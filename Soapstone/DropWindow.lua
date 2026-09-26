local _, ns = ...

-- "Leave a Soapstone": the drop window. Two buttons at the top, Write and
-- Draw, pick between a short message (WritePanel) and a sketch (DrawPanel:
-- Splatoon-style tools beside the canvas). The chosen one stays lit, like
-- Appraise / Disparage in the stone window. It always opens on Write.
--
--  ┌ Leave a Soapstone ─────────────────────────────── x ┐
--  │                [  Write  ][  Draw  ]                 │
--  │ Pen  Eraser   ┌──────────────────────────────────┐   │
--  │ [·]  [▫]      │                                  │   │
--  │ [•]  [□]      │        160 × 60 canvas, 3×       │   │
--  │ [●]  [▢]      │                                  │   │
--  │ [ Undo  ]     └──────────────────────────────────┘   │
--  │ [ Clear ]      Left-drag to draw · Right-drag erases │
--  │                              [ Drop Stone ][Cancel]  │
--  └──────────────────────────────────────────────────────┘

local Sketch = ns.Sketch

local DropWindow = {}
ns.DropWindow = DropWindow

local FRAME_NAME = "SoapstoneDropFrame"
local PAD = 14
local TOP = 34             -- clears the title bar
local MODE_WIDTH = 110     -- Write / Draw buttons
local MODE_HEIGHT = 24     -- a touch taller than the 22px action buttons
local MODE_ROW = MODE_HEIGHT + 10
local CONTENT_TOP = TOP + MODE_ROW
local FOOTER = 62          -- hint line + action buttons
local MODES = { { key = "text", label = "Write" }, { key = "sketch", label = "Draw" } }

local function createActionButton(parent, text, width)
	local btn = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
	btn:SetSize(width, 22)
	btn:SetText(text)
	return btn
end

-- Building ------------------------------------------------------------------

function DropWindow:Build()
	local f = ns.CreateWindow(FRAME_NAME, "Leave a Soapstone")
	f:SetPoint("CENTER", 0, 80)
	self.frame = f

	-- Write | Draw, centred under the title bar, in standard button text.
	self.modeButtons = {}
	for i, mode in ipairs(MODES) do
		local btn = createActionButton(f, mode.label, MODE_WIDTH)
		btn:SetHeight(MODE_HEIGHT)
		if i == 1 then
			btn:SetPoint("TOPRIGHT", f, "TOP", -2, -TOP)
		else
			btn:SetPoint("LEFT", self.modeButtons[i - 1], "RIGHT", 4, 0)
		end
		btn:SetScript("OnClick", function()
			self:SetMode(mode.key)
			if SOUNDKIT and SOUNDKIT.IG_CHARACTER_INFO_TAB then PlaySound(SOUNDKIT.IG_CHARACTER_INFO_TAB) end
		end)
		btn.mode = mode.key
		self.modeButtons[i] = btn
	end

	local drawer = ns.DrawPanel.Create(f, function() self:UpdateButtons() end)
	drawer.frame:SetPoint("TOPLEFT", 0, -CONTENT_TOP)
	self.drawer = drawer

	local writer = ns.WritePanel.Create(f, function() self:Submit() end, function() self:UpdateButtons() end)
	writer.frame:SetPoint("TOPLEFT", PAD, -CONTENT_TOP)
	writer.frame:SetPoint("BOTTOMRIGHT", drawer.canvas.frame, "BOTTOMRIGHT", 6, -6)
	self.writer = writer

	local cancel = createActionButton(f, CANCEL, 90)
	cancel:SetPoint("BOTTOMRIGHT", -PAD, 12)
	cancel:SetScript("OnClick", function() f:Hide() end)
	local drop = createActionButton(f, "Drop Stone", 110)
	drop:SetPoint("RIGHT", cancel, "LEFT", -4, 0)
	drop:SetScript("OnClick", function() self:Submit() end)
	self.dropButton = drop
end

-- Behaviour -----------------------------------------------------------------

function DropWindow:Layout()
	local width, height = self.drawer:Layout()
	self.frame:SetSize(width + PAD, CONTENT_TOP + height + FOOTER)
end

function DropWindow:Open()
	if not self.frame then self:Build() end
	self:Layout()
	self.frame:Show()
	self:SetMode("text") -- always opens on Write
end

function DropWindow:SetMode(mode)
	if mode ~= "sketch" then mode = "text" end
	self.mode = mode
	local sketch = mode == "sketch"
	self.drawer.frame:SetShown(sketch)
	self.writer.frame:SetShown(not sketch)

	for _, btn in ipairs(self.modeButtons) do
		if btn.mode == mode then btn:LockHighlight() else btn:UnlockHighlight() end
	end

	if sketch then self.writer:ClearFocus() else self.writer:Focus() end
	self:UpdateButtons()
end

function DropWindow:HasContent()
	if self.mode == "sketch" then
		return not self.drawer:IsEmpty()
	end
	return self.writer:GetText() ~= ""
end

function DropWindow:UpdateButtons()
	if not self.dropButton then return end
	self.dropButton:SetEnabled(self:HasContent())
	self.drawer:Refresh()
end

-- Drops the current text or sketch. The draft is kept if the window is simply
-- closed, and cleared once a stone is actually dropped.
function DropWindow:Submit()
	if not self:HasContent() then return end
	local stone
	if self.mode == "sketch" then
		stone = ns.Stones:Drop({ sketch = Sketch.Pack(self.drawer:GetGrid()) })
		if stone then self.drawer:Reset() end
	else
		stone = ns.Stones:Drop({ text = self.writer:GetText() })
		if stone then self.writer:SetText("") end
	end
	if stone then self.frame:Hide() end
end
