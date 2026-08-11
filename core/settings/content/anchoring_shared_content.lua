local ADDON_NAME, ns = ...
local Helpers = ns.Helpers

local QUI_Anchoring_Options = {}
ns.QUI_Anchoring_Options = QUI_Anchoring_Options

local function GetGUI()
    local QUI = _G.QUI
    if QUI and QUI.GUI then
        return QUI.GUI
    end
    return nil
end

local anchorLiveUpdaters = {}
local anchorListenerInstalled = false
local function EnsureAnchorChangedListener()
    if anchorListenerInstalled then return end
    local QUI = _G.QUI
    if not (QUI and QUI.RegisterMessage) then return end
    anchorListenerInstalled = true
    QUI:RegisterMessage("QUI_FRAME_ANCHOR_CHANGED", function(_, changedKey)
        local update = anchorLiveUpdaters[changedKey]
        if update then update() end
    end)
end

local function GetColors()
    local GUI = GetGUI()
    if GUI and GUI.Colors then
        return GUI.Colors
    end
    return {
        text = {1, 1, 1},
        border = {0.3, 0.3, 0.3},
        accent = {0.2, 0.6, 1}
    }
end

local GetCore = Helpers.GetCore

local ANCHORING_DEFAULTS = {
    parent         = "screen",
    point          = "CENTER",
    relative       = "CENTER",
    offsetX        = 0,
    offsetY        = 0,
    sizeStable     = true,
    autoWidth      = false,
    widthAdjust    = 0,
    autoHeight     = false,
    heightAdjust   = 0,
    hideWithParent = false,
    keepInPlace    = true,
}

local HUD_MIN_WIDTH_DEFAULT = (Helpers and Helpers.HUD_MIN_WIDTH_DEFAULT) or 200

function QUI_Anchoring_Options:GetAnchoringDB()
    local core = GetCore()
    local db = core and core.db and core.db.profile
    if not db then return nil end
    if type(db.frameAnchoring) ~= "table" then
        db.frameAnchoring = {}
    end

    local hudMinWidth
    if Helpers and Helpers.MigrateHUDMinWidthSettings then
        hudMinWidth = Helpers.MigrateHUDMinWidthSettings(db.frameAnchoring)
    end
    if not hudMinWidth then
        local enabled, width = false, HUD_MIN_WIDTH_DEFAULT
        if Helpers and Helpers.ParseHUDMinWidth then
            enabled, width = Helpers.ParseHUDMinWidth(db.frameAnchoring)
        end
        hudMinWidth = {
            enabled = enabled == true,
            width = width or HUD_MIN_WIDTH_DEFAULT,
        }
        db.frameAnchoring.hudMinWidth = hudMinWidth
        db.frameAnchoring.hudMinWidthEnabled = nil
    end

    return db.frameAnchoring
end

function QUI_Anchoring_Options:GetFrameDB(key)
    local anchoringDB = self:GetAnchoringDB()
    if not anchoringDB then return nil end

    local existing = anchoringDB[key]
    if existing then
        for k, v in pairs(ANCHORING_DEFAULTS) do
            if existing[k] == nil then
                existing[k] = v
            end
        end
        return existing
    end

    local proxy = {}
    setmetatable(proxy, {
        __index = function(_, k)
            local real = anchoringDB[key]
            if real and real[k] ~= nil then
                return real[k]
            end
            return ANCHORING_DEFAULTS[k]
        end,
        __newindex = function(_, k, v)
            local real = anchoringDB[key]
            if not real then
                if v == ANCHORING_DEFAULTS[k] then
                    return
                end
                real = {}
                anchoringDB[key] = real
                for dk, dv in pairs(ANCHORING_DEFAULTS) do
                    real[dk] = dv
                end
            end
            real[k] = v
        end,
    })
    return proxy
end

local FORM_ROW = 32

function QUI_Anchoring_Options:BuildAnchoringSection(tabContent, frameKey, options, y)
    options = options or {}
    local PAD = 15
    local GUI = GetGUI()
    if not GUI then return y, nil end

    local ninePointOptions = self:GetNinePointAnchorOptions()
    local frameDB = self:GetFrameDB(frameKey)
    if not frameDB then return y, nil end

    local screenW = math.ceil((UIParent and UIParent:GetWidth() or 1920) / 2)
    local screenH = math.ceil((UIParent and UIParent:GetHeight() or 1080) / 2)
    local defaultRange = math.max(screenW, screenH)
    local sliderMin = options.sliderRange and options.sliderRange[1] or -defaultRange
    local sliderMax = options.sliderRange and options.sliderRange[2] or defaultRange

    local widgetRefs = {}

    local function OnChange()
        if _G.QUI_ApplyFrameAnchor then
            _G.QUI_ApplyFrameAnchor(frameKey)
        end
        local inLayoutMode = _G.QUI_IsLayoutModeActive and _G.QUI_IsLayoutModeActive()
        if inLayoutMode then
            if _G.QUI_LayoutModeMarkChanged then
                _G.QUI_LayoutModeMarkChanged()
            end
            if _G.QUI_LayoutModeClearPending then
                _G.QUI_LayoutModeClearPending(frameKey)
            end
        end
        if _G.QUI_LayoutModeSyncHandle then
            _G.QUI_LayoutModeSyncHandle(frameKey)
        end

        local anchoringDB = GetCore()
        anchoringDB = anchoringDB and anchoringDB.db and anchoringDB.db.profile and anchoringDB.db.profile.frameAnchoring
        if anchoringDB then
            local visited = { [frameKey] = true }
            local queue = { frameKey }
            while #queue > 0 do
                local parentKey = table.remove(queue, 1)
                for childKey, childSettings in pairs(anchoringDB) do
                    if not visited[childKey] and type(childSettings) == "table"
                        and childSettings.parent == parentKey then
                        visited[childKey] = true
                        queue[#queue + 1] = childKey
                        if inLayoutMode and _G.QUI_LayoutModeClearPending then
                            _G.QUI_LayoutModeClearPending(childKey)
                        end
                        if _G.QUI_ForceReapplyFrameAnchor then
                            _G.QUI_ForceReapplyFrameAnchor(childKey)
                        elseif _G.QUI_ApplyFrameAnchor then
                            _G.QUI_ApplyFrameAnchor(childKey)
                        end
                        if _G.QUI_LayoutModeSyncHandle then
                            _G.QUI_LayoutModeSyncHandle(childKey)
                        end
                    end
                end
            end
        end
    end

    if not options.noHeader then
        local headerName = options.name or frameKey
        ns.QUI_Options.CreateAccentDotLabel(tabContent, headerName .. " " .. ns.L["Anchoring"], y); y = y - 30
    end

    local function OnAnchorTargetChange(val)
        frameDB.offsetX = 0
        frameDB.offsetY = 0
        if widgetRefs.sliderX and widgetRefs.sliderX.SetValue then
            widgetRefs.sliderX:SetValue(0, true)
        end
        if widgetRefs.sliderY and widgetRefs.sliderY.SetValue then
            widgetRefs.sliderY:SetValue(0, true)
        end
        OnChange()
    end
    local anchorDropdown = self:CreateAnchorDropdown(
        tabContent, ns.L["Anchor To"], frameDB, "parent",
        PAD + 10, y, nil, OnAnchorTargetChange,
        nil, nil, frameKey
    )
    if anchorDropdown then
        anchorDropdown:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        widgetRefs.anchorDropdown = anchorDropdown
        y = y - FORM_ROW
    end

    local fromPoint = GUI:CreateFormDropdown(tabContent, ns.L["From Point"], ninePointOptions, "point", frameDB, OnChange,
        { description = ns.L["Which corner or edge of this frame attaches to the anchor. Together with To Point, this defines how the two frames align."] })
    fromPoint:SetPoint("TOPLEFT", PAD + 10, y)
    fromPoint:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
    widgetRefs.fromPoint = fromPoint
    y = y - FORM_ROW

    local toPoint = GUI:CreateFormDropdown(tabContent, ns.L["To Point"], ninePointOptions, "relative", frameDB, OnChange,
        { description = ns.L["Which corner or edge of the anchor target this frame attaches to. Together with From Point, this defines how the two frames align."] })
    toPoint:SetPoint("TOPLEFT", PAD + 10, y)
    toPoint:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
    widgetRefs.toPoint = toPoint
    y = y - FORM_ROW

    local sliderX = GUI:CreateFormSlider(tabContent, ns.L["Offset X"], sliderMin, sliderMax, 1, "offsetX", frameDB, OnChange, nil,
        { description = ns.L["Horizontal pixel offset from the anchor point. Positive values move the frame right, negative values move it left."] })
    sliderX:SetPoint("TOPLEFT", PAD + 10, y)
    sliderX:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
    widgetRefs.sliderX = sliderX
    y = y - FORM_ROW

    local sliderY = GUI:CreateFormSlider(tabContent, ns.L["Offset Y"], sliderMin, sliderMax, 1, "offsetY", frameDB, OnChange, nil,
        { description = ns.L["Vertical pixel offset from the anchor point. Positive values move the frame up, negative values move it down."] })
    sliderY:SetPoint("TOPLEFT", PAD + 10, y)
    sliderY:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
    widgetRefs.sliderY = sliderY
    y = y - FORM_ROW

    if options.autoWidth then
        local autoWidthToggle = GUI:CreateFormToggle(tabContent, ns.L["Auto-Width (Match Anchor Target)"], "autoWidth", frameDB, OnChange,
            { description = ns.L["Automatically resize this frame to match the width of its anchor target so the two stay visually aligned. Use Width Adjustment below for fine pixel tweaks."] })
        autoWidthToggle:SetPoint("TOPLEFT", PAD + 10, y)
        autoWidthToggle:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        widgetRefs.autoWidth = autoWidthToggle
        y = y - FORM_ROW

        local widthAdjust = GUI:CreateFormSlider(tabContent, ns.L["Width Adjustment"], -20, 20, 1, "widthAdjust", frameDB, OnChange, nil,
            { description = ns.L["Pixel tweak added to the auto-matched width. Useful for overshooting or undershooting the anchor target to account for borders or padding."] })
        widthAdjust:SetPoint("TOPLEFT", PAD + 10, y)
        widthAdjust:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        widgetRefs.widthAdjust = widthAdjust
        y = y - FORM_ROW
    end

    if options.autoHeight then
        local autoHeightToggle = GUI:CreateFormToggle(tabContent, ns.L["Auto-Height (Match CDM Row 1 Icon)"], "autoHeight", frameDB, OnChange,
            { description = ns.L["Automatically resize this frame to match the height of the Cooldown Manager's first icon row, so the frame scales with CDM icon size changes."] })
        autoHeightToggle:SetPoint("TOPLEFT", PAD + 10, y)
        autoHeightToggle:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        widgetRefs.autoHeight = autoHeightToggle
        y = y - FORM_ROW

        local heightAdjust = GUI:CreateFormSlider(tabContent, ns.L["Height Adjustment"], -20, 20, 1, "heightAdjust", frameDB, OnChange, nil,
            { description = ns.L["Pixel tweak added to the auto-matched height. Useful for overshooting or undershooting the match to account for borders or visual padding."] })
        heightAdjust:SetPoint("TOPLEFT", PAD + 10, y)
        heightAdjust:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        widgetRefs.heightAdjust = heightAdjust
        y = y - FORM_ROW
    end

    if options.hideWithParent ~= false then
        local hideToggle = GUI:CreateFormToggle(tabContent, ns.L["Hide With Anchor"], "hideWithParent", frameDB, OnChange,
            { description = ns.L["Hide this frame whenever its anchor target is hidden, so dependent frames disappear together with the thing they follow."] })
        hideToggle:SetPoint("TOPLEFT", PAD + 10, y)
        hideToggle:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        widgetRefs.hideWithParent = hideToggle
        y = y - FORM_ROW
    end

    if options.hideWithParent ~= false then
        local keepToggle = GUI:CreateFormToggle(tabContent, ns.L["Keep In Place When Hidden"], "keepInPlace", frameDB, OnChange,
            { description = ns.L["When the anchor target is hidden but this frame stays visible, keep it at its last screen position instead of snapping toward the hidden anchor."] })
        keepToggle:SetPoint("TOPLEFT", PAD + 10, y)
        keepToggle:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        widgetRefs.keepInPlace = keepToggle
        y = y - FORM_ROW
    end

    y = y - 2

    local function ApplyLiveValues()
        local db = self:GetFrameDB(frameKey)
        if not db then return end
        if widgetRefs.sliderX and widgetRefs.sliderX.SetValue then
            widgetRefs.sliderX:SetValue(db.offsetX or 0, true)
        end
        if widgetRefs.sliderY and widgetRefs.sliderY.SetValue then
            widgetRefs.sliderY:SetValue(db.offsetY or 0, true)
        end
        if widgetRefs.anchorDropdown and widgetRefs.anchorDropdown.SetValue then
            widgetRefs.anchorDropdown:SetValue(db.parent or "screen", true)
        end
        if widgetRefs.fromPoint and widgetRefs.fromPoint.SetValue then
            widgetRefs.fromPoint:SetValue(db.point or "CENTER", true)
        end
        if widgetRefs.toPoint and widgetRefs.toPoint.SetValue then
            widgetRefs.toPoint:SetValue(db.relative or "CENTER", true)
        end
    end

    local function RegisterLiveUpdates()
        EnsureAnchorChangedListener()
        anchorLiveUpdaters[frameKey] = ApplyLiveValues
    end

    local function UnregisterLiveUpdates()
        if anchorLiveUpdaters[frameKey] == ApplyLiveValues then
            anchorLiveUpdaters[frameKey] = nil
        end
    end

    RegisterLiveUpdates()
    tabContent:HookScript("OnHide", function()
        UnregisterLiveUpdates()
    end)
    tabContent:HookScript("OnShow", function()
        RegisterLiveUpdates()
    end)

    return y, widgetRefs
end

function QUI_Anchoring_Options:CreateAnchorDropdown(parent, label, settingsDB, anchorKey, x, y, width, onChange, includeList, excludeList, excludeSelf)
    if not ns.QUI_Anchoring or not ns.QUI_Anchoring.GetAnchorTargetList then
        return nil
    end

    local GUI = GetGUI()
    if not GUI then
        return nil
    end

    local function GetAnchorOptions()
        return ns.QUI_Anchoring:GetAnchorTargetList(includeList, excludeList, excludeSelf)
    end
    local anchorOptions = GetAnchorOptions()

    local dropdown = GUI:CreateFormDropdown(parent, label, anchorOptions, anchorKey, settingsDB, onChange,
        { description = ns.L["Which frame this one anchors to. Pick a QUI frame, a Blizzard frame, or the screen; use From Point and To Point below to choose how the two frames align."] },
        { searchable = true, collapsible = true })
    dropdown.preserveUnknownValue = true

    if x and y then
        dropdown:SetPoint("TOPLEFT", x, y)
    end

    if width then
        dropdown:SetPoint("RIGHT", parent, "RIGHT", -(x or 0), 0)
    end

    return dropdown
end

function QUI_Anchoring_Options:GetNinePointAnchorOptions()
    return {
        {value = "TOPLEFT", text = ns.L["Top Left"]},
        {value = "TOP", text = ns.L["Top Center"]},
        {value = "TOPRIGHT", text = ns.L["Top Right"]},
        {value = "LEFT", text = ns.L["Center Left"]},
        {value = "CENTER", text = ns.L["Center"]},
        {value = "RIGHT", text = ns.L["Center Right"]},
        {value = "BOTTOMLEFT", text = ns.L["Bottom Left"]},
        {value = "BOTTOM", text = ns.L["Bottom Center"]},
        {value = "BOTTOMRIGHT", text = ns.L["Bottom Right"]},
    }
end
