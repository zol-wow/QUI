local ADDON_NAME, ns = ...
local Helpers = ns.Helpers

local GetSettings = Helpers.CreateDBGetter("general")

local ALERT_HOLD = 3

local alertFrame, alertText
local deadState = {}
local tracked = {}
local hideTimer = 0

local function Cfg()
    local s = GetSettings()
    return s and s.deathAlert or nil
end

local function Enabled()
    local cfg = Cfg()
    return cfg and cfg.enabled == true and IsInGroup()
end

local function EnsureFrame()
    if alertFrame then return end
    alertFrame = CreateFrame("Frame", "QUI_DeathAlertFrame", UIParent)
    alertFrame:SetSize(400, 40)
    alertFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 220)
    alertFrame:SetFrameStrata("HIGH")
    alertText = alertFrame:CreateFontString(nil, "OVERLAY")
    alertText:SetAllPoints()
    local font = Helpers.GetGeneralFont and Helpers.GetGeneralFont()
    if ns.Helpers.ApplyFontWithFallback then
        ns.Helpers.ApplyFontWithFallback(alertText, font or STANDARD_TEXT_FONT, 24, "OUTLINE")
    else
        alertText:SetFont(font or STANDARD_TEXT_FONT, 24, "OUTLINE")
    end
    alertText:SetTextColor(1, 0.25, 0.25)
    alertFrame:Hide()
    alertFrame:SetScript("OnUpdate", function(self, elapsed)
        hideTimer = hideTimer - elapsed
        if hideTimer <= 0 then self:Hide() end
    end)
end

local function ApplyPosition()
    local cfg = Cfg()
    if not alertFrame or not cfg then return end
    alertFrame:ClearAllPoints()
    alertFrame:SetPoint("CENTER", UIParent, "CENTER",
        tonumber(cfg.offsetX) or 0, tonumber(cfg.offsetY) or 220)
    local size = tonumber(cfg.fontSize) or 24
    local font = Helpers.GetGeneralFont and Helpers.GetGeneralFont()
    if ns.Helpers.ApplyFontWithFallback then
        ns.Helpers.ApplyFontWithFallback(alertText, font or STANDARD_TEXT_FONT, size, "OUTLINE")
    end
end

local function PlayAlertSound()
    local cfg = Cfg()
    local soundName = cfg and cfg.sound
    if not soundName or soundName == "None" or soundName == "" then return end
    local LSM = ns.LSM
    local path = LSM and LSM:Fetch("sound", soundName)
    if path and type(path) == "string" then
        PlaySoundFile(path, "Master")
    end
end

local function ShowAlert(unit)
    EnsureFrame()
    ApplyPosition()
    local who = ns.L["An ally"]
    local okName, name = pcall(UnitName, unit)
    name = Helpers.SafeValue(name)
    if okName and name and name ~= "" then
        who = name
    end
    alertText:SetText(who .. " " .. ns.L["died!"])
    hideTimer = ALERT_HOLD
    alertFrame:Show()
    PlayAlertSound()
end

local function CheckUnit(unit)
    if not tracked[unit] then return end
    local okDead, dead = pcall(UnitIsDeadOrGhost, unit)
    if not okDead or Helpers.IsSecretValue(dead) then return end
    dead = dead and true or false

    if dead and not deadState[unit] then
        local okFeign, feign = pcall(UnitIsFeignDeath, unit)
        if okFeign and not Helpers.IsSecretValue(feign) and feign then
            return
        end
        deadState[unit] = true
        if Enabled() then ShowAlert(unit) end
    elseif not dead and deadState[unit] then
        deadState[unit] = false
    end
end

local function RebuildRoster()
    wipe(tracked)
    wipe(deadState)
    if not Enabled() then return end
    local units = {}
    if IsInRaid() then
        for i = 1, GetNumGroupMembers() do units[#units + 1] = "raid" .. i end
    else
        for i = 1, 4 do units[#units + 1] = "party" .. i end
    end
    for _, unit in ipairs(units) do
        if UnitExists(unit) then
            tracked[unit] = true
            local okDead, dead = pcall(UnitIsDeadOrGhost, unit)
            deadState[unit] = (okDead and not Helpers.IsSecretValue(dead) and dead) and true or false
        end
    end
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("GROUP_ROSTER_UPDATE")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:RegisterEvent("UNIT_HEALTH")
frame:RegisterEvent("UNIT_FLAGS")
frame:SetScript("OnEvent", function(_, event, arg1)
    if event == "UNIT_HEALTH" or event == "UNIT_FLAGS" then
        if arg1 then CheckUnit(arg1) end
    else
        RebuildRoster()
    end
end)

ns.RefreshDeathAlert = function()
    RebuildRoster()
    if alertFrame then ApplyPosition() end
end

ns.ToggleDeathAlertPreview = function(show)
    EnsureFrame()
    ApplyPosition()
    if show then
        alertText:SetText(ns.L["An ally"] .. " " .. ns.L["died!"])
        hideTimer = math.huge
        alertFrame:Show()
    else
        hideTimer = 0
        alertFrame:Hide()
    end
end
