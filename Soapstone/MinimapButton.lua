local _, ns = ...

-- A hand-rolled minimap button (same layout LibDBIcon uses) so the addon has
-- no library dependencies yet.

local Button = {}
ns.MinimapButton = Button

local function updatePosition(btn)
	local angle = math.rad(ns.db.minimap.angle)
	local radius = Minimap:GetWidth() / 2 + 5
	btn:ClearAllPoints()
	btn:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * radius, math.sin(angle) * radius)
end

local function onDragUpdate(btn)
	local mx, my = Minimap:GetCenter()
	local cx, cy = GetCursorPosition()
	local scale = Minimap:GetEffectiveScale()
	ns.db.minimap.angle = math.deg(math.atan2(cy / scale - my, cx / scale - mx)) % 360
	updatePosition(btn)
end

local function onEnter(btn)
	GameTooltip:SetOwner(btn, "ANCHOR_LEFT")
	GameTooltip:AddLine("Soapstone")
	local list, here = ns.Stones:Nearby()
	local nearest = list[1]
	if nearest then
		GameTooltip:AddLine(format("Nearest stone: %d yd %s", nearest.dist, ns.Stones:Bearing(here, nearest.stone)), 1, 1, 1)
	else
		GameTooltip:AddLine("No stones on this continent.", 1, 1, 1)
	end
	GameTooltip:AddLine(ns.Companion:Status(), 0.6, 0.6, 0.6)
	GameTooltip:AddLine(" ")
	GameTooltip:AddLine("|cffffd100Left-click|r  leave a stone here", 0.8, 0.8, 0.8)
	GameTooltip:AddLine("|cffffd100Right-click|r  list nearby stones", 0.8, 0.8, 0.8)
	GameTooltip:AddLine("|cffffd100Shift-click|r  sync with the companion (reloads)", 0.8, 0.8, 0.8)
	GameTooltip:AddLine("|cffffd100Drag|r  move this button", 0.8, 0.8, 0.8)
	GameTooltip:Show()
end

function Button:Init()
	local btn = CreateFrame("Button", "SoapstoneMinimapButton", Minimap)
	btn:SetSize(31, 31)
	btn:SetFrameStrata("MEDIUM")
	btn:SetFrameLevel(8)
	btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	btn:RegisterForDrag("LeftButton")
	btn:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

	local bg = btn:CreateTexture(nil, "BACKGROUND")
	bg:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
	bg:SetSize(20, 20)
	bg:SetPoint("TOPLEFT", 7, -5)

	local icon = btn:CreateTexture(nil, "ARTWORK")
	icon:SetTexture(ns.ICON)
	icon:SetSize(20, 20)
	icon:SetPoint("CENTER", bg, "CENTER")

	local border = btn:CreateTexture(nil, "OVERLAY")
	border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
	border:SetSize(53, 53)
	border:SetPoint("TOPLEFT")

	-- Pulses while a readable stone is in range.
	local glow = btn:CreateTexture(nil, "OVERLAY", nil, 1)
	glow:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
	glow:SetBlendMode("ADD")
	glow:SetVertexColor(0.62, 0.83, 0.78)
	glow:SetSize(48, 48)
	glow:SetPoint("CENTER", icon, "CENTER")
	glow:Hide()
	local pulse = glow:CreateAnimationGroup()
	pulse:SetLooping("BOUNCE")
	local fade = pulse:CreateAnimation("Alpha")
	fade:SetFromAlpha(1)
	fade:SetToAlpha(0.2)
	fade:SetDuration(0.8)
	btn.glow, btn.pulse = glow, pulse

	btn:SetScript("OnClick", function(_, mouse)
		if IsShiftKeyDown() then
			ns.Companion:Sync()
		elseif mouse == "RightButton" then
			ns.Stones:PrintNearby()
		else
			ns.ShowDropDialog()
		end
	end)
	btn:SetScript("OnDragStart", function(self)
		self:SetScript("OnUpdate", onDragUpdate)
	end)
	btn:SetScript("OnDragStop", function(self)
		self:SetScript("OnUpdate", nil)
	end)
	btn:SetScript("OnEnter", onEnter)
	btn:SetScript("OnLeave", GameTooltip_Hide)

	self.frame = btn
	updatePosition(btn)
	self:UpdateVisibility()
end

function Button:UpdateVisibility()
	if not self.frame then return end
	self.frame:SetShown(not ns.db.minimap.hide)
end

function Button:SetGlow(on)
	local btn = self.frame
	if not btn or btn.glow:IsShown() == on then return end
	btn.glow:SetShown(on)
	if on then btn.pulse:Play() else btn.pulse:Stop() end
end
