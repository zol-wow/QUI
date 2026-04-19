--[[
    QUI Action Bars - Native Engine
    Creates native ActionButtonTemplate buttons (bar 1) or reparents
    Blizzard's existing buttons (bars 2-8) into QUI-owned containers.
    Buttons get native icon, cooldown, count, drag/pickup, and keybind
    behavior. QUI handles skinning, layout, fade, and empty slot hiding.
]]

local ADDON_NAME, ns = ...
local Helpers = ns.Helpers
local GetCore = Helpers.GetCore
local LSM = ns.LSM

-- Upvalue caching for hot-path performance
local type = type
local pairs = pairs
local ipairs = ipairs
local pcall = pcall
local C_Timer = C_Timer
local InCombatLockdown = InCombatLockdown

-- ADDON_LOADED safe window flag: during a combat /reload, InCombatLockdown()
-- returns true but protected calls are still allowed. This flag lets
-- initialization sub-functions bypass their combat guards.
local inInitSafeWindow = false

---------------------------------------------------------------------------
-- MIDNIGHT (12.0+) DETECTION
---------------------------------------------------------------------------

local IS_MIDNIGHT = select(4, GetBuildInfo()) >= 120000

-- LOCAL suppression of GetActionCount on Midnight (same approach as
-- action button addons).  Must be local — replacing the global taints every
-- Blizzard button that calls it, causing SetCooldown secret-value errors
-- on the hidden original MultiBar buttons we don't own.
local GetActionCount = GetActionCount
if IS_MIDNIGHT then
    GetActionCount = function() return 0 end
end

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

-- Explicit micro button names (stable list, not dependent on GetChildren order)
local MICRO_BUTTON_NAMES = {
    "CharacterMicroButton", "ProfessionMicroButton", "PlayerSpellsMicroButton",
    "AchievementMicroButton", "QuestLogMicroButton", "HousingMicroButton",
    "GuildMicroButton", "LFDMicroButton", "CollectionsMicroButton",
    "EJMicroButton", "StoreMicroButton", "MainMenuMicroButton",
}

-- Standard action bar keys (bars 1-8, not pet/stance)
local STANDARD_BAR_KEYS = {"bar1", "bar2", "bar3", "bar4", "bar5", "bar6", "bar7", "bar8"}

-- All managed bar keys (includes pet/stance/microbar/bags which are reparented into owned containers)
local ALL_MANAGED_BAR_KEYS = {"bar1", "bar2", "bar3", "bar4", "bar5", "bar6", "bar7", "bar8", "pet", "stance", "microbar", "bags"}

-- Bars that receive action bar skinning (icon crop, backdrop, gloss, keybind text, etc.)
-- Micro menu and bag bar buttons are NOT action buttons and should not be skinned.
local SKINNABLE_BAR_KEYS = {
    bar1 = true, bar2 = true, bar3 = true, bar4 = true,
    bar5 = true, bar6 = true, bar7 = true, bar8 = true,
    pet = true, stance = true,
}

---------------------------------------------------------------------------
-- MODULE STATE
---------------------------------------------------------------------------

local ActionBarsOwned = {
    initialized = false,
    containers = {},       -- barKey → container frame
    nativeButtons = {},    -- barKey → { button, ... } (native ActionButtonTemplate or reparented Blizzard)
    cachedLayouts = {},    -- barKey → { numCols, numRows, isVertical, numIcons }
    editModeActive = false,
    editOverlays = {},     -- barKey → overlay frame
    fadeState = {},         -- barKey → fade state (shared by all fade subsystems)
    pendingExtraButtonRefresh = false,
    pendingExtraButtonInit = false,
    skinnedButtons = {},    -- button → true (tracking for re-skin on updates)
}
ns.ActionBarsOwned = ActionBarsOwned

-- Forward declaration: defined ~line 3296, called from SafeUpdate (below)
local UpdateAssistedCombatRotationFrame
local UpdateAllAssistedHighlights
-- Forward declaration: defined in usability section, called from OnOwnedEvent
local ScheduleUsabilityUpdate

-- Backward compat alias for any code referencing mirrorButtons
ActionBarsOwned.mirrorButtons = ActionBarsOwned.nativeButtons

-- Taint-safe UpdateAction replacement.  The mixin's UpdateAction calls
-- ActionButton_CalculateAction and uses comparison operators, which can
-- error in tainted context during combat.  This version just syncs the
-- Lua-side self.action from the attribute (set by restricted code) and
-- triggers a safe visual refresh.  Called explicitly via CallMethod from
-- the _childupdate-offset restricted snippet after page changes, and
-- also installed as an instance shadow so any residual mixin path that
-- reaches UpdateAction hits this safe version.
function ActionBarsOwned.SafeSyncAction(self)
    local oldAction = self.action
    local action = self:GetAttribute("action")
    if action then
        self.action = action
        -- Keep slotMap in sync when bar 1 pages (action ID changes)
        local slotMap = ActionBarsOwned.slotMap
        if slotMap then
            if oldAction and oldAction ~= action then
                slotMap[oldAction] = nil
            end
            if action > 0 then
                local entry = slotMap[action]
                if entry then
                    entry.button = self
                else
                    slotMap[action] = { button = self, barKey = "bar1" }
                end
            end
        end
    end
    -- Re-register with C-side after page change so it pushes updates
    -- for the new action (critical for assisted combat rotation).
    if SetActionUIButton and action and self.cooldown then
        SetActionUIButton(self, action, self.cooldown)
    end
    ActionBarsOwned.SafeUpdate(self)
    -- Refresh assisted combat highlights after page change — the button
    -- now shows a different spell so the old highlight may be stale.
    if oldAction and oldAction ~= action and UpdateAllAssistedHighlights then
        UpdateAllAssistedHighlights()
    end
end

-- Taint-safe Update replacement for addon-created action buttons.
-- The Blizzard mixin's Update uses comparison operators (==, ~=, >) on
-- secret number values returned by restricted APIs, which errors when
-- the button is tainted.  This version uses ONLY truthiness tests
-- (if X then) on API returns — Lua evaluates truthiness without
-- comparison operators, so secret booleans/numbers pass through safely.
-- Installed as an instance shadow so any residual mixin path that
-- reaches self:Update() hits this safe version.
-- Pre-filtered "buttons with an action" set. Mirrors LibActionButton's
-- ActiveButtons pattern: maintained by SafeUpdate, consumed by the centralized
-- state/usable/cooldown loops so they skip empty slots without an O(N)
-- iterate + HasAction check every tick. Weak-keyed so destroyed buttons
-- drop out automatically.
ActionBarsOwned._activeButtons = ActionBarsOwned._activeButtons
    or setmetatable({}, { __mode = "k" })

local UpdateButtonProfessionQuality

function ActionBarsOwned.SafeUpdate(self)
    local action = self.action
    if not action then return end

    if HasAction(action) then
        ActionBarsOwned._activeButtons[self] = true
        -- Icon — GSE override buttons use the sequence macro icon instead
        -- of the action slot texture, so SafeUpdate doesn't overwrite it.
        local gseSeq = self:GetAttribute("gse-button")
        local texture
        if gseSeq then
            -- Prefer the compiled macro icon registered by GSE
            if GetMacroIndexByName then
                local idx = GetMacroIndexByName(gseSeq)
                if idx and idx > 0 then
                    local _, macTex = GetMacroInfo(idx)
                    texture = macTex
                end
            end
            -- Fall back to the action slot texture (may be the original
            -- spell icon, which is still a reasonable fallback)
            if not texture then
                texture = GetActionTexture(action)
            end
        else
            texture = GetActionTexture(action)
        end
        if texture then
            self.icon:SetTexture(texture)
            self.icon:Show()
            if self.SlotBackground then self.SlotBackground:Hide() end
        else
            self.icon:Hide()
            if self.SlotBackground then self.SlotBackground:Show() end
        end

        UpdateButtonProfessionQuality(self)

        self:SetAlpha(1.0)

        -- Checked state (autoattack, toggle abilities)
        if IsCurrentAction(action) or IsAutoRepeatAction(action) then
            self:SetChecked(true)
        else
            self:SetChecked(false)
        end

        -- Usability coloring is handled entirely by the QUI tint overlay
        -- system (UpdateButtonUsability).  Keep icon vertex color neutral
        -- so the overlay is the sole source of range/mana/unusable tinting.
        self.icon:SetVertexColor(1, 1, 1)

        -- Equipped border
        if IsEquippedAction(action) then
            self.Border:SetVertexColor(0, 1, 0, 0.35)
            self.Border:Show()
        else
            self.Border:Hide()
        end

        -- Action text (macro name)
        self.Name:SetText(GetActionText(action) or "")

        -- Delegated to shadowed methods
        self:UpdateCount()
        self:UpdateCooldown()

        -- Proc glow (spell activation overlay)
        ActionBarsOwned.UpdateOverlayGlow(self)

        -- Flyout arrow
        if self.UpdateFlyout then
            pcall(self.UpdateFlyout, self)
        end

        -- Assisted combat rotation arrow (one-button rotation).
        -- Set everActive flag here — SafeUpdate already confirmed
        -- IsAssistedCombatAction, so unblock the rotation frame's
        -- fast-path early return.
        if C_ActionBar and C_ActionBar.IsAssistedCombatAction
            and C_ActionBar.IsAssistedCombatAction(action) then
            ActionBarsOwned._assistedCombatEverActive = true
        end
        UpdateAssistedCombatRotationFrame(self)

        -- Level link lock
        if self.LevelLinkLockIcon and C_LevelLink and C_LevelLink.IsActionLocked then
            if C_LevelLink.IsActionLocked(action) then
                self.icon:SetDesaturated(true)
                self.LevelLinkLockIcon:SetShown(true)
            else
                self.icon:SetDesaturated(false)
                self.LevelLinkLockIcon:SetShown(false)
            end
        end

        -- Flash animation (auto-attack / auto-repeat)
        local shouldFlash = (IsAttackAction(action) and IsCurrentAction(action))
            or IsAutoRepeatAction(action)
        if shouldFlash then
            if not self.flashing then
                if ActionButton_StartFlash then
                    pcall(ActionButton_StartFlash, self)
                end
            end
        else
            if self.flashing then
                if ActionButton_StopFlash then
                    pcall(ActionButton_StopFlash, self)
                end
            end
        end
    else
        -- Empty slot
        ActionBarsOwned._activeButtons[self] = nil
        self.icon:Hide()
        if self.SlotBackground then self.SlotBackground:Show() end
        self:SetChecked(false)
        self.cooldown:Hide()
        self.Count:SetText("")
        self.Name:SetText("")
        self.Border:Hide()
        UpdateButtonProfessionQuality(self)
        if self.LevelLinkLockIcon then
            self.LevelLinkLockIcon:SetShown(false)
        end
        if self.flashing then
            if ActionButton_StopFlash then
                pcall(ActionButton_StopFlash, self)
            end
        end
        -- Clean up overlays/elements that belong to the departed action
        if self.UpdateFlyout then
            pcall(self.UpdateFlyout, self)
        end
        UpdateAssistedCombatRotationFrame(self)
        ActionBarsOwned.UpdateOverlayGlow(self)
    end
end

local hiddenBarParent = CreateFrame("Frame")
hiddenBarParent:Hide()

local noop = function() end

-- QUI uses ActionButtonTemplate + SecureActionButtonTemplate (not
-- ActionBarButtonTemplate) to avoid auto-registering with the secure
-- ActionBarButtonEventsFrame dispatch.  Adding tainted buttons to that
-- array permanently taints its iteration.

local function SuppressBlizzardButton(btn)
    btn:Hide()
    btn:UnregisterAllEvents()
    btn:SetAttribute("statehidden", true)
    -- Keep the original secure OnEvent handler intact.  The dispatch
    -- calls it, but with events unregistered and the button hidden,
    -- the secure handler runs harmlessly without tainting the context.
end

local LayoutNativeButtons -- forward declaration; defined below

-- Reclaim reparented buttons back to their QUI container and re-layout.
-- Used after Blizzard steals them during vehicle/override transitions.
local function ReclaimBarButtons(barKey)
    local btns = ActionBarsOwned.nativeButtons[barKey]
    local cont = ActionBarsOwned.containers[barKey]
    if not btns or not cont then return end
    for _, btn in ipairs(btns) do
        if btn:GetParent() ~= cont then
            btn:SetParent(cont)
        end
    end
    LayoutNativeButtons(barKey)
end

---------------------------------------------------------------------------
-- SECURE LAYOUT HANDLER
---------------------------------------------------------------------------
-- A single SecureHandlerAttributeTemplate whose restricted snippet executes
-- SetScale/SetPoint/Show/Hide on secure action buttons, bypassing combat
-- lockdown entirely. Normal Lua encodes layout data as attributes; the
-- restricted environment reads them and applies the layout.
---------------------------------------------------------------------------

local layoutHandler = CreateFrame("Frame", "QUI_ActionBarLayoutHandler", UIParent, "SecureHandlerAttributeTemplate")

layoutHandler:SetAttribute("_onattributechanged", [=[
    if name ~= "do-layout" then return end
    local barKey = self:GetAttribute("layout-target")
    if not barKey then return end

    local prefix = "bl-" .. barKey
    local count  = self:GetAttribute(prefix .. "-count") or 0
    local anchor = self:GetAttribute(prefix .. "-anchor") or "TOPLEFT"
    local scale  = tonumber(self:GetAttribute(prefix .. "-scale")) or 1
    local cw     = tonumber(self:GetAttribute(prefix .. "-cw"))
    local ch     = tonumber(self:GetAttribute(prefix .. "-ch"))
    local barRef = self:GetFrameRef("bar-" .. barKey)
    if not barRef then return end

    if cw and ch then
        barRef:SetScale(1)
        barRef:SetWidth(cw)
        barRef:SetHeight(ch)
    end

    for i = 1, count do
        local btnRef = self:GetFrameRef("btn-" .. barKey .. "-" .. i)
        if btnRef then
            local data = self:GetAttribute(prefix .. "-" .. i)
            if data then
                local x, y, show = strsplit("|", data)
                btnRef:SetScale(scale)
                btnRef:ClearAllPoints()
                btnRef:SetPoint(anchor, barRef, anchor, tonumber(x) or 0, tonumber(y) or 0)
                if show == "1" then
                    btnRef:Show()
                else
                    btnRef:Hide()
                end
            end
        end
    end
]=])

-- Encode layout data as attributes and trigger the secure snippet.
local function SecureLayoutBar(barKey, buttons, numVisible, anchor, btnScale, positions, groupWidth, groupHeight)
    local prefix = "bl-" .. barKey
    layoutHandler:SetAttribute(prefix .. "-count", #buttons)
    layoutHandler:SetAttribute(prefix .. "-anchor", anchor)
    layoutHandler:SetAttribute(prefix .. "-scale", btnScale)
    layoutHandler:SetAttribute(prefix .. "-cw", groupWidth)
    layoutHandler:SetAttribute(prefix .. "-ch", groupHeight)

    for i = 1, #buttons do
        if i <= numVisible then
            local pos = positions[i]
            layoutHandler:SetAttribute(prefix .. "-" .. i, pos.x .. "|" .. pos.y .. "|1")
        else
            layoutHandler:SetAttribute(prefix .. "-" .. i, "0|0|0")
        end
    end

    layoutHandler:SetAttribute("layout-target", barKey)
    layoutHandler:SetAttribute("do-layout", GetTime())
end

-- Forward declarations for functions defined later but needed by BuildBar / event handlers
local SkinButton, UpdateButtonText, UpdateEmptySlotVisibility, UpdateKeybindText
local FadeHideTextures, FadeShowTextures
local ApplyAllBarSpacing
local ApplyFlyoutDirection, ApplyAllFlyoutDirections

-- Store QUI state outside secure Blizzard frame tables.
-- Writing custom keys directly on action buttons can taint secret values.
-- UNIFIED: both LibKeyBound patch and keybind registration use this single table.
local frameState, GetFrameState = Helpers.CreateStateTable()

---------------------------------------------------------------------------
-- DB ACCESSORS
---------------------------------------------------------------------------

local GetDB = Helpers.CreateDBGetter("actionBars")

local function GetSafeActionSlot(button)
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

-- Effective settings (global merged with per-bar overrides)
local function GetEffectiveSettings(barKey)
    local global = GetGlobalSettings()
    if not global then return nil end

    local barSettings = GetBarSettings(barKey)
    if not barSettings then
        return global
    end

    local effective = {}
    for key, value in pairs(global) do
        effective[key] = value
    end
    for key, value in pairs(barSettings) do
        effective[key] = value
    end

    return effective
end

---------------------------------------------------------------------------
-- HELPERS
---------------------------------------------------------------------------

-- Safe wrappers for APIs that may return secret values on Midnight.
-- Use only truthiness tests (if X then) — never comparison operators
-- (==, ~=, >) — so secret booleans/numbers pass through without error.
-- No pcall needed since truthiness evaluation never triggers the
-- secret-value error (only comparisons and arithmetic do).
local function SafeHasAction(action)
    if HasAction(action) then return true end
    return false
end

local function SafeIsActionInRange(action)
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

local function SafeIsUsableAction(action)
    local usable, noMana = IsUsableAction(action)
    -- Convert via truthiness (and/or), not comparison
    return (usable and true or false), (noMana and true or false)
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
    if ActionBarsOwned.levelSuppressionActive == suppress then
        return false
    end
    ActionBarsOwned.levelSuppressionActive = suppress
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
local function GetButtonIndex(button)
    local name = button and button:GetName()
    if not name then return nil end
    return tonumber(name:match("%d+$"))
end

local function GetBarFrame(barKey)
    local frameName = BAR_FRAMES[barKey]
    local frame = frameName and _G[frameName]
    if not frame and barKey == "bar1" then
        frame = _G["MainMenuBar"]
    end
    return frame
end

local function GetBarButtons(barKey)
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

-- Register keybind command for LibKeyBound quickbind support.
-- Sets bindingCommand in frameState so the patched Binder can find it.
local function AddKeybindMethods(button, barKey)
    local prefix = BINDING_COMMANDS[barKey]
    if not prefix then return end
    local index = GetButtonIndex(button)
    if not index then return end
    local state = GetFrameState(button)
    state.bindingCommand = prefix .. index
    state.keybindMethods = true
end

-- Check if the cursor is holding a placeable action (for drag preview)
local function CursorHasPlaceableAction()
    local infoType = GetCursorInfo()
    return infoType == "spell" or infoType == "item" or infoType == "macro"
        or infoType == "petaction" or infoType == "mount" or infoType == "flyout"
end

-- Visual refresh after secure drag pickup/place.
-- PickupAction/PlaceAction are handled entirely by the secure
-- WrapScript pre-bodies (see button setup) which return
-- "action", slot to the secure framework.  These Lua hooks only
-- refresh button visuals after the secure handler completes.
local function OwnedButton_PostDrag(self)
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

local function CreateBarContainer(barKey)
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
    -- disabled (bar7/8 off, no-pet pet bar, no-stance stance bar, etc.).
    --
    -- Instead, use a custom state handler that hides on override but
    -- only re-shows when the frame's "qui-user-shown" attribute is true.
    -- Lua code that controls visibility (disable, HasPetUI,
    -- GetNumShapeshiftForms) sets qui-user-shown alongside Show/Hide
    -- calls via SetBarContainerShown() below.
    container:SetAttribute("qui-user-shown", true)
    container:SetAttribute("_onstate-quioverride", [[
        if newstate == "hide" then
            self:Hide()
        elseif self:GetAttribute("qui-user-shown") then
            self:Show()
        end
    ]])
    RegisterStateDriver(container, "quioverride",
        "[overridebar][vehicleui][possessbar][petbattle] hide; show")

    return container
end

-- Central helper for toggling a bar container's intended visibility.
-- Sets the qui-user-shown attribute so the override/vehicle state driver
-- knows whether to re-show the bar on exit, and calls Show/Hide to apply
-- the change immediately (when out of combat).
local function SetBarContainerShown(container, shown)
    if not container then return end
    container:SetAttribute("qui-user-shown", shown and true or false)
    if InCombatLockdown() then return end
    if shown then
        container:Show()
    else
        container:Hide()
    end
end
ActionBarsOwned.SetBarContainerShown = SetBarContainerShown

---------------------------------------------------------------------------
-- LAYOUT ENGINE
---------------------------------------------------------------------------

-- Read layout settings from ownedLayout DB (fully independent of Blizzard Edit Mode)
local function GetOwnedLayout(barKey)
    local barDB = GetBarSettings(barKey)
    local profile = nil
    local core = GetCore()
    if core and core.db then
        profile = core.db.profile
    end

    if type(barDB) == "table"
        and type(profile) == "table"
        and profile._legacyMainlineUsesEditModeActionBars
        and (barKey == "bar1" or barKey == "bar2" or barKey == "bar3" or barKey == "bar4"
            or barKey == "bar5" or barKey == "bar6" or barKey == "bar7" or barKey == "bar8")
    then
        local layout = rawget(barDB, "ownedLayout")
        local expectedColumns = (barKey == "bar4" or barKey == "bar5") and 6 or 12
        local isSyntheticLayout = type(layout) == "table"
            and (layout.orientation or "horizontal") == "horizontal"
            and (layout.columns or 12) == expectedColumns
            and (layout.iconCount or 12) == 12
            and layout.buttonSize == nil
            and layout.buttonSpacing == nil
            and layout.buttonHeight == nil
            and (layout.growUp or false) == false
            and (layout.growLeft or false) == false

        if layout == nil or isSyntheticLayout then
            local barFrame = GetBarFrame(barKey)
            if barFrame and barFrame.GetSettingValue and Enum and Enum.EditModeActionBarSetting then
                local allButtons = GetBarButtons(barKey)
                local buttonCount = #allButtons
                if buttonCount > 0 then
                    local EditModeSettings = Enum.EditModeActionBarSetting
                    local okOrientation, orientation = pcall(barFrame.GetSettingValue, barFrame, EditModeSettings.Orientation)
                    local okRows, numRows = pcall(barFrame.GetSettingValue, barFrame, EditModeSettings.NumRows)
                    local okIcons, numIcons = pcall(barFrame.GetSettingValue, barFrame, EditModeSettings.NumIcons)
                    if not okIcons or type(numIcons) ~= "number" or numIcons <= 0 then
                        numIcons = buttonCount
                    else
                        numIcons = math.min(numIcons, buttonCount)
                    end

                    local isVertical = okOrientation and orientation == 1
                    local columns = 12
                    if okRows and type(numRows) == "number" and numRows > 0 then
                        if isVertical then
                            columns = numRows
                        else
                            columns = math.ceil(numIcons / numRows)
                        end
                    end

                    return isVertical and "vertical" or "horizontal", math.max(1, columns), numIcons, false, false, nil, nil, nil
                end
            end
        end
    end

    local layout = barDB and barDB.ownedLayout
    if not layout then
        return "horizontal", 12, 12, false, false, nil, nil, nil
    end
    return
        layout.orientation or "horizontal",
        layout.columns or 12,
        layout.iconCount or 12,
        layout.growUp or false,
        layout.growLeft or false,
        layout.buttonSize,
        layout.buttonSpacing,
        layout.buttonHeight
end

LayoutNativeButtons = function(barKey)
    local container = ActionBarsOwned.containers[barKey]
    local buttons = ActionBarsOwned.nativeButtons[barKey]
    if not container or not buttons or #buttons == 0 then return end

    local orientation, columns, iconCount, growUp, growLeft, sizeOverride, spacingOverride, heightOverride = GetOwnedLayout(barKey)

    -- Stance bar: clamp iconCount to actual form count so callers that bypass
    -- UpdateStanceBarLayout() (settings refresh, edit mode exit, etc.) never
    -- lay out more buttons than the player's class has stances.
    if barKey == "stance" and GetNumShapeshiftForms then
        local numForms = GetNumShapeshiftForms() or 0
        if numForms > 0 then
            iconCount = math.min(iconCount, numForms)
        end
    end

    local isVertical = (orientation == "vertical")

    local numVisible = math.min(iconCount, #buttons)
    if numVisible == 0 then return end

    -- Desired visual button size from settings
    local desiredSize
    if sizeOverride and sizeOverride > 0 then
        desiredSize = sizeOverride
    else
        local settings = GetGlobalSettings()
        local iconSize = settings and settings.iconSize
        if iconSize and iconSize > 0 then
            desiredSize = iconSize
        else
            desiredSize = 36
        end
    end

    -- Buttons stay at their native frame size (45x45 for action bars, 30x30
    -- for pet/stance). Per-button SetScale handles visual resize so Blizzard
    -- overlays (proc glows, rotation assist) work at their expected dimensions.
    -- Container stays at scale 1.0 so anchoring, positioning, and Layout Mode
    -- all work correctly.
    -- Cache naturalSize outside combat — GetWidth() returns secret values in combat.
    if not ActionBarsOwned.cachedNaturalSize then
        ActionBarsOwned.cachedNaturalSize = {}
    end
    local naturalSize
    if not InCombatLockdown() then
        naturalSize = math.floor((buttons[1]:GetWidth() or 45) + 0.5)
        if naturalSize < 10 then naturalSize = 45 end
        ActionBarsOwned.cachedNaturalSize[barKey] = naturalSize
    else
        naturalSize = ActionBarsOwned.cachedNaturalSize[barKey] or 45
    end

    local spacing
    if spacingOverride then
        spacing = spacingOverride
    else
        local settings = GetGlobalSettings()
        spacing = settings and settings.buttonSpacing or 2
    end

    -- Pixel-snap desiredSize and spacing to the container's physical pixel grid.
    -- Without this, fractional physical-pixel button widths cause WoW's renderer
    -- to round each button's edges independently, producing uneven gaps (e.g., a
    -- visible 1-2px gap between buttons 7 and 8 but not other pairs).
    -- Snapping at the source ensures step, btnScale, and all derived positions
    -- are inherently pixel-aligned — no per-button corrections needed.
    local Core = GetCore()
    local px = Core and Core.GetPixelSize and Core:GetPixelSize(container) or nil
    if px and px > 0 then
        desiredSize = math.floor(desiredSize / px + 0.5) * px
        spacing = math.floor(spacing / px + 0.5) * px
    end

    -- Rectangular button support: when buttonHeight is set (e.g. microbar 32×40),
    -- use separate width/height for container sizing and y-step calculations.
    -- btnScale stays width-based (WoW only supports a single SetScale value).
    local desiredHeight = desiredSize
    if heightOverride and heightOverride > 0 then
        desiredHeight = heightOverride
        if px and px > 0 then
            desiredHeight = math.floor(desiredHeight / px + 0.5) * px
        end
    end

    local btnScale = desiredSize / naturalSize

    local numCols, numRows
    if isVertical then
        local buttonsPerCol = math.max(1, columns)
        numRows = buttonsPerCol
        numCols = math.ceil(numVisible / buttonsPerCol)
    else
        numCols = math.max(1, columns)
        numRows = math.ceil(numVisible / numCols)
    end

    -- Determine the anchor point ONCE for this layout pass
    local anchor
    if growUp then
        anchor = growLeft and "BOTTOMRIGHT" or "BOTTOMLEFT"
    else
        anchor = growLeft and "TOPRIGHT" or "TOPLEFT"
    end

    -- Container size = visual grid size (scale 1.0, matches screen pixels)
    local groupWidth = numCols * desiredSize + math.max(0, numCols - 1) * spacing
    local groupHeight = numRows * desiredHeight + math.max(0, numRows - 1) * spacing

    -- Compute absolute offsets from the container anchor for each button.
    -- WoW multiplies SetPoint offsets by the child's scale, so divide by
    -- btnScale to get correct screen positions.
    local xStep = (desiredSize + spacing) / btnScale
    local yStep = (desiredHeight + spacing) / btnScale
    local xDir = growLeft and -1 or 1
    local yDir = growUp and 1 or -1

    if SKINNABLE_BAR_KEYS[barKey] then
        -- SECURE PATH: Encode positions as attributes, let the restricted
        -- snippet call SetScale/SetPoint/Show/Hide on secure buttons — this
        -- bypasses combat lockdown entirely (no pcall, no ADDON_ACTION_BLOCKED).
        local positions = {}
        for i = 1, numVisible do
            local idx = i - 1
            local col, row
            if isVertical then
                col = math.floor(idx / numRows)
                row = idx % numRows
            else
                col = idx % numCols
                row = math.floor(idx / numCols)
            end
            positions[i] = {
                x = col * xStep * xDir,
                y = row * yStep * yDir,
            }
        end

        SecureLayoutBar(barKey, buttons, numVisible, anchor, btnScale, positions, groupWidth, groupHeight)
    else
        -- NON-SECURE PATH: microbar, bags — direct Lua calls (not protected).
        for i, btn in ipairs(buttons) do
            if i <= numVisible then
                btn:SetScale(btnScale)
                btn:ClearAllPoints()
                local idx = i - 1
                local col, row
                if isVertical then
                    col = math.floor(idx / numRows)
                    row = idx % numRows
                else
                    col = idx % numCols
                    row = math.floor(idx / numCols)
                end
                btn:SetPoint(anchor, container, anchor, col * xStep * xDir, row * yStep * yDir)
                btn:Show()
            else
                btn:Hide()
            end
        end
        container:SetScale(1)
        container:SetSize(groupWidth, groupHeight)
    end

    -- HelpMicroButton / StoreMicroButton slot sharing: overlay Help on Store's
    -- position so they share the same grid slot (only one is visible at a time).
    if barKey == "microbar" then
        local helpBtn = _G.HelpMicroButton
        local storeBtn = _G.StoreMicroButton
        if helpBtn and storeBtn then
            helpBtn:ClearAllPoints()
            helpBtn:SetAllPoints(storeBtn)
            if storeBtn:IsShown() then
                helpBtn:Hide()
            else
                helpBtn:Show()
            end
        end
    end

    -- Suppress Blizzard's dirty flag so its Layout() doesn't override our
    -- positioning on the next frame. SetPoint/SetSize calls above mark the
    -- container dirty; clearing it prevents the built-in OnUpdate from
    -- re-running Blizzard's default layout and stomping our grid.
    if container.MarkClean then
        container:MarkClean()
    end

    ActionBarsOwned.cachedLayouts[barKey] = {
        numCols = numCols,
        numRows = numRows,
        isVertical = isVertical,
        numIcons = numVisible,
        btnWidth = desiredSize,
        btnHeight = desiredHeight,
    }
end

---------------------------------------------------------------------------
-- CONTAINER POSITIONING
---------------------------------------------------------------------------

-- Legacy position helpers removed — frameAnchoring system handles positioning.
-- SaveContainerPosition / RestoreContainerPosition kept as no-ops for any
-- remaining callers; the edit overlay drag and bar init now rely on frameAnchoring.
local function SaveContainerPosition(barKey) end

local function RestoreContainerPosition(barKey)
    local container = ActionBarsOwned.containers[barKey]
    if not container then return false end

    -- Fallback: copy Blizzard frame's position when no frameAnchoring override exists
    -- Map internal bar keys to anchoring system keys where they differ
    local anchorKey = (barKey == "pet" and "petBar")
        or (barKey == "stance" and "stanceBar")
        or (barKey == "microbar" and "microMenu")
        or (barKey == "bags" and "bagBar")
        or barKey
    if _G.QUI_HasFrameAnchor and _G.QUI_HasFrameAnchor(anchorKey) then
        return true
    end

    local barFrame = GetBarFrame(barKey)
    if barFrame then
        local ok, point, relativeTo, relPoint, x, y = pcall(barFrame.GetPoint, barFrame, 1)
        if ok and point then
            container:ClearAllPoints()
            local ox = Helpers.SafeToNumber(x, 0)
            local oy = Helpers.SafeToNumber(y, 0)
            local anchorParent = relativeTo or UIParent
            local anchorRelative = relPoint or point
            local setOk = pcall(container.SetPoint, container, point, anchorParent, anchorRelative, ox, oy)
            if setOk then
                return true
            end

            local rawCx, rawCy = barFrame:GetCenter()
            local rawSx, rawSy = UIParent:GetCenter()
            local cx = Helpers.SafeToNumber(rawCx)
            local cy = Helpers.SafeToNumber(rawCy)
            local sx = Helpers.SafeToNumber(rawSx)
            local sy = Helpers.SafeToNumber(rawSy)
            if cx and cx ~= 0 and cy and cy ~= 0 and sx and sy then
                container:SetPoint("CENTER", UIParent, "CENTER", cx - sx, cy - sy)
                return true
            end
        end
    end

    return false
end

---------------------------------------------------------------------------
-- FADE SYSTEM
---------------------------------------------------------------------------

-- Alias the module-level table so both fade subsystems share one backing store.
local fadeState = ActionBarsOwned.fadeState

local function GetOwnedBarFadeState(barKey)
    if not fadeState[barKey] then
        fadeState[barKey] = {
            isFading = false,
            currentAlpha = 1,
            targetAlpha = 1,
            fadeStart = 0,
            fadeStartAlpha = 1,
            fadeDuration = 0.3,
            isMouseOver = false,
            delayTimer = nil,
            leaveCheckTimer = nil,
        }
    end
    return fadeState[barKey]
end

local IsInEditMode = Helpers.IsEditModeShown

local function SetOwnedBarAlpha(barKey, alpha)
    local container = ActionBarsOwned.containers[barKey]
    if not container then return end

    local buttons = ActionBarsOwned.nativeButtons[barKey]

    container:SetAlpha(alpha)

    if buttons then
        for _, btn in ipairs(buttons) do
            local state = GetFrameState(btn)
            local hidden = alpha <= 0 or state.hiddenEmpty
            if hidden then
                -- Fully invisible: hide all QUI textures + effects so
                -- ADD/MOD blend textures don't bleed through at alpha 0.
                if not state.fadeHidden then
                    FadeHideTextures(state, btn)
                end
            else
                if state.fadeHidden then
                    FadeShowTextures(state, btn)
                    -- Restore button-level alpha that
                    -- UpdateEmptySlotVisibility may have set to 0.
                    btn:SetAlpha(1)
                end
                -- Container alpha handles BLEND textures (icon, backdrop,
                -- border) via normal inheritance.  ADD/MOD textures ignore
                -- parent alpha — hide them while fading, show at full alpha.
                -- MOD blend fades toward white (not transparent), so
                -- SetAlpha looks wrong; clean hide/show is better.
                if alpha < 1 then
                    if state.gloss and state.gloss:IsShown() then
                        state.gloss:Hide(); state._fadeGloss = true
                    end
                    if state.tintOverlay and state.tintOverlay:IsShown() then
                        state.tintOverlay:Hide(); state._fadeTint = true
                    end
                else
                    if state._fadeGloss and state.gloss then
                        state.gloss:Show(); state._fadeGloss = nil
                    end
                    if state._fadeTint and state.tintOverlay then
                        state.tintOverlay:Show(); state._fadeTint = nil
                    end
                end
            end
        end
    end

    GetOwnedBarFadeState(barKey).currentAlpha = alpha
end

-- Expose for HUD visibility system (hud_visibility.lua) so it can fade
-- bars through the proper path that hides MOD-blend textures.
ActionBarsOwned.SetBarAlpha = SetOwnedBarAlpha

local fadeFrame = nil
local fadeFrameUpdate = nil

local function StartOwnedBarFade(barKey, targetAlpha)
    if targetAlpha < 1 and IsInEditMode() then return end
    if targetAlpha < 1 and ShouldForceShowForSpellBook() then return end

    local state = GetOwnedBarFadeState(barKey)
    local fadeSettings = GetFadeSettings()

    local duration = targetAlpha > state.currentAlpha
        and (fadeSettings and fadeSettings.fadeInDuration or 0.2)
        or (fadeSettings and fadeSettings.fadeOutDuration or 0.3)

    if math.abs(state.currentAlpha - targetAlpha) < 0.01 then
        state.isFading = false
        return
    end

    state.isFading = true
    state.targetAlpha = targetAlpha
    state.fadeStart = GetTime()
    state.fadeStartAlpha = state.currentAlpha
    state.fadeDuration = duration

    if not fadeFrame then
        fadeFrame = CreateFrame("Frame")
        fadeFrameUpdate = function(self, elapsed)
            local now = GetTime()
            local anyFading = false

            for bKey, bState in pairs(fadeState) do
                if bState.isFading then
                    anyFading = true
                    local elapsedTime = now - bState.fadeStart
                    local progress = math.min(elapsedTime / bState.fadeDuration, 1)
                    local easedProgress = progress * (2 - progress)
                    local a = bState.fadeStartAlpha + (bState.targetAlpha - bState.fadeStartAlpha) * easedProgress
                    SetOwnedBarAlpha(bKey, a)

                    if progress >= 1 then
                        bState.isFading = false
                        SetOwnedBarAlpha(bKey, bState.targetAlpha)
                    end
                end
            end

            if not anyFading then
                self:SetScript("OnUpdate", nil)
                self:Hide()
            end
        end
    end
    fadeFrame:SetScript("OnUpdate", fadeFrameUpdate)
    fadeFrame:Show()
end

local function CancelOwnedBarFadeTimers(state)
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

local function IsLinkedBar(barKey)
    for _, key in ipairs(STANDARD_BAR_KEYS) do
        if key == barKey then return true end
    end
    return false
end

local function IsMouseOverOwnedBar(barKey)
    local container = ActionBarsOwned.containers[barKey]
    if container and container:IsMouseOver() then return true end

    local buttons = ActionBarsOwned.nativeButtons[barKey]
    if buttons then
        for _, btn in ipairs(buttons) do
            if btn:IsMouseOver() then return true end
        end
    end
    return false
end

local function IsMouseOverAnyLinkedOwnedBar()
    for _, barKey in ipairs(STANDARD_BAR_KEYS) do
        if IsMouseOverOwnedBar(barKey) then return true end
    end
    return false
end

local function HookOwnedFrameForMouseover(frame, barKey)
    if not frame then return end
    local state = GetFrameState(frame)
    if state.ownedMouseoverHooked then return end
    state.ownedMouseoverHooked = true

    frame:HookScript("OnEnter", function()
        ActionBarsOwned:OnBarMouseEnter(barKey)
    end)

    frame:HookScript("OnLeave", function()
        ActionBarsOwned:OnBarMouseLeave(barKey)
    end)
end

function ActionBarsOwned:OnBarMouseEnter(barKey)
    local state = GetOwnedBarFadeState(barKey)
    local fadeSettings = GetFadeSettings()
    local barSettings = GetBarSettings(barKey)

    if ShouldSuppressMouseoverHideForLevel() then
        SetOwnedBarAlpha(barKey, 1)
        return
    end
    if ShouldForceShowForSpellBook() then
        SetOwnedBarAlpha(barKey, 1)
        return
    end

    if barSettings and barSettings.alwaysShow then return end

    local fadeEnabled = barSettings and barSettings.fadeEnabled
    if fadeEnabled == nil then
        fadeEnabled = fadeSettings and fadeSettings.enabled
    end
    if not fadeEnabled then return end

    state.isMouseOver = true

    if fadeSettings and fadeSettings.linkBars1to8 and IsLinkedBar(barKey) then
        for _, linkedKey in ipairs(STANDARD_BAR_KEYS) do
            if linkedKey ~= barKey then
                local linkedState = GetOwnedBarFadeState(linkedKey)
                CancelOwnedBarFadeTimers(linkedState)
                StartOwnedBarFade(linkedKey, 1)
            end
        end
    end

    CancelOwnedBarFadeTimers(state)
    StartOwnedBarFade(barKey, 1)
end

function ActionBarsOwned:OnBarMouseLeave(barKey)
    if IsInEditMode() then return end

    local state = GetOwnedBarFadeState(barKey)
    local fadeSettings = GetFadeSettings()
    local barSettings = GetBarSettings(barKey)

    if ShouldSuppressMouseoverHideForLevel() then
        SetOwnedBarAlpha(barKey, 1)
        return
    end
    if ShouldForceShowForSpellBook() then
        SetOwnedBarAlpha(barKey, 1)
        return
    end

    if barSettings and barSettings.alwaysShow then return end

    local isMainBar = barKey and barKey:match("^bar%d$")
    if isMainBar and InCombatLockdown() and fadeSettings and fadeSettings.alwaysShowInCombat then
        return
    end

    local fadeEnabled = barSettings and barSettings.fadeEnabled
    if fadeEnabled == nil then
        fadeEnabled = fadeSettings and fadeSettings.enabled
    end
    if not fadeEnabled then return end

    if state.leaveCheckTimer then
        state.leaveCheckTimer:Cancel()
    end

    state.leaveCheckTimer = C_Timer.NewTimer(0.066, function()
        state.leaveCheckTimer = nil

        if IsMouseOverOwnedBar(barKey) then return end

        if fadeSettings and fadeSettings.linkBars1to8 and IsLinkedBar(barKey) then
            if IsMouseOverAnyLinkedOwnedBar() then return end
            for _, linkedKey in ipairs(STANDARD_BAR_KEYS) do
                local linkedBarSettings = GetBarSettings(linkedKey)
                if not (linkedBarSettings and linkedBarSettings.alwaysShow) then
                    local linkedState = GetOwnedBarFadeState(linkedKey)
                    linkedState.isMouseOver = false
                    local linkedFadeOutAlpha = linkedBarSettings and linkedBarSettings.fadeOutAlpha
                    if linkedFadeOutAlpha == nil then
                        linkedFadeOutAlpha = fadeSettings and fadeSettings.fadeOutAlpha or 0
                    end
                    local delay = fadeSettings and fadeSettings.fadeOutDelay or 0.5
                    CancelOwnedBarFadeTimers(linkedState)
                    linkedState.delayTimer = C_Timer.NewTimer(delay, function()
                        linkedState.delayTimer = nil
                        if not IsMouseOverAnyLinkedOwnedBar() then
                            StartOwnedBarFade(linkedKey, linkedFadeOutAlpha)
                        end
                    end)
                end
            end
            return
        end

        state.isMouseOver = false

        local fadeOutAlpha = barSettings and barSettings.fadeOutAlpha
        if fadeOutAlpha == nil then
            fadeOutAlpha = fadeSettings and fadeSettings.fadeOutAlpha or 0
        end
        local delay = fadeSettings and fadeSettings.fadeOutDelay or 0.5

        if state.delayTimer then
            state.delayTimer:Cancel()
        end
        state.delayTimer = C_Timer.NewTimer(delay, function()
            if state.isMouseOver then
                state.delayTimer = nil
                return
            end
            if ShouldForceShowForSpellBook() then
                SetOwnedBarAlpha(barKey, 1)
                state.delayTimer = nil
                return
            end
            local freshBarSettings = GetBarSettings(barKey)
            local freshFadeSettings = GetFadeSettings()
            local freshFadeOutAlpha = freshBarSettings and freshBarSettings.fadeOutAlpha
            if freshFadeOutAlpha == nil then
                freshFadeOutAlpha = freshFadeSettings and freshFadeSettings.fadeOutAlpha or 0
            end
            StartOwnedBarFade(barKey, freshFadeOutAlpha)
            state.delayTimer = nil
        end)
    end)
end

local function SetupOwnedBarMouseover(barKey)
    if IsInEditMode() then
        SetOwnedBarAlpha(barKey, 1)
        return
    end

    local barSettings = GetBarSettings(barKey)
    local fadeSettings = GetFadeSettings()

    if ShouldSuppressMouseoverHideForLevel() then
        SetOwnedBarAlpha(barKey, 1)
        return
    end
    if ShouldForceShowForSpellBook() then
        SetOwnedBarAlpha(barKey, 1)
        return
    end

    if barSettings and barSettings.alwaysShow then
        SetOwnedBarAlpha(barKey, 1)
        return
    end

    local fadeEnabled = barSettings and barSettings.fadeEnabled
    if fadeEnabled == nil then
        fadeEnabled = fadeSettings and fadeSettings.enabled
    end
    if not fadeEnabled then
        SetOwnedBarAlpha(barKey, 1)
        return
    end

    -- Combat override: keep bars visible when alwaysShowInCombat is on.
    -- Mirrors the guard in OnBarMouseLeave — without this, HUD visibility
    -- refreshes (QUI_RefreshActionBarFade) reset alpha to fadeOutAlpha
    -- even though the combat-enter handler just showed the bars.
    local isMainBar = barKey and barKey:match("^bar%d$")
    if isMainBar and InCombatLockdown() and fadeSettings and fadeSettings.alwaysShowInCombat then
        SetOwnedBarAlpha(barKey, 1)
        return
    end

    local fadeOutAlpha = barSettings and barSettings.fadeOutAlpha
    if fadeOutAlpha == nil then
        fadeOutAlpha = fadeSettings and fadeSettings.fadeOutAlpha or 0
    end

    -- Hook container and buttons for mouseover detection
    local container = ActionBarsOwned.containers[barKey]
    if container then
        HookOwnedFrameForMouseover(container, barKey)
    end
    local buttons = ActionBarsOwned.nativeButtons[barKey]
    if buttons then
        for _, btn in ipairs(buttons) do
            HookOwnedFrameForMouseover(btn, barKey)
        end
    end

    local state = GetOwnedBarFadeState(barKey)
    state.isFading = false
    CancelOwnedBarFadeTimers(state)

    local isMouseOver = IsMouseOverOwnedBar(barKey)
    if fadeSettings and fadeSettings.linkBars1to8 and IsLinkedBar(barKey) then
        isMouseOver = IsMouseOverAnyLinkedOwnedBar()
    end

    state.isMouseOver = isMouseOver
    SetOwnedBarAlpha(barKey, isMouseOver and 1 or fadeOutAlpha)
end

---------------------------------------------------------------------------
-- USABILITY POLLING
---------------------------------------------------------------------------

-- (Mirror usability polling and keybind methods removed — handled natively)

---------------------------------------------------------------------------
-- EDIT MODE INTEGRATION
---------------------------------------------------------------------------

local function CreateEditOverlay(container, barKey)
    local overlay = CreateFrame("Frame", nil, container, "BackdropTemplate")
    overlay:SetAllPoints(container)
    local core = GetCore()
    local px = (core and core.GetPixelSize and core:GetPixelSize(overlay)) or 1
    local edge2 = 2 * px
    overlay:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = edge2,
    })
    overlay:SetBackdropColor(0.2, 0.8, 0.6, 0.3)
    overlay:SetBackdropBorderColor(0.376, 0.647, 0.980, 1)
    overlay:EnableMouse(true)
    overlay:SetMovable(true)
    overlay:RegisterForDrag("LeftButton")
    overlay:SetFrameStrata("HIGH")
    overlay:Hide()

    local text = overlay:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    text:SetPoint("CENTER")
    local displayName = barKey:gsub("bar", "Bar ")
    text:SetText(displayName)
    overlay.label = text

    overlay:SetScript("OnDragStart", function()
        container:StartMoving()
    end)

    overlay:SetScript("OnDragStop", function()
        container:StopMovingOrSizing()
        SaveContainerPosition(barKey)
    end)

    return overlay
end

local function EnsureEditOverlay(barKey)
    local container = ActionBarsOwned.containers[barKey]
    if not container then return nil end

    local overlay = ActionBarsOwned.editOverlays[barKey]
    if not overlay then
        overlay = CreateEditOverlay(container, barKey)
        ActionBarsOwned.editOverlays[barKey] = overlay
    end

    return overlay
end

local function SetEditOverlayVisible(barKey, visible)
    local overlay = EnsureEditOverlay(barKey)
    if not overlay then return end

    if visible then
        overlay:Show()
    else
        overlay:Hide()
    end
end

local function OnEditModeEnter()
    ActionBarsOwned.editModeActive = true

    for _, barKey in ipairs(ALL_MANAGED_BAR_KEYS) do
        local container = ActionBarsOwned.containers[barKey]
        if container then
            container:SetMovable(true)

            local state = GetOwnedBarFadeState(barKey)
            state.isFading = false
            CancelOwnedBarFadeTimers(state)
            SetOwnedBarAlpha(barKey, 1)

            SetEditOverlayVisible(barKey, true)
        end
    end
end

local function OnEditModeExit()
    ActionBarsOwned.editModeActive = false

    for _, barKey in ipairs(ALL_MANAGED_BAR_KEYS) do
        if ActionBarsOwned.editOverlays[barKey] then
            ActionBarsOwned.editOverlays[barKey]:Hide()
        end

        SaveContainerPosition(barKey)
        LayoutNativeButtons(barKey)
        SetupOwnedBarMouseover(barKey)
    end
end

---------------------------------------------------------------------------
-- OVERRIDE BINDING APPLICATION
---------------------------------------------------------------------------

local function IsVehicleBarActive()
    return (HasVehicleActionBar and HasVehicleActionBar())
        or (HasOverrideActionBar and HasOverrideActionBar())
        or (UnitInVehicle and UnitInVehicle("player"))
end

local function IsPetBattleActive()
    return C_PetBattles and C_PetBattles.IsInBattle and C_PetBattles.IsInBattle()
end

-- Apply override bindings for a bar. All bars need this because reparenting
-- + SetID(0) disconnects buttons from Blizzard's native binding lookup.
local function ApplyBarOverrideBindings(barKey)
    if InCombatLockdown() and not inInitSafeWindow then
        ActionBarsOwned.pendingBindings = true
        return
    end

    local container = ActionBarsOwned.containers[barKey]
    if not container then return end

    -- Clear existing override bindings on this bar's container
    ClearOverrideBindings(container)

    -- Vehicle guard: bar1 keybinds should pass through to Blizzard's
    -- vehicle/override bar natively when one is active.
    if barKey == "bar1" and IsVehicleBarActive() then
        return
    end

    -- Pet battle guard: all bindings should pass through to the pet
    -- battle UI natively.  Clear and return for every bar.
    if IsPetBattleActive() then
        return
    end

    -- Housing guard: housing has its own keybinds.
    if ActionBarsOwned._inHousing then
        return
    end

    local buttons = ActionBarsOwned.nativeButtons[barKey]
    local prefix = BINDING_COMMANDS[barKey]
    if not buttons or not prefix then return end

    for i, btn in ipairs(buttons) do
        local command = prefix .. i
        for ki = 1, select("#", GetBindingKey(command)) do
            local key = select(ki, GetBindingKey(command))
            if key then
                local existing = GetBindingAction(key, true)
                if not existing or existing == "" or existing == command then
                    -- Pet/stance buttons use PetActionButtonTemplate / StanceButtonTemplate
                    -- whose OnClick handlers check for "LeftButton" specifically.  Standard
                    -- action bars (SecureActionButtonTemplate) fire via secure attributes
                    -- regardless of button string, so "Keybind" works for them.
                    local vBtn = (barKey == "pet" or barKey == "stance") and "LeftButton" or "Keybind"
                    SetOverrideBindingClick(container, false, key, btn:GetName(), vBtn)
                end
            end
        end
    end
end

-- Apply override bindings for all managed bars (including pet/stance)
local function ApplyAllOverrideBindings()
    for _, barKey in ipairs(ALL_MANAGED_BAR_KEYS) do
        ApplyBarOverrideBindings(barKey)
    end
end

-- Compat aliases
local ApplyBar1OverrideBindings = function() ApplyBarOverrideBindings("bar1") end

---------------------------------------------------------------------------
-- BAR 1 PAGING STATE DRIVER
---------------------------------------------------------------------------

local function BuildPagingCondition()
    local parts = {}
    -- Override/vehicle/possess/shapeshift: use string tokens resolved
    -- dynamically in the _onstate-page restricted snippet (bar indices
    -- can change mid-session so must not be baked at build time).
    table.insert(parts, "[overridebar] override")
    table.insert(parts, "[vehicleui][possessbar][shapeshift] possess")
    -- Dragonriding (bonusbar:5)
    table.insert(parts, "[bonusbar:5] 11")
    -- Class-specific bonus bars (Druid forms, Rogue stealth, etc.)
    for i = 4, 1, -1 do
        table.insert(parts, "[bonusbar:" .. i .. "] " .. (6 + i))
    end
    -- Manual page switching
    for i = 6, 2, -1 do
        table.insert(parts, "[bar:" .. i .. "] " .. i)
    end
    -- Default page
    table.insert(parts, "1")
    return table.concat(parts, "; ")
end

local bar1PagingInitialized = false

local function SetupBar1Paging(container)
    if bar1PagingInitialized then return end
    bar1PagingInitialized = true

    -- Resolve override/possess/shapeshift bar indices dynamically in
    -- restricted code (they can change mid-session).  String tokens from
    -- BuildPagingCondition are converted to real page numbers here.
    container:SetAttribute("_onstate-page", [[
        local page = newstate
        if page == "override" then
            if HasVehicleActionBar and HasVehicleActionBar() then
                page = GetVehicleBarIndex()
            elseif HasOverrideActionBar and HasOverrideActionBar() then
                page = GetOverrideBarIndex()
            elseif HasTempShapeshiftActionBar and HasTempShapeshiftActionBar() then
                page = GetTempShapeshiftBarIndex()
            else
                page = 1
            end
        elseif page == "possess" then
            if HasVehicleActionBar and HasVehicleActionBar() then
                page = GetVehicleBarIndex()
            elseif HasOverrideActionBar and HasOverrideActionBar() then
                page = GetOverrideBarIndex()
            elseif HasTempShapeshiftActionBar and HasTempShapeshiftActionBar() then
                page = GetTempShapeshiftBarIndex()
            elseif HasBonusActionBar and HasBonusActionBar() then
                page = GetBonusBarIndex()
            else
                page = 1
            end
        end
        page = tonumber(page) or 1
        local offset = (page - 1) * 12
        control:ChildUpdate("offset", offset)
    ]])
    RegisterStateDriver(container, "page", BuildPagingCondition())
end

---------------------------------------------------------------------------
-- BAR BUILD (native engine)
---------------------------------------------------------------------------

-- Get the ORIGINAL Blizzard buttons by name (bypassing nativeButtons cache).
-- Used during BuildBar to find buttons that need hiding.
local function GetOriginalBlizzButtons(barKey)
    local buttons = {}
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

local function BuildBar(barKey)
    local barFrame = GetBarFrame(barKey)

    if not ActionBarsOwned.containers[barKey] then
        ActionBarsOwned.containers[barKey] = CreateBarContainer(barKey)
    end
    local container = ActionBarsOwned.containers[barKey]

    local settings = GetEffectiveSettings(barKey)
    local buttons = {}

    if barKey == "bar1" then
        -- BAR 1: Create new ActionButtonTemplate buttons with paging
        -- Hide Blizzard's bar frame and original buttons
        if barFrame then
            barFrame:UnregisterAllEvents()
            barFrame:SetParent(hiddenBarParent)
            barFrame:Hide()
        end
        local origButtons = GetOriginalBlizzButtons(barKey)
        for _, blizzBtn in ipairs(origButtons) do
            blizzBtn:SetParent(hiddenBarParent)
            SuppressBlizzardButton(blizzBtn)
        end

        -- Rescue the leave-vehicle button from the hidden Blizzard bar hierarchy.
        -- MainMenuBarVehicleLeaveButton is a child of MainActionBar; reparenting
        -- the bar to hiddenBarParent makes it invisible. Reparent to UIParent so
        -- Blizzard's visibility driver can still show/hide it normally.
        local leaveBtn = _G.MainMenuBarVehicleLeaveButton
        if leaveBtn then
            leaveBtn:SetParent(UIParent)
        end

        -- Create or reuse QUI bar1 buttons
        for i = 1, 12 do
            local btnName = "QUI_Bar1Button" .. i
            local btn = _G[btnName]
            if not btn then
                local ok
                ok, btn = pcall(CreateFrame, "CheckButton", btnName, container, "ActionButtonTemplate, SecureActionButtonTemplate")
                if not ok then btn = _G[btnName] end
                -- Secure action attributes (normally set by ActionBarActionButtonMixin:OnLoad)
                btn:SetAttribute("type", "action")
                btn:SetAttribute("checkselfcast", true)
                btn:SetAttribute("checkfocuscast", true)
                btn:SetAttribute("checkmouseovercast", true)
                btn:SetAttribute("useparent-unit", true)
                btn:SetAttribute("useparent-actionpage", true)
                btn:RegisterForDrag("LeftButton", "RightButton")
                -- Register for both down and up clicks — empowered
                -- spells (Evoker Fire Breath etc.) need mouse-down to
                -- start the empower and mouse-up to release.
                btn:RegisterForClicks("AnyDown", "AnyUp")
                -- Click timing is user-configurable:
                --   • false (default) — cast on mouse-up. Drag motions
                --     naturally pre-empt the cast.
                --   • true — cast on mouse-down for snappier response.
                -- Empowered spells still work in both modes because
                -- pressAndHoldAction + typerelease="actionrelease"
                -- override the timing for press/release flow.
                do
                    local _db = GetDB()
                    local _g = _db and _db.global
                    btn:SetAttribute("useOnKeyDown", _g and _g.useOnKeyDown == true)
                end
                -- Popup direction support for spell flyouts.
                -- BaseActionButtonMixin:UpdateFlyout bails at
                -- "if not self.HasPopup" without these methods,
                -- so the flyoutDirection attribute is never read.
                if not btn.HasPopup then
                    local popupDir
                    btn.HasPopup = true
                    btn.SetPopupDirection = function(_, dir) popupDir = dir end
                    btn.GetPopupDirection = function() return popupDir end
                    btn.SetPopup = function(self2, popup)
                        if popup then
                            rawset(self2, "_quiPopup", popup)
                        end
                    end
                    btn.ClearPopup = function(self2)
                        rawset(self2, "_quiPopup", nil)
                    end
                end
                btn.flashing = 0
                btn.flashtime = 0
                btn:SetAttribute("index", i)
                btn:SetAttribute("action", i)
                btn:SetAttribute("_childupdate-offset", [[
                    local index = self:GetAttribute("index")
                    local newAction = index + (message or 0)
                    -- Always set action from restricted code so the attribute
                    -- is untainted.  An addon-side SetAttribute taints the
                    -- value; Blizzard's Update then propagates that taint
                    -- through GetActionInfo → IsPressHoldReleaseSpell, causing
                    -- "attempt to compare a secret number value" in combat.
                    self:SetAttribute("action", newAction)
                    -- Pre-set pressAndHoldAction from restricted code so the
                    -- comparison in Blizzard's ActionButton:Update does not hit
                    -- the taint barrier when IsPressHoldReleaseSpell returns a
                    -- secret value during combat.
                    if IsPressHoldReleaseSpell then
                        local pressAndHold = false
                        self:SetAttribute("typerelease", "actionrelease")
                        local actionType, id, subType = GetActionInfo(newAction)
                        if actionType == "spell" then
                            pressAndHold = IsPressHoldReleaseSpell(id)
                        elseif actionType == "macro" and subType == "spell" then
                            pressAndHold = IsPressHoldReleaseSpell(id)
                        end
                        self:SetAttribute("pressAndHoldAction", pressAndHold)
                    end
                    -- Sync button.action on the Lua side so SafeUpdate reads
                    -- the correct slot.  Without this, the mixin's
                    -- OnAttributeChanged is the only sync path — fragile
                    -- because that handler runs in tainted context.
                    self:CallMethod("SafeSyncAction")
                ]])
                -- Methods called during the state driver's immediate fire:
                -- RegisterStateDriver → _childupdate-offset →
                -- CallMethod("SafeSyncAction") → SafeUpdate →
                -- self:UpdateCooldown() / self:UpdateCount().
                -- Must exist BEFORE SetupBar1Paging.
                btn.SafeSyncAction = ActionBarsOwned.SafeSyncAction
                btn.UpdateCooldown = function(self)
                    ActionBarsOwned.UpdateCooldown(self)
                end
                btn.UpdateCount = function(self)
                    local action = self.action
                    if not action or not HasAction(action) then
                        if self.Count then self.Count:SetText("") end
                        return
                    end
                    if C_ActionBar and C_ActionBar.GetActionDisplayCount then
                        if self.Count then self.Count:SetText(C_ActionBar.GetActionDisplayCount(action) or "") end
                    elseif self.Count then
                        self.Count:SetText("")
                    end
                end
                -- Sync btn.action (ActionButtonTemplate has no
                -- OnAttributeChanged to do this automatically).
                btn.action = i
            else
                btn:SetParent(container)
                btn.action = btn:GetAttribute("action") or i
            end
            btn:Show()
            buttons[i] = btn
        end

        -- Register paging state driver
        SetupBar1Paging(container)
    elseif barKey == "pet" or barKey == "stance" then
        -- PET/STANCE: Create fresh buttons from Blizzard templates, then
        -- fully suppress the originals (same pattern as bars 1-8 and
        -- action button addons).  Pet/stance buttons use GetID() for
        -- slot lookup — SetID is the only required setup.
        if barFrame then
            -- Purge Edit Mode's isShownExternal before reparenting to avoid
            -- tainting the Edit Mode system.  Writing enough nil keys pushes
            -- the tainted entry off the secure-variable tracking list.
            if barFrame.system then
                barFrame.isShownExternal = nil
                local c = 42
                repeat
                    if barFrame[c] == nil then
                        barFrame[c] = nil
                    end
                    c = c + 1
                until issecurevariable(barFrame, "isShownExternal")
            end
            barFrame:UnregisterAllEvents()
            barFrame:SetParent(hiddenBarParent)
            if barFrame.HideBase then
                barFrame:HideBase()
            else
                barFrame:Hide()
            end
            -- Do NOT write to the bar frame (numForms, Update, etc.) — any
            -- tainted write is read by ActionBarController, tainting its
            -- context and leaking into the ActionBarButtonEventsFrame dispatch.
            -- The bar is hidden + reparented + events unregistered; the
            -- controller's calls to Update/ShouldShow are harmless.
        end

        -- Suppress original Blizzard buttons — but for the pet bar we
        -- must leave the originals ALIVE (not UnregisterAllEvents, not
        -- statehidden).  Blizzard's native pet action bar keeps the
        -- server<->client state in sync via PetActionButton_OnEvent on
        -- the individual buttons — if we unregister their events, pet
        -- bar drag state fails to persist across /reload because the
        -- native sync path never runs.  The container is already
        -- hidden + reparented above, which is enough to make them
        -- invisible.  Bartender4 uses the same approach (see
        -- HideBlizzard.lua:78 — `hideActionBarFrame(PetActionBar, true)`
        -- only touches the container, never the child buttons).
        if barKey ~= "pet" then
            local origButtons = GetOriginalBlizzButtons(barKey)
            for _, blizzBtn in ipairs(origButtons) do
                SuppressBlizzardButton(blizzBtn)
            end
        end

        -- Create fresh buttons from the native template
        local template = barKey == "pet" and "PetActionButtonTemplate" or "StanceButtonTemplate"
        local prefix = barKey == "pet" and "QUI_PetButton" or "QUI_StanceButton"
        local count = BUTTON_COUNTS[barKey] or 10

        for i = 1, count do
            local btnName = prefix .. i
            local btn = _G[btnName]
            if not btn then
                local ok
                ok, btn = pcall(CreateFrame, "CheckButton", btnName, container, template)
                if not ok then btn = _G[btnName] end
                btn:SetID(i)
            else
                btn:SetParent(container)
            end
            -- Pet buttons inherit ActionButton OnEvent from the template, which
            -- runs BaseActionButtonMixin:Update (wrong for pet actions) and can
            -- taint the execution context.  Silence events — QUI drives pet
            -- button visuals via UpdatePetButton / UpdateAllPetButtons.
            if barKey == "pet" then
                btn:UnregisterAllEvents()
                btn:SetScript("OnEvent", nil)
                -- Pin the pet slot on the button itself so our drag
                -- overrides below don't depend on GetID() or on
                -- whatever the template's OnLoad populated.
                btn.id = i
                -- The inherited OnEnter is BaseActionButtonMixin:OnEnter →
                -- GameTooltip:SetAction(self.action), which is wrong for pet
                -- buttons (they have no .action).  Replace with SetPetAction.
                btn:SetScript("OnEnter", function(self)
                    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                    GameTooltip:SetPetAction(self:GetID())
                    GameTooltip:Show()
                end)
                btn:SetScript("OnLeave", GameTooltip_Hide)
                -- Explicit insecure drag handlers.  Pet action pickup /
                -- placement is not combat-protected, so plain Lua calls
                -- are fine here.  Overriding means we don't rely on the
                -- template's native OnDragStart / OnReceiveDrag, which
                -- may misbehave when the button is reparented outside
                -- the original PetActionBar frame or when the template
                -- internals read stale cached fields.
                btn:SetScript("OnDragStart", function(self)
                    if InCombatLockdown() then return end
                    local slot = self.id or self:GetID()
                    if not slot or slot < 1 then return end
                    self:SetChecked(false)
                    PickupPetAction(slot)
                    ActionBarsOwned.UpdatePetButton(self)
                end)
                btn:SetScript("OnReceiveDrag", function(self)
                    if InCombatLockdown() then return end
                    local slot = self.id or self:GetID()
                    if not slot or slot < 1 then return end
                    local cursorType = GetCursorInfo()
                    if cursorType == "petaction" then
                        self:SetChecked(false)
                        PickupPetAction(slot)
                        ActionBarsOwned.UpdatePetButton(self)
                    end
                end)
            end
            btn:Show()
            -- Both pet and stance bar-level Updates are suppressed — QUI
            -- drives button visuals directly via the Blizzard APIs.
            if barKey == "pet" then
                ActionBarsOwned.UpdatePetButton(btn)
            elseif barKey == "stance" then
                ActionBarsOwned.UpdateStanceButton(btn)
            end
            buttons[i] = btn
        end
    elseif barKey == "microbar" then
        -- MICRO MENU: Reparent individual micro buttons into QUI container.
        -- Fully silence the Blizzard container so its Layout() never fires
        -- during combat (which would propagate taint through our hooks).
        if barFrame then
            -- Purge Edit Mode's isShownExternal before reparenting to avoid
            -- tainting the Edit Mode system. Writing enough nil keys pushes
            -- the tainted entry off the secure-variable tracking list.
            if barFrame.system then
                barFrame.isShownExternal = nil
                local c = 42
                repeat
                    if barFrame[c] == nil then
                        barFrame[c] = nil
                    end
                    c = c + 1
                until issecurevariable(barFrame, "isShownExternal")
            end
            barFrame:UnregisterAllEvents()
            barFrame:SetParent(hiddenBarParent)
            -- Use the original C-side Hide to avoid Edit Mode's Lua override
            -- which can propagate taint on managed frames.
            if barFrame.HideBase then
                barFrame:HideBase()
            else
                barFrame:Hide()
            end
        end

        -- Suppress Blizzard's MicroMenu.Layout during reparenting — partially
        -- reparented children have nil positions, which crashes GetEdgeButton.
        local origLayout = MicroMenu and MicroMenu.Layout
        if MicroMenu then MicroMenu.Layout = function() end end

        -- Use explicit button list instead of fragile GetChildren enumeration
        ActionBarsOwned._microAnchors = {}
        for i, name in ipairs(MICRO_BUTTON_NAMES) do
            local btn = _G[name]
            if btn then
                -- Save original anchor for clean restoration during yield
                ActionBarsOwned._microAnchors[i] = { btn:GetPoint() }
                btn:SetParent(container)
                btn:Show()
                buttons[#buttons + 1] = btn
            end
        end

        -- HelpMicroButton shares StoreMicroButton's slot — reparent it into
        -- our container so Blizzard's Layout doesn't crash on orphaned children,
        -- but don't add it to the buttons array (LayoutNativeButtons handles it).
        local helpBtn = _G.HelpMicroButton
        if helpBtn then
            helpBtn:SetParent(container)
        end

        -- Restore MicroMenu.Layout now that all children are reparented
        if MicroMenu and origLayout then MicroMenu.Layout = origLayout end

        -- Apply clickthrough setting
        local barDB = GetBarSettings("microbar")
        if barDB and barDB.clickthrough then
            for _, btn in ipairs(buttons) do
                btn:EnableMouse(false)
            end
        end

        -- Hook Blizzard's layout to reclaim buttons if it tries to reparent them
        if not ActionBarsOwned._microLayoutHooked then
            ActionBarsOwned._microLayoutHooked = true

            -- Shared reclaim function: reparent stray buttons and reapply layout.
            -- During combat, defers via C_Timer.After(0) to break the taint
            -- chain from hooked Blizzard execution paths, then coalesces
            -- multiple hook fires into a single layout per frame.
            -- Reparenting (SetParent) is protected during combat,
            -- so that is deferred to PLAYER_REGEN_ENABLED, but SetPoint/SetScale
            -- on micro buttons works fine from untainted addon code.
            local microCombatLayoutPending = false
            local function ReclaimMicroButtons()
                if not ActionBarsOwned.initialized then return end
                -- Skip reclaim when Blizzard legitimately owns the buttons
                -- (vehicle, override bar, pet battle). The _microOwnedByUI
                -- flag is set by the MicroMenu:SetParent hook.
                if ActionBarsOwned._microOwnedByUI then return end

                -- Clear Blizzard's cached grid settings so its next Layout()
                -- doesn't reuse stale button positions from before QUI reclaimed.
                if MicroMenu then
                    MicroMenu.oldGridSettings = nil
                end

                local btns = ActionBarsOwned.nativeButtons["microbar"]
                local cont = ActionBarsOwned.containers["microbar"]
                if not btns or not cont then return end

                -- Check if any buttons need reparenting (protected during combat)
                local needsReparent = false
                for _, btn in ipairs(btns) do
                    if btn:GetParent() ~= cont then
                        needsReparent = true
                        break
                    end
                end

                if needsReparent and InCombatLockdown() then
                    -- SetParent is protected — defer reparenting to combat end
                    if not ActionBarsOwned._microDeferPending then
                        ActionBarsOwned._microDeferPending = true
                        ns.Addon:RegisterEvent("PLAYER_REGEN_ENABLED", function()
                            ns.Addon:UnregisterEvent("PLAYER_REGEN_ENABLED")
                            ActionBarsOwned._microDeferPending = false
                            ReclaimMicroButtons()
                        end)
                    end
                    return
                end

                if needsReparent then
                    for _, btn in ipairs(btns) do
                        if btn:GetParent() ~= cont then
                            btn:SetParent(cont)
                        end
                    end
                    -- Reclaim HelpMicroButton as well (shares Store's slot)
                    local helpBtn = _G.HelpMicroButton
                    if helpBtn and helpBtn:GetParent() ~= cont then
                        helpBtn:SetParent(cont)
                    end
                    -- Re-apply clickthrough after reparenting
                    local microDB = GetBarSettings("microbar")
                    local ct = microDB and microDB.clickthrough
                    for _, btn in ipairs(btns) do
                        btn:EnableMouse(not ct)
                    end
                end

                -- SetScale on the microbar container is protected during combat.
                -- Defer layout to combat end via a dedicated frame event handler
                -- (not ns.Addon:RegisterEvent, which would conflict with the
                -- reparent defer above).
                if InCombatLockdown() then
                    if not microCombatLayoutPending then
                        microCombatLayoutPending = true
                        local f = ActionBarsOwned._microLayoutFrame
                        if not f then
                            f = CreateFrame("Frame")
                            ActionBarsOwned._microLayoutFrame = f
                        end
                        f:RegisterEvent("PLAYER_REGEN_ENABLED")
                        f:SetScript("OnEvent", function(self)
                            self:UnregisterEvent("PLAYER_REGEN_ENABLED")
                            microCombatLayoutPending = false
                            if not ActionBarsOwned._microOwnedByUI then
                                LayoutNativeButtons("microbar")
                            end
                        end)
                    end
                else
                    LayoutNativeButtons("microbar")
                end
            end

            -- Yield micro buttons back to Blizzard when MicroMenu is
            -- reparented away from UIParent (vehicle, override, pet battle).
            -- Reclaim when it returns to UIParent.
            local function YieldMicroButtons()
                ActionBarsOwned._microOwnedByUI = true
                local btns = ActionBarsOwned.nativeButtons["microbar"]
                if btns and MicroMenu then
                    local savedAnchors = ActionBarsOwned._microAnchors
                    for i, btn in ipairs(btns) do
                        btn:SetParent(MicroMenu)
                        btn:EnableMouse(true)
                        -- Restore original anchor if saved
                        if savedAnchors and savedAnchors[i] then
                            btn:ClearAllPoints()
                            btn:SetPoint(unpack(savedAnchors[i]))
                        end
                    end
                    -- Return HelpMicroButton to MicroMenu as well
                    local helpBtn = _G.HelpMicroButton
                    if helpBtn then
                        helpBtn:SetParent(MicroMenu)
                    end
                end
            end

            local function ReclaimOrYield()
                if MicroMenu and MicroMenu:GetParent() ~= UIParent then
                    YieldMicroButtons()
                else
                    ActionBarsOwned._microOwnedByUI = false
                    ReclaimMicroButtons()
                end
            end

            -- Hook MicroMenu:SetParent — primary ownership detection.
            -- Fires when Blizzard reparents the frame for vehicle/override/
            -- pet battle transitions.
            if MicroMenu then
                hooksecurefunc(MicroMenu, "SetParent", function(_, parent)
                    if not ActionBarsOwned.initialized then return end
                    if parent == UIParent then
                        ActionBarsOwned._microOwnedByUI = false
                        ReclaimMicroButtons()
                    else
                        YieldMicroButtons()
                    end
                end)
            end

            -- Hook MicroMenuContainer AND MicroMenu Layout — both can fire
            -- when Blizzard re-layouts buttons (Edit Mode changes, grid
            -- recalculation, etc.). MicroMenu.Layout repositions individual
            -- buttons; MicroMenuContainer.Layout repositions the container.
            if MicroMenuContainer and MicroMenuContainer.Layout then
                hooksecurefunc(MicroMenuContainer, "Layout", ReclaimMicroButtons)
            end
            if MicroMenu and MicroMenu.Layout and MicroMenu ~= MicroMenuContainer then
                hooksecurefunc(MicroMenu, "Layout", ReclaimMicroButtons)
            end

            -- Hook UpdateMicroButtons — fires on many events (talent changes,
            -- guild updates, store state, etc.) and repositions buttons
            if UpdateMicroButtons then
                hooksecurefunc("UpdateMicroButtons", ReclaimMicroButtons)
            end

            -- Hook UpdateMicroButtonsParent — fires when Blizzard explicitly
            -- reparents micro buttons (vehicle, override bar, pet battle)
            if UpdateMicroButtonsParent then
                hooksecurefunc("UpdateMicroButtonsParent", ReclaimOrYield)
            end

            -- Hook ActionBarController_UpdateAll — fires on bar state changes
            -- (vehicle exit, stance changes) that can trigger button reparenting
            if ActionBarController_UpdateAll then
                hooksecurefunc("ActionBarController_UpdateAll", ReclaimMicroButtons)
            end

            -- Reclaim micro buttons when pet battle ends — no other hook
            -- reliably fires for this transition.
            if C_PetBattles then
                local petBattleFrame = CreateFrame("Frame")
                petBattleFrame:RegisterEvent("PET_BATTLE_CLOSE")
                petBattleFrame:SetScript("OnEvent", function()
                    if not ActionBarsOwned.initialized then return end
                    ActionBarsOwned._microOwnedByUI = false
                    -- Restore MicroMenu parent so the SetParent hook also fires
                    if MicroMenu and MicroMenu:GetParent() ~= UIParent then
                        MicroMenu:SetParent(UIParent)
                    else
                        ReclaimMicroButtons()
                    end
                end)
            end

            -- Reanchor MicroButtonAlert callouts when the microbar is near
            -- a screen edge so the alert bubble doesn't render off-screen.
            -- Blizzard's default is BOTTOM-of-alert to TOP-of-button (alert
            -- above button).  We flip to TOP-of-alert to BOTTOM-of-button
            -- when the button is in the upper portion of the screen, and
            -- nudge horizontally when near a side edge.
            if not ActionBarsOwned._microAlertAnchorHooked then
                ActionBarsOwned._microAlertAnchorHooked = true

                local EDGE_THRESHOLD_Y = 200  -- px from top before flipping
                local EDGE_THRESHOLD_X = 60   -- px from side before nudging

                local function ReanchorMicroAlert(button)
                    if not button then return end
                    local alert = button.FlashBorder or button.alert
                    if not alert and button.GetName then
                        alert = _G[button:GetName() .. "Alert"]
                    end
                    if not alert or not alert:IsShown() then return end

                    local screenH = GetScreenHeight()
                    local screenW = GetScreenWidth()
                    if not screenH or screenH == 0 then return end

                    local _, btnTop = button:GetCenter()
                    local btnLeft = button:GetLeft()
                    local btnRight = button:GetRight()
                    if not btnTop or not btnLeft then return end

                    -- Determine vertical anchor: flip below if near top
                    local nearTop = (screenH - btnTop) < EDGE_THRESHOLD_Y
                    -- Determine horizontal nudge
                    local xOff = 0
                    if btnLeft < EDGE_THRESHOLD_X then
                        xOff = EDGE_THRESHOLD_X - btnLeft
                    elseif btnRight and (screenW - btnRight) < EDGE_THRESHOLD_X then
                        xOff = -( EDGE_THRESHOLD_X - (screenW - btnRight) )
                    end

                    alert:ClearAllPoints()
                    if nearTop then
                        -- Alert below button
                        alert:SetPoint("TOP", button, "BOTTOM", xOff, -4)
                        -- Flip the arrow to point upward
                        if alert.Arrow then
                            alert.Arrow:ClearAllPoints()
                            alert.Arrow:SetPoint("BOTTOM", alert, "TOP", 0, -2)
                            alert.Arrow:SetTexCoord(0, 1, 1, 0) -- flip vertically
                        end
                    else
                        -- Alert above button (Blizzard default direction)
                        alert:SetPoint("BOTTOM", button, "TOP", xOff, 4)
                        if alert.Arrow then
                            alert.Arrow:ClearAllPoints()
                            alert.Arrow:SetPoint("TOP", alert, "BOTTOM", 0, 2)
                            alert.Arrow:SetTexCoord(0, 1, 0, 1) -- normal
                        end
                    end
                end

                -- Hook the global alert function to reposition after it sets up
                if type(MainMenuMicroButton_ShowAlert) == "function" then
                    hooksecurefunc("MainMenuMicroButton_ShowAlert", function(button)
                        C_Timer.After(0, function()
                            ReanchorMicroAlert(button)
                        end)
                    end)
                end
            end
        end
    elseif barKey == "bags" then
        -- BAG BAR: Reparent bag slot buttons into QUI container.
        -- Fully silence the Blizzard container so its Layout() never fires
        -- during combat (which would propagate taint through our hooks).
        if barFrame then
            if barFrame.system then
                barFrame.isShownExternal = nil
                local c = 42
                repeat
                    if barFrame[c] == nil then
                        barFrame[c] = nil
                    end
                    c = c + 1
                until issecurevariable(barFrame, "isShownExternal")
            end
            barFrame:UnregisterAllEvents()
            barFrame:SetParent(hiddenBarParent)
            if barFrame.HideBase then
                barFrame:HideBase()
            else
                barFrame:Hide()
            end
        end

        local bagButtons = GetBarButtons("bags")
        local noopFunc = function() end
        for i, btn in ipairs(bagButtons) do
            btn:SetParent(container)
            btn:Show()
            -- Prevent Blizzard's expand/collapse animation from firing on
            -- reparented bag buttons.
            if btn.SetBarExpanded then
                btn.SetBarExpanded = noopFunc
            end
            buttons[i] = btn
        end

        -- Prevent BagsBar from responding to expand/collapse state changes
        -- which would trigger unnecessary Layout calls.
        if BagsBar and EventRegistry and EventRegistry.UnregisterCallback then
            pcall(EventRegistry.UnregisterCallback, EventRegistry, "MainMenuBarManager.OnExpandChanged", BagsBar)
        end

        -- Hook Blizzard's layout to reclaim buttons if it tries to reparent them
        if not ActionBarsOwned._bagsLayoutHooked then
            ActionBarsOwned._bagsLayoutHooked = true
            local bagsBar = BagsBar
            if bagsBar and bagsBar.Layout then
                hooksecurefunc(bagsBar, "Layout", function()
                    if not ActionBarsOwned.initialized then return end
                    if not ActionBarsOwned.nativeButtons["bags"] then return end
                    if InCombatLockdown() then
                        ActionBarsOwned.pendingBagsReclaim = true
                        return
                    end
                    C_Timer.After(0, function()
                        if InCombatLockdown() then
                            ActionBarsOwned.pendingBagsReclaim = true
                            return
                        end
                        local btns = ActionBarsOwned.nativeButtons["bags"]
                        local cont = ActionBarsOwned.containers["bags"]
                        if btns and cont then
                            for _, btn in ipairs(btns) do
                                if btn:GetParent() ~= cont then
                                    btn:SetParent(cont)
                                end
                            end
                            LayoutNativeButtons("bags")
                        end
                    end)
                end)
            end
        end
    else
        -- BARS 2-8: Create fresh ActionButtonTemplate buttons.
        -- Fully dispose Blizzard's bar frame and original buttons to prevent
        -- double event processing and taint propagation from hidden frames.
        if barFrame then
            barFrame:UnregisterAllEvents()
            barFrame:SetParent(hiddenBarParent)
            barFrame:Hide()
        end
        -- Fully suppress hidden Blizzard buttons via shared helper.
        local origButtons = GetOriginalBlizzButtons(barKey)
        for _, blizzBtn in ipairs(origButtons) do
            SuppressBlizzardButton(blizzBtn)
        end

        -- Action slot offsets: each bar maps to a fixed range of action slots.
        local BAR_ACTION_OFFSETS = {
            bar2 = 60,   -- slots 61-72
            bar3 = 48,   -- slots 49-60
            bar4 = 24,   -- slots 25-36
            bar5 = 36,   -- slots 37-48
            bar6 = 144,  -- slots 145-156
            bar7 = 156,  -- slots 157-168
            bar8 = 168,  -- slots 169-180
        }
        local offset = BAR_ACTION_OFFSETS[barKey] or 0
        local barNum = barKey:sub(4)  -- "bar2" → "2"

        for i = 1, 12 do
            local btnName = "QUI_Bar" .. barNum .. "Button" .. i
            local btn = _G[btnName]
            if not btn then
                -- pcall: during combat reload, the template's OnLoad fires
                -- synchronously and hits secret-value comparisons in the
                -- tainted call stack.  The frame IS created even if OnLoad
                -- errors — retrieve it from globals.
                local ok
                ok, btn = pcall(CreateFrame, "CheckButton", btnName, container, "ActionButtonTemplate, SecureActionButtonTemplate")
                if not ok then btn = _G[btnName] end
                -- Secure action attributes (normally set by ActionBarActionButtonMixin:OnLoad)
                btn:SetAttribute("type", "action")
                btn:SetAttribute("checkselfcast", true)
                btn:SetAttribute("checkfocuscast", true)
                btn:SetAttribute("checkmouseovercast", true)
                btn:SetAttribute("useparent-unit", true)
                btn:SetAttribute("useparent-actionpage", true)
                btn:RegisterForDrag("LeftButton", "RightButton")
                -- Click registration and cast-timing policy — see the
                -- comments on the matching block in the bar1 creation
                -- path above for full rationale.
                btn:RegisterForClicks("AnyDown", "AnyUp")
                do
                    local _db = GetDB()
                    local _g = _db and _db.global
                    btn:SetAttribute("useOnKeyDown", _g and _g.useOnKeyDown == true)
                end
                -- Popup direction support — see bar1 creation path.
                if not btn.HasPopup then
                    local popupDir
                    btn.HasPopup = true
                    btn.SetPopupDirection = function(_, dir) popupDir = dir end
                    btn.GetPopupDirection = function() return popupDir end
                    btn.SetPopup = function(self2, popup)
                        if popup then
                            rawset(self2, "_quiPopup", popup)
                        end
                    end
                    btn.ClearPopup = function(self2)
                        rawset(self2, "_quiPopup", nil)
                    end
                end
                btn.flashing = 0
                btn.flashtime = 0
                local action = offset + i
                -- Set action and pressAndHoldAction from RESTRICTED code.
                -- OnAttributeChanged → Update populates icons here.
                -- Mixin methods are shadowed AFTER this loop to prevent
                -- taint errors during subsequent combat events.
                container:SetFrameRef("init-btn", btn)
                container:Execute(string.format([[
                    local btn = self:GetFrameRef("init-btn")
                    btn:SetAttribute("action", %d)
                    btn:SetAttribute("typerelease", "actionrelease")
                    if IsPressHoldReleaseSpell then
                        local pressAndHold = false
                        local actionType, id, subType = GetActionInfo(%d)
                        if actionType == "spell" then
                            pressAndHold = IsPressHoldReleaseSpell(id)
                        elseif actionType == "macro" and subType == "spell" then
                            pressAndHold = IsPressHoldReleaseSpell(id)
                        end
                        btn:SetAttribute("pressAndHoldAction", pressAndHold)
                    end
                ]], action, action))
                -- Sync btn.action from the attribute (ActionButtonTemplate
                -- has no OnAttributeChanged to do this automatically).
                btn.action = offset + i
            else
                btn:SetParent(container)
                btn.action = offset + i
            end
            btn:Show()
            buttons[i] = btn
        end
    end

    ActionBarsOwned.nativeButtons[barKey] = buttons

    -- Build slot→{button, barKey} lookup for O(1) ACTIONBAR_SLOT_CHANGED dispatch
    if not ActionBarsOwned.slotMap then ActionBarsOwned.slotMap = {} end
    for _, btn in ipairs(buttons) do
        if btn.action and btn.action > 0 then
            ActionBarsOwned.slotMap[btn.action] = { button = btn, barKey = barKey }
        end
    end

    -- Standard action bars (bar1-8): suppress Blizzard's event handling
    -- and shadow mixin methods with taint-safe versions.
    --
    -- Buttons ARE registered with SetActionUIButton so the C-side can
    -- push icon/cooldown/state updates (critical for assisted combat
    -- rotation which has no Lua event).  The taint-unsafe mixin methods
    -- (Update, UpdateAction, UpdateCooldown) are shadowed below with
    -- QUI's safe versions, so C-side ForceUpdateAction → btn:Update()
    -- hits SafeUpdate instead of the original mixin code.
    if barKey ~= "pet" and barKey ~= "stance" and barKey ~= "microbar" and barKey ~= "bags" then
        for _, btn in ipairs(buttons) do
            -- Unregister all events — QUI handles events centrally.
            btn:UnregisterAllEvents()
            -- Replace OnEvent with QUI's safe handler.  Routes cooldown
            -- events to QUI's DurationObject path; everything else to
            -- SafeUpdate.  Uses only truthiness checks — no secret value
            -- comparisons — so the handler cannot taint the context.
            btn:SetScript("OnEvent", function(self, event, ...)
                if event == "ACTIONBAR_UPDATE_COOLDOWN"
                    or event == "LOSS_OF_CONTROL_ADDED"
                    or event == "LOSS_OF_CONTROL_UPDATE" then
                    ActionBarsOwned.UpdateCooldown(self)
                else
                    ActionBarsOwned.SafeUpdate(self)
                end
            end)
            -- Shadow taint-unsafe mixin methods.  These shadows are
            -- permanent and serve two purposes:
            --   1. Internal calls (e.g. SafeUpdate → self:UpdateCount())
            --      hit the safe versions.
            --   2. Any residual mixin paths (OnAttributeChanged → Update)
            --      are intercepted before they can compare secret values.
            btn.Update = ActionBarsOwned.SafeUpdate
            btn.UpdateAction = ActionBarsOwned.SafeSyncAction
            btn.SafeSyncAction = ActionBarsOwned.SafeSyncAction  -- CallMethod target
            btn.UpdateCooldown = function(self)
                ActionBarsOwned.UpdateCooldown(self)
            end
            btn.UpdatePressAndHoldAction = function() end
            btn.UpdateCount = function(self)
                local action = self.action
                if not action or not HasAction(action) then
                    self.Count:SetText("")
                    return
                end
                if C_ActionBar and C_ActionBar.GetActionDisplayCount then
                    self.Count:SetText(C_ActionBar.GetActionDisplayCount(action) or "")
                else
                    self.Count:SetText("")
                end
            end
            -- Register with C-side so it pushes icon/state/cooldown updates.
            -- Must come AFTER method shadows so ForceUpdateAction → Update()
            -- hits SafeUpdate.
            if SetActionUIButton and btn.action and btn.cooldown then
                SetActionUIButton(btn, btn.action, btn.cooldown)
            end

            -- ActionButtonTemplate only provides BaseActionButtonMixin (flyout
            -- handling).  Tooltip code lives in ActionBarActionButtonMixin
            -- (part of ActionBarButtonTemplate) which QUI does not use.
            -- Add SetTooltip + OnEnter/OnLeave hooks for action tooltips.
            btn.SetTooltip = function(self)
                if GetCVar("UberTooltips") == "1" then
                    GameTooltip_SetDefaultAnchor(GameTooltip, self)
                else
                    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                end
                if GameTooltip:SetAction(self.action) then
                    self.UpdateTooltip = self.SetTooltip
                else
                    self.UpdateTooltip = nil
                end
            end

            -- Sync lockActionBars CVar → button attribute so the
            -- restricted OnDragStart wrap's lock check can read it
            -- (GetCVar is not available in the restricted env).
            -- MUST run every Refresh so dropdown changes propagate.
            btn:SetAttribute("buttonlock", GetCVar("lockActionBars") == "1")

            btn.QUI_PostDrag = function(self)
                OwnedButton_PostDrag(self)
            end

            -- One-time hook script and secure wrap install.  HookScript
            -- and SecureHandlerWrapScript both STACK on repeat calls —
            -- re-running these on every BuildBar/Refresh would layer N
            -- copies of every wrap, breaking buttonlock and drag/click
            -- behavior after a few setting changes.
            if not btn.quiSecureHooksInstalled then
                btn.quiSecureHooksInstalled = true

                -- Re-evaluate pressAndHoldAction whenever the button's
                -- `action` attribute changes.  Empowered / hold-to-
                -- release spells (Evoker Fire Breath, channeled actions)
                -- require pressAndHoldAction=true so the secure click
                -- dispatch fires the "release" action on mouse-up.
                -- Bar paging (_childupdate-offset, state driver) rewrites
                -- the action attribute without re-running the initial
                -- Execute block, so without this wrap the flag is stale
                -- on every page change.
                SecureHandlerWrapScript(btn, "OnAttributeChanged", btn, [[
                    if name == "action" and IsPressHoldReleaseSpell and type(value) == "number" then
                        local actionType, id, subType = GetActionInfo(value)
                        local pressAndHold = false
                        if actionType == "spell" then
                            pressAndHold = IsPressHoldReleaseSpell(id)
                        elseif actionType == "macro" and subType == "spell" then
                            pressAndHold = IsPressHoldReleaseSpell(id)
                        end
                        self:SetAttribute("pressAndHoldAction", pressAndHold)
                        self:SetAttribute("typerelease", "actionrelease")
                    end
                ]])

                btn:HookScript("OnEnter", function(self)
                    local global = GetGlobalSettings()
                    if global and global.showTooltips == false then return end
                    self:SetTooltip()
                end)
                btn:HookScript("OnLeave", function(self)
                    self.UpdateTooltip = nil
                    GameTooltip:Hide()
                end)

                -- ── PreClick: defer action to mouse-up when drag modifier held ──
                -- When useOnKeyDown is true the action fires on mouse-
                -- down, BEFORE OnDragStart can detect the drag motion.
                -- Without intervention shift-click casts instead of
                -- picking up the spell.  This Lua pre-click handler
                -- temporarily disables useOnKeyDown so the action fires
                -- on mouse-up instead — giving OnDragStart time to
                -- detect drags while still letting the action through
                -- for normal modifier+click (e.g. [mod:shift] macros).
                -- When the cursor already carries a spell (placement),
                -- the deferral is skipped so the drop goes through.
                -- Uses Lua hooks (not restricted snippets) because the
                -- restricted environment lacks GetCursorInfo().
                -- SetAttribute is fine — bar rearranging is out-of-combat.
                btn:HookScript("PreClick", function(self)
                    if InCombatLockdown() then return end
                    local useOnKeyDown = self:GetAttribute("useOnKeyDown")
                    if useOnKeyDown
                        and self:GetAttribute("buttonlock")
                        and IsModifiedClick("PICKUPACTION")
                        and not GetCursorInfo() then
                        self:SetAttribute("useOnKeyDown", false)
                        self._quiPreClickKeyDownBackup = useOnKeyDown
                    end
                end)
                btn:HookScript("PostClick", function(self)
                    if self._quiPreClickKeyDownBackup ~= nil then
                        if not InCombatLockdown() then
                            self:SetAttribute("useOnKeyDown", self._quiPreClickKeyDownBackup)
                        end
                        self._quiPreClickKeyDownBackup = nil
                    end
                end)

                -- ── Pickup / Place (secure WrapScript pattern) ──
                -- Lua OnDragStart/OnReceiveDrag handlers are nil'd, and
                -- the drag logic runs inside secure WrapScript snippets
                -- so pickup works in combat via the restricted path and
                -- the lockActionBars check stays taint-safe.
                --
                -- Click timing is NOT handled here — it's seeded at
                -- button creation from the `useOnKeyDown` profile
                -- setting and re-applied via QUI_ApplyUseOnKeyDown.

                -- OnDragStart: nil the Lua handler, let WrapScript do the
                -- pickup via return "action", slot → secure PickupAction.
                -- Double-wrapped: the post-script does NOT run when the
                -- inner pre-script causes a pickup, so the outer wrap
                -- returns a phony "message" so its post-body still fires
                -- for visual refresh.
                btn:SetScript("OnDragStart", nil)
                SecureHandlerWrapScript(btn, "OnDragStart", btn, [[
                    if (self:GetAttribute("buttonlock") and not IsModifiedClick("PICKUPACTION"))
                        or self:GetAttribute("LABdisableDragNDrop") then
                        return false
                    end
                    return "action", self:GetAttribute("action")
                ]])
                SecureHandlerWrapScript(btn, "OnDragStart", btn, [[
                    return "message", "update"
                ]], [[
                    self:CallMethod("QUI_PostDrag")
                ]])

                -- OnReceiveDrag: same double-wrap pattern.
                btn:SetScript("OnReceiveDrag", nil)
                SecureHandlerWrapScript(btn, "OnReceiveDrag", btn, [[
                    if (self:GetAttribute("buttonlock") and not IsModifiedClick("PICKUPACTION"))
                        or self:GetAttribute("LABdisableDragNDrop") then
                        return false
                    end
                    return "action", self:GetAttribute("action")
                ]])
                SecureHandlerWrapScript(btn, "OnReceiveDrag", btn, [[
                    return "message", "update"
                ]], [[
                    self:CallMethod("QUI_PostDrag")
                ]])
            end
        end

        -- Populate visuals via the mixin (safe — GetActionCount is
        -- suppressed, and shadows are in place so any internal
        -- self:Method() calls hit the safe versions).
        for _, btn in ipairs(buttons) do
            if ActionButton_Update then
                pcall(ActionButton_Update, btn)
            end
            ActionBarsOwned.UpdateCooldown(btn)
            ActionBarsOwned.UpdateOverlayGlow(btn)
        end
    end

    -- Register frame refs for the secure layout handler (must be outside combat).
    if SKINNABLE_BAR_KEYS[barKey] then
        layoutHandler:SetFrameRef("bar-" .. barKey, container)
        for i, btn in ipairs(buttons) do
            layoutHandler:SetFrameRef("btn-" .. barKey .. "-" .. i, btn)
        end
    end

    -- Micro/bag buttons are not action buttons — skip skinning, keybinds, and override bindings
    if SKINNABLE_BAR_KEYS[barKey] then
        -- Defer skinning slightly so ActionButtonTemplate has time to
        -- populate icons and visuals from the action attribute.
        local capturedSettings = settings
        C_Timer.After(0, function()
            if not capturedSettings then return end
            local btns = ActionBarsOwned.nativeButtons[barKey]
            if not btns then return end
            for _, btn in ipairs(btns) do
                -- Reset skin key to force full re-skin
                local st = GetFrameState(btn)
                st.skinKey = nil
                SkinButton(btn, capturedSettings)
                UpdateButtonText(btn, capturedSettings)
                UpdateEmptySlotVisibility(btn, capturedSettings)
            end
        end)

        -- Register keybind methods for LibKeyBound
        local prefix = BINDING_COMMANDS[barKey]
        if prefix then
            local LKB = LibStub("LibKeyBound-1.0", true)
            for i, btn in ipairs(buttons) do
                local state = GetFrameState(btn)
                state.bindingCommand = prefix .. i
                state.keybindMethods = true
                -- Hook OnEnter so LibKeyBound detects hover.
                -- No OnLeave hook needed — the binder frame handles its own OnLeave.
                -- Guard against re-entry: if the binder is already targeting this
                -- button, skip Set() to avoid a show/hide flicker loop.
                if LKB then
                    btn:HookScript("OnEnter", function(self)
                        if LKB:IsShown() then
                            local bf = LKB.frame
                            if not bf or bf.button ~= self then
                                LKB:Set(self)
                            end
                        end
                    end)
                end
            end
        end
    end

    LayoutNativeButtons(barKey)
    RestoreContainerPosition(barKey)
    SetupOwnedBarMouseover(barKey)

    -- Action bars need override bindings (reparenting disconnects native bindings)
    if SKINNABLE_BAR_KEYS[barKey] then
        ApplyBarOverrideBindings(barKey)
    end

end

---------------------------------------------------------------------------
-- PET/STANCE BAR HELPERS
---------------------------------------------------------------------------

-- Forward declarations (defined here, referenced in event handler and Initialize)
local UpdatePetBarVisibility, UpdateStanceBarLayout

-- Update a single QUI pet button's icon and state.
-- PetActionBarMixin:Update() on the original bar is suppressed (bar is hidden
-- with events unregistered), so QUI must drive pet button visuals directly.
-- Stored on ActionBarsOwned to avoid consuming a file-level local slot.
function ActionBarsOwned.UpdatePetButton(btn)
    local id = btn:GetID()
    if not id or id < 1 then return end
    local name, texture, isToken, isActive, autoCastAllowed, autoCastEnabled, spellID = GetPetActionInfo(id)
    local icon = btn.icon
    if icon then
        if texture then
            icon:SetTexture(isToken and _G[texture] or texture)
            if GetPetActionSlotUsable and GetPetActionSlotUsable(id) then
                icon:SetVertexColor(1, 1, 1)
            else
                icon:SetVertexColor(0.4, 0.4, 0.4)
            end
            icon:Show()
        else
            icon:Hide()
        end
    end
    if isActive then
        if IsPetAttackAction and IsPetAttackAction(id) then
            -- Pet Attack: flash + subtle checked highlight
            if btn.StartFlash then btn:StartFlash() end
            local ct = btn:GetCheckedTexture()
            if ct then ct:SetAlpha(0.5) end
        else
            -- Stance/ability active: full checked highlight
            if btn.StopFlash then btn:StopFlash() end
            local ct = btn:GetCheckedTexture()
            if ct then ct:SetAlpha(1.0) end
        end
        btn:SetChecked(true)
    else
        if btn.StopFlash then btn:StopFlash() end
        btn:SetChecked(false)
    end
    -- Orange active-stance border (Assist/Defensive/Passive indicator)
    local isPetAttack = IsPetAttackAction and IsPetAttackAction(id)
    local showOrangeBorder = isActive and not isPetAttack
    if showOrangeBorder then
        if not btn.QUI_ActiveBorder then
            btn.QUI_ActiveBorder = btn:CreateTexture(nil, "OVERLAY", nil, 3)
            btn.QUI_ActiveBorder:SetTexture(TEXTURES.normal)
            btn.QUI_ActiveBorder:SetAllPoints(btn)
        end
        btn.QUI_ActiveBorder:SetVertexColor(1.0, 0.6, 0.0, 1.0)
        btn.QUI_ActiveBorder:Show()
    elseif btn.QUI_ActiveBorder then
        btn.QUI_ActiveBorder:Hide()
    end
    if btn.AutoCastOverlay then
        btn.AutoCastOverlay:SetShown(autoCastAllowed and true or false)
        btn.AutoCastOverlay:ShowAutoCastEnabled(autoCastEnabled and true or false)
    end
    if btn.SpellHighlightTexture then
        if spellID and C_Spell and C_Spell.IsSpellOverlayed and C_Spell.IsSpellOverlayed(spellID) then
            btn.SpellHighlightTexture:Show()
        else
            btn.SpellHighlightTexture:Hide()
        end
    end
    -- Cooldown (also bar-driven in Blizzard code).  GetPetActionCooldown values
    -- flow directly to the C-side; pcall guards against secret-value rejection.
    local cooldown = btn.cooldown
    if cooldown and GetPetActionCooldown then
        local start, duration, enable = GetPetActionCooldown(id)
        if CooldownFrame_Set then
            pcall(CooldownFrame_Set, cooldown, start, duration, enable)
        end
    end
end

-- Update all QUI pet buttons' visuals.
function ActionBarsOwned.UpdateAllPetButtons()
    local petBtns = ActionBarsOwned.nativeButtons["pet"]
    if not petBtns then return end
    for _, btn in ipairs(petBtns) do
        ActionBarsOwned.UpdatePetButton(btn)
    end
end

-- Update a single QUI stance button's icon and state.
-- Same pattern as pet: the bar-level Update is suppressed, so QUI
-- drives stance button visuals directly via GetShapeshiftFormInfo.
function ActionBarsOwned.UpdateStanceButton(btn)
    local id = btn:GetID()
    if not id or id < 1 then return end
    local texture, isActive, isCastable, spellID = GetShapeshiftFormInfo(id)
    local icon = btn.icon
    if icon then
        if texture then
            icon:SetTexture(texture)
            if isCastable then
                icon:SetVertexColor(1, 1, 1)
            else
                icon:SetVertexColor(0.4, 0.4, 0.4)
            end
            icon:Show()
        else
            icon:Hide()
        end
    end
    if isActive then
        btn:SetChecked(true)
    else
        btn:SetChecked(false)
    end
    local cooldown = btn.cooldown
    if cooldown and GetShapeshiftFormCooldown then
        local start, duration, enable = GetShapeshiftFormCooldown(id)
        if CooldownFrame_Set then
            pcall(CooldownFrame_Set, cooldown, start, duration, enable)
        end
    end
end

-- Update all QUI stance buttons' visuals.
function ActionBarsOwned.UpdateAllStanceButtons()
    local stanceBtns = ActionBarsOwned.nativeButtons["stance"]
    if not stanceBtns then return end
    for _, btn in ipairs(stanceBtns) do
        ActionBarsOwned.UpdateStanceButton(btn)
    end
end

-- Update pet bar container visibility based on whether the player has an active pet bar.
-- PetActionBar events are unregistered (we took ownership), so we drive visibility ourselves.
UpdatePetBarVisibility = function()
    local container = ActionBarsOwned.containers["pet"]
    if not container then return end

    local barDB = GetBarSettings("pet")
    if barDB and barDB.enabled == false then
        container:SetAttribute("qui-user-shown", false)
        if not InCombatLockdown() or inInitSafeWindow then
            container:Hide()
        else
            ActionBarsOwned.pendingPetUpdate = true
        end
        -- Notify anchoring system so dependents (e.g. stance bar) can re-anchor
        if _G.QUI_UpdateFramesAnchoredTo then _G.QUI_UpdateFramesAnchoredTo("petBar") end
        return
    end

    -- HasPetUI() returns true when the player has a controllable pet with a bar
    if InCombatLockdown() and not inInitSafeWindow then
        -- Show/Hide are protected — defer to PLAYER_REGEN_ENABLED
        ActionBarsOwned.pendingPetUpdate = true
        return
    end
    local wasShown = container:IsShown()
    local hasPet = HasPetUI and HasPetUI()
    if hasPet then
        container:SetAttribute("qui-user-shown", true)
        container:Show()
        -- Populate pet button icons/state (PetActionBarMixin:Update on the
        -- original bar is suppressed, so QUI drives visuals directly).
        ActionBarsOwned.UpdateAllPetButtons()
        LayoutNativeButtons("pet")
        -- Re-evaluate mouseover fade so alwaysShow / fade alpha are correct
        SetupOwnedBarMouseover("pet")
        -- Let the HUD visibility system re-assert its fade state so mounting
        -- / flying / vehicle hide rules take precedence over the mouseover
        -- fade alpha that SetupOwnedBarMouseover just applied.
        if _G.QUI_RefreshActionBarsVisibility then
            _G.QUI_RefreshActionBarsVisibility()
        end
    elseif inInitSafeWindow and InCombatLockdown() then
        -- During a combat reload, pet data may not be available yet at PEW
        -- time (HasPetUI returns false). Don't hide — defer to
        -- PLAYER_REGEN_ENABLED so pet events have a chance to populate.
        ActionBarsOwned.pendingPetUpdate = true
    else
        container:SetAttribute("qui-user-shown", false)
        container:Hide()
    end
    -- Notify anchoring system when visibility changed so dependents re-anchor
    local isShown = container:IsShown()
    if wasShown ~= isShown and _G.QUI_UpdateFramesAnchoredTo then
        _G.QUI_UpdateFramesAnchoredTo("petBar")
    end
end

-- Update stance bar layout: show only the buttons matching GetNumShapeshiftForms().
UpdateStanceBarLayout = function()
    local container = ActionBarsOwned.containers["stance"]
    if not container then return end

    if InCombatLockdown() and not inInitSafeWindow then
        ActionBarsOwned.pendingStanceUpdate = true
        return
    end

    local barDB = GetBarSettings("stance")
    if barDB and barDB.enabled == false then
        container:SetAttribute("qui-user-shown", false)
        container:Hide()
        if _G.QUI_UpdateFramesAnchoredTo then _G.QUI_UpdateFramesAnchoredTo("stanceBar") end
        return
    end

    local wasShown = container:IsShown()
    local numForms = GetNumShapeshiftForms and GetNumShapeshiftForms() or 0
    local buttons = ActionBarsOwned.nativeButtons["stance"]
    if not buttons then return end

    if numForms == 0 then
        if inInitSafeWindow and InCombatLockdown() then
            -- During a combat reload, shapeshift data may not be available
            -- yet at PEW time. Don't hide — defer to PLAYER_REGEN_ENABLED.
            ActionBarsOwned.pendingStanceUpdate = true
            return
        end
        container:SetAttribute("qui-user-shown", false)
        container:Hide()
        if wasShown and _G.QUI_UpdateFramesAnchoredTo then
            _G.QUI_UpdateFramesAnchoredTo("stanceBar")
        end
        return
    end

    container:SetAttribute("qui-user-shown", true)
    container:Show()

    -- Populate stance button icons/state (bar-level Update is suppressed).
    ActionBarsOwned.UpdateAllStanceButtons()

    -- Clamp ownedLayout.iconCount to actual form count for layout
    local layout = barDB and barDB.ownedLayout
    if layout then
        -- Temporarily clamp iconCount for the layout pass
        local savedIconCount = layout.iconCount
        layout.iconCount = math.min(layout.iconCount or 10, numForms)
        LayoutNativeButtons("stance")
        layout.iconCount = savedIconCount
    else
        LayoutNativeButtons("stance")
    end

    -- Re-evaluate mouseover fade so alwaysShow / fade alpha are correct
    SetupOwnedBarMouseover("stance")
    -- Let the HUD visibility system re-assert its fade state so mounting
    -- / flying / vehicle hide rules take precedence over the mouseover
    -- fade alpha that SetupOwnedBarMouseover just applied.
    if _G.QUI_RefreshActionBarsVisibility then
        _G.QUI_RefreshActionBarsVisibility()
    end

    -- Notify anchoring system when visibility changed
    if not wasShown and _G.QUI_UpdateFramesAnchoredTo then
        _G.QUI_UpdateFramesAnchoredTo("stanceBar")
    end
end

---------------------------------------------------------------------------
-- EVENT HANDLING
---------------------------------------------------------------------------

local ownedEventFrame = CreateFrame("Frame")

-- Refresh empty slot visibility and skinning for all native buttons
local function RefreshAllNativeVisuals()
    for _, barKey in ipairs(ALL_MANAGED_BAR_KEYS) do
        local buttons = ActionBarsOwned.nativeButtons[barKey]
        local settings = GetEffectiveSettings(barKey)
        if buttons and settings and SKINNABLE_BAR_KEYS[barKey] then
            for _, btn in ipairs(buttons) do
                SkinButton(btn, settings)
                UpdateButtonText(btn, settings)
                UpdateEmptySlotVisibility(btn, settings)
            end
        end
    end
end

-- Refresh keybind text on all native buttons
local function RefreshNativeKeybinds()
    for _, barKey in ipairs(ALL_MANAGED_BAR_KEYS) do
        local buttons = ActionBarsOwned.nativeButtons[barKey]
        local settings = GetEffectiveSettings(barKey)
        if buttons and settings then
            for _, btn in ipairs(buttons) do
                UpdateKeybindText(btn, settings)
            end
        end
    end
    -- Refresh all override bindings
    ApplyAllOverrideBindings()
end

-- Forward declaration for extra button functions used in event handler
local InitializeExtraButtons
local RefreshExtraButtons
local ApplyPageArrowVisibility

---------------------------------------------------------------------------
-- OWNED COOLDOWN UPDATE (12.0.5+ DurationObject path)
---------------------------------------------------------------------------
-- Replaces Blizzard's ActionButton_UpdateCooldown which can no longer call
-- SetCooldown with secret values from tainted code.  Uses the new
-- C_ActionBar structured APIs (isActive boolean, DurationObjects) to drive
-- cooldown display via SetCooldownFromDurationObject — the only remaining
-- secret-safe cooldown setter.
--
-- All helpers are scoped inside a do...end block to stay within Lua's
-- 200 file-scope local variable limit.  Public functions are stored as
-- ActionBarsOwned fields.

do
    -- Build 66562+ removed the secure delegate from ActionButton_ApplyCooldown
    -- and blocked SetCooldown from accepting secret values in tainted context.
    local USE_DURATION_OBJECTS = IS_MIDNIGHT
        and C_ActionBar ~= nil
        and C_ActionBar.GetActionCooldownDuration ~= nil
        and (tonumber((select(2, GetBuildInfo()))) or 0) >= 66562

    local DEFAULT_CD_INFO  = { startTime = 0, duration = 0, isEnabled = false, isActive = false, modRate = 0 }
    local DEFAULT_CHG_INFO = { currentCharges = 0, maxCharges = 0, cooldownStartTime = 0, cooldownDuration = 0, chargeModRate = 0, isActive = false }
    local DEFAULT_LOC_INFO = { startTime = 0, duration = 0, modRate = 0, isActive = false, shouldReplaceNormalCooldown = false }

    local function GetOrCreateChargeCooldown(button)
        if button.chargeCooldown then return button.chargeCooldown end
        local parent = button.cooldown or button
        local cd = CreateFrame("Cooldown", nil, button, "CooldownFrameTemplate")
        cd:SetHideCountdownNumbers(true)
        cd:SetDrawSwipe(false)
        cd:SetAllPoints(parent)
        cd:SetFrameLevel(button:GetFrameLevel())
        button.chargeCooldown = cd
        return cd
    end

    local function GetOrCreateLoCCooldown(button)
        if button.lossOfControlCooldown then return button.lossOfControlCooldown end
        local parent = button.cooldown or button
        local cd = CreateFrame("Cooldown", nil, button, "CooldownFrameTemplate")
        cd:SetHideCountdownNumbers(true)
        cd:SetAllPoints(parent)
        cd:SetFrameLevel(button:GetFrameLevel() + 1)
        cd:SetSwipeColor(0.17, 0, 0, 0.8)
        button.lossOfControlCooldown = cd
        return cd
    end

    local function SetOrClearCooldown(cooldown, shouldShow, durationObject)
        if not cooldown then return end
        if not shouldShow or not durationObject then
            cooldown:Clear()
            return
        end
        cooldown:SetCooldownFromDurationObject(durationObject)
    end

    -- Per-button "was on cooldown last scan" cache. Skips redundant Clear()
    -- calls on idle buttons (the common case — ~90 of 96 buttons are usually
    -- off cooldown at any given moment). In raid combat, SPELL_UPDATE_COOLDOWN
    -- fires ~20-30/sec and we scan all 96 buttons on each tick; without this
    -- cache we hit Clear() 270 times per tick (cooldown + charge + LoC frames)
    -- for buttons that are already cleared.
    local _buttonWasActive = setmetatable({}, { __mode = "k" })

    function ActionBarsOwned.UpdateCooldown(button)
        -- Hot path: called every ~100ms for all active buttons. Every
        -- saved Lua op compounds to measurable ms/sec in raid combat.
        -- `button.action` is always set by SafeSyncAction/state driver,
        -- so the GetAttribute fallback is dead code and has been removed.
        local action = button.action
        if not action or action == 0 then return end

        local cooldown = button.cooldown or button.Cooldown
        if not cooldown then return end

        if USE_DURATION_OBJECTS then
            -- Fast path: check primary cooldown first (1 API call).
            -- If not active, skip charges/LoC entirely (saves 2 API calls per
            -- button for the majority of buttons not on cooldown at any moment).
            local cdInfo  = C_ActionBar.GetActionCooldown(action) or DEFAULT_CD_INFO
            local chgInfo = C_ActionBar.GetActionCharges(action) or DEFAULT_CHG_INFO
            local cdActive = cdInfo.isActive
            local chActive = chgInfo.isActive
            if not cdActive and not chActive then
                -- Idle button: only clear the frames on the active→inactive
                -- transition. Subsequent idle scans skip the Clear() churn.
                -- Note: a charged spell with an unspent charge (e.g. 1/2)
                -- is still "active" here because its recharge swipe must
                -- drive the charge cooldown frame even though the primary
                -- cooldown is idle.
                if _buttonWasActive[button] then
                    _buttonWasActive[button] = nil
                    cooldown:Clear()
                    if button.chargeCooldown then button.chargeCooldown:Clear() end
                    if button.lossOfControlCooldown then button.lossOfControlCooldown:Clear() end
                end
                return
            end
            _buttonWasActive[button] = true

            -- Button is on cooldown and/or recharging a charge — LoC is the
            -- remaining query.
            local locInfo = C_ActionBar.GetActionLossOfControlCooldownInfo(action) or DEFAULT_LOC_INFO

            local showLoC    = locInfo.isActive
            local showCharge = not locInfo.shouldReplaceNormalCooldown and chActive
            local showNormal = not locInfo.shouldReplaceNormalCooldown and cdActive

            -- Normal cooldown (only fetch DurationObject when needed)
            if showNormal then
                SetOrClearCooldown(cooldown, true, C_ActionBar.GetActionCooldownDuration(action))
            else
                cooldown:Clear()
            end

            -- Charge cooldown (lazy-create frame)
            if showCharge then
                SetOrClearCooldown(GetOrCreateChargeCooldown(button), true, C_ActionBar.GetActionChargeDuration(action))
            elseif button.chargeCooldown then
                button.chargeCooldown:Clear()
            end

            -- Loss of control cooldown (lazy-create frame)
            if showLoC then
                SetOrClearCooldown(GetOrCreateLoCCooldown(button), true, C_ActionBar.GetActionLossOfControlCooldownDuration(action))
            elseif button.lossOfControlCooldown then
                button.lossOfControlCooldown:Clear()
            end
        else
            -- Pre-12.0.5 fallback: delegate to Blizzard's handler (pcall for safety)
            if ActionButton_UpdateCooldown then
                pcall(ActionButton_UpdateCooldown, button)
            end
        end
    end

    local _lastCdUpdateTime = 0
    function ActionBarsOwned.UpdateAllCooldowns()
        -- Hard throttle: max once per frame (prevents duplicate work when
        -- multiple code paths trigger cooldown updates in the same frame)
        local now = GetTime()
        if now == _lastCdUpdateTime then return end
        _lastCdUpdateTime = now

        -- Fast path: iterate only buttons with actions (LibActionButton
        -- pattern). Typical raid: ~30-50 active of 96 total.
        local activeButtons = ActionBarsOwned._activeButtons
        if next(activeButtons) ~= nil then
            for btn in pairs(activeButtons) do
                ActionBarsOwned.UpdateCooldown(btn)
            end
            return
        end

        -- Fallback: full scan before the first SafeUpdate pass has
        -- populated _activeButtons (fresh login, brief window before
        -- PLAYER_ENTERING_WORLD-driven refresh).
        for _, barKey in ipairs(STANDARD_BAR_KEYS) do
            local buttons = ActionBarsOwned.nativeButtons[barKey]
            if buttons then
                for _, btn in ipairs(buttons) do
                    if HasAction(btn.action or 0) then
                        ActionBarsOwned.UpdateCooldown(btn)
                    end
                end
            end
        end
    end

end -- do block (cooldown ownership)

---------------------------------------------------------------------------
-- SPELL ACTIVATION OVERLAY GLOW
---------------------------------------------------------------------------
-- Self-managed proc glow system.  Replaces the C-side glow that was
-- previously provided by SetActionUIButton registration.  Driven by
-- SPELL_ACTIVATION_OVERLAY_GLOW_SHOW/HIDE events.  Uses LibCustomGlow
-- for the visual effect (same library used by CDM glows).
---------------------------------------------------------------------------
do -- spell glow / highlight / assisted rotation

local LCG = LibStub and LibStub("LibCustomGlow-1.0", true)

-- Extract the spell ID from an action button's current action.
-- Returns nil for empty slots, items, or if GetActionInfo errors (combat).
local function GetButtonSpellId(button)
    local action = button.action
    if not action then return nil end
    if not HasAction(action) then return nil end

    local ok, actionType, id, subType = pcall(GetActionInfo, action)
    if not ok then return nil end

    if actionType == "spell" then
        return id
    elseif actionType == "macro" then
        if subType == "spell" then
            return id
        end
        -- Fallback: GetMacroSpell for macros without spell subType
        if GetMacroSpell then
            local macroOk, spellId = pcall(GetMacroSpell, id)
            if macroOk and spellId then return spellId end
        end
    end
    return nil
end

local function ForEachSpellCandidate(spellId, callback)
    if not spellId or not callback then return end

    local seen = {}
    local function Visit(id)
        if id and not seen[id] then
            seen[id] = true
            callback(id)
        end
    end

    Visit(spellId)

    if C_Spell and C_Spell.GetOverrideSpell then
        local ok, overrideId = pcall(C_Spell.GetOverrideSpell, spellId)
        if ok and overrideId and overrideId ~= spellId then
            Visit(overrideId)
        end
    end
end

-- Check if the button's action is a flyout containing a specific spell.
local function ButtonFlyoutContainsSpell(button, spellId)
    local action = button.action
    if not action then return false end
    local ok, actionType, id = pcall(GetActionInfo, action)
    if not ok or actionType ~= "flyout" then return false end
    if FlyoutHasSpell then
        local fok, has = pcall(FlyoutHasSpell, id, spellId)
        if fok and has then return true end
    end
    return false
end

---------------------------------------------------------------------------
-- SPELL-TO-BUTTONS REVERSE LOOKUP
---------------------------------------------------------------------------
-- Maps spellId → {btn1, btn2, ...} for O(1) glow event dispatch instead of
-- scanning all ~96 buttons on every proc event.  Rebuilt when action bar
-- content changes (visual update, slot change).
local spellIdToButtons = {}
local flyoutButtons = {}  -- buttons with flyout actions (checked as fallback)

local function RebuildSpellIdMap()
    wipe(spellIdToButtons)
    wipe(flyoutButtons)
    for _, barKey in ipairs(STANDARD_BAR_KEYS) do
        local btns = ActionBarsOwned.nativeButtons[barKey]
        if btns then
            for _, btn in ipairs(btns) do
                local spellId = GetButtonSpellId(btn)
                if spellId then
                    ForEachSpellCandidate(spellId, function(candidateId)
                        local list = spellIdToButtons[candidateId]
                        if not list then
                            list = {}
                            spellIdToButtons[candidateId] = list
                        end
                        list[#list + 1] = btn
                    end)
                else
                    -- Check if this is a flyout button (rare but possible)
                    local action = btn.action
                    if action and HasAction(action) then
                        local ok, actionType = pcall(GetActionInfo, action)
                        if ok and actionType == "flyout" then
                            flyoutButtons[#flyoutButtons + 1] = btn
                        end
                    end
                end
            end
        end
    end
end

local function ShowActionButtonGlow(button)
    if not LCG then return end
    local state = GetFrameState(button)
    if state.quiProcGlow then return end
    state.quiProcGlow = true
    LCG.ButtonGlow_Start(button)
end

local function HideActionButtonGlow(button)
    if not LCG then return end
    local state = GetFrameState(button)
    if not state.quiProcGlow then return end
    state.quiProcGlow = false
    LCG.ButtonGlow_Stop(button)
end

-- Update the overlay glow on a single button based on current spell state.
function ActionBarsOwned.UpdateOverlayGlow(button)
    local spellId = GetButtonSpellId(button)
    if spellId then
        local IsSpellOverlayed = C_SpellActivationOverlay and C_SpellActivationOverlay.IsSpellOverlayed
            or _G.IsSpellOverlayed
        if IsSpellOverlayed then
            local overlayed = false
            ForEachSpellCandidate(spellId, function(candidateId)
                if overlayed then return end
                local ok, result = pcall(IsSpellOverlayed, candidateId)
                if ok and result then
                    overlayed = true
                end
            end)
            if overlayed then
                ShowActionButtonGlow(button)
                return
            end
        end
    end
    HideActionButtonGlow(button)
end

---------------------------------------------------------------------------
-- SPELLBOOK HOVER HIGHLIGHT
-- When hovering a spell in the spellbook, highlight matching buttons.
---------------------------------------------------------------------------

ActionBarsOwned.spellHighlight = { type = nil, id = nil }

local function UpdateSpellHighlight(button)
    local spellHighlight = ActionBarsOwned.spellHighlight
    local shown = false
    if spellHighlight.type == "spell" then
        local btnSpellId = GetButtonSpellId(button)
        if btnSpellId and btnSpellId == spellHighlight.id then
            shown = true
        end
    elseif spellHighlight.type == "flyout" then
        local action = button.action
        if action then
            local ok, actionType, actionId = pcall(GetActionInfo, action)
            if ok and actionType == "flyout" and actionId == spellHighlight.id then
                shown = true
            end
        end
    end

    if shown then
        if button.SpellHighlightTexture then
            button.SpellHighlightTexture:Show()
        end
        if button.SpellHighlightAnim then
            button.SpellHighlightAnim:Play()
        end
    else
        if button.SpellHighlightTexture then
            button.SpellHighlightTexture:Hide()
        end
        if button.SpellHighlightAnim then
            button.SpellHighlightAnim:Stop()
        end
    end
end

local function UpdateAllSpellHighlights()
    for _, barKey in ipairs(STANDARD_BAR_KEYS) do
        local btns = ActionBarsOwned.nativeButtons[barKey]
        if btns then
            for _, btn in ipairs(btns) do
                UpdateSpellHighlight(btn)
            end
        end
    end
end

---------------------------------------------------------------------------
-- ASSISTED COMBAT ROTATION
-- Show arrow overlay on buttons with the one-button rotation action.
---------------------------------------------------------------------------

-- Tracks whether any button has ever shown an assisted combat rotation
-- frame.  Once true, SafeUpdate must check every button.  While false,
-- we can skip the per-button pcall entirely — a huge saving when the
-- feature isn't in use (majority of players).  Set to true by
-- OnSetActionSpell callback and by the first successful frame creation.
-- Stored on the module table so the EventRegistry callback (outside
-- this do block) can set it.
ActionBarsOwned._assistedCombatEverActive = false

-- The single button that currently hosts the AssistedCombatRotationFrame.
-- There is only ever one rotation slot, so rotation updates only need to
-- touch this one button instead of sweeping all 96.
local _assistRotationButton = nil

UpdateAssistedCombatRotationFrame = function(button)
    if not (C_ActionBar and C_ActionBar.IsAssistedCombatAction) then return end
    -- Fast path: if assisted combat was never active AND this button has
    -- no rotation frame, skip entirely.
    local frame = button.AssistedCombatRotationFrame
    if not ActionBarsOwned._assistedCombatEverActive and not frame then return end

    local action = button.action
    local show = false
    local hasAction = action and HasAction(action)
    if hasAction then
        show = C_ActionBar.IsAssistedCombatAction(action)
    end

    -- Only create the template frame when needed (first time it should show).
    if show and not frame then
        ActionBarsOwned._assistedCombatEverActive = true
        frame = CreateFrame("Frame", nil, button, "ActionBarButtonAssistedCombatRotationTemplate")
        button.AssistedCombatRotationFrame = frame
        _assistRotationButton = button
        -- The template OnLoad sets frame level relative to MainActionBar's
        -- EndCaps, which QUI reparented to a hidden frame (low level).
        -- Override to sit above the button so it's visible over QUI's
        -- border/gloss overlays.
        frame:SetFrameLevel(button:GetFrameLevel() + 5)
    end
    -- Always delegate to UpdateState — the template manages its own
    -- show/hide and has internal event handlers that can re-show the
    -- frame if we only call Hide() manually.
    if frame then
        frame:UpdateState()
        -- Re-assert frame level: the template's OnEvent resets it
        -- relative to MainActionBar (reparented/hidden in QUI).
        frame:SetFrameLevel(button:GetFrameLevel() + 5)
    end
end

local function UpdateAllAssistedCombatRotation()
    -- Fast path: one known rotation button, update just it.
    if _assistRotationButton then
        UpdateAssistedCombatRotationFrame(_assistRotationButton)
        return
    end

    -- Discovery pass: no rotation button known yet.  Look up the slot for
    -- the current recommendation and update that one button.  Once it
    -- creates a frame, _assistRotationButton gets set and subsequent
    -- updates take the fast path above.
    if not (C_AssistedCombat and C_AssistedCombat.GetNextCastSpell
        and C_ActionBar and C_ActionBar.FindSpellActionButtons) then
        return
    end
    local ok, spellID = pcall(C_AssistedCombat.GetNextCastSpell, false)
    if not ok or not spellID then return end
    local slots = C_ActionBar.FindSpellActionButtons(spellID)
    if not slots then return end
    local slotMap = ActionBarsOwned.slotMap
    if not slotMap then return end
    for _, slot in ipairs(slots) do
        local entry = slotMap[slot]
        if entry and entry.button then
            UpdateAssistedCombatRotationFrame(entry.button)
            if _assistRotationButton then return end
        end
    end
end

---------------------------------------------------------------------------
-- ASSISTED COMBAT HIGHLIGHT
-- Shows marching-ants highlight on buttons matching the next recommended
-- spell from the rotation assistant (C_AssistedCombat).  Separate from
-- the rotation frame above, which marks the one-button rotation slot.
---------------------------------------------------------------------------

local assistedHighlightButtons = {}  -- set of buttons currently highlighted (button → true)
local _assistHighlightScratch = {}   -- reusable scratch table to avoid per-frame allocation
local ASSISTED_HIGHLIGHT_COLOR = { 0.2, 0.82, 0.6, 1 }  -- Teal/mint, matches QUI accent

local function SetAssistedHighlightShown(button, show)
    if not LCG then return end
    local state = GetFrameState(button)
    if show then
        if state.quiAssistedHighlight then return end
        state.quiAssistedHighlight = true
        LCG.ButtonGlow_Start(button, ASSISTED_HIGHLIGHT_COLOR)
    else
        if not state.quiAssistedHighlight then return end
        state.quiAssistedHighlight = false
        LCG.ButtonGlow_Stop(button)
    end
end

UpdateAllAssistedHighlights = function()
    if not (C_AssistedCombat and C_AssistedCombat.GetNextCastSpell) then return end
    if not (C_ActionBar and C_ActionBar.FindSpellActionButtons) then return end

    local db = GetDB()
    if not (db and db.global and db.global.assistedHighlight) then
        for btn in pairs(assistedHighlightButtons) do
            SetAssistedHighlightShown(btn, false)
        end
        wipe(assistedHighlightButtons)
        return
    end

    local okNext, nextSpellID = pcall(C_AssistedCombat.GetNextCastSpell, false)
    if not okNext then nextSpellID = nil end

    -- Build match set into a reusable scratch table to avoid per-call
    -- allocation — this runs up to 10x/sec under soft targeting.
    local matchButtons = _assistHighlightScratch
    wipe(matchButtons)
    if nextSpellID then
        local slots = C_ActionBar.FindSpellActionButtons(nextSpellID)
        if slots then
            local slotMap = ActionBarsOwned.slotMap
            if slotMap then
                for _, slot in ipairs(slots) do
                    local entry = slotMap[slot]
                    if entry and entry.button then
                        matchButtons[entry.button] = true
                    end
                end
            end
        end
    end

    -- Clear previously highlighted buttons that are no longer in the match set.
    for btn in pairs(assistedHighlightButtons) do
        if not matchButtons[btn] then
            SetAssistedHighlightShown(btn, false)
        end
    end

    -- Apply highlights to matching buttons.
    for btn in pairs(matchButtons) do
        SetAssistedHighlightShown(btn, true)
    end

    -- Swap: move scratch results into the live set, reuse the old live
    -- table as next call's scratch.  Zero allocation per frame.
    _assistHighlightScratch = assistedHighlightButtons
    wipe(_assistHighlightScratch)
    assistedHighlightButtons = matchButtons
end

-- Update overlay glows on all owned action buttons.
function ActionBarsOwned.UpdateAllOverlayGlows()
    for _, barKey in ipairs(STANDARD_BAR_KEYS) do
        local btns = ActionBarsOwned.nativeButtons[barKey]
        if btns then
            for _, btn in ipairs(btns) do
                ActionBarsOwned.UpdateOverlayGlow(btn)
            end
        end
    end
end

-- Handle SPELL_ACTIVATION_OVERLAY_GLOW_SHOW: O(1) lookup via reverse map,
-- flyout fallback for rare flyout-containing-spell case.
local function ForEachButtonForSpellGlow(spellId, callback)
    if not spellId or not callback then return false end

    local matched = false
    local visited = {}
    local slotMap = ActionBarsOwned.slotMap

    local function VisitButton(button)
        if button and not visited[button] then
            visited[button] = true
            matched = true
            callback(button)
        end
    end

    ForEachSpellCandidate(spellId, function(candidateId)
        local btns = spellIdToButtons[candidateId]
        if btns then
            for _, btn in ipairs(btns) do
                VisitButton(btn)
            end
        end

        for _, btn in ipairs(flyoutButtons) do
            if ButtonFlyoutContainsSpell(btn, candidateId) then
                VisitButton(btn)
            end
        end

        if C_ActionBar and C_ActionBar.FindSpellActionButtons and slotMap then
            local ok, slots = pcall(C_ActionBar.FindSpellActionButtons, candidateId)
            if ok and slots then
                for _, slot in ipairs(slots) do
                    local entry = slotMap[slot]
                    if entry and entry.button then
                        VisitButton(entry.button)
                    end
                end
            end
        end
    end)

    return matched
end

function ActionBarsOwned.OnSpellActivationGlowShow(spellId)
    if not spellId then return end
    if not ForEachButtonForSpellGlow(spellId, ShowActionButtonGlow) then
        -- Some proc events fire for spell IDs that do not appear directly on
        -- the button (base vs current override). Fall back to a cheap full
        -- rescan so the visible button still picks up the glow.
        ActionBarsOwned.UpdateAllOverlayGlows()
    end
end

-- Handle SPELL_ACTIVATION_OVERLAY_GLOW_HIDE: O(1) lookup via reverse map,
-- flyout fallback for rare flyout-containing-spell case.
function ActionBarsOwned.OnSpellActivationGlowHide(spellId)
    if not spellId then return end
    if not ForEachButtonForSpellGlow(spellId, HideActionButtonGlow) then
        ActionBarsOwned.UpdateAllOverlayGlows()
    end
end

ActionBarsOwned.RebuildSpellIdMap = RebuildSpellIdMap
ActionBarsOwned.UpdateAllSpellHighlights = UpdateAllSpellHighlights
ActionBarsOwned.ShowActionButtonGlow = ShowActionButtonGlow
ActionBarsOwned.HideActionButtonGlow = HideActionButtonGlow
ActionBarsOwned.UpdateAllAssistedCombatRotation = UpdateAllAssistedCombatRotation
ActionBarsOwned.UpdateAllAssistedHighlights = function() UpdateAllAssistedHighlights() end

end -- do (spell glow / highlight / assisted rotation)

-- Lean checked-state refresh: IsCurrentAction / IsAutoRepeatAction +
-- SetChecked. Used for ACTIONBAR_UPDATE_STATE which fires frequently in
-- combat (every autoattack toggle, every current-action change). Avoids
-- the 20-API-call full SafeUpdate path for events that only affect
-- the checked state. Mirrors LibActionButton's UpdateButtonState.
local _lastStateUpdateTime = 0
function ActionBarsOwned.UpdateAllButtonStates()
    local now = GetTime()
    if now == _lastStateUpdateTime then return end
    _lastStateUpdateTime = now

    for btn in pairs(ActionBarsOwned._activeButtons) do
        local action = btn.action
        if action and action ~= 0 then
            if IsCurrentAction(action) or IsAutoRepeatAction(action) then
                btn:SetChecked(true)
            else
                btn:SetChecked(false)
            end
        end
    end
end

-- Lean count refresh: UpdateCount on active buttons only.
-- Used for UNIT_AURA which fires when aura-based resource overlays
-- (Soul Fragments, etc.) change.  Avoids full SafeUpdate.
local _lastCountUpdateTime = 0
function ActionBarsOwned.UpdateAllButtonCounts()
    local now = GetTime()
    if now == _lastCountUpdateTime then return end
    _lastCountUpdateTime = now

    for btn in pairs(ActionBarsOwned._activeButtons) do
        if btn.UpdateCount then pcall(btn.UpdateCount, btn) end
    end
end

-- Full visual refresh for all owned action buttons via SafeUpdate.
-- Uses only truthiness tests on API returns — safe during combat.
local _lastVisualUpdateTime = 0
local _visualFirstRunDone = false
function ActionBarsOwned.UpdateAllButtonVisuals()
    -- Hard throttle: max once per frame
    local now = GetTime()
    if now == _lastVisualUpdateTime then return end
    _lastVisualUpdateTime = now

    -- First run needs a full scan: it's where _activeButtons gets populated
    -- for the first time (SafeUpdate sets the entries). All empty-slot
    -- visuals are also initialized here. Subsequent runs iterate only the
    -- active set (typical: 30-50 vs 96).
    --
    -- Full scans also run when SPELLS_CHANGED, PLAYER_ENTERING_WORLD, or
    -- similar "something big happened" events fire — those need to walk
    -- every button to catch mass action-table shuffles. Those events
    -- force _visualFirstRunDone = false via ForceFullVisualRescan.
    if not _visualFirstRunDone then
        for _, barKey in ipairs(STANDARD_BAR_KEYS) do
            local btns = ActionBarsOwned.nativeButtons[barKey]
            if btns then
                for _, btn in ipairs(btns) do
                    local action = btn.action or 0
                    if HasAction(action) then
                        local state = GetFrameState(btn)
                        state.wasEmpty = false
                        pcall(ActionBarsOwned.SafeUpdate, btn)
                    else
                        local state = GetFrameState(btn)
                        if not state.wasEmpty then
                            state.wasEmpty = true
                            pcall(ActionBarsOwned.SafeUpdate, btn)
                        end
                    end
                end
            end
        end
        _visualFirstRunDone = true
    else
        -- Fast path: iterate only buttons with actions. Active→empty
        -- transitions are handled by SafeSyncAction/ACTIONBAR_SLOT_CHANGED
        -- paths calling SafeUpdate directly on the affected button.
        for btn in pairs(ActionBarsOwned._activeButtons) do
            local state = GetFrameState(btn)
            state.wasEmpty = false
            pcall(ActionBarsOwned.SafeUpdate, btn)
        end
    end

    -- Rebuild spell-to-button reverse lookup for glow events
    ActionBarsOwned.RebuildSpellIdMap()
end

-- Force the next UpdateAllButtonVisuals call to do a full scan (covers
-- mass action-table shuffles where individual slot events aren't reliable).
function ActionBarsOwned.ForceFullVisualRescan()
    _visualFirstRunDone = false
end

---------------------------------------------------------------------------
-- EVENT COALESCING (elapsed-time gated Show/Hide)
---------------------------------------------------------------------------
-- Events activate the frame via Show().  OnUpdate checks elapsed time
-- and only runs the update after a minimum interval.  Multiple events
-- in the same frame are coalesced (Show on shown = no-op).  If the
-- interval hasn't elapsed, the frame stays shown and retries next frame.
-- Zero closure allocation.
--
-- Out of combat all updates flush immediately (next frame) for zero-latency
-- visual changes.  In combat, high-frequency events (ACTIONBAR_UPDATE_COOLDOWN,
-- ACTIONBAR_UPDATE_STATE) are coalesced behind these interval gates (~30Hz).
-- Low-frequency events (SPELL_UPDATE_ICON, PLAYER_ENTER/LEAVE_COMBAT) set the
-- _immediate flag to bypass the combat throttle for that tick.
local AB_CD_UPDATE_INTERVAL    = 0.033  -- 33ms in-combat cooldown gate (~30Hz)
local AB_STATE_UPDATE_INTERVAL = 0.033  -- 33ms in-combat checked-state gate
local AB_VIS_UPDATE_INTERVAL   = 0.033  -- 33ms in-combat visual gate

-- Unified update frame: merges cooldown, state and visual update into a
-- single OnUpdate handler with dirty flags. When visuals are dirty,
-- SafeUpdate already covers checked state + cooldown internally, so those
-- flags are subsumed. When only state is dirty (common in combat from
-- ACTIONBAR_UPDATE_STATE), a lean per-button SetChecked pass runs instead
-- of the 20-API-call SafeUpdate chain.
local abUpdateFrame = CreateFrame("Frame")
abUpdateFrame:Hide()
abUpdateFrame._lastCd = 0
abUpdateFrame._lastState = 0
abUpdateFrame._lastVis = 0
abUpdateFrame._dirtyCooldowns = false
abUpdateFrame._dirtyStates = false
abUpdateFrame._dirtyVisuals = false
abUpdateFrame._dirtyCounts = false
abUpdateFrame._immediate = false  -- bypass combat throttle for this tick
abUpdateFrame._lastCount = 0
abUpdateFrame:SetScript("OnUpdate", function(self)
    local now = GetTime()
    -- Out of combat: flush immediately (no throttle).
    -- In combat: coalesce high-frequency events behind interval gates.
    -- _immediate flag lets low-frequency events (icon change, form swap)
    -- bypass the combat throttle for a single tick.
    local throttle = InCombatLockdown() and not self._immediate
    self._immediate = false

    local doVis = self._dirtyVisuals
    local doState = self._dirtyStates
    local doCd  = self._dirtyCooldowns
    local doCount = self._dirtyCounts

    if doVis then
        if throttle and (now - self._lastVis < AB_VIS_UPDATE_INTERVAL) then return end
        self:Hide()
        self._lastVis = now
        self._lastCd = now
        self._lastState = now
        self._lastCount = now
        self._dirtyCooldowns = false
        self._dirtyStates = false
        self._dirtyVisuals = false
        self._dirtyCounts = false
        -- SafeUpdate includes cooldown + checked state + count internally
        ActionBarsOwned.UpdateAllButtonVisuals()
    elseif doState then
        if throttle and (now - self._lastState < AB_STATE_UPDATE_INTERVAL) then return end
        -- State is lean; if cooldowns or counts are also dirty, run them
        -- in the same tick to avoid a second OnUpdate wake-up.
        self:Hide()
        self._lastState = now
        self._dirtyStates = false
        ActionBarsOwned.UpdateAllButtonStates()
        if doCd and (not throttle or (now - self._lastCd >= AB_CD_UPDATE_INTERVAL)) then
            self._lastCd = now
            self._dirtyCooldowns = false
            ActionBarsOwned.UpdateAllCooldowns()
        end
        if doCount then
            self._lastCount = now
            self._dirtyCounts = false
            ActionBarsOwned.UpdateAllButtonCounts()
        end
    elseif doCd then
        if throttle and (now - self._lastCd < AB_CD_UPDATE_INTERVAL) then return end
        self:Hide()
        self._lastCd = now
        self._dirtyCooldowns = false
        ActionBarsOwned.UpdateAllCooldowns()
        -- Piggyback counts if dirty — same frame, avoid extra wake-up.
        if doCount then
            self._lastCount = now
            self._dirtyCounts = false
            ActionBarsOwned.UpdateAllButtonCounts()
        end
    elseif doCount then
        -- Counts are lightweight — no combat throttle needed, just
        -- once-per-frame dedup via _lastCountUpdateTime inside the fn.
        self:Hide()
        self._lastCount = now
        self._dirtyCounts = false
        ActionBarsOwned.UpdateAllButtonCounts()
    else
        self:Hide()
    end
end)

-- Profiler: split cooldown-path vs state-path vs visual-path work so we
-- can see which is hot. We wrap the update functions at the SetScript
-- handler level rather than the OnUpdate tick, so the measurement
-- reflects only the actual refresh cost (not throttled no-op ticks).
do
    local origAllCd    = ActionBarsOwned.UpdateAllCooldowns
    local origAllVis   = ActionBarsOwned.UpdateAllButtonVisuals
    local origAllState = ActionBarsOwned.UpdateAllButtonStates
    local cdProbeFrame    = CreateFrame("Frame")
    local visProbeFrame   = CreateFrame("Frame")
    local stateProbeFrame = CreateFrame("Frame")
    cdProbeFrame:SetScript("OnEvent",    function() origAllCd()    end)
    visProbeFrame:SetScript("OnEvent",   function() origAllVis()   end)
    stateProbeFrame:SetScript("OnEvent", function() origAllState() end)
    ActionBarsOwned.UpdateAllCooldowns     = function() cdProbeFrame:GetScript("OnEvent")()    end
    ActionBarsOwned.UpdateAllButtonVisuals = function() visProbeFrame:GetScript("OnEvent")()   end
    ActionBarsOwned.UpdateAllButtonStates  = function() stateProbeFrame:GetScript("OnEvent")() end
    ns.QUI_PerfRegistry = ns.QUI_PerfRegistry or {}
    ns.QUI_PerfRegistry[#ns.QUI_PerfRegistry + 1] = { name = "AB_Cooldowns", frame = cdProbeFrame,    scriptType = "OnEvent" }
    ns.QUI_PerfRegistry[#ns.QUI_PerfRegistry + 1] = { name = "AB_States",    frame = stateProbeFrame, scriptType = "OnEvent" }
    ns.QUI_PerfRegistry[#ns.QUI_PerfRegistry + 1] = { name = "AB_Visuals",   frame = visProbeFrame,   scriptType = "OnEvent" }
end

local function ScheduleABCooldownUpdate(immediate)
    abUpdateFrame._dirtyCooldowns = true
    if immediate then abUpdateFrame._immediate = true end
    abUpdateFrame:Show()
end

local function ScheduleABVisualUpdate(full, immediate)
    abUpdateFrame._dirtyVisuals = true
    if immediate then abUpdateFrame._immediate = true end
    if full then
        -- Mass action-table shuffles (shapeshift, vehicle swap, fresh world,
        -- spell learn/unlearn) need a full scan because the old _activeButtons
        -- set is stale — the same button handle may now point at a different
        -- action and some active→empty transitions aren't event-signalled.
        ActionBarsOwned.ForceFullVisualRescan()
    end
    abUpdateFrame:Show()
end

local function ScheduleABStateUpdate(immediate)
    abUpdateFrame._dirtyStates = true
    if immediate then abUpdateFrame._immediate = true end
    abUpdateFrame:Show()
end

local function ScheduleABCountUpdate()
    abUpdateFrame._dirtyCounts = true
    abUpdateFrame:Show()
end

-- ACTIONBAR_SLOT_CHANGED: only needed for drag/drop (specific slot > 0).
-- Slot 0 ("all changed") is ignored — already covered by SPELLS_CHANGED,
-- SafeSyncAction, PLAYER_ENTERING_WORLD, etc.
-- Specific slots during paging are also suppressed: UPDATE_SHAPESHIFT_FORM
-- and SafeSyncAction already handle those buttons.
local abDirtySlots = {}
local abSlotFrame = CreateFrame("Frame")
abSlotFrame:Hide()
local _lastPagingTime = 0

abSlotFrame:SetScript("OnUpdate", function(self)
    self:Hide()
    local slotMap = ActionBarsOwned.slotMap
    local inCombat = InCombatLockdown()
    for slot in pairs(abDirtySlots) do
        if slotMap then
            local entry = slotMap[slot]
            if entry then
                local btn, barKey = entry.button, entry.barKey
                pcall(ActionBarsOwned.SafeUpdate, btn)
                ActionBarsOwned.UpdateCooldown(btn)
                ActionBarsOwned.UpdateOverlayGlow(btn)
                -- Re-evaluate pressAndHoldAction for the new spell at
                -- this slot.  The `action` attribute is the slot index
                -- and hasn't changed, so the OnAttributeChanged wrap
                -- won't fire — we must update it from Lua here.
                -- SetAttribute on secure buttons is combat-blocked, so
                -- skip in combat (ACTIONBAR_SLOT_CHANGED content changes
                -- don't normally happen in combat anyway).
                if not inCombat and IsPressHoldReleaseSpell then
                    local actionType, id, subType = GetActionInfo(slot)
                    local pressAndHold = false
                    if actionType == "spell" then
                        pressAndHold = IsPressHoldReleaseSpell(id)
                    elseif actionType == "macro" and subType == "spell" then
                        pressAndHold = IsPressHoldReleaseSpell(id)
                    end
                    btn:SetAttribute("pressAndHoldAction", pressAndHold)
                    btn:SetAttribute("typerelease", "actionrelease")
                end
                if not inCombat then
                    local settings = GetEffectiveSettings(barKey)
                    if settings then
                        local st = GetFrameState(btn)
                        st.sk_sz = nil
                        SkinButton(btn, settings)
                        UpdateButtonText(btn, settings)
                        UpdateEmptySlotVisibility(btn, settings)
                    end
                end
            end
        end
    end
    wipe(abDirtySlots)
    -- Rebuild spell-to-button map after slot content changes (drag/drop)
    ActionBarsOwned.RebuildSpellIdMap()
    -- Slot contents changed — the rotation action may have moved to a
    -- different button.  Invalidate the cached rotation button so the
    -- next UpdateAllAssistedCombatRotation re-discovers it from the
    -- current recommendation.
    _assistRotationButton = nil
    -- Refresh assisted combat highlights and rotation frames.
    UpdateAllAssistedHighlights()
    ActionBarsOwned.UpdateAllAssistedCombatRotation()
end)

local function ScheduleSlotUpdate(slot)
    -- Ignore slot 0 (full refresh) — redundant with companion events
    if not slot or slot < 1 then return end
    -- Suppress during paging window (form changes, stealth, vehicle).
    -- UPDATE_SHAPESHIFT_FORM + SafeSyncAction already refresh these buttons.
    if GetTime() - _lastPagingTime < 0.5 then return end
    abDirtySlots[slot] = true
    abSlotFrame:Show()
end

local function OnOwnedEvent(self, event, ...)
    if not ActionBarsOwned.initialized then return end

    if event == "ACTIONBAR_SLOT_CHANGED" then
        -- Debounced: collect dirty slots, process in one batch after 50ms.
        -- Talent swaps fire 96 events, bar paging fires 12, zone transitions
        -- fire slot 0 — all coalesced into a single update pass.
        local slot = ...
        ScheduleSlotUpdate(slot)

    elseif event == "ACTIONBAR_PAGE_CHANGED"
        or event == "UPDATE_BONUS_ACTIONBAR"
        or event == "UPDATE_SHAPESHIFT_FORM"
        or event == "UPDATE_SHAPESHIFT_FORMS"
        or event == "UPDATE_STEALTH" then
        -- Mark paging window so ScheduleSlotUpdate suppresses the redundant
        -- ACTIONBAR_SLOT_CHANGED burst that Blizzard fires after paging.
        _lastPagingTime = GetTime()
        -- Page swap may remap which button holds the rotation action.
        _assistRotationButton = nil
        -- Paging is handled by state driver: _childupdate-offset sets the
        -- action attribute and calls CallMethod("SafeSyncAction") which
        -- syncs self.action and refreshes visuals on each button.
        -- Remaining work: empty slot visibility, cooldowns, proc glows,
        -- and bar1 bindings.
        local buttons = ActionBarsOwned.nativeButtons["bar1"]
        local settings = GetEffectiveSettings("bar1")
        if buttons and settings then
            for _, btn in ipairs(buttons) do
                UpdateEmptySlotVisibility(btn, settings)
            end
        end
        -- Refresh cooldowns and proc glows for the new page's actions
        if buttons then
            for _, btn in ipairs(buttons) do
                ActionBarsOwned.UpdateCooldown(btn)
                ActionBarsOwned.UpdateOverlayGlow(btn)
            end
        end
        -- Stance bar may need re-layout when shapeshift forms change
        if not InCombatLockdown() then
            UpdateStanceBarLayout()
        else
            ActionBarsOwned.pendingStanceUpdate = true
        end
        ApplyBar1OverrideBindings()

    elseif event == "UPDATE_SHAPESHIFT_COOLDOWN" or event == "UPDATE_SHAPESHIFT_USABLE" then
        -- Refresh stance button visuals (cooldowns, usability coloring)
        ActionBarsOwned.UpdateAllStanceButtons()

    elseif event == "UNIT_ENTERED_VEHICLE" or event == "UNIT_EXITED_VEHICLE" then
        local unit = ...
        if unit == "player" then
            ApplyBar1OverrideBindings()
            -- Blizzard may reclaim micro buttons during vehicle transitions
            if event == "UNIT_EXITED_VEHICLE" then
                C_Timer.After(0.2, function()
                    if not ActionBarsOwned.initialized then return end
                    if InCombatLockdown() then
                        ActionBarsOwned.pendingMicroReclaim = true
                        ActionBarsOwned.pendingBagsReclaim = true
                        return
                    end
                    ReclaimBarButtons("microbar")
                    ReclaimBarButtons("bags")
                end)
            end
        end

    elseif event == "UPDATE_BINDINGS" then
        C_Timer.After(0.1, RefreshNativeKeybinds)

    elseif event == "CURSOR_CHANGED" then
        local settings = GetGlobalSettings()
        if settings and settings.hideEmptySlots then
            local shouldPreview = CursorHasPlaceableAction()
            if shouldPreview ~= (ActionBarsOwned.dragPreviewActive or false) then
                ActionBarsOwned.dragPreviewActive = shouldPreview or nil
                for _, barKey in ipairs(STANDARD_BAR_KEYS) do
                    local buttons = ActionBarsOwned.nativeButtons[barKey]
                    if buttons then
                        local effSettings = GetEffectiveSettings(barKey)
                        if effSettings then
                            for _, btn in ipairs(buttons) do
                                UpdateEmptySlotVisibility(btn, effSettings)
                            end
                        end
                    end
                end
            end
        end

    elseif event == "PLAYER_REGEN_ENABLED" then
        if ActionBarsOwned.pendingExtraButtonInit then
            ActionBarsOwned.pendingExtraButtonInit = false
            InitializeExtraButtons()
        end
        if ActionBarsOwned.pendingExtraButtonRefresh then
            ActionBarsOwned.pendingExtraButtonRefresh = false
            RefreshExtraButtons()
        end
        if ActionBarsOwned.pendingRefresh then
            ActionBarsOwned.pendingRefresh = false
            ActionBarsOwned:Refresh()
        end
        if ActionBarsOwned.pendingUseOnKeyDownUpdate then
            ActionBarsOwned.pendingUseOnKeyDownUpdate = false
            if _G.QUI_ApplyUseOnKeyDown then _G.QUI_ApplyUseOnKeyDown() end
        end
        if ActionBarsOwned.pendingBindings then
            ActionBarsOwned.pendingBindings = false
            ApplyAllOverrideBindings()
        end
        if ActionBarsOwned.pendingPetUpdate then
            ActionBarsOwned.pendingPetUpdate = false
            UpdatePetBarVisibility()
        end
        if ActionBarsOwned.pendingStanceUpdate then
            ActionBarsOwned.pendingStanceUpdate = false
            UpdateStanceBarLayout()
        end
        if ActionBarsOwned.pendingMicroReclaim then
            ActionBarsOwned.pendingMicroReclaim = false
            ReclaimBarButtons("microbar")
        end
        if ActionBarsOwned.pendingBagsReclaim then
            ActionBarsOwned.pendingBagsReclaim = false
            ReclaimBarButtons("bags")
        end
        if ActionBarsOwned.pendingSpacing then
            ActionBarsOwned.pendingSpacing = false
            ApplyAllBarSpacing()
        end
        if ActionBarsOwned.pendingFlyoutDirection then
            ActionBarsOwned.pendingFlyoutDirection = false
            if ApplyAllFlyoutDirections then ApplyAllFlyoutDirections() end
        end
        -- SafeUpdate keeps all visuals live during combat (icon, cooldown,
        -- glow, usability, count, checked state).  Skinning state does not
        -- drift in combat, so no post-combat re-skin pass is needed.

    elseif event == "PET_BAR_UPDATE" or event == "PET_BAR_UPDATE_COOLDOWN" then
        -- PetActionBarMixin:Update on the suppressed bar won't fire, so QUI
        -- drives pet button visuals (icons, active state, autocast) directly.
        ActionBarsOwned.UpdateAllPetButtons()
        if not InCombatLockdown() then
            UpdatePetBarVisibility()
        else
            ActionBarsOwned.pendingPetUpdate = true
        end

    elseif event == "PET_UI_UPDATE" or event == "UNIT_PET" then
        local unit = ...
        if event == "UNIT_PET" and unit ~= "player" then return end
        -- Pet summoned/dismissed/swapped — update container visibility
        C_Timer.After(0.1, function()
            if not ActionBarsOwned.initialized then return end
            if InCombatLockdown() then
                ActionBarsOwned.pendingPetUpdate = true
                return
            end
            UpdatePetBarVisibility()
        end)

    elseif event == "PLAYER_ENTERING_WORLD" then
        local isLogin, isReload = ...
        -- Safe period: InCombatLockdown() is true during combat reload but
        -- protected calls are still allowed. Set the flag so all sub-functions
        -- bypass their combat guards.
        inInitSafeWindow = true
        -- Also set the namespace-level flag so the anchoring system can
        -- reposition bar containers during this safe window. During
        -- ADDON_LOADED the containers may not have existed yet, so the
        -- anchoring system resolved the Blizzard frames instead.
        ns._inInitSafeWindow = true
        if isReload then
            ApplyAllBarSpacing()
            -- Safety net: Blizzard's Layout() may fire after safe window
            -- closes. Mark pending so PLAYER_REGEN_ENABLED reapplies.
            ActionBarsOwned.pendingSpacing = true
        end
        -- Re-apply frame anchoring now that containers exist. The
        -- ADDON_LOADED pass may have missed them (created after the
        -- core init safe window closed).
        if ns.QUI_Anchoring and ns.QUI_Anchoring.ApplyAllFrameAnchors then
            ns.QUI_Anchoring:ApplyAllFrameAnchors(true)
        end
        -- Do layout immediately during the safe period so the UI is correct
        for _, barKey in ipairs(ALL_MANAGED_BAR_KEYS) do
            LayoutNativeButtons(barKey)
            RestoreContainerPosition(barKey)
        end
        RefreshAllNativeVisuals()
        ActionBarsOwned.UpdateAllButtonVisuals()
        ActionBarsOwned.UpdateAllCooldowns()
        UpdatePetBarVisibility()
        UpdateStanceBarLayout()
        ApplyAllFlyoutDirections()
        inInitSafeWindow = false
        ns._inInitSafeWindow = false
        -- Second pass after Blizzard frames settle; defer if safe period ended
        C_Timer.After(0.2, function()
            if InCombatLockdown() then
                ActionBarsOwned.pendingRefresh = true
                ActionBarsOwned.pendingPetUpdate = true
                ActionBarsOwned.pendingStanceUpdate = true
                return
            end
            for _, barKey in ipairs(ALL_MANAGED_BAR_KEYS) do
                LayoutNativeButtons(barKey)
                RestoreContainerPosition(barKey)
            end
            RefreshAllNativeVisuals()
            -- PEW covers zone/arena/BG entry — action set may differ,
            -- force a full scan so the active button set rebuilds.
            ActionBarsOwned.ForceFullVisualRescan()
            ActionBarsOwned.UpdateAllButtonVisuals()
            ActionBarsOwned.UpdateAllCooldowns()
            UpdatePetBarVisibility()
            UpdateStanceBarLayout()
            ApplyAllFlyoutDirections()
        end)
        local db = GetDB()
        if db and db.bars and db.bars.bar1 then
            C_Timer.After(0.1, function()
                ApplyPageArrowVisibility(db.bars.bar1.hidePageArrow)
            end)
            C_Timer.After(0.6, function()
                ApplyPageArrowVisibility(db.bars.bar1.hidePageArrow)
            end)
        end

    elseif event == "PLAYER_REGEN_DISABLED" then
        local fadeSettings = GetFadeSettings()
        if fadeSettings and fadeSettings.enabled and fadeSettings.alwaysShowInCombat then
            for _, barKey in ipairs(ALL_MANAGED_BAR_KEYS) do
                local state = GetOwnedBarFadeState(barKey)
                CancelOwnedBarFadeTimers(state)
                StartOwnedBarFade(barKey, 1)
            end
        end

    elseif event == "PLAYER_LEVEL_UP" then
        if UpdateLevelSuppressionState() then
            if type(_G.QUI_RefreshActionBars) == "function" then
                _G.QUI_RefreshActionBars()
            end
        end

    elseif event == "ACTIONBAR_UPDATE_COOLDOWN"
        or event == "LOSS_OF_CONTROL_ADDED"
        or event == "LOSS_OF_CONTROL_UPDATE" then
        -- Centralized cooldown update for all owned action buttons.
        -- Per-button OnEvent is suppressed (addon-created frames are
        -- tainted).  DurationObject path is secret-safe.
        -- Coalesced: fires 20+/sec in combat, throttled to ~30Hz.
        ScheduleABCooldownUpdate()

    elseif event == "ACTIONBAR_UPDATE_STATE" then
        -- Checked state only (autoattack, toggle abilities, current action).
        -- This event fires very frequently in combat — dispatch via the
        -- lean SetChecked-only pass instead of the full SafeUpdate chain.
        ScheduleABStateUpdate()

    elseif event == "SPELL_UPDATE_ICON" then
        -- Icon texture changed (rare — spell morphs, glyphs, etc).
        -- Needs full SafeUpdate to refresh the icon texture.
        -- Immediate: infrequent but visually jarring when delayed.
        ScheduleABVisualUpdate(false, true)

    elseif event == "MODIFIER_STATE_CHANGED" then
        -- Modifier pressed/released — macro conditionals like [mod:shift]
        -- may resolve to a different spell, changing the icon texture.
        -- Immediate: user expects instant visual feedback on key press.
        ScheduleABVisualUpdate(false, true)

    elseif event == "ACTIONBAR_UPDATE_USABLE" then
        -- Usability only — the dedicated usability overlay system handles
        -- tinting (range/mana/unusable).  No need for a full SafeUpdate
        -- which redundantly sets vertex colors on all 96 buttons.
        ScheduleUsabilityUpdate()

    elseif event == "SPELL_UPDATE_CHARGES" then
        -- Charge count changed (e.g. Arcane Charges, Chi).
        ScheduleABCountUpdate()

    elseif event == "UNIT_AURA" then
        -- Aura-based resource overlays (Soul Fragments, etc.) update
        -- the action display count when auras change.  Only react to
        -- player auras — party/target aura churn is irrelevant.
        local unit = ...
        if unit == "player" then
            ScheduleABCountUpdate()
        end

    elseif event == "ACTIONBAR_SHOWGRID" then
        -- Dragging from spellbook — show empty slot grid.
        -- Temporarily register ACTIONBAR_SLOT_CHANGED so we catch the
        -- specific slot the player drops onto.
        ActionBarsOwned._showGrid = true
        self:RegisterEvent("ACTIONBAR_SLOT_CHANGED")
        for _, barKey in ipairs(STANDARD_BAR_KEYS) do
            local btns = ActionBarsOwned.nativeButtons[barKey]
            if btns then
                for _, btn in ipairs(btns) do
                    btn:SetAlpha(1)
                end
            end
        end

    elseif event == "ACTIONBAR_HIDEGRID" then
        -- Drag ended — restore empty slot visibility and unregister
        -- ACTIONBAR_SLOT_CHANGED (fires constantly even while idle).
        ActionBarsOwned._showGrid = nil
        self:UnregisterEvent("ACTIONBAR_SLOT_CHANGED")
        -- Full post-drag refresh: the drag may have moved spells (including
        -- the one-button rotation action) between slots.  Some action types
        -- don't fire per-slot ACTIONBAR_SLOT_CHANGED, so we refresh
        -- everything here to guarantee correctness.  Force a full scan so
        -- newly-populated empty slots are caught immediately.
        ScheduleABVisualUpdate(true)
        ScheduleABCooldownUpdate()
        -- Assisted combat rotation and highlights must also refresh — the
        -- rotation action may have moved to a new button.
        ActionBarsOwned.UpdateAllAssistedCombatRotation()
        UpdateAllAssistedHighlights()
        -- Restore empty slot visibility (alpha was forced to 1 during grid)
        for _, barKey in ipairs(STANDARD_BAR_KEYS) do
            local buttons = ActionBarsOwned.nativeButtons[barKey]
            local settings = GetEffectiveSettings(barKey)
            if buttons and settings then
                for _, btn in ipairs(buttons) do
                    UpdateEmptySlotVisibility(btn, settings)
                end
            end
        end
        -- Rebuild spell-to-button map (slot contents may have changed)
        ActionBarsOwned.RebuildSpellIdMap()

    elseif event == "PLAYER_ENTER_COMBAT" or event == "PLAYER_LEAVE_COMBAT" then
        -- Auto-attack flash state changes (SafeUpdate handles flash now)
        -- Immediate: discrete one-shot events, not combat spam.
        ScheduleABVisualUpdate(false, true)

    elseif event == "START_AUTOREPEAT_SPELL" or event == "STOP_AUTOREPEAT_SPELL" then
        -- Auto-shot/wand toggle — refresh flash state on all buttons
        -- Immediate: discrete one-shot events.
        ScheduleABVisualUpdate(false, true)

    elseif event == "SPELLS_CHANGED"
        or event == "LEARNED_SPELL_IN_SKILL_LINE" then
        -- Talent swap, respec, new spell learned — full refresh of icons,
        -- usability, cooldowns, flyouts, and empty slot visibility.
        -- Coalesced: SPELLS_CHANGED fires more often than expected in 12.0+.
        ScheduleABVisualUpdate(true)  -- force full scan: action table reshuffled
        ScheduleABCooldownUpdate()
        ActionBarsOwned.UpdateAllOverlayGlows()
        -- Update flyout data on all buttons
        for _, barKey in ipairs(STANDARD_BAR_KEYS) do
            local btns = ActionBarsOwned.nativeButtons[barKey]
            if btns then
                for _, btn in ipairs(btns) do
                    if btn.UpdateFlyout then pcall(btn.UpdateFlyout, btn) end
                end
            end
        end
        ApplyAllFlyoutDirections()
        for _, barKey in ipairs(STANDARD_BAR_KEYS) do
            local btns = ActionBarsOwned.nativeButtons[barKey]
            local s = GetEffectiveSettings(barKey)
            if btns and s then
                for _, btn in ipairs(btns) do
                    UpdateEmptySlotVisibility(btn, s)
                end
            end
        end
        -- Zone/extra abilities may have changed — recapture frames.
        RefreshExtraButtons()

    elseif event == "SPELL_FLYOUT_UPDATE" then
        -- Flyout data changed — refresh flyout arrows on all buttons
        for _, barKey in ipairs(STANDARD_BAR_KEYS) do
            local btns = ActionBarsOwned.nativeButtons[barKey]
            if btns then
                for _, btn in ipairs(btns) do
                    if btn.UpdateFlyout then pcall(btn.UpdateFlyout, btn) end
                end
            end
        end
        ApplyAllFlyoutDirections()

    elseif event == "SPELL_UPDATE_USABLE" then
        -- Spell usability changed (e.g. resource gained/spent, GCD ended).
        -- Routed to the dedicated usability overlay system — avoids
        -- redundant full SafeUpdate on all 96 buttons just for tinting.
        ScheduleUsabilityUpdate()

    elseif event == "SPELL_ACTIVATION_OVERLAY_GLOW_SHOW" then
        local spellId = ...
        ActionBarsOwned.OnSpellActivationGlowShow(spellId)

    elseif event == "SPELL_ACTIVATION_OVERLAY_GLOW_HIDE" then
        local spellId = ...
        ActionBarsOwned.OnSpellActivationGlowHide(spellId)

    elseif event == "UPDATE_VEHICLE_ACTIONBAR" then
        -- Vehicle action bar data changed — full refresh (coalesced)
        ScheduleABVisualUpdate(true)  -- force full scan: vehicle swaps whole action set
        ScheduleABCooldownUpdate()
        ActionBarsOwned.UpdateAllOverlayGlows()
        ApplyBar1OverrideBindings()

    elseif event == "UPDATE_EXTRA_ACTIONBAR" then
        -- Extra action bar appeared/disappeared — recapture frames.
        RefreshExtraButtons()

    elseif event == "UNIT_INVENTORY_CHANGED" then
        -- Equipment changed — items on action bars may need icon/cooldown refresh
        local unit = ...
        if unit == "player" then
            ScheduleABVisualUpdate(true)  -- force full scan: item slots may have gained/lost actions
            ScheduleABCooldownUpdate()
        end

    elseif event == "PLAYER_MOUNT_DISPLAY_CHANGED" then
        -- Mount display changed — icon refresh for mount abilities
        ScheduleABVisualUpdate()

    elseif event == "PET_BATTLE_OPENING_START" then
        -- Clear all override bindings so the pet battle UI gets keys.
        -- Hide action bar containers (pet battle has its own UI).
        if not InCombatLockdown() then
            for _, barKey in ipairs(ALL_MANAGED_BAR_KEYS) do
                local cont = ActionBarsOwned.containers[barKey]
                if cont then
                    ClearOverrideBindings(cont)
                    cont:Hide()
                end
            end
        end

    elseif event == "PET_BATTLE_CLOSE" then
        -- Restore bars and bindings after pet battle ends
        if not InCombatLockdown() then
            for _, barKey in ipairs(ALL_MANAGED_BAR_KEYS) do
                local cont = ActionBarsOwned.containers[barKey]
                if cont then cont:Show() end
            end
            ApplyAllOverrideBindings()
            -- Restore pet/stance visibility (may have been hidden)
            UpdatePetBarVisibility()
            UpdateStanceBarLayout()
        else
            ActionBarsOwned.pendingBindings = true
            ActionBarsOwned.pendingRefresh = true
        end
    end
end

-- Event handler is set here; events are registered in Initialize().
ownedEventFrame:SetScript("OnEvent", OnOwnedEvent)

ns.QUI_PerfRegistry = ns.QUI_PerfRegistry or {}
ns.QUI_PerfRegistry[#ns.QUI_PerfRegistry + 1] = { name = "ActionBars", frame = ownedEventFrame }

---------------------------------------------------------------------------
-- EXTRA BUTTON CUSTOMIZATION (Extra Action Button & Zone Ability)
---------------------------------------------------------------------------
do

local extraBtnState = {
    extraActionHolder = nil,
    extraActionMover = nil,
    zoneAbilityHolder = nil,
    zoneAbilityMover = nil,
    moversVisible = false,
    hookingSetPoint = false,
    extraActionSetPointHooked = false,
    zoneAbilitySetPointHooked = false,
    hookingSetParent = false,
    extraActionSetParentHooked = false,
    zoneAbilitySetParentHooked = false,
    extraActionShowHooked = false,
    zoneAbilityShowHooked = false,
    pageArrowShowHooked = {},
    pageArrowRetryTimer = nil,
    pageArrowRetryAttempts = 0,
    PAGE_ARROW_RETRY_MAX_ATTEMPTS = 15,
    PAGE_ARROW_RETRY_DELAY = 0.2,
}

local function GetExtraButtonDB(buttonType)
    local core = GetCore()
    if not core or not core.db or not core.db.profile then return nil end
    return core.db.profile.actionBars and core.db.profile.actionBars.bars
        and core.db.profile.actionBars.bars[buttonType]
end

local function CreateExtraButtonNudgeButton(parent, direction, holder, buttonType)
    local btn = CreateFrame("Button", nil, parent)
    btn:SetSize(18, 18)
    btn:SetFrameStrata("HIGH")
    btn:SetFrameLevel(100)

    local bg = btn:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetTexture("Interface\\Buttons\\WHITE8x8")
    bg:SetVertexColor(0.1, 0.1, 0.1, 0.7)

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
        if holder.AdjustPointsOffset then
            holder:AdjustPointsOffset(dx, dy)
        else
            local point, relativeTo, relativePoint, xOfs, yOfs = holder:GetPoint(1)
            if point then
                holder:ClearAllPoints()
                holder:SetPoint(point, relativeTo, relativePoint, (xOfs or 0) + dx, (yOfs or 0) + dy)
            end
        end
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

local function CreateExtraButtonHolder(buttonType, displayName)
    local settings = GetExtraButtonDB(buttonType)
    if not settings then return nil, nil end

    local holder = CreateFrame("Frame", "QUI_" .. buttonType .. "Holder", UIParent)
    holder:SetSize(64, 64)
    holder:SetMovable(true)
    holder:SetClampedToScreen(true)

    local pos = settings.position
    if pos and pos.point then
        holder:SetPoint(pos.point, UIParent, pos.relPoint or pos.point, pos.x or 0, pos.y or 0)
    else
        if buttonType == "extraActionButton" then
            holder:SetPoint("CENTER", UIParent, "CENTER", -100, -200)
        else
            holder:SetPoint("CENTER", UIParent, "CENTER", 100, -200)
        end
    end

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
    mover:SetBackdropColor(0.2, 0.8, 0.6, 0.5)
    mover:SetBackdropBorderColor(0.376, 0.647, 0.980, 1)
    mover:EnableMouse(true)
    mover:SetMovable(true)
    mover:RegisterForDrag("LeftButton")
    mover:SetFrameStrata("HIGH")
    mover:Hide()

    local text = mover:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    text:SetPoint("CENTER")
    text:SetText(displayName)
    mover.text = text

    local nudgeUp = CreateExtraButtonNudgeButton(mover, "UP", holder, buttonType)
    nudgeUp:SetPoint("BOTTOM", mover, "TOP", 0, 4)
    local nudgeDown = CreateExtraButtonNudgeButton(mover, "DOWN", holder, buttonType)
    nudgeDown:SetPoint("TOP", mover, "BOTTOM", 0, -4)
    local nudgeLeft = CreateExtraButtonNudgeButton(mover, "LEFT", holder, buttonType)
    nudgeLeft:SetPoint("RIGHT", mover, "LEFT", -4, 0)
    local nudgeRight = CreateExtraButtonNudgeButton(mover, "RIGHT", holder, buttonType)
    nudgeRight:SetPoint("LEFT", mover, "RIGHT", 4, 0)

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

local extraButtonOriginalParents = {}


local function ApplyExtraButtonSettings(buttonType)
    if InCombatLockdown() and not inInitSafeWindow then
        ActionBarsOwned.pendingExtraButtonRefresh = true
        return
    end

    local settings = GetExtraButtonDB(buttonType)
    if not settings or not settings.enabled then return end

    local blizzFrame
    local holder

    if buttonType == "extraActionButton" then
        blizzFrame = ExtraActionBarFrame
        holder = extraBtnState.extraActionHolder
    else
        blizzFrame = ZoneAbilityFrame
        holder = extraBtnState.zoneAbilityHolder
    end

    if not blizzFrame or not holder then return end

    local scale = settings.scale or 1.0
    blizzFrame:SetScale(scale)

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
    -- Deregister from the managed-container's layout chain BEFORE reparenting,
    -- otherwise the container still iterates this frame during Layout passes
    -- (e.g. cinematic start), runs our hooks, and taints the container's
    -- SetSize call — ADDON_ACTION_BLOCKED on UIParentRightManagedFrameContainer.
    local currentParent = blizzFrame:GetParent()
    if currentParent and currentParent.RemoveManagedFrame then
        pcall(currentParent.RemoveManagedFrame, currentParent, blizzFrame)
    end
    blizzFrame.ignoreFramePositionManager = true
    extraBtnState.hookingSetParent = true
    blizzFrame:SetParent(holder)
    extraBtnState.hookingSetParent = false
    extraBtnState.hookingSetPoint = true
    blizzFrame:ClearAllPoints()
    blizzFrame:SetPoint("CENTER", holder, "CENTER", offsetX, offsetY)
    extraBtnState.hookingSetPoint = false

    local width = Helpers.SafeToNumber(blizzFrame:GetWidth(), 64) * scale
    local height = Helpers.SafeToNumber(blizzFrame:GetHeight(), 64) * scale
    holder:SetSize(math.max(width, 64), math.max(height, 64))

    if settings.hideArtwork then
        if buttonType == "extraActionButton" and blizzFrame.button and blizzFrame.button.style then
            blizzFrame.button.style:SetAlpha(0)
        end
        if buttonType == "zoneAbility" and blizzFrame.Style then
            blizzFrame.Style:SetAlpha(0)
        end
    else
        if buttonType == "extraActionButton" and blizzFrame.button and blizzFrame.button.style then
            blizzFrame.button.style:SetAlpha(1)
        end
        if buttonType == "zoneAbility" and blizzFrame.Style then
            blizzFrame.Style:SetAlpha(1)
        end
    end

    if not settings.fadeEnabled then
        blizzFrame:SetAlpha(1)
    end
end

local pendingExtraButtonReanchor = {}

local function QueueExtraButtonReanchor(buttonType)
    if pendingExtraButtonReanchor[buttonType] then return end
    pendingExtraButtonReanchor[buttonType] = true

    C_Timer.After(0, function()
        pendingExtraButtonReanchor[buttonType] = false

        if InCombatLockdown() then
            ActionBarsOwned.pendingExtraButtonRefresh = true
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
    if ExtraActionBarFrame and not extraBtnState.extraActionSetPointHooked then
        extraBtnState.extraActionSetPointHooked = true
        hooksecurefunc(ExtraActionBarFrame, "SetPoint", function(self)
            if extraBtnState.hookingSetPoint then return end
            C_Timer.After(0, function()
                if extraBtnState.hookingSetPoint or InCombatLockdown() then return end
                local settings = GetExtraButtonDB("extraActionButton")
                if extraBtnState.extraActionHolder and settings and settings.enabled then
                    QueueExtraButtonReanchor("extraActionButton")
                end
            end)
        end)
    end

    if ZoneAbilityFrame and not extraBtnState.zoneAbilitySetPointHooked then
        extraBtnState.zoneAbilitySetPointHooked = true
        hooksecurefunc(ZoneAbilityFrame, "SetPoint", function(self)
            if extraBtnState.hookingSetPoint then return end
            C_Timer.After(0, function()
                if extraBtnState.hookingSetPoint or InCombatLockdown() then return end
                local settings = GetExtraButtonDB("zoneAbility")
                if extraBtnState.zoneAbilityHolder and settings and settings.enabled then
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
            if extraBtnState.hookingSetParent then return end
            if newParent == holder then return end
            C_Timer.After(0, function()
                if extraBtnState.hookingSetParent or InCombatLockdown() then return end
                local settings = GetExtraButtonDB(buttonType)
                if holder and settings and settings.enabled then
                    extraBtnState.hookingSetParent = true
                    blizzFrame:SetParent(holder)
                    extraBtnState.hookingSetParent = false
                    QueueExtraButtonReanchor(buttonType)
                end
            end)
        end)
    end
    if ExtraActionBarFrame and not extraBtnState.extraActionSetParentHooked then
        extraBtnState.extraActionSetParentHooked = true
        HookSetParentForType(ExtraActionBarFrame, "extraActionButton", extraBtnState.extraActionHolder)
    end
    if ZoneAbilityFrame and not extraBtnState.zoneAbilitySetParentHooked then
        extraBtnState.zoneAbilitySetParentHooked = true
        HookSetParentForType(ZoneAbilityFrame, "zoneAbility", extraBtnState.zoneAbilityHolder)
    end

    -- Hook Show to recapture frames when Blizzard makes them visible
    -- (e.g., zone ability appearing upon entering a new zone).
    if ExtraActionBarFrame and not extraBtnState.extraActionShowHooked then
        extraBtnState.extraActionShowHooked = true
        hooksecurefunc(ExtraActionBarFrame, "Show", function()
            QueueExtraButtonReanchor("extraActionButton")
        end)
    end
    if ZoneAbilityFrame and not extraBtnState.zoneAbilityShowHooked then
        extraBtnState.zoneAbilityShowHooked = true
        hooksecurefunc(ZoneAbilityFrame, "Show", function()
            QueueExtraButtonReanchor("zoneAbility")
        end)
    end
end

local function ShowExtraButtonMovers()
    extraBtnState.moversVisible = true
    if extraBtnState.extraActionMover then extraBtnState.extraActionMover:Show() end
    if extraBtnState.zoneAbilityMover then extraBtnState.zoneAbilityMover:Show() end
end

local function HideExtraButtonMovers()
    extraBtnState.moversVisible = false
    if extraBtnState.extraActionMover then extraBtnState.extraActionMover:Hide() end
    if extraBtnState.zoneAbilityMover then extraBtnState.zoneAbilityMover:Hide() end
end

local function ToggleExtraButtonMovers()
    if extraBtnState.moversVisible then
        HideExtraButtonMovers()
    else
        ShowExtraButtonMovers()
    end
end

-- Assign to upvalue for forward declaration in event handler
InitializeExtraButtons = function()
    if InCombatLockdown() and not inInitSafeWindow then
        ActionBarsOwned.pendingExtraButtonInit = true
        return
    end

    extraBtnState.extraActionHolder, extraBtnState.extraActionMover = CreateExtraButtonHolder("extraActionButton", "Extra Action Button")
    extraBtnState.zoneAbilityHolder, extraBtnState.zoneAbilityMover = CreateExtraButtonHolder("zoneAbility", "Zone Ability")

    C_Timer.After(0.5, function()
        ApplyExtraButtonSettings("extraActionButton")
        ApplyExtraButtonSettings("zoneAbility")
        HookExtraButtonPositioning()
        -- If the frame anchoring system manages these frames, let it
        -- reposition the holders now that they exist.
        local ApplyAnchor = _G.QUI_ApplyFrameAnchor
        if ApplyAnchor then
            if _G.QUI_HasFrameAnchor and _G.QUI_HasFrameAnchor("extraActionButton") then
                ApplyAnchor("extraActionButton")
            end
            if _G.QUI_HasFrameAnchor and _G.QUI_HasFrameAnchor("zoneAbility") then
                ApplyAnchor("zoneAbility")
            end
        end
    end)
end

-- Assign to upvalue for forward declaration in event handler
RefreshExtraButtons = function()
    if InCombatLockdown() and not inInitSafeWindow then
        ActionBarsOwned.pendingExtraButtonRefresh = true
        return
    end
    ApplyExtraButtonSettings("extraActionButton")
    ApplyExtraButtonSettings("zoneAbility")
    -- Set up hooks on any newly available frames (handles late-loaded
    -- frames like ZoneAbilityFrame that may not exist at init time).
    HookExtraButtonPositioning()
end

_G.QUI_ToggleExtraButtonMovers = ToggleExtraButtonMovers
_G.QUI_RefreshExtraButtons = RefreshExtraButtons
ActionBarsOwned.extraBtnState = extraBtnState

end -- do (extra buttons)

---------------------------------------------------------------------------
-- BUTTON SKINNING
---------------------------------------------------------------------------
do -- button skinning / usability / bar spacing

-- Get the icon texture from a button, handling stance/pet buttons
-- that use NormalTexture as the icon source.
-- Returns: icon texture, iconUsesNormalTexture (bool)
local function GetButtonIconTexture(button)
    -- Standard action buttons use .icon or .Icon
    local icon = button.icon or button.Icon
    if icon then return icon, false end

    -- Stance/pet buttons may use NormalTexture as the icon
    local normalTex = button:GetNormalTexture()
    if normalTex then
        return normalTex, true
    end

    return nil, false
end

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

    -- Neutralize IconMask to prevent Blizzard's UpdateButtonArt from
    -- re-adding it during combat transitions and bar paging.
    if button.IconMask then
        button.IconMask:Hide()
        button.IconMask:SetTexture(nil)
        button.IconMask:ClearAllPoints()
        button.IconMask:SetSize(0.001, 0.001)
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

    -- Replace Blizzard's highlight, pushed, checked, and flash textures
    -- with QUI versions that are properly sized via SetAllPoints.
    local function ReplaceTexture(tex, texturePath)
        if not tex then return end
        tex:SetAtlas(nil)
        tex:SetTexture(texturePath)
        tex:SetTexCoord(0, 1, 0, 1)
        tex:ClearAllPoints()
        tex:SetAllPoints(button)
        tex:SetAlpha(1)
    end

    local highlight = button:GetHighlightTexture()
    if highlight then ReplaceTexture(highlight, TEXTURES.highlight) end
    if button.HighlightTexture and button.HighlightTexture ~= highlight then
        ReplaceTexture(button.HighlightTexture, TEXTURES.highlight)
    end

    local pushed = button:GetPushedTexture()
    if pushed then ReplaceTexture(pushed, TEXTURES.pushed) end
    if button.PushedTexture and button.PushedTexture ~= pushed then
        ReplaceTexture(button.PushedTexture, TEXTURES.pushed)
    end

    local checked = button.GetCheckedTexture and button:GetCheckedTexture()
    if checked then ReplaceTexture(checked, TEXTURES.checked) end
    if button.CheckedTexture and button.CheckedTexture ~= checked then
        ReplaceTexture(button.CheckedTexture, TEXTURES.checked)
    end

    -- Replace flash texture
    if button.Flash then
        ReplaceTexture(button.Flash, TEXTURES.flash)
    end

    -- Hide border/shadow decorations
    if button.Border then button.Border:SetAlpha(0) end
    if button.BorderShadow then button.BorderShadow:SetAlpha(0) end

    -- SpellHighlightTexture: anchor to button so it matches our size
    if button.SpellHighlightTexture then
        button.SpellHighlightTexture:ClearAllPoints()
        button.SpellHighlightTexture:SetAllPoints(button)
    end

    -- Cooldown: anchor to button so it fills correctly
    local cd = button.cooldown or button.Cooldown
    if cd then
        cd:ClearAllPoints()
        cd:SetAllPoints(button)
    end

    -- No overlay scaling needed — buttons stay at their natural 45x45 size
    -- and the container's SetScale handles visual resize. Blizzard overlays
    -- (SpellActivationAlert, proc glows, rotation assist) work naturally
    -- because the button dimensions match what overlays expect.
end

---------------------------------------------------------------------------
-- BUTTON SKINNING
---------------------------------------------------------------------------

local FadeHideEffects
local FadeShowEffects
local SkinSpellFlyoutButtons
local PROC_ALERT_REGION_KEYS = {
    "ProcStartFlipbook",
    "ProcLoopFlipbook",
}

local function SuppressProcVisualFrame(frame)
    if not frame then return end

    pcall(function()
        if frame.Hide then
            frame:Hide()
        end
        if frame.SetAlpha then
            frame:SetAlpha(0)
        end
        if frame.StopAnimating then
            frame:StopAnimating()
        end
    end)

    if frame.Show then
        Helpers.DeferredHideOnShow(frame, { clearAlpha = true, combatCheck = false })
    end
end

local function SuppressButtonProcVisuals(button)
    if not button then return end

    pcall(function()
        local alert = button.SpellActivationAlert
        if alert then
            SuppressProcVisualFrame(alert)

            for _, regionKey in ipairs(PROC_ALERT_REGION_KEYS) do
                SuppressProcVisualFrame(alert[regionKey])
            end
        end
    end)

    pcall(function()
        SuppressProcVisualFrame(button.OverlayGlow)
    end)

    pcall(function()
        SuppressProcVisualFrame(button._ButtonGlow)
    end)
end

UpdateButtonProfessionQuality = function(button, settings)
    if not button then return end

    local overlay = button.ProfessionQualityOverlayTexture
    if settings == nil then
        local db = GetDB()
        settings = db and db.global
    end
    if settings and settings.showProfessionQuality == false then
        if overlay then
            overlay:Hide()
        end
        return
    end

    local action = GetSafeActionSlot(button)
    if not action or not (C_ActionBar and C_ActionBar.GetProfessionQualityInfo) then
        if overlay then
            overlay:Hide()
        end
        return
    end

    local ok, qualityInfo = pcall(C_ActionBar.GetProfessionQualityInfo, action)
    local atlas = ok and qualityInfo and qualityInfo.iconInventory
    if not atlas then
        if overlay then
            overlay:Hide()
        end
        return
    end

    if not overlay then
        overlay = button:CreateTexture(nil, "OVERLAY", nil, 7)
        overlay:SetPoint("CENTER", button, "TOPLEFT", 14, -14)
        overlay:SetDrawLayer("OVERLAY", 7)
        button.ProfessionQualityOverlayTexture = overlay
    end

    overlay:SetAtlas(
        atlas,
        TextureKitConstants and TextureKitConstants.UseAtlasSize or true
    )
    overlay:Show()
end

-- Apply QUI skin to a single button
SkinButton = function(button, settings)
    if not button or not settings then
        return
    end

    UpdateButtonProfessionQuality(button, settings)

    if not settings.skinEnabled then
        return
    end
    local state = GetFrameState(button)

    -- Skip if already skinned with same settings (direct field comparison,
    -- avoids string.format allocation on every call)
    local _sz = settings.iconSize or 36
    local _zm = settings.iconZoom or 0.07
    local _bd = settings.showBackdrop
    local _ba = settings.backdropAlpha or 0.8
    local _gl = settings.showGloss
    local _ga = settings.glossAlpha or 0.6
    local _br = settings.showBorders
    local _fl = settings.showFlash
    if state.sk_sz == _sz and state.sk_zm == _zm
        and state.sk_bd == _bd and state.sk_ba == _ba
        and state.sk_gl == _gl and state.sk_ga == _ga
        and state.sk_br == _br and state.sk_fl == _fl then
        return
    end
    state.sk_sz = _sz; state.sk_zm = _zm
    state.sk_bd = _bd; state.sk_ba = _ba
    state.sk_gl = _gl; state.sk_ga = _ga
    state.sk_br = _br; state.sk_fl = _fl

    -- Save original Blizzard pushed texture before stripping (for restore)
    if not state.origPushedTex then
        local p = button:GetPushedTexture()
        if p then
            state.origPushedTex = p:GetTexture()
            state.origPushedAtlas = p:GetAtlas()
        end
    end

    -- Strip Blizzard artwork first
    StripBlizzardArtwork(button)
    SuppressButtonProcVisuals(button)

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
        local action = GetSafeActionSlot(button)
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

    -- Button-press pushed texture (the visual on keydown/click).
    -- showFlash: "qui" = QUI texture, "blizzard" = original, "off"/false = hidden
    -- Backwards compat: true → "qui", false → "off"
    local flashMode = settings.showFlash
    if flashMode == true then flashMode = "qui"
    elseif flashMode == false then flashMode = "off"
    end

    local function ApplyPushedMode(tex)
        if not tex then return end
        if flashMode == "off" then
            tex:SetAtlas(nil)
            tex:SetTexture(nil)
        elseif flashMode == "blizzard" then
            if state.origPushedAtlas then
                tex:SetTexture(nil)
                tex:SetAtlas(state.origPushedAtlas)
            elseif state.origPushedTex then
                tex:SetAtlas(nil)
                tex:SetTexture(state.origPushedTex)
                tex:SetTexCoord(0, 1, 0, 1)
            end
            -- Blizzard's pushed atlas has asymmetric padding (more on the
            -- right/bottom). Extend BOTTOMRIGHT to compensate.
            tex:ClearAllPoints()
            tex:SetPoint("TOPLEFT", button, "TOPLEFT")
            tex:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", 4, -4)
        else -- "qui" (default)
            tex:SetAtlas(nil)
            tex:SetTexture(TEXTURES.pushed)
            tex:SetTexCoord(0, 1, 0, 1)
        end
    end

    ApplyPushedMode(button:GetPushedTexture())
    if button.PushedTexture and button.PushedTexture ~= button:GetPushedTexture() then
        ApplyPushedMode(button.PushedTexture)
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

    ActionBarsOwned.skinnedButtons[button] = true

    -- PERF: Per-button UpdateButtonArt hook.
    -- Fires only when Blizzard resets button artwork (combat transitions,
    -- paging, bonus bar swaps) — much less frequent than ActionButton_Update.
    -- Cached closure avoids allocation per hook fire.
    if button.UpdateButtonArt and not button._quiArtHooked then
        local cachedSkinFn = function()
            if button:IsForbidden() then return end
            local bk = GetBarKeyFromButton(button)
            if bk then
                local s = GetEffectiveSettings(bk)
                if s then
                    -- Clear skin cache to force re-apply after Blizzard reset
                    local st = GetFrameState(button)
                    st.sk_sz = nil
                    SkinButton(button, s)
                end
            end
        end
        hooksecurefunc(button, "UpdateButtonArt", function()
            C_Timer.After(0, cachedSkinFn)
        end)
        button._quiArtHooked = true
    end
end

---------------------------------------------------------------------------
-- TEXT VISIBILITY
---------------------------------------------------------------------------

-- Update keybind/hotkey text visibility and styling
-- Directly modifies Blizzard's HotKey element with abbreviated text
UpdateKeybindText = function(button, settings)
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

        -- QUI fresh buttons (bar1-8)
        if not bindingName then
            num = buttonName:match("^QUI_Bar1Button(%d+)$")
            if num then bindingName = "ACTIONBUTTON" .. num end
        end
        if not bindingName then
            num = buttonName:match("^QUI_Bar2Button(%d+)$")
            if num then bindingName = "MULTIACTIONBAR1BUTTON" .. num end
        end
        if not bindingName then
            num = buttonName:match("^QUI_Bar3Button(%d+)$")
            if num then bindingName = "MULTIACTIONBAR2BUTTON" .. num end
        end
        if not bindingName then
            num = buttonName:match("^QUI_Bar4Button(%d+)$")
            if num then bindingName = "MULTIACTIONBAR3BUTTON" .. num end
        end
        if not bindingName then
            num = buttonName:match("^QUI_Bar5Button(%d+)$")
            if num then bindingName = "MULTIACTIONBAR4BUTTON" .. num end
        end
        if not bindingName then
            num = buttonName:match("^QUI_Bar6Button(%d+)$")
            if num then bindingName = "MULTIACTIONBAR5BUTTON" .. num end
        end
        if not bindingName then
            num = buttonName:match("^QUI_Bar7Button(%d+)$")
            if num then bindingName = "MULTIACTIONBAR6BUTTON" .. num end
        end
        if not bindingName then
            num = buttonName:match("^QUI_Bar8Button(%d+)$")
            if num then bindingName = "MULTIACTIONBAR7BUTTON" .. num end
        end
        if not bindingName then
            num = buttonName:match("^QUI_PetButton(%d+)$")
            if num then bindingName = "BONUSACTIONBUTTON" .. num end
        end
        if not bindingName then
            num = buttonName:match("^QUI_StanceButton(%d+)$")
            if num then bindingName = "SHAPESHIFTBUTTON" .. num end
        end

        -- Blizzard button names (fallback for reparented buttons)
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
        local action = GetSafeActionSlot(button)
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

    -- Match text justification to anchor direction (Blizzard defaults to RIGHT justify)
    if anchor:find("LEFT") then
        hotkey:SetJustifyH("LEFT")
    elseif anchor:find("RIGHT") then
        hotkey:SetJustifyH("RIGHT")
    else
        hotkey:SetJustifyH("CENTER")
    end

    hotkey:SetWidth(0)
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
UpdateButtonText = function(button, settings)
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

    SuppressButtonProcVisuals(button)
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
    SuppressButtonProcVisuals(button)
end

-- Hide QUI textures on a button, saving which were visible for later restore.
FadeHideTextures = function(state, button)
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
FadeShowTextures = function(state, button)
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


-- Drag preview: show hidden empty slots at low alpha while cursor holds a placeable action
local DRAG_PREVIEW_ALPHA = 0.3

-- Update empty slot visibility for a single button
UpdateEmptySlotVisibility = function(button, settings)
    if not settings then return end
    local state = GetFrameState(button)

    local barKey = GetBarKeyFromButton(button)

    -- Stance/pet buttons are not standard action slots and can report action
    -- data that does not map cleanly to HasAction(). Never apply hide-empty
    -- logic to them.
    -- Button-level alpha handles only empty-slot hiding.  The mouseover
    -- fade effect is applied on the *container*, so buttons should be at
    -- alpha 1 when they have content.  Using the container's currentAlpha
    -- here would leave buttons stuck at 0 after a fade-in because
    -- SetOwnedBarAlpha only animates the container, not individual buttons.

    if barKey == "stance" or barKey == "pet" then
        if state.hiddenEmpty then
            state.hiddenEmpty = nil
            FadeShowTextures(state, button)
        end
        button:SetAlpha(1)
        return
    end

    if not settings.hideEmptySlots then
        -- Restore visibility if setting is off
        if state.hiddenEmpty then
            button:SetAlpha(1)
            state.hiddenEmpty = nil
            FadeShowTextures(state, button)
        end
        return
    end

    -- Only applies to action buttons with action property
    local action = GetSafeActionSlot(button)
    if action then
        local hasAction = SafeHasAction(action)
        if hasAction then
            button:SetAlpha(1)
            if state.hiddenEmpty then
                state.hiddenEmpty = nil
                FadeShowTextures(state, button)
            end
        else
            -- Show at preview alpha while dragging a placeable action
            if ActionBarsOwned.dragPreviewActive then
                button:SetAlpha(DRAG_PREVIEW_ALPHA)
            else
                button:SetAlpha(0)
            end
            if not state.hiddenEmpty then
                state.hiddenEmpty = true
                FadeHideTextures(state, button)
            end
        end
    else
        button:SetAlpha(1)
        if state.hiddenEmpty then
            state.hiddenEmpty = nil
            FadeShowTextures(state, button)
        end
    end
end


-- Usability indicator state tracking
-- PERF: Relaxed from 250ms/100ms to 500ms.  State-change gating in
-- UpdateButtonUsability means visual updates only happen when the tint
-- actually changes, so polling less often has no visible impact.
local usabilityState = {
    checkFrame = nil,
    INTERVAL_COMBAT = 0.5,   -- 500ms in combat
    INTERVAL_IDLE = 2.0,     -- 2s OOC (range matters less)
    inCombat = false,
    updatePending = false,
}

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
    local state = GetFrameState(button)
    local action = GetSafeActionSlot(button)

    -- Skip buttons that are effectively invisible (faded bar or hidden empty
    -- slot).  MOD-blend textures ignore parent alpha inheritance and will
    -- darken the scene behind them even when the button is at alpha 0.
    if state.fadeHidden or state.hiddenEmpty then
        return
    end

    if not action or not SafeHasAction(action) then
        if state.tinted then
            if state.tintOverlay then state.tintOverlay:Hide() end
            state.tinted = nil
        end
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

    -- Compute new tint state BEFORE applying visuals — skip overlay
    -- updates when state hasn't changed.
    local newTint = nil  -- nil = normal/no tint

    -- Priority 1: Out of Range check (if enabled)
    if settings.rangeIndicator then
        local inRange = SafeIsActionInRange(action)
        if inRange == false then  -- false = out of range, nil = no range check needed
            newTint = "range"
        end
    end

    -- Priority 2: Usability check (if enabled, and not already range-tinted)
    if not newTint and settings.usabilityIndicator then
        local isUsable, notEnoughMana = SafeIsUsableAction(action)
        if notEnoughMana then
            newTint = "mana"
        elseif not isUsable then
            newTint = "unusable"
        end
    end

    -- State-change gate: skip overlay work if tint state unchanged
    if state.tinted == newTint then return end

    -- Apply the new tint state
    if newTint == "range" then
        local overlay = GetTintOverlay(button)
        if overlay then
            local c = settings.rangeColor
            overlay:SetColorTexture(c and c[1] or 0.8, c and c[2] or 0.1, c and c[3] or 0.1, c and c[4] or 1)
            overlay:Show()
        end
        state.tinted = "range"
    elseif newTint == "mana" then
        local overlay = GetTintOverlay(button)
        if overlay then
            local c = settings.manaColor
            overlay:SetColorTexture(c and c[1] or 0.5, c and c[2] or 0.5, c and c[3] or 1.0, c and c[4] or 1)
            overlay:Show()
        end
        state.tinted = "mana"
    elseif newTint == "unusable" then
        local overlay = GetTintOverlay(button)
        if overlay then
            local c = settings.usabilityColor
            overlay:SetColorTexture(c and c[1] or 0.4, c and c[2] or 0.4, c and c[3] or 0.4, c and c[4] or 1)
            overlay:Show()
        end
        state.tinted = "unusable"
    else
        -- Normal state - hide overlay
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
        local fadeState = ActionBarsOwned.fadeState and ActionBarsOwned.fadeState[barKey]
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
ScheduleUsabilityUpdate = function()
    if usabilityState.updatePending then return end
    usabilityState.updatePending = true
    C_Timer.After(0.05, function()
        usabilityState.updatePending = false
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
    if not usabilityState.checkFrame then
        usabilityState.checkFrame = CreateFrame("Frame")
        usabilityState.checkFrame.elapsed = 0
    end

    local checkFrame = usabilityState.checkFrame

    -- Event-driven usability updates (very efficient)
    -- ACTIONBAR_UPDATE_USABLE and SPELL_UPDATE_USABLE are handled by
    -- OnOwnedEvent → ScheduleUsabilityUpdate() directly, so they are
    -- NOT registered here (avoids double dispatch).
    if usabilityEnabled or rangeEnabled then
        checkFrame:RegisterEvent("SPELL_UPDATE_CHARGES")
        checkFrame:RegisterUnitEvent("UNIT_POWER_UPDATE", "player")
        checkFrame:RegisterEvent("PLAYER_TARGET_CHANGED")
        checkFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
        checkFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
        checkFrame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
        checkFrame:RegisterEvent("ZONE_CHANGED_INDOORS")

        checkFrame:SetScript("OnEvent", function(self, event, ...)
            if event == "PLAYER_REGEN_DISABLED" then
                usabilityState.inCombat = true
                self.elapsed = 0  -- reset so combat interval kicks in immediately
                return
            elseif event == "PLAYER_REGEN_ENABLED" then
                usabilityState.inCombat = false
                ScheduleUsabilityUpdate()  -- one-shot refresh after combat
                return
            end
            ScheduleUsabilityUpdate()
        end)

        -- Initial update
        ScheduleUsabilityUpdate()
    else
        checkFrame:UnregisterAllEvents()
        checkFrame:SetScript("OnEvent", nil)
    end

    -- Range requires polling (no "player moved" event exists).
    -- PERF: Relaxed to 500ms combat / 2s OOC.  State-change gating in
    -- UpdateButtonUsability skips overlay work when tint is unchanged,
    -- so less frequent polling has no visible impact.
    if rangeEnabled then
        checkFrame:SetScript("OnUpdate", function(self, elapsed)
            self.elapsed = self.elapsed + elapsed
            local interval = usabilityState.inCombat and usabilityState.INTERVAL_COMBAT or usabilityState.INTERVAL_IDLE
            if self.elapsed < interval then return end
            self.elapsed = 0
            UpdateAllButtonUsability()
        end)
        checkFrame:Show()
    else
        checkFrame:SetScript("OnUpdate", nil)
        checkFrame.elapsed = 0
        -- Don't hide - events still need to work if usability is enabled
        if not usabilityEnabled then
            checkFrame:Hide()
            ResetAllButtonTints()
        end
    end
end

---------------------------------------------------------------------------
-- BUTTON SPACING OVERRIDE
---------------------------------------------------------------------------

-- Detect how many columns a bar has by comparing button Y positions.
-- Buttons in the same row share a similar top edge; a new row drops down.
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
    if InCombatLockdown() and not inInitSafeWindow then
        ActionBarsOwned.pendingSpacing = true
        return
    end

    local settings = GetGlobalSettings()
    if not settings or settings.buttonSpacing == nil then return end

    local spacing = settings.buttonSpacing
    -- Only apply spacing to standard action bars (1-8) that DON'T use the
    -- owned layout system. Owned bars use LayoutNativeButtons instead.
    -- Pet/stance bars have variable visible button counts per class
    -- and resizing their bar frames breaks the frame anchoring chain
    -- (size-stable CENTER anchoring shifts visual content on resize).
    if barKey == "pet" or barKey == "stance" then return end
    local ownedLayout = ActionBarsOwned.containers and ActionBarsOwned.containers[barKey]
    if ownedLayout then return end

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

-- Apply spacing override to all standard bars.
ApplyAllBarSpacing = function()
    if InCombatLockdown() and not inInitSafeWindow then
        ActionBarsOwned.pendingSpacing = true
        return
    end

    for barKey, _ in pairs(BUTTON_PATTERNS) do
        ApplyButtonSpacing(barKey)
    end
end

-- Apply the user's flyoutDirection setting to each button on a standard bar.
-- "AUTO" clears the attribute so Blizzard's position-based auto-detect runs.
-- Writing secure attributes on tainted addon buttons during combat causes
-- taint, so defer to PLAYER_REGEN_ENABLED when locked down.
local VALID_FLYOUT_DIRS = { UP = true, DOWN = true, LEFT = true, RIGHT = true }

ApplyFlyoutDirection = function(barKey)
    local buttons = ActionBarsOwned.nativeButtons and ActionBarsOwned.nativeButtons[barKey]
    if not buttons or #buttons == 0 then return end

    local db = GetDB()
    local barDB = db and db.bars and db.bars[barKey]
    local layout = barDB and barDB.ownedLayout
    if not layout then return end

    if InCombatLockdown() then
        ActionBarsOwned.pendingFlyoutDirection = true
        return
    end

    local dir = layout.flyoutDirection
    if not VALID_FLYOUT_DIRS[dir] then dir = nil end -- AUTO / unset

    for _, btn in ipairs(buttons) do
        if btn and btn.SetAttribute then
            btn:SetAttribute("flyoutDirection", dir)
            -- Explicitly sync popup direction: UpdateFlyout only calls
            -- SetPopupDirection when the value is non-nil, so switching
            -- back to AUTO would leave the old direction stuck.
            if btn.SetPopupDirection then btn:SetPopupDirection(dir) end
            if btn.UpdateFlyout then pcall(btn.UpdateFlyout, btn) end
        end
    end
end

ApplyAllFlyoutDirections = function()
    for _, barKey in ipairs(STANDARD_BAR_KEYS) do
        ApplyFlyoutDirection(barKey)
    end
end

ActionBarsOwned.SuppressButtonProcVisuals = SuppressButtonProcVisuals
ActionBarsOwned.UpdateUsabilityPolling = UpdateUsabilityPolling
ActionBarsOwned.DRAG_PREVIEW_ALPHA = DRAG_PREVIEW_ALPHA

end -- do (button skinning / usability / bar spacing)

---------------------------------------------------------------------------
-- MOUSEOVER FADE SYSTEM
---------------------------------------------------------------------------

-- During Edit Mode, fade-outs are suspended so all bars remain visible.
local IsInEditMode = ns.Helpers.IsEditModeShown

-- Get or create fade state for a bar
local function GetBarFadeState(barKey)
    if not ActionBarsOwned.fadeState[barKey] then
        ActionBarsOwned.fadeState[barKey] = {
            isFading = false,
            currentAlpha = 1,
            targetAlpha = 1,
            fadeStart = 0,
            fadeStartAlpha = 1,
            fadeDuration = 0.3,
            isMouseOver = false,
            delayTimer = nil,
            leaveCheckTimer = nil,
        }
    end
    return ActionBarsOwned.fadeState[barKey]
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
            button:SetAlpha(ActionBarsOwned.dragPreviewActive and (ActionBarsOwned.DRAG_PREVIEW_ALPHA * alpha) or 0)
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
    if not ActionBarsOwned.fadeFrame then
        ActionBarsOwned.fadeFrame = CreateFrame("Frame")
        ActionBarsOwned.fadeFrame:SetScript("OnUpdate", function(self, elapsed)
            local now = GetTime()
            local anyFading = false

            for bKey, bState in pairs(ActionBarsOwned.fadeState) do
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
        ActionBarsOwned.fadeFrameUpdate = ActionBarsOwned.fadeFrame:GetScript("OnUpdate")
    end
    ActionBarsOwned.fadeFrame:SetScript("OnUpdate", ActionBarsOwned.fadeFrameUpdate)
    ActionBarsOwned.fadeFrame:Show()
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

-- Mouseover fade subsystem.  Wrapped in do...end to reclaim local variable
-- slots (file has >200 locals without this, hitting Lua's MAXLOCALS limit).
-- Entry points are exposed on ActionBarsOwned at the end of the block.
do

local function IsMouseOverAnyLinkedBar()
    for _, barKey in ipairs(STANDARD_BAR_KEYS) do
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

local function RefreshBarsForSpellBookVisibility()
    if not ActionBarsOwned.initialized then return end

    local forceShow = ShouldForceShowForSpellBook()

    -- Owned bars (bar1-8, pet, stance) use the owned fade system.
    -- Non-owned bars (extraActionButton, zoneAbility) use the bar fade system.
    for barKey, _ in pairs(BAR_FRAMES) do
        if SKINNABLE_BAR_KEYS[barKey] then
            -- Owned bar → owned fade system (container-level alpha)
            local state = GetOwnedBarFadeState(barKey)
            state.isFading = false
            CancelOwnedBarFadeTimers(state)
            if forceShow then
                SetOwnedBarAlpha(barKey, 1)
            else
                SetupOwnedBarMouseover(barKey)
            end
        else
            -- Non-owned bar → bar fade system (per-button alpha)
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

local function EnsureSpellBookVisibilityHooks()
    HookSpellBookVisibilityFrame(_G.SpellBookFrame)

    local playerSpellsFrame = _G.PlayerSpellsFrame
    HookSpellBookVisibilityFrame(playerSpellsFrame)
    if playerSpellsFrame and playerSpellsFrame.SpellBookFrame then
        HookSpellBookVisibilityFrame(playerSpellsFrame.SpellBookFrame)
    end
end

local function ScheduleSpellBookVisibilityRefresh()
    if not ActionBarsOwned.initialized then return end

    local function Refresh()
        if not ActionBarsOwned.initialized then return end
        EnsureSpellBookVisibilityHooks()
        RefreshBarsForSpellBookVisibility()
    end

    -- PlayerSpellsFrame and its spellbook tab can be created or shown a tick
    -- after the toggle function runs, so recheck briefly to catch first-open.
    Refresh()
    C_Timer.After(0, Refresh)
    C_Timer.After(SPELL_UI_FADE_RECHECK_DELAY, Refresh)
end

local function HookSpellBookToggleFunction(functionName)
    local fn = _G[functionName]
    if type(fn) ~= "function" then return end

    local hooked = ActionBarsOwned.spellBookToggleHooks
    if not hooked then
        hooked = {}
        ActionBarsOwned.spellBookToggleHooks = hooked
    end
    if hooked[functionName] then return end

    hooked[functionName] = true
    hooksecurefunc(functionName, ScheduleSpellBookVisibilityRefresh)
end

local SPELLBOOK_UI_ADDONS = {
    Blizzard_PlayerSpells = true,
    Blizzard_SpellBook = true,
}

local function HandleSpellBookAddonLoaded(addonName)
    if not SPELLBOOK_UI_ADDONS[addonName] then return end

    C_Timer.After(0, function()
        if not ActionBarsOwned.initialized then return end
        ScheduleSpellBookVisibilityRefresh()
    end)
end

-- Expose entry points from the mouseover fade do...end block
ActionBarsOwned.SetupBarMouseover = SetupBarMouseover
ActionBarsOwned.RefreshBarsForSpellBookVisibility = RefreshBarsForSpellBookVisibility
ActionBarsOwned.HookSpellBookVisibilityFrame = HookSpellBookVisibilityFrame
ActionBarsOwned.EnsureSpellBookVisibilityHooks = EnsureSpellBookVisibilityHooks
ActionBarsOwned.ScheduleSpellBookVisibilityRefresh = ScheduleSpellBookVisibilityRefresh
ActionBarsOwned.HookSpellBookToggleFunction = HookSpellBookToggleFunction
ActionBarsOwned.HandleSpellBookAddonLoaded = HandleSpellBookAddonLoaded

end -- do (mouseover fade subsystem)


---------------------------------------------------------------------------
-- COMBAT VISIBILITY HANDLER
---------------------------------------------------------------------------

-- Combat event handler for "always show in combat" feature
-- Only applies to main action bars (1-8), not microbar, bags, pet, stance
local COMBAT_FADE_BARS = {
    bar1 = true, bar2 = true, bar3 = true, bar4 = true,
    bar5 = true, bar6 = true, bar7 = true, bar8 = true,
}

-- Combat-leave fade resume.  REGEN_DISABLED is already handled by the
-- main OnOwnedEvent handler (line ~3081).  This frame only resumes
-- mouseover fade behaviour when combat ends.
local combatFadeFrame = CreateFrame("Frame")
combatFadeFrame:RegisterEvent("PLAYER_REGEN_ENABLED")

combatFadeFrame:SetScript("OnEvent", function(self, event)
    local fadeSettings = GetFadeSettings()
    if not fadeSettings or not fadeSettings.enabled then return end
    if not fadeSettings.alwaysShowInCombat then return end
    if ShouldSuppressMouseoverHideForLevel() then return end

    for barKey, _ in pairs(COMBAT_FADE_BARS) do
        SetupOwnedBarMouseover(barKey)
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
                ActionBarsOwned.SuppressButtonProcVisuals(self)
                local key = GetBarKeyFromButton(self)
                local fadeState = key and ActionBarsOwned.fadeState and ActionBarsOwned.fadeState[key]
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

do -- spell flyout skinning

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
        local nChildren = select('#', flyout:GetChildren())
        for i = 1, nChildren do
            local child = select(i, flyout:GetChildren())
            AddButton(child)
            if child and child.GetChildren then
                local nGrand = select('#', child:GetChildren())
                for j = 1, nGrand do
                    local grandChild = select(j, child:GetChildren())
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

    local rawW, rawH = sourceButton:GetSize()
    local width = Helpers.SafeToNumber(rawW)
    local height = Helpers.SafeToNumber(rawH)
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

ActionBarsOwned.HookSpellFlyoutSkinning = HookSpellFlyoutSkinning

end -- do (spell flyout skinning)

---------------------------------------------------------------------------
-- PAGE ARROW VISIBILITY
---------------------------------------------------------------------------
do

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

local function SchedulePageArrowVisibilityRetry()
    local ebs = ActionBarsOwned.extraBtnState
    if ebs.pageArrowRetryTimer or ebs.pageArrowRetryAttempts >= ebs.PAGE_ARROW_RETRY_MAX_ATTEMPTS then return end
    ebs.pageArrowRetryAttempts = ebs.pageArrowRetryAttempts + 1
    ebs.pageArrowRetryTimer = C_Timer.NewTimer(ebs.PAGE_ARROW_RETRY_DELAY, function()
        ebs.pageArrowRetryTimer = nil
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

    local ebs = ActionBarsOwned.extraBtnState
    ebs.pageArrowRetryAttempts = 0
    if ebs.pageArrowRetryTimer then
        ebs.pageArrowRetryTimer:Cancel()
        ebs.pageArrowRetryTimer = nil
    end

    if hide then
        for _, frame in ipairs(frames) do
            frame:Hide()
            if not ebs.pageArrowShowHooked[frame] then
                ebs.pageArrowShowHooked[frame] = true
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

end -- do (page arrow visibility)

---------------------------------------------------------------------------
-- PUBLIC API
---------------------------------------------------------------------------

function ActionBarsOwned:Initialize()
    if self.initialized then return end

    -- Master enabled check — skip all bar creation if the module is disabled,
    -- letting Blizzard's default action bars remain untouched.
    local masterDB = GetDB()
    if masterDB and masterDB.enabled == false then return end

    self.initialized = true

    -- Patch LibKeyBound Binder methods to work with unified frameState
    PatchLibKeyBoundForMidnight()

    -- Re-register events
    -- ACTIONBAR_SLOT_CHANGED not registered here — only registered during
    -- drag operations (ACTIONBAR_SHOWGRID).  Blizzard fires slot 0 constantly
    -- even while idle, and all non-drag scenarios are already covered by
    -- SPELLS_CHANGED, SafeSyncAction, UPDATE_SHAPESHIFT_FORM, etc.
    ownedEventFrame:RegisterEvent("ACTIONBAR_PAGE_CHANGED")
    ownedEventFrame:RegisterEvent("UPDATE_BONUS_ACTIONBAR")
    ownedEventFrame:RegisterEvent("UPDATE_SHAPESHIFT_FORM")
    ownedEventFrame:RegisterEvent("UPDATE_SHAPESHIFT_FORMS")
    ownedEventFrame:RegisterEvent("UPDATE_SHAPESHIFT_COOLDOWN")
    ownedEventFrame:RegisterEvent("UPDATE_SHAPESHIFT_USABLE")
    ownedEventFrame:RegisterEvent("UPDATE_STEALTH")
    ownedEventFrame:RegisterEvent("UPDATE_BINDINGS")
    ownedEventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
    ownedEventFrame:RegisterEvent("CURSOR_CHANGED")
    ownedEventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    ownedEventFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
    ownedEventFrame:RegisterEvent("PLAYER_LEVEL_UP")
    ownedEventFrame:RegisterEvent("UNIT_ENTERED_VEHICLE")
    ownedEventFrame:RegisterEvent("UNIT_EXITED_VEHICLE")
    ownedEventFrame:RegisterEvent("UPDATE_EXTRA_ACTIONBAR")
    ownedEventFrame:RegisterEvent("ACTIONBAR_UPDATE_COOLDOWN")
    ownedEventFrame:RegisterEvent("ACTIONBAR_UPDATE_USABLE")
    ownedEventFrame:RegisterEvent("ACTIONBAR_UPDATE_STATE")
    ownedEventFrame:RegisterEvent("ACTIONBAR_SHOWGRID")
    ownedEventFrame:RegisterEvent("ACTIONBAR_HIDEGRID")
    ownedEventFrame:RegisterEvent("SPELL_UPDATE_CHARGES")
    ownedEventFrame:RegisterUnitEvent("UNIT_AURA", "player")
    ownedEventFrame:RegisterEvent("SPELL_UPDATE_ICON")
    ownedEventFrame:RegisterEvent("MODIFIER_STATE_CHANGED")
    ownedEventFrame:RegisterEvent("PLAYER_ENTER_COMBAT")
    ownedEventFrame:RegisterEvent("PLAYER_LEAVE_COMBAT")
    ownedEventFrame:RegisterEvent("PET_BATTLE_OPENING_START")
    ownedEventFrame:RegisterEvent("PET_BATTLE_CLOSE")
    ownedEventFrame:RegisterEvent("LOSS_OF_CONTROL_ADDED")
    ownedEventFrame:RegisterEvent("LOSS_OF_CONTROL_UPDATE")
    -- Spell activation overlay glow (proc abilities)
    ownedEventFrame:RegisterEvent("SPELL_ACTIVATION_OVERLAY_GLOW_SHOW")
    ownedEventFrame:RegisterEvent("SPELL_ACTIVATION_OVERLAY_GLOW_HIDE")
    -- Events that QUI handles centrally — per-button events are
    -- unregistered on QUI-created buttons.
    ownedEventFrame:RegisterEvent("SPELLS_CHANGED")
    ownedEventFrame:RegisterEvent("SPELL_UPDATE_USABLE")
    ownedEventFrame:RegisterEvent("SPELL_FLYOUT_UPDATE")
    ownedEventFrame:RegisterEvent("UPDATE_VEHICLE_ACTIONBAR")
    ownedEventFrame:RegisterEvent("UNIT_INVENTORY_CHANGED")
    ownedEventFrame:RegisterEvent("PLAYER_MOUNT_DISPLAY_CHANGED")
    ownedEventFrame:RegisterEvent("START_AUTOREPEAT_SPELL")
    ownedEventFrame:RegisterEvent("STOP_AUTOREPEAT_SPELL")
    if IS_MIDNIGHT then
        ownedEventFrame:RegisterEvent("LEARNED_SPELL_IN_SKILL_LINE")
    end
    ownedEventFrame:Show()

    -- Force all action bars enabled so owned buttons function correctly
    C_CVar.SetCVar("SHOW_MULTI_ACTIONBAR_1", "1")
    C_CVar.SetCVar("SHOW_MULTI_ACTIONBAR_2", "1")
    C_CVar.SetCVar("SHOW_MULTI_ACTIONBAR_3", "1")
    C_CVar.SetCVar("SHOW_MULTI_ACTIONBAR_4", "1")

    -- Build all managed bars (1-8 + pet/stance)
    for _, barKey in ipairs(ALL_MANAGED_BAR_KEYS) do
        BuildBar(barKey)
    end

    -- Let Blizzard's OverrideActionBar display natively during vehicle /
    -- override / possess states.  QUI's bar1 is hidden during those states
    -- by a secure visibility state driver (see HideBar1DuringOverride
    -- below), so there's no visual conflict.  Keybinds pass through to
    -- Blizzard's native override bar because ApplyBarOverrideBindings bails
    -- for bar1 when IsVehicleBarActive() is true, leaving the default
    -- ACTIONBUTTON1..6 -> OverrideActionBarButton1..6 remap intact.
    --
    -- We still clean isShownExternal on OverrideActionBar to prevent
    -- Edit Mode from writing a tainted show flag that could propagate
    -- through ActionBarController on re-show.
    local overrideBar = _G.OverrideActionBar
    if overrideBar and overrideBar.system then
        overrideBar.isShownExternal = nil
        local c = 42
        repeat
            if overrideBar[c] == nil then
                overrideBar[c] = nil
            end
            c = c + 1
        until issecurevariable(overrideBar, "isShownExternal")
    end

    -- Suppress PossessActionBar (mind control bar) — can overlap QUI bars
    local possessBar = _G.PossessActionBar or _G.PossessBarFrame
    if possessBar then
        possessBar:UnregisterAllEvents()
        possessBar:SetParent(hiddenBarParent)
        possessBar:Hide()
    end

    -- Suppress NPE (New Player Experience) tutorials that reference
    -- original Blizzard action buttons.  Without this, the tutorial
    -- system tries to find ActionButton1 etc. which are suppressed.
    if _G.AddSpellToActionBar then
        _G.AddSpellToActionBar = noop
    end
    if _G.AddClassSpellToActionBar then
        _G.AddClassSpellToActionBar = noop
    end
    -- Enable the auto-push watcher so spells still go to bars
    if _G.AutoPushSpellWatcher and _G.AutoPushSpellWatcher.Start then
        pcall(_G.AutoPushSpellWatcher.Start, _G.AutoPushSpellWatcher)
    end

    -- Clear override bindings when entering player housing (housing has
    -- its own keybinds).  Restore when leaving.
    if EventRegistry and EventRegistry.RegisterCallback then
        EventRegistry:RegisterCallback("HouseEditor.StateUpdated", function(_, state)
            if InCombatLockdown() then
                if not state then
                    ActionBarsOwned.pendingBindings = true
                end
                return
            end
            if state then
                ActionBarsOwned._inHousing = true
                for _, barKey in ipairs(ALL_MANAGED_BAR_KEYS) do
                    local cont = ActionBarsOwned.containers[barKey]
                    if cont then ClearOverrideBindings(cont) end
                end
            else
                ActionBarsOwned._inHousing = nil
                ApplyAllOverrideBindings()
            end
        end, "QUI_ActionBars")
    end

    -- Register pet/stance-specific events
    ownedEventFrame:RegisterEvent("PET_BAR_UPDATE")
    ownedEventFrame:RegisterEvent("PET_BAR_UPDATE_COOLDOWN")
    ownedEventFrame:RegisterEvent("PET_UI_UPDATE")
    ownedEventFrame:RegisterEvent("UNIT_PET")

    -- Update pet bar visibility based on current pet state
    UpdatePetBarVisibility()
    UpdateStanceBarLayout()

    -- Blizzard bars are fully disposed (hidden + events unregistered).
    -- QUI creates fresh buttons with SetOverrideBindingClick for keybinds.

    -- Spellbook hover highlight — show which action bar button has a spell
    -- when hovering that spell in the spellbook.
    if _G.UpdateOnBarHighlightMarksBySpell then
        hooksecurefunc("UpdateOnBarHighlightMarksBySpell", function(spellID)
            ActionBarsOwned.spellHighlight.type = "spell"
            ActionBarsOwned.spellHighlight.id = tonumber(spellID)
        end)
    end
    if _G.UpdateOnBarHighlightMarksByFlyout then
        hooksecurefunc("UpdateOnBarHighlightMarksByFlyout", function(flyoutID)
            ActionBarsOwned.spellHighlight.type = "flyout"
            ActionBarsOwned.spellHighlight.id = tonumber(flyoutID)
        end)
    end
    if _G.ClearOnBarHighlightMarks then
        hooksecurefunc("ClearOnBarHighlightMarks", function()
            ActionBarsOwned.spellHighlight.type = nil
            ActionBarsOwned.spellHighlight.id = nil
        end)
    end
    if _G.ActionBarController_UpdateAllSpellHighlights then
        hooksecurefunc("ActionBarController_UpdateAllSpellHighlights", ActionBarsOwned.UpdateAllSpellHighlights)
    end

    -- Assisted combat rotation (one-button rotation arrow overlay).
    if EventRegistry and EventRegistry.RegisterCallback then
        EventRegistry:RegisterCallback("AssistedCombatManager.OnSetActionSpell", function()
            local okSpell, newSpell = pcall(C_AssistedCombat.GetNextCastSpell, false)
            if not okSpell then newSpell = nil end
            -- Dedupe: Blizzard fires this every OnUpdate frame under soft
            -- targeting; if the rotation spell hasn't actually changed,
            -- skip entirely.
            if newSpell == ActionBarsOwned._lastAssistRotationSpell then return end
            ActionBarsOwned._lastAssistRotationSpell = newSpell
            if newSpell then ActionBarsOwned._assistedCombatEverActive = true end
            ActionBarsOwned.UpdateAllAssistedCombatRotation()
            -- The rotation button's icon needs to update too — SafeUpdate
            -- overrides the arrow texture with the recommended spell.
            -- Immediate flush: spell changes are low-frequency.
            ScheduleABVisualUpdate(false, true)
            -- Notify other modules that consume the rotation recommendation.
            -- Centralized here so they react to the same event instead of
            -- polling GetNextCastSpell on independent timers.
            local rai = ns.RotationAssistIcon
            if rai and rai.Update then pcall(rai.Update) end
            local kb = ns.Keybinds
            if kb and kb.UpdateAllRotationHelpers then pcall(kb.UpdateAllRotationHelpers) end
        end, "QUI_ActionBars_AssistedCombat")

        -- Assisted combat highlight (marching ants on the next-cast button).
        -- Process immediately in the callback — no dirty-flag deferral.
        -- Soft targeting causes constant nil→spell→nil→spell oscillation.
        -- Nil means "no recommendation right now" (target lost, soft-target
        -- gap) — NOT "rotation disabled".  Ignore nil to avoid flicker.
        -- Highlights refresh on HIDEGRID or PLAYER_REGEN_ENABLED.
        EventRegistry:RegisterCallback("AssistedCombatManager.OnAssistedHighlightSpellChange", function()
            local okHL, nextSpell = pcall(C_AssistedCombat.GetNextCastSpell, false)
            if not okHL then nextSpell = nil end
            if not nextSpell then return end
            if nextSpell == ActionBarsOwned._lastAssistHighlightSpell then return end
            ActionBarsOwned._lastAssistHighlightSpell = nextSpell
            UpdateAllAssistedHighlights()
        end, "QUI_ActionBars_AssistedHighlight")
    end

    -- Direct hook on AssistedCombatManager — works even when no assisted
    -- combat button is on any action bar.  The EventRegistry events above
    -- don't reliably fire, and SafeUpdate notifications only work when
    -- a button IS on a bar.  This hook catches all spell changes at the
    -- source and notifies the rotation assist icon + CDM viewer overlay.
    if AssistedCombatManager and AssistedCombatManager.UpdateAllAssistedHighlightFramesForSpell then
        hooksecurefunc(AssistedCombatManager, "UpdateAllAssistedHighlightFramesForSpell", function(_, spellID)
            if not spellID then return end
            local Helpers = ns.Helpers
            local isSecret = Helpers and Helpers.IsSecretValue(spellID)

            -- Resolve the talent-transformed display spell.  Blizzard may
            -- recommend a base spell ID while talents have replaced it with
            -- an override (or vice versa).  Resolve both directions so
            -- downstream matching works regardless of which ID the API returns.
            local resolvedID = spellID
            if not isSecret then
                -- Forward: base → current override (e.g., Thunder Clap → Thunder Blast)
                local okOvr, overrideID = pcall(C_Spell.GetOverrideSpell, spellID)
                if okOvr and overrideID and overrideID ~= spellID then
                    resolvedID = overrideID
                end
            end

            -- ForceUpdateAction → SafeUpdate races the C-side texture write:
            -- SafeUpdate reads GetActionTexture before the new value is
            -- committed, showing the PREVIOUS spell icon.  This hook fires
            -- AFTER the C-side completes, so schedule an immediate visual
            -- refresh to re-read the now-correct texture.
            ScheduleABVisualUpdate(false, true)
            -- Rotation assist icon handles secret values natively via C-side
            -- functions — pass the raw spellID so it works during combat.
            local rai = ns.RotationAssistIcon
            if rai and rai.Update then pcall(rai.Update, spellID) end
            -- Pass both the resolved override and the original base so the
            -- matcher can check either direction.  Secret values pass through
            -- safely — tonumber() returns nil for secrets, so no match = no
            -- overlay, no crash.
            local kb = ns.Keybinds
            if kb and kb.UpdateAllRotationHelpers then
                pcall(kb.UpdateAllRotationHelpers, resolvedID, spellID)
            end
        end)
    end

    -- No overlay scaling hooks needed — buttons stay at their natural 45x45
    -- size and the container's SetScale handles visual resize. Blizzard overlays
    -- work naturally because button dimensions match what they expect.

    -- Hook ActionButton_Update to refresh text/visibility (but NOT force re-skin).
    -- PERF: Removed skinKey = nil force-reset — the field-comparison dedup in
    -- SkinButton handles this naturally without string.format overhead.
    -- Actual artwork re-skinning is handled by per-button UpdateButtonArt hooks
    -- installed during BuildBar (fires less often, deferred via C_Timer).
    if ActionButton_Update then
        hooksecurefunc("ActionButton_Update", function(button)
            if InCombatLockdown() then return end
            if not ActionBarsOwned.skinnedButtons[button] then return end
            local bk = GetBarKeyFromButton(button)
            if not bk then return end
            local s = GetEffectiveSettings(bk)
            if s then
                SkinButton(button, s)
                UpdateButtonText(button, s)
                UpdateEmptySlotVisibility(button, s)
            end
        end)
    end

    -- Setup usability polling
    ActionBarsOwned.UpdateUsabilityPolling()

    -- Register Edit Mode callbacks
    local core = GetCore()
    if core and core.RegisterEditModeEnter then
        core:RegisterEditModeEnter(OnEditModeEnter)
        core:RegisterEditModeExit(OnEditModeExit)
    end

    -- Hook tooltip suppression for QUI action bar buttons.
    -- PERF: This fires on EVERY tooltip in the game.  Fast-exit via cached
    -- setting + O(1) skinnedButtons lookup instead of DB walk + string match.
    ActionBarsOwned._suppressTooltips = false
    function ActionBarsOwned:RefreshTooltipSuppressCache()
        local global = GetGlobalSettings()
        self._suppressTooltips = global and global.showTooltips == false
    end
    ActionBarsOwned:RefreshTooltipSuppressCache()

    hooksecurefunc("GameTooltip_SetDefaultAnchor", function(tooltip, parent)
        if not ActionBarsOwned._suppressTooltips then return end
        if not parent or not ActionBarsOwned.skinnedButtons[parent] then return end
        tooltip:Hide()
        tooltip:SetOwner(UIParent, "ANCHOR_NONE")
        tooltip:ClearLines()
    end)

    -- Hook spellbook visibility for the mouseover fade system. The player
    -- spells UI can be created lazily, so we also hook its toggle functions
    -- and retry once the panel is actually opening.
    ActionBarsOwned.EnsureSpellBookVisibilityHooks()
    ActionBarsOwned.HookSpellBookToggleFunction("ToggleSpellBook")
    ActionBarsOwned.HookSpellBookToggleFunction("TogglePlayerSpellsFrame")
    ActionBarsOwned.ScheduleSpellBookVisibilityRefresh()

    -- Initialize extra buttons
    inInitSafeWindow = true
    InitializeExtraButtons()
    inInitSafeWindow = false

    -- Apply page arrow visibility
    local db = GetDB()
    if db and db.bars and db.bars.bar1 then
        ApplyPageArrowVisibility(db.bars.bar1.hidePageArrow)
    end

    -- Hide bars that are disabled in DB
    for _, barKey in ipairs(ALL_MANAGED_BAR_KEYS) do
        local barDB = GetBarSettings(barKey)
        if barDB and barDB.enabled == false then
            local container = self.containers[barKey]
            if container then
                container:SetAttribute("qui-user-shown", false)
                container:Hide()
            end
        end
    end
end

function ActionBarsOwned:Refresh()
    if not self.initialized then return end

    if InCombatLockdown() then
        self.pendingRefresh = true
        return
    end

    for _, barKey in ipairs(ALL_MANAGED_BAR_KEYS) do
        BuildBar(barKey)
    end

    -- Patch LibKeyBound Binder methods to work without method injection on Midnight
    PatchLibKeyBoundForMidnight()

    -- Hook tooltip suppression for action buttons (once only — hooksecurefunc is permanent)
    -- NOTE: Synchronous — deferring causes tooltip flash before hide.
    if not ActionBarsOwned._refreshHooksInstalled then
        ActionBarsOwned._refreshHooksInstalled = true
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

        if type(ActionButton_ShowOverlayGlow) == "function" then
            hooksecurefunc("ActionButton_ShowOverlayGlow", function(button)
                if ActionBarsOwned.skinnedButtons[button] then
                    ActionBarsOwned.SuppressButtonProcVisuals(button)
                end
            end)
        end
    end

    -- Initial skin pass
    for _, barKey in ipairs(ALL_MANAGED_BAR_KEYS) do
        SkinBar(barKey)
    end
    ActionBarsOwned.HookSpellFlyoutSkinning()

    -- Apply bar layout settings (spacing, empty slot visibility)
    ApplyAllBarSpacing()
    ApplyAllFlyoutDirections()

    -- Hide bars that are disabled in DB
    for _, barKey in ipairs(ALL_MANAGED_BAR_KEYS) do
        local barDB = GetBarSettings(barKey)
        if barDB and barDB.enabled == false then
            local container = self.containers[barKey]
            if container then
                container:SetAttribute("qui-user-shown", false)
                container:Hide()
            end
        end
    end

    -- Refresh pet/stance conditional visibility
    UpdatePetBarVisibility()
    UpdateStanceBarLayout()

    ActionBarsOwned.UpdateUsabilityPolling()
    if self.RefreshTooltipSuppressCache then self:RefreshTooltipSuppressCache() end
end


---------------------------------------------------------------------------
-- GLOBAL REFRESH FUNCTION
---------------------------------------------------------------------------

_G.QUI_RefreshActionBars = function()
    if InCombatLockdown() then
        ActionBarsOwned.pendingRefresh = true
        return
    end
    ActionBarsOwned:Refresh()
end

-- Apply the `useOnKeyDown` profile setting to all QUI action bar
-- buttons. SetAttribute on a secure frame is protected during combat,
-- so defer to PLAYER_REGEN_ENABLED when locked down. Empowered spells
-- are unaffected — pressAndHoldAction + typerelease="actionrelease"
-- handle the press/release flow independently of this attribute.
_G.QUI_ApplyUseOnKeyDown = function()
    if InCombatLockdown() then
        ActionBarsOwned.pendingUseOnKeyDownUpdate = true
        return
    end
    local db = GetDB()
    local value = db and db.global and db.global.useOnKeyDown == true
    for bar = 1, 8 do
        for i = 1, 12 do
            local btn = _G["QUI_Bar" .. bar .. "Button" .. i]
            if btn then
                btn:SetAttribute("useOnKeyDown", value)
            end
        end
    end
end

-- Lightweight refresh: only re-evaluate mouseover fade state for all bars.
-- Used by fade/alwaysShow settings that don't need a full bar rebuild.
_G.QUI_RefreshActionBarFade = function()
    if not ActionBarsOwned.initialized then return end
    for _, barKey in ipairs(ALL_MANAGED_BAR_KEYS) do
        local state = GetOwnedBarFadeState(barKey)
        state.isFading = false
        CancelOwnedBarFadeTimers(state)
        SetupOwnedBarMouseover(barKey)
    end
end

---------------------------------------------------------------------------
-- INITIALIZATION
---------------------------------------------------------------------------

local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("ADDON_LOADED")
initFrame:SetScript("OnEvent", function(self, event, addonName)
    if addonName == ADDON_NAME then
        local db = GetDB()
        if not db or not db.enabled then return end
        ActionBarsOwned:Initialize()
    elseif addonName == "Blizzard_ActionBar" then
        ActionBarsOwned.HookSpellFlyoutSkinning()
        C_Timer.After(0, SkinSpellFlyoutButtons)
        local db = GetDB()
        if db and db.bars and db.bars.bar1 then
            C_Timer.After(0, function()
                ApplyPageArrowVisibility(db.bars.bar1.hidePageArrow)
            end)
        end
        -- OverrideActionBar is intentionally left visible so Blizzard can
        -- display vehicle/override abilities natively; QUI bar1 hides
        -- during those states via its qui_overridevisibility state driver.
        -- Clean isShownExternal here (Blizzard_ActionBar may have just
        -- created it) so Edit Mode writes don't taint ActionBarController.
        local overrideBar = _G.OverrideActionBar
        if overrideBar and overrideBar.system then
            overrideBar.isShownExternal = nil
            local c = 42
            repeat
                if overrideBar[c] == nil then
                    overrideBar[c] = nil
                end
                c = c + 1
            until issecurevariable(overrideBar, "isShownExternal")
        end
    elseif ActionBarsOwned.HandleSpellBookAddonLoaded then
        ActionBarsOwned.HandleSpellBookAddonLoaded(addonName)
    end
end)

---------------------------------------------------------------------------
-- UNLOCK MODE ELEMENT REGISTRATION
---------------------------------------------------------------------------
do
    local function RegisterLayoutModeElements()
        local um = ns.QUI_LayoutMode
        if not um then return end

        local BAR_ELEMENTS = {
            { key = "bar1", label = "Action Bar 1", order = 1 },
            { key = "bar2", label = "Action Bar 2", order = 2 },
            { key = "bar3", label = "Action Bar 3", order = 3 },
            { key = "bar4", label = "Action Bar 4", order = 4 },
            { key = "bar5", label = "Action Bar 5", order = 5 },
            { key = "bar6", label = "Action Bar 6", order = 6 },
            { key = "bar7", label = "Action Bar 7", order = 7 },
            { key = "bar8", label = "Action Bar 8", order = 8 },
            { key = "petBar",    label = "Pet Bar",     order = 9 },
            { key = "stanceBar", label = "Stance Bar",  order = 10 },
            { key = "microMenu", label = "Micro Menu",  order = 11 },
            { key = "bagBar",    label = "Bag Bar",     order = 12 },
        }

        local DB_KEY_MAP = {
            petBar = "pet", stanceBar = "stance",
            microMenu = "microbar", bagBar = "bags",
        }

        -- Master action bars toggle — disabling reverts to Blizzard bars (requires reload)
        um:RegisterElement({
            key = "actionBars",
            label = "Action Bars",
            group = "Action Bars",
            order = -1,
            isOwned = true,
            noHandle = true,
            isEnabled = function()
                local db = GetDB()
                return db and db.enabled ~= false
            end,
            setEnabled = function(val)
                local db = GetDB()
                if not db then return end
                local old = db.enabled ~= false
                db.enabled = val
                if (val ~= false) ~= old then
                    local QUI = _G.QUI
                    local GUI = QUI and QUI.GUI
                    if GUI and GUI.ShowConfirmation then
                        GUI:ShowConfirmation({
                            title = "Reload UI?",
                            message = "Enabling or disabling action bars requires a UI reload to take effect.",
                            acceptText = "Reload",
                            cancelText = "Later",
                            onAccept = function() QUI:SafeReload() end,
                        })
                    end
                end
            end,
            getFrame = function()
                return ActionBarsOwned.containers and ActionBarsOwned.containers["bar1"]
            end,
        })

        -- Leave Vehicle button — standalone proxy mover (not part of the bar loop)
        um:RegisterElement({
            key = "leaveVehicle",
            label = "Leave Vehicle",
            group = "Action Bars",
            order = 13,
            getFrame = function()
                return _G.MainMenuBarVehicleLeaveButton
            end,
        })

        for _, info in ipairs(BAR_ELEMENTS) do
            local dbKey = DB_KEY_MAP[info.key] or info.key
            local containerKey = DB_KEY_MAP[info.key] or info.key
            um:RegisterElement({
                key = info.key,
                label = info.label,
                group = "Action Bars",
                order = info.order,
                isOwned = true,
                isEnabled = function()
                    local db = GetDB()
                    if not db or db.enabled == false then return false end
                    local barDB = GetBarSettings(dbKey)
                    return barDB and barDB.enabled ~= false
                end,
                setEnabled = function(val)
                    local barDB = GetBarSettings(dbKey)
                    if not barDB then return end
                    local old = barDB.enabled ~= false
                    barDB.enabled = val
                    local container = ActionBarsOwned.containers and ActionBarsOwned.containers[containerKey]
                    if container then
                        container:SetAttribute("qui-user-shown", val and true or false)
                        if val then
                            container:Show()
                        else
                            container:Hide()
                        end
                    end
                    if (val ~= false) ~= old then
                        local QUI = _G.QUI
                        local GUI = QUI and QUI.GUI
                        if GUI and GUI.ShowConfirmation then
                            GUI:ShowConfirmation({
                                title = "Reload UI?",
                                message = "Enabling or disabling an action bar requires a UI reload to fully take effect.",
                                acceptText = "Reload",
                                cancelText = "Later",
                                onAccept = function() QUI:SafeReload() end,
                            })
                        end
                    end
                end,
                getFrame = function()
                    local owned = ActionBarsOwned.containers and ActionBarsOwned.containers[containerKey]
                    if owned then return owned end
                    local BLIZZARD_FRAMES = {
                        bar1 = "MainActionBar", bar2 = "MultiBarBottomLeft",
                        bar3 = "MultiBarBottomRight", bar4 = "MultiBarRight",
                        bar5 = "MultiBarLeft", bar6 = "MultiBar5",
                        bar7 = "MultiBar6", bar8 = "MultiBar7",
                        petBar = "PetActionBar", stanceBar = "StanceBar",
                        microMenu = "MicroMenuContainer", bagBar = "BagsBar",
                    }
                    return _G[BLIZZARD_FRAMES[info.key]]
                end,
                setGameplayHidden = function(hide)
                    local container = ActionBarsOwned.containers and ActionBarsOwned.containers[containerKey]
                    if not container then return end
                    container:SetAttribute("qui-user-shown", (not hide) and true or false)
                    if hide then
                        container:Hide()
                    else
                        container:Show()
                    end
                end,
                onOpen = function()
                    SetEditOverlayVisible(containerKey, true)
                end,
                onClose = function()
                    SetEditOverlayVisible(containerKey, false)
                end,
            })
        end
    end

    C_Timer.After(2, RegisterLayoutModeElements)
end

---------------------------------------------------------------------------
-- UNLOCK MODE SETTINGS PROVIDER
---------------------------------------------------------------------------
do
    local function RegisterSettingsProviders()
        local settingsPanel = ns.QUI_LayoutMode_Settings
        if not settingsPanel then return end

        local GUI = QUI and QUI.GUI
        if not GUI then return end

        local C = GUI.Colors or {}
        local U = ns.QUI_LayoutMode_Utils
        local P = U.PlaceRow
        local ACCENT_R, ACCENT_G, ACCENT_B = 0.376, 0.647, 0.980
        local PADDING = 0
        local FORM_ROW = U and U.FORM_ROW or 32

        local function RefreshActionBars()
            for _, bk in ipairs(ALL_MANAGED_BAR_KEYS) do
                local buttons = ActionBarsOwned.nativeButtons[bk]
                local settings = GetEffectiveSettings(bk)
                if buttons and settings then
                    if SKINNABLE_BAR_KEYS[bk] then
                        for _, btn in ipairs(buttons) do
                            local st = GetFrameState(btn)
                            st.skinKey = nil
                            SkinButton(btn, settings)
                            UpdateButtonText(btn, settings)
                            UpdateEmptySlotVisibility(btn, settings)
                        end
                    end
                    pcall(LayoutNativeButtons, bk)
                end
            end
        end

        local anchorOptions = {
            {value = "TOPLEFT", text = "Top Left"},
            {value = "TOP", text = "Top"},
            {value = "TOPRIGHT", text = "Top Right"},
            {value = "LEFT", text = "Left"},
            {value = "CENTER", text = "Center"},
            {value = "RIGHT", text = "Right"},
            {value = "BOTTOMLEFT", text = "Bottom Left"},
            {value = "BOTTOM", text = "Bottom"},
            {value = "BOTTOMRIGHT", text = "Bottom Right"},
        }

        local orientationOptions = {
            {value = "horizontal", text = "Horizontal"},
            {value = "vertical", text = "Vertical"},
        }

        local LAYOUT_BARS = {
            bar1 = true, bar2 = true, bar3 = true, bar4 = true,
            bar5 = true, bar6 = true, bar7 = true, bar8 = true,
            pet = true, stance = true, microbar = true, bags = true,
        }

        local FLYOUT_BARS = {
            bar1 = true, bar2 = true, bar3 = true, bar4 = true,
            bar5 = true, bar6 = true, bar7 = true, bar8 = true,
        }

        local flyoutDirectionOptions = {
            {value = "AUTO",  text = "Auto"},
            {value = "UP",    text = "Up"},
            {value = "DOWN",  text = "Down"},
            {value = "LEFT",  text = "Left"},
            {value = "RIGHT", text = "Right"},
        }

        local SETTINGS_DB_KEY_MAP = {
            petBar = "pet", stanceBar = "stance",
            microMenu = "microbar", bagBar = "bags",
        }

        local copyKeys = {
            "iconZoom", "showBackdrop", "backdropAlpha", "showGloss", "glossAlpha", "showBorders",
            "showKeybinds", "hideEmptyKeybinds", "keybindFontSize", "keybindColor",
            "keybindAnchor", "keybindOffsetX", "keybindOffsetY",
            "showMacroNames", "macroNameFontSize", "macroNameColor",
            "macroNameAnchor", "macroNameOffsetX", "macroNameOffsetY",
            "showCounts", "countFontSize", "countColor",
            "countAnchor", "countOffsetX", "countOffsetY",
            "showFlash",
        }

        local copyBarOptions = {
            {value = "bar1", text = "Bar 1"}, {value = "bar2", text = "Bar 2"},
            {value = "bar3", text = "Bar 3"}, {value = "bar4", text = "Bar 4"},
            {value = "bar5", text = "Bar 5"}, {value = "bar6", text = "Bar 6"},
            {value = "bar7", text = "Bar 7"}, {value = "bar8", text = "Bar 8"},
        }

        local function CreateCollapsible(parent, title, contentHeight, buildFunc, sections, relayout)
            return U.CreateCollapsible(parent, title, contentHeight, buildFunc, sections, relayout)
        end

        local function BuildBarSettings(content, barKey, width)
            local db = GetDB()
            if not db or not db.bars then return 80 end

            local dbKey = SETTINGS_DB_KEY_MAP[barKey] or barKey
            local barDB = db.bars[dbKey]
            if not barDB then return 80 end

            local global = db.global
            local hasLayout = LAYOUT_BARS[dbKey]
            local layout = barDB.ownedLayout

            local sections = {}
            local function relayout() U.StandardRelayout(content, sections) end
            local DEFER = { deferOnDrag = true }

            -- Lightweight preview: recompute container size from layout params
            local function PreviewBarSize()
                local container = ActionBarsOwned.containers and ActionBarsOwned.containers[DB_KEY_MAP[barKey] or barKey]
                if not container or not layout then return end
                local btnSize = layout.buttonSize or 36
                local spacing = layout.buttonSpacing or 2
                local cols = layout.columns or 12
                local visible = layout.iconCount or (BUTTON_COUNTS[dbKey] or 12)
                local rows = math.ceil(visible / math.max(cols, 1))
                local isVertical = layout.orientation == "vertical"
                local w, h
                if isVertical then
                    w = rows * btnSize + math.max(rows - 1, 0) * spacing
                    h = math.min(visible, cols) * btnSize + math.max(math.min(visible, cols) - 1, 0) * spacing
                else
                    w = math.min(visible, cols) * btnSize + math.max(math.min(visible, cols) - 1, 0) * spacing
                    h = rows * btnSize + math.max(rows - 1, 0) * spacing
                end
                container:SetSize(math.max(w, 1), math.max(h, 1))
            end
            local DEFER_SIZE = { deferOnDrag = true, onDragPreview = PreviewBarSize }

            -- SECTION: Layout
            if hasLayout and layout then
                local isMicroBag = (dbKey == "microbar" or dbKey == "bags")
                local maxButtons = BUTTON_COUNTS[dbKey] or (dbKey == "microbar" and 12 or (dbKey == "bags" and 6 or 12))
                local extraRows = isMicroBag and 1 or 2
                if barKey == "bar1" then extraRows = extraRows + 1 end
                if FLYOUT_BARS[barKey] then extraRows = extraRows + 1 end
                local numRows = 7 + extraRows
                local descHeight = isMicroBag and 0 or 16
                CreateCollapsible(content, "Layout", numRows * FORM_ROW + descHeight + 8, function(body)
                    local sy = -4

                    if barKey == "bar1" then
                        sy = P(GUI:CreateFormCheckbox(body,
                            "Hide Default Paging Arrow", "hidePageArrow", barDB,
                            function(val)
                                if _G.QUI_ApplyPageArrowVisibility then
                                    _G.QUI_ApplyPageArrowVisibility(val)
                                end
                            end), body, sy)
                    end

                    if not isMicroBag then
                    local applyAllBtn = CreateFrame("Button", nil, body)
                    applyAllBtn:SetSize(200, 22)
                    applyAllBtn:SetPoint("TOPLEFT", 0, sy)

                    local applyBg = applyAllBtn:CreateTexture(nil, "BACKGROUND")
                    applyBg:SetAllPoints()
                    applyBg:SetColorTexture(ACCENT_R, ACCENT_G, ACCENT_B, 0.25)

                    local applyText = applyAllBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                    applyText:SetPoint("CENTER")
                    applyText:SetText("Apply To All Bars")
                    applyText:SetTextColor(1, 1, 1, 1)

                    applyAllBtn:SetScript("OnClick", function()
                        for i = 1, 8 do
                            local otherKey = "bar" .. i
                            if otherKey ~= barKey then
                                local otherDbKey = SETTINGS_DB_KEY_MAP[otherKey] or otherKey
                                local otherDB = db.bars[otherDbKey]
                                if otherDB then
                                    for _, key in ipairs(copyKeys) do
                                        otherDB[key] = barDB[key]
                                    end
                                end
                            end
                        end
                        RefreshActionBars()
                    end)
                    applyAllBtn:SetScript("OnEnter", function()
                        applyBg:SetColorTexture(ACCENT_R, ACCENT_G, ACCENT_B, 0.4)
                    end)
                    applyAllBtn:SetScript("OnLeave", function()
                        applyBg:SetColorTexture(ACCENT_R, ACCENT_G, ACCENT_B, 0.25)
                    end)
                    sy = sy - FORM_ROW

                    local filteredCopyOptions = {}
                    for _, opt in ipairs(copyBarOptions) do
                        if opt.value ~= barKey then
                            table.insert(filteredCopyOptions, opt)
                        end
                    end

                    sy = P(GUI:CreateFormDropdown(body, "Copy Settings From", filteredCopyOptions, nil, nil,
                        function(sourceKey)
                            local sourceDbKey = SETTINGS_DB_KEY_MAP[sourceKey] or sourceKey
                            local sourceDB = db.bars[sourceDbKey]
                            if not sourceDB then return end
                            for _, key in ipairs(copyKeys) do
                                barDB[key] = sourceDB[key]
                            end
                            RefreshActionBars()
                        end), body, sy)

                    local copyDesc = body:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                    copyDesc:SetPoint("TOPLEFT", 2, sy + 4)
                    copyDesc:SetPoint("RIGHT", body, "RIGHT", 0, 0)
                    copyDesc:SetTextColor(0.5, 0.5, 0.5, 1)
                    copyDesc:SetText("Copies visual, keybind, macro, and count settings. Layout is per-bar.")
                    copyDesc:SetJustifyH("LEFT")
                    sy = sy - 16
                    end -- isMicroBag guard

                    if isMicroBag then
                        sy = P(GUI:CreateFormCheckbox(body, "Clickthrough",
                            "clickthrough", barDB, function(val)
                                local btns = ActionBarsOwned.nativeButtons[dbKey]
                                if btns then
                                    for _, btn in ipairs(btns) do
                                        btn:EnableMouse(not val)
                                    end
                                end
                            end), body, sy)
                    end

                    sy = P(GUI:CreateFormDropdown(body, "Orientation",
                        orientationOptions, "orientation", layout, RefreshActionBars), body, sy)

                    sy = P(GUI:CreateFormSlider(body, "Buttons Per Row",
                        1, maxButtons, 1, "columns", layout, RefreshActionBars, DEFER_SIZE), body, sy)

                    sy = P(GUI:CreateFormSlider(body, "Visible Buttons",
                        1, maxButtons, 1, "iconCount", layout, RefreshActionBars, DEFER_SIZE), body, sy)

                    sy = P(GUI:CreateFormSlider(body, "Button Size",
                        20, 64, 1, "buttonSize", layout, RefreshActionBars, DEFER_SIZE), body, sy)

                    sy = P(GUI:CreateFormSlider(body, "Button Spacing",
                        -10, 10, 1, "buttonSpacing", layout, RefreshActionBars, DEFER_SIZE), body, sy)

                    sy = P(GUI:CreateFormCheckbox(body, "Grow Upward",
                        "growUp", layout, RefreshActionBars), body, sy)

                    if FLYOUT_BARS[barKey] then
                        sy = P(GUI:CreateFormCheckbox(body, "Grow Left",
                            "growLeft", layout, RefreshActionBars), body, sy)

                        P(GUI:CreateFormDropdown(body, "Flyout Direction",
                            flyoutDirectionOptions, "flyoutDirection", layout,
                            function()
                                ApplyFlyoutDirection(barKey)
                            end), body, sy)
                    else
                        P(GUI:CreateFormCheckbox(body, "Grow Left",
                            "growLeft", layout, RefreshActionBars), body, sy)
                    end
                end, sections, relayout)
            end

            -- SECTION: Visual (action bars only — micro/bag buttons are not skinned)
            if SKINNABLE_BAR_KEYS[dbKey] then
            CreateCollapsible(content, "Visual", 7 * FORM_ROW + 8, function(body)
                local sy = -4
                sy = P(GUI:CreateFormSlider(body, "Icon Crop",
                    0.05, 0.15, 0.01, "iconZoom", barDB, RefreshActionBars, DEFER), body, sy)

                sy = P(GUI:CreateFormCheckbox(body, "Show Backdrop",
                    "showBackdrop", barDB, RefreshActionBars), body, sy)

                sy = P(GUI:CreateFormSlider(body, "Backdrop Opacity",
                    0, 1, 0.05, "backdropAlpha", barDB, RefreshActionBars, DEFER), body, sy)

                sy = P(GUI:CreateFormCheckbox(body, "Show Gloss",
                    "showGloss", barDB, RefreshActionBars), body, sy)

                sy = P(GUI:CreateFormSlider(body, "Gloss Opacity",
                    0, 1, 0.05, "glossAlpha", barDB, RefreshActionBars, DEFER), body, sy)

                sy = P(GUI:CreateFormCheckbox(body, "Show Borders",
                    "showBorders", barDB, RefreshActionBars), body, sy)

                local pressedOptions = {
                    {value = "off", text = "Off"},
                    {value = "blizzard", text = "Blizzard Default"},
                    {value = "qui", text = "QUI"},
                }
                P(GUI:CreateFormDropdown(body, "Pressed Effect",
                    pressedOptions, "showFlash", barDB, RefreshActionBars), body, sy)
            end, sections, relayout)

            -- SECTION: Keybind Text
            CreateCollapsible(content, "Keybind Text", 7 * FORM_ROW + 8, function(body)
                local sy = -4
                sy = P(GUI:CreateFormCheckbox(body, "Show Keybinds",
                    "showKeybinds", barDB, RefreshActionBars), body, sy)

                sy = P(GUI:CreateFormCheckbox(body, "Hide Empty Keybinds",
                    "hideEmptyKeybinds", barDB, RefreshActionBars), body, sy)

                sy = P(GUI:CreateFormSlider(body, "Font Size",
                    8, 18, 1, "keybindFontSize", barDB, RefreshActionBars, DEFER), body, sy)

                sy = P(GUI:CreateFormDropdown(body, "Anchor",
                    anchorOptions, "keybindAnchor", barDB, RefreshActionBars), body, sy)

                sy = P(GUI:CreateFormSlider(body, "X-Offset",
                    -20, 20, 1, "keybindOffsetX", barDB, RefreshActionBars, DEFER), body, sy)

                sy = P(GUI:CreateFormSlider(body, "Y-Offset",
                    -20, 20, 1, "keybindOffsetY", barDB, RefreshActionBars, DEFER), body, sy)

                P(GUI:CreateFormColorPicker(body, "Color",
                    "keybindColor", barDB, RefreshActionBars), body, sy)
            end, sections, relayout)

            -- SECTION: Macro Names
            CreateCollapsible(content, "Macro Names", 6 * FORM_ROW + 8, function(body)
                local sy = -4
                sy = P(GUI:CreateFormCheckbox(body, "Show Macro Names",
                    "showMacroNames", barDB, RefreshActionBars), body, sy)

                sy = P(GUI:CreateFormSlider(body, "Font Size",
                    8, 18, 1, "macroNameFontSize", barDB, RefreshActionBars, DEFER), body, sy)

                sy = P(GUI:CreateFormDropdown(body, "Anchor",
                    anchorOptions, "macroNameAnchor", barDB, RefreshActionBars), body, sy)

                sy = P(GUI:CreateFormSlider(body, "X-Offset",
                    -20, 20, 1, "macroNameOffsetX", barDB, RefreshActionBars, DEFER), body, sy)

                sy = P(GUI:CreateFormSlider(body, "Y-Offset",
                    -20, 20, 1, "macroNameOffsetY", barDB, RefreshActionBars, DEFER), body, sy)

                P(GUI:CreateFormColorPicker(body, "Color",
                    "macroNameColor", barDB, RefreshActionBars), body, sy)
            end, sections, relayout)

            -- SECTION: Stack Count
            CreateCollapsible(content, "Stack Count", 6 * FORM_ROW + 8, function(body)
                local sy = -4
                sy = P(GUI:CreateFormCheckbox(body, "Show Counts",
                    "showCounts", barDB, RefreshActionBars), body, sy)

                sy = P(GUI:CreateFormSlider(body, "Font Size",
                    8, 20, 1, "countFontSize", barDB, RefreshActionBars, DEFER), body, sy)

                sy = P(GUI:CreateFormDropdown(body, "Anchor",
                    anchorOptions, "countAnchor", barDB, RefreshActionBars), body, sy)

                sy = P(GUI:CreateFormSlider(body, "X-Offset",
                    -20, 20, 1, "countOffsetX", barDB, RefreshActionBars, DEFER), body, sy)

                sy = P(GUI:CreateFormSlider(body, "Y-Offset",
                    -20, 20, 1, "countOffsetY", barDB, RefreshActionBars, DEFER), body, sy)

                P(GUI:CreateFormColorPicker(body, "Color",
                    "countColor", barDB, RefreshActionBars), body, sy)
            end, sections, relayout)
            end -- SKINNABLE_BAR_KEYS guard

            -- Position / Anchoring
            U.BuildPositionCollapsible(content, barKey, nil, sections, relayout)

            -- Initial layout
            relayout()
            return content:GetHeight()
        end

        local ALL_BAR_KEYS = {
            "bar1", "bar2", "bar3", "bar4", "bar5", "bar6", "bar7", "bar8",
            "stanceBar", "petBar", "microMenu", "bagBar",
        }

        settingsPanel:RegisterProvider(ALL_BAR_KEYS, {
            build = BuildBarSettings,
        })
    end

    C_Timer.After(3, RegisterSettingsProviders)
end

---------------------------------------------------------------------------
-- EXPOSE MODULE
---------------------------------------------------------------------------

local core = GetCore()
if core then
    core.ActionBars = ActionBarsOwned
end

if ns.Registry then
    ns.Registry:Register("actionbars", {
        refresh = _G.QUI_RefreshActionBars,
        priority = 20,
        group = "frames",
        importCategories = { "actionBars" },
    })
end
