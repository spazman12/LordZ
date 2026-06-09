@echo off
setlocal
cd /d "%~dp0backend\steam-qr-server"
if not exist node_modules (
  echo Installing steam-qr-server dependencies...
  call npm install
  if errorlevel 1 exit /b 1
)
echo Starting LordZ Steam QR backend on http://127.0.0.1:8765
node server.js
