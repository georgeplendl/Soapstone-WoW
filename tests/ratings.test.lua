-- Appraise / disparage: Store ratings and Stones:Rate, plus their effect on
-- proximity cues. Characters: Mad Decent (rater) and Osha Compliant.
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
local who = { "Mad", "Decent" }
function UnitFullName() return who[1], who[2] end
function UnitName() return who[1], who[2] end
function GetNormalizedRealmName() return who[2] end
C_Map = { GetMapInfo = function() return { mapType = 3 } end }
C_Timer = { NewTicker = function() return { Cancel = function() end } end }
local messages = {}
UIErrorsFrame = { AddMessage = function(_, msg) messages[#messages + 1] = msg end }

local ns = {}
assert(loadfile(ROOT .. "/Identity.lua"))("Soapstone", ns)
assert(loadfile(ROOT .. "/Store.lua"))("Soapstone", ns)
assert(loadfile(ROOT .. "/Stones.lua"))("Soapstone", ns)
ns.Print = function() end
ns.db = { stones = {}, zones = {}, outbox = {}, gateYards = 40, nearYards = 150 }
local cues, pins = {}, 0
ns.Cues = { Play = function(_, name) cues[#cues + 1] = name end }
ns.MinimapPins = { Update = function() pins = pins + 1 end }
ns.MinimapButton = { SetGlow = function() end }
ns.ReadWindow = { Current = function() return nil end }
ns.Sync = { OnZone = function() end }
local Store, Stones = ns.Store, ns.Stones
Store:Init()
check(type(ns.db.ratings) == "table", "Init adds the ratings table to an existing save")

local function put(id, author, fields)
	local s = { id = id, authorKey = author, author = (author:gsub("%-", " ", 1)), instance = 1,
		wx = 0, wy = 0, mapID = 1413, t = NOW, text = "hello" }
	for k, v in pairs(fields or {}) do s[k] = v end
	return Store:Put(s)
end
local zug = put("Zug-Zug-1-1", "Zug-Zug")
local own = put("Mad-Decent-1-1", "Mad-Decent")
local A, D = Stones.APPRAISE, Stones.DISPARAGE

-- Someone else's stone: +1 / -1, clicking the same arrow again takes it back.
check(Stones:Rating(zug) == 0 and Stones:Score(zug) == 1, "a stranger's stone starts at score 1 (its author's upvote)")
check(Stones:Vote(zug, A) == A and Stones:Rating(zug) == A and Stones:Score(zug) == 2, "appraise: score 2")
check(cues[#cues] == "appraise" and messages[#messages]:find("You appraised Zug Zug's soapstone") ~= nil,
	"with a sound and a message")
check(Stones:Vote(zug, A) == 0 and Stones:Score(zug) == 1, "clicking again takes it back")
check(messages[#messages] == "You withdrew your appraisal.", "and says so")
check(ns.db.ratings[zug.id] == nil, "an empty vote leaves nothing behind")
check(Stones:Vote(zug, D) == D and Stones:Score(zug) == 0 and cues[#cues] == "disparage", "disparage: score 0")
check(Stones:Vote(zug, A) == A and Stones:Score(zug) == 2, "switching straight from down to up")
check(pins == 4, "pins are restyled after each of the 4 changes")

-- Your own stone: already upvoted; you can take that back but not go below 0.
check(Stones:Rating(own) == A and Stones:Score(own) == 1, "your own stone starts upvoted (score 1)")
check(Stones:OthersRating(own) == 0, "but that doesn't count as appraising it (no gold pin)")
check(Stones:Vote(own, D) == 0 and Stones:Score(own) == 0, "downvoting your own takes your upvote back: score 0")
check(messages[#messages] == "You withdrew your appraisal.", "and says so, in Dark Souls terms")
check(Stones:Vote(own, D) == 0 and Stones:Score(own) == 0, "it can't go below 0")
check(Stones:Vote(own, A) == A and Stones:Score(own) == 1, "upvoting restores it")
check(ns.db.ratings[own.id] == nil, "the default upvote isn't stored")
check(Stones:Vote(own, A) == 0 and Stones:Score(own) == 0, "clicking ▲ again takes it back too, like Reddit")
Stones:Vote(own, A)

-- Per character: votes from your characters add up.
who = { "Osha", "Compliant" }
check(Stones:Rating(zug) == 0, "Osha doesn't see Mad's vote as her own")
check(Stones:Rating(own) == 0 and Stones:Score(own) == 1, "Mad's stone isn't Osha's: she hasn't voted, score 1")
Stones:Vote(own, A)
check(Stones:Score(own) == 2, "Osha appraises Mad's stone: score 2")
Stones:Vote(zug, D)
check(Stones:Rating(zug) == D and Stones:Score(zug) == 1, "Osha's down + Mad's up on Zug's stone: score 1")
who = { "Mad", "Decent" }
check(Stones:Rating(zug) == A and Stones:Score(own) == 2, "Mad sees his own vote, and Osha's in the score")

-- What can't be voted on
local gone = put("Zug-Zug-1-2", "Zug-Zug")
Store:Tombstone(gone)
check(Stones:Vote(Store:Get(gone.id), A) == nil, "a deleted stone")

-- Votes live apart from the stone record
put("Zug-Zug-1-1", "Zug-Zug", { v = 2, text = "a fresh copy" })
check(Stones:Rating(Store:Get("Zug-Zug-1-1")) == A, "a fresh copy of the stone keeps your vote")
local evicted = put("Zug-Zug-1-3", "Zug-Zug")
Stones:Vote(evicted, D)
Store:Remove(evicted.id)
check(ns.db.ratings[evicted.id] == nil, "an evicted stone's votes go with it")
Store:Clear()
check(next(ns.db.ratings) == nil, "/soap clear clears votes too")

-- Disparaged stones never call you over
local here = { mapID = 1413, instance = 1, wx = 0, wy = 0 }
function Stones:GetPlayerLocation() return here end
function Stones:OnUnlock(stone) stone.unlocked = true end
local near = put("Zug-Zug-2-1", "Zug-Zug", { wx = 20, wy = 0 })
local shunned = put("Zug-Zug-2-2", "Zug-Zug", { wx = -20, wy = 0 })
Stones:Vote(shunned, D)
cues = {}
Stones:CheckProximity()
check(near.heard and near.unlocked, "a normal stone in range unlocks")
check(not shunned.heard and not shunned.unlocked, "a disparaged one in range doesn't")
local reads = 0
for _, c in ipairs(cues) do if c == "read" then reads = reads + 1 end end
check(reads == 1, "one read cue, for the normal stone only")

done()
