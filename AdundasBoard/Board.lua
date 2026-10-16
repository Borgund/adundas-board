-- Board.lua: the leaderboard window.
local _, ns = ...

local ROW_HEIGHT = 18
local VISIBLE_ROWS = 18
local WIDTH = 520
local TABS_HEIGHT = 32

local COLUMNS = {
	{ key = "rank",  title = "#",     width = 30,  justify = "RIGHT" },
	{ key = "name",  title = "Name",  width = 170, justify = "LEFT" },
	{ key = "level", title = "Level", width = 50,  justify = "RIGHT" },
	{ key = "xp",    title = "XP",    width = 50,  justify = "RIGHT" },
	{ key = "class", title = "Class", width = 80,  justify = "LEFT" },
	{ key = "zone",  title = "Zone",  width = 110, justify = "LEFT" },
}

local board -- created on first open
local sorted = {}

local MODE_MEMBERS = "members"
local MODE_MILESTONES = "milestones"
local mode = MODE_MEMBERS

-- Progress through the current level as 0..1, or nil if unknown.
local function Progress(m)
	if m.xp and m.xpMax and m.xpMax > 0 then return m.xp / m.xpMax end
	return nil
end

-- Seconds-ago as "just now", "5m ago", "3h ago", "2d ago".
local function RelativeTime(at)
	if not at then return "" end
	local delta = time() - at
	if delta < 60 then return "just now" end
	if delta < 3600 then return format("%dm ago", math.floor(delta / 60)) end
	if delta < 86400 then return format("%dh ago", math.floor(delta / 3600)) end
	return format("%dd ago", math.floor(delta / 86400))
end

local function SortValue(m, key)
	if key == "level" then return (m.level or 0) + (Progress(m) or 0) end
	if key == "name" then return m.name or "" end
	if key == "class" then return m.classLocalized or "" end
	if key == "zone" then return m.zone or "" end
	return 0
end

local function BuildSorted()
	wipe(sorted)
	if mode == MODE_MILESTONES then
		-- Newest first; ns.db.milestones is stored oldest-last.
		local list = ns.db.milestones
		for i = #list, 1, -1 do table.insert(sorted, list[i]) end
		return
	end
	local s = ns.db.settings
	for _, m in pairs(ns.db.members) do
		if not s.onlineOnly or m.online then table.insert(sorted, m) end
	end
	table.sort(sorted, function(a, b)
		local va, vb = SortValue(a, s.sortKey), SortValue(b, s.sortKey)
		if va == vb then return (a.name or "") < (b.name or "") end
		if s.sortDesc then return va > vb end
		return va < vb
	end)
end

local function ClassColor(token)
	local c = token and RAID_CLASS_COLORS[token]
	if c then return c.r, c.g, c.b end
	return 0.8, 0.8, 0.8
end

local function UpdateMemberRow(row, m, index)
	local p = Progress(m)
	row.cells.rank:SetText(index)
	row.cells.name:SetText(Ambiguate(m.name, "guild"))
	row.cells.name:SetTextColor(ClassColor(m.class))
	row.cells.level:SetText(m.level or "?")
	row.cells.xp:SetText(p and format("%d%%", p * 100) or "")
	row.cells.class:SetText(m.classLocalized or "")
	local zoneText = m.zone or ""
	if not m.online and m.lastSeen then
		zoneText = format("%s (%s)", zoneText ~= "" and zoneText or "offline", RelativeTime(m.lastSeen))
	end
	row.cells.zone:SetText(zoneText)
	row:SetAlpha(m.online and 1 or 0.5)
	row.data = m
end

local function UpdateMilestoneRow(row, ms, index)
	row.cells.rank:SetText(index)
	row.cells.name:SetText(Ambiguate(ms.name, "guild"))
	row.cells.name:SetTextColor(1, 1, 1)
	row.cells.level:SetText(ms.level)
	row.cells.xp:SetText("")
	row.cells.class:SetText(ms.source == "self" and "you" or "")
	row.cells.zone:SetText(RelativeTime(ms.at))
	row:SetAlpha(1)
	row.data = nil
end

local function UpdateRows()
	local offset = FauxScrollFrame_GetOffset(board.scroll)
	for i, row in ipairs(board.rows) do
		local index = offset + i
		local item = sorted[index]
		if item then
			if mode == MODE_MEMBERS then
				UpdateMemberRow(row, item, index)
			else
				UpdateMilestoneRow(row, item, index)
			end
			row:Show()
		else
			row.data = nil
			row:Hide()
		end
	end
	FauxScrollFrame_Update(board.scroll, #sorted, VISIBLE_ROWS, ROW_HEIGHT)

	if mode == MODE_MEMBERS then
		local withAddon = 0
		for _, m in ipairs(sorted) do if m.hasAddon then withAddon = withAddon + 1 end end
		board.footer:SetText(format("%d members shown, %d with the addon", #sorted, withAddon))
	else
		board.footer:SetText(format("%d recent level-ups", #sorted))
	end
end

function ns.RefreshBoard()
	if not board or not board:IsShown() then return end
	BuildSorted()
	UpdateRows()
end

local function HighlightTab(tab, active)
	if active then
		tab:SetBackdropColor(0.16, 0.22, 0.32, 0.9)
		tab:SetBackdropBorderColor(0.55, 0.75, 1, 0.9)
		tab.text:SetTextColor(1, 1, 1)
	else
		tab:SetBackdropColor(0, 0, 0, 0.35)
		tab:SetBackdropBorderColor(1, 1, 1, 0.2)
		tab.text:SetTextColor(0.6, 0.6, 0.6)
	end
end

-- Switches between the member roster and the recent level-ups feed,
-- relabelling the columns that mean something different in each.
local function SetMode(newMode)
	mode = newMode
	local b = board
	if not b then return end
	HighlightTab(b.tabMembers, mode == MODE_MEMBERS)
	HighlightTab(b.tabMilestones, mode == MODE_MILESTONES)
	if mode == MODE_MILESTONES then
		b.headers.zone:SetText("When")
		b.headers.class:SetText("")
		b.headers.xp:SetText("")
		b.onlineCheck:Hide()
		if ns.MarkMilestonesSeen then ns.MarkMilestonesSeen() end
	else
		b.headers.zone:SetText("Zone")
		b.headers.class:SetText("Class")
		b.headers.xp:SetText("XP")
		b.onlineCheck:Show()
	end
	ns.RefreshBoard()
end

local function CreateRow(parent, index)
	local row = CreateFrame("Frame", nil, parent)
	row:SetSize(WIDTH - 40, ROW_HEIGHT)
	row:SetPoint("TOPLEFT", 12, -56 - TABS_HEIGHT - (index - 1) * ROW_HEIGHT)
	row.cells = {}
	local x = 0
	for _, col in ipairs(COLUMNS) do
		local fs = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		fs:SetPoint("LEFT", x, 0)
		fs:SetWidth(col.width - 6)
		fs:SetJustifyH(col.justify)
		fs:SetWordWrap(false)
		row.cells[col.key] = fs
		x = x + col.width
	end
	if index % 2 == 0 then
		local bg = row:CreateTexture(nil, "BACKGROUND")
		bg:SetAllPoints()
		bg:SetColorTexture(1, 1, 1, 0.04)
	end

	row:EnableMouse(true)
	row:SetScript("OnEnter", function(self)
		local m = self.data
		if not m then return end
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:AddLine(Ambiguate(m.name, "guild"), 1, 1, 1)
		if m.rank then GameTooltip:AddLine(m.rank, 0.8, 0.8, 0.8) end
		if m.online then
			GameTooltip:AddLine("Online now", 0.1, 1, 0.1)
		elseif m.lastSeen then
			GameTooltip:AddLine("Last seen " .. RelativeTime(m.lastSeen), 0.8, 0.8, 0.8)
		end
		if m.hasAddon then
			GameTooltip:AddLine("Adundas Board " .. (m.addonVersion or "?"), 0.6, 0.6, 1)
		end
		GameTooltip:Show()
	end)
	row:SetScript("OnLeave", function() GameTooltip:Hide() end)
	return row
end

local function CreateBoard()
	local f = CreateFrame("Frame", "AdundasBoardFrame", UIParent, "BasicFrameTemplateWithInset")
	f:SetSize(WIDTH, 56 + TABS_HEIGHT + VISIBLE_ROWS * ROW_HEIGHT + 40)
	f:SetPoint("CENTER")
	f:SetMovable(true)
	f:EnableMouse(true)
	f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", f.StartMoving)
	f:SetScript("OnDragStop", f.StopMovingOrSizing)
	f:SetClampedToScreen(true)
	f:SetFrameStrata("MEDIUM")
	tinsert(UISpecialFrames, "AdundasBoardFrame") -- close with Escape
	f.TitleText:SetText("Adundas Board")

	-- Two tabs switch between the member roster and the recent level-ups
	-- feed. Anchored well below the title bar so they don't crowd it, with a
	-- backdrop border so the active one reads as clearly "selected".
	local function CreateTab(text, newMode, xOffset, width)
		local tab = CreateFrame("Button", nil, f, "BackdropTemplate")
		tab:SetSize(width, TABS_HEIGHT - 8)
		tab:SetPoint("TOPLEFT", xOffset, -28)
		tab:SetBackdrop({
			bgFile = "Interface\\Buttons\\WHITE8x8",
			edgeFile = "Interface\\Buttons\\WHITE8x8",
			edgeSize = 1,
		})
		tab.text = tab:CreateFontString(nil, "OVERLAY", "GameFontNormal")
		tab.text:SetAllPoints()
		tab.text:SetJustifyH("CENTER")
		tab.text:SetText(text)
		tab:SetScript("OnClick", function() SetMode(newMode) end)
		tab:SetScript("OnEnter", function(self) if mode ~= newMode then self.text:SetTextColor(0.85, 0.85, 0.85) end end)
		tab:SetScript("OnLeave", function(self) HighlightTab(self, mode == newMode) end)
		return tab
	end
	f.tabMembers = CreateTab("Roster", MODE_MEMBERS, 14, 110)
	f.tabMilestones = CreateTab("Recent level-ups", MODE_MILESTONES, 128, 150)
	HighlightTab(f.tabMembers, mode == MODE_MEMBERS)
	HighlightTab(f.tabMilestones, mode == MODE_MILESTONES)

	-- Column headers are buttons that change the sort (members mode only).
	f.headers = {}
	local x = 12
	for _, col in ipairs(COLUMNS) do
		local h = CreateFrame("Button", nil, f)
		h:SetSize(col.width, 18)
		h:SetPoint("TOPLEFT", x, -32 - TABS_HEIGHT)
		local fs = h:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
		fs:SetAllPoints()
		fs:SetJustifyH(col.justify)
		fs:SetText(col.title)
		f.headers[col.key] = fs
		if col.key ~= "rank" and col.key ~= "xp" then
			h:SetScript("OnClick", function()
				if mode ~= MODE_MEMBERS then return end
				local s = ns.db.settings
				if s.sortKey == col.key then s.sortDesc = not s.sortDesc
				else s.sortKey, s.sortDesc = col.key, col.key == "level" end
				ns.RefreshBoard()
			end)
		end
		x = x + col.width
	end

	f.scroll = CreateFrame("ScrollFrame", nil, f, "FauxScrollFrameTemplate")
	f.scroll:SetPoint("TOPLEFT", 8, -54 - TABS_HEIGHT)
	f.scroll:SetPoint("BOTTOMRIGHT", -30, 36)
	f.scroll:SetScript("OnVerticalScroll", function(self, offset)
		FauxScrollFrame_OnVerticalScroll(self, offset, ROW_HEIGHT, UpdateRows)
	end)

	f.rows = {}
	for i = 1, VISIBLE_ROWS do f.rows[i] = CreateRow(f, i) end

	local online = CreateFrame("CheckButton", nil, f, "UICheckButtonTemplate")
	online:SetSize(22, 22)
	online:SetPoint("BOTTOMLEFT", 10, 8)
	online.Text:SetText("Online only")
	online:SetChecked(ns.db.settings.onlineOnly)
	online:SetScript("OnClick", function(self)
		ns.db.settings.onlineOnly = self:GetChecked()
		ns.RefreshBoard()
	end)
	f.onlineCheck = online

	f.footer = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	f.footer:SetPoint("BOTTOMRIGHT", -14, 14)

	f:SetScript("OnShow", function()
		ns.RequestRoster()
		ns.RefreshBoard()
	end)
	return f
end

function ns.ToggleBoard()
	if not ns.db then return end
	board = board or CreateBoard()
	board:SetShown(not board:IsShown())
	if board:IsShown() then ns.RefreshBoard() end
end
