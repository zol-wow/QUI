-- tests/cdm_icon_factory_mirror_empty_stack_test.lua
-- Run: lua tests/cdm_icon_factory_mirror_empty_stack_test.lua

function InCombatLockdown() return false end
function GetTime() return 100 end
function CreateFrame() return {} end

local stackWrites = {}

local ns = {
    Helpers = {
        IsSecretValue = function() return false end,
    },
    CDMResolvers = {
        GetEntryTexture = function() return nil end,
        GetSpellTexture = function() return nil end,
        QueryCharges = function(spellID)
            if spellID == 49998 then
                return {
                    currentCharges = 3,
                    maxCharges = 3,
                    isActive = false,
                }
            end
            return nil
        end,
        QueryCooldown = function()
            return {
                startTime = 0,
                duration = 0,
                isActive = false,
            }
        end,
        QueryOverrideSpell = function() return nil end,
        QueryDisplayCount = function(spellID)
            if spellID == 49998 then
                return 3
            end
            return nil
        end,
        ResolveAuraStateForIcon = function() return { isActive = false } end,
        HasRealCooldownState = function() return false end,
        ResolveMacro = function() return nil end,
        IsAuraEntry = function() return false end,
    },
}

assert(loadfile("modules/cdm/cdm_icon_factory.lua"))("QUI", ns)

ns.CDMIconFactory._FinalizeImports({
    GetBestSpellCooldown = function()
        return 0, 0, nil, false, false
    end,
    IsTotemSlotEntry = function() return false end,
    ApplyResolvedCooldown = function() return true end,
    ReapplySwipeStyle = function() end,
    ClearIconStackText = function(icon, reason)
        stackWrites[#stackWrites + 1] = { op = "clear", reason = reason }
    end,
    HideIconStackText = function(icon, reason)
        stackWrites[#stackWrites + 1] = { op = "hide", reason = reason }
    end,
    ShowIconStackText = function(icon, value, _settings, source)
        stackWrites[#stackWrites + 1] = { op = "show", value = value, source = source }
    end,
    ValueIsMissing = function(value) return value == nil end,
    ValueIsPresent = function(value) return value ~= nil end,
    GetTrackerSettings = function()
        return { desaturateOnCooldown = true }
    end,
    ResolveTrackerSettingsNow = function()
        return { desaturateOnCooldown = true }
    end,
    IsCustomBarContainer = function() return false end,
    StopCustomBarActiveGlow = function() end,
    ApplyCooldownDesaturation = function() end,
    ShouldAllowStackTextWrites = function() return true end,
    ResolveIconStackText = function()
        return nil, nil, true
    end,
    ShouldUseBuffSwipeForIcon = function() return false end,
    IsSafeNumeric = function(value) return type(value) == "number" end,
    GetRecentCastAliasForEntry = function() return nil end,
})

local icon = {
    _spellEntry = {
        id = 49998,
        spellID = 49998,
        type = "spell",
        kind = "cooldown",
        viewerType = "essential",
        name = "Death Strike",
    },
    _blizzMirrorCooldownID = 12345,
    _blizzMirrorCategory = "essential",
    Icon = {
        SetTexture = function() end,
    },
    Cooldown = {},
}

ns.CDMIconFactory.UpdateIconCooldown(icon)

assert(#stackWrites == 1, "mirror-empty cooldown icon should only clear existing stack text")
assert(stackWrites[1].op == "hide", "mirror-empty cooldown icon should hide stack text")
assert(stackWrites[1].reason == "mirror-stack-empty", "mirror-empty cooldown icon should use mirror-empty reason")

print("OK: cdm_icon_factory_mirror_empty_stack_test")
