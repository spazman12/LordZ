# LordZ — Workshop Mirror Engine

**Tired of mod updates forcing you to restart your dedicated server? LordZ is the tool for you.**

LordZ is a Windows GUI that mirrors Steam Workshop mods to **your own** Workshop copies. You control when updates land on your server — no more surprise restarts because a mod author pushed a patch at 3 AM.

Built for **Deadside** dedicated server hosts (`App ID 895400`), with a workflow designed around real dedi pain: queue mods, generate SteamCMD scripts, run mirrors in one login session, and keep your server on stable copies until *you* decide to sync.

---

## Why use LordZ?

| Problem | How LordZ helps |
|--------|------------------|
| Workshop mod updated → server must restart | Mirror the mod once; your server uses **your** copy until you re-mirror |
| Juggling SteamCMD commands by hand | GUI queue + one-click **Generate Script** / **Run Script** |
| Steam login bans from bad scripting | Single-session login — password entered once in PowerShell, not stored in files |
| New hosts don't know SteamCMD | **Download & Install SteamCMD** built in (Valve CDN) |
| Mod ID typos / dead mods | Live **Steam API validation** before you waste a mirror run |

---

## Features

### Core mirroring
- **Mirror Queue** — add multiple source mod IDs, set mirror name and visibility (Public / Friends / Private)
- **Auto-fill mirror names** from Steam Workshop metadata
- **Mirror ID** support (`0` = create new mirror, or target an existing published file)
- **Generate Script** — builds SteamCMD batch + PowerShell runner under `Generated\`
- **Run Script** — opens external PowerShell with Lord Zolton banner; prompts for Steam password securely
- **Copy Script** — copy the runner to clipboard for manual use
- **Single-session Steam auth** — one `login` prepended to the batch at runtime (reduces repeat-login risk)

### SteamCMD integration
- **One-click SteamCMD install** to `.\steamcmd\` beside the app
- **In-app Steam console** — type commands when SteamCMD asks (login, Steam Guard codes)
- **App ID verify** — checks game via Steam Store API (Deadside `895400` pre-filled)
- **Mod availability check** — validates workshop items before generation

### User experience
- **LordZ - Start Here.bat** — double-click launcher, no install wizard
- **First-run Quick Start** popup with step-by-step guide
- **Settings auto-save** to `lordz.settings.json`
- **Operation log** with ASCII banner and live status
- **Create Desktop Shortcut.bat** for one-click access
- **Pack-LordZ.ps1** — build a clean distributable zip for sharing

### Discord support (optional)
- **Quick Request** — send help messages via webhook
- **Live Help Chat** — two-way relay to a private Discord thread (bot token required)
- **Join Discord** button when invite URL is configured
- Configure via `lordz.discord.example.json` → `lordz.discord.json`

### Developer / debug (optional)
- `Start-LordZ-Debug.bat` — visible console on startup failures
- QR Steam login backend under `backend\` (advanced; not required for normal use)

---

## Quick start

1. **Download** — clone this repo or grab a release zip from `Release\` (run `.\Pack-LordZ.ps1` to build one)
2. **Launch** — double-click **`LordZ - Start Here.bat`**
3. **Setup** (one time):
   - Click **Download & Install SteamCMD**
   - Enter your **Steam username**
   - Click **Verify** on App ID `895400` (Deadside)
4. **Mirror**:
   - Add **Source Mod ID(s)** to the queue
   - Click **Generate Script**
   - Click **Run Script** → enter Steam password in the PowerShell window
   - Approve **Steam Guard** on your phone when prompted

Plain-text instructions also live in [`README.txt`](README.txt).

---

## Requirements

- Windows 10 or 11
- PowerShell 5.1 (included with Windows)
- Steam account that owns **Deadside**
- Internet connection

---

## Project layout

```
LordZ/
├── LordZ - Start Here.bat    # Main launcher
├── LordZ-MirrorEngine.ps1    # GUI application
├── Modules/                    # Core PowerShell modules
├── Assets/                     # Banner and static assets
├── Generated/                  # Output scripts (created at runtime)
├── steamcmd/                   # SteamCMD (installed by the app)
├── lordz.settings.json         # Your settings (gitignored)
├── Pack-LordZ.ps1              # Build distributable zip
└── README.md                   # You are here
```

---

## Disclaimer

You must obtain permission from the original mod author before mirroring Workshop content. **Any legal liability arising from such use rests solely with you.**

LordZ is a community server-admin tool, not affiliated with Valve, Deadside, or any mod author.

---

## Topics / tags

When publishing on GitHub, add these **repository topics**:

`deadside` `dedicated-server` `game-server` `steam-workshop` `steamcmd` `workshop-mirror` `modding` `server-admin` `powershell` `windows` `survival-game` `lordz` `workshop-mod` `dedi-hosting`

---

## License

Use at your own risk. See disclaimer above.
