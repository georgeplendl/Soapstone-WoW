-- Loading SoapstoneData (Companion.lua): the file the companion app writes.
-- fixtures/companion/Stones.lua is written by the companion's own test
-- (companion/src-tauri/src/soapdata.rs, `UPDATE_FIXTURES=1 cargo test`), so
-- this checks the two sides agree on the format.
-- Characters: Mad Decent and Osha Compliant on this account.
dofile(TESTS .. "/lib/harness.lua")
local NOW = 1791234567 + 120
function time() return NOW end
format = string.format
unpack = unpack or table.unpack
function wipe(t) for k in pairs(t) do t[k] = nil end return t end
function strtrim(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
function SecondsToTime(s) return s .. " sec" end
function GetBuildInfo() return "1.60.1", "70235", "", 16001 end
WOW_PROJECT_ID, WOW_PROJECT_CAMELOT = 18, 18
local region = 90
function GetCurrentRegion() return region end
local who = { "Mad", "Decent" }
function UnitFullName() return who[1], who[2] end
function UnitName() return who[1], who[2] end
function GetUnitName() return who[1] .. " " .. who[2] end
function GetNormalizedRealmName() return who[2] end
C_Map = { GetMapInfo = function() return { mapType = 3, name = "The Barrens" } end }

local ns, printed = {}, {}
for _, file in ipairs({ "Identity", "Store", "Codec", "Sketch", "Stones", "Companion" }) do
	assert(loadfile(ROOT .. "/" .. file .. ".lua"))("Soapstone", ns)
end
ns.Print = function(msg) printed[#printed + 1] = msg end
ns.Version = function() return "0.5.0" end
ns.MinimapPins = { Update = function() end }
local Store, Stones, Companion, Codec = ns.Store, ns.Stones, ns.Companion, ns.Codec

-- Codec pieces the format rests on.
check(Codec.Base64Encode("foo") == "Zm9v" and Codec.Base64Encode("fo") == "Zm8=" and Codec.Base64Encode("f") == "Zg==",
	"base64 encodes like the companion")
check(Codec.Base64Decode("Zm9v") == "foo" and Codec.Base64Decode("Zm8=") == "fo" and Codec.Base64Decode("Zg==") == "f",
	"and decodes")
for _, bad in ipairs({ "Zm9", "Zm9v\"", "Z===", "Zg=a", "a\"..os.exit()..\"", 42 }) do
	check(Codec.Base64Decode(bad) == nil, "refuses bad base64: " .. tostring(bad))
end
local s = Codec.Scramble("Zug-Zug-1-1", "Praise the sun!")
check(s:match("^[A-Za-z0-9+/=]+$") and not s:find("Praise"), "scrambled text is base64 and unreadable")
check(Codec.Unscramble("Zug-Zug-1-1", s) == "Praise the sun!", "and unscrambles with the same id")
check(Codec.Unscramble("Zug-Zug-1-2", s) ~= "Praise the sun!", "but not with another")

-- This account's save before loading.
local function stone(id, author, fields)
	local st = { id = id, v = 1, authorKey = author, author = (author:gsub("%-", " ", 1)), flavor = "forever",
		zone = 1413, instance = 1, wx = 0, wy = 0, mapID = 1413, t = 1791000000, text = "hello" }
	for k, v in pairs(fields or {}) do st[k] = v end
	return st
end
ns.db = {
	schema = 2, zones = {}, ratings = {}, outbox = {}, gateYards = 40, nearYards = 150,
	meta = { characters = { ["Mad-Decent"] = {}, ["Osha-Compliant"] = {} } },
	stones = {
		["Osha-Compliant-1790000000-1"] = stone("Osha-Compliant-1790000000-1", "Osha-Compliant", { mine = true, text = "mine" }),
		["Gone-Away-1791000000-1"] = stone("Gone-Away-1791000000-1", "Gone-Away"),
		["Rude-Person-1791000000-1"] = stone("Rude-Person-1791000000-1", "Rude-Person"),
		["Mad-Decent-1791000000-9"] = stone("Mad-Decent-1791000000-9", "Mad-Decent", { mine = true }),
		["Mad-Decent-1791000000-1"] = stone("Mad-Decent-1791000000-1", "Mad-Decent", { mine = true }),
		["Mad-Decent-1791000000-2"] = stone("Mad-Decent-1791000000-2", "Mad-Decent", { mine = true, v = 2 }),
		["Mad-Decent-1791000000-3"] = stone("Mad-Decent-1791000000-3", "Mad-Decent", { mine = true }),
	},
	pending = {
		stones = { ["Mad-Decent-1791000000-1"] = 1, ["Mad-Decent-1791000000-2"] = 2, ["Mad-Decent-1791000000-3"] = 1 },
		votes = { ["Zug-Zug-1791200000-1"] = { ["Mad-Decent"] = 1 }, ["Gone-Away-1791000000-1"] = { ["Mad-Decent"] = -1 } },
		unlocks = { ["Zug-Zug-1791200000-1"] = { ["Mad-Decent"] = 1791205000, ["Osha-Compliant"] = 1791220000 } },
	},
}
Store:Init()
check(Companion:Status() == "Companion: not installed", "before loading: not installed")

local file = readFile(FIXTURES .. "/companion/Stones.lua")
check(file ~= nil, "the companion's fixture exists")
assert(load(file))()
local out = Companion:Load()
check(Companion.state == "ok" and out.skipped == 0, "the companion's file loads, every record valid")

-- Stones from the database.
local zug = Store:Get("Zug-Zug-1791200000-1")
check(zug and zug.text == nil and zug.scrambled and not zug.scrambled:find("Praise"),
	"a stranger's stone arrives with its words scrambled (also in SavedVariables)")
check(Stones.TextOf(zug) == "Praise the sun! ~;||% \"quotes\" café", "and shows them unscrambled, escapes and UTF-8 intact")
check(zug.author == "Zug Zug" and zug.score == 3 and zug.found == 14 and zug.inDatabase, "with its author, score and found count")
check(zug.wx == -1450.2 and zug.x == 0.5123 and zug.zone == 1413 and zug.flavor == "forever", "and its position")
check(#Store:Near({ instance = 1, wx = -1450, wy = -3750 }, 10) >= 1, "it's on the map")
check(not Store.IsHeard(zug), "sealed for Mad")
check(Store.IsHeard(zug, "Osha-Compliant") and zug.heardBy["Osha-Compliant"] == 1791210000,
	"but read by Osha, from the server's record of her unlock (earlier than hers here)")
check(ns.db.pending.unlocks["Zug-Zug-1791200000-1"] == nil, "which settles both pending unlocks (Mad's was acknowledged)")
local sketch = Store:Get("Zug-Zug-1791200000-2")
check(sketch and sketch.sketchId == "sk_9f2c41e07ab35d18" and sketch.v == 2 and sketch.edited == 1791200100,
	"a drawing arrives by its sketch id")
check(Stones.IsSketch(sketch) and Stones:Summary(sketch) == "a sketch" and Stones.TextOf(sketch) == nil, "and counts as a sketch")
local restored = Store:Get("Mad-Decent-1791100000-1")
check(restored and restored.text == "Restored from the database" and restored.mine and Store.IsMine(restored),
	"one of your stones missing here is restored, words in the clear (they're yours)")
local osha = Store:Get("Osha-Compliant-1790000000-1")
check(osha.text == "mine" and osha.v == 1 and osha.score == 9 and osha.inDatabase,
	"your own copy is never replaced, but learns its score")

-- Removals.
check(Store:Get("Gone-Away-1791000000-1").deleted, "a stone its author deleted is removed")
local rude = Store:Get("Rude-Person-1791000000-1")
check(rude.deleted and rude.why == "hidden", "a hidden stone is removed, saying why")
local own = Store:Get("Mad-Decent-1791000000-9")
check(not own.deleted and own.notShared == "rejected", "your own refused stone stays, marked not shared")

-- Acknowledgements and refusals.
local p = ns.db.pending
check(p.stones["Mad-Decent-1791000000-1"] == nil and Store:Get("Mad-Decent-1791000000-1").inDatabase,
	"an acknowledged drop leaves pending")
check(p.stones["Mad-Decent-1791000000-2"] == 2, "an edit made after the upload stays (the ack was for v1)")
check(p.votes["Zug-Zug-1791200000-1"] == nil, "an acknowledged vote leaves pending")
check(ns.db.sharedVotes["Zug-Zug-1791200000-1"] == 1, "and is recorded as the vote the server counts")
check(Stones:Score(zug) == 4 and Stones:FoundCount(zug) == 14,
	"so the stone shows the server's score (3) plus its author's point, and its found count")
check(p.stones["Mad-Decent-1791000000-3"] == nil and Store:Get("Mad-Decent-1791000000-3").notShared == "too many nearby",
	"a refused stone leaves pending, marked with the reason")
check(p.votes["Gone-Away-1791000000-1"]["Mad-Decent"] == -1, "a vote refused for today stays, to try again")
Companion:AnnounceRefusals()
check(#printed == 1 and printed[1]:find("Your stone in The Barrens wasn't shared: there are already stones right there") ~= nil,
	"you're told why your stone wasn't shared")

-- Loading again (every /reload) changes nothing and says nothing new.
local before = #printed
out = Companion:Load()
Companion:AnnounceRefusals()
check(#printed == before, "a refusal is announced once")
check((out.added or 0) == 0 and (out.updated or 0) == 0 and (out.restored or 0) == 0 and (out.removed or 0) == 0,
	"reloading the same file changes nothing")

-- Status line.
check(Companion:Status() == "Companion: synced 2 mins ago", "status: synced 2 mins ago")
check(Companion:Status(1791234567 + 3 * 86400) == "Companion: not running (last synced 3 days ago)",
	"status: not running, once the file is older than 15 minutes")

-- Drawings (Sketches.lua, also written by the companion's test).
check(Stones.SketchOf(sketch) == nil, "without Sketches.lua a drawing from the database can't be shown")
assert(load(readFile(FIXTURES .. "/companion/Sketches.lua")))()
local loaded, skipped = Companion:LoadSketches(nil, 1791234567 + 60)
check(loaded == 1 and skipped == 0, "the companion's drawings load (it leaves invalid ones out itself)")
local drawing = Stones.SketchOf(sketch)
check(drawing and drawing.w == 160 and drawing.h == 60 and ns.Sketch.Unpack(drawing) ~= nil,
	"and the sketch stone now has its drawing")
check(not next(ns.db.stones[sketch.id].sketch or {}), "drawings stay out of SavedVariables")
check(Companion:LoadSketches(nil, 1791234567 + Companion.STALE + 1) == 0 and Stones.SketchOf(sketch) == nil,
	"a Sketches.lua older than 15 minutes is ignored (the companion isn't running)")
local scope = Codec.Base64Encode("forever~test")
local function sketches(records) return { format = 1, writtenAt = NOW, scope = scope, records = records } end
local good = SoapstoneData_Sketches.records[1]
check(select(2, Companion:LoadSketches(sketches({
	Codec.Base64Encode("sk_9f2c41e07ab35d18~160~60~***"),
	Codec.Base64Encode("sk_9f2c~160~60~k0DD"),
	Codec.Base64Encode("sk_9f2c41e07ab35d18~10~60~k0DD"),
	Codec.Base64Encode("sk_9f2c41e07ab35d18~160~60~" .. ("/"):rep(50)),
	"not base64",
}), NOW)) == 5, "bad ids, sizes and data are skipped")
check(Companion:LoadSketches({ format = 1, writtenAt = NOW, scope = Codec.Base64Encode("classic~us"), records = { good } }, NOW) == 0,
	"another game's drawings are ignored")

-- Sync: a reload, when there's a companion to sync with.
local reloads = 0
function ReloadUI() reloads = reloads + 1 end
check(Companion:Sync() and reloads == 1, "Sync reloads the UI so the companion's latest files load")

-- Files that aren't for us, or aren't right.
local function load(data)
	Companion:Load(data)
	return Companion.state
end
Companion:Load(false) -- no SoapstoneData at all
Companion.state = "none"
local before = #printed
check(Companion:Sync() == false and reloads == 1, "without a companion, Sync doesn't reload")
check(#printed == before + 1 and printed[#printed]:find("companion app") ~= nil, "it says what the companion is instead")
check(load({ format = 2, records = {} }) == "outdated", "an unknown format: update the companion")
check(Companion:Status() == "Companion: update the Soapstone companion", "and says so")
check(load({ format = 1, scope = Codec.Base64Encode("classic~us"), records = {} }) == "elsewhere", "another game's stones are ignored")
check(load({ format = 1, scope = Codec.Base64Encode("forever~eu"), records = {} }) == "elsewhere", "and another region's")
check(load("oops") == "unreadable" and load({ format = 1 }) == "unreadable", "a broken file is unreadable, not an error")
local evil = {
	"not base64!",
	Codec.Base64Encode("S~1~1~" .. ("x~"):rep(15) .. "x"),
	Codec.Base64Encode("R~Someone-1-1~1~1413~because"),
	Codec.Base64Encode("Q~what"),
	Codec.Base64Encode("S~1~1~Fake-1-1~1~Zug-Zug~1791000000~1413~1~0~0~1413~0.5~0.5~~T~" .. Codec.Scramble("Fake-1-1", "hi") .. "~~"),
	Codec.Base64Encode("S~1~1~Zug-Zug-9-9~1~Zug-Zug~1791000000~1413~1~0~0~1413~0.5~0.5~~T~" .. Codec.Scramble("Zug-Zug-9-9", ("long "):rep(40)) .. "~~"),
}
out = Companion:Load({ format = 1, scope = Codec.Base64Encode("forever~test"), writtenAt = NOW, records = evil })
check(out.skipped == #evil, "malformed, unknown, forged and over-long records are all skipped")
check(Store:Get("Zug-Zug-9-9") == nil and Store:Get("Fake-1-1") == nil, "and add nothing")

-- Abuse (adversarial review 2026-10-06).
check(Codec.IdBelongsTo("Mad-Decent-1791000000-1", "Mad-Decent"), "an id is <author>-<time>-<n>")
check(not Codec.IdBelongsTo("Mad-Decent-1791000000-1", "Mad"), "a short name can't take a longer name's ids")
check(not Codec.IdBelongsTo("Mad-Decent-x-1", "Mad-Decent") and not Codec.IdBelongsTo("Mad-Decent-1", "Mad-Decent"),
	"and nothing looser passes")
check(Codec.Neutralize("|cffff0000Free gold|r") == "||cffff0000Free gold||r", "escape codes become plain text")
check(Codec.Neutralize("left || right") == "left || right" and Codec.Neutralize("plain") == "plain", "safe text is left alone")
check(Codec.Neutralize("|||Hx") == "||||Hx", "an odd run of pipes is evened up")
check(Codec.HasEscapeCodes("|Hurl:x|h[click]|h") and not Codec.HasEscapeCodes("a || b") and not Codec.HasEscapeCodes("a | b"),
	"live escape codes are spotted; plain pipes aren't")
local function record(fields)
	return "S~1~1~" .. table.concat(fields, "~")
end
local forged = {
	Codec.Base64Encode(record({ "Mad-Decent-1791000000-1", "1", "Mad", "1791000000", "1413", "1", "0", "0", "1413", "0.5", "0.5", "",
		"T", Codec.Scramble("Mad-Decent-1791000000-1", "hijacked"), "", "" })),
	Codec.Base64Encode(record({ "Zug-Zug-1791000000-77", "1", "Zug-Zug", "1791000000", "1413", "1", "0", "0", "1413", "0.5", "0.5", "",
		"T", Codec.Scramble("Zug-Zug-1791000000-77", "|cffff0000Blizzard:|r your account is banned"), "", "" })),
	Codec.Base64Encode(record({ "Zug%7CZug-1791000000-1", "1", "Zug%7CZug", "1791000000", "1413", "1", "0", "0", "1413", "0.5", "0.5", "",
		"T", Codec.Scramble("Zug|Zug-1791000000-1", "a name with a pipe"), "", "" })),
}
out = Companion:Load({ format = 1, scope = Codec.Base64Encode("forever~test"), writtenAt = NOW, records = forged })
check(out.skipped == 3, "a hijacked id, escape codes in the words and a pipe in a name are all refused")

-- Even a stone that got in some other way can't replace another author's.
local mine = Store:Get("Mad-Decent-1791000000-1")
check(Store:MergeRemote({ id = "Mad-Decent-1791000000-1", v = 99, authorKey = "Someone-Else", t = 1, zone = 1413, instance = 1, wx = 0, wy = 0 }) == nil
	and Store:Get("Mad-Decent-1791000000-1") == mine, "a stone never replaces one by a different author")
check(Store:Merge({ id = "Mad-Decent-1791000000-1", v = 99, authorKey = "Someone-Else", t = 1, zone = 1413, instance = 1, wx = 0, wy = 0 }, "Someone-Else") == nil,
	"not from another player either")
local shown = Stones.TextOf({ id = "x", text = "|TInterface\\Icons\\INV:500|t" })
check(shown == "||TInterface\\Icons\\INV:500||t", "any text is shown as plain text, whatever got stored")
check(ns.Identity.Display("Zug|cff00ff00-Zug") == "Zug||cff00ff00 Zug", "names too")

done()
