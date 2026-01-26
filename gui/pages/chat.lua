--[[
    QUI Options - Chat Tab
    BuildChatTab for General & QoL page
]]

local ADDON_NAME, ns = ...
local QUI = QUI
local GUI = QUI.GUI
local C = GUI.Colors

-- Import shared utilities
local Shared = ns.QUI_Options

local function BuildChatTab(tabContent)
    local y = -10
    local FORM_ROW = 32
    local PADDING = Shared.PADDING
    local db = Shared.GetDB()

    -- Set search context for auto-registration
    GUI:SetSearchContext({tabIndex = 1, tabName = "General & QoL", subTabIndex = 5, subTabName = "Chat"})

    -- Refresh callback
    local function RefreshChat()
        if _G.QUI_RefreshChat then
            _G.QUI_RefreshChat()
        end
    end

    if db and db.chat then
        local chat = db.chat

        -- SECTION: Enable/Disable
        local enableHeader = GUI:CreateSectionHeader(tabContent, "Enable/Disable QUI Chat Module")
        enableHeader:SetPoint("TOPLEFT", PADDING, y)
        y = y - enableHeader.gap

        local enableCheck = GUI:CreateFormCheckbox(tabContent, "QUI Chat Module", "enabled", chat, RefreshChat)
        enableCheck:SetPoint("TOPLEFT", PADDING, y)
        enableCheck:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
        y = y - FORM_ROW

        local enableInfo = GUI:CreateLabel(tabContent, "If you are using a dedicated chat addon, toggle this off.", 10, C.textMuted)
        enableInfo:SetPoint("TOPLEFT", PADDING, y)
        enableInfo:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
        enableInfo:SetJustifyH("LEFT")
        y = y - 20

        -- SECTION: Intro Message
        local introHeader = GUI:CreateSectionHeader(tabContent, "Intro Message")
        introHeader:SetPoint("TOPLEFT", PADDING, y)
        y = y - introHeader.gap

        local introCheck = GUI:CreateFormCheckbox(tabContent, "Show Login Message", "showIntroMessage", chat, nil)
        introCheck:SetPoint("TOPLEFT", PADDING, y)
        introCheck:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
        y = y - FORM_ROW

        local introInfo = GUI:CreateLabel(tabContent, "Display the QUI reminder tips when you log in.", 10, C.textMuted)
        introInfo:SetPoint("TOPLEFT", PADDING, y)
        introInfo:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
        introInfo:SetJustifyH("LEFT")
        y = y - 20

        -- SECTION: Chat Background
        local glassHeader = GUI:CreateSectionHeader(tabContent, "Chat Background")
        glassHeader:SetPoint("TOPLEFT", PADDING, y)
        y = y - glassHeader.gap

        if chat.glass then
            local glassCheck = GUI:CreateFormCheckbox(tabContent, "Chat Background Texture", "enabled", chat.glass, RefreshChat)
            glassCheck:SetPoint("TOPLEFT", PADDING, y)
            glassCheck:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
            y = y - FORM_ROW

            local alphaSlider = GUI:CreateFormSlider(tabContent, "Background Opacity", 0, 1.0, 0.05, "bgAlpha", chat.glass, RefreshChat)
            alphaSlider:SetPoint("TOPLEFT", PADDING, y)
            alphaSlider:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
            y = y - FORM_ROW

            local bgColorPicker = GUI:CreateFormColorPicker(tabContent, "Background Color", "bgColor", chat.glass, RefreshChat)
            bgColorPicker:SetPoint("TOPLEFT", PADDING, y)
            bgColorPicker:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
            y = y - FORM_ROW
        end

        -- SECTION: Input Box Background
        local editBoxHeader = GUI:CreateSectionHeader(tabContent, "Input Box Background")
        editBoxHeader:SetPoint("TOPLEFT", PADDING, y)
        y = y - editBoxHeader.gap

        if chat.editBox then
            local editBoxCheck = GUI:CreateFormCheckbox(tabContent, "Input Box Background Texture", "enabled", chat.editBox, RefreshChat)
            editBoxCheck:SetPoint("TOPLEFT", PADDING, y)
            editBoxCheck:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
            y = y - FORM_ROW

            local editBoxAlphaSlider = GUI:CreateFormSlider(tabContent, "Background Opacity", 0, 1.0, 0.05, "bgAlpha", chat.editBox, RefreshChat)
            editBoxAlphaSlider:SetPoint("TOPLEFT", PADDING, y)
            editBoxAlphaSlider:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
            y = y - FORM_ROW

            local editBoxColorPicker = GUI:CreateFormColorPicker(tabContent, "Background Color", "bgColor", chat.editBox, RefreshChat)
            editBoxColorPicker:SetPoint("TOPLEFT", PADDING, y)
            editBoxColorPicker:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
            y = y - FORM_ROW

            local positionTopCheck = GUI:CreateFormCheckbox(tabContent, "Position Input Box at Top", "positionTop", chat.editBox, RefreshChat)
            positionTopCheck:SetPoint("TOPLEFT", PADDING, y)
            positionTopCheck:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
            y = y - FORM_ROW

            local positionTopInfo = GUI:CreateLabel(tabContent, "Moves input box above chat tabs with opaque background.", 10, C.textMuted)
            positionTopInfo:SetPoint("TOPLEFT", PADDING, y)
            positionTopInfo:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
            positionTopInfo:SetJustifyH("LEFT")
            y = y - 20
        end

        -- SECTION: Message Fade
        local fadeHeader = GUI:CreateSectionHeader(tabContent, "Message Fade")
        fadeHeader:SetPoint("TOPLEFT", PADDING, y)
        y = y - fadeHeader.gap

        if chat.fade then
            local fadeCheck = GUI:CreateFormCheckbox(tabContent, "Fade Messages After Inactivity", "enabled", chat.fade, RefreshChat)
            fadeCheck:SetPoint("TOPLEFT", PADDING, y)
            fadeCheck:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
            y = y - FORM_ROW

            local delaySlider = GUI:CreateFormSlider(tabContent, "Fade Delay (seconds)", 1, 120, 1, "delay", chat.fade, RefreshChat)
            delaySlider:SetPoint("TOPLEFT", PADDING, y)
            delaySlider:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
            y = y - FORM_ROW
        end

        -- SECTION: URL Detection
        local urlHeader = GUI:CreateSectionHeader(tabContent, "URL Detection")
        urlHeader:SetPoint("TOPLEFT", PADDING, y)
        y = y - urlHeader.gap

        if chat.urls then
            local urlCheck = GUI:CreateFormCheckbox(tabContent, "Make URLs Clickable", "enabled", chat.urls, RefreshChat)
            urlCheck:SetPoint("TOPLEFT", PADDING, y)
            urlCheck:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
            y = y - FORM_ROW

            local urlInfo = GUI:CreateLabel(tabContent, "Click any URL in chat to open a copy dialog.", 10, C.textMuted)
            urlInfo:SetPoint("TOPLEFT", PADDING, y)
            urlInfo:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
            urlInfo:SetJustifyH("LEFT")
            y = y - 20
        end

        -- SECTION: Timestamps
        local timestampHeader = GUI:CreateSectionHeader(tabContent, "Timestamps")
        timestampHeader:SetPoint("TOPLEFT", PADDING, y)
        y = y - timestampHeader.gap

        if not chat.timestamps then chat.timestamps = {enabled = false, format = "24h", color = {0.6, 0.6, 0.6}} end

        local timestampCheck = GUI:CreateFormCheckbox(tabContent, "Show Timestamps", "enabled", chat.timestamps, RefreshChat)
        timestampCheck:SetPoint("TOPLEFT", PADDING, y)
        timestampCheck:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
        y = y - FORM_ROW

        local timestampInfo = GUI:CreateLabel(tabContent, "Timestamps only appear on new messages after enabling.", 10, C.textMuted)
        timestampInfo:SetPoint("TOPLEFT", PADDING, y)
        timestampInfo:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
        timestampInfo:SetJustifyH("LEFT")
        y = y - 20

        local formatOptions = {
            {value = "24h", text = "24-Hour (15:27)"},
            {value = "12h", text = "12-Hour (3:27 PM)"},
        }
        local formatDropdown = GUI:CreateFormDropdown(tabContent, "Format", formatOptions, "format", chat.timestamps, RefreshChat)
        formatDropdown:SetPoint("TOPLEFT", PADDING, y)
        formatDropdown:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
        y = y - FORM_ROW

        local timestampColorPicker = GUI:CreateFormColorPicker(tabContent, "Timestamp Color", "color", chat.timestamps, RefreshChat)
        timestampColorPicker:SetPoint("TOPLEFT", PADDING, y)
        timestampColorPicker:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
        y = y - FORM_ROW

        -- SECTION: UI Cleanup
        local cleanupHeader = GUI:CreateSectionHeader(tabContent, "UI Cleanup")
        cleanupHeader:SetPoint("TOPLEFT", PADDING, y)
        y = y - cleanupHeader.gap

        local hideButtonsCheck = GUI:CreateFormCheckbox(tabContent, "Hide Chat Buttons", "hideButtons", chat, RefreshChat)
        hideButtonsCheck:SetPoint("TOPLEFT", PADDING, y)
        hideButtonsCheck:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
        y = y - FORM_ROW

        local hideButtonsInfo = GUI:CreateLabel(tabContent, "Hides social, channel, and scroll buttons. Mouse wheel still scrolls.", 10, C.textMuted)
        hideButtonsInfo:SetPoint("TOPLEFT", PADDING, y)
        hideButtonsInfo:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
        hideButtonsInfo:SetJustifyH("LEFT")
        y = y - 20

        y = y - FORM_ROW

        -- SECTION: Copy Button
        local copyHeader = GUI:CreateSectionHeader(tabContent, "Copy Button")
        copyHeader:SetPoint("TOPLEFT", PADDING, y)
        y = y - copyHeader.gap

        local copyButtonOptions = {
            {value = "always", text = "Show Always"},
            {value = "hover", text = "Show on Hover"},
            {value = "disabled", text = "Disabled"},
        }
        local copyButtonDropdown = GUI:CreateFormDropdown(tabContent, "Copy Button", copyButtonOptions, "copyButtonMode", chat, RefreshChat)
        copyButtonDropdown:SetPoint("TOPLEFT", PADDING, y)
        copyButtonDropdown:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
        y = y - FORM_ROW

        local copyButtonInfo = GUI:CreateLabel(tabContent, "Controls the copy button on each chat frame for copying chat history.", 10, C.textMuted)
        copyButtonInfo:SetPoint("TOPLEFT", PADDING, y)
        copyButtonInfo:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
        copyButtonInfo:SetJustifyH("LEFT")
        y = y - 20
    end

    tabContent:SetHeight(math.abs(y) + 50)
end

-- Export
ns.QUI_ChatOptions = {
    BuildChatTab = BuildChatTab
}
