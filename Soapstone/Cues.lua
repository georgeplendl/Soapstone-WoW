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
}

local function resolveKit(cue)
	if cue.kit == nil then
		cue.kit = false
		for _, name in ipairs(cue.kits) do
			if SOUNDKIT and SOUNDKIT[name] then
				cue.kit = SOUNDKIT[name]
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
