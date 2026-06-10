#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"

if command -v pwsh >/dev/null 2>&1; then
  exec pwsh -NoProfile -File "$ROOT/LordZ-MirrorCli.ps1" "$@"
fi

if command -v powershell >/dev/null 2>&1; then
  exec powershell -NoProfile -File "$ROOT/LordZ-MirrorCli.ps1" "$@"
fi

echo "[!] PowerShell is required."
echo "    Install: https://learn.microsoft.com/en-us/powershell/scripting/install/installing-powershell-on-linux"
echo "    Ubuntu/Debian: sudo apt-get install -y powershell"
exit 1
