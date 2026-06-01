--[[
    QUI Minimap Shared Settings Providers
    Owns provider-backed settings content for Minimap and Datatext panel
    surfaces in the shared settings layer. Migrated to V3 body pattern
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
    local NotifyProviderFor = ctx.NotifyProviderFor
    local PAD = (ns.QUI_Options and ns.QUI_Options.PADDING) or 15
    local HEADER_GAP = 26
    local SECTION_GAP = 14

    local function RegisterSharedOnly(key, provider)
        ctx.RegisterShared(key, provider)
    end

    local function MakeLayout(content)
        if U._layoutModePositionOnly then
            return U.MakeSuppressedProviderLayout(content)
        end
        local Opts = ns.QUI_Options
        local y = -10
        local L = {}
        local sections = {}

        function L.headerAt(text)
            local h = Opts.CreateAccentDotLabel(content, text, y)
            h:ClearAllPoints()
            h:SetPoint("TOPLEFT", content, "TOPLEFT", PAD, y)
            h:SetPoint("TOPRIGHT", content, "TOPRIGHT", -PAD, y)
            y = y - HEADER_GAP
        end
        function L.sectionAt()
            local c = Opts.CreateSettingsCardGroup(content, y)
            c.frame:ClearAllPoints()
            c.frame:SetPoint("TOPLEFT", content, "TOPLEFT", PAD, y)
            c.frame:SetPoint("TOPRIGHT", content, "TOPRIGHT", -PAD, y)
            return c
        end
        function L.closeSection(c)
            c.Finalize()
            y = y - c.frame:GetHeight() - SECTION_GAP
        end
        function L.placeCustom(frame, height)
            frame:ClearAllPoints()
            frame:SetPoint("TOPLEFT", content, "TOPLEFT", PAD, y)
            frame:SetPoint("RIGHT", content, "RIGHT", -PAD, 0)
            frame:SetHeight(height)
            y = y - height - SECTION_GAP
        end

        -- Tail relayout for legacy V2 collapsibles (Position, OpenFullSettings)
        -- that still use sections + StandardRelayout. They get laid out
        -- starting from the bottom of the V3 cards above.
        local function relayoutSections()
            local cy = y
            for _, s in ipairs(sections) do
                s:ClearAllPoints()
                s:SetPoint("TOPLEFT", content, "TOPLEFT", PAD, cy)
                s:SetPoint("RIGHT", content, "RIGHT", -PAD, 0)
                cy = cy - s:GetHeight() - 4
            end
            content:SetHeight(math.abs(cy) + 16)
        end
        L.sections = sections
        L.relayoutSections = relayoutSections

        function L.finish()
            content:SetHeight(math.abs(y) + 10)
            return content:GetHeight()
        end

        return L
    end

    local function row(parent, label, widget, desc)
        return ns.QUI_Options.BuildSettingRow(parent, label, widget, desc)
    end

    ---------------------------------------------------------------------------
    -- MINIMAP PROVIDER
    ---------------------------------------------------------------------------
    RegisterSharedOnly("minimap", { build = function(content, key, _width)
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

        local bdSpaceW = GUI:CreateFormCheckbox(s7.frame, nil, "buttonSpacing", drawer, Refresh,
            { description = "Add a small pixel gap between buttons inside the drawer." })
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

    ---------------------------------------------------------------------------
    -- DATATEXT PANEL HELPERS
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
        if panelDB.borderColorSource == nil then panelDB.borderColorSource = "inherit" end
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
        if not label or label == "" then return "TXT" end

        local initials = {}
        for token in string.gmatch(label, "[%a%d]+") do
            initials[#initials + 1] = string.upper(string.sub(token, 1, 1))
            if #initials >= 4 then break end
        end

        if #initials >= 2 then
            return table.concat(initials)
        end

        local compact = string.gsub(label, "[^%a%d]", "")
        compact = string.upper(compact)
        if compact == "" then return "TXT" end

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
        if not datatextID or datatextID == "" then return nil end

        local settings = slotSettings or {}
        local vr, vg, vb = GetDatatextPreviewValueColor(dtSettings)
        local valueText = string.format("|cff%02x%02x%02x123|r",
            ToPreviewHexComponent(vr),
            ToPreviewHexComponent(vg),
            ToPreviewHexComponent(vb)
        )

        if settings.noLabel then return valueText end

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

    ---------------------------------------------------------------------------
    -- DATATEXT PANEL PROVIDER
    ---------------------------------------------------------------------------
    RegisterSharedOnly("datatextPanel", { build = function(content, key, _width)
        local profile = U.GetProfileDB()
        if not profile or not ns.QUI_Options then return 80 end

        local QUICore = ns.Addon
        local dtGlobal = EnsureMinimapDatatextConfig(profile)
        local selected = GetSelectedDatatextContext(profile)
        local dtOptions = GetDatatextOptions(QUICore)
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
            if not preview or not preview.Render then return end

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

        local L = MakeLayout(content)

        -- PANEL SELECTOR + PREVIEW (custom layout, outside cards)
        L.headerAt("Panel Selector")
        local selectorRow = CreateFrame("Frame", nil, content)
        L.placeCustom(selectorRow, 30)
        local selectorState = { activePanel = selected.key }

        local selector = GUI:CreateFormDropdown(
            selectorRow, nil, GetDatapanelSelectorOptions(profile),
            "activePanel", selectorState, function(val)
                if not val or val == selected.key or val == DatatextPanelState.activePanel then
                    return
                end
                DatatextPanelState.activePanel = val
                NotifyStructuralRefresh()
            end,
            { description = "Pick which datatext panel you want to configure. The minimap panel and every custom datapanel are edited from this same tab.",
              searchable = true, collapsible = false }
        )
        selector:SetPoint("TOPLEFT", selectorRow, "TOPLEFT", 0, 0)
        selector:SetPoint("RIGHT", selectorRow, "RIGHT", -196, 0)
        if selector.SetValue then selector:SetValue(selected.key, true) end

        local newBtn = GUI:CreateButton(selectorRow, "+ New", 90, 24, function()
            local newPanel = CreateCustomDatapanel(profile)
            RegisterCustomDatapanelRuntime(newPanel, QUICore, profile)
            DatatextPanelState.activePanel = newPanel.id
            RefreshAllDatatextSurfaces()
            NotifyStructuralRefresh()
        end, "primary")
        newBtn:SetPoint("TOPRIGHT", selectorRow, "TOPRIGHT", -100, -2)

        local deleteBtn = GUI:CreateButton(selectorRow, "Delete", 90, 24, function()
            if selected.isMinimap then return end

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
        deleteBtn:SetPoint("TOPRIGHT", selectorRow, "TOPRIGHT", 0, -2)
        deleteBtn:SetShown(not selected.isMinimap)

        preview = CreateDatatextPreview(content, 104)
        L.placeCustom(preview, 104)
        RenderDatatextPreview()

        local hintRow = CreateFrame("Frame", nil, content)
        local hint = hintRow:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        hint:SetPoint("LEFT", hintRow, "LEFT", 0, 0)
        hint:SetPoint("RIGHT", hintRow, "RIGHT", 0, 0)
        hint:SetTextColor(0.6, 0.6, 0.6, 0.85)
        hint:SetText(selected.isMinimap
            and "Preview shows the minimap datatext panel only. Width follows your minimap size."
            or "Sample text preview only. Empty slots collapse just like they do in-game.")
        hint:SetJustifyH("LEFT")
        L.placeCustom(hintRow, 22)

        -- PANEL SETTINGS + SLOT CONFIGURATION
        if selected.isMinimap then
            L.headerAt("Panel Settings")
            local ps = L.sectionAt()
            local enW = GUI:CreateFormCheckbox(ps.frame, nil, "enabled", dtGlobal, RefreshAllDatatextSurfaces,
                { description = "Show the datatext panel anchored below the minimap." })
            local singleW = GUI:CreateFormCheckbox(ps.frame, nil, "forceSingleLine", dtGlobal, RefreshAllDatatextSurfaces,
                { description = "Keep all minimap datatext slots on one row instead of allowing wrap." })
            ps.AddRow(row(ps.frame, "Enable Minimap Datatext", enW), row(ps.frame, "Force Single Line", singleW))

            local hW = GUI:CreateFormSlider(ps.frame, nil, 18, 50, 1, "height", dtGlobal, RefreshAllDatatextSurfaces,
                { description = "Pixel height reserved per row of minimap datatext." })
            local bgW = GUI:CreateFormSlider(ps.frame, nil, 0, 100, 5, "bgOpacity", dtGlobal, RefreshAllDatatextSurfaces,
                { description = "Opacity of the minimap datatext background (0 invisible, 100 fully opaque)." })
            ps.AddRow(row(ps.frame, "Panel Height (Per Row)", hW), row(ps.frame, "Background Transparency", bgW))

            local borSizeW = GUI:CreateFormSlider(ps.frame, nil, 0, 8, 1, "borderSize", dtGlobal, RefreshAllDatatextSurfaces,
                { description = "Thickness of the minimap datatext border. Set to 0 to hide it." })
            local borSrcW, borColorW = ns.QUI_BorderControl.Attach(GUI, ps.frame, dtGlobal, "", RefreshAllDatatextSurfaces,
                { label = "Border Color Source", colorLabel = "Border Color",
                  colorDescription = "Color of the minimap datatext border." })
            ps.AddRow(row(ps.frame, "Border Size (0=hidden)", borSizeW), row(ps.frame, "Border Color Source", borSrcW))
            ps.AddRow(row(ps.frame, "Border Color", borColorW))

            local offYW = GUI:CreateFormSlider(ps.frame, nil, -40, 40, 1, "offsetY", dtGlobal, RefreshAllDatatextSurfaces,
                { description = "Vertical offset from the minimap. Positive moves up, negative moves down." })
            local fSizeW = GUI:CreateFormSlider(ps.frame, nil, 9, 18, 1, "fontSize", dtGlobal, RefreshAllDatatextSurfaces,
                { description = "Font size of the minimap datatext labels and values." })
            ps.AddRow(row(ps.frame, "Vertical Offset", offYW), row(ps.frame, "Text Size", fSizeW))
            L.closeSection(ps)

            for slotIdx = 1, 3 do
                local slotKey = "slot" .. slotIdx
                local slotData = dtGlobal[slotKey]
                local slotLabel = "Slot " .. slotIdx .. " ("
                    .. (slotIdx == 1 and "Left" or slotIdx == 2 and "Center" or "Right") .. ")"

                L.headerAt(slotLabel)
                local sc = L.sectionAt()

                local slotDD = GUI:CreateFormDropdown(sc.frame, nil, dtOptions, nil, nil, function(val)
                    dtGlobal.slots[slotIdx] = val
                    RefreshAllDatatextSurfaces()
                    NotifyStructuralRefresh()
                end, { description = "Datatext shown in this slot." })
                if slotDD.SetValue then slotDD:SetValue(dtGlobal.slots[slotIdx] or "", true) end
                sc.AddRow(row(sc.frame, "Datatext", slotDD))

                local shortW = GUI:CreateFormCheckbox(sc.frame, nil, "shortLabel", slotData, RefreshAllDatatextSurfaces,
                    { description = "Use the compact label variant for this slot." })
                local noLabelW = GUI:CreateFormCheckbox(sc.frame, nil, "noLabel", slotData, RefreshAllDatatextSurfaces,
                    { description = "Hide the label and show only the value." })
                sc.AddRow(row(sc.frame, "Short Label", shortW), row(sc.frame, "No Label", noLabelW))

                local sxW = GUI:CreateFormSlider(sc.frame, nil, -50, 50, 1, "xOffset", slotData, RefreshAllDatatextSurfaces,
                    { description = "Horizontal pixel offset for this slot." })
                local syW = GUI:CreateFormSlider(sc.frame, nil, -20, 20, 1, "yOffset", slotData, RefreshAllDatatextSurfaces,
                    { description = "Vertical pixel offset for this slot." })
                sc.AddRow(row(sc.frame, "X Offset", sxW), row(sc.frame, "Y Offset", syW))
                L.closeSection(sc)
            end
        else
            RegisterCustomDatapanelRuntime(selected.panelDB, QUICore, profile)

            L.headerAt("Panel Settings")
            local ps = L.sectionAt()

            local nameField = GUI:CreateFormEditBox(ps.frame, nil, "name", selected.panelDB, function()
                UpdateCustomDatapanelRuntimeLabel(selected.panelDB)
                RefreshAllDatatextSurfaces()
                NotifyStructuralRefresh()
            end, { maxLetters = 48 }, { description = "Name used in the selector and in Layout Mode for this custom datapanel." })
            local enW = GUI:CreateFormCheckbox(ps.frame, nil, "enabled", selected.panelDB, RefreshAllDatatextSurfaces,
                { description = "Enable or disable this custom datapanel." })
            ps.AddRow(row(ps.frame, "Panel Name", nameField), row(ps.frame, "Enabled", enW))

            local lockW = GUI:CreateFormCheckbox(ps.frame, nil, "locked", selected.panelDB, RefreshAllDatatextSurfaces,
                { description = "Prevent this panel from being dragged in-game until unlocked." })
            local widthW = GUI:CreateFormSlider(ps.frame, nil, 100, 800, 1, "width", selected.panelDB, RefreshAllDatatextSurfaces,
                { description = "Width of this custom datapanel in pixels." })
            ps.AddRow(row(ps.frame, "Lock Position", lockW), row(ps.frame, "Width", widthW))

            local heightW = GUI:CreateFormSlider(ps.frame, nil, 16, 60, 1, "height", selected.panelDB, RefreshAllDatatextSurfaces,
                { description = "Height of this custom datapanel in pixels." })
            local numSlotsW = GUI:CreateFormSlider(ps.frame, nil, 1, 8, 1, "numSlots", selected.panelDB, function()
                EnsureCustomDatapanelDefaults(selected.panelDB)
                RefreshAllDatatextSurfaces()
                NotifyStructuralRefresh()
            end, { description = "How many datatext slots this panel shows. Empty slots stay hidden." })
            ps.AddRow(row(ps.frame, "Height", heightW), row(ps.frame, "Number of Slots", numSlotsW))

            local bgW = GUI:CreateFormSlider(ps.frame, nil, 0, 100, 5, "bgOpacity", selected.panelDB, RefreshAllDatatextSurfaces,
                { description = "Opacity of the panel background fill (0 transparent, 100 fully opaque)." })
            local borSizeW = GUI:CreateFormSlider(ps.frame, nil, 0, 8, 1, "borderSize", selected.panelDB, RefreshAllDatatextSurfaces,
                { description = "Border thickness in pixels. Set to 0 to hide the border entirely." })
            ps.AddRow(row(ps.frame, "Background Opacity", bgW), row(ps.frame, "Border Size (0=hidden)", borSizeW))

            local borSrcW, borColorW = ns.QUI_BorderControl.Attach(GUI, ps.frame, selected.panelDB, "", RefreshAllDatatextSurfaces,
                { label = "Border Color Source", colorLabel = "Border Color",
                  colorDescription = "Color used for the panel border." })
            local fontSizeW = GUI:CreateFormSlider(ps.frame, nil, 8, 18, 1, "fontSize", selected.panelDB, RefreshAllDatatextSurfaces,
                { description = "Font size for every datatext slot on this panel." })
            ps.AddRow(row(ps.frame, "Border Color Source", borSrcW), row(ps.frame, "Font Size", fontSizeW))
            ps.AddRow(row(ps.frame, "Border Color", borColorW))
            L.closeSection(ps)

            for s = 1, selected.numSlots do
                local slotSettings = selected.panelDB.slotSettings[s]
                L.headerAt("Slot " .. s)
                local sc = L.sectionAt()

                local slotDD = GUI:CreateFormDropdown(sc.frame, nil, dtOptions, nil, nil, function(val)
                    selected.panelDB.slots[s] = val
                    RefreshAllDatatextSurfaces()
                    NotifyStructuralRefresh()
                end, { description = "Pick which datatext this slot displays. Empty slots stay hidden and the remaining slots share the width." })
                if slotDD.SetValue then slotDD:SetValue(selected.panelDB.slots[s] or "", true) end
                sc.AddRow(row(sc.frame, "Datatext", slotDD))

                local shortW = GUI:CreateFormCheckbox(sc.frame, nil, "shortLabel", slotSettings, RefreshAllDatatextSurfaces,
                    { description = "Use the compact label variant for this slot." })
                local noLabelW = GUI:CreateFormCheckbox(sc.frame, nil, "noLabel", slotSettings, RefreshAllDatatextSurfaces,
                    { description = "Hide the label and show only the value for this slot." })
                sc.AddRow(row(sc.frame, "Short Label", shortW), row(sc.frame, "No Label", noLabelW))
                L.closeSection(sc)
            end
        end

        -- TEXT STYLING
        L.headerAt("Text Styling")
        local ts = L.sectionAt()
        local useClassW = GUI:CreateFormCheckbox(ts.frame, nil, "useClassColor", dtGlobal, RefreshAllDatatextSurfaces,
            { description = "Color datatext values by your class instead of the custom swatch below." })
        local valColorW = GUI:CreateFormColorPicker(ts.frame, nil, "valueColor", dtGlobal, RefreshAllDatatextSurfaces, nil,
            { description = "Color used for datatext values when Use Class Color is off." })
        ts.AddRow(row(ts.frame, "Use Class Color", useClassW), row(ts.frame, "Custom Text Color", valColorW))
        L.closeSection(ts)

        local noteRow = CreateFrame("Frame", nil, content)
        local note = noteRow:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        note:SetPoint("LEFT", noteRow, "LEFT", 0, 0)
        note:SetTextColor(0.6, 0.6, 0.6, 0.8)
        note:SetText("Text Styling applies to every datatext panel.")
        L.placeCustom(noteRow, 18)

        -- SPEC DISPLAY (conditional)
        if CountSlotsWithValue(selected.slots, selected.numSlots, "playerspec") then
            L.headerAt("Spec Display")
            local sp = L.sectionAt()
            local specOpts = {
                { value = "icon", text = "Icon Only" },
                { value = "loadout", text = "Icon + Loadout" },
                { value = "full", text = "Full (Spec / Loadout)" },
            }
            local specW = GUI:CreateFormDropdown(sp.frame, nil, specOpts, "specDisplayMode", dtGlobal, RefreshAllDatatextSurfaces,
                { description = "How the Spec datatext renders: just the icon, icon plus loadout, or the full spec and loadout label." })
            sp.AddRow(row(sp.frame, "Spec Display Mode", specW))
            L.closeSection(sp)
        end

        -- TIME OPTIONS (conditional)
        if CountSlotsWithValue(selected.slots, selected.numSlots, "time") then
            L.headerAt("Time Options")
            local tm = L.sectionAt()
            local fmtW = GUI:CreateFormDropdown(tm.frame, nil, {
                { value = "local", text = "Local Time" },
                { value = "server", text = "Server Time" },
            }, "timeFormat", dtGlobal, RefreshAllDatatextSurfaces,
                { description = "Whether the Time datatext shows your local system time or realm server time." })
            local clkW = GUI:CreateFormDropdown(tm.frame, nil, {
                { value = true, text = "24-Hour Clock" },
                { value = false, text = "AM/PM" },
            }, "use24Hour", dtGlobal, RefreshAllDatatextSurfaces,
                { description = "Display time as 24-hour or 12-hour AM/PM." })
            tm.AddRow(row(tm.frame, "Time Format", fmtW), row(tm.frame, "Clock Format", clkW))

            local lkW = GUI:CreateFormSlider(tm.frame, nil, 1, 30, 1, "lockoutCacheMinutes", dtGlobal, nil,
                { description = "How often raid lockout info is refreshed when shown in the Time tooltip." })
            tm.AddRow(row(tm.frame, "Lockout Refresh (minutes)", lkW))
            L.closeSection(tm)
        end

        -- CURRENCIES (conditional, custom layout with reorder controls)
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

            L.headerAt("Currencies")
            local currencyFrame = CreateFrame("Frame", nil, content)
            local rowFrames = {}

            local hintFs = currencyFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            hintFs:SetPoint("TOPLEFT", currencyFrame, "TOPLEFT", 4, -4)
            hintFs:SetPoint("RIGHT", currencyFrame, "RIGHT", -4, 0)
            hintFs:SetTextColor(0.6, 0.6, 0.6, 0.8)
            hintFs:SetText("First 6 enabled are displayed. Use arrows to reorder.")

            local CURRENCY_ROW_HEIGHT = 28
            local function RebuildCurrencyRows()
                for _, rf in ipairs(rowFrames) do rf:Hide() end

                local ry = -24
                for idx, cid in ipairs(dtGlobal.currencyOrder) do
                    local cInfo = trackedById[cid]
                    local displayName = cInfo and cInfo.text or cid

                    local r = rowFrames[idx]
                    if not r then
                        r = CreateFrame("Frame", nil, currencyFrame)
                        r:SetHeight(CURRENCY_ROW_HEIGHT - 4)
                        rowFrames[idx] = r
                    end
                    r:ClearAllPoints()
                    r:SetPoint("TOPLEFT", currencyFrame, "TOPLEFT", 0, ry)
                    r:SetPoint("RIGHT", currencyFrame, "RIGHT", 0, 0)
                    r:Show()

                    if not r._built then
                        r._cb = GUI:CreateFormCheckbox(r, "", nil, nil, nil,
                            { description = "Toggle this currency in the Currencies datatext. Use the arrows to reorder." })
                        r._cb:SetPoint("LEFT", 4, 0)
                        r._cb:SetHeight(CURRENCY_ROW_HEIGHT - 4)

                        r._upBtn = CreateFrame("Button", nil, r)
                        r._upBtn:SetSize(16, 16)
                        r._upBtn:SetPoint("RIGHT", r, "RIGHT", -24, 0)
                        r._upBtn:SetNormalFontObject("GameFontNormalSmall")
                        r._upBtn:SetText("^")
                        r._upBtn:GetFontString():SetTextColor(0.376, 0.647, 0.980, 1)

                        r._downBtn = CreateFrame("Button", nil, r)
                        r._downBtn:SetSize(16, 16)
                        r._downBtn:SetPoint("RIGHT", r, "RIGHT", -4, 0)
                        r._downBtn:SetNormalFontObject("GameFontNormalSmall")
                        r._downBtn:SetText("v")
                        r._downBtn:GetFontString():SetTextColor(0.376, 0.647, 0.980, 1)

                        r._built = true
                    end

                    r._cb.label:SetText(displayName)
                    r._cb:SetChecked(dtGlobal.currencyEnabled[cid] ~= false)
                    r._cb:SetScript("OnClick", function(self)
                        dtGlobal.currencyEnabled[cid] = self:GetChecked()
                        RefreshAllDatatextSurfaces()
                        NotifyProviderFor(r._cb, { structural = true })
                    end)

                    local capturedIdx = idx
                    r._upBtn:SetScript("OnClick", function()
                        if capturedIdx > 1 then
                            local order = dtGlobal.currencyOrder
                            order[capturedIdx], order[capturedIdx - 1] = order[capturedIdx - 1], order[capturedIdx]
                            RebuildCurrencyRows()
                            RefreshAllDatatextSurfaces()
                            NotifyProviderFor(r._upBtn, { structural = true })
                        end
                    end)
                    r._upBtn:SetAlpha(idx > 1 and 1 or 0.3)

                    r._downBtn:SetScript("OnClick", function()
                        if capturedIdx < #dtGlobal.currencyOrder then
                            local order = dtGlobal.currencyOrder
                            order[capturedIdx], order[capturedIdx + 1] = order[capturedIdx + 1], order[capturedIdx]
                            RebuildCurrencyRows()
                            RefreshAllDatatextSurfaces()
                            NotifyProviderFor(r._downBtn, { structural = true })
                        end
                    end)
                    r._downBtn:SetAlpha(idx < #dtGlobal.currencyOrder and 1 or 0.3)

                    ry = ry - CURRENCY_ROW_HEIGHT
                end
            end

            local rowCount = math.max(#ordered, 1)
            local currencyHeight = 24 + rowCount * CURRENCY_ROW_HEIGHT + 8
            L.placeCustom(currencyFrame, currencyHeight)
            RebuildCurrencyRows()

            if #ordered == 0 then
                local empty = currencyFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                empty:SetPoint("TOPLEFT", currencyFrame, "TOPLEFT", 4, -24)
                empty:SetTextColor(0.6, 0.6, 0.6, 1)
                empty:SetText("No tracked currencies. Track currencies via the backpack.")
            end

            local cNoteRow = CreateFrame("Frame", nil, content)
            local cNote = cNoteRow:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            cNote:SetPoint("LEFT", cNoteRow, "LEFT", 0, 0)
            cNote:SetTextColor(0.6, 0.6, 0.6, 0.8)
            cNote:SetText("Currencies applies to all panels with the Currencies datatext.")
            L.placeCustom(cNoteRow, 18)
        end

        -- Layout-mode chrome
        if selected.isMinimap then
            U.BuildPositionCollapsible(content, "datatextPanel", nil, L.sections, L.relayoutSections)
        else
            U.BuildPositionCollapsible(content, selected.positionKey, { autoWidth = true }, L.sections, L.relayoutSections)
        end
        U.BuildOpenFullSettingsLink(content, key, L.sections, L.relayoutSections)
        L.relayoutSections()
        return content:GetHeight()
    end })
end)
