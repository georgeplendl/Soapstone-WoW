local _, ns = ...

-- "Get the companion": where to download the Soapstone companion, which is
-- what shares stones between players. WoW can't open web pages, so the link
-- sits selected in a box, ready for Ctrl+C.
--
-- Opens with /soap companion, when you sync without a companion, and once
-- by itself the first time you log in without one (ns.db.companionOffered).

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

	local close = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
	close:SetSize(100, 22)
	close:SetPoint("BOTTOM", 0, 14)
	close:SetText("Close")
	close:SetScript("OnClick", function() f:Hide() end)

	self.frame, self.body, self.box, self.hint, self.closeButton = f, body, box, hint, close
end

function Window:Open()
	self:Build()
	self.frame:Show()
	self.box:SetText(self.URL)
	self.box:SetFocus()
	self.box:HighlightText()
end

function Window:Close()
	if self.frame then self.frame:Hide() end
end

-- After the companion's data has loaded: the first time there's none, show
-- the window once, a few seconds in. Never again after that; the minimap
-- button's tooltip and /soap companion still point the way.
function Window:OfferOnce()
	if ns.Companion.state ~= "none" or ns.db.companionOffered then return false end
	ns.db.companionOffered = true
	C_Timer.After(self.OFFER_DELAY, function() Window:Open() end)
	return true
end
