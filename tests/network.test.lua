-- Networking is opt-in (0.3.1): Core's defaults and 0.3.0-save cleanup, and
-- Net:Init / "/soap net join|leave" deciding whether to be in the channel.
dofile(TESTS .. "/lib/harness.lua")
format = string.format
unpack = unpack or table.unpack
function wipe(t) for k in pairs(t) do t[k] = nil end return t end
function CopyTable(t) local c = {} for k, v in pairs(t) do c[k] = type(v) == "table" and CopyTable(v) or v end return c end
function GetBuildInfo() return "1.60.1", "70009", "", 16001 end
WOW_PROJECT_ID = 1
function UnitFullName() return "Mad", "Decent" end
function GetNormalizedRealmName() return "Decent" end
SlashCmdList = {}

local joined, joins, leaves, printed = false, 0, 0, {}
function GetChannelName() return joined and 6 or 0 end
function JoinTemporaryChannel() joined = true; joins = joins + 1 end
function LeaveChannelByName() joined = false; leaves = leaves + 1 end
C_ChatInfo = { RegisterAddonMessagePrefix = function() end }
C_Timer = { After = function(_, fn) fn() end } -- run delayed joins straight away

local bootFrame
function CreateFrame()
	local frame = { events = {} }
	function frame:RegisterEvent(e) self.events[e] = true end
	function frame:UnregisterEvent() end
	function frame:SetScript(_, fn) self.OnEvent = fn end
	if not bootFrame then bootFrame = frame end -- Core.lua's is the first frame made
	return frame
end

local function load(save)
	SoapstoneDB, bootFrame = save, nil
	joins, leaves, printed = 0, 0, {}
	local ns = {}
	for _, file in ipairs({ "Core.lua", "Identity.lua", "Net.lua", "Sync.lua" }) do
		assert(loadfile(ROOT .. "/" .. file))("Soapstone", ns)
	end
	ns.Print = function(msg) printed[#printed + 1] = msg end
	bootFrame.OnEvent(bootFrame, "ADDON_LOADED", "Soapstone") -- what WoW does on login
	return ns
end

-- A fresh install: off.
joined = false
local ns = load(nil)
check(ns.db.network == false, "a fresh install has networking off")
ns.Net:Init()
check(joins == 0 and not joined, "and doesn't join the channel at login")

-- Upgrading from 0.3.0, whose save said net = true: off too.
ns = load({ net = true, stones = {} })
check(ns.db.net == nil and ns.db.network == false, "0.3.0's 'net = true' is dropped; networking is off")
ns.Net:Init()
check(joins == 0, "and it doesn't join")

-- Still in the channel from before a /reload: leave it.
joined = true
ns = load({ stones = {} })
ns.Net:Init()
check(leaves == 1 and not joined, "a leftover channel is left at login")

-- Opting in.
joined = false
ns = load({ stones = {} })
ns.Net:Init()
ns.Net:Command("join")
check(ns.db.network == true and joined, "/soap net join turns it on and joins")
check(printed[#printed]:find("Networking on") ~= nil, "and says so")
joined = false   -- a fresh login: temporary channels don't carry over
ns = load(ns.db) -- next login with the same save
ns.Net:Init()
check(joins == 1 and joined, "the choice sticks: next login joins by itself")
ns.Net:Command("leave")
check(ns.db.network == false and not joined, "/soap net leave turns it off and leaves")

-- With networking off, /soap net sync says how to turn it on.
ns.Sync.zone = 1413
ns.Sync:Command("now")
check(printed[#printed]:find("Networking is off") ~= nil, "/soap net sync now explains networking is off")

done()
