-- /soap version text: ns.VersionString with and without BuildInfo.lua.
dofile(TESTS .. "/lib/harness.lua")
format = string.format
local stubFrame = setmetatable({}, { __index = function() return function() end end })
function CreateFrame() return stubFrame end
SlashCmdList = {}
C_AddOns = { GetAddOnMetadata = function(_, field) return field == "Version" and "0.2.0" or nil end }

local ns = {}
assert(loadfile(ROOT .. "/Core.lua"))("Soapstone", ns)

check(ns.VersionString() == "0.2.0", "no build info: just the version")

ns.BUILD = { branch = "ratings", commit = "16dd7e0", date = "2026-09-25 18:02" }
check(ns.VersionString() == "0.2.0 (branch ratings @ 16dd7e0, 2026-09-25 18:02)", "dev checkout: branch, commit, date")

ns.BUILD = { branch = "v0.3.0", commit = "abc1234", date = "2026-10-01 12:00", release = true }
check(ns.VersionString() == "0.2.0 (release v0.3.0 @ abc1234, 2026-10-01 12:00)", "release zip says so")

ns.BUILD = { branch = "detached", commit = "", date = "" }
check(ns.VersionString() == "0.2.0 (branch detached)", "missing commit/date are left out")

ns.BUILD = { branch = "" }
check(ns.VersionString() == "0.2.0", "an empty branch is ignored")

-- The generated file itself is valid Lua that sets ns.BUILD.
local generated = 'local _, ns = ...\nns.BUILD = { branch = "fix \\"quotes\\"", commit = "1", date = "d" }\n'
local chunk = assert(load(generated))
local target = {}
chunk("Soapstone", target)
check(target.BUILD and target.BUILD.branch == 'fix "quotes"', "escaped quotes in a branch name load fine")

done()
