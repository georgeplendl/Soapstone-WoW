-- "Guide me there" (Guide.lua): TomTom's arrow when TomTom is installed, the
-- game's own map pin otherwise, plain directions as a last resort; and the
-- waypoint going away on arrival without touching a pin the player set.
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

function CreateVector2D(x, y)
	return { x = x, y = y, GetXY = function(v) return v.x, v.y end }
end

-- The Barrens (1413) is a 1000-yard square on instance 1; 9001 is a cave in it.
local player = { x = 0.1, y = 0.1 }
C_Map = {
	GetMapInfo = function(id)
		if id == 9001 then return { mapType = 5, parentMapID = 1413 } end
		return { mapType = 3 }
	end,
	GetBestMapForUnit = function() return 1413 end,
	GetPlayerMapPosition = function() return CreateVector2D(player.x, player.y) end,
	GetWorldPosFromMapPos = function(mapID, pos)
		if mapID ~= 1413 then return nil end
		return 1, CreateVector2D(pos.x * 1000, pos.y * 1000)
	end,
	GetMapPosFromWorldPos = function(instance, world, mapID)
		if instance ~= 1 or mapID ~= 1413 then return nil end
		return mapID, CreateVector2D(world.x / 1000, world.y / 1000)
	end,
}

local printed = {}
local ns = {}
assert(loadfile(ROOT .. "/Identity.lua"))("Soapstone", ns)
assert(loadfile(ROOT .. "/Store.lua"))("Soapstone", ns)
assert(loadfile(ROOT .. "/Stones.lua"))("Soapstone", ns)
assert(loadfile(ROOT .. "/WorldMapPins.lua"))("Soapstone", ns)
assert(loadfile(ROOT .. "/Guide.lua"))("Soapstone", ns)
ns.Print = function(msg) printed[#printed + 1] = msg end
ns.db = { stones = {}, zones = {}, outbox = {}, gateYards = 40, nearYards = 150 }
ns.Cues = { Play = function() end }
ns.MinimapPins = { Update = function() end }
ns.MinimapButton = { SetGlow = function() end }
ns.ReadWindow = { Current = function() return nil end }
ns.Sync = { OnZone = function() end }
local Store, Stones, Guide = ns.Store, ns.Stones, ns.Guide
Store:Init()
local function last() return printed[#printed] or "" end

local function put(id, author, wx, wy, fields)
	local s = { id = id, authorKey = author, author = (author:gsub("%-", " ", 1)), instance = 1,
		wx = wx, wy = wy, mapID = 9001, x = 0.42, y = 0.42, t = NOW, text = "hi" }
	for k, v in pairs(fields or {}) do s[k] = v end
	return Store:Put(s)
end
local far = put("Zug-Zug-1-1", "Zug-Zug", 500, 500)      -- 566 yd away
local near = put("Zug-Zug-1-2", "Zug-Zug", 300, 300)     -- 283 yd away
local read = put("Zug-Zug-1-3", "Zug-Zug", 150, 150, { heard = true })
local mine = put("Mad-Decent-1-1", "Mad-Decent", 120, 120)

-- No TomTom, no waypoint API: directions only --------------------------------------
check(Guide.Method(1413) == nil, "with neither TomTom nor the game's waypoint, there's no marker")
Guide:To(far)
check(last() == "A sealed soapstone: 566 yd to the north-west.", "it says which way to go")
check(Guide:Current() == nil, "and nothing is being tracked")

-- The game's own waypoint ----------------------------------------------------------
local userPin, superTracked
UiMapPoint = { CreateFromCoordinates = function(mapID, x, y)
	return { uiMapID = mapID, position = CreateVector2D(x, y) }
end }
C_Map.CanSetUserWaypointOnMap = function(mapID) return mapID == 1413 end
C_Map.SetUserWaypoint = function(point) userPin = point end
C_Map.HasUserWaypoint = function() return userPin ~= nil end
C_Map.GetUserWaypoint = function() return userPin end
C_Map.ClearUserWaypoint = function() userPin = nil end
C_SuperTrack = { SetSuperTrackedUserWaypoint = function(on) superTracked = on end }

check(Guide.Method(1413) == "map" and Guide.Method(9001) == nil, "the game's waypoint, on maps that allow it")
Guide:To(far)
check(userPin and userPin.uiMapID == 1413, "the pin goes on the zone map, not the cave the stone was dropped in")
check(math.abs(userPin.position.x - 0.5) < 1e-9 and math.abs(userPin.position.y - 0.5) < 1e-9, "at the stone")
check(superTracked == true, "with the in-world marker turned on")
check(last():find("^Marked a sealed soapstone on your map, 566 yd") ~= nil, "and says so")
check(Guide:Current() == far, "it's being guided to")

Guide:Check(Stones:GetPlayerLocation())
check(userPin ~= nil, "still far away: the pin stays")
player.x, player.y = 0.5, 0.48 -- 20 yards off
Stones:CheckProximity()
check(userPin == nil and Guide:Current() == nil, "arriving clears it")

player.x, player.y = 0.1, 0.1
Guide:To(far)
userPin = UiMapPoint.CreateFromCoordinates(1413, 0.9, 0.9) -- the player puts their own pin somewhere
Guide:Clear()
check(userPin and userPin.position.x == 0.9, "a pin the player set since is never cleared")
check(Guide:Current() == nil, "though we stop guiding")

userPin = nil
Guide:To(near)
Store:Tombstone(near)
Guide:Check(Stones:GetPlayerLocation())
check(userPin == nil and Guide:Current() == nil, "a stone deleted on the way ends the guide")

-- TomTom ---------------------------------------------------------------------------
local added, removed = {}, {}
TomTom = {}
function TomTom:AddWaypoint(mapID, x, y, opts)
	local uid = { mapID, x, y, title = opts.title, opts = opts }
	added[#added + 1] = uid
	return uid
end
function TomTom:IsValidWaypoint(uid)
	for _, r in ipairs(removed) do if r == uid then return false end end
	return true
end
function TomTom:RemoveWaypoint(uid) removed[#removed + 1] = uid end

check(Guide.Method(1413) == "tomtom" and Guide.Method(9001) == "tomtom", "TomTom wins whenever it's installed")
check(far.heard, "(the walk above unlocked the far stone)")
local fresh = put("Zug-Zug-1-5", "Zug-Zug", 500, 600) -- still sealed, 640 yd away
userPin = nil
Guide:To(fresh)
local uid = added[1]
check(uid and uid[1] == 1413 and math.abs(uid[2] - 0.5) < 1e-9 and math.abs(uid[3] - 0.6) < 1e-9,
	"a TomTom waypoint at the stone, on its zone map")
check(userPin == nil, "and the game's pin is left alone")
local o = uid.opts
check(o.title == "A sealed soapstone" and o.from == "Soapstone", "titled, and says it came from Soapstone")
check(o.crazy == true and o.silent == true, "with the arrow on and no chat spam from TomTom")
check(o.persistent == false and o.minimap == false and o.world == false,
	"not kept across sessions, and no extra map icons (Soapstone draws its own)")
check(o.cleardistance == 40 and o.arrivaldistance == 40, "TomTom clears it within reading range")
check(last():find("^TomTom's arrow points to a sealed soapstone, 640 yd") ~= nil, "and says so")

Guide:To(read)
check(#removed == 1 and removed[1] == uid, "guiding somewhere else removes the old waypoint")
check(added[2].title == "A soapstone", "read stones get a plain title")
Guide:To(mine)
check(added[3].title == "Your soapstone", "and your own say so")

-- TomTom cleared it itself on arrival: nothing to remove twice.
removed[#removed + 1] = added[3]
local before = #removed
Guide:Clear()
check(#removed == before, "a waypoint TomTom already cleared isn't removed again")

-- /soap guide ----------------------------------------------------------------------
local unsealed = put("Zug-Zug-1-4", "Zug-Zug", 400, 400)
Guide:Command("")
check(Guide:Current() == unsealed, "/soap guide picks the nearest sealed stone (not read, not yours)")
Guide:Command("OFF")
check(Guide:Current() == nil and last() == "Stopped guiding.", "/soap guide off stops")
Guide:Command("off")
check(last() == "Not guiding you anywhere.", "and says so when there's nothing to stop")
Stones:Vote(unsealed, Stones.DISPARAGE)
Stones:Vote(fresh, Stones.DISPARAGE)
Guide:Command("")
check(Guide:Current() == nil and last() == "No sealed soapstones on this continent to head for.",
	"disparaged stones are skipped, and it says when nothing's left")

done()
