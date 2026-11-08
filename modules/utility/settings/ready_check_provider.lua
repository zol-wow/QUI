local _, ns = ...

do
    local function RegisterReadyCheckProvider()
        local settingsPanel = ns.QUI_LayoutMode_Settings
        if not settingsPanel then return end

        local GUI = QUI and QUI.GUI
        if not GUI then return end

        local Helpers = ns.Helpers
        local U = ns.QUI_LayoutMode_Utils
        local Opts = ns.QUI_Options
        local PAD = (Opts and Opts.PADDING) or 15
        local HEADER_GAP = 26
        local SECTION_GAP = 14

        local function GetGeneralDB()
            local core = Helpers.GetCore()
            return core and core.db and core.db.profile and core.db.profile.general
        end

        local function RefreshColors()
            if _G.QUI_RefreshReadyCheckColors then _G.QUI_RefreshReadyCheckColors() end
        end

        local function MakeLayout(content)
            if U._layoutModePositionOnly then
                return U.MakeSuppressedProviderLayout(content)
            end
            return ns.QUI_SettingsLayoutShared.MakeLayout(content, U)
        end

        local function row(parent, label, widget, desc)
            return Opts.BuildSettingRow(parent, label, widget, desc)
        end

        local function BuildReadyCheckSettings(content, key, _width)
            Opts = ns.QUI_Options or Opts
            PAD = (Opts and Opts.PADDING) or PAD

            local general = GetGeneralDB()
            if not general then return 80 end

            if general.skinReadyCheck == nil then general.skinReadyCheck = true end

            local L = MakeLayout(content)

            L.headerAt(ns.L["Skinning"])
            local sSk = L.sectionAt()
            local skinW = GUI:CreateFormCheckbox(sSk.frame, nil, "skinReadyCheck", general, function()
                GUI:ShowConfirmation({
                    reload = true,
                    title = ns.L["Reload UI?"],
                    message = ns.L["Skinning changes require a reload to take effect."],
                    acceptText = ns.L["Reload"],
                    cancelText = ns.L["Later"],
                    onAccept = function() QUI:SafeReload() end,
                })
            end, { description = ns.L["Apply QUI styling to the Blizzard ready-check popup. Requires a UI reload to take effect."] })
            sSk.AddRow(row(sSk.frame, ns.L["Skin Ready Check Frame"], skinW))
            L.closeSection(sSk)

            L.headerAt(ns.L["Border"])
            local sBd = L.sectionAt()
            local rcSrcW, rcColW = ns.QUI_BorderControl.Attach(GUI, sBd.frame, general, "readyCheck", RefreshColors,
                { label = ns.L["Border Color Source"], colorLabel = ns.L["Border Color"], noAlpha = true })
            sBd.AddRow(row(sBd.frame, ns.L["Border Color Source"], rcSrcW), row(sBd.frame, ns.L["Border Color"], rcColW))
            L.closeSection(sBd)

            if general.readyCheckBackgroundColor == nil then
                local color = general.skinBgColor or { 0.008, 0.008, 0.008, 1 }
                general.readyCheckBackgroundColor = { color[1], color[2], color[3], color[4] or 1 }
            end
            L.headerAt(ns.L["Background"])
            local sBg = L.sectionAt()
            local overrideW = GUI:CreateFormCheckbox(sBg.frame, nil, "readyCheckBgOverride", general, RefreshColors,
                { description = ns.L["Use a background color specific to this skin instead of the global default chosen in Theme & Colors."] })
            local hideW = GUI:CreateFormCheckbox(sBg.frame, nil, "readyCheckHideBackground", general, RefreshColors,
                { description = ns.L["Hide the background fill on this skin entirely. Only takes effect when the override above is enabled."] })
            sBg.AddRow(row(sBg.frame, ns.L["Override Global Background"], overrideW), row(sBg.frame, ns.L["Hide Background"], hideW))
            local colorW = GUI:CreateFormColorPicker(sBg.frame, nil, "readyCheckBackgroundColor", general, RefreshColors, nil,
                { description = ns.L["Custom background color used when override is enabled."] })
            sBg.AddRow(row(sBg.frame, ns.L["Background Color"], colorW))
            L.closeSection(sBg)

            U.BuildPositionCollapsible(content, "readyCheck", nil, L.sections, L.relayoutSections)
            U.BuildOpenFullSettingsLink(content, key, L.sections, L.relayoutSections)
            L.relayoutSections()
            return content:GetHeight()
        end

        settingsPanel:RegisterSharedProvider("readyCheck", {
            build = BuildReadyCheckSettings,
        })
        local adapters = ns.Settings and ns.Settings.RenderAdapters
        if adapters and type(adapters.NotifyProviderChanged) == "function" then
            adapters.NotifyProviderChanged("readyCheck", { structural = true })
        end
    end

    local ProviderPanels = ns.Settings and ns.Settings.ProviderPanels
    if ProviderPanels and type(ProviderPanels.RegisterAfterLoad) == "function" then
        ProviderPanels:RegisterAfterLoad(function()
            RegisterReadyCheckProvider()
        end)
    else
        RegisterReadyCheckProvider()
    end
end
