-- UI smoke test: builds and drives the real DropWindow / EditWindow /
-- DrawPanel / WritePanel code against a permissive fake of WoW's frame API,
-- to catch wiring mistakes (nil calls, missing fields) that the syntax check
-- can't. It doesn't check pixels.
dofile(TESTS .. "/lib/harness.lua")
local NOW = 1790400000
function time() return NOW end
format = string.format
unpack = unpack or table.unpack
function wipe(t) for k in pairs(t) do t[k] = nil end return t end
function strtrim(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
function strlenutf8(s) return utf8.len(s) or #s end
function SecondsToTime(s) return s .. " sec" end
function GetBuildInfo() return "1.60.1", "70009", "", 16001 end
WOW_PROJECT_ID = 1
function UnitFullName() return "Mad", "Decent" end
function UnitName() return "Mad", "Decent" end
function GetUnitName() return "Mad Decent" end
function GetNormalizedRealmName() return "Decent" end
function GetPhysicalScreenSize() return 1920, 1080 end
function GetCursorPosition() return 0, 0 end
function IsMouseButtonDown() return false end
function PlaySound() end
C_Map = { GetMapInfo = function() return { mapType = 3, name = "The Barrens" } end }
C_Timer = { After = function() end, NewTicker = function() return { Cancel = function() end } end }
CANCEL, SAVE, DELETE = "Cancel", "Save", "Delete"
UISpecialFrames = {}
SlashCmdList = {}
tinsert = table.insert
ChatFontNormal = {}
UIErrorsFrame = { AddMessage = function() end }
GameTooltip = setmetatable({}, { __index = function() return function() end end })
GameTooltip_Hide = function() end

-- A permissive frame: remembers text/shown/size/scripts, answers the getters
-- our code does maths with, and accepts any other method call.
local frames = {}
local Frame = {}
function Frame.new(kind)
	local f = setmetatable({ kind = kind, shown = true, text = "", w = 100, h = 100, scripts = {} }, Frame)
	frames[#frames + 1] = f
	return f
end
Frame.__index = function(f, key)
	local known = {
		Show = function(self) self.shown = true end,
		Hide = function(self)
			local wasShown = self.shown
			self.shown = false
			if wasShown and self.scripts.OnHide then self.scripts.OnHide(self) end
		end,
		SetShown = function(self, on) if on then self:Show() else self:Hide() end end,
		IsShown = function(self) return self.shown end,
		IsVisible = function(self) return self.shown end,
		SetText = function(self, text) self.text = text or "" end,
		GetText = function(self) return self.text end,
		SetSize = function(self, w, h) self.w, self.h = w, h end,
		GetSize = function(self) return self.w, self.h end,
		GetWidth = function(self) return self.w end,
		GetHeight = function(self) return self.h end,
		GetEffectiveScale = function() return 0.64 end,
		GetLeft = function() return 0 end,
		GetTop = function() return 0 end,
		GetStringHeight = function() return 14 end,
		GetName = function(self) return self.name end,
		SetScript = function(self, name, fn) self.scripts[name] = fn end,
		GetScript = function(self, name) return self.scripts[name] end,
		SetEnabled = function(self, on) self.enabled = on end,
		IsEnabled = function(self) return self.enabled end,
		CreateTexture = function() return Frame.new("Texture") end,
		CreateFontString = function() return Frame.new("FontString") end,
		CreateAnimationGroup = function() return Frame.new("AnimationGroup") end,
		CreateAnimation = function() return Frame.new("Animation") end,
		LockHighlight = function(self) self.locked = true end,
		UnlockHighlight = function(self) self.locked = false end,
	}
	-- Template fields our code checks for and falls back from (e.g. a window's
	-- TitleText) read as missing; any other unknown key is a method.
	local absentFields = { TitleText = true, TitleBg = true, Tabs = true, editBox = true, EditBox = true }
	if absentFields[key] then return nil end
	return known[key] or function(self) return self end
end
function CreateFrame(kind, name, parent)
	local f = Frame.new(kind)
	f.name = name
	f.shown = kind ~= "Frame" or name == nil -- named windows start hidden like ours do
	return f
end
local function click(button) button.scripts.OnClick(button, "LeftButton") end

local popups = {}
StaticPopupDialogs = {}
function StaticPopup_Show(which, _, _, data) popups[#popups + 1] = { which = which, data = data } end
function StaticPopup_Hide() end
PanelTemplates_TabResize, PanelTemplates_SetNumTabs, PanelTemplates_SetTab = function() end, function() end, function() end

local ns = {}
for _, file in ipairs({ "Core.lua", "Identity.lua", "Store.lua", "Sketch.lua", "Codec.lua", "Stones.lua",
	"SketchCanvas.lua", "WritePanel.lua", "DrawPanel.lua", "DropWindow.lua", "ReadWindow.lua", "EditWindow.lua" }) do
	assert(loadfile(ROOT .. "/" .. file))("Soapstone", ns)
end
local printed = {}
ns.Print = function(msg) printed[#printed + 1] = msg end
ns.db = { stones = {}, zones = {}, outbox = {}, ratings = {}, schema = 2, dropMode = "text", gateYards = 40, nearYards = 150 }
ns.MinimapPins = { Update = function() end }
ns.Cues = { Play = function() end }
ns.Store:Init()
function ns.Stones:GetPlayerLocation()
	return { mapID = 1413, x = 0.5, y = 0.5, instance = 1, wx = 0, wy = 0 }
end
local Stones, Store, Sketch = ns.Stones, ns.Store, ns.Sketch

-- Drop window: both tabs, drop a text stone and a sketch.
local drop = ns.DropWindow
local ok, err = pcall(function() drop:Open() end)
check(ok, "drop window opens (" .. tostring(err) .. ")")
check(drop.frame.w > 400 and drop.frame.h > 200, ("drop window sized %.0fx%.0f from the draw panel"):format(drop.frame.w, drop.frame.h))
drop.writer.edit:SetText("Try jumping")
drop.writer.edit.scripts.OnTextChanged(drop.writer.edit)
check(drop.dropButton.enabled == true, "Drop Stone lights up once there's text")
click(drop.dropButton)
local text
for _, s in Store:Each() do if s.text == "Try jumping" then text = s end end
check(text ~= nil and not drop.frame.shown, "a written stone is dropped and the window closes")

drop:Open()
drop:SetMode("sketch")
check(drop.drawer.frame.shown and not drop.writer.frame.shown, "the Draw tab shows the drawing editor")
check(drop.dropButton.enabled == false, "Drop Stone is off for an empty canvas")
drop.drawer:SetGrid(Sketch.Sun())
drop:UpdateButtons()
check(drop.dropButton.enabled == true and drop.drawer.clearButton.enabled == true, "a drawing enables Drop and Clear")
click(drop.drawer.toolButtons[2]) -- small eraser
check(drop.drawer.canvas.tool.mode == "eraser" and drop.drawer.toolButtons[2].locked, "tool buttons select and highlight")
click(drop.dropButton)
local drawing
for _, s in Store:Each() do if s.sketch then drawing = s end end
check(drawing ~= nil and drop.drawer:IsEmpty(), "a sketch is dropped and the canvas cleared for next time")

-- Edit window on the written stone: pause, cancel, resume.
local edit = ns.EditWindow
NOW = NOW + 60
ok, err = pcall(function() edit:Open(text) end)
check(ok, "edit window opens on a written stone (" .. tostring(err) .. ")")
check(edit.writer.frame.shown and not edit.drawer.frame.shown, "with the message box, not the drawing editor")
check(Stones:IsEditClockPaused(text), "the clock pauses while it's open")
check(edit.countdown.text:find("4:00") and edit.countdown.text:find("paused"), "countdown: " .. edit.countdown.text)
check(edit.saveButton.enabled == false, "Save waits for a change")
NOW = NOW + 900
edit.frame:Hide() -- Cancel
check(not Stones:IsEditClockPaused(text) and Stones:EditTimeLeft(text) == 240, "cancel resumes at 4:00 despite 15 minutes open")

-- Save a reworded stone: clock restarts.
edit:Open(text)
edit.writer.edit:SetText("Try rolling")
edit.writer.edit.scripts.OnTextChanged(edit.writer.edit)
check(edit.saveButton.enabled == true, "Save lights up after a change")
click(edit.saveButton)
check(text.text == "Try rolling" and Stones:EditTimeLeft(text) == 300 and not edit.frame.shown, "saved; 5:00 again; closed")

-- Edit window on the sketch: drawing editor, save, then delete. (The sketch
-- was dropped 16 test-minutes ago, so its window has honestly expired; give
-- it a fresh one, as if it had just been posted.)
check(Stones:EditTimeLeft(drawing) == 0, "the sketch's own window did expire meanwhile")
drawing.windowStart = NOW
ok, err = pcall(function() edit:Open(drawing) end)
check(ok, "edit window opens on a sketch (" .. tostring(err) .. ")")
check(edit.drawer.frame.shown and not edit.writer.frame.shown, "with the drawing editor, loaded")
check(not edit.drawer:IsEmpty(), "holding the current drawing")
check(edit.saveButton.enabled == false, "Save waits for a change")
local g = edit.drawer:GetGrid()
Sketch.Stamp(g, 3, 3, 5, true)
edit.drawer.canvas:PushUndo({ [1] = false }) -- what a real stroke does: triggers onChange
check(edit.saveButton.enabled == true, "a stroke lights up Save")
local before = drawing.sketch.data
click(edit.saveButton)
check(drawing.sketch.data ~= before and drawing.v == 2 and Stones:EditTimeLeft(drawing) == 300, "sketch saved, version 2, 5:00 again")

edit:Open(drawing)
click(edit.deleteButton)
check(#popups == 1 and popups[1].which == "SOAPSTONE_DELETE" and popups[1].data == drawing, "Delete asks for confirmation")
StaticPopupDialogs.SOAPSTONE_DELETE.OnAccept(nil, drawing)
check(Store:Get(drawing.id).deleted and not edit.frame.shown, "confirming deletes the sketch and closes the editor")
check(not Stones:IsEditClockPaused(drawing), "no clock left paused")

done()
