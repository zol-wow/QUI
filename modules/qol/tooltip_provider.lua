--[[
    QUI Tooltip Provider
    Abstraction layer for the tooltip engine.
    Load order: tooltip_provider.lua → tooltip_classic.lua
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
    activeEngineName = nil, -- "classic"
    initialized = false,
}

---------------------------------------------------------------------------
-- ENGINE REGISTRATION
---------------------------------------------------------------------------

--- Register a tooltip engine implementation.
--- @param name string  Engine identifier ("classic")
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
-- SHARED UTILITIES (engine-agnostic, used by both engines)
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
local MOUSE_FRAME_CACHE_TTL = 0.2  -- 200ms cache

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
    return focus:IsVisible()
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
    local alpha = Helpers.SafeToNumber(owner:GetEffectiveAlpha(), 1)
    return alpha < FADED_ALPHA_THRESHOLD
end

---------------------------------------------------------------------------
-- Context Detection
-- Determines what triggered the tooltip based on owner frame
---------------------------------------------------------------------------
function TooltipProvider:GetTooltipContext(owner)
    if not owner then return "npcs" end
    if owner.IsForbidden and owner:IsForbidden() then return "npcs" end

    -- CDM: Check for skinned CDM icons
    local getIS = _G.QUI_GetCDMIconState
    local ownerIS = getIS and getIS(owner)
    if ownerIS and ownerIS.skinned then
        return "cdm"
    end

    local parent = owner:GetParent()
    if parent then
        local parentIS = getIS and getIS(parent)
        if parentIS and parentIS.skinned then
            return "cdm"
        end
        local getViewer = _G.QUI_GetCDMViewerFrame
        if getViewer and (
           parent == getViewer("essential") or
           parent == getViewer("utility") or
           parent == getViewer("buffIcon") or
           parent == getViewer("buffBar")) then
            return "cdm"
        end
    end

    -- Custom Trackers
    if owner.__customTrackerIcon then
        return "customTrackers"
    end

    local name = owner:GetName() or ""

    -- Abilities: action button patterns
    if strmatch(name, "ActionButton") or
       strmatch(name, "MultiBar") or
       strmatch(name, "PetActionButton") or
       strmatch(name, "StanceButton") or
       strmatch(name, "OverrideActionBar") or
       strmatch(name, "ExtraActionButton") or
       strmatch(name, "BT4Button") or
       strmatch(name, "DominosActionButton") or
       strmatch(name, "ElvUI_Bar") then
        local actionSlot = owner:GetAttribute("action")
        if actionSlot and not Helpers.IsSecretValue(actionSlot) then
            local actionType = GetActionInfo(actionSlot)
            if actionType == "item" then
                return "items"
            end
        end
        return "abilities"
    end

    -- Items: container/bag patterns
    if strmatch(name, "ContainerFrame") or
       strmatch(name, "BagSlot") or
       strmatch(name, "BankFrame") or
       strmatch(name, "ReagentBank") or
       strmatch(name, "BagItem") or
       strmatch(name, "Baganator") then
        return "items"
    end

    if parent then
        local parentNameItems = parent:GetName() or ""
        if strmatch(parentNameItems, "ContainerFrame") or
           strmatch(parentNameItems, "BankFrame") or
           strmatch(parentNameItems, "Baganator") then
            return "items"
        end
    end

    -- Frames: unit frame patterns
    if owner.unit or
       strmatch(name, "UnitFrame") or
       strmatch(name, "PlayerFrame") or
       strmatch(name, "TargetFrame") or
       strmatch(name, "FocusFrame") or
       strmatch(name, "PartyMemberFrame") or
       strmatch(name, "CompactRaidFrame") or
       strmatch(name, "CompactPartyFrame") or
       strmatch(name, "NamePlate") or
       strmatch(name, "Quazii.*Frame") then
        return "frames"
    end

    return "npcs"
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
-- INITIALIZATION
---------------------------------------------------------------------------

function TooltipProvider:InitializeEngine()
    if self.initialized then return end

    local QUICore = ns.Addon
    local engineName = "classic"
    if QUICore and QUICore.db and QUICore.db.profile and QUICore.db.profile.tooltip then
        engineName = QUICore.db.profile.tooltip.engine or "classic"
    end

    local engine = self.engines[engineName]
    if not engine then
        engine = self.engines["classic"]
        engineName = "classic"
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
