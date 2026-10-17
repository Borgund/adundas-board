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

### Updating automatically (WowUp)

This addon isn't listed on CurseForge or Wago, but
[WowUp](https://wowup.io) can track a GitHub repository directly and
notify you of updates the same way it does for listed addons:

1. Open WowUp and go to **Get Addons**.
2. Click **Install from URL**.
3. Paste `https://github.com/Borgund/adundas-board` and confirm.

WowUp finds the latest tagged release's zip automatically from there, so
future updates show up the normal way. This relies on every release being
a proper tagged GitHub release with a packaged zip attached, which is
exactly what pushing a `v*` tag here already produces.

The CurseForge app doesn't support this (it only installs from its own
listings), so CurseForge-app users need to grab the zip manually for now.

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

Push a [SemVer](https://semver.org) tag such as `v0.1.0` or
`v0.1.0-beta.1`. GitHub Actions builds the zip, creates a release, and
uploads to CurseForge/Wago if their API token secrets and the matching
`## X-Curse-Project-ID` / `## X-Wago-ID` TOC lines exist (neither is
currently configured; see the main dev repo's `CLAUDE.md` for how this
repo gets published from there).
