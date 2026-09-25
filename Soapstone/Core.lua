local ADDON_NAME, ns = ...

-- Icon textures with transparent backgrounds, made from art/soapstone.png by
-- tools/convert_icon.py. The pin version is smaller because it's drawn tiny.
ns.ICON = "Interface\\AddOns\\Soapstone\\Media\\Soapstone"
ns.PIN_ICON = "Interface\\AddOns\\Soapstone\\Media\\SoapstonePin"

ns.DEFAULTS = {
	stones = {},
	gateYards = 40, -- the app's 1-mile gate, scaled down to Azeroth
	nearYards = 150, -- "somewhere close" sound cue for unread stones
	sound = true,
	dropMode = "text", -- last tab used in the drop window: "text" or "sketch"
	net = true, -- join the hidden Soapstone network channel at login
	minimap = { angle = 210, hide = false },
}

local function applyDefaults(db, defaults)
	for k, v in pairs(defaults) do
		if db[k] == nil then
			db[k] = type(v) == "table" and CopyTable(v) or v
		elseif type(v) == "table" and type(db[k]) == "table" then
			applyDefaults(db[k], v)
		end
	end
end

-- The `## Version:` from Soapstone.toc (newer clients moved the lookup).
function ns.Version()
	local lookup = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
	return lookup and lookup(ADDON_NAME, "Version") or "unknown"
end

function ns.Print(msg)
	print("|cff9fd3c7Soapstone|r: " .. msg)
end

-- 272 -> "4:32"
function ns.FormatCountdown(seconds)
	seconds = math.max(0, math.floor(seconds))
	return format("%d:%02d", math.floor(seconds / 60), seconds % 60)
end

-- Windows -------------------------------------------------------------------

-- A standard Blizzard window: title bar, close button, inset, draggable by its
-- background, closes on Escape. Starts hidden.
function ns.CreateWindow(name, title)
	local f = CreateFrame("Frame", name, UIParent, "BasicFrameTemplateWithInset")
	f:Hide()
	f:SetFrameStrata("DIALOG")
	f:SetToplevel(true)
	f:SetClampedToScreen(true)
	f:SetMovable(true)
	f:EnableMouse(true)
	f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", f.StartMoving)
	f:SetScript("OnDragStop", f.StopMovingOrSizing)
	tinsert(UISpecialFrames, name)

	local text = f.TitleText
	if not text then
		text = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
		if f.TitleBg then
			text:SetPoint("CENTER", f.TitleBg, "CENTER", 0, 0)
		else
			text:SetPoint("TOP", 0, -5)
		end
	end
	text:SetText(title)
	f.title = text
	return f
end

function ns.ShowDropDialog()
	if not ns.Stones:GetPlayerLocation() then
		ns.Print("The ground here won't take a stone (no map position — are you in an instance?).")
		return
	end
	ns.DropWindow:Open()
end

-- Slash commands ------------------------------------------------------------

local HELP = {
	"/soap — leave a stone (write or draw) where you stand",
	"/soap drop <message> — drop a written stone without the window",
	"/soap read — open the nearest stone you're close enough to read",
	"/soap list — nearby stones, nearest first",
	"/soap test [yards] — plant a stranger's stone or sketch north of you (default 200)",
	"/soap radius <yards> — how close you must be to read (now %d)",
	"/soap near <yards> — range of the \"somewhere close\" cue (now %d)",
	"/soap sound [on||off||test] — toggle or preview the sound cues", -- "||" shows as "|"
	"/soap button — show/hide the minimap button",
	"/soap version — show the installed version",
	"/soap net — network test tools (selftest, pacetest, status, ping, burst, log)",
	"/soap stats — how many stones are stored, by zone",
	"/soap clear — delete every stone",
}

local function mapName(mapID)
	local info = mapID and C_Map.GetMapInfo(mapID)
	return info and info.name or ("map " .. tostring(mapID))
end

local function printStats()
	local here = ns.Stones:GetPlayerLocation()
	local zone = here and ns.Store.ZoneKey(here.mapID)
	local s = ns.Store:Stats(zone)
	ns.Print(format("%d stones: %d yours, %d from others, %d test stones.", s.live, s.mine, s.others, s.localOnly))
	ns.Print(format("%d deleted (kept as tombstones), %d of your changes waiting to announce, %d messages queued.",
		s.tombstones, s.outbox, ns.Net:QueueLength()))
	if zone then
		ns.Print(format("Here: %s (zone %d), %d stones. Zones visited: %d.", mapName(zone), zone, s.inZone, s.zones))
	end
	local zones = {}
	for id, count in pairs(s.perZone) do zones[#zones + 1] = { id = id, count = count } end
	table.sort(zones, function(a, b) return a.count > b.count end)
	for i = 1, math.min(#zones, 5) do
		ns.Print(format("  %s (zone %d): %d", mapName(zones[i].id), zones[i].id, zones[i].count))
	end
end

SLASH_SOAPSTONE1 = "/soapstone"
SLASH_SOAPSTONE2 = "/soap"
SlashCmdList.SOAPSTONE = function(input)
	local cmd, rest = (input or ""):match("^(%S*)%s*(.-)$")
	cmd = cmd:lower()

	if cmd == "" then
		ns.ShowDropDialog()
	elseif cmd == "drop" then
		if rest ~= "" then ns.Stones:Drop({ text = rest }) else ns.ShowDropDialog() end
	elseif cmd == "read" then
		ns.Stones:ReadNearest()
	elseif cmd == "list" then
		ns.Stones:PrintNearby()
	elseif cmd == "test" then
		ns.Stones:DropTestStone(tonumber(rest) or 200)
	elseif cmd == "radius" then
		local yards = tonumber(rest)
		if yards and yards > 0 then
			ns.db.gateYards = yards
			ns.Print(format("Stones now open within %d yards.", yards))
		else
			ns.Print(format("Stones open within %d yards.", ns.db.gateYards))
		end
	elseif cmd == "near" then
		local yards = tonumber(rest)
		if yards and yards > 0 then
			ns.db.nearYards = yards
		end
		ns.Print(format("You'll sense unread stones within %d yards.", ns.db.nearYards))
	elseif cmd == "sound" then
		rest = rest:lower()
		if rest == "test" then
			ns.Print("Playing: somewhere close… then: readable.")
			ns.Cues:Play("near", true)
			C_Timer.After(1.5, function() ns.Cues:Play("read", true) end)
			return
		elseif rest == "on" or rest == "off" then
			ns.db.sound = rest == "on"
		else
			ns.db.sound = not ns.db.sound
		end
		ns.Print("Sound cues " .. (ns.db.sound and "on." or "off."))
	elseif cmd == "net" then
		ns.Net:Command(rest)
	elseif cmd == "version" then
		ns.Print("version " .. ns.Version())
	elseif cmd == "button" then
		ns.db.minimap.hide = not ns.db.minimap.hide
		ns.MinimapButton:UpdateVisibility()
	elseif cmd == "stats" then
		printStats()
	elseif cmd == "clear" then
		ns.Store:Clear()
		ns.MinimapPins:Update()
		ns.Print("Every stone has crumbled.")
	else
		for _, line in ipairs(HELP) do
			ns.Print(format(line, ns.db.gateYards, ns.db.nearYards))
		end
	end
end

-- Boot ----------------------------------------------------------------------

local boot = CreateFrame("Frame")
boot:RegisterEvent("ADDON_LOADED")
boot:RegisterEvent("PLAYER_LOGIN")
boot:SetScript("OnEvent", function(self, event, arg1)
	if event == "ADDON_LOADED" and arg1 == ADDON_NAME then
		SoapstoneDB = SoapstoneDB or {}
		applyDefaults(SoapstoneDB, ns.DEFAULTS)
		ns.db = SoapstoneDB
		self:UnregisterEvent("ADDON_LOADED")
	elseif event == "PLAYER_LOGIN" then
		local upgraded = ns.Store:Init()
		if upgraded > 0 then
			ns.Print(format("Upgraded %d stones to the new storage format.", upgraded))
		end
		ns.MinimapButton:Init()
		ns.MinimapPins:Init()
		ns.Stones:AdoptOwnStones()
		ns.Stones:StartProximity()
		ns.Net:Init()
	end
end)
