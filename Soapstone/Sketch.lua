local _, ns = ...

-- A sketch is a 1-bit grid: every cell is ink or blank. Cells live in a flat
-- table indexed y * w + x + 1 (x and y start at 0); ink is `true`, blank is nil.
--
-- Saved form: { v = 1, w = 160, h = 60, data = "<runs>" }, where data is the
-- run lengths of alternating blank/ink cells (starting with blank), each
-- written as a base-32 varint in a base64 alphabet. Safe for SavedVariables
-- and, later, addon messages.

local Sketch = {}
ns.Sketch = Sketch

Sketch.WIDTH = 160
Sketch.HEIGHT = 60
Sketch.SIZES = { 1, 3, 5 } -- brush diameters in cells, for both pen and eraser

local FORMAT_VERSION = 1

function Sketch.New(w, h)
	return { w = w or Sketch.WIDTH, h = h or Sketch.HEIGHT, cells = {} }
end

function Sketch.IsEmpty(grid)
	return next(grid.cells) == nil
end

-- Brushes -------------------------------------------------------------------

local brushes = {}

-- Offsets covered by a round brush of odd diameter `size`.
local function brush(size)
	local pts = brushes[size]
	if not pts then
		pts = {}
		local r = (size - 1) / 2
		local limit = r * r + r
		for dy = -r, r do
			for dx = -r, r do
				if dx * dx + dy * dy <= limit then
					pts[#pts + 1] = { dx, dy }
				end
			end
		end
		brushes[size] = pts
	end
	return pts
end

-- Paints one brush dab centred on (cx, cy). `changes` (optional) records each
-- touched cell's previous value (false for blank) the first time it changes;
-- `dirtyRows` (optional) collects the rows that need redrawing.
function Sketch.Stamp(grid, cx, cy, size, ink, changes, dirtyRows)
	local w, h, cells = grid.w, grid.h, grid.cells
	local value = ink or nil
	for _, p in ipairs(brush(size)) do
		local x, y = cx + p[1], cy + p[2]
		if x >= 0 and x < w and y >= 0 and y < h then
			local i = y * w + x + 1
			local old = cells[i]
			if old ~= value then
				if changes and changes[i] == nil then changes[i] = old or false end
				cells[i] = value
				if dirtyRows then dirtyRows[y] = true end
			end
		end
	end
end

-- Stamps along a straight line so fast strokes don't leave gaps (Bresenham).
function Sketch.Line(grid, x0, y0, x1, y1, size, ink, changes, dirtyRows)
	local dx, dy = math.abs(x1 - x0), -math.abs(y1 - y0)
	local sx = x0 < x1 and 1 or -1
	local sy = y0 < y1 and 1 or -1
	local err = dx + dy
	while true do
		Sketch.Stamp(grid, x0, y0, size, ink, changes, dirtyRows)
		if x0 == x1 and y0 == y1 then return end
		local e2 = 2 * err
		if e2 >= dy then err = err + dy; x0 = x0 + sx end
		if e2 <= dx then err = err + dx; y0 = y0 + sy end
	end
end

-- Restores the cells recorded in `changes`, returning the rows it touched.
function Sketch.Revert(grid, changes, dirtyRows)
	local w, cells = grid.w, grid.cells
	for i, old in pairs(changes) do
		cells[i] = old or nil
		if dirtyRows then dirtyRows[math.floor((i - 1) / w)] = true end
	end
end

-- Blanks the whole grid, recording what was there so it can be undone.
function Sketch.Clear(grid, changes)
	for i in pairs(grid.cells) do
		if changes then changes[i] = true end
	end
	wipe(grid.cells)
end

-- Encoding ------------------------------------------------------------------

local ALPHABET = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local DIGIT = {}
for i = 1, #ALPHABET do DIGIT[ALPHABET:byte(i)] = i - 1 end

local function putVarint(out, v)
	repeat
		local digit = v % 32
		v = math.floor(v / 32)
		if v > 0 then digit = digit + 32 end
		out[#out + 1] = ALPHABET:sub(digit + 1, digit + 1)
	until v == 0
end

local function readVarint(data, pos)
	local value, scale = 0, 1
	while pos <= #data do
		local digit = DIGIT[data:byte(pos)]
		if not digit then return nil end
		pos = pos + 1
		value = value + (digit % 32) * scale
		if digit < 32 then return value, pos end
		scale = scale * 32
	end
	return nil
end

function Sketch.Pack(grid)
	local out, cells = {}, grid.cells
	local ink, run = false, 0
	for i = 1, grid.w * grid.h do
		if (cells[i] == true) == ink then
			run = run + 1
		else
			putVarint(out, run)
			ink, run = not ink, 1
		end
	end
	putVarint(out, run)
	return { v = FORMAT_VERSION, w = grid.w, h = grid.h, data = table.concat(out) }
end

-- Returns a grid, or nil if `packed` isn't a sketch this version understands.
function Sketch.Unpack(packed)
	if type(packed) ~= "table" or packed.v ~= FORMAT_VERSION or type(packed.data) ~= "string" then
		return nil
	end
	local grid = Sketch.New(packed.w, packed.h)
	local cells, total = grid.cells, grid.w * grid.h
	local pos, i, ink = 1, 1, false
	while pos <= #packed.data and i <= total do
		local run
		run, pos = readVarint(packed.data, pos)
		if not run then return nil end
		if ink then
			for k = i, math.min(i + run - 1, total) do cells[k] = true end
		end
		i, ink = i + run, not ink
	end
	return grid
end

-- Test art ------------------------------------------------------------------

-- "Praise the sun!": a sun with rays, for the stranger's test stones.
function Sketch.Sun()
	local grid = Sketch.New()
	local cx, cy, r = grid.w / 2, grid.h / 2, 13
	local steps = 48
	local px, py
	for s = 0, steps do
		local a = s / steps * 2 * math.pi
		local x = math.floor(cx + math.cos(a) * r + 0.5)
		local y = math.floor(cy + math.sin(a) * r + 0.5)
		if px then Sketch.Line(grid, px, py, x, y, 3, true) end
		px, py = x, y
	end
	for ray = 0, 11 do
		local a = ray / 12 * 2 * math.pi
		local c, s = math.cos(a), math.sin(a)
		Sketch.Line(grid,
			math.floor(cx + c * (r + 5) + 0.5), math.floor(cy + s * (r + 5) + 0.5),
			math.floor(cx + c * (r + 13) + 0.5), math.floor(cy + s * (r + 13) + 0.5),
			ray % 2 == 0 and 3 or 1, true)
	end
	Sketch.Stamp(grid, cx - 5, cy - 3, 3, true)
	Sketch.Stamp(grid, cx + 5, cy - 3, 3, true)
	Sketch.Line(grid, cx - 6, cy + 4, cx - 2, cy + 7, 1, true)
	Sketch.Line(grid, cx - 2, cy + 7, cx + 2, cy + 7, 1, true)
	Sketch.Line(grid, cx + 2, cy + 7, cx + 6, cy + 4, 1, true)
	return grid
end
