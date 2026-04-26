--[[
    QUI Minimap Shared Settings Providers
    Owns provider-backed settings content for Minimap and Datatext panel surfaces in the shared settings layer.
]]

local ADDON_NAME, ns = ...

local Settings = ns.Settings
local ProviderPanels = Settings and Settings.ProviderPanels
if not ProviderPanels or type(ProviderPanels.RegisterAfterLoad) ~= "function" then
    return
end

ProviderPanels:RegisterAfterLoad(function(ctx)
    local GUI = ctx.GUI
    local U = ctx.U
    local P = ctx.P
    local FORM_ROW = ctx.FORM_ROW
    local NotifyProviderFor = ctx.NotifyProviderFor
    local anchorOptions = ctx.anchorOptions
    local function RegisterSharedOnly(key, provider)
        ctx.RegisterShared(key, provider)
    end

    ---------------------------------------------------------------------------
    -- MINIMAP
    ---------------------------------------------------------------------------
    RegisterSharedOnly("minimap", { build = function(content, key, width)
        local db = U.GetProfileDB()
        if not db or not db.minimap then return 80 end
        local mm = db.minimap
        if not db.uiHider then db.uiHider = {} end
        local sections = {}
        local function relayout() U.StandardRelayout(content, sections) end
        local function Refresh() if _G.QUI_RefreshMinimap then _G.QUI_RefreshMinimap() end end
        local function RefreshUIHider() if _G.QUI_RefreshUIHider then _G.QUI_RefreshUIHider() end end

        U.CreateCollapsible(content, "General", 7 * FORM_ROW + 8, function(body)
            local sy = -4
            sy = P(GUI:CreateFormSlider(body, "Map Dimensions", 120, 380, 1, "size", mm, Refresh, nil, { description = "Pixel size of the minimap (width = height)." }), body, sy)
            sy = P(GUI:CreateFormSlider(body, "Map Zoom Level", 0, 5, 1, "zoomLevel", mm, Refresh, nil, { description = "Default zoom level applied to the minimap. 0 is fully zoomed out." }), body, sy)
            sy = P(GUI:CreateFormCheckbox(body, "Middle-Click Menu", "middleClickMenuEnabled", mm, Refresh, { description = "Open the tracking/options menu when you middle-click the minimap." }), body, sy)
            sy = P(GUI:CreateFormCheckbox(body, "Auto-Zoom After Idle", "autoZoom", mm, nil, { description = "Gradually zoom the minimap back out to the default zoom level after a period of inactivity." }), body, sy)
            sy = P(GUI:CreateFormSlider(body, "Coord Update Interval (sec)", 1, 10, 1, "coordUpdateInterval", mm, nil, nil, { description = "How often the coordinate datatext refreshes, in seconds. Lower is smoother but slightly more expensive." }), body, sy)
            sy = P(GUI:CreateFormSlider(body, "Addon Button Corner Radius", 0, 12, 1, "buttonRadius", mm, Refresh, nil, { description = "Corner rounding applied to addon minimap buttons in pixels. 0 is square." }), body, sy)
            P(GUI:CreateFormCheckbox(body, "Hide Addon Buttons Until Hover", "hideAddonButtons", mm, function()
                if _G.QUI_RefreshMinimapAddonButtons then _G.QUI_RefreshMinimapAddonButtons() end
            end, { description = "Hide addon minimap buttons until you mouse over the minimap. Reduces clutter when you aren't using them." }), body, sy)
        end, sections, relayout)

        U.CreateCollapsible(content, "Border", 4 * FORM_ROW + 8, function(body)
            local sy = -4
            sy = P(GUI:CreateFormSlider(body, "Border Size", 1, 16, 1, "borderSize", mm, Refresh, nil, { description = "Thickness of the border drawn around the minimap." }), body, sy)
            sy = P(GUI:CreateFormColorPicker(body, "Border Color", "borderColor", mm, Refresh, nil, { description = "Color of the minimap border. Ignored if Class Color or Accent Color is enabled below." }), body, sy)
            sy = P(GUI:CreateFormCheckbox(body, "Class Color Border", "useClassColorBorder", mm, Refresh, { description = "Color the border by your class instead of the Border Color swatch above." }), body, sy)
            P(GUI:CreateFormCheckbox(body, "Accent Color Border", "useAccentColorBorder", mm, Refresh, { description = "Color the border using the UI accent color instead of the Border Color swatch above." }), body, sy)
        end, sections, relayout)

        U.CreateCollapsible(content, "Hide Elements", 10 * FORM_ROW + 8, function(body)
            local sy = -4
            -- Inverted checkboxes: checked = hide (DB false), unchecked = show (DB true)
            sy = P(GUI:CreateFormCheckboxInverted(body, "Hide Mail (reload after)", "showMail", mm, Refresh, { description = "Hide the mail notification icon on the minimap. Requires a UI reload to take effect." }), body, sy)
            sy = P(GUI:CreateFormCheckboxInverted(body, "Hide Work Order Notification", "showCraftingOrder", mm, Refresh, { description = "Hide the crafting/work order notification icon on the minimap." }), body, sy)
            sy = P(GUI:CreateFormCheckboxInverted(body, "Hide Tracking", "showTracking", mm, Refresh, { description = "Hide the tracking/eye icon on the minimap." }), body, sy)
            sy = P(GUI:CreateFormCheckboxInverted(body, "Hide Difficulty", "showDifficulty", mm, Refresh, { description = "Hide the instance difficulty indicator on the minimap." }), body, sy)
            sy = P(GUI:CreateFormCheckboxInverted(body, "Hide Garrison/Mission Report", "showMissions", mm, Refresh, { description = "Hide the garrison / mission table / expedition report button on the minimap." }), body, sy)
            -- UIHider controls
            sy = P(GUI:CreateFormCheckbox(body, "Hide Border (Top)", "hideMinimapBorder", db.uiHider, RefreshUIHider, { description = "Hide the native Blizzard minimap border artwork at the top of the minimap." }), body, sy)
            sy = P(GUI:CreateFormCheckbox(body, "Hide Clock Button", "hideTimeManager", db.uiHider, RefreshUIHider, { description = "Hide the Blizzard clock/stopwatch button on the minimap." }), body, sy)
            sy = P(GUI:CreateFormCheckbox(body, "Hide Calendar Button", "hideGameTime", db.uiHider, RefreshUIHider, { description = "Hide the Blizzard calendar button on the minimap." }), body, sy)
            sy = P(GUI:CreateFormCheckbox(body, "Hide Zone Text (Native)", "hideMinimapZoneText", db.uiHider, RefreshUIHider, { description = "Hide the Blizzard zone-text label above the minimap. Use the QUI zone label below for a replacement." }), body, sy)
            P(GUI:CreateFormCheckboxInverted(body, "Hide Zoom Buttons", "showZoomButtons", mm, Refresh, { description = "Hide the + / - zoom buttons on the minimap. You can still mouse-wheel to zoom." }), body, sy)
        end, sections, relayout)

        -- Zone Label section
        U.CreateCollapsible(content, "Zone Label", 6 * FORM_ROW + 8, function(body)
            local sy = -4
            sy = P(GUI:CreateFormCheckbox(body, "Show Zone Label", "showZoneText", mm, Refresh, { description = "Show the QUI zone label above the minimap." }), body, sy)
            if not mm.zoneTextConfig then mm.zoneTextConfig = {} end
            local ztc = mm.zoneTextConfig
            sy = P(GUI:CreateFormSlider(body, "Horizontal Offset", -150, 150, 1, "offsetX", ztc, Refresh, nil, { description = "Horizontal pixel offset for the zone label from its anchor. Positive moves right, negative moves left." }), body, sy)
            sy = P(GUI:CreateFormSlider(body, "Vertical Offset", -150, 150, 1, "offsetY", ztc, Refresh, nil, { description = "Vertical pixel offset for the zone label from its anchor. Positive moves up, negative moves down." }), body, sy)
            sy = P(GUI:CreateFormSlider(body, "Label Size", 8, 20, 1, "fontSize", ztc, Refresh, nil, { description = "Font size of the zone label text." }), body, sy)
            sy = P(GUI:CreateFormCheckbox(body, "Uppercase Text", "allCaps", ztc, Refresh, { description = "Render the zone label in all uppercase letters." }), body, sy)
            P(GUI:CreateFormCheckbox(body, "Use Class Color", "useClassColor", ztc, Refresh, { description = "Color the zone label by your class instead of by the zone's PvP status." }), body, sy)
        end, sections, relayout)

        -- Dungeon Eye section
        if not mm.dungeonEye then
            mm.dungeonEye = { enabled = true, corner = "BOTTOMLEFT", scale = 0.6, offsetX = 0, offsetY = 0 }
        end
        local eye = mm.dungeonEye
        local cornerOptions = {
            {value = "TOPRIGHT", text = "Top Right"},
            {value = "TOPLEFT", text = "Top Left"},
            {value = "BOTTOMRIGHT", text = "Bottom Right"},
            {value = "BOTTOMLEFT", text = "Bottom Left"},
        }
        U.CreateCollapsible(content, "Dungeon Eye", 5 * FORM_ROW + 8, function(body)
            local sy = -4
            sy = P(GUI:CreateFormCheckbox(body, "Enable Dungeon Eye", "enabled", eye, Refresh, { description = "Show the LFG eye icon on a corner of the minimap while you're queued for a dungeon or raid." }), body, sy)
            sy = P(GUI:CreateFormDropdown(body, "Corner Position", cornerOptions, "corner", eye, Refresh, { description = "Which corner of the minimap the dungeon eye icon is anchored to." }), body, sy)
            sy = P(GUI:CreateFormSlider(body, "Icon Scale", 0.1, 2.0, 0.1, "scale", eye, Refresh, nil, { description = "Scale multiplier applied to the dungeon eye icon." }), body, sy)
            sy = P(GUI:CreateFormSlider(body, "X Offset", -30, 30, 1, "offsetX", eye, Refresh, nil, { description = "Horizontal pixel offset for the dungeon eye from its corner. Positive moves right, negative moves left." }), body, sy)
            P(GUI:CreateFormSlider(body, "Y Offset", -30, 30, 1, "offsetY", eye, Refresh, nil, { description = "Vertical pixel offset for the dungeon eye from its corner. Positive moves up, negative moves down." }), body, sy)
        end, sections, relayout)

        -- Great Vault section
        if not mm.greatVault then
            mm.greatVault = { enabled = false, anchor = "TOPLEFT", fadeWhenMouseOut = false, fadeOpacity = 0, scale = 1.0, offsetX = 1, offsetY = -1 }
        end
        if not mm.greatVault.anchor then mm.greatVault.anchor = "TOPLEFT" end
        if mm.greatVault.fadeWhenMouseOut == nil then mm.greatVault.fadeWhenMouseOut = false end
        if mm.greatVault.fadeOpacity == nil then mm.greatVault.fadeOpacity = 0 end
        if mm.greatVault.offsetX == nil then mm.greatVault.offsetX = 1 end
        if mm.greatVault.offsetY == nil then mm.greatVault.offsetY = -1 end
        local vault = mm.greatVault
        local vaultAnchorOptions = {
            {value = "TOPLEFT", text = "Top Left"},
            {value = "TOP", text = "Top"},
            {value = "TOPRIGHT", text = "Top Right"},
            {value = "LEFT", text = "Left"},
            {value = "CENTER", text = "Center"},
            {value = "RIGHT", text = "Right"},
            {value = "BOTTOMLEFT", text = "Bottom Left"},
            {value = "BOTTOM", text = "Bottom"},
            {value = "BOTTOMRIGHT", text = "Bottom Right"},
        }
        U.CreateCollapsible(content, "Great Vault", 7 * FORM_ROW + 8, function(body)
            local sy = -4
            sy = P(GUI:CreateFormCheckbox(body, "Enable Great Vault Button", "enabled", vault, Refresh, { description = "Show a clickable Great Vault shortcut anchored relative to the minimap." }), body, sy)
            sy = P(GUI:CreateFormCheckbox(body, "Fade When Not Hovered", "fadeWhenMouseOut", vault, Refresh, { description = "Fade the Great Vault button down when you aren't hovering the minimap." }), body, sy)
            sy = P(GUI:CreateFormSlider(body, "Fade Opacity", 0, 1, 0.05, "fadeOpacity", vault, Refresh, { precision = 2 }, { description = "Opacity the button fades down to when not hovered (0 is fully invisible, 1 is fully opaque)." }), body, sy)
            sy = P(GUI:CreateFormDropdown(body, "Anchor", vaultAnchorOptions, "anchor", vault, Refresh, { description = "Which point of the minimap the Great Vault button anchors to." }), body, sy)
            sy = P(GUI:CreateFormSlider(body, "Icon Scale", 0.5, 2.0, 0.1, "scale", vault, Refresh, nil, { description = "Scale multiplier applied to the Great Vault icon." }), body, sy)
            sy = P(GUI:CreateFormSlider(body, "X Offset", -200, 200, 1, "offsetX", vault, Refresh, nil, { description = "Horizontal pixel offset from the anchor point. Positive moves right, negative moves left." }), body, sy)
            P(GUI:CreateFormSlider(body, "Y Offset", -200, 200, 1, "offsetY", vault, Refresh, nil, { description = "Vertical pixel offset from the anchor point. Positive moves up, negative moves down." }), body, sy)
        end, sections, relayout)

        -- Button Drawer section
        if not mm.buttonDrawer then
            mm.buttonDrawer = {
                enabled = false, anchor = "RIGHT", offsetX = 0, offsetY = 0,
                toggleOffsetX = 0, toggleOffsetY = 0, autoHideDelay = 1.5,
                buttonSize = 28, buttonSpacing = 2, padding = 6, columns = 1,
                growthDirection = "RIGHT", centerGrowth = false,
                bgColor = {0.03, 0.03, 0.03, 1}, bgOpacity = 98,
                borderSize = 1, borderColor = {0.2, 0.8, 0.6, 1},
                openOnMouseover = true, autoHideToggle = false, hiddenButtons = {},
            }
        end
        local drawer = mm.buttonDrawer
        if drawer.toggleSize == nil then drawer.toggleSize = 20 end
        if not drawer.toggleIcon then drawer.toggleIcon = "hammer" end
        if drawer.hiddenButtons == nil then drawer.hiddenButtons = {} end
        if drawer.padding == nil then drawer.padding = 6 end
        if not drawer.growthDirection then drawer.growthDirection = "RIGHT" end
        if drawer.centerGrowth == nil then drawer.centerGrowth = false end
        if not drawer.bgColor then drawer.bgColor = {0.03, 0.03, 0.03, 1} end
        if drawer.bgOpacity == nil then drawer.bgOpacity = 98 end
        if drawer.borderSize == nil then drawer.borderSize = 1 end
        if not drawer.borderColor then drawer.borderColor = {0.2, 0.8, 0.6, 1} end

        local anchorOptions = {
            {value = "RIGHT", text = "Right"}, {value = "LEFT", text = "Left"},
            {value = "TOP", text = "Top"}, {value = "BOTTOM", text = "Bottom"},
            {value = "TOPLEFT", text = "Top Left"}, {value = "TOPRIGHT", text = "Top Right"},
            {value = "BOTTOMLEFT", text = "Bottom Left"}, {value = "BOTTOMRIGHT", text = "Bottom Right"},
        }
        local growthOptions = {
            {value = "RIGHT", text = "Right"}, {value = "LEFT", text = "Left"},
            {value = "DOWN", text = "Down"}, {value = "UP", text = "Up"},
        }
        local toggleIconOptions = {
            {value = "hammer", text = "Hammer"}, {value = "grid", text = "Grid Dots"},
        }

        U.CreateCollapsible(content, "Button Drawer", 17 * FORM_ROW + 8, function(body)
            local sy = -4
            sy = P(GUI:CreateFormCheckbox(body, "Enable Button Drawer", "enabled", drawer, Refresh, { description = "Collect addon minimap buttons into a hideable drawer attached to the minimap." }), body, sy)
            sy = P(GUI:CreateFormCheckbox(body, "Open on Mouseover", "openOnMouseover", drawer, Refresh, { description = "Open the drawer automatically when you hover the toggle button. Off requires a click to open." }), body, sy)
            sy = P(GUI:CreateFormDropdown(body, "Anchor Side", anchorOptions, "anchor", drawer, Refresh, { description = "Which side of the minimap the drawer expands out from." }), body, sy)
            sy = P(GUI:CreateFormSlider(body, "Drawer X Offset", -200, 200, 1, "offsetX", drawer, Refresh, nil, { description = "Horizontal pixel offset for the drawer body from its anchor. Positive moves right, negative moves left." }), body, sy)
            sy = P(GUI:CreateFormSlider(body, "Drawer Y Offset", -200, 200, 1, "offsetY", drawer, Refresh, nil, { description = "Vertical pixel offset for the drawer body from its anchor. Positive moves up, negative moves down." }), body, sy)
            sy = P(GUI:CreateFormSlider(body, "Button X Offset", -200, 200, 1, "toggleOffsetX", drawer, Refresh, nil, { description = "Horizontal pixel offset for the drawer toggle button. Positive moves right, negative moves left." }), body, sy)
            sy = P(GUI:CreateFormSlider(body, "Button Y Offset", -200, 200, 1, "toggleOffsetY", drawer, Refresh, nil, { description = "Vertical pixel offset for the drawer toggle button. Positive moves up, negative moves down." }), body, sy)
            sy = P(GUI:CreateFormSlider(body, "Toggle Size", 12, 40, 1, "toggleSize", drawer, Refresh, nil, { description = "Pixel size of the drawer toggle button." }), body, sy)
            sy = P(GUI:CreateFormDropdown(body, "Toggle Icon", toggleIconOptions, "toggleIcon", drawer, Refresh, { description = "Icon used for the drawer toggle button." }), body, sy)
            sy = P(GUI:CreateFormSlider(body, "Auto-Hide Delay (0=manual)", 0, 5, 0.5, "autoHideDelay", drawer, Refresh, nil, { description = "Seconds the drawer stays open after your cursor leaves. Set to 0 to require a manual close." }), body, sy)
            sy = P(GUI:CreateFormSlider(body, "Button Size", 20, 40, 1, "buttonSize", drawer, Refresh, nil, { description = "Pixel size of each addon button inside the drawer." }), body, sy)
            sy = P(GUI:CreateFormSlider(body, "Inner Padding", 0, 20, 1, "padding", drawer, Refresh, nil, { description = "Pixel padding between the drawer border and the first/last addon button." }), body, sy)
            sy = P(GUI:CreateFormSlider(body, "Columns", 1, 6, 1, "columns", drawer, Refresh, nil, { description = "How many columns of buttons the drawer uses before wrapping to a new row." }), body, sy)
            sy = P(GUI:CreateFormDropdown(body, "Growth Direction", growthOptions, "growthDirection", drawer, Refresh, { description = "Direction the drawer extends as more buttons are added." }), body, sy)
            sy = P(GUI:CreateFormCheckbox(body, "Center Growth", "centerGrowth", drawer, Refresh, { description = "Center the drawer along its growth axis instead of extending in one direction." }), body, sy)
            sy = P(GUI:CreateFormCheckbox(body, "Auto-Hide Toggle Button", "autoHideToggle", drawer, Refresh, { description = "Hide the drawer toggle button until you mouse over the minimap." }), body, sy)
            P(GUI:CreateFormCheckbox(body, "Button Spacing", "buttonSpacing", drawer, Refresh, { description = "Add a small pixel gap between buttons inside the drawer." }), body, sy)
        end, sections, relayout)

        -- Button Drawer Appearance
        U.CreateCollapsible(content, "Drawer Appearance", 4 * FORM_ROW + 8, function(body)
            local sy = -4
            sy = P(GUI:CreateFormColorPicker(body, "Background Color", "bgColor", drawer, Refresh, { noAlpha = true }, { description = "Background color of the drawer body." }), body, sy)
            sy = P(GUI:CreateFormSlider(body, "Background Opacity", 0, 100, 1, "bgOpacity", drawer, Refresh, nil, { description = "Opacity of the drawer background (0 to 100 percent)." }), body, sy)
            sy = P(GUI:CreateFormSlider(body, "Border Size (0=hidden)", 0, 8, 1, "borderSize", drawer, Refresh, nil, { description = "Thickness of the drawer border. Set to 0 to hide the border." }), body, sy)
            P(GUI:CreateFormColorPicker(body, "Border Color", "borderColor", drawer, Refresh, { noAlpha = true }, { description = "Color of the drawer border." }), body, sy)
        end, sections, relayout)

        -- Hidden Buttons
        local buttonNames = _G.QUI_GetDrawerButtonNames and _G.QUI_GetDrawerButtonNames() or {}
        local hiddenCount = #buttonNames > 0 and #buttonNames or 1
        U.CreateCollapsible(content, "Hidden Buttons", hiddenCount * FORM_ROW + 8, function(body)
            local sy = -4
            if #buttonNames > 0 then
                for _, bName in ipairs(buttonNames) do
                    local displayName = bName:gsub("^LibDBIcon10_", "")
                    sy = P(GUI:CreateFormCheckbox(body, displayName, bName, drawer.hiddenButtons, Refresh, { description = "Hide this addon button from both the minimap and the drawer. Useful for buttons you never click." }), body, sy)
                end
            else
                local label = body:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                label:SetPoint("TOPLEFT", 4, sy)
                label:SetTextColor(0.6, 0.6, 0.6, 1)
                label:SetText("No buttons collected yet. Enable the drawer and reload.")
            end
        end, sections, relayout)

        U.BuildPositionCollapsible(content, "minimap", nil, sections, relayout)
        U.BuildOpenFullSettingsLink(content, key, sections, relayout)
        relayout() return content:GetHeight()
    end })

    ---------------------------------------------------------------------------
    -- DATATEXT PANEL (Minimap + Custom Panels)
    ---------------------------------------------------------------------------
    local DATATEXT_MINIMAP_KEY = "__minimap"
    local DatatextPanelState = {
        activePanel = DATATEXT_MINIMAP_KEY,
    }

    local function EnsureMinimapDatatextConfig(profile)
        if not profile.datatext then profile.datatext = {} end
        local dt = profile.datatext
        if dt.enabled == nil then dt.enabled = true end
        if not dt.slots then dt.slots = { "time", "friends", "guild" } end
        if not dt.slot1 then dt.slot1 = { shortLabel = false, noLabel = false, xOffset = 0, yOffset = 0 } end
        if not dt.slot2 then dt.slot2 = { shortLabel = false, noLabel = false, xOffset = 0, yOffset = 0 } end
        if not dt.slot3 then dt.slot3 = { shortLabel = false, noLabel = false, xOffset = 0, yOffset = 0 } end
        if dt.slot1.noLabel == nil then dt.slot1.noLabel = false end
        if dt.slot2.noLabel == nil then dt.slot2.noLabel = false end
        if dt.slot3.noLabel == nil then dt.slot3.noLabel = false end
        return dt
    end

    local function EnsureCustomDatapanelStore(profile)
        if not profile.quiDatatexts then
            profile.quiDatatexts = { panels = {} }
        end
        if not profile.quiDatatexts.panels then
            profile.quiDatatexts.panels = {}
        end
        return profile.quiDatatexts
    end

    local function EnsureCustomDatapanelDefaults(panelDB)
        if panelDB.enabled == nil then panelDB.enabled = true end
        if panelDB.locked == nil then panelDB.locked = false end
        if not panelDB.name or panelDB.name == "" then
            panelDB.name = "Datapanel"
        end
        if not panelDB.width then panelDB.width = 300 end
        if not panelDB.height then panelDB.height = 22 end
        if not panelDB.numSlots then panelDB.numSlots = 3 end
        if not panelDB.bgOpacity then panelDB.bgOpacity = 50 end
        if panelDB.borderSize == nil then panelDB.borderSize = 2 end
        if not panelDB.borderColor then panelDB.borderColor = { 0, 0, 0, 1 } end
        if not panelDB.fontSize then panelDB.fontSize = 12 end
        if not panelDB.position then panelDB.position = { "CENTER", "CENTER", 0, 300 } end
        if not panelDB.slots then panelDB.slots = {} end
        if not panelDB.slotSettings then panelDB.slotSettings = {} end
        for i = 1, (panelDB.numSlots or 3) do
            if not panelDB.slotSettings[i] then
                panelDB.slotSettings[i] = { shortLabel = false, noLabel = false }
            end
            if panelDB.slotSettings[i].shortLabel == nil then panelDB.slotSettings[i].shortLabel = false end
            if panelDB.slotSettings[i].noLabel == nil then panelDB.slotSettings[i].noLabel = false end
        end
        return panelDB
    end

    local function FindCustomDatapanel(profile, panelID)
        local dtStore = EnsureCustomDatapanelStore(profile)
        for i, panelDB in ipairs(dtStore.panels) do
            if panelDB and panelDB.id == panelID then
                return EnsureCustomDatapanelDefaults(panelDB), i, dtStore.panels
            end
        end
        return nil, nil, dtStore.panels
    end

    local function GetDatatextOptions(addon)
        local dtOptions = {
            { value = "", text = "(empty)" },
        }
        if addon and addon.Datatexts then
            local allDatatexts = addon.Datatexts:GetAll()
            for _, datatextDef in ipairs(allDatatexts) do
                dtOptions[#dtOptions + 1] = {
                    value = datatextDef.id,
                    text = datatextDef.displayName,
                }
            end
        end
        return dtOptions
    end

    local function GetDatapanelSelectorOptions(profile)
        local opts = {
            { value = DATATEXT_MINIMAP_KEY, text = "Minimap Panel" },
        }
        local dtStore = EnsureCustomDatapanelStore(profile)
        for i, panelDB in ipairs(dtStore.panels) do
            EnsureCustomDatapanelDefaults(panelDB)
            opts[#opts + 1] = {
                value = panelDB.id,
                text = panelDB.name or ("Datapanel " .. i),
            }
        end
        return opts
    end

    local function EnsureDatatextSelection(profile)
        local active = DatatextPanelState.activePanel or DATATEXT_MINIMAP_KEY
        if active == DATATEXT_MINIMAP_KEY then
            DatatextPanelState.activePanel = active
            return active
        end
        local panelDB = FindCustomDatapanel(profile, active)
        if panelDB then
            DatatextPanelState.activePanel = active
            return active
        end
        DatatextPanelState.activePanel = DATATEXT_MINIMAP_KEY
        return DATATEXT_MINIMAP_KEY
    end

    local function NormalizeDatatextSelectionKey(profile, lookupKey)
        if type(lookupKey) ~= "string" or lookupKey == "" then
            return DATATEXT_MINIMAP_KEY
        end

        if lookupKey == DATATEXT_MINIMAP_KEY or lookupKey == "datatextPanel" then
            return DATATEXT_MINIMAP_KEY
        end

        local panelID = lookupKey
        if lookupKey:find("^datapanel_") then
            panelID = lookupKey:sub(11)
        end

        local panelDB = FindCustomDatapanel(profile, panelID)
        if panelDB then
            return panelID
        end

        return DATATEXT_MINIMAP_KEY
    end

    local function SetActiveDatatextPanel(lookupKey, profile)
        local active = NormalizeDatatextSelectionKey(profile, lookupKey)
        DatatextPanelState.activePanel = active
        return active
    end

    ns.QUI_DatatextPanelSelection = {
        minimapKey = DATATEXT_MINIMAP_KEY,
        setActivePanel = function(lookupKey, profile)
            return SetActiveDatatextPanel(lookupKey, profile)
        end,
        getActivePanel = function(profile)
            return EnsureDatatextSelection(profile)
        end,
        getPositionTarget = function(profile, lookupKey)
            local active = lookupKey and SetActiveDatatextPanel(lookupKey, profile) or EnsureDatatextSelection(profile)
            if active == DATATEXT_MINIMAP_KEY then
                return "datatextPanel", nil
            end
            return "datapanel_" .. active, { autoWidth = true }
        end,
    }

    local function CreateCustomDatapanel(profile)
        local dtStore = EnsureCustomDatapanelStore(profile)
        local newID = "panel" .. (#dtStore.panels + 1)
        local existing = {}
        for _, panelDB in ipairs(dtStore.panels) do
            if panelDB and panelDB.id then
                existing[panelDB.id] = true
            end
        end
        while existing[newID] do
            newID = newID .. "_"
        end

        local newPanel = EnsureCustomDatapanelDefaults({
            id = newID,
            name = "Datapanel " .. (#dtStore.panels + 1),
        })
        dtStore.panels[#dtStore.panels + 1] = newPanel
        return newPanel
    end

    local function UpdateCustomDatapanelRuntimeLabel(panelDB)
        if not panelDB or not panelDB.id then return end
        local elementKey = "datapanel_" .. panelDB.id
        local displayName = panelDB.name or panelDB.id
        local um = ns.QUI_LayoutMode
        if um and um._elements and um._elements[elementKey] then
            um._elements[elementKey].label = displayName
        end
        if ns.FRAME_ANCHOR_INFO and ns.FRAME_ANCHOR_INFO[elementKey] then
            ns.FRAME_ANCHOR_INFO[elementKey].displayName = displayName
        end
        local uiSelf = ns.QUI_LayoutMode_UI
        if uiSelf and uiSelf._RebuildDrawer then
            uiSelf:_RebuildDrawer()
        end
    end

    local function RegisterCustomDatapanelRuntime(panelDB, addon, profile)
        if not panelDB or not panelDB.id or not addon then return end

        local panelID = panelDB.id
        local elementKey = "datapanel_" .. panelID
        local Datapanels = addon.Datapanels
        local um = ns.QUI_LayoutMode
        local needsFrameRefresh = not (Datapanels and Datapanels.activePanels and Datapanels.activePanels[panelID])
        local needsElementRegistration = not (um and um._elements and um._elements[elementKey])

        if needsFrameRefresh and Datapanels then
            addon.Datapanels:RefreshAll()
        end

        if needsElementRegistration and um then
            um:RegisterElement({
                key = elementKey,
                label = panelDB.name or panelID,
                group = "Display",
                order = 10 + #(EnsureCustomDatapanelStore(profile).panels or {}),
                isOwned = true,
                getFrame = function()
                    return Datapanels and Datapanels.activePanels[panelID]
                end,
                isEnabled = function()
                    local _, _, panels = FindCustomDatapanel(profile, panelID)
                    if panels then
                        for _, pc in ipairs(panels) do
                            if pc.id == panelID then
                                return pc.enabled ~= false
                            end
                        end
                    end
                    return false
                end,
                setEnabled = function(val)
                    local panel = Datapanels and Datapanels.activePanels[panelID]
                    if panel then
                        panel.config.enabled = val
                        if val then panel:Show() else panel:Hide() end
                    end
                    local panelDB2 = FindCustomDatapanel(profile, panelID)
                    if panelDB2 then
                        panelDB2.enabled = val
                    end
                end,
                setGameplayHidden = function(hide)
                    local panel = Datapanels and Datapanels.activePanels[panelID]
                    if not panel then return end
                    if hide then panel:Hide() else panel:Show() end
                end,
            })
        end

        local displayName = panelDB.name or panelID
        if ns.FRAME_ANCHOR_INFO then
            ns.FRAME_ANCHOR_INFO[elementKey] = {
                displayName = displayName,
                category = "Display",
                order = 10 + #(EnsureCustomDatapanelStore(profile).panels or {}),
            }
        end

        local anchoring = ns.QUI_Anchoring
        if anchoring and anchoring.RegisterAnchorTarget then
            local panel = Datapanels and Datapanels.activePanels[panelID]
            if panel then
                anchoring:RegisterAnchorTarget(elementKey, panel, {
                    displayName = displayName,
                    category = "Display",
                    order = 10 + #(EnsureCustomDatapanelStore(profile).panels or {}),
                })
            end
        end

        if Datapanels and Datapanels.RegisterSettingsLookup then
            Datapanels.RegisterSettingsLookup(panelID, elementKey)
        end

        local uiSelf = ns.QUI_LayoutMode_UI
        if needsElementRegistration and uiSelf and uiSelf._RebuildDrawer then
            uiSelf:_RebuildDrawer()
        end
    end

    local function UnregisterCustomDatapanelRuntime(panelID, addon)
        if not panelID then return end
        local elementKey = "datapanel_" .. panelID
        local um = ns.QUI_LayoutMode
        if um then
            local handle = um._handles and um._handles[elementKey]
            if handle then
                handle:Hide()
                handle:SetParent(nil)
                um._handles[elementKey] = nil
            end
            if um._elements then
                um._elements[elementKey] = nil
            end
            if um._elementOrder then
                for idx, k2 in ipairs(um._elementOrder) do
                    if k2 == elementKey then
                        table.remove(um._elementOrder, idx)
                        break
                    end
                end
            end
        end

        if addon and addon.Datapanels and addon.Datapanels.UnregisterSettingsLookup then
            addon.Datapanels.UnregisterSettingsLookup(panelID, elementKey)
        end
        if ns.FRAME_ANCHOR_INFO then
            ns.FRAME_ANCHOR_INFO[elementKey] = nil
        end
        local anchoring = ns.QUI_Anchoring
        if anchoring and anchoring.UnregisterAnchorTarget then
            anchoring:UnregisterAnchorTarget(elementKey)
        end
        local uiSelf = ns.QUI_LayoutMode_UI
        if uiSelf and uiSelf._RebuildDrawer then
            uiSelf:_RebuildDrawer()
        end
        if addon and addon.Datapanels then
            addon.Datapanels:DeletePanel(panelID)
            addon.Datapanels:RefreshAll()
        end
    end

    local function GetDatatextDisplayName(addon, datatextID)
        if not datatextID or datatextID == "" then
            return "(empty)"
        end
        if addon and addon.Datatexts and addon.Datatexts.Get then
            local datatextDef = addon.Datatexts:Get(datatextID)
            if datatextDef and datatextDef.displayName and datatextDef.displayName ~= "" then
                return datatextDef.displayName
            end
        end
        return tostring(datatextID)
    end

    local function BuildShortPreviewLabel(label)
        if not label or label == "" then
            return "TXT"
        end

        local initials = {}
        for token in string.gmatch(label, "[%a%d]+") do
            initials[#initials + 1] = string.upper(string.sub(token, 1, 1))
            if #initials >= 4 then
                break
            end
        end

        if #initials >= 2 then
            return table.concat(initials)
        end

        local compact = string.gsub(label, "[^%a%d]", "")
        compact = string.upper(compact)
        if compact == "" then
            return "TXT"
        end

        return string.sub(compact, 1, math.min(4, string.len(compact)))
    end

    local function GetDatatextPreviewValueColor(dtSettings)
        if dtSettings and dtSettings.useClassColor then
            local _, class = UnitClass("player")
            local classColor = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
            if classColor then
                return classColor.r or 1, classColor.g or 1, classColor.b or 1
            end
        end

        local color = dtSettings and dtSettings.valueColor or nil
        if type(color) == "table" then
            return color[1] or 0.1, color[2] or 1, color[3] or 0.1
        end

        return 0.1, 1, 0.1
    end

    local function ToPreviewHexComponent(value)
        local v = tonumber(value) or 0
        v = math.max(0, math.min(1, v))
        return math.floor(v * 255 + 0.5)
    end

    local function GetDatatextPreviewFontSettings()
        local Helpers = ns.Helpers
        local fontPath = Helpers and Helpers.GetGeneralFont and Helpers.GetGeneralFont() or STANDARD_TEXT_FONT
        local fontOutline = Helpers and Helpers.GetGeneralFontOutline and Helpers.GetGeneralFontOutline() or "OUTLINE"
        return fontPath or STANDARD_TEXT_FONT, fontOutline or ""
    end

    local function BuildPreviewSlotText(addon, datatextID, slotSettings, dtSettings)
        if not datatextID or datatextID == "" then
            return nil
        end

        local settings = slotSettings or {}
        local vr, vg, vb = GetDatatextPreviewValueColor(dtSettings)
        local valueText = string.format("|cff%02x%02x%02x123|r",
            ToPreviewHexComponent(vr),
            ToPreviewHexComponent(vg),
            ToPreviewHexComponent(vb)
        )

        if settings.noLabel then
            return valueText
        end

        local label = GetDatatextDisplayName(addon, datatextID)
        if settings.shortLabel then
            return BuildShortPreviewLabel(label) .. ": " .. valueText
        end

        return label .. ": " .. valueText
    end

    local function GetSelectedDatatextContext(profile)
        local activeKey = EnsureDatatextSelection(profile)
        if activeKey == DATATEXT_MINIMAP_KEY then
            local dt = EnsureMinimapDatatextConfig(profile)
            return {
                key = DATATEXT_MINIMAP_KEY,
                label = "Minimap Panel",
                isMinimap = true,
                positionKey = "datatextPanel",
                panelDB = dt,
                numSlots = 3,
                slots = dt.slots,
                slotSettings = { dt.slot1, dt.slot2, dt.slot3 },
            }
        end

        local panelDB = FindCustomDatapanel(profile, activeKey)
        if not panelDB then
            DatatextPanelState.activePanel = DATATEXT_MINIMAP_KEY
            return GetSelectedDatatextContext(profile)
        end

        return {
            key = panelDB.id,
            label = panelDB.name or panelDB.id,
            isMinimap = false,
            positionKey = "datapanel_" .. panelDB.id,
            panelDB = panelDB,
            numSlots = panelDB.numSlots or 3,
            slots = panelDB.slots,
            slotSettings = panelDB.slotSettings,
        }
    end

    local function ApplyDatatextPreviewBackdrop(frame, bgR, bgG, bgB, bgA, borderR, borderG, borderB, borderA)
        if not frame or not frame.SetBackdrop then return end
        local core = ns.Addon
        local px = (core and core.GetPixelSize and core:GetPixelSize(frame)) or 1
        frame:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Buttons\\WHITE8x8",
            edgeSize = px,
        })
        frame:SetBackdropColor(bgR or 0, bgG or 0, bgB or 0, bgA or 1)
        frame:SetBackdropBorderColor(borderR or 0, borderG or 0, borderB or 0, borderA or 1)
    end

    local function CreateDatatextPreview(parent, stageHeight)
        local preview = CreateFrame("Frame", nil, parent, "BackdropTemplate")
        preview:SetHeight(stageHeight or 176)
        ApplyDatatextPreviewBackdrop(preview, 0.06, 0.08, 0.11, 0.92, 0.22, 0.24, 0.28, 1)

        preview.canvas = CreateFrame("Frame", nil, preview)
        preview.canvas:SetPoint("CENTER")

        local accent = (GUI and GUI.Colors and GUI.Colors.accent) or { 0.376, 0.647, 0.980, 1 }

        preview.anchorBox = CreateFrame("Frame", nil, preview.canvas, "BackdropTemplate")
        ApplyDatatextPreviewBackdrop(preview.anchorBox, 0.03, 0.04, 0.06, 0.92, accent[1], accent[2], accent[3], 0.65)
        preview.anchorLabel = preview.anchorBox:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        preview.anchorLabel:SetPoint("CENTER")
        preview.anchorLabel:SetTextColor(0.76, 0.82, 0.90, 1)

        preview.panel = CreateFrame("Frame", nil, preview.canvas)
        preview.panel.bg = preview.panel:CreateTexture(nil, "BACKGROUND")
        preview.panel.bg:SetAllPoints()
        preview.panel.borderLeft = preview.panel:CreateTexture(nil, "BORDER")
        preview.panel.borderRight = preview.panel:CreateTexture(nil, "BORDER")
        preview.panel.borderTop = preview.panel:CreateTexture(nil, "BORDER")
        preview.panel.borderBottom = preview.panel:CreateTexture(nil, "BORDER")
        preview.emptyText = preview.panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        preview.emptyText:SetPoint("CENTER")
        preview.emptyText:SetTextColor(0.62, 0.68, 0.74, 1)

        preview.slots = {}
        for i = 1, 8 do
            local slot = CreateFrame("Frame", nil, preview.panel)
            slot.text = slot:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            slot.text:SetPoint("LEFT", slot, "LEFT", 6, 0)
            slot.text:SetPoint("RIGHT", slot, "RIGHT", -6, 0)
            slot.text:SetJustifyH("CENTER")
            slot.text:SetWordWrap(false)

            if i < 8 then
                slot.separator = preview.panel:CreateTexture(nil, "ARTWORK")
                slot.separator:SetColorTexture(1, 1, 1, 0.07)
            end

            preview.slots[i] = slot
        end

        function preview:Render(data)
            self._data = data or self._data or {}
            local cfg = self._data
            local panelWidth = math.max(140, tonumber(cfg.width) or 300)
            local panelHeight = math.max(18, tonumber(cfg.height) or 22)
            local borderSize = math.max(0, tonumber(cfg.borderSize) or 2)
            local bgOpacity = math.max(0, math.min(100, tonumber(cfg.bgOpacity) or 50))
            local fontSize = math.max(9, math.min(18, tonumber(cfg.fontSize) or 12))
            local fontPath = cfg.fontPath or STANDARD_TEXT_FONT
            local fontOutline = cfg.fontOutline or ""
            local borderColor = cfg.borderColor or { 0, 0, 0, 1 }
            local borderR = borderColor[1] or 0
            local borderG = borderColor[2] or 0
            local borderB = borderColor[3] or 0
            local borderA = borderColor[4] or 1
            local slotTexts = cfg.slotTexts or {}
            local activeTexts = {}
            for i = 1, #slotTexts do
                if slotTexts[i] and slotTexts[i] ~= "" then
                    activeTexts[#activeTexts + 1] = slotTexts[i]
                end
            end

            self.panel:SetSize(panelWidth, panelHeight)
            self.panel.bg:SetColorTexture(0, 0, 0, bgOpacity / 100)

            self.panel.borderLeft:SetWidth(borderSize)
            self.panel.borderRight:SetWidth(borderSize)
            self.panel.borderTop:SetHeight(borderSize)
            self.panel.borderBottom:SetHeight(borderSize)
            self.panel.borderLeft:SetColorTexture(borderR, borderG, borderB, borderA)
            self.panel.borderRight:SetColorTexture(borderR, borderG, borderB, borderA)
            self.panel.borderTop:SetColorTexture(borderR, borderG, borderB, borderA)
            self.panel.borderBottom:SetColorTexture(borderR, borderG, borderB, borderA)

            self.panel.borderLeft:ClearAllPoints()
            self.panel.borderLeft:SetPoint("TOPRIGHT", self.panel, "TOPLEFT", 0, 0)
            self.panel.borderLeft:SetPoint("BOTTOMRIGHT", self.panel, "BOTTOMLEFT", 0, 0)

            self.panel.borderRight:ClearAllPoints()
            self.panel.borderRight:SetPoint("TOPLEFT", self.panel, "TOPRIGHT", 0, 0)
            self.panel.borderRight:SetPoint("BOTTOMLEFT", self.panel, "BOTTOMRIGHT", 0, 0)

            self.panel.borderTop:ClearAllPoints()
            self.panel.borderTop:SetPoint("BOTTOMLEFT", self.panel, "TOPLEFT", -borderSize, 0)
            self.panel.borderTop:SetPoint("BOTTOMRIGHT", self.panel, "TOPRIGHT", borderSize, 0)

            self.panel.borderBottom:ClearAllPoints()
            self.panel.borderBottom:SetPoint("TOPLEFT", self.panel, "BOTTOMLEFT", -borderSize, 0)
            self.panel.borderBottom:SetPoint("TOPRIGHT", self.panel, "BOTTOMRIGHT", borderSize, 0)

            local showBorder = borderSize > 0
            self.panel.borderLeft:SetShown(showBorder)
            self.panel.borderRight:SetShown(showBorder)
            self.panel.borderTop:SetShown(showBorder)
            self.panel.borderBottom:SetShown(showBorder)

            local anchorWidth = 0
            local anchorHeight = 0
            local gap = 0
            if cfg.showAnchor then
                anchorWidth = math.max(120, tonumber(cfg.anchorWidth) or panelWidth)
                anchorHeight = math.max(84, math.min(160, tonumber(cfg.anchorHeight) or anchorWidth))
                gap = 14
                self.anchorBox:SetSize(anchorWidth, anchorHeight)
                self.anchorBox:ClearAllPoints()
                self.anchorBox:SetPoint("TOP", self.canvas, "TOP", 0, 0)
                self.anchorBox:Show()
                self.anchorLabel:SetText(cfg.anchorLabel or "Minimap")
                self.panel:ClearAllPoints()
                self.panel:SetPoint("TOP", self.anchorBox, "BOTTOM", 0, -gap)
            else
                self.anchorBox:Hide()
                self.panel:ClearAllPoints()
                self.panel:SetPoint("CENTER", self.canvas, "CENTER", 0, 0)
            end

            local canvasWidth = math.max(panelWidth, anchorWidth)
            local canvasHeight = panelHeight + anchorHeight + gap
            local availableWidth = math.max(120, (self:GetWidth() or canvasWidth) - 24)
            local availableHeight = math.max(72, (self:GetHeight() or canvasHeight) - 24)
            local scale = math.min(1, availableWidth / math.max(1, canvasWidth), availableHeight / math.max(1, canvasHeight))

            self.canvas:SetSize(canvasWidth, canvasHeight)
            self.canvas:ClearAllPoints()
            self.canvas:SetPoint("CENTER")
            self.canvas:SetScale(scale)

            if not self.emptyText:SetFont(fontPath, math.max(fontSize - 1, 10), fontOutline) then
                self.emptyText:SetFont(STANDARD_TEXT_FONT, math.max(fontSize - 1, 10), fontOutline)
            end
            if #activeTexts == 0 then
                self.emptyText:SetText(cfg.emptyText or "Assign a datatext to preview this panel.")
                self.emptyText:Show()
            else
                self.emptyText:Hide()
            end

            local slotWidth = (#activeTexts > 0) and (panelWidth / #activeTexts) or panelWidth
            for i, slot in ipairs(self.slots) do
                local isActive = i <= #activeTexts
                slot:SetShown(isActive)
                if slot.separator then
                    slot.separator:SetShown(isActive and i < #activeTexts)
                end
                if isActive then
                    slot:ClearAllPoints()
                    slot:SetPoint("LEFT", self.panel, "LEFT", (i - 1) * slotWidth, 0)
                    slot:SetSize(slotWidth, panelHeight)
                    if not slot.text:SetFont(fontPath, fontSize, fontOutline) then
                        slot.text:SetFont(STANDARD_TEXT_FONT, fontSize, fontOutline)
                    end
                    slot.text:SetText(activeTexts[i])
                    slot.text:SetTextColor(1, 1, 1, 1)
                    if slot.separator then
                        slot.separator:ClearAllPoints()
                        slot.separator:SetPoint("TOPRIGHT", slot, "TOPRIGHT", 0, -3)
                        slot.separator:SetPoint("BOTTOMRIGHT", slot, "BOTTOMRIGHT", 0, 3)
                        slot.separator:SetWidth(1)
                    end
                end
            end
        end

        preview:SetScript("OnSizeChanged", function(self)
            if self._data then
                self:Render(self._data)
            end
        end)

        return preview
    end

    RegisterSharedOnly("datatextPanel", { build = function(content, key, width)
        local profile = U.GetProfileDB()
        if not profile then return 80 end

        local QUICore = ns.Addon
        local dtGlobal = EnsureMinimapDatatextConfig(profile)
        local selected = GetSelectedDatatextContext(profile)
        local dtOptions = GetDatatextOptions(QUICore)
        local sections = {}
        local function relayout() U.StandardRelayout(content, sections) end
        local preview

        local function CountSlotsWithValue(slotList, numSlots, targetValue)
            for i = 1, numSlots do
                if slotList and slotList[i] == targetValue then
                    return true
                end
            end
            return false
        end

        local function BuildSlotPreviewTexts()
            local texts = {}
            for i = 1, selected.numSlots do
                texts[i] = BuildPreviewSlotText(QUICore, selected.slots and selected.slots[i], selected.slotSettings and selected.slotSettings[i], dtGlobal)
            end
            return texts
        end

        local function RenderDatatextPreview()
            if not preview or not preview.Render then
                return
            end

            local fontPath, fontOutline = GetDatatextPreviewFontSettings()
            preview:Render({
                width = selected.isMinimap and (((profile.minimap or {}).size) or 220) or (selected.panelDB.width or 300),
                height = selected.panelDB.height or 22,
                bgOpacity = selected.panelDB.bgOpacity or 50,
                borderSize = selected.panelDB.borderSize or 2,
                borderColor = selected.panelDB.borderColor or { 0, 0, 0, 1 },
                fontSize = selected.panelDB.fontSize or dtGlobal.fontSize or 12,
                fontPath = fontPath,
                fontOutline = fontOutline,
                slotTexts = BuildSlotPreviewTexts(),
                showAnchor = false,
                emptyText = selected.isMinimap
                    and "Assign at least one minimap slot to preview this panel."
                    or "Assign at least one slot to preview this custom panel.",
            })
        end

        local function NotifyStructuralRefresh()
            local compat = ns.Settings and ns.Settings.RenderAdapters
            if compat and compat.NotifyProviderChanged then
                compat.NotifyProviderChanged("datatextPanel", { structural = true })
            end
        end

        local function RefreshAllDatatextSurfaces()
            RenderDatatextPreview()
            if _G.QUI_RefreshMinimap then _G.QUI_RefreshMinimap() end
            if QUICore and QUICore.Datapanels then QUICore.Datapanels:RefreshAll() end
            if QUICore and QUICore.Datatexts and QUICore.Datatexts.UpdateAll then
                QUICore.Datatexts:UpdateAll()
            end
        end

        U.CreateCollapsible(content, "Panel Selector", 186, function(body)
            local sy = -4
            local selectorState = { activePanel = selected.key }

            local headerRow = CreateFrame("Frame", nil, body)
            headerRow._quiDualColumnFullWidth = true
            headerRow._quiDualColumnRowHeight = 30
            headerRow:SetHeight(30)
            sy = P(headerRow, body, sy, headerRow._quiDualColumnRowHeight)

            local selector = GUI:CreateFormDropdown(
                headerRow, "Panel", GetDatapanelSelectorOptions(profile),
                "activePanel", selectorState, function(val)
                    if not val or val == selected.key or val == DatatextPanelState.activePanel then
                        return
                    end
                    DatatextPanelState.activePanel = val
                    NotifyStructuralRefresh()
                end,
                { description = "Pick which datatext panel you want to configure. The minimap panel and every custom datapanel are edited from this same tab." },
                { searchable = true, collapsible = false }
            )
            selector:SetPoint("TOPLEFT", headerRow, "TOPLEFT", 0, 0)
            selector:SetPoint("RIGHT", headerRow, "RIGHT", -196, 0)
            if selector.SetValue then selector:SetValue(selected.key, true) end

            local newBtn = GUI:CreateButton(headerRow, "+ New", 90, 24, function()
                local newPanel = CreateCustomDatapanel(profile)
                RegisterCustomDatapanelRuntime(newPanel, QUICore, profile)
                DatatextPanelState.activePanel = newPanel.id
                RefreshAllDatatextSurfaces()
                NotifyStructuralRefresh()
            end, "primary")
            newBtn:SetPoint("TOPRIGHT", headerRow, "TOPRIGHT", -100, -2)

            local deleteBtn = GUI:CreateButton(headerRow, "Delete", 90, 24, function()
                if selected.isMinimap then
                    return
                end

                GUI:ShowConfirmation({
                    title = "Delete Panel?",
                    message = "Delete '" .. (selected.label or "Datapanel") .. "'?",
                    warningText = "This cannot be undone.",
                    acceptText = "Delete",
                    cancelText = "Cancel",
                    isDestructive = true,
                    onAccept = function()
                        local _, panelIndex, panels = FindCustomDatapanel(profile, selected.key)
                        if panelIndex and panels then
                            table.remove(panels, panelIndex)
                        end
                        DatatextPanelState.activePanel = DATATEXT_MINIMAP_KEY
                        UnregisterCustomDatapanelRuntime(selected.key, QUICore)
                        RefreshAllDatatextSurfaces()
                        NotifyStructuralRefresh()
                    end,
                })
            end, "ghost")
            deleteBtn:SetPoint("TOPRIGHT", headerRow, "TOPRIGHT", 0, -2)
            deleteBtn:SetShown(not selected.isMinimap)

            preview = CreateDatatextPreview(body, 104)
            preview._quiDualColumnFullWidth = true
            preview._quiDualColumnRowHeight = 104
            preview:SetHeight(preview._quiDualColumnRowHeight)
            sy = P(preview, body, sy, preview._quiDualColumnRowHeight)
            RenderDatatextPreview()

            local hintRow = CreateFrame("Frame", nil, body)
            hintRow._quiDualColumnFullWidth = true
            hintRow._quiDualColumnRowHeight = 22
            hintRow:SetHeight(hintRow._quiDualColumnRowHeight)
            sy = P(hintRow, body, sy, hintRow._quiDualColumnRowHeight)

            local hint = hintRow:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            hint:SetPoint("LEFT", hintRow, "LEFT", 0, 0)
            hint:SetPoint("RIGHT", hintRow, "RIGHT", 0, 0)
            hint:SetTextColor(0.6, 0.6, 0.6, 0.85)
            hint:SetText(selected.isMinimap
                and "Preview shows the minimap datatext panel only. Width follows your minimap size."
                or "Sample text preview only. Empty slots collapse just like they do in-game.")
            hint:SetJustifyH("LEFT")
        end, sections, relayout)

        if selected.isMinimap then
            U.CreateCollapsible(content, "Panel Settings", 8 * FORM_ROW + 8, function(body)
                local sy = -4
                sy = P(GUI:CreateFormCheckbox(body, "Enable Minimap Datatext", "enabled", dtGlobal, RefreshAllDatatextSurfaces, { description = "Show the datatext panel anchored below the minimap." }), body, sy)
                sy = P(GUI:CreateFormCheckbox(body, "Force Single Line", "forceSingleLine", dtGlobal, RefreshAllDatatextSurfaces, { description = "Keep all minimap datatext slots on one row instead of allowing wrap." }), body, sy)
                sy = P(GUI:CreateFormSlider(body, "Panel Height (Per Row)", 18, 50, 1, "height", dtGlobal, RefreshAllDatatextSurfaces, nil, { description = "Pixel height reserved per row of minimap datatext." }), body, sy)
                sy = P(GUI:CreateFormSlider(body, "Background Transparency", 0, 100, 5, "bgOpacity", dtGlobal, RefreshAllDatatextSurfaces, nil, { description = "Opacity of the minimap datatext background (0 is invisible, 100 is fully opaque)." }), body, sy)
                sy = P(GUI:CreateFormSlider(body, "Border Size (0=hidden)", 0, 8, 1, "borderSize", dtGlobal, RefreshAllDatatextSurfaces, nil, { description = "Thickness of the minimap datatext border. Set to 0 to hide it." }), body, sy)
                sy = P(GUI:CreateFormColorPicker(body, "Border Color", "borderColor", dtGlobal, RefreshAllDatatextSurfaces, nil, { description = "Color of the minimap datatext border." }), body, sy)
                sy = P(GUI:CreateFormSlider(body, "Vertical Offset", -40, 40, 1, "offsetY", dtGlobal, RefreshAllDatatextSurfaces, nil, { description = "Vertical offset from the minimap. Positive moves up, negative moves down." }), body, sy)
                P(GUI:CreateFormSlider(body, "Text Size", 9, 18, 1, "fontSize", dtGlobal, RefreshAllDatatextSurfaces, nil, { description = "Font size of the minimap datatext labels and values." }), body, sy)
            end, sections, relayout)

            U.CreateCollapsible(content, "Slot Configuration", 15 * FORM_ROW + 30, function(body)
                local sy = -4

                local s1dd = GUI:CreateFormDropdown(body, "Slot 1 (Left)", dtOptions, nil, nil, function(val)
                    dtGlobal.slots[1] = val
                    RefreshAllDatatextSurfaces()
                    NotifyStructuralRefresh()
                end, { description = "Datatext shown in slot 1 (the leftmost slot on the minimap panel)." })
                if s1dd.SetValue then s1dd:SetValue(dtGlobal.slots[1] or "", true) end
                sy = P(s1dd, body, sy)
                sy = P(GUI:CreateFormCheckbox(body, "Slot 1 Short Label", "shortLabel", dtGlobal.slot1, RefreshAllDatatextSurfaces, { description = "Use the compact label variant for slot 1." }), body, sy)
                sy = P(GUI:CreateFormCheckbox(body, "Slot 1 No Label", "noLabel", dtGlobal.slot1, RefreshAllDatatextSurfaces, { description = "Hide the slot 1 label and show only the value." }), body, sy)
                sy = P(GUI:CreateFormSlider(body, "Slot 1 X Offset", -50, 50, 1, "xOffset", dtGlobal.slot1, RefreshAllDatatextSurfaces, nil, { description = "Horizontal pixel offset for slot 1." }), body, sy)
                sy = P(GUI:CreateFormSlider(body, "Slot 1 Y Offset", -20, 20, 1, "yOffset", dtGlobal.slot1, RefreshAllDatatextSurfaces, nil, { description = "Vertical pixel offset for slot 1." }), body, sy)

                local s2dd = GUI:CreateFormDropdown(body, "Slot 2 (Center)", dtOptions, nil, nil, function(val)
                    dtGlobal.slots[2] = val
                    RefreshAllDatatextSurfaces()
                    NotifyStructuralRefresh()
                end, { description = "Datatext shown in slot 2 (the center slot on the minimap panel)." })
                if s2dd.SetValue then s2dd:SetValue(dtGlobal.slots[2] or "", true) end
                sy = P(s2dd, body, sy)
                sy = P(GUI:CreateFormCheckbox(body, "Slot 2 Short Label", "shortLabel", dtGlobal.slot2, RefreshAllDatatextSurfaces, { description = "Use the compact label variant for slot 2." }), body, sy)
                sy = P(GUI:CreateFormCheckbox(body, "Slot 2 No Label", "noLabel", dtGlobal.slot2, RefreshAllDatatextSurfaces, { description = "Hide the slot 2 label and show only the value." }), body, sy)
                sy = P(GUI:CreateFormSlider(body, "Slot 2 X Offset", -50, 50, 1, "xOffset", dtGlobal.slot2, RefreshAllDatatextSurfaces, nil, { description = "Horizontal pixel offset for slot 2." }), body, sy)
                sy = P(GUI:CreateFormSlider(body, "Slot 2 Y Offset", -20, 20, 1, "yOffset", dtGlobal.slot2, RefreshAllDatatextSurfaces, nil, { description = "Vertical pixel offset for slot 2." }), body, sy)

                local s3dd = GUI:CreateFormDropdown(body, "Slot 3 (Right)", dtOptions, nil, nil, function(val)
                    dtGlobal.slots[3] = val
                    RefreshAllDatatextSurfaces()
                    NotifyStructuralRefresh()
                end, { description = "Datatext shown in slot 3 (the rightmost slot on the minimap panel)." })
                if s3dd.SetValue then s3dd:SetValue(dtGlobal.slots[3] or "", true) end
                sy = P(s3dd, body, sy)
                sy = P(GUI:CreateFormCheckbox(body, "Slot 3 Short Label", "shortLabel", dtGlobal.slot3, RefreshAllDatatextSurfaces, { description = "Use the compact label variant for slot 3." }), body, sy)
                sy = P(GUI:CreateFormCheckbox(body, "Slot 3 No Label", "noLabel", dtGlobal.slot3, RefreshAllDatatextSurfaces, { description = "Hide the slot 3 label and show only the value." }), body, sy)
                sy = P(GUI:CreateFormSlider(body, "Slot 3 X Offset", -50, 50, 1, "xOffset", dtGlobal.slot3, RefreshAllDatatextSurfaces, nil, { description = "Horizontal pixel offset for slot 3." }), body, sy)
                P(GUI:CreateFormSlider(body, "Slot 3 Y Offset", -20, 20, 1, "yOffset", dtGlobal.slot3, RefreshAllDatatextSurfaces, nil, { description = "Vertical pixel offset for slot 3." }), body, sy)
            end, sections, relayout)
        else
            RegisterCustomDatapanelRuntime(selected.panelDB, QUICore, profile)

            U.CreateCollapsible(content, "Panel Settings", 10 * FORM_ROW + 8, function(body)
                local sy = -4

                local nameField = GUI:CreateFormEditBox(body, "Panel Name", "name", selected.panelDB, function()
                    UpdateCustomDatapanelRuntimeLabel(selected.panelDB)
                    RefreshAllDatatextSurfaces()
                    NotifyStructuralRefresh()
                end, { maxLetters = 48 }, { description = "Name used in the selector and in Layout Mode for this custom datapanel." })
                sy = P(nameField, body, sy)
                sy = P(GUI:CreateFormCheckbox(body, "Enabled", "enabled", selected.panelDB, RefreshAllDatatextSurfaces, { description = "Enable or disable this custom datapanel." }), body, sy)
                sy = P(GUI:CreateFormCheckbox(body, "Lock Position", "locked", selected.panelDB, RefreshAllDatatextSurfaces, { description = "Prevent this panel from being dragged in-game until unlocked." }), body, sy)
                sy = P(GUI:CreateFormSlider(body, "Width", 100, 800, 1, "width", selected.panelDB, RefreshAllDatatextSurfaces, nil, { description = "Width of this custom datapanel in pixels." }), body, sy)
                sy = P(GUI:CreateFormSlider(body, "Height", 16, 60, 1, "height", selected.panelDB, RefreshAllDatatextSurfaces, nil, { description = "Height of this custom datapanel in pixels." }), body, sy)

                local numSlotsSlider = GUI:CreateFormSlider(body, "Number of Slots", 1, 8, 1, "numSlots", selected.panelDB, function()
                    EnsureCustomDatapanelDefaults(selected.panelDB)
                    RefreshAllDatatextSurfaces()
                    NotifyStructuralRefresh()
                end, nil, { description = "How many datatext slots this panel shows. Empty slots stay hidden." })
                sy = P(numSlotsSlider, body, sy)

                sy = P(GUI:CreateFormSlider(body, "Background Opacity", 0, 100, 5, "bgOpacity", selected.panelDB, RefreshAllDatatextSurfaces, nil, { description = "Opacity of the panel background fill. 0 is fully transparent, 100 is fully opaque." }), body, sy)
                sy = P(GUI:CreateFormSlider(body, "Border Size (0=hidden)", 0, 8, 1, "borderSize", selected.panelDB, RefreshAllDatatextSurfaces, nil, { description = "Border thickness in pixels. Set to 0 to hide the border entirely." }), body, sy)
                sy = P(GUI:CreateFormColorPicker(body, "Border Color", "borderColor", selected.panelDB, RefreshAllDatatextSurfaces, nil, { description = "Color used for the panel border." }), body, sy)
                P(GUI:CreateFormSlider(body, "Font Size", 8, 18, 1, "fontSize", selected.panelDB, RefreshAllDatatextSurfaces, nil, { description = "Font size for every datatext slot on this panel." }), body, sy)
            end, sections, relayout)

            U.CreateCollapsible(content, "Slot Configuration", math.max(1, selected.numSlots) * (3 * FORM_ROW) + 16, function(body)
                local sy = -4
                for s = 1, selected.numSlots do
                    local slotSettings = selected.panelDB.slotSettings[s]
                    local slotDD = GUI:CreateFormDropdown(body, "Slot " .. s, dtOptions, nil, nil, function(val)
                        selected.panelDB.slots[s] = val
                        RefreshAllDatatextSurfaces()
                        NotifyStructuralRefresh()
                    end, { description = "Pick which datatext this slot displays. Empty slots stay hidden and the remaining slots share the width." })
                    if slotDD.SetValue then slotDD:SetValue(selected.panelDB.slots[s] or "", true) end
                    sy = P(slotDD, body, sy)
                    sy = P(GUI:CreateFormCheckbox(body, "Slot " .. s .. " Short Label", "shortLabel", slotSettings, RefreshAllDatatextSurfaces, { description = "Use the compact label variant for this slot." }), body, sy)
                    sy = P(GUI:CreateFormCheckbox(body, "Slot " .. s .. " No Label", "noLabel", slotSettings, RefreshAllDatatextSurfaces, { description = "Hide the label and show only the value for this slot." }), body, sy)
                end
            end, sections, relayout)
        end

        U.CreateCollapsible(content, "Text Styling", 3 * FORM_ROW + 8, function(body)
            local sy = -4
            sy = P(GUI:CreateFormCheckbox(body, "Use Class Color", "useClassColor", dtGlobal, RefreshAllDatatextSurfaces, { description = "Color datatext values by your class instead of the custom swatch below." }), body, sy)
            sy = P(GUI:CreateFormColorPicker(body, "Custom Text Color", "valueColor", dtGlobal, RefreshAllDatatextSurfaces, nil, { description = "Color used for datatext values when Use Class Color is off." }), body, sy)

            local note = body:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            note:SetPoint("TOPLEFT", 4, sy)
            note:SetPoint("RIGHT", body, "RIGHT", -4, 0)
            note:SetTextColor(0.6, 0.6, 0.6, 0.8)
            note:SetText("Applies to every datatext panel")
            note:SetJustifyH("LEFT")
        end, sections, relayout)

        if CountSlotsWithValue(selected.slots, selected.numSlots, "playerspec") then
            U.CreateCollapsible(content, "Spec Display", 1 * FORM_ROW + 20, function(body)
                local sy = -4
                local specOpts = {
                    { value = "icon", text = "Icon Only" },
                    { value = "loadout", text = "Icon + Loadout" },
                    { value = "full", text = "Full (Spec / Loadout)" },
                }
                P(GUI:CreateFormDropdown(body, "Spec Display Mode", specOpts, "specDisplayMode", dtGlobal, RefreshAllDatatextSurfaces, { description = "How the Spec datatext renders: just the icon, icon plus loadout, or the full spec and loadout label." }), body, sy)

                local note = body:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                note:SetPoint("TOPLEFT", 4, sy - FORM_ROW)
                note:SetPoint("RIGHT", body, "RIGHT", -4, 0)
                note:SetTextColor(0.6, 0.6, 0.6, 0.8)
                note:SetText("Applies to all panels with Spec datatext")
                note:SetJustifyH("LEFT")
            end, sections, relayout)
        end

        if CountSlotsWithValue(selected.slots, selected.numSlots, "time") then
            U.CreateCollapsible(content, "Time Options", 3 * FORM_ROW + 20, function(body)
                local sy = -4
                sy = P(GUI:CreateFormDropdown(body, "Time Format", {
                    { value = "local", text = "Local Time" },
                    { value = "server", text = "Server Time" },
                }, "timeFormat", dtGlobal, RefreshAllDatatextSurfaces, { description = "Whether the Time datatext shows your local system time or realm server time." }), body, sy)
                sy = P(GUI:CreateFormDropdown(body, "Clock Format", {
                    { value = true, text = "24-Hour Clock" },
                    { value = false, text = "AM/PM" },
                }, "use24Hour", dtGlobal, RefreshAllDatatextSurfaces, { description = "Display time as 24-hour or 12-hour AM/PM." }), body, sy)
                P(GUI:CreateFormSlider(body, "Lockout Refresh (minutes)", 1, 30, 1, "lockoutCacheMinutes", dtGlobal, nil, nil, { description = "How often raid lockout info is refreshed when shown in the Time tooltip." }), body, sy)

                local note = body:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                note:SetPoint("TOPLEFT", 4, sy - FORM_ROW)
                note:SetPoint("RIGHT", body, "RIGHT", -4, 0)
                note:SetTextColor(0.6, 0.6, 0.6, 0.8)
                note:SetText("Applies to all panels with Time datatext")
                note:SetJustifyH("LEFT")
            end, sections, relayout)
        end

        if CountSlotsWithValue(selected.slots, selected.numSlots, "currencies") then
            local trackedCurrencies = {}
            if _G.C_CurrencyInfo and C_CurrencyInfo.GetBackpackCurrencyInfo then
                local i = 1
                local seen = {}
                while true do
                    local info = C_CurrencyInfo.GetBackpackCurrencyInfo(i)
                    if not info then break end
                    local currencyID = info.currencyTypesID or info.currencyID
                    if currencyID and info.name and not seen[currencyID] then
                        seen[currencyID] = true
                        trackedCurrencies[#trackedCurrencies + 1] = {
                            value = tostring(currencyID),
                            text = info.name,
                        }
                    end
                    i = i + 1
                end
            end

            if type(dtGlobal.currencyOrder) ~= "table" then dtGlobal.currencyOrder = {} end
            if type(dtGlobal.currencyEnabled) ~= "table" then dtGlobal.currencyEnabled = {} end

            local trackedById = {}
            for _, c in ipairs(trackedCurrencies) do trackedById[c.value] = c end

            local ordered = {}
            local seen = {}
            for _, rawVal in ipairs(dtGlobal.currencyOrder) do
                local val = type(rawVal) == "number" and tostring(rawVal) or rawVal
                if val and val ~= "" and val ~= "none" and trackedById[val] and not seen[val] then
                    seen[val] = true
                    ordered[#ordered + 1] = val
                end
            end
            for _, c in ipairs(trackedCurrencies) do
                if not seen[c.value] then
                    ordered[#ordered + 1] = c.value
                end
            end
            dtGlobal.currencyOrder = ordered

            for _, cid in ipairs(ordered) do
                if dtGlobal.currencyEnabled[cid] == nil then
                    dtGlobal.currencyEnabled[cid] = true
                end
            end

            local rowCount = math.max(#ordered, 1)
            U.CreateCollapsible(content, "Currencies", rowCount * FORM_ROW + 28, function(body)
                local sy = -4

                local note = body:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                note:SetPoint("TOPLEFT", 4, sy)
                note:SetPoint("RIGHT", body, "RIGHT", -4, 0)
                note:SetTextColor(0.6, 0.6, 0.6, 0.8)
                note:SetText("First 6 enabled are displayed. Use arrows to reorder.")
                note:SetJustifyH("LEFT")
                sy = sy - 18

                if #ordered == 0 then
                    local empty = body:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                    empty:SetPoint("TOPLEFT", 4, sy)
                    empty:SetTextColor(0.6, 0.6, 0.6, 1)
                    empty:SetText("No tracked currencies. Track currencies via the backpack.")
                else
                    local rowFrames = {}
                    local function RebuildCurrencyRows()
                        for _, rf in ipairs(rowFrames) do rf:Hide() end

                        local ry = sy
                        for idx, cid in ipairs(dtGlobal.currencyOrder) do
                            local cInfo = trackedById[cid]
                            local displayName = cInfo and cInfo.text or cid

                            local row = rowFrames[idx]
                            if not row then
                                row = CreateFrame("Frame", nil, body)
                                row:SetHeight(FORM_ROW - 4)
                                rowFrames[idx] = row
                            end
                            row:ClearAllPoints()
                            row:SetPoint("TOPLEFT", body, "TOPLEFT", 0, ry)
                            row:SetPoint("RIGHT", body, "RIGHT", 0, 0)
                            row:Show()

                            if not row._built then
                                row._cb = GUI:CreateFormCheckbox(row, "", nil, nil, nil, { description = "Toggle this currency in the Currencies datatext. Use the arrows to reorder." })
                                row._cb:SetPoint("LEFT", 4, 0)
                                row._cb:SetHeight(FORM_ROW - 4)

                                row._upBtn = CreateFrame("Button", nil, row)
                                row._upBtn:SetSize(16, 16)
                                row._upBtn:SetPoint("RIGHT", row, "RIGHT", -24, 0)
                                row._upBtn:SetNormalFontObject("GameFontNormalSmall")
                                row._upBtn:SetText("^")
                                row._upBtn:GetFontString():SetTextColor(0.376, 0.647, 0.980, 1)

                                row._downBtn = CreateFrame("Button", nil, row)
                                row._downBtn:SetSize(16, 16)
                                row._downBtn:SetPoint("RIGHT", row, "RIGHT", -4, 0)
                                row._downBtn:SetNormalFontObject("GameFontNormalSmall")
                                row._downBtn:SetText("v")
                                row._downBtn:GetFontString():SetTextColor(0.376, 0.647, 0.980, 1)

                                row._built = true
                            end

                            row._cb.label:SetText(displayName)
                            row._cb:SetChecked(dtGlobal.currencyEnabled[cid] ~= false)
                            row._cb:SetScript("OnClick", function(self)
                                dtGlobal.currencyEnabled[cid] = self:GetChecked()
                                RefreshAllDatatextSurfaces()
                                NotifyProviderFor(row._cb, { structural = true })
                            end)

                            local capturedIdx = idx
                            row._upBtn:SetScript("OnClick", function()
                                if capturedIdx > 1 then
                                    local order = dtGlobal.currencyOrder
                                    order[capturedIdx], order[capturedIdx - 1] = order[capturedIdx - 1], order[capturedIdx]
                                    RebuildCurrencyRows()
                                    RefreshAllDatatextSurfaces()
                                    NotifyProviderFor(row._upBtn, { structural = true })
                                end
                            end)
                            row._upBtn:SetAlpha(idx > 1 and 1 or 0.3)

                            row._downBtn:SetScript("OnClick", function()
                                if capturedIdx < #dtGlobal.currencyOrder then
                                    local order = dtGlobal.currencyOrder
                                    order[capturedIdx], order[capturedIdx + 1] = order[capturedIdx + 1], order[capturedIdx]
                                    RebuildCurrencyRows()
                                    RefreshAllDatatextSurfaces()
                                    NotifyProviderFor(row._downBtn, { structural = true })
                                end
                            end)
                            row._downBtn:SetAlpha(idx < #dtGlobal.currencyOrder and 1 or 0.3)

                            ry = ry - FORM_ROW
                        end

                        local realHeight = math.abs(sy) + #dtGlobal.currencyOrder * FORM_ROW + 8
                        body:SetHeight(realHeight)
                        local sec = body:GetParent()
                        if sec and sec._expanded then
                            sec._contentHeight = realHeight
                            sec:SetHeight((U.HEADER_HEIGHT or 24) + realHeight)
                            relayout()
                        end
                    end

                    RebuildCurrencyRows()
                end

                local globalNote = body:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                globalNote:SetPoint("BOTTOMLEFT", body, "BOTTOMLEFT", 4, 4)
                globalNote:SetPoint("RIGHT", body, "RIGHT", -4, 0)
                globalNote:SetTextColor(0.6, 0.6, 0.6, 0.8)
                globalNote:SetText("Applies to all panels with Currencies datatext")
                globalNote:SetJustifyH("LEFT")
            end, sections, relayout)
        end

        if selected.isMinimap then
            U.BuildPositionCollapsible(content, "datatextPanel", nil, sections, relayout)
        else
            U.BuildPositionCollapsible(content, selected.positionKey, { autoWidth = true }, sections, relayout)
        end
        U.BuildOpenFullSettingsLink(content, key, sections, relayout)
        relayout()
        return content:GetHeight()
    end })
end)
