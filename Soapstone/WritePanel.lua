local _, ns = ...

-- The message box shared by the "Leave a Soapstone" and "Edit Soapstone"
-- windows: a bordered multi-line box capped at MAX_LETTERS, with a placeholder
-- and a character counter. Enter submits; newlines are folded into spaces.
-- The caller positions and sizes `panel.frame`.

local WritePanel = {}
ns.WritePanel = WritePanel

WritePanel.MAX_LETTERS = 140

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
	edit:SetPoint("TOPLEFT", 12, -12)
	edit:SetPoint("TOPRIGHT", -12, -12)
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

	self.frame, self.edit = frame, edit
	return self
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
