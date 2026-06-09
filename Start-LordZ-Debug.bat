@echo off
setlocal
set "PS_EXE=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
if not exist "%PS_EXE%" set "PS_EXE=powershell.exe"

REM Visible console — shows PowerShell errors if the app fails to start
"%PS_EXE%" -NoProfile -STA -ExecutionPolicy Bypass -File "%~dp0LordZ-MirrorEngine.ps1"
pause
