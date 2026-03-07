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
local GetCursorPosition = GetCursorPosition
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

-- GetEffectiveAlpha is C-side (returns fine), but we need to compare in Lua.
-- SafeToNumber returns fallback when the value is secret in combat.
local function IsOwnerFadedOut(owner)
    if not owner or not owner.GetEffectiveAlpha then return false end
    local alpha = Helpers.SafeToNumber(owner:GetEffectiveAlpha(), 1)
    return alpha < FADED_ALPHA_THRESHOLD
end

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
-- Cursor Anchor Positioning
---------------------------------------------------------------------------
local CURSOR_ANCHOR_POINTS = {
    TOPLEFT = true,
    TOP = true,
    TOPRIGHT = true,
    LEFT = true,
    CENTER = true,
    RIGHT = true,
    BOTTOMLEFT = true,
    BOTTOM = true,
    BOTTOMRIGHT = true,
}

local DEFAULT_CURSOR_ANCHOR = "TOPLEFT"
local DEFAULT_CURSOR_OFFSET_X = 16
local DEFAULT_CURSOR_OFFSET_Y = -16

local cursorFollowActive = setmetatable({}, {__mode = "k"})
local cursorFollowHooked = setmetatable({}, {__mode = "k"})

local function GetCursorAnchorConfig(settings)
    local anchor = settings and settings.cursorAnchor
    if type(anchor) ~= "string" or not CURSOR_ANCHOR_POINTS[anchor] then
        anchor = DEFAULT_CURSOR_ANCHOR
    end

    local offsetX = tonumber(settings and settings.cursorOffsetX) or DEFAULT_CURSOR_OFFSET_X
    local offsetY = tonumber(settings and settings.cursorOffsetY) or DEFAULT_CURSOR_OFFSET_Y
    return anchor, offsetX, offsetY
end

local function PositionTooltipAtCursor(tooltip, settings)
    if not tooltip then return end
    if tooltip.IsForbidden and tooltip:IsForbidden() then return end
    -- GetCursorPosition / GetEffectiveScale return secret values in combat;
    -- Lua arithmetic on them taints tooltip frame layout. Let Blizzard handle
    -- default positioning in combat.
    if InCombatLockdown() then return end

    local cursorX, cursorY = GetCursorPosition()
    if not cursorX or not cursorY then return end

    local scale = UIParent:GetEffectiveScale()
    if not scale or scale == 0 then return end

    local anchor, offsetX, offsetY = GetCursorAnchorConfig(settings)
    tooltip:ClearAllPoints()
    tooltip:SetPoint(anchor, UIParent, "BOTTOMLEFT", (cursorX / scale) + offsetX, (cursorY / scale) + offsetY)
end

local function EnsureCursorFollowHooks(tooltip)
    if not tooltip or cursorFollowHooked[tooltip] then return end
    cursorFollowHooked[tooltip] = true

    tooltip:HookScript("OnUpdate", function(self)
        if not cursorFollowActive[self] then return end
        -- Stop cursor follow in combat — secret values from GetCursorPosition
        -- would taint tooltip frame properties via SetPoint arithmetic
        if InCombatLockdown() then
            cursorFollowActive[self] = nil
            return
        end
        local settings = GetSettings()
        if not settings or not settings.enabled or not settings.anchorToCursor then
            cursorFollowActive[self] = nil
            return
        end
        PositionTooltipAtCursor(self, settings)
    end)

    tooltip:HookScript("OnHide", function(self)
        cursorFollowActive[self] = nil
    end)
end

local function AnchorTooltipToCursor(tooltip, parent, settings)
    if not tooltip then return false end
    if tooltip.IsForbidden and tooltip:IsForbidden() then return false end
    EnsureCursorFollowHooks(tooltip)
    tooltip:SetOwner(parent or UIParent, "ANCHOR_NONE")
    cursorFollowActive[tooltip] = true
    PositionTooltipAtCursor(tooltip, settings or GetSettings())
    return true
end

---------------------------------------------------------------------------
-- Context Detection
-- Determines what triggered the tooltip based on owner frame
---------------------------------------------------------------------------
local function GetTooltipContext(owner)
    if not owner then return "npcs" end
    if owner.IsForbidden and owner:IsForbidden() then return "npcs" end

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
        -- GetAttribute returns a secret value in combat; GetActionInfo may reject it
        -- and the returned actionType needs Lua comparison
        local actionSlot = owner:GetAttribute("action")
        if actionSlot and not Helpers.IsSecretValue(actionSlot) then
            local actionType = GetActionInfo(actionSlot)
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
    ns.QUI_AnchorTooltipToCursor = AnchorTooltipToCursor

    -- NOTE: Tooltip hooks run synchronously — deferring causes visible flashing/repositioning.
    -- These are NOT a taint source for Edit Mode (tooltips are not in the Edit Mode chain).
    hooksecurefunc("GameTooltip_SetDefaultAnchor", function(tooltip, parent)
        -- TAINT SAFETY: Return immediately during combat to avoid tainting the
        -- execution context.  Blizzard code that follows this hook (e.g.
        -- GameTooltip_AddWidgetSet → RegisterForWidgetSet → ProcessWidget →
        -- UIWidgetTemplateTextWithState:Setup) runs in the same call stack.
        -- ANY addon code that calls methods on Blizzard frames (Hide, SetOwner,
        -- ClearLines) taints the context, causing GetStringHeight() to return
        -- secret values and arithmetic to fail in widget setup.
        -- Combat tooltip hiding is handled independently by the SetUnit hook.
        if InCombatLockdown() then return end

        if tooltip.IsForbidden and tooltip:IsForbidden() then return end
        if parent and parent.IsForbidden and parent:IsForbidden() then return end

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
            AnchorTooltipToCursor(tooltip, parent, settings)
        else
            cursorFollowActive[tooltip] = nil
        end
    end)

    -- Hook SetUnit to suppress tooltips when a UI frame blocks the mouse
    -- Also hides tooltips in combat when hideInCombat is enabled (prevents flash
    -- caused by Blizzard calling SetUnit AFTER GameTooltip_SetDefaultAnchor already hid it)
    -- PERFORMANCE: Mouse-blocking check debounced to prevent spam with @mouseover macros
    hooksecurefunc(GameTooltip, "SetUnit", function(tooltip)
        if tooltip.IsForbidden and tooltip:IsForbidden() then return end
        local settings = GetSettings()
        if not settings or not settings.enabled then return end

        -- Synchronous combat check — must run immediately (before debounce) to
        -- prevent a 1-frame tooltip flash when hideInCombat is enabled
        if settings.hideInCombat and InCombatLockdown() then
            if not settings.combatKey or settings.combatKey == "NONE" or not IsModifierActive(settings.combatKey) then
                tooltip:Hide()
                return
            end
        end

        -- Debounce: Only process once per 100ms to prevent CPU spikes with @mouseover macros
        if pendingSetUnit then return end
        pendingSetUnit = C_Timer.After(0.1, function()
            pendingSetUnit = nil
            if tooltip.IsForbidden and tooltip:IsForbidden() then return end
            -- If owner is UIParent (world tooltip) and a UI frame is blocking the mouse
            if tooltip:GetOwner() == UIParent and IsFrameBlockingMouse() then
                tooltip:Hide()
            end
        end)
    end)

    -- Apply class color to player names in tooltips (WoW 10.0+)
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, function(tooltip)
        if tooltip ~= GameTooltip then return end

        local settings = GetSettings()
        if not settings or not settings.enabled or not settings.classColorName then return end

        local ok, _, unit = pcall(tooltip.GetUnit, tooltip)
        if not ok then return end
        if not unit then return end

        -- Secret value fallback: tooltip:GetUnit() can return a secret token in 12.0.
        -- Fall back to "mouseover" which is always a valid non-secret unit token.
        if Helpers.IsSecretValue(unit) then
            unit = UnitExists("mouseover") and "mouseover" or nil
            if not unit then return end
        end

        local okPlayer, isPlayer = pcall(UnitIsPlayer, unit)
        if not okPlayer or not isPlayer then return end

        local okClass, _, class = pcall(UnitClass, unit)
        if not okClass or not class then return end

        -- In combat, use C_ClassColor API which handles secret values safely.
        -- Out of combat, use RAID_CLASS_COLORS for consistency.
        local classColor
        if InCombatLockdown() then
            if C_ClassColor and C_ClassColor.GetClassColor then
                local okColor, color = pcall(C_ClassColor.GetClassColor, class)
                if okColor and color then
                    classColor = color
                end
            end
        else
            classColor = RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
        end

        if classColor then
            local nameLine = tooltip.GetLeftLine and tooltip:GetLeftLine(1) or GameTooltipTextLeft1
            if nameLine then
                local okText, text = pcall(nameLine.GetText, nameLine)
                if okText and text and not Helpers.IsSecretValue(text) then
                    pcall(nameLine.SetTextColor, nameLine, classColor.r, classColor.g, classColor.b)
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

        if GameTooltipStatusBar and not (GameTooltipStatusBar.IsForbidden and GameTooltipStatusBar:IsForbidden()) then
            pcall(GameTooltipStatusBar.SetShown, GameTooltipStatusBar, not hideBar)
            pcall(GameTooltipStatusBar.SetAlpha, GameTooltipStatusBar, hideBar and 0 or 1)
        end
    end)

    -- Track which tooltip has already had IDs added (to prevent duplicates)
    local tooltipSpellIDAdded = setmetatable({}, {__mode = "k"})

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
        if tooltip.IsForbidden and tooltip:IsForbidden() then return end
        if type(tooltip.UpdateTooltipSize) == "function" then
            pcall(tooltip.UpdateTooltipSize, tooltip)
        end
        pcall(tooltip.Show, tooltip)
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
    -- Skip in combat: running code in the tainted callback chain contributes to
    -- taint reaching ActionBarController (WoWUIBugs #298). Spell IDs are informational-only.
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Spell, function(tooltip, data)
        if InCombatLockdown() then return end
        pcall(function()
            if data and data.id and type(data.id) == "number" then
                AddSpellIDToTooltip(tooltip, data.id)
            end
        end)
    end)

    -- Aura tooltip data (player buffs/debuffs) - guard for optional enum
    if Enum.TooltipDataType.Aura then
        TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Aura, function(tooltip, data)
            if InCombatLockdown() then return end
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

    -- Hook SetSpellByID to suppress tooltips that bypass GameTooltip_SetDefaultAnchor
    -- (CDM icons, Custom Trackers, action bars, etc.)
    -- NOTE: Synchronous — deferring causes tooltip flash before hide.
    hooksecurefunc(GameTooltip, "SetSpellByID", function(tooltip)
        if tooltip.IsForbidden and tooltip:IsForbidden() then return end
        local settings = GetSettings()
        if not settings or not settings.enabled then return end

        local owner = tooltip:GetOwner()

        -- Suppress tooltip if owner frame is faded out (e.g., CDM hidden when mounted)
        if IsOwnerFadedOut(owner) then
            tooltip:Hide()
            return
        end

        local context = GetTooltipContext(owner)

        if not ShouldShowTooltip(context) then
            tooltip:Hide()
        end
    end)

    -- Hook SetItemByID to suppress tooltips that bypass GameTooltip_SetDefaultAnchor
    hooksecurefunc(GameTooltip, "SetItemByID", function(tooltip)
        if tooltip.IsForbidden and tooltip:IsForbidden() then return end
        local settings = GetSettings()
        if not settings or not settings.enabled then return end

        local owner = tooltip:GetOwner()

        -- Suppress tooltip if owner frame is faded out (e.g., CDM hidden when mounted)
        if IsOwnerFadedOut(owner) then
            tooltip:Hide()
            return
        end

        local context = GetTooltipContext(owner)

        if not ShouldShowTooltip(context) then
            tooltip:Hide()
        end
    end)

    -- Hook GameTooltip_Hide as safety net for combat tooltip issues
    -- Runs after original function - if tooltip still visible during combat, force hide
    hooksecurefunc("GameTooltip_Hide", function()
        C_Timer.After(0, function()
            if GameTooltip.IsForbidden and GameTooltip:IsForbidden() then return end
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
            -- pcall: some frames (e.g. PingListenerFrame) are restricted and
            -- reject GetParent() with "calling on bad self"
            local ok, parent = pcall(checkFrame.GetParent, checkFrame)
            checkFrame = ok and parent or nil
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
ns.QUI_RefreshTooltips = function()
    InvalidateCache()
    -- Settings will apply on next tooltip show
end
