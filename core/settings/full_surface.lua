local ADDON_NAME, ns = ...

local Settings = ns.Settings or {}
ns.Settings = Settings

local FullSurface = Settings.FullSurface or {}
Settings.FullSurface = FullSurface

local function ResolveAccent(options)
    local accent = type(options) == "table" and options.accent or nil
    if type(accent) == "table" then
        return accent[1] or 1, accent[2] or 1, accent[3] or 1
    end
    return 0.2, 0.83, 0.6
end

function FullSurface.ClearFrame(frame)
    if not frame then
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
            definition.text or definition.label or "Action",
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

    local headerRow = CreateFrame("Frame", nil, parent)
    headerRow:SetHeight(headerHeight)
    headerRow:SetPoint("TOPLEFT", pad, headerTop)
    headerRow:SetPoint("TOPRIGHT", -pad, headerTop)

    local actions = FullSurface.BuildHeaderActions(headerRow, {
        gui = gui,
        state = options.state,
        actions = options.headerActions,
        buttonGap = options.headerActionGap,
        leftGap = options.headerActionLeftGap,
        rightInset = options.headerActionRightInset,
    })

    local dropdownStateKey = options.dropdownStateKey or "_selection"
    local dropdownDB = {
        [dropdownStateKey] = options.selectedValue,
    }

    local dropdownRightInset = options.dropdownRightInset or 0
    if actions.width > 0 then
        dropdownRightInset = math.max(dropdownRightInset, actions.width + actions.leftGap)
    end

    local dropdown = gui:CreateFormDropdown(
        headerRow,
        options.dropdownLabel or "Selection",
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

    local previewHost = CreateFrame("Frame", nil, parent)
    previewHost:SetPoint("TOPLEFT", headerRow, "BOTTOMLEFT", 0, previewGap)
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
            actions = actions.buttons,
        })
    end

    return {
        headerRow = headerRow,
        dropdown = dropdown,
        dropdownDB = dropdownDB,
        previewHost = previewHost,
        actions = actions.buttons,
    }
end

function FullSurface.CreateTabStrip(parent, options)
    options = options or {}

    local rowHeight = options.rowHeight or 28
    local rowSpacing = options.rowSpacing or 6
    local buttonSpacing = options.buttonSpacing or 16
    local buttonPadding = options.buttonPadding or 24
    local labelSize = options.labelSize or 11
    local wrapRows = options.wrapRows == true
    local fallbackWidth = options.fallbackWidth or 780
    local accentR, accentG, accentB = ResolveAccent(options)

    local strip = CreateFrame("Frame", nil, parent)
    strip:SetHeight(rowHeight)

    local underline = strip:CreateTexture(nil, "OVERLAY")
    underline:SetPoint("BOTTOMLEFT", 0, 0)
    underline:SetPoint("BOTTOMRIGHT", 0, 0)
    underline:SetHeight(1)
    underline:SetColorTexture(0.22, 0.22, 0.22, 1)

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
        label:SetFont(fontPath, labelSize, fontFlags or "")
        button._label = label

        local activeBar = button:CreateTexture(nil, "OVERLAY")
        activeBar:SetPoint("BOTTOMLEFT", 4, 0)
        activeBar:SetPoint("BOTTOMRIGHT", -4, 0)
        activeBar:SetHeight(2)
        activeBar:SetColorTexture(accentR, accentG, accentB, 1)
        activeBar:Hide()
        button._activeBar = activeBar

        buttons[index] = button
        return button
    end

    local function PaintButton(button, width, activeKey, onClick, xOffset, yOffset)
        button:SetWidth(width)
        button:ClearAllPoints()

        if wrapRows then
            button:SetPoint("TOPLEFT", strip, "TOPLEFT", xOffset, yOffset)
        else
            button:SetPoint("LEFT", strip, "LEFT", xOffset, 0)
        end

        if button._tabKey == activeKey then
            button._label:SetTextColor(1, 1, 1, 1)
            button._activeBar:Show()
        else
            button._label:SetTextColor(0.6, 0.6, 0.6, 1)
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

function FullSurface.BuildScrollTabBody(body, options)
    options = options or {}

    local clearFrame = options.clearFrame or FullSurface.ClearFrame
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
    if ns.QUI_Options and ns.QUI_Options.CreateScrollableContent then
        _, scrollContent = ns.QUI_Options.CreateScrollableContent(scrollWrap)
    end

    local state = type(options.state) == "table" and options.state or nil

    local function RenderActive()
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

        paintTabs(tabs, activeTab, function(tabKey)
            if tabKey == activeTab then
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
            RenderActive()
        end)

        repainting = false
    end

    local function RepaintAndRender()
        RepaintTabs()
        RenderActive()
    end

    if state then
        state.repaintTabs = RepaintAndRender
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

    RepaintAndRender()

    return {
        tabStrip = tabStrip,
        scrollWrap = scrollWrap,
        scrollContent = scrollContent,
        RepaintTabs = RepaintTabs,
        RenderActive = RenderActive,
    }
end

function FullSurface.BuildMultiHostTabBody(body, options)
    options = options or {}

    local clearFrame = options.clearFrame or FullSurface.ClearFrame
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
    for hostKey, definition in pairs(options.hosts or {}) do
        local container = CreateFrame("Frame", nil, body)
        container:SetPoint("TOPLEFT", tabStrip, "BOTTOMLEFT", 0, contentTop)
        container:SetPoint("BOTTOMRIGHT", body, "BOTTOMRIGHT", -contentRight, contentBottom)
        container:Hide()

        local content = container
        if definition.kind == "scroll" and ns.QUI_Options and ns.QUI_Options.CreateScrollableContent then
            _, content = ns.QUI_Options.CreateScrollableContent(container)
        end

        hosts[hostKey] = {
            container = container,
            content = content or container,
            clearFrame = definition.clearFrame or clearFrame,
        }
    end

    local state = type(options.state) == "table" and options.state or nil

    local function RenderActive()
        local activeTab = type(options.getActiveTab) == "function" and options.getActiveTab() or nil
        local activeHostKey = type(options.resolveHostKey) == "function"
            and options.resolveHostKey(activeTab) or options.defaultHostKey
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

        paintTabs(tabs, activeTab, function(tabKey)
            if tabKey == activeTab then
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
            RenderActive()
        end)

        repainting = false
    end

    local function RepaintAndRender()
        RepaintTabs()
        RenderActive()
    end

    if state then
        state.repaintTabs = RepaintAndRender
    end

    RepaintAndRender()

    return {
        tabStrip = tabStrip,
        hosts = hosts,
        RepaintTabs = RepaintTabs,
        RenderActive = RenderActive,
    }
end
