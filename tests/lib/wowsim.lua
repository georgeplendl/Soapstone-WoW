-- A small simulated WoW Forever for multi-player tests.
--
-- Every client loads the real addon files (Core, Identity, Store, Sketch,
-- Codec, Net, Sync) into its own environment, so each has its own ns,
-- SoapstoneDB and send allowance. They share one clock and one "server"
-- that behaves like the measurements in docs/Sharing - Architecture.md:
--   * channel messages reach every joined client, whispers one client,
--     0.675 s later, with the sender shown as "First Last";
--   * per client: 10 messages at once, then 1 per second
--     (AddonMessageThrottle beyond that); messages over 255 bytes refused;
--   * whispering someone offline produces the real system message, which
--     goes through the client's CHAT_MSG_SYSTEM filter.
--
--   local Sim = dofile(TESTS .. "/lib/wowsim.lua")
--   Sim.ROOT = ROOT
--   local a = Sim.client("Osha", "Compliant")
--   Sim.run(30)

local Sim = {}

Sim.LATENCY = 0.675
Sim.BURST = 10
Sim.REFILL = 1
Sim.FILES = { "Core.lua", "Identity.lua", "Store.lua", "Sketch.lua", "Codec.lua", "Net.lua", "Sync.lua" }
Sim.MAPS = {
	[1411] = { name = "Durotar", mapType = 3, parentMapID = 1414 },
	[1413] = { name = "The Barrens", mapType = 3, parentMapID = 1414 },
	[1456] = { name = "Thunder Bluff", mapType = 3, parentMapID = 1414 },
	[1414] = { name = "Kalimdor", mapType = 2, parentMapID = 947 },
}
local ZONE_ORIGIN = { [1411] = { -500, -4500 }, [1413] = { -1400, -3700 }, [1456] = { -1000, -100 } }

local clock = 1790400000
local seq = 0
local timers = {}
local clients = {}
Sim.stats = { CHANNEL = 0, WHISPER = 0, refused = 0, oversize = 0, bytes = 0, byType = {} }
Sim.wire = {} -- every accepted message: { at, from, dist, target, msg }

function Sim.now() return clock end

-- Timers ------------------------------------------------------------------------

local function schedule(at, fn)
	seq = seq + 1
	local t = { at = at, seq = seq, fn = fn }
	function t:Cancel() self.cancelled = true end
	timers[#timers + 1] = t
	return t
end

function Sim.after(delay, fn)
	return schedule(clock + delay, fn)
end

function Sim.ticker(interval, fn, iterations)
	local handle = { remaining = iterations }
	function handle:Cancel() self.cancelled = true end
	local function tick()
		if handle.cancelled then return end
		if handle.remaining then handle.remaining = handle.remaining - 1 end
		fn(handle)
		if not handle.cancelled and (handle.remaining == nil or handle.remaining > 0) then
			schedule(clock + interval, tick)
		end
	end
	schedule(clock + interval, tick)
	return handle
end

-- Runs every timer due within `seconds`, in time order.
function Sim.run(seconds)
	local stop = clock + seconds
	while true do
		local best, index
		for i, t in ipairs(timers) do
			if not t.cancelled and t.at <= stop and (not best or t.at < best.at or (t.at == best.at and t.seq < best.seq)) then
				best, index = t, i
			end
		end
		if not best then break end
		table.remove(timers, index)
		if best.at > clock then clock = best.at end
		best.fn()
	end
	clock = stop
	local live = {}
	for _, t in ipairs(timers) do if not t.cancelled then live[#live + 1] = t end end
	timers = live
end

-- Runs until `cond()` is true (checked every step), or `limit` seconds pass.
-- Returns the seconds it took, or nil.
function Sim.runUntil(cond, limit, step)
	step = step or 0.25
	local start = clock
	while clock - start < limit do
		if cond() then return clock - start end
		Sim.run(step)
	end
	return cond() and clock - start or nil
end

-- Server --------------------------------------------------------------------------

function Sim.find(name)
	for _, c in ipairs(clients) do
		if c.name == name or c.key == name then return c end
	end
end

local function deliver(to, prefix, msg, dist, senderName)
	if not to.online then return end
	for _, frame in ipairs(to.frames) do
		if frame.events.CHAT_MSG_ADDON and frame.OnEvent then
			frame.OnEvent(frame, "CHAT_MSG_ADDON", prefix, msg, dist, senderName)
		end
	end
end

function Sim.send(c, prefix, msg, dist, target)
	if not c.online then return 9 end
	c.tokens = math.min(Sim.BURST, c.tokens + (clock - c.lastRefill) * Sim.REFILL)
	c.lastRefill = clock
	if c.tokens < 1 then
		Sim.stats.refused = Sim.stats.refused + 1
		return 3 -- AddonMessageThrottle
	end
	if #msg > 255 then
		Sim.stats.oversize = Sim.stats.oversize + 1
		return 2 -- InvalidMessage
	end
	if dist == "CHANNEL" and not c.joined then return 7 end
	if dist ~= "CHANNEL" and dist ~= "WHISPER" then return 4 end
	c.tokens = c.tokens - 1
	c.sent = c.sent + 1
	Sim.stats[dist] = Sim.stats[dist] + 1
	Sim.stats.bytes = Sim.stats.bytes + #msg
	local kind = msg:match("^S1;[^;]*;([^;]+)")
	if kind == "P" then kind = "P:" .. (msg:match("^S1;[^;]*;P;[^;]*;[^;]*;[^;]*;([^;]+)") or "?") end
	Sim.stats.byType[kind or "?"] = (Sim.stats.byType[kind or "?"] or 0) + 1
	Sim.wire[#Sim.wire + 1] = { at = clock, from = c.key, dist = dist, target = target, msg = msg, kind = kind }

	if dist == "CHANNEL" then
		for _, other in ipairs(clients) do
			if other.joined and other.online then
				Sim.after(Sim.LATENCY, function()
					if other.joined then deliver(other, prefix, msg, dist, c.name) end
				end)
			end
		end
	else
		Sim.after(Sim.LATENCY, function()
			local to = Sim.find(target)
			if to and to.online then
				deliver(to, prefix, msg, dist, c.name)
			elseif c.online then
				local text = format("No player named '%s' is currently playing.", tostring(target))
				local filter = c.filters.CHAT_MSG_SYSTEM
				if not (filter and filter(nil, "CHAT_MSG_SYSTEM", text)) then
					table.insert(c.systemShown, text)
				end
			end
		end)
	end
	return 0
end

function Sim.logoff(c)
	c.online, c.joined = false, false
end

-- Logs off every client except the ones given, so a scenario only involves
-- the players it's about.
function Sim.only(...)
	local keep = {}
	for _, c in ipairs({ ... }) do keep[c] = true end
	for _, c in ipairs(clients) do
		if not keep[c] then Sim.logoff(c) end
	end
end

-- Clients -------------------------------------------------------------------------

local function strsplit(sep, s)
	local out = {}
	for part in (s .. sep):gmatch("(.-)" .. sep:gsub("%p", "%%%0")) do out[#out + 1] = part end
	return table.unpack(out)
end

-- opts: build ("1.60.1"), project (1)
function Sim.client(first, last, opts)
	opts = opts or {}
	local c = {
		first = first, last = last, name = first .. " " .. last, key = first .. "-" .. last,
		online = true, joined = false, tokens = Sim.BURST, lastRefill = clock, sent = 0,
		frames = {}, filters = {}, printed = {}, systemShown = {},
	}
	local env = setmetatable({}, { __index = _G })
	env._G = env
	env.format, env.unpack, env.tinsert = string.format, table.unpack, table.insert
	env.strsplit = strsplit
	env.strtrim = function(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
	env.strlenutf8 = function(s) return utf8.len(s) or #s end
	env.wipe = function(t) for k in pairs(t) do t[k] = nil end return t end
	env.time = function() return math.floor(clock) end
	env.GetTime = function() return clock end
	env.GetTimePreciseSec = env.GetTime
	env.GetBuildInfo = function() return opts.build or "1.60.1", "70009", "", 16001 end
	env.WOW_PROJECT_ID = opts.project or 1
	env.UnitFullName = function() return first, last end
	env.UnitName = env.UnitFullName
	env.GetUnitName = function() return c.name end
	env.GetNormalizedRealmName = function() return last end
	env.GetAddOnMetadata = function() return "0.3.0" end
	env.Enum = {
		UIMapType = { Zone = 3 },
		SendAddonMessageResult = { Success = 0, InvalidMessage = 2, AddonMessageThrottle = 3,
			InvalidChatType = 4, InvalidChannel = 7, GeneralError = 9 },
	}
	env.C_Map = { GetMapInfo = function(id) return Sim.MAPS[id] end }
	env.C_Timer = {
		After = function(delay, fn) Sim.after(delay, fn) end,
		NewTimer = function(delay, fn) return Sim.after(delay, fn) end,
		NewTicker = Sim.ticker,
	}
	env.CreateFrame = function()
		local frame = { events = {} }
		function frame:RegisterEvent(event) self.events[event] = true end
		function frame:UnregisterEvent(event) self.events[event] = nil end
		function frame:SetScript(name, fn) self[name] = fn end
		c.frames[#c.frames + 1] = frame
		return frame
	end
	env.SlashCmdList = {}
	env.C_ChatInfo = {
		RegisterAddonMessagePrefix = function() return true end,
		IsAddonMessagePrefixRegistered = function() return true end,
		SendAddonMessage = function(prefix, msg, dist, target) return Sim.send(c, prefix, msg, dist, target) end,
	}
	env.GetChannelName = function() return c.joined and 6 or 0 end
	env.JoinTemporaryChannel = function() if c.online then c.joined = true end end
	env.LeaveChannelByName = function() c.joined = false end
	env.NUM_CHAT_WINDOWS = 0
	env.ChatFrame_AddMessageEventFilter = function(event, fn) c.filters[event] = fn end
	env.ERR_CHAT_PLAYER_NOT_FOUND_S = "No player named '%s' is currently playing."

	local ns = {}
	for _, file in ipairs(Sim.FILES) do
		assert(loadfile(Sim.ROOT .. "/" .. file, "t", env))("Soapstone", ns)
	end
	ns.Print = function(msg) c.printed[#c.printed + 1] = msg end
	ns.Version = function() return "0.3.0" end
	ns.db = { stones = {}, zones = {}, outbox = {}, schema = 2, network = true, gateYards = 40, nearYards = 150 }
	ns.Store:Init()
	ns.Net:Init()
	ns.Sync:Init()
	c.ns, c.env = ns, env
	clients[#clients + 1] = c
	return c
end

-- Stones ----------------------------------------------------------------------------

-- A stone as its author would have dropped it. The id depends only on the
-- author, n and opts.t, so calling this again later names the same stone.
-- opts: v, t, text, sketch (packed), localOnly
local STONE_EPOCH = 1790390000
function Sim.stone(authorKey, n, zone, opts)
	opts = opts or {}
	local origin = ZONE_ORIGIN[zone]
	local t = opts.t or (STONE_EPOCH + n)
	return {
		id = authorKey .. "-" .. t .. "-" .. n, v = opts.v or 1, authorKey = authorKey,
		author = (authorKey:gsub("%-", " ", 1)), t = t, zone = zone, instance = 1,
		wx = origin[1] + n * 7, wy = origin[2] + n * 3, mapID = zone, x = 0.5, y = 0.5,
		text = not opts.sketch and (opts.text or ("Stone " .. n .. " by " .. authorKey)) or nil,
		sketch = opts.sketch, localOnly = opts.localOnly,
	}
end

local function copy(t)
	local out = {}
	for k, v in pairs(t) do out[k] = type(v) == "table" and copy(v) or v end
	return out
end

-- Puts a copy of `stone` straight into a client's store (test setup).
function Sim.give(c, stone, via)
	local s = copy(stone)
	s.via = via
	c.ns.Store:Put(s)
	return s
end

function Sim.count(c, zone)
	local n = 0
	for _, s in c.ns.Store:Each() do
		if not zone or s.zone == zone then n = n + 1 end
	end
	return n
end

-- Channel messages of a given type sent since wire index `from`.
function Sim.countWire(kind, from, dist)
	local n = 0
	for i = (from or 0) + 1, #Sim.wire do
		local w = Sim.wire[i]
		if w.kind == kind and (not dist or w.dist == dist) then n = n + 1 end
	end
	return n
end

return Sim
