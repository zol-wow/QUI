--[[
    QUI QoL Options - General Tab (Quality of Life tile sub-page)
    Migrated to V3 body pattern (CreateAccentDotLabel + CreateSettingsCardGroup
    + BuildSettingRow). Each registered feature shows a single section.
]]

local _, ns = ...
local QUI = QUI
local GUI = QUI.GUI
local QUICore = ns.Addon
local C = GUI.Colors
local Shared = ns.QUI_Options
local Opts = Shared
local Settings = ns.Settings
local Registry = Settings and Settings.Registry
local Schema = Settings and Settings.Schema

local PAD = (Opts and Opts.PADDING) or 15
local HEADER_GAP = 26
local SECTION_GAP = 14

local function MakeLayout(content)
    local y = -10
    local L = {}
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
    function L.intro(text)
        local frame = CreateFrame("Frame", nil, content)
        frame:ClearAllPoints()
        frame:SetPoint("TOPLEFT", content, "TOPLEFT", PAD, y)
        frame:SetPoint("TOPRIGHT", content, "TOPRIGHT", -PAD, y)
        local lbl = GUI:CreateLabel(frame, text, 11, C.textMuted)
        lbl:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
        lbl:SetPoint("RIGHT", frame, "RIGHT", 0, 0)
        lbl:SetJustifyH("LEFT")
        lbl:SetWordWrap(true)
        local approxHeight = math.max(18, math.ceil(#text / 90) * 15)
        frame:SetHeight(approxHeight)
        y = y - approxHeight - 8
        return lbl, frame
    end
    function L.placeCustom(frame, height)
        -- Defensive reparent: callers sometimes create with nil parent and
        -- rely on anchoring alone. SetParent ensures the frame is hidden /
        -- garbage-collected with the settings page rather than orphaning to
        -- UIParent and lingering on screen after the panel closes.
        frame:SetParent(content)
        frame:ClearAllPoints()
        frame:SetPoint("TOPLEFT", content, "TOPLEFT", PAD, y)
        frame:SetPoint("RIGHT", content, "RIGHT", -PAD, 0)
        frame:SetHeight(height)
        y = y - height - SECTION_GAP
    end
    function L.gap(n)
        y = y - (n or 6)
    end
    function L.finish()
        content:SetHeight(math.abs(y) + 10)
        return content:GetHeight()
    end
    return L
end

local function row(parent, label, widget, desc)
    return Opts.BuildSettingRow(parent, label, widget, desc)
end

local function ShouldBuildSection(selectedSectionKey, sectionKey)
    return selectedSectionKey == nil or selectedSectionKey == sectionKey
end

---------------------------------------------------------------------------
-- BUILDERS PER SECTION (each is its own subpage)
---------------------------------------------------------------------------

local function BuildSettingsPanel(L, db)
    if not db.general then return end
    L.headerAt(ns.L["Settings Panel"])
    local s = L.sectionAt()
    local w = GUI:CreateFormCheckbox(s.frame, nil, "showOptionTooltips", db.general, nil,
        { description = ns.L["Show a brief explanation of each setting when you hover over it in this panel."] })
    s.AddRow(row(s.frame, ns.L["Show Setting Tooltips"], w))
    L.closeSection(s)
end

local function BuildUIScale(L, db)
    if not db.general then return end

    L.headerAt(ns.L["UI Scale"])
    L.intro(ns.L["Global scale factor applied to the entire Blizzard UI. Lower values make elements smaller; the presets below pick pixel-perfect values for common resolutions."])

    local s = L.sectionAt()
    local scaleSlider = GUI:CreateFormSlider(s.frame, nil, 0.3, 2.0, 0.01,
        "uiScale", db.general, function(val)
            if InCombatLockdown() then return end
            UIParent:SetScale(val)
        end, { deferOnDrag = true, precision = 7, editWidth = 58,
              description = ns.L["Global scale factor applied to the entire Blizzard UI."] })
    s.AddRow(row(s.frame, ns.L["Global UI Scale"], scaleSlider))
    L.closeSection(s)

    local function ApplyPreset(val, name)
        if InCombatLockdown() then return end
        db.general.uiScale = val
        UIParent:SetScale(val)
        local msg = "|cff60A5FA[QUI]|r " .. ns.L["UI scale set to"] .. " " .. val
        if name then msg = msg .. " (" .. name .. ")" end
        DEFAULT_CHAT_FRAME:AddMessage(msg)
        scaleSlider.SetValue(val, true)
    end

    local function AutoScale()
        local _, height = GetPhysicalScreenSize()
        local scale = 768 / height
        scale = math.max(0.3, math.min(2.0, scale))
        ApplyPreset(scale, ns.L["Auto"])
    end

    local PRESET_HEIGHT = 86
    local presetBlock = CreateFrame("Frame", nil, nil)
    L.placeCustom(presetBlock, PRESET_HEIGHT)

    local presetLabel = GUI:CreateLabel(presetBlock, ns.L["Quick UI Scale Presets:"], 12, C.text)
    presetLabel:SetPoint("TOPLEFT", presetBlock, "TOPLEFT", 0, 0)

    local buttonContainer = CreateFrame("Frame", nil, presetBlock)
    buttonContainer:SetPoint("TOPLEFT", presetBlock, "TOPLEFT", 180, 0)
    buttonContainer:SetPoint("RIGHT", presetBlock, "RIGHT", 0, 0)
    buttonContainer:SetHeight(26)

    local BUTTON_GAP = 6
    local NUM_BUTTONS = 5
    local buttons = {}
    buttons[1] = GUI:CreateButton(buttonContainer, "1080p", 50, 26, function() ApplyPreset(0.7111111, "1080p") end)
    buttons[2] = GUI:CreateButton(buttonContainer, "1440p", 50, 26, function() ApplyPreset(0.5333333, "1440p") end)
    buttons[3] = GUI:CreateButton(buttonContainer, "1440p+", 50, 26, function() ApplyPreset(0.64, "1440p+") end)
    buttons[4] = GUI:CreateButton(buttonContainer, "4K", 50, 26, function() ApplyPreset(0.3555556, "4K") end)
    buttons[5] = GUI:CreateButton(buttonContainer, ns.L["Auto"], 50, 26, AutoScale)

    buttonContainer:SetScript("OnSizeChanged", function(self, width)
        if width and width > 0 then
            local buttonWidth = (width - (NUM_BUTTONS - 1) * BUTTON_GAP) / NUM_BUTTONS
            for i, btn in ipairs(buttons) do
                btn:SetWidth(buttonWidth)
                btn:ClearAllPoints()
                if i == 1 then
                    btn:SetPoint("LEFT", self, "LEFT", 0, 0)
                else
                    btn:SetPoint("LEFT", buttons[i - 1], "RIGHT", BUTTON_GAP, 0)
                end
            end
        end
    end)

    local tooltipData = {
        { title = "1080p",  desc = ns.L["Scale: 0.7111111\nPixel-perfect for 1920x1080"] },
        { title = "1440p",  desc = ns.L["Scale: 0.5333333\nPixel-perfect for 2560x1440"] },
        { title = "1440p+", desc = ns.L["Scale: 0.64\nQuazii's personal setting - larger and more readable.\nRequires manual adjustment for pixel perfection."] },
        { title = "4K",     desc = ns.L["Scale: 0.3555556\nPixel-perfect for 3840x2160"] },
        { title = ns.L["Auto"],   desc = ns.L["Computes pixel-perfect scale based on your resolution.\nFormula: 768 / screen height"] },
    }
    for i, btn in ipairs(buttons) do
        local data = tooltipData[i]
        btn:HookScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:AddLine(data.title, 1, 1, 1)
            GameTooltip:AddLine(data.desc, 0.8, 0.8, 0.8, true)
            GameTooltip:Show()
        end)
        btn:HookScript("OnLeave", function() GameTooltip:Hide() end)
    end

    local presetSummary = GUI:CreateLabel(presetBlock, ns.L["Hover any preset for details. 1440p+ is Quazii's personal setting."], 11, C.textMuted)
    presetSummary:SetPoint("TOPLEFT", buttonContainer, "BOTTOMLEFT", 0, -8)
    presetSummary:SetPoint("RIGHT", presetBlock, "RIGHT", 0, 0)
    presetSummary:SetJustifyH("LEFT")

    local bigPicture = GUI:CreateLabel(presetBlock,
        ns.L["UI scale is highly personal — it depends on your monitor size, resolution, and preference. If you already have a scale you like, stick with it."],
        11, C.textMuted)
    bigPicture:SetPoint("TOPLEFT", presetSummary, "BOTTOMLEFT", 0, -6)
    bigPicture:SetPoint("RIGHT", presetBlock, "RIGHT", 0, 0)
    bigPicture:SetJustifyH("LEFT")
end

local function BuildDefaultFonts(L, db)
    if not db.general then return end

    local function RefreshDefaultFonts()
        if QUICore and QUICore.RefreshAll then QUICore:RefreshAll() end
        if _G.QUI_RefreshUnitFrames then _G.QUI_RefreshUnitFrames() end
        if QUICore then
            if QUICore.UpdatePowerBar then QUICore:UpdatePowerBar() end
            if QUICore.UpdateSecondaryPowerBar then QUICore:UpdateSecondaryPowerBar() end
        end
    end
    local function RefreshDefaultTextures()
        if QUICore and QUICore.Minimap and QUICore.Minimap.Refresh then QUICore.Minimap:Refresh() end
        if _G.QUI_RefreshBuffBorders then _G.QUI_RefreshBuffBorders() end
        if ns and ns.NCDM and ns.NCDM.RefreshAll then ns.NCDM:RefreshAll() end
        if QUICore and QUICore.Loot and QUICore.Loot.RefreshColors then QUICore.Loot:RefreshColors() end
        C_Timer.After(0.1, function()
            if QUICore and QUICore.ApplyViewerLayout then
                local essV = _G.QUI_GetCDMViewerFrame and _G.QUI_GetCDMViewerFrame("essential")
                local utilV = _G.QUI_GetCDMViewerFrame and _G.QUI_GetCDMViewerFrame("utility")
                if essV then QUICore:ApplyViewerLayout(essV) end
                if utilV then QUICore:ApplyViewerLayout(utilV) end
            end
        end)
    end
    local function RefreshDefaultAppearance()
        RefreshDefaultFonts()
        RefreshDefaultTextures()
    end

    L.headerAt(ns.L["Default Font Settings"])
    L.intro(ns.L["These settings apply throughout the UI. Individual elements with their own font options will override these defaults."])

    local fontList = {}
    local LSM = ns.LSM
    if LSM then
        for name in pairs(LSM:HashTable("font")) do
            table.insert(fontList, { value = name, text = name })
        end
        table.sort(fontList, function(a, b) return a.text < b.text end)
    else
        fontList = { { value = "Friz Quadrata TT", text = "Friz Quadrata TT" } }
    end
    local outlineOptions = {
        { value = "", text = ns.L["None"] },
        { value = "OUTLINE", text = ns.L["Outline"] },
        { value = "THICKOUTLINE", text = ns.L["Thick Outline"] },
    }

    local s = L.sectionAt()
    local fontW = GUI:CreateFormDropdown(s.frame, nil, fontList, "font", db.general, RefreshDefaultFonts,
        { description = ns.L["Font used as the default across QUI-managed text elements that don't have their own font override."] })
    local outlineW = GUI:CreateFormDropdown(s.frame, nil, outlineOptions, "fontOutline", db.general, RefreshDefaultFonts,
        { description = ns.L["Default font outline applied to QUI-managed text. Outline helps readability against busy backgrounds."] })
    s.AddRow(row(s.frame, ns.L["Default Font"], fontW), row(s.frame, ns.L["Font Outline"], outlineW))

    local sctW = GUI:CreateFormCheckbox(s.frame, nil, "overrideSCTFont", db.general, RefreshDefaultFonts,
        { description = ns.L["Apply the QUI default font to Blizzard's floating combat text numbers."] })
    local blizW = GUI:CreateFormCheckbox(s.frame, nil, "applyGlobalFontToBlizzard", db.general, RefreshDefaultAppearance,
        { description = ns.L["Replace Blizzard's default UI fonts with the QUI default font so the whole client shares the same typography."] })
    s.AddRow(row(s.frame, ns.L["Override Scrolling Combat Text Font"], sctW), row(s.frame, ns.L["Apply Font to Blizzard UI"], blizW))
    L.closeSection(s)
end

local function BuildFPSPreset(L, db)
    L.headerAt(ns.L["Quazii Recommended FPS Settings"])
    L.intro(ns.L["Apply Quazii's optimized graphics settings for competitive play. Your current settings are saved when you click Apply — use Restore Previous Settings to revert anytime. Clicking Apply again overwrites the backup."])

    local btnBlock = CreateFrame("Frame", nil, nil)
    L.placeCustom(btnBlock, 60)

    local restoreFpsBtn
    local fpsStatusText

    local function UpdateFPSStatus()
        local _, matched, total = Shared.CheckCVarsMatch()
        if matched >= 50 then
            fpsStatusText:SetText(ns.L["Settings: All applied"])
            fpsStatusText:SetTextColor(C.accent[1], C.accent[2], C.accent[3], 1)
        else
            fpsStatusText:SetText(string.format(ns.L["Settings: %1$d/%2$d match"], matched, total))
            fpsStatusText:SetTextColor(C.textMuted[1], C.textMuted[2], C.textMuted[3], 1)
        end
    end

    local applyFpsBtn = GUI:CreateButton(btnBlock, ns.L["Apply FPS Settings"], 180, 28, function()
        Shared.ApplyQuaziiFPSSettings()
        restoreFpsBtn:SetAlpha(1)
        restoreFpsBtn:Enable()
        UpdateFPSStatus()
    end)
    applyFpsBtn:SetPoint("TOPLEFT", btnBlock, "TOPLEFT", 0, 0)
    applyFpsBtn:SetPoint("RIGHT", btnBlock, "CENTER", -5, 0)

    restoreFpsBtn = GUI:CreateButton(btnBlock, ns.L["Restore Previous Settings"], 180, 28, function()
        if Shared.RestorePreviousFPSSettings() then
            restoreFpsBtn:SetAlpha(0.5)
            restoreFpsBtn:Disable()
        end
        UpdateFPSStatus()
    end)
    restoreFpsBtn:SetPoint("LEFT", btnBlock, "CENTER", 5, 0)
    restoreFpsBtn:SetPoint("TOP", applyFpsBtn, "TOP", 0, 0)
    restoreFpsBtn:SetPoint("RIGHT", btnBlock, "RIGHT", 0, 0)

    fpsStatusText = GUI:CreateLabel(btnBlock, "", 11, C.accent)
    fpsStatusText:SetPoint("TOPLEFT", applyFpsBtn, "BOTTOMLEFT", 0, -8)

    if not db.fpsBackup then
        restoreFpsBtn:SetAlpha(0.5)
        restoreFpsBtn:Disable()
    end
    UpdateFPSStatus()
end

local function BuildCombatText(L, db)
    local combatTextDB = db and db.combatText
    if not combatTextDB then return end

    local function RefreshCombatText()
        if _G.QUI_RefreshCombatText then _G.QUI_RefreshCombatText() end
    end

    L.headerAt(ns.L["Combat Status Text Indicator"])
    L.intro(ns.L["Displays '+Combat' or '-Combat' text on screen when entering or leaving combat. Useful for Shadowmeld skips."])

    local previewBlock = CreateFrame("Frame", nil, nil)
    L.placeCustom(previewBlock, 32)
    local previewEnterBtn = GUI:CreateButton(previewBlock, ns.L["Preview +Combat"], 140, 28, function()
        if _G.QUI_PreviewCombatText then _G.QUI_PreviewCombatText("+Combat") end
    end)
    previewEnterBtn:SetPoint("TOPLEFT", previewBlock, "TOPLEFT", 0, 0)
    previewEnterBtn:SetPoint("RIGHT", previewBlock, "CENTER", -5, 0)
    local previewLeaveBtn = GUI:CreateButton(previewBlock, ns.L["Preview -Combat"], 140, 28, function()
        if _G.QUI_PreviewCombatText then _G.QUI_PreviewCombatText("-Combat") end
    end)
    previewLeaveBtn:SetPoint("LEFT", previewBlock, "CENTER", 5, 0)
    previewLeaveBtn:SetPoint("TOP", previewEnterBtn, "TOP", 0, 0)
    previewLeaveBtn:SetPoint("RIGHT", previewBlock, "RIGHT", 0, 0)

    local s = L.sectionAt()
    local enableW = GUI:CreateFormCheckbox(s.frame, nil, "enabled", combatTextDB, RefreshCombatText,
        { description = ns.L["Show '+Combat' and '-Combat' floating text when combat starts and ends."] })
    local displayW = GUI:CreateFormSlider(s.frame, nil, 0.3, 3.0, 0.1, "displayTime", combatTextDB, RefreshCombatText,
        { description = ns.L["How long the combat text stays fully visible before starting to fade, in seconds."] })
    s.AddRow(row(s.frame, ns.L["Enable Combat Text"], enableW), row(s.frame, ns.L["Display Time (sec)"], displayW))

    local fadeW = GUI:CreateFormSlider(s.frame, nil, 0.1, 1.0, 0.05, "fadeTime", combatTextDB, RefreshCombatText,
        { description = ns.L["How long the fade-out animation takes after the display time elapses, in seconds."] })
    local sizeW = GUI:CreateFormSlider(s.frame, nil, 12, 48, 1, "fontSize", combatTextDB, RefreshCombatText,
        { description = ns.L["Font size of the combat text."] })
    s.AddRow(row(s.frame, ns.L["Fade Duration (sec)"], fadeW), row(s.frame, ns.L["Font Size"], sizeW))

    local fontList = Shared.GetFontList()
    local combatTextFontDropdown
    local useCustomFontCheck = GUI:CreateFormCheckbox(s.frame, nil, "useCustomFont", combatTextDB, function(val)
        RefreshCombatText()
        if combatTextFontDropdown and combatTextFontDropdown.SetEnabled then
            combatTextFontDropdown:SetEnabled(val)
        end
    end, { description = ns.L["Use a custom font for the combat text instead of inheriting the global QUI default font."] })
    combatTextFontDropdown = GUI:CreateFormDropdown(s.frame, nil, fontList, "font", combatTextDB, RefreshCombatText,
        { description = ns.L["Custom font used for the combat text when Use Custom Font is enabled."] })
    if combatTextFontDropdown.SetEnabled then
        combatTextFontDropdown:SetEnabled(combatTextDB.useCustomFont == true)
    end
    s.AddRow(row(s.frame, ns.L["Use Custom Font"], useCustomFontCheck), row(s.frame, ns.L["Font"], combatTextFontDropdown))

    local xW = GUI:CreateFormSlider(s.frame, nil, -2000, 2000, 1, "xOffset", combatTextDB, RefreshCombatText,
        { description = ns.L["Horizontal pixel offset of the combat text from the screen center."] })
    local yW = GUI:CreateFormSlider(s.frame, nil, -2000, 2000, 1, "yOffset", combatTextDB, RefreshCombatText,
        { description = ns.L["Vertical pixel offset of the combat text from the screen center."] })
    s.AddRow(row(s.frame, ns.L["X Position Offset"], xW), row(s.frame, ns.L["Y Position Offset"], yW))

    local enterColorW = GUI:CreateFormColorPicker(s.frame, nil, "enterCombatColor", combatTextDB, RefreshCombatText, nil,
        { description = ns.L["Color of the '+Combat' text shown when entering combat."] })
    local leaveColorW = GUI:CreateFormColorPicker(s.frame, nil, "leaveCombatColor", combatTextDB, RefreshCombatText, nil,
        { description = ns.L["Color of the '-Combat' text shown when leaving combat."] })
    s.AddRow(row(s.frame, ns.L["+Combat Text Color"], enterColorW), row(s.frame, ns.L["-Combat Text Color"], leaveColorW))
    L.closeSection(s)
end

local function BuildAutomation(L, generalDB)
    if not generalDB then return end

    L.headerAt(ns.L["Automation"])
    L.intro(ns.L["Toggle quality-of-life automation features. These run silently in the background."])

    local s = L.sectionAt()
    local sellW = GUI:CreateFormCheckbox(s.frame, nil, "sellJunk", generalDB, nil,
        { description = ns.L["Automatically sell grey-quality junk items in your bags when you open a merchant window."] })
    local repairOptions = {
        { value = "off", text = ns.L["Off"] },
        { value = "personal", text = ns.L["Personal Gold"] },
        { value = "guild", text = ns.L["Guild Bank (fallback to personal)"] },
    }
    local repairW = GUI:CreateFormDropdown(s.frame, nil, repairOptions, "autoRepair", generalDB, nil,
        { description = ns.L["Automatically repair durability when you open a repair merchant. Guild mode tries guild bank first."] })
    s.AddRow(row(s.frame, ns.L["Sell Junk Items at Vendors"], sellW), row(s.frame, ns.L["Auto Repair at Vendors"], repairW))

    local fastLootW = GUI:CreateFormCheckbox(s.frame, nil, "fastAutoLoot", generalDB, nil,
        { description = ns.L["Speed up auto-loot by moving items as fast as the client allows, skipping Blizzard's default per-tick delay."] })
    local inviteOptions = {
        { value = "off", text = ns.L["Off"] },
        { value = "all", text = ns.L["Everyone"] },
        { value = "friends", text = ns.L["Friends & BNet Only"] },
        { value = "guild", text = ns.L["Guild Members Only"] },
        { value = "both", text = ns.L["Friends & Guild"] },
    }
    local inviteW = GUI:CreateFormDropdown(s.frame, nil, inviteOptions, "autoAcceptInvites", generalDB, nil,
        { description = ns.L["Automatically accept incoming party/raid invites from the chosen set of senders."] })
    s.AddRow(row(s.frame, ns.L["Fast Auto Loot"], fastLootW), row(s.frame, ns.L["Auto Accept Party Invites"], inviteW))

    local roleW = GUI:CreateFormCheckbox(s.frame, nil, "autoRoleAccept", generalDB, nil,
        { description = ns.L["Automatically confirm role checks in LFG using the role you already had selected."] })
    local questW = GUI:CreateFormCheckbox(s.frame, nil, "autoAcceptQuest", generalDB, nil,
        { description = ns.L["Automatically accept quests from NPCs without requiring a click."] })
    s.AddRow(row(s.frame, ns.L["Auto Accept Role Check"], roleW), row(s.frame, ns.L["Auto Accept Quests"], questW))

    local turnInW = GUI:CreateFormCheckbox(s.frame, nil, "autoTurnInQuest", generalDB, nil,
        { description = ns.L["Automatically hand in completed quests and pick the only available reward when applicable."] })
    local gossipW = GUI:CreateFormCheckbox(s.frame, nil, "autoSelectGossip", generalDB, nil,
        { description = ns.L["When an NPC gossip has a single option, pick it automatically so you skip the popup."] })
    s.AddRow(row(s.frame, ns.L["Auto Turn-In Quests"], turnInW), row(s.frame, ns.L["Auto Select Single Gossip Option"], gossipW))

    local pauseW = GUI:CreateFormCheckbox(s.frame, nil, "questHoldShift", generalDB, nil,
        { description = ns.L["Hold Shift while interacting to temporarily disable the quest and gossip automations above."] })
    local keyW = GUI:CreateFormCheckbox(s.frame, nil, "autoInsertKey", generalDB, nil,
        { description = ns.L["Automatically place your Mythic+ keystone into the font of power when you open the keystone window."] })
    s.AddRow(row(s.frame, ns.L["Hold Shift to Pause Quest/Gossip Automation"], pauseW), row(s.frame, ns.L["Auto Insert M+ Keys"], keyW))

    local logMW = GUI:CreateFormCheckbox(s.frame, nil, "autoCombatLog", generalDB, function()
        if _G.QUI_RefreshAutoCombatLogging then _G.QUI_RefreshAutoCombatLogging() end
    end, { description = ns.L["Turn on combat logging automatically when a Mythic+ run starts, and off when it ends."] })
    local logRW = GUI:CreateFormCheckbox(s.frame, nil, "autoCombatLogRaid", generalDB, function()
        if _G.QUI_RefreshAutoCombatLogging then _G.QUI_RefreshAutoCombatLogging() end
    end, { description = ns.L["Turn on combat logging automatically when you zone into a raid instance."] })
    s.AddRow(row(s.frame, ns.L["Auto Combat Log in M+"], logMW), row(s.frame, ns.L["Auto Combat Log in Raids"], logRW))

    local telW = GUI:CreateFormCheckbox(s.frame, nil, "mplusTeleportEnabled", generalDB, nil,
        { description = ns.L["Allow clicking on a dungeon icon in the Mythic+ UI to cast its teleport spell if you have it."] })
    local delW = GUI:CreateFormCheckbox(s.frame, nil, "autoDeleteConfirm", generalDB, nil,
        { description = ns.L["Pre-fill the word DELETE into the confirmation box when destroying a rare or higher item."] })
    s.AddRow(row(s.frame, ns.L["Click-to-Teleport on M+ Tab"], telW), row(s.frame, ns.L["Auto-Fill DELETE Confirmation Text"], delW))

    local ahW = GUI:CreateFormCheckbox(s.frame, nil, "auctionHouseExpansionFilter", generalDB, nil,
        { description = ns.L["Automatically toggle the current expansion filter when you open the Auction House so you only see modern items."] })
    local coW = GUI:CreateFormCheckbox(s.frame, nil, "craftingOrderExpansionFilter", generalDB, nil,
        { description = ns.L["Automatically toggle the current expansion filter when you open the Crafting Orders window."] })
    s.AddRow(row(s.frame, ns.L["Auto-Enable AH Expansion Filter"], ahW), row(s.frame, ns.L["Auto-Enable Crafting Orders Filter"], coW))
    L.closeSection(s)
end

local function BuildPopupBlocker(L, generalDB)
    if not generalDB then return end
    if type(generalDB.popupBlocker) ~= "table" then generalDB.popupBlocker = {} end
    local popupDB = generalDB.popupBlocker

    L.headerAt(ns.L["Popup & Toast Blocker"])
    L.intro(ns.L["Block selected Blizzard popups, toasts, and reminder alerts (including talent reminders and collection toasts)."])

    local function RefreshPopupBlocker()
        if _G.QUI_RefreshPopupBlocker then _G.QUI_RefreshPopupBlocker() end
    end

    local popupToggleWidgets = {}
    local function UpdatePopupToggleState()
        local enabled = popupDB.enabled == true
        for _, w in ipairs(popupToggleWidgets) do
            if w and w.SetEnabled then w:SetEnabled(enabled) end
        end
    end

    local enableSection = L.sectionAt()
    local enableW = GUI:CreateFormCheckbox(enableSection.frame, nil, "enabled", popupDB, function()
        UpdatePopupToggleState()
        RefreshPopupBlocker()
    end, { description = ns.L["Master toggle for the popup and toast blocker. Individual toggles below are only applied when this is on."] })
    enableSection.AddRow(row(enableSection.frame, ns.L["Enable Popup/Toast Blocker"], enableW))
    L.closeSection(enableSection)

    local descriptions = {
        blockTalentMicroButtonAlerts = ns.L["Suppress the pulsing reminder on the talent microbutton that appears when unspent points are available."],
        blockMicroButtonGlows        = ns.L["Suppress the glow animation on every microbutton (collections, achievements, etc.) when new items are detected."],
        blockHelpTips                = ns.L["Suppress the tutorial help tip callouts that Blizzard shows near talent and spellbook buttons."],
        blockEventToasts             = ns.L["Suppress general event toast popups, often triggered by campaign progress or housing updates."],
        blockMountAlerts             = ns.L["Suppress the toast that pops when you learn a new mount."],
        blockPetAlerts               = ns.L["Suppress the toast that pops when you learn a new battle pet."],
        blockToyAlerts               = ns.L["Suppress the toast that pops when you learn a new toy."],
        blockCosmeticAlerts          = ns.L["Suppress the toast that pops when you acquire a new cosmetic item."],
        blockWarbandSceneAlerts      = ns.L["Suppress warband scene notification toasts."],
        blockEntitlementAlerts       = ns.L["Suppress entitlement and recruit-a-friend delivery toast notifications."],
        blockStaticTalentPopups      = ns.L["Suppress the blocking static popups that appear for talent-related confirmations."],
        blockStaticHousingPopups     = ns.L["Suppress the blocking static popups that appear for housing-related confirmations."],
    }
    local toggles = {
        { ns.L["Block Talent Reminder Alerts (Microbutton)"],                  "blockTalentMicroButtonAlerts" },
        { ns.L["Block All Microbutton Glows"],                                  "blockMicroButtonGlows" },
        { ns.L["Block Help Tips (talent/spellbook)"],                           "blockHelpTips" },
        { ns.L["Block Event Toasts"],                                           "blockEventToasts" },
        { ns.L["Block New Mount Toasts"],                                       "blockMountAlerts" },
        { ns.L["Block New Pet Toasts"],                                         "blockPetAlerts" },
        { ns.L["Block New Toy Toasts"],                                         "blockToyAlerts" },
        { ns.L["Block New Cosmetic Toasts"],                                    "blockCosmeticAlerts" },
        { ns.L["Block Warband Scene Toasts"],                                   "blockWarbandSceneAlerts" },
        { ns.L["Block Entitlement/RAF Delivery Toasts"],                        "blockEntitlementAlerts" },
        { ns.L["Block Talent-Related Static Popups"],                           "blockStaticTalentPopups" },
        { ns.L["Block Housing-Related Static Popups"],                          "blockStaticHousingPopups" },
    }

    local togglesSection = L.sectionAt()
    local pending = nil
    for _, entry in ipairs(toggles) do
        local label, key = entry[1], entry[2]
        local w = GUI:CreateFormCheckbox(togglesSection.frame, nil, key, popupDB, RefreshPopupBlocker,
            { description = descriptions[key] })
        table.insert(popupToggleWidgets, w)
        local cell = row(togglesSection.frame, label, w)
        if pending then
            togglesSection.AddRow(pending, cell)
            pending = nil
        else
            pending = cell
        end
    end
    if pending then togglesSection.AddRow(pending) end
    L.closeSection(togglesSection)

    UpdatePopupToggleState()
end

local function BuildQuickSalvage(L, db)
    local qsDB = db and db.general and db.general.quickSalvage
    if not qsDB then return end

    L.headerAt(ns.L["Quick Salvage"])
    L.intro(ns.L["Mill, prospect, or disenchant items with a single click using a modifier key. Requires the corresponding profession."])

    local s = L.sectionAt()
    local enableW = GUI:CreateFormCheckbox(s.frame, nil, "enabled", qsDB, function()
        if _G.QUI_RefreshQuickSalvage then _G.QUI_RefreshQuickSalvage() end
    end, { description = ns.L["Let you mill, prospect, or disenchant items by holding the modifier key below and clicking them in your bags."] })
    local modifierOptions = {
        { value = "ALT", text = ns.L["Alt"] },
        { value = "ALTCTRL", text = ns.L["Alt + Ctrl"] },
        { value = "ALTSHIFT", text = ns.L["Alt + Shift"] },
    }
    local modW = GUI:CreateFormDropdown(s.frame, nil, modifierOptions, "modifier", qsDB, function()
        if _G.QUI_RefreshQuickSalvage then _G.QUI_RefreshQuickSalvage() end
    end, { description = ns.L["Modifier combination you must hold while clicking to trigger milling, prospecting, or disenchanting."] })
    s.AddRow(row(s.frame, ns.L["Enable Quick Salvage"], enableW), row(s.frame, ns.L["Modifier Key"], modW))
    L.closeSection(s)

    L.intro(ns.L["Milling: Herbs (5+ stack)  |  Prospecting: Ores (5+ stack)  |  Disenchanting: Green+ gear"])
end

local function BuildConsumableCheck(L, generalDB)
    if not generalDB then return end

    L.headerAt(ns.L["Consumable Check"])
    L.intro(ns.L["Display consumable status icons when triggered by events below. Left-click an icon to use your preferred item; right-click any shown icon to choose or refresh a consumable."])

    local function RefreshConsumables()
        if _G.QUI_RefreshConsumables then _G.QUI_RefreshConsumables() end
    end

    -- Main toggle + persistent mode
    local s1 = L.sectionAt()
    local enableW = GUI:CreateFormCheckbox(s1.frame, nil, "consumableCheckEnabled", generalDB, nil,
        { description = ns.L["Show a consumables window listing food, flasks, weapon enchants, runes, and healthstones based on the triggers below."] })
    local persistW = GUI:CreateFormCheckbox(s1.frame, nil, "consumablePersistent", generalDB, function()
        if generalDB.consumablePersistent then
            if _G.QUI_ShowConsumables then _G.QUI_ShowConsumables() end
        else
            if _G.QUI_HideConsumables then _G.QUI_HideConsumables() end
        end
    end, { description = ns.L["Keep the consumables window visible at all times instead of only showing on trigger events."] })
    s1.AddRow(row(s1.frame, ns.L["Enable Consumable Check"], enableW), row(s1.frame, ns.L["Always Show (Persistent Mode)"], persistW))
    L.closeSection(s1)

    -- Triggers card
    L.headerAt(ns.L["Triggers"])
    local s2 = L.sectionAt()
    local trgRC = GUI:CreateFormCheckbox(s2.frame, nil, "consumableOnReadyCheck", generalDB, nil,
        { description = ns.L["Open the consumables window when a Ready Check fires so you can fix any missing buffs."] })
    local trgD = GUI:CreateFormCheckbox(s2.frame, nil, "consumableOnDungeon", generalDB, nil,
        { description = ns.L["Open the consumables window when you zone into a dungeon."] })
    s2.AddRow(row(s2.frame, ns.L["Ready Check"], trgRC), row(s2.frame, ns.L["Dungeon Entrance"], trgD))

    local trgR = GUI:CreateFormCheckbox(s2.frame, nil, "consumableOnRaid", generalDB, nil,
        { description = ns.L["Open the consumables window when you zone into a raid."] })
    local trgRez = GUI:CreateFormCheckbox(s2.frame, nil, "consumableOnResurrect", generalDB, nil,
        { description = ns.L["Open the consumables window after a resurrection inside a dungeon or raid to remind you to re-buff."] })
    s2.AddRow(row(s2.frame, ns.L["Raid Entrance"], trgR), row(s2.frame, ns.L["Instanced Resurrect"], trgRez))
    L.closeSection(s2)

    -- Buff checks
    L.headerAt(ns.L["Buff Checks"])
    local s3 = L.sectionAt()
    local foodW = GUI:CreateFormCheckbox(s3.frame, nil, "consumableFood", generalDB, nil,
        { description = ns.L["Include a Food Buff slot in the consumables window."] })
    local flaskW = GUI:CreateFormCheckbox(s3.frame, nil, "consumableFlask", generalDB, nil,
        { description = ns.L["Include a Flask slot in the consumables window."] })
    s3.AddRow(row(s3.frame, ns.L["Food Buff"], foodW), row(s3.frame, ns.L["Flask Buff"], flaskW))

    local mhLabel = ns.ConsumableCheckLabels and ns.ConsumableCheckLabels.GetMHLabel() or ns.L["Weapon Oil"]
    local mhW = GUI:CreateFormCheckbox(s3.frame, nil, "consumableOilMH", generalDB, nil,
        { description = ns.L["Include a main-hand weapon enchant slot in the consumables window."] })
    local ohLabel = ns.ConsumableCheckLabels and ns.ConsumableCheckLabels.GetOHLabel() or ns.L["Weapon Oil"]
    local ohW = GUI:CreateFormCheckbox(s3.frame, nil, "consumableOilOH", generalDB, nil,
        { description = ns.L["Include an off-hand weapon enchant slot in the consumables window."] })
    s3.AddRow(row(s3.frame, mhLabel .. ns.L[" (Main Hand)"], mhW), row(s3.frame, ohLabel .. ns.L[" (Off Hand)"], ohW))

    local runeW = GUI:CreateFormCheckbox(s3.frame, nil, "consumableRune", generalDB, nil,
        { description = ns.L["Include an Augment Rune slot in the consumables window."] })
    local hsW = GUI:CreateFormCheckbox(s3.frame, nil, "consumableHealthstone", generalDB, nil,
        { description = ns.L["Include a Healthstone slot in the consumables window. Only shown when a Warlock is in the group."] })
    s3.AddRow(row(s3.frame, ns.L["Augment Rune"], runeW), row(s3.frame, ns.L["Healthstones"], hsW, ns.L["Only shows when a Warlock is in the group."]))
    L.closeSection(s3)

    -- Expiration warning
    L.headerAt(ns.L["Expiration Warning"])
    local s4 = L.sectionAt()
    local warnW = GUI:CreateFormCheckbox(s4.frame, nil, "consumableExpirationWarning", generalDB, nil,
        { description = ns.L["Open the consumables window automatically when a tracked buff is close to expiring while you are in instanced content."] })
    local threshW = GUI:CreateFormSlider(s4.frame, nil, 60, 600, 30, "consumableExpirationThreshold", generalDB, nil,
        { description = ns.L["How much time must remain on a tracked buff before the expiration warning fires, in seconds."] })
    s4.AddRow(row(s4.frame, ns.L["Warn When Buffs Expiring"], warnW), row(s4.frame, ns.L["Warning Threshold (sec)"], threshW))
    L.closeSection(s4)

    -- Display
    L.headerAt(ns.L["Display"])
    local s5 = L.sectionAt()
    local iconW = GUI:CreateFormSlider(s5.frame, nil, 24, 64, 2, "consumableIconSize", generalDB, RefreshConsumables,
        { description = ns.L["Pixel size of each consumable icon in the check window."] })
    local scaleW = GUI:CreateFormSlider(s5.frame, nil, 0.5, 3, 0.05, "consumableScale", generalDB, RefreshConsumables,
        { description = ns.L["Overall scale multiplier applied to the consumables window."] })
    s5.AddRow(row(s5.frame, ns.L["Icon Size"], iconW), row(s5.frame, ns.L["Scale"], scaleW))
    L.closeSection(s5)
end

local function BuildConsumableMacros(L, generalDB)
    local cmDB = generalDB and generalDB.consumableMacros
    if not cmDB then return end

    L.headerAt(ns.L["Consumable Macros"])
    L.intro(ns.L["Auto-create per-character macros that use the best-quality Flask or Potion in your bags. Higher quality variants are tried first (Gold Fleeting > Silver Fleeting > Gold Crafted > Silver Crafted)."])

    local function Refresh()
        if ns.ConsumableMacros then ns.ConsumableMacros:ForceRefresh() end
    end

    -- Enable + chat notifications
    local s1 = L.sectionAt()
    local enableW = GUI:CreateFormCheckbox(s1.frame, nil, "enabled", cmDB, function()
        if ns.ConsumableMacros then
            if cmDB.enabled then ns.ConsumableMacros:ForceRefresh()
            else ns.ConsumableMacros:DeleteMacros() end
        end
    end, { description = ns.L["Create per-character macros that pick the best available consumable from your bags. Disabling this removes the macros."] })
    local chatW = GUI:CreateFormCheckbox(s1.frame, nil, "chatNotifications", cmDB, nil,
        { description = ns.L["Print a chat message each time the consumable macros are rebuilt so you know which item was chosen."] })
    s1.AddRow(row(s1.frame, ns.L["Enable Consumable Macros"], enableW), row(s1.frame, ns.L["Chat Notifications"], chatW))
    L.closeSection(s1)

    -- Dropdowns
    L.headerAt(ns.L["Macro Selections"])
    local s2 = L.sectionAt()
    local flaskOpts = ns.ConsumableMacros and ns.ConsumableMacros.FLASK_OPTIONS or { { value = "none", text = ns.L["None"] } }
    local potionOpts = ns.ConsumableMacros and ns.ConsumableMacros.POTION_OPTIONS or { { value = "none", text = ns.L["None"] } }
    local healthOpts = ns.ConsumableMacros and ns.ConsumableMacros.HEALTH_OPTIONS or { { value = "none", text = ns.L["None"] } }
    local hsOpts = ns.ConsumableMacros and ns.ConsumableMacros.HEALTHSTONE_OPTIONS or { { value = "none", text = ns.L["None"] } }
    local augOpts = ns.ConsumableMacros and ns.ConsumableMacros.AUGMENT_OPTIONS or { { value = "none", text = ns.L["None"] } }
    local vantusOpts = ns.ConsumableMacros and ns.ConsumableMacros.VANTUS_OPTIONS or { { value = "none", text = ns.L["None"] } }
    local weaponOpts = ns.ConsumableMacros and ns.ConsumableMacros.WEAPON_OPTIONS or { { value = "none", text = ns.L["None"] } }

    local flaskW = GUI:CreateFormDropdown(s2.frame, nil, flaskOpts, "selectedFlask", cmDB, Refresh,
        { description = ns.L["Flask family the QUI_Flask macro should prefer. The macro always picks the highest-quality variant in your bags."] })
    local potW = GUI:CreateFormDropdown(s2.frame, nil, potionOpts, "selectedPotion", cmDB, Refresh,
        { description = ns.L["Combat utility potion (e.g., stat/tempered potions) used by the QUI_Pot macro."] })
    s2.AddRow(row(s2.frame, ns.L["Flask Type"], flaskW), row(s2.frame, ns.L["Potion Type"], potW))

    local healthW = GUI:CreateFormDropdown(s2.frame, nil, healthOpts, "selectedHealth", cmDB, Refresh,
        { description = ns.L["Healing potion family used by the QUI_Health macro."] })
    local hsW = GUI:CreateFormDropdown(s2.frame, nil, hsOpts, "selectedHealthstone", cmDB, Refresh,
        { description = ns.L["Healthstone variant used by the QUI_Stone macro."] })
    s2.AddRow(row(s2.frame, ns.L["Health Potion"], healthW), row(s2.frame, ns.L["Healthstone"], hsW))

    local augW = GUI:CreateFormDropdown(s2.frame, nil, augOpts, "selectedAugment", cmDB, Refresh,
        { description = ns.L["Augment rune family used by the QUI_Rune macro."] })
    local vantusW = GUI:CreateFormDropdown(s2.frame, nil, vantusOpts, "selectedVantus", cmDB, Refresh,
        { description = ns.L["Vantus rune the QUI_Vantus macro should use — useful for raid boss attempt buffs."] })
    s2.AddRow(row(s2.frame, ns.L["Augment Rune"], augW), row(s2.frame, ns.L["Vantus Rune"], vantusW))

    local weaponW = GUI:CreateFormDropdown(s2.frame, nil, weaponOpts, "selectedWeapon", cmDB, Refresh,
        { description = ns.L["Weapon oil, stone, or enchant consumable used by the QUI_Weapon macro."] })
    s2.AddRow(row(s2.frame, ns.L["Weapon Consumable"], weaponW))
    L.closeSection(s2)

    L.intro(ns.L["Creates per-character macros: QUI_Flask, QUI_Pot, QUI_Health, QUI_Stone, QUI_Rune, QUI_Vantus, QUI_Weapon. Drag them to your action bars."])
end

local function BuildTargetDistance(L, db)
    local rangeCheckDB = db and db.rangeCheck
    if not rangeCheckDB then return end

    L.headerAt(ns.L["Target Distance Bracket Display"])

    local dynamicColorCheck
    local classColorCheck
    local textColorPicker

    local function RefreshRangeControls()
        if rangeCheckDB.dynamicColor and rangeCheckDB.useClassColor then
            rangeCheckDB.useClassColor = false
            if classColorCheck and classColorCheck.SetValue then classColorCheck.SetValue(false, true) end
        end
        if dynamicColorCheck and dynamicColorCheck.SetEnabled then dynamicColorCheck:SetEnabled(true) end
        if classColorCheck and classColorCheck.SetEnabled then
            classColorCheck:SetEnabled(not rangeCheckDB.dynamicColor)
        end
        if textColorPicker and textColorPicker.SetEnabled then
            textColorPicker:SetEnabled(not rangeCheckDB.dynamicColor and not rangeCheckDB.useClassColor)
        end
    end

    -- Toggle + preview
    local s1 = L.sectionAt()
    local enableW = GUI:CreateFormCheckbox(s1.frame, nil, "enabled", rangeCheckDB, function()
        Shared.RefreshRangeCheck()
    end, { description = ns.L["Show the current target's distance bracket as on-screen text."] })
    local previewState = { enabled = _G.QUI_IsRangeCheckPreviewMode and _G.QUI_IsRangeCheckPreviewMode() or false }
    local previewW = GUI:CreateFormCheckbox(s1.frame, nil, "enabled", previewState, function(val)
        if _G.QUI_ToggleRangeCheckPreview then _G.QUI_ToggleRangeCheckPreview(val) end
    end, { description = ns.L["Show a draggable preview frame so you can position the distance bracket display."] })
    s1.AddRow(row(s1.frame, ns.L["Enable Distance Bracket Display"], enableW), row(s1.frame, ns.L["Preview / Move Frame"], previewW))

    local combatW = GUI:CreateFormCheckbox(s1.frame, nil, "combatOnly", rangeCheckDB, function() Shared.RefreshRangeCheck() end,
        { description = ns.L["Only show the distance bracket display while you are in combat."] })
    local hostileW = GUI:CreateFormCheckbox(s1.frame, nil, "showOnlyWithTarget", rangeCheckDB, function() Shared.RefreshRangeCheck() end,
        { description = ns.L["Only show the display when you have a hostile target selected."] })
    s1.AddRow(row(s1.frame, ns.L["Combat Only"], combatW), row(s1.frame, ns.L["Only Show With Hostile Target"], hostileW))

    local shortW = GUI:CreateFormCheckbox(s1.frame, nil, "shortenText", rangeCheckDB, function() Shared.RefreshRangeCheck() end,
        { description = ns.L["Use abbreviated distance labels (e.g., Melee/Close/Far) instead of longer phrasing."] })
    dynamicColorCheck = GUI:CreateFormCheckbox(s1.frame, nil, "dynamicColor", rangeCheckDB, function(val)
        if val then
            rangeCheckDB.useClassColor = false
            if classColorCheck and classColorCheck.SetValue then classColorCheck.SetValue(false, true) end
        end
        Shared.RefreshRangeCheck()
        RefreshRangeControls()
    end, { description = ns.L["Change the text color to match the current distance bracket. Overrides Use Class Color."] })
    s1.AddRow(row(s1.frame, ns.L["Shorten Text"], shortW), row(s1.frame, ns.L["Dynamic Color (by bracket)"], dynamicColorCheck))

    classColorCheck = GUI:CreateFormCheckbox(s1.frame, nil, "useClassColor", rangeCheckDB, function()
        Shared.RefreshRangeCheck()
        RefreshRangeControls()
    end, { description = ns.L["Color the distance text with your class color. Ignored when Dynamic Color is on."] })

    if not rangeCheckDB.textColor then rangeCheckDB.textColor = { 0.2, 0.95, 0.55, 1 } end
    textColorPicker = GUI:CreateFormColorPicker(s1.frame, nil, "textColor", rangeCheckDB, function() Shared.RefreshRangeCheck() end, nil,
        { description = ns.L["Custom static color used when neither Dynamic Color nor Use Class Color is enabled."] })
    s1.AddRow(row(s1.frame, ns.L["Use Class Color"], classColorCheck), row(s1.frame, ns.L["Text Color"], textColorPicker))

    local fontList = Shared.GetFontList()
    local fontW = GUI:CreateFormDropdown(s1.frame, nil, fontList, "font", rangeCheckDB, function() Shared.RefreshRangeCheck() end,
        { description = ns.L["Font used for the distance text."] })
    local fSizeW = GUI:CreateFormSlider(s1.frame, nil, 8, 48, 1, "fontSize", rangeCheckDB, function() Shared.RefreshRangeCheck() end,
        { description = ns.L["Font size of the distance text."] })
    s1.AddRow(row(s1.frame, ns.L["Font"], fontW), row(s1.frame, ns.L["Font Size"], fSizeW))

    local strataOptions = {
        { value = "BACKGROUND", text = ns.L["Background"] },
        { value = "LOW", text = ns.L["Low"] },
        { value = "MEDIUM", text = ns.L["Medium"] },
        { value = "HIGH", text = ns.L["High"] },
        { value = "DIALOG", text = ns.L["Dialog"] },
    }
    local strataW = GUI:CreateFormDropdown(s1.frame, nil, strataOptions, "strata", rangeCheckDB, function() Shared.RefreshRangeCheck() end,
        { description = ns.L["Rendering layer for the distance display. Raise this if other frames cover it."] })
    local xW = GUI:CreateFormSlider(s1.frame, nil, -700, 700, 1, "offsetX", rangeCheckDB, function() Shared.RefreshRangeCheck() end,
        { description = ns.L["Horizontal pixel offset of the distance text from its anchor."] })
    s1.AddRow(row(s1.frame, ns.L["Frame Strata"], strataW), row(s1.frame, ns.L["X-Offset"], xW))

    local yW = GUI:CreateFormSlider(s1.frame, nil, -700, 700, 1, "offsetY", rangeCheckDB, function() Shared.RefreshRangeCheck() end,
        { description = ns.L["Vertical pixel offset of the distance text from its anchor."] })
    s1.AddRow(row(s1.frame, ns.L["Y-Offset"], yW))
    L.closeSection(s1)

    RefreshRangeControls()
end

local function BuildQuiPanel(L, db)
    L.headerAt(ns.L["QUI Panel Settings"])
    local s = L.sectionAt()

    local alphaW = GUI:CreateFormSlider(s.frame, nil, 0.3, 1.0, 0.01, "configPanelAlpha", db, function(val)
        local mainFrame = GUI.MainFrame
        if mainFrame then
            local bgColor = GUI.Colors.bg
            mainFrame:SetBackdropColor(bgColor[1], bgColor[2], bgColor[3], val)
        end
    end, { description = ns.L["Background opacity of the QUI options panel itself."] })

    local minimapBtnDB = db and db.minimapButton
    if minimapBtnDB then
        local hideW = GUI:CreateFormCheckbox(s.frame, nil, "hide", minimapBtnDB, function(dbVal)
            local LibDBIcon = LibStub("LibDBIcon-1.0", true)
            if LibDBIcon then
                if dbVal then LibDBIcon:Hide("QUI") else LibDBIcon:Show("QUI") end
            end
            if _G.QUI_RefreshMinimapButtonDrawer then _G.QUI_RefreshMinimapButtonDrawer() end
        end, { description = ns.L["Hide the QUI minimap button. You can still open the options panel via /qui."] })
        s.AddRow(row(s.frame, ns.L["Hide QUI Minimap Icon"], hideW), row(s.frame, ns.L["QUI Panel Transparency"], alphaW))
    else
        s.AddRow(row(s.frame, ns.L["QUI Panel Transparency"], alphaW))
    end
    L.closeSection(s)
end

local function BuildReloadBehavior(L, db)
    L.headerAt(ns.L["Reload Behavior"])
    L.intro(ns.L["By default, QUI queues /reload until combat ends to prevent taint issues. Enable this to bypass the combat check and reload immediately."])

    if not db.general then return end
    local s = L.sectionAt()
    local w = GUI:CreateFormCheckbox(s.frame, nil, "allowReloadInCombat", db.general, nil,
        { description = ns.L["Bypass QUI's usual combat-end queue and reload immediately when a reload is requested. Can re-introduce taint issues during combat."] })
    s.AddRow(row(s.frame, ns.L["Allow Reload During Combat"], w))
    L.closeSection(s)
end

---------------------------------------------------------------------------
-- DISPATCH
---------------------------------------------------------------------------

local SECTION_BUILDERS = {
    settingsPanel    = function(L, db) BuildSettingsPanel(L, db) end,
    uiScale          = function(L, db) BuildUIScale(L, db) end,
    defaultFonts     = function(L, db) BuildDefaultFonts(L, db) end,
    fpsPreset        = function(L, db) BuildFPSPreset(L, db) end,
    combatText       = function(L, db) BuildCombatText(L, db) end,
    automation       = function(L, db) BuildAutomation(L, db and db.general) end,
    popupBlocker     = function(L, db) BuildPopupBlocker(L, db and db.general) end,
    quickSalvage     = function(L, db) BuildQuickSalvage(L, db) end,
    consumables      = function(L, db) BuildConsumableCheck(L, db and db.general) end,
    consumableMacros = function(L, db) BuildConsumableMacros(L, db and db.general) end,
    targetDistance   = function(L, db) BuildTargetDistance(L, db) end,
    quiPanel         = function(L, db) BuildQuiPanel(L, db) end,
    reloadBehavior   = function(L, db) BuildReloadBehavior(L, db) end,
}

local SECTION_ORDER = {
    "settingsPanel", "uiScale", "defaultFonts", "fpsPreset", "combatText",
    "automation", "popupBlocker", "quickSalvage", "consumables",
    "consumableMacros", "targetDistance", "quiPanel", "reloadBehavior",
}

local function BuildGeneralTab(tabContent, searchContext, selectedSectionKey)
    local db = Shared.GetDB()
    if not db then return end

    if searchContext then
        GUI:SetSearchContext(searchContext)
    end

    local L = MakeLayout(tabContent)

    for _, key in ipairs(SECTION_ORDER) do
        if ShouldBuildSection(selectedSectionKey, key) then
            local builder = SECTION_BUILDERS[key]
            if builder then builder(L, db) end
        end
    end

    return L.finish()
end

-- Export
ns.QUI_QoLOptions = {
    BuildGeneralTab = BuildGeneralTab,
}

local function GetGeneralDB(profile)
    return profile and profile.general
end

local generalSectionFeatures = {
    { id = "fpsPreset",         category = "qol",        nav = { tileId = "qol", subPageIndex = 1 }, sectionKey = "fpsPreset",        sectionTitle = "Quazii Recommended FPS Settings", searchContext = { tabIndex = 17, tabName = "Quality of Life", subTabIndex = 1, subTabName = "FPS Preset" } },
    { id = "combatText",        category = "qol",        nav = { tileId = "qol", subPageIndex = 2 }, sectionKey = "combatText",       sectionTitle = "Combat Status Text Indicator",     searchContext = { tabIndex = 17, tabName = "Quality of Life", subTabIndex = 2, subTabName = "Combat Text" } },
    { id = "automation",        category = "qol",        nav = { tileId = "qol", subPageIndex = 3 }, sectionKey = "automation",       sectionTitle = "Automation",                       searchContext = { tabIndex = 17, tabName = "Quality of Life", subTabIndex = 3, subTabName = "Automation" } },
    { id = "popupBlocker",      category = "qol",        nav = { tileId = "qol", subPageIndex = 4 }, sectionKey = "popupBlocker",     sectionTitle = "Popup & Toast Blocker",            searchContext = { tabIndex = 17, tabName = "Quality of Life", subTabIndex = 4, subTabName = "Popups" } },
    { id = "quickSalvage",      category = "qol",        nav = { tileId = "qol", subPageIndex = 5 }, sectionKey = "quickSalvage",     sectionTitle = "Quick Salvage",                    searchContext = { tabIndex = 17, tabName = "Quality of Life", subTabIndex = 5, subTabName = "Salvage" } },
    { id = "consumableMacros",  category = "qol",        nav = { tileId = "qol", subPageIndex = 6 }, sectionKey = "consumableMacros", sectionTitle = "Consumable Macros",                searchContext = { tabIndex = 17, tabName = "Quality of Life", subTabIndex = 6, subTabName = "Consumables" } },
    { id = "targetDistance",    category = "qol",        nav = { tileId = "qol", subPageIndex = 7 }, sectionKey = "targetDistance",   sectionTitle = "Target Distance Bracket Display",  searchContext = { tabIndex = 17, tabName = "Quality of Life", subTabIndex = 7, subTabName = "Distance" } },
    { id = "quiPanel",          category = "qol",        nav = { tileId = "qol", subPageIndex = 8 }, sectionKey = "quiPanel",         sectionTitle = "QUI Panel Settings",               searchContext = { tabIndex = 17, tabName = "Quality of Life", subTabIndex = 8, subTabName = "Panel" } },
    { id = "reloadBehavior",    category = "qol",        nav = { tileId = "qol", subPageIndex = 9 }, sectionKey = "reloadBehavior",   sectionTitle = "Reload Behavior",                  searchContext = { tabIndex = 17, tabName = "Quality of Life", subTabIndex = 9, subTabName = "Reload" } },
    { id = "uiScale",           category = "appearance", nav = { tileId = "appearance", subPageIndex = 1 }, sectionKey = "uiScale",   sectionTitle = "UI Scale",                         searchContext = { tabIndex = 10, tabName = "Appearance",      subTabIndex = 3, subTabName = "UI Scale" } },
    { id = "defaultFonts",      category = "appearance", nav = { tileId = "appearance", subPageIndex = 2 }, sectionKey = "defaultFonts", sectionTitle = "Default Font Settings",         searchContext = { tabIndex = 10, tabName = "Appearance",      subTabIndex = 4, subTabName = "Fonts" } },
}

if Registry and Schema
    and type(Registry.RegisterFeature) == "function"
    and type(Schema.Feature) == "function"
    and type(Schema.Section) == "function" then
    for _, spec in ipairs(generalSectionFeatures) do
        local featureSpec = spec
        Registry:RegisterFeature(Schema.Feature({
            id = featureSpec.id,
            moverKey = featureSpec.moverKey or featureSpec.id,
            category = featureSpec.category,
            nav = featureSpec.nav,
            getDB = GetGeneralDB,
            searchContext = featureSpec.searchContext,
            sectionTitle = featureSpec.sectionTitle,
            sectionKey = featureSpec.sectionKey,
            sections = {
                Schema.Section({
                    id = "settings",
                    kind = "page",
                    minHeight = 80,
                    build = function(host)
                        return BuildGeneralTab(host, featureSpec.searchContext, featureSpec.sectionKey)
                    end,
                }),
            },
        }))
    end
end
