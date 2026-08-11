local ADDON_NAME, ns = ...

local QUI_GF = ns.QUI_GroupFrames

local pairs = pairs
local type = type
local IsInRaid = IsInRaid
local C_Timer = C_Timer

local registered = false
local refreshCb
local notifyScheduled = false

local provider = {
    Name = "QUI",

    GetFrames = function()
        local out = {}
        if not (QUI_GF and QUI_GF.IsEnabled and QUI_GF:IsEnabled()) then
            return out
        end
        if IsInRaid() then
            return out
        end
        local map = QUI_GF.unitFrameMap
        if map then
            for unit, list in pairs(map) do
                if type(unit) == "string" and not unit:find("^raid%d") then
                    for i = 1, #list do
                        out[#out + 1] = list[i]
                    end
                end
            end
        end
        return out
    end,

    RegisterRefreshFrames = function(cb)
        refreshCb = cb
    end,
}

local function TryRegister()
    if registered then return true end
    local api = _G.MiniCCApi
    if not (api and api.v1 and api.v1.RegisterFrameProvider) then
        return false
    end
    local ok = ns.SafeCallMethod("bulkhead", api.v1, "RegisterFrameProvider", provider)
    if ok then
        registered = true
    end
    return registered
end

local function Notify()
    if not (registered and refreshCb) then return end
    if notifyScheduled then return end
    notifyScheduled = true
    C_Timer.After(0, function()
        notifyScheduled = false
        local cb = refreshCb
        if cb then ns.SafeCall("bulkhead", cb) end
    end)
end

if QUI_GF then
    if QUI_GF.RefreshAllFrames then
        hooksecurefunc(QUI_GF, "RefreshAllFrames", Notify)
    end
    if QUI_GF.Disable then
        hooksecurefunc(QUI_GF, "Disable", Notify)
    end
end

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:SetScript("OnEvent", function(self)
    if TryRegister() then
        self:UnregisterEvent("ADDON_LOADED")
    end
end)
