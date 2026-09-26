-- Sound cues: each cue plays the first SOUNDKIT the client has, respects the
-- sound setting, and /soap sound <cue> previews one.
dofile(TESTS .. "/lib/harness.lua")

format = string.format
local played = {}
function PlaySound(kit, channel) played[#played + 1] = { kit = kit, channel = channel } end
function PlaySoundFile() end
-- Like an older client: no artifact-forge sound, but the gem clink is there.
SOUNDKIT = { PUT_DOWN_GEMS = 1204, IG_QUEST_LOG_ABANDON_QUEST = 846, IG_ABILITY_ICON_DROP = 838, MAP_PING = 3175 }

local ns = { db = { sound = true } }
assert(loadfile(ROOT .. "/Cues.lua"))("Soapstone", ns)
local Cues = ns.Cues

Cues:Play("drop")
check(#played == 1 and played[1].kit == 1204 and played[1].channel == "SFX",
	"drop falls back to the first sound this client has (gem clink)")

ns.db.sound = false
Cues:Play("drop")
check(#played == 1, "no drop sound with sound cues off")

check(Cues:Preview("drop") == "PUT_DOWN_GEMS" and #played == 2, "preview plays it anyway and names it")
check(Cues:Preview("delete") == "UI_ADVENTURES_AURA_REMOVE (165943)" and played[3].kit == 165943,
	"delete plays the sound picked in game, by id")
check(Cues:Preview("nope") == false and #played == 3, "an unknown cue plays nothing")

local known = true
for _, name in ipairs(Cues.NAMES) do
	if Cues:Preview(name) == false then known = false end
end
check(known, "every listed cue exists")

done()
