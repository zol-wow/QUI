--[[
    QUI Chat Shared Settings Providers
    Owns provider-backed Chat settings content in the shared settings layer for full pages and Layout Mode drawers.
]]

local ADDON_NAME, ns = ...

local Settings = ns.Settings
local ProviderPanels = Settings and Settings.ProviderPanels
if not ProviderPanels or type(ProviderPanels.RegisterAfterLoad) ~= "function" then
    return
end

ProviderPanels:RegisterAfterLoad(function(ctx)
    local GUI = ctx.GUI
    local U = ctx.U
    local P = ctx.P
    local FORM_ROW = ctx.FORM_ROW
    local NotifyProviderFor = ctx.NotifyProviderFor
    local CreateSingleColumnCollapsible = ctx.CreateSingleColumnCollapsible
    local function RegisterSharedOnly(key, provider)
        ctx.RegisterShared(key, provider)
    end

    ---------------------------------------------------------------------------
    -- CHAT
    ---------------------------------------------------------------------------
    RegisterSharedOnly("chatFrame1", { build = function(content, key, width)
        local db = U.GetProfileDB()
        if not db or not db.chat then return 80 end
        local chat = db.chat
        local sections = {}
        local function relayout() U.StandardRelayout(content, sections) end
        local function Refresh() if _G.QUI_RefreshChat then _G.QUI_RefreshChat() end end

        -- Frame Size drives ChatFrame1 directly via FCF_SetWindowSize, so
        -- Blizzard persists the dimensions in ChatConfig on logout. The proxy
        -- table lets CreateFormSlider read/write live frame dimensions.
        local sizeProxy = setmetatable({}, {
            __index = function(_, k)
                local f = _G.ChatFrame1
                if not f then return 0 end
                if k == "width" then return math.floor((f:GetWidth() or 0) + 0.5) end
                if k == "height" then return math.floor((f:GetHeight() or 0) + 0.5) end
                return 0
            end,
            __newindex = function(_, k, v)
                local f = _G.ChatFrame1
                if not f or type(v) ~= "number" then return end
                local w, h = f:GetWidth() or 0, f:GetHeight() or 0
                if k == "width" then w = v end
                if k == "height" then h = v end
                if _G.FCF_SetWindowSize then
                    _G.FCF_SetWindowSize(f, w, h)
                else
                    f:SetSize(w, h)
                end
                if _G.FCF_SavePositionAndDimensions then
                    _G.FCF_SavePositionAndDimensions(f)
                end
            end,
        })

        local widthSlider, heightSlider
        CreateSingleColumnCollapsible(content, "Frame Size", 2 * FORM_ROW + 8, function(body)
            local sy = -4
            widthSlider = GUI:CreateFormSlider(body, "Width", 296, 1400, 1, "width", sizeProxy, nil, nil, { description = "Pixel width of ChatFrame1. Blizzard persists this across logout." })
            sy = P(widthSlider, body, sy)
            heightSlider = GUI:CreateFormSlider(body, "Height", 120, 900, 1, "height", sizeProxy, nil, nil, { description = "Pixel height of ChatFrame1. Blizzard persists this across logout." })
            P(heightSlider, body, sy)
        end, sections, relayout)

        -- Expose a refresh hook so the corner-grip drag can sync slider positions.
        _G.QUI_RefreshChatSizeSliders = function()
            if widthSlider and widthSlider.SetValue then
                widthSlider:SetValue(sizeProxy.width)
            end
            if heightSlider and heightSlider.SetValue then
                heightSlider:SetValue(sizeProxy.height)
            end
        end

        -- Intro Message
        CreateSingleColumnCollapsible(content, "Intro Message", 2 * FORM_ROW + 8, function(body)
            local sy = -4
            sy = P(GUI:CreateFormCheckbox(body, "Show Login Message", "showIntroMessage", chat, nil, { description = "Display the QUI reminder/intro tips in chat when you log in." }), body, sy)
            local info = GUI:CreateLabel(body, "Display the QUI reminder tips when you log in.", 10, {0.5, 0.5, 0.5, 1})
            info:SetPoint("TOPLEFT", 0, sy)
            info:SetPoint("RIGHT", body, "RIGHT", 0, 0)
            info:SetJustifyH("LEFT")
        end, sections, relayout)

        -- Default Tab
        CreateSingleColumnCollapsible(content, "Default Tab", 3 * FORM_ROW + 8, function(body)
            -- Build tab options dynamically from current chat windows
            local tabOptions = {}
            for i = 1, NUM_CHAT_WINDOWS do
                local name = GetChatWindowInfo(i)
                if name and name ~= "" then
                    tabOptions[#tabOptions + 1] = {
                        value = i,
                        text = i .. ". " .. name,
                    }
                end
            end
            if #tabOptions == 0 then
                tabOptions[1] = { value = 1, text = "1. General" }
            end

            if not chat.defaultTabBySpec then chat.defaultTabBySpec = {} end

            local container = nil

            local function RebuildDefaultTab()
                -- Destroy previous container (clears children AND regions)
                if container then
                    container:Hide()
                    container:SetParent(nil)
                    container = nil
                end

                container = CreateFrame("Frame", nil, body)
                container:SetPoint("TOPLEFT", 0, 0)
                container:SetPoint("RIGHT", body, "RIGHT", 0, 0)
                container:SetHeight(1)

                local sy = -4

                if chat.defaultTabPerSpec then
                    -- Per-spec mode: all spec dropdowns tiled on one row
                    local specs = {}
                    local numSpecs = GetNumSpecializations and GetNumSpecializations() or 0
                    for s = 1, numSpecs do
                        local specID, specName = GetSpecializationInfo(s)
                        if specID and specName then
                            if not chat.defaultTabBySpec[specID] then
                                chat.defaultTabBySpec[specID] = 1
                            end
                            specs[#specs + 1] = { id = specID, name = specName }
                        end
                    end

                    local count = #specs
                    if count > 0 then
                        local GAP = 16
                        local LABEL_WIDTH = 80
                        local row = CreateFrame("Frame", nil, container)
                        row:SetPoint("TOPLEFT", 0, sy)
                        row:SetPoint("RIGHT", container, "RIGHT", 0, 0)
                        row:SetHeight(FORM_ROW)

                        -- Create equal-width column frames by chaining anchors
                        local columns = {}
                        for idx = 1, count do
                            local col = CreateFrame("Frame", nil, row)
                            col:SetPoint("TOP", 0, 0)
                            col:SetPoint("BOTTOM", 0, 0)
                            if idx == 1 then
                                col:SetPoint("LEFT", row, "LEFT", 0, 0)
                            else
                                col:SetPoint("LEFT", columns[idx - 1], "RIGHT", GAP, 0)
                            end
                            columns[idx] = col
                        end
                        -- Distribute column widths evenly via OnSizeChanged
                        local function DistributeColumns(w)
                            local colW = (w - GAP * (count - 1)) / count
                            for idx = 1, count do
                                columns[idx]:SetWidth(math.max(colW, 1))
                            end
                        end
                        row:SetScript("OnSizeChanged", function(self, w) DistributeColumns(w) end)
                        C_Timer.After(0, function()
                            local w = row:GetWidth()
                            if w and w > 0 then DistributeColumns(w) end
                        end)

                        -- Place a dropdown inside each column with compact label offset
                        for idx, spec in ipairs(specs) do
                            local dd = GUI:CreateFormDropdown(columns[idx], spec.name, tabOptions, spec.id, chat.defaultTabBySpec, Refresh, { description = "Chat tab to switch to when this spec is active, on login, reload, or spec change." })
                            dd:ClearAllPoints()
                            dd:SetPoint("TOPLEFT", 0, 0)
                            dd:SetPoint("RIGHT", columns[idx], "RIGHT", 0, 0)
                            -- Tighten label-to-dropdown gap (default is 180px)
                            local btn = select(1, dd:GetChildren())
                            if btn then
                                btn:ClearAllPoints()
                                btn:SetPoint("LEFT", dd, "LEFT", LABEL_WIDTH, 0)
                                btn:SetPoint("RIGHT", dd, "RIGHT", 0, 0)
                            end
                        end
                        sy = sy - FORM_ROW
                    end

                    local info = GUI:CreateLabel(container, "Each spec selects its own chat tab on login, reload, or spec switch.", 10, {0.5, 0.5, 0.5, 1})
                    info:SetPoint("TOPLEFT", 0, sy)
                    info:SetPoint("RIGHT", container, "RIGHT", 0, 0)
                    info:SetJustifyH("LEFT")
                    sy = sy - 20
                else
                    sy = P(GUI:CreateFormDropdown(container, "Default Tab", tabOptions, "defaultTab", chat, Refresh, { description = "Chat tab to make active on login and reload." }), container, sy)
                    local info = GUI:CreateLabel(container, "Select which chat tab is active when you log in or reload.", 10, {0.5, 0.5, 0.5, 1})
                    info:SetPoint("TOPLEFT", 0, sy)
                    info:SetPoint("RIGHT", container, "RIGHT", 0, 0)
                    info:SetJustifyH("LEFT")
                    sy = sy - 20
                end

                P(GUI:CreateFormCheckbox(container, "Per Spec", "defaultTabPerSpec", chat, function()
                    Refresh()
                    RebuildDefaultTab()
                end, { description = "Switch to per-spec default chat tabs instead of a single default. Each spec gets its own dropdown above." }), container, sy)
            end

            RebuildDefaultTab()
        end, sections, relayout)

        -- Chat Background
        if chat.glass then
            CreateSingleColumnCollapsible(content, "Chat Background", 3 * FORM_ROW + 8, function(body)
                local sy = -4
                sy = P(GUI:CreateFormCheckbox(body, "Chat Background Texture", "enabled", chat.glass, Refresh, { description = "Draw an opaque background behind the chat frame so text stays readable over busy scenery." }), body, sy)
                sy = P(GUI:CreateFormSlider(body, "Background Opacity", 0, 1.0, 0.05, "bgAlpha", chat.glass, Refresh, nil, { description = "Opacity of the chat background (0 is invisible, 1 is fully opaque)." }), body, sy)
                P(GUI:CreateFormColorPicker(body, "Background Color", "bgColor", chat.glass, Refresh, nil, { description = "Color of the chat background." }), body, sy)
            end, sections, relayout)
        end

        -- Input Box Background
        if chat.editBox then
            CreateSingleColumnCollapsible(content, "Input Box Background", 5 * FORM_ROW + 8, function(body)
                local sy = -4
                sy = P(GUI:CreateFormCheckbox(body, "Input Box Background Texture", "enabled", chat.editBox, Refresh, { description = "Draw an opaque background behind the chat input box for better contrast while typing." }), body, sy)
                sy = P(GUI:CreateFormSlider(body, "Background Opacity", 0, 1.0, 0.05, "bgAlpha", chat.editBox, Refresh, nil, { description = "Opacity of the input box background (0 is invisible, 1 is fully opaque)." }), body, sy)
                sy = P(GUI:CreateFormColorPicker(body, "Background Color", "bgColor", chat.editBox, Refresh, nil, { description = "Color of the input box background." }), body, sy)
                sy = P(GUI:CreateFormCheckbox(body, "Position Input Box at Top", "positionTop", chat.editBox, Refresh, { description = "Move the input box above the chat tabs instead of below the chat frame." }), body, sy)
                local info = GUI:CreateLabel(body, "Moves input box above chat tabs with opaque background.", 10, {0.5, 0.5, 0.5, 1})
                info:SetPoint("TOPLEFT", 0, sy)
                info:SetPoint("RIGHT", body, "RIGHT", 0, 0)
                info:SetJustifyH("LEFT")
            end, sections, relayout)
        end

        -- Message Fade
        if chat.fade then
            CreateSingleColumnCollapsible(content, "Message Fade", 2 * FORM_ROW + 8, function(body)
                local sy = -4
                sy = P(GUI:CreateFormCheckbox(body, "Fade Messages After Inactivity", "enabled", chat.fade, Refresh, { description = "Fade old chat messages out after no new messages have arrived for the delay below." }), body, sy)
                P(GUI:CreateFormSlider(body, "Fade Delay (seconds)", 1, 120, 1, "delay", chat.fade, Refresh, nil, { description = "Seconds of inactivity before chat messages start fading." }), body, sy)
            end, sections, relayout)
        end

        -- URL Detection
        if chat.urls then
            CreateSingleColumnCollapsible(content, "URL Detection", 2 * FORM_ROW + 8, function(body)
                local sy = -4
                sy = P(GUI:CreateFormCheckbox(body, "Make URLs Clickable", "enabled", chat.urls, Refresh, { description = "Detect URLs in chat and click them to open a copy dialog." }), body, sy)
                local info = GUI:CreateLabel(body, "Click any URL in chat to open a copy dialog.", 10, {0.5, 0.5, 0.5, 1})
                info:SetPoint("TOPLEFT", 0, sy)
                info:SetPoint("RIGHT", body, "RIGHT", 0, 0)
                info:SetJustifyH("LEFT")
            end, sections, relayout)
        end

        -- Timestamps
        CreateSingleColumnCollapsible(content, "Timestamps", 4 * FORM_ROW + 8, function(body)
            local sy = -4
            if not chat.timestamps then chat.timestamps = {enabled = false, format = "24h", color = {0.6, 0.6, 0.6}} end
            sy = P(GUI:CreateFormCheckbox(body, "Show Timestamps", "enabled", chat.timestamps, Refresh, { description = "Prepend a timestamp to each new chat message. Existing messages in the frame are not retroactively stamped." }), body, sy)
            local info = GUI:CreateLabel(body, "Timestamps only appear on new messages after enabling.", 10, {0.5, 0.5, 0.5, 1})
            info:SetPoint("TOPLEFT", 0, sy)
            info:SetPoint("RIGHT", body, "RIGHT", 0, 0)
            info:SetJustifyH("LEFT")
            sy = sy - 20
            local formatOptions = {
                {value = "24h", text = "24-Hour (15:27)"},
                {value = "12h", text = "12-Hour (3:27 PM)"},
            }
            sy = P(GUI:CreateFormDropdown(body, "Format", formatOptions, "format", chat.timestamps, Refresh, { description = "Timestamp format: 24-hour (15:27) or 12-hour with AM/PM (3:27 PM)." }), body, sy)
            P(GUI:CreateFormColorPicker(body, "Timestamp Color", "color", chat.timestamps, Refresh, nil, { description = "Color of the timestamp prefix on chat messages." }), body, sy)
        end, sections, relayout)

        -- UI Cleanup
        CreateSingleColumnCollapsible(content, "UI Cleanup", 2 * FORM_ROW + 8, function(body)
            local sy = -4
            sy = P(GUI:CreateFormCheckbox(body, "Hide Chat Buttons", "hideButtons", chat, Refresh, { description = "Hide the social, channel, and scroll buttons on each chat frame. Mouse wheel still scrolls." }), body, sy)
            local info = GUI:CreateLabel(body, "Hides social, channel, and scroll buttons. Mouse wheel still scrolls.", 10, {0.5, 0.5, 0.5, 1})
            info:SetPoint("TOPLEFT", 0, sy)
            info:SetPoint("RIGHT", body, "RIGHT", 0, 0)
            info:SetJustifyH("LEFT")
        end, sections, relayout)

        -- Copy Button
        CreateSingleColumnCollapsible(content, "Copy Button", 2 * FORM_ROW + 8, function(body)
            local sy = -4
            local copyButtonOptions = {
                {value = "always", text = "Show Always"},
                {value = "hover", text = "Show on Hover"},
                {value = "disabled", text = "Disabled"},
            }
            sy = P(GUI:CreateFormDropdown(body, "Copy Button", copyButtonOptions, "copyButtonMode", chat, Refresh, { description = "When the per-frame copy button is shown: always visible, only on hover, or disabled entirely." }), body, sy)
            local info = GUI:CreateLabel(body, "Controls the copy button on each chat frame for copying chat history.", 10, {0.5, 0.5, 0.5, 1})
            info:SetPoint("TOPLEFT", 0, sy)
            info:SetPoint("RIGHT", body, "RIGHT", 0, 0)
            info:SetJustifyH("LEFT")
        end, sections, relayout)

        -- Message History
        CreateSingleColumnCollapsible(content, "Message History", 2 * FORM_ROW + 8, function(body)
            local sy = -4
            if not chat.messageHistory then
                chat.messageHistory = { enabled = true, maxHistory = 50 }
            end
            sy = P(GUI:CreateFormCheckbox(body, "Enable Message History", "enabled", chat.messageHistory, Refresh, { description = "Let the Up/Down arrow keys navigate through your recently sent messages while the chat input is focused." }), body, sy)
            local info = GUI:CreateLabel(body, "Use arrow keys (Up/Down) to navigate through your sent message history while typing.", 10, {0.5, 0.5, 0.5, 1})
            info:SetPoint("TOPLEFT", 0, sy)
            info:SetPoint("RIGHT", body, "RIGHT", 0, 0)
            info:SetJustifyH("LEFT")
        end, sections, relayout)

        -- New Message Sound
        CreateSingleColumnCollapsible(content, "New Message Sound", 1, function(body)
            local sy = -4
            if not chat.newMessageSound then
                chat.newMessageSound = { enabled = false, entries = {{ channel = "guild_officer", sound = "None" }} }
            end
            if not chat.newMessageSound.entries or #chat.newMessageSound.entries == 0 then
                chat.newMessageSound.entries = {{ channel = "guild_officer", sound = "None" }}
            end

            sy = P(GUI:CreateFormCheckbox(body, "Play Sound on New Message", "enabled", chat.newMessageSound, Refresh, { description = "Master toggle for playing sounds on incoming chat messages. Configure per-channel sounds below." }), body, sy)

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
                        opts[#opts + 1] = o
                    end
                end
                return opts
            end

            local section = body:GetParent()

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
                        Refresh()
                        RebuildSoundEntries()
                    end
                    local channelDropdown = GUI:CreateFormDropdown(row, "Channel", channelOpts, "channel", entry, OnChannelChange, { description = "Chat channel this sound entry listens for. Each channel can only be assigned to one entry." })
                    if GUI.SetWidgetProviderSyncOptions then
                        GUI:SetWidgetProviderSyncOptions(channelDropdown, { auto = true, structural = true })
                    end
                    channelDropdown:SetPoint("TOPLEFT", 0, 0)
                    channelDropdown:SetPoint("RIGHT", row, "RIGHT", -80, 0)

                    local soundList = U.GetSoundList()
                    local soundDropdown = GUI:CreateFormDropdown(row, "Sound", soundList, "sound", entry, Refresh, { description = "Sound to play when a message arrives on this channel." })
                    soundDropdown:SetPoint("TOPLEFT", 0, -FORM_ROW)
                    soundDropdown:SetPoint("RIGHT", row, "RIGHT", -80, 0)

                    local removeBtn = GUI:CreateButton(row, "X", 24, 22, function()
                        table.remove(entries, i)
                        RebuildSoundEntries()
                        Refresh()
                        NotifyProviderFor(removeBtn, { structural = true })
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
                        Refresh()
                        NotifyProviderFor(addBtn, { structural = true })
                    end)
                    addBtn:SetPoint("TOPLEFT", 0, -rowY - 4)
                    rowY = rowY + 28
                end
                soundEntriesContainer:SetHeight(rowY)

                local totalHeight = FORM_ROW + 8 + rowY + 30
                section._contentHeight = totalHeight
                if section._expanded then
                    section:SetHeight(24 + totalHeight)
                    relayout()
                end
            end

            RebuildSoundEntries()

            local info = GUI:CreateLabel(body, "Each channel can have its own sound. Saved to your profile.", 10, {0.5, 0.5, 0.5, 1})
            info:SetPoint("TOPLEFT", soundEntriesContainer, "BOTTOMLEFT", 0, -8)
            info:SetPoint("RIGHT", body, "RIGHT", 0, 0)
            info:SetJustifyH("LEFT")
        end, sections, relayout)

        U.BuildPositionCollapsible(content, "chatFrame1", nil, sections, relayout)
        U.BuildOpenFullSettingsLink(content, key, sections, relayout)
        relayout() return content:GetHeight()
    end })
end)
