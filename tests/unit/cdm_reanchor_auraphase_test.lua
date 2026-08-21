-- tests/unit/cdm_reanchor_auraphase_test.lua
-- Run: lua tests/unit/cdm_reanchor_auraphase_test.lua
-- Locks the hook contract of the re-anchor swipe colour owner.

local ns = {}
-- Task 45f: cdm_reanchor_auraphase.lua routes discarded-result pcall guards
-- through ns.SafeCall. Additive stub (T1d/T1e precedent).
ns.SafeCall = function(_policy, fn, ...) return pcall(fn, ...) end
ns.SafeCallMethod = function(_policy, obj, name, ...) return pcall(function(...) return obj[name](obj, ...) end, ...) end
ns.SafeCallMethodIfPresent = function(_policy, obj, name, ...) if obj == nil then return nil end local okP, m = pcall(function() return obj[name] end) if not okP then return false end if m == nil then return nil end return pcall(m, obj, ...) end
assert(loadfile("QUI_CDM/cdm/cdm_reanchor_auraphase.lua"))("QUI", ns)
local M = assert(ns.CDMReanchorAuraPhase, "CDMReanchorAuraPhase not exported")

-- Hook installs SetSwipeColor ONLY, never RefreshSpellCooldownInfo
do
    local hooked = {}
    local inst = M.New({
        securecall = function(fn, ...) return fn(...) end,
        hooksecurefunc = function(obj, method) hooked[method] = true end,
        reassertColor = function() end,
        isAuraPhaseEnabled = function() return true end,
    })
    local cd = { SetSwipeColor = function() end }
    local frame = {
        GetCooldownFrame = function() return cd end,
        RefreshSpellCooldownInfo = function() end,
    }
    inst:Hook(frame)
    assert(hooked["SetSwipeColor"] == true,
        "Hook must install a SetSwipeColor hook")
    assert(hooked["RefreshSpellCooldownInfo"] == nil,
        "Hook must NOT install a RefreshSpellCooldownInfo hook (secret-value taint)")
end

-- SetSwipeColor re-assert hook: calls reassertColor, re-entry guarded so the
-- reassert's own SetSwipeColor (which re-fires the hook) cannot recurse.
do
    local calls = 0
    local inst
    local deps = {
        reassertColor = function(f, cdw)
            calls = calls + 1
            inst:OnSwipeColor(f, cdw)  -- simulate the SetSwipeColor re-fire
        end,
    }
    inst = M.New(deps)
    local f = { cooldownUseAuraDisplayTime = false }
    local cdw = {}
    inst:OnSwipeColor(f, cdw)
    assert(calls == 1, "OnSwipeColor must call reassertColor once (re-entry guarded)")
    inst:OnSwipeColor(f, cdw)
    assert(calls == 2, "guard must clear after each call so later re-colours re-assert")
    inst:OnSwipeColor(f, nil)
    assert(calls == 2, "nil cooldown frame must be a no-op")
end

-- G13: :Hook ALSO installs a parallel SetDrawEdge hook so Blizzard's per-refresh
-- recharge-edge re-assert (cooldownShowDrawEdge=true for charge spells) can be
-- re-hidden. SetDrawEdge is AllowedWhenTainted (taint-safe, same class as SetSwipeColor).
do
    local hooked = {}
    local inst = M.New({
        securecall = function(fn, ...) return fn(...) end,
        hooksecurefunc = function(obj, method) hooked[method] = true end,
        reassertColor = function() end,
        reassertEdge = function() end,
        isAuraPhaseEnabled = function() return true end,
    })
    local cd = { SetSwipeColor = function() end, SetDrawEdge = function() end }
    local frame = { GetCooldownFrame = function() return cd end }
    inst:Hook(frame)
    assert(hooked["SetSwipeColor"] == true, "G13: still installs the SetSwipeColor hook")
    assert(hooked["SetDrawEdge"] == true, "G13: Hook must also install a SetDrawEdge hook")
    cd.SetDrawSwipe = function() end
    inst:Hook({ GetCooldownFrame = function() return cd end })
    assert(hooked["SetDrawSwipe"] == true, "G13: Hook must also install a SetDrawSwipe hook")
    assert(hooked["RefreshSpellCooldownInfo"] == nil,
        "G13: still NEVER hooks RefreshSpellCooldownInfo (secret-value taint)")
end

do
    local hooked
    local requested
    local inst = M.New({
        securecall = function(fn, ...) return fn(...) end,
        hooksecurefunc = function(_, method, fn) hooked = fn end,
        requestAuraPhaseRefresh = function(frame, key, show)
            requested = { frame = frame, key = key, show = show }
        end,
    })
    local cd = { SetUseAuraDisplayTime = function() end }
    local frame = {
        cooldownUseAuraDisplayTime = false,
        GetCooldownFrame = function() return cd end,
    }
    inst:Hook(frame, "essential")
    hooked(cd, true)
    assert(requested and requested.frame == frame and requested.key == "essential"
        and requested.show == true,
        "native aura-mode changes request a safe reanchor")
end

do
    local hooks = {}
    local requested = {}
    local inst = M.New({
        securecall = function(fn, ...) return fn(...) end,
        hooksecurefunc = function(_, method, fn) hooks[method] = fn end,
        isAuraPhaseEnabled = function() return false end,
        requestAuraPhaseRefresh = function(_, key, show)
            requested[#requested + 1] = { key = key, show = show }
        end,
    })
    local cd = {
        SetCooldown = function() end,
        SetCooldownFromDurationObject = function() end,
        SetUseAuraDisplayTime = function() end,
    }
    local frame = {
        cooldownUseAuraDisplayTime = true,
        GetCooldownFrame = function() return cd end,
    }
    inst:Hook(frame, "essential")
    hooks.SetCooldown(cd)
    hooks.SetCooldownFromDurationObject(cd)
    assert(#requested == 2 and requested[1].key == "essential"
        and requested[1].show == true,
        "disabled aura phase rechecks native cooldown pushes")
end

do
    local hooks, textureHooks = {}, {}
    local repairs = {}
    local inst
    local texture = {
        SetDesaturated = function() end,
        SetDesaturation = function() end,
    }
    local cd = {
        Clear = function() end,
        SetUseAuraDisplayTime = function() end,
        SetCooldownFromDurationObject = function() end,
    }
    local frame = {
        cooldownInfo = { linkedSpellID = 9001 },
        auraInstanceID = nil,
        wasSetFromAura = false,
        Icon = texture,
        GetCooldownFrame = function() return cd end,
    }
    inst = M.New({
        securecall = function(fn, ...) return fn(...) end,
        hooksecurefunc = function(obj, method, fn)
            if obj == texture then textureHooks[method] = fn else hooks[method] = fn end
        end,
        isNativeCooldownRepairFrame = function(_, key) return key == "essential" end,
        repairStaleLinkedAura = function(f, cdw, entry, reason)
            repairs[#repairs + 1] = { frame = f, cd = cdw, entry = entry, reason = reason }
            inst:OnNativeRepairDriver(f, cdw, reason)
        end,
    })
    local entry = { spellID = 9001 }
    inst:Hook(frame, "essential", entry)
    assert(hooks.Clear and textureHooks.SetDesaturated and textureHooks.SetDesaturation,
        "stale-link repair hooks native Clear and both desaturation drivers")
    hooks.Clear(cd)
    assert(#repairs == 1 and repairs[1].entry == entry and repairs[1].reason == "clear",
        "stale-link repair runs once and is re-entry guarded")
    textureHooks.SetDesaturated(texture)
    textureHooks.SetDesaturation(texture)
    assert(#repairs == 3, "desaturation drivers recheck stale linked state")
    frame.auraInstanceID = 12
    hooks.Clear(cd)
    assert(#repairs == 3, "active aura instance blocks native cooldown repair")
    frame.auraInstanceID = nil
    frame.wasSetFromAura = true
    textureHooks.SetDesaturated(texture)
    assert(#repairs == 3, "native aura ownership blocks native cooldown repair")
end

do
    local repairs = 0
    local inst = M.New({
        isNativeCooldownRepairFrame = function(_, key) return key == "essential" end,
        repairStaleLinkedAura = function() repairs = repairs + 1 end,
    })
    local cd = {}
    local frame = {
        cooldownInfo = { linkedSpellID = 9002 },
        auraInstanceID = nil,
        wasSetFromAura = false,
    }
    inst:Hook(frame, "buff", { spellID = 9002 })
    assert(inst:IsNativeCooldownRepairFrame(frame, "buff") == false,
        "buff frames are excluded from stale-link repair")
    inst:OnNativeRepairDriver(frame, cd, "clear")
    assert(repairs == 0, "excluded frames never invoke stale-link repair")
    frame.cooldownInfo.linkedSpellID = nil
    inst:OnNativeRepairDriver(frame, cd, "clear")
    assert(repairs == 0, "frames without a linked spell are ignored")
end

do
    local hooks = {}
    local requested = {}
    local inst = M.New({
        securecall = function(fn, ...) return fn(...) end,
        hooksecurefunc = function(_, method, fn) hooks[method] = fn end,
        requestAuraPhaseRefresh = function(_, _, show) requested[#requested + 1] = show end,
    })
    local cd = { SetUseAuraDisplayTime = function() end, SetDrawEdge = function() end }
    local frame = {
        cooldownUseAuraDisplayTime = true,
        GetCooldownFrame = function() return cd end,
    }
    inst:Hook(frame, "essential")
    frame.cooldownUseAuraDisplayTime = false
    hooks.SetDrawEdge(cd, false)
    hooks.SetDrawEdge(cd, false)
    assert(#requested == 1 and requested[1] == false,
        "expired edge refresh requests only once when aura mode changes")
end

-- G13: OnDrawEdge -> reassertEdge once (re-entry guarded so the reassert's own
-- SetDrawEdge(false), which re-fires the hook, cannot recurse); nil cd is a no-op.
do
    local calls = 0
    local inst
    local deps = {
        reassertEdge = function(f, cdw)
            calls = calls + 1
            inst:OnDrawEdge(f, cdw)  -- simulate the reassert's SetDrawEdge re-firing the hook
        end,
    }
    inst = M.New(deps)
    local f, cdw = {}, {}
    inst:OnDrawEdge(f, cdw)
    assert(calls == 1, "G13: OnDrawEdge calls reassertEdge once (re-entry guarded)")
    inst:OnDrawEdge(f, cdw)
    assert(calls == 2, "G13: guard clears after each call so later re-asserts fire")
    inst:OnDrawEdge(f, nil)
    assert(calls == 2, "G13: nil cooldown frame must be a no-op")
end

do
    local calls = 0
    local inst
    local deps = {
        reassertSwipe = function(f, cdw, key, show)
            calls = calls + 1
            assert(key == "essential" and show == false, "SetDrawSwipe forwards key and native state")
            inst:OnDrawSwipe(f, cdw, show)
        end,
    }
    inst = M.New(deps)
    local f, cdw = {}, {}
    inst._keyByFrame[f] = "essential"
    inst:OnDrawSwipe(f, cdw, false)
    assert(calls == 1, "OnDrawSwipe must guard re-entry")
    inst:OnDrawSwipe(f, cdw, true)
    assert(calls == 2, "OnDrawSwipe guard must clear after each call")
end

-- Without a native re-arm dependency, timing and desaturation hooks are absent.
do
    local hooked = {}
    local texHooked = {}
    local tex = { SetDesaturated = function() end }
    local cd = { SetSwipeColor = function() end, SetDrawEdge = function() end, SetCooldown = function() end }
    local inst = M.New({
        securecall = function(fn, ...) return fn(...) end,
        hooksecurefunc = function(obj, method)
            if obj == tex then texHooked[method] = true else hooked[method] = true end
        end,
        reassertColor = function() end,
        reassertEdge = function() end,
        isAuraPhaseEnabled = function() return true end,
    })
    local frame = { GetCooldownFrame = function() return cd end, Icon = tex }
    inst:Hook(frame)
    assert(hooked["SetCooldown"] == nil,
        "without a re-arm dependency, no native timing hook is installed")
    assert(texHooked["SetDesaturated"] == nil,
        "Hook must not install an untainted-only SetDesaturated hook")
    assert(hooked["RefreshSpellCooldownInfo"] == nil,
        "still NEVER hooks RefreshSpellCooldownInfo (secret-value taint)")
end

print("OK: cdm_reanchor_auraphase_test")
