local _, ns = ...

-- The drawing editor shared by "Leave a Soapstone" and "Edit Soapstone", laid
-- out like Splatoon's post editor: a tool strip (3 pens, 3 erasers, Undo,
-- Clear) beside a 160×60 canvas drawn at 3×, with a hint underneath.
--
--   Pen  Eraser   ┌──────────────────────────────────┐
--   [·]  [▫]      │                                  │
--   [•]  [□]      │        160 × 60 canvas, 3×       │
--   [●]  [▢]      │                                  │
--   [ Undo  ]     └──────────────────────────────────┘
--   [ Clear ]      Left-drag to draw · Right-drag erases
--
-- The caller anchors `panel.frame` by its TOPLEFT and calls Layout(), which
-- sizes the frame (the hint hangs just below it) and returns width, height.

local Sketch, SketchCanvas = ns.Sketch, ns.SketchCanvas

local DrawPanel = {}
ns.DrawPanel = DrawPanel

local DRAW_SCALE = 3
local PAD = 14
local TOOL_BUTTON = 30
local TOOL_GAP = 6
local TOOL_ROW = TOOL_BUTTON + 4
local TOOLS_WIDTH = TOOL_BUTTON * 2 + TOOL_GAP
local LABEL_HEIGHT = 14
local TOOLS_HEIGHT = LABEL_HEIGHT + 3 * TOOL_ROW + 8 + 22 + 4 + 22
local CANVAS_LEFT = PAD + TOOLS_WIDTH + PAD + 6
local SIZE_NAMES = { "Small", "Medium", "Large" }

local function showTooltip(owner, title, hint)
	GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
	GameTooltip:AddLine(title)
	if hint then GameTooltip:AddLine(hint, 0.8, 0.8, 0.8, true) end
	GameTooltip:Show()
end

local function createActionButton(parent, text, width)
	local btn = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
	btn:SetSize(width, 22)
	btn:SetText(text)
	return btn
end

local Panel = {}
Panel.__index = Panel

-- A square button showing a brush swatch: a solid dot for the pen, a hollow
-- one for the eraser, sized to match the brush.
function Panel:CreateToolButton(mode, size, index)
	local btn = CreateFrame("Button", nil, self.frame, "UIPanelButtonTemplate")
	btn:SetSize(TOOL_BUTTON, TOOL_BUTTON)
	btn.mode, btn.size = mode, size

	local swatch = btn:CreateTexture(nil, "OVERLAY")
	swatch:SetColorTexture(unpack(SketchCanvas.PAPER))
	swatch:SetSize(TOOL_BUTTON - 10, TOOL_BUTTON - 10)
	swatch:SetPoint("CENTER")

	local d = math.max(4, size * 3)
	local dot = btn:CreateTexture(nil, "OVERLAY", nil, 1)
	dot:SetColorTexture(unpack(SketchCanvas.INK))
	dot:SetSize(d + (mode == "eraser" and 2 or 0), d + (mode == "eraser" and 2 or 0))
	dot:SetPoint("CENTER")
	if mode == "eraser" then
		local hole = btn:CreateTexture(nil, "OVERLAY", nil, 2)
		hole:SetColorTexture(unpack(SketchCanvas.PAPER))
		hole:SetSize(d - 2, d - 2)
		hole:SetPoint("CENTER")
	end

	local label = (mode == "pen" and "Pen" or "Eraser") .. " — " .. SIZE_NAMES[index]
	btn:SetScript("OnEnter", function(b) showTooltip(b, label, "Right-drag on the canvas always erases.") end)
	btn:SetScript("OnLeave", GameTooltip_Hide)
	btn:SetScript("OnClick", function()
		self.canvas:SetTool(mode, size)
		self:Refresh()
	end)
	return btn
end

-- `onChange` runs after every stroke, undo and clear.
function DrawPanel.Create(parent, onChange)
	local self = setmetatable({ onChange = onChange }, Panel)
	local frame = CreateFrame("Frame", nil, parent)
	self.frame = frame

	local canvas = SketchCanvas.Create(frame, DRAW_SCALE)
	canvas.frame:SetPoint("TOPLEFT", CANVAS_LEFT, -6)
	canvas:EnableEditing(function()
		self:Refresh()
		if self.onChange then self.onChange() end
	end)
	self.canvas = canvas

	local penLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	penLabel:SetPoint("TOPLEFT", PAD, 0)
	penLabel:SetWidth(TOOL_BUTTON)
	penLabel:SetText("Pen")
	local eraserLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	eraserLabel:SetPoint("TOPLEFT", PAD + TOOL_BUTTON + TOOL_GAP - 8, 0)
	eraserLabel:SetWidth(TOOL_BUTTON + 16)
	eraserLabel:SetText("Eraser")

	self.toolButtons = {}
	for i, size in ipairs(Sketch.SIZES) do
		local y = -LABEL_HEIGHT - (i - 1) * TOOL_ROW
		local pen = self:CreateToolButton("pen", size, i)
		pen:SetPoint("TOPLEFT", PAD, y)
		local eraser = self:CreateToolButton("eraser", size, i)
		eraser:SetPoint("TOPLEFT", PAD + TOOL_BUTTON + TOOL_GAP, y)
		table.insert(self.toolButtons, pen)
		table.insert(self.toolButtons, eraser)
	end

	local undo = createActionButton(frame, "Undo", TOOLS_WIDTH)
	undo:SetPoint("TOPLEFT", PAD, -LABEL_HEIGHT - 3 * TOOL_ROW - 8)
	undo:SetScript("OnClick", function() canvas:Undo() end)
	local clear = createActionButton(frame, "Clear", TOOLS_WIDTH)
	clear:SetPoint("TOPLEFT", undo, "BOTTOMLEFT", 0, -4)
	clear:SetScript("OnClick", function() canvas:Clear() end)
	clear:SetScript("OnEnter", function(btn) showTooltip(btn, "Clear", "Wipes the canvas. Undo brings it back.") end)
	clear:SetScript("OnLeave", GameTooltip_Hide)
	self.undoButton, self.clearButton = undo, clear

	local hint = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	hint:SetPoint("TOPRIGHT", canvas.frame, "BOTTOMRIGHT", 0, -10)
	hint:SetText("Left-drag to draw  ·  Right-drag to erase")

	return self
end

-- Sizes the panel for the current UI scale; returns its width and height
-- (not counting the hint line hanging below).
function Panel:Layout()
	self.canvas:Layout()
	local cw, ch = self.canvas:GetSize()
	local width, height = CANVAS_LEFT + cw + 6, 6 + math.max(ch, TOOLS_HEIGHT)
	self.frame:SetSize(width, height)
	self:Refresh()
	return width, height
end

-- Undo/Clear availability and which tool is highlighted.
function Panel:Refresh()
	self.undoButton:SetEnabled(self.canvas:CanUndo())
	self.clearButton:SetEnabled(not Sketch.IsEmpty(self.canvas.grid))
	local tool = self.canvas.tool
	for _, btn in ipairs(self.toolButtons) do
		local selected = btn.mode == tool.mode
			and btn.size == (tool.mode == "pen" and tool.penSize or tool.eraserSize)
		if selected then btn:LockHighlight() else btn:UnlockHighlight() end
	end
end

function Panel:GetGrid()
	return self.canvas.grid
end

function Panel:IsEmpty()
	return Sketch.IsEmpty(self.canvas.grid)
end

-- Loads a grid to edit, with a fresh undo history.
function Panel:SetGrid(grid)
	self.canvas:SetGrid(grid)
	self:Refresh()
end

-- A blank canvas and no history.
function Panel:Reset()
	self.canvas:Reset()
end
