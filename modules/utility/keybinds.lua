local _, QUI = ...
local LSM = QUI.LSM

local function CJKFont(fs, p, s, f)
    if QUI.Helpers and QUI.Helpers.ApplyFontWithFallback then
        QUI.Helpers.ApplyFontWithFallback(fs, p, s, f)
    else
        fs:SetFont(p, s, f)
    end
end

local GetCore = QUI.Helpers.GetCore

local VIEWER_DB_KEY = {
    essential = "EssentialCooldownViewer",
    utility   = "UtilityCooldownViewer",
}
local VIEWER_RESOLVER_KEY = {
    EssentialCooldownViewer = "essential",
    UtilityCooldownViewer   = "utility",
    QUI_EssentialContainer  = "essential",
    QUI_UtilityContainer    = "utility",
}

local spellToKeybind = {}
local spellNameToKeybind = {}
local itemToKeybind = {}
local itemNameToKeybind = {}
local lastCacheUpdate = 0
local CACHE_UPDATE_INTERVAL = 1.0

local cachedActionButtons = {}
local actionButtonsCached = false

local function CompatGlobalName(...)
    return string.char(...)
end

local COMPAT_ACTION_PREFIX_A = CompatGlobalName(66, 84, 52, 66, 117, 116, 116, 111, 110)
local COMPAT_PET_PREFIX_A = CompatGlobalName(66, 84, 52, 80, 101, 116, 66, 117, 116, 116, 111, 110)
local COMPAT_STANCE_PREFIX_A = CompatGlobalName(66, 84, 52, 83, 116, 97, 110, 99, 101, 66, 117, 116, 116, 111, 110)
local COMPAT_ACTION_PREFIX_B = CompatGlobalName(68, 111, 109, 105, 110, 111, 115, 65, 99, 116, 105, 111, 110, 66, 117, 116, 116, 111, 110)
local COMPAT_BAR_PREFIX_C = CompatGlobalName(69, 108, 118, 85, 73, 95, 66, 97, 114)
local COMPAT_BAR_BUTTON_SUFFIX_C = "Button"

local macroNameToIndex = {}

local pendingRebuild = false

local rotationHelperEnabled = false
local currentRotationSpellID = nil
local currentRotationBaseSpellID = nil

local iconKeybindCache = {}

local function SetupDebugInstrumentation()
    local mp = QUI._memprobes or {}; QUI._memprobes = mp
    mp[#mp + 1] = { name = "KB_spellToKeybind",     tbl = spellToKeybind }
    mp[#mp + 1] = { name = "KB_spellNameToKeybind", tbl = spellNameToKeybind }
    mp[#mp + 1] = { name = "KB_itemToKeybind",      tbl = itemToKeybind }
    mp[#mp + 1] = { name = "KB_macroNameToIndex",   tbl = macroNameToIndex }
    mp[#mp + 1] = { name = "KB_iconKeybindCache",   tbl = iconKeybindCache }
end
if QUI.DebugRegister then
    QUI.DebugRegister(SetupDebugInstrumentation)
else
    SetupDebugInstrumentation()
end

local iconKeybindState = QUI.Helpers.CreateStateTable()
local hookedKeybindViewers = QUI.Helpers.CreateStateTable()

local function IsAnyKeybindFeatureEnabled()
    local core = GetCore()
    if not core or not core.db or not core.db.profile then return false end

    local viewers = core.db.profile.viewers
    if viewers then
        for _, settings in pairs(viewers) do
            if settings.showKeybinds or settings.showMacroNames or settings.showStackCounts then
                return true
            end
        end
    end

    local ncdm = core.db.profile.ncdm
    local ct = ncdm and ncdm.containers
    if ct then
        for _, settings in pairs(ct) do
            if type(settings) == "table" and settings.showKeybinds then
                return true
            end
        end
    end
    local trackerKeybinds = core.db.profile.customTrackers and core.db.profile.customTrackers.keybinds
    if trackerKeybinds and trackerKeybinds.showKeybinds then
        return true
    end
    return false
end

local Helpers = QUI.Helpers
local GetGeneralFont = Helpers.GetGeneralFont
local GetGeneralFontOutline = Helpers.GetGeneralFontOutline

local function GetViewerSettings(viewerName)
    local QUICore = _G.QUI and _G.QUI.QUICore
    if not QUICore or not QUICore.db or not QUICore.db.profile then return nil end
    local dbKey = VIEWER_DB_KEY[viewerName]
    if dbKey then
        local viewers = QUICore.db.profile.viewers
        return viewers and viewers[dbKey]
    end
    local ncdm = QUICore.db.profile.ncdm
    local container = ncdm and ncdm.containers and ncdm.containers[viewerName]
    if type(container) == "table"
       and (container.keybindContext == "customTrackers" or container.containerType == "customBar")
    then
        local ct = QUICore.db.profile.customTrackers
        return ct and ct.keybinds or container
    end
    return container
end

local function GetViewerKeybindContext(viewerName)
    local QUICore = _G.QUI and _G.QUI.QUICore
    local profile = QUICore and QUICore.db and QUICore.db.profile
    local ncdm = profile and profile.ncdm
    local container = ncdm and ncdm.containers and ncdm.containers[viewerName]
    if type(container) == "table"
       and (container.keybindContext == "customTrackers" or container.containerType == "customBar")
    then
        return "customTrackers"
    end
    return "cdm"
end

local function GetCurrentSpecID()
    return QUI.Helpers.GetCurrentSpecID() or 0
end

local function GetSharedOverrides()
    local QUICore = _G.QUI and _G.QUI.QUICore
    if not QUICore or not QUICore.db or not QUICore.db.char then return nil end

    local specID = GetCurrentSpecID()

    if not QUICore.db.char.keybindOverrides[specID] then
        QUICore.db.char.keybindOverrides[specID] = {}
    end

    return QUICore.db.char.keybindOverrides[specID]
end

local function GetOverrideKeybind(spellID, baseSpellID)
    local overrides = GetSharedOverrides()
    if not overrides then return nil end

    local isSecret = type(issecretvalue) == "function" and issecretvalue or nil

    if baseSpellID and not (isSecret and isSecret(baseSpellID)) and overrides[baseSpellID] ~= nil then
        return overrides[baseSpellID]
    end

    if spellID and not (isSecret and isSecret(spellID)) and overrides[spellID] ~= nil then
        return overrides[spellID]
    end

    return nil
end

local function GetOverrideKeybindForItem(itemID)
    if not itemID then return nil end
    if type(issecretvalue) == "function" and issecretvalue(itemID) then return nil end
    local overrides = GetSharedOverrides()
    if not overrides then return nil end

    local key = -tonumber(itemID)
    if overrides[key] ~= nil then
        return overrides[key]
    end

    return nil
end

local FormatKeybind = QUI.FormatKeybind

local BT4_BINDING_MAPPINGS = {
    [1] = "ACTIONBUTTON%d",
    [3] = "MULTIACTIONBAR3BUTTON%d",
    [4] = "MULTIACTIONBAR4BUTTON%d",
    [5] = "MULTIACTIONBAR2BUTTON%d",
    [6] = "MULTIACTIONBAR1BUTTON%d",
    [13] = "MULTIACTIONBAR5BUTTON%d",
    [14] = "MULTIACTIONBAR6BUTTON%d",
    [15] = "MULTIACTIONBAR7BUTTON%d",
}

local function GetBT4BindingName(buttonNum)
    local bar = math.ceil(buttonNum / 12)
    local buttonInBar = ((buttonNum - 1) % 12) + 1
    local template = BT4_BINDING_MAPPINGS[bar]
    if template then
        return string.format(template, buttonInBar)
    end
    return nil
end

local function GetBindingNameFromActionSlot(slot)
    if not slot or slot < 1 then return nil end
    if slot <= 12 then
        return "ACTIONBUTTON" .. slot
    elseif slot <= 24 then
        return "ACTIONBUTTON" .. (slot - 12)
    elseif slot <= 36 then
        return "MULTIACTIONBAR3BUTTON" .. (slot - 24)
    elseif slot <= 48 then
        return "MULTIACTIONBAR4BUTTON" .. (slot - 36)
    elseif slot <= 60 then
        return "MULTIACTIONBAR1BUTTON" .. (slot - 48)
    elseif slot <= 72 then
        return "MULTIACTIONBAR2BUTTON" .. (slot - 60)
    end
    return nil
end

local BAR_BUTTON_BINDINGS = {
    { "^QUI_Bar1Button(%d+)$", "ACTIONBUTTON" },
    { "^QUI_Bar2Button(%d+)$", "MULTIACTIONBAR1BUTTON" },
    { "^QUI_Bar3Button(%d+)$", "MULTIACTIONBAR2BUTTON" },
    { "^QUI_Bar4Button(%d+)$", "MULTIACTIONBAR3BUTTON" },
    { "^QUI_Bar5Button(%d+)$", "MULTIACTIONBAR4BUTTON" },
    { "^QUI_Bar6Button(%d+)$", "MULTIACTIONBAR5BUTTON" },
    { "^QUI_Bar7Button(%d+)$", "MULTIACTIONBAR6BUTTON" },
    { "^QUI_Bar8Button(%d+)$", "MULTIACTIONBAR7BUTTON" },
    { "ActionButton(%d+)$", "ACTIONBUTTON" },
    { "MultiBarBottomLeftButton(%d+)$", "MULTIACTIONBAR1BUTTON" },
    { "MultiBarBottomRightButton(%d+)$", "MULTIACTIONBAR2BUTTON" },
    { "MultiBarRightButton(%d+)$", "MULTIACTIONBAR3BUTTON" },
    { "MultiBarLeftButton(%d+)$", "MULTIACTIONBAR4BUTTON" },
}

local function GetKeybindFromActionButton(button, actionSlot)
    if not button then return nil end

    if button.HotKey then
        local ok, hotkeyText = pcall(function() return button.HotKey:GetText() end)
        if ok and hotkeyText and hotkeyText ~= "" and hotkeyText ~= RANGE_INDICATOR then
            return FormatKeybind(hotkeyText)
        end
    end

    if button.hotKey then
        local ok, hotkeyText = pcall(function() return button.hotKey:GetText() end)
        if ok and hotkeyText and hotkeyText ~= "" and hotkeyText ~= RANGE_INDICATOR then
            return FormatKeybind(hotkeyText)
        end
    end

    if button.GetHotkey then
        local ok, hotkey = pcall(function() return button:GetHotkey() end)
        if ok and hotkey and hotkey ~= "" then
            return FormatKeybind(hotkey)
        end
    end

    local buttonName = button:GetName()
    if buttonName then
        local key1 = GetBindingKey("CLICK " .. buttonName .. ":LeftButton")
        if key1 then
            return FormatKeybind(key1)
        end

        for i = 1, #BAR_BUTTON_BINDINGS do
            local entry = BAR_BUTTON_BINDINGS[i]
            local num = buttonName:match(entry[1])
            if num then
                key1 = GetBindingKey(entry[2] .. num)
                if key1 then return FormatKeybind(key1) end
                return nil
            end
        end

        if buttonName:match("^BT4Button(%d+)$") then
            local num = tonumber(buttonName:match("^BT4Button(%d+)$"))
            if num then
                key1 = GetBindingKey("CLICK " .. buttonName .. ":Keybind")
                if not key1 then
                    key1 = GetBindingKey("CLICK " .. buttonName .. ":LeftButton")
                end
                if not key1 then
                    local bindingName = GetBT4BindingName(num)
                    if bindingName then
                        key1 = GetBindingKey(bindingName)
                    end
                end
                if not key1 and actionSlot then
                    local bindingName = GetBindingNameFromActionSlot(actionSlot)
                    if bindingName then
                        key1 = GetBindingKey(bindingName)
                    end
                end
                if key1 then return FormatKeybind(key1) end
            end
        elseif buttonName:match("^BT4PetButton(%d+)$") then
            local num = buttonName:match("^BT4PetButton(%d+)$")
            if num then
                key1 = GetBindingKey("CLICK " .. buttonName .. ":LeftButton")
                if not key1 then
                    key1 = GetBindingKey("BONUSACTIONBUTTON" .. num)
                end
                if key1 then return FormatKeybind(key1) end
            end
        elseif buttonName:match("^BT4StanceButton(%d+)$") then
            local num = buttonName:match("^BT4StanceButton(%d+)$")
            if num then
                key1 = GetBindingKey("CLICK " .. buttonName .. ":LeftButton")
                if not key1 then
                    key1 = GetBindingKey("SHAPESHIFTBUTTON" .. num)
                end
                if key1 then return FormatKeybind(key1) end
            end
        end
    end

    return nil
end

local function TrimMacroToken(value)
    if not value then return nil end
    return value:match("^%s*(.-)%s*$")
end

local function CleanMacroCommandPayload(value)
    value = TrimMacroToken(value)
    if not value or value == "" then return nil end
    value = value:gsub("%[.-%]", "")
    value = value:match("^([^;/]+)") or value
    return TrimMacroToken(value)
end

local function StoreLowerName(tbl, value)
    if not value or value == "" or value == "?" then return end
    local ok, lower = pcall(function() return value:lower() end)
    if ok and lower and lower ~= "" then
        tbl[lower] = true
    end
end

local function StoreMacroItemID(itemIDs, itemNames, itemID)
    if not itemID then return end
    if type(issecretvalue) == "function" and issecretvalue(itemID) then return end
    itemIDs[itemID] = true
    if C_Item and C_Item.GetItemInfo then
        local ok, itemName = pcall(C_Item.GetItemInfo, itemID)
        if ok then
            StoreLowerName(itemNames, itemName)
        end
    end
end

local function StoreMacroItemToken(itemIDs, itemNames, value)
    value = CleanMacroCommandPayload(value)
    if not value or value == "" or value == "?" then return end

    local itemID = value:match("item:(%d+)")
    if itemID then
        StoreMacroItemID(itemIDs, itemNames, tonumber(itemID))
    end

    local linkedName = value:match("%[(.-)%]")
    if linkedName then
        StoreLowerName(itemNames, linkedName)
    end

    local numeric = tonumber(value)
    if numeric then
        StoreMacroItemID(itemIDs, itemNames, numeric)
        if numeric >= 1 and numeric <= 19 and GetInventoryItemID then
            local ok, equippedItemID = pcall(GetInventoryItemID, "player", numeric)
            if ok then
                StoreMacroItemID(itemIDs, itemNames, equippedItemID)
            end
        end
        return
    end

    if not itemID and not linkedName then
        StoreLowerName(itemNames, value)
        if C_Item and C_Item.GetItemInfo then
            local ok, itemName = pcall(C_Item.GetItemInfo, value)
            if ok then
                StoreLowerName(itemNames, itemName)
            end
        end
    end
end

local function ParseMacroForSpells(macroIndex)
    local spellIDs = {}
    local spellNames = {}
    local itemIDs = {}
    local itemNames = {}

    local _, _, body = GetMacroInfo(macroIndex)
    if not body then return spellIDs, spellNames, itemIDs, itemNames end

    local simpleSpell = GetMacroSpell(macroIndex)
    if simpleSpell then
        spellIDs[simpleSpell] = true
        local spellInfo = C_Spell.GetSpellInfo(simpleSpell)
        if spellInfo and spellInfo.name then
            spellNames[spellInfo.name:lower()] = true
        end
    end

    for line in body:gmatch("[^\r\n]+") do
        local lineLower = line:lower()

        if not lineLower:match("^%s*%-%-") then
            local spellName = nil
            local itemName = nil

            if lineLower:match("/cast") then
                local afterCast = line:match("/[cC][aA][sS][tT]%s*(.*)")
                if afterCast then
                    spellName = CleanMacroCommandPayload(afterCast)
                end
            end

            if not spellName or spellName == "" then
                if lineLower:match("/use") then
                    local afterUse = line:match("/[uU][sS][eE]%s*(.*)")
                    if afterUse then
                        spellName = CleanMacroCommandPayload(afterUse)
                        itemName = spellName
                    end
                end
            end

            if not spellName or spellName == "" then
                if lineLower:match("#showtooltip") then
                    spellName = line:match("#[sS][hH][oO][wW][tT][oO][oO][lL][tT][iI][pP]%s+(.+)")
                    if spellName then
                        spellName = CleanMacroCommandPayload(spellName)
                        itemName = spellName
                    end
                end
            end

            if spellName and spellName ~= "" and spellName ~= "?" then
                spellName = spellName:match("^([^;/]+)")
                if spellName then
                    spellName = spellName:match("^%s*(.-)%s*$")
                end

                if spellName and spellName ~= "" then
                    spellNames[spellName:lower()] = true

                    local spellInfo = C_Spell.GetSpellInfo(spellName)
                    if spellInfo and spellInfo.spellID then
                        spellIDs[spellInfo.spellID] = true
                    end
                end
            end

            if itemName and itemName ~= "" then
                StoreMacroItemToken(itemIDs, itemNames, itemName)
            end
        end
    end

    return spellIDs, spellNames, itemIDs, itemNames
end

local function ProcessActionButton(button)
    if not button then return end

    local buttonName = button:GetName()
    local action

    if buttonName and buttonName:match("^" .. COMPAT_ACTION_PREFIX_A) then
        action = button._state_action
        if not action and button.GetAction then
            local actionType, actionSlot = button:GetAction()
            if actionType == "action" then
                action = actionSlot
            end
        end
    else
        action = button.action or (button.GetAction and button:GetAction())
    end

    if not action or action == 0 then return end

    local actionType, id = GetActionInfo(action)
    local keybind = nil

    if actionType == "spell" and id then
        keybind = GetKeybindFromActionButton(button, action)
        if keybind then
            if not spellToKeybind[id] then
                spellToKeybind[id] = keybind
            end
            local spellInfo = C_Spell.GetSpellInfo(id)
            if spellInfo and spellInfo.name then
                local nameLower = spellInfo.name:lower()
                if not spellNameToKeybind[nameLower] then
                    spellNameToKeybind[nameLower] = keybind
                end
            end
        end
    elseif actionType == "item" and id then
        keybind = GetKeybindFromActionButton(button, action)
        if keybind then
            if not itemToKeybind[id] then
                itemToKeybind[id] = keybind
            end
            local itemName = C_Item.GetItemInfo(id)
            if itemName then
                local nameLower = itemName:lower()
                if not itemNameToKeybind[nameLower] then
                    itemNameToKeybind[nameLower] = keybind
                end
            end
        end
    elseif actionType == "macro" then
        keybind = GetKeybindFromActionButton(button, action)
        if not keybind then return end

        local macroName = id and GetMacroInfo(id)

        if macroName then
            local macroSpells, macroSpellNames, macroItems, macroItemNames = ParseMacroForSpells(id)

            for spellID in pairs(macroSpells) do
                if not spellToKeybind[spellID] then
                    spellToKeybind[spellID] = keybind
                end
            end
            for spellName in pairs(macroSpellNames) do
                if not spellNameToKeybind[spellName] then
                    spellNameToKeybind[spellName] = keybind
                end
            end
            for itemID in pairs(macroItems) do
                if not itemToKeybind[itemID] then
                    itemToKeybind[itemID] = keybind
                end
            end
            for itemName in pairs(macroItemNames) do
                if not itemNameToKeybind[itemName] then
                    itemNameToKeybind[itemName] = keybind
                end
            end
        else
            local actionText = GetActionText(action)

            if id and id > 0 then
                if not spellToKeybind[id] then
                    spellToKeybind[id] = keybind
                end
                local spellInfo = C_Spell.GetSpellInfo(id)
                if spellInfo and spellInfo.name then
                    local nameLower = spellInfo.name:lower()
                    if not spellNameToKeybind[nameLower] then
                        spellNameToKeybind[nameLower] = keybind
                    end
                end
            end

            if actionText and actionText ~= "" then
                local macroIndex = macroNameToIndex[actionText:lower()]
                if macroIndex then
                    local macroSpells, macroSpellNames, macroItems, macroItemNames = ParseMacroForSpells(macroIndex)
                    for spellID in pairs(macroSpells) do
                        if not spellToKeybind[spellID] then
                            spellToKeybind[spellID] = keybind
                        end
                    end
                    for spellName in pairs(macroSpellNames) do
                        if not spellNameToKeybind[spellName] then
                            spellNameToKeybind[spellName] = keybind
                        end
                    end
                    for itemID in pairs(macroItems) do
                        if not itemToKeybind[itemID] then
                            itemToKeybind[itemID] = keybind
                        end
                    end
                    for itemName in pairs(macroItemNames) do
                        if not itemNameToKeybind[itemName] then
                            itemNameToKeybind[itemName] = keybind
                        end
                    end
                end
            end
        end
    end
end

local function LooksLikeActionButton(frame)
    if frame.action then return true end
    return type(frame.GetAction) == "function"
end

local globalSweepButtons = {}
local globalSweepDone = false

local function RunGlobalActionButtonSweep()
    if globalSweepDone then return end
    globalSweepDone = true

    for globalName, frame in pairs(_G) do
        if type(globalName) == "string" and type(frame) == "table"
            and Helpers.CanAccessTable(frame) and Helpers.CanAccessValue(frame)
            and C_Widget.IsFrameWidget(frame) then
            local ok, isActionButton = QUI.SafeCall("best-effort-style", LooksLikeActionButton, frame)

            if ok and isActionButton then
                table.insert(globalSweepButtons, frame)
            end
        end
    end
end

local function BuildActionButtonCache()
    if actionButtonsCached then return end

    wipe(cachedActionButtons)

    RunGlobalActionButtonSweep()
    for _, btn in ipairs(globalSweepButtons) do
        table.insert(cachedActionButtons, btn)
    end

    local addedButtons = {}
    for _, btn in ipairs(cachedActionButtons) do
        addedButtons[btn] = true
    end

    local buttonPrefixes = {
        "QUI_Bar1Button",
        "QUI_Bar2Button",
        "QUI_Bar3Button",
        "QUI_Bar4Button",
        "QUI_Bar5Button",
        "QUI_Bar6Button",
        "QUI_Bar7Button",
        "QUI_Bar8Button",
        "ActionButton",
        "MultiBarBottomLeftButton",
        "MultiBarBottomRightButton",
        "MultiBarRightButton",
        "MultiBarLeftButton",
        "MultiBar5Button",
        "MultiBar6Button",
        "MultiBar7Button",
        "MultiBarBottomLeftActionButton",
        "MultiBarBottomRightActionButton",
        "MultiBarRightActionButton",
        "MultiBarLeftActionButton",
        "MultiBar5ActionButton",
        "MultiBar6ActionButton",
        "MultiBar7ActionButton",
        "OverrideActionBarButton",
        COMPAT_ACTION_PREFIX_A,
        COMPAT_ACTION_PREFIX_B,
        COMPAT_BAR_PREFIX_C .. "1" .. COMPAT_BAR_BUTTON_SUFFIX_C,
        COMPAT_BAR_PREFIX_C .. "2" .. COMPAT_BAR_BUTTON_SUFFIX_C,
        COMPAT_BAR_PREFIX_C .. "3" .. COMPAT_BAR_BUTTON_SUFFIX_C,
        COMPAT_BAR_PREFIX_C .. "4" .. COMPAT_BAR_BUTTON_SUFFIX_C,
        COMPAT_BAR_PREFIX_C .. "5" .. COMPAT_BAR_BUTTON_SUFFIX_C,
        COMPAT_BAR_PREFIX_C .. "6" .. COMPAT_BAR_BUTTON_SUFFIX_C,
    }

    for _, prefix in ipairs(buttonPrefixes) do
        for i = 1, 12 do
            local button = _G[prefix .. i]
            if button and not addedButtons[button] then
                table.insert(cachedActionButtons, button)
                addedButtons[button] = true
            end
        end
    end

    for i = 1, 180 do
        local button = _G[COMPAT_ACTION_PREFIX_B .. i]
        if button and not addedButtons[button] then
            table.insert(cachedActionButtons, button)
            addedButtons[button] = true
        end
    end

    for i = 1, 120 do
        local button = _G[COMPAT_ACTION_PREFIX_A .. i]
        if button and not addedButtons[button] then
            table.insert(cachedActionButtons, button)
            addedButtons[button] = true
        end
    end

    for i = 1, 10 do
        local button = _G[COMPAT_PET_PREFIX_A .. i]
        if button and not addedButtons[button] then
            table.insert(cachedActionButtons, button)
            addedButtons[button] = true
        end
    end

    for i = 1, 10 do
        local button = _G[COMPAT_STANCE_PREFIX_A .. i]
        if button and not addedButtons[button] then
            table.insert(cachedActionButtons, button)
            addedButtons[button] = true
        end
    end

    table.sort(cachedActionButtons, function(a, b)
        local nameA = (type(a.GetName) == "function") and a:GetName() or ""
        local nameB = (type(b.GetName) == "function") and b:GetName() or ""

        local numA = nameA:match("^" .. COMPAT_ACTION_PREFIX_A .. "(%d+)$")
        local numB = nameB:match("^" .. COMPAT_ACTION_PREFIX_A .. "(%d+)$")
        if numA and numB then
            return tonumber(numA) < tonumber(numB)
        end

        numA = nameA:match("^" .. COMPAT_ACTION_PREFIX_B .. "(%d+)$")
        numB = nameB:match("^" .. COMPAT_ACTION_PREFIX_B .. "(%d+)$")
        if numA and numB then
            return tonumber(numA) < tonumber(numB)
        end

        local barA, slotA = nameA:match("^" .. COMPAT_BAR_PREFIX_C .. "(%d+)" .. COMPAT_BAR_BUTTON_SUFFIX_C .. "(%d+)$")
        local barB, slotB = nameB:match("^" .. COMPAT_BAR_PREFIX_C .. "(%d+)" .. COMPAT_BAR_BUTTON_SUFFIX_C .. "(%d+)$")
        if barA and barB then
            if barA ~= barB then return tonumber(barA) < tonumber(barB) end
            return tonumber(slotA) < tonumber(slotB)
        end

        local priorityA = nameA:match("^" .. COMPAT_ACTION_PREFIX_A) and 1
            or nameA:match("^" .. COMPAT_ACTION_PREFIX_B) and 2
            or nameA:match("^" .. COMPAT_BAR_PREFIX_C) and 3
            or 4
        local priorityB = nameB:match("^" .. COMPAT_ACTION_PREFIX_A) and 1
            or nameB:match("^" .. COMPAT_ACTION_PREFIX_B) and 2
            or nameB:match("^" .. COMPAT_BAR_PREFIX_C) and 3
            or 4
        if priorityA ~= priorityB then
            return priorityA < priorityB
        end

        return false
    end)

    actionButtonsCached = true
end

local function RebuildCache()
    if not IsAnyKeybindFeatureEnabled() then
        lastCacheUpdate = GetTime()
        return
    end

    if InCombatLockdown() then
        pendingRebuild = true
        return
    end

    if not actionButtonsCached then
        BuildActionButtonCache()
    end

    wipe(spellToKeybind)
    wipe(spellNameToKeybind)
    wipe(itemToKeybind)
    wipe(itemNameToKeybind)

    wipe(macroNameToIndex)
    for i = 1, 138 do
        local name = GetMacroInfo(i)
        if name then
            macroNameToIndex[name:lower()] = i
        end
    end

    for _, button in ipairs(cachedActionButtons) do
        QUI.SafeCall("best-effort-style", ProcessActionButton, button)
    end

    lastCacheUpdate = GetTime()
    pendingRebuild = false
end

local function GetKeybindForSpell(spellID)
    if not spellID then return nil end

    local now = GetTime()
    if now - lastCacheUpdate > CACHE_UPDATE_INTERVAL then
        RebuildCache()
    end

    local ok, result = pcall(function()
        return spellToKeybind[spellID]
    end)

    if ok then
        return result
    end
    return nil
end

local function GetKeybindForSpellName(spellName)
    if not spellName then return nil end

    local now = GetTime()
    if now - lastCacheUpdate > CACHE_UPDATE_INTERVAL then
        RebuildCache()
    end

    local ok, nameLower = pcall(function() return spellName:lower() end)
    if not ok or not nameLower then return nil end

    return spellNameToKeybind[nameLower]
end

local function GetKeybindForItem(itemID)
    if not itemID then return nil end

    local now = GetTime()
    if now - lastCacheUpdate > CACHE_UPDATE_INTERVAL then
        RebuildCache()
    end

    return itemToKeybind[itemID]
end

local function GetKeybindForItemName(itemName)
    if not itemName then return nil end

    local now = GetTime()
    if now - lastCacheUpdate > CACHE_UPDATE_INTERVAL then
        RebuildCache()
    end

    local ok, nameLower = pcall(function() return itemName:lower() end)
    if not ok or not nameLower then return nil end

    return itemNameToKeybind[nameLower]
end

local function ApplyKeybindToIcon(icon, viewerName)
    local QUICore = _G.QUI and _G.QUI.QUICore
    if not QUICore or not QUICore.db or not QUICore.db.profile then return end

    local settings = GetViewerSettings(viewerName)
    if not settings then return end

    if not settings.showKeybinds then
        local iks = iconKeybindState[icon]
        if iks and iks.text then
            iks.text:Hide()
        end
        return
    end

    local spellID
    local spellName
    local itemID
    local itemName

    local spellEntry = icon._spellEntry
    if not spellEntry and _G.QUI_ResolveCDMFrameEntry then
        spellEntry = _G.QUI_ResolveCDMFrameEntry(icon)
    end
    local customEntry = icon._customCDMEntry
        or (spellEntry and (spellEntry._isCustomEntry or spellEntry._isOwnedEntry) and spellEntry)
    local isItemEntry = customEntry and (customEntry.type == "item" or customEntry.type == "trinket" or customEntry.type == "slot")

    if spellEntry then
        spellID = spellEntry.overrideSpellID or spellEntry.spellID
        if spellEntry.name and type(spellEntry.name) == "string" and spellEntry.name ~= "" then
            spellName = spellEntry.name
        end
    end

    if not spellID then
        local ok, result = pcall(function()
            local id = icon.spellID
            if not id and icon.GetSpellID then
                id = icon:GetSpellID()
            end
            return id
        end)

        if ok and result then
            if type(issecretvalue) == "function" and issecretvalue(result) then
                result = nil
            end
            spellID = result
        end
    end

    if isItemEntry and customEntry and customEntry.id then
        if customEntry.type == "item" then
            itemID = tonumber(customEntry.id)
        elseif customEntry.type == "trinket" or customEntry.type == "slot" then
            itemID = customEntry.itemID or GetInventoryItemID("player", customEntry.id)
        end
        if itemID then
            itemName = C_Item.GetItemInfo(itemID)
        end
    end

    if not spellID and icon.action then
        local actionOk, actionType, id = pcall(GetActionInfo, icon.action)
        if actionOk and actionType == "spell" then
            if type(issecretvalue) == "function" and issecretvalue(id) then
                id = nil
            end
            spellID = id
        end
    end

    if not spellName then
        pcall(function()
            if icon.cooldownInfo and icon.cooldownInfo.name then
                local testOk, _ = pcall(function() return icon.cooldownInfo.name:len() end)
                if testOk then
                    spellName = icon.cooldownInfo.name
                end
            end
            if not spellName and spellID then
                local info = C_Spell.GetSpellInfo(spellID)
                if info and info.name then
                    local testOk, _ = pcall(function() return info.name:len() end)
                    if testOk then
                        spellName = info.name
                    end
                end
            end
        end)
    end

    local keybind = nil
    local baseSpellID = nil

    local overrideKeybind = nil
    local cdmOverridesEnabled = true
    local QUICore_ref = _G.QUI and _G.QUI.QUICore
    if QUICore_ref and QUICore_ref.db and QUICore_ref.db.profile then
        if GetViewerKeybindContext(viewerName) == "customTrackers" then
            cdmOverridesEnabled = QUICore_ref.db.profile.keybindOverridesEnabledTrackers ~= false
        else
            cdmOverridesEnabled = QUICore_ref.db.profile.keybindOverridesEnabledCDM ~= false
        end
    end
    if cdmOverridesEnabled then
        if isItemEntry and itemID then
            overrideKeybind = GetOverrideKeybindForItem(itemID)
        else
            overrideKeybind = GetOverrideKeybind(spellID, nil)
        end
    end
    if overrideKeybind then
        if overrideKeybind == "" then
            local iks = iconKeybindState[icon]
            if iks and iks.text then
                if iks.shownText then
                    iks.text:SetText("")
                    iks.shownText = nil
                end
                if iks.text:IsShown() then iks.text:Hide() end
            end
            return
        end
        keybind = overrideKeybind
    end

    if not keybind and isItemEntry and itemID then
        keybind = GetKeybindForItem(itemID)
    end
    if not keybind and isItemEntry and itemName then
        keybind = GetKeybindForItemName(itemName)
    end

    if not keybind and spellID then
        keybind = GetKeybindForSpell(spellID)
    end

    if not keybind and spellID and not isItemEntry then
        local baseFromInfo = (spellEntry and spellEntry.spellID) or (icon.cooldownInfo and icon.cooldownInfo.spellID)
        if baseFromInfo then
            local compareOk, isDifferent = pcall(function() return baseFromInfo ~= spellID end)
            if compareOk and isDifferent then
                if type(issecretvalue) == "function" and issecretvalue(baseFromInfo) then
                    baseFromInfo = nil
                end
                baseSpellID = baseFromInfo
                if cdmOverridesEnabled then
                    overrideKeybind = GetOverrideKeybind(spellID, baseSpellID)
                end
                if overrideKeybind then
                    if overrideKeybind == "" then
                        local iks = iconKeybindState[icon]
                        if iks and iks.text then
                            if iks.shownText then
                                iks.text:SetText("")
                                iks.shownText = nil
                            end
                            if iks.text:IsShown() then iks.text:Hide() end
                        end
                        return
                    end
                    keybind = overrideKeybind
                else
                    keybind = GetKeybindForSpell(baseSpellID)
                end
            end
        end
    end

    if not keybind and spellID and C_Spell.GetBaseSpell and not isItemEntry then
        local okBase, resultBase = pcall(C_Spell.GetBaseSpell, spellID)
        if okBase and resultBase then
            local compareOk, isDifferent = pcall(function() return resultBase ~= spellID end)
            if compareOk and isDifferent then
                if type(issecretvalue) == "function" and issecretvalue(resultBase) then
                    resultBase = nil
                end
                baseSpellID = resultBase
                if cdmOverridesEnabled then
                    overrideKeybind = GetOverrideKeybind(spellID, baseSpellID)
                end
                if overrideKeybind then
                    if overrideKeybind == "" then
                        local iks = iconKeybindState[icon]
                        if iks and iks.text then
                            if iks.shownText then
                                iks.text:SetText("")
                                iks.shownText = nil
                            end
                            if iks.text:IsShown() then iks.text:Hide() end
                        end
                        return
                    end
                    keybind = overrideKeybind
                else
                    keybind = GetKeybindForSpell(baseSpellID)
                end
            end
        end
    end

    if not keybind and spellName then
        keybind = GetKeybindForSpellName(spellName)
    end

    if not keybind then
        local iks = iconKeybindState[icon]
        if iks and iks.text then
            if iks.shownText then
                iks.text:SetText("")
                iks.shownText = nil
            end
            if iks.text:IsShown() then iks.text:Hide() end
        end
        return
    end

    local fontSize = settings.keybindTextSize or 10
    local anchor = settings.keybindAnchor or "TOPLEFT"
    local offsetX = settings.keybindOffsetX or 2
    local offsetY = settings.keybindOffsetY or -2
    local textColor = settings.keybindTextColor or { 1, 1, 1, 1 }

    local iks = iconKeybindState[icon]
    if not iks then
        iks = {}
        iconKeybindState[icon] = iks
    end

    local textLayerParent = (icon.TextOverlay and icon.TextOverlay.CreateFontString and icon.TextOverlay) or icon

    if iks.textLayer and iks.textLayer.GetParent and iks.textLayer:GetParent() ~= textLayerParent then
        if iks.text then
            iks.text:Hide()
        end
        if iks.textLayer.Hide then
            iks.textLayer:Hide()
        end
        iks.textLayer = nil
        iks.text = nil
        iks.shownText = nil
        iks.anchor, iks.offsetX, iks.offsetY = nil, nil, nil
        iks.font, iks.fontSize, iks.fontOutline = nil, nil, nil
        iks.r, iks.g, iks.b, iks.a = nil, nil, nil, nil
    end
    if not iks.textLayer then
        local layer = CreateFrame("Frame", nil, textLayerParent)
        layer:SetAllPoints(textLayerParent)
        iks.textLayer = layer
    end
    if iks.textLayer then
        local cooldownLevel = (icon.Cooldown and icon.Cooldown.GetFrameLevel and icon.Cooldown:GetFrameLevel()) or icon:GetFrameLevel()
        local desiredLevel = cooldownLevel + 20
        if iks.textLayer:GetFrameLevel() ~= desiredLevel then
            iks.textLayer:SetFrameLevel(desiredLevel)
        end
        local strataSource = (textLayerParent.GetFrameStrata and textLayerParent) or icon
        if strataSource.GetFrameStrata and iks.textLayer.GetFrameStrata and iks.textLayer:GetFrameStrata() ~= strataSource:GetFrameStrata() then
            iks.textLayer:SetFrameStrata(strataSource:GetFrameStrata())
        end
    end

    if not iks.text then
        local textParent = iks.textLayer or icon
        iks.text = textParent:CreateFontString(nil, "OVERLAY", nil, 7)
        iks.text:SetShadowOffset(1, -1)
        iks.text:SetShadowColor(0, 0, 0, 1)
    elseif iks.textLayer and iks.text:GetParent() ~= iks.textLayer then
        local existingText = iks.text:GetText()
        local shown = iks.text:IsShown()
        iks.text:Hide()
        iks.text = iks.textLayer:CreateFontString(nil, "OVERLAY", nil, 7)
        iks.text:SetShadowOffset(1, -1)
        iks.text:SetShadowColor(0, 0, 0, 1)
        iks.text:SetText(existingText or "")
        if shown then iks.text:Show() end
        iks.anchor, iks.offsetX, iks.offsetY = nil, nil, nil
        iks.font, iks.fontSize, iks.fontOutline = nil, nil, nil
        iks.r, iks.g, iks.b, iks.a = nil, nil, nil, nil
    end

    local curFont = GetGeneralFont()
    local curOutline = GetGeneralFontOutline()
    local r, g, b, a = textColor[1], textColor[2], textColor[3], textColor[4] or 1

    if iks.anchor ~= anchor or iks.offsetX ~= offsetX or iks.offsetY ~= offsetY then
        iks.text:ClearAllPoints()
        local anchorParent = iks.textLayer or icon
        iks.text:SetPoint(anchor, anchorParent, anchor, offsetX, offsetY)
        iks.anchor, iks.offsetX, iks.offsetY = anchor, offsetX, offsetY
    end

    if iks.font ~= curFont or iks.fontSize ~= fontSize or iks.fontOutline ~= curOutline then
        CJKFont(iks.text, curFont, fontSize, curOutline)
        iks.font, iks.fontSize, iks.fontOutline = curFont, fontSize, curOutline
    end

    if iks.r ~= r or iks.g ~= g or iks.b ~= b or iks.a ~= a then
        iks.text:SetTextColor(r, g, b, a)
        iks.r, iks.g, iks.b, iks.a = r, g, b, a
    end

    if keybind then
        if iks.shownText ~= keybind then
            iks.text:SetText(keybind)
            iks.shownText = keybind
        end
        if not iks.text:IsShown() then iks.text:Show() end
    else
        if iks.shownText then
            iks.text:SetText("")
            iks.shownText = nil
        end
        if iks.text:IsShown() then iks.text:Hide() end
    end
end

local function ClearKeybindIconState(icon)
    if not icon then return end
    local iks = iconKeybindState[icon]
    if not iks then return end

    if iks.text then
        if iks.shownText then
            iks.text:SetText("")
        end
        if iks.text:IsShown() then iks.text:Hide() end
    end
    iks.shownText = nil
    iks.keybind = nil
    iks.spellID = nil

    if iks.overlay and iks.overlay:IsShown() then
        iks.overlay:Hide()
    end
end

local function SetKeybindOverride(spellID, keybindText)
    if not spellID then return end

    spellID = tonumber(spellID)
    if not spellID or spellID <= 0 then return end

    local overrides = GetSharedOverrides()
    if not overrides then return end

    if keybindText == nil then
        overrides[spellID] = nil
    else
        overrides[spellID] = keybindText
    end

    if _G.QUI_RefreshKeybinds then
        _G.QUI_RefreshKeybinds()
    end

    if _G.QUI_RefreshCustomTrackerKeybinds then
        _G.QUI_RefreshCustomTrackerKeybinds()
    end
end

local function ClearAllKeybindOverrides()
    local overrides = GetSharedOverrides()
    if not overrides then return end

    wipe(overrides)

    if _G.QUI_RefreshKeybinds then
        _G.QUI_RefreshKeybinds()
    end

    if _G.QUI_RefreshCustomTrackerKeybinds then
        _G.QUI_RefreshCustomTrackerKeybinds()
    end
end

local function SetKeybindOverrideForItem(itemID, keybindText)
    if not itemID then return end

    itemID = tonumber(itemID)
    if not itemID or itemID <= 0 then return end

    local overrides = GetSharedOverrides()
    if not overrides then return end
    local key = -itemID

    if keybindText == nil then
        overrides[key] = nil
    else
        overrides[key] = keybindText
    end

    if _G.QUI_RefreshCustomTrackerKeybinds then
        _G.QUI_RefreshCustomTrackerKeybinds()
    end

    if _G.QUI_RefreshKeybinds then
        _G.QUI_RefreshKeybinds()
    end
end

local function GetCustomContainerKeys()
    local core = GetCore()
    if not core or not core.db or not core.db.profile then return end
    local ncdm = core.db.profile.ncdm
    local ct = ncdm and ncdm.containers
    if not ct then return end
    local keys = {}
    for key, settings in pairs(ct) do
        if type(settings) == "table" and not settings.builtIn
            and (settings.containerType == "cooldown" or settings.containerType == "customBar") then
            keys[#keys + 1] = key
        end
    end
    return keys
end

-- <<< QUI_TEST_EXTRACT viewer_children_sweep
local function GetViewerChildren(viewerName)
    local viewer = _G.QUI_GetCDMViewerFrame and _G.QUI_GetCDMViewerFrame(viewerName)
    local out
    if viewer then
        local container = viewer.viewerFrame or viewer
        out = {}
        local children = { container:GetChildren() }
        for i = 1, #children do
            if not children[i]._quiCdmClickSlot then
                out[#out + 1] = children[i]
            end
        end
    end
    if _G.QUI_GetReanchoredCDMFrames then
        local extra = _G.QUI_GetReanchoredCDMFrames(viewerName)
        if extra and #extra > 0 then
            out = out or {}
            for i = 1, #extra do
                out[#out + 1] = extra[i]
            end
        end
    end
    return out
end
-- <<< QUI_TEST_EXTRACT viewer_children_sweep

local function UpdateViewerKeybinds(viewerName)
    local children = GetViewerChildren(viewerName)
    if not children then return end

    for _, child in ipairs(children) do
        if child:IsShown() then
            ApplyKeybindToIcon(child, viewerName)
        end
    end
end

local function ClearStoredKeybinds(viewerName)
    local children = GetViewerChildren(viewerName)
    if not children then return end

    for _, child in ipairs(children) do
        local cks = iconKeybindState[child]
        if cks then
            cks.keybind = nil
            cks.spellID = nil
            cks.shownText = nil
        end
    end
end

local function ClearAllStoredKeybinds()
    ClearStoredKeybinds("essential")
    ClearStoredKeybinds("utility")
    local customKeys = GetCustomContainerKeys()
    if customKeys then
        for _, key in ipairs(customKeys) do
            ClearStoredKeybinds(key)
        end
    end
end

local function UpdateAllKeybinds()
    lastCacheUpdate = 0
    RebuildCache()

    UpdateViewerKeybinds("essential")
    UpdateViewerKeybinds("utility")
    local customKeys = GetCustomContainerKeys()
    if customKeys then
        for _, key in ipairs(customKeys) do
            UpdateViewerKeybinds(key)
        end
    end
end

local updatePending = false
local UPDATE_THROTTLE = 0.5

local function ThrottledUpdate()
    if updatePending then return end
    updatePending = true

    C_Timer.After(UPDATE_THROTTLE, function()
        updatePending = false
        if InCombatLockdown() then
            pendingRebuild = true
            return
        end
        UpdateAllKeybinds()
    end)
end

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("UPDATE_BINDINGS")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("SPELLS_CHANGED")
eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")

eventFrame:SetScript("OnEvent", function(self, event)
    if event ~= "PLAYER_ENTERING_WORLD" and event ~= "PLAYER_REGEN_ENABLED" then
        if not IsAnyKeybindFeatureEnabled() then return end
    end

    if event == "PLAYER_REGEN_ENABLED" then
        if pendingRebuild and IsAnyKeybindFeatureEnabled() then
            C_Timer.After(0.2, UpdateAllKeybinds)
        end
        return
    end

    if event == "PLAYER_ENTERING_WORLD" then
        C_Timer.After(0.5, function()
            if not IsAnyKeybindFeatureEnabled() then return end
            actionButtonsCached = false
            wipe(iconKeybindCache)
            UpdateAllKeybinds()
        end)
        return
    end

    if event == "UPDATE_BINDINGS" then
        wipe(iconKeybindCache)
        ClearAllStoredKeybinds()
    end

    ThrottledUpdate()
end)

if QUI.WhenLoggedIn then
    QUI.WhenLoggedIn(function()
        C_Timer.After(0.5, function()
            if not IsAnyKeybindFeatureEnabled() then return end
            actionButtonsCached = false
            wipe(iconKeybindCache)
            UpdateAllKeybinds()
        end)
    end)
end

local function HookViewerLayout(viewerName)
    local viewer = _G.QUI_GetCDMViewerFrame and _G.QUI_GetCDMViewerFrame(viewerName)
    if not viewer then return end

    hookedKeybindViewers[viewer] = true
end

local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("ADDON_LOADED")
initFrame:RegisterEvent("PLAYER_ENTERING_WORLD")

local function HookAllViewerLayouts()
    HookViewerLayout("essential")
    HookViewerLayout("utility")
    local customKeys = GetCustomContainerKeys()
    if customKeys then
        for _, key in ipairs(customKeys) do
            HookViewerLayout(key)
        end
    end
end

initFrame:SetScript("OnEvent", function(self, event, arg)
    if event == "ADDON_LOADED" and arg == "Blizzard_CooldownManager" then
        C_Timer.After(0.5, function()
            HookAllViewerLayouts()
            if IsAnyKeybindFeatureEnabled() then
                UpdateAllKeybinds()
            end
        end)
    elseif event == "PLAYER_ENTERING_WORLD" then
        C_Timer.After(1.0, function()
            HookAllViewerLayouts()
            if IsAnyKeybindFeatureEnabled() then
                UpdateAllKeybinds()
            end
        end)
    end
end)

if QUI.WhenLoggedIn then
    QUI.WhenLoggedIn(function()
        C_Timer.After(1.0, function()
            HookAllViewerLayouts()
            if IsAnyKeybindFeatureEnabled() then
                UpdateAllKeybinds()
            end
        end)
    end)
end

_G.QUI_UpdateViewerKeybinds = function(viewerName)
    if not IsAnyKeybindFeatureEnabled() then return end
    UpdateViewerKeybinds(VIEWER_RESOLVER_KEY[viewerName] or viewerName)
end

local function GetRotationHelperOverlay(icon)
    local iks = iconKeybindState[icon]
    if iks and iks.overlay then
        return iks.overlay
    end

    local overlay = CreateFrame("Frame", nil, icon)
    overlay:SetAllPoints(icon)
    overlay:SetFrameLevel(icon:GetFrameLevel() + 15)

    local borderSize = 2
    local borders = {}

    borders.top = overlay:CreateTexture(nil, "OVERLAY")
    borders.top:SetColorTexture(0, 1, 0, 0.8)
    borders.top:SetPoint("TOPLEFT", overlay, "TOPLEFT", 0, 0)
    borders.top:SetPoint("TOPRIGHT", overlay, "TOPRIGHT", 0, 0)
    borders.top:SetHeight(borderSize)

    borders.bottom = overlay:CreateTexture(nil, "OVERLAY")
    borders.bottom:SetColorTexture(0, 1, 0, 0.8)
    borders.bottom:SetPoint("BOTTOMLEFT", overlay, "BOTTOMLEFT", 0, 0)
    borders.bottom:SetPoint("BOTTOMRIGHT", overlay, "BOTTOMRIGHT", 0, 0)
    borders.bottom:SetHeight(borderSize)

    borders.left = overlay:CreateTexture(nil, "OVERLAY")
    borders.left:SetColorTexture(0, 1, 0, 0.8)
    borders.left:SetPoint("TOPLEFT", overlay, "TOPLEFT", 0, 0)
    borders.left:SetPoint("BOTTOMLEFT", overlay, "BOTTOMLEFT", 0, 0)
    borders.left:SetWidth(borderSize)

    borders.right = overlay:CreateTexture(nil, "OVERLAY")
    borders.right:SetColorTexture(0, 1, 0, 0.8)
    borders.right:SetPoint("TOPRIGHT", overlay, "TOPRIGHT", 0, 0)
    borders.right:SetPoint("BOTTOMRIGHT", overlay, "BOTTOMRIGHT", 0, 0)
    borders.right:SetWidth(borderSize)

    overlay.borders = borders

    overlay.SetBorderColor = function(self, r, g, b, a)
        for _, tex in pairs(self.borders) do
            tex:SetColorTexture(r, g, b, a or 0.8)
        end
    end

    overlay.SetBorderSize = function(self, size)
        self.borders.top:SetHeight(size)
        self.borders.bottom:SetHeight(size)
        self.borders.left:SetWidth(size)
        self.borders.right:SetWidth(size)
    end

    overlay:Hide()
    if not iks then
        iks = {}
        iconKeybindState[icon] = iks
    end
    iks.overlay = overlay

    return overlay
end

local function ApplyRotationHelperToIcon(icon, settings, nextSpellID, nextBaseSpellID)
    if not settings or not settings.showRotationHelper then
        local iks = iconKeybindState[icon]
        if iks and iks.overlay then
            iks.overlay:Hide()
        end
        return
    end

    local iconSpellID
    local resolvedEntry = icon._spellEntry
    if not resolvedEntry and _G.QUI_ResolveCDMFrameEntry then
        resolvedEntry = _G.QUI_ResolveCDMFrameEntry(icon)
    end
    local ok, result = pcall(function()
        if resolvedEntry then
            return resolvedEntry.overrideSpellID or resolvedEntry.spellID or resolvedEntry.id
        end
        if icon.cooldownID then
            return icon.cooldownID
        end
        if icon.cooldownInfo and icon.cooldownInfo.spellID then
            return icon.cooldownInfo.spellID
        end
        if icon.spellID then
            return icon.spellID
        end
        return nil
    end)

    if ok and result then
        iconSpellID = result
    end

    if not iconSpellID then
        local iks = iconKeybindState[icon]
        if iks and iks.overlay then
            iks.overlay:Hide()
        end
        return
    end

    local isNextSpell = false
    if nextSpellID then
        if iconSpellID == nextSpellID then
            isNextSpell = true
        end
        if not isNextSpell and nextBaseSpellID and iconSpellID == nextBaseSpellID then
            isNextSpell = true
        end
        if not isNextSpell and resolvedEntry then
            local entryBase = resolvedEntry.spellID
            local entryOvr = resolvedEntry.overrideSpellID
            if entryBase and (entryBase == nextSpellID or (nextBaseSpellID and entryBase == nextBaseSpellID)) then
                isNextSpell = true
            elseif entryOvr and (entryOvr == nextSpellID or (nextBaseSpellID and entryOvr == nextBaseSpellID)) then
                isNextSpell = true
            end
        end
        if not isNextSpell and iconSpellID and C_SpellBook and C_SpellBook.FindBaseSpellByID then
            local okBase, resolvedBase = pcall(C_SpellBook.FindBaseSpellByID, iconSpellID)
            if okBase and resolvedBase and resolvedBase ~= iconSpellID then
                if resolvedBase == nextSpellID or (nextBaseSpellID and resolvedBase == nextBaseSpellID) then
                    isNextSpell = true
                end
            end
        end
    end

    local overlay = GetRotationHelperOverlay(icon)

    if isNextSpell then
        local color = settings.rotationHelperColor or { 0, 1, 0, 0.8 }
        local thickness = settings.rotationHelperThickness or 2
        overlay:SetBorderColor(color[1], color[2], color[3], color[4] or 0.8)
        overlay:SetBorderSize(thickness)
        overlay:Show()
    else
        overlay:Hide()
    end
end

local function UpdateViewerRotationHelper(viewerName, nextSpellID, nextBaseSpellID)
    local settings
    local core = GetCore()
    if core and core.db and core.db.profile then
        local viewers = core.db.profile.viewers
        if viewers then
            settings = viewers[VIEWER_DB_KEY[viewerName] or viewerName]
        end
    end

    local function ProcessReanchored()
        if not _G.QUI_GetReanchoredCDMFrames then return end
        local extra = _G.QUI_GetReanchoredCDMFrames(viewerName)
        if not extra then return end
        for i = 1, #extra do
            ApplyRotationHelperToIcon(extra[i], settings, nextSpellID, nextBaseSpellID)
        end
    end

    local CDMIconFactory = QUI.CDMIconFactory
    if CDMIconFactory then
        local pool = CDMIconFactory:GetIconPool(viewerName)
        if pool then
            for _, icon in ipairs(pool) do
                ApplyRotationHelperToIcon(icon, settings, nextSpellID, nextBaseSpellID)
            end
            ProcessReanchored()
            return
        end
    end

    local children = GetViewerChildren(viewerName)
    if not children then return end
    for i = 1, #children do
        ApplyRotationHelperToIcon(children[i], settings, nextSpellID, nextBaseSpellID)
    end
end

local function UpdateAllRotationHelpers(overrideSpellID, baseSpellID)
    local nextSpellID = overrideSpellID
    local nextBaseSpellID = baseSpellID
    if not nextSpellID then
        if not C_AssistedCombat or not C_AssistedCombat.GetNextCastSpell then
            return
        end
        local ok, sid = pcall(C_AssistedCombat.GetNextCastSpell, false)
        if ok then nextSpellID = sid end
        if nextSpellID and C_Spell and C_Spell.GetOverrideSpell then
            nextBaseSpellID = nextSpellID
            local okOvr, ovrID = pcall(C_Spell.GetOverrideSpell, nextSpellID)
            if okOvr and ovrID and ovrID ~= nextSpellID then
                nextSpellID = ovrID
            end
        end
    end

    currentRotationSpellID = nextSpellID
    currentRotationBaseSpellID = nextBaseSpellID

    UpdateViewerRotationHelper("essential", nextSpellID, nextBaseSpellID)
    UpdateViewerRotationHelper("utility", nextSpellID, nextBaseSpellID)
end

local function ShouldRunRotationHelper()
    local core = GetCore()
    if not core or not core.db or not core.db.profile then return false end

    local viewers = core.db.profile.viewers
    if not viewers then return false end

    local essential = viewers.EssentialCooldownViewer
    local utility = viewers.UtilityCooldownViewer

    return (essential and essential.showRotationHelper) or (utility and utility.showRotationHelper)
end

local function RefreshRotationHelper()
    rotationHelperEnabled = ShouldRunRotationHelper()

    if not rotationHelperEnabled then
        UpdateViewerRotationHelper("essential", nil)
        UpdateViewerRotationHelper("utility", nil)
    else
        UpdateAllRotationHelpers()
    end
end

local rotationHelperInitFrame = CreateFrame("Frame")
rotationHelperInitFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
rotationHelperInitFrame:SetScript("OnEvent", function()
    C_Timer.After(1.0, RefreshRotationHelper)
end)

if QUI.WhenLoggedIn then
    QUI.WhenLoggedIn(function()
        C_Timer.After(1.0, RefreshRotationHelper)
    end)
end

QUI._onIconAssigned = function(icon)
    if not rotationHelperEnabled or not currentRotationSpellID then return end
    local entry = icon._spellEntry
    if not entry then return end
    local vType = entry.viewerType
    if vType ~= "essential" and vType ~= "utility" then return end
    local core = GetCore()
    if not core or not core.db or not core.db.profile or not core.db.profile.viewers then return end
    local settings = core.db.profile.viewers[VIEWER_DB_KEY[vType] or vType]
    if settings then
        ApplyRotationHelperToIcon(icon, settings, currentRotationSpellID, currentRotationBaseSpellID)
    end
end

QUI.Keybinds = {
    UpdateAll = UpdateAllKeybinds,
    UpdateViewer = UpdateViewerKeybinds,
    GetKeybindForSpell = GetKeybindForSpell,
    GetKeybindForSpellName = GetKeybindForSpellName,
    GetKeybindForItem = GetKeybindForItem,
    GetKeybindForItemName = GetKeybindForItemName,
    GetOverrides = GetSharedOverrides,
    RebuildCache = RebuildCache,
    SetOverride = SetKeybindOverride,
    SetOverrideForItem = SetKeybindOverrideForItem,
    GetOverrideForItem = GetOverrideKeybindForItem,
    ClearAllOverrides = ClearAllKeybindOverrides,
    ClearIconState = ClearKeybindIconState,
    RefreshRotationHelper = RefreshRotationHelper,
    UpdateAllRotationHelpers = UpdateAllRotationHelpers,
}

_G.QUI_RefreshKeybinds = UpdateAllKeybinds
_G.QUI_RefreshRotationHelper = RefreshRotationHelper
_G.QUI_ClearKeybindIconState = ClearKeybindIconState

if QUI.Registry then
    QUI.Registry:Register("keybinds", {
        refresh = _G.QUI_RefreshKeybinds,
        priority = 50,
        group = "utility",
        importCategories = { "cdm", "customTrackers" },
    })
end
