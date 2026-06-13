-- tests/unit/bags_corner_widgets_test.lua
-- Run: lua tests/unit/bags_corner_widgets_test.lua
-- TDD for Bags.CornerWidgets.Select (pure: ctx in, payload out).
--   widgets: quantity / item_level / junk / equipment_set / binding /
--            expansion; "none"/unknown ids fall through; primary→fallback.

local ns = {
    Helpers = { GetGeneralFont = function() return "font" end },
}
assert(loadfile("QUI_Bags/bags/views/corner_widgets.lua"))("QUI", ns)
local CW = ns.Bags.CornerWidgets
assert(CW, "corner_widgets.lua must publish Bags.CornerWidgets")

-- quality-color shim (corner text coloring routes through ItemButtons)
ns.Bags.ItemButtons = { GetQualityColor = function() return 0.1, 0.2, 0.3 end }

local function ctx(over)
    local c = {
        entry = { count = 5, quality = 3 },
        details = { ilvl = 480, equipLoc = "INVTYPE_HEAD", isEquippable = true,
                    bindType = 2, isBound = false, expacID = 9 },
        isJunk = false,
        inSet = false,
        qualityColorText = false,
    }
    for k, v in pairs(over or {}) do c[k] = v end
    return c
end

-- Test 1: quantity — count > 1 shows, count 1 falls through
local p = CW.Select("quantity", nil, ctx())
assert(p and p.text == "5", "count 5 must render '5'")
p = CW.Select("quantity", nil, ctx({ entry = { count = 1, quality = 3 } }))
assert(p == nil, "count 1 must not render a quantity")

-- Test 2: item_level — equippables only, quality coloring honored
p = CW.Select("item_level", nil, ctx())
assert(p and p.text == "480" and p.r == 1, "ilvl renders white by default")
p = CW.Select("item_level", nil, ctx({ qualityColorText = true }))
assert(p and p.r == 0.1 and p.g == 0.2 and p.b == 0.3,
       "qualityColorText must route through GetQualityColor")
p = CW.Select("item_level", nil, ctx({ details = { ilvl = 480, isEquippable = false } }))
assert(p == nil, "non-equippable must not show ilvl")
-- regression: non-equippables (flasks/potions) can report a non-empty equipLoc
-- token; the gate is isEquippable, not equipLoc ~= "".
p = CW.Select("item_level", nil, ctx({ details = {
    ilvl = 480, equipLoc = "INVTYPE_NON_EQUIP_IGNORE", isEquippable = false } }))
assert(p == nil, "flask with INVTYPE_NON_EQUIP_IGNORE token must not show ilvl")
local noDetails = ctx()
noDetails.details = nil
p = CW.Select("item_level", nil, noDetails)
assert(p == nil, "missing details (item data not loaded) must fall through")

-- Test 3: junk / equipment_set — fact-gated textures
p = CW.Select("junk", nil, ctx({ isJunk = true }))
assert(p and p.atlas == "bags-junkcoin", "junk coin atlas")
assert(CW.Select("junk", nil, ctx()) == nil, "non-junk must not coin")
p = CW.Select("equipment_set", nil, ctx({ inSet = true }))
assert(p and p.atlas == "questlog-icon-setting", "set glyph atlas")
assert(CW.Select("equipment_set", nil, ctx()) == nil, "non-set must not glyph")

-- Test 4: binding — BoE (OnEquip=2 unbound), BoA (7/8/9 unbound), bound = nil
p = CW.Select("binding", nil, ctx())
assert(p and p.text == "BoE", "bindType 2 unbound = BoE")
for _, bt in ipairs({ 7, 8, 9 }) do
    p = CW.Select("binding", nil, ctx({ details = { bindType = bt, isBound = false } }))
    assert(p and p.text == "BoA", "bindType " .. bt .. " unbound = BoA")
end
p = CW.Select("binding", nil, ctx({ details = { bindType = 2, isBound = true } }))
assert(p == nil, "bound item must not show a binding tag")
p = CW.Select("binding", nil, ctx({ details = { bindType = 1, isBound = false } }))
assert(p == nil, "bind-on-pickup must not show a binding tag")

-- Test 5: expansion — short label from expacID
p = CW.Select("expansion", nil, ctx())
assert(p and p.text == "DF", "expacID 9 = DF")
p = CW.Select("expansion", nil, ctx({ details = { expacID = 0 } }))
assert(p and p.text == "Cls", "expacID 0 = Cls")
p = CW.Select("expansion", nil, ctx({ details = { expacID = nil } }))
assert(p == nil, "missing expacID must fall through")

-- Test 6: fallback chain — primary inapplicable → fallback; both miss → nil
p = CW.Select("junk", "item_level", ctx())
assert(p and p.text == "480", "inapplicable primary must fall to fallback")
p = CW.Select("junk", "item_level", ctx({ isJunk = true }))
assert(p and p.atlas == "bags-junkcoin", "applicable primary wins over fallback")
assert(CW.Select("none", "none", ctx()) == nil, "'none' picks render nothing")
assert(CW.Select("bogus", nil, ctx()) == nil, "unknown ids render nothing")
assert(CW.Select("quantity", nil, nil) == nil, "nil ctx (empty slot) renders nothing")

-- Test 7: crafting_quality — atlas straight from the dress-path fact
p = CW.Select("crafting_quality", nil,
    ctx({ craftQualityAtlas = "Professions-Icon-Quality-Tier3-Small" }))
assert(p and p.atlas == "Professions-Icon-Quality-Tier3-Small",
    "crafting_quality renders the supplied tier atlas")
p = CW.Select("crafting_quality", nil, ctx())
assert(p == nil, "no craftQualityAtlas → falls through")
p = CW.Select("crafting_quality", "quantity", ctx({ entry = { count = 5 } }))
assert(p and p.text == "5", "non-profession item falls to the fallback widget")

print("OK: bags_corner_widgets_test")
