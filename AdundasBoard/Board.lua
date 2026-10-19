-- Board.lua: the leaderboard window.
local _, ns = ...

local ROW_HEIGHT = 18
local VISIBLE_ROWS = 18
local WIDTH = 640
local TABS_HEIGHT = 32

local COLUMNS = {
	{ key = "rank",   title = "#",      width = 30,  justify = "RIGHT" },
	{ key = "name",   title = "Name",   width = 170, justify = "LEFT" },
	{ key = "level",  title = "Level",  width = 50,  justify = "RIGHT" },
	{ key = "xp",     title = "XP",     width = 50,  justify = "RIGHT" },
	{ key = "class",  title = "Class",  width = 80,  justify = "LEFT" },
	{ key = "zone",   title = "Zone",   width = 110, justify = "LEFT" },
	{ key = "deaths", title = "Deaths", width = 50,  justify = "RIGHT" },
}

local board -- created on first open
local sorted = {}

local MODE_MEMBERS = "members"
local MODE_MILESTONES = "milestones"
local MODE_RECORDS = "records"
local mode = MODE_MEMBERS

-- Race tab grid geometry: a label column plus one column per
-- ns.RECORD_THRESHOLDS entry, sized to add up to WIDTH - 40 like the other
-- tabs' columns do. Capped at RECORD_ROWS rows (Overall + one per class),
-- no scrolling. RECORD_ROWS is deliberately generous rather than pinned to
-- Forever's exact class count, which isn't confirmed (checked
-- wow-ui-source-forever: its client flavors range from 9 to 12 classes,
-- never actually 13 - so don't trust a specific number here). CreateBoard
-- sizes the window tall enough for RECORD_ROWS * RECORD_ROW_HEIGHT, which
-- is taller than the shared VISIBLE_ROWS * ROW_HEIGHT the other two tabs
-- need, for breathing room between rows.
local RECORD_ROWS = 20
local RECORD_ROW_HEIGHT = 23
local RECORD_LABEL_WIDTH = 150
local RECORD_COL_WIDTH = 75

-- Zone-firsts list (ns.TRACKED_ZONES / ns.db.zoneFirsts): one line per
-- tracked zone, anchored at a fixed row inside the Race grid's existing
-- RECORD_ROWS reservation rather than dynamically after however many class
-- rows are currently in use, so it doesn't jump around as members change
-- classes. Typical class-row usage tops out around 13 (Overall + up to 12
-- classes, per the RECORD_ROWS comment above), leaving rows 15-20 free. If
-- ns.TRACKED_ZONES ever needs more room than that, bump RECORD_ROWS (the
-- window grows to match automatically, see CreateBoard) and/or this.
local ZONE_FIRST_START_ROW = 15

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
	if key == "deaths" then return m.deathCount or 0 end
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
	row.cells.deaths:SetText(tostring(m.deathCount or 0))
	row:SetAlpha(m.online and 1 or 0.5)
	row.data = m
end

-- Captured from ns.db.lastSeenMilestoneAt right before SetMode calls
-- ns.MarkMilestonesSeen (which bumps that value to "now"), so rows newer
-- than this can still be highlighted for this viewing of the tab.
local milestonesSeenCutoff = 0

local function UpdateMilestoneRow(row, ms, index)
	row.cells.rank:SetText(index)
	row.cells.name:SetText(Ambiguate(ms.name, "guild"))
	if ms.at > milestonesSeenCutoff then
		row.cells.name:SetTextColor(1, 0.82, 0)
	else
		row.cells.name:SetTextColor(1, 1, 1)
	end
	row.cells.level:SetText(ms.level)
	row.cells.xp:SetText("")
	row.cells.class:SetText(ms.source == "self" and "you" or "")
	row.cells.zone:SetText(RelativeTime(ms.at))
	row.cells.deaths:SetText("")
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

-- One row per class that actually has a member, plus a synthetic Overall
-- row first. Built fresh on every refresh instead of cached, since the
-- set of classes present can change as people join or leave.
local recordRowsData = {}
local function BuildRecordRows()
	wipe(recordRowsData)
	table.insert(recordRowsData, { label = "Overall", bucket = ns.db.records.overall, gold = true })
	local classRows, seen = {}, {}
	for _, m in pairs(ns.db.members) do
		if m.class and not seen[m.class] then
			seen[m.class] = true
			table.insert(classRows, {
				label = m.classLocalized or m.class,
				token = m.class,
				bucket = ns.db.records.byClass[m.class] or {},
			})
		end
	end
	table.sort(classRows, function(a, b) return a.label < b.label end)
	for _, row in ipairs(classRows) do table.insert(recordRowsData, row) end
end

-- Warns once (not every refresh) if more classes show up than RECORD_ROWS
-- has room for, so a class silently missing from the grid is at least
-- noticeable instead of just absent - its ns.db.records data is untouched
-- either way.
local recordRowOverflowWarned = false

local function UpdateRecordsRows()
	BuildRecordRows()
	if #recordRowsData > RECORD_ROWS and not recordRowOverflowWarned then
		recordRowOverflowWarned = true
		ns.Print(format("The Race tab only has room for %d rows; %d classes are in the guild. Some are being left off.", RECORD_ROWS, #recordRowsData - 1))
	end
	for i, row in ipairs(board.recordRows) do
		local data = recordRowsData[i]
		if data then
			row.label:SetText(data.label)
			if data.gold then
				row.label:SetTextColor(1, 0.82, 0)
			else
				row.label:SetTextColor(ClassColor(data.token))
			end
			for t, threshold in ipairs(ns.RECORD_THRESHOLDS) do
				local cell = row.cells[t]
				local record = data.bucket[threshold]
				cell.data = record
				if record then
					cell:SetText(Ambiguate(record.name, "guild"))
					-- ns.PeekMember, not ns.GetMember: this is a read-only
					-- render, and ns.GetMember would create a ghost member
					-- for a record holder who's since left the guild.
					local holder = ns.PeekMember(record.name)
					cell:SetTextColor(ClassColor(holder and holder.class))
				else
					cell:SetText("-")
					cell:SetTextColor(0.4, 0.4, 0.4)
				end
			end
			row:Show()
		else
			row:Hide()
		end
	end
	for i, zoneName in ipairs(ns.TRACKED_ZONES) do
		local row = board.zoneFirstRows[i]
		local first = ns.db.zoneFirsts[zoneName]
		if first then
			row:SetText(format("%s: %s - %s", zoneName, Ambiguate(first.name, "guild"), RelativeTime(first.at)))
		else
			row:SetText(format("%s: nobody yet", zoneName))
		end
		row:Show()
	end
	board.footer:SetText("First the addon observed at each level; levels before anyone ran it aren't counted.")
end

function ns.RefreshBoard()
	if not board or not board:IsShown() then return end
	if mode == MODE_RECORDS then
		UpdateRecordsRows()
	else
		BuildSorted()
		UpdateRows()
	end
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

-- Switches between the member roster, the recent level-ups feed, and the
-- Race grid, relabelling/showing the pieces that mean something different
-- (or nothing) in each.
local function SetMode(newMode)
	mode = newMode
	local b = board
	if not b then return end
	HighlightTab(b.tabMembers, mode == MODE_MEMBERS)
	HighlightTab(b.tabMilestones, mode == MODE_MILESTONES)
	HighlightTab(b.tabRecords, mode == MODE_RECORDS)

	local showList = mode ~= MODE_RECORDS
	b.scroll:SetShown(showList)
	for _, col in ipairs(COLUMNS) do b.headers[col.key]:SetShown(showList) end
	if not showList then for _, row in ipairs(b.rows) do row:Hide() end end
	if showList then
		for _, row in ipairs(b.recordRows) do row:Hide() end
		for _, row in ipairs(b.zoneFirstRows) do row:Hide() end
	end
	b.recordsHeaderLabel:SetShown(not showList)
	for _, h in ipairs(b.recordsHeaders) do h:SetShown(not showList) end

	if mode == MODE_MILESTONES then
		b.headers.zone:SetText("When")
		b.headers.class:SetText("")
		b.headers.xp:SetText("")
		b.headers.deaths:SetText("")
		b.onlineCheck:Hide()
		-- Capture before MarkMilestonesSeen bumps lastSeenMilestoneAt to now,
		-- so UpdateMilestoneRow can still tell which rows are new this visit.
		milestonesSeenCutoff = ns.db.lastSeenMilestoneAt or 0
		if ns.MarkMilestonesSeen then ns.MarkMilestonesSeen() end
	elseif mode == MODE_MEMBERS then
		b.headers.zone:SetText("Zone")
		b.headers.class:SetText("Class")
		b.headers.xp:SetText("XP")
		b.headers.deaths:SetText("Deaths")
		b.onlineCheck:Show()
	else
		b.onlineCheck:Hide()
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

-- A Race grid row: a label plus one cell per ns.RECORD_THRESHOLDS entry.
-- Each cell has its own tooltip, unlike CreateRow's rows, since every cell
-- names a different person.
local function CreateRecordRow(parent, index)
	local row = CreateFrame("Frame", nil, parent)
	row:SetSize(WIDTH - 40, RECORD_ROW_HEIGHT)
	row:SetPoint("TOPLEFT", 12, -56 - TABS_HEIGHT - (index - 1) * RECORD_ROW_HEIGHT)

	row.label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	row.label:SetPoint("LEFT", 0, 0)
	row.label:SetWidth(RECORD_LABEL_WIDTH - 10)
	row.label:SetJustifyH("LEFT")
	row.label:SetWordWrap(false)

	row.cells = {}
	for i = 1, #ns.RECORD_THRESHOLDS do
		local cell = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		cell:SetPoint("LEFT", RECORD_LABEL_WIDTH + (i - 1) * RECORD_COL_WIDTH, 0)
		cell:SetWidth(RECORD_COL_WIDTH - 10)
		cell:SetJustifyH("CENTER")
		cell:SetWordWrap(false)
		cell:EnableMouse(true)
		cell:SetScript("OnEnter", function(self)
			local record = self.data
			if not record then return end
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			GameTooltip:AddLine(record.name, 1, 1, 1)
			GameTooltip:AddLine(date("%b %d, %Y", record.at), 0.8, 0.8, 0.8)
			GameTooltip:Show()
		end)
		cell:SetScript("OnLeave", function() GameTooltip:Hide() end)
		row.cells[i] = cell
	end

	if index % 2 == 0 then
		local bg = row:CreateTexture(nil, "BACKGROUND")
		bg:SetAllPoints()
		bg:SetColorTexture(1, 1, 1, 0.04)
	end
	return row
end

local function CreateBoard()
	local f = CreateFrame("Frame", "AdundasBoardFrame", UIParent, "BasicFrameTemplateWithInset")
	local rowAreaHeight = math.max(VISIBLE_ROWS * ROW_HEIGHT, RECORD_ROWS * RECORD_ROW_HEIGHT)
	f:SetSize(WIDTH, 56 + TABS_HEIGHT + rowAreaHeight + 40)
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
	f.tabRecords = CreateTab("Race", MODE_RECORDS, 282, 60)
	HighlightTab(f.tabMembers, mode == MODE_MEMBERS)
	HighlightTab(f.tabMilestones, mode == MODE_MILESTONES)
	HighlightTab(f.tabRecords, mode == MODE_RECORDS)

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

	-- Race grid header (hidden outside MODE_RECORDS; see SetMode) and its
	-- row pool, positioned on the same TABS_HEIGHT-relative offsets as the
	-- member/milestone header and rows above.
	f.recordsHeaderLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	f.recordsHeaderLabel:SetPoint("TOPLEFT", 12, -32 - TABS_HEIGHT)
	f.recordsHeaderLabel:SetWidth(RECORD_LABEL_WIDTH)
	f.recordsHeaderLabel:SetJustifyH("LEFT")
	f.recordsHeaderLabel:SetText("First to reach level")
	f.recordsHeaderLabel:Hide()

	f.recordsHeaders = {}
	for i, threshold in ipairs(ns.RECORD_THRESHOLDS) do
		local h = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
		h:SetPoint("TOPLEFT", 12 + RECORD_LABEL_WIDTH + (i - 1) * RECORD_COL_WIDTH, -32 - TABS_HEIGHT)
		h:SetWidth(RECORD_COL_WIDTH)
		h:SetJustifyH("CENTER")
		h:SetText(tostring(threshold))
		h:Hide()
		f.recordsHeaders[i] = h
	end

	f.recordRows = {}
	for i = 1, RECORD_ROWS do f.recordRows[i] = CreateRecordRow(f, i) end

	-- One line per ns.TRACKED_ZONES entry, below the grid's typical usage
	-- (see ZONE_FIRST_START_ROW above). Empty for now since ns.TRACKED_ZONES
	-- starts empty - this pool just has zero rows until that's filled in.
	f.zoneFirstRows = {}
	for i = 1, #ns.TRACKED_ZONES do
		local fs = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		fs:SetPoint("TOPLEFT", 12, -56 - TABS_HEIGHT - (ZONE_FIRST_START_ROW - 1 + i - 1) * RECORD_ROW_HEIGHT)
		fs:SetWidth(WIDTH - 52)
		fs:SetJustifyH("LEFT")
		fs:SetWordWrap(false)
		fs:Hide()
		f.zoneFirstRows[i] = fs
	end

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
