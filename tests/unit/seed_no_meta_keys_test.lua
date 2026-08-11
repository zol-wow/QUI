-- tests/unit/seed_no_meta_keys_test.lua
-- Run: lua tests/unit/seed_no_meta_keys_test.lua
-- The shipped seed (decoded from importstrings/starter_profile.lua — the
-- string is generated pre-stripped) must contain ZERO "_"-prefixed keys at
-- ANY depth (the generator contract), and no orphan cdmCustom_/glow
-- satellites for containers that do not exist in the seed's own
-- ncdm.containers.

local env = dofile("tools/_addon_env.lua")
local ns = env.LoadCore()
local seed = assert(ns.GetNewProfileSeed and ns.GetNewProfileSeed(), "decoded seed missing")

local violations = {}
local function walk(t, path)
    for k, v in pairs(t) do
        if type(k) == "string" and k:sub(1, 1) == "_" then
            violations[#violations + 1] = path .. "." .. k
        end
        if type(v) == "table" then
            walk(v, path .. "." .. tostring(k))
        end
    end
end
walk(seed, "seed")
assert(#violations == 0,
    "meta keys leaked into the seed:\n  " .. table.concat(violations, "\n  "))

-- No orphan cdmCustom_ anchors.
local live = {}
local containers = seed.ncdm and seed.ncdm.containers or {}
for key in pairs(containers) do live[key] = true end
local anchors = seed.frameAnchoring or {}
for k in pairs(anchors) do
    local key = type(k) == "string" and k:match("^cdmCustom_(.+)$")
    assert(not key or live[key],
        "orphan anchor in seed: " .. tostring(k))
end

print("OK seed_no_meta_keys_test")
