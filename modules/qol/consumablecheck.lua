local addonName, ns = ...
local Helpers = ns.Helpers

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

---------------------------------------------------------------------------
-- BUFF / ITEM DATA
---------------------------------------------------------------------------

local FOOD_BUFFS = {
    -- TWW Food (Well Fed buffs)
    [462210] = true, [462212] = true, [462213] = true, [462214] = true,
    [462215] = true, [462216] = true, [462217] = true, [462218] = true,
    [462270] = true, [462271] = true, [462272] = true, [462273] = true,
    -- Dragonflight food (still valid)
    [382145] = true, [382146] = true, [382149] = true, [382150] = true,
    [382152] = true, [382153] = true, [382154] = true, [382155] = true,
    [382156] = true, [382157] = true, [382246] = true, [382247] = true,
    [396092] = true,
}

local FLASK_BUFFS = {
    -- Midnight Flasks
    [1235057] = true, [1235108] = true, [1235110] = true, [1235111] = true,
    -- TWW Flasks
    [432021] = true, [432473] = true, [431971] = true, [431972] = true,
    [431973] = true, [431974] = true,
    -- Dragonflight Flasks
    [371339] = true, [374000] = true, [371354] = true, [371204] = true,
    [370662] = true, [373257] = true, [371386] = true, [370652] = true,
    [371172] = true, [371186] = true,
}

local RUNE_BUFFS = {
    [453250] = true,   -- Crystallized Augment Rune (TWW)
    [393438] = true,   -- Draconic Augment Rune (DF)
    [367405] = true,   -- Eternal Augment Rune
    [347901] = true,   -- Veiled Augment Rune
    [270058] = true,   -- Battle-Scarred Augment Rune
    [317065] = true,   -- Lightless Force (SL)
    [1234969] = true,  -- Midnight Augment Rune
    [1242347] = true,  -- Greater Midnight Augment Rune
}

local FLASK_ITEMS = {
    241320, 241322, 241324, 241326,  -- Midnight Flasks
    212283, 212284, 212285, 212286, 212287, 212288,  -- TWW Flasks
    191318, 191319, 191320, 191321, 191322, 191323, 191324, 191325, 191326, 191327,  -- DF Flasks
}

local RUNE_ITEMS = {
    224572,  -- Crystallized Augment Rune (TWW)
    201325,  -- Draconic Augment Rune (DF)
    190384,  -- Eternal Augment Rune
}

local OIL_ITEMS = {
    -- TWW Oils
    222502, 222503, 222504,
    222508, 222509, 222510,
    222888, 222889, 222890, 222891, 222892, 222893, 222894, 222895, 222896,
    -- TWW Stones
    219906, 219907, 219908,
    219909, 219910, 219911,
    219912, 219913, 219914,
    224105, 224106, 224107,
    224108, 224109, 224110,
    224111, 224112, 224113,
    -- DF Oils
    191933, 191939, 191940,
    191943, 191944, 191945,
    191948, 191949, 191950,
}

local WEAPON_ENCHANTS = {
    -- TWW Bubbling Wax
    [7549] = { icon = 3622199, item = 222508 },
    [7550] = { icon = 3622199, item = 222509 },
    [7551] = { icon = 3622199, item = 222510 },
    -- TWW Algari Mana Oil
    [7529] = { icon = 4549251, item = 222888 },
    [7530] = { icon = 4549251, item = 222889 },
    [7531] = { icon = 4549251, item = 222890 },
    [7532] = { icon = 4549251, item = 222891 },
    [7533] = { icon = 4549251, item = 222892 },
    [7534] = { icon = 4549251, item = 222893 },
    [7535] = { icon = 4549251, item = 222894 },
    [7536] = { icon = 4549251, item = 222895 },
    [7537] = { icon = 4549251, item = 222896 },
    -- TWW Oil of Beledar's Grace
    [7543] = { icon = 3622195, item = 222502 },
    [7544] = { icon = 3622195, item = 222503 },
    [7545] = { icon = 3622195, item = 222504 },
    -- TWW Ironclaw Whetstone
    [7599] = { icon = 5975854, item = 219906 },
    [7600] = { icon = 5975854, item = 219907 },
    [7601] = { icon = 5975854, item = 219908 },
    -- TWW Ironclaw Weightstone
    [7596] = { icon = 5975933, item = 219909 },
    [7597] = { icon = 5975933, item = 219910 },
    [7598] = { icon = 5975933, item = 219911 },
    -- TWW Ironclaw Razorstone
    [7593] = { icon = 5975753, item = 219912 },
    [7594] = { icon = 5975753, item = 219913 },
    [7595] = { icon = 5975753, item = 219914 },
    -- TWW Oils (older IDs)
    [7500] = { icon = 609896, item = 224108 },
    [7501] = { icon = 609896, item = 224109 },
    [7502] = { icon = 609896, item = 224110 },
    [7496] = { icon = 609897, item = 224105 },
    [7497] = { icon = 609897, item = 224106 },
    [7498] = { icon = 609897, item = 224107 },
    [7493] = { icon = 609892, item = 224111 },
    [7494] = { icon = 609892, item = 224112 },
    [7495] = { icon = 609892, item = 224113 },
    -- DF Primal Whetstone
    [6379] = { icon = 4622275, item = 191933 },
    [6380] = { icon = 4622275, item = 191939 },
    [6381] = { icon = 4622275, item = 191940 },
    -- DF Primal Weightstone
    [6696] = { icon = 4622279, item = 191943 },
    [6697] = { icon = 4622279, item = 191944 },
    [6698] = { icon = 4622279, item = 191945 },
    -- DF Primal Razorstone
    [6382] = { icon = 4622274, item = 191948 },
    [6383] = { icon = 4622274, item = 191949 },
    [6384] = { icon = 4622274, item = 191950 },
}

---------------------------------------------------------------------------
-- UTILITY FUNCTIONS
---------------------------------------------------------------------------

local function GetSettings()
    return Helpers.GetModuleDB("general")
end

local function GetButtonSize()
    local settings = GetSettings()
    return (settings and settings.consumableIconSize) or DEFAULT_BUTTON_SIZE
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

local function IsDualWielding()
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

local function ScanPlayerBuffs()
    local result = {
        hasFood = false, hasFlask = false, hasRune = false,
        foodData = nil, flaskData = nil, runeData = nil,
    }
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
        if result.hasFood and result.hasFlask and result.hasRune then break end
    end
    return result
end

---------------------------------------------------------------------------
-- CONSUMABLES FRAME
---------------------------------------------------------------------------

local ConsumablesFrame = CreateFrame("Frame", "QUI_ConsumablesFrame", UIParent)
ConsumablesFrame:SetSize(DEFAULT_BUTTON_SIZE * 6 + BUTTON_SPACING * 5, DEFAULT_BUTTON_SIZE)
ConsumablesFrame:Hide()
ConsumablesFrame.buttons = {}

-- Close button
local closeButton = CreateFrame("Button", nil, ConsumablesFrame)
closeButton:SetSize(DEFAULT_BUTTON_SIZE * 4, 18)
closeButton:SetPoint("TOP", ConsumablesFrame, "BOTTOM", 0, 0)

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
closeButton:SetScript("OnClick", function() ConsumablesFrame:Hide() end)
ConsumablesFrame.closeButton = closeButton

---------------------------------------------------------------------------
-- BUTTON CREATION
---------------------------------------------------------------------------

local function CreateConsumableButton(parent, index, buttonType, iconID, isClickable, buttonSize)
    local button = CreateFrame("Frame", nil, parent)
    button:SetSize(buttonSize, buttonSize)
    button.buttonType = buttonType

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
        button.click:RegisterForClicks("AnyUp")
        button.click:Hide()
        if buttonType == "oilMH" then
            button.click:SetAttribute("type", "item")
            button.click:SetAttribute("target-slot", INVSLOT_MAINHAND)
        elseif buttonType == "oilOH" then
            button.click:SetAttribute("type", "item")
            button.click:SetAttribute("target-slot", INVSLOT_OFFHAND)
        else
            button.click:SetAttribute("type", "item")
        end
        button.click:SetScript("OnEnter", function() button:SetAlpha(0.7) end)
        button.click:SetScript("OnLeave", function() button:SetAlpha(1) end)
    end

    return button
end

local function StartButtonGlow(button)
    if LCG and button then
        LCG.PixelGlow_Start(button, {1, 0.8, 0, 1}, 8, 0.25, nil, 2, 0, 0, false, "_QUIConsumable")
    end
end

local function StopButtonGlow(button)
    if LCG and button then
        LCG.PixelGlow_Stop(button, "_QUIConsumable")
    end
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

    local buttonDefs = {
        { "food", 136000, false },
        { "flask", 3566840, true },
        { "oilMH", 609892, true },
        { "rune", 4549102, true },
        { "healthstone", 538745, false },
        { "oilOH", 609892, true },
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
-- UPDATE CONSUMABLE STATUS
---------------------------------------------------------------------------

local function UpdateConsumables()
    local settings = GetSettings()
    if not settings then return end

    local buttons = ConsumablesFrame.buttons
    local now = GetTime()
    local visibleCount = 0

    -- Reset all buttons
    for _, button in pairs(buttons) do
        if type(button) == "table" and button.icon then
            button.status:SetTexture("Interface\\RaidFrame\\ReadyCheck-NotReady")
            button.icon:SetDesaturated(true)
            button.timeText:SetText("")
            button.countText:SetText("")
            if not InCombatLockdown() then
                button:Hide()
                if button.click then button.click:Hide() end
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

    -- Weapon enchant check (Main Hand)
    local hasMainHandEnchant, mainHandExpiration, _, mainHandEnchantID, hasOffHandEnchant, offHandExpiration, _, offHandEnchantID = GetWeaponEnchantInfo()
    if settings.consumableOilMH ~= false then
        if hasMainHandEnchant then
            buttons.oilMH.status:SetTexture("Interface\\RaidFrame\\ReadyCheck-Ready")
            buttons.oilMH.icon:SetDesaturated(false)
            if mainHandEnchantID and WEAPON_ENCHANTS[mainHandEnchantID] then
                local enchantData = WEAPON_ENCHANTS[mainHandEnchantID]
                buttons.oilMH.icon:SetTexture(enchantData.icon)
                SaveLastWeaponEnchant(INVSLOT_MAINHAND, mainHandEnchantID, enchantData.icon, enchantData.item)
            end
            if mainHandExpiration and mainHandExpiration > 0 then
                buttons.oilMH.timeText:SetText(FormatTimeRemaining(mainHandExpiration / 1000))
            end
        else
            local lastEnchant = GetLastWeaponEnchant(INVSLOT_MAINHAND)
            if lastEnchant and lastEnchant.icon then buttons.oilMH.icon:SetTexture(lastEnchant.icon) end
        end
    end

    -- Weapon enchant check (Off Hand)
    if settings.consumableOilOH ~= false and IsDualWielding() then
        if hasOffHandEnchant then
            buttons.oilOH.status:SetTexture("Interface\\RaidFrame\\ReadyCheck-Ready")
            buttons.oilOH.icon:SetDesaturated(false)
            if offHandEnchantID and WEAPON_ENCHANTS[offHandEnchantID] then
                local enchantData = WEAPON_ENCHANTS[offHandEnchantID]
                buttons.oilOH.icon:SetTexture(enchantData.icon)
                SaveLastWeaponEnchant(INVSLOT_OFFHAND, offHandEnchantID, enchantData.icon, enchantData.item)
            end
            if offHandExpiration and offHandExpiration > 0 then
                buttons.oilOH.timeText:SetText(FormatTimeRemaining(offHandExpiration / 1000))
            end
        else
            local lastEnchant = GetLastWeaponEnchant(INVSLOT_OFFHAND)
            if lastEnchant and lastEnchant.icon then buttons.oilOH.icon:SetTexture(lastEnchant.icon) end
        end
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

    -- Clickable flask button
    local hasFlask = buttons.flask.icon:IsDesaturated() == false
    if not hasFlask and settings.consumableFlask ~= false and not InCombatLockdown() then
        for _, itemID in ipairs(FLASK_ITEMS) do
            local count = C_Item.GetItemCount(itemID, false, false)
            if count and count > 0 then
                local itemName = C_Item.GetItemInfo(itemID)
                if itemName and buttons.flask.click then
                    buttons.flask.click:SetAttribute("type", "macro")
                    buttons.flask.click:SetAttribute("macrotext", "/use " .. itemName)
                    buttons.flask.click:Show()
                    buttons.flask.countText:SetText(tostring(count))
                    local texture = select(5, C_Item.GetItemInfoInstant(itemID))
                    if texture then buttons.flask.icon:SetTexture(texture) end
                    StartButtonGlow(buttons.flask)
                end
                break
            end
        end
    end

    -- Clickable rune button
    local hasRune = buttons.rune.icon:IsDesaturated() == false
    if not hasRune and settings.consumableRune ~= false and not InCombatLockdown() then
        for _, itemID in ipairs(RUNE_ITEMS) do
            local count = C_Item.GetItemCount(itemID, false, false)
            if count and count > 0 then
                local itemName = C_Item.GetItemInfo(itemID)
                if itemName and buttons.rune.click then
                    buttons.rune.click:SetAttribute("type", "macro")
                    buttons.rune.click:SetAttribute("macrotext", "/use " .. itemName)
                    buttons.rune.click:Show()
                    buttons.rune.countText:SetText(tostring(count))
                    local texture = select(5, C_Item.GetItemInfoInstant(itemID))
                    if texture then buttons.rune.icon:SetTexture(texture) end
                    StartButtonGlow(buttons.rune)
                end
                break
            end
        end
    end

    -- Clickable oil button (Main Hand)
    if not hasMainHandEnchant and settings.consumableOilMH ~= false and not InCombatLockdown() then
        local lastEnchant = GetLastWeaponEnchant(INVSLOT_MAINHAND)
        local oilItemID = lastEnchant and lastEnchant.item
        local oilCount = oilItemID and C_Item.GetItemCount(oilItemID, false, false) or 0
        if not oilItemID or oilCount == 0 then
            for _, itemID in ipairs(OIL_ITEMS) do
                local count = C_Item.GetItemCount(itemID, false, false)
                if count and count > 0 then
                    oilItemID = itemID; oilCount = count; break
                end
            end
        end
        if oilItemID and oilCount > 0 and buttons.oilMH.click then
            local itemName = C_Item.GetItemInfo(oilItemID)
            if itemName then
                buttons.oilMH.click:SetAttribute("item", itemName)
                buttons.oilMH.click:Show()
                buttons.oilMH.countText:SetText(tostring(oilCount))
                local texture = select(5, C_Item.GetItemInfoInstant(oilItemID))
                if texture then buttons.oilMH.icon:SetTexture(texture) end
                StartButtonGlow(buttons.oilMH)
            end
        end
    end

    -- Clickable oil button (Off Hand)
    if not hasOffHandEnchant and settings.consumableOilOH ~= false and IsDualWielding() and not InCombatLockdown() then
        local lastEnchant = GetLastWeaponEnchant(INVSLOT_OFFHAND)
        local oilItemID = lastEnchant and lastEnchant.item
        local oilCount = oilItemID and C_Item.GetItemCount(oilItemID, false, false) or 0
        if not oilItemID or oilCount == 0 then
            for _, itemID in ipairs(OIL_ITEMS) do
                local count = C_Item.GetItemCount(itemID, false, false)
                if count and count > 0 then
                    oilItemID = itemID; oilCount = count; break
                end
            end
        end
        if oilItemID and oilCount > 0 and buttons.oilOH.click then
            local itemName = C_Item.GetItemInfo(oilItemID)
            if itemName then
                buttons.oilOH.click:SetAttribute("item", itemName)
                buttons.oilOH.click:Show()
                buttons.oilOH.countText:SetText(tostring(oilCount))
                local texture = select(5, C_Item.GetItemInfoInstant(oilItemID))
                if texture then buttons.oilOH.icon:SetTexture(texture) end
                StartButtonGlow(buttons.oilOH)
            end
        end
    end

    -- Position visible buttons
    if not InCombatLockdown() then
        local xOffset = 0
        local buttonSize = ConsumablesFrame.buttonSize or DEFAULT_BUTTON_SIZE

        if settings.consumableFood ~= false then
            buttons.food:ClearAllPoints()
            buttons.food:SetPoint("LEFT", ConsumablesFrame, "LEFT", xOffset, 0)
            buttons.food:Show()
            xOffset = xOffset + buttonSize + BUTTON_SPACING
            visibleCount = visibleCount + 1
        end
        if settings.consumableFlask ~= false then
            buttons.flask:ClearAllPoints()
            buttons.flask:SetPoint("LEFT", ConsumablesFrame, "LEFT", xOffset, 0)
            buttons.flask:Show()
            xOffset = xOffset + buttonSize + BUTTON_SPACING
            visibleCount = visibleCount + 1
        end
        if settings.consumableOilMH ~= false then
            buttons.oilMH:ClearAllPoints()
            buttons.oilMH:SetPoint("LEFT", ConsumablesFrame, "LEFT", xOffset, 0)
            buttons.oilMH:Show()
            xOffset = xOffset + buttonSize + BUTTON_SPACING
            visibleCount = visibleCount + 1
        end
        if settings.consumableRune ~= false then
            buttons.rune:ClearAllPoints()
            buttons.rune:SetPoint("LEFT", ConsumablesFrame, "LEFT", xOffset, 0)
            buttons.rune:Show()
            xOffset = xOffset + buttonSize + BUTTON_SPACING
            visibleCount = visibleCount + 1
        end
        if settings.consumableHealthstone ~= false and HasWarlockInGroup() then
            buttons.healthstone:ClearAllPoints()
            buttons.healthstone:SetPoint("LEFT", ConsumablesFrame, "LEFT", xOffset, 0)
            buttons.healthstone:Show()
            xOffset = xOffset + buttonSize + BUTTON_SPACING
            visibleCount = visibleCount + 1
        end
        if settings.consumableOilOH ~= false and IsDualWielding() then
            buttons.oilOH:ClearAllPoints()
            buttons.oilOH:SetPoint("LEFT", ConsumablesFrame, "LEFT", xOffset, 0)
            buttons.oilOH:Show()
            xOffset = xOffset + buttonSize + BUTTON_SPACING
            visibleCount = visibleCount + 1
        end

        local frameWidth = visibleCount > 0
            and (visibleCount * buttonSize + (visibleCount - 1) * BUTTON_SPACING)
            or buttonSize
        ConsumablesFrame:SetSize(frameWidth, buttonSize)
        if ConsumablesFrame.closeButton then
            ConsumablesFrame.closeButton:SetWidth(frameWidth)
        end
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
    self:UnregisterEvent("UNIT_AURA")
    if weaponEnchantTicker then
        weaponEnchantTicker:Cancel()
        weaponEnchantTicker = nil
    end
end)

---------------------------------------------------------------------------
-- POSITIONING & MOVER
---------------------------------------------------------------------------

local CLOSE_BUTTON_HEIGHT = 18

local MoverFrame = CreateFrame("Frame", "QUI_ConsumablesMover", UIParent, "BackdropTemplate")
MoverFrame:SetSize(200, 60)
MoverFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 100)
MoverFrame:SetFrameStrata("DIALOG")
MoverFrame:SetMovable(true)
MoverFrame:EnableMouse(true)
MoverFrame:RegisterForDrag("LeftButton")
MoverFrame:SetClampedToScreen(true)
MoverFrame:Hide()

MoverFrame:SetBackdrop({
    bgFile = "Interface\\Buttons\\WHITE8x8",
    edgeFile = "Interface\\Buttons\\WHITE8x8",
    edgeSize = 1,
})
MoverFrame:SetBackdropColor(0.1, 0.1, 0.1, 0.8)
MoverFrame:SetBackdropBorderColor(0.4, 0.8, 1.0, 1)

MoverFrame.text = MoverFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
MoverFrame.text:SetPoint("CENTER")
MoverFrame.text:SetText("Consumables Check\nDrag to position")
MoverFrame.text:SetTextColor(0.4, 0.8, 1.0, 1)

MoverFrame.closeBtn = CreateFrame("Button", nil, MoverFrame)
MoverFrame.closeBtn:SetSize(16, 16)
MoverFrame.closeBtn:SetPoint("TOPRIGHT", -2, -2)
MoverFrame.closeBtn:SetNormalTexture("Interface\\Buttons\\UI-StopButton")
MoverFrame.closeBtn:SetScript("OnClick", function() MoverFrame:Hide() end)

MoverFrame:SetScript("OnDragStart", function(self) self:StartMoving() end)
MoverFrame:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local settings = GetSettings()
    if settings then
        local point, _, relativePoint, x, y = self:GetPoint()
        settings.consumableFreePosition = { point = point, relativePoint = relativePoint, x = x, y = y }
    end
end)

local function ToggleMover()
    if MoverFrame:IsShown() then
        MoverFrame:Hide()
    else
        local settings = GetSettings()
        if settings and settings.consumableFreePosition then
            local pos = settings.consumableFreePosition
            MoverFrame:ClearAllPoints()
            MoverFrame:SetPoint(pos.point, UIParent, pos.relativePoint, pos.x, pos.y)
        end
        MoverFrame:Show()
    end
end

local function PositionConsumablesFrame()
    ConsumablesFrame:ClearAllPoints()
    local settings = GetSettings()
    local anchorMode = settings and settings.consumableAnchorMode ~= false

    if anchorMode then
        local userOffset = (settings and settings.consumableIconOffset) or 5
        local totalOffset = userOffset + CLOSE_BUTTON_HEIGHT + 2
        if ReadyCheckFrame then
            ConsumablesFrame:SetPoint("BOTTOM", ReadyCheckFrame, "TOP", 0, totalOffset)
            ConsumablesFrame:SetParent(ReadyCheckFrame)
            ConsumablesFrame:SetFrameStrata("DIALOG")
        else
            ConsumablesFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 100)
            ConsumablesFrame:SetParent(UIParent)
        end
    else
        ConsumablesFrame:SetParent(UIParent)
        ConsumablesFrame:SetFrameStrata("DIALOG")
        if settings and settings.consumableFreePosition then
            local pos = settings.consumableFreePosition
            ConsumablesFrame:SetPoint(pos.point, UIParent, pos.relativePoint, pos.x, pos.y)
        else
            ConsumablesFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 100)
        end
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
    local hasMainHandEnchant, _, _, _, hasOffHandEnchant = GetWeaponEnchantInfo()
    if settings.consumableOilMH ~= false and not hasMainHandEnchant then return true end
    if settings.consumableOilOH ~= false and IsDualWielding() and not hasOffHandEnchant then return true end
    if settings.consumableHealthstone ~= false and HasWarlockInGroup() then
        local hsCount = C_Item.GetItemCount(5512, false, true) + C_Item.GetItemCount(224464, false, true)
        if hsCount == 0 then return true end
    end
    return false
end

---------------------------------------------------------------------------
-- SHOW / TRIGGER LOGIC
---------------------------------------------------------------------------

local function ShowConsumablesStandalone()
    InitializeButtons()
    UpdateConsumables()

    local settings = GetSettings()
    local anchorMode = settings and settings.consumableAnchorMode ~= false

    ConsumablesFrame:ClearAllPoints()
    ConsumablesFrame:SetParent(UIParent)
    ConsumablesFrame:SetFrameStrata("DIALOG")

    if not anchorMode and settings and settings.consumableFreePosition then
        local pos = settings.consumableFreePosition
        ConsumablesFrame:SetPoint(pos.point, UIParent, pos.relativePoint, pos.x, pos.y)
    else
        local userOffset = (settings and settings.consumableIconOffset) or 5
        local totalOffset = userOffset + CLOSE_BUTTON_HEIGHT + 2
        local savedPos = settings and settings.readyCheckPosition
        if savedPos then
            local readyCheckHalfHeight = 55
            ConsumablesFrame:SetPoint("BOTTOM", UIParent, savedPos.relativePoint, savedPos.x, savedPos.y + readyCheckHalfHeight + totalOffset)
        else
            ConsumablesFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 100)
        end
    end

    ConsumablesFrame:Show()
end

local function OnReadyCheck(starter, timer)
    local settings = GetSettings()
    if not settings or settings.consumableCheckEnabled == false then return end
    if settings.consumableOnReadyCheck == false then return end

    PositionConsumablesFrame()
    UpdateConsumables()
    ConsumablesFrame:Show()
end

local function OnReadyCheckFinished()
    ConsumablesFrame:Hide()
    if not InCombatLockdown() then
        for _, button in pairs(ConsumablesFrame.buttons) do
            if type(button) == "table" and button.click then button.click:Hide() end
        end
    end
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
    if settings.consumableOilMH ~= false then
        local hasMainHandEnchant, mainHandExpiration = GetWeaponEnchantInfo()
        if hasMainHandEnchant and mainHandExpiration then
            local remaining = mainHandExpiration / 1000
            if remaining > 0 and remaining <= threshold then
                table.insert(expiringBuffs, { type = "oilMH", remaining = remaining })
            end
        end
    end
    if settings.consumableOilOH ~= false and IsDualWielding() then
        local _, _, _, _, hasOffHandEnchant, offHandExpiration = GetWeaponEnchantInfo()
        if hasOffHandEnchant and offHandExpiration then
            local remaining = offHandExpiration / 1000
            if remaining > 0 and remaining <= threshold then
                table.insert(expiringBuffs, { type = "oilOH", remaining = remaining })
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
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("PLAYER_ALIVE")

eventFrame:SetScript("OnEvent", function(self, event, ...)
    if event == "PLAYER_LOGIN" then
        InitializeButtons()
    elseif event == "READY_CHECK" then
        OnReadyCheck(...)
    elseif event == "READY_CHECK_FINISHED" then
        OnReadyCheckFinished()
    elseif event == "PLAYER_ENTERING_WORLD" then
        C_Timer.After(1, OnInstanceEnter)
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
        for _, button in pairs(ConsumablesFrame.buttons) do
            if type(button) == "table" and button.click then
                button.click:Hide()
            end
        end
    elseif event == "PLAYER_REGEN_ENABLED" then
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
        ConsumablesFrame:ClearAllPoints()
        ConsumablesFrame:SetPoint(point, relativeTo, relativePoint, x, y)
    end
end

_G.QUI_RepositionConsumables = function()
    if ConsumablesFrame:IsShown() then
        InitializeButtons()
        UpdateConsumables()
        if ConsumablesFrame:GetParent() == ReadyCheckFrame then
            PositionConsumablesFrame()
        end
    end
end

_G.QUI_ToggleConsumablesMover = ToggleMover

_G.QUI_ShowConsumables = function() ShowConsumablesStandalone() end
_G.QUI_HideConsumables = function() ConsumablesFrame:Hide() end
