-- tests/unit/nameplates_aura_elements_store_test.lua
-- Run: lua tests/unit/nameplates_aura_elements_store_test.lua
--
-- NPAuras.ResolveElements seeds auras.elements["*"] exactly once (behind
-- E.EnsureSeeded's elementsSeeded flag) and returns only the enabled
-- elements. Element lists are never declared in core/defaults.lua, because
-- AceDB copyDefaults re-fills deleted array indices (buffborders.lua:186-189
-- states the same rule) -- so seeding has to happen lazily, on demand, and
-- exactly once, or a user's deliberate deletion would silently come back.

local function fail(msg)
    print("FAIL: nameplates_aura_elements_store_test - " .. msg)
    os.exit(1)
end

-- Minimal ns, reused across every loadfile call below exactly like
-- tests/unit/nameplates_preview_test.lua does — in real WoW, QUI_Nameplates'
-- namespace is metatable-proxied to the QUI core namespace by
-- QUI_Nameplates/bootstrap.lua (reads/writes land in the SAME table); here
-- a single shared `ns` table stands in for that bridge, so ns.AuraElements set
-- by core/aura_elements.lua below is directly visible to plate_auras.lua.
local ns = {
    Helpers = {
        -- plate_auras.lua reads Helpers.IsSecretValue at module-load time
        -- (local IsSecretValue = Helpers.IsSecretValue); shared.lua does the
        -- same. Neither is called by the two functions under test.
        IsSecretValue = function() return false end,
    },
}

-- core/aura_elements.lua is pure Lua (its own header: "no frame APIs, fully
-- unit-testable headless") and needs nothing beyond (ADDON_NAME, ns).
assert(loadfile("core/aura_elements.lua"))("QUI", ns)

-- shared.lua creates ns.QUI_Nameplates (NP) and must load before
-- plate_auras.lua, which nil-guards on it existing.
assert(loadfile("QUI_Nameplates/nameplates/shared.lua"))("QUI_Nameplates", ns)
assert(loadfile("QUI_Nameplates/nameplates/plate_auras.lua"))("QUI_Nameplates", ns)

local NP = ns.QUI_Nameplates
if not NP then fail("plate_auras must export ns.QUI_Nameplates") end
if type(NP.Auras) ~= "table" then fail("plate_auras must export NP.Auras") end
if type(NP.Auras.DefaultNameplateBucket) ~= "function" then fail("must export DefaultNameplateBucket") end
if type(NP.DefaultNameplateBucket) ~= "function" then fail("must alias NP.DefaultNameplateBucket") end
if type(NP.Auras.ResolveElements) ~= "function" then fail("must export ResolveElements") end

local Auras = NP.Auras
NP.Extras = { GetContext = function() return { instanceKind = "world" } end }

local function test(name, fn) print(name); fn(); print("  ok") end

test("the default bucket seeds exactly three filterStrip elements", function()
    local bucket = Auras.DefaultNameplateBucket()
    if #bucket ~= 3 then fail("expected exactly 3 seeded elements, got " .. #bucket) end
    for i = 1, 3 do
        if bucket[i].mode ~= "filterStrip" then
            fail("element " .. i .. " must be a filterStrip, got " .. tostring(bucket[i].mode))
        end
    end
end)

test("debuffs and cc seed HARMFUL, buffs seeds HELPFUL", function()
    local bucket = Auras.DefaultNameplateBucket()
    if bucket[1].auraType ~= "HARMFUL" then fail("element 1 (debuffs) must seed HARMFUL") end
    if bucket[2].auraType ~= "HELPFUL" then fail("element 2 (buffs) must seed HELPFUL") end
    if bucket[3].auraType ~= "HARMFUL" then fail("element 3 (cc) must seed HARMFUL") end
end)

test("ResolveElements seeds the bucket into auras.elements['*'] on first call", function()
    local settings = { auras = { enabled = true, elements = {} } }
    local out = Auras.ResolveElements(settings)
    if #out ~= 3 then fail("expected 3 active elements from a fresh bucket, got " .. #out) end
    local bucket = settings.auras.elements["*"]
    if type(bucket) ~= "table" or #bucket ~= 3 then
        fail("auras.elements['*'] must hold the seeded 3-element bucket, got "
            .. tostring(bucket and #bucket))
    end
end)

test("ResolveElements returns only the enabled elements", function()
    local settings = { auras = { enabled = true, elements = {} } }
    Auras.ResolveElements(settings)
    settings.auras.elements["*"][2].enabled = false
    local out = Auras.ResolveElements(settings)
    if #out ~= 2 then fail("disabling one element must drop it from ResolveElements, got " .. #out) end
end)

test("seeding is once-only and survives user deletion", function()
    local settings = { auras = { enabled = true, elements = {} } }
    Auras.ResolveElements(settings)
    settings.auras.elements["*"] = {}
    local out = Auras.ResolveElements(settings)
    if #out ~= 0 then fail("re-seeding after user deletion is the AceDB array-defaults bug this guards") end
    if #settings.auras.elements["*"] ~= 0 then
        fail("the emptied bucket itself must stay empty, not just the filtered result")
    end
end)

test("elements are reused by reference, not rebuilt every call", function()
    local settings = { auras = { enabled = true, elements = {} } }
    local first = Auras.ResolveElements(settings)[1]
    local second = Auras.ResolveElements(settings)[1]
    if first ~= second then fail("ResolveElements must return the SAME element object across calls") end
end)

print("OK: nameplates_aura_elements_store_test")
