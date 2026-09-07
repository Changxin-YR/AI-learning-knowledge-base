$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$envFile = Join-Path $root '.env'
if (Test-Path $envFile) {
    Get-Content $envFile | ForEach-Object {
        if ($_ -match '^\s*([^#=\s]+)\s*=\s*(.*)\s*$') {
            $name = $matches[1]
            $value = $matches[2].Trim().Trim('"').Trim("'")
            Set-Item -Path "Env:$name" -Value $value
        }
    }
}
Set-Location (Join-Path $root 'server')
if (-not (Test-Path (Join-Path $root '.venv'))) { Write-Host 'Using system Python; install server/requirements.txt if imports fail.' }
$port = if ($env:KNOWFLOW_PORT) { $env:KNOWFLOW_PORT } else { '8001' }
python -m uvicorn app.main:app --host 0.0.0.0 --port $port
