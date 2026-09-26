local _, ns = ...

-- All stone data lives here (sharing step 2, "data model"; see
-- docs/Sharing - Architecture.md).
--
-- SoapstoneDB (schema 2):
--   stones  = { [id] = stone }      live stones and tombstones, keyed by id
--   zones   = { [zone] = { visited = time } }   for least-recently-visited eviction
--   outbox  = { [id] = true }       your changes not yet announced (step 4)
--   ratings = { [id] = { [characterKey] = 1 | -1 } }   appraise / disparage
--
-- stone = { id, v (version, edits bump it), flavor, zone (zone-level uiMapID),
--           instance, wx, wy (world yards), mapID, x, y (map 0-1), t (dropped),
--           author, authorKey, text | sketch, edited, heard,
--           localOnly (test stones, never shared), via / verified (step 3) }
-- tombstone = { id, v, deleted = true, deletedAt, zone, flavor, authorKey }
--
-- A runtime spatial index (CELL-yard squares per continent) lets the minimap
-- and proximity checks look only at nearby stones, across zone borders.

local Store = {}
ns.Store = Store

Store.SCHEMA = 2
Store.CELL = 500                    -- yards per spatial-index cell
Store.MAX_PER_ZONE = 200            -- other players' stones kept per zone
Store.MAX_TOTAL = 5000              -- other players' stones kept overall
Store.TOMBSTONE_TTL = 7 * 24 * 3600 -- deleted stones remembered this long

local ZONE_TYPE = (Enum and Enum.UIMapType and Enum.UIMapType.Zone) or 3

local cells = {} -- "instance:cx:cy" -> { [id] = stone } (live stones only)

local function db() return ns.db end

-- Keys ------------------------------------------------------------------------

local zoneCache = {}

-- The zone-level map a map belongs to: climb from dungeon/micro/orphan maps
-- to their parent until reaching a Zone (or anything above one).
function Store.ZoneKey(mapID)
	if not mapID then return nil end
	local cached = zoneCache[mapID]
	if cached then return cached end
	local id = mapID
	for _ = 1, 10 do
		local info = C_Map.GetMapInfo(id)
		if not info or info.mapType <= ZONE_TYPE or not info.parentMapID or info.parentMapID == 0 then break end
		id = info.parentMapID
	end
	zoneCache[mapID] = id
	return id
end

-- Yours = written by this character. Stones from before names were stored in
-- full have no authorKey; fall back to their old account-wide flag.
function Store.IsMine(stone)
	if stone.authorKey then return stone.authorKey == ns.Identity.PlayerKey() end
	return stone.mine == true
end

-- Live, and from this game (Forever / Retail / Classic never mix).
function Store.IsLive(stone)
	return not stone.deleted and (stone.flavor == nil or stone.flavor == ns.Identity.Flavor())
end

-- Spatial index -------------------------------------------------------------

local function cellKey(instance, cx, cy)
	return instance .. ":" .. cx .. ":" .. cy
end

local function cellOf(stone)
	return cellKey(stone.instance, math.floor(stone.wx / Store.CELL), math.floor(stone.wy / Store.CELL))
end

local function index(stone)
	if not Store.IsLive(stone) or not stone.wx or not stone.instance then return end
	local key = cellOf(stone)
	local cell = cells[key]
	if not cell then
		cell = {}
		cells[key] = cell
	end
	cell[stone.id] = stone
end

local function unindex(stone)
	if not stone.wx or not stone.instance then return end
	local cell = cells[cellOf(stone)]
	if cell then cell[stone.id] = nil end
end

-- Live stones on `loc`'s continent within a square of `range` yards around
-- it (callers check exact distance). Fills and returns `out` if given.
function Store:Near(loc, range, out)
	out = out or {}
	wipe(out)
	if not loc or not loc.wx then return out end
	local x0, x1 = math.floor((loc.wx - range) / self.CELL), math.floor((loc.wx + range) / self.CELL)
	local y0, y1 = math.floor((loc.wy - range) / self.CELL), math.floor((loc.wy + range) / self.CELL)
	for cx = x0, x1 do
		for cy = y0, y1 do
			local cell = cells[cellKey(loc.instance, cx, cy)]
			if cell then
				for _, stone in pairs(cell) do out[#out + 1] = stone end
			end
		end
	end
	return out
end

-- Access --------------------------------------------------------------------

function Store:Get(id)
	return db().stones[id]
end

-- Iterates live stones from this game: for id, stone in Store:Each() do.
function Store:Each()
	local stones = db().stones
	local id, stone
	return function()
		repeat
			id, stone = next(stones, id)
		until id == nil or Store.IsLive(stone)
		return id, stone
	end
end

-- Adds or replaces a stone, filling in version, game and zone.
function Store:Put(stone)
	local old = db().stones[stone.id]
	if old then unindex(old) end
	stone.v = stone.v or 1
	stone.flavor = stone.flavor or ns.Identity.Flavor()
	stone.zone = stone.zone or Store.ZoneKey(stone.mapID)
	db().stones[stone.id] = stone
	index(stone)
	return stone
end

-- Forgets a stone outright (eviction); not the same as deleting one.
function Store:Remove(id)
	local stone = db().stones[id]
	if not stone then return end
	unindex(stone)
	db().stones[id] = nil
	db().ratings[id] = nil
end

-- Deletes a stone: keeps a tombstone at a higher version, so a stale copy
-- from someone else can't bring it back.
function Store:Tombstone(stone)
	unindex(stone)
	db().stones[stone.id] = {
		id = stone.id,
		v = (stone.v or 1) + 1,
		t = stone.t,
		deleted = true,
		deletedAt = time(),
		zone = stone.zone,
		flavor = stone.flavor,
		authorKey = stone.authorKey,
	}
	self:MarkChanged(stone.id)
end

-- Your stone changed (dropped, edited, deleted): announce it in step 4.
function Store:MarkChanged(id)
	db().outbox[id] = true
end

function Store:Visit(zone)
	if zone then db().zones[zone] = { visited = time() } end
end

function Store:Clear()
	wipe(db().stones)
	wipe(db().outbox)
	wipe(db().ratings)
	wipe(cells)
end

-- Upkeep --------------------------------------------------------------------

-- Keeps other players' stones within MAX_PER_ZONE (newest win) and MAX_TOTAL
-- (least recently visited zones go first). Your own stones are never
-- evicted. Returns how many were removed.
function Store:Enforce()
	local byZone, foreign, removed = {}, 0, 0
	for _, stone in self:Each() do
		if not Store.IsMine(stone) then
			local zone = stone.zone or 0
			byZone[zone] = byZone[zone] or {}
			table.insert(byZone[zone], stone)
			foreign = foreign + 1
		end
	end
	local newestFirst = function(a, b) return (a.t or 0) > (b.t or 0) end
	for _, list in pairs(byZone) do
		table.sort(list, newestFirst)
		for i = #list, self.MAX_PER_ZONE + 1, -1 do
			self:Remove(list[i].id)
			list[i] = nil
			removed, foreign = removed + 1, foreign - 1
		end
	end
	if foreign > self.MAX_TOTAL then
		local zonesByAge = {}
		for zone in pairs(byZone) do zonesByAge[#zonesByAge + 1] = zone end
		local visited = function(zone) return (db().zones[zone] or {}).visited or 0 end
		table.sort(zonesByAge, function(a, b) return visited(a) < visited(b) end)
		for _, zone in ipairs(zonesByAge) do
			local list = byZone[zone]
			for i = #list, 1, -1 do -- oldest stones in the stalest zone first
				if foreign <= self.MAX_TOTAL then break end
				self:Remove(list[i].id)
				removed, foreign = removed + 1, foreign - 1
			end
			if foreign <= self.MAX_TOTAL then break end
		end
	end
	return removed
end

function Store:PruneTombstones()
	local cutoff = time() - self.TOMBSTONE_TTL
	local stones, doomed = db().stones, {}
	for id, stone in pairs(stones) do
		if stone.deleted and (stone.deletedAt or 0) < cutoff then doomed[#doomed + 1] = id end
	end
	for _, id in ipairs(doomed) do
		stones[id] = nil
		db().outbox[id] = nil
		db().ratings[id] = nil
	end
	return #doomed
end

-- Ratings -------------------------------------------------------------------------
-- Appraise (+1) or disparage (-1): one rating per stone per character, kept in
-- db.ratings[id][characterKey], apart from the stone record, so a fresh copy
-- of a stone (from sync or, later, a server) never wipes your rating.

function Store:MyRating(id)
	local ratings = db().ratings[id]
	return ratings and ratings[ns.Identity.PlayerKey()] or nil
end

-- Every vote cast on this account for `id`: { [characterKey] = 1 | 0 | -1 }.
function Store:Votes(id)
	return db().ratings[id] or {}
end

-- value: 1, -1, 0 (an author taking back their own upvote), or nil to clear.
function Store:Rate(id, value)
	local ratings = db().ratings[id] or {}
	ratings[ns.Identity.PlayerKey()] = value
	db().ratings[id] = next(ratings) and ratings or nil
end

-- Sync view -------------------------------------------------------------------
-- What Sync.lua compares and trades. A zone's shareable stones (tombstones
-- included, so deletions spread) are split into BUCKETS by id; each bucket's
-- fingerprint is an order-independent sum of hash("id:v"). Two players swap
-- the 16 fingerprints and only list the buckets that differ.

Store.BUCKETS = 16

-- Shareable: from this game, not a local test stone, and with a known
-- author (stones from before names were stored in full have none).
function Store.IsShareable(stone)
	return not stone.localOnly and stone.authorKey ~= nil
		and (stone.flavor == nil or stone.flavor == ns.Identity.Flavor())
end

local function bucketOf(id)
	return ns.Codec.Hash(id) % Store.BUCKETS + 1
end

-- Shareable stones and tombstones in `zone`.
function Store:ZoneEntries(zone)
	local list = {}
	for _, stone in pairs(db().stones) do
		if stone.zone == zone and Store.IsShareable(stone) then list[#list + 1] = stone end
	end
	return list
end

-- Per-bucket fingerprints for `zone`, and the number of entries.
function Store:Buckets(zone)
	local sums, count = {}, 0
	for b = 1, self.BUCKETS do sums[b] = 0 end
	for _, stone in ipairs(self:ZoneEntries(zone)) do
		local b = bucketOf(stone.id)
		sums[b] = (sums[b] + ns.Codec.Hash(stone.id .. ":" .. (stone.v or 1))) % 16777216
		count = count + 1
	end
	return sums, count
end

-- The 16 fingerprints as one 96-character string, and back.
function Store.EncodeBuckets(sums)
	local parts = {}
	for b = 1, Store.BUCKETS do parts[b] = ns.Codec.Hex6(sums[b]) end
	return table.concat(parts)
end

function Store.DecodeBuckets(s)
	if type(s) ~= "string" or #s ~= Store.BUCKETS * 6 or s:find("[^0-9a-f]") then return nil end
	local sums = {}
	for b = 1, Store.BUCKETS do sums[b] = tonumber(s:sub(b * 6 - 5, b * 6), 16) end
	return sums
end

-- One short fingerprint for the whole zone, plus its entry count.
function Store:ZoneDigest(zone)
	local sums, count = self:Buckets(zone)
	return ns.Codec.Hex6(ns.Codec.Hash(Store.EncodeBuckets(sums))), count
end

-- "id:v" for every entry of `zone` in the buckets marked true in `wanted`.
function Store:BucketEntries(zone, wanted)
	local out = {}
	for _, stone in ipairs(self:ZoneEntries(zone)) do
		if wanted[bucketOf(stone.id)] then out[#out + 1] = stone.id .. ":" .. (stone.v or 1) end
	end
	return out
end

-- Takes a stone (or tombstone) decoded from another player. `viaKey` is who
-- sent it. Rules:
--   * your own stones are never overwritten; you're their only source
--   * only a newer version replaces what you have
--   * changing or deleting a stone you already have must come first-hand
--     from its author (a relay could forge an edit); new stones are
--     accepted from anyone and marked verified when first-hand
-- Returns "added" | "updated" | "deleted" | "tombstone", or nil and a reason.
function Store:Merge(rec, viaKey)
	if rec.authorKey == ns.Identity.PlayerKey() then return nil, "own stone" end
	local firstHand = viaKey ~= nil and viaKey == rec.authorKey
	local have = db().stones[rec.id]
	if have then
		if (have.v or 1) >= rec.v then return nil, "not newer" end
		if not firstHand then return nil, "change not from the author" end
	end

	if rec.deleted then
		if have then unindex(have) end
		db().stones[rec.id] = {
			id = rec.id, v = rec.v, t = rec.t, deleted = true, deletedAt = rec.deletedAt or time(),
			zone = rec.zone, flavor = ns.Identity.Flavor(), authorKey = rec.authorKey,
		}
		return have and "deleted" or "tombstone"
	end

	rec.author = ns.Identity.Display(rec.authorKey)
	rec.flavor = ns.Identity.Flavor()
	rec.via = viaKey
	rec.verified = firstHand
	if have then rec.heard = have.heard end
	self:Put(rec)
	return have and "updated" or "added"
end

-- Schema --------------------------------------------------------------------

-- Schema 1 kept stones in a list. Key them by id and fill in version, game
-- and zone. Stones that weren't yours were all local test stones then (no
-- sharing existed), so they're marked never to be shared.
local function migrate(d)
	d.zones = d.zones or {}
	d.outbox = d.outbox or {}
	d.ratings = d.ratings or {}
	if d.schema == Store.SCHEMA then return 0 end
	local old, stones, count = d.stones or {}, {}, 0
	for _, stone in ipairs(old) do
		stone.id = stone.id or format("local-%d-%04d", stone.t or 0, math.random(0, 9999))
		stone.v = stone.v or 1
		stone.flavor = stone.flavor or ns.Identity.Flavor()
		stone.zone = stone.zone or Store.ZoneKey(stone.mapID)
		if not stone.mine and not stone.authorKey then stone.localOnly = true end
		stones[stone.id] = stone
		count = count + 1
	end
	d.stones = stones
	d.schema = Store.SCHEMA
	return count
end

function Store:Init()
	local migrated = migrate(db())
	self:PruneTombstones()
	wipe(cells)
	for _, stone in pairs(db().stones) do index(stone) end
	self:Enforce()
	return migrated
end

-- Numbers for /soap stats.
function Store:Stats(zone)
	local s = { live = 0, mine = 0, others = 0, localOnly = 0, tombstones = 0, outbox = 0,
		zones = 0, inZone = 0, perZone = {} }
	for _, stone in pairs(db().stones) do
		if stone.deleted then
			s.tombstones = s.tombstones + 1
		elseif Store.IsLive(stone) then
			s.live = s.live + 1
			if Store.IsMine(stone) then s.mine = s.mine + 1
			elseif stone.localOnly then s.localOnly = s.localOnly + 1
			else s.others = s.others + 1 end
			if stone.zone then s.perZone[stone.zone] = (s.perZone[stone.zone] or 0) + 1 end
			if zone and stone.zone == zone then s.inZone = s.inZone + 1 end
		end
	end
	for _ in pairs(db().outbox) do s.outbox = s.outbox + 1 end
	for _ in pairs(db().zones) do s.zones = s.zones + 1 end
	return s
end
