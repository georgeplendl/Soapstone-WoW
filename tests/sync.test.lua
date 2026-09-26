-- Zone sync end to end, on the simulated WoW Forever (lib/wowsim.lua):
-- every player runs the real Core/Identity/Store/Sketch/Codec/Net/Sync code.
dofile(TESTS .. "/lib/harness.lua")
format = string.format
local Sim = dofile(TESTS .. "/lib/wowsim.lua")
Sim.ROOT = ROOT
math.randomseed(7)

local BARRENS, BLUFF, DUROTAR = 1413, 1456, 1411

local function lastPrint(c)
	return c.printed[#c.printed] or ""
end

local function finished(c)
	return function() return c.ns.Sync:Current() == nil and c.ns.Sync.lastResult ~= nil end
end

-- Everyone logs in; the channel is joined ~8 s later.
local zug = Sim.client("Zug", "Zug")
local osha = Sim.client("Osha", "Compliant")
Sim.run(10)
check(zug.joined and osha.joined, "both joined the hidden channel")

---------------------------------------------------------------------------
-- 1. A newcomer pulls a zone from one player.
local sun = zug.ns.Sketch.Pack(zug.ns.Sketch.Sun())
for n = 1, 20 do Sim.give(zug, Sim.stone("Zug-Zug", n, BARRENS)) end
for n = 21, 25 do Sim.give(zug, Sim.stone("Zug-Zug", n, BARRENS, { sketch = sun })) end
zug.ns.Sync:OnZone(BLUFF)
local wireStart = #Sim.wire
osha.ns.Sync:OnZone(BARRENS)
local took = Sim.runUntil(finished(osha), 300)
check(took ~= nil, "sync finished")
check(Sim.count(osha, BARRENS) == 25, "Osha now has all 25 Barrens stones (" .. Sim.count(osha, BARRENS) .. ")")
check(osha.ns.Store:ZoneDigest(BARRENS) == zug.ns.Store:ZoneDigest(BARRENS), "and the same zone fingerprint as Zug")
local got = osha.ns.Store:Get(Sim.stone("Zug-Zug", 3, BARRENS).id)
check(got and got.text == "Stone 3 by Zug-Zug" and got.author == "Zug Zug", "text and author name came through")
check(got and got.verified == true and got.via == "Zug-Zug", "marked first-hand from the author")
check(got and got.heard == nil and not osha.ns.Store.IsMine(got), "arrives unread, and not as Osha's")
local sk = osha.ns.Store:Get(Sim.stone("Zug-Zug", 22, BARRENS).id)
check(sk and sk.sketch and osha.ns.Sketch.Unpack(sk.sketch) ~= nil, "sketches arrive whole")
check(#osha.ns.Store:Near({ instance = 1, wx = -1400 + 21, wy = -3700 + 9 }, 5) >= 1, "arrivals are on the minimap index")
check(lastPrint(osha):find("25 new stones arrived for The Barrens") ~= nil, "Osha is told: " .. lastPrint(osha))
check(Sim.stats.refused == 0, "no message ever hit AddonMessageThrottle")
check(Sim.stats.oversize == 0, "no message over 255 bytes")
local used = #Sim.wire - wireStart
vprint(("     25 stones (5 sketches) in %.1f s over %d messages; types:"):format(took or -1, used))
for kind, n in pairs(Sim.stats.byType) do vprint(("       %-8s %d"):format(kind, n)) end
check(took and took < 90, ("took %.0f s (budget ~1 msg/s)"):format(took or -1))

---------------------------------------------------------------------------
-- 2. Already up to date: one question, no answer, nothing else.
wireStart = #Sim.wire
osha.ns.Sync.lastResult = nil
osha.ns.Sync:Start(BARRENS, true)
Sim.runUntil(finished(osha), 30)
check(Sim.countWire("ZQ", wireStart) == 1 and #Sim.wire - wireStart == 1, "an up-to-date zone costs one broadcast")
check(osha.ns.Sync.lastResult.added == 0, "and brings nothing")

---------------------------------------------------------------------------
-- 3. Three players with identical stones: normally only one answers.
local tb = {}
for n = 1, 10 do tb[n] = Sim.stone("Moon-Watcher", n, BLUFF) end
local helpers = { Sim.client("Ada", "One"), Sim.client("Bo", "Two"), Sim.client("Cy", "Three") }
for _, h in ipairs(helpers) do
	for _, s in ipairs(tb) do Sim.give(h, s, "Moon-Watcher") end
	h.ns.Sync:OnZone(DUROTAR)
end
local newbie = Sim.client("New", "Comer")
Sim.run(10)
wireStart = #Sim.wire
newbie.ns.Sync:OnZone(BLUFF)
Sim.runUntil(finished(newbie), 120)
local offers = Sim.countWire("ZH", wireStart)
check(offers >= 1 and offers <= 2, "identical holders mostly stay quiet (" .. offers .. " offer(s) from 3 + Zug)")
check(Sim.count(newbie, BLUFF) >= 10, "newcomer got Thunder Bluff's stones")
local relayed = newbie.ns.Store:Get(tb[1].id)
check(relayed and relayed.verified == false and relayed.via ~= "Moon-Watcher", "relayed stones are marked unverified")

---------------------------------------------------------------------------
-- 4. The chosen player logs off mid-transfer: retry with someone else.
local left = { Sim.client("Hal", "Gone"), Sim.client("Ivy", "Stays") }
local many = {}
for n = 1, 30 do many[n] = Sim.stone("Old-Timer", n, DUROTAR) end
for _, p in ipairs(left) do
	for _, s in ipairs(many) do Sim.give(p, s, "Old-Timer") end
	p.ns.Sync:OnZone(BARRENS)
end
local jo = Sim.client("Jo", "Walker")
Sim.run(10)
jo.ns.Sync:OnZone(DUROTAR)
local job
Sim.runUntil(function()
	job = jo.ns.Sync:Current()
	return job and job.stage == "fetch"
end, 60, 0.1)
check(job and job.stage == "fetch", "Jo started fetching from someone")
local first = Sim.find(job.peer)
Sim.run(3)
Sim.logoff(first)
Sim.runUntil(function() return Sim.count(jo, DUROTAR) == 30 end, 180)
check(Sim.count(jo, DUROTAR) == 30, "Jo still ended up with all 30 (" .. Sim.count(jo, DUROTAR) .. ")")
check(#jo.systemShown == 0, "the 'No player named…' line was hidden")
check(jo.ns.Sync.retries >= 1, "a retry was needed and happened")

---------------------------------------------------------------------------
-- 5. Edits and deletions follow the author, not relays.
local kai = Sim.client("Kai", "Author")
local lee = Sim.client("Lee", "Relay")
local mo = Sim.client("Mo", "Reader")
Sim.run(10)
local s1 = Sim.stone("Kai-Author", 1, DUROTAR, { text = "original" })
local s2 = Sim.stone("Kai-Author", 2, DUROTAR, { text = "to be deleted" })
for _, s in ipairs({ s1, s2 }) do
	Sim.give(kai, s); Sim.give(lee, s, "Kai-Author"); Sim.give(mo, s, "Kai-Author")
end
-- Lee forges an edit of Kai's stone and holds a tombstone for a stone Mo never saw.
local forged = Sim.give(lee, Sim.stone("Kai-Author", 1, DUROTAR, { text = "forged!", v = 2 }), "Kai-Author")
local ghost = Sim.stone("Kai-Author", 3, DUROTAR)
lee.ns.Store:Put({ id = ghost.id, v = 2, deleted = true, deletedAt = Sim.now(), zone = DUROTAR, authorKey = "Kai-Author" })
Sim.only(lee, mo) -- Kai is away; Lee is the only one with Durotar news
local wire5 = #Sim.wire
mo.ns.Sync:OnZone(DUROTAR)
Sim.runUntil(finished(mo), 120)
local function explain(c, from)
	local r = c.ns.Sync.lastResult
	vprint("     " .. c.name .. " was told: " .. table.concat(c.printed, " | "))
	vprint(r and format("     result: +%d, %d updated, %d removed, %d rejected, problem: %s",
		r.added, r.updated, r.deleted, r.rejected, tostring(r.lastProblem)) or "     no result")
	for i = from + 1, #Sim.wire do
		local w = Sim.wire[i]
		vprint(format("       %7.2f %-12s %-7s %-14s %s", w.at - Sim.wire[from + 1].at, w.from, w.dist,
			tostring(w.target or ""), w.msg:sub(1, 70)))
	end
end
explain(mo, wire5)
check(mo.ns.Store:Get(s1.id).text == "original", "a relayed edit is refused (Mo keeps the original)")
check(mo.ns.Sync.lastResult.rejected >= 1, "and counted as rejected")
local tomb = mo.ns.Store:Get(ghost.id)
check(tomb and tomb.deleted, "a relayed tombstone for an unseen stone is kept (blocks resurrection)")

-- Now Kai comes back, really edits s1 and deletes s2; Lee leaves.
Sim.logoff(lee)
kai.online = true
kai.ns.Net:Join()
Sim.run(3)
local real = kai.ns.Store:Get(s1.id)
real.text, real.v, real.edited = "edited by Kai", 2, Sim.now()
kai.ns.Store:Tombstone(kai.ns.Store:Get(s2.id))
mo.ns.Sync.lastResult = nil
mo.ns.Sync:Start(DUROTAR, true)
Sim.runUntil(finished(mo), 120)
check(mo.ns.Store:Get(s1.id).text == "edited by Kai", "a first-hand edit from the author is accepted")
check(mo.ns.Store:Get(s2.id).deleted == true, "a first-hand deletion removes the stone")
local stillIndexed = false
for _, s in ipairs(mo.ns.Store:Near({ instance = 1, wx = -500 + 14, wy = -4500 + 6 }, 3)) do
	if s.id == s2.id then stillIndexed = true end
end
check(not stillIndexed, "and takes it off the minimap")

-- Your own stones are never overwritten by someone else's copy.
local mine = Sim.stone("Mo-Reader", 1, DUROTAR, { text = "mine" })
Sim.give(mo, mine)
Sim.give(kai, Sim.stone("Mo-Reader", 1, DUROTAR, { text = "not yours", v = 5 }), "Mo-Reader")
mo.ns.Sync.lastResult = nil
mo.ns.Sync:Start(DUROTAR, true)
Sim.runUntil(finished(mo), 120)
check(mo.ns.Store:Get(mine.id).text == "mine" and mo.ns.Store:Get(mine.id).v == 1, "own stone untouched by a 'newer' copy")

---------------------------------------------------------------------------
-- 6. Retail and Forever never mix, even on one server.
local retail = Sim.client("Rae", "Retail", { build = "11.2.5" })
local fresh = Sim.client("Fay", "Fresh")
Sim.run(10)
Sim.only(retail, fresh)
for n = 1, 5 do Sim.give(retail, Sim.stone("Rae-Retail", n, BARRENS)) end
retail.ns.Sync:OnZone(BARRENS)
fresh.ns.Sync:OnZone(BARRENS)
Sim.runUntil(finished(fresh), 60)
check(Sim.count(fresh, BARRENS) == 0, "a Forever player gets nothing from a Retail player")
check(retail.ns.Store:ZoneDigest(BARRENS) ~= fresh.ns.Store:ZoneDigest(BARRENS), "(the Retail player did have stones)")

---------------------------------------------------------------------------
-- 7. Local test stones never leave your machine.
local tess = Sim.client("Tess", "Tester")
local quinn = Sim.client("Quinn", "Asks")
Sim.run(10)
Sim.only(tess, quinn)
Sim.give(tess, Sim.stone("Tess-Tester", 1, BLUFF))
Sim.give(tess, Sim.stone("Tess-Tester", 2, BLUFF, { localOnly = true }))
tess.ns.Sync:OnZone(BARRENS)
quinn.ns.Sync:OnZone(BLUFF)
Sim.runUntil(finished(quinn), 60)
check(quinn.ns.Store:Get(Sim.stone("Tess-Tester", 1, BLUFF).id) ~= nil, "a real stone is shared")
check(quinn.ns.Store:Get(Sim.stone("Tess-Tester", 2, BLUFF).id) == nil, "the local test stone is not")

---------------------------------------------------------------------------
-- 8. Two players hold different stones for a zone: one sync gets both sets.
local east = Sim.client("Eve", "East")
local west = Sim.client("Wes", "West")
local both = Sim.client("Bea", "Both")
Sim.run(10)
Sim.only(east, west, both)
for n = 1, 6 do Sim.give(east, Sim.stone("Eve-East", n, DUROTAR)) end
for n = 1, 4 do Sim.give(west, Sim.stone("Wes-West", n, DUROTAR)) end
both.ns.Sync:OnZone(DUROTAR)
Sim.runUntil(finished(both), 120)
check(Sim.count(both, DUROTAR) == 10, "one sync pulled from both players (" .. Sim.count(both, DUROTAR) .. " of 10)")
check(both.ns.Sync.lastResult.peers == 2, "by moving on to the second offer")

check(Sim.stats.refused == 0 and Sim.stats.oversize == 0, "whole run: nothing throttled, nothing oversized")
done()
