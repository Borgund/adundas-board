-- Options.lua: a panel under Options > AddOns > Adundas Board.
local addonName, ns = ...

local category

local function FindSoundIndex(key)
	for i, s in ipairs(ns.LEVEL_UP_SOUNDS) do
		if s.key == key then return i end
	end
	return 1
end

local OPTIONS = {
	{ key = "announceLevelUps", label = "Announce guildmates' level-ups in chat" },
	{ key = "playSound",        label = "Play a sound on level-ups" },
	{ key = "showBanner",       label = "Show a big banner for level-ups" },
	{ key = "shareXP",          label = "Share my XP progress with other addon users" },
}

function ns.InitOptions()
	local panel = CreateFrame("Frame")
	panel.name = "Adundas Board"

	local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
	title:SetPoint("TOPLEFT", 16, -16)
	title:SetText("Adundas Board " .. ns.VERSION)

	local description = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	description:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -6)
	description:SetPoint("RIGHT", panel, "RIGHT", -16, 0)
	description:SetJustifyH("LEFT")
	description:SetText("Tracks the guild leveling race: everyone's level and zone from the guild roster, plus XP progress and level-up history from anyone else running the addon.")

	local anchor = description

	local guildLabel = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
	guildLabel:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -16)
	guildLabel:SetText("Tracked guild")

	local guildBox = CreateFrame("EditBox", nil, panel, "InputBoxInstructionsTemplate")
	guildBox:SetSize(220, 20)
	guildBox:SetAutoFocus(false)
	guildBox:SetMaxLetters(100)
	guildBox:SetPoint("TOPLEFT", guildLabel, "BOTTOMLEFT", 6, -8)
	guildBox.Instructions:SetText("auto-detected after you log in")
	guildBox:SetText(ns.db.settings.guildName or "")

	local function CommitGuildName(self)
		local name = strtrim(self:GetText() or "")
		if name == "" then
			self:SetText(ns.db.settings.guildName or "")
		else
			ns.db.settings.guildName = name
		end
		self:ClearFocus()
	end
	guildBox:SetScript("OnEnterPressed", CommitGuildName)
	guildBox:SetScript("OnEditFocusLost", CommitGuildName)
	guildBox:SetScript("OnEscapePressed", function(self)
		self:SetText(ns.db.settings.guildName or "")
		self:ClearFocus()
	end)

	local useCurrentBtn = CreateFrame("Button", nil, panel, "BackdropTemplate")
	useCurrentBtn:SetSize(150, 20)
	useCurrentBtn:SetPoint("LEFT", guildBox, "RIGHT", 8, 0)
	useCurrentBtn:SetBackdrop({
		bgFile = "Interface\\Buttons\\WHITE8x8",
		edgeFile = "Interface\\Buttons\\WHITE8x8",
		edgeSize = 1,
	})
	useCurrentBtn:SetBackdropColor(1, 1, 1, 0.08)
	useCurrentBtn:SetBackdropBorderColor(1, 1, 1, 0.3)
	useCurrentBtn.text = useCurrentBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	useCurrentBtn.text:SetAllPoints()
	useCurrentBtn.text:SetJustifyH("CENTER")
	useCurrentBtn.text:SetText("Use my current guild")
	useCurrentBtn:SetScript("OnClick", function()
		local name = GetGuildInfo("player")
		if not name then
			ns.Print("You're not in a guild right now, so there's nothing to copy.")
			return
		end
		ns.db.settings.guildName = name
		guildBox:SetText(name)
		ns.Print("Tracked guild set to " .. name .. ".")
	end)

	anchor = guildBox

	local guildHelp = panel:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
	guildHelp:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", -6, -4)
	guildHelp:SetText("Auto-detected the first time you log in. Press Enter to save a change, or click \"Use my current guild\". Changing this clears the old guild's saved data next login.")
	anchor = guildHelp

	for _, opt in ipairs(OPTIONS) do
		local cb = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
		cb:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -8)
		cb.Text:SetText(opt.label)
		cb:SetChecked(ns.db.settings[opt.key])
		cb:SetScript("OnClick", function(self)
			ns.db.settings[opt.key] = self:GetChecked()
		end)
		anchor = cb
	end

	local minimapCb = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
	minimapCb:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -8)
	minimapCb.Text:SetText("Show minimap button")
	minimapCb:SetChecked(not ns.db.minimap.hide)
	minimapCb:SetScript("OnClick", function(self)
		ns.db.minimap.hide = not self:GetChecked()
		if ns.UpdateMinimapVisibility then ns.UpdateMinimapVisibility() end
	end)
	anchor = minimapCb

	local soundLabel = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
	soundLabel:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -16)
	soundLabel:SetText("Level-up sound")

	local soundBtn = CreateFrame("Button", nil, panel, "BackdropTemplate")
	soundBtn:SetSize(220, 22)
	soundBtn:SetPoint("TOPLEFT", soundLabel, "BOTTOMLEFT", 0, -6)
	soundBtn:SetBackdrop({
		bgFile = "Interface\\Buttons\\WHITE8x8",
		edgeFile = "Interface\\Buttons\\WHITE8x8",
		edgeSize = 1,
	})
	soundBtn:SetBackdropColor(1, 1, 1, 0.08)
	soundBtn:SetBackdropBorderColor(1, 1, 1, 0.3)
	soundBtn.text = soundBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	soundBtn.text:SetAllPoints()
	soundBtn.text:SetJustifyH("CENTER")
	soundBtn.text:SetText(ns.LEVEL_UP_SOUNDS[FindSoundIndex(ns.db.settings.levelUpSound)].label)
	soundBtn:SetScript("OnClick", function()
		local i = FindSoundIndex(ns.db.settings.levelUpSound) % #ns.LEVEL_UP_SOUNDS + 1
		local choice = ns.LEVEL_UP_SOUNDS[i]
		ns.db.settings.levelUpSound = choice.key
		soundBtn.text:SetText(choice.label)
		PlaySound(SOUNDKIT[choice.key]) -- preview it immediately
	end)
	anchor = soundBtn

	local soundHelp = panel:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
	soundHelp:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -4)
	soundHelp:SetText("Click to cycle through sounds and preview each one")
	anchor = soundHelp

	local help = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	help:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -16)
	help:SetPoint("RIGHT", panel, "RIGHT", -16, 0)
	help:SetJustifyH("LEFT")
	help:SetText("Open the board with the minimap button or /ab. /ab refresh re-reads the guild roster right away, /ab reset clears all saved board data, and /ab options reopens this panel.")

	category = Settings.RegisterCanvasLayoutCategory(panel, panel.name)
	Settings.RegisterAddOnCategory(category)
end

function ns.OpenOptions()
	if category then Settings.OpenToCategory(category:GetID()) end
end
