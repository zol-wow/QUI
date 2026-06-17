-- tests/unit/cdm_blizz_mirror_unit_aura_scoped_test.lua
-- Run: lua tests/unit/cdm_blizz_mirror_unit_aura_scoped_test.lua
--
-- Regression: a partial UNIT_AURA (one proc's auras, e.g. Hammer of Light)
-- used to re-evaluate EVERY aura-viewer child via RefreshAuraViewerChildActive-
-- States, flickering charges/stacks across the whole bar. HandleUnitAuraChanged
-- must now scope active-state refreshes to the payload (Blizzard parity) and
-- full-walk only on isFullUpdate / nil payload.

local function noop() end
local eventScript
local registeredUnitEvents = {}

function hooksecurefunc(owner, method, hook)
    local original = owner[method] or noop
    owner[method] = function(self, ...)
        original(self, ...)
        hook(self, ...)
    end
end

function InCombatLockdown() return false end
function GetTime() return 10 end
function wipe(tbl)
    for key in pairs(tbl) do tbl[key] = nil end
end

function CreateFrame()
    return {
        RegisterEvent = noop,
        RegisterUnitEvent = function(_, event) registeredUnitEvents[event] = true end,
        SetScript = function(_, script, handler)
            if script == "OnEvent" then eventScript = handler end
        end,
    }
end

C_Timer = { After = function() end }

local function MakeAuraChild(cooldownID)
    local child = {
        cooldownID = cooldownID,
        isActive = true,  -- aura present => ReadChildSemanticActive returns true
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

local auraChildA = MakeAuraChild(2001)   -- spellID 9001
local auraChildB = MakeAuraChild(3001)   -- spellID 300001

local function MakeViewer(getChildren)
    return {
        alpha = 1,
        GetAlpha = function(self) return self.alpha end,
        SetAlpha = function(self, alpha) self.alpha = alpha end,
        GetChildren = getChildren,
    }
end

EssentialCooldownViewer = MakeViewer(function() end)
UtilityCooldownViewer = MakeViewer(function() end)
BuffIconCooldownViewer = MakeViewer(function() return auraChildA, auraChildB end)
BuffBarCooldownViewer = MakeViewer(function() end)

C_CooldownViewer = {
    GetCooldownViewerCategorySet = function(category)
        if category == 2 then return { 2001, 3001 } end
        return {}
    end,
    GetCooldownViewerCooldownInfo = function(cooldownID)
        if cooldownID == 2001 then
            return { cooldownID = 2001, spellID = 9001, overrideSpellID = 9001,
                linkedSpellIDs = {}, selfAura = true, hasAura = true,
                charges = false, isKnown = true }
        end
        if cooldownID == 3001 then
            return { cooldownID = 3001, spellID = 300001, overrideSpellID = 300001,
                linkedSpellIDs = {}, selfAura = true, hasAura = true,
                charges = false, isKnown = true }
        end
    end,
}

local mirrorRefreshes = {}
local function ResetRefreshes() mirrorRefreshes = {} end
local function CountFor(cooldownID)
    local count = 0
    for _, r in ipairs(mirrorRefreshes) do
        if r.cooldownID == cooldownID then count = count + 1 end
    end
    return count
end

local updatedInstanceSpellID = {}  -- [instanceID] = spellID

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
        QueryAuraDataByAuraInstanceID = function(_unit, instID)
            local sid = updatedInstanceSpellID[instID]
            if sid then return { spellId = sid, auraInstanceID = instID } end
            return nil
        end,
    },
    CDMIcons = {
        UpdateAllCooldowns = noop,
        RequestMirrorTextRefresh = function(_, cooldownID, category, reason)
            mirrorRefreshes[#mirrorRefreshes + 1] =
                { cooldownID = cooldownID, category = category, reason = reason }
        end,
    },
}

assert(loadfile("QUI_CDM/cdm/cdm_blizz_mirror.lua"))("QUI", ns)
assert(type(eventScript) == "function", "mirror event script should install")
assert(registeredUnitEvents.UNIT_AURA ~= true,
    "mirror consumes UNIT_AURA via cdm_spelldata, never registers its own")

ns.CDMBlizzMirror.ForceRescan()
assert(auraChildA._quiMirrorBound and auraChildB._quiMirrorBound,
    "both aura children should bind on rescan")

local H = ns.CDMBlizzMirror.HandleUnitAuraChanged

-- 1) Partial add of ONE aura (spellID 9001) refreshes only its child, not the
--    unrelated aura-viewer child.
ResetRefreshes()
H("player", {
    isFullUpdate = false,
    addedAuras = { { spellId = 9001, auraInstanceID = 555 } },
})
assert(CountFor(2001) >= 1, "scoped add should refresh the matching aura child (2001)")
assert(CountFor(3001) == 0,
    "scoped add must NOT refresh the unrelated aura child (3001) -- this is the flicker bug")

-- 2) Update-only tick (spellID 300001) refreshes only its child.
ResetRefreshes()
updatedInstanceSpellID[777] = 300001
H("player", {
    isFullUpdate = false,
    updatedAuraInstanceIDs = { 777 },
})
assert(CountFor(3001) >= 1, "scoped update should refresh the matching aura child (3001)")
assert(CountFor(2001) == 0, "scoped update must NOT refresh the unrelated aura child (2001)")

-- 3) Full update walks every aura-viewer child.
ResetRefreshes()
H("player", { isFullUpdate = true })
assert(CountFor(2001) >= 1 and CountFor(3001) >= 1,
    "isFullUpdate must refresh every aura-viewer child")

-- 4) Nil payload also full-walks (defensive).
ResetRefreshes()
H("player", nil)
assert(CountFor(2001) >= 1 and CountFor(3001) >= 1,
    "nil payload must fall back to a full walk")

-- 5) An added aura whose spellID maps to nothing refreshes no child.
ResetRefreshes()
H("player", {
    isFullUpdate = false,
    addedAuras = { { spellId = 424242, auraInstanceID = 999 } },
})
assert(CountFor(2001) == 0 and CountFor(3001) == 0,
    "unmapped added aura must not refresh any aura-viewer child")

print("OK: cdm_blizz_mirror_unit_aura_scoped_test")
