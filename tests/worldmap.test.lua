-- World map pins: which stones land on which map, how each kind looks, what
-- the tooltip says (never a stone's words), and redrawing while the map is
-- open. Drives WorldMapPins.lua against a small fake of the map canvas.
dofile(TESTS .. "/lib/harness.lua")
local NOW = 1790400000
function time() return NOW end
format = string.format
unpack = unpack or table.unpack
math.atan2 = math.atan2 or math.atan -- WoW's Lua 5.1 has atan2; 5.3 folds it into atan
function wipe(t) for k in pairs(t) do t[k] = nil end return t end
function strtrim(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
function GetBuildInfo() return "1.60.1", "70009", "", 16001 end
WOW_PROJECT_ID = 1
function UnitFullName() return "Mad", "Decent" end
function UnitName() return "Mad", "Decent" end
function GetNormalizedRealmName() return "Decent" end
C_Timer = { NewTicker = function() return { Cancel = function() end } end }
UIErrorsFrame = { AddMessage = function() end }
local tooltip = {}
GameTooltip = setmetatable({}, { __index = function(_, key)
	if key == "AddLine" then return function(_, text) tooltip[#tooltip + 1] = text end end
	return function() end
end })

function CreateVector2D(x, y)
	return { x = x, y = y, GetXY = function(v) return v.x, v.y end }
end

-- Maps: the Barrens (1413) is a 1000-yard square at the corner of Kalimdor
-- (1414, instance 1, 10000 yards); Eastern Kingdoms is instance 0; the world
-- map (947) has no world coordinates.
local BOUNDS = {
	[1413] = { instance = 1, size = 1000 },
	[1414] = { instance = 1, size = 10000 },
	[1415] = { instance = 0, size = 10000 },
}
local player = { mapID = 1413, x = 0.1, y = 0.1 }
C_Map = {
	GetMapInfo = function(id) return { mapType = 3, name = ({ [1413] = "The Barrens", [1414] = "Kalimdor" })[id] } end,
	GetBestMapForUnit = function() return player.mapID end,
	GetPlayerMapPosition = function() return CreateVector2D(player.x, player.y) end,
	GetWorldPosFromMapPos = function(mapID, pos)
		local b = BOUNDS[mapID]
		if not b then return nil end
		return b.instance, CreateVector2D(pos.x * b.size, pos.y * b.size)
	end,
	GetMapPosFromWorldPos = function(instance, world, mapID)
		local b = BOUNDS[mapID]
		if not b or b.instance ~= instance then return nil end
		return mapID, CreateVector2D(world.x / b.size, world.y / b.size)
	end,
}

-- Frames: only the bits WorldMapPins.lua uses.
local frames = {}
local function permissive(t)
	return setmetatable(t, { __index = function() return function() end end })
end
function CreateFrame()
	local f = permissive({ events = {} })
	function f:RegisterEvent(e) self.events[e] = true end
	function f:UnregisterAllEvents() self.events = {} end
	function f:SetScript(name, fn) self[name] = fn end
	function f:CreateFontString()
		local label = permissive({ text = "", shown = true })
		function label:SetText(t) self.text = t end
		function label:SetShown(v) self.shown = v end
		return label
	end
	frames[#frames + 1] = f
	return f
end

local ns = {}
assert(loadfile(ROOT .. "/Identity.lua"))("Soapstone", ns)
assert(loadfile(ROOT .. "/Store.lua"))("Soapstone", ns)
assert(loadfile(ROOT .. "/Codec.lua"))("Soapstone", ns)
assert(loadfile(ROOT .. "/Stones.lua"))("Soapstone", ns)
assert(loadfile(ROOT .. "/WorldMapPins.lua"))("Soapstone", ns)
assert(loadfile(ROOT .. "/Guide.lua"))("Soapstone", ns)
ns.Print = function() end
ns.db = { stones = {}, zones = {}, outbox = {}, gateYards = 40, nearYards = 150 }
ns.Cues = { Play = function() end }
ns.MinimapPins = { Update = function() end }
ns.MinimapButton = { SetGlow = function() end }
ns.ReadWindow = { Current = function() return nil end }
ns.Sync = { OnZone = function() end }
local Store, Stones, MapPins = ns.Store, ns.Stones, ns.WorldMapPins
Store:Init()

local function put(id, author, wx, wy, fields)
	local s = { id = id, authorKey = author, author = (author:gsub("%-", " ", 1)), instance = 1,
		wx = wx, wy = wy, mapID = 1413, t = NOW - 3 * 3600, text = "Praise the sun!" }
	for k, v in pairs(fields or {}) do s[k] = v end
	return Store:Put(s)
end

-- Kinds -----------------------------------------------------------------------------
local sealed = put("Zug-Zug-1-1", "Zug-Zug", 500, 500)
local read = put("Zug-Zug-1-2", "Zug-Zug", 600, 600, { heard = true })
local liked = put("Zug-Zug-1-3", "Zug-Zug", 700, 700, { heard = true })
local disliked = put("Zug-Zug-1-4", "Zug-Zug", 800, 800, { heard = true })
local mine = put("Mad-Decent-1-1", "Mad-Decent", 900, 900)
local outside = put("Zug-Zug-1-5", "Zug-Zug", 5000, 5000)       -- Kalimdor, not the Barrens
local elsewhere = put("Zug-Zug-1-6", "Zug-Zug", 500, 500, { instance = 0 }) -- Eastern Kingdoms
Stones:Vote(liked, Stones.APPRAISE)
Stones:Vote(disliked, Stones.DISPARAGE)

check(MapPins.Kind(sealed) == "sealed", "a stone you haven't been to is sealed")
check(MapPins.Kind(read) == "read", "one you've unlocked is read")
check(MapPins.Kind(liked) == "appraised", "one you appraised is appraised")
check(MapPins.Kind(disliked) == "disparaged", "one you disparaged is disparaged")
check(MapPins.Kind(mine) == "mine", "your own is yours")
check(MapPins.LOOKS.sealed.glow and not MapPins.LOOKS.read.glow and not MapPins.LOOKS.mine.glow,
	"only sealed stones glow")
check(MapPins.LOOKS.sealed.size > MapPins.LOOKS.read.size, "sealed pins are bigger than read ones")

-- Placement -------------------------------------------------------------------------
local function ids(list)
	local set = {}
	for _, p in ipairs(list) do set[p.stone.id] = p end
	return set
end
local barrens = ids(MapPins:Place(1413))
check(barrens[sealed.id] and barrens[mine.id] and barrens[disliked.id], "stones in the Barrens are on its map")
check(math.abs(barrens[sealed.id].x - 0.5) < 1e-9 and math.abs(barrens[sealed.id].y - 0.5) < 1e-9,
	"at their position on that map")
check(not barrens[outside.id], "a stone elsewhere on Kalimdor is off the Barrens map")
check(not barrens[elsewhere.id], "a stone on another continent is off it too")
local kalimdor = ids(MapPins:Place(1414))
check(kalimdor[sealed.id] and kalimdor[outside.id] and not kalimdor[elsewhere.id],
	"the continent map shows every stone on that continent")
check(ids(MapPins:Place(1415))[elsewhere.id] and not ids(MapPins:Place(1415))[sealed.id],
	"and Eastern Kingdoms only its own")
check(#MapPins:Place(947) == 0, "the world map (no coordinates) shows none")
check(#MapPins:Place(nil) == 0, "and no map shows none")
Store:Tombstone(put("Zug-Zug-1-7", "Zug-Zug", 550, 550))
check(not ids(MapPins:Place(1413))["Zug-Zug-1-7"], "deleted stones leave the map")

-- Tooltips --------------------------------------------------------------------------
local function joined(stone)
	local out = {}
	for _, line in ipairs(MapPins.TooltipLines(stone)) do out[#out + 1] = line[1] end
	return table.concat(out, " | ")
end
vprint(joined(sealed))
check(joined(sealed):find("^A sealed soapstone") ~= nil, "sealed: says it's sealed")
check(joined(sealed):find("566 yd to the north%-west") ~= nil, "with how far and which way")
check(joined(sealed):find("Travel there to unlock it") ~= nil, "and asks you to go")
check(joined(sealed):find("Zug") == nil, "without naming its author")
check(joined(read):find("A soapstone you've read") and joined(read):find("Zug Zug, 3 hrs ago"),
	"read: says so, with who and when")
check(joined(mine):find("Your soapstone") and joined(mine):find("%(You%)"), "yours: says so")
for _, stone in ipairs({ sealed, read, liked, disliked, mine }) do
	check(joined(stone):find("Praise the sun") == nil, "the map never shows a stone's words (" .. stone.id .. ")")
end
check(joined(elsewhere):find("another continent") ~= nil, "a stone on another continent says so")

-- Hooking into the map --------------------------------------------------------------
-- The real canvas asserts that pins have no OnEnter/OnLeave scripts (it routes
-- hover to OnMouseEnter/OnMouseLeave, and clicks to OnMouseUp, itself).
local xml = readFile(ROOT .. "/WorldMapPins.xml")
for _, script in ipairs({ "OnEnter", "OnLeave", "OnMouseUp", "OnMouseDown", "OnClick" }) do
	check(not xml:find("<" .. script .. "[%s/>]"), "the pin template sets no " .. script .. " script")
end
check(xml:find('<OnLoad method="OnLoad"/>') ~= nil, "only OnLoad")

local acquired, released, refreshes = {}, 0, 0
MapCanvasPinMixin = {
	UseFrameLevelType = function(self, level) self.level = level end,
	SetScalingLimits = function() end,
	SetPosition = function(self, x, y) self.x, self.y = x, y end,
	GetMap = function(self) return self.owningMap end,
}
MapCanvasDataProviderMixin = {
	OnAdded = function(self, map) self.owningMap = map end,
	GetMap = function(self) return self.owningMap end,
}
local function fakeTexture()
	local t = { shown = false }
	function t:Show() self.shown = true end
	function t:Hide() self.shown = false end
	function t:SetDesaturated(v) self.grey = v end
	function t:SetVertexColor() end
	return t
end
local function fakeAnim()
	local a = { playing = false }
	function a:Play() self.playing = true end
	function a:Stop() self.playing = false end
	return a
end
local map = { shown = false, mapID = 1413, providers = {} }
function map:IsShown() return self.shown end
function map:GetMapID() return self.mapID end
function map:AddDataProvider(p) self.providers[#self.providers + 1] = p; p:OnAdded(self) end
function map:RemoveAllPinsByTemplate(template)
	check(template == "SoapstoneWorldMapPinTemplate", "pins are cleared by our template")
	refreshes = refreshes + 1
	for _, pin in ipairs(acquired) do pin:OnReleased(); released = released + 1 end
	acquired = {}
end
function map:AcquirePin(template, ...)
	-- Like the real pool: a frame made from the template, with our mixin.
	local pin = setmetatable({ Icon = fakeTexture(), Glow = fakeTexture(), Pulse = fakeAnim() },
		{ __index = SoapstoneWorldMapPinMixin })
	function pin:SetSize(w) self.size = w end
	function pin:SetAlpha(a) self.alpha = a end
	function pin:SetMouseClickEnabled(v) self.clicks = v end
	function pin:SetMouseMotionEnabled(v) self.motion = v end
	pin.owningMap = self
	pin:OnLoad()
	pin:OnAcquired(...)
	acquired[#acquired + 1] = pin
	return pin
end
local function refresh() map.providers[1]:RefreshAllData() end
local function pinFor(stone)
	for _, pin in ipairs(acquired) do if pin.stone == stone then return pin end end
end

MapPins:Init()
check(not MapPins.ready, "before the world map loads, Init waits")
local waiter = frames[#frames]
check(waiter.events.ADDON_LOADED, "for the map's addon to load")
WorldMapFrame = map
waiter.OnEvent(waiter, "ADDON_LOADED", "SomeOtherAddon")
check(not MapPins.ready, "another addon loading doesn't count")
waiter.OnEvent(waiter, "ADDON_LOADED", "Blizzard_WorldMap")
check(MapPins.ready and #map.providers == 1, "the world map loading hooks us in")
check(not next(waiter.events), "and stops listening")
check(SoapstoneWorldMapPinMixin.SetPosition == MapCanvasPinMixin.SetPosition, "pins get the map's base pin methods")
check(SoapstoneWorldMapPinMixin.OnAcquired ~= nil and map.providers[1].GetMap ~= nil, "on top of our own")

map.shown = true
refresh()
check(#acquired == 5, "opening the Barrens map draws its 5 live stones")
local p = pinFor(sealed)
check(p and p.x == 0.5 and p.y == 0.5, "at their map position")
check(p.size == 18 and p.Glow.shown and p.Pulse.playing, "the sealed one big and glowing")
check(p.level == "PIN_FRAME_LEVEL_AREA_POI", "drawn at the map's point-of-interest level")
local r = pinFor(read)
check(r.Icon.grey and not r.Glow.shown and not r.Pulse.playing and r.alpha < 1, "the read one dim and still")

tooltip = {}
p:OnMouseEnter()
check(tooltip[1] == "A sealed soapstone", "hovering shows the tooltip")
check(tooltip[#tooltip] == "Click: guide me there", "and says a click guides you there")

-- Clicks: left guides, right zooms out or goes up a map, like anywhere on the map.
local guided
local realTo = ns.Guide.To
ns.Guide.To = function(_, stone) guided = stone end
p:OnMouseUp("LeftButton")
check(guided == sealed, "left-clicking a pin guides you to its stone")
ns.Guide.To = realTo
local zoomedOut, wentUp = 0, 0
map.ScrollContainer = { zoomed = true }
function map.ScrollContainer:IsZoomedIn() return self.zoomed end
function map.ScrollContainer:ZoomOut() zoomedOut = zoomedOut + 1; self.zoomed = false end
function map:NavigateToParentMap() wentUp = wentUp + 1 end
p:OnMouseUp("RightButton")
check(zoomedOut == 1 and wentUp == 0, "right-clicking a pin while zoomed in zooms out")
p:OnMouseUp("RightButton")
check(zoomedOut == 1 and wentUp == 1, "and when not zoomed, goes up to the parent map")

-- The count line under the map
local summary = MapPins.summary
check(summary and summary.shown, "the map shows a count line")
check(summary.text == "The Barrens: 1 sealed soapstone to find · 3 read", "counting sealed and read stones, not yours")
check(MapPins.Summary(1413, {}) == nil, "nothing on the map: no line")
check(MapPins.Summary(1413, { { stone = mine } }) == "The Barrens: only your own soapstones so far",
	"only yours: says so")
check(MapPins.Summary(1413, { { stone = read }, { stone = liked } }) == "The Barrens: every soapstone found (2)",
	"all found: says so")
check(MapPins.Summary(1414, { { stone = sealed }, { stone = outside } }) == "Kalimdor: 2 sealed soapstones to find",
	"plural, and on a continent map")

-- Redrawing while open
local before = refreshes
MapPins:Update()
check(refreshes == before, "nothing changed: no redraw")
put("Zug-Zug-1-8", "Zug-Zug", 300, 300)
MapPins:Update()
check(refreshes == before + 1 and #acquired == 6, "a new stone (say, synced in) appears while the map is open")

-- Walk up to the sealed stone: unlocking it turns its pin to read.
player.x, player.y = 0.5, 0.49 -- 10 yards from it
Stones:CheckProximity()
check(ns.Store.IsHeard(sealed), "standing by it unlocks it")
MapPins:Update()
check(MapPins.Kind(sealed) == "read" and not pinFor(sealed).Glow.shown, "and its map pin stops glowing")
check(MapPins.summary.text == "The Barrens: 1 sealed soapstone to find · 4 read", "and the count line moves on (one synced in, one unlocked)")

local count = refreshes
map.shown = false
put("Zug-Zug-1-9", "Zug-Zug", 310, 310)
MapPins:Update()
check(refreshes == count, "with the map closed, nothing is redrawn")
map.shown = true
MapPins:Update()
check(refreshes == count + 1, "opening it again catches up")
Stones:Vote(read, Stones.APPRAISE)
MapPins:Update()
check(pinFor(read).alpha == MapPins.LOOKS.appraised.alpha, "appraising restyles the pin")

done()
