--[[
    QUI Alts Shared Settings Provider
    Owns provider-backed settings content for the Alts surface in the shared
    settings layer (bags_providers precedent: MakeLayout with
    headerAt/sectionAt/closeSection/placeCustom, the `row` helper via
    ns.QUI_Options.BuildSettingRow, DB writes calling _G.QUI_RefreshAlts).

    Loaded cross-addon from QUI_Options.toc (LoD), NOT from QUI_Alts.toc —
    the shared settings layer only exists once QUI_Options loads, so the
    ProviderPanels guard returns early in any other context.
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
-- (bags_providers precedent).
ProviderPanels:RegisterAfterLoad(function(ctx)
    local GUI = ctx.GUI
    local U = ctx.U
    local NotifyProviderFor = ctx.NotifyProviderFor
    local PAD = (ns.QUI_Options and ns.QUI_Options.PADDING) or 15
    local HEADER_GAP = 26
    local SECTION_GAP = 14

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

    -- Muted inline note (bags_providers idiom, word-wrapped).
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
    -- ALTS PROVIDER
    ---------------------------------------------------------------------------
    ctx.RegisterShared("alts", { build = function(content, _key, _width)
        local db = U.GetProfileDB()
        if not db or not db.alts or not ns.QUI_Options then return 80 end
        local alts = db.alts
        if not alts.columns then alts.columns = {} end
        if not alts.scanners then alts.scanners = {} end

        -- Roster columns refresh live: QUI_RefreshAlts reflows an open window
        -- via Window.OnProfileChanged; also poke RefreshActive so the active
        -- tab re-renders immediately.
        local function Refresh()
            if _G.QUI_RefreshAlts then _G.QUI_RefreshAlts() end
            local Window = ns.Alts and ns.Alts.Window
            if Window and Window.IsShown and Window.IsShown() and Window.RefreshActive then
                Window.RefreshActive()
            end
        end
        -- Scanner toggles only write the DB: the collector reads each flag
        -- live (ScannerEnabled in core/storage/collector.lua); no refresh.
        local function NoRefresh() end

        local L = MakeLayout(content)

        ---------------------------------------------------------------------
        -- ALTS MODULE (master toggle — chat_frame1_provider parity: the flip
        -- writes the manifest legacyFlag live, then offers a reload so the
        -- LoD addon actually loads/unloads)
        ---------------------------------------------------------------------
        local function ShowAltsModuleReloadPrompt()
            local Q = _G.QUI
            local G = Q and Q.GUI
            if G and type(G.ShowConfirmation) == "function" then
                G:ShowConfirmation({
                    title      = "Reload UI?",
                    message    = "This change takes full effect after a reload.",
                    acceptText = "Reload",
                    cancelText = "Later",
                    onAccept   = function() if Q and Q.SafeReload then Q:SafeReload() end end,
                })
            end
        end
        L.headerAt("Alts Module")
        local s0 = L.sectionAt()
        local enableW = GUI:CreateFormCheckbox(s0.frame, nil, "enabled", alts, function()
            Refresh()
            ShowAltsModuleReloadPrompt()
        end, { description = "Account-wide character tracking window (/alts): roster, professions, reputations, weeklies, and item search across all your characters." })
        s0.AddRow(row(s0.frame, "Enable Alts Module", enableW))
        L.closeSection(s0)

        ---------------------------------------------------------------------
        -- ROSTER COLUMNS
        ---------------------------------------------------------------------
        L.headerAt("Roster Columns")
        local s1 = L.sectionAt()
        local columnRows = {
            { key = "ilvl",        label = "Item level",
              desc = "Columns shown on the Roster tab; Character and Level always show." },
            { key = "gold",        label = "Gold" },
            { key = "played",      label = "Played time" },
            { key = "rested",      label = "Rested XP" },
            { key = "zone",        label = "Zone" },
            { key = "lastSeen",    label = "Last seen" },
            { key = "professions", label = "Professions" },
        }
        local pendingCol = nil
        for _, def in ipairs(columnRows) do
            local w = GUI:CreateFormCheckbox(s1.frame, nil, def.key, alts.columns, Refresh,
                def.desc and { description = def.desc } or nil)
            local cell = row(s1.frame, def.label, w)
            if pendingCol then
                s1.AddRow(pendingCol, cell)
                pendingCol = nil
            else
                pendingCol = cell
            end
        end
        if pendingCol then
            s1.AddRow(pendingCol)
        end
        L.closeSection(s1)

        ---------------------------------------------------------------------
        -- SCANNERS
        ---------------------------------------------------------------------
        L.headerAt("Scanners")
        local s2 = L.sectionAt()
        local repW = GUI:CreateFormCheckbox(s2.frame, nil, "reputations", alts.scanners, NoRefresh,
            { description = "Track faction standings on this character." })
        local weekW = GUI:CreateFormCheckbox(s2.frame, nil, "weeklies", alts.scanners, NoRefresh,
            { description = "Track Great Vault, M+ rating, and keystone." })
        s2.AddRow(row(s2.frame, "Reputations", repW), row(s2.frame, "Weeklies", weekW))

        local lockW = GUI:CreateFormCheckbox(s2.frame, nil, "lockouts", alts.scanners, NoRefresh,
            { description = "Track saved instances." })
        s2.AddRow(row(s2.frame, "Lockouts", lockW))
        L.closeSection(s2)

        ---------------------------------------------------------------------
        -- TAB FILTERS (currencies + reputations visibility; same db keys as
        -- the in-window Filter buttons: [id] = false hides, absent = show).
        -- One dropdown button per tab opening the shared searchable popup
        -- (filter_popup.lua, floating mode — the settings scrollframe clips
        -- child frames). List builders live in the LoD view files — guard
        -- and fall back to a note when QUI_Alts isn't loaded (LoD-symbol
        -- rule); the data itself comes from always-loaded core Storage.
        ---------------------------------------------------------------------
        if not alts.currencyFilter then alts.currencyFilter = {} end
        if not alts.reputationFilter then alts.reputationFilter = {} end

        local Store2 = ns.Storage and ns.Storage.Store
        local storeChars = {}
        if Store2 and Store2.IsInitialized and Store2.IsInitialized()
            and Store2.ListCharacters and Store2.GetCharacter then
            for _, key in ipairs(Store2.ListCharacters()) do
                local rec = Store2.GetCharacter(key)
                if rec then storeChars[key] = rec end
            end
        end

        -- dropdown-style button (alts-window selector chrome) opening the
        -- shared filter popup; label shows a visible/hidden summary
        local function MakeFilterDropdown(parentFrame)
            local UIKit = ns.UIKit
            local b = CreateFrame("Button", nil, parentFrame)
            b:SetSize(200, 22)
            UIKit.CreateBackground(b, 1, 1, 1, 0.06)
            UIKit.CreateBorderLines(b)
            UIKit.UpdateBorderLines(b, 1, 1, 1, 1, 0.2)
            b:SetScript("OnEnter", function(self)
                UIKit.UpdateBorderLines(self, 1, 1, 1, 1, 0.35)
            end)
            b:SetScript("OnLeave", function(self)
                UIKit.UpdateBorderLines(self, 1, 1, 1, 1, 0.2)
            end)
            local caret = UIKit.CreateChevronCaret(b, {
                point = "RIGHT", relativeTo = b, relativePoint = "RIGHT",
                xPixels = -8, sizePixels = 10, lineWidthPixels = 6,
                r = 1, g = 1, b = 1, a = 0.45,
                expanded = true,
            })
            local lbl = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            lbl:SetPoint("LEFT", b, "LEFT", 8, 0)
            lbl:SetPoint("RIGHT", caret, "LEFT", -4, 0)
            lbl:SetJustifyH("LEFT")
            lbl:SetTextColor(0.9, 0.9, 0.9, 1)
            function b.SetSummary(text) lbl:SetText(text) end
            return b
        end

        local function MakeSummary(entries, filter, idField)
            local hidden = 0
            for _, e in ipairs(entries) do
                if filter[e[idField]] == false then hidden = hidden + 1 end
            end
            if hidden == 0 then
                return string.format("All shown (%d)", #entries)
            end
            return string.format("%d of %d shown", #entries - hidden, #entries)
        end

        local FP = ns.Alts and ns.Alts.FilterPopup

        L.headerAt("Currencies Tab")
        local CV = ns.Alts and ns.Alts.CurrenciesView
        if not (CV and FP) then
            PlaceNote(L, content,
                "Enable the Alts module (and reload) to configure which currencies the Currencies tab shows.",
                30)
        else
            local curNames = {}
            for _, rec in pairs(storeChars) do
                if type(rec.currencies) == "table" then
                    for id in pairs(rec.currencies) do
                        if curNames[id] == nil and C_CurrencyInfo and C_CurrencyInfo.GetCurrencyInfo then
                            local info = C_CurrencyInfo.GetCurrencyInfo(id) -- MayReturnNothing
                            curNames[id] = (info and info.name) or false
                        end
                    end
                end
            end
            local curEntries = CV.BuildDisplayRows(storeChars, curNames, nil)
            if #curEntries == 0 then
                PlaceNote(L, content, "No currencies tracked yet.", 26)
            else
                local sC = L.sectionAt()
                local btn = MakeFilterDropdown(sC.frame)
                btn.SetSummary(MakeSummary(curEntries, alts.currencyFilter, "currencyID"))
                FP.Attach({
                    tabFrame = content,
                    floating = true,
                    anchorButton = btn,
                    getRows = function()
                        local popupRows = {}
                        for _, e in ipairs(curEntries) do
                            popupRows[#popupRows + 1] = { id = e.currencyID, label = e.label }
                        end
                        return popupRows
                    end,
                    isChecked = function(id) return alts.currencyFilter[id] ~= false end,
                    setChecked = function(id, checked)
                        if checked then alts.currencyFilter[id] = nil
                        else alts.currencyFilter[id] = false end
                    end,
                    onChanged = function()
                        btn.SetSummary(MakeSummary(curEntries, alts.currencyFilter, "currencyID"))
                        Refresh()
                    end,
                })
                sC.AddRow(row(sC.frame, "Visible currencies", btn,
                    "Choose which currencies the Currencies tab lists. Same filter as the tab's own Filter button."))
                L.closeSection(sC)
            end
        end

        L.headerAt("Reputations Tab")
        local RV = ns.Alts and ns.Alts.ReputationsView
        if not (RV and FP) then
            PlaceNote(L, content,
                "Enable the Alts module (and reload) to configure which reputations the Reputations tab shows.",
                30)
        else
            local fNames  = (Store2 and Store2.GetFactionNames  and Store2.GetFactionNames())  or {}
            local fGroups = (Store2 and Store2.GetFactionGroups and Store2.GetFactionGroups()) or {}
            local repRows = RV.BuildDisplayRows(storeChars, fNames, fGroups, nil)
            local factionEntries = {}
            for _, r in ipairs(repRows) do
                if r.kind == "faction" then
                    factionEntries[#factionEntries + 1] = r
                end
            end
            if #factionEntries == 0 then
                PlaceNote(L, content, "No reputations tracked yet.", 26)
            else
                local sR = L.sectionAt()
                local btn = MakeFilterDropdown(sR.frame)
                btn.SetSummary(MakeSummary(factionEntries, alts.reputationFilter, "factionID"))
                FP.Attach({
                    tabFrame = content,
                    floating = true,
                    anchorButton = btn,
                    getRows = function()
                        -- full row list incl. group headers (gold rows)
                        local popupRows = {}
                        for _, e in ipairs(repRows) do
                            if e.kind == "group" then
                                popupRows[#popupRows + 1] = { label = e.label, header = true }
                            else
                                popupRows[#popupRows + 1] = { id = e.factionID, label = e.label }
                            end
                        end
                        return popupRows
                    end,
                    isChecked = function(id) return alts.reputationFilter[id] ~= false end,
                    setChecked = function(id, checked)
                        if checked then alts.reputationFilter[id] = nil
                        else alts.reputationFilter[id] = false end
                    end,
                    onChanged = function()
                        btn.SetSummary(MakeSummary(factionEntries, alts.reputationFilter, "factionID"))
                        Refresh()
                    end,
                })
                sR.AddRow(row(sR.frame, "Visible reputations", btn,
                    "Choose which reputations the Reputations tab lists. Same filter as the tab's own Filter button."))
                L.closeSection(sR)
            end
        end

        ---------------------------------------------------------------------
        -- CACHE (character list + delete — alt-tracking design doc scope:
        -- "character-cache management (list + delete)")
        ---------------------------------------------------------------------
        L.headerAt("Cache")
        local Store = ns.Storage and ns.Storage.Store
        local keys = (Store and Store.IsInitialized and Store.IsInitialized()
            and Store.ListCharacters and Store.ListCharacters()) or {}
        if #keys == 0 then
            PlaceNote(L, content,
                "No characters cached yet. Log a character in and it appears here.",
                26)
        else
            local ROW_H = 24
            local currentKey = Store.GetCurrentCharacterKey and Store.GetCurrentCharacterKey()
            local holder = CreateFrame("Frame", nil, content)
            for i, key in ipairs(keys) do
                local rec = Store.GetCharacter and Store.GetCharacter(key)
                local d = (rec and rec.details) or {}
                local y0 = -(i - 1) * ROW_H

                local nameFS = holder:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                nameFS:SetPoint("TOPLEFT", holder, "TOPLEFT", 6, y0 - 6)
                nameFS:SetJustifyH("LEFT")
                nameFS:SetText(key)
                -- RAID_CLASS_COLORS read directly (roster view precedent)
                local c = d.class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[d.class]
                if c then nameFS:SetTextColor(c.r, c.g, c.b, 1) end

                local metaFS = holder:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                metaFS:SetPoint("LEFT", nameFS, "RIGHT", 8, 0)
                metaFS:SetTextColor(0.6, 0.6, 0.6, 1)
                metaFS:SetText(d.level and ("Level " .. d.level) or "")

                if key == currentKey then
                    local curFS = holder:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                    curFS:SetPoint("TOPRIGHT", holder, "TOPRIGHT", -6, y0 - 6)
                    curFS:SetTextColor(0.6, 0.6, 0.6, 1)
                    curFS:SetText("current character")
                else
                    local delBtn
                    delBtn = GUI:CreateButton(holder, "Delete", 60, 18, function()
                        if Store.DeleteCharacter then Store.DeleteCharacter(key) end
                        Refresh()
                        -- structural: the row set changed — rebuild the panel
                        NotifyProviderFor(delBtn, { structural = true })
                    end, "ghost")
                    delBtn:SetPoint("TOPRIGHT", holder, "TOPRIGHT", -6, y0 - 3)
                    GUI:AttachTooltip(delBtn,
                        "Remove this character's cached data (roster, professions, items). It repopulates on that character's next login.",
                        "Delete " .. key)
                end
            end
            L.placeCustom(holder, #keys * ROW_H + 6)
        end

        L.relayoutSections()
        return content:GetHeight()
    end })
end)
