-- Roster.lua: reads the guild roster into AdundasBoardDB.members.
local _, ns = ...

local ROSTER_THROTTLE = 15 -- seconds between roster requests
local MAX_MILESTONES = 50
local lastRequest = 0

-- Ask the server for fresh roster data. The answer arrives as GUILD_ROSTER_UPDATE.
function ns.RequestRoster(force)
	if not IsInGuild() then return end
	local now = GetTime()
	if not force and now - lastRequest < ROSTER_THROTTLE then return end
	lastRequest = now
	C_GuildInfo.GuildRoster()
end

-- Record a level-up once, whether we learn it from the roster or from a message.
function ns.RecordLevelUp(fullName, level, source)
	local list = ns.db.milestones
	for i = #list, math.max(1, #list - 10), -1 do
		local m = list[i]
		if m.name == fullName and m.level == level then return false end
	end
	table.insert(list, { name = fullName, level = level, at = time(), source = source })
	while #list > MAX_MILESTONES do table.remove(list, 1) end
	ns.Touch()
	if ns.UpdateMinimapBadge then ns.UpdateMinimapBadge() end
	return true
end

function ns.HasUnseenMilestones()
	local list = ns.db.milestones
	local last = list[#list]
	return last ~= nil and last.at > (ns.db.lastSeenMilestoneAt or 0)
end

function ns.MarkMilestonesSeen()
	local list = ns.db.milestones
	ns.db.lastSeenMilestoneAt = list[#list] and list[#list].at or time()
	if ns.UpdateMinimapBadge then ns.UpdateMinimapBadge() end
end

local function GetMember(fullName)
	local members = ns.db.members
	local m = members[fullName]
	if not m then
		m = { name = fullName }
		members[fullName] = m
	end
	return m
end
ns.GetMember = GetMember

local function ScanRoster()
	if not ns.db then return end -- saved data not loaded yet
	local numTotal = GetNumGuildMembers()
	if not numTotal or numTotal == 0 then return end -- roster not ready yet

	local guildName = ns.Readable(GetGuildInfo("player"))
	if not guildName then return end -- not in a guild right now

	if not ns.db.settings.guildName then
		-- Never configured: adopt whichever guild we see first. A character
		-- can only be in one guild at a time, so this is a safe, one-time
		-- auto-detect rather than a guess. Options.lua can still retarget it
		-- later (e.g. you logged an alt in first by mistake, or the guild
		-- got renamed).
		ns.db.settings.guildName = guildName
		ns.Print("Now tracking " .. guildName .. ". Change this under Options if that's wrong.")
	end

	if guildName ~= ns.db.settings.guildName then return end -- a different guild; leave saved data alone

	if ns.db.guild ~= guildName then
		-- First run, or switched guild from whatever we tracked before:
		-- start clean so an alt's old guild never lingers in the board.
		wipe(ns.db.members)
		wipe(ns.db.milestones)
		ns.db.guild = guildName
	end

	local seen = {}
	local now = time()
	for i = 1, numTotal do
		local name, rankName, rankIndex, level, classLocalized, zone, _, _, isOnline, _, classToken =
			GetGuildRosterInfo(i)
		local fullName = ns.FullName(ns.Readable(name))
		if fullName then
			seen[fullName] = true
			local m = GetMember(fullName)
			local newLevel = ns.Readable(level)
			if m.level and newLevel and newLevel > m.level then
				if ns.RecordLevelUp(fullName, newLevel, "roster") then
					ns.AnnounceLevelUp(fullName, newLevel)
				end
			end
			m.rank = ns.Readable(rankName)
			m.rankIndex = ns.Readable(rankIndex)
			m.level = newLevel or m.level
			m.class = ns.Readable(classToken)
			m.classLocalized = ns.Readable(classLocalized)
			m.zone = ns.Readable(zone) or m.zone
			m.online = ns.Readable(isOnline) and true or false
			if m.online then m.lastSeen = now end
		end
	end

	-- Drop people who left the guild.
	for fullName in pairs(ns.db.members) do
		if not seen[fullName] then ns.db.members[fullName] = nil end
	end

	ns.Touch()
	if ns.RefreshBoard then ns.RefreshBoard() end
end

ns.On("GUILD_ROSTER_UPDATE", ScanRoster)

ns.On("PLAYER_ENTERING_WORLD", function(isLogin, isReload)
	if isLogin or isReload then
		C_Timer.After(3, function() ns.RequestRoster(true) end)
	end
end)

-- Keep the board fresh while you play. The throttle above keeps this polite.
C_Timer.NewTicker(60, function() ns.RequestRoster() end)
