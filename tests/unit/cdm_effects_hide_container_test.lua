-- tests/unit/cdm_effects_hide_container_test.lua
-- Run: lua tests/unit/cdm_effects_hide_container_test.lua
--
-- profile.cooldownEffects hide flags must suppress swipe+edge per container.
-- The "Hide Cooldown Effects" checkbox writes cooldownEffects.hideEssential /
-- hideUtility / hide_<customKey>; the swipe applicator must consult those flags
-- and force SetDrawSwipe(false)+SetDrawEdge(false) for a hidden container while
-- passing configured swipe state through for a non-hidden one.

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
    NewTicker = function() return { Cancel = noop } end,
    NewTimer = function() return { Cancel = noop } end,
}

-- essential hidden, utility NOT hidden (matches the seed shape after Task 9).
local effectsSettings = { hideEssential = true, hideUtility = false }

local ns = {
    Helpers = {
        CreateDBGetter = function()
            return function() return {} end
        end,
        GetModuleSettings = function(name, defaults)
            if name == "cooldownEffects" then
                return effectsSettings
            end
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
        GetNcdmDB = function() return {} end,
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

-- Swipe settings that would normally SHOW the cooldown swipe + recharge edge.
local swipeSettings = {
    showCooldownSwipe = true,
    showRechargeEdge = true,
    swipeColorMode = "custom",
    swipeColor = { 0.1, 0.2, 0.3, 0.4 },
}

---------------------------------------------------------------------------
-- Per-icon apply: hidden essential container forces swipe+edge OFF.
---------------------------------------------------------------------------
local essential = NewCooldownSpy()
ns._OwnedSwipe.ApplyToIcon({
    Cooldown = essential,
    _resolvedCooldownMode = "cooldown",
    _hasCooldownActive = true,
    _spellEntry = { kind = "cooldown", viewerType = "essential", spellID = 111 },
}, swipeSettings)

assert(essential.calls.drawSwipe == false, "hidden essential container must force swipe off")
assert(essential.calls.drawEdge == false, "hidden essential container must force edge off")
assert(essential.calls.color[4] == 0, "hidden essential swipe color must be transparent")

---------------------------------------------------------------------------
-- Per-icon apply: non-hidden utility container passes swipe+edge through.
---------------------------------------------------------------------------
local utility = NewCooldownSpy()
ns._OwnedSwipe.ApplyToIcon({
    Cooldown = utility,
    _resolvedCooldownMode = "cooldown",
    _hasCooldownActive = true,
    _spellEntry = { kind = "cooldown", viewerType = "utility", spellID = 222 },
}, swipeSettings)

assert(utility.calls.drawSwipe == true, "non-hidden utility container must keep the swipe")
assert(utility.calls.drawEdge == true, "non-hidden utility container must keep the recharge edge")
assert(utility.calls.color[1] == 0.1, "non-hidden utility keeps the configured swipe color")

---------------------------------------------------------------------------
-- Pure mapping seam: ContainerHideKey MUST stay in lockstep with
-- ResolveEffectsContext in settings/containers_page.lua (911-921).
---------------------------------------------------------------------------
assert(ns._OwnedSwipe.IsContainerEffectsHidden, "IsContainerEffectsHidden must be exported")
assert(ns._OwnedSwipe._TestContainerHideKey, "ContainerHideKey test seam must be exported")
assert(ns._OwnedSwipe._TestContainerHideKey("essential") == "hideEssential",
    "essential -> hideEssential")
assert(ns._OwnedSwipe._TestContainerHideKey("utility") == "hideUtility",
    "utility -> hideUtility")
assert(ns._OwnedSwipe._TestContainerHideKey("custom_x") == "hide_custom_x",
    "custom_x -> hide_custom_x")
assert(ns._OwnedSwipe._TestContainerHideKey(nil) == nil, "nil viewerType -> nil key")

-- IsContainerEffectsHidden honours the flags.
assert(ns._OwnedSwipe.IsContainerEffectsHidden("essential") == true,
    "essential is hidden per effectsSettings")
assert(ns._OwnedSwipe.IsContainerEffectsHidden("utility") == false,
    "utility is not hidden per effectsSettings")
assert(ns._OwnedSwipe.IsContainerEffectsHidden(nil) == false,
    "nil viewerType is never hidden")

print("OK: cdm_effects_hide_container_test")
