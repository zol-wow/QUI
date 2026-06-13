--- QUI settings — shared provider-panel layout scaffold.
---
--- The `MakeLayout(content)` top-to-bottom stacking helper (headerAt /
--- sectionAt / closeSection / placeCustom + sections/relayoutSections) is
--- copy-pasted across many `*/settings/*` provider files. Those files load in
--- the QUI_Options surface context (QUI_Options.toc), which shares no addon
--- ancestor with the modules that own them, so the only shared home that is
--- always loaded first is core.
---
--- ONLY the self-contained variant lives here: bodies that resolve QUI_Options
--- at MakeLayout entry and treat PAD/HEADER_GAP/SECTION_GAP as constants.
--- Several provider files instead read a file-level `Opts`/`PAD` upvalue that
--- their Build* functions re-resolve *after* MakeLayout returns (the
--- stub-then-replace dance) — extracting those would sever that coupling, so
--- they are intentionally NOT migrated here.

local _, ns = ...

local Shared = ns.QUI_SettingsLayoutShared or {}
ns.QUI_SettingsLayoutShared = Shared

-- Standard provider-panel layout. `U` is the layout-mode utils (ctx.U); when
-- layout mode is positioning-only we hand back the suppressed layout instead.
-- QUI_Options is resolved at entry: callers build the panel on settings-open,
-- long after the on-demand QUI_Options addon has replaced its bootstrap stub.
function Shared.MakeLayout(content, U)
    -- U is the layout-mode utils (ctx.U / ns.QUI_LayoutMode_Utils). Some
    -- provider files never wired the positioning-only suppression and pass no
    -- U; `U and` keeps the guard a no-op for them (identical to their old body)
    -- while preserving suppression for the files that do pass U.
    if U and U._layoutModePositionOnly then
        return U.MakeSuppressedProviderLayout(content)
    end
    local Opts = ns.QUI_Options
    local PAD = (ns.QUI_Options and ns.QUI_Options.PADDING) or 15
    local HEADER_GAP = 26
    local SECTION_GAP = 14
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
    -- Finalize tail used by the finish-family providers (skinning, prey,
    -- datatexts legacy collapsibles, etc.) that size the scroll body directly
    -- instead of via relayoutSections.
    function L.finish()
        content:SetHeight(math.abs(y) + 10)
        return content:GetHeight()
    end
    L.sections = sections
    L.relayoutSections = relayoutSections

    return L
end
