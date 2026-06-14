--[[
    QUI BigWigs Integration Module
    Anchors BigWigs normal/emphasized bars to QUI elements via proxy frames.
]]

local ADDON_NAME, ns = ...
local QUICore = ns.Addon
local UIKit = ns.UIKit
local Helpers = ns.Helpers

---------------------------------------------------------------------------
-- MODULE TABLE
---------------------------------------------------------------------------
local QUI_BigWigs = {}
ns.QUI_BigWigs = QUI_BigWigs

-- Pending combat/deferred updates
local pendingUpdate = false

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
-- PROXY FRAMES (via UIKit.CreateAnchorProxy)
---------------------------------------------------------------------------
local function BigWigsAnchorResolver(proxy, source)
    -- Prefer SetAllPoints for exact mirror; fall back to center-based positioning
    -- when the source frame restricts SetAllPoints (e.g. protected frames).
    local ok = pcall(function()
        proxy:ClearAllPoints()
        proxy:SetAllPoints(source)
    end)
    if not ok then
        pcall(function()
            local cx, cy = source:GetCenter()
            cx = Helpers.SafeValue(cx, nil)
            cy = Helpers.SafeValue(cy, nil)
            local ux, uy = UIParent:GetCenter()
            ux = Helpers.SafeValue(ux, nil)
            uy = Helpers.SafeValue(uy, nil)
            proxy:ClearAllPoints()
            if cx and cy and ux and uy then
                proxy:SetPoint("CENTER", UIParent, "CENTER", cx - ux, cy - uy)
            else
                proxy:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
            end
            local sw = Helpers.SafeValue(source:GetWidth(), 1)
            local sh = Helpers.SafeValue(source:GetHeight(), 1)
            proxy:SetSize(math.max(1, sw), math.max(1, sh))
        end)
    end
end

local function EnsureProxy(key, anchorFrame)
    local proxy = proxies[key]
    if proxy then
        proxy:SetSourceFrame(anchorFrame)
    else
        proxy = UIKit.CreateAnchorProxy(anchorFrame, {
            frameName = PROXY_NAMES[key],
            combatFreeze = false,
            mirrorVisibility = false,
            anchorResolver = BigWigsAnchorResolver,
        })
        proxies[key] = proxy
    end
    return proxy
end


local QueueRetry = ns.QUI_IntegrationShared.MakeQueueRetry("QUI_BigWigs")

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

local anchoredFramesHookInstalled = false
local function TryInstallAnchoredFramesHook()
    if anchoredFramesHookInstalled then
        return true
    end
    if not (ns.QUI_Anchoring and ns.QUI_Anchoring.RegisterAnchoredFramesPostHook) then
        return false
    end
    ns.QUI_Anchoring.RegisterAnchoredFramesPostHook("bigwigs", function()
        QUI_BigWigs:ApplyAllPositions()
    end)
    anchoredFramesHookInstalled = true
    return true
end

---------------------------------------------------------------------------
-- ANCHOR FRAME RESOLUTION
---------------------------------------------------------------------------
function QUI_BigWigs:GetAnchorFrame(anchorName)
    return ns.QUI_IntegrationShared.GetAnchorFrame(anchorName)
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

-- Resolve the Bars plugin + the position array for the given key, ensuring the
-- position array exists. Returns (bars, pos, positionKey) or nil.
local function ResolveBarsProfilePos(key)
    local bars = GetBarsPlugin()
    if not bars or not bars.db or not bars.db.profile then
        return nil
    end

    local profile = bars.db.profile
    local positionKey = (key == "emphasized") and "expPosition" or "normalPosition"
    if type(profile[positionKey]) ~= "table" then
        profile[positionKey] = {}
    end

    return bars, profile[positionKey], positionKey
end

local function ApplyBarsProfilePosition(key, cfg, proxyName)
    local bars, pos = ResolveBarsProfilePos(key)
    if not bars then
        return false
    end

    local db = GetDB()
    if db and type(db.backupPositions) ~= "table" then
        db.backupPositions = {}
    end

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
    local bars, pos, positionKey = ResolveBarsProfilePos(key)
    if not bars then
        return false
    end

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

    local proxy = EnsureProxy(key, anchorFrame)
    if not proxy then
        return
    end

    proxy:Sync()

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
function QUI_BigWigs:Initialize()
    if not self:IsAvailable() then
        return
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
