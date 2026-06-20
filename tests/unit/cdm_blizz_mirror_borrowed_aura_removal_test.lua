-- tests/unit/cdm_blizz_mirror_borrowed_aura_removal_test.lua
-- Run: lua tests/unit/cdm_blizz_mirror_borrowed_aura_removal_test.lua
-- luacheck: globals hooksecurefunc InCombatLockdown GetTime wipe CreateFrame
-- luacheck: globals EssentialCooldownViewer UtilityCooldownViewer BuffIconCooldownViewer BuffBarCooldownViewer C_CooldownViewer
--
-- Regression: a UTILITY cooldown icon borrows a buff's duration via the
-- aura-related-child lane (mode=aura while the buff is up). When the buff is
-- removed, the borrowed auraInstanceID used to stay stamped on the cooldown
-- state, freezing the icon in mode=aura so it never showed the real cooldown
-- swipe after the buff ended (Druid Stampeding Roar is the reference case).
--
-- The removal happens under the realistic stuck condition: the buff child
-- frame still exposes the (now-dead) auraInstanceID and C_UnitAuras.
-- GetAuraDuration still returns a live DurationObject on the removal tick, so
-- the GetAuraDuration-probe eviction path cannot clear it. Only the
-- authoritative removedAuraInstanceIDs clear frees the borrowed lane.

local function noop() end
local eventScript

function hooksecurefunc(owner, method, hook)
    local original = owner[method] or noop
    owner[method] = function(self, ...)
        original(self, ...)
        hook(self, ...)
    end
end

function InCombatLockdown() return true end -- removal happens in combat
function GetTime() return 100 end
function wipe(tbl)
    for key in pairs(tbl) do tbl[key] = nil end
end
function CreateFrame()
    return {
        RegisterEvent = noop,
        RegisterUnitEvent = noop,
        SetScript = function(_, script, handler)
            if script == "OnEvent" then eventScript = handler end
        end,
    }
end
C_Timer = { After = function() end }

local UTIL_CDID = 2282
local BUFF_CDID = 5001
local SPELL = 77761
local INST = 254

local function MakeChild(cooldownID, auraInstanceID)
    local child = {
        cooldownID = cooldownID,
        isActive = true,
        auraInstanceID = auraInstanceID,
        Cooldown = {
            SetCooldown = noop, SetCooldownFromDurationObject = noop,
            SetCooldownFromExpirationTime = noop, SetCooldownDuration = noop,
            SetCooldownUNIX = noop, Clear = noop,
        },
        Show = noop, Hide = noop,
    }
    child.Cooldown.GetParent = function() return child end
    return child
end

local utilChild = MakeChild(UTIL_CDID, nil)
local buffChild = MakeChild(BUFF_CDID, INST)

local function MakeViewer(getChildren)
    return {
        alpha = 1,
        GetAlpha = function(self) return self.alpha end,
        SetAlpha = function(self, alpha) self.alpha = alpha end,
        GetChildren = getChildren,
    }
end

EssentialCooldownViewer = MakeViewer(function() end)
UtilityCooldownViewer = MakeViewer(function() return utilChild end)
BuffIconCooldownViewer = MakeViewer(function() return buffChild end)
BuffBarCooldownViewer = MakeViewer(function() end)

local function Info(cooldownID)
    return {
        cooldownID = cooldownID, spellID = SPELL, overrideSpellID = SPELL,
        linkedSpellIDs = {}, selfAura = true, hasAura = true,
        charges = false, isKnown = true,
    }
end

C_CooldownViewer = {
    GetCooldownViewerCategorySet = function(category)
        if category == 1 then return { UTIL_CDID } end -- utility
        if category == 2 then return { BUFF_CDID } end -- buff
        return {}
    end,
    GetCooldownViewerCooldownInfo = function(cooldownID)
        if cooldownID == UTIL_CDID or cooldownID == BUFF_CDID then
            return Info(cooldownID)
        end
    end,
}

-- The aura is "live" until we flip this; on the removal tick it stays live to
-- replicate the GetAuraDuration lag the trace showed (mauraDur=live).
local auraLive = true
local liveDurObj = { token = "aura-dur" }

local ns = {
    Helpers = {
        IsSecretValue = function() return false end,
        IsAuraOwnedByPlayerOrPet = function() return true end,
    },
    CDMSources = {
        QueryPlayerAuraBySpellID = function() return nil end,
        QueryUnitAuraBySpellID = function() return nil end,
        QueryAuraDataBySpellID = function() return nil end,
        QueryBaseSpell = function() return nil end,
        QueryAuraDuration = function(_unit, instID)
            if instID == INST and auraLive then return liveDurObj end
            return nil
        end,
        QueryAuraDataByAuraInstanceID = function(_unit, instID)
            if instID == INST and auraLive then
                return { spellId = SPELL, auraInstanceID = INST }
            end
            return nil
        end,
    },
    CDMIcons = {
        UpdateAllCooldowns = noop,
        RequestMirrorTextRefresh = noop,
    },
}

assert(loadfile("QUI_CDM/cdm/cdm_blizz_mirror.lua"))("QUI", ns)
assert(type(eventScript) == "function", "mirror event script should install")

local M = ns.CDMBlizzMirror
M.ForceRescan()

local H = M.HandleUnitAuraChanged

-- 1) Buff applied: stamps the buff sibling and borrows onto the utility icon.
H("player", {
    isFullUpdate = false,
    addedAuras = { { spellId = SPELL, auraInstanceID = INST } },
})

local utilState = M.GetStateByCooldownID(UTIL_CDID, "utility")
assert(utilState, "utility state should exist after rescan")
assert(utilState.auraInstanceID == INST,
    "precondition: utility cooldown should borrow the buff aura instance ("
    .. tostring(utilState.auraInstanceID) .. ")")

-- 2) Buff removed in combat. The buff child still exposes the dead instance and
--    GetAuraDuration still returns a live DurationObject (auraLive stays true),
--    so only the authoritative removedAuraInstanceIDs clear can free the lane.
H("player", {
    isFullUpdate = false,
    removedAuraInstanceIDs = { INST },
})

utilState = M.GetStateByCooldownID(UTIL_CDID, "utility")
assert(utilState.auraInstanceID == nil,
    "REGRESSION: borrowed aura lane must clear on removal so the cooldown icon "
    .. "leaves mode=aura (got auraInstanceID=" .. tostring(utilState.auraInstanceID) .. ")")

print("cdm_blizz_mirror_borrowed_aura_removal_test: PASS")
