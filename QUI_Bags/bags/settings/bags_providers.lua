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
    local NotifyProviderFor = ctx.NotifyProviderFor

    -- Shared provider-panel layout scaffold (core/settings_layout_shared.lua).
    local function MakeLayout(content)
        return ns.QUI_SettingsLayoutShared.MakeLayout(content, U)
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
        return ns.L["Currency"] .. " " .. tostring(id)
    end

    local function ItemLabel(itemID)
        local name = C_Item and C_Item.GetItemInfo and C_Item.GetItemInfo(itemID)
        if name and name ~= "" then
            return string.format("%s (%d)", name, itemID)
        end
        return ns.L["Item"] .. " " .. tostring(itemID)
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

    -- Currency bar config uses the shared currency-section model
    -- (currencyOrder array + currencyEnabled map, STRING ids — the same
    -- shape the datatext/Info Bar Currencies section edits). One-time
    -- migration folds the legacy [id]=true set in as enabled rows; the
    -- lists are authoritative afterwards (currency_bar.lua renders
    -- order ∩ enabled).
    local function EnsureCurrencyBarLists(cfg)
        if type(cfg.currencyOrder) ~= "table" then cfg.currencyOrder = {} end
        if type(cfg.currencyEnabled) ~= "table" then cfg.currencyEnabled = {} end
        if type(cfg.currencies) == "table" then
            local legacy = {}
            for id in pairs(cfg.currencies) do legacy[#legacy + 1] = id end
            table.sort(legacy)
            local inOrder = {}
            for _, sid in ipairs(cfg.currencyOrder) do inOrder[tostring(sid)] = true end
            for _, id in ipairs(legacy) do
                local sid = tostring(id)
                if not inOrder[sid] then
                    cfg.currencyOrder[#cfg.currencyOrder + 1] = sid
                end
                cfg.currencyEnabled[sid] = true
            end
            cfg.currencies = nil
        end
    end

    -- (The section's row pool is the Blizzard backpack-tracked list — the
    -- shared builder's default, the same pool the Info Bar/datatext pages
    -- list. Legacy configured-but-untracked IDs survive in currencyEnabled
    -- but only get a row/render while tracked.)

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
    ctx.RegisterShared("bags", { build = function(content, _key, _width)
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
        -- (currencyOrder/currencyEnabled are ensured by EnsureCurrencyBarLists
        -- at the Currency Bar section below; the legacy `currencies` set is
        -- migrated there and must NOT be re-created here.)

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
                    title      = ns.L["Reload UI?"],
                    message    = ns.L["This change takes full effect after a reload."],
                    acceptText = ns.L["Reload"],
                    cancelText = ns.L["Later"],
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

        L.headerAt(ns.L["General"])
        local g0 = L.sectionAt()
        local moduleW = GUI:CreateFormCheckbox(g0.frame, nil, "enabled", moduleProxy, nil,
            { description = ns.L["QUI's bag takeover. Mirrors the Bags row on the Module Addons page: enabling loads the module (live when possible), disabling hands bags back to Blizzard — a UI reload is prompted for a clean handoff. Everything below applies live while the module is enabled."] })
        g0.AddRow(row(g0.frame, ns.L["Enable Bags Module"], moduleW))
        L.closeSection(g0)

        -- APPEARANCE
        L.headerAt(ns.L["Appearance"])
        local s1 = L.sectionAt()
        local iconSizeW = GUI:CreateFormSlider(s1.frame, nil, 24, 48, 1, "iconSize", bags.appearance, Refresh,
            { description = ns.L["Pixel size of each item button in the bag, bank, and guild bank windows."] })
        local columnsW = GUI:CreateFormSlider(s1.frame, nil, 6, 20, 1, "columns", bags.appearance, Refresh,
            { description = ns.L["How many item columns the bag window grid uses."] })
        s1.AddRow(row(s1.frame, ns.L["Icon Size"], iconSizeW), row(s1.frame, ns.L["Columns"], columnsW))

        local spacingW = GUI:CreateFormSlider(s1.frame, nil, 0, 8, 1, "spacing", bags.appearance, Refresh,
            { description = ns.L["Pixel gap between item buttons."] })
        local setMarkW = GUI:CreateFormCheckbox(s1.frame, nil, "equipmentSetMark", bags.appearance, Refresh,
            { description = ns.L["Show a small gear icon on items that belong to a saved equipment set (live bag and bank views)."] })
        s1.AddRow(row(s1.frame, ns.L["Item Spacing"], spacingW), row(s1.frame, ns.L["Equipment Set Icon"], setMarkW))

        local layoutModeW = GUI:CreateFormDropdown(s1.frame, nil, {
            { value = "flat", text = ns.L["Flat Grid"] },
            { value = "categories", text = ns.L["Categories"] },
        }, "layoutMode", bags.appearance, Refresh,
            { description = ns.L["Bag window layout. Flat Grid mirrors your real bag slots; Categories groups items under headers (Equipment, Consumables, Trade Goods, ... Junk last; new loot lands in Recent) and hides empty slots — the free count stays in the footer."] })
        local reagentW = GUI:CreateFormDropdown(s1.frame, nil, {
            { value = "separate", text = ns.L["Separate Section"] },
            { value = "merged", text = ns.L["Merged Into Grid"] },
            { value = "hidden", text = ns.L["Hidden"] },
        }, "reagentDisplay", bags.appearance, Refresh,
            { description = ns.L["Flat Grid only: show the reagent bag as its own labeled section below the regular bags, merge its slots into the grid, or hide it from the bag window entirely."] })
        s1.AddRow(row(s1.frame, ns.L["Layout"], layoutModeW), row(s1.frame, ns.L["Reagent Bag"], reagentW))

        local bankColsW = GUI:CreateFormSlider(s1.frame, nil, 6, 24, 1, "bankColumns", bags.appearance, Refresh,
            { description = ns.L["How many item columns the bank window grid uses."] })
        local guildColsW = GUI:CreateFormSlider(s1.frame, nil, 6, 24, 1, "guildColumns", bags.appearance, Refresh,
            { description = ns.L["How many item columns the guild bank grid uses."] })
        s1.AddRow(row(s1.frame, ns.L["Bank Columns"], bankColsW), row(s1.frame, ns.L["Guild Bank Columns"], guildColsW))

        local groupEmptyW = GUI:CreateFormCheckbox(s1.frame, nil, "groupEmptySlots", bags.appearance, Refresh,
            { description = ns.L["Flat Grid only: collapse each section's empty slots into a single cell showing the free count."] })
        local greyJunkW = GUI:CreateFormCheckbox(s1.frame, nil, "greyJunk", bags.appearance, Refresh,
            { description = ns.L["Desaturate junk (grey-quality) items."] })
        s1.AddRow(row(s1.frame, ns.L["Group Empty Slots"], groupEmptyW), row(s1.frame, ns.L["Grey Out Junk"], greyJunkW))

        local markUnusableW = GUI:CreateFormCheckbox(s1.frame, nil, "markUnusable", bags.appearance, Refresh,
            { description = ns.L["Red-tint items your character cannot use (reads the item tooltip's red text)."] })
        local setBorderW = GUI:CreateFormCheckbox(s1.frame, nil, "equipmentSetBorder", bags.appearance, Refresh,
            { description = ns.L["Use a cyan border instead of the quality color on items that belong to a saved equipment set (live views)."] })
        s1.AddRow(row(s1.frame, ns.L["Mark Unusable Items"], markUnusableW), row(s1.frame, ns.L["Equipment Set Border"], setBorderW))

        local contextFadeW = GUI:CreateFormCheckbox(s1.frame, nil, "contextFading", bags.appearance, Refresh,
            { description = ns.L["Fade items that don't match the open context UI (socketing, scrapping, item upgrade)."] })
        local bagSlotsW = GUI:CreateFormCheckbox(s1.frame, nil, "showBagSlots", bags.appearance, Refresh,
            { description = ns.L["Show the bag-slot strip at the top of the bag window: your four bag slots plus the reagent bag slot. Drag a container onto a slot (or click with one on the cursor) to equip or swap it; click an equipped bag to pick it up."] })
        s1.AddRow(row(s1.frame, ns.L["Context Fading"], contextFadeW), row(s1.frame, ns.L["Show Bag Slots"], bagSlotsW))

        -- Per-bag hiding (bags 1–4): display-only, mirrors Alt+click on the
        -- bag-slot strip. Numeric keys into the hiddenBags scalar map.
        local hiddenBags = bags.appearance.hiddenBags
        local hide1W = GUI:CreateFormCheckbox(s1.frame, nil, 1, hiddenBags, Refresh,
            { description = ns.L["Hide bag 1's slots from the bag window grid. Display-only: search and sort still cover it."] })
        local hide2W = GUI:CreateFormCheckbox(s1.frame, nil, 2, hiddenBags, Refresh,
            { description = ns.L["Hide bag 2's slots from the bag window grid. Display-only: search and sort still cover it."] })
        s1.AddRow(row(s1.frame, ns.L["Hide Bag 1"], hide1W), row(s1.frame, ns.L["Hide Bag 2"], hide2W))
        local hide3W = GUI:CreateFormCheckbox(s1.frame, nil, 3, hiddenBags, Refresh,
            { description = ns.L["Hide bag 3's slots from the bag window grid. Display-only: search and sort still cover it."] })
        local hide4W = GUI:CreateFormCheckbox(s1.frame, nil, 4, hiddenBags, Refresh,
            { description = ns.L["Hide bag 4's slots from the bag window grid. Display-only: search and sort still cover it."] })
        s1.AddRow(row(s1.frame, ns.L["Hide Bag 3"], hide3W), row(s1.frame, ns.L["Hide Bag 4"], hide4W))
        L.closeSection(s1)

        -- CORNER WIDGETS (per-corner primary + fallback pick)
        L.headerAt(ns.L["Icon Corners"])
        local sc = L.sectionAt()
        local CORNER_OPTS = {
            { value = "none", text = ns.L["None"] },
            { value = "quantity", text = ns.L["Quantity"] },
            { value = "item_level", text = ns.L["Item Level"] },
            { value = "junk", text = ns.L["Junk Coin"] },
            { value = "equipment_set", text = ns.L["Equipment Set"] },
            { value = "binding", text = ns.L["Binding (BoE/BoA)"] },
            { value = "expansion", text = ns.L["Expansion"] },
            { value = "crafting_quality", text = ns.L["Crafting Quality (R1-R5)"] },
        }
        local function cornerDD(key, desc)
            return GUI:CreateFormDropdown(sc.frame, nil, CORNER_OPTS, key, bags.appearance.corners, Refresh,
                { description = desc })
        end
        sc.AddRow(row(sc.frame, ns.L["Top Left"], cornerDD("tl1",
                ns.L["Primary widget for the top-left icon corner. The first widget that applies to an item renders."])),
            row(sc.frame, ns.L["Top Left Fallback"], cornerDD("tl2",
                ns.L["Shown in the top-left corner when the primary widget doesn't apply to the item."])))
        sc.AddRow(row(sc.frame, ns.L["Top Right"], cornerDD("tr1",
                ns.L["Primary widget for the top-right icon corner."])),
            row(sc.frame, ns.L["Top Right Fallback"], cornerDD("tr2",
                ns.L["Shown in the top-right corner when the primary widget doesn't apply."])))
        sc.AddRow(row(sc.frame, ns.L["Bottom Left"], cornerDD("bl1",
                ns.L["Primary widget for the bottom-left icon corner."])),
            row(sc.frame, ns.L["Bottom Left Fallback"], cornerDD("bl2",
                ns.L["Shown in the bottom-left corner when the primary widget doesn't apply."])))
        sc.AddRow(row(sc.frame, ns.L["Bottom Right"], cornerDD("br1",
                ns.L["Primary widget for the bottom-right icon corner."])),
            row(sc.frame, ns.L["Bottom Right Fallback"], cornerDD("br2",
                ns.L["Shown in the bottom-right corner when the primary widget doesn't apply."])))

        local cornerFontW = GUI:CreateFormSlider(sc.frame, nil, 8, 16, 1, "cornerFontSize", bags.appearance, Refresh,
            { description = ns.L["Font size of corner text widgets (quantity, item level, binding, expansion)."] })
        local qualityTextW = GUI:CreateFormCheckbox(sc.frame, nil, "qualityColorText", bags.appearance, Refresh,
            { description = ns.L["Color corner text (item level, binding) by the item's quality instead of white."] })
        sc.AddRow(row(sc.frame, ns.L["Corner Font Size"], cornerFontW), row(sc.frame, ns.L["Quality-Colored Text"], qualityTextW))
        L.closeSection(sc)

        -- BEHAVIOR
        local sortOptions = {
            { value = "quality", text = ns.L["Quality"] },
            { value = "type", text = ns.L["Type"] },
            { value = "name", text = ns.L["Name"] },
            { value = "ilvl", text = ns.L["Item Level"] },
            { value = "expansion", text = ns.L["Expansion"] },
        }
        local tooltipCountOptions = {
            { value = "on", text = ns.L["Always On"] },
            { value = "off", text = ns.L["Off"] },
            { value = "modifier", text = ns.L["While Shift Held"] },
        }

        L.headerAt(ns.L["Behavior"])
        local s2 = L.sectionAt()
        local sortKeyW = GUI:CreateFormDropdown(s2.frame, nil, sortOptions, "sortKey", behavior, nil,
            { description = ns.L["Primary ordering the Sort button uses. Quality sorts best-first; the other keys fall back to quality within equal groups. Right-clicking a Sort button changes this too."] })
        local sortRevW = GUI:CreateFormCheckbox(s2.frame, nil, "sortReverse", behavior, nil,
            { description = ns.L["Flip the chosen sort order wholesale (worst-first quality, Z-A names, lowest item level first, ...)."] })
        s2.AddRow(row(s2.frame, ns.L["Sort Items By"], sortKeyW), row(s2.frame, ns.L["Reverse Sort Order"], sortRevW))

        local tooltipCountsW = GUI:CreateFormDropdown(s2.frame, nil, tooltipCountOptions, "tooltipCounts", behavior, nil,
            { description = ns.L["Show how many of an item you own across characters, bank, mail, and more on item tooltips. 'While Shift Held' shows the counts only while Shift is down."] })
        local autoReagentsW = GUI:CreateFormCheckbox(s2.frame, nil, "autoDepositReagents", behavior, nil,
            { description = ns.L["Deposit all crafting reagents from your bags into the warband bank every time you open the bank."] })
        s2.AddRow(row(s2.frame, ns.L["Tooltip Item Counts"], tooltipCountsW), row(s2.frame, ns.L["Auto-Deposit Reagents"], autoReagentsW))

        local glowEnableW = GUI:CreateFormCheckbox(s2.frame, nil, "enabled", behavior.newItemGlow, Refresh,
            { description = ns.L["Highlight recently looted items in the bag window until you mouse over them or the timeout passes."] })
        local glowTimeoutW = GUI:CreateFormSlider(s2.frame, nil, 5, 120, 5, "timeoutMinutes", behavior.newItemGlow, nil,
            { description = ns.L["Minutes before a new-item highlight expires on its own."] })
        s2.AddRow(row(s2.frame, ns.L["New Item Highlight"], glowEnableW), row(s2.frame, ns.L["Highlight Timeout (min)"], glowTimeoutW))
        L.closeSection(s2)

        -- AUTO-OPEN
        L.headerAt(ns.L["Auto-Open"])
        local s3 = L.sectionAt()
        local autoOpenRows = {
            { key = "merchant", label = ns.L["Merchant"], desc = ns.L["Open the bag window when you talk to a merchant."] },
            { key = "mail", label = ns.L["Mailbox"], desc = ns.L["Open the bag window at a mailbox."] },
            { key = "auctionHouse", label = ns.L["Auction House"], desc = ns.L["Open the bag window at the auction house."] },
            { key = "trade", label = ns.L["Trade"], desc = ns.L["Open the bag window when a trade starts."] },
            { key = "scrappingMachine", label = ns.L["Scrapping Machine"], desc = ns.L["Open the bag window at a scrapping machine."] },
            { key = "itemUpgrade", label = ns.L["Item Upgrade"], desc = ns.L["Open the bag window at the item upgrade vendor."] },
            { key = "socket", label = ns.L["Socketing"], desc = ns.L["Open the bag window when socketing an item."] },
            { key = "bank", label = ns.L["Bank"], desc = ns.L["Open the bag window alongside the bank window."] },
            { key = "guildBank", label = ns.L["Guild Bank"], desc = ns.L["Open the bag window alongside the guild bank window."] },
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
        L.headerAt(ns.L["Junk"])
        local s4 = L.sectionAt()
        local junkDimW = GUI:CreateFormCheckbox(s4.frame, nil, "dim", behavior.junk, Refresh,
            { description = ns.L["Desaturate junk (gray) items and overlay a coin icon in the bag window."] })
        local sellButtonW = GUI:CreateFormCheckbox(s4.frame, nil, "sellButton", behavior.junk, Refresh,
            { description = ns.L["Show a Sell Junk button in the bag window while a merchant is open."] })
        s4.AddRow(row(s4.frame, ns.L["Dim Junk Items"], junkDimW), row(s4.frame, ns.L["Sell Junk Button"], sellButtonW))

        local exclusionWrapper = { selected = "" }
        local exclusionDropdown
        exclusionDropdown = GUI:CreateFormDropdown(s4.frame, nil, BuildExclusionOptions(behavior.junk), "selected", exclusionWrapper, function(value)
            if not value or value == "" then return end
            behavior.junk.exclusions[value] = nil
            print("|cff60A5FAQUI:|r " .. string.format(ns.L["Removed junk exclusion: %s"], ItemLabel(value)))
            exclusionWrapper.selected = ""
            if exclusionDropdown.SetOptions then exclusionDropdown.SetOptions(BuildExclusionOptions(behavior.junk)) end
            if exclusionDropdown.SetValue then exclusionDropdown.SetValue("", true) end
            Refresh()
        end, { description = ns.L["Items excluded from junk dimming and the Sell Junk button. Selecting one removes the exclusion."] })
        s4.AddRow(row(s4.frame, ns.L["Remove Exclusion"], exclusionDropdown))

        -- Add-by-ID cell (the currency-bar idiom below): validate via
        -- GetItemInfoInstant (MayReturnNothing per ItemDocumentation — nil
        -- = no such item; instant, no async wait), write exclusions[id]=true.
        local exclAddInput = GUI:CreateFormEditBox(s4.frame, nil, nil, nil, nil, {
            commitOnEnter = false, commitOnFocusLost = false,
            onEscapePressed = function(self) self:ClearFocus() end,
        }, { description = ns.L["Numeric item ID to exclude from junk handling (find IDs on database sites or via item tooltips). Click Add to validate and append it."] })
        local exclAddCell = row(s4.frame, ns.L["Add Exclusion by ID"], exclAddInput)
        local exclAddBtn = GUI:CreateButton(exclAddCell, ns.L["Add"], 70, 22, function()
            local text = exclAddInput.editBox and exclAddInput.editBox:GetText()
            local id = tonumber(text)
            if not id or id <= 0 or id % 1 ~= 0 then
                print("|cffff0000QUI:|r " .. ns.L["Enter a numeric item ID."])
                return
            end
            local valid = C_Item and C_Item.GetItemInfoInstant
                and C_Item.GetItemInfoInstant(id)
            if not valid then
                print("|cffff0000QUI:|r " .. string.format(ns.L["Unknown item ID: %s"], id))
                return
            end
            behavior.junk.exclusions[id] = true
            if exclAddInput.editBox then exclAddInput.editBox:SetText("") end
            print("|cff60A5FAQUI:|r " .. string.format(ns.L["Added junk exclusion: %s"], ItemLabel(id)))
            if exclusionDropdown.SetOptions then exclusionDropdown.SetOptions(BuildExclusionOptions(behavior.junk)) end
            Refresh()
        end)
        exclAddBtn:SetPoint("RIGHT", exclAddCell, "RIGHT", 0, 0)
        exclAddInput:ClearAllPoints()
        exclAddInput:SetPoint("LEFT", exclAddCell, "LEFT", 84, 0)
        exclAddInput:SetPoint("RIGHT", exclAddBtn, "LEFT", -8, 0)

        L.closeSection(s4)
        PlaceNote(L, content,
            ns.L["Exclusions protect specific items from junk dimming and the Sell Junk button. Add by item ID above; remove via the dropdown."],
            26)

        -- CURRENCY BAR
        L.headerAt(ns.L["Currency Bar"])
        local s5 = L.sectionAt()
        local cbar = bags.currencyBar
        local cbarEnableW = GUI:CreateFormCheckbox(s5.frame, nil, "enabled", cbar, Refresh,
            { description = ns.L["Show a footer row on the bag window with the currencies enabled below."] })
        s5.AddRow(row(s5.frame, ns.L["Enable Currency Bar"], cbarEnableW))
        L.closeSection(s5)

        -- Currency list: the shared toggle+reorder section — the same view
        -- AND the same Blizzard backpack-tracked pool as the Info Bar/
        -- datatext Currencies settings; only the edited config differs
        -- (bags.currencyBar). The builder is exported by the QUI_Datatexts
        -- settings page — guarded because QUI_Bags does not depend on that
        -- module addon.
        if ns.QUI_BuildCurrencyOrderSection then
            EnsureCurrencyBarLists(cbar)
            ns.QUI_BuildCurrencyOrderSection(L, content, {
                dtGlobal = cbar,
                header = ns.L["Currencies"],
                hint = ns.L["Enabled currencies show on the bag window's bar, in this order."],
                toggleDescription = ns.L["Show this currency on the bag window's currency bar. Use the arrows to reorder."],
                note = ns.L["Lists your backpack-tracked currencies — the same pool as the Currencies datatext."],
                refresh = Refresh,
                notify = function(region)
                    if NotifyProviderFor then NotifyProviderFor(region, { structural = true }) end
                end,
            })
        else
            local noteRow = CreateFrame("Frame", nil, content)
            local note = noteRow:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            note:SetPoint("LEFT", noteRow, "LEFT", 0, 0)
            note:SetTextColor(1, 0.6, 0.1, 1)
            note:SetText(ns.L["Enable the Datatexts module addon (Modules page) to configure the currency list."])
            L.placeCustom(noteRow, 18)
        end

        -- CACHED DATA
        L.headerAt(ns.L["Cached Data"])
        local s6 = L.sectionAt()
        local charWrapper = { selected = "" }
        local charDropdown
        charDropdown = GUI:CreateFormDropdown(s6.frame, nil, BuildCharacterOptions(), "selected", charWrapper, function(value)
            if not value or value == "" then return end
            GUI:ShowConfirmation({
                title = ns.L["Delete Cached Character?"],
                message = string.format(ns.L["Delete the cached inventory data for '%1$s'?"], value),
                warningText = ns.L["This cannot be undone. The cache rebuilds the next time that character logs in."],
                acceptText = ns.L["Delete"], cancelText = ns.L["Cancel"], isDestructive = true,
                onAccept = function()
                    local Store = ns.Bags and ns.Bags.Store
                    if Store and Store.DeleteCharacter then
                        Store.DeleteCharacter(value)
                        print("|cff60A5FAQUI:|r " .. string.format(ns.L["Deleted cached character: %s"], value))
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
        end, { description = ns.L["Delete a character's cached bags, bank, equipment, mail, and currency data. The current character can't be deleted."] })

        local guildWrapper = { selected = "" }
        local guildDropdown
        guildDropdown = GUI:CreateFormDropdown(s6.frame, nil, BuildGuildOptions(), "selected", guildWrapper, function(value)
            if not value or value == "" then return end
            GUI:ShowConfirmation({
                title = ns.L["Delete Cached Guild?"],
                message = string.format(ns.L["Delete the cached guild bank data for '%1$s'?"], value),
                warningText = ns.L["This cannot be undone. The cache rebuilds on the next guild bank visit."],
                acceptText = ns.L["Delete"], cancelText = ns.L["Cancel"], isDestructive = true,
                onAccept = function()
                    local Store = ns.Bags and ns.Bags.Store
                    if Store and Store.DeleteGuild then
                        Store.DeleteGuild(value)
                        print("|cff60A5FAQUI:|r " .. string.format(ns.L["Deleted cached guild: %s"], value))
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
        end, { description = ns.L["Delete a guild's cached guild bank data."] })
        s6.AddRow(row(s6.frame, ns.L["Delete Character Cache"], charDropdown), row(s6.frame, ns.L["Delete Guild Cache"], guildDropdown))
        L.closeSection(s6)

        L.relayoutSections()
        return content:GetHeight()
    end })
end)
