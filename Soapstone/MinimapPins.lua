local _, ns = ...

-- Stones drawn on the minimap. Stones outside the minimap's view (but within
-- EDGE_RANGE) cling to its rim, pointing the way — the "pull to walk" pins.

local Pins = {}
ns.MinimapPins = Pins

-- Minimap diameter in yards per zoom level (values from HereBeDragons-Pins).
local OUTDOOR = { [0] = 466 + 2 / 3, 400, 333 + 1 / 3, 266 + 2 / 3, 200, 133 + 1 / 3 }
local INDOOR = { [0] = 300, 240, 180, 120, 80, 50 }

local EDGE_RANGE = 1000 -- yards; farther stones are hidden
local PIN_SIZE = 16
local RIM_INSET = 7
local UPDATE_INTERVAL = 0.05

local pool = {}
local nearby = {} -- scratch list for Store:Near, reused every update

local function onPinEnter(pin)
	local stone = pin.stone
	GameTooltip:SetOwner(pin, "ANCHOR_RIGHT")
	if ns.Stones:IsReadable(stone, pin.dist) then
		-- Sketches are never drawn in tooltips; they open in the read window.
		local sketch = ns.Stones.IsSketch(stone)
		GameTooltip:AddLine(sketch and "A sketch" or format("\"%s\"", ns.Stones.TextOf(stone) or ""), 1, 1, 1, true)
		GameTooltip:AddLine(ns.Stones:Byline(stone), 0.62, 0.83, 0.78)
		GameTooltip:AddLine(sketch and "Click to view" or "Click to open", 0.5, 0.5, 0.5)
	else
		GameTooltip:AddLine("A sealed soapstone", 0.6, 0.6, 0.6)
	end
	local rating = ns.Stones:OthersRating(stone)
	local vote = rating == ns.Stones.APPRAISE and "  ·  you appraised it"
		or rating == ns.Stones.DISPARAGE and "  ·  you disparaged it" or ""
	local found = ns.Stones:FoundCount(stone)
	found = found and found > 0 and format("  ·  found by %d", found) or ""
	GameTooltip:AddLine(format("Score %d%s%s", ns.Stones:Score(stone), found, vote),
		rating == ns.Stones.DISPARAGE and 0.6 or 1, rating == ns.Stones.DISPARAGE and 0.6 or 0.82,
		rating == ns.Stones.DISPARAGE and 0.6 or 0)
	if not ns.Stones:IsReadable(stone, pin.dist) then
		GameTooltip:AddLine(format("Walk within %d yards to read it (%d yd away).", ns.db.gateYards, pin.dist), 0.8, 0.8, 0.8, true)
	end
	GameTooltip:Show()
end

local function acquire(i)
	local pin = pool[i]
	if pin then return pin end
	pin = CreateFrame("Frame", nil, Minimap)
	pin:SetSize(PIN_SIZE, PIN_SIZE)
	pin:SetFrameLevel(Minimap:GetFrameLevel() + 5)
	pin.tex = pin:CreateTexture(nil, "OVERLAY")
	pin.tex:SetAllPoints()
	pin.tex:SetTexture(ns.PIN_ICON)
	pin:EnableMouse(true)
	pin:SetScript("OnEnter", onPinEnter)
	pin:SetScript("OnLeave", GameTooltip_Hide)
	pin:SetScript("OnMouseUp", function(self, button)
		if button == "LeftButton" and self.stone and ns.Stones:IsReadable(self.stone, self.dist) then
			GameTooltip:Hide()
			ns.ReadWindow:Show(self.stone)
		end
	end)
	pool[i] = pin
	return pin
end

local function style(pin, readable, onRim)
	local stone = pin.stone
	local rating = ns.Stones:OthersRating(stone) -- your own upvote doesn't gild your pins
	if rating == ns.Stones.DISPARAGE then -- faded, whether or not in range
		pin.tex:SetDesaturated(true)
		pin.tex:SetVertexColor(0.5, 0.5, 0.5)
		pin:SetAlpha(0.35)
		return
	elseif rating == ns.Stones.APPRAISE then -- gold
		pin.tex:SetDesaturated(false)
		pin.tex:SetVertexColor(1, 0.85, 0.35)
		pin:SetAlpha(readable and 1 or 0.8)
		return
	end
	pin.tex:SetDesaturated(not readable)
	if readable then
		pin.tex:SetVertexColor(1, 1, 1)
		pin:SetAlpha(1)
	elseif ns.Store.IsHeard(stone) then
		pin.tex:SetVertexColor(0.8, 0.8, 0.8)
		pin:SetAlpha(0.75)
	else
		pin.tex:SetVertexColor(0.6, 0.6, 0.6)
		pin:SetAlpha(onRim and 0.5 or 0.7)
	end
end

function Pins:Update()
	local here = ns.Stones:GetPlayerLocation()
	local shown = 0

	if here and Minimap:IsVisible() then
		local diameter = (IsIndoors() and INDOOR or OUTDOOR)[Minimap:GetZoom()] or OUTDOOR[0]
		local radiusPx = Minimap:GetWidth() / 2
		local pxPerYard = radiusPx / (diameter / 2)
		local rimPx = radiusPx - RIM_INSET

		-- With a rotating minimap the player's facing is "up".
		local facing = GetCVar("rotateMinimap") == "1" and (GetPlayerFacing() or 0) or 0
		local cosF, sinF = math.cos(facing), math.sin(facing)

		for _, stone in ipairs(ns.Store:Near(here, EDGE_RANGE, nearby)) do
			local north, east = ns.Stones:Offset(here, stone)
			if north then
				local dist = math.sqrt(north * north + east * east)
				if dist <= EDGE_RANGE then
					local px = (east * cosF + north * sinF) * pxPerYard
					local py = (north * cosF - east * sinF) * pxPerYard
					local len = math.sqrt(px * px + py * py)
					local onRim = len > rimPx
					if onRim then
						px, py = px / len * rimPx, py / len * rimPx
					end

					shown = shown + 1
					local pin = acquire(shown)
					pin.stone, pin.dist = stone, dist
					pin:ClearAllPoints()
					pin:SetPoint("CENTER", Minimap, "CENTER", px, py)
					style(pin, ns.Stones:IsReadable(stone, dist), onRim)
					pin:Show()
				end
			end
		end
	end

	for i = shown + 1, #pool do
		pool[i]:Hide()
	end
end

function Pins:Init()
	local driver = CreateFrame("Frame")
	local elapsed = 0
	driver:SetScript("OnUpdate", function(_, dt)
		elapsed = elapsed + dt
		if elapsed < UPDATE_INTERVAL then return end
		elapsed = 0
		self:Update()
	end)
	self:Update()
end
