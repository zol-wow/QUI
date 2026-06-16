local ADDON_NAME, ns = ...
local QUI = QUI
local GUI = QUI.GUI
local Opts = ns.QUI_Options
local ACTION_BARS_SEARCH_TILE_ID = "action_bars"
local ACTION_BARS_BUFF_DEBUFF_FEATURE_ID = "actionBarsBuffDebuff"
local ACTION_BARS_BUFF_DEBUFF_SUB_PAGE_INDEX = 2

local GROW_DIRECTION_OPTIONS = {
    { value = "right_down", text = ns.L["Right then Down"] },
    { value = "left_down",  text = ns.L["Left then Down"] },
    { value = "right_up",   text = ns.L["Right then Up"] },
    { value = "left_up",    text = ns.L["Left then Up"] },
}

-- Sort rule keys mirror SORT_TRANSLATIONS in modules/actionbars/buffborders.lua, which
-- maps each key to a UnitAuraSortRule enum (for GetUnitAuras) AND the legacy
-- SecureAuraHeader sortMethod string. Both must change together — single
-- source of truth lives in buffborders.lua's translation table.
local SORT_OPTIONS = {
    { value = "INDEX",         text = ns.L["API order (raw slot)"] },
    { value = "DEFAULT",       text = ns.L["Default (player-applied first)"] },
    { value = "EXPIRY",        text = ns.L["Expiration (player-first, soonest)"] },
    { value = "EXPIRY_ONLY",   text = ns.L["Expiration only (soonest)"] },
    { value = "NAME",          text = ns.L["Name (player-first, A\226\134\146Z)"] },
    { value = "NAME_ONLY",     text = ns.L["Name only (A\226\134\146Z)"] },
    { value = "BIG_DEFENSIVE", text = ns.L["Big Defensive priority"] },
}

local function RefreshBuffBorders()
    if Opts and Opts.RefreshBuffBorders then
        Opts.RefreshBuffBorders()
        return
    end

    if _G.QUI_RefreshBuffBorders then
        _G.QUI_RefreshBuffBorders()
    end
end

local function GetBuffBordersSettings()
    local db = Opts and Opts.GetDB and Opts.GetDB()
    if not db then
        return nil
    end

    db.buffBorders = db.buffBorders or {}
    return db.buffBorders
end

local function GetGrowDirection(settings, prefix)
    local growLeft = settings[prefix .. "GrowLeft"] == true
    local growUp = settings[prefix .. "GrowUp"] == true

    if growLeft and growUp then
        return "left_up"
    elseif growLeft then
        return "left_down"
    elseif growUp then
        return "right_up"
    end

    return "right_down"
end

local function SetGrowDirection(settings, prefix, value)
    if type(settings) ~= "table" then
        return
    end

    settings[prefix .. "GrowLeft"] = value == "left_down" or value == "left_up"
    settings[prefix .. "GrowUp"] = value == "right_up" or value == "left_up"
end

local function CreateGrowDirectionProxy(settings, prefix)
    return setmetatable({}, {
        __index = function(_, key)
            if key == "growDirection" then
                return GetGrowDirection(settings, prefix)
            end
        end,
        __newindex = function(_, key, value)
            if key == "growDirection" then
                SetGrowDirection(settings, prefix, value)
            end
        end,
    })
end

local function BuildSharedSection(tabContent, headerAt, sectionAt, closeSection, settings)
    headerAt(ns.L["Shared"])
    local card = sectionAt()

    local showStacks = GUI:CreateFormToggle(card.frame, nil, "showStacks", settings, RefreshBuffBorders,
        { description = ns.L["Show stack counts on aura icons when the buff or debuff has multiple stacks."] })
    local hideSwipe = GUI:CreateFormToggle(card.frame, nil, "hideSwipe", settings, RefreshBuffBorders,
        { description = ns.L["Hide the cooldown swipe animation that fills the icon as time expires."] })
    card.AddRow(
        Opts.BuildSettingRow(card.frame, ns.L["Show Stack Counts"], showStacks),
        Opts.BuildSettingRow(card.frame, ns.L["Hide Duration Swipe"], hideSwipe)
    )

    local borderSize = GUI:CreateFormSlider(card.frame, nil, 1, 6, 1, "borderSize", settings, RefreshBuffBorders, nil,
        { description = ns.L["Thickness of the border drawn around buff and debuff icons."] })
    local fontSize = GUI:CreateFormSlider(card.frame, nil, 8, 24, 1, "fontSize", settings, RefreshBuffBorders, nil,
        { description = ns.L["Font size used for both stack text and countdown text."] })
    card.AddRow(
        Opts.BuildSettingRow(card.frame, ns.L["Border Size"], borderSize),
        Opts.BuildSettingRow(card.frame, ns.L["Font Size"], fontSize)
    )

    local fadeOutAlpha = GUI:CreateFormSlider(card.frame, nil, 0, 1, 0.05, "fadeOutAlpha", settings, RefreshBuffBorders, nil,
        { description = ns.L["Opacity used when a faded buff or debuff frame is not being hovered."] })
    card.AddRow(Opts.BuildSettingRow(card.frame, ns.L["Fade Out Opacity"], fadeOutAlpha))

    closeSection(card)
end

local function BuildAuraSection(tabContent, headerAt, sectionAt, closeSection, settings, spec)
    headerAt(spec.title)

    local general = sectionAt()
    local enabled = GUI:CreateFormToggle(general.frame, nil, spec.enabledKey, settings, RefreshBuffBorders,
        { description = spec.enableDescription })
    local showBorders = GUI:CreateFormToggle(general.frame, nil, spec.showBordersKey, settings, RefreshBuffBorders,
        { description = spec.borderDescription })
    general.AddRow(
        Opts.BuildSettingRow(general.frame, ns.L["Enabled"], enabled),
        Opts.BuildSettingRow(general.frame, ns.L["Show Borders"], showBorders)
    )

    local hideFrame = GUI:CreateFormToggle(general.frame, nil, spec.hideFrameKey, settings, RefreshBuffBorders,
        { description = spec.hideDescription })
    local fadeFrame = GUI:CreateFormToggle(general.frame, nil, spec.fadeKey, settings, RefreshBuffBorders,
        { description = spec.fadeDescription })
    general.AddRow(
        Opts.BuildSettingRow(general.frame, ns.L["Hide Frame"], hideFrame),
        Opts.BuildSettingRow(general.frame, ns.L["Fade On Mouseover"], fadeFrame)
    )
    closeSection(general)

    local layout = sectionAt()
    local iconSize = GUI:CreateFormSlider(layout.frame, nil, 0, 64, 1, spec.iconSizeKey, settings, RefreshBuffBorders, nil,
        { description = ns.L["Pixel size of each icon. Set to 0 to use the default size."] })
    local iconsPerRow = GUI:CreateFormSlider(layout.frame, nil, 0, 20, 1, spec.iconsPerRowKey, settings, RefreshBuffBorders, nil,
        { description = ns.L["Maximum number of icons before wrapping to a new row. Set to 0 to use the default row length."] })
    layout.AddRow(
        Opts.BuildSettingRow(layout.frame, ns.L["Icon Size"], iconSize),
        Opts.BuildSettingRow(layout.frame, ns.L["Icons Per Row"], iconsPerRow)
    )

    local iconSpacing = GUI:CreateFormSlider(layout.frame, nil, 0, 12, 1, spec.iconSpacingKey, settings, RefreshBuffBorders, nil,
        { description = ns.L["Horizontal gap between icons in the same row."] })
    local rowSpacing = GUI:CreateFormSlider(layout.frame, nil, 0, 20, 1, spec.rowSpacingKey, settings, RefreshBuffBorders, nil,
        { description = ns.L["Vertical gap between wrapped rows of icons."] })
    layout.AddRow(
        Opts.BuildSettingRow(layout.frame, ns.L["Icon Spacing"], iconSpacing),
        Opts.BuildSettingRow(layout.frame, ns.L["Row Spacing"], rowSpacing)
    )

    local growProxy = CreateGrowDirectionProxy(settings, spec.prefix)
    local growDirection = GUI:CreateFormDropdown(layout.frame, nil, GROW_DIRECTION_OPTIONS, "growDirection", growProxy, RefreshBuffBorders,
        { description = ns.L["Choose which direction new icons are added from the anchor corner."] })
    local invertSwipe = GUI:CreateFormToggle(layout.frame, nil, spec.invertSwipeKey, settings, RefreshBuffBorders,
        { description = ns.L["Invert the swipe shading so the cooldown fill darkens in the opposite direction."] })
    layout.AddRow(
        Opts.BuildSettingRow(layout.frame, ns.L["Grow Direction"], growDirection),
        Opts.BuildSettingRow(layout.frame, ns.L["Invert Swipe Darkening"], invertSwipe)
    )
    closeSection(layout)

    local text = sectionAt()
    local stackAnchor = GUI:CreateFormDropdown(text.frame, nil, Opts.NINE_POINT_ANCHOR_OPTIONS, spec.stackAnchorKey, settings, RefreshBuffBorders,
        { description = ns.L["Which point of the icon the stack count text is anchored to."] })
    local stackX = GUI:CreateFormSlider(text.frame, nil, -20, 20, 1, spec.stackOffsetXKey, settings, RefreshBuffBorders, nil,
        { description = ns.L["Horizontal offset for the stack count text."] })
    text.AddRow(
        Opts.BuildSettingRow(text.frame, ns.L["Stack Anchor"], stackAnchor),
        Opts.BuildSettingRow(text.frame, ns.L["Stack X Offset"], stackX)
    )

    local stackY = GUI:CreateFormSlider(text.frame, nil, -20, 20, 1, spec.stackOffsetYKey, settings, RefreshBuffBorders, nil,
        { description = ns.L["Vertical offset for the stack count text."] })
    local durationAnchor = GUI:CreateFormDropdown(text.frame, nil, Opts.NINE_POINT_ANCHOR_OPTIONS, spec.durationAnchorKey, settings, RefreshBuffBorders,
        { description = ns.L["Which point of the icon the countdown text is anchored to."] })
    text.AddRow(
        Opts.BuildSettingRow(text.frame, ns.L["Stack Y Offset"], stackY),
        Opts.BuildSettingRow(text.frame, ns.L["Duration Anchor"], durationAnchor)
    )

    local durationX = GUI:CreateFormSlider(text.frame, nil, -20, 20, 1, spec.durationOffsetXKey, settings, RefreshBuffBorders, nil,
        { description = ns.L["Horizontal offset for the countdown text."] })
    local durationY = GUI:CreateFormSlider(text.frame, nil, -20, 20, 1, spec.durationOffsetYKey, settings, RefreshBuffBorders, nil,
        { description = ns.L["Vertical offset for the countdown text."] })
    text.AddRow(
        Opts.BuildSettingRow(text.frame, ns.L["Duration X Offset"], durationX),
        Opts.BuildSettingRow(text.frame, ns.L["Duration Y Offset"], durationY)
    )
    closeSection(text)

    -- Filters section. spec.filters is a list of { dbKey, label, description };
    -- spec.filterMutex (optional) is a list of {a, b} pairs whose toggles
    -- mutually exclude each other — turning one ON force-clears the partner
    -- and dithers + click-locks it via SetEnabled (alpha 0.4 + EnableMouse=false).
    if spec.filters and #spec.filters > 0 then
        local filterCard = sectionAt()
        local boxes = {}

        local function UpdateMutex()
            if not spec.filterMutex then return end
            for _, pair in ipairs(spec.filterMutex) do
                local a, b = pair[1], pair[2]
                local aBox, bBox = boxes[a], boxes[b]
                if aBox and bBox then
                    local aVal = settings[a]
                    local bVal = settings[b]
                    -- Defensive: if both true on entry (hand-edited SV), clear b
                    -- so neither toggle is stuck "checked while disabled".
                    if aVal and bVal then
                        settings[b] = false
                        bBox:Refresh()
                        bVal = false
                    end
                    aBox:SetEnabled(not bVal)
                    bBox:SetEnabled(not aVal)
                end
            end
        end

        local function MakeFilterOnChange(dbKey)
            return function(val)
                if val and spec.filterMutex then
                    for _, pair in ipairs(spec.filterMutex) do
                        local partner
                        if pair[1] == dbKey then partner = pair[2]
                        elseif pair[2] == dbKey then partner = pair[1]
                        end
                        if partner and settings[partner] then
                            settings[partner] = false
                            if boxes[partner] then boxes[partner]:Refresh() end
                        end
                    end
                end
                UpdateMutex()
                RefreshBuffBorders()
            end
        end

        for _, f in ipairs(spec.filters) do
            boxes[f.dbKey] = GUI:CreateFormToggle(filterCard.frame, nil, f.dbKey, settings,
                MakeFilterOnChange(f.dbKey),
                { description = f.description })
        end

        for i = 1, #spec.filters, 2 do
            local f1 = spec.filters[i]
            local f2 = spec.filters[i + 1]
            if f2 then
                filterCard.AddRow(
                    Opts.BuildSettingRow(filterCard.frame, f1.label, boxes[f1.dbKey]),
                    Opts.BuildSettingRow(filterCard.frame, f2.label, boxes[f2.dbKey])
                )
            else
                filterCard.AddRow(
                    Opts.BuildSettingRow(filterCard.frame, f1.label, boxes[f1.dbKey])
                )
            end
        end

        UpdateMutex()
        closeSection(filterCard)
    end

    -- Sort section: dropdown + reverse toggle.
    if spec.sortRuleKey then
        local sortCard = sectionAt()
        local sortDropdown = GUI:CreateFormDropdown(sortCard.frame, nil, SORT_OPTIONS, spec.sortRuleKey, settings, RefreshBuffBorders, nil,
            { description = ns.L["Sort order. Sent to both the secure header and C_UnitAuras.GetUnitAuras so child\226\134\148aura pairing stays valid."] })
        local sortReverse = GUI:CreateFormToggle(sortCard.frame, nil, spec.sortReverseKey, settings, RefreshBuffBorders,
            { description = ns.L["Flip the sort order. With Expiration sort this swaps soonest-first \226\134\148 longest-first."] })
        sortCard.AddRow(
            Opts.BuildSettingRow(sortCard.frame, ns.L["Sort"], sortDropdown),
            Opts.BuildSettingRow(sortCard.frame, ns.L["Reverse"], sortReverse)
        )
        closeSection(sortCard)
    end
end

local function BuildBuffDebuffTab(tabContent)
    local settings = GetBuffBordersSettings()
    if not settings then
        local label = tabContent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        label:SetPoint("TOPLEFT", 15, -15)
        label:SetPoint("RIGHT", tabContent, "RIGHT", -15, 0)
        label:SetJustifyH("LEFT")
        label:SetText(ns.L["Buff and debuff settings are unavailable right now."])
        tabContent:SetHeight(80)
        return
    end

    local PAD = Opts.PADDING
    local HEADER_GAP = 26
    local SECTION_GAP = 14
    local y = -10

    GUI:SetSearchContext({
        tabIndex = 8,
        tabName = "Action Bars",
        subTabIndex = 2,
        subTabName = "Buff/Debuff",
        tileId = ACTION_BARS_SEARCH_TILE_ID,
        subPageIndex = ACTION_BARS_BUFF_DEBUFF_SUB_PAGE_INDEX,
        featureId = ACTION_BARS_BUFF_DEBUFF_FEATURE_ID,
        category = "frames",
    })

    local function headerAt(text)
        local header = Opts.CreateAccentDotLabel(tabContent, text, y)
        header:ClearAllPoints()
        header:SetPoint("TOPLEFT", tabContent, "TOPLEFT", PAD, y)
        header:SetPoint("TOPRIGHT", tabContent, "TOPRIGHT", -PAD, y)
        y = y - HEADER_GAP
    end

    local function sectionAt()
        local card = Opts.CreateSettingsCardGroup(tabContent, y)
        card.frame:ClearAllPoints()
        card.frame:SetPoint("TOPLEFT", tabContent, "TOPLEFT", PAD, y)
        card.frame:SetPoint("TOPRIGHT", tabContent, "TOPRIGHT", -PAD, y)
        return card
    end

    local function closeSection(card)
        card.Finalize()
        y = y - card.frame:GetHeight() - SECTION_GAP
    end

    BuildSharedSection(tabContent, headerAt, sectionAt, closeSection, settings)

    BuildAuraSection(tabContent, headerAt, sectionAt, closeSection, settings, {
        title = ns.L["Buffs"],
        prefix = "buff",
        enabledKey = "enableBuffs",
        showBordersKey = "showBuffBorders",
        hideFrameKey = "hideBuffFrame",
        fadeKey = "fadeBuffFrame",
        invertSwipeKey = "buffInvertSwipeDarkening",
        iconSizeKey = "buffIconSize",
        iconsPerRowKey = "buffIconsPerRow",
        iconSpacingKey = "buffIconSpacing",
        rowSpacingKey = "buffRowSpacing",
        stackAnchorKey = "buffStackTextAnchor",
        stackOffsetXKey = "buffStackTextOffsetX",
        stackOffsetYKey = "buffStackTextOffsetY",
        durationAnchorKey = "buffDurationTextAnchor",
        durationOffsetXKey = "buffDurationTextOffsetX",
        durationOffsetYKey = "buffDurationTextOffsetY",
        enableDescription = ns.L["Show the custom buff frame managed by QUI."],
        borderDescription = ns.L["Draw borders around buff icons."],
        hideDescription = ns.L["Hide the buff frame entirely, even when hovering its anchor area."],
        fadeDescription = ns.L["Fade the buff frame out until you hover it."],
        filters = {
            { dbKey = "buffFilterPlayer",        label = ns.L["Only My Buffs (PLAYER)"],
              description = ns.L["Show only buffs you applied yourself. Hides everything cast on you by others."] },
            { dbKey = "buffFilterRaid",          label = ns.L["Only Raid-Relevant (RAID)"],
              description = ns.L["Show only buffs flagged as raid-relevant for your class \226\128\148 typically the ones you'd track on a raid frame."] },
            { dbKey = "buffFilterCancelable",    label = ns.L["Only Cancellable"],
              description = ns.L["Show only buffs you can right-click to cancel. Excludes most consumables, talents, and gear procs. Mutually exclusive with Only Persistent."] },
            { dbKey = "buffFilterNotCancelable", label = ns.L["Only Persistent"],
              description = ns.L["Show only buffs that cannot be cancelled \226\128\148 flasks, food, world buffs, gear procs, and similar. Mutually exclusive with Only Cancellable."] },
            { dbKey = "buffFilterBigDefensive",  label = ns.L["Big Defensive Only"],
              description = ns.L["Show only big-defensive buffs (Aspect of the Turtle, Divine Shield, Ice Block, etc.). Patch 12.0.1+."] },
        },
        filterMutex = {
            { "buffFilterCancelable", "buffFilterNotCancelable" },
        },
        sortRuleKey = "buffSortRule",
        sortReverseKey = "buffSortReverse",
    })

    BuildAuraSection(tabContent, headerAt, sectionAt, closeSection, settings, {
        title = ns.L["Debuffs"],
        prefix = "debuff",
        enabledKey = "enableDebuffs",
        showBordersKey = "showDebuffBorders",
        hideFrameKey = "hideDebuffFrame",
        fadeKey = "fadeDebuffFrame",
        invertSwipeKey = "debuffInvertSwipeDarkening",
        iconSizeKey = "debuffIconSize",
        iconsPerRowKey = "debuffIconsPerRow",
        iconSpacingKey = "debuffIconSpacing",
        rowSpacingKey = "debuffRowSpacing",
        stackAnchorKey = "debuffStackTextAnchor",
        stackOffsetXKey = "debuffStackTextOffsetX",
        stackOffsetYKey = "debuffStackTextOffsetY",
        durationAnchorKey = "debuffDurationTextAnchor",
        durationOffsetXKey = "debuffDurationTextOffsetX",
        durationOffsetYKey = "debuffDurationTextOffsetY",
        enableDescription = ns.L["Show the custom debuff frame managed by QUI."],
        borderDescription = ns.L["Draw borders around debuff icons."],
        hideDescription = ns.L["Hide the debuff frame entirely, even when hovering its anchor area."],
        fadeDescription = ns.L["Fade the debuff frame out until you hover it."],
        filters = {
            { dbKey = "debuffFilterPlayer",                label = ns.L["Only My Debuffs (PLAYER)"],
              description = ns.L["Show only debuffs you applied \226\128\148 useful for DoT trackers and similar."] },
            { dbKey = "debuffFilterRaid",                  label = ns.L["Only Raid-Relevant (RAID)"],
              description = ns.L["Show only debuffs flagged as raid-relevant \226\128\148 typically what raid frames would surface."] },
            { dbKey = "debuffFilterIncludeNameplateOnly",  label = ns.L["Include Nameplate-Only"],
              description = ns.L["Expand results to include auras flagged for nameplate-only display, which are normally hidden from the debuff frame."] },
            { dbKey = "debuffFilterRaidPlayerDispellable", label = ns.L["Only Dispellable by You"],
              description = ns.L["Show only debuffs whose dispel type your class can remove. Patch 12.0.1+."] },
            { dbKey = "debuffFilterImportant",             label = ns.L["Important Spells Only"],
              description = ns.L["Show only spells flagged as important by C_Spell.IsSpellImportant. Patch 12.0.1+."] },
            { dbKey = "debuffFilterCrowdControl",          label = ns.L["Crowd Control Only"],
              description = ns.L["Show only crowd-control effects (stuns, fears, roots, etc.). Patch 12.0.1+."] },
        },
        sortRuleKey = "debuffSortRule",
        sortReverseKey = "debuffSortReverse",
    })

    tabContent:SetHeight(math.abs(y) + 40)
end

ns.QUI_BuffDebuffOptions = {
    BuildBuffDebuffTab = BuildBuffDebuffTab,
}
