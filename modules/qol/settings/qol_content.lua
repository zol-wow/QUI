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

local function MakeLayout(content)
    return ns.QUI_SettingsLayoutShared.MakeLayout(content)
end

local function row(parent, label, widget, desc)
    return Opts.BuildSettingRow(parent, label, widget, desc)
end

local function ShouldBuildSection(selectedSectionKey, sectionKey)
    return selectedSectionKey == nil or selectedSectionKey == sectionKey
end

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

    if db.general then
        L.headerAt(ns.L["Blizzard Combat Text"])
        L.intro(ns.L["Controls Blizzard's own floating combat text — the scrolling damage and healing numbers over units. Separate from QUI's +Combat indicator above."])
        local s2 = L.sectionAt()
        local disableSCTW = GUI:CreateFormCheckbox(s2.frame, nil, "disableScrollingCombatText", db.general, function()
            if QUICore and QUICore.RefreshScrollingCombatText then QUICore.RefreshScrollingCombatText() end
        end, { description = ns.L["Turn off Blizzard's floating/scrolling combat text. QUI re-applies this on login. Does not affect QUI's +Combat indicator."] })
        s2.AddRow(row(s2.frame, ns.L["Disable Scrolling Combat Text"], disableSCTW))
        L.closeSection(s2)
    end
end

local function BuildAutomation(L, generalDB)
    if not generalDB then return end

    L.headerAt(ns.L["Automation"])
    L.intro(ns.L["Toggle quality-of-life automation features. These run silently in the background."])

    local s = L.sectionAt()
    local sellW = GUI:CreateFormCheckbox(s.frame, nil, "sellJunk", generalDB, nil,
        { description = ns.L["Automatically sell grey-quality junk items in your bags when you open a merchant window. Honors the Bags module's junk exclusion list and per-bag exclude-from-junk-sell flags, so the bag window's junk coin previews exactly what will be sold."] })
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

    local closeBagsKeyW = GUI:CreateFormCheckbox(s.frame, nil, "closeBagsOnKeystoneInsert", generalDB, nil,
        { description = ns.L["Close your bags after the keystone is auto-inserted. Requires Auto Insert M+ Keys."] })
    s.AddRow(row(s.frame, ns.L["Close Bags After Inserting Key"], closeBagsKeyW))

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

    local mapTelW = GUI:CreateFormCheckbox(s.frame, nil, "worldMapTeleports", generalDB, function()
        if ns.RefreshWorldMapTeleports then ns.RefreshWorldMapTeleports() end
    end, { description = ns.L["Show a panel of this season's M+ dungeon teleports on the world map. Unlearned teleports show desaturated. Panel builds out of combat."] })
    s.AddRow(row(s.frame, ns.L["World Map Teleport Panel"], mapTelW))

    if type(generalDB.focusMarker) ~= "table" then generalDB.focusMarker = {} end
    local fm = generalDB.focusMarker
    local function RefreshFM()
        if ns.RefreshFocusMarker then ns.RefreshFocusMarker() end
    end
    local fmEnableW = GUI:CreateFormCheckbox(s.frame, nil, "enabled", fm, RefreshFM,
        { description = ns.L["One press sets your focus AND puts a raid marker on it (hostile living mouseover first, else your target). Keeps a character macro named 'FocusMarker_QUI' in sync — drag it to a bar or keybind it. Updates apply out of combat."] })
    local markerOptions = {
        { value = 1, text = ns.L["Star"] },
        { value = 2, text = ns.L["Circle"] },
        { value = 3, text = ns.L["Diamond"] },
        { value = 4, text = ns.L["Triangle"] },
        { value = 5, text = ns.L["Moon"] },
        { value = 6, text = ns.L["Square"] },
        { value = 7, text = ns.L["Cross"] },
        { value = 8, text = ns.L["Skull"] },
    }
    local fmMarkerW = GUI:CreateFormDropdown(s.frame, nil, markerOptions, "marker", fm, RefreshFM,
        { description = ns.L["Raid target icon the button applies."] })
    s.AddRow(row(s.frame, ns.L["Focus + Marker Button"], fmEnableW), row(s.frame, ns.L["Marker Icon"], fmMarkerW))

    local fmMouseoverW = GUI:CreateFormCheckbox(s.frame, nil, "useMouseover", fm, RefreshFM,
        { description = ns.L["Prefer the hostile living unit under your mouse; fall back to your current target."] })
    local fmMacroW = GUI:CreateFormCheckbox(s.frame, nil, "writeMacro", fm, RefreshFM,
        { description = ns.L["Create/update the 'FocusMarker_QUI' character macro automatically."] })
    s.AddRow(row(s.frame, ns.L["Use Mouseover"], fmMouseoverW), row(s.frame, ns.L["Maintain Macro"], fmMacroW))

    if type(generalDB.healerMana) ~= "table" then generalDB.healerMana = {} end
    local hm = generalDB.healerMana
    local function RefreshHM()
        if ns.RefreshHealerMana then ns.RefreshHealerMana() end
    end
    local hmEnableW = GUI:CreateFormCheckbox(s.frame, nil, "enabled", hm, RefreshHM,
        { description = ns.L["Show a small movable list of your group's healers with a mana bar each (bars only — mana numbers are combat-restricted in 12.x). Position it in Layout Mode."] })
    local hmInstanceW = GUI:CreateFormCheckbox(s.frame, nil, "instanceOnly", hm, RefreshHM,
        { description = ns.L["Only show inside dungeons, raids, and other instances."] })
    s.AddRow(row(s.frame, ns.L["Healer Mana Bars"], hmEnableW), row(s.frame, ns.L["Instances Only"], hmInstanceW))

    if type(generalDB.deathAlert) ~= "table" then generalDB.deathAlert = {} end
    local da = generalDB.deathAlert
    local function RefreshDA()
        if ns.RefreshDeathAlert then ns.RefreshDeathAlert() end
    end
    local daEnableW = GUI:CreateFormCheckbox(s.frame, nil, "enabled", da, RefreshDA,
        { description = ns.L["Flash an on-screen alert when a party or raid member dies (hunter feigns filtered). Position it in Layout Mode. Names fall back to 'An ally' when combat-restricted."] })
    local daSoundW = GUI:CreateFormDropdown(s.frame, nil, Shared.GetSoundList(), "sound", da, nil,
        { description = ns.L["Sound played with the death alert. None = silent."] })
    s.AddRow(row(s.frame, ns.L["Group Death Alert"], daEnableW), row(s.frame, ns.L["Death Alert Sound"], daSoundW))

    local ahW = GUI:CreateFormCheckbox(s.frame, nil, "auctionHouseExpansionFilter", generalDB, nil,
        { description = ns.L["Automatically toggle the current expansion filter when you open the Auction House so you only see modern items."] })
    local coW = GUI:CreateFormCheckbox(s.frame, nil, "craftingOrderExpansionFilter", generalDB, nil,
        { description = ns.L["Automatically toggle the current expansion filter when you open the Crafting Orders window."] })
    s.AddRow(row(s.frame, ns.L["Auto-Enable AH Expansion Filter"], ahW), row(s.frame, ns.L["Auto-Enable Crafting Orders Filter"], coW))

    local duelW = GUI:CreateFormCheckbox(s.frame, nil, "autoDeclineDuel", generalDB, nil,
        { description = ns.L["Automatically decline incoming duel requests so the popup never interrupts you."] })
    local petDuelW = GUI:CreateFormCheckbox(s.frame, nil, "autoDeclinePetBattle", generalDB, nil,
        { description = ns.L["Automatically decline incoming pet battle duel requests so the popup never interrupts you."] })
    s.AddRow(row(s.frame, ns.L["Auto-Decline Duels"], duelW), row(s.frame, ns.L["Auto-Decline Pet Battle Duels"], petDuelW))

    local releaseOptions = {
        { value = "off", text = ns.L["Off"] },
        { value = "pvp", text = ns.L["Battlegrounds"] },
        { value = "pvpworld", text = ns.L["Battlegrounds & Open World"] },
    }
    local releaseW = GUI:CreateFormDropdown(s.frame, nil, releaseOptions, "autoRelease", generalDB, nil,
        { description = ns.L["Automatically release your spirit after you die. Never triggers in dungeons or raids, where a battle resurrection matters."] })
    local blockReleaseW = GUI:CreateFormCheckbox(s.frame, nil, "blockReleaseInRaid", generalDB, nil,
        { description = ns.L["Guard the Release Spirit button while you are dead in a raid: it locks during a 3-second countdown and afterwards only works while Ctrl is held, so you don't release before a battle resurrection."] })
    s.AddRow(row(s.frame, ns.L["Auto Release Spirit"], releaseW), row(s.frame, ns.L["Block Release in Raids"], blockReleaseW))

    local audioOptions = (ns.GetAudioDeviceOptions and ns.GetAudioDeviceOptions())
        or { { value = "", text = ns.L["Off (don't lock)"] } }
    local audioW = GUI:CreateFormDropdown(s.frame, nil, audioOptions, "audioOutputDevice", generalDB, function()
        if ns.ApplyPreferredAudioDevice then ns.ApplyPreferredAudioDevice() end
    end, { description = ns.L["Lock the game's audio output to a specific device. When your system switches devices (e.g. plugging in headphones), QUI forces it back. Off leaves Blizzard's default behavior."] })
    s.AddRow(row(s.frame, ns.L["Lock Audio Output Device"], audioW))

    local unwrapW = GUI:CreateFormCheckbox(s.frame, nil, "autoUnwrapCollections", generalDB, function()
        if ns.RefreshCollectionFanfare then ns.RefreshCollectionFanfare() end
    end, { description = ns.L["Automatically unwrap newly collected mounts, pets, and toys — clears the present-box fanfare in the Collections journal and dismisses the unopened-items alert."] })
    local socketW = GUI:CreateFormCheckbox(s.frame, nil, "autoConfirmSocketReplace", generalDB, nil,
        { description = ns.L["Skip the confirmation popup when replacing a gem that is already socketed."] })
    s.AddRow(row(s.frame, ns.L["Auto-Unwrap New Collectibles"], unwrapW), row(s.frame, ns.L["Auto-Confirm Gem Replacement"], socketW))

    local tokenW = GUI:CreateFormCheckbox(s.frame, nil, "autoConfirmTokenPurchase", generalDB, nil,
        { description = ns.L["Skip the confirmation popup when buying items that cost tokens or currencies."] })
    local highCostW = GUI:CreateFormCheckbox(s.frame, nil, "autoConfirmHighCost", generalDB, nil,
        { description = ns.L["Skip the confirmation popup when buying expensive items from vendors."] })
    s.AddRow(row(s.frame, ns.L["Auto-Confirm Currency Purchases"], tokenW), row(s.frame, ns.L["Auto-Confirm Expensive Purchases"], highCostW))

    local ejSpecW = GUI:CreateFormCheckbox(s.frame, nil, "ejLootSpecIcons", generalDB, function()
        if ns.RefreshEJLootSpecIcons then ns.RefreshEJLootSpecIcons() end
    end, { description = ns.L["Show spec icons on Encounter Journal loot rows for items only some specializations can get. Items usable by everyone stay unmarked."] })
    local gemPickerW = GUI:CreateFormCheckbox(s.frame, nil, "gemSocketPicker", generalDB, function()
        if ns.RefreshGemPicker then ns.RefreshGemPicker() end
    end, { description = ns.L["Show a panel of the gems in your bags under the item socketing window; click one to pick it up ready to socket."] })
    s.AddRow(row(s.frame, ns.L["Journal Loot Spec Icons"], ejSpecW), row(s.frame, ns.L["Gem Socket Picker"], gemPickerW))

    local mailPanelW = GUI:CreateFormCheckbox(s.frame, nil, "mailContactsPanel", generalDB, function()
        if ns.RefreshMailContacts then ns.RefreshMailContacts() end
    end, { description = ns.L["Show an account-wide contacts panel next to the send-mail tab: your alts plus everyone you've mailed. Click a name to fill the recipient."] })
    local mailRememberW = GUI:CreateFormCheckbox(s.frame, nil, "mailRememberRecipient", generalDB, nil,
        { description = ns.L["After sending a mail, keep the recipient name filled in for the next one."] })
    s.AddRow(row(s.frame, ns.L["Mail Contacts Panel"], mailPanelW), row(s.frame, ns.L["Remember Mail Recipient"], mailRememberW))

    if type(generalDB.tradeMailLog) ~= "table" then generalDB.tradeMailLog = {} end
    local tml = generalDB.tradeMailLog
    local tmlEnableW = GUI:CreateFormCheckbox(s.frame, nil, "enabled", tml, nil,
        { description = ns.L["Keep an account-wide log of trades and mail (partner, gold, COD, attached items). View it with /quilog — item links stay clickable in chat."] })
    local tmlTradesW = GUI:CreateFormCheckbox(s.frame, nil, "logTrades", tml, nil,
        { description = ns.L["Log player trades (both sides' items and gold, completed or cancelled)."] })
    s.AddRow(row(s.frame, ns.L["Trade & Mail Log"], tmlEnableW), row(s.frame, ns.L["Log Trades"], tmlTradesW))

    local tmlSentW = GUI:CreateFormCheckbox(s.frame, nil, "logSentMail", tml, nil,
        { description = ns.L["Log mail you send (recipient, subject, gold, COD, attachments)."] })
    local tmlRecvW = GUI:CreateFormCheckbox(s.frame, nil, "logReceivedMail", tml, nil,
        { description = ns.L["Log mail you open in your inbox (sender, subject, gold, COD, attachments)."] })
    s.AddRow(row(s.frame, ns.L["Log Sent Mail"], tmlSentW), row(s.frame, ns.L["Log Received Mail"], tmlRecvW))
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

    if type(generalDB.lootToastFilter) ~= "table" then generalDB.lootToastFilter = {} end
    local lootCfg = generalDB.lootToastFilter

    L.headerAt(ns.L["Loot Toast Curation"])
    L.intro(ns.L["Hide loot-won toasts below a chosen quality. Mounts, pets, upgraded drops, and high item-level gear can always be kept. Items the game hasn't cached yet still show their toast."])

    local sLoot = L.sectionAt()
    local lootEnableW = GUI:CreateFormCheckbox(sLoot.frame, nil, "enabled", lootCfg, nil,
        { description = ns.L["Master toggle for loot toast curation."] })
    local qualityOptions = {
        { value = 0, text = ns.L["Show All"] },
        { value = 2, text = ns.L["Uncommon (hide Poor/Common)"] },
        { value = 3, text = ns.L["Rare (hide below Rare)"] },
        { value = 4, text = ns.L["Epic (hide below Epic)"] },
        { value = 5, text = ns.L["Legendary (hide below Legendary)"] },
    }
    local minQualW = GUI:CreateFormDropdown(sLoot.frame, nil, qualityOptions, "minQuality", lootCfg, nil,
        { description = ns.L["Only loot toasts at or above this quality are shown; lower-quality toasts are hidden (unless kept by the overrides below)."] })
    sLoot.AddRow(row(sLoot.frame, ns.L["Enable Loot Toast Curation"], lootEnableW), row(sLoot.frame, ns.L["Minimum Toast Quality"], minQualW))

    local keepMountsW = GUI:CreateFormCheckbox(sLoot.frame, nil, "keepMounts", lootCfg, nil,
        { description = ns.L["Always show toasts for mount-teaching items regardless of quality."] })
    local keepPetsW = GUI:CreateFormCheckbox(sLoot.frame, nil, "keepPets", lootCfg, nil,
        { description = ns.L["Always show toasts for battle pet items regardless of quality."] })
    sLoot.AddRow(row(sLoot.frame, ns.L["Always Keep Mounts"], keepMountsW), row(sLoot.frame, ns.L["Always Keep Pets"], keepPetsW))

    local keepUpgradesW = GUI:CreateFormCheckbox(sLoot.frame, nil, "keepUpgrades", lootCfg, nil,
        { description = ns.L["Always show toasts for drops the game flags as upgraded (warforged-style rolls)."] })
    local minIlvlW = GUI:CreateFormSlider(sLoot.frame, nil, 0, 800, 5, "minKeepIlvl", lootCfg, nil,
        { description = ns.L["Equippable items at or above this item level always show their toast. 0 disables the override."] })
    sLoot.AddRow(row(sLoot.frame, ns.L["Always Keep Upgraded Drops"], keepUpgradesW), row(sLoot.frame, ns.L["Always Keep Item Level ≥"], minIlvlW))
    L.closeSection(sLoot)
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

    L.headerAt(ns.L["Expiration Warning"])
    local s4 = L.sectionAt()
    local warnW = GUI:CreateFormCheckbox(s4.frame, nil, "consumableExpirationWarning", generalDB, nil,
        { description = ns.L["Open the consumables window automatically when a tracked buff is close to expiring while you are in instanced content."] })
    local threshW = GUI:CreateFormSlider(s4.frame, nil, 60, 600, 30, "consumableExpirationThreshold", generalDB, nil,
        { description = ns.L["How much time must remain on a tracked buff before the expiration warning fires, in seconds."] })
    s4.AddRow(row(s4.frame, ns.L["Warn When Buffs Expiring"], warnW), row(s4.frame, ns.L["Warning Threshold (sec)"], threshW))
    L.closeSection(s4)

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
        { description = ns.L["Flask family the Flask_QUI macro should prefer. The macro always picks the highest-quality variant in your bags."] })
    local potW = GUI:CreateFormDropdown(s2.frame, nil, potionOpts, "selectedPotion", cmDB, Refresh,
        { description = ns.L["Combat utility potion (e.g., stat/tempered potions) used by the Pot_QUI macro."] })
    s2.AddRow(row(s2.frame, ns.L["Flask Type"], flaskW), row(s2.frame, ns.L["Potion Type"], potW))

    local healthW = GUI:CreateFormDropdown(s2.frame, nil, healthOpts, "selectedHealth", cmDB, Refresh,
        { description = ns.L["Healing potion family used by the Health_QUI macro."] })
    local hsW = GUI:CreateFormDropdown(s2.frame, nil, hsOpts, "selectedHealthstone", cmDB, Refresh,
        { description = ns.L["Healthstone variant used by the Stone_QUI macro."] })
    s2.AddRow(row(s2.frame, ns.L["Health Potion"], healthW), row(s2.frame, ns.L["Healthstone"], hsW))

    local augW = GUI:CreateFormDropdown(s2.frame, nil, augOpts, "selectedAugment", cmDB, Refresh,
        { description = ns.L["Augment rune family used by the Rune_QUI macro."] })
    local vantusW = GUI:CreateFormDropdown(s2.frame, nil, vantusOpts, "selectedVantus", cmDB, Refresh,
        { description = ns.L["Vantus rune the Vantus_QUI macro should use — useful for raid boss attempt buffs."] })
    s2.AddRow(row(s2.frame, ns.L["Augment Rune"], augW), row(s2.frame, ns.L["Vantus Rune"], vantusW))

    local weaponW = GUI:CreateFormDropdown(s2.frame, nil, weaponOpts, "selectedWeapon", cmDB, Refresh,
        { description = ns.L["Weapon oil, stone, or enchant consumable used by the Weapon_QUI macro."] })
    s2.AddRow(row(s2.frame, ns.L["Weapon Consumable"], weaponW))
    L.closeSection(s2)

    L.intro(ns.L["Creates per-character macros: Flask_QUI, Pot_QUI, Health_QUI, Stone_QUI, Rune_QUI, Vantus_QUI, Weapon_QUI. Drag them to your action bars."])
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

local function BuildMerchantGrid(L, db)
    local mDB = db and db.merchantGrid
    if not mDB then return end

    local function RefreshMerchantGrid()
        if QUI and QUI.MerchantGrid and QUI.MerchantGrid.Refresh then
            QUI.MerchantGrid.Refresh()
        end
    end

    L.headerAt(ns.L["Merchant Grid"])
    L.intro(ns.L["Show more vendor items at once by widening the merchant window into a Columns x Rows grid. At 2 columns x 5 rows it is identical to the default vendor. Vendors with more items than the grid holds still page normally. Reopen the vendor after changing these."])

    local s = L.sectionAt()
    local enableW = GUI:CreateFormCheckbox(s.frame, nil, "enabled", mDB, RefreshMerchantGrid,
        { description = ns.L["Enable the enlarged vendor item grid."] })
    s.AddRow(row(s.frame, ns.L["Enable Merchant Grid"], enableW))

    local colsW = GUI:CreateFormSlider(s.frame, nil, 2, 4, 1, "columns", mDB, RefreshMerchantGrid,
        { description = ns.L["Number of item columns per page (2-4)."] })
    local rowsW = GUI:CreateFormSlider(s.frame, nil, 5, 8, 1, "rows", mDB, RefreshMerchantGrid,
        { description = ns.L["Number of item rows per page (5-8)."] })
    s.AddRow(row(s.frame, ns.L["Columns"], colsW), row(s.frame, ns.L["Rows"], rowsW))

    local generalDB = db and db.general
    if generalDB then
        local petMarkW = GUI:CreateFormCheckbox(s.frame, nil, "merchantKnownPetMark", generalDB, function()
            if ns.RefreshMerchantPetMarks then ns.RefreshMerchantPetMarks() end
        end, { description = ns.L["Show a green check on merchant items that teach a battle pet you have already collected."] })
        s.AddRow(row(s.frame, ns.L["Mark Collected Pets"], petMarkW))
    end
    L.closeSection(s)

    if generalDB then
        if type(generalDB.vendorRules) ~= "table" then generalDB.vendorRules = {} end
        local vr = generalDB.vendorRules

        L.headerAt(ns.L["Vendor Sell Rules"])
        L.intro(ns.L["Rule-based auto-sell for equippable gear at merchants. Hard protections always apply: equipment-set items, gear still on an upgrade track, unbound tradeable gear, and never-sell items are never sold; at most 12 items per visit. Preview mode only prints what would be sold — turn it off once you trust your rules."])

        local sv = L.sectionAt()
        local vrEnableW = GUI:CreateFormCheckbox(sv.frame, nil, "enabled", vr, nil,
            { description = ns.L["Master toggle for vendor sell rules."] })
        local vrPreviewW = GUI:CreateFormCheckbox(sv.frame, nil, "previewOnly", vr, nil,
            { description = ns.L["Print what the rules would sell instead of selling. Strongly recommended until you've checked the output at a vendor."] })
        sv.AddRow(row(sv.frame, ns.L["Enable Vendor Rules"], vrEnableW), row(sv.frame, ns.L["Preview Mode (no selling)"], vrPreviewW))

        local qualityOptions = {
            { value = 1, text = ns.L["Common (white) and below"] },
            { value = 2, text = ns.L["Uncommon (green) and below"] },
            { value = 3, text = ns.L["Rare (blue) and below"] },
        }
        local vrQualityW = GUI:CreateFormDropdown(sv.frame, nil, qualityOptions, "maxQuality", vr, nil,
            { description = ns.L["Equippable weapons and armor at or below this quality are sellable (grey junk is handled by the junk seller)."] })
        local vrIlvlW = GUI:CreateFormSlider(sv.frame, nil, 0, 800, 5, "maxIlvl", vr, nil,
            { description = ns.L["Only sell gear BELOW this item level. 0 disables the item-level rule (quality alone decides)."] })
        sv.AddRow(row(sv.frame, ns.L["Max Sell Quality"], vrQualityW), row(sv.frame, ns.L["Only Below Item Level"], vrIlvlW))

        local vrForceW = GUI:CreateFormEditBox(sv.frame, nil, "forceSell", vr, nil,
            { maxLetters = 500, live = true },
            { description = ns.L["Item IDs to always sell (comma or space separated). Protections still apply."] })
        local vrNeverW = GUI:CreateFormEditBox(sv.frame, nil, "neverSell", vr, nil,
            { maxLetters = 500, live = true },
            { description = ns.L["Item IDs to never sell, on top of the built-in protections."] })
        sv.AddRow(row(sv.frame, ns.L["Force-Sell Item IDs"], vrForceW), row(sv.frame, ns.L["Never-Sell Item IDs"], vrNeverW))
        L.closeSection(sv)
    end
end

local function BuildFriendsList(L, db)
    local generalDB = db and db.general
    if not generalDB then return end

    local function Refresh()
        if ns.RefreshFriendsDecor then ns.RefreshFriendsDecor() end
    end

    L.headerAt(ns.L["Friends List"])
    L.intro(ns.L["Cosmetic tweaks for the Blizzard friends list."])

    local s = L.sectionAt()
    local classColorW = GUI:CreateFormCheckbox(s.frame, nil, "friendsClassColor", generalDB, Refresh,
        { description = ns.L["Color the names in the WoW friends list by class. Applies to regular friends and Battle.net friends currently playing WoW."] })
    local privacyW = GUI:CreateFormCheckbox(s.frame, nil, "communitiesPrivacy", generalDB, function()
        if ns.RefreshCommunitiesPrivacy then ns.RefreshCommunitiesPrivacy() end
    end, { description = ns.L["Stream safety: cover the Communities/guild chat and member list until you click the eye button to reveal them. Hides again every time the window reopens."] })
    s.AddRow(row(s.frame, ns.L["Class-Color Names"], classColorW), row(s.frame, ns.L["Communities Privacy Cover"], privacyW))
    L.closeSection(s)
end

local function BuildExtendedIgnore(L, db)
    local generalDB = db and db.general
    if not generalDB then return end
    if type(generalDB.extendedIgnore) ~= "table" then generalDB.extendedIgnore = {} end
    local cfg = generalDB.extendedIgnore

    local function Refresh()
        if ns.RefreshExtendedIgnore then ns.RefreshExtendedIgnore() end
    end

    L.headerAt(ns.L["Extended Ignore"])
    L.intro(ns.L["Suppress chat and auto-decline party invites, duels, and trades from a list of names, beyond Blizzard's ignore limit. Enter names separated by commas or new lines; realm suffixes are optional."])

    local s = L.sectionAt()
    local enableW = GUI:CreateFormCheckbox(s.frame, nil, "enabled", cfg, Refresh,
        { description = ns.L["Enable the extended ignore list."] })
    s.AddRow(row(s.frame, ns.L["Enable Extended Ignore"], enableW))

    local suppressW = GUI:CreateFormCheckbox(s.frame, nil, "suppressChat", cfg, Refresh,
        { description = ns.L["Hide public chat (say, yell, emotes, channels, whispers) from names on the list."] })
    local declineW = GUI:CreateFormCheckbox(s.frame, nil, "autoDecline", cfg, Refresh,
        { description = ns.L["Automatically decline party invites, duel requests, and trades from names on the list."] })
    s.AddRow(row(s.frame, ns.L["Suppress Their Chat"], suppressW), row(s.frame, ns.L["Auto-Decline Their Invites"], declineW))

    local namesW = GUI:CreateFormEditBox(s.frame, nil, "names", cfg, Refresh,
        { maxLetters = 1000, live = true },
        { description = ns.L["Character names to ignore, separated by commas or new lines. Realm names are optional (matching uses the character name only)."] })
    s.AddRow(row(s.frame, ns.L["Ignored Names"], namesW))
    L.closeSection(s)
end

local function BuildEventSounds(L, db)
    local generalDB = db and db.general
    if not generalDB then return end
    if type(generalDB.eventSounds) ~= "table" then generalDB.eventSounds = {} end
    local cfg = generalDB.eventSounds

    L.headerAt(ns.L["Event Sounds"])
    L.intro(ns.L["Play a sound when one of these events fires. Set an event to None to leave it silent. Requires Event Sounds to be enabled."])

    local s = L.sectionAt()
    local enableW = GUI:CreateFormCheckbox(s.frame, nil, "enabled", cfg, nil,
        { description = ns.L["Master toggle for event sound alerts."] })
    s.AddRow(row(s.frame, ns.L["Enable Event Sounds"], enableW))

    local soundList = Shared.GetSoundList()
    local whisperW = GUI:CreateFormDropdown(s.frame, nil, soundList, "whisper", cfg, nil,
        { description = ns.L["Sound played when you receive a whisper."] })
    local readyW = GUI:CreateFormDropdown(s.frame, nil, soundList, "readyCheck", cfg, nil,
        { description = ns.L["Sound played when a ready check starts."] })
    s.AddRow(row(s.frame, ns.L["Whisper"], whisperW), row(s.frame, ns.L["Ready Check"], readyW))

    local lfgW = GUI:CreateFormDropdown(s.frame, nil, soundList, "lfgProposal", cfg, nil,
        { description = ns.L["Sound played when a dungeon or raid group is found (LFG proposal)."] })
    local rezW = GUI:CreateFormDropdown(s.frame, nil, soundList, "resurrect", cfg, nil,
        { description = ns.L["Sound played when another player offers you a resurrection."] })
    s.AddRow(row(s.frame, ns.L["Group Found"], lfgW), row(s.frame, ns.L["Resurrection Offer"], rezW))

    local mailW = GUI:CreateFormDropdown(s.frame, nil, soundList, "mail", cfg, nil,
        { description = ns.L["Sound played when you receive new mail (only when new mail arrives, not on login)."] })
    local lootWonW = GUI:CreateFormDropdown(s.frame, nil, soundList, "lootRollWon", cfg, nil,
        { description = ns.L["Sound played when a loot roll is won. Bursts are throttled to one sound every couple of seconds."] })
    s.AddRow(row(s.frame, ns.L["New Mail"], mailW), row(s.frame, ns.L["Loot Roll Won"], lootWonW))

    local lootUpW = GUI:CreateFormDropdown(s.frame, nil, soundList, "lootUpgrade", cfg, nil,
        { description = ns.L["Sound played when an item you loot upgrades into a higher quality."] })
    s.AddRow(row(s.frame, ns.L["Loot Upgrade"], lootUpW))
    L.closeSection(s)
end

local function BuildSoundMute(L, generalDB)
    if not generalDB then return end
    if type(generalDB.soundMute) ~= "table" then generalDB.soundMute = {} end
    local soundDB = generalDB.soundMute

    L.headerAt(ns.L["Sound Mute"])
    L.intro(ns.L["Permanently silence selected game sounds — annoying mounts, repeated boss and NPC voice lines, interface pings, and more. Muting applies at login and takes effect immediately when toggled."])

    local function Refresh()
        if ns.RefreshSoundMute then ns.RefreshSoundMute() end
    end

    local entryWidgets = {}
    local function UpdateEntryState()
        local enabled = soundDB.enabled == true
        for _, w in ipairs(entryWidgets) do
            if w and w.SetEnabled then w:SetEnabled(enabled) end
        end
    end

    local enableSection = L.sectionAt()
    local enableW = GUI:CreateFormCheckbox(enableSection.frame, nil, "enabled", soundDB, function()
        UpdateEntryState()
        Refresh()
    end, { description = ns.L["Master toggle for Sound Mute. The categories below are only muted while this is on."] })
    enableSection.AddRow(row(enableSection.frame, ns.L["Enable Sound Mute"], enableW))
    L.closeSection(enableSection)

    local catalog = ns.SoundMuteCatalog
    if not catalog or not catalog.categories then
        UpdateEntryState()
        return
    end

    for _, category in ipairs(catalog.categories) do
        L.headerAt(category.label)
        local section = L.sectionAt()
        local pending = nil
        for _, entry in ipairs(category.entries) do
            local w = GUI:CreateFormCheckbox(section.frame, nil, entry.key, soundDB, Refresh)
            table.insert(entryWidgets, w)
            local cell = row(section.frame, entry.label, w)
            if pending then
                section.AddRow(pending, cell)
                pending = nil
            else
                pending = cell
            end
        end
        if pending then section.AddRow(pending) end
        L.closeSection(section)
    end

    UpdateEntryState()
end

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
    merchantGrid     = function(L, db) BuildMerchantGrid(L, db) end,
    friendsList      = function(L, db) BuildFriendsList(L, db) end,
    extendedIgnore   = function(L, db) BuildExtendedIgnore(L, db) end,
    eventSounds      = function(L, db) BuildEventSounds(L, db) end,
    soundMute        = function(L, db) BuildSoundMute(L, db and db.general) end,
}

local SECTION_ORDER = {
    "settingsPanel", "uiScale", "defaultFonts", "fpsPreset", "combatText",
    "automation", "popupBlocker", "quickSalvage", "consumables",
    "consumableMacros", "targetDistance", "quiPanel", "reloadBehavior",
    "merchantGrid",
    "friendsList",
    "extendedIgnore",
    "eventSounds",
    "soundMute",
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
    { id = "merchantGrid",      category = "qol",        nav = { tileId = "qol", subPageIndex = 10 }, sectionKey = "merchantGrid",     sectionTitle = "Merchant Grid",                    searchContext = { tabIndex = 17, tabName = "Quality of Life", subTabIndex = 10, subTabName = "Merchant" } },
    { id = "friendsList",       category = "qol",        nav = { tileId = "qol", subPageIndex = 11 }, sectionKey = "friendsList",      sectionTitle = "Friends List",                     searchContext = { tabIndex = 17, tabName = "Quality of Life", subTabIndex = 11, subTabName = "Friends List" } },
    { id = "extendedIgnore",    category = "qol",        nav = { tileId = "qol", subPageIndex = 12 }, sectionKey = "extendedIgnore",   sectionTitle = "Extended Ignore",                  searchContext = { tabIndex = 17, tabName = "Quality of Life", subTabIndex = 12, subTabName = "Extended Ignore" } },
    { id = "eventSounds",       category = "qol",        nav = { tileId = "qol", subPageIndex = 13 }, sectionKey = "eventSounds",      sectionTitle = "Event Sounds",                     searchContext = { tabIndex = 17, tabName = "Quality of Life", subTabIndex = 13, subTabName = "Event Sounds" } },
    { id = "soundMute",         category = "qol",        nav = { tileId = "qol", subPageIndex = 14 }, sectionKey = "soundMute",        sectionTitle = "Sound Mute",                       searchContext = { tabIndex = 17, tabName = "Quality of Life", subTabIndex = 14, subTabName = "Sound Mute" } },
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
