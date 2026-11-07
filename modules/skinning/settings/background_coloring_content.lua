local _, ns = ...
local GUI = QUI.GUI
local Shared = ns.QUI_Options
local Helpers = ns.Helpers
local Registry = ns.Settings.Registry
local Schema = ns.Settings.Schema

local function Refresh(name, ...)
    local callback = ns[name] or _G[name]
    if type(callback) == "function" then callback(...) end
end

local function BuildBackgroundColoringTab(content)
    local profile = Shared.GetDB()
    if not profile then return end
    GUI:SetSearchContext({
        tileId = "appearance", tabName = "Appearance", subPageIndex = 12,
        subTabName = "Background Coloring", featureId = "backgroundColoringPage", category = "appearance",
    })
    local layout = ns.QUI_SettingsLayoutShared.MakeLayout(content)
    local groupTitle, card, cells
    local function CloseGroup()
        if not card then return end
        for index = 1, #cells, 2 do
            card.AddRow(cells[index], cells[index + 1])
        end
        layout.closeSection(card)
    end
    local function Group(title)
        CloseGroup()
        groupTitle = title
        layout.headerAt(title)
        card = layout.sectionAt()
        cells = {}
    end
    local function Add(title, db, colorKey, refresh, opts)
        if type(db) ~= "table" then return end
        opts = opts or {}
        local function Row(label, widget)
            if title ~= groupTitle then label = title .. " " .. label end
            cells[#cells + 1] = Shared.BuildSettingRow(card.frame, label, widget)
        end
        local color, hide
        local function InheritedColor()
            local _, _, _, _, r, g, b, a = Helpers.GetWindowColors()
            return { r, g, b, a }
        end
        local function Sync()
            local overridden = not opts.override or db[opts.override]
            if hide then hide:SetEnabled(overridden) end
            if color then
                color:SetEnabled(overridden and (not opts.hide or not db[opts.hide])
                    and (not opts.style or db[opts.style] == "custom"))
            end
        end
        local function Changed()
            if opts.override and db[opts.override] and colorKey and db[colorKey] == nil then
                db[colorKey] = InheritedColor()
                color.UpdateVisual(db[colorKey])
            end
            Sync()
            refresh()
        end
        if opts.show then
            Row(ns.L["Show Background"], GUI:CreateFormCheckbox(card.frame, nil, opts.show, db, Changed))
        end
        if opts.override then
            Row(ns.L["Override Global Background"], GUI:CreateFormCheckbox(card.frame, nil, opts.override, db, Changed))
        end
        if opts.hide then
            hide = GUI:CreateFormCheckbox(card.frame, nil, opts.hide, db, Changed)
            Row(ns.L["Hide Background"], hide)
        end
        if opts.style then
            Row(ns.L["Background Style"], GUI:CreateFormDropdown(card.frame, nil, {
                { value = "theme", text = ns.L["Theme"] },
                { value = "custom", text = ns.L["Custom"] },
                { value = "transparent", text = ns.L["Transparent"] },
                { value = "blizzard", text = ns.L["Blizzard"] },
            }, opts.style, db, Changed))
        end
        if colorKey then
            color = GUI:CreateFormColorPicker(card.frame, nil, colorKey, db, Changed, { noAlpha = opts.noAlpha })
            if db[colorKey] == nil and opts.override then
                color.UpdateVisual(InheritedColor())
            end
            Row(title == groupTitle and ns.L["Background Color"] or ns.L["Color"], color)
        end
        if opts.opacity then
            Row(ns.L["Opacity"], GUI:CreateFormSlider(card.frame, nil, 0, opts.percent and 100 or 1,
                opts.percent and 5 or 0.05, opts.opacity, opts.opacityDB or db, refresh,
                { precision = opts.percent and 0 or 2, deferOnDrag = true }))
        end
        if opts.class then
            Row(ns.L["Class Color Background"], GUI:CreateFormCheckbox(card.frame, nil, opts.class, db, Changed))
        end
        Sync()
    end
    local function Callback(name)
        return function() Refresh(name) end
    end
    local function Override(title, db, prefix, refresh, opacity)
        Add(title, db, prefix == "" and "backgroundColor" or prefix .. "BackgroundColor", refresh, {
            override = prefix == "" and "bgOverride" or prefix .. "BgOverride",
            hide = prefix == "" and "hideBackground" or prefix .. "HideBackground", opacity = opacity,
        })
    end
    local general = profile.general
    Group(ns.L["Global Background"])
    Add(ns.L["Global Background"], general, "skinBgColor", function()
        if ns.Registry then ns.Registry:RefreshAll("skinning") end
        Refresh("QUI_RefreshStatusTrackingBarSkin")
    end)
    Group(ns.L["Skinning"])
    local chat = profile.chat
    Add(ns.L["Chat Background"], chat and chat.glass, "bgColor", Callback("QUI_RefreshChat"),
        { show = "enabled", opacity = "bgAlpha", noAlpha = true })
    Add(ns.L["Input Box Background"], chat and chat.editBox, "bgColor", Callback("QUI_RefreshChat"),
        { show = "enabled", opacity = "bgAlpha", noAlpha = true })
    Add(ns.L["Tooltip"], profile.tooltip, "bgColor", Callback("QUI_RefreshTooltipSkinColors"),
        { opacity = "bgOpacity", noAlpha = true })
    Add(ns.L["Objective Tracker"], general, "objectiveTrackerBackgroundColor", Callback("QUI_RefreshObjectiveTracker"),
        { opacity = "objectiveTrackerBackgroundOpacity", style = "objectiveTrackerBackgroundStyle", noAlpha = true })
    Override(ns.L["Status Tracking Bars"], general, "statusTrackingBars", Callback("QUI_RefreshStatusTrackingBarSkin"))
    Override(ns.L["Ready Check"], general, "readyCheck", Callback("QUI_RefreshReadyCheckColors"))
    Override(ns.L["Alert Frames"], general, "alerts", Callback("QUI_RefreshAlertColors"))
    local function RefreshUnits()
        Refresh("QUI_RefreshUnitFrames")
        Refresh("QUI_RefreshUnitFramePreview")
    end
    local function FrameBackgrounds(title, db, refresh, noAlpha)
        Add(title .. " - " .. ns.L["Normal"], db, "defaultBgColor", refresh,
            { opacity = "defaultBgOpacity", noAlpha = noAlpha })
        Add(title .. " - " .. ns.L["Dark Mode"], db, "darkModeBgColor", refresh,
            { opacity = "darkModeBgOpacity", noAlpha = noAlpha })
    end
    Group(ns.L["Frames"])
    FrameBackgrounds(ns.L["Unit Frames"], general, RefreshUnits, true)
    for _, entry in ipairs({
        { "player", ns.L["Player"] }, { "target", ns.L["Target"] }, { "focus", ns.L["Focus"] },
        { "targettarget", ns.L["Target of Target"] }, { "pet", ns.L["Pet"] }, { "boss", ns.L["Boss"] },
    }) do
        local unit = profile.quiUnitFrames and profile.quiUnitFrames[entry[1]]
        Add(entry[2], unit, nil, RefreshUnits, { class = "useClassColorBg" })
        Add(entry[2] .. " - " .. ns.L["Castbar"], unit and unit.castbar, "bgColor", RefreshUnits)
    end
    for _, entry in ipairs({ { "party", ns.L["Party"] }, { "raid", ns.L["Raid"] } }) do
        local mode = entry[1]
        local group = profile.quiGroupFrames and profile.quiGroupFrames[mode]
        FrameBackgrounds(entry[2], group and group.general, function()
            Refresh("QUI_RefreshGroupFrames")
            Refresh("QUI_RefreshGroupFramePreview", mode)
        end)
    end
    local nameplates = profile.nameplates
    if nameplates and ns.QUI_Nameplates and ns.QUI_Nameplates.NormalizeTypes then
        ns.QUI_Nameplates.NormalizeTypes(nameplates)
    end
    for _, entry in ipairs({
        { "enemyNPC", ns.L["Enemy NPC"] }, { "enemyPlayer", ns.L["Enemy Player"] },
        { "minorTrivial", ns.L["Minor / Trivial"] }, { "bossElite", ns.L["Boss / Elite"] },
        { "friendly", ns.L["Friendly"] }, { "petMinion", ns.L["Pet / Minion"] },
    }) do
        local plate = nameplates and nameplates.types and nameplates.types[entry[1]]
        local title = ns.L["Nameplates"] .. " - " .. entry[2]
        local function RefreshPlates()
            Refresh("QUI_RefreshNameplates")
            Refresh("QUI_RefreshNameplatePreview")
        end
        Add(title, plate and plate.health, "bgColor", RefreshPlates, { opacity = "bgAlpha", noAlpha = true })
        Add(title .. " - " .. ns.L["Castbar"], plate and plate.colors, "castBg", RefreshPlates)
    end
    local function RefreshResources()
        local core = Helpers.GetCore()
        if core and core.UpdatePowerBar then core:UpdatePowerBar() end
        if core and core.UpdateSecondaryPowerBar then core:UpdateSecondaryPowerBar() end
        Refresh("QUI_RefreshResourceBarPreview")
    end
    Group(ns.L["Resource Bars"])
    Add(ns.L["Primary Resource Bar"], profile.powerBar, "bgColor", RefreshResources)
    Add(ns.L["Secondary Resource Bar"], profile.secondaryPowerBar, "bgColor", RefreshResources)
    Group(ns.L["Trackers"])
    Override(ns.L["M+ Timer"], profile.mplusTimer, "", function()
        Refresh("QUI_ApplyMPlusTimerSkin")
        Refresh("QUI_RefreshMPlusTimerColors")
    end, "frameBackgroundOpacity")
    if ns.SwingTimers then
        Override(ns.L["Swing Timers"], general, "swingTimers", function() ns.SwingTimers.Refresh() end)
    end
    for _, entry in ipairs({
        { "combatTimer", ns.L["Combat Timer"], "QUI_RefreshCombatTimer" },
        { "lustTimer", ns.L["Lust Timer"], "QUI_RefreshLustTimer" },
        { "brzCounter", ns.L["Brez Counter"], "QUI_RefreshBrezCounter" },
        { "atonementCounter", ns.L["Atonement Counter"], "QUI_RefreshAtonementCounter" },
    }) do
        Add(entry[2], profile[entry[1]], "backdropColor", Callback(entry[3]), { show = "showBackdrop" })
    end
    Add(ns.L["Action Tracker"], general and general.actionTracker, "backdropColor", Callback("QUI_RefreshActionTracker"),
        { show = "showBackdrop" })
    Add(ns.L["XP Tracker"], profile.xpTracker, "backdropColor", Callback("QUI_RefreshXPTracker"))
    Add(ns.L["Prey Tracker"], profile.preyTracker, "barBackgroundColor", Callback("QUI_RefreshPreyTracker"),
        { override = "barBgOverride" })
    Add(ns.L["Skyriding Vigor Bar"], profile.skyriding, "backgroundColor", Callback("QUI_RefreshSkyriding"))
    Add(ns.L["Second Wind"], profile.skyriding, "secondWindBackgroundColor", Callback("QUI_RefreshSkyriding"))
    Group(ns.L["HUD"])
    Override(ns.L["Bags"], profile.bags and profile.bags.appearance, "", Callback("QUI_RefreshBags"))
    Add(ns.L["Minimap Button Drawer"], profile.minimap and profile.minimap.buttonDrawer, "bgColor",
        Callback("QUI_RefreshMinimap"), { opacity = "bgOpacity", percent = true, noAlpha = true })
    local function RefreshDatatexts()
        Refresh("QUI_RefreshMinimap")
        Refresh("QUI_RefreshDatapanels")
    end
    Add(ns.L["Datatext"], profile.datatext, nil, RefreshDatatexts, { opacity = "bgOpacity", percent = true })
    local function EachNamed(tables, fn)
        local keys = {}
        for key, value in pairs(tables or {}) do
            if key ~= "*" and type(value) == "table" then keys[#keys + 1] = key end
        end
        table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
        for _, key in ipairs(keys) do fn(key, tables[key]) end
    end
    EachNamed(profile.quiDatatexts and profile.quiDatatexts.panels, function(key, panel)
        Add(ns.L["Datatext"] .. " - " .. (type(panel.name) == "string" and panel.name or tostring(key)), panel, nil, RefreshDatatexts,
            { opacity = "bgOpacity", percent = true })
    end)
    local native = profile.damageMeter and profile.damageMeter.native
    local app = native and native.appearance and native.appearance.global
    Add(ns.L["Damage Meter"], app and app.colors, "bg", function()
        local meter = ns.QUI_DamageMeter or _G.QUI_DamageMeter
        if meter and meter.WindowManager then meter.WindowManager:RefreshAll() end
    end, { opacity = "windowBgAlpha", opacityDB = app })
    Group(ns.L["CDM"])
    local ncdm = profile.ncdm
    local seen = {}
    local function AuraBar(key, bar)
        if not bar or seen[bar] then return end
        seen[bar] = true
        local name = key == "trackedBar" and ns.L["Buff Bars"] or bar.name
        Add(ns.L["Aura Bars"] .. " - " .. (type(name) == "string" and name or tostring(key)), bar, "bgColor", function()
            if _G.QUI_ForceLayoutContainer then _G.QUI_ForceLayoutContainer(key)
            else Refresh("QUI_RefreshNCDM") end
            Refresh("QUI_RefreshCDMPreview")
        end, { opacity = "bgOpacity", noAlpha = true })
    end
    AuraBar("trackedBar", ncdm and ncdm.trackedBar)
    EachNamed(ncdm and ncdm.containers, function(key, bar)
        if key ~= "trackedBar" and bar.containerType == "auraBar" then AuraBar(key, bar) end
    end)
    CloseGroup()
    layout.finish()
end

Registry:RegisterFeature(Schema.Feature({
    id = "backgroundColoringPage", moverKey = "backgroundColoring", category = "appearance",
    lookupKeys = { "background", "backdrop", "fill", "opacity" },
    nav = { tileId = "appearance", subPageIndex = 12 },
    sections = { Schema.Section({ id = "settings", kind = "page", minHeight = 80, build = BuildBackgroundColoringTab }) },
}))
