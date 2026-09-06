$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
Set-Location (Join-Path $root 'server')
@{
  message = 'Use POST /api/v1/auth/demo to create the repeatable demo account.'
  email = 'demo@knowflow.local'
  password = 'KnowFlowDemo123!'
} | ConvertTo-Json
