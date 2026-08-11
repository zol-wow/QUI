local ADDON_NAME, ns = ...
local QUICore = ns.Addon
local Datatexts = QUICore and QUICore.Datatexts
if not Datatexts then return end

local format = string.format
local floor = math.floor
local min = math.min
local ipairs = ipairs

local C_Reputation = _G.C_Reputation
local C_WeeklyRewards = _G.C_WeeklyRewards
local GetProfessions = _G.GetProfessions
local GetProfessionInfo = _G.GetProfessionInfo
local WeeklyRewards_ShowUI = _G.WeeklyRewards_ShowUI
local C_Traits = _G.C_Traits
local C_PlayerInfo = _G.C_PlayerInfo

local GetValueColor = Datatexts.GetValueColor
local GetLabel = Datatexts.GetLabel
local EnsureText = Datatexts.EnsureText

local function MarkWidthDirty(slotFrame)
    if slotFrame._quiOnWidthDirty then slotFrame._quiOnWidthDirty() end
end

Datatexts:Register("reputation", {
    displayName = ns.L["Reputation"],
    category = ns.L["Character"],
    description = "Displays watched faction reputation progress",

    OnEnable = function(slotFrame, settings)
        local frame = CreateFrame("Frame", nil, slotFrame)
        frame:SetAllPoints()

        local text = EnsureText(slotFrame)

        local function GetWatchedProgress()
            if not (C_Reputation and C_Reputation.GetWatchedFactionData) then return nil end
            local data = C_Reputation.GetWatchedFactionData()
            if not data or not data.name then return nil end

            local cur = (data.currentStanding or 0) - (data.currentReactionThreshold or 0)
            local total = (data.nextReactionThreshold or 0) - (data.currentReactionThreshold or 0)

            if data.factionID and C_Reputation.IsFactionParagon
                and C_Reputation.IsFactionParagon(data.factionID) then
                local value, threshold = C_Reputation.GetFactionParagonInfo(data.factionID)
                if value and threshold and threshold > 0 then
                    cur = value % threshold
                    total = threshold
                    return data.name, cur, total, true
                end
            end

            return data.name, cur, total, false
        end

        local function Update()
            local r, g, b = GetValueColor()
            local label = GetLabel(ns.L["Rep: "], ns.L["R: "], slotFrame.shortLabel, slotFrame.noLabel)
            local name, cur, total = GetWatchedProgress()
            if not name then
                text:SetFormattedText(label .. "|cff%02x%02x%02x—|r", r, g, b)
            else
                local pct = (total and total > 0) and floor((cur / total) * 100 + 0.5) or 100
                text:SetFormattedText(label .. "|cff%02x%02x%02x%s %d%%|r", r, g, b, name, pct)
            end
            MarkWidthDirty(slotFrame)
        end

        frame.Update = Update

        frame:RegisterEvent("UPDATE_FACTION")
        frame:RegisterEvent("PLAYER_ENTERING_WORLD")
        frame:SetScript("OnEvent", Update)

        slotFrame:EnableMouse(true)
        slotFrame:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
            GameTooltip:ClearLines()
            GameTooltip:AddLine(ns.L["Reputation"], 1, 1, 1)
            GameTooltip:AddLine(" ")

            local ar, ag, ab = GetValueColor()
            ar, ag, ab = ar / 255, ag / 255, ab / 255

            local name, cur, total, isParagon = GetWatchedProgress()
            if name then
                GameTooltip:AddDoubleLine(name, format("%d / %d", cur or 0, total or 0),
                    0.8, 0.8, 0.8, ar, ag, ab)
                if isParagon then
                    GameTooltip:AddLine(ns.L["Paragon"], 0.6, 0.6, 0.6)
                end
            else
                GameTooltip:AddLine(ns.L["No faction watched"], 0.6, 0.6, 0.6)
            end

            GameTooltip:AddLine(" ")
            GameTooltip:AddLine(ns.L["|cffFFFFFFLeft Click:|r Open Reputation"], ar, ag, ab)
            GameTooltip:Show()
        end)
        slotFrame:SetScript("OnLeave", function() GameTooltip:Hide() end)

        slotFrame:RegisterForClicks("AnyUp")
        slotFrame:SetScript("OnClick", function(self, button)
            if button == "LeftButton" then
                ToggleCharacter("ReputationFrame")
            end
        end)

        Update()
        return frame
    end,

    OnDisable = function(frame)
        frame:UnregisterAllEvents()
        frame:SetScript("OnEvent", nil)
    end,
})

Datatexts:Register("vault", {
    displayName = ns.L["Vault"],
    category = ns.L["Character"],
    description = "Displays weekly reward (Great Vault) progress",

    OnEnable = function(slotFrame, settings)
        local frame = CreateFrame("Frame", nil, slotFrame)
        frame:SetAllPoints()

        local text = EnsureText(slotFrame)

        local TYPE_NAMES = {}
        if Enum and Enum.WeeklyRewardChestThresholdType then
            local t = Enum.WeeklyRewardChestThresholdType
            TYPE_NAMES[t.Raid or -1] = ns.L["Raids"]
            TYPE_NAMES[t.Activities or -1] = ns.L["Dungeons"]
            TYPE_NAMES[t.RankedPvP or -1] = ns.L["PvP"]
            TYPE_NAMES[t.World or -1] = ns.L["World"]
        end

        local function GetActivities()
            if not (C_WeeklyRewards and C_WeeklyRewards.GetActivities) then return nil end
            return C_WeeklyRewards.GetActivities()
        end

        local function Update()
            local done, total = 0, 0
            local activities = GetActivities()
            if activities then
                total = #activities
                for _, activity in ipairs(activities) do
                    if activity.progress and activity.threshold
                        and activity.progress >= activity.threshold then
                        done = done + 1
                    end
                end
            end

            local r, g, b = GetValueColor()
            local label = GetLabel(ns.L["Vault: "], ns.L["V: "], slotFrame.shortLabel, slotFrame.noLabel)
            text:SetFormattedText(label .. "|cff%02x%02x%02x%d/%d|r", r, g, b, done, total)
            MarkWidthDirty(slotFrame)
        end

        frame.Update = Update

        frame:RegisterEvent("WEEKLY_REWARDS_UPDATE")
        frame:RegisterEvent("CHALLENGE_MODE_COMPLETED")
        frame:RegisterEvent("PLAYER_ENTERING_WORLD")
        frame:SetScript("OnEvent", Update)

        slotFrame:EnableMouse(true)
        slotFrame:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
            GameTooltip:ClearLines()
            GameTooltip:AddLine(ns.L["Great Vault"], 1, 1, 1)
            GameTooltip:AddLine(" ")

            local ar, ag, ab = GetValueColor()
            ar, ag, ab = ar / 255, ag / 255, ab / 255

            local activities = GetActivities()
            if activities and #activities > 0 then
                for _, activity in ipairs(activities) do
                    local progress = activity.progress or 0
                    local threshold = activity.threshold or 0
                    local typeName = TYPE_NAMES[activity.type] or ns.L["Activity"]
                    local rowName = format("%s (%d)", typeName, activity.index or 0)
                    local vr, vg, vb
                    if threshold > 0 and progress >= threshold then
                        vr, vg, vb = ar, ag, ab
                    else
                        vr, vg, vb = 0.6, 0.6, 0.6
                    end
                    GameTooltip:AddDoubleLine(rowName,
                        format("%d / %d", min(progress, threshold), threshold),
                        0.8, 0.8, 0.8, vr, vg, vb)
                end
            else
                GameTooltip:AddLine(ns.L["No weekly progress data"], 0.6, 0.6, 0.6)
            end

            GameTooltip:AddLine(" ")
            GameTooltip:AddLine(ns.L["|cffFFFFFFLeft Click:|r Open Great Vault"], ar, ag, ab)
            GameTooltip:Show()
        end)
        slotFrame:SetScript("OnLeave", function() GameTooltip:Hide() end)

        slotFrame:RegisterForClicks("AnyUp")
        slotFrame:SetScript("OnClick", function(self, button)
            if button ~= "LeftButton" then return end
            if InCombatLockdown() then return end
            if WeeklyRewardsFrame and WeeklyRewardsFrame:IsShown() then
                HideUIPanel(WeeklyRewardsFrame)
            elseif WeeklyRewards_ShowUI then
                WeeklyRewards_ShowUI()
            end
        end)

        Update()
        return frame
    end,

    OnDisable = function(frame)
        frame:UnregisterAllEvents()
        frame:SetScript("OnEvent", nil)
    end,
})

Datatexts:Register("mail", {
    displayName = ns.L["Mail"],
    category = ns.L["Character"],
    description = "Displays unread mail notification",

    OnEnable = function(slotFrame, settings)
        local frame = CreateFrame("Frame", nil, slotFrame)
        frame:SetAllPoints()

        local text = EnsureText(slotFrame)

        local function Update()
            local label = GetLabel(ns.L["Mail: "], ns.L["M: "], slotFrame.shortLabel, slotFrame.noLabel)
            if HasNewMail() then
                text:SetFormattedText(label .. "|cffffd100" .. ns.L["New!"] .. "|r")
            else
                local r, g, b = GetValueColor()
                text:SetFormattedText(label .. "|cff%02x%02x%02x—|r", r, g, b)
            end
            MarkWidthDirty(slotFrame)
        end

        frame.Update = Update

        frame:RegisterEvent("UPDATE_PENDING_MAIL")
        frame:RegisterEvent("MAIL_INBOX_UPDATE")
        frame:RegisterEvent("PLAYER_ENTERING_WORLD")
        frame:SetScript("OnEvent", Update)

        slotFrame:EnableMouse(true)
        slotFrame:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
            GameTooltip:ClearLines()
            GameTooltip:AddLine(ns.L["Mail"], 1, 1, 1)
            GameTooltip:AddLine(" ")

            if HasNewMail() then
                GameTooltip:AddLine(ns.L["Unread mail from:"], 0.8, 0.8, 0.8)
                local senders = { GetLatestThreeSenders() }
                if #senders > 0 then
                    for _, sender in ipairs(senders) do
                        GameTooltip:AddLine(sender, 1, 1, 1)
                    end
                else
                    GameTooltip:AddLine(ns.L["Unknown sender"], 0.6, 0.6, 0.6)
                end
            else
                GameTooltip:AddLine(ns.L["No unread mail"], 0.6, 0.6, 0.6)
            end

            GameTooltip:Show()
        end)
        slotFrame:SetScript("OnLeave", function() GameTooltip:Hide() end)

        Update()
        return frame
    end,

    OnDisable = function(frame)
        frame:UnregisterAllEvents()
        frame:SetScript("OnEvent", nil)
    end,
})

Datatexts:Register("professions", {
    displayName = ns.L["Professions"],
    category = ns.L["Character"],
    description = "Displays primary profession skill levels",

    OnEnable = function(slotFrame, settings)
        local frame = CreateFrame("Frame", nil, slotFrame)
        frame:SetAllPoints()

        local text = EnsureText(slotFrame)

        local function GetProfession(index)
            if not index then return nil end
            return GetProfessionInfo(index)
        end

        local function AppendBarPart(parts, index, r, g, b)
            local name, texture, rank, maxRank = GetProfession(index)
            if not name then return end
            if slotFrame.hideIcon then
                parts[#parts + 1] = format("|cff%02x%02x%02x%d/%d|r",
                    r, g, b, rank or 0, maxRank or 0)
            else
                parts[#parts + 1] = format("|T%s:14:14|t |cff%02x%02x%02x%d/%d|r",
                    tostring(texture or 0), r, g, b, rank or 0, maxRank or 0)
            end
        end

        local function Update()
            local r, g, b = GetValueColor()
            local label = GetLabel(ns.L["Prof: "], ns.L["P: "], slotFrame.shortLabel, slotFrame.noLabel)

            local prof1, prof2 = GetProfessions()
            local parts = {}
            AppendBarPart(parts, prof1, r, g, b)
            AppendBarPart(parts, prof2, r, g, b)

            if #parts == 0 then
                text:SetFormattedText(label .. "|cff%02x%02x%02x—|r", r, g, b)
            else
                text:SetText(label .. table.concat(parts, " "))
            end
            MarkWidthDirty(slotFrame)
        end

        frame.Update = Update

        frame:RegisterEvent("SKILL_LINES_CHANGED")
        frame:RegisterEvent("PLAYER_ENTERING_WORLD")
        frame:SetScript("OnEvent", Update)

        slotFrame:EnableMouse(true)
        slotFrame:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
            GameTooltip:ClearLines()
            GameTooltip:AddLine(ns.L["Professions"], 1, 1, 1)
            GameTooltip:AddLine(" ")

            local ar, ag, ab = GetValueColor()
            ar, ag, ab = ar / 255, ag / 255, ab / 255

            local prof1, prof2, arch, fish, cook = GetProfessions()
            local any = false
            local function AddRow(index)
                local name, _, rank, maxRank = GetProfession(index)
                if not name then return end
                any = true
                GameTooltip:AddDoubleLine(name, format("%d / %d", rank or 0, maxRank or 0),
                    0.8, 0.8, 0.8, ar, ag, ab)
            end
            AddRow(prof1)
            AddRow(prof2)
            AddRow(cook)
            AddRow(fish)
            AddRow(arch)
            if not any then
                GameTooltip:AddLine(ns.L["No professions learned"], 0.6, 0.6, 0.6)
            end

            GameTooltip:AddLine(" ")
            GameTooltip:AddLine(ns.L["|cffFFFFFFLeft Click:|r Open Professions"], ar, ag, ab)
            GameTooltip:Show()
        end)
        slotFrame:SetScript("OnLeave", function() GameTooltip:Hide() end)

        slotFrame:RegisterForClicks("AnyUp")
        slotFrame:SetScript("OnClick", function(self, button)
            if button ~= "LeftButton" then return end
            if InCombatLockdown() then return end
            if ToggleProfessionsBook then
                ToggleProfessionsBook()
            end
        end)

        Update()
        return frame
    end,

    OnDisable = function(frame)
        frame:UnregisterAllEvents()
        frame:SetScript("OnEvent", nil)
    end,
})

local RUNES_OF_POWER_SYSTEM_ID = 48
local RUNES_OF_POWER_TREE_ID = 1186

Datatexts:Register("omniumfolio", {
    displayName = ns.L["Omnium Folio"],
    category = ns.L["Character"],
    description = "Opens the Omnium Folio (Midnight landing page) and shows unspent Runes of Power",

    OnEnable = function(slotFrame, settings)
        local frame = CreateFrame("Frame", nil, slotFrame)
        frame:SetAllPoints()

        local text = EnsureText(slotFrame)

        local MIDNIGHT_EXPANSION_ID = _G.LE_EXPANSION_MIDNIGHT

        local function IsUnlocked()
            if not MIDNIGHT_EXPANSION_ID then return false end
            if not (C_PlayerInfo and C_PlayerInfo.IsExpansionLandingPageUnlockedForPlayer) then
                return false
            end
            return C_PlayerInfo.IsExpansionLandingPageUnlockedForPlayer(MIDNIGHT_EXPANSION_ID)
        end

        local function GetUnspentPoints()
            if not (C_Traits and C_Traits.GetConfigIDBySystemID and C_Traits.GetTreeCurrencyInfo) then
                return nil
            end
            local configID = C_Traits.GetConfigIDBySystemID(RUNES_OF_POWER_SYSTEM_ID)
            if not configID then return nil end
            local currencies = C_Traits.GetTreeCurrencyInfo(configID, RUNES_OF_POWER_TREE_ID, false)
            if not (currencies and currencies[1]) then return nil end
            return currencies[1].quantity
        end

        local function Update()
            local label = GetLabel(ns.L["Folio: "], ns.L["F: "], slotFrame.shortLabel, slotFrame.noLabel)
            if not IsUnlocked() then
                text:SetFormattedText(label .. "|cff888888%s|r", ns.L["Locked"])
                MarkWidthDirty(slotFrame)
                return
            end
            local unspent = GetUnspentPoints() or 0
            local r, g, b = GetValueColor()
            text:SetFormattedText(label .. "|cff%02x%02x%02x%d|r", r, g, b, unspent)
            MarkWidthDirty(slotFrame)
        end

        frame.Update = Update

        frame:RegisterEvent("PLAYER_ENTERING_WORLD")
        frame:RegisterEvent("TRAIT_CONFIG_UPDATED")
        frame:RegisterEvent("TRAIT_TREE_CURRENCY_INFO_UPDATED")
        frame:SetScript("OnEvent", Update)

        slotFrame:EnableMouse(true)
        slotFrame:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
            GameTooltip:ClearLines()
            GameTooltip:AddLine(_G.MIDNIGHT_LANDING_PAGE_TITLE or ns.L["Omnium Folio"], 1, 1, 1)
            GameTooltip:AddLine(" ")

            local ar, ag, ab = GetValueColor()
            ar, ag, ab = ar / 255, ag / 255, ab / 255

            if not IsUnlocked() then
                GameTooltip:AddLine(ns.L["Not yet unlocked."], 0.6, 0.6, 0.6)
            else
                local unspent = GetUnspentPoints()
                if unspent and unspent > 0 then
                    GameTooltip:AddLine(_G.OMNIUM_FOLIO_UNSPENT_POINTS or ns.L["You have unspent points."], ar, ag, ab)
                    GameTooltip:AddDoubleLine(ns.L["Unspent Runes of Power"], unspent, 0.8, 0.8, 0.8, ar, ag, ab)
                else
                    GameTooltip:AddLine(ns.L["No unspent Runes of Power."], 0.6, 0.6, 0.6)
                end
            end

            GameTooltip:AddLine(" ")
            GameTooltip:AddLine(ns.L["|cffFFFFFFLeft Click:|r Open Omnium Folio"], ar, ag, ab)
            GameTooltip:Show()
        end)
        slotFrame:SetScript("OnLeave", function() GameTooltip:Hide() end)

        slotFrame:RegisterForClicks("AnyUp")
        slotFrame:SetScript("OnClick", function(self, button)
            if button ~= "LeftButton" then return end
            if InCombatLockdown() then return end
            if _G.ToggleExpansionLandingPage then
                _G.ToggleExpansionLandingPage()
            end
        end)

        Update()
        return frame
    end,

    OnDisable = function(frame)
        frame:UnregisterAllEvents()
        frame:SetScript("OnEvent", nil)
    end,
})

local CATALYST_CURRENCY_BY_SEASON = {
    [15] = 3269,
    [17] = 3378,
    [18] = 3465,
}

Datatexts:Register("catalyst", {
    displayName = ns.L["Catalyst Charges"],
    category = ns.L["Character"],
    description = "Displays remaining catalyst charges",

    OnEnable = function(slotFrame, settings)
        local frame = CreateFrame("Frame", nil, slotFrame)
        frame:SetAllPoints()

        local text = EnsureText(slotFrame)

        local catalystID

        local function ResolveCurrencyID()
            if catalystID then return catalystID end
            if not (C_MythicPlus and C_MythicPlus.GetCurrentSeason) then return nil end
            local season = C_MythicPlus.GetCurrentSeason()
            if not season or season == -1 then
                if C_MythicPlus.RequestMapInfo then C_MythicPlus.RequestMapInfo() end
                return nil
            end
            catalystID = CATALYST_CURRENCY_BY_SEASON[season]
            return catalystID
        end

        local function GetInfo()
            local id = ResolveCurrencyID()
            if not id or not (C_CurrencyInfo and C_CurrencyInfo.GetCurrencyInfo) then return nil end
            return C_CurrencyInfo.GetCurrencyInfo(id)
        end

        local function Update()
            local info = GetInfo()
            local label = GetLabel(ns.L["Catalyst: "], ns.L["Cat: "], slotFrame.shortLabel, slotFrame.noLabel)
            local r, g, b = GetValueColor()
            if info and info.quantity then
                text:SetFormattedText(label .. "|cff%02x%02x%02x%d|r", r, g, b, info.quantity)
            else
                text:SetFormattedText(label .. "|cff%02x%02x%02x—|r", r, g, b)
            end
            MarkWidthDirty(slotFrame)
        end

        frame.Update = Update

        frame:RegisterEvent("CURRENCY_DISPLAY_UPDATE")
        frame:RegisterEvent("PLAYER_ENTERING_WORLD")
        frame:SetScript("OnEvent", Update)

        slotFrame:EnableMouse(true)
        slotFrame:SetScript("OnEnter", function(self)
            local info = GetInfo()
            GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
            GameTooltip:ClearLines()
            GameTooltip:AddLine(ns.L["Catalyst Charges"], 1, 1, 1)
            if info then
                GameTooltip:AddLine(" ")
                local vr, vg, vb = GetValueColor()
                local value = tostring(info.quantity or 0)
                if info.maxQuantity and info.maxQuantity > 0 then
                    value = value .. " / " .. info.maxQuantity
                end
                GameTooltip:AddDoubleLine(info.name or ns.L["Charges"], value,
                    0.8, 0.8, 0.8, vr / 255, vg / 255, vb / 255)
            else
                GameTooltip:AddLine(ns.L["No catalyst currency for the current season (or season data not loaded yet)."], 0.8, 0.8, 0.8, true)
            end
            GameTooltip:Show()
        end)
        slotFrame:SetScript("OnLeave", function() GameTooltip:Hide() end)

        Update()
        return frame
    end,

    OnDisable = function(frame)
        frame:UnregisterAllEvents()
        frame:SetScript("OnEvent", nil)
    end,
})
