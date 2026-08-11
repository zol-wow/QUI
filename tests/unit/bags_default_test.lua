-- Regression guard: QUI_Bags bags.enabled defaults.
-- The new-profile seed (decoded from importstrings/starter_profile.lua by
-- core/new_profile_defaults.lua) must have bags.enabled = true so
-- newly-created profiles get the bag UI on without user action.
-- core/defaults.lua (live AceDB fallback layer) must keep bags.enabled = false so
-- existing profiles that never wrote the key are NOT retroactively changed.

local env = dofile("tools/_addon_env.lua")
local ns = env.LoadCore()

local newProfileSeed = ns.GetNewProfileSeed and ns.GetNewProfileSeed()
assert(type(newProfileSeed) == "table", "decoded new-profile seed must be a table")
assert(type(newProfileSeed.bags) == "table",
    "new-profile seed bags must be a table")

-- PRIMARY assertion: new profiles get bags ON.
assert(newProfileSeed.bags.enabled == true,
    "new-profile seed: bags.enabled must be true (new profiles get bags on)")

-- GUARD assertion: live AceDB default stays false so existing profiles are untouched.
local liveBags = ns.defaults and ns.defaults.profile and ns.defaults.profile.bags
assert(type(liveBags) == "table", "live defaults must have a bags subtable")
assert(liveBags.enabled == false,
    "live AceDB default: bags.enabled must remain false (existing profiles untouched)")

print("PASS: new-profile seed bags.enabled == true; live default bags.enabled == false")
