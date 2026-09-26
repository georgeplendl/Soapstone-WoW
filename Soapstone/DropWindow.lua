local _, ns = ...

-- "Leave a Soapstone": the drop window. Two Blizzard-style tabs along the
-- bottom switch between Write (a short message, WritePanel) and Draw (a
-- sketch, DrawPanel: Splatoon-style tools beside the canvas).
--
--  ┌ Leave a Soapstone ─────────────────────────────── x ┐
--  │ Pen  Eraser   ┌──────────────────────────────────┐   │
--  │ [·]  [▫]      │                                  │   │
--  │ [•]  [□]      │        160 × 60 canvas, 3×       │   │
--  │ [●]  [▢]      │                                  │   │
--  │ [ Undo  ]     └──────────────────────────────────┘   │
--  │ [ Clear ]      Left-drag to draw · Right-drag erases │
--  │                              [ Drop Stone ][Cancel]  │
--  └──────────────────────────────────────────────────────┘
--    (Write)(Draw)

local Sketch = ns.Sketch

local DropWindow = {}
ns.DropWindow = DropWindow

local FRAME_NAME = "SoapstoneDropFrame"
local PAD = 14
local TOP = 34    -- clears the title bar
local FOOTER = 62 -- hint line + action buttons

local TAB_TEMPLATES = { "CharacterFrameTabButtonTemplate", "CharacterFrameTabTemplate", "PanelTabButtonTemplate" }

local function templateExists(name)
	if C_XMLUtil and C_XMLUtil.GetTemplateInfo then
		return C_XMLUtil.GetTemplateInfo(name) ~= nil
	end
	return true -- can't check on this client; CreateFrame is wrapped in pcall
end

-- A bottom tab in whichever style this client ships. Falls back to a plain
-- panel button if none of the known tab templates exist.
local function createTab(parent, id)
	local name = parent:GetName() .. "Tab" .. id
	for _, template in ipairs(TAB_TEMPLATES) do
		if templateExists(template) then
			local ok, tab = pcall(CreateFrame, "Button", name, parent, template)
			if ok and tab then
				tab:SetID(id)
				return tab, true
			end
		end
	end
	local tab = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
	tab:SetSize(80, 24)
	tab:SetID(id)
	return tab, false
end

local function createActionButton(parent, text, width)
	local btn = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
	btn:SetSize(width, 22)
	btn:SetText(text)
	return btn
end

-- Building ------------------------------------------------------------------

function DropWindow:Build()
	local f = ns.CreateWindow(FRAME_NAME, "Leave a Soapstone")
	f:SetPoint("CENTER", 0, 80)
	self.frame = f

	local drawer = ns.DrawPanel.Create(f, function() self:UpdateButtons() end)
	drawer.frame:SetPoint("TOPLEFT", 0, -TOP)
	self.drawer = drawer

	local writer = ns.WritePanel.Create(f, function() self:Submit() end, function() self:UpdateButtons() end)
	writer.frame:SetPoint("TOPLEFT", PAD, -TOP)
	writer.frame:SetPoint("BOTTOMRIGHT", drawer.canvas.frame, "BOTTOMRIGHT", 6, -6)
	self.writer = writer

	local cancel = createActionButton(f, CANCEL, 90)
	cancel:SetPoint("BOTTOMRIGHT", -PAD, 12)
	cancel:SetScript("OnClick", function() f:Hide() end)
	local drop = createActionButton(f, "Drop Stone", 110)
	drop:SetPoint("RIGHT", cancel, "LEFT", -4, 0)
	drop:SetScript("OnClick", function() self:Submit() end)
	self.dropButton = drop

	self.tabs = {}
	for i, label in ipairs({ "Write", "Draw" }) do
		local tab, blizzard = createTab(f, i)
		tab:SetText(label)
		if blizzard and PanelTemplates_TabResize then PanelTemplates_TabResize(tab, 0) end
		tab:SetScript("OnClick", function()
			self:SetMode(i == 1 and "text" or "sketch")
			if SOUNDKIT and SOUNDKIT.IG_CHARACTER_INFO_TAB then PlaySound(SOUNDKIT.IG_CHARACTER_INFO_TAB) end
		end)
		self.tabs[i] = tab
		self.blizzardTabs = blizzard
	end
	self.tabs[1]:SetPoint("TOPLEFT", f, "BOTTOMLEFT", 12, 2)
	self.tabs[2]:SetPoint("LEFT", self.tabs[1], "RIGHT", self.blizzardTabs and -14 or 4, 0)
	if self.blizzardTabs then
		f.Tabs = self.tabs
		PanelTemplates_SetNumTabs(f, #self.tabs)
	end
end

-- Behaviour -----------------------------------------------------------------

function DropWindow:Layout()
	local width, height = self.drawer:Layout()
	self.frame:SetSize(width + PAD, TOP + height + FOOTER)
end

function DropWindow:Open()
	if not self.frame then self:Build() end
	self:Layout()
	self.frame:Show()
	self:SetMode(ns.db.dropMode)
end

function DropWindow:SetMode(mode)
	if mode ~= "sketch" then mode = "text" end
	ns.db.dropMode = mode
	local sketch = mode == "sketch"
	self.drawer.frame:SetShown(sketch)
	self.writer.frame:SetShown(not sketch)

	if self.blizzardTabs then
		PanelTemplates_SetTab(self.frame, sketch and 2 or 1)
	else
		for i, tab in ipairs(self.tabs) do
			if (i == 2) == sketch then tab:LockHighlight() else tab:UnlockHighlight() end
		end
	end

	if sketch then self.writer:ClearFocus() else self.writer:Focus() end
	self:UpdateButtons()
end

function DropWindow:HasContent()
	if ns.db.dropMode == "sketch" then
		return not self.drawer:IsEmpty()
	end
	return self.writer:GetText() ~= ""
end

function DropWindow:UpdateButtons()
	if not self.dropButton then return end
	self.dropButton:SetEnabled(self:HasContent())
	self.drawer:Refresh()
end

-- Drops the current text or sketch. The draft is kept if the window is simply
-- closed, and cleared once a stone is actually dropped.
function DropWindow:Submit()
	if not self:HasContent() then return end
	local stone
	if ns.db.dropMode == "sketch" then
		stone = ns.Stones:Drop({ sketch = Sketch.Pack(self.drawer:GetGrid()) })
		if stone then self.drawer:Reset() end
	else
		stone = ns.Stones:Drop({ text = self.writer:GetText() })
		if stone then self.writer:SetText("") end
	end
	if stone then self.frame:Hide() end
end
