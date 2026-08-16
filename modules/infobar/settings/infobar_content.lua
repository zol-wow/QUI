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

    local function GetAccent()
        local QGUI = _G.QUI and _G.QUI.GUI
        if QGUI and QGUI.Colors and QGUI.Colors.accent then
            return QGUI.Colors.accent[1], QGUI.Colors.accent[2], QGUI.Colors.accent[3]
        end
        return 0.376, 0.647, 0.980
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

        local ZONE_ROW_HEIGHT = 26
        for _, zdef in ipairs(ZONE_DEFS) do
            local zoneList = db.zones[zdef.key]

            L.headerAt(zdef.label)
            local zoneFrame = CreateFrame("Frame", nil, content)

            local hintFs = zoneFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            hintFs:SetPoint("TOPLEFT", zoneFrame, "TOPLEFT", 4, -4)
            hintFs:SetPoint("RIGHT", zoneFrame, "RIGHT", -4, 0)
            hintFs:SetJustifyH("LEFT")
            hintFs:SetTextColor(0.6, 0.6, 0.6, 0.8)
            hintFs:SetText(#zoneList > 0
                and ns.L["Drag a row (or use the arrows) to reorder; x removes the widget from the bar."]
                or ns.L["No widgets in this zone. Add one below."])

            local accR, accG, accB = GetAccent()
            local ZONE_LIST_TOP = 24

            local dropLine = zoneFrame:CreateTexture(nil, "OVERLAY")
            dropLine:SetHeight(2)
            dropLine:SetColorTexture(accR, accG, accB, 0.9)
            if ns.UIKit and ns.UIKit.DisablePixelSnap then
                ns.UIKit.DisablePixelSnap(dropLine)
            end
            dropLine:Hide()

            local function DropGapFromCursor()
                local top = zoneFrame:GetTop()
                if not top then return 1 end
                local _, cursorY = GetCursorPosition()
                cursorY = cursorY / zoneFrame:GetEffectiveScale()
                local offset = (top - cursorY) - ZONE_LIST_TOP
                local gap = math.floor(offset / ZONE_ROW_HEIGHT + 0.5) + 1
                if gap < 1 then gap = 1 end
                if gap > #zoneList + 1 then gap = #zoneList + 1 end
                return gap
            end

            local ry = -ZONE_LIST_TOP
            for idx, widgetId in ipairs(zoneList) do
                local r = CreateFrame("Frame", nil, zoneFrame)
                r:SetHeight(ZONE_ROW_HEIGHT - 4)
                r:SetPoint("TOPLEFT", zoneFrame, "TOPLEFT", 0, ry)
                r:SetPoint("RIGHT", zoneFrame, "RIGHT", 0, 0)

                local nameFs = r:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                nameFs:SetPoint("LEFT", r, "LEFT", 4, 0)
                nameFs:SetPoint("RIGHT", r, "RIGHT", -70, 0)
                nameFs:SetJustifyH("LEFT")
                if GetWidgetDef(QUICore, widgetId) then
                    nameFs:SetText(GetWidgetDisplayName(QUICore, widgetId))
                    nameFs:SetTextColor(0.9, 0.9, 0.9, 1)
                else
                    nameFs:SetText(tostring(widgetId) .. " " .. ns.L["(not loaded)"])
                    nameFs:SetTextColor(0.6, 0.6, 0.6, 1)
                end

                local hoverBg = r:CreateTexture(nil, "BACKGROUND")
                hoverBg:SetAllPoints()
                hoverBg:SetColorTexture(accR, accG, accB, 0.08)
                hoverBg:Hide()

                local function makeRowButton(text, xOff, tip)
                    local btn = CreateFrame("Button", nil, r)
                    btn:SetSize(16, 16)
                    btn:SetPoint("RIGHT", r, "RIGHT", xOff, 0)
                    btn:SetNormalFontObject("GameFontNormalSmall")
                    btn:SetText(text)
                    btn:GetFontString():SetTextColor(accR, accG, accB, 1)
                    btn:SetScript("OnEnter", function(self)
                        hoverBg:Show()
                        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                        GameTooltip:SetText(tip, 1, 1, 1)
                        GameTooltip:Show()
                    end)
                    btn:SetScript("OnLeave", function()
                        GameTooltip:Hide()
                        if not r:IsMouseOver() then hoverBg:Hide() end
                    end)
                    return btn
                end

                local capturedId = widgetId
                local function findCurrentIndex()
                    for i, id in ipairs(zoneList) do
                        if id == capturedId then return i end
                    end
                    return nil
                end

                r:EnableMouse(true)
                r:RegisterForDrag("LeftButton")
                r:SetScript("OnEnter", function(self)
                    hoverBg:Show()
                    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                    GameTooltip:SetText(GetWidgetDisplayName(QUICore, capturedId), accR, accG, accB)
                    GameTooltip:AddLine(ns.L["Drag to reorder within this zone, or use the arrows."], 1, 1, 1, true)
                    GameTooltip:Show()
                end)
                r:SetScript("OnLeave", function(self)
                    GameTooltip:Hide()
                    if not self:IsMouseOver() then hoverBg:Hide() end
                end)
                r:SetScript("OnDragStart", function(self)
                    GameTooltip:Hide()
                    self:SetAlpha(0.4)
                    dropLine:Show()
                    self:SetScript("OnUpdate", function()
                        local gap = DropGapFromCursor()
                        dropLine:ClearAllPoints()
                        dropLine:SetPoint("TOPLEFT", zoneFrame, "TOPLEFT", 0,
                            -(ZONE_LIST_TOP + (gap - 1) * ZONE_ROW_HEIGHT) + 1)
                        dropLine:SetPoint("RIGHT", zoneFrame, "RIGHT", -4, 0)
                    end)
                end)
                r:SetScript("OnDragStop", function(self)
                    self:SetScript("OnUpdate", nil)
                    self:SetAlpha(1)
                    dropLine:Hide()
                    local gap = DropGapFromCursor()
                    local curIdx = findCurrentIndex()
                    if not curIdx then return end
                    local target = (gap > curIdx) and (gap - 1) or gap
                    if target ~= curIdx then
                        table.remove(zoneList, curIdx)
                        table.insert(zoneList, target, capturedId)
                        RefreshInfoBar()
                        NotifyStructuralRefresh()
                    end
                end)

                local upBtn = makeRowButton("^", -44, ns.L["Move up"])
                upBtn:SetScript("OnClick", function()
                    local curIdx = findCurrentIndex()
                    if curIdx and curIdx > 1 then
                        zoneList[curIdx], zoneList[curIdx - 1] =
                            zoneList[curIdx - 1], zoneList[curIdx]
                        RefreshInfoBar()
                        NotifyStructuralRefresh()
                    end
                end)
                upBtn:SetAlpha(idx > 1 and 1 or 0.3)

                local downBtn = makeRowButton("v", -24, ns.L["Move down"])
                downBtn:SetScript("OnClick", function()
                    local curIdx = findCurrentIndex()
                    if curIdx and curIdx < #zoneList then
                        zoneList[curIdx], zoneList[curIdx + 1] =
                            zoneList[curIdx + 1], zoneList[curIdx]
                        RefreshInfoBar()
                        NotifyStructuralRefresh()
                    end
                end)
                downBtn:SetAlpha(idx < #zoneList and 1 or 0.3)

                local removeBtn = makeRowButton("x", -4, ns.L["Remove from bar"])
                removeBtn:SetScript("OnClick", function()
                    local curIdx = findCurrentIndex()
                    if curIdx then
                        table.remove(zoneList, curIdx)
                        RefreshInfoBar()
                        NotifyStructuralRefresh()
                    end
                end)

                ry = ry - ZONE_ROW_HEIGHT
            end

            local addOpts = { { value = "", text = ns.L["Add widget..."] } }
            for _, opt in ipairs(GetAvailableWidgetOptions(QUICore, placedSet)) do
                addOpts[#addOpts + 1] = opt
            end
            local addDD = GUI:CreateFormDropdown(zoneFrame, nil, addOpts, nil, nil, function(val)
                if not val or val == "" then return end
                for _, widgetId in ipairs(zoneList) do
                    if widgetId == val then return end
                end
                zoneList[#zoneList + 1] = val
                RefreshInfoBar()
                NotifyStructuralRefresh()
            end, { description = ns.L["Add a widget to the end of this zone. Widgets already placed in any zone are not listed."] },
                { searchable = true })
            AttachDropdownTooltip(addDD,
                ns.L["Add a widget to the end of this zone. Widgets already placed in any zone are not listed."],
                ns.L["Add Widget"])
            addDD:SetPoint("TOPLEFT", zoneFrame, "TOPLEFT", 0, ry - 4)
            addDD:SetPoint("RIGHT", zoneFrame, "RIGHT", -4, 0)
            if addDD.SetValue then addDD:SetValue("", true) end

            local zoneHeight = 24 + (#zoneList * ZONE_ROW_HEIGHT) + 38
            L.placeCustom(zoneFrame, zoneHeight)
        end

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
            local noteRow = CreateFrame("Frame", nil, content)
            local note = noteRow:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            note:SetPoint("LEFT", noteRow, "LEFT", 0, 0)
            note:SetTextColor(0.6, 0.6, 0.6, 0.8)
            note:SetText(ns.L["Place a widget in a zone to configure per-widget overrides."])
            L.placeCustom(noteRow, 18)
        end

        if placedSet["currencies"] and ns.QUI_BuildCurrencyOrderSection then
            if not profile.datatext then profile.datatext = {} end
            ns.QUI_BuildCurrencyOrderSection(L, content, {
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
        mm.AddRow(row(mm.frame, ns.L["Talents"], mmCheckbox("talents", ns.L["Talents"])),
            row(mm.frame, ns.L["Achievements"], mmCheckbox("achievements", ns.L["Achievements"])))
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
        return content:GetHeight()
    end })
end)
