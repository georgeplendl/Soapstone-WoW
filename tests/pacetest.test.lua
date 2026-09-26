-- Net:PaceTest against a fake client throttle: 10-message bucket, refilling
dofile(TESTS .. "/lib/harness.lua")
-- 1 per second. Sending 4/s for 20 s should accept ~20 (the refill), since
-- the bucket was drained first.
function GetBuildInfo() return "1.60.1", "70009", "", 16001 end
WOW_PROJECT_ID = 1
function UnitFullName() return "Osha", "Compliant" end
function GetUnitName() return "Osha Compliant" end
function GetNormalizedRealmName() return "Compliant" end
local clock = 1000
function GetTimePreciseSec() return clock end
format = string.format
unpack = unpack or table.unpack
function strsplit(sep, s)
	local out = {}
	for part in (s .. sep):gmatch("(.-)" .. sep:gsub("%p", "%%%0")) do out[#out + 1] = part end
	return unpack(out)
end
function GetChannelName() return 6 end

-- Like WoW Forever: once the burst is spent, accepted sends report
-- ChannelThrottle (8) but are still delivered; refused ones are
-- AddonMessageThrottle (3).
local tokens, lastRefill, loop, sends = 10, clock, {}, 0
Enum = { SendAddonMessageResult = { Success = 0, AddonMessageThrottle = 3, ChannelThrottle = 8 } }
C_ChatInfo = {
	SendAddonMessage = function(_, msg, dist)
		sends = sends + 1
		tokens = math.min(10, tokens + (clock - lastRefill))
		lastRefill = clock
		if tokens < 1 then return 3 end
		tokens = tokens - 1
		loop[#loop + 1] = msg
		return sends > 10 and 8 or 0
	end,
}
local pending, after = nil, {}
C_Timer = {
	NewTicker = function(interval, fn, iterations)
		local t = { cancelled = false }
		function t:Cancel() self.cancelled = true end
		pending = { t = t, fn = fn, interval = interval, n = iterations }
		return t
	end,
	After = function(_, fn) after[#after + 1] = fn end,
}

local ns, printed = {}, {}
ns.Print = function(msg) printed[#printed + 1] = msg end
ns.Version = function() return "0.2.0" end
ns.db = { net = true }
assert(loadfile(ROOT .. "/Identity.lua"))("Soapstone", ns)
assert(loadfile(ROOT .. "/Net.lua"))("Soapstone", ns)
local Net = ns.Net

local function find(pattern)
	for _, line in ipairs(printed) do if line:find(pattern) then return line end end
end

Net:Command("pacetest 4 20")
check(tokens == 0, "burst drained before pacing")
check(pending and pending.n == 80 and math.abs(pending.interval - 0.25) < 1e-9, "80 sends at 0.25 s intervals")

for _ = 1, pending.n do
	if pending.t.cancelled then break end
	clock = clock + pending.interval
	pending.fn()
end
check(pending.t.cancelled, "ticker cancels itself after the last send")
for _, m in ipairs(loop) do Net:OnMessage(m, "CHANNEL", "Osha Compliant") end
check(#after == 1, "waits for echoes before reporting")
after[1]()

local sentLine = find("sent 80 over")
vprint("     " .. tostring(sentLine))
local rateLine = find("sustained rate")
vprint("     " .. tostring(rateLine))
local accepted = tonumber(rateLine and rateLine:match("accepted (%d+)"))
local rate = tonumber(rateLine and rateLine:match("about |cffffffff([%d%.]+)"))
check(accepted and accepted >= 19 and accepted <= 21, "accepted ~20 = the refill over 20 s")
check(rate and rate > 0.9 and rate < 1.1, "reports ~1 message/s")
check(sentLine and sentLine:find("AddonMessageThrottle x") ~= nil, "refusals tallied by name")
check(sentLine and sentLine:find("ChannelThrottle x2%d") ~= nil and not sentLine:find("ok x"),
	"reproduces George's run: only ChannelThrottle and AddonMessageThrottle")
check(rateLine and rateLine:find(accepted .. " came back") ~= nil, "every accepted message counted on return")
check(find("Pace test done") ~= nil, "finishes with a copy-me line")

done()
