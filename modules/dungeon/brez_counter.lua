local ADDON_NAME, ns = ...
local QUI = ns.QUI or {}
ns.QUI = QUI
local Helpers = ns.Helpers
local QUICore = ns.Addon
local UIKit = ns.UIKit

local REBIRTH_SPELL_ID = 20484
local REBIRTH_ICON_ID = 136080

local REINCARNATION_SPELL_ID = 21169

local VALID_DIFFICULTIES = {
    [3]  = true,
    [4]  = true,
    [5]  = true,
    [6]  = true,
    [8]  = true,
    [14] = true,
    [15] = true,
    [16] = true,
    [17] = true,
    [23] = true,
    [33] = true,
}

local BrezState = {
    frame = nil,
    ticker = nil,
    isPreviewMode = false,
    isInRelevantContent = false,
    resHistory = {},
    encounterStartTime = 0,
    challengeStartTime = 0,
    inChallenge = false,
    inEncounter = false,
}

local GetSettings = Helpers.CreateDBGetter("brzCounter")

local function GetClassColor()
    local r, g, b = Helpers.GetPlayerClassColor()
    return { r, g, b, 1 }
end

local function SafeChargeNumber(value)
    if value == nil or Helpers.IsSecretValue(value) then
        return nil
    end
    local num = tonumber(value)
    if type(num) == "number" then
        return num
    end
    return nil
end

local function FormatTime(seconds)
    if seconds <= 0 then return "" end
    return Helpers.FormatMMSS(seconds)
end

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
    return Helpers.FormatMMSS(elapsed)
end

local GetClassColorByClass = Helpers.GetClassColor

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

    local SSB = QUICore and QUICore.SafeSetBackdrop
    if SSB then
        SSB(frame, UIKit.GetBackdropInfo(nil, nil, frame))
    else
        frame:SetBackdrop(UIKit.GetBackdropInfo(nil, nil, frame))
    end
    frame:SetBackdropColor(0, 0, 0, 0.6)

    UIKit.CreateBorderLines(frame)
    UIKit.UpdateBorderLines(frame, 1, 0, 0, 0, 1)

    local icon = frame:CreateTexture(nil, "ARTWORK")
    icon:SetAllPoints(frame)
    icon:SetTexture(REBIRTH_ICON_ID)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    frame.icon = icon

    local chargeText = frame:CreateFontString(nil, "OVERLAY")
    chargeText:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -2, 2)
    if ns.Helpers and ns.Helpers.ApplyFontWithFallback then
        ns.Helpers.ApplyFontWithFallback(chargeText, UIKit.ResolveFontPath(), 14, "OUTLINE")
    else
        chargeText:SetFont(UIKit.ResolveFontPath(), 14, "OUTLINE")
    end
    chargeText:SetTextColor(0.3, 1, 0.3, 1)
    chargeText:SetJustifyH("RIGHT")
    chargeText:SetText("0")
    frame.chargeText = chargeText

    local timerText = frame:CreateFontString(nil, "OVERLAY")
    timerText:SetPoint("TOPLEFT", frame, "TOPLEFT", 2, -2)
    if ns.Helpers and ns.Helpers.ApplyFontWithFallback then
        ns.Helpers.ApplyFontWithFallback(timerText, UIKit.ResolveFontPath(), 12, "OUTLINE")
    else
        timerText:SetFont(UIKit.ResolveFontPath(), 12, "OUTLINE")
    end
    timerText:SetTextColor(1, 1, 1, 1)
    timerText:SetJustifyH("LEFT")
    timerText:SetText("")
    frame.timerText = timerText

    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function(self)
        local settings = GetSettings()
        local locked = settings and settings.locked ~= false
        local isOverridden = _G.QUI_HasFrameAnchor and _G.QUI_HasFrameAnchor("brezCounter")
        if settings and not locked and not isOverridden and not InCombatLockdown() then
            self:StartMoving()
        end
    end)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local settings = GetSettings()
        if settings then
            local _, _, _, xOfs, yOfs = self:GetPoint()
            settings.xOffset = QUICore:PixelRound(xOfs)
            settings.yOffset = QUICore:PixelRound(yOfs)
        end
    end)

    frame:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(ns.L["Battle Res Charges"], 0.204, 1.0, 0.6)

        local chargeInfo = C_Spell.GetSpellCharges(REBIRTH_SPELL_ID)
        if chargeInfo then -- @secret-safe: SpellChargeInfo container is a plain table-or-nil (MayReturnNothing); secret-capable fields go to SafeChargeNumber below
            local currentCharges = SafeChargeNumber(chargeInfo.currentCharges)
            local maxCharges = SafeChargeNumber(chargeInfo.maxCharges)
            local cooldownDuration = SafeChargeNumber(chargeInfo.cooldownDuration)
            local cooldownStartTime = SafeChargeNumber(chargeInfo.cooldownStartTime)
            if currentCharges and maxCharges then
                GameTooltip:AddLine(string.format(ns.L["Charges: %d / %d"], currentCharges, maxCharges), 1, 1, 1)
            else
                GameTooltip:AddLine(ns.L["Charges: ?"], 1, 1, 1)
            end
            if currentCharges and maxCharges and cooldownDuration and cooldownStartTime
                and currentCharges < maxCharges and cooldownDuration > 0 then
                local remaining = (cooldownStartTime + cooldownDuration) - GetTime()
                if remaining > 0 then
                    GameTooltip:AddLine(string.format(ns.L["Next charge: %s"], FormatTime(remaining)), 0.8, 0.8, 0.8)
                end
            end
        end

        if #BrezState.resHistory > 0 then
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine(ns.L["Res History"], 0.204, 1.0, 0.6)
            for _, entry in ipairs(BrezState.resHistory) do
                local timeStr = FormatCombatTime(entry.timestamp)
                local sr, sg, sb = GetClassColorByClass(entry.sourceClass)
                if entry.spellId == REINCARNATION_SPELL_ID then
                    local line = string.format(ns.L["[%s] %s (Reincarnation)"], timeStr, entry.source)
                    GameTooltip:AddLine(line, sr, sg, sb)
                else
                    local tr, tg, tb = GetClassColorByClass(entry.targetClass)
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

local _lastDesaturated = true

local function UpdateDisplay()
    local frame = BrezState.frame
    if not frame then return end

    local settings = GetSettings()
    if not settings then return end

    if BrezState.isPreviewMode then
        frame.chargeText:SetText("2")
        frame.timerText:SetText("1:23")
        local hasColor = settings.hasChargesColor or { 0.3, 1, 0.3, 1 }
        frame.chargeText:SetTextColor(hasColor[1], hasColor[2], hasColor[3], hasColor[4] or 1)
        frame.icon:SetDesaturated(false)
        return
    end

    local chargeInfo = C_Spell.GetSpellCharges(REBIRTH_SPELL_ID)
    if not chargeInfo then -- @secret-safe: SpellChargeInfo container is a plain table-or-nil (MayReturnNothing); fields are probed/sunk below
        if settings.hideWhenUnavailable then
            frame:Hide()
        end
        frame.chargeText:SetText("?")
        frame.timerText:SetText("")
        frame.icon:SetDesaturated(true)
        _lastDesaturated = true
        return
    end

    if settings.hideWhenUnavailable and BrezState.isInRelevantContent and not frame:IsShown()
        and not (_G.QUI_IsFrameHiddenByAnchor and _G.QUI_IsFrameHiddenByAnchor("brezCounter")) then
        frame:Show()
    end

    pcall(frame.chargeText.SetFormattedText, frame.chargeText, "%d", chargeInfo.currentCharges)

    local charges = SafeChargeNumber(chargeInfo.currentCharges)
    local maxCharges = SafeChargeNumber(chargeInfo.maxCharges)

    if charges ~= nil and maxCharges ~= nil then
        if charges == 0 then
            local noColor = settings.noChargesColor or { 1, 0.3, 0.3, 1 }
            frame.chargeText:SetTextColor(noColor[1], noColor[2], noColor[3], noColor[4] or 1)
            frame.icon:SetDesaturated(true)
            _lastDesaturated = true
        else
            local hasColor = settings.hasChargesColor or { 0.3, 1, 0.3, 1 }
            frame.chargeText:SetTextColor(hasColor[1], hasColor[2], hasColor[3], hasColor[4] or 1)
            frame.icon:SetDesaturated(false)
            _lastDesaturated = false
        end

        local cooldownDuration = SafeChargeNumber(chargeInfo.cooldownDuration)
        local cooldownStartTime = SafeChargeNumber(chargeInfo.cooldownStartTime)
        if charges < maxCharges and cooldownDuration and cooldownStartTime and cooldownDuration > 0 then
            local remaining = (cooldownStartTime + cooldownDuration) - GetTime()
            if remaining > 0 then
                frame.timerText:SetText(FormatTime(remaining))
            else
                frame.timerText:SetText("")
            end
        else
            frame.timerText:SetText("")
        end
    end
end

local function StartTicker()
    if BrezState.ticker then return end
    BrezState.ticker = C_Timer.NewTicker(1, UpdateDisplay)
    UpdateDisplay()
end

local function StopTicker()
    if BrezState.ticker then
        BrezState.ticker:Cancel()
        BrezState.ticker = nil
    end
end

local function UpdateAppearance()
    if not BrezState.frame then
        CreateBrezFrame()
    end

    local settings = GetSettings()
    if not settings then return end

    local frame = BrezState.frame

    local width = settings.width or 50
    local height = settings.height or 50
    frame:SetSize(width, height)

    local xOffset = settings.xOffset or 500
    local yOffset = settings.yOffset or -50
    if not (_G.QUI_HasFrameAnchor and _G.QUI_HasFrameAnchor("brezCounter")) then
        frame:ClearAllPoints()
        frame:SetPoint("CENTER", UIParent, "CENTER", xOffset, yOffset)
    end

    local fontPath = UIKit.ResolveFontPath(settings.useCustomFont and settings.font)

    local fontSize = settings.fontSize or 14
    if ns.Helpers and ns.Helpers.ApplyFontWithFallback then
        ns.Helpers.ApplyFontWithFallback(frame.chargeText, fontPath, fontSize, "OUTLINE")
    else
        frame.chargeText:SetFont(fontPath, fontSize, "OUTLINE")
    end

    local timerFontSize = settings.timerFontSize or 12
    if ns.Helpers and ns.Helpers.ApplyFontWithFallback then
        ns.Helpers.ApplyFontWithFallback(frame.timerText, fontPath, timerFontSize, "OUTLINE")
    else
        frame.timerText:SetFont(fontPath, timerFontSize, "OUTLINE")
    end

    local timerColor
    if settings.useClassColorText then
        timerColor = GetClassColor()
    else
        timerColor = settings.timerColor or { 1, 1, 1, 1 }
    end
    frame.timerText:SetTextColor(timerColor[1], timerColor[2], timerColor[3], timerColor[4] or 1)

    local showBackdrop = settings.showBackdrop
    if showBackdrop == nil then showBackdrop = true end

    local borderSize = settings.borderSize or 1
    local borderTexture = settings.borderTexture or "None"
    local useLSMBorder = borderTexture ~= "None" and borderSize > 0

    local bR, bG, bB, bA = Helpers.GetSkinBorderColor(settings, "")

    local hideBorder = settings.hideBorder
    local effectiveUseLSMBorder = useLSMBorder and not hideBorder

    local SSB = QUICore and QUICore.SafeSetBackdrop
    if showBackdrop or effectiveUseLSMBorder then
        local borderColorTable = effectiveUseLSMBorder and { bR, bG, bB, bA } or nil
        local backdropInfo = UIKit.GetBackdropInfo(hideBorder and "None" or borderTexture, hideBorder and 0 or borderSize, frame)
        if SSB then
            SSB(frame, backdropInfo, borderColorTable)
        else
            frame:SetBackdrop(backdropInfo)
        end

        if showBackdrop then
            local bgColor = settings.backdropColor or { 0, 0, 0, 0.6 }
            frame:SetBackdropColor(bgColor[1], bgColor[2], bgColor[3], bgColor[4] or 0.6)
        else
            frame:SetBackdropColor(0, 0, 0, 0)
        end

        if effectiveUseLSMBorder and not SSB then
            frame:SetBackdropBorderColor(bR, bG, bB, bA)
        end
    else
        if SSB then
            SSB(frame, nil)
        else
            frame:SetBackdrop(nil)
        end
    end

    UIKit.CreateBorderLines(frame)
    UIKit.UpdateBorderLines(frame, borderSize, bR, bG, bB, bA, useLSMBorder or hideBorder)

    local locked = settings.locked ~= false
    frame:SetMovable(not locked)

    UpdateDisplay()
end

local function IsInRelevantContent()
    local _, _, difficultyID = GetInstanceInfo()
    return VALID_DIFFICULTIES[difficultyID] or false
end

local function ShowFrame()
    if not BrezState.frame then
        CreateBrezFrame()
    end
    UpdateAppearance()
    local settings = GetSettings()
    if settings and settings.hideWhenUnavailable and not BrezState.isPreviewMode
        and not C_Spell.GetSpellCharges(REBIRTH_SPELL_ID) then -- @secret-safe: plain table-or-nil container check
        BrezState.frame:Hide()
    else
        BrezState.frame:Show()
    end
    StartTicker()
end

local function HideFrame()
    if BrezState.frame then
        BrezState.frame:Hide()
    end
    StopTicker()
end

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

local function ResetHistory()
    wipe(BrezState.resHistory)
end

local function RefreshBrezCounter()
    local settings = GetSettings()

    if (not settings or not settings.enabled) and not BrezState.isPreviewMode then
        HideFrame()
        BrezState.isInRelevantContent = false
        return
    end

    UpdateAppearance()

    if not BrezState.isPreviewMode then
        EvaluateVisibility()
    end
end

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
            ShowFrame()
        else
            HideFrame()
        end
    end
end

local function IsPreviewMode()
    return BrezState.isPreviewMode
end

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("ENCOUNTER_START")
eventFrame:RegisterEvent("ENCOUNTER_END")
eventFrame:RegisterEvent("CHALLENGE_MODE_START")
eventFrame:RegisterEvent("CHALLENGE_MODE_COMPLETED")
eventFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")

eventFrame:SetScript("OnEvent", function(self, event, ...)
    if event == "PLAYER_ENTERING_WORLD" then
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
        if BrezState.frame then
            BrezState.frame:SetMovable(false)
        end

    elseif event == "PLAYER_REGEN_ENABLED" then
        if BrezState.frame then
            local settings = GetSettings()
            local locked = settings and settings.locked ~= false
            BrezState.frame:SetMovable(not locked)
        end

    end
end)

if ns.WhenLoggedIn then
    ns.WhenLoggedIn(function()
        CreateBrezFrame()
        EvaluateVisibility()
    end)
end

_G.QUI_RefreshBrezCounter = RefreshBrezCounter
_G.QUI_ToggleBrezCounterPreview = TogglePreview

QUI.BrezCounter = {
    Refresh = RefreshBrezCounter,
    TogglePreview = TogglePreview,
    IsPreviewMode = IsPreviewMode,
}

if ns.Registry then
    ns.Registry:Register("brezCounter", {
        refresh = _G.QUI_RefreshBrezCounter,
        priority = 40,
        group = "trackers",
        importCategories = { "trackersTimers" },
    })
end

if Helpers and Helpers.BorderRegistry then
    Helpers.BorderRegistry.Register({
        key = "brezCounter", label = ns.L["Brez Counter"], category = ns.L["Trackers"], prefix = "",
        db = function(p) return p.brzCounter end,
        refresh = function() if _G.QUI_RefreshBrezCounter then _G.QUI_RefreshBrezCounter() end end,
        legacy = { useClass = "useClassColorBorder", accent = "useAccentColorBorder" },
    })
end
