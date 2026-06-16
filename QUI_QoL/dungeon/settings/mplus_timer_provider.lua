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

        -- Shared provider-panel layout scaffold (core/settings_layout_shared.lua).
        local function MakeLayout(content)
            if U._layoutModePositionOnly then
                return U.MakeSuppressedProviderLayout(content)
            end
            return ns.QUI_SettingsLayoutShared.MakeLayout(content, U)
        end

        local function row(parent, label, widget, desc)
            return Opts.BuildSettingRow(parent, label, widget, desc)
        end

        local function BuildMPlusTimerSettings(content, key, _width)
            -- core/gui_shell.lua installs a minimal ns.QUI_Options stub, then
            -- the on-demand QUI_Options addon (shared.lua) REPLACES the table
            -- with the real one carrying the V3 body helpers. The Opts upvalue
            -- captured at registration can thus be nil (headless) or the stale
            -- stub (which lacks CreateAccentDotLabel). Re-resolve live-first each
            -- build: a truthy stale stub must not win over the replacement.
            Opts = ns.QUI_Options or Opts
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
                objectiveTextAlign = "LEFT",
                maxDungeonNameLength = 18,
            })

            local L = MakeLayout(content)

            -- General
            L.headerAt(ns.L["General"])
            local sGen = L.sectionAt()

            local layoutOptions = {
                { text = ns.L["Compact"], value = "compact" },
                { text = ns.L["Full"], value = "full" },
                { text = ns.L["Sleek"], value = "sleek" },
            }
            local genLayoutW = GUI:CreateFormDropdown(sGen.frame, nil, layoutOptions, "layoutMode", mpDB, RefreshAll,
                { description = ns.L["Overall timer layout: Compact is a single row; Full shows all key details; Sleek trims non-essentials."] })
            local genScaleW = GUI:CreateFormSlider(sGen.frame, nil, 0.5, 2.0, 0.05, "scale", mpDB, function()
                local MPlusTimer = _G.QUI_MPlusTimer
                if MPlusTimer and MPlusTimer.ApplyScale then MPlusTimer:ApplyScale() end
            end, { deferOnDrag = true, precision = 2, description = ns.L["Zoom factor applied to the whole M+ timer panel."] })
            sGen.AddRow(
                row(sGen.frame, ns.L["Layout Mode"], genLayoutW),
                row(sGen.frame, ns.L["Timer Scale"], genScaleW)
            )

            local genMaxLenW = GUI:CreateFormSlider(sGen.frame, nil, 0, 40, 1, "maxDungeonNameLength", mpDB, function()
                local MPlusTimer = _G.QUI_MPlusTimer
                if MPlusTimer and MPlusTimer.RenderKeyDetails then MPlusTimer:RenderKeyDetails() end
            end, { description = ns.L["Truncate the dungeon name to this many characters. Set to 0 to show the full name."] })
            local genShowTimerW = GUI:CreateFormCheckbox(sGen.frame, nil, "showTimer", mpDB, RefreshLayout,
                { description = ns.L["Show the numeric 'time remaining' text in Full layout mode. Compact/Sleek modes hide it regardless."] })
            sGen.AddRow(
                row(sGen.frame, ns.L["Max Dungeon Name Length"], genMaxLenW),
                row(sGen.frame, ns.L["Show Timer Text (Full mode)"], genShowTimerW)
            )

            local genDeathsW = GUI:CreateFormCheckbox(sGen.frame, nil, "showDeaths", mpDB, RefreshLayout,
                { description = ns.L["Show the deaths counter and penalty time on the timer panel."] })
            local genAffixesW = GUI:CreateFormCheckbox(sGen.frame, nil, "showAffixes", mpDB, RefreshLayout,
                { description = ns.L["Show the active weekly affix icons on the timer panel."] })
            sGen.AddRow(
                row(sGen.frame, ns.L["Show Deaths"], genDeathsW),
                row(sGen.frame, ns.L["Show Affixes"], genAffixesW)
            )

            local genObjW = GUI:CreateFormCheckbox(sGen.frame, nil, "showObjectives", mpDB, RefreshLayout,
                { description = ns.L["Show the boss/objective rows under the timer."] })
            local genBorderW = GUI:CreateFormCheckbox(sGen.frame, nil, "showBorder", mpDB, RefreshSkin,
                { description = ns.L["Draw a border around the whole M+ timer panel."] })
            sGen.AddRow(
                row(sGen.frame, ns.L["Show Objectives"], genObjW),
                row(sGen.frame, ns.L["Show Border"], genBorderW)
            )

            local objAlignOpts = {
                { text = ns.L["Left"], value = "LEFT" },
                { text = ns.L["Center"], value = "CENTER" },
                { text = ns.L["Right"], value = "RIGHT" },
            }
            local genObjAlignW = GUI:CreateFormDropdown(sGen.frame, nil, objAlignOpts, "objectiveTextAlign", mpDB, RefreshLayout,
                { description = ns.L["Horizontal alignment of the boss/objective text rows on the timer panel."] })
            sGen.AddRow(row(sGen.frame, ns.L["Objective Text Alignment"], genObjAlignW))
            L.closeSection(sGen)

            -- Border
            L.headerAt(ns.L["Border"])
            local sBd = L.sectionAt()
            local bdSrcW, bdColW = ns.QUI_BorderControl.Attach(GUI, sBd.frame, mpDB, "", RefreshColors,
                { label = ns.L["Border Color Source"], colorLabel = ns.L["Border Color"], noAlpha = true })
            sBd.AddRow(row(sBd.frame, ns.L["Border Color Source"], bdSrcW), row(sBd.frame, ns.L["Border Color"], bdColW))
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

            L.headerAt(ns.L["Background"])
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
            end, { description = ns.L["Use M+ timer-specific background settings instead of the shared skinning background. Enables the controls below."] })
            bgHideCheck = GUI:CreateFormCheckbox(sBg.frame, nil, "hideBackground", mpDB, function()
                UpdateBgState()
                RefreshColors()
            end, { description = ns.L["Hide the backdrop fill behind the M+ timer panel entirely."] })
            sBg.AddRow(
                row(sBg.frame, ns.L["Override Global Background"], bgOverrideW),
                row(sBg.frame, ns.L["Hide Background"], bgHideCheck)
            )

            bgColorPicker = GUI:CreateFormColorPicker(sBg.frame, nil, "backgroundColor", mpDB, RefreshColors, nil,
                { description = ns.L["Custom background color applied when Override Global Background is on and Hide Background is off."] })
            local bgOpacityW = GUI:CreateFormSlider(sBg.frame, nil, 0, 1, 0.05, "frameBackgroundOpacity", mpDB, RefreshSkin,
                { deferOnDrag = true, precision = 2, description = ns.L["Opacity of the M+ timer background fill. 0 is fully transparent, 1 is fully opaque."] })
            sBg.AddRow(
                row(sBg.frame, ns.L["Background Color"], bgColorPicker),
                row(sBg.frame, ns.L["Panel Opacity"], bgOpacityW)
            )

            UpdateBgState()
            L.closeSection(sBg)

            -- Forces Bar
            Helpers.EnsureDefaults(mpDB, {
                forcesBarEnabled = true,
                forcesDisplayMode = "bar",
                forcesPosition = "after_timer",
                forcesTextFormat = "both",
                forcesTextAlign = "LEFT",
                forcesFont = "Poppins",
                forcesFontSize = 11,
                forcesBarHeight = 0,
                barUseClassColor = false,
            })
            if mpDB.barColor == nil then
                local fb = general and (general.skinBorderColor or general.addonAccentColor) or { 0.376, 0.647, 0.980, 1 }
                mpDB.barColor = { fb[1], fb[2], fb[3], fb[4] or 1 }
            end

            L.headerAt(ns.L["Forces Bar"])
            local sFB = L.sectionAt()

            local fbEnableW = GUI:CreateFormCheckbox(sFB.frame, nil, "forcesBarEnabled", mpDB, RefreshLayout,
                { description = ns.L["Show the trash-count / forces progress element on the timer panel."] })

            local displayModeOpts = {
                { text = ns.L["Progress Bar"], value = "bar" },
                { text = ns.L["Text Only"], value = "text" },
            }
            local fbDisplayW = GUI:CreateFormDropdown(sFB.frame, nil, displayModeOpts, "forcesDisplayMode", mpDB, RefreshLayout,
                { description = ns.L["Render forces progress as a filling bar or as text only."] })
            sFB.AddRow(
                row(sFB.frame, ns.L["Show Forces Bar"], fbEnableW),
                row(sFB.frame, ns.L["Display Mode"], fbDisplayW)
            )

            local posOpts = {
                { text = ns.L["After Timer Bars"], value = "after_timer" },
                { text = ns.L["Before Timer Bars"], value = "before_timer" },
                { text = ns.L["Before Objectives"], value = "before_objectives" },
                { text = ns.L["After Objectives"], value = "after_objectives" },
            }
            local fbPosW = GUI:CreateFormDropdown(sFB.frame, nil, posOpts, "forcesPosition", mpDB, RefreshLayout,
                { description = ns.L["Where the forces bar / text is inserted relative to the timer bars and objective rows."] })

            local formatOpts = {
                { text = ns.L["Count (123/273)"], value = "count" },
                { text = ns.L["Percentage (45.32%)"], value = "percentage" },
                { text = ns.L["Both"], value = "both" },
            }
            local fbFmtW = GUI:CreateFormDropdown(sFB.frame, nil, formatOpts, "forcesTextFormat", mpDB, function()
                local MPlusTimer = _G.QUI_MPlusTimer
                if MPlusTimer and MPlusTimer.RenderForces then MPlusTimer:RenderForces() end
            end, { description = ns.L["How forces progress is formatted: running count, percent, or both."] })
            sFB.AddRow(
                row(sFB.frame, ns.L["Position"], fbPosW),
                row(sFB.frame, ns.L["Text Format"], fbFmtW)
            )

            local fbAlignW = GUI:CreateFormDropdown(sFB.frame, nil, objAlignOpts, "forcesTextAlign", mpDB, RefreshLayout,
                { description = ns.L["Horizontal alignment of the forces text when Display Mode is Text Only."] })
            local fbBarHeightW = GUI:CreateFormSlider(sFB.frame, nil, 0, 30, 1, "forcesBarHeight", mpDB, RefreshLayout,
                { deferOnDrag = true, description = ns.L["Height of the forces progress bar. 0 uses the layout's default height (14 Full / 12 Compact / 8 Sleek)."] })
            sFB.AddRow(
                row(sFB.frame, ns.L["Text Alignment"], fbAlignW),
                row(sFB.frame, ns.L["Bar Height"], fbBarHeightW)
            )

            local fontList = {}
            if LSM then
                for name in pairs(LSM:HashTable("font")) do
                    fontList[#fontList + 1] = {value = name, text = name}
                end
                table.sort(fontList, function(a, b) return a.text < b.text end)
            end

            local fbSizeW = GUI:CreateFormSlider(sFB.frame, nil, 8, 18, 1, "forcesFontSize", mpDB, RefreshLayout,
                { description = ns.L["Font size for the forces-bar text."] })
            if #fontList > 0 then
                local fbFontW = GUI:CreateFormDropdown(sFB.frame, nil, fontList, "forcesFont", mpDB, RefreshLayout,
                    { description = ns.L["Font used for the forces-bar text."] })
                sFB.AddRow(
                    row(sFB.frame, ns.L["Font"], fbFontW),
                    row(sFB.frame, ns.L["Font Size"], fbSizeW)
                )
            else
                sFB.AddRow(row(sFB.frame, ns.L["Font Size"], fbSizeW))
            end

            local fbTextColorW = GUI:CreateFormColorPicker(sFB.frame, nil, "forcesTextColor", mpDB, function()
                local MPlusTimer = _G.QUI_MPlusTimer
                if MPlusTimer and MPlusTimer.RenderForces then MPlusTimer:RenderForces() end
                RefreshSkin()
            end, nil, { description = ns.L["Color used for the forces-bar text."] })

            local fbBarColorPicker
            local fbBarClassW = GUI:CreateFormCheckbox(sFB.frame, nil, "barUseClassColor", mpDB, function()
                if fbBarColorPicker and fbBarColorPicker.SetEnabled then
                    fbBarColorPicker:SetEnabled(not mpDB.barUseClassColor)
                end
                RefreshSkin()
            end, { description = ns.L["Tint the forces progress bar with your class color instead of the Bar Fill Color below."] })
            sFB.AddRow(
                row(sFB.frame, ns.L["Text Color"], fbTextColorW),
                row(sFB.frame, ns.L["Use Class Color for Bar"], fbBarClassW)
            )

            fbBarColorPicker = GUI:CreateFormColorPicker(sFB.frame, nil, "barColor", mpDB, RefreshSkin, { noAlpha = true },
                { description = ns.L["Fallback fill color for the forces progress bar when Use Class Color for Bar is off."] })
            if fbBarColorPicker.SetEnabled then fbBarColorPicker:SetEnabled(not mpDB.barUseClassColor) end
            sFB.AddRow(row(sFB.frame, ns.L["Bar Fill Color"], fbBarColorPicker))
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
