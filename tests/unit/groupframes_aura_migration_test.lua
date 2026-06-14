-- tests/unit/groupframes_aura_migration_test.lua
-- Run: lua tests/unit/groupframes_aura_migration_test.lua
local ns = dofile("tools/_addon_env.lua").LoadCore()
local M = ns.Migrations
local function test(n, f) print(n); f(); print("  ok") end

-- Build a legacy group-frame context table (old shape) for one context.
local function legacyContext()
    return {
        auras = {
            showDebuffs = true, maxDebuffs = 3, debuffIconSize = 16, debuffAnchor = "BOTTOMRIGHT",
            debuffGrowDirection = "LEFT", debuffSpacing = 2, debuffOffsetX = -2, debuffOffsetY = -18,
            debuffHideSwipe = false, debuffReverseSwipe = false,
            showBuffs = true, maxBuffs = 4, buffIconSize = 14, buffAnchor = "TOPLEFT",
            buffGrowDirection = "RIGHT", buffSpacing = 2, buffOffsetX = 2, buffOffsetY = 16,
            buffHideSwipe = false, buffReverseSwipe = false,
            filterMode = "off", buffFilterOnlyMine = true, buffHidePermanent = false, buffDeduplicateDefensives = true,
            buffClassifications = { raid = true }, debuffClassifications = { important = true },
            buffWhitelist = { [123] = true }, buffBlacklist = {}, debuffWhitelist = {}, debuffBlacklist = {},
        },
        pinnedAuras = {
            enabled = true, slotSize = 8, edgeInset = 2, showSwipe = true, reverseSwipe = false,
            specSlots = { [105] = {
                { spellID = 774, displayType = "icon", anchor = "TOPLEFT" },
                { spellID = 33763, displayType = "square", anchor = "BOTTOMRIGHT", color = { 0, 1, 0 } },
            } },
        },
        auraIndicators = {
            enabled = true, iconSize = 14, anchor = "TOP", growDirection = "RIGHT", spacing = 2,
            maxIndicators = 5, hideSwipe = false, reverseSwipe = false, entries = {
                { spellID = 139, enabled = true, onlyMine = true, indicators = { { type = "icon", enabled = true } } },
                { spellID = 41635, enabled = true, onlyMine = false, indicators = {
                    { type = "icon", enabled = true },
                    { type = "bar", enabled = true, anchor = "LEFT", offsetX = 1, offsetY = 0, thickness = 4, length = 40 },
                } },
                { spellID = 21562, enabled = true, onlyMine = false, indicators = {
                    { type = "healthBarColor", enabled = true, color = { 1, 1, 1 }, animation = "fill" } } },
            },
        },
    }
end

test("strips → 2 filterStrip elements in '*' with field carry", function()
    local ctx = legacyContext()
    M.MigrateUnifiedAuras_Context(ctx)              -- per-context helper (pure)
    local star = ctx.auras.elements["*"]
    local buff, debuff
    for _, e in ipairs(star) do
        if e.mode == "filterStrip" and e.auraType == "HELPFUL" then buff = e end
        if e.mode == "filterStrip" and e.auraType == "HARMFUL" then debuff = e end
    end
    assert(buff and debuff)
    assert(buff.enabled == true and buff.maxIcons == 4 and buff.onlyMine == true)
    assert(buff.anchor == "TOPLEFT" and buff.offsetY == 16)
    assert(debuff.enabled == true and debuff.maxIcons == 3 and debuff.anchor == "BOTTOMRIGHT")
    assert(buff.whitelist[123] == true)
end)

test("pinned slots → tracked elements in [105] with edgeInset→offset", function()
    local ctx = legacyContext(); M.MigrateUnifiedAuras_Context(ctx)
    local slots = ctx.auras.elements[105]
    assert(#slots == 2)
    local rejuv = slots[1]
    assert(rejuv.mode == "tracked" and rejuv.spells[1] == 774 and rejuv.displayType == "icon")
    assert(rejuv.anchor == "TOPLEFT" and rejuv.offsetX == 2 and rejuv.offsetY == -2)  -- edgeInset 2
    assert(rejuv.iconSize == 8 and rejuv.enabled == true)
    local lb = slots[2]
    assert(lb.displayType == "square" and lb.offsetX == -2 and lb.offsetY == 2)
end)

test("indicators: icon entries collapse to one strip element with onlyMineSpells", function()
    local ctx = legacyContext(); M.MigrateUnifiedAuras_Context(ctx)
    local star = ctx.auras.elements["*"]
    local iconStrip
    for _, e in ipairs(star) do
        if e.mode == "tracked" and e.displayType == "icon" then iconStrip = e end
    end
    assert(iconStrip)
    -- spells 139 and 41635 both had an icon indicator
    local has139, has41635 = false, false
    for _, s in ipairs(iconStrip.spells) do
        if s == 139 then has139 = true elseif s == 41635 then has41635 = true end
    end
    assert(has139 and has41635)
    assert(iconStrip.onlyMineSpells[139] == true)        -- entry 139 onlyMine=true preserved
    assert(iconStrip.onlyMineSpells[41635] == false)
    assert(iconStrip.anchor == "TOP" and iconStrip.iconSize == 14 and iconStrip.maxIcons == 5)
end)

test("indicators: bar + healthTint → own elements", function()
    local ctx = legacyContext(); M.MigrateUnifiedAuras_Context(ctx)
    local star = ctx.auras.elements["*"]
    local bar, tint
    for _, e in ipairs(star) do
        if e.mode == "tracked" and e.displayType == "bar" then bar = e end
        if e.mode == "tracked" and e.displayType == "healthTint" then tint = e end
    end
    assert(bar and bar.spells[1] == 41635 and bar.anchor == "LEFT" and bar.bar.thickness == 4)
    assert(tint and tint.spells[1] == 21562 and tint.healthTint.animation == "fill")
end)

test("idempotent: second run is a no-op", function()
    local ctx = legacyContext()
    M.MigrateUnifiedAuras_Context(ctx)
    local n1 = #ctx.auras.elements["*"]
    M.MigrateUnifiedAuras_Context(ctx)
    assert(#ctx.auras.elements["*"] == n1)
    -- ADDITIVE migration: legacy keys are KEPT (legacy runtime still reads them
    -- until the consumer flip; the flip release removes them).
    assert(ctx.pinnedAuras ~= nil and ctx.auraIndicators ~= nil)
    assert(ctx.auras.showDebuffs == true)  -- legacy strip fields retained too
end)

test("RunOnProfile wires v46 through the real group-frame path", function()
    local prof = { quiGroupFrames = {   -- if your path verification finds a different key, use it here AND in the wrapper
        party = legacyContext(), raid = legacyContext(),
    } }
    M.RunOnProfile(prof)
    assert(prof.quiGroupFrames.party.auras and prof.quiGroupFrames.party.auras.elements, "party migrated")
    assert(prof.quiGroupFrames.raid.auras and prof.quiGroupFrames.raid.auras.elements, "raid migrated")
    assert(prof.quiGroupFrames.party.pinnedAuras ~= nil, "legacy pinned KEPT (additive until flip)")
end)

test("fresh profile (already has elements) is left alone by the context migration", function()
    local ctx = { auras = { enabled = true, elements = { ["*"] = {} } } }
    M.MigrateUnifiedAuras_Context(ctx)
    assert(#ctx.auras.elements["*"] == 0)  -- early-return: nothing appended to existing elements
end)

test("icon strip: disabled entry first, enabled second -> strip enabled, only enabled spell", function()
    local ctx = { auraIndicators = {
        enabled = true, anchor = "TOP", growDirection = "RIGHT", spacing = 2, iconSize = 14, maxIndicators = 5,
        entries = {
            { spellID = 111, enabled = false, onlyMine = false, indicators = { { type = "icon", enabled = true } } },
            { spellID = 222, enabled = true,  onlyMine = false, indicators = { { type = "icon", enabled = true } } },
        },
    } }
    M.MigrateUnifiedAuras_Context(ctx)
    local strip
    for _, e in ipairs(ctx.auras.elements["*"]) do
        if e.mode == "tracked" and e.displayType == "icon" then strip = e end
    end
    assert(strip, "icon strip created")
    assert(strip.enabled == true, "strip enabled from container, NOT frozen at the first (disabled) entry")
    local has111, has222 = false, false
    for _, s in ipairs(strip.spells) do
        if s == 111 then has111 = true elseif s == 222 then has222 = true end
    end
    assert(has222 == true, "enabled entry spell present")
    assert(has111 == false, "disabled entry spell excluded (was never shown)")
end)

test("icon strip: container disabled -> strip disabled even with an enabled entry", function()
    local ctx = { auraIndicators = {
        enabled = false, anchor = "TOP", entries = {
            { spellID = 222, enabled = true, indicators = { { type = "icon", enabled = true } } },
        },
    } }
    M.MigrateUnifiedAuras_Context(ctx)
    local strip
    for _, e in ipairs(ctx.auras.elements["*"]) do
        if e.mode == "tracked" and e.displayType == "icon" then strip = e end
    end
    assert(strip and strip.enabled == false, "container off => strip off")
end)

print("ALL PASS")
