--[[
    QUI Options — 3rd Party Addons Anchoring
    Migrated to V3 body pattern. Each anchor config (BigWigs Normal /
    Emphasized, Danders Party/Raid/Pinned, AbilityTimeline Timeline/BigIcon)
    renders as an accent-dot section + card group with paired rows.
]]

local ADDON_NAME, ns = ...
local QUI = QUI
local GUI = QUI.GUI
local C = GUI.Colors
local Shared = ns.QUI_Options
local Settings = ns.Settings
local Registry = Settings and Settings.Registry
local Schema = Settings and Settings.Schema
local RenderAdapters = Settings and Settings.RenderAdapters

local PADDING = Shared.PADDING
local GetCore = ns.Helpers.GetCore
local SECTION_GAP = 14

local ANCHOR_POINTS = {
    {value = "TOPLEFT",     text = "Top Left"},
    {value = "TOP",         text = "Top"},
    {value = "TOPRIGHT",    text = "Top Right"},
    {value = "LEFT",        text = "Left"},
    {value = "CENTER",      text = "Center"},
    {value = "RIGHT",       text = "Right"},
    {value = "BOTTOMLEFT",  text = "Bottom Left"},
    {value = "BOTTOM",      text = "Bottom"},
    {value = "BOTTOMRIGHT", text = "Bottom Right"},
}

local THIRD_PARTY_LAYOUT_KEYS = {
    dandersParty = { containerKey = "party", label = "Party Frames" },
    dandersRaid = { containerKey = "raid", label = "Raid Frames" },
    dandersPinned1 = { containerKey = "pinned1", label = "Pinned Set 1" },
    dandersPinned2 = { containerKey = "pinned2", label = "Pinned Set 2" },
}

local function FilterAnchorOptions(anchorOptions, excludedValue)
    if not anchorOptions or not excludedValue then
        return anchorOptions
    end
    local filtered = {}
    for _, option in ipairs(anchorOptions) do
        if option.value == nil or option.value ~= excludedValue then
            table.insert(filtered, option)
        end
    end
    return filtered
end

-- Emit one anchor-config block (accent-dot label + card) inside `tabContent`
-- starting at `y`. Returns the new y after the block + SECTION_GAP.
local function BuildAnchorBlock(tabContent, label, cfg, y, anchorOptions, onChange)
    if not cfg then return y end

    Shared.CreateAccentDotLabel(tabContent, label, y); y = y - 22

    local card = Shared.CreateSettingsCardGroup(tabContent, y)

    -- Enable — full-width (the primary gate).
    local enableW = GUI:CreateFormCheckbox(card.frame, nil, "enabled", cfg, onChange,
        { description = "Let QUI drive the position of " .. label .. ". Turn off to leave the addon's own anchor behavior intact." })
    card.AddRow(Shared.BuildSettingRow(card.frame, "Enable Anchoring", enableW))

    -- Anchor To — full-width dropdown; labels can be long (other tile IDs).
    local anchorW = GUI:CreateFormDropdown(card.frame, nil, anchorOptions, "anchorTo", cfg, onChange,
        { description = "Which QUI element " .. label .. " should attach to. Choose the HUD piece you want this frame to track." })
    card.AddRow(Shared.BuildSettingRow(card.frame, "Anchor To", anchorW))

    -- Container Point + Target Point — paired 9-point dropdowns.
    local srcW = GUI:CreateFormDropdown(card.frame, nil, ANCHOR_POINTS, "sourcePoint", cfg, onChange,
        { description = "Which corner or edge of " .. label .. " is used as its anchor point." })
    local dstW = GUI:CreateFormDropdown(card.frame, nil, ANCHOR_POINTS, "targetPoint", cfg, onChange,
        { description = "Which corner or edge of the target QUI element the container point attaches to." })
    card.AddRow(
        Shared.BuildSettingRow(card.frame, "Container Point", srcW),
        Shared.BuildSettingRow(card.frame, "Target Point", dstW)
    )

    -- X / Y offset — paired sliders.
    local xW = GUI:CreateFormSlider(card.frame, nil, -200, 200, 1, "offsetX", cfg, onChange, nil,
        { description = "Horizontal pixel offset from the target anchor point." })
    local yW = GUI:CreateFormSlider(card.frame, nil, -200, 200, 1, "offsetY", cfg, onChange, nil,
        { description = "Vertical pixel offset from the target anchor point." })
    card.AddRow(
        Shared.BuildSettingRow(card.frame, "X Offset", xW),
        Shared.BuildSettingRow(card.frame, "Y Offset", yW)
    )

    card.Finalize()
    return y - card.frame:GetHeight() - SECTION_GAP
end

local function BuildThirdPartyContainerLayoutSettings(host, lookupKey)
    local entry = type(lookupKey) == "string" and THIRD_PARTY_LAYOUT_KEYS[lookupKey] or nil
    local U = ns.QUI_LayoutMode_Utils
    local DF = ns.QUI_DandersFrames
    if not entry or not host or not U or not DF or not DF.IsAvailable or not DF:IsAvailable() then
        return 80
    end

    local core = GetCore()
    local profile = core and core.db and core.db.profile
    local db = profile and profile.dandersFrames
    local cfg = db and db[entry.containerKey]
    local GUI = QUI and QUI.GUI
    if not cfg or not GUI then
        return 80
    end

    local sections = {}
    local function relayout()
        U.StandardRelayout(host, sections)
    end

    local function Refresh()
        DF:ApplyPosition(entry.containerKey)
        if _G.QUI_LayoutModeSyncHandle then
            _G.QUI_LayoutModeSyncHandle(lookupKey)
        end
    end

    local P = U.PlaceRow
    local FORM_ROW = U.FORM_ROW
    local anchorOptions = DF:BuildAnchorOptions()

    U.CreateCollapsible(host, "Anchoring (drag the mover to place)", 6 * FORM_ROW + 8, function(body)
        local sy = -4
        sy = P(GUI:CreateFormCheckbox(body, "Enable", "enabled", cfg, Refresh,
            { description = "Enable QUI-managed anchoring for this container. While off, the container keeps its existing position." }), body, sy)
        sy = P(GUI:CreateFormDropdown(body, "Anchor To", anchorOptions, "anchorTo", cfg, Refresh,
            { description = "Which QUI element this container attaches to." }), body, sy)
        sy = P(GUI:CreateFormDropdown(body, "Container Point", ANCHOR_POINTS, "sourcePoint", cfg, Refresh,
            { description = "Which point on this container is used as the attach point." }), body, sy)
        sy = P(GUI:CreateFormDropdown(body, "Target Point", ANCHOR_POINTS, "targetPoint", cfg, Refresh,
            { description = "Which point on the target frame this container attaches to." }), body, sy)
        sy = P(GUI:CreateFormSlider(body, "X Offset", -400, 400, 1, "offsetX", cfg, Refresh, nil,
            { description = "Horizontal pixel offset between container point and target point." }), body, sy)
        P(GUI:CreateFormSlider(body, "Y Offset", -400, 400, 1, "offsetY", cfg, Refresh, nil,
            { description = "Vertical pixel offset between container point and target point." }), body, sy)
    end, sections, relayout)

    U.BuildOpenFullSettingsLink(host, lookupKey, sections, relayout)
    relayout()
    return host:GetHeight()
end

-- Renders a single integration's section: top-level accent-dot label
-- with the addon name, availability guard (muted label if the target
-- addon isn't installed), intro paragraph, then one BuildAnchorBlock
-- per configured key.
local function BuildIntegrationSection(tabContent, y, opts)
    local PAD = PADDING

    Shared.CreateAccentDotLabel(tabContent, opts.name, y); y = y - 22

    if not opts.isAvailable() then
        local info = GUI:CreateLabel(tabContent, opts.unavailableMessage, 11, C.textMuted)
        info:SetPoint("TOPLEFT", tabContent, "TOPLEFT", PAD, y)
        info:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        info:SetJustifyH("LEFT")
        return y - 26
    end

    local core = GetCore()
    local db = core and core.db and core.db.profile and core.db.profile[opts.dbKey]
    if not db then
        local errorLabel = GUI:CreateLabel(tabContent, opts.name .. " anchor database not loaded. Please reload UI.", 12, {1, 0.3, 0.3, 1})
        errorLabel:SetPoint("TOPLEFT", PAD, y)
        return y - 24
    end

    if opts.description then
        local desc = GUI:CreateLabel(tabContent, opts.description, 11, C.textMuted)
        desc:SetPoint("TOPLEFT", tabContent, "TOPLEFT", PAD, y)
        desc:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        desc:SetJustifyH("LEFT")
        desc:SetWordWrap(true)
        y = y - 32
    end

    local anchorOptions = opts.buildAnchorOptions()
    for _, entry in ipairs(opts.keys) do
        local cfg = db[entry.key]
        local entryAnchorOptions = opts.filterExcludeKey and FilterAnchorOptions(anchorOptions, opts.filterExcludeKey[entry.key]) or anchorOptions
        y = BuildAnchorBlock(
            tabContent,
            opts.name .. " \226\128\148 " .. entry.label,  -- "BigWigs — Normal Bars"
            cfg, y, entryAnchorOptions,
            function() opts.applyPosition(entry.key) end
        )
    end

    return y
end

local function BuildThirdPartyTab(tabContent)
    GUI:SetSearchContext({tabIndex = 3, tabName = "Frame Positioning", subTabIndex = 7, subTabName = "3rd Party Addons"})

    local y = -10
    local PAD = PADDING

    local intro = GUI:CreateLabel(tabContent,
        "Configure QUI-driven anchoring integrations for supported external addons.",
        11, C.textMuted)
    intro:SetPoint("TOPLEFT", tabContent, "TOPLEFT", PAD, y)
    intro:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
    intro:SetJustifyH("LEFT")
    intro:SetWordWrap(true)
    y = y - 30

    -- BigWigs
    y = BuildIntegrationSection(tabContent, y, {
        name    = "BigWigs",
        dbKey   = "bigWigs",
        keys    = {
            {key = "normal",     label = "Normal Bars"},
            {key = "emphasized", label = "Emphasized Bars"},
        },
        isAvailable          = function() return ns.QUI_BigWigs and ns.QUI_BigWigs:IsAvailable() end,
        unavailableMessage   = "BigWigs not detected. Install and enable BigWigs to use these anchors.",
        description          = "Anchor BigWigs bar groups to QUI elements. This writes to BigWigs Bars custom anchor points.",
        buildAnchorOptions   = function() return ns.QUI_BigWigs:BuildAnchorOptions() end,
        applyPosition        = function(k) ns.QUI_BigWigs:ApplyPosition(k) end,
    })

    -- DandersFrames
    y = BuildIntegrationSection(tabContent, y, {
        name    = "DandersFrames",
        dbKey   = "dandersFrames",
        keys    = {
            {key = "party",   label = "Party Frames"},
            {key = "raid",    label = "Raid Frames"},
            {key = "pinned1", label = "Pinned Set 1"},
            {key = "pinned2", label = "Pinned Set 2"},
        },
        isAvailable        = function() return ns.QUI_DandersFrames and ns.QUI_DandersFrames:IsAvailable() end,
        unavailableMessage = "DandersFrames not detected. Install and enable DandersFrames to use these anchors.",
        description        = "Anchor DandersFrames containers to QUI elements. When enabled, QUI controls placement; move them with QUI Layout Mode rather than DandersFrames' own unlock.",
        buildAnchorOptions = function() return ns.QUI_DandersFrames:BuildAnchorOptions() end,
        applyPosition      = function(k) ns.QUI_DandersFrames:ApplyPosition(k) end,
    })

    -- AbilityTimeline — each key can't anchor to its own target, so the
    -- anchor option list is filtered per key.
    y = BuildIntegrationSection(tabContent, y, {
        name    = "AbilityTimeline",
        dbKey   = "abilityTimeline",
        keys    = {
            {key = "timeline", label = "Timeline Frame"},
            {key = "bigIcon",  label = "Big Icon Frame"},
        },
        filterExcludeKey = {
            timeline = "abilityTimelineTimeline",
            bigIcon  = "abilityTimelineBigIcon",
        },
        isAvailable        = function() return ns.QUI_AbilityTimeline and ns.QUI_AbilityTimeline:IsAvailable() end,
        unavailableMessage = "AbilityTimeline not detected. Install and enable AbilityTimeline to use these anchors.",
        description        = "Anchor AbilityTimeline frames to QUI elements. This controls the timeline and big icon frame positions.",
        buildAnchorOptions = function() return ns.QUI_AbilityTimeline:BuildAnchorOptions() end,
        applyPosition      = function(k) ns.QUI_AbilityTimeline:ApplyPosition(k) end,
    })

    tabContent:SetHeight(math.abs(y) + 30)
end

ns.QUI_ThirdPartyAnchoringOptions = {
    BuildThirdPartyTab = BuildThirdPartyTab,
    BuildLayoutContainerSettings = BuildThirdPartyContainerLayoutSettings,
}

if Registry and Schema and RenderAdapters
    and type(Registry.RegisterFeature) == "function"
    and type(Schema.Feature) == "function"
    and type(Schema.Section) == "function" then
    Registry:RegisterFeature(Schema.Feature({
        id = "thirdPartyAnchoring",
        moverKey = "thirdPartyAnchoring",
        lookupKeys = { "dandersParty", "dandersRaid", "dandersPinned1", "dandersPinned2" },
        category = "global",
        nav = { tileId = "global", subPageIndex = 4 },
        sections = {
            Schema.Section({
                id = "settings",
                kind = "page",
                minHeight = 80,
                build = BuildThirdPartyTab,
            }),
        },
        render = {
            layout = function(host, options)
                return BuildThirdPartyContainerLayoutSettings(
                    host,
                    options and options.providerKey or "thirdPartyAnchoring"
                )
            end,
        },
    }))
end
