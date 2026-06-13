local addonName, ns = ...

local GetCore = ns.Helpers.GetCore
local SkinBase = ns.SkinBase
local Helpers = ns.Helpers

---------------------------------------------------------------------------
-- PLAYER POWER BAR ALT SKINNING
---------------------------------------------------------------------------
-- Replaces the encounter/quest-specific power bar (PlayerPowerBarAlt)
-- with a clean QUI-styled bar. Used for: Atramedes sound, Cho'gall
-- corruption, Darkmoon games, etc.
--
-- Approach: Hide Blizzard's bar, create custom replacement

local FONT_FLAGS = "OUTLINE"

-- Bar dimensions
local BAR_WIDTH = 250
local BAR_HEIGHT = 20

-- Locals for performance
local floor = math.floor
local UnitPower = UnitPower
local UnitPowerMax = UnitPowerMax
local GetUnitPowerBarInfo = GetUnitPowerBarInfo
local GetUnitPowerBarStrings = GetUnitPowerBarStrings
local ALTERNATE_POWER_INDEX = Enum.PowerType.Alternate or 10

-- Module state
local QUIAltPowerBar = nil
local isEnabled = false

local function RunAfterFirstFrame(callback, delay)
    if ns.RunAfterFirstFrame then
        return ns.RunAfterFirstFrame(callback, delay)
    end
    if C_Timer and C_Timer.After then
        return C_Timer.After(delay or 0, callback)
    end
    if type(callback) == "function" then
        return callback()
    end
    return nil
end

---------------------------------------------------------------------------
-- DATABASE ACCESS
---------------------------------------------------------------------------

local function GetDB()
    local core = GetCore()
    return core and core.db and core.db.profile or {}
end

local function GetGeneralSettings()
    local db = GetDB()
    return db.general or {}
end

local function GetModuleSkinColors()
    return SkinBase.GetSkinColors(GetGeneralSettings(), "powerBarAlt")
end

-- Legacy position helpers removed — frameAnchoring system handles positioning.

---------------------------------------------------------------------------
-- TOOLTIP HANDLING
---------------------------------------------------------------------------

local function OnEnter(self)
    if not self:IsVisible() or GameTooltip:IsForbidden() then return end

    GameTooltip:ClearAllPoints()
    GameTooltip_SetDefaultAnchor(GameTooltip, self)

    if self.powerName and self.powerTooltip then
        GameTooltip:SetText(self.powerName, 1, 1, 1)
        GameTooltip:AddLine(self.powerTooltip, nil, nil, nil, true)
        GameTooltip:Show()
    end
end

local function OnLeave()
    GameTooltip:Hide()
end

---------------------------------------------------------------------------
-- BAR UPDATE
---------------------------------------------------------------------------

local function UpdateBar(self)
    local barInfo = GetUnitPowerBarInfo("player")

    if barInfo then
        local powerName, powerTooltip = GetUnitPowerBarStrings("player")
        local power = UnitPower("player", ALTERNATE_POWER_INDEX)
        local maxPower = UnitPowerMax("player", ALTERNATE_POWER_INDEX)

        -- Calculate percentage safely (handles secret values from Midnight API)
        -- BUG-004: UnitPower can return secret values that pass nil checks but fail arithmetic
        local perc = 0
        local calcOk, calcResult = pcall(function()
            if power and maxPower and maxPower > 0 then
                return floor(power / maxPower * 100)
            end
            return 0
        end)
        if calcOk and calcResult then
            perc = calcResult
        end

        self.powerName = powerName
        self.powerTooltip = powerTooltip
        self.powerValue = power
        self.powerMaxValue = maxPower
        self.powerPercent = perc

        -- StatusBar handles secret values natively in SetMinMaxValues/SetValue
        self:SetMinMaxValues(barInfo.minPower or 0, maxPower or 0)
        self:SetValue(power or 0)

        -- Update text (perc is guaranteed safe from pcall)
        if powerName then
            self.text:SetText(string.format("%s: %d%%", powerName, perc))
        else
            self.text:SetText(string.format("%d%%", perc))
        end

        self:Show()
    else
        self.powerName = nil
        self.powerTooltip = nil
        self.powerValue = nil
        self.powerMaxValue = nil
        self.powerPercent = nil

        self:Hide()
    end
end

local function OnEvent(self, event, arg1, arg2)
    if event == "UNIT_POWER_UPDATE" then
        if arg1 == "player" and arg2 == "ALTERNATE" then
            UpdateBar(self)
        end
    elseif event == "UNIT_POWER_BAR_SHOW" or event == "UNIT_POWER_BAR_HIDE" then
        if arg1 == "player" then
            UpdateBar(self)
        end
    elseif event == "PLAYER_ENTERING_WORLD" then
        UpdateBar(self)
    end
end

---------------------------------------------------------------------------
-- BAR CREATION
---------------------------------------------------------------------------

local function CreateQUIAltPowerBar()
    local sr, sg, sb, sa, bgr, bgg, bgb, bga = GetModuleSkinColors()

    -- Create the status bar
    local bar = CreateFrame("StatusBar", "QUI_AltPowerBar", UIParent)
    bar:SetSize(BAR_WIDTH, BAR_HEIGHT)

    -- Default position; ApplyAllFrameAnchors overrides from frameAnchoring DB
    bar:SetPoint("TOP", UIParent, "TOP", 0, -100)

    bar:SetStatusBarTexture("Interface\\Buttons\\WHITE8x8")
    bar:SetStatusBarColor(sr, sg, sb)
    bar:SetMinMaxValues(0, 100)
    bar:SetValue(0)
    bar:Hide()

    -- Make movable (controlled by mover overlay)
    bar:SetMovable(true)
    bar:SetClampedToScreen(true)

    -- Create backdrop
    bar.backdrop = CreateFrame("Frame", nil, bar, "BackdropTemplate")
    SkinBase.SetExpandedPixelPoints(bar.backdrop, bar, 2)
    local safeLevel = bar:GetFrameLevel() - 1
    if safeLevel < 0 then
        safeLevel = 0
    end
    bar.backdrop:SetFrameLevel(safeLevel)
    SkinBase.ApplyPixelBackdrop(bar.backdrop, 1, true, true)
    Helpers.SetFrameBackdropColor(bar.backdrop, bgr, bgg, bgb, bga)
    Helpers.SetFrameBackdropBorderColor(bar.backdrop, sr, sg, sb, sa)

    -- Create text
    bar.text = bar:CreateFontString(nil, "OVERLAY")
    bar.text:SetPoint("CENTER", bar, "CENTER")
    bar.text:SetFont(STANDARD_TEXT_FONT, 11, FONT_FLAGS)
    bar.text:SetTextColor(1, 1, 1)
    bar.text:SetJustifyH("CENTER")

    -- Store colors for refresh and mark as skinned
    SkinBase.SetFrameData(bar, "skinColor", { sr, sg, sb, sa })
    SkinBase.SetFrameData(bar, "bgColor", { bgr, bgg, bgb, bga })
    SkinBase.MarkSkinned(bar)
    SkinBase.SkinFrameText(bar, { recurse = true })

    -- Tooltip support
    bar:EnableMouse(true)
    bar:SetScript("OnEnter", OnEnter)
    bar:SetScript("OnLeave", OnLeave)

    -- Event handling
    bar:RegisterUnitEvent("UNIT_POWER_UPDATE", "player")
    bar:RegisterUnitEvent("UNIT_POWER_BAR_SHOW", "player")
    bar:RegisterUnitEvent("UNIT_POWER_BAR_HIDE", "player")
    bar:RegisterEvent("PLAYER_ENTERING_WORLD")
    bar:SetScript("OnEvent", OnEvent)

    return bar
end

---------------------------------------------------------------------------
-- BLIZZARD BAR HIDING
---------------------------------------------------------------------------

local blizzardBarHooked = false

local function HideBlizzardBar()
    local bar = _G.PlayerPowerBarAlt
    if bar then
        bar:UnregisterAllEvents()
        bar:Hide()
        bar:SetAlpha(0)
    end

    -- Hook UnitPowerBarAlt_SetUp to catch bar creation/setup during encounters
    if not blizzardBarHooked and _G.UnitPowerBarAlt_SetUp then
        -- TAINT SAFETY: Defer to break taint chain from secure context.
        hooksecurefunc("UnitPowerBarAlt_SetUp", function(self)
            local bar = self
            C_Timer.After(0, function()
                if bar == _G.PlayerPowerBarAlt and isEnabled then
                    bar:UnregisterAllEvents()
                    bar:Hide()
                    bar:SetAlpha(0)
                end
            end)
        end)
        blizzardBarHooked = true
    end
end

---------------------------------------------------------------------------
-- POWER BAR WIDGET CARRY-ALONG
---------------------------------------------------------------------------
-- Blizzard parents UIWidgetPowerBarContainerFrame (prey hunt crystal and
-- other encounter widgets) to EncounterBar, a VerticalLayoutFrame whose
-- Layout() re-anchors its children on every widget update — so the
-- container must be reparented out, not just re-pinned. Since QUI replaces
-- PlayerPowerBarAlt with its own bar at the powerBarAlt anchor, the widget
-- container rides along below the QUI bar; otherwise those widgets stay at
-- Blizzard's default bottom-center position while the user's encounter bar
-- lives elsewhere.

local widgetCarryInstalled = false

local function PowerBarWidgetsMoverActive()
    -- The Blizzard Frame Mover has its own "Power Bar Widgets" entry
    -- (default off). If the user enabled it, that system owns the
    -- container's position — don't fight it.
    local mover = GetDB().blizzardMover
    if not mover or not mover.enabled or not mover.frames then return false end
    local row = mover.frames.UIWidgetPowerBarContainerFrame
    return row ~= nil and row.enabled == true
end

local function CarryPowerBarWidgetContainer()
    if widgetCarryInstalled then return end
    if PowerBarWidgetsMoverActive() then return end
    local container = _G.UIWidgetPowerBarContainerFrame
    if not container or not QUIAltPowerBar then return end

    -- Combat /reload lands Initialize() in combat; the container isn't a
    -- protected frame, but defer anyway so the reparent never runs while
    -- Blizzard's encounter layout is live mid-fight.
    if InCombatLockdown() then
        local waiter = CreateFrame("Frame")
        waiter:RegisterEvent("PLAYER_REGEN_ENABLED")
        waiter:SetScript("OnEvent", function(self)
            self:UnregisterAllEvents()
            CarryPowerBarWidgetContainer()
        end)
        return
    end

    container:SetParent(UIParent)
    -- Non-fixed strata follows the parent on SetParent; keep EncounterBar's
    container:SetFrameStrata("MEDIUM")
    container:ClearAllPoints()
    container:SetPoint("TOP", QUIAltPowerBar, "BOTTOM", 0, -6)
    widgetCarryInstalled = true
end

---------------------------------------------------------------------------
-- REFRESH COLORS
---------------------------------------------------------------------------

local function RefreshPowerBarAltColors()
    if not QUIAltPowerBar then return end

    local sr, sg, sb, sa, bgr, bgg, bgb, bga = GetModuleSkinColors()

    QUIAltPowerBar:SetStatusBarColor(sr, sg, sb)
    Helpers.SetFrameBackdropColor(QUIAltPowerBar.backdrop, bgr, bgg, bgb, bga)
    Helpers.SetFrameBackdropBorderColor(QUIAltPowerBar.backdrop, sr, sg, sb, sa)

    SkinBase.SetFrameData(QUIAltPowerBar, "skinColor", { sr, sg, sb, sa })
    SkinBase.SetFrameData(QUIAltPowerBar, "bgColor", { bgr, bgg, bgb, bga })
end

_G.QUI_RefreshPowerBarAltColors = RefreshPowerBarAltColors

if ns.Registry then
    ns.Registry:Register("skinPowerBarAlt", {
        refresh = _G.QUI_RefreshPowerBarAltColors,
        priority = 80,
        group = "skinning",
        importCategories = { "skinning", "theme" },
    })
end

---------------------------------------------------------------------------
-- INITIALIZATION
---------------------------------------------------------------------------

local function Initialize()
    local core = GetCore()
    local settings = core and core.db and core.db.profile and core.db.profile.general

    if not settings or not settings.skinPowerBarAlt then return end
    if isEnabled then return end

    -- Hide Blizzard's bar
    HideBlizzardBar()

    -- Create our bar
    QUIAltPowerBar = CreateQUIAltPowerBar()

    -- Carry the Blizzard power-bar widget container (prey crystal, encounter
    -- widgets) along with the QUI bar's anchor
    CarryPowerBarWidgetContainer()

    -- Initial update
    UpdateBar(QUIAltPowerBar)

    isEnabled = true
end

-- LOD catch-up: first PEW already fired before this module loads, so the old
-- one-shot PLAYER_ENTERING_WORLD init runs via ns.WhenLoggedIn instead.
-- ns.WhenLoggedIn is nil only in the headless test harness, where the old
-- never-firing PEW registration was equally inert.
if ns.WhenLoggedIn then
    ns.WhenLoggedIn(function()
        RunAfterFirstFrame(function()
            Initialize()
        end, 0.1)
    end)
end
