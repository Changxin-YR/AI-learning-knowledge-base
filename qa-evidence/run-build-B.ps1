$ErrorActionPreference = 'Continue'
$log = 'C:\Users\27363\Desktop\jianli\flutteer\qa-evidence\ohos-build-B.log'
Set-Content -LiteralPath $log -Value ("START " + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))
& 'C:\Users\27363\Desktop\jianli\flutteer\scripts\build-ohos-local.ps1' -UseDefaultDebugSigning -TargetPlatform ohos-x64 *>&1 | Tee-Object -FilePath $log -Append
Add-Content -LiteralPath $log -Value ("EXITCODE=$LASTEXITCODE " + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))
