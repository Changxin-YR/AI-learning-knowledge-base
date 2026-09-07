$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
Set-Location (Join-Path $root 'mobile')
$apiUrl = if ($env:KNOWFLOW_API_URL) { $env:KNOWFLOW_API_URL } else { 'http://10.0.2.2:8001' }
flutter run -d ohos --dart-define=API_BASE_URL=$apiUrl
