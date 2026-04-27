local ADDON_NAME, ns = ...
local Helpers = ns.Helpers
local UIKit = ns.UIKit

---------------------------------------------------------------------------
-- CONSUMABLE CHECK
-- Shows consumable status buttons on ready check, instance entry, resurrect
---------------------------------------------------------------------------

local LCG = LibStub and LibStub("LibCustomGlow-1.0", true)

local DEFAULT_BUTTON_SIZE = 40
local BUTTON_SPACING = 0
local STATUS_ICON_SIZE = 18

local INVSLOT_MAINHAND = 16
local INVSLOT_OFFHAND = 17
local FOOD_ICON_FALLBACK = 136000
local PICKER_ROW_HEIGHT = 24
local PICKER_MIN_WIDTH = 200

---------------------------------------------------------------------------
-- BUFF / ITEM DATA
---------------------------------------------------------------------------

local FOOD_BUFFS = {
    -- Midnight / current retail generic Well Fed auras
    [1232324] = true, [285719] = true,
}

local FLASK_BUFFS = {
    -- Midnight Flasks
    [1235057] = true, [1235108] = true, [1235110] = true, [1235111] = true,
}

local RUNE_BUFFS = {
    [1234969] = true,  -- Midnight Augment Rune
    [1242347] = true,  -- Greater Midnight Augment Rune
    [1264426] = true,  -- Void-Touched Augment Rune (Midnight)
}

local FLASK_ITEMS = {
    -- Midnight Flasks (all current item variants)
    241320, 241321, -- Flask of Thalassian Resistance
    241322, 241323, -- Flask of the Magisters
    241324, 241325, -- Flask of the Blood Knights
    241326, 241327, -- Flask of the Shattered Sun
}
local FLASK_ITEM_SET = {}
for _, itemID in ipairs(FLASK_ITEMS) do
    FLASK_ITEM_SET[itemID] = true
end

local RUNE_ITEMS = {
    259085,  -- Void-Touched Augment Rune (Midnight)
    243191,  -- Ethereal Augment Rune (infinite)
}

local OIL_ITEMS = {
    -- Midnight Oils
    243733, 243734, -- Thalassian Phoenix Oil
    243735, 243736, -- Oil of Dawn
    243737, 243738, -- Smuggler's Enchanted Edge
    -- Midnight Stones
    237370, 237371, -- Refulgent Whetstone
    237367, 237369, -- Refulgent Weightstone
}

local AMMO_ITEMS = {
    -- Midnight Hunter Ammo (Engineering)
    257746, 257745, -- Farstrider's Hawkeye (Crit)
    257748, 257747, -- Smuggler's Lynxeye (Mastery)
    257750, 257749, -- Laced Zoomshots (Nature DoT)
    257752, 257751, -- Weighted Boomshots (AoE Fire)
}

local WEAPON_ENCHANTS = {}

local PREFERENCE_KEYS = {
    food = "consumablePreferredFood",
    flask = "consumablePreferredFlask",
    rune = "consumablePreferredRune",
    oilMH = "consumablePreferredOilMH",
    oilOH = "consumablePreferredOilOH",
}

---------------------------------------------------------------------------
-- CLASS-AWARE WEAPON ENHANCEMENT CONFIG
---------------------------------------------------------------------------

local BuildOwnedItemsFromList  -- forward declaration (defined in utility section below)

local _, playerClass = UnitClass("player")

-- Each class entry has MH and/or OH sub-configs:
--   source: "spell" (cast via /cast) or "item" (use via /use, default for non-class configs)
--   label: display name for UI
--   checkType: "weaponEnchant" (GetWeaponEnchantInfo) or "playerAura" (buff scan)
--   anyEnchantIDs: set of enchant IDs for weaponEnchant detection
--   anyBuffIDs: set of aura spell IDs for playerAura detection
--   spells: ordered list of { spellID, name } for spell-based enhancements
--   items: item ID list for item-based enhancements (hunter ammo)
--   requiresShield: only show if shield equipped (shaman OH)
local CLASS_ENHANCEMENT_CONFIG = {
    ROGUE = {
        MH = {
            source = "spell",
            label = "Lethal Poison",
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
            label = "Non-Lethal Poison",
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
        -- Enhancement: Windfury → MH. Resto: Earthliving → MH.
        -- Flametongue is OH-only for Enhancement and lives in OHWeapon below.
        MH = {
            source = "spell",
            label = "Weapon Imbue",
            checkType = "weaponEnchant",
            anyEnchantIDs = { [5400] = true, [5401] = true, [6498] = true },
            spells = {
                { spellID = 33757,  name = "Windfury Weapon" },
                { spellID = 382021, name = "Earthliving Weapon" },
            },
        },
        -- Resto/Ele with shield equipped
        OHShield = {
            source = "spell",
            label = "Shield Enchant",
            checkType = "weaponEnchant",
            anyEnchantIDs = { [7587] = true, [7528] = true },
            spells = {
                { spellID = 462757, name = "Thunderstrike Ward" },
                { spellID = 457481, name = "Tidecaller's Guard" },
            },
        },
        -- Enhancement dual-wielding: Flametongue → OH
        OHWeapon = {
            source = "spell",
            label = "Offhand Imbue",
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
            label = "Weapon Rite",
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
            label = "Ammo",
            checkType = "weaponEnchant",
            items = AMMO_ITEMS,
        },
    },
}

-- Forward declarations: SHAMAN OH dispatch (below) needs these before they are defined.
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
    return classID == 4 and subClassID == 6  -- Armor / Shield
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
            -- Fallback: try first spell even if not yet known at load time
            if config.spells and config.spells[1] then
                local icon = C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(config.spells[1].spellID)
                if icon then return icon end
            end
        elseif config.items then
            local items = BuildOwnedItemsFromList(config.items)
            if items[1] and items[1].icon then return items[1].icon end
            -- Fallback: use first item's icon from game data
            local icon = select(5, C_Item.GetItemInfoInstant(config.items[1]))
            if icon then return icon end
        end
    end
    -- Default: try first owned oil icon
    local oils = BuildOwnedItemsFromList(OIL_ITEMS)
    if oils[1] and oils[1].icon then return oils[1].icon end
    return 609892  -- generic fallback
end

local function GetEnhancementLabel(slot)
    local config = GetEnhancementConfig(slot)
    if config and config.label then return config.label end
    return slot == "MH" and "Weapon Oil" or "Weapon Oil"
end

-- Export label function for options panel
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

---------------------------------------------------------------------------
-- UTILITY FUNCTIONS
---------------------------------------------------------------------------

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
    if playerClass == "WARLOCK" then return true end
    local numMembers = GetNumGroupMembers()
    if numMembers == 0 then return false end
    local prefix = IsInRaid() and "raid" or "party"
    for i = 1, numMembers do
        local unit = prefix .. i
        if UnitExists(unit) then
            local _, class = UnitClass(unit)
            if class == "WARLOCK" then return true end
        end
    end
    return false
end

function IsDualWielding()
    local offhand = GetInventoryItemID("player", INVSLOT_OFFHAND)
    if not offhand then return false end
    local _, _, _, _, _, itemClassID = C_Item.GetItemInfoInstant(offhand)
    return itemClassID == 2  -- LE_ITEM_CLASS_WEAPON
end

local function FormatTimeRemaining(seconds)
    if seconds >= 3600 then
        return string.format("%dh", math.floor(seconds / 3600))
    elseif seconds >= 60 then
        return string.format("%dm", math.floor(seconds / 60))
    else
        return string.format("%ds", math.floor(seconds))
    end
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

local function BuildOwnedItemsFromTotals(totals, fallbackIcon)
    local items = {}
    for itemID, count in pairs(totals) do
        local itemName = C_Item.GetItemInfo(itemID)
        local icon = select(5, C_Item.GetItemInfoInstant(itemID))
        table.insert(items, {
            itemID = itemID,
            name = itemName or ("item:" .. itemID),
            count = count,
            icon = icon or fallbackIcon,
        })
    end
    table.sort(items, function(a, b)
        return (a.name or "") < (b.name or "")
    end)
    return items
end

BuildOwnedItemsFromList = function(itemIDs, fallbackIcon)
    local totals = {}
    CollectItemTotalsFromList(itemIDs, totals)
    return BuildOwnedItemsFromTotals(totals, fallbackIcon)
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
                return BuildOwnedItemsFromList(config.items)
            end
        end
        return BuildOwnedItemsFromList(OIL_ITEMS)
    end
    return {}
end

local function ResolveSelectedOwnedItem(buttonType, ownedItems)
    local preferredItemID = GetPreferredItemID(buttonType)
    if preferredItemID then
        for _, itemData in ipairs(ownedItems) do
            if itemData.itemID == preferredItemID then
                return itemData
            end
        end
        SetPreferredItemID(buttonType, nil)
    end
    return ownedItems[1]
end

local function ConfigureButtonClickAction(button, buttonType, data, showGlow)
    if not button or not button.click or not data then return end
    button.selectedItemID = data.itemID
    button.click.selectedItemID = data.itemID

    button.click:SetAttribute("type1", "macro")
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

local function ApplyPreferredItemIcons(buttons, settings)
    if not settings then return end

    local function apply(buttonType)
        local button = buttons[buttonType]
        if not button then return end
        local preferredID = GetPreferredItemID(buttonType)
        if not preferredID then return end
        -- Check if this is a spell preference (for class-based enhancements)
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

    if settings.consumableFood ~= false then apply("food") end
    if settings.consumableFlask ~= false then apply("flask") end
    if settings.consumableRune ~= false then apply("rune") end
    if settings.consumableOilMH ~= false then apply("oilMH") end
    if settings.consumableOilOH ~= false then apply("oilOH") end
end

local function ScanPlayerBuffs()
    local result = {
        hasFood = false, hasFlask = false, hasRune = false,
        hasWeaponMH = false, hasWeaponOH = false,
        foodData = nil, flaskData = nil, runeData = nil,
        weaponMHData = nil, weaponOHData = nil,
    }
    -- Check aura-based weapon enhancements (rogues)
    local mhConfig = GetEnhancementConfig("MH")
    local ohConfig = GetEnhancementConfig("OH")
    local checkMHAura = mhConfig and mhConfig.checkType == "playerAura"
    local checkOHAura = ohConfig and ohConfig.checkType == "playerAura"

    for i = 1, 40 do
        local auraData = C_UnitAuras.GetAuraDataByIndex("player", i, "HELPFUL")
        if not auraData then break end
        local spellId = auraData.spellId
        local icon = auraData.icon
        if not result.hasFood then
            local success, isFood = pcall(function() return FOOD_BUFFS[spellId] or icon == 136000 end)
            if success and isFood then result.hasFood = true; result.foodData = auraData end
        end
        if not result.hasFlask then
            local success, isFlask = pcall(function() return FLASK_BUFFS[spellId] end)
            if success and isFlask then result.hasFlask = true; result.flaskData = auraData end
        end
        if not result.hasRune then
            local success, isRune = pcall(function() return RUNE_BUFFS[spellId] end)
            if success and isRune then result.hasRune = true; result.runeData = auraData end
        end
        if checkMHAura and not result.hasWeaponMH then
            local ok, match = pcall(function() return mhConfig.anyBuffIDs[spellId] end)
            if ok and match then result.hasWeaponMH = true; result.weaponMHData = auraData end
        end
        if checkOHAura and not result.hasWeaponOH then
            local ok, match = pcall(function() return ohConfig.anyBuffIDs[spellId] end)
            if ok and match then result.hasWeaponOH = true; result.weaponOHData = auraData end
        end
    end
    return result
end

---------------------------------------------------------------------------
-- CONSUMABLES FRAME
---------------------------------------------------------------------------

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
end

local function EnsureConsumableCombatDeferFrame()
    if consumableCombatDeferFrame then return end
    consumableCombatDeferFrame = CreateFrame("Frame")
    consumableCombatDeferFrame:SetScript("OnEvent", function(f, event)
        if event ~= "PLAYER_REGEN_ENABLED" then return end
        f:UnregisterEvent("PLAYER_REGEN_ENABLED")
        if hideConsumablesAfterCombat then
            hideConsumablesAfterCombat = false
            -- In persistent mode, restore visibility instead of hiding
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
    -- In persistent mode, never auto-hide (close button calls HideConsumablesFrameNow directly)
    local settings = GetSettings()
    if settings and settings.consumablePersistent and settings.consumableCheckEnabled ~= false then
        return
    end
    if InCombatLockdown() then
        hideConsumablesAfterCombat = true
        if ConsumablesFrame:IsShown() then
            -- In combat we cannot hide this protected frame safely, so make it invisible immediately.
            ConsumablesFrame:SetAlpha(0)
        end
        EnsureConsumableCombatDeferFrame()
        consumableCombatDeferFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
        return
    end

    hideConsumablesAfterCombat = false
    HideConsumablesFrameNow()
end

-- Close button
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
closeButton.text:SetText("Close")
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

---------------------------------------------------------------------------
-- BUTTON CREATION
---------------------------------------------------------------------------

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
    button.timeText:SetFont(STANDARD_TEXT_FONT, 9, "OUTLINE")
    button.timeText:SetTextColor(1, 1, 1, 1)

    button.countText = button:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    button.countText:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -2, 2)
    button.countText:SetFont(STANDARD_TEXT_FONT, 10, "OUTLINE")
    button.countText:SetTextColor(1, 1, 1, 1)

    if isClickable then
        button.click = CreateFrame("Button", nil, button, "SecureActionButtonTemplate")
        button.click:SetAllPoints()
        button.click:RegisterForClicks("AnyUp", "AnyDown")
        button.click:Hide()
        button.click:SetAttribute("type1", "macro")
        button.click:SetScript("OnEnter", function() button:SetAlpha(0.7) end)
        button.click:SetScript("OnLeave", function() button:SetAlpha(1) end)
        button.click:SetScript("PostClick", function(self, mouseButton, down)
            if down then return end
            if mouseButton == "RightButton" then
                if not InCombatLockdown() and ToggleConsumablePicker then
                    ToggleConsumablePicker(button)
                end
                return
            end
            if mouseButton == "LeftButton" and self.selectedItemID then
                SetPreferredItemID(button.buttonType, self.selectedItemID)
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
    pickerFrame:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    pickerFrame:SetBackdropColor(0.05, 0.05, 0.05, 0.95)
    pickerFrame:SetBackdropBorderColor(0.35, 0.35, 0.35, 1)
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
            -- Defer hide until combat ends to avoid ADDON_ACTION_BLOCKED
            local f = CreateFrame("Frame")
            f:RegisterEvent("PLAYER_REGEN_ENABLED")
            f:SetScript("OnEvent", function(self)
                self:UnregisterAllEvents()
                if pickerFrame then pickerFrame:Hide() end
            end)
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

    local runeIcon = C_Item.GetItemIconByID and C_Item.GetItemIconByID(259085) or 4549102
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
        buttons[i] = button
    end

    ConsumablesFrame.buttonSize = buttonSize
end

---------------------------------------------------------------------------
-- CLASS-AWARE ENHANCEMENT DETECTION
---------------------------------------------------------------------------

-- Checks whether a weapon enhancement is active for the given slot.
-- Returns isActive; also updates the button icon/status/time directly.
local function CheckEnhancementActive(slot, button, hasEnchant, enchantExpiration, enchantID)
    local config = GetEnhancementConfig(slot)

    if config and config.checkType == "playerAura" then
        -- Aura-based detection (rogues)
        for i = 1, 40 do
            local auraData = C_UnitAuras.GetAuraDataByIndex("player", i, "HELPFUL")
            if not auraData then break end
            local ok, match = pcall(function() return config.anyBuffIDs[auraData.spellId] end)
            if ok and match then
                button.status:SetTexture("Interface\\RaidFrame\\ReadyCheck-Ready")
                button.icon:SetDesaturated(false)
                if auraData.icon then
                    button.icon:SetTexture(auraData.icon)
                end
                pcall(function()
                    local expires = auraData.expirationTime
                    if expires and expires > 0 then
                        button.timeText:SetText(FormatTimeRemaining(expires - GetTime()))
                    end
                end)
                return true
            end
        end
        return false
    end

    if config and config.checkType == "weaponEnchant" then
        -- Enchant-based detection with class-specific enchant IDs (shamans, paladins)
        if hasEnchant then
            button.status:SetTexture("Interface\\RaidFrame\\ReadyCheck-Ready")
            button.icon:SetDesaturated(false)
            if enchantID and config.anyEnchantIDs and config.anyEnchantIDs[enchantID] then
                -- Known class enchant - use the spell icon for the active enchant
                if config.spells then
                    for _, spell in ipairs(config.spells) do
                        local icon = C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(spell.spellID)
                        if icon then
                            button.icon:SetTexture(icon)
                            break
                        end
                    end
                end
            elseif enchantID and WEAPON_ENCHANTS[enchantID] then
                -- Fallback: known item enchant (should not happen for class enhancements)
                local enchantData = WEAPON_ENCHANTS[enchantID]
                button.icon:SetTexture(enchantData.icon)
            end
            if enchantExpiration and enchantExpiration > 0 then
                button.timeText:SetText(FormatTimeRemaining(enchantExpiration / 1000))
            end
            return true
        end
        return false
    end

    -- Default: item-based oil/stone detection via GetWeaponEnchantInfo
    local invSlot = slot == "MH" and INVSLOT_MAINHAND or INVSLOT_OFFHAND
    if hasEnchant then
        button.status:SetTexture("Interface\\RaidFrame\\ReadyCheck-Ready")
        button.icon:SetDesaturated(false)
        if enchantID and WEAPON_ENCHANTS[enchantID] then
            local enchantData = WEAPON_ENCHANTS[enchantID]
            button.icon:SetTexture(enchantData.icon)
            SaveLastWeaponEnchant(invSlot, enchantID, enchantData.icon, enchantData.item)
        end
        if enchantExpiration and enchantExpiration > 0 then
            button.timeText:SetText(FormatTimeRemaining(enchantExpiration / 1000))
        end
        return true
    else
        -- Restore last known icon when enchant has expired
        local lastEnchant = GetLastWeaponEnchant(invSlot)
        if lastEnchant and lastEnchant.icon then
            button.icon:SetTexture(lastEnchant.icon)
        end
        return false
    end
end

-- Checks whether an OH enhancement button should be visible for the current class
local function ShouldShowOHButton(settings)
    if settings.consumableOilOH == false then return false end
    local config = GetEnhancementConfig("OH")
    if config then
        if config.requiresShield then
            return HasShieldEquipped()
        end
        return true
    end
    -- No class config for OH: check if class explicitly has no OH (Paladin, Hunter)
    local classConfig = CLASS_ENHANCEMENT_CONFIG[playerClass]
    if classConfig and classConfig.MH and not classConfig.OH then
        return false
    end
    -- Default: show if dual wielding
    return IsDualWielding()
end

---------------------------------------------------------------------------
-- UPDATE CONSUMABLE STATUS
---------------------------------------------------------------------------

UpdateConsumables = function()
    local settings = GetSettings()
    if not settings then return end

    local buttons = ConsumablesFrame.buttons
    local frameScale = GetConsumableScale()
    if not InCombatLockdown() then
        ConsumablesFrame:SetScale(frameScale)
        if pickerFrame and pickerFrame:IsShown() then
            pickerFrame:SetScale(frameScale)
        end
    end
    local now = GetTime()
    local visibleCount = 0
    local hasFoodBuff = false
    local hasFlaskBuff = false
    local hasRuneBuff = false

    -- Reset all buttons
    for _, button in pairs(buttons) do
        if type(button) == "table" and button.icon then
            button.status:SetTexture("Interface\\RaidFrame\\ReadyCheck-NotReady")
            if button.defaultIcon then
                button.icon:SetTexture(button.defaultIcon)
            end
            button.icon:SetDesaturated(true)
            button.timeText:SetText("")
            button.countText:SetText("")
            button.selectedItemID = nil
            if not InCombatLockdown() then
                button:Hide()
                if button.click then
                    button.click.selectedItemID = nil
                    button.click:Hide()
                end
            end
            StopButtonGlow(button)
        end
    end

    -- Scan player buffs
    for i = 1, 40 do
        local auraData = C_UnitAuras.GetAuraDataByIndex("player", i, "HELPFUL")
        if not auraData then break end
        local spellId = auraData.spellId
        local expires = auraData.expirationTime
        local icon = auraData.icon

        if settings.consumableFood ~= false then
            local success, isFood = pcall(function() return FOOD_BUFFS[spellId] or icon == 136000 end)
            if success and isFood then
                hasFoodBuff = true
                buttons.food.status:SetTexture("Interface\\RaidFrame\\ReadyCheck-Ready")
                buttons.food.icon:SetDesaturated(false)
                pcall(function()
                    if expires and expires > 0 then
                        buttons.food.timeText:SetText(FormatTimeRemaining(expires - now))
                    end
                end)
            end
        end

        if settings.consumableFlask ~= false then
            local success, isFlask = pcall(function() return FLASK_BUFFS[spellId] end)
            if success and isFlask then
                hasFlaskBuff = true
                buttons.flask.status:SetTexture("Interface\\RaidFrame\\ReadyCheck-Ready")
                buttons.flask.icon:SetDesaturated(false)
                buttons.flask.icon:SetTexture(icon)
                pcall(function()
                    if expires and expires > 0 then
                        buttons.flask.timeText:SetText(FormatTimeRemaining(expires - now))
                    end
                end)
            end
        end

        if settings.consumableRune ~= false then
            local success, isRune = pcall(function() return RUNE_BUFFS[spellId] end)
            if success and isRune then
                hasRuneBuff = true
                buttons.rune.status:SetTexture("Interface\\RaidFrame\\ReadyCheck-Ready")
                buttons.rune.icon:SetDesaturated(false)
                pcall(function()
                    if expires and expires > 0 then
                        buttons.rune.timeText:SetText(FormatTimeRemaining(expires - now))
                    end
                end)
            end
        end
    end

    -- Weapon enhancement check (class-aware)
    local hasMainHandEnchant, mainHandExpiration, _, mainHandEnchantID, hasOffHandEnchant, offHandExpiration, _, offHandEnchantID = GetWeaponEnchantInfo()
    local hasMHEnhancement = false
    local hasOHEnhancement = false

    if settings.consumableOilMH ~= false then
        hasMHEnhancement = CheckEnhancementActive("MH", buttons.oilMH, hasMainHandEnchant, mainHandExpiration, mainHandEnchantID)
    end

    if ShouldShowOHButton(settings) then
        hasOHEnhancement = CheckEnhancementActive("OH", buttons.oilOH, hasOffHandEnchant, offHandExpiration, offHandEnchantID)
    end

    -- Healthstone count
    if settings.consumableHealthstone ~= false and HasWarlockInGroup() then
        local hsCount = C_Item.GetItemCount(5512, false, true) or 0
        local hsLockCount = C_Item.GetItemCount(224464, false, true) or 0
        local ok, totalHS = pcall(function() return hsCount + hsLockCount end)
        if not ok then totalHS = 0 end
        if totalHS > 0 then
            buttons.healthstone.status:SetTexture("Interface\\RaidFrame\\ReadyCheck-Ready")
            buttons.healthstone.icon:SetDesaturated(false)
            buttons.healthstone.countText:SetText(tostring(totalHS))
        else
            buttons.healthstone.countText:SetText("0")
        end
    end

    -- If a preferred item is configured, use that icon for the category.
    ApplyPreferredItemIcons(buttons, settings)

    local canUseItems = not InCombatLockdown()
    if canUseItems then
        if settings.consumableFood ~= false then
            local ownedFoodItems = GetOwnedItemsForButton("food")
            local selectedFood = ResolveSelectedOwnedItem("food", ownedFoodItems)
            if selectedFood then
                ConfigureButtonClickAction(buttons.food, "food", selectedFood, not hasFoodBuff)
            end
        end

        if settings.consumableFlask ~= false then
            local ownedFlasks = GetOwnedItemsForButton("flask")
            local selectedFlask = ResolveSelectedOwnedItem("flask", ownedFlasks)
            if selectedFlask then
                ConfigureButtonClickAction(buttons.flask, "flask", selectedFlask, not hasFlaskBuff)
            end
        end

        if settings.consumableRune ~= false then
            local ownedRunes = GetOwnedItemsForButton("rune")
            local selectedRune = ResolveSelectedOwnedItem("rune", ownedRunes)
            if selectedRune then
                ConfigureButtonClickAction(buttons.rune, "rune", selectedRune, not hasRuneBuff)
            end
        end

        if settings.consumableOilMH ~= false then
            local ownedMH = GetOwnedItemsForButton("oilMH")
            local selectedMH = ResolveSelectedOwnedItem("oilMH", ownedMH)
            if selectedMH then
                ConfigureButtonClickAction(buttons.oilMH, "oilMH", selectedMH, not hasMHEnhancement)
            end
        end

        if ShouldShowOHButton(settings) then
            local ownedOH = GetOwnedItemsForButton("oilOH")
            local selectedOH = ResolveSelectedOwnedItem("oilOH", ownedOH)
            if selectedOH then
                ConfigureButtonClickAction(buttons.oilOH, "oilOH", selectedOH, not hasOHEnhancement)
            end
        end
    else
        HideConsumablePicker()
    end

    -- Position visible buttons (above the close button)
    if not InCombatLockdown() then
        local xOffset = 0
        local buttonSize = ConsumablesFrame.buttonSize or DEFAULT_BUTTON_SIZE
        local buttonY = CLOSE_BUTTON_HEIGHT  -- buttons sit above close button

        if settings.consumableFood ~= false then
            buttons.food:ClearAllPoints()
            buttons.food:SetPoint("BOTTOMLEFT", ConsumablesFrame, "BOTTOMLEFT", xOffset, buttonY)
            buttons.food:Show()
            xOffset = xOffset + buttonSize + BUTTON_SPACING
            visibleCount = visibleCount + 1
        end
        if settings.consumableFlask ~= false then
            buttons.flask:ClearAllPoints()
            buttons.flask:SetPoint("BOTTOMLEFT", ConsumablesFrame, "BOTTOMLEFT", xOffset, buttonY)
            buttons.flask:Show()
            xOffset = xOffset + buttonSize + BUTTON_SPACING
            visibleCount = visibleCount + 1
        end
        if settings.consumableOilMH ~= false then
            buttons.oilMH:ClearAllPoints()
            buttons.oilMH:SetPoint("BOTTOMLEFT", ConsumablesFrame, "BOTTOMLEFT", xOffset, buttonY)
            buttons.oilMH:Show()
            xOffset = xOffset + buttonSize + BUTTON_SPACING
            visibleCount = visibleCount + 1
        end
        if settings.consumableRune ~= false then
            buttons.rune:ClearAllPoints()
            buttons.rune:SetPoint("BOTTOMLEFT", ConsumablesFrame, "BOTTOMLEFT", xOffset, buttonY)
            buttons.rune:Show()
            xOffset = xOffset + buttonSize + BUTTON_SPACING
            visibleCount = visibleCount + 1
        end
        if settings.consumableHealthstone ~= false and HasWarlockInGroup() then
            buttons.healthstone:ClearAllPoints()
            buttons.healthstone:SetPoint("BOTTOMLEFT", ConsumablesFrame, "BOTTOMLEFT", xOffset, buttonY)
            buttons.healthstone:Show()
            xOffset = xOffset + buttonSize + BUTTON_SPACING
            visibleCount = visibleCount + 1
        end
        if ShouldShowOHButton(settings) then
            buttons.oilOH:ClearAllPoints()
            buttons.oilOH:SetPoint("BOTTOMLEFT", ConsumablesFrame, "BOTTOMLEFT", xOffset, buttonY)
            buttons.oilOH:Show()
            xOffset = xOffset + buttonSize + BUTTON_SPACING
            visibleCount = visibleCount + 1
        end

        local frameWidth = visibleCount > 0
            and (visibleCount * buttonSize + (visibleCount - 1) * BUTTON_SPACING)
            or buttonSize
        ConsumablesFrame:SetSize(frameWidth, buttonSize + CLOSE_BUTTON_HEIGHT)
    end
end

---------------------------------------------------------------------------
-- WEAPON ENCHANT POLLING
---------------------------------------------------------------------------

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

ConsumablesFrame:SetScript("OnEvent", function(self, event, unit)
    if event == "UNIT_AURA" and unit == "player" then
        UpdateConsumables()
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

---------------------------------------------------------------------------
-- POSITIONING (frameAnchoring handles position via layout mode)
---------------------------------------------------------------------------

local function PositionConsumablesFrame()
    if not InCombatLockdown() then
        ConsumablesFrame:SetScale(GetConsumableScale())
    end
    ConsumablesFrame:SetParent(UIParent)
    ConsumablesFrame:SetFrameStrata("DIALOG")
    -- Skip repositioning when layout mode owns the frame (avoids fighting the handle system)
    local anchoring = ns.QUI_Anchoring
    if anchoring and anchoring.layoutOwnedFrames and anchoring.layoutOwnedFrames[ConsumablesFrame] then
        return
    end
    -- Default position; frameAnchoring overrides if the user has positioned in layout mode
    ConsumablesFrame:ClearAllPoints()
    ConsumablesFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 100)
    if _G.QUI_ApplyAllFrameAnchors then
        _G.QUI_ApplyAllFrameAnchors()
    end
end

---------------------------------------------------------------------------
-- INSTANCE & BUFF CHECK HELPERS
---------------------------------------------------------------------------

local function IsInDungeonInstance()
    local _, instanceType = IsInInstance()
    return instanceType == "party"
end

local function IsInRaidInstance()
    local _, instanceType = IsInInstance()
    return instanceType == "raid"
end

local function HasMissingBuffs()
    local settings = GetSettings()
    if not settings then return false end
    local buffs = ScanPlayerBuffs()
    if settings.consumableFood ~= false and not buffs.hasFood then return true end
    if settings.consumableFlask ~= false and not buffs.hasFlask then return true end
    if settings.consumableRune ~= false and not buffs.hasRune then return true end

    -- Weapon enhancement check (class-aware)
    local hasMainHandEnchant, _, _, _, hasOffHandEnchant = GetWeaponEnchantInfo()
    if settings.consumableOilMH ~= false then
        local mhConfig = GetEnhancementConfig("MH")
        if mhConfig and mhConfig.checkType == "playerAura" then
            if not buffs.hasWeaponMH then return true end
        else
            if not hasMainHandEnchant then return true end
        end
    end
    if ShouldShowOHButton(settings) then
        local ohConfig = GetEnhancementConfig("OH")
        if ohConfig and ohConfig.checkType == "playerAura" then
            if not buffs.hasWeaponOH then return true end
        else
            if not hasOffHandEnchant then return true end
        end
    end

    if settings.consumableHealthstone ~= false and HasWarlockInGroup() then
        local hsCount = (C_Item.GetItemCount(5512, false, true) or 0) + (C_Item.GetItemCount(224464, false, true) or 0)
        if hsCount == 0 then return true end
    end
    return false
end

---------------------------------------------------------------------------
-- SHOW / TRIGGER LOGIC
---------------------------------------------------------------------------

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
        if HasMissingBuffs() then ShowConsumablesStandalone() end
        return
    end
    if settings.consumableOnRaid and IsInRaidInstance() then
        if HasMissingBuffs() then ShowConsumablesStandalone() end
        return
    end
end

local function OnResurrect()
    local settings = GetSettings()
    if not settings or settings.consumableCheckEnabled == false then return end
    if not settings.consumableOnResurrect then return end
    if InCombatLockdown() then return end
    if not ns.Utils.IsInInstancedContent() then return end
    if HasMissingBuffs() then ShowConsumablesStandalone() end
end

---------------------------------------------------------------------------
-- EXPIRATION WARNING
---------------------------------------------------------------------------

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
    -- Weapon enhancement expiration (class-aware)
    if settings.consumableOilMH ~= false then
        local mhConfig = GetEnhancementConfig("MH")
        if mhConfig and mhConfig.checkType == "playerAura" then
            -- Aura-based (rogues): check aura expiration
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

---------------------------------------------------------------------------
-- EVENT HANDLING
---------------------------------------------------------------------------

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
    end
end)

-- Combat lockdown: hide clickable buttons, restore after combat
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
    elseif event == "PLAYER_REGEN_ENABLED" then
        if hideConsumablesAfterCombat then
            return
        end
        UpdateConsumables()
    end
end)

-- Zone change: restart expiration monitoring
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

---------------------------------------------------------------------------
-- GLOBAL API
---------------------------------------------------------------------------

_G.QUI_RefreshConsumables = function()
    if ConsumablesFrame:IsShown() then
        local point, relativeTo, relativePoint, x, y = ConsumablesFrame:GetPoint()
        InitializeButtons()
        UpdateConsumables()
        ConsumablesFrame:SetScale(GetConsumableScale())
        ConsumablesFrame:ClearAllPoints()
        ConsumablesFrame:SetPoint(point, relativeTo, relativePoint, x, y)
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
end
