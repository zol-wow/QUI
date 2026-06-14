-- tests/unit/groupframes_aura_model_test.lua
-- Run: lua tests/unit/groupframes_aura_model_test.lua
local ns = {}
assert(loadfile("QUI_GroupFrames/groupframes/groupframes_aura_model.lua"))("QUI_GroupFrames", ns)
local Model = ns.QUI_GroupFramesAuraModel

local function test(name, fn) print(name); fn(); print("  ok") end

test("NewFilterStripElement defaults", function()
    local e = Model.NewFilterStripElement("HELPFUL")
    assert(e.mode == "filterStrip"); assert(e.auraType == "HELPFUL")
    assert(e.enabled == true); assert(type(e.id) == "string" and #e.id > 0)
    assert(e.classifications ~= nil)
end)

test("NewTrackedElement defaults", function()
    local e = Model.NewTrackedElement({ 774 }, "icon")
    assert(e.mode == "tracked"); assert(e.displayType == "icon")
    assert(e.spells[1] == 774); assert(e.onlyMine == false)
    assert(type(e.onlyMineSpells) == "table")
end)

test("Validate rejects unknown mode", function()
    assert(Model.Validate({ mode = "bogus" }) == false)
end)

test("Validate rejects tracked without spells", function()
    assert(Model.Validate({ mode = "tracked", spells = {}, displayType = "icon" }) == false)
end)

test("EffectiveOnlyMine: per-spell override beats default", function()
    local e = Model.NewTrackedElement({ 10060 }, "icon")
    e.onlyMine = true; e.onlyMineSpells = { [10060] = false }
    assert(Model.EffectiveOnlyMine(e, 10060) == false)
    assert(Model.EffectiveOnlyMine(e, 999) == true)
end)

test("Default seed = enabled + 2 filter strips", function()
    local seed = Model.DefaultElements()
    local strips = seed["*"]
    assert(#strips == 2)
    local kinds = {}
    for _, e in ipairs(strips) do kinds[e.auraType] = e end
    assert(kinds.HELPFUL and kinds.HARMFUL)
    assert(kinds.HELPFUL.enabled == false)
    assert(kinds.HARMFUL.enabled == true)
end)

test("ActiveElementsForSpec: spec bucket OVERRIDES '*' (either/or, not union)", function()
    local auras = { enabled = true, elements = {
        ["*"] = { { id = "d", enabled = true, mode = "filterStrip", auraType = "HARMFUL" },
                   { id = "off", enabled = false, mode = "filterStrip", auraType = "HELPFUL" } },
        [105] = { { id = "p", enabled = true, mode = "tracked", spells = { 774 }, displayType = "icon" } },
    } }
    -- spec 105 present -> ONLY its bucket (1), not 1+1 union
    local s105 = Model.ActiveElementsForSpec(auras, 105)
    assert(#s105 == 1 and s105[1].id == "p")
    -- spec 256 absent -> inherit "*" (1 enabled, "off" skipped)
    local s256 = Model.ActiveElementsForSpec(auras, 256)
    assert(#s256 == 1 and s256[1].id == "d")
end)

test("ActiveElementsForSpec: empty spec bucket = show nothing (override)", function()
    local auras = { enabled = true, elements = {
        ["*"] = { { id = "d", enabled = true, mode = "filterStrip", auraType = "HARMFUL" } },
        [105] = {},
    } }
    assert(#Model.ActiveElementsForSpec(auras, 105) == 0)
    assert(#Model.ActiveElementsForSpec(auras, 256) == 1)
end)

test("ActiveElementsForSpec: reuses + clears caller-supplied out (zero-alloc path)", function()
    local auras = { enabled = true, elements = {
        ["*"] = { { id = "a", enabled = true, mode = "filterStrip", auraType = "HARMFUL" },
                   { id = "b", enabled = true, mode = "filterStrip", auraType = "HELPFUL" } },
        [105] = { { id = "p", enabled = true, mode = "tracked", spells = { 774 }, displayType = "icon" } },
    } }
    local scratch = {}
    local r1 = Model.ActiveElementsForSpec(auras, 256, scratch) -- inherit "*" -> 2
    assert(r1 == scratch, "must return the same table when out is supplied")
    assert(#r1 == 2)
    -- Reuse with a smaller result: the stale 2nd entry must be cleared.
    local r2 = Model.ActiveElementsForSpec(auras, 105, scratch) -- spec 105 -> 1
    assert(r2 == scratch)
    assert(#r2 == 1 and r2[1].id == "p")
    assert(r2[2] == nil, "stale second entry must be cleared on reuse")
end)

test("PopulateElementMatches: reuses + clears caller-supplied out", function()
    local cache = { buffsBySpellID = { [100] = { auraInstanceID = 1 },
                                       [200] = { auraInstanceID = 2 } } }
    local scratch = {}
    local m1 = Model.PopulateElementMatches({ mode = "tracked", spells = { 100, 200 } }, cache, scratch)
    assert(m1 == scratch)
    assert(m1[100] and m1[200])
    -- Reuse with an element matching only one spell: stale key must clear.
    local m2 = Model.PopulateElementMatches({ mode = "tracked", spells = { 100 } }, cache, scratch)
    assert(m2 == scratch)
    assert(m2[100] ~= nil and m2[200] == nil, "stale spell 200 must be cleared on reuse")
end)

test("HasSpecOverride: present non-'*' bucket only", function()
    local els = { ["*"] = {}, [105] = {} }
    assert(Model.HasSpecOverride(els, 105) == true)
    assert(Model.HasSpecOverride(els, 256) == false)
    assert(Model.HasSpecOverride(els, "*") == false)
end)

test("EnableSpecOverride: copies '*' with fresh ids; DisableSpecOverride deletes", function()
    local auras = { elements = { ["*"] = {
        { id = "debuffs", enabled = true, mode = "filterStrip", auraType = "HARMFUL" },
    } } }
    Model.EnableSpecOverride(auras, 105)
    assert(type(auras.elements[105]) == "table" and #auras.elements[105] == 1)
    assert(auras.elements[105][1] ~= auras.elements["*"][1], "must be an independent copy")
    assert(auras.elements[105][1].id ~= "debuffs", "copy gets a fresh id")
    assert(auras.elements[105][1].auraType == "HARMFUL")
    -- idempotent: enabling again does not overwrite
    local kept = auras.elements[105]
    Model.EnableSpecOverride(auras, 105)
    assert(auras.elements[105] == kept)
    Model.DisableSpecOverride(auras, 105)
    assert(auras.elements[105] == nil)
end)

test("EnsureSeeded: drops empty spec buckets once (transition cleanup)", function()
    local auras = { elements = { ["*"] = { { id = "d" } }, [105] = {}, [256] = { { id = "x" } } } }
    Model.EnsureSeeded(auras)
    assert(auras.elements[105] == nil, "empty spec bucket dropped")
    assert(auras.elements[256] ~= nil, "non-empty spec bucket kept")
    assert(auras._specBucketsNormalized == true)
end)

test("PopulateElementMatches resolves tracked spells from cache", function()
    local cache = { buffsBySpellID = { [774] = { auraInstanceID = 1, spellId = 774 } }, debuffsBySpellID = {} }
    local el = { mode = "tracked", spells = { 774, 999 }, displayType = "icon" }
    local matches = Model.PopulateElementMatches(el, cache)
    assert(matches[774] ~= nil and matches[999] == nil)
end)

test("DefaultStripBucket: 2 strips with fixed ids, fresh table each call", function()
    local a = Model.DefaultStripBucket()
    local b = Model.DefaultStripBucket()
    assert(#a == 2)
    assert(a[1].id == "debuffs" and a[1].auraType == "HARMFUL" and a[1].enabled == true)
    assert(a[2].id == "buffs" and a[2].auraType == "HELPFUL" and a[2].enabled == false)
    assert(a ~= b and a[1] ~= b[1], "must return a fresh table each call")
end)

test("EnsureSeeded: fresh auras gets '*' strips + flag", function()
    local auras = { enabled = true }
    Model.EnsureSeeded(auras)
    assert(auras.elementsSeeded == true)
    assert(type(auras.elements) == "table" and #auras.elements["*"] == 2)
end)

test("EnsureSeeded: already-flagged is a no-op (no re-seed)", function()
    local auras = { enabled = true, elementsSeeded = true }
    Model.EnsureSeeded(auras)
    assert(auras.elements == nil, "flagged profile must not be seeded")
end)

test("EnsureSeeded: emptied bucket stays empty (deletion persists)", function()
    -- User deleted every strip last session, then flag was set.
    local auras = { enabled = true, elementsSeeded = true, elements = { ["*"] = {} } }
    Model.EnsureSeeded(auras)
    assert(#auras.elements["*"] == 0, "must NOT resurrect deleted strips")
end)

test("EnsureSeeded: existing user strips preserved, not overwritten", function()
    local mine = { id = "debuffs", enabled = false, mode = "filterStrip", auraType = "HARMFUL" }
    local auras = { enabled = true, elements = { ["*"] = { mine } } }
    Model.EnsureSeeded(auras)
    assert(auras.elementsSeeded == true)
    assert(#auras.elements["*"] == 1 and auras.elements["*"][1] == mine)
end)

test("EnsureSeeded: ignores non-table input", function()
    Model.EnsureSeeded(nil)  -- must not error
end)

test("EnsureSeeded: backfills nil element ids (render keys on element.id)", function()
    -- Legacy/imported spec bucket with an id-less tracked element -> render
    -- reconciliation did `current[element.id] = true` and threw "table index is nil".
    local idless = { mode = "tracked", spells = { 31821 }, displayType = "icon" }
    local auras = { enabled = true, elementsSeeded = true, elements = { [250] = { idless } } }
    Model.EnsureSeeded(auras)
    assert(type(idless.id) == "string" and idless.id ~= "", "nil id must be healed")
end)

test("EnsureSeeded: backfill is one-time (own flag) and assigns unique ids", function()
    local a = { mode = "tracked", spells = { 1 } }
    local b = { mode = "tracked", spells = { 2 } }
    local auras = { enabled = true, elementsSeeded = true, elements = { ["*"] = { a, b } } }
    Model.EnsureSeeded(auras)
    assert(auras._elementIDsBackfilled == true)
    assert(a.id ~= nil and b.id ~= nil and a.id ~= b.id, "ids must be unique")
    local firstA = a.id
    Model.EnsureSeeded(auras)  -- second call must not re-touch
    assert(a.id == firstA, "backfill must not re-run")
end)

test("EnsureSeeded: duplicate ids are split", function()
    local a = { id = "e1", mode = "tracked", spells = { 1 } }
    local b = { id = "e1", mode = "tracked", spells = { 2 } }
    local auras = { enabled = true, elementsSeeded = true, elements = { ["*"] = { a, b } } }
    Model.EnsureSeeded(auras)
    assert(a.id ~= b.id, "shared id must be split so render keys stay distinct")
end)

print("ALL PASS")
