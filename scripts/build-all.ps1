$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$mobile = Join-Path $root 'mobile'
$androidOut = Join-Path $root 'artifacts/android'
$ohosOut = Join-Path $root 'artifacts/ohos'
$apiUrl = if ($env:KNOWFLOW_API_URL) { $env:KNOWFLOW_API_URL } else { 'http://10.0.2.2:8001' }

function Assert-NativeSuccess([string]$Step) {
  if ($LASTEXITCODE -ne 0) { throw "$Step failed with exit code $LASTEXITCODE" }
}

New-Item -ItemType Directory -Force -Path $androidOut,$ohosOut | Out-Null
Set-Location $mobile

$apk = Join-Path $mobile 'build/app/outputs/flutter-apk/app-release.apk'
if (Test-Path $apk) { Remove-Item $apk -Force }
flutter build apk --release --dart-define=API_BASE_URL=$apiUrl
Assert-NativeSuccess 'Android release build'
if (-not (Test-Path $apk)) { throw 'Android APK was not produced.' }
Copy-Item $apk (Join-Path $androidOut 'knowflow-ai-release.apk') -Force

if (Test-Path (Join-Path $mobile 'build')) {
  Get-ChildItem -Path (Join-Path $mobile 'build') -Recurse -Filter '*-signed.hap' -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue
}
flutter build hap --release --target-platform ohos-x64 --dart-define=API_BASE_URL=$apiUrl
Assert-NativeSuccess 'HarmonyOS release build'
$hap = Get-ChildItem -Path (Join-Path $mobile 'build') -Recurse -Filter '*-signed.hap' -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1
if (-not $hap) { throw 'Signed HAP was not produced.' }
Copy-Item $hap.FullName (Join-Path $ohosOut 'knowflow-ai-release.hap') -Force

Write-Host 'Android APK and HarmonyOS HAP were rebuilt successfully.'
