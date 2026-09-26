local _, ns = ...

-- Shows one stone: its message, or its sketch at 3×. Opened by clicking a
-- readable minimap pin or with /soap read. Stones.lua closes it when the
-- player walks out of reading range.
--
-- Layout, top to bottom: the title bar ("Soapstone" left, the stone's
-- appraisals right); the message or sketch; Appraise and Disparage centred
-- under it (see Stones.lua for the rules); a horizontal rule; then Edit
-- (left, while your own stone's edit window is open) and who left it
-- (right). The window is as wide as the widest of those.
--
--  ┌ Soapstone                          Appraisals: 1   x ┐
--  │                  "Try jumping"                       │
--  │             [Appraised]  [Disparage]                 │
--  │ ──────────────────────────────────────────────────── │
--  │ [Edit (4:32)]                 — Mad Decent, just now │
--  └──────────────────────────────────────────────────────┘

local Sketch, SketchCanvas = ns.Sketch, ns.SketchCanvas

local ReadWindow = {}
ns.ReadWindow = ReadWindow

local FRAME_NAME = "SoapstoneReadFrame"
local READ_SCALE = 3 -- sketches: 160×60 cells at 3× = 480×180, as drawn
local PAD = 16
local TITLE_BAR = 24   -- the window template's title bar
local CONTENT_GAP = 18 -- the same space above the stone and below it (to the buttons)
local TOP = TITLE_BAR + CONTENT_GAP
local SKETCH_BORDER = 5 -- the sketch's border sits this far outside the canvas
local TEXT_WIDTH = 320
local TICK = 0.25
local BUTTON_HEIGHT = 22
local VOTE_WIDTH = 88      -- fits "Appraised" / "Disparaged"
local EDIT_WIDTH = 92
local CLOSE_BUTTON = 28    -- room left for the title bar's close button
local GAP = 4
local BYLINE_GAP = 16      -- at least this much between Edit and the byline
-- Measured up from the window's bottom edge:
local ROW_Y = 10                            -- Edit + byline row
local RULE_Y = ROW_Y + BUTTON_HEIGHT + 8    -- the horizontal rule
local VOTE_Y = RULE_Y + 1 + 10              -- Appraise / Disparage
local FOOTER = VOTE_Y + BUTTON_HEIGHT + CONTENT_GAP -- everything below the stone itself

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

	-- Title bar: "Soapstone" moves to the left; appraisals go on the right.
	local bar = f.TitleBg
	f.title:ClearAllPoints()
	f.title:SetJustifyH("LEFT")
	if bar then f.title:SetPoint("LEFT", bar, "LEFT", 6, 0) else f.title:SetPoint("TOPLEFT", 10, -5) end
	local appraisals = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	appraisals:SetJustifyH("RIGHT")
	if bar then
		appraisals:SetPoint("RIGHT", bar, "RIGHT", -CLOSE_BUTTON, 0)
	else
		appraisals:SetPoint("TOPRIGHT", -CLOSE_BUTTON - 2, -6)
	end
	self.appraisalsText = appraisals

	local text = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
	text:SetPoint("TOP", 0, -TOP)
	text:SetWidth(TEXT_WIDTH)
	text:SetJustifyH("CENTER")
	text:SetSpacing(3)
	self.text = text

	local canvas = SketchCanvas.Create(f, READ_SCALE)
	canvas.frame:SetPoint("TOP", 0, -TOP - SKETCH_BORDER)
	self.canvas = canvas

	-- Appraise and Disparage, centred under the stone.
	local appraise = button(f, "Appraise", VOTE_WIDTH)
	appraise:SetPoint("BOTTOMRIGHT", f, "BOTTOM", -GAP / 2, VOTE_Y)
	appraise:SetScript("OnClick", function() self:Vote(ns.Stones.APPRAISE) end)
	tooltip(appraise, "Appraise", "Tell the author this stone helped. On someone else's stone its pin turns gold. "
		.. "Your own stones start appraised. Click again to withdraw it.")
	self.appraiseButton = appraise

	local disparage = button(f, "Disparage", VOTE_WIDTH)
	disparage:SetPoint("LEFT", appraise, "RIGHT", GAP, 0)
	disparage:SetScript("OnClick", function() self:Vote(ns.Stones.DISPARAGE) end)
	tooltip(disparage, "Disparage", "This stone didn't help. On someone else's stone its pin fades and it stops "
		.. "calling you over. On your own stone it withdraws your appraisal (never below 0). Click again to withdraw it.")
	self.disparageButton = disparage

	-- A horizontal rule, then Edit (left) and the byline (right).
	local rule = f:CreateTexture(nil, "ARTWORK")
	rule:SetColorTexture(1, 1, 1, 0.15)
	rule:SetHeight(1)
	rule:SetPoint("BOTTOMLEFT", PAD - 4, RULE_Y)
	rule:SetPoint("BOTTOMRIGHT", -(PAD - 4), RULE_Y)
	self.rule = rule

	local edit = button(f, "Edit", EDIT_WIDTH)
	edit:SetPoint("BOTTOMLEFT", PAD - 4, ROW_Y)
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
-- stays lit; the title bar's appraisal count takes its colour.
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
	self.appraisalsText:SetText(format("Appraisals: %d", ns.Stones:Score(stone)))
	self.appraisalsText:SetTextColor(unpack(color))
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

-- The narrowest the window can be: wide enough for Appraise + Disparage, and
-- for Edit (when shown) beside the byline.
function ReadWindow:MinWidth()
	local votes = PAD * 2 + VOTE_WIDTH * 2 + GAP
	local footer = (PAD - 4) + self.byline:GetStringWidth() + PAD
	if self.editButton:IsShown() then footer = footer + EDIT_WIDTH + BYLINE_GAP end
	return math.max(votes, footer)
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
		width, height = cw + SKETCH_BORDER * 2, ch + SKETCH_BORDER * 2 -- gaps measured from the border
	else
		self.canvas.frame:Hide()
		-- A written stone is quoted, as in tooltips and chat; the fallback for an
		-- unreadable sketch is Soapstone talking, so it isn't.
		self.text:SetText(stone.text and format("\"%s\"", stone.text)
			or (stone.sketch and "The carving is too worn to make out.") or "")
		self.text:Show()
		width, height = TEXT_WIDTH, self.text:GetStringHeight() -- the text's real height, so both gaps match
	end

	self.byline:SetText(ns.Stones:Byline(stone))
	self:UpdateEditButton()
	self:UpdateVotes()

	self.frame:SetSize(math.max(width + PAD * 2, self:MinWidth()), height + TOP + FOOTER)
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
