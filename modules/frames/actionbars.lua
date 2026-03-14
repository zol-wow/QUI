--[[
    QUI Action Bars - Button Skinning and Fade System
    Hooks Blizzard action buttons for visual customization
]]

local ADDON_NAME, ns = ...
local LSM = LibStub("LibSharedMedia-3.0")

local GetCore = ns.Helpers.GetCore

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
local VISUAL_REFRESH_DELAY = 0.05
local WORLD_INITIAL_REFRESH_DELAY = 0.5

-- Bar frame name mappings (MainMenuBar was renamed to MainActionBar in Midnight 12.0)
local BAR_FRAMES = {
    bar1 = "MainActionBar",
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
    levelSuppressionActive = nil, -- Cached state for below-max-level suppression
    initialWorldRefreshQueued = false, -- One delayed pass to catch late-created bars (stance/pet)
    visualRefreshQueued = false,
    reactiveSkinRefreshQueued = false,
}

-- Store QUI state outside secure Blizzard frame tables.
-- Writing custom keys directly on action buttons can taint secret values.
local frameState, GetFrameState = ns.Helpers.CreateStateTable()

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

local function IsPlayerBelowMaxLevel()
    local level = UnitLevel("player")
    if not level or level <= 0 then return false end

    local maxLevel = GetMaxLevelForPlayerExpansion and GetMaxLevelForPlayerExpansion() or MAX_PLAYER_LEVEL or 80
    if not maxLevel or maxLevel <= 0 then return false end

    return level < maxLevel
end

local function ShouldSuppressMouseoverHideForLevel()
    local fadeSettings = GetFadeSettings()
    return fadeSettings and fadeSettings.disableBelowMaxLevel and IsPlayerBelowMaxLevel()
end

local function IsLeaveVehicleButtonVisible()
    -- Only apply when player is actually in a vehicle; prevents bar1 staying visible
    -- when keepLeaveVehicleVisible is enabled but player is not in a vehicle
    if not (UnitInVehicle and UnitInVehicle("player")) then
        return false
    end

    if CanExitVehicle and CanExitVehicle() then
        return true
    end

    local mainLeaveButton = _G.MainMenuBarVehicleLeaveButton
    if mainLeaveButton and mainLeaveButton.IsShown and mainLeaveButton:IsShown() then
        return true
    end

    local overrideBar = _G.OverrideActionBar
    local overrideLeaveButton = overrideBar and overrideBar.LeaveButton
    if overrideLeaveButton and overrideLeaveButton.IsShown and overrideLeaveButton:IsShown() then
        return true
    end

    return false
end

local function ShouldKeepLeaveVehicleVisible()
    local fadeSettings = GetFadeSettings()
    if not (fadeSettings and fadeSettings.keepLeaveVehicleVisible) then
        return false
    end
    return IsLeaveVehicleButtonVisible()
end

local function ApplyLeaveVehicleButtonVisibilityOverride(forceVisible)
    local mainLeaveButton = _G.MainMenuBarVehicleLeaveButton
    local overrideBar = _G.OverrideActionBar
    local overrideLeaveButton = overrideBar and overrideBar.LeaveButton
    local leaveButtons = { mainLeaveButton, overrideLeaveButton }

    for _, button in ipairs(leaveButtons) do
        if button then
            local keepOpaque = forceVisible and button.IsShown and button:IsShown()
            if button.SetIgnoreParentAlpha then
                button:SetIgnoreParentAlpha(keepOpaque)
            end
            if keepOpaque then
                button:SetAlpha(1)
            end
        end
    end
end

local function IsSpellBookVisible()
    local spellBookFrame = _G.SpellBookFrame
    if spellBookFrame and spellBookFrame.IsShown and spellBookFrame:IsShown() then
        return true
    end

    local playerSpellsFrame = _G.PlayerSpellsFrame
    if playerSpellsFrame and playerSpellsFrame.IsShown and playerSpellsFrame:IsShown() then
        local embeddedSpellBook = playerSpellsFrame.SpellBookFrame
        if embeddedSpellBook and embeddedSpellBook.IsShown then
            return embeddedSpellBook:IsShown()
        end
        return true
    end

    return false
end

local function ShouldForceShowForSpellBook()
    local fadeSettings = GetFadeSettings()
    return fadeSettings and fadeSettings.showWhenSpellBookOpen and IsSpellBookVisible()
end

local function GetSpellFlyoutSourceButton(flyout)
    if not flyout then return nil end

    local sourceButton = rawget(flyout, "flyoutButton")
    if not sourceButton and flyout.GetParent then
        sourceButton = flyout:GetParent()
    end

    return sourceButton
end

local function GetSpellFlyoutSourceBarKey(flyout)
    local sourceButton = GetSpellFlyoutSourceButton(flyout)
    if not sourceButton then return nil end

    local name = sourceButton.GetName and sourceButton:GetName()
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

local function IsSpellFlyoutActiveForBar(barKey)
    if not barKey then return false end

    local flyout = _G.SpellFlyout
    if not (flyout and flyout.IsShown and flyout:IsShown()) then
        return false
    end

    local sourceBarKey = GetSpellFlyoutSourceBarKey(flyout)
    if not sourceBarKey then
        return false
    end

    return sourceBarKey == barKey
end

local function ShouldSuspendMouseoverFade(barKey)
    return ShouldForceShowForSpellBook() or IsSpellFlyoutActiveForBar(barKey)
end

local SPELL_UI_FADE_RECHECK_DELAY = 0.1

local function CancelBarFadeTimers(state)
    if not state then return end
    if state.delayTimer then
        state.delayTimer:Cancel()
        state.delayTimer = nil
    end
    if state.leaveCheckTimer then
        state.leaveCheckTimer:Cancel()
        state.leaveCheckTimer = nil
    end
end

local function UpdateLevelSuppressionState()
    local suppress = ShouldSuppressMouseoverHideForLevel()
    if ActionBars.levelSuppressionActive == suppress then
        return false
    end
    ActionBars.levelSuppressionActive = suppress
    return true
end

local function GetFontSettings()
    local fontPath = "Fonts\\FRIZQT__.TTF"
    local outline = "OUTLINE"
    local core = GetCore()
    if core and core.db and core.db.profile and core.db.profile.general then
        local general = core.db.profile.general
        if general.font and LSM then
            fontPath = LSM:Fetch("font", general.font) or fontPath
        end
        outline = general.fontOutline or outline
    end
    return fontPath, outline
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

-- Resolve a button's icon texture object.
-- Stance buttons are inconsistent across clients:
-- - some expose button.icon/button.Icon,
-- - some use a named region (<ButtonName>Icon),
-- - some use NormalTexture as the icon.
local function GetButtonIconTexture(button)
    if not button then return nil, false end

    local isStance = GetBarKeyFromButton(button) == "stance"
    local buttonName = button.GetName and button:GetName()
    local namedIcon = buttonName and _G[buttonName .. "Icon"] or nil
    local icon = button.icon or button.Icon

    local function HasTexture(texture)
        if not texture or not texture.GetTexture then return false end
        return texture:GetTexture() ~= nil
    end

    local chosenTexture, usesNormalTexture = nil, false

    if isStance then
        -- Prefer the texture object that actually has an assigned texture.
        if HasTexture(icon) then
            chosenTexture, usesNormalTexture = icon, false
        elseif HasTexture(namedIcon) then
            chosenTexture, usesNormalTexture = namedIcon, false
        else
            local normalTex = button:GetNormalTexture() or button.NormalTexture
            if HasTexture(normalTex) then
                chosenTexture, usesNormalTexture = normalTex, true
            elseif icon then
                chosenTexture, usesNormalTexture = icon, false
            elseif namedIcon then
                chosenTexture, usesNormalTexture = namedIcon, false
            elseif normalTex then
                chosenTexture, usesNormalTexture = normalTex, true
            end
        end

        return chosenTexture, usesNormalTexture
    end

    if icon then
        return icon, false
    end
    if namedIcon then
        return namedIcon, false
    end

    return nil, false
end

-- Register a button's binding command so LibKeyBound can bind keys to it.
-- On pre-Midnight clients the methods are injected directly onto the button.
-- On Midnight (12.0+) mutating secure action buttons spreads taint, so we
-- store the data in our external frameState table and patch the LibKeyBound
-- Binder to consult it instead (see PatchLibKeyBoundForMidnight below).
local function AddKeybindMethods(button, barKey)
    if not button then return end

    local state = GetFrameState(button)
    if state.keybindMethods then return end

    local bindingPrefix = BINDING_COMMANDS[barKey]
    if not bindingPrefix then return end

    local buttonIndex = GetButtonIndex(button)
    if not buttonIndex then return end

    local bindingCommand = bindingPrefix .. buttonIndex
    state.bindingCommand = bindingCommand
    state.keybindMethods = true

    -- On Midnight we skip method injection; the patched Binder handles it.
    if IS_MIDNIGHT then return end

    -- Required method: Returns current keybind text
    function button:GetHotkey()
        local command = GetFrameState(self).bindingCommand
        local key = command and GetBindingKey(command)
        if key then
            local LibKeyBound = LibStub("LibKeyBound-1.0", true)
            return LibKeyBound and LibKeyBound:ToShortKey(key) or key
        end
        return nil
    end

    -- Required method: Binds a key to this button
    function button:SetKey(key)
        if InCombatLockdown() then return end
        local command = GetFrameState(self).bindingCommand
        if command then
            SetBinding(key, command)
        end
    end

    -- Optional method: Returns all bindings as comma-separated string
    function button:GetBindings()
        local command = GetFrameState(self).bindingCommand
        if not command then return nil end
        local keys = {}
        for i = 1, select("#", GetBindingKey(command)) do
            local key = select(i, GetBindingKey(command))
            if key then
                table.insert(keys, key)
            end
        end
        return #keys > 0 and table.concat(keys, ", ") or nil
    end

    -- Optional method: Clears all bindings from this button
    function button:ClearBindings()
        if InCombatLockdown() then return end
        local command = GetFrameState(self).bindingCommand
        if not command then return end
        while GetBindingKey(command) do
            SetBinding(GetBindingKey(command), nil)
        end
    end

    -- Optional method: Returns display name for what we're binding
    function button:GetActionName()
        return GetFrameState(self).bindingCommand
    end
end

---------------------------------------------------------------------------
-- MIDNIGHT LIBKEYBOUND COMPATIBILITY
-- On Midnight (12.0+) we cannot inject methods onto secure action buttons
-- without spreading taint. Instead we override LibKeyBound's Binder methods
-- to consult our external frameState table for binding commands.
---------------------------------------------------------------------------

local libKeyBoundPatched = false

local function PatchLibKeyBoundForMidnight()
    if not IS_MIDNIGHT then return end
    if libKeyBoundPatched then return end

    local LibKeyBound = LibStub("LibKeyBound-1.0", true)
    if not LibKeyBound then return end

    libKeyBoundPatched = true
    local Binder = LibKeyBound.Binder

    -- Helper: get binding command from our external state
    local function GetBindingCommand(button)
        local state = frameState[button]
        return state and state.bindingCommand
    end

    -- Override SetKey: use our frameState binding command when button lacks SetKey
    function Binder:SetKey(button, key)
        if InCombatLockdown() then
            UIErrorsFrame:AddMessage(LibKeyBound.L.CannotBindInCombat, 1, 0.3, 0.3, 1, UIERRORS_HOLD_TIME)
            return
        end

        self:FreeKey(button, key)

        local command = GetBindingCommand(button)
        if command then
            SetBinding(key, command)
        elseif button.SetKey then
            button:SetKey(key)
        else
            SetBindingClick(key, button:GetName(), "LeftButton")
        end

        local msg
        if command then
            msg = format(LibKeyBound.L.BoundKey, GetBindingText(key), command)
        elseif button.GetActionName then
            msg = format(LibKeyBound.L.BoundKey, GetBindingText(key), button:GetActionName())
        else
            msg = format(LibKeyBound.L.BoundKey, GetBindingText(key), button:GetName())
        end
        UIErrorsFrame:AddMessage(msg, 1, 1, 1, 1, UIERRORS_HOLD_TIME)
    end

    -- Override ClearBindings: use our frameState binding command
    function Binder:ClearBindings(button)
        if InCombatLockdown() then
            UIErrorsFrame:AddMessage(LibKeyBound.L.CannotBindInCombat, 1, 0.3, 0.3, 1, UIERRORS_HOLD_TIME)
            return
        end

        local command = GetBindingCommand(button)
        if command then
            while GetBindingKey(command) do
                SetBinding(GetBindingKey(command), nil)
            end
        elseif button.ClearBindings then
            button:ClearBindings()
        else
            local binding = self:ToBinding(button)
            while (GetBindingKey(binding)) do
                SetBinding(GetBindingKey(binding), nil)
            end
        end

        local msg
        if command then
            msg = format(LibKeyBound.L.ClearedBindings, command)
        elseif button.GetActionName then
            msg = format(LibKeyBound.L.ClearedBindings, button:GetActionName())
        else
            msg = format(LibKeyBound.L.ClearedBindings, button:GetName())
        end
        UIErrorsFrame:AddMessage(msg, 1, 1, 1, 1, UIERRORS_HOLD_TIME)
    end

    -- Override GetBindings: use our frameState binding command
    local origGetBindings = Binder.GetBindings
    function Binder:GetBindings(button)
        local command = GetBindingCommand(button)
        if command then
            local keys
            for i = 1, select("#", GetBindingKey(command)) do
                local hotKey = select(i, GetBindingKey(command))
                if keys then
                    keys = keys .. ", " .. GetBindingText(hotKey)
                else
                    keys = GetBindingText(hotKey)
                end
            end
            return keys
        end
        return origGetBindings(self, button)
    end

    -- Override FreeKey: check our frameState binding command for conflict resolution
    local origFreeKey = Binder.FreeKey
    function Binder:FreeKey(button, key)
        local command = GetBindingCommand(button)
        if command then
            local action = GetBindingAction(key)
            if action and action ~= "" and action ~= command then
                SetBinding(key, nil)
                local msg = format(LibKeyBound.L.UnboundKey, GetBindingText(key), action)
                UIErrorsFrame:AddMessage(msg, 1, 0.82, 0, 1, UIERRORS_HOLD_TIME)
            end
        else
            origFreeKey(self, button, key)
        end
    end

    -- Wrap LibKeyBound:Set — only override for buttons tracked in our frameState;
    -- delegate to the original for everything else so future library updates apply.
    local origSet = LibKeyBound.Set
    function LibKeyBound:Set(button, ...)
        -- If the button has no entry in our state, let the original handle it
        if not button or not GetBindingCommand(button) then
            return origSet(self, button, ...)
        end

        if self:IsShown() and not InCombatLockdown() then
            local bindFrame = self.frame
            if bindFrame then
                bindFrame.button = button
                bindFrame:SetAllPoints(button)

                -- Get hotkey text from our external state
                local hotkeyText
                local cmd = GetBindingCommand(button)
                if cmd then
                    local key = GetBindingKey(cmd)
                    if key then
                        hotkeyText = self:ToShortKey(key)
                    end
                end

                bindFrame.text:SetFontObject("GameFontNormalLarge")
                bindFrame.text:SetText(hotkeyText or "")
                if bindFrame.text:GetStringWidth() > bindFrame:GetWidth() then
                    bindFrame.text:SetFontObject("GameFontNormal")
                end
                bindFrame:Show()
                bindFrame:OnEnter()
            end
        elseif self.frame then
            self.frame.button = nil
            self.frame:ClearAllPoints()
            self.frame:Hide()
        end
    end

    -- Wrap Binder:OnEnter — only override for our frameState buttons; delegate
    -- to the original for everything else.
    local origOnEnter = Binder.OnEnter
    function Binder:OnEnter()
        local button = self.button
        if not button or not GetBindingCommand(button) then
            return origOnEnter(self)
        end

        if not InCombatLockdown() then
            if self:GetRight() >= (GetScreenWidth() / 2) then
                GameTooltip:SetOwner(self, "ANCHOR_LEFT")
            else
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            end

            local command = GetBindingCommand(button)
            GameTooltip:SetText(command, 1, 1, 1)

            local bindings = self:GetBindings(button)
            if bindings and bindings ~= "" then
                GameTooltip:AddLine(bindings, 0, 1, 0)
                GameTooltip:AddLine(LibKeyBound.L.ClearTip)
            else
                GameTooltip:AddLine(LibKeyBound.L.NoKeysBoundTip, 0, 1, 0)
            end
            GameTooltip:Show()
        else
            GameTooltip:Hide()
        end
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
        "iconZoom", "showBackdrop", "backdropAlpha", "showGloss", "glossAlpha", "showBorders",
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
    local frame = frameName and _G[frameName]
    -- Fallback: MainMenuBar (pre-Midnight name for bar1)
    if not frame and barKey == "bar1" then
        frame = _G["MainMenuBar"]
    end
    return frame
end

---------------------------------------------------------------------------
-- EXTRA BUTTON CUSTOMIZATION (Extra Action Button & Zone Ability)
---------------------------------------------------------------------------

local extraActionHolder = nil
local extraActionMover = nil
local zoneAbilityHolder = nil
local zoneAbilityMover = nil
local extraButtonMoversVisible = false
local hookingSetPoint = false
local extraActionSetPointHooked = false
local zoneAbilitySetPointHooked = false
local hookingSetParent = false
local pageArrowShowHooked = {}
local pageArrowRetryTimer = nil
local pageArrowRetryAttempts = 0
local PAGE_ARROW_RETRY_MAX_ATTEMPTS = 15
local PAGE_ARROW_RETRY_DELAY = 0.2

-- Get settings for a specific extra button type
local function GetExtraButtonDB(buttonType)
    local core = GetCore()
    if not core or not core.db or not core.db.profile then return nil end
    return core.db.profile.actionBars and core.db.profile.actionBars.bars
        and core.db.profile.actionBars.bars[buttonType]
end

-- Create a nudge button for extra button movers
local function CreateExtraButtonNudgeButton(parent, direction, holder, buttonType)
    local btn = CreateFrame("Button", nil, parent)
    btn:SetSize(18, 18)
    btn:SetFrameStrata("HIGH")
    btn:SetFrameLevel(100)

    -- Background
    local bg = btn:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetTexture("Interface\\Buttons\\WHITE8x8")
    bg:SetVertexColor(0.1, 0.1, 0.1, 0.7)

    -- Chevron lines
    local line1 = btn:CreateTexture(nil, "ARTWORK")
    line1:SetColorTexture(1, 1, 1, 0.9)
    line1:SetSize(7, 2)

    local line2 = btn:CreateTexture(nil, "ARTWORK")
    line2:SetColorTexture(1, 1, 1, 0.9)
    line2:SetSize(7, 2)

    if direction == "DOWN" then
        line1:SetPoint("CENTER", btn, "CENTER", -2, 1)
        line1:SetRotation(math.rad(-45))
        line2:SetPoint("CENTER", btn, "CENTER", 2, 1)
        line2:SetRotation(math.rad(45))
    elseif direction == "UP" then
        line1:SetPoint("CENTER", btn, "CENTER", -2, -1)
        line1:SetRotation(math.rad(45))
        line2:SetPoint("CENTER", btn, "CENTER", 2, -1)
        line2:SetRotation(math.rad(-45))
    elseif direction == "LEFT" then
        line1:SetPoint("CENTER", btn, "CENTER", 1, -2)
        line1:SetRotation(math.rad(-45))
        line2:SetPoint("CENTER", btn, "CENTER", 1, 2)
        line2:SetRotation(math.rad(45))
    elseif direction == "RIGHT" then
        line1:SetPoint("CENTER", btn, "CENTER", -1, -2)
        line1:SetRotation(math.rad(45))
        line2:SetPoint("CENTER", btn, "CENTER", -1, 2)
        line2:SetRotation(math.rad(-45))
    end

    btn:SetScript("OnEnter", function(self)
        line1:SetVertexColor(1, 0.8, 0, 1)
        line2:SetVertexColor(1, 0.8, 0, 1)
    end)
    btn:SetScript("OnLeave", function(self)
        line1:SetVertexColor(1, 1, 1, 0.9)
        line2:SetVertexColor(1, 1, 1, 0.9)
    end)

    btn:SetScript("OnClick", function()
        local dx, dy = 0, 0
        if direction == "UP" then dy = 1
        elseif direction == "DOWN" then dy = -1
        elseif direction == "LEFT" then dx = -1
        elseif direction == "RIGHT" then dx = 1
        end
        -- Move the holder
        if holder.AdjustPointsOffset then
            holder:AdjustPointsOffset(dx, dy)
        else
            local point, relativeTo, relativePoint, xOfs, yOfs = holder:GetPoint(1)
            if point then
                holder:ClearAllPoints()
                holder:SetPoint(point, relativeTo, relativePoint, (xOfs or 0) + dx, (yOfs or 0) + dy)
            end
        end
        -- Save position
        local core = GetCore()
        if core and core.SnapFramePosition then
            local point, _, relPoint, x, y = core:SnapFramePosition(holder)
            local db = GetExtraButtonDB(buttonType)
            if db and point then
                db.position = { point = point, relPoint = relPoint, x = x, y = y }
            end
        end
    end)

    return btn
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
    local core = GetCore()
    local px = (core and core.GetPixelSize and core:GetPixelSize(mover)) or 1
    local edge2 = 2 * px
    mover:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = edge2,
    })
    mover:SetBackdropColor(0.2, 0.8, 0.6, 0.5)  -- QUI mint color
    mover:SetBackdropBorderColor(0.2, 1.0, 0.6, 1)
    mover:EnableMouse(true)
    mover:SetMovable(true)
    mover:RegisterForDrag("LeftButton")
    mover:SetFrameStrata("HIGH")
    mover:Hide()

    -- Label text
    local text = mover:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    text:SetPoint("CENTER")
    text:SetText(displayName)
    mover.text = text

    -- Nudge buttons
    local nudgeUp = CreateExtraButtonNudgeButton(mover, "UP", holder, buttonType)
    nudgeUp:SetPoint("BOTTOM", mover, "TOP", 0, 4)

    local nudgeDown = CreateExtraButtonNudgeButton(mover, "DOWN", holder, buttonType)
    nudgeDown:SetPoint("TOP", mover, "BOTTOM", 0, -4)

    local nudgeLeft = CreateExtraButtonNudgeButton(mover, "LEFT", holder, buttonType)
    nudgeLeft:SetPoint("RIGHT", mover, "LEFT", -4, 0)

    local nudgeRight = CreateExtraButtonNudgeButton(mover, "RIGHT", holder, buttonType)
    nudgeRight:SetPoint("LEFT", mover, "RIGHT", 4, 0)

    -- Drag handlers
    mover:SetScript("OnDragStart", function(self)
        holder:StartMoving()
    end)

    mover:SetScript("OnDragStop", function(self)
        holder:StopMovingOrSizing()
        local core = GetCore()
        if not core or not core.SnapFramePosition then return end
        local point, _, relPoint, x, y = core:SnapFramePosition(holder)
        local db = GetExtraButtonDB(buttonType)
        if db and point then
            db.position = { point = point, relPoint = relPoint, x = x, y = y }
        end
    end)

    return holder, mover
end

-- Original parents for managed frames (saved before reparenting)
local extraButtonOriginalParents = {}

-- Apply settings (scale, position, artwork) to an extra button frame
local function ApplyExtraButtonSettings(buttonType)
    if InCombatLockdown() then
        ActionBars.pendingExtraButtonRefresh = true
        return
    end

    local settings = GetExtraButtonDB(buttonType)
    if not settings or not settings.enabled then return end

    local blizzFrame
    local holder

    if buttonType == "extraActionButton" then
        blizzFrame = ExtraActionBarFrame
        holder = extraActionHolder
    else
        blizzFrame = ZoneAbilityFrame
        holder = zoneAbilityHolder
    end

    if not blizzFrame or not holder then return end

    -- Apply scale
    local scale = settings.scale or 1.0
    blizzFrame:SetScale(scale)

    -- Apply offsets (relative to holder position)
    local offsetX = settings.offsetX or 0
    local offsetY = settings.offsetY or 0

    -- TAINT SAFETY: Reparent the Blizzard frame to our holder, removing it
    -- from the UIParent managed frame container's layout chain.  Calling
    -- ClearAllPoints/SetPoint on managed frames from addon code permanently
    -- taints their position data; when Blizzard's secure UseAction chain
    -- later calls UIParent_ManageFramePositions, the taint propagates to
    -- all managed containers (including UIParentRightManagedFrameContainer),
    -- causing ADDON_ACTION_BLOCKED.  Reparenting removes the frame from the
    -- managed container entirely so its position is never read by the secure
    -- layout system.
    if not extraButtonOriginalParents[buttonType] then
        extraButtonOriginalParents[buttonType] = blizzFrame:GetParent()
    end
    hookingSetParent = true
    blizzFrame:SetParent(holder)
    hookingSetParent = false
    hookingSetPoint = true
    blizzFrame:ClearAllPoints()
    blizzFrame:SetPoint("CENTER", holder, "CENTER", offsetX, offsetY)
    hookingSetPoint = false

    -- Update holder size to match scaled frame (SafeToNumber guards against
    -- secret values that GetWidth/GetHeight can return during combat lockdown)
    local width = Helpers.SafeToNumber(blizzFrame:GetWidth(), 64) * scale
    local height = Helpers.SafeToNumber(blizzFrame:GetHeight(), 64) * scale
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
local pendingExtraButtonReanchor = {}

-- Re-anchor extra buttons outside Blizzard's SetPoint call chain.
-- Directly mutating anchors inside managed-frame SetPoint hooks can taint
-- UIParent managed frame containers and trigger ADDON_ACTION_BLOCKED in combat.
local function QueueExtraButtonReanchor(buttonType)
    if pendingExtraButtonReanchor[buttonType] then return end
    pendingExtraButtonReanchor[buttonType] = true

    C_Timer.After(0, function()
        pendingExtraButtonReanchor[buttonType] = false

        if InCombatLockdown() then
            ActionBars.pendingExtraButtonRefresh = true
            return
        end

        local settings = GetExtraButtonDB(buttonType)
        if settings and settings.enabled then
            ApplyExtraButtonSettings(buttonType)
        end
    end)
end

-- Hook Blizzard frames to prevent them from repositioning.
-- After reparenting, the managed container won't reposition these frames,
-- but other Blizzard code (e.g. ability grant, zone transition) may call
-- SetPoint directly.  The hooks re-anchor to our holder after each attempt.
local function HookExtraButtonPositioning()
    if ExtraActionBarFrame and not extraActionSetPointHooked then
        extraActionSetPointHooked = true
        hooksecurefunc(ExtraActionBarFrame, "SetPoint", function(self)
            if hookingSetPoint then return end
            C_Timer.After(0, function()
                if hookingSetPoint or InCombatLockdown() then return end
                local settings = GetExtraButtonDB("extraActionButton")
                if extraActionHolder and settings and settings.enabled then
                    QueueExtraButtonReanchor("extraActionButton")
                end
            end)
        end)
    end

    if ZoneAbilityFrame and not zoneAbilitySetPointHooked then
        zoneAbilitySetPointHooked = true
        hooksecurefunc(ZoneAbilityFrame, "SetPoint", function(self)
            if hookingSetPoint then return end
            C_Timer.After(0, function()
                if hookingSetPoint or InCombatLockdown() then return end
                local settings = GetExtraButtonDB("zoneAbility")
                if zoneAbilityHolder and settings and settings.enabled then
                    QueueExtraButtonReanchor("zoneAbility")
                end
            end)
        end)
    end

    -- Hook SetParent to reclaim frames if Blizzard reparents them back to
    -- a managed container (e.g. during Edit Mode layout recalculation).
    local function HookSetParentForType(blizzFrame, buttonType, holder)
        if not blizzFrame then return end
        hooksecurefunc(blizzFrame, "SetParent", function(self, newParent)
            if hookingSetParent then return end
            if newParent == holder then return end  -- already ours
            C_Timer.After(0, function()
                if hookingSetParent or InCombatLockdown() then return end
                local settings = GetExtraButtonDB(buttonType)
                if holder and settings and settings.enabled then
                    hookingSetParent = true
                    blizzFrame:SetParent(holder)
                    hookingSetParent = false
                    QueueExtraButtonReanchor(buttonType)
                end
            end)
        end)
    end
    HookSetParentForType(ExtraActionBarFrame, "extraActionButton", extraActionHolder)
    HookSetParentForType(ZoneAbilityFrame, "zoneAbility", zoneAbilityHolder)
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
    local state = GetFrameState(button)
    local icon, iconUsesNormalTexture = GetButtonIconTexture(button)

    -- Always re-hide NormalTexture — Blizzard may reset it after our init
    -- (e.g. action bar updates that call SetNormalTexture post-PLAYER_LOGIN).
    -- If a button currently uses NormalTexture as the icon source, keep it.
    -- Otherwise hide NormalTexture, including for stance buttons.
    local normalTex = button:GetNormalTexture()
    if normalTex and not iconUsesNormalTexture then
        normalTex:SetAlpha(0)
    end
    if button.NormalTexture and not iconUsesNormalTexture then
        button.NormalTexture:SetAlpha(0)
    end

    -- Remove mask textures from icon
    -- Re-run when icon object changes (can happen for stance/pet during paging).
    if icon and not iconUsesNormalTexture and icon.GetMaskTexture and icon.RemoveMaskTexture then
        if state.lastMaskStrippedIcon ~= icon then
            for i = 1, 10 do
                local mask = icon:GetMaskTexture(i)
                if mask then
                    icon:RemoveMaskTexture(mask)
                end
            end
            state.lastMaskStrippedIcon = icon
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

local FadeHideEffects
local FadeShowEffects
local SkinSpellFlyoutButtons

-- Apply QUI skin to a single button
local function SkinButton(button, settings)
    if not button or not settings or not settings.skinEnabled then return end
    local state = GetFrameState(button)

    -- Skip if already skinned with same settings
    local settingsKey = string.format("%d_%.2f_%s_%.2f_%s_%.2f_%s",
        settings.iconSize or 36,
        settings.iconZoom or 0.07,
        tostring(settings.showBackdrop),
        settings.backdropAlpha or 0.8,
        tostring(settings.showGloss),
        settings.glossAlpha or 0.6,
        tostring(settings.showBorders)
    )
    if state.skinKey == settingsKey then return end
    state.skinKey = settingsKey

    -- Strip Blizzard artwork first
    StripBlizzardArtwork(button)

    local iconSize = settings.iconSize or 36
    local zoom = settings.iconZoom or 0.07

    -- Apply icon TexCoords (crop transparent edges)
    local icon = GetButtonIconTexture(button)
    if icon then
        icon:SetTexCoord(zoom, 1 - zoom, zoom, 1 - zoom)
        icon:ClearAllPoints()
        icon:SetAllPoints(button)
        local buttonName = button.GetName and button:GetName()
        local isSpellFlyoutButton = buttonName and (
            buttonName:match("^SpellFlyoutPopupButton%d+$")
            or buttonName:match("^SpellFlyoutButton%d+$")
        )
        -- After /reload, empty slots may retain stale icon textures from the
        -- previous session. Clear them so ghost icons don't appear.
        -- Do not apply this to stance/pet buttons: they use non-standard action
        -- slot semantics and can return false from HasAction() while still
        -- having a valid icon.
        -- Also skip spell flyout buttons: Blizzard sets their icon directly.
        local barKey = GetBarKeyFromButton(button)
        local action = Helpers.SafeToNumber(button.action)
        if action and barKey ~= "stance" and barKey ~= "pet" and not isSpellFlyoutButton
            and not SafeHasAction(action) then
            icon:SetTexture(nil)
        end
        icon:SetAlpha(1)
        if icon.Show then icon:Show() end
    end

    -- Create or update backdrop (behind icon, configurable opacity)
    if settings.showBackdrop then
        if not state.backdrop then
            state.backdrop = button:CreateTexture(nil, "BACKGROUND", nil, -8)
            state.backdrop:SetColorTexture(0, 0, 0, 1)
        end
        state.backdrop:SetAlpha(settings.backdropAlpha or 0.8)
        state.backdrop:ClearAllPoints()
        state.backdrop:SetAllPoints(button)  -- Same size as button, not extending beyond
        state.backdrop:Show()
    elseif state.backdrop then
        state.backdrop:Hide()
    end

    -- Create or update Normal overlay (border frame texture)
    if settings.showBorders ~= false then
        if not state.normal then
            state.normal = button:CreateTexture(nil, "OVERLAY", nil, 1)
            state.normal:SetTexture(TEXTURES.normal)
            state.normal:SetVertexColor(0, 0, 0, 1)
        end
        state.normal:SetSize(iconSize, iconSize)
        state.normal:ClearAllPoints()
        state.normal:SetAllPoints(button)
        state.normal:Show()
    elseif state.normal then
        state.normal:Hide()
    end

    -- Create or update Gloss overlay (ADD blend shine)
    if settings.showGloss then
        if not state.gloss then
            state.gloss = button:CreateTexture(nil, "OVERLAY", nil, 2)
            state.gloss:SetTexture(TEXTURES.gloss)
            state.gloss:SetBlendMode("ADD")
        end
        state.gloss:SetVertexColor(1, 1, 1, settings.glossAlpha or 0.6)
        state.gloss:SetAllPoints(button)
        state.gloss:Show()
    elseif state.gloss then
        state.gloss:Hide()
    end

    -- Fix Cooldown frame positioning
    local cooldown = button.cooldown or button.Cooldown
    if cooldown then
        cooldown:ClearAllPoints()
        cooldown:SetAllPoints(button)
    end

    -- If the button is currently hidden (bar faded out or empty slot),
    -- keep newly-created textures hidden to match the fade state.
    -- Record _fh* flags so FadeShowTextures knows to restore them on hover.
    if state.fadeHidden then
        if state.backdrop and state.backdrop:IsShown() then state.backdrop:Hide(); state._fhBg = true end
        if state.normal and state.normal:IsShown() then state.normal:Hide(); state._fhNorm = true end
        if state.gloss and state.gloss:IsShown() then state.gloss:Hide(); state._fhGloss = true end
        FadeHideEffects(button, state)
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
        local action = Helpers.SafeToNumber(button.action)
        if action then
            local hasAction = SafeHasAction(action)
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
    local fontPath, outline = GetFontSettings()

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
    local fontPath, outline = GetFontSettings()

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
    local fontPath, outline = GetFontSettings()

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
-- FADE-HIDE HELPERS
-- QUI-owned textures (backdrop, border, gloss, tintOverlay) may not
-- respect parent alpha inheritance — especially MOD-blend textures.
-- We must explicitly Hide()/Show() them when the button should be
-- invisible (bar faded to alpha 0, or hidden empty slot).
---------------------------------------------------------------------------

FadeHideEffects = function(button, state)
    if not button then return end

    local cooldown = button.cooldown or button.Cooldown
    if cooldown then
        if not state._fhCooldownShowHooked and cooldown.HookScript then
            state._fhCooldownShowHooked = true
            cooldown:HookScript("OnShow", function(self)
                local st = GetFrameState(button)
                if st and st.fadeHidden then
                    self:Hide()
                end
            end)
        end

        if cooldown:IsShown() then
            state._fhCooldownFrameShown = true
            cooldown:Hide()
        end
        if state._fhCooldownSwipe == nil and cooldown.GetDrawSwipe then
            state._fhCooldownSwipe = cooldown:GetDrawSwipe()
        end
        if state._fhCooldownEdge == nil and cooldown.GetDrawEdge then
            state._fhCooldownEdge = cooldown:GetDrawEdge()
        end
        if cooldown.SetDrawSwipe then cooldown:SetDrawSwipe(false) end
        if cooldown.SetDrawEdge then cooldown:SetDrawEdge(false) end
    end

    local spellActivation = button.SpellActivationAlert
    if spellActivation then
        if not state._fhSpellActivationShowHooked and spellActivation.HookScript then
            state._fhSpellActivationShowHooked = true
            spellActivation:HookScript("OnShow", function(self)
                local st = GetFrameState(button)
                if st and st.fadeHidden then
                    self:Hide()
                end
            end)
        end
        if spellActivation:IsShown() then
            spellActivation:Hide()
            state._fhSpellActivationAlert = true
        end
    end
    local overlayGlow = button.OverlayGlow
    if overlayGlow then
        if not state._fhOverlayGlowShowHooked and overlayGlow.HookScript then
            state._fhOverlayGlowShowHooked = true
            overlayGlow:HookScript("OnShow", function(self)
                local st = GetFrameState(button)
                if st and st.fadeHidden then
                    self:Hide()
                end
            end)
        end
        if overlayGlow:IsShown() then
            overlayGlow:Hide()
            state._fhOverlayGlow = true
        end
    end
    local buttonGlow = button._ButtonGlow
    if buttonGlow then
        if not state._fhButtonGlowShowHooked and buttonGlow.HookScript then
            state._fhButtonGlowShowHooked = true
            buttonGlow:HookScript("OnShow", function(self)
                local st = GetFrameState(button)
                if st and st.fadeHidden then
                    self:Hide()
                end
            end)
        end
        if buttonGlow:IsShown() then
            buttonGlow:Hide()
            state._fhButtonGlow = true
        end
    end
end

FadeShowEffects = function(button, state)
    if not button then return end

    local cooldown = button.cooldown or button.Cooldown
    if cooldown then
        if state._fhCooldownSwipe ~= nil and cooldown.SetDrawSwipe then
            cooldown:SetDrawSwipe(state._fhCooldownSwipe)
        end
        if state._fhCooldownEdge ~= nil and cooldown.SetDrawEdge then
            cooldown:SetDrawEdge(state._fhCooldownEdge)
        end
        if state._fhCooldownFrameShown and cooldown.Show then
            cooldown:Show()
        end
    end
    state._fhCooldownFrameShown = nil
    state._fhCooldownSwipe = nil
    state._fhCooldownEdge = nil

    if state._fhSpellActivationAlert and button.SpellActivationAlert then
        button.SpellActivationAlert:Show()
    end
    if state._fhOverlayGlow and button.OverlayGlow then
        button.OverlayGlow:Show()
    end
    if state._fhButtonGlow and button._ButtonGlow then
        button._ButtonGlow:Show()
    end
    state._fhSpellActivationAlert = nil
    state._fhOverlayGlow = nil
    state._fhButtonGlow = nil
end

-- Hide QUI textures on a button, saving which were visible for later restore.
local function FadeHideTextures(state, button)
    if state.fadeHidden then return end
    state.fadeHidden = true
    if state.tintOverlay and state.tintOverlay:IsShown() then
        state.tintOverlay:Hide(); state._fhTint = true
    end
    if state.backdrop and state.backdrop:IsShown() then
        state.backdrop:Hide(); state._fhBg = true
    end
    if state.normal and state.normal:IsShown() then
        state.normal:Hide(); state._fhNorm = true
    end
    if state.gloss and state.gloss:IsShown() then
        state.gloss:Hide(); state._fhGloss = true
    end
    FadeHideEffects(button, state)
end

-- Restore QUI textures that were hidden by FadeHideTextures.
local function FadeShowTextures(state, button)
    if not state.fadeHidden then return end
    state.fadeHidden = nil
    if state._fhTint and state.tintOverlay then state.tintOverlay:Show() end
    if state._fhBg and state.backdrop then state.backdrop:Show() end
    if state._fhNorm and state.normal then state.normal:Show() end
    if state._fhGloss and state.gloss then state.gloss:Show() end
    state._fhTint = nil; state._fhBg = nil
    state._fhNorm = nil; state._fhGloss = nil
    FadeShowEffects(button, state)
end

---------------------------------------------------------------------------
-- BAR LAYOUT FEATURES
---------------------------------------------------------------------------

-- Apply global scale to all action bar container frames
-- NOTE: Disabled - action bar scaling should be done via Edit Mode for consistency
local function ApplyBarScale()
    -- No-op: Users should scale action bars via Edit Mode
end

-- Drag preview: show hidden empty slots at low alpha while cursor holds a placeable action
local DRAG_PREVIEW_ALPHA = 0.3

local function CursorHasPlaceableAction()
    local infoType = GetCursorInfo()
    return infoType == "spell" or infoType == "item" or infoType == "macro"
        or infoType == "petaction" or infoType == "mount" or infoType == "flyout"
end

-- Update empty slot visibility for a single button
local function UpdateEmptySlotVisibility(button, settings)
    if not settings then return end
    local state = GetFrameState(button)

    -- Get the bar's current fade alpha (respects mouseover hide)
    local barKey = GetBarKeyFromButton(button)
    local fadeState = barKey and ActionBars.fadeState and ActionBars.fadeState[barKey]
    local targetAlpha = fadeState and fadeState.currentAlpha or 1

    -- Stance/pet buttons are not standard action slots and can report action
    -- data that does not map cleanly to HasAction(). Never apply hide-empty
    -- logic to them.
    if barKey == "stance" or barKey == "pet" then
        if state.hiddenEmpty then
            state.hiddenEmpty = nil
            FadeShowTextures(state, button)
        end
        button:SetAlpha(targetAlpha)
        return
    end

    if not settings.hideEmptySlots then
        -- Restore visibility if setting is off (respect fade state)
        if state.hiddenEmpty then
            button:SetAlpha(targetAlpha)
            state.hiddenEmpty = nil
            FadeShowTextures(state, button)
        end
        return
    end

    -- Only applies to action buttons with action property
    local action = Helpers.SafeToNumber(button.action)
    if action then
        local hasAction = SafeHasAction(action)
        if hasAction then
            button:SetAlpha(targetAlpha)
            if state.hiddenEmpty then
                state.hiddenEmpty = nil
                FadeShowTextures(state, button)
            end
        else
            -- Show at preview alpha while dragging a placeable action
            if ActionBars.dragPreviewActive then
                button:SetAlpha(DRAG_PREVIEW_ALPHA * targetAlpha)
            else
                button:SetAlpha(0)
            end
            if not state.hiddenEmpty then
                state.hiddenEmpty = true
                FadeHideTextures(state, button)
            end
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

-- Get or create a QUI-owned tint overlay for range/usability coloring.
-- Uses MOD (multiplicative) blend on ARTWORK sublevel 1, so it renders
-- above the icon (sublevel 0) but below OVERLAY borders/gloss.
-- Hidden by default — no overlay = no tint.
local function GetTintOverlay(button)
    local state = GetFrameState(button)
    if not state.tintOverlay then
        local icon = GetButtonIconTexture(button)
        if not icon then return nil end
        local overlay = button:CreateTexture(nil, "ARTWORK", nil, 1)
        overlay:SetAllPoints(icon)
        overlay:SetBlendMode("MOD")
        overlay:SetColorTexture(1, 1, 1, 1)  -- White = no tint
        overlay:Hide()
        state.tintOverlay = overlay
    end
    return state.tintOverlay
end

-- Update range and usability indicators for a single button.
-- Uses a QUI-owned overlay texture instead of modifying Blizzard's icon
-- directly, which avoids tainting secret values during combat.
local function UpdateButtonUsability(button, settings)
    if not settings then return end
    local action = Helpers.SafeToNumber(button.action)
    if not action then return end

    local state = GetFrameState(button)

    -- Skip buttons that are effectively invisible (faded bar or hidden empty
    -- slot).  MOD-blend textures ignore parent alpha inheritance and will
    -- darken the scene behind them even when the button is at alpha 0.
    if state.fadeHidden or state.hiddenEmpty then
        return
    end

    -- Reset state if both features disabled
    if not settings.rangeIndicator and not settings.usabilityIndicator then
        if state.tinted then
            if state.tintOverlay then state.tintOverlay:Hide() end
            state.tinted = nil
        end
        return
    end

    -- Priority 1: Out of Range check (if enabled)
    if settings.rangeIndicator then
        local inRange = SafeIsActionInRange(action)
        if inRange == false then  -- false = out of range, nil = no range check needed
            local overlay = GetTintOverlay(button)
            if overlay then
                local c = settings.rangeColor
                overlay:SetColorTexture(c and c[1] or 0.8, c and c[2] or 0.1, c and c[3] or 0.1, c and c[4] or 1)
                overlay:Show()
            end
            state.tinted = "range"
            return
        end
    end

    -- Priority 2: Usability check (if enabled)
    if settings.usabilityIndicator then
        local isUsable, notEnoughMana = SafeIsUsableAction(action)

        if notEnoughMana then
            -- Out of mana/resources - blue tint
            local overlay = GetTintOverlay(button)
            if overlay then
                local c = settings.manaColor
                overlay:SetColorTexture(c and c[1] or 0.5, c and c[2] or 0.5, c and c[3] or 1.0, c and c[4] or 1)
                overlay:Show()
            end
            state.tinted = "mana"
            return
        elseif not isUsable then
            -- Not usable - dark tint (MOD blend can't desaturate, so we
            -- approximate the desaturate look with a dim grey overlay)
            local overlay = GetTintOverlay(button)
            if overlay then
                if settings.usabilityDesaturate then
                    overlay:SetColorTexture(0.4, 0.4, 0.4, 1)
                else
                    local c = settings.usabilityColor
                    overlay:SetColorTexture(c and c[1] or 0.4, c and c[2] or 0.4, c and c[3] or 0.4, c and c[4] or 1)
                end
                overlay:Show()
            end
            state.tinted = "unusable"
            return
        end
    end

    -- Normal state - hide overlay
    if state.tinted then
        if state.tintOverlay then state.tintOverlay:Hide() end
        state.tinted = nil
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
        -- Skip bars that are fully faded out
        local fadeState = ActionBars.fadeState and ActionBars.fadeState[barKey]
        if not fadeState or fadeState.currentAlpha > 0 then
            local buttons = GetBarButtons(barKey)
            for _, button in ipairs(buttons) do
                -- UpdateButtonUsability internally checks fadeHidden/hiddenEmpty
                if button:IsVisible() then
                    UpdateButtonUsability(button, globalSettings)
                end
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
            local state = GetFrameState(button)
            if state.tinted then
                if state.tintOverlay then state.tintOverlay:Hide() end
                state.tinted = nil
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

---------------------------------------------------------------------------
-- BUTTON SPACING OVERRIDE
---------------------------------------------------------------------------

-- Detect how many columns a bar has by comparing button Y positions.
-- Buttons in the same row share a similar top edge; a new row drops down.
-- Detect how many columns a bar has by comparing button Y positions.
-- Fallback for bars without Edit Mode API (pet, stance).
local function DetectBarColumns(buttons)
    if #buttons < 2 then return #buttons end

    local firstTop = buttons[1]:GetTop()
    if not firstTop then return #buttons end

    local buttonHeight = buttons[1]:GetHeight() or 30
    local threshold = buttonHeight * 0.3
    local numCols = 1

    for i = 2, #buttons do
        local top = buttons[i]:GetTop()
        if not top or math.abs(top - firstTop) > threshold then
            break
        end
        numCols = numCols + 1
    end

    return numCols
end

-- Read the bar's grid layout from the Edit Mode API.
-- Returns numCols, numRows, isVertical.
-- Falls back to position-based detection for bars without the API (pet, stance).
local function GetBarGridLayout(barFrame, buttons)
    local isVertical = false
    local numCols, numRows

    local EditModeSettings = Enum.EditModeActionBarSetting
    if barFrame.GetSettingValue and EditModeSettings then
        local okO, orientation = pcall(barFrame.GetSettingValue, barFrame, EditModeSettings.Orientation)
        local okR, editNumRows = pcall(barFrame.GetSettingValue, barFrame, EditModeSettings.NumRows)

        if okO and okR and editNumRows and editNumRows > 0 then
            isVertical = (orientation == 1)
            if isVertical then
                -- Vertical: Blizzard's "NumRows" is the number of visual columns
                numCols = editNumRows
                numRows = math.ceil(#buttons / numCols)
            else
                -- Horizontal: NumRows is actual rows
                numRows = editNumRows
                numCols = math.ceil(#buttons / numRows)
            end
        end
    end

    -- Fallback for bars without Edit Mode API
    if not numCols then
        numCols = DetectBarColumns(buttons)
        numRows = math.ceil(#buttons / numCols)
    end

    return numCols, numRows, isVertical
end

-- Reposition action bar buttons with custom spacing override.
-- WoW 12.0 wraps each button in a per-button container managed by an internal
-- LayoutFrame. We reposition the containers (not the buttons) to override
-- Blizzard's layout, then resize the bar frame to exactly fit the group.
-- Supports both horizontal and vertical bar orientations via Edit Mode API.
local function ApplyButtonSpacing(barKey)
    if InCombatLockdown() then
        ActionBars.pendingSpacing = true
        return
    end

    local settings = GetGlobalSettings()
    if not settings or settings.buttonSpacing == nil then return end

    local spacing = settings.buttonSpacing
    -- Only apply spacing to standard action bars (1-8).
    -- Pet/stance bars have variable visible button counts per class
    -- and resizing their bar frames breaks the frame anchoring chain
    -- (size-stable CENTER anchoring shifts visual content on resize).
    if barKey == "pet" or barKey == "stance" then return end

    local allButtons = GetBarButtons(barKey)
    if #allButtons < 2 then return end

    local barFrame = GetBarFrame(barKey)
    if not barFrame then return end

    -- Sort ALL buttons by layoutIndex BEFORE taking the NumIcons subset.
    -- This ensures the correct buttons are selected when the user configures
    -- fewer than 12 visible icons in Edit Mode.
    do
        local needsSort = false
        for _, btn in ipairs(allButtons) do
            local container = btn:GetParent()
            if container and container.layoutIndex then
                needsSort = true
                break
            end
        end
        if needsSort then
            local sorted = {}
            for i, btn in ipairs(allButtons) do
                sorted[i] = btn
            end
            table.sort(sorted, function(a, b)
                local indexA = a:GetParent() and a:GetParent().layoutIndex
                local indexB = b:GetParent() and b:GetParent().layoutIndex
                if indexA and indexB and indexA ~= indexB then
                    return indexA < indexB
                end
                -- Tiebreaker: preserve name-based order
                local numA = tonumber(a:GetName():match("%d+$")) or 0
                local numB = tonumber(b:GetName():match("%d+$")) or 0
                return numA < numB
            end)
            allButtons = sorted
        end
    end

    -- Read the visible icon count from Edit Mode API.
    -- Users can configure bars to show fewer than 12 buttons (e.g. 9 of 12).
    -- We must only layout the visible subset, otherwise the bar frame is sized
    -- for invisible buttons and the layout breaks.
    local buttons = allButtons
    local editModeNumIcons = nil
    local EditModeSettings = Enum.EditModeActionBarSetting
    if barFrame.GetSettingValue and EditModeSettings then
        local okN, numIcons = pcall(barFrame.GetSettingValue, barFrame, EditModeSettings.NumIcons)
        if okN and numIcons and numIcons > 0 then
            editModeNumIcons = numIcons
            if numIcons < #allButtons then
                local visible = {}
                for i = 1, numIcons do
                    visible[i] = allButtons[i]
                end
                buttons = visible
            end
            -- When numIcons == #allButtons, trust the API — use all buttons.
            -- Do NOT fall through to the IsShown fallback, which would filter
            -- out buttons that Blizzard hasn't re-shown yet (e.g. after the
            -- user increases the button count in Edit Mode).
        end
    end

    -- Fallback: filter to only shown buttons when the Edit Mode API is NOT
    -- available (should not happen for bars 1-8, but guards pet/stance bars
    -- if they ever reach here).
    -- When ALL buttons are hidden (e.g. no pet summoned), skip the bar entirely.
    if not editModeNumIcons and #buttons == #allButtons then
        local shown = {}
        for _, btn in ipairs(allButtons) do
            if btn:IsShown() then
                shown[#shown + 1] = btn
            end
        end
        if #shown > 0 and #shown < #buttons then
            buttons = shown
        end
    end

    if #buttons < 2 then return end

    local numCols, numRows, isVertical = GetBarGridLayout(barFrame, buttons)

    -- Read Blizzard's layout direction flags.
    -- addButtonsToTop=true: rows stack bottom-to-top (button 1 at bottom row)
    -- addButtonsToRight=true: columns stack left-to-right (button 1 at left column)
    local addToTop = barFrame.addButtonsToTop
    local addToRight = barFrame.addButtonsToRight

    -- Effective scales for coordinate space conversion
    local containerEffScale = buttons[1]:GetParent():GetEffectiveScale()
    local barEffScale = barFrame:GetEffectiveScale()
    if not containerEffScale or containerEffScale <= 0 or not barEffScale or barEffScale <= 0 then return end

    -- Group dimensions in container coordinate space (buttons are scale 1.0 inside containers)
    local btnWidth = buttons[1]:GetWidth()
    local btnHeight = buttons[1]:GetHeight()
    local groupWidth = numCols * btnWidth + math.max(0, numCols - 1) * spacing
    local groupHeight = numRows * btnHeight + math.max(0, numRows - 1) * spacing

    -- Resize bar frame to exactly fit the button group.
    -- Convert from container coordinate space to bar frame coordinate space.
    -- We intentionally do NOT adjust anchor offsets to preserve the bar's center
    -- position — that offset manipulation was the root cause of cumulative drift.
    -- The bar resizes from whatever anchor point Edit Mode assigned it.
    barFrame:SetSize(
        groupWidth * containerEffScale / barEffScale,
        groupHeight * containerEffScale / barEffScale
    )

    -- Reposition the CONTAINERS (button parents) instead of the buttons themselves.
    -- Blizzard's LayoutFrame positions containers; button-level anchors don't
    -- override the visual layout because the container is what renders.
    -- Respect Blizzard's addButtonsToTop/addButtonsToRight flags so QUI's
    -- layout matches Edit Mode's visual order.
    local container1 = buttons[1]:GetParent()
    container1:ClearAllPoints()
    container1:SetSize(btnWidth, btnHeight)

    if isVertical then
        -- Vertical: buttons flow top-to-bottom, then wrap to the next column.
        -- addButtonsToRight controls column stacking direction.
        local buttonsPerCol = numRows
        if addToRight == false then
            -- Columns stack right-to-left: first column at right edge
            container1:SetPoint("TOPRIGHT", barFrame, "TOPRIGHT", 0, 0)
        else
            -- Columns stack left-to-right (default): first column at left edge
            container1:SetPoint("TOPLEFT", barFrame, "TOPLEFT", 0, 0)
        end

        for i = 2, #buttons do
            local container = buttons[i]:GetParent()
            local rowInCol = (i - 1) % buttonsPerCol  -- 0 = first in new column

            container:ClearAllPoints()
            if rowInCol == 0 then
                -- First button in a new column
                local prevColStart = i - buttonsPerCol
                if addToRight == false then
                    container:SetPoint("TOPRIGHT", buttons[prevColStart]:GetParent(), "TOPLEFT", -spacing, 0)
                else
                    container:SetPoint("TOPLEFT", buttons[prevColStart]:GetParent(), "TOPRIGHT", spacing, 0)
                end
            else
                -- Same column: anchor below previous button
                container:SetPoint("TOPLEFT", buttons[i - 1]:GetParent(), "BOTTOMLEFT", 0, -spacing)
            end
            container:SetSize(btnWidth, btnHeight)
        end
    else
        -- Horizontal: buttons flow left-to-right, then wrap to the next row.
        -- addButtonsToTop controls row stacking direction.
        if addToTop then
            -- Rows stack bottom-to-top: first row at bottom edge
            container1:SetPoint("BOTTOMLEFT", barFrame, "BOTTOMLEFT", 0, 0)
        else
            -- Rows stack top-to-bottom (default): first row at top edge
            container1:SetPoint("TOPLEFT", barFrame, "TOPLEFT", 0, 0)
        end

        for i = 2, #buttons do
            local container = buttons[i]:GetParent()
            local colIndex = ((i - 1) % numCols) + 1

            container:ClearAllPoints()
            if colIndex == 1 then
                -- First container in a new row
                local prevRowStart = buttons[i - numCols]:GetParent()
                if addToTop then
                    -- New row goes ABOVE previous row
                    container:SetPoint("BOTTOMLEFT", prevRowStart, "TOPLEFT", 0, spacing)
                else
                    -- New row goes BELOW previous row
                    container:SetPoint("TOPLEFT", prevRowStart, "BOTTOMLEFT", 0, -spacing)
                end
            else
                -- Same row: anchor to the right of the previous container
                local prevContainer = buttons[i - 1]:GetParent()
                container:SetPoint("LEFT", prevContainer, "RIGHT", spacing, 0)
            end
            container:SetSize(btnWidth, btnHeight)
        end
    end

    -- Re-anchor each button to fill its container (undo any previous cross-hierarchy anchors)
    for i = 1, #buttons do
        buttons[i]:ClearAllPoints()
        buttons[i]:SetAllPoints(buttons[i]:GetParent())
    end
end

-- Restore buttons and containers back to Blizzard's default layout.
-- Invalidates the LayoutFrame so Blizzard can recalculate container positions
-- (e.g., after column/row changes in Edit Mode).
local function RestoreButtonsToContainers()
    if InCombatLockdown() then return end

    local settings = GetGlobalSettings()
    if not settings or settings.buttonSpacing == nil then return end

    for barKey, _ in pairs(BUTTON_PATTERNS) do
        local barFrame = GetBarFrame(barKey)
        local buttons = GetBarButtons(barKey)
        for _, button in ipairs(buttons) do
            -- Restore button to fill its container
            button:ClearAllPoints()
            button:SetAllPoints(button:GetParent())
        end

        -- Invalidate the LayoutFrame so Blizzard recalculates container positions.
        -- The containers are children of a LayoutFrame inside the bar frame.
        -- NOTE: Do NOT clear container anchor points before MarkDirty — doing so
        -- triggers a Blizzard scale-computation bug where the bar frame size is
        -- computed using 1/scale instead of scale, inflating bars by ~scale² factor.
        -- MarkDirty overrides container anchors internally.
        if barFrame and #buttons > 0 then
            local layoutParent = buttons[1]:GetParent():GetParent()
            if layoutParent and layoutParent.MarkDirty then
                layoutParent:MarkDirty()
            elseif layoutParent and layoutParent.Layout then
                layoutParent:Layout()
            end
        end
    end
end

-- Apply spacing override to all standard bars.
local function ApplyAllBarSpacing()
    if InCombatLockdown() then
        ActionBars.pendingSpacing = true
        return
    end

    for barKey, _ in pairs(BUTTON_PATTERNS) do
        ApplyButtonSpacing(barKey)
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

    -- Apply button spacing override (after scale + visibility so positions are final)
    ApplyAllBarSpacing()
end

---------------------------------------------------------------------------
-- MOUSEOVER FADE SYSTEM
---------------------------------------------------------------------------

-- During Edit Mode, fade-outs are suspended so all bars remain visible.
local IsInEditMode = ns.Helpers.IsEditModeShown

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
    if alpha < 1 and ShouldSuspendMouseoverFade(barKey) then
        alpha = 1
    end

    local buttons = GetBarButtons(barKey)
    local settings = GetGlobalSettings()
    local hideEmptyEnabled = settings and settings.hideEmptySlots

    for _, button in ipairs(buttons) do
        local state = GetFrameState(button)
        -- Respect hide empty slots setting - keep empty buttons hidden
        if hideEmptyEnabled and state.hiddenEmpty then
            button:SetAlpha(ActionBars.dragPreviewActive and (DRAG_PREVIEW_ALPHA * alpha) or 0)
        else
            button:SetAlpha(alpha)
        end

        -- Explicitly hide/show QUI-owned textures when the button should be
        -- invisible.  Child textures (especially MOD-blend tintOverlays) may
        -- not respect parent alpha inheritance and keep rendering even when
        -- the button is at alpha 0.
        local hidden = alpha <= 0 or (hideEmptyEnabled and state.hiddenEmpty)
        if hidden then
            FadeHideTextures(state, button)
        elseif state.fadeHidden then
            FadeShowTextures(state, button)
        end
    end

    local barFrame = GetBarFrame(barKey)
    if barFrame then
        barFrame:SetAlpha(alpha)
    end

    if barKey == "bar1" then
        ApplyLeaveVehicleButtonVisibilityOverride(alpha < 1 and ShouldKeepLeaveVehicleVisible())
    end

    GetBarFadeState(barKey).currentAlpha = alpha
end

-- Start smooth fade animation for a bar
local function StartBarFade(barKey, targetAlpha)
    -- Don't fade bars out during Edit Mode — keep everything visible
    if targetAlpha < 1 and IsInEditMode() then return end
    if targetAlpha < 1 and ShouldSuspendMouseoverFade(barKey) then return end

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
                self:SetScript("OnUpdate", nil)
                self:Hide()
            end
        end)
        ActionBars.fadeFrameUpdate = ActionBars.fadeFrame:GetScript("OnUpdate")
    end
    ActionBars.fadeFrame:SetScript("OnUpdate", ActionBars.fadeFrameUpdate)
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
    if ShouldForceShowForSpellBook() then
        SetBarAlpha(barKey, 1)
        return
    end
    if ShouldSuppressMouseoverHideForLevel() then
        SetBarAlpha(barKey, 1)
        return
    end
    if barSettings.alwaysShow then return end

    local fadeEnabled = barSettings.fadeEnabled
    if fadeEnabled == nil then
        fadeEnabled = fadeSettings and fadeSettings.enabled
    end
    if not fadeEnabled then return end

    local state = GetBarFadeState(barKey)

    -- Cancel pending fade-out timers
    CancelBarFadeTimers(state)

    StartBarFade(barKey, 1)
end

-- Start fade-out for a linked bar
local function FadeLinkedBarDirect(barKey)
    if IsInEditMode() then return end

    local barSettings = GetBarSettings(barKey)
    local fadeSettings = GetFadeSettings()

    if not barSettings then return end
    if ShouldForceShowForSpellBook() then
        SetBarAlpha(barKey, 1)
        return
    end
    if ShouldSuppressMouseoverHideForLevel() then
        SetBarAlpha(barKey, 1)
        return
    end
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

    local function TryLinkedFade()
        if ShouldForceShowForSpellBook() then
            SetBarAlpha(barKey, 1)
            state.delayTimer = nil
            return
        end

        if IsSpellFlyoutActiveForBar(barKey) then
            SetBarAlpha(barKey, 1)
            state.delayTimer = C_Timer.NewTimer(SPELL_UI_FADE_RECHECK_DELAY, TryLinkedFade)
            return
        end

        state.delayTimer = nil

        -- Re-check at fade time in case mouse moved back.
        if not IsMouseOverAnyLinkedBar() then
            StartBarFade(barKey, fadeOutAlpha)
        end
    end

    state.delayTimer = C_Timer.NewTimer(delay, TryLinkedFade)
end

-- Handle mouse entering the bar area (event-based, no polling)
local function OnBarMouseEnter(barKey)
    local state = GetBarFadeState(barKey)
    local fadeSettings = GetFadeSettings()
    local barSettings = GetBarSettings(barKey)

    if ShouldSuppressMouseoverHideForLevel() then
        SetBarAlpha(barKey, 1)
        return
    end
    if ShouldForceShowForSpellBook() then
        SetBarAlpha(barKey, 1)
        return
    end

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
    CancelBarFadeTimers(state)

    StartBarFade(barKey, 1)
end

-- Handle mouse leaving a bar element (with delay to check if still over bar)
local function OnBarMouseLeave(barKey)
    if IsInEditMode() then return end

    local state = GetBarFadeState(barKey)
    local fadeSettings = GetFadeSettings()
    local barSettings = GetBarSettings(barKey)

    if ShouldSuppressMouseoverHideForLevel() then
        SetBarAlpha(barKey, 1)
        return
    end
    if ShouldForceShowForSpellBook() then
        SetBarAlpha(barKey, 1)
        return
    end
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

        local function TryFadeOut()
            if state.isMouseOver then
                state.delayTimer = nil
                return
            end

            if ShouldForceShowForSpellBook() then
                SetBarAlpha(barKey, 1)
                state.delayTimer = nil
                return
            end

            if IsSpellFlyoutActiveForBar(barKey) then
                SetBarAlpha(barKey, 1)
                state.delayTimer = C_Timer.NewTimer(SPELL_UI_FADE_RECHECK_DELAY, TryFadeOut)
                return
            end

            -- Read fresh value at fade time in case settings changed.
            local freshBarSettings = GetBarSettings(barKey)
            local freshFadeSettings = GetFadeSettings()
            local freshFadeOutAlpha = freshBarSettings and freshBarSettings.fadeOutAlpha
            if freshFadeOutAlpha == nil then
                freshFadeOutAlpha = freshFadeSettings and freshFadeSettings.fadeOutAlpha or 0
            end
            StartBarFade(barKey, freshFadeOutAlpha)
            state.delayTimer = nil
        end

        state.delayTimer = C_Timer.NewTimer(delay, TryFadeOut)
    end)
end

-- Hook OnEnter/OnLeave on a frame for bar mouseover detection
local function HookFrameForMouseover(frame, barKey)
    if not frame then return end
    local state = GetFrameState(frame)
    if state.mouseoverHooked then return end
    state.mouseoverHooked = true

    frame:HookScript("OnEnter", function()
        OnBarMouseEnter(barKey)
    end)

    frame:HookScript("OnLeave", function()
        OnBarMouseLeave(barKey)
    end)
end

-- Setup mouseover detection for a bar (event-based, no polling)
local function SetupBarMouseover(barKey)
    -- During Edit Mode, keep all bars fully visible
    if IsInEditMode() then
        SetBarAlpha(barKey, 1)
        return
    end

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

    if ShouldSuppressMouseoverHideForLevel() then
        state.isFading = false
        CancelBarFadeTimers(state)
        SetBarAlpha(barKey, 1)
        return
    end

    if ShouldForceShowForSpellBook() then
        state.isFading = false
        CancelBarFadeTimers(state)
        SetBarAlpha(barKey, 1)
        return
    end

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

local SPELLBOOK_UI_ADDONS = {
    Blizzard_PlayerSpells = true,
    Blizzard_SpellBook = true,
}

local function RefreshBarsForSpellBookVisibility()
    if not ActionBars.initialized then return end

    local forceShow = ShouldForceShowForSpellBook()
    for barKey, _ in pairs(BAR_FRAMES) do
        local state = GetBarFadeState(barKey)
        state.isFading = false
        CancelBarFadeTimers(state)

        if forceShow then
            SetBarAlpha(barKey, 1)
        else
            SetupBarMouseover(barKey)
        end
    end
end

local function HookSpellBookVisibilityFrame(frame)
    if not frame then return end

    local state = GetFrameState(frame)
    if state.spellBookVisibilityHooked then return end
    state.spellBookVisibilityHooked = true

    frame:HookScript("OnShow", function()
        C_Timer.After(0, RefreshBarsForSpellBookVisibility)
    end)
    frame:HookScript("OnHide", function()
        C_Timer.After(0, RefreshBarsForSpellBookVisibility)
    end)
end

local function HookSpellBookVisibilityFrames()
    HookSpellBookVisibilityFrame(_G.SpellBookFrame)

    local playerSpellsFrame = _G.PlayerSpellsFrame
    HookSpellBookVisibilityFrame(playerSpellsFrame)
    if playerSpellsFrame and playerSpellsFrame.SpellBookFrame then
        HookSpellBookVisibilityFrame(playerSpellsFrame.SpellBookFrame)
    end
end

local function HandleSpellBookAddonLoaded(addonName)
    if not SPELLBOOK_UI_ADDONS[addonName] then return end
    C_Timer.After(0, function()
        HookSpellBookVisibilityFrames()
        RefreshBarsForSpellBookVisibility()
    end)
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
    if ShouldSuppressMouseoverHideForLevel() then return end

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

        -- Register binding command for LibKeyBound quickbind support.
        -- On pre-Midnight this injects methods directly; on Midnight the patched
        -- Binder reads from our external frameState instead.
        AddKeybindMethods(button, barKey)

        -- Hook OnEnter to register with LibKeyBound when in keybind mode.
        -- HookScript is safe on secure frames (unlike SetScript) because it
        -- appends to the handler chain without replacing the secure handler.
        local state = GetFrameState(button)
        if not state.onEnterHooked then
            state.onEnterHooked = true
            button:HookScript("OnEnter", function(self)
                local LibKeyBound = LibStub("LibKeyBound-1.0", true)
                if LibKeyBound and LibKeyBound:IsShown() then
                    LibKeyBound:Set(self)
                end
            end)
        end

        -- Spell flyout popup buttons are created on click; defer one frame so
        -- they exist before we apply QUI skinning.
        if not state.flyoutSkinHooked then
            state.flyoutSkinHooked = true
            button:HookScript("OnClick", function()
                C_Timer.After(0, function()
                    if SkinSpellFlyoutButtons then
                        SkinSpellFlyoutButtons()
                    end
                end)
            end)
        end

        -- Keep cooldown swipes/proc glows from rendering on hidden buttons.
        -- This also covers pet/stance visibility toggles where Blizzard hides
        -- the button frame entirely (no alpha transition through SetBarAlpha).
        if not state.visibilityEffectsHooked then
            state.visibilityEffectsHooked = true
            button:HookScript("OnHide", function(self)
                local st = GetFrameState(self)
                FadeHideTextures(st, self)
            end)
            button:HookScript("OnShow", function(self)
                local st = GetFrameState(self)
                local key = GetBarKeyFromButton(self)
                local fadeState = key and ActionBars.fadeState and ActionBars.fadeState[key]
                local hideEmptyEnabled = GetGlobalSettings() and GetGlobalSettings().hideEmptySlots
                local shouldStayHidden = (fadeState and fadeState.currentAlpha and fadeState.currentAlpha <= 0)
                    or (hideEmptyEnabled and st.hiddenEmpty)

                if shouldStayHidden then
                    FadeHideTextures(st, self)
                else
                    FadeShowTextures(st, self)
                end
            end)
        end
    end
end

local spellFlyoutSkinHooked = false

local function IsSpellFlyoutButtonFrame(button, flyout)
    if not button then return false end
    if flyout and button.GetParent and button:GetParent() == flyout then
        return true
    end

    local name = button.GetName and button:GetName()
    if not name then return false end

    return name:match("^SpellFlyoutButton%d+$") ~= nil
        or name:match("^SpellFlyoutPopupButton%d+$") ~= nil
end

local function CollectSpellFlyoutButtons(flyout)
    local buttons, seen = {}, {}

    local function AddButton(button)
        if not button or seen[button] then return end
        if not (button.IsObjectType and button:IsObjectType("Button")) then return end
        if not IsSpellFlyoutButtonFrame(button, flyout) then return end

        seen[button] = true
        table.insert(buttons, button)
    end

    if flyout and flyout.GetChildren then
        for _, child in ipairs({flyout:GetChildren()}) do
            AddButton(child)
            if child and child.GetChildren then
                for _, grandChild in ipairs({child:GetChildren()}) do
                    AddButton(grandChild)
                end
            end
        end
    end

    for i = 1, 40 do
        AddButton(_G["SpellFlyoutButton" .. i])
        AddButton(_G["SpellFlyoutPopupButton" .. i])
    end

    return buttons
end

local function GetSpellFlyoutSkinSettings(flyout)
    local sourceBarKey = GetSpellFlyoutSourceBarKey(flyout)
    if sourceBarKey then
        local sourceSettings = GetEffectiveSettings(sourceBarKey)
        if sourceSettings then
            return sourceSettings
        end
    end

    return GetGlobalSettings()
end

local function GetSpellFlyoutSourceButtonSize(flyout)
    local sourceButton = GetSpellFlyoutSourceButton(flyout)
    if not (sourceButton and sourceButton.GetSize) then
        return nil, nil
    end

    local width, height = sourceButton:GetSize()
    if not width or not height or width <= 0 or height <= 0 then
        return nil, nil
    end

    return width, height
end

local function SkinSpellFlyoutContainer(flyout)
    if not flyout then return end

    local bg = flyout.Background
    if not bg then return end

    if bg.Start then bg.Start:SetAlpha(0) end
    if bg.End then bg.End:SetAlpha(0) end
    if bg.HorizontalMiddle then bg.HorizontalMiddle:SetAlpha(0) end
    if bg.VerticalMiddle then bg.VerticalMiddle:SetAlpha(0) end
end

local function ApplySpellFlyoutButtonStateTextures(button)
    if not button then return end

    if button.SetHitRectInsets then
        button:SetHitRectInsets(0, 0, 0, 0)
    end

    local normal = button.GetNormalTexture and button:GetNormalTexture()
    if normal then
        normal:SetAlpha(0)
        normal:ClearAllPoints()
        normal:SetAllPoints(button)
    end

    local pushed = button.GetPushedTexture and button:GetPushedTexture()
    if pushed then
        pushed:SetTexture(TEXTURES.pushed)
        pushed:ClearAllPoints()
        pushed:SetAllPoints(button)
    end

    local checked = button.GetCheckedTexture and button:GetCheckedTexture()
    if checked then
        checked:SetTexture(TEXTURES.checked)
        checked:ClearAllPoints()
        checked:SetAllPoints(button)
    end

    local highlight = button.GetHighlightTexture and button:GetHighlightTexture()
    if highlight then
        highlight:SetTexture(TEXTURES.highlight)
        highlight:ClearAllPoints()
        highlight:SetAllPoints(button)
    end
end

SkinSpellFlyoutButtons = function()
    local flyout = _G.SpellFlyout
    if not (flyout and flyout.IsShown and flyout:IsShown()) then return end

    SkinSpellFlyoutContainer(flyout)

    local settings = GetSpellFlyoutSkinSettings(flyout)
    if not (settings and settings.skinEnabled) then return end

    local sourceWidth, sourceHeight = GetSpellFlyoutSourceButtonSize(flyout)

    for _, button in ipairs(CollectSpellFlyoutButtons(flyout)) do
        if sourceWidth and sourceHeight and button.SetSize then
            button:SetSize(sourceWidth, sourceHeight)
        end
        ApplySpellFlyoutButtonStateTextures(button)
        SkinButton(button, settings)
    end

    -- Rebuild flyout background extents after resizing popup buttons.
    if flyout.Layout then
        flyout:Layout()
    end
end

local function HookSpellFlyoutSkinning()
    if spellFlyoutSkinHooked then return end

    local flyout = _G.SpellFlyout
    if not flyout then return end

    spellFlyoutSkinHooked = true
    flyout:HookScript("OnShow", function()
        C_Timer.After(0, SkinSpellFlyoutButtons)
    end)
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

    SkinSpellFlyoutButtons()
end

---------------------------------------------------------------------------
-- PAGE ARROW VISIBILITY
---------------------------------------------------------------------------

local function CollectPageArrowFrames()
    local seen, frames = {}, {}

    local function AddFrame(frame)
        if not frame or seen[frame] then return end
        if frame.Hide and frame.Show then
            seen[frame] = true
            table.insert(frames, frame)
        end
    end

    local mainBar = _G.MainActionBar or _G.MainMenuBar
    AddFrame(mainBar and mainBar.ActionBarPageNumber)
    AddFrame(_G.ActionBarPageNumber)

    AddFrame(_G.ActionBarUpButton)
    AddFrame(_G.ActionBarDownButton)

    local artFrame = _G.MainMenuBarArtFrame
    AddFrame(artFrame and artFrame.PageNumber)
    AddFrame(artFrame and artFrame.PageUpButton)
    AddFrame(artFrame and artFrame.PageDownButton)

    return frames
end

local ApplyPageArrowVisibility

local function SchedulePageArrowVisibilityRetry()
    if pageArrowRetryTimer or pageArrowRetryAttempts >= PAGE_ARROW_RETRY_MAX_ATTEMPTS then return end
    pageArrowRetryAttempts = pageArrowRetryAttempts + 1
    pageArrowRetryTimer = C_Timer.NewTimer(PAGE_ARROW_RETRY_DELAY, function()
        pageArrowRetryTimer = nil
        local db = GetDB()
        if db and db.bars and db.bars.bar1 then
            ApplyPageArrowVisibility(db.bars.bar1.hidePageArrow)
        end
    end)
end

ApplyPageArrowVisibility = function(hide)
    local frames = CollectPageArrowFrames()
    if #frames == 0 then
        if hide then
            SchedulePageArrowVisibilityRetry()
        end
        return
    end

    pageArrowRetryAttempts = 0
    if pageArrowRetryTimer then
        pageArrowRetryTimer:Cancel()
        pageArrowRetryTimer = nil
    end

    if hide then
        for _, frame in ipairs(frames) do
            frame:Hide()
            if not pageArrowShowHooked[frame] then
                pageArrowShowHooked[frame] = true
                -- TAINT SAFETY: Defer to break taint chain from secure context.
                hooksecurefunc(frame, "Show", function(self)
                    C_Timer.After(0, function()
                        local db = GetDB()
                        if db and db.bars and db.bars.bar1 and db.bars.bar1.hidePageArrow and self and self.Hide then
                            self:Hide()
                        end
                    end)
                end)
            end
        end
    else
        for _, frame in ipairs(frames) do
            frame:Show()
        end
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
        GetFrameState(button).skinKey = nil
    end

    SkinAllBars()
    HookSpellFlyoutSkinning()
    ApplyBarLayoutSettings()
    RefreshBarsForSpellBookVisibility()

    -- Apply page arrow visibility
    local db = GetDB()
    if db and db.bars and db.bars.bar1 then
        ApplyPageArrowVisibility(db.bars.bar1.hidePageArrow)
    end
end

-- Initialize the module
function ActionBars:Initialize()
    if ActionBars.initialized then return end

    local db = GetDB()
    if not db or not db.enabled then
        return
    end

    ActionBars.initialized = true
    ActionBars.levelSuppressionActive = ShouldSuppressMouseoverHideForLevel()

    -- One-time migration for lock setting (preserves user setting after CVar sync fix)
    MigrateLockSetting()

    -- Patch LibKeyBound Binder methods to work without method injection on Midnight
    PatchLibKeyBoundForMidnight()

    -- Hook tooltip suppression for action buttons
    -- NOTE: Synchronous — deferring causes tooltip flash before hide.
    hooksecurefunc("GameTooltip_SetDefaultAnchor", function(tooltip, parent)
        local global = GetGlobalSettings()
        if not global or global.showTooltips ~= false then return end
        local name = parent and parent.GetName and parent:GetName()
        if name and (name:match("^ActionButton") or name:match("^MultiBar") or name:match("^PetActionButton")
            or name:match("^StanceButton") or name:match("^OverrideActionBar") or name:match("^ExtraActionButton")) then
            tooltip:Hide()
            tooltip:SetOwner(UIParent, "ANCHOR_NONE")
            tooltip:ClearLines()
        end
    end)

    -- Initial skin pass
    SkinAllBars()
    HookSpellFlyoutSkinning()

    -- Apply bar layout settings (scale, lock, range indicator, empty slots)
    ApplyBarLayoutSettings()

    -- Hook Blizzard's Layout() on each bar frame to reapply QUI button
    -- spacing after Blizzard's Edit Mode recalculates container positions.
    -- Without this, Edit Mode layout overwrites QUI spacing on reload.
    local _layoutHookGuard = false
    for barKey, _ in pairs(BUTTON_PATTERNS) do
        if barKey ~= "pet" and barKey ~= "stance" then
            local barFrame = GetBarFrame(barKey)
            if barFrame and barFrame.Layout then
                hooksecurefunc(barFrame, "Layout", function()
                    if _layoutHookGuard or not ActionBars.initialized or InCombatLockdown() then return end
                    _layoutHookGuard = true
                    ApplyButtonSpacing(barKey)
                    _layoutHookGuard = false
                end)
            end
        end
    end

    -- Keep bars visible while Spellbook UI is open (optional setting).
    HookSpellBookVisibilityFrames()
    RefreshBarsForSpellBookVisibility()

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

local function RefreshAllButtonVisuals()
    for barKey, _ in pairs(BUTTON_PATTERNS) do
        local effectiveSettings = GetEffectiveSettings(barKey)
        if effectiveSettings then
            local buttons = GetBarButtons(barKey)
            for _, button in ipairs(buttons) do
                UpdateButtonText(button, effectiveSettings)
                UpdateEmptySlotVisibility(button, effectiveSettings)
            end
        end
    end
end

local function QueueAllButtonVisualRefresh(delay)
    if ActionBars.visualRefreshQueued then return end
    ActionBars.visualRefreshQueued = true
    C_Timer.After(delay or VISUAL_REFRESH_DELAY, function()
        ActionBars.visualRefreshQueued = nil
        RefreshAllButtonVisuals()
    end)
end

-- Reapply full skin for bars whose button textures are frequently reset by Blizzard
-- during form/pet/page changes.
local function RefreshReactiveBarSkin(barKey)
    local effectiveSettings = GetEffectiveSettings(barKey)
    if not effectiveSettings then return end

    local buttons = GetBarButtons(barKey)
    if not buttons or #buttons == 0 then return end

    for _, button in ipairs(buttons) do
        local state = GetFrameState(button)
        state.skinKey = nil
        SkinButton(button, effectiveSettings)
        UpdateButtonText(button, effectiveSettings)
        UpdateEmptySlotVisibility(button, effectiveSettings)
    end
end

local function QueueReactiveBarSkinRefresh(delay)
    -- Stance/pet buttons can have their textures reset by Blizzard during
    -- form/page transitions, so queue a dedicated reskin pass for those bars.
    if ActionBars.reactiveSkinRefreshQueued then return end
    ActionBars.reactiveSkinRefreshQueued = true
    C_Timer.After(delay or VISUAL_REFRESH_DELAY, function()
        ActionBars.reactiveSkinRefreshQueued = nil
        RefreshReactiveBarSkin("stance")
        RefreshReactiveBarSkin("pet")
    end)
end

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ACTIONBAR_SLOT_CHANGED")
eventFrame:RegisterEvent("ACTIONBAR_PAGE_CHANGED")
eventFrame:RegisterEvent("UPDATE_BONUS_ACTIONBAR")
eventFrame:RegisterEvent("UPDATE_SHAPESHIFT_FORM")
eventFrame:RegisterEvent("UPDATE_SHAPESHIFT_FORMS")
eventFrame:RegisterEvent("UPDATE_STEALTH")
eventFrame:RegisterEvent("UPDATE_BINDINGS")
eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
eventFrame:RegisterEvent("CURSOR_CHANGED")
eventFrame:RegisterEvent("PLAYER_LEVEL_UP")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("UPDATE_VEHICLE_ACTIONBAR")
eventFrame:RegisterEvent("UNIT_ENTERED_VEHICLE")
eventFrame:RegisterEvent("UNIT_EXITED_VEHICLE")
eventFrame:RegisterEvent("ADDON_LOADED")

eventFrame:SetScript("OnEvent", function(self, event, ...)
    if event == "ADDON_LOADED" then
        local addonName = ...
        if addonName == ADDON_NAME then
            ActionBars:Initialize()
        end
        HandleSpellBookAddonLoaded(addonName)
        if addonName == "Blizzard_ActionBar" then
            HookSpellFlyoutSkinning()
            C_Timer.After(0, SkinSpellFlyoutButtons)
            local db = GetDB()
            if db and db.bars and db.bars.bar1 then
                C_Timer.After(0, function()
                    ApplyPageArrowVisibility(db.bars.bar1.hidePageArrow)
                end)
            end
        end

    elseif event == "ACTIONBAR_SLOT_CHANGED" then
        -- Defer slot-change processing during combat to avoid taint
        if InCombatLockdown() then
            ActionBars.pendingSlotUpdate = true
            return
        end
        -- Re-apply text styling and empty slot visibility when actions change
        QueueAllButtonVisualRefresh(0.1)

    elseif event == "ACTIONBAR_PAGE_CHANGED"
        or event == "UPDATE_BONUS_ACTIONBAR"
        or event == "UPDATE_SHAPESHIFT_FORM"
        or event == "UPDATE_SHAPESHIFT_FORMS"
        or event == "UPDATE_STEALTH" then
        -- Paging/form changes can happen in combat (e.g. druid shapeshifts).
        -- Refresh QUI-managed visuals immediately so displayed buttons match
        -- the active page even while combat lockdown defers slot updates.
        QueueAllButtonVisualRefresh(0.05)
        QueueReactiveBarSkinRefresh(0.05)

    elseif event == "CURSOR_CHANGED" then
        -- Show/hide drag preview on hidden empty slots
        local settings = GetGlobalSettings()
        if settings and settings.hideEmptySlots then
            local shouldPreview = CursorHasPlaceableAction()
            if shouldPreview ~= (ActionBars.dragPreviewActive or false) then
                ActionBars.dragPreviewActive = shouldPreview or nil
                for barKey, _ in pairs(BUTTON_PATTERNS) do
                    local effectiveSettings = GetEffectiveSettings(barKey)
                    if effectiveSettings then
                        local buttons = GetBarButtons(barKey)
                        for _, button in ipairs(buttons) do
                            local state = GetFrameState(button)
                            if state.hiddenEmpty then
                                local fadeState = ActionBars.fadeState and ActionBars.fadeState[barKey]
                                local targetAlpha = fadeState and fadeState.currentAlpha or 1
                                button:SetAlpha(shouldPreview and (DRAG_PREVIEW_ALPHA * targetAlpha) or 0)
                            end
                        end
                    end
                end
            end
        end

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

    elseif event == "PLAYER_LEVEL_UP" then
        if UpdateLevelSuppressionState() then
            if type(_G.QUI_RefreshActionBars) == "function" then
                _G.QUI_RefreshActionBars()
            end
        end

    elseif event == "PLAYER_ENTERING_WORLD" then
        local isLogin, isReload = ...
        if (isLogin or isReload) and not ActionBars.initialWorldRefreshQueued then
            -- Initialization now runs at ADDON_LOADED. Some Blizzard bar buttons
            -- (especially stance/pet variants) can be created slightly later, so
            -- schedule one delayed full refresh to ensure they get skinned.
            ActionBars.initialWorldRefreshQueued = true
            C_Timer.After(WORLD_INITIAL_REFRESH_DELAY, function()
                if type(_G.QUI_RefreshActionBars) == "function" then
                    _G.QUI_RefreshActionBars()
                end
            end)
        end
        if isReload then
            if not InCombatLockdown() then
                -- Second spacing pass during combat /reload safe window.
                ApplyAllBarSpacing()
            end
            -- Safety net: Blizzard's Layout() may fire after safe window
            -- closes. Mark pending so PLAYER_REGEN_ENABLED reapplies.
            ActionBars.pendingSpacing = true
        end
        if UpdateLevelSuppressionState() then
            if type(_G.QUI_RefreshActionBars) == "function" then
                _G.QUI_RefreshActionBars()
            end
        end
        local db = GetDB()
        if db and db.bars and db.bars.bar1 then
            C_Timer.After(0.1, function()
                ApplyPageArrowVisibility(db.bars.bar1.hidePageArrow)
            end)
            C_Timer.After(0.6, function()
                ApplyPageArrowVisibility(db.bars.bar1.hidePageArrow)
            end)
        end

    elseif event == "UPDATE_VEHICLE_ACTIONBAR" then
        C_Timer.After(0.05, function()
            SetupBarMouseover("bar1")
        end)

    elseif event == "UNIT_ENTERED_VEHICLE" or event == "UNIT_EXITED_VEHICLE" then
        local unit = ...
        if unit ~= "player" then return end
        C_Timer.After(0.05, function()
            SetupBarMouseover("bar1")
        end)

    elseif event == "PLAYER_REGEN_ENABLED" then
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
        -- Re-apply button spacing that was deferred during combat
        if ActionBars.pendingSpacing then
            ActionBars.pendingSpacing = false
            ApplyAllBarSpacing()
        end
        -- Process slot changes deferred from combat
        if ActionBars.pendingSlotUpdate then
            ActionBars.pendingSlotUpdate = false
            QueueAllButtonVisualRefresh(0.1)
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
-- Suspend mouseover fade and show extra button movers during Edit Mode
---------------------------------------------------------------------------

-- Use central Edit Mode dispatcher to avoid taint from multiple hooksecurefunc
-- callbacks on EnterEditMode/ExitEditMode.
do
    local core = GetCore()
    if core and core.RegisterEditModeEnter then
        core:RegisterEditModeEnter(function()
            -- Restore Blizzard's default layout so Edit Mode can properly manage
            -- button counts and bar sizing.  QUI's spacing override will be
            -- re-applied when Edit Mode exits.
            RestoreButtonsToContainers()

            -- Force all bars to full opacity and cancel pending fades
            for barKey, state in pairs(ActionBars.fadeState) do
                state.isFading = false
                if state.delayTimer then
                    state.delayTimer:Cancel()
                    state.delayTimer = nil
                end
                if state.leaveCheckTimer then
                    state.leaveCheckTimer:Cancel()
                    state.leaveCheckTimer = nil
                end
                SetBarAlpha(barKey, 1)
            end

            -- Show extra button movers when QUI extra button feature is enabled
            local extraSettings = GetExtraButtonDB("extraActionButton")
            local zoneSettings = GetExtraButtonDB("zoneAbility")
            if (extraSettings and extraSettings.enabled) or (zoneSettings and zoneSettings.enabled) then
                ShowExtraButtonMovers()
            end

        end)

        core:RegisterEditModeExit(function()
            HideExtraButtonMovers()

            -- Resume mouseover fade for all bars
            for barKey, _ in pairs(BAR_FRAMES) do
                SetupBarMouseover(barKey)
            end

            -- Re-apply button spacing after Blizzard re-layouts buttons on Edit Mode exit
            C_Timer.After(0, function()
                ApplyAllBarSpacing()
            end)
        end)
    end
end

---------------------------------------------------------------------------
-- EXPOSE MODULE
---------------------------------------------------------------------------

local core = GetCore()
if core then
    core.ActionBars = ActionBars
end
