-- tests/unit/cdm_tooltip_secret_aura_fallback_test.lua
-- Regression: in combat the live CDM icon's auraInstanceID (or the aura it
-- names) can be secret; ShowEntryTooltip must fall back to the spell tooltip
-- instead of erroring inside GameTooltip.SetUnitAuraByAuraInstanceID
-- ("Auras cannot be accessed when secret while tainted by 'QUI_CDM'").
-- Run: lua tests/unit/cdm_tooltip_secret_aura_fallback_test.lua

local SecretSentinel = dofile("tests/helpers/secret_sentinel.lua")
local restoreSecret = SecretSentinel.InstallSecretStub()

function InCombatLockdown() return true end

QUICore = {
    db = {
        profile = {
            tooltip = {
                anchorToCursor = false,
                hideInCombat = false,
            },
        },
    },
}

local ns = {
    Addon = QUICore,
    Helpers = {
        GetGeneralFont = function() return "Fonts\\FRIZQT__.TTF" end,
        GetGeneralFontOutline = function() return "" end,
    },
    CDMSources = {
        QueryLastCategoryCooldownSource = function(categoryID)
            if categoryID == 1711 then return 6262, 999999 end
        end,
        QueryConsumableCategoryItem = function(categoryID)
            if categoryID == 1711 then return 5512 end
        end,
    },
    CDMResolvers = {
        GetEntryTexture = function() return 134400 end,
        GetSpellTexture = function() return 134400 end,
    },
    CDMSpellData = {
        ResolveDisplaySpellID = function(_, entry)
            return entry and entry.spellID
        end,
    },
}

local auraTooltipCalls = 0
GameTooltip = {
    IsForbidden = function() return false end,
    SetOwner = function(self, owner, anchor)
        self.owner = owner
        self.anchor = anchor
    end,
    SetSpellByID = function(self, spellID) self.spellID = spellID end,
    SetItemByID = function(self, itemID) self.itemID = itemID end,
    SetUnitAuraByAuraInstanceID = function(self, unit, auraInstanceID, filter)
        auraTooltipCalls = auraTooltipCalls + 1
        if issecretvalue(auraInstanceID) or issecretvalue(unit) or self._auraIsSecret then
            error("GetUnitAuraByAuraInstanceID(): Auras cannot be accessed when secret while tainted by 'QUI_CDM'")
        end
        self.auraInstanceID = auraInstanceID
        return true
    end,
    Show = function(self) self.shown = true end,
    Hide = function(self) self.hidden = true end,
    AddLine = function() end,
}

local loadChunk = dofile("tests/helpers/load_cdm_consolidated_chunk.lua")
loadChunk("QUI_CDM/cdm/cdm_icon_factory.lua", "cdm_icon_factory.lua")("QUI", ns)
local Factory = assert(ns.CDMIconFactory, "factory module must export CDMIconFactory")

local function resetTooltip()
    GameTooltip.owner, GameTooltip.anchor = nil, nil
    GameTooltip.spellID, GameTooltip.itemID, GameTooltip.auraInstanceID = nil, nil, nil
    GameTooltip.shown, GameTooltip._auraIsSecret = false, false
end

-- Case A: the carrier frame holds a SECRET auraInstanceID (combat). The
-- secret must never reach GameTooltip.SetUnitAuraByAuraInstanceID; the
-- tooltip falls back to the entry's spell.
resetTooltip()
local secretOwner = {
    auraDataUnit = "player",
    auraInstanceID = SecretSentinel.MakeSecretSentinel(),
}
local ok, err = pcall(Factory.ShowEntryTooltip, secretOwner, { spellID = 777 }, "cdm")
assert(ok, "secret auraInstanceID must not escape ShowEntryTooltip: " .. tostring(err))
assert(auraTooltipCalls == 0, "secret auraInstanceID must be rejected before the aura tooltip call")
assert(GameTooltip.spellID == 777 and GameTooltip.shown == true,
    "secret aura carrier falls back to the spell tooltip")

-- Case B: the ID reads fine but the aura itself is secret — in game the
-- tooltip accessor hard-errors. ShowEntryTooltip must absorb it and fall
-- back to the spell tooltip.
resetTooltip()
GameTooltip._auraIsSecret = true
local combatOwner = { auraDataUnit = "player", auraInstanceID = 42 }
ok, err = pcall(Factory.ShowEntryTooltip, combatOwner, { spellID = 777 }, "cdm")
assert(ok, "secret-aura tooltip error must not escape ShowEntryTooltip: " .. tostring(err))
assert(GameTooltip.spellID == 777 and GameTooltip.shown == true,
    "secret-aura tooltip error falls back to the spell tooltip")
assert(GameTooltip.owner == combatOwner and GameTooltip.anchor == "ANCHOR_BOTTOM",
    "fallback re-anchors the tooltip after the failed aura call")

-- Case C: readable aura still uses the aura-instance tooltip path.
resetTooltip()
local liveOwner = { auraDataUnit = "player", auraInstanceID = 42 }
assert(Factory.ShowEntryTooltip(liveOwner, { spellID = 777 }, "cdm") == true,
    "readable aura tooltip still shows")
assert(GameTooltip.auraInstanceID == 42, "readable aura uses the aura-instance tooltip path")
assert(GameTooltip.spellID == nil, "no spell fallback when the aura tooltip succeeded")

-- Case D: consumable categories use the actual item for their tooltip.
resetTooltip()
local consumableOwner = { _runtimeSpellID = 6262 }
assert(Factory.ShowEntryTooltip(consumableOwner, { type = "consumable", id = 1711 }, "cdm") == true,
    "consumable tooltip shows")
assert(GameTooltip.itemID == 5512 and GameTooltip.spellID == nil,
    "consumable tooltip uses the Healthstone item")

SecretSentinel.RestoreSecretStub(restoreSecret)
print("OK: cdm_tooltip_secret_aura_fallback_test")
