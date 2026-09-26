-- Codec.lua: stone records on the wire, and validation of what arrives.
dofile(TESTS .. "/lib/harness.lua")
format = string.format
unpack = unpack or table.unpack
function wipe(t) for k in pairs(t) do t[k] = nil end return t end
function strlenutf8(s) return utf8.len(s) or #s end

local ns = {}
assert(loadfile(ROOT .. "/Sketch.lua"))("Soapstone", ns)
assert(loadfile(ROOT .. "/Codec.lua"))("Soapstone", ns)
local Codec, Sketch = ns.Codec, ns.Sketch

local function stone(fields)
	local s = { id = "Mad-Decent-1790363195-1", v = 1, authorKey = "Mad-Decent", t = 1790363195, zone = 1413,
		instance = 1, wx = -1444.39501953125, wy = -3751.90869140625, mapID = 1413,
		x = 0.6290946006774902, y = 0.4524543881416321 }
	for k, v in pairs(fields) do s[k] = v end
	return s
end

-- Round trips
local tricky = "Praise; the ~sun~ at 100% | fin\nnext line — ünïcödé"
local wire = Codec.EncodeStone(stone({ text = tricky, edited = 1790363200, v = 3 }))
check(not wire:find(";", 1, true) and not wire:find("|", 1, true) and not wire:find("\n", 1, true),
	"encoded record has no ; | or newline")
local back = Codec.DecodeStone(wire)
check(back and back.text == tricky, "text with ; ~ % | newline and UTF-8 survives")
check(back and back.v == 3 and back.edited == 1790363200 and back.zone == 1413, "version, edit time, zone survive")
check(back and math.abs(back.wx - -1444.4) < 0.06 and math.abs(back.x - 0.6291) < 0.0001, "positions rounded sensibly")

local sun = Sketch.Pack(Sketch.Sun())
back = Codec.DecodeStone(Codec.EncodeStone(stone({ sketch = sun })))
check(back and back.sketch and back.sketch.data == sun.data and back.sketch.w == 160, "sketch survives")
check(back and back.text == nil, "a sketch carries no text")
vprint(("     sun record: %d chars"):format(#Codec.EncodeStone(stone({ sketch = sun }))))

back = Codec.DecodeStone(Codec.EncodeStone({ id = "Mad-Decent-1-1", v = 2, authorKey = "Mad-Decent", t = 5,
	zone = 1413, deleted = true, deletedAt = 99 }))
check(back and back.deleted and back.deletedAt == 99 and back.v == 2, "tombstone survives, without a position")
back = Codec.DecodeStone(Codec.EncodeStone({ id = "Mad-Decent-1-1", v = 2, authorKey = "Mad-Decent",
	zone = 1413, deleted = true, deletedAt = 99 }))
check(back and back.deleted, "a tombstone without a drop time is still accepted")
check(Codec.DecodeStone(Codec.EncodeStone(stone({ text = "hi", t = false }))) == nil, "a live stone without a drop time isn't")

check(Codec.Hash("abc") == Codec.Hash("abc") and Codec.Hash("abc") ~= Codec.Hash("abd"), "hash is stable and sensitive")
check(Codec.Hash(("x"):rep(5000)) < 16777216, "hash stays within 24 bits")

-- Rejections
local function rejects(s, why)
	local ok = Codec.DecodeStone(s)
	check(ok == nil, "rejects " .. why)
end
local good = Codec.EncodeStone(stone({ text = "hi" }))
rejects((good:gsub("^Mad%-Decent", "Zug-Zug")), "an id that isn't the author's")
rejects(Codec.EncodeStone(stone({ text = ("x"):rep(141) })), "text over 140 characters")
check(Codec.DecodeStone(Codec.EncodeStone(stone({ text = ("é"):rep(140) }))) ~= nil, "accepts 140 accented characters")
rejects(Codec.EncodeStone(stone({ text = "" })), "empty text")
rejects(Codec.EncodeStone(stone({ sketch = { w = 320, h = 120, data = sun.data } })), "the wrong sketch size")
rejects(Codec.EncodeStone(stone({ sketch = { w = 160, h = 60, data = "not base64!" } })), "sketch data outside the alphabet")
rejects(Codec.EncodeStone(stone({ sketch = { w = 160, h = 60, data = ("A"):rep(9000) } })), "oversized sketch data")
rejects(good .. "~extra", "extra fields")
rejects((good:gsub("~T~", "~Q~")), "an unknown kind")
rejects((good:gsub("^([^~]*)~1~", "%1~0~")), "version 0")
rejects(Codec.EncodeStone(stone({ text = "hi", wx = false })), "a missing position")
rejects(("x"):rep(10000), "a huge blob")
rejects(nil, "nil")

done()
