local _, ns = ...

-- A stone is pinned to a world position. Map coordinates (0-1 within a zone map)
-- are kept for display; distances use world coordinates, which are in yards and
-- continuous across a continent. World X grows northward, world Y grows westward.
--
-- stone = { id, text, author, t, mapID, x, y, instance, wx, wy, mine, heard }

local Stones = {}
ns.Stones = Stones

local TEST_MESSAGES = {
	"Try jumping",
	"Treasure ahead",
	"Be wary of left",
	"Praise the sun!",
	"Visions of murlocs...",
	"Didn't expect flight path",
	"Time for a break",
}

local COMPASS = { "north", "north-east", "east", "south-east", "south", "south-west", "west", "north-west" }

-- Where the player is right now. nil in instances and anywhere the map API has
-- no position for us.
function Stones:GetPlayerLocation()
	local mapID = C_Map.GetBestMapForUnit("player")
	if not mapID then return nil end
	local pos = C_Map.GetPlayerMapPosition(mapID, "player")
	if not pos then return nil end
	local instance, world = C_Map.GetWorldPosFromMapPos(mapID, pos)
	if not instance or not world then return nil end
	local x, y = pos:GetXY()
	local wx, wy = world:GetXY()
	return { mapID = mapID, x = x, y = y, instance = instance, wx = wx, wy = wy }
end

-- Offset from `from` to `to` in yards, as (north, east). nil across continents.
function Stones:Offset(from, to)
	if not from or not to or from.instance ~= to.instance then return nil end
	return to.wx - from.wx, from.wy - to.wy
end

function Stones:Distance(from, to)
	local north, east = self:Offset(from, to)
	if not north then return nil end
	return math.sqrt(north * north + east * east)
end

function Stones:Bearing(from, to)
	local north, east = self:Offset(from, to)
	if not north then return "" end
	local deg = math.deg(math.atan2(east, north)) % 360
	return COMPASS[math.floor((deg + 22.5) / 45) % 8 + 1]
end

function Stones:IsReadable(stone, dist)
	return stone.mine or (dist ~= nil and dist <= ns.db.gateYards)
end

local function zoneName(mapID)
	local info = mapID and C_Map.GetMapInfo(mapID)
	return info and info.name or "somewhere"
end

local function newID()
	return format("%d-%04d", time(), math.random(0, 9999))
end

-- Dropping ------------------------------------------------------------------

function Stones:Add(stone)
	stone.id = stone.id or newID()
	stone.t = stone.t or time()
	table.insert(ns.db.stones, stone)
	ns.MinimapPins:Update()
	return stone
end

function Stones:Drop(text)
	text = strtrim(text or "")
	if text == "" then return end
	local here = self:GetPlayerLocation()
	if not here then
		ns.Print("The ground here won't take a stone.")
		return
	end
	here.text = text
	here.author = UnitName("player")
	here.mine = true
	here.heard = true
	self:Add(here)
	ns.Print(format("Stone left in %s (%.1f, %.1f).", zoneName(here.mapID), here.x * 100, here.y * 100))
end

-- Plants someone else's stone `yards` north of the player so the unlock loop
-- can be tried solo.
function Stones:DropTestStone(yards)
	local here = self:GetPlayerLocation()
	if not here then
		ns.Print("No map position here — try outdoors.")
		return
	end
	local stone = {
		text = TEST_MESSAGES[math.random(#TEST_MESSAGES)],
		author = "A stranger",
		instance = here.instance,
		wx = here.wx + yards,
		wy = here.wy,
		mapID = here.mapID,
		x = here.x,
		y = here.y,
	}
	local mapID, pos = C_Map.GetMapPosFromWorldPos(here.instance, CreateVector2D(stone.wx, stone.wy), here.mapID)
	if mapID and pos then
		stone.mapID = mapID
		stone.x, stone.y = pos:GetXY()
	end
	self:Add(stone)
	ns.Print(format("A stranger's stone sits %d yards north of you. Go read it.", yards))
end

-- Proximity trigger ---------------------------------------------------------

function Stones:StartProximity()
	if self.ticker then return end
	self.ticker = C_Timer.NewTicker(1, function() self:CheckProximity() end)
	self:CheckProximity()
end

-- Each stone sits in a zone relative to the player: "far", "near" (within
-- nearYards) or "read" (within gateYards). Crossing inward fires a cue; a
-- band of HYSTERESIS yards keeps a boundary from flickering.
local HYSTERESIS = 8
local zones = {} -- stone.id -> zone, this session only

local function zoneFor(dist, prev)
	local gate, near = ns.db.gateYards, ns.db.nearYards
	if dist <= gate or (prev == "read" and dist <= gate + HYSTERESIS) then return "read" end
	if dist <= near or (prev and prev ~= "far" and dist <= near + HYSTERESIS) then return "near" end
	return "far"
end

function Stones:CheckProximity()
	local here = self:GetPlayerLocation()
	local anyInRange, cueNear, cueRead = false, false, false
	if here then
		for _, stone in ipairs(ns.db.stones) do
			local dist = not stone.mine and self:Distance(here, stone)
			if dist then
				local prev = zones[stone.id]
				local zone = zoneFor(dist, prev)
				zones[stone.id] = zone
				if zone == "read" then
					anyInRange = true
					if prev ~= "read" then cueRead = true end
					if not stone.heard then
						stone.heard = true
						self:OnUnlock(stone)
					end
				elseif zone == "near" and (prev == nil or prev == "far") and not stone.heard then
					cueNear = true
				end
			else
				zones[stone.id] = nil
			end
		end
	end
	-- One sound per tick; being able to read outranks being close.
	if cueRead then
		ns.Cues:Play("read")
	elseif cueNear then
		ns.Cues:Play("near")
		UIErrorsFrame:AddMessage("You sense a soapstone somewhere close.", 0.62, 0.83, 0.78)
	end
	ns.MinimapButton:SetGlow(anyInRange)
end

function Stones:OnUnlock(stone)
	UIErrorsFrame:AddMessage("A soapstone glows nearby.", 0.62, 0.83, 0.78)
	ns.Print(format("|cffffffff\"%s\"|r — %s", stone.text, stone.author or "?"))
end

-- Queries -------------------------------------------------------------------

-- Stones on the player's continent, nearest first, as { stone, dist } pairs.
function Stones:Nearby()
	local here = self:GetPlayerLocation()
	local list = {}
	if not here then return list, nil end
	for _, stone in ipairs(ns.db.stones) do
		local dist = self:Distance(here, stone)
		if dist then table.insert(list, { stone = stone, dist = dist }) end
	end
	table.sort(list, function(a, b) return a.dist < b.dist end)
	return list, here
end

function Stones:PrintNearby()
	local list, here = self:Nearby()
	if #list == 0 then
		ns.Print("No stones on this continent.")
		return
	end
	for i = 1, math.min(#list, 10) do
		local stone, dist = list[i].stone, list[i].dist
		local where = dist < 3 and "here" or format("%d yd %s", dist, self:Bearing(here, stone))
		if self:IsReadable(stone, dist) then
			ns.Print(format("%s — |cffffffff\"%s\"|r", where, stone.text))
		else
			ns.Print(format("%s — |cff888888sealed|r", where))
		end
	end
end
