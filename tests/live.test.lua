-- Live changes (sharing step 4) on the simulated WoW Forever: drops, edits
-- and deletions are announced on the channel and fetched from the author.
dofile(TESTS .. "/lib/harness.lua")
format = string.format
local Sim = dofile(TESTS .. "/lib/wowsim.lua")
Sim.ROOT = ROOT
math.randomseed(11)

local BARRENS, BLUFF = 1413, 1456

-- What Stones:Drop / Edit / Delete do to the store, minus the UI.
local function drop(c, n, zone, opts)
	local s = Sim.give(c, Sim.stone(c.key, n, zone, opts))
	c.ns.Store:MarkChanged(s.id)
	return s
end
local function edit(c, id, text)
	local s = c.ns.Store:Get(id)
	s.text, s.v, s.edited = text, (s.v or 1) + 1, math.floor(Sim.now())
	c.ns.Store:MarkChanged(id)
end
local function sentBy(c, kind, from)
	local n = 0
	for i = (from or 0) + 1, #Sim.wire do
		if Sim.wire[i].from == c.key and Sim.wire[i].kind == kind then n = n + 1 end
	end
	return n
end

local ann = Sim.client("Ann", "Author")
local ben = Sim.client("Ben", "Barrens")   -- in the same zone
local cal = Sim.client("Cal", "Bluff")     -- elsewhere, not holding anything
local dee = Sim.client("Dee", "Holder")    -- elsewhere, but already has Ann's stone
Sim.run(10)
for _, c in ipairs({ ann, ben }) do c.ns.Sync:OnZone(BARRENS) end
for _, c in ipairs({ cal, dee }) do c.ns.Sync:OnZone(BLUFF) end
Sim.run(10) -- let the settle-time zone syncs run first

---------------------------------------------------------------------------
-- A drop reaches players in that zone within seconds.
local w = #Sim.wire
local s = drop(ann, 1, BARRENS, { text = "Try jumping" })
local took = Sim.runUntil(function() return ben.ns.Store:Get(s.id) ~= nil end, 30, 0.1)
check(took ~= nil, ("Ben (same zone) got the new stone in %.1f s"):format(took or -1))
check(took and took < 5, "within a few seconds")
local got = ben.ns.Store:Get(s.id)
check(got and got.text == "Try jumping" and got.verified == true, "first-hand and intact")
check(sentBy(ann, "NS", w) == 1, "Ann announced it once on the channel")
Sim.run(5)
check(cal.ns.Store:Get(s.id) == nil and sentBy(cal, "SG", w) == 0, "Cal (other zone) didn't fetch it")
check(ann.ns.db.outbox[s.id] == nil, "Ann's outbox is empty again")

---------------------------------------------------------------------------
-- An edit reaches the reader, and a holder in another zone.
Sim.give(dee, s, "Ann-Author")
w = #Sim.wire
edit(ann, s.id, "Try rolling")
Sim.runUntil(function()
	local b, d = ben.ns.Store:Get(s.id), dee.ns.Store:Get(s.id)
	return b and b.v == 2 and d and d.v == 2
end, 30, 0.1)
check(ben.ns.Store:Get(s.id).text == "Try rolling", "Ben sees the edit")
check(dee.ns.Store:Get(s.id).text == "Try rolling", "Dee, holding it from another zone, sees it too")
check(sentBy(cal, "SG", w) == 0, "Cal still isn't bothered")

---------------------------------------------------------------------------
-- A deletion removes it everywhere it was held.
ann.ns.Store:Tombstone(ann.ns.Store:Get(s.id))
Sim.runUntil(function()
	local b, d = ben.ns.Store:Get(s.id), dee.ns.Store:Get(s.id)
	return b and b.deleted and d and d.deleted
end, 30, 0.1)
check(ben.ns.Store:Get(s.id).deleted and dee.ns.Store:Get(s.id).deleted, "deleted for Ben and Dee")
local indexed = false
for _, x in ipairs(ben.ns.Store:Near({ instance = 1, wx = -1400 + 7, wy = -3700 + 3 }, 3)) do
	if x.id == s.id then indexed = true end
end
check(not indexed, "and gone from Ben's minimap")

---------------------------------------------------------------------------
-- Forgeries and unrequested stones are ignored.
local eve = Sim.client("Eve", "Forger")
Sim.run(10)
eve.ns.Sync:OnZone(BARRENS)
w = #Sim.wire
local fake = Sim.stone("Ann-Author", 9, BARRENS, { text = "not Ann" })
eve.ns.Net:Enqueue("CHANNEL", nil, "NS", BARRENS, fake.id, 1) -- Eve announces "Ann's" stone
Sim.run(5)
check(sentBy(ben, "SG", w) == 0, "an announcement from someone other than the author is ignored")
eve.ns.Net:SendPayload("WHISPER", "Ben Barrens", "SL", eve.ns.Codec.EncodeStone(Sim.stone("Eve-Forger", 1, BARRENS)))
Sim.run(5)
check(ben.ns.Store:Get(Sim.stone("Eve-Forger", 1, BARRENS).id) == nil, "a stone nobody asked for is ignored")

---------------------------------------------------------------------------
-- Changes made while offline go out once the channel is joined.
Sim.logoff(ann)
local offline = drop(ann, 2, BARRENS, { text = "left while offline" })
check(ann.ns.db.outbox[offline.id] == true, "an offline drop waits in the outbox")
ann.online = true
ann.ns.Net:Join()
Sim.runUntil(function() return ben.ns.Store:Get(offline.id) ~= nil end, 30, 0.1)
check(ben.ns.Store:Get(offline.id) ~= nil, "and reaches Ben after Ann reconnects")

---------------------------------------------------------------------------
-- Test stones are never announced.
w = #Sim.wire
local test = Sim.give(ann, Sim.stone("Ann-Author", 3, BARRENS, { localOnly = true }))
ann.ns.Store:MarkChanged(test.id)
Sim.run(3)
check(sentBy(ann, "NS", w) == 0 and ann.ns.db.outbox[test.id] == nil, "a local test stone isn't announced")

---------------------------------------------------------------------------
-- An author flooding announcements is capped per minute. (Wait out the
-- minute first: Ann's earlier announcements still count towards it.)
Sim.run(61)
w = #Sim.wire
for n = 10, 24 do drop(ann, n, BARRENS) end
Sim.run(40)
local fetched = sentBy(ben, "SG", w)
check(fetched == ben.ns.Sync.LIVE_PER_AUTHOR, ("Ben fetched %d of 15 (capped at %d per minute)"):format(fetched, ben.ns.Sync.LIVE_PER_AUTHOR))
check(Sim.stats.refused == 0 and Sim.stats.oversize == 0, "nothing throttled or oversized")
done()
