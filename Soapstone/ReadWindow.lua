local _, ns = ...

-- Shows one stone: its message, or its sketch at 2×. Opened by clicking a
-- readable minimap pin or with /soap read. Stones.lua closes it when the
-- player walks out of reading range.
--
-- The bottom row: every stone gets a ▲ score ▼ vote control (appraise /
-- disparage, Reddit-style; see Stones.lua); your own stones also get
-- "Edit (m:ss)" while their edit window is open.

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

	-- ▲ score ▼, built from Blizzard's scroll-arrow buttons.
	local function arrow(direction)
		local btn = CreateFrame("Button", nil, f)
		btn:SetSize(24, 24)
		local art = "Interface\\Buttons\\UI-ScrollBar-Scroll" .. direction .. "Button-"
		btn:SetNormalTexture(art .. "Up")
		btn:SetPushedTexture(art .. "Down")
		btn:SetHighlightTexture(art .. "Highlight", "ADD")
		return btn
	end
	local up = arrow("Up")
	up:SetPoint("BOTTOMLEFT", PAD - 6, 9)
	up:SetScript("OnClick", function() self:Vote(ns.Stones.APPRAISE) end)
	tooltip(up, "Appraise",
		"Upvote. On someone else's stone its pin turns gold. Your own stones start upvoted. Click again to take it back.")
	local score = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	score:SetPoint("LEFT", up, "RIGHT", 0, 0)
	score:SetWidth(30)
	score:SetJustifyH("CENTER")
	local down = arrow("Down")
	down:SetPoint("LEFT", score, "RIGHT", 0, 0)
	down:SetScript("OnClick", function() self:Vote(ns.Stones.DISPARAGE) end)
	tooltip(down, "Disparage", "Downvote. On someone else's stone its pin fades and it stops calling you over. "
		.. "On your own stone it takes your upvote back (down to 0). Click again to take it back.")
	self.upButton, self.scoreText, self.downButton = up, score, down

	local edit = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
	edit:SetSize(96, 22)
	edit:SetPoint("LEFT", down, "RIGHT", 8, 0)
	edit:SetScript("OnClick", function()
		if self.stone then ns.EditWindow:Open(self.stone) end
	end)
	tooltip(edit, "Edit Soapstone", format("You can change or delete your stone for %d minutes after posting it "
		.. "(the clock pauses while you edit, and restarts when you save).", ns.Stones.EDIT_SECONDS / 60))
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

function ReadWindow:Vote(arrow)
	if not self.stone then return end
	ns.Stones:Vote(self.stone, arrow)
	self:UpdateVotes()
end

local UP_COLOR = { 1, 0.55, 0.1 }    -- Reddit orange
local DOWN_COLOR = { 0.45, 0.6, 1 }  -- Reddit blue
local IDLE_COLOR = { 0.75, 0.75, 0.75 }

-- Colours the arrow you voted with and shows the score in the same colour.
function ReadWindow:UpdateVotes()
	local stone = self.stone
	if not stone then return end
	local vote = ns.Stones:Rating(stone)
	local upColor = vote == ns.Stones.APPRAISE and UP_COLOR or IDLE_COLOR
	local downColor = vote == ns.Stones.DISPARAGE and DOWN_COLOR or IDLE_COLOR
	self.upButton:GetNormalTexture():SetVertexColor(unpack(upColor))
	self.downButton:GetNormalTexture():SetVertexColor(unpack(downColor))
	local scoreColor = vote == ns.Stones.APPRAISE and UP_COLOR or vote == ns.Stones.DISPARAGE and DOWN_COLOR
		or { 1, 1, 1 }
	self.scoreText:SetText(ns.Stones:Score(stone))
	self.scoreText:SetTextColor(unpack(scoreColor))
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
	self:UpdateVotes()

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
