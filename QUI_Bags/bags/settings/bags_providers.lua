--[[
    QUI Bags Shared Settings Provider
    Owns provider-backed settings content for the Bags surface in the shared
    settings layer (minimap_providers precedent: V3 body pattern —
    CreateAccentDotLabel + CreateSettingsCardGroup + BuildSettingRow).

    API notes (vendored docs):
      • C_CurrencyInfo.GetCurrencyInfo(type) → CurrencyInfo { name, ... },
        MayReturnNothing (CurrencyInfoDocumentation.lua:249) — nil return is
        the "unknown currency ID" signal for the add-by-ID validation.
      • C_Item.GetItemInfo(itemInfo) → itemName first return,
        MayReturnNothing (ItemDocumentation.lua:589) — uncached items fall
        back to a numeric label.
]]

local _, ns = ...

local Settings = ns.Settings
local ProviderPanels = Settings and Settings.ProviderPanels
if not ProviderPanels or type(ProviderPanels.RegisterAfterLoad) ~= "function" then
    return
end

-- NOTE: do NOT capture `ns.QUI_Options` as a local in this outer closure.
-- QUI_Options/shared.lua REPLACES the stub table installed by
-- core/gui_shell.lua, so any captured local would be stale. Re-resolve
-- ns.QUI_Options at call time inside MakeLayout / row / build bodies
-- (minimap_providers precedent).
ProviderPanels:RegisterAfterLoad(function(ctx)
    local GUI = ctx.GUI
    local U = ctx.U
    local PAD = (ns.QUI_Options and ns.QUI_Options.PADDING) or 15
    local HEADER_GAP = 26
    local SECTION_GAP = 14

    local function RegisterSharedOnly(key, provider)
        ctx.RegisterShared(key, provider)
    end

    local function MakeLayout(content)
        if U._layoutModePositionOnly then
            return U.MakeSuppressedProviderLayout(content)
        end
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

        return L
    end

    local function row(parent, label, widget, desc)
        return ns.QUI_Options.BuildSettingRow(parent, label, widget, desc)
    end

    -- Muted inline note (minimap's drawer empty-state idiom, word-wrapped).
    local function PlaceNote(L, content, text, height)
        local holder = CreateFrame("Frame", nil, content)
        local lbl = holder:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        lbl:SetPoint("TOPLEFT", holder, "TOPLEFT", 6, -4)
        lbl:SetPoint("RIGHT", holder, "RIGHT", -6, 0)
        lbl:SetJustifyH("LEFT")
        lbl:SetWordWrap(true)
        lbl:SetTextColor(0.6, 0.6, 0.6, 1)
        lbl:SetText(text)
        L.placeCustom(holder, height or 30)
    end

    ---------------------------------------------------------------------------
    -- Label helpers. Both APIs MayReturnNothing; both are nil-guarded so the
    -- headless search-cache harness (no C_* namespaces) renders fallbacks.
    ---------------------------------------------------------------------------
    local function CurrencyLabel(id)
        local info = C_CurrencyInfo and C_CurrencyInfo.GetCurrencyInfo
            and C_CurrencyInfo.GetCurrencyInfo(id)
        local name = info and info.name
        if name and name ~= "" then
            return string.format("%s (%d)", name, id)
        end
        return "Currency " .. tostring(id)
    end

    local function ItemLabel(itemID)
        local name = C_Item and C_Item.GetItemInfo and C_Item.GetItemInfo(itemID)
        if name and name ~= "" then
            return string.format("%s (%d)", name, itemID)
        end
        return "Item " .. tostring(itemID)
    end

    ---------------------------------------------------------------------------
    -- Dropdown option builders (sorted for deterministic order; the DBs are
    -- unordered maps). Store access is build-time-guarded: ns.Bags.Store is
    -- absent in the headless harness, and reads are re-resolved per call so
    -- delete refreshes see live data.
    ---------------------------------------------------------------------------
    local function BuildExclusionOptions(junk)
        local ids = {}
        for id in pairs((junk and junk.exclusions) or {}) do ids[#ids + 1] = id end
        table.sort(ids)
        local opts = {}
        for _, id in ipairs(ids) do
            opts[#opts + 1] = { value = id, text = ItemLabel(id) }
        end
        return opts
    end

    local function BuildCurrencyOptions(cfg)
        local ids = {}
        for id in pairs((cfg and cfg.currencies) or {}) do ids[#ids + 1] = id end
        table.sort(ids)
        local opts = {}
        for _, id in ipairs(ids) do
            opts[#opts + 1] = { value = id, text = CurrencyLabel(id) }
        end
        return opts
    end

    local function BuildCharacterOptions()
        local Store = ns.Bags and ns.Bags.Store
        local opts = {}
        if Store and Store.ListCharacters then
            local current = Store.GetCurrentCharacterKey and Store.GetCurrentCharacterKey()
            for _, key in ipairs(Store.ListCharacters()) do
                if key ~= current then
                    opts[#opts + 1] = { value = key, text = key }
                end
            end
        end
        return opts
    end

    local function BuildGuildOptions()
        local Store = ns.Bags and ns.Bags.Store
        local opts = {}
        if Store and Store.ListGuilds then
            for _, key in ipairs(Store.ListGuilds()) do
                opts[#opts + 1] = { value = key, text = key }
            end
        end
        return opts
    end

    ---------------------------------------------------------------------------
    -- BAGS PROVIDER
    ---------------------------------------------------------------------------
    RegisterSharedOnly("bags", { build = function(content, _key, _width)
        local db = U.GetProfileDB()
        if not db or not db.bags or not ns.QUI_Options then return 80 end
        local bags = db.bags
        if not bags.appearance then bags.appearance = {} end
        if not bags.behavior then bags.behavior = {} end
        local behavior = bags.behavior
        if not behavior.autoOpen then behavior.autoOpen = {} end
        if not behavior.junk then behavior.junk = {} end
        if not behavior.junk.exclusions then behavior.junk.exclusions = {} end
        if not behavior.newItemGlow then behavior.newItemGlow = {} end
        if not bags.currencyBar then bags.currencyBar = {} end
        if not bags.currencyBar.currencies then bags.currencyBar.currencies = {} end

        local function Refresh() if _G.QUI_RefreshBags then _G.QUI_RefreshBags() end end

        local L = MakeLayout(content)

        -- GENERAL: master enable toggle, parity with the Module Addons row
        -- (moduleAddon_QUI_Bags) — the OTHER surface that flips this module.
        -- Both move the addon enable-state AND the bags.enabled dormant-guard
        -- flag together; reload is prompted exactly when that row prompts
        -- (always on disable; on enable when the addon needs a reload or the
        -- guard flag was explicitly false).
        local function ShowBagsReloadPrompt()
            local Q = _G.QUI
            local G2 = Q and Q.GUI
            if G2 and type(G2.ShowConfirmation) == "function" then
                G2:ShowConfirmation({
                    title      = "Reload UI?",
                    message    = "This change takes full effect after a reload.",
                    acceptText = "Reload",
                    cancelText = "Later",
                    onAccept   = function() if Q and Q.SafeReload then Q:SafeReload() end end,
                })
            end
        end
        local function ModuleIsOn()
            local loader = ns.AddonLoader
            local addonOn = loader and loader.IsModuleAddonEnabled
                and loader.IsModuleAddonEnabled("QUI_Bags")
            return (addonOn and bags.enabled) and true or false
        end
        local function ApplyModuleEnabled(val)
            local flipped = val and (bags.enabled == false)
            bags.enabled = val and true or false
            local result
            if ns.AddonLoader and ns.AddonLoader.SetModuleAddonEnabled then
                result = ns.AddonLoader.SetModuleAddonEnabled("QUI_Bags", val and true or false)
            end
            if ns.QUI_Modules then
                ns.QUI_Modules:NotifyChanged("moduleAddon_QUI_Bags")
            end
            Refresh()
            if (not val) or result == "reload" or (flipped and result == "loaded") then
                ShowBagsReloadPrompt()
            end
        end
        -- Proxy "db" for the checkbox: reads compute the combined module
        -- state; writes apply it. The widget writes the current value back
        -- at creation (SetValue(GetValue())), so unchanged writes must be
        -- no-ops or page build would re-run the enable path.
        local moduleProxy = setmetatable({}, {
            __index = function(_, k)
                if k == "enabled" then return ModuleIsOn() end
            end,
            __newindex = function(_, k, v)
                if k == "enabled" and ((v and true or false) ~= ModuleIsOn()) then
                    ApplyModuleEnabled(v and true or false)
                end
            end,
        })

        L.headerAt("General")
        local g0 = L.sectionAt()
        local moduleW = GUI:CreateFormCheckbox(g0.frame, nil, "enabled", moduleProxy, nil,
            { description = "QUI's bag takeover. Mirrors the Bags row on the Module Addons page: enabling loads the module (live when possible), disabling hands bags back to Blizzard — a UI reload is prompted for a clean handoff. Everything below applies live while the module is enabled." })
        g0.AddRow(row(g0.frame, "Enable Bags Module", moduleW))
        L.closeSection(g0)

        -- APPEARANCE
        L.headerAt("Appearance")
        local s1 = L.sectionAt()
        local iconSizeW = GUI:CreateFormSlider(s1.frame, nil, 24, 48, 1, "iconSize", bags.appearance, Refresh,
            { description = "Pixel size of each item button in the bag, bank, and guild bank windows." })
        local columnsW = GUI:CreateFormSlider(s1.frame, nil, 6, 20, 1, "columns", bags.appearance, Refresh,
            { description = "How many item columns the bag window grid uses." })
        s1.AddRow(row(s1.frame, "Icon Size", iconSizeW), row(s1.frame, "Columns", columnsW))

        local spacingW = GUI:CreateFormSlider(s1.frame, nil, 0, 8, 1, "spacing", bags.appearance, Refresh,
            { description = "Pixel gap between item buttons." })
        local setMarkW = GUI:CreateFormCheckbox(s1.frame, nil, "equipmentSetMark", bags.appearance, Refresh,
            { description = "Show a small gear icon on items that belong to a saved equipment set (live bag and bank views)." })
        s1.AddRow(row(s1.frame, "Item Spacing", spacingW), row(s1.frame, "Equipment Set Icon", setMarkW))

        local layoutModeW = GUI:CreateFormDropdown(s1.frame, nil, {
            { value = "flat", text = "Flat Grid" },
            { value = "categories", text = "Categories" },
        }, "layoutMode", bags.appearance, Refresh,
            { description = "Bag window layout. Flat Grid mirrors your real bag slots; Categories groups items under headers (Equipment, Consumables, Trade Goods, ... Junk last; new loot lands in Recent) and hides empty slots — the free count stays in the footer." })
        local reagentW = GUI:CreateFormDropdown(s1.frame, nil, {
            { value = "separate", text = "Separate Section" },
            { value = "merged", text = "Merged Into Grid" },
            { value = "hidden", text = "Hidden" },
        }, "reagentDisplay", bags.appearance, Refresh,
            { description = "Flat Grid only: show the reagent bag as its own labeled section below the regular bags, merge its slots into the grid, or hide it from the bag window entirely." })
        s1.AddRow(row(s1.frame, "Layout", layoutModeW), row(s1.frame, "Reagent Bag", reagentW))

        local bankColsW = GUI:CreateFormSlider(s1.frame, nil, 6, 24, 1, "bankColumns", bags.appearance, Refresh,
            { description = "How many item columns the bank window grid uses." })
        local guildColsW = GUI:CreateFormSlider(s1.frame, nil, 6, 24, 1, "guildColumns", bags.appearance, Refresh,
            { description = "How many item columns the guild bank grid uses." })
        s1.AddRow(row(s1.frame, "Bank Columns", bankColsW), row(s1.frame, "Guild Bank Columns", guildColsW))

        local groupEmptyW = GUI:CreateFormCheckbox(s1.frame, nil, "groupEmptySlots", bags.appearance, Refresh,
            { description = "Flat Grid only: collapse each section's empty slots into a single cell showing the free count." })
        local greyJunkW = GUI:CreateFormCheckbox(s1.frame, nil, "greyJunk", bags.appearance, Refresh,
            { description = "Desaturate junk (grey-quality) items." })
        s1.AddRow(row(s1.frame, "Group Empty Slots", groupEmptyW), row(s1.frame, "Grey Out Junk", greyJunkW))

        local markUnusableW = GUI:CreateFormCheckbox(s1.frame, nil, "markUnusable", bags.appearance, Refresh,
            { description = "Red-tint items your character cannot use (reads the item tooltip's red text)." })
        local setBorderW = GUI:CreateFormCheckbox(s1.frame, nil, "equipmentSetBorder", bags.appearance, Refresh,
            { description = "Use a cyan border instead of the quality color on items that belong to a saved equipment set (live views)." })
        s1.AddRow(row(s1.frame, "Mark Unusable Items", markUnusableW), row(s1.frame, "Equipment Set Border", setBorderW))

        local contextFadeW = GUI:CreateFormCheckbox(s1.frame, nil, "contextFading", bags.appearance, Refresh,
            { description = "Fade items that don't match the open context UI (socketing, scrapping, item upgrade)." })
        local bagSlotsW = GUI:CreateFormCheckbox(s1.frame, nil, "showBagSlots", bags.appearance, Refresh,
            { description = "Show the bag-slot strip at the top of the bag window: your four bag slots plus the reagent bag slot. Drag a container onto a slot (or click with one on the cursor) to equip or swap it; click an equipped bag to pick it up." })
        s1.AddRow(row(s1.frame, "Context Fading", contextFadeW), row(s1.frame, "Show Bag Slots", bagSlotsW))

        -- Per-bag hiding (bags 1–4): display-only, mirrors Alt+click on the
        -- bag-slot strip. Numeric keys into the hiddenBags scalar map.
        local hiddenBags = bags.appearance.hiddenBags
        local hide1W = GUI:CreateFormCheckbox(s1.frame, nil, 1, hiddenBags, Refresh,
            { description = "Hide bag 1's slots from the bag window grid. Display-only: search and sort still cover it." })
        local hide2W = GUI:CreateFormCheckbox(s1.frame, nil, 2, hiddenBags, Refresh,
            { description = "Hide bag 2's slots from the bag window grid. Display-only: search and sort still cover it." })
        s1.AddRow(row(s1.frame, "Hide Bag 1", hide1W), row(s1.frame, "Hide Bag 2", hide2W))
        local hide3W = GUI:CreateFormCheckbox(s1.frame, nil, 3, hiddenBags, Refresh,
            { description = "Hide bag 3's slots from the bag window grid. Display-only: search and sort still cover it." })
        local hide4W = GUI:CreateFormCheckbox(s1.frame, nil, 4, hiddenBags, Refresh,
            { description = "Hide bag 4's slots from the bag window grid. Display-only: search and sort still cover it." })
        s1.AddRow(row(s1.frame, "Hide Bag 3", hide3W), row(s1.frame, "Hide Bag 4", hide4W))
        L.closeSection(s1)

        -- CORNER WIDGETS (per-corner primary + fallback pick)
        L.headerAt("Icon Corners")
        local sc = L.sectionAt()
        local CORNER_OPTS = {
            { value = "none", text = "None" },
            { value = "quantity", text = "Quantity" },
            { value = "item_level", text = "Item Level" },
            { value = "junk", text = "Junk Coin" },
            { value = "equipment_set", text = "Equipment Set" },
            { value = "binding", text = "Binding (BoE/BoA)" },
            { value = "expansion", text = "Expansion" },
            { value = "crafting_quality", text = "Crafting Quality (R1-R5)" },
        }
        local function cornerDD(key, desc)
            return GUI:CreateFormDropdown(sc.frame, nil, CORNER_OPTS, key, bags.appearance.corners, Refresh,
                { description = desc })
        end
        sc.AddRow(row(sc.frame, "Top Left", cornerDD("tl1",
                "Primary widget for the top-left icon corner. The first widget that applies to an item renders.")),
            row(sc.frame, "Top Left Fallback", cornerDD("tl2",
                "Shown in the top-left corner when the primary widget doesn't apply to the item.")))
        sc.AddRow(row(sc.frame, "Top Right", cornerDD("tr1",
                "Primary widget for the top-right icon corner.")),
            row(sc.frame, "Top Right Fallback", cornerDD("tr2",
                "Shown in the top-right corner when the primary widget doesn't apply.")))
        sc.AddRow(row(sc.frame, "Bottom Left", cornerDD("bl1",
                "Primary widget for the bottom-left icon corner.")),
            row(sc.frame, "Bottom Left Fallback", cornerDD("bl2",
                "Shown in the bottom-left corner when the primary widget doesn't apply.")))
        sc.AddRow(row(sc.frame, "Bottom Right", cornerDD("br1",
                "Primary widget for the bottom-right icon corner.")),
            row(sc.frame, "Bottom Right Fallback", cornerDD("br2",
                "Shown in the bottom-right corner when the primary widget doesn't apply.")))

        local cornerFontW = GUI:CreateFormSlider(sc.frame, nil, 8, 16, 1, "cornerFontSize", bags.appearance, Refresh,
            { description = "Font size of corner text widgets (quantity, item level, binding, expansion)." })
        local qualityTextW = GUI:CreateFormCheckbox(sc.frame, nil, "qualityColorText", bags.appearance, Refresh,
            { description = "Color corner text (item level, binding) by the item's quality instead of white." })
        sc.AddRow(row(sc.frame, "Corner Font Size", cornerFontW), row(sc.frame, "Quality-Colored Text", qualityTextW))
        L.closeSection(sc)

        -- BEHAVIOR
        local sortOptions = {
            { value = "quality", text = "Quality" },
            { value = "type", text = "Type" },
            { value = "name", text = "Name" },
            { value = "ilvl", text = "Item Level" },
            { value = "expansion", text = "Expansion" },
        }
        local tooltipCountOptions = {
            { value = "on", text = "Always On" },
            { value = "off", text = "Off" },
            { value = "modifier", text = "While Shift Held" },
        }

        L.headerAt("Behavior")
        local s2 = L.sectionAt()
        local sortKeyW = GUI:CreateFormDropdown(s2.frame, nil, sortOptions, "sortKey", behavior, nil,
            { description = "Primary ordering the Sort button uses. Quality sorts best-first; the other keys fall back to quality within equal groups. Right-clicking a Sort button changes this too." })
        local sortRevW = GUI:CreateFormCheckbox(s2.frame, nil, "sortReverse", behavior, nil,
            { description = "Flip the chosen sort order wholesale (worst-first quality, Z-A names, lowest item level first, ...)." })
        s2.AddRow(row(s2.frame, "Sort Items By", sortKeyW), row(s2.frame, "Reverse Sort Order", sortRevW))

        local tooltipCountsW = GUI:CreateFormDropdown(s2.frame, nil, tooltipCountOptions, "tooltipCounts", behavior, nil,
            { description = "Show how many of an item you own across characters, bank, mail, and more on item tooltips. 'While Shift Held' shows the counts only while Shift is down." })
        local autoReagentsW = GUI:CreateFormCheckbox(s2.frame, nil, "autoDepositReagents", behavior, nil,
            { description = "Deposit all crafting reagents from your bags into the warband bank every time you open the bank." })
        s2.AddRow(row(s2.frame, "Tooltip Item Counts", tooltipCountsW), row(s2.frame, "Auto-Deposit Reagents", autoReagentsW))

        local glowEnableW = GUI:CreateFormCheckbox(s2.frame, nil, "enabled", behavior.newItemGlow, Refresh,
            { description = "Highlight recently looted items in the bag window until you mouse over them or the timeout passes." })
        local glowTimeoutW = GUI:CreateFormSlider(s2.frame, nil, 5, 120, 5, "timeoutMinutes", behavior.newItemGlow, nil,
            { description = "Minutes before a new-item highlight expires on its own." })
        s2.AddRow(row(s2.frame, "New Item Highlight", glowEnableW), row(s2.frame, "Highlight Timeout (min)", glowTimeoutW))
        L.closeSection(s2)

        -- AUTO-OPEN
        L.headerAt("Auto-Open")
        local s3 = L.sectionAt()
        local autoOpenRows = {
            { key = "merchant", label = "Merchant", desc = "Open the bag window when you talk to a merchant." },
            { key = "mail", label = "Mailbox", desc = "Open the bag window at a mailbox." },
            { key = "auctionHouse", label = "Auction House", desc = "Open the bag window at the auction house." },
            { key = "trade", label = "Trade", desc = "Open the bag window when a trade starts." },
            { key = "scrappingMachine", label = "Scrapping Machine", desc = "Open the bag window at a scrapping machine." },
            { key = "itemUpgrade", label = "Item Upgrade", desc = "Open the bag window at the item upgrade vendor." },
            { key = "socket", label = "Socketing", desc = "Open the bag window when socketing an item." },
            { key = "bank", label = "Bank", desc = "Open the bag window alongside the bank window." },
            { key = "guildBank", label = "Guild Bank", desc = "Open the bag window alongside the guild bank window." },
        }
        local pendingCell = nil
        for _, def in ipairs(autoOpenRows) do
            local w = GUI:CreateFormCheckbox(s3.frame, nil, def.key, behavior.autoOpen, nil,
                { description = def.desc })
            local cell = row(s3.frame, def.label, w)
            if pendingCell then
                s3.AddRow(pendingCell, cell)
                pendingCell = nil
            else
                pendingCell = cell
            end
        end
        if pendingCell then
            s3.AddRow(pendingCell)
        end
        L.closeSection(s3)

        -- JUNK
        L.headerAt("Junk")
        local s4 = L.sectionAt()
        local junkDimW = GUI:CreateFormCheckbox(s4.frame, nil, "dim", behavior.junk, Refresh,
            { description = "Desaturate junk (gray) items and overlay a coin icon in the bag window." })
        local sellButtonW = GUI:CreateFormCheckbox(s4.frame, nil, "sellButton", behavior.junk, Refresh,
            { description = "Show a Sell Junk button in the bag window while a merchant is open." })
        s4.AddRow(row(s4.frame, "Dim Junk Items", junkDimW), row(s4.frame, "Sell Junk Button", sellButtonW))

        local exclusionWrapper = { selected = "" }
        local exclusionDropdown
        exclusionDropdown = GUI:CreateFormDropdown(s4.frame, nil, BuildExclusionOptions(behavior.junk), "selected", exclusionWrapper, function(value)
            if not value or value == "" then return end
            behavior.junk.exclusions[value] = nil
            print("|cff60A5FAQUI:|r Removed junk exclusion: " .. ItemLabel(value))
            exclusionWrapper.selected = ""
            if exclusionDropdown.SetOptions then exclusionDropdown.SetOptions(BuildExclusionOptions(behavior.junk)) end
            if exclusionDropdown.SetValue then exclusionDropdown.SetValue("", true) end
            Refresh()
        end, { description = "Items excluded from junk dimming and the Sell Junk button. Selecting one removes the exclusion." })
        s4.AddRow(row(s4.frame, "Remove Exclusion", exclusionDropdown))

        -- Add-by-ID cell (the currency-bar idiom below): validate via
        -- GetItemInfoInstant (MayReturnNothing per ItemDocumentation — nil
        -- = no such item; instant, no async wait), write exclusions[id]=true.
        local exclAddInput = GUI:CreateFormEditBox(s4.frame, nil, nil, nil, nil, {
            commitOnEnter = false, commitOnFocusLost = false,
            onEscapePressed = function(self) self:ClearFocus() end,
        }, { description = "Numeric item ID to exclude from junk handling (find IDs on database sites or via item tooltips). Click Add to validate and append it." })
        local exclAddCell = row(s4.frame, "Add Exclusion by ID", exclAddInput)
        local exclAddBtn = GUI:CreateButton(exclAddCell, "Add", 70, 22, function()
            local text = exclAddInput.editBox and exclAddInput.editBox:GetText()
            local id = tonumber(text)
            if not id or id <= 0 or id % 1 ~= 0 then
                print("|cffff0000QUI:|r Enter a numeric item ID.")
                return
            end
            local valid = C_Item and C_Item.GetItemInfoInstant
                and C_Item.GetItemInfoInstant(id)
            if not valid then
                print("|cffff0000QUI:|r Unknown item ID: " .. id)
                return
            end
            behavior.junk.exclusions[id] = true
            if exclAddInput.editBox then exclAddInput.editBox:SetText("") end
            print("|cff60A5FAQUI:|r Added junk exclusion: " .. ItemLabel(id))
            if exclusionDropdown.SetOptions then exclusionDropdown.SetOptions(BuildExclusionOptions(behavior.junk)) end
            Refresh()
        end)
        exclAddBtn:SetPoint("RIGHT", exclAddCell, "RIGHT", 0, 0)
        exclAddInput:ClearAllPoints()
        exclAddInput:SetPoint("LEFT", exclAddCell, "LEFT", 84, 0)
        exclAddInput:SetPoint("RIGHT", exclAddBtn, "LEFT", -8, 0)

        L.closeSection(s4)
        PlaceNote(L, content,
            "Exclusions protect specific items from junk dimming and the Sell Junk button. Add by item ID above; remove via the dropdown.",
            26)

        -- CURRENCY BAR
        L.headerAt("Currency Bar")
        local s5 = L.sectionAt()
        local cbar = bags.currencyBar
        local cbarEnableW = GUI:CreateFormCheckbox(s5.frame, nil, "enabled", cbar, Refresh,
            { description = "Show a footer row on the bag window with the currencies listed below." })
        s5.AddRow(row(s5.frame, "Enable Currency Bar", cbarEnableW))

        local currencyWrapper = { selected = "" }
        local currencyDropdown
        currencyDropdown = GUI:CreateFormDropdown(s5.frame, nil, BuildCurrencyOptions(cbar), "selected", currencyWrapper, function(value)
            if not value or value == "" then return end
            cbar.currencies[value] = nil
            print("|cff60A5FAQUI:|r Removed currency: " .. CurrencyLabel(value))
            currencyWrapper.selected = ""
            if currencyDropdown.SetOptions then currencyDropdown.SetOptions(BuildCurrencyOptions(cbar)) end
            if currencyDropdown.SetValue then currencyDropdown.SetValue("", true) end
            Refresh()
        end, { description = "Currencies shown on the bar. Selecting one removes it." })

        -- Add-by-ID cell: BuildSettingRow supplies the label/pin/search
        -- capture; the bare editbox is re-anchored to make room for an inline
        -- Add button (profiles_content New Profile idiom).
        local addInput = GUI:CreateFormEditBox(s5.frame, nil, nil, nil, nil, {
            commitOnEnter = false, commitOnFocusLost = false,
            onEscapePressed = function(self) self:ClearFocus() end,
        }, { description = "Numeric currency ID to add to the bar (find IDs on database sites or the currency tab). Click Add to validate and append it." })
        local addCell = row(s5.frame, "Add Currency by ID", addInput)
        local addBtn = GUI:CreateButton(addCell, "Add", 70, 22, function()
            local text = addInput.editBox and addInput.editBox:GetText()
            local id = tonumber(text)
            if not id or id <= 0 or id % 1 ~= 0 then
                print("|cffff0000QUI:|r Enter a numeric currency ID.")
                return
            end
            local info = C_CurrencyInfo and C_CurrencyInfo.GetCurrencyInfo
                and C_CurrencyInfo.GetCurrencyInfo(id)
            if not info then
                print("|cffff0000QUI:|r Unknown currency ID: " .. id)
                return
            end
            cbar.currencies[id] = true
            if addInput.editBox then addInput.editBox:SetText("") end
            print("|cff60A5FAQUI:|r Added currency: " .. CurrencyLabel(id))
            if currencyDropdown.SetOptions then currencyDropdown.SetOptions(BuildCurrencyOptions(cbar)) end
            Refresh()
        end)
        addBtn:SetPoint("RIGHT", addCell, "RIGHT", 0, 0)
        addInput:ClearAllPoints()
        addInput:SetPoint("LEFT", addCell, "LEFT", 84, 0)
        addInput:SetPoint("RIGHT", addBtn, "LEFT", -8, 0)

        s5.AddRow(addCell, row(s5.frame, "Remove Currency", currencyDropdown))
        L.closeSection(s5)

        -- CACHED DATA
        L.headerAt("Cached Data")
        local s6 = L.sectionAt()
        local charWrapper = { selected = "" }
        local charDropdown
        charDropdown = GUI:CreateFormDropdown(s6.frame, nil, BuildCharacterOptions(), "selected", charWrapper, function(value)
            if not value or value == "" then return end
            GUI:ShowConfirmation({
                title = "Delete Cached Character?",
                message = string.format("Delete the cached inventory data for '%s'?", value),
                warningText = "This cannot be undone. The cache rebuilds the next time that character logs in.",
                acceptText = "Delete", cancelText = "Cancel", isDestructive = true,
                onAccept = function()
                    local Store = ns.Bags and ns.Bags.Store
                    if Store and Store.DeleteCharacter then
                        Store.DeleteCharacter(value)
                        print("|cff60A5FAQUI:|r Deleted cached character: " .. value)
                    end
                    charWrapper.selected = ""
                    if charDropdown.SetOptions then charDropdown.SetOptions(BuildCharacterOptions()) end
                    if charDropdown.SetValue then charDropdown.SetValue("", true) end
                end,
                onCancel = function()
                    charWrapper.selected = ""
                    if charDropdown.SetValue then charDropdown.SetValue("", true) end
                end,
            })
        end, { description = "Delete a character's cached bags, bank, equipment, mail, and currency data. The current character can't be deleted." })

        local guildWrapper = { selected = "" }
        local guildDropdown
        guildDropdown = GUI:CreateFormDropdown(s6.frame, nil, BuildGuildOptions(), "selected", guildWrapper, function(value)
            if not value or value == "" then return end
            GUI:ShowConfirmation({
                title = "Delete Cached Guild?",
                message = string.format("Delete the cached guild bank data for '%s'?", value),
                warningText = "This cannot be undone. The cache rebuilds on the next guild bank visit.",
                acceptText = "Delete", cancelText = "Cancel", isDestructive = true,
                onAccept = function()
                    local Store = ns.Bags and ns.Bags.Store
                    if Store and Store.DeleteGuild then
                        Store.DeleteGuild(value)
                        print("|cff60A5FAQUI:|r Deleted cached guild: " .. value)
                    end
                    guildWrapper.selected = ""
                    if guildDropdown.SetOptions then guildDropdown.SetOptions(BuildGuildOptions()) end
                    if guildDropdown.SetValue then guildDropdown.SetValue("", true) end
                end,
                onCancel = function()
                    guildWrapper.selected = ""
                    if guildDropdown.SetValue then guildDropdown.SetValue("", true) end
                end,
            })
        end, { description = "Delete a guild's cached guild bank data." })
        s6.AddRow(row(s6.frame, "Delete Character Cache", charDropdown), row(s6.frame, "Delete Guild Cache", guildDropdown))
        L.closeSection(s6)

        L.relayoutSections()
        return content:GetHeight()
    end })
end)
