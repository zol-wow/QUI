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
    local CreateTileCollapsible = ctx.CreateTileCollapsible or U.CreateCollapsible
    local function RegisterSharedOnly(key, provider)
        ctx.RegisterShared(key, provider)
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

    -- Build dropdown options for the per-frame editor selectors. Excludes
    -- combat log frames — neither tab filters nor a custom button bar make
    -- sense on a frame whose purpose is the system-driven combat-log feed.
    local function buildFrameOptions()
        local opts = {}
        local n = _G.NUM_CHAT_WINDOWS or 10
        for i = 1, n do
            local f = _G["ChatFrame" .. i]
            if f and not f.isCombatLog then
                local tab = _G["ChatFrame" .. i .. "Tab"]
                local tabName = tab and tab.GetText and tab:GetText()
                local label
                if type(tabName) == "string" and tabName ~= "" then
                    label = "ChatFrame" .. i .. " (" .. tabName .. ")"
                else
                    label = "ChatFrame" .. i
                end
                opts[#opts + 1] = { value = i, text = label }
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
    RegisterSharedOnly("chatFrame1", { build = function(content, key, width, options)
        local db = U.GetProfileDB()
        if not db or not db.chat then return 80 end
        local chat = db.chat
        local sections = {}
        local function relayout() U.StandardRelayout(content, sections) end
        local function Refresh() if _G.QUI_RefreshChat then _G.QUI_RefreshChat() end end

        local sectionPresets = {
            general = {
                "chatModule", "frameSize", "introMessage", "defaultTab",
                "chatBackground", "inputBoxBackground", "commandHistory",
                "messageFade", "urlDetection", "chatHyperlinks",
                "uiCleanup", "copyButton",
            },
            filters = { "tabFilters" },
            buttonBar = { "buttonBar" },
            alerts = {
                "timestamps", "messageModifiers", "keywordAlert",
                "redundantTextCleanup", "newMessageSound",
            },
            history = {
                "persistentMessageHistory", "messageHistory",
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

        local function CreateChatSection(sectionId, title, contentHeight, buildFunc, sectionList, relayoutFn)
            if not ShouldRenderSection(sectionId) then
                return nil
            end
            return CreateTileCollapsible(
                content,
                title,
                contentHeight,
                buildFunc,
                sectionList or sections,
                relayoutFn or relayout
            )
        end

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

        -- Master enable toggle. Disabling tears down all chat customization
        -- (glass, tabs, edit box, copy buttons, fade, message filters); the
        -- per-feature toggles below remain visible but no-op until re-enabled.
        CreateChatSection("chatModule", "Chat Module", FORM_ROW + 8, function(body)
            local sy = -4
            sy = P(GUI:CreateFormCheckbox(body, "Enable Chat Module", "enabled", chat, Refresh, { description = "Master switch for QUI's chat customization. When off, all chat frames revert to Blizzard defaults and the per-feature toggles below have no effect." }), body, sy)
        end, sections, relayout)

        local widthSlider, heightSlider
        CreateChatSection("frameSize", "Frame Size", 2 * FORM_ROW + 8, function(body)
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
        CreateChatSection("introMessage", "Intro Message", 2 * FORM_ROW + 8, function(body)
            local sy = -4
            sy = P(GUI:CreateFormCheckbox(body, "Show Login Message", "showIntroMessage", chat, nil, { description = "Display the QUI reminder/intro tips in chat when you log in." }), body, sy)
            local info = GUI:CreateLabel(body, "Display the QUI reminder tips when you log in.", 10, {0.5, 0.5, 0.5, 1})
            info:SetPoint("TOPLEFT", 0, sy)
            info:SetPoint("RIGHT", body, "RIGHT", 0, 0)
            info:SetJustifyH("LEFT")
        end, sections, relayout)

        -- Default Tab
        CreateChatSection("defaultTab", "Default Tab", 3 * FORM_ROW + 8, function(body)
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
                container._quiDualColumnFullWidth = true

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

                local perSpecCheck
                perSpecCheck = GUI:CreateFormCheckbox(container, "Per Spec", "defaultTabPerSpec", chat, function()
                    Refresh()
                    NotifyProviderFor(perSpecCheck, { structural = true })
                    RebuildDefaultTab()
                end, { description = "Switch to per-spec default chat tabs instead of a single default. Each spec gets its own dropdown above." })
                sy = P(perSpecCheck, container, sy)

                local containerHeight = math.max(FORM_ROW, math.abs(sy) + 4)
                container:SetHeight(containerHeight)
                container._quiDualColumnRowHeight = containerHeight
            end

            RebuildDefaultTab()
        end, sections, relayout)

        -- Chat Background
        if chat.glass then
            CreateChatSection("chatBackground", "Chat Background", 3 * FORM_ROW + 8, function(body)
                local sy = -4
                sy = P(GUI:CreateFormCheckbox(body, "Chat Background Texture", "enabled", chat.glass, Refresh, { description = "Draw an opaque background behind the chat frame so text stays readable over busy scenery." }), body, sy)
                sy = P(GUI:CreateFormSlider(body, "Background Opacity", 0, 1.0, 0.05, "bgAlpha", chat.glass, Refresh, nil, { description = "Opacity of the chat background (0 is invisible, 1 is fully opaque)." }), body, sy)
                P(GUI:CreateFormColorPicker(body, "Background Color", "bgColor", chat.glass, Refresh, nil, { description = "Color of the chat background." }), body, sy)
            end, sections, relayout)
        end

        -- Input Box Background
        if chat.editBox then
            CreateChatSection("inputBoxBackground", "Input Box Background", 5 * FORM_ROW + 8, function(body)
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

        -- Command History (Phase C)
        -- Persistent Up/Down arrow recall. Settings live on the profile;
        -- the captured entries are per-character at
        -- db.char.chat.editboxHistory.entries (initialized lazily by
        -- editbox_history.lua's getStore on first capture or recall).
        CreateChatSection("commandHistory", "Command History", 4 * FORM_ROW + 8, function(body)
            local sy = -4
            if not chat.editboxHistory then
                chat.editboxHistory = {
                    enabled = true,
                    maxEntries = 200,
                    filterSensitive = true,
                    restoreChatType = true,
                }
            end
            local ebh = chat.editboxHistory

            sy = P(GUI:CreateFormCheckbox(body, "Persistent command history", "enabled", ebh, Refresh, { description = "Save messages you send so the Up/Down arrows recall them after a /reload. Stored per-character. Disabling stops new captures and recall but does not delete prior entries." }), body, sy)
            sy = P(GUI:CreateFormSlider(body, "Max history entries", 50, 500, 1, "maxEntries", ebh, Refresh, nil, { description = "Maximum number of recalled messages to keep per character. Oldest entries are dropped first when the cap is reached." }), body, sy)
            sy = P(GUI:CreateFormCheckbox(body, "Filter sensitive commands", "filterSensitive", ebh, Refresh, { description = "Skip storing commands that frequently contain secrets or raw Lua. Filtered prefixes: /password, /logout, /quit, /exit, /dnd, /afk, /camp, /script, /run, /console." }), body, sy)
            P(GUI:CreateFormCheckbox(body, "Restore chat type on recall", "restoreChatType", ebh, Refresh, { description = "When recalling a message with Up/Down, also restore its original chat type (Say, Yell, Whisper target, channel) so pressing Enter sends to the same destination." }), body, sy)
        end, sections, relayout)

        -- Message Fade
        if chat.fade then
            CreateChatSection("messageFade", "Message Fade", 2 * FORM_ROW + 8, function(body)
                local sy = -4
                sy = P(GUI:CreateFormCheckbox(body, "Fade Messages After Inactivity", "enabled", chat.fade, Refresh, { description = "Fade old chat messages out after no new messages have arrived for the delay below." }), body, sy)
                P(GUI:CreateFormSlider(body, "Fade Delay (seconds)", 1, 120, 1, "delay", chat.fade, Refresh, nil, { description = "Seconds of inactivity before chat messages start fading." }), body, sy)
            end, sections, relayout)
        end

        -- URL Detection
        if chat.urls then
            CreateChatSection("urlDetection", "URL Detection", 2 * FORM_ROW + 8, function(body)
                local sy = -4
                sy = P(GUI:CreateFormCheckbox(body, "Make URLs Clickable", "enabled", chat.urls, Refresh, { description = "Detect URLs in chat and click them to open a copy dialog." }), body, sy)
                local info = GUI:CreateLabel(body, "Click any URL in chat to open a copy dialog.", 10, {0.5, 0.5, 0.5, 1})
                info:SetPoint("TOPLEFT", 0, sy)
                info:SetPoint("RIGHT", body, "RIGHT", 0, 0)
                info:SetJustifyH("LEFT")
            end, sections, relayout)
        end

        -- Chat Hyperlinks (Phase D)
        if not chat.hyperlinks then
            chat.hyperlinks = { coordinates = true, friendlyURLs = false, interactiveNames = true }
        end
        CreateChatSection("chatHyperlinks", "Chat Hyperlinks", 3 * FORM_ROW + 8, function(body)
            local sy = -4
            sy = P(GUI:CreateFormCheckbox(body, "Coordinate links", "coordinates", chat.hyperlinks, Refresh,
                { description = "Detects (x, y) coordinate patterns in chat and makes them clickable waypoints." }), body, sy)
            sy = P(GUI:CreateFormCheckbox(body, "Friendly URL labels", "friendlyURLs", chat.hyperlinks, Refresh,
                { description = "Replace common WoW-community URLs with readable labels — e.g., wowhead.com -> [Wowhead]." }), body, sy)
            sy = P(GUI:CreateFormCheckbox(body, "Interactive player names", "interactiveNames", chat.hyperlinks, Refresh,
                { description = "Click a class-colored player name in chat to open quick-action menu (Whisper, Invite, Add Friend, Ignore)." }), body, sy)
        end, sections, relayout)

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
                __index = function(_, key)
                    local list = getList()
                    if not list then return false end
                    for i = 1, #list do
                        if list[i] == key then return true end
                    end
                    return false
                end,
                __newindex = function(_, key, value)
                    local list = getList() or {}
                    if value then
                        for i = 1, #list do
                            if list[i] == key then return end
                        end
                        list[#list + 1] = key
                    else
                        for i = 1, #list do
                            if list[i] == key then
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

        -- Build the tab filter sub-tile body for the currently-selected frame.
        -- All data lookups (proxies, onChange handlers) read
        -- chat.tabs[selectedTabFilterFrame] dynamically, so frame-selector
        -- changes can soft-refresh existing widgets via :Refresh() instead
        -- of triggering a structural rebuild — WoW frames can't be GC'd, and
        -- every structural rebuild leaks ~25MB of orphaned widgets.
        --
        -- refreshList is appended to as widgets are built; the wrapper tile
        -- callback walks it on frame-selector change to update visuals.
        -- frameID/frameLabel are just initial cosmetic values (passed in by
        -- the caller); the actual frame is whichever selectedTabFilterFrame
        -- currently points to.
        local function buildTabFilterBody(body, frameID, frameLabel, startSy, refreshList, markLayoutItem)
            local sy = startSy or -4
            refreshList = refreshList or {}

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

            -- Customized toggle. Triggers reconcile + indicator update via
            -- the chat module's _afterRefresh chain (Refresh -> tab_filters
            -- ApplyEnabled). When toggled OFF the stored entry is preserved
            -- so re-enabling restores the user's selection.
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

            local headerLabel = GUI:CreateLabel(body, frameLabel, 11, {0.7, 0.85, 0.7, 1})
            if markLayoutItem then markLayoutItem(headerLabel, true) end
            headerLabel:SetPoint("TOPLEFT", 0, sy)
            headerLabel:SetPoint("RIGHT", body, "RIGHT", 0, 0)
            headerLabel:SetJustifyH("LEFT")
            -- Header label refresh: re-derive the label from frame options.
            refreshList[#refreshList + 1] = function()
                local opts = buildFrameOptions()
                for _, opt in ipairs(opts) do
                    if opt.value == selectedTabFilterFrame then
                        headerLabel:SetText(opt.text)
                        return
                    end
                end
                headerLabel:SetText("ChatFrame" .. selectedTabFilterFrame)
            end
            sy = sy - 18

            local customizedCheckbox = GUI:CreateFormCheckbox(body, "Customize this tab's filters", "_customized", customizedProxy, Refresh,
                { description = "When on, this tab shows ONLY the message groups and channels selected below. Inclusion-only — to silence a group, deselect it. When off, Blizzard's defaults apply unchanged." })
            if markLayoutItem then markLayoutItem(customizedCheckbox) end
            sy = P(customizedCheckbox, body, sy)
            refreshList[#refreshList + 1] = function() if customizedCheckbox.Refresh then customizedCheckbox:Refresh() end end

            -- Build the filter rows synchronously so the section appears in
            -- its final shape on the first render. Explicit layout sequence
            -- markers preserve header/group/channel ordering when the shared
            -- dual-column pass later sorts children and font-string regions.
            local groupsHeader = GUI:CreateLabel(body, "    Message groups", 10, {0.5, 0.5, 0.5, 1})
            if markLayoutItem then markLayoutItem(groupsHeader, true) end
            groupsHeader:SetPoint("TOPLEFT", 0, sy)
            groupsHeader:SetPoint("RIGHT", body, "RIGHT", 0, 0)
            groupsHeader:SetJustifyH("LEFT")
            sy = sy - 16

            local groupsProxy = makeArraySetProxy(
                function() return getCurEntry().groups end,
                function(list) getCurEntry().groups = list end
            )
            for _, key in ipairs(CHAT_GROUPS) do
                local cb = GUI:CreateFormCheckbox(body, "    " .. key, key, groupsProxy, function()
                    local e = getCurEntry()
                    if e.customized and ns.QUI and ns.QUI.Chat and ns.QUI.Chat.TabFilters then
                        ns.QUI.Chat.TabFilters.SaveTabConfig(selectedTabFilterFrame, e.groups, e.channels)
                    end
                    Refresh()
                end, { description = "Show " .. key .. " messages on this tab. Only takes effect while 'Customize this tab's filters' is on." })
                if markLayoutItem then markLayoutItem(cb) end
                cb:SetPoint("TOPLEFT", 0, sy)
                cb:SetPoint("RIGHT", body, "RIGHT", 0, 0)
                refreshList[#refreshList + 1] = function() if cb.Refresh then cb:Refresh() end end
                sy = sy - FORM_ROW
            end

            local channelsHeader = GUI:CreateLabel(body, "    Channels (current join list)", 10, {0.5, 0.5, 0.5, 1})
            if markLayoutItem then markLayoutItem(channelsHeader, true) end
            channelsHeader:SetPoint("TOPLEFT", 0, sy - 4)
            channelsHeader:SetPoint("RIGHT", body, "RIGHT", 0, 0)
            channelsHeader:SetJustifyH("LEFT")
            sy = sy - 18

            local channelsProxy = makeArraySetProxy(
                function() return getCurEntry().channels end,
                function(list) getCurEntry().channels = list end
            )
            local channels = getChannelNamesNow()
            if #channels == 0 then
                local noChan = GUI:CreateLabel(body, "        (Not currently in any custom channels.)", 10, {0.5, 0.5, 0.5, 1})
                if markLayoutItem then markLayoutItem(noChan, true) end
                noChan:SetPoint("TOPLEFT", 0, sy)
                noChan:SetPoint("RIGHT", body, "RIGHT", 0, 0)
                noChan:SetJustifyH("LEFT")
                sy = sy - 16
            else
                for _, channelName in ipairs(channels) do
                    local cb = GUI:CreateFormCheckbox(body, "    " .. channelName, channelName, channelsProxy, function()
                        local e = getCurEntry()
                        if e.customized and ns.QUI and ns.QUI.Chat and ns.QUI.Chat.TabFilters then
                            ns.QUI.Chat.TabFilters.SaveTabConfig(selectedTabFilterFrame, e.groups, e.channels)
                        end
                        Refresh()
                    end, { description = "Show messages from channel '" .. channelName .. "' on this tab." })
                    if markLayoutItem then markLayoutItem(cb) end
                    cb:SetPoint("TOPLEFT", 0, sy)
                    cb:SetPoint("RIGHT", body, "RIGHT", 0, 0)
                    refreshList[#refreshList + 1] = function() if cb.Refresh then cb:Refresh() end end
                    sy = sy - FORM_ROW
                end
            end

            local resetRow = CreateFrame("Frame", nil, body)
            if markLayoutItem then markLayoutItem(resetRow, true) end
            resetRow:SetPoint("TOPLEFT", 0, sy - 4)
            resetRow:SetPoint("RIGHT", body, "RIGHT", 0, 0)
            resetRow:SetHeight(FORM_ROW)

            local resetBtn
            resetBtn = GUI:CreateButton(resetRow, "Reset to Blizzard defaults", 200, 24, function()
                if ns.QUI and ns.QUI.Chat and ns.QUI.Chat.TabFilters then
                    ns.QUI.Chat.TabFilters.ResetTab(selectedTabFilterFrame)
                end
                NotifyProviderFor(resetBtn, { structural = true })
            end)
            resetBtn:SetPoint("TOPLEFT", 0, 0)

            local resetHelp = GUI:CreateLabel(resetRow, "Clears stored config. /reload to fully restore Blizzard's original groups.", 10, {0.5, 0.5, 0.5, 1})
            resetHelp:SetPoint("LEFT", resetBtn, "RIGHT", 12, 0)
            resetHelp:SetPoint("RIGHT", resetRow, "RIGHT", 0, 0)
            resetHelp:SetJustifyH("LEFT")
            sy = sy - FORM_ROW - 4

            if body then
                body._contentHeight = math.abs(sy) + 4
            end
        end

        -- Multi-frame tab-filter editor. The frame-selector dropdown writes
        -- to selectedTabFilterFrame (module-level upvalue) and triggers a
        -- structural rebuild of the panel so buildTabFilterBody re-runs with
        -- the newly selected frameID. tab_filters.lua reconciles whichever
        -- frameIDs appear in db.profile.chat.tabs, so changes saved here
        -- apply immediately to the chosen frame.
        --
        -- Tile height is pre-computed from the known row count so the section
        -- has a stable first layout before the shared dual-column compaction
        -- pass runs.
        local tabFilterChannelCount = 0
        if type(GetChannelList) == "function" then
            local data = { GetChannelList() }
            local i = 1
            while i + 1 <= #data do
                local name = data[i + 1]
                local isHeader = data[i + 2]
                if type(name) == "string" and name ~= "" and not isHeader then
                    tabFilterChannelCount = tabFilterChannelCount + 1
                end
                i = i + 3
            end
        end
        -- Layout vertical budget:
        --   FORM_ROW   frame-selector dropdown
        --   18         chat-frame label
        --   FORM_ROW   "Customize this tab" toggle
        --   16         "Message groups" subheader
        --   36*FORM_ROW  group checkboxes
        --   22         "Channels" subheader (incl. 4px gap)
        --   N*FORM_ROW or 16   channel checkboxes / "no channels" label
        --   FORM_ROW + 4   reset button row (+ gap)
        --   16         vertical padding
        local tabFilterChannelsBlock = (tabFilterChannelCount > 0) and (tabFilterChannelCount * FORM_ROW) or 16
        local tabFilterTileHeight = (FORM_ROW + 18 + FORM_ROW + 16 + 36 * FORM_ROW + 22 + tabFilterChannelsBlock + FORM_ROW + 4) + 16

        CreateChatSection("tabFilters", "Tab Filters", tabFilterTileHeight, function(body)
            local layoutSequence = 0
            local function markLayoutItem(item, fullWidth)
                if not item then return item end
                layoutSequence = layoutSequence + 1
                item._quiDualColumnSequence = layoutSequence
                if fullWidth then
                    item._quiDualColumnFullWidth = true
                end
                return item
            end

            local frameOptions = buildFrameOptions()
            -- Validate selection still exists (e.g. frame deleted between sessions).
            local validSelection = false
            for _, opt in ipairs(frameOptions) do
                if opt.value == selectedTabFilterFrame then validSelection = true; break end
            end
            if not validSelection then selectedTabFilterFrame = frameOptions[1].value end

            local selectorTable = MarkTransientOptionsBinding({ _selected = selectedTabFilterFrame })
            local frameLabel = "ChatFrame" .. selectedTabFilterFrame
            for _, opt in ipairs(frameOptions) do
                if opt.value == selectedTabFilterFrame then frameLabel = opt.text; break end
            end

            -- Soft-refresh registry. buildTabFilterBody appends a closure per
            -- widget; on frame-selector change we walk this list and call
            -- each widget's :Refresh() instead of triggering a structural
            -- rebuild — the latter leaks ~25MB of orphan widgets per change
            -- because WoW frames can't be GC'd.
            local refreshList = {}

            local sy = -4
            local frameSelector
            frameSelector = GUI:CreateFormDropdown(body, "Editing tab", frameOptions, "_selected", selectorTable, function()
                local newValue = selectorTable._selected or 1
                -- Idempotency guard: CreateFormDropdown's SetValue fires onChange
                -- on every click without checking value-changed, so re-clicking
                -- the same option used to no-op rebuild.
                if newValue == selectedTabFilterFrame then return end
                selectedTabFilterFrame = newValue
                -- Soft-refresh: re-bind existing widgets to the new frame's
                -- data via :Refresh(). Zero new widget allocation.
                for i = 1, #refreshList do
                    pcall(refreshList[i])
                end
            end, { description = "Pick which chat frame's tab filters to edit. Each frame stores its own filter set in db.profile.chat.tabs[<frameID>]; this dropdown only changes which one the controls below are bound to." })
            markLayoutItem(frameSelector)
            sy = P(frameSelector, body, sy)

            buildTabFilterBody(body, selectedTabFilterFrame, frameLabel, sy, refreshList, markLayoutItem)
        end, sections, relayout)
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

        local function buildButtonBarBody(body, frameID, frameLabel, startSy)
            local sy = startSy or -4

            local BB = ns.QUI and ns.QUI.Chat and ns.QUI.Chat.ButtonBar
            if not BB then
                local errLabel = GUI:CreateLabel(body, "Button Bar module not loaded.", 10, {1, 0.5, 0.5, 1})
                errLabel:SetPoint("TOPLEFT", 0, sy)
                errLabel:SetPoint("RIGHT", body, "RIGHT", 0, 0)
                return
            end

            -- Lazily initialise the entry with built-in defaults so toggles
            -- below have something to bind to. The bar stays disabled until
            -- the user flips the master toggle.
            local entry = BB.InitFrameDefaults(frameID)
            if not entry then return end

            local headerLabel = GUI:CreateLabel(body, frameLabel, 11, {0.7, 0.85, 0.7, 1})
            headerLabel:SetPoint("TOPLEFT", 0, sy)
            headerLabel:SetPoint("RIGHT", body, "RIGHT", 0, 0)
            headerLabel:SetJustifyH("LEFT")
            sy = sy - 18

            sy = P(GUI:CreateFormCheckbox(body, "Show button bar for this frame", "enabled", entry, Refresh,
                { description = "Master toggle for the custom button bar on this chat frame. When off, no bar is shown for this frame; the per-button selections below are preserved." }), body, sy)
            sy = P(GUI:CreateFormCheckbox(body, "Hide in combat", "hideInCombat", entry, Refresh,
                { description = "Hide this chat frame's button bar while you are in combat, then restore it after combat ends." }), body, sy)

            local positionOptions = {
                { value = "outside_left",  text = "Outside left (vertical strip)" },
                { value = "outside_right", text = "Outside right (vertical strip)" },
                { value = "inside_left",   text = "Inside left (vertical, above scrollback)" },
                { value = "inside_right",  text = "Inside right (vertical, above scrollback)" },
                { value = "inside_tabs",   text = "Inside tab row (horizontal)" },
                { value = "hidden",        text = "Hidden (configured but not shown)" },
            }
            sy = P(GUI:CreateFormDropdown(body, "Position", positionOptions, "position", entry, Refresh,
                { description = "Where the button bar attaches relative to the chat frame. outside_left/outside_right anchor outside the chat frame's edge; inside_left/inside_right anchor inside above the scrollback; inside_tabs lays buttons horizontally next to this chat frame's tab." }), body, sy)

            sy = P(GUI:CreateFormSlider(body, "X offset", -200, 200, 1, "offsetX", entry, Refresh, nil,
                { description = "Fine-tune the bar's horizontal position relative to the selected anchor. Positive values move right. In Inside tab row mode the anchor follows this chat frame's tab." }), body, sy)
            sy = P(GUI:CreateFormSlider(body, "Y offset", -200, 200, 1, "offsetY", entry, Refresh, nil,
                { description = "Fine-tune the bar's vertical position relative to the selected anchor. Positive values move up. In Inside tab row mode the anchor follows this chat frame's tab." }), body, sy)
            sy = P(GUI:CreateFormSlider(body, "Button spacing", 0, 24, 1, "buttonSpacing", entry, Refresh, nil,
                { description = "Pixels between buttons in this chat frame's button bar." }), body, sy)

            -- Built-in buttons checklist. Each entry in entry.buttons is
            -- { id = "<builtinKey>", visible = bool }. The proxy maps each
            -- builtin key to the visible flag of its matching array entry,
            -- creating one if missing on first toggle.
            local builtinHeader = GUI:CreateLabel(body, "    Built-in buttons", 10, {0.5, 0.5, 0.5, 1})
            builtinHeader:SetPoint("TOPLEFT", 0, sy)
            builtinHeader:SetPoint("RIGHT", body, "RIGHT", 0, 0)
            builtinHeader:SetJustifyH("LEFT")
            sy = sy - 16

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

            local builtinProxy = setmetatable({}, {
                __index = function(_, id)
                    local rec = findOrCreate(id)
                    return rec.visible and true or false
                end,
                __newindex = function(_, id, v)
                    local rec = findOrCreate(id)
                    rec.visible = v and true or false
                end,
            })

            local labels = {
                qui_options = "QUI options (/qui)",
                qui_layout  = "Layout Mode",
                qui_keybind = "Keybind mode",
                qui_cdm     = "Cooldown Manager",
                social      = "Friends list",
                guild       = "Guild frame",
                reload      = "Reload UI",
            }
            for _, id in ipairs(BB.GetBuiltinOrder()) do
                sy = P(GUI:CreateFormCheckbox(body, "    " .. (labels[id] or id), id, builtinProxy, Refresh,
                    { description = "Show the '" .. (labels[id] or id) .. "' button on this chat frame's button bar." }), body, sy)
            end

            -- Custom slash-command buttons editor. Each row binds three form
            -- edit boxes to one customButton record { label, slashCommand,
            -- icon }. The runtime in button_bar.lua iterates customButtons
            -- in order, creating an icon-textured button when `icon` is set
            -- and a text button otherwise. Add/Remove trigger structural
            -- rebuilds so the row count stays in sync with the data.
            local customHeader = GUI:CreateLabel(body, "    Custom slash-command buttons", 10, {0.5, 0.5, 0.5, 1})
            customHeader:SetPoint("TOPLEFT", 0, sy - 4)
            customHeader:SetPoint("RIGHT", body, "RIGHT", 0, 0)
            customHeader:SetJustifyH("LEFT")
            sy = sy - 18

            for idx = 1, #entry.customButtons do
                local cb = entry.customButtons[idx]
                if type(cb) ~= "table" then
                    cb = { label = "", slashCommand = "", icon = "" }
                    entry.customButtons[idx] = cb
                end
                if cb.icon == nil then cb.icon = "" end

                local rowLabel = GUI:CreateLabel(body, "    Button " .. idx, 10, {0.7, 0.85, 0.7, 1})
                rowLabel:SetPoint("TOPLEFT", 0, sy)
                rowLabel:SetPoint("RIGHT", body, "RIGHT", 0, 0)
                rowLabel:SetJustifyH("LEFT")
                sy = sy - 16

                sy = P(GUI:CreateFormEditBox(body, "Label", "label", cb, Refresh,
                    { description = "Text shown on the button when no icon is set." }), body, sy)
                sy = P(GUI:CreateFormEditBox(body, "Slash command", "slashCommand", cb, Refresh,
                    { description = "Slash command to run on click — e.g. /target Boss, /readycheck. Must include the leading slash." }), body, sy)
                sy = P(GUI:CreateFormEditBox(body, "Icon path (optional)", "icon", cb, Refresh,
                    { description = "Texture path for an icon-style button — e.g. Interface/Icons/Spell_Holy_HolyBolt or any registered AddOn texture path. Leave blank to render as a text button." }), body, sy)

                local removeRow = CreateFrame("Frame", nil, body)
                removeRow:SetPoint("TOPLEFT", 0, sy - 2)
                removeRow:SetPoint("RIGHT", body, "RIGHT", 0, 0)
                removeRow:SetHeight(FORM_ROW)
                local removeBtn
                removeBtn = GUI:CreateButton(removeRow, "Remove", 100, 22, function()
                    table.remove(entry.customButtons, idx)
                    Refresh()
                    NotifyProviderFor(removeBtn, { structural = true })
                end)
                removeBtn:SetPoint("TOPLEFT", 16, 0)
                sy = sy - (FORM_ROW + 4)
            end

            -- Add button row.
            local addRow = CreateFrame("Frame", nil, body)
            addRow:SetPoint("TOPLEFT", 0, sy - 4)
            addRow:SetPoint("RIGHT", body, "RIGHT", 0, 0)
            addRow:SetHeight(FORM_ROW)
            local addBtn
            addBtn = GUI:CreateButton(addRow, "Add custom button", 200, 24, function()
                entry.customButtons[#entry.customButtons + 1] = { label = "", slashCommand = "", icon = "" }
                Refresh()
                NotifyProviderFor(addBtn, { structural = true })
            end)
            addBtn:SetPoint("TOPLEFT", 0, 0)
        end

        -- Multi-frame button bar editor. Frame-selector dropdown writes to
        -- selectedButtonBarFrame and triggers structural rebuild — same
        -- pattern as the Tab Filters tile. Tile height is computed upfront
        -- from the current custom-button count so dynamic content fits;
        -- structural rebuilds (add/remove buttons, frame switch) re-enter
        -- this block and recompute.
        do
            local frameOptions = buildFrameOptions()
            local validSelection = false
            for _, opt in ipairs(frameOptions) do
                if opt.value == selectedButtonBarFrame then validSelection = true; break end
            end
            if not validSelection then selectedButtonBarFrame = frameOptions[1].value end

            local existingEntry = chat.buttonBars and chat.buttonBars[selectedButtonBarFrame]
            local customCount = (existingEntry and type(existingEntry.customButtons) == "table") and #existingEntry.customButtons or 0
            local btnTileHeight = (16 + 5 * customCount) * FORM_ROW + 24

            CreateChatSection("buttonBar", "Button Bar", btnTileHeight, function(body)
                local selectorTable = { _selected = selectedButtonBarFrame }
                local frameLabel = "ChatFrame" .. selectedButtonBarFrame
                for _, opt in ipairs(frameOptions) do
                    if opt.value == selectedButtonBarFrame then frameLabel = opt.text; break end
                end

                local sy = -4
                local frameSelector
                frameSelector = GUI:CreateFormDropdown(body, "Editing frame", frameOptions, "_selected", selectorTable, function()
                    local newValue = selectorTable._selected or 1
                    if newValue == selectedButtonBarFrame then return end
                    selectedButtonBarFrame = newValue
                    NotifyProviderFor(frameSelector, { structural = true })
                end, { description = "Pick which chat frame's button bar to edit. Each frame stores its own bar config in db.profile.chat.buttonBars[<frameID>]." })
                sy = P(frameSelector, body, sy)

                buildButtonBarBody(body, selectedButtonBarFrame, frameLabel, sy)
            end, sections, relayout)
        end
        end

        -- Timestamps
        CreateChatSection("timestamps", "Timestamps", 4 * FORM_ROW + 8, function(body)
            local sy = -4
            if not chat.timestamps then chat.timestamps = {enabled = false, format = "24h", color = {0.6, 0.6, 0.6}} end
            sy = P(GUI:CreateFormCheckbox(body, "Show Timestamps", "enabled", chat.timestamps, Refresh, { description = "Use QUI's colored timestamp prefix on new chat messages. While enabled, Blizzard's native chat timestamp is suppressed so the two do not stack." }), body, sy)
            local info = GUI:CreateLabel(body, "Only new messages are stamped. QUI replaces Blizzard timestamps while enabled.", 10, {0.5, 0.5, 0.5, 1})
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

        -- Message Modifiers (Phase A)
        CreateChatSection("messageModifiers", "Message Modifiers", 4 * FORM_ROW + 8, function(body)
            local sy = -4
            if not chat.modifiers then chat.modifiers = {} end
            if not chat.modifiers.classColors then
                chat.modifiers.classColors = { enabled = true, recolorBodyText = false }
            end
            if not chat.modifiers.channelShorten then
                chat.modifiers.channelShorten = { enabled = true, preset = "letter" }
            end
            local classColors = chat.modifiers.classColors
            local channelShorten = chat.modifiers.channelShorten

            sy = P(GUI:CreateFormCheckbox(body, "Class colors on player names", "enabled", classColors, Refresh, { description = "Color player names in chat by their class color (e.g. Mage names appear in light blue, Druid names in orange)." }), body, sy)
            sy = P(GUI:CreateFormCheckbox(body, "    Recolor names mentioned in body text", "recolorBodyText", classColors, Refresh, { description = "Performs an extra regex pass on every chat message to recolor known player names anywhere in the body. Slightly more expensive than the default name-only coloring." }), body, sy)

            sy = P(GUI:CreateFormCheckbox(body, "Shorten channel labels", "enabled", channelShorten, Refresh, { description = "Replace verbose channel tags like [Guild] with compact labels like [G] in chat output." }), body, sy)
            local presetOptions = {
                {value = "letter", text = "Letter \226\128\148 [G], [O], [P]"},
                {value = "number", text = "Number \226\128\148 same as Letter; numbered channels deferred"},
            }
            P(GUI:CreateFormDropdown(body, "Preset", presetOptions, "preset", channelShorten, Refresh, { description = "Channel label preset. Letter uses [G]/[O]/[P]/[R]/[I] etc. Number is currently identical to Letter for the 11 covered Blizzard chat events; numbered custom channels (CHAT_MSG_CHANNEL) are out of scope for Phase A." }), body, sy)
        end, sections, relayout)

        -- Keyword Alert (Phase A.1)
        CreateChatSection("keywordAlert", "Keyword Alert", 9 * FORM_ROW + 8, function(body)
            local sy = -4
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

            sy = P(GUI:CreateFormCheckbox(body, "Enable keyword alerts", "enabled", ka, Refresh, { description = "Highlight chat messages containing your configured keywords or character/guild name. Optionally play a sound and flash the chat tab when a match is found." }), body, sy)
            sy = P(GUI:CreateFormCheckbox(body, "    Trigger on my character name", "includeOwnName", ka, Refresh, { description = "Always treat your own character name as a keyword. Recommended on so you're alerted when someone @-mentions you." }), body, sy)
            sy = P(GUI:CreateFormCheckbox(body, "    Trigger on my first name", "includeFirstName", ka, Refresh, { description = "When your character name contains a space (e.g., 'Foo Bar'), trigger on the first part. Most player names don't have spaces." }), body, sy)
            sy = P(GUI:CreateFormCheckbox(body, "    Trigger on my guild name", "includeGuildName", ka, Refresh, { description = "Trigger an alert when your guild name appears in chat. Only fires when you are in a guild." }), body, sy)
            sy = P(GUI:CreateFormCheckbox(body, "    Skip my own messages", "skipSelf", ka, Refresh, { description = "Don't trigger alerts for messages you send yourself. Recommended on." }), body, sy)
            sy = P(GUI:CreateFormCheckbox(body, "    Flash chat tab on alert", "flashTab", ka, Refresh, { description = "Briefly flash the chat tab in addition to highlighting the matched text." }), body, sy)

            sy = P(GUI:CreateFormColorPicker(body, "Highlight Color", "highlightColor", ka, Refresh, nil, { description = "Color used to wrap matched keywords in chat output." }), body, sy)

            -- Sound dropdown via LSM if available, else a text input fallback.
            -- Architectural note: when LSM is loaded the sound list is the same
            -- one used by Timestamps / New Message Sound (U.GetSoundList());
            -- when not loaded we surface a text input so users can still paste
            -- a literal "Sound\\Interface\\Foo.ogg" path.
            local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
            if LSM and U.GetSoundList then
                local soundList = U.GetSoundList()
                sy = P(GUI:CreateFormDropdown(body, "Alert Sound", soundList, "soundFile", ka, Refresh, { description = "Sound played when a keyword match is detected. List sourced from LibSharedMedia." }), body, sy)
            else
                sy = P(GUI:CreateFormEditBox(body, "Alert Sound", "soundFile", ka, Refresh, {
                    maxLetters = 260, live = false,
                    onEditFocusGained = function(self) self:HighlightText() end,
                }, { description = "Path to the sound file to play on alert. Example: Sound\\Interface\\RaidWarning.ogg" }), body, sy)
            end

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
            local keywordsProxy = setmetatable({}, {
                __index = function(_, k)
                    if k == "keywordsText" then return joinKeywords(ka.keywords) end
                    return nil
                end,
                __newindex = function(_, k, v)
                    if k == "keywordsText" and type(v) == "string" then
                        ka.keywords = splitKeywords(v)
                    end
                end,
            })

            local keywordsField = GUI:CreateFormEditBox(body, "Custom Keywords", "keywordsText", keywordsProxy, Refresh, {
                maxLetters = 500, live = false,
                onEditFocusGained = function(self) self:HighlightText() end,
            }, { description = "Comma-separated list of additional keywords to highlight. Example: 'flask, food, summon'. Case-insensitive. Keywords containing commas are not supported by this input." })
            keywordsField:SetPoint("TOPLEFT", 0, sy)
            keywordsField:SetPoint("RIGHT", body, "RIGHT", 0, 0)
            sy = sy - FORM_ROW

            local helpLabel = GUI:CreateLabel(body, "Comma-separated. Case-insensitive substring match. Always-on triggers above are added on top of this list.", 10, {0.5, 0.5, 0.5, 1})
            helpLabel:SetPoint("TOPLEFT", 0, sy + 4)
            helpLabel:SetPoint("RIGHT", body, "RIGHT", 0, 0)
            helpLabel:SetJustifyH("LEFT")
        end, sections, relayout)

        -- Redundant Text Cleanup (Phase A.2)
        CreateChatSection("redundantTextCleanup", "Redundant Text Cleanup", 7 * FORM_ROW + 8, function(body)
            local sy = -4
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

            sy = P(GUI:CreateFormCheckbox(body, "Enable cleanup", "enabled", rt, Refresh, { description = "Compresses verbose loot/XP/honor/reputation/currency messages into short forms." }), body, sy)
            sy = P(GUI:CreateFormCheckbox(body, "    Loot collapse", "loot", rtp, Refresh, { description = "'You receive item: X' \226\134\146 '\226\156\147 X'" }), body, sy)
            sy = P(GUI:CreateFormCheckbox(body, "    Currency collapse", "currency", rtp, Refresh, { description = "Collapses currency-receive messages into a compact arrow form." }), body, sy)
            sy = P(GUI:CreateFormCheckbox(body, "    XP collapse", "xp", rtp, Refresh, { description = "Collapses experience-gain messages to '+N XP'." }), body, sy)
            sy = P(GUI:CreateFormCheckbox(body, "    Honor collapse", "honor", rtp, Refresh, { description = "Collapses honor-gain messages to '+N Honor'." }), body, sy)
            P(GUI:CreateFormCheckbox(body, "    Reputation collapse", "reputation", rtp, Refresh, { description = "Collapses reputation-change messages to a compact up/down arrow form." }), body, sy)
        end, sections, relayout)

        -- Persistent Message History (Phase B)
        -- The "Advanced: per-channel retention" disclosure described in the plan
        -- is implemented inline as a labelled section inside the main tile body
        -- rather than as a nested CreateTileCollapsible. CreateCollapsible doesn't
        -- expose a nested-tile primitive, and the inline form keeps every control
        -- visible and reachable without extra clicks. Per-channel override toggles
        -- and sliders sit at the bottom of the tile, after a divider label.
        CreateChatSection("persistentMessageHistory", "Persistent Message History", 16 * FORM_ROW + 8, function(body)
            local sy = -4
            if not chat.history then
                chat.history = {
                    enabled = true,
                    retentionDays = 7,
                    storeWhispers = false,
                    showSeparators = true,
                    perChannelRetention = {},
                }
            end
            local hist = chat.history
            if type(hist.perChannelRetention) ~= "table" then
                hist.perChannelRetention = {}
            end

            sy = P(GUI:CreateFormCheckbox(body, "Persist chat history across /reload", "enabled", hist, Refresh, { description = "Save displayed chat messages to your character's saved variables and replay them on next login or reload. Captured per character; cleared by 'Clear history now'." }), body, sy)
            sy = P(GUI:CreateFormSlider(body, "Retention (days)", 1, 30, 1, "retentionDays", hist, Refresh, nil, { description = "Default age limit for stored messages. Older entries are pruned at login. Per-channel overrides below take precedence when set." }), body, sy)
            sy = P(GUI:CreateFormCheckbox(body, "Store whispers", "storeWhispers", hist, Refresh, { description = "Include whispers in the persistent history. Default OFF: Blizzard's built-in HistoryKeeper already restores recent whispers, so enabling this can produce duplicate restored whispers." }), body, sy)
            sy = P(GUI:CreateFormCheckbox(body, "Show session separators", "showSeparators", hist, Refresh, { description = "Insert '──── Previous session ────' and '──── Resumed ────' markers around the restored block on login." }), body, sy)

            -- Clear-now button with confirmation popup.
            local clearRow = CreateFrame("Frame", nil, body)
            clearRow:SetPoint("TOPLEFT", 0, sy)
            clearRow:SetPoint("RIGHT", body, "RIGHT", 0, 0)
            clearRow:SetHeight(FORM_ROW)

            local clearBtn = GUI:CreateButton(clearRow, "Clear history now", 180, 24, function()
                StaticPopupDialogs["QUI_CHAT_HISTORY_CLEAR"] = {
                    text = "Clear all persisted chat history for this character? This cannot be undone.",
                    button1 = "Clear",
                    button2 = "Cancel",
                    OnAccept = function()
                        if ns.QUI and ns.QUI.Chat and ns.QUI.Chat.History and ns.QUI.Chat.History.Clear then
                            ns.QUI.Chat.History.Clear()
                            if DEFAULT_CHAT_FRAME then
                                DEFAULT_CHAT_FRAME:AddMessage("|cff34D399[QUI]|r Chat history cleared.", 1, 1, 1)
                            end
                        end
                    end,
                    timeout = 0,
                    whileDead = true,
                    hideOnEscape = true,
                    preferredIndex = 3,
                }
                StaticPopup_Show("QUI_CHAT_HISTORY_CLEAR")
            end)
            clearBtn:SetPoint("TOPLEFT", 0, 0)

            local clearHelp = GUI:CreateLabel(clearRow, "Erases this character's persisted entries. Does not change settings.", 10, {0.5, 0.5, 0.5, 1})
            clearHelp:SetPoint("LEFT", clearBtn, "RIGHT", 12, 0)
            clearHelp:SetPoint("RIGHT", clearRow, "RIGHT", 0, 0)
            clearHelp:SetJustifyH("LEFT")
            sy = sy - FORM_ROW - 4

            -- Advanced: per-channel retention overrides.
            -- Each chat-type group below gets its own toggle + slider row. When
            -- the toggle is on, the override-days value is written into
            -- hist.perChannelRetention[<key>]; when off, the entry is removed
            -- (nil = use default). Slider stays visible always for simplicity.
            local advancedHeader = GUI:CreateLabel(body, "Advanced: per-channel retention overrides", 11, {0.7, 0.85, 0.7, 1})
            advancedHeader:SetPoint("TOPLEFT", 0, sy - 4)
            advancedHeader:SetPoint("RIGHT", body, "RIGHT", 0, 0)
            advancedHeader:SetJustifyH("LEFT")
            sy = sy - 18

            local advancedHelp = GUI:CreateLabel(body, "Override the default retention for individual chat types. Off = use default.", 10, {0.5, 0.5, 0.5, 1})
            advancedHelp:SetPoint("TOPLEFT", 0, sy)
            advancedHelp:SetPoint("RIGHT", body, "RIGHT", 0, 0)
            advancedHelp:SetJustifyH("LEFT")
            sy = sy - 16

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
            local function makeGroupProxy(key)
                return setmetatable({}, {
                    __index = function(_, k)
                        if k == "enabled" then
                            return hist.perChannelRetention[key] ~= nil
                        elseif k == "days" then
                            return hist.perChannelRetention[key] or hist.retentionDays or 7
                        end
                        return nil
                    end,
                    __newindex = function(_, k, v)
                        if k == "enabled" then
                            if v then
                                if hist.perChannelRetention[key] == nil then
                                    hist.perChannelRetention[key] = hist.retentionDays or 7
                                end
                            else
                                hist.perChannelRetention[key] = nil
                            end
                        elseif k == "days" then
                            if type(v) == "number" and hist.perChannelRetention[key] ~= nil then
                                hist.perChannelRetention[key] = v
                            end
                        end
                    end,
                })
            end

            for _, group in ipairs(CHANNEL_GROUPS) do
                local proxy = makeGroupProxy(group.key)
                sy = P(GUI:CreateFormCheckbox(body, "    Override " .. group.label, "enabled", proxy, Refresh, { description = "When on, " .. group.label .. " messages use the days slider on the right instead of the default retention. When off, the default applies." }), body, sy)
                sy = P(GUI:CreateFormSlider(body, "        " .. group.label .. " days", 1, 30, 1, "days", proxy, Refresh, nil, { description = "Retention in days for " .. group.label .. " messages when the override toggle above is on. Ignored otherwise." }), body, sy)
            end

            -- Reset all overrides button.
            local resetRow = CreateFrame("Frame", nil, body)
            resetRow:SetPoint("TOPLEFT", 0, sy - 4)
            resetRow:SetPoint("RIGHT", body, "RIGHT", 0, 0)
            resetRow:SetHeight(FORM_ROW)

            local resetBtn = GUI:CreateButton(resetRow, "Reset all overrides", 180, 24, function()
                wipe(hist.perChannelRetention)
                NotifyProviderFor(resetBtn, { structural = true })
                Refresh()
            end)
            resetBtn:SetPoint("TOPLEFT", 0, 0)

            local resetHelp = GUI:CreateLabel(resetRow, "Clears every per-channel override above. Default retention applies to all channels.", 10, {0.5, 0.5, 0.5, 1})
            resetHelp:SetPoint("LEFT", resetBtn, "RIGHT", 12, 0)
            resetHelp:SetPoint("RIGHT", resetRow, "RIGHT", 0, 0)
            resetHelp:SetJustifyH("LEFT")
        end, sections, relayout)

        -- UI Cleanup
        CreateChatSection("uiCleanup", "UI Cleanup", 2 * FORM_ROW + 8, function(body)
            local sy = -4
            sy = P(GUI:CreateFormCheckbox(body, "Hide Chat Buttons", "hideButtons", chat, Refresh, { description = "Hide the social and channel buttons on each chat frame. The scrollbar stays visible." }), body, sy)
            local info = GUI:CreateLabel(body, "Hides social and channel buttons. The scrollbar stays visible.", 10, {0.5, 0.5, 0.5, 1})
            info:SetPoint("TOPLEFT", 0, sy)
            info:SetPoint("RIGHT", body, "RIGHT", 0, 0)
            info:SetJustifyH("LEFT")
        end, sections, relayout)

        -- Copy Button
        CreateChatSection("copyButton", "Copy Button", 4 * FORM_ROW + 8, function(body)
            local sy = -4
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
            sy = P(GUI:CreateFormDropdown(body, "Copy Button", copyButtonOptions, "copyButtonMode", chat, Refresh, { description = "Controls whether the copy glyph stays faintly visible, hides when idle, or is disabled." }), body, sy)
            sy = P(GUI:CreateFormDropdown(body, "Copy Source", copySourceOptions, "copyHistorySource", chat, Refresh, { description = "Choose whether the copy popup reads the current live scrollback or the persisted history buffer. Persisted history must be enabled above." }), body, sy)
            sy = P(GUI:CreateFormDropdown(body, "Scrollback Lines", scrollbackOptions, "scrollbackLines", chat, Refresh, { description = "Sets the live chat frame scrollback cap. Changing this can clear the current visible buffer once per frame." }), body, sy)
            local info = GUI:CreateLabel(body, "The copy popup uses live scrollback by default. Persisted source is useful when you need older saved lines.", 10, {0.5, 0.5, 0.5, 1})
            info:SetPoint("TOPLEFT", 0, sy)
            info:SetPoint("RIGHT", body, "RIGHT", 0, 0)
            info:SetJustifyH("LEFT")
        end, sections, relayout)

        -- Message History
        CreateChatSection("messageHistory", "Message History", 2 * FORM_ROW + 8, function(body)
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
        CreateChatSection("newMessageSound", "New Message Sound", 1, function(body)
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
                soundEntriesContainer._quiDualColumnRowHeight = math.max(FORM_ROW, rowY)

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
