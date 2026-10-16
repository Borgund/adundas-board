-- Comm.lua: shares your XP progress and level-ups with other Adundas Board users.
--
-- Wire format: a JSON object sent on the GUILD addon channel with prefix
-- "AdundasBoard". Messages must stay under 255 bytes, and every prefix gets a
-- small allowance (10 messages, refilling 1 per second), so we send rarely.
local _, ns = ...

local PREFIX = "AdundasBoard" -- at most 16 characters
local PROTOCOL = 1
local XP_SEND_INTERVAL = 120 -- seconds between routine XP updates
local lastXPSend = 0

local function CanSend()
	if not IsInGuild() then return false end
	-- In dungeons, raids, encounters and PvP matches, addon messaging is locked
	-- down on Midnight-era clients. Check first instead of hitting the error.
	if C_ChatInfo.InChatMessagingLockdown and C_ChatInfo.InChatMessagingLockdown() then
		return false
	end
	return true
end

local function Send(payload)
	if not CanSend() then return false end
	payload.p = PROTOCOL
	local ok, text = pcall(C_EncodingUtil.SerializeJSON, payload)
	if not ok or #text > 255 then return false end
	local result = C_ChatInfo.SendAddonMessage(PREFIX, text, "GUILD")
	return result == Enum.SendAddonMessageResult.Success
end

local function MyStatus(kind)
	return {
		k = kind,                        -- "s" status, "l" level-up, "h" hello
		v = ns.VERSION,
		l = UnitLevel("player"),
		x = ns.db.settings.shareXP and UnitXP("player") or nil,
		m = ns.db.settings.shareXP and UnitXPMax("player") or nil,
	}
end

function ns.SendStatus(kind, force)
	if not ns.db then return end
	local now = GetTime()
	if not force and now - lastXPSend < XP_SEND_INTERVAL then return end
	if Send(MyStatus(kind or "s")) then lastXPSend = now end
end

-- Treat every incoming message as untrusted: check types and ranges.
local function ParseMessage(text)
	local ok, data = pcall(C_EncodingUtil.DeserializeJSON, text)
	if not ok or type(data) ~= "table" then return nil end
	if data.p ~= PROTOCOL then return nil end
	if type(data.k) ~= "string" then return nil end
	local level = tonumber(data.l)
	if not level or level < 1 or level > 60 then return nil end
	local xp, xpMax = tonumber(data.x), tonumber(data.m)
	if xp and xpMax and (xp < 0 or xpMax <= 0 or xp > xpMax) then xp, xpMax = nil, nil end
	return {
		kind = data.k,
		version = type(data.v) == "string" and data.v:sub(1, 20) or nil,
		level = math.floor(level),
		xp = xp,
		xpMax = xpMax,
	}
end

ns.On("CHAT_MSG_ADDON", function(prefix, text, channel, sender)
	if prefix ~= PREFIX or channel ~= "GUILD" or not ns.db then return end
	prefix, text, sender = ns.Readable(prefix), ns.Readable(text), ns.Readable(sender)
	if not text or not sender then return end
	local fullName = ns.FullName(sender)
	if not fullName or fullName == ns.FullName(UnitName("player")) then return end

	local msg = ParseMessage(text)
	if not msg then return end

	local m = ns.GetMember(fullName)
	local previous = m.level
	m.hasAddon = true
	m.addonVersion = msg.version
	m.level = math.max(m.level or 0, msg.level)
	-- A status without xp just means the sender has "share my XP" off right
	-- now; keep whatever we last knew instead of blanking it.
	if msg.xp then
		m.xp, m.xpMax = msg.xp, msg.xpMax
		m.xpUpdatedAt = time()
	end
	m.online = true
	m.lastSeen = time()

	if msg.kind == "l" or (previous and msg.level > previous) then
		if ns.RecordLevelUp(fullName, msg.level, "addon") then
			ns.AnnounceLevelUp(fullName, msg.level)
		end
	end
	-- Someone new came online: answer so they see our progress too.
	if msg.kind == "h" then
		C_Timer.After(math.random(2, 8), function() ns.SendStatus("s", true) end)
	end

	ns.Touch()
	if ns.RefreshBoard then ns.RefreshBoard() end
end)

-- A big on-screen banner for guildmates' level-ups, queued so two level-ups
-- a second apart don't overlap. Your own level-up already gets Blizzard's
-- own level-up visuals, so this is never shown for yourself.
local banner
local bannerQueue = {}
local bannerShowing = false

local function CreateBanner()
	local f = CreateFrame("Frame", nil, UIParent)
	f:SetSize(420, 60)
	f:SetPoint("TOP", 0, -180)
	f:SetFrameStrata("HIGH")

	local bg = f:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints()
	bg:SetColorTexture(0, 0, 0, 0.55)

	f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
	f.title:SetPoint("TOP", 0, -8)
	f.title:SetText("LEVEL UP!")

	f.subtitle = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
	f.subtitle:SetPoint("TOP", f.title, "BOTTOM", 0, -4)

	-- An AnimationGroup only drives alpha while it's actively playing; once it
	-- finishes, nothing holds the frame at the animation's final value unless
	-- something sets it explicitly, so without this the banner would fade in
	-- and then drift back to invisible a moment later. OnFinished only ever
	-- touches alpha here, never Show/Hide, so it can't race ShowNextBanner's
	-- own timer the way an OnFinished-triggered Hide used to.
	f.fadeIn = f:CreateAnimationGroup()
	local inAlpha = f.fadeIn:CreateAnimation("Alpha")
	inAlpha:SetFromAlpha(0)
	inAlpha:SetToAlpha(1)
	inAlpha:SetDuration(0.3)
	f.fadeIn:SetScript("OnFinished", function() f:SetAlpha(1) end)

	f.fadeOut = f:CreateAnimationGroup()
	local outAlpha = f.fadeOut:CreateAnimation("Alpha")
	outAlpha:SetFromAlpha(1)
	outAlpha:SetToAlpha(0)
	outAlpha:SetDuration(0.6)
	f.fadeOut:SetScript("OnFinished", function() f:SetAlpha(0) end)

	return f
end

local function ShowNextBanner()
	if bannerShowing or #bannerQueue == 0 then return end
	bannerShowing = true
	local item = table.remove(bannerQueue, 1)
	banner = banner or CreateBanner()
	banner.fadeIn:Stop()
	banner.fadeOut:Stop()
	banner:SetAlpha(0)
	banner.subtitle:SetText(format("%s reached level %d", Ambiguate(item.name, "guild"), item.level))
	local c = item.class and RAID_CLASS_COLORS[item.class]
	banner.subtitle:SetTextColor(c and c.r or 1, c and c.g or 1, c and c.b or 1)
	banner:Show()
	banner.fadeIn:Play()
	C_Timer.After(3, function() banner.fadeOut:Play() end)
	C_Timer.After(3.6, function()
		banner:Hide()
		bannerShowing = false
		ShowNextBanner()
	end)
end

local function ShowLevelUpBanner(fullName, level, class)
	table.insert(bannerQueue, { name = fullName, level = level, class = class })
	ShowNextBanner()
end

-- /ab test: fires a fake banner so you can check how it looks and sounds
-- without waiting on a real guildmate. Touches nothing in ns.db, and bypasses
-- the showBanner/playSound settings so it always fires on request. Run it
-- twice in quick succession to test that the second banner doesn't cut the
-- first one's fade-out short (see the queue race this used to have).
local TEST_CLASSES = { "WARRIOR", "MAGE", "PRIEST", "HUNTER", "ROGUE", "DRUID" }
function ns.TestLevelUpBanner()
	local level = math.random(2, 60)
	local class = TEST_CLASSES[math.random(#TEST_CLASSES)]
	ns.Print(format("Test: simulating a level %d banner.", level))
	PlaySound(SOUNDKIT[ns.db.settings.levelUpSound] or SOUNDKIT.UI_QUEST_ROLLING_FORWARD_01)
	ShowLevelUpBanner("Testy-Forever", level, class)
end

function ns.AnnounceLevelUp(fullName, level)
	if not ns.db.settings.announceLevelUps then return end
	ns.Print(format("%s reached level %d!", Ambiguate(fullName, "guild"), level))
	if ns.db.settings.playSound then
		local soundID = SOUNDKIT[ns.db.settings.levelUpSound] or SOUNDKIT.UI_QUEST_ROLLING_FORWARD_01
		PlaySound(soundID)
	end
	if ns.db.settings.showBanner then
		local m = ns.GetMember(fullName)
		ShowLevelUpBanner(fullName, level, m and m.class)
	end
end

local function UpdateSelf()
	local me = ns.FullName(UnitName("player"))
	if not me or not ns.db then return end
	local m = ns.GetMember(me)
	m.level = UnitLevel("player")
	m.xp, m.xpMax = UnitXP("player"), UnitXPMax("player")
	m.xpUpdatedAt = time()
	m.hasAddon = true
	m.addonVersion = ns.VERSION
	m.online = true
	m.lastSeen = time()
	ns.Touch()
end

function ns.OnLoad()
	C_ChatInfo.RegisterAddonMessagePrefix(PREFIX)
end

ns.On("PLAYER_ENTERING_WORLD", function(isLogin, isReload)
	UpdateSelf()
	if isLogin or isReload then
		C_Timer.After(10, function() ns.SendStatus("h", true) end)
	end
end)

ns.On("PLAYER_XP_UPDATE", function()
	UpdateSelf()
	ns.SendStatus("s")
	if ns.RefreshBoard then ns.RefreshBoard() end
end)

ns.On("PLAYER_LEVEL_UP", function(level)
	UpdateSelf()
	local me = ns.FullName(UnitName("player"))
	if me then ns.RecordLevelUp(me, level, "self") end
	-- UnitLevel can lag one frame behind the event, so send the event's level.
	C_Timer.After(1, function()
		local status = MyStatus("l")
		status.l = level
		if Send(status) then lastXPSend = GetTime() end
	end)
	if ns.RefreshBoard then ns.RefreshBoard() end
end)

-- Leaving an instance lifts the messaging lockdown; catch up then.
ns.On("ZONE_CHANGED_NEW_AREA", function()
	C_Timer.After(5, function() ns.SendStatus("s") end)
end)
