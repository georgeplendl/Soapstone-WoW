local _, ns = ...

-- Turning stones into text for the wire, and back. Used by Sync.lua.
--
-- A stone record is 16 fields joined by "~":
--   id ~ v ~ authorKey ~ t ~ zone ~ instance ~ wx ~ wy ~ mapID ~ x ~ y ~ edited
--   ~ kind ~ a ~ b ~ c
-- kind "T" (text): a = text · "S" (sketch): a = w, b = h, c = data
-- kind "D" (deleted / tombstone): a = deletedAt
-- Characters that would break framing (% ~ ; | and control characters) are
-- escaped as %XX, so a payload never contains ";" (the wire separator).
--
-- Everything decoded from another player is validated; anything odd is
-- rejected rather than repaired.

local Codec = {}
ns.Codec = Codec

local FIELDS = 16
local MAX_LETTERS = 140    -- same limit as the message box (WritePanel.MAX_LETTERS)
local MAX_TEXT_BYTES = 600 -- 140 characters of up to 4 bytes each, with slack
local MAX_SKETCH_CHARS = 8000

-- Strings ---------------------------------------------------------------------

function Codec.Escape(value)
	return (tostring(value):gsub("[%%~;|%c]", function(c) return format("%%%02X", c:byte()) end))
end

function Codec.Unescape(s)
	return (s:gsub("%%(%x%x)", function(hex) return string.char(tonumber(hex, 16)) end))
end

-- djb2, kept to 24 bits so it's exact in Lua numbers.
function Codec.Hash(s)
	local h = 5381
	for i = 1, #s do h = (h * 33 + s:byte(i)) % 16777216 end
	return h
end

function Codec.Hex6(n)
	return format("%06x", n % 16777216)
end

-- Stones ----------------------------------------------------------------------

local function fixed(n, places)
	return n and format("%." .. places .. "f", n) or nil
end

function Codec.EncodeStone(s)
	local kind, a, b, c
	if s.deleted then
		kind, a = "D", s.deletedAt
	elseif s.sketch then
		kind, a, b, c = "S", s.sketch.w, s.sketch.h, s.sketch.data
	else
		kind, a = "T", s.text
	end
	local out = { s.id, s.v or 1, s.authorKey, s.t, s.zone, s.instance, fixed(s.wx, 1), fixed(s.wy, 1),
		s.mapID, fixed(s.x, 4), fixed(s.y, 4), s.edited, kind, a, b, c }
	for i = 1, FIELDS do
		out[i] = out[i] == nil and "" or Codec.Escape(out[i])
	end
	return table.concat(out, "~")
end

local function int(s)
	local n = tonumber(s)
	if n and n == math.floor(n) then return n end
end

-- Returns a stone table, or nil and a reason.
function Codec.DecodeStone(str)
	if type(str) ~= "string" or #str > MAX_SKETCH_CHARS + 400 then return nil, "size" end
	local f = {}
	for field in (str .. "~"):gmatch("([^~]*)~") do f[#f + 1] = Codec.Unescape(field) end
	if #f ~= FIELDS then return nil, "fields" end

	local s = {
		id = f[1], v = int(f[2]), authorKey = f[3], t = int(f[4]), zone = int(f[5]),
		instance = int(f[6]), wx = tonumber(f[7]), wy = tonumber(f[8]), mapID = int(f[9]),
		x = tonumber(f[10]), y = tonumber(f[11]), edited = int(f[12]),
	}
	if s.id == "" or #s.id > 100 or s.authorKey == "" or #s.authorKey > 60 then return nil, "id" end
	if s.id:sub(1, #s.authorKey + 1) ~= s.authorKey .. "-" then return nil, "id not the author's" end
	if not s.v or s.v < 1 or s.v > 1000000 or not s.zone then return nil, "numbers" end

	local kind = f[13]
	if kind == "D" then
		s.deleted = true
		s.deletedAt = int(f[14]) or s.t
		return s
	end
	if not s.t then return nil, "drop time" end -- live stones need one; tombstones may not have it
	if not (s.instance and s.wx and s.wy) then return nil, "position" end
	if kind == "T" then
		local text = f[14]
		local length = strlenutf8 and strlenutf8(text) or #text
		if text == "" or #text > MAX_TEXT_BYTES or length > MAX_LETTERS then return nil, "text" end
		s.text = text
	elseif kind == "S" then
		local w, h, data = int(f[14]), int(f[15]), f[16]
		local Sketch = ns.Sketch
		if w ~= Sketch.WIDTH or h ~= Sketch.HEIGHT then return nil, "sketch size" end
		if #data == 0 or #data > MAX_SKETCH_CHARS or not data:match("^[A-Za-z0-9+/]+$") then return nil, "sketch data" end
		s.sketch = { v = 1, w = w, h = h, data = data }
		if not Sketch.Unpack(s.sketch) then return nil, "sketch decode" end
	else
		return nil, "kind"
	end
	return s
end
