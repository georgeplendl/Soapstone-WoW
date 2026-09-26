-- Net:Enqueue / Pump against a fake client allowance (10 burst, 1/s).
dofile(TESTS .. "/lib/harness.lua")
local clock = 500
function GetTimePreciseSec() return clock end
format = string.format
unpack = unpack or table.unpack
function GetBuildInfo() return "1.60.1", "70009", "", 16001 end
WOW_PROJECT_ID = 1
function UnitFullName() return "Osha", "Compliant" end
function GetNormalizedRealmName() return "Compliant" end
function GetChannelName() return 6 end
function strsplit(sep, s)
	local out = {}
	for part in (s .. sep):gmatch("(.-)" .. sep:gsub("%p", "%%%0")) do out[#out + 1] = part end
	return unpack(out)
end

Enum = { SendAddonMessageResult = { Success = 0, AddonMessageThrottle = 3, ChannelThrottle = 8, TargetRequired = 6 } }
local allowance, lastRefill, wire, forceThrottle = 10, clock, {}, 0
C_ChatInfo = {
	SendAddonMessage = function(_, msg, dist, target)
		allowance = math.min(10, allowance + (clock - lastRefill))
		lastRefill = clock
		if forceThrottle > 0 then forceThrottle = forceThrottle - 1 return 3 end
		if allowance < 1 then return 3 end
		allowance = allowance - 1
		wire[#wire + 1] = msg
		if dist == "WHISPER" and not target then return 6 end
		return #wire > 5 and 8 or 0
	end,
}
local tickers = {}
C_Timer = {
	NewTicker = function(_, fn)
		local t = { fn = fn }
		function t:Cancel() self.cancelled = true end
		tickers[#tickers + 1] = t
		return t
	end,
	After = function() end,
}

local ns = { db = { net = true } }
ns.Print = function() end
ns.Version = function() return "0.2.0" end
assert(loadfile(ROOT .. "/Identity.lua"))("Soapstone", ns)
assert(loadfile(ROOT .. "/Net.lua"))("Soapstone", ns)
local Net = ns.Net

local function run(seconds)
	for _ = 1, seconds * 4 do
		clock = clock + 0.25
		for _, t in ipairs(tickers) do if not t.cancelled then t.fn() end end
	end
end

for i = 1, 20 do Net:Enqueue("CHANNEL", nil, "T", i) end
check(#wire == 9, "first 9 go out at once (our bucket, under the client's 10)")
check(Net:QueueLength() == 11, "the rest wait in the queue")
run(5)
check(#wire >= 12 and #wire <= 14, "about 0.9/s after that (" .. #wire .. " after 5 s)")
run(10)
check(#wire == 20 and Net:QueueLength() == 0, "all 20 sent within ~13 s")
local inOrder = true
for i, msg in ipairs(wire) do if msg ~= "S1;forever;T;" .. i then inOrder = false end end
check(inOrder, "sent in order, with ChannelThrottle counted as sent (no repeats)")
local live = 0
for _, t in ipairs(tickers) do if not t.cancelled then live = live + 1 end end
check(live == 0, "pump stops when the queue is empty")

-- The client refuses even though our bucket said yes: back off and retry.
run(20) -- refill
forceThrottle = 2
Net:Enqueue("CHANNEL", nil, "R", "a")
check(Net:QueueLength() == 1 and #wire == 20, "refused message stays queued")
run(3)
check(Net:QueueLength() == 0 and wire[#wire] == "S1;forever;R;a", "and goes out after backing off")

-- A message that can never be delivered is dropped, not retried forever.
Net:Enqueue("WHISPER", nil, "W", "x")
run(2)
check(Net:QueueLength() == 0, "undeliverable message dropped")

-- nil fields keep their positions
Net:Enqueue("CHANNEL", nil, "N", "a", nil, "c")
run(2)
check(wire[#wire] == "S1;forever;N;a;;c", "a nil field is sent as an empty field")
check(Net:QueueLength() == 0, "and the queue carries on")

done()
