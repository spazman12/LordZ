@echo off
title LordZ - Create Desktop Shortcut
cd /d "%~dp0"

set "PS_EXE=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
if not exist "%PS_EXE%" set "PS_EXE=powershell.exe"

"%PS_EXE%" -NoProfile -ExecutionPolicy Bypass -File "%~dp0\Tools\New-LordZDesktopShortcut.ps1"
pause
