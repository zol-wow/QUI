local ADDON_NAME, ns = ...
local QUICore = ns.Addon
local LSM = ns.LSM
local Sources = ns.CDMSources

local GetCore = ns.Helpers.GetCore

local type = type
local pcall = pcall
local ipairs = ipairs
local tostring = tostring
local CreateFrame = CreateFrame
local InCombatLockdown = InCombatLockdown
local C_Timer = C_Timer
local hooksecurefunc = hooksecurefunc
local _securecall = securecallfunction or function(fn, ...) return fn(...) end
local table_insert = table.insert

local CDMBuffLayout = {}
ns.CDMBuffLayout = CDMBuffLayout

local inInitSafeWindow = false

local Helpers = ns.Helpers

local function GetBuffIconViewer() return _G.QUI_GetCDMViewerFrame("buffIcon") end
local function GetBuffBarViewer() return _G.QUI_GetCDMViewerFrame("buffBar") end
local function GetEssentialViewer() return _G.QUI_GetCDMViewerFrame("essential") end
local function GetUtilityViewer() return _G.QUI_GetCDMViewerFrame("utility") end

local floor = math.floor

local function snapPx(value, px)
    if value == 0 then return 0 end
    return floor(value / px + 0.5) * px
end

local viewerBuffState = Helpers.CreateStateTable()

local abs = math.abs

local WoW_IsSecretValue = issecretvalue

local function ReadNumber(value, fallback)
    if WoW_IsSecretValue and WoW_IsSecretValue(value) then return fallback end
    local valueType = type(value)
    if valueType == "number" then return value end
    if valueType == "string" then return tonumber(value) or fallback end
    return fallback
end

local function ReadString(value, fallback)
    if WoW_IsSecretValue and WoW_IsSecretValue(value) then return fallback end
    if type(value) == "string" then return value end
    return fallback
end

local function ReadBoolean(value, fallback)
    if WoW_IsSecretValue and WoW_IsSecretValue(value) then return fallback end
    if type(value) == "boolean" then return value end
    return fallback
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
    local alpha = ReadNumber((frame.GetAlpha and frame:GetAlpha()) or 1, 1)
    if alpha <= 0.01 then
        return false
    end
    local width = ReadNumber(frame.GetWidth and frame:GetWidth(), 0)
    local height = ReadNumber(frame.GetHeight and frame:GetHeight(), 0)
    if width <= 1 or height <= 1 then
        return false
    end
    return true
end

local function GetFrameTopEdge(frame)
    if not frame then return nil end
    local top = ReadNumber(frame.GetTop and frame:GetTop(), nil)
    if type(top) == "number" then
        return top
    end
    local rawCenterY
    if frame.GetCenter then
        local _, cy = frame:GetCenter()
        rawCenterY = cy
    end
    local centerY = ReadNumber(rawCenterY, nil)
    local height = ReadNumber(frame.GetHeight and frame:GetHeight(), nil)
    if type(centerY) == "number" and type(height) == "number" then
        return centerY + (height / 2)
    end
    return nil
end

local function GetTopVisibleResourceBarFrame()
    if QUICore and QUICore.GetResourceBarsProxy then
        local proxy = QUICore:GetResourceBarsProxy()
        if proxy and IsFrameVisiblyShown(proxy) then
            local hasPrimary = QUICore.powerBar and IsFrameVisiblyShown(QUICore.powerBar)
            local hasSecondary = QUICore.secondaryPowerBar and IsFrameVisiblyShown(QUICore.secondaryPowerBar)
            if hasPrimary or hasSecondary then
                return proxy
            end
        end
    end

    local candidates = {}
    if QUICore then
        if QUICore.powerBar then
            table_insert(candidates, QUICore.powerBar)
        end
        if QUICore.secondaryPowerBar then
            table_insert(candidates, QUICore.secondaryPowerBar)
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
    if anchorTo == "screen" then
        return UIParent
    elseif anchorTo == "essential" then
        return GetEssentialViewer()
    elseif anchorTo == "utility" then
        return GetUtilityViewer()
    elseif anchorTo == "primary" then
        if QUICore and QUICore.GetSwapAwareBarFor then
            local f = QUICore:GetSwapAwareBarFor("primary")
            if f then return f end
        end
        return QUICore and QUICore.powerBar
    elseif anchorTo == "secondary" then
        if QUICore and QUICore.GetSwapAwareBarFor then
            local f = QUICore:GetSwapAwareBarFor("secondary")
            if f then return f end
        end
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
        width = (afvs and afvs.iconWidth) or (afvs and afvs.row1Width) or ReadNumber(anchorFrame:GetWidth())
    else
        width = ReadNumber(anchorFrame:GetWidth())
    end

    if type(width) ~= "number" or width <= 1 then
        return nil
    end
    return width
end

local function anchorCacheMatches(cache, anchorTo, placement, anchorFrame, sourcePoint, targetPoint, px, py)
    if cache == nil then return false end
    if cache.anchorTo ~= anchorTo then return false end
    if cache.placement ~= placement then return false end
    if cache.anchorFrame ~= anchorFrame then return false end
    if cache.sourcePoint ~= sourcePoint then return false end
    if cache.targetPoint ~= targetPoint then return false end
    if abs((cache.px or 0) - (px or 0)) > 0.5 then return false end
    if abs((cache.py or 0) - (py or 0)) > 0.5 then return false end
    return true
end

local function writeAnchorCache(viewer, anchorTo, placement, anchorFrame, sourcePoint, targetPoint, px, py)
    viewerBuffState[viewer] = viewerBuffState[viewer] or {}
    viewerBuffState[viewer].anchorCache = {
        anchorTo = anchorTo,
        placement = placement,
        anchorFrame = anchorFrame,
        sourcePoint = sourcePoint,
        targetPoint = targetPoint,
        px = px,
        py = py,
    }
end

local function ApplyTrackedBarAnchor(settings)
    local viewer = GetBuffBarViewer()
    if not viewer then return end
    if _G.QUI_HasFrameAnchor and _G.QUI_HasFrameAnchor("buffBar") then return end
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
        targetPoint = "TOP"
        spacingY = spacing
    elseif placement == "below" then
        targetPoint = "BOTTOM"
        spacingY = -spacing
    elseif placement == "left" then
        targetPoint = "LEFT"
        spacingX = -spacing
    elseif placement == "right" then
        targetPoint = "RIGHT"
        spacingX = spacing
    end

    local orientation = settings.orientation or "horizontal"
    local growUp = settings.growUp ~= false
    if orientation == "vertical" then
        sourcePoint = growUp and "LEFT" or "RIGHT"
    else
        sourcePoint = growUp and "BOTTOM" or "TOP"
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
        anchorFrame = ResolveTrackedBarAnchorFrame(anchorTo)
    end
    if not anchorFrame then return end
    if anchorFrame ~= UIParent and not anchorFrame:IsShown() then return end

    local vbs = viewerBuffState[viewer] or {}

    local ok, px, py
    if Helpers.FrameIsProtected(anchorFrame) or Helpers.FrameIsAnchoringRestricted(anchorFrame) then
        ok, px, py = Helpers.PinFrameToTargetAbsolute(viewer, sourcePoint, anchorFrame, targetPoint, offsetX, offsetY)
        if ok and anchorCacheMatches(vbs.anchorCache, anchorTo, placement, anchorFrame, sourcePoint, targetPoint, px, py) then
            return
        end
    else
        px, py = offsetX, offsetY
        if anchorCacheMatches(vbs.anchorCache, anchorTo, placement, anchorFrame, sourcePoint, targetPoint, px, py) then
            return
        end
        ok = ns.SafeCall("best-effort-style", function()
            viewer:ClearAllPoints()
            viewer:SetPoint(sourcePoint, anchorFrame, targetPoint, offsetX, offsetY)
        end)
    end

    if ok then
        writeAnchorCache(viewer, anchorTo, placement, anchorFrame, sourcePoint, targetPoint, px, py)
    end
end

local function ApplyBuffIconAnchor(settings)
    local viewer = GetBuffIconViewer()
    if not viewer then return end
    if _G.QUI_HasFrameAnchor and _G.QUI_HasFrameAnchor("buffIcon") then return end
    if Helpers.IsEditModeActive() then return end

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
            ns.SafeCall("best-effort-style", function()
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

    local ok, px, py
    if Helpers.FrameIsProtected(anchorFrame) or Helpers.FrameIsAnchoringRestricted(anchorFrame) then
        ok, px, py = Helpers.PinFrameToTargetAbsolute(viewer, sourcePoint, anchorFrame, targetPoint, offsetX, offsetY)
        if ok and anchorCacheMatches(vbs.anchorCache, anchorTo, placement, anchorFrame, sourcePoint, targetPoint, px, py) then
            return
        end
    else
        px, py = offsetX, offsetY
        if anchorCacheMatches(vbs.anchorCache, anchorTo, placement, anchorFrame, sourcePoint, targetPoint, px, py) then
            return
        end
        ok = ns.SafeCall("best-effort-style", function()
            viewer:ClearAllPoints()
            viewer:SetPoint(sourcePoint, anchorFrame, targetPoint, offsetX, offsetY)
        end)
    end

    if ok then
        writeAnchorCache(viewer, anchorTo, placement, anchorFrame, sourcePoint, targetPoint, px, py)
    end
end

local GetDB = Helpers.CreateDBGetter("ncdm")

local function GetBuffSettings()
    local db = GetDB()
    if db and db.buff then
        local buff = db.buff
        if buff.aspectRatioCrop == nil and buff.shape then
            if buff.shape == "rectangle" or buff.shape == "flat" then
                buff.aspectRatioCrop = 1.33
            else
                buff.aspectRatioCrop = 1.0
            end
        end
        return buff
    end
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
        if db.trackedBar.colorOverrides == nil then
            db.trackedBar.colorOverrides = {}
        end
        return db.trackedBar
    end
    return {
        enabled = true,
        barHeight = 25,
        barWidth = 215,
        texture = "Quazii v5",
        useClassColor = true,
        barColor = {0.376, 0.647, 0.980, 1},
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
        orientation = "horizontal",
        fillDirection = "up",
        iconPosition = "top",
        showTextOnVertical = false,
        colorOverrides = {},
    }
end

local function GetTrackedBarSourceViewer()
    return _G["BuffBarCooldownViewer"] or GetBuffBarViewer()
end

local function GetTrackedBarName(frame)
    local region = frame and frame.Name
    if not region or not region.GetText then return nil end
    local okText, rawText = pcall(region.GetText, region)
    if not okText then return nil end
    local text = ReadString(rawText, nil)
    if text == "" then return nil end
    return text
end

local function GetTrackedBarSpellData(frame)
    if not frame then return nil end

    local resolvedSpellID, baseSpellID, overrideSpellID, name
    local cdInfo = frame.cooldownInfo
    if cdInfo then
        overrideSpellID = ReadNumber(cdInfo.overrideSpellID, nil)
        baseSpellID = ReadNumber(cdInfo.spellID, nil)
        name = ReadString(cdInfo.name, nil)
        resolvedSpellID = overrideSpellID or baseSpellID
    end

    if (not resolvedSpellID or not name) and frame.cooldownID then
        local apiInfo = ns.CDMCatalog and ns.CDMCatalog.GetCooldownInfo
            and ns.CDMCatalog.GetCooldownInfo(frame.cooldownID)
        if apiInfo then
            overrideSpellID = overrideSpellID or ReadNumber(apiInfo.overrideSpellID, nil)
            baseSpellID = baseSpellID or ReadNumber(apiInfo.spellID, nil)
            name = name or ReadString(apiInfo.name, nil)
            resolvedSpellID = resolvedSpellID or overrideSpellID or baseSpellID
        end
    end

    if not name then
        name = GetTrackedBarName(frame) or GetTrackedBarName(frame.Bar)
    end

    if not resolvedSpellID and name then
        local spellInfo = Sources and Sources.QuerySpellInfo and Sources.QuerySpellInfo(name)
        if spellInfo and spellInfo.spellID then
            baseSpellID = baseSpellID or spellInfo.spellID
            resolvedSpellID = resolvedSpellID or spellInfo.spellID
        end
    end

    if not name and resolvedSpellID then
        local spellInfo = Sources and Sources.QuerySpellInfo and Sources.QuerySpellInfo(resolvedSpellID)
        if spellInfo and spellInfo.name then
            name = spellInfo.name
        end
    end

    if not resolvedSpellID and not name and not frame.cooldownID then
        return nil
    end

    return {
        spellID = resolvedSpellID,
        baseSpellID = baseSpellID or resolvedSpellID,
        overrideSpellID = overrideSpellID,
        name = name,
        cooldownID = frame.cooldownID,
    }
end

local function GetTrackedBarIconTexture(frame, spellData)
    if not frame then return nil end
    local iconContainer = frame.Icon
    local iconTexture = iconContainer and (iconContainer.Icon or iconContainer.icon or iconContainer.texture)
    if iconTexture and iconTexture.GetTexture then
        local okTex, rawTexture = pcall(iconTexture.GetTexture, iconTexture)
        local texture
        if okTex then texture = rawTexture end
        if WoW_IsSecretValue and WoW_IsSecretValue(texture) then texture = nil end
        if texture and texture ~= 0 and texture ~= "" then
            return texture
        end
    end

    local spellID = spellData and (spellData.overrideSpellID or spellData.spellID or spellData.baseSpellID)
    if spellID then
        local info = Sources and Sources.QuerySpellInfo and Sources.QuerySpellInfo(spellID)
        if info and info.iconID then
            return info.iconID
        end
    end

    return nil
end

local function IsTrackedBarActive(frame)
    if not frame or not frame.IsShown then return false end
    local okShown, shown = pcall(frame.IsShown, frame)
    if not okShown then return false end
    return ReadBoolean(shown, false)
end

local function GetTrackedBarRuntimeEntries()
    local viewer = GetTrackedBarSourceViewer()
    if not viewer then return {} end

    local entries = {}
    local selection = viewer.Selection
    local okN, numChildren = pcall(viewer.GetNumChildren, viewer)
    if not okN or not numChildren or numChildren == 0 then
        return entries
    end

    local children = { viewer:GetChildren() }
    for ci = 1, numChildren do
        local child = children[ci]
        if child and child ~= selection and child.IsObjectType and child:IsObjectType("Frame")
            and child.Bar and child.Bar.IsObjectType and child.Bar:IsObjectType("StatusBar")
            and (child.cooldownID or child.layoutIndex) then
            local spellData = GetTrackedBarSpellData(child)
            if spellData then
                entries[#entries + 1] = {
                    spellID = spellData.spellID,
                    baseSpellID = spellData.baseSpellID,
                    overrideSpellID = spellData.overrideSpellID,
                    name = spellData.name or "",
                    iconTexture = GetTrackedBarIconTexture(child, spellData),
                    cooldownID = spellData.cooldownID,
                    layoutIndex = child.layoutIndex or 9999,
                    isActive = IsTrackedBarActive(child),
                    frame = child,
                }
            end
        end
    end

    table.sort(entries, function(a, b)
        local layoutA = a.layoutIndex or 9999
        local layoutB = b.layoutIndex or 9999
        if layoutA ~= layoutB then
            return layoutA < layoutB
        end
        local nameA = tostring(a.name or "")
        local nameB = tostring(b.name or "")
        if nameA ~= nameB then
            return nameA < nameB
        end
        return (a.spellID or 0) < (b.spellID or 0)
    end)

    return entries
end

local LayoutBuffIcons
local LayoutBuffBars

local isIconLayoutRunning = false
local isBarLayoutRunning = false

local layoutSuppressed = 0

local function IsLayoutSuppressed()
    return layoutSuppressed > 0
end

local trackedBarReadyFrame
local trackedBarReadyQueued = false
local barViewerLayoutHooked = false
local InstallBarViewerLayoutHook

local function IsCooldownViewerReady()
    local catalog = ns.CDMCatalog
    if catalog and catalog.IsCooldownViewerReady then
        return catalog.IsCooldownViewerReady()
    end

    local api = _G.C_CooldownViewer
    if not api then return false end
    if not api.IsCooldownViewerAvailable then return true end
    local ok, ready = pcall(api.IsCooldownViewerAvailable)
    return ok and ready == true
end

local function QueueTrackedBarLayoutWhenReady()
    if trackedBarReadyQueued then return end
    trackedBarReadyQueued = true

    if not CreateFrame then return end
    if not trackedBarReadyFrame then
        trackedBarReadyFrame = CreateFrame("Frame")
    end

    trackedBarReadyFrame:RegisterEvent("COOLDOWN_VIEWER_DATA_LOADED")
    trackedBarReadyFrame:SetScript("OnEvent", function(self)
        self:UnregisterEvent("COOLDOWN_VIEWER_DATA_LOADED")
        self:SetScript("OnEvent", nil)
        trackedBarReadyQueued = false
        local ready = IsCooldownViewerReady()
        if not ready then return end
        if InstallBarViewerLayoutHook then InstallBarViewerLayoutHook() end
        if LayoutBuffBars then LayoutBuffBars() end
    end)
end

InstallBarViewerLayoutHook = function()
    if barViewerLayoutHooked then return end
    if not IsCooldownViewerReady() then
        QueueTrackedBarLayoutWhenReady()
        return
    end

    local blizzBarViewer = _G["BuffBarCooldownViewer"]
    if blizzBarViewer and blizzBarViewer.Layout then
        local function onBarViewerLayout()
            if InCombatLockdown() then return end
            C_Timer.After(0.1, function()
                if isBarLayoutRunning then return end
                LayoutBuffBars()
            end)
        end
        hooksecurefunc(blizzBarViewer, "Layout", function(...) _securecall(onBarViewerLayout, ...) end)
        barViewerLayoutHooked = true
    end
end

local function GetBuffIconFrames()
    local pool = ns.CDMIconFactory and ns.CDMIconFactory:GetIconPool("buff")
    if not pool or #pool == 0 then return {} end

    local inCombat = InCombatLockdown()
    local visible = {}
    for _, icon in ipairs(pool) do
        local shown, alpha
        if inCombat then
            shown = ReadBoolean(icon:IsShown(), false)
            alpha = ReadNumber(icon:GetAlpha(), 1)
        else
            shown = icon:IsShown()
            alpha = icon:GetAlpha()
        end
        if shown and alpha > 0 then
            visible[#visible + 1] = icon
        end
    end

    table.sort(visible, function(a, b)
        local aIdx = (a._spellEntry and a._spellEntry.layoutIndex) or 0
        local bIdx = (b._spellEntry and b._spellEntry.layoutIndex) or 0
        return aIdx < bIdx
    end)

    return visible
end

local function ApplyIconStyle(icon, settings)
    if not icon then return end

    local rowConfig = {
        size = settings.iconSize or 42,
        borderSize = settings.borderSize or 2,
        borderColorSource = settings.borderColorSource,
        borderColor = settings.borderColor or settings.borderColorTable or {0, 0, 0, 1},
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
        showAbsorbAmount = settings.showAbsorbAmount or false,
    }
    if ns.CDMIcons and ns.CDMIcons.OnIconRowConfigApplied then
        ns.CDMIcons.OnIconRowConfigApplied(icon, rowConfig)
    end
    local swipeMod = QUI and QUI.CooldownSwipe
    if swipeMod and swipeMod.ApplyToIcon then
        swipeMod.ApplyToIcon(icon)
    end
    if icon.GetScale and icon:GetScale() ~= 1 then
        icon:SetScale(1)
    end
end

LayoutBuffIcons = function()
    local viewer = GetBuffIconViewer()
    if not viewer then return end
    if isIconLayoutRunning then return end
    if IsLayoutSuppressed() then return end

    isIconLayoutRunning = true

    local settings = GetBuffSettings()
    if not settings.enabled then
        isIconLayoutRunning = false
        return
    end

    ApplyBuffIconAnchor(settings)

    if (not InCombatLockdown()) or inInitSafeWindow then
        local core = GetCore()
        local hudLayering = core and core.db and core.db.profile and core.db.profile.hudLayering
        local layerPriority = hudLayering and hudLayering.buffIcon or 5
        if core and core.GetHUDFrameLevel then
            local frameLevel = core:GetHUDFrameLevel(layerPriority)
            viewer:SetFrameLevel(frameLevel)
        end
    end

    local iconSize = settings.iconSize or 42
    local padding = settings.padding or 0
    local aspectRatio = settings.aspectRatioCrop or 1.0
    local growthDirection = settings.growthDirection or "CENTERED_HORIZONTAL"

    local iconWidth, iconHeight = iconSize, iconSize
    if aspectRatio > 1.0 then
        iconHeight = iconSize / aspectRatio
    elseif aspectRatio < 1.0 then
        iconWidth = iconSize * aspectRatio
    end

    local icons = GetBuffIconFrames()
    local currentCount = #icons

    if currentCount == 0 then
        if not ns._cdmBoot then
            viewer:SetSize(iconWidth, iconHeight)
            if _G.QUI_SetCDMViewerBounds then
                _G.QUI_SetCDMViewerBounds(viewer, iconWidth, iconHeight)
            end
        end
        isIconLayoutRunning = false
        return
    end

    local targetCount = currentCount

    local isVertical = (growthDirection == "UP" or growthDirection == "DOWN")

    local px = QUICore:GetPixelSize()

    local totalWidth, totalHeight
    if isVertical then
        totalWidth = iconWidth
        totalHeight = (targetCount * iconHeight) + ((targetCount - 1) * padding)
        totalHeight = snapPx(totalHeight, px)
    else
        totalWidth = (targetCount * iconWidth) + ((targetCount - 1) * padding)
        totalWidth = snapPx(totalWidth, px)
        totalHeight = iconHeight
    end

    local startX, startY
    if isVertical then
        startX = 0
        if growthDirection == "UP" then
            startY = -(totalHeight / 2) + iconHeight / 2
        else
            startY = (totalHeight / 2) - iconHeight / 2
        end
        startY = snapPx(startY, px)
    else
        startX = -totalWidth / 2 + iconWidth / 2
        startX = snapPx(startX, px)
        startY = 0
    end

    local needsReposition = false
    for i, icon in ipairs(icons) do
        if isVertical then
            local expectedY
            if growthDirection == "UP" then
                expectedY = snapPx(startY + (i - 1) * (iconHeight + padding), px)
            else
                expectedY = snapPx(startY - (i - 1) * (iconHeight + padding), px)
            end
            local point, _, _, xOfs, yOfs = icon:GetPoint(1)
            if not point or point ~= "CENTER" or abs((yOfs or 0) - expectedY) > 2 then
                needsReposition = true
                break
            end
        else
            local expectedX = snapPx(startX + (i - 1) * (iconWidth + padding), px)
            if not PositionMatchesTolerance(icon, expectedX, 2) then
                needsReposition = true
                break
            end
        end
    end

    if needsReposition then
        for _, icon in ipairs(icons) do
            icon:ClearAllPoints()
        end

        for i, icon in ipairs(icons) do
            ApplyIconStyle(icon, settings)
            if isVertical then
                local y
                if growthDirection == "UP" then
                    y = startY + (i - 1) * (iconHeight + padding)
                else
                    y = startY - (i - 1) * (iconHeight + padding)
                end
                icon:SetPoint("CENTER", viewer, "CENTER", 0, snapPx(y, px))
            else
                local x = startX + (i - 1) * (iconWidth + padding)
                icon:SetPoint("CENTER", viewer, "CENTER", snapPx(x, px), snapPx(startY, px))
            end
        end
    else
        for _, icon in ipairs(icons) do
            ApplyIconStyle(icon, settings)
        end
    end

    viewer:SetSize(totalWidth, totalHeight)

    if _G.QUI_SetCDMViewerBounds then
        _G.QUI_SetCDMViewerBounds(viewer, totalWidth, totalHeight)
    end

    if viewer.MarkClean then
        viewer:MarkClean()
    end

    isIconLayoutRunning = false
end

LayoutBuffBars = function()
    local viewer = GetBuffBarViewer()
    if not viewer then return end
    if isBarLayoutRunning then return end

    isBarLayoutRunning = true
    local settings = GetTrackedBarSettings()
    if not IsCooldownViewerReady() then
        QueueTrackedBarLayoutWhenReady()
        isBarLayoutRunning = false
        return
    end
    if not settings.enabled then
        if ns.CDMBlizzardBuffBarSuppressor then
            ns.CDMBlizzardBuffBarSuppressor:Apply(settings)
        end
        isBarLayoutRunning = false
        return
    end

    ApplyTrackedBarAnchor(settings)

    local resolvedBarWidth = settings.barWidth or 215
    local anchorTo = settings.anchorTo or "disabled"
    local placement = settings.anchorPlacement or "center"
    local canAutoWidth = settings.autoWidth and (anchorTo ~= "screen")
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

    local CDMBars = ns.CDMBars
    if CDMBars then
        local runtimeEntries = GetTrackedBarRuntimeEntries()
        CDMBars:Refresh(viewer, settings, resolvedBarWidth, "trackedBar", runtimeEntries)
    end

    if ns.CDMBlizzardBuffBarSuppressor then
        ns.CDMBlizzardBuffBarSuppressor:Apply(settings)
    end

    isBarLayoutRunning = false
end

---@type table<string, any> -- count is numeric; the ICON_STATE_FIELDS keys are not
local lastIconState = { count = -1 }

local ICON_STATE_FIELDS = {
    { "iconSize", 42 },
    { "padding", 0 },
    { "aspectRatioCrop", 1.0 },
    { "borderSize", 2 },
    { "growthDirection", "CENTERED_HORIZONTAL" },
    { "anchorTo", "disabled" },
    { "anchorPlacement", "center" },
    { "anchorSpacing", 0 },
    { "anchorSourcePoint", "CENTER" },
    { "anchorTargetPoint", "CENTER" },
    { "anchorOffsetX", 0 },
    { "anchorOffsetY", 0 },
}

local function InvalidateIconState()
    lastIconState.count = -1
end

local function UpdateIconState(count, settings)
    local changed = lastIconState.count ~= count
    lastIconState.count = count
    for i = 1, #ICON_STATE_FIELDS do
        local field = ICON_STATE_FIELDS[i]
        local key = field[1]
        local value = settings[key]
        if value == nil then value = field[2] end
        if lastIconState[key] ~= value then
            lastIconState[key] = value
            changed = true
        end
    end
    return changed
end

local function CheckIconChanges()
    local viewer = GetBuffIconViewer()
    if not viewer then return end
    if isIconLayoutRunning then return end
    if IsLayoutSuppressed() then return end
    if Helpers.IsEditModeActive() then return end

    local visibleCount = 0
    local inCombat = InCombatLockdown()
    local pool = ns.CDMIconFactory and ns.CDMIconFactory:GetIconPool("buff")
    if pool then
        for _, icon in ipairs(pool) do
            if inCombat then
                if ReadBoolean(icon:IsShown(), false) and ReadNumber(icon:GetAlpha(), 1) > 0 then
                    visibleCount = visibleCount + 1
                end
            else
                if icon:IsShown() and icon:GetAlpha() > 0 then visibleCount = visibleCount + 1 end
            end
        end
    end

    local settings = GetBuffSettings()
    ApplyBuffIconAnchor(settings)

    if not UpdateIconState(visibleCount, settings) then
        return
    end

    LayoutBuffIcons()
end

local buffIconOnUpdateElapsed = 0
local buffIconScanElapsed = 0

local function BuffIconViewer_OnUpdate(self, elapsed)
    buffIconOnUpdateElapsed = buffIconOnUpdateElapsed + elapsed
    buffIconScanElapsed = buffIconScanElapsed + elapsed
    if buffIconOnUpdateElapsed > 0.1 then
        buffIconOnUpdateElapsed = 0
        if self.MarkClean then self:MarkClean() end
    end
    if buffIconScanElapsed > 0.25 then
        buffIconScanElapsed = 0
        if self:IsShown() then
            CheckIconChanges()
        end
    end
end

local initialized = false

local function Initialize()
    if initialized then return end
    initialized = true

    inInitSafeWindow = true
    ns._inInitSafeWindow = true

    local barViewer = GetBuffBarViewer()
    if barViewer then
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

    local iconViewer = GetBuffIconViewer()
    local iconVbs = iconViewer and (viewerBuffState[iconViewer] or {})
    if iconViewer then viewerBuffState[iconViewer] = iconVbs end
    if iconViewer and not iconVbs.onUpdateHooked then
        iconVbs.onUpdateHooked = true
        iconViewer:HookScript("OnUpdate", BuffIconViewer_OnUpdate)
    end

    local lastAuraIconCount = 0
    do
        local iconAuraCoalesce = CreateFrame("Frame")
        iconAuraCoalesce:Hide()
        iconAuraCoalesce:SetScript("OnUpdate", function(self)
            self:Hide()
            local iv2 = GetBuffIconViewer()
            if not iv2 or not iv2:IsShown() then return end
            if isIconLayoutRunning then return end
            if IsLayoutSuppressed() then return end

            if ns._cdmBoot and ns._cdmReanchorHooks then
                ns._cdmReanchorHooks:MarkDirty("buff")
                return
            end

            if InCombatLockdown() then
                local currentCount = 0
                local pool = ns.CDMIconFactory and ns.CDMIconFactory:GetIconPool("buff")
                if pool then
                    for _, icon in ipairs(pool) do
                        if ReadBoolean(icon:IsShown(), false) and ReadNumber(icon:GetAlpha(), 1) > 0 then
                            currentCount = currentCount + 1
                        end
                    end
                end
                if currentCount == lastAuraIconCount then
                    return
                end
                lastAuraIconCount = currentCount
            end

            InvalidateIconState()
            CheckIconChanges()
        end)

        if ns.AuraEvents then
            ns.AuraEvents:Subscribe("player", function(unit, updateInfo)
                local iv = GetBuffIconViewer()
                if iv and iv:IsShown() then
                    iconAuraCoalesce:Show()
                end
            end)
        end
    end

    InstallBarViewerLayoutHook()
    local barAuraCoalesce = CreateFrame("Frame")
    barAuraCoalesce:Hide()
    barAuraCoalesce:SetScript("OnUpdate", function(self)
        self:Hide()
        if isBarLayoutRunning then return end
        LayoutBuffBars()
    end)
    if ns.AuraEvents then
        ns.AuraEvents:Subscribe("player", function(unit, updateInfo)
            local bv = _G["BuffBarCooldownViewer"]
            if bv and bv:IsShown() then
                barAuraCoalesce:Show()
            end
        end)
    end

    LayoutBuffIcons()
    LayoutBuffBars()

    inInitSafeWindow = false
    ns._inInitSafeWindow = false
end

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:SetScript("OnEvent", function(self, event, ...)
    if event == "ADDON_LOADED" then
        local addonName = ...
        if addonName ~= ADDON_NAME then return end
        self:UnregisterEvent("ADDON_LOADED")
        Initialize()
    elseif event == "PLAYER_ENTERING_WORLD" then
        local isInitialLogin, isReloadingUi = ...
        if isInitialLogin or isReloadingUi then
            inInitSafeWindow = true
            ns._inInitSafeWindow = true
            do
                local viewer = GetBuffIconViewer()
                if viewer and viewerBuffState[viewer] then
                    viewerBuffState[viewer].anchorCache = nil
                end
            end
            LayoutBuffIcons()
            LayoutBuffBars()
            inInitSafeWindow = false
            ns._inInitSafeWindow = false

            C_Timer.After(1.5, function()
                local viewer = GetBuffIconViewer()
                if viewer and viewerBuffState[viewer] then
                    viewerBuffState[viewer].anchorCache = nil
                end
                LayoutBuffIcons()
                LayoutBuffBars()
            end)
            C_Timer.After(3.5, function()
                if InCombatLockdown() then return end
                local viewer = GetBuffIconViewer()
                if viewer and viewerBuffState[viewer] then
                    viewerBuffState[viewer].anchorCache = nil
                end
                LayoutBuffIcons()
            end)
        end
    end
end)

local function SetupDebugInstrumentation()
    ns.QUI_PerfRegistry = ns.QUI_PerfRegistry or {}
    ns.QUI_PerfRegistry[#ns.QUI_PerfRegistry + 1] = { name = "CDMBuffLayout", frame = eventFrame }
end
if ns.DebugRegister then
    ns.DebugRegister(SetupDebugInstrumentation)
else
    SetupDebugInstrumentation()
end

function CDMBuffLayout.OnContainerReady()
    if not initialized then
        Initialize()
    else
        local iconViewer = GetBuffIconViewer()
        if iconViewer then
            local iconVbs = viewerBuffState[iconViewer] or {}
            viewerBuffState[iconViewer] = iconVbs
            if not iconVbs.onUpdateHooked then
                iconVbs.onUpdateHooked = true
                iconViewer:HookScript("OnUpdate", BuffIconViewer_OnUpdate)
            end
            if not iconVbs.onShowHooked then
                iconVbs.onShowHooked = true
                iconViewer:HookScript("OnShow", function(self)
                    C_Timer.After(0, function()
                        if InCombatLockdown() then return end
                        if IsLayoutSuppressed() then return end
                        if isIconLayoutRunning then return end
                        LayoutBuffIcons()
                    end)
                end)
            end
            iconVbs.anchorCache = nil

            C_Timer.After(0.3, LayoutBuffIcons)
        end
    end
end

function CDMBuffLayout.OnLayoutReady()
    InvalidateIconState()
    LayoutBuffIcons()
end

C_Timer.After(0, function()
    if GetBuffIconViewer() or GetBuffBarViewer() then
        Initialize()
    end
end)

do
    local core = GetCore()
    if core and core.RegisterEditModeExit then
        core:RegisterEditModeExit(function()
            InvalidateIconState()

            local viewer = GetBuffIconViewer()
            if viewer and viewerBuffState[viewer] then
                viewerBuffState[viewer].anchorCache = nil
            end

            C_Timer.After(0.1, function()
                if InCombatLockdown() then return end
                LayoutBuffIcons()
                LayoutBuffBars()
            end)
        end)
    end
end

CDMBuffLayout.LayoutIcons = LayoutBuffIcons
CDMBuffLayout.LayoutBars = LayoutBuffBars
CDMBuffLayout.Initialize = Initialize
CDMBuffLayout.GetTrackedBarRuntimeEntries = GetTrackedBarRuntimeEntries

function CDMBuffLayout.Refresh()
    InvalidateIconState()

    local barViewer = GetBuffBarViewer()
    if barViewer then
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

_G.QUI_RefreshCDMBuffLayout = CDMBuffLayout.Refresh

if ns.Registry then
    ns.Registry:Register("cdmBuffLayout", {
        refresh = _G.QUI_RefreshCDMBuffLayout,
        priority = 20,
        group = "cooldowns",
        importCategories = { "cdm" },
    })
end
