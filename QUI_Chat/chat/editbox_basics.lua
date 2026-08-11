local ADDON_NAME, ns = ...
local Helpers = ns.Helpers

local I = assert(ns.QUI.Chat and ns.QUI.Chat._internals,
    "QUI Chat: editbox_basics.lua loaded before chat.lua. Check chat.xml — chat.lua must precede editbox_basics.lua.")

ns.QUI.Chat.EditBoxBasics = ns.QUI.Chat.EditBoxBasics or {}
local EditBoxBasics = ns.QUI.Chat.EditBoxBasics

local function GetAnchorFrame(chatFrame, frameID)
    if frameID == 1 then
        local settings = I.GetSettings and I.GetSettings()
        if I.IsChatEnabled and I.IsChatEnabled(settings) then
            local Display = ns.QUI.Chat.DisplayLayer
            if Display and Display.GetContainer then
                local active = Display.GetActiveWindow and Display.GetActiveWindow() or 1
                local c = Display.GetContainer(active)
                if not (c and c.IsShown and c:IsShown()) then
                    c = Display.GetContainer(1)
                end
                if c and c.IsShown and c:IsShown() then
                    return c
                end
            end
        end
    end
    return chatFrame
end

local EDITBOX_TEXTURES = {
    "FocusLeft", "FocusMid", "FocusRight",
    "Header", "HeaderSuffix", "LanguageHeader",
    "Prompt", "NewcomerHint",
}

local EDITBOX_CHILD_SUFFIXES = {
    "Left", "Mid", "Right",
    "FocusLeft", "FocusMid", "FocusRight",
}

local EDITBOX_BACKDROP_HEIGHT = 24
local EDITBOX_TEXT_PAD_X = 8

local function IsChatLayoutLockedDown()
    return (type(InCombatLockdown) == "function" and InCombatLockdown())
        or (I.IsChatMessagingLockedDown and I.IsChatMessagingLockedDown())
end

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

local function SetEditBoxVisualShown(editBox, shown)
    if editBox and editBox.SetAlpha then
        editBox:SetAlpha(shown and 1 or 0)
    end
end

local EDITBOX_HEADER_KEYS = { "header", "headerSuffix", "languageHeader", "prompt" }

local function ApplyEditBoxFont(editBox)
    if not (editBox and editBox.SetFontObject) then return end
    local fo = I.chatFontObject or _G.QUI_CustomChatFontObject or _G.ChatFontNormal
    if not fo then return end
    editBox:SetFontObject(fo)
    for _, key in ipairs(EDITBOX_HEADER_KEYS) do
        local fs = editBox[key]
        if fs and fs.SetFontObject then
            fs:SetFontObject(fo)
        end
    end
end

local function RestoreStockEditBoxFont(fontInstance)
    if not (fontInstance and fontInstance.SetFont) then return end
    local file, height, flags = "Fonts\\ARIALN.TTF", 14, ""
    local stock = _G.ChatFontNormal
    if stock and stock.GetFont then
        local ok, f, h, fl = pcall(stock.GetFont, stock)
        if ok and type(f) == "string" and f ~= "" and type(h) == "number" and h > 0 then
            file, height, flags = f, h, fl or ""
        end
    end
    pcall(fontInstance.SetFont, fontInstance, file, height, flags)
end

local RemoveEditBoxStyle

local function StyleEditBox(chatFrame)
    if not chatFrame or (chatFrame.IsForbidden and chatFrame:IsForbidden()) then return end

    local settings = I.GetSettings()
    if not (I.IsChatEnabled and I.IsChatEnabled(settings))
        or not settings or not settings.editBox or not settings.editBox.enabled then
        RemoveEditBoxStyle(chatFrame)
        return
    end

    local frameName = chatFrame:GetName()
    if not frameName then return end

    local frameID = tonumber(frameName:match("ChatFrame(%d+)"))

    local editBox = chatFrame.editBox or _G[frameName .. "EditBox"]
    if not editBox then return end

    if not I.editBoxState[editBox] then
        I.editBoxState[editBox] = {}
    end
    local ebState = I.editBoxState[editBox]
    EnsureGeometryHooks(chatFrame, editBox, ebState)

    if not ebState.styled then
        ebState.styled = true

        for _, suffix in ipairs(EDITBOX_CHILD_SUFFIXES) do
            local child = _G[frameName .. "EditBox" .. suffix]
            if child and child.Hide then
                child:Hide()
            end
        end

        if editBox.focusLeft then editBox.focusLeft:SetAlpha(0) end
        if editBox.focusMid then editBox.focusMid:SetAlpha(0) end
        if editBox.focusRight then editBox.focusRight:SetAlpha(0) end

        for _, name in ipairs(EDITBOX_TEXTURES) do
            local tex = editBox[name]
            if tex and tex.Hide then
                tex:Hide()
            end
        end

        local regions = {editBox:GetRegions()}
        for _, region in ipairs(regions) do
            if region and region.GetObjectType and region:GetObjectType() == "Texture" then
                region:SetAlpha(0)
            end
        end
    end

    ApplyEditBoxFont(editBox)

    if not I.editBoxBackdrops[chatFrame] then
        local backdrop = CreateFrame("Frame", nil, chatFrame)
        I.editBoxBackdrops[chatFrame] = backdrop
    end

    local backdrop = I.editBoxBackdrops[chatFrame]
    local positionTop = settings.editBox.positionTop

    local anchor = GetAnchorFrame(chatFrame, frameID)

    if backdrop:GetParent() ~= anchor then
        backdrop:SetParent(anchor)
    end

    backdrop:ClearAllPoints()
    if positionTop then
        backdrop:SetFrameLevel(chatFrame:GetFrameLevel() + 10)
        backdrop:SetPoint("BOTTOMLEFT", anchor, "TOPLEFT", 0, 0)
        backdrop:SetPoint("BOTTOMRIGHT", anchor, "TOPRIGHT", 0, 0)
        backdrop:SetHeight(EDITBOX_BACKDROP_HEIGHT)
        I.ApplySurfaceStyle(backdrop, {0, 0, 0, 1}, {0, 0, 0, 1}, 1)

        AnchorEditBoxToBackdrop(chatFrame, editBox, backdrop)

        ebState.backdropRef = backdrop

        if not ebState.topModeHooked then
            ebState.topModeHooked = true
            editBox:HookScript("OnEditFocusGained", function(self)
                local s = I.GetSettings()
                local state = I.editBoxState[self]
                if state then
                    state.hasFocus = true
                end
                if I.IsChatEnabled and I.IsChatEnabled(s)
                    and s.editBox and s.editBox.positionTop and state and state.backdropRef then
                    self:EnableMouse(true)
                    SetEditBoxVisualShown(self, true)
                    state.backdropRef:Show()
                end
            end)
            editBox:HookScript("OnEditFocusLost", function(self)
                local s = I.GetSettings()
                local state = I.editBoxState[self]
                if state then
                    state.hasFocus = false
                end
                if not (I.IsChatEnabled and I.IsChatEnabled(s)
                    and s.editBox and s.editBox.positionTop) then
                    return
                end
                if state and state.backdropRef then
                    state.backdropRef:Hide()
                end
                SetEditBoxVisualShown(self, false)
                self:EnableMouse(false)
            end)
        end

        backdrop:Hide()
        if ebState.hasFocus then
            backdrop:Show()
            editBox:EnableMouse(true)
            SetEditBoxVisualShown(editBox, true)
        else
            editBox:EnableMouse(false)
            SetEditBoxVisualShown(editBox, false)
        end
    else
        backdrop:SetFrameLevel(math.max(1, editBox:GetFrameLevel() - 1))
        backdrop:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -6)
        backdrop:SetPoint("TOPRIGHT", anchor, "BOTTOMRIGHT", 0, -6)
        backdrop:SetHeight(EDITBOX_BACKDROP_HEIGHT)

        local alpha = settings.editBox.bgAlpha or 0.25
        local bgColor = settings.editBox.bgColor or {0, 0, 0}
        I.ApplySurfaceStyle(backdrop, {bgColor[1], bgColor[2], bgColor[3], alpha}, {bgColor[1], bgColor[2], bgColor[3], alpha}, 1)

        AnchorEditBoxToBackdrop(chatFrame, editBox, backdrop)

        ebState.backdropRef = backdrop

        backdrop:Show()
        editBox:EnableMouse(true)
        SetEditBoxVisualShown(editBox, true)
    end
end

function RemoveEditBoxStyle(chatFrame)
    if not chatFrame then return end
    local frameName = chatFrame.GetName and chatFrame:GetName()
    local editBox = chatFrame.editBox or (frameName and _G[frameName .. "EditBox"])
    if not editBox then return end

    local ebState = I.editBoxState[editBox]
    if not (ebState and ebState.styled) then return end
    ebState.styled = false

    if I.editBoxBackdrops[chatFrame] then
        I.editBoxBackdrops[chatFrame]:Hide()
    end

    if editBox.EnableMouse then
        editBox:EnableMouse(true)
        SetEditBoxVisualShown(editBox, true)
    end

    if editBox.ClearAllPoints and editBox.SetPoint then
        editBox:ClearAllPoints()
        editBox:SetPoint("TOPLEFT", chatFrame, "BOTTOMLEFT", -5, -2)
        local scrollBar = chatFrame.ScrollBar
        if scrollBar then
            editBox:SetPoint("RIGHT", scrollBar, "RIGHT", 8, 0)
        else
            editBox:SetPoint("RIGHT", chatFrame, "RIGHT", 8, 0)
        end
    end

    RestoreStockEditBoxFont(editBox)
    for _, key in ipairs(EDITBOX_HEADER_KEYS) do
        RestoreStockEditBoxFont(editBox[key])
    end
    for _, suffix in ipairs(EDITBOX_CHILD_SUFFIXES) do
        local child = frameName and _G[frameName .. "EditBox" .. suffix]
        if child and child.Show then
            child:Show()
        end
    end
    if editBox.focusLeft then editBox.focusLeft:SetAlpha(1) end
    if editBox.focusMid then editBox.focusMid:SetAlpha(1) end
    if editBox.focusRight then editBox.focusRight:SetAlpha(1) end
    for _, name in ipairs(EDITBOX_TEXTURES) do
        local tex = editBox[name]
        if tex and tex.Show then
            tex:Show()
        end
    end
    if editBox.GetRegions then
        local regions = { editBox:GetRegions() }
        for _, region in ipairs(regions) do
            if region and region.GetObjectType and region:GetObjectType() == "Texture" then
                region:SetAlpha(1)
            end
        end
    end
end

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
    if IsChatLayoutLockedDown() then return end

    local tabIndex = tonumber(GetDefaultTabIndex(settings))
    if not tabIndex then return end

    local TabUI = ns.QUI.Chat.TabUI
    if TabUI and TabUI.ActivateFrameID then
        TabUI.ActivateFrameID(1, tabIndex)
    end
end

local defaultTabFrame = CreateFrame("Frame")
defaultTabFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
defaultTabFrame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
defaultTabFrame:SetScript("OnEvent", function(self, event, arg1, arg2)
    local settings = I.GetSettings()
    if not (I.IsChatEnabled and I.IsChatEnabled(settings)) then return end

    if event == "PLAYER_ENTERING_WORLD" then
        local isInitialLogin, isReloadingUi = arg1, arg2
        if not (isInitialLogin or isReloadingUi) then return end
        C_Timer.After(0.5, function() SelectDefaultTab(settings) end)
    elseif event == "PLAYER_SPECIALIZATION_CHANGED" then
        if not settings.defaultTabPerSpec then return end
        C_Timer.After(0.3, function() SelectDefaultTab(settings) end)
    end
end)

EditBoxBasics.StyleEditBox        = StyleEditBox
EditBoxBasics.RemoveEditBoxStyle  = RemoveEditBoxStyle
EditBoxBasics.ApplyDefaultTab     = SelectDefaultTab
EditBoxBasics.MatchChatFrameWidth = MatchChatFrameWidth
EditBoxBasics._GetAnchorFrame     = GetAnchorFrame
