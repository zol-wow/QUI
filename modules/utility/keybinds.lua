-- keybinds.lua
-- Displays action bar keybinds on Essential and Utility cooldown viewer icons
-- Also handles Rotation Helper overlay (C_AssistedCombat integration)

local _, QUI = ...
local LSM = LibStub("LibSharedMedia-3.0")

-- Cache for spell ID to keybind mapping
local spellToKeybind = {}
-- Cache for spell NAME to keybind mapping (fallback for macros)
local spellNameToKeybind = {}
-- Cache for item ID to keybind mapping (custom trackers)
local itemToKeybind = {}
-- Cache for item NAME to keybind mapping (fallback for macros with items)
local itemNameToKeybind = {}
local lastCacheUpdate = 0
local CACHE_UPDATE_INTERVAL = 1.0 -- Seconds between cache rebuilds

-- Cache of known action buttons (built once, reused)
local cachedActionButtons = {}
local actionButtonsCached = false

-- Macro name → index lookup table for O(1) lookup instead of O(138) loop
local macroNameToIndex = {}

-- Combat throttling
local pendingRebuild = false

-- Rotation Helper state
local rotationHelperEnabled = false
local lastNextSpellID = nil
local rotationHelperTicker = nil  -- Performance: Ticker instead of OnUpdate

-- Position-based keybind cache (remembers keybinds by icon to handle procs)
local iconKeybindCache = {}

-- Debug mode for keybind tracking
local KEYBIND_DEBUG = false

-- Performance: Check if ANY keybind display feature is enabled across all viewers
-- This gates expensive operations to prevent CPU spikes when features are disabled
local function IsAnyKeybindFeatureEnabled()
    local QUICore = _G.QUI and _G.QUI.QUICore
    if not QUICore or not QUICore.db or not QUICore.db.profile then return false end

    local viewers = QUICore.db.profile.viewers
    if not viewers then return false end

    for viewerName, settings in pairs(viewers) do
        if settings.showKeybinds or settings.showMacroNames or settings.showStackCounts then
            return true
        end
    end
    return false
end

-- Get font from general settings (uses shared helpers)
local Helpers = QUI.Helpers
local GetGeneralFont = Helpers.GetGeneralFont
local GetGeneralFontOutline = Helpers.GetGeneralFontOutline

-- Format keybind text for display (shorten modifiers, max 4 chars)
local function FormatKeybind(keybind)
    if not keybind then return nil end

    local upper = keybind:upper()

    -- CRITICAL: Remove ALL spaces first to normalize localized text
    -- WoW returns "Num Pad 3", "Mouse Wheel Up", etc. - we need "NUMPAD3", "MOUSEWHEELUP"
    upper = upper:gsub(" ", "")

    -- Shorten mousewheel/mouse BEFORE removing modifier hyphens
    -- This ensures CTRL-MOUSEWHEELUP -> CTRL-WU -> CWU (not CMOUSEWHEELUP)
    upper = upper:gsub("MOUSEWHEELUP", "WU")
    upper = upper:gsub("MOUSEWHEELDOWN", "WD")
    upper = upper:gsub("MIDDLEMOUSE", "B3")
    upper = upper:gsub("MIDDLEBUTTON", "B3")
    upper = upper:gsub("BUTTON(%d+)", "B%1")  -- BUTTON4 -> B4, BUTTON5 -> B5

    -- THEN: Remove modifier hyphens
    upper = upper:gsub("SHIFT%-", "S")
    upper = upper:gsub("CTRL%-", "C")
    upper = upper:gsub("ALT%-", "A")
    upper = upper:gsub("^S%-(.+)", "S%1")
    upper = upper:gsub("^C%-(.+)", "C%1")
    upper = upper:gsub("^A%-(.+)", "A%1")

    -- Numpad special keys (BEFORE generic NUMPAD replacement)
    upper = upper:gsub("NUMPADPLUS", "N+")
    upper = upper:gsub("NUMPADMINUS", "N-")
    upper = upper:gsub("NUMPADMULTIPLY", "N*")
    upper = upper:gsub("NUMPADDIVIDE", "N/")
    upper = upper:gsub("NUMPADPERIOD", "N.")
    upper = upper:gsub("NUMPADENTER", "NE")

    -- Other common keys
    upper = upper:gsub("NUMPAD", "N")
    upper = upper:gsub("CAPSLOCK", "CAP")
    upper = upper:gsub("DELETE", "DEL")
    upper = upper:gsub("ESCAPE", "ESC")
    upper = upper:gsub("BACKSPACE", "BS")
    upper = upper:gsub("SPACE", "SP")
    upper = upper:gsub("INSERT", "INS")
    upper = upper:gsub("PAGEUP", "PU")
    upper = upper:gsub("PAGEDOWN", "PD")
    upper = upper:gsub("HOME", "HM")
    upper = upper:gsub("END", "ED")
    upper = upper:gsub("PRINTSCREEN", "PS")
    upper = upper:gsub("SCROLLLOCK", "SL")
    upper = upper:gsub("PAUSE", "PA")
    upper = upper:gsub("TILDE", "`")
    upper = upper:gsub("GRAVE", "`")

    -- Arrow keys
    upper = upper:gsub("UPARROW", "UP")
    upper = upper:gsub("DOWNARROW", "DN")
    upper = upper:gsub("LEFTARROW", "LF")
    upper = upper:gsub("RIGHTARROW", "RT")

    -- Symbol keys
    upper = upper:gsub("SEMICOLON", ";")
    upper = upper:gsub("APOSTROPHE", "'")
    upper = upper:gsub("LEFTBRACKET", "[")
    upper = upper:gsub("RIGHTBRACKET", "]")
    upper = upper:gsub("BACKSLASH", "\\")
    upper = upper:gsub("MINUS", "-")
    upper = upper:gsub("EQUALS", "=")
    upper = upper:gsub("COMMA", ",")
    -- Note: PERIOD already handled by NUMPADPERIOD, but standalone PERIOD key:
    upper = upper:gsub("^PERIOD$", ".")
    upper = upper:gsub("SLASH", "/")

    -- Final safety: truncate to max 4 characters
    if #upper > 4 then
        upper = upper:sub(1, 4)
    end

    return upper
end

-- Expose globally for other modules (action bars, rotation helper)
QUI.FormatKeybind = FormatKeybind

-- BT4 bar number to WoW binding name mapping (matches Bartender4's BINDING_MAPPINGS)
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

-- Get binding name from BT4 button number (e.g., BT4Button5 -> ACTIONBUTTON5)
local function GetBT4BindingName(buttonNum)
    local bar = math.ceil(buttonNum / 12)
    local buttonInBar = ((buttonNum - 1) % 12) + 1
    local template = BT4_BINDING_MAPPINGS[bar]
    if template then
        return string.format(template, buttonInBar)
    end
    return nil
end

-- Maps action slot numbers to WoW binding names (fallback)
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

-- Get the keybind for an action button by scanning the button directly
local function GetKeybindFromActionButton(button, actionSlot)
    if not button then return nil end
    
    -- Method 1: Check if button has a hotkey text (most reliable for action bar addons)
    if button.HotKey then
        local ok, hotkeyText = pcall(function() return button.HotKey:GetText() end)
        if ok and hotkeyText and hotkeyText ~= "" and hotkeyText ~= RANGE_INDICATOR then
            return FormatKeybind(hotkeyText)
        end
    end
    
    -- Method 2: Check hotKey (lowercase k - some addons use this)
    if button.hotKey then
        local ok, hotkeyText = pcall(function() return button.hotKey:GetText() end)
        if ok and hotkeyText and hotkeyText ~= "" and hotkeyText ~= RANGE_INDICATOR then
            return FormatKeybind(hotkeyText)
        end
    end
    
    -- Method 3: Try GetHotkey method (some addons provide this)
    if button.GetHotkey then
        local ok, hotkey = pcall(function() return button:GetHotkey() end)
        if ok and hotkey and hotkey ~= "" then
            return FormatKeybind(hotkey)
        end
    end
    
    -- Method 4: Get binding from button name
    local buttonName = button:GetName()
    if buttonName then
        -- Try CLICK binding (used by many addons)
        local key1 = GetBindingKey("CLICK " .. buttonName .. ":LeftButton")
        if key1 then
            return FormatKeybind(key1)
        end
        
        -- Try standard action button bindings based on name
        if buttonName:match("ActionButton(%d+)$") then
            local num = tonumber(buttonName:match("ActionButton(%d+)$"))
            if num then
                key1 = GetBindingKey("ACTIONBUTTON" .. num)
                if key1 then return FormatKeybind(key1) end
            end
        elseif buttonName:match("MultiBarBottomLeftButton(%d+)$") then
            local num = tonumber(buttonName:match("MultiBarBottomLeftButton(%d+)$"))
            if num then
                key1 = GetBindingKey("MULTIACTIONBAR1BUTTON" .. num)
                if key1 then return FormatKeybind(key1) end
            end
        elseif buttonName:match("MultiBarBottomRightButton(%d+)$") then
            local num = tonumber(buttonName:match("MultiBarBottomRightButton(%d+)$"))
            if num then
                key1 = GetBindingKey("MULTIACTIONBAR2BUTTON" .. num)
                if key1 then return FormatKeybind(key1) end
            end
        elseif buttonName:match("MultiBarRightButton(%d+)$") then
            local num = tonumber(buttonName:match("MultiBarRightButton(%d+)$"))
            if num then
                key1 = GetBindingKey("MULTIACTIONBAR3BUTTON" .. num)
                if key1 then return FormatKeybind(key1) end
            end
        elseif buttonName:match("MultiBarLeftButton(%d+)$") then
            local num = tonumber(buttonName:match("MultiBarLeftButton(%d+)$"))
            if num then
                key1 = GetBindingKey("MULTIACTIONBAR4BUTTON" .. num)
                if key1 then return FormatKeybind(key1) end
            end
        elseif buttonName:match("^BT4Button(%d+)$") then
            local num = tonumber(buttonName:match("^BT4Button(%d+)$"))
            if num then
                -- Priority 1: Try Bartender4's CLICK binding formats
                key1 = GetBindingKey("CLICK " .. buttonName .. ":Keybind")
                if not key1 then
                    key1 = GetBindingKey("CLICK " .. buttonName .. ":LeftButton")
                end
                -- Priority 2: Try BT4 bar-based binding (ACTIONBUTTON, MULTIACTIONBAR, etc.)
                if not key1 then
                    local bindingName = GetBT4BindingName(num)
                    if bindingName then
                        key1 = GetBindingKey(bindingName)
                    end
                end
                -- Priority 3: Fallback to action slot-based binding
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

-- Parse macro body text to extract spell names/IDs
-- Returns two tables: spellIDs (id -> true) and spellNames (name -> true)
local function ParseMacroForSpells(macroIndex)
    local spellIDs = {}
    local spellNames = {}
    
    -- Get macro body
    local macroName, iconTexture, body = GetMacroInfo(macroIndex)
    if not body then return spellIDs, spellNames end
    
    -- First, try the simple GetMacroSpell which handles basic cases
    local simpleSpell = GetMacroSpell(macroIndex)
    if simpleSpell then
        spellIDs[simpleSpell] = true
        -- Also get the spell name for this ID
        local spellInfo = C_Spell.GetSpellInfo(simpleSpell)
        if spellInfo and spellInfo.name then
            spellNames[spellInfo.name:lower()] = true
        end
    end
    
    -- Parse each line for /cast, /use, #showtooltip commands
    for line in body:gmatch("[^\r\n]+") do
        local lineLower = line:lower()
        
        -- Skip comments
        if not lineLower:match("^%s*%-%-") then
            local spellName = nil
            
            -- Try to extract spell name from various patterns
            -- Pattern 1: /cast [conditions] SpellName or /cast SpellName
            if lineLower:match("/cast") then
                -- Remove the /cast part and any conditions in brackets
                local afterCast = line:match("/[cC][aA][sS][tT]%s*(.*)")
                if afterCast then
                    -- Remove condition brackets like [@mouseover,exists][]
                    afterCast = afterCast:gsub("%[.-%]", "")
                    -- Clean up and get the spell name
                    spellName = afterCast:match("^%s*(.-)%s*$")
                end
            end
            
            -- Pattern 2: /use [conditions] SpellName or /use SpellName  
            if not spellName or spellName == "" then
                if lineLower:match("/use") then
                    local afterUse = line:match("/[uU][sS][eE]%s*(.*)")
                    if afterUse then
                        afterUse = afterUse:gsub("%[.-%]", "")
                        spellName = afterUse:match("^%s*(.-)%s*$")
                    end
                end
            end
            
            -- Pattern 3: #showtooltip SpellName
            if not spellName or spellName == "" then
                if lineLower:match("#showtooltip") then
                    spellName = line:match("#[sS][hH][oO][wW][tT][oO][oO][lL][tT][iI][pP]%s+(.+)")
                    if spellName then
                        spellName = spellName:match("^%s*(.-)%s*$")
                    end
                end
            end
            
            -- Process the extracted spell name
            if spellName and spellName ~= "" and spellName ~= "?" then
                -- Remove any trailing semicolons or slashes
                spellName = spellName:match("^([^;/]+)")
                if spellName then
                    spellName = spellName:match("^%s*(.-)%s*$")
                end
                
                if spellName and spellName ~= "" then
                    -- Store the spell name (lowercase for consistent matching)
                    spellNames[spellName:lower()] = true
                    
                    -- Also try to get spell ID if possible
                    local spellInfo = C_Spell.GetSpellInfo(spellName)
                    if spellInfo and spellInfo.spellID then
                        spellIDs[spellInfo.spellID] = true
                    end
                end
            end
        end
    end
    
    return spellIDs, spellNames
end

-- Helper to process an action button and add to cache
local function ProcessActionButton(button)
    if not button then return end

    local buttonName = button:GetName()
    local action

    -- Bartender4: use LibActionButton's internal _state_action for accurate slot mapping
    -- BT4 has dynamic action slots due to buttonOffset and state paging
    if buttonName and buttonName:match("^BT4Button") then
        action = button._state_action
        -- Fallback: GetAction() returns (type, actionSlot)
        if not action and button.GetAction then
            local actionType, actionSlot = button:GetAction()
            if actionType == "action" then
                action = actionSlot
            end
        end
    else
        -- ElvUI, Dominos, default UI: standard handling (unchanged)
        action = button.action or (button.GetAction and button:GetAction())
    end

    if not action or action == 0 then return end
    
    local actionType, id = GetActionInfo(action)
    local keybind = nil
    
    if actionType == "spell" and id then
        -- Direct spell - cache by both ID and name
        keybind = keybind or GetKeybindFromActionButton(button, action)
        if keybind then
            if not spellToKeybind[id] then
                spellToKeybind[id] = keybind
            end
            -- Also cache by spell name
            local spellInfo = C_Spell.GetSpellInfo(id)
            if spellInfo and spellInfo.name then
                local nameLower = spellInfo.name:lower()
                if not spellNameToKeybind[nameLower] then
                    spellNameToKeybind[nameLower] = keybind
                end
            end
        end
    elseif actionType == "item" and id then
        -- Direct item on action bar - cache by ID and name
        keybind = keybind or GetKeybindFromActionButton(button, action)
        if keybind then
            if not itemToKeybind[id] then
                itemToKeybind[id] = keybind
            end
            -- Also cache by item name
            local itemName = C_Item.GetItemInfo(id)
            if itemName then
                local nameLower = itemName:lower()
                if not itemNameToKeybind[nameLower] then
                    itemNameToKeybind[nameLower] = keybind
                end
            end
        end
    elseif actionType == "macro" then
        keybind = keybind or GetKeybindFromActionButton(button, action)
        if not keybind then return end
        
        -- In modern WoW, GetActionInfo for macros may return the spell ID directly
        -- First, check if 'id' is a valid macro index (1-138)
        local macroName = id and GetMacroInfo(id)
        
        if macroName then
            -- Valid macro index - parse the macro for spells
            local macroSpells, macroSpellNames = ParseMacroForSpells(id)
            
            -- Cache by spell ID
            for spellID in pairs(macroSpells) do
                if not spellToKeybind[spellID] then
                    spellToKeybind[spellID] = keybind
                end
            end
            -- Cache by spell name
            for spellName in pairs(macroSpellNames) do
                if not spellNameToKeybind[spellName] then
                    spellNameToKeybind[spellName] = keybind
                end
            end
        else
            -- 'id' might be a spell ID returned by modern API
            -- Also try GetActionText to get macro/action name
            local actionText = GetActionText(action)
            
            if id and id > 0 then
                -- Treat id as a spell ID
                if not spellToKeybind[id] then
                    spellToKeybind[id] = keybind
                end
                -- Also cache by spell name
                local spellInfo = C_Spell.GetSpellInfo(id)
                if spellInfo and spellInfo.name then
                    local nameLower = spellInfo.name:lower()
                    if not spellNameToKeybind[nameLower] then
                        spellNameToKeybind[nameLower] = keybind
                    end
                end
            end
            
            -- If we have action text (macro name), use hash lookup (O(1) instead of O(138))
            if actionText and actionText ~= "" then
                local macroIndex = macroNameToIndex[actionText:lower()]
                if macroIndex then
                    local macroSpells, macroSpellNames = ParseMacroForSpells(macroIndex)
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
                end
            end
        end
    end
end

-- Build the list of action buttons ONCE (expensive _G iteration)
local function BuildActionButtonCache()
    if actionButtonsCached then return end
    
    wipe(cachedActionButtons)
    
    -- Method 1: Scan by iterating all global frames that look like action buttons
    -- This catches most action bar addons
    for globalName, frame in pairs(_G) do
        if type(globalName) == "string" and type(frame) == "table" then
            -- Skip non-widget tables (like localization tables that happen to have an "action" key)
            -- Only real WoW frames have GetObjectType as a method
            if type(frame.GetObjectType) ~= "function" then
                -- Not a WoW widget, skip
            else
                -- Check if this looks like an action button
                local isActionButton = false

                -- Check for common action button indicators
                if frame.action or (frame.GetAction and type(frame.GetAction) == "function") then
                    isActionButton = true
                end

                -- Also check by name pattern
                if not isActionButton then
                    if globalName:match("ActionButton%d+$") or
                       globalName:match("Button%d+$") and globalName:match("Bar") then
                        if frame.action or frame.GetAction then
                            isActionButton = true
                        end
                    end
                end

                if isActionButton then
                    table.insert(cachedActionButtons, frame)
                end
            end
        end
    end
    
    -- Method 2: Explicitly scan known button patterns as backup
    -- Use a lookup table for faster duplicate checking
    local addedButtons = {}
    for _, btn in ipairs(cachedActionButtons) do
        addedButtons[btn] = true
    end
    
    local buttonPrefixes = {
        -- Default Blizzard (both old and new naming conventions)
        "ActionButton",
        "MultiBarBottomLeftButton",
        "MultiBarBottomRightButton",
        "MultiBarRightButton",
        "MultiBarLeftButton",
        "MultiBar5Button",
        "MultiBar6Button",
        "MultiBar7Button",
        -- Alternate naming (ActionButton suffix)
        "MultiBarBottomLeftActionButton",
        "MultiBarBottomRightActionButton",
        "MultiBarRightActionButton",
        "MultiBarLeftActionButton",
        "MultiBar5ActionButton",
        "MultiBar6ActionButton",
        "MultiBar7ActionButton",
        -- Override bar
        "OverrideActionBarButton",
        -- Bartender
        "BT4Button",
        -- Dominos
        "DominosActionButton",
        -- ElvUI
        "ElvUI_Bar1Button",
        "ElvUI_Bar2Button",
        "ElvUI_Bar3Button",
        "ElvUI_Bar4Button",
        "ElvUI_Bar5Button",
        "ElvUI_Bar6Button",
    }
    
    -- Standard 12-button bars
    for _, prefix in ipairs(buttonPrefixes) do
        for i = 1, 12 do
            local button = _G[prefix .. i]
            if button and not addedButtons[button] then
                table.insert(cachedActionButtons, button)
                addedButtons[button] = true
            end
        end
    end
    
    -- Dominos can have up to 180 buttons (15 bars x 12 buttons)
    for i = 1, 180 do
        local button = _G["DominosActionButton" .. i]
        if button and not addedButtons[button] then
            table.insert(cachedActionButtons, button)
            addedButtons[button] = true
        end
    end

    -- Bartender4 can have up to 120 buttons (10 bars x 12 buttons)
    for i = 1, 120 do
        local button = _G["BT4Button" .. i]
        if button and not addedButtons[button] then
            table.insert(cachedActionButtons, button)
            addedButtons[button] = true
        end
    end

    -- Bartender4 pet bar buttons
    for i = 1, 10 do
        local button = _G["BT4PetButton" .. i]
        if button and not addedButtons[button] then
            table.insert(cachedActionButtons, button)
            addedButtons[button] = true
        end
    end

    -- Bartender4 stance bar buttons
    for i = 1, 10 do
        local button = _G["BT4StanceButton" .. i]
        if button and not addedButtons[button] then
            table.insert(cachedActionButtons, button)
            addedButtons[button] = true
        end
    end

    -- Sort cache so bar 1 buttons (lower numbers) are processed first
    -- This ensures bar 1 keybinds take priority when a spell is on multiple bars
    -- CRITICAL: pairs(_G) iterates in undefined order, so without sorting,
    -- bar 5 buttons might be cached before bar 1 buttons, causing wrong keybinds
    table.sort(cachedActionButtons, function(a, b)
        local nameA = (type(a.GetName) == "function") and a:GetName() or ""
        local nameB = (type(b.GetName) == "function") and b:GetName() or ""

        -- BT4 buttons: sort by button number (bar 1 = 1-12, bar 2 = 13-24, etc.)
        local numA = nameA:match("^BT4Button(%d+)$")
        local numB = nameB:match("^BT4Button(%d+)$")
        if numA and numB then
            return tonumber(numA) < tonumber(numB)
        end

        -- Dominos buttons: sort by button number
        numA = nameA:match("^DominosActionButton(%d+)$")
        numB = nameB:match("^DominosActionButton(%d+)$")
        if numA and numB then
            return tonumber(numA) < tonumber(numB)
        end

        -- ElvUI buttons: sort by bar then number
        local barA, slotA = nameA:match("^ElvUI_Bar(%d+)Button(%d+)$")
        local barB, slotB = nameB:match("^ElvUI_Bar(%d+)Button(%d+)$")
        if barA and barB then
            if barA ~= barB then return tonumber(barA) < tonumber(barB) end
            return tonumber(slotA) < tonumber(slotB)
        end

        -- Different addon types: BT4 < Dominos < ElvUI < Blizzard
        local priorityA = nameA:match("^BT4") and 1 or nameA:match("^Dominos") and 2 or nameA:match("^ElvUI") and 3 or 4
        local priorityB = nameB:match("^BT4") and 1 or nameB:match("^Dominos") and 2 or nameB:match("^ElvUI") and 3 or 4
        if priorityA ~= priorityB then
            return priorityA < priorityB
        end

        -- Fallback: keep original order
        return false
    end)

    actionButtonsCached = true
end

-- Force rebuild the button cache (useful if bars were loaded late)
local function ForceRebuildButtonCache()
    actionButtonsCached = false
    wipe(cachedActionButtons)
    BuildActionButtonCache()
end

-- Scan cached action buttons and build spell-to-keybind cache (fast)
local function RebuildCache()
    -- PERFORMANCE: Skip entirely if no keybind features are enabled
    -- This prevents CPU spikes from @mouseover macros when features are OFF
    if not IsAnyKeybindFeatureEnabled() then
        lastCacheUpdate = GetTime()  -- Mark as "fresh" to prevent repeated checks
        return
    end

    -- Skip if in combat - defer until combat ends
    if InCombatLockdown() then
        pendingRebuild = true
        return
    end

    -- Build button cache if not done yet
    if not actionButtonsCached then
        BuildActionButtonCache()
    end

    wipe(spellToKeybind)
    wipe(spellNameToKeybind)
    wipe(itemToKeybind)
    wipe(itemNameToKeybind)

    -- Build macro name → index lookup table (O(138) once, enables O(1) lookups)
    wipe(macroNameToIndex)
    for i = 1, 138 do
        local name = GetMacroInfo(i)
        if name then
            macroNameToIndex[name:lower()] = i
        end
    end

    -- Process cached buttons (fast - no _G iteration)
    for _, button in ipairs(cachedActionButtons) do
        pcall(ProcessActionButton, button)
    end

    lastCacheUpdate = GetTime()
    pendingRebuild = false
end

-- Get keybind for a spell ID (uses cache)
local function GetKeybindForSpell(spellID)
    if not spellID then return nil end
    
    -- Rebuild cache if stale
    local now = GetTime()
    if now - lastCacheUpdate > CACHE_UPDATE_INTERVAL then
        RebuildCache()
    end
    
    -- Wrap in pcall to handle "secret" spell IDs
    local ok, result = pcall(function()
        return spellToKeybind[spellID]
    end)
    
    if ok then
        return result
    end
    return nil
end

-- Get keybind for a spell name (fallback for macros)
local function GetKeybindForSpellName(spellName)
    if not spellName then return nil end
    
    -- Rebuild cache if stale
    local now = GetTime()
    if now - lastCacheUpdate > CACHE_UPDATE_INTERVAL then
        RebuildCache()
    end
    
    -- Lowercase for consistent matching (wrap in pcall for secret values)
    local ok, nameLower = pcall(function() return spellName:lower() end)
    if not ok or not nameLower then return nil end
    
    return spellNameToKeybind[nameLower]
end

-- Get keybind for an item ID (uses cache)
local function GetKeybindForItem(itemID)
    if not itemID then return nil end

    -- Rebuild cache if stale
    local now = GetTime()
    if now - lastCacheUpdate > CACHE_UPDATE_INTERVAL then
        RebuildCache()
    end

    return itemToKeybind[itemID]
end

-- Get keybind for an item name (fallback for macros with items)
local function GetKeybindForItemName(itemName)
    if not itemName then return nil end

    -- Rebuild cache if stale
    local now = GetTime()
    if now - lastCacheUpdate > CACHE_UPDATE_INTERVAL then
        RebuildCache()
    end

    -- Lowercase for consistent matching
    local ok, nameLower = pcall(function() return itemName:lower() end)
    if not ok or not nameLower then return nil end

    return itemNameToKeybind[nameLower]
end

-- Apply keybind text to a cooldown icon
local function ApplyKeybindToIcon(icon, viewerName)
    local QUICore = _G.QUI and _G.QUI.QUICore
    if not QUICore or not QUICore.db or not QUICore.db.profile then return end
    
    local settings = QUICore.db.profile.viewers[viewerName]
    if not settings then return end
    
    -- Check if keybinds should be shown
    if not settings.showKeybinds then
        if icon.keybindText then
            icon.keybindText:Hide()
        end
        return
    end
    
    -- Get spell ID from the icon (wrap in pcall to handle "secret" values)
    local spellID
    local spellName
    local ok, result = pcall(function()
        local id = icon.spellID
        if not id and icon.GetSpellID then
            id = icon:GetSpellID()
        end
        return id
    end)
    
    if ok then
        spellID = result
    end
    
    -- Try to get from action info if available
    if not spellID and icon.action then
        local actionOk, actionType, id = pcall(GetActionInfo, icon.action)
        if actionOk and actionType == "spell" then
            spellID = id
        end
    end
    
    -- Try to get spell name from icon (for fallback matching)
    -- Must validate that name is a real string (not a secret value)
    pcall(function()
        -- Try cooldownInfo first (CDM uses this)
        if icon.cooldownInfo and icon.cooldownInfo.name then
            -- Validate it's a usable string by attempting string operation
            local testOk, _ = pcall(function() return icon.cooldownInfo.name:len() end)
            if testOk then
                spellName = icon.cooldownInfo.name
            end
        end
        -- Try getting name from spell ID
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
    
    -- Get keybind for this spell (try ID first, then name, then BASE spell)
    local keybind = nil
    local baseSpellID = nil
    
    if spellID then
        keybind = GetKeybindForSpell(spellID)
        
        -- If no keybind found, try the BASE spell from cooldownInfo
        -- (CDM icons store the base spell ID even when showing evolved form)
        if not keybind and icon.cooldownInfo and icon.cooldownInfo.spellID then
            local baseFromInfo = icon.cooldownInfo.spellID
            -- Use pcall for comparison since spellID may be a secret value
            local compareOk, isDifferent = pcall(function() return baseFromInfo ~= spellID end)
            if compareOk and isDifferent then
                keybind = GetKeybindForSpell(baseFromInfo)
                if keybind then baseSpellID = baseFromInfo end
            end
        end

        -- Try C_Spell.GetBaseSpell API (evolved → base lookup)
        -- e.g., Raze → Ravage, Thunder Blast → Thunder Clap
        if not keybind and C_Spell.GetBaseSpell then
            local ok, result = pcall(C_Spell.GetBaseSpell, spellID)
            if ok and result then
                -- Use pcall for comparison since spellID may be a secret value
                local compareOk, isDifferent = pcall(function() return result ~= spellID end)
                if compareOk and isDifferent then
                    baseSpellID = result
                    keybind = GetKeybindForSpell(baseSpellID)
                end
            end
        end
    end
    
    -- Fallback: try matching by spell name (important for macros)
    if not keybind and spellName then
        keybind = GetKeybindForSpellName(spellName)
    end
    
    -- Debug output
    local debugSpellName = "?"
    pcall(function() debugSpellName = spellName or "?" end)
    
    if KEYBIND_DEBUG then
        print(string.format("|cFFFFAA00[KB Debug]|r Icon=%s spellID=%s base=%s name=%s found=%s",
            tostring(icon):sub(1,20), tostring(spellID), tostring(baseSpellID),
            tostring(debugSpellName):sub(1,15), tostring(keybind)))
    end
    
    if keybind and KEYBIND_DEBUG then
        print("|cFF00FF00[KB Debug] Using keybind:|r " .. keybind)
    end
    
    -- If no keybind at all, just hide and return
    if not keybind then
        if KEYBIND_DEBUG then
            print("|cFFFF0000[KB Debug] No keybind found, hiding|r")
        end
        if icon.keybindText then
            icon.keybindText:SetText("")
            icon.keybindText:Hide()
        end
        return
    end
    
    -- Get settings
    local fontSize = settings.keybindTextSize or 10
    local anchor = settings.keybindAnchor or "TOPLEFT"
    local offsetX = settings.keybindOffsetX or 2
    local offsetY = settings.keybindOffsetY or -2
    local textColor = settings.keybindTextColor or { 1, 1, 1, 1 }
    
    -- Create keybind text if it doesn't exist
    if not icon.keybindText then
        icon.keybindText = icon:CreateFontString(nil, "OVERLAY")
        icon.keybindText:SetShadowOffset(1, -1)
        icon.keybindText:SetShadowColor(0, 0, 0, 1)
    end
    
    -- Update position (clear and re-anchor in case anchor changed)
    icon.keybindText:ClearAllPoints()
    icon.keybindText:SetPoint(anchor, icon, anchor, offsetX, offsetY)
    
    -- Set font size
    icon.keybindText:SetFont(GetGeneralFont(), fontSize, GetGeneralFontOutline())
    
    -- Set text color
    icon.keybindText:SetTextColor(textColor[1], textColor[2], textColor[3], textColor[4] or 1)
    
    -- Set text
    if keybind then
        icon.keybindText:SetText(keybind)
        icon.keybindText:Show()
    else
        icon.keybindText:SetText("")
        icon.keybindText:Hide()
    end
end

-- Update keybinds on all icons in a viewer
local function UpdateViewerKeybinds(viewerName)
    local viewer = _G[viewerName]
    if not viewer then return end
    
    local container = viewer.viewerFrame or viewer
    local children = { container:GetChildren() }
    
    for _, child in ipairs(children) do
        if child:IsShown() then
            ApplyKeybindToIcon(child, viewerName)
        end
    end
end

-- Clear stored keybinds from all icons (called when bindings change)
local function ClearStoredKeybinds(viewerName)
    local viewer = _G[viewerName]
    if not viewer then return end
    
    local container = viewer.viewerFrame or viewer
    local children = { container:GetChildren() }
    
    for _, child in ipairs(children) do
        child._quiKeybind = nil
        child._quiKeybindSpellID = nil
    end
end

local function ClearAllStoredKeybinds()
    ClearStoredKeybinds("EssentialCooldownViewer")
    ClearStoredKeybinds("UtilityCooldownViewer")
end

-- Update keybinds on Essential and Utility viewers
local function UpdateAllKeybinds()
    -- Force cache rebuild
    lastCacheUpdate = 0
    RebuildCache()
    
    UpdateViewerKeybinds("EssentialCooldownViewer")
    UpdateViewerKeybinds("UtilityCooldownViewer")
end

-- Throttle for event-driven updates
local updatePending = false
local UPDATE_THROTTLE = 0.5 -- Don't rebuild more than once per 0.5 seconds

local function ThrottledUpdate()
    if updatePending then return end
    updatePending = true
    
    C_Timer.After(UPDATE_THROTTLE, function()
        updatePending = false
        -- Skip if in combat
        if InCombatLockdown() then
            pendingRebuild = true
            return
        end
        UpdateAllKeybinds()
    end)
end

-- Event frame for cache updates
local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ACTIONBAR_SLOT_CHANGED")
eventFrame:RegisterEvent("UPDATE_BINDINGS")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("SPELLS_CHANGED")
eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED") -- Combat ended

eventFrame:SetScript("OnEvent", function(self, event)
    -- PERFORMANCE: Skip expensive processing if no keybind features are enabled
    -- Exception: PLAYER_ENTERING_WORLD and PLAYER_REGEN_ENABLED are lightweight
    if event ~= "PLAYER_ENTERING_WORLD" and event ~= "PLAYER_REGEN_ENABLED" then
        if not IsAnyKeybindFeatureEnabled() then return end
    end

    if event == "PLAYER_REGEN_ENABLED" then
        -- Combat ended - process pending rebuild if any
        if pendingRebuild and IsAnyKeybindFeatureEnabled() then
            C_Timer.After(0.2, UpdateAllKeybinds)
        end
        return
    end

    if event == "PLAYER_ENTERING_WORLD" then
        -- Full rebuild on world enter (only if features enabled)
        C_Timer.After(0.5, function()
            if not IsAnyKeybindFeatureEnabled() then return end
            actionButtonsCached = false -- Force button cache rebuild
            wipe(iconKeybindCache) -- Clear position cache on world enter
            UpdateAllKeybinds()
        end)
        return
    end

    if event == "UPDATE_BINDINGS" or event == "ACTIONBAR_SLOT_CHANGED" then
        -- Clear stored keybinds when bindings or action bar changes
        wipe(iconKeybindCache)
        ClearAllStoredKeybinds()
    end

    -- Throttle other events
    ThrottledUpdate()
end)

-- Hook into viewer layout updates
local function HookViewerLayout(viewerName)
    local viewer = _G[viewerName]
    if not viewer then return end

    if viewer.Layout and not viewer._QUI_KeybindHooked then
        viewer._QUI_KeybindHooked = true
        hooksecurefunc(viewer, "Layout", function()
            -- PERFORMANCE: Skip if no keybind features are enabled
            if not IsAnyKeybindFeatureEnabled() then return end
            C_Timer.After(0.25, function()  -- 250ms debounce for CPU efficiency
                -- Double-check after timer (settings may have changed)
                if not IsAnyKeybindFeatureEnabled() then return end
                UpdateViewerKeybinds(viewerName)
            end)
        end)
    end
end

-- Initialize hooks when viewers are available
local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("ADDON_LOADED")
initFrame:RegisterEvent("PLAYER_ENTERING_WORLD")

initFrame:SetScript("OnEvent", function(self, event, arg)
    if event == "ADDON_LOADED" and arg == "Blizzard_CooldownManager" then
        C_Timer.After(0.5, function()
            HookViewerLayout("EssentialCooldownViewer")
            HookViewerLayout("UtilityCooldownViewer")
            -- Only do initial keybind update if features are enabled
            if IsAnyKeybindFeatureEnabled() then
                UpdateAllKeybinds()
            end
        end)
    elseif event == "PLAYER_ENTERING_WORLD" then
        C_Timer.After(1.0, function()
            HookViewerLayout("EssentialCooldownViewer")
            HookViewerLayout("UtilityCooldownViewer")
            -- Only do initial keybind update if features are enabled
            if IsAnyKeybindFeatureEnabled() then
                UpdateAllKeybinds()
            end
        end)
    end
end)

-- Export for NCDM integration (allows LayoutViewer to trigger keybind updates)
_G.QUI_UpdateViewerKeybinds = function(viewerName)
    -- PERFORMANCE: Skip if no keybind features are enabled
    if not IsAnyKeybindFeatureEnabled() then return end
    UpdateViewerKeybinds(viewerName)
end

-- Debug function to see what's in the cache
local function DebugPrintCache()
    print("|cFF56D1FF[QUI Keybinds]|r Cache contents:")
    
    -- Print spell ID cache
    print("|cFF00FF00Spell ID Cache:|r")
    local count = 0
    for spellID, keybind in pairs(spellToKeybind) do
        local spellInfo = C_Spell.GetSpellInfo(spellID)
        local spellName = spellInfo and spellInfo.name or "Unknown"
        print(string.format("  SpellID %d (%s) = %s", spellID, spellName, keybind))
        count = count + 1
        if count >= 15 then
            print("  ... and more (showing first 15)")
            break
        end
    end
    if count == 0 then
        print("  |cFFFF0000Spell ID cache is empty!|r")
    end
    
    -- Print spell name cache
    print("|cFF00FF00Spell Name Cache:|r")
    local nameCount = 0
    for spellName, keybind in pairs(spellNameToKeybind) do
        print(string.format("  '%s' = %s", spellName, keybind))
        nameCount = nameCount + 1
        if nameCount >= 15 then
            print("  ... and more (showing first 15)")
            break
        end
    end
    if nameCount == 0 then
        print("  |cFFFF0000Spell Name cache is empty!|r")
    end
    
    if count == 0 and nameCount == 0 then
        print("  Scanning for action buttons...")
        
        -- Debug: Look for any action-like buttons
        local foundButtons = {}
        for globalName, frame in pairs(_G) do
            if type(globalName) == "string" and type(frame) == "table" then
                if frame.action or (frame.GetAction and type(frame.GetAction) == "function") then
                    table.insert(foundButtons, globalName)
                    if #foundButtons >= 10 then break end
                end
            end
        end
        
        if #foundButtons > 0 then
            print("  Found action buttons: " .. table.concat(foundButtons, ", "))
        else
            print("  |cFFFF0000No action buttons found in _G!|r")
        end
    end
end

-- Debug function to test macro parsing
local function DebugMacro(macroName)
    -- Find macro by name
    local macroIndex = nil
    for i = 1, 138 do -- 120 general + 18 character-specific
        local name = GetMacroInfo(i)
        if name and name:lower() == macroName:lower() then
            macroIndex = i
            break
        end
    end
    
    if not macroIndex then
        print("|cFFFF0000Macro '" .. macroName .. "' not found!|r")
        return
    end
    
    local name, iconTexture, body = GetMacroInfo(macroIndex)
    print("|cFF56D1FF[QUI Keybinds]|r Macro Debug: " .. name)
    print("  Index: " .. macroIndex)
    print("  Body:")
    for line in body:gmatch("[^\r\n]+") do
        print("    |cFF888888" .. line .. "|r")
    end
    
    -- Test GetMacroSpell
    local simpleSpell = GetMacroSpell(macroIndex)
    if simpleSpell then
        local spellInfo = C_Spell.GetSpellInfo(simpleSpell)
        print("  GetMacroSpell: " .. simpleSpell .. " (" .. (spellInfo and spellInfo.name or "?") .. ")")
    else
        print("  GetMacroSpell: |cFFFF0000nil|r")
    end
    
    -- Test our parsing
    local spellIDs, spellNames = ParseMacroForSpells(macroIndex)
    print("  Parsed Spell IDs:")
    for id in pairs(spellIDs) do
        local info = C_Spell.GetSpellInfo(id)
        print("    " .. id .. " (" .. (info and info.name or "?") .. ")")
    end
    print("  Parsed Spell Names:")
    for spellName in pairs(spellNames) do
        print("    '" .. spellName .. "'")
    end
end

-- Debug function to find which action button has a specific macro
local function DebugFindMacro(macroName)
    -- Find macro index first
    local targetMacroIndex = nil
    for i = 1, 138 do
        local name = GetMacroInfo(i)
        if name and name:lower() == macroName:lower() then
            targetMacroIndex = i
            break
        end
    end
    
    if not targetMacroIndex then
        print("|cFFFF0000Macro '" .. macroName .. "' not found!|r")
        return
    end
    
    print("|cFF56D1FF[QUI Keybinds]|r Searching for macro '" .. macroName .. "' (index " .. targetMacroIndex .. ") on action buttons...")
    
    -- Scan ALL action buttons in _G
    local foundButtons = {}
    local scannedCount = 0
    
    for globalName, frame in pairs(_G) do
        if type(globalName) == "string" and type(frame) == "table" then
            local action = nil
            -- Safely get action value
            if type(frame.action) == "number" then
                action = frame.action
            elseif frame.GetAction and type(frame.GetAction) == "function" then
                local ok, result = pcall(function() return frame:GetAction() end)
                if ok and type(result) == "number" then
                    action = result
                end
            end
            -- Validate action is in valid range (1-180 typical for action bars)
            if action and action >= 1 and action <= 180 then
                scannedCount = scannedCount + 1
                local ok, actionType, id = pcall(GetActionInfo, action)
                if ok and actionType == "macro" and id == targetMacroIndex then
                    local keybind = GetKeybindFromActionButton(frame, action)
                    table.insert(foundButtons, {
                        name = globalName,
                        action = action,
                        keybind = keybind or "none"
                    })
                end
            end
        end
    end
    
    print("  Scanned " .. scannedCount .. " action buttons")
    
    if #foundButtons > 0 then
        print("  |cFF00FF00Found on " .. #foundButtons .. " button(s):|r")
        for _, btn in ipairs(foundButtons) do
            print("    " .. btn.name .. " (action=" .. btn.action .. ", keybind=" .. btn.keybind .. ")")
        end
        
        -- Check if these buttons are in our cache
        print("  Checking if in cachedActionButtons...")
        for _, btn in ipairs(foundButtons) do
            local inCache = false
            for _, cachedBtn in ipairs(cachedActionButtons) do
                if cachedBtn:GetName() == btn.name then
                    inCache = true
                    break
                end
            end
            print("    " .. btn.name .. ": " .. (inCache and "|cFF00FF00YES|r" or "|cFFFF0000NO|r"))
        end
    else
        print("  |cFFFF0000Not found on any action button!|r")
        print("  Is the macro placed on an action bar?")
        
        -- Check for direct macro binding
        print("  Checking for direct macro binding...")
        local macroBindingName = "MACRO " .. macroName
        local key1, key2 = GetBindingKey(macroBindingName)
        if key1 or key2 then
            print("  |cFF00FF00Found direct binding:|r " .. (key1 or "") .. " " .. (key2 or ""))
        else
            print("  No direct binding found for '" .. macroBindingName .. "'")
        end
    end
end

-- Debug function to check what a specific key is bound to
local function DebugKey(keyName)
    print("|cFF56D1FF[QUI Keybinds]|r Checking what '" .. keyName .. "' is bound to...")
    
    -- GetBindingAction returns the action bound to a key
    local action = GetBindingAction(keyName)
    if action and action ~= "" then
        print("  GetBindingAction: |cFF00FF00" .. action .. "|r")
        
        -- If it's a MULTIACTIONBAR or ACTIONBUTTON binding, find the actual button
        if action:match("BUTTON%d+$") then
            -- Try to find the frame for this binding
            local buttonNum = action:match("BUTTON(%d+)$")
            local possibleFrames = {}
            
            if action:match("^ACTIONBUTTON") then
                table.insert(possibleFrames, "ActionButton" .. buttonNum)
                table.insert(possibleFrames, "DominosActionButton" .. buttonNum)
            elseif action:match("^MULTIACTIONBAR1") then
                table.insert(possibleFrames, "MultiBarBottomLeftButton" .. buttonNum)
                table.insert(possibleFrames, "DominosActionButton" .. (12 + tonumber(buttonNum)))
            elseif action:match("^MULTIACTIONBAR2") then
                table.insert(possibleFrames, "MultiBarBottomRightButton" .. buttonNum)
                table.insert(possibleFrames, "DominosActionButton" .. (24 + tonumber(buttonNum)))
            elseif action:match("^MULTIACTIONBAR3") then
                table.insert(possibleFrames, "MultiBarRightButton" .. buttonNum)
            elseif action:match("^MULTIACTIONBAR4") then
                table.insert(possibleFrames, "MultiBarLeftButton" .. buttonNum)
            end
            
            print("  Looking for button frames...")
            for _, frameName in ipairs(possibleFrames) do
                local frame = _G[frameName]
                if frame then
                    print("    Found: " .. frameName)
                    local btnAction = frame.action or (frame.GetAction and frame:GetAction())
                    if btnAction then
                        print("      action slot = " .. tostring(btnAction))
                        local ok, actionType, id = pcall(GetActionInfo, btnAction)
                        if ok and actionType then
                            print("      type = " .. actionType .. ", id = " .. tostring(id))
                            if actionType == "macro" then
                                local macroName = GetMacroInfo(id)
                                print("      |cFF00FF00Macro: " .. (macroName or "?") .. "|r")
                            elseif actionType == "spell" then
                                local spellInfo = C_Spell.GetSpellInfo(id)
                                print("      Spell: " .. (spellInfo and spellInfo.name or "?"))
                            end
                        end
                    end
                end
            end
            
            -- Also scan ALL Dominos buttons to find which one has this binding
            print("  Scanning Dominos buttons for binding '" .. action .. "'...")
            for i = 1, 180 do
                local btn = _G["DominosActionButton" .. i]
                if btn then
                    -- Check if this button's binding matches
                    local btnName = btn:GetName()
                    local key1, key2 = GetBindingKey(action)
                    -- Check button's hotkey
                    local hotkey = btn.HotKey and btn.HotKey:GetText()
                    if hotkey and hotkey ~= "" and hotkey ~= RANGE_INDICATOR then
                        -- This button has a visible keybind
                        local btnAction = btn.action or (btn.GetAction and btn:GetAction())
                        if btnAction then
                            local ok, actionType, id = pcall(GetActionInfo, btnAction)
                            if ok and actionType == "macro" then
                                local macroName = GetMacroInfo(id)
                                if macroName and macroName:lower():match("shield") then
                                    print("    |cFF00FF00Found Shield macro on " .. btnName .. "!|r")
                                    print("      action slot = " .. btnAction)
                                    print("      hotkey text = " .. hotkey)
                                end
                            end
                        end
                    end
                end
            end
        end
    else
        print("  GetBindingAction: |cFFFF0000nothing|r")
    end
end

-- Slash command for debugging
SLASH_QUIKEYBINDS1 = "/quikeybinds"
SlashCmdList["QUIKEYBINDS"] = function(msg)
    if msg == "debug" then
        RebuildCache()
        DebugPrintCache()
    elseif msg == "refresh" then
        UpdateAllKeybinds()
        print("|cFF56D1FF[QUI Keybinds]|r Refreshed keybinds")
    elseif msg == "rebuild" then
        ForceRebuildButtonCache()
        RebuildCache()
        print("|cFF56D1FF[QUI Keybinds]|r Force rebuilt button and spell caches")
        print("  Button count: " .. #cachedActionButtons)
    elseif msg:match("^macro%s+") then
        local macroName = msg:match("^macro%s+(.+)")
        if macroName then
            DebugMacro(macroName)
        end
    elseif msg:match("^find%s+") then
        local macroName = msg:match("^find%s+(.+)")
        if macroName then
            DebugFindMacro(macroName)
        end
    elseif msg == "buttons" then
        -- Show how many action buttons we have cached
        print("|cFF56D1FF[QUI Keybinds]|r Action button cache:")
        print("  Cached: " .. (actionButtonsCached and "YES" or "NO"))
        print("  Button count: " .. #cachedActionButtons)
        local sample = {}
        for i = 1, math.min(10, #cachedActionButtons) do
            local name = cachedActionButtons[i]:GetName() or "unnamed"
            table.insert(sample, name)
        end
        if #sample > 0 then
            print("  Sample: " .. table.concat(sample, ", "))
        end
    elseif msg:match("^key%s+") then
        local keyName = msg:match("^key%s+(.+)")
        if keyName then
            DebugKey(keyName)
        end
    elseif msg == "dominos" then
        -- Scan all Dominos buttons and show macros
        print("|cFF56D1FF[QUI Keybinds]|r Scanning Dominos buttons for macros...")
        local found = 0
        for i = 1, 180 do
            local btn = _G["DominosActionButton" .. i]
            if btn then
                local btnAction = btn.action or (btn.GetAction and btn:GetAction())
                if btnAction then
                    local ok, actionType, id = pcall(GetActionInfo, btnAction)
                    if ok and actionType == "macro" then
                        local macroName = GetMacroInfo(id)
                        local hotkey = btn.HotKey and btn.HotKey:GetText()
                        print("  DominosActionButton" .. i .. ": |cFFFFFF00" .. (macroName or "?") .. "|r (slot " .. btnAction .. ", key: " .. (hotkey or "none") .. ")")
                        found = found + 1
                    end
                end
            end
        end
        print("  Found " .. found .. " macros on Dominos buttons")
    elseif msg == "bartender" then
        -- Scan all Bartender4 buttons and show macros
        print("|cFF56D1FF[QUI Keybinds]|r Scanning Bartender4 buttons for macros...")
        local found = 0
        for i = 1, 120 do
            local btn = _G["BT4Button" .. i]
            if btn then
                local btnAction = btn.action or (btn.GetAction and btn:GetAction())
                if btnAction then
                    local ok, actionType, id = pcall(GetActionInfo, btnAction)
                    if ok and actionType == "macro" then
                        local macroName = GetMacroInfo(id)
                        local hotkey = btn.HotKey and btn.HotKey:GetText()
                        if not hotkey and btn.GetHotkey then
                            local hotkeyOk, hotkeyResult = pcall(function() return btn:GetHotkey() end)
                            if hotkeyOk then hotkey = hotkeyResult end
                        end
                        print("  BT4Button" .. i .. ": |cFFFFFF00" .. (macroName or "?") .. "|r (slot " .. btnAction .. ", key: " .. (hotkey or "none") .. ")")
                        found = found + 1
                    end
                end
            end
        end
        print("  Found " .. found .. " macros on Bartender4 buttons")
    elseif msg:match("^trace%s+") then
        -- Trace a specific button by name
        local btnName = msg:match("^trace%s+(.+)")
        local btn = _G[btnName]
        if not btn then
            print("|cFFFF0000Button '" .. btnName .. "' not found!|r")
            return
        end
        print("|cFF56D1FF[QUI Keybinds]|r Tracing button: " .. btnName)
        
        -- Check if in cache
        local inCache = false
        for _, cachedBtn in ipairs(cachedActionButtons) do
            local cachedName = cachedBtn.GetName and cachedBtn:GetName()
            if cachedName and cachedName == btnName then
                inCache = true
                break
            end
        end
        print("  In cachedActionButtons: " .. (inCache and "|cFF00FF00YES|r" or "|cFFFF0000NO|r"))
        
        -- Get action
        local btnAction = btn.action or (btn.GetAction and btn:GetAction())
        print("  action slot: " .. tostring(btnAction))
        
        if btnAction then
            local ok, actionType, id = pcall(GetActionInfo, btnAction)
            if ok then
                print("  actionType: " .. tostring(actionType))
                print("  id: " .. tostring(id))
            end
        end
        
        -- Get keybind using our function
        local keybind = GetKeybindFromActionButton(btn, btnAction)
        print("  GetKeybindFromActionButton: " .. (keybind and ("|cFF00FF00" .. keybind .. "|r") or "|cFFFF0000nil|r"))
        
        -- Try various binding methods manually
        print("  Manual binding checks:")
        local hotkey = btn.HotKey and btn.HotKey:GetText()
        print("    HotKey text: " .. (hotkey or "nil"))
        
        local key1, key2 = GetBindingKey("CLICK " .. btnName .. ":LeftButton")
        print("    CLICK " .. btnName .. ":LeftButton -> " .. (key1 or "nil"))
        
        -- For MultiBar buttons, check the specific binding
        if btnName:match("^MultiBarBottomRight") then
            local num = btnName:match("Button(%d+)$")
            local bindingName = "MULTIACTIONBAR2BUTTON" .. num
            key1, key2 = GetBindingKey(bindingName)
            print("    " .. bindingName .. " -> " .. (key1 or "nil"))
        end

        -- For BT4 buttons, show detailed binding chain
        if btnName:match("^BT4Button(%d+)$") then
            local num = tonumber(btnName:match("^BT4Button(%d+)$"))
            print("  |cFFFFFF00BT4-specific checks:|r")

            -- Check _state_action (LibActionButton internal)
            local stateAction = btn._state_action
            print("    _state_action: " .. tostring(stateAction))

            -- Check CLICK :Keybind binding
            key1 = GetBindingKey("CLICK " .. btnName .. ":Keybind")
            print("    CLICK " .. btnName .. ":Keybind -> " .. (key1 or "nil"))

            -- Check GetBT4BindingName result
            local bt4BindingName = GetBT4BindingName(num)
            print("    GetBT4BindingName(" .. num .. ") -> " .. (bt4BindingName or "nil"))

            if bt4BindingName then
                key1 = GetBindingKey(bt4BindingName)
                print("    GetBindingKey(\"" .. bt4BindingName .. "\") -> " .. (key1 or "nil"))
            end

            -- For bar 1 buttons (1-12), also show action slot binding
            if num <= 12 then
                print("    |cFF00FFFFBar 1 button - checking action slot binding:|r")
                local actionSlot = stateAction or btnAction
                if actionSlot and actionSlot >= 1 and actionSlot <= 12 then
                    local slotBinding = "ACTIONBUTTON" .. actionSlot
                    key1 = GetBindingKey(slotBinding)
                    print("      Action slot " .. actionSlot .. " -> " .. slotBinding .. " -> " .. (key1 or "nil"))
                end
            end

            -- Show cache position
            for i, cachedBtn in ipairs(cachedActionButtons) do
                local cachedName = cachedBtn.GetName and cachedBtn:GetName()
                if cachedName == btnName then
                    print("    Cache position: " .. i .. " of " .. #cachedActionButtons)
                    break
                end
            end
        end
    elseif msg == "proctest" then
        -- Toggle proc debug mode
        KEYBIND_DEBUG = not KEYBIND_DEBUG
        print("|cFF56D1FF[QUI Keybinds]|r Proc debug mode: " .. (KEYBIND_DEBUG and "|cFF00FF00ON|r" or "|cFFFF0000OFF|r"))
        if KEYBIND_DEBUG then
            print("  Watch chat for keybind tracking messages when spells proc")
        end
    else
        print("|cFF56D1FF[QUI Keybinds]|r Commands:")
        print("  /quikeybinds debug - Show cache contents")
        print("  /quikeybinds refresh - Force refresh keybinds")
        print("  /quikeybinds rebuild - Force rebuild button cache")
        print("  /quikeybinds macro <name> - Debug a specific macro")
        print("  /quikeybinds find <name> - Find which button has a macro")
        print("  /quikeybinds buttons - Show cached action buttons")
        print("  /quikeybinds key <key> - Check what a key is bound to")
        print("  /quikeybinds trace <button> - Trace a specific button")
        print("  /quikeybinds dominos - Scan Dominos buttons for macros")
        print("  /quikeybinds bartender - Scan Bartender4 buttons for macros")
        print("  /quikeybinds proctest - Toggle proc debug mode")
    end
end

-- ============================================================================
-- ROTATION HELPER OVERLAY (C_AssistedCombat integration)
-- Shows a border on the CDM icon that matches the next recommended spell
-- ============================================================================

-- Create or get the rotation helper border overlay for an icon
-- Uses simple textures instead of BackdropTemplate to avoid "arithmetic on secret value" errors
-- when icons are resized during combat (GetWidth/GetHeight return secret values)
-- Border renders INSIDE the icon frame, above glow effects (frame level +15)
local function GetRotationHelperOverlay(icon)
    if icon._rotationHelperOverlay then
        return icon._rotationHelperOverlay
    end

    -- Create a simple frame for the overlay (no BackdropTemplate)
    local overlay = CreateFrame("Frame", nil, icon)
    overlay:SetAllPoints(icon)
    overlay:SetFrameLevel(icon:GetFrameLevel() + 15)  -- Above LibCustomGlow (+8)

    -- Create border textures (4 edges) - INSIDE the icon frame
    local borderSize = 2
    local borders = {}

    -- Top border (inside)
    borders.top = overlay:CreateTexture(nil, "OVERLAY")
    borders.top:SetColorTexture(0, 1, 0, 0.8)
    borders.top:SetPoint("TOPLEFT", overlay, "TOPLEFT", 0, 0)
    borders.top:SetPoint("TOPRIGHT", overlay, "TOPRIGHT", 0, 0)
    borders.top:SetHeight(borderSize)

    -- Bottom border (inside)
    borders.bottom = overlay:CreateTexture(nil, "OVERLAY")
    borders.bottom:SetColorTexture(0, 1, 0, 0.8)
    borders.bottom:SetPoint("BOTTOMLEFT", overlay, "BOTTOMLEFT", 0, 0)
    borders.bottom:SetPoint("BOTTOMRIGHT", overlay, "BOTTOMRIGHT", 0, 0)
    borders.bottom:SetHeight(borderSize)

    -- Left border (inside)
    borders.left = overlay:CreateTexture(nil, "OVERLAY")
    borders.left:SetColorTexture(0, 1, 0, 0.8)
    borders.left:SetPoint("TOPLEFT", overlay, "TOPLEFT", 0, 0)
    borders.left:SetPoint("BOTTOMLEFT", overlay, "BOTTOMLEFT", 0, 0)
    borders.left:SetWidth(borderSize)

    -- Right border (inside)
    borders.right = overlay:CreateTexture(nil, "OVERLAY")
    borders.right:SetColorTexture(0, 1, 0, 0.8)
    borders.right:SetPoint("TOPRIGHT", overlay, "TOPRIGHT", 0, 0)
    borders.right:SetPoint("BOTTOMRIGHT", overlay, "BOTTOMRIGHT", 0, 0)
    borders.right:SetWidth(borderSize)

    overlay.borders = borders

    -- Helper to set border color
    overlay.SetBorderColor = function(self, r, g, b, a)
        for _, tex in pairs(self.borders) do
            tex:SetColorTexture(r, g, b, a or 0.8)
        end
    end

    -- Helper to set border thickness
    overlay.SetBorderSize = function(self, size)
        self.borders.top:SetHeight(size)
        self.borders.bottom:SetHeight(size)
        self.borders.left:SetWidth(size)
        self.borders.right:SetWidth(size)
    end

    overlay:Hide()
    icon._rotationHelperOverlay = overlay
    return overlay
end

-- Apply rotation helper overlay to a single icon
local function ApplyRotationHelperToIcon(icon, viewerName, nextSpellID)
    local QUICore = _G.QUI and _G.QUI.QUICore
    if not QUICore or not QUICore.db or not QUICore.db.profile then return end
    
    local settings = QUICore.db.profile.viewers[viewerName]
    if not settings or not settings.showRotationHelper then
        -- Hide overlay if disabled
        if icon._rotationHelperOverlay then
            icon._rotationHelperOverlay:Hide()
        end
        return
    end
    
    -- Get the icon's spell ID
    local iconSpellID
    local ok, result = pcall(function()
        -- Try cooldownID first (CDM uses this)
        if icon.cooldownID then
            return icon.cooldownID
        end
        -- Try cooldownInfo
        if icon.cooldownInfo and icon.cooldownInfo.spellID then
            return icon.cooldownInfo.spellID
        end
        -- Try spellID
        if icon.spellID then
            return icon.spellID
        end
        return nil
    end)
    
    if ok then
        iconSpellID = result
    end
    
    if not iconSpellID then
        if icon._rotationHelperOverlay then
            icon._rotationHelperOverlay:Hide()
        end
        return
    end
    
    -- Check if this icon matches the next spell
    local isNextSpell = false
    if nextSpellID then
        -- Direct match
        if iconSpellID == nextSpellID then
            isNextSpell = true
        end
        -- Check overrideSpellID (some spells morph)
        if not isNextSpell and icon.cooldownInfo and icon.cooldownInfo.overrideSpellID then
            if icon.cooldownInfo.overrideSpellID == nextSpellID then
                isNextSpell = true
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

-- Update rotation helper on all icons in a viewer
local function UpdateViewerRotationHelper(viewerName, nextSpellID)
    local viewer = _G[viewerName]
    if not viewer then return end
    
    local container = viewer.viewerFrame or viewer
    local children = { container:GetChildren() }
    
    for _, child in ipairs(children) do
        if child:IsShown() then
            ApplyRotationHelperToIcon(child, viewerName, nextSpellID)
        end
    end
end

-- Update rotation helper on all viewers
local function UpdateAllRotationHelpers()
    -- Check if C_AssistedCombat API is available
    if not C_AssistedCombat or not C_AssistedCombat.GetNextCastSpell then
        return
    end
    
    -- Get the next recommended spell (false = don't consider GCD)
    local ok, nextSpellID = pcall(C_AssistedCombat.GetNextCastSpell, false)
    if not ok then
        nextSpellID = nil
    end
    
    -- Only update if the spell changed
    if nextSpellID == lastNextSpellID then
        return
    end
    lastNextSpellID = nextSpellID
    
    UpdateViewerRotationHelper("EssentialCooldownViewer", nextSpellID)
    UpdateViewerRotationHelper("UtilityCooldownViewer", nextSpellID)
end

-- Check if rotation helper should be running
local function ShouldRunRotationHelper()
    local QUICore = _G.QUI and _G.QUI.QUICore
    if not QUICore or not QUICore.db or not QUICore.db.profile then return false end
    
    local viewers = QUICore.db.profile.viewers
    if not viewers then return false end
    
    local essential = viewers.EssentialCooldownViewer
    local utility = viewers.UtilityCooldownViewer
    
    return (essential and essential.showRotationHelper) or (utility and utility.showRotationHelper)
end

-- Rotation helper ticker interval (Performance: uses ticker instead of OnUpdate)
local ROTATION_HELPER_INTERVAL = 0.1 -- Update every 100ms

local function StartRotationHelperTicker()
    if rotationHelperTicker then rotationHelperTicker:Cancel() end
    rotationHelperTicker = C_Timer.NewTicker(ROTATION_HELPER_INTERVAL, function()
        if not rotationHelperEnabled then return end
        if not ShouldRunRotationHelper() then return end
        UpdateAllRotationHelpers()
    end)
end

local function StopRotationHelperTicker()
    if rotationHelperTicker then
        rotationHelperTicker:Cancel()
        rotationHelperTicker = nil
    end
end

-- Start/stop rotation helper based on settings
local function RefreshRotationHelper()
    rotationHelperEnabled = ShouldRunRotationHelper()

    if not rotationHelperEnabled then
        -- Hide all overlays and stop ticker
        lastNextSpellID = nil
        UpdateViewerRotationHelper("EssentialCooldownViewer", nil)
        UpdateViewerRotationHelper("UtilityCooldownViewer", nil)
        StopRotationHelperTicker()
    else
        -- Start ticker when enabled
        StartRotationHelperTicker()
    end
end

-- Initialize rotation helper when entering world
local rotationHelperInitFrame = CreateFrame("Frame")
rotationHelperInitFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
rotationHelperInitFrame:SetScript("OnEvent", function()
    C_Timer.After(1.0, RefreshRotationHelper)
end)

-- Export functions
QUI.Keybinds = {
    UpdateAll = UpdateAllKeybinds,
    UpdateViewer = UpdateViewerKeybinds,
    GetKeybindForSpell = GetKeybindForSpell,
    GetKeybindForSpellName = GetKeybindForSpellName,
    GetKeybindForItem = GetKeybindForItem,
    GetKeybindForItemName = GetKeybindForItemName,
    RebuildCache = RebuildCache,
    DebugPrintCache = DebugPrintCache,
    RefreshRotationHelper = RefreshRotationHelper,
    UpdateAllRotationHelpers = UpdateAllRotationHelpers,
}

-- Global refresh function for config panel
_G.QUI_RefreshKeybinds = UpdateAllKeybinds
_G.QUI_RefreshRotationHelper = RefreshRotationHelper

