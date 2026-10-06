-- What the addon leaves for the companion app: `meta` (game type, region,
-- build, characters) and `pending` (drops, edits, deletes, votes, unlocks).
-- Characters: Mad Decent and Osha Compliant on this account, Zug Zug elsewhere.
dofile(TESTS .. "/lib/harness.lua")
local NOW = 1790400000
function time() return NOW end
format = string.format
unpack = unpack or table.unpack
function wipe(t) for k in pairs(t) do t[k] = nil end return t end
function strtrim(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
function SecondsToTime(s) return s .. " sec" end
function GetBuildInfo() return "1.60.1", "70009", "", 16001 end
WOW_PROJECT_ID = 1
local region = 1
function GetCurrentRegion() return region end
local who = { "Mad", "Decent" }
function UnitFullName() return who[1], who[2] end
function UnitName() return who[1], who[2] end
function GetUnitName() return who[1] .. " " .. who[2] end
function GetNormalizedRealmName() return who[2] end

local pos = { x = 0, y = 0 }
local function vec(x, y) return { GetXY = function() return x, y end } end
C_Map = {
	GetMapInfo = function() return { mapType = 3 } end,
	GetBestMapForUnit = function() return 1413 end,
	GetPlayerMapPosition = function() return vec(0.5, 0.5) end,
	GetWorldPosFromMapPos = function() return 1, vec(pos.x, pos.y) end,
}
C_Timer = { NewTicker = function() return { Cancel = function() end } end }
UIErrorsFrame = { AddMessage = function() end }

local ns = {}
assert(loadfile(ROOT .. "/Identity.lua"))("Soapstone", ns)
assert(loadfile(ROOT .. "/Store.lua"))("Soapstone", ns)
assert(loadfile(ROOT .. "/Sketch.lua"))("Soapstone", ns)
assert(loadfile(ROOT .. "/Stones.lua"))("Soapstone", ns)
ns.Print = function() end
ns.Version = function() return "0.5.0" end
ns.Cues = { Play = function() end }
ns.MinimapPins = { Update = function() end }
ns.MinimapButton = { SetGlow = function() end }
ns.ReadWindow = { Current = function() return nil end, Show = function() end, Hide = function() end }
ns.Sync = { OnZone = function() end }
ns.Guide = { Check = function() end }
local Store, Stones = ns.Store, ns.Stones

local function stone(id, author, fields)
	local s = { id = id, v = 1, authorKey = author, author = author and (author:gsub("%-", " ", 1)), flavor = "forever",
		zone = 1413, instance = 1, wx = 0, wy = 0, mapID = 1413, t = NOW, text = "hello" }
	for k, v in pairs(fields or {}) do s[k] = v end
	return s
end

-- A save from 0.4: own stones, an old-format id, a test stone, a stranger's.
ns.db = {
	schema = 2, zones = {}, ratings = {}, gateYards = 40, nearYards = 150,
	outbox = { ["Mad-Decent-1-2"] = true },
	stones = {
		["Mad-Decent-1-1"] = stone("Mad-Decent-1-1", "Mad-Decent", { mine = true }),
		["Mad-Decent-1-2"] = stone("Mad-Decent-1-2", "Mad-Decent", { v = 2, deleted = true, deletedAt = NOW, text = false }),
		["Osha-Compliant-1-1"] = stone("Osha-Compliant-1-1", "Osha-Compliant", { mine = true }),
		["1790363195-7862"] = stone("1790363195-7862", "Mad-Decent", { mine = true }),
		["local-1-0001"] = stone("local-1-0001", nil, { localOnly = true, author = "A stranger" }),
		["Zug-Zug-1-1"] = stone("Zug-Zug-1-1", "Zug-Zug", { wx = 100 }),
	},
}
ns.db.stones["Mad-Decent-1-2"].text = nil

Store:RecordMeta()
local meta = ns.db.meta
check(meta.flavor == "forever" and meta.region == "us" and meta.regionId == 1, "meta: game type and region (1 = us)")
check(meta.build == "1.60.1.70009" and meta.addon == "0.5.0", "meta: build and addon version")
check(meta.characters["Mad-Decent"] and meta.characters["Mad-Decent"].name == "Mad Decent"
	and meta.characters["Mad-Decent"].seen == NOW, "meta: the character logging in, with when")

Store:Init()
local p = ns.db.pending
check(p.stones["Mad-Decent-1-1"] == 1, "first load queues your earlier stones")
check(p.stones["Osha-Compliant-1-1"] == 1, "including your other characters'")
check(p.stones["Mad-Decent-1-2"] == 2, "and changes still in the outbox (a delete, at its tombstone's version)")
check(p.stones["1790363195-7862"] == nil, "but not stones whose id doesn't carry their author (the server refuses them)")
check(p.stones["local-1-0001"] == nil and p.stones["Zug-Zug-1-1"] == nil, "nor test stones or other players' stones")

p.stones["Mad-Decent-1-1"] = nil -- as if acknowledged
Store:Init()
check(ns.db.pending.stones["Mad-Decent-1-1"] == nil, "seeding happens once, not on every load")
ns.db.pending.stones = {}

-- Drops, edits, deletes.
local dropped = Stones:Drop({ text = "Praise the sun!" })
check(ns.db.pending.stones[dropped.id] == 1, "a drop is queued at version 1")
Stones:Edit(dropped, { text = "Praise the moon!" })
check(ns.db.pending.stones[dropped.id] == 2, "an edit raises the queued version")
Stones:Delete(dropped)
check(ns.db.pending.stones[dropped.id] == 3 and Store:Get(dropped.id).deleted, "a delete queues the tombstone")

-- Votes.
local zug = Store:Get("Zug-Zug-1-1")
Stones:Vote(zug, Stones.APPRAISE)
check(ns.db.pending.votes["Zug-Zug-1-1"]["Mad-Decent"] == 1, "appraising a stranger's stone queues +1")
Stones:Vote(zug, Stones.APPRAISE)
check(ns.db.pending.votes["Zug-Zug-1-1"]["Mad-Decent"] == 0, "taking it back queues 0, so the server forgets it too")
Stones:Vote(zug, Stones.DISPARAGE)
check(ns.db.pending.votes["Zug-Zug-1-1"]["Mad-Decent"] == -1, "disparaging queues -1")
Stones:Vote(Store:Get("Mad-Decent-1-1"), Stones.DISPARAGE)
check(ns.db.pending.votes["Mad-Decent-1-1"] == nil, "votes on your own stones stay local")

who = { "Osha", "Compliant" }
Store:RecordMeta()
check(ns.db.meta.characters["Osha-Compliant"] and ns.db.meta.characters["Mad-Decent"], "meta keeps every character seen")
Stones:Vote(Store:Get("Mad-Decent-1-1"), Stones.APPRAISE)
check(ns.db.pending.votes["Mad-Decent-1-1"] == nil, "and so do votes on your other characters' stones")
Stones:Vote(zug, Stones.APPRAISE)
check(ns.db.pending.votes["Zug-Zug-1-1"]["Osha-Compliant"] == 1 and ns.db.pending.votes["Zug-Zug-1-1"]["Mad-Decent"] == -1,
	"each character's vote is queued separately")

-- Unlocks.
pos.x = 0
Stones:CheckProximity()
check(ns.db.pending.unlocks["Zug-Zug-1-1"] == nil, "a stone out of reach isn't unlocked")
pos.x = 80
Stones:CheckProximity()
check(Store.IsHeard(Store:Get("Zug-Zug-1-1")), "walking up to a stranger's stone opens it")
check(ns.db.pending.unlocks["Zug-Zug-1-1"]["Osha-Compliant"] == NOW, "and queues the unlock with who and when")
NOW = NOW + 60
Store:Unlock(zug)
check(ns.db.pending.unlocks["Zug-Zug-1-1"]["Osha-Compliant"] == NOW - 60, "a repeat keeps the first unlock time")
Store:Unlock(Store:Get("Mad-Decent-1-1"))
check(ns.db.pending.unlocks["Mad-Decent-1-1"] == nil, "your own characters' stones don't count as unlocks")
check(Store.IsHeard(Store:Get("Mad-Decent-1-1")), "(but Osha has read Mad's stone now)")

-- Read is per character.
who = { "Mad", "Decent" }
check(not Store.IsHeard(zug), "Mad hasn't read the stone Osha opened")
Stones:Vote(zug, Stones.APPRAISE) -- he'd disparaged it, and disparaged stones never open
pos.x = 0
Stones:CheckProximity()
pos.x = 80
Stones:CheckProximity()
check(Store.IsHeard(zug) and ns.db.pending.unlocks["Zug-Zug-1-1"]["Mad-Decent"] == NOW,
	"until he walks up to it himself, which queues his own unlock")
check(ns.db.pending.unlocks["Zug-Zug-1-1"]["Osha-Compliant"] == NOW - 60, "next to Osha's")
local old = Store:Put(stone("Zug-Zug-1-9", "Zug-Zug", { heard = true, wx = 5000 }))
check(Store.IsHeard(old, "Mad-Decent") and Store.IsHeard(old, "Osha-Compliant"),
	"a stone read before 0.5 (heard = true, no names) counts as read by everyone")
check(Store.IsHeard(dropped, "Mad-Decent") and not Store.IsHeard(dropped, "Osha-Compliant"),
	"a drop counts as read by its author only")

check(Store:PendingCount() == 1 + 2 + 2, "PendingCount: 1 stone, 2 votes, 2 unlocks")

-- A delete waiting for the companion outlives the tombstone TTL.
NOW = NOW + Store.TOMBSTONE_TTL + 1
Store:PruneTombstones()
check(Store:Get(dropped.id) and Store:Get(dropped.id).deleted, "an unsent delete's tombstone is kept past its TTL")
ns.db.pending.stones[dropped.id] = nil
Store:PruneTombstones()
check(Store:Get(dropped.id) == nil, "and pruned once it's been sent")

-- Regions.
region = 3
Store:RecordMeta()
check(ns.db.meta.region == "eu", "3 = eu")
region = 90
Store:RecordMeta()
check(ns.db.meta.region == "test" and ns.db.meta.regionId == 90, "90 (WoW Forever's beta) = test")
region = 98
Store:RecordMeta()
check(ns.db.meta.region == nil and ns.db.meta.regionId == 98, "an unknown region is left blank, with the raw id kept")
GetCurrentRegion = nil
Store:RecordMeta()
check(ns.db.meta.region == nil and ns.db.meta.regionId == nil, "a client without GetCurrentRegion")

Store:Clear()
check(Store:PendingCount() == 0, "/soap clear empties the queue too")

-- Build 70235 labelled Forever stones "classic-18": they come back as forever
-- and join the queue, next to what was already waiting.
ns.db.stones = {
	["Mad-Decent-2-1"] = stone("Mad-Decent-2-1", "Mad-Decent", { mine = true, flavor = "classic-18" }),
	["Mad-Decent-2-2"] = stone("Mad-Decent-2-2", "Mad-Decent", { mine = true }),
	["Zug-Zug-2-1"] = stone("Zug-Zug-2-1", "Zug-Zug", { flavor = "classic-18" }),
}
ns.db.pending = { stones = { ["Mad-Decent-2-1"] = 1 } }
Store:Init()
check(Store:Get("Mad-Decent-2-1").flavor == "forever" and Store:Get("Zug-Zug-2-1").flavor == "forever",
	"classic-18 stones are relabelled forever")
local seen = 0
for _ in Store:Each() do seen = seen + 1 end
check(seen == 3, "and show again")
check(ns.db.pending.stones["Mad-Decent-2-2"] == 1 and ns.db.pending.stones["Mad-Decent-2-1"] == 1,
	"your stones hidden by the old label join the queue")
check(ns.db.pending.stones["Zug-Zug-2-1"] == nil, "others' don't")

done()
