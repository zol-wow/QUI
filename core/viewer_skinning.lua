---------------------------------------------------------------------------
-- QUI Viewer Skinning & Layout (Classic CDM Engine)
-- Icon skinning, aspect-ratio crop, row-pattern layout, and viewer rescan.
-- Extracted from core/main.lua for maintainability.
-- Only active when the classic CDM engine is selected.
---------------------------------------------------------------------------
local ADDON_NAME, ns = ...
local QUICore = ns.Addon

-- Gate: viewer_skinning is only relevant for the classic engine.
-- At file load time the provider may not have initialized yet, so we
-- defer the check to runtime via a lazy guard in the public functions.
-- The file still loads (WoW loads all XML-referenced Lua unconditionally)
-- but its functions will no-op when the owned engine is active.

---------------------------------------------------------------------------
-- TAINT SAFETY: Weak-keyed tables for per-icon and per-viewer state
-- Previously stored as icon.__cdmSkinned, viewer.__cdmIconCount, etc.
-- which taints Blizzard frames in the Midnight (12.0) taint model.
---------------------------------------------------------------------------
local Helpers = ns.Helpers
local skinIconState, GetSkinIconState     = Helpers.CreateStateTable()
local skinViewerState, GetSkinViewerState = Helpers.CreateStateTable()
local EMPTY = {}

-- Expose skin state for cross-module reads (e.g. main.lua, qol/tooltips.lua)
_G.QUI_GetSkinIconState   = function(icon) return skinIconState[icon] end
_G.QUI_GetSkinViewerState = function(viewer) return skinViewerState[viewer] end

---------------------------------------------------------------------------
-- LOCAL HELPERS
---------------------------------------------------------------------------

local function CreateBorder(frame)
    if frame.border then return frame.border end

    local bord = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    local px = (QUICore and QUICore.GetPixelSize and QUICore:GetPixelSize(bord)) or 1
    bord:SetPoint("TOPLEFT", frame, -px, px)
    bord:SetPoint("BOTTOMRIGHT", frame, px, -px)
    bord:SetBackdrop({
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = px,
    })
    bord:SetBackdropBorderColor(0, 0, 0, 1)

    frame.border = bord
    return bord
end

local function IsCooldownIconFrame(frame)
    return frame and (frame.icon or frame.Icon) and frame.Cooldown
end

local _overlayHooked = setmetatable({}, { __mode = "k" })
local function StripBlizzardOverlay(icon)
    for _, region in ipairs({ icon:GetRegions() }) do
        if region:IsObjectType("Texture") and region.GetAtlas and region:GetAtlas() == "UI-HUD-CoolDownManager-IconOverlay" then
            region:SetTexture("")
            region:Hide()
            if not _overlayHooked[region] then
                _overlayHooked[region] = true
                hooksecurefunc(region, "Show", function(self)
                    if self.IsForbidden and self:IsForbidden() then return end
                    pcall(self.Hide, self)
                end)
            end
        end
    end
end

local function GetIconCountFont(icon)
    if not icon then return nil end

    -- 1. ChargeCount (charges)
    local charge = icon.ChargeCount
    if charge then
        local fs = charge.Current or charge.Text or charge.Count or nil

        if not fs and charge.GetRegions then
            for _, region in ipairs({ charge:GetRegions() }) do
                if region:GetObjectType() == "FontString" then
                    fs = region
                    break
                end
            end
        end

        if fs then
            return fs
        end
    end

    -- 2. Applications (Buff stacks)
    local apps = icon.Applications
    if apps and apps.GetRegions then
        for _, region in ipairs({ apps:GetRegions() }) do
            if region:GetObjectType() == "FontString" then
                return region
            end
        end
    end

    -- 3. Fallback: look for named stack text
    for _, region in ipairs({ icon:GetRegions() }) do
        if region:GetObjectType() == "FontString" then
            local name = region:GetName()
            if name and (name:find("Stack") or name:find("Applications")) then
                return region
            end
        end
    end

    return nil
end

---------------------------------------------------------------------------
-- ICON SKINNING
---------------------------------------------------------------------------

function QUICore:SkinIcon(icon, settings)
    -- Get the icon texture frame (handle both .icon and .Icon for compatibility)
    local iconTexture = icon.icon or icon.Icon
    if not icon or not iconTexture then return end
    if InCombatLockdown() then return false end

    -- Calculate icon dimensions from iconSize and aspectRatio (crop slider)
    local iconSize = settings.iconSize or 40
    local aspectRatioValue = 1.0 -- Default to square

    -- Get aspect ratio from crop slider or convert from string format
    if settings.aspectRatioCrop then
        aspectRatioValue = settings.aspectRatioCrop
    elseif settings.aspectRatio then
        -- Convert "16:9" format to numeric ratio
        local aspectW, aspectH = settings.aspectRatio:match("^(%d+%.?%d*):(%d+%.?%d*)$")
        if aspectW and aspectH then
            aspectRatioValue = tonumber(aspectW) / tonumber(aspectH)
        end
    end

    local iconWidth = iconSize
    local iconHeight = iconSize

    -- Calculate width/height based on aspect ratio value
    -- aspectRatioValue is width:height ratio (e.g., 1.78 for 16:9, 0.56 for 9:16)
    if aspectRatioValue and aspectRatioValue ~= 1.0 then
        if aspectRatioValue > 1.0 then
            -- Wider - width is longest, so width = iconSize
            iconWidth = iconSize
            iconHeight = iconSize / aspectRatioValue
        elseif aspectRatioValue < 1.0 then
            -- Taller - height is longest, so height = iconSize
            iconWidth = iconSize * aspectRatioValue
            iconHeight = iconSize
        end
    end

    local padding   = settings.padding or 5
    local zoom      = settings.zoom or 0
    local border    = (skinIconState[icon] or EMPTY).borderTexture
    local cdPadding = math.floor(padding * 0.7 + 0.5)

    -- This prevents stretching by cropping the texture to match the container aspect ratio
    iconTexture:ClearAllPoints()

    -- Fill the container
    iconTexture:SetPoint("TOPLEFT", icon, "TOPLEFT", padding, -padding)
    iconTexture:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", -padding, padding)

    -- Calculate texture coordinates based on aspect ratio to prevent stretching
    -- Use the same aspectRatioValue calculated above
    local left, right, top, bottom = 0, 1, 0, 1

    if aspectRatioValue and aspectRatioValue ~= 1.0 then
        if aspectRatioValue > 1.0 then
            -- Wider than tall (e.g., 1.78 for 16:9) - crop top/bottom
            local cropAmount = 1.0 - (1.0 / aspectRatioValue)
            local offset = cropAmount / 2.0
            top = offset
            bottom = 1.0 - offset
        elseif aspectRatioValue < 1.0 then
            -- Taller than wide (e.g., 0.56 for 9:16) - crop left/right
            local cropAmount = 1.0 - aspectRatioValue
            local offset = cropAmount / 2.0
            left = offset
            right = 1.0 - offset
        end
    end

    -- Apply zoom on top of aspect ratio crop
    if zoom > 0 then
        local currentWidth = right - left
        local currentHeight = bottom - top
        local visibleSize = 1.0 - (zoom * 2)

        local zoomedWidth = currentWidth * visibleSize
        local zoomedHeight = currentHeight * visibleSize

        local centerX = (left + right) / 2.0
        local centerY = (top + bottom) / 2.0

        left = centerX - (zoomedWidth / 2.0)
        right = centerX + (zoomedWidth / 2.0)
        top = centerY - (zoomedHeight / 2.0)
        bottom = centerY + (zoomedHeight / 2.0)
    end

    -- Apply texture coordinates - this zooms/crops instead of stretching
    iconTexture:SetTexCoord(left, right, top, bottom)

    -- Use SetWidth and SetHeight separately AND SetSize to ensure both dimensions are set independently
    -- Wrap in pcall to handle protected frames gracefully
    local sizeSet = pcall(function()
    icon:SetWidth(iconWidth)
    icon:SetHeight(iconHeight)
    icon:SetSize(iconWidth, iconHeight)
    end)

    -- If size couldn't be set, reset texture coords to avoid visual mismatch
    -- and mark icon as NOT skinned so we retry later
    if not sizeSet then
        iconTexture:SetTexCoord(0, 1, 0, 1)
        GetSkinIconState(icon).skinFailed = true  -- Mark for retry
    else
        GetSkinIconState(icon).skinFailed = nil
    end

    -- Cooldown glow
    if icon.CooldownFlash then
        icon.CooldownFlash:ClearAllPoints()
        icon.CooldownFlash:SetPoint("TOPLEFT", icon, "TOPLEFT", cdPadding, -cdPadding)
        icon.CooldownFlash:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", -cdPadding, cdPadding)
    end

    -- Cooldown swipe
    if icon.Cooldown then
        icon.Cooldown:ClearAllPoints()
        icon.Cooldown:SetPoint("TOPLEFT", icon, "TOPLEFT", cdPadding, -cdPadding)
        icon.Cooldown:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", -cdPadding, cdPadding)
    end

    -- Pandemic icon
    local picon = icon.PandemicIcon or icon.pandemicIcon or icon.Pandemic or icon.pandemic
    if not picon then
        for _, region in ipairs({ icon:GetChildren() }) do
            if region:GetName() and region:GetName():find("Pandemic") then
                picon = region
                break
            end
        end
    end

    if picon and picon.ClearAllPoints then
        picon:ClearAllPoints()
        picon:SetPoint("TOPLEFT", icon, "TOPLEFT", padding, -padding)
        picon:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", -padding, padding)
    end

    -- Out of range highlight
    local oor = icon.OutOfRange or icon.outOfRange or icon.oor
    if oor and oor.ClearAllPoints then
        oor:ClearAllPoints()
        oor:SetPoint("TOPLEFT", icon, "TOPLEFT", padding, -padding)
        oor:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", -padding, padding)
    end

    -- Charge/stack text
    local fs = GetIconCountFont(icon)
    if fs and fs.ClearAllPoints then
        fs:ClearAllPoints()

        local point   = settings.chargeTextAnchor or "BOTTOMRIGHT"
        if point == "MIDDLE" then point = "CENTER" end

        local offsetX = settings.countTextOffsetX or 0
        local offsetY = settings.countTextOffsetY or 0

        fs:SetPoint(point, iconTexture, point, offsetX, offsetY)

        local desiredSize = settings.countTextSize
        if desiredSize and desiredSize > 0 then
            local font, _, flags = fs:GetFont()
            fs:SetFont(font, desiredSize, flags or "OUTLINE")
        end
    end

    -- Duration text (cooldown countdown) - find and style the cooldown text
    local cooldown = icon.cooldown or icon.Cooldown
    if cooldown then
        -- Try to find the cooldown's text region
        local durationSize = settings.durationTextSize
        if durationSize and durationSize > 0 then
            -- Method 1: Check for OmniCC text
            if cooldown.text then
                local font, _, flags = cooldown.text:GetFont()
                if font then
                    cooldown.text:SetFont(font, durationSize, flags or "OUTLINE")
                end
            end

            -- Method 2: Check for Blizzard's built-in cooldown text (GetRegions)
            for _, region in pairs({cooldown:GetRegions()}) do
                if region:GetObjectType() == "FontString" then
                    local font, _, flags = region:GetFont()
                    if font then
                        region:SetFont(font, durationSize, flags or "OUTLINE")
                    end
                end
            end
        end
    end

    -- Strip Blizzard overlay
    StripBlizzardOverlay(icon)

    -- NOTE: OnCooldownIDCleared workaround removed — replacing the function
    -- directly on the Blizzard frame taints the icon's execution context,
    -- causing isActive to become a secret value tainted by QUI and crashing
    -- Blizzard_CooldownViewer SetIsActive comparisons.  The EnableSpellRangeCheck
    -- nil-spell error it suppressed is a harmless Blizzard bug (cosmetic error log).

    -- Border (using BACKGROUND texture to avoid secret value errors during combat)
    -- BackdropTemplate causes "arithmetic on secret value" crashes when frame is resized during combat
    if icon.IsForbidden and icon:IsForbidden() then
        GetSkinIconState(icon).skinned = true
        return
    end

    local edgeSize = tonumber(settings.borderSize) or 1

    if edgeSize > 0 then
        if not border then
            border = icon:CreateTexture(nil, "BACKGROUND", nil, -8)
            GetSkinIconState(icon).borderTexture = border
        end

        local r, g, b, a = unpack(settings.borderColor or { 0, 0, 0, 1 })
        border:SetColorTexture(r, g, b, a or 1)
        border:ClearAllPoints()
        border:SetPoint("TOPLEFT", iconTexture, "TOPLEFT", -edgeSize, edgeSize)
        border:SetPoint("BOTTOMRIGHT", iconTexture, "BOTTOMRIGHT", edgeSize, -edgeSize)
        border:Show()
    else
        if border then
            border:Hide()
        end
    end

    -- Only mark as fully skinned if size was successfully set
    local iState = GetSkinIconState(icon)
    if not iState.skinFailed then
    iState.skinned = true
    end
    iState.skinPending = nil  -- Clear pending flag
end

function QUICore:SkinAllIconsInViewer(viewer)
    if not viewer or not viewer.GetName then return end

    local name     = viewer:GetName()
    local settings = self.db.profile.viewers[name]
    if not settings or not settings.enabled then return end

    local container = viewer.viewerFrame or viewer
    local children  = { container:GetChildren() }

    for _, icon in ipairs(children) do
        if IsCooldownIconFrame(icon) and (icon.icon or icon.Icon) then
            local ok, err = pcall(self.SkinIcon, self, icon, settings)
            if not ok then
                GetSkinIconState(icon).skinError = true
                print("|cffff4444[QUICore] SkinIcon error for", name, "icon:", err, "|r")
            end
        end
    end
end

---------------------------------------------------------------------------
-- VIEWER LAYOUT
---------------------------------------------------------------------------

-- Helper: Build row pattern array from settings
local function BuildRowPattern(settings, viewerName)
    local pattern = {}

    if viewerName == "EssentialCooldownViewer" then
        -- Essential has 3 rows
        if (settings.row1Icons or 0) > 0 then table.insert(pattern, settings.row1Icons) end
        if (settings.row2Icons or 0) > 0 then table.insert(pattern, settings.row2Icons) end
        if (settings.row3Icons or 0) > 0 then table.insert(pattern, settings.row3Icons) end
    elseif viewerName == "UtilityCooldownViewer" then
        -- Utility has 2 rows
        if (settings.row1Icons or 0) > 0 then table.insert(pattern, settings.row1Icons) end
        if (settings.row2Icons or 0) > 0 then table.insert(pattern, settings.row2Icons) end
    end

    -- If all rows are 0 or pattern is empty, default to unlimited single row
    if #pattern == 0 then
        return nil
    end

    return pattern
end

-- Helper: Compute grid from icons and pattern
local function ComputeGrid(icons, pattern)
    local grid = {}
    local idx = 1

    for _, rowSize in ipairs(pattern) do
        if rowSize > 0 then
            local row = {}
            for i = 1, rowSize do
                if idx <= #icons then
                    row[#row + 1] = icons[idx]
                    idx = idx + 1
                end
            end
            if #row > 0 then
                grid[#grid + 1] = row
            end
        end
    end

    -- If there are remaining icons beyond the pattern, add them to extra rows
    -- using the last row's size as the template
    local lastRowSize = pattern[#pattern] or 6
    while idx <= #icons do
        local row = {}
        for i = 1, lastRowSize do
            if idx <= #icons then
                row[#row + 1] = icons[idx]
                idx = idx + 1
            end
        end
        if #row > 0 then
            grid[#grid + 1] = row
        end
    end

    return grid
end

-- Helper: Calculate max row width for centering
local function MaxRowWidth(grid, iconWidth, spacing)
    local maxW = 0
    for _, row in ipairs(grid) do
        local rowW = (#row * iconWidth) + ((#row - 1) * spacing)
        if rowW > maxW then
            maxW = rowW
        end
    end
    return maxW
end

function QUICore:ApplyViewerLayout(viewer)
    if not viewer or not viewer.GetName then return end
    if InCombatLockdown() then return end
    local name     = viewer:GetName()
    local settings = self.db.profile.viewers[name]
    if not settings or not settings.enabled then return end

    local container = viewer.viewerFrame or viewer
    local icons = {}

    for _, child in ipairs({ container:GetChildren() }) do
        if IsCooldownIconFrame(child) and child:IsShown() then
            table.insert(icons, child)
        end
    end

    local count = #icons
    if count == 0 then return end

    -- Sort icons by layoutIndex or frame ID
    table.sort(icons, function(a, b)
        local la = a.layoutIndex or a:GetID() or 0
        local lb = b.layoutIndex or b:GetID() or 0
        return la < lb
    end)

    -- Calculate icon dimensions from iconSize and aspectRatio (crop slider)
    local iconSize = settings.iconSize or 32
    local aspectRatioValue = 1.0 -- Default to square

    -- Get aspect ratio from crop slider or convert from string format
    if settings.aspectRatioCrop then
        aspectRatioValue = settings.aspectRatioCrop
    elseif settings.aspectRatio then
        -- Convert "16:9" format to numeric ratio
        local aspectW, aspectH = settings.aspectRatio:match("^(%d+%.?%d*):(%d+%.?%d*)$")
        if aspectW and aspectH then
            aspectRatioValue = tonumber(aspectW) / tonumber(aspectH)
        end
    end

    local iconWidth = iconSize
    local iconHeight = iconSize

    -- Calculate width/height based on aspect ratio value
    if aspectRatioValue and aspectRatioValue ~= 1.0 then
        if aspectRatioValue > 1.0 then
            -- Wider - width is longest, so width = iconSize
            iconWidth = iconSize
            iconHeight = iconSize / aspectRatioValue
        elseif aspectRatioValue < 1.0 then
            -- Taller - height is longest, so height = iconSize
            iconWidth = iconSize * aspectRatioValue
            iconHeight = iconSize
        end
    end

    local spacing    = settings.spacing or 4
    local rowLimit   = settings.rowLimit or 0

    -- Apply icon sizes
    for _, icon in ipairs(icons) do
        icon:ClearAllPoints()
        icon:SetWidth(iconWidth)
        icon:SetHeight(iconHeight)
        icon:SetSize(iconWidth, iconHeight)
    end

    -- Check if we should use row pattern (for Essential/Utility only)
    local useRowPattern = settings.useRowPattern
    local rowPattern = nil

    if useRowPattern and (name == "EssentialCooldownViewer" or name == "UtilityCooldownViewer") then
        rowPattern = BuildRowPattern(settings, name)
    end

    -- Calculate Y offset if Utility is anchored to Essential
    local yOffset = 0
    if name == "UtilityCooldownViewer" and settings.anchorToEssential then
        local essentialViewer = _G.QUI_GetCDMViewerFrame and _G.QUI_GetCDMViewerFrame("essential")
        local essVS = _G.QUI_GetCDMViewerState and _G.QUI_GetCDMViewerState(essentialViewer)
        if essentialViewer and essVS and essVS.totalHeight then
            local anchorGap = settings.anchorGap or 10
            -- Offset by Essential's total height plus gap
            yOffset = -(essVS.totalHeight + anchorGap)
        end
    end

    -- Use row pattern layout if enabled and valid
    if rowPattern and #rowPattern > 0 then
        local grid = ComputeGrid(icons, rowPattern)
        local maxW = MaxRowWidth(grid, iconWidth, spacing)
        local alignment = settings.rowAlignment or "CENTER"
        local rowSpacing = iconHeight + spacing

        -- Update viewer state dimensions for anchoring/resource bars
        local totalH = (#grid * iconHeight) + ((#grid - 1) * spacing)
        if _G.QUI_SetCDMViewerBounds then _G.QUI_SetCDMViewerBounds(viewer, maxW, totalH) end

        local y = yOffset
        for rowIdx, row in ipairs(grid) do
            local rowW = (#row * iconWidth) + ((#row - 1) * spacing)

            -- Calculate starting X based on alignment
            local startX
            if alignment == "LEFT" then
                startX = -maxW / 2 + iconWidth / 2
            elseif alignment == "RIGHT" then
                startX = maxW / 2 - rowW + iconWidth / 2
            else -- CENTER
                startX = -rowW / 2 + iconWidth / 2
            end

            -- Position icons in this row
            for idx, icon in ipairs(row) do
                local x = startX + (idx - 1) * (iconWidth + spacing)
                icon:SetPoint("CENTER", container, "CENTER", x, y)
            end

            -- Move down for next row
            y = y - rowSpacing
        end

    -- Legacy rowLimit behavior (for backwards compatibility)
    elseif rowLimit <= 0 then
        -- Single row (original behavior)
        local totalWidth = count * iconWidth + (count - 1) * spacing
        if _G.QUI_SetCDMViewerBounds then _G.QUI_SetCDMViewerBounds(viewer, totalWidth, iconHeight) end

        local startX = -totalWidth / 2 + iconWidth / 2

        for i, icon in ipairs(icons) do
            local x = startX + (i - 1) * (iconWidth + spacing)
            icon:SetPoint("CENTER", container, "CENTER", x, yOffset)
        end
    else
        -- Multi-row layout with centered horizontal growth (legacy rowLimit)
        local numRows = math.ceil(count / rowLimit)
        local rowSpacing = iconHeight + spacing

        local maxRowWidth = 0
        for row = 1, numRows do
            local rowStart = (row - 1) * rowLimit + 1
            local rowEnd = math.min(row * rowLimit, count)
            local rowCount = rowEnd - rowStart + 1
            if rowCount > 0 then
                local rowWidth = rowCount * iconWidth + (rowCount - 1) * spacing
                if rowWidth > maxRowWidth then
                    maxRowWidth = rowWidth
                end
            end
        end

        local totalH3 = (numRows * iconHeight) + ((numRows - 1) * spacing)
        if _G.QUI_SetCDMViewerBounds then _G.QUI_SetCDMViewerBounds(viewer, maxRowWidth, totalH3) end

        local growDirection = "down"

        for i, icon in ipairs(icons) do
            local row = math.ceil(i / rowLimit)
            local rowStart = (row - 1) * rowLimit + 1
            local rowEnd = math.min(row * rowLimit, count)
            local rowCount = rowEnd - rowStart + 1
            local positionInRow = i - rowStart + 1

            local rowWidth = rowCount * iconWidth + (rowCount - 1) * spacing
            local startX = -rowWidth / 2 + iconWidth / 2
            local x = startX + (positionInRow - 1) * (iconWidth + spacing)

            local y
            if growDirection == "up" then
                y = yOffset + (row - 1) * rowSpacing
            else
                y = yOffset - (row - 1) * rowSpacing
            end

            icon:SetPoint("CENTER", container, "CENTER", x, y)
        end
    end
end

---------------------------------------------------------------------------
-- VIEWER RESCAN & APPLY
---------------------------------------------------------------------------

function QUICore:RescanViewer(viewer)
    if not viewer or not viewer.GetName then return end
    local name     = viewer:GetName()
    local settings = self.db.profile.viewers[name]
    if not settings or not settings.enabled then return end

    local container = viewer.viewerFrame or viewer
    local icons = {}
    local changed = false
    local inCombat = InCombatLockdown()

    for _, child in ipairs({ container:GetChildren() }) do
        if IsCooldownIconFrame(child) and child:IsShown() then
            table.insert(icons, child)

            -- Retry skinning if it failed before or hasn't been done
            local childIS = skinIconState[child] or EMPTY
            if not childIS.skinned or childIS.skinFailed then
                -- Mark as pending to avoid multiple attempts
                if not childIS.skinPending then
                    GetSkinIconState(child).skinPending = true

                    if inCombat then
                        -- Defer skinning until out of combat
                        if not self.__cdmPendingIcons then
                            self.__cdmPendingIcons = {}
                        end
                        self.__cdmPendingIcons[child] = { icon = child, settings = settings, viewer = viewer }

                        -- Ensure we have an event frame for combat end
                        if not self.__cdmIconSkinEventFrame then
                            local eventFrame = CreateFrame("Frame")
                            eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
                            eventFrame:SetScript("OnEvent", function(self)
                                self:UnregisterEvent("PLAYER_REGEN_ENABLED")
                                QUICore:ProcessPendingIcons()
                            end)
                            self.__cdmIconSkinEventFrame = eventFrame
                        end
                        self.__cdmIconSkinEventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
                    else
                        -- Not in combat, try to skin immediately
                        local success = pcall(self.SkinIcon, self, child, settings)
                        if success then
                            GetSkinIconState(child).skinPending = nil
                        end
                    end
                    changed = true
                end
            end
        end
    end

    local count = #icons

    -- Check if icon count changed
    if count ~= (skinViewerState[viewer] or EMPTY).iconCount then
        GetSkinViewerState(viewer).iconCount = count
        changed = true
    end

    if changed then
        -- Re-apply layout when the viewer's icon set changes
        self:ApplyViewerLayout(viewer)

        -- Keep resource bars in sync with the viewer width immediately
        if self.UpdatePowerBar then
            self:UpdatePowerBar()
        end
        if self.UpdateSecondaryPowerBar then
            self:UpdateSecondaryPowerBar()
        end
    end
end

function QUICore:ApplyViewerSkin(viewer)
    if not viewer or not viewer.GetName then return end
    local name     = viewer:GetName()
    local settings = self.db.profile.viewers[name]
    if not settings or not settings.enabled then return end

    -- Apply layout first to set container sizes, then skin to handle textures
    self:ApplyViewerLayout(viewer)
    self:SkinAllIconsInViewer(viewer)
    self:UpdatePowerBar()
    self:UpdateSecondaryPowerBar()

    -- Try to process any pending icons if not in combat
    if not InCombatLockdown() then
        self:ProcessPendingIcons()
    end
end

function QUICore:ProcessPendingIcons()
    if not self.__cdmPendingIcons then return end
    if InCombatLockdown() then return end

    local processed = {}
    for icon, data in pairs(self.__cdmPendingIcons) do
        if icon and icon:IsShown() and not (skinIconState[icon] or EMPTY).skinned then
            local success = pcall(self.SkinIcon, self, icon, data.settings)
            if success then
                GetSkinIconState(icon).skinPending = nil
                processed[icon] = true
            end
        elseif not icon or not icon:IsShown() then
            -- Icon no longer exists or is hidden, remove from pending
            processed[icon] = true
        end
    end

    -- Remove processed icons from pending list
    for icon in pairs(processed) do
        self.__cdmPendingIcons[icon] = nil
    end

    -- If no more pending icons, clear the table
    if not next(self.__cdmPendingIcons) then
        self.__cdmPendingIcons = nil
    end
end

---------------------------------------------------------------------------
-- FORCE REFRESH / RESKIN
---------------------------------------------------------------------------

function QUICore:ForceRefreshBuffIcons()
    local viewer = _G.QUI_GetCDMViewerFrame and _G.QUI_GetCDMViewerFrame("buffIcon")
    if viewer and viewer:IsShown() then
        GetSkinViewerState(viewer).iconCount = nil
        self:RescanViewer(viewer)
        -- Process any pending icons if not in combat
        if not InCombatLockdown() then
            self:ProcessPendingIcons()
        end
    end
end

-- Force re-skin all icons in all viewers (used when Edit Mode changes)
function QUICore:ForceReskinAllViewers()
    for _, name in ipairs(self.viewers) do
        local viewer = _G[name]
        if viewer then
            local container = viewer.viewerFrame or viewer
            local children = { container:GetChildren() }
            for _, child in ipairs(children) do
                -- Clear skinned flag to force re-skinning
                local cState = skinIconState[child]
                if cState then
                    cState.skinned = nil
                    cState.skinPending = nil
                    cState.skinFailed = nil
                end
            end
            -- Reset icon count to force layout refresh
            GetSkinViewerState(viewer).iconCount = nil

            -- Note: We avoid calling viewer.Layout() directly as it can trigger
            -- Blizzard's internal code that accesses "secret" values and errors
        end
    end

    -- Trigger immediate rescan of all viewers
    for _, name in ipairs(self.viewers) do
        local viewer = _G[name]
        if viewer and viewer:IsShown() then
            self:RescanViewer(viewer)
            -- Also force apply viewer skin which does layout + skinning
            self:ApplyViewerSkin(viewer)
        end
    end
end
