param(
    [string]$SigningProfile,
    [switch]$UseDefaultDebugSigning,
    [ValidateSet('debug', 'profile', 'release')]
    [string]$Mode = 'debug',
    [ValidateSet('ohos-arm64', 'ohos-x64')]
    [string]$TargetPlatform = 'ohos-x64',
    [string]$MaterialPrefix,
    [string]$ApiUrl = 'http://10.0.2.2:8001'
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$material = $null
if ($UseDefaultDebugSigning) {
    $localProfilePath = Join-Path $root '.ohos-signing.local.json'
    if (-not (Test-Path -LiteralPath $localProfilePath)) {
        throw "Missing local signing profile: $localProfilePath (copy a DevEco profile here; it is gitignored)."
    }
    $localProfile = Get-Content -Raw $localProfilePath | ConvertFrom-Json
    $material = $localProfile.app.signingConfigs[0].material
    if (-not $material -or -not $material.storeFile -or -not $material.profile -or -not $material.certpath) {
        throw "Local signing profile must contain app.signingConfigs[0].material with storeFile, profile and certpath."
    }
} else {
    if (-not $SigningProfile) { throw 'Specify -SigningProfile or -UseDefaultDebugSigning.' }
    $profile = Get-Content -Raw $SigningProfile | ConvertFrom-Json
    $material = $profile.app.signingConfigs[0].material
    if (-not $material) { throw "No signing material found in $SigningProfile" }
    if ($MaterialPrefix) {
        $material.storeFile = "$MaterialPrefix.p12"
        $material.profile = "$MaterialPrefix.p7b"
        $material.certpath = "$MaterialPrefix.cer"
    }
}

Set-Location (Join-Path $root 'mobile')
Remove-Item 'build\ohos\hap' -Recurse -Force -ErrorAction SilentlyContinue
$buildProfilePath = Join-Path (Get-Location) 'ohos\build-profile.json5'
$originalBuildProfile = Get-Content -Raw $buildProfilePath
$oldOhosSdkHome = $env:OHOS_SDK_HOME
$oldOhosHome = $env:OHOS_HOME
$oldHmosSdkHome = $env:HOS_SDK_HOME
$oldDevecoSdkHome = $env:DEVECO_SDK_HOME
$oldPath = $env:Path
try {
    $devecoSdk = 'C:\Program Files\Huawei\DevEco Studio\sdk'
    $env:OHOS_SDK_HOME = $null
    $env:OHOS_HOME = $null
    $env:HOS_SDK_HOME = $devecoSdk
    $env:DEVECO_SDK_HOME = $devecoSdk
    $devecoToolchains = Join-Path $devecoSdk 'default\openharmony\toolchains'
    $pathEntries = (($oldPath -split ';') | Where-Object { $_ -and ($_ -notmatch 'Desktop\\max\\openharmony-sdk') } | Select-Object -Unique)
    $env:Path = "$devecoToolchains;" + ($pathEntries -join ';')

    $buildProfile = $originalBuildProfile | ConvertFrom-Json
    $buildProfile.app.signingConfigs = @([pscustomobject]@{
        name = 'default'
        type = 'HarmonyOS'
        material = $material
    })
    $buildProfile.app.products[0] | Add-Member -NotePropertyName signingConfig -NotePropertyValue 'default' -Force
    $buildProfile | ConvertTo-Json -Depth 20 | Set-Content -Encoding utf8 $buildProfilePath

    flutter build hap --$Mode --target-platform $TargetPlatform --dart-define=API_BASE_URL=$ApiUrl
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

    $hap = Get-ChildItem -Recurse 'build\ohos\hap' -Filter '*-signed.hap' |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1
    if (-not $hap) { throw 'Signed HAP was not produced.' }
    Write-Output $hap.FullName
}
finally {
    [System.IO.File]::WriteAllText($buildProfilePath, $originalBuildProfile, (New-Object System.Text.UTF8Encoding($false)))
    $env:OHOS_SDK_HOME = $oldOhosSdkHome
    $env:OHOS_HOME = $oldOhosHome
    $env:HOS_SDK_HOME = $oldHmosSdkHome
    $env:DEVECO_SDK_HOME = $oldDevecoSdkHome
    $env:Path = $oldPath
}
