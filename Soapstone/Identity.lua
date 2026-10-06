local _, ns = ...

-- Who and where: the game flavour a stone belongs to, and player identity.
--
-- Flavour keeps WoW Forever, Retail and Classic stones apart. It's a fixed
-- label stored on every stone, so however a client patch changes the ways
-- of telling games apart, the labels must not change. WoW Forever has
-- shown up two ways: early beta builds ran as the mainline project
-- (WOW_PROJECT_ID 1) on 1.60 builds; build 70235 (2026-10-05) has its own
-- project, WOW_PROJECT_CAMELOT = 18. Both are "forever", and so is any 1.60+
-- build (Classic Era is 1.15), in case launch renumbers it again.
--
-- Identity: on WoW Forever, UnitFullName returns ("Mad", "Decent"), with
-- the second part in the realm slot, and the UI shows "Mad Decent". Normal
-- servers have ("Mad", "Stormrage"). Either way the pair is unique, so the
-- key is WoW's usual Name-Realm form ("Mad-Decent") and no login is needed.
-- Addon-message senders may arrive as "Mad-Decent", "Mad Decent" or just
-- "Mad" (same realm); KeyFromSender folds all of those into the key.

local Identity = {}
ns.Identity = Identity

local flavor

-- Labels earlier versions gave Forever stones, relabelled on load
-- (Store.lua). 0.4 called build 70235 "classic-18".
Identity.FLAVOR_ALIASES = { ["classic-18"] = "forever" }

function Identity.Flavor()
	if not flavor then
		local project = WOW_PROJECT_ID or 1
		local major, minor = (GetBuildInfo()):match("^(%d+)%.(%d+)")
		major, minor = tonumber(major) or 0, tonumber(minor) or 0
		if (WOW_PROJECT_CAMELOT and project == WOW_PROJECT_CAMELOT) or (major == 1 and minor >= 60)
			or (project == 1 and major < 2) then
			flavor = "forever"
		elseif project == 1 then
			flavor = "retail"
		elseif project == 2 then
			flavor = "classic"
		else
			flavor = Identity.FLAVOR_ALIASES["classic-" .. project] or ("classic-" .. project)
		end
	end
	return flavor
end

-- The WoW region ("us", "eu", ...), which keeps the companion's stones apart
-- by region, plus the raw id. WoW Forever's beta reports 90 (its Config.wtf
-- says portal "test"): "test", so beta stones stay apart from launch ones.
-- nil if the client doesn't say or says something unknown; the raw id is
-- still returned so it can be checked.
local REGIONS = { "us", "kr", "eu", "tw", "cn", [90] = "test" }

function Identity.Region()
	local id = GetCurrentRegion and GetCurrentRegion()
	return id and REGIONS[id], id
end

local function realmPart(realm)
	return (realm or ""):gsub("[%s%-]", "")
end

-- "Mad", "Decent" -> "Mad-Decent"
function Identity.Key(name, realm)
	realm = realmPart(realm)
	if realm == "" then realm = realmPart(GetNormalizedRealmName and GetNormalizedRealmName() or GetRealmName()) end
	if realm == "" then return name end
	return name .. "-" .. realm
end

function Identity.PlayerKey()
	return Identity.Key(UnitFullName("player"))
end

-- What the game's own UI calls you ("Mad Decent" on WoW Forever).
function Identity.PlayerDisplay()
	return GetUnitName("player", true) or UnitName("player")
end

-- Any sender string from CHAT_MSG_ADDON -> key.
function Identity.KeyFromSender(sender)
	if not sender or sender == "" then return nil end
	local name, realm = sender:match("^([^%-%s]+)[%-%s](.+)$")
	if name then return Identity.Key(name, realm) end
	return Identity.Key(sender, nil)
end

-- "Mad-Decent" -> "Mad Decent" on WoW Forever, which shows names that way;
-- elsewhere the realm really is a realm, so keep "Mad-Stormrage".
function Identity.Display(key)
	if not key then return nil end
	-- Names come from other players too: never let one carry escape codes.
	if key:find("|") then key = ns.Codec and ns.Codec.Neutralize(key) or key:gsub("|", "||") end
	if Identity.Flavor() ~= "forever" then return key end
	return (key:gsub("%-", " ", 1))
end
