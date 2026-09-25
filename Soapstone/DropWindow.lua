local _, ns = ...

-- "Leave a Soapstone": the drop window. Two Blizzard-style tabs along the
-- bottom switch between Write (a short message) and Draw (a sketch). The Draw
-- layout follows Splatoon's post editor: tools down the left, the canvas
-- beside them, actions along the bottom.
--
--  ┌ Leave a Soapstone ─────────────────────────────── x ┐
--  │ Pen  Eraser   ┌──────────────────────────────────┐   │
--  │ [·]  [▫]      │                                  │   │
--  │ [•]  [□]      │        160 × 60 canvas, 3×       │   │
--  │ [●]  [▢]      │                                  │   │
--  │ [ Undo  ]     └──────────────────────────────────┘   │
--  │ [ Clear ]      Left-drag to draw · Right-drag erases │
--  │                              [ Drop Stone ][Cancel]  │
--  └──────────────────────────────────────────────────────┘
--    (Write)(Draw)

local Sketch, SketchCanvas = ns.Sketch, ns.SketchCanvas

local DropWindow = {}
ns.DropWindow = DropWindow

local FRAME_NAME = "SoapstoneDropFrame"
local DRAW_SCALE = 3
local MAX_LETTERS = 140

local PAD = 14
local TOP = 34 -- clears the title bar
local TOOL_BUTTON = 30
local TOOL_GAP = 6
local TOOL_ROW = TOOL_BUTTON + 4
local TOOLS_WIDTH = TOOL_BUTTON * 2 + TOOL_GAP
local LABEL_HEIGHT = 14
local TOOLS_HEIGHT = LABEL_HEIGHT + 3 * TOOL_ROW + 8 + 22 + 4 + 22
local CANVAS_LEFT = PAD + TOOLS_WIDTH + PAD + 6
local FOOTER = 62 -- hint line + action buttons

local TAB_TEMPLATES = { "CharacterFrameTabButtonTemplate", "CharacterFrameTabTemplate", "PanelTabButtonTemplate" }
local SIZE_NAMES = { "Small", "Medium", "Large" }

local PANEL_BACKDROP = {
	bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
	edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
	tile = true,
	tileSize = 16,
	edgeSize = 14,
	insets = { left = 4, right = 4, top = 4, bottom = 4 },
}

local function templateExists(name)
	if C_XMLUtil and C_XMLUtil.GetTemplateInfo then
		return C_XMLUtil.GetTemplateInfo(name) ~= nil
	end
	return true -- can't check on this client; CreateFrame is wrapped in pcall
end

-- A bottom tab in whichever style this client ships. Falls back to a plain
-- panel button if none of the known tab templates exist.
local function createTab(parent, id)
	local name = parent:GetName() .. "Tab" .. id
	for _, template in ipairs(TAB_TEMPLATES) do
		if templateExists(template) then
			local ok, tab = pcall(CreateFrame, "Button", name, parent, template)
			if ok and tab then
				tab:SetID(id)
				return tab, true
			end
		end
	end
	local tab = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
	tab:SetSize(80, 24)
	tab:SetID(id)
	return tab, false
end

local function showTooltip(owner, title, hint)
	GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
	GameTooltip:AddLine(title)
	if hint then GameTooltip:AddLine(hint, 0.8, 0.8, 0.8, true) end
	GameTooltip:Show()
end

-- A square button showing a brush swatch: a solid dot for the pen, a hollow
-- one for the eraser, sized to match the brush.
local function createToolButton(parent, mode, size, index)
	local btn = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
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
	btn:SetScript("OnEnter", function(self)
		showTooltip(self, label, "Right-drag on the canvas always erases.")
	end)
	btn:SetScript("OnLeave", GameTooltip_Hide)
	btn:SetScript("OnClick", function()
		DropWindow.canvas:SetTool(mode, size)
		DropWindow:UpdateButtons()
	end)
	return btn
end

local function createActionButton(parent, text, width)
	local btn = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
	btn:SetSize(width, 22)
	btn:SetText(text)
	return btn
end

-- Building ------------------------------------------------------------------

function DropWindow:BuildDrawPanel(f)
	local panel = CreateFrame("Frame", nil, f)
	panel:SetAllPoints()

	local canvas = SketchCanvas.Create(panel, DRAW_SCALE)
	canvas.frame:SetPoint("TOPLEFT", CANVAS_LEFT, -TOP - 6)
	canvas:EnableEditing(function() self:UpdateButtons() end)
	self.canvas = canvas

	local penLabel = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	penLabel:SetPoint("TOPLEFT", PAD, -TOP)
	penLabel:SetWidth(TOOL_BUTTON)
	penLabel:SetText("Pen")
	local eraserLabel = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	eraserLabel:SetPoint("TOPLEFT", PAD + TOOL_BUTTON + TOOL_GAP - 8, -TOP)
	eraserLabel:SetWidth(TOOL_BUTTON + 16)
	eraserLabel:SetText("Eraser")

	self.toolButtons = {}
	for i, size in ipairs(Sketch.SIZES) do
		local y = -TOP - LABEL_HEIGHT - (i - 1) * TOOL_ROW
		local pen = createToolButton(panel, "pen", size, i)
		pen:SetPoint("TOPLEFT", PAD, y)
		local eraser = createToolButton(panel, "eraser", size, i)
		eraser:SetPoint("TOPLEFT", PAD + TOOL_BUTTON + TOOL_GAP, y)
		table.insert(self.toolButtons, pen)
		table.insert(self.toolButtons, eraser)
	end

	local undo = createActionButton(panel, "Undo", TOOLS_WIDTH)
	undo:SetPoint("TOPLEFT", PAD, -TOP - LABEL_HEIGHT - 3 * TOOL_ROW - 8)
	undo:SetScript("OnClick", function() canvas:Undo() end)
	local clear = createActionButton(panel, "Clear", TOOLS_WIDTH)
	clear:SetPoint("TOPLEFT", undo, "BOTTOMLEFT", 0, -4)
	clear:SetScript("OnClick", function() canvas:Clear() end)
	clear:SetScript("OnEnter", function(btn) showTooltip(btn, "Clear", "Wipes the canvas. Undo brings it back.") end)
	clear:SetScript("OnLeave", GameTooltip_Hide)
	self.undoButton, self.clearButton = undo, clear

	local hint = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	hint:SetPoint("TOPRIGHT", canvas.frame, "BOTTOMRIGHT", 0, -10)
	hint:SetText("Left-drag to draw  ·  Right-drag to erase")

	return panel
end

function DropWindow:BuildWritePanel(f)
	local panel = CreateFrame("Frame", nil, f, "BackdropTemplate")
	panel:SetBackdrop(PANEL_BACKDROP)
	panel:SetBackdropColor(0, 0, 0, 0.6)
	panel:SetBackdropBorderColor(0.7, 0.7, 0.7)
	panel:SetPoint("TOPLEFT", PAD, -TOP)
	panel:SetPoint("BOTTOMRIGHT", self.canvas.frame, "BOTTOMRIGHT", 6, -6)
	panel:EnableMouse(true)

	local edit = CreateFrame("EditBox", nil, panel)
	edit:SetMultiLine(true)
	edit:SetAutoFocus(false)
	edit:SetMaxLetters(MAX_LETTERS)
	edit:SetFontObject(ChatFontNormal)
	edit:SetPoint("TOPLEFT", 12, -12)
	edit:SetPoint("TOPRIGHT", -12, -12)
	edit:SetHeight(80)
	panel:SetScript("OnMouseDown", function() edit:SetFocus() end)

	local placeholder = panel:CreateFontString(nil, "OVERLAY", "GameFontDisable")
	placeholder:SetPoint("TOPLEFT", edit, "TOPLEFT", 0, 0)
	placeholder:SetText("What should the next traveller read here?")

	local counter = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	counter:SetPoint("BOTTOMRIGHT", -12, 10)

	edit:SetScript("OnEscapePressed", edit.ClearFocus)
	edit:SetScript("OnEnterPressed", function() self:Submit() end)
	edit:SetScript("OnTextChanged", function(box)
		local text = box:GetText()
		if text:find("\n") then
			box:SetText((text:gsub("\n", " ")))
			return
		end
		placeholder:SetShown(text == "")
		counter:SetText(format("%d / %d", strlenutf8(text), MAX_LETTERS))
		self:UpdateButtons()
	end)
	counter:SetText(format("0 / %d", MAX_LETTERS))

	self.edit = edit
	return panel
end

function DropWindow:Build()
	local f = ns.CreateWindow(FRAME_NAME, "Leave a Soapstone")
	f:SetPoint("CENTER", 0, 80)
	self.frame = f

	self.drawPanel = self:BuildDrawPanel(f)
	self.writePanel = self:BuildWritePanel(f)

	local cancel = createActionButton(f, CANCEL, 90)
	cancel:SetPoint("BOTTOMRIGHT", -PAD, 12)
	cancel:SetScript("OnClick", function() f:Hide() end)
	local drop = createActionButton(f, "Drop Stone", 110)
	drop:SetPoint("RIGHT", cancel, "LEFT", -4, 0)
	drop:SetScript("OnClick", function() self:Submit() end)
	self.dropButton = drop

	self.tabs = {}
	for i, label in ipairs({ "Write", "Draw" }) do
		local tab, blizzard = createTab(f, i)
		tab:SetText(label)
		if blizzard and PanelTemplates_TabResize then PanelTemplates_TabResize(tab, 0) end
		tab:SetScript("OnClick", function()
			self:SetMode(i == 1 and "text" or "sketch")
			if SOUNDKIT and SOUNDKIT.IG_CHARACTER_INFO_TAB then PlaySound(SOUNDKIT.IG_CHARACTER_INFO_TAB) end
		end)
		self.tabs[i] = tab
		self.blizzardTabs = blizzard
	end
	self.tabs[1]:SetPoint("TOPLEFT", f, "BOTTOMLEFT", 12, 2)
	self.tabs[2]:SetPoint("LEFT", self.tabs[1], "RIGHT", self.blizzardTabs and -14 or 4, 0)
	if self.blizzardTabs then
		f.Tabs = self.tabs
		PanelTemplates_SetNumTabs(f, #self.tabs)
	end
end

-- Behaviour -----------------------------------------------------------------

function DropWindow:Layout()
	self.canvas:Layout()
	local cw, ch = self.canvas:GetSize()
	self.frame:SetSize(CANVAS_LEFT + cw + PAD + 6, TOP + 6 + math.max(ch, TOOLS_HEIGHT) + FOOTER)
end

function DropWindow:Open()
	if not self.frame then self:Build() end
	self:Layout()
	self.frame:Show()
	self:SetMode(ns.db.dropMode)
end

function DropWindow:SetMode(mode)
	if mode ~= "sketch" then mode = "text" end
	ns.db.dropMode = mode
	local sketch = mode == "sketch"
	self.drawPanel:SetShown(sketch)
	self.writePanel:SetShown(not sketch)

	if self.blizzardTabs then
		PanelTemplates_SetTab(self.frame, sketch and 2 or 1)
	else
		for i, tab in ipairs(self.tabs) do
			if (i == 2) == sketch then tab:LockHighlight() else tab:UnlockHighlight() end
		end
	end

	if sketch then self.edit:ClearFocus() else self.edit:SetFocus() end
	self:UpdateButtons()
end

function DropWindow:HasContent()
	if ns.db.dropMode == "sketch" then
		return not Sketch.IsEmpty(self.canvas.grid)
	end
	return strtrim(self.edit:GetText()) ~= ""
end

function DropWindow:UpdateButtons()
	if not self.frame then return end
	self.dropButton:SetEnabled(self:HasContent())
	self.undoButton:SetEnabled(self.canvas:CanUndo())
	self.clearButton:SetEnabled(not Sketch.IsEmpty(self.canvas.grid))

	local tool = self.canvas.tool
	for _, btn in ipairs(self.toolButtons) do
		local selected = btn.mode == tool.mode
			and btn.size == (tool.mode == "pen" and tool.penSize or tool.eraserSize)
		if selected then btn:LockHighlight() else btn:UnlockHighlight() end
	end
end

-- Drops the current text or sketch. The draft is kept if the window is simply
-- closed, and cleared once a stone is actually dropped.
function DropWindow:Submit()
	if not self:HasContent() then return end
	local stone
	if ns.db.dropMode == "sketch" then
		stone = ns.Stones:Drop({ sketch = Sketch.Pack(self.canvas.grid) })
		if stone then self.canvas:Reset() end
	else
		stone = ns.Stones:Drop({ text = self.edit:GetText() })
		if stone then self.edit:SetText("") end
	end
	if stone then self.frame:Hide() end
end
