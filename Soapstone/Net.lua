local _, ns = ...

-- Network layer, step 1: a test harness for player-to-player messaging.
-- See docs/Sharing - Architecture.md. Nothing here syncs stones yet; it
-- answers the unknowns first:
--   * do hidden custom channels and addon messages work on this client, and
--     how far do they reach?
--   * what does the sender name look like when a message arrives?
--   * where does the client start throttling?
--
-- Wire format: "S1;<flavor>;<TYPE>;field;field..." on prefix "Soapstone".
-- Messages from another protocol version or game flavour are ignored.

local Identity = ns.Identity

local Net = {}
ns.Net = Net

local PREFIX = "Soapstone"
local CHANNEL = "SoapstoneNet"
local PROTOCOL = "S1"
local JOIN_DELAY = 6   -- seconds after login, so General/Trade keep their usual numbers
local PING_WINDOW = 10 -- seconds to collect ping replies
local BURST_SETTLE = 4 -- seconds after the first burst message before acknowledging

local DISTRIBUTIONS = { channel = "CHANNEL", guild = "GUILD", party = "PARTY", raid = "RAID",
	yell = "YELL", say = "SAY", whisper = "WHISPER" }

local pings = {}  -- nonce -> { sentAt, dist, count }
local bursts = {} -- sender .. runId -> { got, n, seen }
local logging = false

local function now()
	return GetTimePreciseSec and GetTimePreciseSec() or GetTime()
end

local function channelIndex()
	local id = GetChannelName(CHANNEL)
	return id and id > 0 and id or nil
end

-- SendAddonMessage returns a result code on newer clients, a boolean on older.
local function describe(result)
	if result == true or result == 0 then return "ok" end
	if result == nil or result == false then return "failed" end
	if Enum and Enum.SendAddonMessageResult then
		for name, value in pairs(Enum.SendAddonMessageResult) do
			if value == result then return name end
		end
	end
	return tostring(result)
end

-- Channel -------------------------------------------------------------------

function Net:HideFromChat()
	local remove = ChatFrame_RemoveChannel or (ChatFrameUtil and ChatFrameUtil.RemoveChannel)
	if not remove then return end
	for i = 1, (NUM_CHAT_WINDOWS or 10) do
		local frame = _G["ChatFrame" .. i]
		if frame then pcall(remove, frame, CHANNEL) end
	end
end

function Net:Join()
	if not channelIndex() then JoinTemporaryChannel(CHANNEL) end
	C_Timer.After(2, function()
		self:HideFromChat()
		if not channelIndex() then
			ns.Print("Couldn't join the Soapstone network channel. Try /soap net join.")
		end
	end)
end

function Net:Leave()
	if channelIndex() then LeaveChannelByName(CHANNEL) end
end

-- Sending -------------------------------------------------------------------

-- Sends TYPE and fields over `dist`. For CHANNEL the target is filled in;
-- for WHISPER `target` is the recipient. Returns a readable result.
function Net:Send(dist, target, kind, ...)
	if dist == "CHANNEL" then
		target = channelIndex()
		if not target then return "not in channel" end
	end
	local msg = table.concat({ PROTOCOL, Identity.Flavor(), kind, ... }, ";")
	return describe(C_ChatInfo.SendAddonMessage(PREFIX, msg, dist, target))
end

-- Receiving -----------------------------------------------------------------

local handlers = {}

function handlers.PING(self, sender, dist, nonce, version)
	local reply = self:Send("WHISPER", sender, "PONG", nonce, ns.Version(), dist)
	ns.Print(format("Ping from |cffffffff%s|r (key %s, v%s) via %s — reply: %s.",
		sender, Identity.KeyFromSender(sender) or "?", version or "?", dist, reply))
end

function handlers.PONG(self, sender, dist, nonce, version, via)
	local ping = pings[nonce]
	if not ping then return end
	ping.count = ping.count + 1
	ns.Print(format("  reply from |cffffffff%s|r  key %s  shows as \"%s\"  %d ms  v%s  (heard it via %s)",
		sender, Identity.KeyFromSender(sender) or "?", Identity.Display(Identity.KeyFromSender(sender)) or "?",
		(now() - ping.sentAt) * 1000, version or "?", via or "?"))
end

function handlers.BURST(self, sender, dist, runId, i, n)
	local id = sender .. ":" .. (runId or "")
	local burst = bursts[id]
	if not burst then
		burst = { got = 0, n = tonumber(n) or 0, seen = {} }
		bursts[id] = burst
		C_Timer.After(BURST_SETTLE, function()
			local reply = self:Send("WHISPER", sender, "BURSTACK", runId, burst.got, burst.n)
			ns.Print(format("Burst from %s via %s: received %d/%d (ack: %s).", sender, dist, burst.got, burst.n, reply))
			bursts[id] = nil
		end)
	end
	if i and not burst.seen[i] then
		burst.seen[i] = true
		burst.got = burst.got + 1
	end
end

function handlers.BURSTACK(self, sender, dist, runId, got, n)
	ns.Print(format("  %s received %s of %s burst messages.", sender, got or "?", n or "?"))
end

function Net:OnMessage(text, dist, sender)
	if logging then ns.Print(format("net < %s [%s] %s", sender, dist, text)) end
	local fields = { strsplit(";", text) }
	if fields[1] ~= PROTOCOL or fields[2] ~= Identity.Flavor() then return end
	if Identity.KeyFromSender(sender) == Identity.PlayerKey() then return end -- our own channel echo
	local handler = handlers[fields[3]]
	if handler then handler(self, sender, dist, unpack(fields, 4)) end
end

-- Test commands ---------------------------------------------------------------

-- "channel" | "guild" | ... | "whisper Name" -> dist, target
local function parseDist(words, start)
	local dist = DISTRIBUTIONS[(words[start] or "channel"):lower()]
	if not dist then return nil end
	return dist, dist == "WHISPER" and words[start + 1] or nil
end

function Net:Status()
	ns.Print(format("You are |cffffffff%s|r (key %s) on %s, Soapstone %s.",
		Identity.PlayerDisplay() or "?", Identity.PlayerKey() or "?", Identity.Flavor(), ns.Version()))
	local id = channelIndex()
	ns.Print(id and format("Network channel %s joined as /%d, hidden from chat.", CHANNEL, id)
		or format("Network channel %s not joined.", CHANNEL))
	local registered = C_ChatInfo.IsAddonMessagePrefixRegistered and C_ChatInfo.IsAddonMessagePrefixRegistered(PREFIX)
	ns.Print(format("Addon prefix \"%s\" registered: %s. Logging: %s.", PREFIX, tostring(registered), logging and "on" or "off"))
end

function Net:Ping(dist, target)
	local nonce = tostring(math.random(100000, 999999))
	pings[nonce] = { sentAt = now(), dist = dist, count = 0 }
	local result = self:Send(dist, target, "PING", nonce, ns.Version())
	ns.Print(format("Ping %s over %s%s: %s. Listening for replies for %d s…",
		nonce, dist, target and (" to " .. target) or "", result, PING_WINDOW))
	C_Timer.After(PING_WINDOW, function()
		local ping = pings[nonce]
		pings[nonce] = nil
		ns.Print(format("Ping %s done: %d repl%s.", nonce, ping.count, ping.count == 1 and "y" or "ies"))
	end)
end

-- Sends `n` numbered messages in one go; the client's own result codes show
-- where it starts refusing, and receivers acknowledge how many arrived.
function Net:Burst(n, dist, target)
	local runId = tostring(math.random(1000, 9999))
	local tally, order = {}, {}
	for i = 1, n do
		local result = self:Send(dist, target, "BURST", runId, i, n)
		if not tally[result] then tally[result] = 0; order[#order + 1] = result end
		tally[result] = tally[result] + 1
	end
	local parts = {}
	for _, result in ipairs(order) do parts[#parts + 1] = format("%s ×%d", result, tally[result]) end
	ns.Print(format("Burst %s: sent %d over %s%s — %s. Acks follow in ~%d s.",
		runId, n, dist, target and (" to " .. target) or "", table.concat(parts, ", "), BURST_SETTLE))
end

local HELP = {
	"/soap net — status: your identity, game, channel",
	"/soap net ping [channel|guild|party|raid|yell|say|whisper Name] — who hears you, and how fast",
	"/soap net burst [count] [same targets] — send many at once to find the throttle",
	"/soap net log — toggle printing every incoming Soapstone message",
	"/soap net join | leave — join or leave the network channel",
}

function Net:Command(input)
	local words = {}
	for word in (input or ""):gmatch("%S+") do words[#words + 1] = word end
	local cmd = (words[1] or "status"):lower()

	if cmd == "status" then
		self:Status()
	elseif cmd == "ping" then
		local dist, target = parseDist(words, 2)
		if not dist or (dist == "WHISPER" and not target) then return ns.Print(HELP[2]) end
		self:Ping(dist, target)
	elseif cmd == "burst" then
		local n = tonumber(words[2])
		local dist, target = parseDist(words, n and 3 or 2)
		if not dist or (dist == "WHISPER" and not target) then return ns.Print(HELP[3]) end
		self:Burst(math.min(n or 20, 100), dist, target)
	elseif cmd == "log" then
		logging = not logging
		ns.Print("Network logging " .. (logging and "on." or "off."))
	elseif cmd == "join" then
		ns.db.net = true
		self:Join()
	elseif cmd == "leave" then
		ns.db.net = false
		self:Leave()
		ns.Print("Left the network channel. /soap net join to rejoin.")
	else
		for _, line in ipairs(HELP) do ns.Print(line) end
	end
end

-- Startup -------------------------------------------------------------------

function Net:Init()
	C_ChatInfo.RegisterAddonMessagePrefix(PREFIX)
	local frame = CreateFrame("Frame")
	frame:RegisterEvent("CHAT_MSG_ADDON")
	frame:SetScript("OnEvent", function(_, _, prefix, text, dist, sender)
		if prefix == PREFIX then self:OnMessage(text, dist, sender) end
	end)
	if ns.db.net then
		C_Timer.After(JOIN_DELAY, function() self:Join() end)
	end
end
