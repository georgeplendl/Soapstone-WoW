local _, ns = ...

-- Sound cues. Each cue lists SOUNDKIT names in order of preference; the first
-- one this client knows is used, so the same code works on Classic and retail.
-- To use custom audio, drop an .ogg in the addon folder and add its path as a
-- `file` (e.g. "Interface\\AddOns\\Soapstone\\Sounds\\near.ogg").

local Cues = {}
ns.Cues = Cues

local CUES = {
	near = { kits = { "MAP_PING", "TELL_MESSAGE" } },                          -- a sealed stone is somewhere close
	read = { kits = { "IG_QUEST_LIST_COMPLETE", "READY_CHECK", "MAP_PING" } }, -- you can read it from here
	appraise = { kits = { "IG_QUEST_LIST_SELECT", "IG_QUEST_LIST_OPEN", "IG_MAINMENU_OPTION_CHECKBOX_ON" } },
	disparage = { kits = { "IG_QUEST_LOG_ABANDON_QUEST", "IG_MAINMENU_OPTION_CHECKBOX_OFF", "IG_MAINMENU_CLOSE" } },
	-- you set a stone down: a crystal settling into place, else a gem clink,
	-- else the thunk of dropping an ability on the action bar
	drop = { kits = { "UI_70_ARTIFACT_FORGE_RELIC_PLACE", "PUT_DOWN_GEMS", "IG_ABILITY_ICON_DROP" } },
}
Cues.NAMES = { "near", "read", "appraise", "disparage", "drop" }

local function resolveKit(cue)
	if cue.kit == nil then
		cue.kit = false
		for _, name in ipairs(cue.kits) do
			if SOUNDKIT and SOUNDKIT[name] then
				cue.kit, cue.kitName = SOUNDKIT[name], name
				break
			end
		end
	end
	return cue.kit
end

function Cues:Play(name, force)
	if not force and not ns.db.sound then return end
	local cue = CUES[name]
	if not cue then return end
	if cue.file then
		PlaySoundFile(cue.file, "SFX")
		return
	end
	local kit = resolveKit(cue)
	if kit then PlaySound(kit, "SFX") end
end

-- Plays a cue even with sounds off; returns what it played (a SOUNDKIT name
-- or file), nil if the client has none of its sounds, or false for no such cue.
function Cues:Preview(name)
	local cue = CUES[name]
	if not cue then return false end
	self:Play(name, true)
	if cue.file then return cue.file end
	resolveKit(cue)
	return cue.kitName
end
