$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
Set-Location (Join-Path $root 'server'); python -m pytest -q
Set-Location (Join-Path $root 'mobile'); flutter analyze; flutter test
