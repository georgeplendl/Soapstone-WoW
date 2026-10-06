local _, ns = ...

-- A stone is pinned to a world position. Map coordinates (0-1 within a zone map)
-- are kept for display; distances use world coordinates, which are in yards and
-- continuous across a continent. World X grows northward, world Y grows westward.
--
-- stone = { id, author ("Mad Decent"), authorKey ("Mad-Decent"), flavor,
--           t, mapID, x, y, instance, wx, wy, mine, heardBy (see Store.IsHeard), edited,
--           windowStart (when the edit window last restarted; defaults to t),
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

-- Appraise / disparage --------------------------------------------------------------
-- Every stone has a score. Anyone can appraise (+1) or disparage (-1) it;
-- pressing the same button again withdraws the judgement (0). Its author
-- starts out having appraised it, and may withdraw or even disparage their
-- own stone, but their own judgement only ever counts as 1 or 0: they can
-- take their appraisal away, not push the score below it. The score here is
-- what this client knows: the author's part plus judgements cast by your
-- characters on this account (a server would add everyone else's). On other
-- players' stones your judgement also changes what you see: appraised pins
-- turn gold, disparaged ones fade and stop calling you over.

Stones.APPRAISE, Stones.DISPARAGE = 1, -1

local function authorOf(stone)
	return stone.authorKey or (ns.Store.IsMine(stone) and ns.Identity.PlayerKey()) or nil
end

-- Your judgement of `stone`: 1, 0 or -1. Your own stones start at 1 (the
-- default isn't stored; 0 and -1 are).
function Stones:Rating(stone)
	if not stone then return 0 end
	local stored = ns.Store:MyRating(stone.id)
	if ns.Store.IsMine(stone) then return stored or 1 end
	return stored or 0
end

-- Your vote on someone else's stone (0 for your own), for pins and cues.
function Stones:OthersRating(stone)
	if not stone or ns.Store.IsMine(stone) then return 0 end
	return self:Rating(stone)
end

function Stones:IsDisparaged(stone)
	return self:OthersRating(stone) == self.DISPARAGE
end

function Stones:Score(stone)
	if not stone then return 0 end
	local author = authorOf(stone)
	local votes = ns.Store:Votes(stone.id)
	-- The author's part: 1 unless they withdrew (0) or disparaged (-1) it,
	-- which only takes their own appraisal away.
	local own = author and votes[author]
	local score = (own == 0 or own == -1) and 0 or 1
	for key, vote in pairs(votes) do
		if key ~= author then score = score + vote end
	end
	return score
end

-- Appraise (APPRAISE) or Disparage (DISPARAGE) was pressed. Returns your new
-- judgement: 1, 0 or -1.
function Stones:Vote(stone, which)
	if not stone or stone.deleted then return nil end
	local mine = ns.Store.IsMine(stone)
	local current = self:Rating(stone)
	local new = current == which and 0 or which -- the same button again withdraws
	if mine then
		ns.Store:Rate(stone.id, new ~= 1 and new or nil) -- your own default (1) isn't stored
	else
		ns.Store:Rate(stone.id, new ~= 0 and new or nil)
	end

	local who = stone.author or "a stranger"
	if new == self.APPRAISE then
		ns.Cues:Play("appraise")
		UIErrorsFrame:AddMessage(mine and "You appraised your own soapstone again."
			or format("You appraised %s's soapstone.", who), 1, 0.82, 0)
	elseif new == self.DISPARAGE then
		ns.Cues:Play("disparage")
		UIErrorsFrame:AddMessage(mine and "You disparaged your own soapstone. It keeps 0 of your appraisal."
			or format("You disparaged %s's soapstone.", who), 0.75, 0.6, 0.6)
	elseif current == self.DISPARAGE then
		UIErrorsFrame:AddMessage("You withdrew your disparagement.", 0.8, 0.8, 0.8)
	else
		UIErrorsFrame:AddMessage("You withdrew your appraisal.", 0.8, 0.8, 0.8)
	end
	if ns.MinimapPins then ns.MinimapPins:Update() end
	return new
end

function Stones:IsReadable(stone, dist)
	return ns.Store.IsMine(stone) or (dist ~= nil and dist <= ns.db.gateYards)
end

-- "just now", "1 min ago", "24 mins ago", "3 hrs ago", "5 days ago".
function Stones.TimeAgo(seconds)
	if seconds < 60 then return "just now" end
	local n, unit
	if seconds < 3600 then
		n, unit = math.floor(seconds / 60), "min"
	elseif seconds < 86400 then
		n, unit = math.floor(seconds / 3600), "hr"
	else
		n, unit = math.floor(seconds / 86400), "day"
	end
	return format("%d %s%s ago", n, unit, n == 1 and "" or "s")
end

-- "— Zug Zug, 3 hrs ago", or for your own "— Mad Decent (You), 24 mins ago",
-- plus " (edited)".
function Stones:Byline(stone)
	local age = time() - (stone.t or time())
	local who = stone.author or "A stranger"
	if ns.Store.IsMine(stone) then
		who = (stone.author or ns.Identity.PlayerDisplay() or "You") .. " (You)"
	end
	return format("— %s, %s%s", who, self.TimeAgo(age), stone.edited and " (edited)" or "")
end

-- Editing -------------------------------------------------------------------

-- The edit window: your own stones (written or drawn) can be edited or
-- deleted for EDIT_SECONDS. The clock
--   * starts when the stone is posted (windowStart, defaulting to the drop),
--   * restarts from a full EDIT_SECONDS whenever an edit is saved, and
--   * stands still while the edit dialog is open, so a slow edit costs
--     nothing; cancelling picks up where it paused.
Stones.EDIT_SECONDS = 5 * 60

local pausedAt = {} -- stone id -> time the editor opened (this session only)

-- Seconds left to edit `stone`; 0 when it can't (or can no longer) be.
function Stones:EditTimeLeft(stone)
	if not stone or stone.deleted or not ns.Store.IsMine(stone) then return 0 end
	if not stone.text and not stone.sketch then return 0 end
	local now = pausedAt[stone.id] or time()
	return math.max(0, (stone.windowStart or stone.t or 0) + self.EDIT_SECONDS - now)
end

-- The edit dialog opened: stop the clock.
function Stones:PauseEditClock(stone)
	if stone and not pausedAt[stone.id] and self:EditTimeLeft(stone) > 0 then
		pausedAt[stone.id] = time()
	end
end

-- The edit dialog closed without saving: carry on from where it paused.
function Stones:ResumeEditClock(stone)
	local at = stone and pausedAt[stone.id]
	if not at then return end
	stone.windowStart = (stone.windowStart or stone.t or 0) + (time() - at)
	pausedAt[stone.id] = nil
end

function Stones:IsEditClockPaused(stone)
	return stone ~= nil and pausedAt[stone.id] ~= nil
end

-- Saves an edit. `content` is { text = "..." } for a written stone or
-- { sketch = <packed> } for a drawing (a plain string counts as text); a
-- stone can't switch between the two. A real change bumps the version and
-- restarts the edit window. Returns true if the edit was accepted.
function Stones:Edit(stone, content)
	if type(content) == "string" then content = { text = content } end
	if self:EditTimeLeft(stone) <= 0 then
		ns.Print("Too late — the stone has set and can't be edited any more.")
		return false
	end
	local changed
	if stone.sketch then
		local packed = content.sketch
		local grid = packed and ns.Sketch.Unpack(packed)
		if not grid or ns.Sketch.IsEmpty(grid) then return false end
		changed = packed.data ~= stone.sketch.data
		if changed then stone.sketch = packed end
	else
		-- Stored with any pipes made plain, so the server never refuses it.
		local text = ns.Codec.Neutralize(strtrim(content.text or ""))
		if text == "" then return false end
		changed = text ~= stone.text
		if changed then stone.text = text end
	end
	pausedAt[stone.id] = nil
	if changed then
		stone.edited = time()
		stone.windowStart = time() -- a fresh five minutes
		stone.v = (stone.v or 1) + 1
		ns.Store:MarkChanged(stone.id)
		ns.Print("Stone updated.")
		if ns.ReadWindow:Current() == stone then ns.ReadWindow:Show(stone) end
	end
	return true
end

-- Removes one of your stones during its edit window. Returns true if deleted.
function Stones:Delete(stone)
	if self:EditTimeLeft(stone) <= 0 then
		ns.Print("Too late — the stone has set and can't be deleted any more.")
		return false
	end
	if ns.Store:Get(stone.id) ~= stone then return false end
	pausedAt[stone.id] = nil
	ns.Store:Tombstone(stone)
	if ns.ReadWindow:Current() == stone then ns.ReadWindow:Hide() end
	ns.MinimapPins:Update()
	ns.Cues:Play("delete")
	ns.Print("Stone deleted.")
	return true
end

-- A written stone's words. Stones from the database keep theirs scrambled
-- (Codec.Scramble) and are only unscrambled here, to be shown.
--
-- Whatever it says, it's shown as plain text: escape codes (|c, |H, |T...)
-- are neutralized, so a stone can't draw links, colours or textures.
function Stones.TextOf(stone)
	local text = stone.text or (stone.scrambled and ns.Codec.Unscramble(stone.id, stone.scrambled)) or nil
	return text and ns.Codec.Neutralize(text)
end

-- A drawing: carried here, or (from the database) only named by its sketch id.
function Stones.IsSketch(stone)
	return stone.sketch ~= nil or stone.sketchId ~= nil
end

-- The drawing itself: your own and other players' come with the stone; ones
-- from the database come from the companion while it runs (Sketches.lua).
function Stones.SketchOf(stone)
	if stone.sketch then return stone.sketch end
	return stone.sketchId and ns.Companion and ns.Companion.sketches[stone.sketchId] or nil
end

-- One-line description for chat and tooltips.
function Stones:Summary(stone)
	if Stones.IsSketch(stone) then return "a sketch" end
	return format("\"%s\"", Stones.TextOf(stone) or "")
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
	local text = content.text and ns.Codec.Neutralize(strtrim(content.text))
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
	here.heardBy = { [here.authorKey] = time() }
	self:Add(here)
	ns.Store:MarkChanged(here.id)
	ns.Cues:Play("drop")
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
-- (within nearYards) or "read" (within gateYards). Crossing into "near" plays
-- the "somewhere close" cue (reaching "read" is silent: the minimap button
-- glows instead); HYSTERESIS yards of slack keep a boundary from flickering. Stones not
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
	local anyInRange, cueNear = false, false
	local nextBands = {}
	if here then
		local zone = ns.Store.ZoneKey(here.mapID)
		if zone ~= self.zone then
			self.zone = zone
			ns.Store:Visit(zone)
			ns.Sync:OnZone(zone)
		end
		for _, stone in ipairs(ns.Store:Near(here, ns.db.nearYards + HYSTERESIS, nearby)) do
			-- Your own stones and ones you've disparaged never call you over.
			local dist = not ns.Store.IsMine(stone) and not self:IsDisparaged(stone) and self:Distance(here, stone)
			if dist then
				local prev = bands[stone.id]
				local band = bandFor(dist, prev)
				nextBands[stone.id] = band
				if band == "read" then
					anyInRange = true
					if not ns.Store.IsHeard(stone) then
						ns.Store:Unlock(stone)
						self:OnUnlock(stone)
					end
				elseif band == "near" and (prev == nil or prev == "far") and not ns.Store.IsHeard(stone) then
					cueNear = true
				end
			end
		end
	end
	bands = nextBands
	if cueNear then
		ns.Cues:Play("near")
		UIErrorsFrame:AddMessage("You sense a soapstone somewhere close.", 0.62, 0.83, 0.78)
	end
	ns.MinimapButton:SetGlow(anyInRange)
	ns.Guide:Check(here)

	-- An open stone goes silent once you walk out of range.
	local open = ns.ReadWindow:Current()
	if open and not self:IsReadable(open, self:Distance(here, open)) then
		ns.ReadWindow:Hide()
		UIErrorsFrame:AddMessage("The soapstone fades as you walk away.", 0.62, 0.83, 0.78)
	end
end

function Stones:OnUnlock(stone)
	UIErrorsFrame:AddMessage("A soapstone glows nearby.", 0.62, 0.83, 0.78)
	if Stones.IsSketch(stone) then
		ns.Print(format("%s left a sketch here. Click its minimap pin or type /soap read to see it.", stone.author or "Someone"))
	else
		ns.Print(format("|cffffffff\"%s\"|r — %s", Stones.TextOf(stone) or "", stone.author or "?"))
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
			local rating = self:OthersRating(stone)
			local mark = rating == self.APPRAISE and " |cffffd100(appraised)|r"
				or rating == self.DISPARAGE and " |cff888888(disparaged)|r" or ""
			ns.Print(format("%s — |cffffffff%s|r [%+d]%s", where, self:Summary(stone), self:Score(stone), mark))
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
