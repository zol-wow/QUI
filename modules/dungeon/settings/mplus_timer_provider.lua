---------------------------------------------------------------------------
-- M+ TIMER SETTINGS PROVIDER (V3)
---------------------------------------------------------------------------
local _, ns = ...

do
    local function RegisterMPlusTimerProvider()
        local settingsPanel = ns.QUI_LayoutMode_Settings
        if not settingsPanel then return end

        local GUI = QUI and QUI.GUI
        if not GUI then return end

        local Helpers = ns.Helpers
        local LSM = ns.LSM
        local U = ns.QUI_LayoutMode_Utils
        local Opts = ns.QUI_Options
        local PAD = (Opts and Opts.PADDING) or 15
        local HEADER_GAP = 26
        local SECTION_GAP = 14

        local function GetMPlusDB()
            local core = Helpers.GetCore()
            local db = core and core.db and core.db.profile
            return db and db.mplusTimer
        end

        local function GetGeneralDB()
            local core = Helpers.GetCore()
            return core and core.db and core.db.profile and core.db.profile.general
        end

        local function RefreshLayout()
            local MPlusTimer = _G.QUI_MPlusTimer
            if MPlusTimer and MPlusTimer.UpdateLayout then MPlusTimer:UpdateLayout() end
        end
        local function RefreshSkin()
            if _G.QUI_ApplyMPlusTimerSkin then _G.QUI_ApplyMPlusTimerSkin() end
        end
        local function RefreshAll()
            RefreshLayout()
            RefreshSkin()
        end
        local function RefreshColors()
            if _G.QUI_RefreshMPlusTimerColors then _G.QUI_RefreshMPlusTimerColors() end
        end

        local function MakeLayout(content)
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

            return L
        end

        local function row(parent, label, widget, desc)
            return Opts.BuildSettingRow(parent, label, widget, desc)
        end

        local function BuildMPlusTimerSettings(content, key, _width)
            -- Headless cache-gen loads this file before ns.QUI_Options exists,
            -- so the upvalues captured at the top of RegisterMPlusTimerProvider
            -- can be nil. Refresh on each build invocation; live runtime is
            -- unaffected (RegisterAfterLoad guarantees QUI_Options is ready).
            Opts = Opts or ns.QUI_Options
            PAD = (Opts and Opts.PADDING) or PAD

            local mpDB = GetMPlusDB()
            if not mpDB then return 80 end

            local general = GetGeneralDB()

            Helpers.EnsureDefaults(mpDB, {
                layoutMode = "full",
                showTimer = true,
                showBorder = true,
                scale = 1.0,
                showDeaths = true,
                showAffixes = true,
                showObjectives = true,
                maxDungeonNameLength = 18,
            })

            local L = MakeLayout(content)

            -- General
            L.headerAt("General")
            local sGen = L.sectionAt()

            local layoutOptions = {
                { text = "Compact", value = "compact" },
                { text = "Full", value = "full" },
                { text = "Sleek", value = "sleek" },
            }
            local genLayoutW = GUI:CreateFormDropdown(sGen.frame, nil, layoutOptions, "layoutMode", mpDB, RefreshAll,
                { description = "Overall timer layout: Compact is a single row; Full shows all key details; Sleek trims non-essentials." })
            local genScaleW = GUI:CreateFormSlider(sGen.frame, nil, 0.5, 2.0, 0.05, "scale", mpDB, function()
                local MPlusTimer = _G.QUI_MPlusTimer
                if MPlusTimer and MPlusTimer.ApplyScale then MPlusTimer:ApplyScale() end
            end, { deferOnDrag = true, precision = 2, description = "Zoom factor applied to the whole M+ timer panel." })
            sGen.AddRow(
                row(sGen.frame, "Layout Mode", genLayoutW),
                row(sGen.frame, "Timer Scale", genScaleW)
            )

            local genMaxLenW = GUI:CreateFormSlider(sGen.frame, nil, 0, 40, 1, "maxDungeonNameLength", mpDB, function()
                local MPlusTimer = _G.QUI_MPlusTimer
                if MPlusTimer and MPlusTimer.RenderKeyDetails then MPlusTimer:RenderKeyDetails() end
            end, { description = "Truncate the dungeon name to this many characters. Set to 0 to show the full name." })
            local genShowTimerW = GUI:CreateFormCheckbox(sGen.frame, nil, "showTimer", mpDB, RefreshLayout,
                { description = "Show the numeric 'time remaining' text in Full layout mode. Compact/Sleek modes hide it regardless." })
            sGen.AddRow(
                row(sGen.frame, "Max Dungeon Name Length", genMaxLenW),
                row(sGen.frame, "Show Timer Text (Full mode)", genShowTimerW)
            )

            local genDeathsW = GUI:CreateFormCheckbox(sGen.frame, nil, "showDeaths", mpDB, RefreshLayout,
                { description = "Show the deaths counter and penalty time on the timer panel." })
            local genAffixesW = GUI:CreateFormCheckbox(sGen.frame, nil, "showAffixes", mpDB, RefreshLayout,
                { description = "Show the active weekly affix icons on the timer panel." })
            sGen.AddRow(
                row(sGen.frame, "Show Deaths", genDeathsW),
                row(sGen.frame, "Show Affixes", genAffixesW)
            )

            local genObjW = GUI:CreateFormCheckbox(sGen.frame, nil, "showObjectives", mpDB, RefreshLayout,
                { description = "Show the boss/objective rows under the timer." })
            local genBorderW = GUI:CreateFormCheckbox(sGen.frame, nil, "showBorder", mpDB, RefreshSkin,
                { description = "Draw a border around the whole M+ timer panel." })
            sGen.AddRow(
                row(sGen.frame, "Show Objectives", genObjW),
                row(sGen.frame, "Show Border", genBorderW)
            )
            L.closeSection(sGen)

            -- Border
            Helpers.EnsureDefaults(mpDB, {
                borderOverride = false,
                hideBorder = false,
                borderUseClassColor = false,
            })
            if mpDB.borderColor == nil then
                local fb = general and (general.skinBorderColor or general.addonAccentColor) or { 0.376, 0.647, 0.980, 1 }
                mpDB.borderColor = { fb[1], fb[2], fb[3], fb[4] or 1 }
            end

            L.headerAt("Border")
            local sBd = L.sectionAt()
            local bdColorPicker, bdHideCheck, bdClassCheck

            local function UpdateBorderState()
                local enabled = mpDB.borderOverride
                if bdHideCheck and bdHideCheck.SetEnabled then bdHideCheck:SetEnabled(enabled) end
                if bdClassCheck and bdClassCheck.SetEnabled then bdClassCheck:SetEnabled(enabled) end
                if bdColorPicker and bdColorPicker.SetEnabled then
                    bdColorPicker:SetEnabled(enabled and not mpDB.borderUseClassColor)
                end
            end

            local bdOverrideW = GUI:CreateFormCheckbox(sBd.frame, nil, "borderOverride", mpDB, function()
                UpdateBorderState()
                RefreshColors()
            end, { description = "Use M+ timer-specific border settings instead of the shared skinning border. Enables the controls below." })
            bdHideCheck = GUI:CreateFormCheckbox(sBd.frame, nil, "hideBorder", mpDB, RefreshColors,
                { description = "Hide the border around the M+ timer panel entirely." })
            sBd.AddRow(
                row(sBd.frame, "Override Global Border", bdOverrideW),
                row(sBd.frame, "Hide Border", bdHideCheck)
            )

            bdClassCheck = GUI:CreateFormCheckbox(sBd.frame, nil, "borderUseClassColor", mpDB, function()
                UpdateBorderState()
                RefreshColors()
            end, { description = "Tint the M+ timer border with your class color instead of the custom Border Color below." })
            bdColorPicker = GUI:CreateFormColorPicker(sBd.frame, nil, "borderColor", mpDB, RefreshColors, { noAlpha = true },
                { description = "Custom border color applied when Override Global Border is on and Use Class Color is off." })
            sBd.AddRow(
                row(sBd.frame, "Use Class Color", bdClassCheck),
                row(sBd.frame, "Border Color", bdColorPicker)
            )

            UpdateBorderState()
            L.closeSection(sBd)

            -- Background
            Helpers.EnsureDefaults(mpDB, {
                bgOverride = false,
                hideBackground = false,
                frameBackgroundOpacity = 1,
            })
            if mpDB.backgroundColor == nil then
                local fb = general and general.skinBgColor or { 0.05, 0.05, 0.05, 0.95 }
                mpDB.backgroundColor = { fb[1], fb[2], fb[3], fb[4] or 0.95 }
            end

            L.headerAt("Background")
            local sBg = L.sectionAt()
            local bgColorPicker, bgHideCheck

            local function UpdateBgState()
                local enabled = mpDB.bgOverride
                if bgHideCheck and bgHideCheck.SetEnabled then bgHideCheck:SetEnabled(enabled) end
                if bgColorPicker and bgColorPicker.SetEnabled then
                    bgColorPicker:SetEnabled(enabled and not mpDB.hideBackground)
                end
            end

            local bgOverrideW = GUI:CreateFormCheckbox(sBg.frame, nil, "bgOverride", mpDB, function()
                UpdateBgState()
                RefreshColors()
            end, { description = "Use M+ timer-specific background settings instead of the shared skinning background. Enables the controls below." })
            bgHideCheck = GUI:CreateFormCheckbox(sBg.frame, nil, "hideBackground", mpDB, function()
                UpdateBgState()
                RefreshColors()
            end, { description = "Hide the backdrop fill behind the M+ timer panel entirely." })
            sBg.AddRow(
                row(sBg.frame, "Override Global Background", bgOverrideW),
                row(sBg.frame, "Hide Background", bgHideCheck)
            )

            bgColorPicker = GUI:CreateFormColorPicker(sBg.frame, nil, "backgroundColor", mpDB, RefreshColors, nil,
                { description = "Custom background color applied when Override Global Background is on and Hide Background is off." })
            local bgOpacityW = GUI:CreateFormSlider(sBg.frame, nil, 0, 1, 0.05, "frameBackgroundOpacity", mpDB, RefreshSkin,
                { deferOnDrag = true, precision = 2, description = "Opacity of the M+ timer background fill. 0 is fully transparent, 1 is fully opaque." })
            sBg.AddRow(
                row(sBg.frame, "Background Color", bgColorPicker),
                row(sBg.frame, "Panel Opacity", bgOpacityW)
            )

            UpdateBgState()
            L.closeSection(sBg)

            -- Forces Bar
            Helpers.EnsureDefaults(mpDB, {
                forcesBarEnabled = true,
                forcesDisplayMode = "bar",
                forcesPosition = "after_timer",
                forcesTextFormat = "both",
                forcesFont = "Poppins",
                forcesFontSize = 11,
                barUseClassColor = false,
            })
            if mpDB.barColor == nil then
                local fb = general and (general.skinBorderColor or general.addonAccentColor) or { 0.376, 0.647, 0.980, 1 }
                mpDB.barColor = { fb[1], fb[2], fb[3], fb[4] or 1 }
            end

            L.headerAt("Forces Bar")
            local sFB = L.sectionAt()

            local fbEnableW = GUI:CreateFormCheckbox(sFB.frame, nil, "forcesBarEnabled", mpDB, RefreshLayout,
                { description = "Show the trash-count / forces progress element on the timer panel." })

            local displayModeOpts = {
                { text = "Progress Bar", value = "bar" },
                { text = "Text Only", value = "text" },
            }
            local fbDisplayW = GUI:CreateFormDropdown(sFB.frame, nil, displayModeOpts, "forcesDisplayMode", mpDB, RefreshLayout,
                { description = "Render forces progress as a filling bar or as text only." })
            sFB.AddRow(
                row(sFB.frame, "Show Forces Bar", fbEnableW),
                row(sFB.frame, "Display Mode", fbDisplayW)
            )

            local posOpts = {
                { text = "After Timer Bars", value = "after_timer" },
                { text = "Before Timer Bars", value = "before_timer" },
                { text = "Before Objectives", value = "before_objectives" },
                { text = "After Objectives", value = "after_objectives" },
            }
            local fbPosW = GUI:CreateFormDropdown(sFB.frame, nil, posOpts, "forcesPosition", mpDB, RefreshLayout,
                { description = "Where the forces bar / text is inserted relative to the timer bars and objective rows." })

            local formatOpts = {
                { text = "Count (123/273)", value = "count" },
                { text = "Percentage (45.32%)", value = "percentage" },
                { text = "Both", value = "both" },
            }
            local fbFmtW = GUI:CreateFormDropdown(sFB.frame, nil, formatOpts, "forcesTextFormat", mpDB, function()
                local MPlusTimer = _G.QUI_MPlusTimer
                if MPlusTimer and MPlusTimer.RenderForces then MPlusTimer:RenderForces() end
            end, { description = "How forces progress is formatted: running count, percent, or both." })
            sFB.AddRow(
                row(sFB.frame, "Position", fbPosW),
                row(sFB.frame, "Text Format", fbFmtW)
            )

            local fontList = {}
            if LSM then
                for name in pairs(LSM:HashTable("font")) do
                    fontList[#fontList + 1] = {value = name, text = name}
                end
                table.sort(fontList, function(a, b) return a.text < b.text end)
            end

            local fbSizeW = GUI:CreateFormSlider(sFB.frame, nil, 8, 18, 1, "forcesFontSize", mpDB, RefreshLayout,
                { description = "Font size for the forces-bar text." })
            if #fontList > 0 then
                local fbFontW = GUI:CreateFormDropdown(sFB.frame, nil, fontList, "forcesFont", mpDB, RefreshLayout,
                    { description = "Font used for the forces-bar text." })
                sFB.AddRow(
                    row(sFB.frame, "Font", fbFontW),
                    row(sFB.frame, "Font Size", fbSizeW)
                )
            else
                sFB.AddRow(row(sFB.frame, "Font Size", fbSizeW))
            end

            local fbTextColorW = GUI:CreateFormColorPicker(sFB.frame, nil, "forcesTextColor", mpDB, function()
                local MPlusTimer = _G.QUI_MPlusTimer
                if MPlusTimer and MPlusTimer.RenderForces then MPlusTimer:RenderForces() end
                RefreshSkin()
            end, nil, { description = "Color used for the forces-bar text." })

            local fbBarColorPicker
            local fbBarClassW = GUI:CreateFormCheckbox(sFB.frame, nil, "barUseClassColor", mpDB, function()
                if fbBarColorPicker and fbBarColorPicker.SetEnabled then
                    fbBarColorPicker:SetEnabled(not mpDB.barUseClassColor)
                end
                RefreshSkin()
            end, { description = "Tint the forces progress bar with your class color instead of the Bar Fill Color below." })
            sFB.AddRow(
                row(sFB.frame, "Text Color", fbTextColorW),
                row(sFB.frame, "Use Class Color for Bar", fbBarClassW)
            )

            fbBarColorPicker = GUI:CreateFormColorPicker(sFB.frame, nil, "barColor", mpDB, RefreshSkin, { noAlpha = true },
                { description = "Fallback fill color for the forces progress bar when Use Class Color for Bar is off." })
            if fbBarColorPicker.SetEnabled then fbBarColorPicker:SetEnabled(not mpDB.barUseClassColor) end
            sFB.AddRow(row(sFB.frame, "Bar Fill Color", fbBarColorPicker))
            L.closeSection(sFB)

            -- Layout-mode chrome (V3-styled collapsibles)
            U.BuildPositionCollapsible(content, "mplusTimer", nil, L.sections, L.relayoutSections)
            U.BuildOpenFullSettingsLink(content, key, L.sections, L.relayoutSections)
            L.relayoutSections()
            return content:GetHeight()
        end

        settingsPanel:RegisterSharedProvider("mplusTimer", {
            build = BuildMPlusTimerSettings,
        })
        local adapters = ns.Settings and ns.Settings.RenderAdapters
        if adapters and type(adapters.NotifyProviderChanged) == "function" then
            adapters.NotifyProviderChanged("mplusTimer", { structural = true })
        end
    end

    local ProviderPanels = ns.Settings and ns.Settings.ProviderPanels
    if ProviderPanels and type(ProviderPanels.RegisterAfterLoad) == "function" then
        ProviderPanels:RegisterAfterLoad(function()
            RegisterMPlusTimerProvider()
        end)
    else
        RegisterMPlusTimerProvider()
    end
end
