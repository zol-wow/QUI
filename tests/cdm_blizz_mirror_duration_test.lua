-- tests/cdm_blizz_mirror_duration_test.lua
-- Run: lua tests/cdm_blizz_mirror_duration_test.lua

local function noop() end

local preferredTotemSlotToken = { token = "preferred-totem-slot" }
local secretTotemDataToken = setmetatable({ token = "secret-totem-data" }, {
    __index = function()
        error("secret totemData must not be indexed")
    end,
})

function issecretvalue(value)
    if value == preferredTotemSlotToken then
        error("preferred totem slot must not be inspected for secret status")
    end
    return value == secretTotemDataToken
end

local hooks = {}
local eventScript
local registeredEvents = {}
function hooksecurefunc(owner, method, hook)
    hooks[#hooks + 1] = { owner = owner, method = method, hook = hook }
    local original = owner[method] or noop
    owner[method] = function(self, ...)
        original(self, ...)
        hook(self, ...)
    end
end

function InCombatLockdown() return false end
function GetTime() return 123 end
function wipe(tbl)
    for key in pairs(tbl) do
        tbl[key] = nil
    end
end
function CreateFrame()
    return {
        RegisterEvent = function(_, event)
            registeredEvents[event] = true
        end,
        RegisterUnitEvent = function(_, event)
            registeredEvents[event] = true
        end,
        SetScript = function(_, script, handler)
            if script == "OnEvent" then
                eventScript = handler
            end
        end,
    }
end
C_Timer = {
    After = function(_, callback)
        callback()
    end,
}

local cooldownDuration = { token = "cooldown-duration-object" }
local gcdDuration = { token = "gcd-duration-object" }
local chargeDuration = { token = "charge-duration-object" }
local uncountedChargeFlagDuration = { token = "uncounted-charge-flag-duration-object" }
local uncountedChargeCooldownDuration = { token = "uncounted-charge-cooldown-duration-object" }
local mindBlastCooldownDuration = { token = "mind-blast-cooldown-duration-object" }
local mindBlastChargeDuration = { token = "mind-blast-charge-duration-object" }
local prayerCooldownDuration = { token = "prayer-cooldown-duration-object" }
local prayerChargeDuration = { token = "prayer-charge-duration-object" }
local auraSpellCooldownDuration = { token = "aura-spell-cooldown-duration-object" }
local auraHookDuration = { token = "aura-hook-duration-object" }
local auraPayloadDuration = { token = "aura-payload-duration-object" }
local auraUnitFallbackDuration = { token = "aura-unit-fallback-duration-object" }
local trackedBarAuraDuration = { token = "tracked-bar-aura-duration-object" }
local cooldownAuraMappedDuration = { token = "cooldown-aura-mapped-duration-object" }
local childFrameAuraDuration = { token = "child-frame-aura-duration-object" }
local childFrameAuraData = { token = "child-frame-aura-data", icon = 12345 }
local childAuraDataOnlyDuration = { token = "child-aura-data-only-duration-object" }
local childAuraDataOnly = { auraInstanceID = 515, icon = 23456 }
local childCombatAuraDataOnlyDuration = { token = "child-combat-aura-data-only-duration-object" }
local childCombatAuraDataOnly = { auraInstanceID = 516, icon = 34567 }
local relatedChildFrameAuraDuration = { token = "related-child-frame-aura-duration-object" }
local amzCooldownDuration = { token = "amz-cooldown-duration-object" }
local amzAuraDuration = { token = "amz-aura-duration-object" }
local iconRefreshCount = 0

local function MakeTextOwner()
    return {
        text = nil,
        SetText = function(self, text)
            self.text = text
        end,
        GetText = function(self)
            return self.text
        end,
        Show = noop,
        Hide = noop,
        SetShown = noop,
    }
end

C_Spell = {
    GetSpellCooldown = function(spellID)
        if spellID == 555000 then
            return {
                isActive = true,
                isEnabled = true,
                isOnGCD = true,
                startTime = 120,
                duration = 1.5,
            }
        end
        if spellID == 1233448 then
            return {
                isActive = true,
                isEnabled = true,
                isOnGCD = false,
                startTime = 120,
                duration = 12,
            }
        end
    end,
    GetSpellCooldownDuration = function(spellID, ignoreGCD)
        if spellID == 8092 and ignoreGCD == true then
            return mindBlastCooldownDuration
        end
        if spellID == 33076 and ignoreGCD == true then
            return prayerCooldownDuration
        end
        if spellID == 555000 then
            if ignoreGCD == false then
                return gcdDuration
            end
            return nil
        end
        if spellID == 1233448 and ignoreGCD == true then
            return cooldownDuration
        end
        if spellID == 1227280 and ignoreGCD == true then
            return uncountedChargeCooldownDuration
        end
        if spellID == 1242998 and ignoreGCD == true then
            return auraSpellCooldownDuration
        end
        if spellID == 51052 and ignoreGCD == true then
            return amzCooldownDuration
        end
    end,
    GetSpellChargeDuration = function(spellID)
        if spellID == 8092 then
            return mindBlastChargeDuration
        end
        if spellID == 17 or spellID == 33076 then
            return prayerChargeDuration
        end
        if spellID == 444347 then
            return chargeDuration
        end
        if spellID == 1227280 then
            return uncountedChargeFlagDuration
        end
    end,
    GetSpellCharges = function(spellID)
        if spellID == 1227280 then
            return {
                currentCharges = 1,
                maxCharges = 2,
                isActive = true,
            }
        end
        if spellID == 8092 then
            return {
                currentCharges = 0,
                maxCharges = 1,
                isActive = false,
            }
        end
        if spellID == 33076 then
            return {
                currentCharges = 0,
                maxCharges = 1,
                isActive = false,
            }
        end
        return nil
    end,
}

local child = {
    cooldownID = 27902,
    isActive = true,
    cooldownChargesShown = true,
    ChargeCount = MakeTextOwner(),
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
child.Cooldown.GetParent = function() return child end
child.ChargeCount.DisplayText = MakeTextOwner()
child.ChargeCount.Current = MakeTextOwner()

local chargedChild = {
    cooldownID = 444001,
    isActive = true,
    wasSetFromCharges = true,
    cooldownChargesShown = true,
    ChargeCount = MakeTextOwner(),
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
chargedChild.Cooldown.GetParent = function() return chargedChild end
chargedChild.ChargeCount.DisplayText = MakeTextOwner()

local unflaggedCountChild = {
    cooldownID = 777001,
    isActive = true,
    ChargeCount = MakeTextOwner(),
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
unflaggedCountChild.Cooldown.GetParent = function() return unflaggedCountChild end
unflaggedCountChild.ChargeCount.Current = MakeTextOwner()

local uncountedChargeFlagChild = {
    cooldownID = 1227280,
    isActive = true,
    wasSetFromCharges = true,
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
uncountedChargeFlagChild.Cooldown.GetParent = function() return uncountedChargeFlagChild end

local mindBlastChild = {
    cooldownID = 809200,
    isActive = true,
    wasSetFromCharges = true,
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
mindBlastChild.Cooldown.GetParent = function() return mindBlastChild end

local prayerAliasChild = {
    cooldownID = 330760,
    isActive = true,
    wasSetFromCharges = true,
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
prayerAliasChild.Cooldown.GetParent = function() return prayerAliasChild end

local gcdChild = {
    cooldownID = 27903,
    isActive = true,
    wasSetFromCooldown = true,
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
gcdChild.Cooldown.GetParent = function() return gcdChild end

local auraChild = {
    cooldownID = 73542,
    isActive = true,
    Applications = MakeTextOwner(),
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
auraChild.Applications.DisplayText = MakeTextOwner()

local auraFallbackChild = {
    cooldownID = 141686,
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
auraFallbackChild.Cooldown.GetParent = function() return auraFallbackChild end

local trackedBarChild = {
    cooldownID = 27925,
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
trackedBarChild.Cooldown.GetParent = function() return trackedBarChild end

local cooldownAuraMappedChild = {
    cooldownID = 69057,
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
cooldownAuraMappedChild.Cooldown.GetParent = function() return cooldownAuraMappedChild end

local reapingChild = {
    cooldownID = 70765,
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
    SetShown = noop,
}
reapingChild.Cooldown.GetParent = function() return reapingChild end

local raiseAbomChild = {
    cooldownID = 92923,
    isActive = true,
    preferredTotemUpdateSlot = preferredTotemSlotToken,
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
    SetShown = noop,
}
raiseAbomChild.Cooldown.GetParent = function() return raiseAbomChild end

local amzUtilityChild = {
    cooldownID = 27911,
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
amzUtilityChild.Cooldown.GetParent = function() return amzUtilityChild end

local amzBuffChild = {
    cooldownID = 103071,
    auraInstanceID = 707,
    auraDataUnit = "player",
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
    SetShown = noop,
}
amzBuffChild.Cooldown.GetParent = function() return amzBuffChild end

EssentialCooldownViewer = {
    GetChildren = function()
        return child, chargedChild, unflaggedCountChild, uncountedChargeFlagChild,
            mindBlastChild, prayerAliasChild, gcdChild
    end,
}
UtilityCooldownViewer = {
    GetChildren = function()
        return amzUtilityChild
    end,
}
BuffIconCooldownViewer = {
    GetChildren = function()
        return auraChild, auraFallbackChild, trackedBarChild, cooldownAuraMappedChild, reapingChild, raiseAbomChild, amzBuffChild
    end,
}
BuffBarCooldownViewer = { GetChildren = function() end }

C_CooldownViewer = {
    GetCooldownViewerCategorySet = function(category)
        if category == 0 then
            return { 27902, 444001, 777001, 1227280, 809200, 330760, 27903 }
        end
        if category == 1 then
            return { 27911 }
        end
        if category == 2 then
            return { 73542, 141686, 70765, 92923, 103071 }
        end
        if category == 3 then
            return { 27925, 69057 }
        end
        return {}
    end,
    GetCooldownViewerCooldownInfo = function(cooldownID)
        if cooldownID == 27902 then
            return {
                cooldownID = 27902,
                spellID = 1233448,
                overrideSpellID = 1233448,
                overrideTooltipSpellID = nil,
                linkedSpellIDs = { 1235391 },
                selfAura = true,
                hasAura = true,
                charges = false,
                isKnown = true,
            }
        end
        if cooldownID == 27903 then
            return {
                cooldownID = 27903,
                spellID = 555000,
                overrideSpellID = 555000,
                overrideTooltipSpellID = nil,
                linkedSpellIDs = nil,
                selfAura = true,
                hasAura = false,
                charges = false,
                isKnown = true,
            }
        end
        if cooldownID == 444001 then
            return {
                cooldownID = 444001,
                spellID = 444347,
                overrideSpellID = 444347,
                overrideTooltipSpellID = nil,
                linkedSpellIDs = nil,
                selfAura = false,
                hasAura = false,
                charges = true,
                isKnown = true,
            }
        end
        if cooldownID == 777001 then
            return {
                cooldownID = 777001,
                spellID = 777002,
                overrideSpellID = 777002,
                overrideTooltipSpellID = nil,
                linkedSpellIDs = nil,
                selfAura = false,
                hasAura = false,
                charges = false,
                isKnown = true,
            }
        end
        if cooldownID == 1227280 then
            return {
                cooldownID = 1227280,
                spellID = 1227280,
                overrideSpellID = 1227280,
                overrideTooltipSpellID = nil,
                linkedSpellIDs = nil,
                selfAura = false,
                hasAura = false,
                charges = true,
                isKnown = true,
            }
        end
        if cooldownID == 809200 then
            return {
                cooldownID = 809200,
                spellID = 8092,
                overrideSpellID = 8092,
                overrideTooltipSpellID = nil,
                linkedSpellIDs = nil,
                selfAura = false,
                hasAura = false,
                charges = true,
                isKnown = true,
            }
        end
        if cooldownID == 330760 then
            return {
                cooldownID = 330760,
                spellID = 17,
                overrideSpellID = nil,
                overrideTooltipSpellID = nil,
                linkedSpellIDs = { 33076 },
                selfAura = false,
                hasAura = false,
                charges = true,
                isKnown = true,
            }
        end
        if cooldownID == 73542 then
            return {
                cooldownID = 73542,
                spellID = 137007,
                overrideSpellID = 137007,
                overrideTooltipSpellID = 1242998,
                linkedSpellIDs = { 1242998 },
                selfAura = true,
                hasAura = false,
                charges = false,
                isKnown = true,
            }
        end
        if cooldownID == 141686 then
            return {
                cooldownID = 141686,
                spellID = 137007,
                overrideSpellID = 137007,
                overrideTooltipSpellID = 1254252,
                linkedSpellIDs = { 1254252 },
                selfAura = true,
                hasAura = false,
                charges = false,
                isKnown = true,
            }
        end
        if cooldownID == 27925 then
            return {
                cooldownID = 27925,
                spellID = 1233448,
                overrideSpellID = 1233448,
                overrideTooltipSpellID = nil,
                linkedSpellIDs = { 1235391 },
                selfAura = true,
                hasAura = true,
                charges = false,
                isKnown = true,
            }
        end
        if cooldownID == 69057 then
            return {
                cooldownID = 69057,
                spellID = 1242158,
                overrideSpellID = 1242158,
                overrideTooltipSpellID = nil,
                linkedSpellIDs = { 1242223 },
                selfAura = true,
                hasAura = false,
                charges = false,
                isKnown = true,
            }
        end
        if cooldownID == 70765 then
            return {
                cooldownID = 70765,
                spellID = 377514,
                overrideSpellID = 377514,
                overrideTooltipSpellID = 1235261,
                linkedSpellIDs = { 1235261 },
                selfAura = true,
                hasAura = false,
                charges = false,
                isKnown = true,
            }
        end
        if cooldownID == 92923 then
            return {
                cooldownID = 92923,
                spellID = 1242608,
                overrideSpellID = 1242608,
                overrideTooltipSpellID = nil,
                linkedSpellIDs = { 288853 },
                selfAura = true,
                hasAura = false,
                charges = false,
                isKnown = true,
            }
        end
        if cooldownID == 27911 then
            return {
                cooldownID = 27911,
                spellID = 51052,
                overrideSpellID = 51052,
                overrideTooltipSpellID = nil,
                linkedSpellIDs = nil,
                selfAura = false,
                hasAura = false,
                charges = false,
                isKnown = true,
            }
        end
        if cooldownID == 103071 then
            return {
                cooldownID = 103071,
                spellID = 51052,
                overrideSpellID = 51052,
                overrideTooltipSpellID = nil,
                linkedSpellIDs = { 145629 },
                selfAura = false,
                hasAura = true,
                charges = false,
                isKnown = true,
            }
        end
    end,
}

local ns = {
    Helpers = {
        IsSecretValue = function(value) return issecretvalue(value) end,
    },
    CDMIcons = {
        RequestMirrorTextRefresh = function()
            iconRefreshCount = iconRefreshCount + 1
        end,
        UpdateAllCooldowns = function()
            iconRefreshCount = iconRefreshCount + 1
        end,
    },
}

assert(loadfile("modules/cdm/cdm_sources.lua"))("QUI", ns)
assert(loadfile("modules/cdm/cdm_blizz_mirror.lua"))("QUI", ns)

local originalQuerySpellCharges = ns.CDMSources.QuerySpellCharges
ns.CDMSources.QuerySpellCharges = function(spellID)
    if spellID == 444347 then
        error("mirror must not query spell charges to classify this cooldown")
    end
    return originalQuerySpellCharges(spellID)
end

auraChild.Applications:SetText("3")
auraChild.Applications.DisplayText:SetText("5")
child.ChargeCount:SetText("1")
child.ChargeCount.DisplayText:SetText("")
child.ChargeCount.Current:SetText("4")
chargedChild.ChargeCount:SetText("1")
chargedChild.ChargeCount.DisplayText:SetText("2")
ns.CDMBlizzMirror.ForceRescan()

local stackState = assert(ns.CDMBlizzMirror.GetStateByCooldownID(73542, "buff"),
    "aura mirror stack state missing")
assert(stackState.stackText == "5", "applications DisplayText should be preferred over parent text")
assert(stackState.stackTextSource == "Applications", "applications DisplayText should keep its mirror source")

stackState = assert(ns.CDMBlizzMirror.GetStateByCooldownID(27902, "essential"),
    "non-charge mirror stack state missing")
assert(stackState.stackText == "4", "visible non-charge cooldown count text should be mirrored")
assert(stackState.stackTextSource == "ChargeCount", "visible cooldown count text should keep its mirror source")

child.cooldownChargesShown = false
child.ChargeCount.Current:SetText("2")
stackState = assert(ns.CDMBlizzMirror.GetStateByCooldownID(27902, "essential"),
    "non-charge mirror stack state missing after hidden count")
assert(stackState.stackText == nil, "hidden non-charge cooldown count text should not be mirrored")
assert(stackState.stackTextSource == nil, "hidden non-charge cooldown count text should not keep a source")

child.cooldownChargesShown = true
child.ChargeCount.Current:SetText("4")

stackState = assert(ns.CDMBlizzMirror.GetStateByCooldownID(444001, "essential"),
    "charge mirror stack state missing")
assert(stackState.stackText == "2", "real charge DisplayText should be preferred over parent text")
assert(stackState.stackTextSource == "ChargeCount", "real charge DisplayText should keep its mirror source")

auraChild.Applications.DisplayText:SetText("1")
stackState = assert(ns.CDMBlizzMirror.GetStateByCooldownID(73542, "buff"),
    "aura mirror stack state missing after single stack text")
assert(stackState.stackText == nil, "single application text should not be mirrored as stack text")
assert(stackState.stackTextSource == nil, "single application text should not set a mirror stack source")

auraChild.Applications.DisplayText:SetText("4")
stackState = assert(ns.CDMBlizzMirror.GetStateByCooldownID(73542, "buff"),
    "aura mirror stack state missing after multi-stack text")
assert(stackState.stackText == "4", "multi-application text should be mirrored")
assert(stackState.stackTextSource == "Applications", "multi-application text should keep its mirror source")

auraChild.Applications.DisplayText:SetText("")
stackState = assert(ns.CDMBlizzMirror.GetStateByCooldownID(73542, "buff"),
    "aura mirror stack state missing after empty stack text")
assert(stackState.stackText == nil, "empty application text should clear mirrored stack text")

auraChild.Applications:SetText("6")
stackState = assert(ns.CDMBlizzMirror.GetStateByCooldownID(73542, "buff"),
    "aura mirror stack state missing after parent stack text")
assert(stackState.stackText == "6", "parent Applications text should be mirrored when nested text is empty")
assert(stackState.stackTextSource == "Applications", "parent Applications text should keep its mirror source")

chargedChild.ChargeCount.DisplayText:SetText("1")
stackState = assert(ns.CDMBlizzMirror.GetStateByCooldownID(444001, "essential"),
    "charge mirror stack state missing")
assert(stackState.stackText == "1", "charge count text should still mirror one charge")
assert(stackState.stackTextSource == "ChargeCount", "charge count text should keep its mirror source")

chargedChild.ChargeCount.DisplayText:SetText("")
chargedChild.ChargeCount:SetText("3")
stackState = assert(ns.CDMBlizzMirror.GetStateByCooldownID(444001, "essential"),
    "charge mirror stack state missing after parent charge text")
assert(stackState.stackText == "3", "parent ChargeCount text should be mirrored when nested text is empty")
assert(stackState.stackTextSource == "ChargeCount", "parent ChargeCount text should keep its mirror source")

unflaggedCountChild.ChargeCount.Current:SetText("8")
stackState = assert(ns.CDMBlizzMirror.GetStateByCooldownID(777001, "essential"),
    "unflagged count mirror state missing")
assert(stackState.stackText == nil, "unflagged non-charge cooldown text writes should not be mirrored")
assert(stackState.stackTextSource == nil, "unflagged non-charge cooldown text writes should not keep a source")

child.Cooldown:SetCooldown()

local state = assert(ns.CDMBlizzMirror.GetStateByCooldownID(27902), "mirror state missing")
assert(state.isActive == true, "SetCooldown should mark the mirror active")
assert(state.durObj == cooldownDuration, "SetCooldown should derive a safe spell cooldown DurationObject")
assert(state.cooldownDurObj == cooldownDuration, "spell cooldown should be carried in the cooldown lane")
assert(state.resolvedMode == "cooldown", "spell cooldown mirror state should expose cooldown mode")

gcdChild.Cooldown:SetCooldown()

local gcdState = assert(ns.CDMBlizzMirror.GetStateByCooldownID(27903), "GCD mirror state missing")
assert(gcdState.isActive == true, "GCD SetCooldown should mark the mirror active")
assert(gcdState.durObj == gcdDuration, "GCD SetCooldown should derive a GCD DurationObject")
assert(gcdState.gcdDurObj == gcdDuration, "GCD duration should be carried in the GCD lane")
assert(gcdState.cooldownDurObj == nil, "GCD duration should not populate the real cooldown lane")
assert(gcdState.durObjSource == "gcd-duration", "selected GCD mirror source should identify the GCD lane")
assert(gcdState.resolvedMode == "gcd-only", "GCD mirror state should expose gcd-only mode")

child.wasSetFromAura = true
child.wasSetFromCooldown = false
child.wasSetFromCharges = false
child.Cooldown:SetCooldownFromDurationObject(auraHookDuration)

state = assert(ns.CDMBlizzMirror.GetStateByCooldownID(27902), "mirror state missing after aura hook")
assert(state.auraDurObj == auraHookDuration, "non-aura entries should keep Blizzard aura duration in the aura lane")
assert(state.cooldownDurObj == cooldownDuration, "aura duration must not overwrite cooldown duration lane")
assert(state.durObj == auraHookDuration, "non-aura entries should select aura duration ahead of cooldown")
assert(state.durObjSource == "aura-duration", "selected duration source should identify the aura lane")

child.wasSetFromAura = false
child.wasSetFromCooldown = true
child.wasSetFromCharges = false
child.Cooldown:SetCooldownFromDurationObject(cooldownDuration)

state = assert(ns.CDMBlizzMirror.GetStateByCooldownID(27902), "mirror state missing after cooldown hook")
assert(state.auraDurObj == auraHookDuration, "cooldown hook should preserve higher-priority aura duration")
assert(state.cooldownDurObj == cooldownDuration, "cooldown duration should stay in the cooldown lane")
assert(state.durObj == auraHookDuration, "aura duration should stay selected ahead of cooldown")
assert(state.durObjSource == "aura-duration", "selected duration source should still identify the aura lane")

child.wasSetFromAura = false
child.wasSetFromCooldown = false
child.wasSetFromCharges = true
child.Cooldown:SetCooldownFromDurationObject(chargeDuration)

state = assert(ns.CDMBlizzMirror.GetStateByCooldownID(27902), "mirror state missing after charge hook")
assert(state.auraDurObj == auraHookDuration, "charge hook should preserve higher-priority aura duration")
assert(state.resourceDurObj == chargeDuration, "charge duration should be carried in the resource lane")
assert(state.cooldownDurObj == cooldownDuration, "charge duration must not overwrite cooldown duration lane")
assert(state.durObj == auraHookDuration, "aura duration should stay selected ahead of charge and cooldown")

mindBlastChild.Cooldown:SetCooldownFromDurationObject(mindBlastChargeDuration)

local mindBlastState = assert(ns.CDMBlizzMirror.GetStateByCooldownID(809200, "essential"),
    "one-charge cooldown mirror state missing after charged setter")
assert(mindBlastState.resourceDurObj == nil,
    "charge-flagged cooldowns without count display proof should not populate the charge lane")
assert(mindBlastState.durObj == mindBlastChargeDuration,
    "charge-flagged cooldowns without count display proof should keep the frame DurationObject")
assert(mindBlastState.durObjSource == "cooldown-frame",
    "charge-flagged cooldowns without count display proof should use the frame as cooldown source")
assert(mindBlastState.resolvedMode == "cooldown",
    "charge-flagged cooldowns without count display proof should resolve as cooldown mode")

prayerAliasChild.Cooldown:SetCooldownFromDurationObject(prayerChargeDuration)

local prayerState = assert(ns.CDMBlizzMirror.GetStateByCooldownID(330760, "essential"),
    "one-charge linked cooldown mirror state missing after charged setter")
assert(prayerState.resourceDurObj == nil,
    "charge-flagged linked cooldowns without count display proof should not populate the charge lane")
assert(prayerState.durObj == prayerChargeDuration,
    "charge-flagged linked cooldowns without count display proof should keep the frame DurationObject")
assert(prayerState.durObjSource == "cooldown-frame",
    "charge-flagged linked cooldowns without count display proof should use the frame as cooldown source")
assert(prayerState.resolvedMode == "cooldown",
    "charge-flagged linked cooldowns without count display proof should resolve as cooldown mode")

child.isActive = true
child.cooldownIsActive = nil
child.wasSetFromCooldown = true
child.wasSetFromCharges = false
child.Cooldown:Clear()

state = assert(ns.CDMBlizzMirror.GetStateByCooldownID(27902), "mirror state missing after transient cooldown clear")
assert(state.isActive == true, "transient non-aura Clear should preserve active child state")
assert(state.cooldownDurObj == cooldownDuration, "transient non-aura Clear should preserve the cooldown duration lane")
assert(state.resourceDurObj == chargeDuration, "transient non-aura Clear should preserve the charge duration lane")
assert(state.durObj == auraHookDuration, "transient non-aura Clear should preserve the higher-priority aura duration")

child.cooldownIsActive = false
child.Cooldown:Clear()

state = assert(ns.CDMBlizzMirror.GetStateByCooldownID(27902), "mirror state missing after inactive cooldown clear")
assert(state.isActive == false, "explicit inactive non-aura Clear should clear active state")
assert(state.cooldownDurObj == nil, "explicit inactive non-aura Clear should clear the cooldown duration lane")
assert(state.durObj == nil, "explicit inactive non-aura Clear should clear the selected duration")

child.isActive = true
child.cooldownIsActive = nil
child.wasSetFromAura = false
child.wasSetFromCooldown = true
child.wasSetFromCharges = false
child.Cooldown:SetCooldownFromDurationObject(cooldownDuration)
state = assert(ns.CDMBlizzMirror.GetStateByCooldownID(27902), "mirror state missing after cooldown reset")
assert(state.durObj == cooldownDuration, "cooldown duration should be selected when no aura or charge lane exists")

child.wasSetFromAura = false
child.wasSetFromCooldown = false
child.wasSetFromCharges = true
child.Cooldown:SetCooldownFromDurationObject(chargeDuration)
state = assert(ns.CDMBlizzMirror.GetStateByCooldownID(27902), "mirror state missing after charge priority hook")
assert(state.resourceDurObj == chargeDuration, "charge priority test should populate the charge lane")
assert(state.cooldownDurObj == cooldownDuration, "charge priority test should keep the cooldown lane")
assert(state.durObj == chargeDuration, "charge/recharge duration should be selected ahead of cooldown")
assert(state.durObjSource == "spell-charge", "selected duration source should identify the charge lane")

uncountedChargeFlagChild.wasSetFromCharges = false
uncountedChargeFlagChild.wasSetFromCooldown = true
uncountedChargeFlagChild.Cooldown:SetCooldown()
local uncountedChargeState = assert(ns.CDMBlizzMirror.GetStateByCooldownID(1227280, "essential"),
    "cooldown-backed multi-charge mirror state missing")
assert(uncountedChargeState.resourceDurObj == uncountedChargeFlagDuration,
    "cooldown-backed multi-charge cooldowns should choose the charge lane")
assert(uncountedChargeState.cooldownDurObj == nil,
    "cooldown-backed multi-charge cooldowns should not populate the cooldown lane with spell cooldown duration")
assert(uncountedChargeState.durObj == uncountedChargeFlagDuration,
    "cooldown-backed multi-charge cooldowns should select the charge DurationObject")
assert(uncountedChargeState.durObjSource == "spell-charge",
    "cooldown-backed multi-charge cooldowns should retain spell-charge source")
assert(uncountedChargeState.resolvedMode == "charge",
    "cooldown-backed multi-charge cooldowns should resolve as charge mode")

uncountedChargeFlagChild.wasSetFromCharges = true
uncountedChargeFlagChild.wasSetFromCooldown = false
uncountedChargeFlagChild.Cooldown:SetCooldownFromDurationObject(uncountedChargeFlagDuration)
uncountedChargeState = assert(ns.CDMBlizzMirror.GetStateByCooldownID(1227280, "essential"),
    "readable multi-charge cooldown mirror state missing")
assert(uncountedChargeState.resourceDurObj == uncountedChargeFlagDuration,
    "readable multi-charge cooldowns should populate the charge lane even without count display proof")
assert(uncountedChargeState.durObj == uncountedChargeFlagDuration,
    "readable multi-charge cooldowns should select the charge DurationObject")
assert(uncountedChargeState.durObjSource == "spell-charge",
    "readable multi-charge cooldowns should retain spell-charge source")
assert(uncountedChargeState.resolvedMode == "charge",
    "readable multi-charge cooldowns should resolve as charge mode")

child.cooldownIsActive = false
child.Cooldown:Clear()

child.isActive = true
child.cooldownIsActive = nil
child.wasSetFromAura = false
child.wasSetFromCooldown = true
child.wasSetFromCharges = false
child.Cooldown:SetCooldownFromDurationObject(cooldownDuration)
state = assert(ns.CDMBlizzMirror.GetStateByCooldownID(27902), "mirror state missing before GCD priority hook")
assert(state.durObj == cooldownDuration, "GCD priority test should start on the cooldown lane")

local originalGetSpellCooldown = C_Spell.GetSpellCooldown
C_Spell.GetSpellCooldown = function(spellID)
    if spellID == 1233448 then
        return {
            isActive = true,
            isEnabled = true,
            isOnGCD = true,
            startTime = 120,
            duration = 1.5,
        }
    end
    return originalGetSpellCooldown(spellID)
end

child.wasSetFromAura = false
child.wasSetFromCooldown = false
child.wasSetFromCharges = false
child.Cooldown:SetCooldownFromDurationObject(gcdDuration)
C_Spell.GetSpellCooldown = originalGetSpellCooldown

state = assert(ns.CDMBlizzMirror.GetStateByCooldownID(27902), "mirror state missing after GCD priority hook")
assert(state.gcdDurObj == gcdDuration, "GCD duration should be carried in the GCD lane")
assert(state.cooldownDurObj == cooldownDuration, "GCD duration must not clear the cooldown lane")
assert(state.durObj == cooldownDuration, "cooldown duration should stay selected ahead of GCD")

child.cooldownIsActive = false
child.Cooldown:Clear()

local packedStateAgain = assert(ns.CDMBlizzMirror.GetStateByCooldownID(27902), "second packed mirror state missing")
assert(packedStateAgain == state, "mirror lookups for the same instance should reuse the packed state table")

auraChild.Cooldown:SetCooldownFromDurationObject(auraSpellCooldownDuration)

local auraDurationState = assert(ns.CDMBlizzMirror.GetStateByCooldownID(73542), "aura mirror state missing after DurationObject hook")
assert(auraDurationState.isActive == true, "aura DurationObject hook should mark the mirror active")
assert(auraDurationState.auraDurObj == auraSpellCooldownDuration, "aura viewer entries should mirror child DurationObjects into the aura lane")
assert(auraDurationState.auraDurObjSource == "aura-child", "aura child DurationObjects should be identified as the child source")
assert(auraDurationState.durObj == auraSpellCooldownDuration, "aura viewer entries should select child DurationObjects first")
assert(auraDurationState.durObjSource == "aura-child", "aura viewer selected duration source should identify the child")

auraChild.Cooldown:SetCooldown()

local auraState = assert(ns.CDMBlizzMirror.GetStateByCooldownID(73542), "aura mirror state missing")
assert(auraState.isActive == true, "aura SetCooldown should mark the mirror active")
assert(auraState.durObj == auraSpellCooldownDuration, "aura SetCooldown should preserve the child DurationObject")
assert(auraState.durObjSource == "aura-child", "aura SetCooldown should not replace child duration with spell cooldown")

ns.CDMSources.QueryAuraDuration = function(unit, auraInstanceID)
    if unit == "player" and auraInstanceID == 101 then
        return auraPayloadDuration
    end
end

ns.CDMBlizzMirror.HandleUnitAuraChanged("player", {
    addedAuras = {
        { spellId = 1242998, auraInstanceID = 101 },
    },
})

auraState = assert(ns.CDMBlizzMirror.GetStateByCooldownID(73542), "aura mirror state missing after UNIT_AURA payload")
assert(auraState.isActive == true, "UNIT_AURA payload should preserve active aura state")
assert(auraState.hasAuraInstanceID == true, "UNIT_AURA payload should still stamp the aura instance")
assert(auraState.auraDurObj == auraSpellCooldownDuration, "UNIT_AURA payload should not overwrite the child DurationObject")
assert(auraState.durObj == auraSpellCooldownDuration, "aura viewer entries should keep selecting child duration first")
assert(auraState.durObjSource == "aura-child", "child duration should stay selected after UNIT_AURA payload")

local queriedPlayerAura = false
local queriedUnitAura = false
ns.CDMSources.QueryPlayerAuraBySpellID = function(spellID)
    if spellID == 1254252 then
        queriedPlayerAura = true
    end
    return nil
end
ns.CDMSources.QueryUnitAuraBySpellID = function(unit, spellID)
    if unit == "player" and spellID == 1254252 then
        queriedUnitAura = true
        return { spellId = 1254252, auraInstanceID = 202 }
    end
    return nil
end
ns.CDMSources.QueryAuraDuration = function(unit, auraInstanceID)
    if unit == "player" and auraInstanceID == 202 then
        return auraUnitFallbackDuration
    end
end

ns.CDMBlizzMirror.HandleUnitAuraChanged("player", { isFullUpdate = true })

local fallbackState = assert(ns.CDMBlizzMirror.GetStateByCooldownID(141686), "fallback aura mirror state missing")
assert(queriedPlayerAura == true, "test must exercise the player aura lookup miss")
assert(queriedUnitAura == true, "player aura scan should fall back to unit aura lookup")
assert(fallbackState.auraDurObj == auraUnitFallbackDuration, "unit aura fallback should stamp the aura DurationObject")
assert(fallbackState.durObj == auraUnitFallbackDuration, "aura viewer should select the unit fallback DurationObject")

local queriedTrackedBarAura = false
ns.CDMSources.QueryPlayerAuraBySpellID = function(spellID)
    if spellID == 1235391 then
        queriedTrackedBarAura = true
        return { spellId = 1235391, auraInstanceID = 303 }
    end
    return nil
end
ns.CDMSources.QueryUnitAuraBySpellID = function()
    return nil
end
ns.CDMSources.QueryAuraDuration = function(unit, auraInstanceID)
    if unit == "player" and auraInstanceID == 303 then
        return trackedBarAuraDuration
    end
end

trackedBarChild.Cooldown:SetCooldown()

local trackedBarState = assert(ns.CDMBlizzMirror.GetStateByCooldownID(27925, "trackedBar"), "trackedBar mirror state missing")
assert(queriedTrackedBarAura == true, "trackedBar SetCooldown should query the linked aura identity")
assert(trackedBarState.isActive == true, "trackedBar SetCooldown should mark the aura active")
assert(trackedBarState.hasAuraInstanceID == true, "trackedBar SetCooldown should stamp the aura instance")
assert(trackedBarState.auraDurObj == trackedBarAuraDuration, "trackedBar SetCooldown should capture the aura DurationObject")
assert(trackedBarState.durObj == trackedBarAuraDuration, "trackedBar aura entries should select captured aura DurationObjects")

local trackedPayload = assert(ns.CDMBlizzMirror.GetCooldownMethodTestPayload(27925, "trackedBar"), "trackedBar test payload missing")
local foundCurrentFieldProbe = false
local foundRelatedEssentialProbe = false
for _, line in ipairs(trackedPayload.auraProbeLines or {}) do
    if line:find("frameField label=current.trackedBar.27925.child key=auraInstanceID", 1, true) then
        foundCurrentFieldProbe = true
    end
    if line:find("related cat=essential", 1, true) then
        foundRelatedEssentialProbe = true
    end
end
assert(foundCurrentFieldProbe == true, "trackedBar payload should probe current child aura fields")
assert(foundRelatedEssentialProbe == true, "trackedBar payload should probe the related essential child")

trackedBarChild.Cooldown:Clear()
trackedBarChild.auraInstanceID = 505
trackedBarChild.auraDataUnit = "player"
trackedBarChild.auraData = childFrameAuraData
ns.CDMSources.QueryPlayerAuraBySpellID = function()
    return nil
end
ns.CDMSources.QueryUnitAuraBySpellID = function()
    return nil
end
ns.CDMSources.QueryAuraDuration = function(unit, auraInstanceID)
    if unit == "player" and auraInstanceID == 505 then
        return childFrameAuraDuration
    end
end

trackedBarChild.Cooldown:SetCooldown()

trackedBarState = assert(ns.CDMBlizzMirror.GetStateByCooldownID(27925, "trackedBar"), "trackedBar child-frame state missing")
assert(trackedBarState.hasAuraInstanceID == true, "trackedBar child auraInstanceID should stamp the mirror")
assert(trackedBarState.auraDurObj == childFrameAuraDuration, "trackedBar child auraInstanceID should capture the DurationObject")
assert(trackedBarState.durObj == childFrameAuraDuration, "trackedBar child auraInstanceID should drive the selected duration")
assert(trackedBarState.auraData == childFrameAuraData, "trackedBar child auraData should be preserved as mirror state")

trackedBarChild.Cooldown:Clear()
trackedBarChild.auraInstanceID = nil
trackedBarChild.auraDataUnit = "player"
trackedBarChild.auraData = childAuraDataOnly
child.auraInstanceID = nil
child.auraDataUnit = nil
ns.CDMSources.QueryAuraDuration = function(unit, auraInstanceID)
    if unit == "player" and auraInstanceID == 515 then
        return childAuraDataOnlyDuration
    end
end

trackedBarChild.Cooldown:SetCooldown()

trackedBarState = assert(ns.CDMBlizzMirror.GetStateByCooldownID(27925, "trackedBar"), "trackedBar child auraData-only state missing")
assert(trackedBarState.hasAuraInstanceID == true, "trackedBar child auraData.auraInstanceID should stamp the mirror")
assert(trackedBarState.auraDurObj == childAuraDataOnlyDuration, "trackedBar child auraData.auraInstanceID should capture the DurationObject immediately")
assert(trackedBarState.durObj == childAuraDataOnlyDuration, "trackedBar child auraData.auraInstanceID should drive the selected duration")
assert(trackedBarState.auraData == childAuraDataOnly, "trackedBar child auraData-only path should preserve child auraData")

trackedBarChild.Cooldown:Clear()
trackedBarChild.auraInstanceID = nil
trackedBarChild.auraDataUnit = "player"
trackedBarChild.auraData = childCombatAuraDataOnly
ns.CDMSources.QueryAuraDuration = function(unit, auraInstanceID)
    if unit == "player" and auraInstanceID == 516 then
        return childCombatAuraDataOnlyDuration
    end
end
function InCombatLockdown() return true end

trackedBarChild.Cooldown:SetCooldown()

function InCombatLockdown() return false end
trackedBarState = assert(ns.CDMBlizzMirror.GetStateByCooldownID(27925, "trackedBar"), "trackedBar combat child auraData-only state missing")
assert(trackedBarState.hasAuraInstanceID == true, "combat trackedBar child auraData.auraInstanceID should stamp the mirror")
assert(trackedBarState.auraDurObj == childCombatAuraDataOnlyDuration, "combat trackedBar child auraData.auraInstanceID should capture the DurationObject immediately")
assert(trackedBarState.durObj == childCombatAuraDataOnlyDuration, "combat trackedBar child auraData.auraInstanceID should drive the selected duration")
assert(trackedBarState.auraData == childCombatAuraDataOnly, "combat trackedBar child auraData-only path should preserve child auraData")

trackedBarChild.Cooldown:Clear()
trackedBarChild.auraInstanceID = nil
trackedBarChild.auraDataUnit = nil
trackedBarChild.auraData = nil
child.auraInstanceID = 606
child.auraDataUnit = "player"
ns.CDMSources.QueryAuraDuration = function(unit, auraInstanceID)
    if unit == "player" and auraInstanceID == 606 then
        return relatedChildFrameAuraDuration
    end
end

trackedBarChild.Cooldown:SetCooldown()

trackedBarState = assert(ns.CDMBlizzMirror.GetStateByCooldownID(27925, "trackedBar"), "trackedBar related-frame state missing")
assert(trackedBarState.hasAuraInstanceID == true, "related cooldown child auraInstanceID should stamp trackedBar mirror")
assert(trackedBarState.auraDurObj == relatedChildFrameAuraDuration, "related cooldown child should provide trackedBar aura DurationObject")
assert(trackedBarState.durObj == relatedChildFrameAuraDuration, "related cooldown child duration should drive trackedBar duration")

trackedBarChild.Cooldown:Clear()
trackedBarChild.auraInstanceID = nil
trackedBarChild.auraDataUnit = nil
child.auraInstanceID = nil
child.auraDataUnit = nil

local queriedCooldownAuraMap = false
local queriedMappedFilteredAura = false
ns.CDMSources.QueryCooldownAuraBySpellID = function(spellID)
    if spellID == 1242158 then
        queriedCooldownAuraMap = true
        return 555001
    end
    return nil
end
ns.CDMSources.QueryPlayerAuraBySpellID = function()
    return nil
end
ns.CDMSources.QueryUnitAuraBySpellID = function(unit, spellID, filter)
    if unit == "player" and spellID == 555001 and filter == "HELPFUL" then
        queriedMappedFilteredAura = true
        return { spellId = 555001, auraInstanceID = 404 }
    end
    return nil
end
ns.CDMSources.QueryAuraDuration = function(unit, auraInstanceID)
    if unit == "player" and auraInstanceID == 404 then
        return cooldownAuraMappedDuration
    end
end

cooldownAuraMappedChild.Cooldown:SetCooldown()

local cooldownAuraMappedState = assert(ns.CDMBlizzMirror.GetStateByCooldownID(69057, "trackedBar"), "cooldown-aura mapped state missing")
assert(queriedCooldownAuraMap == true, "trackedBar capture should query the cooldown-aura spell mapping")
assert(queriedMappedFilteredAura == true, "trackedBar capture should try filtered aura lookup for mapped IDs")
assert(cooldownAuraMappedState.hasAuraInstanceID == true, "mapped cooldown-aura lookup should stamp the aura instance")
assert(cooldownAuraMappedState.durObj == cooldownAuraMappedDuration, "mapped cooldown-aura lookup should capture the DurationObject")

ns.CDMSources.QueryAuraDuration = function(unit, auraInstanceID)
    if unit == "player" and auraInstanceID == 707 then
        return amzAuraDuration
    end
end

amzBuffChild.auraInstanceID = nil
amzBuffChild.auraDataUnit = nil
amzUtilityChild.Cooldown:SetCooldown()
local amzUtilityState = assert(ns.CDMBlizzMirror.GetStateByCooldownID(27911, "utility"), "AMZ utility mirror state missing before aura")
assert(amzUtilityState.cooldownDurObj == amzCooldownDuration, "AMZ utility should start with its own spell cooldown lane")
assert(amzUtilityState.auraDurObj == nil, "AMZ utility should not have an aura lane before the related buff child has an instance")

amzBuffChild.auraInstanceID = 707
amzBuffChild.auraDataUnit = "player"
amzBuffChild:SetShown(true)
local amzBuffState = assert(ns.CDMBlizzMirror.GetStateByCooldownID(103071, "buff"), "AMZ buff mirror state missing")
assert(amzBuffState.isActive == true, "AMZ buff child auraInstanceID should make the buff mirror active")
assert(amzBuffState.hasAuraInstanceID == true, "AMZ buff child auraInstanceID should be stamped")
assert(amzBuffState.auraDurObj == amzAuraDuration, "AMZ buff child auraInstanceID should capture the aura duration")

amzUtilityState = assert(ns.CDMBlizzMirror.GetStateByCooldownID(27911, "utility"), "AMZ utility mirror state missing after aura")
assert(amzUtilityState.isActive == true, "AMZ utility child should stay active")
assert(amzUtilityState.cooldownDurObj == amzCooldownDuration, "AMZ utility should keep its own spell cooldown lane")
assert(amzUtilityState.hasAuraInstanceID == true, "AMZ utility should borrow the related buff child aura instance")
assert(amzUtilityState.auraUnit == "player", "AMZ utility should trust the related buff child aura unit")
assert(amzUtilityState.auraDurObj == amzAuraDuration, "AMZ utility should borrow the related buff child aura duration")
assert(amzUtilityState.durObj == amzAuraDuration, "AMZ utility should select the related aura duration ahead of cooldown")
assert(amzUtilityState.durObjSource == "aura-related-child", "AMZ utility selected duration should identify the related aura child")

local reapingState = assert(ns.CDMBlizzMirror.GetStateByCooldownID(70765, "buff"), "Reaping buff mirror state missing")
assert(reapingState.isActive == false, "Reaping test should start inactive")

local refreshBeforeSetShown = iconRefreshCount
reapingChild.isActive = true
reapingChild:SetShown(true)

reapingState = assert(ns.CDMBlizzMirror.GetStateByCooldownID(70765, "buff"), "Reaping buff mirror state missing after SetShown")
assert(reapingState.isActive == true, "durationless buff child SetShown should mirror child.isActive")
assert(reapingState.durObj == nil, "durationless buff child should not invent a DurationObject")
assert(iconRefreshCount > refreshBeforeSetShown, "durationless buff child SetShown should request an icon refresh")

reapingChild.isActive = false
reapingChild:SetShown(false)
reapingState = assert(ns.CDMBlizzMirror.GetStateByCooldownID(70765, "buff"), "Reaping buff mirror state missing after SetShown false")
assert(reapingState.isActive == false, "durationless buff child SetShown(false) should clear active state")

assert(registeredEvents.SPELL_ACTIVATION_OVERLAY_GLOW_SHOW == true,
    "mirror should listen for spell activation overlay show events")
assert(registeredEvents.SPELL_ACTIVATION_OVERLAY_GLOW_HIDE == true,
    "mirror should listen for spell activation overlay hide events")
assert(type(eventScript) == "function", "mirror event script should be installed")

local refreshBeforeOverlay = iconRefreshCount
reapingChild.isActive = true
eventScript(nil, "SPELL_ACTIVATION_OVERLAY_GLOW_SHOW", 1235261)

reapingState = assert(ns.CDMBlizzMirror.GetStateByCooldownID(70765, "buff"), "Reaping buff mirror state missing after overlay event")
assert(reapingState.isActive == true, "spell activation overlay should refresh durationless buff child state")
assert(iconRefreshCount > refreshBeforeOverlay, "spell activation overlay should request an icon refresh")

-- Totem-backed buff entry: guardian-summoning self-buffs (e.g. Raise
-- Abomination) carry hasAura=false on the parent cdID, so the aura-viewer
-- branch in SelectDurationForState has no auraDurObj to select. The mirror
-- captures the duration via PLAYER_TOTEM_UPDATE -> _ActivateTotemCooldownID
-- and SelectDurationForState must fall through to the totem lane, then
-- resolve mode as "aura" so the buff viewer renders a swipe instead of
-- dead-ending at durObj=nil.
local totemBuffDuration = { token = "totem-buff-duration-object" }
local totemChildDuration = { token = "totem-child-duration-object" }
MAX_TOTEMS = 4
GetTotemInfo = function(slot)
    if slot == 1 then
        return true, "Reaping", 0, 60, "Interface\\Icons\\Reaping", 0, 1235261
    end
    return false
end
GetTotemDuration = function(slot)
    if slot == 1 then
        return totemBuffDuration
    end
    return nil
end

reapingChild.Cooldown:SetCooldownFromDurationObject(totemChildDuration)

ns.CDMBlizzMirror.HandlePlayerTotemUpdate()

local totemBuffState = assert(ns.CDMBlizzMirror.GetStateByCooldownID(70765, "buff"),
    "Reaping buff mirror state missing after totem update")
assert(totemBuffState.isActive == true,
    "PLAYER_TOTEM_UPDATE should mark the totem-backed buff cdID active")
assert(totemBuffState.totemDurObj == totemBuffDuration,
    "PLAYER_TOTEM_UPDATE should populate the totem lane on the buff cdID")
assert(totemBuffState.durObj == totemBuffDuration,
    "totem-backed buff viewer should prefer the totem-slot duration over child cooldown duration")
assert(totemBuffState.durObjSource == "totem-duration",
    "selected duration source should identify the totem lane")
assert(totemBuffState.resolvedMode == "aura",
    "totem-backed buff entry should resolve mode as aura for buff viewer rendering")

local highSlotTotemDuration = { token = "high-slot-totem-duration-object" }
GetNumTotemSlots = function() return 6 end
GetTotemInfo = function(slot)
    if slot == 6 then
        return true, "Reaping", 0, 60, "Interface\\Icons\\Reaping", 0, 1235261
    end
    return false
end
GetTotemDuration = function(slot)
    if slot == 6 then
        return highSlotTotemDuration
    end
    return nil
end

ns.CDMBlizzMirror.HandlePlayerTotemUpdate(6)

totemBuffState = assert(ns.CDMBlizzMirror.GetStateByCooldownID(70765, "buff"),
    "Reaping buff mirror state missing after high-slot totem update")
assert(totemBuffState.isActive == true,
    "PLAYER_TOTEM_UPDATE should scan the full totem slot count")
assert(totemBuffState.totemSlot == 6,
    "PLAYER_TOTEM_UPDATE should preserve the active totem slot")
assert(totemBuffState.totemDurObj == highSlotTotemDuration,
    "PLAYER_TOTEM_UPDATE should populate the totem lane from high-numbered slots")
assert(totemBuffState.durObj == highSlotTotemDuration,
    "totem-backed buff viewer should select the high-slot totem duration")

local preferredSlotTotemDuration = { token = "preferred-slot-totem-duration-object" }
local preferredSlotDurationArg
GetNumTotemSlots = function() return 4 end
GetTotemInfo = function(slot)
    if slot == preferredTotemSlotToken then
        return true, "Raise Abomination", 0, 30, "Interface\\Icons\\RaiseAbomination", 0, 288853
    end
    return false
end
GetTotemDuration = function(slot)
    preferredSlotDurationArg = slot
    if slot == preferredTotemSlotToken then
        return preferredSlotTotemDuration
    end
    return nil
end

reapingChild.totemData = secretTotemDataToken
local preferredSlotOk, preferredSlotErr = pcall(ns.CDMBlizzMirror.HandlePlayerTotemUpdate)
reapingChild.totemData = nil
assert(preferredSlotOk, preferredSlotErr)

local preferredTotemState = assert(ns.CDMBlizzMirror.GetStateByCooldownID(92923, "buff"),
    "Raise Abomination buff mirror state missing after preferred-slot totem update")
assert(preferredTotemState.isActive == true,
    "preferred totem slot should keep the totem-backed buff cdID active")
assert(preferredSlotDurationArg == preferredTotemSlotToken,
    "PLAYER_TOTEM_UPDATE should pass the child preferred totem slot opaquely to GetTotemDuration")
assert(preferredTotemState.totemSlot == nil,
    "secret preferred totem slots must not be stored in mirror state")
assert(preferredTotemState.totemDurObj == preferredSlotTotemDuration,
    "preferred totem slot should populate the totem lane on the buff cdID")
assert(preferredTotemState.durObj == preferredSlotTotemDuration,
    "totem-backed buff viewer should select the child preferred-slot duration")

-- Tear down the totem so it doesn't bleed into the mirror stats counts
-- below (stale active totems hold the buff cdID's mirror state open).
GetTotemInfo = function() return false end
ns.CDMBlizzMirror.HandlePlayerTotemUpdate()
GetNumTotemSlots = nil

local mirrorStats = ns.CDMBlizzMirror.GetCacheStats and ns.CDMBlizzMirror.GetCacheStats()
assert(mirrorStats, "mirror should expose cache stats")
assert(mirrorStats.mirrorStates >= 1, "mirror stats should include mirrored state count")
assert(mirrorStats.packedStates >= 1, "mirror stats should include packed state count")
assert(mirrorStats.cooldownInfo >= 1, "mirror stats should include cooldown info count")
assert(mirrorStats.spellMapEntries >= 1, "mirror stats should include spell map entry count")

print("OK: cdm_blizz_mirror_duration_test")
