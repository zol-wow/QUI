--[[
    QUI Options Init
    Registers feature tiles, Welcome, Help, Tools strip, and the inline
    search bar.
]]

local ADDON_NAME, ns = ...
local QUI = QUI
local GUI = QUI.GUI

function GUI:InitializeOptions()
    local frame = self:CreateMainFrame()

    -- Sidebar search bar (top)
    self:AddSidebarSearchBar(frame)

    -- Keyboard shortcut: / or Ctrl+F focuses the search box while the panel is open.
    frame:EnableKeyboard(true)
    frame:SetPropagateKeyboardInput(true)
    frame:SetScript("OnKeyDown", function(self, key)
        if key == "ESCAPE" then
            self:SetPropagateKeyboardInput(false)
            self:Hide()
            return
        end
        -- Don't intercept if the user is typing in another edit box.
        local focused = GetCurrentKeyBoardFocus and GetCurrentKeyBoardFocus()
        if focused and focused ~= frame._searchBox and focused ~= (frame._searchBox and frame._searchBox.editBox) then
            self:SetPropagateKeyboardInput(true)
            return
        end
        local ctrl = IsControlKeyDown and IsControlKeyDown()
        -- WoW's OnKeyDown reports slash as "/" (not "SLASH"); accept both for safety.
        if key == "/" or key == "SLASH" or (ctrl and key == "F") then
            -- Block propagation of this key *first* so it doesn't leak into
            -- any other frame.
            self:SetPropagateKeyboardInput(false)
            -- Defer focus to next frame. If we SetFocus synchronously, the
            -- editbox becomes the keyboard-focus frame for this same event
            -- and WoW routes the '/' character into it — the user sees a
            -- stray slash. Next-tick focus lets this keystroke finish with
            -- no focused editbox, then the user can type freely.
            C_Timer.After(0, function()
                GUI:FocusSearchBox()
            end)
            return
        end
        self:SetPropagateKeyboardInput(true)
    end)

    -- Welcome tile (top of sidebar)
    if ns.QUI_Options and type(ns.QUI_Options.RegisterFeatureTile) == "function" then
        ns.QUI_Options.RegisterFeatureTile(frame, {
            id = "welcome",
            icon = "*",
            name = "Welcome",
            subtitle = "Getting started · Tips · What's new",
            featureId = "welcomePage",
            noScroll = false,
        })
    end

    -- Feature tiles (guarded; each file in tiles/ attaches its own table to ns).
    if ns.QUI_GlobalTile then
        ns.QUI_GlobalTile.Register(frame)
    end
    if ns.QUI_UnitFramesTile then
        ns.QUI_UnitFramesTile.Register(frame)
    end
    if ns.QUI_GroupFramesTile then
        ns.QUI_GroupFramesTile.Register(frame)
    end
    if ns.QUI_ActionBarsTile then
        ns.QUI_ActionBarsTile.Register(frame)
    end
    if ns.QUI_CooldownManagerTile then
        ns.QUI_CooldownManagerTile.Register(frame)
    end
    if ns.QUI_ResourceBarsTile then
        ns.QUI_ResourceBarsTile.Register(frame)
    end
    if ns.QUI_MinimapTile then
        ns.QUI_MinimapTile.Register(frame)
    end
    if ns.QUI_AppearanceTile then
        ns.QUI_AppearanceTile.Register(frame)
    end
    if ns.QUI_ChatTooltipsTile then
        ns.QUI_ChatTooltipsTile.Register(frame)
    end
    if ns.QUI_GameplayTile then
        ns.QUI_GameplayTile.Register(frame)
    end
    if ns.QUI_QoLTile then
        ns.QUI_QoLTile.Register(frame)
    end

    -- Help & Welcome tile — bottom of sidebar, two sub-pages.
    if ns.QUI_HelpTile then
        ns.QUI_HelpTile.Register(frame)
    end

    -- Tools strip (bottom)
    self:AddToolsStripButton(frame, {
        id = "cdm_settings", icon = "+", label = "Blizz CDM",
        onClick = function()
            if CooldownViewerSettings then
                CooldownViewerSettings:SetShown(not CooldownViewerSettings:IsShown())
            end
        end,
    })
    self:AddToolsStripButton(frame, {
        id = "blizz_edit", icon = ">", label = "Blizz Edit",
        onClick = function()
            if InCombatLockdown() then return end
            if EditModeManagerFrame then
                ShowUIPanel(EditModeManagerFrame)
            end
        end,
    })

    self:SeedStaticSearchRoutesFromTiles(frame)

    -- Select Welcome immediately. It's cheap and the only page the user
    -- sees right after opening.
    GUI:SelectFeatureTile(frame, 1)

    return frame
end
