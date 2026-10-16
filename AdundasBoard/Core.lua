-- Core.lua: namespace, saved data, event dispatch and shared helpers.
local addonName, ns = ...

ns.VERSION = C_AddOns.GetAddOnMetadata(addonName, "Version") or "dev"
ns.SCHEMA = 1 -- bump when the shape of AdundasBoardDB.members changes

-- Curated, checked-to-exist SOUNDKIT names for the level-up sound picker in
-- Options.lua. Comm.lua looks the chosen key up in SOUNDKIT at play time.
ns.LEVEL_UP_SOUNDS = {
	{ key = "UI_QUEST_ROLLING_FORWARD_01", label = "Quest Complete" },
	{ key = "UI_ADVENTURES_ADVENTURER_LEVEL_UP", label = "Adventurer Level Up" },
	{ key = "UI_GARRISON_COMMAND_TABLE_FOLLOWER_LEVEL_UP", label = "Follower Level Up" },
	{ key = "RAID_WARNING", label = "Raid Warning" },
	{ key = "READY_CHECK", label = "Ready Check" },
	{ key = "UI_PVP_HONOR_PRESTIGE_RANK_UP", label = "PvP Rank Up" },
}

local defaults = {
	schema = ns.SCHEMA,
	settings = {
		-- guildName is deliberately not seeded here. A character can only be
		-- in one guild at a time (confirmed against the Guild and
		-- API_GetGuildInfo pages on warcraft.wiki.gg), so Roster.lua adopts
		-- whichever guild you're in the first time it ever sees one, instead
		-- of guessing a default. Once set, only that guild is tracked.
		announceLevelUps = true, -- print guildmates' level-ups in your chat frame
		playSound = true,  -- play a sound when a guildmate levels up
		levelUpSound = ns.LEVEL_UP_SOUNDS[1].key, -- which SOUNDKIT to play
		showBanner = true, -- big on-screen banner for guildmates' level-ups
		shareXP = true,    -- send your own XP progress to other addon users
		onlineOnly = false, -- board filter
		sortKey = "level",
		sortDesc = true,
	},
	guild = nil,  -- guild name this data belongs to
	updatedAt = 0, -- unix time of the last change
	members = {}, -- [fullName] = member record (see Roster.lua)
	milestones = {}, -- recent level-ups, newest last, capped
	lastSeenMilestoneAt = 0, -- for the minimap button's "unseen" badge
	minimap = { angle = 225, hide = false }, -- button position and visibility
}

-- Copy missing keys from defaults into the saved table, recursively.
local function MergeDefaults(target, source)
	for k, v in pairs(source) do
		if type(v) == "table" then
			if type(target[k]) ~= "table" then target[k] = {} end
			MergeDefaults(target[k], v)
		elseif target[k] == nil then
			target[k] = v
		end
	end
end

-- Midnight-era clients can hand addons "secret" values. issecretvalue only
-- exists on those clients, so guard the call. A secret value is never
-- compared or stored by this addon; we treat it as missing.
function ns.Readable(value)
	if value == nil then return nil end
	if issecretvalue and issecretvalue(value) then return nil end
	return value
end

-- Forever characters can have first and last names, so a name may contain a
-- space. Always keep the full "Name-Realm" string as the key and never split
-- on spaces.
function ns.FullName(name)
	if type(name) ~= "string" or name == "" then return nil end
	if not name:find("-", 1, true) then
		local realm = GetNormalizedRealmName()
		if realm then name = name .. "-" .. realm end
	end
	return name
end

function ns.Print(msg)
	print("|cff8ab4ffAdundas Board|r: " .. msg)
end

function ns.Touch()
	ns.db.updatedAt = time()
end

-- One frame owns all events. Modules register handlers with ns.On(event, fn).
local frame = CreateFrame("Frame")
local handlers = {}

function ns.On(event, fn)
	if not handlers[event] then
		handlers[event] = {}
		frame:RegisterEvent(event)
	end
	table.insert(handlers[event], fn)
end

frame:SetScript("OnEvent", function(_, event, ...)
	for _, fn in ipairs(handlers[event]) do
		fn(...)
	end
end)

ns.On("ADDON_LOADED", function(name)
	if name ~= addonName then return end
	AdundasBoardDB = AdundasBoardDB or {}
	MergeDefaults(AdundasBoardDB, defaults)
	ns.db = AdundasBoardDB
	if ns.db.schema ~= ns.SCHEMA then
		-- Simple migration policy for a starter: drop old member data.
		ns.db.members = {}
		ns.db.schema = ns.SCHEMA
	end
	if ns.OnLoad then ns.OnLoad() end
	if ns.InitOptions then ns.InitOptions() end
end)

SLASH_ADUNDASBOARD1 = "/adundas"
SLASH_ADUNDASBOARD2 = "/ab"
SlashCmdList.ADUNDASBOARD = function(msg)
	msg = strtrim(msg or ""):lower()
	if msg == "options" or msg == "config" then
		ns.OpenOptions()
	elseif msg == "refresh" then
		ns.RequestRoster(true)
		ns.Print("Refreshing guild roster.")
	elseif msg == "reset" then
		wipe(ns.db.members)
		wipe(ns.db.milestones)
		ns.Print("Board data cleared.")
		if ns.RefreshBoard then ns.RefreshBoard() end
	elseif msg == "test" then
		if ns.TestLevelUpBanner then ns.TestLevelUpBanner() end
	else
		ns.ToggleBoard()
	end
end

-- Called from the minimap addon compartment (see AddonCompartmentFunc in the TOC).
function AdundasBoard_OnCompartmentClick()
	ns.ToggleBoard()
end
