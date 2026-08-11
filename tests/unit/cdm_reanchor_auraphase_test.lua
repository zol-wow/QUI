-- tests/unit/cdm_reanchor_auraphase_test.lua
-- Run: lua tests/unit/cdm_reanchor_auraphase_test.lua
-- Locks the hook contract of the re-anchor swipe colour owner.
-- :Hook installs SetSwipeColor / SetDrawEdge / SetCooldown post-hooks (never
-- RefreshSpellCooldownInfo). :OnSwipeColor -> reassertColor re-asserts the QUI
-- colour from non-secret state; :OnCooldownSet re-asserts AFTER Blizzard's
-- timing write so the aura-phase-off re-bind survives the refresh.

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
    assert(hooked["RefreshSpellCooldownInfo"] == nil,
        "G13: still NEVER hooks RefreshSpellCooldownInfo (secret-value taint)")
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

-- Timing post-hook: :Hook ALSO installs a SetCooldown hook. Blizzard's refresh
-- recolours BEFORE it re-binds timing (CooldownViewer.lua:1166 vs :1169), so the
-- aura-phase-off re-bind must re-assert from the LAST timing write to survive.
-- Desat post-hook: :Hook ALSO installs a SetDesaturated hook on the icon TEXTURE
-- (frame.Icon): RefreshData writes desaturation AFTER the timing refresh
-- (:1269 vs :1271), so the aura-phase-off saturation must re-assert from there.
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
        reassertDesat = function() end,
        isAuraPhaseEnabled = function() return true end,
    })
    local frame = { GetCooldownFrame = function() return cd end, Icon = tex }
    inst:Hook(frame)
    assert(hooked["SetCooldown"] == true, "Hook must install a SetCooldown timing post-hook")
    assert(texHooked["SetDesaturated"] == true,
        "Hook must install a SetDesaturated post-hook on the icon texture")
    assert(hooked["RefreshSpellCooldownInfo"] == nil,
        "still NEVER hooks RefreshSpellCooldownInfo (secret-value taint)")
end

-- :OnCooldownSet -> reassertColor once, guarded against BOTH its own re-fire and
-- the colour hook: the reassert's SetSwipeColor re-fires OnSwipeColor, which must
-- no-op while the timing re-assert is in flight (no double restyle per refresh).
do
    local calls = 0
    local inst
    local deps = {
        reassertColor = function(f, cdw)
            calls = calls + 1
            inst:OnSwipeColor(f, cdw)   -- simulate the reassert's SetSwipeColor re-firing the colour hook
            inst:OnCooldownSet(f, cdw)  -- and a nested SetCooldown re-fire
        end,
    }
    inst = M.New(deps)
    local f, cdw = {}, {}
    inst:OnCooldownSet(f, cdw)
    assert(calls == 1, "OnCooldownSet calls reassertColor once (both guards held)")
    inst:OnCooldownSet(f, cdw)
    assert(calls == 2, "guards clear after each call so later refreshes re-assert")
    inst:OnCooldownSet(f, nil)
    assert(calls == 2, "nil cooldown frame must be a no-op")
end

-- :OnDesaturated -> reassertDesat once (re-entry guarded so the reassert's own
-- boolean SetDesaturated fallback, which re-fires the hook, cannot recurse).
do
    local calls = 0
    local inst
    local deps = {
        reassertDesat = function(f, texArg)
            calls = calls + 1
            inst:OnDesaturated(f, texArg)  -- simulate the fallback's SetDesaturated re-firing
        end,
    }
    inst = M.New(deps)
    local f, tex = {}, {}
    inst:OnDesaturated(f, tex)
    assert(calls == 1, "OnDesaturated calls reassertDesat once (re-entry guarded)")
    inst:OnDesaturated(f, tex)
    assert(calls == 2, "guard clears after each call so later re-asserts fire")
    inst:OnDesaturated(f, nil)
    assert(calls == 2, "nil texture must be a no-op")
end

print("OK: cdm_reanchor_auraphase_test")
