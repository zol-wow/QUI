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

        local function MakeLayout(content)
            if U._layoutModePositionOnly then
                return U.MakeSuppressedProviderLayout(content)
            end
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

            Helpers.EnsureDefaults(db, {
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
            L.headerAt("General")
            local sGen = L.sectionAt()
            local genEnableW = GUI:CreateFormCheckbox(sGen.frame, nil, "enabled", db, Refresh,
                { description = "Show per-enemy forces contribution on M+ tooltips and nameplates." })
            local genTooltipW = GUI:CreateFormCheckbox(sGen.frame, nil, "tooltipEnabled", db, Refresh,
                { description = "Add the enemy forces contribution to unit tooltips in active Mythic+ runs." })
            sGen.AddRow(
                row(sGen.frame, "Enable M+ Mob Progress", genEnableW),
                row(sGen.frame, "Show Tooltip Progress", genTooltipW)
            )

            local genNameplateW = GUI:CreateFormCheckbox(sGen.frame, nil, "nameplateEnabled", db, Refresh,
                { description = "Show each visible enemy's forces contribution next to its nameplate." })
            sGen.AddRow(row(sGen.frame, "Show Nameplate Progress", genNameplateW))
            L.closeSection(sGen)

            -- Tooltips
            L.headerAt("Tooltips")
            local sTT = L.sectionAt()
            local ttCountW = GUI:CreateFormCheckbox(sTT.frame, nil, "tooltipIncludeCount", db, Refresh,
                { description = "Show the enemy's count contribution when the value is available for Lua to inspect." })
            local ttNoProgW = GUI:CreateFormCheckbox(sTT.frame, nil, "tooltipShowNoProgress", db, Refresh,
                { description = "Show a tooltip line for attackable enemies that do not contribute forces." })
            sTT.AddRow(
                row(sTT.frame, "Include Count", ttCountW),
                row(sTT.frame, "Show No Progress Line", ttNoProgW)
            )
            L.closeSection(sTT)

            -- Nameplates
            L.headerAt("Nameplates")
            local sNP = L.sectionAt()
            local formatOpts = {
                { text = "+2.5%",        value = "+$percent$%" },
                { text = "2.5%",         value = "$percent$%" },
                { text = "2.5",          value = "$percent$" },
                { text = "Forces: 2.5%", value = "Forces: $percent$%" },
            }
            local npFmtW = GUI:CreateFormDropdown(sNP.frame, nil, formatOpts, "nameplateTextFormat", db, Refresh,
                { description = "How each enemy's forces contribution is shown next to its nameplate." })
            local npScaleW = GUI:CreateFormSlider(sNP.frame, nil, 0.5, 2.0, 0.05, "nameplateTextScale", db, Refresh,
                { deferOnDrag = true, precision = 2, description = "Scale of the M+ progress text attached to nameplates." })
            sNP.AddRow(
                row(sNP.frame, "Text Format", npFmtW),
                row(sNP.frame, "Text Scale", npScaleW)
            )

            local fontList = { { value = "", text = "(Global Font)" } }
            if LSM then
                local names = {}
                for name in pairs(LSM:HashTable("font")) do names[#names + 1] = name end
                table.sort(names)
                for _, name in ipairs(names) do
                    fontList[#fontList + 1] = { value = name, text = name }
                end
            end
            local npFontW = GUI:CreateFormDropdown(sNP.frame, nil, fontList, "nameplateFont", db, Refresh,
                { description = "Font for the nameplate progress text. Pick (Global Font) to inherit the UI font." })
            local npSizeW = GUI:CreateFormSlider(sNP.frame, nil, 8, 18, 1, "nameplateFontSize", db, Refresh,
                { description = "Font size for the nameplate progress text." })
            sNP.AddRow(
                row(sNP.frame, "Font", npFontW),
                row(sNP.frame, "Font Size", npSizeW)
            )

            local npXW = GUI:CreateFormSlider(sNP.frame, nil, -100, 100, 1, "nameplateOffsetX", db, Refresh,
                { description = "Horizontal offset from the right side of the nameplate." })
            local npYW = GUI:CreateFormSlider(sNP.frame, nil, -100, 100, 1, "nameplateOffsetY", db, Refresh,
                { description = "Vertical offset from the nameplate anchor." })
            sNP.AddRow(
                row(sNP.frame, "Offset X", npXW),
                row(sNP.frame, "Offset Y", npYW)
            )

            local npColorW = GUI:CreateFormColorPicker(sNP.frame, nil, "nameplateTextColor", db, Refresh, nil,
                { description = "Color used for M+ progress text on nameplates." })
            sNP.AddRow(row(sNP.frame, "Text Color", npColorW))
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
