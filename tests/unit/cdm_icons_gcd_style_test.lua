-- tests/unit/cdm_icons_gcd_style_test.lua
-- Run: lua tests/unit/cdm_icons_gcd_style_test.lua

local BuildCooldownStateContext = dofile("tests/helpers/cdm_context_builder_stub.lua")

local function noop() end

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
        UnregisterAllEvents = noop,
        SetScript = noop,
    }
end

C_Timer = {
    After = function(_, callback) callback() end,
    NewTimer = function()
        return { Cancel = noop }
    end,
}

local gcdDuration = { token = "gcd-duration" }
local realDuration = { token = "real-duration" }
local itemAuraDuration = { token = "item-aura-duration" }
local chargedOverrideDuration = { token = "charged-override-duration" }
local chargedOverrideMirrorDuration = { token = "charged-override-mirror-duration" }
local rechargeWithChargeDuration = { token = "recharge-with-charge-duration" }
local preservedMirrorDuration = { token = "preserved-mirror-duration" }
local styleCalls = 0
local styleSawGCD = false
local desaturated
local gcdVisualDesaturated
local usableDesaturated
local resourceDesaturated
local priorMirrorDesaturated
local priorMirrorAppliedDuration
local itemAuraAppliedDuration
local itemAuraReverse
local itemAuraClearWhenZero
local rechargeWithChargeDesaturated
local depletedChargeDesaturated
local fullChargeMirrorDesaturated
local mirrorDesaturated
local staleMirrorDesaturated
local mirrorGapMode = "cooldown"
local chargedOverridePhase = "charge"
local chargedOverrideMirrorActive = true
local cooldownQueryCounts = {}

local function resolvedState(durObj, mode, sourceID, start, duration, spellID, mirrorBacked, mirrorPayload, activity)
    local state = mirrorPayload or {}
    local mirrorState = state.state or state.mirrorState
    state.mode = mode or "inactive"
    state.durObj = durObj
    state.sourceID = sourceID
    state.start = start
    state.duration = duration
    state.spellID = spellID
    state.mirrorBacked = mirrorBacked == true or state.mirrorBacked
    state.state = mirrorState
    state.mirrorState = mirrorState
    state.cooldownID = state.cooldownID or state.mirrorCooldownID or (mirrorState and mirrorState.cooldownID)
    state.category = state.category or state.mirrorCategory or (mirrorState and mirrorState.viewerCategory)
    state.mirrorCooldownID = state.cooldownID
    state.mirrorCategory = state.category
    if state.active == nil then
        if mirrorState and type(mirrorState.isActive) == "boolean" then
            state.active = mirrorState.isActive
        else
            state.active = mode ~= "inactive" and (durObj ~= nil or start ~= nil or mirrorBacked == true)
        end
    end
    state.isActive = state.active
    activity = activity or {}
    -- Under the post-cascade-collapse contract the resolver never returns
    -- mode == "charge"; recharge timers come back as mode == "cooldown" and
    -- the icon renderer queries charges separately when it cares. The helper
    -- mirrors that — no charge-specific OR clauses here.
    if activity.isOnCooldown ~= nil then
        state.isOnCooldown = activity.isOnCooldown == true
    elseif state.mode == "cooldown" or state.mode == "item-cooldown" then
        state.isOnCooldown = state.active == true
    else
        state.isOnCooldown = false
    end
    state.rechargeActive = activity.rechargeActive == true
    state.hasCharges = activity.hasCharges == true
    if activity.hasChargesRemaining ~= nil then
        state.hasChargesRemaining = activity.hasChargesRemaining == true
    else
        state.hasChargesRemaining = state.hasCharges == true
            and state.rechargeActive == true
            and state.isOnCooldown ~= true
    end
    state.gcdOnly = state.mode == "gcd-only"
    state.numericCooldownActive = activity.numericCooldownActive
    state.cooldownInfo = activity.cooldownInfo
    state.cooldownInfoActive = activity.cooldownInfoActive
    state.cooldownInfoOnGCD = activity.cooldownInfoOnGCD
    return state
end

local ns = {
    Helpers = {
        GetGeneralFont = function() return "Fonts\\FRIZQT__.TTF" end,
        GetGeneralFontOutline = function() return "" end,
        CreateDBGetter = function()
            return function()
                return {
                    essential = {
                        desaturateOnCooldown = true,
                    },
                }
            end
        end,
        IsSecretValue = function() return false end,
        SafeValue = function(value) return value end,
        SafeToNumber = function(value) return value end,
        CanAccessTable = function(tbl) return type(tbl) == "table" end,
    },
    Addon = {
        db = {
            profile = { ncdm = {} },
            char = { ncdm = {} },
        },
    },
    CDMShared = {
        IsRuntimeEnabled = function() return true end,
        IsSafeNumeric = function(value) return type(value) == "number" end,
    },
    CDMSources = {
        QuerySpellUsable = function(spellID)
            if spellID == 13579 then
                return true, false
            end
            if spellID == 1227280 then
                return true, false
            end
            if spellID == 1227281 then
                return true, false
            end
            if spellID == 121536 then
                return true, false
            end
            if spellID == 86421 then
                return true, false
            end
            if spellID == 97531 then
                return false, true
            end
            return nil, nil
        end,
        QuerySpellCharges = function(spellID)
            return nil
        end,
        QuerySpellCooldown = function(spellID)
            cooldownQueryCounts[spellID] = (cooldownQueryCounts[spellID] or 0) + 1
            if spellID == 24680 then
                return { isActive = true, isOnGCD = true }
            end
            if spellID == 13579 then
                return { isActive = true, isOnGCD = false }
            end
            if spellID == 97531 then
                return { isActive = true, isOnGCD = false }
            end
            if spellID == 1227280 then
                return { isActive = true, isOnGCD = true }
            end
            if spellID == 1227281 then
                return { isActive = true, isOnGCD = false }
            end
            if spellID == 121536 then
                return { isActive = true, isOnGCD = false, startTime = 0, duration = 0 }
            end
            if spellID == 86420 then
                return { isActive = false, isOnGCD = nil }
            end
            if spellID == 86421 then
                return { isActive = false, isOnGCD = nil }
            end
            if spellID == 86424 then
                -- Legitimate transient gap scenario: the live API confirms
                -- the CD is still active (isActive=true) while the mirror
                -- briefly resolves to gcd-only. Preservation MUST fire here.
                return { isActive = true, isOnGCD = true, startTime = 0, duration = 0 }
            end
            if spellID == 86426 then
                -- Genuine CD-end scenario: live API authoritatively says
                -- the cooldown has ended. Preservation MUST NOT fire even
                -- if the icon was just in mirror-cooldown mode.
                return { isActive = false, isOnGCD = nil, startTime = 0, duration = 0 }
            end
            if spellID == 86425 then
                return { isActive = false, isOnGCD = nil, startTime = 0, duration = 0 }
            end
            if spellID == 450983 then
                return { isActive = true, isOnGCD = false, startTime = 10, duration = 8 }
            end
            if spellID == 8092 then
                return { isActive = true, isOnGCD = true, startTime = 20, duration = 1.5 }
            end
            return nil
        end,
        QuerySpellCooldownDuration = function(spellID)
            return nil
        end,
        QuerySpellChargeDuration = function(spellID)
            return nil
        end,
        QueryOverrideSpell = function() return nil end,
        QuerySpellDisplayCount = function() return nil end,
        QuerySpellCount = function() return nil end,
    },
    CDMResolvers = {
        BuildCooldownStateContext = BuildCooldownStateContext,
        _textureCycleCache = {},
        _FinalizeImports = noop,
        Subscribe = noop,
        GetSpellTexture = function() return nil end,
        ResolveMacro = function() return nil end,
        GetEntryTexture = function() return nil end,
        IsAuraEntry = function(entry) return entry and entry.kind == "aura" end,
        ResolveSpellActiveState = function() return nil end,
        ResolveCooldownActivityState = function() return nil end,
        ResolveCooldownState = function(context)
            local entry = context and context.entry
            local id = entry and entry.id
            if id == 24680 then
                return resolvedState(realDuration, "cooldown", 24680, nil, nil, 24680)
            end
            if id == 241288 then
                local state = resolvedState(itemAuraDuration,
                    "aura",
                    "item-aura-instance:241288",
                    nil,
                    nil,
                    1236994,
                    nil,
                    nil,
                    {
                        isOnCooldown = false,
                    })
                state.auraResolved = true
                state.auraActive = true
                state.auraIsActive = true
                state.auraUnit = "player"
                state.auraInstanceID = 94001
                state.resolvedAuraSpellID = 440289
                return state
            end
            if id == 13579 then
                return resolvedState(realDuration, "cooldown", 13579, nil, nil, 13579, nil, nil, {
                    isOnCooldown = false,
                    cooldownInfoActive = true,
                    cooldownInfoOnGCD = false,
                })
            end
            if id == 97531 then
                return resolvedState(realDuration, "cooldown", 97531, nil, nil, 97531)
            end
            if id == 1227280 then
                return resolvedState(rechargeWithChargeDuration, "charge", "1227280:1", nil, nil, 1227280, nil, nil, {
                    isOnCooldown = false,
                    rechargeActive = true,
                    hasCharges = true,
                    hasChargesRemaining = true,
                    cooldownInfoActive = false,
                    cooldownInfoOnGCD = true,
                })
            end
            if id == 1227281 then
                return resolvedState(rechargeWithChargeDuration, "charge", "1227281:1", nil, nil, 1227281, nil, nil, {
                    isOnCooldown = true,
                    rechargeActive = true,
                    hasCharges = true,
                    hasChargesRemaining = false,
                    cooldownInfoActive = true,
                    cooldownInfoOnGCD = false,
                })
            end
            if id == 121536 then
                return resolvedState(nil,
                    "cooldown",
                    "mirror:7478:291",
                    nil,
                    nil,
                    121536,
                    true,
                    {
                        state = {
                            cooldownID = 7478,
                            viewerCategory = "utility",
                            isActive = true,
                            resolvedMode = nil,
                        },
                    },
                    {
                        isOnCooldown = false,
                        hasCharges = true,
                        rechargeActive = true,
                        hasChargesRemaining = true,
                    })
            end
            if id == 86420 then
                cooldownQueryCounts[86420] = (cooldownQueryCounts[86420] or 0) + 1
                return resolvedState(nil, "inactive", nil, nil, nil, 86420)
            end
            if id == 86421 then
                return resolvedState(nil, "inactive", nil, nil, nil, 86421)
            end
            if id == 86422 then
                return resolvedState(realDuration, "cooldown", "mirror:779:11", nil, nil, 86422, true)
            end
            if id == 86424 then
                if mirrorGapMode == "gcd-only" then
                    return resolvedState(gcdDuration, "gcd-only", 86424, nil, nil, 86424)
                end
                return resolvedState(realDuration, "cooldown", "mirror:780:12", nil, nil, 86424, true, nil, {
                    isOnCooldown = false,
                    cooldownInfoActive = true,
                    cooldownInfoOnGCD = true,
                })
            end
            if id == 86425 then
                return resolvedState(nil, "inactive", nil, nil, nil, 86425)
            end
            if id == 86426 then
                if mirrorGapMode == "inactive" then
                    return resolvedState(nil, "inactive", nil, nil, nil, 86426)
                end
                return resolvedState(nil, "inactive", nil, nil, nil, 86426)
            end
            if id == 8092 then
                if chargedOverridePhase == "charge" then
                    return resolvedState(chargedOverrideDuration, "charge", "450983:7", nil, nil, 450983, nil, nil, {
                        isOnCooldown = true,
                        rechargeActive = true,
                        hasCharges = true,
                        hasChargesRemaining = false,
                        cooldownInfoActive = true,
                        cooldownInfoOnGCD = false,
                    })
                end
                if chargedOverridePhase == "inactive" then
                    return resolvedState(nil, "inactive", nil, nil, nil, 8092)
                end
                return resolvedState(chargedOverrideMirrorDuration,
                    "cooldown",
                    "mirror:8194:47",
                    nil,
                    nil,
                    8092,
                    true,
                    {
                        state = {
                            cooldownID = 8194,
                            viewerCategory = "essential",
                            isActive = true,
                            resolvedMode = "cooldown",
                        },
                    },
                    {
                        isOnCooldown = true,
                        cooldownInfoActive = true,
                        cooldownInfoOnGCD = true,
                    })
            end
            if id == 212121 then
                return resolvedState(preservedMirrorDuration,
                    "cooldown",
                    "mirror:27927:2218",
                    nil,
                    nil,
                    212121,
                    true,
                    nil,
                    {
                        isOnCooldown = true,
                        cooldownInfoActive = true,
                        cooldownInfoOnGCD = false,
                    })
            end
            local fallbackID = id or 12345
            return resolvedState(gcdDuration, "gcd-only", fallbackID, nil, nil, fallbackID)
        end,
    },
    CDMBlizzMirror = {
        GetStateByCooldownID = function(cooldownID, viewerCategory)
            if cooldownID == 8194 and viewerCategory == "essential" then
                return {
                    cooldownID = 8194,
                    viewerCategory = "essential",
                    isActive = chargedOverrideMirrorActive,
                    resolvedMode = chargedOverrideMirrorActive and "cooldown" or nil,
                }
            end
            return nil
        end,
    },
    CDMIconFactory = {
        _FinalizeImports = noop,
        AcquireIcon = noop,
        ReleaseIcon = noop,
    },
    CDMRuntimeStore = {
        SetIconState = noop,
    },
    _OwnedSwipe = {
        ApplyToIcon = function(icon)
            styleCalls = styleCalls + 1
            styleSawGCD = icon and icon._showingGCDSwipe == true
        end,
    },
}

dofile("tests/helpers/load_cdm_icon_runtime.lua")(ns)
assert(loadfile("QUI_CDM/cdm/cdm_icon_renderer.lua"))("QUI", ns)

local icon = {
    Cooldown = {
        SetCooldownFromDurationObject = noop,
        SetReverse = noop,
        SetSwipeTexture = noop,
        Clear = noop,
    },
    _showingGCDSwipe = nil,
    _showingRealCooldownSwipe = true,
    _spellEntry = {
        id = 12345,
        spellID = 12345,
        kind = "cooldown",
        type = "spell",
        viewerType = "essential",
    },
}

local applied = ns.CDMIcons.ApplyResolvedCooldown(icon)

assert(applied == true, "GCD-only duration should be applied")
assert(icon._showingGCDSwipe == true, "GCD-only duration should mark the icon as showing GCD")
assert(styleCalls == 1, "GCD-only duration should reapply swipe styling immediately")
assert(styleSawGCD == true, "swipe styling should run after the GCD flag is set")

local itemAuraIcon = {
    Cooldown = {
        SetCooldownFromDurationObject = function(_, durObj, clearWhenZero)
            itemAuraAppliedDuration = durObj
            itemAuraClearWhenZero = clearWhenZero
        end,
        SetReverse = function(_, reverse)
            itemAuraReverse = reverse
        end,
        SetSwipeTexture = noop,
        Clear = noop,
    },
    _spellEntry = {
        id = 241288,
        itemID = 241288,
        kind = "cooldown",
        type = "item",
        viewerType = "essential",
    },
}

applied = ns.CDMIcons.ApplyResolvedCooldown(itemAuraIcon)

assert(applied == true, "item aura DurationObject should be applied")
assert(itemAuraIcon._resolvedCooldownMode == "aura", "item aura should stamp resolved icon mode")
assert(itemAuraIcon._auraActive == true, "item aura should stamp active aura metadata on the icon")
assert(itemAuraIcon._lastAuraDurObj == itemAuraDuration, "item aura should cache its aura DurationObject")
assert(itemAuraIcon._activeAuraSpellID == 440289, "item aura should stamp the resolved buff spell")
assert(itemAuraAppliedDuration == itemAuraDuration, "item aura should bind the DurationObject to the cooldown frame")
assert(itemAuraClearWhenZero == true, "item aura DurationObject should use clear-when-zero")
assert(itemAuraReverse == true, "item aura cooldown frame should run in aura/reverse mode")
assert(itemAuraIcon._hasCooldownActive == false, "item aura should not mark the item as a real cooldown")

local gcdVisualIcon = {
    Cooldown = {
        SetCooldownFromDurationObject = noop,
        SetReverse = noop,
        SetSwipeTexture = noop,
    },
    Icon = {
        SetDesaturated = function(_, value)
            gcdVisualDesaturated = value
        end,
        SetVertexColor = noop,
    },
    _cdDesaturated = true,
    _showingGCDSwipe = nil,
    _spellEntry = {
        id = 12345,
        spellID = 12345,
        kind = "cooldown",
        type = "spell",
        viewerType = "essential",
    },
}

applied = ns.CDMIcons.ApplyResolvedCooldown(gcdVisualIcon)

-- gcd-only means the visible swipe is a GCD, not a real CD
-- (feedback_blizz_cd_state_signals). The real CD is either over or shorter
-- than the remaining GCD, so the icon must NOT remain desaturated even if
-- a prior real-CD pass set _cdDesaturated=true. Without releasing here the
-- icon stayed grey through the entire GCD-after-CD-end chain until the
-- next inactive transition (3+ second visible stuck-desat window).
assert(applied == true, "GCD-only duration should still be applied when icon has existing visual state")
assert(gcdVisualDesaturated == false, "GCD-only must clear prior real-CD desat; the visible swipe is a GCD, the spell is usable")
assert(gcdVisualIcon._cdDesaturated == nil, "GCD-only must clear the _cdDesaturated ownership flag along with the visual state")

local realCooldownIcon = {
    Cooldown = {
        SetCooldownFromDurationObject = noop,
        SetReverse = noop,
        SetSwipeTexture = noop,
    },
    Icon = {
        SetDesaturated = function(_, value)
            desaturated = value
        end,
        SetVertexColor = noop,
    },
    _showingGCDSwipe = true,
    _showingRealCooldownSwipe = true,
    _hasCooldownActive = true,
    _hasRealCooldownActive = true,
    _spellEntry = {
        id = 24680,
        spellID = 24680,
        kind = "cooldown",
        type = "spell",
        viewerType = "essential",
    },
}

applied = ns.CDMIcons.ApplyResolvedCooldown(realCooldownIcon)

assert(applied == true, "real cooldown duration should be applied")
assert(realCooldownIcon._hasCooldownActive == true, "real cooldown should remain active when the resolved API state is cooldown")
assert(realCooldownIcon._hasRealCooldownActive == true, "real cooldown flag should remain active when the resolved API state is cooldown")
assert(desaturated == true, "real cooldown should stay desaturated when the resolved API state is cooldown")
assert(realCooldownIcon._showingGCDSwipe == nil, "real cooldown should clear stale GCD swipe state")
assert(realCooldownIcon._showingRealCooldownSwipe == true, "real cooldown swipe state should remain set")

local usableCooldownIcon = {
    Cooldown = {
        SetCooldownFromDurationObject = noop,
        SetReverse = noop,
        SetSwipeTexture = noop,
    },
    Icon = {
        SetDesaturated = function(_, value)
            usableDesaturated = value
        end,
        SetVertexColor = noop,
    },
    _spellEntry = {
        id = 13579,
        spellID = 13579,
        kind = "cooldown",
        type = "spell",
        viewerType = "essential",
    },
}

applied = ns.CDMIcons.ApplyResolvedCooldown(usableCooldownIcon)

assert(applied == true, "usable cooldown duration should still be safely applied if provided")
assert(usableCooldownIcon._hasCooldownActive == false, "usable cooldown should not be marked cooldown-active")
assert(usableCooldownIcon._hasRealCooldownActive == false, "usable cooldown should not be marked real-cooldown-active")
assert(usableDesaturated == false, "usable cooldown should not desaturate")

local resourceBlockedIcon = {
    Cooldown = {
        SetCooldownFromDurationObject = noop,
        SetReverse = noop,
        SetSwipeTexture = noop,
    },
    Icon = {
        SetDesaturated = function(_, value)
            resourceDesaturated = value
        end,
        SetVertexColor = noop,
    },
    _spellEntry = {
        id = 97531,
        spellID = 97531,
        kind = "cooldown",
        type = "spell",
        viewerType = "essential",
    },
}

applied = ns.CDMIcons.ApplyResolvedCooldown(resourceBlockedIcon)

assert(applied == true, "resource-blocked cooldown duration should still be safely applied if provided")
assert(resourceBlockedIcon._hasCooldownActive == true, "resource-blocked cooldown should be marked cooldown-active")
assert(resourceBlockedIcon._hasRealCooldownActive == true, "resource-blocked cooldown should be marked real-cooldown-active")
assert(resourceDesaturated == true, "resource-blocked cooldown should desaturate")

local priorMirrorResourceBlockedIcon = {
    Cooldown = {
        SetCooldownFromDurationObject = function(_, durObj)
            priorMirrorAppliedDuration = durObj
        end,
        SetReverse = noop,
        SetSwipeTexture = noop,
    },
    Icon = {
        SetDesaturated = function(_, value)
            priorMirrorDesaturated = value
        end,
        SetVertexColor = noop,
    },
    _hasCooldownActive = true,
    _hasRealCooldownActive = true,
    _showingRealCooldownSwipe = true,
    _lastDurObjKey = "cooldown:mirror:27927:2218",
    _lastDurObj = preservedMirrorDuration,
    _spellEntry = {
        id = 212121,
        spellID = 212121,
        kind = "cooldown",
        type = "spell",
        viewerType = "essential",
    },
}

applied = ns.CDMIcons.ApplyResolvedCooldown(priorMirrorResourceBlockedIcon)

assert(applied == true, "renderer should keep an API-confirmed non-GCD mirror cooldown binding")
assert(priorMirrorAppliedDuration == nil,
    "matching mirror cooldown should dedupe an already-bound DurationObject")
assert(priorMirrorResourceBlockedIcon._lastDurObj == preservedMirrorDuration,
    "matching mirror cooldown should keep the prior DurationObject")
assert(priorMirrorResourceBlockedIcon._resolvedCooldownMode == "cooldown",
    "API-confirmed non-GCD mirror cooldown should keep real-cooldown mode on the icon")
assert(priorMirrorResourceBlockedIcon._lastDurObjKey == "cooldown:mirror:27927:2218",
    "matching mirror cooldown should keep the prior mirror source key")
assert(priorMirrorResourceBlockedIcon._hasCooldownActive == true,
    "API-confirmed non-GCD mirror cooldown should remain cooldown-active")
assert(priorMirrorDesaturated == true,
    "API-confirmed non-GCD mirror cooldown should remain desaturated")

local rechargeWithChargeIcon = {
    Cooldown = {
        SetCooldownFromDurationObject = noop,
        SetReverse = noop,
        SetSwipeTexture = noop,
    },
    Icon = {
        SetDesaturated = function(_, value)
            rechargeWithChargeDesaturated = value
        end,
        SetVertexColor = noop,
    },
    _spellEntry = {
        id = 1227280,
        spellID = 1227280,
        kind = "cooldown",
        type = "spell",
        viewerType = "essential",
        hasCharges = true,
    },
}

applied = ns.CDMIcons.ApplyResolvedCooldown(rechargeWithChargeIcon)

assert(applied == true, "active recharge should keep the charge DurationObject bound")
assert(rechargeWithChargeIcon._resolvedCooldownMode == "charge",
    "active recharge should stay in charge mode for the visible recharge swipe")
assert(rechargeWithChargeIcon._hasCooldownActive == false,
    "recharging spell with a charge remaining should not be marked cooldown-active during GCD")
assert(rechargeWithChargeIcon._hasRealCooldownActive == false,
    "recharging spell with a charge remaining should not be marked real-cooldown-active during GCD")
assert(rechargeWithChargeDesaturated == false,
    "recharging spell with a charge remaining should not desaturate during GCD")

local depletedChargeIcon = {
    Cooldown = {
        SetCooldownFromDurationObject = noop,
        SetReverse = noop,
        SetSwipeTexture = noop,
    },
    Icon = {
        SetDesaturated = function(_, value)
            depletedChargeDesaturated = value
        end,
        SetVertexColor = noop,
    },
    _spellEntry = {
        id = 1227281,
        spellID = 1227281,
        kind = "cooldown",
        type = "spell",
        viewerType = "essential",
        hasCharges = true,
    },
}

applied = ns.CDMIcons.ApplyResolvedCooldown(depletedChargeIcon)

assert(applied == true, "depleted charge cooldown should keep the charge DurationObject bound")
assert(depletedChargeIcon._resolvedCooldownMode == "charge",
    "depleted charge cooldown should stay in charge mode for the visible cooldown swipe")
assert(depletedChargeIcon._hasCooldownActive == true,
    "cdInfo.isActive=true with isOnGCD=false should mark a charged spell unavailable")
assert(depletedChargeIcon._hasRealCooldownActive == true,
    "cdInfo.isActive=true with isOnGCD=false should mark a charged spell real-cooldown-active")
assert(depletedChargeDesaturated == true,
    "charged spell cooldown state should follow cdInfo.isActive rather than QuerySpellUsable")

local fullChargeMirrorIcon = {
    Cooldown = {
        Clear = noop,
        SetCooldownFromDurationObject = noop,
        SetReverse = noop,
        SetSwipeTexture = noop,
    },
    Icon = {
        SetDesaturated = function(_, value)
            fullChargeMirrorDesaturated = value
        end,
        SetVertexColor = noop,
    },
    _cdDesaturated = true,
    _lastChargeMirrorCooldownID = 7478,
    _lastChargeMirrorCategory = "utility",
    _lastChargeRuntimeSpellID = 121536,
    _spellEntry = {
        id = 121536,
        spellID = 121536,
        kind = "cooldown",
        type = "spell",
        viewerType = "utility",
        hasCharges = true,
    },
}

applied = ns.CDMIcons.ApplyResolvedCooldown(fullChargeMirrorIcon)

assert(applied == false,
    "full-charge mirror state without a DurationObject should clear rather than apply")
assert(fullChargeMirrorIcon._hasCooldownActive == false,
    "full-charge mirror state without a DurationObject must not keep the spell unavailable")
assert(fullChargeMirrorIcon._hasRealCooldownActive == false,
    "full-charge mirror state without a DurationObject must not count as a real cooldown")
assert(fullChargeMirrorDesaturated == false,
    "full-charge mirror state without a DurationObject must release cooldown desaturation")
assert(fullChargeMirrorIcon._cdDesaturated == nil,
    "full-charge mirror state without a DurationObject must clear the cooldown desat owner flag")

local mirroredCooldownIcon = {
    Cooldown = {
        SetCooldownFromDurationObject = noop,
        SetReverse = noop,
        SetSwipeTexture = noop,
    },
    Icon = {
        SetDesaturated = function(_, value)
            mirrorDesaturated = value
        end,
        SetVertexColor = noop,
    },
    _spellEntry = {
        id = 86420,
        spellID = 86420,
        kind = "cooldown",
        type = "spell",
        viewerType = "essential",
    },
}

applied = ns.CDMIcons.ApplyResolvedCooldown(mirroredCooldownIcon)

-- cdInfo.isActive is authoritative per feedback_blizz_cd_state_signals.
-- When the mirror reports an active duration but the live API cleanly
-- returns isActive=false (proc-window scenario: Festering Scythe holds
-- Festering Strike's mirror cooldownID active even though the underlying
-- spell isn't on a real cooldown), the resolver must flip to inactive and
-- release the desaturation. Without this override the icon stayed
-- desaturated for the full 12+s proc window and procOnUsable glows were
-- suppressed because IsSpellCastable checks _hasCooldownActive.
assert(applied == false, "mirror with active durObj but cdInfo isActive=false should resolve to inactive")
assert(mirroredCooldownIcon._hasCooldownActive == false,
    "cdInfo isActive=false overrides mirror; icon must not be marked cooldown-active")
assert(mirroredCooldownIcon._hasRealCooldownActive == false,
    "cdInfo isActive=false overrides mirror; icon must not be marked real-cooldown-active")
assert(mirrorDesaturated == false,
    "cdInfo isActive=false overrides mirror; icon must not desaturate")
assert(cooldownQueryCounts[86420] ~= nil,
    "mirror-active resolution must consult live cdInfo so stale mirror state can be overridden")

mirrorDesaturated = nil

local usableMirroredCooldownIcon = {
    Cooldown = {
        SetCooldownFromDurationObject = noop,
        SetReverse = noop,
        SetSwipeTexture = noop,
    },
    Icon = {
        SetDesaturated = function(_, value)
            mirrorDesaturated = value
        end,
        SetVertexColor = noop,
    },
    _spellEntry = {
        id = 86421,
        spellID = 86421,
        kind = "cooldown",
        type = "spell",
        viewerType = "essential",
    },
}

applied = ns.CDMIcons.ApplyResolvedCooldown(usableMirroredCooldownIcon)

-- Same authority rule as 86420: cdInfo.isActive=false beats mirror-active.
-- Spell being usable + mirror reporting active is still a stale-mirror
-- signal when the live API disagrees.
assert(applied == false, "mirror-active + usable but cdInfo isActive=false should still resolve to inactive")
assert(usableMirroredCooldownIcon._hasCooldownActive == false,
    "cdInfo isActive=false overrides mirror even when QuerySpellUsable says true")
assert(usableMirroredCooldownIcon._hasRealCooldownActive == false,
    "cdInfo isActive=false overrides mirror even when QuerySpellUsable says true")
assert(mirrorDesaturated == false,
    "cdInfo isActive=false overrides mirror; icon must not desaturate")

local mirrorClearedPriorDesaturated
local priorDesaturatedMirrorIcon = {
    Cooldown = {
        SetCooldownFromDurationObject = noop,
        SetReverse = noop,
        SetSwipeTexture = noop,
    },
    Icon = {
        SetDesaturated = function(_, value)
            mirrorClearedPriorDesaturated = value
        end,
        SetVertexColor = noop,
    },
    _cdDesaturated = true,
    _spellEntry = {
        id = 86421,
        spellID = 86421,
        kind = "cooldown",
        type = "spell",
        viewerType = "essential",
    },
}

applied = ns.CDMIcons.ApplyResolvedCooldown(priorDesaturatedMirrorIcon)

-- Same authority rule: cdInfo says isActive=false, so the prior _cdDesaturated
-- flag must be released. The icon is no longer on a real cooldown even though
-- it WAS desaturated by an earlier pass. This is the recovery path for the
-- proc-stuck scenario from the trace.
assert(applied == false, "cdInfo isActive=false flips to inactive even with prior _cdDesaturated set")
assert(mirrorClearedPriorDesaturated == false,
    "cdInfo isActive=false releases prior desat; SetDesaturated must be called with false")
assert(priorDesaturatedMirrorIcon._cdDesaturated == nil,
    "cdInfo isActive=false clears the _cdDesaturated flag")

local mirrorNoCooldownInfoDesaturated
local mirrorNoCooldownInfoIcon = {
    Cooldown = {
        SetCooldownFromDurationObject = noop,
        SetReverse = noop,
        SetSwipeTexture = noop,
    },
    Icon = {
        SetDesaturated = function(_, value)
            mirrorNoCooldownInfoDesaturated = value
        end,
        SetVertexColor = noop,
    },
    _spellEntry = {
        id = 86422,
        spellID = 86422,
        kind = "cooldown",
        type = "spell",
        viewerType = "essential",
    },
}

applied = ns.CDMIcons.ApplyResolvedCooldown(mirrorNoCooldownInfoIcon)

assert(applied == true, "mirrored cooldown without live cdInfo should still be applied")
assert(mirrorNoCooldownInfoIcon._hasCooldownActive == true,
    "mirrored cooldown without live cdInfo should remain cooldown-active")
assert(mirrorNoCooldownInfoIcon._hasRealCooldownActive == true,
    "mirrored cooldown without live cdInfo should remain real-cooldown-active")
assert(mirrorNoCooldownInfoDesaturated == true,
    "mirrored cooldown without live cdInfo should desaturate when the mirror reports real-CD active")

mirrorDesaturated = nil
mirrorGapMode = "cooldown"

local mirroredCooldownGapIcon = {
    Cooldown = {
        SetCooldownFromDurationObject = noop,
        SetReverse = noop,
        SetSwipeTexture = noop,
    },
    Icon = {
        SetDesaturated = function(_, value)
            mirrorDesaturated = value
        end,
        SetVertexColor = noop,
    },
    _spellEntry = {
        id = 86424,
        spellID = 86424,
        kind = "cooldown",
        type = "spell",
        viewerType = "essential",
    },
}

-- When the mirror still reports cooldown but cdInfo.isOnGCD=true, the
-- override at cdm_icon_renderer.lua:1532+ releases the cooldown-active flag and
-- desat WITHOUT flipping the resolver's mode. Flipping mode to gcd-only
-- while the cooldown frame is still bound to the real CD's durObj caused
-- a visible "swipe vanishes" blip until the mirror's own state caught up
-- and emitted a gcd-only durObj. Let the mirror own the mode/durObj
-- transition; we only gate the side effects.
applied = ns.CDMIcons.ApplyResolvedCooldown(mirroredCooldownGapIcon)
-- 86424's QuerySpellCooldown source stub returns isActive=true + isOnGCD=true. Per
-- feedback_blizz_cd_state_signals that means the visible swipe is a GCD
-- (real CD is functionally over or shorter than remaining GCD). The mirror
-- still has the real CD durObj bound, so we keep mode=cooldown (preserving
-- the swipe binding) while flipping _hasCooldownActive=false and releasing
-- desat. Once the mirror itself emits gcd-only, the second-pass assertions
-- below cover the natural transition.
assert(applied == true,
    "mirror still has a durObj so the resolver still applies it; the binding stays as cooldown until the mirror itself flips")
assert(mirroredCooldownGapIcon._resolvedCooldownMode == "cooldown",
    "override does NOT change mode — flipping to gcd-only with the real-CD durObj re-keys dedupe and re-styles, causing the swipe to vanish briefly")
assert(mirroredCooldownGapIcon._hasCooldownActive == false,
    "cdInfo.isOnGCD=true releases _hasCooldownActive so procOnUsable glows can fire and IsSpellCastable returns true")
assert(mirroredCooldownGapIcon._hasRealCooldownActive == false,
    "cdInfo.isOnGCD=true also releases _hasRealCooldownActive")
assert(mirrorDesaturated == false,
    "cdInfo.isOnGCD=true releases desat — the visible swipe is a GCD, real CD is over (or shorter than GCD); icon must not look unavailable")

mirrorGapMode = "gcd-only"
applied = ns.CDMIcons.ApplyResolvedCooldown(mirroredCooldownGapIcon)

assert(applied == true, "resolver gcd-only flip should still apply")
assert(mirroredCooldownGapIcon._resolvedCooldownMode == "gcd-only",
    "once the mirror itself emits gcd-only, the resolver's mode flips naturally — and the icon picks up the mirror's gcd-only durObj for a clean swipe binding")
assert(mirrorDesaturated == false,
    "second pass with native mirror gcd-only must also keep desat cleared — every gcd-only pass writes desat=false unconditionally")
assert(mirroredCooldownGapIcon._mirrorCooldownPreserveUntil == nil,
    "regression guard: the _mirrorCooldownPreserveUntil mechanism was removed and must not be reintroduced")

local chargedOverrideDesaturated
local chargedOverrideIcon = {
    Cooldown = {
        SetCooldownFromDurationObject = noop,
        SetReverse = noop,
        SetSwipeTexture = noop,
        Clear = noop,
    },
    Icon = {
        SetDesaturated = function(_, value)
            chargedOverrideDesaturated = value
        end,
        SetVertexColor = noop,
    },
    _blizzMirrorCooldownID = 8194,
    _blizzMirrorCategory = "essential",
    _spellEntry = {
        id = 8092,
        spellID = 8092,
        kind = "cooldown",
        type = "spell",
        viewerType = "essential",
    },
}

chargedOverridePhase = "charge"
applied = ns.CDMIcons.ApplyResolvedCooldown(chargedOverrideIcon)
assert(applied == true, "charged override recharge should apply first")
assert(chargedOverrideIcon._hasCooldownActive == true,
    "charged override recharge should start as cooldown-active")

chargedOverridePhase = "inactive"
chargedOverrideMirrorActive = true
applied = ns.CDMIcons.ApplyResolvedCooldown(chargedOverrideIcon)
assert(applied == false,
    "transient inactive base-spell pass may clear the active recharge binding while mirror state catches up")

chargedOverridePhase = "mirror-cooldown"
applied = ns.CDMIcons.ApplyResolvedCooldown(chargedOverrideIcon)
assert(applied == true,
    "cooldown-backed mirror payload after charged override should be applied")
assert(chargedOverrideIcon._hasCooldownActive == true,
    "cooldown-backed mirror payload after charged override should stay cooldown-active despite live GCD state")
assert(chargedOverrideIcon._hasRealCooldownActive == true,
    "cooldown-backed mirror payload after charged override should stay real-cooldown-active")
assert(chargedOverrideDesaturated == true,
    "cooldown-backed mirror payload after charged override should keep cooldown desaturation")

-- Genuine CD-end test: live cdInfo says isActive=false; the resolver
-- transitions cleanly to "inactive" and desat releases on the next event.
local cdEndDesaturated
mirrorGapMode = "cooldown"
local mirrorCdEndIcon = {
    Cooldown = {
        Clear = noop,
        SetCooldownFromDurationObject = noop,
        SetReverse = noop,
        SetSwipeTexture = noop,
    },
    Icon = {
        SetDesaturated = function(_, value)
            cdEndDesaturated = value
        end,
        SetVertexColor = noop,
    },
    _spellEntry = {
        id = 86426,
        spellID = 86426,
        kind = "cooldown",
        type = "spell",
        viewerType = "essential",
    },
}

applied = ns.CDMIcons.ApplyResolvedCooldown(mirrorCdEndIcon)
-- 86426's QuerySpellCooldown source stub returns isActive=false (genuine CD-end). With
-- cdInfo authority, the resolver flips to inactive on the very first pass
-- even though the mirror reports an active duration. No "initial setup"
-- desaturation is expected anymore.
assert(applied == false,
    "cdInfo isActive=false flips to inactive even when mirror reports active duration")
assert(cdEndDesaturated == false,
    "cdInfo isActive=false must not desaturate the icon")
assert(mirrorCdEndIcon._resolvedCooldownMode == "inactive",
    "resolver inactive output must be reflected on the icon")

mirrorGapMode = "inactive"
applied = ns.CDMIcons.ApplyResolvedCooldown(mirrorCdEndIcon)

-- Steady-state confirmation: mirror itself now reports inactive too.
assert(mirrorCdEndIcon._resolvedCooldownMode == "inactive",
    "resolver inactive output must be reflected on the icon — no preservation reverts it back to cooldown")
assert(cdEndDesaturated == false,
    "CD end must keep desaturation released")
assert(mirrorCdEndIcon._cdDesaturated == nil,
    "CD end must clear the _cdDesaturated flag")
assert(mirrorCdEndIcon._mirrorCooldownPreserveUntil == nil,
    "regression guard: preservation mechanism removed; field must never be written")

local staleMirrorNoDurationIcon = {
    Cooldown = {
        Clear = noop,
        SetCooldownFromDurationObject = noop,
        SetReverse = noop,
        SetSwipeTexture = noop,
    },
    Icon = {
        SetDesaturated = function(_, value)
            staleMirrorDesaturated = value
        end,
        SetVertexColor = noop,
    },
    _cdDesaturated = true,
    _spellEntry = {
        id = 86425,
        spellID = 86425,
        kind = "cooldown",
        type = "spell",
        viewerType = "essential",
    },
}

applied = ns.CDMIcons.ApplyResolvedCooldown(staleMirrorNoDurationIcon)

assert(applied == false, "stale mirrored cooldown without a duration should not apply")
assert(staleMirrorNoDurationIcon._hasCooldownActive == false,
    "stale mirrored cooldown should not keep cooldown-active true when live API is inactive")
assert(staleMirrorNoDurationIcon._hasRealCooldownActive == false,
    "stale mirrored cooldown should not keep real-cooldown-active true when live API is inactive")
assert(staleMirrorNoDurationIcon._resolvedCooldownMode == "inactive",
    "stale mirrored cooldown should be normalized to inactive")
assert(staleMirrorDesaturated == false,
    "stale mirrored cooldown should release previous cooldown desaturation once")

print("OK: cdm_icons_gcd_style_test")
