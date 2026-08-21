-- tests/unit/cdm_reanchor_auraphase_restyle_test.lua
-- Run: lua tests/unit/cdm_reanchor_auraphase_restyle_test.lua
-- Locks native aura-display timing and QUI cooldown swipe color.
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
local fMatchHasAura = true
local fMatch = {
    GetCooldownID = function() return 11 end,
    GetCooldownInfo = function() return { hasAura = fMatchHasAura } end,
}
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

-- 1) Native aura timing uses the buff swipe colour, NO timing writes.
do
    swipeStub.showCooldownIconAuraPhase = true
    swipeStub.showBuffSwipe = true
    fMatch.cooldownUseAuraDisplayTime = true
    local cd = NewCd()
    reassertColor(fMatch, cd)
    local c = assert(lastColor(cd), "aura phase paints a colour")
    assert(c[1] == 0.93 and c[2] == 0.77 and c[3] == 0 and c[4] == 0.45,
        "native aura timing: buff swipe colour")
    assert(#cd.binds == 0 and #cd.auraDisplay == 0 and cd.cleared == 0,
        "setting ON: native aura timing untouched")
end

-- 2) Disabling aura phase hides the native aura presentation.
do
    swipeStub.showCooldownIconAuraPhase = false
    fMatch.cooldownUseAuraDisplayTime = true
    cdDurObj, chargeDurObj = { cdSentinel = true }, nil
    durQueries = {}
    local cd = NewCd()
    reassertColor(fMatch, cd)
    local c = assert(lastColor(cd), "native aura timing uses the cooldown colour")
    assert(c[1] == 0 and c[2] == 0 and c[3] == 0 and c[4] == 0.8,
        "setting OFF: native aura timing uses the cooldown colour")
    assert(#durQueries == 0 and #cd.auraDisplay == 0 and #cd.binds == 0 and cd.cleared == 0,
        "setting OFF: native aura timing remains untouched")
end

-- 3) Setting OFF + cooldown swipe disabled: only the visual colour is hidden.
do
    swipeStub.showCooldownSwipe = false
    cdDurObj, chargeDurObj = { cdSentinel = true }, nil
    local cd = NewCd()
    reassertColor(fMatch, cd)
    assert(#cd.binds == 0 and #cd.auraDisplay == 0 and cd.cleared == 0,
        "swipe disabled: native timing remains untouched")
    local c = assert(lastColor(cd))
    assert(c[4] == 0, "swipe disabled: alpha-0 colour")
    swipeStub.showCooldownSwipe = true
end

-- 4) Setting OFF + an unclaimed frame: no native timing write.
do
    local orphan = { cooldownUseAuraDisplayTime = true }
    local cd = NewCd()
    reassertColor(orphan, cd)
    local c = assert(lastColor(cd))
    assert(c[1] == 0 and c[4] == 0.8 and #cd.binds == 0 and #cd.auraDisplay == 0,
        "no entry: native cooldown presentation remains native-owned")
end

-- 5) Non-aura phase: unchanged cooldown-colour path, no timing writes.
do
    fMatchHasAura = false
    fMatch.cooldownUseAuraDisplayTime = false
    local cd = NewCd()
    reassertColor(fMatch, cd)
    local c = assert(lastColor(cd))
    assert(c[1] == 0 and c[4] == 0.8, "non-aura phase: cooldown colour")
    assert(#cd.binds == 0 and #cd.auraDisplay == 0 and cd.cleared == 0,
        "non-aura phase: no timing writes")
end

-- 6) Item-backed entry: native timing remains untouched.
do
    curatedEntry.type = "trinket"
    curatedEntry.spellID = nil
    curatedEntry.id = 13 -- trinket slot, NOT a spellID
    fMatch.cooldownUseAuraDisplayTime = true
    swipeStub.showCooldownIconAuraPhase = false
    local itemCalls = {}
    ns.CDMResolvers = {
        BuildEntryItemDurationObject = function(entry)
            itemCalls[#itemCalls + 1] = entry
            return { itemSentinel = true }
        end,
    }
    durQueries = {}
    local cd = NewCd()
    reassertColor(fMatch, cd)
    assert(#itemCalls == 0 and #durQueries == 0 and #cd.binds == 0
        and #cd.auraDisplay == 0 and cd.cleared == 0,
        "item entry: no native timing source or write")
    ns.CDMResolvers = nil
    curatedEntry.type = nil
    curatedEntry.spellID = 500
    curatedEntry.id = nil
end

-- 7) Consumable entry: native timing remains untouched.
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
    assert(#durQueries == 0 and #cd.binds == 0 and #cd.auraDisplay == 0 and cd.cleared == 0,
        "consumable: no native timing source or write")
    ns.CDMIndex = nil
    curatedEntry.type = nil
    curatedEntry.spellID = 500
    curatedEntry.id = nil
end

print("OK: cdm_reanchor_auraphase_restyle_test")
