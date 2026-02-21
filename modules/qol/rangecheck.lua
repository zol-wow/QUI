-- QUI Target Distance Bracket Display
-- Shows target distance as range brackets (e.g. 0-5, 5-10, 10-25, 25+)
-- Uses LibRangeCheck-3.0 when available, with a built-in fallback.
---------------------------------------------------------------------------
local ADDON_NAME, ns = ...
local QUI = QuaziiUI

local Helpers = ns.Helpers
local UIKit = ns.UIKit
local RangeLib = LibStub("LibRangeCheck-3.0", true)

local DEFAULT_SETTINGS = {
    enabled = false,
    combatOnly = false,
    showOnlyWithTarget = true,
    updateRate = 0.1,
    shortenText = false,
    dynamicColor = false,
    font = "Quazii",
    fontSize = 22,
    useClassColor = false,
    textColor = { 0.2, 0.95, 0.55, 1 },
    strata = "MEDIUM",
    offsetX = 0,
    offsetY = -190,
}

local DYNAMIC_RANGE_COLORS = {
    [0]  = { 0.2, 0.95, 0.55, 1 }, -- 0-4
    [5]  = { 0.8, 0.95, 0.2, 1 },  -- 5-9
    [10] = { 1, 0.75, 0.25, 1 },   -- 10-14
    [15] = { 1, 0.55, 0.2, 1 },    -- 15-19
    [20] = { 1, 0.35, 0.2, 1 },    -- 20-24
    [25] = { 1, 0.2, 0.2, 1 },     -- 25+
}

local state = {
    frame = nil,
    text = nil,
    ticker = nil,
    tickerInterval = nil,
    inCombat = false,
    preview = false,
    dragging = false,
    lastShown = false,
    lastText = nil,
    lastR = nil,
    lastG = nil,
    lastB = nil,
    lastA = nil,
}

-- Melee range abilities (5 yards only)
local MELEE_RANGE_ABILITIES = {
    96231, 6552, 1766, 116705, 183752,
    228478, 263642, 49143, 55090, 206930,
    100780, 100784, 107428,
    5221, 3252, 1822, 22568, 22570,
    33917, 6807,
}

-- Mid-range abilities (25 yards)
local MID_RANGE_ABILITIES = {
    361469, 356995, 382266, 357211, 355913, 360995, 364343, 366155,
    473662, 1226019, 473728,
}

local function GetSettings()
    local settings = Helpers.GetModuleSettings("rangeCheck", DEFAULT_SETTINGS)

    -- Backward compatibility for earlier iterations of this feature.
    if settings.dynamicColor == nil then
        settings.dynamicColor = settings.useBracketColors == true
    end

    return settings
end

local function HasAttackableTarget()
    if not UnitExists("target") then return false end
    if not UnitCanAttack("player", "target") then return false end
    if UnitIsDeadOrGhost("target") then return false end
    return true
end

local function IsOutOfMeleeRange()
    if not HasAttackableTarget() then return false end

    if IsActionInRange then
        for slot = 1, 180 do
            local actionType, id, subType = GetActionInfo(slot)
            if id and (actionType == "spell" or (actionType == "macro" and subType == "spell")) then
                for _, abilityID in ipairs(MELEE_RANGE_ABILITIES) do
                    if id == abilityID then
                        local inRange = IsActionInRange(slot)
                        if inRange == true then
                            return false
                        elseif inRange == false then
                            return true
                        end
                    end
                end
            end
        end
    end

    if IsSpellInRange then
        local attackInRange = IsSpellInRange("Attack", "target")
        if attackInRange == 1 then
            return false
        elseif attackInRange == 0 then
            return true
        end
    end

    if C_Spell and C_Spell.IsSpellInRange then
        for _, spellID in ipairs(MELEE_RANGE_ABILITIES) do
            if IsSpellKnown and IsSpellKnown(spellID) then
                local inRange = C_Spell.IsSpellInRange(spellID, "target")
                if inRange == true then
                    return false
                elseif inRange == false then
                    return true
                end
            end
        end
    end

    return false
end

local function IsOutOfMidRange()
    if not HasAttackableTarget() then return false end

    if IsActionInRange then
        local foundInRange, foundOutOfRange = false, false
        for slot = 1, 180 do
            local actionType, id, subType = GetActionInfo(slot)
            if id and (actionType == "spell" or (actionType == "macro" and subType == "spell")) then
                for _, abilityID in ipairs(MID_RANGE_ABILITIES) do
                    if id == abilityID then
                        local inRange = IsActionInRange(slot)
                        if inRange == false then
                            foundOutOfRange = true
                        elseif inRange == true then
                            foundInRange = true
                        end
                    end
                end
            end
        end
        if foundOutOfRange then return true end
        if foundInRange then return false end
    end

    if C_Spell and C_Spell.IsSpellInRange then
        for _, spellID in ipairs(MID_RANGE_ABILITIES) do
            if IsPlayerSpell and IsPlayerSpell(spellID) then
                local inRange = C_Spell.IsSpellInRange(spellID, "target")
                if inRange == true then
                    return false
                elseif inRange == false then
                    return true
                end
            end
        end
    end

    return false
end

local function GetFallbackRange()
    if not HasAttackableTarget() then
        return nil, nil
    end

    if not IsOutOfMeleeRange() then
        return 0, 5
    end

    local inTen = CheckInteractDistance and CheckInteractDistance("target", 3)
    if inTen == true then
        return 5, 10
    end

    if not IsOutOfMidRange() then
        if inTen == false then
            return 10, 25
        end
        return 5, 25
    end

    return 25, nil
end

local function GetTargetRange()
    if RangeLib and RangeLib.GetRange then
        local ok, minRange, maxRange = pcall(RangeLib.GetRange, RangeLib, "target")
        if ok and (minRange or maxRange) then
            return minRange, maxRange
        end
    end

    return GetFallbackRange()
end

local function GetBracketColor(settings, minRange)
    if settings.dynamicColor then
        if type(minRange) == "number" then
            local bucket = math.floor(minRange / 5) * 5
            if bucket < 0 then bucket = 0 end
            if bucket > 25 then bucket = 25 end
            local c = DYNAMIC_RANGE_COLORS[bucket] or DYNAMIC_RANGE_COLORS[25]
            if c then
                return c[1], c[2], c[3], c[4]
            end
        end
    end

    if settings.useClassColor then
        local r, g, b = Helpers.GetPlayerClassColor()
        return r, g, b, 1
    end

    local c = settings.textColor or DEFAULT_SETTINGS.textColor
    return c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1
end

local function FormatRangeText(minRange, maxRange, shortenText)
    local function RoundYards(v)
        if type(v) ~= "number" then return v end
        return math.floor(v + 0.5)
    end

    minRange = RoundYards(minRange)
    maxRange = RoundYards(maxRange)

    if minRange and maxRange then
        if shortenText then
            return string.format("%d-%d", minRange, maxRange)
        end
        return string.format("%d-%d yd", minRange, maxRange)
    end
    if maxRange then
        if shortenText then
            return string.format("0-%d", maxRange)
        end
        return string.format("0-%d yd", maxRange)
    end
    if minRange then
        if shortenText then
            return string.format("%d+", minRange)
        end
        return string.format("%d+ yd", minRange)
    end
    if shortenText then
        return "--"
    end
    return "-- yd"
end

local function CreateRangeFrame()
    if state.frame then return end

    local frame = CreateFrame("Frame", "QUI_RangeCheckFrame", UIParent, "BackdropTemplate")
    frame:SetSize(180, 30)
    frame:SetFrameStrata("MEDIUM")
    frame:SetMovable(true)
    frame:EnableMouse(false)
    frame:RegisterForDrag("LeftButton")

    local text = UIKit.CreateText(frame, 22, nil, "OUTLINE", "OVERLAY")
    text:SetPoint("CENTER", frame, "CENTER", 0, 0)
    text:SetText("10-25 yd")

    frame:SetScript("OnDragStart", function(self)
        if not state.preview then return end
        state.dragging = true
        self:StartMoving()
    end)

    frame:SetScript("OnDragStop", function(self)
        if not state.dragging then return end
        self:StopMovingOrSizing()
        state.dragging = false

        local settings = GetSettings()
        local frameX, frameY = self:GetCenter()
        local parentX, parentY = UIParent:GetCenter()
        if frameX and frameY and parentX and parentY then
            settings.offsetX = math.floor((frameX - parentX) + 0.5)
            settings.offsetY = math.floor((frameY - parentY) + 0.5)
        end
    end)

    frame.text = text
    frame:Hide()

    state.frame = frame
    state.text = text
    state.lastShown = false
end

local function ApplyAppearance()
    if not state.frame then
        CreateRangeFrame()
    end
    if not state.frame then return end

    local settings = GetSettings()
    local fontName = settings.font or "Quazii"
    local fontPath = UIKit.ResolveFontPath(fontName)
    local fontSize = settings.fontSize or 22

    state.frame:SetFrameStrata(settings.strata or "MEDIUM")
    state.text:SetFont(fontPath, fontSize, "OUTLINE")

    if not (_G.QUI_IsFrameOverridden and _G.QUI_IsFrameOverridden(state.frame)) then
        state.frame:ClearAllPoints()
        state.frame:SetPoint("CENTER", UIParent, "CENTER", settings.offsetX or 0, settings.offsetY or -190)
    end
end

local function SetDisplay(text, r, g, b, a)
    if not state.frame or not state.text then return end

    if text ~= state.lastText then
        state.text:SetText(text or "-- yd")
        state.lastText = text
    end

    if r ~= state.lastR or g ~= state.lastG or b ~= state.lastB or a ~= state.lastA then
        state.text:SetTextColor(r or 1, g or 1, b or 1, a or 1)
        state.lastR, state.lastG, state.lastB, state.lastA = r, g, b, a
    end

    if not state.lastShown then
        state.frame:Show()
        state.lastShown = true
    end
end

local function HideDisplay()
    if state.frame and state.lastShown then
        state.frame:Hide()
        state.lastShown = false
    end
end

local function ShouldShow(settings)
    if not settings.enabled then
        return false
    end
    if settings.combatOnly and not state.inCombat then
        return false
    end
    if settings.showOnlyWithTarget and not HasAttackableTarget() then
        return false
    end
    return true
end

local function UpdateRangeDisplay()
    if not state.frame then return end

    local settings = GetSettings()
    if state.preview then
        local r, g, b, a = GetBracketColor(settings, 10)
        SetDisplay(FormatRangeText(10, 25, settings.shortenText), r, g, b, a)
        return
    end

    if not ShouldShow(settings) then
        HideDisplay()
        return
    end

    local minRange, maxRange = GetTargetRange()
    local r, g, b, a = GetBracketColor(settings, minRange)
    SetDisplay(FormatRangeText(minRange, maxRange, settings.shortenText), r, g, b, a)
end

local function StopTicker()
    if state.ticker then
        state.ticker:Cancel()
        state.ticker = nil
    end
    state.tickerInterval = nil
end

local function StartTicker(settings)
    if not settings then return end
    local interval = tonumber(settings.updateRate) or 0.1
    if interval < 0.05 then interval = 0.05 end
    if interval > 0.5 then interval = 0.5 end

    if state.ticker and state.tickerInterval == interval then
        return
    end

    StopTicker()
    state.tickerInterval = interval
    state.ticker = C_Timer.NewTicker(interval, function()
        UpdateRangeDisplay()
        local currentSettings = GetSettings()
        if not (currentSettings.enabled and not state.preview and ShouldShow(currentSettings)) then
            StopTicker()
        end
    end)
end

local function SyncTickerState()
    local settings = GetSettings()
    if state.preview then
        StopTicker()
        return
    end
    if settings.enabled and ShouldShow(settings) then
        StartTicker(settings)
    else
        StopTicker()
    end
end

local function RefreshRangeCheck()
    CreateRangeFrame()
    ApplyAppearance()
    UpdateRangeDisplay()
    SyncTickerState()
end

local function TogglePreview(enabled)
    if enabled == nil then
        state.preview = not state.preview
    else
        state.preview = enabled == true
    end

    CreateRangeFrame()
    state.frame:EnableMouse(state.preview == true)

    if state.preview then
        StopTicker()
        ApplyAppearance()
        UpdateRangeDisplay()
    else
        if state.dragging and state.frame then
            state.frame:StopMovingOrSizing()
            state.dragging = false
        end
        RefreshRangeCheck()
    end
end

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
eventFrame:RegisterEvent("PLAYER_TARGET_CHANGED")
eventFrame:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_LOGIN" then
        C_Timer.After(1, function()
            state.inCombat = InCombatLockdown()
            RefreshRangeCheck()
        end)
        return
    end

    if event == "PLAYER_REGEN_DISABLED" then
        state.inCombat = true
    elseif event == "PLAYER_REGEN_ENABLED" then
        state.inCombat = false
    end

    UpdateRangeDisplay()
    SyncTickerState()
end)

_G.QUI_RefreshRangeCheck = RefreshRangeCheck
_G.QUI_ToggleRangeCheckPreview = TogglePreview
_G.QUI_IsRangeCheckPreviewMode = function()
    return state.preview == true
end

if QUI then
    QUI.RangeCheck = {
        Refresh = RefreshRangeCheck,
        TogglePreview = TogglePreview,
    }
end
