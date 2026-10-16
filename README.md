# Adundas Board

A guild leveling race board for **Adundas** on WoW: Forever. Shows every
guild member's level, class, zone and online status, and lets anyone who
runs the addon share live XP progress and level-up announcements with the
rest of the guild.

## Install

Download the latest release zip from the
[Releases page](https://github.com/Borgund/adundas-board/releases) and
unzip the `AdundasBoard` folder into:

```
World of Warcraft/_classic_beta_/Interface/AddOns/
```

If you'd rather track updates automatically, most addon managers (WowUp,
for example) can watch this GitHub repo directly.

## Developing

Clone the repo and symlink it into your AddOns folder so edits show up
after a `/reload`:

```sh
# macOS
ln -s ~/path/to/adundas-board "/Applications/World of Warcraft/_classic_beta_/Interface/AddOns/AdundasBoard"
```

```powershell
# Windows (PowerShell as admin)
New-Item -ItemType SymbolicLink `
  -Path "C:\Program Files (x86)\World of Warcraft\_classic_beta_\Interface\AddOns\AdundasBoard" `
  -Target "C:\path\to\adundas-board"
```

Smoke test outside the game (loads the real Lua files into a Lua 5.1
interpreter with a fake WoW API):

```sh
pip install lupa
python tests/harness.py
```

## In game

`/ab` toggles the board, `/ab options` opens settings, `/ab refresh`
re-reads the guild roster, `/ab reset` clears all saved board data.

## Releasing

Push a tag such as `v0.1.0`. GitHub Actions builds the zip, creates a
release, and uploads to CurseForge/Wago if their API token secrets and the
matching `## X-Curse-Project-ID` / `## X-Wago-ID` TOC lines exist.
