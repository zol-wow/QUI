local GetSpecialization = (C_SpecializationInfo and C_SpecializationInfo.GetSpecialization) or GetSpecialization
local GetSpecializationInfo = (C_SpecializationInfo and C_SpecializationInfo.GetSpecializationInfo) or GetSpecializationInfo
local _, ns = ...
local QUICore = ns.Addon
local Datatexts = QUICore and QUICore.Datatexts
if not Datatexts then return end

local format = string.format
local floor = math.floor
local isForever = ns.Client and ns.Client.isForever or false

local function GetSwitchIndex()
    if isForever then return C_SpecializationInfo.GetActiveSpecGroup() end
    return GetSpecialization()
end

local function GetSwitchCount()
    if isForever then return _G.GetNumSpecGroups() or 0 end
    return GetNumSpecializations() or 0
end

local function GetSwitchInfo(index)
    if isForever then
        return index, index == 1 and _G.DUAL_SPEC_PRIMARY or _G.DUAL_SPEC_SECONDARY
    end
    return GetSpecializationInfo(index)
end

local ICON_STRING = "|T%s:14:14:0:0:64:64:4:60:4:60|t"

local function GetValueColor()
    local db = QUICore.db and QUICore.db.profile
    local dt = db and db.datatext
    if dt and dt.useClassColor then
        local _, class = UnitClass("player")
        -- @secret-policy: collapse-only — UnitClass can return SECRET on 12.1 PTR7
        if issecretvalue and issecretvalue(class) then class = nil end
        local color = class and RAID_CLASS_COLORS[class]
        if color then
            return floor(color.r * 255), floor(color.g * 255), floor(color.b * 255)
        end
    end
    local c = dt and dt.valueColor or { 0.1, 1.0, 0.1, 1 }
    return floor(c[1] * 255), floor(c[2] * 255), floor(c[3] * 255)
end

local function EnsureText(slotFrame)
    local text = slotFrame.text
    if not text then
        text = slotFrame:CreateFontString(nil, "OVERLAY")
        text:SetPoint("CENTER")
        slotFrame.text = text
    end
    return text
end

local function MarkWidthDirty(slotFrame)
    if slotFrame._quiOnWidthDirty then slotFrame._quiOnWidthDirty() end
end

Datatexts:Register("specswap", {
    displayName = ns.L["Spec Switch"],
    category = ns.L["Character"],
    description = "Current specialization with quick spec/loot-spec switch menus",

    OnEnable = function(slotFrame, settings)
        local frame = CreateFrame("Frame", nil, slotFrame)
        frame:SetAllPoints()

        local text = EnsureText(slotFrame)

        local function Update()
            local specIndex = GetSwitchIndex()
            if not specIndex then
                text:SetText(ns.L["No Spec"])
                MarkWidthDirty(slotFrame)
                return
            end

            local specID, specName, _, icon = GetSwitchInfo(specIndex)
            if not specID or specID == 0 or not specName then
                text:SetText("?")
                MarkWidthDirty(slotFrame)
                return
            end

            local iconText = (not slotFrame.hideIcon) and icon and format(ICON_STRING, icon) or nil
            if slotFrame.noLabel and iconText then
                text:SetText(iconText)
            else
                local r, g, b = GetValueColor()
                if iconText then
                    text:SetFormattedText("%s |cff%02x%02x%02x%s|r",
                        iconText, r, g, b, specName)
                else
                    text:SetFormattedText("|cff%02x%02x%02x%s|r",
                        r, g, b, specName)
                end
            end
            MarkWidthDirty(slotFrame)
        end

        frame.Update = Update

        frame:RegisterEvent("PLAYER_ENTERING_WORLD")
        frame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
        frame:RegisterEvent("PLAYER_LOOT_SPEC_UPDATED")
        if isForever then
            frame:RegisterEvent("PLAYER_TALENT_UPDATE")
            frame:RegisterEvent("ACTIVE_PLAYER_SPECIALIZATION_CHANGED")
        end
        frame:SetScript("OnEvent", function(_, event)
            if event == "PLAYER_SPECIALIZATION_CHANGED" then
                C_Timer.After(0.1, Update)
            else
                Update()
            end
        end)

        slotFrame:EnableMouse(true)
        slotFrame:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
            GameTooltip:ClearLines()
            GameTooltip:AddLine(ns.L["Specialization"], 1, 1, 1)
            GameTooltip:AddLine(" ")

            local ar, ag, ab = GetValueColor()
            ar, ag, ab = ar / 255, ag / 255, ab / 255

            local currentSpec = GetSwitchIndex()
            local numSpecs = GetNumSpecializations() or 0
            for i = 1, GetSwitchCount() do
                local _, specName = GetSwitchInfo(i)
                if specName then
                    if i == currentSpec then
                        GameTooltip:AddDoubleLine(specName, ns.L["Active"],
                            1, 1, 1, ar, ag, ab)
                    else
                        GameTooltip:AddLine(specName, 0.6, 0.6, 0.6)
                    end
                end
            end

            local lootSpec = GetLootSpecialization()
            if lootSpec == 0 then
                GameTooltip:AddDoubleLine(ns.L["Loot"], ns.L["Current spec"],
                    0.8, 0.8, 0.8, ar, ag, ab)
            else
                for i = 1, numSpecs do
                    local specID, specName = GetSpecializationInfo(i)
                    if specID == lootSpec then
                        GameTooltip:AddDoubleLine(ns.L["Loot"], specName,
                            0.8, 0.8, 0.8, ar, ag, ab)
                        break
                    end
                end
            end

            GameTooltip:AddLine(" ")
            GameTooltip:AddLine(ns.L["|cffFFFFFFLeft Click:|r Change Spec"], ar, ag, ab)
            GameTooltip:AddLine(ns.L["|cffFFFFFFRight Click:|r Change Loot Spec"], ar, ag, ab)
            GameTooltip:Show()
        end)
        slotFrame:SetScript("OnLeave", function() GameTooltip:Hide() end)

        slotFrame:RegisterForClicks("AnyUp")
        slotFrame:SetScript("OnClick", function(self, button)
            local specIndex = GetSwitchIndex()
            if not specIndex then return end
            local numSpecs = GetNumSpecializations() or 0

            if button == "LeftButton" then
                MenuUtil.CreateContextMenu(self, function(_, root)
                    root:CreateTitle(ns.L["Switch Specialization"])
                    local function IsSelected(i)
                        return i == GetSwitchIndex()
                    end
                    local function SetSelected(i)
                        if InCombatLockdown() then return end
                        if isForever then
                            C_SpecializationInfo.SetActiveSpecGroup(i)
                        else
                            C_SpecializationInfo.SetSpecialization(i)
                        end
                    end
                    for i = 1, GetSwitchCount() do
                        local _, specName, _, icon = GetSwitchInfo(i)
                        if specName then
                            local prefix = icon and (format(ICON_STRING, icon) .. " ") or ""
                            root:CreateRadio(prefix .. specName,
                                IsSelected, SetSelected, i)
                        end
                    end
                end)
            elseif button == "RightButton" then
                MenuUtil.CreateContextMenu(self, function(_, root)
                    root:CreateTitle(ns.L["Loot Specialization"])
                    local function IsSelected(specID)
                        return GetLootSpecialization() == specID
                    end
                    local function SetSelected(specID)
                        if InCombatLockdown() then return end
                        SetLootSpecialization(specID)
                    end
                    root:CreateRadio(ns.L["Current spec"], IsSelected, SetSelected, 0)
                    root:CreateDivider()
                    for i = 1, numSpecs do
                        local specID, specName, _, icon = GetSpecializationInfo(i)
                        if specID and specID ~= 0 and specName then
                            local prefix = icon and (format(ICON_STRING, icon) .. " ") or ""
                            root:CreateRadio(prefix .. specName,
                                IsSelected, SetSelected, specID)
                        end
                    end
                end)
            end
        end)

        if ns.WhenLoggedIn then
            ns.WhenLoggedIn(Update)
        else
            Update()
        end

        return frame
    end,

    OnDisable = function(frame)
        frame:UnregisterAllEvents()
        frame:SetScript("OnEvent", nil)
    end,
})
