---------------------------------------------------------------------------
-- M+ PROGRESS SETTINGS PROVIDER (V3)
---------------------------------------------------------------------------
local _, ns = ...

do
    local function RegisterMPlusProgressProvider()
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

        local function GetProgressDB()
            local core = Helpers.GetCore()
            local db = core and core.db and core.db.profile
            return db and db.mplusProgress
        end

        local function Refresh()
            if _G.QUI_RefreshMPlusProgress then
                _G.QUI_RefreshMPlusProgress()
            end
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

        local function BuildMPlusProgressSettings(content, key, _width)
            -- core/gui_shell.lua installs a minimal ns.QUI_Options stub, then
            -- the on-demand QUI_Options addon (shared.lua) REPLACES the table
            -- with the real one carrying the V3 body helpers. The Opts upvalue
            -- captured at registration can thus be nil (headless) or the stale
            -- stub (which lacks CreateAccentDotLabel). Re-resolve live-first each
            -- build: a truthy stale stub must not win over the replacement.
            Opts = ns.QUI_Options or Opts
            PAD = (Opts and Opts.PADDING) or PAD

            local db = GetProgressDB()
            if not db then return 80 end

            -- Reuse the feature's single DEFAULTS table so the panel and the
            -- mplus_progress.lua feature can never diverge. ns.MPlusProgress is
            -- defined by the QUI_QoL login module, loaded before this on-demand
            -- options page; the inline fallback covers the headless harness.
            Helpers.EnsureDefaults(db, (ns.MPlusProgress and ns.MPlusProgress.DEFAULTS) or {
                enabled = true,
                tooltipEnabled = true,
                tooltipIncludeCount = true,
                tooltipShowNoProgress = false,
                nameplateEnabled = true,
                nameplateTextFormat = "+$percent$%",
                nameplateFont = "",
                nameplateFontSize = 12,
                nameplateTextColor = { 1, 1, 1, 1 },
                nameplateTextScale = 1.0,
                nameplateOffsetX = 0,
                nameplateOffsetY = 0,
            })

            local L = MakeLayout(content)

            -- General
            L.headerAt(ns.L["General"])
            local sGen = L.sectionAt()
            local genEnableW = GUI:CreateFormCheckbox(sGen.frame, nil, "enabled", db, Refresh,
                { description = ns.L["Show per-enemy forces contribution on M+ tooltips and nameplates."] })
            local genTooltipW = GUI:CreateFormCheckbox(sGen.frame, nil, "tooltipEnabled", db, Refresh,
                { description = ns.L["Add the enemy forces contribution to unit tooltips in active Mythic+ runs."] })
            sGen.AddRow(
                row(sGen.frame, ns.L["Enable M+ Mob Progress"], genEnableW),
                row(sGen.frame, ns.L["Show Tooltip Progress"], genTooltipW)
            )

            local genNameplateW = GUI:CreateFormCheckbox(sGen.frame, nil, "nameplateEnabled", db, Refresh,
                { description = ns.L["Show each visible enemy's forces contribution next to its nameplate."] })
            sGen.AddRow(row(sGen.frame, ns.L["Show Nameplate Progress"], genNameplateW))
            L.closeSection(sGen)

            -- Tooltips
            L.headerAt(ns.L["Tooltips"])
            local sTT = L.sectionAt()
            local ttCountW = GUI:CreateFormCheckbox(sTT.frame, nil, "tooltipIncludeCount", db, Refresh,
                { description = ns.L["Show the enemy's count contribution when the value is available for Lua to inspect."] })
            local ttNoProgW = GUI:CreateFormCheckbox(sTT.frame, nil, "tooltipShowNoProgress", db, Refresh,
                { description = ns.L["Show a tooltip line for attackable enemies that do not contribute forces."] })
            sTT.AddRow(
                row(sTT.frame, ns.L["Include Count"], ttCountW),
                row(sTT.frame, ns.L["Show No Progress Line"], ttNoProgW)
            )
            L.closeSection(sTT)

            -- Nameplates
            L.headerAt(ns.L["Nameplates"])
            local sNP = L.sectionAt()
            local formatOpts = {
                { text = ns.L["+2.5%"],        value = "+$percent$%" },
                { text = ns.L["2.5%"],         value = "$percent$%" },
                { text = ns.L["2.5"],          value = "$percent$" },
                { text = ns.L["Forces: 2.5%"], value = "Forces: $percent$%" },
            }
            local npFmtW = GUI:CreateFormDropdown(sNP.frame, nil, formatOpts, "nameplateTextFormat", db, Refresh,
                { description = ns.L["How each enemy's forces contribution is shown next to its nameplate."] })
            local npScaleW = GUI:CreateFormSlider(sNP.frame, nil, 0.5, 2.0, 0.05, "nameplateTextScale", db, Refresh,
                { deferOnDrag = true, precision = 2, description = ns.L["Scale of the M+ progress text attached to nameplates."] })
            sNP.AddRow(
                row(sNP.frame, ns.L["Text Format"], npFmtW),
                row(sNP.frame, ns.L["Text Scale"], npScaleW)
            )

            local fontList = { { value = "", text = ns.L["(Global Font)"] } }
            if LSM then
                local names = {}
                for name in pairs(LSM:HashTable("font")) do names[#names + 1] = name end
                table.sort(names)
                for _, name in ipairs(names) do
                    fontList[#fontList + 1] = { value = name, text = name }
                end
            end
            local npFontW = GUI:CreateFormDropdown(sNP.frame, nil, fontList, "nameplateFont", db, Refresh,
                { description = ns.L["Font for the nameplate progress text. Pick (Global Font) to inherit the UI font."] })
            local npSizeW = GUI:CreateFormSlider(sNP.frame, nil, 8, 18, 1, "nameplateFontSize", db, Refresh,
                { description = ns.L["Font size for the nameplate progress text."] })
            sNP.AddRow(
                row(sNP.frame, ns.L["Font"], npFontW),
                row(sNP.frame, ns.L["Font Size"], npSizeW)
            )

            local npXW = GUI:CreateFormSlider(sNP.frame, nil, -100, 100, 1, "nameplateOffsetX", db, Refresh,
                { description = ns.L["Horizontal offset from the right side of the nameplate."] })
            local npYW = GUI:CreateFormSlider(sNP.frame, nil, -100, 100, 1, "nameplateOffsetY", db, Refresh,
                { description = ns.L["Vertical offset from the nameplate anchor."] })
            sNP.AddRow(
                row(sNP.frame, ns.L["Offset X"], npXW),
                row(sNP.frame, ns.L["Offset Y"], npYW)
            )

            local npColorW = GUI:CreateFormColorPicker(sNP.frame, nil, "nameplateTextColor", db, Refresh, nil,
                { description = ns.L["Color used for M+ progress text on nameplates."] })
            sNP.AddRow(row(sNP.frame, ns.L["Text Color"], npColorW))
            L.closeSection(sNP)

            -- Layout-mode chrome (no Position collapsible for this provider)
            U.BuildOpenFullSettingsLink(content, key, L.sections, L.relayoutSections)
            L.relayoutSections()
            return content:GetHeight()
        end

        settingsPanel:RegisterSharedProvider("mplusProgress", {
            build = BuildMPlusProgressSettings,
        })
    end

    C_Timer.After(3, RegisterMPlusProgressProvider)
end
