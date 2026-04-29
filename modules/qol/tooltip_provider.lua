--[[
    QUI Tooltip Provider
    Abstraction layer for the tooltip engine.
    Load order: tooltip_provider.lua → tooltip.lua
    Engine files call RegisterEngine() at load time.
    Provider calls Initialize() on the selected engine after PLAYER_LOGIN.
]]

local ADDON_NAME, ns = ...
local Helpers = ns.Helpers
local GetCore = Helpers.GetCore

---------------------------------------------------------------------------
-- PROVIDER STATE
---------------------------------------------------------------------------
local TooltipProvider = {
    engines = {},           -- name → engine table
    activeEngine = nil,     -- the initialized engine table
    activeEngineName = nil, -- "default"
    initialized = false,
}

---------------------------------------------------------------------------
-- ENGINE REGISTRATION
---------------------------------------------------------------------------

--- Register a tooltip engine implementation.
--- @param name string  Engine identifier ("default")
--- @param engine table  Table with contract methods (Initialize, Refresh, etc.)
function TooltipProvider:RegisterEngine(name, engine)
    self.engines[name] = engine
end

--- Get the name of the active engine (or nil if not yet initialized).
--- @return string|nil
function TooltipProvider:GetActiveEngineName()
    return self.activeEngineName
end

---------------------------------------------------------------------------
-- SHARED UTILITIES (engine-agnostic)
---------------------------------------------------------------------------

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
local wipe = wipe

local function GetFrameName(frame)
    if not frame or not frame.GetName then
        return ""
    end
    local ok, name = pcall(frame.GetName, frame)
    if not ok or type(name) ~= "string" then
        return ""
    end
    return name
end

local function IsOPieFrameName(name)
    if name == "" then
        return false
    end
    return strmatch(name, "^OneRing") or
       strmatch(name, "^ORL_") or
       strmatch(name, "^ORLOpen")
end

local function IsOPieFrame(frame)
    local depth = 0
    while frame and depth < 5 do
        if IsOPieFrameName(GetFrameName(frame)) then
            return true
        end
        if frame == UIParent then
            break
        end
        if not frame.GetParent then
            break
        end
        -- GetMouseFoci() can return frames (e.g. PingListenerFrame) whose GetParent errors with "bad self".
        local ok, parent = pcall(frame.GetParent, frame)
        if not ok or not parent then
            break
        end
        frame = parent
        depth = depth + 1
    end
    return false
end

---------------------------------------------------------------------------
-- Cached UI Scale
-- GetEffectiveScale() can return secret values during combat.
-- Cache the scale on UI_SCALE_CHANGED and use the cached value for
-- cursor positioning arithmetic. This is the MidnightTooltip pattern.
---------------------------------------------------------------------------
local cachedUIScale = 1

local function UpdateCachedUIScale()
    local core = GetCore and GetCore()
    if core and type(core.uiscale) == "number" and core.uiscale > 0 then
        cachedUIScale = core.uiscale
        return
    end
    local ok, scale = pcall(UIParent.GetEffectiveScale, UIParent)
    if ok and scale and type(scale) == "number" and scale > 0 then
        cachedUIScale = scale
    end
end

local scaleEventFrame = CreateFrame("Frame")
scaleEventFrame:RegisterEvent("UI_SCALE_CHANGED")
scaleEventFrame:RegisterEvent("DISPLAY_SIZE_CHANGED")
scaleEventFrame:RegisterEvent("ADDON_LOADED")
scaleEventFrame:SetScript("OnEvent", function()
    UpdateCachedUIScale()
end)

---------------------------------------------------------------------------
-- Mouse Focus Detection
-- PERFORMANCE: Cached to prevent repeated GetMouseFoci() calls with @mouseover macros
---------------------------------------------------------------------------
local cachedMouseFrame = nil
local cachedMouseFrameTime = 0
-- Cache TTL must be short: long staleness causes IsTooltipOwnerHovered to keep
-- returning true after the cursor leaves the owner, which masks hideDelay=0
-- and makes "instant hide" look laggy. 50ms still coalesces the multiple
-- GetMouseFoci calls within a single visibility-check tick (those happen
-- microseconds apart) without carrying focus across ticks.
local MOUSE_FRAME_CACHE_TTL = 0.05
local contextCache = Helpers.CreateStateTable()
local CONTEXT_CACHE_TTL = 0.12
local NIL_CONTEXT = {}

local function SetCachedContext(owner, value, now)
    local entry = contextCache[owner]
    if not entry then
        entry = {}
        contextCache[owner] = entry
    end
    entry.value = value or NIL_CONTEXT
    entry.time = now
end

function TooltipProvider:GetTopMouseFrame()
    local now = GetTime()
    if cachedMouseFrame ~= nil and (now - cachedMouseFrameTime) < MOUSE_FRAME_CACHE_TTL then
        return cachedMouseFrame
    end
    if GetMouseFoci then
        local frames = GetMouseFoci()
        cachedMouseFrame = frames and frames[1]
    else
        cachedMouseFrame = GetMouseFocus and GetMouseFocus()
    end
    cachedMouseFrameTime = now
    return cachedMouseFrame
end

function TooltipProvider:IsFrameBlockingMouse()
    local focus = self:GetTopMouseFrame()
    if not focus then return false end
    if focus == WorldFrame then return false end
    if IsOPieFrame(focus) then return false end
    -- Some frames (e.g. PingListenerFrame) are forbidden objects
    -- where IsVisible() cannot be called from addon code.
    local ok, visible = pcall(focus.IsVisible, focus)
    return ok and visible
end

---------------------------------------------------------------------------
-- Settings Cache
---------------------------------------------------------------------------
local cachedSettings = nil

function TooltipProvider:GetSettings()
    if cachedSettings then return cachedSettings end
    cachedSettings = Helpers.GetModuleDB("tooltip")
    return cachedSettings
end

function TooltipProvider:InvalidateCache()
    cachedSettings = nil
end

---------------------------------------------------------------------------
-- Owner Alpha Detection
---------------------------------------------------------------------------
local FADED_ALPHA_THRESHOLD = 0.5

function TooltipProvider:IsOwnerFadedOut(owner)
    if not owner or not owner.GetEffectiveAlpha then return false end
    if owner.IsForbidden and owner:IsForbidden() then return false end
    if IsOPieFrame(owner) then return false end
    local ok, alpha = pcall(owner.GetEffectiveAlpha, owner)
    if not ok then return false end
    return Helpers.SafeToNumber(alpha, 1) < FADED_ALPHA_THRESHOLD
end

function TooltipProvider:IsTransientTooltipOwner(owner)
    if not owner then
        return false
    end
    return owner == UIParent or IsOPieFrame(owner)
end

local function IsCDMOwnerState(state)
    return state and (state.skinned or state._isQUICDMIcon or state._spellEntry)
end

local BUILTIN_CDM_KEYS = {
    essential = true,
    utility = true,
    buff = true,
    trackedBar = true,
}

local function GetCDMTooltipContextForKey(key)
    if type(key) ~= "string" then return "cdm" end
    if BUILTIN_CDM_KEYS[key] then return "cdm" end

    local core = GetCore and GetCore()
    local profile = core and core.db and core.db.profile
    local ncdm = profile and profile.ncdm
    local container = ncdm and ncdm.containers and ncdm.containers[key]
    if type(container) == "table" then
        if container.tooltipContext == "customTrackers" or container.containerType == "customBar" then
            return "customTrackers"
        end
    end

    return "cdm"
end

local MAX_CONTEXT_PARENT_DEPTH = 6
local frameChainScratch = {}

local function GetParentFrame(frame)
    if not frame or not frame.GetParent then
        return nil
    end
    local ok, parent = pcall(frame.GetParent, frame)
    if not ok or parent == frame then
        return nil
    end
    return parent
end

local function GetFrameChain(frame)
    wipe(frameChainScratch)
    local depth = 0
    while frame and depth < MAX_CONTEXT_PARENT_DEPTH do
        frameChainScratch[#frameChainScratch + 1] = frame
        if frame == UIParent then
            break
        end
        frame = GetParentFrame(frame)
        depth = depth + 1
    end
    return frameChainScratch
end

local function GetActionSlot(frame)
    if not frame then
        return nil
    end

    if frame.GetAttribute then
        local ok, actionSlot = pcall(frame.GetAttribute, frame, "action")
        if ok and actionSlot and not Helpers.IsSecretValue(actionSlot) then
            return actionSlot
        end
    end

    local actionSlot = frame.action
    if actionSlot and not Helpers.IsSecretValue(actionSlot) then
        return actionSlot
    end

    return nil
end

local function IsActionFrameName(name)
    if name == "" then
        return false
    end

    return strmatch(name, "ActionButton") or
        strmatch(name, "MultiBar") or
        strmatch(name, "PetActionButton") or
        strmatch(name, "StanceButton") or
        strmatch(name, "OverrideActionBar") or
        strmatch(name, "ExtraActionButton") or
        strmatch(name, "BT4Button") or
        strmatch(name, "DominosActionButton") or
        strmatch(name, "ElvUI_Bar") or
        strmatch(name, "^QUI_Bar%d+Button%d+$") or
        strmatch(name, "^QUI_PetButton%d+$") or
        strmatch(name, "^QUI_StanceButton%d+$") or
        strmatch(name, "^QUI_SpellFlyoutButton%d+$") or
        strmatch(name, "^SpellFlyoutPopupButton%d+$") or
        strmatch(name, "^SpellFlyoutButton%d+$")
end

local function IsItemFrameName(name)
    if name == "" then
        return false
    end

    return strmatch(name, "ContainerFrame") or
        strmatch(name, "BagSlot") or
        strmatch(name, "BankFrame") or
        strmatch(name, "ReagentBank") or
        strmatch(name, "BagItem") or
        strmatch(name, "Baganator") or
        strmatch(name, "^Character.+Slot$") or
        strmatch(name, "^Inspect.+Slot$")
end

local function IsUnitFrameName(frame, name)
    if not frame then
        return false
    end

    return frame.unit or
        strmatch(name, "UnitFrame") or
        strmatch(name, "PlayerFrame") or
        strmatch(name, "TargetFrame") or
        strmatch(name, "FocusFrame") or
        strmatch(name, "PartyMemberFrame") or
        strmatch(name, "CompactRaidFrame") or
        strmatch(name, "CompactPartyFrame") or
        strmatch(name, "NamePlate") or
        strmatch(name, "Quazii.*Frame") or
        strmatch(name, "^QUI_.*Frame$")
end

---------------------------------------------------------------------------
-- Context Detection
-- Determines what triggered the tooltip based on owner frame
---------------------------------------------------------------------------
function TooltipProvider:GetTooltipContext(owner)
    if not owner then return "npcs" end
    if owner.IsForbidden and owner:IsForbidden() then return "npcs" end
    if owner == WorldFrame then return "npcs" end
    if self:IsTransientTooltipOwner(owner) then return nil end

    local now = GetTime()
    local cached = contextCache[owner]
    if cached and (now - cached.time) < CONTEXT_CACHE_TTL then
        return cached.value ~= NIL_CONTEXT and cached.value or nil
    end

    local getIS = _G.QUI_GetIconState or _G.QUI_GetCDMIconState
    local getViewer = _G.QUI_GetCDMViewerFrame
    local chain = GetFrameChain(owner)

    for _, frame in ipairs(chain) do
        local state = getIS and getIS(frame)
        local entry = state and state._spellEntry
        local viewerType = entry and entry.viewerType
        if type(viewerType) == "string" and not BUILTIN_CDM_KEYS[viewerType] then
            local context = GetCDMTooltipContextForKey(viewerType)
            SetCachedContext(owner, context, now)
            return context
        end

        local cdmKey = frame._quiCdmKey
        if type(cdmKey) == "string" and not BUILTIN_CDM_KEYS[cdmKey] then
            local context = GetCDMTooltipContextForKey(cdmKey)
            SetCachedContext(owner, context, now)
            return context
        end

        if IsCDMOwnerState(state) then
            SetCachedContext(owner, "cdm", now)
            return "cdm"
        end

        if getViewer and (
            frame == getViewer("essential") or
            frame == getViewer("utility") or
            frame == getViewer("buffIcon") or
            frame == getViewer("buffBar")
        ) then
            SetCachedContext(owner, "cdm", now)
            return "cdm"
        end
    end

    for _, frame in ipairs(chain) do
        local frameName = GetFrameName(frame)
        if frame.__customTrackerIcon or
            frame._quiTooltipContext == "customTrackers" or
            frame.__quiTooltipContext == "customTrackers" or
            strmatch(frameName, "[Cc]ustomTracker") then
            SetCachedContext(owner, "customTrackers", now)
            return "customTrackers"
        end
    end

    for _, frame in ipairs(chain) do
        local actionSlot = GetActionSlot(frame)
        if actionSlot then
            local actionType = GetActionInfo(actionSlot)
            if actionType == "item" then
                SetCachedContext(owner, "items", now)
                return "items"
            end
            if actionType then
                SetCachedContext(owner, "abilities", now)
                return "abilities"
            end
        end

        if IsActionFrameName(GetFrameName(frame)) then
            SetCachedContext(owner, "abilities", now)
            return "abilities"
        end
    end

    for _, frame in ipairs(chain) do
        if IsItemFrameName(GetFrameName(frame)) then
            SetCachedContext(owner, "items", now)
            return "items"
        end
    end

    for _, frame in ipairs(chain) do
        if IsUnitFrameName(frame, GetFrameName(frame)) then
            SetCachedContext(owner, "frames", now)
            return "frames"
        end
    end

    SetCachedContext(owner, nil, now)
    return nil
end

---------------------------------------------------------------------------
-- Modifier Key Check
---------------------------------------------------------------------------
function TooltipProvider:IsModifierActive(modKey)
    if modKey == "SHIFT" then return IsShiftKeyDown() end
    if modKey == "CTRL" then return IsControlKeyDown() end
    if modKey == "ALT" then return IsAltKeyDown() end
    return false
end

---------------------------------------------------------------------------
-- Visibility Logic
---------------------------------------------------------------------------
function TooltipProvider:ShouldShowTooltip(context)
    local settings = self:GetSettings()
    if not settings or not settings.enabled then
        return true  -- Module disabled = default behavior
    end

    if settings.hideInCombat and InCombatLockdown() then
        if settings.combatKey and settings.combatKey ~= "NONE" then
            if self:IsModifierActive(settings.combatKey) then
                return true
            end
        end
        return false
    end

    local visibility = settings.visibility and settings.visibility[context]
    if not visibility then
        return true
    end

    if visibility == "SHOW" then
        return true
    elseif visibility == "HIDE" then
        return false
    else
        return self:IsModifierActive(visibility)
    end
end

---------------------------------------------------------------------------
-- Cursor Anchor Config
---------------------------------------------------------------------------
local CURSOR_ANCHOR_POINTS = {
    TOPLEFT = true, TOP = true, TOPRIGHT = true,
    LEFT = true, CENTER = true, RIGHT = true,
    BOTTOMLEFT = true, BOTTOM = true, BOTTOMRIGHT = true,
}

local DEFAULT_CURSOR_ANCHOR = "TOPLEFT"
local DEFAULT_CURSOR_OFFSET_X = 16
local DEFAULT_CURSOR_OFFSET_Y = -16

function TooltipProvider:GetCursorAnchorConfig(settings)
    local anchor = settings and settings.cursorAnchor
    if type(anchor) ~= "string" or not CURSOR_ANCHOR_POINTS[anchor] then
        anchor = DEFAULT_CURSOR_ANCHOR
    end
    local offsetX = tonumber(settings and settings.cursorOffsetX) or DEFAULT_CURSOR_OFFSET_X
    local offsetY = tonumber(settings and settings.cursorOffsetY) or DEFAULT_CURSOR_OFFSET_Y
    return anchor, offsetX, offsetY
end

function TooltipProvider:PositionTooltipAtCursor(tooltip, settings)
    if not tooltip then return end
    if tooltip.IsForbidden and tooltip:IsForbidden() then return end

    local cursorX, cursorY = GetCursorPosition()
    if not cursorX or not cursorY then return end

    -- Use cached scale (updated on UI_SCALE_CHANGED) to avoid calling
    -- GetEffectiveScale() during combat where it may return secret values.
    local core = GetCore and GetCore()
    local scale = cachedUIScale
    if core and type(core.uiscale) == "number" and core.uiscale > 0 then
        scale = core.uiscale
    end
    if scale <= 0 then
        scale = 1
    end
    local anchor, offsetX, offsetY = self:GetCursorAnchorConfig(settings)
    local x = (cursorX / scale) + offsetX
    local y = (cursorY / scale) + offsetY

    -- Snap the final tooltip rect to the pixel grid so the existing 1px border
    -- math in the skinning layer does not land on fractional screen coordinates.
    -- Use the cached UIParent scale path here rather than frame:GetEffectiveScale()
    -- so cursor anchoring stays combat-safe.
    if core and core.GetPixelPerfectScale and scale > 0 then
        local px = core:GetPixelPerfectScale() / scale
        if px > 0 then
            x = math.floor((x / px) + 0.5) * px
            y = math.floor((y / px) + 0.5) * px
        end
    end

    tooltip:ClearAllPoints()
    tooltip:SetPoint(anchor, UIParent, "BOTTOMLEFT", x, y)
end

---------------------------------------------------------------------------
-- TOOLTIP ANCHOR (fixed position when not cursor-anchored)
---------------------------------------------------------------------------

local tooltipAnchor = CreateFrame("Frame", "QUI_TooltipAnchor", UIParent)
tooltipAnchor:SetSize(200, 40)
tooltipAnchor:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", -200, 100)
tooltipAnchor:SetClampedToScreen(true)

--- Position the tooltip at the fixed anchor frame.
function TooltipProvider:PositionTooltipAtAnchor(tooltip, settings)
    if not tooltip then return end
    tooltip:ClearAllPoints()
    tooltip:SetPoint("BOTTOMRIGHT", tooltipAnchor, "BOTTOMRIGHT", 0, 0)
end

--- Legacy position helpers removed — frameAnchoring system handles positioning.
--- RestoreAnchorPosition kept as no-op for any remaining callers.
function TooltipProvider:RestoreAnchorPosition() end

---------------------------------------------------------------------------
-- INITIALIZATION
---------------------------------------------------------------------------

function TooltipProvider:InitializeEngine()
    if self.initialized then return end

    local QUICore = ns.Addon
    local engineName = "default"
    if QUICore and QUICore.db and QUICore.db.profile and QUICore.db.profile.tooltip then
        engineName = QUICore.db.profile.tooltip.engine or "default"
    end

    local engine = self.engines[engineName]
    if not engine then
        engine = self.engines["default"]
        engineName = "default"
    end

    if not engine then
        return
    end

    self.activeEngine = engine
    self.activeEngineName = engineName
    self.initialized = true

    if engine.Initialize then
        engine:Initialize()
    end

    -- Restore saved tooltip anchor position
    self:RestoreAnchorPosition()
end

---------------------------------------------------------------------------
-- ADDON_LOADED TRIGGER
---------------------------------------------------------------------------
local providerEventFrame = CreateFrame("Frame")
providerEventFrame:RegisterEvent("ADDON_LOADED")
providerEventFrame:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" and arg1 == ADDON_NAME then
        self:UnregisterEvent("ADDON_LOADED")
        TooltipProvider:InitializeEngine()
    end
end)

---------------------------------------------------------------------------
-- GLOBAL REFRESH
---------------------------------------------------------------------------
ns.QUI_RefreshTooltips = function()
    TooltipProvider:InvalidateCache()
    if TooltipProvider.activeEngine and TooltipProvider.activeEngine.Refresh then
        TooltipProvider.activeEngine:Refresh()
    end
end

---------------------------------------------------------------------------
-- NAMESPACE EXPORT
---------------------------------------------------------------------------
ns.TooltipProvider = TooltipProvider
