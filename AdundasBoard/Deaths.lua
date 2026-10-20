-- Deaths.lua: tracks guild member deaths (a count per member + a short
-- recent feed). No cause-of-death parsing yet - that needs real combat-log
-- work and is v2 territory.
local _, ns = ...

local MAX_DEATHS = 50

-- Record a death once we learn about it, whether it's our own (PLAYER_DEAD
-- below) or a guildmate's (an incoming "d" addon message, see Comm.lua).
-- Unlike ns.RecordLevelUp, this never dedupes - a second death at the same
-- level is a real second death, not a duplicate report of one event.
function ns.RecordDeath(fullName, level, zone)
	local list = ns.db.deaths
	table.insert(list, { name = fullName, level = level, zone = zone, at = time() })
	while #list > MAX_DEATHS do table.remove(list, 1) end
	local m = ns.GetMember(fullName)
	m.deathCount = (m.deathCount or 0) + 1
	ns.Touch()
	if ns.RefreshBoard then ns.RefreshBoard() end
end

-- A death broadcast that failed to send (most likely messaging lockdown in
-- a dungeon/raid), retried on the next zone change or after a short delay,
-- whichever comes first. Single-slot, not a queue: a second death before
-- the first retry lands just replaces it - an acceptable gap given how
-- rare back-to-back deaths within seconds of each other are.
local pendingDeath = nil

local function TryBroadcastDeath(level, zone)
	if ns.Send({ k = "d", v = ns.VERSION, l = level, z = zone }) then
		pendingDeath = nil
	else
		pendingDeath = { level = level, zone = zone }
	end
end

-- Leaving an instance lifts the messaging lockdown; catch up then, same as
-- Comm.lua's XP status retry (same 5s delay, to let the lockdown actually
-- clear before trying).
ns.On("ZONE_CHANGED_NEW_AREA", function()
	if pendingDeath then
		C_Timer.After(5, function()
			if pendingDeath then TryBroadcastDeath(pendingDeath.level, pendingDeath.zone) end
		end)
	end
end)

ns.On("PLAYER_DEAD", function()
	local me = ns.FullName(UnitName("player"))
	if not me or not ns.db then return end
	local level, zone = UnitLevel("player"), GetZoneText()
	ns.RecordDeath(me, level, zone)
	TryBroadcastDeath(level, zone)
	-- Insurance retry for a same-zone throttle miss with no zone change to
	-- hang the retry above on (e.g. a solo-leveling death).
	C_Timer.After(10, function()
		if pendingDeath then TryBroadcastDeath(pendingDeath.level, pendingDeath.zone) end
	end)
end)
