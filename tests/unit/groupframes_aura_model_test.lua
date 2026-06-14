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

test("ActiveElementsForSpec merges '*' and spec bucket; skips disabled", function()
    local auras = { enabled = true, elements = {
        ["*"] = { { id = "d", enabled = true, mode = "filterStrip", auraType = "HARMFUL" },
                   { id = "off", enabled = false, mode = "filterStrip", auraType = "HELPFUL" } },
        [105] = { { id = "p", enabled = true, mode = "tracked", spells = { 774 }, displayType = "icon" } },
    } }
    assert(#Model.ActiveElementsForSpec(auras, 105) == 2)
    assert(#Model.ActiveElementsForSpec(auras, 256) == 1)
end)

test("PopulateElementMatches resolves tracked spells from cache", function()
    local cache = { buffsBySpellID = { [774] = { auraInstanceID = 1, spellId = 774 } }, debuffsBySpellID = {} }
    local el = { mode = "tracked", spells = { 774, 999 }, displayType = "icon" }
    local matches = Model.PopulateElementMatches(el, cache)
    assert(matches[774] ~= nil and matches[999] == nil)
end)

print("ALL PASS")
