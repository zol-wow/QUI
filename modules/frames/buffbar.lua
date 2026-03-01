local ADDON_NAME, ns = ...
local QUICore = ns.Addon
local LSM = LibStub("LibSharedMedia-3.0")

local GetCore = ns.Helpers.GetCore

---------------------------------------------------------------------------
-- QUI Buff Bar Manager
-- Handles dynamic centering of BuffIconCooldownViewer and BuffBarCooldownViewer
-- Uses hash-based polling + sticky center debounce for stable updates
---------------------------------------------------------------------------

local QUI_BuffBar = {}
ns.BuffBar = QUI_BuffBar

---------------------------------------------------------------------------
-- HELPER: Get font from general settings (uses shared helpers)
---------------------------------------------------------------------------
local Helpers = ns.Helpers
local GetGeneralFont = Helpers.GetGeneralFont
local GetGeneralFontOutline = Helpers.GetGeneralFontOutline

---------------------------------------------------------------------------
-- CDM ENGINE DETECTION
---------------------------------------------------------------------------
local function IsOwnedEngine()
    return ns.CDMProvider and ns.CDMProvider:GetActiveEngineName() == "owned"
end

---------------------------------------------------------------------------
-- CDM VIEWER FRAME GETTERS (resolve via QUI-owned frame registry)
---------------------------------------------------------------------------
local function GetBuffIconViewer() return _G.QUI_GetCDMViewerFrame("buffIcon") end
local function GetBuffBarViewer() return _G.QUI_GetCDMViewerFrame("buffBar") end
local function GetEssentialViewer() return _G.QUI_GetCDMViewerFrame("essential") end
local function GetUtilityViewer() return _G.QUI_GetCDMViewerFrame("utility") end

---------------------------------------------------------------------------
-- UTILITY FUNCTIONS
---------------------------------------------------------------------------

local floor = math.floor

-- TAINT SAFETY: Store per-frame state in local weak-keyed tables instead of
-- writing custom properties to Blizzard CDM viewer frames and their children.
local iconBuffState   = Helpers.CreateStateTable()  -- icon → { setup, border, borderSize, aspectRatioCrop, atlasHooked, atlasDisabled }
local barFrameState   = Helpers.CreateStateTable()  -- bar frame → { bg, borderContainer, styled, isActive }
local viewerBuffState = Helpers.CreateStateTable()  -- viewer → { anchorCache, originalPoints, onUpdateHooked, isHorizontal, goingRight, goingUp }
local disabledRegions = Helpers.CreateStateTable()  -- region → true (guard for Show hook)

-- Tolerance-based position check: skip repositioning if within tolerance
-- Prevents jitter from floating-point drift
local abs = math.abs
local function Clamp01(value, fallback)
    if type(value) ~= "number" then return fallback end
    if value < 0 then return 0 end
    if value > 1 then return 1 end
    return value
end

local function PositionMatchesTolerance(icon, expectedX, tolerance)
    if not icon then return false end
    local point, _, _, xOfs = icon:GetPoint(1)
    if not point then return false end
    return abs((xOfs or 0) - expectedX) <= (tolerance or 2)
end

local VALID_ANCHOR_POINTS = {
    TOPLEFT = true, TOP = true, TOPRIGHT = true,
    LEFT = true, CENTER = true, RIGHT = true,
    BOTTOMLEFT = true, BOTTOM = true, BOTTOMRIGHT = true,
}

local function IsFrameVisiblyShown(frame)
    if not frame or not frame.IsShown or not frame:IsShown() then
        return false
    end
    local alpha = Helpers.SafeToNumber((frame.GetAlpha and frame:GetAlpha()) or 1, 1)
    if alpha <= 0.01 then
        return false
    end
    local width = Helpers.SafeToNumber(frame.GetWidth and frame:GetWidth(), 0)
    local height = Helpers.SafeToNumber(frame.GetHeight and frame:GetHeight(), 0)
    if width <= 1 or height <= 1 then
        return false
    end
    return true
end

local function GetFrameTopEdge(frame)
    if not frame then return nil end
    local top = Helpers.SafeToNumber(frame.GetTop and frame:GetTop(), nil)
    if type(top) == "number" then
        return top
    end
    local _, rawCenterY = frame.GetCenter and frame:GetCenter()
    local centerY = Helpers.SafeToNumber(rawCenterY, nil)
    local height = Helpers.SafeToNumber(frame.GetHeight and frame:GetHeight(), nil)
    if type(centerY) == "number" and type(height) == "number" then
        return centerY + (height / 2)
    end
    return nil
end

local function GetTopVisibleResourceBarFrame()
    local candidates = {}
    if QUICore then
        if QUICore.powerBar then
            table.insert(candidates, QUICore.powerBar)
        end
        if QUICore.secondaryPowerBar then
            table.insert(candidates, QUICore.secondaryPowerBar)
        end
    end

    local bestFrame, bestTop
    for _, frame in ipairs(candidates) do
        if IsFrameVisiblyShown(frame) then
            local top = GetFrameTopEdge(frame)
            if type(top) == "number" and (not bestTop or top > bestTop) then
                bestTop = top
                bestFrame = frame
            end
        end
    end

    return bestFrame
end

local function ResolveTrackedBarAnchorFrame(anchorTo)
    if not anchorTo or anchorTo == "disabled" then
        return nil
    end
    if anchorTo == "essential" or anchorTo == "utility" then
        local getProxy = _G.QUI_GetCDMAnchorProxyFrame
        if type(getProxy) == "function" then
            local proxyKey = (anchorTo == "essential") and "cdmEssential" or "cdmUtility"
            local proxy = getProxy(proxyKey)
            if proxy then
                return proxy
            end
        end
    end
    if anchorTo == "screen" then
        return UIParent
    elseif anchorTo == "essential" then
        return GetEssentialViewer()
    elseif anchorTo == "utility" then
        return GetUtilityViewer()
    elseif anchorTo == "primary" then
        return QUICore and QUICore.powerBar
    elseif anchorTo == "secondary" then
        return QUICore and QUICore.secondaryPowerBar
    elseif anchorTo == "playerFrame" then
        return _G.QUI_UnitFrames and _G.QUI_UnitFrames.player
    elseif anchorTo == "targetFrame" then
        return _G.QUI_UnitFrames and _G.QUI_UnitFrames.target
    end
    return nil
end

local function GetTrackedBarAnchorWidth(anchorTo, anchorFrame)
    if not anchorFrame then return nil end

    local width
    if anchorTo == "essential" or anchorTo == "utility" then
        local afvs = _G.QUI_GetCDMViewerState and _G.QUI_GetCDMViewerState(anchorFrame)
        width = (afvs and afvs.iconWidth) or (afvs and afvs.row1Width) or anchorFrame:GetWidth()
    else
        width = anchorFrame:GetWidth()
    end

    if type(width) ~= "number" or width <= 1 then
        return nil
    end
    return width
end

local function ApplyTrackedBarAnchor(settings)
    local viewer = GetBuffBarViewer()
    if not viewer then return end
    -- Avoid ClearAllPoints/SetPoint churn on protected Blizzard viewers during combat.
    if InCombatLockdown() then return end
    -- Don't reposition during Edit Mode — let the user drag/nudge freely.
    -- Blizzard's Edit Mode system handles position save/restore.
    if Helpers.IsEditModeActive() then return end

    local anchorTo = settings.anchorTo or "disabled"
    local sourcePoint = settings.anchorSourcePoint or "CENTER"
    local targetPoint = settings.anchorTargetPoint or sourcePoint
    local placement = settings.anchorPlacement or "center"
    local spacing = settings.anchorSpacing or 0
    local useTopResourceBars = placement == "onTopResourceBars"
    local spacingX, spacingY = 0, 0
    local offsetX = settings.anchorOffsetX or 0
    local offsetY = settings.anchorOffsetY or 0

    if useTopResourceBars or placement == "onTop" then
        sourcePoint = "BOTTOM"
        targetPoint = "TOP"
        spacingY = spacing
    elseif placement == "below" then
        sourcePoint = "TOP"
        targetPoint = "BOTTOM"
        spacingY = -spacing
    elseif placement == "left" then
        sourcePoint = "RIGHT"
        targetPoint = "LEFT"
        spacingX = -spacing
    elseif placement == "right" then
        sourcePoint = "LEFT"
        targetPoint = "RIGHT"
        spacingX = spacing
    else -- center (or advanced manual points)
        -- Keep configured source/target points for backward compatibility.
    end

    offsetX = QUICore:PixelRound(offsetX + spacingX, viewer)
    offsetY = QUICore:PixelRound(offsetY + spacingY, viewer)

    if not VALID_ANCHOR_POINTS[sourcePoint] then sourcePoint = "CENTER" end
    if not VALID_ANCHOR_POINTS[targetPoint] then targetPoint = sourcePoint end

    if anchorTo == "disabled" and not useTopResourceBars then
        local vbs = viewerBuffState[viewer]
        if vbs then vbs.anchorCache = nil end
        return
    end

    local anchorFrame = useTopResourceBars and GetTopVisibleResourceBarFrame() or ResolveTrackedBarAnchorFrame(anchorTo)
    if not anchorFrame and useTopResourceBars then
        -- Fallback to configured target when no visible resource bar is available.
        anchorFrame = ResolveTrackedBarAnchorFrame(anchorTo)
    end
    if not anchorFrame then return end
    if anchorFrame ~= UIParent and not anchorFrame:IsShown() then return end

    local vbs = viewerBuffState[viewer] or {}
    local cache = vbs.anchorCache
    if cache
        and cache.anchorTo == anchorTo
        and cache.placement == placement
        and cache.anchorFrame == anchorFrame
        and cache.sourcePoint == sourcePoint
        and cache.targetPoint == targetPoint
        and cache.offsetX == offsetX
        and cache.offsetY == offsetY
    then
        return
    end

    pcall(function()
        viewer:ClearAllPoints()
        viewer:SetPoint(sourcePoint, anchorFrame, targetPoint, offsetX, offsetY)
    end)

    viewerBuffState[viewer] = viewerBuffState[viewer] or {}
    viewerBuffState[viewer].anchorCache = {
        anchorTo = anchorTo,
        placement = placement,
        anchorFrame = anchorFrame,
        sourcePoint = sourcePoint,
        targetPoint = targetPoint,
        offsetX = offsetX,
        offsetY = offsetY,
    }
end

local function ApplyBuffIconAnchor(settings)
    local viewer = GetBuffIconViewer()
    if not viewer then return end
    if InCombatLockdown() then return end

    local anchorTo = settings.anchorTo or "disabled"
    local sourcePoint = settings.anchorSourcePoint or "CENTER"
    local targetPoint = settings.anchorTargetPoint or sourcePoint
    local placement = settings.anchorPlacement or "center"
    local spacing = settings.anchorSpacing or 0
    local spacingX, spacingY = 0, 0
    local offsetX = settings.anchorOffsetX or 0
    local offsetY = settings.anchorOffsetY or 0

    if placement == "onTop" then
        sourcePoint = "BOTTOM"
        targetPoint = "TOP"
        spacingY = spacing
    elseif placement == "below" then
        sourcePoint = "TOP"
        targetPoint = "BOTTOM"
        spacingY = -spacing
    elseif placement == "left" then
        sourcePoint = "RIGHT"
        targetPoint = "LEFT"
        spacingX = -spacing
    elseif placement == "right" then
        sourcePoint = "LEFT"
        targetPoint = "RIGHT"
        spacingX = spacing
    else
        -- center/manual points
    end

    offsetX = QUICore:PixelRound(offsetX + spacingX, viewer)
    offsetY = QUICore:PixelRound(offsetY + spacingY, viewer)

    if not VALID_ANCHOR_POINTS[sourcePoint] then sourcePoint = "CENTER" end
    if not VALID_ANCHOR_POINTS[targetPoint] then targetPoint = sourcePoint end

    if anchorTo == "disabled" then
        local vbs = viewerBuffState[viewer] or {}
        local hadAnchor = vbs.anchorCache ~= nil
        local originalPoints = vbs.originalPoints
        if hadAnchor and originalPoints and #originalPoints > 0 then
            pcall(function()
                viewer:ClearAllPoints()
                for _, pointData in ipairs(originalPoints) do
                    viewer:SetPoint(
                        pointData.point,
                        pointData.relativeTo,
                        pointData.relativePoint,
                        pointData.xOfs,
                        pointData.yOfs
                    )
                end
            end)
        end
        if viewerBuffState[viewer] then
            viewerBuffState[viewer].anchorCache = nil
        end
        return
    end

    local anchorFrame = ResolveTrackedBarAnchorFrame(anchorTo)
    if not anchorFrame then return end
    if anchorFrame ~= UIParent and not anchorFrame:IsShown() then return end

    local vbs = viewerBuffState[viewer] or {}
    local cache = vbs.anchorCache
    if cache
        and cache.anchorTo == anchorTo
        and cache.placement == placement
        and cache.anchorFrame == anchorFrame
        and cache.sourcePoint == sourcePoint
        and cache.targetPoint == targetPoint
        and cache.offsetX == offsetX
        and cache.offsetY == offsetY
    then
        return
    end

    if not vbs.originalPoints then
        local originalPoints = {}
        local numPoints = viewer:GetNumPoints() or 0
        for i = 1, numPoints do
            local point, relativeTo, relativePoint, xOfs, yOfs = viewer:GetPoint(i)
            if point then
                originalPoints[#originalPoints + 1] = {
                    point = point,
                    relativeTo = relativeTo,
                    relativePoint = relativePoint,
                    xOfs = xOfs or 0,
                    yOfs = yOfs or 0,
                }
            end
        end
        viewerBuffState[viewer] = viewerBuffState[viewer] or {}
        viewerBuffState[viewer].originalPoints = originalPoints
    end

    pcall(function()
        viewer:ClearAllPoints()
        viewer:SetPoint(sourcePoint, anchorFrame, targetPoint, offsetX, offsetY)
    end)

    viewerBuffState[viewer] = viewerBuffState[viewer] or {}
    viewerBuffState[viewer].anchorCache = {
        anchorTo = anchorTo,
        placement = placement,
        anchorFrame = anchorFrame,
        sourcePoint = sourcePoint,
        targetPoint = targetPoint,
        offsetX = offsetX,
        offsetY = offsetY,
    }
end

---------------------------------------------------------------------------
-- DATABASE ACCESS
---------------------------------------------------------------------------

-- DB accessor using shared helpers
local GetDB = Helpers.CreateDBGetter("ncdm")

local function GetBuffSettings()
    local db = GetDB()
    if db and db.buff then
        local buff = db.buff
        -- Migrate old 'shape' setting to new 'aspectRatioCrop'
        if buff.aspectRatioCrop == nil and buff.shape then
            if buff.shape == "rectangle" or buff.shape == "flat" then
                buff.aspectRatioCrop = 1.33  -- 4:3 aspect ratio
            else
                buff.aspectRatioCrop = 1.0  -- square
            end
        end
        return buff
    end
    -- Return defaults if no DB
    return {
        enabled = true,
        iconSize = 42,
        borderSize = 2,
        aspectRatioCrop = 1.0,
        zoom = 0,
        padding = 0,
        opacity = 1.0,
        anchorTo = "disabled",
        anchorPlacement = "center",
        anchorSpacing = 0,
        anchorSourcePoint = "CENTER",
        anchorTargetPoint = "CENTER",
        anchorOffsetX = 0,
        anchorOffsetY = 0,
    }
end

local function GetTrackedBarSettings()
    local db = GetDB()
    if db and db.trackedBar then
        return db.trackedBar
    end
    -- Return defaults if no DB
    return {
        enabled = true,
        barHeight = 25,
        barWidth = 215,
        texture = "Quazii v5",
        useClassColor = true,
        barColor = {0.204, 0.827, 0.6, 1},
        barOpacity = 1.0,
        borderSize = 2,
        bgColor = {0, 0, 0, 1},
        bgOpacity = 0.5,
        textSize = 14,
        spacing = 2,
        growUp = true,
        hideText = false,
        inactiveMode = "hide",
        inactiveAlpha = 0.3,
        desaturateInactive = false,
        reserveSlotWhenInactive = false,
        autoWidth = false,
        autoWidthOffset = 0,
        anchorTo = "disabled",
        anchorPlacement = "center",
        anchorSpacing = 0,
        anchorSourcePoint = "CENTER",
        anchorTargetPoint = "CENTER",
        anchorOffsetX = 0,
        anchorOffsetY = 0,
        -- Vertical bar settings
        orientation = "horizontal",
        fillDirection = "up",
        iconPosition = "top",
        showTextOnVertical = false,
    }
end

---------------------------------------------------------------------------
-- FORWARD DECLARATIONS
---------------------------------------------------------------------------

local LayoutBuffIcons
local LayoutBuffBars

---------------------------------------------------------------------------
-- RE-ENTRY GUARDS: Prevent recursive layout calls
---------------------------------------------------------------------------

local isIconLayoutRunning = false
local isBarLayoutRunning = false

---------------------------------------------------------------------------
-- ARCHITECTURE NOTES:
-- - Hash-based change detection: only layout when count OR settings change
-- - Direct centering: immediate layout on count change (no debounce)
-- - 0.05s polling rate (20 FPS) matches proven stable implementations
-- - Per-icon OnShow hooks REMOVED - they caused cascade during rapid changes
---------------------------------------------------------------------------

---------------------------------------------------------------------------
-- LAYOUT SUPPRESSION: Prevents recursive layout calls from our own SetSize()
---------------------------------------------------------------------------

local layoutSuppressed = 0

local function SuppressLayout()
    layoutSuppressed = layoutSuppressed + 1
end

local function UnsuppressLayout()
    layoutSuppressed = math.max(0, layoutSuppressed - 1)
end

local function IsLayoutSuppressed()
    return layoutSuppressed > 0
end

---------------------------------------------------------------------------
-- ICON FRAME COLLECTION
---------------------------------------------------------------------------

local function GetBuffIconFrames()
    -- Owned engine: read addon-owned icons from the CDM icon pool
    if IsOwnedEngine() then
        local pool = ns.CDMIcons and ns.CDMIcons:GetIconPool("buff")
        if not pool or #pool == 0 then return {} end

        local visible = {}
        for _, icon in ipairs(pool) do
            if icon:IsShown() then
                visible[#visible + 1] = icon
            end
        end

        -- Sort by layoutIndex from spell entry
        table.sort(visible, function(a, b)
            local aIdx = (a._spellEntry and a._spellEntry.layoutIndex) or 0
            local bIdx = (b._spellEntry and b._spellEntry.layoutIndex) or 0
            return aIdx < bIdx
        end)

        return visible
    end

    -- Classic engine: iterate Blizzard viewer children
    local viewer = GetBuffIconViewer()
    if not viewer then
        return {}
    end

    local all = {}

    for _, child in ipairs({ viewer:GetChildren() }) do
        if child then
            -- Skip Selection frame (Edit Mode)
            if child == viewer.Selection then
                -- Skip
            else
                local hasIcon = child.icon or child.Icon
                local hasCooldown = child.cooldown or child.Cooldown

                if hasIcon or hasCooldown then
                    table.insert(all, child)
                end
            end
        end
    end

    table.sort(all, function(a, b)
        return (a.layoutIndex or 0) < (b.layoutIndex or 0)
    end)

    -- Only keep visible icons that have been fully initialized (have cooldownID)
    local visible = {}
    for _, icon in ipairs(all) do
        if icon:IsShown() and icon.cooldownID then
            table.insert(visible, icon)
        end
    end

    return visible
end

---------------------------------------------------------------------------
-- BAR FRAME COLLECTION
---------------------------------------------------------------------------

local function GetBuffBarFrames()
    local viewer = GetBuffBarViewer()
    if not viewer then
        return {}
    end

    local frames = {}

    -- First, try CooldownViewer API if present
    if viewer.GetItemFrames then
        local ok, items = pcall(viewer.GetItemFrames, viewer)
        if ok and items then
            frames = items
        end
    end

    -- Merge raw children scan as well (GetItemFrames may return only active rows).
    local seen = {}
    for _, frame in ipairs(frames) do
        seen[frame] = true
    end
    local okc, children = pcall(function()
        return { viewer:GetChildren() }
    end)
    if okc and children then
        for _, child in ipairs(children) do
            if child and child:IsObjectType("Frame") then
                -- Skip Selection frame
                if child ~= viewer.Selection and not seen[child] then
                    table.insert(frames, child)
                    seen[child] = true
                end
            end
        end
    end

    -- Resolve inactivity behavior once for this pass
    local settings = GetTrackedBarSettings()
    local stylingEnabled = settings.enabled
    local inactiveMode = stylingEnabled and (settings.inactiveMode or "hide") or "always"
    if inactiveMode ~= "always" and inactiveMode ~= "fade" and inactiveMode ~= "hide" then
        inactiveMode = "always"
    end
    local reserveSlotWhenInactive = (settings.reserveSlotWhenInactive == true)

    local function IsTrackedBarActive(frame)
        if not frame then return false end

        local function IsSecret(value)
            if Helpers and Helpers.IsSecretValue then
                local ok, secret = pcall(Helpers.IsSecretValue, value)
                return ok and secret == true
            end
            return false
        end

        local function IsSafeNumber(value)
            return type(value) == "number" and not IsSecret(value)
        end

        local function SafeCompareNumbers(a, b, mode)
            if not IsSafeNumber(a) or not IsSafeNumber(b) then return nil end
            local ok, result = pcall(function()
                if mode == "gt" then return a > b end
                if mode == "lt" then return a < b end
                return nil
            end)
            return ok and result or nil
        end

        local function SafeAddNumber(a, b)
            if not IsSafeNumber(a) or not IsSafeNumber(b) then return nil end
            local ok, result = pcall(function()
                return a + b
            end)
            if ok and IsSafeNumber(result) then
                return result
            end
            return nil
        end

        local hadComparableData = false

        local function LooksLikeDurationText(text)
            if IsSecret(text) then return false end
            if type(text) ~= "string" then return false end
            local compact = text:gsub("%s+", "")
            if compact == "" then return false end
            local lowered = compact:lower()
            if lowered == "0" or lowered == "0.0" or lowered == "0s" or lowered == "00:00" then
                return false
            end
            return lowered:match("^[%d:%.smhd]+$") ~= nil
        end

        local function HasDurationText(owner)
            if not owner or not owner.GetRegions then return false end
            for _, region in ipairs({ owner:GetRegions() }) do
                if region and region.GetObjectType and region:GetObjectType() == "FontString" and region.GetText then
                    local okText, text = pcall(region.GetText, region)
                    if okText and type(text) == "string" and not IsSecret(text) then
                        hadComparableData = true
                    end
                    if okText and LooksLikeDurationText(text) then
                        return true
                    end
                end
            end
            return false
        end

        local hasProgressingValue = false
        local hasRunningCooldown = false
        local hasDuration = false

        local statusBar = frame.Bar
        if statusBar and statusBar.GetValue then
            local okValue, value = pcall(statusBar.GetValue, statusBar)
            if okValue and IsSafeNumber(value) then
                hadComparableData = true
                local okMinMax, minValue, maxValue = pcall(statusBar.GetMinMaxValues, statusBar)
                local maxGreaterMin = okMinMax and SafeCompareNumbers(maxValue, minValue, "gt")
                if maxGreaterMin then
                    hadComparableData = true
                    -- Treat only in-progress bars as active from value alone.
                    local minThreshold = SafeAddNumber(minValue, 0.001)
                    local maxThreshold = SafeAddNumber(maxValue, -0.001)
                    local aboveMin = minThreshold and SafeCompareNumbers(value, minThreshold, "gt")
                    local belowMax = maxThreshold and SafeCompareNumbers(value, maxThreshold, "lt")
                    hasProgressingValue = (aboveMin == true and belowMax == true)
                end
            end
        end

        local iconContainer = frame.Icon
        local cooldown = iconContainer and (iconContainer.Cooldown or iconContainer.cooldown)
        if cooldown and cooldown.GetCooldownTimes then
            local okCD, startTime, duration, isEnabled = pcall(cooldown.GetCooldownTimes, cooldown)
            if okCD and IsSafeNumber(duration) and IsSafeNumber(startTime) then
                hadComparableData = true
                local durationPositive = SafeCompareNumbers(duration, 0, "gt")
                local startPositive = SafeCompareNumbers(startTime, 0, "gt")
                local enabledState = true
                if isEnabled ~= nil and not IsSecret(isEnabled) then
                    hadComparableData = true
                    local okEnabled, enabled = pcall(function()
                        return isEnabled ~= 0
                    end)
                    enabledState = okEnabled and enabled or false
                end
                if durationPositive and startPositive and enabledState then
                    hasRunningCooldown = true
                end
            end
        end

        hasDuration = HasDurationText(frame) or HasDurationText(statusBar)

        if hasRunningCooldown or hasDuration or hasProgressingValue then
            return true
        end
        if hadComparableData then
            return false
        end
        return nil -- Unknown due secret/combat restrictions.
    end

    -- Filter frames, allowing inactive entries to be shown for always/fade modes.
    local active = {}
    local inCombat = InCombatLockdown()
    for _, frame in ipairs(frames) do
        if frame then
            local iconContainer = frame.Icon
            local iconTexture = iconContainer and (iconContainer.Icon or iconContainer.icon or iconContainer.texture)
            local hasTexture = iconTexture and iconTexture.GetTexture and iconTexture:GetTexture() ~= nil
            -- Hidden frames without identifiers or texture are usually unused pool entries.
            local looksInitialized = (frame.cooldownID ~= nil) or (frame.layoutIndex ~= nil) or hasTexture

            if not frame:IsShown() and not looksInitialized then
                -- Skip uninitialized pooled frames.
            else
                -- In combat, bars can be intentionally alpha-hidden by QUI while still
                -- logically shown by Blizzard. Using IsVisible() here would treat
                -- alpha=0 bars as absent, preventing them from coming back when the
                -- aura becomes active mid-combat.
                local blizzShown = frame:IsShown()

                if inCombat then
                    -- In combat, trust Blizzard visibility state and avoid forcing Show/Hide.
                    barFrameState[frame] = barFrameState[frame] or {}
                    barFrameState[frame].isActive = blizzShown
                    if blizzShown then
                        table.insert(active, frame)
                    end
                else
                    local isActive = IsTrackedBarActive(frame)
                    if isActive == nil then
                        isActive = blizzShown
                    end
                    barFrameState[frame] = barFrameState[frame] or {}
                    barFrameState[frame].isActive = isActive

                    if inactiveMode == "hide" and not reserveSlotWhenInactive and not isActive then
                        pcall(function()
                            frame:SetAlpha(0)
                            frame:Hide()
                        end)
                    else
                        if not frame:IsShown() then
                            pcall(function()
                                frame:Show()
                            end)
                        end
                        table.insert(active, frame)
                    end
                end
            end
        end
    end

    table.sort(active, function(a, b)
        return (a.layoutIndex or 0) < (b.layoutIndex or 0)
    end)

    return active
end

---------------------------------------------------------------------------
-- HELPER: Strip Blizzard's overlay texture (the square artifact)
---------------------------------------------------------------------------

local function StripBlizzardOverlay(icon)
    if not icon or not icon.GetRegions then return end

    for _, region in ipairs({ icon:GetRegions() }) do
        if region:IsObjectType("Texture") then
            -- Check for the specific overlay atlas
            if region.GetAtlas then
                local ok, atlas = pcall(region.GetAtlas, region)
                if ok and atlas == "UI-HUD-CoolDownManager-IconOverlay" then
                    region:SetTexture("")
                    region:Hide()
                    if not disabledRegions[region] then
                        disabledRegions[region] = true
                        hooksecurefunc(region, "Show", function(self)
                            if self and not (self.IsForbidden and self:IsForbidden()) then
                                pcall(self.Hide, self)
                            end
                        end)
                    end
                end
            end
        end
    end
end

---------------------------------------------------------------------------
-- HELPER: Disable atlas-based border textures (debuff type colors, etc.)
-- Hooks SetAtlas to prevent Blizzard from re-applying borders on updates
---------------------------------------------------------------------------

local function DisableAtlasBorder(tex)
    if not tex then return end

    -- Immediately clear everything
    if tex.SetAtlas then tex:SetAtlas(nil) end
    if tex.SetTexture then tex:SetTexture(nil) end
    if tex.SetAlpha then tex:SetAlpha(0) end
    if tex.Hide then tex:Hide() end

    -- Hook to re-clear on future SetAtlas calls (Blizzard re-applies on buff updates)
    local ibs = iconBuffState[tex]
    if tex.SetAtlas and not (ibs and ibs.atlasDisabled) then
        iconBuffState[tex] = ibs or {}
        iconBuffState[tex].atlasDisabled = true
        local _atlasGuard = false
        hooksecurefunc(tex, "SetAtlas", function(self)
            if _atlasGuard then return end  -- prevent recursion from our own SetAtlas(nil)
            if not self or (self.IsForbidden and self:IsForbidden()) then return end
            _atlasGuard = true
            pcall(function()
                self:SetAtlas(nil)
                self:SetTexture(nil)
                self:SetAlpha(0)
                self:Hide()
            end)
            _atlasGuard = false
        end)
    end
end

---------------------------------------------------------------------------
-- HELPER: One-time icon setup (mask removal, overlay strip)
-- NOTE: Per-icon OnShow hooks removed - they caused cascade during rapid buff changes
-- Polling at 0.05s + viewer hooks handle detection efficiently
---------------------------------------------------------------------------

local function SetupIconOnce(icon)
    local ibs = iconBuffState[icon]
    if ibs and ibs.setup then return end

    -- Remove ALL of Blizzard's masks (they may have multiple)
    local textures = { icon.Icon, icon.icon, icon.texture, icon.Texture }
    for _, tex in ipairs(textures) do
        if tex and tex.GetMaskTexture then
            for i = 1, 10 do
                local mask = tex:GetMaskTexture(i)
                if mask then
                    tex:RemoveMaskTexture(mask)
                end
            end
        end
    end

    -- Hide any NormalTexture border that Blizzard adds
    if icon.NormalTexture then icon.NormalTexture:SetAlpha(0) end
    if icon.GetNormalTexture then
        local normalTex = icon:GetNormalTexture()
        if normalTex then normalTex:SetAlpha(0) end
    end

    -- Strip Blizzard's overlay texture
    StripBlizzardOverlay(icon)

    -- Disable aura type border textures (debuff colors, buff borders, enchant borders)
    DisableAtlasBorder(icon.DebuffBorder)
    DisableAtlasBorder(icon.BuffBorder)
    DisableAtlasBorder(icon.TempEnchantBorder)

    iconBuffState[icon] = ibs or {}
    iconBuffState[icon].setup = true
end

---------------------------------------------------------------------------
-- HELPER: Apply icon size, aspect ratio, border, and perfect square fix
---------------------------------------------------------------------------

local function ApplyIconStyle(icon, settings)
    if not icon then return end

    -- Owned engine: delegate to icon factory + swipe module
    if IsOwnedEngine() then
        local rowConfig = {
            size = settings.iconSize or 42,
            borderSize = settings.borderSize or 2,
            borderColorTable = settings.borderColorTable or {0, 0, 0, 1},
            aspectRatioCrop = settings.aspectRatioCrop or 1.0,
            zoom = settings.zoom or 0,
            durationSize = settings.durationSize or 14,
            durationOffsetX = settings.durationOffsetX or 0,
            durationOffsetY = settings.durationOffsetY or 8,
            durationTextColor = settings.durationTextColor or {1, 1, 1, 1},
            durationAnchor = settings.durationAnchor or "TOP",
            stackSize = settings.stackSize or 14,
            stackOffsetX = settings.stackOffsetX or 0,
            stackOffsetY = settings.stackOffsetY or -8,
            stackTextColor = settings.stackTextColor or {1, 1, 1, 1},
            stackAnchor = settings.stackAnchor or "BOTTOM",
            opacity = settings.opacity or 1.0,
        }
        if ns.CDMIcons and ns.CDMIcons.ConfigureIcon then
            ns.CDMIcons.ConfigureIcon(icon, rowConfig)
        end
        local swipeMod = QUI and QUI.CooldownSwipe
        if swipeMod and swipeMod.ApplyToIcon then
            swipeMod.ApplyToIcon(icon)
        end
        if icon.GetScale and icon:GetScale() ~= 1 then
            icon:SetScale(1)
        end
        return
    end

    -- Classic engine: manual styling
    SetupIconOnce(icon)

    local size = settings.iconSize or 42
    local aspectRatio = settings.aspectRatioCrop or 1.0
    local zoom = settings.zoom or 0
    local borderSize = settings.borderSize or 2

    -- Calculate dimensions using crop-based aspect ratio
    local width, height = size, size
    if aspectRatio > 1.0 then
        -- Wider: height shrinks
        height = size / aspectRatio
    elseif aspectRatio < 1.0 then
        -- Taller: width shrinks
        width = size * aspectRatio
    end

    -- Reset any scale Blizzard may have applied (Edit Mode slider can set
    -- per-icon scale, which persists after exit and makes icons visually
    -- larger even though GetWidth/GetHeight returns QUI's configured size).
    if icon.GetScale and icon:GetScale() ~= 1 then
        icon:SetScale(1)
    end

    icon:SetSize(width, height)

    -- Create or update border (using BACKGROUND texture to avoid secret value errors during combat)
    -- BackdropTemplate causes "arithmetic on secret value" crashes when frame is resized during combat
    local ibs = iconBuffState[icon] or {}
    iconBuffState[icon] = ibs
    if borderSize > 0 then
        if not ibs.border then
            ibs.border = icon:CreateTexture(nil, "BACKGROUND", nil, -8)
            ibs.border:SetColorTexture(0, 0, 0, 1)
        end

        ibs.border:ClearAllPoints()
        ibs.border:SetPoint("TOPLEFT", icon, "TOPLEFT", -borderSize, borderSize)
        ibs.border:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", borderSize, -borderSize)
        ibs.border:Show()
        ibs.borderSize = borderSize
    else
        if ibs.border then
            ibs.border:Hide()
        end
        ibs.borderSize = 0
    end

    -- Calculate texture coordinates (crop-based, no stretching)
    -- BASE_CROP always applied first to hide Blizzard's grey icon edges
    local BASE_CROP = 0.08
    local left, right, top, bottom = BASE_CROP, 1 - BASE_CROP, BASE_CROP, 1 - BASE_CROP

    -- Apply aspect ratio crop ON TOP of base crop (within the already-cropped area)
    if aspectRatio > 1.0 then
        -- Wider: crop MORE from top/bottom
        local cropAmount = 1.0 - (1.0 / aspectRatio)
        local availableHeight = bottom - top
        local offset = (cropAmount * availableHeight) / 2.0
        top = top + offset
        bottom = bottom - offset
    elseif aspectRatio < 1.0 then
        -- Taller: crop MORE from left/right
        local cropAmount = 1.0 - aspectRatio
        local availableWidth = right - left
        local offset = (cropAmount * availableWidth) / 2.0
        left = left + offset
        right = right - offset
    end

    -- Apply zoom on top of everything (zooms into center)
    if zoom > 0 then
        local centerX = (left + right) / 2.0
        local centerY = (top + bottom) / 2.0
        local currentWidth = right - left
        local currentHeight = bottom - top
        local visibleSize = 1.0 - (zoom * 2)
        left = centerX - (currentWidth * visibleSize / 2.0)
        right = centerX + (currentWidth * visibleSize / 2.0)
        top = centerY - (currentHeight * visibleSize / 2.0)
        bottom = centerY + (currentHeight * visibleSize / 2.0)
    end

    local function ProcessTexture(tex)
        if not tex then return end
        tex:ClearAllPoints()
        tex:SetAllPoints(icon)
        if tex.SetTexCoord then
            tex:SetTexCoord(left, right, top, bottom)
        end
    end

    -- Try common texture property names
    ProcessTexture(icon.Icon)
    ProcessTexture(icon.icon)
    ProcessTexture(icon.texture)
    ProcessTexture(icon.Texture)

    -- Fix the Cooldown frame
    local cooldown = icon.Cooldown or icon.cooldown
    if cooldown then
        cooldown:ClearAllPoints()
        cooldown:SetAllPoints(icon)
        -- Use simple stretchable texture so swipe fills entire frame
        cooldown:SetSwipeTexture("Interface\\Buttons\\WHITE8X8")
        cooldown:SetSwipeColor(0, 0, 0, 0.8)

        -- Show cooldown swipe based on showBuffIconSwipe setting (opt-in, default OFF)
        local core = GetCore()
        local showBuffIconSwipe = core and core.db and core.db.profile.cooldownSwipe
            and core.db.profile.cooldownSwipe.showBuffIconSwipe or false
        if cooldown.SetDrawSwipe then
            cooldown:SetDrawSwipe(showBuffIconSwipe)
        end
        if cooldown.SetDrawEdge then
            cooldown:SetDrawEdge(showBuffIconSwipe)
        end
    end

    -- Fix CooldownFlash if it exists
    if icon.CooldownFlash then
        icon.CooldownFlash:ClearAllPoints()
        icon.CooldownFlash:SetAllPoints(icon)
    end

    -- Apply text sizes and offsets
    local durationSize = settings.durationSize or 12
    local stackSize = settings.stackSize or 12
    local durationOffsetX = settings.durationOffsetX or 0
    local durationOffsetY = settings.durationOffsetY or 0
    local durationAnchor = settings.durationAnchor or "CENTER"
    local stackOffsetX = settings.stackOffsetX or 0
    local stackOffsetY = settings.stackOffsetY or 0
    local stackAnchor = settings.stackAnchor or "BOTTOMRIGHT"

    -- Get font from general settings
    local generalFont = GetGeneralFont()
    local generalOutline = GetGeneralFontOutline()

    -- Apply duration text size and offset (cooldown text)
    if cooldown and durationSize then
        -- Method 1: Check for OmniCC text
        if cooldown.text then
            cooldown.text:SetFont(generalFont, durationSize, generalOutline)
            pcall(function()
                cooldown.text:ClearAllPoints()
                cooldown.text:SetPoint(durationAnchor, icon, durationAnchor, durationOffsetX, durationOffsetY)
            end)
        end

        -- Method 2: Check for Blizzard's built-in cooldown text (GetRegions)
        for _, region in ipairs({ cooldown:GetRegions() }) do
            if region:GetObjectType() == "FontString" then
                region:SetFont(generalFont, durationSize, generalOutline)
                pcall(function()
                    region:ClearAllPoints()
                    region:SetPoint(durationAnchor, icon, durationAnchor, durationOffsetX, durationOffsetY)
                end)
            end
        end
    end

    -- Apply stack text size using same approach as core/main.lua
    local fs = nil

    -- 1. ChargeCount (ability charges)
    local charge = icon.ChargeCount
    if charge then
        fs = charge.Current or charge.Text or charge.Count or nil
        if not fs and charge.GetRegions then
            for _, region in ipairs({ charge:GetRegions() }) do
                if region:GetObjectType() == "FontString" then
                    fs = region
                    break
                end
            end
        end
    end

    -- 2. Applications (Buff stacks)
    if not fs then
        local apps = icon.Applications
        if apps and apps.GetRegions then
            for _, region in ipairs({ apps:GetRegions() }) do
                if region:GetObjectType() == "FontString" then
                    fs = region
                    break
                end
            end
        end
    end

    -- 3. Fallback: look for named stack text
    if not fs and icon.GetRegions then
        for _, region in ipairs({ icon:GetRegions() }) do
            if region:GetObjectType() == "FontString" then
                local name = region:GetName()
                if name and (name:find("Stack") or name:find("Applications") or name:find("Count")) then
                    fs = region
                    break
                end
            end
        end
    end

    -- Apply the stack size and offset
    if fs and stackSize then
        fs:SetFont(generalFont, stackSize, generalOutline)
        pcall(function()
            fs:ClearAllPoints()
            fs:SetPoint(stackAnchor, icon, stackAnchor, stackOffsetX, stackOffsetY)
        end)
    end

    -- Apply opacity
    local opacity = settings.opacity or 1.0
    icon:SetAlpha(opacity)
end

---------------------------------------------------------------------------
-- BAR STYLING (for BuffBarCooldownViewer item cooldowns)
---------------------------------------------------------------------------

local function ApplyBarStyle(frame, settings, overrideBarWidth)
    if not frame then return end
    if frame.IsForbidden and frame:IsForbidden() then return end

    local barHeight = settings.barHeight or 24
    local barWidth = overrideBarWidth or settings.barWidth or 200
    local texture = settings.texture or "Quazii v5"
    local useClassColor = settings.useClassColor
    local barColor = settings.barColor or {0.204, 0.827, 0.6, 1}
    local barOpacity = settings.barOpacity or 1.0
    local borderSize = settings.borderSize or 1
    local bgColor = settings.bgColor or {0, 0, 0, 1}
    local bgOpacity = settings.bgOpacity or 0.7
    local textSize = settings.textSize or 12
    local hideIcon = settings.hideIcon
    local hideText = settings.hideText

    -- Inactive visual settings
    local inactiveMode = settings.inactiveMode or "hide"
    if inactiveMode ~= "always" and inactiveMode ~= "fade" and inactiveMode ~= "hide" then
        inactiveMode = "always"
    end
    local inactiveAlpha = Clamp01(settings.inactiveAlpha, 0.3)
    local desaturateInactive = (settings.desaturateInactive == true)

    -- Vertical bar settings
    local orientation = settings.orientation or "horizontal"
    local isVertical = (orientation == "vertical")
    local fillDirection = settings.fillDirection or "up"
    local iconPosition = settings.iconPosition or "top"
    local showTextOnVertical = settings.showTextOnVertical or false
    local bfs = barFrameState[frame]
    local isActive = not (bfs and bfs.isActive == false)

    -- For vertical bars: swap width/height conceptually
    -- "Bar Height" setting becomes bar width, "Bar Width" becomes bar height
    local frameWidth, frameHeight
    if isVertical then
        frameWidth = barHeight   -- Height setting becomes width
        frameHeight = barWidth   -- Width setting becomes height
    else
        frameWidth = barWidth
        frameHeight = barHeight
    end

    -- Get the StatusBar child (usually frame.Bar)
    local statusBar = frame.Bar
    if not statusBar and frame.GetChildren then
        local okC, children = pcall(function()
            return { frame:GetChildren() }
        end)
        if okC and children then
            for _, child in ipairs(children) do
                if child and child.IsObjectType and child:IsObjectType("StatusBar") then
                    statusBar = child
                    break
                end
            end
        end
    end

    -- 1. STRIP Blizzard's decorative textures from the statusBar (keep only the fill texture)
    if statusBar and statusBar.GetRegions then
        pcall(function()
            local mainTex = statusBar:GetStatusBarTexture()
            for _, region in ipairs({statusBar:GetRegions()}) do
                if region and region:IsObjectType("Texture") and region ~= mainTex then
                    region:SetTexture(nil)
                    region:Hide()
                end
            end
        end)
    end

    -- 1b. Disable atlas borders on the bar FRAME itself (debuff type colors like red/purple/green)
    DisableAtlasBorder(frame.DebuffBorder)
    DisableAtlasBorder(frame.BuffBorder)
    DisableAtlasBorder(frame.TempEnchantBorder)

    -- 2. Set bar dimensions (swapped for vertical orientation)
    pcall(function()
        frame:SetHeight(frameHeight)
        frame:SetWidth(frameWidth)
        if statusBar then
            statusBar:SetHeight(frameHeight)
            statusBar:SetWidth(frameWidth)
            -- Set StatusBar orientation
            if statusBar.SetOrientation then
                statusBar:SetOrientation(isVertical and "VERTICAL" or "HORIZONTAL")
            end
            -- Set fill direction for vertical bars
            if isVertical and statusBar.SetReverseFill then
                statusBar:SetReverseFill(fillDirection == "down")
            end
        end
    end)

    -- 3. Handle icon visibility and styling
    local iconContainer = frame.Icon
    local iconTexture = iconContainer and (iconContainer.Icon or iconContainer.icon or iconContainer.texture)
    if iconContainer then
        if hideIcon then
            -- Hide icon completely when user wants no icon
            pcall(function()
                iconContainer:Hide()
                iconContainer:SetAlpha(0)
            end)
        else
            -- Show and style icon with full texture stripping for clean rendering
            pcall(function()
                iconContainer:Show()
                iconContainer:SetAlpha(1)

                -- Disable atlas borders on iconContainer (prevents thick border reappearance)
                DisableAtlasBorder(iconContainer.DebuffBorder)
                DisableAtlasBorder(iconContainer.BuffBorder)
                DisableAtlasBorder(iconContainer.TempEnchantBorder)

                -- Icon size: use the smaller dimension for vertical bars
                local iconSize = isVertical and frameWidth or frameHeight
                iconContainer:SetSize(iconSize, iconSize)

            -- Get the actual icon texture inside the container
            if iconTexture and iconTexture.IsObjectType and iconTexture:IsObjectType("Texture") then
                -- Step A: Remove ALL mask textures FIRST (iterate through all of them)
                if iconTexture.GetMaskTexture then
                    local i = 1
                    local mask = iconTexture:GetMaskTexture(i)
                    while mask do
                        iconTexture:RemoveMaskTexture(mask)
                        i = i + 1
                        mask = iconTexture:GetMaskTexture(i)
                    end
                end

                -- Disable cooldown swipe on buff bar icons (bar shows duration, swipe is redundant)
                local cooldown = iconContainer.Cooldown or iconContainer.cooldown
                if cooldown then
                    if cooldown.SetDrawSwipe then cooldown:SetDrawSwipe(false) end
                    if cooldown.SetDrawEdge then cooldown:SetDrawEdge(false) end
                end

                -- Step B: Clear anchor points and fill container completely
                iconTexture:ClearAllPoints()
                iconTexture:SetPoint("TOPLEFT", iconContainer, "TOPLEFT", 0, 0)
                iconTexture:SetPoint("BOTTOMRIGHT", iconContainer, "BOTTOMRIGHT", 0, 0)

                -- Step C: Apply TexCoord cropping (removes transparent icon border)
                iconTexture:SetTexCoord(0.07, 0.93, 0.07, 0.93)

                -- Step D: Strip ALL sibling textures from iconContainer (removes debuff rings, borders)
                for _, region in ipairs({iconContainer:GetRegions()}) do
                    if region:IsObjectType("Texture") and region ~= iconTexture then
                        region:SetTexture(nil)
                        region:Hide()
                    end
                end

                -- Step E: Also strip any child frames that might contain borders
                if iconContainer.GetChildren then
                    for _, child in ipairs({iconContainer:GetChildren()}) do
                        if child and child ~= iconTexture then
                            -- Hide border frames but not the cooldown
                            local childName = child.GetName and child:GetName() or ""
                            if not childName:find("Cooldown") then
                                for _, reg in ipairs({child:GetRegions()}) do
                                    if reg:IsObjectType("Texture") then
                                        reg:SetTexture(nil)
                                        reg:Hide()
                                    end
                                end
                            end
                        end
                    end
                end
            end

            -- Step E2: Hide all text on icon (duration shown by bar, text is redundant)
            for _, region in ipairs({iconContainer:GetRegions()}) do
                if region:IsObjectType("FontString") then
                    region:SetAlpha(0)
                end
            end
            -- Also check icon children for text (cooldown timers, count text)
            if iconContainer.GetChildren then
                for _, child in ipairs({iconContainer:GetChildren()}) do
                    if child.GetRegions then
                        for _, region in ipairs({child:GetRegions()}) do
                            if region:IsObjectType("FontString") then
                                region:SetAlpha(0)
                            end
                        end
                    end
                end
            end

            -- Step F: Hook SetAtlas on icon texture to prevent Blizzard re-applying borders (one-time hook)
            -- TAINT SAFETY: Defer to break taint chain from secure CDM context.
            local itbs = iconBuffState[iconTexture]
            if iconTexture and iconTexture.SetAtlas and not (itbs and itbs.atlasHooked) then
                iconBuffState[iconTexture] = itbs or {}
                iconBuffState[iconTexture].atlasHooked = true
                hooksecurefunc(iconTexture, "SetAtlas", function(self)
                    if self and self.SetTexCoord then
                        self:SetTexCoord(0.07, 0.93, 0.07, 0.93)
                    end
                end)
            end
        end)
        end  -- end else (not hideIcon)
    end

    -- Apply optional icon desaturation for inactive entries.
    if iconTexture and iconTexture.SetDesaturated then
        pcall(function()
            iconTexture:SetDesaturated((not isActive) and desaturateInactive and inactiveMode ~= "always")
        end)
    end

    -- 3b. Reposition statusBar and icon based on orientation and visibility
    if statusBar then
        pcall(function()
            statusBar:ClearAllPoints()

            if isVertical then
                -- VERTICAL: Icon at top or bottom, bar fills remaining space
                if hideIcon or not iconContainer then
                    -- No icon: bar fills entire frame
                    statusBar:SetAllPoints(frame)
                else
                    -- Position icon based on iconPosition setting
                    iconContainer:ClearAllPoints()
                    if iconPosition == "bottom" then
                        iconContainer:SetPoint("BOTTOM", frame, "BOTTOM", 0, 0)
                        statusBar:SetPoint("TOP", frame, "TOP", 0, 0)
                        statusBar:SetPoint("LEFT", frame, "LEFT", 0, 0)
                        statusBar:SetPoint("RIGHT", frame, "RIGHT", 0, 0)
                        statusBar:SetPoint("BOTTOM", iconContainer, "TOP", 0, 0)
                    else -- "top" (default)
                        iconContainer:SetPoint("TOP", frame, "TOP", 0, 0)
                        statusBar:SetPoint("BOTTOM", frame, "BOTTOM", 0, 0)
                        statusBar:SetPoint("LEFT", frame, "LEFT", 0, 0)
                        statusBar:SetPoint("RIGHT", frame, "RIGHT", 0, 0)
                        statusBar:SetPoint("TOP", iconContainer, "BOTTOM", 0, 0)
                    end
                end
            else
                -- HORIZONTAL: Original behavior
                if hideIcon or not iconContainer then
                    statusBar:SetPoint("LEFT", frame, "LEFT", 0, 0)
                else
                    statusBar:SetPoint("LEFT", iconContainer, "RIGHT", 0, 0)
                end
                statusBar:SetPoint("TOP", frame, "TOP", 0, 0)
                statusBar:SetPoint("BOTTOM", frame, "BOTTOM", 0, 0)
                statusBar:SetPoint("RIGHT", frame, "RIGHT", 0, 0)
            end
        end)
    end

    -- 4. Apply StatusBar texture
    if statusBar and statusBar.SetStatusBarTexture then
        local texturePath = LSM:Fetch("statusbar", texture) or LSM:Fetch("statusbar", "Quazii v5")
        if texturePath then
            pcall(statusBar.SetStatusBarTexture, statusBar, texturePath)
        end
    end

    -- 5. Apply bar color (class or custom) with opacity
    if statusBar and statusBar.SetStatusBarColor then
        pcall(function()
            local c = barColor
            if useClassColor then
                local _, class = UnitClass("player")
                local safeClass = Helpers.SafeToString(class, nil)
                local color = safeClass and RAID_CLASS_COLORS[safeClass]
                if color then
                    statusBar:SetStatusBarColor(color.r, color.g, color.b, barOpacity)
                else
                    statusBar:SetStatusBarColor(c[1] or 0.2, c[2] or 0.8, c[3] or 0.6, barOpacity)
                end
            else
                statusBar:SetStatusBarColor(c[1] or 0.2, c[2] or 0.8, c[3] or 0.6, barOpacity)
            end
        end)
    end

    -- 6. Apply clean backdrop (solid background BEHIND the statusBar fill)
    -- Create on the frame itself, positioned behind statusBar
    local bfsBar = barFrameState[frame] or {}
    barFrameState[frame] = bfsBar
    if not bfsBar.bg then
        bfsBar.bg = frame:CreateTexture(nil, "BACKGROUND", nil, -8)
    end
    -- Apply background color from settings
    local bgR, bgG, bgB = bgColor[1] or 0, bgColor[2] or 0, bgColor[3] or 0
    bfsBar.bg:SetColorTexture(bgR, bgG, bgB, 1)
    if statusBar then
        bfsBar.bg:ClearAllPoints()
        bfsBar.bg:SetAllPoints(statusBar)
    end
    bfsBar.bg:SetAlpha(bgOpacity)
    bfsBar.bg:Show()

    -- 7. Apply crisp border using 4-edge technique
    -- Parent to the bar frame itself (not viewer) so it hides when bar hides
    if borderSize > 0 then
        if not bfsBar.borderContainer then
            local container = CreateFrame("Frame", nil, frame)
            container:SetFrameLevel((frame.GetFrameLevel and frame:GetFrameLevel() or 1) + 5)

            -- Create 4 edge textures
            container._top = container:CreateTexture(nil, "OVERLAY", nil, 7)
            container._top:SetColorTexture(0, 0, 0, 1)
            container._bottom = container:CreateTexture(nil, "OVERLAY", nil, 7)
            container._bottom:SetColorTexture(0, 0, 0, 1)
            container._left = container:CreateTexture(nil, "OVERLAY", nil, 7)
            container._left:SetColorTexture(0, 0, 0, 1)
            container._right = container:CreateTexture(nil, "OVERLAY", nil, 7)
            container._right:SetColorTexture(0, 0, 0, 1)

            bfsBar.borderContainer = container
        end

        local container = bfsBar.borderContainer
        -- Position container to wrap around the bar (extends OUTSIDE by borderSize)
        container:ClearAllPoints()
        container:SetPoint("TOPLEFT", frame, "TOPLEFT", -borderSize, borderSize)
        container:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", borderSize, -borderSize)

        -- Top edge
        container._top:ClearAllPoints()
        container._top:SetPoint("TOPLEFT", container, "TOPLEFT", 0, 0)
        container._top:SetPoint("TOPRIGHT", container, "TOPRIGHT", 0, 0)
        container._top:SetHeight(borderSize)

        -- Bottom edge
        container._bottom:ClearAllPoints()
        container._bottom:SetPoint("BOTTOMLEFT", container, "BOTTOMLEFT", 0, 0)
        container._bottom:SetPoint("BOTTOMRIGHT", container, "BOTTOMRIGHT", 0, 0)
        container._bottom:SetHeight(borderSize)

        -- Left edge
        container._left:ClearAllPoints()
        container._left:SetPoint("TOPLEFT", container, "TOPLEFT", 0, 0)
        container._left:SetPoint("BOTTOMLEFT", container, "BOTTOMLEFT", 0, 0)
        container._left:SetWidth(borderSize)

        -- Right edge
        container._right:ClearAllPoints()
        container._right:SetPoint("TOPRIGHT", container, "TOPRIGHT", 0, 0)
        container._right:SetPoint("BOTTOMRIGHT", container, "BOTTOMRIGHT", 0, 0)
        container._right:SetWidth(borderSize)

        container:Show()
    else
        if bfsBar.borderContainer then
            bfsBar.borderContainer:Hide()
        end
    end

    -- 8. Apply text size to duration/name text (hide if hideText enabled or vertical without showTextOnVertical)
    local generalFont = GetGeneralFont()
    local generalOutline = GetGeneralFontOutline()
    local showText = not hideText and (not isVertical or showTextOnVertical)

    if frame.GetRegions then
        for _, region in ipairs({frame:GetRegions()}) do
            if region and region:GetObjectType() == "FontString" then
                pcall(function()
                    if showText then
                        region:SetFont(generalFont, textSize, generalOutline)
                        region:SetAlpha(1)
                    else
                        region:SetAlpha(0)
                    end
                end)
            end
        end
    end

    if statusBar and statusBar.GetRegions then
        for _, region in ipairs({statusBar:GetRegions()}) do
            if region and region:GetObjectType() == "FontString" then
                pcall(function()
                    if showText then
                        region:SetFont(generalFont, textSize, generalOutline)
                        region:SetAlpha(1)
                    else
                        region:SetAlpha(0)
                    end
                end)
            end
        end
    end

    -- Apply frame alpha as the final step so all child visuals are covered.
    local targetAlpha = 1
    if not isActive then
        if inactiveMode == "fade" then
            targetAlpha = inactiveAlpha
        elseif inactiveMode == "hide" then
            targetAlpha = 0
        end
    end
    pcall(function()
        frame:SetAlpha(targetAlpha)
    end)

    bfsBar.styled = true
end

---------------------------------------------------------------------------
-- ICON CENTER MANAGER (PARENT-SYNCHRONIZED & STABILIZED)
---------------------------------------------------------------------------

local iconState = {
    isInitialized = false,
    lastCount     = 0,
}

LayoutBuffIcons = function()
    local viewer = GetBuffIconViewer()
    if not viewer then return end
    if isIconLayoutRunning then return end  -- Re-entry guard
    if IsLayoutSuppressed() then return end
    -- Skip during Edit Mode — Blizzard controls icon layout/padding.
    -- QUI re-layouts on Edit Mode exit with saved settings.
    if Helpers.IsEditModeActive() then return end

    isIconLayoutRunning = true

    local settings = GetBuffSettings()
    if not settings.enabled then
        isIconLayoutRunning = false
        return
    end

    -- Optional anchoring to CDM/resource/unitframe targets.
    ApplyBuffIconAnchor(settings)

    -- Apply HUD layer priority
    local core = GetCore()
    local hudLayering = core and core.db and core.db.profile and core.db.profile.hudLayering
    local layerPriority = hudLayering and hudLayering.buffIcon or 5
    if core and core.GetHUDFrameLevel then
        local frameLevel = core:GetHUDFrameLevel(layerPriority)
        viewer:SetFrameLevel(frameLevel)
    end

    local icons = GetBuffIconFrames()
    local currentCount = #icons

    -- Handle empty state
    if currentCount == 0 then
        iconState.lastCount = 0
        iconState.isInitialized = false
        isIconLayoutRunning = false
        return
    end

    -- Get settings
    local iconSize = settings.iconSize or 42
    local padding = settings.padding or 0
    local aspectRatio = settings.aspectRatioCrop or 1.0
    local growthDirection = settings.growthDirection or "CENTERED_HORIZONTAL"

    -- Calculate dimensions using crop-based aspect ratio
    local iconWidth, iconHeight = iconSize, iconSize
    if aspectRatio > 1.0 then
        -- Wider: height shrinks
        iconHeight = iconSize / aspectRatio
    elseif aspectRatio < 1.0 then
        -- Taller: width shrinks
        iconWidth = iconSize * aspectRatio
    end

    local targetCount = currentCount
    iconState.lastCount = currentCount
    iconState.isInitialized = true

    -- Determine if vertical or horizontal layout
    local isVertical = (growthDirection == "UP" or growthDirection == "DOWN")

    -- Calculate total size using our settings
    local totalWidth, totalHeight
    if isVertical then
        totalWidth = iconWidth
        totalHeight = (targetCount * iconHeight) + ((targetCount - 1) * padding)
        totalHeight = QUICore:PixelRound(totalHeight)
    else
        totalWidth = (targetCount * iconWidth) + ((targetCount - 1) * padding)
        totalWidth = QUICore:PixelRound(totalWidth)
        totalHeight = iconHeight
    end

    -- Calculate starting position — icons anchor at CENTER of viewer.
    -- This keeps icons stable regardless of Blizzard's auto-sized viewer height
    -- (same approach as Essential/Utility viewers).
    local startX, startY
    if isVertical then
        startX = 0
        if growthDirection == "UP" then
            -- Grow up: icon 1 at bottom of stack, icons stack upward
            startY = -(totalHeight / 2) + iconHeight / 2
        else -- DOWN
            -- Grow down: icon 1 at top of stack, icons stack downward
            startY = (totalHeight / 2) - iconHeight / 2
        end
        startY = QUICore:PixelRound(startY)
    else
        -- Horizontal: centered both ways
        startX = -totalWidth / 2 + iconWidth / 2
        startX = QUICore:PixelRound(startX)
        startY = 0
    end

    -- Tolerance-based check: skip repositioning if all icons are already in correct positions
    -- Prevents jitter from floating-point drift (allows 2px tolerance)
    local needsReposition = false
    for i, icon in ipairs(icons) do
        if isVertical then
            local expectedY
            if growthDirection == "UP" then
                expectedY = QUICore:PixelRound(startY + (i - 1) * (iconHeight + padding))
            else -- DOWN
                expectedY = QUICore:PixelRound(startY - (i - 1) * (iconHeight + padding))
            end
            local point, _, _, xOfs, yOfs = icon:GetPoint(1)
            if not point or point ~= "CENTER" or abs((yOfs or 0) - expectedY) > 2 then
                needsReposition = true
                break
            end
        else
            local expectedX = QUICore:PixelRound(startX + (i - 1) * (iconWidth + padding))
            if not PositionMatchesTolerance(icon, expectedX, 2) then
                needsReposition = true
                break
            end
        end
    end

    if needsReposition then
        -- TWO-PASS LAYOUT: Clear all points first, then position - prevents mixed state flicker
        -- PASS 1: Clear all points first
        for _, icon in ipairs(icons) do
            icon:ClearAllPoints()
        end

        -- PASS 2: Apply style and position each icon
        for i, icon in ipairs(icons) do
            ApplyIconStyle(icon, settings)
            if isVertical then
                local y
                if growthDirection == "UP" then
                    y = startY + (i - 1) * (iconHeight + padding)
                else -- DOWN
                    y = startY - (i - 1) * (iconHeight + padding)
                end
                icon:SetPoint("CENTER", viewer, "CENTER", 0, QUICore:PixelRound(y))
            else
                local x = startX + (i - 1) * (iconWidth + padding)
                icon:SetPoint("CENTER", viewer, "CENTER", QUICore:PixelRound(x), QUICore:PixelRound(startY))
            end
        end
    else
        -- Positions are correct, just apply styling (skip SetPoint calls)
        for _, icon in ipairs(icons) do
            ApplyIconStyle(icon, settings)
        end
    end

    -- Owned containers need explicit sizing (Blizzard viewers auto-size from children).
    if IsOwnedEngine() then
        viewer:SetSize(totalWidth, totalHeight)
    end

    -- Write calculated dimensions to viewer state so the proxy sizeResolver
    -- (CDMSizeResolver) reads our formula dimensions instead of falling back
    -- to Blizzard's auto-sized frame dimensions.
    if _G.QUI_SetCDMViewerBounds then
        _G.QUI_SetCDMViewerBounds(viewer, totalWidth, totalHeight)
    end

    isIconLayoutRunning = false
end

---------------------------------------------------------------------------
-- BAR ALIGNMENT MANAGER (FORCED UPWARD GROWTH)
---------------------------------------------------------------------------

local barState = {
    lastCount      = 0,
    lastBarWidth   = nil,
    lastBarHeight  = nil,
    lastSpacing    = nil,
}

LayoutBuffBars = function()
    local viewer = GetBuffBarViewer()
    if not viewer then return end
    if isBarLayoutRunning then return end  -- Re-entry guard
    if IsLayoutSuppressed() then return end
    -- Skip during Edit Mode — Blizzard controls bar layout/padding.
    if Helpers.IsEditModeActive() then return end

    isBarLayoutRunning = true

    -- Combat-safe refresh path: avoid moving the viewer anchor itself, but still
    -- keep per-bar style/size/stack positioning in sync so QUI options are honored
    -- when bars appear mid-combat.
    if InCombatLockdown() then
        -- Apply HUD layer priority to bars even during combat.
        local core = GetCore()
        local hudLayering = core and core.db and core.db.profile and core.db.profile.hudLayering
        local layerPriority = hudLayering and hudLayering.buffBar or 5
        local frameLevel = 200
        if core and core.GetHUDFrameLevel then
            frameLevel = core:GetHUDFrameLevel(layerPriority)
        end

        local settings = GetTrackedBarSettings()
        local stylingEnabled = settings.enabled
        local inactiveMode = settings.inactiveMode or "hide"
        if inactiveMode ~= "always" and inactiveMode ~= "fade" and inactiveMode ~= "hide" then
            inactiveMode = "always"
        end
        local inactiveAlpha = Clamp01(settings.inactiveAlpha, 0.3)
        local reserveSlotWhenInactive = (settings.reserveSlotWhenInactive == true)
        local bars = GetBuffBarFrames()
        local count = #bars
        if count == 0 then
            isBarLayoutRunning = false
            return
        end

        local refBar = bars[1]
        if not refBar then
            isBarLayoutRunning = false
            return
        end

        local barWidth = refBar:GetWidth()
        local resolvedBarWidth = settings.barWidth or barWidth
        local placement = settings.anchorPlacement or "center"
        local anchorTo = settings.anchorTo or "disabled"
        local canAutoWidth = stylingEnabled and settings.autoWidth and (anchorTo ~= "screen")
        if canAutoWidth then
            local anchorFrame
            local widthAnchorType = anchorTo
            if placement == "onTopResourceBars" then
                anchorFrame = GetTopVisibleResourceBarFrame()
                widthAnchorType = nil
            else
                anchorFrame = ResolveTrackedBarAnchorFrame(anchorTo)
            end
            if not anchorFrame and placement == "onTopResourceBars" then
                anchorFrame = ResolveTrackedBarAnchorFrame(anchorTo)
                widthAnchorType = anchorTo
            end
            if anchorFrame and anchorFrame:IsShown() then
                local anchorWidth = GetTrackedBarAnchorWidth(widthAnchorType, anchorFrame)
                if anchorWidth then
                    local adjust = settings.autoWidthOffset or 0
                    resolvedBarWidth = math.max(20, QUICore:PixelRound(anchorWidth + adjust, viewer))
                end
            end
        end
        if stylingEnabled then
            barWidth = resolvedBarWidth
        end

        local barHeight = stylingEnabled and settings.barHeight or refBar:GetHeight()
        local spacing = stylingEnabled and settings.spacing or (viewer.childYPadding or 0)
        local growFromBottom = (not stylingEnabled) or (settings.growUp ~= false)
        local orientation = stylingEnabled and settings.orientation or "horizontal"
        local isVertical = (orientation == "vertical")
        if stylingEnabled and ((settings.anchorTo or "disabled") ~= "disabled" or placement == "onTopResourceBars") then
            if placement == "onTop" or placement == "onTopResourceBars" then
                growFromBottom = true
            elseif placement == "below" then
                growFromBottom = false
            elseif isVertical and placement == "right" then
                growFromBottom = true
            elseif isVertical and placement == "left" then
                growFromBottom = false
            end
        end

        local effectiveBarWidth, effectiveBarHeight
        if isVertical then
            effectiveBarWidth = barHeight
            effectiveBarHeight = stylingEnabled and resolvedBarWidth or 200
        else
            effectiveBarWidth = barWidth
            effectiveBarHeight = barHeight
        end

        -- Keep Blizzard layout direction state aligned with QUI settings.
        viewerBuffState[viewer] = viewerBuffState[viewer] or {}
        local vbsBar = viewerBuffState[viewer]
        vbsBar.isHorizontal = not isVertical
        if isVertical then
            vbsBar.goingRight = growFromBottom
            vbsBar.goingUp = false
        else
            vbsBar.goingRight = true
            vbsBar.goingUp = growFromBottom
        end

        -- COMBAT PASS 1: Apply styling and strata/level first.
        -- SetHeight/SetWidth in ApplyBarStyle can trigger Blizzard's Layout()
        -- which repositions bars with default spacing, so we style first and
        -- position last to ensure QUI spacing wins.
        for _, frame in ipairs(bars) do
            if stylingEnabled then
                ApplyBarStyle(frame, settings, resolvedBarWidth)
            else
                pcall(function()
                    frame:SetAlpha(1)
                end)
            end

            -- Keep strata/level in sync with HUD layering.
            pcall(function()
                frame:SetFrameStrata("MEDIUM")
                frame:SetFrameLevel(frameLevel)
                if frame.Bar then
                    frame.Bar:SetFrameStrata("MEDIUM")
                    frame.Bar:SetFrameLevel(frameLevel + 1)
                end
                if frame.Icon then
                    frame.Icon:SetFrameStrata("MEDIUM")
                    frame.Icon:SetFrameLevel(frameLevel + 1)
                end
            end)
        end

        -- COMBAT PASS 2: Position bars and apply alpha LAST so QUI spacing
        -- overrides any positions Blizzard's Layout() set during styling.
        for index, frame in ipairs(bars) do
            pcall(function()
                frame:ClearAllPoints()
                local offsetIndex = index - 1
                if isVertical then
                    local x
                    if growFromBottom then
                        x = QUICore:PixelRound(offsetIndex * (effectiveBarWidth + spacing))
                        frame:SetPoint("LEFT", viewer, "LEFT", x, 0)
                    else
                        x = QUICore:PixelRound(-offsetIndex * (effectiveBarWidth + spacing))
                        frame:SetPoint("RIGHT", viewer, "RIGHT", x, 0)
                    end
                else
                    local y
                    if growFromBottom then
                        y = QUICore:PixelRound(offsetIndex * (effectiveBarHeight + spacing))
                        frame:SetPoint("BOTTOM", viewer, "BOTTOM", 0, y)
                    else
                        y = QUICore:PixelRound(-offsetIndex * (effectiveBarHeight + spacing))
                        frame:SetPoint("TOP", viewer, "TOP", 0, y)
                    end
                end
            end)

            local bfs = barFrameState[frame]
            local isActive = not (bfs and bfs.isActive == false)
            local targetAlpha = 1
            if not isActive then
                if inactiveMode == "fade" then
                    targetAlpha = inactiveAlpha
                elseif inactiveMode == "hide" and not reserveSlotWhenInactive then
                    targetAlpha = 0
                end
            end
            pcall(function()
                frame:SetAlpha(targetAlpha)
            end)
        end

        isBarLayoutRunning = false
        return
    end

    -- Apply HUD layer priority (strata + level)
    local core = GetCore()
    local hudLayering = core and core.db and core.db.profile and core.db.profile.hudLayering
    local layerPriority = hudLayering and hudLayering.buffBar or 5
    local frameLevel = 200  -- Default fallback
    if core and core.GetHUDFrameLevel then
        frameLevel = core:GetHUDFrameLevel(layerPriority)
    end
    -- Set strata to MEDIUM to match power bars, then apply frame level
    viewer:SetFrameStrata("MEDIUM")
    viewer:SetFrameLevel(frameLevel)

    -- Get tracked bar settings
    local settings = GetTrackedBarSettings()
    local stylingEnabled = settings.enabled

    -- Optional anchoring to CDM/resource/unitframe targets.
    ApplyTrackedBarAnchor(settings)

    local bars = GetBuffBarFrames()
    local count = #bars
    if count == 0 then
        barState.lastCount = 0
        isBarLayoutRunning = false
        return
    end

    local refBar = bars[1]
    if not refBar then
        isBarLayoutRunning = false
        return
    end

    -- Use settings for dimensions if styling enabled, otherwise use frame defaults
    local barWidth = refBar:GetWidth()
    local resolvedBarWidth = settings.barWidth or barWidth
    local placement = settings.anchorPlacement or "center"
    local anchorTo = settings.anchorTo or "disabled"
    local canAutoWidth = stylingEnabled and settings.autoWidth and (anchorTo ~= "screen")
    if canAutoWidth then
        local anchorFrame
        local widthAnchorType = anchorTo
        if placement == "onTopResourceBars" then
            anchorFrame = GetTopVisibleResourceBarFrame()
            widthAnchorType = nil
        else
            anchorFrame = ResolveTrackedBarAnchorFrame(anchorTo)
        end
        if not anchorFrame and placement == "onTopResourceBars" then
            anchorFrame = ResolveTrackedBarAnchorFrame(anchorTo)
            widthAnchorType = anchorTo
        end
        if anchorFrame and anchorFrame:IsShown() then
            local anchorWidth = GetTrackedBarAnchorWidth(widthAnchorType, anchorFrame)
            if anchorWidth then
                local adjust = settings.autoWidthOffset or 0
                resolvedBarWidth = math.max(20, QUICore:PixelRound(anchorWidth + adjust, viewer))
            end
        end
    end
    if stylingEnabled then
        barWidth = resolvedBarWidth
    end

    local barHeight = stylingEnabled and settings.barHeight or refBar:GetHeight()
    local spacing = stylingEnabled and settings.spacing or (viewer.childYPadding or 0)
    local growFromBottom = (not stylingEnabled) or (settings.growUp ~= false)

    -- Vertical bar support
    local orientation = stylingEnabled and settings.orientation or "horizontal"
    local isVertical = (orientation == "vertical")
    if stylingEnabled and ((settings.anchorTo or "disabled") ~= "disabled" or placement == "onTopResourceBars") then
        if placement == "onTop" then
            growFromBottom = true
        elseif placement == "onTopResourceBars" then
            growFromBottom = true
        elseif placement == "below" then
            growFromBottom = false
        elseif isVertical and placement == "right" then
            growFromBottom = true
        elseif isVertical and placement == "left" then
            growFromBottom = false
        end
    end

    -- CRITICAL: Tell Blizzard's GridLayoutFrameMixin which layout direction to use
    -- When isHorizontal=true, Blizzard positions bars up/down (Y-axis)
    -- When isHorizontal=false, Blizzard positions bars left/right (X-axis)
    -- This prevents Blizzard's Layout() from overriding QUI's positioning with wrong axis
    -- TAINT SAFETY: Store layout flags in local table instead of writing to Blizzard viewer
    viewerBuffState[viewer] = viewerBuffState[viewer] or {}
    local vbsBar = viewerBuffState[viewer]
    vbsBar.isHorizontal = not isVertical
    -- Also update direction flags to match QUI's growth direction
    if isVertical then
        vbsBar.goingRight = growFromBottom  -- growUp becomes growRight
        vbsBar.goingUp = false
    else
        vbsBar.goingRight = true
        vbsBar.goingUp = growFromBottom
    end

    -- For vertical bars, swap dimensions (height setting becomes width)
    local effectiveBarWidth, effectiveBarHeight
    if isVertical then
        effectiveBarWidth = barHeight  -- Height setting becomes bar width
        effectiveBarHeight = stylingEnabled and resolvedBarWidth or 200  -- Width setting becomes bar height
    else
        effectiveBarWidth = barWidth
        effectiveBarHeight = barHeight
    end

    if not effectiveBarHeight or effectiveBarHeight == 0 then
        isBarLayoutRunning = false
        return
    end

    barState.lastCount = count
    barState.lastBarWidth = effectiveBarWidth
    barState.lastBarHeight = effectiveBarHeight
    barState.lastSpacing = spacing

    -- Total size of the stack (height for horizontal bars, width for vertical)
    local totalSize
    if isVertical then
        totalSize = (count * effectiveBarWidth) + ((count - 1) * spacing)
    else
        totalSize = (count * effectiveBarHeight) + ((count - 1) * spacing)
    end
    totalSize = QUICore:PixelRound(totalSize)

    -- PASS 1: Apply visual styling and frame strata/level FIRST.
    -- ApplyBarStyle calls SetHeight/SetWidth which can trigger Blizzard's Layout()
    -- on the viewer, overriding bar positions. By styling first we let Blizzard's
    -- Layout finish before our positioning pass claims the final word.
    for _, bar in ipairs(bars) do
        if stylingEnabled then
            ApplyBarStyle(bar, settings, resolvedBarWidth)
        else
            pcall(function()
                bar:SetAlpha(1)
            end)
            local iconContainer = bar.Icon
            local iconTexture = iconContainer and (iconContainer.Icon or iconContainer.icon or iconContainer.texture)
            if iconTexture and iconTexture.SetDesaturated then
                pcall(function()
                    iconTexture:SetDesaturated(false)
                end)
            end
        end
        -- Apply frame strata/level to each bar AND its .Bar child for proper HUD layering
        bar:SetFrameStrata("MEDIUM")
        bar:SetFrameLevel(frameLevel)
        if bar.Bar then
            bar.Bar:SetFrameStrata("MEDIUM")
            bar.Bar:SetFrameLevel(frameLevel + 1)
        end
        if bar.Icon then
            bar.Icon:SetFrameStrata("MEDIUM")
            bar.Icon:SetFrameLevel(frameLevel + 1)
        end
    end

    -- POSITION CHECK: After styling, verify if bars need repositioning.
    -- The styling pass above may have triggered Blizzard's Layout() which uses
    -- its own childYPadding — check for position drift before doing SetPoint work.
    local needsReposition = false
    for index, bar in ipairs(bars) do
        local offsetIndex = index - 1
        if isVertical then
            local expectedX
            if growFromBottom then
                expectedX = QUICore:PixelRound(offsetIndex * (effectiveBarWidth + spacing))
            else
                expectedX = QUICore:PixelRound(-offsetIndex * (effectiveBarWidth + spacing))
            end
            local point, _, _, xOfs = bar:GetPoint(1)
            if not point or abs((xOfs or 0) - expectedX) > 2 then
                needsReposition = true
                break
            end
        else
            local expectedY
            if growFromBottom then
                expectedY = QUICore:PixelRound(offsetIndex * (effectiveBarHeight + spacing))
            else
                expectedY = QUICore:PixelRound(-offsetIndex * (effectiveBarHeight + spacing))
            end
            local point, _, _, _, yOfs = bar:GetPoint(1)
            if not point or abs((yOfs or 0) - expectedY) > 2 then
                needsReposition = true
                break
            end
        end
    end

    -- PASS 2: Position each bar LAST so QUI's spacing overrides any positions
    -- that Blizzard's Layout() applied during the styling pass above.
    if needsReposition then
        for _, bar in ipairs(bars) do
            bar:ClearAllPoints()
        end
        for index, bar in ipairs(bars) do
            local offsetIndex = index - 1

            if isVertical then
                -- VERTICAL BARS: Stack horizontally (left/right)
                local x
                if growFromBottom then
                    -- Grow Right: bar 1 at LEFT edge, stacks rightward
                    x = offsetIndex * (effectiveBarWidth + spacing)
                    x = QUICore:PixelRound(x)
                    bar:SetPoint("LEFT", viewer, "LEFT", x, 0)
                else
                    -- Grow Left: bar 1 at RIGHT edge, stacks leftward
                    x = -offsetIndex * (effectiveBarWidth + spacing)
                    x = QUICore:PixelRound(x)
                    bar:SetPoint("RIGHT", viewer, "RIGHT", x, 0)
                end
            else
                -- HORIZONTAL BARS: Stack vertically (up/down)
                local y
                if growFromBottom then
                    y = offsetIndex * (effectiveBarHeight + spacing)
                    y = QUICore:PixelRound(y)
                    bar:SetPoint("BOTTOM", viewer, "BOTTOM", 0, y)
                else
                    y = -offsetIndex * (effectiveBarHeight + spacing)
                    y = QUICore:PixelRound(y)
                    bar:SetPoint("TOP", viewer, "TOP", 0, y)
                end
            end
        end
    end

    -- No SetSize on the viewer frame — Blizzard auto-sizes it from children.
    -- This prevents the SetSize → RefreshLayout → re-layout loop.
    -- Ensure Blizzard's Layout() uses correct direction flags.
    if isVertical then
        vbsBar.isHorizontal = false
    else
        vbsBar.isHorizontal = true
        vbsBar.goingUp = growFromBottom
    end

    -- Write calculated dimensions to viewer state so the proxy sizeResolver
    -- reads our formula dimensions instead of Blizzard's auto-sized frame size.
    if _G.QUI_SetCDMViewerBounds then
        local bw, bh
        if isVertical then
            bw = totalSize
            bh = effectiveBarHeight
        else
            bw = effectiveBarWidth
            bh = totalSize
        end
        _G.QUI_SetCDMViewerBounds(viewer, bw, bh)
    end

    isBarLayoutRunning = false
end

---------------------------------------------------------------------------
-- CHANGE DETECTION (called from OnUpdate hooks on viewers)
-- Icons: Hash-based detection for count/settings changes
-- Bars: Position verification (hash removed - bars now self-correct via position checks)
---------------------------------------------------------------------------

local lastIconHash = ""

-- Build hash of icon count + settings to detect actual changes
local function BuildIconHash(count, settings)
    return string.format("%d_%d_%d_%.2f_%d_%s_%s_%s_%d_%s_%s_%d_%d",
        count,
        settings.iconSize or 42,
        settings.padding or 0,
        settings.aspectRatioCrop or 1.0,
        settings.borderSize or 2,
        settings.growthDirection or "CENTERED_HORIZONTAL",
        settings.anchorTo or "disabled",
        settings.anchorPlacement or "center",
        settings.anchorSpacing or 0,
        settings.anchorSourcePoint or "CENTER",
        settings.anchorTargetPoint or "CENTER",
        settings.anchorOffsetX or 0,
        settings.anchorOffsetY or 0
    )
end

local function CheckIconChanges()
    local viewer = GetBuffIconViewer()
    if not viewer then return end
    if isIconLayoutRunning then return end
    if IsLayoutSuppressed() then return end
    -- Skip during Edit Mode — Blizzard controls icon layout/padding.
    if Helpers.IsEditModeActive() then return end

    -- Count visible icons
    local visibleCount = 0
    if IsOwnedEngine() then
        local pool = ns.CDMIcons and ns.CDMIcons:GetIconPool("buff")
        if pool then
            for _, icon in ipairs(pool) do
                if icon:IsShown() then visibleCount = visibleCount + 1 end
            end
        end
    else
        for _, child in ipairs({ viewer:GetChildren() }) do
            if child and child ~= viewer.Selection then
                if (child.icon or child.Icon) and child:IsShown() then
                    visibleCount = visibleCount + 1
                end
            end
        end
    end

    -- Build hash including count AND settings
    local settings = GetBuffSettings()
    ApplyBuffIconAnchor(settings)
    local hash = BuildIconHash(visibleCount, settings)

    -- Only layout if hash changed (count or settings)
    if hash == lastIconHash then
        return
    end

    lastIconHash = hash
    LayoutBuffIcons()
end

local function CheckBarChanges()
    if not GetBuffBarViewer() then return end
    if isBarLayoutRunning then return end  -- Skip if already laying out
    -- Skip during Edit Mode — Blizzard controls bar layout/padding.
    if Helpers.IsEditModeActive() then return end

    -- Always call LayoutBuffBars - it styles bars first, then verifies positions
    -- and corrects any drift caused by Blizzard's Layout() overriding QUI spacing.
    LayoutBuffBars()
end

---------------------------------------------------------------------------
-- OnUpdate handlers for buff icon/bar viewers (module-level to avoid
-- per-hook closure allocation).  Elapsed accumulators live at module scope
-- instead of being captured upvalues inside anonymous closures.
---------------------------------------------------------------------------
local buffIconOnUpdateElapsed = 0
local buffBarOnUpdateElapsed = 0

local function BuffIconViewer_OnUpdate(self, elapsed)
    buffIconOnUpdateElapsed = buffIconOnUpdateElapsed + elapsed
    if buffIconOnUpdateElapsed > 0.05 then  -- 20 FPS polling - hash prevents over-layout
        buffIconOnUpdateElapsed = 0
        if self:IsShown() then
            CheckIconChanges()
        end
    end
end

local function BuffBarViewer_OnUpdate(self, elapsed)
    buffBarOnUpdateElapsed = buffBarOnUpdateElapsed + elapsed
    if buffBarOnUpdateElapsed > 0.05 then  -- 20 FPS for bars
        buffBarOnUpdateElapsed = 0
        if self:IsShown() then
            CheckBarChanges()
        end
    end
end

---------------------------------------------------------------------------
-- FORCE POPULATE: Briefly trigger Edit Mode behavior to load all spells
-- This ensures the buff icons know what spells to display on first load
---------------------------------------------------------------------------

local forcePopulateDone = false

local function ForcePopulateBuffIcons()
    if forcePopulateDone then return end
    if InCombatLockdown() then return end

    -- Owned engine: trigger spell data rescan; the container module handles
    -- icon building and fires QUI_OnBuffLayoutReady when icons are ready.
    if IsOwnedEngine() then
        forcePopulateDone = true
        if ns.CDMSpellData then
            ns.CDMSpellData:ForceScan()
        end
        return
    end

    -- Classic engine: poke Blizzard viewer to populate
    local viewer = GetBuffIconViewer()
    if not viewer then return end

    forcePopulateDone = true

    -- Method 1: Call Layout() which triggers Blizzard to populate icons
    if viewer.Layout and type(viewer.Layout) == "function" then
        pcall(function()
            viewer:Layout()
        end)
    end

    -- Method 2: If the viewer has systemInfo with spells, it should auto-populate
    -- Just triggering a size change can help force refresh
    if not InCombatLockdown() then
        local w, h = viewer:GetSize()
        if w and h and w > 0 and h > 0 then
            -- Briefly nudge size to trigger internal refresh
            pcall(function()
                viewer:SetSize(w + 0.1, h)
                C_Timer.After(0.05, function()
                    if viewer and not InCombatLockdown() then
                        pcall(function() viewer:SetSize(w, h) end)
                    end
                end)
            end)
        end
    end

    -- Method 3: Force a rescan via QUICore if available
    local core = GetCore()
    if core and core.ForceRefreshBuffIcons then
            C_Timer.After(0.2, function()
                pcall(function() core:ForceRefreshBuffIcons() end)
            end)
    end
end

---------------------------------------------------------------------------
-- INITIALIZATION
---------------------------------------------------------------------------

local initialized = false

local function Initialize()
    if initialized then return end
    initialized = true

    -- CRITICAL: Set layout direction IMMEDIATELY at login, before combat can start
    -- This prevents Blizzard's Layout() from using wrong axis if first buff appears during combat
    -- TAINT SAFETY: Store in local table instead of writing to Blizzard viewer
    local barViewer = GetBuffBarViewer()
    if barViewer and not InCombatLockdown() then
        local settings = GetTrackedBarSettings()
        local isVertical = (settings.orientation == "vertical")
        local growFromBottom = (settings.growUp ~= false)

        viewerBuffState[barViewer] = viewerBuffState[barViewer] or {}
        local vbs = viewerBuffState[barViewer]
        vbs.isHorizontal = not isVertical
        if isVertical then
            vbs.goingRight = growFromBottom
            vbs.goingUp = false
        else
            vbs.goingRight = true
            vbs.goingUp = growFromBottom
        end
    end

    -- Force populate buff icons first (teaches the viewer what spells to show)
    ForcePopulateBuffIcons()

    -- TAINT SAFETY: OnUpdate hooks use module-level elapsed tracking instead of
    -- writing properties to Blizzard CDM viewer frames, to avoid tainting the
    -- frame table.  Handlers are module-level named functions (BuffIconViewer_OnUpdate,
    -- BuffBarViewer_OnUpdate) so no closure is allocated per HookScript call.
    -- OnUpdate polling at 0.05s (20 FPS) - works alongside UNIT_AURA event detection
    local iconViewer = GetBuffIconViewer()
    local iconVbs = iconViewer and (viewerBuffState[iconViewer] or {})
    if iconViewer then viewerBuffState[iconViewer] = iconVbs end
    if iconViewer and not iconVbs.onUpdateHooked then
        iconVbs.onUpdateHooked = true
        iconViewer:HookScript("OnUpdate", BuffIconViewer_OnUpdate)
    end

    barViewer = GetBuffBarViewer()
    local barVbs = barViewer and (viewerBuffState[barViewer] or {})
    if barViewer then viewerBuffState[barViewer] = barVbs end
    if barViewer and not barVbs.onUpdateHooked then
        barVbs.onUpdateHooked = true
        barViewer:HookScript("OnUpdate", BuffBarViewer_OnUpdate)
    end

    -- TAINT SAFETY: ALL hooks on Blizzard CDM viewer frames must defer via C_Timer.After(0)
    -- to break taint chain from secure CDM context. CDM viewers are Edit Mode managed frames.

    -- OnSizeChanged removed: Blizzard auto-sizes the viewer from children,
    -- which would create a loop (LayoutBuffIcons → icon SetPoint → auto-size
    -- → OnSizeChanged → LayoutBuffIcons). The Layout hook below covers
    -- Blizzard-initiated layout changes.

    -- Blizzard viewer hooks (classic engine only — owned containers don't use
    -- .Layout/.RefreshLayout and the alpha=0 Blizzard viewer never shows).
    if not IsOwnedEngine() then
        -- OnShow hook - refresh when viewer becomes visible
        if iconViewer then
            iconViewer:HookScript("OnShow", function(self)
                C_Timer.After(0, function()
                    if InCombatLockdown() then return end
                    if IsLayoutSuppressed() then return end
                    if isIconLayoutRunning then return end
                    LayoutBuffIcons()
                end)
            end)
        end

        -- Hook Layout - deferred call after Blizzard's layout completes
        if iconViewer and iconViewer.Layout then
            hooksecurefunc(iconViewer, "Layout", function()
                C_Timer.After(0, function()
                    if InCombatLockdown() then return end
                    if IsLayoutSuppressed() then return end
                    if isIconLayoutRunning then return end
                    LayoutBuffIcons()
                end)
            end)
        end

        if barViewer and barViewer.Layout then
            hooksecurefunc(barViewer, "Layout", function()
                C_Timer.After(0, function()
                    if InCombatLockdown() then return end
                    if IsLayoutSuppressed() then return end
                    if isBarLayoutRunning then return end
                    LayoutBuffBars()
                end)
            end)
        end

        -- FEAT-007: Hook RefreshLayout to correct layout direction after Blizzard sets it
        -- Blizzard's RefreshLayout() sets isHorizontal based on IsHorizontal() (always true for BuffBar)
        -- then calls Layout(). We hook RefreshLayout to fix direction right before Layout() runs.
        -- TAINT SAFETY: Store in local table instead of writing to Blizzard viewer
        if barViewer and barViewer.RefreshLayout then
            hooksecurefunc(barViewer, "RefreshLayout", function(self)
                C_Timer.After(0, function()
                    if InCombatLockdown() then return end
                    local settings = GetTrackedBarSettings()
                    if settings.enabled and settings.orientation == "vertical" then
                        viewerBuffState[self] = viewerBuffState[self] or {}
                        viewerBuffState[self].isHorizontal = false
                        viewerBuffState[self].goingRight = settings.growUp ~= false
                        viewerBuffState[self].goingUp = false
                    end
                end)
            end)
        end
    end

    ---------------------------------------------------------------------------
    -- EVENT-BASED UPDATES: UNIT_AURA hook for immediate buff change detection
    -- (Replaces polling as primary detection - polling becomes fallback only)
    ---------------------------------------------------------------------------

    -- TAINT SAFETY: Use local variables instead of writing to Blizzard CDM viewer frames.
    local auraHookCreated = false
    local rescanPending = false
    iconViewer = GetBuffIconViewer()
    if iconViewer and not auraHookCreated then
        auraHookCreated = true
        local auraEventFrame = CreateFrame("Frame")
        auraEventFrame:RegisterEvent("UNIT_AURA")
        auraEventFrame:SetScript("OnEvent", function(_, event, unit)
            local iv = GetBuffIconViewer()
            if unit == "player" and iv and iv:IsShown() then
                -- Debounce: only queue one rescan per 0.1s window
                if not rescanPending then
                    rescanPending = true
                    C_Timer.After(0.1, function()
                        rescanPending = false
                        -- Re-check visibility after timer (viewer may have hidden)
                        local iv2 = GetBuffIconViewer()
                        if iv2 and iv2:IsShown() then
                            if isIconLayoutRunning then return end
                            if IsLayoutSuppressed() then return end
                            -- Reset hash to force layout recalculation
                            lastIconHash = ""
                            CheckIconChanges()
                        end
                    end)
                end
            end
        end)
    end

    -- Initial layouts (after force populate)
    C_Timer.After(0.3, function()
        LayoutBuffIcons()  -- Direct calls
        LayoutBuffBars()
    end)
end

---------------------------------------------------------------------------
-- EVENT HANDLING
---------------------------------------------------------------------------

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
eventFrame:SetScript("OnEvent", function(self, event, ...)
    if event == "PLAYER_LOGIN" then
        C_Timer.After(1, Initialize)
        -- Additional force populate attempts
        C_Timer.After(2, ForcePopulateBuffIcons)
        C_Timer.After(4, ForcePopulateBuffIcons)
    elseif event == "PLAYER_ENTERING_WORLD" then
        local isInitialLogin, isReloadingUi = ...
        if isInitialLogin or isReloadingUi then
            C_Timer.After(1.5, function()
                ForcePopulateBuffIcons()
                LayoutBuffIcons()  -- Direct calls
                LayoutBuffBars()
            end)
        end
    elseif event == "PLAYER_REGEN_ENABLED" then
        -- After combat ends, try to populate if we haven't yet
        C_Timer.After(0.5, function()
            ForcePopulateBuffIcons()
            LayoutBuffIcons()  -- Direct calls
            LayoutBuffBars()
        end)
    end
end)

---------------------------------------------------------------------------
-- OWNED ENGINE CALLBACKS
-- cdm_containers.lua fires these when buff container/icons are ready.
---------------------------------------------------------------------------
_G.QUI_OnBuffContainerReady = function()
    -- Container was just created; re-initialize if we haven't yet
    if not initialized then
        Initialize()
    end
end

_G.QUI_OnBuffLayoutReady = function()
    -- Icons were (re)built in the owned container; position + style them
    lastIconHash = ""
    iconState.isInitialized = false
    LayoutBuffIcons()
end

-- Also try to initialize immediately if viewers exist
C_Timer.After(0, function()
    if GetBuffIconViewer() or GetBuffBarViewer() then
        Initialize()
    end
end)

---------------------------------------------------------------------------
-- EDIT MODE CALLBACKS: Re-apply QUI icon size / padding on exit
---------------------------------------------------------------------------

do
    local core = GetCore()
    if core and core.RegisterEditModeExit then
        core:RegisterEditModeExit(function()
            -- Reset hash so the next CheckIconChanges() triggers a full re-layout
            lastIconHash = ""
            iconState.isInitialized = false
            barState.lastCount = 0

            -- Deferred: Blizzard may still be tearing down Edit Mode on this frame
            C_Timer.After(0.1, function()
                if InCombatLockdown() then return end
                LayoutBuffIcons()
                LayoutBuffBars()
            end)
        end)
    end
end

---------------------------------------------------------------------------
-- PUBLIC API
---------------------------------------------------------------------------

QUI_BuffBar.LayoutIcons = LayoutBuffIcons
QUI_BuffBar.LayoutBars = LayoutBuffBars
QUI_BuffBar.Initialize = Initialize

-- Force refresh function (can be called from GUI)
function QUI_BuffBar.Refresh()
    -- Reset states to force recalculation
    iconState.isInitialized = false
    iconState.lastCount = 0
    barState.lastCount = 0
    lastIconHash = ""  -- Force hash recalculation for icons

    -- Update layout direction when settings change (e.g., orientation toggle)
    -- Must be done outside combat to take effect
    -- TAINT SAFETY: Store in local table instead of writing to Blizzard viewer
    local barViewer = GetBuffBarViewer()
    if barViewer and not InCombatLockdown() then
        local settings = GetTrackedBarSettings()
        local isVertical = (settings.orientation == "vertical")
        local growFromBottom = (settings.growUp ~= false)

        viewerBuffState[barViewer] = viewerBuffState[barViewer] or {}
        local vbs = viewerBuffState[barViewer]
        vbs.isHorizontal = not isVertical
        if isVertical then
            vbs.goingRight = growFromBottom
            vbs.goingUp = false
        else
            vbs.goingRight = true
            vbs.goingUp = growFromBottom
        end
    end

    LayoutBuffIcons()
    LayoutBuffBars()
end

-- Global refresh function for GUI
_G.QUI_RefreshBuffBar = QUI_BuffBar.Refresh
