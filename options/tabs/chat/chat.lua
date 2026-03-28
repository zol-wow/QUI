local ADDON_NAME, ns = ...
local QUI = QUI
local GUI = QUI.GUI
local C = GUI.Colors
local Shared = ns.QUI_Options
local Helpers = ns.Helpers
local P = Helpers.PlaceRow

local function BuildChatTab(tabContent)
    local FORM_ROW = 32
    local PAD = Shared.PADDING
    local db = Shared.GetDB()

    GUI:SetSearchContext({tabIndex = 2, tabName = "General & QoL", subTabIndex = 4, subTabName = "Chat"})

    if not (db and db.chat) then return end

    local chat = db.chat
    local function RefreshChat()
        if _G.QUI_RefreshChat then _G.QUI_RefreshChat() end
    end

    local sections, relayout, CreateCollapsible = Shared.CreateCollapsiblePage(tabContent, PAD)

    -- ========== Enable/Disable ==========
    CreateCollapsible("Enable/Disable QUI Chat Module", 2 * FORM_ROW + 8, function(body)
        local sy = -4
        sy = P(GUI:CreateFormCheckbox(body, "QUI Chat Module", "enabled", chat, RefreshChat), body, sy)

        local info = GUI:CreateLabel(body, "If you are using a dedicated chat addon, toggle this off.", 10, C.textMuted)
        info:SetPoint("TOPLEFT", 0, sy)
        info:SetPoint("RIGHT", body, "RIGHT", 0, 0)
        info:SetJustifyH("LEFT")
    end)

    -- ========== Intro Message ==========
    CreateCollapsible("Intro Message", 2 * FORM_ROW + 8, function(body)
        local sy = -4
        sy = P(GUI:CreateFormCheckbox(body, "Show Login Message", "showIntroMessage", chat, nil), body, sy)

        local info = GUI:CreateLabel(body, "Display the QUI reminder tips when you log in.", 10, C.textMuted)
        info:SetPoint("TOPLEFT", 0, sy)
        info:SetPoint("RIGHT", body, "RIGHT", 0, 0)
        info:SetJustifyH("LEFT")
    end)

    -- ========== Chat Background ==========
    if chat.glass then
        CreateCollapsible("Chat Background", 3 * FORM_ROW + 8, function(body)
            local sy = -4
            sy = P(GUI:CreateFormCheckbox(body, "Chat Background Texture", "enabled", chat.glass, RefreshChat), body, sy)
            sy = P(GUI:CreateFormSlider(body, "Background Opacity", 0, 1.0, 0.05, "bgAlpha", chat.glass, RefreshChat), body, sy)
            P(GUI:CreateFormColorPicker(body, "Background Color", "bgColor", chat.glass, RefreshChat), body, sy)
        end)
    end

    -- ========== Input Box Background ==========
    if chat.editBox then
        CreateCollapsible("Input Box Background", 5 * FORM_ROW + 8, function(body)
            local sy = -4
            sy = P(GUI:CreateFormCheckbox(body, "Input Box Background Texture", "enabled", chat.editBox, RefreshChat), body, sy)
            sy = P(GUI:CreateFormSlider(body, "Background Opacity", 0, 1.0, 0.05, "bgAlpha", chat.editBox, RefreshChat), body, sy)
            sy = P(GUI:CreateFormColorPicker(body, "Background Color", "bgColor", chat.editBox, RefreshChat), body, sy)
            sy = P(GUI:CreateFormCheckbox(body, "Position Input Box at Top", "positionTop", chat.editBox, RefreshChat), body, sy)

            local info = GUI:CreateLabel(body, "Moves input box above chat tabs with opaque background.", 10, C.textMuted)
            info:SetPoint("TOPLEFT", 0, sy)
            info:SetPoint("RIGHT", body, "RIGHT", 0, 0)
            info:SetJustifyH("LEFT")
        end)
    end

    -- ========== Message Fade ==========
    if chat.fade then
        CreateCollapsible("Message Fade", 2 * FORM_ROW + 8, function(body)
            local sy = -4
            sy = P(GUI:CreateFormCheckbox(body, "Fade Messages After Inactivity", "enabled", chat.fade, RefreshChat), body, sy)
            P(GUI:CreateFormSlider(body, "Fade Delay (seconds)", 1, 120, 1, "delay", chat.fade, RefreshChat), body, sy)
        end)
    end

    -- ========== URL Detection ==========
    if chat.urls then
        CreateCollapsible("URL Detection", 2 * FORM_ROW + 8, function(body)
            local sy = -4
            sy = P(GUI:CreateFormCheckbox(body, "Make URLs Clickable", "enabled", chat.urls, RefreshChat), body, sy)

            local info = GUI:CreateLabel(body, "Click any URL in chat to open a copy dialog.", 10, C.textMuted)
            info:SetPoint("TOPLEFT", 0, sy)
            info:SetPoint("RIGHT", body, "RIGHT", 0, 0)
            info:SetJustifyH("LEFT")
        end)
    end

    -- ========== Timestamps ==========
    CreateCollapsible("Timestamps", 4 * FORM_ROW + 8, function(body)
        local sy = -4
        if not chat.timestamps then chat.timestamps = {enabled = false, format = "24h", color = {0.6, 0.6, 0.6}} end

        sy = P(GUI:CreateFormCheckbox(body, "Show Timestamps", "enabled", chat.timestamps, RefreshChat), body, sy)

        local info = GUI:CreateLabel(body, "Timestamps only appear on new messages after enabling.", 10, C.textMuted)
        info:SetPoint("TOPLEFT", 0, sy)
        info:SetPoint("RIGHT", body, "RIGHT", 0, 0)
        info:SetJustifyH("LEFT")
        sy = sy - 20

        local formatOptions = {
            {value = "24h", text = "24-Hour (15:27)"},
            {value = "12h", text = "12-Hour (3:27 PM)"},
        }
        sy = P(GUI:CreateFormDropdown(body, "Format", formatOptions, "format", chat.timestamps, RefreshChat), body, sy)
        P(GUI:CreateFormColorPicker(body, "Timestamp Color", "color", chat.timestamps, RefreshChat), body, sy)
    end)

    -- ========== UI Cleanup ==========
    CreateCollapsible("UI Cleanup", 2 * FORM_ROW + 8, function(body)
        local sy = -4
        sy = P(GUI:CreateFormCheckbox(body, "Hide Chat Buttons", "hideButtons", chat, RefreshChat), body, sy)

        local info = GUI:CreateLabel(body, "Hides social, channel, and scroll buttons. Mouse wheel still scrolls.", 10, C.textMuted)
        info:SetPoint("TOPLEFT", 0, sy)
        info:SetPoint("RIGHT", body, "RIGHT", 0, 0)
        info:SetJustifyH("LEFT")
    end)

    -- ========== Copy Button ==========
    CreateCollapsible("Copy Button", 2 * FORM_ROW + 8, function(body)
        local sy = -4
        local copyButtonOptions = {
            {value = "always", text = "Show Always"},
            {value = "hover", text = "Show on Hover"},
            {value = "disabled", text = "Disabled"},
        }
        sy = P(GUI:CreateFormDropdown(body, "Copy Button", copyButtonOptions, "copyButtonMode", chat, RefreshChat), body, sy)

        local info = GUI:CreateLabel(body, "Controls the copy button on each chat frame for copying chat history.", 10, C.textMuted)
        info:SetPoint("TOPLEFT", 0, sy)
        info:SetPoint("RIGHT", body, "RIGHT", 0, 0)
        info:SetJustifyH("LEFT")
    end)

    -- ========== Message History ==========
    CreateCollapsible("Message History", 2 * FORM_ROW + 8, function(body)
        local sy = -4
        if not chat.messageHistory then
            chat.messageHistory = { enabled = true, maxHistory = 50 }
        end

        sy = P(GUI:CreateFormCheckbox(body, "Enable Message History", "enabled", chat.messageHistory, RefreshChat), body, sy)

        local info = GUI:CreateLabel(body, "Use arrow keys (Up/Down) to navigate through your sent message history while typing.", 10, C.textMuted)
        info:SetPoint("TOPLEFT", 0, sy)
        info:SetPoint("RIGHT", body, "RIGHT", 0, 0)
        info:SetJustifyH("LEFT")
    end)

    -- ========== New Message Sound ==========
    CreateCollapsible("New Message Sound", 1, function(body)
        local sy = -4
        if not chat.newMessageSound then
            chat.newMessageSound = { enabled = false, entries = {{ channel = "guild_officer", sound = "None" }} }
        end
        if not chat.newMessageSound.entries or #chat.newMessageSound.entries == 0 then
            chat.newMessageSound.entries = {{ channel = "guild_officer", sound = "None" }}
        end

        sy = P(GUI:CreateFormCheckbox(body, "Play Sound on New Message", "enabled", chat.newMessageSound, RefreshChat), body, sy)

        local soundEntriesContainer = CreateFrame("Frame", nil, body)
        soundEntriesContainer:SetPoint("TOPLEFT", 0, sy)
        soundEntriesContainer:SetPoint("RIGHT", body, "RIGHT", 0, 0)
        soundEntriesContainer:SetHeight(1)

        local ALL_CHANNEL_OPTIONS = {
            {value = "guild_officer", text = "Guild & Officer"},
            {value = "guild", text = "Guild Only"},
            {value = "officer", text = "Officer Only"},
            {value = "party", text = "Party"},
            {value = "raid", text = "Raid"},
            {value = "whisper", text = "Whisper"},
            {value = "all", text = "All Channels"},
        }

        local function GetChannelOptionsForEntry(entries, excludeIndex)
            local used = {}
            for i, e in ipairs(entries) do
                if i ~= excludeIndex and e.channel then used[e.channel] = true end
            end
            local currentChannel = entries[excludeIndex] and entries[excludeIndex].channel
            local opts = {}
            for _, o in ipairs(ALL_CHANNEL_OPTIONS) do
                if not used[o.value] or o.value == currentChannel then
                    table.insert(opts, o)
                end
            end
            return opts
        end

        local section = body:GetParent()  -- reference to this collapsible section

        local function RebuildSoundEntries()
            soundEntriesContainer:SetHeight(0)
            for _, child in ipairs({ soundEntriesContainer:GetChildren() }) do
                child:Hide()
                child:SetParent(nil)
            end

            local entries = chat.newMessageSound.entries
            if not entries then return end

            local rowY = 0
            for i, entry in ipairs(entries) do
                local row = CreateFrame("Frame", nil, soundEntriesContainer)
                row:SetPoint("TOPLEFT", 0, -rowY)
                row:SetPoint("RIGHT", soundEntriesContainer, "RIGHT", 0, 0)
                row:SetHeight(FORM_ROW)

                local channelOpts = GetChannelOptionsForEntry(entries, i)
                if #channelOpts == 0 then
                    channelOpts = {{value = entry.channel or "guild_officer", text = entry.channel or "guild_officer"}}
                end

                local function OnChannelChange()
                    RefreshChat()
                    RebuildSoundEntries()
                end
                local channelDropdown = GUI:CreateFormDropdown(row, "Channel", channelOpts, "channel", entry, OnChannelChange)
                channelDropdown:SetPoint("TOPLEFT", 0, 0)
                channelDropdown:SetPoint("RIGHT", row, "RIGHT", -80, 0)

                local soundList = Shared.GetSoundList and Shared.GetSoundList() or {{value = "None", text = "None"}}
                local soundDropdown = GUI:CreateFormDropdown(row, "Sound", soundList, "sound", entry, RefreshChat)
                soundDropdown:SetPoint("TOPLEFT", 0, -FORM_ROW)
                soundDropdown:SetPoint("RIGHT", row, "RIGHT", -80, 0)

                local removeBtn = GUI:CreateButton(row, "X", 24, 22, function()
                    table.remove(entries, i)
                    RebuildSoundEntries()
                    RefreshChat()
                end)
                removeBtn:SetPoint("RIGHT", row, "RIGHT", 0, -FORM_ROW/2)

                row:SetHeight(FORM_ROW * 2)
                rowY = rowY + FORM_ROW * 2 + 4
            end

            soundEntriesContainer:SetHeight(rowY)

            local function GetFirstAvailableChannel()
                local used = {}
                for _, e in ipairs(chat.newMessageSound.entries) do
                    if e.channel then used[e.channel] = true end
                end
                for _, o in ipairs(ALL_CHANNEL_OPTIONS) do
                    if not used[o.value] then return o.value end
                end
                return nil
            end

            local nextChannel = GetFirstAvailableChannel()
            if nextChannel then
                local addBtn = GUI:CreateButton(soundEntriesContainer, "+ Add Channel + Sound", 180, 24, function()
                    local channel = GetFirstAvailableChannel()
                    if not channel then return end
                    table.insert(chat.newMessageSound.entries, { channel = channel, sound = "None" })
                    RebuildSoundEntries()
                    RefreshChat()
                end)
                addBtn:SetPoint("TOPLEFT", 0, -rowY - 4)
                rowY = rowY + 28
            end
            soundEntriesContainer:SetHeight(rowY)

            -- Update collapsible section height dynamically
            local totalHeight = FORM_ROW + 8 + rowY + 30
            section._contentHeight = totalHeight
            if section._expanded then
                section:SetHeight(24 + totalHeight)
                relayout()
            end
        end

        RebuildSoundEntries()

        local info = GUI:CreateLabel(body, "Each channel can have its own sound. Uses LibSharedMedia. Saved to your profile.", 10, C.textMuted)
        info:SetPoint("TOPLEFT", soundEntriesContainer, "BOTTOMLEFT", 0, -8)
        info:SetPoint("RIGHT", body, "RIGHT", 0, 0)
        info:SetJustifyH("LEFT")
    end)

    relayout()
end

ns.QUI_ChatOptions = {
    BuildChatTab = BuildChatTab,
}
