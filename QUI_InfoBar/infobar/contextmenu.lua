--- QUI Info Bar — right-click context menu on empty bar space: quick
--- add/remove of widgets (categorized checkboxes; target zone = the bar
--- third under the cursor) plus per-widget boolean overrides, mirroring
--- the settings page's data shapes (db.zones / db.widgetSettings).
--- Loads after infobar.lua in the TOC; wires itself by wrapping
--- InfoBar.ApplyAll (the bar frame is created there).

local _, ns = ...
local QUICore = ns.Addon

local InfoBar = QUICore and QUICore.InfoBar
if not InfoBar then return end

local ContextMenu = {}
InfoBar.ContextMenu = ContextMenu

local ZONE_ORDER = { "left", "center", "right" }
local ZONE_LABELS = { left = "Left Zone", center = "Center Zone", right = "Right Zone" }

---------------------------------------------------------------------------
-- PURE HELPERS (headlessly unit-tested: tests/unit/infobar_contextmenu_test.lua)
---------------------------------------------------------------------------

-- Bar third under the cursor decides which zone an added widget joins.
function ContextMenu.ZoneFromCursorX(relX, barWidth)
    if not barWidth or barWidth <= 0 then return "left" end
    if relX < barWidth / 3 then return "left" end
    if relX < barWidth * 2 / 3 then return "center" end
    return "right"
end

-- Sub-table guards only (same contract as the settings page): scalars come
-- from AceDB defaults; writing them here would pin shipped defaults.
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

-- Removes the first match only: every write surface (this menu and the
-- settings page) enforces the one-zone-per-widget invariant.
function ContextMenu.RemoveWidget(db, widgetId)
    local key, idx = ContextMenu.FindWidget(db, widgetId)
    if not key then return false end
    table.remove(db.zones[key], idx)
    return true
end

-- Same seeding shape as the settings page (infobar_content.lua): both now
-- delegate to the shared core helper so the defaults can never drift apart.
ContextMenu.EnsureWidgetSettings = ns.QUI_InfoBarShared.EnsureWidgetSettings

-- Group Datatexts:GetAll() output (already sorted by category, then name)
-- into { { category = "...", widgets = { { id, name }, ... } }, ... },
-- preserving first-seen category order.
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

-- Placed widgets across all zones in visual order (left, center, right).
-- getDef(id) -> registry def or nil; nil marks a "(not loaded)" entry whose
-- only menu action is Remove.
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

---------------------------------------------------------------------------
-- MENU (in-game only below this line; nothing here runs under the test)
---------------------------------------------------------------------------

local function GetDB()
    local db = QUICore.db and QUICore.db.profile
    return db and db.infobar
end

local function RefreshAll()
    if _G.QUI_RefreshInfoBar then _G.QUI_RefreshInfoBar() end
    -- Keep an open options page in sync — the same structural notify the
    -- settings page fires on its own mutations. The settings layer may not
    -- be loaded; guard every step.
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
    -- A cold open LoadAddOns QUI_Options synchronously, but the shell
    -- builds over the first frame; navigate next frame (the pattern the
    -- CDM composer deep-link uses).
    C_Timer.After(0, function()
        local gui = _G.QUI and _G.QUI.GUI
        if gui and gui.NavigateTo then
            -- Info Bar tab route — keep in sync with the navRoutes in
            -- QUI_Options/tiles/infobar.lua.
            gui:NavigateTo(18, 1)
        end
    end)
end

local OVERRIDE_TOGGLES = {
    { key = "shortLabel",   label = "Short Label" },
    { key = "noLabel",      label = "No Label" },
    { key = "hideIcon",     label = "Hide Icon" },
    { key = "hideText",     label = "Hide Text" },
    { key = "clickThrough", label = "Click-Through" },
}

local function BuildMenu(owner, zoneKey)
    MenuUtil.CreateContextMenu(owner, function(_, root)
        root:CreateTitle("Info Bar — " .. (ZONE_LABELS[zoneKey] or "Bar"))
        local db = GetDB()
        if not db then return end
        local Datatexts = QUICore.Datatexts

        if not Datatexts then
            local note = root:CreateButton(
                "Datatexts module is disabled — enable it under Modules.",
                function() end)
            note:SetEnabled(false)
        else
            -- Checkbox state is "placed in ANY zone"; checking adds to the
            -- clicked zone, unchecking removes from the owning zone.
            -- Checkboxes respond with MenuResponse.Refresh by default, so
            -- the menu stays open for adding several widgets in a row.
            local add = root:CreateButton("Add Widget")
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

            -- Submenu lists are generator-time snapshots: a widget added a
            -- moment ago appears under Configure Widget on the NEXT open
            -- (Refresh reinitializes frames, it does not re-run this
            -- generator). Acceptable; spec'd.
            local placed = ContextMenu.PlacedList(db,
                function(id) return Datatexts:Get(id) end)
            if #placed > 0 then
                local cfg = root:CreateButton("Configure Widget")
                for _, item in ipairs(placed) do
                    local wMenu = cfg:CreateButton(item.loaded and item.name
                        or (item.name .. " (not loaded)"))
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
                    wMenu:CreateButton("Remove from Bar", function()
                        ContextMenu.RemoveWidget(db, item.id)
                        RefreshAll()
                    end)
                end
            end
        end

        root:CreateDivider()
        root:CreateButton("Info Bar Settings…", OpenInfoBarSettings)
    end)
end

---------------------------------------------------------------------------
-- WIRING
---------------------------------------------------------------------------

local function OnBarMouseUp(self, button)
    if button ~= "RightButton" then return end
    -- Widget slots are mouse-enabled Buttons that swallow their own clicks
    -- (several widgets own right-click menus already); only genuine
    -- empty-space clicks reach the bar frame here.
    -- GetEffectiveScale: SecretReturnsForAspect=Scale, and GetLeft/GetWidth
    -- are SecretWhenAnchoringSecret — guard all three (SafeToNumber maps
    -- secrets to the fallback) so the zone math can't throw in combat.
    -- GetCursorPosition is never secret. Degraded fallback: right zone.
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

-- Wire on the next ApplyAll: the bar frame is created there, and this file
-- loads after infobar.lua in the TOC so the wrap is installed before the
-- deferred login-time ApplyAll fires. Insecure script on an insecure frame;
-- combat needs no handling here (mutations ride ApplyAll's own deferral).
local origApplyAll = InfoBar.ApplyAll
function InfoBar:ApplyAll()
    origApplyAll(self)
    -- Bracket access: the frame global is created by name (CreateFrame) and
    -- is invisible to the language server's _G field list.
    local bar = _G["QUI_InfoBar"]
    if bar and not bar._quiContextMenuWired then
        bar._quiContextMenuWired = true
        bar:EnableMouse(true)
        bar:SetScript("OnMouseUp", OnBarMouseUp)
    end
end
