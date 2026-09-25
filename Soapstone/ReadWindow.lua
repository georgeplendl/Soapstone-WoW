local _, ns = ...

-- Shows one stone: its message, or its sketch at 2×. Opened by clicking a
-- readable minimap pin or with /soap read. Stones.lua closes it when the
-- player walks out of reading range. Your own written stones get an
-- "Edit (m:ss)" button that counts down the edit window, then disappears.

local Sketch, SketchCanvas = ns.Sketch, ns.SketchCanvas

local ReadWindow = {}
ns.ReadWindow = ReadWindow

local FRAME_NAME = "SoapstoneReadFrame"
local READ_SCALE = 2
local PAD = 16
local TOP = 36
local TEXT_WIDTH = 320
local TICK = 0.25

function ReadWindow:Build()
	local f = ns.CreateWindow(FRAME_NAME, "Soapstone")
	f:SetPoint("CENTER", 0, 120)
	f:SetScript("OnHide", function() self.stone = nil end)
	self.frame = f

	local text = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
	text:SetPoint("TOPLEFT", PAD, -TOP)
	text:SetWidth(TEXT_WIDTH)
	text:SetJustifyH("CENTER")
	text:SetSpacing(3)
	self.text = text

	local canvas = SketchCanvas.Create(f, READ_SCALE)
	canvas.frame:SetPoint("TOPLEFT", PAD + 4, -TOP - 4)
	self.canvas = canvas

	local byline = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	byline:SetPoint("BOTTOMRIGHT", -PAD, 14)
	self.byline = byline

	local edit = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
	edit:SetSize(96, 22)
	edit:SetPoint("BOTTOMLEFT", PAD - 4, 10)
	edit:SetScript("OnClick", function()
		if self.stone then ns.EditWindow:Open(self.stone) end
	end)
	edit:SetScript("OnEnter", function(btn)
		GameTooltip:SetOwner(btn, "ANCHOR_TOP")
		GameTooltip:AddLine("Edit Soapstone")
		GameTooltip:AddLine(format("You can reword or delete a written stone for %d minutes after dropping it.",
			ns.Stones.EDIT_SECONDS / 60), 0.8, 0.8, 0.8, true)
		GameTooltip:Show()
	end)
	edit:SetScript("OnLeave", GameTooltip_Hide)
	edit:Hide()
	self.editButton = edit

	local elapsed = 0
	f:SetScript("OnUpdate", function(_, dt)
		elapsed = elapsed + dt
		if elapsed < TICK then return end
		elapsed = 0
		self:UpdateEditButton()
	end)
end

-- Shows "Edit (4:32)" while the open stone can still be edited.
function ReadWindow:UpdateEditButton()
	local left = ns.Stones:EditTimeLeft(self.stone)
	if left > 0 then
		self.editButton:SetText(format("Edit (%s)", ns.FormatCountdown(left)))
		self.editButton:Show()
	else
		self.editButton:Hide()
	end
end

function ReadWindow:Show(stone)
	if not self.frame then self:Build() end
	local refreshing = self:Current() == stone
	self.stone = stone

	local grid = stone.sketch and Sketch.Unpack(stone.sketch)
	local width, height
	if grid then
		self.text:Hide()
		self.canvas:SetGrid(grid)
		self.canvas:Layout()
		self.canvas.frame:Show()
		local cw, ch = self.canvas:GetSize()
		width, height = cw + 8, ch + 8
	else
		self.canvas.frame:Hide()
		self.text:SetText(stone.text or (stone.sketch and "The carving is too worn to make out.") or "")
		self.text:Show()
		width, height = TEXT_WIDTH, math.max(self.text:GetStringHeight(), 24)
	end

	self.byline:SetText(ns.Stones:Byline(stone))
	self:UpdateEditButton()

	self.frame:SetSize(width + PAD * 2, height + TOP + 44)
	self.frame:Show()
	if not refreshing and SOUNDKIT and SOUNDKIT.IG_QUEST_LIST_OPEN then
		PlaySound(SOUNDKIT.IG_QUEST_LIST_OPEN)
	end
end

function ReadWindow:Hide()
	if self.frame then self.frame:Hide() end
end

-- The stone currently open, if any.
function ReadWindow:Current()
	return self.frame and self.frame:IsShown() and self.stone or nil
end
