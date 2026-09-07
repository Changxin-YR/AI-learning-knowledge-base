$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot

function Assert-NativeSuccess([string]$Step) {
  if ($LASTEXITCODE -ne 0) { throw "$Step failed with exit code $LASTEXITCODE" }
}

Set-Location (Join-Path $root 'server')
python -m pytest -q
Assert-NativeSuccess 'Backend pytest'

Set-Location (Join-Path $root 'mobile')
flutter analyze
Assert-NativeSuccess 'Flutter analyze'
flutter test
Assert-NativeSuccess 'Flutter test'

Write-Host 'All automated checks passed.'
