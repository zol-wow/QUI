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

-- ChatFrame1's editbox follows the ACTIVE custom window: the backdrop (and
-- therefore the editbox, which anchors to the backdrop) attaches to the
-- last-active QUI window. Window 1 is the fallback when the active window's
-- container is missing/hidden. Only frame 1 — other Blizzard frames keep
-- their own editboxes untouched.
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

-- Edit box textures to remove for clean styling
local EDITBOX_TEXTURES = {
    "FocusLeft", "FocusMid", "FocusRight",
    "Header", "HeaderSuffix", "LanguageHeader",
    "Prompt", "NewcomerHint",
}

-- Child FRAMES (not textures) hidden by StyleEditBox and re-shown by
-- RemoveEditBoxStyle; the two must stay symmetric, so keep one list.
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

-- The channel prefix shown to the LEFT of the input ("Guild", "/w Name", …) is
-- a set of child fontstrings, not the editbox's own text — each inherits
-- ChatFontNormal from the template, so the editbox SetFontObject doesn't reach
-- them. Font them explicitly (Blizzard re-sets only their COLOR/TEXT per channel,
-- never the font, so this persists). parentKeys per ChatFrameEditBox.xml.
local EDITBOX_HEADER_KEYS = { "header", "headerSuffix", "languageHeader", "prompt" }

-- The input editbox follows the QUI chat font: it adopts the SAME font object
-- the message frame uses, so typed text matches the rendered messages exactly —
-- path, size and outline are resolved in one place (display_layer.ApplyTheme)
-- and shared, never duplicated here. ApplyTheme publishes that object on the
-- shared internals (I.chatFontObject) during Display.Refresh, which runs before
-- StyleEditBox on every refresh path. In-game that object is a per-script font
-- FAMILY (CJK fallback), so the QUI_CustomChatFontObject global — built only on
-- the family-less degrade path — usually never exists; it is kept as a second
-- choice, with stock ChatFontNormal last (no font path configured, or pre-build).
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

-- Restore a chat-input FontInstance (the editbox or a channel-prefix child) to
-- the stock chat font.
--
-- We DELIBERATELY do not re-apply a captured GetFontObject() snapshot. The
-- editbox's pre-QUI font object — handed back by GetFontObject() and reported
-- "Font <UnknownFile:0>" (a runtime object with no XML source) — RESOLVES to a
-- real file (ARIALN) yet its font-object derivation chain is self-referential.
-- Re-applying it via SetFontObject makes the engine walk that cycle until the C
-- stack overflows (ERROR #132, uncatchable by pcall, and indistinguishable by
-- any property test since GetFont returns a valid path). SetFont(file,height,
-- flags) writes the physical font with NO object-derivation link, so the cycle
-- is structurally impossible — it never reaches SetFontObject's graph walk.
-- Values come from ChatFontNormal (what the ChatFrameEditBox template inherits);
-- a guarded fallback covers a garbage GetFont (height can come back negative,
-- which makes SetFont throw "Invalid fontHeight").
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

---------------------------------------------------------------------------
-- Style edit box (chat input area)
---------------------------------------------------------------------------
local RemoveEditBoxStyle -- forward-declared: the settings bails below clean up

local function StyleEditBox(chatFrame)
    if not chatFrame or (chatFrame.IsForbidden and chatFrame:IsForbidden()) then return end

    -- Settings gate lives HERE only — callers (display_fallback.Apply) never
    -- duplicate it. A gated-off call removes prior styling so flipping the
    -- editBox option off works live, without a /reload.
    local settings = I.GetSettings()
    if not (I.IsChatEnabled and I.IsChatEnabled(settings))
        or not settings or not settings.editBox or not settings.editBox.enabled then
        RemoveEditBoxStyle(chatFrame)
        return
    end

    local frameName = chatFrame:GetName()
    if not frameName then return end

    -- Derive numeric frameID so GetAnchorFrame can gate on frame 1 only.
    local frameID = tonumber(frameName:match("ChatFrame(%d+)"))

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

        -- The stock font is restored via RestoreStockEditBoxFont (SetFont with
        -- ChatFontNormal's values) on the disable flip — we do NOT snapshot
        -- editBox:GetFontObject() here: that object can be self-referential and
        -- re-applying it stack-overflows the client (see RemoveEditBoxStyle).

        -- Hide child FRAMES by global name (these are frames, not textures)
        for _, suffix in ipairs(EDITBOX_CHILD_SUFFIXES) do
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

    -- Follow the QUI chat font (re-applied every call so live font changes land).
    ApplyEditBoxFont(editBox)

    -- Create glass backdrop for edit box (once per chatFrame, stored in local table)
    -- Parent to chatFrame (not editBox) so we can control visibility independently
    if not I.editBoxBackdrops[chatFrame] then
        local backdrop = CreateFrame("Frame", nil, chatFrame)
        I.editBoxBackdrops[chatFrame] = backdrop
    end

    local backdrop = I.editBoxBackdrops[chatFrame]
    local positionTop = settings.editBox.positionTop

    -- When the custom display is active, frame 1's backdrop anchors to the
    -- custom container instead of the Blizzard frame so the editbox sits
    -- visually below the custom display. All other frames use chatFrame.
    local anchor = GetAnchorFrame(chatFrame, frameID)

    -- The backdrop must not follow ChatFrame1 into the suppression anchor —
    -- keep it parented where it's anchored (QUI-owned frame; unrestricted).
    if backdrop:GetParent() ~= anchor then
        backdrop:SetParent(anchor)
    end

    -- Position backdrop and editbox based on setting
    backdrop:ClearAllPoints()
    if positionTop then
        -- Position at TOP, overlaying tabs with opaque black background
        backdrop:SetFrameLevel(chatFrame:GetFrameLevel() + 10)
        backdrop:SetPoint("BOTTOMLEFT", anchor, "TOPLEFT", 0, 0)
        backdrop:SetPoint("BOTTOMRIGHT", anchor, "TOPRIGHT", 0, 0)
        backdrop:SetHeight(EDITBOX_BACKDROP_HEIGHT)
        I.ApplySurfaceStyle(backdrop, {0, 0, 0, 1}, {0, 0, 0, 1}, 1)

        AnchorEditBoxToBackdrop(chatFrame, editBox, backdrop)

        -- Store backdrop reference in local state table for hooks to access
        ebState.backdropRef = backdrop

        -- For top position: Only show backdrop when editbox has focus (user is typing).
        -- Mouse is also disabled while unfocused so clicks fall through to the chat
        -- tabs that occupy the same strip — Blizzard sometimes leaves the editBox
        -- shown (chatStyle="im", lockShow, sticky channels) and an invisible-but-
        -- mouse-enabled editBox would otherwise eat tab clicks.
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

        -- Start hidden - will show when user focuses editbox (presses Enter)
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
        -- Default: Position at BOTTOM
        backdrop:SetFrameLevel(math.max(1, editBox:GetFrameLevel() - 1))
        backdrop:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -6)
        backdrop:SetPoint("TOPRIGHT", anchor, "BOTTOMRIGHT", 0, -6)
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
        -- Restore mouse on the editBox in case top mode previously disabled it.
        editBox:EnableMouse(true)
        SetEditBoxVisualShown(editBox, true)
    end
end

---------------------------------------------------------------------------
-- Remove edit box styling (restore when disabled)
---------------------------------------------------------------------------
function RemoveEditBoxStyle(chatFrame)
    if not chatFrame then return end
    local frameName = chatFrame.GetName and chatFrame:GetName()
    local editBox = chatFrame.editBox or (frameName and _G[frameName .. "EditBox"])
    if not editBox then return end

    -- Nothing to undo if QUI never styled this editbox: bail before touching the
    -- backdrop, mouse, alpha, anchors, or font so a foreign chat addon's editbox
    -- is left exactly as it was. Single gate (vs. per-block guards) keeps "did we
    -- style this?" in one place; clearing the latch makes a repeat teardown a
    -- no-op too.
    local ebState = I.editBoxState[editBox]
    if not (ebState and ebState.styled) then return end
    ebState.styled = false

    -- Hide the glass backdrop (only ever created by StyleEditBox).
    if I.editBoxBackdrops[chatFrame] then
        I.editBoxBackdrops[chatFrame]:Hide()
    end

    -- Restore mouse + visibility on the editBox — top mode disables the mouse
    -- while unfocused so clicks fall through to the tabs, and that state must not
    -- survive teardown.
    if editBox.EnableMouse then
        editBox:EnableMouse(true)
        SetEditBoxVisualShown(editBox, true)
    end

    -- Stock restore: the live disable flip must hand back a fully stock editbox
    -- (no /reload). Inverse of StyleEditBox's strip + reanchor. Anchors per
    -- FloatingChatFrame.xml's ChatFrameEditBoxTemplate use:
    -- TOPLEFT -> chatFrame BOTTOMLEFT (-5,-2), RIGHT -> ScrollBar RIGHT (8,0).
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

    -- Hand the QUI chat font back to the stock chat font, on the input AND each
    -- channel-prefix child. RestoreStockEditBoxFont uses SetFont (never
    -- SetFontObject) so a captured self-referential font object can't
    -- stack-overflow the client — see its comment.
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
    if IsChatLayoutLockedDown() then return end

    local tabIndex = tonumber(GetDefaultTabIndex(settings))
    if not tabIndex then return end

    local TabUI = ns.QUI.Chat.TabUI
    if TabUI and TabUI.ActivateFrameID then
        TabUI.ActivateFrameID(1, tabIndex) -- default tab applies to the primary window
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

---------------------------------------------------------------------------
-- Public interface
---------------------------------------------------------------------------
EditBoxBasics.StyleEditBox        = StyleEditBox
EditBoxBasics.RemoveEditBoxStyle  = RemoveEditBoxStyle
EditBoxBasics.ApplyDefaultTab     = SelectDefaultTab
EditBoxBasics.MatchChatFrameWidth = MatchChatFrameWidth
EditBoxBasics._GetAnchorFrame     = GetAnchorFrame
