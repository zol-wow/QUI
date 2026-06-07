-- tests/unit/cdm_icon_custom_bar_policy_test.lua
-- Run: lua tests/unit/cdm_icon_custom_bar_policy_test.lua

local secretCount = { token = "secret-count" }

function issecretvalue(value)
    return value == secretCount
end

Enum = {
    ItemClass = {
        Armor = 4,
        Weapon = 2,
    },
}

local ns = {}
local loadChunk = dofile("tests/helpers/load_cdm_consolidated_chunk.lua")
loadChunk("QUI_CDM/cdm/cdm_icon_renderer.lua", "cdm_icon_custom_bar_policy.lua")("QUI", ns)

local policyModule = assert(ns.CDMIconCustomBarPolicy, "CDMIconCustomBarPolicy should be exported")

local sources = {}
local trackerSettings = {}
local cooldownStates = {}
local knownSpells = {}
local activeSpells = {}
local debugEvents = {}
local glowEvents = {}
local reapplyCount = 0
local inCombat = false

local function visibilityMode(containerDB)
    return containerDB and containerDB.visibilityMode or "always"
end

local function makeCooldown()
    local writes = {}
    local cooldown = {
        SetDrawSwipe = function(_, value)
            writes[#writes + 1] = { op = "swipe", value = value }
        end,
        SetDrawEdge = function(_, value)
            writes[#writes + 1] = { op = "edge", value = value }
        end,
        SetSwipeTexture = function(_, value)
            writes[#writes + 1] = { op = "texture", value = value }
        end,
        SetSwipeColor = function(_, r, g, b, a)
            writes[#writes + 1] = { op = "color", r = r, g = g, b = b, a = a }
        end,
    }
    return cooldown, writes
end

local function makeIcon(entry)
    local cooldown, writes = makeCooldown()
    local icon = {
        _spellEntry = entry,
        Cooldown = cooldown,
        Icon = {
            AddMaskTexture = function(_, mask)
                glowEvents[#glowEvents + 1] = { op = "add-mask", mask = mask }
            end,
            RemoveMaskTexture = function(_, mask)
                glowEvents[#glowEvents + 1] = { op = "remove-mask", mask = mask }
            end,
        },
        Border = {
            shown = true,
            IsShown = function(self) return self.shown end,
            Hide = function(self) self.shown = false end,
            Show = function(self) self.shown = true end,
        },
        GetSize = function()
            return 32, 32
        end,
        IsShown = function()
            return true
        end,
        CreateMaskTexture = function()
            return {
                SetTexture = function() end,
                SetAllPoints = function() end,
            }
        end,
    }
    return icon, writes
end

local policy = policyModule.Create({
    getSources = function() return sources end,
    getSpellData = function()
        return {
            IsSpellKnown = function(_, spellID)
                return knownSpells[spellID] ~= false
            end,
        }
    end,
    getGlowLib = function()
        return {
            PixelGlow_Start = function(icon, color, lines, frequency, texture, thickness, x, y, border, key)
                glowEvents[#glowEvents + 1] = {
                    op = "pixel-start",
                    key = key,
                    lines = lines,
                    thickness = thickness,
                }
            end,
            PixelGlow_Stop = function(icon, key)
                glowEvents[#glowEvents + 1] = { op = "pixel-stop", key = key }
            end,
            AutoCastGlow_Start = function(icon, color, lines, frequency, scale, x, y, key)
                glowEvents[#glowEvents + 1] = { op = "autocast-start", key = key, scale = scale }
            end,
            AutoCastGlow_Stop = function(icon, key)
                glowEvents[#glowEvents + 1] = { op = "autocast-stop", key = key }
            end,
            ProcGlow_Start = function(icon, options)
                glowEvents[#glowEvents + 1] = { op = "proc-start", key = options.key, duration = options.duration }
            end,
            ProcGlow_Stop = function(icon, key)
                glowEvents[#glowEvents + 1] = { op = "proc-stop", key = key }
            end,
        }
    end,
    getTime = function() return 123 end,
    getTrackerSettings = function(viewerType)
        return trackerSettings[viewerType]
    end,
    isCustomBarContainer = function(containerDB)
        return containerDB and containerDB.containerType == "customBar"
    end,
    getCustomBarVisibilityMode = visibilityMode,
    resolveMacro = function(entry)
        return entry.resolvedID, entry.resolvedType
    end,
    resolveSpellActiveState = function(spellID)
        local state = activeSpells[spellID]
        if state then
            return state[1], state[2], state[3], state[4]
        end
        return false
    end,
    resolveCooldownActivityState = function(icon, entry)
        return cooldownStates[entry and entry.id] or {
            isOnCooldown = false,
            rechargeActive = false,
            hasCharges = false,
            hasChargesRemaining = false,
        }
    end,
    reapplySwipeStyle = function()
        reapplyCount = reapplyCount + 1
    end,
    isPlayerInCombat = function()
        return inCombat
    end,
    debugIconEvent = function(icon, kind, ...)
        debugEvents[#debugEvents + 1] = { kind = kind, args = { ... } }
    end,
    after = function(delay, callback)
        callback()
    end,
})

trackerSettings.custom = {
    containerType = "customBar",
    visibilityMode = "onCooldown",
    hideNonUsable = true,
    showRechargeSwipe = true,
    activeGlowEnabled = true,
}

sources.QuerySpellUsable = function()
    return false
end
cooldownStates[101] = {
    isOnCooldown = true,
    rechargeActive = false,
    hasCharges = false,
    hasChargesRemaining = false,
}
local icon = makeIcon({ type = "spell", id = 101, spellID = 101, viewerType = "custom" })
local visible = policy:ComputeVisibility(icon, icon._spellEntry, trackerSettings.custom, 123)
assert(visible.layoutVisible == true,
    "known spells on cooldown should pass hideNonUsable custom-bar layout visibility")
assert(visible.renderVisible == true,
    "known spells on cooldown should render when combat visibility allows")
assert(visible.isUsable == true,
    "known spells on cooldown should be considered usable for custom-bar visibility")

knownSpells[102] = false
cooldownStates[102] = { isOnCooldown = false }
local unusable = policy:ResolveUsability({ type = "spell", id = 102, spellID = 102 }, trackerSettings.custom, cooldownStates[102])
assert(unusable == false, "unknown spells should fail custom-bar usability")

trackerSettings.custom.visibilityMode = "active"
trackerSettings.custom.showOnlyInCombat = true
inCombat = false
icon._customBarActive = true
visible = policy:ComputeVisibility(icon, icon._spellEntry, trackerSettings.custom, 123)
assert(visible.layoutVisible == true, "active mode should keep active icons in layout")
assert(visible.renderVisible == false, "showOnlyInCombat should gate rendering without changing layout")

trackerSettings.custom.visibilityMode = "offCooldown"
trackerSettings.custom.showOnlyInCombat = false
sources.QuerySpellUsable = function()
    return true
end
cooldownStates[101] = {
    isOnCooldown = false,
    rechargeActive = false,
    hasChargesRemaining = false,
}
visible = policy:ComputeVisibility(icon, icon._spellEntry, trackerSettings.custom, 123)
assert(visible.layoutVisible == false,
    "off-cooldown mode should hide active icons with no charge ready")
cooldownStates[101].hasChargesRemaining = true
visible = policy:ComputeVisibility(icon, icon._spellEntry, trackerSettings.custom, 123)
assert(visible.layoutVisible == true,
    "off-cooldown mode should show active icons when a charge remains")

sources.QueryItemInfoInstant = function(itemID)
    if itemID == 200 then
        return itemID, nil, nil, nil, nil, Enum.ItemClass.Armor
    end
    return itemID
end
sources.QueryIsEquippedItem = function()
    return false
end
assert(policy:ResolveUsability({ type = "item", id = 200 }, trackerSettings.custom, nil) == false,
    "equippable items should fail usability when not equipped")
sources.QueryItemInfoInstant = function(itemID) return itemID end
sources.QueryItemCount = function(itemID)
    if itemID == 201 then return secretCount end
    return 0
end
assert(policy:ResolveUsability({ type = "item", id = 201 }, trackerSettings.custom, nil) == true,
    "secret item counts should be treated as usable instead of compared in Lua")

sources.QueryItemSpell = function(itemID)
    if itemID == 301 then return "Item Spell", 777 end
    if itemID == 302 then return "Item Spell", 778 end
    return nil
end
activeSpells[777] = { true, 10, 20, "item-spell" }
local active, startTime, duration, activeType = policy:ResolveActiveState({
    type = "macro",
    resolvedID = 301,
    resolvedType = "item",
    viewerType = "custom",
}, icon, 123)
assert(active == true and startTime == 10 and duration == 20 and activeType == "item-spell",
    "macro item active-state resolution should preserve spell active-state tuple")

sources.QueryScannedItemAuraInfo = function(itemID, itemSpellID)
    if itemID == 302 and itemSpellID == 778 then
        return {
            active = true,
            expiration = 150,
            duration = 30,
            useSpellID = 778,
            buffSpellID = 779,
        }
    end
    return nil
end
activeSpells[778] = nil
active, startTime, duration, activeType = policy:ResolveActiveState({
    type = "item",
    id = 302,
    viewerType = "custom",
}, icon, 123)
assert(active == true and startTime == 120 and duration == 30 and activeType == "buff",
    "item active-state resolution should prefer scanned related aura timing")
sources.QueryScannedItemAuraInfo = nil

local cooldownIcon, swipeWrites = makeIcon({ type = "spell", id = 101, spellID = 101, viewerType = "custom" })
policy:ApplySwipeStyle(cooldownIcon, trackerSettings.custom, {
    hasCharges = true,
    rechargeActive = true,
})
assert(swipeWrites[1].op == "swipe" and swipeWrites[1].value == true,
    "recharge swipe style should draw the recharge swipe")
assert(swipeWrites[2].op == "edge" and swipeWrites[2].value == false,
    "recharge swipe style should hide the cooldown edge")
assert(swipeWrites[3].op == "texture",
    "recharge swipe style should restore the owned swipe texture")
assert(swipeWrites[4].op == "color" and swipeWrites[4].a == 0.6,
    "recharge swipe style should tint the recharge swipe")

local activeIcon = makeIcon({ type = "spell", id = 101, spellID = 101, viewerType = "custom" })
activeSpells[101] = { true, 1, 2, "spell-active" }
policy:ApplyActiveState(activeIcon, activeIcon._spellEntry, trackerSettings.custom)
assert(activeIcon._customBarActive == true,
    "active-state application should stamp custom-bar active status")
assert(reapplyCount > 0, "active-state transitions should reapply swipe styling")

policy:StartActiveGlow(activeIcon, trackerSettings.custom)
assert(glowEvents[#glowEvents].op == "pixel-start",
    "active glow should start the configured glow")
assert(activeIcon._customBarActiveGlowShown == true,
    "active glow should stamp glow state on the icon")
policy:ApplyActiveGlow(activeIcon, trackerSettings.custom, {
    renderVisible = true,
    isActive = true,
    visibilityMode = "onCooldown",
})
assert(glowEvents[#glowEvents].op == "pixel-stop",
    "onCooldown visibility mode should suppress active glow")
assert(activeIcon._customBarActiveGlowShown == nil,
    "stopping active glow should clear glow state")

print("OK: cdm_icon_custom_bar_policy_test")
