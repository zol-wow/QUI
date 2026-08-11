local addonName, ns = ...

-- luacheck: globals RaiderIO

local openRaidLib = LibStub and LibStub:GetLibrary("LibOpenRaid-1.0", true)
if not openRaidLib then
    return
end

local function CJKFont(fs, p, s, f)
    if ns.Helpers and ns.Helpers.ApplyFontWithFallback then
        ns.Helpers.ApplyFontWithFallback(fs, p, s, f)
    else
        fs:SetFont(p, s, f)
    end
end

local Helpers = ns.Helpers
local UIKit = ns.UIKit
local GetCore = Helpers.GetCore

local function GetSettings()
    local guiQUICore = GetCore()
    return guiQUICore and guiQUICore.db and guiQUICore.db.profile and guiQUICore.db.profile.general
end

local function IsEnabled()
    local s = GetSettings()
    return s and s.keyTrackerEnabled ~= false
end

local function GetFont()
    local s = GetSettings()
    local fontName = s and s.keyTrackerFont
    return UIKit.ResolveFontPath(fontName)
end

local function GetFrameWidth()
    local s = GetSettings()
    return s and s.keyTrackerWidth or 170
end

local function GetTextColor()
    local s = GetSettings()
    if s and s.keyTrackerTextColor then
        return unpack(s.keyTrackerTextColor)
    end
    return 1, 1, 1, 1
end

local BUTTON_SIZE = 20
local ENTRY_PADDING_X = 4
local ENTRY_PADDING_Y = 4
local ENTRY_SPACING = 6
local HEADER_HEIGHT = BUTTON_SIZE + (ENTRY_PADDING_Y * 2)
local ENTRY_HEIGHT = BUTTON_SIZE + ENTRY_SPACING

local function GetFontSize()
    local s = GetSettings()
    return s and s.keyTrackerFontSize or 9
end

local INITIAL_REQUEST_DELAY = 3
local GROUP_CHANGE_DELAY = 2
local UPDATE_DELAY = 1
local VISIBILITY_DELAY = 0.1
local INITIAL_KEYSTONE_REQUEST_DELAY = 5

local GetSkinColors = Helpers.CreateSkinColorGetter()

local function GetDungeonInfo(mapID)
    if not mapID then
        return "Interface\\Icons\\INV_Misc_QuestionMark", "???", nil
    end

    if _G.QUI_DungeonData then
        local data = _G.QUI_DungeonData.GetDungeonData(mapID)
        if data then
            local _, _, _, icon = C_ChallengeMode.GetMapUIInfo(mapID)
            return icon, data.short, data.spellID
        end
    end
    local name, _, _, icon = C_ChallengeMode.GetMapUIInfo(mapID)
    local short = name and name:match("^(%S+)") or "???"
    return icon, short, nil
end

local function GetKeyColor(level)
    if _G.QUI_DungeonData and _G.QUI_DungeonData.GetKeyColor then
        return _G.QUI_DungeonData.GetKeyColor(level)
    end
    if not level or level == 0 then return 0.7, 0.7, 0.7 end
    if level >= 12 then return 1, 0.5, 0 end
    if level >= 10 then return 0.64, 0.21, 0.93 end
    if level >= 7 then return 0, 0.44, 0.87 end
    if level >= 5 then return 0.12, 0.75, 0.26 end
    return 1, 1, 1
end

local function GetPlayerScoreInfo(unit)
    local score, color = 0, { r = 1, g = 1, b = 1 }

    if RaiderIO and RaiderIO.GetProfile then
        local profile = RaiderIO.GetProfile(unit)
        if profile and profile.mythicKeystoneProfile and profile.mythicKeystoneProfile.currentScore then
            score = math.floor(profile.mythicKeystoneProfile.currentScore)
            if RaiderIO.GetScoreColor then
                local r, g, b = RaiderIO.GetScoreColor(score)
                color = { r = r, g = g, b = b }
            end
            return score, color
        end
    end

    local ratingInfo = C_PlayerInfo.GetPlayerMythicPlusRatingSummary(unit)
    if ratingInfo and ratingInfo.currentSeasonScore and ratingInfo.currentSeasonScore > 0 then
        score = math.floor(ratingInfo.currentSeasonScore)
        if C_ChallengeMode.GetDungeonScoreRarityColor then
            local rarityColor = C_ChallengeMode.GetDungeonScoreRarityColor(score)
            if rarityColor then
                color = { r = rarityColor.r, g = rarityColor.g, b = rarityColor.b }
            end
        end
    end
    return score, color
end

local KeyTrackerFrame = CreateFrame("Frame", "QUIKeyTrackerFrame", UIParent, "BackdropTemplate")
KeyTrackerFrame:SetFrameStrata("HIGH")
KeyTrackerFrame:SetSize(GetFrameWidth(), HEADER_HEIGHT)

local function GetKeyTrackerPixelSize()
    if UIKit and UIKit.GetPixelSize then
        return UIKit.GetPixelSize(KeyTrackerFrame)
    end
    local core = GetCore()
    return (core and core.GetPixelSize and core:GetPixelSize(KeyTrackerFrame)) or 1
end

local keyTrackerBackdrop = {
    bgFile = "Interface\\Buttons\\WHITE8X8",
    edgeFile = "Interface\\Buttons\\WHITE8X8",
    edgeSize = GetKeyTrackerPixelSize(),
}
KeyTrackerFrame:SetBackdrop(keyTrackerBackdrop)
local function UpdateKeyTrackerPixelSize()
    local px = GetKeyTrackerPixelSize()
    if keyTrackerBackdrop.edgeSize ~= px then
        keyTrackerBackdrop.edgeSize = px
        KeyTrackerFrame:SetBackdrop(keyTrackerBackdrop)
    end
end
UpdateKeyTrackerPixelSize()
KeyTrackerFrame:EnableMouse(true)
KeyTrackerFrame:SetMovable(true)
KeyTrackerFrame:RegisterForDrag("LeftButton")
KeyTrackerFrame:SetClampedToScreen(true)
KeyTrackerFrame:Hide()

local title = KeyTrackerFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
title:SetPoint("TOP", KeyTrackerFrame, "TOP", 0, -2)
CJKFont(title, title:GetFont(), 9, "OUTLINE")

local function UpdateTitleColor()
    local sr, sg, sb = GetSkinColors()
    title:SetText("|cff" .. string.format("%02x%02x%02x", sr*255, sg*255, sb*255) .. ns.L["Party Keys|r"])
end

local function ApplySkinColors()
    UpdateKeyTrackerPixelSize()
    local sr, sg, sb, sa, bgr, bgg, bgb, bga = GetSkinColors()
    KeyTrackerFrame:SetBackdropColor(bgr, bgg, bgb, bga)
    KeyTrackerFrame:SetBackdropBorderColor(sr, sg, sb, sa)
    UpdateTitleColor()
end

local function PositionKeyTracker()
    KeyTrackerFrame:ClearAllPoints()
    if PVEFrame then
        local s = GetSettings()
        local point = s and s.keyTrackerPoint or "TOPRIGHT"
        local relPoint = s and s.keyTrackerRelPoint or "BOTTOMRIGHT"
        local offsetX = s and s.keyTrackerOffsetX or 0
        local offsetY = s and s.keyTrackerOffsetY or 0
        KeyTrackerFrame:SetPoint(point, PVEFrame, relPoint, offsetX, offsetY)
    end
end

KeyTrackerFrame:HookScript("OnShow", function()
    if PVEFrame then
        PositionKeyTracker()
    end
end)

KeyTrackerFrame:SetScript("OnDragStart", function(self)
    if IsShiftKeyDown() then
        self:StartMoving()
    end
end)
KeyTrackerFrame:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
end)

KeyTrackerFrame:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:AddLine(ns.L["Party Keys"], 1, 1, 1)
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine(ns.L["Right-click to refresh"], 0.7, 0.7, 0.7)
    GameTooltip:AddLine(ns.L["Shift+Drag to move"], 0.7, 0.7, 0.7)
    GameTooltip:Show()
end)
KeyTrackerFrame:SetScript("OnLeave", function()
    GameTooltip:Hide()
end)

local function GetRowWidth()
    return GetFrameWidth() - (ENTRY_PADDING_X * 2)
end

local function CreateKeystoneButton(parent, yOffset)
    local button = CreateFrame("Button", nil, parent, "SecureActionButtonTemplate")
    button:SetSize(GetRowWidth(), BUTTON_SIZE)
    button:SetPoint("TOPLEFT", parent, "TOPLEFT", ENTRY_PADDING_X, yOffset)
    button:RegisterForClicks("AnyDown", "AnyUp")

    button.icon = button:CreateTexture(nil, "ARTWORK")
    button.icon:SetSize(BUTTON_SIZE, BUTTON_SIZE)
    button.icon:SetPoint("LEFT", button, "LEFT", 0, 0)
    button.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    button.cooldownOverlay = button:CreateTexture(nil, "ARTWORK", nil, 1)
    button.cooldownOverlay:SetAllPoints(button.icon)
    button.cooldownOverlay:SetColorTexture(0, 0, 0, 0.6)
    button.cooldownOverlay:Hide()

    button.highlight = button:CreateTexture(nil, "HIGHLIGHT")
    button.highlight:SetAllPoints()
    button.highlight:SetColorTexture(1, 1, 1, 0.06)

    local fontSize = GetFontSize()
    local fontPath = GetFont()

    button.keyLevel = button:CreateFontString(nil, "OVERLAY")
    button.keyLevel:SetPoint("CENTER", button.icon, "CENTER", 0, 0)
    CJKFont(button.keyLevel, fontPath, fontSize + 1, "OUTLINE")

    button.dungeonName = button:CreateFontString(nil, "OVERLAY")
    button.dungeonName:SetPoint("LEFT", button.icon, "RIGHT", 4, 0)
    CJKFont(button.dungeonName, fontPath, fontSize, "OUTLINE")
    button.dungeonName:SetJustifyH("LEFT")
    button.dungeonName:SetWidth(40)

    button.playerName = button:CreateFontString(nil, "OVERLAY")
    button.playerName:SetPoint("LEFT", button.dungeonName, "RIGHT", 4, 0)
    CJKFont(button.playerName, fontPath, fontSize, "OUTLINE")
    button.playerName:SetJustifyH("LEFT")

    button.score = button:CreateFontString(nil, "OVERLAY")
    button.score:SetPoint("RIGHT", button, "RIGHT", 0, 0)
    CJKFont(button.score, fontPath, fontSize, "OUTLINE")
    button.score:SetJustifyH("RIGHT")
    button.score:SetJustifyV("MIDDLE")

    button.leaderIcon = button:CreateTexture(nil, "OVERLAY")
    button.leaderIcon:SetSize(10, 10)
    button.leaderIcon:SetPoint("TOPLEFT", button.icon, "TOPLEFT", -2, 2)
    button.leaderIcon:SetTexture("Interface\\GroupFrame\\UI-Group-LeaderIcon")
    button.leaderIcon:Hide()

    button:SetScript("OnEnter", function(self)
        if self.tooltipDungeon then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine(self.tooltipDungeon, 1, 1, 1)
            if self.spellID then
                GameTooltip:AddLine(ns.L["Click to teleport"], 0.5, 1, 0.5)
            end
            GameTooltip:Show()
        end
    end)
    button:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    return button
end

local TITLE_HEIGHT = 12
local keystoneButtons = {}
keystoneButtons[0] = CreateKeystoneButton(KeyTrackerFrame, -TITLE_HEIGHT)
for i = 1, 4 do
    keystoneButtons[i] = CreateKeystoneButton(KeyTrackerFrame, -TITLE_HEIGHT - (i * ENTRY_HEIGHT))
end

local function UpdateAllButtonFonts()
    local fontSize = GetFontSize()
    local fontPath = GetFont()
    local tr, tg, tb, ta = GetTextColor()
    for i = 0, 4 do
        local button = keystoneButtons[i]
        if button then
            CJKFont(button.keyLevel, fontPath, fontSize + 1, "OUTLINE")
            CJKFont(button.dungeonName, fontPath, fontSize, "OUTLINE")
            button.dungeonName:SetTextColor(tr, tg, tb, ta)
            CJKFont(button.playerName, fontPath, fontSize, "OUTLINE")
            CJKFont(button.score, fontPath, fontSize, "OUTLINE")
        end
    end
end

local function UpdateButtonCooldown(button)
    if InCombatLockdown() then return end
    if button.spellID then
        local cooldownInfo = C_Spell.GetSpellCooldown(button.spellID)
        local showCooldown
        if cooldownInfo then -- @secret-safe: SpellCooldownInfo container is a plain table-or-nil (MayReturnNothing); fields probed below
            local startTime = cooldownInfo.startTime
            if issecretvalue and issecretvalue(startTime) then
                -- @secret-policy: keep-visible-when-unknown (hold last overlay state)
            elseif startTime > 0 then
                local duration = cooldownInfo.duration
                if issecretvalue and issecretvalue(duration) then
                    -- @secret-policy: keep-visible-when-unknown (hold last overlay state)
                else
                    showCooldown = duration > 5
                end
            else
                showCooldown = false
            end
        else
            showCooldown = false
        end
        if showCooldown == true then
            button.cooldownOverlay:Show()
        elseif showCooldown == false then
            button.cooldownOverlay:Hide()
        elseif button._quiCooldownSpellID ~= button.spellID then
            button.cooldownOverlay:Hide()
        end
        button._quiCooldownSpellID = button.spellID
    else
        button.cooldownOverlay:Hide()
        button._quiCooldownSpellID = nil
    end
end

local function UpdateButton(button, keystoneInfo, unitName, unit, isLeader)
    if InCombatLockdown() then return end

    local _, class = UnitClass(unit)
    -- @secret-policy: collapse-only — white player-name fallback
    if Helpers.IsSecretValue(class) then class = nil end
    local classColor = class and RAID_CLASS_COLORS[class] and RAID_CLASS_COLORS[class].colorStr or "FFFFFFFF"
    local displayName = unitName:match("([^%-]+)") or unitName

    if keystoneInfo and keystoneInfo.level and keystoneInfo.level > 0 then
        local icon, shortName, spellID = GetDungeonInfo(keystoneInfo.challengeMapID)
        local kr, kg, kb = GetKeyColor(keystoneInfo.level)

        button.icon:SetTexture(icon or "Interface\\Icons\\INV_Misc_QuestionMark")
        button.keyLevel:SetText("+" .. keystoneInfo.level)
        button.keyLevel:SetTextColor(kr, kg, kb)
        button.dungeonName:SetText(shortName)
        local tr, tg, tb, ta = GetTextColor()
        button.dungeonName:SetTextColor(tr, tg, tb, ta)
        button.playerName:SetText("|c" .. classColor .. displayName .. "|r")

        local score, scoreColor = GetPlayerScoreInfo(unit)
        if score > 0 then
            button.score:SetText(string.format("|cff%02x%02x%02x%d|r", scoreColor.r*255, scoreColor.g*255, scoreColor.b*255, score))
        else
            button.score:SetText("")
        end

        if spellID and IsSpellKnown(spellID) then
            button:SetAttribute("type", "spell")
            button:SetAttribute("spell", spellID)
            button.spellID = spellID
        else
            button:SetAttribute("type", nil)
            button:SetAttribute("spell", nil)
            button.spellID = nil
        end

        button.tooltipDungeon = C_ChallengeMode.GetMapUIInfo(keystoneInfo.challengeMapID)
    end

    if isLeader and not IsInRaid() then
        button.leaderIcon:Show()
    else
        button.leaderIcon:Hide()
    end

    UpdateButtonCooldown(button)
    button:Show()
end

local function HideButton(button)
    if InCombatLockdown() then return end
    button:Hide()
    button:SetAttribute("type", nil)
    button:SetAttribute("spell", nil)
    button.spellID = nil
    button.tooltipDungeon = nil
end

local function UpdateAllKeystones()
    if InCombatLockdown() or not IsEnabled() then return end

    for i = 0, 4 do
        HideButton(keystoneButtons[i])
    end

    if IsInRaid() then
        KeyTrackerFrame:SetHeight(HEADER_HEIGHT)
        return
    end

    local allKeystoneInfo = openRaidLib.GetAllKeystonesInfo()
    local buttonIndex = 0

    local myKeystoneInfo = openRaidLib.GetKeystoneInfo("player")
    if myKeystoneInfo and myKeystoneInfo.level and myKeystoneInfo.level > 0 then
        local isLeader = UnitIsGroupLeader("player")
        local myName = UnitName("player")
        if issecretvalue and issecretvalue(myName) then
            myName = nil -- @secret-policy: reject-secret-value (skip row this pass)
        end
        if myName then
            UpdateButton(keystoneButtons[buttonIndex], myKeystoneInfo, myName, "player", isLeader)
            buttonIndex = buttonIndex + 1
        end
    end

    local numMembers = GetNumGroupMembers()
    for i = 1, numMembers - 1 do
        local unitId = "party" .. i
        local unitName, realm = UnitName(unitId)
        if issecretvalue and issecretvalue(unitName) then
            unitName = nil -- @secret-policy: reject-secret-value (skip row this pass)
        end
        if issecretvalue and issecretvalue(realm) then
            realm = nil -- @secret-policy: reject-secret-value (fall back to short name)
        end

        if unitName and buttonIndex <= 4 then
            local fullName = unitName
            if realm and realm ~= "" then
                fullName = unitName .. "-" .. realm
            end

            local keystoneInfo = allKeystoneInfo[fullName] or allKeystoneInfo[unitName]

            if keystoneInfo and keystoneInfo.level and keystoneInfo.level > 0 then
                local isLeader = UnitIsGroupLeader(unitId)
                UpdateButton(keystoneButtons[buttonIndex], keystoneInfo, fullName, unitId, isLeader)
                buttonIndex = buttonIndex + 1
            end
        end
    end

    if buttonIndex > 0 then
        KeyTrackerFrame:SetHeight(TITLE_HEIGHT + (buttonIndex * ENTRY_HEIGHT) + ENTRY_PADDING_Y)
    else
        KeyTrackerFrame:SetHeight(HEADER_HEIGHT)
    end
end

local function UpdateAll()
    if not IsEnabled() then
        KeyTrackerFrame:Hide()
        return
    end
    UpdateAllKeystones()
end

local function RefreshKeyTracker()
    if InCombatLockdown() then return end
    PositionKeyTracker()
    local w = GetFrameWidth()
    KeyTrackerFrame:SetWidth(w)
    local rowW = w - (ENTRY_PADDING_X * 2)
    for i = 0, 4 do
        local button = keystoneButtons[i]
        if button then
            button:SetWidth(rowW)
        end
    end
    UpdateAllButtonFonts()
    ApplySkinColors()
    if IsEnabled() then
        UpdateAllKeystones()
    else
        KeyTrackerFrame:Hide()
    end
end

_G.QUI_RefreshKeyTracker = RefreshKeyTracker

if ns.Registry then
    ns.Registry:Register("keyTracker", {
        refresh = _G.QUI_RefreshKeyTracker,
        priority = 55,
        group = "data",
        importCategories = { "minimapDatatexts" },
    })
    ns.Registry:Register("keyTrackerSkin", {
        refresh = _G.QUI_RefreshKeyTracker,
        priority = 55,
        group = "skinning",
        importCategories = { "skinning", "theme" },
    })
end

local requestTimer = nil

local function RequestKeystones()
    if InCombatLockdown() then return end
    openRaidLib.RequestKeystoneDataFromParty()
    if not requestTimer then
        requestTimer = C_Timer.NewTimer(GROUP_CHANGE_DELAY, function()
            if not InCombatLockdown() then
                UpdateAll()
            end
            requestTimer = nil
        end)
    end
end

local function UpdateVisibility()
    if InCombatLockdown() then return end
    if not IsEnabled() then
        KeyTrackerFrame:Hide()
        return
    end

    local anyoneHasKey = false
    local myKeystoneInfo = openRaidLib.GetKeystoneInfo("player")
    if myKeystoneInfo and myKeystoneInfo.level and myKeystoneInfo.level > 0 then
        anyoneHasKey = true
    end

    if not anyoneHasKey and IsInGroup() then
        local allKeystoneInfo = openRaidLib.GetAllKeystonesInfo()
        for _, info in pairs(allKeystoneInfo) do
            if info and info.level and info.level > 0 then
                anyoneHasKey = true
                break
            end
        end
    end

    if not anyoneHasKey then
        KeyTrackerFrame:Hide()
        return
    end

    if PVEFrame and PVEFrame:IsShown() then
        KeyTrackerFrame:Show()
        UpdateAll()
    else
        KeyTrackerFrame:Hide()
    end
end

local pveFrameHooked = false

local function SetupPVEFrameHooks()
    if pveFrameHooked or not PVEFrame then return end
    pveFrameHooked = true

    PVEFrame:HookScript("OnShow", function()
        C_Timer.After(VISIBILITY_DELAY, function()
            UpdateVisibility()
            if KeyTrackerFrame:IsShown() and not InCombatLockdown() then
                RequestKeystones()
            end
        end)
    end)
    PVEFrame:HookScript("OnHide", function()
        if not InCombatLockdown() then
            KeyTrackerFrame:Hide()
        end
    end)
end

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
eventFrame:RegisterEvent("GROUP_JOINED")
eventFrame:RegisterEvent("GROUP_LEFT")
eventFrame:RegisterEvent("CHALLENGE_MODE_COMPLETED")
eventFrame:RegisterEvent("SPELL_UPDATE_COOLDOWN")

eventFrame:SetScript("OnEvent", function(self, event, ...)
    if event == "ADDON_LOADED" then
        local loadedAddon = ...
        if loadedAddon == "Blizzard_GroupFinder" then
            SetupPVEFrameHooks()
            PositionKeyTracker()
        end
    elseif event == "PLAYER_ENTERING_WORLD" then
        SetupPVEFrameHooks()
        PositionKeyTracker()
        ApplySkinColors()
        UpdateAllButtonFonts()
        C_Timer.After(INITIAL_REQUEST_DELAY, function()
            if not InCombatLockdown() then
                RequestKeystones()
            end
        end)
    elseif event == "GROUP_ROSTER_UPDATE" or event == "GROUP_JOINED" then
        C_Timer.After(GROUP_CHANGE_DELAY, function()
            if not InCombatLockdown() then
                RequestKeystones()
            end
        end)
    elseif event == "GROUP_LEFT" then
        C_Timer.After(UPDATE_DELAY, function()
            if not InCombatLockdown() then
                UpdateAll()
            end
        end)
    elseif event == "CHALLENGE_MODE_COMPLETED" then
        C_Timer.After(INITIAL_REQUEST_DELAY, function()
            if not InCombatLockdown() then
                RequestKeystones()
            end
        end)
    elseif event == "SPELL_UPDATE_COOLDOWN" then
        if not InCombatLockdown() then
            for i = 0, 4 do
                UpdateButtonCooldown(keystoneButtons[i])
            end
        end
    end
end)

if openRaidLib then
    openRaidLib.RegisterCallback(addonName, "KeystoneUpdate", function()
        C_Timer.After(UPDATE_DELAY, function()
            if not InCombatLockdown() then
                UpdateAll()
            end
        end)
    end)
end

KeyTrackerFrame:SetScript("OnMouseUp", function(self, button)
    if button == "RightButton" and not InCombatLockdown() then
        RequestKeystones()
        print(ns.L["|cFF56D1FFQUI:|r Refreshing party keys..."])
    end
end)

SetupPVEFrameHooks()
PositionKeyTracker()

C_Timer.After(INITIAL_KEYSTONE_REQUEST_DELAY, function()
    if not InCombatLockdown() then
        RequestKeystones()
    end
end)
