local _, ns = ...

-- The message box shared by the "Leave a Soapstone" and "Edit Soapstone"
-- windows: a bordered multi-line box capped at MAX_LETTERS, with a placeholder
-- and a character counter. Enter submits; newlines are folded into spaces.
-- The caller positions and sizes `panel.frame`.

local WritePanel = {}
ns.WritePanel = WritePanel

WritePanel.MAX_LETTERS = 140
WritePanel.INSET = 12 -- the text sits this far inside the panel's border
WritePanel.STONE_HEIGHT = 130 -- the message box in both drop and edit windows

-- The width that makes a stone-style panel wrap like the stone window's text.
-- A function because ReadWindow loads after the drop window.
function WritePanel.StoneWidth()
	return ns.ReadWindow.TEXT_WIDTH + 2 * WritePanel.INSET
end

local BACKDROP = {
	bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
	edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
	tile = true,
	tileSize = 16,
	edgeSize = 14,
	insets = { left = 4, right = 4, top = 4, bottom = 4 },
}

local Panel = {}
Panel.__index = Panel

-- `onSubmit` runs when Enter is pressed; `onChange` after every text change.
function WritePanel.Create(parent, onSubmit, onChange)
	local self = setmetatable({}, Panel)
	local max = WritePanel.MAX_LETTERS

	local frame = CreateFrame("Frame", nil, parent, "BackdropTemplate")
	frame:SetBackdrop(BACKDROP)
	frame:SetBackdropColor(0, 0, 0, 0.6)
	frame:SetBackdropBorderColor(0.7, 0.7, 0.7)
	frame:EnableMouse(true)

	local edit = CreateFrame("EditBox", nil, frame)
	edit:SetMultiLine(true)
	edit:SetAutoFocus(false)
	edit:SetMaxLetters(max)
	edit:SetFontObject(ChatFontNormal)
	edit:SetPoint("TOPLEFT", WritePanel.INSET, -WritePanel.INSET)
	edit:SetPoint("TOPRIGHT", -WritePanel.INSET, -WritePanel.INSET)
	edit:SetHeight(80)
	frame:SetScript("OnMouseDown", function() edit:SetFocus() end)

	local placeholder = frame:CreateFontString(nil, "OVERLAY", "GameFontDisable")
	placeholder:SetPoint("TOPLEFT", edit, "TOPLEFT", 0, 0)
	placeholder:SetText("What should the next traveller read here?")

	local counter = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	counter:SetPoint("BOTTOMRIGHT", -12, 10)
	counter:SetText(format("0 / %d", max))

	edit:SetScript("OnEscapePressed", edit.ClearFocus)
	edit:SetScript("OnEnterPressed", function() if onSubmit then onSubmit() end end)
	edit:SetScript("OnTextChanged", function(box)
		local text = box:GetText()
		if text:find("\n") then
			box:SetText((text:gsub("\n", " ")))
			return
		end
		placeholder:SetShown(text == "")
		counter:SetText(format("%d / %d", strlenutf8(text), max))
		if onChange then onChange() end
	end)

	self.frame, self.edit, self.placeholder = frame, edit, placeholder
	return self
end

-- Types in the stone window's font and size, centred, so the text wraps and
-- reads just as it will when opened (the caller makes the panel
-- WritePanel.StoneWidth() wide and STONE_HEIGHT tall).
function Panel:UseStoneStyle()
	ns.ReadWindow.ApplyStoneFont(self.edit)
	self.edit:SetJustifyH("CENTER")
	ns.ReadWindow.ApplyStoneFont(self.placeholder)
	self.placeholder:SetTextColor(0.5, 0.5, 0.5)
	self.placeholder:ClearAllPoints()
	self.placeholder:SetPoint("TOPLEFT", self.edit, "TOPLEFT", 0, 0)
	self.placeholder:SetPoint("TOPRIGHT", self.edit, "TOPRIGHT", 0, 0)
	self.placeholder:SetJustifyH("CENTER")
end

-- The message with surrounding whitespace removed.
function Panel:GetText()
	return strtrim(self.edit:GetText())
end

function Panel:SetText(text)
	self.edit:SetText(text or "")
	self.edit:SetCursorPosition(#(text or ""))
end

function Panel:Focus()
	self.edit:SetFocus()
end

function Panel:ClearFocus()
	self.edit:ClearFocus()
end
