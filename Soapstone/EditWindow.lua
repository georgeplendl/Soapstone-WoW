local _, ns = ...

-- "Edit Soapstone": lets the author rework or delete one of their stones
-- inside its edit window (Stones.EDIT_SECONDS; see Stones.lua for how the
-- clock pauses while this is open and restarts after a saved edit).
-- Written stones get the message box (WritePanel), sketches the drawing
-- editor (DrawPanel), loaded with the current drawing. No Write / Draw choice:
-- a stone can't switch between text and drawing.
--
--  ┌ Edit Soapstone ──────────────────────────────── x ┐
--  │ ┌──────────────────────────────────────────────┐  │
--  │ │ message (or the drawing editor)      42 / 140│  │
--  │ └──────────────────────────────────────────────┘  │
--  │ [Delete] Editable for 4:32 · paused   [Save][Cancel]
--  └───────────────────────────────────────────────────┘

local Sketch = ns.Sketch

local EditWindow = {}
ns.EditWindow = EditWindow

StaticPopupDialogs["SOAPSTONE_DELETE"] = {
	text = "Delete this soapstone?\nThis can't be undone.",
	button1 = DELETE or "Delete",
	button2 = CANCEL,
	OnAccept = function(_, stone)
		if stone and ns.Stones:Delete(stone) then EditWindow:Hide() end
	end,
	showAlert = true,
	timeout = 0,
	whileDead = true,
	hideOnEscape = true,
	preferredIndex = 3,
}

local FRAME_NAME = "SoapstoneEditFrame"
local PAD = 14
local TOP = 34
-- The message box is exactly as wide as the stone window's text, so it wraps
-- the same way (see WritePanel:UseStoneStyle).
local TEXT_WIDTH = ns.WritePanel.StoneWidth() + 2 * PAD
local TEXT_HEIGHT = ns.WritePanel.STONE_HEIGHT
local FOOTER = 46        -- action buttons
local SKETCH_FOOTER = 62 -- hint line + action buttons
local TICK = 0.25

local function button(parent, text, width)
	local btn = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
	btn:SetSize(width, 22)
	btn:SetText(text)
	return btn
end

function EditWindow:Build()
	local f = ns.CreateWindow(FRAME_NAME, "Edit Soapstone")
	f:SetPoint("CENTER", 0, 60)
	self.frame = f

	local writer = ns.WritePanel.Create(f, function() self:Save() end, function() self:UpdateButtons() end)
	writer.frame:SetPoint("TOPLEFT", PAD, -TOP)
	writer.frame:SetPoint("TOPRIGHT", -PAD, -TOP)
	writer.frame:SetHeight(TEXT_HEIGHT)
	writer:UseStoneStyle() -- same font, size, centring and width as the stone window
	self.writer = writer

	local drawer = ns.DrawPanel.Create(f, function() self:OnDrawingChanged() end)
	drawer.frame:SetPoint("TOPLEFT", 0, -TOP)
	self.drawer = drawer

	local cancel = button(f, CANCEL, 90)
	cancel:SetPoint("BOTTOMRIGHT", -PAD, 12)
	cancel:SetScript("OnClick", function() f:Hide() end)

	local save = button(f, SAVE or "Save", 90)
	save:SetPoint("RIGHT", cancel, "LEFT", -4, 0)
	save:SetScript("OnClick", function() self:Save() end)
	self.saveButton = save

	local delete = button(f, DELETE or "Delete", 80)
	delete:SetPoint("BOTTOMLEFT", PAD, 12)
	delete:SetScript("OnClick", function()
		if self.stone then StaticPopup_Show("SOAPSTONE_DELETE", nil, nil, self.stone) end
	end)
	self.deleteButton = delete

	local countdown = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	countdown:SetPoint("LEFT", delete, "RIGHT", 10, 0)
	self.countdown = countdown

	local elapsed = 0
	f:SetScript("OnUpdate", function(_, dt)
		elapsed = elapsed + dt
		if elapsed < TICK then return end
		elapsed = 0
		self:Tick()
	end)
	f:SetScript("OnHide", function()
		-- Closed without saving (or deleting): the clock carries on.
		if self.stone then ns.Stones:ResumeEditClock(self.stone) end
		self.stone = nil
		StaticPopup_Hide("SOAPSTONE_DELETE")
	end)
end

function EditWindow:Open(stone)
	if ns.Stones:EditTimeLeft(stone) <= 0 then
		ns.Print("This stone has already set and can't be edited.")
		return
	end
	if not self.frame then self:Build() end
	if self.frame:IsShown() then self.frame:Hide() end -- resume the previous stone's clock
	self.stone = stone
	self.sketch = stone.sketch ~= nil
	self.drawingChanged = false

	self.writer.frame:SetShown(not self.sketch)
	self.drawer.frame:SetShown(self.sketch)
	if self.sketch then
		self.drawer:SetGrid(Sketch.Unpack(stone.sketch) or Sketch.New())
		local width, height = self.drawer:Layout()
		self.frame:SetSize(width + PAD, TOP + height + SKETCH_FOOTER)
	else
		self.writer:SetText(stone.text)
		self.frame:SetSize(TEXT_WIDTH, TOP + TEXT_HEIGHT + FOOTER)
	end

	ns.Stones:PauseEditClock(stone)
	self.frame:Show()
	self.frame:Raise()
	if not self.sketch then self.writer:Focus() end
	self:Tick()
end

function EditWindow:OnDrawingChanged()
	local stone = self.stone
	if not stone or not self.sketch then return end
	self.drawingChanged = not self.drawer:IsEmpty()
		and Sketch.Pack(self.drawer:GetGrid()).data ~= stone.sketch.data
	self:UpdateButtons()
end

function EditWindow:Tick()
	local stone = self.stone
	if not stone then return end
	local left = ns.Stones:EditTimeLeft(stone)
	if left > 0 then
		local paused = ns.Stones:IsEditClockPaused(stone) and "  ·  paused while you edit" or ""
		self.countdown:SetText(format("Editable for %s%s", ns.FormatCountdown(left), paused))
	else
		self.countdown:SetText("|cffff6060The stone has set and can't be edited.|r")
	end
	self:UpdateButtons()
end

-- Delete is live while there's time left; Save also needs a real change.
function EditWindow:UpdateButtons()
	if not self.saveButton then return end
	local stone = self.stone
	local open = stone ~= nil and ns.Stones:EditTimeLeft(stone) > 0
	local changed
	if self.sketch then
		changed = self.drawingChanged
	else
		local text = self.writer:GetText()
		changed = stone ~= nil and text ~= "" and text ~= stone.text
	end
	self.saveButton:SetEnabled(open and changed)
	self.deleteButton:SetEnabled(open)
	if not open then StaticPopup_Hide("SOAPSTONE_DELETE") end
end

function EditWindow:Hide()
	if self.frame then self.frame:Hide() end
end

function EditWindow:Save()
	local stone = self.stone
	if not stone then return end
	local content = self.sketch and { sketch = Sketch.Pack(self.drawer:GetGrid()) }
		or { text = self.writer:GetText() }
	if ns.Stones:Edit(stone, content) then
		self.frame:Hide() -- Edit already restarted the clock; resuming is a no-op
	end
end
