local ADDON_NAME, ns = ...
local env = ns.ActionBarsEnv
env.ADDON_NAME = ADDON_NAME
env.ns = ns
env.SetChunkEnv(1, env)

---------------------------------------------------------------------------
-- DB ACCESSORS
---------------------------------------------------------------------------

GetDB = Helpers.CreateDBGetter("actionBars")

function GetSafeActionSlot(button)
    if not button then return nil end
    local action = button.action
    if action == nil or Helpers.IsSecretValue(action) then
        return nil
    end
    local ok, numericAction = pcall(tonumber, action)
    if not ok or type(numericAction) ~= "number" or numericAction < 1 then
        return nil
    end
    return numericAction
end

function GetGlobalSettings()
    local db = GetDB()
    return db and db.global
end

function GetBarSettings(barKey)
    local db = GetDB()
    return db and db.bars and db.bars[barKey]
end

function GetFadeSettings()
    local db = GetDB()
    return db and db.fade
end

effectiveSettingsCache = {}
effectiveSettingsCacheStats = { hits = 0, builds = 0, invalidations = 0 }

do local mp = ns._memprobes or {}; ns._memprobes = mp
    mp[#mp + 1] = { name = "AB_settingsCacheHits", counter = true, fn = function() return effectiveSettingsCacheStats.hits end }
    mp[#mp + 1] = { name = "AB_settingsCacheBuilds", counter = true, fn = function() return effectiveSettingsCacheStats.builds end }
    mp[#mp + 1] = { name = "AB_settingsCacheInvalidations", counter = true, fn = function() return effectiveSettingsCacheStats.invalidations end }
end

function InvalidateEffectiveSettingsCache(barKey)
    effectiveSettingsCacheStats.invalidations = effectiveSettingsCacheStats.invalidations + 1
    if barKey then
        effectiveSettingsCache[barKey] = nil
        return
    end

    for key in pairs(effectiveSettingsCache) do
        effectiveSettingsCache[key] = nil
    end
end

-- Effective settings (global merged with per-bar overrides)
function GetEffectiveSettings(barKey)
    local global = GetGlobalSettings()
    if not global then return nil end

    local barSettings = GetBarSettings(barKey)
    if not barSettings then
        return global
    end

    local cached = effectiveSettingsCache[barKey]
    if cached and cached.global == global and cached.bar == barSettings then
        effectiveSettingsCacheStats.hits = effectiveSettingsCacheStats.hits + 1
        return cached.effective
    end

    effectiveSettingsCacheStats.builds = effectiveSettingsCacheStats.builds + 1
    local effective = {}
    for key, value in pairs(global) do
        effective[key] = value
    end
    for key, value in pairs(barSettings) do
        effective[key] = value
    end

    effectiveSettingsCache[barKey] = {
        global = global,
        bar = barSettings,
        effective = effective,
    }
    return effective
end

ActionBarsOwned.GetEffectiveSettings = GetEffectiveSettings
ActionBarsOwned.InvalidateEffectiveSettingsCache = InvalidateEffectiveSettingsCache

---------------------------------------------------------------------------
-- HELPERS
---------------------------------------------------------------------------

-- Safe wrappers for APIs that may return secret values on Midnight.
-- Use only truthiness tests (if X then) — never comparison operators
-- (==, ~=, >) — so secret booleans/numbers pass through without error.
-- No pcall needed since truthiness evaluation never triggers the
-- secret-value error (only comparisons and arithmetic do).
SafeHasAction = function(action)
    if HasAction(action) then return true end
    return false
end

HasButtonContent = function(button, action)
    if button and button.GetAttribute and button:GetAttribute("gse-button") then
        return true
    end
    if action then
        return SafeHasAction(action)
    end
    return false
end

function SafeIsActionInRange(action)
    -- Returns: true (in range), false (out of range), nil (no range data).
    -- pcall guards against internal errors; truthiness tests are safe for
    -- secret values.  The `== nil` check is safe because Lua never invokes
    -- __eq metamethods when comparing against nil (different types).
    local ok, val = pcall(IsActionInRange, action)
    if not ok then return nil end
    if val then return true end        -- truthy → in range
    if val == nil then return nil end  -- nil → no range data
    return false                       -- falsy non-nil → out of range
end

function SafeIsUsableAction(action)
    local usable, noMana = IsUsableAction(action)
    -- Convert via truthiness (and/or), not comparison
    return (usable and true or false), (noMana and true or false)
end

function IsPlayerBelowMaxLevel()
    local level = UnitLevel("player")
    if not level or level <= 0 then return false end

    local maxLevel = GetMaxLevelForPlayerExpansion and GetMaxLevelForPlayerExpansion() or MAX_PLAYER_LEVEL or 80
    if not maxLevel or maxLevel <= 0 then return false end

    return level < maxLevel
end

function ShouldSuppressMouseoverHideForLevel()
    local fadeSettings = GetFadeSettings()
    return fadeSettings and fadeSettings.disableBelowMaxLevel and IsPlayerBelowMaxLevel()
end

function IsLeaveVehicleButtonVisible()
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

function ShouldKeepLeaveVehicleVisible()
    local fadeSettings = GetFadeSettings()
    if not (fadeSettings and fadeSettings.keepLeaveVehicleVisible) then
        return false
    end
    return IsLeaveVehicleButtonVisible()
end

function ApplyLeaveVehicleButtonVisibilityOverride(forceVisible)
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

function IsSpellBookVisible()
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

function ShouldForceShowForSpellBook()
    local fadeSettings = GetFadeSettings()
    return fadeSettings and fadeSettings.showWhenSpellBookOpen and IsSpellBookVisible()
end

function GetSpellFlyoutSourceButton(flyout)
    if not flyout then return nil end

    local sourceButton = rawget(flyout, "flyoutButton")
    if not sourceButton and flyout.GetParent then
        sourceButton = flyout:GetParent()
    end

    return sourceButton
end

function GetSpellFlyoutSourceBarKey(flyout)
    local sourceButton = GetSpellFlyoutSourceButton(flyout)
    if not sourceButton then return nil end

    local name = sourceButton.GetName and sourceButton:GetName()
    if not name then return nil end

    if name:match("^ActionButton%d+$") then return "bar1" end
    if name:match("^QUI_Bar1Button%d+$") then return "bar1" end
    if name:match("^QUI_Bar2Button%d+$") then return "bar2" end
    if name:match("^QUI_Bar3Button%d+$") then return "bar3" end
    if name:match("^QUI_Bar4Button%d+$") then return "bar4" end
    if name:match("^QUI_Bar5Button%d+$") then return "bar5" end
    if name:match("^QUI_Bar6Button%d+$") then return "bar6" end
    if name:match("^QUI_Bar7Button%d+$") then return "bar7" end
    if name:match("^QUI_Bar8Button%d+$") then return "bar8" end
    if name:match("^MultiBarBottomLeftButton%d+$") then return "bar2" end
    if name:match("^MultiBarBottomRightButton%d+$") then return "bar3" end
    if name:match("^MultiBarRightButton%d+$") then return "bar4" end
    if name:match("^MultiBarLeftButton%d+$") then return "bar5" end
    if name:match("^MultiBar5Button%d+$") then return "bar6" end
    if name:match("^MultiBar6Button%d+$") then return "bar7" end
    if name:match("^MultiBar7Button%d+$") then return "bar8" end
    if name:match("^QUI_PetButton%d+$") or name:match("^PetActionButton%d+$") then return "pet" end
    if name:match("^QUI_StanceButton%d+$") or name:match("^StanceButton%d+$") then return "stance" end

    return nil
end

function IsSpellFlyoutActiveForBar(barKey)
    if not barKey then return false end

    local activeFlyouts = {
        _G.QUI_SpellFlyout,
        _G.SpellFlyout,
    }

    for _, flyout in ipairs(activeFlyouts) do
        if flyout and flyout.IsShown and flyout:IsShown() then
            local sourceBarKey = GetSpellFlyoutSourceBarKey(flyout)
            if sourceBarKey == barKey then
                return true
            end
        end
    end

    return false
end

function ShouldSuspendMouseoverFade(barKey)
    return ShouldForceShowForSpellBook() or IsSpellFlyoutActiveForBar(barKey)
end

SPELL_UI_FADE_RECHECK_DELAY = 0.1

function CancelBarFadeTimers(state)
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

function UpdateLevelSuppressionState()
    local suppress = ShouldSuppressMouseoverHideForLevel()
    if ActionBarsOwned.levelSuppressionActive == suppress then
        return false
    end
    ActionBarsOwned.levelSuppressionActive = suppress
    return true
end

function GetFontSettings()
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
function GetBarKeyFromButton(button)
    if button and button._quiBarKey then return button._quiBarKey end

    local getName = button and button.GetName
    local name = getName and getName(button)
    if not name then return nil end

    if name:match("^ActionButton%d+$") then return "bar1" end
    if name:match("^QUI_Bar1Button%d+$") then return "bar1" end
    if name:match("^QUI_Bar2Button%d+$") then return "bar2" end
    if name:match("^QUI_Bar3Button%d+$") then return "bar3" end
    if name:match("^QUI_Bar4Button%d+$") then return "bar4" end
    if name:match("^QUI_Bar5Button%d+$") then return "bar5" end
    if name:match("^QUI_Bar6Button%d+$") then return "bar6" end
    if name:match("^QUI_Bar7Button%d+$") then return "bar7" end
    if name:match("^QUI_Bar8Button%d+$") then return "bar8" end
    if name:match("^MultiBarBottomLeftButton%d+$") then return "bar2" end
    if name:match("^MultiBarBottomRightButton%d+$") then return "bar3" end
    if name:match("^MultiBarRightButton%d+$") then return "bar4" end
    if name:match("^MultiBarLeftButton%d+$") then return "bar5" end
    if name:match("^MultiBar5Button%d+$") then return "bar6" end
    if name:match("^MultiBar6Button%d+$") then return "bar7" end
    if name:match("^MultiBar7Button%d+$") then return "bar8" end
    if name:match("^QUI_PetButton%d+$") or name:match("^PetActionButton%d+$") then return "pet" end
    if name:match("^QUI_StanceButton%d+$") or name:match("^StanceButton%d+$") then return "stance" end
    return nil
end

-- Get button index from button name
function GetButtonIndex(button)
    if not button then return nil end
    local index = button._quiButtonIndex
    if type(index) == "number" then return index end
    if button.GetAttribute then
        index = button:GetAttribute("qui-button-index")
        if type(index) == "number" then return index end
        index = tonumber(index)
        if index then return index end
    end

    local getName = button.GetName
    local name = getName and getName(button)
    if not name then return nil end
    return tonumber(name:match("%d+$"))
end

function GetBarFrame(barKey)
    local frameName = BAR_FRAMES[barKey]
    local frame = frameName and _G[frameName]
    if not frame and barKey == "bar1" then
        frame = _G["MainMenuBar"]
    end
    return frame
end

function GetBarButtons(barKey)
    -- If the native engine has built this bar, return our managed buttons
    -- instead of looking up Blizzard globals (which may be hidden/reparented).
    local native = ActionBarsOwned.nativeButtons[barKey]
    if native and #native > 0 then
        return native
    end

    local buttons = {}

    -- Special handling for non-standard bars
    if barKey == "microbar" then
        for _, name in ipairs(MICRO_BUTTON_NAMES) do
            local btn = _G[name]
            if btn then
                table.insert(buttons, btn)
            end
        end
        return buttons
    elseif barKey == "bags" then
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
        if ExtraActionBarFrame and ExtraActionBarFrame.button then
            table.insert(buttons, ExtraActionBarFrame.button)
        end
        return buttons
    elseif barKey == "zoneAbility" then
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

---------------------------------------------------------------------------
-- MIDNIGHT LIBKEYBOUND COMPATIBILITY
-- On Midnight (12.0+) we cannot inject methods onto secure action buttons
-- without spreading taint. Instead we override LibKeyBound's Binder methods
-- to consult our external frameState table for binding commands.
-- UNIFIED: keybind registration writes to this same frameState.
---------------------------------------------------------------------------

libKeyBoundPatched = false

function PatchLibKeyBoundForMidnight()
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

-- Register keybind command for LibKeyBound quickbind support.
-- Sets bindingCommand in frameState so the patched Binder can find it.
function AddKeybindMethods(button, barKey)
    local prefix = BINDING_COMMANDS[barKey]
    if not prefix then return end
    local index = GetButtonIndex(button)
    if not index then return end
    local state = GetFrameState(button)
    state.bindingCommand = prefix .. index
    state.keybindMethods = true
end

-- Check if the cursor is holding a placeable action (for drag preview)
function CursorHasPlaceableAction()
    local infoType = GetCursorInfo()
    return infoType == "spell" or infoType == "item" or infoType == "macro"
        or infoType == "petaction" or infoType == "mount" or infoType == "flyout"
end

-- Visual refresh after secure drag pickup/place.
-- PickupAction/PlaceAction are handled entirely by the secure
-- WrapScript pre-bodies (see button setup) which return
-- "action", slot to the secure framework.  These Lua hooks only
-- refresh button visuals after the secure handler completes.
function OwnedButton_PostDrag(self)
    ActionBarsOwned.SafeUpdate(self)
    -- Immediate re-skin to prevent blank flash between SafeUpdate stripping
    -- Blizzard artwork and the deferred SkinButton restoring QUI textures.
    local bk = GetBarKeyFromButton(self)
    local s = bk and GetEffectiveSettings(bk)
    if s then
        local st = GetFrameState(self)
        st.sk_sz = nil
        SkinButton(self, s)
        UpdateButtonText(self, s)
        UpdateEmptySlotVisibility(self, s)
    end
    -- Slot data may lag by one frame after pickup/place — refresh again
    C_Timer.After(0, function()
        ActionBarsOwned.SafeUpdate(self)
        if s then
            local st = GetFrameState(self)
            st.sk_sz = nil
            SkinButton(self, s)
            UpdateButtonText(self, s)
            UpdateEmptySlotVisibility(self, s)
        end
    end)
end

---------------------------------------------------------------------------
-- CONTAINER FACTORY
---------------------------------------------------------------------------

function CreateBarContainer(barKey)
    local containerName = "QUI_ActionBar_" .. barKey
    local container = CreateFrame("Frame", containerName, UIParent, "SecureHandlerStateTemplate")
    container:SetSize(1, 1)
    container:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    container:Show()
    container:SetClampedToScreen(true)

    -- Override / vehicle / possess / petbattle visibility gate.
    --
    -- Blizzard's OverrideActionBar and the pet battle UI take over input
    -- during those states; leaving any QUI bar visible would draw
    -- duplicate or empty icons.  We can't use the reserved "visibility"
    -- state driver because it unconditionally Show()s the frame when the
    -- macro doesn't match, which would clobber bars the user has
    -- disabled (bar7/8 off, no-stance stance bar, etc.).
    --
    -- Instead, use a custom state handler that hides on override but
    -- only re-shows when the frame's "qui-user-shown" attribute is true.
    -- Lua code that controls visibility (disable, GetNumShapeshiftForms)
    -- sets qui-user-shown alongside Show/Hide calls via
    -- SetBarContainerShown() below.
    --
    -- Pet bar additionally folds the [nopet] macro condition into its
    -- driver below so pet summon/dismiss flips visibility from inside
    -- the secure snippet (works in combat without any tainted Lua).
    container:SetAttribute("qui-user-shown", true)
    container:SetAttribute("_onstate-quioverride", [[
        if newstate == "hide" then
            self:Hide()
        elseif self:GetAttribute("qui-user-shown") then
            self:Show()
        end
    ]])
    local driver = "[overridebar][vehicleui][possessbar][petbattle] hide; show"
    if barKey == "pet" then
        driver = "[overridebar][vehicleui][possessbar][petbattle][nopet] hide; show"
        -- The [nopet] secure driver flips Show/Hide asynchronously when pet
        -- status changes (including in combat). Notify dependents (e.g.
        -- stance bar anchored to petBar) so they re-anchor when that happens.
        local function notifyAnchor()
            if _G.QUI_UpdateFramesAnchoredTo then
                _G.QUI_UpdateFramesAnchoredTo("petBar")
            end
        end
        container:HookScript("OnShow", notifyAnchor)
        container:HookScript("OnHide", notifyAnchor)
    end
    RegisterStateDriver(container, "quioverride", driver)

    return container
end

-- Central helper for toggling a bar container's intended visibility.
-- Sets the qui-user-shown attribute so the override/vehicle state driver
-- knows whether to re-show the bar on exit, and calls Show/Hide to apply
-- the change immediately (when out of combat).
function SetBarContainerShown(container, shown)
    if not container then return end
    container:SetAttribute("qui-user-shown", shown and true or false)
    if InCombatLockdown() then return end
    if shown then
        container:Show()
    else
        if ActionBarsOwned and ActionBarsOwned.HideOwnedFlyout then
            ActionBarsOwned.HideOwnedFlyout()
        end
        container:Hide()
    end
end

function InstallSecureActionFlagRefresh(btn)
    if not btn or btn._quiActionFlagRefreshInstalled then return end
    btn._quiActionFlagRefreshInstalled = true
    btn:SetAttribute("QUI_UpdateActionFlags", [[
        local action = self:GetAttribute("action")
        local gseButton = self:GetAttribute("gse-button")
        local pressAndHold = false

        if gseButton then
            -- When useOnKeyDown=true, the press fires the click → forwards to the
            -- sequence frame and advances the step.  typerelease="click" would fire
            -- a SECOND click on release, double-advancing the sequence.  Clear it
            -- in that mode; keep it for useOnKeyDown=false so release-mode still
            -- forwards reliably even when BAR_SWAP flips type to "action".
            if self:GetAttribute("useOnKeyDown") then
                self:SetAttribute("typerelease", nil)
            else
                self:SetAttribute("typerelease", "click")
            end
            self:SetAttribute("pressAndHoldAction", false)
            return
        end

        self:SetAttribute("typerelease", "actionrelease")
        if action and IsPressHoldReleaseSpell then
            local actionType, id, subType = GetActionInfo(action)
            if actionType == "spell" then
                pressAndHold = IsPressHoldReleaseSpell(id)
            elseif actionType == "macro" and subType == "spell" then
                pressAndHold = IsPressHoldReleaseSpell(id)
            end
        end

        self:SetAttribute("pressAndHoldAction", pressAndHold)
    ]])
end
ActionBarsOwned.SetBarContainerShown = SetBarContainerShown

env.__declared.EnsureOwnedFlyoutFrame = true
env.__declared.SyncOwnedFlyoutInfoToHandler = true

