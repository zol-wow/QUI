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
    local calls = 0
    local hooked = {}
    local inst
    local cd = {
        SetSwipeColor = function() end,
        SetCooldown = function() end,
        SetCooldownFromDurationObject = function() end,
        SetUseAuraDisplayTime = function() end,
    }
    inst = M.New({
        securecall = function(fn, ...) return fn(...) end,
        hooksecurefunc = function(_, method, fn) hooked[method] = fn end,
        rearmNativeCooldown = function()
            calls = calls + 1
            inst:OnNativeCooldownPush({}, cd)
        end,
    })
    local frame = { GetCooldownFrame = function() return cd end }
    inst:Hook(frame, "essential", { type = "spell", spellID = 1233448 })
    assert(hooked.SetSwipeColor and hooked.SetCooldown
        and hooked.SetCooldownFromDurationObject and hooked.SetUseAuraDisplayTime,
        "native cooldown push hooks installed")
    hooked.SetSwipeColor()
    assert(calls == 0, "swipe repaint does not re-arm without a timing push")
    hooked.SetCooldown()
    assert(calls == 1, "native cooldown re-arm is re-entry guarded")
    inst:Reassert(frame)
    assert(calls == 2, "Reassert re-arms the native cooldown once")
end

do
    local hooked = {}
    local inst
    local cd = {
        SetCooldown = function() end,
        SetUseAuraDisplayTime = function() end,
    }
    inst = M.New({
        securecall = function(fn, ...) return fn(...) end,
        hooksecurefunc = function(_, method, fn) hooked[method] = fn end,
        rearmNativeCooldown = function() end,
    })
    local frame = { GetCooldownFrame = function() return cd end }
    inst:Hook(frame, "essential", { type = "spell", spellID = 1233448 })
    hooked.SetUseAuraDisplayTime(cd, true)
    assert(inst._nativeAuraActive[cd] == true,
        "native aura timing marks the cooldown as aura-active")
    inst._nativeRearmReentry[cd] = true
    hooked.SetUseAuraDisplayTime(cd, false)
    inst._nativeRearmReentry[cd] = false
    assert(inst._nativeAuraActive[cd] == true,
        "addon re-arm does not discard native aura eligibility")
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
