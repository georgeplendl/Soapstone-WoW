local _, ns = ...

-- Stones on the world map, so far-off stones give you somewhere to go.
-- Sealed stones (ones you haven't been to yet) stand out with a slow glow;
-- stones you've read and your own sit back. The map never shows what a stone
-- says: reading it still means standing where it was left. Clicking a pin
-- guides you there (Guide.lua); a line under the map counts what's left to
-- find on the map you're looking at.
--
-- Built on the map's own pin system: a data provider, plus the pin template
-- in WorldMapPins.xml. The map asks for pins whenever it opens or changes
-- map; while it's open, a change in the store (a stone synced in, unlocked,
-- deleted, rated) redraws them.

local MapPins = {}
ns.WorldMapPins = MapPins

local TEMPLATE = "SoapstoneWorldMapPinTemplate"
local CHECK_INTERVAL = 0.5 -- seconds between "did the stones change?" checks while the map is open

-- How each kind of pin looks: size, alpha, colour, desaturated, glowing.
MapPins.LOOKS = {
	sealed     = { size = 18, alpha = 1,    r = 1,    g = 1,    b = 1,    glow = true },
	appraised  = { size = 14, alpha = 0.85, r = 1,    g = 0.85, b = 0.35 },
	read       = { size = 14, alpha = 0.6,  r = 0.8,  g = 0.8,  b = 0.8,  grey = true },
	mine       = { size = 14, alpha = 0.8,  r = 0.62, g = 0.83, b = 0.78 },
	disparaged = { size = 12, alpha = 0.3,  r = 0.5,  g = 0.5,  b = 0.5,  grey = true },
}

-- Which kind of pin a stone gets.
function MapPins.Kind(stone)
	if ns.Store.IsMine(stone) then return "mine" end
	local rating = ns.Stones:OthersRating(stone)
	if rating == ns.Stones.DISPARAGE then return "disparaged" end
	if not stone.heard then return "sealed" end
	if rating == ns.Stones.APPRAISE then return "appraised" end
	return "read"
end

-- Which continent (world-coordinate instance) a map is on; nil for maps
-- without one, like the whole world. Maps don't move, so it's kept.
local instances = {}
local function instanceOf(mapID)
	local cached = instances[mapID]
	if cached == nil then
		cached = C_Map.GetWorldPosFromMapPos(mapID, CreateVector2D(0.5, 0.5)) or false
		instances[mapID] = cached
	end
	return cached or nil
end

-- Every live stone that falls on `mapID`, as { stone, x, y } with x and y in
-- 0-1 across that map. Fills and returns `out` if given.
function MapPins:Place(mapID, out)
	out = out or {}
	wipe(out)
	local instance = mapID and instanceOf(mapID)
	if not instance then return out end
	for _, stone in ns.Store:Each() do
		if stone.instance == instance and stone.wx then
			local _, pos = C_Map.GetMapPosFromWorldPos(instance, CreateVector2D(stone.wx, stone.wy), mapID)
			local x, y
			if pos then x, y = pos:GetXY() end
			if x and x >= 0 and x <= 1 and y >= 0 and y <= 1 then
				out[#out + 1] = { stone = stone, x = x, y = y }
			end
		end
	end
	return out
end

-- "840 yd to the north-east", "Far away, on another continent" or nil.
function MapPins.Whereabouts(stone)
	local here = ns.Stones:GetPlayerLocation()
	if not here then return nil end
	local dist = ns.Stones:Distance(here, stone)
	if not dist then return "Far away, on another continent" end
	if dist < 1 then return "Right here" end
	return format("%d yd to the %s", math.floor(dist + 0.5), ns.Stones:Bearing(here, stone))
end

-- The tooltip lines for a stone: { text, r, g, b } each. Never its words.
function MapPins.TooltipLines(stone)
	local kind = MapPins.Kind(stone)
	local lines = {}
	local function add(text, r, g, b) lines[#lines + 1] = { text, r, g, b } end
	if kind == "sealed" then
		add("A sealed soapstone", 1, 1, 1)
	elseif kind == "mine" then
		add("Your soapstone", 0.62, 0.83, 0.78)
		add(ns.Stones:Byline(stone), 0.62, 0.83, 0.78)
	else
		add("A soapstone you've read", 0.8, 0.8, 0.8)
		add(ns.Stones:Byline(stone), 0.62, 0.83, 0.78)
	end
	local where = MapPins.Whereabouts(stone)
	if where then add(where, 0.8, 0.8, 0.8) end
	if kind == "sealed" then
		add("Travel there to unlock it.", 0.5, 0.5, 0.5)
	elseif kind ~= "mine" then
		add("Return to it to read it again.", 0.5, 0.5, 0.5)
	end
	add(ns.Guide.Hint(), 0.5, 0.5, 0.5)
	return lines
end

-- The line under the map for `placed` (from Place) on `mapID`, or nil when
-- there's nothing on it: "Durotar: 4 sealed soapstones to find · 2 read".
function MapPins.Summary(mapID, placed)
	if #placed == 0 then return nil end
	local sealed, read = 0, 0
	for _, p in ipairs(placed) do
		local kind = MapPins.Kind(p.stone)
		if kind == "sealed" then
			sealed = sealed + 1
		elseif kind ~= "mine" then
			read = read + 1
		end
	end
	local info = C_Map.GetMapInfo(mapID)
	local name = info and info.name and (info.name .. ": ") or ""
	if sealed == 0 and read == 0 then
		return format("%sonly your own soapstones so far", name)
	elseif sealed == 0 then
		return format("%severy soapstone found (%d)", name, read)
	end
	return format("%s%d sealed soapstone%s to find%s", name, sealed, sealed == 1 and "" or "s",
		read > 0 and format(" · %d read", read) or "")
end

-- The pin ------------------------------------------------------------------------

-- Our methods; the map's own base pin methods are filled in by Init.
SoapstoneWorldMapPinMixin = {}
local Pin = SoapstoneWorldMapPinMixin

function Pin:OnLoad()
	self:UseFrameLevelType("PIN_FRAME_LEVEL_AREA_POI")
	self:SetScalingLimits(1, 1.0, 1.2)
end

function Pin:OnAcquired(stone, x, y)
	self.stone = stone
	self:SetPosition(x, y)
	local look = MapPins.LOOKS[MapPins.Kind(stone)]
	self:SetSize(look.size, look.size)
	self:SetAlpha(look.alpha)
	self.Icon:SetDesaturated(look.grey or false)
	self.Icon:SetVertexColor(look.r, look.g, look.b)
	if look.glow then
		self.Glow:Show()
		self.Pulse:Play()
	else
		self.Pulse:Stop()
		self.Glow:Hide()
	end
end

function Pin:OnReleased()
	self.stone = nil
	self.Pulse:Stop()
end

function Pin:OnMouseEnter()
	if not self.stone then return end
	GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
	for _, line in ipairs(MapPins.TooltipLines(self.stone)) do
		GameTooltip:AddLine(line[1], line[2], line[3], line[4], true)
	end
	GameTooltip:Show()
end

function Pin:OnMouseLeave()
	GameTooltip:Hide()
end

-- Left-click guides you there. Right-click does what it does anywhere else
-- on the map: zoom out, or go up to the parent map.
function Pin:OnMouseUp(button)
	if button == "LeftButton" then
		if self.stone then ns.Guide:To(self.stone) end
	elseif button == "RightButton" then
		local map = self:GetMap()
		local scroll = map and map.ScrollContainer
		if scroll and scroll.IsZoomedIn and scroll:IsZoomedIn() then
			scroll:ZoomOut()
		elseif map and map.NavigateToParentMap then
			map:NavigateToParentMap()
		end
	end
end

-- The data provider ----------------------------------------------------------------

local Provider = {}
local placed = {} -- scratch list for MapPins:Place

function Provider:RemoveAllData()
	self:GetMap():RemoveAllPinsByTemplate(TEMPLATE)
end

function Provider:RefreshAllData()
	self:RemoveAllData()
	local map = self:GetMap()
	local mapID = map:GetMapID()
	for _, p in ipairs(MapPins:Place(mapID, placed)) do
		map:AcquirePin(TEMPLATE, p.stone, p.x, p.y)
	end
	MapPins:SetSummary(MapPins.Summary(mapID, placed))
	self.revision = ns.Store.revision
end

-- The count line, along the bottom of the map.
function MapPins:SetSummary(text)
	if not self.summary then
		local parent = WorldMapFrame.ScrollContainer or WorldMapFrame
		local holder = CreateFrame("Frame", nil, parent)
		holder:SetFrameStrata("HIGH")
		holder:SetSize(1, 1)
		holder:SetPoint("BOTTOM", parent, "BOTTOM", 0, 10)
		local label = holder:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
		label:SetPoint("BOTTOM")
		label:SetTextColor(0.62, 0.83, 0.78)
		label:SetShadowOffset(1, -1)
		self.summary = label
	end
	self.summary:SetText(text or "")
	self.summary:SetShown(text ~= nil)
end

-- Redraws if the map is open and the stones changed since it last drew.
function MapPins:Update()
	if not self.ready or not WorldMapFrame:IsShown() then return end
	if Provider.revision ~= ns.Store.revision then Provider:RefreshAllData() end
end

-- Gives `mixin` every method of `base` it doesn't define itself.
local function inherit(mixin, base)
	for key, value in pairs(base) do
		if mixin[key] == nil then mixin[key] = value end
	end
end

-- Hooks into the world map, now or as soon as it loads.
function MapPins:Init()
	if self.ready then return end
	if not (WorldMapFrame and WorldMapFrame.AddDataProvider and MapCanvasPinMixin and MapCanvasDataProviderMixin) then
		if not self.waiting then
			self.waiting = CreateFrame("Frame")
			self.waiting:RegisterEvent("ADDON_LOADED")
			self.waiting:SetScript("OnEvent", function(_, _, name)
				if name == "Blizzard_WorldMap" then self:Init() end
			end)
		end
		return
	end
	if self.waiting then self.waiting:UnregisterAllEvents() end
	inherit(Pin, MapCanvasPinMixin)
	inherit(Provider, MapCanvasDataProviderMixin)
	WorldMapFrame:AddDataProvider(Provider)
	self.ready = true

	local driver = CreateFrame("Frame")
	local elapsed = 0
	driver:SetScript("OnUpdate", function(_, dt)
		elapsed = elapsed + dt
		if elapsed < CHECK_INTERVAL then return end
		elapsed = 0
		self:Update()
	end)
end
