---------------------------------------------------------------------------
-- QUI Battle Res Counter
-- Displays available battle res charges and cooldown timer
-- Uses C_Spell.GetSpellCharges(20484) which returns the shared brez pool
---------------------------------------------------------------------------
local ADDON_NAME, ns = ...
local QUI = ns.QUI or {}
ns.QUI = QUI
local Helpers = ns.Helpers
local QUICore = ns.Addon
local UIKit = ns.UIKit

---------------------------------------------------------------------------
-- Constants
---------------------------------------------------------------------------
local REBIRTH_SPELL_ID = 20484
local REBIRTH_ICON_ID = 136080  -- Spell_Nature_Reincarnation (Rebirth icon)

-- All battle res spell IDs for combat log tracking
local BREZ_SPELL_IDS = {
    [20484]  = true,  -- Rebirth (Druid)
    [61999]  = true,  -- Raise Ally (Death Knight)
    [95750]  = true,  -- Soulstone Resurrection (Warlock)
    [391054] = true,  -- Intercession (Paladin)
    [345130] = true,  -- Disposable Spectrophasic Reanimator (Engineering)
    [385403] = true,  -- Tinker: Arclight Vital Correctors (Engineering)
    [384893] = true,  -- Convincingly Realistic Jumper Cables (Engineering)
}
local REINCARNATION_SPELL_ID = 21169  -- Shaman self-res

-- Raid difficulties that have battle res charges
local VALID_DIFFICULTIES = {
    [3]  = true,  -- 10-Player Raid
    [4]  = true,  -- 25-Player Raid
    [5]  = true,  -- 10-Player Heroic
    [6]  = true,  -- 25-Player Heroic
    [8]  = true,  -- Mythic Keystone
    [14] = true,  -- Normal Raid
    [15] = true,  -- Heroic Raid
    [16] = true,  -- Mythic Raid
    [17] = true,  -- LFR
    [23] = true,  -- Mythic Dungeon
    [33] = true,  -- Timewalking Raid
}

---------------------------------------------------------------------------
-- State tracking
---------------------------------------------------------------------------
local BrezState = {
    frame = nil,
    ticker = nil,
    isPreviewMode = false,
    isInRelevantContent = false,
    resHistory = {},  -- { { source, target, spellId, timestamp, sourceClass, targetClass } }
    encounterStartTime = 0,
    challengeStartTime = 0,
    inChallenge = false,
    inEncounter = false,
}

---------------------------------------------------------------------------
-- Get settings from database
---------------------------------------------------------------------------
local function GetSettings()
    return Helpers.GetModuleDB("brzCounter")
end

local function GetClassColor()
    local r, g, b = Helpers.GetPlayerClassColor()
    return { r, g, b, 1 }
end

---------------------------------------------------------------------------
-- Format time as M:SS
---------------------------------------------------------------------------
local function FormatTime(seconds)
    if seconds <= 0 then return "" end
    local mins = math.floor(seconds / 60)
    local secs = math.floor(seconds % 60)
    return string.format("%d:%02d", mins, secs)
end

---------------------------------------------------------------------------
-- Format combat-relative timestamp as M:SS
---------------------------------------------------------------------------
local function FormatCombatTime(timestamp)
    local baseTime = 0
    if BrezState.inChallenge and BrezState.challengeStartTime > 0 then
        baseTime = BrezState.challengeStartTime
    elseif BrezState.inEncounter and BrezState.encounterStartTime > 0 then
        baseTime = BrezState.encounterStartTime
    end
    if baseTime == 0 then return "0:00" end
    local elapsed = timestamp - baseTime
    if elapsed < 0 then elapsed = 0 end
    local mins = math.floor(elapsed / 60)
    local secs = math.floor(elapsed % 60)
    return string.format("%d:%02d", mins, secs)
end

---------------------------------------------------------------------------
-- Get class color for a unit GUID
---------------------------------------------------------------------------
local CLASS_COLORS = RAID_CLASS_COLORS

local function GetClassColorByClass(className)
    if className and CLASS_COLORS and CLASS_COLORS[className] then
        local c = CLASS_COLORS[className]
        return c.r, c.g, c.b
    end
    return 1, 1, 1
end

---------------------------------------------------------------------------
-- Create the brez counter frame
---------------------------------------------------------------------------
local function CreateBrezFrame()
    if BrezState.frame then return end

    local frame = CreateFrame("Frame", "QUI_BrezCounter", UIParent, "BackdropTemplate")
    frame:SetPoint("CENTER", UIParent, "CENTER", 500, -50)
    frame:SetSize(50, 50)
    frame:SetFrameStrata("HIGH")
    frame:SetFrameLevel(50)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:SetClampedToScreen(true)

    -- Set up backdrop
    frame:SetBackdrop(UIKit.GetBackdropInfo(nil, nil, frame))
    frame:SetBackdropColor(0, 0, 0, 0.6)

    -- Create border lines
    UIKit.CreateBorderLines(frame)
    UIKit.UpdateBorderLines(frame, 1, 0, 0, 0, 1)

    -- Spell icon texture
    local icon = frame:CreateTexture(nil, "BACKGROUND")
    icon:SetAllPoints(frame)
    icon:SetTexture(REBIRTH_ICON_ID)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)  -- Crop icon borders
    frame.icon = icon

    -- Charges text (bottom-right)
    local chargeText = frame:CreateFontString(nil, "OVERLAY")
    chargeText:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -2, 2)
    chargeText:SetFont(UIKit.ResolveFontPath(), 14, "OUTLINE")
    chargeText:SetTextColor(0.3, 1, 0.3, 1)
    chargeText:SetJustifyH("RIGHT")
    chargeText:SetText("0")
    frame.chargeText = chargeText

    -- Timer text (top-left)
    local timerText = frame:CreateFontString(nil, "OVERLAY")
    timerText:SetPoint("TOPLEFT", frame, "TOPLEFT", 2, -2)
    timerText:SetFont(UIKit.ResolveFontPath(), 12, "OUTLINE")
    timerText:SetTextColor(1, 1, 1, 1)
    timerText:SetJustifyH("LEFT")
    timerText:SetText("")
    frame.timerText = timerText

    -- Drag handling (only out of combat)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function(self)
        if not InCombatLockdown() then
            self:StartMoving()
        end
    end)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        -- Save position back to settings
        local settings = GetSettings()
        if settings then
            local _, _, _, xOfs, yOfs = self:GetPoint()
            settings.xOffset = QUICore:PixelRound(xOfs)
            settings.yOffset = QUICore:PixelRound(yOfs)
        end
    end)

    -- Tooltip
    frame:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Battle Res Charges", 0.204, 1.0, 0.6)

        -- Current charges info
        local chargeInfo = C_Spell.GetSpellCharges(REBIRTH_SPELL_ID)
        if chargeInfo then
            GameTooltip:AddLine(string.format("Charges: %d / %d", chargeInfo.currentCharges, chargeInfo.maxCharges), 1, 1, 1)
            if chargeInfo.currentCharges < chargeInfo.maxCharges and chargeInfo.cooldownDuration > 0 then
                local remaining = (chargeInfo.cooldownStartTime + chargeInfo.cooldownDuration) - GetTime()
                if remaining > 0 then
                    GameTooltip:AddLine(string.format("Next charge: %s", FormatTime(remaining)), 0.8, 0.8, 0.8)
                end
            end
        end

        -- Res history
        if #BrezState.resHistory > 0 then
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine("Res History", 0.204, 1.0, 0.6)
            for _, entry in ipairs(BrezState.resHistory) do
                local timeStr = FormatCombatTime(entry.timestamp)
                local sr, sg, sb = GetClassColorByClass(entry.sourceClass)
                if entry.spellId == REINCARNATION_SPELL_ID then
                    -- Reincarnation: self-res, no target
                    local line = string.format("[%s] %s (Reincarnation)", timeStr, entry.source)
                    GameTooltip:AddLine(line, sr, sg, sb)
                else
                    local tr, tg, tb = GetClassColorByClass(entry.targetClass)
                    -- Two-part colored line: source >> target
                    GameTooltip:AddDoubleLine(
                        string.format("[%s] %s >>", timeStr, entry.source),
                        entry.target,
                        sr, sg, sb,
                        tr, tg, tb
                    )
                end
            end
        end

        GameTooltip:Show()
    end)
    frame:SetScript("OnLeave", function(self)
        GameTooltip:Hide()
    end)

    frame:Hide()
    BrezState.frame = frame
end

---------------------------------------------------------------------------
-- Update the display (called by ticker)
---------------------------------------------------------------------------
local function UpdateDisplay()
    local frame = BrezState.frame
    if not frame then return end

    local settings = GetSettings()
    if not settings then return end

    -- In preview mode, show static data
    if BrezState.isPreviewMode then
        frame.chargeText:SetText("2")
        frame.timerText:SetText("1:23")
        local hasColor = settings.hasChargesColor or { 0.3, 1, 0.3, 1 }
        frame.chargeText:SetTextColor(hasColor[1], hasColor[2], hasColor[3], hasColor[4] or 1)
        frame.icon:SetDesaturated(false)
        return
    end

    local chargeInfo = C_Spell.GetSpellCharges(REBIRTH_SPELL_ID)
    if not chargeInfo then
        frame.chargeText:SetText("?")
        frame.timerText:SetText("")
        frame.icon:SetDesaturated(true)
        return
    end

    local charges = chargeInfo.currentCharges
    local maxCharges = chargeInfo.maxCharges

    -- Update charges text
    frame.chargeText:SetText(tostring(charges))

    -- Color based on charges available
    if charges == 0 then
        local noColor = settings.noChargesColor or { 1, 0.3, 0.3, 1 }
        frame.chargeText:SetTextColor(noColor[1], noColor[2], noColor[3], noColor[4] or 1)
        frame.icon:SetDesaturated(true)
    else
        local hasColor = settings.hasChargesColor or { 0.3, 1, 0.3, 1 }
        frame.chargeText:SetTextColor(hasColor[1], hasColor[2], hasColor[3], hasColor[4] or 1)
        frame.icon:SetDesaturated(false)
    end

    -- Update timer text
    if charges < maxCharges and chargeInfo.cooldownDuration > 0 then
        local remaining = (chargeInfo.cooldownStartTime + chargeInfo.cooldownDuration) - GetTime()
        if remaining > 0 then
            frame.timerText:SetText(FormatTime(remaining))
        else
            frame.timerText:SetText("")
        end
    else
        frame.timerText:SetText("")
    end
end

---------------------------------------------------------------------------
-- Start/stop the update ticker
---------------------------------------------------------------------------
local function StartTicker()
    if BrezState.ticker then return end
    BrezState.ticker = C_Timer.NewTicker(1, UpdateDisplay)
    UpdateDisplay()  -- Immediate first update
end

local function StopTicker()
    if BrezState.ticker then
        BrezState.ticker:Cancel()
        BrezState.ticker = nil
    end
end

---------------------------------------------------------------------------
-- Update frame appearance from settings
---------------------------------------------------------------------------
local function UpdateAppearance()
    if not BrezState.frame then
        CreateBrezFrame()
    end

    local settings = GetSettings()
    if not settings then return end

    local frame = BrezState.frame

    -- Update size
    local width = settings.width or 50
    local height = settings.height or 50
    frame:SetSize(width, height)

    -- Update position
    local xOffset = settings.xOffset or 500
    local yOffset = settings.yOffset or -50
    frame:ClearAllPoints()
    frame:SetPoint("CENTER", UIParent, "CENTER", xOffset, yOffset)

    -- Update fonts
    local fontPath = UIKit.ResolveFontPath(settings.useCustomFont and settings.font)

    local fontSize = settings.fontSize or 14
    frame.chargeText:SetFont(fontPath, fontSize, "OUTLINE")

    local timerFontSize = settings.timerFontSize or 12
    frame.timerText:SetFont(fontPath, timerFontSize, "OUTLINE")

    -- Update timer text color
    local timerColor
    if settings.useClassColorText then
        timerColor = GetClassColor()
    else
        timerColor = settings.timerColor or { 1, 1, 1, 1 }
    end
    frame.timerText:SetTextColor(timerColor[1], timerColor[2], timerColor[3], timerColor[4] or 1)

    -- Update backdrop and border
    local showBackdrop = settings.showBackdrop
    if showBackdrop == nil then showBackdrop = true end

    local borderSize = settings.borderSize or 1
    local borderTexture = settings.borderTexture or "None"
    local useLSMBorder = borderTexture ~= "None" and borderSize > 0

    local borderColor
    if settings.useClassColorBorder then
        borderColor = GetClassColor()
    elseif settings.useAccentColorBorder then
        local QUI = _G.QUI
        if QUI and QUI.GetAddonAccentColor then
            local ar, ag, ab, aa = QUI:GetAddonAccentColor()
            borderColor = { ar, ag, ab, aa }
        else
            borderColor = settings.borderColor or { 0, 0, 0, 1 }
        end
    else
        borderColor = settings.borderColor or { 0, 0, 0, 1 }
    end

    local hideBorder = settings.hideBorder
    local effectiveUseLSMBorder = useLSMBorder and not hideBorder

    if showBackdrop or effectiveUseLSMBorder then
        frame:SetBackdrop(UIKit.GetBackdropInfo(hideBorder and "None" or borderTexture, hideBorder and 0 or borderSize, frame))

        if showBackdrop then
            local bgColor = settings.backdropColor or { 0, 0, 0, 0.6 }
            frame:SetBackdropColor(bgColor[1], bgColor[2], bgColor[3], bgColor[4] or 0.6)
        else
            frame:SetBackdropColor(0, 0, 0, 0)
        end

        if effectiveUseLSMBorder then
            frame:SetBackdropBorderColor(borderColor[1], borderColor[2], borderColor[3], borderColor[4] or 1)
        end
    else
        frame:SetBackdrop(nil)
    end

    -- Update manual border lines
    UIKit.CreateBorderLines(frame)
    UIKit.UpdateBorderLines(frame, borderSize, borderColor[1], borderColor[2], borderColor[3], borderColor[4] or 1, useLSMBorder or hideBorder)

    -- Update display immediately
    UpdateDisplay()
end

---------------------------------------------------------------------------
-- Check if current content supports brez tracking
---------------------------------------------------------------------------
local function IsInRelevantContent()
    local _, _, difficultyID = GetInstanceInfo()
    return VALID_DIFFICULTIES[difficultyID] or false
end

---------------------------------------------------------------------------
-- Show/hide the frame based on context
---------------------------------------------------------------------------
local function ShowFrame()
    if not BrezState.frame then
        CreateBrezFrame()
    end
    UpdateAppearance()
    BrezState.frame:Show()
    StartTicker()
end

local function HideFrame()
    if BrezState.frame then
        BrezState.frame:Hide()
    end
    StopTicker()
end

---------------------------------------------------------------------------
-- Evaluate visibility (called on zone change, settings change, etc.)
---------------------------------------------------------------------------
local function EvaluateVisibility()
    local settings = GetSettings()
    if not settings or not settings.enabled then
        if not BrezState.isPreviewMode then
            HideFrame()
            BrezState.isInRelevantContent = false
        end
        return
    end

    if BrezState.isPreviewMode then return end

    local inContent = IsInRelevantContent()
    BrezState.isInRelevantContent = inContent

    if inContent then
        ShowFrame()
    else
        HideFrame()
    end
end

---------------------------------------------------------------------------
-- Combat log handler for res history
---------------------------------------------------------------------------
local function OnCombatLogEvent()
    local _, subEvent, _, sourceGUID, sourceName, sourceFlags, _, destGUID, destName, destFlags, _, spellId = CombatLogGetCurrentEventInfo()

    if not spellId then return end

    -- Check for brez spells (SPELL_RESURRECT)
    if subEvent == "SPELL_RESURRECT" and BREZ_SPELL_IDS[spellId] then
        local sourceClass = select(2, GetPlayerInfoByGUID(sourceGUID))
        local targetClass = select(2, GetPlayerInfoByGUID(destGUID))
        table.insert(BrezState.resHistory, {
            source = sourceName or "Unknown",
            target = destName or "Unknown",
            spellId = spellId,
            timestamp = GetTime(),
            sourceClass = sourceClass,
            targetClass = targetClass,
        })
        -- Trigger immediate display update
        UpdateDisplay()
    end

    -- Check for Reincarnation (self-res via SPELL_CAST_SUCCESS)
    if subEvent == "SPELL_CAST_SUCCESS" and spellId == REINCARNATION_SPELL_ID then
        local sourceClass = select(2, GetPlayerInfoByGUID(sourceGUID))
        table.insert(BrezState.resHistory, {
            source = sourceName or "Unknown",
            target = sourceName or "Unknown",
            spellId = REINCARNATION_SPELL_ID,
            timestamp = GetTime(),
            sourceClass = sourceClass,
            targetClass = sourceClass,
        })
        UpdateDisplay()
    end
end

---------------------------------------------------------------------------
-- Reset res history
---------------------------------------------------------------------------
local function ResetHistory()
    wipe(BrezState.resHistory)
end

---------------------------------------------------------------------------
-- Refresh function (called when settings change)
---------------------------------------------------------------------------
local function RefreshBrezCounter()
    local settings = GetSettings()

    if (not settings or not settings.enabled) and not BrezState.isPreviewMode then
        HideFrame()
        BrezState.isInRelevantContent = false
        return
    end

    UpdateAppearance()

    -- Re-evaluate visibility
    if not BrezState.isPreviewMode then
        EvaluateVisibility()
    end
end

---------------------------------------------------------------------------
-- Toggle preview mode (for options panel)
---------------------------------------------------------------------------
local function TogglePreview(enable)
    CreateBrezFrame()
    if not BrezState.frame then return end

    BrezState.isPreviewMode = enable

    if enable then
        UpdateAppearance()
        BrezState.frame:Show()
        StartTicker()
    else
        local settings = GetSettings()
        if settings and settings.enabled and BrezState.isInRelevantContent then
            UpdateAppearance()
            BrezState.frame:Show()
            StartTicker()
        else
            HideFrame()
        end
    end
end

local function IsPreviewMode()
    return BrezState.isPreviewMode
end

---------------------------------------------------------------------------
-- Event handler
---------------------------------------------------------------------------
local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("ENCOUNTER_START")
eventFrame:RegisterEvent("ENCOUNTER_END")
eventFrame:RegisterEvent("CHALLENGE_MODE_START")
eventFrame:RegisterEvent("CHALLENGE_MODE_COMPLETED")
eventFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")

eventFrame:SetScript("OnEvent", function(self, event, ...)
    if event == "PLAYER_LOGIN" then
        C_Timer.After(1, function()
            CreateBrezFrame()
            EvaluateVisibility()
        end)

    elseif event == "PLAYER_ENTERING_WORLD" then
        -- Delay 1 frame to let instance info settle
        C_Timer.After(0, function()
            EvaluateVisibility()
        end)

    elseif event == "ENCOUNTER_START" then
        BrezState.inEncounter = true
        BrezState.encounterStartTime = GetTime()
        ResetHistory()
        EvaluateVisibility()

    elseif event == "ENCOUNTER_END" then
        BrezState.inEncounter = false

    elseif event == "CHALLENGE_MODE_START" then
        BrezState.inChallenge = true
        BrezState.challengeStartTime = GetTime()
        ResetHistory()
        EvaluateVisibility()

    elseif event == "CHALLENGE_MODE_COMPLETED" then
        BrezState.inChallenge = false

    elseif event == "PLAYER_REGEN_DISABLED" then
        -- Lock frame during combat
        if BrezState.frame then
            BrezState.frame:SetMovable(false)
        end

    elseif event == "PLAYER_REGEN_ENABLED" then
        -- Unlock frame out of combat
        if BrezState.frame then
            BrezState.frame:SetMovable(true)
        end

    end
end)

-- COMBAT_LOG_EVENT_UNFILTERED is protected in 12.0; RegisterEvent/RegisterFrameEventAndCallback
-- both trigger ADDON_ACTION_FORBIDDEN. Use RegisterCallback which subscribes to Blizzard's
-- own internal dispatch without calling RegisterEvent.
EventRegistry:RegisterCallback("COMBAT_LOG_EVENT_UNFILTERED", OnCombatLogEvent, eventFrame)

---------------------------------------------------------------------------
-- Global functions for GUI
---------------------------------------------------------------------------
_G.QUI_RefreshBrezCounter = RefreshBrezCounter
_G.QUI_ToggleBrezCounterPreview = TogglePreview
_G.QUI_IsBrezCounterPreviewMode = IsPreviewMode

QUI.BrezCounter = {
    Refresh = RefreshBrezCounter,
    TogglePreview = TogglePreview,
    IsPreviewMode = IsPreviewMode,
}
