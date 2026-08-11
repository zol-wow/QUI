local _, ns = ...
local QUICore = ns.Addon

local InfoBar = QUICore and QUICore.InfoBar
if not InfoBar then return end

local ContextMenu = {}
InfoBar.ContextMenu = ContextMenu

local ZONE_ORDER = { "left", "center", "right" }
local ZONE_LABELS = { left = ns.L["Left Zone"], center = ns.L["Center Zone"], right = ns.L["Right Zone"] }

function ContextMenu.ZoneFromCursorX(relX, barWidth)
    if not barWidth or barWidth <= 0 then return "left" end
    if relX < barWidth / 3 then return "left" end
    if relX < barWidth * 2 / 3 then return "center" end
    return "right"
end

function ContextMenu.EnsureZones(db)
    if not db.zones then db.zones = {} end
    for _, key in ipairs(ZONE_ORDER) do
        if not db.zones[key] then db.zones[key] = {} end
    end
    return db.zones
end

function ContextMenu.FindWidget(db, widgetId)
    local zones = ContextMenu.EnsureZones(db)
    for _, key in ipairs(ZONE_ORDER) do
        for i, id in ipairs(zones[key]) do
            if id == widgetId then return key, i end
        end
    end
    return nil
end

function ContextMenu.IsPlaced(db, widgetId)
    return ContextMenu.FindWidget(db, widgetId) ~= nil
end

function ContextMenu.AddWidget(db, zoneKey, widgetId)
    if ContextMenu.IsPlaced(db, widgetId) then return false end
    local list = ContextMenu.EnsureZones(db)[zoneKey]
    if not list then return false end
    list[#list + 1] = widgetId
    return true
end

function ContextMenu.RemoveWidget(db, widgetId)
    local key, idx = ContextMenu.FindWidget(db, widgetId)
    if not key then return false end
    table.remove(db.zones[key], idx)
    return true
end

ContextMenu.EnsureWidgetSettings = ns.QUI_InfoBarShared.EnsureWidgetSettings

function ContextMenu.BuildCategories(defs)
    local out, byCat = {}, {}
    for _, def in ipairs(defs or {}) do
        local cat = byCat[def.category]
        if not cat then
            cat = { category = def.category, widgets = {} }
            byCat[def.category] = cat
            out[#out + 1] = cat
        end
        cat.widgets[#cat.widgets + 1] = { id = def.id, name = def.displayName or def.id }
    end
    return out
end

function ContextMenu.PlacedList(db, getDef)
    local zones = ContextMenu.EnsureZones(db)
    local out = {}
    for _, key in ipairs(ZONE_ORDER) do
        for _, id in ipairs(zones[key]) do
            local def = getDef and getDef(id) or nil
            out[#out + 1] = {
                id = id,
                name = def and def.displayName or tostring(id),
                loaded = def ~= nil,
            }
        end
    end
    return out
end

local function GetDB()
    local db = QUICore.db and QUICore.db.profile
    return db and db.infobar
end

local function RefreshAll()
    if _G.QUI_RefreshInfoBar then _G.QUI_RefreshInfoBar() end
    local compat = ns.Settings and ns.Settings.RenderAdapters
    if compat and compat.NotifyProviderChanged then
        compat.NotifyProviderChanged("infobar", { structural = true })
    end
end

local function OpenInfoBarSettings()
    local QUI = _G.QUI
    if QUI and type(QUI.OpenOptions) == "function" then
        QUI:OpenOptions()
    end
    C_Timer.After(0, function()
        local gui = _G.QUI and _G.QUI.GUI
        if gui and gui.NavigateTo then
            gui:NavigateTo(18, 1)
        end
    end)
end

local OVERRIDE_TOGGLES = {
    { key = "shortLabel",   label = ns.L["Short Label"] },
    { key = "noLabel",      label = ns.L["No Label"] },
    { key = "hideIcon",     label = ns.L["Hide Icon"] },
    { key = "hideText",     label = ns.L["Hide Text"] },
    { key = "clickThrough", label = ns.L["Click-Through"] },
}

local function BuildMenu(owner, zoneKey)
    MenuUtil.CreateContextMenu(owner, function(_, root)
        root:CreateTitle(ns.L["Info Bar"] .. " — " .. (ZONE_LABELS[zoneKey] or ns.L["Bar"]))
        local db = GetDB()
        if not db then return end
        local Datatexts = QUICore.Datatexts

        if not Datatexts then
            local note = root:CreateButton(
                ns.L["Datatexts module is disabled — enable it under Modules."],
                function() end)
            note:SetEnabled(false)
        else
            local add = root:CreateButton(ns.L["Add Widget"])
            for _, cat in ipairs(ContextMenu.BuildCategories(Datatexts:GetAll())) do
                local catMenu = add:CreateButton(cat.category)
                for _, w in ipairs(cat.widgets) do
                    catMenu:CreateCheckbox(w.name,
                        function() return ContextMenu.IsPlaced(db, w.id) end,
                        function()
                            if ContextMenu.IsPlaced(db, w.id) then
                                ContextMenu.RemoveWidget(db, w.id)
                            else
                                ContextMenu.AddWidget(db, zoneKey, w.id)
                            end
                            RefreshAll()
                        end)
                end
            end

            local placed = ContextMenu.PlacedList(db,
                function(id) return Datatexts:Get(id) end)
            if #placed > 0 then
                local cfg = root:CreateButton(ns.L["Configure Widget"])
                for _, item in ipairs(placed) do
                    local wMenu = cfg:CreateButton(item.loaded and item.name
                        or (item.name .. " " .. ns.L["(not loaded)"]))
                    if item.loaded then
                        for _, t in ipairs(OVERRIDE_TOGGLES) do
                            wMenu:CreateCheckbox(t.label,
                                function()
                                    return ContextMenu.EnsureWidgetSettings(db, item.id)[t.key] == true
                                end,
                                function()
                                    local ws = ContextMenu.EnsureWidgetSettings(db, item.id)
                                    ws[t.key] = not ws[t.key]
                                    RefreshAll()
                                end)
                        end
                        wMenu:CreateDivider()
                    end
                    wMenu:CreateButton(ns.L["Remove from Bar"], function()
                        ContextMenu.RemoveWidget(db, item.id)
                        RefreshAll()
                    end)
                end
            end
        end

        root:CreateDivider()
        root:CreateButton(ns.L["Info Bar Settings…"], OpenInfoBarSettings)
    end)
end

local function OnBarMouseUp(self, button)
    if button ~= "RightButton" then return end
    local Helpers = ns.Helpers
    local scale = Helpers.SafeToNumber(self:GetEffectiveScale(), 0)
    local left = Helpers.SafeToNumber(self:GetLeft(), 0)
    local width = Helpers.SafeToNumber(self:GetWidth(), 0)
    local zoneKey = "right"
    if scale > 0 then
        local cursorX = GetCursorPosition()
        zoneKey = ContextMenu.ZoneFromCursorX(cursorX / scale - left, width)
    end
    BuildMenu(self, zoneKey)
end

local origApplyAll = InfoBar.ApplyAll
function InfoBar:ApplyAll()
    origApplyAll(self)
    local bar = _G["QUI_InfoBar"]
    if bar and not bar._quiContextMenuWired then
        bar._quiContextMenuWired = true
        bar:EnableMouse(true)
        bar:SetScript("OnMouseUp", OnBarMouseUp)
    end
end
