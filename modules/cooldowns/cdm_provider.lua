--[[
    QUI CDM Provider
    Abstraction layer that lets multiple CDM engine implementations coexist.
    Only one engine initializes at runtime based on db.profile.ncdm.engine.

    Load order: cdm_provider.lua → hud_visibility.lua → engine files
    Engine files call RegisterEngine() at load time.
    Provider calls Initialize() on the selected engine after PLAYER_LOGIN.
]]

local ADDON_NAME, ns = ...
local Helpers = ns.Helpers

---------------------------------------------------------------------------
-- PROVIDER STATE
---------------------------------------------------------------------------
local CDMProvider = {
    engines = {},           -- name → engine table
    activeEngine = nil,     -- the initialized engine table
    activeEngineName = nil, -- "classic" or "owned"
    initialized = false,
}

---------------------------------------------------------------------------
-- ENGINE REGISTRATION
---------------------------------------------------------------------------

--- Register a CDM engine implementation.
--- @param name string  Engine identifier ("classic" or "owned")
--- @param engine table  Table with contract methods (Initialize, Refresh, etc.)
function CDMProvider:RegisterEngine(name, engine)
    self.engines[name] = engine
end

---------------------------------------------------------------------------
-- FRAME RESOLVER (available immediately, before engine init)
---------------------------------------------------------------------------

-- Blizzard frame name fallbacks for pre-init resolution
local BLIZZARD_FRAME_KEYS = {
    essential = "EssentialCooldownViewer",
    utility   = "UtilityCooldownViewer",
    buffIcon  = "BuffIconCooldownViewer",
    buffBar   = "BuffBarCooldownViewer",
}

--- Resolve a viewer key to a frame.
--- Works before engine init via Blizzard global fallback.
--- @param key string  One of "essential", "utility", "buffIcon", "buffBar"
--- @return Frame|nil
function CDMProvider:GetViewerFrame(key)
    -- Active engine gets priority
    if self.activeEngine and self.activeEngine.GetViewerFrame then
        return self.activeEngine:GetViewerFrame(key)
    end
    -- Fallback to well-known Blizzard globals
    local blizzName = BLIZZARD_FRAME_KEYS[key]
    return blizzName and _G[blizzName] or nil
end

--- Get all viewer frames for visibility control.
--- @return table  Array of frame references
function CDMProvider:GetViewerFrames()
    if self.activeEngine and self.activeEngine.GetViewerFrames then
        return self.activeEngine:GetViewerFrames()
    end
    -- Fallback: collect from Blizzard globals
    local frames = {}
    for _, blizzName in pairs(BLIZZARD_FRAME_KEYS) do
        if _G[blizzName] then
            frames[#frames + 1] = _G[blizzName]
        end
    end
    return frames
end

--- Get the name of the active engine (or nil if not yet initialized).
--- @return string|nil
function CDMProvider:GetActiveEngineName()
    return self.activeEngineName
end

---------------------------------------------------------------------------
-- GLOBAL WIRING
---------------------------------------------------------------------------

-- Wire _G.QUI_* globals from the active engine.
-- These are the integration points that consumer modules call.
local GLOBAL_WIRE_MAP = {
    -- method name → global name
    { method = "Refresh",                global = "QUI_RefreshNCDM" },
    { method = "ApplyUtilityAnchor",     global = "QUI_ApplyUtilityAnchor" },
    { method = "IsSelectionKeepVisible", global = "QUI_IsSelectionKeepVisible" },
    { method = "GetViewerState",         global = "QUI_GetCDMViewerState" },
    { method = "SetViewerBounds",        global = "QUI_SetCDMViewerBounds" },
    { method = "RefreshViewerFromBounds",global = "QUI_RefreshCDMViewerFromBounds" },
    { method = "GetIconState",           global = "QUI_GetIconState" },
    { method = "ClearIconState",         global = "QUI_ClearIconState" },
    { method = "IsHUDAnchoredToCDM",     global = "QUI_IsHUDAnchoredToCDM" },
    { method = "GetHUDMinWidthSettings", global = "QUI_GetHUDMinWidthSettings" },
}

local function WireGlobals(engine)
    for _, entry in ipairs(GLOBAL_WIRE_MAP) do
        if engine[entry.method] then
            _G[entry.global] = function(...)
                return engine[entry.method](engine, ...)
            end
        end
    end
end

---------------------------------------------------------------------------
-- INITIALIZATION
---------------------------------------------------------------------------

function CDMProvider:InitializeEngine()
    if self.initialized then return end

    -- Read engine selection from profile
    local QUICore = ns.Addon
    local engineName = "owned"
    if QUICore and QUICore.db and QUICore.db.profile and QUICore.db.profile.ncdm then
        engineName = QUICore.db.profile.ncdm.engine or "owned"
    end

    local engine = self.engines[engineName]
    if not engine then
        -- Fallback to classic if selected engine isn't registered
        engine = self.engines["classic"]
        engineName = "classic"
    end

    if not engine then
        return  -- No engines registered at all
    end

    self.activeEngine = engine
    self.activeEngineName = engineName
    self.initialized = true

    -- Initialize the engine
    if engine.Initialize then
        engine:Initialize()
    end

    -- Wire globals from the active engine (only for globals the engine provides)
    WireGlobals(engine)

    -- Wire ns.NCDM for backward compat
    if engine.GetNCDM then
        ns.NCDM = engine:GetNCDM()
    end

    -- Wire ns.CustomCDM for backward compat
    if engine.GetCustomCDM then
        ns.CustomCDM = engine:GetCustomCDM()
    end

    -- Invalidate visibility frame cache now that engine is ready
    if ns.InvalidateCDMFrameCache then
        ns.InvalidateCDMFrameCache()
    end
end

---------------------------------------------------------------------------
-- GLOBAL FRAME RESOLVER
---------------------------------------------------------------------------
-- Available immediately for consumer modules to use, even before engine init.
_G.QUI_GetCDMViewerFrame = function(key)
    return CDMProvider:GetViewerFrame(key)
end

---------------------------------------------------------------------------
-- PLAYER_LOGIN TRIGGER
---------------------------------------------------------------------------
-- Initialize the selected engine shortly after login (matches classic timing).
local providerEventFrame = CreateFrame("Frame")
providerEventFrame:RegisterEvent("PLAYER_LOGIN")
providerEventFrame:SetScript("OnEvent", function(self, event)
    if event == "PLAYER_LOGIN" then
        self:UnregisterEvent("PLAYER_LOGIN")
        -- Delay slightly to match the original cdm_viewer.lua timing
        C_Timer.After(0.1, function()
            CDMProvider:InitializeEngine()
        end)
    end
end)

---------------------------------------------------------------------------
-- NAMESPACE EXPORT
---------------------------------------------------------------------------
ns.CDMProvider = CDMProvider
