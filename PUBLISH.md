# Publish LordZ to GitHub

Local git is ready (`main` branch, initial commit done). Finish with these steps:

## 1. Log in to GitHub (one time)

```powershell
gh auth login
```

Follow the prompts (browser login is easiest).

## 2. Create the repo and push

```powershell
cd "C:\Users\Moot\Documents\LOrdz"

gh repo create LordZ --public --source=. --remote=origin --push --description "Tired of mod updates forcing dedi restarts? Mirror Steam Workshop mods on your schedule."

Repo URL: https://github.com/spazman12/LordZ
```

Use a different name if `LordZ` is taken on your account.

## 3. Add repository topics (tags)

```powershell
gh repo edit --add-topic deadside --add-topic dedicated-server --add-topic game-server --add-topic steam-workshop --add-topic steamcmd --add-topic workshop-mirror --add-topic modding --add-topic server-admin --add-topic powershell --add-topic windows --add-topic survival-game --add-topic lordz --add-topic workshop-mod --add-topic dedi-hosting
```

## 4. Optional — GitHub Release zip

```powershell
.\Pack-LordZ.ps1
gh release create v1.0.0 "Release\LordZ-*.zip" --title "LordZ v1.0" --notes "First public release. Double-click LordZ - Start Here.bat to run."
```
