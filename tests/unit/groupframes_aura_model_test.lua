-- tests/unit/groupframes_aura_model_test.lua
-- Run: lua5.1 tests/unit/groupframes_aura_model_test.lua
--
-- The GF element model moved to core/aura_elements.lua (ns.AuraElements, shared
-- by every aura surface). groupframes_aura_model.lua is now a COMPATIBILITY
-- SHIM: a `setmetatable({}, { __index = E })` table that delegates every
-- constructor / seed / override method to core, plus its own GF-only
-- PopulateElementMatches (the preview-fake tracked-match populator). The full
-- model behaviour is covered by aura_elements_model_test.lua; these tests only
-- pin that the shim delegates and that PopulateElementMatches works.
local env = dofile("tools/_addon_env.lua")
local ns = env.LoadCore()          -- populates ns.AuraElements (E)
assert(ns.AuraElements, "core aura_elements must load before the shim")
env.LoadAddonFile("QUI_GroupFrames/groupframes/groupframes_aura_model.lua", "QUI_GroupFrames", ns)
local Model = ns.QUI_GroupFramesAuraModel
local E = ns.AuraElements

local function test(name, fn) print(name); fn(); print("  ok") end

test("shim delegates to core via __index (not a copy)", function()
    assert(getmetatable(Model), "shim must have a metatable")
    -- Methods that live on E are reachable through the shim...
    assert(Model.NewFilterStripElement == E.NewFilterStripElement)
    assert(Model.ActiveElementsForSpec == E.ActiveElementsForSpec)
    -- ...but the shim owns PopulateElementMatches (not on E) and wraps
    -- EnsureSeeded (legacy one-arg signature threads the GF default bucket).
    assert(E.PopulateElementMatches == nil, "PopulateElementMatches is GF-shim-only")
    assert(type(Model.PopulateElementMatches) == "function")
    assert(rawget(Model, "EnsureSeeded") ~= nil, "shim wraps EnsureSeeded (legacy signature)")
end)

test("legacy one-arg EnsureSeeded threads the GF default bucket", function()
    -- The editor/preview/schema call EnsureSeeded(auras) with NO bucket fn and
    -- may run before the runtime seeds; the shim must thread the GF defaults so
    -- a fresh profile is not latched with an EMPTY '*' bucket. The bucket is
    -- SHIM-OWNED (always-loaded file): no Options-side module may be required,
    -- or an Options-disabled install would latch empty and permanently lose
    -- the shipped strips (Task 4 review regression).
    assert(ns.QUI_GroupFramesAuraDefaults == nil,
        "test precondition: Options-side defaults must NOT be loaded here")
    local auras = { enabled = true }
    Model.EnsureSeeded(auras)
    assert(auras.elementsSeeded == true)
    assert(type(auras.elements) == "table" and #auras.elements["*"] == 3,
        "one-arg EnsureSeeded must seed the GF default bucket, not an empty one")
    assert(auras.elements["*"][1].id == "debuffs" and auras.elements["*"][2].id == "buffs"
        and auras.elements["*"][3].id == "defensives")
    -- One-arg = unknown surface: defensives seeds DISABLED (conservative).
    assert(auras.elements["*"][3].enabled == false)
    -- Normalized shape (core schema) straight from the shim's bucket.
    assert(type(auras.elements["*"][1].duration) == "table"
        and auras.elements["*"][1].duration.anchor == "BOTTOM")
    assert(auras.elements["*"][1].rightClickCancel == true)
end)

test("shim owns DefaultStripBucket (fresh table each call)", function()
    local a, b = Model.DefaultStripBucket(), Model.DefaultStripBucket()
    assert(a ~= b and a[1] ~= b[1], "must return a fresh table each call")
    assert(rawget(Model, "DefaultStripBucket") ~= nil, "bucket is shim-owned, not on E")
    assert(E.DefaultStripBucket == nil, "core model must stay surface-agnostic")
end)

test("two-arg EnsureSeeded passes the caller's bucket through unchanged", function()
    local auras = { enabled = true }
    Model.EnsureSeeded(auras, function()
        return { { id = "custom", enabled = true, mode = "filterStrip", auraType = "HELPFUL" } }
    end)
    assert(#auras.elements["*"] == 1 and auras.elements["*"][1].id == "custom")
end)

test("delegated constructors still build valid elements", function()
    local e = Model.NewFilterStripElement("HELPFUL")
    assert(e.mode == "filterStrip" and e.auraType == "HELPFUL")
    assert(type(e.id) == "string" and #e.id > 0)
    local t = Model.NewTrackedElement({ 774 }, "icon")
    assert(t.mode == "tracked" and t.displayType == "icon" and t.spells[1] == 774)
    assert(Model.NewMissingRaidBuffElement().mode == "missingRaidBuff")
end)

test("delegated ActiveElementsForSpec: spec bucket OVERRIDES '*'", function()
    local auras = { enabled = true, elements = {
        ["*"] = { { id = "d", enabled = true, mode = "filterStrip", auraType = "HARMFUL" },
                   { id = "off", enabled = false, mode = "filterStrip", auraType = "HELPFUL" } },
        [105] = { { id = "p", enabled = true, mode = "tracked", spells = { 774 }, displayType = "icon" } },
    } }
    local s105 = Model.ActiveElementsForSpec(auras, 105)
    assert(#s105 == 1 and s105[1].id == "p")
    local s256 = Model.ActiveElementsForSpec(auras, 256)
    assert(#s256 == 1 and s256[1].id == "d")
end)

test("delegated EnableSpecOverride / DisableSpecOverride", function()
    -- generated-form id ("e<N>") re-keys on clone; FIXED semantic ids
    -- ("defensives"/"encounterBoss") are preserved per-bucket — see
    -- aura_elements_model_test.lua for the fixed-id contract.
    local auras = { elements = { ["*"] = {
        { id = "e3", enabled = true, mode = "filterStrip", auraType = "HARMFUL" },
    } } }
    Model.EnableSpecOverride(auras, 105)
    assert(type(auras.elements[105]) == "table" and #auras.elements[105] == 1)
    assert(auras.elements[105][1].id ~= "e3", "generated id re-keyed fresh")
    Model.DisableSpecOverride(auras, 105)
    assert(auras.elements[105] == nil)
end)

test("PopulateElementMatches: reuses + clears caller-supplied out", function()
    local cache = { buffsBySpellID = { [100] = { auraInstanceID = 1 },
                                       [200] = { auraInstanceID = 2 } } }
    local scratch = {}
    local m1 = Model.PopulateElementMatches({ mode = "tracked", spells = { 100, 200 } }, cache, scratch)
    assert(m1 == scratch)
    assert(m1[100] and m1[200])
    local m2 = Model.PopulateElementMatches({ mode = "tracked", spells = { 100 } }, cache, scratch)
    assert(m2 == scratch)
    assert(m2[100] ~= nil and m2[200] == nil, "stale spell 200 must be cleared on reuse")
end)

test("PopulateElementMatches resolves tracked spells from buff+debuff caches", function()
    local cache = { buffsBySpellID = { [774] = { auraInstanceID = 1, spellId = 774 } },
                    debuffsBySpellID = { [999] = { auraInstanceID = 2, spellId = 999 } } }
    local m = Model.PopulateElementMatches({ mode = "tracked", spells = { 774, 999, 42 } }, cache)
    assert(m[774] ~= nil and m[999] ~= nil and m[42] == nil)
end)

test("PopulateElementMatches: non-tracked mode returns empty", function()
    local m = Model.PopulateElementMatches({ mode = "filterStrip", spells = { 1 } }, { buffsBySpellID = { [1] = {} } })
    assert(next(m) == nil, "filterStrip elements have no tracked matches")
end)

-- Shim SOURCE-TEXT contract (mirrors groupframes_auras_container_test): the file
-- must be a delegate, not a re-declaration of the moved model.
local function readAll(path)
    local f = assert(io.open(path, "rb")); local s = f:read("*a"); f:close(); return (s:gsub("\r\n", "\n"))
end
local shimSrc = readAll("QUI_GroupFrames/groupframes/groupframes_aura_model.lua")
test("shim source: setmetatable delegate, PopulateElementMatches kept, model NOT re-declared", function()
    assert(shimSrc:find("setmetatable({}, { __index = E })", 1, true), "must delegate via __index to E")
    assert(shimSrc:find("function Model.PopulateElementMatches", 1, true), "keeps the GF preview populator")
    assert(shimSrc:find("function Model.NewFilterStripElement", 1, true) == nil, "must NOT re-declare the moved model")
    assert(shimSrc:find("function Model.DefaultStripBucket", 1, true) ~= nil,
        "DefaultStripBucket must be SHIM-owned (always-loaded) so the runtime seed can never latch empty")
end)

-- Wave 4 Task 2d: dedupeDefensives had zero runtime consumers (re-verified
-- repo-wide) and is removed from every LIVE seed, including this shim's
-- shipped GF default strip bucket. Stores that already carry the stale key
-- keep it (absent-key convention tolerates residue — no migration writes
-- here), but nothing should mint a NEW instance of it going forward.
test("shim source: DefaultStripBucket no longer seeds dedupeDefensives", function()
    assert(shimSrc:find("dedupeDefensives", 1, true) == nil, "dedupeDefensives must not be re-seeded")
end)

print("ALL PASS")
