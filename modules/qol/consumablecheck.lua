local ADDON_NAME, ns = ...
local Helpers = ns.Helpers
local SkinBase = ns.SkinBase
local UIKit = ns.UIKit

local LCG = LibStub and LibStub("LibCustomGlow-1.0", true)

local DEFAULT_BUTTON_SIZE = 40
local BUTTON_SPACING = 0
local STATUS_ICON_SIZE = 18

local INVSLOT_MAINHAND = 16
local INVSLOT_OFFHAND = 17
local FOOD_ICON_FALLBACK = 136000
local RUNE_ICON_FALLBACK = "Interface\\Icons\\inv_10_enchanting_crystal_color2"
local PICKER_ROW_HEIGHT = 24
local PICKER_MIN_WIDTH = 200

local FOOD_BUFFS = {
    [1232324] = true, [285719] = true,
}

local FLASK_BUFFS = {
    [1235057] = true, [1235108] = true, [1235110] = true, [1235111] = true,
}

local RUNE_BUFFS = {
    [1234969] = true,
    [1242347] = true,
    [1264426] = true,
}

local FLASK_ITEMS = {
    245926, 245927, 241320, 241321,
    245932, 245933, 241322, 241323,
    245930, 245931, 241324, 241325,
    245928, 245929, 241326, 241327,
}
local FLASK_ITEM_SET = {}
for _, itemID in ipairs(FLASK_ITEMS) do
    FLASK_ITEM_SET[itemID] = true
end

local RUNE_ITEMS = {
    259085,
    243191,
}

local OIL_ITEMS = {
    243733, 243734,
    243735, 243736,
    243737, 243738,
    237370, 237371,
    237367, 237369,
}

local AMMO_ITEMS = {
    257746, 257745,
    257748, 257747,
    257750, 257749,
    257752, 257751,
}

local WEAPON_ENCHANTS = {}

local PREFERENCE_KEYS = {
    food = "consumablePreferredFood",
    flask = "consumablePreferredFlask",
    rune = "consumablePreferredRune",
    oilMH = "consumablePreferredOilMH",
    oilOH = "consumablePreferredOilOH",
}

local MACRO_SLOT_FOR_BUTTON = {
    flask       = "selectedFlask",
    rune        = "selectedAugment",
    healthstone = "selectedHealthstone",
    oilMH       = "selectedWeapon",
}

local BUTTON_TYPES = { "food", "flask", "oilMH", "rune", "healthstone", "oilOH" }

local repaintLog = nil
local layoutRuns = 0

local function GetMacroSelection(buttonType)
    local dbKey = MACRO_SLOT_FOR_BUTTON[buttonType]
    if not dbKey then return nil end
    local cm = ns.ConsumableMacros
    if not (cm and cm.GetSelectedItem) then return nil end
    return cm.GetSelectedItem(dbKey)
end

local function GetMacroPreferredItemID(buttonType)
    local sel = GetMacroSelection(buttonType)
    return sel and sel.itemID or nil
end

local BuildOwnedItemsFromList

local _, playerClass = UnitClass("player")
-- @secret-policy: collapse-only — unknown class = no enhancement config
if Helpers.IsSecretValue and Helpers.IsSecretValue(playerClass) then playerClass = nil end

local CLASS_ENHANCEMENT_CONFIG = {
    ROGUE = {
        MH = {
            source = "spell",
            label = ns.L["Lethal Poison"],
            checkType = "playerAura",
            anyBuffIDs = { [2823] = true, [315584] = true, [8679] = true, [381664] = true },
            spells = {
                { spellID = 2823,   name = "Deadly Poison" },
                { spellID = 315584, name = "Instant Poison" },
                { spellID = 8679,   name = "Wound Poison" },
                { spellID = 381664, name = "Amplifying Poison" },
            },
        },
        OH = {
            source = "spell",
            label = ns.L["Non-Lethal Poison"],
            checkType = "playerAura",
            anyBuffIDs = { [3408] = true, [5761] = true, [381637] = true },
            spells = {
                { spellID = 3408,   name = "Crippling Poison" },
                { spellID = 5761,   name = "Numbing Poison" },
                { spellID = 381637, name = "Atrophic Poison" },
            },
        },
    },
    SHAMAN = {
        MH = {
            source = "spell",
            label = ns.L["Weapon Imbue"],
            checkType = "weaponEnchant",
            anyEnchantIDs = { [5400] = true, [5401] = true, [6498] = true },
            spells = {
                { spellID = 33757,  name = "Windfury Weapon" },
                { spellID = 382021, name = "Earthliving Weapon" },
            },
        },
        OHShield = {
            source = "spell",
            label = ns.L["Shield Enchant"],
            checkType = "weaponEnchant",
            anyEnchantIDs = { [7587] = true, [7528] = true },
            spells = {
                { spellID = 462757, name = "Thunderstrike Ward" },
                { spellID = 457481, name = "Tidecaller's Guard" },
            },
        },
        OHWeapon = {
            source = "spell",
            label = ns.L["Offhand Imbue"],
            checkType = "weaponEnchant",
            anyEnchantIDs = { [5400] = true, [5401] = true, [6498] = true },
            spells = {
                { spellID = 318038, name = "Flametongue Weapon" },
            },
        },
    },
    PALADIN = {
        MH = {
            source = "spell",
            label = ns.L["Weapon Rite"],
            checkType = "weaponEnchant",
            anyEnchantIDs = { [7143] = true, [7144] = true },
            spells = {
                { spellID = 433568, name = "Rite of Sanctification" },
                { spellID = 433583, name = "Rite of Adjuration" },
            },
        },
    },
    HUNTER = {
        MH = {
            source = "item",
            label = ns.L["Ammo"],
            checkType = "weaponEnchant",
            items = AMMO_ITEMS,
        },
    },
}

local HasShieldEquipped, IsDualWielding

local function GetEnhancementConfig(slot)
    local classConfig = CLASS_ENHANCEMENT_CONFIG[playerClass]
    if not classConfig then return nil end
    local slotConfig
    if playerClass == "SHAMAN" and slot == "OH" then
        if HasShieldEquipped() then
            slotConfig = classConfig.OHShield
        elseif IsDualWielding() then
            slotConfig = classConfig.OHWeapon
        end
    else
        slotConfig = classConfig[slot]
    end
    if not slotConfig then return nil end
    if slotConfig.spells then
        for _, spell in ipairs(slotConfig.spells) do
            if IsPlayerSpell(spell.spellID) then
                return slotConfig
            end
        end
        return nil
    end
    return slotConfig
end

function HasShieldEquipped()
    local ohItemID = GetInventoryItemID("player", INVSLOT_OFFHAND)
    if not ohItemID then return false end
    local _, _, _, _, _, classID, subClassID = C_Item.GetItemInfoInstant(ohItemID)
    return classID == 4 and subClassID == 6
end

local function GetKnownSpellsForConfig(config)
    if not config or not config.spells then return {} end
    local result = {}
    for _, spell in ipairs(config.spells) do
        if IsPlayerSpell(spell.spellID) then
            local icon = C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(spell.spellID)
            table.insert(result, {
                itemID = spell.spellID,
                name = spell.name,
                count = nil,
                icon = icon,
                isSpell = true,
            })
        end
    end
    return result
end

local function ResolveDefaultEnhancementIcon(slot)
    local config = GetEnhancementConfig(slot)
    if config then
        if config.source == "spell" then
            local spells = GetKnownSpellsForConfig(config)
            if spells[1] and spells[1].icon then return spells[1].icon end
            if config.spells and config.spells[1] then
                local icon = C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(config.spells[1].spellID)
                if icon then return icon end
            end
        elseif config.items then
            local items = BuildOwnedItemsFromList(config.items)
            if items[1] and items[1].icon then return items[1].icon end
            local icon = select(5, C_Item.GetItemInfoInstant(config.items[1]))
            if icon then return icon end
        end
    end
    local oils = BuildOwnedItemsFromList(OIL_ITEMS)
    if oils[1] and oils[1].icon then return oils[1].icon end
    return 609892
end

local function GetEnhancementLabel(slot)
    local config = GetEnhancementConfig(slot)
    if config and config.items then
        local buttonType = slot == "MH" and "oilMH" or "oilOH"
        local sel = GetMacroSelection(buttonType)
        if sel and sel.label then return sel.label end
    end
    if config and config.label then return config.label end
    return ns.L["Weapon Oil"]
end

ns.ConsumableCheckLabels = {
    GetMHLabel = function() return GetEnhancementLabel("MH") end,
    GetOHLabel = function() return GetEnhancementLabel("OH") end,
}

local UpdateConsumables
local ToggleConsumablePicker
local HideConsumablePicker
local StartButtonGlow
local StopButtonGlow
local RequestHideConsumablesFrame
local ITEM_CLASS_CONSUMABLE_ID = (Enum and Enum.ItemClass and Enum.ItemClass.Consumable) or LE_ITEM_CLASS_CONSUMABLE
local FOOD_AND_DRINK_SUBCLASS_ID = Enum and Enum.ItemConsumableSubclass and Enum.ItemConsumableSubclass.FoodAndDrink
local FLASK_SUBCLASS_ID = Enum and Enum.ItemConsumableSubclass and Enum.ItemConsumableSubclass.Flask
local PHIAL_SUBCLASS_ID = Enum and Enum.ItemConsumableSubclass and Enum.ItemConsumableSubclass.Phial

local GetSettings = Helpers.CreateDBGetter("general")

local function GetButtonSize()
    local settings = GetSettings()
    return (settings and settings.consumableIconSize) or DEFAULT_BUTTON_SIZE
end

local function GetConsumableScale()
    local settings = GetSettings()
    local scale = (settings and settings.consumableScale) or 1
    scale = tonumber(scale) or 1
    if scale < 0.5 then
        return 0.5
    elseif scale > 3 then
        return 3
    end
    return scale
end

local function GetLastWeaponEnchant(slot)
    local settings = GetSettings()
    if not settings then return nil end
    if slot == INVSLOT_MAINHAND then
        return settings.lastWeaponEnchantMH or settings.lastWeaponEnchant
    elseif slot == INVSLOT_OFFHAND then
        return settings.lastWeaponEnchantOH
    end
    return nil
end

local function SaveLastWeaponEnchant(slot, enchantID, icon, itemID)
    local settings = GetSettings()
    if not settings then return end
    local data = { enchantID = enchantID, icon = icon, item = itemID }
    if slot == INVSLOT_MAINHAND then
        settings.lastWeaponEnchantMH = data
    elseif slot == INVSLOT_OFFHAND then
        settings.lastWeaponEnchantOH = data
    end
end

local function HasWarlockInGroup()
    local _, playerClass = UnitClass("player")
    -- @secret-policy: collapse-only — secret class treated as non-warlock
    if Helpers.IsSecretValue and Helpers.IsSecretValue(playerClass) then playerClass = nil end
    if playerClass == "WARLOCK" then return true end
    local numMembers = GetNumGroupMembers()
    if numMembers == 0 then return false end
    local prefix = IsInRaid() and "raid" or "party"
    for i = 1, numMembers do
        local unit = prefix .. i
        if UnitExists(unit) then
            local _, class = UnitClass(unit)
            -- @secret-policy: collapse-only — secret class treated as non-warlock
            if Helpers.IsSecretValue and Helpers.IsSecretValue(class) then class = nil end
            if class == "WARLOCK" then return true end
        end
    end
    return false
end

function IsDualWielding()
    local offhand = GetInventoryItemID("player", INVSLOT_OFFHAND)
    if not offhand then return false end
    local _, _, _, _, _, itemClassID = C_Item.GetItemInfoInstant(offhand)
    return itemClassID == 2
end

local function FormatTimeRemaining(seconds)
    if seconds < 60 then
        return string.format("%ds", math.ceil(seconds))
    end
    local mins = math.ceil(seconds / 60)
    if mins < 60 then
        return string.format("%dm", mins)
    end
    local hours = math.floor(mins / 60)
    local rem = mins % 60
    if rem > 0 then
        return string.format("%dh %dm", hours, rem)
    end
    return string.format("%dh", hours)
end

local function GetPreferenceKey(buttonType)
    return PREFERENCE_KEYS[buttonType]
end

local function GetPreferredItemID(buttonType)
    local settings = GetSettings()
    if not settings then return nil end
    local key = GetPreferenceKey(buttonType)
    return key and settings[key] or nil
end

local function SetPreferredItemID(buttonType, itemID)
    local settings = GetSettings()
    if not settings then return end
    local key = GetPreferenceKey(buttonType)
    if key then
        settings[key] = itemID
    end
end

local function ShouldPersistPreferenceOnUse(buttonType)
    if GetPreferredItemID(buttonType) ~= nil then
        return true
    end
    if GetMacroPreferredItemID(buttonType) ~= nil then
        return false
    end
    return true
end

local function GetMacroVariantOrder(itemID)
    if Helpers.IsSecretValue and Helpers.IsSecretValue(itemID) then return nil end -- @secret-policy: reject-secret-ids
    itemID = tonumber(itemID)
    if not itemID then return nil end

    local consumables = ns.ConsumableMacros
    local getVariantOrder = consumables and consumables.GetVariantOrderForItem
    return getVariantOrder and getVariantOrder(itemID) or nil
end

local function GetMacroVariantRank(itemID)
    if Helpers.IsSecretValue and Helpers.IsSecretValue(itemID) then return nil end -- @secret-policy: reject-secret-ids
    itemID = tonumber(itemID)
    if not itemID then return nil end

    local variants = GetMacroVariantOrder(itemID)
    if type(variants) ~= "table" then return nil end
    for rank, variantID in ipairs(variants) do
        if type(variantID) == "number" and variantID == itemID then
            return rank
        end
    end
    return nil
end

local function CompareOwnedItemsByPriority(a, b)
    local aRank = a and GetMacroVariantRank(a.itemID)
    local bRank = b and GetMacroVariantRank(b.itemID)
    if aRank and bRank and aRank ~= bRank then
        return aRank < bRank
    elseif aRank and not bRank then
        return true
    elseif bRank and not aRank then
        return false
    end

    local aListOrder = a and a._listOrder
    local bListOrder = b and b._listOrder
    if aListOrder and bListOrder and aListOrder ~= bListOrder then
        return aListOrder < bListOrder
    elseif aListOrder and not bListOrder then
        return true
    elseif bListOrder and not aListOrder then
        return false
    end

    local aName = (a and a.name) or ""
    local bName = (b and b.name) or ""
    if aName ~= bName then
        return aName < bName
    end

    local aItemID = 0
    local bItemID = 0
    local aRawItemID = a and a.itemID
    local bRawItemID = b and b.itemID
    if not (Helpers.IsSecretValue and Helpers.IsSecretValue(aRawItemID)) then
        aItemID = tonumber(aRawItemID) or 0
    end
    if not (Helpers.IsSecretValue and Helpers.IsSecretValue(bRawItemID)) then
        bItemID = tonumber(bRawItemID) or 0
    end
    return aItemID < bItemID
end

local function BuildOwnedItemLookup(ownedItems)
    local lookup = {}
    for _, itemData in ipairs(ownedItems or {}) do
        local rawItemID = itemData and itemData.itemID
        local itemID
        if not (Helpers.IsSecretValue and Helpers.IsSecretValue(rawItemID)) then
            itemID = tonumber(rawItemID)
        end
        if itemID then
            lookup[itemID] = itemData
        end
    end
    return lookup
end

local function ResolveBestOwnedVariantItemData(itemID, ownedItems)
    if Helpers.IsSecretValue and Helpers.IsSecretValue(itemID) then return nil end -- @secret-policy: reject-secret-ids
    itemID = tonumber(itemID)
    if not itemID then return nil end

    local ownedByID = BuildOwnedItemLookup(ownedItems)
    local variants = GetMacroVariantOrder(itemID)
    if type(variants) == "table" then
        for _, variantID in ipairs(variants) do
            if type(variantID) == "number" then
                local itemData = ownedByID[variantID]
                if itemData then
                    return itemData
                end
            end
        end
    end

    return ownedByID[itemID]
end

local function MergeItemLists(a, b)
    local merged, seen = {}, {}
    for _, list in ipairs({ a, b }) do
        for _, itemID in ipairs(list) do
            if not seen[itemID] then
                seen[itemID] = true
                merged[#merged + 1] = itemID
            end
        end
    end
    return merged
end

local function BuildItemOrderLookup(itemIDs)
    local order = {}
    for index, itemID in ipairs(itemIDs or {}) do
        if type(itemID) == "number" and order[itemID] == nil then
            order[itemID] = index
        end
    end
    return order
end

local function CollectItemTotalsFromList(itemIDs, totals)
    for _, itemID in ipairs(itemIDs) do
        local count = C_Item.GetItemCount(itemID, false, false)
        if count and count > 0 then
            totals[itemID] = (totals[itemID] or 0) + count
        end
    end
end

local function CollectItemTotalsFromBags(totals, predicate)
    local maxBag = NUM_BAG_SLOTS or 4
    for bag = 0, maxBag do
        local numSlots = C_Container.GetContainerNumSlots(bag) or 0
        for slot = 1, numSlots do
            local itemID = C_Container.GetContainerItemID(bag, slot)
            if itemID and predicate(itemID) then
                local info = C_Container.GetContainerItemInfo(bag, slot)
                local stackCount = (info and info.stackCount) or 1
                totals[itemID] = (totals[itemID] or 0) + stackCount
            end
        end
    end
end

local function BuildOwnedItemsFromTotals(totals, fallbackIcon, itemOrder)
    local items = {}
    for itemID, count in pairs(totals) do
        local itemName = C_Item.GetItemInfo(itemID)
        local icon = select(5, C_Item.GetItemInfoInstant(itemID))
        table.insert(items, {
            itemID = itemID,
            name = itemName or ("item:" .. itemID),
            count = count,
            icon = icon or fallbackIcon,
            _listOrder = itemOrder and itemOrder[itemID] or nil,
        })
    end
    table.sort(items, CompareOwnedItemsByPriority)
    return items
end

BuildOwnedItemsFromList = function(itemIDs, fallbackIcon)
    local totals = {}
    CollectItemTotalsFromList(itemIDs, totals)
    return BuildOwnedItemsFromTotals(totals, fallbackIcon, BuildItemOrderLookup(itemIDs))
end

local function IsFoodItem(itemID)
    local _, foodSpellID = C_Item.GetItemSpell(itemID)
    if foodSpellID and FOOD_BUFFS[foodSpellID] then
        return true
    end

    local _, _, _, _, _, classID, subClassID = C_Item.GetItemInfoInstant(itemID)
    if not classID or not subClassID then
        return false
    end
    if classID ~= ITEM_CLASS_CONSUMABLE_ID then
        return false
    end
    if FOOD_AND_DRINK_SUBCLASS_ID then
        return subClassID == FOOD_AND_DRINK_SUBCLASS_ID
    end
    return false
end

local function IsFlaskItem(itemID)
    local _, flaskSpellID = C_Item.GetItemSpell(itemID)
    if flaskSpellID and FLASK_BUFFS[flaskSpellID] then
        return true
    end

    local _, _, _, _, _, classID, subClassID = C_Item.GetItemInfoInstant(itemID)
    if not classID or not subClassID then
        return false
    end
    if classID ~= ITEM_CLASS_CONSUMABLE_ID then
        return false
    end
    if FLASK_SUBCLASS_ID and subClassID == FLASK_SUBCLASS_ID then
        return true
    end
    if PHIAL_SUBCLASS_ID and subClassID == PHIAL_SUBCLASS_ID then
        return true
    end
    return false
end

local function BuildOwnedFoodItems()
    local totals = {}
    CollectItemTotalsFromBags(totals, IsFoodItem)
    return BuildOwnedItemsFromTotals(totals, FOOD_ICON_FALLBACK)
end

local function BuildOwnedFlaskItems()
    local totals = {}
    CollectItemTotalsFromBags(totals, function(itemID)
        return FLASK_ITEM_SET[itemID] or IsFlaskItem(itemID)
    end)
    return BuildOwnedItemsFromTotals(totals)
end

local function GetOwnedItemsForButton(buttonType)
    if buttonType == "food" then
        return BuildOwnedFoodItems()
    elseif buttonType == "flask" then
        return BuildOwnedFlaskItems()
    elseif buttonType == "rune" then
        return BuildOwnedItemsFromList(RUNE_ITEMS)
    elseif buttonType == "oilMH" or buttonType == "oilOH" then
        local slot = buttonType == "oilMH" and "MH" or "OH"
        local config = GetEnhancementConfig(slot)
        if config then
            if config.source == "spell" then
                return GetKnownSpellsForConfig(config)
            elseif config.items then
                return BuildOwnedItemsFromList(MergeItemLists(config.items, OIL_ITEMS))
            end
        end
        return BuildOwnedItemsFromList(OIL_ITEMS)
    end
    return {}
end

local function ResolveSelectedOwnedItem(buttonType, ownedItems)
    local explicitItemID = GetPreferredItemID(buttonType)
    local preferredItemID = explicitItemID or GetMacroPreferredItemID(buttonType)
    if preferredItemID then
        local preferredVariant = ResolveBestOwnedVariantItemData(preferredItemID, ownedItems)
        if preferredVariant then
            if buttonType == "rune" and ownedItems[1] and ownedItems[1]._listOrder then
                return ownedItems[1]
            end
            return preferredVariant
        end
        if explicitItemID then
            SetPreferredItemID(buttonType, nil)
        end
    end
    return ownedItems[1]
end

local function ButtonStatesEqual(a, b)
    if a == nil or b == nil then
        return a == b
    end
    return a.shown == b.shown
        and a.active == b.active
        and a.icon == b.icon
        and a.timeText == b.timeText
        and a.clickable == b.clickable
        and a.itemID == b.itemID
        and a.count == b.count
end

local function DiffButtonStates(prev, next, buttonTypes)
    local changed = {}
    local visibilityChanged = false
    for _, buttonType in ipairs(buttonTypes) do
        local before = prev and prev[buttonType] or nil
        local after = next[buttonType]
        if not ButtonStatesEqual(before, after) then
            changed[#changed + 1] = buttonType
        end
        local wasShown = (before and before.shown) or false
        local isShown = (after and after.shown) or false
        if wasShown ~= isShown then
            visibilityChanged = true
        end
    end
    return changed, visibilityChanged
end

local snapshotCache = { entries = nil, hasWarlock = nil, lastStates = nil, layoutDirty = nil }

local function InvalidateInventorySnapshot()
    snapshotCache.entries = nil
    snapshotCache.hasWarlock = nil
    snapshotCache.lastStates = nil
end

local function GetSnapshotEntry(buttonType)
    local entries = snapshotCache.entries
    if not entries then
        entries = {}
        snapshotCache.entries = entries
    end
    local entry = entries[buttonType]
    if entry == nil then
        local owned = GetOwnedItemsForButton(buttonType)
        entry = { owned = owned, selected = ResolveSelectedOwnedItem(buttonType, owned) }
        entries[buttonType] = entry
    end
    return entry
end

local function GetCachedWarlockPresence()
    if snapshotCache.hasWarlock == nil then
        snapshotCache.hasWarlock = HasWarlockInGroup()
    end
    return snapshotCache.hasWarlock
end

local function ConfigureButtonClickAction(button, buttonType, data, showGlow)
    if not button or not button.click or not data then return end
    button.selectedItemID = data.itemID
    button.click.selectedItemID = data.itemID

    button.click:SetAttribute("type1", "macro")
    button.click:SetAttribute("type2", nil)
    button.click:SetAttribute("macrotext2", nil)
    if data.isSpell then
        button.click:SetAttribute("macrotext1", "/cast " .. data.name)
    else
        local useToken = data.name or ("item:" .. data.itemID)
        if buttonType == "oilMH" then
            button.click:SetAttribute("macrotext1", "/use " .. useToken .. "\n/use " .. INVSLOT_MAINHAND)
        elseif buttonType == "oilOH" then
            button.click:SetAttribute("macrotext1", "/use " .. useToken .. "\n/use " .. INVSLOT_OFFHAND)
        else
            button.click:SetAttribute("macrotext1", "/use " .. useToken)
        end
    end
    button.click:Show()
    button.countText:SetText(data.count and data.count > 0 and tostring(data.count) or "")
    if data.icon then
        button.icon:SetTexture(data.icon)
    end
    if showGlow then
        StartButtonGlow(button)
    end
end

local function ApplyPreferredIcon(button, buttonType)
    if not button then return end
    local preferredID = GetPreferredItemID(buttonType) or GetMacroPreferredItemID(buttonType)
    if not preferredID then return end
    local slot = (buttonType == "oilMH" and "MH") or (buttonType == "oilOH" and "OH") or nil
    local config = slot and GetEnhancementConfig(slot)
    if config and config.source == "spell" then
        local icon = C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(preferredID)
        if icon then button.icon:SetTexture(icon) end
    else
        local icon = select(5, C_Item.GetItemInfoInstant(preferredID))
        if icon then button.icon:SetTexture(icon) end
    end
end

local C_Secrets = C_Secrets
local function ForEachPlayerHelpfulAura(callback)
    if C_Secrets and C_Secrets.ShouldAurasBeSecret and C_Secrets.ShouldAurasBeSecret() then
        return
    end
    local i = 0
    while true do
        i = i + 1
        local ok, auraData = pcall(C_UnitAuras.GetAuraDataByIndex, "player", i, "HELPFUL")
        if not ok then return end
        if Helpers.IsSecretValue(auraData) then
            auraData = nil -- @secret-policy: reject-secret-value — skip, keep walking
        elseif auraData == nil then
            return
        end
        if auraData ~= nil and callback(auraData) then
            return
        end
    end
end

local function ScanPlayerBuffs()
    local result = {
        hasFood = false, hasFlask = false, hasRune = false,
        hasWeaponMH = false, hasWeaponOH = false,
        foodData = nil, flaskData = nil, runeData = nil,
        weaponMHData = nil, weaponOHData = nil,
    }
    local mhConfig = GetEnhancementConfig("MH")
    local ohConfig = GetEnhancementConfig("OH")
    local checkMHAura = mhConfig and mhConfig.checkType == "playerAura"
    local checkOHAura = ohConfig and ohConfig.checkType == "playerAura"

    ForEachPlayerHelpfulAura(function(auraData)
        local spellId = Helpers.SafeValue(auraData.spellId)
        local icon = Helpers.SafeValue(auraData.icon)
        if not result.hasFood then
            if FOOD_BUFFS[spellId] or icon == 136000 then result.hasFood = true; result.foodData = auraData end
        end
        if not result.hasFlask then
            if FLASK_BUFFS[spellId] then result.hasFlask = true; result.flaskData = auraData end
        end
        if not result.hasRune then
            if RUNE_BUFFS[spellId] then result.hasRune = true; result.runeData = auraData end
        end
        if checkMHAura and not result.hasWeaponMH then
            if mhConfig.anyBuffIDs[spellId] then result.hasWeaponMH = true; result.weaponMHData = auraData end
        end
        if checkOHAura and not result.hasWeaponOH then
            if ohConfig.anyBuffIDs[spellId] then result.hasWeaponOH = true; result.weaponOHData = auraData end
        end
    end)
    return result
end

local ConsumablesFrame = CreateFrame("Frame", "QUI_ConsumablesFrame", UIParent)
ConsumablesFrame:SetSize(DEFAULT_BUTTON_SIZE * 6 + BUTTON_SPACING * 5, DEFAULT_BUTTON_SIZE + 18)
ConsumablesFrame:Hide()
ConsumablesFrame.buttons = {}

local consumableCombatDeferFrame
local hideConsumablesAfterCombat = false

local function HideConsumablesFrameNow()
    if not ConsumablesFrame then return end
    ConsumablesFrame:SetAlpha(1)
    ConsumablesFrame:Hide()
    for _, button in pairs(ConsumablesFrame.buttons) do
        if type(button) == "table" and button.click then
            button.click:Hide()
        end
    end
    snapshotCache.lastStates = nil
end

local function EnsureConsumableCombatDeferFrame()
    if consumableCombatDeferFrame then return end
    consumableCombatDeferFrame = CreateFrame("Frame")
    consumableCombatDeferFrame:SetScript("OnEvent", function(f, event)
        if event ~= "PLAYER_REGEN_ENABLED" then return end
        f:UnregisterEvent("PLAYER_REGEN_ENABLED")
        if hideConsumablesAfterCombat then
            hideConsumablesAfterCombat = false
            local settings = GetSettings()
            if settings and settings.consumablePersistent and settings.consumableCheckEnabled ~= false then
                ConsumablesFrame:SetAlpha(1)
                UpdateConsumables()
                return
            end
            HideConsumablesFrameNow()
        end
    end)
end

RequestHideConsumablesFrame = function()
    HideConsumablePicker()
    local settings = GetSettings()
    if settings and settings.consumablePersistent and settings.consumableCheckEnabled ~= false then
        return
    end
    if InCombatLockdown() then
        hideConsumablesAfterCombat = true
        if ConsumablesFrame:IsShown() then
            ConsumablesFrame:SetAlpha(0)
        end
        EnsureConsumableCombatDeferFrame()
        consumableCombatDeferFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
        return
    end

    hideConsumablesAfterCombat = false
    HideConsumablesFrameNow()
end

local CLOSE_BUTTON_HEIGHT = 18

local closeButton = CreateFrame("Button", nil, ConsumablesFrame)
closeButton:SetSize(DEFAULT_BUTTON_SIZE * 4, CLOSE_BUTTON_HEIGHT)
closeButton:SetPoint("BOTTOMLEFT", ConsumablesFrame, "BOTTOMLEFT", 0, 0)
closeButton:SetPoint("BOTTOMRIGHT", ConsumablesFrame, "BOTTOMRIGHT", 0, 0)

closeButton.bg = closeButton:CreateTexture(nil, "BACKGROUND")
closeButton.bg:SetAllPoints()
closeButton.bg:SetColorTexture(0.15, 0.15, 0.15, 0.9)

closeButton.text = closeButton:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
closeButton.text:SetPoint("CENTER")
closeButton.text:SetText(ns.L["Close"])
closeButton.text:SetTextColor(0.8, 0.8, 0.8, 1)

closeButton:SetScript("OnEnter", function(self)
    self.bg:SetColorTexture(0.25, 0.25, 0.25, 0.9)
    self.text:SetTextColor(1, 1, 1, 1)
end)
closeButton:SetScript("OnLeave", function(self)
    self.bg:SetColorTexture(0.15, 0.15, 0.15, 0.9)
    self.text:SetTextColor(0.8, 0.8, 0.8, 1)
end)
closeButton:SetScript("OnClick", function()
    RequestHideConsumablesFrame()
end)
ConsumablesFrame.closeButton = closeButton

local function CreateConsumableButton(parent, index, buttonType, iconID, isClickable, buttonSize)
    local button = CreateFrame("Frame", nil, parent)
    button:SetSize(buttonSize, buttonSize)
    button.buttonType = buttonType
    button.defaultIcon = iconID

    button.icon = button:CreateTexture(nil, "BACKGROUND")
    button.icon:SetAllPoints()
    button.icon:SetTexture(iconID)

    button.status = button:CreateTexture(nil, "OVERLAY")
    button.status:SetSize(STATUS_ICON_SIZE, STATUS_ICON_SIZE)
    button.status:SetPoint("CENTER")
    button.status:SetTexture("Interface\\RaidFrame\\ReadyCheck-NotReady")

    button.timeText = button:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    button.timeText:SetPoint("BOTTOM", button, "TOP", 0, 2)
    if ns.Helpers and ns.Helpers.ApplyFontWithFallback then
        ns.Helpers.ApplyFontWithFallback(button.timeText, STANDARD_TEXT_FONT, 9, "OUTLINE")
    else
        button.timeText:SetFont(STANDARD_TEXT_FONT, 9, "OUTLINE")
    end
    button.timeText:SetTextColor(1, 1, 1, 1)

    button.countText = button:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    button.countText:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -2, 2)
    if ns.Helpers and ns.Helpers.ApplyFontWithFallback then
        ns.Helpers.ApplyFontWithFallback(button.countText, STANDARD_TEXT_FONT, 10, "OUTLINE")
    else
        button.countText:SetFont(STANDARD_TEXT_FONT, 10, "OUTLINE")
    end
    button.countText:SetTextColor(1, 1, 1, 1)

    if isClickable then
        button.click = CreateFrame("Button", nil, button, "SecureActionButtonTemplate")
        button.click:SetAllPoints()
        button.click:RegisterForClicks("AnyUp", "AnyDown")
        button.click:Hide()
        button.click:SetAttribute("type1", "macro")
        button.click:SetScript("OnEnter", function() button:SetAlpha(0.7) end)
        button.click:SetScript("OnLeave", function() button:SetAlpha(1) end)
        button.click:SetScript("OnMouseUp", function(self, mouseButton)
            if mouseButton == "RightButton" and not InCombatLockdown() and ToggleConsumablePicker then
                ToggleConsumablePicker(button)
            end
        end)
        button.click:SetScript("PostClick", function(self, mouseButton, down)
            if down then return end
            if mouseButton == "RightButton" then
                return
            end
            if mouseButton == "LeftButton" and self.selectedItemID
                and ShouldPersistPreferenceOnUse(button.buttonType) then
                SetPreferredItemID(button.buttonType, self.selectedItemID)
                InvalidateInventorySnapshot()
            end
        end)
    end

    return button
end

StartButtonGlow = function(button)
    if LCG and button then
        LCG.PixelGlow_Start(button, {1, 0.8, 0, 1}, 8, 0.25, nil, 2, 0, 0, false, "_QUIConsumable")
    end
end

StopButtonGlow = function(button)
    if LCG and button then
        LCG.PixelGlow_Stop(button, "_QUIConsumable")
    end
end

local pickerFrame = nil
local pickerOverlay = nil
local pickerCombatHideFrame = nil

local function CreatePickerRow(parent)
    local row = CreateFrame("Button", nil, parent, "SecureActionButtonTemplate")
    row:SetHeight(PICKER_ROW_HEIGHT)
    row:RegisterForClicks("AnyUp", "AnyDown")

    row.bg = row:CreateTexture(nil, "BACKGROUND")
    row.bg:SetAllPoints()
    row.bg:SetColorTexture(0.12, 0.12, 0.12, 0.95)

    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(18, 18)
    row.icon:SetPoint("LEFT", 5, 0)

    row.nameText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.nameText:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
    row.nameText:SetJustifyH("LEFT")

    row.countText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.countText:SetPoint("RIGHT", -6, 0)
    row.countText:SetTextColor(0.85, 0.85, 0.85, 1)

    row:SetScript("OnEnter", function(self)
        self.bg:SetColorTexture(0.2, 0.2, 0.2, 0.95)
    end)
    row:SetScript("OnLeave", function(self)
        self.bg:SetColorTexture(0.12, 0.12, 0.12, 0.95)
    end)
    row:SetScript("PostClick", function(self, mouseButton, down)
        if down then return end
        if mouseButton ~= "LeftButton" and mouseButton ~= "RightButton" then return end
        if self.itemID then
            SetPreferredItemID(self.buttonType, self.itemID)
            InvalidateInventorySnapshot()
        end
        HideConsumablePicker()
        if UpdateConsumables and ConsumablesFrame:IsShown() then
            C_Timer.After(0.1, UpdateConsumables)
        end
    end)

    return row
end

local function EnsurePickerFrame()
    if pickerFrame then return end

    pickerOverlay = CreateFrame("Button", nil, UIParent)
    pickerOverlay:SetAllPoints(UIParent)
    pickerOverlay:EnableMouse(true)
    pickerOverlay:RegisterForClicks("AnyUp")
    pickerOverlay:SetFrameStrata("DIALOG")
    pickerOverlay:SetFrameLevel(600)
    pickerOverlay:SetScript("OnClick", function()
        if HideConsumablePicker then HideConsumablePicker() end
    end)
    pickerOverlay:Hide()

    pickerFrame = CreateFrame("Frame", "QUI_ConsumablesPickerFrame", UIParent, "BackdropTemplate")
    pickerFrame:SetFrameStrata("FULLSCREEN_DIALOG")
    pickerFrame:SetFrameLevel(700)
    pickerFrame:SetClampedToScreen(true)
    pickerFrame:Hide()
    pickerFrame.rows = {}
    pickerFrame.activeRows = {}
    do
        local bgr, bgg, bgb = 0.05, 0.05, 0.05
        if Helpers and Helpers.GetSkinBgColor then
            bgr, bgg, bgb = Helpers.GetSkinBgColor()
        end
        local sr, sg, sb = 0.35, 0.35, 0.35
        if Helpers and Helpers.GetSkinBorderColor then
            sr, sg, sb = Helpers.GetSkinBorderColor()
        end
        if SkinBase and SkinBase.CreateBackdrop then
            SkinBase.CreateBackdrop(pickerFrame, sr, sg, sb, 1, bgr, bgg, bgb, 0.95)
        elseif SkinBase and SkinBase.ApplyPixelBackdrop then
            SkinBase.ApplyPixelBackdrop(pickerFrame, 1, true, false, { sr, sg, sb, 1 }, { bgr, bgg, bgb, 0.95 })
        end
    end
    if UIKit and UIKit.CreateObjectPool then
        pickerFrame.rowPool = UIKit.CreateObjectPool(
            function()
                return CreatePickerRow(pickerFrame)
            end,
            function(row)
                row.buttonType = nil
                row.itemID = nil
                if not InCombatLockdown() then
                    row:ClearAllPoints()
                    row:SetAttribute("type1", nil)
                    row:SetAttribute("macrotext1", nil)
                    row:SetAttribute("type2", nil)
                    row:SetAttribute("macrotext2", nil)
                end
                row.nameText:SetTextColor(1, 1, 1, 1)
                row:Hide()
            end
        )
    end
    pickerFrame:SetScript("OnHide", function()
        if pickerOverlay then pickerOverlay:Hide() end
    end)
end

HideConsumablePicker = function()
    if pickerFrame then
        if pickerFrame.rowPool and pickerFrame.activeRows then
            for i = #pickerFrame.activeRows, 1, -1 do
                local row = pickerFrame.activeRows[i]
                pickerFrame.rowPool:Release(row)
                pickerFrame.activeRows[i] = nil
            end
        end
        pickerFrame.ownerButton = nil
        if InCombatLockdown() then
            if not pickerCombatHideFrame then
                pickerCombatHideFrame = CreateFrame("Frame")
                pickerCombatHideFrame:SetScript("OnEvent", function(self)
                    self:UnregisterAllEvents()
                    if pickerFrame then pickerFrame:Hide() end
                end)
            end
            pickerCombatHideFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
        else
            pickerFrame:Hide()
        end
    end
end

local function ConfigurePickerRow(row, buttonType, data)
    row.buttonType = buttonType
    row.itemID = data.itemID
    row.icon:SetTexture(data.icon or FOOD_ICON_FALLBACK)
    row.nameText:SetText(data.name or ("item:" .. data.itemID))
    row.countText:SetText(data.count and data.count > 0 and tostring(data.count) or "")

    local macroText
    if data.isSpell then
        macroText = "/cast " .. data.name
    else
        local useToken = data.name or ("item:" .. data.itemID)
        if buttonType == "oilMH" then
            macroText = "/use " .. useToken .. "\n/use " .. INVSLOT_MAINHAND
        elseif buttonType == "oilOH" then
            macroText = "/use " .. useToken .. "\n/use " .. INVSLOT_OFFHAND
        else
            macroText = "/use " .. useToken
        end
    end
    row:SetAttribute("type1", "macro")
    row:SetAttribute("macrotext1", macroText)
    row:SetAttribute("type2", "macro")
    row:SetAttribute("macrotext2", macroText)
end

local function BuildPickerRows(buttonType, ownedItems)
    EnsurePickerFrame()
    local rowCount = #ownedItems
    local maxNameWidth = 0
    local preferredItemID = GetPreferredItemID(buttonType)
    local activeRows = pickerFrame.activeRows or {}

    for i = #activeRows, 1, -1 do
        local row = activeRows[i]
        if pickerFrame.rowPool then
            pickerFrame.rowPool:Release(row)
        else
            if row then
                row:Hide()
            end
        end
        activeRows[i] = nil
    end
    pickerFrame.activeRows = activeRows

    for i = 1, rowCount do
        local row
        if pickerFrame.rowPool then
            row = pickerFrame.rowPool:Acquire()
        else
            row = pickerFrame.rows[i]
            if not row then
                row = CreatePickerRow(pickerFrame)
                pickerFrame.rows[i] = row
            end
        end
        activeRows[i] = row

        local itemData = ownedItems[i]
        ConfigurePickerRow(row, buttonType, itemData)
        if preferredItemID and itemData.itemID == preferredItemID then
            row.nameText:SetTextColor(0.5, 1, 0.5, 1)
        else
            row.nameText:SetTextColor(1, 1, 1, 1)
        end
        local width = row.nameText:GetStringWidth() or 0
        if width > maxNameWidth then
            maxNameWidth = width
        end
        row:ClearAllPoints()
        row:SetPoint("BOTTOMLEFT", pickerFrame, "BOTTOMLEFT", 2, 2 + (i - 1) * PICKER_ROW_HEIGHT)
        row:SetPoint("BOTTOMRIGHT", pickerFrame, "BOTTOMRIGHT", -2, 2 + (i - 1) * PICKER_ROW_HEIGHT)
        row:Show()
    end

    if not pickerFrame.rowPool then
        for i = rowCount + 1, #pickerFrame.rows do
            pickerFrame.rows[i]:Hide()
        end
    end

    local frameWidth = math.max(PICKER_MIN_WIDTH, math.ceil(maxNameWidth) + 70)
    local frameHeight = rowCount * PICKER_ROW_HEIGHT + 4
    pickerFrame:SetSize(frameWidth, frameHeight)
end

local function ShowConsumablePicker(button, ownedItems)
    if not button or not button.buttonType or not ownedItems or #ownedItems == 0 then return end
    BuildPickerRows(button.buttonType, ownedItems)
    pickerFrame:SetScale(GetConsumableScale())
    pickerFrame.ownerButton = button
    pickerFrame:ClearAllPoints()
    pickerFrame:SetPoint("BOTTOMLEFT", button, "TOPLEFT", 0, 4)
    pickerOverlay:Show()
    pickerFrame:Show()
end

ToggleConsumablePicker = function(button)
    if not button or not button.buttonType then return end
    if not ConsumablesFrame:IsShown() then return end
    if InCombatLockdown() then return end

    local ownedItems = GetOwnedItemsForButton(button.buttonType)
    if #ownedItems == 0 then
        HideConsumablePicker()
        return
    end

    if pickerFrame and pickerFrame:IsShown() and pickerFrame.ownerButton == button then
        HideConsumablePicker()
        return
    end
    ShowConsumablePicker(button, ownedItems)
end

local function InitializeButtons()
    local buttons = ConsumablesFrame.buttons
    local buttonSize = GetButtonSize()

    for k, button in pairs(buttons) do
        if type(button) == "table" and button.Hide then
            button:Hide()
        end
        buttons[k] = nil
    end

    local runeIcon = (C_Item.GetItemIconByID and C_Item.GetItemIconByID(259085)) or RUNE_ICON_FALLBACK
    local buttonDefs = {
        { "food", FOOD_ICON_FALLBACK, true },
        { "flask", 3566840, true },
        { "oilMH", ResolveDefaultEnhancementIcon("MH"), true },
        { "rune", runeIcon, true },
        { "healthstone", 538745, false },
        { "oilOH", ResolveDefaultEnhancementIcon("OH"), true },
    }

    for i, def in ipairs(buttonDefs) do
        local button = CreateConsumableButton(ConsumablesFrame, i, def[1], def[2], def[3], buttonSize)
        button:SetPoint("LEFT", ConsumablesFrame, "LEFT", (i - 1) * (buttonSize + BUTTON_SPACING), 0)
        buttons[def[1]] = button
    end

    snapshotCache.lastStates = nil
    ConsumablesFrame.buttonSize = buttonSize
end

local function AuraStateFields(auraData, now)
    if not auraData then return nil, "" end
    local icon = Helpers.SafeValue(auraData.icon)
    local expires = Helpers.SafeToNumber(auraData.expirationTime)
    local timeText = ""
    if expires > 0 then
        timeText = FormatTimeRemaining(expires - now)
    end
    return icon, timeText
end

local function ComputeEnhancementState(slot, hasEnchant, enchantExpiration, enchantID, buffs, now)
    local config = GetEnhancementConfig(slot)

    if config and config.checkType == "playerAura" then
        local auraData = (slot == "MH") and buffs.weaponMHData or buffs.weaponOHData
        if auraData then
            local icon, timeText = AuraStateFields(auraData, now)
            return true, icon, timeText
        end
        return false, nil, ""
    end

    if config and config.checkType == "weaponEnchant" then
        if hasEnchant then
            local icon
            if enchantID and config.anyEnchantIDs and config.anyEnchantIDs[enchantID] then
                if config.spells then
                    for _, spell in ipairs(config.spells) do
                        local spellIcon = C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(spell.spellID)
                        if spellIcon then
                            icon = spellIcon
                            break
                        end
                    end
                end
            elseif enchantID and WEAPON_ENCHANTS[enchantID] then
                icon = WEAPON_ENCHANTS[enchantID].icon
            end
            local timeText = ""
            if enchantExpiration and enchantExpiration > 0 then
                timeText = FormatTimeRemaining(enchantExpiration / 1000)
            end
            return true, icon, timeText
        end
        return false, nil, ""
    end

    local invSlot = slot == "MH" and INVSLOT_MAINHAND or INVSLOT_OFFHAND
    if hasEnchant then
        local icon
        if enchantID and WEAPON_ENCHANTS[enchantID] then
            local enchantData = WEAPON_ENCHANTS[enchantID]
            icon = enchantData.icon
            SaveLastWeaponEnchant(invSlot, enchantID, enchantData.icon, enchantData.item)
        end
        local timeText = ""
        if enchantExpiration and enchantExpiration > 0 then
            timeText = FormatTimeRemaining(enchantExpiration / 1000)
        end
        return true, icon, timeText
    end
    local lastEnchant = GetLastWeaponEnchant(invSlot)
    if lastEnchant and lastEnchant.icon then
        return false, lastEnchant.icon, ""
    end
    return false, nil, ""
end

local function ShouldShowOHButton(settings)
    if settings.consumableOilOH == false then return false end
    local config = GetEnhancementConfig("OH")
    if config then
        if config.requiresShield then
            return HasShieldEquipped()
        end
        return true
    end
    local classConfig = CLASS_ENHANCEMENT_CONFIG[playerClass]
    if classConfig and classConfig.MH and not classConfig.OH then
        return false
    end
    return IsDualWielding()
end

local function ComputeDesiredStates(settings, canUseItems)
    local now = GetTime()
    local buffs = ScanPlayerBuffs()
    local hasMainHandEnchant, mainHandExpiration, _, mainHandEnchantID,
        hasOffHandEnchant, offHandExpiration, _, offHandEnchantID = GetWeaponEnchantInfo()

    local function newState(shown)
        return { shown = shown, active = false, icon = nil, timeText = "",
                 clickable = false, itemID = nil, count = nil }
    end

    local states = {}

    states.food = newState(settings.consumableFood ~= false)
    if states.food.shown and buffs.hasFood then
        states.food.active = true
        local _, timeText = AuraStateFields(buffs.foodData, now)
        states.food.timeText = timeText
    end

    states.flask = newState(settings.consumableFlask ~= false)
    if states.flask.shown and buffs.hasFlask then
        states.flask.active = true
        states.flask.icon, states.flask.timeText = AuraStateFields(buffs.flaskData, now)
    end

    states.rune = newState(settings.consumableRune ~= false)
    if states.rune.shown and buffs.hasRune then
        states.rune.active = true
        local _, timeText = AuraStateFields(buffs.runeData, now)
        states.rune.timeText = timeText
    end

    states.oilMH = newState(settings.consumableOilMH ~= false)
    if states.oilMH.shown then
        states.oilMH.active, states.oilMH.icon, states.oilMH.timeText =
            ComputeEnhancementState("MH", hasMainHandEnchant, mainHandExpiration, mainHandEnchantID, buffs, now)
    end

    states.oilOH = newState(ShouldShowOHButton(settings))
    if states.oilOH.shown then
        states.oilOH.active, states.oilOH.icon, states.oilOH.timeText =
            ComputeEnhancementState("OH", hasOffHandEnchant, offHandExpiration, offHandEnchantID, buffs, now)
    end

    states.healthstone = newState(settings.consumableHealthstone ~= false and GetCachedWarlockPresence())
    if states.healthstone.shown then
        local hsCount = C_Item.GetItemCount(5512, false, true) or 0
        local hsLockCount = C_Item.GetItemCount(224464, false, true) or 0
        local totalHS = hsCount + hsLockCount
        states.healthstone.count = totalHS
        if totalHS > 0 then
            states.healthstone.active = true
        end
    end

    if canUseItems then
        for _, buttonType in ipairs(BUTTON_TYPES) do
            local state = states[buttonType]
            if state.shown and buttonType ~= "healthstone" then
                local entry = GetSnapshotEntry(buttonType)
                local selected = entry and entry.selected
                if selected then
                    state.clickable = true
                    state.itemID = selected.itemID
                    state.count = selected.count
                end
            end
        end
    end

    return states
end

local function PaintButton(button, buttonType, state)
    if repaintLog then repaintLog[#repaintLog + 1] = buttonType end

    button.status:SetTexture("Interface\\RaidFrame\\ReadyCheck-NotReady")
    if button.defaultIcon then
        button.icon:SetTexture(button.defaultIcon)
    end
    button.icon:SetDesaturated(true)
    button.timeText:SetText("")
    button.countText:SetText("")
    button.selectedItemID = nil
    if not InCombatLockdown() then
        if button.click then
            button.click.selectedItemID = nil
            button.click:Hide()
        end
    end
    StopButtonGlow(button)

    if state.active then
        button.status:SetTexture("Interface\\RaidFrame\\ReadyCheck-Ready")
        button.icon:SetDesaturated(false)
    end
    if state.icon then
        button.icon:SetTexture(state.icon)
    end
    if state.timeText ~= "" then
        button.timeText:SetText(state.timeText)
    end
    if buttonType == "healthstone" and state.shown then
        button.countText:SetText(tostring(state.count or 0))
    end

    ApplyPreferredIcon(button, buttonType)

    if state.clickable then
        local entry = GetSnapshotEntry(buttonType)
        if entry and entry.selected then
            ConfigureButtonClickAction(button, buttonType, entry.selected, not state.active)
        end
    end
end

local function ApplyButtonLayout(states)
    layoutRuns = layoutRuns + 1
    local buttons = ConsumablesFrame.buttons
    local xOffset = 0
    local buttonSize = ConsumablesFrame.buttonSize or DEFAULT_BUTTON_SIZE
    local buttonY = CLOSE_BUTTON_HEIGHT
    local visibleCount = 0
    for _, buttonType in ipairs(BUTTON_TYPES) do
        local button = buttons[buttonType]
        if type(button) == "table" and button.Hide then
            local state = states[buttonType]
            if state and state.shown then
                button:ClearAllPoints()
                button:SetPoint("BOTTOMLEFT", ConsumablesFrame, "BOTTOMLEFT", xOffset, buttonY)
                button:Show()
                xOffset = xOffset + buttonSize + BUTTON_SPACING
                visibleCount = visibleCount + 1
            else
                button:Hide()
            end
        end
    end
    local frameWidth = visibleCount > 0
        and (visibleCount * buttonSize + (visibleCount - 1) * BUTTON_SPACING)
        or buttonSize
    ConsumablesFrame:SetSize(frameWidth, buttonSize + CLOSE_BUTTON_HEIGHT)
end

UpdateConsumables = function()
    local settings = GetSettings()
    if not settings then return end

    if C_Secrets and C_Secrets.ShouldAurasBeSecret and C_Secrets.ShouldAurasBeSecret() then
        return
    end

    local buttons = ConsumablesFrame.buttons
    local frameScale = GetConsumableScale()
    if not InCombatLockdown() then
        ConsumablesFrame:SetScale(frameScale)
        if pickerFrame and pickerFrame:IsShown() then
            pickerFrame:SetScale(frameScale)
        end
    end

    local canUseItems = not InCombatLockdown()

    local states = ComputeDesiredStates(settings, canUseItems)

    local forceFull = snapshotCache.lastStates == nil
    local changed, visibilityChanged = DiffButtonStates(snapshotCache.lastStates, states, BUTTON_TYPES)
    snapshotCache.lastStates = states

    for _, buttonType in ipairs(changed) do
        local button = buttons[buttonType]
        if type(button) == "table" and button.icon then
            PaintButton(button, buttonType, states[buttonType])
        end
    end

    if not canUseItems then
        HideConsumablePicker()
    end

    if forceFull or visibilityChanged or snapshotCache.layoutDirty then
        if InCombatLockdown() then
            snapshotCache.layoutDirty = true
        else
            snapshotCache.layoutDirty = nil
            ApplyButtonLayout(states)
        end
    end
end

local lastMainHandEnchant = nil
local lastOffHandEnchant = nil
local weaponEnchantTicker = nil

local function CheckWeaponEnchantChanges()
    local hasMainHandEnchant, _, _, mainHandEnchantID, hasOffHandEnchant, _, _, offHandEnchantID = GetWeaponEnchantInfo()
    local currentMainHand = hasMainHandEnchant and mainHandEnchantID or nil
    local currentOffHand = hasOffHandEnchant and offHandEnchantID or nil
    if currentMainHand ~= lastMainHandEnchant or currentOffHand ~= lastOffHandEnchant then
        lastMainHandEnchant = currentMainHand
        lastOffHandEnchant = currentOffHand
        UpdateConsumables()
    end
end

local auraUpdatePending = false

local function RunPendingAuraUpdate()
    auraUpdatePending = false
    UpdateConsumables()
end

ConsumablesFrame:SetScript("OnEvent", function(self, event)
    if event == "UNIT_AURA" then
        if auraUpdatePending then return end
        auraUpdatePending = true
        C_Timer.After(0.2, RunPendingAuraUpdate)
    end
end)

ConsumablesFrame:SetScript("OnShow", function(self)
    self:RegisterUnitEvent("UNIT_AURA", "player")
    local hasMainHandEnchant, _, _, mainHandEnchantID, hasOffHandEnchant, _, _, offHandEnchantID = GetWeaponEnchantInfo()
    lastMainHandEnchant = hasMainHandEnchant and mainHandEnchantID or nil
    lastOffHandEnchant = hasOffHandEnchant and offHandEnchantID or nil
    if not weaponEnchantTicker then
        weaponEnchantTicker = C_Timer.NewTicker(0.5, CheckWeaponEnchantChanges)
    end
end)

ConsumablesFrame:SetScript("OnHide", function(self)
    HideConsumablePicker()
    self:UnregisterEvent("UNIT_AURA")
    if weaponEnchantTicker then
        weaponEnchantTicker:Cancel()
        weaponEnchantTicker = nil
    end
end)

local function PositionConsumablesFrame()
    if not InCombatLockdown() then
        ConsumablesFrame:SetScale(GetConsumableScale())
    end
    ConsumablesFrame:SetParent(UIParent)
    ConsumablesFrame:SetFrameStrata("DIALOG")
    local anchoring = ns.QUI_Anchoring
    if anchoring and anchoring.layoutOwnedFrames and anchoring.layoutOwnedFrames[ConsumablesFrame] then
        return
    end
    ConsumablesFrame:ClearAllPoints()
    ConsumablesFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 100)
    if _G.QUI_ApplyAllFrameAnchors then
        _G.QUI_ApplyAllFrameAnchors()
    end
end

local function IsInDungeonInstance()
    local _, instanceType = IsInInstance()
    return instanceType == "party"
end

local function IsInRaidInstance()
    local _, instanceType = IsInInstance()
    return instanceType == "raid"
end

local function ShowConsumablesStandalone()
    HideConsumablePicker()
    InitializeButtons()
    UpdateConsumables()
    if not InCombatLockdown() then
        ConsumablesFrame:SetScale(GetConsumableScale())
    end
    ConsumablesFrame:SetAlpha(1)
    ConsumablesFrame:SetParent(UIParent)
    ConsumablesFrame:SetFrameStrata("DIALOG")
    PositionConsumablesFrame()
    ConsumablesFrame:Show()
end

local function OnReadyCheck(starter, timer)
    local settings = GetSettings()
    if not settings or settings.consumableCheckEnabled == false then return end
    if settings.consumableOnReadyCheck == false then return end

    HideConsumablePicker()
    PositionConsumablesFrame()
    UpdateConsumables()
    ConsumablesFrame:SetAlpha(1)
    ConsumablesFrame:Show()
end

local function OnReadyCheckFinished()
    RequestHideConsumablesFrame()
end

local function OnInstanceEnter()
    lastMainHandEnchant = nil
    lastOffHandEnchant = nil

    local settings = GetSettings()
    if not settings or settings.consumableCheckEnabled == false then return end
    if InCombatLockdown() then return end

    if settings.consumableOnDungeon and IsInDungeonInstance() then
        ShowConsumablesStandalone()
        return
    end
    if settings.consumableOnRaid and IsInRaidInstance() then
        ShowConsumablesStandalone()
        return
    end
end

local function OnResurrect()
    local settings = GetSettings()
    if not settings or settings.consumableCheckEnabled == false then return end
    if not settings.consumableOnResurrect then return end
    if InCombatLockdown() then return end
    if not ns.Utils.IsInInstancedContent() then return end
    ShowConsumablesStandalone()
end

local expirationTicker = nil
local lastExpirationWarning = 0
local WARNING_COOLDOWN = 60

local function CheckExpiringBuffs()
    local settings = GetSettings()
    if not settings or settings.consumableCheckEnabled == false then return nil end
    if not settings.consumableExpirationWarning then return nil end
    if not ns.Utils.IsInInstancedContent() then return nil end
    if InCombatLockdown() then return nil end

    local threshold = (settings.consumableExpirationThreshold or 300)
    local now = GetTime()
    local expiringBuffs = {}
    local buffs = ScanPlayerBuffs()

    if settings.consumableFood ~= false and buffs.hasFood and buffs.foodData then
        local expires = buffs.foodData.expirationTime
        if expires and expires > 0 then
            local remaining = expires - now
            if remaining > 0 and remaining <= threshold then
                table.insert(expiringBuffs, { type = "food", remaining = remaining })
            end
        end
    end
    if settings.consumableFlask ~= false and buffs.hasFlask and buffs.flaskData then
        local expires = buffs.flaskData.expirationTime
        if expires and expires > 0 then
            local remaining = expires - now
            if remaining > 0 and remaining <= threshold then
                table.insert(expiringBuffs, { type = "flask", remaining = remaining })
            end
        end
    end
    if settings.consumableRune ~= false and buffs.hasRune and buffs.runeData then
        local expires = buffs.runeData.expirationTime
        if expires and expires > 0 then
            local remaining = expires - now
            if remaining > 0 and remaining <= threshold then
                table.insert(expiringBuffs, { type = "rune", remaining = remaining })
            end
        end
    end
    if settings.consumableOilMH ~= false then
        local mhConfig = GetEnhancementConfig("MH")
        if mhConfig and mhConfig.checkType == "playerAura" then
            if buffs.hasWeaponMH and buffs.weaponMHData then
                local expires = buffs.weaponMHData.expirationTime
                if expires and expires > 0 then
                    local remaining = expires - now
                    if remaining > 0 and remaining <= threshold then
                        table.insert(expiringBuffs, { type = "oilMH", remaining = remaining })
                    end
                end
            end
        else
            local hasMainHandEnchant, mainHandExpiration = GetWeaponEnchantInfo()
            if hasMainHandEnchant and mainHandExpiration then
                local remaining = mainHandExpiration / 1000
                if remaining > 0 and remaining <= threshold then
                    table.insert(expiringBuffs, { type = "oilMH", remaining = remaining })
                end
            end
        end
    end
    if ShouldShowOHButton(settings) then
        local ohConfig = GetEnhancementConfig("OH")
        if ohConfig and ohConfig.checkType == "playerAura" then
            if buffs.hasWeaponOH and buffs.weaponOHData then
                local expires = buffs.weaponOHData.expirationTime
                if expires and expires > 0 then
                    local remaining = expires - now
                    if remaining > 0 and remaining <= threshold then
                        table.insert(expiringBuffs, { type = "oilOH", remaining = remaining })
                    end
                end
            end
        else
            local _, _, _, _, hasOffHandEnchant, offHandExpiration = GetWeaponEnchantInfo()
            if hasOffHandEnchant and offHandExpiration then
                local remaining = offHandExpiration / 1000
                if remaining > 0 and remaining <= threshold then
                    table.insert(expiringBuffs, { type = "oilOH", remaining = remaining })
                end
            end
        end
    end

    return #expiringBuffs > 0 and expiringBuffs or nil
end

local function ShowExpirationWarning()
    local now = GetTime()
    if now - lastExpirationWarning < WARNING_COOLDOWN then return end
    local expiringBuffs = CheckExpiringBuffs()
    if not expiringBuffs then return end
    if ConsumablesFrame:IsShown() then return end
    lastExpirationWarning = now
    ShowConsumablesStandalone()
end

local function StartExpirationMonitoring()
    local settings = GetSettings()
    if not settings or not settings.consumableExpirationWarning then return end
    if expirationTicker then expirationTicker:Cancel(); expirationTicker = nil end
    if not ns.Utils.IsInInstancedContent() then return end
    expirationTicker = C_Timer.NewTicker(30, ShowExpirationWarning)
    C_Timer.After(2, ShowExpirationWarning)
end

local function StopExpirationMonitoring()
    if expirationTicker then expirationTicker:Cancel(); expirationTicker = nil end
end

local function OnInventoryPossiblyChanged()
    InvalidateInventorySnapshot()
    if ConsumablesFrame:IsShown() then
        UpdateConsumables()
    end
end

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("READY_CHECK")
eventFrame:RegisterEvent("READY_CHECK_FINISHED")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("PLAYER_ALIVE")

eventFrame:SetScript("OnEvent", function(self, event, ...)
    if event == "ADDON_LOADED" then
        local loadedAddon = ...
        if loadedAddon ~= ADDON_NAME then return end
        self:UnregisterEvent("ADDON_LOADED")
        InitializeButtons()
    elseif event == "READY_CHECK" then
        OnReadyCheck(...)
    elseif event == "READY_CHECK_FINISHED" then
        OnReadyCheckFinished()
    elseif event == "PLAYER_ENTERING_WORLD" then
        C_Timer.After(1, OnInstanceEnter)
        C_Timer.After(1.5, function()
            local s = GetSettings()
            if s and s.consumablePersistent and s.consumableCheckEnabled ~= false then
                ShowConsumablesStandalone()
            end
        end)
        C_Timer.After(2, function()
            if ns.Utils.IsInInstancedContent() then
                StartExpirationMonitoring()
            else
                StopExpirationMonitoring()
            end
        end)
    elseif event == "PLAYER_ALIVE" then
        C_Timer.After(0.5, OnResurrect)
    elseif event == "BAG_UPDATE_DELAYED" or event == "PLAYER_EQUIPMENT_CHANGED"
        or event == "GROUP_ROSTER_UPDATE" then
        OnInventoryPossiblyChanged()
    end
end)

if ns.Storage and ns.Storage.Bus then
    ns.Storage.Bus.Subscribe("BagsChanged", OnInventoryPossiblyChanged)
    ns.Storage.Bus.Subscribe("EquippedChanged", OnInventoryPossiblyChanged)
else
    eventFrame:RegisterEvent("BAG_UPDATE_DELAYED")
    eventFrame:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
end
eventFrame:RegisterEvent("GROUP_ROSTER_UPDATE")

if ns.WhenLoggedIn then
    ns.WhenLoggedIn(function()
        InitializeButtons()
        C_Timer.After(1, OnInstanceEnter)
        C_Timer.After(1.5, function()
            local s = GetSettings()
            if s and s.consumablePersistent and s.consumableCheckEnabled ~= false then
                ShowConsumablesStandalone()
            end
        end)
        C_Timer.After(2, function()
            if ns.Utils.IsInInstancedContent() then
                StartExpirationMonitoring()
            else
                StopExpirationMonitoring()
            end
        end)
    end)
end

local combatFrame = CreateFrame("Frame")
combatFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
combatFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
combatFrame:SetScript("OnEvent", function(self, event)
    if event == "PLAYER_REGEN_DISABLED" then
        HideConsumablePicker()
        for _, button in pairs(ConsumablesFrame.buttons) do
            if type(button) == "table" and button.click then
                button.click:Hide()
            end
        end
        snapshotCache.lastStates = nil
    elseif event == "PLAYER_REGEN_ENABLED" then
        if hideConsumablesAfterCombat then
            return
        end
        UpdateConsumables()
    end
end)

local zoneFrame = CreateFrame("Frame")
zoneFrame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
zoneFrame:SetScript("OnEvent", function()
    C_Timer.After(2, function()
        if ns.Utils.IsInInstancedContent() then
            StartExpirationMonitoring()
        else
            StopExpirationMonitoring()
        end
    end)
end)

_G.QUI_RefreshConsumables = function()
    InvalidateInventorySnapshot()
    if ConsumablesFrame:IsShown() then
        local point, relativeTo, relativePoint, x, y = ConsumablesFrame:GetPoint()
        InitializeButtons()
        UpdateConsumables()
        ConsumablesFrame:SetScale(GetConsumableScale())
        ConsumablesFrame:ClearAllPoints()
        ConsumablesFrame:SetPoint(point, relativeTo, relativePoint, x, y)
    end
    if pickerFrame then
        local bgr, bgg, bgb = 0.05, 0.05, 0.05
        if Helpers and Helpers.GetSkinBgColor then
            bgr, bgg, bgb = Helpers.GetSkinBgColor()
        end
        local sr, sg, sb = 0.35, 0.35, 0.35
        if Helpers and Helpers.GetSkinBorderColor then
            sr, sg, sb = Helpers.GetSkinBorderColor()
        end
        if SkinBase and SkinBase.CreateBackdrop then
            SkinBase.CreateBackdrop(pickerFrame, sr, sg, sb, 1, bgr, bgg, bgb, 0.95)
        else
            pickerFrame:SetBackdropColor(bgr, bgg, bgb, 0.95)
            pickerFrame:SetBackdropBorderColor(sr, sg, sb, 1)
        end
    end
end

_G.QUI_ShowConsumables = function() ShowConsumablesStandalone() end
_G.QUI_HideConsumables = function() RequestHideConsumablesFrame() end

if ns.Registry then
    ns.Registry:Register("consumables", {
        refresh = _G.QUI_RefreshConsumables,
        priority = 30,
        group = "qol",
        importCategories = { "qol" },
    })
    ns.Registry:Register("consumablesSkin", {
        refresh = _G.QUI_RefreshConsumables,
        priority = 30,
        group = "skinning",
        importCategories = { "skinning", "theme" },
    })
end

if ns.__test then
    repaintLog = {}
    ns.ConsumableCheckTest = {
        RuneIconFallback = RUNE_ICON_FALLBACK,
        GetButtons = function() return ConsumablesFrame.buttons end,
        GetOwnedItemsForButton = GetOwnedItemsForButton,
        ResolveSelectedOwnedItem = ResolveSelectedOwnedItem,
        BuildOwnedItemsFromTotals = BuildOwnedItemsFromTotals,
        GetMacroPreferredItemID = GetMacroPreferredItemID,
        GetEnhancementLabel = GetEnhancementLabel,
        ShouldPersistPreferenceOnUse = ShouldPersistPreferenceOnUse,
        ButtonStatesEqual = ButtonStatesEqual,
        DiffButtonStates = DiffButtonStates,
        GetSnapshotEntry = GetSnapshotEntry,
        InvalidateInventorySnapshot = InvalidateInventorySnapshot,
        ComputeDesiredStates = ComputeDesiredStates,
        RunUpdate = function() UpdateConsumables() end,
        GetRepaintLog = function() return repaintLog end,
        ResetRepaintLog = function()
            for i = #repaintLog, 1, -1 do repaintLog[i] = nil end
        end,
        GetLayoutRunCount = function() return layoutRuns end,
    }
end
