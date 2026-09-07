$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$envFile = Join-Path $root '.env'

if (Test-Path $envFile) {
  Get-Content $envFile | ForEach-Object {
    $line = $_.Trim()
    if ($line -and -not $line.StartsWith('#') -and $line.Contains('=')) {
      $parts = $line.Split('=', 2)
      $name = $parts[0].Trim()
      $value = $parts[1].Trim()
      if ($name -and -not [Environment]::GetEnvironmentVariable($name, 'Process')) {
        [Environment]::SetEnvironmentVariable($name, $value, 'Process')
      }
    }
  }
}

Set-Location (Join-Path $root 'server')
if (-not (Test-Path (Join-Path $root '.venv'))) { Write-Host 'Using system Python; install server/requirements.txt if imports fail.' }
$port = if ($env:KNOWFLOW_PORT) { $env:KNOWFLOW_PORT } else { '8001' }
python -m uvicorn app.main:app --host 0.0.0.0 --port $port
if ($LASTEXITCODE -ne 0) { throw "Backend exited with code $LASTEXITCODE" }
