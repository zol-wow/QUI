--[[
    QUI CDM Containers + Layout Engine (Owned Engine)

    All three trackers (Essential/Utility/Buff) use addon-owned containers
    with addon-owned icon frames created by the CDMIcons factory.
    Blizzard viewers are hidden (alpha=0). Only Blizzard CooldownFrames
    are adopted onto addon-owned icons for taint-safe rendering.

    Visibility is handled by hud_visibility.lua (loads before engines).
    Initialization is driven by cdm_provider.lua calling Initialize().
]]

local ADDON_NAME, ns = ...
local Helpers = ns.Helpers
local QUICore = ns.Addon
local UIKit = ns.UIKit
local LSM = LibStub("LibSharedMedia-3.0")

---------------------------------------------------------------------------
-- CONSTANTS
---------------------------------------------------------------------------
local HUD_MIN_WIDTH_DEFAULT = Helpers.HUD_MIN_WIDTH_DEFAULT or 200
local ROW_GAP = 5

-- Aspect ratio migration
local function MigrateRowAspect(rowData)
    if rowData and rowData.aspectRatioCrop == nil and rowData.shape then
        if rowData.shape == "rectangle" or rowData.shape == "flat" then
            rowData.aspectRatioCrop = 1.33
        else
            rowData.aspectRatioCrop = 1.0
        end
    end
    return rowData.aspectRatioCrop or 1.0
end

---------------------------------------------------------------------------
-- STATE
---------------------------------------------------------------------------
local containers = {}  -- { essential = frame, utility = frame, buff = frame }
local viewerState = {} -- keyed by container frame
local applying = {}    -- re-entry guard per tracker
local initialized = false

-- Anchor proxy for Utility below Essential
local UtilityAnchorProxy = nil

---------------------------------------------------------------------------
-- DB ACCESS
---------------------------------------------------------------------------
local GetDB = Helpers.CreateDBGetter("ncdm")

local function GetTrackerSettings(trackerKey)
    local db = GetDB()
    return db and db[trackerKey] or nil
end

local function IsHUDAnchoredToCDM()
    local profile = QUICore and QUICore.db and QUICore.db.profile
    if Helpers and Helpers.IsHUDAnchoredToCDM then
        return Helpers.IsHUDAnchoredToCDM(profile)
    end
    return false
end

local function GetHUDMinWidth()
    local profile = QUICore and QUICore.db and QUICore.db.profile
    if Helpers and Helpers.GetHUDMinWidthSettingsFromProfile then
        return Helpers.GetHUDMinWidthSettingsFromProfile(profile)
    end
    return false, HUD_MIN_WIDTH_DEFAULT
end

---------------------------------------------------------------------------
-- HELPER: Update locked power bars and castbars
---------------------------------------------------------------------------
local function UpdateLockedBarsForViewer(trackerKey)
    if trackerKey == "essential" then
        if _G.QUI_UpdateLockedPowerBar then _G.QUI_UpdateLockedPowerBar() end
        if _G.QUI_UpdateLockedSecondaryPowerBar then _G.QUI_UpdateLockedSecondaryPowerBar() end
        if _G.QUI_UpdateLockedCastbarToEssential then _G.QUI_UpdateLockedCastbarToEssential() end
    elseif trackerKey == "utility" then
        if _G.QUI_UpdateLockedPowerBarToUtility then _G.QUI_UpdateLockedPowerBarToUtility() end
        if _G.QUI_UpdateLockedSecondaryPowerBarToUtility then _G.QUI_UpdateLockedSecondaryPowerBarToUtility() end
        if _G.QUI_UpdateLockedCastbarToUtility then _G.QUI_UpdateLockedCastbarToUtility() end
    end
end

local function UpdateAllLockedBars()
    UpdateLockedBarsForViewer("essential")
    UpdateLockedBarsForViewer("utility")
end

---------------------------------------------------------------------------
-- HELPER: Get total icon capacity from row settings
---------------------------------------------------------------------------
local function GetTotalIconCapacity(settings)
    local total = 0
    for i = 1, 3 do
        local rowKey = "row" .. i
        if settings[rowKey] and settings[rowKey].iconCount then
            total = total + settings[rowKey].iconCount
        end
    end
    return total
end

---------------------------------------------------------------------------
-- UTILITY ANCHOR PROXY
---------------------------------------------------------------------------
local function GetUtilityAnchorProxy()
    if not UtilityAnchorProxy then
        UtilityAnchorProxy = UIKit.CreateAnchorProxy(nil, {
            mirrorVisibility = false,
            sizeResolver = function(source)
                local vs = viewerState[source]
                local width = (vs and vs.cdmIconWidth) or source:GetWidth() or 0
                local height = (vs and vs.cdmTotalHeight) or source:GetHeight() or 0
                return width, height
            end,
        })
    end
    return UtilityAnchorProxy
end

local function UpdateUtilityAnchorProxy()
    local proxy = GetUtilityAnchorProxy()
    local essContainer = containers.essential
    if not essContainer then
        return proxy
    end
    proxy:SetSourceFrame(essContainer)
    proxy:Sync()
    return proxy
end

---------------------------------------------------------------------------
-- CONTAINER CREATION
---------------------------------------------------------------------------
local function CreateContainer(name)
    local frame = CreateFrame("Frame", name, UIParent)
    frame:SetSize(1, 1)
    frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    frame:Show()
    viewerState[frame] = {}
    return frame
end

local function InitContainers()
    if containers.essential then return end -- already created

    containers.essential = CreateContainer("QUI_EssentialContainer")
    containers.utility   = CreateContainer("QUI_UtilityContainer")
    containers.buff      = CreateContainer("QUI_BuffContainer")
    _G["QUI_BuffIconContainer"] = containers.buff

    -- Migrate position from Blizzard viewers (one-time)
    local function MigratePosition(container, blizzViewerName)
        local viewer = _G[blizzViewerName]
        if not viewer then return end
        local cx, cy = viewer:GetCenter()
        local sx, sy = UIParent:GetCenter()
        if cx and cy and sx and sy then
            local ox = cx - sx
            local oy = cy - sy
            container:ClearAllPoints()
            container:SetPoint("CENTER", UIParent, "CENTER", ox, oy)
        end
    end

    MigratePosition(containers.essential, "EssentialCooldownViewer")
    MigratePosition(containers.utility, "UtilityCooldownViewer")
    MigratePosition(containers.buff, "BuffIconCooldownViewer")
end

-- Deferred init for buff container (viewer may load after us)
-- The addon-owned QUI_BuffContainer is created in InitContainers().
-- This function ensures it exists and notifies buffbar.lua.
local function InitBuffContainer()
    if not containers.buff then
        -- InitContainers hasn't run yet -- create the container now
        containers.buff = CreateContainer("QUI_BuffContainer")
        _G["QUI_BuffIconContainer"] = containers.buff
    end
    if ns.InvalidateCDMFrameCache then ns.InvalidateCDMFrameCache() end
    -- Notify buffbar.lua to set up hooks on the new container
    if _G.QUI_OnBuffContainerReady then
        C_Timer.After(0.1, _G.QUI_OnBuffContainerReady)
    end
end

---------------------------------------------------------------------------
-- CORE: Layout icons in a container
-- Ported from cdm_viewer.lua:1069-1554 with taint safety removed.
---------------------------------------------------------------------------
local function LayoutContainer(trackerKey)
    local container = containers[trackerKey]
    if not container then return end

    -- Never layout during Edit Mode
    if Helpers.IsEditModeActive() then return end

    -- Never rebuild during combat — Blizzard CooldownFrames adopted onto our
    -- icons are updated natively.  Rebuilding mid-combat destroys the working
    -- layout (ClearPool) and may produce wrong positions.
    -- A full rebuild fires on PLAYER_REGEN_ENABLED via _G.QUI_RefreshNCDM.
    if InCombatLockdown() then return end

    local settings = GetTrackerSettings(trackerKey)
    if not settings or not settings.enabled then
        container:Hide()
        return
    end

    -- Re-entry guard
    if applying[trackerKey] then return end
    applying[trackerKey] = true

    container:Show()

    -- Apply HUD layer priority
    local hudLayering = QUICore and QUICore.db and QUICore.db.profile and QUICore.db.profile.hudLayering
    local layerPriority = hudLayering and hudLayering[trackerKey] or 5
    if QUICore and QUICore.GetHUDFrameLevel then
        local frameLevel = QUICore:GetHUDFrameLevel(layerPriority)
        container:SetFrameLevel(frameLevel)
    end

    local vs = viewerState[container]
    if not vs then
        viewerState[container] = {}
        vs = viewerState[container]
    end

    -- Check for vertical layout mode
    local layoutDirection = settings.layoutDirection or "HORIZONTAL"
    local isVertical = (layoutDirection == "VERTICAL")
    vs.cdmLayoutDirection = layoutDirection

    -- Buff tracker: create addon-owned icons via icon factory, adopt
    -- Blizzard CooldownFrames for taint-safe aura display.
    -- Blizzard's children stay in the hidden viewer (alpha=0).
    -- buffbar.lua handles positioning and styling of addon-owned icons.
    if trackerKey == "buff" then
        InitBuffContainer()
        container = containers.buff
        if not container then
            applying[trackerKey] = false
            return
        end

        -- Fingerprint: skip rebuild when the same buff spellIDs are active.
        -- Aura events fire on stack/duration changes too, but the icon set
        -- only changes when buffs are gained or lost.
        local spellData = ns.CDMSpellData and ns.CDMSpellData:GetSpellList("buff") or {}
        local parts = {}
        for i, entry in ipairs(spellData) do
            parts[i] = tostring(entry.spellID or 0)
        end
        local fingerprint = table.concat(parts, ",")

        local currentPool = ns.CDMIcons:GetIconPool("buff")
        if fingerprint == (containers._buffFingerprint or "") and #currentPool > 0 then
            -- Same buff set -- skip destructive rebuild
            applying[trackerKey] = false
            return
        end
        containers._buffFingerprint = fingerprint

        -- Build addon-owned icons (adopts Blizzard CooldownFrames)
        local allIcons = ns.CDMIcons:BuildIcons("buff", container)
        for _, icon in ipairs(allIcons) do
            icon:Show()
        end

        applying[trackerKey] = false

        -- Notify buffbar.lua to position + style icons immediately
        -- (no delay -- icons are parented and visible, ready for layout)
        if _G.QUI_OnBuffLayoutReady then
            _G.QUI_OnBuffLayoutReady()
        end
        return
    end

    -- Build icons via the icon factory (essential/utility only)
    local allIcons = ns.CDMIcons:BuildIcons(trackerKey, container)
    local totalCapacity = GetTotalIconCapacity(settings)


    -- Select icons to layout (up to capacity)
    local iconsToLayout = {}
    for i = 1, math.min(#allIcons, totalCapacity) do
        iconsToLayout[i] = allIcons[i]
        allIcons[i]:Show()
    end

    -- Hide overflow icons
    for i = totalCapacity + 1, #allIcons do
        if allIcons[i] then
            allIcons[i]:Hide()
            allIcons[i]:ClearAllPoints()
        end
    end

    if #iconsToLayout == 0 then
        applying[trackerKey] = false
        return
    end

    -- Build row config
    local rows = {}
    for i = 1, 3 do
        local rowKey = "row" .. i
        if settings[rowKey] and settings[rowKey].iconCount and settings[rowKey].iconCount > 0 then
            MigrateRowAspect(settings[rowKey])
            rows[#rows + 1] = {
                count = settings[rowKey].iconCount,
                size = settings[rowKey].iconSize or 50,
                borderSize = settings[rowKey].borderSize or 2,
                borderColorTable = settings[rowKey].borderColorTable or {0, 0, 0, 1},
                aspectRatioCrop = settings[rowKey].aspectRatioCrop or 1.0,
                zoom = settings[rowKey].zoom or 0,
                padding = settings[rowKey].padding or 0,
                yOffset = settings[rowKey].yOffset or 0,
                xOffset = settings[rowKey].xOffset or 0,
                durationSize = settings[rowKey].durationSize or 14,
                durationOffsetX = settings[rowKey].durationOffsetX or 0,
                durationOffsetY = settings[rowKey].durationOffsetY or 0,
                durationTextColor = settings[rowKey].durationTextColor or {1, 1, 1, 1},
                durationAnchor = settings[rowKey].durationAnchor or "CENTER",
                stackSize = settings[rowKey].stackSize or 14,
                stackOffsetX = settings[rowKey].stackOffsetX or 0,
                stackOffsetY = settings[rowKey].stackOffsetY or 0,
                stackTextColor = settings[rowKey].stackTextColor or {1, 1, 1, 1},
                stackAnchor = settings[rowKey].stackAnchor or "BOTTOMRIGHT",
                opacity = settings[rowKey].opacity or 1.0,
            }
        end
    end

    if #rows == 0 then
        applying[trackerKey] = false
        return
    end

    -- Calculate potential row widths (for power bars / castbars)
    local potentialRow1Width = 0
    local potentialBottomRowWidth = 0
    if rows[1] then
        potentialRow1Width = (rows[1].count * rows[1].size) + ((rows[1].count - 1) * (rows[1].padding or 0))
    end
    if rows[#rows] then
        potentialBottomRowWidth = (rows[#rows].count * rows[#rows].size) + ((rows[#rows].count - 1) * (rows[#rows].padding or 0))
    end

    -- Calculate row/column dimensions
    local iconIndex = 1
    local maxRowWidth = 0
    local maxColHeight = 0
    local rowWidths = {}
    local colHeights = {}
    local tempIndex = 1

    for rowNum, rowConfig in ipairs(rows) do
        local iconsInRow = math.min(rowConfig.count, #iconsToLayout - tempIndex + 1)
        if iconsInRow <= 0 then break end

        local iconWidth = rowConfig.size
        local aspectRatio = rowConfig.aspectRatioCrop or 1.0
        local iconHeight = rowConfig.size / aspectRatio

        if isVertical then
            local colHeight = (iconsInRow * iconHeight) + ((iconsInRow - 1) * rowConfig.padding)
            colHeights[rowNum] = colHeight
            rowWidths[rowNum] = iconWidth
            if colHeight > maxColHeight then maxColHeight = colHeight end
        else
            local rowWidth = (iconsInRow * iconWidth) + ((iconsInRow - 1) * rowConfig.padding)
            rowWidths[rowNum] = rowWidth
            if rowWidth > maxRowWidth then maxRowWidth = rowWidth end
        end
        tempIndex = tempIndex + iconsInRow
    end

    -- Calculate total width/height for CENTER-based positioning
    local totalHeight = 0
    local totalWidth = 0
    local rowHeights = {}
    local numRowsUsed = 0
    local tempIdx = 1

    for rowNum, rowConfig in ipairs(rows) do
        local iconsInRow = math.min(rowConfig.count, #iconsToLayout - tempIdx + 1)
        if iconsInRow <= 0 then break end

        local aspectRatio = rowConfig.aspectRatioCrop or 1.0
        local iconHeight = rowConfig.size / aspectRatio
        local iconWidth = rowConfig.size
        rowHeights[rowNum] = iconHeight
        numRowsUsed = numRowsUsed + 1

        if isVertical then
            totalWidth = totalWidth + iconWidth
            if numRowsUsed > 1 then totalWidth = totalWidth + ROW_GAP end
        else
            totalHeight = totalHeight + iconHeight
            if numRowsUsed > 1 then totalHeight = totalHeight + ROW_GAP end
        end
        tempIdx = tempIdx + iconsInRow
    end

    if isVertical then
        totalHeight = maxColHeight
        maxRowWidth = totalWidth
    end

    -- Compute yOffset-adjusted envelope for proxy sizing
    local baseTotalHeight = totalHeight
    local proxyTotalHeight = totalHeight
    vs.cdmProxyYOffset = 0
    if not isVertical and numRowsUsed > 0 then
        local pos = baseTotalHeight / 2
        local actualTop = pos
        local actualBot = -baseTotalHeight / 2
        local tmpIdx = 1
        for _, rc in ipairs(rows) do
            local n = math.min(rc.count, #iconsToLayout - tmpIdx + 1)
            if n <= 0 then break end
            local ih = rc.size / (rc.aspectRatioCrop or 1.0)
            local yOff = rc.yOffset or 0
            actualTop = math.max(actualTop, pos + yOff)
            actualBot = math.min(actualBot, pos - ih + yOff)
            pos = pos - ih - ROW_GAP
            tmpIdx = tmpIdx + n
        end
        proxyTotalHeight = actualTop - actualBot
        vs.cdmProxyYOffset = (actualTop + actualBot) / 2
    end

    -- HUD min-width floor
    local minWidthEnabled, minWidth = GetHUDMinWidth()
    local applyHUDMinWidth = minWidthEnabled and IsHUDAnchoredToCDM()
    if applyHUDMinWidth then
        maxRowWidth = math.max(maxRowWidth, minWidth)
        potentialRow1Width = math.max(potentialRow1Width, minWidth)
        potentialBottomRowWidth = math.max(potentialBottomRowWidth, minWidth)
    end

    -- Position icons using CENTER-based anchoring
    local currentY = baseTotalHeight / 2
    local currentX = -totalWidth / 2

    for rowNum, rowConfig in ipairs(rows) do
        local rowIcons = {}
        local iconsInRow = 0

        for _ = 1, rowConfig.count do
            if iconIndex <= #iconsToLayout then
                rowIcons[#rowIcons + 1] = iconsToLayout[iconIndex]
                iconIndex = iconIndex + 1
                iconsInRow = iconsInRow + 1
            end
        end

        if iconsInRow == 0 then break end

        local aspectRatio = rowConfig.aspectRatioCrop or 1.0
        local iconWidth = rowConfig.size
        local iconHeight = rowConfig.size / aspectRatio
        local rowWidth = rowWidths[rowNum] or (iconsInRow * iconWidth) + ((iconsInRow - 1) * rowConfig.padding)
        local colHeight = colHeights[rowNum] or (iconsInRow * iconHeight) + ((iconsInRow - 1) * rowConfig.padding)

        for i, icon in ipairs(rowIcons) do
            local x, y

            if isVertical then
                local colCenterX = currentX + (iconWidth / 2)
                local colStartY = baseTotalHeight / 2 - iconHeight / 2
                y = colStartY - ((i - 1) * (iconHeight + rowConfig.padding)) + rowConfig.yOffset
                x = colCenterX + (rowConfig.xOffset or 0)
            else
                local rowCenterY = currentY - (iconHeight / 2) + rowConfig.yOffset
                local rowStartX = -rowWidth / 2 + iconWidth / 2
                x = rowStartX + ((i - 1) * (iconWidth + rowConfig.padding)) + (rowConfig.xOffset or 0)
                y = rowCenterY
            end

            -- Configure icon appearance (size, border, zoom, text)
            ns.CDMIcons.ConfigureIcon(icon, rowConfig)

            -- Reset scale (if somehow changed)
            if icon.GetScale and icon:GetScale() ~= 1 then
                icon:SetScale(1)
            end

            -- Pixel-snap position
            if QUICore and QUICore.PixelRound then
                x = QUICore:PixelRound(x, container)
                y = QUICore:PixelRound(y, container)
            end
            icon:ClearAllPoints()
            icon:SetPoint("CENTER", container, "CENTER", x, y)
            icon:Show()

            -- Update cooldown state
            ns.CDMIcons.UpdateIconCooldown(icon)
        end

        if isVertical then
            currentX = currentX + iconWidth + ROW_GAP
        else
            currentY = currentY - iconHeight - ROW_GAP
        end
    end

    -- Store dimensions in viewer state
    vs.cdmIconWidth = maxRowWidth
    vs.cdmTotalHeight = proxyTotalHeight

    -- Persist for next reload
    local ncdm = QUICore and QUICore.db and QUICore.db.profile and QUICore.db.profile.ncdm
    if ncdm and maxRowWidth > 0 then
        if trackerKey == "essential" then
            ncdm._lastEssentialWidth = maxRowWidth
            ncdm._lastEssentialHeight = proxyTotalHeight
        elseif trackerKey == "utility" then
            ncdm._lastUtilityWidth = maxRowWidth
            ncdm._lastUtilityHeight = proxyTotalHeight
        end
    end

    -- Row-specific dimensions
    vs.cdmRow1IconHeight = rows[1] and (rows[1].size / (rows[1].aspectRatioCrop or 1.0)) or 0
    vs.cdmRow1BorderSize = rows[1] and rows[1].borderSize or 0
    vs.cdmBottomRowBorderSize = rows[#rows] and rows[#rows].borderSize or 0
    vs.cdmBottomRowYOffset = rows[#rows] and rows[#rows].yOffset or 0

    if isVertical then
        vs.cdmRow1Width = maxRowWidth
        vs.cdmBottomRowWidth = maxRowWidth
        vs.cdmPotentialRow1Width = maxRowWidth
        vs.cdmPotentialBottomRowWidth = maxRowWidth
    else
        local row1Width = rowWidths[1] or maxRowWidth
        local bottomRowWidth = rowWidths[#rows] or maxRowWidth
        if applyHUDMinWidth then
            row1Width = math.max(row1Width, minWidth)
            bottomRowWidth = math.max(bottomRowWidth, minWidth)
        end
        vs.cdmRow1Width = row1Width
        vs.cdmBottomRowWidth = bottomRowWidth
        vs.cdmPotentialRow1Width = potentialRow1Width
        vs.cdmPotentialBottomRowWidth = potentialBottomRowWidth
    end

    -- Size the container to match content bounds
    if maxRowWidth > 0 and proxyTotalHeight > 0 then
        container:SetSize(maxRowWidth, proxyTotalHeight)
    end

    -- Update proxy frames
    if _G.QUI_UpdateCDMAnchorProxyFrames then
        _G.QUI_UpdateCDMAnchorProxyFrames()
    end

    applying[trackerKey] = false

    -- Trigger Utility anchor after Essential layout
    if trackerKey == "essential" then
        local db = GetDB()
        if db and db.utility and db.utility.anchorBelowEssential then
            C_Timer.After(0.05, function()
                if _G.QUI_ApplyUtilityAnchor then
                    _G.QUI_ApplyUtilityAnchor()
                end
            end)
        end
    end

    -- Update dependent systems (debounced)
    if not vs.cdmUpdatePending then
        vs.cdmUpdatePending = true
        C_Timer.After(0.05, function()
            vs.cdmUpdatePending = nil
            UpdateLockedBarsForViewer(trackerKey)
            if _G.QUI_UpdateCDMAnchoredUnitFrames then
                _G.QUI_UpdateCDMAnchoredUnitFrames()
            end
            if _G.QUI_UpdateViewerKeybinds then
                local containerName = container:GetName()
                _G.QUI_UpdateViewerKeybinds(containerName)
            end
        end)
    end
end

---------------------------------------------------------------------------
-- REFRESH ALL
---------------------------------------------------------------------------
local function RefreshAll()
    if not initialized then return end

    -- Defer to combat end — rebuilding destroys the current layout.
    -- The classic engine's combatFrame calls _G.QUI_RefreshNCDM on
    -- PLAYER_REGEN_ENABLED, which routes here and provides recovery.
    if InCombatLockdown() then return end

    if ns.CDMSpellData then
        ns.CDMSpellData:UpdateCVar()
    end

    applying["essential"] = false
    applying["utility"] = false
    applying["buff"] = false

    -- Reset buff fingerprint so the rebuild goes through
    if containers then containers._buffFingerprint = nil end

    C_Timer.After(0.01, function()
        LayoutContainer("essential")
    end)
    C_Timer.After(0.02, function()
        LayoutContainer("utility")
        if _G.QUI_ApplyUtilityAnchor then
            _G.QUI_ApplyUtilityAnchor()
        end
    end)
    C_Timer.After(0.03, function()
        LayoutContainer("buff")
    end)

    -- Update locked bars and refresh swipe/glow after all layouts complete
    C_Timer.After(0.10, function()
        UpdateAllLockedBars()
        if _G.QUI_UpdateCDMAnchoredUnitFrames then
            _G.QUI_UpdateCDMAnchoredUnitFrames()
        end
        if _G.QUI_RefreshCDMMouseover then
            _G.QUI_RefreshCDMMouseover()
        end
        -- Apply swipe settings and glow state to newly created/rebuilt icons
        if _G.QUI_RefreshCooldownSwipe then
            _G.QUI_RefreshCooldownSwipe()
        end
        if _G.QUI_RefreshCustomGlows then
            _G.QUI_RefreshCustomGlows()
        end
    end)
end

---------------------------------------------------------------------------
-- UTILITY ANCHOR: Position Utility container below Essential
---------------------------------------------------------------------------
local function ApplyUtilityAnchor()
    local db = GetDB()
    if not db or not db.utility then return end

    local utilSettings = db.utility
    local utilContainer = containers.utility
    if not utilContainer then return end

    -- Respect centralized frame anchoring overrides
    if _G.QUI_IsFrameOverridden and _G.QUI_IsFrameOverridden(utilContainer) then
        return
    end

    if not utilSettings.anchorBelowEssential then
        return
    end

    local essContainer = containers.essential
    if not essContainer then return end

    local utilityTopBorder = utilSettings.row1 and utilSettings.row1.borderSize or 0
    local totalOffset = (utilSettings.anchorGap or 0) - utilityTopBorder

    local anchorParent = UpdateUtilityAnchorProxy() or essContainer

    local ok = pcall(function()
        utilContainer:ClearAllPoints()
        utilContainer:SetPoint("TOP", anchorParent, "BOTTOM", 0, -totalOffset)
    end)

    if not ok then
        -- Fallback: center on screen
        utilContainer:ClearAllPoints()
        utilContainer:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
        utilSettings.anchorBelowEssential = false
        print("|cff34D399QUI:|r Anchor Utility below Essential failed (circular dependency). Setting has been disabled.")
    end
end

---------------------------------------------------------------------------
-- VIEWER STATE API (backward compatible with old cdm_viewer.lua API)
---------------------------------------------------------------------------
local _stateSnapshots = setmetatable({}, { __mode = "k" })

local function GetViewerState(viewer)
    if not viewer then return nil end
    local vs = viewerState[viewer]
    if not vs or not vs.cdmIconWidth then return nil end
    local snap = _stateSnapshots[viewer]
    if not snap then
        snap = {}
        _stateSnapshots[viewer] = snap
    end
    snap.iconWidth              = vs.cdmIconWidth
    snap.totalHeight            = vs.cdmTotalHeight
    snap.row1Width              = vs.cdmRow1Width
    snap.bottomRowWidth         = vs.cdmBottomRowWidth
    snap.potentialRow1Width     = vs.cdmPotentialRow1Width
    snap.potentialBottomRowWidth = vs.cdmPotentialBottomRowWidth
    snap.row1IconHeight         = vs.cdmRow1IconHeight
    snap.row1BorderSize         = vs.cdmRow1BorderSize
    snap.bottomRowBorderSize    = vs.cdmBottomRowBorderSize
    snap.bottomRowYOffset       = vs.cdmBottomRowYOffset
    snap.layoutDir              = vs.cdmLayoutDirection
    snap.proxyYOffset           = vs.cdmProxyYOffset or 0
    return snap
end

local function SetViewerBounds(viewer, boundsW, boundsH)
    if not viewer then return end
    local vs = viewerState[viewer]
    if not vs then
        viewerState[viewer] = {}
        vs = viewerState[viewer]
    end
    vs.cdmIconWidth = boundsW
    vs.cdmRow1Width = boundsW
    vs.cdmBottomRowWidth = boundsW
    vs.cdmPotentialRow1Width = boundsW
    vs.cdmPotentialBottomRowWidth = boundsW
    vs.cdmTotalHeight = boundsH
end

local function RefreshViewerFromBounds(viewer, trackerKey)
    if not viewer then return end
    if _G.QUI_UpdateCDMAnchorProxyFrames then
        _G.QUI_UpdateCDMAnchorProxyFrames()
    end
    UpdateLockedBarsForViewer(trackerKey)
    if _G.QUI_UpdateAnchoredUnitFrames then
        _G.QUI_UpdateAnchoredUnitFrames()
    end
    local proxyKey = trackerKey == "essential" and "cdmEssential" or "cdmUtility"
    if _G.QUI_UpdateFramesAnchoredTo then
        _G.QUI_UpdateFramesAnchoredTo(proxyKey)
    end
end

-- Callback for spell data changes (essential/utility)
_G.QUI_OnSpellDataChanged = function()
    if initialized then
        RefreshAll()
    end
end

-- Callback for buff aura events (from hooks on Blizzard buff children).
-- Runs LayoutContainer to reparent children, then notifies buffbar.
_G.QUI_OnBuffDataChanged = function()
    if initialized and not applying["buff"] then
        LayoutContainer("buff")
    end
end

-- Callback for buffbar.lua to style and position reparented children.
-- Fired by LayoutContainer("buff") after reparent completes.
_G.QUI_OnBuffLayoutReady = _G.QUI_OnBuffLayoutReady or function() end

---------------------------------------------------------------------------
-- EDIT MODE INTEGRATION
-- On enter: release addon-owned buff icons (restoring CooldownFrames),
--           hide owned containers, show Blizzard viewers at containers' positions.
-- On exit: read new position from Blizzard viewers, restore owned
--          containers, rebuild addon-owned icons via RefreshAll.
---------------------------------------------------------------------------
_G.QUI_OnEditModeEnterCDM = function()
    -- Position Blizzard viewers at owned containers' positions
    local function SyncBlizzardToContainer(viewerType, blizzViewerName)
        local container = containers[viewerType]
        local viewer = _G[blizzViewerName]
        if not container or not viewer then return end

        local cx, cy = container:GetCenter()
        local sx, sy = UIParent:GetCenter()
        if cx and cy and sx and sy then
            local ox = cx - sx
            local oy = cy - sy
            pcall(function()
                viewer:ClearAllPoints()
                viewer:SetPoint("CENTER", UIParent, "CENTER", ox, oy)
            end)
        end

        -- Size the Blizzard viewer to match the QUI container so .Selection
        -- covers the full content area during Edit Mode.
        local cw = container:GetWidth()
        local ch = container:GetHeight()
        if cw and ch and cw > 1 and ch > 1 then
            pcall(function() viewer:SetSize(cw, ch) end)
        end
    end

    SyncBlizzardToContainer("essential", "EssentialCooldownViewer")
    SyncBlizzardToContainer("utility", "UtilityCooldownViewer")
    SyncBlizzardToContainer("buff", "BuffIconCooldownViewer")

    -- Release addon-owned buff icons (restores Blizzard CooldownFrames to viewer)
    if ns.CDMIcons then
        ns.CDMIcons:ClearPool("buff")
    end
    -- Reset fingerprint so icons rebuild on Edit Mode exit
    if containers then containers._buffFingerprint = nil end

    -- Hide all owned containers
    for _, cont in pairs(containers) do
        cont:Hide()
    end
end

_G.QUI_OnEditModeExitCDM = function()
    -- Read new position from Blizzard viewers and apply to owned containers
    local function SyncContainerToBlizzard(viewerType, blizzViewerName)
        local container = containers[viewerType]
        local viewer = _G[blizzViewerName]
        if not container or not viewer then return end

        local cx, cy = viewer:GetCenter()
        local sx, sy = UIParent:GetCenter()
        if cx and cy and sx and sy then
            local ox = cx - sx
            local oy = cy - sy
            container:ClearAllPoints()
            container:SetPoint("CENTER", UIParent, "CENTER", ox, oy)
        end
    end

    SyncContainerToBlizzard("essential", "EssentialCooldownViewer")
    SyncContainerToBlizzard("utility", "UtilityCooldownViewer")
    SyncContainerToBlizzard("buff", "BuffIconCooldownViewer")

    -- Show all owned containers
    for _, cont in pairs(containers) do
        cont:Show()
    end

    -- Refresh layout (rebuilds addon-owned icons for all trackers)
    RefreshAll()
end

---------------------------------------------------------------------------
-- NCDM COMPATIBILITY TABLE
-- Provides a Refresh() and LayoutViewer() interface matching the classic
-- engine's NCDM object for backward-compatible consumer access.
---------------------------------------------------------------------------
local NCDM = {
    initialized = false,
}

NCDM.Refresh = RefreshAll
NCDM.LayoutViewer = function(name, key)
    LayoutContainer(key or name)
end

---------------------------------------------------------------------------
-- ENGINE TABLE (provider contract)
---------------------------------------------------------------------------
local ownedEngine = {}

-- Viewer key → container key mapping
local VIEWER_KEY_MAP = {
    essential = "essential",
    utility   = "utility",
    buffIcon  = "buff",
    buffBar   = nil,  -- owned engine doesn't manage BuffBar
}

-- Blizzard frame fallback for pre-container resolution and unmanaged viewers
local BLIZZARD_FALLBACKS = {
    essential = "EssentialCooldownViewer",
    utility   = "UtilityCooldownViewer",
    buffIcon  = "BuffIconCooldownViewer",
    buffBar   = "BuffBarCooldownViewer",
}

---------------------------------------------------------------------------
-- Initialize: called by cdm_provider.lua after engine selection
---------------------------------------------------------------------------
function ownedEngine:Initialize()
    -- Wire owned engine's deferred exports (glows, swipe)
    -- These are deferred to avoid overwriting classic engine's exports at file load time.
    if ns._OwnedGlows then
        QUI.CustomGlows = ns._OwnedGlows
        _G.QUI_RefreshCustomGlows = ns._OwnedGlows.RefreshAllGlows
        _G.QUI_GetGlowState = ns._OwnedGlows.GetGlowState
        -- No-op effects refresh (owned engine has no effects.lua)
        _G.QUI_RefreshCooldownEffects = function() end
    end
    if ns._OwnedSwipe then
        QUI.CooldownSwipe = ns._OwnedSwipe
        _G.QUI_RefreshCooldownSwipe = ns._OwnedSwipe.Apply
    end

    -- Bootstrap spell data harvesting
    if ns.CDMSpellData then
        ns.CDMSpellData:Initialize()
    end

    -- Create addon-owned containers (1.0s delay ensures Blizzard viewers are fully loaded)
    C_Timer.After(1.0, function()
        InitContainers()
        InitBuffContainer()

        -- Start the CDMIcons update ticker
        if ns.CDMIcons then
            ns.CDMIcons:StartUpdateTicker()
        end

        initialized = true
        NCDM.initialized = true

        -- Invalidate visibility frame cache so hud_visibility picks up new containers
        if ns.InvalidateCDMFrameCache then
            ns.InvalidateCDMFrameCache()
        end

        RefreshAll()
    end)

    -- Register runtime events (spec change, zone change, cinematics, addon loads)
    local eventFrame = CreateFrame("Frame")
    eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    eventFrame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
    eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
    eventFrame:RegisterEvent("CHALLENGE_MODE_START")
    eventFrame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
    eventFrame:RegisterEvent("CINEMATIC_STOP")
    eventFrame:RegisterEvent("STOP_MOVIE")
    eventFrame:RegisterEvent("ADDON_LOADED")

    eventFrame:SetScript("OnEvent", function(self, event, arg1, arg2)
        if event == "PLAYER_REGEN_ENABLED" then
            -- Combat end: full rebuild to pick up any spell data changes
            -- that were deferred while LayoutContainer was combat-gated.
            C_Timer.After(0.1, function()
                if not InCombatLockdown() then
                    RefreshAll()
                end
            end)
            return
        elseif event == "ADDON_LOADED" and arg1 == "Blizzard_CooldownManager" then
            -- Viewer just loaded -- grab it as buff container
            InitBuffContainer()
            if initialized then
                if ns.InvalidateCDMFrameCache then ns.InvalidateCDMFrameCache() end
                RefreshAll()
            end
        elseif event == "PLAYER_ENTERING_WORLD" then
            local isLogin, isReload = arg1, arg2
            if not isLogin and not isReload then
                C_Timer.After(0.3, RefreshAll)
            end
        elseif event == "PLAYER_SPECIALIZATION_CHANGED" then
            C_Timer.After(0.5, RefreshAll)
        elseif event == "CHALLENGE_MODE_START" then
            C_Timer.After(0.5, RefreshAll)
        elseif event == "ZONE_CHANGED_NEW_AREA" then
            C_Timer.After(0.3, RefreshAll)
        elseif event == "CINEMATIC_STOP" or event == "STOP_MOVIE" then
            -- After cinematics, refresh everything and invalidate frame cache
            C_Timer.After(0.3, function()
                if ns.InvalidateCDMFrameCache then ns.InvalidateCDMFrameCache() end
                RefreshAll()
                if _G.QUI_RefreshCDMVisibility then
                    _G.QUI_RefreshCDMVisibility()
                end
                if _G.QUI_RefreshUnitframesVisibility then
                    _G.QUI_RefreshUnitframesVisibility()
                end
            end)
        end
    end)
end

function ownedEngine:Refresh()
    RefreshAll()
end

function ownedEngine:GetViewerFrame(key)
    local containerKey = VIEWER_KEY_MAP[key]
    if containerKey then
        local container = containers[containerKey]
        if container then return container end
    end
    -- Fall back to Blizzard frame (before containers exist or for unmanaged viewers)
    local blizzName = BLIZZARD_FALLBACKS[key]
    return blizzName and _G[blizzName] or nil
end

function ownedEngine:GetViewerFrames()
    local frames = {}
    if containers.essential then frames[#frames + 1] = containers.essential end
    if containers.utility then frames[#frames + 1] = containers.utility end
    if containers.buff then frames[#frames + 1] = containers.buff end
    -- BuffBar remains Blizzard-managed; include it if it exists
    if _G.BuffBarCooldownViewer then
        frames[#frames + 1] = _G.BuffBarCooldownViewer
    end
    return frames
end

function ownedEngine:GetViewerState(viewer)
    return GetViewerState(viewer)
end

function ownedEngine:SetViewerBounds(viewer, boundsW, boundsH)
    SetViewerBounds(viewer, boundsW, boundsH)
end

function ownedEngine:RefreshViewerFromBounds(viewer, trackerKey)
    RefreshViewerFromBounds(viewer, trackerKey)
end

function ownedEngine:GetIconState(icon)
    -- Owned icons are addon-created; state is on the icon itself (no external table)
    if not icon then return nil end
    return icon._spellEntry and icon or nil
end

function ownedEngine:ClearIconState(icon)
    -- No external state table for owned icons; release handled by CDMIcons
    if not icon then return end
    if ns.CDMIcons then
        ns.CDMIcons:ReleaseIcon(icon)
    end
end

function ownedEngine:IsHUDAnchoredToCDM()
    return IsHUDAnchoredToCDM()
end

function ownedEngine:GetHUDMinWidthSettings()
    return GetHUDMinWidth()
end

function ownedEngine:ApplyUtilityAnchor()
    ApplyUtilityAnchor()
end

function ownedEngine:IsSelectionKeepVisible(sel)
    -- Owned frames don't use Blizzard's .Selection overlay
    return false
end

function ownedEngine:GetNCDM()
    return NCDM
end

function ownedEngine:GetCustomCDM()
    -- CustomCDM is defined in cdm_icons.lua; access via CDMIcons module
    return ns.CDMIcons and ns.CDMIcons.CustomCDM or nil
end

function ownedEngine:LayoutViewer(name, key)
    LayoutContainer(key or name)
end

---------------------------------------------------------------------------
-- REGISTER ENGINE
---------------------------------------------------------------------------
if ns.CDMProvider then
    ns.CDMProvider:RegisterEngine("owned", ownedEngine)
end

---------------------------------------------------------------------------
-- NAMESPACE EXPORT
---------------------------------------------------------------------------
ns.CDMContainers = {
    GetContainer = function(viewerType) return containers[viewerType] end,
    LayoutContainer = LayoutContainer,
    RefreshAll = RefreshAll,
}

