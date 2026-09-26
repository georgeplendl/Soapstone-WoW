-- Identity.lua + Net.lua message handling, with a fake WoW Forever client.
dofile(TESTS .. "/lib/harness.lua")
local BUILD, PROJECT = "1.60.1", 1
function GetBuildInfo() return BUILD, "70009", "Sep 1 2026", 16001 end
WOW_PROJECT_ID = PROJECT
function UnitFullName() return "Mad", "Decent" end
function UnitName() return "Mad", "Decent" end
function GetUnitName() return "Mad Decent" end
function GetNormalizedRealmName() return "Decent" end
function GetTime() return 100 end
format = string.format
function strsplit(sep, s)
	local out = {}
	for part in (s .. sep):gmatch("(.-)" .. sep:gsub("%p", "%%%0")) do out[#out + 1] = part end
	return unpack(out)
end
unpack = unpack or table.unpack

local sent, timers, printed = {}, {}, {}
C_ChatInfo = {
	SendAddonMessage = function(prefix, msg, dist, target) sent[#sent + 1] = { prefix, msg, dist, target } return 0 end,
}
C_Timer = { After = function(_, fn) timers[#timers + 1] = fn end }
function GetChannelName() return 5 end

local ns = {}
ns.Print = function(msg) printed[#printed + 1] = msg end
ns.Version = function() return "0.2.0" end
assert(loadfile(ROOT .. "/Identity.lua"))("Soapstone", ns)
assert(loadfile(ROOT .. "/Net.lua"))("Soapstone", ns)
local I, Net = ns.Identity, ns.Net


-- Flavour
check(I.Flavor() == "forever", "1.60 on project 1 is forever")
local function flavorFor(build, project)
	BUILD, WOW_PROJECT_ID = build, project
	local fresh = {}
	assert(loadfile(ROOT .. "/Identity.lua"))("Soapstone", fresh)
	return fresh.Identity.Flavor()
end
check(flavorFor("11.2.5", 1) == "retail", "11.x on project 1 is retail")
check(flavorFor("1.15.7", 2) == "classic", "project 2 is classic")
check(flavorFor("5.5.1", 19) == "classic-19", "other classic projects keep their id")
BUILD, WOW_PROJECT_ID = "1.60.1", 1

-- Identity
check(I.PlayerKey() == "Mad-Decent", "own key is Mad-Decent")
check(I.PlayerDisplay() == "Mad Decent", "own display is Mad Decent")
check(I.KeyFromSender("Mad-Decent") == "Mad-Decent", "sender 'Mad-Decent' -> key")
check(I.KeyFromSender("Mad Decent") == "Mad-Decent", "sender 'Mad Decent' -> key")
check(I.KeyFromSender("Mad") == "Mad-Decent", "bare sender gets own realm part")
check(I.KeyFromSender("Jo-Area 52") == "Jo-Area52", "spaces in realm part dropped")
check(I.Display("Zug-Zug") == "Zug Zug", "display uses a space on forever")

-- Net: routing
local function receive(text, dist, sender) Net:OnMessage(text, dist, sender) end
receive("S1;forever;PING;123456;0.2.0", "CHANNEL", "Zug-Zug")
check(#sent == 1 and sent[1][3] == "WHISPER" and sent[1][4] == "Zug-Zug", "ping answered by whisper to the sender")
check(sent[1][2] == "S1;forever;PONG;123456;0.2.0;CHANNEL", "pong carries nonce, version, and how it arrived")
check(sent[1][1] == "Soapstone", "uses the Soapstone prefix")

receive("S1;retail;PING;1;0.2.0", "CHANNEL", "Zug-Zug")
check(#sent == 1, "other game flavours ignored")
receive("S2;forever;PING;1;0.2.0", "CHANNEL", "Zug-Zug")
check(#sent == 1, "other protocol versions ignored")
receive("S1;forever;PING;1;0.2.0", "CHANNEL", "Mad-Decent")
check(#sent == 1, "own channel echo ignored")
receive("S1;forever;PING;1;0.2.0", "CHANNEL", "Mad Decent")
check(#sent == 1, "own echo ignored in the space-separated form too")

-- Net: burst counting
receive("S1;forever;BURST;77;1;3", "CHANNEL", "Zug-Zug")
receive("S1;forever;BURST;77;2;3", "CHANNEL", "Zug-Zug")
receive("S1;forever;BURST;77;2;3", "CHANNEL", "Zug-Zug")
check(#timers == 1, "one settle timer per burst")
timers[1]()
check(sent[#sent][2] == "S1;forever;BURSTACK;77;2;3", "ack reports 2 unique of 3 (duplicate not double-counted)")

-- Net: sending
Net:Burst(3, "CHANNEL")
check(sent[#sent][4] == 5 and sent[#sent][2] == "S1;forever;BURST;" .. sent[#sent][2]:match("BURST;(%d+)") .. ";3;3",
	"burst goes to the channel number with i/n")
check(printed[#printed]:find("ok ×3") ~= nil, "burst tallies send results")

done()
