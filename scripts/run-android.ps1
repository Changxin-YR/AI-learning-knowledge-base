$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
Set-Location (Join-Path $root 'mobile')
flutter run -d android --dart-define=API_BASE_URL=$env:KNOWFLOW_API_URL
