-- tests/cdm_icon_factory_blizz_fallback_test.lua
-- Run: lua tests/cdm_icon_factory_blizz_fallback_test.lua

function InCombatLockdown() return false end
function CreateFrame() return {} end

local auraDuration = { token = "aura-duration-object" }
local queriedAura = false

local ns = {
    Helpers = {},
    CDMResolvers = {
        GetEntryTexture = function() return nil end,
        GetSpellTexture = function() return nil end,
        QueryCharges = function() return nil end,
        QueryCooldown = function() return nil end,
        QueryOverrideSpell = function() return nil end,
        QueryDisplayCount = function() return nil end,
        ResolveAuraStateForIcon = function() return nil end,
        HasRealCooldownState = function() return false end,
        ResolveMacro = function() return nil end,
        IsAuraEntry = function() return true end,
    },
    CDMSources = {
        QueryUnitAuraBySpellID = function(unit, spellID, filter)
            if unit == "player" and spellID == 1242998 and filter == "HELPFUL" then
                queriedAura = true
                return { auraInstanceID = 77 }
            end
            return nil
        end,
        QueryAuraDuration = function(unit, auraInstanceID)
            if unit == "player" and auraInstanceID == 77 then
                return auraDuration
            end
            return nil
        end,
    },
    CDMBlizzMirror = {
        GetStateByCooldownID = function(cooldownID)
            assert(cooldownID == 73542, "unexpected cooldownID")
            return {
                cooldownID = 73542,
                isActive = true,
                durObj = nil,
                selfAura = true,
                viewerCategory = "buff",
                spellID = 137007,
                overrideSpellID = 137007,
                overrideTooltipSpellID = 1242998,
                linkedSpellIDs = { 1242998 },
                mirrorEpoch = 3,
            }
        end,
    },
    _OwnedSwipe = {
        ApplyToIcon = function() end,
    },
}

assert(loadfile("modules/cdm/cdm_icon_factory.lua"))("QUI", ns)

local appliedDuration
ns.CDMIconFactory._FinalizeImports({
    IsTotemSlotEntry = function() return false end,
    ApplyResolvedCooldown = function(icon)
        appliedDuration = icon._lastAuraDurObj
        return true
    end,
    ReapplySwipeStyle = function() end,
    ClearIconStackText = function() end,
    RequestBuffIconLayoutRefresh = function() end,
})

local icon = {
    _spellEntry = {
        id = 1242998,
        spellID = 1242998,
        kind = "aura",
        type = "aura",
        viewerType = "buff",
    },
    _blizzMirrorCooldownID = 73542,
}

ns.CDMIconFactory.UpdateIconCooldown(icon)

assert(queriedAura == false, "icon sync must not query aura APIs; UNIT_AURA mirror path owns aura duration")
assert(appliedDuration == nil, "active mirror with no durObj should show without inventing a duration")

print("OK: cdm_icon_factory_blizz_fallback_test")
