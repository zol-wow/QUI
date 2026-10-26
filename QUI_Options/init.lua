local ADDON_NAME, ns = ...
local QUI = QUI
local GUI = QUI.GUI

local function IsLockedDown()
    return type(InCombatLockdown) == "function" and InCombatLockdown()
end

local function SetKeyboardPropagation(frame, propagate)
    if IsLockedDown() then return false end
    if frame and frame.SetPropagateKeyboardInput then
        frame:SetPropagateKeyboardInput(propagate)
        return true
    end
    return false
end

function GUI:InitializeOptions()
    local frame = self:CreateMainFrame()

    self:AddSidebarSearchBar(frame)

    frame:EnableKeyboard(true)
    frame:SetScript("OnKeyDown", function(self, key)
        local focused = GetCurrentKeyBoardFocus and GetCurrentKeyBoardFocus()
        if (not focused or key == "ESCAPE") and GUI.HandleNavigationKey and GUI:HandleNavigationKey(self, key) then
            SetKeyboardPropagation(self, false)
            return
        end
        if key == "ESCAPE" then
            SetKeyboardPropagation(self, false)
            self:Hide()
            return
        end
        if focused and focused ~= frame._searchBox and focused ~= (frame._searchBox and frame._searchBox.editBox) then
            SetKeyboardPropagation(self, true)
            return
        end
        local ctrl = IsControlKeyDown and IsControlKeyDown()
        if ctrl and key == "F" then
            SetKeyboardPropagation(self, false)
            C_Timer.After(0, function()
                GUI:FocusSearchBox()
            end)
            return
        end
        SetKeyboardPropagation(self, true)
    end)

    ns.QUI_Options.RegisterAllFeatureTiles(frame)

    self:AddToolsStripButton(frame, {
        id = "cdm_settings", icon = "+", label = ns.L["Blizz CDM"],
        onClick = function()
            if CooldownViewerSettings then
                CooldownViewerSettings:SetShown(not CooldownViewerSettings:IsShown())
            end
        end,
    })
    self:AddToolsStripButton(frame, {
        id = "blizz_edit", icon = ">", label = ns.L["Blizz Edit"],
        onClick = function()
            if InCombatLockdown() then return end
            if EditModeManagerFrame then
                ShowUIPanel(EditModeManagerFrame)
            end
        end,
    })
    self:AddToolsStripButton(frame, {
        id = "layout", label = ns.L["Layout Mode"],
        onClick = function()
            if InCombatLockdown and InCombatLockdown() then
                print("|cff60A5FAQUI:|r Cannot open Layout Mode during combat.")
                return
            end
            if GUI and GUI.Hide then GUI:Hide() end
            if _G.QUI_OpenLayoutMode then _G.QUI_OpenLayoutMode() end
        end,
    })

    self:SeedStaticSearchRoutesFromTiles(frame)

    if self.LayoutSidebarGroups then self:LayoutSidebarGroups(frame) end

    GUI:SelectFeatureTile(frame, 1)

    return frame
end
