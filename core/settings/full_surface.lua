local ADDON_NAME, ns = ...

local Settings = ns.Settings or {}
ns.Settings = Settings

local FullSurface = Settings.FullSurface or {}
Settings.FullSurface = FullSurface

local function ResolveCurrentThemeAccent()
    local gui = _G.QUI and _G.QUI.GUI
    local accent = gui and gui.Colors and gui.Colors.accent
    if type(accent) == "table" then
        return accent[1] or 1, accent[2] or 1, accent[3] or 1
    end
    return 0.2, 0.83, 0.6
end

-- Palette role lookup with a literal fallback for harnesses that never load
-- core/theme.lua. Returns r, g, b, a.
local function ThemeRole(name, fallback)
    local gui = _G.QUI and _G.QUI.GUI
    local role = gui and gui.Colors and gui.Colors[name] or fallback
    return role[1] or 1, role[2] or 1, role[3] or 1, role[4] or 1
end

local TAB_NORMAL_FALLBACK = { 1, 1, 1, 0.55 }
local TAB_HOVER_FALLBACK = { 1, 1, 1, 0.85 }
local TAB_SELECTED_TEXT_FALLBACK = { 1, 1, 1, 1 }
local STRIP_RULE_FALLBACK = { 1, 1, 1, 0.1 }

local function ResolveAccent(options)
    local accent = type(options) == "table" and options.accent or nil
    if type(accent) == "function" then
        local r, g, b = accent()
        if type(r) == "table" then
            return r[1] or 1, r[2] or 1, r[3] or 1
        end
        if r and g and b then
            return r, g, b
        end
    end
    if type(accent) == "table" then
        return accent[1] or 1, accent[2] or 1, accent[3] or 1
    end
    return ResolveCurrentThemeAccent()
end

function FullSurface.ClearFrame(frame)
    if not frame then
        return
    end

    local gui = _G.QUI and _G.QUI.GUI
    if gui and type(gui.TeardownFrameTree) == "function" then
        gui:TeardownFrameTree(frame)
        return
    end

    for _, child in pairs({ frame:GetChildren() }) do
        child:Hide()
        child:SetParent(nil)
        child:ClearAllPoints()
    end

    for _, region in pairs({ frame:GetRegions() }) do
        if region.Hide then
            region:Hide()
        end
        if region.SetParent then
            region:SetParent(nil)
        end
    end
end

function FullSurface.RenderEmbeddedEditor(parent, options)
    options = options or {}

    local render = options.render
    if not parent or type(render) ~= "function" then
        return nil, nil
    end

    local host = options.host
    if not host then
        host = CreateFrame("Frame", nil, parent)
        if host.ClearAllPoints then
            host:ClearAllPoints()
        end
        host:SetPoint("TOPLEFT", parent, "TOPLEFT", options.leftOffset or 0, options.topOffset or 0)
        host:SetPoint("TOPRIGHT", parent, "TOPRIGHT", options.rightOffset or 0, options.topOffset or 0)
    end

    local clearFrame = options.clearFrame
    if type(clearFrame) == "function" then
        clearFrame(host)
    end

    local minHeight = options.minHeight or 1
    if host.SetHeight then
        host:SetHeight(minHeight)
    end

    if type(options.beforeRender) == "function" then
        options.beforeRender(host)
    end

    local height = render(host)
    if type(height) ~= "number" or height <= 0 then
        height = host.GetHeight and host:GetHeight() or minHeight
    end
    if type(height) ~= "number" or height <= 0 then
        height = minHeight
    end

    height = math.max(minHeight, height)
    if host.SetHeight then
        host:SetHeight(height)
    end

    return height, host
end

function FullSurface.CreateSelectionController(state, options)
    options = options or {}

    local controller = {
        _suppressDropdownSync = false,
    }

    local stateKey = options.stateKey or "selection"
    local dropdownKey = options.dropdownKey or "dropdown"

    function controller:Set(value)
        local normalize = options.normalize
        if type(normalize) == "function" then
            value = normalize(value)
        end

        if state[stateKey] == value then
            return value, false
        end

        state[stateKey] = value

        local dropdown = state[dropdownKey]
        if dropdown and dropdown.SetValue and not controller._suppressDropdownSync then
            controller._suppressDropdownSync = true
            pcall(dropdown.SetValue, dropdown, value, true)
            controller._suppressDropdownSync = false
        end

        if type(options.afterSet) == "function" then
            options.afterSet(value, state, controller)
        end

        return value, true
    end

    function controller:IsSyncing()
        return controller._suppressDropdownSync == true
    end

    return controller
end

function FullSurface.CreateTabModel(state, options)
    options = options or {}

    local definitions = options.tabs or {}
    local stateKey = options.stateKey or "activeTab"
    local defaultKey = options.defaultKey or (definitions[1] and definitions[1].key)
    local model = {}

    local function IsVisible(definition)
        local visible = definition and definition.visible
        if type(visible) == "function" then
            return visible(state, definition, model) ~= false
        end
        return visible ~= false
    end

    function model:GetTabs()
        local tabs = {}
        for _, definition in ipairs(definitions) do
            if IsVisible(definition) then
                tabs[#tabs + 1] = definition
            end
        end
        return tabs
    end

    function model:NormalizeKey(tabKey)
        local normalized = tabKey or state[stateKey] or defaultKey
        if type(options.normalizeKey) == "function" then
            local custom = options.normalizeKey(normalized, state, model)
            if custom ~= nil then
                normalized = custom
            end
        end

        for _, definition in ipairs(self:GetTabs()) do
            if definition.key == normalized then
                return normalized
            end
        end

        local fallback = type(options.resolveFallbackKey) == "function"
            and options.resolveFallbackKey(self:GetTabs(), state, model)
            or nil
        if fallback ~= nil then
            return fallback
        end

        local first = self:GetTabs()[1]
        return (first and first.key) or normalized
    end

    function model:ApplyNormalized(tabKey)
        local previous = state[stateKey]
        local normalized = self:NormalizeKey(tabKey)
        state[stateKey] = normalized
        return normalized, previous ~= normalized
    end

    function model:GetActiveKey()
        local normalized = self:NormalizeKey(state[stateKey])
        if state[stateKey] ~= normalized then
            state[stateKey] = normalized
        end
        return normalized
    end

    function model:SetActiveKey(tabKey)
        state[stateKey] = tabKey
    end

    function model:GetDefinition(tabKey)
        local key = self:NormalizeKey(tabKey)
        for _, definition in ipairs(self:GetTabs()) do
            if definition.key == key then
                return definition
            end
        end
        return nil
    end

    function model:GetHostKey(tabKey)
        local definition = self:GetDefinition(tabKey)
        if not definition then
            return options.defaultHostKey
        end

        local hostKey = definition.hostKey
        if type(hostKey) == "function" then
            hostKey = hostKey(state, definition, model)
        end
        return hostKey or options.defaultHostKey
    end

    function model:RenderKey(host, tabKey, ...)
        local definition = self:GetDefinition(tabKey)
        local renderer = definition and definition.render or nil
        if type(renderer) == "function" then
            return renderer(host, state, definition, ...)
        end

        if type(options.onMissing) == "function" then
            return options.onMissing(host, definition, state, model, ...)
        end

        return nil
    end

    return model
end

function FullSurface.BuildHeaderActions(headerRow, options)
    options = options or {}

    local gui = options.gui or (_G.QUI and _G.QUI.GUI)
    local definitions = options.actions
    if not gui or type(gui.CreateButton) ~= "function"
        or type(definitions) ~= "table" or #definitions == 0 then
        return {
            buttons = {},
            width = 0,
            leftGap = 0,
        }
    end

    local buttonGap = options.buttonGap or 10
    local rightInset = options.rightInset or 0
    local leftGap = options.leftGap or buttonGap
    local occupiedWidth = rightInset
    local buttons = {}
    local previous

    for index = #definitions, 1, -1 do
        local definition = definitions[index]
        local width = definition.width or 90
        local height = definition.height or 24
        local gap = definition.gapAfter or buttonGap

        local button = gui:CreateButton(
            headerRow,
            definition.text or definition.label or ns.L["Action"],
            width,
            height,
            function(...)
                if type(definition.onClick) == "function" then
                    definition.onClick(...)
                end
            end,
            definition.variant or definition.style or "ghost"
        )

        if previous then
            button:SetPoint("TOPRIGHT", previous, "TOPLEFT", -gap, 0)
            occupiedWidth = occupiedWidth + width + gap
        else
            button:SetPoint("TOPRIGHT", headerRow, "TOPRIGHT", -rightInset, definition.topOffset or -2)
            occupiedWidth = occupiedWidth + width
        end

        local stateField = definition.stateField
        if type(options.state) == "table"
            and type(stateField) == "string" and stateField ~= "" then
            options.state[stateField] = button
        end

        if type(definition.key) == "string" and definition.key ~= "" then
            buttons[definition.key] = button
        end

        if type(definition.afterCreate) == "function" then
            definition.afterCreate(button, definition)
        end

        previous = button
    end

    return {
        buttons = buttons,
        width = occupiedWidth,
        leftGap = leftGap,
    }
end

function FullSurface.BuildDropdownPreviewBlock(parent, options)
    options = options or {}

    local gui = options.gui or (_G.QUI and _G.QUI.GUI)
    if not gui then
        return nil
    end

    local pad = options.padding or 8
    local headerHeight = options.headerHeight or 30
    local headerTop = options.headerTopOffset or -2
    local previewGap = options.previewGap or -4
    local previewFillAlpha = options.previewFillAlpha
    if previewFillAlpha == nil then
        previewFillAlpha = 0.15
    end

    local showDropdown = options.showDropdown
    if showDropdown == nil then
        showDropdown = true
    end

    local headerRow, actions, dropdown, dropdownStateKey, dropdownDB

    if showDropdown then
        headerRow = CreateFrame("Frame", nil, parent)
        headerRow:SetHeight(headerHeight)
        headerRow:SetPoint("TOPLEFT", pad, headerTop)
        headerRow:SetPoint("TOPRIGHT", -pad, headerTop)

        actions = FullSurface.BuildHeaderActions(headerRow, {
            gui = gui,
            state = options.state,
            actions = options.headerActions,
            buttonGap = options.headerActionGap,
            leftGap = options.headerActionLeftGap,
            rightInset = options.headerActionRightInset,
        })

        dropdownStateKey = options.dropdownStateKey or "_selection"
        dropdownDB = {
            [dropdownStateKey] = options.selectedValue,
        }

        local dropdownRightInset = options.dropdownRightInset or 0
        if actions.width > 0 then
            dropdownRightInset = math.max(dropdownRightInset, actions.width + actions.leftGap)
        end

        dropdown = gui:CreateFormDropdown(
            headerRow,
            options.dropdownLabel or ns.L["Selection"],
            options.dropdownOptions or {},
            dropdownStateKey,
            dropdownDB,
            function()
                if type(options.onDropdownChanged) == "function" then
                    options.onDropdownChanged(dropdownDB[dropdownStateKey], dropdownDB)
                end
            end,
            options.dropdownMeta or {},
            options.dropdownConfig or { searchable = false, collapsible = false }
        )
        dropdown:SetPoint("TOPLEFT", headerRow, "TOPLEFT", 0, 0)
        dropdown:SetPoint("RIGHT", headerRow, "RIGHT", -dropdownRightInset, 0)

        if type(options.state) == "table" then
            options.state[options.dropdownField or "dropdown"] = dropdown
        end
    end

    local previewHost = CreateFrame("Frame", nil, parent)
    if showDropdown then
        previewHost:SetPoint("TOPLEFT", headerRow, "BOTTOMLEFT", 0, previewGap)
    else
        previewHost:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, 0)
    end
    previewHost:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -pad, pad)

    if options.clipPreviewChildren and previewHost.SetClipsChildren then
        previewHost:SetClipsChildren(true)
    end

    if previewFillAlpha > 0 then
        local hostBg = previewHost:CreateTexture(nil, "BACKGROUND")
        hostBg:SetAllPoints(previewHost)
        hostBg:SetColorTexture(0, 0, 0, previewFillAlpha)
    end

    if type(options.onBuildPreviewHost) == "function" then
        options.onBuildPreviewHost(previewHost, {
            headerRow = headerRow,
            dropdown = dropdown,
            dropdownDB = dropdownDB,
            actions = actions and actions.buttons,
        })
    end

    return {
        headerRow = headerRow,
        dropdown = dropdown,
        dropdownDB = dropdownDB,
        previewHost = previewHost,
        actions = actions and actions.buttons,
    }
end

function FullSurface.MeasureRenderedExtent(root)
    if not root then return 0, 0 end
    local L, R, T, B
    local function acc(region)
        if not region or not region.GetLeft or not region.IsShown or not region:IsShown() then return end
        local l, r, t, b = region:GetLeft(), region:GetRight(), region:GetTop(), region:GetBottom()
        if not (l and r and t and b) then return end
        local s = (region.GetEffectiveScale and region:GetEffectiveScale()) or 1
        if s <= 0 then s = 1 end
        l, r, t, b = l * s, r * s, t * s, b * s
        if L == nil or l < L then L = l end
        if R == nil or r > R then R = r end
        if T == nil or t > T then T = t end
        if B == nil or b < B then B = b end
    end
    acc(root)
    local function walk(f)
        if f.GetChildren then
            for _, c in ipairs({ f:GetChildren() }) do
                if not (c.IsShown and not c:IsShown()) then
                    acc(c)
                    walk(c)
                end
            end
        end
        if f.GetRegions then
            for _, rg in ipairs({ f:GetRegions() }) do acc(rg) end
        end
    end
    walk(root)
    if L == nil then return 0, 0 end
    local rootScale = (root.GetEffectiveScale and root:GetEffectiveScale()) or 1
    if rootScale <= 0 then rootScale = 1 end
    return (R - L) / rootScale, (T - B) / rootScale
end

function FullSurface.CreateDockedPreviewPanel(opts)
    opts = opts or {}
    local gui = opts.gui or (_G.QUI and _G.QUI.GUI)
    local window = opts.window or (gui and gui.MainFrame) or _G.QUI_Options
    if not gui or not window then return nil end

    local SCALE_MIN = tonumber(opts.scaleMin) or 0.4
    local SCALE_MAX = tonumber(opts.scaleMax) or 1.25
    if SCALE_MAX < SCALE_MIN then SCALE_MAX = SCALE_MIN end

    local session = opts.sessionState or {}
    if session.scale == nil then
        local seed = tonumber(opts.defaultScale) or 1
        session.scale = math.max(SCALE_MIN, math.min(SCALE_MAX, seed))
    end
    if session.collapsed == nil then session.collapsed = false end
    session.detached = false

    local UIKit = ns.UIKit
    local C = gui.Colors or {}
    local bg = C.bg or { 0.06, 0.06, 0.06 }
    local border = C.border or { 0.22, 0.22, 0.22 }

    local GAP = opts.gap or 6
    local PAD = opts.pad or 8
    local HEADER_H = opts.headerHeight or 22
    local STRIP_H = opts.controlStripHeight or 0
    local MIN_W = opts.minWidth or 140

    local panel = CreateFrame("Frame", nil, window, "BackdropTemplate")
    panel:SetFrameStrata("FULLSCREEN_DIALOG")
    panel:SetToplevel(true)
    local LEVEL_OFFSET = 40
    local function RaiseAboveWindow()
        panel:SetFrameLevel((window:GetFrameLevel() or 500) + LEVEL_OFFSET)
        panel:Raise()
    end
    RaiseAboveWindow()
    panel:SetClampedToScreen(true)
    panel:SetSize(MIN_W + PAD * 2, HEADER_H + PAD * 2 + 40)
    panel:Hide()
    local function ApplyBackdrop()
        if not panel:GetParent() then return end
        if ns.SkinBase and ns.SkinBase.ApplyPixelBackdrop then
            ns.SkinBase.ApplyPixelBackdrop(panel, 1, true, false,
                { border[1], border[2], border[3], border[4] or 1 },
                { bg[1], bg[2], bg[3], bg[4] or 1 })
        end
    end
    ApplyBackdrop()
    if UIKit and UIKit.RegisterScaleRefresh then
        UIKit.RegisterScaleRefresh(panel, "dockedPreviewPanel" .. (opts.idSuffix or ""), ApplyBackdrop)
    end

    local contentBg = C.bgContent
    if contentBg then
        local wash = panel:CreateTexture(nil, "BACKGROUND", nil, 1)
        wash:SetPoint("TOPLEFT", panel, "TOPLEFT", 1, -1)
        wash:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -1, 1)
        wash:SetColorTexture(contentBg[1], contentBg[2], contentBg[3], contentBg[4] or 0.02)
        panel._contentWash = wash
    end
    local glowColor = C.accentGlow
    if glowColor then
        local glow = panel:CreateTexture(nil, "BACKGROUND", nil, 2)
        glow:SetPoint("TOPLEFT", panel, "TOPLEFT", 1, -1)
        glow:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -1, 1)
        glow:SetTexture("Interface\\BUTTONS\\WHITE8x8")
        if glow.SetGradient and CreateColor then
            local ok = pcall(function()
                glow:SetGradient("HORIZONTAL",
                    CreateColor(glowColor[1], glowColor[2], glowColor[3], glowColor[4] or 0.06),
                    CreateColor(glowColor[1], glowColor[2], glowColor[3], 0))
            end)
            if not ok then
                glow:SetColorTexture(glowColor[1], glowColor[2], glowColor[3], glowColor[4] or 0.06)
            end
        else
            glow:SetColorTexture(glowColor[1], glowColor[2], glowColor[3], glowColor[4] or 0.06)
        end
        panel._accentGlow = glow
    end

    local HEADER_BAND_H = HEADER_H + PAD
    local bandColor = C.bgSidebar or { 0, 0, 0, 0.25 }
    local bandHover = C.accentFaint or { 1, 1, 1, 0.07 }

    local headerBand = panel:CreateTexture(nil, "ARTWORK", nil, 0)
    headerBand:SetPoint("TOPLEFT", panel, "TOPLEFT", 1, -1)
    headerBand:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -1, -1)
    headerBand:SetHeight(HEADER_BAND_H - 1)
    local function SetBandColor(c)
        headerBand:SetColorTexture(c[1], c[2], c[3], c[4] or 0.25)
    end
    SetBandColor(bandColor)
    panel._headerBand = headerBand

    local headerSep = panel:CreateTexture(nil, "ARTWORK", nil, 1)
    headerSep:SetPoint("TOPLEFT", panel, "TOPLEFT", PAD, -HEADER_BAND_H)
    headerSep:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -PAD, -HEADER_BAND_H)
    headerSep:SetHeight(1)
    headerSep:SetColorTexture(border[1], border[2], border[3], border[4] or 1)
    panel._headerSep = headerSep

    local titleColor = C.text or { 1, 1, 1, 1 }
    local title = gui:CreateLabel(panel, opts.title or ns.L["Preview"], 13,
        C.accentLight or titleColor, "TOPLEFT", PAD, -PAD)
    title:SetJustifyH("LEFT")

    local P

    panel:SetMovable(true)
    local header = CreateFrame("Frame", nil, panel)
    header:SetPoint("TOPLEFT", 0, 0)
    header:SetPoint("TOPRIGHT", 0, 0)
    header:SetHeight(HEADER_H + PAD)
    header:EnableMouse(true)
    header:RegisterForDrag("LeftButton")

    local UpdateHeaderButtons, ApplySize, ApplyCollapsedSize, grip

    header:SetScript("OnDragStart", function()
        session.detached = true
        RaiseAboveWindow()
        panel:StartMoving()
        UpdateHeaderButtons()
    end)
    header:SetScript("OnDragStop", function()
        panel:StopMovingOrSizing()
    end)
    header:SetScript("OnEnter", function() SetBandColor(bandHover) end)
    header:SetScript("OnLeave", function() SetBandColor(bandColor) end)

    local BTN_H = 18
    local function MakeHeaderButton(text, width, onClick)
        if UIKit and UIKit.CreateButton then
            local b = UIKit.CreateButton(header, {
                text = text, width = width, height = BTN_H,
                onClick = onClick, variant = "ghost", fontSize = 10,
            })
            b._label = b.text
            return b
        end
        local b = CreateFrame("Button", nil, header)
        b:SetSize(width, 16)
        b._label = gui:CreateLabel(b, text, 13, titleColor, "CENTER", 0, 0)
        b:SetScript("OnClick", onClick)
        return b
    end

    local COLLAPSE_BTN_W, DOCK_BTN_W = 20, 44
    local collapseBtn = MakeHeaderButton("–", COLLAPSE_BTN_W, function()
        P.SetCollapsed(not session.collapsed)
    end)
    collapseBtn:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -PAD, -PAD + 1)

    local dockBtn = MakeHeaderButton(ns.L["Dock"], DOCK_BTN_W, function()
        P.Redock()
    end)
    dockBtn:SetPoint("TOPRIGHT", collapseBtn, "TOPLEFT", -4, 0)

    local COLLAPSED_MIN_W = 96
    ApplyCollapsedSize = function()
        local titleW = (title.GetStringWidth and title:GetStringWidth()) or 0
        local btnW = collapseBtn:GetWidth() or COLLAPSE_BTN_W
        if session.detached then
            btnW = btnW + 4 + (dockBtn:GetWidth() or DOCK_BTN_W)
        end
        local w = PAD + titleW + 8 + btnW + PAD
        if w < COLLAPSED_MIN_W then w = COLLAPSED_MIN_W end
        panel:SetSize(w, HEADER_H + PAD * 2)
    end

    UpdateHeaderButtons = function()
        dockBtn:SetShown(session.detached and true or false)
        collapseBtn._label:SetText(session.collapsed and "+" or "–")
        grip:SetShown(not session.collapsed)
        if session.collapsed then ApplyCollapsedSize() end
    end

    local controlStrip
    if STRIP_H > 0 then
        controlStrip = CreateFrame("Frame", nil, panel)
        controlStrip:SetPoint("TOPLEFT", PAD, -(PAD + HEADER_H))
        controlStrip:SetPoint("TOPRIGHT", -PAD, -(PAD + HEADER_H))
        controlStrip:SetHeight(STRIP_H)
    end

    local content = CreateFrame("Frame", nil, panel)
    content:SetPoint("TOPLEFT", PAD, -(PAD + HEADER_H + STRIP_H))
    content:SetPoint("BOTTOMRIGHT", -PAD, PAD)

    local scaleHost = CreateFrame("Frame", nil, content)
    scaleHost:SetPoint("TOPLEFT", content, "TOPLEFT", 0, 0)
    scaleHost:SetSize(1, 1)
    scaleHost:SetScale(session.scale or 1)

    local EDGE_MARGIN = 8

    local function Reflow()
        if session.detached then return end
        local ws = window:GetEffectiveScale() or 1
        local us = UIParent:GetEffectiveScale() or 1
        if ws <= 0 then ws = 1 end

        local panelW = panel:GetWidth() or 0
        local winRightPx = (window:GetRight() or 0) * ws
        local winLeftPx = (window:GetLeft() or 0) * ws
        local panelWpx = panelW * ws
        local gapPx = GAP * ws
        local screenRightPx = (UIParent:GetRight() or 0) * us
        local screenLeftPx = (UIParent:GetLeft() or 0) * us

        panel:ClearAllPoints()

        local neededRightPx = winRightPx + gapPx + panelWpx
        if neededRightPx <= screenRightPx then
            panel:SetPoint("TOPLEFT", window, "TOPRIGHT", GAP, 0)
            return
        end

        local leftDockEdgePx = winLeftPx - gapPx - panelWpx
        if leftDockEdgePx >= screenLeftPx then
            panel:SetPoint("TOPRIGHT", window, "TOPLEFT", -GAP, 0)
            return
        end

        local overflowPx = (neededRightPx - screenRightPx) + EDGE_MARGIN
        if (winLeftPx - overflowPx) >= screenLeftPx then
            local point, relTo, relPoint, x, y = window:GetPoint(1)
            if point then
                window:SetPoint(point, relTo, relPoint, (x or 0) - (overflowPx / ws), y or 0)
                panel:SetPoint("TOPLEFT", window, "TOPRIGHT", GAP, 0)
                return
            end
        end

        panel:SetPoint("TOPRIGHT", window, "TOPLEFT", -GAP, 0)
    end

    panel:HookScript("OnShow", function()
        if not session.collapsed and (session.contentW or 0) > 0 then
            ApplySize()
        end
        Reflow()
    end)
    window:HookScript("OnSizeChanged", function() if panel:IsShown() then Reflow() end end)
    if type(window.StopMovingOrSizing) == "function" then
        hooksecurefunc(window, "StopMovingOrSizing", function() if panel:IsShown() then Reflow() end end)
    end

    window:HookScript("OnHide", function()
        if grip then grip:SetScript("OnUpdate", nil) end
        if session.detached then
            session.detached = false
            panel:ClearAllPoints()
            if type(panel.StopMovingOrSizing) == "function" then
                panel:StopMovingOrSizing()
            end
        end
        UpdateHeaderButtons()
    end)

    P = { frame = panel, contentHost = scaleHost, controlStrip = controlStrip }

    grip = CreateFrame("Button", nil, panel)
    grip:SetSize(16, 16)
    grip:SetPoint("BOTTOMRIGHT", -2, 2)
    grip:SetFrameLevel((panel:GetFrameLevel() or 500) + 10)

    local gripTex = grip:CreateTexture(nil, "OVERLAY")
    gripTex:SetAllPoints()
    gripTex:SetTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")

    local gripHi = grip:CreateTexture(nil, "HIGHLIGHT")
    gripHi:SetAllPoints()
    gripHi:SetTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")

    local function CancelGripDrag()
        grip:SetScript("OnUpdate", nil)
        if type(panel.StopMovingOrSizing) == "function" then
            panel:StopMovingOrSizing()
        end
    end

    grip:SetScript("OnMouseDown", function(self, button)
        if button ~= "LeftButton" or session.collapsed then return end
        local ox = (panel:GetLeft() or 0) - (window:GetLeft() or 0)
        local oy = (panel:GetTop() or 0) - (window:GetTop() or 0)
        panel:ClearAllPoints()
        panel:SetPoint("TOPLEFT", window, "TOPLEFT", ox, oy)
        local es = panel:GetEffectiveScale() or 1
        if es <= 0 then es = 1 end
        local _, cy = GetCursorPosition()
        self._startY = cy / es
        self._startScale = session.scale or 1
        self._elapsed = 0
        self:SetScript("OnUpdate", function(self, elapsed)
            self._elapsed = (self._elapsed or 0) + elapsed
            if self._elapsed < 0.016 then return end
            self._elapsed = 0
            local contentH = session.contentH or 0
            if contentH <= 0 then return end
            local es2 = panel:GetEffectiveScale() or 1
            if es2 <= 0 then es2 = 1 end
            local _, y = GetCursorPosition()
            local dyDown = self._startY - y / es2
            P.SetContentScale(self._startScale + dyDown / contentH)
        end)
    end)
    grip:SetScript("OnMouseUp", function(self)
        self:SetScript("OnUpdate", nil)
        Reflow()
    end)
    panel:HookScript("OnHide", CancelGripDrag)

    function P.SetTitle(text)
        title:SetText(text or ns.L["Preview"])
        if session.collapsed then
            ApplyCollapsedSize()
            Reflow()
        end
    end
    function P.Show()
        panel:Show()
        RaiseAboveWindow()
        Reflow()
    end
    function P.Hide() panel:Hide() end
    function P.IsDetached() return session.detached and true or false end
    function P.Redock()
        session.detached = false
        panel:ClearAllPoints()
        UpdateHeaderButtons()
        Reflow()
    end
    P.header = header
    P.dockButton = dockBtn
    P._session = session

    ApplySize = function()
        local s = session.scale or 1
        local w = math.max((session.contentW or 0) * s, MIN_W) + PAD * 2
        local h = (session.contentH or 0) * s + HEADER_H + STRIP_H + PAD * 2
        local cap = (window:GetHeight() or 850)
        if h > cap then h = cap end
        panel:SetSize(w, h)
    end

    function P.SetContentScale(s)
        s = tonumber(s) or 1
        if s < SCALE_MIN then s = SCALE_MIN end
        if s > SCALE_MAX then s = SCALE_MAX end
        session.scale = s
        scaleHost:SetScale(s)
        if not session.collapsed then
            ApplySize()
        end
    end
    function P.GetContentScale() return session.scale or 1 end

    function P.Resize(contentW, contentH)
        session.contentW, session.contentH = contentW or 0, contentH or 0
        if session.collapsed then return end
        ApplySize()
        Reflow()
    end

    function P.SetCollapsed(v)
        session.collapsed = v and true or false
        if session.collapsed then
            content:Hide()
            if controlStrip then controlStrip:Hide() end
            headerBand:SetHeight(HEADER_H + PAD * 2 - 2)
            headerSep:Hide()
            ApplyCollapsedSize()
        else
            content:Show()
            if controlStrip then controlStrip:Show() end
            headerBand:SetHeight(HEADER_BAND_H - 1)
            headerSep:Show()
            ApplySize()
        end
        UpdateHeaderButtons()
        Reflow()
    end
    function P.IsCollapsed() return session.collapsed and true or false end
    P.collapseButton = collapseBtn
    P._contentWrapper = content
    P.grip = grip

    if session.collapsed then
        P.SetCollapsed(true)
    else
        UpdateHeaderButtons()
    end

    return P
end

function FullSurface.BuildContextDropdownRow(parent, opts)
    opts = opts or {}
    local gui = opts.gui or (_G.QUI and _G.QUI.GUI)
    if not gui or not parent then return nil end

    local pad = opts.pad or 8
    local height = opts.height or 30
    local topOffset = opts.topOffset or 0
    local stateKey = opts.stateKey or "_selection"

    local row = CreateFrame("Frame", nil, parent)
    row:SetHeight(height)
    row:SetPoint("TOPLEFT", parent, "TOPLEFT", pad, -(4 + topOffset))
    row:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -pad, -(4 + topOffset))

    local db = { [stateKey] = opts.selectedValue }
    local dropdown = gui:CreateFormDropdown(
        row,
        opts.label or ns.L["Selection"],
        opts.options or {},
        stateKey,
        db,
        function()
            if type(opts.onChanged) == "function" then
                opts.onChanged(db[stateKey], db)
            end
        end,
        opts.meta or {},
        opts.config or { searchable = false, collapsible = false }
    )
    dropdown:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
    dropdown:SetPoint("RIGHT", row, "RIGHT", 0, 0)

    return { row = row, dropdown = dropdown, dropdownDB = db }
end

function FullSurface.CreateTabStrip(parent, options)
    options = options or {}

    local rowHeight = options.rowHeight or 28
    local rowSpacing = options.rowSpacing or 6
    local buttonSpacing = options.buttonSpacing or 16
    local buttonPadding = options.buttonPadding or 24
    local labelSize = options.labelSize or 11
    local wrapRows = options.wrapRows == true
    local fixedRows = options.fixedRows == true
    local rowResolver = options.rowResolver
    local fallbackWidth = options.fallbackWidth or 780

    local strip = CreateFrame("Frame", nil, parent)
    strip:SetHeight(rowHeight)

    local underline = strip:CreateTexture(nil, "OVERLAY")
    underline:SetPoint("BOTTOMLEFT", 0, 0)
    underline:SetPoint("BOTTOMRIGHT", 0, 0)
    underline:SetHeight(1)
    underline:SetColorTexture(ThemeRole("borderStrong", STRIP_RULE_FALLBACK))

    local buttons = {}

    local function EnsureButton(index)
        local button = buttons[index]
        if button then
            return button
        end

        button = CreateFrame("Button", nil, strip)
        button:SetHeight(rowHeight)

        local label = button:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        label:SetPoint("CENTER", 0, 0)
        local fontPath, _, fontFlags = label:GetFont()
        ns.Helpers.ApplyFontWithFallback(label, fontPath, labelSize, fontFlags or "")
        button._label = label

        local activeBar = button:CreateTexture(nil, "OVERLAY")
        activeBar:SetPoint("BOTTOMLEFT", 4, 0)
        activeBar:SetPoint("BOTTOMRIGHT", -4, 0)
        activeBar:SetHeight(2)
        local accentR, accentG, accentB = ResolveAccent(options)
        activeBar:SetColorTexture(accentR, accentG, accentB, 1)
        activeBar:Hide()
        button._activeBar = activeBar

        button:SetScript("OnEnter", function(self)
            if not self._tabActive then
                self._label:SetTextColor(ThemeRole("tabHover", TAB_HOVER_FALLBACK))
            end
        end)
        button:SetScript("OnLeave", function(self)
            if not self._tabActive then
                self._label:SetTextColor(ThemeRole("tabNormal", TAB_NORMAL_FALLBACK))
            end
        end)

        buttons[index] = button
        return button
    end

    local function PaintButton(button, width, activeKey, onClick, xOffset, yOffset)
        button:SetWidth(width)
        button:ClearAllPoints()

        if wrapRows or fixedRows then
            button:SetPoint("TOPLEFT", strip, "TOPLEFT", xOffset, yOffset)
        else
            button:SetPoint("LEFT", strip, "LEFT", xOffset, 0)
        end

        if button._tabKey == activeKey then
            local accentR, accentG, accentB = ResolveAccent(options)
            button._tabActive = true
            button._activeBar:SetColorTexture(accentR, accentG, accentB, 1)
            button._label:SetTextColor(ThemeRole("tabSelectedText", TAB_SELECTED_TEXT_FALLBACK))
            button._activeBar:Show()
        else
            button._tabActive = false
            button._label:SetTextColor(ThemeRole("tabNormal", TAB_NORMAL_FALLBACK))
            button._activeBar:Hide()
        end

        button:SetScript("OnClick", function(self)
            onClick(self._tabKey)
        end)
        button:Show()
    end

    local function Paint(tabs, activeKey, onClick)
        for _, button in ipairs(buttons) do
            button:Hide()
            button:ClearAllPoints()
        end

        local widths = {}
        for index, definition in ipairs(tabs) do
            local button = EnsureButton(index)
            button._tabKey = definition.key
            button._label:SetText(definition.label)
            widths[index] = button._label:GetStringWidth() + buttonPadding
        end

        if fixedRows then
            local rowLookup = {}
            local rowKeys = {}

            for index, definition in ipairs(tabs) do
                local rowKey = definition.row
                if type(rowResolver) == "function" then
                    local resolved = rowResolver(definition)
                    if resolved ~= nil then
                        rowKey = resolved
                    end
                end
                rowKey = rowKey or 1
                if not rowLookup[rowKey] then
                    rowLookup[rowKey] = {}
                    rowKeys[#rowKeys + 1] = rowKey
                end
                rowLookup[rowKey][#rowLookup[rowKey] + 1] = index
            end

            table.sort(rowKeys)
            local rows = {}
            for _, rowKey in ipairs(rowKeys) do
                rows[#rows + 1] = rowLookup[rowKey]
            end

            for rowIndex, row in ipairs(rows) do
                local xOffset = 0
                local yOffset = -((rowIndex - 1) * (rowHeight + rowSpacing))
                for _, buttonIndex in ipairs(row) do
                    local button = buttons[buttonIndex]
                    PaintButton(button, widths[buttonIndex], activeKey, onClick, xOffset, yOffset)
                    xOffset = xOffset + widths[buttonIndex] + buttonSpacing
                end
            end

            local totalRows = #rows
            strip:SetHeight(totalRows * rowHeight + math.max(0, totalRows - 1) * rowSpacing)
            return
        end

        if wrapRows then
            local stripWidth = strip:GetWidth()
            if not stripWidth or stripWidth <= 0 then
                stripWidth = fallbackWidth
            end

            local rows = { {} }
            local rowWidths = { 0 }
            for index in ipairs(tabs) do
                local width = widths[index]
                local rowIndex = #rows
                local currentWidth = rowWidths[rowIndex]
                local spacing = currentWidth > 0 and buttonSpacing or 0

                if currentWidth + spacing + width > stripWidth and currentWidth > 0 then
                    rows[#rows + 1] = {}
                    rowWidths[#rowWidths + 1] = 0
                    rowIndex = #rows
                    currentWidth = 0
                    spacing = 0
                end

                rows[rowIndex][#rows[rowIndex] + 1] = index
                rowWidths[rowIndex] = currentWidth + spacing + width
            end

            for rowIndex, row in ipairs(rows) do
                local xOffset = 0
                local yOffset = -((rowIndex - 1) * (rowHeight + rowSpacing))
                for _, buttonIndex in ipairs(row) do
                    local button = buttons[buttonIndex]
                    PaintButton(button, widths[buttonIndex], activeKey, onClick, xOffset, yOffset)
                    xOffset = xOffset + widths[buttonIndex] + buttonSpacing
                end
            end

            local totalRows = #rows
            strip:SetHeight(totalRows * rowHeight + math.max(0, totalRows - 1) * rowSpacing)
            return
        end

        local xOffset = 0
        for index in ipairs(tabs) do
            local button = buttons[index]
            PaintButton(button, widths[index], activeKey, onClick, xOffset, 0)
            xOffset = xOffset + widths[index] + buttonSpacing
        end

        strip:SetHeight(rowHeight)
    end

    return strip, Paint
end

local function CreateTabRepainter(options, paintTabs, RenderActive)
    local repainting = false
    local function RepaintTabs()
        if options.preventReentry and repainting then
            return
        end
        repainting = true

        local tabs = type(options.getTabs) == "function" and options.getTabs() or {}
        local activeTab = type(options.getActiveTab) == "function" and options.getActiveTab() or nil
        if type(options.normalizeActiveTab) == "function" then
            local normalized = options.normalizeActiveTab(tabs, activeTab)
            if normalized ~= nil and normalized ~= activeTab and type(options.setActiveTab) == "function" then
                options.setActiveTab(normalized)
                activeTab = normalized
            end
        end

        local function HandleTabClick(tabKey, previousActiveTab)
            if tabKey == previousActiveTab then
                return
            end
            if type(options.setActiveTab) == "function" then
                options.setActiveTab(tabKey)
            end
            if type(options.onTabChanged) == "function" then
                options.onTabChanged(tabKey)
            end
            repainting = false
            RepaintTabs()
            RenderActive(false)
        end

        paintTabs(tabs, activeTab, function(tabKey)
            return HandleTabClick(tabKey, activeTab)
        end)

        repainting = false
    end

    local function RepaintAndRender(force)
        RepaintTabs()
        RenderActive(force ~= false)
    end

    return RepaintTabs, RepaintAndRender
end

function FullSurface.BuildScrollTabBody(body, options)
    options = options or {}

    local clearFrame = options.clearFrame or FullSurface.ClearFrame
    local cacheTabBodies = options.cacheTabBodies == true
    if clearFrame then
        clearFrame(body)
    end

    if type(options.initialize) == "function" then
        options.initialize()
    end

    local pad = options.padding or 8
    local tabTop = options.tabTopOffset or -4
    local contentTop = options.contentTopOffset or -8
    local contentRight = options.contentRightPadding or pad
    local contentBottom = options.contentBottomPadding or pad

    local createTabStrip = options.createTabStrip or function(parent)
        return FullSurface.CreateTabStrip(parent, options.tabStripOptions)
    end

    local tabStrip, paintTabs = createTabStrip(body)
    tabStrip:SetPoint("TOPLEFT", body, "TOPLEFT", pad, tabTop)
    tabStrip:SetPoint("RIGHT", body, "RIGHT", -pad, 0)

    local scrollWrap = CreateFrame("Frame", nil, body)
    scrollWrap:SetPoint("TOPLEFT", tabStrip, "BOTTOMLEFT", 0, contentTop)
    scrollWrap:SetPoint("BOTTOMRIGHT", body, "BOTTOMRIGHT", -contentRight, contentBottom)

    local scrollContent
    if not cacheTabBodies and ns.QUI_Options and ns.QUI_Options.CreateScrollableContent then
        local _scrollFrame
        _scrollFrame, scrollContent = ns.QUI_Options.CreateScrollableContent(scrollWrap)
    end

    local state = type(options.state) == "table" and options.state or nil
    local tabBodyCache = {}

    local function GetTabCacheKey(tabKey)
        local key = (tabKey == nil) and "__nil" or tostring(tabKey)
        if type(options.resolveVariantKey) == "function" then
            local variant = options.resolveVariantKey(tabKey)
            if variant ~= nil then
                key = key .. "\31" .. tostring(variant)
            end
        end
        return key
    end

    local function CreateCachedTabBody(tabKey)
        local cacheKey = GetTabCacheKey(tabKey)
        local cached = tabBodyCache[cacheKey]
        if cached then
            return cached
        end

        local container = CreateFrame("Frame", nil, scrollWrap)
        container:SetAllPoints(scrollWrap)
        container:Hide()

        local content = container
        local scrollFrame
        if ns.QUI_Options and ns.QUI_Options.CreateScrollableContent then
            scrollFrame, content = ns.QUI_Options.CreateScrollableContent(container)
        end

        cached = {
            container = container,
            content = content or container,
            scrollFrame = scrollFrame,
            tabKey = tabKey,
            rendered = false,
        }
        tabBodyCache[cacheKey] = cached
        return cached
    end

    local function ShowCachedTabBody(tabKey)
        local cached = CreateCachedTabBody(tabKey)
        for _, info in pairs(tabBodyCache) do
            if info.container then
                if info == cached then
                    info.container:Show()
                else
                    info.container:Hide()
                end
            end
        end
        return cached
    end

    local function RenderCachedTabBody(tabKey, cached, force)
        local host = cached.content
        if force or not cached.rendered then
            if clearFrame then
                clearFrame(host)
            end
            if type(options.render) == "function" then
                options.render(host, tabKey, cached)
            end
            cached.rendered = true
        end
        return host
    end

    local function InvalidateCachedTabBodies(tabKey)
        if not cacheTabBodies then
            return
        end

        for _, cached in pairs(tabBodyCache) do
            if tabKey == nil or cached.tabKey == tabKey then
                cached.rendered = false
            end
        end
    end

    local function RenderActive(force)
        if cacheTabBodies then
            local activeTab = type(options.getActiveTab) == "function" and options.getActiveTab() or nil
            local cached = ShowCachedTabBody(activeTab)
            local host = RenderCachedTabBody(activeTab, cached, force)
            if state then
                state.activeBody = host
            end
            return
        end

        local host = scrollContent or scrollWrap
        if clearFrame then
            clearFrame(host)
        end
        if state then
            state.activeBody = host
        end
        if type(options.render) == "function" then
            options.render(host)
        end
    end

    local RepaintTabs, RepaintAndRender = CreateTabRepainter(options, paintTabs, RenderActive)

    if state then
        state.repaintTabs = RepaintAndRender
        state.invalidateTabBodies = InvalidateCachedTabBodies
    end

    if options.repaintOnSizeChanged then
        body:HookScript("OnSizeChanged", function()
            if options.deferResizeRepaint and C_Timer and C_Timer.After then
                C_Timer.After(0, RepaintTabs)
            else
                RepaintTabs()
            end
        end)
    end

    RepaintAndRender(true)

    return {
        tabStrip = tabStrip,
        scrollWrap = scrollWrap,
        scrollContent = scrollContent,
        RepaintTabs = RepaintTabs,
        RenderActive = RenderActive,
        InvalidateCachedTabBodies = InvalidateCachedTabBodies,
    }
end

function FullSurface.BuildMultiHostTabBody(body, options)
    options = options or {}

    local clearFrame = options.clearFrame or FullSurface.ClearFrame
    local cacheTabBodies = options.cacheTabBodies == true
    if clearFrame then
        clearFrame(body)
    end

    if type(options.initialize) == "function" then
        options.initialize()
    end

    local pad = options.padding or 8
    local tabTop = options.tabTopOffset or -4
    local contentTop = options.contentTopOffset or -8
    local contentRight = options.contentRightPadding or pad
    local contentBottom = options.contentBottomPadding or pad

    local createTabStrip = options.createTabStrip or function(parent)
        return FullSurface.CreateTabStrip(parent, options.tabStripOptions)
    end

    local tabStrip, paintTabs = createTabStrip(body)
    tabStrip:SetPoint("TOPLEFT", body, "TOPLEFT", pad, tabTop)
    tabStrip:SetPoint("RIGHT", body, "RIGHT", -pad, 0)

    local hosts = {}
    if not cacheTabBodies then
        for hostKey, definition in pairs(options.hosts or {}) do
            local container = CreateFrame("Frame", nil, body)
            container:SetPoint("TOPLEFT", tabStrip, "BOTTOMLEFT", 0, contentTop)
            container:SetPoint("BOTTOMRIGHT", body, "BOTTOMRIGHT", -contentRight, contentBottom)
            container:Hide()

            local content = container
            if definition.kind == "scroll" and ns.QUI_Options and ns.QUI_Options.CreateScrollableContent then
                local _scrollFrame
                _scrollFrame, content = ns.QUI_Options.CreateScrollableContent(container)
            end

            hosts[hostKey] = {
                container = container,
                content = content or container,
                clearFrame = definition.clearFrame or clearFrame,
            }
        end
    end

    local state = type(options.state) == "table" and options.state or nil
    local tabBodyCache = {}

    local function ResolveHostKey(activeTab)
        return type(options.resolveHostKey) == "function"
            and options.resolveHostKey(activeTab) or options.defaultHostKey
    end

    local function GetTabCacheKey(tabKey, hostKey)
        return tostring(hostKey or "__host") .. "\31" .. tostring(tabKey or "__nil")
    end

    local function CreateCachedHost(activeTab, activeHostKey)
        local cacheKey = GetTabCacheKey(activeTab, activeHostKey)
        local cached = tabBodyCache[cacheKey]
        if cached then
            return cached
        end

        local definitions = options.hosts or {}
        local definition = definitions[activeHostKey] or definitions[options.defaultHostKey] or {}
        local container = CreateFrame("Frame", nil, body)
        container:SetPoint("TOPLEFT", tabStrip, "BOTTOMLEFT", 0, contentTop)
        container:SetPoint("BOTTOMRIGHT", body, "BOTTOMRIGHT", -contentRight, contentBottom)
        container:Hide()

        local content = container
        if definition.kind == "scroll" and ns.QUI_Options and ns.QUI_Options.CreateScrollableContent then
            local _scrollFrame
            _scrollFrame, content = ns.QUI_Options.CreateScrollableContent(container)
        end

        cached = {
            container = container,
            content = content or container,
            clearFrame = definition.clearFrame or clearFrame,
            hostKey = activeHostKey,
            tabKey = activeTab,
            rendered = false,
        }
        tabBodyCache[cacheKey] = cached
        return cached
    end

    local function ShowCachedHost(activeTab, activeHostKey)
        local cached = CreateCachedHost(activeTab, activeHostKey)
        for _, info in pairs(tabBodyCache) do
            if info.container then
                if info == cached then
                    info.container:Show()
                else
                    info.container:Hide()
                end
            end
        end
        return cached
    end

    local function RenderCachedHost(activeTab, activeHostKey, cached, force)
        if force or not cached.rendered then
            if cached.clearFrame then
                cached.clearFrame(cached.content)
            end
            if type(options.render) == "function" then
                options.render(cached.content, activeTab, activeHostKey, cached)
            end
            cached.rendered = true
        end
        return cached.content
    end

    local function InvalidateCachedTabBodies(tabKey)
        if not cacheTabBodies then
            return
        end

        for _, cached in pairs(tabBodyCache) do
            if tabKey == nil or cached.tabKey == tabKey then
                cached.rendered = false
            end
        end
    end

    local function RenderActive(force)
        local activeTab = type(options.getActiveTab) == "function" and options.getActiveTab() or nil
        local activeHostKey = ResolveHostKey(activeTab)

        if cacheTabBodies then
            local cached = ShowCachedHost(activeTab, activeHostKey)
            local host = RenderCachedHost(activeTab, activeHostKey, cached, force)
            if state then
                state.activeBody = host
            end
            return
        end

        local hostInfo = hosts[activeHostKey] or hosts[options.defaultHostKey]
        if not hostInfo then
            return
        end

        for hostKey, info in pairs(hosts) do
            if hostKey == activeHostKey then
                info.container:Show()
            else
                info.container:Hide()
            end
        end

        if hostInfo.clearFrame then
            hostInfo.clearFrame(hostInfo.content)
        end

        if state then
            state.activeBody = hostInfo.content
        end

        if type(options.render) == "function" then
            options.render(hostInfo.content, activeTab, activeHostKey, hostInfo)
        end
    end

    local RepaintTabs, RepaintAndRender = CreateTabRepainter(options, paintTabs, RenderActive)

    if state then
        state.repaintTabs = RepaintAndRender
        state.invalidateTabBodies = InvalidateCachedTabBodies
    end

    RepaintAndRender(true)

    return {
        tabStrip = tabStrip,
        hosts = hosts,
        RepaintTabs = RepaintTabs,
        RenderActive = RenderActive,
        InvalidateCachedTabBodies = InvalidateCachedTabBodies,
    }
end
