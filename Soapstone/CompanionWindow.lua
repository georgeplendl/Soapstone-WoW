local _, ns = ...

-- "Get the companion": where to download the Soapstone companion, which is
-- what shares stones between players. WoW can't open web pages, so the link
-- sits selected in a box, ready for Ctrl+C.
--
-- Opens with /soap companion, when you sync without a companion, and by
-- itself a few seconds into every login (not reloads or loading screens)
-- until the companion turns up, unless you tick "Don't show this again"
-- (ns.db.companionDismissed).

local Window = {}
ns.CompanionWindow = Window

-- The companion's download page. Only companion releases are marked Latest
-- on GitHub (addon releases go out with --latest=false), so this is always
-- its newest installer.
Window.URL = "https://github.com/georgeplendl/Soapstone-WoW/releases/latest"
Window.OFFER_DELAY = 5 -- seconds after login, so it isn't lost in the login messages

local WIDTH, HEIGHT = 440, 250
local TEXT = "Soapstone shares stones through the |cffffd100Soapstone companion|r, a small app"
	.. " for Windows that runs next to WoW (a macOS version is coming soon).\n\n"
	.. "|cffff8040Without it, nobody else will see your stones, and you won't find theirs.|r\n\n"
	.. "Get it here:"

function Window:Build()
	if self.frame then return end
	local f = ns.CreateWindow("SoapstoneCompanionWindow", "The Soapstone Companion")
	f:SetSize(WIDTH, HEIGHT)
	f:SetPoint("CENTER", 0, 100)

	local body = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	body:SetPoint("TOPLEFT", 22, -36)
	body:SetPoint("TOPRIGHT", -22, -36)
	body:SetJustifyH("LEFT")
	body:SetText(TEXT)

	-- Typing can't change the link: anything typed puts it back, selected.
	local box = CreateFrame("EditBox", nil, f, "InputBoxTemplate")
	box:SetAutoFocus(false)
	box:SetSize(WIDTH - 56, 22)
	box:SetPoint("TOPLEFT", body, "BOTTOMLEFT", 6, -10)
	box:SetScript("OnTextChanged", function(edit, userInput)
		if userInput then
			edit:SetText(Window.URL)
			edit:HighlightText()
		end
	end)
	box:SetScript("OnEditFocusGained", function(edit) edit:HighlightText() end)
	box:SetScript("OnMouseUp", function(edit) edit:HighlightText() end)
	box:SetScript("OnEscapePressed", function() f:Hide() end)
	box:SetScript("OnEnterPressed", function() f:Hide() end)

	local hint = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	hint:SetPoint("TOPLEFT", box, "BOTTOMLEFT", -6, -6)
	hint:SetText("Press Ctrl+C to copy it, then paste it into your web browser.")

	-- Only while there's no companion: it stops the login reminder, nothing else.
	local dismiss = CreateFrame("CheckButton", nil, f, "UICheckButtonTemplate")
	dismiss:SetSize(24, 24)
	dismiss:SetPoint("BOTTOMLEFT", 16, 12)
	local label = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	label:SetPoint("LEFT", dismiss, "RIGHT", 2, 0)
	label:SetText("Don't show this again")
	dismiss:SetHitRectInsets(0, -label:GetStringWidth() - 4, 0, 0) -- the label is clickable too
	dismiss:SetScript("OnClick", function(check) ns.db.companionDismissed = check:GetChecked() and true or false end)

	local close = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
	close:SetSize(100, 22)
	close:SetPoint("BOTTOMRIGHT", -16, 14)
	close:SetText("Close")
	close:SetScript("OnClick", function() f:Hide() end)

	self.frame, self.body, self.box, self.hint, self.closeButton = f, body, box, hint, close
	self.dismissCheck, self.dismissLabel = dismiss, label
end

-- `quietly`: opened by itself at login, so it leaves the keyboard alone
-- (focus would turn your movement keys into typing in the link box).
function Window:Open(quietly)
	self:Build()
	local noCompanion = ns.Companion.state == "none"
	self.dismissCheck:SetShown(noCompanion)
	self.dismissLabel:SetShown(noCompanion)
	self.dismissCheck:SetChecked(ns.db.companionDismissed and true or false)
	self.frame:Show()
	self.box:SetText(self.URL)
	if not quietly then
		self.box:SetFocus()
		self.box:HighlightText()
	end
end

function Window:Close()
	if self.frame then self.frame:Hide() end
end

-- From PLAYER_ENTERING_WORLD, after the companion's data has loaded: on a
-- real login (not a reload or a loading screen) without a companion, opens
-- a few seconds in, unless you've said not to.
function Window:OfferAtLogin(isInitialLogin)
	if not isInitialLogin or ns.Companion.state ~= "none" or ns.db.companionDismissed then return false end
	C_Timer.After(self.OFFER_DELAY, function()
		if ns.Companion.state == "none" then Window:Open(true) end
	end)
	return true
end
