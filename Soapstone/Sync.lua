local _, ns = ...

-- Zone sync (sharing step 3): when you settle in a zone, fetch the stones
-- other Soapstone players have for it. See docs/Sharing - Architecture.md.
--
--  you  ─channel─►  ZQ zone digest count          "who has this zone?"
--  peer ─channel─►  ZH zone digest count          offer (random delay; others
--                                                  with the same digest stay quiet)
--  you  ─whisper─►  ZL zone <16 bucket fingerprints>
--  peer ─whisper─►  [ZI] zone,id:v,id:v…          entries in buckets that differ
--  you  ─whisper─►  [ZG] zone,id,id…              "send me these"
--  peer ─whisper─►  [ST] stone … ZE zone count    stones (text first), then done
--  peer ─whisper─►  ZX zone reason                can't help (busy / nothing)
--
-- [..] are multi-part payloads (Net:SendPayload). One sync runs at a time,
-- always for the zone you're in; if a peer goes quiet or logs off, the next
-- offer is tried.

local Sync = {}
ns.Sync = Sync

Sync.SETTLE = 4          -- seconds in a zone before asking (passing through doesn't count)
Sync.COOLDOWN = 600      -- don't ask again for a zone within this, unless our stones changed
Sync.OFFER_WINDOW = 2    -- after the first offer, wait this long for bigger ones
Sync.QUERY_TIMEOUT = 8   -- nobody offered
Sync.STEP_TIMEOUT = 20   -- a peer went quiet mid-sync
Sync.BACKOFF_MIN = 0.4   -- responders wait a random time in this range
Sync.BACKOFF_MAX = 2.5
Sync.MAX_SERVING = 2     -- players we send stones to at once
Sync.MAX_WANT = 200      -- stones requested per sync
Sync.MAX_PEERS = 3       -- players to pull from in one sync, while they still have something new
Sync.RETRY_DELAY = 10    -- after a peer vanishes mid-sync, ask again this much later…
Sync.MAX_RETRIES = 2     -- …at most this many times per zone visit

local job              -- the sync in progress (requester side)
local lastSync = {}    -- zone -> { at, digest }
local pendingOffers = {} -- zone .. "/" .. digest -> timer (responder side)
local serving = {}     -- requester key -> { zone, at }
local history = {}     -- recent results for /soap net sync

local function Store() return ns.Store end
local function Net() return ns.Net end
local function keyOf(sender) return ns.Identity.KeyFromSender(sender) end

local function remember(line)
	table.insert(history, 1, format("%s  %s", date and date("%H:%M:%S") or "", line))
	history[6] = nil
end

local function zoneName(zone)
	local info = zone and C_Map.GetMapInfo(zone)
	return info and info.name or ("zone " .. tostring(zone))
end

-- Requesting ------------------------------------------------------------------

local function cancel(timer)
	if timer then timer:Cancel() end
end

function Sync:Deadline(seconds, reason)
	local current = job
	cancel(current.timer)
	current.timer = C_Timer.NewTimer(seconds, function()
		if job == current then self:Fail(reason) end
	end)
end

-- The sync in progress, if any (read-only; for /soap net sync and tests).
function Sync:Current()
	return job
end

function Sync:OnZone(zone)
	if zone == self.zone then return end
	self.zone = zone
	self.retries = 0
	cancel(self.settleTimer)
	self.settleTimer = zone and C_Timer.NewTimer(self.SETTLE, function()
		self.settleTimer = nil
		self:Start(zone)
	end)
end

function Sync:OnNetReady()
	if self.zone and not self.settleTimer then self:Start(self.zone) end
end

-- Asks the channel who has stones for `zone` that we lack.
function Sync:Start(zone, force)
	if job or zone ~= self.zone or not Net():IsReady() then return false end
	local digest, count = Store():ZoneDigest(zone)
	local last = lastSync[zone]
	if not force and last and time() - last.at < self.COOLDOWN and last.digest == digest then return false end
	job = { zone = zone, digest = digest, count = count, stage = "query", offers = {}, tried = {},
		added = 0, updated = 0, deleted = 0, rejected = 0 }
	lastSync[zone] = { at = time(), digest = digest }
	Net():Enqueue("CHANNEL", nil, "ZQ", zone, digest, count)
	self:Deadline(self.QUERY_TIMEOUT, "nobody had anything new")
	return true
end

function Sync:OnOffer(sender, zone, digest, count)
	if not job or job.stage ~= "query" or zone ~= job.zone or digest == job.digest then return end
	local key = keyOf(sender)
	if job.tried[key] then return end
	table.insert(job.offers, { peer = sender, key = key, count = count or 0, digest = digest })
	if not job.choosing then
		local current = job
		job.choosing = C_Timer.NewTimer(self.OFFER_WINDOW, function()
			if job == current then
				job.choosing = nil
				self:Next()
			end
		end)
	end
end

-- Moves on to the best untried offer, or finishes.
function Sync:Next()
	table.sort(job.offers, function(a, b) return a.count > b.count end)
	local offer = table.remove(job.offers, 1)
	if not offer then return self:Finish() end
	job.tried[offer.key] = true
	job.peer, job.peerKey, job.stage = offer.peer, offer.key, "list"
	local sums = Store():Buckets(job.zone)
	Net():Enqueue("WHISPER", job.peer, "ZL", job.zone, Store().EncodeBuckets(sums))
	self:Deadline(self.STEP_TIMEOUT, "peer went quiet")
end

function Sync:Fail(reason)
	if not job then return end
	job.lastProblem = reason
	if job.stage == "query" and #job.offers == 0 then return self:Finish(reason) end
	job.stage = "query"
	self:Next()
end

function Sync:OnList(sender, payload)
	if not job or job.stage ~= "list" or keyOf(sender) ~= job.peerKey then return end
	local zone, rest = payload:match("^(%d+),?(.*)$")
	if tonumber(zone) ~= job.zone then return end
	local want = {}
	local ownPrefix = ns.Identity.PlayerKey() .. "-" -- ids start with their author's key
	for id, v in rest:gmatch("([^,:]+):(%d+)") do
		local have = Store():Get(id)
		if (not have or (have.v or 1) < tonumber(v)) and id:sub(1, #ownPrefix) ~= ownPrefix then
			want[#want + 1] = id
			if #want >= self.MAX_WANT then break end
		end
	end
	if #want == 0 then return self:Finish() end
	job.stage, job.expected = "fetch", #want
	Net():SendPayload("WHISPER", job.peer, "ZG", job.zone .. "," .. table.concat(want, ","))
	self:Deadline(self.STEP_TIMEOUT, "peer went quiet")
end

function Sync:OnStone(sender, payload)
	if not job or job.stage ~= "fetch" or keyOf(sender) ~= job.peerKey then return end
	local rec = ns.Codec.DecodeStone(payload)
	local result = rec and rec.zone == job.zone and Store():Merge(rec, job.peerKey)
	if result == "added" then job.added = job.added + 1
	elseif result == "updated" then job.updated = job.updated + 1
	elseif result == "deleted" then job.deleted = job.deleted + 1
	elseif result ~= "tombstone" then job.rejected = job.rejected + 1 end -- a new tombstone just gets remembered
	self:Deadline(self.STEP_TIMEOUT, "peer went quiet")
end

function Sync:OnEnd(sender, zone)
	if job and job.stage == "fetch" and keyOf(sender) == job.peerKey and zone == job.zone then
		self:Finish()
	end
end

function Sync:OnRefused(sender, zone, reason)
	if job and job.stage ~= "query" and keyOf(sender) == job.peerKey and zone == job.zone then
		self:Fail(reason or "refused")
	end
end

function Sync:OnPeerGone(name)
	if job and job.peer and (job.peer == name or keyOf(name) == job.peerKey) then
		self:Fail("peer logged off")
	end
end

function Sync:Finish(problem)
	local done = job
	if not done then return end

	-- Other players offered too. If any of them still has stones we don't
	-- (their fingerprint differs from ours now), pull from them next.
	if not problem and #done.offers > 0 and (done.peers or 1) < self.MAX_PEERS then
		local ours = Store():ZoneDigest(done.zone)
		local rest = {}
		for _, offer in ipairs(done.offers) do
			if offer.digest ~= ours then rest[#rest + 1] = offer end
		end
		done.offers = rest
		if #rest > 0 then
			done.peers = (done.peers or 1) + 1
			done.stage = "query"
			return self:Next()
		end
	end

	job = nil
	cancel(done.timer)
	cancel(done.choosing)
	local changed = done.added + done.updated + done.deleted
	if changed > 0 then
		Store():Enforce()
		if ns.MinimapPins then ns.MinimapPins:Update() end
		ns.Print(format("%d new stone%s arrived for %s%s.", done.added, done.added == 1 and "" or "s",
			zoneName(done.zone),
			(done.updated + done.deleted > 0) and format(" (%d updated, %d removed)", done.updated, done.deleted) or ""))
	end
	lastSync[done.zone] = { at = time(), digest = (Store():ZoneDigest(done.zone)) }
	remember(format("%s: +%d, %d updated, %d removed, %d rejected%s", zoneName(done.zone), done.added,
		done.updated, done.deleted, done.rejected, (problem or done.lastProblem) and (" — " .. (problem or done.lastProblem)) or ""))
	self.lastResult = done

	-- A peer vanished mid-sync and nobody else offered (players with the same
	-- stones stayed quiet on purpose), so ask again: someone else will answer.
	local vanished = done.lastProblem == "peer logged off" or done.lastProblem == "peer went quiet"
	if vanished and (self.retries or 0) < self.MAX_RETRIES then
		self.retries = (self.retries or 0) + 1
		C_Timer.After(self.RETRY_DELAY, function()
			if self.zone == done.zone then self:Start(done.zone, true) end
		end)
	end
end

-- Serving -----------------------------------------------------------------------

local function servingCount()
	local n, t = 0, time()
	for key, s in pairs(serving) do
		if t - s.at > 60 then serving[key] = nil else n = n + 1 end
	end
	return n
end

function Sync:OnQuery(sender, zone, digest)
	local mine, count = Store():ZoneDigest(zone)
	if count == 0 or mine == digest or servingCount() >= self.MAX_SERVING then return end
	local key = zone .. "/" .. mine
	if pendingOffers[key] then return end
	local delay = self.BACKOFF_MIN + math.random() * (self.BACKOFF_MAX - self.BACKOFF_MIN)
	pendingOffers[key] = C_Timer.NewTimer(delay, function()
		pendingOffers[key] = nil
		Net():Enqueue("CHANNEL", nil, "ZH", zone, mine, count)
	end)
end

-- Someone offered: if it's the same stones we were about to offer, stay quiet.
function Sync:OnOfferHeard(zone, digest)
	local key = zone .. "/" .. tostring(digest)
	if pendingOffers[key] then
		pendingOffers[key]:Cancel()
		pendingOffers[key] = nil
	end
end

function Sync:OnListRequest(sender, zone, encoded)
	local theirs = Store().DecodeBuckets(encoded)
	if not theirs then return end
	local requester = keyOf(sender)
	if not serving[requester] and servingCount() >= self.MAX_SERVING then
		return Net():Enqueue("WHISPER", sender, "ZX", zone, "busy")
	end
	serving[requester] = { zone = zone, at = time() }
	local mine = Store():Buckets(zone)
	local differ = {}
	for b = 1, Store().BUCKETS do
		if mine[b] ~= theirs[b] then differ[b] = true end
	end
	local entries = Store():BucketEntries(zone, differ)
	Net():SendPayload("WHISPER", sender, "ZI", zone .. "," .. table.concat(entries, ","))
end

function Sync:OnFetch(sender, payload)
	local requester = keyOf(sender)
	local zone, rest = payload:match("^(%d+),?(.*)$")
	zone = tonumber(zone)
	if not zone or not serving[requester] then return end
	serving[requester].at = time()
	local texts, sketches, sent = {}, {}, 0
	for id in rest:gmatch("[^,]+") do
		local stone = Store():Get(id)
		if stone and stone.zone == zone and Store().IsShareable(stone) then
			table.insert(stone.sketch and sketches or texts, stone)
		end
		if #texts + #sketches >= self.MAX_WANT then break end
	end
	for _, list in ipairs({ texts, sketches }) do -- text and deletions first; sketches are bigger
		for _, stone in ipairs(list) do
			Net():SendPayload("WHISPER", sender, "ST", ns.Codec.EncodeStone(stone))
			sent = sent + 1
		end
	end
	Net():Enqueue("WHISPER", sender, "ZE", zone, sent)
	serving[requester] = nil
end

-- Wiring --------------------------------------------------------------------------

function Sync:Init()
	local net = Net()
	net:On("ZQ", function(_, sender, dist, zone, digest)
		zone = tonumber(zone)
		if zone and dist == "CHANNEL" then self:OnQuery(sender, zone, digest) end
	end)
	net:On("ZH", function(_, sender, dist, zone, digest, count)
		zone = tonumber(zone)
		if not zone then return end
		self:OnOfferHeard(zone, digest)
		self:OnOffer(sender, zone, digest, tonumber(count))
	end)
	net:On("ZL", function(_, sender, dist, zone, buckets)
		zone = tonumber(zone)
		if zone and dist == "WHISPER" then self:OnListRequest(sender, zone, buckets) end
	end)
	net:On("ZE", function(_, sender, dist, zone) self:OnEnd(sender, tonumber(zone)) end)
	net:On("ZX", function(_, sender, dist, zone, reason) self:OnRefused(sender, tonumber(zone), reason) end)
	net:OnPayload("ZI", function(_, sender, payload) self:OnList(sender, payload) end)
	net:OnPayload("ZG", function(_, sender, payload) self:OnFetch(sender, payload) end)
	net:OnPayload("ST", function(_, sender, payload) self:OnStone(sender, payload) end)
	net:OnPeerGone(function(name) self:OnPeerGone(name) end)
end

-- /soap net sync ------------------------------------------------------------------

function Sync:Command(input)
	input = (input or ""):lower()
	if input == "now" then
		if not self.zone then return ns.Print("No zone yet — try again in a moment.") end
		if job then return ns.Print("A sync is already running.") end
		if not ns.db.network then return ns.Print("Networking is off. /soap net join turns it on.") end
		if not Net():IsReady() then return ns.Print("Not connected to the Soapstone network yet (/soap net).") end
		self:Start(self.zone, true)
		return ns.Print(format("Asking who has stones for %s…", zoneName(self.zone)))
	end
	local digest, count = self.zone and Store():ZoneDigest(self.zone)
	ns.Print(format("Zone: %s — %d shareable stones (fingerprint %s). Network: %s.",
		zoneName(self.zone), count or 0, digest or "-",
		not ns.db.network and "off (/soap net join)" or Net():IsReady() and "connected" or "not connected yet"))
	if job then
		ns.Print(format("Syncing now: %s%s.", job.stage, job.peer and (" with " .. job.peer) or ""))
	end
	ns.Print(format("Serving %d player%s. /soap net sync now to ask again.", servingCount(), servingCount() == 1 and "" or "s"))
	for _, line in ipairs(history) do ns.Print("  " .. line) end
end
