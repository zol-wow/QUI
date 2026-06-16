-- tests/unit/groupframes_preview_driver_test.lua
-- Run: lua tests/unit/groupframes_preview_driver_test.lua
-- The driver DEFINES functions that call WoW API but never at file scope, so it
-- loads with a fresh ns. Only the pure helpers are exercised here.
local ns = {}
assert(loadfile("QUI_GroupFrames/groupframes/settings/group_frames_preview_driver.lua"))("QUI_Options", ns)
local D = ns.QUI_GroupFramesPreview
local function test(n, f) print(n); f(); print("  ok") end
local NOW = 1000

test("filterStrip HELPFUL honors maxIcons and marks helpful", function()
    local m = D._BuildFilterStripMatches({ mode = "filterStrip", auraType = "HELPFUL", maxIcons = 2 }, NOW)
    assert(#m == 2, "expected 2 got " .. #m)
    assert(m[1].isHelpful == true and m[1].isHarmful == false)
    assert(m[1].icon and m[1].duration and m[1].expirationTime >= NOW)
    assert(m[1].expirationTime <= NOW + m[1].duration)
end)

test("filterStrip maxIcons=0 shows the full sample pool", function()
    local m = D._BuildFilterStripMatches({ mode = "filterStrip", auraType = "HELPFUL", maxIcons = 0 }, NOW)
    assert(#m >= 3, "expected full pool, got " .. #m)
end)

test("filterStrip HARMFUL sets dispelName and harmful flags", function()
    local m = D._BuildFilterStripMatches({ mode = "filterStrip", auraType = "HARMFUL", maxIcons = 3 }, NOW)
    assert(m[1].isHarmful == true and m[1].isHelpful == false)
    assert(type(m[1].dispelName) == "string")
end)

test("tracked builds a spellID-keyed map for configured spells", function()
    local m = D._BuildTrackedMatches({ mode = "tracked", displayType = "bar", spells = { 111, 222 } }, NOW)
    assert(m[111] and m[222], "both spellIDs keyed")
    assert(m[111].spellId == 111 and m[111].expirationTime >= NOW)
end)

test("tracked with no spells yields an empty map", function()
    local m = D._BuildTrackedMatches({ mode = "tracked", displayType = "icon" }, NOW)
    assert(next(m) == nil, "empty map when no spells")
end)

test("party grid: 5 units stack downward (grow DOWN), single column", function()
    local p = D._ComputeGridPositions("party", 5, { growDirection = "DOWN", spacing = 2 }, 100, 20)
    assert(#p == 5)
    assert(p[1].x == 0 and p[1].y == 0)
    assert(p[2].x == 0 and p[2].y == -(20 + 2))
    assert(p[5].y == -4 * (20 + 2))
end)

test("party grid: grow RIGHT lays units along +x", function()
    local p = D._ComputeGridPositions("party", 3, { growDirection = "RIGHT", spacing = 4 }, 100, 20)
    assert(p[1].x == 0 and p[2].x == (100 + 4) and p[3].x == 2 * (100 + 4))
    assert(p[1].y == 0 and p[2].y == 0)
end)

test("raid grouped: 10 units = 2 columns of 5 (vertical, groupGrow RIGHT)", function()
    local p = D._ComputeGridPositions("raid", 10,
        { growDirection = "DOWN", groupGrowDirection = "RIGHT", groupBy = "GROUP",
          spacing = 1, groupSpacing = 10 }, 80, 16)
    assert(p[1].x == 0 and p[5].x == 0)
    assert(p[6].x == (80 + 10) and p[6].y == 0)
    assert(p[2].y == -(16 + 1))
end)

test("raid flat (groupBy NONE) wraps by unitsPerFlat using spacing as colSpacing", function()
    local p = D._ComputeGridPositions("raid", 6,
        { growDirection = "DOWN", groupGrowDirection = "RIGHT", groupBy = "NONE",
          unitsPerFlat = 3, spacing = 2 }, 80, 16)
    assert(p[3].x == 0 and p[4].x == (80 + 2))
end)

test("roster has the requested count and stable fields", function()
    local r = D._BuildRoster("raid", 25)
    assert(#r == 25)
    for i = 1, 25 do
        assert(type(r[i].name) == "string" and r[i].name ~= "")
        assert(type(r[i].class) == "string")
        assert(r[i].role == "TANK" or r[i].role == "HEALER" or r[i].role == "DAMAGER")
        assert(type(r[i].healthPct) == "number")
    end
end)

test("roster is deterministic", function()
    local a = D._BuildRoster("party", 5)
    local b = D._BuildRoster("party", 5)
    for i = 1, 5 do assert(a[i].name == b[i].name and a[i].class == b[i].class) end
end)

test("raid snap: exact tiers pass through", function()
    assert(D._SnapRaidCount(5) == 5)
    assert(D._SnapRaidCount(20) == 20)
    assert(D._SnapRaidCount(40) == 40)
end)

test("raid snap: clamps below 5 and above 40", function()
    assert(D._SnapRaidCount(1) == 5)
    assert(D._SnapRaidCount(0) == 5)
    assert(D._SnapRaidCount(99) == 40)
    assert(D._SnapRaidCount(nil) == 25)   -- default when unset
end)

test("raid snap: rounds to nearest tier, ties round up", function()
    assert(D._SnapRaidCount(7) == 5)
    assert(D._SnapRaidCount(8) == 10)
    assert(D._SnapRaidCount(35) == 35)   -- 35 is a tier now: slider value renders 1:1
    assert(D._SnapRaidCount(33) == 35)   -- nearest multiple of 5
    assert(D._SnapRaidCount(32) == 30)   -- rounds down
    assert(D._SnapRaidCount(37) == 35)   -- |37-35|=2 < |37-40|=3
end)

test("filter normalize: nil yields all-true defaults", function()
    local fset = D._NormalizeFilter(nil)
    for _, k in ipairs({ "threat", "dispel", "auras", "indicators", "highlights" }) do
        assert(fset[k] == true, "expected default true for " .. k)
    end
end)

test("filter normalize: explicit false preserved, unknown keys dropped", function()
    local fset = D._NormalizeFilter({ threat = false, bogus = true })
    assert(fset.threat == false)
    assert(fset.dispel == true)
    assert(fset.bogus == nil, "unknown key must be dropped")
end)

test("filter allows: missing/true -> allowed, false -> denied", function()
    assert(D._FilterAllows({ threat = false }, "threat") == false)
    assert(D._FilterAllows({ threat = false }, "auras") == true)
    assert(D._FilterAllows(nil, "auras") == true)
end)

test("chip enabled: threat default-on unless explicit false", function()
    assert(D._ChipEnabledInConfig({ indicators = {} }, "threat") == true)
    assert(D._ChipEnabledInConfig({ indicators = { showThreatBorder = false } }, "threat") == false)
end)

test("chip enabled: dispel requires cfg.enabled ~= false", function()
    assert(D._ChipEnabledInConfig({ healer = { dispelOverlay = { enabled = true } } }, "dispel") == true)
    assert(D._ChipEnabledInConfig({ healer = { dispelOverlay = { enabled = false } } }, "dispel") == false)
    assert(D._ChipEnabledInConfig({ healer = {} }, "dispel") == false)
end)

test("chip enabled: auras requires enabled ~= false", function()
    assert(D._ChipEnabledInConfig({ auras = { enabled = true } }, "auras") == true)
    assert(D._ChipEnabledInConfig({ auras = { enabled = false } }, "auras") == false)
    assert(D._ChipEnabledInConfig({}, "auras") == false)
end)

test("chip enabled: indicators true if ANY corner icon on", function()
    assert(D._ChipEnabledInConfig({ indicators = { showLeaderIcon = true } }, "indicators") == true)
    assert(D._ChipEnabledInConfig({ indicators = {} }, "indicators") == false)
end)

test("chip enabled: highlights true if ANY extra on", function()
    assert(D._ChipEnabledInConfig({ pets = { enabled = true } }, "highlights") == true)
    assert(D._ChipEnabledInConfig({ healer = { targetHighlight = { enabled = true } } }, "highlights") == true)
    assert(D._ChipEnabledInConfig({ targetedSpells = { enabled = true } }, "highlights") == true)
    assert(D._ChipEnabledInConfig({}, "highlights") == false)
end)

test("indicator host level sits above aura sub-frames (+8/+9)", function()
    assert(D._IndicatorHostLevel(0) == 12)
    assert(D._IndicatorHostLevel(0) > 9, "must exceed aura bar level frame+9")
    assert(D._IndicatorHostLevel(100) == 112)
end)

print("ALL PASS")
