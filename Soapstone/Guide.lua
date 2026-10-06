local _, ns = ...

-- "Guide me there": a waypoint to a stone, from clicking its pin or
-- /soap guide. Uses TomTom's arrow when TomTom is installed, since many
-- players already rely on it; otherwise the game's own map pin and in-world
-- marker, where this client has them; otherwise it just says which way to go.
--
-- Only one stone is guided to at a time. The waypoint goes away once you're
-- close enough to read the stone. The game's map pin is the player's own
-- (there's only one), so it's only cleared if it's still the one we set.

local Guide = {}
ns.Guide = Guide

local current -- { stone, via = "tomtom" | "map", uid (TomTom), mapID, x, y }

-- The stone's position on its zone map, which TomTom and the game's
-- waypoint both handle best; falls back to the map it was dropped on (a
-- cave, say).
local function zonePoint(stone)
	if stone.zone and stone.instance and stone.wx then
		local _, pos = C_Map.GetMapPosFromWorldPos(stone.instance, CreateVector2D(stone.wx, stone.wy), stone.zone)
		if pos then
			local x, y = pos:GetXY()
			if x and x >= 0 and x <= 1 and y >= 0 and y <= 1 then return stone.zone, x, y end
		end
	end
	return stone.mapID, stone.x, stone.y
end

local function title(stone)
	if ns.Store.IsMine(stone) then return "Your soapstone" end
	return stone.heard and "A soapstone" or "A sealed soapstone"
end

function Guide.HasTomTom()
	return type(TomTom) == "table" and type(TomTom.AddWaypoint) == "function"
end

-- How a guide would be shown here: "tomtom", "map" or nil (directions only).
function Guide.Method(mapID)
	if Guide.HasTomTom() then return "tomtom" end
	if C_Map.SetUserWaypoint and UiMapPoint and mapID
		and (not C_Map.CanSetUserWaypointOnMap or C_Map.CanSetUserWaypointOnMap(mapID)) then
		return "map"
	end
	return nil
end

function Guide:Current()
	return current and current.stone
end

function Guide:To(stone)
	if not stone then return end
	self:Clear()
	local mapID, x, y = zonePoint(stone)
	local method = Guide.Method(mapID)
	local where = ns.WorldMapPins.Whereabouts(stone)

	if method == "tomtom" then
		local uid = TomTom:AddWaypoint(mapID, x, y, {
			title = title(stone),
			from = "Soapstone",
			persistent = false, -- stones come and go; don't keep it across sessions
			minimap = false,    -- Soapstone draws its own pins
			world = false,
			crazy = true,       -- the arrow is the point
			silent = true,
			cleardistance = ns.db.gateYards,
			arrivaldistance = ns.db.gateYards,
		})
		current = { stone = stone, via = "tomtom", uid = uid }
		ns.Print(format("TomTom's arrow points to %s%s.", title(stone):lower(), where and (", " .. where) or ""))
	elseif method == "map" then
		C_Map.SetUserWaypoint(UiMapPoint.CreateFromCoordinates(mapID, x, y))
		if C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then
			C_SuperTrack.SetSuperTrackedUserWaypoint(true)
		end
		current = { stone = stone, via = "map", mapID = mapID, x = x, y = y }
		ns.Print(format("Marked %s on your map%s.", title(stone):lower(), where and (", " .. where) or ""))
	else
		ns.Print(format("%s: %s.", title(stone), where or "somewhere on another map"))
	end
end

-- Whether the game's map pin is still the one `guide` set. The game hands the
-- position back as a plain { x, y } table, not a vector with GetXY.
local function ourMapPin(guide)
	if not (C_Map.HasUserWaypoint and C_Map.HasUserWaypoint()) then return false end
	local point = C_Map.GetUserWaypoint()
	local pos = point and point.position
	if not pos or point.uiMapID ~= guide.mapID or not pos.x or not pos.y then return false end
	return math.abs(pos.x - guide.x) < 0.0001 and math.abs(pos.y - guide.y) < 0.0001
end

function Guide:Clear()
	local guide = current
	if not guide then return end
	current = nil -- first, so a failure below can't leave it repeating every tick
	if guide.via == "tomtom" then
		if guide.uid and Guide.HasTomTom() and TomTom:IsValidWaypoint(guide.uid) then
			TomTom:RemoveWaypoint(guide.uid)
		end
	elseif guide.via == "map" and ourMapPin(guide) then
		C_Map.ClearUserWaypoint()
	end
end

-- Every proximity tick: arriving (or the stone vanishing) ends the guide.
function Guide:Check(here)
	if not current then return end
	local stone = current.stone
	if not ns.Store.IsLive(ns.Store:Get(stone.id) or { deleted = true }) then
		return self:Clear()
	end
	local dist = here and ns.Stones:Distance(here, stone)
	if dist and dist <= ns.db.gateYards then
		self:Clear()
	end
end

-- The nearest stone worth walking to: sealed, someone else's, not disparaged.
function Guide:NearestSealed()
	for _, entry in ipairs(ns.Stones:Nearby()) do
		local stone = entry.stone
		if not stone.heard and not ns.Store.IsMine(stone) and not ns.Stones:IsDisparaged(stone)
			and entry.dist > ns.db.gateYards then
			return stone
		end
	end
end

-- /soap guide [off]
function Guide:Command(rest)
	rest = (rest or ""):lower()
	if rest == "off" or rest == "stop" then
		if not current then return ns.Print("Not guiding you anywhere.") end
		self:Clear()
		return ns.Print("Stopped guiding.")
	end
	local stone = self:NearestSealed()
	if not stone then return ns.Print("No sealed soapstones on this continent to head for.") end
	self:To(stone)
end

-- The line pins add to their tooltips.
function Guide.Hint()
	return Guide.HasTomTom() and "Click: TomTom arrow to it" or "Click: guide me there"
end
