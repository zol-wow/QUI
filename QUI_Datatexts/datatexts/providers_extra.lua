--- QUI Datatexts — additional providers: reputation, vault, mail, professions.
--- Registered into the shared registry; usable by every slot consumer.

local ADDON_NAME, ns = ...
local QUICore = ns.Addon
local Datatexts = QUICore and QUICore.Datatexts
if not Datatexts then return end

local format = string.format
local floor = math.floor
local min = math.min
local ipairs = ipairs

-- WoW globals (upvalued; all exist before addons load)
local C_Reputation = _G.C_Reputation
local C_WeeklyRewards = _G.C_WeeklyRewards
local GetProfessions = _G.GetProfessions
local GetProfessionInfo = _G.GetProfessionInfo
local WeeklyRewards_ShowUI = _G.WeeklyRewards_ShowUI

-- File-local copies of the registry's color/label helpers (locals there by design).
local function GetValueColor()
    local addon = ns and ns.Addon
    local db = addon and addon.db and addon.db.profile
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

local function GetLabel(fullLabel, shortLabel, useShortLabel, useNoLabel)
    if useNoLabel then return "" end
    if useShortLabel then return shortLabel end
    return fullLabel
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

-- Hook installed by auto-width hosts (info bar); nil on fixed-width panels.
local function MarkWidthDirty(slotFrame)
    if slotFrame._quiOnWidthDirty then slotFrame._quiOnWidthDirty() end
end

---=================================================================================
--- REPUTATION DATATEXT
---=================================================================================

Datatexts:Register("reputation", {
    displayName = "Reputation",
    category = "Character",
    description = "Displays watched faction reputation progress",

    OnEnable = function(slotFrame, settings)
        local frame = CreateFrame("Frame", nil, slotFrame)
        frame:SetAllPoints()

        local text = EnsureText(slotFrame)

        -- Returns name, current-into-standing, total-for-standing, isParagon
        -- (nil when no faction is watched).
        local function GetWatchedProgress()
            if not (C_Reputation and C_Reputation.GetWatchedFactionData) then return nil end
            local data = C_Reputation.GetWatchedFactionData()
            if not data or not data.name then return nil end

            local cur = (data.currentStanding or 0) - (data.currentReactionThreshold or 0)
            local total = (data.nextReactionThreshold or 0) - (data.currentReactionThreshold or 0)

            -- Paragon override: progress within the current paragon cycle.
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
            local label = GetLabel("Rep: ", "R: ", slotFrame.shortLabel, slotFrame.noLabel)
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

        -- Tooltip
        slotFrame:EnableMouse(true)
        slotFrame:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
            GameTooltip:ClearLines()
            GameTooltip:AddLine("Reputation", 1, 1, 1)
            GameTooltip:AddLine(" ")

            local ar, ag, ab = GetValueColor()
            ar, ag, ab = ar / 255, ag / 255, ab / 255

            local name, cur, total, isParagon = GetWatchedProgress()
            if name then
                GameTooltip:AddDoubleLine(name, format("%d / %d", cur or 0, total or 0),
                    0.8, 0.8, 0.8, ar, ag, ab)
                if isParagon then
                    GameTooltip:AddLine("Paragon", 0.6, 0.6, 0.6)
                end
            else
                GameTooltip:AddLine("No faction watched", 0.6, 0.6, 0.6)
            end

            GameTooltip:AddLine(" ")
            GameTooltip:AddLine("|cffFFFFFFLeft Click:|r Open Reputation", ar, ag, ab)
            GameTooltip:Show()
        end)
        slotFrame:SetScript("OnLeave", function() GameTooltip:Hide() end)

        -- Click handler: Left = Reputation panel
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

---=================================================================================
--- GREAT VAULT DATATEXT
---=================================================================================

Datatexts:Register("vault", {
    displayName = "Vault",
    category = "Character",
    description = "Displays weekly reward (Great Vault) progress",

    OnEnable = function(slotFrame, settings)
        local frame = CreateFrame("Frame", nil, slotFrame)
        frame:SetAllPoints()

        local text = EnsureText(slotFrame)

        local TYPE_NAMES = {}
        if Enum and Enum.WeeklyRewardChestThresholdType then
            local t = Enum.WeeklyRewardChestThresholdType
            TYPE_NAMES[t.Raid or -1] = "Raids"
            TYPE_NAMES[t.Activities or -1] = "Dungeons"
            TYPE_NAMES[t.RankedPvP or -1] = "PvP"
            TYPE_NAMES[t.World or -1] = "World"
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
            local label = GetLabel("Vault: ", "V: ", slotFrame.shortLabel, slotFrame.noLabel)
            text:SetFormattedText(label .. "|cff%02x%02x%02x%d/%d|r", r, g, b, done, total)
            MarkWidthDirty(slotFrame)
        end

        frame.Update = Update

        frame:RegisterEvent("WEEKLY_REWARDS_UPDATE")
        frame:RegisterEvent("CHALLENGE_MODE_COMPLETED")
        frame:RegisterEvent("PLAYER_ENTERING_WORLD")
        frame:SetScript("OnEvent", Update)

        -- Tooltip
        slotFrame:EnableMouse(true)
        slotFrame:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
            GameTooltip:ClearLines()
            GameTooltip:AddLine("Great Vault", 1, 1, 1)
            GameTooltip:AddLine(" ")

            local ar, ag, ab = GetValueColor()
            ar, ag, ab = ar / 255, ag / 255, ab / 255

            local activities = GetActivities()
            if activities and #activities > 0 then
                for _, activity in ipairs(activities) do
                    local progress = activity.progress or 0
                    local threshold = activity.threshold or 0
                    local typeName = TYPE_NAMES[activity.type] or "Activity"
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
                GameTooltip:AddLine("No weekly progress data", 0.6, 0.6, 0.6)
            end

            GameTooltip:AddLine(" ")
            GameTooltip:AddLine("|cffFFFFFFLeft Click:|r Open Great Vault", ar, ag, ab)
            GameTooltip:Show()
        end)
        slotFrame:SetScript("OnLeave", function() GameTooltip:Hide() end)

        -- Click handler: Left = Great Vault (loads Blizzard_WeeklyRewards on demand)
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

---=================================================================================
--- MAIL DATATEXT
---=================================================================================

Datatexts:Register("mail", {
    displayName = "Mail",
    category = "Character",
    description = "Displays unread mail notification",

    OnEnable = function(slotFrame, settings)
        local frame = CreateFrame("Frame", nil, slotFrame)
        frame:SetAllPoints()

        local text = EnsureText(slotFrame)

        local function Update()
            local label = GetLabel("Mail: ", "M: ", slotFrame.shortLabel, slotFrame.noLabel)
            if HasNewMail() then
                text:SetFormattedText(label .. "|cffffd100New!|r")
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

        -- Tooltip
        slotFrame:EnableMouse(true)
        slotFrame:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
            GameTooltip:ClearLines()
            GameTooltip:AddLine("Mail", 1, 1, 1)
            GameTooltip:AddLine(" ")

            if HasNewMail() then
                GameTooltip:AddLine("Unread mail from:", 0.8, 0.8, 0.8)
                local senders = { GetLatestThreeSenders() }
                if #senders > 0 then
                    for _, sender in ipairs(senders) do
                        GameTooltip:AddLine(sender, 1, 1, 1)
                    end
                else
                    GameTooltip:AddLine("Unknown sender", 0.6, 0.6, 0.6)
                end
            else
                GameTooltip:AddLine("No unread mail", 0.6, 0.6, 0.6)
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

---=================================================================================
--- PROFESSIONS DATATEXT
---=================================================================================

Datatexts:Register("professions", {
    displayName = "Professions",
    category = "Character",
    description = "Displays primary profession skill levels",

    OnEnable = function(slotFrame, settings)
        local frame = CreateFrame("Frame", nil, slotFrame)
        frame:SetAllPoints()

        local text = EnsureText(slotFrame)

        -- index may be nil (GetProfessions returns nil for empty slots);
        -- returns nil for empty slots, otherwise name, texture, rank, maxRank.
        local function GetProfession(index)
            if not index then return nil end
            return GetProfessionInfo(index)
        end

        local function AppendBarPart(parts, index, r, g, b)
            local name, texture, rank, maxRank = GetProfession(index)
            if not name then return end
            -- hideIcon: per-widget host override — drop the inline profession
            -- icon, keep the skill numbers.
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
            local label = GetLabel("Prof: ", "P: ", slotFrame.shortLabel, slotFrame.noLabel)

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

        -- Tooltip
        slotFrame:EnableMouse(true)
        slotFrame:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
            GameTooltip:ClearLines()
            GameTooltip:AddLine("Professions", 1, 1, 1)
            GameTooltip:AddLine(" ")

            local ar, ag, ab = GetValueColor()
            ar, ag, ab = ar / 255, ag / 255, ab / 255

            -- GetProfessions returns prof1, prof2, archaeology, fishing, cooking
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
                GameTooltip:AddLine("No professions learned", 0.6, 0.6, 0.6)
            end

            GameTooltip:AddLine(" ")
            GameTooltip:AddLine("|cffFFFFFFLeft Click:|r Open Professions", ar, ag, ab)
            GameTooltip:Show()
        end)
        slotFrame:SetScript("OnLeave", function() GameTooltip:Hide() end)

        -- Click handler: Left = Professions book (loads Blizzard_ProfessionsBook on demand)
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
