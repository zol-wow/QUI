-- tests/unit/cdm_blizz_mirror_cooldown_capture_test.lua
-- Run: lua tests/unit/cdm_blizz_mirror_cooldown_capture_test.lua
--
-- Locks the hook-synchronous capture of the cooldown DurationObject passed
-- to SetCooldownFromDurationObject for non-aura cooldownIDs. The capture
-- exists so the resolver can avoid polling C_Spell.GetSpellCooldownDuration,
-- which lags hook events during GCD overlays on resource-driven specs.

local function noop() end

function hooksecurefunc(owner, method, hook)
    local original = owner[method] or noop
    owner[method] = function(self, ...)
        original(self, ...)
        hook(self, ...)
    end
end

function InCombatLockdown() return false end
function GetTime() return 100 end
function wipe(tbl)
    for key in pairs(tbl) do tbl[key] = nil end
end
function CreateFrame()
    return {
        RegisterEvent = noop,
        RegisterUnitEvent = noop,
        SetScript = noop,
    }
end

local cooldownChild = {
    cooldownID = 70001,
    isActive = false,
    Cooldown = {
        SetCooldown = noop,
        SetCooldownFromDurationObject = noop,
        SetCooldownFromExpirationTime = noop,
        SetCooldownDuration = noop,
        SetCooldownUNIX = noop,
        Clear = noop,
    },
    Show = noop,
    Hide = noop,
}
cooldownChild.Cooldown.GetParent = function() return cooldownChild end

local auraChild = {
    cooldownID = 70002,
    isActive = true,
    Cooldown = {
        SetCooldown = noop,
        SetCooldownFromDurationObject = noop,
        SetCooldownFromExpirationTime = noop,
        SetCooldownDuration = noop,
        SetCooldownUNIX = noop,
        Clear = noop,
    },
    Show = noop,
    Hide = noop,
}
auraChild.Cooldown.GetParent = function() return auraChild end

EssentialCooldownViewer = {
    GetChildren = function() return cooldownChild end,
}
UtilityCooldownViewer = { GetChildren = function() end }
BuffIconCooldownViewer = {
    GetChildren = function() return auraChild end,
}
BuffBarCooldownViewer = { GetChildren = function() end }

C_CooldownViewer = {
    GetCooldownViewerCategorySet = function(category)
        if category == 0 then return { 70001 } end
        if category == 2 then return { 70002 } end
        return {}
    end,
    GetCooldownViewerCooldownInfo = function(cooldownID)
        if cooldownID == 70001 then
            return {
                cooldownID = 70001,
                spellID = 600001,
                overrideSpellID = 600001,
                selfAura = nil,
                hasAura = false,
                charges = false,
                isKnown = true,
            }
        end
        if cooldownID == 70002 then
            return {
                cooldownID = 70002,
                spellID = 600002,
                overrideSpellID = 600002,
                selfAura = true,
                hasAura = true,
                charges = false,
                isKnown = true,
            }
        end
    end,
}

local ns = {
    Helpers = {
        IsSecretValue = function() return false end,
        IsAuraOwnedByPlayerOrPet = function() return true end,
    },
}

local loadChunk = dofile("tests/helpers/load_cdm_consolidated_chunk.lua")
loadChunk("QUI_CDM/cdm/cdm_sources.lua", "cdm_sources.lua")("QUI", ns)
assert(loadfile("QUI_CDM/cdm/cdm_blizz_mirror.lua"))("QUI", ns)

ns.CDMBlizzMirror.ForceRescan()

local fakeDurObj = { token = "fake-cooldown-durObj" }
local secondDurObj = { token = "fake-cooldown-durObj-second" }
local fakeAuraDurObj = { token = "fake-aura-durObj" }

-- ASSERTION 1: SCFDO non-aura branch captures durObj into s.cooldownDurObj.
cooldownChild.Cooldown:SetCooldownFromDurationObject(fakeDurObj, false)
local state = assert(ns.CDMBlizzMirror.GetStateByCooldownID(70001, "essential"),
    "essential cooldown state missing after SCFDO")
assert(state.cooldownDurObj == fakeDurObj,
    "SCFDO non-aura branch must capture the durObj into state.cooldownDurObj "
    .. "(got " .. tostring(state.cooldownDurObj) .. ")")
assert(state.cooldownDurObjSource == "live-cooldown",
    "captured cooldown durObj must be tagged source=live-cooldown "
    .. "(got " .. tostring(state.cooldownDurObjSource) .. ")")

-- ASSERTION 2: Repeat SCFDO with a different durObj overwrites (no lanes).
cooldownChild.Cooldown:SetCooldownFromDurationObject(secondDurObj, false)
state = assert(ns.CDMBlizzMirror.GetStateByCooldownID(70001, "essential"),
    "essential cooldown state missing after second SCFDO")
assert(state.cooldownDurObj == secondDurObj,
    "subsequent SCFDO must overwrite the captured durObj (got "
    .. tostring(state.cooldownDurObj) .. ")")

-- ASSERTION 3: Cooldown:Clear on non-aura cdID invalidates the capture.
cooldownChild.Cooldown:Clear()
state = assert(ns.CDMBlizzMirror.GetStateByCooldownID(70001, "essential"),
    "essential cooldown state missing after Clear")
assert(state.cooldownDurObj == nil,
    "Cooldown:Clear must invalidate s.cooldownDurObj on non-aura cdIDs "
    .. "(got " .. tostring(state.cooldownDurObj) .. ")")
assert(state.cooldownDurObjSource == nil,
    "Cooldown:Clear must also clear s.cooldownDurObjSource "
    .. "(got " .. tostring(state.cooldownDurObjSource) .. ")")

-- ASSERTION 4: SCFDO on an aura-category cdID does NOT write cooldownDurObj.
-- The aura branch owns aura attribution; the cooldown durObj slot is for
-- non-aura cooldown swipes only. To prove isolation, re-prime the non-aura
-- state first, then exercise the aura branch and verify (a) the aura state's
-- cooldownDurObj stays nil and (b) the unrelated non-aura state is untouched.
local primeDurObj = { token = "prime-cooldown-durObj" }
cooldownChild.Cooldown:SetCooldownFromDurationObject(primeDurObj, false)
state = assert(ns.CDMBlizzMirror.GetStateByCooldownID(70001, "essential"),
    "essential state missing after re-prime")
assert(state.cooldownDurObj == primeDurObj,
    "re-prime sanity check failed (got " .. tostring(state.cooldownDurObj) .. ")")

auraChild.Cooldown:SetCooldownFromDurationObject(fakeAuraDurObj, false)

local auraState = assert(ns.CDMBlizzMirror.GetStateByCooldownID(70002, "buff"),
    "buff aura state missing after SCFDO")
assert(auraState.cooldownDurObj == nil,
    "aura-category SCFDO must NOT populate s.cooldownDurObj on the aura state "
    .. "(slot is for non-aura cooldown swipes only; got "
    .. tostring(auraState.cooldownDurObj) .. ")")
assert(auraState.cooldownDurObj ~= fakeAuraDurObj,
    "aura-category SCFDO must not leak the inbound durObj into cooldownDurObj")

-- ASSERTION 5: Cross-cdID isolation. The aura-branch SCFDO must not have
-- touched the unrelated non-aura cdID's cooldownDurObj slot.
state = assert(ns.CDMBlizzMirror.GetStateByCooldownID(70001, "essential"),
    "essential state missing after aura-branch SCFDO")
assert(state.cooldownDurObj == primeDurObj,
    "aura-branch SCFDO must not modify unrelated cdID's cooldownDurObj "
    .. "(expected " .. tostring(primeDurObj)
    .. ", got " .. tostring(state.cooldownDurObj) .. ")")

print("OK: cdm_blizz_mirror_cooldown_capture_test")
