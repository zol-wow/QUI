-- modules/chat/display_fallback.lua
-- Applies chat.displayMode. "custom" starts capture and shows the custom
-- display; "blizzard" (or chat disabled) tears capture down and hides it.
-- The MessageStore is NEVER cleared here — toggling is lossless by design
-- (Phase 1 validation gate: "toggle back to Blizzard anytime without data
-- loss"). Blizzard chat frames are untouched in Phase 1 (dual display).
local ADDON_NAME, ns = ...

local I = assert(ns.QUI.Chat and ns.QUI.Chat._internals,
    "QUI Chat: display_fallback.lua loaded before chat.lua. Check chat.xml — chat.lua must precede display_fallback.lua.")

ns.QUI.Chat.DisplayFallback = ns.QUI.Chat.DisplayFallback or {}
local Fallback = ns.QUI.Chat.DisplayFallback

local lastAppliedCustom -- nil until first Apply; latches the applied mode

-- Idempotent; safe to call from PLAYER_LOGIN, RefreshAll, and option flips.
-- The full SMF Rebuild (Clear + re-render of up to maxLines entries) runs
-- only when the mode TRANSITIONS into custom — repeat Apply() calls in the
-- same mode (cosmetic RefreshAll: sliders, skin colors) just Refresh().
function Fallback.Apply()
    local Capture = ns.QUI.Chat.MessageCapture
    local Display = ns.QUI.Chat.DisplayLayer
    local TabManager = ns.QUI.Chat.TabManager
    if not (Capture and Display) then return end

    local settings = I.GetSettings and I.GetSettings()
    local enabled = I.IsChatEnabled and I.IsChatEnabled(settings)
    local custom = (enabled and settings and settings.displayMode == "custom") and true or false
    local entering = custom and lastAppliedCustom ~= true
    lastAppliedCustom = custom

    if custom then
        Capture.Setup()
        Display.EnsureCreated()
        Display.Refresh()
        Display.Show()
        if entering then
            -- Replay the retained store through the active tab filter; while
            -- in blizzard mode capture is torn down, so nothing accumulates
            -- hidden — entering is the only moment the view can be stale.
            Display.Rebuild(TabManager and TabManager.GetActiveFilter and TabManager.GetActiveFilter() or nil)
        end
    else
        Capture.Teardown()
        if Display.IsCreated and Display.IsCreated() then
            Display.Hide()
        end
    end
end
