local _, ns = ...

local Settings = ns.Settings
local ProviderPanels = Settings and Settings.ProviderPanels
if not ProviderPanels or type(ProviderPanels.RegisterAfterLoad) ~= "function" then
    return
end

ProviderPanels:RegisterAfterLoad(function(ctx)
    local GUI = ctx.GUI
    local U = ctx.U
    local NotifyProviderFor = ctx.NotifyProviderFor

    local function MakeLayout(content)
        return ns.QUI_SettingsLayoutShared.MakeLayout(content, U)
    end

    local function row(parent, label, widget, desc)
        return ns.QUI_Options.BuildSettingRow(parent, label, widget, desc)
    end

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

    ctx.RegisterShared("alts", { build = function(content, _key, _width)
        local db = U.GetProfileDB()
        if not db or not db.alts or not ns.QUI_Options then return 80 end
        local alts = db.alts
        if not alts.columns then alts.columns = {} end
        if not alts.scanners then alts.scanners = {} end

        local function Refresh()
            if _G.QUI_RefreshAlts then _G.QUI_RefreshAlts() end
            local Window = ns.Alts and ns.Alts.Window
            if Window and Window.IsShown and Window.IsShown() and Window.RefreshActive then
                Window.RefreshActive()
            end
        end
        local function NoRefresh() end

        local L = MakeLayout(content)

        local function ShowAltsModuleReloadPrompt()
            local Q = _G.QUI
            local G = Q and Q.GUI
            if G and type(G.ShowConfirmation) == "function" then
                G:ShowConfirmation({
                    title      = ns.L["Reload UI?"],
                    message    = ns.L["This change takes full effect after a reload."],
                    acceptText = ns.L["Reload"],
                    cancelText = ns.L["Later"],
                    onAccept   = function() if Q and Q.SafeReload then Q:SafeReload() end end,
                })
            end
        end
        L.headerAt(ns.L["Alts Module"])
        local s0 = L.sectionAt()
        local enableW = GUI:CreateFormCheckbox(s0.frame, nil, "enabled", alts, function()
            Refresh()
            ShowAltsModuleReloadPrompt()
        end, { description = ns.L["Account-wide character tracking window (/alts): roster, professions, reputations, weeklies, and item search across all your characters."] })
        s0.AddRow(row(s0.frame, ns.L["Enable Alts Module"], enableW))
        L.closeSection(s0)

        L.headerAt(ns.L["Roster Columns"])
        local s1 = L.sectionAt()
        local columnRows = {
            { key = "ilvl",        label = ns.L["Item level"],
              desc = ns.L["Columns shown on the Roster tab; Character and Level always show."] },
            { key = "gold",        label = ns.L["Gold"] },
            { key = "played",      label = ns.L["Played time"] },
            { key = "rested",      label = ns.L["Rested XP"] },
            { key = "zone",        label = ns.L["Zone"] },
            { key = "lastSeen",    label = ns.L["Last seen"] },
            { key = "professions", label = ns.L["Professions"] },
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

        L.headerAt(ns.L["Scanners"])
        local s2 = L.sectionAt()
        local repW = GUI:CreateFormCheckbox(s2.frame, nil, "reputations", alts.scanners, NoRefresh,
            { description = ns.L["Track faction standings on this character."] })
        local weekW = GUI:CreateFormCheckbox(s2.frame, nil, "weeklies", alts.scanners, NoRefresh,
            { description = ns.L["Track Great Vault, M+ rating, and keystone."] })
        s2.AddRow(row(s2.frame, ns.L["Reputations"], repW), row(s2.frame, ns.L["Weeklies"], weekW))

        local lockW = GUI:CreateFormCheckbox(s2.frame, nil, "lockouts", alts.scanners, NoRefresh,
            { description = ns.L["Track saved instances."] })
        s2.AddRow(row(s2.frame, ns.L["Lockouts"], lockW))
        L.closeSection(s2)

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
                return string.format(ns.L["All shown (%d)"], #entries)
            end
            return string.format(ns.L["%d of %d shown"], #entries - hidden, #entries)
        end

        local FP = ns.Alts and ns.Alts.FilterPopup

        L.headerAt(ns.L["Currencies Tab"])
        local CV = ns.Alts and ns.Alts.CurrenciesView
        if not (CV and FP) then
            PlaceNote(L, content,
                ns.L["Enable the Alts module (and reload) to configure which currencies the Currencies tab shows."],
                30)
        else
            local curNames = {}
            for _, rec in pairs(storeChars) do
                if type(rec.currencies) == "table" then
                    for id in pairs(rec.currencies) do
                        if curNames[id] == nil and C_CurrencyInfo and C_CurrencyInfo.GetCurrencyInfo then
                            local info = C_CurrencyInfo.GetCurrencyInfo(id)
                            curNames[id] = (info and info.name) or false
                        end
                    end
                end
            end
            local curEntries = CV.BuildDisplayRows(storeChars, curNames, nil)
            if #curEntries == 0 then
                PlaceNote(L, content, ns.L["No currencies tracked yet."], 26)
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
                sC.AddRow(row(sC.frame, ns.L["Visible currencies"], btn,
                    ns.L["Choose which currencies the Currencies tab lists. Same filter as the tab's own Filter button."]))
                L.closeSection(sC)
            end
        end

        L.headerAt(ns.L["Reputations Tab"])
        local RV = ns.Alts and ns.Alts.ReputationsView
        if not (RV and FP) then
            PlaceNote(L, content,
                ns.L["Enable the Alts module (and reload) to configure which reputations the Reputations tab shows."],
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
                PlaceNote(L, content, ns.L["No reputations tracked yet."], 26)
            else
                local sR = L.sectionAt()
                local btn = MakeFilterDropdown(sR.frame)
                btn.SetSummary(MakeSummary(factionEntries, alts.reputationFilter, "factionID"))
                FP.Attach({
                    tabFrame = content,
                    floating = true,
                    anchorButton = btn,
                    getRows = function()
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
                sR.AddRow(row(sR.frame, ns.L["Visible reputations"], btn,
                    ns.L["Choose which reputations the Reputations tab lists. Same filter as the tab's own Filter button."]))
                L.closeSection(sR)
            end
        end

        L.headerAt(ns.L["Cache"])
        local Store = ns.Storage and ns.Storage.Store
        local keys = (Store and Store.IsInitialized and Store.IsInitialized()
            and Store.ListCharacters and Store.ListCharacters()) or {}
        if #keys == 0 then
            PlaceNote(L, content,
                ns.L["No characters cached yet. Log a character in and it appears here."],
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
                local c = d.class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[d.class]
                if c then nameFS:SetTextColor(c.r, c.g, c.b, 1) end

                local metaFS = holder:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                metaFS:SetPoint("LEFT", nameFS, "RIGHT", 8, 0)
                metaFS:SetTextColor(0.6, 0.6, 0.6, 1)
                metaFS:SetText(d.level and (ns.L["Level "] .. d.level) or "")

                if key == currentKey then
                    local curFS = holder:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                    curFS:SetPoint("TOPRIGHT", holder, "TOPRIGHT", -6, y0 - 6)
                    curFS:SetTextColor(0.6, 0.6, 0.6, 1)
                    curFS:SetText(ns.L["current character"])
                else
                    local delBtn
                    delBtn = GUI:CreateButton(holder, ns.L["Delete"], 60, 18, function()
                        if Store.DeleteCharacter then Store.DeleteCharacter(key) end
                        Refresh()
                        NotifyProviderFor(delBtn, { structural = true })
                    end, "ghost")
                    delBtn:SetPoint("TOPRIGHT", holder, "TOPRIGHT", -6, y0 - 3)
                    GUI:AttachTooltip(delBtn,
                        ns.L["Remove this character's cached data (roster, professions, items). It repopulates on that character's next login."],
                        ns.L["Delete "] .. key)
                end
            end
            L.placeCustom(holder, #keys * ROW_H + 6)
        end

        L.relayoutSections()
        return content:GetHeight()
    end })
end)
