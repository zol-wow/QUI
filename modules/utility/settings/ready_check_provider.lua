---------------------------------------------------------------------------
-- READY CHECK SETTINGS PROVIDER (V3)
---------------------------------------------------------------------------
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

        local function BuildReadyCheckSettings(content, key, _width)
            -- Headless cache-gen loads this file before ns.QUI_Options exists,
            -- so the upvalues captured at the top of RegisterReadyCheckProvider
            -- can be nil. Refresh on each build invocation; live runtime is
            -- unaffected (RegisterAfterLoad guarantees QUI_Options is ready).
            Opts = Opts or ns.QUI_Options
            PAD = (Opts and Opts.PADDING) or PAD

            local general = GetGeneralDB()
            if not general then return 80 end

            if general.skinReadyCheck == nil then general.skinReadyCheck = true end
            Helpers.EnsureDefaults(general, {
                readyCheckBorderOverride = false,
                readyCheckHideBorder = false,
                readyCheckBorderUseClassColor = false,
            })
            if general.readyCheckBorderColor == nil then
                local fallback = general.skinBorderColor or general.addonAccentColor or { 0.376, 0.647, 0.980, 1 }
                general.readyCheckBorderColor = { fallback[1], fallback[2], fallback[3], fallback[4] or 1 }
            end

            local L = MakeLayout(content)

            -- Skinning
            L.headerAt("Skinning")
            local sSk = L.sectionAt()
            local skinW = GUI:CreateFormCheckbox(sSk.frame, nil, "skinReadyCheck", general, function()
                GUI:ShowConfirmation({
                    title = "Reload UI?",
                    message = "Skinning changes require a reload to take effect.",
                    acceptText = "Reload",
                    cancelText = "Later",
                    onAccept = function() QUI:SafeReload() end,
                })
            end, { description = "Apply QUI styling to the Blizzard ready-check popup. Requires a UI reload to take effect." })
            sSk.AddRow(row(sSk.frame, "Skin Ready Check Frame", skinW))
            L.closeSection(sSk)

            -- Border
            L.headerAt("Border")
            local sBd = L.sectionAt()
            local colorPicker, hideCheck, classCheck

            local function UpdateBorderState()
                local enabled = general.readyCheckBorderOverride
                if hideCheck and hideCheck.SetEnabled then hideCheck:SetEnabled(enabled) end
                if classCheck and classCheck.SetEnabled then classCheck:SetEnabled(enabled) end
                if colorPicker and colorPicker.SetEnabled then
                    colorPicker:SetEnabled(enabled and not general.readyCheckBorderUseClassColor)
                end
            end

            local overrideCheck = GUI:CreateFormCheckbox(sBd.frame, nil, "readyCheckBorderOverride", general, function()
                UpdateBorderState()
                RefreshColors()
            end, { description = "Use ready-check-specific border settings instead of the shared skinning border. Enables the controls below." })

            hideCheck = GUI:CreateFormCheckbox(sBd.frame, nil, "readyCheckHideBorder", general, RefreshColors,
                { description = "Hide the border around the ready-check frame entirely." })

            sBd.AddRow(
                row(sBd.frame, "Override Global Border", overrideCheck),
                row(sBd.frame, "Hide Border", hideCheck)
            )

            classCheck = GUI:CreateFormCheckbox(sBd.frame, nil, "readyCheckBorderUseClassColor", general, function()
                UpdateBorderState()
                RefreshColors()
            end, { description = "Tint the ready-check border with your class color instead of the custom Border Color below." })

            colorPicker = GUI:CreateFormColorPicker(sBd.frame, nil, "readyCheckBorderColor", general, RefreshColors, { noAlpha = true },
                { description = "Custom border color applied when Override Global Border is on and Use Class Color is off." })

            sBd.AddRow(
                row(sBd.frame, "Use Class Color", classCheck),
                row(sBd.frame, "Border Color", colorPicker)
            )

            UpdateBorderState()
            L.closeSection(sBd)

            -- Layout-mode chrome (V3-styled collapsibles)
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
