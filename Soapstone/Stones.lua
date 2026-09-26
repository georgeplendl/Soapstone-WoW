local _, ns = ...

-- A stone is pinned to a world position. Map coordinates (0-1 within a zone map)
-- are kept for display; distances use world coordinates, which are in yards and
-- continuous across a continent. World X grows northward, world Y grows westward.
--
-- stone = { id, author ("Mad Decent"), authorKey ("Mad-Decent"), flavor,
--           t, mapID, x, y, instance, wx, wy, mine, heard, edited,
--           text = "..." or sketch = <Sketch.Pack result> }

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
	return ns.Store.IsMine(stone) or (dist ~= nil and dist <= ns.db.gateYards)
end

-- "— Author, 3 hr ago" (or "just now" for the first minute), plus "(edited)".
function Stones:Byline(stone)
	local age = time() - (stone.t or time())
	local who = ns.Store.IsMine(stone) and "You" or (stone.author or "A stranger")
	local when = age < 60 and "just now" or (SecondsToTime(age, true) .. " ago")
	return format("— %s, %s%s", who, when, stone.edited and " (edited)" or "")
end

-- Editing -------------------------------------------------------------------

-- How long after dropping a stone its author may still reword it.
Stones.EDIT_SECONDS = 5 * 60

-- Seconds left to edit `stone`: only your own written stones, counted from
-- when they were dropped. 0 when it can't (or can no longer) be edited.
function Stones:EditTimeLeft(stone)
	if not stone or stone.deleted or not ns.Store.IsMine(stone) or not stone.text or stone.sketch then return 0 end
	return math.max(0, (stone.t or 0) + self.EDIT_SECONDS - time())
end

-- Rewords a written stone. Returns true if it changed.
function Stones:Edit(stone, text)
	text = strtrim(text or "")
	if text == "" then return false end
	if self:EditTimeLeft(stone) <= 0 then
		ns.Print("Too late — the stone has set and can't be edited any more.")
		return false
	end
	if text ~= stone.text then
		stone.text = text
		stone.edited = time()
		stone.v = (stone.v or 1) + 1
		ns.Store:MarkChanged(stone.id)
		ns.Print("Stone updated.")
		if ns.ReadWindow:Current() == stone then ns.ReadWindow:Show(stone) end
	end
	return true
end

-- Removes a written stone during its edit window. Returns true if deleted.
function Stones:Delete(stone)
	if self:EditTimeLeft(stone) <= 0 then
		ns.Print("Too late — the stone has set and can't be deleted any more.")
		return false
	end
	if ns.Store:Get(stone.id) ~= stone then return false end
	ns.Store:Tombstone(stone)
	if ns.ReadWindow:Current() == stone then ns.ReadWindow:Hide() end
	ns.MinimapPins:Update()
	ns.Print("Stone deleted.")
	return true
end

-- One-line description for chat and tooltips.
function Stones:Summary(stone)
	if stone.sketch then return "a sketch" end
	return format("\"%s\"", stone.text or "")
end

local function zoneName(mapID)
	local info = mapID and C_Map.GetMapInfo(mapID)
	return info and info.name or "somewhere"
end

-- Your stones get "Mad-Decent-<time>-<n>": unique across all players, since
-- the author key is. Anything else (test stones) gets a local-only id.
local dropCount = 0
local function newID(stone)
	dropCount = dropCount + 1
	if stone.authorKey then
		return format("%s-%d-%d", stone.authorKey, time(), dropCount)
	end
	return format("local-%d-%04d", time(), math.random(0, 9999))
end

-- Stones dropped before names were stored in full say just "Mad". Relabel
-- the ones that are yours as "Mad Decent" / "Mad-Decent".
function Stones:AdoptOwnStones()
	local short, display, key = UnitName("player"), ns.Identity.PlayerDisplay(), ns.Identity.PlayerKey()
	local count = 0
	for _, stone in ns.Store:Each() do
		if stone.mine and not stone.authorKey and stone.author == short then
			stone.author, stone.authorKey = display, key
			count = count + 1
		end
	end
	if count > 0 then
		ns.Print(format("Signed %d of your earlier stones as %s.", count, display))
	end
end

-- Dropping ------------------------------------------------------------------

function Stones:Add(stone)
	stone.id = stone.id or newID(stone)
	stone.t = stone.t or time()
	ns.Store:Put(stone)
	ns.MinimapPins:Update()
	return stone
end

-- Drops a stone at the player's feet. `content` is { text = "..." } or
-- { sketch = <packed sketch> }. Returns the stone, or nil if nothing dropped.
function Stones:Drop(content)
	local text = content.text and strtrim(content.text)
	if text == "" then text = nil end
	if not text and not content.sketch then return nil end
	local here = self:GetPlayerLocation()
	if not here then
		ns.Print("The ground here won't take a stone.")
		return nil
	end
	here.text = text
	here.sketch = not text and content.sketch or nil
	here.author = ns.Identity.PlayerDisplay()
	here.authorKey = ns.Identity.PlayerKey()
	here.flavor = ns.Identity.Flavor()
	here.mine = true
	here.heard = true
	self:Add(here)
	ns.Store:MarkChanged(here.id)
	ns.Print(format("%s left in %s (%.1f, %.1f).", here.sketch and "Sketch" or "Stone",
		zoneName(here.mapID), here.x * 100, here.y * 100))
	return here
end

-- Plants someone else's stone `yards` north of the player so the unlock loop
-- can be tried solo.
function Stones:DropTestStone(yards)
	local here = self:GetPlayerLocation()
	if not here then
		ns.Print("No map position here — try outdoors.")
		return
	end
	-- Half the strangers draw instead of write.
	local sketch = math.random(2) == 1
	local stone = {
		text = not sketch and TEST_MESSAGES[math.random(#TEST_MESSAGES)] or nil,
		sketch = sketch and ns.Sketch.Pack(ns.Sketch.Sun()) or nil,
		author = "A stranger",
		localOnly = true, -- a test stone: never shared
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
	ns.Print(format("A stranger's %s sits %d yards north of you. Go find it.", sketch and "sketch" or "stone", yards))
end

-- Proximity trigger ---------------------------------------------------------

function Stones:StartProximity()
	if self.ticker then return end
	self.ticker = C_Timer.NewTicker(1, function() self:CheckProximity() end)
	self:CheckProximity()
end

-- Each nearby stone sits in a band relative to the player: "far", "near"
-- (within nearYards) or "read" (within gateYards). Crossing inward fires a
-- cue; HYSTERESIS yards of slack keep a boundary from flickering. Stones not
-- looked at this tick drop out, so coming back counts as arriving again.
local HYSTERESIS = 8
local bands = {} -- stone.id -> band, rebuilt every tick
local nearby = {} -- scratch list for Store:Near

local function bandFor(dist, prev)
	local gate, near = ns.db.gateYards, ns.db.nearYards
	if dist <= gate or (prev == "read" and dist <= gate + HYSTERESIS) then return "read" end
	if dist <= near or (prev and prev ~= "far" and dist <= near + HYSTERESIS) then return "near" end
	return "far"
end

function Stones:CheckProximity()
	local here = self:GetPlayerLocation()
	local anyInRange, cueNear, cueRead = false, false, false
	local nextBands = {}
	if here then
		local zone = ns.Store.ZoneKey(here.mapID)
		if zone ~= self.zone then
			self.zone = zone
			ns.Store:Visit(zone)
			ns.Sync:OnZone(zone)
		end
		for _, stone in ipairs(ns.Store:Near(here, ns.db.nearYards + HYSTERESIS, nearby)) do
			local dist = not ns.Store.IsMine(stone) and self:Distance(here, stone)
			if dist then
				local prev = bands[stone.id]
				local band = bandFor(dist, prev)
				nextBands[stone.id] = band
				if band == "read" then
					anyInRange = true
					if prev ~= "read" then cueRead = true end
					if not stone.heard then
						stone.heard = true
						self:OnUnlock(stone)
					end
				elseif band == "near" and (prev == nil or prev == "far") and not stone.heard then
					cueNear = true
				end
			end
		end
	end
	bands = nextBands
	-- One sound per tick; being able to read outranks being close.
	if cueRead then
		ns.Cues:Play("read")
	elseif cueNear then
		ns.Cues:Play("near")
		UIErrorsFrame:AddMessage("You sense a soapstone somewhere close.", 0.62, 0.83, 0.78)
	end
	ns.MinimapButton:SetGlow(anyInRange)

	-- An open stone goes silent once you walk out of range.
	local open = ns.ReadWindow:Current()
	if open and not self:IsReadable(open, self:Distance(here, open)) then
		ns.ReadWindow:Hide()
		UIErrorsFrame:AddMessage("The soapstone fades as you walk away.", 0.62, 0.83, 0.78)
	end
end

function Stones:OnUnlock(stone)
	UIErrorsFrame:AddMessage("A soapstone glows nearby.", 0.62, 0.83, 0.78)
	if stone.sketch then
		ns.Print(format("%s left a sketch here. Click its minimap pin or type /soap read to see it.", stone.author or "Someone"))
	else
		ns.Print(format("|cffffffff\"%s\"|r — %s", stone.text or "", stone.author or "?"))
	end
end

-- Queries -------------------------------------------------------------------

-- Stones on the player's continent, nearest first, as { stone, dist } pairs.
function Stones:Nearby()
	local here = self:GetPlayerLocation()
	local list = {}
	if not here then return list, nil end
	for _, stone in ns.Store:Each() do
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
			ns.Print(format("%s — |cffffffff%s|r", where, self:Summary(stone)))
		else
			ns.Print(format("%s — |cff888888sealed|r", where))
		end
	end
end

-- Opens the nearest stone you can read from here (your own always count).
function Stones:ReadNearest()
	for _, entry in ipairs(self:Nearby()) do
		if self:IsReadable(entry.stone, entry.dist) then
			ns.ReadWindow:Show(entry.stone)
			return
		end
	end
	ns.Print("No stone close enough to read.")
end
