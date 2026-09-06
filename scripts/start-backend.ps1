$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
Set-Location (Join-Path $root 'server')
if (-not (Test-Path (Join-Path $root '.venv'))) { Write-Host 'Using system Python; install server/requirements.txt if imports fail.' }
$port = if ($env:KNOWFLOW_PORT) { $env:KNOWFLOW_PORT } else { '8001' }
python -m uvicorn app.main:app --host 0.0.0.0 --port $port
