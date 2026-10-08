local _, ns = ...

local Settings = ns.Settings
local ProviderPanels = Settings and Settings.ProviderPanels
if not ProviderPanels or type(ProviderPanels.RegisterAfterLoad) ~= "function" then
    return
end

ProviderPanels:RegisterAfterLoad(function(ctx)
    local GUI = ctx.GUI
    local U = ctx.U

    local function MakeLayout(content)
        return ns.QUI_SettingsLayoutShared.MakeLayout(content, U)
    end

    local function row(parent, label, widget, desc)
        return ns.QUI_Options.BuildSettingRow(parent, label, widget, desc)
    end

    local function AttachDropdownTooltip(dd, description, title)
        if not GUI.AttachTooltip then return end
        GUI:AttachTooltip(dd, description, title)
        if dd.dropdown then GUI:AttachTooltip(dd.dropdown, description, title) end
    end

    local ZONE_DEFS = {
        { key = "left",   label = ns.L["Left Zone"] },
        { key = "center", label = ns.L["Center Zone"] },
        { key = "right",  label = ns.L["Right Zone"] },
    }

    local InfoBarPageState = {
        selectedWidget = nil,
        arrangementSelection = nil,
        removedWidget = nil,
        arrangementScroll = {},
    }

    local function EnsureInfoBarConfig(profile)
        if not profile.infobar then profile.infobar = {} end
        local db = profile.infobar
        if not db.zones then db.zones = {} end
        for _, zdef in ipairs(ZONE_DEFS) do
            if not db.zones[zdef.key] then db.zones[zdef.key] = {} end
        end
        if not db.widgetSettings then db.widgetSettings = {} end
        if not db.micromenu then db.micromenu = {} end
        if not db.micromenu.buttons then db.micromenu.buttons = {} end
        if not db.travel then db.travel = {} end
        return db
    end

    local EnsureWidgetSettings = ns.QUI_InfoBarShared.EnsureWidgetSettings

    local function GetWidgetDef(addon, widgetId)
        if addon and addon.Datatexts and type(addon.Datatexts.Get) == "function" then
            return addon.Datatexts:Get(widgetId)
        end
        return nil
    end

    local function GetWidgetDisplayName(addon, widgetId)
        local def = GetWidgetDef(addon, widgetId)
        if def and def.displayName and def.displayName ~= "" then
            return def.displayName
        end
        return tostring(widgetId)
    end

    local function GetAvailableWidgetOptions(addon, placedSet)
        local opts = {}
        if addon and addon.Datatexts and type(addon.Datatexts.GetAll) == "function" then
            for _, def in ipairs(addon.Datatexts:GetAll()) do
                if def and def.id and not placedSet[def.id] then
                    local text = def.displayName or def.id
                    if def.category == "Plugins" then
                        text = text .. " " .. ns.L["|cff999999(plugin)|r"]
                    end
                    opts[#opts + 1] = {
                        value = def.id,
                        text = text,
                    }
                end
            end
        end
        return opts
    end

    local function BuildPlacement(db)
        local placedSet, placedList = {}, {}
        for _, zdef in ipairs(ZONE_DEFS) do
            for _, widgetId in ipairs(db.zones[zdef.key]) do
                if not placedSet[widgetId] then
                    placedSet[widgetId] = true
                    placedList[#placedList + 1] = widgetId
                end
            end
        end
        return placedSet, placedList
    end

    local function RefreshInfoBar()
        if _G.QUI_RefreshInfoBar then _G.QUI_RefreshInfoBar() end
    end

    local function NotifyStructuralRefresh()
        local compat = ns.Settings and ns.Settings.RenderAdapters
        if compat and compat.NotifyProviderChanged then
            compat.NotifyProviderChanged("infobar", { structural = true })
        end
    end

    ctx.RegisterShared("infobar", { build = function(content, _key, _width)
        local profile = U.GetProfileDB()
        if not profile or not ns.QUI_Options then return 80 end

        local QUICore = ns.Addon
        local db = EnsureInfoBarConfig(profile)
        local placedSet, placedList = BuildPlacement(db)

        local L = MakeLayout(content)

        if ns.QUI_DatatextsRegistryNotice then
            ns.QUI_DatatextsRegistryNotice(L, content,
                ns.L["The Datatexts module addon is disabled — enable it under Modules to configure datatexts. The Info Bar's widget lists below are empty until it loads."])
        end

        L.headerAt(ns.L["General"])
        local g = L.sectionAt()

        local enW = GUI:CreateFormCheckbox(g.frame, nil, "enabled", db, function(enabled)
            if ns.QUI_Modules and type(ns.QUI_Modules.SetEnabled) == "function" then
                ns.QUI_Modules:SetEnabled("moduleFlag_infobar", enabled)
            end
            RefreshInfoBar()
        end,
            { description = ns.L["Show the full-width info bar. The Info Bar module itself must also be enabled on the Module Addons page."] })
        local posW = GUI:CreateFormDropdown(g.frame, nil, {
            { value = "TOP", text = ns.L["Top"] },
            { value = "BOTTOM", text = ns.L["Bottom"] },
        }, "position", db, RefreshInfoBar,
            { description = ns.L["Pin the bar to the top or the bottom edge of the screen."] })
        g.AddRow(row(g.frame, ns.L["Enable Info Bar"], enW), row(g.frame, ns.L["Bar Position"], posW))

        local hW = GUI:CreateFormSlider(g.frame, nil, 16, 40, 1, "height", db, RefreshInfoBar,
            { description = ns.L["Height of the bar in pixels."] })
        local fSizeW = GUI:CreateFormSlider(g.frame, nil, 9, 18, 1, "fontSize", db, RefreshInfoBar,
            { description = ns.L["Font size of every widget on the bar."] })
        g.AddRow(row(g.frame, ns.L["Bar Height"], hW), row(g.frame, ns.L["Font Size"], fSizeW))

        local bgW = GUI:CreateFormSlider(g.frame, nil, 0, 100, 5, "bgOpacity", db, RefreshInfoBar,
            { description = ns.L["Opacity of the bar background (0 transparent, 100 fully opaque)."] })
        local borSizeW = GUI:CreateFormSlider(g.frame, nil, 0, 4, 1, "borderSize", db, RefreshInfoBar,
            { description = ns.L["Thickness of the bar's screen-inner edge border. Set to 0 to hide it."] })
        g.AddRow(row(g.frame, ns.L["Background Opacity"], bgW), row(g.frame, ns.L["Border Size (0=hidden)"], borSizeW))

        local borSrcW, borColorW = ns.QUI_BorderControl.Attach(GUI, g.frame, db, "", RefreshInfoBar,
            { label = ns.L["Border Color Source"], colorLabel = ns.L["Border Color"],
              colorDescription = ns.L["Color of the bar's edge border."] })
        g.AddRow(row(g.frame, ns.L["Border Color Source"], borSrcW), row(g.frame, ns.L["Border Color"], borColorW))

        local spacingW = GUI:CreateFormSlider(g.frame, nil, 4, 30, 1, "widgetSpacing", db, RefreshInfoBar,
            { description = ns.L["Horizontal gap between widgets within a zone."] })
        local padW = GUI:CreateFormSlider(g.frame, nil, 0, 30, 1, "zonePadding", db, RefreshInfoBar,
            { description = ns.L["Inset between the screen edges and the left/right zones."] })
        g.AddRow(row(g.frame, ns.L["Widget Spacing"], spacingW), row(g.frame, ns.L["Zone Padding"], padW))
        L.closeSection(g)

        L.headerAt(ns.L["Visibility"])
        local vis = L.sectionAt()
        local fadeW = GUI:CreateFormCheckbox(vis.frame, nil, "mouseoverFade", db, RefreshInfoBar,
            { description = ns.L["Fade the bar out when the mouse is not over it."] })
        local restW = GUI:CreateFormSlider(vis.frame, nil, 0, 100, 5, "fadeRestOpacity", db, RefreshInfoBar,
            { description = ns.L["Bar opacity while faded out (0 invisible, 100 fully visible)."] })
        vis.AddRow(row(vis.frame, ns.L["Mouseover Fade"], fadeW), row(vis.frame, ns.L["Faded Opacity"], restW))

        local combatW = GUI:CreateFormCheckbox(vis.frame, nil, "hideInCombat", db, RefreshInfoBar,
            { description = ns.L["Hide the entire bar while you are in combat."] })
        vis.AddRow(row(vis.frame, ns.L["Hide in Combat"], combatW))
        L.closeSection(vis)

        L.headerAt(ns.L["Arrangement"])
        local editor = CreateFrame("Frame", nil, content)
        local dragGroup = {}
        local columns = {}
        local selected = InfoBarPageState.arrangementSelection
        local function Find(id)
            for _, z in ipairs(ZONE_DEFS) do
                for index, value in ipairs(db.zones[z.key]) do
                    if value == id then return z.key, index end
                end
            end
        end
        local function RefreshZone()
            RefreshInfoBar()
            NotifyStructuralRefresh()
        end
        local function Move(id, zone, gap)
            local driver = QUICore and QUICore.InfoBar and QUICore.InfoBar.DragReorder
            if driver and driver.MoveWidget(db, id, zone, gap) then
                InfoBarPageState.arrangementSelection = id
                RefreshZone()
            end
        end
        local preview = CreateFrame("Frame", nil, editor)
        preview:SetPoint("TOPLEFT", 0, 0)
        preview:SetPoint("TOPRIGHT", 0, 0)
        preview:SetHeight(70)
        ns.UIKit.CreateRoundedSurface(preview, {radius = 8,
            bgColor = GUI.Colors.bgContent, borderColor = GUI.Colors.border})
        local previewTitle = GUI:CreateLabel(preview, ns.L["Bar arrangement preview"], 11, GUI.Colors.textMuted)
        previewTitle:SetPoint("TOPLEFT", 10, -8)
        local previewParts = {}
        for _, z in ipairs(ZONE_DEFS) do
            local part = CreateFrame("Frame", nil, preview)
            local label = GUI:CreateLabel(part, "", 11)
            label:SetAllPoints(part)
            label:SetJustifyH(z.key == "center" and "CENTER" or z.key == "right" and "RIGHT" or "LEFT")
            label:SetWordWrap(false)
            local names = {}
            for i, id in ipairs(db.zones[z.key]) do
                if i <= 3 then names[#names + 1] = GetWidgetDisplayName(QUICore, id) end
            end
            if #db.zones[z.key] > 3 then names[#names + 1] = "+" .. (#db.zones[z.key] - 3) end
            label:SetText(#names > 0 and table.concat(names, "  |  ") or ns.L["Empty"])
            previewParts[#previewParts + 1] = part
        end
        local selectionText = GUI:CreateLabel(editor,
            selected and GetWidgetDisplayName(QUICore, selected) or ns.L["Select a widget to move or remove it."], 12)
        selectionText:SetPoint("TOPLEFT", 0, -82)
        selectionText:SetPoint("TOPRIGHT", 0, -82)
        selectionText:SetJustifyH("LEFT")
        selectionText:SetWordWrap(false)
        local selectedZone, selectedIndex = Find(selected)
        local up = GUI:CreateButton(editor, ns.L["Move up"], 76, 24, function()
            local zone, index = Find(InfoBarPageState.arrangementSelection)
            if zone and index > 1 then Move(InfoBarPageState.arrangementSelection, zone, index - 1) end
        end)
        up:SetPoint("TOPLEFT", 0, -106)
        up:SetEnabled(selectedIndex ~= nil and selectedIndex > 1)
        local down = GUI:CreateButton(editor, ns.L["Move down"], 86, 24, function()
            local zone, index = Find(InfoBarPageState.arrangementSelection)
            if zone and index < #db.zones[zone] then Move(InfoBarPageState.arrangementSelection, zone, index + 2) end
        end)
        down:SetPoint("LEFT", up, "RIGHT", 6, 0)
        down:SetEnabled(selectedZone ~= nil and selectedIndex < #db.zones[selectedZone])
        local moveOptions = {}
        for _, z in ipairs(ZONE_DEFS) do moveOptions[#moveOptions + 1] = {value = z.key, text = z.label} end
        local moveDD = GUI:CreateFormDropdown(editor, nil, moveOptions, nil, nil, function(zone)
            local id = InfoBarPageState.arrangementSelection
            if id and Find(id) then Move(id, zone, #db.zones[zone] + 1) end
        end, nil, {placeholder = ns.L["Move to zone"]})
        moveDD:SetWidth(140)
        moveDD:SetPoint("LEFT", down, "RIGHT", 8, 0)
        moveDD:SetEnabled(selectedZone ~= nil)
        local remove = GUI:CreateButton(editor, ns.L["Remove"], 72, 24, function()
            local id = InfoBarPageState.arrangementSelection
            local zone, index = Find(id)
            if not zone then return end
            InfoBarPageState.removedWidget = {id = id, zone = zone, index = index}
            table.remove(db.zones[zone], index)
            InfoBarPageState.arrangementSelection = nil
            RefreshZone()
        end)
        remove:SetPoint("LEFT", moveDD, "RIGHT", 8, 0)
        remove:SetEnabled(selectedZone ~= nil)
        local undo = GUI:CreateButton(editor, ns.L["Undo removal"], 100, 24, function()
            local removed = InfoBarPageState.removedWidget
            if not removed then return end
            if not Find(removed.id) then
                local list = db.zones[removed.zone]
                table.insert(list, math.min(removed.index, #list + 1), removed.id)
            end
            InfoBarPageState.arrangementSelection = removed.id
            InfoBarPageState.removedWidget = nil
            RefreshZone()
        end)
        undo:SetPoint("LEFT", remove, "RIGHT", 6, 0)
        undo:SetEnabled(InfoBarPageState.removedWidget ~= nil)
        local hint = GUI:CreateLabel(editor, ns.L["Drag by the handle to reorder or move between zones."], 11, GUI.Colors.textMuted)
        hint:SetPoint("TOPLEFT", 0, -142)
        local maxHeight = 0
        for _, zdef in ipairs(ZONE_DEFS) do
            local zoneKey = zdef.key
            local zoneList = db.zones[zoneKey]
            local zoneFrame = CreateFrame("Frame", nil, editor)
            ns.UIKit.CreateRoundedSurface(zoneFrame, {radius = 8,
                bgColor = GUI.Colors.bgContent, borderColor = GUI.Colors.border})
            columns[#columns + 1] = zoneFrame
            local title = GUI:CreateLabel(zoneFrame, zdef.label .. " (" .. #zoneList .. ")", 12)
            title:SetPoint("TOPLEFT", 10, -10)
            local addOpts = {{value = "", text = ns.L["Add widget..."]}}
            for _, opt in ipairs(GetAvailableWidgetOptions(QUICore, placedSet)) do addOpts[#addOpts + 1] = opt end
            local addDD = GUI:CreateFormDropdown(zoneFrame, nil, addOpts, nil, nil, function(id)
                if not id or id == "" or Find(id) then return end
                zoneList[#zoneList + 1] = id
                InfoBarPageState.arrangementSelection = id
                RefreshZone()
            end, nil, {searchable = true})
            addDD:SetPoint("TOPLEFT", 10, -34)
            addDD:SetPoint("TOPRIGHT", -10, -34)
            addDD:SetValue("", true)
            local viewport = CreateFrame("ScrollFrame", nil, zoneFrame)
            viewport:SetPoint("TOPLEFT", 8, -70)
            viewport:SetPoint("BOTTOMRIGHT", -16, 8)
            viewport:EnableMouseWheel(true)
            local listHost = CreateFrame("Frame", nil, viewport)
            listHost:SetPoint("TOPLEFT", 0, 0)
            viewport:SetScrollChild(listHost)
            viewport:HookScript("OnSizeChanged", function(self, width)
                if width and width > 0 then listHost:SetWidth(width) end
            end)
            local _, listHeight = ns.QUI_ReorderList.Build(listHost, 0, {
                items = zoneList, zone = zoneKey, dragGroup = dragGroup, dropOwner = viewport,
                cards = true, actionsInToolbar = true, rowHeight = 32, hideHint = true,
                selected = selected,
                identify = function(id) return id end,
                getLabel = function(id)
                    return GetWidgetDisplayName(QUICore, id), not GetWidgetDef(QUICore, id)
                end,
                getTooltip = function(id)
                    return GetWidgetDisplayName(QUICore, id),
                        GetWidgetDef(QUICore, id) and ns.L["Drag to reorder or select for more actions."] or ns.L["This widget's addon is not loaded."]
                end,
                onSelect = function(id)
                    InfoBarPageState.arrangementSelection = id
                    NotifyStructuralRefresh()
                end,
                onDrop = function(id, target, gap) Move(id, target.zone, gap) end,
                onChange = RefreshZone,
            })
            listHost:SetHeight(math.max(44, listHeight))
            if ns.UIKit.CreateScrollBar then
                ns.UIKit.CreateScrollBar(viewport, {width = 4, hitWidth = 12, offsetX = 8})
            end
            if #zoneList == 0 then
                local empty = GUI:CreateLabel(listHost, ns.L["Drop a widget here"], 11, GUI.Colors.textMuted)
                empty:SetPoint("TOPLEFT", 4, -8)
            end
            viewport:SetScript("OnMouseWheel", function(self, delta)
                local offset = math.max(0, math.min(math.max(0, listHeight - self:GetHeight()),
                    self:GetVerticalScroll() - delta * 32))
                self:SetVerticalScroll(offset)
                InfoBarPageState.arrangementScroll[zoneKey] = offset
            end)
            viewport:SetVerticalScroll(InfoBarPageState.arrangementScroll[zoneKey] or 0)
            maxHeight = 410
        end
        local UpdateContentHeight
        local toolbarWidth = up:GetWidth() + down:GetWidth() + moveDD:GetWidth() + remove:GetWidth() + undo:GetWidth() + 28
        local function LayoutArrangement()
            local width = editor:GetWidth()
            if not width or width <= 0 then return end
            local extraHeight = width < toolbarWidth and 32 or 0
            remove:ClearAllPoints()
            if extraHeight > 0 then
                remove:SetPoint("TOPLEFT", editor, "TOPLEFT", 0, -138)
            else
                remove:SetPoint("LEFT", moveDD, "RIGHT", 8, 0)
            end
            hint:ClearAllPoints()
            hint:SetPoint("TOPLEFT", 0, -142 - extraHeight)
            local height = maxHeight + 172 + extraHeight
            if editor:GetHeight() ~= height then
                editor:SetHeight(height)
                if UpdateContentHeight then UpdateContentHeight() end
            end
            local columnWidth = (width - 20) / 3
            for index, column in ipairs(columns) do
                column:ClearAllPoints()
                column:SetPoint("TOPLEFT", editor, "TOPLEFT", (index - 1) * (columnWidth + 10), -164 - extraHeight)
                column:SetSize(columnWidth, maxHeight)
                local part = previewParts[index]
                part:ClearAllPoints()
                part:SetPoint("TOPLEFT", preview, "TOPLEFT", 10 + (index - 1) * (columnWidth + 10), -32)
                part:SetSize(columnWidth - 20, 26)
            end
        end
        editor:SetScript("OnSizeChanged", LayoutArrangement)
        local editorWidth = content:GetWidth() - 2 * (ns.QUI_Options.PADDING or 15)
        L.placeCustom(editor, maxHeight + 172 + (editorWidth < toolbarWidth and 32 or 0))
        LayoutArrangement()

        if U and U._layoutModePositionOnly then
            L.relayoutSections()
            return content:GetHeight()
        end
        local precedingHeight = -L.getY() - editor:GetHeight()
        local remaining = CreateFrame("Frame", nil, content)
        local padding = ns.QUI_Options.PADDING or 15
        remaining:SetPoint("TOPLEFT", editor, "BOTTOMLEFT", -padding, -14)
        remaining:SetPoint("TOPRIGHT", editor, "BOTTOMRIGHT", padding, -14)
        L = ns.QUI_SettingsLayoutShared.MakeLayout(remaining, U, 0)

        L.headerAt(ns.L["Widget Overrides"])
        if #placedList > 0 then
            local selected = InfoBarPageState.selectedWidget
            local selectedValid = false
            for _, widgetId in ipairs(placedList) do
                if widgetId == selected then
                    selectedValid = true
                    break
                end
            end
            if not selectedValid then
                selected = placedList[1]
                InfoBarPageState.selectedWidget = selected
            end

            local ov = L.sectionAt()
            local selOpts = {}
            for _, widgetId in ipairs(placedList) do
                selOpts[#selOpts + 1] = {
                    value = widgetId,
                    text = GetWidgetDisplayName(QUICore, widgetId),
                }
            end
            local selDD = GUI:CreateFormDropdown(ov.frame, nil, selOpts, nil, nil, function(val)
                if not val or val == InfoBarPageState.selectedWidget then return end
                InfoBarPageState.selectedWidget = val
                NotifyStructuralRefresh()
            end, { description = ns.L["Pick which placed widget the overrides below apply to."] }, { searchable = true })
            AttachDropdownTooltip(selDD, ns.L["Pick which placed widget the overrides below apply to."], ns.L["Widget"])
            if selDD.SetValue then selDD:SetValue(selected, true) end
            ov.AddRow(row(ov.frame, ns.L["Widget"], selDD))

            local ws = EnsureWidgetSettings(db, selected)
            local shortW = GUI:CreateFormCheckbox(ov.frame, nil, "shortLabel", ws, RefreshInfoBar,
                { description = ns.L["Use the compact label variant for this widget."] })
            local noLabelW = GUI:CreateFormCheckbox(ov.frame, nil, "noLabel", ws, RefreshInfoBar,
                { description = ns.L["Hide the label and show only the value for this widget."] })
            ov.AddRow(row(ov.frame, ns.L["Short Label"], shortW), row(ov.frame, ns.L["No Label"], noLabelW))

            local minWidthW = GUI:CreateFormSlider(ov.frame, nil, 0, 300, 1, "minWidth", ws, RefreshInfoBar,
                { description = ns.L["Minimum width reserved for this widget in pixels. 0 sizes to content."] })
            ov.AddRow(row(ov.frame, ns.L["Minimum Width"], minWidthW))

            local xOffsetW = GUI:CreateFormSlider(ov.frame, nil, -50, 50, 1, "xOffset", ws, RefreshInfoBar,
                { description = ns.L["Horizontal nudge for this widget in pixels. Positive moves it toward the right edge of the screen; neighbor spacing is unaffected."] })
            ov.AddRow(row(ov.frame, ns.L["X Offset"], xOffsetW))

            local hideIconW = GUI:CreateFormCheckbox(ov.frame, nil, "hideIcon", ws, RefreshInfoBar,
                { description = ns.L["Hide this widget's inline icon and keep the text. Not applied to icon-only widgets (Micro Menu, Travel) — hiding their icon would blank them."] })
            local hideTextW = GUI:CreateFormCheckbox(ov.frame, nil, "hideText", ws, RefreshInfoBar,
                { description = ns.L["Hide this widget's text and keep only its icon. Text-only widgets (FPS, Gold, …) become blank."] })
            ov.AddRow(row(ov.frame, ns.L["Hide Icon"], hideIconW), row(ov.frame, ns.L["Hide Text (icon only)"], hideTextW))
            local clickThroughW = GUI:CreateFormCheckbox(ov.frame, nil, "clickThrough", ws, RefreshInfoBar,
                { description = ns.L["Disable clicks and tooltips for this widget. Targets text datatexts; Micro Menu and Travel buttons keep their own mouse input."] })
            ov.AddRow(row(ov.frame, ns.L["Click-Through (no clicks or tooltip)"], clickThroughW))
            L.closeSection(ov)
        else
            local noteRow = CreateFrame("Frame", nil, remaining)
            local note = noteRow:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            note:SetPoint("LEFT", noteRow, "LEFT", 0, 0)
            note:SetTextColor(0.6, 0.6, 0.6, 0.8)
            note:SetText(ns.L["Place a widget in a zone to configure per-widget overrides."])
            L.placeCustom(noteRow, 18)
        end

        if placedSet["currencies"] and ns.QUI_BuildCurrencyOrderSection then
            if not profile.datatext then profile.datatext = {} end
            ns.QUI_BuildCurrencyOrderSection(L, remaining, {
                dtGlobal = profile.datatext,
                refresh = function()
                    RefreshInfoBar()
                    if QUICore and QUICore.Datatexts and QUICore.Datatexts.UpdateAll then
                        QUICore.Datatexts:UpdateAll()
                    end
                end,
                notify = function(_region) NotifyStructuralRefresh() end,
                note = ns.L["Order and visibility apply everywhere the Currencies datatext is shown, including datatext panels."],
            })
        end

        if placedSet["alts"] then
            if not profile.datatext then profile.datatext = {} end
            L.headerAt(ns.L["Alts Options"])
            local al = L.sectionAt()
            local altW = GUI:CreateFormDropdown(al.frame, nil, {
                { value = "gold", text = ns.L["Total Gold"] },
                { value = "count", text = ns.L["Alt Count"] },
            }, "altsMode", profile.datatext, function()
                RefreshInfoBar()
                if QUICore and QUICore.Datatexts and QUICore.Datatexts.UpdateAll then
                    QUICore.Datatexts:UpdateAll()
                end
            end, { description = ns.L["What the Alts datatext shows on the bar: total gold across your tracked alts, or the number of tracked alts. The tooltip always lists every alt. Applies everywhere the Alts datatext is shown, including datatext panels."] })
            al.AddRow(row(al.frame, ns.L["Bar Text"], altW))
            L.closeSection(al)
        end

        L.headerAt(ns.L["Micro Menu"])
        local mmButtons = db.micromenu.buttons
        local mm = L.sectionAt()
        local function mmCheckbox(buttonKey, buttonLabel)
            return GUI:CreateFormCheckbox(mm.frame, nil, buttonKey, mmButtons, RefreshInfoBar,
                { description = ns.L["Show the %1$s button in the Micro Menu widget."]:format(buttonLabel) })
        end
        mm.AddRow(row(mm.frame, ns.L["Character"], mmCheckbox("character", ns.L["Character"])),
            row(mm.frame, ns.L["Spellbook"], mmCheckbox("spellbook", ns.L["Spellbook"])))
        local progressKey = ns.Client and ns.Client.isForever and "legacy" or "achievements"
        local progressLabel = progressKey == "legacy" and ns.L["Legacy"] or ns.L["Achievements"]
        mm.AddRow(row(mm.frame, ns.L["Talents"], mmCheckbox("talents", ns.L["Talents"])),
            row(mm.frame, progressLabel, mmCheckbox(progressKey, progressLabel)))
        mm.AddRow(row(mm.frame, ns.L["Professions"], mmCheckbox("professions", ns.L["Professions"])),
            row(mm.frame, ns.L["Quest Log"], mmCheckbox("questlog", ns.L["Quest Log"])))
        mm.AddRow(row(mm.frame, ns.L["Collections"], mmCheckbox("collections", ns.L["Collections"])),
            row(mm.frame, ns.L["Group Finder"], mmCheckbox("lfg", ns.L["Group Finder"])))
        mm.AddRow(row(mm.frame, ns.L["Housing"], mmCheckbox("housing", ns.L["Housing"])),
            row(mm.frame, ns.L["Adventure Guide"], mmCheckbox("adventureguide", ns.L["Adventure Guide"])))
        mm.AddRow(row(mm.frame, ns.L["Shop"], mmCheckbox("shop", ns.L["Shop"])),
            row(mm.frame, ns.L["Support"], mmCheckbox("help", ns.L["Support"])))
        L.closeSection(mm)

        L.headerAt(ns.L["Travel"])
        local tv = L.sectionAt()
        local hearthW = GUI:CreateFormCheckbox(tv.frame, nil, "useRandomHearth", db.travel, RefreshInfoBar,
            { description = ns.L["Clicking the Travel widget's hearth uses a random owned hearthstone toy instead of the standard Hearthstone."] })
        tv.AddRow(row(tv.frame, ns.L["Random Hearthstone Toy"], hearthW))
        L.closeSection(tv)

        L.relayoutSections()
        UpdateContentHeight = function()
            local height = precedingHeight + editor:GetHeight() + remaining:GetHeight()
            if content:GetHeight() ~= height then content:SetHeight(height) end
        end
        remaining:SetScript("OnSizeChanged", UpdateContentHeight)
        UpdateContentHeight()
        return content:GetHeight()
    end })
end)
