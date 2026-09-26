local _, ns = ...

-- Shows one stone: its message, or its sketch at 2×. Opened by clicking a
-- readable minimap pin or with /soap read. Stones.lua closes it when the
-- player walks out of reading range.
--
-- The button row: your own written stones get "Edit (m:ss)", counting down
-- the edit window; everyone else's get Appraise and Disparage.

local Sketch, SketchCanvas = ns.Sketch, ns.SketchCanvas

local ReadWindow = {}
ns.ReadWindow = ReadWindow

local FRAME_NAME = "SoapstoneReadFrame"
local READ_SCALE = 2
local PAD = 16
local TOP = 36
local TEXT_WIDTH = 320
local TICK = 0.25
local FOOTER = 68 -- byline, then the button row

local function tooltip(owner, title, body)
	owner:SetScript("OnEnter", function(btn)
		GameTooltip:SetOwner(btn, "ANCHOR_TOP")
		GameTooltip:AddLine(title)
		GameTooltip:AddLine(body, 0.8, 0.8, 0.8, true)
		GameTooltip:Show()
	end)
	owner:SetScript("OnLeave", GameTooltip_Hide)
end

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
	byline:SetPoint("BOTTOMRIGHT", -PAD, 40)
	self.byline = byline

	local edit = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
	edit:SetSize(96, 22)
	edit:SetPoint("BOTTOMLEFT", PAD - 4, 10)
	edit:SetScript("OnClick", function()
		if self.stone then ns.EditWindow:Open(self.stone) end
	end)
	tooltip(edit, "Edit Soapstone", format("You can reword or delete a written stone for %d minutes after dropping it.",
		ns.Stones.EDIT_SECONDS / 60))
	edit:Hide()
	self.editButton = edit

	local appraise = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
	appraise:SetSize(100, 22)
	appraise:SetPoint("BOTTOMLEFT", PAD - 4, 10)
	appraise:SetScript("OnClick", function() self:Rate(ns.Stones.APPRAISE) end)
	tooltip(appraise, "Appraise", "This stone helped. Its pin turns gold on your minimap. Click again to take it back.")
	self.appraiseButton = appraise

	local disparage = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
	disparage:SetSize(100, 22)
	disparage:SetPoint("LEFT", appraise, "RIGHT", 4, 0)
	disparage:SetScript("OnClick", function() self:Rate(ns.Stones.DISPARAGE) end)
	tooltip(disparage, "Disparage",
		"This stone is unhelpful. Its pin fades and it stops calling you over. Click again to take it back.")
	self.disparageButton = disparage

	local elapsed = 0
	f:SetScript("OnUpdate", function(_, dt)
		elapsed = elapsed + dt
		if elapsed < TICK then return end
		elapsed = 0
		self:UpdateEditButton()
	end)
end

function ReadWindow:Rate(value)
	if not self.stone then return end
	ns.Stones:Rate(self.stone, value)
	self:UpdateRatingButtons()
end

-- Appraise / Disparage for other players' stones; the chosen one reads
-- "Appraised" / "Disparaged" and stays highlighted.
function ReadWindow:UpdateRatingButtons()
	local stone = self.stone
	local canRate = stone ~= nil and not ns.Store.IsMine(stone)
	local rating = canRate and ns.Stones:Rating(stone)
	local buttons = {
		{ self.appraiseButton, ns.Stones.APPRAISE, "Appraise", "Appraised" },
		{ self.disparageButton, ns.Stones.DISPARAGE, "Disparage", "Disparaged" },
	}
	for _, b in ipairs(buttons) do
		local button, value, label, chosen = b[1], b[2], b[3], b[4]
		button:SetShown(canRate)
		button:SetText(rating == value and chosen or label)
		if rating == value then button:LockHighlight() else button:UnlockHighlight() end
	end
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
	self:UpdateRatingButtons()

	self.frame:SetSize(width + PAD * 2, height + TOP + FOOTER)
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
