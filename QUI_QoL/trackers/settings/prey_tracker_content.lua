--[[
    QUI Prey Tracker Options
    Options sub-tab for the Prey Tracker module. Migrated to V3 body pattern.
]]

local _, ns = ...
local QUI = QUI
local GUI = QUI.GUI
local C = GUI.Colors
local Shared = ns.QUI_Options
local Settings = ns.Settings
local Registry = Settings and Settings.Registry
local Schema = Settings and Settings.Schema
local RenderAdapters = Settings and Settings.RenderAdapters

local PAD = (Shared and Shared.PADDING) or 15
local HEADER_GAP = 26
local SECTION_GAP = 14

local function GetDB()
    local db = Shared.GetDB()
    return db and db.preyTracker
end

local function MakeLayout(content)
    local y = -10
    local L = {}
    function L.headerAt(text)
        local h = Shared.CreateAccentDotLabel(content, text, y)
        h:ClearAllPoints()
        h:SetPoint("TOPLEFT", content, "TOPLEFT", PAD, y)
        h:SetPoint("TOPRIGHT", content, "TOPRIGHT", -PAD, y)
        y = y - HEADER_GAP
    end
    function L.sectionAt()
        local c = Shared.CreateSettingsCardGroup(content, y)
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
    function L.finish()
        content:SetHeight(math.abs(y) + 10)
        return content:GetHeight()
    end
    return L
end

local function row(parent, label, widget, desc)
    return Shared.BuildSettingRow(parent, label, widget, desc)
end

local function placeHint(L, parent, text)
    local f = CreateFrame("Frame", nil, parent)
    local lbl = GUI:CreateLabel(f, text, 11, C.textMuted)
    lbl:SetPoint("TOPLEFT", f, "TOPLEFT", 6, 0)
    lbl:SetPoint("RIGHT", f, "RIGHT", -6, 0)
    lbl:SetJustifyH("LEFT")
    lbl:SetWordWrap(true)
    L.placeCustom(f, 22)
end

ns.QUI_PreyTrackerOptions = {}

function ns.QUI_PreyTrackerOptions.BuildPreyTrackerContent(content)
    local db = GetDB()

    -- The V2 renderer (ResolveFeatureSearchContext in options/shared.lua)
    -- already populated the search context with tileId="gameplay" /
    -- subPageIndex=8 / featureId="preyTrackerPage" before invoking this
    -- builder. Calling SetSearchContext here would wipe those route fields.

    if not db then
        local noData = GUI:CreateLabel(content, "Prey Tracker settings are not available. Please reload the UI.", 12, C.textMuted)
        noData:SetPoint("TOPLEFT", PAD, -20)
        content:SetHeight(80)
        return
    end

    local function Refresh()
        if _G.QUI_RefreshPreyTracker then _G.QUI_RefreshPreyTracker() end
    end

    local function RefreshPreview()
        Refresh()
        if _G.QUI_TogglePreyTrackerPreview then
            _G.QUI_TogglePreyTrackerPreview(true)
        end
    end

    local L = MakeLayout(content)

    ---------------------------------------------------------------------------
    -- GENERAL
    ---------------------------------------------------------------------------
    L.headerAt("General")
    local sGen = L.sectionAt()
    local genEnableW = GUI:CreateFormCheckbox(sGen.frame, nil, "enabled", db, Refresh,
        { description = "Enable the prey tracker bar that shows your hunt progress from the Midnight prey system. Requires an active prey hunt quest." })
    sGen.AddRow(row(sGen.frame, "Enable Prey Tracker", genEnableW))
    L.closeSection(sGen)
    placeHint(L, content, "Tracks prey hunting progress from the Midnight prey system. Requires an active prey hunt quest.")

    -- Dimensions card (Width / Height / Border).
    local sDim = L.sectionAt()
    local dimWidthW = GUI:CreateFormSlider(sDim.frame, nil, 100, 500, 1, "width", db, RefreshPreview,
        { description = "Width of the prey tracker bar in pixels." })
    local dimHeightW = GUI:CreateFormSlider(sDim.frame, nil, 10, 40, 1, "height", db, RefreshPreview,
        { description = "Height of the prey tracker bar in pixels." })
    sDim.AddRow(
        row(sDim.frame, "Bar Width", dimWidthW),
        row(sDim.frame, "Bar Height", dimHeightW)
    )
    local dimBorderW = GUI:CreateFormSlider(sDim.frame, nil, 0, 3, 1, "borderSize", db, RefreshPreview,
        { description = "Thickness of the bar's border in pixels. 0 removes the border entirely." })
    sDim.AddRow(row(sDim.frame, "Border Size", dimBorderW))
    L.closeSection(sDim)

    ---------------------------------------------------------------------------
    -- BAR APPEARANCE
    ---------------------------------------------------------------------------
    L.headerAt("Bar Appearance")
    local sBA = L.sectionAt()

    local textureList = Shared.GetTextureList()
    local baTexW = GUI:CreateFormDropdown(sBA.frame, nil, textureList, "texture", db, RefreshPreview,
        { description = "Status bar texture used to fill the prey tracker bar." })

    -- Color mode dropdown: not bound to a single DB key — maps to two booleans.
    local colorModeOptions = {
        { value = "accent", text = "Accent Color" },
        { value = "class", text = "Class Color" },
        { value = "custom", text = "Custom Color" },
    }
    local function GetColorMode()
        if db.barUseClassColor then return "class"
        elseif db.barUseAccentColor then return "accent"
        else return "custom"
        end
    end
    local colorModeDropdown = GUI:CreateFormDropdown(sBA.frame, nil, colorModeOptions, nil, nil, nil,
        { description = "How the prey tracker bar is colored. Accent uses the addon accent, Class uses your class color, Custom uses the picker below." })
    local dropdownBtn
    for _, child in ipairs({ colorModeDropdown:GetChildren() }) do
        if child.GetObjectType and child:GetObjectType() == "Button" then
            dropdownBtn = child
            break
        end
    end
    if dropdownBtn then
        local currentMode = GetColorMode()
        for _, opt in ipairs(colorModeOptions) do
            if opt.value == currentMode then
                local btnText = dropdownBtn:GetFontString()
                if btnText then btnText:SetText(opt.text) end
                break
            end
        end
        dropdownBtn:SetScript("OnClick", function(self)
            local menuItems = {}
            for _, opt in ipairs(colorModeOptions) do
                table.insert(menuItems, {
                    text = opt.text,
                    checked = (opt.value == GetColorMode()),
                    func = function()
                        db.barUseClassColor = (opt.value == "class")
                        db.barUseAccentColor = (opt.value == "accent")
                        local btnText2 = self:GetFontString()
                        if btnText2 then btnText2:SetText(opt.text) end
                        RefreshPreview()
                    end,
                })
            end
            if GUI.ShowDropdownMenu then
                GUI:ShowDropdownMenu(self, menuItems)
            end
        end)
    end

    sBA.AddRow(
        row(sBA.frame, "Bar Texture", baTexW),
        row(sBA.frame, "Bar Color Mode", colorModeDropdown)
    )

    local baCustomColorW = GUI:CreateFormColorPicker(sBA.frame, nil, "barColor", db, RefreshPreview, nil,
        { description = "Custom bar fill color used when Bar Color Mode is set to Custom Color." })
    local baBgOverrideW = GUI:CreateFormCheckbox(sBA.frame, nil, "barBgOverride", db, RefreshPreview,
        { description = "Use a custom color for the bar background instead of the default subtle fill." })
    sBA.AddRow(
        row(sBA.frame, "Custom Bar Color", baCustomColorW),
        row(sBA.frame, "Override Background Color", baBgOverrideW)
    )

    local baBgColorW = GUI:CreateFormColorPicker(sBA.frame, nil, "barBackgroundColor", db, RefreshPreview, nil,
        { description = "Background color applied when the override above is enabled." })
    sBA.AddRow(row(sBA.frame, "Background Color", baBgColorW))
    L.closeSection(sBA)

    ---------------------------------------------------------------------------
    -- BORDER
    ---------------------------------------------------------------------------
    L.headerAt("Border")
    local sBD = L.sectionAt()
    if ns.QUI_BorderControl then
        local srcW, colW = ns.QUI_BorderControl.Attach(GUI, sBD.frame, db, "", RefreshPreview,
            { label = "Border Color Source", colorLabel = "Border Color" })
        sBD.AddRow(row(sBD.frame, "Border Color Source", srcW), row(sBD.frame, "Border Color", colW))
    end
    L.closeSection(sBD)

    ---------------------------------------------------------------------------
    -- TEXT & DISPLAY
    ---------------------------------------------------------------------------
    L.headerAt("Text & Display")
    local sTX = L.sectionAt()
    local txShowW = GUI:CreateFormCheckbox(sTX.frame, nil, "showText", db, RefreshPreview,
        { description = "Display the progress text on top of the prey tracker bar." })

    local textFormatOptions = {
        { value = "stage_pct", text = "Stage 3 — 67%" },
        { value = "pct_only", text = "67%" },
        { value = "stage_only", text = "Stage 3" },
        { value = "name_pct", text = "Prey Name — 67%" },
    }
    local txFmtW = GUI:CreateFormDropdown(sTX.frame, nil, textFormatOptions, "textFormat", db, RefreshPreview,
        { description = "Format of the overlay text. Choose whether to show the stage, the percentage, the prey name, or a combination." })
    sTX.AddRow(
        row(sTX.frame, "Show Text", txShowW),
        row(sTX.frame, "Text Format", txFmtW)
    )

    local txSizeW = GUI:CreateFormSlider(sTX.frame, nil, 8, 18, 1, "textSize", db, RefreshPreview,
        { description = "Font size used for the progress text." })
    local txTicksW = GUI:CreateFormCheckbox(sTX.frame, nil, "showTickMarks", db, RefreshPreview,
        { description = "Show tick marks on the bar at the stage boundaries configured by Tick Style." })
    sTX.AddRow(
        row(sTX.frame, "Font Size", txSizeW),
        row(sTX.frame, "Show Tick Marks", txTicksW)
    )

    local tickStyleOptions = {
        { value = "thirds", text = "Thirds (33% / 66%)" },
        { value = "quarters", text = "Quarters (25% / 50% / 75%)" },
    }
    local txTickStyleW = GUI:CreateFormDropdown(sTX.frame, nil, tickStyleOptions, "tickStyle", db, RefreshPreview,
        { description = "Where tick marks are drawn. Thirds matches prey stages; Quarters is purely visual." })
    local txSparkW = GUI:CreateFormCheckbox(sTX.frame, nil, "showSpark", db, RefreshPreview,
        { description = "Show a bright spark at the leading edge of the filled portion of the bar." })
    sTX.AddRow(
        row(sTX.frame, "Tick Style", txTickStyleW),
        row(sTX.frame, "Show Spark", txSparkW)
    )
    L.closeSection(sTX)

    ---------------------------------------------------------------------------
    -- SOUNDS
    ---------------------------------------------------------------------------
    L.headerAt("Sounds")
    local sSnd = L.sectionAt()
    local sndEnableW = GUI:CreateFormCheckbox(sSnd.frame, nil, "soundEnabled", db, nil,
        { description = "Master toggle for prey tracker audio cues. Individual stage sounds below won't play unless this is enabled." })
    local sndS2W = GUI:CreateFormCheckbox(sSnd.frame, nil, "soundStage2", db, nil,
        { description = "Play a sound when you reach hunt stage 2." })
    sSnd.AddRow(
        row(sSnd.frame, "Enable Sounds", sndEnableW),
        row(sSnd.frame, "Stage 2 Sound", sndS2W)
    )

    local sndS3W = GUI:CreateFormCheckbox(sSnd.frame, nil, "soundStage3", db, nil,
        { description = "Play a sound when you reach hunt stage 3." })
    local sndS4W = GUI:CreateFormCheckbox(sSnd.frame, nil, "soundStage4", db, nil,
        { description = "Play a sound when you reach hunt stage 4." })
    sSnd.AddRow(
        row(sSnd.frame, "Stage 3 Sound", sndS3W),
        row(sSnd.frame, "Stage 4 Sound", sndS4W)
    )

    local sndCompleteW = GUI:CreateFormCheckbox(sSnd.frame, nil, "completionSound", db, nil,
        { description = "Play a sound when the hunt finishes and the prey spawns." })
    sSnd.AddRow(row(sSnd.frame, "Completion Sound", sndCompleteW))
    L.closeSection(sSnd)

    ---------------------------------------------------------------------------
    -- AMBUSH ALERTS
    ---------------------------------------------------------------------------
    L.headerAt("Ambush Alerts")
    local sAmb = L.sectionAt()
    local ambEnableW = GUI:CreateFormCheckbox(sAmb.frame, nil, "ambushAlertEnabled", db, nil,
        { description = "Show an alert when the prey enters an ambushable state so you can position for the takedown." })
    local ambSoundW = GUI:CreateFormCheckbox(sAmb.frame, nil, "ambushSoundEnabled", db, nil,
        { description = "Play a distinct sound when the ambush alert fires." })
    sAmb.AddRow(
        row(sAmb.frame, "Enable Ambush Alerts", ambEnableW),
        row(sAmb.frame, "Ambush Sound", ambSoundW)
    )

    local ambGlowW = GUI:CreateFormCheckbox(sAmb.frame, nil, "ambushGlowEnabled", db, nil,
        { description = "Flash a glow effect on the prey tracker bar when an ambush is available." })
    local ambDurW = GUI:CreateFormSlider(sAmb.frame, nil, 2, 15, 1, "ambushDuration", db, nil,
        { description = "How long the ambush glow remains visible, in seconds." })
    sAmb.AddRow(
        row(sAmb.frame, "Ambush Glow Effect", ambGlowW),
        row(sAmb.frame, "Glow Duration (sec)", ambDurW)
    )
    L.closeSection(sAmb)

    ---------------------------------------------------------------------------
    -- VISIBILITY
    ---------------------------------------------------------------------------
    L.headerAt("Visibility")
    local sVis = L.sectionAt()
    local visReplaceW = GUI:CreateFormCheckbox(sVis.frame, nil, "replaceDefaultIndicator", db, function()
        if ns.QUI_PreyTracker and ns.QUI_PreyTracker.ToggleDefaultIndicator then
            ns.QUI_PreyTracker.ToggleDefaultIndicator(db.replaceDefaultIndicator)
        end
    end, { description = "Hide the default Blizzard prey indicator so only the QUI tracker is shown." })
    local visAutoHideW = GUI:CreateFormCheckbox(sVis.frame, nil, "autoHide", db, Refresh,
        { description = "Hide the bar when no prey hunt is active. Turn off to keep a placeholder bar visible at all times." })
    sVis.AddRow(
        row(sVis.frame, "Replace Default Prey Indicator", visReplaceW),
        row(sVis.frame, "Auto-Hide When No Progress", visAutoHideW)
    )

    local visInstW = GUI:CreateFormCheckbox(sVis.frame, nil, "hideInInstances", db, Refresh,
        { description = "Hide the prey tracker bar while you are inside dungeons, raids, and other instances." })
    local visZoneW = GUI:CreateFormCheckbox(sVis.frame, nil, "hideOutsidePreyZone", db, Refresh,
        { description = "Hide the bar whenever you leave the zone the current prey belongs to." })
    sVis.AddRow(
        row(sVis.frame, "Hide in Instances", visInstW),
        row(sVis.frame, "Hide Outside Prey Zone", visZoneW)
    )
    L.closeSection(sVis)

    ---------------------------------------------------------------------------
    -- HUNT SCANNER
    ---------------------------------------------------------------------------
    L.headerAt("Hunt Scanner")
    local sHS = L.sectionAt()
    local hsW = GUI:CreateFormCheckbox(sHS.frame, nil, "huntScannerEnabled", db, nil,
        { description = "Show a list of available hunts when you interact with a hunt table NPC, so you can pick the best prey at a glance." })
    sHS.AddRow(row(sHS.frame, "Enable Hunt Scanner", hsW))
    L.closeSection(sHS)
    placeHint(L, content, "Shows available hunts when visiting a hunt table NPC.")

    ---------------------------------------------------------------------------
    -- CURRENCY TRACKER
    ---------------------------------------------------------------------------
    L.headerAt("Currency Tracker")
    local sCT = L.sectionAt()
    local ctEnableW = GUI:CreateFormCheckbox(sCT.frame, nil, "currencyEnabled", db, nil,
        { description = "Add prey-related currency tracking details to the bag and currency tooltips." })
    local ctSessionW = GUI:CreateFormCheckbox(sCT.frame, nil, "currencyShowSession", db, nil,
        { description = "Include how much of each prey currency you've earned in the current play session in the tooltip." })
    sCT.AddRow(
        row(sCT.frame, "Enable Currency Tooltip", ctEnableW),
        row(sCT.frame, "Show Session Gains", ctSessionW)
    )

    local ctWeeklyW = GUI:CreateFormCheckbox(sCT.frame, nil, "currencyShowWeekly", db, nil,
        { description = "Include progress toward weekly prey currency caps in the tooltip." })
    sCT.AddRow(row(sCT.frame, "Show Weekly Progress", ctWeeklyW))
    L.closeSection(sCT)

    ---------------------------------------------------------------------------
    -- PREVIEW BUTTON
    ---------------------------------------------------------------------------
    local previewSection = CreateFrame("Frame", nil, content)
    local previewBtn = GUI:CreateButton(previewSection, "Toggle Preview", 140, 28, function()
        if _G.QUI_TogglePreyTrackerPreview then
            local state = ns.QUI_PreyTracker and ns.QUI_PreyTracker.GetState and ns.QUI_PreyTracker.GetState()
            local isPreview = state and state.isPreviewMode
            _G.QUI_TogglePreyTrackerPreview(not isPreview)
        end
    end)
    previewBtn:SetPoint("TOPLEFT", 0, -6)
    L.placeCustom(previewSection, 40)

    L.finish()
end

function ns.QUI_PreyTrackerOptions.CreatePreyTrackerPage(parent)
    local _, content = Shared.CreateScrollableContent(parent)
    ns.QUI_PreyTrackerOptions.BuildPreyTrackerContent(content)
end

if Registry and Schema and RenderAdapters
    and type(Registry.RegisterFeature) == "function"
    and type(Schema.Feature) == "function"
    and type(Schema.Section) == "function" then
    Registry:RegisterFeature(Schema.Feature({
        id = "preyTrackerPage",
        moverKey = "preyTracker",
        lookupKeys = { "preyTracker" },
        category = "gameplay",
        nav = { tileId = "gameplay", subPageIndex = 8 },
        sections = {
            Schema.Section({
                id = "settings",
                kind = "page",
                minHeight = 80,
                build = ns.QUI_PreyTrackerOptions.BuildPreyTrackerContent,
            }),
        },
        render = {
            layout = function(host, options)
                return RenderAdapters.RenderLayoutRoute(host, options and options.providerKey or "preyTracker")
            end,
        },
    }))
end
