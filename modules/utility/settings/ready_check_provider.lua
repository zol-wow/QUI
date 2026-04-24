---------------------------------------------------------------------------
-- READY CHECK SETTINGS PROVIDER
---------------------------------------------------------------------------
local ADDON_NAME, ns = ...

do
    local function RegisterReadyCheckProvider()
        local settingsPanel = ns.QUI_LayoutMode_Settings
        if not settingsPanel then return end

        local GUI = QUI and QUI.GUI
        if not GUI then return end

        local Helpers = ns.Helpers
        local U = ns.QUI_LayoutMode_Utils
        local P = U.PlaceRow
        local FORM_ROW = U and U.FORM_ROW or 32

        local function GetGeneralDB()
            local core = Helpers.GetCore()
            return core and core.db and core.db.profile and core.db.profile.general
        end

        local function RefreshColors()
            if _G.QUI_RefreshReadyCheckColors then _G.QUI_RefreshReadyCheckColors() end
        end

        local function BuildReadyCheckSettings(content, key, width)
            local general = GetGeneralDB()
            if not general then return 80 end

            local sections = {}
            local function relayout() U.StandardRelayout(content, sections) end

            -- Skinning
            U.CreateCollapsible(content, "Skinning", 1 * FORM_ROW + 8, function(body)
                local sy = -4

                local skinCheck = GUI:CreateFormCheckbox(body, "Skin Ready Check Frame", "skinReadyCheck", general, function()
                    GUI:ShowConfirmation({
                        title = "Reload UI?",
                        message = "Skinning changes require a reload to take effect.",
                        acceptText = "Reload",
                        cancelText = "Later",
                        onAccept = function() QUI:SafeReload() end,
                    })
                end, { description = "Apply QUI styling to the Blizzard ready-check popup. Requires a UI reload to take effect." })
                P(skinCheck, body, sy)
            end, sections, relayout)

            -- Border Override
            Helpers.EnsureDefaults(general, {
                readyCheckBorderOverride = false,
                readyCheckHideBorder = false,
                readyCheckBorderUseClassColor = false,
            })
            if general.readyCheckBorderColor == nil then
                local fallback = general.skinBorderColor or general.addonAccentColor or { 0.376, 0.647, 0.980, 1 }
                general.readyCheckBorderColor = { fallback[1], fallback[2], fallback[3], fallback[4] or 1 }
            end

            U.CreateCollapsible(content, "Border", 4 * FORM_ROW + 8, function(body)
                local sy = -4
                local colorPicker, hideCheck, classCheck

                local function UpdateBorderState()
                    local enabled = general.readyCheckBorderOverride
                    if hideCheck then hideCheck:SetEnabled(enabled) end
                    if classCheck then classCheck:SetEnabled(enabled) end
                    if colorPicker then
                        colorPicker:SetEnabled(enabled and not general.readyCheckBorderUseClassColor)
                    end
                end

                local overrideCheck = GUI:CreateFormCheckbox(body, "Override Global Border", "readyCheckBorderOverride", general, function()
                    UpdateBorderState()
                    RefreshColors()
                end, { description = "Use ready-check-specific border settings instead of the shared skinning border. Enables the controls below." })
                sy = P(overrideCheck, body, sy)

                hideCheck = GUI:CreateFormCheckbox(body, "Hide Border", "readyCheckHideBorder", general, RefreshColors,
                    { description = "Hide the border around the ready-check frame entirely." })
                sy = P(hideCheck, body, sy)

                classCheck = GUI:CreateFormCheckbox(body, "Use Class Color", "readyCheckBorderUseClassColor", general, function()
                    UpdateBorderState()
                    RefreshColors()
                end, { description = "Tint the ready-check border with your class color instead of the custom Border Color below." })
                sy = P(classCheck, body, sy)

                colorPicker = GUI:CreateFormColorPicker(body, "Border Color", "readyCheckBorderColor", general, RefreshColors, { noAlpha = true },
                    { description = "Custom border color applied when Override Global Border is on and Use Class Color is off." })
                P(colorPicker, body, sy)

                UpdateBorderState()
            end, sections, relayout)

            -- Position
            U.BuildPositionCollapsible(content, "readyCheck", nil, sections, relayout)
            U.BuildOpenFullSettingsLink(content, key, sections, relayout)

            relayout()
            return content:GetHeight()
        end

        settingsPanel:RegisterSharedProvider("readyCheck", {
            build = BuildReadyCheckSettings,
        })
    end

    C_Timer.After(3, RegisterReadyCheckProvider)
end
