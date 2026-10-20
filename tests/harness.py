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
-- Advances the simulated clock and fires only the timers whose delay has
-- elapsed by then, so a test can distinguish "the 3s roster request fired"
-- from "the 20s catch-up window closed" instead of both firing together.
function __advanceTime(seconds)
  now = now + seconds
  local fired, keep = {}, {}
  for _, t in ipairs(timers) do
    if t.at <= now then table.insert(fired, t.fn) else table.insert(keep, t) end
  end
  wipe(timers)
  for i, t in ipairs(keep) do timers[i] = t end
  for _, fn in ipairs(fired) do fn() end
end
-- Fires every pending timer regardless of delay, for tests that don't care
-- about relative timing.
function __runTimers()
  __advanceTime(1000000)
end

C_Timer = {
  After = function(delay, fn) table.insert(timers, { at = now + delay, fn = fn }) end,
  NewTicker = function() end,
}
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
function GetZoneText() return __myZone or "Elwynn Forest" end
function Ambiguate(n) return (n:gsub("%-.*$", "")) end
function FauxScrollFrame_GetOffset() return 0 end
function FauxScrollFrame_Update() end
function FauxScrollFrame_OnVerticalScroll() end
__roster = {
  { "Adrian Borg-Forever", "Officer", 1, 14, "Priest", "Tirisfal Glades", "", "", true, 0, "PRIEST" },
  { "Grumpy-Forever", "Member", 3, 9, "Warrior", "Durotar", "", "", false, 0, "WARRIOR" },
  { "Zinx-Forever", "Member", 4, 3, "Rogue", "Westfall", "", "", false, 0, "ROGUE" },
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
# Advance past the 3s roster-request timer and Comm.lua's 10s hello-reply
# timer, but not the 20s catch-up window (Roster.lua's CATCH_UP_WINDOW) -
# g.__runTimers() would fire all three at once and the catch-up tests below
# need the window to still be open.
g.__advanceTime(10)
check(g.__rosterRequested is True, "requests the guild roster after login")
check(len(g.__sent) == 1 and g.__sent[1].chan == "GUILD", "sends a hello on the GUILD channel")

g.__fire("GUILD_ROSTER_UPDATE", True)  # burst 1: Grumpy's catch-up level-up (5 -> 9)
check(db.settings.guildName == REAL_GUILD, "auto-adopts the first guild it ever sees")
check(db.guild == REAL_GUILD, "stores the guild name")
check(db.members["Grumpy-Forever"].level == 9, "reads roster levels")
check(db.members["Adrian Borg-Forever"] is not None, "keeps names with spaces intact")
check(
    not any("Grumpy reached level 9" in p for p in g.__prints.values()),
    "catch-up level-up skips the normal per-member announce line",
)
check(
    not any("reached new levels while you were away" in p for p in g.__prints.values()),
    "catch-up summary doesn't print until the window closes",
)

# The server can send roster data in more than one GUILD_ROSTER_UPDATE
# after login; a second burst still inside the same window should land in
# the same buffer, not get its own live announce or its own summary line.
g.__roster[3][4] = 6  # Zinx dings 3 -> 6, well below any RECORD_THRESHOLDS
g.__fire("GUILD_ROSTER_UPDATE", True)  # burst 2, still within the window
check(
    not any("Zinx reached level 6" in p for p in g.__prints.values()),
    "a second burst in the same window also skips the live announce",
)

g.__advanceTime(20)  # must stay >= Roster.lua's CATCH_UP_WINDOW; closes the window
check(
    sum(1 for p in g.__prints.values() if "reached new levels while you were away" in p) == 1,
    "batches both bursts into exactly one catch-up summary when the window closes",
)
check(
    any("Grumpy" in p and "Zinx" in p and "reached new levels while you were away" in p for p in g.__prints.values()),
    "the combined summary names members from both bursts",
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

# ns.PeekMember must never create an entry, unlike ns.GetMember - that's
# the whole point of having it.
before_count = len(db.members)
check(ns.PeekMember("NoSuchName-Forever") is None, "PeekMember returns nil for an unknown member")
check(len(db.members) == before_count, "PeekMember doesn't create an entry as a side effect")

# Backfill ghost-member regression: a milestone whose subject has since
# left the guild (not in db.members) must not get silently resurrected
# into db.members by BackfillRecords reading their class via ClaimRecords.
g.tinsert(db.milestones, lua.table(name="Gone-Forever", level=40, at=1700000001, source="roster"))
db.recordsBackfilled = False
ns.BackfillRecords()
check(db.records.overall[40].name == "Gone-Forever", "still credits the overall record despite the unknown class")
check(db.members["Gone-Forever"] is None, "does not resurrect a ghost member for a departed record holder")

# Zone-firsts: ns.TRACKED_ZONES ships empty (the real zone strings aren't
# collected yet), so override it here to exercise the detection/claim/
# announce path end-to-end. g.__roster was shrunk to one member earlier
# (the "left the guild" test); add a second one back for this.
ns.TRACKED_ZONES = lua.table("Camelot Crypt")
g.__roster[2] = lua.table("Pip-Forever", "Member", 4, 12, "Mage", "Tirisfal Glades", "", "", False, 0, "MAGE")
g.__fire("GUILD_ROSTER_UPDATE", True)  # baseline scan: nobody's in the tracked zone yet
check(db.zoneFirsts["Camelot Crypt"] is None, "no zone-first claimed before anyone enters the tracked zone")

g.__roster[2][6] = "Camelot Crypt"  # Pip walks into the tracked zone
g.__fire("GUILD_ROSTER_UPDATE", True)
check(db.zoneFirsts["Camelot Crypt"].name == "Pip-Forever", "credits the first guildmate seen in a tracked zone")
check(
    any("Pip" in p and "first into Camelot Crypt" in p for p in g.__prints.values()),
    "announces the zone-first in chat",
)

g.__roster[1][6] = "Camelot Crypt"  # Adrian (you) also walks in, after Pip already claimed it
g.__fire("GUILD_ROSTER_UPDATE", True)
check(db.zoneFirsts["Camelot Crypt"].name == "Pip-Forever", "first-wins: a later entrant doesn't steal the zone-first")

# Deaths: a guildmate's death learned via addon message gets recorded and
# announced (chat print, no banner by default).
decoded = lua.table(p=1, k="d", v="1.0.0", l=22, z="Camelot Crypt")
g.__lastDecoded = decoded
before_deaths = len(db.deaths)
g.__fire("CHAT_MSG_ADDON", "AdundasBoard", "{}", "GUILD", "Pip-Forever")
check(len(db.deaths) == before_deaths + 1, "records a death learned via addon message")
check(db.members["Pip-Forever"].deathCount == 1, "increments the member's death count")
check(
    any("Pip" in p and "died in Camelot Crypt" in p for p in g.__prints.values()),
    "announces a guildmate's death in chat",
)

# ns.RecordDeath never dedupes, unlike ns.RecordLevelUp - two deaths at the
# same level are two real deaths.
before_deaths = len(db.deaths)
ns.RecordDeath("Fenwick-Forever", 6, "Westfall")
ns.RecordDeath("Fenwick-Forever", 6, "Westfall")
check(len(db.deaths) == before_deaths + 2, "records a second death at the same level without deduping")
check(db.members["Fenwick-Forever"].deathCount == 2, "counts both deaths for the member")

# Your own death: recorded locally, but never announced in chat - you
# already saw your own death screen.
g.__lockdown = True  # dungeons/raids are exactly where this tends to happen
before_deaths = len(db.deaths)
sent_before = len(g.__sent)
prints_before = len(g.__prints)
g.__fire("PLAYER_DEAD")
check(len(db.deaths) == before_deaths + 1, "records your own death locally even if the broadcast is blocked")
check(db.members["Adrian Borg-Forever"].deathCount >= 1, "increments your own death count")
check(len(g.__sent) == sent_before, "does not send the death broadcast while messaging is locked down")
check(len(g.__prints) == prints_before, "never announces your own death in chat")

# Leaving the instance (ZONE_CHANGED_NEW_AREA) retries the blocked
# broadcast. Comm.lua's own XP-status retry fires on the same event too, so
# check among the newly-sent messages rather than assuming there's only one.
g.__lockdown = False
g.__fire("ZONE_CHANGED_NEW_AREA")
g.__advanceTime(5)
new_sent = [g.__sent[i] for i in range(sent_before + 1, len(g.__sent) + 1)]
check(
    any('"k":"d"' in m.text for m in new_sent),
    "retries the blocked death broadcast after leaving the instance",
)

# The ~10s insurance retry covers a same-zone throttle miss with no zone
# change to hang the retry above on.
g.__lockdown = True
sent_before = len(g.__sent)
g.__fire("PLAYER_DEAD")
check(len(g.__sent) == sent_before, "blocked again under lockdown")
g.__lockdown = False
g.__advanceTime(10)
check(len(g.__sent) == sent_before + 1, "the 10s insurance retry resends a blocked death broadcast")

print()
sys.exit(1 if failures else 0)
