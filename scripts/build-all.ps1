$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$mobile = Join-Path $root 'mobile'
$androidOut = Join-Path $root 'artifacts/android'
$ohosOut = Join-Path $root 'artifacts/ohos'
$apiUrl = if ($env:KNOWFLOW_API_URL) { $env:KNOWFLOW_API_URL } else { 'http://10.0.2.2:8001' }
New-Item -ItemType Directory -Force -Path $androidOut,$ohosOut | Out-Null
$apk = Join-Path $androidOut 'knowflow-ai-release.apk'
$hapOut = Join-Path $ohosOut 'knowflow-ai-release.hap'
Remove-Item $apk,$hapOut -Force -ErrorAction SilentlyContinue
Set-Location $mobile
flutter build apk --release --dart-define=API_BASE_URL=$apiUrl
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
$apkBuild = Join-Path $mobile 'build/app/outputs/flutter-apk/app-release.apk'
if (-not (Test-Path $apkBuild)) { throw 'APK was not produced.' }
Copy-Item $apkBuild $apk -Force
Remove-Item (Join-Path $mobile 'build/ohos/hap') -Recurse -Force -ErrorAction SilentlyContinue
$ohosBuilder = Join-Path $root 'scripts/build-ohos-local.ps1'
& $ohosBuilder -UseDefaultDebugSigning -Mode release -TargetPlatform ohos-x64 -ApiUrl $apiUrl
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
$hap = Get-ChildItem -Recurse (Join-Path $mobile 'build/ohos/hap') -Filter '*-signed.hap' | Sort-Object LastWriteTime -Descending | Select-Object -First 1
if ($hap) { Copy-Item $hap.FullName $hapOut -Force } else { throw 'HAP was not produced.' }
