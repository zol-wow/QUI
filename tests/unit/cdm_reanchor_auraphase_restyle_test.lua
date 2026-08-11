-- tests/unit/cdm_reanchor_auraphase_restyle_test.lua
-- Run: lua tests/unit/cdm_reanchor_auraphase_restyle_test.lua
-- Locks the reassertColor contract for showCooldownIconAuraPhase on re-anchored
-- NATIVE frames: setting ON -> aura colour over Blizzard's native aura timing;
-- setting OFF -> re-bind the widget to the spell's REAL cooldown via a duration
-- object (spell CD first, charge recharge fallback), or clear to ready when the
-- spell has no cooldown behind the buff. Colour honours showCooldownSwipe.
local ns = {}
-- Task 45f: cdm_reanchor*.lua route discarded-result pcall guards through
-- ns.SafeCall. Additive stub (T1d/T1e precedent) — bare pcall passthrough.
ns.SafeCall = function(_policy, fn, ...) return pcall(fn, ...) end
ns.SafeCallMethod = function(_policy, obj, name, ...) return pcall(function(...) return obj[name](obj, ...) end, ...) end
ns.SafeCallMethodIfPresent = function(_policy, obj, name, ...) if obj == nil then return nil end local okP, m = pcall(function() return obj[name] end) if not okP then return false end if m == nil then return nil end return pcall(m, obj, ...) end
local loadChunk = dofile("tests/helpers/load_cdm_consolidated_chunk.lua")
loadChunk("QUI_CDM/cdm/cdm_reanchor.lua", "cdm_reanchor.lua")("QUI", ns)
loadChunk("QUI_CDM/cdm/cdm_reanchor_wiring.lua", "cdm_reanchor_wiring.lua")("QUI", ns)
loadChunk("QUI_CDM/cdm/cdm_reanchor_runtime.lua", "cdm_reanchor_runtime.lua")("QUI", ns)
loadChunk("QUI_CDM/cdm/cdm_reanchor_boot.lua", "cdm_reanchor_boot.lua")("QUI", ns)
local B = assert(ns.CDMReanchorBoot)

-- Minimal live viewer: one curated-matched frame (cd 11 <- spellID 500).
local raw = {
    ClearAllPoints = function() end,
    SetPoint = function() end,
    SetAlpha = function() end,
}
local fMatch = { GetCooldownID = function() return 11 end }
local viewer = { GetItemFrames = function() return { fMatch } end }
local container = { SetSize = function() end }
local curatedEntry = { spellID = 500, _assignedRow = 1 }

local env = {
    CDMReanchor = {
        New = function(opts)
            opts = opts or {}
            opts.raw = raw
            opts.securecall = function(fn, ...) return fn(...) end
            opts.hooksecurefunc = function() end
            return ns.CDMReanchor.New(opts)
        end,
    },
    CDMReanchorWiring = {
        New = function(opts)
            local w = ns.CDMReanchorWiring.New(opts)
            w.GetViewerForKey = function() return viewer end
            return w
        end,
    },
    CDMReanchorRuntime = ns.CDMReanchorRuntime,
    uiParent = { uiparent = true },
    index = {
        IsUsableID = function(id) return type(id) == "number" and id > 0 end,
        Get = function(id) if id == 500 then return { cooldownID = 11 } end end,
    },
    getContainer = function() return container end,
    getCurated = function() return { curatedEntry } end,
    getSettings = function() return { row1 = { iconCount = 4, iconSize = 40 } } end,
    buildLayout = function(_, icons)
        local p = {}
        for i = 1, #icons do
            p[i] = { icon = icons[i], x = i, y = -i, w = 30, h = 20, rowConfig = { size = 30 } }
        end
        return { placements = p, metrics = { iconWidth = 40, totalHeight = 40 } }
    end,
    pixelRound = function(v) return v end,
    acquireIcon = function() return nil end,
    releaseIcon = function() end,
    resolveAdditional = function() return {} end,
    mintShell = function() end,
    positionShell = function() end,
    positionClickSlot = function() return { SetSize = function() end } end,
    updateClickOverlay = function() end,
    beginShellPass = function() end,
    endShellPass = function() end,
}

-- Capture the reassertColor closure BuildRuntime wires into the aura-phase owner.
local capturedAuraDeps
ns.CDMReanchorAuraPhase = { New = function(deps) capturedAuraDeps = deps; return { Hook = function() end } end }
local swipeStub = { showCooldownIconAuraPhase = true, showCooldownSwipe = true }
ns._OwnedSwipe = { GetSettings = function() return swipeStub end }

-- Controllable duration-object sources (opaque sentinel tables).
local cdDurObj, chargeDurObj
local durQueries = {}
ns.CDMSources = {
    QuerySpellCooldownDuration = function(spellID, ignoreGCD)
        durQueries[#durQueries + 1] = { kind = "cd", spellID = spellID, ignoreGCD = ignoreGCD }
        return cdDurObj
    end,
    QuerySpellChargeDuration = function(spellID)
        durQueries[#durQueries + 1] = { kind = "charge", spellID = spellID }
        return chargeDurObj
    end,
}

local facade = B.BuildRuntime(env)
assert(facade:RefreshBuiltin("essential") == 1, "curated entry claims the native frame")
assert(capturedAuraDeps and type(capturedAuraDeps.reassertColor) == "function",
    "BuildRuntime wires reassertColor into the aura-phase owner")
local reassertColor = capturedAuraDeps.reassertColor

-- Recording cooldown-widget stub.
local function NewCd()
    local cd = { colors = {}, binds = {}, auraDisplay = {}, cleared = 0 }
    cd.SetSwipeColor = function(_, r, g, b, a) cd.colors[#cd.colors + 1] = { r, g, b, a } end
    cd.SetUseAuraDisplayTime = function(_, v) cd.auraDisplay[#cd.auraDisplay + 1] = v end
    cd.SetCooldownFromDurationObject = function(_, durObj, clearIfZero)
        cd.binds[#cd.binds + 1] = { durObj = durObj, clearIfZero = clearIfZero }
    end
    cd.Clear = function() cd.cleared = cd.cleared + 1 end
    return cd
end
local function lastColor(cd) return cd.colors[#cd.colors] end

-- 1) Setting ON + aura phase: aura colour only, NO timing writes.
do
    swipeStub.showCooldownIconAuraPhase = true
    fMatch.cooldownUseAuraDisplayTime = true
    local cd = NewCd()
    reassertColor(fMatch, cd)
    local c = assert(lastColor(cd), "aura phase paints a colour")
    assert(c[1] > 0.9 and c[2] > 0.7, "setting ON: aura (fallback gold) colour")
    assert(#cd.binds == 0 and #cd.auraDisplay == 0 and cd.cleared == 0,
        "setting ON: native aura timing untouched")
end

-- 2) Setting OFF + aura phase + spell CD active: re-bind to the real cooldown.
do
    swipeStub.showCooldownIconAuraPhase = false
    fMatch.cooldownUseAuraDisplayTime = true
    cdDurObj, chargeDurObj = { cdSentinel = true }, nil
    durQueries = {}
    local cd = NewCd()
    reassertColor(fMatch, cd)
    assert(durQueries[1] and durQueries[1].kind == "cd"
        and durQueries[1].spellID == 500 and durQueries[1].ignoreGCD == true,
        "setting OFF: queries the spell CD duration object (ignoreGCD)")
    assert(#cd.auraDisplay == 1 and cd.auraDisplay[1] == false,
        "setting OFF: widget leaves aura display mode")
    assert(#cd.binds == 1 and cd.binds[1].durObj == cdDurObj and cd.binds[1].clearIfZero == true,
        "setting OFF: re-binds the widget to the spell CD duration object")
    local c = assert(lastColor(cd))
    assert(c[1] == 0 and c[2] == 0 and c[3] == 0 and c[4] == 0.8,
        "setting OFF: cooldown (fallback dark) colour")
    assert(cd.cleared == 0, "active CD: no clear")
end

-- 3) Setting OFF + spell castable but a charge recharging: charge fallback.
do
    cdDurObj, chargeDurObj = nil, { chargeSentinel = true }
    local cd = NewCd()
    reassertColor(fMatch, cd)
    assert(#cd.binds == 1 and cd.binds[1].durObj == chargeDurObj,
        "setting OFF: nil spell CD falls back to the charge recharge duration object")
end

-- 4) Setting OFF + no cooldown at all behind the buff: clear to ready.
do
    cdDurObj, chargeDurObj = nil, nil
    local cd = NewCd()
    reassertColor(fMatch, cd)
    assert(cd.cleared == 1, "no CD behind the buff: widget cleared to ready")
    assert(#cd.binds == 0, "no CD behind the buff: nothing re-bound")
    local c = assert(lastColor(cd))
    assert(c[4] == 0, "no CD behind the buff: alpha-0 colour")
end

-- 5) Setting OFF + cooldown swipe disabled: re-bind still happens, colour alpha-0
--    (countdown text follows the re-bind; only the radial darkening is hidden).
do
    swipeStub.showCooldownSwipe = false
    cdDurObj, chargeDurObj = { cdSentinel = true }, nil
    local cd = NewCd()
    reassertColor(fMatch, cd)
    assert(#cd.binds == 1, "swipe disabled: re-bind still happens")
    local c = assert(lastColor(cd))
    assert(c[4] == 0, "swipe disabled: alpha-0 colour")
    swipeStub.showCooldownSwipe = true
end

-- 6) Setting OFF + unclaimed frame (no curated entry): suppress outright.
do
    local orphan = { cooldownUseAuraDisplayTime = true }
    local cd = NewCd()
    reassertColor(orphan, cd)
    assert(cd.cleared == 1 and #cd.binds == 0, "no entry: suppress (clear), never re-bind")
    local c = assert(lastColor(cd))
    assert(c[4] == 0, "no entry: alpha-0 colour")
end

-- 7) Non-aura phase: unchanged cooldown-colour path, no timing writes.
do
    fMatch.cooldownUseAuraDisplayTime = false
    local cd = NewCd()
    reassertColor(fMatch, cd)
    local c = assert(lastColor(cd))
    assert(c[1] == 0 and c[4] == 0.8, "non-aura phase: cooldown colour")
    assert(#cd.binds == 0 and #cd.auraDisplay == 0 and cd.cleared == 0,
        "non-aura phase: no timing writes")
end

-- reassertDesat: Blizzard forces the icon BRIGHT in aura phase (RefreshData
-- writes desaturation AFTER the timing refresh), so the aura-phase-off restyle
-- must re-drive saturation from the SetDesaturated post-hook: real-CD duration
-- object through the shared step curve into SetDesaturation (dark while the CD
-- rolls, bright at zero). Leaves Blizzard's writes alone everywhere else.
assert(type(capturedAuraDeps.reassertDesat) == "function",
    "BuildRuntime wires reassertDesat into the aura-phase owner")
local reassertDesat = capturedAuraDeps.reassertDesat

local desatCurve = { curveSentinel = true }
ns._CDM_GetCooldownDesatCurve = function() return desatCurve end
local function NewTex()
    local tex = { levels = {}, bools = {} }
    tex.SetDesaturation = function(_, v) tex.levels[#tex.levels + 1] = v end
    tex.SetDesaturated = function(_, v) tex.bools[#tex.bools + 1] = v end
    return tex
end
local function NewDurObj()
    return {
        EvaluateRemainingPercent = function(_, curve)
            assert(curve == desatCurve, "evaluates through the shared step curve")
            return 0.42 -- opaque C-side handle stand-in
        end,
    }
end

-- 8) Setting OFF + aura phase + real CD: curve-driven SetDesaturation.
do
    swipeStub.showCooldownIconAuraPhase = false
    fMatch.cooldownUseAuraDisplayTime = true
    cdDurObj, chargeDurObj = NewDurObj(), nil
    local tex = NewTex()
    reassertDesat(fMatch, tex)
    assert(#tex.levels == 1 and tex.levels[1] == 0.42,
        "aura-phase-off + real CD: curve value driven into SetDesaturation")
    assert(#tex.bools == 0, "curve path never uses the boolean setter")
end

-- 9) Setting OFF + no CD behind the buff: leave Blizzard's bright write.
do
    cdDurObj, chargeDurObj = nil, nil
    local tex = NewTex()
    reassertDesat(fMatch, tex)
    assert(#tex.levels == 0 and #tex.bools == 0,
        "no real CD: icon stays bright (matches clear-to-ready)")
end

-- 10) Setting OFF + no CurveUtil: boolean fallback.
do
    ns._CDM_GetCooldownDesatCurve = nil
    cdDurObj, chargeDurObj = NewDurObj(), nil
    local tex = NewTex()
    reassertDesat(fMatch, tex)
    assert(#tex.bools == 1 and tex.bools[1] == true,
        "no curve helper: falls back to SetDesaturated(true)")
    ns._CDM_GetCooldownDesatCurve = function() return desatCurve end
end

-- 11) Setting ON: never touches Blizzard's desaturation.
do
    swipeStub.showCooldownIconAuraPhase = true
    cdDurObj = NewDurObj()
    local tex = NewTex()
    reassertDesat(fMatch, tex)
    assert(#tex.levels == 0 and #tex.bools == 0, "setting ON: desaturation untouched")
end

-- 12) Non-aura phase: never touches Blizzard's desaturation.
do
    swipeStub.showCooldownIconAuraPhase = false
    fMatch.cooldownUseAuraDisplayTime = false
    cdDurObj = NewDurObj()
    local tex = NewTex()
    reassertDesat(fMatch, tex)
    assert(#tex.levels == 0 and #tex.bools == 0, "non-aura phase: desaturation untouched")
end

-- 13) Item-backed entry (trinket/slot/item): entry.id is an ITEM/SLOT id, not a
--     spellID -- must route through the resolvers' item duration-object builder,
--     never the spell queries (which returned nil and cleared the trinket to a
--     bright "ready" icon during its proc).
do
    curatedEntry.type = "trinket"
    curatedEntry.spellID = nil
    curatedEntry.id = 13 -- trinket slot, NOT a spellID
    fMatch.cooldownUseAuraDisplayTime = true
    swipeStub.showCooldownIconAuraPhase = false
    local itemDurObj = { itemSentinel = true }
    local itemCalls = {}
    ns.CDMResolvers = {
        BuildEntryItemDurationObject = function(entry)
            itemCalls[#itemCalls + 1] = entry
            return itemDurObj
        end,
    }
    durQueries = {}
    local cd = NewCd()
    reassertColor(fMatch, cd)
    assert(#itemCalls == 1 and itemCalls[1] == curatedEntry,
        "item entry: resolvers item duration-object builder consulted")
    assert(#durQueries == 0, "item entry: spell duration queries never consulted")
    assert(#cd.binds == 1 and cd.binds[1].durObj == itemDurObj,
        "item entry: widget re-bound to the ITEM cooldown duration object")
    assert(cd.cleared == 0, "item entry with rolling CD: never cleared to ready")
    -- desat rides the same item durObj through the curve
    itemDurObj.EvaluateRemainingPercent = function(_, curve)
        assert(curve == desatCurve, "item durObj evaluates through the shared curve")
        return 0.77
    end
    local tex = NewTex()
    reassertDesat(fMatch, tex)
    assert(#tex.levels == 1 and tex.levels[1] == 0.77,
        "item entry: curve-driven desaturation from the item durObj")
    ns.CDMResolvers = nil
    curatedEntry.type = nil
    curatedEntry.spellID = 500
    curatedEntry.id = nil
end

-- 14) Consumable entry: entry.id is a SPELL CATEGORY id -- resolves through
--     CDMIndex.GetByCategory -> primarySpellID into the spell duration path.
do
    curatedEntry.type = "consumable"
    curatedEntry.spellID = nil
    curatedEntry.id = 4 -- spell category, NOT a spellID
    fMatch.cooldownUseAuraDisplayTime = true
    swipeStub.showCooldownIconAuraPhase = false
    ns.CDMIndex = {
        GetByCategory = function(catID)
            assert(catID == 4, "consumable resolves via its category id")
            return { cooldownID = 404, primarySpellID = 777 }
        end,
    }
    cdDurObj, chargeDurObj = { cdSentinel = true }, nil
    durQueries = {}
    local cd = NewCd()
    reassertColor(fMatch, cd)
    assert(durQueries[1] and durQueries[1].kind == "cd" and durQueries[1].spellID == 777,
        "consumable: spell duration queried with the category's primarySpellID")
    assert(#cd.binds == 1 and cd.binds[1].durObj == cdDurObj,
        "consumable: widget re-bound to the category cooldown duration object")
    ns.CDMIndex = nil
    curatedEntry.type = nil
    curatedEntry.spellID = 500
    curatedEntry.id = nil
end

print("OK: cdm_reanchor_auraphase_restyle_test")
