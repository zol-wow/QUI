-- tests/unit/cdm_effects_gcd_swipe_test.lua
-- Run: lua tests/unit/cdm_effects_gcd_swipe_test.lua

local function noop() end

function InCombatLockdown() return false end
function CreateFrame()
    return {
        RegisterEvent = noop,
        UnregisterAllEvents = noop,
        SetScript = noop,
        SetAllPoints = noop,
        SetAlpha = noop,
    }
end

C_Timer = {
    NewTicker = function()
        return { Cancel = noop }
    end,
    NewTimer = function()
        return { Cancel = noop }
    end,
}

local ns = {
    Helpers = {
        CreateDBGetter = function()
            return function()
                return {}
            end
        end,
        GetModuleSettings = function(_, defaults)
            return defaults
        end,
    },
    CDMShared = {
        IsRuntimeEnabled = function() return true end,
        SettingEnabled = function(value, fallback)
            if value == nil then return fallback == true end
            return value == true
        end,
        GetBuiltinContainerKeysByEntryKind = function(entryKind)
            if entryKind == "cooldown" then
                return { "essential", "utility" }
            end
            return nil
        end,
        GetBuiltinContainerKeysByShape = function(shape)
            if shape == "icon" then
                return { "essential", "utility", "buff" }
            end
            return nil
        end,
        IsBuiltinAuraContainerKey = function(containerKey)
            return containerKey == "buff" or containerKey == "trackedBar"
        end,
    },
    CDMSpellData = {
        IsAuraEntry = function(entry)
            return entry and entry.kind == "aura"
        end,
    },
    CDMIconFactory = {
        GetIconPool = function() return {} end,
    },
    CDMResolvers = {
        ResolveAuraActiveState = function() return false end,
    },
    CDMIcons = {},
}

local loadChunk = dofile("tests/helpers/load_cdm_consolidated_chunk.lua")
loadChunk("QUI_CDM/cdm/cdm_frame_writes.lua", "cdm_effects.lua")("QUI", ns)

local function NewCooldownSpy()
    local calls = {}
    return {
        calls = calls,
        SetSwipeTexture = function(_, value) calls.texture = value end,
        SetDrawSwipe = function(_, value) calls.drawSwipe = value end,
        SetDrawEdge = function(_, value) calls.drawEdge = value end,
        SetSwipeColor = function(_, r, g, b, a)
            calls.color = { r, g, b, a }
        end,
    }
end

local settings = {
    showBuffSwipe = false,
    showBuffIconSwipe = false,
    showGCDSwipe = true,
    showCooldownSwipe = false,
    overlayColorMode = "custom",
    overlayColor = { 0.9, 0.8, 0.7, 0.6 },
    swipeColorMode = "custom",
    swipeColor = { 0.1, 0.2, 0.3, 0.4 },
}

local cooldownGCD = NewCooldownSpy()
ns._OwnedSwipe.ApplyToIcon({
    Cooldown = cooldownGCD,
    _showingGCDSwipe = true,
    _spellEntry = {
        kind = "cooldown",
        viewerType = "essential",
        spellID = 12345,
    },
}, settings)

assert(cooldownGCD.calls.drawSwipe == true, "cooldown-kind GCD should use showGCDSwipe")
assert(cooldownGCD.calls.drawEdge == false, "GCD swipe should not draw recharge edge")
assert(cooldownGCD.calls.color[1] == 0.1, "cooldown-kind GCD should use cooldown swipe color")
assert(cooldownGCD.calls.color[4] == 0.4, "cooldown-kind GCD should preserve cooldown swipe alpha")

local originalResolveAuraActiveState = ns.CDMResolvers.ResolveAuraActiveState
local authoritativeGCDSettings = {
    showBuffSwipe = true,
    showBuffIconSwipe = true,
    showGCDSwipe = true,
    showCooldownSwipe = true,
    showRechargeEdge = true,
    overlayColorMode = "custom",
    overlayColor = { 0.9, 0.8, 0.7, 0.6 },
    swipeColorMode = "custom",
    swipeColor = { 0.1, 0.2, 0.3, 0.4 },
}

ns.CDMResolvers.ResolveAuraActiveState = function(entry)
    return entry and entry.spellID == 67890
end

local resolvedGCDWithLiveAura = NewCooldownSpy()
ns._OwnedSwipe.ApplyToIcon({
    Cooldown = resolvedGCDWithLiveAura,
    _showingGCDSwipe = true,
    _resolvedCooldownMode = "gcd-only",
    _spellEntry = {
        kind = "cooldown",
        viewerType = "essential",
        spellID = 67890,
    },
}, authoritativeGCDSettings)

ns.CDMResolvers.ResolveAuraActiveState = originalResolveAuraActiveState

assert(resolvedGCDWithLiveAura.calls.drawSwipe == true, "resolved GCD should keep drawing the GCD swipe")
assert(resolvedGCDWithLiveAura.calls.drawEdge == false, "resolved GCD should not be reclassified as aura edge")
assert(resolvedGCDWithLiveAura.calls.color[1] == 0.1, "resolved GCD should use cooldown swipe color even if a live aura lookup matches")
assert(resolvedGCDWithLiveAura.calls.color[4] == 0.4, "resolved GCD should preserve cooldown swipe alpha even if a live aura lookup matches")

local inactiveCooldown = NewCooldownSpy()
ns._OwnedSwipe.ApplyToIcon({
    Cooldown = inactiveCooldown,
    _resolvedCooldownMode = "inactive",
    _hasCooldownActive = false,
    _spellEntry = {
        kind = "cooldown",
        viewerType = "essential",
        spellID = 22222,
    },
}, authoritativeGCDSettings)

assert(inactiveCooldown.calls.drawSwipe == false, "inactive cooldown-kind entries should not enable a swipe")
assert(inactiveCooldown.calls.drawEdge == false, "inactive cooldown-kind entries should not draw a recharge edge")
assert(inactiveCooldown.calls.color[4] == 0, "inactive cooldown-kind entries should force a transparent swipe color")

local cooldownModeGCDGap = NewCooldownSpy()
ns._OwnedSwipe.ApplyToIcon({
    Cooldown = cooldownModeGCDGap,
    _resolvedCooldownMode = "cooldown",
    _showingGCDSwipe = true,
    _hasCooldownActive = false,
    _hasRealCooldownActive = false,
    _spellEntry = {
        kind = "cooldown",
        viewerType = "essential",
        spellID = 33333,
    },
}, authoritativeGCDSettings)

assert(cooldownModeGCDGap.calls.drawSwipe == true, "cooldown-mode GCD gap should keep the GCD swipe visible")
assert(cooldownModeGCDGap.calls.drawEdge == false, "cooldown-mode GCD gap should not draw the recharge edge")
assert(cooldownModeGCDGap.calls.color[1] == 0.1, "cooldown-mode GCD gap should use cooldown swipe color")
assert(cooldownModeGCDGap.calls.color[4] == 0.4, "cooldown-mode GCD gap should preserve cooldown swipe alpha")

local cooldownModeInactiveTail = NewCooldownSpy()
ns._OwnedSwipe.ApplyToIcon({
    Cooldown = cooldownModeInactiveTail,
    _resolvedCooldownMode = "cooldown",
    _hasCooldownActive = false,
    _hasRealCooldownActive = false,
    _spellEntry = {
        kind = "cooldown",
        viewerType = "essential",
        spellID = 33334,
    },
}, authoritativeGCDSettings)

assert(cooldownModeInactiveTail.calls.drawSwipe == false, "cooldown mode without cooldown or GCD state should not draw a swipe")
assert(cooldownModeInactiveTail.calls.drawEdge == false, "cooldown mode without cooldown or GCD state should not draw an edge")
assert(cooldownModeInactiveTail.calls.color[4] == 0, "cooldown mode without cooldown or GCD state should force a transparent swipe")

local chargeRecharge = NewCooldownSpy()
ns._OwnedSwipe.ApplyToIcon({
    Cooldown = chargeRecharge,
    _resolvedCooldownMode = "charge",
    _hasCooldownActive = false,
    _hasRealCooldownActive = false,
    _spellEntry = {
        kind = "cooldown",
        viewerType = "essential",
        spellID = 44444,
    },
}, authoritativeGCDSettings)

assert(chargeRecharge.calls.drawSwipe == true, "charge recharge should keep the cooldown swipe visible")
assert(chargeRecharge.calls.drawEdge == true, "charge recharge should keep the recharge edge")

local inactiveAuraCooldown = NewCooldownSpy()
ns._OwnedSwipe.ApplyToIcon({
    Cooldown = inactiveAuraCooldown,
    _showingGCDSwipe = true,
    _spellEntry = {
        kind = "aura",
        viewerType = "essential",
        spellID = 12345,
    },
}, settings)

assert(inactiveAuraCooldown.calls.drawSwipe == false, "aura-kind entries should not use GCD swipe settings")
assert(inactiveAuraCooldown.calls.color[4] == 0, "disabled aura swipe should stay transparent")

print("OK: cdm_effects_gcd_swipe_test")
