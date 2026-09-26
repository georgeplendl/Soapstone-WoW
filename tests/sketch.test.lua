-- Exercises Soapstone/Sketch.lua outside the game. Run via run_sketch_test.js.
dofile(TESTS .. "/lib/harness.lua")
function wipe(t) for k in pairs(t) do t[k] = nil end return t end

local ns = {}
local chunk = assert(loadfile(ROOT .. "/Sketch.lua"))
chunk("Soapstone", ns)
local Sketch = ns.Sketch

local function count(grid) local n = 0 for _ in pairs(grid.cells) do n = n + 1 end return n end
local function same(a, b)
	if a.w ~= b.w or a.h ~= b.h then return false end
	for i = 1, a.w * a.h do if (a.cells[i] == true) ~= (b.cells[i] == true) then return false end end
	return true
end

-- Brush shapes
for _, case in ipairs({ { 1, 1 }, { 3, 9 }, { 5, 21 } }) do
	local g = Sketch.New()
	Sketch.Stamp(g, 80, 30, case[1], true)
	check(count(g) == case[2], ("brush %d covers %d cells (got %d)"):format(case[1], case[2], count(g)))
end

-- Clipping at the edges
local g = Sketch.New()
Sketch.Stamp(g, 0, 0, 5, true)
check(count(g) > 0 and count(g) < 21, "brush clips at the top-left corner")

-- Lines have no gaps: a 1px diagonal from corner to corner touches every column
g = Sketch.New()
Sketch.Line(g, 0, 0, 159, 59, 1, true)
local cols = {}
for i in pairs(g.cells) do cols[(i - 1) % 160] = true end
local allCols = true
for x = 0, 159 do if not cols[x] then allCols = false end end
check(allCols, "diagonal line touches all 160 columns")

-- Empty grid round trip
local empty = Sketch.New()
local packed = Sketch.Pack(empty)
check(Sketch.IsEmpty(Sketch.Unpack(packed)), "empty grid round-trips (" .. #packed.data .. " chars)")

-- Sun round trip + size
local sun = Sketch.Sun()
packed = Sketch.Pack(sun)
check(same(sun, Sketch.Unpack(packed)), ("sun round-trips: %d ink cells, %d chars"):format(count(sun), #packed.data))
check(packed.data:match("^[A-Za-z0-9+/]+$") ~= nil, "packed data uses only the base64 alphabet")

-- Random noise round trip (worst case)
math.randomseed(42)
local noise = Sketch.New()
for i = 1, 160 * 60 do if math.random() < 0.5 then noise.cells[i] = true end end
packed = Sketch.Pack(noise)
check(same(noise, Sketch.Unpack(packed)), ("noise round-trips: %d chars"):format(#packed.data))

-- Full grid round trip
local full = Sketch.New()
for i = 1, 160 * 60 do full.cells[i] = true end
check(same(full, Sketch.Unpack(Sketch.Pack(full))), "full grid round-trips")

-- Undo: stroke changes revert exactly
local canvas = Sketch.Sun()
local before = Sketch.Unpack(Sketch.Pack(canvas))
local changes, dirty = {}, {}
Sketch.Line(canvas, 10, 10, 150, 50, 5, true, changes, dirty)
Sketch.Line(canvas, 20, 50, 140, 5, 3, false, changes, dirty)
check(not same(before, canvas), "strokes change the grid")
Sketch.Revert(canvas, changes)
check(same(before, canvas), "revert restores the grid exactly")
local rows = 0 for _ in pairs(dirty) do rows = rows + 1 end
check(rows > 0 and rows <= 60, "dirty rows recorded (" .. rows .. ")")

-- Clear is undoable
changes = {}
Sketch.Clear(canvas, changes)
check(Sketch.IsEmpty(canvas), "clear empties the grid")
Sketch.Revert(canvas, changes)
check(same(before, canvas), "reverting a clear restores it")

-- Bad input
check(Sketch.Unpack(nil) == nil, "unpack rejects nil")
check(Sketch.Unpack({ v = 99, w = 160, h = 60, data = "A" }) == nil, "unpack rejects unknown versions")
check(Sketch.Unpack({ v = 1, w = 160, h = 60, data = "!!" }) == nil, "unpack rejects bad characters")

-- ASCII preview of the sun (every other row/column), with -v
if VERBOSE then for y = 0, 59, 2 do
	local line = {}
	for x = 0, 159, 2 do line[#line + 1] = sun.cells[y * 160 + x + 1] and "#" or " " end
	print(table.concat(line))
end end

done()
