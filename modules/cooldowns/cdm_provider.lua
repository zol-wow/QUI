--[[
    QUI CDM Provider

    Thin bootstrap around the single CDM engine ("owned"). Phase B.3
    removed the engine-selection abstraction since there has only ever
    been one implementation — the owned engine. This file remains the
    place that:

      1. Wires _G.QUI_* globals from the engine so consumer modules can
         call them without reaching into the engine table directly.
      2. Publishes a frame resolver that works before the engine has
         finished initializing (Blizzard global fallback).
      3. Kicks off engine initialization on ADDON_LOADED when the CDM
         master toggle is enabled, inside the safe window where combat
         /reload hasn't yet locked protected frames.

    Load order: cdm_provider.lua → hud_visibility.lua → owned engine
    files. The owned engine calls SetEngine() at load time to hand its
    table over; the provider initializes it on ADDON_LOADED unless the
    profile has disabled CDM completely.
]]

local ADDON_NAME, ns = ...

---------------------------------------------------------------------------
-- PROVIDER STATE
---------------------------------------------------------------------------
local CDMProvider = {
    engine = nil,         -- the single engine table
    initialized = false,
    disabled = false,
    emptyFrames = {},
}

---------------------------------------------------------------------------
-- ENGINE REGISTRATION (single-engine; owned is the only implementation)
---------------------------------------------------------------------------

--- Hand the owned engine table to the provider. Called at file-load
--- time by cdm_containers.lua; initialization is deferred to
--- InitializeEngine() on ADDON_LOADED.
--- @param engine table  Engine table with contract methods (Initialize, Refresh, etc.)
function CDMProvider:SetEngine(engine)
    self.engine = engine
end

local function GetNCDMProfile()
    local addon = _G.QUI
    local db = addon and addon.db
    local profile = db and db.profile
    return profile and profile.ncdm or nil
end

function CDMProvider:IsMasterEnabled()
    local ncdm = GetNCDMProfile()
    return not ncdm or ncdm.enabled ~= false
end

function CDMProvider:IsDisabled()
    return self.disabled == true
end

function CDMProvider:IsRuntimeEnabled()
    return self:IsMasterEnabled() and not self:IsDisabled()
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
CDMProvider.BLIZZARD_FRAME_KEYS = BLIZZARD_FRAME_KEYS

function CDMProvider:GetViewerFrameNames()
    return BLIZZARD_FRAME_KEYS
end

--- Resolve a viewer key to a frame. Works before engine init via the
--- Blizzard global fallback.
function CDMProvider:GetViewerFrame(key)
    if self.disabled then return nil end

    local engine = self.engine
    if self.initialized and engine and engine.GetViewerFrame then
        return engine:GetViewerFrame(key)
    end
    local blizzName = BLIZZARD_FRAME_KEYS[key]
    return blizzName and _G[blizzName] or nil
end

--- Get all viewer frames for visibility control.
function CDMProvider:GetViewerFrames()
    if self.disabled then
        return self.emptyFrames
    end

    local engine = self.engine
    if self.initialized and engine and engine.GetViewerFrames then
        return engine:GetViewerFrames()
    end
    local frames = {}
    for _, blizzName in pairs(BLIZZARD_FRAME_KEYS) do
        if _G[blizzName] then
            frames[#frames + 1] = _G[blizzName]
        end
    end
    return frames
end

---------------------------------------------------------------------------
-- GLOBAL WIRING
---------------------------------------------------------------------------

-- Wire _G.QUI_* globals from the engine so consumer modules don't need
-- to reach into the engine table directly.
local GLOBAL_WIRE_MAP = {
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

local function DisableOwnedRuntime()
    local engine = CDMProvider.engine
    if engine and engine.DisableRuntime then
        engine:DisableRuntime()
    end
    if ns.CDMSpellData and ns.CDMSpellData.DisableRuntime then
        ns.CDMSpellData:DisableRuntime()
    end
    if ns.CDMIcons and ns.CDMIcons.DisableRuntime then
        ns.CDMIcons:DisableRuntime()
    end
    if ns._OwnedGlows and ns._OwnedGlows.DisableRuntime then
        ns._OwnedGlows.DisableRuntime()
    end
    if ns._OwnedHighlighter and ns._OwnedHighlighter.DisableRuntime then
        ns._OwnedHighlighter.DisableRuntime()
    end
end

function CDMProvider:DisableRuntime()
    self.disabled = true
    DisableOwnedRuntime()
    if ns.InvalidateCDMFrameCache then
        ns.InvalidateCDMFrameCache()
    end
end

---------------------------------------------------------------------------
-- INITIALIZATION
---------------------------------------------------------------------------

function CDMProvider:InitializeEngine()
    if self.initialized then return end
    local engine = self.engine
    if not engine then
        return  -- Engine not registered yet
    end

    if not self:IsMasterEnabled() then
        self:DisableRuntime()
        return
    end

    self.disabled = false
    self.initialized = true

    if engine.Initialize then
        engine:Initialize()
    end

    WireGlobals(engine)

    if ns.Registry then
        ns.Registry:Register("ncdm", {
            refresh = _G.QUI_RefreshNCDM,
            priority = 10,
            group = "cooldowns",
            importCategories = { "cdm" },
        })
    end

    -- Backward compat namespace exports
    if engine.GetNCDM then
        ns.NCDM = engine:GetNCDM()
    end
    if engine.GetCustomCDM then
        ns.CustomCDM = engine:GetCustomCDM()
    end

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

_G.QUI_IsCDMMasterEnabled = function()
    return CDMProvider:IsRuntimeEnabled()
end

---------------------------------------------------------------------------
-- ADDON_LOADED TRIGGER
---------------------------------------------------------------------------
-- Initialize during ADDON_LOADED for our own addon. This leverages the
-- safe window where InCombatLockdown() returns false even during a combat
-- /reload, allowing container creation and layout to complete before
-- combat lockdown kicks in.
local providerEventFrame = CreateFrame("Frame")
providerEventFrame:RegisterEvent("ADDON_LOADED")
providerEventFrame:SetScript("OnEvent", function(self, event, addonName)
    if event == "ADDON_LOADED" and addonName == ADDON_NAME then
        self:UnregisterEvent("ADDON_LOADED")
        CDMProvider:InitializeEngine()
    end
end)

---------------------------------------------------------------------------
-- NAMESPACE EXPORT
---------------------------------------------------------------------------
ns.CDMProvider = CDMProvider
