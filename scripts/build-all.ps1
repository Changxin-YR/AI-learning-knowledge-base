$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$mobile = Join-Path $root 'mobile'
$androidOut = Join-Path $root 'artifacts/android'
$ohosOut = Join-Path $root 'artifacts/ohos'
$apiUrl = if ($env:KNOWFLOW_API_URL) { $env:KNOWFLOW_API_URL } else { 'http://10.0.2.2:8001' }
New-Item -ItemType Directory -Force -Path $androidOut,$ohosOut | Out-Null
Set-Location $mobile
flutter build apk --release --dart-define=API_BASE_URL=$apiUrl
Copy-Item build/app/outputs/flutter-apk/app-release.apk (Join-Path $androidOut 'knowflow-ai-release.apk') -Force
flutter build hap --release --target-platform ohos-x64 --dart-define=API_BASE_URL=$apiUrl
$hap = Get-ChildItem -Recurse build -Filter '*-signed.hap' | Select-Object -First 1
if ($hap) { Copy-Item $hap.FullName (Join-Path $ohosOut 'knowflow-ai-release.hap') -Force } else { throw 'HAP was not produced.' }
