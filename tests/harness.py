"""Smoke test for Adundas Board outside the game.

Loads the addon's Lua files into a real Lua 5.1 interpreter with a tiny fake
WoW API, fires the events a login would fire, and checks the saved data.
It catches syntax errors, typos in names and logic slips; it does NOT prove
the addon works in the real client.

    pip install lupa
    python addon/tests/harness.py
"""
import pathlib
import sys

from lupa import lua51

ROOT = pathlib.Path(__file__).resolve().parents[1] / "AdundasBoard"
lua = lua51.LuaRuntime(unpack_returned_tuples=True)

STUBS = r"""
local events, timers, sent = {}, {}, {}
_G.__sent, _G.__timers, _G.__prints = sent, timers, {}
local now = 1000

function print(...) local t = {...}; for i=1,#t do t[i]=tostring(t[i]) end; table.insert(__prints, table.concat(t, " ")) end
function GetTime() return now end
function time() return 1792170000 + now end
function format(...) return string.format(...) end
function strtrim(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
function wipe(t) for k in pairs(t) do t[k] = nil end return t end
tinsert = table.insert
UISpecialFrames = {}
SlashCmdList = {}
SOUNDKIT = { UI_QUEST_ROLLING_FORWARD_01 = 43936 }
function PlaySound() end
RAID_CLASS_COLORS = { PRIEST = { r = 1, g = 1, b = 1 } }
Enum = { SendAddonMessageResult = { Success = 0, AddOnMessageLockdown = 11 } }

local function newRegion()
  local r = {}
  setmetatable(r, { __index = function(t, k)
    return function(self, ...) return nil end
  end })
  return r
end
Minimap = newRegion()
function CreateFrame(kind, name)
  local f = newRegion()
  f.scripts = {}
  f.Text, f.TitleText, f.Instructions = newRegion(), newRegion(), newRegion()
  f.RegisterEvent = function(self, e) events[e] = events[e] or {}; table.insert(events[e], self) end
  f.SetScript = function(self, s, fn) self.scripts[s] = fn end
  f.CreateFontString = function() return newRegion() end
  f.CreateTexture = function() return newRegion() end
  f.CreateAnimationGroup = function()
    local ag = newRegion()
    ag.CreateAnimation = function() return newRegion() end
    return ag
  end
  f.IsShown = function(self) return self.shown end
  f.SetShown = function(self, v) self.shown = v; if v and self.scripts.OnShow then self.scripts.OnShow(self) end end
  f.GetChecked = function() return true end
  if name then _G[name] = f end
  return f
end
function __fire(e, ...)
  for _, f in ipairs(events[e] or {}) do f.scripts.OnEvent(f, e, ...) end
end
function __runTimers()
  local list = {}; for i, t in ipairs(timers) do list[i] = t end
  wipe(timers)
  for _, fn in ipairs(list) do fn() end
end

C_Timer = { After = function(_, fn) table.insert(timers, fn) end, NewTicker = function() end }
C_AddOns = { GetAddOnMetadata = function() return "1.0.0-test" end }
C_GuildInfo = { GuildRoster = function() __rosterRequested = true end }
C_EncodingUtil = {
  SerializeJSON = function(v)
    local parts = {}
    for k, val in pairs(v) do
      local s = type(val) == "string" and ('"' .. val .. '"') or tostring(val)
      table.insert(parts, '"' .. k .. '":' .. s)
    end
    return "{" .. table.concat(parts, ",") .. "}"
  end,
  DeserializeJSON = function(s) return __lastDecoded end,
}
__lockdown = false
C_ChatInfo = {
  RegisterAddonMessagePrefix = function(p) __prefix = p end,
  InChatMessagingLockdown = function() return __lockdown end,
  SendAddonMessage = function(prefix, text, chan) table.insert(sent, { prefix = prefix, text = text, chan = chan }); return 0 end,
}
Settings = {
  RegisterCanvasLayoutCategory = function() return { GetID = function() return 1 end } end,
  RegisterAddOnCategory = function() end,
  OpenToCategory = function() end,
}
function IsInGuild() return true end
__guildName = "Adundas"
function GetGuildInfo() return __guildName end
function GetNormalizedRealmName() return "Forever" end
function UnitName() return "Adrian Borg" end
function UnitLevel() return __myLevel or 14 end
function UnitXP() return 4200 end
function UnitXPMax() return 9800 end
function Ambiguate(n) return (n:gsub("%-.*$", "")) end
function FauxScrollFrame_GetOffset() return 0 end
function FauxScrollFrame_Update() end
function FauxScrollFrame_OnVerticalScroll() end
__roster = {
  { "Adrian Borg-Forever", "Officer", 1, 14, "Priest", "Tirisfal Glades", "", "", true, 0, "PRIEST" },
  { "Grumpy-Forever", "Member", 3, 9, "Warrior", "Durotar", "", "", false, 0, "WARRIOR" },
}
function GetNumGuildMembers() return #__roster, 1 end
function GetGuildRosterInfo(i) return unpack(__roster[i]) end
"""

failures = []


def check(cond, msg):
    print(("PASS " if cond else "FAIL ") + msg)
    if not cond:
        failures.append(msg)


lua.execute(STUBS)
ns = lua.table()
toc = (ROOT / "AdundasBoard.toc").read_text().splitlines()
files = [l.strip() for l in toc if l.strip().endswith(".lua")]
for name in files:
    chunk = lua.eval("loadstring")((ROOT / name).read_text(), "@" + name)
    if chunk is None:
        sys.exit(f"syntax error in {name}")
    chunk("AdundasBoard", ns)
check(True, f"loaded {len(files)} files")

g = lua.globals()
REAL_GUILD = "Test Guild"  # whatever the fake GetGuildInfo stub reports
g.__guildName = REAL_GUILD
g.__fire("ADDON_LOADED", "AdundasBoard")
check(g.AdundasBoardDB is not None, "ADDON_LOADED creates AdundasBoardDB")
check(g.__prefix == "AdundasBoard", "registers the addon message prefix")
db = g.AdundasBoardDB
check(db.settings.guildName is None, "guildName starts unset, no hardcoded default")

# Simulate a returning player: this device already saved data for this guild
# from a previous session, including Grumpy at a lower level than the live
# roster now reports (he leveled up while we were offline). Pre-setting
# db.guild to the guild ScanRoster is about to see skips the "first run for
# this guild, start clean" wipe, so this seed survives into the scan below -
# the only way to exercise the catch-up path, which only ever fires on the
# first scan of a session.
db.guild = REAL_GUILD
db.members["Grumpy-Forever"] = lua.table(name="Grumpy-Forever", level=5)
db.members["Grumpy-Forever"]["class"] = "WARRIOR"

g.__fire("PLAYER_ENTERING_WORLD", True, False)
g.__runTimers()
check(g.__rosterRequested is True, "requests the guild roster after login")
check(len(g.__sent) == 1 and g.__sent[1].chan == "GUILD", "sends a hello on the GUILD channel")

g.__fire("GUILD_ROSTER_UPDATE", True)
check(db.settings.guildName == REAL_GUILD, "auto-adopts the first guild it ever sees")
check(db.guild == REAL_GUILD, "stores the guild name")
check(db.members["Grumpy-Forever"].level == 9, "reads roster levels")
check(db.members["Adrian Borg-Forever"] is not None, "keeps names with spaces intact")
check(
    any("Grumpy reached new levels while you were away" in p for p in g.__prints.values()),
    "summarizes a catch-up level-up instead of announcing it immediately",
)
check(
    not any("Grumpy reached level 9" in p for p in g.__prints.values()),
    "catch-up level-up skips the normal per-member announce line",
)

# Grumpy dings 10 according to the roster.
g.__roster[2][4] = 10
g.__fire("GUILD_ROSTER_UPDATE", True)
check(any("Grumpy reached level 10" in p for p in g.__prints.values()), "announces a roster level-up")
check(ns.HasUnseenMilestones() is True, "flags an unseen milestone for the minimap badge")
ns.MarkMilestonesSeen()
check(ns.HasUnseenMilestones() is False, "clears the flag once the milestones tab is opened")

# The Race tab's records: a threshold ding credits both the overall and
# per-class buckets, first-wins.
check(db.records.overall[10].name == "Grumpy-Forever", "credits the overall race record for a threshold ding")
check(db.records.byClass.WARRIOR[10].name == "Grumpy-Forever", "credits the per-class race record too")

# A scan that jumps straight from 10 to 25 (missed polling the climb through
# 20) should still credit level 20, not just levels actually observed.
g.__roster[2][4] = 25
g.__fire("GUILD_ROSTER_UPDATE", True)
check(db.records.overall[20].name == "Grumpy-Forever", "credits a threshold skipped over mid-scan")
check(db.records.byClass.WARRIOR[20].name == "Grumpy-Forever", "...same for the per-class record")
g.__roster[2][4] = 10  # reset: later checks in this file assume Grumpy is still level 10
g.__fire("GUILD_ROSTER_UPDATE", True)

# A roster scan from a different guild (an alt, say) must never touch our data.
g.__guildName = "Rivals"
g.__roster[2][4] = 50
g.__fire("GUILD_ROSTER_UPDATE", True)
check(db.members["Grumpy-Forever"].level == 10, "ignores a roster scan from a different guild")
check(db.guild == REAL_GUILD, "keeps the recorded guild name when the current guild changes")
g.__guildName = REAL_GUILD
g.__roster[2][4] = 10

# An addon message from another member.
decoded = lua.table(p=1, k="l", v="1.0.0", l=11, x=50, m=8000)
g.__lastDecoded = decoded
g.__fire("CHAT_MSG_ADDON", "AdundasBoard", "{}", "GUILD", "Grumpy-Forever")
gm = db.members["Grumpy-Forever"]
check(gm.level == 11 and gm.hasAddon is True and gm.xp == 50, "applies a valid addon message")

g.__lastDecoded = lua.table(p=1, k="l", l=99)
g.__fire("CHAT_MSG_ADDON", "AdundasBoard", "{}", "GUILD", "Grumpy-Forever")
check(db.members["Grumpy-Forever"].level == 11, "rejects an out-of-range level")

# Grumpy turns off "share my XP"; a status update with no xp fields must not
# erase the xp we already knew about.
g.__lastDecoded = lua.table(p=1, k="s", v="1.0.0", l=11)
g.__fire("CHAT_MSG_ADDON", "AdundasBoard", "{}", "GUILD", "Grumpy-Forever")
gm = db.members["Grumpy-Forever"]
check(gm.xp == 50 and gm.xpMax == 8000, "keeps previous xp when a status update omits it")

# /ab test fires a fake banner without touching real saved data.
g.SlashCmdList.ADUNDASBOARD("test")
check(any("Test: simulating" in p for p in g.__prints.values()), "/ab test fires without erroring")
check(db.members["Testy-Forever"] is None, "/ab test leaves no fake member behind")

# No messages while messaging is locked down (dungeons, raids).
before = len(g.__sent)
g.__lockdown = True
g.__fire("PLAYER_LEVEL_UP", 15, 0, 0)
g.__runTimers()
check(len(g.__sent) == before, "does not send during messaging lockdown")

g.__fire("GUILD_ROSTER_UPDATE", True)
g.__roster[2] = None
g.__roster = lua.table(g.__roster[1])
g.__fire("GUILD_ROSTER_UPDATE", True)
check(db.members["Grumpy-Forever"] is None, "removes members who left the guild")

g.SlashCmdList.ADUNDASBOARD("")
check(g.AdundasBoardFrame is not None, "/ab opens the board")

# Backfill: an old milestone for a class not otherwise seen in this run
# should still populate ns.db.records once BackfillRecords runs, as long
# as the member's current class is resolvable.
db.members["Shadow-Forever"] = lua.table(name="Shadow-Forever")
db.members["Shadow-Forever"]["class"] = "ROGUE"
g.tinsert(db.milestones, lua.table(name="Shadow-Forever", level=30, at=1700000000, source="roster"))
db.recordsBackfilled = False
ns.BackfillRecords()
check(db.records.byClass.ROGUE[30].name == "Shadow-Forever", "backfills a class record from an old milestone")
check(db.recordsBackfilled is True, "marks the backfill done so it only runs once")
ns.BackfillRecords()
check(db.records.byClass.ROGUE[30].name == "Shadow-Forever", "second backfill call is a no-op")

print()
sys.exit(1 if failures else 0)
