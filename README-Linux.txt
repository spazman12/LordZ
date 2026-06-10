================================================================================
  LORDZ - Linux / macOS (CLI)
================================================================================

The Windows GUI does not run on Linux. Use the LordZ terminal CLI instead.
Same mirror engine, same Discord support, same SteamCMD workflow.

REQUIREMENTS
------------
  - Linux (Ubuntu/Debian recommended) or macOS
  - PowerShell 7+ (pwsh)
  - CA certificates + curl (required for Discord live chat):
      sudo apt-get install -y ca-certificates curl
      sudo update-ca-certificates
  - 32-bit libraries for SteamCMD on Linux:
      sudo apt-get install -y lib32gcc-s1 lib32stdc++6 libc6-i386 tar
  - Steam account that owns the game

INSTALL
-------
  1. Download LordZ-linux-*.zip from GitHub Releases
  2. unzip LordZ-linux-*.zip -d ~/LordZ
  3. cd ~/LordZ
  4. sed -i 's/\r$//' lordz.sh
  5. chmod +x lordz.sh
  6. ./lordz.sh

  If you see: env: 'bash\r': No such file or directory
  run step 4 (fixes Windows line endings in the script).

FIRST-TIME SETUP
----------------
  Menu option 1  - Install SteamCMD
  Menu option 2  - Set Steam username and App ID (895400 = Deadside)
  Menu option 3  - Verify App ID
  Menu option 4  - Add workshop mod IDs to queue
  Menu option 7  - Generate mirror script
  Menu option 8  - Run script (enter Steam password + Steam Guard)

DISCORD HELP
------------
  Option 9  - Quick Request (webhook)
  Option 10 - Live Help Chat (if bundled lordz.discord.json is present)

  If live chat says "SSL connection could not be established":
      sudo apt-get install -y ca-certificates curl
      sudo update-ca-certificates
      ./lordz.sh

DISCLAIMER
----------
  You must obtain permission from the original mod author before mirroring
  Workshop content. Any legal liability arising from such use rests solely
  with you.

================================================================================
