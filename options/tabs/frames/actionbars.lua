local ADDON_NAME, ns = ...
local QUI = QUI
local GUI = QUI.GUI
local C = GUI.Colors
local Shared = ns.QUI_Options

-- Local references
local PADDING = Shared.PADDING
local CreateScrollableContent = Shared.CreateScrollableContent
local GetDB = Shared.GetDB
local GetTextureList = Shared.GetTextureList
local GetFontList = Shared.GetFontList
-- Forward declaration for Totem Bar sub-tab (defined below Action Bars page)
local BuildTotemBarTab

local Helpers = ns.Helpers
local GetCore = Helpers.GetCore

---------------------------------------------------------------------------
-- PAGE: Action Bars
---------------------------------------------------------------------------
local function CreateActionBarsPage(parent)
    local scroll, content = CreateScrollableContent(parent)
    local db = GetDB()

    -- Safety check
    if not db or not db.actionBars then
        local errorLabel = GUI:CreateLabel(content, "Action Bars settings not available. Please reload UI.", 12, C.text)
        errorLabel:SetPoint("TOPLEFT", PADDING, -15)
        content:SetHeight(100)
        return scroll, content
    end

    local actionBars = db.actionBars
    local global = actionBars.global
    local fade = actionBars.fade
    local bars = actionBars.bars

    -- Refresh callbacks
    local function RefreshActionBars()
        if _G.QUI_RefreshActionBars then
            _G.QUI_RefreshActionBars()
        end
    end
    -- Lightweight: only re-evaluate mouseover fade state (no full bar rebuild)
    local function RefreshActionBarFade()
        if _G.QUI_RefreshActionBarFade then
            _G.QUI_RefreshActionBarFade()
        end
    end

    ---------------------------------------------------------
    -- SUB-TAB: Mouseover Hide
    ---------------------------------------------------------
    local function BuildMouseoverHideTab(tabContent)
        local PAD = PADDING
        local FORM_ROW = 32
        local P = Helpers.PlaceRow

        GUI:SetSearchContext({tabIndex = 8, tabName = "Action Bars", subTabIndex = 2, subTabName = "Mouseover Hide"})

        local sections, relayout, CreateCollapsible = Shared.CreateCollapsiblePage(tabContent, PAD)

        -- Fade Settings
        CreateCollapsible("Fade Settings", 10 * FORM_ROW + 50, function(body)
            local sy = -4
            sy = P(GUI:CreateFormCheckbox(body, "Enable Mouseover Hide", "enabled", fade, RefreshActionBarFade), body, sy)
            sy = P(GUI:CreateFormSlider(body, "Fade In Speed (sec)", 0.1, 1.0, 0.05, "fadeInDuration", fade, RefreshActionBarFade), body, sy)
            sy = P(GUI:CreateFormSlider(body, "Fade Out Speed (sec)", 0.1, 1.0, 0.05, "fadeOutDuration", fade, RefreshActionBarFade), body, sy)
            sy = P(GUI:CreateFormSlider(body, "Faded Opacity", 0, 1, 0.05, "fadeOutAlpha", fade, RefreshActionBarFade), body, sy)
            sy = P(GUI:CreateFormSlider(body, "Fade Out Delay (sec)", 0, 2.0, 0.1, "fadeOutDelay", fade, RefreshActionBarFade), body, sy)
            sy = P(GUI:CreateFormCheckbox(body, "Do Not Hide In Combat", "alwaysShowInCombat", fade, RefreshActionBarFade), body, sy)
            sy = P(GUI:CreateFormCheckbox(body, "Show Bars While Spellbook Open", "showWhenSpellBookOpen", fade, RefreshActionBarFade), body, sy)
            sy = P(GUI:CreateFormCheckbox(body, "Keep Leave Vehicle Button Visible", "keepLeaveVehicleVisible", fade, RefreshActionBarFade), body, sy)
            sy = P(GUI:CreateFormCheckbox(body, "Disable Below Max Level", "disableBelowMaxLevel", fade, RefreshActionBarFade), body, sy)
            P(GUI:CreateFormCheckbox(body, "Link Bars 1-8 on Mouseover", "linkBars1to8", fade, RefreshActionBarFade), body, sy)
        end)

        -- Always Show Bars
        local alwaysShowBars = {
            { key = "bar1", label = "Bar 1" }, { key = "bar2", label = "Bar 2" },
            { key = "bar3", label = "Bar 3" }, { key = "bar4", label = "Bar 4" },
            { key = "bar5", label = "Bar 5" }, { key = "bar6", label = "Bar 6" },
            { key = "bar7", label = "Bar 7" }, { key = "bar8", label = "Bar 8" },
            { key = "microbar", label = "Microbar" }, { key = "bags", label = "Bags" },
            { key = "pet", label = "Pet Bar" }, { key = "stance", label = "Stance Bar" },
            { key = "extraActionButton", label = "Extra Action" }, { key = "zoneAbility", label = "Zone Ability" },
        }
        local alwaysShowCount = 0
        for _, bi in ipairs(alwaysShowBars) do if bars[bi.key] then alwaysShowCount = alwaysShowCount + 1 end end

        CreateCollapsible("Always Show Bars", alwaysShowCount * FORM_ROW + 8, function(body)
            local sy = -4
            for _, barInfo in ipairs(alwaysShowBars) do
                local barDB = bars[barInfo.key]
                if barDB then
                    sy = P(GUI:CreateFormCheckbox(body, barInfo.label, "alwaysShow", barDB, RefreshActionBarFade), body, sy)
                end
            end
        end)

        relayout()
    end  -- End BuildMouseoverHideTab

    ---------------------------------------------------------
    -- SUB-TAB: Master Visual Settings (existing global settings)
    ---------------------------------------------------------
    local function BuildMasterSettingsTab(tabContent)
        local PAD = PADDING
        local FORM_ROW = 32
        local P = Helpers.PlaceRow

        GUI:SetSearchContext({tabIndex = 8, tabName = "Action Bars", subTabIndex = 1, subTabName = "General"})

        local sections, relayout, CreateCollapsible = Shared.CreateCollapsiblePage(tabContent, PAD)

        -- General
        CreateCollapsible("General", 3 * FORM_ROW + 8, function(body)
            local sy = -4
            sy = P(GUI:CreateFormCheckbox(body, "Enable QUI Action Bars (Req. Reload)", "enabled", actionBars, function()
                GUI:ShowConfirmation({
                    title = "Reload Required",
                    message = "Action Bar styling requires a UI reload to take effect.",
                    acceptText = "Reload Now", cancelText = "Later",
                    onAccept = function() QUI:SafeReload() end,
                })
            end), body, sy)
            sy = P(GUI:CreateFormCheckbox(body, "Show Tooltips", "showTooltips", global), body, sy)
            P(GUI:CreateFormCheckbox(body, "Hide Empty Slots", "hideEmptySlots", global, RefreshActionBars), body, sy)
        end)

        -- Button Lock
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

        CreateCollapsible("Button Lock", 1 * FORM_ROW + 8, function(body)
            local sy = -4
            local dd = GUI:CreateFormDropdown(body, "Action Button Lock", lockOptions, "buttonLock", lockProxy, RefreshActionBars)
            dd:HookScript("OnShow", function(self) self.SetValue(lockProxy.buttonLock, true) end)
            P(dd, body, sy)
        end)

        -- Range & Usability
        CreateCollapsible("Range & Usability Indicators", 6 * FORM_ROW + 8, function(body)
            local sy = -4
            sy = P(GUI:CreateFormCheckbox(body, "Out of Range Indicator", "rangeIndicator", global, RefreshActionBars), body, sy)
            sy = P(GUI:CreateFormColorPicker(body, "Out of Range Color", "rangeColor", global, RefreshActionBars), body, sy)
            sy = P(GUI:CreateFormCheckbox(body, "Dim Unusable Buttons", "usabilityIndicator", global, RefreshActionBars), body, sy)
            sy = P(GUI:CreateFormCheckbox(body, "Desaturate Unusable", "usabilityDesaturate", global, RefreshActionBars), body, sy)
            sy = P(GUI:CreateFormColorPicker(body, "Out of Mana Color", "manaColor", global, RefreshActionBars), body, sy)
            P(GUI:CreateFormCheckbox(body, "Unthrottled CPU Usage", "fastUsabilityUpdates", global, RefreshActionBars), body, sy)
        end)

        -- Quick Keybind
        CreateCollapsible("Quick Keybind Mode", 1 * FORM_ROW + 8, function(body)
            local keybindModeBtn = GUI:CreateButton(body, "Toggle Keybind Mode", 180, 28, function()
                if InCombatLockdown() then return end
                local LibKeyBound = LibStub("LibKeyBound-1.0", true)
                if LibKeyBound then LibKeyBound:Toggle()
                elseif QuickKeybindFrame then ShowUIPanel(QuickKeybindFrame) end
            end)
            keybindModeBtn:SetPoint("TOPLEFT", 4, -4)
        end)

        relayout()
    end  -- End BuildMasterSettingsTab

    -- Per-Bar Overrides moved to QUI Edit Mode settings panel

    local function BuildExtraButtonsTab(tabContent)
        local y = -15
        local PAD = PADDING
        local FORM_ROW = 32

        -- Set search context
        GUI:SetSearchContext({tabIndex = 8, tabName = "Action Bars", subTabIndex = 4, subTabName = "Extra Buttons"})

        -- Refresh callback
        local function RefreshExtraButtons()
            if _G.QUI_RefreshExtraButtons then
                _G.QUI_RefreshExtraButtons()
            end
        end

        -- Description
        local descLabel = GUI:CreateLabel(tabContent,
            "Customize the Extra Action Button (boss encounters, quests) and Zone Ability Button (garrison, covenant, zone abilities) separately.",
            11, C.textMuted)
        descLabel:SetPoint("TOPLEFT", PAD, y)
        descLabel:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        descLabel:SetJustifyH("LEFT")
        descLabel:SetWordWrap(true)
        descLabel:SetHeight(30)
        y = y - 40

        -- Toggle Movers Button
        local moverBtn = GUI:CreateButton(tabContent, "Toggle Position Movers", 200, 28, function()
            if _G.QUI_ToggleExtraButtonMovers then
                _G.QUI_ToggleExtraButtonMovers()
            end
        end)
        moverBtn:SetPoint("TOPLEFT", PAD, y)
        y = y - 35

        local moverTip = GUI:CreateLabel(tabContent,
            "Click to show draggable movers. Drag to position, use sliders for fine-tuning.",
            10, C.textMuted)
        moverTip:SetPoint("TOPLEFT", PAD, y)
        moverTip:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        moverTip:SetJustifyH("LEFT")
        y = y - 25

        -- Extra Action Button settings moved to Edit Mode settings panel.

        -- Zone Ability Button settings moved to Edit Mode settings panel.

        tabContent:SetHeight(math.abs(y) + 50)
    end  -- End BuildExtraButtonsTab

    local PAD = PADDING

    GUI:SetSearchContext({tabIndex = 8, tabName = "Action Bars"})

    -- Host frame for sub-tabs
    local subTabHost = CreateFrame("Frame", nil, content)
    subTabHost:SetPoint("TOPLEFT", 0, -8)
    subTabHost:SetPoint("BOTTOMRIGHT", 0, 0)

    GUI:CreateSubTabs(subTabHost, {
        {name = "General", builder = BuildMasterSettingsTab},
        {name = "Mouseover Hide", builder = BuildMouseoverHideTab},
    })

    content:SetHeight(700)
    return scroll, content
end

---------------------------------------------------------------------------
-- SUB-TAB: Totem Bar (Blizzard TotemFrame — any class the client uses it for)
---------------------------------------------------------------------------
BuildTotemBarTab = function(tabContent)
    local PAD = PADDING
    local FORM_ROW = 32
    local y = -15

    local core = GetCore()
    local db = core and core.db and core.db.profile and core.db.profile.totemBar

    -- Set search context for widget auto-registration
    GUI:SetSearchContext({tabIndex = 8, tabName = "Action Bars", subTabIndex = 5, subTabName = "Totem Bar"})

    if not db then
        local notice = GUI:CreateLabel(tabContent, "Totem Bar settings not available. Try /rl.", 12, C.textMuted)
        notice:SetPoint("TOPLEFT", PAD, y)
        notice:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        notice:SetJustifyH("LEFT")
        tabContent:SetHeight(60)
        return
    end

    local function RefreshTotemBar()
        if _G.QUI_RefreshTotemBar then
            _G.QUI_RefreshTotemBar()
        end
    end

    -- =====================================================
    -- ENABLE & LOCK
    -- =====================================================
    local enableHeader = GUI:CreateSectionHeader(tabContent, "Totem Bar")
    enableHeader:SetPoint("TOPLEFT", PAD, y)
    y = y - enableHeader.gap

    local enableCB = GUI:CreateFormCheckbox(tabContent, "Enable Totem Bar", "enabled", db, RefreshTotemBar)
    enableCB:SetPoint("TOPLEFT", PAD, y)
    enableCB:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
    y = y - FORM_ROW

    local lockCB = GUI:CreateFormCheckbox(tabContent, "Lock Position", "locked", db)
    lockCB:SetPoint("TOPLEFT", PAD, y)
    lockCB:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
    y = y - FORM_ROW

    -- Preview toggle (pill-shaped, matches Debuff/Buff Preview style)
    local previewContainer = CreateFrame("Frame", nil, tabContent)
    previewContainer:SetHeight(FORM_ROW)
    previewContainer:SetPoint("TOPLEFT", PAD, y)
    previewContainer:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)

    local previewLabel = previewContainer:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    previewLabel:SetPoint("LEFT", 0, 0)
    previewLabel:SetText("Preview")
    previewLabel:SetTextColor(C.text[1], C.text[2], C.text[3], 1)

    local previewTrack = CreateFrame("Button", nil, previewContainer, "BackdropTemplate")
    previewTrack:SetSize(40, 20)
    previewTrack:SetPoint("LEFT", previewContainer, "LEFT", 180, 0)
    local pxCore = GetCore()
    local pxTrack = (pxCore and pxCore.GetPixelSize) and pxCore:GetPixelSize(previewTrack) or 1
    previewTrack:SetBackdrop({bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = pxTrack})

    local previewThumb = CreateFrame("Frame", nil, previewTrack, "BackdropTemplate")
    previewThumb:SetSize(16, 16)
    local pxThumb = (pxCore and pxCore.GetPixelSize) and pxCore:GetPixelSize(previewThumb) or 1
    previewThumb:SetBackdrop({bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = pxThumb})
    previewThumb:SetBackdropColor(0.95, 0.95, 0.95, 1)
    previewThumb:SetBackdropBorderColor(0.85, 0.85, 0.85, 1)
    previewThumb:SetFrameLevel(previewTrack:GetFrameLevel() + 1)

    local isPreviewOn = false
    local function UpdatePreviewToggle(on)
        if on then
            previewTrack:SetBackdropColor(C.accent[1], C.accent[2], C.accent[3], 1)
            previewTrack:SetBackdropBorderColor(C.accent[1]*0.8, C.accent[2]*0.8, C.accent[3]*0.8, 1)
            previewThumb:ClearAllPoints()
            previewThumb:SetPoint("RIGHT", previewTrack, "RIGHT", -2, 0)
        else
            previewTrack:SetBackdropColor(0.15, 0.18, 0.22, 1)
            previewTrack:SetBackdropBorderColor(0.12, 0.14, 0.18, 1)
            previewThumb:ClearAllPoints()
            previewThumb:SetPoint("LEFT", previewTrack, "LEFT", 2, 0)
        end
    end
    UpdatePreviewToggle(isPreviewOn)

    previewTrack:SetScript("OnClick", function()
        isPreviewOn = not isPreviewOn
        UpdatePreviewToggle(isPreviewOn)
        if _G.QUI_ToggleTotemBarPreview then
            _G.QUI_ToggleTotemBarPreview()
        end
    end)
    y = y - FORM_ROW

    local info = GUI:CreateLabel(tabContent, "Right-click a totem to dismiss when allowed. Preview shows mock icons for positioning (drag to reposition).", 11, C.textMuted)
    info:SetPoint("TOPLEFT", PAD, y)
    info:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
    info:SetJustifyH("LEFT")
    info:SetWordWrap(true)
    tabContent:SetHeight(math.abs(y) + 40)
end

---------------------------------------------------------------------------
-- Export
---------------------------------------------------------------------------
ns.QUI_ActionBarsOptions = {
    CreateActionBarsPage = CreateActionBarsPage
}
