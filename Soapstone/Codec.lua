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

-- WoW reads "|" as the start of an escape code (|c colour, |H link, |T
-- texture...) wherever text is drawn; "||" is a plain pipe. Doubling every
-- odd run of pipes turns any escape code into plain text, and leaves text
-- that's already safe alone. Used on everything shown from other players.
function Codec.Neutralize(s)
	if type(s) ~= "string" then return s end
	return (s:gsub("|+", function(run)
		if #run % 2 == 1 then return run .. "|" end
	end))
end

-- Text with a live escape code in it (a "|" left over after removing "||",
-- followed by something). The server refuses these; so does the addon.
function Codec.HasEscapeCodes(s)
	return s:gsub("||", ""):find("|%S") ~= nil
end

-- Exactly "<authorKey>-<unix time>-<n>". A looser prefix check lets a short
-- name take a longer name's ids ("Mad" posting "Mad-Decent-1791000000-1").
function Codec.IdBelongsTo(id, authorKey)
	if type(id) ~= "string" or type(authorKey) ~= "string" or authorKey == "" then return false end
	if id:sub(1, #authorKey + 1) ~= authorKey .. "-" then return false end
	return id:sub(#authorKey + 2):match("^%d+%-%d+$") ~= nil
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
		kind, a = "T", s.text or (s.scrambled and Codec.Unscramble(s.id, s.scrambled))
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
	if s.authorKey:find("[%s~;|%%]") then return nil, "name" end
	if not Codec.IdBelongsTo(s.id, s.authorKey) then return nil, "id not the author's" end
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
		if Codec.HasEscapeCodes(text) then return nil, "text characters" end
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

-- Base64 ------------------------------------------------------------------------
-- The companion's data files (SoapstoneData) carry every record as base64,
-- whose alphabet can't close a Lua string, so a bad record can't become code.

local B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local B64_VALUE = {}
for i = 1, 64 do B64_VALUE[B64:byte(i)] = i - 1 end

function Codec.Base64Encode(s)
	local out = {}
	for i = 1, #s, 3 do
		local a, b, c = s:byte(i, i + 2)
		local n = a * 65536 + (b or 0) * 256 + (c or 0)
		local d1, d2 = math.floor(n / 262144), math.floor(n / 4096) % 64
		local d3, d4 = math.floor(n / 64) % 64, n % 64
		out[#out + 1] = B64:sub(d1 + 1, d1 + 1) .. B64:sub(d2 + 1, d2 + 1)
			.. (b and B64:sub(d3 + 1, d3 + 1) or "=") .. (c and B64:sub(d4 + 1, d4 + 1) or "=")
	end
	return table.concat(out)
end

-- nil for anything that isn't well-formed base64.
function Codec.Base64Decode(s)
	if type(s) ~= "string" or #s % 4 ~= 0 or s:find("[^A-Za-z0-9+/=]") or s:find("=[^=]") or s:find("===") then
		return nil
	end
	local out = {}
	for i = 1, #s, 4 do
		local c1, c2, c3, c4 = s:byte(i, i + 3)
		local v1, v2 = B64_VALUE[c1], B64_VALUE[c2]
		local v3, v4 = B64_VALUE[c3], B64_VALUE[c4] -- nil for "="
		if not v1 or not v2 or (not v3 and v4) then return nil end
		local n = v1 * 262144 + v2 * 4096 + (v3 or 0) * 64 + (v4 or 0)
		local chunk = string.char(math.floor(n / 65536))
		if v3 then chunk = chunk .. string.char(math.floor(n / 256) % 256) end
		if v4 then chunk = chunk .. string.char(n % 256) end
		out[#out + 1] = chunk
	end
	return table.concat(out)
end

-- Scrambling ------------------------------------------------------------------
-- A stone's words are in SoapstoneData before you reach it, so they're
-- lightly scrambled: XOR with a key stream seeded from the stone id, then
-- base64. It stops reading sealed stones in Notepad, not a determined
-- player. The companion (companion/src-tauri/src/soapdata.rs) does the same.

local function xorByte(a, b)
	if bit and bit.bxor then return bit.bxor(a, b) end
	local r, p = 0, 1
	for _ = 1, 8 do
		if a % 2 ~= b % 2 then r = r + p end
		a, b, p = math.floor(a / 2), math.floor(b / 2), p * 2
	end
	return r
end

local function xorStream(id, s)
	local seed = Codec.Hash(id)
	local out = {}
	for i = 1, #s do
		seed = (seed * 33 + 7 + i) % 16777216
		out[i] = string.char(xorByte(s:byte(i), math.floor(seed / 65536) % 256))
	end
	return table.concat(out)
end

function Codec.Scramble(id, text)
	return Codec.Base64Encode(xorStream(id, text))
end

function Codec.Unscramble(id, scrambled)
	local raw = Codec.Base64Decode(scrambled)
	return raw and xorStream(id, raw)
end

-- Stones from the database --------------------------------------------------------
-- The same 16 fields as EncodeStone, with two differences: a written stone's
-- text (kind "T") is scrambled, and a drawing comes as kind "K" with only
-- its sketch id ("sk_" + 16 hex), the drawing itself being in Sketches.lua.
-- Checked as strictly as a stone from another player, words included.
-- Returns a stone (text kept scrambled in `scrambled`), or nil and a reason.
function Codec.DecodeRemoteStone(str)
	if type(str) ~= "string" then return nil, "size" end
	local f = {}
	for field in (str .. "~"):gmatch("([^~]*)~") do f[#f + 1] = field end
	if #f ~= FIELDS then return nil, "fields" end
	local kind = f[13]
	if kind == "T" then
		local scrambled = Codec.Unescape(f[14])
		local text = Codec.Unscramble(f[1] and Codec.Unescape(f[1]) or "", scrambled)
		if not text then return nil, "scrambled text" end
		f[14] = Codec.Escape(text)
		local s, why = Codec.DecodeStone(table.concat(f, "~"))
		if not s then return nil, why end
		s.text, s.scrambled = nil, scrambled
		return s
	elseif kind == "K" then
		local sketchId = Codec.Unescape(f[16])
		if not sketchId:match("^sk_%x+$") or #sketchId ~= 19 then return nil, "sketch id" end
		-- Check everything else as a text stone with a stand-in word.
		f[13], f[14], f[15], f[16] = "T", "x", "", ""
		local s, why = Codec.DecodeStone(table.concat(f, "~"))
		if not s then return nil, why end
		s.text, s.sketchId = nil, sketchId
		return s
	elseif kind == "D" then
		return Codec.DecodeStone(str)
	end
	return nil, "kind"
end

-- A drawing from SoapstoneData\Sketches.lua: "sk_<16 hex>~w~h~data", checked
-- like a drawing from another player. Returns id and sketch, or nil and a reason.
function Codec.DecodeSketchRecord(str)
	if type(str) ~= "string" or #str > MAX_SKETCH_CHARS + 100 then return nil, "size" end
	local id, w, h, data = str:match("^(sk_%x+)~(%d+)~(%d+)~([A-Za-z0-9+/]+)$")
	if not id or #id ~= 19 then return nil, "sketch id" end
	local Sketch = ns.Sketch
	if tonumber(w) ~= Sketch.WIDTH or tonumber(h) ~= Sketch.HEIGHT then return nil, "sketch size" end
	if #data > MAX_SKETCH_CHARS then return nil, "sketch data" end
	local sketch = { v = 1, w = Sketch.WIDTH, h = Sketch.HEIGHT, data = data }
	if not Sketch.Unpack(sketch) then return nil, "sketch decode" end
	return id, sketch
end
