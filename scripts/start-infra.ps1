$ErrorActionPreference = 'Stop'
Set-Location (Split-Path -Parent $PSScriptRoot)
docker compose up -d
if ($LASTEXITCODE -ne 0) { throw 'Docker Compose failed. Ensure Docker Desktop is running.' }
