#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"

if [[ ! -f "$ROOT/Modules/LordZ.Core.psm1" ]]; then
  echo "[!] Incomplete LordZ folder."
  echo "    Extract the full LordZ-linux zip into one folder, cd there, then run:"
  echo "    bash start-lordz.sh"
  echo "    Missing: $ROOT/Modules/LordZ.Core.psm1"
  exit 1
fi

if [[ -d /etc/ssl/certs ]]; then
  export SSL_CERT_DIR="${SSL_CERT_DIR:-/etc/ssl/certs}"
fi
if [[ -f /etc/ssl/certs/ca-certificates.crt ]]; then
  export SSL_CERT_FILE="${SSL_CERT_FILE:-/etc/ssl/certs/ca-certificates.crt}"
fi

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
