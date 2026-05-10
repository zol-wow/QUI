local ADDON_NAME, ns = ...

---------------------------------------------------------------------------
-- CDM Layout Mode Registration
--
-- Registers owned CDM containers with QUI layout mode. Container creation,
-- frame writes, and layout math remain in their owning modules.
---------------------------------------------------------------------------

local CDMLayoutMode = {}
ns.CDMLayoutMode = CDMLayoutMode

local C_Timer = C_Timer
local ipairs = ipairs
local pairs = pairs

local CDM_ELEMENTS = {
    { key = "cdmEssential", label = "CDM Essential", order = 1 },
    { key = "cdmUtility", label = "CDM Utility", order = 2 },
    { key = "buffIcon", label = "Buff Icons", order = 3 },
    { key = "buffBar", label = "Buff Bars", order = 4 },
}

local CDM_KEY_MAP = {
    cdmEssential = "essential",
    cdmUtility = "utility",
    buffIcon = "buff",
    buffBar = "trackedBar",
}

local CDM_VIEWER_MAP = {
    cdmEssential = "essential",
    cdmUtility = "utility",
    buffIcon = "buffIcon",
    buffBar = "buffBar",
}

local function GetNcdmDB()
    local core = ns.Helpers and ns.Helpers.GetCore and ns.Helpers.GetCore()
    return core and core.db and core.db.profile and core.db.profile.ncdm
end

local function GetCDMDB(cdmKey)
    local ncdm = GetNcdmDB()
    if not ncdm then return nil end
    local dbKey = CDM_KEY_MAP[cdmKey]
    if ncdm[dbKey] then
        return ncdm[dbKey]
    end
    if ncdm.containers and ncdm.containers[dbKey] then
        return ncdm.containers[dbKey]
    end
    return nil
end

local function RefreshCDM()
    if _G.QUI_RefreshCDMVisibility then _G.QUI_RefreshCDMVisibility() end
    if _G.QUI_RefreshCustomTrackersVisibility then _G.QUI_RefreshCustomTrackersVisibility() end
end

local function ShowCDMReloadPrompt(enabled)
    local QUI = _G.QUI
    local GUI = QUI and QUI.GUI
    if not (GUI and GUI.ShowConfirmation) then
        return
    end

    GUI:ShowConfirmation({
        title = "Reload UI?",
        message = enabled
            and "Enabling Cooldown Manager requires a UI reload to hand cooldown viewers back to QUI."
            or "Disabling Cooldown Manager requires a UI reload to fully hand cooldown viewers back to the default UI.",
        acceptText = "Reload",
        cancelText = "Later",
        onAccept = function()
            if QUI and QUI.SafeReload then
                QUI:SafeReload()
            end
        end,
    })
end

local function GetViewerFrame(elementKey)
    local viewerKey = CDM_VIEWER_MAP[elementKey]
    return viewerKey and _G.QUI_GetCDMViewerFrame and _G.QUI_GetCDMViewerFrame(viewerKey)
end

local function SetAllGameplayHidden(hide)
    for _, info in ipairs(CDM_ELEMENTS) do
        local f = GetViewerFrame(info.key)
        if f then
            if hide then f:Hide() else f:Show() end
        end
    end
end

local function GetFirstViewerFrame()
    for _, info in ipairs(CDM_ELEMENTS) do
        local f = GetViewerFrame(info.key)
        if f then return f end
    end
    return nil
end

local function GetCachedContainerSize(elementKey)
    local ncdm = GetNcdmDB()
    if not ncdm then return nil, nil end
    if elementKey == "cdmEssential" then
        return ncdm._lastEssentialWidth, ncdm._lastEssentialHeight
    elseif elementKey == "cdmUtility" then
        return ncdm._lastUtilityWidth, ncdm._lastUtilityHeight
    end
    return nil, nil
end

local function RegisterMasterElement(um)
    um:RegisterElement({
        key = "cdm",
        label = "Cooldown Manager",
        group = "Cooldown Manager & Custom Tracker Bars",
        order = -1,
        isOwned = true,
        noHandle = true,
        isEnabled = function()
            local ncdm = GetNcdmDB()
            return ncdm and ncdm.enabled ~= false
        end,
        setEnabled = function(val)
            local ncdm = GetNcdmDB()
            local oldEnabled = ncdm and ncdm.enabled ~= false
            local enabled = val ~= false
            if ncdm then ncdm.enabled = val end
            if ns.CDMSpellData and ns.CDMSpellData.SyncCooldownViewerCVar then
                ns.CDMSpellData:SyncCooldownViewerCVar()
            end
            RefreshCDM()
            if not enabled and ns.CDMProvider and ns.CDMProvider.DisableRuntime then
                ns.CDMProvider:DisableRuntime()
            end
            if oldEnabled ~= nil and oldEnabled ~= enabled then
                ShowCDMReloadPrompt(enabled)
            end
        end,
        setGameplayHidden = SetAllGameplayHidden,
        getFrame = GetFirstViewerFrame,
    })
end

local function RegisterBuiltInElement(um, info)
    um:RegisterElement({
        key = info.key,
        label = info.label,
        group = "Cooldown Manager & Custom Tracker Bars",
        order = info.order,
        isOwned = true,
        isEnabled = function()
            local ncdm = GetNcdmDB()
            if not ncdm or ncdm.enabled == false then return false end
            local db = GetCDMDB(info.key)
            return db and db.enabled ~= false
        end,
        setEnabled = function(val)
            local db = GetCDMDB(info.key)
            if db then db.enabled = val end
            RefreshCDM()
        end,
        setGameplayHidden = function(hide)
            local f = GetViewerFrame(info.key)
            if f then
                if hide then f:Hide() else f:Show() end
            end
        end,
        getFrame = function()
            return GetViewerFrame(info.key)
        end,
        getSize = function()
            local f = GetViewerFrame(info.key)
            if f and f.GetSize then
                local fw, fh = f.GetSize(f)
                if fw and fh and fw > 2 and fh > 2 then
                    return fw, fh
                end
            end
            local cw, ch = GetCachedContainerSize(info.key)
            if cw and ch and cw > 2 and ch > 2 then
                return cw, ch
            end
            return nil, nil
        end,
    })
end

local function RegisterCustomElements()
    local containersAPI = ns.CDMContainers
    if not (containersAPI and containersAPI.RegisterDynamicLayoutElement) then
        return
    end

    local ncdm = GetNcdmDB()
    if ncdm and ncdm.containers then
        for key, settings in pairs(ncdm.containers) do
            if not settings.builtIn then
                containersAPI.RegisterDynamicLayoutElement(key, settings)
            end
        end
    end
end

function CDMLayoutMode.RegisterLayoutModeElements()
    local um = ns.QUI_LayoutMode
    if not um then return false end

    RegisterMasterElement(um)
    for _, info in ipairs(CDM_ELEMENTS) do
        RegisterBuiltInElement(um, info)
    end
    RegisterCustomElements()
    return true
end

function CDMLayoutMode.ScheduleRegistration()
    local retryCount = 0
    local function attempt()
        if CDMLayoutMode.RegisterLayoutModeElements() then
            return
        end
        if retryCount < 20 then
            retryCount = retryCount + 1
            C_Timer.After(0.5, attempt)
        end
    end
    C_Timer.After(2, attempt)
end

CDMLayoutMode.ScheduleRegistration()
