local ADDON_NAME, ns = ...

local SettingsBuilders = {}
ns.SettingsBuilders = SettingsBuilders

local surfaceSeq = 0
local providerSurfaces = {}
local pendingProviderRefresh = {}

local function GetGUI()
    return _G.QUI and _G.QUI.GUI
end

local function NextSurfaceId(prefix)
    surfaceSeq = surfaceSeq + 1
    return string.format("%s:%d", prefix or "provider", surfaceSeq)
end

local function ShowProviderUnavailable(parent, message)
    if not parent then return 80 end

    local GUI = GetGUI()
    local label
    if GUI and GUI.CreateLabel then
        label = GUI:CreateLabel(parent, message or "Settings are still initializing.", 11, GUI.Colors and GUI.Colors.textMuted)
    else
        label = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        label:SetText(message or "Settings are still initializing.")
        label:SetTextColor(0.65, 0.65, 0.65, 1)
    end

    label:SetPoint("TOPLEFT", 0, -8)
    label:SetPoint("RIGHT", parent, "RIGHT", 0, 0)
    if label.SetJustifyH then
        label:SetJustifyH("LEFT")
    end
    if parent.SetHeight then
        parent:SetHeight(80)
    end
    return 80
end

local function GetProvider(providerKey)
    local Settings = ns.Settings
    local providers = Settings and (Settings.Providers or Settings.ProviderRegistry)
    if not providers or type(providers.Get) ~= "function" then
        return nil
    end
    return providers:Get(providerKey)
end

local function IsSurfaceVisible(frame)
    if not frame or type(frame.IsVisible) ~= "function" then
        return false
    end

    local okVisible, isVisible = pcall(frame.IsVisible, frame)
    if not okVisible or not isVisible then
        return false
    end

    local GUI = GetGUI()
    local mainFrame = GUI and GUI.MainFrame
    if mainFrame and mainFrame ~= frame and type(mainFrame.IsVisible) == "function" then
        local okMainVisible, mainVisible = pcall(mainFrame.IsVisible, mainFrame)
        if not okMainVisible or not mainVisible then
            return false
        end
    end

    return true
end

local function ClearHost(parent)
    if not parent then return end

    local GUI = GetGUI()
    if GUI and GUI.CleanupWidgetTree then
        GUI:CleanupWidgetTree(parent)
    end

    for _, child in ipairs({parent:GetChildren()}) do
        child:Hide()
        child:SetParent(nil)
    end

    for _, region in ipairs({parent:GetRegions()}) do
        if region.Hide then
            region:Hide()
        end
    end

    if parent.SetHeight then
        parent:SetHeight(1)
    end
end

function SettingsBuilders.RegisterProviderSurface(providerKey, surfaceId, refreshFn, isVisibleFn)
    if not providerKey or not surfaceId or type(refreshFn) ~= "function" then return end
    providerSurfaces[surfaceId] = {
        providerKey = providerKey,
        refreshFn = refreshFn,
        isVisibleFn = isVisibleFn,
    }
end

function SettingsBuilders.UnregisterProviderSurface(surfaceId)
    if not surfaceId then return end
    providerSurfaces[surfaceId] = nil
end

local function FlushProviderRefresh(providerKey)
    local pending = pendingProviderRefresh[providerKey]
    pendingProviderRefresh[providerKey] = nil
    if not pending then return end

    for surfaceId, surface in pairs(providerSurfaces) do
        if surface.providerKey == providerKey and (pending.structural or not pending.skipSurfaceIds[surfaceId]) then
            local isVisible = true
            if surface.isVisibleFn then
                local okVisible, visible = pcall(surface.isVisibleFn)
                isVisible = okVisible and visible ~= false
            end
            if isVisible then
                pcall(surface.refreshFn, {
                    providerKey = providerKey,
                    structural = pending.structural == true,
                })
            end
        end
    end
end

function SettingsBuilders.NotifyProviderChanged(providerKey, opts)
    if not providerKey then return end
    opts = opts or {}

    local pending = pendingProviderRefresh[providerKey]
    if not pending then
        pending = {
            structural = false,
            skipSurfaceIds = {},
        }
        pendingProviderRefresh[providerKey] = pending
        C_Timer.After(0.05, function()
            FlushProviderRefresh(providerKey)
        end)
    end

    if opts.structural then
        pending.structural = true
    end
    if opts.sourceSurfaceId then
        pending.skipSurfaceIds[opts.sourceSurfaceId] = true
    end
end

local function ErrorHandler(err)
    local message = tostring(err)
    if type(_G.debugstack) == "function" then
        message = message .. "\n" .. _G.debugstack(2, 20, 20)
    end
    return message
end

local function WithSuppressedPosition(includePosition, fn)
    local U = ns.QUI_LayoutMode_Utils
    local original = U and U.BuildPositionCollapsible

    if U and includePosition == false then
        U.BuildPositionCollapsible = function() end
    end

    local ok, result = xpcall(fn, ErrorHandler)

    if U and original then
        U.BuildPositionCollapsible = original
    end

    if not ok then
        geterrorhandler()(result)
        return nil
    end

    return result
end

-- Inverse of WithSuppressedPosition. Suppresses every Utils.CreateCollapsible
-- call inside fn EXCEPT when that call originates from BuildPositionCollapsible
-- (which wraps its anchoring widgets in a "Position" card). The
-- BuildOpenFullSettingsLink helper builds its own row and is unaffected.
--
-- Result: Layout Mode drawer renders only Position + "Open full settings →".
local function WithOnlyPosition(fn)
    local U = ns.QUI_LayoutMode_Utils
    if not U or not U.CreateCollapsible or not U.BuildPositionCollapsible then
        return xpcall(fn, ErrorHandler)
    end

    local originalCreate = U.CreateCollapsible
    local originalBuildPosition = U.BuildPositionCollapsible
    local insidePosition = false

    U.CreateCollapsible = function(...)
        if insidePosition then
            return originalCreate(...)
        end
        -- Suppress: skip buildFunc, do not insert into sections, return nil.
        return nil
    end

    U.BuildPositionCollapsible = function(...)
        local prev = insidePosition
        insidePosition = true
        local ok, err = xpcall(originalBuildPosition, ErrorHandler, ...)
        insidePosition = prev
        if not ok then geterrorhandler()(err) end
    end

    local ok, result = xpcall(fn, ErrorHandler)

    U.CreateCollapsible = originalCreate
    U.BuildPositionCollapsible = originalBuildPosition

    if not ok then
        geterrorhandler()(result)
        return nil
    end

    return result
end

-- Dual-column post-layout. The provider builders anchor widgets via
-- Helpers.PlaceRow (TOPLEFT at (0, sy), RIGHT to body RIGHT → full width).
-- After CreateCollapsible returns, we walk the body's direct children and
-- direct FontString help text in creation order, pair controls into card rows,
-- and re-anchor each pair LEFT-half / RIGHT-half with a center divider +
-- alternating row bg. Text regions stay full-width rows so helper copy keeps
-- its place in the flow. Mirrors the element-tab dual-column rendering in
-- layoutmode_composer.lua so every tile tab looks the same.
---------------------------------------------------------------------------
local CARD_ROW_HEIGHT = 32

local function GetDualColumnRowHeight(widget)
    if not widget then return CARD_ROW_HEIGHT end
    local customHeight = widget._quiDualColumnRowHeight
    if type(customHeight) == "number" and customHeight > 0 then
        return customHeight
    end

    local widgetHeight = widget.GetHeight and widget:GetHeight() or nil
    if type(widgetHeight) == "number" and widgetHeight > 0 then
        return math.max(CARD_ROW_HEIGHT, math.ceil(widgetHeight))
    end

    return CARD_ROW_HEIGHT
end

local function ApplyDualColumnLayout(section)
    if not section or not section._body then return end
    local body = section._body
    if section._quiSkipDualColumnLayout or body._quiSkipDualColumnLayout then return end
    body._dualRowFrames = body._dualRowFrames or {}

    local pooledRowFrames = {}
    for _, rf in ipairs(body._dualRowFrames) do
        pooledRowFrames[rf] = true
    end

    local layoutItems = {}
    local itemOrder = {}
    local function AddLayoutItem(item, isTextRegion)
        if not item then return end
        if item.IsShown and not item:IsShown() then return end

        table.insert(layoutItems, item)
        itemOrder[item] = #layoutItems

        if isTextRegion then
            item._quiDualColumnFullWidth = true

            local textHeight = nil
            if item.GetStringHeight then
                textHeight = item:GetStringHeight()
            elseif item.GetHeight then
                textHeight = item:GetHeight()
            end
            item._quiDualColumnRowHeight = math.max(18, math.ceil((textHeight or 14) + 6))
        end
    end

    for _, child in ipairs({ body:GetChildren() }) do
        if not pooledRowFrames[child] and not child._quiDualRowFrame then
            AddLayoutItem(child, false)
        end
    end

    local regionCount = body.GetNumRegions and body:GetNumRegions() or 0
    for i = 1, regionCount do
        local region = select(i, body:GetRegions())
        local objectType = region and region.GetObjectType and region:GetObjectType() or nil
        if objectType == "FontString" then
            AddLayoutItem(region, true)
        end
    end

    if #layoutItems == 0 then return end

    -- Pre-rendered card groups (from CreateSettingsCardGroup) already
    -- pair their content into two columns with their own row frames.
    -- Reanchoring the card inside a 32px row frame scrambles the inner
    -- layout and causes siblings to overlap — skip this section entirely
    -- if any direct child is a marked card group.
    for _, item in ipairs(layoutItems) do
        if item._quiCardGroup then return end
    end

    -- Stable sort by descending top edge so order matches PlaceRow's
    -- vertical layout (top-most widgets first).
    table.sort(layoutItems, function(a, b)
        local at = a.GetTop and a:GetTop() or 0
        local bt = b.GetTop and b:GetTop() or 0
        if math.abs(at - bt) <= 1 then
            return (itemOrder[a] or 0) < (itemOrder[b] or 0)
        end
        return at > bt
    end)

    -- Reset row-chrome pool attached to the body so repeated renders don't
    -- leak textures.
    for _, rf in ipairs(body._dualRowFrames) do
        rf:Hide()
        rf._divider:Hide()
        rf._bg:Hide()
    end

    local function AcquireRowFrame(idx)
        local rf = body._dualRowFrames[idx]
        if not rf then
            rf = CreateFrame("Frame", nil, body)
            rf._quiDualRowFrame = true
            rf._bg = rf:CreateTexture(nil, "BACKGROUND")
            rf._bg:SetAllPoints(rf)
            rf._bg:Hide()
            rf._divider = rf:CreateTexture(nil, "ARTWORK")
            rf._divider:SetWidth(1)
            rf._divider:SetColorTexture(1, 1, 1, 0.05)
            rf._divider:Hide()
            body._dualRowFrames[idx] = rf
        end
        return rf
    end

    local ly = -4
    local rowIdx = 0
    local i = 1
    while i <= #layoutItems do
        local left = layoutItems[i]
        if left and left._quiDualColumnFullWidth then
            rowIdx = rowIdx + 1
            local rf = AcquireRowFrame(rowIdx)
            local rowHeight = GetDualColumnRowHeight(left)
            rf:ClearAllPoints()
            rf:SetPoint("TOPLEFT", body, "TOPLEFT", -2, ly)
            rf:SetPoint("TOPRIGHT", body, "TOPRIGHT", 2, ly)
            rf:SetHeight(rowHeight)
            rf:Show()
            rf._bg:Hide()
            rf._divider:Hide()

            left:ClearAllPoints()
            left:SetPoint("LEFT", rf, "LEFT", 12, 0)
            left:SetPoint("RIGHT", rf, "RIGHT", -12, 0)

            ly = ly - rowHeight
            i = i + 1
        else
            local right = layoutItems[i + 1]
            if right and right._quiDualColumnFullWidth then
                right = nil
            end

            rowIdx = rowIdx + 1
            local rf = AcquireRowFrame(rowIdx)
            rf:ClearAllPoints()
            rf:SetPoint("TOPLEFT", body, "TOPLEFT", -2, ly)
            rf:SetPoint("TOPRIGHT", body, "TOPRIGHT", 2, ly)
            rf:SetHeight(CARD_ROW_HEIGHT)
            rf:Show()

            if (rowIdx % 2) == 0 then
                rf._bg:SetColorTexture(1, 1, 1, 0.02)
                rf._bg:Show()
            end

            left:ClearAllPoints()
            left:SetPoint("LEFT", rf, "LEFT", 12, 0)
            if right then
                left:SetPoint("RIGHT", rf, "CENTER", -12, 0)
                right:ClearAllPoints()
                right:SetPoint("LEFT", rf, "CENTER", 12, 0)
                right:SetPoint("RIGHT", rf, "RIGHT", -12, 0)
                rf._divider:ClearAllPoints()
                rf._divider:SetPoint("TOP", rf, "TOP", 0, -6)
                rf._divider:SetPoint("BOTTOM", rf, "BOTTOM", 0, 6)
                rf._divider:Show()
                i = i + 2
            else
                left:SetPoint("RIGHT", rf, "RIGHT", -12, 0)
                i = i + 1
            end

            ly = ly - CARD_ROW_HEIGHT
        end
    end

    local contentHeight = math.abs(ly) + 4

    -- Providers set section._contentHeight to the full-width totalHeight
    -- at the end of their buildFunc (≈ nRows × FORM_ROW). RefreshContentHeight
    -- does math.max between that and the freshly-measured height, so if we
    -- don't reset it, the section retains the old tall height and leaves
    -- dead space below the compacted dual-column content. Clear both
    -- caches, then let RefreshContentHeight re-measure from the current
    -- child layout.
    section._contentHeight = 0
    body._contentHeight = contentHeight
    if section.SetExpanded then
        section:SetExpanded(true)
    elseif section.RefreshContentHeight then
        section:RefreshContentHeight()
    end
end

local function ApplyDualColumnLayoutWhenReady(section)
    if not section then return end

    ApplyDualColumnLayout(section)

    -- Tile sub-pages build into containers that start hidden and are only
    -- shown after the current selection finishes rendering. Re-run the
    -- compaction on the next frame so direct body regions (intro copy,
    -- helper text, etc.) have resolved geometry before we place row 1.
    C_Timer.After(0, function()
        if not section or not section._body or not section.GetParent then return end
        if not section:GetParent() then return end
        if section.IsShown and not section:IsShown() then return end
        ApplyDualColumnLayout(section)
    end)
end

---------------------------------------------------------------------------
-- RenderWithTileChrome
-- Wraps `fn` so every U.CreateCollapsible call inside it renders as a
-- borderless section and gets the dual-column post-process applied — the
-- V2 tile look (accent-dot header, no card border, rows paired into 32 px
-- cells with a center divider and alternating bg).
---------------------------------------------------------------------------
local function RenderWithTileChrome(fn)
    local U = ns.QUI_LayoutMode_Utils
    if not U or not U.CreateCollapsible then
        return xpcall(fn, ErrorHandler)
    end

    local originalCreate = U.CreateCollapsible
    local originalBuildPosition = U.BuildPositionCollapsible
    local originalOpenLink = U.BuildOpenFullSettingsLink

    U.CreateCollapsible = function(parent, title, contentHeight, buildFunc, sections, relayout)
        U._nextBorderless = true
        local section = originalCreate(parent, title, contentHeight, buildFunc, sections, relayout)
        ApplyDualColumnLayoutWhenReady(section)
        return section
    end

    if originalBuildPosition then
        U.BuildPositionCollapsible = function() end
    end
    if originalOpenLink then
        U.BuildOpenFullSettingsLink = function() end
    end

    local ok, result = xpcall(fn, ErrorHandler)

    U.CreateCollapsible = originalCreate
    if originalBuildPosition then
        U.BuildPositionCollapsible = originalBuildPosition
    end
    if originalOpenLink then
        U.BuildOpenFullSettingsLink = originalOpenLink
    end

    if not ok then
        geterrorhandler()(result)
        return nil
    end
    return result
end

SettingsBuilders.WithSuppressedPosition = WithSuppressedPosition
SettingsBuilders.WithOnlyPosition = WithOnlyPosition
SettingsBuilders.RenderWithTileChrome = RenderWithTileChrome

local function BuildViaProvider(providerKey, parent, width, options)
    if not parent then return 80 end

    ClearHost(parent)

    local provider = GetProvider(providerKey)
    if not provider or type(provider.build) ~= "function" then
        return ShowProviderUnavailable(parent, "Settings are still initializing. Please reopen this tab in a moment.")
    end

    local targetWidth = width or (parent and parent.GetWidth and parent:GetWidth()) or 400
    local surfaceId = parent._quiProviderSurfaceId or NextSurfaceId("options-provider")
    parent._quiProviderSurfaceId = surfaceId
    parent._quiProviderSync = {
        providerKey = providerKey,
        surfaceId = surfaceId,
    }

    local function RefreshSurface()
        local latestWidth = math.max(300, (parent and parent.GetWidth and parent:GetWidth()) or targetWidth or 400)
        return BuildViaProvider(providerKey, parent, latestWidth, options)
    end

    parent._quiProviderSurfaceInfo = {
        providerKey = providerKey,
        surfaceId = surfaceId,
        refreshFn = RefreshSurface,
    }

    SettingsBuilders.RegisterProviderSurface(providerKey, surfaceId, RefreshSurface, function()
        return IsSurfaceVisible(parent)
    end)

    if not parent._quiProviderSurfaceHooks then
        parent._quiProviderSurfaceHooks = true
        parent:HookScript("OnHide", function(self)
            local info = self._quiProviderSurfaceInfo
            if info then
                SettingsBuilders.UnregisterProviderSurface(info.surfaceId)
            end
        end)
        parent:HookScript("OnShow", function(self)
            local info = self._quiProviderSurfaceInfo
            if not info then return end
            SettingsBuilders.RegisterProviderSurface(info.providerKey, info.surfaceId, info.refreshFn, function()
                return IsSurfaceVisible(self)
            end)
            C_Timer.After(0, function()
                local latestInfo = self._quiProviderSurfaceInfo
                if latestInfo ~= info or not IsSurfaceVisible(self) then
                    return
                end
                info.refreshFn()
            end)
        end)
    end

    local function BuildSurfaceContent()
        return WithSuppressedPosition(options and options.includePosition, function()
            return provider.build(parent, providerKey, targetWidth)
        end)
    end

    local height
    if options and options.tileLayout then
        height = RenderWithTileChrome(BuildSurfaceContent)
    else
        height = BuildSurfaceContent()
    end

    if not height and parent and parent.GetHeight then
        height = parent:GetHeight()
    end
    if parent and parent.SetHeight and height then
        parent:SetHeight(math.max(height, 80))
    end
    return height or 80
end

function SettingsBuilders.BuildProvider(providerKey, parent, width, options)
    return BuildViaProvider(providerKey, parent, width, options)
end

-- Friendly display names for provider/feature keys. Used by higher-level
-- stacked feature composition to label each feature section without relying
-- on raw internal keys.
SettingsBuilders.PROVIDER_LABELS = {
    -- Gameplay · Combat
    combatTimer        = "Combat Timer",
    brezCounter        = "Battle Res Counter",
    atonementCounter   = "Atonement Counter",
    rotationAssistIcon = "Rotation Assist",
    focusCastAlert     = "Focus Cast Alert",
    petWarning         = "Pet Warning",
    readyCheck         = "Ready Check",
    mplusTimer         = "Mythic+ Timer",
    mplusProgress      = "Mythic+ Mob Progress",
    actionTracker      = "Action Tracker",

    -- Gameplay · Raid Buffs & Consumables
    missingRaidBuffs   = "Missing Raid Buffs",
    consumables        = "Consumables",

    -- Cooldown Manager
    buffIcon           = "Buff Icons",
    buffBar            = "Buff Bars",
    primaryPower       = "Primary Resource",
    secondaryPower     = "Secondary Resource",

    -- Appearance · widget anchoring labels
    topCenterWidgets    = "Top-Center Widgets",
    belowMinimapWidgets = "Below-Minimap Widgets",
    objectiveTracker    = "Objective Tracker",

    -- Action Bars · Per-Bar
    bar1 = "Bar 1", bar2 = "Bar 2", bar3 = "Bar 3", bar4 = "Bar 4",
    bar5 = "Bar 5", bar6 = "Bar 6", bar7 = "Bar 7", bar8 = "Bar 8",
    stanceBar = "Stance Bar",
    petBar    = "Pet Bar",
    microMenu = "Micro Menu",
    bagBar    = "Bag Bar",
    extraActionButton = "Extra Action Button",
    zoneAbility       = "Zone Ability",
    totemBar          = "Totem Bar",

    -- Group Frames
    partyFrames     = "Party Frames",
    raidFrames      = "Raid Frames",
    spotlightFrames = "Spotlight Frames",
    dandersParty    = "Danders Party",
    dandersRaid     = "Danders Raid",
    dandersPinned1  = "Danders Pinned Set 1",
    dandersPinned2  = "Danders Pinned Set 2",

    -- Minimap & Datatext
    datatextPanel = "Datatext Panel",
    minimap       = "Minimap",
}

