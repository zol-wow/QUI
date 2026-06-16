---------------------------------------------------------------------------
-- QUI Layout Mode — Shared Provider Utilities
-- Canonical implementations of CreateCollapsible, StandardRelayout,
-- BuildPositionCollapsible, and PlaceRow used by all settings providers.
---------------------------------------------------------------------------
local ADDON_NAME, ns = ...

-- Re-applies a FontString's current font through the CJK-safe family resolver
-- so Chinese/Korean glyphs render (GameFont* templates are Latin-only).
local function EnsureCJKFont(fs)
    if not fs or not fs.GetFont then return fs end
    local fp, sz, fl = fs:GetFont()
    if fp and ns.Helpers and ns.Helpers.ApplyFontWithFallback then
        ns.Helpers.ApplyFontWithFallback(fs, fp, sz, fl)
    end
    return fs
end

local Helpers = ns.Helpers
local LSM = ns.LSM
local UIKit = ns.UIKit

local Utils = {}
ns.QUI_LayoutMode_Utils = Utils

---------------------------------------------------------------------------
-- SHARED CONSTANTS
---------------------------------------------------------------------------
Utils.ACCENT_R, Utils.ACCENT_G, Utils.ACCENT_B = 0.376, 0.647, 0.980

function Utils:RefreshAccentColor()
    local GUI = _G.QUI and _G.QUI.GUI
    if GUI and GUI.Colors and GUI.Colors.accent then
        self.ACCENT_R = GUI.Colors.accent[1]
        self.ACCENT_G = GUI.Colors.accent[2]
        self.ACCENT_B = GUI.Colors.accent[3]
    end
end
Utils.HEADER_HEIGHT = 24
Utils.FORM_ROW = 32
Utils.PADDING = 0

-- PROVIDER → V2 TILE MAPPING (legacy fallback)
-- Retained as a last-resort bucket when a provider key does not resolve
-- through the shared settings registry. It is currently empty and only
-- exists as a safety net for unmigrated surfaces.
---------------------------------------------------------------------------
Utils.PROVIDER_TO_V2 = {
}

---------------------------------------------------------------------------
-- DB / LSM HELPERS
---------------------------------------------------------------------------

function Utils.GetProfileDB()
    local core = Helpers.GetCore()
    return core and core.db and core.db.profile
end

function Utils.GetTextureList()
    local list = {}
    if LSM then
        for name in pairs(LSM:HashTable("statusbar")) do
            list[#list + 1] = {value = name, text = name}
        end
        table.sort(list, function(a, b) return a.text < b.text end)
    end
    return list
end

function Utils.GetFontList()
    local list = {}
    if LSM then
        for name in pairs(LSM:HashTable("font")) do
            list[#list + 1] = {value = name, text = name}
        end
        table.sort(list, function(a, b) return a.text < b.text end)
    end
    return list
end

function Utils.GetSoundList()
    local sounds = {{value = "None", text = "None"}}
    if LSM then
        for _, name in ipairs(LSM:List("sound") or {}) do
            if name ~= "None" then
                sounds[#sounds + 1] = {value = name, text = name}
            end
        end
    end
    return sounds
end

---------------------------------------------------------------------------
-- ALTERNATING ROW BACKGROUNDS
-- Lays a subtle white-tint strip behind every other direct child of `body`,
-- ordered top-down by current GetTop(). Matches the row-striping rhythm
-- used by QUI_Options.CreateSettingsCardGroup in the main settings window.
---------------------------------------------------------------------------
function Utils.ApplyAlternatingRowBackgrounds(body)
    if not body or not body.GetNumChildren then return end

    -- Tear down any previous strips so re-measures don't stack textures.
    if body._quiAltRowStrips then
        for i = 1, #body._quiAltRowStrips do
            local t = body._quiAltRowStrips[i]
            if t and t.Hide then t:Hide() end
            if t and t.SetParent then t:SetParent(nil) end
        end
    end
    body._quiAltRowStrips = {}

    local children = {}
    local childCount = body:GetNumChildren() or 0
    for i = 1, childCount do
        local child = select(i, body:GetChildren())
        if child and (not child.IsShown or child:IsShown()) and child.GetTop and child:GetTop() then
            children[#children + 1] = child
        end
    end
    if #children < 2 then return end

    table.sort(children, function(a, b)
        return (a:GetTop() or 0) > (b:GetTop() or 0)
    end)

    for i, child in ipairs(children) do
        if (i % 2) == 0 then
            local rowBg = body:CreateTexture(nil, "BACKGROUND", nil, -1)
            rowBg:SetPoint("LEFT", body, "LEFT", -2, 0)
            rowBg:SetPoint("RIGHT", body, "RIGHT", 2, 0)
            rowBg:SetPoint("TOP", child, "TOP", 0, 2)
            rowBg:SetPoint("BOTTOM", child, "BOTTOM", 0, -2)
            rowBg:SetColorTexture(1, 1, 1, 0.02)
            body._quiAltRowStrips[#body._quiAltRowStrips + 1] = rowBg
        end
    end
end

---------------------------------------------------------------------------
-- STANDARD RELAYOUT
---------------------------------------------------------------------------

function Utils.StandardRelayout(content, sections)
    local cy = -8
    for _, s in ipairs(sections) do
        s:ClearAllPoints()
        s:SetPoint("TOPLEFT", content, "TOPLEFT", Utils.PADDING, cy)
        s:SetPoint("RIGHT", content, "RIGHT", -Utils.PADDING, 0)
        cy = cy - s:GetHeight() - 4
    end
    content:SetHeight(math.abs(cy) + 16)
end

---------------------------------------------------------------------------
-- CREATE COLLAPSIBLE SECTION
---------------------------------------------------------------------------

-- V3 card group: always-visible accent-dot header + subtle card body.
-- Signature preserved for backwards compatibility with every provider caller.
-- Legacy `_expanded`/`SetExpanded` fields kept as static no-ops so the old
-- expansion-state save path (layoutmode_settings.lua) stays harmless.
function Utils.CreateCollapsible(parent, title, contentHeight, buildFunc, sections, relayout)
    -- Layout Mode position-only rendering: suppress every collapsible except
    -- the one nested inside Utils.BuildPositionCollapsible. Set by the layout
    -- mode settings panel before invoking the shared renderer.
    if Utils._layoutModePositionOnly and not Utils._insidePositionCollapsible then
        return nil
    end
    Utils:RefreshAccentColor()
    local ACCENT_R, ACCENT_G, ACCENT_B = Utils.ACCENT_R, Utils.ACCENT_G, Utils.ACCENT_B
    local baseHeaderHeight = Utils.HEADER_HEIGHT
    -- Headerless mode: consume a one-shot flag set by renderer section filters for
    -- single-entry whitelists (the tile tab already names the section).
    local headerless = Utils._nextHeaderless == true
    Utils._nextHeaderless = false
    -- Borderless mode: skip cardBg + hairline borders for tile-tab rendering.
    -- Tile tabs already frame the content; the outer card is redundant there.
    local borderless = Utils._nextBorderless == true or Utils._useMinimalDrawerChrome == true
    Utils._nextBorderless = false
    local HEADER_HEIGHT = headerless and 0 or baseHeaderHeight
    local CARD_GAP = headerless and 0 or 6     -- space between header underline and card top
    local CARD_PAD = 8     -- vertical padding inside card
    -- Body keeps full section width to preserve widget layout math used by
    -- anchoring sliders and other builders that compute offsets from the
    -- body's left/right edges. The card bg spans the same width for a flush
    -- look; only vertical padding is applied.

    local section = CreateFrame("Frame", nil, parent)

    -- Auto-register this collapsible as a section on any V2 settings sub-page
    -- body that opted in via sectionNav. Walks up the parent chain because
    -- BuildFeatureTabPage wraps the renderer in an intermediate host frame.
    -- Headerless sections have no visible title to chip; skip them.
    -- _sectionsAuthoritative tells us BuildFeatureStackPage is in charge of
    -- registration (one chip per featureId titleRow); skip nested registers.
    --
    -- Also stamp the section title onto the GUI search context so that any
    -- pinnable widget bound inside buildFunc carries the right sectionName.
    -- Without this, bindings inherit a stale sectionName from whatever was
    -- last set, which surfaces as misrouted Jump-to-setting clicks on pins.
    if not headerless and type(title) == "string" and title ~= "" then
        local GUI = QUI and QUI.GUI
        if GUI and type(GUI.SetSearchSection) == "function" then
            GUI:SetSearchSection(title)
        end

        local target = parent
        while target do
            if type(target.RegisterSection) == "function" then
                if not target._sectionsAuthoritative then
                    target:RegisterSection(title, title, section)
                end
                break
            end
            if not target.GetParent then break end
            target = target:GetParent()
        end
    end

    if not headerless then
        -- Header: accent dot + title + 1px accent underline
        local dot = section:CreateTexture(nil, "OVERLAY")
        dot:SetSize(4, 4)
        dot:SetPoint("TOPLEFT", section, "TOPLEFT", 2, -((HEADER_HEIGHT - 4) / 2))
        dot:SetColorTexture(ACCENT_R, ACCENT_G, ACCENT_B, 1)

        local label = EnsureCJKFont(section:CreateFontString(nil, "OVERLAY", "GameFontNormal"))
        label:SetPoint("LEFT", dot, "RIGHT", 8, 0)
        label:SetTextColor(ACCENT_R, ACCENT_G, ACCENT_B, 1)
        label:SetText(title)

        local underline = section:CreateTexture(nil, "ARTWORK")
        underline:SetHeight(1)
        underline:SetPoint("TOPLEFT", section, "TOPLEFT", 0, -HEADER_HEIGHT)
        underline:SetPoint("TOPRIGHT", section, "TOPRIGHT", 0, -HEADER_HEIGHT)
        underline:SetColorTexture(ACCENT_R, ACCENT_G, ACCENT_B, 0.3)
    end

    if not borderless then
        -- Card surface: subtle bg fill + 1px border hairlines below header
        local cardBg = section:CreateTexture(nil, "BACKGROUND")
        cardBg:SetPoint("TOPLEFT", section, "TOPLEFT", 0, -(HEADER_HEIGHT + CARD_GAP))
        cardBg:SetPoint("BOTTOMRIGHT", section, "BOTTOMRIGHT", 0, 0)
        cardBg:SetColorTexture(1, 1, 1, 0.02)

        local function Hairline()
            local t = section:CreateTexture(nil, "BORDER")
            t:SetColorTexture(1, 1, 1, 0.06)
            return t
        end
        local cardTop = Hairline(); cardTop:SetHeight(1)
        cardTop:SetPoint("TOPLEFT", cardBg, "TOPLEFT", 0, 0)
        cardTop:SetPoint("TOPRIGHT", cardBg, "TOPRIGHT", 0, 0)
        local cardBot = Hairline(); cardBot:SetHeight(1)
        cardBot:SetPoint("BOTTOMLEFT", cardBg, "BOTTOMLEFT", 0, 0)
        cardBot:SetPoint("BOTTOMRIGHT", cardBg, "BOTTOMRIGHT", 0, 0)
        local cardLeft = Hairline(); cardLeft:SetWidth(1)
        cardLeft:SetPoint("TOPLEFT", cardBg, "TOPLEFT", 0, 0)
        cardLeft:SetPoint("BOTTOMLEFT", cardBg, "BOTTOMLEFT", 0, 0)
        local cardRight = Hairline(); cardRight:SetWidth(1)
        cardRight:SetPoint("TOPRIGHT", cardBg, "TOPRIGHT", 0, 0)
        cardRight:SetPoint("BOTTOMRIGHT", cardBg, "BOTTOMRIGHT", 0, 0)
    end

    -- Body: widgets get parented here. Full section width so existing widget
    -- positioning math (e.g. anchoring sliders anchored to body RIGHT) stays
    -- correct. Vertical CARD_PAD gives breathing room inside the card surface.
    local body = CreateFrame("Frame", nil, section)
    body:SetPoint("TOPLEFT", section, "TOPLEFT", 0, -(HEADER_HEIGHT + CARD_GAP + CARD_PAD))
    body:SetPoint("RIGHT", section, "RIGHT", 0, 0)
    body:SetHeight(contentHeight)
    body._logicalSection = section

    -- Public state
    section._expanded = true         -- V3: always visible. Kept true so legacy save-path is harmless.
    section._contentHeight = contentHeight
    section._body = body
    section._sectionTitle = title

    local function MeasureBodyContentHeight()
        local bodyTop = body.GetTop and body:GetTop()
        if not bodyTop then return nil end
        local maxOffset = 0
        local function Accumulate(region)
            if not region or not region.GetBottom then return end
            if region.IsShown and not region:IsShown() then return end
            local bottom = region:GetBottom()
            if bottom then
                maxOffset = math.max(maxOffset, bodyTop - bottom)
            end
        end
        local childCount = body.GetNumChildren and body:GetNumChildren() or 0
        for i = 1, childCount do Accumulate(select(i, body:GetChildren())) end
        local regionCount = body.GetNumRegions and body:GetNumRegions() or 0
        for i = 1, regionCount do Accumulate(select(i, body:GetRegions())) end
        if maxOffset <= 0 then return nil end
        return math.ceil(maxOffset + 4)
    end

    local function RefreshContentHeight()
        if type(body._contentHeight) == "number" and body._contentHeight > 0 then
            section._contentHeight = math.max(section._contentHeight or 0, body._contentHeight)
            body._contentHeight = nil
        end
        local measured = MeasureBodyContentHeight()
        if measured and measured > 0 then
            section._contentHeight = math.max(section._contentHeight or 0, measured)
        end
        local bh = section._contentHeight or contentHeight
        body:SetHeight(bh)
        section:SetHeight(HEADER_HEIGHT + CARD_GAP + (CARD_PAD * 2) + bh)
    end

    -- Exposed so BuildPositionCollapsible (and any other caller that mutates
    -- body height directly) can request a remeasure.
    section.RefreshContentHeight = RefreshContentHeight

    -- Legacy shim: always-expanded, but keep the signature so nothing crashes.
    section.SetExpanded = function(self, _expanded, skipRelayout)
        RefreshContentHeight()
        if not skipRelayout and relayout then relayout() end
    end

    buildFunc(body)
    RefreshContentHeight()
    C_Timer.After(0, function()
        if not section or not body then return end
        RefreshContentHeight()
        Utils.ApplyAlternatingRowBackgrounds(body)
        if relayout then relayout() end
    end)

    table.insert(sections, section)
    return section
end

---------------------------------------------------------------------------
-- SUPPRESSED PROVIDER LAYOUT (Layout Mode position-only)
---------------------------------------------------------------------------

-- Layout Mode renders a mover's shared-provider body in position-only mode so
-- right-click shows ONLY the Position controls + the "Open ... settings" link.
-- CreateCollapsible already self-suppresses when Utils._layoutModePositionOnly
-- is set, but the V3 body primitives (CreateAccentDotLabel +
-- CreateSettingsCardGroup, driven by each provider's local MakeLayout) do not,
-- so those bodies would render every section. Each provider's MakeLayout returns
-- THIS inert layout instead when the flag is on: it mirrors the MakeLayout
-- contract (headerAt / sectionAt / closeSection / placeCustom / sections /
-- relayoutSections) so the build body runs unchanged, but the section builders
-- are no-ops, custom blocks are hidden, and the appended Position collapsible +
-- settings link are the only things laid out. Any widgets the body still creates
-- against sectionAt().frame land on a hidden throwaway frame that ClearContent's
-- child sweep reclaims on the next drawer rebuild.
function Utils.MakeSuppressedProviderLayout(content)
    local sections = {}
    ---@type fun(...)
    local noop = function() end

    -- Hidden host for widgets the provider body creates against sectionAt().frame.
    -- Parented to content so ClearContent releases it (and its descendants).
    local trash = CreateFrame("Frame", nil, content)
    trash:Hide()
    trash:SetSize(1, 1)

    local stubSection = {
        frame = trash,
        AddRow = noop,
        Finalize = noop,
        GetRowCount = function() return 0 end,
    }

    local L = {
        sections = sections,
        headerAt = noop,
        sectionAt = function() return stubSection end,
        closeSection = noop,
        -- Custom blocks are created by the body before placeCustom is called;
        -- hide them so they do not float at the default anchor.
        placeCustom = function(frame)
            if frame and frame.Hide then frame:Hide() end
        end,
    }

    function L.relayoutSections()
        local PAD = Utils.PADDING or 0
        local cy = -10
        for _, s in ipairs(sections) do
            s:ClearAllPoints()
            s:SetPoint("TOPLEFT", content, "TOPLEFT", PAD, cy)
            s:SetPoint("RIGHT", content, "RIGHT", -PAD, 0)
            cy = cy - (s:GetHeight() or 0) - 4
        end
        content:SetHeight(math.abs(cy) + 16)
    end

    return L
end

---------------------------------------------------------------------------
-- BUILD POSITION COLLAPSIBLE
---------------------------------------------------------------------------

function Utils.BuildPositionCollapsible(content, frameKey, anchorOpts, sections, relayout)
    local AnchorOpts = ns.QUI_Anchoring_Options
    if not AnchorOpts or not AnchorOpts.BuildAnchoringSection then return end

    local PLACEHOLDER = 6 * Utils.FORM_ROW + 8
    local prevInside = Utils._insidePositionCollapsible
    Utils._insidePositionCollapsible = true
    local ok, err = xpcall(function()
        Utils.CreateCollapsible(content, ns.L["Position"], PLACEHOLDER, function(body)
            local opts = {}
            if anchorOpts then
                for k, v in pairs(anchorOpts) do opts[k] = v end
            end
            opts.noHeader = true
            local finalY = AnchorOpts:BuildAnchoringSection(body, frameKey, opts, -4)
            local realHeight = math.abs(finalY) + 4
            body:SetHeight(realHeight)
            local sec = body._logicalSection
            if sec then
                sec._contentHeight = realHeight
                if sec.RefreshContentHeight then
                    sec:RefreshContentHeight()
                end
            end
        end, sections, relayout)
    end, function(msg) return msg end)
    Utils._insidePositionCollapsible = prevInside
    if not ok and geterrorhandler then
        geterrorhandler()(err)
    end
end

---------------------------------------------------------------------------
-- OPEN FULL SETTINGS LINK
---------------------------------------------------------------------------

local function ResolveTileDisplayName(tileId)
    local GUI = QUI and QUI.GUI
    local frame = GUI and GUI.MainFrame
    if frame and frame._tiles then
        for _, tile in ipairs(frame._tiles) do
            if tile.id == tileId and tile.config and tile.config.name then
                return tile.config.name
            end
        end
    end
    return tileId
end

--[[
    Utils.BuildOpenFullSettingsLink(content, providerKey, sections, relayout)

    Renders a clickable "Open [Tile] settings" link row as the last section
    of a Layout Mode provider panel. Clicking closes Layout Mode, opens /qui,
    and navigates V2 to the mapped tile + sub-page. No-op for providers
    without a V2 mapping.
]]
function Utils.BuildOpenFullSettingsLink(content, providerKey, sections, relayout)
    local Settings = ns.Settings
    local Nav = Settings and Settings.Nav
    local Registry = Settings and Settings.Registry
    local feature = Registry and type(Registry.GetFeature) == "function"
        and Registry:GetFeature(providerKey) or nil
    local route = Nav and type(Nav.GetRoute) == "function"
        and Nav:GetRoute(providerKey) or nil
    if not route and Nav and type(Nav.GetLookupTarget) == "function" then
        route, feature = Nav:GetLookupTarget(providerKey)
    elseif not route and Nav and type(Nav.GetRouteByLookupKey) == "function" then
        route = Nav:GetRouteByLookupKey(providerKey)
    end
    if not feature and Registry and type(Registry.GetFeatureByLookupKey) == "function" then
        feature = Registry:GetFeatureByLookupKey(providerKey)
    end
    if not route then
        route = Utils.PROVIDER_TO_V2 and Utils.PROVIDER_TO_V2[providerKey]
    end
    if not route then return end

    local GUI = QUI and QUI.GUI
    if not GUI then return end

    local ROW_HEIGHT = 26
    local row = CreateFrame("Button", nil, content)
    row:SetHeight(ROW_HEIGHT)
    row._contentHeight = ROW_HEIGHT
    row._expanded = true
    table.insert(sections, row)

    local divider = row:CreateTexture(nil, "ARTWORK")
    divider:SetPoint("TOPLEFT", row, "TOPLEFT", 8, 0)
    divider:SetPoint("TOPRIGHT", row, "TOPRIGHT", -8, 0)
    divider:SetHeight(1)
    divider:SetColorTexture(1, 1, 1, 0.06)

    local label = EnsureCJKFont(row:CreateFontString(nil, "OVERLAY", "GameFontNormal"))
    label:SetPoint("LEFT", row, "LEFT", 12, -2)
    local tileName = ResolveTileDisplayName(route.tileId)
    label:SetText(ns.L["Open %s settings"]:format(tileName))
    local accent = GUI.Colors and GUI.Colors.accent or { 0.2, 0.83, 0.6, 1 }
    row.label = label

    local chevron = UIKit and UIKit.CreateChevronCaret and UIKit.CreateChevronCaret(row, {
        point = "LEFT",
        relativeTo = label,
        relativePoint = "RIGHT",
        xPixels = 6,
        yPixels = -1,
        sizePixels = 10,
        lineWidthPixels = 6,
        lineHeightPixels = 1,
        expanded = false,
        collapsedDirection = "right",
        r = accent[1],
        g = accent[2],
        b = accent[3],
        a = 1,
    }) or EnsureCJKFont(row:CreateFontString(nil, "OVERLAY", "GameFontNormal"))
    if not (UIKit and UIKit.CreateChevronCaret) then
        chevron:SetPoint("LEFT", label, "RIGHT", 6, 0)
        chevron:SetText(">")
    end
    row.chevron = chevron

    local function SetLinkColor(r, g, b, a)
        label:SetTextColor(r, g, b, a or 1)
        if UIKit and UIKit.SetChevronCaretColor and chevron.GetObjectType and chevron:GetObjectType() == "Frame" then
            UIKit.SetChevronCaretColor(chevron, r, g, b, a or 1)
        elseif chevron.SetTextColor then
            chevron:SetTextColor(r, g, b, a or 1)
        end
    end

    SetLinkColor(accent[1], accent[2], accent[3], 1)
    row:SetScript("OnEnter", function() SetLinkColor(1, 1, 1, 1) end)
    row:SetScript("OnLeave", function() SetLinkColor(accent[1], accent[2], accent[3], 1) end)
    row:SetScript("OnClick", function()
        if feature and type(feature.onNavigate) == "function" then
            pcall(feature.onNavigate, providerKey, route, {
                source = "layoutmode",
            })
        end
        if _G.QUI_ToggleLayoutMode then
            pcall(_G.QUI_ToggleLayoutMode)
        end
        if QUI and QUI.SlashCommandOpen then
            pcall(QUI.SlashCommandOpen, QUI, "")
        elseif GUI and GUI.Toggle then
            pcall(GUI.Toggle, GUI)
        end
        local frame = GUI and GUI.MainFrame
        if frame and GUI.FindV2TileByID and GUI.SelectFeatureTile then
            local _, idx = GUI:FindV2TileByID(frame, route.tileId)
            if idx then
                GUI:SelectFeatureTile(frame, idx, { subPageIndex = route.subPageIndex })
            end
        end
    end)

    if relayout then relayout() end
end

---------------------------------------------------------------------------
-- WIDGET ROW HELPER (delegates to Helpers)
---------------------------------------------------------------------------

Utils.PlaceRow = Helpers.PlaceRow
Utils.EnsureDefaults = Helpers.EnsureDefaults

---------------------------------------------------------------------------
-- FRAME SIZE SECTION
-- Width/Height sliders bound through a proxy table. Used by Layout Mode
-- mover panels for resizable frames (damage meter windows, ChatFrame1).
-- opts.getSize() must return (width, height); opts.setSize(w, h) applies +
-- persists. Caller controls clamps and persistence path.
---------------------------------------------------------------------------
function Utils.BuildSizeCollapsible(content, opts, sections, relayout)
    local GUI = QUI and QUI.GUI
    if not GUI or type(opts) ~= "table"
        or type(opts.getSize) ~= "function"
        or type(opts.setSize) ~= "function" then
        return
    end

    local minW = opts.minW or 100
    local maxW = opts.maxW or 1400
    local minH = opts.minH or 100
    local maxH = opts.maxH or 900
    local widthDescription  = opts.widthDescription  or ns.L["Frame width in pixels."]
    local heightDescription = opts.heightDescription or ns.L["Frame height in pixels."]

    local function ReadSize()
        local w, h = opts.getSize()
        return tonumber(w) or 0, tonumber(h) or 0
    end

    local proxy = setmetatable({}, {
        __index = function(_, k)
            local w, h = ReadSize()
            if k == "width"  then return math.floor(w + 0.5) end
            if k == "height" then return math.floor(h + 0.5) end
            return 0
        end,
        __newindex = function(_, k, v)
            if type(v) ~= "number" then return end
            local cw, ch = ReadSize()
            if k == "width"  then opts.setSize(v, ch) end
            if k == "height" then opts.setSize(cw, v) end
        end,
    })

    local PLACEHOLDER = 2 * Utils.FORM_ROW + 8
    local widthSlider, heightSlider
    Utils.CreateCollapsible(content, ns.L["Frame Size"], PLACEHOLDER, function(body)
        local sy = -4
        widthSlider  = GUI:CreateFormSlider(body, ns.L["Width"],  minW, maxW, 1, "width",  proxy, nil, nil, { description = widthDescription })
        sy = Utils.PlaceRow(widthSlider, body, sy)
        heightSlider = GUI:CreateFormSlider(body, ns.L["Height"], minH, maxH, 1, "height", proxy, nil, nil, { description = heightDescription })
        Utils.PlaceRow(heightSlider, body, sy)
    end, sections, relayout)

    -- Corner-drag resize grips change the live frame size directly, but these
    -- sliders read the live size only at build time — so without a re-sync the
    -- panel keeps showing the pre-drag value. Register a refresher the grips
    -- call on mouse-up. Only one mover drawer is open at a time, so a single
    -- module-level slot is sufficient; the most recently built size section
    -- wins, which is exactly the element whose grips can fire.
    Utils._activeSizeSliderRefresh = function()
        if widthSlider and widthSlider.SetValue then widthSlider:SetValue(proxy.width) end
        if heightSlider and heightSlider.SetValue then heightSlider:SetValue(proxy.height) end
    end
end

-- Called by resize grips (ChatFrame1, damage meter windows) after a corner
-- drag so the Layout Mode Frame Size sliders re-read the live dimensions.
-- Safe no-op when no size section is currently built.
function Utils.RefreshActiveSizeSliders()
    local fn = Utils._activeSizeSliderRefresh
    if type(fn) ~= "function" then return end
    local ok, err = pcall(fn)
    if not ok and geterrorhandler then geterrorhandler()(err) end
end

---------------------------------------------------------------------------
-- BACKDROP & BORDER SECTION (shared by combatTimer, brezCounter)
---------------------------------------------------------------------------

function Utils.BuildBackdropBorderSection(content, db, sections, relayout, Refresh)
    local GUI = QUI and QUI.GUI
    if not GUI then return end

    Utils.CreateCollapsible(content, ns.L["Backdrop & Border"], 7 * Utils.FORM_ROW + 8, function(body)
        local sy = -4
        sy = Utils.PlaceRow(GUI:CreateFormCheckbox(body, ns.L["Show Backdrop"], "showBackdrop", db, Refresh,
            { description = "Draw a semi-transparent backdrop behind this frame so it's easier to see against busy scenes." }), body, sy)
        sy = Utils.PlaceRow(GUI:CreateFormColorPicker(body, ns.L["Backdrop Color"], "backdropColor", db, Refresh, nil,
            { description = ns.L["Color and opacity used for the backdrop when Show Backdrop is on."] }), body, sy)
        sy = Utils.PlaceRow(GUI:CreateFormCheckbox(body, "Hide Border", "hideBorder", db, Refresh,
            { description = "Hide the border outline entirely. Overrides the Border Size, Class Color, Accent Color, and Border Color controls below." }), body, sy)
        sy = Utils.PlaceRow(GUI:CreateFormSlider(body, "Border Size", 1, 5, 0.5, "borderSize", db, Refresh, nil,
            { description = "Border thickness in pixels. Ignored while Hide Border is on." }), body, sy)
        sy = Utils.PlaceRow(GUI:CreateFormCheckbox(body, "Class Color Border", "useClassColorBorder", db, Refresh,
            { description = "Tint the border with your class color. Takes precedence over Accent Color Border and the Border Color swatch." }), body, sy)
        sy = Utils.PlaceRow(GUI:CreateFormCheckbox(body, "Accent Color Border", "useAccentColorBorder", db, Refresh,
            { description = "Tint the border with the QUI accent color. Ignored if Class Color Border is on." }), body, sy)
        Utils.PlaceRow(GUI:CreateFormColorPicker(body, ns.L["Border Color"], "borderColor", db, Refresh, nil,
            { description = "Fallback border color used when neither Class Color nor Accent Color is on." }), body, sy)
    end, sections, relayout)
end

do
    local Settings = ns.Settings
    local Registry = Settings and Settings.Registry
    local Schema = Settings and Settings.Schema
    local RenderAdapters = Settings and Settings.RenderAdapters

    if Registry and Schema and RenderAdapters
        and type(Registry.RegisterFeature) == "function"
        and type(Schema.Feature) == "function" then
        for _, frameKey in ipairs({
            "leaveVehicle",
            "equipmentDurability",
            "topCenterWidgets",
            "belowMinimapWidgets",
            "rangeCheck",
            "lootFrame",
            "lootRollAnchor",
            "alertAnchor",
            "toastAnchor",
            "bnetToastAnchor",
            "powerBarAlt",
        }) do
            local key = frameKey
            Registry:RegisterFeature(Schema.Feature({
                id = key,
                moverKey = key,
                render = {
                    layout = function(host, options)
                        return RenderAdapters.RenderPositionOnly(host, options and options.providerKey or key)
                    end,
                },
            }))
        end
    end
end
