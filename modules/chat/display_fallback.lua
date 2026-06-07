-- modules/chat/display_fallback.lua
-- Applies the chat takeover: enabled starts capture and shows the QUI display;
-- disabled tears everything down and restores stock Blizzard chat.
-- The MessageStore is NEVER cleared here — toggling is lossless by design
-- (validation gate: "toggle back to Blizzard anytime without data loss").
-- While enabled ChatFrame1 is reparented/suppressed unconditionally and
-- fully EVENT-NEUTERED (no message processing). Sounds, keyword sounds,
-- and history are driven by QUI's store subscribers while suppressed.
local ADDON_NAME, ns = ...

local I = assert(ns.QUI.Chat and ns.QUI.Chat._internals,
    "QUI Chat: display_fallback.lua loaded before chat.lua. Check chat.xml — chat.lua must precede display_fallback.lua.")

ns.QUI.Chat.DisplayFallback = ns.QUI.Chat.DisplayFallback or {}
local Fallback = ns.QUI.Chat.DisplayFallback

local lastAppliedCustom -- nil until first Apply; latches the applied state

-- Idempotent; safe to call from PLAYER_LOGIN, RefreshAll, and option flips.
-- The full SMF Rebuild (Clear + re-render of up to maxLines entries) runs
-- only when the takeover TRANSITIONS on — repeat Apply() calls in the
-- same state (cosmetic RefreshAll: sliders, skin colors) just Refresh().
function Fallback.Apply()
    local Capture = ns.QUI.Chat.MessageCapture
    local Display = ns.QUI.Chat.DisplayLayer
    local TabManager = ns.QUI.Chat.TabManager
    if not (Capture and Display) then return end

    local settings = I.GetSettings and I.GetSettings()
    local enabled = I.IsChatEnabled and I.IsChatEnabled(settings)
    local active = enabled and true or false
    local entering = active and lastAppliedCustom ~= true
    lastAppliedCustom = active

    if active then
        Capture.Setup()
        Display.EnsureCreated()
        Display.Refresh()
        Display.Show()
        if entering then
            -- Mid-session first enable: replay the Blizzard scrollback so the
            -- view doesn't start empty (login-time enables backfill nothing —
            -- the store already captured from ADDON_LOADED).
            local StoreMod = ns.QUI.Chat.MessageStore
            if StoreMod and StoreMod.Size and StoreMod.Size() == 0
                and Capture.BackfillFromDefaultFrame then
                Capture.BackfillFromDefaultFrame()
            end
            -- Replay the retained store through every window's active filter;
            -- while disabled capture is torn down, so nothing accumulates
            -- hidden — entering is the only moment the view can be stale.
            if TabManager and TabManager.ReapplyAll then
                TabManager.ReapplyAll()
            end
        end
        local TabUI = ns.QUI.Chat.TabUI
        if TabUI and TabUI.EnsureAttached then
            TabUI.EnsureAttached()
        end
        local Scrollbar = ns.QUI.Chat.Scrollbar
        if Scrollbar and Scrollbar.EnsureAttached then
            Scrollbar.EnsureAttached()
        end
        local Copy = ns.QUI.Chat.Copy
        if Copy and Copy.EnsureCustomCopyButton then
            Copy.EnsureCustomCopyButton()
        end
        -- The takeover owns ChatFrame1's editbox (the single input): input
        -- styling + docking under the QUI display. Must run AFTER the display
        -- is created/shown so editbox_basics' anchor chooser targets the
        -- container. Self-gates on settings.editBox; idempotent.
        local EditBox = ns.QUI.Chat.EditBoxBasics
        if EditBox and EditBox.StyleEditBox then
            EditBox.StyleEditBox(_G.ChatFrame1)
        end
    else
        Capture.Teardown()
        if Display.IsCreated and Display.IsCreated() then
            Display.Hide()
        end
        -- Flip-back: drop the glass styling so the stock editbox returns.
        local EditBox = ns.QUI.Chat.EditBoxBasics
        if EditBox and EditBox.RemoveEditBoxStyle then
            EditBox.RemoveEditBoxStyle(_G.ChatFrame1)
        end
    end
    -- Takeover switch: reparent suppression of the Blizzard frames follows the
    -- master toggle (self-latched; restores on any exit path).
    local Suppress = ns.QUI.Chat.BlizzardSuppress
    if Suppress and Suppress.Apply then
        Suppress.Apply()
    end
    -- Suppression may have changed the frame-1 bar's anchor target —
    -- reconcile bars now rather than one refresh late (the bar module's
    -- _afterRefresh hook already ran earlier in RefreshAll).
    local ButtonBar = ns.QUI.Chat.ButtonBar
    if ButtonBar and ButtonBar.Reapply then
        ButtonBar.Reapply()
    end
end

-- Live skin/accent recolor: the chat module's own Registry group is "chat"
-- (global skin refreshes skip it), so the custom display registers its own
-- entry on the "skinning" group, mirroring chatSurfaceSkin.
if ns.Registry then
    ns.Registry:Register("chatCustomDisplaySkin", {
        refresh = function()
            local settings = I.GetSettings and I.GetSettings()
            if not (I.IsChatEnabled and I.IsChatEnabled(settings)) then return end
            local Display = ns.QUI.Chat.DisplayLayer
            if not (Display and Display.IsCreated and Display.IsCreated()) then return end
            if Display.Refresh then Display.Refresh() end
            local TabUI = ns.QUI.Chat.TabUI
            if TabUI and TabUI.Rebuild then TabUI.Rebuild() end
            local Scrollbar = ns.QUI.Chat.Scrollbar
            if Scrollbar and Scrollbar.Restyle then Scrollbar.Restyle() end
        end,
        priority = 50,
        group = "skinning",
        importCategories = { "skinning", "theme" },
    })
end
