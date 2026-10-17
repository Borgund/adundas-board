-- Minimap.lua: a draggable minimap button for quick access, with a small
-- red badge when there's a level-up on the board you haven't seen yet.
local addonName, ns = ...

local button

-- Measure the real minimap each time instead of assuming a fixed size: its
-- on-screen radius depends on the client's default and the player's own
-- "Minimap Size" slider, which the fixed radius of 80 we started with
-- ignored, landing the button inside the rim instead of on it.
local function Reposition(angle)
	local rad = math.rad(angle)
	local radius = (Minimap:GetWidth() or 140) / 2 + 5
	button:ClearAllPoints()
	button:SetPoint("CENTER", Minimap, "CENTER", math.cos(rad) * radius, math.sin(rad) * radius)
end

local function CreateButton()
	local b = CreateFrame("Button", "AdundasBoardMinimapButton", Minimap)
	b:SetSize(31, 31)
	b:SetFrameStrata("MEDIUM")
	b:RegisterForClicks("AnyUp")
	b:RegisterForDrag("LeftButton")

	local icon = b:CreateTexture(nil, "BACKGROUND")
	icon:SetSize(20, 20)
	icon:SetPoint("CENTER", 0, 1)
	icon:SetTexture("Interface\\Icons\\INV_Misc_Book_09")

	local border = b:CreateTexture(nil, "OVERLAY")
	border:SetSize(54, 54)
	border:SetPoint("TOPLEFT")
	border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")

	b:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

	-- A pre-made round dot, not a colored rectangle: SetColorTexture can only
	-- ever fill a flat square, so a genuinely round badge needs real art.
	-- This is the same dot Blizzard uses for ready checks and LFG pops.
	local badge = b:CreateTexture(nil, "OVERLAY", nil, 1)
	badge:SetSize(12, 12)
	badge:SetPoint("TOPRIGHT", -1, -1)
	badge:SetTexture("Interface\\COMMON\\Indicator-Red")
	badge:Hide()
	b.badge = badge

	b:SetScript("OnClick", function() ns.ToggleBoard() end)
	b:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_LEFT")
		GameTooltip:SetText("Adundas Board")
		GameTooltip:AddLine("Click to open", 1, 1, 1)
		GameTooltip:AddLine("Drag to move", 0.6, 0.6, 0.6)
		GameTooltip:Show()
	end)
	b:SetScript("OnLeave", function() GameTooltip:Hide() end)

	-- Classic radial minimap-button drag: track the angle from the minimap's
	-- center to the cursor every frame while dragging, then just hold still.
	b:SetScript("OnDragStart", function(self)
		self:SetScript("OnUpdate", function()
			local mx, my = Minimap:GetCenter()
			local scale = Minimap:GetEffectiveScale()
			local px, py = GetCursorPosition()
			px, py = px / scale, py / scale
			local angle = math.deg(math.atan2(py - my, px - mx))
			Reposition(angle)
			ns.db.minimap.angle = angle
		end)
	end)
	b:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)

	return b
end

function ns.UpdateMinimapBadge()
	if not button then return end
	button.badge:SetShown(ns.HasUnseenMilestones())
end

function ns.UpdateMinimapVisibility()
	if not button then return end
	button:SetShown(not ns.db.minimap.hide)
end

ns.On("ADDON_LOADED", function(name)
	if name ~= addonName then return end
	button = CreateButton()
	Reposition(ns.db.minimap.angle or 225)
	ns.UpdateMinimapBadge()
	ns.UpdateMinimapVisibility()
end)
