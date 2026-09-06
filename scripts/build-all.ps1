$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$mobile = Join-Path $root 'mobile'
$androidOut = Join-Path $root 'artifacts/android'
$ohosOut = Join-Path $root 'artifacts/ohos'
New-Item -ItemType Directory -Force -Path $androidOut,$ohosOut | Out-Null
Set-Location $mobile
flutter build apk --release --dart-define=API_BASE_URL=$env:KNOWFLOW_API_URL
Copy-Item build/app/outputs/flutter-apk/app-release.apk (Join-Path $androidOut 'knowflow-ai-release.apk') -Force
flutter build hap --release --dart-define=API_BASE_URL=$env:KNOWFLOW_API_URL
$hap = Get-ChildItem -Recurse build -Filter '*.hap' | Select-Object -First 1
if ($hap) { Copy-Item $hap.FullName (Join-Path $ohosOut 'knowflow-ai-release.hap') -Force } else { throw 'HAP was not produced.' }
