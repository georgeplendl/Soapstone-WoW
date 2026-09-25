local _, ns = ...

-- "Edit Soapstone": lets the author reword a written stone during the first
-- Stones.EDIT_SECONDS after dropping it. Same message box as the drop window,
-- but no Write | Draw tabs: a written stone can't become a sketch.
--
--  ┌ Edit Soapstone ──────────────────────────── x ┐
--  │ ┌──────────────────────────────────────────┐  │
--  │ │ message                          42 / 140│  │
--  │ └──────────────────────────────────────────┘  │
--  │ Editable for 4:32            [ Save ][Cancel] │
--  └───────────────────────────────────────────────┘

local EditWindow = {}
ns.EditWindow = EditWindow

local FRAME_NAME = "SoapstoneEditFrame"
local PAD = 14
local TOP = 34
local WIDTH = 520
local TEXT_HEIGHT = 130
local FOOTER = 46
local TICK = 0.25

function EditWindow:Build()
	local f = ns.CreateWindow(FRAME_NAME, "Edit Soapstone")
	f:SetPoint("CENTER", 0, 60)
	f:SetSize(WIDTH, TOP + TEXT_HEIGHT + FOOTER)
	self.frame = f

	local writer = ns.WritePanel.Create(f, function() self:Save() end, function() self:UpdateButtons() end)
	writer.frame:SetPoint("TOPLEFT", PAD, -TOP)
	writer.frame:SetPoint("TOPRIGHT", -PAD, -TOP)
	writer.frame:SetHeight(TEXT_HEIGHT)
	self.writer = writer

	local cancel = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
	cancel:SetSize(90, 22)
	cancel:SetPoint("BOTTOMRIGHT", -PAD, 12)
	cancel:SetText(CANCEL)
	cancel:SetScript("OnClick", function() f:Hide() end)

	local save = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
	save:SetSize(90, 22)
	save:SetPoint("RIGHT", cancel, "LEFT", -4, 0)
	save:SetText(SAVE or "Save")
	save:SetScript("OnClick", function() self:Save() end)
	self.saveButton = save

	local countdown = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	countdown:SetPoint("BOTTOMLEFT", PAD + 2, 18)
	self.countdown = countdown

	local elapsed = 0
	f:SetScript("OnUpdate", function(_, dt)
		elapsed = elapsed + dt
		if elapsed < TICK then return end
		elapsed = 0
		self:Tick()
	end)
	f:SetScript("OnHide", function() self.stone = nil end)
end

function EditWindow:Open(stone)
	if ns.Stones:EditTimeLeft(stone) <= 0 then
		ns.Print("This stone has already set and can't be edited.")
		return
	end
	if not self.frame then self:Build() end
	self.stone = stone
	self.writer:SetText(stone.text)
	self.frame:Show()
	self.frame:Raise()
	self.writer:Focus()
	self:Tick()
end

function EditWindow:Tick()
	local stone = self.stone
	if not stone then return end
	local left = ns.Stones:EditTimeLeft(stone)
	if left > 0 then
		self.countdown:SetText(format("Editable for %s", ns.FormatCountdown(left)))
	else
		self.countdown:SetText("|cffff6060The stone has set and can't be edited.|r")
	end
	self:UpdateButtons()
end

-- Save is live only while there's time left and the text actually changed.
function EditWindow:UpdateButtons()
	if not self.saveButton then return end
	local stone = self.stone
	local text = self.writer:GetText()
	local ok = stone ~= nil and ns.Stones:EditTimeLeft(stone) > 0 and text ~= "" and text ~= stone.text
	self.saveButton:SetEnabled(ok)
end

function EditWindow:Save()
	local stone = self.stone
	if stone and ns.Stones:Edit(stone, self.writer:GetText()) then
		self.frame:Hide()
	end
end
