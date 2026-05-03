---------------------------------------------------------------------------
-- QUI Chat Module — Skinning
-- Glass backdrops, font outline, tab styling, message padding, and
-- message fade. Leaf-level skinning operations consumed by chat.lua's
-- SkinChatFrame orchestrator.
--
-- Extracted from chat.lua during Phase 0 refactor.
---------------------------------------------------------------------------

local ADDON_NAME, ns = ...
local UIKit = ns.UIKit

-- Defensive: assert _internals exists before reading state through it.
-- Set up by chat.lua, which loads first per chat.xml.
local I = assert(ns.QUI.Chat and ns.QUI.Chat._internals,
    "QUI Chat: skinning.lua loaded before chat.lua. Check chat.xml — chat.lua must precede skinning.lua.")

ns.QUI.Chat.Skinning = ns.QUI.Chat.Skinning or {}
local Skinning = ns.QUI.Chat.Skinning

local pairs, ipairs = pairs, ipairs

-- Local alias to the shared "already skinned" tracker promoted to _internals.
-- Regular (non-weak) table — must persist for the lifetime of the addon.
local skinnedFrames = I.skinnedFrames
local scrollButtonState = setmetatable({}, { __mode = "k" })
local minimalScrollBarState = setmetatable({}, { __mode = "k" })
local minimalThumbState = setmetatable({}, { __mode = "k" })
local scrollBarHookState = setmetatable({}, { __mode = "k" })

local CHAT_SCROLLBAR_HIT_WIDTH = 18
local CHAT_SCROLLBAR_TRACK_WIDTH = 10
local CHAT_SCROLLBAR_THUMB_WIDTH = 12
local CHAT_SCROLL_TO_BOTTOM_SIZE = 18
local CHAT_SCROLLBAR_INSET_X = 2
local CHAT_SCROLLBAR_INSET_TOP = 4
local CHAT_SCROLLBAR_INSET_BOTTOM = 4
local CHAT_SCROLLBAR_BUTTON_GAP = 2
local CHAT_SCROLLBAR_TRACK_ALPHA = 0
local CHAT_SCROLLBAR_THUMB_ALPHA = 1

---------------------------------------------------------------------------
-- Blizzard texture names to strip for glass effect
---------------------------------------------------------------------------
local CHAT_FRAME_TEXTURES = {
    "Background",
    "TopLeftTexture", "TopRightTexture",
    "BottomLeftTexture", "BottomRightTexture",
    "TopTexture", "BottomTexture",
    "LeftTexture", "RightTexture",
}

local HideTexture

---------------------------------------------------------------------------
-- Strip Blizzard default textures from chat frame
---------------------------------------------------------------------------
local function StripDefaultTextures(chatFrame)
    local frameName = chatFrame:GetName()
    if not frameName then return end

    for _, textureName in ipairs(CHAT_FRAME_TEXTURES) do
        local texture = _G[frameName .. textureName]
        if texture and texture.SetTexture then
            texture:SetTexture(0)
            texture:SetAlpha(0)
        end
    end
end

local function StripChatFrameBackground(chatFrame)
    if not chatFrame then return end

    if chatFrame.Background then
        HideTexture(chatFrame.Background)
    end

    local frameName = chatFrame.GetName and chatFrame:GetName()
    if not frameName then return end

    HideTexture(_G[frameName .. "Background"])
    HideTexture(_G[frameName .. "ButtonFrameBackground"])
end

---------------------------------------------------------------------------
-- Create glass-style backdrop for chat frame
---------------------------------------------------------------------------
local function CreateGlassBackdrop(chatFrame)
    local settings = I.GetSettings()
    if not settings or not settings.glass or not settings.glass.enabled then return end

    -- Create or update backdrop (stored in shared weak table, NOT on frame).
    -- Horizontal insets are 0 so the backdrop's left edge aligns with the
    -- first tab in the dock (Blizzard anchors ChatFrame1Tab at the chat
    -- frame's BOTTOMLEFT with x=0). Previously the backdrop overhung 8px
    -- on each side, which made the first tab look indented from the
    -- visible chat-window edge. Vertical insets are kept asymmetric so the
    -- backdrop still extends slightly above the message area and 8px below
    -- the input box.
    if not I.chatBackdrops[chatFrame] then
        local backdrop = CreateFrame("Frame", nil, chatFrame)
        backdrop:SetFrameLevel(math.max(1, chatFrame:GetFrameLevel() - 1))
        I.chatBackdrops[chatFrame] = backdrop
    end

    local backdrop = I.chatBackdrops[chatFrame]
    backdrop:ClearAllPoints()
    backdrop:SetPoint("TOPLEFT", 0, 2)
    backdrop:SetPoint("BOTTOMRIGHT", 0, -8)

    local bgColor, borderColor = I.GetChatSurfaceColors(settings)
    I.ApplySurfaceStyle(backdrop, bgColor, borderColor, 1)
    backdrop:Show()
end

---------------------------------------------------------------------------
-- Remove glass backdrop (when disabled)
---------------------------------------------------------------------------
local function RemoveGlassBackdrop(chatFrame)
    if I.chatBackdrops[chatFrame] then
        I.chatBackdrops[chatFrame]:Hide()
    end
end

---------------------------------------------------------------------------
-- Force font outline on chat text (always enabled)
---------------------------------------------------------------------------
local function StyleFontStrings(chatFrame)
    -- Style the main font string container
    local fontFile, fontSize, fontFlags = chatFrame:GetFont()
    if fontFile and fontSize then
        -- Add OUTLINE if not already present
        local newFlags = fontFlags or ""
        if not newFlags:find("OUTLINE") then
            newFlags = "OUTLINE"
        end
        chatFrame:SetFont(fontFile, fontSize, newFlags)
        chatFrame:SetShadowOffset(0, 0)
    end
end

---------------------------------------------------------------------------
-- Message Fade System (uses native ScrollingMessageFrame API)
---------------------------------------------------------------------------
local function SetupMessageFade(chatFrame)
    local settings = I.GetSettings()
    if not settings or not settings.fade then return end

    if settings.fade.enabled then
        chatFrame:SetFading(true)
        chatFrame:SetTimeVisible(settings.fade.delay or 60)
    else
        chatFrame:SetFading(false)
    end
end

---------------------------------------------------------------------------
-- Scrollbar styling
---------------------------------------------------------------------------
local function ResolveTheme()
    if I.GetThemeColors then
        return I.GetThemeColors()
    end
    local accent = I.GetAccent and I.GetAccent() or I.QUI_COLORS.accent
    return {
        textDim = I.QUI_COLORS.textDim,
        accent = accent,
        accentHover = accent,
    }
end

local function GetScrollBar(chatFrame)
    if not chatFrame then return nil end
    if chatFrame.ScrollBar then return chatFrame.ScrollBar end
    local frameName = chatFrame.GetName and chatFrame:GetName()
    if frameName then
        return _G[frameName .. "ScrollBar"]
    end
    return nil
end

local function HideDefaultTextures(frame)
    if not frame or not frame.GetRegions then return end
    for _, region in ipairs({frame:GetRegions()}) do
        if region and region.GetObjectType and region:GetObjectType() == "Texture" and region.SetAlpha then
            region:SetAlpha(0)
        end
    end
end

HideTexture = function(texture)
    if not texture then return end
    if texture.SetAlpha then texture:SetAlpha(0) end
    if texture.Hide then texture:Hide() end
end

local function HideTextureKeys(frame, keys)
    if not frame then return end
    for _, key in ipairs(keys) do
        HideTexture(frame[key])
    end
end

local MINIMAL_SCROLLBAR_PIECES = { "Begin", "Middle", "End" }

local function HideMinimalTrackArtwork(scrollBar)
    if not scrollBar or not scrollBar.Track then return end
    HideTextureKeys(scrollBar.Track, MINIMAL_SCROLLBAR_PIECES)
end

local function HideMinimalThumbArtwork(thumb)
    HideTextureKeys(thumb, MINIMAL_SCROLLBAR_PIECES)
end

local function HideScrollToBottomArtwork(button)
    if not button then return end

    if button.Flash then
        if UIFrameFlashStop then UIFrameFlashStop(button.Flash) end
        HideTexture(button.Flash)
    end
    if button.GetNormalTexture then HideTexture(button:GetNormalTexture()) end
    if button.GetPushedTexture then HideTexture(button:GetPushedTexture()) end
    if button.GetHighlightTexture then HideTexture(button:GetHighlightTexture()) end
    if button.GetDisabledTexture then HideTexture(button:GetDisabledTexture()) end
end

local function HideScrollButton(button)
    if not button then return end
    button:SetAlpha(0)
    if button.SetSize then
        button:SetSize(1, 1)
    end
    HideDefaultTextures(button)
end

local function KeepFrameVisible(frame)
    if not frame then return end
    if UIFrameFadeRemoveFrame then
        UIFrameFadeRemoveFrame(frame)
    end
    if frame.SetAlpha then frame:SetAlpha(1) end
end

local function GetMinimalThumb(scrollBar)
    if not scrollBar then return nil end

    if scrollBar.GetThumb then
        local ok, thumb = pcall(scrollBar.GetThumb, scrollBar)
        if ok and thumb then return thumb end
    end

    if scrollBar.Track and scrollBar.Track.Thumb then
        return scrollBar.Track.Thumb
    end

    return scrollBar.Thumb
end

local function IsMinimalScrollBar(scrollBar)
    local thumb = GetMinimalThumb(scrollBar)
    return scrollBar
        and scrollBar.Track
        and thumb
        and thumb.GetParent
        and thumb:GetParent() == scrollBar.Track
end

local function LayoutScrollToBottomButton(chatFrame, button)
    if not chatFrame or not button or not button.ClearAllPoints then return end

    button:ClearAllPoints()
    button:SetPoint("BOTTOMRIGHT", chatFrame, "BOTTOMRIGHT", -CHAT_SCROLLBAR_INSET_X, CHAT_SCROLLBAR_INSET_BOTTOM)
end

local function LayoutChatScrollBar(chatFrame, scrollBar, bottomButton)
    if not chatFrame or not scrollBar or not scrollBar.ClearAllPoints then return end

    scrollBar:ClearAllPoints()
    scrollBar:SetPoint("TOPRIGHT", chatFrame, "TOPRIGHT", -CHAT_SCROLLBAR_INSET_X, -CHAT_SCROLLBAR_INSET_TOP)
    if bottomButton and bottomButton.IsShown and bottomButton:IsShown() then
        scrollBar:SetPoint("BOTTOMRIGHT", bottomButton, "TOPRIGHT", 0, CHAT_SCROLLBAR_BUTTON_GAP)
    else
        scrollBar:SetPoint("BOTTOMRIGHT", chatFrame, "BOTTOMRIGHT", -CHAT_SCROLLBAR_INSET_X, CHAT_SCROLLBAR_INSET_BOTTOM)
    end
end

local function StyleMinimalTrack(scrollBar, theme)
    if not IsMinimalScrollBar(scrollBar) then return end

    HideMinimalTrackArtwork(scrollBar)

    local state = minimalScrollBarState[scrollBar]
    if not state then
        state = {}
        minimalScrollBarState[scrollBar] = state

        state.track = scrollBar.Track:CreateTexture(nil, "BACKGROUND")
        state.track:SetTexture("Interface\\Buttons\\WHITE8x8")
        if UIKit and UIKit.DisablePixelSnap then
            UIKit.DisablePixelSnap(state.track)
        end
    end

    if scrollBar.SetWidth then scrollBar:SetWidth(CHAT_SCROLLBAR_HIT_WIDTH) end
    if scrollBar.Track.SetWidth then scrollBar.Track:SetWidth(CHAT_SCROLLBAR_HIT_WIDTH) end
    scrollBar.Track:ClearAllPoints()
    scrollBar.Track:SetPoint("TOP", scrollBar, "TOP", 0, -2)
    scrollBar.Track:SetPoint("BOTTOM", scrollBar, "BOTTOM", 0, 2)

    state.track:ClearAllPoints()
    state.track:SetPoint("TOP", scrollBar.Track, "TOP", 0, 0)
    state.track:SetPoint("BOTTOM", scrollBar.Track, "BOTTOM", 0, 0)
    state.track:SetWidth(CHAT_SCROLLBAR_TRACK_WIDTH)

    local trackColor = theme.border or theme.textDim or {1, 1, 1, 1}
    state.track:SetColorTexture(trackColor[1], trackColor[2], trackColor[3], CHAT_SCROLLBAR_TRACK_ALPHA)
    state.track:SetAlpha(1)
    state.track:Show()
    HideMinimalTrackArtwork(scrollBar)
end

local function PaintMinimalThumb(thumb, alpha, theme)
    if not thumb then return end

    theme = theme or ResolveTheme()
    alpha = alpha or 0.82

    local state = minimalThumbState[thumb]
    if not state or not state.texture then return end

    HideMinimalThumbArtwork(thumb)

    state.texture:ClearAllPoints()
    state.texture:SetPoint("TOP", thumb, "TOP", 0, 0)
    state.texture:SetPoint("BOTTOM", thumb, "BOTTOM", 0, 0)
    state.texture:SetWidth(CHAT_SCROLLBAR_THUMB_WIDTH)
    state.texture:SetColorTexture(theme.accent[1], theme.accent[2], theme.accent[3], alpha)
    state.texture:SetAlpha(1)
    state.texture:Show()
end

local StyleMinimalThumb

local function RepaintMinimalScrollBar(scrollBar, theme)
    if not IsMinimalScrollBar(scrollBar) then return end

    theme = theme or ResolveTheme()
    if scrollBar.Track then
        scrollBar.Track:SetAlpha(1)
        KeepFrameVisible(scrollBar.Track)
        HideDefaultTextures(scrollBar.Track)
        StyleMinimalTrack(scrollBar, theme)
        HideMinimalTrackArtwork(scrollBar)
    end

    if StyleMinimalThumb then
        StyleMinimalThumb(GetMinimalThumb(scrollBar), theme)
    end
end

function StyleMinimalThumb(thumb, theme)
    if not thumb then return end

    local state = minimalThumbState[thumb]
    if not state then
        state = {}
        minimalThumbState[thumb] = state

        state.texture = thumb:CreateTexture(nil, "OVERLAY")
        state.texture:SetTexture("Interface\\Buttons\\WHITE8x8")
        if state.texture.SetDrawLayer then
            state.texture:SetDrawLayer("OVERLAY", 7)
        end
        if UIKit and UIKit.DisablePixelSnap then
            UIKit.DisablePixelSnap(state.texture)
        end

        if hooksecurefunc and thumb.OnButtonStateChanged then
            hooksecurefunc(thumb, "OnButtonStateChanged", function(self)
                PaintMinimalThumb(self, CHAT_SCROLLBAR_THUMB_ALPHA)
            end)
        end
        if thumb.HookScript then
            thumb:HookScript("OnShow", function(self)
                PaintMinimalThumb(self, CHAT_SCROLLBAR_THUMB_ALPHA)
            end)
            thumb:HookScript("OnSizeChanged", function(self)
                PaintMinimalThumb(self, CHAT_SCROLLBAR_THUMB_ALPHA)
            end)
        end
        thumb:HookScript("OnEnter", function(self)
            PaintMinimalThumb(self, CHAT_SCROLLBAR_THUMB_ALPHA)
        end)
        thumb:HookScript("OnLeave", function(self)
            PaintMinimalThumb(self, CHAT_SCROLLBAR_THUMB_ALPHA)
        end)
        thumb:HookScript("OnMouseDown", function(self)
            PaintMinimalThumb(self, CHAT_SCROLLBAR_THUMB_ALPHA)
        end)
        thumb:HookScript("OnMouseUp", function(self)
            PaintMinimalThumb(self, CHAT_SCROLLBAR_THUMB_ALPHA)
        end)
    end

    -- The native thumb mixin reads atlas metadata during resize, so keep
    -- those atlas-backed pieces intact and paint QUI's thumb as an overlay.
    HideMinimalThumbArtwork(thumb)
    if thumb.SetWidth then thumb:SetWidth(CHAT_SCROLLBAR_HIT_WIDTH) end

    PaintMinimalThumb(thumb, CHAT_SCROLLBAR_THUMB_ALPHA, theme)
end

local function StyleScrollBarThumb(scrollBar, theme)
    local thumbTexture = scrollBar.ThumbTexture or (scrollBar.GetThumbTexture and scrollBar:GetThumbTexture())
    if thumbTexture and thumbTexture.SetColorTexture then
        thumbTexture:SetTexture("Interface\\Buttons\\WHITE8x8")
        thumbTexture:SetColorTexture(theme.accent[1], theme.accent[2], theme.accent[3], CHAT_SCROLLBAR_THUMB_ALPHA)
        if thumbTexture.SetAlpha then thumbTexture:SetAlpha(1) end
        if thumbTexture.SetSize then thumbTexture:SetSize(8, 40) end
        return
    end

    if IsMinimalScrollBar(scrollBar) then
        StyleMinimalThumb(GetMinimalThumb(scrollBar), theme)
    end
end

local function CreateLine(parent)
    local line = parent:CreateTexture(nil, "ARTWORK")
    line:SetTexture("Interface\\Buttons\\WHITE8x8")
    return line
end

local function StyleScrollToBottomButton(button)
    if not button then return end

    local state = scrollButtonState[button]
    if not state then
        state = {}
        scrollButtonState[button] = state
        HideDefaultTextures(button)
        if UIKit and UIKit.CreateBorderLines then
            UIKit.CreateBorderLines(button)
        end

        state.hover = button:CreateTexture(nil, "BACKGROUND")
        state.hover:SetAllPoints(button)
        state.hover:Hide()

        state.left = CreateLine(button)
        state.left:SetSize(8, 1)
        state.left:SetPoint("CENTER", -3, 1)
        if state.left.SetRotation then state.left:SetRotation(-0.785) end

        state.right = CreateLine(button)
        state.right:SetSize(8, 1)
        state.right:SetPoint("CENTER", 3, 1)
        if state.right.SetRotation then state.right:SetRotation(0.785) end

        state.base = CreateLine(button)
        state.base:SetSize(12, 1)
        state.base:SetPoint("CENTER", 0, -5)

        button:HookScript("OnEnter", function(self)
            local s = scrollButtonState[self]
            local theme = ResolveTheme()
            if s and s.hover then
                s.hover:SetColorTexture(theme.accent[1], theme.accent[2], theme.accent[3], 0.08)
                s.hover:Show()
            end
            if UIKit and UIKit.UpdateBorderLines then
                UIKit.UpdateBorderLines(self, 1, theme.accent[1], theme.accent[2], theme.accent[3], 0.9)
            end
            HideScrollToBottomArtwork(self)
        end)
        button:HookScript("OnLeave", function(self)
            local s = scrollButtonState[self]
            local theme = ResolveTheme()
            if s and s.hover then
                s.hover:Hide()
            end
            if UIKit and UIKit.UpdateBorderLines then
                UIKit.UpdateBorderLines(self, 1, theme.accent[1], theme.accent[2], theme.accent[3], 0.35)
            end
            HideScrollToBottomArtwork(self)
        end)
        button:HookScript("OnShow", HideScrollToBottomArtwork)
        button:HookScript("OnMouseDown", HideScrollToBottomArtwork)
        button:HookScript("OnMouseUp", HideScrollToBottomArtwork)
    end

    local theme = ResolveTheme()
    HideScrollToBottomArtwork(button)

    button:SetAlpha(0.85)
    if button.SetSize then
        button:SetSize(CHAT_SCROLL_TO_BOTTOM_SIZE, CHAT_SCROLL_TO_BOTTOM_SIZE)
    end
    if UIKit and UIKit.UpdateBorderLines then
        UIKit.UpdateBorderLines(button, 1, theme.accent[1], theme.accent[2], theme.accent[3], 0.35)
    end
    if state.left then state.left:SetColorTexture(theme.accent[1], theme.accent[2], theme.accent[3], 0.9) end
    if state.right then state.right:SetColorTexture(theme.accent[1], theme.accent[2], theme.accent[3], 0.9) end
    if state.base then state.base:SetColorTexture(theme.textDim[1], theme.textDim[2], theme.textDim[3], 0.5) end
    if state.left then state.left:SetAlpha(1) end
    if state.right then state.right:SetAlpha(1) end
    if state.base then state.base:SetAlpha(1) end
end

local function HookScrollBarUpdates(scrollBar)
    if not scrollBar or scrollBarHookState[scrollBar] then return end
    scrollBarHookState[scrollBar] = true

    if hooksecurefunc and scrollBar.Update then
        hooksecurefunc(scrollBar, "Update", function(self)
            RepaintMinimalScrollBar(self)
        end)
    end
    if scrollBar.HookScript then
        scrollBar:HookScript("OnShow", function(self)
            RepaintMinimalScrollBar(self)
        end)
    end
end

local function StyleChatScrollChrome(chatFrame)
    local settings = I.GetSettings and I.GetSettings()
    if not settings or not settings.enabled then return end

    if settings.glass and settings.glass.enabled then
        StripChatFrameBackground(chatFrame)
    end

    local scrollBar = GetScrollBar(chatFrame)
    local theme = ResolveTheme()
    local frameName = chatFrame and chatFrame.GetName and chatFrame:GetName()
    local bottomButton = chatFrame and chatFrame.ScrollToBottomButton
    if not bottomButton and frameName then
        bottomButton = _G[frameName .. "ScrollToBottomButton"]
    end
    if bottomButton then
        LayoutScrollToBottomButton(chatFrame, bottomButton)
        StyleScrollToBottomButton(bottomButton)
    end

    if scrollBar then
        local isMinimalScrollBar = IsMinimalScrollBar(scrollBar)
        LayoutChatScrollBar(chatFrame, scrollBar, bottomButton)
        HideDefaultTextures(scrollBar)
        if scrollBar.Track then
            if isMinimalScrollBar then
                HookScrollBarUpdates(scrollBar)
                RepaintMinimalScrollBar(scrollBar, theme)
            else
                scrollBar.Track:SetAlpha(0)
            end
        end
        if scrollBar.Background then scrollBar.Background:SetAlpha(0) end
        if scrollBar.BG then scrollBar.BG:SetAlpha(0) end
        if scrollBar.SetWidth then scrollBar:SetWidth(isMinimalScrollBar and CHAT_SCROLLBAR_HIT_WIDTH or 8) end

        StyleScrollBarThumb(scrollBar, theme)

        HideScrollButton(scrollBar.ScrollUpButton)
        HideScrollButton(scrollBar.ScrollDownButton)
        HideScrollButton(scrollBar.Back)
        HideScrollButton(scrollBar.Forward)
        if frameName then
            HideScrollButton(_G[frameName .. "ScrollBarScrollUpButton"])
            HideScrollButton(_G[frameName .. "ScrollBarScrollDownButton"])
        end
    end

end

local function RestyleChatScrollChrome(chatFrame)
    if not chatFrame then return end
    StyleChatScrollChrome(chatFrame)
    if C_Timer and C_Timer.After then
        C_Timer.After(0, function()
            StyleChatScrollChrome(chatFrame)
        end)
    end
end

local function FadeInChatScrollBarFullAlpha(chatFrame)
    local scrollBar = GetScrollBar(chatFrame)
    if not scrollBar or (scrollBar.IsShown and not scrollBar:IsShown()) then return end

    if UIFrameFadeRemoveFrame then
        UIFrameFadeRemoveFrame(scrollBar)
    end

    local fromAlpha = scrollBar.GetAlpha and scrollBar:GetAlpha() or 0
    if UIFrameFadeIn then
        UIFrameFadeIn(scrollBar, CHAT_FRAME_FADE_TIME or 0.15, fromAlpha, 1)
    elseif scrollBar.SetAlpha then
        scrollBar:SetAlpha(1)
    end
end

local function RestyleChatScrollChromeAfterFadeIn(chatFrame)
    RestyleChatScrollChrome(chatFrame)
    FadeInChatScrollBarFullAlpha(chatFrame)
    if C_Timer and C_Timer.After then
        C_Timer.After(0, function()
            FadeInChatScrollBarFullAlpha(chatFrame)
        end)
    end
end

local function StyleCombatLogQuickButtonFrame()
    local combatLog = _G.COMBATLOG or _G.ChatFrame2
    local quickFrame = _G.CombatLogQuickButtonFrame_Custom
    if not combatLog or not quickFrame or not quickFrame.ClearAllPoints then return end

    -- Blizzard anchors this bar to COMBATLOG plus the scrollbar width. QUI's
    -- scrollbar sits inside the chat surface, so that extra width makes the
    -- combat-log filter strip protrude past the visible chat window.
    quickFrame:ClearAllPoints()
    quickFrame:SetPoint("BOTTOMLEFT", combatLog, "TOPLEFT", 0, 3)
    quickFrame:SetPoint("BOTTOMRIGHT", combatLog, "TOPRIGHT", 0, 3)

    if quickFrame.SetWidth and combatLog.GetWidth then
        local width = tonumber(combatLog:GetWidth())
        if width and width > 0 then
            quickFrame:SetWidth(width)
        end
    end
end

local function RestyleCombatLogQuickButtonFrame()
    StyleCombatLogQuickButtonFrame()
    if C_Timer and C_Timer.After then
        C_Timer.After(0, StyleCombatLogQuickButtonFrame)
    end
end

local combatLogHooksInstalled = false
local function InstallCombatLogHooks()
    if combatLogHooksInstalled or not hooksecurefunc then return end
    if not _G.Blizzard_CombatLog_Update_QuickButtons then return end

    combatLogHooksInstalled = true
    hooksecurefunc("Blizzard_CombatLog_Update_QuickButtons", RestyleCombatLogQuickButtonFrame)
    if _G.Blizzard_CombatLog_QuickButtonFrame_OnLoad then
        hooksecurefunc("Blizzard_CombatLog_QuickButtonFrame_OnLoad", RestyleCombatLogQuickButtonFrame)
    end
    RestyleCombatLogQuickButtonFrame()
end

local scrollChromeHooksInstalled = false
local function InstallScrollChromeHooks()
    if scrollChromeHooksInstalled or not hooksecurefunc then return end
    scrollChromeHooksInstalled = true

    if FCF_UpdateScrollbarAnchors then
        hooksecurefunc("FCF_UpdateScrollbarAnchors", RestyleChatScrollChrome)
    end
    if FloatingChatFrame_UpdateScroll then
        hooksecurefunc("FloatingChatFrame_UpdateScroll", RestyleChatScrollChrome)
    end
    if FCF_FadeInScrollbar then
        hooksecurefunc("FCF_FadeInScrollbar", RestyleChatScrollChromeAfterFadeIn)
    end
    if FCF_FadeOutScrollbar then
        hooksecurefunc("FCF_FadeOutScrollbar", RestyleChatScrollChrome)
    end
    InstallCombatLogHooks()
end

---------------------------------------------------------------------------
-- Style chat tabs (General, Combat Log, etc.)
---------------------------------------------------------------------------

-- Texture regions on ChatTabArtTemplate that need to be kept invisible. The
-- glow is intentionally excluded — we reskin it in StyleTab as an unread pulse.
local STRIPPED_PARENTKEYS = {
    "Left", "Middle", "Right",
    "ActiveLeft", "ActiveMiddle", "ActiveRight",
    "HighlightLeft", "HighlightMiddle", "HighlightRight",
    "leftSelectedTexture", "middleSelectedTexture", "rightSelectedTexture",
    "leftHighlightTexture", "middleHighlightTexture", "rightHighlightTexture",
    "conversationIcon",
}

local TAB_CHROME_HEIGHT = 22
local TAB_TEXT_PAD_X = 8
local UNREAD_PULSE_HEIGHT = 3

local function GetTabChromeWidth(tab)
    local chatFrame = I.GetTabChatFrame and I.GetTabChatFrame(tab)
    if not I.IsTemporaryChatFrame(chatFrame) or not tab.GetWidth then return nil end

    local tabWidth = tonumber(tab:GetWidth())
    local extraPadding = tonumber(tab.sizePadding) or 0
    if not tabWidth or extraPadding <= 0 then return nil end

    -- Blizzard adds sizePadding to temporary tabs for the whisper/conversation
    -- icon. QUI hides that icon, so omit the icon reserve from our visible skin.
    return math.max(1, tabWidth - extraPadding)
end

local function GetTabForChatFrame(chatFrame)
    if not chatFrame then return nil end
    if chatFrame.GetName then
        local frameName = chatFrame:GetName()
        if frameName then
            return _G[frameName .. "Tab"]
        end
    end
    if chatFrame.GetID then
        local frameID = chatFrame:GetID()
        if frameID then
            return _G["ChatFrame" .. frameID .. "Tab"]
        end
    end
    return nil
end

local function VisitChatFrameTab(chatFrame, seen, callback)
    local tab = GetTabForChatFrame(chatFrame)
    if tab and not seen[tab] then
        seen[tab] = true
        callback(tab)
    end
end

local function VisitChatFrame(chatFrame, seen, callback)
    if chatFrame and not seen[chatFrame] then
        seen[chatFrame] = true
        callback(chatFrame)
    end
end

local function ForEachChatFrame(callback)
    local seen = {}
    local numChatWindows = _G.NUM_CHAT_WINDOWS or NUM_CHAT_WINDOWS or 10

    for i = 1, numChatWindows do
        VisitChatFrame(_G["ChatFrame" .. i], seen, callback)
    end

    if type(_G.CHAT_FRAMES) == "table" then
        for _, frameName in pairs(_G.CHAT_FRAMES) do
            VisitChatFrame(_G[frameName], seen, callback)
        end
    end

    local dock = _G.GENERAL_CHAT_DOCK
    if not dock then return end

    local dockedFrames
    if type(_G.FCFDock_GetChatFrames) == "function" then
        local ok, frames = pcall(_G.FCFDock_GetChatFrames, dock)
        if ok then dockedFrames = frames end
    end
    dockedFrames = dockedFrames or dock.DOCKED_CHAT_FRAMES or _G.DOCKED_CHAT_FRAMES

    if type(dockedFrames) ~= "table" then return end
    for _, chatFrame in pairs(dockedFrames) do
        VisitChatFrame(chatFrame, seen, callback)
    end
end

local function ForEachChatTab(callback)
    local seen = {}

    -- Temporary whisper windows are docked chat frames. Walk the same combined
    -- frame list used by SkinAll so their tabs are styled with regular tabs.
    ForEachChatFrame(function(chatFrame)
        VisitChatFrameTab(chatFrame, seen, callback)
    end)
end

local function IsDockSelectedTab(tab)
    if not tab or type(_G.FCFDock_GetSelectedWindow) ~= "function" or not _G.GENERAL_CHAT_DOCK then
        return false
    end

    local ok, selectedFrame = pcall(_G.FCFDock_GetSelectedWindow, _G.GENERAL_CHAT_DOCK)
    return ok and GetTabForChatFrame(selectedFrame) == tab
end

-- Idempotent strip used by both the initial paint and every Blizzard repaint.
-- SetAlpha alone wasn't sticking — Blizzard's FCFTab_UpdateColors does
-- :Show() on Active* on the selected tab and :SetVertexColor(r,g,b) on
-- Active*/Highlight*/glow on every call. Empirically the corner artwork
-- ended up visible after dock/alert/chat-type events even after our initial
-- SetAlpha(0). Hide() on top of SetAlpha(0) is belt-and-suspenders: Hide
-- pulls the texture from the draw list regardless of vertex/alpha state.
local function StripBlizzardArtwork(tab)
    for _, key in ipairs(STRIPPED_PARENTKEYS) do
        local region = tab[key]
        if region then
            if region.SetAlpha then region:SetAlpha(0) end
            if region.Hide then region:Hide() end
        end
    end
    -- Defense net: any other texture child whose file path looks like Blizzard
    -- tab artwork (but not the glow we reskinned) gets the same treatment.
    if tab.GetRegions then
        for _, region in ipairs({tab:GetRegions()}) do
            if region and region.GetObjectType and region:GetObjectType() == "Texture" then
                local path = region.GetTexture and region:GetTexture()
                if type(path) == "string" then
                    local lower = path:lower()
                    if lower:find("chatframetab%-") and not lower:find("newmessage") then
                        region:SetAlpha(0)
                        if region.Hide then region:Hide() end
                    end
                end
            end
        end
    end
end

local function LayoutTabChrome(tab)
    local backdrop = I.tabBackdrops[tab]
    if not backdrop then return end

    -- Blizzard may give selected, alerting, or docked tabs different button
    -- heights. Keep QUI's visible tab chrome fixed so every tab paints at the
    -- same height while leaving Blizzard's own tab hitboxes/layout intact.
    backdrop:ClearAllPoints()
    backdrop:SetPoint("BOTTOMLEFT", tab, "BOTTOMLEFT", 0, 0)
    local chromeWidth = GetTabChromeWidth(tab)
    if chromeWidth then
        backdrop:SetWidth(chromeWidth)
    else
        backdrop:SetPoint("BOTTOMRIGHT", tab, "BOTTOMRIGHT", 0, 0)
    end
    backdrop:SetHeight(TAB_CHROME_HEIGHT)

    local fontString = tab:GetFontString()
    if fontString then
        if fontString.SetIgnoreParentAlpha then
            fontString:SetIgnoreParentAlpha(true)
        end
        fontString:ClearAllPoints()
        fontString:SetPoint("LEFT", backdrop, "LEFT", TAB_TEXT_PAD_X, 0)
        fontString:SetPoint("RIGHT", backdrop, "RIGHT", -TAB_TEXT_PAD_X, 0)
        if fontString.SetJustifyH then
            fontString:SetJustifyH("CENTER")
        end
    end
end

local function LayoutUnreadPulse(tab)
    local glow = tab and tab.glow
    if not glow or not glow.SetTexture then return end

    local anchor = I.tabBackdrops[tab] or tab
    glow:ClearAllPoints()
    glow:SetPoint("TOPLEFT", anchor, "TOPLEFT", 1, -1)
    glow:SetPoint("TOPRIGHT", anchor, "TOPRIGHT", -1, -1)
    glow:SetHeight(UNREAD_PULSE_HEIGHT)
    glow:SetTexture("Interface\\Buttons\\WHITE8x8")
    if glow.SetBlendMode then
        glow:SetBlendMode("ADD")
    end
end

local function UpdateTabColors(tab)
    local settings = I.GetSettings()
    if not settings or not I.tabBackdrops[tab] then return end

    local alpha = settings.glass and settings.glass.bgAlpha or 0.4

    -- Check if this tab is selected
    local isSelected = false
    for i = 1, (_G.NUM_CHAT_WINDOWS or NUM_CHAT_WINDOWS or 10) do
        local cf = _G["ChatFrame" .. i]
        if cf and cf:IsShown() then
            local frameTab = _G["ChatFrame" .. i .. "Tab"]
            if frameTab == tab then
                isSelected = true
                break
            end
        end
    end

    -- Also check button state
    if tab.GetButtonState and tab:GetButtonState() == "PUSHED" then
        isSelected = true
    end
    if not isSelected and IsDockSelectedTab(tab) then
        isSelected = true
    end

    -- Re-strip Blizzard artwork on every repaint. Without this, Active*
    -- shows on the selected tab (FCFTab_UpdateColors does :Show on the
    -- selected tab) and Highlight* can leak through after mouseover/dock
    -- events. Strip is idempotent so calling it on every UpdateTabColors
    -- is safe and cheap.
    StripBlizzardArtwork(tab)
    LayoutTabChrome(tab)
    LayoutUnreadPulse(tab)

    local fontString = tab:GetFontString()
    -- Accent resolved live so a theme-preset change propagates on the next
    -- repaint instead of being captured at module load.
    local accent = I.GetAccent and I.GetAccent() or I.QUI_COLORS.accent
    if isSelected then
        I.ApplySurfaceStyle(I.tabBackdrops[tab], {0, 0, 0, alpha + 0.2}, accent, 1)
        if fontString then
            fontString:SetTextColor(accent[1], accent[2], accent[3], 1)
        end
    else
        I.ApplySurfaceStyle(I.tabBackdrops[tab], {0, 0, 0, alpha}, {0, 0, 0, alpha}, 1)
        if fontString then
            local c = I.QUI_COLORS.textDim or {0.72, 0.72, 0.76, 1}
            fontString:SetTextColor(c[1], c[2], c[3], 1)
        end
    end
    -- Tint the new-message glow (reskinned as a pulsing top border on the
    -- visible tab chrome) to match the live theme accent. UIFrameFlash drives
    -- alpha pulse; SetVertexColor only affects the RGB so the pulse remains.
    if tab.glow and tab.glow.SetVertexColor then
        tab.glow:SetVertexColor(accent[1], accent[2], accent[3], 1)
    end
end

local function StyleTab(tab)
    if not tab then return end
    if tab.IsForbidden and tab:IsForbidden() then return end

    local settings = I.GetSettings()
    if not settings then return end

    -- Strip default tab artwork. Implementation is shared with UpdateTabColors
    -- so Blizzard's per-event re-Show of Active*/Highlight* gets re-stripped
    -- on every repaint, not just at first paint.
    StripBlizzardArtwork(tab)

    -- Create glass backdrop for our fixed-height tab chrome. SetIgnoreParentAlpha
    -- keeps the backdrop visually independent of the tab's own alpha — Blizzard
    -- sets tab:SetAlpha(0.4) on unselected tabs (FCFTab_UpdateAlpha), which
    -- would otherwise cascade onto our backdrop and make inactive tabs look
    -- fainter than selected ones. We control dimming through ApplySurfaceStyle.
    if not I.tabBackdrops[tab] then
        local backdrop = CreateFrame("Frame", nil, tab)
        backdrop:SetFrameLevel(math.max(1, tab:GetFrameLevel() - 1))
        if backdrop.SetIgnoreParentAlpha then
            backdrop:SetIgnoreParentAlpha(true)
        end
        I.tabBackdrops[tab] = backdrop
    end
    LayoutTabChrome(tab)

    -- Reskin the new-message glow as an accent-colored top border pinned to
    -- the visible tab chrome. The Blizzard ChatFrameTab-NewMessage texture is
    -- a wide bottom-anchored artwork whose visible glow extends well above the
    -- tab. Replacing the texture with a slim tab-width pulse keeps the unread
    -- signal (UIFrameFlash still pulses alpha on this exact frame) but makes
    -- it read as tab state instead of a separate indicator.
    LayoutUnreadPulse(tab)

    -- Update colors
    UpdateTabColors(tab)

    -- Style font with outline
    local fontString = tab:GetFontString()
    if fontString then
        local font, size = fontString:GetFont()
        if font then
            fontString:SetFont(font, size or 12, "OUTLINE")
            fontString:SetShadowOffset(0, 0)
        end
    end
end

local function StyleAllTabs()
    local settings = I.GetSettings()
    if not settings or not settings.enabled then return end

    ForEachChatTab(StyleTab)

    local TF = ns.QUI.Chat and ns.QUI.Chat.TabFilters
    if TF and TF.UpdateTabIndicators then
        TF.UpdateTabIndicators()
    end
end

---------------------------------------------------------------------------
-- Apply message padding (text inset via FontStringContainer positioning)
---------------------------------------------------------------------------
local function ApplyMessagePadding(chatFrame)
    local settings = I.GetSettings()
    if not settings then return end

    local padding = settings.messagePadding or 0
    local rightPadding = 0

    -- Modern chat frames use FontStringContainer for message display
    local container = chatFrame.FontStringContainer
    if container then
        container:ClearAllPoints()
        if padding > 0 then
            container:SetPoint("TOPLEFT", chatFrame, "TOPLEFT", padding, 0)
            container:SetPoint("BOTTOMRIGHT", chatFrame, "BOTTOMRIGHT", -rightPadding, 0)
        else
            container:SetPoint("TOPLEFT", chatFrame, "TOPLEFT", 0, 0)
            container:SetPoint("BOTTOMRIGHT", chatFrame, "BOTTOMRIGHT", -rightPadding, 0)
        end
    end
end

---------------------------------------------------------------------------
-- Main skin function for a single chat frame (orchestrator)
-- Calls into co-located leaves (StripDefaultTextures, CreateGlassBackdrop, etc.)
-- and cross-sibling subsystems (Cleanup, Copy, EditBoxBasics, EditBoxHistory).
---------------------------------------------------------------------------
local function SkinChatFrame(chatFrame)
    if not chatFrame or chatFrame:IsForbidden() or I.IsTemporaryChatFrame(chatFrame) then return end

    local settings = I.GetSettings()
    if not settings or not settings.enabled then return end

    local frameName = chatFrame:GetName()
    if not frameName then return end

    -- Mark as skinned
    skinnedFrames[chatFrame] = true

    -- Apply glass effect
    if settings.glass and settings.glass.enabled then
        StripDefaultTextures(chatFrame)
        CreateGlassBackdrop(chatFrame)
    end

    -- Apply font styling (always enabled)
    StyleFontStrings(chatFrame)

    -- Setup message fade (handles both enabling and disabling)
    SetupMessageFade(chatFrame)

    -- Apply live scrollback cap. This is state-tracked because SetMaxLines
    -- clears the visible buffer when the target changes.
    if I.ApplyScrollbackLines then
        I.ApplyScrollbackLines(chatFrame, settings)
    end

    StyleChatScrollChrome(chatFrame)

    -- Hide chat buttons (social/channel chrome)
    if settings.hideButtons then
        ns.QUI.Chat.Cleanup.HideButtons(chatFrame)
    end

    -- Style edit box
    if settings.editBox and settings.editBox.enabled then
        ns.QUI.Chat.EditBoxBasics.StyleEditBox(chatFrame)
    end

    -- Initialize chat history
    ns.QUI.Chat.EditBoxHistory.InitializeForFrame(chatFrame)

    -- Apply message padding
    ApplyMessagePadding(chatFrame)

    -- Apply copy button based on mode
    ns.QUI.Chat.Copy.ApplyButtonMode(chatFrame)
end

---------------------------------------------------------------------------
-- Skin all existing chat frames
---------------------------------------------------------------------------
local function SkinAllChatFrames()
    InstallScrollChromeHooks()

    ForEachChatFrame(function(chatFrame)
        if I.IsTemporaryChatFrame(chatFrame) then
            -- Whisper/popout chat frames keep their Blizzard frame hitbox, but
            -- their visible body and input should align with regular QUI chat.
            local settings = I.GetSettings()
            if settings and settings.enabled and settings.glass and settings.glass.enabled then
                StripDefaultTextures(chatFrame)
                CreateGlassBackdrop(chatFrame)
            end
            if ns.QUI.Chat.EditBoxBasics and ns.QUI.Chat.EditBoxBasics.StyleEditBox then
                ns.QUI.Chat.EditBoxBasics.StyleEditBox(chatFrame)
            end
            ApplyMessagePadding(chatFrame)
        else
            SkinChatFrame(chatFrame)
        end
    end)

    InstallCombatLogHooks()
    RestyleCombatLogQuickButtonFrame()
end

---------------------------------------------------------------------------
-- Public surface
---------------------------------------------------------------------------
Skinning.StripDefaultTextures = StripDefaultTextures
Skinning.CreateBackdrop       = CreateGlassBackdrop
Skinning.RemoveBackdrop       = RemoveGlassBackdrop
Skinning.StyleFontStrings     = StyleFontStrings
Skinning.SetupFade            = SetupMessageFade
Skinning.UpdateTabColors      = UpdateTabColors
Skinning.StyleTab             = StyleTab
Skinning.StyleAllTabs         = StyleAllTabs
Skinning.ApplyPadding         = ApplyMessagePadding
Skinning.StyleScrollChrome    = StyleChatScrollChrome
Skinning.SkinFrame            = SkinChatFrame
Skinning.SkinAll              = SkinAllChatFrames

-- Aliases on ns.QUI.Chat. Assigned here, not in chat.lua, because chat.lua
-- loads before skinning.lua per chat.xml.
ns.QUI.Chat.SkinFrame = SkinChatFrame
ns.QUI.Chat.SkinAll   = SkinAllChatFrames

InstallScrollChromeHooks()
InstallCombatLogHooks()

local combatLogEventFrame = CreateFrame("Frame")
combatLogEventFrame:RegisterEvent("ADDON_LOADED")
combatLogEventFrame:RegisterEvent("PLAYER_LOGIN")
combatLogEventFrame:SetScript("OnEvent", function(_, event, addonName)
    if event == "ADDON_LOADED" and addonName ~= "Blizzard_CombatLog" then return end
    InstallCombatLogHooks()
    RestyleCombatLogQuickButtonFrame()
end)
