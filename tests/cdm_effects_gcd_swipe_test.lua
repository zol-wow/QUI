-- tests/cdm_effects_gcd_swipe_test.lua
-- Run: lua tests/cdm_effects_gcd_swipe_test.lua

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
    },
    CDMSpellData = {
        IsAuraEntry = function(entry)
            return entry and entry.kind == "aura"
        end,
    },
    CDMIcons = {
        GetIconPool = function() return {} end,
        IsAuraCurrentlyActive = function() return false end,
    },
}

assert(loadfile("modules/cdm/cdm_effects.lua"))("QUI", ns)

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
