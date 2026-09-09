param(
    [string]$ApiUrl = 'http://10.0.2.2:8001',
    [switch]$SkipTests,
    [switch]$BuildOnly
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$mobile = Join-Path $root 'mobile'
$releaseDir = Join-Path $root 'artifacts\releases\v1.1.0'
$version = 'v1.1.0'
$buildName = '1.1.0'
$buildNumber = '2'

function Assert-LastExitCode([string]$Step) {
    if ($LASTEXITCODE -ne 0) {
        throw "$Step failed with exit code $LASTEXITCODE"
    }
}

function Assert-Command([string]$Name) {
    if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
        throw "Required command '$Name' is not available."
    }
}

Set-Location $root
Assert-Command git
Assert-Command flutter

$branch = (git branch --show-current).Trim()
Assert-LastExitCode 'git branch --show-current'
if ($branch -ne 'main') {
    throw "Release must run from main; current branch is '$branch'."
}

if (git status --porcelain) {
    throw 'Working tree must be clean before release.'
}

git fetch origin
Assert-LastExitCode 'git fetch origin'
$localSha = (git rev-parse HEAD).Trim()
$remoteSha = (git rev-parse origin/main).Trim()
if ($localSha -ne $remoteSha) {
    throw "Local main ($localSha) must exactly match origin/main ($remoteSha)."
}

$trackedSensitive = git ls-files | Where-Object {
    $_ -match '(^|/)(\.env|\.ohos-signing\.local\.json)$' -or
    $_ -match '\.(p12|p7b|cer|jks|keystore|pem|key)$'
}
if ($trackedSensitive) {
    throw "Sensitive release material is tracked by Git: $($trackedSensitive -join ', ')"
}

# Lightweight tracked-content scan. Exit code 1 from git grep means no matches.
$secretPattern = '(-----BEGIN (RSA |OPENSSH |EC )?PRIVATE KEY-----|sk-[A-Za-z0-9_-]{20,}|ghp_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,})'
$secretMatches = git grep -n -I -E $secretPattern -- . 2>$null
$secretScanExit = $LASTEXITCODE
if ($secretScanExit -eq 0) {
    throw "Potential secret material found in tracked files:`n$($secretMatches -join [Environment]::NewLine)"
}
if ($secretScanExit -ne 1) {
    throw "Tracked secret scan failed with exit code $secretScanExit"
}
Write-Host 'Tracked secret scan: PASS' -ForegroundColor Green

if (-not $SkipTests) {
    & (Join-Path $root 'scripts\test-all.ps1')
    Assert-LastExitCode 'scripts/test-all.ps1'
}

if (-not (Test-Path (Join-Path $root '.ohos-signing.local.json'))) {
    throw 'HarmonyOS engineering signing profile .ohos-signing.local.json is required and must remain gitignored.'
}

Remove-Item $releaseDir -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force -Path $releaseDir | Out-Null

# Android engineering release APK.
Set-Location $mobile
flutter pub get
Assert-LastExitCode 'flutter pub get'
flutter build apk --release --build-name $buildName --build-number $buildNumber --dart-define="API_BASE_URL=$ApiUrl"
Assert-LastExitCode 'flutter build apk'
$androidSource = Join-Path $mobile 'build\app\outputs\flutter-apk\app-release.apk'
if (-not (Test-Path $androidSource)) { throw 'Android APK was not produced.' }
$androidTarget = Join-Path $releaseDir 'KnowFlow-AI-v1.1.0-Android.apk'
Copy-Item $androidSource $androidTarget -Force

# HarmonyOS x64 engineering release HAP.
Set-Location $root
$x64Output = & (Join-Path $root 'scripts\build-ohos-local.ps1') -UseDefaultDebugSigning -Mode release -TargetPlatform ohos-x64 -ApiUrl $ApiUrl
Assert-LastExitCode 'HarmonyOS x64 build'
$x64Source = $x64Output | Where-Object { $_ -and (Test-Path $_) } | Select-Object -Last 1
if (-not $x64Source) { throw 'HarmonyOS x64 signed HAP was not produced.' }
$x64Target = Join-Path $releaseDir 'KnowFlow-AI-v1.1.0-HarmonyOS-x64.hap'
Copy-Item $x64Source $x64Target -Force

# HarmonyOS ARM64 engineering release HAP.
$arm64Output = & (Join-Path $root 'scripts\build-ohos-local.ps1') -UseDefaultDebugSigning -Mode release -TargetPlatform ohos-arm64 -ApiUrl $ApiUrl
Assert-LastExitCode 'HarmonyOS ARM64 build'
$arm64Source = $arm64Output | Where-Object { $_ -and (Test-Path $_) } | Select-Object -Last 1
if (-not $arm64Source) { throw 'HarmonyOS ARM64 signed HAP was not produced.' }
$arm64Target = Join-Path $releaseDir 'KnowFlow-AI-v1.1.0-HarmonyOS-arm64.hap'
Copy-Item $arm64Source $arm64Target -Force

$artifacts = @($androidTarget, $x64Target, $arm64Target)
$hashLines = foreach ($artifact in $artifacts) {
    $hash = (Get-FileHash -Algorithm SHA256 $artifact).Hash.ToUpperInvariant()
    "$hash  $([System.IO.Path]::GetFileName($artifact))"
}
$shaFile = Join-Path $releaseDir 'SHA256SUMS.txt'
[System.IO.File]::WriteAllLines($shaFile, $hashLines, [System.Text.UTF8Encoding]::new($false))

$metadata = @{
    version = $version
    commit = $localSha
    created_at = [DateTimeOffset]::UtcNow.ToString('o')
    api_url = $ApiUrl
    secret_scan = 'PASS'
    signing = @{
        android = 'engineering/local release signing'
        harmonyos = 'engineering/local debug profile'
    }
    artifacts = foreach ($artifact in $artifacts) {
        @{
            name = [System.IO.Path]::GetFileName($artifact)
            size = (Get-Item $artifact).Length
            sha256 = (Get-FileHash -Algorithm SHA256 $artifact).Hash.ToUpperInvariant()
        }
    }
}
$metadata | ConvertTo-Json -Depth 8 | Set-Content -Encoding utf8 (Join-Path $releaseDir 'release-metadata.json')

Write-Host ''
Write-Host 'Release build completed:' -ForegroundColor Green
Get-Content $shaFile
Write-Host "Artifacts: $releaseDir"

if ($BuildOnly) {
    Write-Host 'BuildOnly requested; tag and GitHub Release were not created.' -ForegroundColor Yellow
    exit 0
}

Assert-Command gh
$ghStatus = gh auth status 2>&1
if ($LASTEXITCODE -ne 0) {
    throw "GitHub CLI is not authenticated. Run 'gh auth login' first."
}

if (git tag --list $version) {
    throw "Tag $version already exists. Refusing to move or overwrite a release tag."
}

# Re-check the tree immediately before tagging so release outputs cannot be accidentally tracked.
if (git status --porcelain) {
    throw 'Working tree changed during release build. Release artifacts must remain gitignored before tagging.'
}

git tag -a $version -m 'KnowFlow AI v1.1.0'
Assert-LastExitCode 'git tag'
git push origin $version
Assert-LastExitCode 'git push tag'

$notesFile = Join-Path $root 'docs\V1.1.0_RELEASE_NOTES.md'
gh release create $version `
    $androidTarget `
    $x64Target `
    $arm64Target `
    $shaFile `
    (Join-Path $releaseDir 'release-metadata.json') `
    --title 'KnowFlow AI v1.1.0' `
    --notes-file $notesFile `
    --verify-tag
Assert-LastExitCode 'gh release create'

gh release view $version --json tagName,name,isDraft,isPrerelease,url
Assert-LastExitCode 'gh release view'
