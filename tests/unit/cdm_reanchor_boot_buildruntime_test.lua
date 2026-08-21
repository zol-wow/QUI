-- tests/unit/cdm_reanchor_boot_buildruntime_test.lua
-- Run: lua tests/unit/cdm_reanchor_boot_buildruntime_test.lua
local ns = {}
local secretGCD = {}
local probedSecretGCD = false
_G.issecretvalue = function(value)
    if value == secretGCD then
        probedSecretGCD = true
        return true
    end
    return false
end
-- Task 45f: cdm_reanchor*.lua route discarded-result pcall guards through
-- ns.SafeCall. Additive stub (T1d/T1e precedent) — bare pcall passthrough.
ns.SafeCall = function(_policy, fn, ...) return pcall(fn, ...) end
ns.SafeCallMethod = function(_policy, obj, name, ...) return pcall(function(...) return obj[name](obj, ...) end, ...) end
ns.SafeCallMethodIfPresent = function(_policy, obj, name, ...) if obj == nil then return nil end local okP, m = pcall(function() return obj[name] end) if not okP then return false end if m == nil then return nil end return pcall(m, obj, ...) end
local loadChunk = dofile("tests/helpers/load_cdm_consolidated_chunk.lua")
-- load the real bridge + wiring + runtime + boot into one ns
loadChunk("QUI_CDM/cdm/cdm_reanchor.lua", "cdm_reanchor.lua")("QUI", ns)
loadChunk("QUI_CDM/cdm/cdm_reanchor_wiring.lua", "cdm_reanchor_wiring.lua")("QUI", ns)
loadChunk("QUI_CDM/cdm/cdm_reanchor_runtime.lua", "cdm_reanchor_runtime.lua")("QUI", ns)
loadChunk("QUI_CDM/cdm/cdm_reanchor_boot.lua", "cdm_reanchor_boot.lua")("QUI", ns)
local B = assert(ns.CDMReanchorBoot)
assert(type(B.BuildRuntime) == "function", "BuildRuntime is a function")

-- recorder raw methods so the real bridge's Claim/Sink are observable
local setpoints, alphas = {}, {}
local raw = {
    ClearAllPoints = function() end,
    SetPoint = function(f, p, rel, rp, x, y) setpoints[#setpoints+1] = { f = f, rel = rel, x = x, y = y } end,
    SetAlpha = function(f, a) alphas[#alphas+1] = { f = f, a = a } end,
}

-- a live viewer with two item frames: cd 11 (curated) and cd 99 (not curated)
local fMatch, fDrop = {
    GetCooldownID = function() return 11 end,
    GetCooldownInfo = function() return { hasAura = true } end,
    HasVisualDataSource_Charges = function() return true end,
}, { GetCooldownID = function() return 99 end }
local viewer = { GetItemFrames = function() return { fMatch, fDrop } end }
local container = { SetSize = function() end }

-- curated: one entry resolving (via index) to cooldownID 11
local curatedEntry = { spellID = 500, _assignedRow = 1 }
local ownedAdds = {}
local releasedIcons = {}
local releasedKeys = {}
local additionalList = {}
local clickSlot = { SetSize = function() end }   -- QUI-owned secure click host for the matched slot
local shellPositioned = false
local clickSlotPositioned = false
local clickOverlayCall
local shellLifecycle = {}

local env = {
    CDMReanchor = ns.CDMReanchor,
    CDMReanchorWiring = ns.CDMReanchorWiring,
    CDMReanchorRuntime = ns.CDMReanchorRuntime,
    uiParent = { uiparent = true },
    index = {
        IsUsableID = function(id) return type(id) == "number" and id > 0 end,
        Get = function(id) if id == 500 then return { cooldownID = 11 } end end,
    },
    -- Combat-defer wiring: canMutate mirrors realenv canMutateProtectedShells --
    -- true OOC/init-safe-window. Stub always-true so no test behavior changes;
    -- captured below via the CDMReanchorRuntime.New wrapper to prove it threads
    -- through to the runtime deps.
    canMutate = function() return true end,
    getContainer = function() return container end,
    getCurated = function() return { curatedEntry } end,
    getSettings = function() return { row1 = { iconCount = 4, iconSize = 40 } } end,
    -- buildLayout stub: echo the wrappers as placements (1 entry here)
    buildLayout = function(settings, icons, opts)
        local p = {}
        for i = 1, #icons do
            p[i] = { icon = icons[i], x = i, y = -i, w = 30, h = 20, rowConfig = { size = 30 } }
        end
        return { placements = p, metrics = { iconWidth = 40, totalHeight = 40 } }
    end,
    pixelRound = function(v) return v end,
    -- Owned-icon stubs need the positionOwned surface (GetScale/ClearAllPoints/
    -- SetPoint/Show) for the additional-entry release block at the end.
    -- Acquire/release record the containerKey they are handed: realenv uses it
    -- for Factory pool membership (content refresh walks GetIconPool(key)).
    acquireIcon = function(c, e, containerKey)
        local o = {
            owned = e,
            acquiredKey = containerKey,
            GetScale = function() return 1 end,
            ClearAllPoints = function() end,
            SetPoint = function() end,
            Show = function() end,
        }
        ownedAdds[#ownedAdds+1] = o
        return o
    end,
    releaseIcon = function(icon, containerKey)
        releasedIcons[#releasedIcons+1] = icon
        releasedKeys[#releasedKeys+1] = containerKey
    end,
    resolveAdditional = function() return additionalList end,
    -- Native deps: matched curated entries direct-anchor the live Blizzard frame
    -- to the container, then position a separate secure click host over the slot.
    mintShell = function() error("native matched entries must not mint shells") end,
    positionShell = function() shellPositioned = true end,
    positionClickSlot = function(containerArg, liveArg, entryArg, keyArg)
        clickSlotPositioned = true
        clickSlot.container = containerArg
        clickSlot.live = liveArg
        clickSlot.entry = entryArg
        clickSlot.key = keyArg
        return clickSlot
    end,
    updateClickOverlay = function(hostArg, entryArg, viewerTypeArg)
        clickOverlayCall = { host = hostArg, entry = entryArg, viewerType = viewerTypeArg }
    end,
    beginShellPass = function(c) shellLifecycle[#shellLifecycle + 1] = { "begin", c } end,
    endShellPass = function(c) shellLifecycle[#shellLifecycle + 1] = { "end", c } end,
    resetShells = function() error("BuildRuntime should pass begin/end shell hooks") end,
    -- inject recorder raw into the bridge via a wrapper: BuildRuntime uses CDMReanchor.New;
    -- we override by passing our own bridge through a shim below instead.
}

-- Shim CDMReanchor so the bridge uses our recorder raw + direct securecall
env.CDMReanchor = {
    New = function(opts)
        opts = opts or {}
        opts.raw = raw
        opts.securecall = function(fn, ...) return fn(...) end
        opts.hooksecurefunc = function() end
        return ns.CDMReanchor.New(opts)
    end,
}

-- need GetViewerForKey to return our viewer: inject via wiring shim
env.CDMReanchorWiring = {
    New = function(opts)
        local w = ns.CDMReanchorWiring.New(opts)
        w.GetViewerForKey = function() return viewer end
        return w
    end,
}

-- Combat-defer wiring: capture the deps BuildRuntime hands to CDMReanchorRuntime.New
-- so we can assert canMutate threads through, without altering the real runtime.
local capturedRuntimeDeps
do
    local realNew = env.CDMReanchorRuntime.New
    env.CDMReanchorRuntime = {
        New = function(d)
            capturedRuntimeDeps = d
            return realNew(d)
        end,
    }
end

-- G13: capture the auraPhase deps so we can exercise the reassertEdge closure that
-- BuildRuntime wires (re-hides the recharge draw-edge when showRechargeEdge is off).
local capturedAuraDeps
ns.CDMReanchorAuraPhase = { New = function(deps) capturedAuraDeps = deps; return { Hook = function() end } end }
local swipeStub = { showRechargeEdge = false, showCooldownSwipe = true }
ns._OwnedSwipe = { GetSettings = function() return swipeStub end }
local facade = B.BuildRuntime(env)
assert(type(facade) == "table" and facade.bridge and facade.wiring and facade.runtime, "facade has bridge/wiring/runtime")
assert(type(facade.RefreshBuiltin) == "function", "facade:RefreshBuiltin exists")
assert(type(facade.RefreshBuiltins) == "function", "facade:RefreshBuiltins exposes atomic placement refresh")
assert(type(facade.GetPlacementsForFrame) == "function", "facade exposes placement consumers")

local count = facade:RefreshBuiltin("essential")
assert(count == 1, "one curated entry assembled (matched)")
-- The matched frame (cd 11) is direct-anchored to the QUI container; the other
-- (cd 99) is sunk (alpha 0).
local overlaidMatch, sunkDrop = false, false
for _, s in ipairs(setpoints) do if s.f == fMatch and s.rel == container then overlaidMatch = true end end
for _, a in ipairs(alphas) do if a.f == fDrop and a.a == 0 then sunkDrop = true end end
assert(not shellPositioned, "matched native slot does not position a QUI chrome shell")
assert(clickSlotPositioned and clickSlot.live == fMatch and clickSlot.entry == curatedEntry,
    "matched native slot positions a separate click host")
assert(clickOverlayCall and clickOverlayCall.host == clickSlot and clickOverlayCall.entry == curatedEntry
    and clickOverlayCall.viewerType == "essential",
    "matched click host receives secure click overlay setup through boot deps")
assert(#shellLifecycle == 2 and shellLifecycle[1][1] == "begin" and shellLifecycle[1][2] == container
    and shellLifecycle[2][1] == "end" and shellLifecycle[2][2] == container,
    "boot wires shell generation lifecycle through to runtime")
assert(overlaidMatch, "curated-matched Blizzard frame direct-anchored to the container")
assert(sunkDrop, "non-curated Blizzard frame sunk (alpha 0)")

-- G13: BuildRuntime wires a reassertEdge dep into the auraPhase. It hides the recharge
-- draw-edge (SetDrawEdge(false)) when the owned-icon showRechargeEdge setting is off,
-- and leaves Blizzard's edge alone when it is on -- non-secret swipe settings only.
assert(capturedAuraDeps and type(capturedAuraDeps.reassertEdge) == "function",
    "G13: auraPhase receives a reassertEdge dep")
assert(type(capturedAuraDeps.reassertColor) == "function",
    "auraPhase still receives reassertColor")
assert(type(capturedAuraDeps.reassertSwipe) == "function",
    "auraPhase receives reassertSwipe")
assert(type(capturedAuraDeps.requestAuraPhaseRefresh) == "function",
    "auraPhase receives the safe aura-phase refresh request")
swipeStub.showCooldownIconAuraPhase = false
local nativeAuraFrame = {
    cooldownUseAuraDisplayTime = true,
    GetCooldownInfo = function() return { hasAura = true } end,
}
assert(capturedRuntimeDeps.shouldReplaceNativeAuraPhase(nativeAuraFrame,
        { type = "spell" }, "essential") == true,
    "disabled aura phase uses a QUI-owned replacement frame")
swipeStub.showCooldownIconAuraPhase = true
local cdSecretGCD = { SetDrawSwipe = function() end }
capturedAuraDeps.reassertSwipe({ isOnGCD = secretGCD }, cdSecretGCD, "essential", true)
assert(probedSecretGCD, "reassertSwipe probes secret isOnGCD before comparing it")
local edgeCalls = {}
local cdEdge = { SetDrawEdge = function(_, v) edgeCalls[#edgeCalls+1] = v end }
swipeStub.showRechargeEdge = false
capturedAuraDeps.reassertEdge({}, cdEdge)
assert(#edgeCalls == 1 and edgeCalls[1] == false,
    "G13: reassertEdge hides the edge (SetDrawEdge(false)) when showRechargeEdge is off")
swipeStub.showRechargeEdge = true
capturedAuraDeps.reassertEdge({}, cdEdge)
assert(#edgeCalls == 1, "G13: reassertEdge leaves Blizzard's edge when showRechargeEdge is on")

-- Ghost owned-icon release: BuildRuntime must thread env.releaseIcon into the
-- runtime's releaseOwned dep so each pass releases the PREVIOUS pass's minted
-- owned icons (frameless/additional entries) instead of abandoning them Show()n
-- at stale slots.
additionalList[1] = { spellID = 900, _assignedRow = 1 }
local ownedBefore = #ownedAdds
facade:RefreshBuiltin("essential")
assert(#ownedAdds == ownedBefore + 1, "additional entry mints an owned icon")
local firstPassIcon = ownedAdds[#ownedAdds]
facade:RefreshBuiltin("essential")
assert(#ownedAdds == ownedBefore + 2, "next pass re-mints the additional entry's icon")
local sawRelease = false
for _, r in ipairs(releasedIcons) do
    if r == firstPassIcon then sawRelease = true end
end
assert(sawRelease,
    "boot threads env.releaseIcon -> releaseOwned: the previous pass's owned icon is released")

-- POOL MEMBERSHIP threading: mintOwned must hand the containerKey through to
-- env.acquireIcon (realenv registers the icon in Factory pool[key] so the
-- content-refresh loops pick it up), and the runtime's release must hand the
-- key back to env.releaseIcon (realenv removes it from the pool).
assert(firstPassIcon.acquiredKey == "essential",
    "boot passes the containerKey to acquireIcon for pool membership")
assert(#releasedKeys > 0 and releasedKeys[#releasedKeys] == "essential",
    "runtime release passes the containerKey back to releaseIcon")

-- Combat-defer wiring: BuildRuntime threads env.canMutate into the runtime and
-- exposes DrainPendingCombatRefresh on the boot table (PLAYER_REGEN_ENABLED drain).
assert(capturedRuntimeDeps and capturedRuntimeDeps.canMutate ~= nil,
    "runtime receives the canMutate dep")
assert(type(facade.DrainPendingCombatRefresh) == "function",
    "boot exposes DrainPendingCombatRefresh")
-- calling it with no deferred keys is a safe no-op
facade:DrainPendingCombatRefresh()

swipeStub.showCooldownIconAuraPhase = false
local shouldReplace = capturedRuntimeDeps.shouldReplaceNativeAuraPhase
local nativeAuraFrame = {
    cooldownUseAuraDisplayTime = false,
    GetCooldownInfo = function() return { hasAura = true } end,
}
for _, entryType in ipairs({ "item", "slot", "trinket", "consumable", "macro" }) do
    assert(shouldReplace(nativeAuraFrame, { type = entryType }, "essential") == false,
        entryType .. "-backed native frame remains native")
end
assert(shouldReplace(nativeAuraFrame, { type = "spell" }, "essential") == false,
    "ordinary spell native frame remains native")
assert(shouldReplace({ cooldownUseAuraDisplayTime = true,
        GetCooldownInfo = function() return { hasAura = false } end },
        { type = "spell" }, "essential") == true,
    "current native aura phase uses an owned replacement when disabled")
assert(shouldReplace({ cooldownUseAuraDisplayTime = true,
        GetCooldownInfo = function() return { hasAura = true, flags = 1 } end },
        { type = "spell" }, "essential") == true,
    "stable eligibility metadata does not block owned replacement")
assert(shouldReplace({}, { type = "item" }, "buff") == false,
    "item-backed BuffIcon entry remains native")
assert(shouldReplace(nativeAuraFrame, { type = "spell", kind = "aura" }, "essential") == false,
    "explicit aura entry remains native")
swipeStub.showCooldownIconAuraPhase = true
assert(shouldReplace(nativeAuraFrame, { type = "spell" }, "essential") == false,
    "native aura frame stays native when aura phase is enabled")

print("OK: cdm_reanchor_boot_buildruntime_test")
