---------------------------------------------------------------------------
-- QUI Chat Module — Edit Box Basics
-- Glass styling for the chat edit box (backdrop, top/bottom position,
-- texture stripping), and default-tab selection logic on login / spec
-- change. Owns visual + position concerns of the input area.
--
-- Persistent Up/Down arrow command history is in editbox_history.lua
-- (Phase C; per-character SV at db.char.chat.editboxHistory.entries).
--
-- Extracted from chat.lua during Phase 0 refactor. No behavior change.
---------------------------------------------------------------------------

local ADDON_NAME, ns = ...
local Helpers = ns.Helpers

-- Defensive: assert _internals exists before reading state through it.
-- Set up by chat.lua, which loads first per chat.xml.
local I = assert(ns.QUI.Chat and ns.QUI.Chat._internals,
    "QUI Chat: editbox_basics.lua loaded before chat.lua. Check chat.xml — chat.lua must precede editbox_basics.lua.")

ns.QUI.Chat.EditBoxBasics = ns.QUI.Chat.EditBoxBasics or {}
local EditBoxBasics = ns.QUI.Chat.EditBoxBasics

-- Edit box textures to remove for clean styling
local EDITBOX_TEXTURES = {
    "FocusLeft", "FocusMid", "FocusRight",
    "Header", "HeaderSuffix", "LanguageHeader",
    "Prompt", "NewcomerHint",
}

local EDITBOX_BACKDROP_HEIGHT = 24
local EDITBOX_TEXT_PAD_X = 8

local function MatchChatFrameWidth(chatFrame, editBox, backdrop)
    if not chatFrame or not editBox or not backdrop or not chatFrame.GetWidth then return end

    local width = chatFrame:GetWidth()
    if Helpers.IsSecretValue and Helpers.IsSecretValue(width) then
        if backdrop.SetWidth then backdrop:SetWidth(width) end
        if editBox.SetWidth then editBox:SetWidth(width) end
        return
    end

    width = tonumber(width)
    if not width or width <= 0 then return end
    if backdrop.SetWidth then backdrop:SetWidth(width) end
    if editBox.SetWidth then editBox:SetWidth(width) end
end

local function QueueStyleEditBox(chatFrame)
    if not chatFrame then return end
    local apply = function()
        if EditBoxBasics.StyleEditBox then
            EditBoxBasics.StyleEditBox(chatFrame)
        end
    end
    if C_Timer and C_Timer.After then
        C_Timer.After(0, apply)
    else
        apply()
    end
end

local function EnsureGeometryHooks(chatFrame, editBox, state)
    if not chatFrame or not editBox or not state or state.geometryHooked then return end
    state.geometryHooked = true
    if chatFrame.HookScript then
        chatFrame:HookScript("OnSizeChanged", function(frame)
            QueueStyleEditBox(frame)
        end)
    end
    if editBox.HookScript then
        editBox:HookScript("OnShow", function()
            QueueStyleEditBox(chatFrame)
        end)
    end
end

local function AnchorEditBoxToBackdrop(chatFrame, editBox, backdrop)
    editBox:ClearAllPoints()
    editBox:SetPoint("LEFT", backdrop, "LEFT", 0, 0)
    editBox:SetPoint("RIGHT", backdrop, "RIGHT", 0, 0)
    editBox:SetPoint("CENTER", backdrop, "CENTER", 0, 0)
    MatchChatFrameWidth(chatFrame, editBox, backdrop)
    if editBox.SetTextInsets then
        editBox:SetTextInsets(EDITBOX_TEXT_PAD_X, EDITBOX_TEXT_PAD_X, 0, 0)
    end
end

---------------------------------------------------------------------------
-- Style edit box (chat input area)
---------------------------------------------------------------------------
local function StyleEditBox(chatFrame)
    if not chatFrame or (chatFrame.IsForbidden and chatFrame:IsForbidden()) then return end

    local settings = I.GetSettings()
    if not settings or not settings.editBox or not settings.editBox.enabled then return end
    if not settings.glass or not settings.glass.enabled then return end

    local frameName = chatFrame:GetName()
    if not frameName then return end

    -- Find edit box
    local editBox = chatFrame.editBox or _G[frameName .. "EditBox"]
    if not editBox then return end

    -- Ensure editBox state table exists
    if not I.editBoxState[editBox] then
        I.editBoxState[editBox] = {}
    end
    local ebState = I.editBoxState[editBox]
    EnsureGeometryHooks(chatFrame, editBox, ebState)

    -- Only strip Blizzard textures once
    if not ebState.styled then
        ebState.styled = true

        -- Hide child FRAMES by global name (these are frames, not textures)
        local childSuffixes = {
            "Left", "Mid", "Right",
            "FocusLeft", "FocusMid", "FocusRight",
        }
        for _, suffix in ipairs(childSuffixes) do
            local child = _G[frameName .. "EditBox" .. suffix]
            if child and child.Hide then
                child:Hide()
            end
        end

        -- Alpha out focus textures via editBox properties
        if editBox.focusLeft then editBox.focusLeft:SetAlpha(0) end
        if editBox.focusMid then editBox.focusMid:SetAlpha(0) end
        if editBox.focusRight then editBox.focusRight:SetAlpha(0) end

        -- Remove Blizzard textures by property name
        for _, name in ipairs(EDITBOX_TEXTURES) do
            local tex = editBox[name]
            if tex and tex.Hide then
                tex:Hide()
            end
        end

        -- Hide all texture regions on the editbox itself
        local regions = {editBox:GetRegions()}
        for _, region in ipairs(regions) do
            if region and region.GetObjectType and region:GetObjectType() == "Texture" then
                region:SetAlpha(0)
            end
        end
    end

    -- Create glass backdrop for edit box (once per chatFrame, stored in local table)
    -- Parent to chatFrame (not editBox) so we can control visibility independently
    if not I.editBoxBackdrops[chatFrame] then
        local backdrop = CreateFrame("Frame", nil, chatFrame)
        I.editBoxBackdrops[chatFrame] = backdrop
    end

    local backdrop = I.editBoxBackdrops[chatFrame]
    local positionTop = settings.editBox.positionTop

    -- Position backdrop and editbox based on setting
    backdrop:ClearAllPoints()
    if positionTop then
        -- Position at TOP, overlaying tabs with opaque black background
        backdrop:SetFrameLevel(chatFrame:GetFrameLevel() + 10)
        backdrop:SetPoint("BOTTOMLEFT", chatFrame, "TOPLEFT", 0, 0)
        backdrop:SetPoint("BOTTOMRIGHT", chatFrame, "TOPRIGHT", 0, 0)
        backdrop:SetHeight(EDITBOX_BACKDROP_HEIGHT)
        I.ApplySurfaceStyle(backdrop, {0, 0, 0, 1}, {0, 0, 0, 1}, 1)

        AnchorEditBoxToBackdrop(chatFrame, editBox, backdrop)

        -- Store backdrop reference in local state table for hooks to access
        ebState.backdropRef = backdrop

        -- For top position: Only show backdrop when editbox has focus (user is typing)
        if not ebState.topModeHooked then
            ebState.topModeHooked = true
            editBox:HookScript("OnEditFocusGained", function(self)
                local s = I.GetSettings()
                local state = I.editBoxState[self]
                if s and s.editBox and s.editBox.positionTop and state and state.backdropRef then
                    state.backdropRef:Show()
                end
            end)
            editBox:HookScript("OnEditFocusLost", function(self)
                local state = I.editBoxState[self]
                if state and state.backdropRef then
                    state.backdropRef:Hide()
                end
            end)
        end

        -- Start hidden - will show when user focuses editbox (presses Enter)
        backdrop:Hide()
        if editBox:HasFocus() then
            backdrop:Show()
        end
    else
        -- Default: Position at BOTTOM
        backdrop:SetFrameLevel(math.max(1, editBox:GetFrameLevel() - 1))
        backdrop:SetPoint("TOPLEFT", chatFrame, "BOTTOMLEFT", 0, -6)
        backdrop:SetPoint("TOPRIGHT", chatFrame, "BOTTOMRIGHT", 0, -6)
        backdrop:SetHeight(EDITBOX_BACKDROP_HEIGHT)

        -- Apply user-configured opacity and color.
        local alpha = settings.editBox.bgAlpha or 0.25
        local bgColor = settings.editBox.bgColor or {0, 0, 0}
        I.ApplySurfaceStyle(backdrop, {bgColor[1], bgColor[2], bgColor[3], alpha}, {bgColor[1], bgColor[2], bgColor[3], alpha}, 1)

        AnchorEditBoxToBackdrop(chatFrame, editBox, backdrop)

        -- Store backdrop reference in local state table for consistency
        ebState.backdropRef = backdrop

        -- Bottom position: always show backdrop (standard behavior)
        backdrop:Show()
    end
end

---------------------------------------------------------------------------
-- Remove edit box styling (restore when disabled)
---------------------------------------------------------------------------
local function RemoveEditBoxStyle(chatFrame)
    -- Hide backdrop stored in local table
    if I.editBoxBackdrops[chatFrame] then
        I.editBoxBackdrops[chatFrame]:Hide()
    end
end

---------------------------------------------------------------------------
-- Default Tab Selection on Login/Reload/Spec Change
---------------------------------------------------------------------------
local function GetDefaultTabIndex(settings)
    if settings.defaultTabPerSpec then
        local specID = Helpers.GetCurrentSpecID()
        if specID and settings.defaultTabBySpec then
            return settings.defaultTabBySpec[specID]
        end
        return nil
    end
    return settings.defaultTab
end

local function SelectDefaultTab(settings)
    local tabIndex = GetDefaultTabIndex(settings)
    if not tabIndex or tabIndex <= 1 then return end

    local chatFrame = _G["ChatFrame" .. tabIndex]
    if not chatFrame then return end

    local tab = _G["ChatFrame" .. tabIndex .. "Tab"]
    if not tab then return end

    -- Verify the tab exists and has a name (not a deleted/empty slot)
    local name = GetChatWindowInfo(tabIndex)
    if not name or name == "" then return end

    FCF_Tab_OnClick(tab, "LeftButton")
end

local defaultTabFrame = CreateFrame("Frame")
defaultTabFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
defaultTabFrame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
defaultTabFrame:SetScript("OnEvent", function(self, event, arg1, arg2)
    local settings = I.GetSettings()
    if not settings or not settings.enabled then return end

    if event == "PLAYER_ENTERING_WORLD" then
        local isInitialLogin, isReloadingUi = arg1, arg2
        if not (isInitialLogin or isReloadingUi) then return end
        C_Timer.After(0.5, function() SelectDefaultTab(settings) end)
    elseif event == "PLAYER_SPECIALIZATION_CHANGED" then
        if not settings.defaultTabPerSpec then return end
        C_Timer.After(0.3, function() SelectDefaultTab(settings) end)
    end
end)

---------------------------------------------------------------------------
-- Public interface
---------------------------------------------------------------------------
EditBoxBasics.StyleEditBox       = StyleEditBox
EditBoxBasics.RemoveEditBoxStyle = RemoveEditBoxStyle
EditBoxBasics.ApplyDefaultTab    = SelectDefaultTab
EditBoxBasics.MatchChatFrameWidth = MatchChatFrameWidth
