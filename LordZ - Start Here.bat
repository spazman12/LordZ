@echo off
title LordZ Workshop Mirror
cd /d "%~dp0"

set "PS_EXE=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
if not exist "%PS_EXE%" set "PS_EXE=powershell.exe"

REM Opens the LordZ GUI (no extra console window)
start "" "%PS_EXE%" -NoProfile -STA -ExecutionPolicy Bypass -WindowStyle Hidden -File "%~dp0LordZ-MirrorEngine.ps1"
