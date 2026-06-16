--- QUI Info Bar — spec switch widget: current spec icon + name in the slot;
--- left click opens a radio menu to change spec, right click a radio menu
--- to change loot spec. NOT secure — spec changes are plain API calls that
--- simply fail in combat (clicks are no-op'd via InCombatLockdown).
---
--- Display-only spec datatexts already exist (playerspec/lootspec); this
--- widget's value is the switch menus, so the id stays distinct.

local _, ns = ...
local QUICore = ns.Addon
local Datatexts = QUICore and QUICore.Datatexts
if not Datatexts then return end

local format = string.format
local floor = math.floor

local ICON_STRING = "|T%s:14:14:0:0:64:64:4:60:4:60|t"

-- File-local copy of the registry's color helper (locals there by design).
local function GetValueColor()
    local db = QUICore.db and QUICore.db.profile
    local dt = db and db.datatext
    if dt and dt.useClassColor then
        local _, class = UnitClass("player")
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
            -- Spec APIs are nil-prone immediately at login; events below
            -- re-drive this until they settle.
            local specIndex = GetSpecialization()
            if not specIndex then
                text:SetText(ns.L["No Spec"])
                MarkWidthDirty(slotFrame)
                return
            end

            local specID, specName, _, icon = GetSpecializationInfo(specIndex)
            if not specID or specID == 0 or not specName or not icon then
                text:SetText("?")
                MarkWidthDirty(slotFrame)
                return
            end

            -- hideIcon: per-widget host override. With noLabel too, fall
            -- through to the name-only branch (never render an empty slot).
            local iconText = (not slotFrame.hideIcon) and format(ICON_STRING, icon) or nil
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
        frame:SetScript("OnEvent", function(_, event)
            if event == "PLAYER_SPECIALIZATION_CHANGED" then
                -- let the API settle after a spec change
                C_Timer.After(0.1, Update)
            else
                Update()
            end
        end)

        -- Tooltip
        slotFrame:EnableMouse(true)
        slotFrame:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
            GameTooltip:ClearLines()
            GameTooltip:AddLine(ns.L["Specialization"], 1, 1, 1)
            GameTooltip:AddLine(" ")

            local ar, ag, ab = GetValueColor()
            ar, ag, ab = ar / 255, ag / 255, ab / 255

            local currentSpec = GetSpecialization()
            local numSpecs = GetNumSpecializations() or 0
            for i = 1, numSpecs do
                local _, specName = GetSpecializationInfo(i)
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

        -- Clicks: radio menus (house pattern: gold/playerspec MenuUtil menus)
        slotFrame:RegisterForClicks("AnyUp")
        slotFrame:SetScript("OnClick", function(self, button)
            local specIndex = GetSpecialization()
            if not specIndex then return end
            local numSpecs = GetNumSpecializations() or 0

            if button == "LeftButton" then
                MenuUtil.CreateContextMenu(self, function(_, root)
                    root:CreateTitle(ns.L["Switch Specialization"])
                    local function IsSelected(i)
                        return i == GetSpecialization()
                    end
                    local function SetSelected(i)
                        if InCombatLockdown() then return end
                        C_SpecializationInfo.SetSpecialization(i)
                    end
                    for i = 1, numSpecs do
                        local _, specName, _, icon = GetSpecializationInfo(i)
                        if specName then
                            -- icon is Nilable (docs) — never format a nil
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
                    -- 0 = follow the current spec
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

        -- Initial fill: spec APIs are unreliable before login completes
        -- (CDM re-key latch precedent) — WhenLoggedIn fires immediately
        -- when already logged in (the LOD attach case).
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
