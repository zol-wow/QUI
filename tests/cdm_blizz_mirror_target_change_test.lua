-- tests/cdm_blizz_mirror_target_change_test.lua
-- Run: lua tests/cdm_blizz_mirror_target_change_test.lua
--
-- Regression guard: PLAYER_TARGET_CHANGED must preserve the cooldown lane
-- of any mirror state stamped with auraUnit == "target".
--
-- Historical bug (pre-2026-05-11): ClearMirrorAuraState called
-- ClearAllDurationLanes, which wiped every lane (cooldown / gcd / totem
-- / resource) along with the aura lane. RefreshChildSemanticState's
-- selfAura==false fallback stamps auraUnit="target" on ANY Essential /
-- Utility cooldown whose info.selfAura is false (target-debuff spells:
-- Soul Reaper, Reaper's Mark, Festering Wound, etc.). On target change,
-- the inline loop iterated those states and called ClearMirrorAuraState,
-- which then nuked the cooldown lane and erased the live swipe even
-- though the player was still on cooldown.
--
-- This test sets up that exact scenario (Essential cooldown viewer entry
-- with selfAura=false → auraUnit gets stamped "target" during ForceRescan;
-- SetCooldownFromDurationObject populates the cooldown lane), then calls
-- HandlePlayerTargetChanged and asserts the cooldown lane survives.

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
    for key in pairs(tbl) do
        tbl[key] = nil
    end
end
function CreateFrame()
    return {
        RegisterEvent = noop,
        RegisterUnitEvent = noop,
        SetScript = noop,
    }
end

local essentialChild = {
    cooldownID = 70001,
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
    IsShown = function() return true end,
}
essentialChild.Cooldown.GetParent = function() return essentialChild end

EssentialCooldownViewer = {
    GetChildren = function() return essentialChild end,
}
UtilityCooldownViewer  = { GetChildren = function() end }
BuffIconCooldownViewer = { GetChildren = function() end }
BuffBarCooldownViewer  = { GetChildren = function() end }

C_CooldownViewer = {
    GetCooldownViewerCategorySet = function(category)
        if category == 1 then return { 70001 } end
        return {}
    end,
    GetCooldownViewerCooldownInfo = function(cooldownID)
        if cooldownID == 70001 then
            return {
                cooldownID = 70001,
                spellID = 343294,
                overrideSpellID = 343294,
                overrideTooltipSpellID = 343294,
                linkedSpellIDs = { 343294 },
                selfAura = false, -- target-debuff spell → auraUnit gets stamped "target"
                hasAura = true,
                charges = false,
                isKnown = true,
            }
        end
    end,
}

local realCooldownDuration = { token = "real-cooldown-duration" }

local ns = {
    Helpers = {
        IsSecretValue = function() return false end,
        IsAuraOwnedByPlayerOrPet = function(auraData)
            return auraData and auraData.isFromPlayerOrPlayerPet == true
        end,
    },
}

assert(loadfile("modules/cdm/cdm_sources.lua"))("QUI", ns)
assert(loadfile("modules/cdm/cdm_blizz_mirror.lua"))("QUI", ns)

ns.CDMSources.QueryUnitAuraBySpellID    = function() return nil end
ns.CDMSources.QueryAuraDuration         = function() return nil end
ns.CDMSources.QueryAuraDataByAuraInstanceID = function() return nil end

ns.CDMBlizzMirror.ForceRescan()
essentialChild.Cooldown:SetCooldownFromDurationObject(realCooldownDuration)

local state = assert(ns.CDMBlizzMirror.GetStateByCooldownID(70001),
    "essential mirror state missing after rescan + cooldown bind")

-- Setup pre-conditions: cooldown lane populated by the hook, auraUnit
-- stamped "target" by RefreshChildSemanticState's selfAura==false fallback.
assert(state.cooldownDurObj == realCooldownDuration,
    "cooldown lane should hold the real cooldown DurObj after SetCooldownFromDurationObject")
assert(state.auraUnit == "target",
    "auraUnit should be stamped 'target' for an info.selfAura==false cooldown (got " .. tostring(state.auraUnit) .. ")")
assert(state.isActive == true,
    "mirror state should be active after a real-cooldown bind")

-- Simulate PLAYER_TARGET_CHANGED.
ns.CDMBlizzMirror.HandlePlayerTargetChanged()

state = assert(ns.CDMBlizzMirror.GetStateByCooldownID(70001),
    "essential mirror state missing after target-change")

-- The whole point: cooldown lane MUST survive. Before the 2026-05-11 fix
-- (ClearAllDurationLanes → ClearAuraDurationLane in ClearMirrorAuraState),
-- this assertion failed and the cooldown swipe disappeared in-game on
-- every target swap for every target-debuff cooldown.
assert(state.cooldownDurObj == realCooldownDuration,
    "PLAYER_TARGET_CHANGED must NOT wipe the cooldown lane (regression: ClearMirrorAuraState used to call ClearAllDurationLanes; got " .. tostring(state.cooldownDurObj) .. ")")
assert(state.isActive == true,
    "mirror state must remain active after target-change (cooldown is still running)")

-- And the aura-side state IS cleared as expected.
assert(state.auraUnit == nil,
    "PLAYER_TARGET_CHANGED must clear the auraUnit stamp (got " .. tostring(state.auraUnit) .. ")")

print("OK: cdm_blizz_mirror_target_change_test")
