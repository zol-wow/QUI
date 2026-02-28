---------------------------------------------------------------------------
-- QUI Tooltip Module
-- Cursor-following tooltips with per-context visibility controls
---------------------------------------------------------------------------
local ADDON_NAME, ns = ...
local QUI = ns.QUI or {}
ns.QUI = QUI
local Helpers = ns.Helpers

-- Locals for performance
local GameTooltip = GameTooltip
local UIParent = UIParent
local IsShiftKeyDown = IsShiftKeyDown
local IsControlKeyDown = IsControlKeyDown
local IsAltKeyDown = IsAltKeyDown
local InCombatLockdown = InCombatLockdown
local strfind = string.find
local strmatch = string.match
local GetMouseFoci = GetMouseFoci
local WorldFrame = WorldFrame

---------------------------------------------------------------------------
-- Mouse Focus Detection
-- Gets topmost frame under mouse cursor (API compatibility wrapper)
-- PERFORMANCE: Cached to prevent repeated GetMouseFoci() calls with @mouseover macros
---------------------------------------------------------------------------
local cachedMouseFrame = nil
local cachedMouseFrameTime = 0
local MOUSE_FRAME_CACHE_TTL = 0.2  -- 200ms cache (was 100ms)

local function GetTopMouseFrame()
    local now = GetTime()
    -- Return cached result if still valid
    if cachedMouseFrame ~= nil and (now - cachedMouseFrameTime) < MOUSE_FRAME_CACHE_TTL then
        return cachedMouseFrame
    end

    -- Expensive API call - cache the result
    if GetMouseFoci then
        local frames = GetMouseFoci()
        cachedMouseFrame = frames and frames[1]
    else
        cachedMouseFrame = GetMouseFocus and GetMouseFocus()
    end
    cachedMouseFrameTime = now
    return cachedMouseFrame
end

-- Check if a UI frame is blocking mouse from the 3D world
local function IsFrameBlockingMouse()
    local focus = GetTopMouseFrame()
    if not focus then return false end

    -- WorldFrame means mouse is over the 3D world, not a UI panel
    if focus == WorldFrame then return false end

    -- If there's any other visible frame under the mouse, it's blocking
    return focus:IsVisible()
end

-- State
local cachedSettings = nil
local originalSetDefaultAnchor = nil

-- PERFORMANCE: Pending state for debouncing (prevents spam with @mouseover macros)
local pendingSetUnit = nil


-- Frames below this alpha are considered "faded out" and tooltips will be suppressed
local FADED_ALPHA_THRESHOLD = 0.5

---------------------------------------------------------------------------
-- Get settings from database (cached for performance)
---------------------------------------------------------------------------
local function GetSettings()
    if cachedSettings then return cachedSettings end
    cachedSettings = Helpers.GetModuleDB("tooltip")
    return cachedSettings
end

-- Cache invalidation (called on profile change or settings update)
local function InvalidateCache()
    cachedSettings = nil
end

---------------------------------------------------------------------------
-- Context Detection
-- Determines what triggered the tooltip based on owner frame
---------------------------------------------------------------------------
local function GetTooltipContext(owner)
    if not owner then return "npcs" end

    -- CDM: Check for skinned CDM icons (Essential, Utility, Buff views)
    -- TAINT SAFETY: Use global accessor to check icon state from weak-keyed table
    -- Note: "skinned" is per-ICON state (iconState), NOT per-viewer state (viewerState)
    local getIS = _G.QUI_GetCDMIconState
    local ownerIS = getIS and getIS(owner)
    if ownerIS and ownerIS.skinned then
        return "cdm"
    end

    -- Check parent for CDM (tooltip owner might be child of CDM icon)
    local parent = owner:GetParent()
    if parent then
        local parentIS = getIS and getIS(parent)
        if parentIS and parentIS.skinned then
            return "cdm"
        end
        -- Check if parent is a CDM viewer frame
        local getViewer = _G.QUI_GetCDMViewerFrame
        if getViewer and (
           parent == getViewer("essential") or
           parent == getViewer("utility") or
           parent == getViewer("buffIcon") or
           parent == getViewer("buffBar")) then
            return "cdm"
        end
    end

    -- Custom Trackers: Check for custom tracker icons
    if owner.__customTrackerIcon then
        return "customTrackers"
    end

    local name = owner:GetName() or ""

    -- Abilities: Check for action button patterns
    if strmatch(name, "ActionButton") or
       strmatch(name, "MultiBar") or
       strmatch(name, "PetActionButton") or
       strmatch(name, "StanceButton") or
       strmatch(name, "OverrideActionBar") or
       strmatch(name, "ExtraActionButton") or
       strmatch(name, "BT4Button") or           -- Bartender4
       strmatch(name, "DominosActionButton") or -- Dominos
       strmatch(name, "ElvUI_Bar") then         -- ElvUI

        -- Check if this action button contains an item (trinket, equipment, etc)
        local actionSlot = owner:GetAttribute("action")
        if actionSlot then
            local actionType, actionID = GetActionInfo(actionSlot)
            if actionType == "item" then
                return "items"
            end
        end

        return "abilities"
    end

    -- Items: Check for container/bag frame patterns
    if strmatch(name, "ContainerFrame") or
       strmatch(name, "BagSlot") or
       strmatch(name, "BankFrame") or
       strmatch(name, "ReagentBank") or
       strmatch(name, "BagItem") or
       strmatch(name, "Baganator") then         -- Baganator addon
        return "items"
    end

    -- Check parent for bag items (nested frames)
    -- Note: parent already defined earlier for CDM check
    if parent then
        local parentNameItems = parent:GetName() or ""
        if strmatch(parentNameItems, "ContainerFrame") or
           strmatch(parentNameItems, "BankFrame") or
           strmatch(parentNameItems, "Baganator") then
            return "items"
        end
    end

    -- Frames: Check for unit frame patterns
    if owner.unit or                            -- Standard unit attribute
       strmatch(name, "UnitFrame") or
       strmatch(name, "PlayerFrame") or
       strmatch(name, "TargetFrame") or
       strmatch(name, "FocusFrame") or
       strmatch(name, "PartyMemberFrame") or
       strmatch(name, "CompactRaidFrame") or
       strmatch(name, "CompactPartyFrame") or
       strmatch(name, "NamePlate") or
       strmatch(name, "Quazii.*Frame") then     -- QUI unit frames
        return "frames"
    end

    -- Default: NPCs, players, objects in the game world
    return "npcs"
end

---------------------------------------------------------------------------
-- Modifier Key Check
---------------------------------------------------------------------------
local function IsModifierActive(modKey)
    if modKey == "SHIFT" then return IsShiftKeyDown() end
    if modKey == "CTRL" then return IsControlKeyDown() end
    if modKey == "ALT" then return IsAltKeyDown() end
    return false
end

---------------------------------------------------------------------------
-- Visibility Logic
-- Determines if tooltip should be shown based on context and settings
---------------------------------------------------------------------------
local function ShouldShowTooltip(context)
    local settings = GetSettings()
    if not settings or not settings.enabled then
        return true  -- Module disabled = default behavior
    end

    -- Combat check - if hideInCombat is enabled and we're in combat
    if settings.hideInCombat and InCombatLockdown() then
        -- Check if combat key is set and pressed
        if settings.combatKey and settings.combatKey ~= "NONE" then
            if IsModifierActive(settings.combatKey) then
                return true  -- Force show in combat with modifier
            end
        end
        return false  -- Hide in combat (no key pressed)
    end

    local visibility = settings.visibility and settings.visibility[context]
    if not visibility then
        return true  -- Unknown context = show by default
    end

    -- Context visibility check
    if visibility == "SHOW" then
        return true
    elseif visibility == "HIDE" then
        return false
    else
        -- Modifier-based visibility (SHIFT/CTRL/ALT)
        return IsModifierActive(visibility)
    end
end

---------------------------------------------------------------------------
-- Tooltip Hook
-- Intercepts GameTooltip_SetDefaultAnchor to apply cursor anchoring
---------------------------------------------------------------------------
local function SetupTooltipHook()
    -- NOTE: Tooltip hooks run synchronously — deferring causes visible flashing/repositioning.
    -- These are NOT a taint source for Edit Mode (tooltips are not in the Edit Mode chain).
    hooksecurefunc("GameTooltip_SetDefaultAnchor", function(tooltip, parent)
        local settings = GetSettings()
        if not settings or not settings.enabled then
            return  -- Module disabled, use default behavior
        end

        -- Get context from parent (owner)
        local context = GetTooltipContext(parent)

        -- Check visibility for this context (handles combat + modifier key logic)
        if not ShouldShowTooltip(context) then
            tooltip:Hide()
            tooltip:SetOwner(UIParent, "ANCHOR_NONE")
            tooltip:ClearLines()
            return
        end

        -- Cursor anchor logic
        if settings.anchorToCursor then
            -- Use WoW's built-in cursor anchor (handles positioning automatically)
            tooltip:SetOwner(parent, "ANCHOR_CURSOR")
        end
    end)

    -- Hook SetUnit to suppress tooltips when a UI frame blocks the mouse
    -- PERFORMANCE: Debounced to prevent spam with @mouseover macros (max 20 calls/sec)
    hooksecurefunc(GameTooltip, "SetUnit", function(tooltip)
        local settings = GetSettings()
        if not settings or not settings.enabled then return end

        -- Debounce: Only process once per 100ms to prevent CPU spikes with @mouseover macros
        if pendingSetUnit then return end
        pendingSetUnit = C_Timer.After(0.1, function()
            pendingSetUnit = nil
            -- If owner is UIParent (world tooltip) and a UI frame is blocking the mouse
            if tooltip:GetOwner() == UIParent and IsFrameBlockingMouse() then
                tooltip:Hide()
            end
        end)
    end)

    -- Apply class color to player names in tooltips (WoW 10.0+)
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, function(tooltip)
        if tooltip ~= GameTooltip then return end
        -- Skip during combat — SetTextColor inside the TooltipDataProcessor
        -- securecall chain taints the line object, breaking other addons
        if InCombatLockdown() then return end

        local settings = GetSettings()
        if not settings or not settings.enabled or not settings.classColorName then return end

        local _, unit = tooltip:GetUnit()
        if not unit then return end

        -- Wrap UnitIsPlayer in pcall to handle protected "secret" unit values
        -- During instanced combat, unit can be a protected value that causes taint errors
        local okPlayer, isPlayer = pcall(UnitIsPlayer, unit)
        if not okPlayer or not isPlayer then return end

        local okClass, _, class = pcall(UnitClass, unit)
        if not okClass or not class then return end

        local classColor = class and RAID_CLASS_COLORS[class]
        if classColor then
            local nameLine = GameTooltipTextLeft1
            if nameLine then
                -- pcall guards against TOCTOU race: combat can start between
                -- InCombatLockdown() check and here, making GetText() return
                -- a secret value and tainting the fontstring for other addons.
                local okText, text = pcall(nameLine.GetText, nameLine)
                if okText and text and not Helpers.IsSecretValue(text) then
                    nameLine:SetTextColor(classColor.r, classColor.g, classColor.b)
                end
            end
        end
    end)

    -- Hide tooltip health bar based on settings
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, function(tooltip)
        if tooltip ~= GameTooltip then return end
        if InCombatLockdown() then return end

        local settings = GetSettings()
        if not settings or not settings.enabled then return end

        local hideBar = settings.hideHealthBar

        if GameTooltipStatusBar then
            GameTooltipStatusBar:SetShown(not hideBar)
            GameTooltipStatusBar:SetAlpha(hideBar and 0 or 1)
        end
    end)

    -- Track which tooltip has already had IDs added (to prevent duplicates)
    local tooltipSpellIDAdded = {}

    -- Clear tracking when tooltip hides or is cleared (synchronous — lightweight table nil)
    GameTooltip:HookScript("OnHide", function(tooltip)
        tooltipSpellIDAdded[tooltip] = nil
    end)
    GameTooltip:HookScript("OnTooltipCleared", function(tooltip)
        tooltipSpellIDAdded[tooltip] = nil
    end)

    -- Secret value safety checks (Aura tooltips can pass protected values in combat)
    local function IsBlockedValue(value)
        if value == nil then return false end
        if type(issecretvalue) == "function" and issecretvalue(value) then
            return true
        end
        if type(canaccessvalue) == "function" and not canaccessvalue(value) then
            return true
        end
        return false
    end

    local function CanAccessAuraArgs(unit, token)
        if IsBlockedValue(unit) then return false end
        if IsBlockedValue(token) then return false end
        return true
    end

    -- Helper to force tooltip size/backdrop refresh after adding lines
    local function RefreshTooltipLayout(tooltip)
        if not tooltip then return end
        if type(tooltip.UpdateTooltipSize) == "function" then
            pcall(tooltip.UpdateTooltipSize, tooltip)
        end
        tooltip:Show()
    end

    -- Helper function to add spell/icon ID info to a tooltip
    local function AddSpellIDToTooltip(tooltip, spellID, skipShow)
        if not spellID then return end

        local settings = GetSettings()
        if not settings or not settings.enabled or not settings.showSpellIDs then return end

        -- Validate spellID is a normal number, not a secret value
        if type(spellID) ~= "number" then return end
        if type(issecretvalue) == "function" and issecretvalue(spellID) then return end

        -- Prevent duplicate additions
        if tooltipSpellIDAdded[tooltip] then return end
        tooltipSpellIDAdded[tooltip] = true

        -- Get icon texture ID (protected)
        local iconID = nil
        if C_Spell and C_Spell.GetSpellTexture then
            local iconOk, result = pcall(C_Spell.GetSpellTexture, spellID)
            if iconOk and result and type(result) == "number" then
                iconID = result
            end
        end

        -- Add ID info to tooltip
        tooltip:AddLine(" ")
        tooltip:AddDoubleLine("Spell ID:", tostring(spellID), 0.5, 0.8, 1, 1, 1, 1)
        if iconID then
            tooltip:AddDoubleLine("Icon ID:", tostring(iconID), 0.5, 0.8, 1, 1, 1, 1)
        end

        -- Resize tooltip to fit new lines (skip for UnitAura to avoid combat errors)
        if not skipShow then
            RefreshTooltipLayout(tooltip)
        end
    end

    -- Use TooltipDataProcessor for Spell tooltips (action bars, spellbook, CDM, etc.)
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Spell, function(tooltip, data)
        pcall(function()
            if data and data.id and type(data.id) == "number" then
                AddSpellIDToTooltip(tooltip, data.id)
            end
        end)
    end)

    -- Aura tooltip data (player buffs/debuffs) - guard for optional enum
    if Enum.TooltipDataType.Aura then
        TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Aura, function(tooltip, data)
            pcall(function()
                if data and data.id and type(data.id) == "number" then
                    AddSpellIDToTooltip(tooltip, data.id, false)
                end
            end)
        end)
    end

    -- For UnitAura tooltips, we CANNOT use TooltipDataProcessor as it causes Blizzard CDM
    -- errors in combat. Use direct hooks on the tooltip methods instead.
    -- Get spell ID from method arguments + C_UnitAuras API.

    -- NOTE: Aura tooltip hooks run synchronously — deferring causes spell IDs to appear late/missing.
    -- These are NOT a taint source for Edit Mode (tooltips are not in the Edit Mode chain).

    -- Helper to create aura tooltip hooks
    local function HookAuraTooltip(methodName, getAuraFunc, isGeneric)
        if not GameTooltip[methodName] then return end
        hooksecurefunc(GameTooltip, methodName, function(tooltip, unit, indexOrID, filter)
            if not CanAccessAuraArgs(unit, indexOrID) then return end
            pcall(function()
                local auraData
                if filter ~= nil then
                    auraData = getAuraFunc(unit, indexOrID, filter)
                else
                    auraData = getAuraFunc(unit, indexOrID)
                end
                if type(canaccesstable) == "function" and auraData and not canaccesstable(auraData) then
                    return
                end
                if auraData and auraData.spellId then
                    AddSpellIDToTooltip(tooltip, auraData.spellId, isGeneric or false)
                end
            end)
        end)
    end

    if C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
        HookAuraTooltip("SetUnitAura", C_UnitAuras.GetAuraDataByIndex, false)
    end
    if C_UnitAuras and C_UnitAuras.GetBuffDataByIndex then
        HookAuraTooltip("SetUnitBuff", C_UnitAuras.GetBuffDataByIndex, false)
    end
    if C_UnitAuras and C_UnitAuras.GetDebuffDataByIndex then
        HookAuraTooltip("SetUnitDebuff", C_UnitAuras.GetDebuffDataByIndex, false)
    end
    if C_UnitAuras and C_UnitAuras.GetAuraDataByAuraInstanceID then
        HookAuraTooltip("SetUnitBuffByAuraInstanceID", C_UnitAuras.GetAuraDataByAuraInstanceID, false)
        HookAuraTooltip("SetUnitDebuffByAuraInstanceID", C_UnitAuras.GetAuraDataByAuraInstanceID, false)
        HookAuraTooltip("SetUnitAuraByAuraInstanceID", C_UnitAuras.GetAuraDataByAuraInstanceID, true)
    end

    -- Hook SetSpellByID to suppress CDM and Custom Tracker tooltips
    -- These icons use SetSpellByID which bypasses GameTooltip_SetDefaultAnchor
    -- NOTE: Synchronous — deferring causes tooltip flash before hide.
    hooksecurefunc(GameTooltip, "SetSpellByID", function(tooltip)
        local settings = GetSettings()
        if not settings or not settings.enabled then return end

        local owner = tooltip:GetOwner()

        -- Suppress tooltip if owner frame is faded out (e.g., CDM hidden when mounted)
        if owner and owner.GetEffectiveAlpha and owner:GetEffectiveAlpha() < FADED_ALPHA_THRESHOLD then
            tooltip:Hide()
            return
        end

        local context = GetTooltipContext(owner)

        -- Apply visibility rules to CDM and Custom Trackers contexts
        if context == "cdm" or context == "customTrackers" then
            if not ShouldShowTooltip(context) then
                tooltip:Hide()
            end
        end
    end)

    -- Hook SetItemByID to suppress Custom Tracker item tooltips
    hooksecurefunc(GameTooltip, "SetItemByID", function(tooltip)
        local settings = GetSettings()
        if not settings or not settings.enabled then return end

        local owner = tooltip:GetOwner()

        -- Suppress tooltip if owner frame is faded out (e.g., CDM hidden when mounted)
        if owner and owner.GetEffectiveAlpha and owner:GetEffectiveAlpha() < FADED_ALPHA_THRESHOLD then
            tooltip:Hide()
            return
        end

        local context = GetTooltipContext(owner)

        -- Apply visibility rules to Custom Trackers context
        if context == "customTrackers" then
            if not ShouldShowTooltip("customTrackers") then
                tooltip:Hide()
            end
        end
    end)

    -- Hook GameTooltip_Hide as safety net for combat tooltip issues
    -- Runs after original function - if tooltip still visible during combat, force hide
    hooksecurefunc("GameTooltip_Hide", function()
        C_Timer.After(0, function()
            if InCombatLockdown() and GameTooltip:IsVisible() then
                GameTooltip:Hide()
            end
        end)
    end)

    -- Tooltip sticking monitor - fixes Midnight 12.0+ combat tooltip issue
    -- PERFORMANCE: Only runs during combat (event-driven start/stop)
    -- Only active when hideInCombat is DISABLED (when ON, the hook handles it)
    local tooltipMonitor = CreateFrame("Frame")
    local monitorElapsed = 0

    local function TooltipMonitorOnUpdate(self, delta)
        monitorElapsed = monitorElapsed + delta
        if monitorElapsed < 0.25 then return end  -- 250ms throttle (4 FPS) - was 100ms
        monitorElapsed = 0

        local settings = GetSettings()
        if not settings or not settings.enabled then return end
        if settings.hideInCombat then return end  -- Hook handles this case

        if not GameTooltip:IsVisible() then return end

        local owner = GameTooltip:GetOwner()
        if not owner then return end

        local mouseFrame = GetTopMouseFrame()
        if not mouseFrame then return end

        -- Check if mouse is over owner or child of owner
        local isOverOwner = false
        local checkFrame = mouseFrame
        while checkFrame do
            if checkFrame == owner then
                isOverOwner = true
                break
            end
            checkFrame = checkFrame:GetParent()
        end

        -- If mouse moved away from owner, hide stuck tooltip
        if not isOverOwner then
            GameTooltip:Hide()
        end
    end

    -- Event-driven: Only run OnUpdate during combat
    tooltipMonitor:RegisterEvent("PLAYER_REGEN_DISABLED")
    tooltipMonitor:RegisterEvent("PLAYER_REGEN_ENABLED")
    tooltipMonitor:SetScript("OnEvent", function(self, event)
        if event == "PLAYER_REGEN_DISABLED" then
            -- Entering combat - start monitoring
            monitorElapsed = 0
            self:SetScript("OnUpdate", TooltipMonitorOnUpdate)
        else
            -- Leaving combat - stop monitoring (zero CPU outside combat)
            self:SetScript("OnUpdate", nil)
        end
    end)
end

---------------------------------------------------------------------------
-- Modifier State Handler
-- Re-evaluates tooltip visibility when modifier keys change
---------------------------------------------------------------------------
local function OnModifierStateChanged()
    -- Only process if tooltip is currently shown
    if not GameTooltip:IsShown() then return end

    local settings = GetSettings()
    if not settings or not settings.enabled then return end

    local owner = GameTooltip:GetOwner()
    local context = GetTooltipContext(owner)

    -- If tooltip should now be hidden, hide it
    if not ShouldShowTooltip(context) then
        GameTooltip:Hide()
    end
end

---------------------------------------------------------------------------
-- Combat State Handler
-- Hides tooltips immediately when entering combat (if hideInCombat enabled)
---------------------------------------------------------------------------
local function OnCombatStateChanged(inCombat)
    local settings = GetSettings()
    if not settings or not settings.enabled or not settings.hideInCombat then return end

    if inCombat then
        -- Entering combat - hide tooltip immediately if no combat key override
        if not settings.combatKey or settings.combatKey == "NONE" or not IsModifierActive(settings.combatKey) then
            GameTooltip:Hide()
        end
    end
    -- Leaving combat - nothing special needed, tooltips will show normally
end

---------------------------------------------------------------------------
-- Event Frame
---------------------------------------------------------------------------
local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:RegisterEvent("MODIFIER_STATE_CHANGED")
eventFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")

eventFrame:SetScript("OnEvent", function(self, event, ...)
    if event == "PLAYER_LOGIN" then
        -- Delay hook setup to ensure database is ready
        C_Timer.After(0.5, function()
            SetupTooltipHook()

            -- NOTE: MoneyFrame_Update, SetTooltipMoney, and GameTooltip.SetSpellByID
            -- were previously wrapped in pcall via direct replacement to suppress
            -- Blizzard secret-value bugs. However, direct global function replacement
            -- permanently taints the function in Midnight's taint model, causing
            -- ADDON_ACTION_FORBIDDEN errors throughout Edit Mode and other secure
            -- execution paths. The pcall wrappers have been removed. If Blizzard's
            -- own functions error on secret values, that is a Blizzard bug — QUI
            -- should not absorb the taint cost of working around it.
        end)
    elseif event == "MODIFIER_STATE_CHANGED" then
        OnModifierStateChanged()
    elseif event == "PLAYER_REGEN_DISABLED" then
        -- Entering combat
        OnCombatStateChanged(true)
    elseif event == "PLAYER_REGEN_ENABLED" then
        -- Leaving combat
        OnCombatStateChanged(false)
    end
end)

---------------------------------------------------------------------------
-- Global Refresh Function (called from options panel)
---------------------------------------------------------------------------
_G.QUI_RefreshTooltips = function()
    InvalidateCache()
    -- Settings will apply on next tooltip show
end
