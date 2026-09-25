local _, ns = ...

-- "Edit Soapstone": lets the author reword or delete a written stone during
-- the first Stones.EDIT_SECONDS after dropping it. Same message box as the
-- drop window, but no Write | Draw tabs: a written stone can't become a sketch.
--
--  ┌ Edit Soapstone ──────────────────────────────── x ┐
--  │ ┌──────────────────────────────────────────────┐  │
--  │ │ message                              42 / 140│  │
--  │ └──────────────────────────────────────────────┘  │
--  │ [Delete] Editable for 4:32       [ Save ][Cancel] │
--  └───────────────────────────────────────────────────┘

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

	local delete = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
	delete:SetSize(80, 22)
	delete:SetPoint("BOTTOMLEFT", PAD, 12)
	delete:SetText(DELETE or "Delete")
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

-- Delete is live while there's time left; Save also needs the text changed.
function EditWindow:UpdateButtons()
	if not self.saveButton then return end
	local stone = self.stone
	local text = self.writer:GetText()
	local open = stone ~= nil and ns.Stones:EditTimeLeft(stone) > 0
	self.saveButton:SetEnabled(open and text ~= "" and text ~= stone.text)
	self.deleteButton:SetEnabled(open)
	if not open then StaticPopup_Hide("SOAPSTONE_DELETE") end
end

function EditWindow:Hide()
	if self.frame then self.frame:Hide() end
end

function EditWindow:Save()
	local stone = self.stone
	if stone and ns.Stones:Edit(stone, self.writer:GetText()) then
		self.frame:Hide()
	end
end
