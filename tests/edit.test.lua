-- Edit/delete rules in Stones.lua on top of Store.lua (schema 2), plus
-- ns.FormatCountdown. Characters: Mad Decent (author) and Osha Compliant.
dofile(TESTS .. "/lib/harness.lua")
local NOW = 1000000
function time() return NOW end
function strtrim(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
format = string.format
unpack = unpack or table.unpack
function SecondsToTime(s) return s .. " sec" end
function wipe(t) for k in pairs(t) do t[k] = nil end return t end
function GetBuildInfo() return "1.60.1", "70009", "", 16001 end
WOW_PROJECT_ID = 1
local who = { "Mad", "Decent" }
function UnitFullName() return who[1], who[2] end
function UnitName() return who[1], who[2] end
function GetNormalizedRealmName() return who[2] end
C_Map = { GetMapInfo = function() return { mapType = 3 } end }

-- Core.lua needs a few frame stubs at load time.
local stubFrame = setmetatable({}, { __index = function() return function() end end })
function CreateFrame() return stubFrame end
SlashCmdList = {}

local ns, printed = {}, {}
assert(loadfile(ROOT .. "/Core.lua"))("Soapstone", ns)
assert(loadfile(ROOT .. "/Identity.lua"))("Soapstone", ns)
assert(loadfile(ROOT .. "/Store.lua"))("Soapstone", ns)
assert(loadfile(ROOT .. "/Sketch.lua"))("Soapstone", ns)
assert(loadfile(ROOT .. "/Stones.lua"))("Soapstone", ns)
ns.Print = function(msg) printed[#printed + 1] = msg end
ns.db = { stones = {}, schema = 2, zones = {}, outbox = {} }
local shown, hidden, pinUpdates = 0, 0, 0
ns.ReadWindow = {
	Current = function() return ns._open end,
	Show = function() shown = shown + 1 end,
	Hide = function() hidden = hidden + 1 end,
}
ns.MinimapPins = { Update = function() pinUpdates = pinUpdates + 1 end }
local Stones, Store = ns.Stones, ns.Store

local function put(fields)
	fields.instance, fields.wx, fields.wy, fields.mapID = 1, 0, 0, 1413
	fields.t = fields.t or NOW
	return Store:Put(fields)
end

check(ns.FormatCountdown(300) == "5:00", "countdown 300s -> 5:00")
check(ns.FormatCountdown(272) == "4:32", "countdown 272s -> 4:32")
check(ns.FormatCountdown(9) == "0:09", "countdown 9s -> 0:09")
check(ns.FormatCountdown(-5) == "0:00", "countdown never negative")

local mine = put({ id = "Mad-Decent-1-1", authorKey = "Mad-Decent", author = "Mad Decent", mine = true, text = "Try jumping" })
check(Stones:EditTimeLeft(mine) == 300, "fresh own stone has 300s")
NOW = NOW + 299
check(Stones:EditTimeLeft(mine) == 1, "1s left at 4:59 elapsed")
NOW = NOW + 1
check(Stones:EditTimeLeft(mine) == 0, "0 at exactly 5:00")
NOW = NOW - 300

check(Stones:EditTimeLeft(put({ id = "Zug-Zug-1-1", authorKey = "Zug-Zug", text = "x" })) == 0, "strangers' stones can't be edited")
check(Stones:EditTimeLeft(put({ id = "Mad-Decent-1-2", authorKey = "Mad-Decent", sketch = {} })) == 300, "your sketches are editable too")
check(Stones:EditTimeLeft(nil) == 0, "no stone -> 0")

-- Account-wide "mine" no longer counts: Osha can't touch Mad's fresh stone.
who = { "Osha", "Compliant" }
check(Stones:EditTimeLeft(mine) == 0, "another character on the account can't edit it")
check(Stones:Byline(mine):find("Mad Decent") ~= nil, "and sees Mad's name, not 'You'")
who = { "Mad", "Decent" }
check(Stones:Byline(mine):find("You") ~= nil, "the author sees 'You'")

ns._open = mine
check(Stones:Edit(mine, "  Try rolling  ") == true, "edit within window succeeds")
check(mine.text == "Try rolling", "text updated and trimmed")
check(mine.edited == NOW, "edited timestamp set")
check(mine.v == 2, "version bumped to 2")
check(ns.db.outbox["Mad-Decent-1-1"], "edit queued in the outbox")
check(shown == 1, "open read window refreshed")
check(Stones:Byline(mine):find("%(edited%)") ~= nil, "byline says (edited)")
check(Stones:Edit(mine, "   ") == false and mine.text == "Try rolling", "blank edit rejected")

-- Delete
local keep = put({ id = "Mad-Decent-1-3", authorKey = "Mad-Decent", text = "keep me" })
local doomed = put({ id = "Mad-Decent-1-4", authorKey = "Mad-Decent", text = "delete me" })
local stranger = Store:Get("Zug-Zug-1-1")
ns._open = doomed
check(Stones:Delete(stranger) == false and Store:Get("Zug-Zug-1-1") == stranger, "can't delete a stranger's stone")
check(Stones:Delete(doomed) == true, "delete within window succeeds")
local tomb = Store:Get("Mad-Decent-1-4")
check(tomb.deleted and tomb.v == 2 and tomb.text == nil, "leaves a v2 tombstone")
check(Store:Get("Mad-Decent-1-3") == keep, "other stones untouched")
check(hidden == 1 and pinUpdates >= 1, "read window closes, pins refresh")
check(Stones:Delete(doomed) == false, "deleting it twice does nothing")
check(Stones:EditTimeLeft(tomb) == 0, "a tombstone can't be edited")

NOW = NOW + 301
check(Stones:Edit(keep, "Too late") == false and keep.text == "keep me", "edit after 5 min rejected")
check(printed[#printed]:find("Too late") ~= nil, "player told it's too late")
check(Stones:Delete(keep) == false and Store:Get("Mad-Decent-1-3") == keep, "delete after 5 min rejected")

-- The edit clock ---------------------------------------------------------------
-- Pauses while the editor is open, resumes on cancel, restarts on a save.

local clock = put({ id = "Mad-Decent-2-1", authorKey = "Mad-Decent", text = "clock" })
NOW = NOW + 60
check(Stones:EditTimeLeft(clock) == 240, "4:00 left after a minute")
Stones:PauseEditClock(clock)
check(Stones:IsEditClockPaused(clock), "opening the editor pauses the clock")
NOW = NOW + 1000
check(Stones:EditTimeLeft(clock) == 240, "a long edit costs nothing (still 4:00)")
Stones:ResumeEditClock(clock)
check(not Stones:IsEditClockPaused(clock) and Stones:EditTimeLeft(clock) == 240, "cancel resumes at 4:00")
NOW = NOW + 30
check(Stones:EditTimeLeft(clock) == 210, "and it counts down again")

Stones:PauseEditClock(clock)
NOW = NOW + 600 -- far past where the window would have ended
check(Stones:Edit(clock, { text = "clock, reworded" }) == true, "saving still works after a long pause")
check(Stones:EditTimeLeft(clock) == 300 and clock.windowStart == NOW, "a saved edit restarts the full 5:00")
check(not Stones:IsEditClockPaused(clock), "and unpauses")
NOW = NOW + 100
check(Stones:Edit(clock, "clock, reworded") == true and Stones:EditTimeLeft(clock) == 200,
	"saving without a change doesn't restart the clock")

-- Sketches ---------------------------------------------------------------------

local Sketch = ns.Sketch
local sun = Sketch.Pack(Sketch.Sun())
local drawing = put({ id = "Mad-Decent-3-1", authorKey = "Mad-Decent", sketch = sun })
local grid = Sketch.Sun()
Sketch.Stamp(grid, 5, 5, 5, true)
local changed = Sketch.Pack(grid)
Stones:PauseEditClock(drawing)
NOW = NOW + 400
check(Stones:Edit(drawing, { sketch = changed }) == true, "a sketch can be redrawn")
check(drawing.sketch.data == changed.data and drawing.v == 2, "new drawing saved, version bumped")
check(Stones:EditTimeLeft(drawing) == 300, "and its clock restarted")
check(Stones:Edit(drawing, { sketch = Sketch.Pack(Sketch.New()) }) == false, "an empty drawing is refused")
check(Stones:Edit(drawing, { text = "words" }) == false and drawing.text == nil, "a sketch can't become text")
check(Stones:Edit(clock, { sketch = changed }) == false and clock.sketch == nil, "and text can't become a sketch")
check(Stones:Delete(drawing) == true and Store:Get(drawing.id).deleted, "a sketch can be deleted in its window")

done()
