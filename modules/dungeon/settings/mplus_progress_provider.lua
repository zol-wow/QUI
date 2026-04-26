---------------------------------------------------------------------------
-- M+ PROGRESS SETTINGS PROVIDER
---------------------------------------------------------------------------
local ADDON_NAME, ns = ...

do
    local function RegisterMPlusProgressProvider()
        local settingsPanel = ns.QUI_LayoutMode_Settings
        if not settingsPanel then return end

        local GUI = QUI and QUI.GUI
        if not GUI then return end

        local Helpers = ns.Helpers
        local U = ns.QUI_LayoutMode_Utils
        local P = U.PlaceRow
        local FORM_ROW = U and U.FORM_ROW or 32

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

        local function BuildMPlusProgressSettings(content, key, width)
            local db = GetProgressDB()
            if not db then return 80 end

            local sections = {}
            local function relayout() U.StandardRelayout(content, sections) end

            Helpers.EnsureDefaults(db, {
                enabled = true,
                tooltipEnabled = true,
                tooltipIncludeCount = true,
                tooltipShowNoProgress = false,
                nameplateEnabled = true,
                nameplateTextFormat = "+$percent$%",
                nameplateTextColor = { 1, 1, 1, 1 },
                nameplateTextScale = 1.0,
                nameplateOffsetX = 0,
                nameplateOffsetY = 0,
            })

            U.CreateCollapsible(content, "General", 3 * FORM_ROW + 8, function(body)
                local sy = -4

                sy = P(GUI:CreateFormCheckbox(body, "Enable M+ Mob Progress", "enabled", db, Refresh,
                    { description = "Show per-enemy forces contribution on M+ tooltips and nameplates." }), body, sy)
                sy = P(GUI:CreateFormCheckbox(body, "Show Tooltip Progress", "tooltipEnabled", db, Refresh,
                    { description = "Add the enemy forces contribution to unit tooltips in active Mythic+ runs." }), body, sy)
                P(GUI:CreateFormCheckbox(body, "Show Nameplate Progress", "nameplateEnabled", db, Refresh,
                    { description = "Show each visible enemy's forces contribution next to its nameplate." }), body, sy)
            end, sections, relayout)

            U.CreateCollapsible(content, "Tooltips", 2 * FORM_ROW + 8, function(body)
                local sy = -4
                sy = P(GUI:CreateFormCheckbox(body, "Include Count", "tooltipIncludeCount", db, Refresh,
                    { description = "Show the enemy's count contribution when the value is available for Lua to inspect." }), body, sy)
                P(GUI:CreateFormCheckbox(body, "Show No Progress Line", "tooltipShowNoProgress", db, Refresh,
                    { description = "Show a tooltip line for attackable enemies that do not contribute forces." }), body, sy)
            end, sections, relayout)

            U.CreateCollapsible(content, "Nameplates", 5 * FORM_ROW + 8, function(body)
                local sy = -4

                sy = P(GUI:CreateFormEditBox(body, "Text Format", "nameplateTextFormat", db, Refresh,
                    { maxLetters = 32 },
                    { description = "Nameplate text format. Use $percent$ for the enemy's forces contribution." }), body, sy)
                sy = P(GUI:CreateFormSlider(body, "Text Scale", 0.5, 2.0, 0.05, "nameplateTextScale", db, Refresh, { deferOnDrag = true },
                    { description = "Scale of the M+ progress text attached to nameplates." }), body, sy)
                sy = P(GUI:CreateFormSlider(body, "Offset X", -100, 100, 1, "nameplateOffsetX", db, Refresh, nil,
                    { description = "Horizontal offset from the right side of the nameplate." }), body, sy)
                sy = P(GUI:CreateFormSlider(body, "Offset Y", -100, 100, 1, "nameplateOffsetY", db, Refresh, nil,
                    { description = "Vertical offset from the nameplate anchor." }), body, sy)
                P(GUI:CreateFormColorPicker(body, "Text Color", "nameplateTextColor", db, Refresh, nil,
                    { description = "Color used for M+ progress text on nameplates." }), body, sy)
            end, sections, relayout)

            U.BuildOpenFullSettingsLink(content, key, sections, relayout)

            relayout()
            return content:GetHeight()
        end

        settingsPanel:RegisterSharedProvider("mplusProgress", {
            build = BuildMPlusProgressSettings,
        })
    end

    C_Timer.After(3, RegisterMPlusProgressProvider)
end
