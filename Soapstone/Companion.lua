local _, ns = ...

-- Reading what the companion app leaves for the addon.
--
-- The companion (companion/) writes a helper addon, SoapstoneData, whose
-- Stones.lua sets one global. WoW runs it as Lua, so it holds only numbers
-- and base64 strings, which can't break out of a string; every record is
-- decoded and checked here, so the worst a bad file can do is be skipped.
--
--   SoapstoneData_Stones = {
--     format    = 1,              -- anything else: "update the companion"
--     writtenAt = 1791234567,     -- the companion refreshes it every few minutes
--     scope     = "<base64>",     -- "flavor~region": whose stones these are
--     records   = { "<base64>", ... },
--   }
--
-- Each record decodes to fields joined by "~" (escaped as in Codec.lua):
--   S~score~found~<16 stone fields>      a stone from the database (Codec.DecodeRemoteStone)
--   R~id~v~zone~why                      removed: deleted | hidden | rejected
--   A~s~id~v · A~v~id~char~value · A~u~id~char     your upload went through
--   X~kind~id~char~reason~retry          refused (kind s, v or u; retry "1": try tomorrow)
--   U~char~stoneId~unlockedAt            one of your characters' unlocks, from the server
--
-- Rules: a stone from the database replaces an older copy, never one of
-- yours; a stone is removed only when a record says so, never because the
-- file doesn't mention it.
--
-- Drawings come separately, in Sketches.lua, and only while the companion
-- runs: it refreshes the file every few minutes and empties it when it
-- quits, and a file older than STALE is ignored (the companion may have
-- crashed). They're kept in memory only, never in SavedVariables:
--
--   SoapstoneData_Sketches = { format = 1, writtenAt = ..., scope = ...,
--     records = { "<base64 of sk_<16 hex>~w~h~data>", ... } }

local Companion = {}
ns.Companion = Companion

Companion.FORMAT = 1
Companion.MAX_RECORDS = 20000
Companion.STALE = 15 * 60 -- older than this, the companion isn't running

-- Drawings by sketch id, from the last LoadSketches.
Companion.sketches = {}

-- What the last Load found, for the status line.
Companion.state = "none" -- none | ok | outdated | unreadable | elsewhere
Companion.writtenAt = nil

local REASONS = {
	["too many stones today"] = "you've left a lot of stones today",
	["too many in this zone"] = "you have 10 stones in this zone already",
	["too many nearby"] = "there are already stones right there",
	["word filter"] = "it contains a word that isn't allowed",
	["duplicate"] = "you left the same words already today",
	["name belongs to another install"] = "your name is linked to another computer",
}

local function split(s)
	local f = {}
	for field in (s .. "~"):gmatch("([^~]*)~") do f[#f + 1] = field end
	return f
end

local function int(s)
	local n = tonumber(s)
	if n and n == math.floor(n) then return n end
end

local function zoneName(zone)
	local info = zone and C_Map and C_Map.GetMapInfo(zone)
	return info and info.name or "somewhere"
end

-- Records ---------------------------------------------------------------------

local handlers = {}

-- S~score~found~<stone>
function handlers.S(self, rest, out)
	local score, found, stoneFields = rest:match("^([^~]*)~([^~]*)~(.*)$")
	local rec, why = stoneFields and ns.Codec.DecodeRemoteStone(stoneFields)
	if not rec then return false, why end
	local result = ns.Store:MergeRemote(rec, int(score), int(found))
	if result then out[result] = (out[result] or 0) + 1 end
	return true
end

-- R~id~v~zone~why
function handlers.R(self, rest, out)
	local f = split(rest)
	local id, v, why = ns.Codec.Unescape(f[1] or ""), int(f[2]), f[4]
	if id == "" or not v or not (why == "deleted" or why == "hidden" or why == "rejected") then return false, "removal" end
	if ns.Store:RemoveRemote(id, v, why) then out.removed = (out.removed or 0) + 1 end
	return true
end

-- A~s~id~v · A~v~id~char~value · A~u~id~char
function handlers.A(self, rest, out)
	local f = split(rest)
	local kind, id = f[1], ns.Codec.Unescape(f[2] or "")
	local pending = ns.Store.Pending()
	if id == "" then return false, "ack" end
	if kind == "s" then
		local v = int(f[3])
		if not v then return false, "ack" end
		if pending.stones[id] and pending.stones[id] <= v then pending.stones[id] = nil end
		local stone = ns.Store:Get(id)
		if stone then
			stone.inDatabase = true
			stone.notShared = nil
		end
	elseif kind == "v" or kind == "u" then
		local char = ns.Codec.Unescape(f[3] or "")
		local list = (kind == "v" and pending.votes or pending.unlocks)[id]
		if list and list[char] ~= nil and (kind == "u" or list[char] == int(f[4])) then
			list[char] = nil
			if not next(list) then (kind == "v" and pending.votes or pending.unlocks)[id] = nil end
		end
	else
		return false, "ack"
	end
	out.acked = (out.acked or 0) + 1
	return true
end

-- X~kind~id~char~reason~retry
function handlers.X(self, rest, out)
	local f = split(rest)
	local kind, id, char = f[1], ns.Codec.Unescape(f[2] or ""), ns.Codec.Unescape(f[3] or "")
	local reason, retry = ns.Codec.Unescape(f[4] or ""), f[5] == "1"
	if id == "" or not (kind == "s" or kind == "v" or kind == "u") then return false, "refusal" end
	local pending = ns.Store.Pending()
	if kind == "s" then
		local stone = ns.Store:Get(id)
		if stone and ns.Store.IsAccountCharacter(stone.authorKey) and stone.notShared ~= reason then
			stone.notShared = reason
			self.refused[#self.refused + 1] = stone
		end
		if not retry then pending.stones[id] = nil end
	elseif not retry then
		local list = (kind == "v" and pending.votes or pending.unlocks)[id]
		if list then
			list[char] = nil
			if not next(list) then (kind == "v" and pending.votes or pending.unlocks)[id] = nil end
		end
	end
	out.refused = (out.refused or 0) + 1
	return true
end

-- U~char~stoneId~unlockedAt
function handlers.U(self, rest, out)
	local f = split(rest)
	local char, id, at = ns.Codec.Unescape(f[1] or ""), ns.Codec.Unescape(f[2] or ""), int(f[3])
	if char == "" or id == "" or not at or at <= 0 then return false, "unlock" end
	local stone = ns.Store:Get(id)
	if stone and not stone.deleted and ns.Store.IsAccountCharacter(char) then
		stone.heardBy = stone.heardBy or {}
		if not stone.heardBy[char] or stone.heardBy[char] > at then stone.heardBy[char] = at end
		local list = ns.Store.Pending().unlocks[id]
		if list then
			list[char] = nil
			if not next(list) then ns.Store.Pending().unlocks[id] = nil end
		end
		out.unlocks = (out.unlocks or 0) + 1
	end
	return true
end

-- Loading -----------------------------------------------------------------------

-- For this game type and region ("scope" is base64 "flavor~region").
local function inScope(data)
	local scope = ns.Codec.Base64Decode(data.scope)
	local flavor, region = (scope or ""):match("^([^~]+)~([^~]+)$")
	local myRegion = ns.Identity.Region()
	return flavor == ns.Identity.Flavor() and (not myRegion or region == myRegion)
end


-- Reads `data` (SoapstoneData_Stones by default) into the store. Returns
-- counts of what changed: added, updated, removed, acked, refused, unlocks,
-- skipped (records that failed their checks).
function Companion:Load(data)
	if data == nil then data = _G.SoapstoneData_Stones end
	local out = { skipped = 0 }
	self.refused = {}
	self.writtenAt = nil
	if data == nil then
		self.state = "none"
		return out
	end
	if type(data) ~= "table" or type(data.records) ~= "table" then
		self.state = "unreadable"
		return out
	end
	if data.format ~= self.FORMAT then
		self.state = "outdated"
		return out
	end
	if not inScope(data) then
		-- Stones for another game type or region: none of them belong here.
		self.state = "elsewhere"
		return out
	end
	self.state = "ok"
	self.writtenAt = type(data.writtenAt) == "number" and data.writtenAt or nil

	for i, blob in ipairs(data.records) do
		if i > self.MAX_RECORDS then break end
		local record = ns.Codec.Base64Decode(blob)
		local kind, rest = (record or ""):match("^(%u)~(.*)$")
		local handler = kind and handlers[kind]
		local ok = handler and handler(self, rest, out)
		if not ok then out.skipped = out.skipped + 1 end
	end
	ns.Store:Enforce()
	ns.Store:Touch()
	return out
end

-- Reads SoapstoneData_Sketches (or `data`). Returns how many drawings were
-- loaded and how many records were skipped.
function Companion:LoadSketches(data, now)
	if data == nil then data = _G.SoapstoneData_Sketches end
	wipe(self.sketches)
	if type(data) ~= "table" or data.format ~= self.FORMAT or type(data.records) ~= "table" then return 0, 0 end
	if type(data.writtenAt) ~= "number" or (now or time()) - data.writtenAt > self.STALE then return 0, 0 end
	if not inScope(data) then return 0, 0 end
	local loaded, skipped = 0, 0
	for i, blob in ipairs(data.records) do
		if i > self.MAX_RECORDS then break end
		local id, sketch = ns.Codec.DecodeSketchRecord(ns.Codec.Base64Decode(blob))
		if id then
			self.sketches[id] = sketch
			loaded = loaded + 1
		else
			skipped = skipped + 1
		end
	end
	return loaded, skipped
end

-- Tells you about stones of yours the server refused, once each.
function Companion:AnnounceRefusals()
	for _, stone in ipairs(self.refused or {}) do
		local reason = REASONS[stone.notShared] or stone.notShared
		ns.Print(format("Your stone in %s wasn't shared: %s. Only you can see it.", zoneName(stone.zone), reason))
	end
end

-- "Companion: synced 2 mins ago", for /soap stats and the minimap button.
function Companion:Status(now)
	now = now or time()
	if self.state == "none" then return "Companion: not installed" end
	if self.state == "unreadable" then return "Companion: data unreadable" end
	if self.state == "outdated" then return "Companion: update the Soapstone companion" end
	if self.state == "elsewhere" then return "Companion: its stones are for another game" end
	local at = self.writtenAt
	if not at then return "Companion: synced" end
	local ago = ns.Stones.TimeAgo(math.max(0, now - at))
	if now - at > self.STALE then return format("Companion: not running (last synced %s)", ago) end
	return format("Companion: synced %s", ago)
end
