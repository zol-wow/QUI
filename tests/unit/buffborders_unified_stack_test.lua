-- tests/unit/buffborders_unified_stack_test.lua
-- Run: lua tests/unit/buffborders_unified_stack_test.lua
--
-- Locks in the 12.1 rollback to TWO CustomAuraContainers:
--   * separate named anchors QUI_BuffIconContainer and QUI_DebuffIconContainer;
--   * each anchor owns exactly one CustomAuraContainerTemplate child;
--   * buffs and debuffs use independent filters and maxFrameCount values;
--   * no roundUpFrameIndex/cumulative stacked-filter math remains;
--   * the dedicated private-aura anchor subsystem is fully removed (12.1
--     AuraContainers render private auras natively).

local function readAll(path)
    local file = assert(io.open(path, "rb"))
    local data = file:read("*a")
    file:close()
    return (data:gsub("\r\n", "\n"))
end

local src = readAll("QUI_ActionBars/actionbars/buffborders.lua")

-- Separate named anchors.
assert(src:find('CreateFrame("Frame", "QUI_BuffIconContainer", UIParent)', 1, true),
    "must create the named buff anchor QUI_BuffIconContainer")
assert(src:find('CreateFrame("Frame", "QUI_DebuffIconContainer", UIParent)', 1, true),
    "must create the named debuff anchor QUI_DebuffIconContainer")
assert(src:find("debuffContainer", 1, true),
    "the debuffContainer upvalue/uses must be restored")

-- Independent per-host element STORES on independent hosts (the approved
-- two-store deviation: buffBorders.buffAuras / buffBorders.debuffAuras, each a
-- { elementsSeeded, elements = { ["*"] = {...} } } bucket). Filters diverge on
-- the element's auraType (HELPFUL vs HARMFUL) and compile C-side via the shared
-- AuraGlue.ElementGroups — the local BuildAuraFilter helper is gone.
assert(not src:find("BuildAuraFilter", 1, true),
    "the per-zone Lua BuildAuraFilter helper must be deleted (filters are element-borne)")
assert(src:find("buffAuras", 1, true) and src:find("debuffAuras", 1, true),
    "each host must own its own element store (buffAuras / debuffAuras)")
assert(src:find('EE.NewFilterStripElement("HELPFUL")', 1, true),
    "the buff default bucket must seed a HELPFUL filterStrip element")
assert(src:find('EE.NewFilterStripElement("HARMFUL")', 1, true),
    "the debuff default bucket must seed a HARMFUL filterStrip element")
assert(src:find("G.ElementGroups", 1, true) or src:find("AuraGlue.ElementGroups", 1, true),
    "group descriptors (buff/debuff filter divergence) come from AuraGlue.ElementGroups")
assert(not src:find("roundUpFrameIndex", 1, true),
    "two-host path must not use stacked-filter roundUpFrameIndex")
assert(not src:find("buffMax + debuffMax", 1, true),
    "two-host path must not use cumulative maxFrameCount math")

-- The dedicated private-aura anchor subsystem must not creep back: 12.1
-- AuraContainers render private auras natively via the normal debuff strip.
assert(not src:find("PrivateAura", 1, true),
    "buffborders.lua must not reintroduce dedicated private-aura anchors")
assert(not src:find("QUI_PA_", 1, true),
    "buffborders.lua must not reintroduce the QUI_PA_ private-aura gate")

print("buffborders_two_container_stack_test: OK")
