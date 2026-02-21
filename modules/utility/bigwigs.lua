--[[
    QUI BigWigs Integration Module
    Anchors BigWigs normal/emphasized bars to QUI elements via proxy frames.
]]

local ADDON_NAME, ns = ...
local QUICore = ns.Addon

---------------------------------------------------------------------------
-- MODULE TABLE
---------------------------------------------------------------------------
local QUI_BigWigs = {}
ns.QUI_BigWigs = QUI_BigWigs

-- Pending combat/deferred updates
local pendingUpdate = false
local retryTimer = nil

-- Hook install guard
local anchoredFramesHookInstalled = false

-- Proxy frames for BigWigs custom anchor points
local PROXY_NAMES = {
    normal = "QUI_BigWigs_NormalAnchorProxy",
    emphasized = "QUI_BigWigs_EmphasizedAnchorProxy",
}

local proxies = {}
local originalPositions = {}

---------------------------------------------------------------------------
-- DATABASE ACCESS
---------------------------------------------------------------------------
local function GetDB()
    if QUICore and QUICore.db and QUICore.db.profile and QUICore.db.profile.bigWigs then
        return QUICore.db.profile.bigWigs
    end
    return nil
end

---------------------------------------------------------------------------
-- BIGWIGS AVAILABILITY
---------------------------------------------------------------------------
local function GetBarsPlugin()
    if type(BigWigs) ~= "table" or type(BigWigs.GetPlugin) ~= "function" then
        return nil
    end

    local ok, plugin = pcall(BigWigs.GetPlugin, BigWigs, "Bars", true)
    if ok then
        return plugin
    end

    return nil
end

function QUI_BigWigs:IsAvailable()
    if type(BigWigsLoader) == "table" and type(BigWigsLoader.RegisterMessage) == "function" then
        return true
    end
    if type(BigWigs) == "table" and type(BigWigs.GetPlugin) == "function" then
        return true
    end
    if C_AddOns and C_AddOns.IsAddOnLoaded then
        return C_AddOns.IsAddOnLoaded("BigWigs") or C_AddOns.IsAddOnLoaded("BigWigs_Core")
    end
    return false
end

---------------------------------------------------------------------------
-- PROXY FRAMES
---------------------------------------------------------------------------
local function EnsureProxyFrame(key)
    local frameName = PROXY_NAMES[key]
    if not frameName then
        return nil
    end

    local frame = proxies[key] or _G[frameName]
    if not frame then
        frame = CreateFrame("Frame", frameName, UIParent)
        frame:SetSize(1, 1)
        frame:Show()
    end

    proxies[key] = frame
    return frame
end

function QUI_BigWigs:GetProxyFrame(key)
    return proxies[key] or _G[PROXY_NAMES[key]]
end

local function SyncProxyToAnchor(proxy, anchorFrame)
    if not proxy or not anchorFrame then
        return false
    end

    local ok = pcall(function()
        proxy:ClearAllPoints()
        proxy:SetAllPoints(anchorFrame)
    end)
    if ok then
        return true
    end

    -- Fallback for frames that do not permit SetAllPoints linkage.
    ok = pcall(function()
        local cx, cy = anchorFrame:GetCenter()
        local ux, uy = UIParent:GetCenter()
        proxy:ClearAllPoints()
        if cx and cy and ux and uy then
            proxy:SetPoint("CENTER", UIParent, "CENTER", cx - ux, cy - uy)
        else
            proxy:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
        end
        proxy:SetSize(math.max(1, anchorFrame:GetWidth() or 1), math.max(1, anchorFrame:GetHeight() or 1))
    end)

    return ok
end

local function QueueRetry()
    if retryTimer then
        return
    end
    retryTimer = C_Timer.NewTimer(1.0, function()
        retryTimer = nil
        if ns.QUI_BigWigs then
            ns.QUI_BigWigs:ApplyAllPositions()
        end
    end)
end

local function ClonePosition(pos)
    if type(pos) ~= "table" then
        return nil
    end
    return {
        pos[1],
        pos[2],
        pos[3],
        pos[4],
        pos[5],
    }
end

local function TryInstallAnchoredFramesHook()
    if anchoredFramesHookInstalled then
        return true
    end

    local previousUpdateAnchoredFrames = _G.QUI_UpdateAnchoredFrames
    if not previousUpdateAnchoredFrames then
        return false
    end

    _G.QUI_UpdateAnchoredFrames = function(...)
        previousUpdateAnchoredFrames(...)
        QUI_BigWigs:ApplyAllPositions()
    end
    anchoredFramesHookInstalled = true
    return true
end

---------------------------------------------------------------------------
-- ANCHOR FRAME RESOLUTION
---------------------------------------------------------------------------
function QUI_BigWigs:GetAnchorFrame(anchorName)
    if not anchorName or anchorName == "disabled" then
        return nil
    end

    -- Hardcoded QUI element map
    if anchorName == "essential" then
        return _G["EssentialCooldownViewer"]
    elseif anchorName == "utility" then
        return _G["UtilityCooldownViewer"]
    elseif anchorName == "primary" then
        return QUICore and QUICore.powerBar
    elseif anchorName == "secondary" then
        return QUICore and QUICore.secondaryPowerBar
    elseif anchorName == "playerCastbar" then
        return ns.QUI_Castbar and ns.QUI_Castbar.castbars and ns.QUI_Castbar.castbars["player"]
    elseif anchorName == "playerFrame" then
        return ns.QUI_UnitFrames and ns.QUI_UnitFrames.frames and ns.QUI_UnitFrames.frames.player
    elseif anchorName == "targetFrame" then
        return ns.QUI_UnitFrames and ns.QUI_UnitFrames.frames and ns.QUI_UnitFrames.frames.target
    end

    -- Registry fallback
    if ns.QUI_Anchoring and ns.QUI_Anchoring.GetAnchorTarget then
        return ns.QUI_Anchoring:GetAnchorTarget(anchorName)
    end

    return nil
end

---------------------------------------------------------------------------
-- ANCHOR OPTIONS FOR DROPDOWNS
---------------------------------------------------------------------------
function QUI_BigWigs:BuildAnchorOptions()
    local options = {
        {value = "disabled", text = "Disabled"},
        {value = "essential", text = "Essential Cooldowns"},
        {value = "utility", text = "Utility Cooldowns"},
        {value = "primary", text = "Primary Resource Bar"},
        {value = "secondary", text = "Secondary Resource Bar"},
        {value = "playerCastbar", text = "Player Castbar"},
        {value = "playerFrame", text = "Player Frame"},
        {value = "targetFrame", text = "Target Frame"},
    }

    if ns.QUI_Anchoring and ns.QUI_Anchoring.anchorTargets then
        for name, data in pairs(ns.QUI_Anchoring.anchorTargets) do
            if name ~= "disabled" and name ~= "essential" and name ~= "utility"
                and name ~= "primary" and name ~= "secondary" and name ~= "playerCastbar"
                and name ~= "playerFrame" and name ~= "targetFrame"
            then
                local displayName = data.options and data.options.displayName or name
                displayName = displayName:gsub("^%l", string.upper)
                displayName = displayName:gsub("([a-z])([A-Z])", "%1 %2")
                table.insert(options, {value = name, text = displayName})
            end
        end
    end

    return options
end

---------------------------------------------------------------------------
-- APPLY TO BIGWIGS
---------------------------------------------------------------------------
local function TriggerBigWigsProfileUpdate()
    -- Preferred path: loader callback bus
    if type(BigWigsLoader) == "table" and type(BigWigsLoader.SendMessage) == "function" then
        local ok = pcall(BigWigsLoader.SendMessage, BigWigsLoader, "BigWigs_ProfileUpdate")
        if ok then
            return true
        end
    end

    -- Fallback path: Bars plugin callback bus
    local bars = GetBarsPlugin()
    if bars and type(bars.SendMessage) == "function" then
        local ok = pcall(bars.SendMessage, bars, "BigWigs_ProfileUpdate")
        if ok then
            return true
        end
    end

    return false
end

local function ApplyBarsProfilePosition(key, cfg, proxyName)
    local bars = GetBarsPlugin()
    if not bars or not bars.db or not bars.db.profile then
        return false
    end

    local profile = bars.db.profile
    local positionKey = (key == "emphasized") and "expPosition" or "normalPosition"
    if type(profile[positionKey]) ~= "table" then
        profile[positionKey] = {}
    end

    local db = GetDB()
    if db and type(db.backupPositions) ~= "table" then
        db.backupPositions = {}
    end

    local pos = profile[positionKey]

    -- Cache the user's pre-QUI position once so disable can restore it.
    if not originalPositions[key] and pos[5] ~= proxyName then
        originalPositions[key] = ClonePosition(pos)
    end
    if db and not db.backupPositions[key] and pos[5] ~= proxyName then
        db.backupPositions[key] = ClonePosition(pos)
    end

    pos[1] = cfg.sourcePoint or "TOP"
    pos[2] = cfg.targetPoint or "BOTTOM"
    pos[3] = cfg.offsetX or 0
    pos[4] = cfg.offsetY or -5
    pos[5] = proxyName

    return TriggerBigWigsProfileUpdate()
end

local function RestoreBarsProfilePosition(key, proxyName)
    local bars = GetBarsPlugin()
    if not bars or not bars.db or not bars.db.profile then
        return false
    end

    local profile = bars.db.profile
    local positionKey = (key == "emphasized") and "expPosition" or "normalPosition"
    if type(profile[positionKey]) ~= "table" then
        profile[positionKey] = {}
    end
    local pos = profile[positionKey]
    local db = GetDB()
    local dbBackup = db and db.backupPositions and db.backupPositions[key]

    local source = originalPositions[key]
    if not source then
        source = dbBackup
    end
    if not source then
        source = bars.defaultDB and bars.defaultDB[positionKey]
    end

    if source and type(source) == "table" then
        pos[1] = source[1]
        pos[2] = source[2]
        pos[3] = source[3]
        pos[4] = source[4]
        pos[5] = source[5]
    elseif pos[5] == proxyName then
        -- Fallback away from our proxy when no source/default is known.
        pos[1] = "CENTER"
        pos[2] = "CENTER"
        pos[3] = 0
        pos[4] = 0
        pos[5] = "UIParent"
    else
        return true
    end

    return TriggerBigWigsProfileUpdate()
end

---------------------------------------------------------------------------
-- POSITIONING
---------------------------------------------------------------------------
function QUI_BigWigs:ApplyPosition(key)
    local db = GetDB()
    if not db or not db[key] then
        return
    end

    local cfg = db[key]
    local proxyName = PROXY_NAMES[key]
    if not cfg.enabled or cfg.anchorTo == "disabled" then
        if not RestoreBarsProfilePosition(key, proxyName) then
            pendingUpdate = true
            QueueRetry()
        end
        return
    end

    local anchorFrame = self:GetAnchorFrame(cfg.anchorTo)
    if not anchorFrame then
        pendingUpdate = true
        QueueRetry()
        return
    end

    local proxy = EnsureProxyFrame(key)
    if not proxy then
        return
    end

    if not SyncProxyToAnchor(proxy, anchorFrame) then
        pendingUpdate = true
        QueueRetry()
        return
    end

    if not ApplyBarsProfilePosition(key, cfg, proxy:GetName()) then
        pendingUpdate = true
        QueueRetry()
    end
end

function QUI_BigWigs:ApplyAllPositions()
    TryInstallAnchoredFramesHook()
    self:ApplyPosition("normal")
    self:ApplyPosition("emphasized")
end

---------------------------------------------------------------------------
-- INITIALIZE
---------------------------------------------------------------------------
local initialized = false

function QUI_BigWigs:Initialize()
    if not self:IsAvailable() then
        return
    end

    if not initialized then
        initialized = true
    end

    self:ApplyAllPositions()
end

---------------------------------------------------------------------------
-- EVENT HANDLING
---------------------------------------------------------------------------
local eventFrame = CreateFrame("Frame")

eventFrame:SetScript("OnEvent", function(_, event, arg1)
    if event == "PLAYER_ENTERING_WORLD" then
        C_Timer.After(1.0, function()
            QUI_BigWigs:Initialize()
        end)
    elseif event == "ADDON_LOADED" and (arg1 == "BigWigs" or arg1 == "BigWigs_Core" or arg1 == "BigWigs_Plugins") then
        C_Timer.After(1.0, function()
            QUI_BigWigs:Initialize()
        end)
    elseif event == "PLAYER_REGEN_ENABLED" and pendingUpdate then
        pendingUpdate = false
        C_Timer.After(0.1, function()
            QUI_BigWigs:ApplyAllPositions()
        end)
    end
end)

eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
