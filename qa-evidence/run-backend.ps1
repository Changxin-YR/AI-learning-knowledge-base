Set-Location 'C:\Users\27363\Desktop\jianli\flutteer\server'
$env:DEMO_AI_MODE = '1'
& 'D:\python\python.exe' -m uvicorn app.runtime:app --host 0.0.0.0 --port 8001 *> 'C:\Users\27363\Desktop\jianli\flutteer\qa-evidence\backend.log'
