---------------------------------------------------------------------------
-- QUI Chat Module — Cleanup
-- Hide/show chat-frame buttons (social/channel chrome), QuickJoinToast
-- handling, and SetClampedToScreen toggling.
--
-- Extracted from chat.lua during Phase 0 refactor.
---------------------------------------------------------------------------

local ADDON_NAME, ns = ...
local Helpers = ns.Helpers

-- Defensive: assert _internals exists before reading state through it.
-- Set up by chat.lua, which loads first per chat.xml.
local I = assert(ns.QUI.Chat and ns.QUI.Chat._internals,
    "QUI Chat: cleanup.lua loaded before chat.lua. Check chat.xml — chat.lua must precede cleanup.lua.")

ns.QUI.Chat.Cleanup = ns.QUI.Chat.Cleanup or {}
local Cleanup = ns.QUI.Chat.Cleanup

---------------------------------------------------------------------------
-- Hide chat buttons (social/channel chrome)
---------------------------------------------------------------------------
-- Flag + hook + hide pattern used by all chat button frames.
-- Can't use Helpers.DeferredHideOnShow because the _chatButtonsHidden
-- guard allows toggling visibility back on at runtime.
local _chatButtonHooked = Helpers.CreateStateTable()
local function HideChatButtonOnShow(frame)
    I._chatButtonsHidden[frame] = true
    if not _chatButtonHooked[frame] then
        _chatButtonHooked[frame] = true
        hooksecurefunc(frame, "Show", function(self)
            C_Timer.After(0, function()
                if not I._chatButtonsHidden[self] then return end
                if self and self.Hide then self:Hide() end
            end)
        end)
    end
    frame:Hide()
end

local function HideChatButtons(chatFrame)
    local settings = I.GetSettings()
    if not settings or not settings.hideButtons then return end

    -- Hide button frame and prevent Blizzard from re-showing it
    if chatFrame.buttonFrame then
        HideChatButtonOnShow(chatFrame.buttonFrame)
        chatFrame.buttonFrame:SetWidth(0.1)  -- Collapse to minimal width
    end

    -- Also try global names for older frames
    local frameName = chatFrame:GetName()
    if frameName then
        local buttonFrame = _G[frameName .. "ButtonFrame"]
        if buttonFrame then
            HideChatButtonOnShow(buttonFrame)
            buttonFrame:SetWidth(0.1)
        end
    end

    -- Hide QuickJoinToastButton (global frame, not per-chat)
    if QuickJoinToastButton then
        HideChatButtonOnShow(QuickJoinToastButton)
    end

    -- Remove screen clamping so chat can move to edges
    if not InCombatLockdown() then
        chatFrame:SetClampedToScreen(false)
        chatFrame:SetClampRectInsets(0, 0, 0, 0)
    end
end

---------------------------------------------------------------------------
-- Show chat buttons (restore when disabled)
---------------------------------------------------------------------------
local function ShowChatButtons(chatFrame)
    if chatFrame.buttonFrame then
        I._chatButtonsHidden[chatFrame.buttonFrame] = false  -- Disable hide-on-show hook
        chatFrame.buttonFrame:Show()
        chatFrame.buttonFrame:SetWidth(29)  -- Restore default width
    end

    local frameName = chatFrame:GetName()
    if frameName then
        local buttonFrame = _G[frameName .. "ButtonFrame"]
        if buttonFrame then
            I._chatButtonsHidden[buttonFrame] = false  -- Disable hide-on-show hook
            buttonFrame:Show()
            buttonFrame:SetWidth(29)
        end
    end

    -- Show QuickJoinToastButton
    if QuickJoinToastButton then
        I._chatButtonsHidden[QuickJoinToastButton] = false  -- Disable hide-on-show hook
        QuickJoinToastButton:Show()
    end

    -- Restore screen clamping
    if not InCombatLockdown() then
        chatFrame:SetClampedToScreen(true)
    end
end

Cleanup.HideButtons = HideChatButtons
Cleanup.ShowButtons = ShowChatButtons
