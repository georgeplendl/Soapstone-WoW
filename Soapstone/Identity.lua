local _, ns = ...

-- Who and where: the game flavour a stone belongs to, and player identity.
--
-- Flavour keeps WoW Forever, Retail and Classic stones apart. Forever runs on
-- the mainline codebase (WOW_PROJECT_ID 1, like Retail) but on 1.x builds.
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

function Identity.Flavor()
	if not flavor then
		local project = WOW_PROJECT_ID or 1
		local major = tonumber((GetBuildInfo()):match("^(%d+)")) or 0
		if project == 1 then
			flavor = major < 2 and "forever" or "retail"
		elseif project == 2 then
			flavor = "classic"
		else
			flavor = "classic-" .. project
		end
	end
	return flavor
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
	if Identity.Flavor() ~= "forever" then return key end
	return (key:gsub("%-", " ", 1))
end
