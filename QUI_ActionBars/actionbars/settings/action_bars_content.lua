local ADDON_NAME, ns = ...
local QUI = QUI
local GUI = QUI.GUI
local C = GUI.Colors
local Shared = ns.QUI_Options
local Opts = Shared  -- V3 body-pattern helpers

-- Local references
local PADDING = Shared.PADDING
local CreateScrollableContent = Shared.CreateScrollableContent
local GetDB = Shared.GetDB
local GetTextureList = Shared.GetTextureList
local GetFontList = Shared.GetFontList
local ACTION_BARS_SEARCH_TILE_ID = "action_bars"
local ACTION_BARS_GENERAL_FEATURE_ID = "actionBarsGeneral"
local ACTION_BARS_GENERAL_SUB_PAGE_INDEX = 1

local Helpers = ns.Helpers
local GetCore = Helpers.GetCore
local Settings = ns.Settings
local Registry = Settings and Settings.Registry
local Schema = Settings and Settings.Schema

---------------------------------------------------------------------------
-- SHARED CONTEXT & REFRESH CALLBACKS
---------------------------------------------------------------------------
local function ResolveContext()
    local db = GetDB()
    if not db or not db.actionBars then return nil end
    return {
        db = db,
        actionBars = db.actionBars,
        global = db.actionBars.global,
        fade = db.actionBars.fade,
        bars = db.actionBars.bars,
    }
end

local function RefreshActionBars()
    if _G.QUI_RefreshActionBars then _G.QUI_RefreshActionBars() end
end

-- Lightweight: only re-evaluate mouseover fade state (no full bar rebuild)
local function RefreshActionBarFade()
    if _G.QUI_RefreshActionBarFade then _G.QUI_RefreshActionBarFade() end
end

local function Unavailable(parent, label)
    local t = GUI:CreateLabel(parent, (label or "Action Bars") .. " settings not available. Please /reload.", 12, C.text)
    t:SetPoint("TOPLEFT", PADDING, -15)
end

-- Vertical section-layout cursor shared by the sub-tab builders. Returns the
-- headerAt / sectionAt / closeSection trio that advance a shared `y` cursor as
-- accent-dot headers and settings-card groups are stacked down the tab.
local function MakeSectionLayout(tabContent)
    local PAD = PADDING
    local HEADER_GAP = 26
    local SECTION_GAP = 14
    local y = -10

    local function headerAt(text)
        local h = Opts.CreateAccentDotLabel(tabContent, text, y)
        h:ClearAllPoints()
        h:SetPoint("TOPLEFT", tabContent, "TOPLEFT", PAD, y)
        h:SetPoint("TOPRIGHT", tabContent, "TOPRIGHT", -PAD, y)
        y = y - HEADER_GAP
    end
    local function sectionAt()
        local c = Opts.CreateSettingsCardGroup(tabContent, y)
        c.frame:ClearAllPoints()
        c.frame:SetPoint("TOPLEFT", tabContent, "TOPLEFT", PAD, y)
        c.frame:SetPoint("TOPRIGHT", tabContent, "TOPRIGHT", -PAD, y)
        return c
    end
    local function closeSection(c)
        c.Finalize()
        y = y - c.frame:GetHeight() - SECTION_GAP
    end
    local function getY()
        return y
    end

    return headerAt, sectionAt, closeSection, getY
end

---------------------------------------------------------------------------
-- PERSISTENT PREVIEW (tile-level, shared across all sub-tabs)
---------------------------------------------------------------------------
-- Called once by framework_v2 BuildTilePage via tile.config.preview.build.
-- Populates the preview frame with 10 action button mirrors + a bar
-- selector dropdown that picks which of bar 1-8 to mirror. Stays in sync
-- with live slot changes. Since it's built at the tile level (not the
-- sub-tab level), it persists across every sub-tab of Action Bars.
local BAR_OPTIONS = {
    { value = "bar1", text = "Bar 1" }, { value = "bar2", text = "Bar 2" },
    { value = "bar3", text = "Bar 3" }, { value = "bar4", text = "Bar 4" },
    { value = "bar5", text = "Bar 5" }, { value = "bar6", text = "Bar 6" },
    { value = "bar7", text = "Bar 7" }, { value = "bar8", text = "Bar 8" },
}
local PreviewState = {
    bar = "bar1",
    refresh = nil,
}
local SelectedBarState = {
    key = "bar1",
}
local SelectedBarListeners = setmetatable({}, { __mode = "k" })

local function NotifySelectedBarChanged(origin)
    for owner, callback in pairs(SelectedBarListeners) do
        if owner and callback then
            local ok = pcall(callback, SelectedBarState.key, origin)
            if not ok then
                SelectedBarListeners[owner] = nil
            end
        end
    end
end

local function RegisterSelectedBarListener(owner, callback)
    if owner and type(callback) == "function" then
        SelectedBarListeners[owner] = callback
    end
end

local function GetSelectedBar()
    return SelectedBarState.key
end

local function SetSelectedBar(barKey, origin)
    if type(barKey) ~= "string" or barKey == "" then return end

    local isPreviewable = ns.QUI_ActionBarsPreviewDriver
        and ns.QUI_ActionBarsPreviewDriver.IsPreviewable(barKey)
    local changedSelection = SelectedBarState.key ~= barKey
    local changedPreview = isPreviewable and PreviewState.bar ~= barKey

    SelectedBarState.key = barKey
    if isPreviewable then
        PreviewState.bar = barKey
    end

    if changedSelection or changedPreview then
        NotifySelectedBarChanged(origin)
    end
end

local function SetActionBarsPreviewBar(barKey)
    if not (ns.QUI_ActionBarsPreviewDriver
        and ns.QUI_ActionBarsPreviewDriver.IsPreviewable(barKey)) then
        return
    end
    SetSelectedBar(barKey, "preview")
    if ns.QUI_ActionBarsPreviewDriver.SetSelectedBar then
        ns.QUI_ActionBarsPreviewDriver.SetSelectedBar(barKey)
    end
    if PreviewState.refresh then PreviewState.refresh() end
end

local function BuildActionBarsPreview(pv)
    local accent = C.accent or { 0.204, 0.827, 0.6, 1 }
    local border = (GUI.Colors and GUI.Colors.border) or { 1, 1, 1, 0.06 }

    local selectedBar = GetSelectedBar()
    if ns.QUI_ActionBarsPreviewDriver
        and ns.QUI_ActionBarsPreviewDriver.IsPreviewable(selectedBar) then
        PreviewState.bar = selectedBar
    end

    local fill = pv:CreateTexture(nil, "BACKGROUND")
    fill:SetAllPoints(pv)
    fill:SetColorTexture(0, 0, 0, 0.2)

    if ns.UIKit and ns.UIKit.CreateBorderLines then
        ns.UIKit.CreateBorderLines(pv)
        ns.UIKit.UpdateBorderLines(pv, 1, border[1], border[2], border[3], 0.15, false)
    end

    local lbl = pv:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    local fpath = ns.UIKit and ns.UIKit.ResolveFontPath and ns.UIKit.ResolveFontPath(GUI:GetFontPath())
    lbl:SetFont(fpath or select(1, lbl:GetFont()), 8, "")
    lbl:SetTextColor(accent[1], accent[2], accent[3], 0.7)
    lbl:SetPoint("TOPLEFT", pv, "TOPLEFT", 8, -6)
    local spaced = "P R E V I E W"
    lbl:SetText(spaced)

    -- Driver owns the preview buttons, Cooldown children, ticker, and cycle.
    if ns.QUI_ActionBarsPreviewDriver and ns.QUI_ActionBarsPreviewDriver.Build then
        ns.QUI_ActionBarsPreviewDriver.Build(pv)
    end

    -- PreviewState.refresh now points at the driver. This is the
    -- callback every option onChange / live-event handler invokes.
    PreviewState.refresh = ns.QUI_ActionBarsPreviewDriver and ns.QUI_ActionBarsPreviewDriver.Refresh
    if PreviewState.refresh then PreviewState.refresh() end

    local selector = GUI:CreateFormDropdown(pv, nil, BAR_OPTIONS,
        "bar", PreviewState, function(val)
            SetActionBarsPreviewBar(val)
        end,
        { description = "Pick which action bar the preview panel renders. This only affects the preview above — it does not change any saved settings." })
    selector:ClearAllPoints()
    selector:SetPoint("TOPRIGHT", pv, "TOPRIGHT", -8, -4)
    selector:SetSize(80, 22)

    RegisterSelectedBarListener(pv, function(barKey, origin)
        if not (ns.QUI_ActionBarsPreviewDriver
            and ns.QUI_ActionBarsPreviewDriver.IsPreviewable(barKey)) then
            return
        end
        PreviewState.bar = barKey
        if selector and selector.SetValue then
            selector.SetValue(barKey, true)
        end
        if origin ~= "preview" and ns.QUI_ActionBarsPreviewDriver.SetSelectedBar then
            ns.QUI_ActionBarsPreviewDriver.SetSelectedBar(barKey)
        end
        if origin ~= "preview" and PreviewState.refresh then
            PreviewState.refresh()
        end
    end)

    pv:RegisterEvent("ACTIONBAR_SLOT_CHANGED")
    pv:RegisterEvent("UPDATE_BINDINGS")
    pv:RegisterEvent("PLAYER_ENTERING_WORLD")
    -- ACTIONBAR_SLOT_CHANGED fires constantly (~10/s) even at idle, so
    -- gate refresh on visibility. OnUpdate already only ticks while shown
    -- and runs every 1.0s, so a freshly-opened panel catches up within a second.
    pv:SetScript("OnEvent", function(self)
        if self:IsVisible() and PreviewState.refresh then
            PreviewState.refresh()
        end
    end)

    -- Safety-net poll. Setting changes are reflected explicitly via
    -- _G.QUI_RefreshActionBars → driver.Refresh; this poll exists only
    -- to catch live action-slot changes the game made without firing
    -- ACTIONBAR_SLOT_CHANGED, plus hypothetical setting paths that skip
    -- the explicit hook chain. 1.0s is imperceptible latency for those.
    local _accum = 0
    pv:SetScript("OnUpdate", function(self, elapsed)
        _accum = _accum + elapsed
        if _accum < 1.0 then return end
        _accum = 0
        if PreviewState.refresh then PreviewState.refresh() end
    end)
end

---------------------------------------------------------------------------
-- SUB-TAB: General (section layout with mixed 2-col)
---------------------------------------------------------------------------
local function BuildMasterSettingsTab(tabContent)
    local ctx = ResolveContext()
    if not ctx then Unavailable(tabContent, "Action Bars"); return end
    local global = ctx.global

    GUI:SetSearchContext({
        tabIndex = 8,
        tabName = "Action Bars",
        subTabIndex = 1,
        subTabName = "General",
        tileId = ACTION_BARS_SEARCH_TILE_ID,
        subPageIndex = ACTION_BARS_GENERAL_SUB_PAGE_INDEX,
        featureId = ACTION_BARS_GENERAL_FEATURE_ID,
        category = "frames",
    })

    local headerAt, sectionAt, closeSection, getY = MakeSectionLayout(tabContent)

    -- Button lock proxy (CVar-backed dropdown)
    local lockOptions = {
        {value = "unlocked", text = "Unlocked"},
        {value = "shift", text = "Locked - Shift to drag"},
        {value = "alt", text = "Locked - Alt to drag"},
        {value = "ctrl", text = "Locked - Ctrl to drag"},
        {value = "none", text = "Fully Locked"},
    }
    local lockProxy = setmetatable({}, {
        __index = function(t, k)
            if k == "buttonLock" then
                local isLocked = GetCVar("lockActionBars") == "1"
                if not isLocked then return "unlocked" end
                local modifier = GetModifiedClick("PICKUPACTION") or "SHIFT"
                if modifier == "NONE" then return "none" end
                return modifier:lower()
            end
        end,
        __newindex = function(t, k, v)
            if InCombatLockdown() then return end
            if k == "buttonLock" and type(v) == "string" then
                if v == "unlocked" then SetCVar("lockActionBars", "0")
                else
                    SetCVar("lockActionBars", "1")
                    SetModifiedClick("PICKUPACTION", (v == "none") and "NONE" or v:upper())
                    SaveBindings(GetCurrentBindingSet())
                end
            end
        end
    })

    -- GENERAL (mixed types paired for space efficiency)
    headerAt("General")
    local s1 = sectionAt()

    -- Module on/off lives in Module Addons (addon enable state); the old
    -- "Enable Action Bars" master toggle was retired with its flag (v43).
    local lockDD = GUI:CreateFormDropdown(s1.frame, nil, lockOptions,
        "buttonLock", lockProxy, RefreshActionBars,
        { description = "Control whether action buttons can be dragged. Choose a modifier to unlock them on the fly or lock the bars fully." })
    lockDD:HookScript("OnShow", function(self) self.SetValue(lockProxy.buttonLock, true) end)
    s1.AddRow(
        Opts.BuildSettingRow(s1.frame, "Button Lock", lockDD)
    )

    local showTipsW = GUI:CreateFormToggle(s1.frame, nil, "showTooltips", global, nil,
        { description = "Show the ability tooltip when hovering an action button." })
    local hideEmptyW = GUI:CreateFormToggle(s1.frame, nil, "hideEmptySlots", global, RefreshActionBars,
        { description = "Hide empty action slots so only buttons with abilities are visible." })
    s1.AddRow(
        Opts.BuildSettingRow(s1.frame, "Show Tooltips", showTipsW),
        Opts.BuildSettingRow(s1.frame, "Hide Empty Slots", hideEmptyW)
    )

    local qualityW = GUI:CreateFormToggle(s1.frame, nil, "showProfessionQuality", global, RefreshActionBars,
        { description = "Show a quality indicator on profession items placed on action bars." })
    local keyPressW = GUI:CreateFormToggle(s1.frame, nil, "useOnKeyDown", global, function()
        if _G.QUI_ApplyUseOnKeyDown then _G.QUI_ApplyUseOnKeyDown() end
    end, { description = "Cast abilities on key press instead of key release for lower input latency." })
    s1.AddRow(
        Opts.BuildSettingRow(s1.frame, "Show Crafted Item Quality", qualityW),
        Opts.BuildSettingRow(s1.frame, "Cast on Key Press", keyPressW)
    )

    local assistW = GUI:CreateFormToggle(s1.frame, nil, "assistedHighlight", global, function()
        if ns.ActionBarsOwned and ns.ActionBarsOwned.UpdateAllAssistedHighlights then
            ns.ActionBarsOwned.UpdateAllAssistedHighlights()
        end
    end, { description = "Highlight the suggested next ability based on your class rotation." })
    s1.AddRow(Opts.BuildSettingRow(s1.frame, "Rotation Assist", assistW))

    closeSection(s1)

    -- RANGE & USABILITY (mixed: toggle + color picker paired row)
    headerAt("Range & Usability")
    local s2 = sectionAt()

    local rangeW = GUI:CreateFormToggle(s2.frame, nil, "rangeIndicator", global, RefreshActionBars,
        { description = "Tint action buttons when your target is out of range." })
    local rangeColorW = GUI:CreateFormColorPicker(s2.frame, nil, "rangeColor", global, RefreshActionBars, nil,
        { description = "Color applied to buttons when the target is out of range." })
    s2.AddRow(
        Opts.BuildSettingRow(s2.frame, "Out of Range Indicator", rangeW),
        Opts.BuildSettingRow(s2.frame, "Out of Range Color", rangeColorW)
    )

    local unusableW = GUI:CreateFormToggle(s2.frame, nil, "usabilityIndicator", global, RefreshActionBars,
        { description = "Dim action buttons when their ability can't currently be cast." })
    local unusableColorW = GUI:CreateFormColorPicker(s2.frame, nil, "usabilityColor", global, RefreshActionBars, nil,
        { description = "Color overlay applied to unusable action buttons." })
    s2.AddRow(
        Opts.BuildSettingRow(s2.frame, "Dim Unusable Buttons", unusableW),
        Opts.BuildSettingRow(s2.frame, "Unusable Color", unusableColorW)
    )

    local fastW = GUI:CreateFormToggle(s2.frame, nil, "fastUsabilityUpdates", global, RefreshActionBars,
        { description = "Update range and usability every frame instead of on a timer. Higher accuracy, slight CPU cost." })
    local manaColorW = GUI:CreateFormColorPicker(s2.frame, nil, "manaColor", global, RefreshActionBars, nil,
        { description = "Color applied to buttons when you lack the mana or resource to cast." })
    s2.AddRow(
        Opts.BuildSettingRow(s2.frame, "Unthrottled CPU", fastW),
        Opts.BuildSettingRow(s2.frame, "Out of Mana Color", manaColorW)
    )

    closeSection(s2)

    -- QUICK KEYBIND
    headerAt("Quick Keybind")
    local s3 = sectionAt()

    local keybindBtn = GUI:CreateButton(s3.frame, "Toggle Keybind Mode", 160, 24, function()
        if InCombatLockdown() then return end
        local LibKeyBound = LibStub("LibKeyBound-1.0", true)
        if LibKeyBound then LibKeyBound:Toggle()
        elseif QuickKeybindFrame then ShowUIPanel(QuickKeybindFrame) end
    end)
    GUI:AttachTooltip(keybindBtn,
        "Enter keybind capture mode — hover any action button and press a key to bind it. Uses LibKeyBound when available, otherwise opens Blizzard's Quick Keybind frame. Disabled in combat.",
        "Toggle Keybind Mode")
    s3.AddRow(Opts.BuildSettingRow(s3.frame,
        "Keybind Mode", keybindBtn,
        "Show keybind overlays on action buttons"))

    closeSection(s3)

    tabContent:SetHeight(math.abs(getY()) + 40)
end

---------------------------------------------------------------------------
-- SUB-TAB: Mouseover Hide (section layout with mixed 2-col pairing)
---------------------------------------------------------------------------
local function BuildMouseoverHideTab(tabContent)
    local ctx = ResolveContext()
    if not ctx then Unavailable(tabContent, "Mouseover Hide"); return end
    local fade, bars = ctx.fade, ctx.bars

    GUI:SetSearchContext({tabIndex = 8, tabName = "Action Bars", subTabIndex = 2, subTabName = "Mouseover Hide"})

    local headerAt, sectionAt, closeSection, getY = MakeSectionLayout(tabContent)

    -- FADE SETTINGS (mixed pairing: toggle+slider, slider+slider, toggle+toggle)
    headerAt("Fade Settings")
    local s1 = sectionAt()

    local enableW = GUI:CreateFormToggle(s1.frame, nil, "enabled", fade, RefreshActionBarFade,
        { description = "Fade action bars when you're not hovering over them. Hover to reveal." })
    local alphaW = GUI:CreateFormSlider(s1.frame, nil, 0, 1, 0.05, "fadeOutAlpha", fade, RefreshActionBarFade,
        { description = "Opacity of action bars when faded out. 0 is fully invisible, 1 is fully opaque." })
    s1.AddRow(
        Opts.BuildSettingRow(s1.frame, "Enable Mouseover Hide", enableW),
        Opts.BuildSettingRow(s1.frame, "Faded Opacity", alphaW)
    )

    local inW = GUI:CreateFormSlider(s1.frame, nil, 0.1, 1.0, 0.05, "fadeInDuration", fade, RefreshActionBarFade,
        { description = "How many seconds the fade-in animation takes when your cursor enters a bar." })
    local outW = GUI:CreateFormSlider(s1.frame, nil, 0.1, 1.0, 0.05, "fadeOutDuration", fade, RefreshActionBarFade,
        { description = "How many seconds the fade-out animation takes when your cursor leaves a bar." })
    s1.AddRow(
        Opts.BuildSettingRow(s1.frame, "Fade In Speed", inW),
        Opts.BuildSettingRow(s1.frame, "Fade Out Speed", outW)
    )

    local delayW = GUI:CreateFormSlider(s1.frame, nil, 0, 2.0, 0.1, "fadeOutDelay", fade, RefreshActionBarFade,
        { description = "Delay in seconds between your cursor leaving a bar and the fade-out starting." })
    local linkW = GUI:CreateFormToggle(s1.frame, nil, "linkBars1to8", fade, RefreshActionBarFade,
        { description = "Treat bars 1-8 plus the pet and stance bars as a single group so hovering any one shows all of them together." })
    s1.AddRow(
        Opts.BuildSettingRow(s1.frame, "Fade Out Delay", delayW),
        Opts.BuildSettingRow(s1.frame, "Link Bars 1-8", linkW)
    )

    local combatW = GUI:CreateFormToggle(s1.frame, nil, "alwaysShowInCombat", fade, RefreshActionBarFade,
        { description = "Keep action bars fully visible while you are in combat, overriding the fade." })
    local sbookW = GUI:CreateFormToggle(s1.frame, nil, "showWhenSpellBookOpen", fade, RefreshActionBarFade,
        { description = "Keep bars visible while the spellbook is open, so you can drag-and-drop abilities." })
    s1.AddRow(
        Opts.BuildSettingRow(s1.frame, "Do Not Hide In Combat", combatW),
        Opts.BuildSettingRow(s1.frame, "Show While Spellbook Open", sbookW)
    )

    local vehicleW = GUI:CreateFormToggle(s1.frame, nil, "keepLeaveVehicleVisible", fade, RefreshActionBarFade,
        { description = "Keep the Leave Vehicle button visible even when the rest of the bar is faded." })
    local levelW = GUI:CreateFormToggle(s1.frame, nil, "disableBelowMaxLevel", fade, RefreshActionBarFade,
        { description = "Disable mouseover fade on non-max-level characters, where full bars are easier to learn." })
    s1.AddRow(
        Opts.BuildSettingRow(s1.frame, "Keep Leave Vehicle Visible", vehicleW),
        Opts.BuildSettingRow(s1.frame, "Disable Below Max Level", levelW)
    )

    closeSection(s1)

    -- ALWAYS SHOW BARS (paired 2-up throughout)
    headerAt("Always Show Bars")
    local s2 = sectionAt()

    local alwaysShowBars = {
        { key = "bar1", label = "Bar 1" }, { key = "bar2", label = "Bar 2" },
        { key = "bar3", label = "Bar 3" }, { key = "bar4", label = "Bar 4" },
        { key = "bar5", label = "Bar 5" }, { key = "bar6", label = "Bar 6" },
        { key = "bar7", label = "Bar 7" }, { key = "bar8", label = "Bar 8" },
        { key = "microbar", label = "Microbar" }, { key = "bags", label = "Bags" },
        { key = "pet", label = "Pet Bar" }, { key = "stance", label = "Stance Bar" },
        { key = "extraActionButton", label = "Extra Action" }, { key = "zoneAbility", label = "Zone Ability" },
    }

    local pending = nil
    for _, barInfo in ipairs(alwaysShowBars) do
        local barDB = bars[barInfo.key]
        if barDB then
            local w = GUI:CreateFormToggle(s2.frame, nil, "alwaysShow", barDB, RefreshActionBarFade,
                { description = "Keep " .. barInfo.label .. " fully visible at all times, ignoring the mouseover fade." })
            local cell = Opts.BuildSettingRow(s2.frame, barInfo.label, w)
            if pending then
                s2.AddRow(pending, cell)
                pending = nil
            else
                pending = cell
            end
        end
    end
    if pending then s2.AddRow(pending) end

    closeSection(s2)

    tabContent:SetHeight(math.abs(getY()) + 40)
end

---------------------------------------------------------------------------
-- LEGACY ENTRY POINT (kept as a thin wrapper for backwards compat)
---------------------------------------------------------------------------
-- The V2 Action Bars tile now routes directly to BuildMasterSettingsTab and
-- BuildMouseoverHideTab, so there are no current callers of this function —
-- but leave it exported as a safety shim for any out-of-tree consumer.
local function CreateActionBarsPage(parent)
    local scroll, content = CreateScrollableContent(parent)
    BuildMasterSettingsTab(content)
    return scroll, content
end

---------------------------------------------------------------------------
-- Export
---------------------------------------------------------------------------
ns.QUI_ActionBarsOptions = {
    BuildActionBarsPreview = BuildActionBarsPreview,
    BuildMasterSettingsTab = BuildMasterSettingsTab,
    BuildMouseoverHideTab  = BuildMouseoverHideTab,
    SetPreviewBar          = SetActionBarsPreviewBar,
    SetSelectedBar         = SetSelectedBar,
    GetSelectedBar         = GetSelectedBar,
    RegisterSelectedBarListener = RegisterSelectedBarListener,
    RefreshPreview         = function()
        if PreviewState.refresh then
            PreviewState.refresh()
        end
    end,
    IsPreviewableBar       = function(barKey)
        return ns.QUI_ActionBarsPreviewDriver
            and ns.QUI_ActionBarsPreviewDriver.IsPreviewable(barKey)
            or false
    end,
    CreateActionBarsPage   = CreateActionBarsPage,  -- legacy shim
}

if Registry and Schema
    and type(Registry.RegisterFeature) == "function"
    and type(Schema.Feature) == "function"
    and type(Schema.Section) == "function" then
    Registry:RegisterFeature(Schema.Feature({
        id = "barHidingPage",
        moverKey = "barHiding",
        category = "appearance",
        nav = { tileId = "appearance", subPageIndex = 6 },
        sections = {
            Schema.Section({
                id = "settings",
                kind = "page",
                minHeight = 80,
                build = BuildMouseoverHideTab,
            }),
        },
    }))
end
