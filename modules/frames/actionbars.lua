--[[
    QUI Action Bars - Button Skinning and Fade System
    Hooks Blizzard action buttons for visual customization
]]

local ADDON_NAME, ns = ...
local LSM = LibStub("LibSharedMedia-3.0")

---------------------------------------------------------------------------
-- MIDNIGHT (12.0+) DETECTION
---------------------------------------------------------------------------

local IS_MIDNIGHT = select(4, GetBuildInfo()) >= 120000

---------------------------------------------------------------------------
-- CONSTANTS
---------------------------------------------------------------------------

-- In-housed textures (self-contained, no external dependencies)
local TEXTURE_PATH = [[Interface\AddOns\QUI\assets\iconskin\]]
local TEXTURES = {
    normal = TEXTURE_PATH .. "Normal",       -- Black border frame
    gloss = TEXTURE_PATH .. "Gloss",         -- ADD blend shine
    highlight = TEXTURE_PATH .. "Highlight", -- Hover state
    pushed = TEXTURE_PATH .. "Pushed",       -- Click state
    checked = TEXTURE_PATH .. "Checked",     -- Selected state
    flash = TEXTURE_PATH .. "Flash",         -- Ready flash
}

-- Icon texture coordinates (crop transparent edges)
local ICON_TEXCOORD = {0.07, 0.93, 0.07, 0.93}

-- Blizzard's range indicator placeholder (to detect and hide)
local RANGE_INDICATOR = RANGE_INDICATOR or "●"

-- Bar frame name mappings
local BAR_FRAMES = {
    bar1 = "MainMenuBar",
    bar2 = "MultiBarBottomLeft",
    bar3 = "MultiBarBottomRight",
    bar4 = "MultiBarRight",
    bar5 = "MultiBarLeft",
    bar6 = "MultiBar5",
    bar7 = "MultiBar6",
    bar8 = "MultiBar7",
    pet = "PetActionBar",
    stance = "StanceBar",
    -- Non-standard bars (special handling in GetBarButtons)
    microbar = "MicroMenuContainer",
    bags = "BagsBar",
    extraActionButton = "ExtraActionBarFrame",  -- Boss encounters, quests
    zoneAbility = "ZoneAbilityFrame",          -- Garrison, covenant, zone powers
}

-- Button name patterns for each bar
local BUTTON_PATTERNS = {
    bar1 = "ActionButton%d",
    bar2 = "MultiBarBottomLeftButton%d",
    bar3 = "MultiBarBottomRightButton%d",
    bar4 = "MultiBarRightButton%d",
    bar5 = "MultiBarLeftButton%d",
    bar6 = "MultiBar5Button%d",
    bar7 = "MultiBar6Button%d",
    bar8 = "MultiBar7Button%d",
    pet = "PetActionButton%d",
    stance = "StanceButton%d",
}

-- Button counts per bar
local BUTTON_COUNTS = {
    bar1 = 12, bar2 = 12, bar3 = 12, bar4 = 12, bar5 = 12,
    bar6 = 12, bar7 = 12, bar8 = 12, pet = 10, stance = 10,
}

-- Binding command prefixes for LibKeyBound integration
local BINDING_COMMANDS = {
    bar1 = "ACTIONBUTTON",           -- ACTIONBUTTON1-12
    bar2 = "MULTIACTIONBAR1BUTTON",  -- MULTIACTIONBAR1BUTTON1-12
    bar3 = "MULTIACTIONBAR2BUTTON",  -- MULTIACTIONBAR2BUTTON1-12
    bar4 = "MULTIACTIONBAR3BUTTON",  -- MULTIACTIONBAR3BUTTON1-12
    bar5 = "MULTIACTIONBAR4BUTTON",  -- MULTIACTIONBAR4BUTTON1-12
    bar6 = "MULTIACTIONBAR5BUTTON",  -- MULTIACTIONBAR5BUTTON1-12
    bar7 = "MULTIACTIONBAR6BUTTON",  -- MULTIACTIONBAR6BUTTON1-12
    bar8 = "MULTIACTIONBAR7BUTTON",  -- MULTIACTIONBAR7BUTTON1-12
    pet = "BONUSACTIONBUTTON",       -- BONUSACTIONBUTTON1-10
    stance = "SHAPESHIFTBUTTON",     -- SHAPESHIFTBUTTON1-10
}

---------------------------------------------------------------------------
-- MODULE STATE
---------------------------------------------------------------------------

local ActionBars = {
    initialized = false,
    skinnedButtons = {},        -- Track which buttons have been skinned
    fadeState = {},             -- Per-bar fade state tracking
    fadeFrame = nil,            -- OnUpdate frame for smooth fading
}

---------------------------------------------------------------------------
-- HELPER FUNCTIONS
---------------------------------------------------------------------------

-- Safe wrapper for HasAction which may return secret values in Midnight
local function SafeHasAction(action)
    if IS_MIDNIGHT then
        local ok, result = pcall(function()
            local has = HasAction(action)
            -- Force comparison to detect secrets
            if has then return true end
            return false
        end)
        if not ok then return true end  -- Secret value, treat as having action
        return result
    else
        return HasAction(action)
    end
end

-- DB accessor using shared helpers
local Helpers = ns.Helpers
local GetDB = Helpers.CreateDBGetter("actionBars")

local function GetGlobalSettings()
    local db = GetDB()
    return db and db.global
end

local function GetBarSettings(barKey)
    local db = GetDB()
    return db and db.bars and db.bars[barKey]
end

local function GetFadeSettings()
    local db = GetDB()
    return db and db.fade
end

-- Determine bar key from button name
local function GetBarKeyFromButton(button)
    local name = button and button:GetName()
    if not name then return nil end

    if name:match("^ActionButton%d+$") then return "bar1" end
    if name:match("^MultiBarBottomLeftButton%d+$") then return "bar2" end
    if name:match("^MultiBarBottomRightButton%d+$") then return "bar3" end
    if name:match("^MultiBarRightButton%d+$") then return "bar4" end
    if name:match("^MultiBarLeftButton%d+$") then return "bar5" end
    if name:match("^MultiBar5Button%d+$") then return "bar6" end
    if name:match("^MultiBar6Button%d+$") then return "bar7" end
    if name:match("^MultiBar7Button%d+$") then return "bar8" end
    if name:match("^PetActionButton%d+$") then return "pet" end
    if name:match("^StanceButton%d+$") then return "stance" end
    return nil
end

-- Get button index from button name
local function GetButtonIndex(button)
    local name = button and button:GetName()
    if not name then return nil end
    return tonumber(name:match("%d+$"))
end

-- Add LibKeyBound methods to a button for mousewheel binding support
local function AddKeybindMethods(button, barKey)
    if not button or button._quiKeybindMethods then return end

    local bindingPrefix = BINDING_COMMANDS[barKey]
    if not bindingPrefix then return end

    local buttonIndex = GetButtonIndex(button)
    if not buttonIndex then return end

    local bindingCommand = bindingPrefix .. buttonIndex
    button._quiBindingCommand = bindingCommand
    button._quiKeybindMethods = true

    -- Required method: Returns current keybind text
    function button:GetHotkey()
        local key = GetBindingKey(self._quiBindingCommand)
        if key then
            local LibKeyBound = LibStub("LibKeyBound-1.0", true)
            return LibKeyBound and LibKeyBound:ToShortKey(key) or key
        end
        return nil
    end

    -- Required method: Binds a key to this button
    function button:SetKey(key)
        if InCombatLockdown() then return end
        SetBinding(key, self._quiBindingCommand)
    end

    -- Optional method: Returns all bindings as comma-separated string
    function button:GetBindings()
        local keys = {}
        for i = 1, select("#", GetBindingKey(self._quiBindingCommand)) do
            local key = select(i, GetBindingKey(self._quiBindingCommand))
            if key then
                table.insert(keys, key)
            end
        end
        return #keys > 0 and table.concat(keys, ", ") or nil
    end

    -- Optional method: Clears all bindings from this button
    function button:ClearBindings()
        if InCombatLockdown() then return end
        while GetBindingKey(self._quiBindingCommand) do
            SetBinding(GetBindingKey(self._quiBindingCommand), nil)
        end
    end

    -- Optional method: Returns display name for what we're binding
    function button:GetActionName()
        return self._quiBindingCommand
    end
end

-- Get effective settings for a bar (merges global with per-bar overrides)
local function GetEffectiveSettings(barKey)
    local global = GetGlobalSettings()
    if not global then return nil end

    local barSettings = GetBarSettings(barKey)

    -- If overrides are disabled or bar doesn't support overrides, use global
    if not barSettings or not barSettings.overrideEnabled then
        return global
    end

    -- Merge: global as base, bar-specific overrides non-nil values
    local effective = {}
    for key, value in pairs(global) do
        effective[key] = value
    end

    -- Override with bar-specific values (only if not nil)
    local overrideKeys = {
        "iconZoom", "showBackdrop", "backdropAlpha", "showGloss", "glossAlpha",
        "showKeybinds", "hideEmptyKeybinds", "keybindFontSize", "keybindColor",
        "keybindAnchor", "keybindOffsetX", "keybindOffsetY",
        "showMacroNames", "macroNameFontSize", "macroNameColor",
        "macroNameAnchor", "macroNameOffsetX", "macroNameOffsetY",
        "showCounts", "countFontSize", "countColor",
        "countAnchor", "countOffsetX", "countOffsetY",
    }

    for _, key in ipairs(overrideKeys) do
        if barSettings[key] ~= nil then
            effective[key] = barSettings[key]
        end
    end

    return effective
end

-- Get buttons for a specific bar
local function GetBarButtons(barKey)
    local buttons = {}

    -- Special handling for non-standard bars
    if barKey == "microbar" then
        -- MicroMenu contains the micro buttons (Character, Spellbook, etc.)
        if MicroMenu then
            for _, child in ipairs({MicroMenu:GetChildren()}) do
                if child.IsObjectType and child:IsObjectType("Button") then
                    table.insert(buttons, child)
                end
            end
        end
        return buttons
    elseif barKey == "bags" then
        -- Bag slots: backpack + 4 bag slots + reagent bag
        if MainMenuBarBackpackButton then
            table.insert(buttons, MainMenuBarBackpackButton)
        end
        for i = 0, 3 do
            local slot = _G["CharacterBag" .. i .. "Slot"]
            if slot then table.insert(buttons, slot) end
        end
        if CharacterReagentBag0Slot then
            table.insert(buttons, CharacterReagentBag0Slot)
        end
        return buttons
    elseif barKey == "extraActionButton" then
        -- Extra Action Button (boss encounters, quests)
        if ExtraActionBarFrame and ExtraActionBarFrame.button then
            table.insert(buttons, ExtraActionBarFrame.button)
        end
        return buttons
    elseif barKey == "zoneAbility" then
        -- Zone Ability buttons (garrison, covenant, zone powers)
        if ZoneAbilityFrame and ZoneAbilityFrame.SpellButtonContainer then
            for button in ZoneAbilityFrame.SpellButtonContainer:EnumerateActive() do
                table.insert(buttons, button)
            end
        end
        return buttons
    end

    -- Standard bars with numbered buttons
    local pattern = BUTTON_PATTERNS[barKey]
    local count = BUTTON_COUNTS[barKey] or 12

    if not pattern then return buttons end

    for i = 1, count do
        local buttonName = string.format(pattern, i)
        local button = _G[buttonName]
        if button then
            table.insert(buttons, button)
        end
    end

    return buttons
end

-- Get the bar container frame
local function GetBarFrame(barKey)
    local frameName = BAR_FRAMES[barKey]
    return frameName and _G[frameName]
end

---------------------------------------------------------------------------
-- EXTRA BUTTON CUSTOMIZATION (Extra Action Button & Zone Ability)
---------------------------------------------------------------------------

local extraActionHolder = nil
local extraActionMover = nil
local zoneAbilityHolder = nil
local zoneAbilityMover = nil
local extraButtonMoversVisible = false

-- Get settings for a specific extra button type
local function GetExtraButtonDB(buttonType)
    local QUICore = _G.QUI and _G.QUI.QUICore
    if not QUICore or not QUICore.db or not QUICore.db.profile then return nil end
    return QUICore.db.profile.actionBars and QUICore.db.profile.actionBars.bars
        and QUICore.db.profile.actionBars.bars[buttonType]
end

-- Create holder frame and mover overlay for an extra button type
local function CreateExtraButtonHolder(buttonType, displayName)
    local settings = GetExtraButtonDB(buttonType)
    if not settings then return nil, nil end

    -- Create holder frame
    local holder = CreateFrame("Frame", "QUI_" .. buttonType .. "Holder", UIParent)
    holder:SetSize(64, 64)
    holder:SetMovable(true)
    holder:SetClampedToScreen(true)

    -- Load saved position or default to center-bottom
    local pos = settings.position
    if pos and pos.point then
        holder:SetPoint(pos.point, UIParent, pos.relPoint or pos.point, pos.x or 0, pos.y or 0)
    else
        -- Default positions: Extra Action left of center, Zone Ability right of center
        if buttonType == "extraActionButton" then
            holder:SetPoint("CENTER", UIParent, "CENTER", -100, -200)
        else
            holder:SetPoint("CENTER", UIParent, "CENTER", 100, -200)
        end
    end

    -- Create mover overlay (visible only when toggled)
    local mover = CreateFrame("Frame", "QUI_" .. buttonType .. "Mover", holder, "BackdropTemplate")
    mover:SetAllPoints(holder)
    mover:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 2,
    })
    mover:SetBackdropColor(0.2, 0.8, 0.6, 0.5)  -- QUI mint color
    mover:SetBackdropBorderColor(0.2, 1.0, 0.6, 1)
    mover:EnableMouse(true)
    mover:SetMovable(true)
    mover:RegisterForDrag("LeftButton")
    mover:SetFrameStrata("FULLSCREEN_DIALOG")
    mover:Hide()

    -- Label text
    local text = mover:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    text:SetPoint("CENTER")
    text:SetText(displayName)
    mover.text = text

    -- Drag handlers
    mover:SetScript("OnDragStart", function(self)
        holder:StartMoving()
    end)

    mover:SetScript("OnDragStop", function(self)
        holder:StopMovingOrSizing()
        local point, _, relPoint, x, y = holder:GetPoint()
        local db = GetExtraButtonDB(buttonType)
        if db then
            db.position = { point = point, relPoint = relPoint, x = x, y = y }
        end
    end)

    return holder, mover
end

-- Apply settings (scale, position, artwork) to an extra button frame
local function ApplyExtraButtonSettings(buttonType)
    if InCombatLockdown() then
        ActionBars.pendingExtraButtonRefresh = true
        return
    end

    local settings = GetExtraButtonDB(buttonType)
    if not settings or not settings.enabled then return end

    local blizzFrame
    local holder, mover

    if buttonType == "extraActionButton" then
        blizzFrame = ExtraActionBarFrame
        holder = extraActionHolder
        mover = extraActionMover
    else
        blizzFrame = ZoneAbilityFrame
        holder = zoneAbilityHolder
        mover = zoneAbilityMover
    end

    if not blizzFrame or not holder then return end

    -- Apply scale
    local scale = settings.scale or 1.0
    blizzFrame:SetScale(scale)

    -- Apply offsets (relative to holder position)
    local offsetX = settings.offsetX or 0
    local offsetY = settings.offsetY or 0

    -- Reparent to our holder and position
    blizzFrame:SetParent(holder)
    blizzFrame:ClearAllPoints()
    blizzFrame:SetPoint("CENTER", holder, "CENTER", offsetX, offsetY)

    -- Update holder size to match scaled frame
    local width = (blizzFrame:GetWidth() or 64) * scale
    local height = (blizzFrame:GetHeight() or 64) * scale
    holder:SetSize(math.max(width, 64), math.max(height, 64))

    -- Hide artwork if enabled
    if settings.hideArtwork then
        if buttonType == "extraActionButton" and blizzFrame.button and blizzFrame.button.style then
            blizzFrame.button.style:SetAlpha(0)
        end
        if buttonType == "zoneAbility" and blizzFrame.Style then
            blizzFrame.Style:SetAlpha(0)
        end
    else
        -- Restore artwork
        if buttonType == "extraActionButton" and blizzFrame.button and blizzFrame.button.style then
            blizzFrame.button.style:SetAlpha(1)
        end
        if buttonType == "zoneAbility" and blizzFrame.Style then
            blizzFrame.Style:SetAlpha(1)
        end
    end

    -- Reset frame alpha if fade is not enabled (fixes toggling fade off without reload)
    if not settings.fadeEnabled then
        blizzFrame:SetAlpha(1)
    end
end

-- Flag to prevent recursive SetPoint hooks
local hookingSetPoint = false

-- Hook Blizzard frames to prevent them from repositioning
local function HookExtraButtonPositioning()
    -- Hook ExtraActionBarFrame
    if ExtraActionBarFrame and not ExtraActionBarFrame._quiHooked then
        ExtraActionBarFrame._quiHooked = true
        hooksecurefunc(ExtraActionBarFrame, "SetPoint", function(self)
            if hookingSetPoint or InCombatLockdown() then return end
            if extraActionHolder and GetExtraButtonDB("extraActionButton") then
                local settings = GetExtraButtonDB("extraActionButton")
                if settings and settings.enabled then
                    hookingSetPoint = true
                    self:ClearAllPoints()
                    self:SetPoint("CENTER", extraActionHolder, "CENTER",
                        settings.offsetX or 0, settings.offsetY or 0)
                    hookingSetPoint = false
                end
            end
        end)
    end

    -- Hook ZoneAbilityFrame
    if ZoneAbilityFrame and not ZoneAbilityFrame._quiHooked then
        ZoneAbilityFrame._quiHooked = true
        hooksecurefunc(ZoneAbilityFrame, "SetPoint", function(self)
            if hookingSetPoint or InCombatLockdown() then return end
            if zoneAbilityHolder and GetExtraButtonDB("zoneAbility") then
                local settings = GetExtraButtonDB("zoneAbility")
                if settings and settings.enabled then
                    hookingSetPoint = true
                    self:ClearAllPoints()
                    self:SetPoint("CENTER", zoneAbilityHolder, "CENTER",
                        settings.offsetX or 0, settings.offsetY or 0)
                    hookingSetPoint = false
                end
            end
        end)
    end

    -- NOTE: Previously attempted to remove ExtraAbilityContainer from UIParentBottomManagedFrameContainer.showingFrames
    -- to prevent Edit Mode interference. However, modifying Blizzard's internal showingFrames table spreads taint
    -- to the entire UIParent frame management system, causing ADDON_ACTION_BLOCKED errors during combat
    -- when PetActionBar or other secure frames update. The Edit Mode interference is a minor cosmetic issue;
    -- the combat taint errors are game-breaking. Removed the problematic code.
end

-- Show/hide mover overlays
local function ShowExtraButtonMovers()
    extraButtonMoversVisible = true
    if extraActionMover then extraActionMover:Show() end
    if zoneAbilityMover then zoneAbilityMover:Show() end
end

local function HideExtraButtonMovers()
    extraButtonMoversVisible = false
    if extraActionMover then extraActionMover:Hide() end
    if zoneAbilityMover then zoneAbilityMover:Hide() end
end

local function ToggleExtraButtonMovers()
    if extraButtonMoversVisible then
        HideExtraButtonMovers()
    else
        ShowExtraButtonMovers()
    end
end

-- Initialize extra button holders
local function InitializeExtraButtons()
    if InCombatLockdown() then
        ActionBars.pendingExtraButtonInit = true
        return
    end

    -- Create holder frames
    extraActionHolder, extraActionMover = CreateExtraButtonHolder("extraActionButton", "Extra Action Button")
    zoneAbilityHolder, zoneAbilityMover = CreateExtraButtonHolder("zoneAbility", "Zone Ability")

    -- Apply settings with delay to ensure Blizzard frames exist
    C_Timer.After(0.5, function()
        ApplyExtraButtonSettings("extraActionButton")
        ApplyExtraButtonSettings("zoneAbility")
        HookExtraButtonPositioning()
    end)
end

-- Refresh extra button settings (called from options)
local function RefreshExtraButtons()
    if InCombatLockdown() then
        ActionBars.pendingExtraButtonRefresh = true
        return
    end
    ApplyExtraButtonSettings("extraActionButton")
    ApplyExtraButtonSettings("zoneAbility")
end

-- Expose global functions for options panel
_G.QUI_ToggleExtraButtonMovers = ToggleExtraButtonMovers
_G.QUI_RefreshExtraButtons = RefreshExtraButtons

-- Strip WoW color codes from text
local function StripColorCodes(text)
    if not text then return "" end
    return text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
end

-- Check if keybind text is valid (not empty or placeholder)
local function IsValidKeybindText(text)
    if not text or text == "" then return false end

    local stripped = StripColorCodes(text)
    if stripped == "" then return false end
    if stripped == RANGE_INDICATOR then return false end
    if stripped == "[]" then return false end

    return true
end

---------------------------------------------------------------------------
-- BUTTON SKINNING
---------------------------------------------------------------------------

-- Remove Blizzard's default textures and masks
local function StripBlizzardArtwork(button)
    if button._quiStripped then return end
    button._quiStripped = true

    -- Hide NormalTexture (Blizzard's border)
    local normalTex = button:GetNormalTexture()
    if normalTex then
        normalTex:SetAlpha(0)
    end
    if button.NormalTexture then
        button.NormalTexture:SetAlpha(0)
    end

    -- Remove mask textures from icon
    local icon = button.icon or button.Icon
    if icon and icon.GetMaskTexture and icon.RemoveMaskTexture then
        for i = 1, 10 do
            local mask = icon:GetMaskTexture(i)
            if mask then
                icon:RemoveMaskTexture(mask)
            end
        end
    end

    -- Hide FloatingBG if present
    if button.FloatingBG then
        button.FloatingBG:SetAlpha(0)
    end

    -- Hide SlotBackground if present
    if button.SlotBackground then
        button.SlotBackground:SetAlpha(0)
    end

    -- Hide SlotArt if present
    if button.SlotArt then
        button.SlotArt:SetAlpha(0)
    end
end

---------------------------------------------------------------------------
-- BUTTON SKINNING
---------------------------------------------------------------------------

-- Apply QUI skin to a single button
local function SkinButton(button, settings)
    if not button or not settings or not settings.skinEnabled then return end

    -- Skip if already skinned with same settings
    local settingsKey = string.format("%d_%.2f_%s_%.2f_%s_%.2f",
        settings.iconSize or 36,
        settings.iconZoom or 0.07,
        tostring(settings.showBackdrop),
        settings.backdropAlpha or 0.8,
        tostring(settings.showGloss),
        settings.glossAlpha or 0.6
    )
    if button._quiSkinKey == settingsKey then return end
    button._quiSkinKey = settingsKey

    -- Strip Blizzard artwork first
    StripBlizzardArtwork(button)

    local iconSize = settings.iconSize or 36
    local zoom = settings.iconZoom or 0.07

    -- Apply icon TexCoords (crop transparent edges)
    local icon = button.icon or button.Icon
    if icon then
        icon:SetTexCoord(zoom, 1 - zoom, zoom, 1 - zoom)
        icon:ClearAllPoints()
        icon:SetAllPoints(button)
    end

    -- Create or update backdrop (behind icon, configurable opacity)
    if settings.showBackdrop then
        if not button._quiBackdrop then
            button._quiBackdrop = button:CreateTexture(nil, "BACKGROUND", nil, -8)
            button._quiBackdrop:SetColorTexture(0, 0, 0, 1)
        end
        button._quiBackdrop:SetAlpha(settings.backdropAlpha or 0.8)
        button._quiBackdrop:ClearAllPoints()
        button._quiBackdrop:SetAllPoints(button)  -- Same size as button, not extending beyond
        button._quiBackdrop:Show()
    elseif button._quiBackdrop then
        button._quiBackdrop:Hide()
    end

    -- Create or update Normal overlay (border frame texture)
    if settings.showBorders ~= false then
        if not button._quiNormal then
            button._quiNormal = button:CreateTexture(nil, "OVERLAY", nil, 1)
            button._quiNormal:SetTexture(TEXTURES.normal)
            button._quiNormal:SetVertexColor(0, 0, 0, 1)
        end
        button._quiNormal:SetSize(iconSize, iconSize)
        button._quiNormal:ClearAllPoints()
        button._quiNormal:SetAllPoints(button)
        button._quiNormal:Show()
    elseif button._quiNormal then
        button._quiNormal:Hide()
    end

    -- Create or update Gloss overlay (ADD blend shine)
    if settings.showGloss then
        if not button._quiGloss then
            button._quiGloss = button:CreateTexture(nil, "OVERLAY", nil, 2)
            button._quiGloss:SetTexture(TEXTURES.gloss)
            button._quiGloss:SetBlendMode("ADD")
        end
        button._quiGloss:SetVertexColor(1, 1, 1, settings.glossAlpha or 0.6)
        button._quiGloss:SetAllPoints(button)
        button._quiGloss:Show()
    elseif button._quiGloss then
        button._quiGloss:Hide()
    end

    -- Fix Cooldown frame positioning
    local cooldown = button.cooldown or button.Cooldown
    if cooldown then
        cooldown:ClearAllPoints()
        cooldown:SetAllPoints(button)
    end

    ActionBars.skinnedButtons[button] = true
end

---------------------------------------------------------------------------
-- TEXT VISIBILITY
---------------------------------------------------------------------------

-- Update keybind/hotkey text visibility and styling
-- Directly modifies Blizzard's HotKey element with abbreviated text
local function UpdateKeybindText(button, settings)
    local hotkey = button.HotKey or button.hotKey
    if not hotkey then return end

    -- Determine if keybinds should be shown
    if not settings.showKeybinds then
        hotkey:SetAlpha(0)
        hotkey:Hide()
        return
    end

    -- Get abbreviated keybind text
    local buttonName = button:GetName()
    local bindingName = nil
    local abbreviated = nil

    if buttonName then
        local num

        -- Map button frame names to WoW binding names
        num = buttonName:match("^ActionButton(%d+)$")
        if num then bindingName = "ACTIONBUTTON" .. num end

        if not bindingName then
            num = buttonName:match("^MultiBarBottomRightButton(%d+)$")
            if num then bindingName = "MULTIACTIONBAR2BUTTON" .. num end
        end

        if not bindingName then
            num = buttonName:match("^MultiBarBottomLeftButton(%d+)$")
            if num then bindingName = "MULTIACTIONBAR1BUTTON" .. num end
        end

        if not bindingName then
            num = buttonName:match("^MultiBarRightButton(%d+)$")
            if num then bindingName = "MULTIACTIONBAR3BUTTON" .. num end
        end

        if not bindingName then
            num = buttonName:match("^MultiBarLeftButton(%d+)$")
            if num then bindingName = "MULTIACTIONBAR4BUTTON" .. num end
        end

        -- MultiBar5-7 (Midnight bars)
        if not bindingName then
            num = buttonName:match("^MultiBar5Button(%d+)$")
            if num then bindingName = "MULTIACTIONBAR5BUTTON" .. num end
        end

        if not bindingName then
            num = buttonName:match("^MultiBar6Button(%d+)$")
            if num then bindingName = "MULTIACTIONBAR6BUTTON" .. num end
        end

        if not bindingName then
            num = buttonName:match("^MultiBar7Button(%d+)$")
            if num then bindingName = "MULTIACTIONBAR7BUTTON" .. num end
        end

        -- Get keybind and abbreviate
        if bindingName then
            local key = GetBindingKey(bindingName)
            if key and ns and ns.FormatKeybind then
                abbreviated = ns.FormatKeybind(key)
            end
        end
    end

    -- Determine visibility
    local shouldShow = abbreviated and abbreviated ~= ""

    -- Only hide keybinds on empty action slots when hideEmptyKeybinds is enabled
    if shouldShow and settings.hideEmptyKeybinds then
        if button.action then
            local hasAction = SafeHasAction(button.action)
            if not hasAction then
                shouldShow = false
            end
        end
    end

    if not shouldShow then
        hotkey:SetAlpha(0)
        hotkey:Hide()
        return
    end

    -- Set the abbreviated text and show
    hotkey:SetText(abbreviated)
    hotkey:Show()
    hotkey:SetAlpha(1)

    -- Apply styling
    local fontPath = "Fonts\\FRIZQT__.TTF"
    local outline = "OUTLINE"
    local QUICore = _G.QUI and _G.QUI.QUICore
    if QUICore and QUICore.db and QUICore.db.profile and QUICore.db.profile.general then
        local general = QUICore.db.profile.general
        if general.font and LSM then
            fontPath = LSM:Fetch("font", general.font) or fontPath
        end
        outline = general.fontOutline or outline
    end

    hotkey:SetFont(fontPath, settings.keybindFontSize or 11, outline)

    local color = settings.keybindColor
    local r = color and color[1] or 1
    local g = color and color[2] or 1
    local b = color and color[3] or 1
    local a = color and color[4] or 1
    hotkey:SetTextColor(r, g, b, a)

    -- Reposition with configurable anchor and offsets
    hotkey:ClearAllPoints()
    local anchor = settings.keybindAnchor or "TOPRIGHT"
    hotkey:SetPoint(anchor, button, anchor, (settings.keybindOffsetX or 0), (settings.keybindOffsetY or 0))
end

-- Update macro name text visibility and styling
local function UpdateMacroText(button, settings)
    local name = button.Name
    if not name then return end

    if not settings.showMacroNames then
        name:SetAlpha(0)
        return
    end

    name:SetAlpha(1)

    -- Apply styling
    local fontPath = "Fonts\\FRIZQT__.TTF"
    local outline = "OUTLINE"
    local QUICore = _G.QUI and _G.QUI.QUICore
    if QUICore and QUICore.db and QUICore.db.profile and QUICore.db.profile.general then
        local general = QUICore.db.profile.general
        if general.font and LSM then
            fontPath = LSM:Fetch("font", general.font) or fontPath
        end
        outline = general.fontOutline or outline
    end

    name:SetFont(fontPath, settings.macroNameFontSize or 10, outline)

    local color = settings.macroNameColor
    local r = color and color[1] or 1
    local g = color and color[2] or 1
    local b = color and color[3] or 1
    local a = color and color[4] or 1
    name:SetTextColor(r, g, b, a)

    -- Reposition with configurable anchor and offsets
    name:ClearAllPoints()
    local anchor = settings.macroNameAnchor or "BOTTOM"
    name:SetPoint(anchor, button, anchor, (settings.macroNameOffsetX or 0), (settings.macroNameOffsetY or 0))
end

-- Update count/charge text visibility and styling
local function UpdateCountText(button, settings)
    local count = button.Count
    if not count then return end

    if not settings.showCounts then
        count:SetAlpha(0)
        return
    end

    count:SetAlpha(1)

    -- Apply styling
    local fontPath = "Fonts\\FRIZQT__.TTF"
    local outline = "OUTLINE"
    local QUICore = _G.QUI and _G.QUI.QUICore
    if QUICore and QUICore.db and QUICore.db.profile and QUICore.db.profile.general then
        local general = QUICore.db.profile.general
        if general.font and LSM then
            fontPath = LSM:Fetch("font", general.font) or fontPath
        end
        outline = general.fontOutline or outline
    end

    count:SetFont(fontPath, settings.countFontSize or 14, outline)

    local color = settings.countColor
    local r = color and color[1] or 1
    local g = color and color[2] or 1
    local b = color and color[3] or 1
    local a = color and color[4] or 1
    count:SetTextColor(r, g, b, a)

    -- Reposition with configurable anchor and offsets
    count:ClearAllPoints()
    local anchor = settings.countAnchor or "BOTTOMRIGHT"
    count:SetPoint(anchor, button, anchor, (settings.countOffsetX or 0), (settings.countOffsetY or 0))
end

-- Update all text elements on a button
local function UpdateButtonText(button, settings)
    UpdateKeybindText(button, settings)
    UpdateMacroText(button, settings)
    UpdateCountText(button, settings)
end

---------------------------------------------------------------------------
-- BAR LAYOUT FEATURES
---------------------------------------------------------------------------

-- Apply global scale to all action bar container frames
-- NOTE: Disabled - action bar scaling should be done via Edit Mode for consistency
local function ApplyBarScale()
    -- No-op: Users should scale action bars via Edit Mode
end

-- Update empty slot visibility for a single button
local function UpdateEmptySlotVisibility(button, settings)
    if not settings then return end

    -- Get the bar's current fade alpha (respects mouseover hide)
    local barKey = GetBarKeyFromButton(button)
    local fadeState = barKey and ActionBars.fadeState and ActionBars.fadeState[barKey]
    local targetAlpha = fadeState and fadeState.currentAlpha or 1

    if not settings.hideEmptySlots then
        -- Restore visibility if setting is off (respect fade state)
        if button._quiHiddenEmpty then
            button:SetAlpha(targetAlpha)
            button._quiHiddenEmpty = nil
        end
        return
    end

    -- Only applies to action buttons with action property
    if button.action then
        local hasAction = SafeHasAction(button.action)
        if hasAction then
            button:SetAlpha(targetAlpha)
            button._quiHiddenEmpty = nil
        else
            button:SetAlpha(0)
            button._quiHiddenEmpty = true
        end
    end
end

-- One-time migration: if QUI lockButtons was true, apply it to Blizzard CVar
-- This preserves existing user settings after the fix that stops QUI from overwriting Blizzard's setting
local function MigrateLockSetting()
    local settings = GetGlobalSettings()
    if not settings then return end

    -- Only migrate once, and only if the user had lockButtons enabled
    if settings.lockButtons and not settings._lockMigrated then
        SetCVar('lockActionBars', '1')
        settings._lockMigrated = true
    end
end

-- Apply button lock - syncs LOCK_ACTIONBAR global from Blizzard's CVar
-- NOTE: No longer overwrites Blizzard's CVar - QUI options panel now syncs directly with it
local function ApplyButtonLock()
    local locked = GetCVar('lockActionBars') == '1'
    LOCK_ACTIONBAR = locked and '1' or '0'
end

-- Usability indicator state tracking
local usabilityCheckFrame = nil
-- Range check interval (only used when range indicator is enabled)
local RANGE_CHECK_INTERVAL_NORMAL = 0.25  -- 250ms = 4 FPS (CPU-friendly)
local RANGE_CHECK_INTERVAL_FAST = 0.05    -- 50ms = 20 FPS (responsive)

local function GetUpdateInterval()
    local settings = GetGlobalSettings()
    if settings and settings.fastUsabilityUpdates then
        return RANGE_CHECK_INTERVAL_FAST
    end
    return RANGE_CHECK_INTERVAL_NORMAL
end

-- Safe wrapper for APIs that may return secret values in Midnight
local function SafeIsActionInRange(action)
    if IS_MIDNIGHT then
        -- In Midnight, IsActionInRange can return secret values
        -- Use pcall to safely check the result
        local ok, result = pcall(function()
            local inRange = IsActionInRange(action)
            -- Try to compare - this will fail if inRange is a secret value
            if inRange == false then return false end
            if inRange == true then return true end
            return nil  -- No range check needed
        end)
        if not ok then return nil end  -- Secret value, treat as in range
        return result
    else
        return IsActionInRange(action)
    end
end

local function SafeIsUsableAction(action)
    if IS_MIDNIGHT then
        -- In Midnight, IsUsableAction can return secret values
        -- We must convert to actual booleans INSIDE pcall before returning
        local ok, isUsable, notEnoughMana = pcall(function()
            local usable, noMana = IsUsableAction(action)
            -- Convert to actual booleans - if secret, comparison fails and pcall catches it
            local boolUsable = usable and true or false
            local boolNoMana = noMana and true or false
            return boolUsable, boolNoMana
        end)
        if not ok then return true, false end  -- Secret value detected, treat as usable
        return isUsable, notEnoughMana
    else
        return IsUsableAction(action)
    end
end

-- Update range and usability indicators for a single button
local function UpdateButtonUsability(button, settings)
    if not settings then return end
    if not button.action then return end

    local icon = button.icon or button.Icon
    if not icon then return end

    -- Reset state if both features disabled
    if not settings.rangeIndicator and not settings.usabilityIndicator then
        if button._quiTinted then
            icon:SetVertexColor(1, 1, 1, 1)
            icon:SetDesaturated(false)
            button._quiTinted = nil
        end
        return
    end

    -- Priority 1: Out of Range check (if enabled)
    if settings.rangeIndicator then
        local inRange = SafeIsActionInRange(button.action)
        if inRange == false then  -- false = out of range, nil = no range check needed
            local c = settings.rangeColor
            local r = c and c[1] or 0.8
            local g = c and c[2] or 0.1
            local b = c and c[3] or 0.1
            local a = c and c[4] or 1
            icon:SetVertexColor(r, g, b, a)
            icon:SetDesaturated(false)
            button._quiTinted = "range"
            return
        end
    end

    -- Priority 2: Usability check (if enabled)
    if settings.usabilityIndicator then
        local isUsable, notEnoughMana = SafeIsUsableAction(button.action)

        if notEnoughMana then
            -- Out of mana/resources - blue tint
            local c = settings.manaColor
            local r = c and c[1] or 0.5
            local g = c and c[2] or 0.5
            local b = c and c[3] or 1.0
            local a = c and c[4] or 1
            icon:SetVertexColor(r, g, b, a)
            icon:SetDesaturated(false)
            button._quiTinted = "mana"
            return
        elseif not isUsable then
            -- Not usable - desaturate or apply grey tint
            if settings.usabilityDesaturate then
                icon:SetDesaturated(true)
                icon:SetVertexColor(0.6, 0.6, 0.6, 1)  -- Slight brightness reduction with desaturation
            else
                local c = settings.usabilityColor
                local r = c and c[1] or 0.4
                local g = c and c[2] or 0.4
                local b = c and c[3] or 0.4
                local a = c and c[4] or 1
                icon:SetVertexColor(r, g, b, a)
                icon:SetDesaturated(false)
            end
            button._quiTinted = "unusable"
            return
        end
    end

    -- Normal state - reset to full brightness
    if button._quiTinted then
        icon:SetVertexColor(1, 1, 1, 1)
        icon:SetDesaturated(false)
        button._quiTinted = nil
    end
end

-- Update all visible action buttons
local function UpdateAllButtonUsability()
    local globalSettings = GetGlobalSettings()
    if not globalSettings then return end
    if not globalSettings.rangeIndicator and not globalSettings.usabilityIndicator then return end

    -- Only check action bars 1-8 (not pet/stance/micro/bags)
    for i = 1, 8 do
        local barKey = "bar" .. i
        local buttons = GetBarButtons(barKey)
        for _, button in ipairs(buttons) do
            if button:IsVisible() then
                UpdateButtonUsability(button, globalSettings)
            end
        end
    end
end

-- Debounced event handler (prevents rapid-fire updates)
local usabilityUpdatePending = false
local function ScheduleUsabilityUpdate()
    if usabilityUpdatePending then return end
    usabilityUpdatePending = true
    C_Timer.After(0.05, function()
        usabilityUpdatePending = false
        UpdateAllButtonUsability()
    end)
end

-- Reset all button tints
local function ResetAllButtonTints()
    for i = 1, 8 do
        local barKey = "bar" .. i
        local buttons = GetBarButtons(barKey)
        for _, button in ipairs(buttons) do
            local icon = button.icon or button.Icon
            if icon and button._quiTinted then
                icon:SetVertexColor(1, 1, 1, 1)
                icon:SetDesaturated(false)
                button._quiTinted = nil
            end
        end
    end
end

-- Start/stop usability indicator system (event-driven + optional range polling)
local function UpdateUsabilityPolling()
    local settings = GetGlobalSettings()
    local usabilityEnabled = settings and settings.usabilityIndicator
    local rangeEnabled = settings and settings.rangeIndicator

    -- Create frame if needed
    if not usabilityCheckFrame then
        usabilityCheckFrame = CreateFrame("Frame")
        usabilityCheckFrame.elapsed = 0
    end

    -- Event-driven usability updates (very efficient)
    if usabilityEnabled or rangeEnabled then
        usabilityCheckFrame:RegisterEvent("ACTIONBAR_UPDATE_USABLE")
        usabilityCheckFrame:RegisterEvent("ACTIONBAR_UPDATE_COOLDOWN")
        usabilityCheckFrame:RegisterEvent("SPELL_UPDATE_USABLE")
        usabilityCheckFrame:RegisterEvent("SPELL_UPDATE_CHARGES")
        usabilityCheckFrame:RegisterEvent("UNIT_POWER_UPDATE")
        usabilityCheckFrame:RegisterEvent("PLAYER_TARGET_CHANGED")

        usabilityCheckFrame:SetScript("OnEvent", function(self, event, ...)
            ScheduleUsabilityUpdate()
        end)

        -- Initial update
        ScheduleUsabilityUpdate()
    else
        usabilityCheckFrame:UnregisterAllEvents()
        usabilityCheckFrame:SetScript("OnEvent", nil)
    end

    -- Range requires slow polling (no "player moved" event exists)
    -- Only poll when range indicator is enabled, at 250ms (was 100ms)
    if rangeEnabled then
        usabilityCheckFrame:SetScript("OnUpdate", function(self, elapsed)
            self.elapsed = self.elapsed + elapsed
            if self.elapsed < GetUpdateInterval() then return end
            self.elapsed = 0
            UpdateAllButtonUsability()
        end)
        usabilityCheckFrame:Show()
    else
        usabilityCheckFrame:SetScript("OnUpdate", nil)
        usabilityCheckFrame.elapsed = 0
        -- Don't hide - events still need to work if usability is enabled
        if not usabilityEnabled then
            usabilityCheckFrame:Hide()
            ResetAllButtonTints()
        end
    end
end

-- Apply all bar layout settings
local function ApplyBarLayoutSettings()
    ApplyBarScale()
    ApplyButtonLock()
    UpdateUsabilityPolling()

    -- Apply empty slot visibility to all action buttons
    local settings = GetGlobalSettings()
    if settings then
        for barKey, _ in pairs(BUTTON_PATTERNS) do
            local buttons = GetBarButtons(barKey)
            for _, button in ipairs(buttons) do
                UpdateEmptySlotVisibility(button, settings)
            end
        end
    end
end

---------------------------------------------------------------------------
-- MOUSEOVER FADE SYSTEM
---------------------------------------------------------------------------

-- Get or create fade state for a bar
local function GetBarFadeState(barKey)
    if not ActionBars.fadeState[barKey] then
        ActionBars.fadeState[barKey] = {
            isFading = false,
            currentAlpha = 1,
            targetAlpha = 1,
            fadeStart = 0,
            fadeStartAlpha = 1,
            fadeDuration = 0.3,
            isMouseOver = false,
            delayTimer = nil,
            detector = nil,
        }
    end
    return ActionBars.fadeState[barKey]
end

-- Apply alpha to all buttons in a bar
local function SetBarAlpha(barKey, alpha)
    local buttons = GetBarButtons(barKey)
    local settings = GetGlobalSettings()
    local hideEmptyEnabled = settings and settings.hideEmptySlots

    for _, button in ipairs(buttons) do
        -- Respect hide empty slots setting - keep empty buttons hidden
        if hideEmptyEnabled and button._quiHiddenEmpty then
            button:SetAlpha(0)
        else
            button:SetAlpha(alpha)
        end
    end

    local barFrame = GetBarFrame(barKey)
    if barFrame then
        barFrame:SetAlpha(alpha)
    end

    GetBarFadeState(barKey).currentAlpha = alpha
end

-- Start smooth fade animation for a bar
local function StartBarFade(barKey, targetAlpha)
    local state = GetBarFadeState(barKey)
    local fadeSettings = GetFadeSettings()

    local duration = targetAlpha > state.currentAlpha
        and (fadeSettings and fadeSettings.fadeInDuration or 0.2)
        or (fadeSettings and fadeSettings.fadeOutDuration or 0.3)

    -- Skip if already at target
    if math.abs(state.currentAlpha - targetAlpha) < 0.01 then
        state.isFading = false
        return
    end

    state.isFading = true
    state.targetAlpha = targetAlpha
    state.fadeStart = GetTime()
    state.fadeStartAlpha = state.currentAlpha
    state.fadeDuration = duration

    -- Create fade frame if needed
    if not ActionBars.fadeFrame then
        ActionBars.fadeFrame = CreateFrame("Frame")
        ActionBars.fadeFrame:SetScript("OnUpdate", function(self, elapsed)
            local now = GetTime()
            local anyFading = false

            for bKey, bState in pairs(ActionBars.fadeState) do
                if bState.isFading then
                    anyFading = true
                    local elapsedTime = now - bState.fadeStart
                    local progress = math.min(elapsedTime / bState.fadeDuration, 1)

                    -- Smooth easing
                    local easedProgress = progress * (2 - progress)

                    local alpha = bState.fadeStartAlpha +
                        (bState.targetAlpha - bState.fadeStartAlpha) * easedProgress

                    SetBarAlpha(bKey, alpha)

                    if progress >= 1 then
                        bState.isFading = false
                        SetBarAlpha(bKey, bState.targetAlpha)
                    end
                end
            end

            if not anyFading then
                self:Hide()
            end
        end)
    end
    ActionBars.fadeFrame:Show()
end

-- Check if mouse is over bar area or any of its buttons
local function IsMouseOverBar(barKey)
    local barFrame = GetBarFrame(barKey)
    if barFrame and barFrame:IsMouseOver() then
        return true
    end

    -- Also check individual buttons
    local buttons = GetBarButtons(barKey)
    for _, button in ipairs(buttons) do
        if button:IsMouseOver() then
            return true
        end
    end

    return false
end

---------------------------------------------------------------------------
-- LINKED ACTION BARS (1-8) MOUSEOVER
---------------------------------------------------------------------------

-- Bars that participate in linked mouseover behavior
local LINKED_BAR_KEYS = {"bar1", "bar2", "bar3", "bar4", "bar5", "bar6", "bar7", "bar8"}

local function IsLinkedBar(barKey)
    for _, key in ipairs(LINKED_BAR_KEYS) do
        if key == barKey then return true end
    end
    return false
end

local function IsMouseOverAnyLinkedBar()
    for _, barKey in ipairs(LINKED_BAR_KEYS) do
        if IsMouseOverBar(barKey) then
            return true
        end
    end
    return false
end

-- Show a linked bar without triggering recursion
local function ShowLinkedBarDirect(barKey)
    local barSettings = GetBarSettings(barKey)
    local fadeSettings = GetFadeSettings()

    if not barSettings then return end
    if barSettings.alwaysShow then return end

    local fadeEnabled = barSettings.fadeEnabled
    if fadeEnabled == nil then
        fadeEnabled = fadeSettings and fadeSettings.enabled
    end
    if not fadeEnabled then return end

    local state = GetBarFadeState(barKey)

    -- Cancel pending fade-out timers
    if state.delayTimer then
        state.delayTimer:Cancel()
        state.delayTimer = nil
    end
    if state.leaveCheckTimer then
        state.leaveCheckTimer:Cancel()
        state.leaveCheckTimer = nil
    end

    StartBarFade(barKey, 1)
end

-- Start fade-out for a linked bar
local function FadeLinkedBarDirect(barKey)
    local barSettings = GetBarSettings(barKey)
    local fadeSettings = GetFadeSettings()

    if not barSettings then return end
    if barSettings.alwaysShow then return end

    local fadeEnabled = barSettings.fadeEnabled
    if fadeEnabled == nil then
        fadeEnabled = fadeSettings and fadeSettings.enabled
    end
    if not fadeEnabled then return end

    local state = GetBarFadeState(barKey)
    state.isMouseOver = false

    local fadeOutAlpha = barSettings.fadeOutAlpha
    if fadeOutAlpha == nil then
        fadeOutAlpha = fadeSettings and fadeSettings.fadeOutAlpha or 0
    end

    local delay = fadeSettings and fadeSettings.fadeOutDelay or 0.5

    if state.delayTimer then
        state.delayTimer:Cancel()
    end

    state.delayTimer = C_Timer.NewTimer(delay, function()
        state.delayTimer = nil
        -- Re-check at fade time in case mouse moved back
        if not IsMouseOverAnyLinkedBar() then
            StartBarFade(barKey, fadeOutAlpha)
        end
    end)
end

-- Handle mouse entering the bar area (event-based, no polling)
local function OnBarMouseEnter(barKey)
    local state = GetBarFadeState(barKey)
    local fadeSettings = GetFadeSettings()
    local barSettings = GetBarSettings(barKey)

    -- If bar should always be visible, skip fade logic entirely
    if barSettings and barSettings.alwaysShow then return end

    -- Check if fade is enabled
    local fadeEnabled = barSettings and barSettings.fadeEnabled
    if fadeEnabled == nil then
        fadeEnabled = fadeSettings and fadeSettings.enabled
    end
    if not fadeEnabled then return end

    state.isMouseOver = true

    -- LINKED BARS: If enabled and this is a linked bar, show ALL linked bars
    if fadeSettings and fadeSettings.linkBars1to8 and IsLinkedBar(barKey) then
        for _, linkedKey in ipairs(LINKED_BAR_KEYS) do
            if linkedKey ~= barKey then
                ShowLinkedBarDirect(linkedKey)
            end
        end
    end

    -- Cancel any pending fade-out
    if state.delayTimer then
        state.delayTimer:Cancel()
        state.delayTimer = nil
    end
    if state.leaveCheckTimer then
        state.leaveCheckTimer:Cancel()
        state.leaveCheckTimer = nil
    end

    StartBarFade(barKey, 1)
end

-- Handle mouse leaving a bar element (with delay to check if still over bar)
local function OnBarMouseLeave(barKey)
    local state = GetBarFadeState(barKey)
    local fadeSettings = GetFadeSettings()
    local barSettings = GetBarSettings(barKey)

    -- If bar should always be visible, skip fade logic entirely
    if barSettings and barSettings.alwaysShow then return end

    -- If in combat and "always show in combat" is enabled, don't fade out (bars 1-8 only)
    local isMainBar = barKey and barKey:match("^bar%d$")
    if isMainBar and InCombatLockdown() and fadeSettings and fadeSettings.alwaysShowInCombat then
        return
    end

    -- Check if fade is enabled
    local fadeEnabled = barSettings and barSettings.fadeEnabled
    if fadeEnabled == nil then
        fadeEnabled = fadeSettings and fadeSettings.enabled
    end
    if not fadeEnabled then return end

    -- Cancel any existing leave check timer
    if state.leaveCheckTimer then
        state.leaveCheckTimer:Cancel()
    end

    -- Short delay to check if mouse moved to another element in the bar
    state.leaveCheckTimer = C_Timer.NewTimer(0.066, function()
        state.leaveCheckTimer = nil

        -- If mouse is still over the bar somewhere, don't fade
        if IsMouseOverBar(barKey) then return end

        -- LINKED BARS: If enabled and this is a linked bar, check if over ANY linked bar
        if fadeSettings and fadeSettings.linkBars1to8 and IsLinkedBar(barKey) then
            if IsMouseOverAnyLinkedBar() then
                return  -- Mouse moved to another linked bar, don't fade any
            end
            -- Mouse left all linked bars - fade them all
            for _, linkedKey in ipairs(LINKED_BAR_KEYS) do
                FadeLinkedBarDirect(linkedKey)
            end
            return  -- Skip normal single-bar fade logic
        end

        state.isMouseOver = false

        -- Get fade out alpha
        local fadeOutAlpha = barSettings and barSettings.fadeOutAlpha
        if fadeOutAlpha == nil then
            fadeOutAlpha = fadeSettings and fadeSettings.fadeOutAlpha or 0
        end

        local delay = fadeSettings and fadeSettings.fadeOutDelay or 0.5

        if state.delayTimer then
            state.delayTimer:Cancel()
        end

        state.delayTimer = C_Timer.NewTimer(delay, function()
            if not state.isMouseOver then
                -- Read fresh value at fade time in case settings changed
                local freshBarSettings = GetBarSettings(barKey)
                local freshFadeSettings = GetFadeSettings()
                local freshFadeOutAlpha = freshBarSettings and freshBarSettings.fadeOutAlpha
                if freshFadeOutAlpha == nil then
                    freshFadeOutAlpha = freshFadeSettings and freshFadeSettings.fadeOutAlpha or 0
                end
                StartBarFade(barKey, freshFadeOutAlpha)
            end
            state.delayTimer = nil
        end)
    end)
end

-- Hook OnEnter/OnLeave on a frame for bar mouseover detection
local function HookFrameForMouseover(frame, barKey)
    if not frame or frame._quiMouseoverHooked then return end
    frame._quiMouseoverHooked = true

    frame:HookScript("OnEnter", function()
        OnBarMouseEnter(barKey)
    end)

    frame:HookScript("OnLeave", function()
        OnBarMouseLeave(barKey)
    end)
end

-- Setup mouseover detection for a bar (event-based, no polling)
local function SetupBarMouseover(barKey)
    local barSettings = GetBarSettings(barKey)
    local fadeSettings = GetFadeSettings()
    local db = GetDB()

    if not db or not db.enabled then return end

    -- Extra button bars (Zone Ability, Extra Action) should never inherit global fade
    -- They only fade if explicitly enabled for that specific bar
    if barKey == "extraActionButton" or barKey == "zoneAbility" then
        if not barSettings or barSettings.fadeEnabled ~= true then
            return
        end
    end

    local state = GetBarFadeState(barKey)

    -- Check if bar should always be visible (overrides fade)
    if barSettings and barSettings.alwaysShow then
        SetBarAlpha(barKey, 1)
        return
    end

    -- Check if fade is enabled for this bar
    local fadeEnabled = barSettings and barSettings.fadeEnabled
    if fadeEnabled == nil then
        fadeEnabled = fadeSettings and fadeSettings.enabled
    end

    if not fadeEnabled then
        -- Ensure bar is fully visible
        SetBarAlpha(barKey, 1)
        return
    end

    -- Get target alpha for this bar when faded out
    local fadeOutAlpha = barSettings and barSettings.fadeOutAlpha
    if fadeOutAlpha == nil then
        fadeOutAlpha = fadeSettings and fadeSettings.fadeOutAlpha or 0
    end

    -- Hook bar frame for mouseover
    local barFrame = GetBarFrame(barKey)
    if barFrame then
        HookFrameForMouseover(barFrame, barKey)
    end

    -- Hook all buttons in the bar for mouseover
    local buttons = GetBarButtons(barKey)
    for _, button in ipairs(buttons) do
        HookFrameForMouseover(button, barKey)
    end

    -- Update target alpha state to match current settings
    state.targetAlpha = fadeOutAlpha

    -- Cancel any ongoing fade animation for this bar (so new settings take effect)
    state.isFading = false
    if state.delayTimer then
        state.delayTimer:Cancel()
        state.delayTimer = nil
    end
    if state.leaveCheckTimer then
        state.leaveCheckTimer:Cancel()
        state.leaveCheckTimer = nil
    end

    -- Initialize to faded state if not moused over
    if not IsMouseOverBar(barKey) then
        SetBarAlpha(barKey, fadeOutAlpha)
    end
end

---------------------------------------------------------------------------
-- COMBAT VISIBILITY HANDLER
---------------------------------------------------------------------------

-- Combat event handler for "always show in combat" feature
-- Only applies to main action bars (1-8), not microbar, bags, pet, stance
local COMBAT_FADE_BARS = {
    bar1 = true, bar2 = true, bar3 = true, bar4 = true,
    bar5 = true, bar6 = true, bar7 = true, bar8 = true,
}

local combatFadeFrame = CreateFrame("Frame")
combatFadeFrame:RegisterEvent("PLAYER_REGEN_DISABLED")  -- Enter combat
combatFadeFrame:RegisterEvent("PLAYER_REGEN_ENABLED")   -- Leave combat

combatFadeFrame:SetScript("OnEvent", function(self, event)
    local fadeSettings = GetFadeSettings()
    if not fadeSettings or not fadeSettings.enabled then return end
    if not fadeSettings.alwaysShowInCombat then return end

    if event == "PLAYER_REGEN_DISABLED" then
        -- Entering combat: Force action bars 1-8 to full opacity
        for barKey, _ in pairs(COMBAT_FADE_BARS) do
            local state = GetBarFadeState(barKey)
            -- Cancel any pending fade timers
            if state.delayTimer then
                state.delayTimer:Cancel()
                state.delayTimer = nil
            end
            if state.leaveCheckTimer then
                state.leaveCheckTimer:Cancel()
                state.leaveCheckTimer = nil
            end
            -- Fade to full opacity
            StartBarFade(barKey, 1)
        end
    else
        -- Leaving combat: Resume normal mouseover behavior for bars 1-8
        for barKey, _ in pairs(COMBAT_FADE_BARS) do
            SetupBarMouseover(barKey)
        end
    end
end)

---------------------------------------------------------------------------
-- BAR PROCESSING
---------------------------------------------------------------------------

-- Skin all buttons for a specific bar
local function SkinBar(barKey)
    local db = GetDB()
    if not db or not db.enabled then return end

    local barSettings = GetBarSettings(barKey)
    if not barSettings or not barSettings.enabled then return end

    -- Use effective settings (global merged with per-bar overrides)
    local effectiveSettings = GetEffectiveSettings(barKey)
    if not effectiveSettings then return end

    local buttons = GetBarButtons(barKey)

    for _, button in ipairs(buttons) do
        SkinButton(button, effectiveSettings)
        UpdateButtonText(button, effectiveSettings)

        -- Add LibKeyBound methods for mousewheel binding support
        AddKeybindMethods(button, barKey)

        -- Hook OnEnter to register with LibKeyBound when in keybind mode
        -- Use HookScript to avoid tainting Blizzard's secure execution context
        -- (SetScript + calling old handler causes ADDON_ACTION_BLOCKED during combat)
        if not button._quiOnEnterHooked then
            button._quiOnEnterHooked = true
            button:HookScript("OnEnter", function(self)
                local LibKeyBound = LibStub("LibKeyBound-1.0", true)
                if LibKeyBound and LibKeyBound:IsShown() then
                    LibKeyBound:Set(self)
                end
            end)
        end
    end
end

-- Skin all enabled bars
local function SkinAllBars()
    local db = GetDB()
    if not db or not db.enabled then return end

    -- Iterate over all bars (including non-standard ones like microbar, bags, etc.)
    for barKey, _ in pairs(BAR_FRAMES) do
        -- Only skin bars that have button patterns (standard action bars)
        if BUTTON_PATTERNS[barKey] then
            SkinBar(barKey)
        end
        -- Setup mouseover fade for ALL bars
        SetupBarMouseover(barKey)
    end
end

---------------------------------------------------------------------------
-- PAGE ARROW VISIBILITY
---------------------------------------------------------------------------

local function ApplyPageArrowVisibility(hide)
    local pageNum = MainActionBar and MainActionBar.ActionBarPageNumber
    if not pageNum then return end

    if hide then
        pageNum:Hide()
        if not pageNum._QUI_ShowHooked then
            pageNum._QUI_ShowHooked = true
            hooksecurefunc(pageNum, "Show", function(self)
                local db = GetDB()
                if db and db.bars and db.bars.bar1 and db.bars.bar1.hidePageArrow then
                    self:Hide()
                end
            end)
        end
    else
        pageNum:Show()
    end
end

_G.QUI_ApplyPageArrowVisibility = ApplyPageArrowVisibility

---------------------------------------------------------------------------
-- INITIALIZATION
---------------------------------------------------------------------------

-- Refresh all action bar styling (called from options)
function ActionBars:Refresh()
    if not ActionBars.initialized then return end

    -- Clear skinned cache to force re-skin
    for button, _ in pairs(ActionBars.skinnedButtons) do
        button._quiSkinKey = nil
    end

    SkinAllBars()
    ApplyBarLayoutSettings()

    -- Apply page arrow visibility
    local db = GetDB()
    if db and db.bars and db.bars.bar1 then
        ApplyPageArrowVisibility(db.bars.bar1.hidePageArrow)
    end
end

-- Initialize the module
function ActionBars:Initialize()
    if ActionBars.initialized then return end

    -- Defer initialization if in combat (protects SetScale calls on action bars)
    if InCombatLockdown() then
        ActionBars.pendingInitialize = true
        return
    end

    local db = GetDB()
    if not db or not db.enabled then return end

    ActionBars.initialized = true

    -- One-time migration for lock setting (preserves user setting after CVar sync fix)
    MigrateLockSetting()

    -- Initial skin pass
    SkinAllBars()

    -- Apply bar layout settings (scale, lock, range indicator, empty slots)
    ApplyBarLayoutSettings()

    -- Apply page arrow visibility
    if db.bars and db.bars.bar1 then
        ApplyPageArrowVisibility(db.bars.bar1.hidePageArrow)
    end

    -- Initialize extra button holders (Extra Action Button & Zone Ability)
    InitializeExtraButtons()

    -- Debounced button update system (prevents rapid-fire during combat)
    local pendingButtonUpdates = {}
    local buttonUpdatePending = false

    local function ProcessPendingButtonUpdates()
        buttonUpdatePending = false
        for button, updateType in pairs(pendingButtonUpdates) do
            local barKey = GetBarKeyFromButton(button)
            local settings = barKey and GetEffectiveSettings(barKey) or GetGlobalSettings()
            if settings then
                if updateType == "hotkey" or updateType == "both" then
                    UpdateKeybindText(button, settings)
                end
                if updateType == "action" or updateType == "both" then
                    UpdateButtonText(button, settings)
                    UpdateEmptySlotVisibility(button, settings)
                end
            end
        end
        wipe(pendingButtonUpdates)
    end

    local function ScheduleButtonUpdate(button, updateType)
        local existing = pendingButtonUpdates[button]
        if existing and existing ~= updateType then
            pendingButtonUpdates[button] = "both"
        else
            pendingButtonUpdates[button] = updateType
        end
        if not buttonUpdatePending then
            buttonUpdatePending = true
            C_Timer.After(0.05, ProcessPendingButtonUpdates)
        end
    end

    -- NOTE: Direct hooks on ActionButton_Update and ActionButton_UpdateHotkeys have been
    -- removed as they cause taint in Midnight (12.0+). These hooks run during Blizzard's
    -- update cycle and can cause SetAttribute() calls to be blocked.
    -- Instead, we rely purely on event-driven updates (ACTIONBAR_SLOT_CHANGED,
    -- UPDATE_BINDINGS) which are already handled in the event frame below.
end

---------------------------------------------------------------------------
-- EVENT HANDLING
---------------------------------------------------------------------------

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:RegisterEvent("ACTIONBAR_SLOT_CHANGED")
eventFrame:RegisterEvent("UPDATE_BINDINGS")
eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")

eventFrame:SetScript("OnEvent", function(self, event, ...)
    if event == "PLAYER_LOGIN" then
        -- Delay initialization to ensure all frames exist
        C_Timer.After(0.5, function()
            ActionBars:Initialize()
        end)

    elseif event == "ACTIONBAR_SLOT_CHANGED" then
        -- Re-apply text styling when actions change
        C_Timer.After(0.1, function()
            for barKey, _ in pairs(BUTTON_PATTERNS) do
                local effectiveSettings = GetEffectiveSettings(barKey)
                if effectiveSettings then
                    local buttons = GetBarButtons(barKey)
                    for _, button in ipairs(buttons) do
                        UpdateButtonText(button, effectiveSettings)
                    end
                end
            end
        end)

    elseif event == "UPDATE_BINDINGS" then
        -- Re-apply keybind styling when bindings change
        C_Timer.After(0.1, function()
            for barKey, _ in pairs(BUTTON_PATTERNS) do
                local effectiveSettings = GetEffectiveSettings(barKey)
                if effectiveSettings then
                    local buttons = GetBarButtons(barKey)
                    for _, button in ipairs(buttons) do
                        UpdateKeybindText(button, effectiveSettings)
                    end
                end
            end
        end)

    elseif event == "PLAYER_REGEN_ENABLED" then
        -- Process pending initialization (from /reload during combat)
        if ActionBars.pendingInitialize then
            ActionBars.pendingInitialize = false
            ActionBars:Initialize()
        end
        -- Process any pending refresh operations
        if ActionBars.pendingRefresh then
            ActionBars.pendingRefresh = false
            ActionBars:Refresh()
        end
        -- Process pending extra button operations
        if ActionBars.pendingExtraButtonInit then
            ActionBars.pendingExtraButtonInit = false
            InitializeExtraButtons()
        end
        if ActionBars.pendingExtraButtonRefresh then
            ActionBars.pendingExtraButtonRefresh = false
            RefreshExtraButtons()
        end
    end
end)

---------------------------------------------------------------------------
-- GLOBAL REFRESH FUNCTION
---------------------------------------------------------------------------

_G.QUI_RefreshActionBars = function()
    if InCombatLockdown() then
        ActionBars.pendingRefresh = true
        return
    end
    ActionBars:Refresh()
end

---------------------------------------------------------------------------
-- EDIT MODE INTEGRATION
-- Show/hide extra button movers when Edit Mode is entered/exited
---------------------------------------------------------------------------

local function SetupEditModeHooks()
    if not EditModeManagerFrame then return end

    -- Show movers when entering Edit Mode
    hooksecurefunc(EditModeManagerFrame, "EnterEditMode", function()
        local extraSettings = GetExtraButtonDB("extraActionButton")
        local zoneSettings = GetExtraButtonDB("zoneAbility")
        -- Only show movers if at least one extra button feature is enabled
        if (extraSettings and extraSettings.enabled) or (zoneSettings and zoneSettings.enabled) then
            ShowExtraButtonMovers()
        end
    end)

    -- Hide movers when exiting Edit Mode
    hooksecurefunc(EditModeManagerFrame, "ExitEditMode", function()
        HideExtraButtonMovers()
    end)
end

-- Call setup after a short delay to ensure EditModeManagerFrame exists
C_Timer.After(1, SetupEditModeHooks)

---------------------------------------------------------------------------
-- EXPOSE MODULE
---------------------------------------------------------------------------

local QUICore = _G.QUI and _G.QUI.QUICore
if QUICore then
    QUICore.ActionBars = ActionBars
end
