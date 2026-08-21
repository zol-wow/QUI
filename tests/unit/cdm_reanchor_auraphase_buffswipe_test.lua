-- tests/unit/cdm_reanchor_auraphase_buffswipe_test.lua
-- Run: lua tests/unit/cdm_reanchor_auraphase_buffswipe_test.lua
--
-- BuffIcon swipe ownership on re-anchored frames. Three pinned contracts:
--
-- 1) reassertColor/reassertEdge route BUFF container frames to the owned
--    buff-child rules (cdm_effects ApplySwipeToBuffChild): showBuffIconSwipe
--    gate + AURA colour, never the cooldown colour and NEVER the aura-phase-off
--    timing restyle. BuffIcon items never set the cooldownUseAuraDisplayTime
--    FIELD (CooldownViewerBuffIconItemMixin refreshes via its own
--    RefreshCooldownInfo, not RefreshSpellCooldownInfo), so without the
--    container key they'd misclassify as plain cooldown swipes.
--
-- 2) The aura-phase owner threads the container key from Hook into every
--    reassert callback, and exposes Reassert(frame) -- the proactive claim-time
--    assert. The per-widget hooks only fire on the NEXT Blizzard write; BuffIcon
--    recolours ONCE per aura application (at apply, BEFORE the settled claim
--    pass), so a first-claimed frame kept the native swipe colour until the next
--    aura refresh ("swipe colours applied inconsistently").
--
-- 3) The runtime claim pass passes the container key to Hook and drives
--    Reassert on every claimed frame.
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

-- Capture the reassert closures AND record the runtime's Hook/Reassert calls.
local capturedAuraDeps
local hookCalls, reasserts = {}, {}
ns.CDMReanchorAuraPhase = { New = function(deps)
    capturedAuraDeps = deps
    return {
        Hook = function(_, frame, key) hookCalls[#hookCalls + 1] = { frame = frame, key = key } end,
        Reassert = function(_, frame) reasserts[#reasserts + 1] = frame end,
    }
end }
local swipeStub = { showCooldownIconAuraPhase = true, showCooldownSwipe = true }
ns._OwnedSwipe = { GetSettings = function() return swipeStub end }
-- Distinct per-mode sentinels so the aura-vs-cooldown routing is unambiguous.
ns._CDM_ResolveModeColor = function(_, mode)
    if mode == "aura" then return 0.11, 0.22, 0.33, 0.44 end
    return 0.55, 0.66, 0.77, 0.88
end

local facade = B.BuildRuntime(env)

---------------------------------------------------------------------------
-- 3) Runtime claim pass: container key threaded into Hook + Reassert driven.
---------------------------------------------------------------------------
assert(facade:RefreshBuiltin("essential") == 1, "curated entry claims the native frame")
assert(hookCalls[1] and hookCalls[1].frame == fMatch and hookCalls[1].key == "essential",
    "claim pass passes the container key to the aura-phase Hook")
assert(reasserts[1] == fMatch,
    "claim pass drives the proactive Reassert on the claimed frame")

assert(capturedAuraDeps and type(capturedAuraDeps.reassertColor) == "function",
    "BuildRuntime wires reassertColor into the aura-phase owner")
local reassertColor = capturedAuraDeps.reassertColor
local reassertEdge = assert(capturedAuraDeps.reassertEdge)
local reassertSwipe = assert(capturedAuraDeps.reassertSwipe)

-- Recording cooldown-widget stub.
local function NewCd()
    local cd = { colors = {}, binds = {}, auraDisplay = {}, edges = {}, swipes = {}, cleared = 0 }
    cd.SetSwipeColor = function(_, r, g, b, a) cd.colors[#cd.colors + 1] = { r, g, b, a } end
    cd.SetUseAuraDisplayTime = function(_, v) cd.auraDisplay[#cd.auraDisplay + 1] = v end
    cd.SetCooldownFromDurationObject = function(_, durObj, clearIfZero)
        cd.binds[#cd.binds + 1] = { durObj = durObj, clearIfZero = clearIfZero }
    end
    cd.SetDrawEdge = function(_, v) cd.edges[#cd.edges + 1] = v end
    cd.SetDrawSwipe = function(_, v) cd.swipes[#cd.swipes + 1] = v end
    cd.Clear = function() cd.cleared = cd.cleared + 1 end
    return cd
end
local function lastColor(cd) return cd.colors[#cd.colors] end

---------------------------------------------------------------------------
-- 1) reassertColor buff routing.
---------------------------------------------------------------------------
-- BuffIcon frame: NO cooldownUseAuraDisplayTime field, aura-phase setting OFF --
-- the exact shape that previously fell into the cooldown branch (and would have
-- been timing-restyled had the field been set).
do
    swipeStub.showCooldownIconAuraPhase = false
    local buffFrame = {}
    local cd = NewCd()
    reassertColor(buffFrame, cd, "buff")
    local c = assert(lastColor(cd), "buff key paints a colour")
    assert(c[1] == 0.11 and c[2] == 0.22 and c[3] == 0.33 and c[4] == 0.44,
        "buff key: AURA colour (owned buff-child parity), not the cooldown colour")
    assert(#cd.binds == 0 and #cd.auraDisplay == 0 and cd.cleared == 0,
        "buff key: never timing-restyled, even with the aura-phase setting OFF")
end

-- "buffIcon" viewer-key alias routes the same way.
do
    local cd = NewCd()
    reassertColor({}, cd, "buffIcon")
    local c = assert(lastColor(cd))
    assert(c[1] == 0.11 and c[4] == 0.44, "buffIcon alias key: aura colour")
end

-- showBuffIconSwipe=false: alpha-0 (matches ApplySwipeToBuffChild).
do
    swipeStub.showBuffIconSwipe = false
    local cd = NewCd()
    reassertColor({}, cd, "buff")
    local c = assert(lastColor(cd))
    assert(c[1] == 0 and c[2] == 0 and c[3] == 0 and c[4] == 0,
        "showBuffIconSwipe=false: alpha-0 swipe")
    swipeStub.showBuffIconSwipe = nil
end

-- Non-buff key with no aura field: unchanged cooldown-colour path (pin).
do
    local cd = NewCd()
    reassertColor({}, cd, nil)
    local c = assert(lastColor(cd))
    assert(c[1] == 0.55 and c[4] == 0.88, "no key: cooldown colour path unchanged")
end

do
    local cd = NewCd()
    reassertSwipe({ cooldownUseAuraDisplayTime = true }, cd, nil, true)
    assert(cd.swipes[1] == false,
        "aura-phase setting hides the native aura swipe when disabled")

    swipeStub.showCooldownSwipe = false
    cd = NewCd()
    reassertSwipe({}, cd, nil, true)
    assert(cd.swipes[1] == false, "cooldown swipe setting hides Blizzard's native swipe")

    swipeStub.showCooldownSwipe = true
    local frame = { HasVisualDataSource_Charges = function() return false end }
    cd = NewCd()
    reassertSwipe(frame, cd, nil, false)
    assert(cd.swipes[1] == true, "non-charge cooldown keeps the configured swipe visible")

    frame.HasVisualDataSource_Charges = function() return true end
    cd = NewCd()
    reassertSwipe(frame, cd, nil, false)
    assert(#cd.swipes == 0, "charge source preserves Blizzard's native swipe decision")
end

do
    swipeStub.showCooldownIconAuraPhase = true
    swipeStub.showBuffSwipe = true
    local cd = NewCd()
    reassertSwipe({ cooldownUseAuraDisplayTime = true }, cd, nil, false)
    assert(cd.swipes[1] == true, "enabled aura phase restores a hidden native swipe")

    swipeStub.showBuffIconSwipe = true
    cd = NewCd()
    reassertSwipe({}, cd, "buff", false)
    assert(cd.swipes[1] == true, "enabled buff icon swipe restores a hidden native swipe")
end

---------------------------------------------------------------------------
-- 1b) reassertEdge buff routing: rides showBuffIconSwipe/showBuffEdge, not
--     showRechargeEdge.
---------------------------------------------------------------------------
do
    swipeStub.showRechargeEdge = false  -- would force-hide on the cooldown path
    local cd = NewCd()
    reassertEdge({}, cd, "buff")
    assert(#cd.edges == 0, "buff key + buff toggles ON: Blizzard's edge untouched")

    swipeStub.showBuffEdge = false
    cd = NewCd()
    reassertEdge({}, cd, "buff")
    assert(#cd.edges == 1 and cd.edges[1] == false, "showBuffEdge=false: edge hidden")
    swipeStub.showBuffEdge = nil

    swipeStub.showBuffIconSwipe = false
    cd = NewCd()
    reassertEdge({}, cd, "buff")
    assert(#cd.edges == 1 and cd.edges[1] == false, "showBuffIconSwipe=false: edge hidden")
    swipeStub.showBuffIconSwipe = nil

    cd = NewCd()
    reassertEdge({}, cd, nil)
    assert(#cd.edges == 1 and cd.edges[1] == false,
        "no key: cooldown path still gates on showRechargeEdge")
    swipeStub.showRechargeEdge = nil
end

---------------------------------------------------------------------------
-- 2) Aura-phase owner: key threading + proactive Reassert (real module).
---------------------------------------------------------------------------
local ns2 = {}
-- Task 45f: cdm_reanchor_auraphase.lua routes discarded-result pcall guards
-- through ns.SafeCall. Additive stub (T1d/T1e precedent).
ns2.SafeCall = function(_policy, fn, ...) return pcall(fn, ...) end
ns2.SafeCallMethod = function(_policy, obj, name, ...) return pcall(function(...) return obj[name](obj, ...) end, ...) end
ns2.SafeCallMethodIfPresent = function(_policy, obj, name, ...) if obj == nil then return nil end local okP, m = pcall(function() return obj[name] end) if not okP then return false end if m == nil then return nil end return pcall(m, obj, ...) end
loadChunk("QUI_CDM/cdm/cdm_reanchor_auraphase.lua", "cdm_reanchor_auraphase.lua")("QUI", ns2)
local AP = assert(ns2.CDMReanchorAuraPhase)

local seen = {}
local hookedFns = {}
local ap = AP.New({
    hooksecurefunc = function(_, method, fn) hookedFns[method] = fn end,
    securecall = function(fn, ...) return fn(...) end,
    reassertColor = function(_, _, key) seen[#seen + 1] = { what = "color", key = key } end,
    reassertEdge = function(_, _, key) seen[#seen + 1] = { what = "edge", key = key } end,
})
local cdw = {
    SetSwipeColor = function() end,
    SetCooldown = function() end,
    SetDrawEdge = function() end,
}
local liveFrame = {
    GetCooldownFrame = function() return cdw end,
    Icon = { SetDesaturated = function() end },
}
ap:Hook(liveFrame, "buff")

-- Hook path: Blizzard's SetSwipeColor write reasserts with the container key.
seen = {}
assert(hookedFns.SetSwipeColor, "SetSwipeColor hook installed")()
assert(seen[1] and seen[1].what == "color" and seen[1].key == "buff",
    "SetSwipeColor hook threads the container key into reassertColor")

assert(hookedFns.SetCooldown == nil, "native SetCooldown hook is not installed")

seen = {}
assert(hookedFns.SetDesaturated == nil, "native SetDesaturated hook is not installed")

-- Proactive path: Reassert fires colour + edge with NO Blizzard write at all.
seen = {}
ap:Reassert(liveFrame)
assert(#seen == 2 and seen[1].what == "color" and seen[2].what == "edge",
    "Reassert proactively drives colour + edge")
assert(seen[1].key == "buff" and seen[2].key == "buff",
    "Reassert threads the container key")

do
    local swipe
    local inst = AP.New({
        securecall = function(fn, ...) return fn(...) end,
        reassertSwipe = function(_, _, _, show) swipe = show end,
    })
    local cd = {
        SetSwipeColor = function() end,
        SetDrawEdge = function() end,
        GetDrawSwipe = function() return false end,
    }
    inst:Reassert({ GetCooldownFrame = function() return cd end })
    assert(swipe == false, "Reassert forwards the readable native swipe state")
end

-- Reassert on a frame with no cooldown widget: harmless no-op.
seen = {}
ap:Reassert({})
assert(#seen == 0, "Reassert without a cooldown widget is a no-op")

-- Hook without a key (legacy callers): callbacks receive nil key.
local ap2 = AP.New({
    hooksecurefunc = function(_, method, fn) hookedFns[method] = fn end,
    securecall = function(fn, ...) return fn(...) end,
    reassertColor = function(_, _, key) seen[#seen + 1] = { key = key } end,
})
ap2:Hook({ GetCooldownFrame = function() return {
    SetSwipeColor = function() end,
    SetCooldown = function() end,
    SetDrawEdge = function() end,
} end })
seen = {}
hookedFns.SetSwipeColor()
assert(#seen == 1 and seen[1].key == nil, "keyless Hook: callbacks see a nil key")

print("OK: cdm_reanchor_auraphase_buffswipe_test")
