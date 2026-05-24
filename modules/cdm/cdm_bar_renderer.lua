--[[
    QUI CDM Bar Factory

    Creates and manages addon-owned bar frames for the CDM tracked bar system.
    All bars are simple Frame objects with StatusBar children — no protected
    attributes, eliminating combat taint concerns for frame operations.

    All bar state flows through QUI's resolver pipeline. When a composer entry
    is backed by a native viewer child, bars render that mirror payload directly.

    Pattern mirrors cdm_icon_renderer.lua pool management.
]]

local _, ns = ...
local Helpers = ns.Helpers
local QUICore = ns.Addon
local LSM = ns.LSM

---------------------------------------------------------------------------
-- MODULE
---------------------------------------------------------------------------
local CDMBars = {}
ns.CDMBars = CDMBars
local Sources = ns.CDMSources
local Renderers = ns.CDMRenderers

---------------------------------------------------------------------------
-- HELPERS
---------------------------------------------------------------------------
local GetGeneralFont = Helpers.GetGeneralFont
local GetGeneralFontOutline = Helpers.GetGeneralFontOutline
local GetTime = GetTime
local InCombatLockdown = InCombatLockdown

-- Upvalue hot-path globals
local type = type
local ipairs = ipairs
local CreateFrame = CreateFrame
local issecretvalue = issecretvalue

---------------------------------------------------------------------------
-- CONSTANTS
---------------------------------------------------------------------------
local MAX_RECYCLE_POOL_SIZE = 20
local STATUS_BAR_INTERPOLATION_IMMEDIATE = 0
local STATUS_BAR_TIMER_REMAINING = 1

local function SetStatusBarValue(statusBar, value)
    if Renderers and Renderers.SetStatusBarValue then
        return Renderers.SetStatusBarValue(statusBar, value, 0, 1)
    end
    if not statusBar then return false end
    statusBar:SetMinMaxValues(0, 1)
    statusBar:SetValue(value)
    return true
end

local function SetStatusBarFull(statusBar)
    if Renderers and Renderers.SetStatusBarFull then
        return Renderers.SetStatusBarFull(statusBar)
    end
    return SetStatusBarValue(statusBar, 1)
end

local function ClearStatusBar(statusBar)
    if Renderers and Renderers.ClearStatusBar then
        return Renderers.ClearStatusBar(statusBar)
    end
    return SetStatusBarValue(statusBar, 0)
end

local function SetStatusBarTimerDuration(statusBar, durObj)
    if Renderers and Renderers.SetStatusBarTimerDuration then
        return Renderers.SetStatusBarTimerDuration(statusBar, durObj, STATUS_BAR_TIMER_REMAINING)
    end
    if not statusBar or not durObj or not statusBar.SetTimerDuration then
        return false
    end
    statusBar:SetTimerDuration(durObj, STATUS_BAR_INTERPOLATION_IMMEDIATE, STATUS_BAR_TIMER_REMAINING)
    return true
end

local function RearmVisibleDurationBarTimer(bar, deferOneFrame)
    if not (bar and bar._active and not bar._hideDurationText) then
        return false
    end

    local durObj = bar._durObj
    if not durObj or type(durObj) == "number" then
        return false
    end

    local statusBar = bar.StatusBar
    if not (statusBar and statusBar.SetTimerDuration) then
        return false
    end

    local ok = SetStatusBarTimerDuration(statusBar, durObj)
    if ok then
        bar._cSideFill = true
        bar._preferDurObjFill = true
    end

    if deferOneFrame and C_Timer and C_Timer.After and not bar._timerShowRearmPending then
        bar._timerShowRearmPending = true
        C_Timer.After(0, function()
            bar._timerShowRearmPending = nil
            RearmVisibleDurationBarTimer(bar, false)
        end)
    end

    return ok
end

---------------------------------------------------------------------------
-- STATE
---------------------------------------------------------------------------
local barPool = {}       -- active bars (array)
local recyclePool = {}   -- recycled bars (array, max MAX_RECYCLE_POOL_SIZE)
local barTimerFrame = CreateFrame("Frame")
local barTimerGroup = barTimerFrame:CreateAnimationGroup()
local barTimerAnim = barTimerGroup:CreateAnimation()
barTimerAnim:SetDuration(0.1)  -- 100ms = ~10 FPS
barTimerGroup:SetLooping("REPEAT")

do local mp = ns._memprobes or {}; ns._memprobes = mp
    mp[#mp + 1] = { name = "CDM_barPool",      tbl = barPool }
    mp[#mp + 1] = { name = "CDM_barRecycle",   tbl = recyclePool }
end

-- Stored refs for periodic re-layout after ticker updates _active state
local _lastContainer = nil
local _lastSettings = nil

---------------------------------------------------------------------------
-- DEFERRED RESIZE
-- The buff-bar container must keep adjusting its size during combat so
-- frames anchored to its growth edge track when bars activate/deactivate
-- mid-combat (and so the container itself follows an autoWidth parent that
-- resizes). LayoutBars is reached via UNIT_AURA dispatch, which
-- enters with taint inherited from the secure event chain; calling
-- container:SetSize directly fires ADDON_ACTION_BLOCKED 'UNKNOWN()' on the
-- protection check (pcall catches the Lua error but not the event itself).
-- C_Timer.After(0) defers the SetSize one tick into clean main-loop context,
-- breaking the taint chain so the call passes the protection check on a
-- non-protected QUI Frame. Multiple in-flight requests coalesce: each
-- container only resizes once per flush, with the latest target dimensions.
---------------------------------------------------------------------------
local _pendingResize = nil

local function _flushPendingResizes()
    local q = _pendingResize
    _pendingResize = nil
    if not q then return end
    for container, dims in pairs(q) do
        if container.SetSize then
            container:SetSize(dims.w, dims.h)
        end
        if _G.QUI_SetCDMViewerBounds then
            _G.QUI_SetCDMViewerBounds(container, dims.w, dims.h)
        end
    end
end

local function ResizeContainer(container, w, h)
    if not container then return end
    if container._lastBarLayoutW == w and container._lastBarLayoutH == h then
        return
    end
    container._lastBarLayoutW = w
    container._lastBarLayoutH = h

    if (not InCombatLockdown()) or ns._inInitSafeWindow then
        container:SetSize(w, h)
        if _G.QUI_SetCDMViewerBounds then
            _G.QUI_SetCDMViewerBounds(container, w, h)
        end
        return
    end

    if not _pendingResize then
        _pendingResize = {}
        C_Timer.After(0, _flushPendingResizes)
    end
    local entry = _pendingResize[container]
    if entry then
        entry.w = w
        entry.h = h
    else
        _pendingResize[container] = { w = w, h = h }
    end
end

---------------------------------------------------------------------------
-- PERMANENT-AURA OVERLAY DRIVE (curve trick via IsZero bool)
--
-- DurationObject:IsZero() returns a (potentially-secret) bool that is
-- stable for the aura's lifetime — it's a property of the durObj itself,
-- not derived from elapsed/remaining time, so it doesn't oscillate as
-- the aura ticks.
--
-- C_CurveUtil.EvaluateColorValueFromBoolean is a C-side helper that
-- selects between two numbers based on a (potentially-secret) bool —
-- the secret never crosses into Lua compares. The selected value may
-- still be secret, so only pass it directly to C-side sinks
-- (Texture:SetAlpha / FontString:SetAlpha).
-- See docs/blizzard/cdm-api-reference.md for the boolean decode policy.
--
-- Mapping for the bar overlay:
--   IsZero=true  (permanent) → alpha 1 (overlay visible — bar full)
--   IsZero=false (timed)     → alpha 0 (overlay invisible — bar shows
--                                       SetTimerDuration animation)
--
-- Mapping for the duration text:
--   IsZero=true  (permanent) → alpha 0 (text hidden — no countdown)
--   IsZero=false (timed)     → alpha 1 (text visible — countdown shows)
---------------------------------------------------------------------------

---------------------------------------------------------------------------
-- BAR FRAME FACTORY
---------------------------------------------------------------------------
local function CreateBar(parent)
    local bar = CreateFrame("Frame", nil, parent)
    bar:SetSize(200, 25)

    -- StatusBar for duration progress
    local statusBar = CreateFrame("StatusBar", nil, bar)
    ClearStatusBar(statusBar)
    bar.StatusBar = statusBar

    -- PermanentFill overlay: full-bar texture rendered above the StatusBar
    -- fill but below text. Alpha is curve-driven from the durObj's total
    -- duration in UpdateOwnedBarAura — visible only for no-expiration
    -- auras, completely invisible (no visual effect) for timed auras.
    local permanentFill = statusBar:CreateTexture(nil, "OVERLAY", nil, 1)
    permanentFill:SetAllPoints(statusBar)
    permanentFill:SetAlpha(0)
    bar.PermanentFill = permanentFill

    -- Background texture (BACKGROUND, sublevel -8)
    local bg = bar:CreateTexture(nil, "BACKGROUND", nil, -8)
    bg:SetColorTexture(0, 0, 0, 1)
    bar.Background = bg

    -- Icon container frame
    local iconContainer = CreateFrame("Frame", nil, bar)
    iconContainer:SetSize(25, 25)
    bar.IconContainer = iconContainer

    -- Icon texture inside container
    local iconTex = iconContainer:CreateTexture(nil, "ARTWORK")
    iconTex:SetAllPoints(iconContainer)
    iconTex:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    bar.IconTexture = iconTex

    -- Border container with 4-edge textures
    local borderFrame = CreateFrame("Frame", nil, bar)
    borderFrame:SetFrameLevel((bar.GetFrameLevel and bar:GetFrameLevel() or 1) + 5)
    borderFrame._top = borderFrame:CreateTexture(nil, "OVERLAY", nil, 7)
    borderFrame._top:SetColorTexture(0, 0, 0, 1)
    borderFrame._bottom = borderFrame:CreateTexture(nil, "OVERLAY", nil, 7)
    borderFrame._bottom:SetColorTexture(0, 0, 0, 1)
    borderFrame._left = borderFrame:CreateTexture(nil, "OVERLAY", nil, 7)
    borderFrame._left:SetColorTexture(0, 0, 0, 1)
    borderFrame._right = borderFrame:CreateTexture(nil, "OVERLAY", nil, 7)
    borderFrame._right:SetColorTexture(0, 0, 0, 1)
    bar.BorderContainer = borderFrame

    -- Text overlay frame (renders above StatusBar fill texture)
    local textOverlay = CreateFrame("Frame", nil, statusBar)
    textOverlay:SetAllPoints(statusBar)
    textOverlay:SetFrameLevel((statusBar.GetFrameLevel and statusBar:GetFrameLevel() or 1) + 2)
    bar.TextOverlay = textOverlay

    -- Name text (spell name)
    local nameText = textOverlay:CreateFontString(nil, "OVERLAY", nil, 7)
    nameText:SetFont(GetGeneralFont(), 14, GetGeneralFontOutline())
    nameText:SetPoint("LEFT", statusBar, "LEFT", 4, 0)
    nameText:SetJustifyH("LEFT")
    nameText:SetTextColor(1, 1, 1, 1)
    nameText:SetShadowColor(0, 0, 0, 1)
    nameText:SetShadowOffset(1, -1)
    bar.NameText = nameText

    -- Duration text (remaining time)
    local durationText = textOverlay:CreateFontString(nil, "OVERLAY", nil, 7)
    durationText:SetFont(GetGeneralFont(), 14, GetGeneralFontOutline())
    durationText:SetPoint("RIGHT", statusBar, "RIGHT", -4, 0)
    durationText:SetJustifyH("RIGHT")
    durationText:SetTextColor(1, 1, 1, 1)
    durationText:SetShadowColor(0, 0, 0, 1)
    durationText:SetShadowOffset(1, -1)
    bar.DurationText = durationText

    -- State tracking
    bar._spellEntry = nil
    bar._spellID = nil
    bar._active = false
    bar._cSideFill = nil
    bar._preferDurObjFill = nil

    bar:Hide()
    return bar
end

---------------------------------------------------------------------------
-- Helper functions for color overrides
---------------------------------------------------------------------------

-- Build a color-override key set from the bar's bound composer entry. Key
-- shape mirrors the legacy Blizzard-child-derived spellData (spellID /
-- baseSpellID / overrideSpellID / cooldownID) so colorOverride profiles
-- imported from earlier versions still match.
local function GetBarSpellData(bar)
    local entry = bar and bar._spellEntry
    if not entry then return nil end
    local baseSpellID = entry.spellID or entry.id
    local overrideSpellID = entry.overrideSpellID
    local resolvedSpellID = overrideSpellID or baseSpellID
    if not resolvedSpellID and not entry.name then return nil end
    return {
        spellID = resolvedSpellID,
        baseSpellID = baseSpellID or resolvedSpellID,
        overrideSpellID = overrideSpellID,
        name = entry.name,
        cooldownID = entry.cooldownID,
    }
end

-- Per-spell "Hide Duration Text" override lookup. Returns true when the
-- composer override forces hide for this bar's spell/container; nil otherwise.
local function GetBarSpellHideDurationOverride(bar)
    local entry = bar and bar._spellEntry
    if not entry then return nil end
    local CDMSpellData = ns.CDMSpellData
    if not CDMSpellData or not entry.viewerType then return nil end
    local spellID = entry.spellID or entry.id
    if not spellID then return nil end
    local ov = CDMSpellData:GetSpellOverride(entry.viewerType, spellID)
    if ov and ov.hideDurationText == true then return true end
    return nil
end

-- DebugBarLabel implementation lives in the load-on-demand debug addon.
-- The placeholder below is rebound by cdm_debug.lua's BindAll() when loaded.
local DebugBarLabel = function() end

local function ReadBoolean(value)
    if issecretvalue and issecretvalue(value) then return nil end
    if type(value) == "boolean" then return value end
    return nil
end

local function ReadNumber(value, fallback)
    if issecretvalue and issecretvalue(value) then return fallback end
    local valueType = type(value)
    if valueType == "number" then return value end
    if valueType == "string" then return tonumber(value) end
    return fallback
end

local function WrapStackSuffix(stackValue)
    if C_StringUtil and C_StringUtil.WrapString then
        return C_StringUtil.WrapString(stackValue, " (", ")")
    end
    return stackValue
end

local function IsMissingOrKnownEmptyText(value)
    if issecretvalue and issecretvalue(value) then return false end
    if value == nil then return true end
    return type(value) == "string" and value == ""
end

local function ValueIsPresent(value)
    if issecretvalue and issecretvalue(value) then return true end
    return value ~= nil
end

local function ApplyNameTextWithCount(fontString, name, count)
    if not fontString or not fontString.SetFormattedText or name == nil then
        return false, "missing-name"
    end

    if not count or ReadBoolean(count.shown) ~= true then
        fontString.SetFormattedText(fontString, "%s", name)
        return true, "name-only", nil, false
    end

    local countText = count.sinkText
    if not ValueIsPresent(countText) then
        countText = count.value
    end

    if IsMissingOrKnownEmptyText(countText) then
        fontString.SetFormattedText(fontString, "%s", name)
        return true, "name-only", nil, false
    end

    local wrappedStack = WrapStackSuffix(countText)
    if IsMissingOrKnownEmptyText(wrappedStack) then
        fontString.SetFormattedText(fontString, "%s", name)
        return true, "name-only", wrappedStack, false
    end

    fontString.SetFormattedText(fontString, "%s%s", name, wrappedStack)
    return true, "wrapped-count", wrappedStack, false
end

CDMBars.ApplyNameTextWithCount = ApplyNameTextWithCount

local function ShouldHideAuraDurationText(r)
    if not r or not r.isActive then return false end
    if r.isTotemInstance then return false end
    if r.hideDurationText or r.hasExpirationTime == false then return true end
    if not r.auraData then return false end
    if InCombatLockdown() then return false end

    local duration = ReadNumber(r.auraData.duration, nil)
    if duration == nil then
        return true
    end
    return duration <= 0
end

local function EnsureBarTimerRunning()
    if barTimerGroup and barTimerGroup.IsPlaying and barTimerGroup.Play
       and not barTimerGroup:IsPlaying() then
        barTimerGroup:Play()
    end
end

local function WriteDurationTextFromDurationObject(bar, durObj)
    if not (bar and durObj and durObj.GetRemainingDuration
        and bar.DurationText and not bar._hideDurationText) then
        return false
    end

    local remaining = durObj.GetRemainingDuration(durObj)
    bar.DurationText.SetFormattedText(bar.DurationText, "%.1f", remaining)
    return true
end

local function GetTrackedBarOverrideColor(settings, spellData)
    local overrides = settings and settings.colorOverrides
    if type(overrides) ~= "table" or type(spellData) ~= "table" then
        return nil
    end

    local color = spellData.spellID and overrides[spellData.spellID]
    if type(color) == "table" then
        return color
    end

    color = spellData.overrideSpellID and overrides[spellData.overrideSpellID]
    if type(color) == "table" then
        return color
    end

    color = spellData.baseSpellID and overrides[spellData.baseSpellID]
    if type(color) == "table" then
        return color
    end

    color = spellData.cooldownID and overrides[spellData.cooldownID]
    if type(color) == "table" then
        return color
    end

    return nil
end

---------------------------------------------------------------------------
-- CONFIGURE BAR
---------------------------------------------------------------------------
function CDMBars.ConfigureBar(bar, settings, overrideWidth)
    if not bar then return end

    local barHeight = settings.barHeight or 25
    local barWidth = overrideWidth or settings.barWidth or 215
    local texture = settings.texture or "Quazii v5"
    local useClassColor = settings.useClassColor
    local barColor = settings.barColor or {0.376, 0.647, 0.980, 1}
    local barOpacity = settings.barOpacity or 1.0
    local borderSize = settings.borderSize or 2
    local bgColor = settings.bgColor or {0, 0, 0, 1}
    local bgOpacity = settings.bgOpacity or 0.5
    local textSize = settings.textSize or 14
    local hideIcon = settings.hideIcon
    local hideText = settings.hideText

    -- Inactive visual settings
    local inactiveMode = settings.inactiveMode or "hide"
    if inactiveMode ~= "always" and inactiveMode ~= "fade" and inactiveMode ~= "hide" then
        inactiveMode = "hide"
    end
    local inactiveAlpha = settings.inactiveAlpha or 0.3
    if inactiveAlpha < 0 then inactiveAlpha = 0 end
    if inactiveAlpha > 1 then inactiveAlpha = 1 end
    local desaturateInactive = (settings.desaturateInactive == true)

    -- Vertical bar settings
    local orientation = settings.orientation or "horizontal"
    local isVertical = (orientation == "vertical")
    local fillDirection = settings.fillDirection or "up"
    local iconPosition = settings.iconPosition or "top"
    local showTextOnVertical = settings.showTextOnVertical or false

    local isActive = bar._active
    local spellData = GetBarSpellData(bar)
    local overrideColor = GetTrackedBarOverrideColor(settings, spellData)

    -- For vertical bars: swap width/height conceptually
    local frameWidth, frameHeight
    if isVertical then
        frameWidth = barHeight
        frameHeight = barWidth
    else
        frameWidth = barWidth
        frameHeight = barHeight
    end

    -- Set bar dimensions
    bar:SetSize(frameWidth, frameHeight)

    local statusBar = bar.StatusBar
    if statusBar then
        statusBar:SetSize(frameWidth, frameHeight)
        if statusBar.SetOrientation then
            statusBar:SetOrientation(isVertical and "VERTICAL" or "HORIZONTAL")
        end
        if isVertical and statusBar.SetReverseFill then
            statusBar:SetReverseFill(fillDirection == "down")
        end
    end

    -- Icon container
    local iconContainer = bar.IconContainer
    if iconContainer then
        if hideIcon then
            iconContainer:Hide()
            iconContainer:SetAlpha(0)
        else
            iconContainer:Show()
            iconContainer:SetAlpha(1)
            local iconSize = isVertical and frameWidth or frameHeight
            iconContainer:SetSize(iconSize, iconSize)

            -- Apply optional desaturation for inactive entries
            if bar.IconTexture and bar.IconTexture.SetDesaturated then
                bar.IconTexture:SetDesaturated((not isActive) and desaturateInactive and inactiveMode ~= "always")
            end
        end
    end

    -- Position statusBar and icon based on orientation
    if statusBar then
        statusBar:ClearAllPoints()
        if isVertical then
            if hideIcon or not iconContainer then
                statusBar:SetAllPoints(bar)
            else
                iconContainer:ClearAllPoints()
                if iconPosition == "bottom" then
                    iconContainer:SetPoint("BOTTOM", bar, "BOTTOM", 0, 0)
                    statusBar:SetPoint("TOP", bar, "TOP", 0, 0)
                    statusBar:SetPoint("LEFT", bar, "LEFT", 0, 0)
                    statusBar:SetPoint("RIGHT", bar, "RIGHT", 0, 0)
                    statusBar:SetPoint("BOTTOM", iconContainer, "TOP", 0, 0)
                else -- "top" (default)
                    iconContainer:SetPoint("TOP", bar, "TOP", 0, 0)
                    statusBar:SetPoint("BOTTOM", bar, "BOTTOM", 0, 0)
                    statusBar:SetPoint("LEFT", bar, "LEFT", 0, 0)
                    statusBar:SetPoint("RIGHT", bar, "RIGHT", 0, 0)
                    statusBar:SetPoint("TOP", iconContainer, "BOTTOM", 0, 0)
                end
            end
        else
            if hideIcon or not iconContainer then
                statusBar:SetPoint("LEFT", bar, "LEFT", 0, 0)
            else
                iconContainer:ClearAllPoints()
                iconContainer:SetPoint("LEFT", bar, "LEFT", 0, 0)
                statusBar:SetPoint("LEFT", iconContainer, "RIGHT", 0, 0)
            end
            statusBar:SetPoint("TOP", bar, "TOP", 0, 0)
            statusBar:SetPoint("BOTTOM", bar, "BOTTOM", 0, 0)
            statusBar:SetPoint("RIGHT", bar, "RIGHT", 0, 0)
        end
    end

    -- Apply StatusBar texture (and mirror onto PermanentFill so the
    -- no-expiration overlay matches the bar's texture/style).
    local resolvedTexturePath
    if statusBar and statusBar.SetStatusBarTexture then
        resolvedTexturePath = LSM:Fetch("statusbar", texture) or LSM:Fetch("statusbar", "Quazii v5")
        if resolvedTexturePath then
            statusBar:SetStatusBarTexture(resolvedTexturePath)
        end
    end
    if bar.PermanentFill and resolvedTexturePath then
        bar.PermanentFill:SetTexture(resolvedTexturePath)
    end

    -- Apply bar color (override > class > custom) with opacity. Mirror the
    -- resolved color onto PermanentFill via SetVertexColor so the overlay
    -- matches the bar's fill color.
    local resolvedR, resolvedG, resolvedB, resolvedA
    if statusBar and statusBar.SetStatusBarColor then
        local c = barColor
        if overrideColor then
            resolvedR, resolvedG, resolvedB, resolvedA =
                overrideColor[1] or 0.2, overrideColor[2] or 0.8, overrideColor[3] or 0.6, barOpacity
        elseif useClassColor then
            local _, class = UnitClass("player")
            local safeClass = tostring(class)
            local color = safeClass and RAID_CLASS_COLORS[safeClass]
            if color then
                resolvedR, resolvedG, resolvedB, resolvedA = color.r, color.g, color.b, barOpacity
            else
                resolvedR, resolvedG, resolvedB, resolvedA =
                    c[1] or 0.2, c[2] or 0.8, c[3] or 0.6, barOpacity
            end
        else
            resolvedR, resolvedG, resolvedB, resolvedA =
                c[1] or 0.2, c[2] or 0.8, c[3] or 0.6, barOpacity
        end
        statusBar:SetStatusBarColor(resolvedR, resolvedG, resolvedB, resolvedA)
    end
    if bar.PermanentFill and resolvedR then
        bar.PermanentFill:SetVertexColor(resolvedR, resolvedG, resolvedB, resolvedA or 1)
    end

    -- Background
    local bg = bar.Background
    if bg then
        local bgR, bgG, bgB = bgColor[1] or 0, bgColor[2] or 0, bgColor[3] or 0
        bg:SetColorTexture(bgR, bgG, bgB, 1)
        if statusBar then
            bg:ClearAllPoints()
            bg:SetAllPoints(statusBar)
        end
        bg:SetAlpha(bgOpacity)
        bg:Show()
    end

    -- Border (4-edge technique)
    local borderFrame = bar.BorderContainer
    if borderFrame then
        if borderSize > 0 then
            borderFrame:ClearAllPoints()
            borderFrame:SetPoint("TOPLEFT", bar, "TOPLEFT", -borderSize, borderSize)
            borderFrame:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", borderSize, -borderSize)

            borderFrame._top:ClearAllPoints()
            borderFrame._top:SetPoint("TOPLEFT", borderFrame, "TOPLEFT", 0, 0)
            borderFrame._top:SetPoint("TOPRIGHT", borderFrame, "TOPRIGHT", 0, 0)
            borderFrame._top:SetHeight(borderSize)

            borderFrame._bottom:ClearAllPoints()
            borderFrame._bottom:SetPoint("BOTTOMLEFT", borderFrame, "BOTTOMLEFT", 0, 0)
            borderFrame._bottom:SetPoint("BOTTOMRIGHT", borderFrame, "BOTTOMRIGHT", 0, 0)
            borderFrame._bottom:SetHeight(borderSize)

            borderFrame._left:ClearAllPoints()
            borderFrame._left:SetPoint("TOPLEFT", borderFrame, "TOPLEFT", 0, 0)
            borderFrame._left:SetPoint("BOTTOMLEFT", borderFrame, "BOTTOMLEFT", 0, 0)
            borderFrame._left:SetWidth(borderSize)

            borderFrame._right:ClearAllPoints()
            borderFrame._right:SetPoint("TOPRIGHT", borderFrame, "TOPRIGHT", 0, 0)
            borderFrame._right:SetPoint("BOTTOMRIGHT", borderFrame, "BOTTOMRIGHT", 0, 0)
            borderFrame._right:SetWidth(borderSize)

            borderFrame:Show()
        else
            borderFrame:Hide()
        end
    end

    -- Text
    local generalFont = GetGeneralFont()
    local generalOutline = GetGeneralFontOutline()
    local showText = not hideText and (not isVertical or showTextOnVertical)

    if bar.NameText then
        bar.NameText:SetFont(generalFont, textSize, generalOutline)
        bar.NameText:SetAlpha(showText and 1 or 0)
    end
    if bar.DurationText then
        bar.DurationText:SetFont(generalFont, textSize, generalOutline)
        local durationBaseAlpha = showText and 1 or 0
        bar.DurationText:SetAlpha(durationBaseAlpha)
        -- Captured so the curve-driven text-hide path (UpdateOwnedBarAura
        -- durObj branch) and the alpha restore sites (inactive branch,
        -- ReleaseBar, _hideDurationText branch) all agree on the
        -- configured visibility — never override a "hide text" setting.
        bar._durationTextBaseAlpha = durationBaseAlpha
    end

    -- Apply frame alpha based on active state
    local targetAlpha = 1
    if not isActive then
        if inactiveMode == "fade" then
            targetAlpha = inactiveAlpha
        elseif inactiveMode == "hide" then
            targetAlpha = 0
        end
    end
    bar:SetAlpha(targetAlpha)
end

---------------------------------------------------------------------------
-- PREVIEW ENTRY POINT
-- Used by modules/cdm/settings/composer_preview_driver.lua to construct
-- a bar frame inside the settings preview pane. CreateBar is pure
-- construction (no runtime hooks at the bar level), so the wrapper is
-- trivial; ConfigureBar(bar, settings, width) is the styling path the
-- driver also uses.
---------------------------------------------------------------------------
function CDMBars.CreateForPreview(parent)
    return CreateBar(parent)
end

---------------------------------------------------------------------------
-- POOL MANAGEMENT
---------------------------------------------------------------------------
local function AcquireBar(parent)
    local bar
    if #recyclePool > 0 then
        bar = table.remove(recyclePool)
        bar:SetParent(parent)
    else
        bar = CreateBar(parent)
    end
    bar:Show()
    barPool[#barPool + 1] = bar
    return bar
end

local function ReleaseBar(bar)
    if ns.CDMRuntimeStore and ns.CDMRuntimeStore.ClearFrame then
        ns.CDMRuntimeStore.ClearFrame(bar)
    end
    bar:Hide()
    bar:ClearAllPoints()
    bar._spellEntry = nil
    bar._spellID = nil
    bar._instanceKey = nil
    bar._active = false
    bar._cSideFill = nil
    bar._preferDurObjFill = nil
    bar._timerShowRearmPending = nil
    bar._lastPosKey = nil
    bar._lastAnchor = nil
    bar._desiredTexture = nil
    bar._isTotemInstance = nil
    bar._totemSlot = nil
    bar._totemIconCache = nil
    bar._totemNameCache = nil
    bar._hideDurationText = nil
    bar._hasAuraExpirationTime = nil
    bar.NameText:SetText("")
    bar.DurationText:SetText("")
    bar.IconTexture:SetTexture(nil)
    ClearStatusBar(bar.StatusBar)
    if bar.PermanentFill then
        bar.PermanentFill:SetAlpha(0)
    end
    -- Restore configured base alpha (or default to 1 for never-configured
    -- bars) so the next ConfigureBar call doesn't have to fight a stale
    -- curve-driven 0 from a previous permanent state.
    bar.DurationText:SetAlpha(bar._durationTextBaseAlpha or 1)

    if #recyclePool < MAX_RECYCLE_POOL_SIZE then
        recyclePool[#recyclePool + 1] = bar
    end
end

function CDMBars:ClearPool()
    for i = #barPool, 1, -1 do
        ReleaseBar(barPool[i])
        barPool[i] = nil
    end
end

function CDMBars:GetActiveBars()
    return barPool
end

-- Aggressive reset: clear per-bar caches stamped during totem/aura
-- mirroring. Repopulated on the next bar update tick.
function CDMBars:ClearPerBarCaches()
    for i = 1, #barPool do
        local bar = barPool[i]
        if bar then
            bar._totemIconCache = nil
            bar._totemNameCache = nil
        end
    end
end

function CDMBars:GetCacheStats()
    return {
        activeBars = #barPool,
    }
end

---------------------------------------------------------------------------
-- BUILD BARS FROM OWNED SPELL LIST: Create bars from owned spell data.
-- All state (StatusBar fill, IconTexture, NameText, DurationText) is driven
-- by UpdateOwnedBarAura -> CDMResolvers.ResolveCooldownState. Composer
-- entries can also provide a mirrored native child identity for exact
-- aura/cooldown state.
---------------------------------------------------------------------------
function CDMBars:BuildBarsFromOwned(container, spellList)
    if not container then return end
    if not spellList or #spellList == 0 then
        -- No owned spells — clear pool and return
        self:ClearPool()
        return
    end

    -- Check if we need to rebuild: compare spell count + IDs with current pool
    local needsRebuild = (#spellList ~= #barPool)
    if not needsRebuild then
        for i, bar in ipairs(barPool) do
            local entry = spellList[i]
            local entrySpellID = entry.overrideSpellID or entry.spellID or entry.id
            if not entry or bar._spellID ~= entrySpellID or bar._instanceKey ~= entry._instanceKey then
                needsRebuild = true
                break
            end
        end
    end

    -- Force rebuild if bars are parented to wrong frame
    if not needsRebuild and #barPool > 0 then
        local firstParent = barPool[1]:GetParent()
        if firstParent ~= container then
            needsRebuild = true
        end
    end

    -- No rebuild needed — refresh active state per bar via the resolver path.
    if not needsRebuild then
        for _, bar in ipairs(barPool) do
            if bar._isOwnedBar and bar._spellID then
                self:UpdateOwnedBarAura(bar)
            end
        end
        return
    end

    -- Clear existing pool
    self:ClearPool()

    -- Create owned bars for each spell entry
    for _, entry in ipairs(spellList) do
        local bar = AcquireBar(container)
        bar._spellEntry = entry
        bar._isOwnedBar = true
        bar._instanceKey = entry._instanceKey
        bar._isTotemInstance = entry._isTotemInstance and true or false
        bar._totemSlot = entry._totemSlot

        local spellID = entry.overrideSpellID or entry.spellID or entry.id
        bar._spellID = spellID

        -- Set initial texture from composer entry / direct C-side APIs.
        -- Totem-instance bars defer to UpdateOwnedBarAura's totemIcon path.
        if bar.IconTexture and spellID and not bar._isTotemInstance then
            local texID
            if entry.type == "item" or entry.type == "slot" then
                if entry.type == "slot" then
                    texID = Sources and Sources.QueryInventoryItemTexture
                        and Sources.QueryInventoryItemTexture("player", entry.id)
                else
                    local _, _, _, _, icon
                    if Sources and Sources.QueryItemInfoInstant then
                        _, _, _, _, icon = Sources.QueryItemInfoInstant(spellID)
                    end
                    texID = icon
                end
            elseif entry.type == "spell" then
                -- Cooldown bars use overrideSpellID for talent replacements.
                -- Aura bars keep their configured entry identity.
                local iconSid
                if entry.isAura then
                    iconSid = entry.overrideSpellID or entry.spellID or entry.id or spellID
                else
                    iconSid = entry.overrideSpellID or entry.id or spellID
                end
                local info
                if Sources and Sources.QuerySpellInfo then
                    info = Sources.QuerySpellInfo(iconSid)
                end
                texID = info and info.iconID
            end
            if texID then
                bar.IconTexture.SetTexture(bar.IconTexture, texID)
                bar._desiredTexture = texID
            end
        end

        -- Set initial name text from the composer entry. Talent rename for
        -- non-aura bars follows via UpdateOwnedBarAura's runtime override
        -- lookup. Totem-instance bars defer to UpdateOwnedBarAura's
        -- totemName path.
        if bar.NameText and not bar._isTotemInstance then
            local displayName = entry and entry.name
                or (ns.CDMSpellData and ns.CDMSpellData:ResolveDisplayName(entry))
            if displayName then
                bar.NameText:SetText(displayName)
            end
        end

        -- Update active state from aura data
        self:UpdateOwnedBarAura(bar)
    end
end

---------------------------------------------------------------------------
-- UPDATE OWNED BAR AURA: Applies mirror payloads directly when present,
-- otherwise delegates to shared resolved cooldown state.
---------------------------------------------------------------------------
-- Phase B.3: drive bar fill from item / trinket-slot cooldowns. Custom
-- auraBar containers accept item entries alongside spells; duration-bar
-- rendering needs its own path since aura resolution is aura-only.
local BuildBarCooldownStateContext

local function StoreBarRuntimeState(bar, mode, active, extra)
    if not (ns.CDMRuntimeStore and ns.CDMRuntimeStore.SetBarState) then return end
    local state = {
        mode = mode,
        active = active and true or false,
        spellID = bar and bar._spellID,
    }
    if type(extra) == "table" then
        for k, v in pairs(extra) do
            state[k] = v
        end
    end
    ns.CDMRuntimeStore.SetBarState(bar, state)
end

local function ApplyResolvedItemBarDurationObject(bar, itemID, r)
    local durObj = r and r.durObj
    if not durObj or type(durObj) == "number" then
        return false
    end
    if not (bar and bar.StatusBar and bar.StatusBar.SetTimerDuration) then
        return false
    end

    local ok = SetStatusBarTimerDuration(bar.StatusBar, durObj)
    if not ok then
        return false
    end

    bar._active = true
    bar._hideDurationText = nil
    bar._hasAuraExpirationTime = r.hasExpirationTime
    bar._durObj = durObj
    bar._cSideFill = true
    bar._preferDurObjFill = true

    local startTime
    local duration
    if r.numericCooldownActive == true
       and type(r.start) == "number"
       and type(r.duration) == "number" then
        startTime = r.start
        duration = r.duration
        bar._totalDuration = duration
        bar._expirationTime = startTime + duration
    else
        bar._totalDuration = nil
        bar._expirationTime = nil
    end

    WriteDurationTextFromDurationObject(bar, durObj)
    EnsureBarTimerRunning()
    StoreBarRuntimeState(bar, r.mode or "item-cooldown", true, {
        itemID = itemID,
        spellID = r.spellID,
        durObj = durObj,
        start = startTime,
        duration = duration,
        isOnCooldown = r.isOnCooldown == true,
        rechargeActive = r.rechargeActive == true,
        hasCharges = r.hasCharges == true,
        hasChargesRemaining = r.hasChargesRemaining == true,
        hasExpirationTime = r.hasExpirationTime,
    })
    return true
end

local function ClearItemBarInactive(bar, itemID)
    bar._active = false
    bar._hideDurationText = nil
    bar._hasAuraExpirationTime = nil
    bar._durObj = nil
    bar._cSideFill = nil
    bar._preferDurObjFill = nil
    bar._totalDuration = nil
    bar._expirationTime = nil
    ClearStatusBar(bar.StatusBar)
    if bar.DurationText then
        bar.DurationText:SetText("")
    end
    StoreBarRuntimeState(bar, "inactive", false, { itemID = itemID })
end

local function UpdateItemBarCooldown(bar, entry)
    local itemID
    if entry.type == "slot" or entry.type == "trinket" then
        itemID = Sources and Sources.QueryInventoryItemID
            and Sources.QueryInventoryItemID("player", entry.id)
    else
        itemID = (Sources and Sources.QueryBestOwnedItemVariant
            and Sources.QueryBestOwnedItemVariant(entry.id)) or entry.id
    end

    -- Texture refresh (trinket swap case)
    if bar.IconTexture and itemID then
        local tex = Sources and Sources.QueryItemIconByID
            and Sources.QueryItemIconByID(itemID)
        if tex then
            bar.IconTexture.SetTexture(bar.IconTexture, tex)
            bar._desiredTexture = tex
        end
    end

    -- Name
    if bar.NameText and itemID then
        local n = Sources and Sources.QueryItemNameByID
            and Sources.QueryItemNameByID(itemID)
        if n then bar.NameText.SetText(bar.NameText, n) end
    end

    -- Active-state detection: scanned item/spell mappings can point from an
    -- item use spell to a different aura spellID. Treat that aura as the
    -- active phase before falling back to cooldown display.
    local scanner = _G.QUI and _G.QUI.SpellScanner
    local isActive, auraDur, auraRemaining
    if Sources and Sources.QueryScannedItemAuraInfo and itemID then
        local scanned = Sources.QueryScannedItemAuraInfo(itemID)
        if scanned and scanned.active == true then
            local readableDuration = ReadNumber(scanned.duration, nil)
            local readableExpiration = ReadNumber(scanned.expiration, nil)
            if readableDuration and readableDuration > 0 then
                isActive = true
                auraDur = readableDuration
                if readableExpiration then
                    auraRemaining = readableExpiration - GetTime()
                end
            end
        end
    end
    if not isActive and scanner and scanner.IsItemActive and itemID then
        local active, expiration, duration = scanner.IsItemActive(itemID)
        local readableDuration = duration
        local readableExpiration = expiration
        if active and readableDuration and readableDuration > 0 then
            isActive = true
            auraDur = readableDuration
            if readableExpiration then
                auraRemaining = readableExpiration - GetTime()
            end
        end
    end

    if isActive and auraRemaining and auraRemaining > 0 then
        bar._active = true
        bar._hideDurationText = GetBarSpellHideDurationOverride(bar)
        bar._hasAuraExpirationTime = nil
        bar._durObj = nil
        bar._cSideFill = nil
        bar._preferDurObjFill = nil
        bar._totalDuration = auraDur
        bar._expirationTime = GetTime() + auraRemaining
        SetStatusBarValue(bar.StatusBar, auraRemaining / auraDur)
        StoreBarRuntimeState(bar, "item-aura", true, {
            itemID = itemID,
            duration = auraDur,
            remaining = auraRemaining,
        })
        return
    end

    -- For aura-kind entries (items in built-in buff/trackedBar containers)
    -- and for entries with displayMode="auraOnly" (custom containers, item
    -- types only), do NOT fall through to cooldown rendering when the aura
    -- is inactive — the bar should go inactive instead.
    local isAuraKind = entry and entry.kind == "aura"
    local containerDB
    if ns.CDMShared and ns.CDMShared.GetContainerDB then
        containerDB = ns.CDMShared.GetContainerDB(entry and entry.viewerType)
    end
    local isCustom = ns.CDMShared and ns.CDMShared.IsCustomBarContainer
        and ns.CDMShared.IsCustomBarContainer(containerDB) or false
    local isAuraOnlyOverride = isCustom
        and entry and entry.displayMode == "auraOnly"
        and (entry.type == "item" or entry.type == "trinket" or entry.type == "slot")

    if isAuraKind or isAuraOnlyOverride then
        ClearItemBarInactive(bar, itemID)
        return
    end

    local resolver = ns.CDMResolvers and ns.CDMResolvers.ResolveCooldownState
    local context = resolver and BuildBarCooldownStateContext(bar, entry, bar._spellID)
    local r = context and resolver(context)
    local startTime = r and r.start
    local duration = r and r.duration

    if r and (r.isActive == true or r.isOnCooldown == true)
       and ApplyResolvedItemBarDurationObject(bar, itemID, r) then
        return
    end

    if r and r.mode == "item-cooldown"
       and r.isOnCooldown == true
       and r.numericCooldownActive == true
       and type(startTime) == "number"
       and type(duration) == "number" then
        local remaining = (startTime + duration) - GetTime()
        if remaining > 0 then
            bar._active = true
            bar._hideDurationText = GetBarSpellHideDurationOverride(bar)
            bar._hasAuraExpirationTime = nil
            bar._durObj = nil
            bar._cSideFill = nil
            bar._preferDurObjFill = nil
            bar._totalDuration = duration
            bar._expirationTime = startTime + duration
            SetStatusBarValue(bar.StatusBar, remaining / duration)
            StoreBarRuntimeState(bar, "item-cooldown", true, {
                itemID = itemID,
                spellID = r.spellID,
                start = startTime,
                duration = duration,
                remaining = remaining,
                isOnCooldown = r.isOnCooldown == true,
                rechargeActive = r.rechargeActive == true,
                hasCharges = r.hasCharges == true,
                hasChargesRemaining = r.hasChargesRemaining == true,
            })
            return
        end
    end

    -- Not active, not on cooldown
    ClearItemBarInactive(bar, itemID)
end

local IsSpellCooldownEntry

local _barCooldownStateContextOptions = {
    mirrorIdentityPolicy = "entry-or-fallback",
    fallbackContainerKey = "trackedBar",
}

local function GetBarFrameState(bar)
    local store = ns.CDMRuntimeStore
    if store and store.GetFrameState then
        return store.GetFrameState(bar)
    end
    return bar and bar._cdmRuntimeState or nil
end

function BuildBarCooldownStateContext(bar, entry, spellID)
    local resolvers = ns.CDMResolvers
    local builder = resolvers and resolvers.BuildCooldownStateContext
    if not builder then return nil end

    local options = _barCooldownStateContextOptions
    local frameState = GetBarFrameState(bar)
    options.containerKey = entry and entry.viewerType
    options.totemSlot = bar and bar._totemSlot
    options.useBuffSwipe = not IsSpellCooldownEntry(entry)
    options.skipAuraPhase = nil
    options.cachedMirrorState = frameState and frameState.mirrorState or nil
    options.cachedMirrorSourceID = frameState and frameState.mirrorSourceID or nil
    return builder(bar, entry, spellID, options)
end

function IsSpellCooldownEntry(entry)
    if not entry then return false end
    local entryType = entry.type
    if entryType
        and entryType ~= "spell"
        and entryType ~= "cooldown" then
        return false
    end
    return entry.kind == "cooldown" or entryType == "cooldown"
end

function CDMBars:UpdateOwnedBarAura(bar)
    if not bar or not bar._spellID then return end
    local spellID = bar._spellID
    local entry = bar._spellEntry
    if not ns.CDMSpellData then return end

    -- Inventory-backed bars retain their adapter path for item names,
    -- trinket-slot texture updates, and SpellScanner item-aura detection.
    if entry and (entry.type == "item" or entry.type == "trinket" or entry.type == "slot") then
        UpdateItemBarCooldown(bar, entry)
        return
    end

    local resolver = ns.CDMResolvers and ns.CDMResolvers.ResolveCooldownState
    if not resolver then return end
    local context = BuildBarCooldownStateContext(bar, entry, spellID)
    if not context then return end
    local r = resolver(context)
    if not r then return end
    local count = r.count
    StoreBarRuntimeState(bar, r.mode or (r.isActive and "aura" or "inactive"), r.isActive, {
        durObj = r.durObj,
        auraUnit = r.auraUnit,
        countShown = count and count.shown == true,
        countValue = count and count.value or nil,
        countSource = count and count.source or nil,
        hasExpirationTime = r.hasExpirationTime,
        mirrorBacked = r.mirrorBacked == true,
        mirrorState = r.mirrorState,
        mirrorSourceID = r.sourceID,
    })

    local _bname = entry and entry.name

    if r.isActive then
        bar._active = true
        bar._auraDataUnit = r.auraUnit
        bar._hasAuraExpirationTime = r.hasExpirationTime
        bar._hideDurationText = ShouldHideAuraDurationText(r)
            or GetBarSpellHideDurationOverride(bar)

        -- Active-aura fallback: when the resolver returns no DurationObject
        -- and an out-of-combat auraData.duration is missing or non-positive,
        -- treat it like permanent.
        if not bar._hideDurationText and not r.durObj and r.auraData
            and not InCombatLockdown() then
            local readableDur = ReadNumber(r.auraData.duration, 0)
            if readableDur <= 0 then
                bar._hideDurationText = true
            end
        end

        if bar._hideDurationText then
            bar._durObj = nil
            bar._cSideFill = nil
            bar._preferDurObjFill = nil
            bar._lastDurationText = nil
            bar._lastDurationBucket = nil
            bar._totalDuration = nil
            bar._expirationTime = nil
            SetStatusBarFull(bar.StatusBar)
            -- Explicit SetValue(1) handles the OOC-resolved permanent
            -- case; the curve-driven PermanentFill overlay is only for
            -- the in-combat case where we can't read the bool. Hide it
            -- here so we don't double-render full.
            if bar.PermanentFill then
                bar.PermanentFill.SetAlpha(bar.PermanentFill, 0)
            end
            if bar.DurationText then
                bar.DurationText.SetText(bar.DurationText, "")
                -- Restore the configured base alpha — never override a
                -- "hide text" setting (vertical bars without text, etc.).
                bar.DurationText.SetAlpha(bar.DurationText, bar._durationTextBaseAlpha or 1)
            end
        end

        -- Cache readable duration/expiration from OOC auraData (for OnUpdate timer text)
        if r.auraData and not bar._hideDurationText
            and not InCombatLockdown() then
            local rawDur = ReadNumber(r.auraData.duration, nil)
            if rawDur and rawDur > 0 then
                bar._totalDuration = rawDur
            end
        end

        -- Bar fill via DurationObject
        local durObj = r.durObj
        if durObj and not bar._hideDurationText then
            local prevDurObj = bar._durObj
            bar._durObj = durObj
            local canUseTimerDuration = bar.StatusBar and bar.StatusBar.SetTimerDuration
            bar._preferDurObjFill = canUseTimerDuration and true or nil
            if bar._cSideFill then
                -- C-side SetTimerDuration is already driving the fill
                -- animation.  Re-calling it would restart the animation
                -- and cause visible flickering.  Detect aura refreshes
                -- by comparing the DurationObject reference (C userdata
                -- identity check — safe in combat, no secret values).
                if durObj ~= prevDurObj then
                    if canUseTimerDuration then
                        local ok = SetStatusBarTimerDuration(bar.StatusBar, durObj)
                        if not ok then
                            bar._preferDurObjFill = nil
                            bar._cSideFill = nil
                        end
                    end
                end
            elseif bar.StatusBar then
                if canUseTimerDuration then
                    local ok = SetStatusBarTimerDuration(bar.StatusBar, durObj)
                    if ok then
                        bar._cSideFill = true
                    else
                        bar._preferDurObjFill = nil
                        bar._cSideFill = nil
                    end
                end
            end

            -- No-expiration overlay + text drive (curve trick via IsZero).
            -- See header doc above the helpers. IsZero is a stable
            -- per-aura property (not derived from elapsed/remaining),
            -- so timed auras like Metamorphosis don't briefly cross a
            -- threshold during animation and produce flicker.
            if durObj.IsZero
               and C_CurveUtil and C_CurveUtil.EvaluateColorValueFromBoolean then
                local isZero = durObj.IsZero(durObj)
                -- Overlay alpha: permanent → 1 (visible), timed → 0.
                if bar.PermanentFill then
                    local alpha = C_CurveUtil.EvaluateColorValueFromBoolean(isZero, 1, 0)
                    bar.PermanentFill.SetAlpha(bar.PermanentFill, alpha)
                end
                -- Duration-text alpha: permanent → 0 (hidden), timed → 1.
                -- Skip when the configured base alpha is 0 (hideText /
                -- vertical-no-text settings) — the timed-aura output is
                -- 1 (visible), which would otherwise override the
                -- user's "hide text" choice.
                if bar.DurationText and (bar._durationTextBaseAlpha or 1) ~= 0 then
                    local textAlpha = C_CurveUtil.EvaluateColorValueFromBoolean(isZero, 0, 1)
                    bar.DurationText.SetAlpha(bar.DurationText, textAlpha)
                end
            end
            WriteDurationTextFromDurationObject(bar, durObj)
            EnsureBarTimerRunning()
        end

        -- Icon: totem instances use slot-bound display from resolved cooldown
        -- state's totemIcon payload. Other bars rely on the desired texture
        -- pinned in BuildBarsFromOwned plus auraData.icon as a runtime override
        -- (talent swaps, debuff overlays). Falls back to the spell texture
        -- source for aura entries whose buff icon differs from the entry's
        -- stored icon.
        if bar.IconTexture then
            if bar._isTotemInstance then
                if r.totemIcon ~= nil then
                    bar._totemIconCache = r.totemIcon
                end
                if bar._totemIconCache ~= nil then
                    bar.IconTexture.SetTexture(bar.IconTexture, bar._totemIconCache)
                end
            else
                local runtimeTex
                if r.auraData then
                    runtimeTex = r.auraData.icon
                end
                if not runtimeTex and entry and entry.isAura then
                    local sid = entry.overrideSpellID or entry.spellID or entry.id
                    if sid then
                        local tex = Sources and Sources.QuerySpellTexture
                            and Sources.QuerySpellTexture(sid)
                        if tex then runtimeTex = tex end
                    end
                end
                if runtimeTex then
                    bar.IconTexture.SetTexture(bar.IconTexture, runtimeTex)
                elseif bar._desiredTexture ~= nil then
                    bar.IconTexture.SetTexture(bar.IconTexture, bar._desiredTexture)
                end
            end
        end

        -- Name + count text.  Display-count payloads are already formatted
        -- by C_UnitAuras, while auraData applications are numeric counts.
        -- Keep both paths in C-side helpers so secret values are forwarded
        -- without Lua concatenation.
        if bar.NameText then
            local name
            if bar._isTotemInstance then
                if r.totemName ~= nil then
                    bar._totemNameCache = r.totemName
                end
                name = bar._totemNameCache
            elseif entry and entry.isAura then
                name = entry.name or ns.CDMSpellData:ResolveDisplayName(entry)
            else
                name = ns.CDMSpellData:ResolveDisplayName(entry)
            end
            if name ~= nil then
                local setOk, countMethod, countText, countSecret =
                    ApplyNameTextWithCount(bar.NameText, name, r.count)
                if _G.QUI_CDM_BAR_DEBUG then
                    local resolvedCount = r.count
                    local countShown = resolvedCount and resolvedCount.shown == true
                    DebugBarLabel(
                        entry, spellID,
                        "label",
                        "name=", tostring(name),
                        "countShown=", tostring(countShown),
                        "countSecret=", tostring(countSecret == true),
                        "countSource=", tostring(resolvedCount and resolvedCount.source or nil),
                        "countMethod=", countMethod,
                        "countOk=", tostring(setOk),
                        "countText=", countSecret and "<secret>" or tostring(countText),
                        "setOk=", tostring(setOk),
                        "setErr=", "nil")
                end
            end
        end
    else
        bar._active = false
        bar._durObj = nil
        bar._cSideFill = nil
        bar._preferDurObjFill = nil
        bar._totalDuration = nil
        bar._expirationTime = nil
        bar._hideDurationText = nil
        bar._hasAuraExpirationTime = nil
        if not InCombatLockdown() then
            bar._resolvedAuraID = nil
        end
        ClearStatusBar(bar.StatusBar)
        if bar.PermanentFill then
            bar.PermanentFill.SetAlpha(bar.PermanentFill, 0)
        end
        if bar.DurationText then
            bar.DurationText:SetText("")
            -- Restore the configured base alpha — never override a
            -- "hide text" setting (vertical bars without text, etc.).
            bar.DurationText.SetAlpha(bar.DurationText, bar._durationTextBaseAlpha or 1)
        end

        -- Always restore name via C-side SetText — no Lua string comparison
        -- (GetText returns a secret value in combat causing taint on ==).
        -- SetText deduplicates on the C side when text is unchanged.
        -- Skip for totem instances: each slot's per-totem name (e.g.
        -- "Dreadstalker" / "Charhound") is owned by the totem-icon path
        -- on the active branch; forcing entry.name ("Call Dreadstalkers")
        -- here would flicker the cached display.
        if bar.NameText and entry and entry.name and entry.name ~= ""
            and not bar._isTotemInstance then
            bar.NameText.SetText(bar.NameText, entry.name)
        end
    end

end

---------------------------------------------------------------------------
-- FORCE ALL ACTIVE: For Edit Mode, force all bars with names visible
-- so the mover overlay shows the full expected area.
---------------------------------------------------------------------------
function CDMBars:ForceAllActive()
    for _, bar in ipairs(barPool) do
        local name = bar.NameText and bar.NameText:GetText()
        if name and name ~= "" then
            bar._active = true
        end
    end
end

---------------------------------------------------------------------------
-- LAYOUT BARS: Pure math positioning, no Blizzard frame interaction.
-- Stacks bars vertically (default) or horizontally (vertical orientation).
---------------------------------------------------------------------------
function CDMBars:LayoutBars(container, settings)
    if not container then return end
    if not settings then return end

    local barHeight = settings.barHeight or 25
    local barWidth = settings.barWidth or 215

    local count = #barPool

    -- Even with 0 bars, set a minimum container size so the Edit Mode
    -- overlay is draggable and visible (not 1x1).
    if count == 0 then
        local orientation = settings.orientation or "horizontal"
        local w, h
        if orientation == "vertical" then
            w, h = barHeight, barWidth
        else
            w, h = barWidth, barHeight
        end
        ResizeContainer(container, w, h)
        return
    end

    local stylingEnabled = settings.enabled
    local spacing = settings.spacing or 2
    local growFromBottom = (settings.growUp ~= false)
    local orientation = settings.orientation or "horizontal"
    local isVertical = (orientation == "vertical")
    local inactiveMode = settings.inactiveMode or "hide"
    local reserveSlotWhenInactive = (settings.reserveSlotWhenInactive == true)

    -- For vertical bars, swap dimensions
    local effectiveBarWidth, effectiveBarHeight
    if isVertical then
        effectiveBarWidth = barHeight
        effectiveBarHeight = barWidth
    else
        effectiveBarWidth = barWidth
        effectiveBarHeight = barHeight
    end

    -- Apply HUD layer priority (skip during layout mode — the handle
    -- system owns strata/level while frames are reparented to movers).
    local layoutActive = Helpers.IsLayoutModeActive()
    local hudLayering = QUICore and QUICore.db and QUICore.db.profile and QUICore.db.profile.hudLayering
    local layerPriority = hudLayering and hudLayering.buffBar or 5
    local frameLevel = 200
    if QUICore and QUICore.GetHUDFrameLevel then
        frameLevel = QUICore:GetHUDFrameLevel(layerPriority)
    end
    if not layoutActive then
        container:SetFrameStrata("MEDIUM")
        container:SetFrameLevel(frameLevel)
    end

    -- Configure and position each bar
    local editModeActive = Helpers.IsEditModeActive()
        or Helpers.IsLayoutModeActive()
        or (_G.QUI_IsCDMEditModeActive and _G.QUI_IsCDMEditModeActive())
    local visibleIndex = 0
    -- Build a lightweight config fingerprint so ConfigureBar is skipped
    -- when settings haven't changed between LayoutBars calls.
    local cfgFingerprint = (settings.barHeight or 0)
        + (barWidth or 0) * 7
        + (settings.borderSize or 0) * 97
        + (settings.textSize or 0) * 1009
        + ((settings.barOpacity or 1) * 10000)
        + ((settings.useClassColor and 1 or 0) * 100003)
    for _, bar in ipairs(barPool) do
        -- In edit/layout mode, force bar active BEFORE ConfigureBar so that
        -- inactive styling (alpha=0 for "hide" mode) doesn't apply.
        if editModeActive then
            bar._active = true
            SetStatusBarValue(bar.StatusBar, 0.65)
            if bar.DurationText then
                bar.DurationText:SetText("0:32")
            end
        end

        -- Apply styling (skip if settings unchanged and bar was already configured)
        if bar._cfgFingerprint ~= cfgFingerprint or bar._cfgActive ~= bar._active then
            bar._cfgFingerprint = cfgFingerprint
            bar._cfgActive = bar._active
            CDMBars.ConfigureBar(bar, settings, barWidth)
        end

        -- Apply strata/level (skip if already correct to avoid layout invalidation)
        if bar._lastFrameLevel ~= frameLevel then
            bar._lastFrameLevel = frameLevel
            bar:SetFrameStrata("MEDIUM")
            bar:SetFrameLevel(frameLevel)
            if bar.StatusBar then
                bar.StatusBar:SetFrameStrata("MEDIUM")
                bar.StatusBar:SetFrameLevel(frameLevel + 1)
            end
            if bar.TextOverlay then
                bar.TextOverlay:SetFrameStrata("MEDIUM")
                bar.TextOverlay:SetFrameLevel(frameLevel + 3)
            end
            if bar.IconContainer then
                bar.IconContainer:SetFrameStrata("MEDIUM")
                bar.IconContainer:SetFrameLevel(frameLevel + 1)
            end
        end

        -- Determine visibility using display mode for owned bars
        local shouldShow = true

        -- In edit/layout mode, force all bars visible (ignore visibility settings)
        if not editModeActive then
            local displayMode = settings.iconDisplayMode or "always"
            local effectiveDisplayMode = displayMode
            if effectiveDisplayMode == "combat" then
                effectiveDisplayMode = InCombatLockdown() and "always" or "active"
            end

            if effectiveDisplayMode == "active" then
                -- Active-only: only show bars with active auras/cooldowns
                if not bar._active then
                    shouldShow = false
                end
            elseif effectiveDisplayMode == "always" then
                -- Always mode: use existing inactiveMode for inactive bars
                if not bar._active then
                    if inactiveMode == "hide" and not reserveSlotWhenInactive then
                        shouldShow = false
                    end
                end
            else
                -- Fallback to existing behavior
                if not bar._active then
                    if inactiveMode == "hide" and not reserveSlotWhenInactive then
                        shouldShow = false
                    end
                end
            end
        end

        if shouldShow then
            local wasShown = bar:IsShown()
            local offsetIndex = visibleIndex

            -- Compute desired anchor point and offset, then skip
            -- ClearAllPoints+SetPoint when the bar is already there.
            -- Redundant point writes cause layout invalidation every tick,
            -- which is the primary visual source of bar flickering.
            local anchor, relAnchor, offsetX, offsetY
            if isVertical then
                if growFromBottom then
                    anchor, relAnchor = "LEFT", "LEFT"
                    offsetX = QUICore:PixelRound(offsetIndex * (effectiveBarWidth + spacing))
                    offsetY = 0
                else
                    anchor, relAnchor = "RIGHT", "RIGHT"
                    offsetX = QUICore:PixelRound(-offsetIndex * (effectiveBarWidth + spacing))
                    offsetY = 0
                end
            else
                if growFromBottom then
                    anchor, relAnchor = "BOTTOM", "BOTTOM"
                    offsetX = 0
                    offsetY = QUICore:PixelRound(offsetIndex * (effectiveBarHeight + spacing))
                else
                    anchor, relAnchor = "TOP", "TOP"
                    offsetX = 0
                    offsetY = QUICore:PixelRound(-offsetIndex * (effectiveBarHeight + spacing))
                end
            end

            local posKey = offsetIndex
            if bar._lastPosKey ~= posKey or bar._lastAnchor ~= anchor
                or not bar:IsShown() then
                bar._lastPosKey = posKey
                bar._lastAnchor = anchor
                bar:ClearAllPoints()
                bar:SetPoint(anchor, container, relAnchor, offsetX, offsetY)
            end

            bar:Show()
            if not wasShown then
                RearmVisibleDurationBarTimer(bar, true)
            end
            visibleIndex = visibleIndex + 1
        else
            if bar:IsShown() then
                bar._lastPosKey = nil
                bar._lastAnchor = nil
                bar:Hide()
            end
        end
    end

    -- Set container size from calculated bounds
    local totalW, totalH
    if visibleIndex == 0 then
        -- All bars hidden by inactiveMode — use settings dimensions so
        -- the container (and Edit Mode overlay) stays a reasonable size.
        totalW = effectiveBarWidth
        totalH = effectiveBarHeight
    elseif isVertical then
        totalW = (visibleIndex * effectiveBarWidth) + ((visibleIndex - 1) * spacing)
        totalH = effectiveBarHeight
    else
        totalW = effectiveBarWidth
        totalH = (visibleIndex * effectiveBarHeight) + ((visibleIndex - 1) * spacing)
    end
    totalW = QUICore:PixelRound(totalW)
    totalH = QUICore:PixelRound(totalH)

    -- Must run in combat too: a bar going active mid-combat would
    -- otherwise leave the container frozen at the previous height,
    -- so frames anchored to its growth edge stop tracking. The combat
    -- branch defers SetSize one tick to escape inherited taint — see
    -- the DEFERRED RESIZE block at the top of the file.
    ResizeContainer(container, totalW, totalH)
end

---------------------------------------------------------------------------
-- REFRESH: Rebuild + re-layout (called from CDMBuffLayout)
---------------------------------------------------------------------------
function CDMBars:Refresh(container, settings, overrideWidth, containerKey)
    if not container then return end
    if not settings then return end

    -- Update barWidth if autoWidth provides an override
    if overrideWidth then
        settings = setmetatable({ barWidth = overrideWidth }, { __index = settings })
    end

    -- Store refs so the periodic ticker can re-layout after _active changes
    _lastContainer = container
    _lastSettings = settings

    -- All bars are sourced from the composer's owned-spells snapshot.
    if ns.CDMSpellData then
        local spellList = ns.CDMSpellData:GetSpellList(containerKey or "trackedBar")
        self:BuildBarsFromOwned(container, spellList)
    else
        self:ClearPool()
    end
    self:LayoutBars(container, settings)
end

---------------------------------------------------------------------------
-- UPDATE ALL OWNED BARS: Periodic aura poll for owned bars.
-- Called from the CDMIcons update ticker (piggybacks on existing 0.5s tick).
---------------------------------------------------------------------------
function CDMBars:UpdateOwnedBars()
    local anyChanged = false
    local anyActive = false
    for _, bar in ipairs(barPool) do
        if bar._isOwnedBar and bar._spellID then
            local wasPreviouslyActive = bar._active
            self:UpdateOwnedBarAura(bar)
            if bar._active ~= wasPreviouslyActive then
                anyChanged = true
            end
            if bar._active then anyActive = true end
        end
    end
    -- Ensure the bar timer is running when any bar is active.
    if anyActive and not barTimerGroup:IsPlaying() then
        barTimerGroup:Play()
    end
    -- Re-layout when any bar's active state changed so Show/Hide updates
    if anyChanged and _lastContainer and _lastSettings then
        self:LayoutBars(_lastContainer, _lastSettings)
    end
end

---------------------------------------------------------------------------
-- OWNED BAR TIMER: 100ms AnimationGroup loop for duration text + bar fill.
-- This loop is ONLY responsible for visual updates (text, fill).
-- Active-state management and layout are owned exclusively by
-- UpdateOwnedBars (called from the 250ms safety ticker + event debounce).
-- Keeping one owner for state+layout prevents the two systems from
-- competing and causing flickering.
---------------------------------------------------------------------------
barTimerGroup:SetScript("OnLoop", function()
    local Helpers = ns.Helpers
    local anyActive = false
    for _, bar in ipairs(barPool) do
        if bar._isOwnedBar and bar._active and bar:IsShown() then
            if bar._hideDurationText then
                anyActive = true
                bar._lastDurationText = nil
                bar._lastDurationBucket = nil
                if bar.DurationText then
                    bar.DurationText.SetText(bar.DurationText, "")
                end
                SetStatusBarFull(bar.StatusBar)
            else
                local durObj = bar._durObj
                -- Guard: GetCooldownDuration can return 0 (a number) when inactive.
                -- Numbers must never be indexed, so only treat userdata/tables as DurationObjects.
                if durObj and type(durObj) == "number" then
                    bar._durObj = nil
                    durObj = nil
                end
                -- Gate on durObj presence (the userdata reference, NOT any
                -- value derived from it). GetRemainingDuration's return is a
                -- secret number in combat — never compare it (`~= nil`,
                -- `> 0`) or do arithmetic on it in Lua. Forward straight to
                -- C-side sinks. SetFormattedText accepts secret numbers and
                -- formats them on the C side. C-side SetTimerDuration drives
                -- the StatusBar fill independently of this loop. Expiration
                -- detection is handled by UpdateOwnedBars (event-driven), not
                -- by Lua-side comparison here.
                if durObj and durObj.GetRemainingDuration then
                    anyActive = true
                    WriteDurationTextFromDurationObject(bar, durObj)
                    -- StatusBar fill: when C-side SetTimerDuration is bound,
                    -- it owns the fill animation entirely. When it isn't,
                    -- pin the bar visibly active without inventing a Lua
                    -- fraction (any division would taint a secret value).
                    if not bar._cSideFill and bar.StatusBar then
                        SetStatusBarFull(bar.StatusBar)
                    end
                end
            end
        end
    end
    -- Stop the animation when no bars need ticking to avoid idle CPU cost.
    if not anyActive then
        barTimerGroup:Stop()
    end
end)

---------------------------------------------------------------------------
-- DEBUG IMPORT BINDING (rebound by cdm_debug.lua's BindAll())
---------------------------------------------------------------------------
ns.CDMBars = ns.CDMBars or CDMBars
function ns.CDMBars._BindDebugImports()
    local d = ns.CDMDebug
    if d then
        DebugBarLabel = d.Bar or DebugBarLabel
    end
end
