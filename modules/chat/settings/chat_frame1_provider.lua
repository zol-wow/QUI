--[[
    QUI Chat Shared Settings Providers
    Owns provider-backed Chat settings content in the shared settings layer for full pages and Layout Mode drawers.
]]

local ADDON_NAME, ns = ...

local Settings = ns.Settings
local ProviderPanels = Settings and Settings.ProviderPanels
local Helpers = ns.Helpers
if not ProviderPanels or type(ProviderPanels.RegisterAfterLoad) ~= "function" then
    return
end

local function IsChatLayoutLockedDown()
    local I = ns.QUI and ns.QUI.Chat and ns.QUI.Chat._internals
    return (type(InCombatLockdown) == "function" and InCombatLockdown())
        or (I and I.IsChatMessagingLockedDown and I.IsChatMessagingLockedDown())
end

local function SafeFrameNumber(value, fallback)
    if Helpers and Helpers.IsSecretValue and Helpers.IsSecretValue(value) then
        return fallback or 0
    end
    return tonumber(value) or fallback or 0
end

ProviderPanels:RegisterAfterLoad(function(ctx)
    local GUI = ctx.GUI
    local U = ctx.U
    -- V2 row-placement helper retained for legacy custom-block bodies
    -- (Tab Filters, Button Bar, Channel Colors, Persistent History, New
    -- Message Sound) where row-by-row anchoring is still simpler than
    -- adapting the V3 paired-row card pattern.
    local P = ctx.P
    local FORM_ROW = ctx.FORM_ROW
    local NotifyProviderFor = ctx.NotifyProviderFor
    local PAD = (ns.QUI_Options and ns.QUI_Options.PADDING) or 15
    local HEADER_GAP = 26
    local SECTION_GAP = 14
    local function RegisterSharedOnly(providerKey, provider)
        ctx.RegisterShared(providerKey, provider)
    end

    -- V3 layout helper. Mirrors the minimap_providers.lua / qol_content.lua
    -- shape: headerAt / sectionAt / closeSection / placeCustom drive a single
    -- y cursor while sections{}/relayoutSections support legacy V2 collapsibles
    -- (Position, OpenFullSettings) at the bottom of the panel.
    local function MakeLayout(content)
        local Opts = ns.QUI_Options
        local y = -10
        local L = {}
        local sections = {}
        function L.headerAt(text)
            local h = Opts.CreateAccentDotLabel(content, text, y)
            h:ClearAllPoints()
            h:SetPoint("TOPLEFT", content, "TOPLEFT", PAD, y)
            h:SetPoint("TOPRIGHT", content, "TOPRIGHT", -PAD, y)
            y = y - HEADER_GAP
        end
        function L.sectionAt()
            local c = Opts.CreateSettingsCardGroup(content, y)
            c.frame:ClearAllPoints()
            c.frame:SetPoint("TOPLEFT", content, "TOPLEFT", PAD, y)
            c.frame:SetPoint("TOPRIGHT", content, "TOPRIGHT", -PAD, y)
            return c
        end
        function L.closeSection(c)
            c.Finalize()
            y = y - c.frame:GetHeight() - SECTION_GAP
        end
        function L.placeCustom(frame, height)
            frame:ClearAllPoints()
            frame:SetPoint("TOPLEFT", content, "TOPLEFT", PAD, y)
            frame:SetPoint("RIGHT", content, "RIGHT", -PAD, 0)
            frame:SetHeight(height)
            y = y - height - SECTION_GAP
        end
        local function relayoutSections()
            local cy = y
            for _, s in ipairs(sections) do
                s:ClearAllPoints()
                s:SetPoint("TOPLEFT", content, "TOPLEFT", PAD, cy)
                s:SetPoint("RIGHT", content, "RIGHT", -PAD, 0)
                cy = cy - s:GetHeight() - 4
            end
            content:SetHeight(math.abs(cy) + 16)
        end
        L.sections = sections
        L.relayoutSections = relayoutSections
        function L.getY() return y end
        function L.setY(newY) y = newY end
        return L
    end

    local function row(parent, label, widget, desc)
        return ns.QUI_Options.BuildSettingRow(parent, label, widget, desc)
    end

    ---------------------------------------------------------------------------
    -- Multi-frame editor state. These upvalues persist across structural
    -- rebuilds of the chat panel — the build closure is recreated on each
    -- NotifyProviderFor({ structural = true }), but RegisterAfterLoad's outer
    -- closure runs once per session, so frame-selection survives the rebuild.
    ---------------------------------------------------------------------------
    local selectedTabFilterFrame = 1
    local selectedButtonBarFrame = 1

    local function MarkTransientOptionsBinding(tableRef)
        if type(tableRef) == "table" then
            rawset(tableRef, "_quiTransientOptionsProxy", true)
        end
        return tableRef
    end

    local function SetControlEnabled(control, enabled)
        if not control then
            return
        end

        enabled = enabled and true or false
        if type(control.SetEnabled) == "function" then
            control:SetEnabled(enabled)
            return
        end

        if type(control.EnableMouse) == "function" then
            control:EnableMouse(enabled)
        end
        if type(control.SetAlpha) == "function" then
            control:SetAlpha(enabled and 1 or 0.4)
        end
    end

    -- Build dropdown options for the per-frame editor selectors. Excludes
    -- combat log frames — neither tab filters nor a custom button bar make
    -- sense on a frame whose purpose is the system-driven combat-log feed.
    -- WoW preallocates all NUM_CHAT_WINDOWS frames, so _G["ChatFrame3"]
    -- survives FCF_Close. The NAME from GetChatWindowInfo also persists
    -- across FCF_Close (the saved variable is never cleared), so the
    -- canonical "is this slot active?" check is FCF_IsChatWindowIndexActive
    -- — Blizzard's own active-window iterator (see Shared/FloatingChatFrame.lua)
    -- consults the `shown` flag (7th return of GetChatWindowInfo) and the
    -- frame's `isDocked` state.
    local function IsChatWindowSlotActive(i, f)
        if type(_G.FCF_IsChatWindowIndexActive) == "function" then
            local ok, active = pcall(_G.FCF_IsChatWindowIndexActive, i)
            if ok then return active and true or false end
        end
        -- Fallback for older clients: read `shown` directly, then dock state.
        if type(GetChatWindowInfo) == "function" then
            local shown = select(7, GetChatWindowInfo(i))
            if shown then return true end
        end
        return f and f.isDocked and true or false
    end

    local function buildFrameOptions()
        local opts = {}
        local I = ns.QUI and ns.QUI.Chat and ns.QUI.Chat._internals
        local n = _G.NUM_CHAT_WINDOWS or 10
        for i = 1, n do
            local f = _G["ChatFrame" .. i]
            local name = GetChatWindowInfo(i)
            local isTemporary = f and (
                f.isTemporary
                or f.privateMessageList
                or (I and I.IsTemporaryChatFrame and I.IsTemporaryChatFrame(f))
            )
            if f and not f.isCombatLog and not isTemporary and not f.privateMessageList
                and IsChatWindowSlotActive(i, f)
                and type(name) == "string" and name ~= "" then
                opts[#opts + 1] = { value = i, text = "ChatFrame" .. i .. " (" .. name .. ")" }
            end
        end
        if #opts == 0 then  -- defensive: always offer at least ChatFrame1
            opts[1] = { value = 1, text = "ChatFrame1" }
        end
        return opts
    end

    ---------------------------------------------------------------------------
    -- CHAT
    ---------------------------------------------------------------------------
    RegisterSharedOnly("chatFrame1", { build = function(content, key, _width, options)
        local db = U.GetProfileDB()
        if not db or not db.chat or not ns.QUI_Options then return 80 end
        local chat = db.chat
        local L = MakeLayout(content)
        local function Refresh() if _G.QUI_RefreshChat then _G.QUI_RefreshChat() end end

        local sectionPresets = {
            general = {
                "chatModule", "frameSize", "introMessage", "defaultTab",
                "chatBackground", "inputBoxBackground", "messageFade",
                "urlDetection", "chatHyperlinks",
                "channelColors",
                "uiCleanup", "copyButton",
            },
            filters = { "tabFilters" },
            buttonBar = { "buttonBar" },
            alerts = {
                "timestamps", "messageModifiers", "keywordAlert",
                "redundantTextCleanup", "newMessageSound",
            },
            history = {
                "messageHistory", "commandHistory", "persistentMessageHistory",
            },
        }

        local function BuildSectionFilter(value)
            if value == nil then return nil end
            if type(value) == "string" then
                value = sectionPresets[value] or { value }
            end
            if type(value) ~= "table" then return nil end

            local filter = {}
            for _, sectionId in ipairs(value) do
                if type(sectionId) == "string" and sectionId ~= "" then
                    filter[sectionId] = true
                end
            end
            return next(filter) and filter or nil
        end

        local sectionFilter = BuildSectionFilter(options and options.chatSections)
        local function ShouldRenderSection(sectionId)
            return not sectionFilter or sectionFilter[sectionId] == true
        end

        -- V3 section emitter: an accent-dot header + card group replaces the
        -- V2 collapsible chrome. buildFunc(card) receives the
        -- CreateSettingsCardGroup return value; widgets attach to card.frame
        -- and rows are added via card.AddRow.
        local function CreateChatSection(sectionId, title, _contentHeight, buildFunc)
            if not ShouldRenderSection(sectionId) then
                return nil
            end
            L.headerAt(title)
            local card = L.sectionAt()
            buildFunc(card)
            L.closeSection(card)
            return card
        end

        -- Custom-block variant for sections whose content cannot fit the V3
        -- paired-row card pattern (dynamic editors, multi-column distributors,
        -- per-row inline buttons). Renders an accent-dot header followed by a
        -- bare container placed with L.placeCustom — no card chrome.
        local function CreateChatCustomSection(sectionId, title, buildFunc, defaultHeight)
            if not ShouldRenderSection(sectionId) then
                return nil
            end
            L.headerAt(title)
            local container = CreateFrame("Frame", nil, content)
            -- Anchor at current y so children can use the container's body.
            -- L.placeCustom is invoked after buildFunc computes the final
            -- height; we provide a temporary anchor in the meantime so that
            -- relative TOPLEFT children render correctly during build.
            container:SetPoint("TOPLEFT", content, "TOPLEFT", PAD, L.getY())
            container:SetPoint("RIGHT", content, "RIGHT", -PAD, 0)
            container:SetHeight(defaultHeight or 1)
            local measuredHeight = buildFunc(container) or defaultHeight or 1
            L.placeCustom(container, math.max(8, measuredHeight))
            return container
        end

        -- Frame Size drives ChatFrame1 directly via FCF_SetWindowSize, so
        -- Blizzard persists the dimensions in ChatConfig on logout. The proxy
        -- table lets CreateFormSlider read/write live frame dimensions.
        local sizeProxy = MarkTransientOptionsBinding(setmetatable({}, {
            __index = function(_, k)
                local f = _G.ChatFrame1
                if not f then return 0 end
                if k == "width" then return math.floor(SafeFrameNumber(f:GetWidth(), 0) + 0.5) end
                if k == "height" then return math.floor(SafeFrameNumber(f:GetHeight(), 0) + 0.5) end
                return 0
            end,
            __newindex = function(_, k, v)
                local f = _G.ChatFrame1
                if not f or type(v) ~= "number" then return end
                if IsChatLayoutLockedDown() then return end
                local w, h = SafeFrameNumber(f:GetWidth(), 0), SafeFrameNumber(f:GetHeight(), 0)
                if k == "width" then w = v end
                if k == "height" then h = v end
                local sizing = ns.QUI and ns.QUI.ChatFrame1Sizing
                if sizing and sizing.SetSize then
                    sizing.SetSize(w, h)
                else
                    if _G.FCF_SetWindowSize then
                        _G.FCF_SetWindowSize(f, w, h)
                    else
                        f:SetSize(w, h)
                    end
                    if _G.FCF_SavePositionAndDimensions then
                        _G.FCF_SavePositionAndDimensions(f)
                    end
                end
            end,
        }))

        -- Master enable toggle. Disabling tears down all chat customization
        -- (glass, tabs, edit box, copy buttons, fade, message filters); the
        -- per-feature toggles below remain visible but no-op until re-enabled.
        CreateChatSection("chatModule", "Chat Module", FORM_ROW + 8, function(card)
            local w = GUI:CreateFormCheckbox(card.frame, nil, "enabled", chat, Refresh, { description = "Master switch for QUI's chat customization. When off, all chat frames revert to Blizzard defaults and the per-feature toggles below have no effect." })
            card.AddRow(row(card.frame, "Enable Chat Module", w))
        end)

        local widthSlider, heightSlider
        CreateChatSection("frameSize", "Frame Size", 2 * FORM_ROW + 8, function(card)
            widthSlider = GUI:CreateFormSlider(card.frame, nil, 296, 1400, 1, "width", sizeProxy, nil, { description = "Pixel width of ChatFrame1. Blizzard persists this across logout." })
            heightSlider = GUI:CreateFormSlider(card.frame, nil, 120, 900, 1, "height", sizeProxy, nil, { description = "Pixel height of ChatFrame1. Blizzard persists this across logout." })
            card.AddRow(row(card.frame, "Width", widthSlider), row(card.frame, "Height", heightSlider))
        end)

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
        CreateChatSection("introMessage", "Intro Message", 2 * FORM_ROW + 8, function(card)
            local w = GUI:CreateFormCheckbox(card.frame, nil, "showIntroMessage", chat, nil, { description = "Display the QUI reminder/intro tips in chat when you log in." })
            card.AddRow(row(card.frame, "Show Login Message", w))
        end)

        -- Default Tab
        -- Rendered as a custom block (placeCustom) because RebuildDefaultTab
        -- emits a dynamic, equal-width column distributor for per-spec mode
        -- that does not fit the V3 paired-row pattern. The block lives just
        -- below an accent-dot header but outside any card chrome.
        CreateChatCustomSection("defaultTab", "Default Tab", function(body)
            -- Build tab options dynamically from currently-active chat windows.
            -- See IsChatWindowSlotActive above — name persistence across
            -- FCF_Close means we can't use `name ~= ""` as the active filter.
            local tabOptions = {}
            for i = 1, NUM_CHAT_WINDOWS do
                local f = _G["ChatFrame" .. i]
                local name = GetChatWindowInfo(i)
                if IsChatWindowSlotActive(i, f) and type(name) == "string" and name ~= "" then
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
            local finalHeight = FORM_ROW

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
                        local rowFrame = CreateFrame("Frame", nil, container)
                        rowFrame:SetPoint("TOPLEFT", 0, sy)
                        rowFrame:SetPoint("RIGHT", container, "RIGHT", 0, 0)
                        rowFrame:SetHeight(FORM_ROW)

                        -- Create equal-width column frames by chaining anchors
                        local columns = {}
                        for idx = 1, count do
                            local col = CreateFrame("Frame", nil, rowFrame)
                            col:SetPoint("TOP", 0, 0)
                            col:SetPoint("BOTTOM", 0, 0)
                            if idx == 1 then
                                col:SetPoint("LEFT", rowFrame, "LEFT", 0, 0)
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
                        rowFrame:SetScript("OnSizeChanged", function(self, w) DistributeColumns(w) end)
                        C_Timer.After(0, function()
                            local w = rowFrame:GetWidth()
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
                    local dd = GUI:CreateFormDropdown(container, "Default Tab", tabOptions, "defaultTab", chat, Refresh, { description = "Chat tab to make active on login and reload." })
                    dd:SetPoint("TOPLEFT", 0, sy)
                    dd:SetPoint("RIGHT", container, "RIGHT", 0, 0)
                    sy = sy - FORM_ROW
                    local info = GUI:CreateLabel(container, "Select which chat tab is active when you log in or reload.", 10, {0.5, 0.5, 0.5, 1})
                    info:SetPoint("TOPLEFT", 0, sy)
                    info:SetPoint("RIGHT", container, "RIGHT", 0, 0)
                    info:SetJustifyH("LEFT")
                    sy = sy - 20
                end

                local perSpecCheck
                perSpecCheck = GUI:CreateFormCheckbox(container, "Per Spec", "defaultTabPerSpec", chat, function()
                    Refresh()
                    NotifyProviderFor(perSpecCheck, { structural = true })
                    RebuildDefaultTab()
                end, { description = "Switch to per-spec default chat tabs instead of a single default. Each spec gets its own dropdown above." })
                perSpecCheck:SetPoint("TOPLEFT", 0, sy)
                perSpecCheck:SetPoint("RIGHT", container, "RIGHT", 0, 0)
                sy = sy - FORM_ROW

                local containerHeight = math.max(FORM_ROW, math.abs(sy) + 4)
                container:SetHeight(containerHeight)
                finalHeight = containerHeight
                body:SetHeight(containerHeight)
            end

            RebuildDefaultTab()
            return finalHeight
        end, 3 * FORM_ROW + 8)

        -- Chat Background
        if chat.glass then
            CreateChatSection("chatBackground", "Chat Background", 3 * FORM_ROW + 8, function(card)
                local bgAlphaSlider, bgColorPicker
                local function UpdateChatBackgroundStates()
                    local enabled = chat.glass.enabled == true
                    SetControlEnabled(bgAlphaSlider, enabled)
                    SetControlEnabled(bgColorPicker, enabled)
                end
                local bgEnableCheckbox = GUI:CreateFormCheckbox(card.frame, nil, "enabled", chat.glass, function()
                    Refresh()
                    UpdateChatBackgroundStates()
                end, { description = "Draw an opaque background behind the chat frame so text stays readable over busy scenery." })
                bgAlphaSlider = GUI:CreateFormSlider(card.frame, nil, 0, 1.0, 0.05, "bgAlpha", chat.glass, Refresh, { description = "Opacity of the chat background (0 is invisible, 1 is fully opaque)." })
                card.AddRow(row(card.frame, "Chat Background Texture", bgEnableCheckbox), row(card.frame, "Background Opacity", bgAlphaSlider))
                bgColorPicker = GUI:CreateFormColorPicker(card.frame, nil, "bgColor", chat.glass, Refresh, nil, { description = "Color of the chat background." })
                card.AddRow(row(card.frame, "Background Color", bgColorPicker))
                UpdateChatBackgroundStates()
            end)
        end

        -- Input Box Background
        if chat.editBox then
            CreateChatSection("inputBoxBackground", "Input Box Background", 5 * FORM_ROW + 8, function(card)
                local inputAlphaSlider, inputColorPicker, inputPositionCheckbox
                local function UpdateInputBackgroundStates()
                    local enabled = chat.editBox.enabled == true
                    SetControlEnabled(inputAlphaSlider, enabled)
                    SetControlEnabled(inputColorPicker, enabled)
                    SetControlEnabled(inputPositionCheckbox, enabled)
                end
                local inputEnableCheckbox = GUI:CreateFormCheckbox(card.frame, nil, "enabled", chat.editBox, function()
                    Refresh()
                    UpdateInputBackgroundStates()
                end, { description = "Draw an opaque background behind the chat input box for better contrast while typing." })
                inputAlphaSlider = GUI:CreateFormSlider(card.frame, nil, 0, 1.0, 0.05, "bgAlpha", chat.editBox, Refresh, { description = "Opacity of the input box background (0 is invisible, 1 is fully opaque)." })
                card.AddRow(row(card.frame, "Input Box Background Texture", inputEnableCheckbox), row(card.frame, "Background Opacity", inputAlphaSlider))
                inputColorPicker = GUI:CreateFormColorPicker(card.frame, nil, "bgColor", chat.editBox, Refresh, nil, { description = "Color of the input box background." })
                inputPositionCheckbox = GUI:CreateFormCheckbox(card.frame, nil, "positionTop", chat.editBox, Refresh, { description = "Move the input box above the chat tabs instead of below the chat frame." })
                card.AddRow(row(card.frame, "Background Color", inputColorPicker), row(card.frame, "Position Input Box at Top", inputPositionCheckbox))
                UpdateInputBackgroundStates()
            end)
        end

        -- Message History
        -- In-memory Up/Down arrow recall during a session. Renders first on
        -- the History tab so the simpler arrow-recall toggle leads, with the
        -- persistent-across-/reload variant (Command History) following.
        CreateChatSection("messageHistory", "Message History", 2 * FORM_ROW + 8, function(card)
            if not chat.messageHistory then
                chat.messageHistory = { enabled = true, maxHistory = 50 }
            end
            local w = GUI:CreateFormCheckbox(card.frame, nil, "enabled", chat.messageHistory, Refresh, { description = "Let the Up/Down arrow keys navigate through your recently sent messages while the chat input is focused." })
            card.AddRow(row(card.frame, "Enable Message History", w))
        end)

        -- Command History (Phase C)
        -- Persistent Up/Down arrow recall. Settings live on the profile;
        -- the captured entries are per-character at
        -- db.char.chat.editboxHistory.entries (initialized lazily by
        -- editbox_history.lua's getStore on first capture or recall).
        CreateChatSection("commandHistory", "Command History", 4 * FORM_ROW + 8, function(card)
            if not chat.editboxHistory then
                chat.editboxHistory = {
                    enabled = true,
                    maxEntries = 200,
                    filterSensitive = true,
                    restoreChatType = true,
                }
            end
            local ebh = chat.editboxHistory

            local historyControls = {}
            local function TrackHistoryControl(control)
                historyControls[#historyControls + 1] = control
                return control
            end
            local function UpdateCommandHistoryStates()
                local enabled = ebh.enabled == true
                for i = 1, #historyControls do
                    SetControlEnabled(historyControls[i], enabled)
                end
            end
            local historyCheckbox = GUI:CreateFormCheckbox(card.frame, nil, "enabled", ebh, function()
                Refresh()
                UpdateCommandHistoryStates()
            end, { description = "Save messages you send so the Up/Down arrows recall them after a /reload. Stored per-character. Disabling stops new captures and recall but does not delete prior entries." })
            local maxEntriesSlider = TrackHistoryControl(GUI:CreateFormSlider(card.frame, nil, 50, 500, 1, "maxEntries", ebh, Refresh, { description = "Maximum number of recalled messages to keep per character. Oldest entries are dropped first when the cap is reached." }))
            card.AddRow(row(card.frame, "Persistent command history", historyCheckbox), row(card.frame, "Max command history", maxEntriesSlider))
            local filterSensitiveCb = TrackHistoryControl(GUI:CreateFormCheckbox(card.frame, nil, "filterSensitive", ebh, Refresh, { description = "Skip storing commands that frequently contain secrets or raw Lua. Filtered prefixes: /password, /logout, /quit, /exit, /dnd, /afk, /camp, /script, /run, /console." }))
            local restoreTypeCb = TrackHistoryControl(GUI:CreateFormCheckbox(card.frame, nil, "restoreChatType", ebh, Refresh, { description = "When recalling a message with Up/Down, also restore its original chat type (Say, Yell, Whisper target, channel) so pressing Enter sends to the same destination." }))
            card.AddRow(row(card.frame, "Filter sensitive commands", filterSensitiveCb), row(card.frame, "Restore chat type on recall", restoreTypeCb))
            UpdateCommandHistoryStates()
        end)

        -- Message Fade
        if chat.fade then
            CreateChatSection("messageFade", "Message Fade", 2 * FORM_ROW + 8, function(card)
                local fadeDelaySlider
                local function UpdateFadeStates()
                    SetControlEnabled(fadeDelaySlider, chat.fade.enabled == true)
                end
                local fadeCheckbox = GUI:CreateFormCheckbox(card.frame, nil, "enabled", chat.fade, function()
                    Refresh()
                    UpdateFadeStates()
                end, { description = "Fade old chat messages out after no new messages have arrived for the delay below." })
                fadeDelaySlider = GUI:CreateFormSlider(card.frame, nil, 1, 120, 1, "delay", chat.fade, Refresh, { description = "Seconds of inactivity before chat messages start fading." })
                card.AddRow(row(card.frame, "Fade Messages After Inactivity", fadeCheckbox), row(card.frame, "Fade Delay (seconds)", fadeDelaySlider))
                UpdateFadeStates()
            end)
        end

        -- URL Detection
        if chat.urls then
            CreateChatSection("urlDetection", "URL Detection", 2 * FORM_ROW + 8, function(card)
                local w = GUI:CreateFormCheckbox(card.frame, nil, "enabled", chat.urls, Refresh, { description = "Detect URLs in chat and click them to open a copy dialog." })
                card.AddRow(row(card.frame, "Make URLs Clickable", w))
            end)
        end

        -- Chat Hyperlinks (Phase D)
        if not chat.hyperlinks then
            chat.hyperlinks = { coordinates = true, friendlyURLs = false, interactiveNames = true }
        end
        CreateChatSection("chatHyperlinks", "Chat Hyperlinks", 3 * FORM_ROW + 8, function(card)
            local coordW = GUI:CreateFormCheckbox(card.frame, nil, "coordinates", chat.hyperlinks, Refresh,
                { description = "Detects (x, y) coordinate patterns in chat and makes them clickable waypoints." })
            local urlW = GUI:CreateFormCheckbox(card.frame, nil, "friendlyURLs", chat.hyperlinks, Refresh,
                { description = "Replace common WoW-community URLs with readable labels — e.g., wowhead.com -> [Wowhead]." })
            card.AddRow(row(card.frame, "Coordinate links", coordW), row(card.frame, "Friendly URL labels", urlW))
            local namesW = GUI:CreateFormCheckbox(card.frame, nil, "interactiveNames", chat.hyperlinks, Refresh,
                { description = "Click a class-colored player name in chat to open quick-action menu (Whisper, Invite, Add Friend, Ignore)." })
            card.AddRow(row(card.frame, "Interactive player names", namesW))
        end)

        if ShouldRenderSection("tabFilters") then
        -- Tab Filters (Phase E)
        -- Per-tab content filtering. Inclusion-only: select which message
        -- groups and channels appear on each chat frame. ChatFrame1 only in
        -- this first iteration; multi-frame editing is intentionally deferred
        -- to a follow-up phase (would add 24+ * NUM_CHAT_WINDOWS widgets).
        --
        -- Storage: db.profile.chat.tabs[<frameID>] = { customized, groups, channels }
        -- The reconcile + tab indicator live in modules/chat/tab_filters.lua.
        --
        -- Standard chat groups exposed below mirror Blizzard's chat-options
        -- grouping (matches the keys ChatFrame_AddMessageGroup expects).
        local CHAT_GROUPS = {
            "SAY", "EMOTE", "YELL",
            "GUILD", "OFFICER",
            "PARTY", "PARTY_LEADER",
            "RAID", "RAID_LEADER", "RAID_WARNING",
            "INSTANCE_CHAT", "INSTANCE_CHAT_LEADER",
            "BG_HORDE", "BG_ALLIANCE",
            "SYSTEM",
            "LOOT", "MONEY", "CURRENCY",
            "WHISPER", "WHISPER_INFORM",
            "BN_WHISPER", "BN_WHISPER_INFORM",
            "AFK", "DND", "IGNORED",
            "COMBAT_XP_GAIN", "COMBAT_HONOR_GAIN", "COMBAT_FACTION_CHANGE",
            "ACHIEVEMENT", "GUILD_ACHIEVEMENT",
            "CHANNEL",
        }

        if not chat.tabs then chat.tabs = {} end

        local function copyStringList(list)
            local out = {}
            if type(list) == "table" then
                for i = 1, #list do
                    if type(list[i]) == "string" then
                        out[#out + 1] = list[i]
                    end
                end
            end
            return out
        end

        local function seedEntryFromCurrentFrame(entry, frameID)
            if not entry then return end
            local frame = _G["ChatFrame" .. tostring(frameID or 1)]
            if not frame then return end
            if type(entry.groups) ~= "table" or #entry.groups == 0 then
                entry.groups = copyStringList(frame.messageTypeList)
            end
            if type(entry.channels) ~= "table" or #entry.channels == 0 then
                entry.channels = copyStringList(frame.channelList)
            end
        end

        -- Helper: bidirectional set <-> array proxy.
        -- Each tile invocation rebuilds these proxies fresh so they always
        -- read the current chat.tabs[frameID].groups / .channels arrays.
        local function makeArraySetProxy(getList, setList)
            return MarkTransientOptionsBinding(setmetatable({}, {
                __index = function(_, entryKey)
                    local list = getList()
                    if not list then return false end
                    for i = 1, #list do
                        if list[i] == entryKey then return true end
                    end
                    return false
                end,
                __newindex = function(_, entryKey, value)
                    local list = getList() or {}
                    if value then
                        for i = 1, #list do
                            if list[i] == entryKey then return end
                        end
                        list[#list + 1] = entryKey
                    else
                        for i = 1, #list do
                            if list[i] == entryKey then
                                table.remove(list, i)
                                break
                            end
                        end
                    end
                    setList(list)
                end,
            }))
        end

        local function getChannelNamesNow()
            -- GetChannelList returns id1, name1, header1, id2, name2, header2, ...
            -- Filter out headers (categorical separators with empty/nil names).
            local out = {}
            if type(GetChannelList) == "function" then
                local data = { GetChannelList() }
                local i = 1
                while i + 1 <= #data do
                    local name = data[i + 1]
                    local isHeader = data[i + 2]
                    if type(name) == "string" and name ~= "" and not isHeader then
                        out[#out + 1] = name
                    end
                    i = i + 3
                end
            end
            return out
        end

        -- Build the per-frame tab-filter UI as a stack of CreateSettingsCardGroup
        -- cards (one per logical group of settings). Each card pairs its rows
        -- into the standard QUI dual-column layout (left/right cell + center
        -- divider + alternating row bg). Soft-refresh on frame-selector change
        -- re-binds proxies via each widget's :Refresh() rather than recreating
        -- widgets — WoW frames can't be GC'd, and structural rebuilds leak
        -- ~25MB of orphan widgets per change.
        CreateChatCustomSection("tabFilters", "Tab Filters", function(body)
            local frameOptions = buildFrameOptions()
            -- Validate selection still exists (e.g. frame deleted between sessions).
            local validSelection = false
            for _, opt in ipairs(frameOptions) do
                if opt.value == selectedTabFilterFrame then validSelection = true; break end
            end
            if not validSelection then selectedTabFilterFrame = frameOptions[1].value end

            local selectorTable = MarkTransientOptionsBinding({ _selected = selectedTabFilterFrame })

            local refreshList = {}
            local sy = -4
            local GAP = 8

            -- Dynamic entry lookup. Reading a fresh reference every access
            -- means proxies/handlers see the current frame's data even after
            -- selectedTabFilterFrame changes out from under them.
            local function getCurEntry()
                local fid = selectedTabFilterFrame
                chat.tabs[fid] = chat.tabs[fid] or { customized = false, groups = {}, channels = {} }
                local e = chat.tabs[fid]
                if type(e.groups) ~= "table" then e.groups = {} end
                if type(e.channels) ~= "table" then e.channels = {} end
                return e
            end

            local dependentControls = {}
            local dependentRegions = {}
            local function TrackFilterControl(control)
                dependentControls[#dependentControls + 1] = control
                return control
            end
            local function TrackFilterRegion(region)
                dependentRegions[#dependentRegions + 1] = region
                return region
            end
            local function UpdateTabFilterDependentStates()
                local enabled = getCurEntry().customized == true
                for i = 1, #dependentControls do
                    SetControlEnabled(dependentControls[i], enabled)
                end
                for i = 1, #dependentRegions do
                    local region = dependentRegions[i]
                    if region and type(region.SetAlpha) == "function" then
                        region:SetAlpha(enabled and 1 or 0.45)
                    end
                end
            end

            -- Selector card (Editing tab dropdown).
            local selectorCard = ns.QUI_Options.CreateSettingsCardGroup(body, sy)
            local frameSelector
            frameSelector = GUI:CreateFormDropdown(selectorCard.frame, nil, frameOptions, "_selected", selectorTable, function()
                local newValue = selectorTable._selected or 1
                -- Idempotency guard: CreateFormDropdown's SetValue fires onChange
                -- on every click without checking value-changed.
                if newValue == selectedTabFilterFrame then return end
                selectedTabFilterFrame = newValue
                for i = 1, #refreshList do
                    pcall(refreshList[i])
                end
            end, { description = "Pick which chat frame's tab filters to edit. Each frame stores its own filter set in db.profile.chat.tabs[<frameID>]; this dropdown only changes which one the controls below are bound to." })
            selectorCard.AddRow(row(selectorCard.frame, "Editing tab", frameSelector))
            selectorCard.Finalize()
            sy = sy - selectorCard.frame:GetHeight() - GAP

            -- Customized toggle card. The proxy triggers reconcile + indicator
            -- update via the chat module's _afterRefresh chain (Refresh ->
            -- tab_filters ApplyEnabled). When toggled OFF the stored entry is
            -- preserved so re-enabling restores the user's selection.
            local customizedProxy = MarkTransientOptionsBinding(setmetatable({}, {
                __index = function() return getCurEntry().customized and true or false end,
                __newindex = function(_, _, v)
                    local e = getCurEntry()
                    local wasCustomized = e.customized
                    e.customized = v and true or false
                    if e.customized and not wasCustomized then
                        seedEntryFromCurrentFrame(e, selectedTabFilterFrame)
                    end
                    if v and ns.QUI and ns.QUI.Chat and ns.QUI.Chat.TabFilters then
                        ns.QUI.Chat.TabFilters.SaveTabConfig(selectedTabFilterFrame, e.groups, e.channels)
                    end
                end,
            }))

            local toggleCard = ns.QUI_Options.CreateSettingsCardGroup(body, sy)
            local customizedCheckbox = GUI:CreateFormCheckbox(toggleCard.frame, nil, "_customized", customizedProxy, function()
                Refresh()
                UpdateTabFilterDependentStates()
            end, { description = "When on, this tab shows ONLY the message groups and channels selected below. Inclusion-only — to silence a group, deselect it. When off, Blizzard's defaults apply unchanged." })
            toggleCard.AddRow(row(toggleCard.frame, "Customize this tab's filters", customizedCheckbox))
            toggleCard.Finalize()
            sy = sy - toggleCard.frame:GetHeight() - GAP
            refreshList[#refreshList + 1] = function() if customizedCheckbox.Refresh then customizedCheckbox:Refresh() end end

            -- Message groups subheader + paired card.
            TrackFilterRegion(ns.QUI_Options.CreateAccentDotLabel(body, "Message groups", sy))
            sy = sy - 30

            local groupsProxy = makeArraySetProxy(
                function() return getCurEntry().groups end,
                function(list) getCurEntry().groups = list end
            )
            local groupsCard = ns.QUI_Options.CreateSettingsCardGroup(body, sy)
            local function makeGroupCheckbox(groupKey)
                local cb = TrackFilterControl(GUI:CreateFormCheckbox(groupsCard.frame, nil, groupKey, groupsProxy, function()
                    local e = getCurEntry()
                    if e.customized and ns.QUI and ns.QUI.Chat and ns.QUI.Chat.TabFilters then
                        ns.QUI.Chat.TabFilters.SaveTabConfig(selectedTabFilterFrame, e.groups, e.channels)
                    end
                    Refresh()
                end, { description = "Show " .. groupKey .. " messages on this tab. Only takes effect while 'Customize this tab's filters' is on." }))
                refreshList[#refreshList + 1] = function() if cb.Refresh then cb:Refresh() end end
                return cb
            end
            for i = 1, #CHAT_GROUPS, 2 do
                local k1, k2 = CHAT_GROUPS[i], CHAT_GROUPS[i + 1]
                local cellL = row(groupsCard.frame, k1, makeGroupCheckbox(k1))
                local cellR
                if k2 then
                    cellR = row(groupsCard.frame, k2, makeGroupCheckbox(k2))
                end
                groupsCard.AddRow(cellL, cellR)
            end
            groupsCard.Finalize()
            sy = sy - groupsCard.frame:GetHeight() - GAP

            -- Channels subheader + paired card (or "no channels" note).
            TrackFilterRegion(ns.QUI_Options.CreateAccentDotLabel(body, "Channels (current join list)", sy))
            sy = sy - 30

            local channels = getChannelNamesNow()
            if #channels == 0 then
                local noChan = TrackFilterRegion(GUI:CreateLabel(body, "    (Not currently in any custom channels.)", 10, {0.5, 0.5, 0.5, 1}))
                noChan:SetPoint("TOPLEFT", 8, sy)
                noChan:SetPoint("RIGHT", body, "RIGHT", 0, 0)
                noChan:SetJustifyH("LEFT")
                sy = sy - 18
            else
                local channelsProxy = makeArraySetProxy(
                    function() return getCurEntry().channels end,
                    function(list) getCurEntry().channels = list end
                )
                local channelsCard = ns.QUI_Options.CreateSettingsCardGroup(body, sy)
                local function makeChannelCheckbox(channelName)
                    local cb = TrackFilterControl(GUI:CreateFormCheckbox(channelsCard.frame, nil, channelName, channelsProxy, function()
                        local e = getCurEntry()
                        if e.customized and ns.QUI and ns.QUI.Chat and ns.QUI.Chat.TabFilters then
                            ns.QUI.Chat.TabFilters.SaveTabConfig(selectedTabFilterFrame, e.groups, e.channels)
                        end
                        Refresh()
                    end, { description = "Show messages from channel '" .. channelName .. "' on this tab." }))
                    refreshList[#refreshList + 1] = function() if cb.Refresh then cb:Refresh() end end
                    return cb
                end
                for i = 1, #channels, 2 do
                    local n1, n2 = channels[i], channels[i + 1]
                    local cellL = row(channelsCard.frame, n1, makeChannelCheckbox(n1))
                    local cellR
                    if n2 then
                        cellR = row(channelsCard.frame, n2, makeChannelCheckbox(n2))
                    end
                    channelsCard.AddRow(cellL, cellR)
                end
                channelsCard.Finalize()
                sy = sy - channelsCard.frame:GetHeight() - GAP
            end

            -- Reset card.
            local resetCard = ns.QUI_Options.CreateSettingsCardGroup(body, sy)
            local resetBtn
            resetBtn = TrackFilterControl(GUI:CreateButton(resetCard.frame, "Reset to Blizzard defaults", 200, 24, function()
                if ns.QUI and ns.QUI.Chat and ns.QUI.Chat.TabFilters then
                    ns.QUI.Chat.TabFilters.ResetTab(selectedTabFilterFrame)
                end
                NotifyProviderFor(resetBtn, { structural = true })
            end))
            GUI:AttachTooltip(resetBtn,
                "Reset this tab's message-type filters to Blizzard's defaults. Per-channel overrides on other tabs are not touched.",
                "Reset filters")
            resetCard.AddRow(row(resetCard.frame, "Reset filters", resetBtn))
            resetCard.Finalize()
            sy = sy - resetCard.frame:GetHeight() - GAP

            refreshList[#refreshList + 1] = UpdateTabFilterDependentStates
            UpdateTabFilterDependentStates()

            return math.abs(sy) + 4
        end, 800)
        end

        if ShouldRenderSection("buttonBar") then
        -- Button Bar (Phase F)
        -- Per-frame custom button bar. The editor below selects which chat
        -- frame to configure, and the runtime reconciles whatever frameIDs
        -- appear in db.profile.chat.buttonBars.
        --
        -- Storage: db.profile.chat.buttonBars[<frameID>] = {
        --   enabled, position, offsetX, offsetY, buttonSpacing, hideInCombat,
        --   buttons = { { id, visible }, ... }, customButtons = { ... }
        -- }
        --
        if not chat.buttonBars then chat.buttonBars = {} end

        -- Multi-frame button bar editor. Frame-selector dropdown writes to
        -- selectedButtonBarFrame and triggers structural rebuild so add/remove
        -- and per-frame switch always re-enter this builder. Rendered as a
        -- stack of CreateSettingsCardGroup cards so the dual-column layout
        -- matches the rest of QUI's chat settings.
        CreateChatCustomSection("buttonBar", "Button Bar", function(body)
            local frameOptions = buildFrameOptions()
            local validSelection = false
            for _, opt in ipairs(frameOptions) do
                if opt.value == selectedButtonBarFrame then validSelection = true; break end
            end
            if not validSelection then selectedButtonBarFrame = frameOptions[1].value end

            local selectorTable = MarkTransientOptionsBinding({ _selected = selectedButtonBarFrame })
            local sy = -4
            local GAP = 8

            -- Selector card (Editing frame dropdown).
            local selectorCard = ns.QUI_Options.CreateSettingsCardGroup(body, sy)
            local frameSelector
            frameSelector = GUI:CreateFormDropdown(selectorCard.frame, nil, frameOptions, "_selected", selectorTable, function()
                local newValue = selectorTable._selected or 1
                if newValue == selectedButtonBarFrame then return end
                selectedButtonBarFrame = newValue
                NotifyProviderFor(frameSelector, { structural = true })
            end, { description = "Pick which chat frame's button bar to edit. Each frame stores its own bar config in db.profile.chat.buttonBars[<frameID>]." })
            selectorCard.AddRow(row(selectorCard.frame, "Editing frame", frameSelector))
            selectorCard.Finalize()
            sy = sy - selectorCard.frame:GetHeight() - GAP

            local BB = ns.QUI and ns.QUI.Chat and ns.QUI.Chat.ButtonBar
            if not BB then
                local errLabel = GUI:CreateLabel(body, "Button Bar module not loaded.", 10, {1, 0.5, 0.5, 1})
                errLabel:SetPoint("TOPLEFT", 4, sy)
                errLabel:SetPoint("RIGHT", body, "RIGHT", 0, 0)
                return math.abs(sy) + 24
            end

            -- Lazily initialise the entry with built-in defaults so toggles
            -- below have something to bind to. The bar stays disabled until
            -- the user flips the master toggle.
            local entry = BB.InitFrameDefaults(selectedButtonBarFrame)
            if not entry then return math.abs(sy) + 4 end

            local dependentControls = {}
            local dependentRegions = {}
            local function TrackBarControl(control)
                dependentControls[#dependentControls + 1] = control
                return control
            end
            local function TrackBarRegion(region)
                dependentRegions[#dependentRegions + 1] = region
                return region
            end
            local function UpdateButtonBarDependentStates()
                local enabled = entry.enabled == true
                for i = 1, #dependentControls do
                    SetControlEnabled(dependentControls[i], enabled)
                end
                for i = 1, #dependentRegions do
                    local region = dependentRegions[i]
                    if region and type(region.SetAlpha) == "function" then
                        region:SetAlpha(enabled and 1 or 0.45)
                    end
                end
            end

            -- Basics card: master/combat toggles + position + offsets + spacing.
            local positionOptions = {
                { value = "outside_left",  text = "Outside left (vertical strip)" },
                { value = "outside_right", text = "Outside right (vertical strip)" },
                { value = "inside_left",   text = "Inside left (vertical, above scrollback)" },
                { value = "inside_right",  text = "Inside right (vertical, above scrollback)" },
                { value = "inside_tabs",   text = "Inside tab row (horizontal)" },
                { value = "hidden",        text = "Hidden (configured but not shown)" },
            }
            local basicsCard = ns.QUI_Options.CreateSettingsCardGroup(body, sy)
            local enabledCheckbox = GUI:CreateFormCheckbox(basicsCard.frame, nil, "enabled", entry, function()
                Refresh()
                UpdateButtonBarDependentStates()
            end, { description = "Master toggle for the custom button bar on this chat frame. When off, no bar is shown for this frame; the per-button selections below are preserved." })
            local hideInCombatCheckbox = TrackBarControl(GUI:CreateFormCheckbox(basicsCard.frame, nil, "hideInCombat", entry, Refresh,
                { description = "Hide this chat frame's button bar while you are in combat, then restore it after combat ends." }))
            basicsCard.AddRow(row(basicsCard.frame, "Show button bar for this frame", enabledCheckbox), row(basicsCard.frame, "Hide in combat", hideInCombatCheckbox))

            local positionDropdown = TrackBarControl(GUI:CreateFormDropdown(basicsCard.frame, nil, positionOptions, "position", entry, Refresh,
                { description = "Where the button bar attaches relative to the chat frame. outside_left/outside_right anchor outside the chat frame's edge; inside_left/inside_right anchor inside above the scrollback; inside_tabs lays buttons horizontally next to this chat frame's tab." }))
            local spacingSlider = TrackBarControl(GUI:CreateFormSlider(basicsCard.frame, nil, 0, 24, 1, "buttonSpacing", entry, Refresh, nil,
                { description = "Pixels between buttons in this chat frame's button bar." }))
            basicsCard.AddRow(row(basicsCard.frame, "Position", positionDropdown), row(basicsCard.frame, "Button spacing", spacingSlider))

            local xOffsetSlider = TrackBarControl(GUI:CreateFormSlider(basicsCard.frame, nil, -200, 200, 1, "offsetX", entry, Refresh, nil,
                { description = "Fine-tune the bar's horizontal position relative to the selected anchor. Positive values move right. In Inside tab row mode the anchor follows this chat frame's tab." }))
            local yOffsetSlider = TrackBarControl(GUI:CreateFormSlider(basicsCard.frame, nil, -200, 200, 1, "offsetY", entry, Refresh, nil,
                { description = "Fine-tune the bar's vertical position relative to the selected anchor. Positive values move up. In Inside tab row mode the anchor follows this chat frame's tab." }))
            basicsCard.AddRow(row(basicsCard.frame, "X offset", xOffsetSlider), row(basicsCard.frame, "Y offset", yOffsetSlider))
            basicsCard.Finalize()
            sy = sy - basicsCard.frame:GetHeight() - GAP

            -- Built-in buttons subheader + paired card. Each entry in
            -- entry.buttons is { id, visible }; the proxy maps each builtin
            -- key to the visible flag, creating a record on first toggle.
            TrackBarRegion(ns.QUI_Options.CreateAccentDotLabel(body, "Built-in buttons", sy))
            sy = sy - 30

            local function findOrCreate(id)
                for i = 1, #entry.buttons do
                    if entry.buttons[i] and entry.buttons[i].id == id then
                        return entry.buttons[i]
                    end
                end
                local rec = { id = id, visible = false }
                entry.buttons[#entry.buttons + 1] = rec
                return rec
            end

            local builtinProxy = MarkTransientOptionsBinding(setmetatable({}, {
                __index = function(_, id)
                    local rec = findOrCreate(id)
                    return rec.visible and true or false
                end,
                __newindex = function(_, id, v)
                    local rec = findOrCreate(id)
                    rec.visible = v and true or false
                end,
            }))

            local labels = {
                qui_options = "QUI options (/qui)",
                qui_layout  = "Layout Mode",
                qui_keybind = "Keybind mode",
                qui_cdm     = "Cooldown Manager",
                social      = "Friends list",
                guild       = "Guild frame",
                reload      = "Reload UI",
            }
            local builtinOrder = BB.GetBuiltinOrder()
            local builtinCard = ns.QUI_Options.CreateSettingsCardGroup(body, sy)
            local function makeBuiltinCheckbox(id)
                return TrackBarControl(GUI:CreateFormCheckbox(builtinCard.frame, nil, id, builtinProxy, Refresh,
                    { description = "Show the '" .. (labels[id] or id) .. "' button on this chat frame's button bar." }))
            end
            for i = 1, #builtinOrder, 2 do
                local id1, id2 = builtinOrder[i], builtinOrder[i + 1]
                local cellL = row(builtinCard.frame, labels[id1] or id1, makeBuiltinCheckbox(id1))
                local cellR
                if id2 then
                    cellR = row(builtinCard.frame, labels[id2] or id2, makeBuiltinCheckbox(id2))
                end
                builtinCard.AddRow(cellL, cellR)
            end
            builtinCard.Finalize()
            sy = sy - builtinCard.frame:GetHeight() - GAP

            -- Custom slash-command buttons subheader. Each custom button gets
            -- its own card with [Label | Slash command] + [Icon path | Remove].
            -- Add/Remove trigger structural rebuilds so this loop re-runs.
            TrackBarRegion(ns.QUI_Options.CreateAccentDotLabel(body, "Custom slash-command buttons", sy))
            sy = sy - 30

            for idx = 1, #entry.customButtons do
                local cb = entry.customButtons[idx]
                if type(cb) ~= "table" then
                    cb = { label = "", slashCommand = "", icon = "" }
                    entry.customButtons[idx] = cb
                end
                if cb.icon == nil then cb.icon = "" end

                TrackBarRegion(ns.QUI_Options.CreateAccentDotLabel(body, "Button " .. idx, sy))
                sy = sy - 30

                local btnCard = ns.QUI_Options.CreateSettingsCardGroup(body, sy)
                local labelEdit = TrackBarControl(GUI:CreateFormEditBox(btnCard.frame, nil, "label", cb, Refresh,
                    { description = "Text shown on the button when no icon is set." }))
                local slashEdit = TrackBarControl(GUI:CreateFormEditBox(btnCard.frame, nil, "slashCommand", cb, Refresh,
                    { description = "Slash command to run on click — e.g. /target Boss, /readycheck. Must include the leading slash." }))
                btnCard.AddRow(row(btnCard.frame, "Label", labelEdit), row(btnCard.frame, "Slash command", slashEdit))

                local iconEdit = TrackBarControl(GUI:CreateFormEditBox(btnCard.frame, nil, "icon", cb, Refresh,
                    { description = "Texture path for an icon-style button — e.g. Interface/Icons/Spell_Holy_HolyBolt or any registered AddOn texture path. Leave blank to render as a text button." }))
                local removeBtn
                removeBtn = TrackBarControl(GUI:CreateButton(btnCard.frame, "Remove button " .. idx, 160, 22, function()
                    table.remove(entry.customButtons, idx)
                    Refresh()
                    NotifyProviderFor(removeBtn, { structural = true })
                end))
                GUI:AttachTooltip(removeBtn,
                    "Remove this custom button from the chat button bar. Its label, slash command, and icon are discarded.",
                    "Remove Button")
                btnCard.AddRow(row(btnCard.frame, "Icon path (optional)", iconEdit), row(btnCard.frame, "Remove", removeBtn))
                btnCard.Finalize()
                sy = sy - btnCard.frame:GetHeight() - GAP
            end

            -- Add button card.
            local addCard = ns.QUI_Options.CreateSettingsCardGroup(body, sy)
            local addBtn
            addBtn = TrackBarControl(GUI:CreateButton(addCard.frame, "Add custom button", 200, 24, function()
                entry.customButtons[#entry.customButtons + 1] = { label = "", slashCommand = "", icon = "" }
                Refresh()
                NotifyProviderFor(addBtn, { structural = true })
            end))
            GUI:AttachTooltip(addBtn,
                "Add a new button to the chat button bar. Configure its label, slash command, and optional icon in the card that appears.",
                "Add Custom Button")
            addCard.AddRow(row(addCard.frame, "Add a new custom button", addBtn))
            addCard.Finalize()
            sy = sy - addCard.frame:GetHeight() - GAP

            UpdateButtonBarDependentStates()

            return math.abs(sy) + 4
        end, 500)
        end

        -- Timestamps
        CreateChatSection("timestamps", "Timestamps", 4 * FORM_ROW + 8, function(card)
            if not chat.timestamps then chat.timestamps = {enabled = false, format = "24h", color = {0.6, 0.6, 0.6}} end
            local formatDropdown, timestampColorPicker
            local function UpdateTimestampStates()
                local enabled = chat.timestamps.enabled == true
                SetControlEnabled(formatDropdown, enabled)
                SetControlEnabled(timestampColorPicker, enabled)
            end
            local timestampsCheckbox = GUI:CreateFormCheckbox(card.frame, nil, "enabled", chat.timestamps, function()
                Refresh()
                UpdateTimestampStates()
            end, { description = "Use QUI's colored timestamp prefix on new chat messages. While enabled, Blizzard's native chat timestamp is suppressed so the two do not stack." })
            local formatOptions = {
                {value = "24h", text = "24-Hour (15:27)"},
                {value = "12h", text = "12-Hour (3:27 PM)"},
            }
            formatDropdown = GUI:CreateFormDropdown(card.frame, nil, formatOptions, "format", chat.timestamps, Refresh, { description = "Timestamp format: 24-hour (15:27) or 12-hour with AM/PM (3:27 PM)." })
            card.AddRow(row(card.frame, "Show Timestamps", timestampsCheckbox), row(card.frame, "Format", formatDropdown))
            timestampColorPicker = GUI:CreateFormColorPicker(card.frame, nil, "color", chat.timestamps, Refresh, nil, { description = "Color of the timestamp prefix on chat messages." })
            card.AddRow(row(card.frame, "Timestamp Color", timestampColorPicker))
            UpdateTimestampStates()
        end)

        -- Message Modifiers (Phase A)
        CreateChatSection("messageModifiers", "Message Modifiers", 4 * FORM_ROW + 8, function(card)
            if not chat.modifiers then chat.modifiers = {} end
            if not chat.modifiers.classColors then
                chat.modifiers.classColors = { enabled = true, recolorBodyText = false }
            end
            if not chat.modifiers.channelShorten then
                chat.modifiers.channelShorten = { enabled = true, preset = "letter" }
            end
            local classColors = chat.modifiers.classColors
            local channelShorten = chat.modifiers.channelShorten

            local recolorBodyCheckbox, channelPresetDropdown
            local function UpdateMessageModifierStates()
                SetControlEnabled(recolorBodyCheckbox, classColors.enabled == true)
                SetControlEnabled(channelPresetDropdown, channelShorten.enabled == true)
            end

            local classColorsCheckbox = GUI:CreateFormCheckbox(card.frame, nil, "enabled", classColors, function()
                Refresh()
                UpdateMessageModifierStates()
            end, { description = "Color player names in chat by their class color (e.g. Mage names appear in light blue, Druid names in orange)." })
            recolorBodyCheckbox = GUI:CreateFormCheckbox(card.frame, nil, "recolorBodyText", classColors, Refresh, { description = "Performs an extra regex pass on every chat message to recolor known player names anywhere in the body. Slightly more expensive than the default name-only coloring." })
            card.AddRow(row(card.frame, "Class colors on player names", classColorsCheckbox), row(card.frame, "Recolor names mentioned in body text", recolorBodyCheckbox))

            local channelShortenCheckbox = GUI:CreateFormCheckbox(card.frame, nil, "enabled", channelShorten, function()
                Refresh()
                UpdateMessageModifierStates()
            end, { description = "Replace verbose channel tags like [Guild] with compact labels like [G] in chat output." })
            local presetOptions = {
                {value = "letter", text = "Letter \226\128\148 [G], [O], [P] + [Gen], [T], [LFG]"},
                {value = "number", text = "Number \226\128\148 [G], [O], [P] + [1], [2], [3]"},
            }
            channelPresetDropdown = GUI:CreateFormDropdown(card.frame, nil, presetOptions, "preset", channelShorten, Refresh, { description = "Channel label preset. Both presets shorten chat types ([G]/[O]/[P]/[R]/[I] etc.). For numbered chat channels: Letter abbreviates the channel name ([1. General] \226\134\146 [Gen], [2. Trade] \226\134\146 [T], [4. Trade (Services)] \226\134\146 [S]; unknown / custom channels get the first 3 letters), Number keeps just the channel number ([1. General] \226\134\146 [1])." })
            card.AddRow(row(card.frame, "Shorten channel labels", channelShortenCheckbox), row(card.frame, "Preset", channelPresetDropdown))
            UpdateMessageModifierStates()
        end)

        -- Keyword Alert (Phase A.1)
        CreateChatSection("keywordAlert", "Keyword Alert", 9 * FORM_ROW + 8, function(card)
            if not chat.modifiers then chat.modifiers = {} end
            if not chat.modifiers.keywordAlert then
                chat.modifiers.keywordAlert = {
                    enabled = false, keywords = {},
                    includeOwnName = true, includeFirstName = false, includeGuildName = false,
                    skipSelf = true,
                    highlightColor = { 0.204, 0.831, 0.600, 1 },
                    soundFile = "Sound\\Interface\\RaidWarning.ogg",
                    flashTab = false,
                }
            end
            local ka = chat.modifiers.keywordAlert
            if type(ka.keywords) ~= "table" then ka.keywords = {} end

            local keywordDependentControls = {}
            local function TrackKeywordControl(control)
                keywordDependentControls[#keywordDependentControls + 1] = control
                return control
            end
            local function UpdateKeywordAlertStates()
                local enabled = ka.enabled == true
                for i = 1, #keywordDependentControls do
                    SetControlEnabled(keywordDependentControls[i], enabled)
                end
            end

            local keywordEnableCheckbox = GUI:CreateFormCheckbox(card.frame, nil, "enabled", ka, function()
                Refresh()
                UpdateKeywordAlertStates()
            end, { description = "Highlight chat messages containing your configured keywords or character/guild name. Optionally play a sound and flash the chat tab when a match is found." })
            local ownNameCb = TrackKeywordControl(GUI:CreateFormCheckbox(card.frame, nil, "includeOwnName", ka, Refresh, { description = "Always treat your own character name as a keyword. Recommended on so you're alerted when someone @-mentions you." }))
            card.AddRow(row(card.frame, "Enable keyword alerts", keywordEnableCheckbox), row(card.frame, "Trigger on my character name", ownNameCb))

            local firstNameCb = TrackKeywordControl(GUI:CreateFormCheckbox(card.frame, nil, "includeFirstName", ka, Refresh, { description = "When your character name contains a space (e.g., 'Foo Bar'), trigger on the first part. Most player names don't have spaces." }))
            local guildNameCb = TrackKeywordControl(GUI:CreateFormCheckbox(card.frame, nil, "includeGuildName", ka, Refresh, { description = "Trigger an alert when your guild name appears in chat. Only fires when you are in a guild." }))
            card.AddRow(row(card.frame, "Trigger on my first name", firstNameCb), row(card.frame, "Trigger on my guild name", guildNameCb))

            local skipSelfCb = TrackKeywordControl(GUI:CreateFormCheckbox(card.frame, nil, "skipSelf", ka, Refresh, { description = "Don't trigger alerts for messages you send yourself. Recommended on." }))
            local flashTabCb = TrackKeywordControl(GUI:CreateFormCheckbox(card.frame, nil, "flashTab", ka, Refresh, { description = "Briefly flash the chat tab in addition to highlighting the matched text." }))
            card.AddRow(row(card.frame, "Skip my own messages", skipSelfCb), row(card.frame, "Flash chat tab on alert", flashTabCb))

            local highlightColorPicker = TrackKeywordControl(GUI:CreateFormColorPicker(card.frame, nil, "highlightColor", ka, Refresh, nil, { description = "Color used to wrap matched keywords in chat output." }))

            -- Sound dropdown via LSM if available, else a text input fallback.
            -- Architectural note: when LSM is loaded the sound list is the same
            -- one used by Timestamps / New Message Sound (U.GetSoundList());
            -- when not loaded we surface a text input so users can still paste
            -- a literal "Sound\\Interface\\Foo.ogg" path.
            local soundWidget
            local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
            if LSM and U.GetSoundList then
                local soundList = U.GetSoundList()
                soundWidget = TrackKeywordControl(GUI:CreateFormDropdown(card.frame, nil, soundList, "soundFile", ka, Refresh, { description = "Sound played when a keyword match is detected. List sourced from LibSharedMedia." }))
            else
                soundWidget = TrackKeywordControl(GUI:CreateFormEditBox(card.frame, nil, "soundFile", ka, Refresh, {
                    maxLetters = 260, live = false,
                    onEditFocusGained = function(self) self:HighlightText() end,
                }, { description = "Path to the sound file to play on alert. Example: Sound\\Interface\\RaidWarning.ogg" }))
            end
            card.AddRow(row(card.frame, "Highlight Color", highlightColorPicker), row(card.frame, "Alert Sound", soundWidget))

            -- Custom keywords list. The settings framework does not currently
            -- expose a native list-editor widget here, so the chosen trade-off
            -- is a comma-separated text input fronted by a metatable proxy.
            -- The proxy bidirectionally syncs ka.keywords (array of strings)
            -- with a "keywordsText" field so CreateFormEditBox sees a regular
            -- string DB key. Empty tokens are dropped on write; whitespace is
            -- trimmed. A user keyword that contains a comma is therefore not
            -- representable in this UI — acceptable since chat keywords are
            -- almost always single words / short phrases without commas.
            local function joinKeywords(list)
                if type(list) ~= "table" then return "" end
                local parts = {}
                for i = 1, #list do
                    local v = list[i]
                    if type(v) == "string" and v ~= "" then
                        parts[#parts + 1] = v
                    end
                end
                return table.concat(parts, ", ")
            end
            local function splitKeywords(text)
                local out = {}
                if type(text) ~= "string" then return out end
                for token in string.gmatch(text, "([^,]+)") do
                    local trimmed = token:gsub("^%s+", ""):gsub("%s+$", "")
                    if trimmed ~= "" then out[#out + 1] = trimmed end
                end
                return out
            end
            local keywordsProxy = MarkTransientOptionsBinding(setmetatable({}, {
                __index = function(_, k)
                    if k == "keywordsText" then return joinKeywords(ka.keywords) end
                    return nil
                end,
                __newindex = function(_, k, v)
                    if k == "keywordsText" and type(v) == "string" then
                        ka.keywords = splitKeywords(v)
                    end
                end,
            }))

            local keywordsField = TrackKeywordControl(GUI:CreateFormEditBox(card.frame, nil, "keywordsText", keywordsProxy, Refresh, {
                maxLetters = 500, live = false,
                onEditFocusGained = function(self) self:HighlightText() end,
            }, { description = "Comma-separated list of additional keywords to highlight. Example: 'flask, food, summon'. Case-insensitive. Keywords containing commas are not supported by this input." }))
            card.AddRow(row(card.frame, "Custom Keywords", keywordsField))
            UpdateKeywordAlertStates()
        end)

        -- Redundant Text Cleanup (Phase A.2)
        CreateChatSection("redundantTextCleanup", "Redundant Text Cleanup", 7 * FORM_ROW + 8, function(card)
            if not chat.modifiers then chat.modifiers = {} end
            if not chat.modifiers.redundantText then
                chat.modifiers.redundantText = {
                    enabled = false,
                    patterns = {
                        loot = true, currency = true, xp = true, honor = true, reputation = true,
                    },
                }
            end
            local rt = chat.modifiers.redundantText
            if type(rt.patterns) ~= "table" then
                rt.patterns = { loot = true, currency = true, xp = true, honor = true, reputation = true }
            end
            local rtp = rt.patterns

            local cleanupPatternControls = {}
            local function TrackCleanupControl(control)
                cleanupPatternControls[#cleanupPatternControls + 1] = control
                return control
            end
            local function UpdateCleanupPatternStates()
                local enabled = rt.enabled == true
                for i = 1, #cleanupPatternControls do
                    SetControlEnabled(cleanupPatternControls[i], enabled)
                end
            end

            local cleanupCheckbox = GUI:CreateFormCheckbox(card.frame, nil, "enabled", rt, function()
                Refresh()
                UpdateCleanupPatternStates()
            end, { description = "Compresses verbose loot/XP/honor/reputation/currency messages into short forms." })
            local lootCb = TrackCleanupControl(GUI:CreateFormCheckbox(card.frame, nil, "loot", rtp, Refresh, { description = "'You receive item: X' \226\134\146 '\226\156\147 X'" }))
            card.AddRow(row(card.frame, "Enable cleanup", cleanupCheckbox), row(card.frame, "Loot collapse", lootCb))

            local currencyCb = TrackCleanupControl(GUI:CreateFormCheckbox(card.frame, nil, "currency", rtp, Refresh, { description = "Collapses currency-receive messages into a compact arrow form." }))
            local xpCb = TrackCleanupControl(GUI:CreateFormCheckbox(card.frame, nil, "xp", rtp, Refresh, { description = "Collapses experience-gain messages to '+N XP'." }))
            card.AddRow(row(card.frame, "Currency collapse", currencyCb), row(card.frame, "XP collapse", xpCb))

            local honorCb = TrackCleanupControl(GUI:CreateFormCheckbox(card.frame, nil, "honor", rtp, Refresh, { description = "Collapses honor-gain messages to '+N Honor'." }))
            local repCb = TrackCleanupControl(GUI:CreateFormCheckbox(card.frame, nil, "reputation", rtp, Refresh, { description = "Collapses reputation-change messages to a compact up/down arrow form." }))
            card.AddRow(row(card.frame, "Honor collapse", honorCb), row(card.frame, "Reputation collapse", repCb))
            UpdateCleanupPatternStates()
        end)

        -- Persistent Message History (Phase B)
        -- The "Advanced: per-channel retention" disclosure described in the plan
        -- is implemented inline as a labelled section inside the main tile body
        -- rather than as a nested CreateTileCollapsible. CreateCollapsible doesn't
        -- expose a nested-tile primitive, and the inline form keeps every control
        -- visible and reachable without extra clicks. Per-channel override toggles
        -- and sliders sit at the bottom of the tile, after a divider label.
        --
        -- Excluded-channels checkbox list: the CreateChatSection call below needs
        -- a fixed body height set at build time, so the joined/stale channel
        -- snapshots are computed here in the outer scope and used both for the
        -- height calc and inside the body closure. CreateChatSection bodies are
        -- rebuilt on structural NotifyProviderFor pulses, so a join/leave during
        -- a session refreshes the list on next reopen.
        local excludedJoinedSnapshot, excludedStaleSnapshot = {}, {}
        do
            local histLocal = (type(chat.history) == "table") and chat.history or nil
            local storedSet = (histLocal and type(histLocal.excludedChannels) == "table")
                              and histLocal.excludedChannels or {}
            -- Inline channel-list walk (the tabFilters section's getChannelNamesNow
            -- is scoped inside its ShouldRenderSection block and not reachable here).
            -- GetChannelList returns id1, name1, header1, ... — skip header rows.
            local joinedSet = {}
            if type(GetChannelList) == "function" then
                local data = { GetChannelList() }
                local i = 1
                while i + 1 <= #data do
                    local name = data[i + 1]
                    local isHeader = data[i + 2]
                    if type(name) == "string" and name ~= "" and not isHeader then
                        excludedJoinedSnapshot[#excludedJoinedSnapshot + 1] = name
                        joinedSet[name] = true
                    end
                    i = i + 3
                end
            end
            for n, on in pairs(storedSet) do
                if on and type(n) == "string" and n ~= ""
                   and not joinedSet[n] then
                    excludedStaleSnapshot[#excludedStaleSnapshot + 1] = n
                end
            end
            table.sort(excludedJoinedSnapshot)
            table.sort(excludedStaleSnapshot)
        end
        local persistentHistoryListRows
        if #excludedJoinedSnapshot == 0 then
            persistentHistoryListRows = 1  -- empty-state placeholder line
        else
            persistentHistoryListRows = #excludedJoinedSnapshot
        end
        if #excludedStaleSnapshot > 0 then
            persistentHistoryListRows = persistentHistoryListRows + 1 + #excludedStaleSnapshot
        end
        -- Base 22 rows covered the old design (which spent 2 rows on editbox + button);
        -- subtract those, add the live list. Floor at the original 22*FORM_ROW + 12 so
        -- a small list never shrinks the section below its prior visual footprint.
        local persistentHistorySectionHeight = (22 + math.max(0, persistentHistoryListRows - 2)) * FORM_ROW + 12

        CreateChatCustomSection("persistentMessageHistory", "Persistent Message History", function(body)
            local sy = -4
            local GAP = 8
            if not chat.history then
                chat.history = {
                    enabled = true,
                    retentionDays = 7,
                    storeWhispers = false,
                    showSeparators = true,
                    perChannelRetention = {},
                    excludedChannels = {},
                }
            end
            local hist = chat.history
            if type(hist.perChannelRetention) ~= "table" then
                hist.perChannelRetention = {}
            end
            if type(hist.excludedChannels) ~= "table" then
                hist.excludedChannels = {}
            end

            local historyDependentControls = {}
            local historyDependentRegions = {}
            local historyOverrideControls = {}
            local function TrackPersistentHistoryControl(control)
                historyDependentControls[#historyDependentControls + 1] = control
                return control
            end
            local function TrackPersistentHistoryRegion(region)
                historyDependentRegions[#historyDependentRegions + 1] = region
                return region
            end
            local function UpdatePersistentHistoryStates()
                local enabled = hist.enabled == true
                for i = 1, #historyDependentControls do
                    SetControlEnabled(historyDependentControls[i], enabled)
                end
                for i = 1, #historyDependentRegions do
                    local region = historyDependentRegions[i]
                    if region and type(region.SetAlpha) == "function" then
                        region:SetAlpha(enabled and 1 or 0.45)
                    end
                end
                for i = 1, #historyOverrideControls do
                    local rec = historyOverrideControls[i]
                    SetControlEnabled(rec.days, enabled and rec.proxy and rec.proxy.enabled == true)
                end
            end

            -- Main settings card: paired rows of master toggle + sliders/toggles.
            local copySourceOptions = {
                { value = "live",      text = "Live (current scrollback)" },
                { value = "persisted", text = "Persisted (full saved history)" },
            }
            local mainCard = ns.QUI_Options.CreateSettingsCardGroup(body, sy)
            local historyEnabledCheckbox = GUI:CreateFormCheckbox(mainCard.frame, nil, "enabled", hist, function()
                Refresh()
                UpdatePersistentHistoryStates()
            end, { description = "Save displayed chat messages to your character's saved variables and replay them on next login or reload. Captured per character; cleared by 'Clear history now'." })
            local retentionSlider = TrackPersistentHistoryControl(GUI:CreateFormSlider(mainCard.frame, nil, 1, 30, 1, "retentionDays", hist, Refresh, nil, { description = "Default age limit for stored messages. Older entries are pruned at login. Per-channel overrides below take precedence when set." }))
            mainCard.AddRow(row(mainCard.frame, "Persist chat history across /reload", historyEnabledCheckbox), row(mainCard.frame, "Retention (days)", retentionSlider))

            local maxEntriesSlider = TrackPersistentHistoryControl(GUI:CreateFormSlider(mainCard.frame, nil, 500, 50000, 500, "maxEntries", hist, Refresh, nil, { description = "Hard cap on stored chat lines per character. Oldest entries beyond this are dropped at flush." }))
            local storeWhispersCheckbox = TrackPersistentHistoryControl(GUI:CreateFormCheckbox(mainCard.frame, nil, "storeWhispers", hist, Refresh, { description = "Include whispers in the persistent history. Default OFF: Blizzard's built-in HistoryKeeper already restores recent whispers, so enabling this can produce duplicate restored whispers." }))
            mainCard.AddRow(row(mainCard.frame, "Max stored messages", maxEntriesSlider), row(mainCard.frame, "Store whispers", storeWhispersCheckbox))

            local separatorsCheckbox = TrackPersistentHistoryControl(GUI:CreateFormCheckbox(mainCard.frame, nil, "showSeparators", hist, Refresh, { description = "Insert '──── Previous session ────' and '──── Resumed ────' markers around the restored block on login." }))
            local copySourceDropdown = TrackPersistentHistoryControl(GUI:CreateFormDropdown(mainCard.frame, nil, copySourceOptions, "copyHistorySource", chat, Refresh, { description = "Which message set the chat-frame copy popup pulls from. 'Live' shows what's currently in the chat tab's visible scrollback. 'Persisted' shows the full saved history including entries scrolled out of view or restored from a previous session." }))
            mainCard.AddRow(row(mainCard.frame, "Show session separators", separatorsCheckbox), row(mainCard.frame, "Copy popup source", copySourceDropdown))
            mainCard.Finalize()
            sy = sy - mainCard.frame:GetHeight() - GAP

            -- Clear actions card. Each action as its own row with help in desc.
            local clearCard = ns.QUI_Options.CreateSettingsCardGroup(body, sy)
            local clearBtn = GUI:CreateButton(clearCard.frame, "Clear history now", 180, 24, function()
                GUI:ShowConfirmation({
                    title = "Clear Chat History?",
                    message = "Clear persisted chat history for this character?",
                    warningText = "This cannot be undone.",
                    acceptText = "Clear",
                    cancelText = "Cancel",
                    isDestructive = true,
                    onAccept = function()
                        if ns.QUI and ns.QUI.Chat and ns.QUI.Chat.History and ns.QUI.Chat.History.Clear then
                            ns.QUI.Chat.History.Clear()
                            if DEFAULT_CHAT_FRAME then
                                DEFAULT_CHAT_FRAME:AddMessage("|cff34D399[QUI]|r Chat history cleared.", 1, 1, 1)
                            end
                        end
                    end,
                })
            end)
            GUI:AttachTooltip(clearBtn,
                "Erase this character's persisted chat history. The live chat window keeps its current scrollback until logout, but the saved file is wiped immediately. Other characters are not affected.",
                "Clear History")
            clearCard.AddRow(row(clearCard.frame, "Clear history for this character", clearBtn))

            local clearAllBtn = GUI:CreateButton(clearCard.frame, "Clear all characters", 180, 24, function()
                GUI:ShowConfirmation({
                    title = "Clear All Chat History?",
                    message = "Clear this character's persisted chat history now, and clear every other character on their next login?",
                    warningText = "This cannot be undone. Other characters' saved files are only loaded by WoW when that character logs in, so they will be wiped at their next login.",
                    acceptText = "Clear All",
                    cancelText = "Cancel",
                    isDestructive = true,
                    onAccept = function()
                        if ns.QUI and ns.QUI.Chat and ns.QUI.Chat.History and ns.QUI.Chat.History.ClearAllCharacters then
                            local characters, entries = ns.QUI.Chat.History.ClearAllCharacters()
                            if DEFAULT_CHAT_FRAME then
                                DEFAULT_CHAT_FRAME:AddMessage(string.format(
                                    "|cff34D399[QUI]|r Cleared this character now (%d character%s, %d entr%s). Other characters will clear on their next login.",
                                    characters or 0,
                                    characters == 1 and "" or "s",
                                    entries or 0,
                                    entries == 1 and "y" or "ies"
                                ), 1, 1, 1)
                            end
                        end
                    end,
                })
            end)
            GUI:AttachTooltip(clearAllBtn,
                "Erase this character's history now and queue every other character on this account to clear on their next login (WoW only loads each character's saved file when that character logs in).",
                "Clear All Characters")
            clearCard.AddRow(row(clearCard.frame, "Clear history for all characters", clearAllBtn))
            clearCard.Finalize()
            sy = sy - clearCard.frame:GetHeight() - GAP

            -- Advanced: per-channel retention overrides.
            -- Each chat-type group below gets its own paired row of [override
            -- toggle | days slider]. When the toggle is on, the override-days
            -- value is written into hist.perChannelRetention[<key>]; when off,
            -- the entry is removed (nil = use default).
            TrackPersistentHistoryRegion(ns.QUI_Options.CreateAccentDotLabel(body, "Advanced: per-channel retention overrides", sy))
            sy = sy - 30

            local advancedHelp = TrackPersistentHistoryRegion(GUI:CreateLabel(body, "Override the default retention for individual chat types. Off = use default.", 10, {0.5, 0.5, 0.5, 1}))
            advancedHelp:SetPoint("TOPLEFT", 4, sy)
            advancedHelp:SetPoint("RIGHT", body, "RIGHT", 0, 0)
            advancedHelp:SetJustifyH("LEFT")
            sy = sy - 20

            -- Channel-type groups exposed for override. Keys map to the chat
            -- types described in the design spec; storage uses the same key
            -- string so pruneExpired can look them up directly via entry.c.
            local CHANNEL_GROUPS = {
                { key = "GUILD",         label = "Guild" },
                { key = "OFFICER",       label = "Officer" },
                { key = "PARTY",         label = "Party" },
                { key = "RAID",          label = "Raid" },
                { key = "INSTANCE_CHAT", label = "Instance chat" },
                { key = "SAY",           label = "Say" },
                { key = "YELL",          label = "Yell" },
                { key = "WHISPER",       label = "Whisper" },
                { key = "SYSTEM",        label = "System / Loot" },
                { key = "CHANNEL",       label = "Numbered / custom channels" },
            }

            -- Proxy table per group: __index returns true if override exists,
            -- and the slider key returns the saved value (or default 7).
            -- __newindex toggles or sets accordingly. This lets the standard
            -- CreateFormCheckbox / CreateFormSlider widgets read/write a map
            -- entry transparently.
            local function makeGroupProxy(groupKey)
                return MarkTransientOptionsBinding(setmetatable({}, {
                    __index = function(_, k)
                        if k == "enabled" then
                            return hist.perChannelRetention[groupKey] ~= nil
                        elseif k == "days" then
                            return hist.perChannelRetention[groupKey] or hist.retentionDays or 7
                        end
                        return nil
                    end,
                    __newindex = function(_, k, v)
                        if k == "enabled" then
                            if v then
                                if hist.perChannelRetention[groupKey] == nil then
                                    hist.perChannelRetention[groupKey] = hist.retentionDays or 7
                                end
                            else
                                hist.perChannelRetention[groupKey] = nil
                            end
                        elseif k == "days" then
                            if type(v) == "number" and hist.perChannelRetention[groupKey] ~= nil then
                                hist.perChannelRetention[groupKey] = v
                            end
                        end
                    end,
                }))
            end

            local overrideCard = ns.QUI_Options.CreateSettingsCardGroup(body, sy)
            for _, group in ipairs(CHANNEL_GROUPS) do
                local proxy = makeGroupProxy(group.key)
                local overrideCheckbox = TrackPersistentHistoryControl(GUI:CreateFormCheckbox(overrideCard.frame, nil, "enabled", proxy, function()
                    Refresh()
                    UpdatePersistentHistoryStates()
                end, { description = "When on, " .. group.label .. " messages use the days slider on the right instead of the default retention. When off, the default applies." }))
                local daysSlider = GUI:CreateFormSlider(overrideCard.frame, nil, 1, 30, 1, "days", proxy, Refresh, nil, { description = "Retention in days for " .. group.label .. " messages when the override toggle on the left is on. Ignored otherwise." })
                historyOverrideControls[#historyOverrideControls + 1] = { proxy = proxy, days = daysSlider }
                overrideCard.AddRow(row(overrideCard.frame, "Override " .. group.label, overrideCheckbox), row(overrideCard.frame, group.label .. " days", daysSlider))
            end
            overrideCard.Finalize()
            sy = sy - overrideCard.frame:GetHeight() - GAP

            -- Reset overrides card.
            local resetCard = ns.QUI_Options.CreateSettingsCardGroup(body, sy)
            local resetBtn
            resetBtn = TrackPersistentHistoryControl(GUI:CreateButton(resetCard.frame, "Reset all overrides", 180, 24, function()
                wipe(hist.perChannelRetention)
                NotifyProviderFor(resetBtn, { structural = true })
                Refresh()
            end))
            GUI:AttachTooltip(resetBtn,
                "Clear every per-channel retention override. Channels fall back to the global retention setting above.",
                "Reset Overrides")
            resetCard.AddRow(row(resetCard.frame, "Reset all overrides", resetBtn))
            resetCard.Finalize()
            sy = sy - resetCard.frame:GetHeight() - GAP

            -- Excluded channels.
            -- Renders one toggle per channel name, paired 2-up. The "Currently
            -- joined" group comes from a GetChannelList() snapshot taken when
            -- the section was built (see excludedJoinedSnapshot above); names
            -- previously excluded but no longer in the join list appear under
            -- "Stored but not joined" so they remain manageable. Storage:
            -- hist.excludedChannels is a set keyed by channel name, with nil
            -- for not-excluded — the proxy below mirrors toggle state to set
            -- membership and never writes a literal false.
            TrackPersistentHistoryRegion(ns.QUI_Options.CreateAccentDotLabel(body, "Excluded channels", sy))
            sy = sy - 30

            local excludedHelp = TrackPersistentHistoryRegion(GUI:CreateLabel(body, "Captures from enabled channels are dropped before storage. Re-open settings after joining or leaving a channel to refresh the list.", 10, {0.5, 0.5, 0.5, 1}))
            excludedHelp:SetPoint("TOPLEFT", 4, sy)
            excludedHelp:SetPoint("RIGHT", body, "RIGHT", 0, 0)
            excludedHelp:SetJustifyH("LEFT")
            excludedHelp:SetWordWrap(true)
            sy = sy - 30

            local excludedProxy = MarkTransientOptionsBinding(setmetatable({}, {
                __index = function(_, k)
                    return hist.excludedChannels[k] == true
                end,
                __newindex = function(_, k, v)
                    if v then
                        hist.excludedChannels[k] = true
                    else
                        hist.excludedChannels[k] = nil
                    end
                end,
            }))

            if #excludedJoinedSnapshot == 0 and #excludedStaleSnapshot == 0 then
                local emptyLabel = TrackPersistentHistoryRegion(GUI:CreateLabel(body, "    (Not currently joined to any channels.)", 10, {0.5, 0.5, 0.5, 1}))
                emptyLabel:SetPoint("TOPLEFT", 8, sy)
                emptyLabel:SetPoint("RIGHT", body, "RIGHT", 0, 0)
                emptyLabel:SetJustifyH("LEFT")
                sy = sy - FORM_ROW
            else
                if #excludedJoinedSnapshot > 0 then
                    local joinedCard = ns.QUI_Options.CreateSettingsCardGroup(body, sy)
                    local function makeExcludedToggle(channelName, desc)
                        return TrackPersistentHistoryControl(GUI:CreateFormToggle(joinedCard.frame, nil, channelName, excludedProxy, nil, { description = desc }))
                    end
                    for i = 1, #excludedJoinedSnapshot, 2 do
                        local n1, n2 = excludedJoinedSnapshot[i], excludedJoinedSnapshot[i + 1]
                        local cellL = row(joinedCard.frame, n1, makeExcludedToggle(n1, "Drop captures from '" .. n1 .. "' before they reach persistent history."))
                        local cellR
                        if n2 then
                            cellR = row(joinedCard.frame, n2, makeExcludedToggle(n2, "Drop captures from '" .. n2 .. "' before they reach persistent history."))
                        end
                        joinedCard.AddRow(cellL, cellR)
                    end
                    joinedCard.Finalize()
                    sy = sy - joinedCard.frame:GetHeight() - GAP
                end

                if #excludedStaleSnapshot > 0 then
                    TrackPersistentHistoryRegion(ns.QUI_Options.CreateAccentDotLabel(body, "Stored but not joined", sy))
                    sy = sy - 30

                    local staleCard = ns.QUI_Options.CreateSettingsCardGroup(body, sy)
                    local function makeStaleToggle(channelName)
                        return TrackPersistentHistoryControl(GUI:CreateFormToggle(staleCard.frame, nil, channelName, excludedProxy, nil,
                            { description = "Stored exclusion for '" .. channelName .. "'. Disable to remove from the persistent exclusion set." }))
                    end
                    for i = 1, #excludedStaleSnapshot, 2 do
                        local n1, n2 = excludedStaleSnapshot[i], excludedStaleSnapshot[i + 1]
                        local cellL = row(staleCard.frame, n1, makeStaleToggle(n1))
                        local cellR
                        if n2 then
                            cellR = row(staleCard.frame, n2, makeStaleToggle(n2))
                        end
                        staleCard.AddRow(cellL, cellR)
                    end
                    staleCard.Finalize()
                    sy = sy - staleCard.frame:GetHeight() - GAP
                end
            end
            UpdatePersistentHistoryStates()
            local computedHeight = math.abs(sy) + 8
            body:SetHeight(computedHeight)
            return computedHeight
        end, persistentHistorySectionHeight)

        -- Channel Colors
        -- Per-channel color overrides via ns.QUI.Chat.ChannelColors. The
        -- dropdown lists every editable built-in chat type and every joined
        -- custom channel; the swatch + reset row act on the current selection.
        CreateChatCustomSection("channelColors", "Channel Colors", function(body)
            local sy = -4
            local CC = ns.QUI and ns.QUI.Chat and ns.QUI.Chat.ChannelColors

            -- Session-only selection state (not persisted to SV).
            local selected = {
                current = (CC and CC.BUILTIN_KEYS and CC.BUILTIN_KEYS[1]) or "SAY",
            }

            local UpdateRow  -- forward declaration; assigned below.

            local function buildOptions()
                local out = {}
                if CC and CC.BUILTIN_KEYS and CC.BUILTIN_LABELS then
                    for i = 1, #CC.BUILTIN_KEYS do
                        local builtinKey = CC.BUILTIN_KEYS[i]
                        out[#out + 1] = {
                            value = builtinKey,
                            text = "Built-in: " .. (CC.BUILTIN_LABELS[builtinKey] or builtinKey),
                        }
                    end
                end
                if type(GetChannelList) == "function" then
                    local data = { GetChannelList() }
                    for i = 1, #data, 3 do
                        local slot, name, header = data[i], data[i + 1], data[i + 2]
                        if slot and name and not header then
                            out[#out + 1] = { value = name, text = "Channel: " .. name }
                        end
                    end
                end
                return out
            end

            local channelOptions = buildOptions()
            local dropdown = GUI:CreateFormDropdown(
                body,
                "Channel",
                channelOptions,
                "current",
                selected,
                function(v)
                    selected.current = v
                    if UpdateRow then UpdateRow() end
                end,
                nil,
                { searchable = true }
            )
            sy = P(dropdown, body, sy)

            -- Swatch + reset row (custom horizontal layout — CreateColorPicker
            -- is hard-bound to a single dbKey/dbTable, but our key changes
            -- with the dropdown selection, so we wire the swatch by hand).
            local swatchRow = CreateFrame("Frame", nil, body)
            swatchRow:SetHeight(FORM_ROW)
            swatchRow:SetPoint("TOPLEFT", 0, sy)
            swatchRow:SetPoint("RIGHT", body, "RIGHT", 0, 0)

            local rowLabel = swatchRow:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            local rowLabelFont = ns.UIKit and ns.UIKit.ResolveFontPath and ns.UIKit.ResolveFontPath(QUI.GUI:GetFontPath())
            local rowLabelColors = (QUI.GUI and QUI.GUI.Colors) or {}
            local rowLabelText = rowLabelColors.text or {1, 1, 1, 1}
            rowLabel:SetFont(rowLabelFont or select(1, rowLabel:GetFont()), 11, "")
            rowLabel:SetTextColor(rowLabelText[1], rowLabelText[2], rowLabelText[3], 1)
            rowLabel:SetPoint("LEFT", 0, 0)
            rowLabel:SetText("Color")

            local swatch = CreateFrame("Button", nil, swatchRow, "BackdropTemplate")
            swatch:SetSize(16, 16)
            swatch:SetPoint("LEFT", swatchRow, "LEFT", 180, 0)
            swatch:SetBackdrop({
                bgFile = "Interface\\Buttons\\WHITE8x8",
                edgeFile = "Interface\\Buttons\\WHITE8x8",
                edgeSize = 1,
            })
            swatch:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)
            swatch:SetScript("OnEnter", function(self)
                pcall(self.SetBackdropBorderColor, self, 0.2, 0.83, 0.6, 1)
            end)
            swatch:SetScript("OnLeave", function(self)
                pcall(self.SetBackdropBorderColor, self, 0.4, 0.4, 0.4, 1)
            end)

            local resetBtn = GUI:CreateButton(swatchRow, "Reset", 80, 22, function()
                if not CC then return end
                CC.Clear(selected.current)
                if UpdateRow then UpdateRow() end
            end)
            resetBtn:SetPoint("LEFT", swatch, "RIGHT", 12, 0)
            GUI:AttachTooltip(resetBtn,
                "Reset just this channel's color back to Blizzard's default. Other channel overrides are unaffected.",
                "Reset Color")

            UpdateRow = function()
                if not CC then return end
                local r, g, b = CC.GetEffective(selected.current)
                swatch:SetBackdropColor(r, g, b, 1)
                if CC.HasOverride(selected.current) then
                    if resetBtn.Enable then resetBtn:Enable() end
                    resetBtn:SetAlpha(1)
                else
                    if resetBtn.Disable then resetBtn:Disable() end
                    resetBtn:SetAlpha(0.5)
                end
            end

            swatch:SetScript("OnClick", function()
                if not CC then return end
                local r, g, b = CC.GetEffective(selected.current)
                local hadOverride = CC.HasOverride(selected.current)
                local info = {
                    r = r, g = g, b = b,
                    opacity = 1,
                    hasOpacity = false,
                    swatchFunc = function()
                        local nr, ng, nb = ColorPickerFrame:GetColorRGB()
                        CC.Set(selected.current, nr, ng, nb)
                        if UpdateRow then UpdateRow() end
                    end,
                    cancelFunc = function(prev)
                        if hadOverride then
                            CC.Set(selected.current, prev.r, prev.g, prev.b)
                        else
                            CC.Clear(selected.current)
                        end
                        if UpdateRow then UpdateRow() end
                    end,
                }
                -- Bump the picker above the QUI settings window strata (it
                -- otherwise opens behind), and use the hide-then-reopen
                -- dance if it's already shown so ShowUIPanel's toggle logic
                -- doesn't turn our second Setup call into a close.
                local function OpenPicker()
                    ColorPickerFrame:SetupColorPickerAndShow(info)
                    ColorPickerFrame:SetFrameStrata("TOOLTIP")
                    ColorPickerFrame:Raise()
                end
                if ColorPickerFrame:IsShown() then
                    HideUIPanel(ColorPickerFrame)
                    C_Timer.After(0, OpenPicker)
                else
                    OpenPicker()
                end
            end)

            sy = sy - (FORM_ROW or 24)

            local resetAllBtn = GUI:CreateButton(body, "Reset All Colors", 180, 24, function()
                if not CC then return end
                CC.ClearAll()
                if UpdateRow then UpdateRow() end
            end)
            resetAllBtn:SetPoint("TOPLEFT", 0, sy)
            GUI:AttachTooltip(resetAllBtn,
                "Reset every channel color override back to Blizzard's defaults. This affects all channels at once.",
                "Reset All Colors")
            sy = sy - (FORM_ROW or 24)

            UpdateRow()
            local computedHeight = math.abs(sy) + 8
            body:SetHeight(computedHeight)
            return computedHeight
        end, 4 * FORM_ROW + 8)

        -- UI Cleanup
        CreateChatSection("uiCleanup", "UI Cleanup", 2 * FORM_ROW + 8, function(card)
            local w = GUI:CreateFormCheckbox(card.frame, nil, "hideButtons", chat, Refresh, { description = "Hide the social and channel buttons on each chat frame. The scrollbar stays visible." })
            card.AddRow(row(card.frame, "Hide Chat Buttons", w))
        end)

        -- Copy Button
        CreateChatSection("copyButton", "Copy Button", 4 * FORM_ROW + 8, function(card)
            local copyButtonOptions = {
                {value = "always", text = "Fade When Idle"},
                {value = "hover", text = "Hide When Idle"},
                {value = "disabled", text = "Disabled"},
            }
            local copySourceOptions = {
                {value = "live", text = "Current Scrollback"},
                {value = "persisted", text = "Persisted History"},
            }
            local scrollbackOptions = {
                {value = 0, text = "Client Default"},
                {value = 500, text = "500 Lines"},
                {value = 1000, text = "1,000 Lines"},
                {value = 2500, text = "2,500 Lines"},
                {value = 5000, text = "5,000 Lines"},
            }
            local copySourceDropdown
            local function UpdateCopyButtonStates()
                SetControlEnabled(copySourceDropdown, chat.copyButtonMode ~= "disabled")
            end
            local copyButtonDropdown = GUI:CreateFormDropdown(card.frame, nil, copyButtonOptions, "copyButtonMode", chat, function()
                Refresh()
                UpdateCopyButtonStates()
            end, { description = "Controls whether the copy glyph stays faintly visible, hides when idle, or is disabled." })
            copySourceDropdown = GUI:CreateFormDropdown(card.frame, nil, copySourceOptions, "copyHistorySource", chat, Refresh, { description = "Choose whether the copy popup reads the current live scrollback or the persisted history buffer. Persisted history must be enabled above." })
            card.AddRow(row(card.frame, "Copy Button", copyButtonDropdown), row(card.frame, "Copy Source", copySourceDropdown))
            local scrollbackDropdown = GUI:CreateFormDropdown(card.frame, nil, scrollbackOptions, "scrollbackLines", chat, Refresh, { description = "Sets the live chat frame scrollback cap. Changing this can clear the current visible buffer once per frame." })
            card.AddRow(row(card.frame, "Scrollback Lines", scrollbackDropdown))
            UpdateCopyButtonStates()
        end)

        -- New Message Sound
        CreateChatCustomSection("newMessageSound", "New Message Sound", function(body)
            local sy = -4
            if not chat.newMessageSound then
                chat.newMessageSound = { enabled = false, entries = {{ channel = "guild_officer", sound = "None" }} }
            end
            if not chat.newMessageSound.entries or #chat.newMessageSound.entries == 0 then
                chat.newMessageSound.entries = {{ channel = "guild_officer", sound = "None" }}
            end

            local soundDependentControls = {}
            local function TrackSoundControl(control)
                soundDependentControls[#soundDependentControls + 1] = control
                return control
            end
            local function UpdateNewMessageSoundStates()
                local enabled = chat.newMessageSound.enabled == true
                for i = 1, #soundDependentControls do
                    SetControlEnabled(soundDependentControls[i], enabled)
                end
            end

            local soundEnableCheckbox = GUI:CreateFormCheckbox(body, "Play Sound on New Message", "enabled", chat.newMessageSound, function()
                Refresh()
                UpdateNewMessageSoundStates()
            end, { description = "Master toggle for playing sounds on incoming chat messages. Configure per-channel sounds below." })
            sy = P(soundEnableCheckbox, body, sy)

            local soundEntriesContainer = CreateFrame("Frame", nil, body)
            soundEntriesContainer:SetPoint("TOPLEFT", 0, sy)
            soundEntriesContainer:SetPoint("RIGHT", body, "RIGHT", 0, 0)
            soundEntriesContainer:SetHeight(1)
            soundEntriesContainer._quiDualColumnFullWidth = true
            soundEntriesContainer._quiDualColumnRowHeight = 1

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

            -- In V3 there's no collapsible "section" wrapper around body; the
            -- body IS the custom-block container. Dynamic add/remove already
            -- triggers a structural NotifyProviderFor, which recreates the
            -- panel — so initial height is the only quantity we need here.
            local lastTotalHeight = 0

            local function RebuildSoundEntries()
                soundEntriesContainer:SetHeight(0)
                for i = #soundDependentControls, 1, -1 do
                    soundDependentControls[i] = nil
                end
                for _, child in ipairs({ soundEntriesContainer:GetChildren() }) do
                    child:Hide()
                    child:SetParent(nil)
                end

                local entries = chat.newMessageSound.entries
                if not entries then return end

                local rowY = 0
                for i, entry in ipairs(entries) do
                    local entryRow = CreateFrame("Frame", nil, soundEntriesContainer)
                    entryRow:SetPoint("TOPLEFT", 0, -rowY)
                    entryRow:SetPoint("RIGHT", soundEntriesContainer, "RIGHT", 0, 0)
                    entryRow:SetHeight(FORM_ROW)

                    local channelOpts = GetChannelOptionsForEntry(entries, i)
                    if #channelOpts == 0 then
                        channelOpts = {{value = entry.channel or "guild_officer", text = entry.channel or "guild_officer"}}
                    end

                    local function OnChannelChange()
                        Refresh()
                        RebuildSoundEntries()
                    end
                    local channelDropdown = TrackSoundControl(GUI:CreateFormDropdown(entryRow, "Channel", channelOpts, "channel", entry, OnChannelChange, { description = "Chat channel this sound entry listens for. Each channel can only be assigned to one entry." }))
                    if GUI.SetWidgetProviderSyncOptions then
                        GUI:SetWidgetProviderSyncOptions(channelDropdown, { auto = true, structural = true })
                    end
                    channelDropdown:SetPoint("TOPLEFT", 0, 0)
                    channelDropdown:SetPoint("RIGHT", entryRow, "RIGHT", -80, 0)

                    local soundList = U.GetSoundList()
                    local soundDropdown = TrackSoundControl(GUI:CreateFormDropdown(entryRow, "Sound", soundList, "sound", entry, Refresh, { description = "Sound to play when a message arrives on this channel." }))
                    soundDropdown:SetPoint("TOPLEFT", 0, -FORM_ROW)
                    soundDropdown:SetPoint("RIGHT", entryRow, "RIGHT", -80, 0)

                    local removeBtn = GUI:CreateButton(entryRow, "X", 24, 22, function()
                        table.remove(entries, i)
                        RebuildSoundEntries()
                        Refresh()
                        NotifyProviderFor(removeBtn, { structural = true })
                    end)
                    GUI:AttachTooltip(removeBtn,
                        "Remove this channel/sound pairing. New messages on this channel will stop playing a sound.",
                        "Remove Entry")
                    TrackSoundControl(removeBtn)
                    removeBtn:SetPoint("RIGHT", entryRow, "RIGHT", 0, -FORM_ROW/2)

                    entryRow:SetHeight(FORM_ROW * 2)
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
                    local addBtn = TrackSoundControl(GUI:CreateButton(soundEntriesContainer, "+ Add Channel + Sound", 180, 24, function()
                        local channel = GetFirstAvailableChannel()
                        if not channel then return end
                        table.insert(chat.newMessageSound.entries, { channel = channel, sound = "None" })
                        RebuildSoundEntries()
                        Refresh()
                        NotifyProviderFor(addBtn, { structural = true })
                    end))
                    GUI:AttachTooltip(addBtn,
                        "Add another channel-to-sound pairing. Pick the channel and the sound to play when a new message arrives there.",
                        "Add Channel + Sound")
                    addBtn:SetPoint("TOPLEFT", 0, -rowY - 4)
                    rowY = rowY + 28
                end
                soundEntriesContainer:SetHeight(rowY)
                soundEntriesContainer._quiDualColumnRowHeight = math.max(FORM_ROW, rowY)

                local totalHeight = FORM_ROW + 8 + rowY + 30
                lastTotalHeight = totalHeight
                body:SetHeight(totalHeight)
                UpdateNewMessageSoundStates()
            end

            RebuildSoundEntries()

            local info = GUI:CreateLabel(body, "Each channel can have its own sound. Saved to your profile.", 10, {0.5, 0.5, 0.5, 1})
            info:SetPoint("TOPLEFT", soundEntriesContainer, "BOTTOMLEFT", 0, -8)
            info:SetPoint("RIGHT", body, "RIGHT", 0, 0)
            info:SetJustifyH("LEFT")
            local finalHeight = lastTotalHeight + 24
            body:SetHeight(finalHeight)
            return finalHeight
        end, FORM_ROW * 4)

        U.BuildPositionCollapsible(content, "chatFrame1", nil, L.sections, L.relayoutSections)
        U.BuildOpenFullSettingsLink(content, key, L.sections, L.relayoutSections)
        L.relayoutSections()
        return content:GetHeight()
    end })
end)
