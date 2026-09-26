-- Store.lua (schema 2) and the Net send queue, starting from George's real
dofile(TESTS .. "/lib/harness.lua")
-- SavedVariables (schema 1, 10 stones). Run via run_edit_test.js.
local NOW = 1790400000
function time() return NOW end
format = string.format
unpack = unpack or table.unpack
function wipe(t) for k in pairs(t) do t[k] = nil end return t end
function GetBuildInfo() return "1.60.1", "70009", "", 16001 end
WOW_PROJECT_ID = 1
local who = { "Osha", "Compliant" }
function UnitFullName() return who[1], who[2] end
function GetNormalizedRealmName() return who[2] end
Enum = { UIMapType = { Zone = 3 }, SendAddonMessageResult = { Success = 0, AddonMessageThrottle = 3, ChannelThrottle = 8, GeneralError = 9 } }

-- Map tree: Durotar/Barrens/Thunder Bluff are zones; 9001 is a cave (micro)
-- inside the Barrens, 9002 a dungeon level inside that cave.
local MAPS = {
	[1411] = { mapType = 3, parentMapID = 1414 }, [1413] = { mapType = 3, parentMapID = 1414 },
	[1456] = { mapType = 3, parentMapID = 1414 }, [1414] = { mapType = 2, parentMapID = 947 },
	[9001] = { mapType = 5, parentMapID = 1413 }, [9002] = { mapType = 4, parentMapID = 9001 },
}
C_Map = { GetMapInfo = function(id) return MAPS[id] end }

assert(loadfile(FIXTURES .. "/savedvariables-schema1.lua"))() -- defines SoapstoneDB, exactly as WoW would
local ns = { db = SoapstoneDB }
ns.Print = function() end
assert(loadfile(ROOT .. "/Identity.lua"))("Soapstone", ns)
assert(loadfile(ROOT .. "/Store.lua"))("Soapstone", ns)
local Store = ns.Store

local function count(iter) local n = 0 for _ in iter do n = n + 1 end return n end

-- Zone keys
check(Store.ZoneKey(1413) == 1413, "a zone is its own zone key")
check(Store.ZoneKey(9001) == 1413, "a cave climbs to its zone")
check(Store.ZoneKey(9002) == 1413, "a dungeon level inside a cave climbs two levels")
check(Store.ZoneKey(1414) == 1414, "a continent stays itself")

-- Migration of the real file
check(#SoapstoneDB.stones == 10 and SoapstoneDB.schema == nil, "fixture is schema 1 with 10 stones in a list")
local upgraded = Store:Init()
check(upgraded == 10, "upgraded all 10 stones")
check(SoapstoneDB.schema == 2 and SoapstoneDB.stones[1] == nil, "now schema 2, keyed by id")
local all, zonesSeen, strangers, badVersion = 0, {}, 0, 0
for id, s in pairs(SoapstoneDB.stones) do
	all = all + 1
	if s.id ~= id then badVersion = badVersion + 100 end
	if s.v ~= 1 or s.flavor ~= "forever" then badVersion = badVersion + 1 end
	zonesSeen[s.zone or "nil"] = true
	if s.author == "A stranger" then strangers = strangers + 1; check(s.localOnly == true, "stranger test stone marked local-only") end
end
check(all == 10 and badVersion == 0, "every stone keyed by its id, v1, flavour forever")
check(zonesSeen[1411] and zonesSeen[1413] and zonesSeen[1456] and not zonesSeen["nil"], "zones filled in: Durotar, Barrens, Thunder Bluff")
check(Store:Init() == 0, "running Init again doesn't migrate twice")

-- Ownership follows the character, not the account
who = { "Osha", "Compliant" }
local s = Store:Stats()
check(s.live == 10 and s.mine == 1 and s.others == 8 and s.localOnly == 1, "as Osha: 1 mine, 8 Mad's, 1 test")
who = { "Mad", "Decent" }
s = Store:Stats()
check(s.mine == 8 and s.others == 1, "as Mad: 8 mine, Osha's counts as someone else's")

-- Spatial index, using the real Barrens stones
local barrens = { instance = 1, wx = -1450, wy = -3750 } -- near the sketches
local near = Store:Near(barrens, 60)
check(#near >= 2 and #near <= 6, "Near finds the stones around the Barrens sketches (" .. #near .. ")")
local far = Store:Near({ instance = 1, wx = 5000, wy = 5000 }, 100)
check(#far == 0, "nothing near an empty spot")
check(#Store:Near({ instance = 0, wx = -1450, wy = -3750 }, 60) == 0, "other continents excluded")
local all3 = Store:Near({ instance = 1, wx = -1000, wy = -2500 }, 4000)
check(#all3 == 10, "a wide search finds all 10")

-- Put, move, tombstone
local stone = Store:Put({ id = "Mad-Decent-1-1", authorKey = "Mad-Decent", instance = 1, wx = 0, wy = 0, mapID = 9001, t = NOW, text = "hi" })
check(stone.v == 1 and stone.zone == 1413 and stone.flavor == "forever", "Put fills version, zone (from a cave map) and flavour")
check(#Store:Near({ instance = 1, wx = 0, wy = 0 }, 10) == 1, "indexed at its position")
Store:Put({ id = "Mad-Decent-1-1", authorKey = "Mad-Decent", instance = 1, wx = 2000, wy = 0, mapID = 1413, t = NOW, text = "moved" })
check(#Store:Near({ instance = 1, wx = 0, wy = 0 }, 10) == 0 and #Store:Near({ instance = 1, wx = 2000, wy = 0 }, 10) == 1,
	"replacing a stone re-indexes it")
Store:Tombstone(Store:Get("Mad-Decent-1-1"))
local tomb = Store:Get("Mad-Decent-1-1")
check(tomb.deleted and tomb.v == 2 and tomb.text == nil and tomb.zone == 1413, "delete leaves a v2 tombstone without content")
check(#Store:Near({ instance = 1, wx = 2000, wy = 0 }, 10) == 0, "tombstones leave the spatial index")
check(SoapstoneDB.outbox["Mad-Decent-1-1"], "delete queued in the outbox")
check(Store:Stats().tombstones == 1 and Store:Stats().live == 10, "stats count tombstones separately")
NOW = NOW + Store.TOMBSTONE_TTL + 1
check(Store:PruneTombstones() == 1 and Store:Get("Mad-Decent-1-1") == nil, "tombstones pruned after 7 days")
check(SoapstoneDB.outbox["Mad-Decent-1-1"] == nil, "and dropped from the outbox")

-- Other games' stones stay invisible
Store:Put({ id = "Zug-Retail-1-1", authorKey = "Zug-Retail", flavor = "retail", instance = 1, wx = -1450, wy = -3750, mapID = 1413, t = NOW })
check(#Store:Near(barrens, 60) == #near, "a retail stone is never indexed on forever")
check(count(Store:Each()) == 10, "and Each skips it")
Store:Remove("Zug-Retail-1-1")

-- Caps: per zone keeps the newest; total drops the stalest zone first; own stones kept
Store.MAX_PER_ZONE, Store.MAX_TOTAL = 3, 5
who = { "Osha", "Compliant" }
for i = 1, 4 do
	Store:Put({ id = "Zug-A-" .. i, authorKey = "Zug-A", instance = 1, wx = 9000 + i, wy = 0, mapID = 1411, t = NOW + i })
end
SoapstoneDB.zones = { [1411] = { visited = NOW }, [1413] = { visited = NOW - 1000 }, [1456] = { visited = NOW - 5 } }
local removed = Store:Enforce()
check(Store:Get("Zug-A-1") == nil and Store:Get("Zug-A-4") ~= nil, "per-zone cap drops the oldest in Durotar")
local st = Store:Stats()
check(st.others + st.localOnly <= 5, "total cap respected (" .. (st.others + st.localOnly) .. " others left)")
check(st.mine == 1, "Osha's own stone survived")
local left = {}
for _, x in Store:Each() do
	if not Store.IsMine(x) then left[x.zone] = (left[x.zone] or 0) + 1 end
end
-- After per-zone trimming: Barrens 3, Durotar 3, Thunder Bluff 1 = 7, two
-- over. Exactly two go, from the least recently visited zone (Barrens).
check(left[1413] == 1, "stalest zone (Barrens) lost just enough: 3 -> 1")
check(left[1411] == 3 and left[1456] == 1, "recently visited Durotar and Thunder Bluff untouched")
vprint("     removed " .. removed .. " by caps")

done()
