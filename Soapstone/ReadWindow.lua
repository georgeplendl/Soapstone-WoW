local _, ns = ...

-- Shows one stone: its message, or its sketch at 2×. Opened by clicking a
-- readable minimap pin or with /soap read. Stones.lua closes it when the
-- player walks out of reading range.
--
-- One row along the bottom: Appraise, the score, Disparage (see Stones.lua
-- for the rules), Edit while your own stone's edit window is open, and who
-- left it. The window widens to fit that row; the stone stays centred above.
--
--  ┌ Soapstone ─────────────────────────────────────────────── x ┐
--  │                   "Try jumping"                             │
--  │ [Appraise] 1 [Disparage] [Edit (4:32)]  — Mad Decent, just now │
--  └─────────────────────────────────────────────────────────────┘

local Sketch, SketchCanvas = ns.Sketch, ns.SketchCanvas

local ReadWindow = {}
ns.ReadWindow = ReadWindow

local FRAME_NAME = "SoapstoneReadFrame"
local READ_SCALE = 2
local PAD = 16
local TOP = 36
local TEXT_WIDTH = 320
local TICK = 0.25
local FOOTER = 44          -- the bottom row, with margins
local ROW_Y = 10           -- bottom row's distance from the window's bottom edge
local BUTTON_HEIGHT = 22
local VOTE_WIDTH = 88      -- fits "Appraised" / "Disparaged"
local SCORE_WIDTH = 26
local EDIT_WIDTH = 92
local GAP = 4
local BYLINE_GAP = 16      -- at least this much between the buttons and the byline

local APPRAISED_COLOR = { 1, 0.82, 0 }     -- gold, like appraised pins
local DISPARAGED_COLOR = { 0.6, 0.6, 0.6 } -- grey, like disparaged pins

local function tooltip(owner, title, body)
	owner:SetScript("OnEnter", function(btn)
		GameTooltip:SetOwner(btn, "ANCHOR_TOP")
		GameTooltip:AddLine(title)
		GameTooltip:AddLine(body, 0.8, 0.8, 0.8, true)
		GameTooltip:Show()
	end)
	owner:SetScript("OnLeave", GameTooltip_Hide)
end

local function button(parent, text, width)
	local btn = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
	btn:SetSize(width, BUTTON_HEIGHT)
	btn:SetText(text)
	return btn
end

function ReadWindow:Build()
	local f = ns.CreateWindow(FRAME_NAME, "Soapstone")
	f:SetPoint("CENTER", 0, 120)
	f:SetScript("OnHide", function() self.stone = nil end)
	self.frame = f

	local text = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
	text:SetPoint("TOP", 0, -TOP)
	text:SetWidth(TEXT_WIDTH)
	text:SetJustifyH("CENTER")
	text:SetSpacing(3)
	self.text = text

	local canvas = SketchCanvas.Create(f, READ_SCALE)
	canvas.frame:SetPoint("TOP", 0, -TOP - 4)
	self.canvas = canvas

	local appraise = button(f, "Appraise", VOTE_WIDTH)
	appraise:SetPoint("BOTTOMLEFT", PAD - 4, ROW_Y)
	appraise:SetScript("OnClick", function() self:Vote(ns.Stones.APPRAISE) end)
	tooltip(appraise, "Appraise", "Tell the author this stone helped. On someone else's stone its pin turns gold. "
		.. "Your own stones start appraised. Click again to withdraw it.")
	self.appraiseButton = appraise

	local score = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	score:SetPoint("LEFT", appraise, "RIGHT", GAP / 2, 0)
	score:SetWidth(SCORE_WIDTH)
	score:SetJustifyH("CENTER")
	self.scoreText = score

	local disparage = button(f, "Disparage", VOTE_WIDTH)
	disparage:SetPoint("LEFT", score, "RIGHT", GAP / 2, 0)
	disparage:SetScript("OnClick", function() self:Vote(ns.Stones.DISPARAGE) end)
	tooltip(disparage, "Disparage", "This stone didn't help. On someone else's stone its pin fades and it stops "
		.. "calling you over. On your own stone it withdraws your appraisal (never below 0). Click again to withdraw it.")
	self.disparageButton = disparage

	local edit = button(f, "Edit", EDIT_WIDTH)
	edit:SetPoint("LEFT", disparage, "RIGHT", GAP + 2, 0)
	edit:SetScript("OnClick", function()
		if self.stone then ns.EditWindow:Open(self.stone) end
	end)
	tooltip(edit, "Edit Soapstone", format("You can change or delete your stone for %d minutes after posting it "
		.. "(the clock pauses while you edit, and restarts when you save).", ns.Stones.EDIT_SECONDS / 60))
	edit:Hide()
	self.editButton = edit

	local byline = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	byline:SetPoint("RIGHT", f, "BOTTOMRIGHT", -PAD, ROW_Y + BUTTON_HEIGHT / 2)
	byline:SetJustifyH("RIGHT")
	self.byline = byline

	local elapsed = 0
	f:SetScript("OnUpdate", function(_, dt)
		elapsed = elapsed + dt
		if elapsed < TICK then return end
		elapsed = 0
		self:UpdateEditButton()
	end)
end

function ReadWindow:Vote(which)
	if not self.stone then return end
	ns.Stones:Vote(self.stone, which)
	self:UpdateVotes()
end

-- The button matching your judgement reads "Appraised" / "Disparaged" and
-- stays lit; the score takes its colour.
function ReadWindow:UpdateVotes()
	local stone = self.stone
	if not stone then return end
	local vote = ns.Stones:Rating(stone)
	local buttons = {
		{ self.appraiseButton, ns.Stones.APPRAISE, "Appraise", "Appraised" },
		{ self.disparageButton, ns.Stones.DISPARAGE, "Disparage", "Disparaged" },
	}
	for _, b in ipairs(buttons) do
		local btn, value, label, chosen = b[1], b[2], b[3], b[4]
		btn:SetText(vote == value and chosen or label)
		if vote == value then btn:LockHighlight() else btn:UnlockHighlight() end
	end
	local color = vote == ns.Stones.APPRAISE and APPRAISED_COLOR
		or vote == ns.Stones.DISPARAGE and DISPARAGED_COLOR or { 1, 1, 1 }
	self.scoreText:SetText(ns.Stones:Score(stone))
	self.scoreText:SetTextColor(unpack(color))
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

-- How wide the bottom row needs the window to be.
function ReadWindow:RowWidth()
	local buttons = (PAD - 4) + VOTE_WIDTH + GAP / 2 + SCORE_WIDTH + GAP / 2 + VOTE_WIDTH
	if self.editButton:IsShown() then buttons = buttons + GAP + 2 + EDIT_WIDTH end
	return buttons + BYLINE_GAP + self.byline:GetStringWidth() + PAD
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
	self:UpdateVotes()

	self.frame:SetSize(math.max(width + PAD * 2, self:RowWidth()), height + TOP + FOOTER)
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
