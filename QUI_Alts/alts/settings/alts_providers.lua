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
        -- CACHE
        ---------------------------------------------------------------------
        L.headerAt("Cache")
        PlaceNote(L, content,
            "Right-click a roster row to delete a character from the cache.",
            26)

        L.relayoutSections()
        return content:GetHeight()
    end })
end)
