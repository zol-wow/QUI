--[[
    QUI Minimap Shared Settings Providers
    Owns provider-backed settings content for the Minimap surface
    in the shared settings layer. Migrated to V3 body pattern
    (CreateAccentDotLabel + CreateSettingsCardGroup + BuildSettingRow).
]]

local _, ns = ...

local Settings = ns.Settings
local ProviderPanels = Settings and Settings.ProviderPanels
if not ProviderPanels or type(ProviderPanels.RegisterAfterLoad) ~= "function" then
    return
end

-- NOTE: do NOT capture `ns.QUI_Options` as a local in this outer closure.
-- This file is loaded by the QUI addon before the on-demand QUI_Options
-- addon is loaded; at that point ns.QUI_Options is the minimal stub
-- installed by core/gui_shell.lua. Once QUI_Options/shared.lua runs it
-- REPLACES the table, so any captured local would be stale. Re-resolve
-- ns.QUI_Options at call time inside MakeLayout / row / build bodies.
ProviderPanels:RegisterAfterLoad(function(ctx)
    local GUI = ctx.GUI
    local U = ctx.U
    local PAD = (ns.QUI_Options and ns.QUI_Options.PADDING) or 15
    local HEADER_GAP = 26
    local SECTION_GAP = 14

    -- Shared provider-panel layout scaffold (core/settings_layout_shared.lua).
    local function MakeLayout(content)
        if U._layoutModePositionOnly then
            return U.MakeSuppressedProviderLayout(content)
        end
        return ns.QUI_SettingsLayoutShared.MakeLayout(content, U)
    end

    local function row(parent, label, widget, desc)
        return ns.QUI_Options.BuildSettingRow(parent, label, widget, desc)
    end

    ---------------------------------------------------------------------------
    -- MINIMAP PROVIDER
    ---------------------------------------------------------------------------
    ctx.RegisterShared("minimap", { build = function(content, key, _width)
        local db = U.GetProfileDB()
        if not db or not db.minimap or not ns.QUI_Options then return 80 end
        local mm = db.minimap
        if not db.uiHider then db.uiHider = {} end

        local function Refresh() if _G.QUI_RefreshMinimap then _G.QUI_RefreshMinimap() end end
        local function RefreshUIHider() if _G.QUI_RefreshUIHider then _G.QUI_RefreshUIHider() end end

        local L = MakeLayout(content)

        -- GENERAL
        L.headerAt("General")
        local s1 = L.sectionAt()
        local sizeW = GUI:CreateFormSlider(s1.frame, nil, 120, 380, 1, "size", mm, Refresh,
            { description = "Pixel size of the minimap (width = height)." })
        local zoomW = GUI:CreateFormSlider(s1.frame, nil, 0, 5, 1, "zoomLevel", mm, Refresh,
            { description = "Default zoom level applied to the minimap. 0 is fully zoomed out." })
        s1.AddRow(row(s1.frame, "Map Dimensions", sizeW), row(s1.frame, "Map Zoom Level", zoomW))

        local middleW = GUI:CreateFormCheckbox(s1.frame, nil, "middleClickMenuEnabled", mm, Refresh,
            { description = "Open the tracking/options menu when you middle-click the minimap." })
        local autoZoomW = GUI:CreateFormCheckbox(s1.frame, nil, "autoZoom", mm, nil,
            { description = "Gradually zoom the minimap back out to the default zoom level after a period of inactivity." })
        s1.AddRow(row(s1.frame, "Middle-Click Menu", middleW), row(s1.frame, "Auto-Zoom After Idle", autoZoomW))

        local coordW = GUI:CreateFormSlider(s1.frame, nil, 1, 10, 1, "coordUpdateInterval", mm, nil,
            { description = "How often the coordinate datatext refreshes, in seconds. Lower is smoother but slightly more expensive." })
        local btnRadiusW = GUI:CreateFormSlider(s1.frame, nil, 0, 12, 1, "buttonRadius", mm, Refresh,
            { description = "Corner rounding applied to addon minimap buttons in pixels. 0 is square." })
        s1.AddRow(row(s1.frame, "Coord Update Interval (sec)", coordW), row(s1.frame, "Addon Button Corner Radius", btnRadiusW))

        local hideAddonW = GUI:CreateFormCheckbox(s1.frame, nil, "hideAddonButtons", mm, function()
            if _G.QUI_RefreshMinimapAddonButtons then _G.QUI_RefreshMinimapAddonButtons() end
        end, { description = "Hide addon minimap buttons until you mouse over the minimap. Reduces clutter when you aren't using them." })
        s1.AddRow(row(s1.frame, "Hide Addon Buttons Until Hover", hideAddonW))
        L.closeSection(s1)

        -- BORDER
        L.headerAt("Border")
        local s2 = L.sectionAt()
        local borderSizeW = GUI:CreateFormSlider(s2.frame, nil, 1, 16, 1, "borderSize", mm, Refresh,
            { description = "Thickness of the border drawn around the minimap." })
        s2.AddRow(row(s2.frame, "Border Size", borderSizeW))

        local srcW, colorW = ns.QUI_BorderControl.Attach(GUI, s2.frame, mm, "", Refresh,
            { label = "Border Color Source", colorLabel = "Border Color" })
        s2.AddRow(row(s2.frame, "Border Color Source", srcW), row(s2.frame, "Border Color", colorW))
        L.closeSection(s2)

        -- HIDE ELEMENTS
        L.headerAt("Hide Elements")
        local s3 = L.sectionAt()
        local hideMailW = GUI:CreateFormCheckboxInverted(s3.frame, nil, "showMail", mm, Refresh,
            { description = "Hide the mail notification icon on the minimap. Requires a UI reload to take effect." })
        local hideCraftW = GUI:CreateFormCheckboxInverted(s3.frame, nil, "showCraftingOrder", mm, Refresh,
            { description = "Hide the crafting/work order notification icon on the minimap." })
        s3.AddRow(row(s3.frame, "Hide Mail (reload after)", hideMailW), row(s3.frame, "Hide Work Order Notification", hideCraftW))

        local hideTrackW = GUI:CreateFormCheckboxInverted(s3.frame, nil, "showTracking", mm, Refresh,
            { description = "Hide the tracking/eye icon on the minimap." })
        local hideDiffW = GUI:CreateFormCheckboxInverted(s3.frame, nil, "showDifficulty", mm, Refresh,
            { description = "Hide the instance difficulty indicator on the minimap." })
        s3.AddRow(row(s3.frame, "Hide Tracking", hideTrackW), row(s3.frame, "Hide Difficulty", hideDiffW))

        local hideMissW = GUI:CreateFormCheckboxInverted(s3.frame, nil, "showMissions", mm, Refresh,
            { description = "Hide the garrison / mission table / expedition report button on the minimap." })
        local hideBorderW = GUI:CreateFormCheckbox(s3.frame, nil, "hideMinimapBorder", db.uiHider, RefreshUIHider,
            { description = "Hide the native Blizzard minimap border artwork at the top of the minimap." })
        s3.AddRow(row(s3.frame, "Hide Garrison/Mission Report", hideMissW), row(s3.frame, "Hide Border (Top)", hideBorderW))

        local hideClockW = GUI:CreateFormCheckbox(s3.frame, nil, "hideTimeManager", db.uiHider, RefreshUIHider,
            { description = "Hide the Blizzard clock/stopwatch button on the minimap." })
        local hideCalW = GUI:CreateFormCheckbox(s3.frame, nil, "hideGameTime", db.uiHider, RefreshUIHider,
            { description = "Hide the Blizzard calendar button on the minimap." })
        s3.AddRow(row(s3.frame, "Hide Clock Button", hideClockW), row(s3.frame, "Hide Calendar Button", hideCalW))

        local hideZoneW = GUI:CreateFormCheckbox(s3.frame, nil, "hideMinimapZoneText", db.uiHider, RefreshUIHider,
            { description = "Hide the Blizzard zone-text label above the minimap. Use the QUI zone label below for a replacement." })
        local hideZoomW = GUI:CreateFormCheckboxInverted(s3.frame, nil, "showZoomButtons", mm, Refresh,
            { description = "Hide the + / - zoom buttons on the minimap. You can still mouse-wheel to zoom." })
        s3.AddRow(row(s3.frame, "Hide Zone Text (Native)", hideZoneW), row(s3.frame, "Hide Zoom Buttons", hideZoomW))
        L.closeSection(s3)

        -- ZONE LABEL
        L.headerAt("Zone Label")
        local s4 = L.sectionAt()
        if not mm.zoneTextConfig then mm.zoneTextConfig = {} end
        local ztc = mm.zoneTextConfig

        local showZoneW = GUI:CreateFormCheckbox(s4.frame, nil, "showZoneText", mm, Refresh,
            { description = "Show the QUI zone label above the minimap." })
        local zlSizeW = GUI:CreateFormSlider(s4.frame, nil, 8, 20, 1, "fontSize", ztc, Refresh,
            { description = "Font size of the zone label text." })
        s4.AddRow(row(s4.frame, "Show Zone Label", showZoneW), row(s4.frame, "Label Size", zlSizeW))

        local zlXW = GUI:CreateFormSlider(s4.frame, nil, -150, 150, 1, "offsetX", ztc, Refresh,
            { description = "Horizontal pixel offset for the zone label from its anchor. Positive moves right, negative moves left." })
        local zlYW = GUI:CreateFormSlider(s4.frame, nil, -150, 150, 1, "offsetY", ztc, Refresh,
            { description = "Vertical pixel offset for the zone label from its anchor. Positive moves up, negative moves down." })
        s4.AddRow(row(s4.frame, "Horizontal Offset", zlXW), row(s4.frame, "Vertical Offset", zlYW))

        local zlAllCapsW = GUI:CreateFormCheckbox(s4.frame, nil, "allCaps", ztc, Refresh,
            { description = "Render the zone label in all uppercase letters." })
        local zlClassW = GUI:CreateFormCheckbox(s4.frame, nil, "useClassColor", ztc, Refresh,
            { description = "Color the zone label by your class instead of by the zone's PvP status." })
        s4.AddRow(row(s4.frame, "Uppercase Text", zlAllCapsW), row(s4.frame, "Use Class Color", zlClassW))
        L.closeSection(s4)

        -- DUNGEON EYE
        if not mm.dungeonEye then
            mm.dungeonEye = { enabled = true, corner = "BOTTOMLEFT", scale = 0.6, offsetX = 0, offsetY = 0 }
        end
        local eye = mm.dungeonEye
        local cornerOptions = {
            { value = "TOPRIGHT", text = "Top Right" },
            { value = "TOPLEFT", text = "Top Left" },
            { value = "BOTTOMRIGHT", text = "Bottom Right" },
            { value = "BOTTOMLEFT", text = "Bottom Left" },
        }

        L.headerAt("Dungeon Eye")
        local s5 = L.sectionAt()
        local eyeEnableW = GUI:CreateFormCheckbox(s5.frame, nil, "enabled", eye, Refresh,
            { description = "Show the LFG eye icon on a corner of the minimap while you're queued for a dungeon or raid." })
        local eyeCornerW = GUI:CreateFormDropdown(s5.frame, nil, cornerOptions, "corner", eye, Refresh,
            { description = "Which corner of the minimap the dungeon eye icon is anchored to." })
        s5.AddRow(row(s5.frame, "Enable Dungeon Eye", eyeEnableW), row(s5.frame, "Corner Position", eyeCornerW))

        local eyeScaleW = GUI:CreateFormSlider(s5.frame, nil, 0.1, 2.0, 0.1, "scale", eye, Refresh,
            { description = "Scale multiplier applied to the dungeon eye icon." })
        local eyeXW = GUI:CreateFormSlider(s5.frame, nil, -30, 30, 1, "offsetX", eye, Refresh,
            { description = "Horizontal pixel offset for the dungeon eye from its corner." })
        s5.AddRow(row(s5.frame, "Icon Scale", eyeScaleW), row(s5.frame, "X Offset", eyeXW))

        local eyeYW = GUI:CreateFormSlider(s5.frame, nil, -30, 30, 1, "offsetY", eye, Refresh,
            { description = "Vertical pixel offset for the dungeon eye from its corner." })
        s5.AddRow(row(s5.frame, "Y Offset", eyeYW))
        L.closeSection(s5)

        -- GREAT VAULT
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
            { value = "TOPLEFT", text = "Top Left" },
            { value = "TOP", text = "Top" },
            { value = "TOPRIGHT", text = "Top Right" },
            { value = "LEFT", text = "Left" },
            { value = "CENTER", text = "Center" },
            { value = "RIGHT", text = "Right" },
            { value = "BOTTOMLEFT", text = "Bottom Left" },
            { value = "BOTTOM", text = "Bottom" },
            { value = "BOTTOMRIGHT", text = "Bottom Right" },
        }

        L.headerAt("Great Vault")
        local s6 = L.sectionAt()
        local gvEnableW = GUI:CreateFormCheckbox(s6.frame, nil, "enabled", vault, Refresh,
            { description = "Show a clickable Great Vault shortcut anchored relative to the minimap." })
        local gvFadeW = GUI:CreateFormCheckbox(s6.frame, nil, "fadeWhenMouseOut", vault, Refresh,
            { description = "Fade the Great Vault button down when you aren't hovering the minimap." })
        s6.AddRow(row(s6.frame, "Enable Great Vault Button", gvEnableW), row(s6.frame, "Fade When Not Hovered", gvFadeW))

        local gvOpacityW = GUI:CreateFormSlider(s6.frame, nil, 0, 1, 0.05, "fadeOpacity", vault, Refresh,
            { precision = 2, description = "Opacity the button fades down to when not hovered (0 fully invisible, 1 fully opaque)." })
        local gvAnchorW = GUI:CreateFormDropdown(s6.frame, nil, vaultAnchorOptions, "anchor", vault, Refresh,
            { description = "Which point of the minimap the Great Vault button anchors to." })
        s6.AddRow(row(s6.frame, "Fade Opacity", gvOpacityW), row(s6.frame, "Anchor", gvAnchorW))

        local gvScaleW = GUI:CreateFormSlider(s6.frame, nil, 0.5, 2.0, 0.1, "scale", vault, Refresh,
            { description = "Scale multiplier applied to the Great Vault icon." })
        local gvXW = GUI:CreateFormSlider(s6.frame, nil, -200, 200, 1, "offsetX", vault, Refresh,
            { description = "Horizontal pixel offset from the anchor point." })
        s6.AddRow(row(s6.frame, "Icon Scale", gvScaleW), row(s6.frame, "X Offset", gvXW))

        local gvYW = GUI:CreateFormSlider(s6.frame, nil, -200, 200, 1, "offsetY", vault, Refresh,
            { description = "Vertical pixel offset from the anchor point." })
        s6.AddRow(row(s6.frame, "Y Offset", gvYW))
        L.closeSection(s6)

        -- BUTTON DRAWER
        if not mm.buttonDrawer then
            mm.buttonDrawer = {
                enabled = false, anchor = "RIGHT", offsetX = 0, offsetY = 0,
                toggleOffsetX = 0, toggleOffsetY = 0, autoHideDelay = 1.5,
                buttonSize = 28, buttonSpacing = 2, padding = 6, columns = 1,
                growthDirection = "RIGHT", centerGrowth = false,
                bgColor = { 0.03, 0.03, 0.03, 1 }, bgOpacity = 98,
                borderSize = 1, borderColor = { 0.2, 0.8, 0.6, 1 },
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
        if not drawer.bgColor then drawer.bgColor = { 0.03, 0.03, 0.03, 1 } end
        if drawer.bgOpacity == nil then drawer.bgOpacity = 98 end
        if drawer.borderSize == nil then drawer.borderSize = 1 end
        if not drawer.borderColor then drawer.borderColor = { 0.2, 0.8, 0.6, 1 } end

        local anchorOptions = {
            { value = "RIGHT", text = "Right" }, { value = "LEFT", text = "Left" },
            { value = "TOP", text = "Top" }, { value = "BOTTOM", text = "Bottom" },
            { value = "TOPLEFT", text = "Top Left" }, { value = "TOPRIGHT", text = "Top Right" },
            { value = "BOTTOMLEFT", text = "Bottom Left" }, { value = "BOTTOMRIGHT", text = "Bottom Right" },
        }
        local growthOptions = {
            { value = "RIGHT", text = "Right" }, { value = "LEFT", text = "Left" },
            { value = "DOWN", text = "Down" }, { value = "UP", text = "Up" },
        }
        local toggleIconOptions = {
            { value = "hammer", text = "Hammer" }, { value = "grid", text = "Grid Dots" },
        }

        L.headerAt("Button Drawer")
        local s7 = L.sectionAt()
        local bdEnableW = GUI:CreateFormCheckbox(s7.frame, nil, "enabled", drawer, Refresh,
            { description = "Collect addon minimap buttons into a hideable drawer attached to the minimap." })
        local bdHoverW = GUI:CreateFormCheckbox(s7.frame, nil, "openOnMouseover", drawer, Refresh,
            { description = "Open the drawer automatically when you hover the toggle button. Off requires a click to open." })
        s7.AddRow(row(s7.frame, "Enable Button Drawer", bdEnableW), row(s7.frame, "Open on Mouseover", bdHoverW))

        local bdAnchorW = GUI:CreateFormDropdown(s7.frame, nil, anchorOptions, "anchor", drawer, Refresh,
            { description = "Which side of the minimap the drawer expands out from." })
        local bdAutoHideW = GUI:CreateFormSlider(s7.frame, nil, 0, 5, 0.5, "autoHideDelay", drawer, Refresh,
            { description = "Seconds the drawer stays open after your cursor leaves. Set to 0 to require a manual close." })
        s7.AddRow(row(s7.frame, "Anchor Side", bdAnchorW), row(s7.frame, "Auto-Hide Delay (0=manual)", bdAutoHideW))

        local bdXW = GUI:CreateFormSlider(s7.frame, nil, -200, 200, 1, "offsetX", drawer, Refresh,
            { description = "Horizontal pixel offset for the drawer body from its anchor." })
        local bdYW = GUI:CreateFormSlider(s7.frame, nil, -200, 200, 1, "offsetY", drawer, Refresh,
            { description = "Vertical pixel offset for the drawer body from its anchor." })
        s7.AddRow(row(s7.frame, "Drawer X Offset", bdXW), row(s7.frame, "Drawer Y Offset", bdYW))

        local bdTogXW = GUI:CreateFormSlider(s7.frame, nil, -200, 200, 1, "toggleOffsetX", drawer, Refresh,
            { description = "Horizontal pixel offset for the drawer toggle button." })
        local bdTogYW = GUI:CreateFormSlider(s7.frame, nil, -200, 200, 1, "toggleOffsetY", drawer, Refresh,
            { description = "Vertical pixel offset for the drawer toggle button." })
        s7.AddRow(row(s7.frame, "Button X Offset", bdTogXW), row(s7.frame, "Button Y Offset", bdTogYW))

        local bdTogSizeW = GUI:CreateFormSlider(s7.frame, nil, 12, 40, 1, "toggleSize", drawer, Refresh,
            { description = "Pixel size of the drawer toggle button." })
        local bdTogIconW = GUI:CreateFormDropdown(s7.frame, nil, toggleIconOptions, "toggleIcon", drawer, Refresh,
            { description = "Icon used for the drawer toggle button." })
        s7.AddRow(row(s7.frame, "Toggle Size", bdTogSizeW), row(s7.frame, "Toggle Icon", bdTogIconW))

        local bdBtnSizeW = GUI:CreateFormSlider(s7.frame, nil, 20, 40, 1, "buttonSize", drawer, Refresh,
            { description = "Pixel size of each addon button inside the drawer." })
        local bdPadW = GUI:CreateFormSlider(s7.frame, nil, 0, 20, 1, "padding", drawer, Refresh,
            { description = "Pixel padding between the drawer border and the first/last addon button." })
        s7.AddRow(row(s7.frame, "Button Size", bdBtnSizeW), row(s7.frame, "Inner Padding", bdPadW))

        local bdColsW = GUI:CreateFormSlider(s7.frame, nil, 1, 6, 1, "columns", drawer, Refresh,
            { description = "How many columns of buttons the drawer uses before wrapping to a new row." })
        local bdGrowthW = GUI:CreateFormDropdown(s7.frame, nil, growthOptions, "growthDirection", drawer, Refresh,
            { description = "Direction the drawer extends as more buttons are added." })
        s7.AddRow(row(s7.frame, "Columns", bdColsW), row(s7.frame, "Growth Direction", bdGrowthW))

        local bdCenterW = GUI:CreateFormCheckbox(s7.frame, nil, "centerGrowth", drawer, Refresh,
            { description = "Center the drawer along its growth axis instead of extending in one direction." })
        local bdAutoTogW = GUI:CreateFormCheckbox(s7.frame, nil, "autoHideToggle", drawer, Refresh,
            { description = "Hide the drawer toggle button until you mouse over the minimap." })
        s7.AddRow(row(s7.frame, "Center Growth", bdCenterW), row(s7.frame, "Auto-Hide Toggle Button", bdAutoTogW))

        local bdSpaceW = GUI:CreateFormSlider(s7.frame, nil, 0, 20, 1, "buttonSpacing", drawer, Refresh,
            { description = "Pixel gap between buttons inside the drawer." })
        s7.AddRow(row(s7.frame, "Button Spacing", bdSpaceW))
        L.closeSection(s7)

        -- DRAWER APPEARANCE
        L.headerAt("Drawer Appearance")
        local s8 = L.sectionAt()
        local daBgColorW = GUI:CreateFormColorPicker(s8.frame, nil, "bgColor", drawer, Refresh,
            { noAlpha = true, description = "Background color of the drawer body." })
        local daBgOpacityW = GUI:CreateFormSlider(s8.frame, nil, 0, 100, 1, "bgOpacity", drawer, Refresh,
            { description = "Opacity of the drawer background (0 to 100 percent)." })
        s8.AddRow(row(s8.frame, "Background Color", daBgColorW), row(s8.frame, "Background Opacity", daBgOpacityW))

        local daBorderSizeW = GUI:CreateFormSlider(s8.frame, nil, 0, 8, 1, "borderSize", drawer, Refresh,
            { description = "Thickness of the drawer border. Set to 0 to hide the border." })
        s8.AddRow(row(s8.frame, "Border Size (0=hidden)", daBorderSizeW))

        local daBdSrcW, daBdColW = ns.QUI_BorderControl.Attach(GUI, s8.frame, drawer, "", Refresh,
            { label = "Border Color Source", colorLabel = "Border Color", noAlpha = true })
        s8.AddRow(row(s8.frame, "Border Color Source", daBdSrcW), row(s8.frame, "Border Color", daBdColW))
        L.closeSection(s8)

        -- HIDDEN BUTTONS IN DRAWER
        local buttonNames = _G.QUI_GetDrawerButtonNames and _G.QUI_GetDrawerButtonNames() or {}
        L.headerAt("Hidden Buttons in Drawer")
        if #buttonNames > 0 then
            local s9 = L.sectionAt()
            local pendingCell = nil
            for _, bName in ipairs(buttonNames) do
                local displayName = bName:gsub("^LibDBIcon10_", "")
                local hbW = GUI:CreateFormCheckbox(s9.frame, nil, bName, drawer.hiddenButtons, Refresh,
                    { description = "Hide this addon button from both the minimap and the drawer. Useful for buttons you never click." })
                local cell = row(s9.frame, displayName, hbW)
                if pendingCell then
                    s9.AddRow(pendingCell, cell)
                    pendingCell = nil
                else
                    pendingCell = cell
                end
            end
            if pendingCell then
                s9.AddRow(pendingCell)
            end
            L.closeSection(s9)
        else
            local empty = CreateFrame("Frame", nil, content)
            local lbl = empty:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            lbl:SetPoint("LEFT", empty, "LEFT", 6, 0)
            lbl:SetTextColor(0.6, 0.6, 0.6, 1)
            lbl:SetText("No buttons collected yet. Enable the drawer and reload.")
            L.placeCustom(empty, 24)
        end

        -- Layout-mode chrome (V3-styled collapsibles)
        U.BuildPositionCollapsible(content, "minimap", nil, L.sections, L.relayoutSections)
        U.BuildOpenFullSettingsLink(content, key, L.sections, L.relayoutSections)
        L.relayoutSections()
        return content:GetHeight()
    end })
end)
