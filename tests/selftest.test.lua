-- Net:SelfTest against a fake server: channel messages and whispers to
dofile(TESTS .. "/lib/harness.lua")
-- "Mad-Decent" echo back; other whisper forms and say/yell vanish; burst
-- sends beyond the 10th are refused by the client.
function GetBuildInfo() return "1.60.1", "70009", "", 16001 end
WOW_PROJECT_ID = 1
function UnitFullName() return "Mad", "Decent" end
function UnitName() return "Mad", "Decent" end
function GetUnitName() return "Mad Decent" end
function GetNormalizedRealmName() return "Decent" end
function IsInGuild() return false end
local clock = 100
function GetTimePreciseSec() return clock end
format = string.format
unpack = unpack or table.unpack
function strsplit(sep, s)
	local out = {}
	for part in (s .. sep):gmatch("(.-)" .. sep:gsub("%p", "%%%0")) do out[#out + 1] = part end
	return unpack(out)
end
function GetChannelName() return 5 end

local ns, printed, timers, loop = {}, {}, {}, {}
ns.Print = function(msg) printed[#printed + 1] = msg end
ns.Version = function() return "0.2.0" end
ns.VersionString = ns.Version -- Core.lua provides both in the addon
ns.db = { net = true }
local bursts = 0
C_ChatInfo = {
	SendAddonMessage = function(_, msg, dist, target)
		if msg:find(";ECHOB;") then
			bursts = bursts + 1
			if bursts > 10 then return 3 end -- pretend "throttled"
		end
		if dist == "CHANNEL" or (dist == "WHISPER" and target == "Mad-Decent") then
			loop[#loop + 1] = { msg, dist }
		end
		return 0
	end,
	IsAddonMessagePrefixRegistered = function() return true end,
}
Enum = { SendAddonMessageResult = { Success = 0, AddonMessageThrottle = 3 } }
C_Timer = { After = function(_, fn) timers[#timers + 1] = fn end }

assert(loadfile(ROOT .. "/Identity.lua"))("Soapstone", ns)
assert(loadfile(ROOT .. "/Net.lua"))("Soapstone", ns)
local Net = ns.Net

local function deliver()
	clock = clock + 0.042
	for _, m in ipairs(loop) do Net:OnMessage(m[1], m[2], "Mad-Decent") end
	loop = {}
end
local function has(pattern)
	for _, line in ipairs(printed) do if line:find(pattern) then return true end end
	return false
end

Net:Command("selftest 30")
check(has("sent channel SoapstoneNet: ok"), "channel send reported")
check(has('sent whisper to "Mad Decent": ok'), "space-form whisper attempted")
check(has("sent say: ok") and has("sent yell: ok"), "say and yell attempted")
check(not has("sent guild"), "guild skipped when not in a guild")
deliver()
check(has('OK|r channel SoapstoneNet: back in 42 ms via CHANNEL; your name arrived as "Mad%-Decent"'),
	"channel echo timed and shows the raw sender")
check(has("OK|r whisper to Mad%-Decent: back in"), "hyphen-form whisper came back")

check(#timers == 1, "waits before judging")
timers[1]()
check(has('NO|r whisper to "Mad Decent": never came back'), "space-form whisper reported missing")
check(has("NO|r whisper to Mad: never came back"), "short-name whisper reported missing")
check(has("NO|r yell: never came back"), "yell reported missing")
check(has("sent 30 at once on the channel: ok x10, AddonMessageThrottle x20"), "burst tallies client results by name")
deliver()
check(#timers == 2, "waits before counting the burst")
timers[2]()
check(has("10 of 30 came back through the server"), "burst echoes counted")
check(has("Self%-test done"), "finishes with a copy-me line")

-- Unrelated own messages are still ignored outside the self-test.
local before = #printed
Net:OnMessage("S1;forever;PING;1;0.2.0", "CHANNEL", "Mad-Decent")
check(#printed == before, "own pings still ignored")

done()
