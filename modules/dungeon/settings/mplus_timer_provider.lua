---------------------------------------------------------------------------
-- M+ TIMER SETTINGS PROVIDER
---------------------------------------------------------------------------
local ADDON_NAME, ns = ...

do
    local function RegisterMPlusTimerProvider()
        local settingsPanel = ns.QUI_LayoutMode_Settings
        if not settingsPanel then return end

        local GUI = QUI and QUI.GUI
        if not GUI then return end

        local Helpers = ns.Helpers
        local LSM = ns.LSM
        local U = ns.QUI_LayoutMode_Utils
        local P = U.PlaceRow
        local FORM_ROW = U and U.FORM_ROW or 32

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

        local function BuildMPlusTimerSettings(content, key, width)
            local mpDB = GetMPlusDB()
            if not mpDB then return 80 end

            local general = GetGeneralDB()
            local sections = {}
            local function relayout() U.StandardRelayout(content, sections) end

            -- Ensure defaults
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

            -- General
            U.CreateCollapsible(content, "General", 8 * FORM_ROW + 8, function(body)
                local sy = -4

                local layoutOptions = {
                    { text = "Compact", value = "compact" },
                    { text = "Full", value = "full" },
                    { text = "Sleek", value = "sleek" },
                }
                sy = P(GUI:CreateFormDropdown(body, "Layout Mode", layoutOptions, "layoutMode", mpDB, RefreshAll,
                    { description = "Overall timer layout: Compact is a single row; Full shows all key details; Sleek trims non-essentials." }), body, sy)

                sy = P(GUI:CreateFormSlider(body, "Timer Scale", 0.5, 2.0, 0.05, "scale", mpDB, function()
                    local MPlusTimer = _G.QUI_MPlusTimer
                    if MPlusTimer and MPlusTimer.ApplyScale then MPlusTimer:ApplyScale() end
                end, { deferOnDrag = true },
                    { description = "Zoom factor applied to the whole M+ timer panel." }), body, sy)

                sy = P(GUI:CreateFormSlider(body, "Max Dungeon Name Length", 0, 40, 1, "maxDungeonNameLength", mpDB, function()
                    local MPlusTimer = _G.QUI_MPlusTimer
                    if MPlusTimer and MPlusTimer.RenderKeyDetails then MPlusTimer:RenderKeyDetails() end
                end, nil,
                    { description = "Truncate the dungeon name to this many characters. Set to 0 to show the full name." }), body, sy)

                sy = P(GUI:CreateFormCheckbox(body, "Show Timer Text (Full mode)", "showTimer", mpDB, RefreshLayout,
                    { description = "Show the numeric 'time remaining' text in Full layout mode. Compact/Sleek modes hide it regardless." }), body, sy)
                sy = P(GUI:CreateFormCheckbox(body, "Show Deaths", "showDeaths", mpDB, RefreshLayout,
                    { description = "Show the deaths counter and penalty time on the timer panel." }), body, sy)
                sy = P(GUI:CreateFormCheckbox(body, "Show Affixes", "showAffixes", mpDB, RefreshLayout,
                    { description = "Show the active weekly affix icons on the timer panel." }), body, sy)
                sy = P(GUI:CreateFormCheckbox(body, "Show Objectives", "showObjectives", mpDB, RefreshLayout,
                    { description = "Show the boss/objective rows under the timer." }), body, sy)
                P(GUI:CreateFormCheckbox(body, "Show Border", "showBorder", mpDB, RefreshSkin,
                    { description = "Draw a border around the whole M+ timer panel." }), body, sy)
            end, sections, relayout)

            -- Border Override
            Helpers.EnsureDefaults(mpDB, {
                borderOverride = false,
                hideBorder = false,
                borderUseClassColor = false,
            })
            if mpDB.borderColor == nil then
                local fb = general and (general.skinBorderColor or general.addonAccentColor) or { 0.376, 0.647, 0.980, 1 }
                mpDB.borderColor = { fb[1], fb[2], fb[3], fb[4] or 1 }
            end

            U.CreateCollapsible(content, "Border", 4 * FORM_ROW + 8, function(body)
                local sy = -4
                local colorPicker, hideCheck, classCheck

                local function UpdateState()
                    local enabled = mpDB.borderOverride
                    if hideCheck then hideCheck:SetEnabled(enabled) end
                    if classCheck then classCheck:SetEnabled(enabled) end
                    if colorPicker then colorPicker:SetEnabled(enabled and not mpDB.borderUseClassColor) end
                end

                local overrideCheck = GUI:CreateFormCheckbox(body, "Override Global Border", "borderOverride", mpDB, function()
                    UpdateState()
                    RefreshColors()
                end, { description = "Use M+ timer-specific border settings instead of the shared skinning border. Enables the controls below." })
                sy = P(overrideCheck, body, sy)

                hideCheck = GUI:CreateFormCheckbox(body, "Hide Border", "hideBorder", mpDB, RefreshColors,
                    { description = "Hide the border around the M+ timer panel entirely." })
                sy = P(hideCheck, body, sy)

                classCheck = GUI:CreateFormCheckbox(body, "Use Class Color", "borderUseClassColor", mpDB, function()
                    UpdateState()
                    RefreshColors()
                end, { description = "Tint the M+ timer border with your class color instead of the custom Border Color below." })
                sy = P(classCheck, body, sy)

                colorPicker = GUI:CreateFormColorPicker(body, "Border Color", "borderColor", mpDB, RefreshColors, { noAlpha = true },
                    { description = "Custom border color applied when Override Global Border is on and Use Class Color is off." })
                P(colorPicker, body, sy)

                UpdateState()
            end, sections, relayout)

            -- Background Override
            Helpers.EnsureDefaults(mpDB, {
                bgOverride = false,
                hideBackground = false,
                frameBackgroundOpacity = 1,
            })
            if mpDB.backgroundColor == nil then
                local fb = general and general.skinBgColor or { 0.05, 0.05, 0.05, 0.95 }
                mpDB.backgroundColor = { fb[1], fb[2], fb[3], fb[4] or 0.95 }
            end

            U.CreateCollapsible(content, "Background", 4 * FORM_ROW + 8, function(body)
                local sy = -4
                local colorPicker, hideCheck

                local function UpdateState()
                    local enabled = mpDB.bgOverride
                    if hideCheck then hideCheck:SetEnabled(enabled) end
                    if colorPicker then colorPicker:SetEnabled(enabled and not mpDB.hideBackground) end
                end

                local overrideCheck = GUI:CreateFormCheckbox(body, "Override Global Background", "bgOverride", mpDB, function()
                    UpdateState()
                    RefreshColors()
                end, { description = "Use M+ timer-specific background settings instead of the shared skinning background. Enables the controls below." })
                sy = P(overrideCheck, body, sy)

                hideCheck = GUI:CreateFormCheckbox(body, "Hide Background", "hideBackground", mpDB, function()
                    UpdateState()
                    RefreshColors()
                end, { description = "Hide the backdrop fill behind the M+ timer panel entirely." })
                sy = P(hideCheck, body, sy)

                colorPicker = GUI:CreateFormColorPicker(body, "Background Color", "backgroundColor", mpDB, RefreshColors, nil,
                    { description = "Custom background color applied when Override Global Background is on and Hide Background is off." })
                sy = P(colorPicker, body, sy)

                P(GUI:CreateFormSlider(body, "Panel Opacity", 0, 1, 0.05, "frameBackgroundOpacity", mpDB, RefreshSkin, { deferOnDrag = true },
                    { description = "Opacity of the M+ timer background fill. 0 is fully transparent, 1 is fully opaque." }), body, sy)

                UpdateState()
            end, sections, relayout)

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

            U.CreateCollapsible(content, "Forces Bar", 9 * FORM_ROW + 8, function(body)
                local sy = -4

                sy = P(GUI:CreateFormCheckbox(body, "Show Forces Bar", "forcesBarEnabled", mpDB, RefreshLayout,
                    { description = "Show the trash-count / forces progress element on the timer panel." }), body, sy)

                local displayModeOpts = {
                    { text = "Progress Bar", value = "bar" },
                    { text = "Text Only", value = "text" },
                }
                sy = P(GUI:CreateFormDropdown(body, "Display Mode", displayModeOpts, "forcesDisplayMode", mpDB, RefreshLayout,
                    { description = "Render forces progress as a filling bar or as text only." }), body, sy)

                local posOpts = {
                    { text = "After Timer Bars", value = "after_timer" },
                    { text = "Before Timer Bars", value = "before_timer" },
                    { text = "Before Objectives", value = "before_objectives" },
                    { text = "After Objectives", value = "after_objectives" },
                }
                sy = P(GUI:CreateFormDropdown(body, "Position", posOpts, "forcesPosition", mpDB, RefreshLayout,
                    { description = "Where the forces bar / text is inserted relative to the timer bars and objective rows." }), body, sy)

                local formatOpts = {
                    { text = "Count (123/273)", value = "count" },
                    { text = "Percentage (45.32%)", value = "percentage" },
                    { text = "Both", value = "both" },
                }
                sy = P(GUI:CreateFormDropdown(body, "Text Format", formatOpts, "forcesTextFormat", mpDB, function()
                    local MPlusTimer = _G.QUI_MPlusTimer
                    if MPlusTimer and MPlusTimer.RenderForces then MPlusTimer:RenderForces() end
                end, { description = "How forces progress is formatted: running count, percent, or both." }), body, sy)

                -- Font dropdown
                local fontList = {}
                if LSM then
                    for name in pairs(LSM:HashTable("font")) do
                        fontList[#fontList + 1] = {value = name, text = name}
                    end
                    table.sort(fontList, function(a, b) return a.text < b.text end)
                end
                if #fontList > 0 then
                    sy = P(GUI:CreateFormDropdown(body, "Font", fontList, "forcesFont", mpDB, RefreshLayout,
                        { description = "Font used for the forces-bar text." }), body, sy)
                end

                sy = P(GUI:CreateFormSlider(body, "Font Size", 8, 18, 1, "forcesFontSize", mpDB, RefreshLayout, nil,
                    { description = "Font size for the forces-bar text." }), body, sy)

                sy = P(GUI:CreateFormColorPicker(body, "Text Color", "forcesTextColor", mpDB, function()
                    local MPlusTimer = _G.QUI_MPlusTimer
                    if MPlusTimer and MPlusTimer.RenderForces then MPlusTimer:RenderForces() end
                    RefreshSkin()
                end, nil, { description = "Color used for the forces-bar text." }), body, sy)

                local barColorPicker
                local barClassCheck = GUI:CreateFormCheckbox(body, "Use Class Color for Bar", "barUseClassColor", mpDB, function()
                    if barColorPicker then barColorPicker:SetEnabled(not mpDB.barUseClassColor) end
                    RefreshSkin()
                end, { description = "Tint the forces progress bar with your class color instead of the Bar Fill Color below." })
                sy = P(barClassCheck, body, sy)

                barColorPicker = GUI:CreateFormColorPicker(body, "Bar Fill Color", "barColor", mpDB, RefreshSkin, { noAlpha = true },
                    { description = "Fallback fill color for the forces progress bar when Use Class Color for Bar is off." })
                P(barColorPicker, body, sy)
                barColorPicker:SetEnabled(not mpDB.barUseClassColor)
            end, sections, relayout)

            -- Position
            U.BuildPositionCollapsible(content, "mplusTimer", nil, sections, relayout)
            U.BuildOpenFullSettingsLink(content, key, sections, relayout)

            relayout()
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
