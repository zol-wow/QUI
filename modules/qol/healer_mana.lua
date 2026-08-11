local ADDON_NAME, ns = ...
local Helpers = ns.Helpers

local GetSettings = Helpers.CreateDBGetter("general")

local MAX_HEALERS = 5
local BAR_W, BAR_H = 130, 12
local ROW_GAP = 3

local container
local rows = {}
local tracked = {}
local inCombat = false

local function Cfg()
    local s = GetSettings()
    return s and s.healerMana or nil
end

local function Enabled()
    local cfg = Cfg()
    if not cfg or not cfg.enabled then return false end
    if cfg.instanceOnly ~= false then
        local inInstance = IsInInstance()
        if not inInstance then return false end
    end
    return IsInGroup()
end

local function EnsureContainer()
    if container then return end
    container = CreateFrame("Frame", "QUI_HealerManaFrame", UIParent)
    container:SetSize(BAR_W, 40)
    container:SetPoint("CENTER", UIParent, "CENTER", 0, -260)
    container:SetFrameStrata("MEDIUM")
    container:Hide()

    for i = 1, MAX_HEALERS do
        local row = CreateFrame("Frame", nil, container)
        row:SetSize(BAR_W, BAR_H)
        row:SetPoint("TOPLEFT", container, "TOPLEFT", 0, -(i - 1) * (BAR_H + ROW_GAP))

        row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.name:SetPoint("BOTTOMLEFT", row, "TOPLEFT", 0, 1)
        row.name:SetJustifyH("LEFT")

        row.bar = CreateFrame("StatusBar", nil, row)
        row.bar:SetAllPoints(row)
        row.bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
        row.bar:SetStatusBarColor(0.25, 0.45, 0.95)
        local bg = row.bar:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(0.05, 0.05, 0.05, 0.8)

        row:Hide()
        rows[i] = row
    end
end

local function ApplyPosition()
    local cfg = Cfg()
    if not container or not cfg then return end
    container:ClearAllPoints()
    container:SetPoint("CENTER", UIParent, "CENTER",
        tonumber(cfg.offsetX) or 0, tonumber(cfg.offsetY) or -260)
end

local function SetRowName(row, unit)
    local okName, name = pcall(UnitName, unit)
    if okName and not Helpers.IsSecretValue(name) and name then
        local classColor
        local okClass, _, class = pcall(UnitClass, unit)
        if not okClass then class = nil end
        -- @secret-policy: collapse-only — white name text fallback below
        if Helpers.IsSecretValue(class) then class = nil end
        if class then
            classColor = RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
        end
        row.name:SetText(name)
        if classColor then
            row.name:SetTextColor(classColor.r, classColor.g, classColor.b)
        else
            row.name:SetTextColor(1, 1, 1)
        end
    end
end

local function UpdateBar(unit)
    local idx = tracked[unit]
    local row = idx and rows[idx]
    if not row then return end
    local okMax, maxPower = pcall(UnitPowerMax, unit, 0)
    local okCur, curPower = pcall(UnitPower, unit, 0)
    if not okMax or not okCur then return end
    if not Helpers.IsSecretValue(maxPower) then
        if maxPower == nil then return end
    end
    if not Helpers.IsSecretValue(curPower) then
        if curPower == nil then return end
    end
    ns.SafeCallMethod("sink-forward", row.bar, "SetMinMaxValues", 0, maxPower)
    ns.SafeCallMethod("sink-forward", row.bar, "SetValue", curPower)
end

local function RebuildRoster()
    if InCombatLockdown() then return end
    EnsureContainer()
    wipe(tracked)

    if not Enabled() then
        container:Hide()
        return
    end

    local units = {}
    if IsInRaid() then
        for i = 1, GetNumGroupMembers() do units[#units + 1] = "raid" .. i end
    else
        units[#units + 1] = "player"
        for i = 1, 4 do units[#units + 1] = "party" .. i end
    end

    local shown = 0
    for _, unit in ipairs(units) do
        if shown >= MAX_HEALERS then break end
        local role = UnitGroupRolesAssigned(unit)
        -- @secret-policy: collapse-only — secret-role units are not tracked
        if Helpers.IsSecretValue(role) then role = nil end
        if UnitExists(unit) and role == "HEALER" then
            shown = shown + 1
            tracked[unit] = shown
            local row = rows[shown]
            SetRowName(row, unit)
            row:Show()
            UpdateBar(unit)
        end
    end
    for i = shown + 1, MAX_HEALERS do rows[i]:Hide() end

    if shown > 0 then
        container:SetHeight(shown * (BAR_H + ROW_GAP) + 12)
        ApplyPosition()
        container:Show()
    else
        container:Hide()
    end
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("GROUP_ROSTER_UPDATE")
frame:RegisterEvent("PLAYER_ROLES_ASSIGNED")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:RegisterEvent("PLAYER_REGEN_DISABLED")
frame:RegisterEvent("PLAYER_REGEN_ENABLED")
frame:RegisterEvent("UNIT_POWER_UPDATE")
frame:RegisterEvent("UNIT_MAXPOWER")
frame:SetScript("OnEvent", function(_, event, arg1)
    if event == "UNIT_POWER_UPDATE" or event == "UNIT_MAXPOWER" then
        if arg1 and tracked[arg1] then UpdateBar(arg1) end
    elseif event == "PLAYER_REGEN_DISABLED" then
        inCombat = true
    elseif event == "PLAYER_REGEN_ENABLED" then
        inCombat = false
        RebuildRoster()
    else
        RebuildRoster()
    end
end)

ns.RefreshHealerMana = RebuildRoster

local previewActive = false
ns.ToggleHealerManaPreview = function(show)
    EnsureContainer()
    if show then
        previewActive = true
        for i = 1, 2 do
            local row = rows[i]
            row.name:SetText(i == 1 and (ns.L["Healer"] .. " 1") or (ns.L["Healer"] .. " 2"))
            row.name:SetTextColor(1, 1, 1)
            row.bar:SetMinMaxValues(0, 100)
            row.bar:SetValue(i == 1 and 75 or 40)
            row:Show()
        end
        for i = 3, MAX_HEALERS do rows[i]:Hide() end
        container:SetHeight(2 * (BAR_H + ROW_GAP) + 12)
        ApplyPosition()
        container:Show()
    elseif previewActive then
        previewActive = false
        RebuildRoster()
    end
end
