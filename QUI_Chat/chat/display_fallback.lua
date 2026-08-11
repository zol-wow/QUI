local ADDON_NAME, ns = ...

local I = assert(ns.QUI.Chat and ns.QUI.Chat._internals,
    "QUI Chat: display_fallback.lua loaded before chat.lua. Check chat.xml — chat.lua must precede display_fallback.lua.")

ns.QUI.Chat.DisplayFallback = ns.QUI.Chat.DisplayFallback or {}
local Fallback = ns.QUI.Chat.DisplayFallback

local lastAppliedCustom

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
            local StoreMod = ns.QUI.Chat.MessageStore
            if StoreMod and StoreMod.Size and StoreMod.Size() == 0
                and Capture.BackfillFromDefaultFrame then
                Capture.BackfillFromDefaultFrame()
            end
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
        local EditBox = ns.QUI.Chat.EditBoxBasics
        if EditBox and EditBox.StyleEditBox then
            EditBox.StyleEditBox(_G.ChatFrame1)
        end
    else
        Capture.Teardown()
        if Display.IsCreated and Display.IsCreated() then
            Display.Hide()
        end
        local EditBox = ns.QUI.Chat.EditBoxBasics
        if EditBox and EditBox.RemoveEditBoxStyle then
            EditBox.RemoveEditBoxStyle(_G.ChatFrame1)
        end
    end
    local Suppress = ns.QUI.Chat.BlizzardSuppress
    if Suppress and Suppress.Apply then
        Suppress.Apply()
    end
    local ButtonBar = ns.QUI.Chat.ButtonBar
    if ButtonBar and ButtonBar.Reapply then
        ButtonBar.Reapply()
    end
end

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
