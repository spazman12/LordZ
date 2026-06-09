@echo off
setlocal
cd /d "%~dp0"
if not exist "backend\steam-qr-server\node_modules" (
  echo Installing backend dependencies...
  pushd backend\steam-qr-server
  call npm install
  if errorlevel 1 exit /b 1
  popd
)
start "LordZ Steam Backend" /MIN cmd /c "%~dp0Start-LordZ-QrBackend.bat"
echo Waiting for backend...
timeout /t 4 /nobreak >nul
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Tools\Invoke-LordZSteamLoginUntilSuccess.ps1" %*
pause
