local ADDON_NAME, ns = ...
local FoldSearchUTF8 = ns.Helpers.FoldSearchUTF8
local function CJKFont(fs, p, s, f)
    if ns.Helpers and ns.Helpers.ApplyFontWithFallback then
        ns.Helpers.ApplyFontWithFallback(fs, p, s, f)
    else
        fs:SetFont(p, s, f)
    end
end
local QUI = QUI
local GUI = QUI.GUI
local C = GUI.Colors
local Shared = ns.QUI_Options
local Settings = ns.Settings
local Registry = Settings and Settings.Registry
local Schema = Settings and Settings.Schema
local QUICore = ns.Addon

local PADDING = Shared.PADDING
local CreateScrollableContent = Shared.CreateScrollableContent

local FORM_ROW = 32
local PAD = 10
local COPY_LABEL_WIDTH = 72
local COPY_DROPDOWN_WIDTH = 420
local COPY_CONTROL_GAP = 12
local BINDINGS_SECTION_GAP = 22
local UIKit = ns.UIKit

local spellCache = {}
local spellCacheBuilt = false

local function RebuildSpellCache()
    wipe(spellCache)
    spellCacheBuilt = false
    if not C_SpellBook or not C_SpellBook.GetNumSpellBookSkillLines then return end
    local ok, numTabs = pcall(C_SpellBook.GetNumSpellBookSkillLines)
    if not ok or not numTabs then return end
    for tab = 1, numTabs do
        local okL, sli = pcall(C_SpellBook.GetSpellBookSkillLineInfo, tab)
        if okL and sli then
            local offset = sli.itemIndexOffset or 0
            for i = 1, (sli.numSpellBookItems or 0) do
                local okI, info = pcall(C_SpellBook.GetSpellBookItemInfo, offset + i, Enum.SpellBookSpellBank.Player)
                if okI and info and info.spellID then
                    local isPassive = false
                    if C_SpellBook.IsSpellBookItemPassive then
                        local okP, p = pcall(C_SpellBook.IsSpellBookItemPassive, offset + i, Enum.SpellBookSpellBank.Player)
                        if okP then isPassive = p end
                    end
                    if not isPassive and not info.isOffSpec then
                        local isKnown = IsPlayerSpell and IsPlayerSpell(info.spellID)
                        if not isKnown and C_Spell.GetBaseSpell then
                            local baseCheck = C_Spell.GetBaseSpell(info.spellID)
                            if baseCheck and baseCheck ~= info.spellID then
                                isKnown = IsPlayerSpell(baseCheck)
                            end
                        end

                        if isKnown then
                            local name = C_Spell.GetSpellName(info.spellID)
                            if name then
                                local spellInfo = C_Spell.GetSpellInfo(info.spellID)
                                local icon = spellInfo and spellInfo.iconID
                                local baseID = C_Spell.GetBaseSpell and C_Spell.GetBaseSpell(info.spellID)
                                local baseName
                                if baseID and baseID ~= info.spellID then
                                    baseName = C_Spell.GetSpellName(baseID)
                                    if baseName == name then baseName = nil end
                                end
                                table.insert(spellCache, { spellID = info.spellID, name = name, baseName = baseName, icon = icon, tab = sli.name or "General" })
                            end
                        end
                    end
                end
            end
        end
    end
    table.sort(spellCache, function(a, b)
        if a.tab == b.tab then return a.name < b.name end
        return a.tab < b.tab
    end)
    spellCacheBuilt = true
end

local function EnsureSpellCache()
    if not spellCacheBuilt then RebuildSpellCache() end
    return spellCache
end

local function SetSizePx(frame, widthPixels, heightPixels)
    if UIKit and UIKit.SetSizePx then
        UIKit.SetSizePx(frame, widthPixels, heightPixels)
    elseif QUICore and QUICore.SetPixelPerfectSize then
        QUICore:SetPixelPerfectSize(frame, widthPixels, heightPixels)
    else
        frame:SetSize(widthPixels or 0, heightPixels or 0)
    end
end

local function SetHeightPx(frame, heightPixels)
    if UIKit and UIKit.SetHeightPx then
        UIKit.SetHeightPx(frame, heightPixels)
    elseif QUICore and QUICore.SetPixelPerfectHeight then
        QUICore:SetPixelPerfectHeight(frame, heightPixels)
    else
        frame:SetHeight(heightPixels or 0)
    end
end

local function EnsurePixelBackdropCompat(frame)
    if not frame then return nil end
    local uikit = ns.UIKit or UIKit
    if frame._quiPixelBackdropCompat then
        return frame._quiPixelBackdropCompat
    end

    local state = {
        borderPixels = 1,
        withBackground = false,
        bgColor = { 0, 0, 0, 1 },
        borderColor = { 1, 1, 1, 1 },
        originalSetBackdropColor = frame.SetBackdropColor,
        originalSetBackdropBorderColor = frame.SetBackdropBorderColor,
    }

    if uikit and uikit.CreateBackground then
        state.bg = uikit.CreateBackground(frame, 0, 0, 0, 0)
        if state.bg and state.bg.Hide then
            state.bg:Hide()
        end
    end

    if frame.SetBackdrop then
        frame:SetBackdrop(nil)
    end

    if uikit and uikit.CreateBorderLines and uikit.UpdateBorderLines then
        uikit.CreateBorderLines(frame)
    end

    frame.SetBackdropColor = function(self, r, g, b, a)
        local compat = self and self._quiPixelBackdropCompat
        if not compat then return end
        compat.bgColor[1], compat.bgColor[2], compat.bgColor[3], compat.bgColor[4] = r or 0, g or 0, b or 0, a or 1

        if compat.bg and compat.bg.SetVertexColor then
            compat.bg:SetVertexColor(compat.bgColor[1], compat.bgColor[2], compat.bgColor[3], compat.bgColor[4])
            if compat.withBackground then
                compat.bg:Show()
            else
                compat.bg:Hide()
            end
        elseif compat.originalSetBackdropColor then
            compat.originalSetBackdropColor(self, compat.bgColor[1], compat.bgColor[2], compat.bgColor[3], compat.bgColor[4])
        end
    end

    frame.SetBackdropBorderColor = function(self, r, g, b, a)
        local compat = self and self._quiPixelBackdropCompat
        if not compat then return end
        compat.borderColor[1], compat.borderColor[2], compat.borderColor[3], compat.borderColor[4] = r or 0, g or 0, b or 0, a or 1

        if uikit and uikit.UpdateBorderLines then
            uikit.UpdateBorderLines(self, compat.borderPixels or 1, compat.borderColor[1], compat.borderColor[2], compat.borderColor[3], compat.borderColor[4], false)
        elseif compat.originalSetBackdropBorderColor then
            compat.originalSetBackdropBorderColor(self, compat.borderColor[1], compat.borderColor[2], compat.borderColor[3], compat.borderColor[4])
        end
    end

    if uikit and uikit.RegisterScaleRefresh then
        uikit.RegisterScaleRefresh(frame, "groupFrameDesignerBackdropCompat", function(owner)
            local compat = owner and owner._quiPixelBackdropCompat
            if not compat then return end
            if compat.bg and compat.bg.SetVertexColor then
                compat.bg:SetVertexColor(compat.bgColor[1], compat.bgColor[2], compat.bgColor[3], compat.bgColor[4])
                if compat.withBackground then
                    compat.bg:Show()
                else
                    compat.bg:Hide()
                end
            end
            if uikit and uikit.UpdateBorderLines then
                uikit.UpdateBorderLines(owner, compat.borderPixels or 1, compat.borderColor[1], compat.borderColor[2], compat.borderColor[3], compat.borderColor[4], false)
            end
        end)
    end

    frame._quiPixelBackdropCompat = state
    return state
end

local function ApplyPixelBackdrop(frame, borderPixels, withBackground)
    if not frame then return end
    local uikit = ns.UIKit or UIKit

    if uikit and uikit.CreateBorderLines and uikit.UpdateBorderLines and uikit.CreateBackground then
        local compat = EnsurePixelBackdropCompat(frame)
        if not compat then return end
        compat.borderPixels = borderPixels or 1
        compat.withBackground = withBackground and true or false
        frame:SetBackdropColor(compat.bgColor[1], compat.bgColor[2], compat.bgColor[3], compat.bgColor[4])
        frame:SetBackdropBorderColor(compat.borderColor[1], compat.borderColor[2], compat.borderColor[3], compat.borderColor[4])
        return
    end

    if not frame.SetBackdrop then return end
    if QUICore and QUICore.SetPixelPerfectBackdrop then
        QUICore:SetPixelPerfectBackdrop(frame, borderPixels or 1, withBackground and "Interface\\Buttons\\WHITE8x8" or nil)
        return
    end

    local px = QUICore and QUICore.GetPixelSize and QUICore:GetPixelSize(frame) or 1
    local edgeSize = (borderPixels or 1) * px
    frame:SetBackdrop({
        bgFile = withBackground and "Interface\\Buttons\\WHITE8x8" or nil,
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = edgeSize,
    })
end

local function CreateClickCastButton(parent, text, width, height, onClick, variant)
    local button = GUI:CreateButton(parent, text or "", width or 1, height or 24, onClick, variant or "ghost")
    if width and width > 0 and height and height > 0 then
        SetSizePx(button, width, height)
    elseif height and height > 0 then
        SetHeightPx(button, height)
    end

    if UIKit and UIKit.CreateBackdropBorder then
        if UIKit.UpdateBorderLines then
            UIKit.UpdateBorderLines(button, 0, 0, 0, 0, 0, true)
        end
        button._clickCastBorder = UIKit.CreateBackdropBorder(button, 1, 1, 1, 1, 0.2)
        button.SetBorderColor = function(self, r, g, b, a)
            local border = self and self._clickCastBorder
            if border and border.SetBackdropBorderColor then
                border:SetBackdropBorderColor(r, g, b, a or 1)
            elseif UIKit and UIKit.UpdateBorderLines then
                UIKit.UpdateBorderLines(self, 1, r, g, b, a or 1, false)
            end
        end
        button.SetFieldBorderColor = button.SetBorderColor
    end

    return button
end

local function SetButtonBorder(button, r, g, b, a)
    if not button then return end
    if button.SetBorderColor then
        button:SetBorderColor(r, g, b, a or 1)
    elseif UIKit and UIKit.UpdateBorderLines then
        UIKit.UpdateBorderLines(button, 1, r, g, b, a or 1, false)
    elseif button.SetBackdropBorderColor then
        button:SetBackdropBorderColor(r, g, b, a or 1)
    end
end

local function SetButtonHover(button, shown, r, g, b, a)
    local hover = button and button._hoverBg
    if not hover then return end
    if r then
        hover:SetColorTexture(r, g or r, b or r, a or 0.06)
    end
    if shown then
        hover:Show()
    else
        hover:Hide()
    end
end

local function SetButtonFill(button, r, g, b, a)
    if not button then return end
    if not button._clickCastFill then
        button._clickCastFill = button:CreateTexture(nil, "BACKGROUND", nil, -1)
        button._clickCastFill:SetAllPoints(button)
    end
    button._clickCastFill:SetColorTexture(r or 0, g or 0, b or 0, a or 0)
end

local function RefreshGF()
    if _G.QUI_RefreshGroupFrames then
        _G.QUI_RefreshGroupFrames()
    end
end

local SEARCH_TAB_INDEX = 7
local SEARCH_TAB_NAME = "Click-Cast"
local SEARCH_SUBTAB_GENERAL_INDEX = 1
local SEARCH_SUBTAB_GENERAL_NAME = "Click-Cast"

local function SetGeneralSearchContext(sectionName)
    GUI:SetSearchContext({
        tabIndex = SEARCH_TAB_INDEX,
        tabName = SEARCH_TAB_NAME,
        subTabIndex = SEARCH_SUBTAB_GENERAL_INDEX,
        subTabName = SEARCH_SUBTAB_GENERAL_NAME,
        sectionName = sectionName,
    })
end

local function MakeLayout(content)
    local L = ns.QUI_SettingsLayoutShared.MakeLayout(content)
    L.offset = L.getY
    return L
end

local function row(parent, label, widget, desc)
    return Shared.BuildSettingRow(parent, label, widget, desc)
end

local function pairCells(card, cells)
    local i = 1
    while i <= #cells do
        local left = cells[i]
        local right = cells[i + 1]
        if right then
            card.AddRow(left, right)
            i = i + 2
        else
            card.AddRow(left)
            i = i + 1
        end
    end
end

local function BuildClickCastGeneral(L, cc, refreshClickCast, state)
    L.headerAt(ns.L["Settings"])
    L.intro(ns.L["Note: If Clique addon is loaded, QUI click-casting is disabled by default to avoid conflicts."])

    local s = L.sectionAt()
    local enableW = GUI:CreateFormCheckbox(s.frame, nil, "enabled", cc, refreshClickCast,
        { description = ns.L["Master toggle for QUI's click-cast system. When on, clicks and key presses on raid/party/unit frames fire the bindings configured below instead of just targeting."] })
    local perSpecW = GUI:CreateFormCheckbox(s.frame, nil, "perSpec", cc, refreshClickCast,
        { description = ns.L["Maintain a separate list of click-cast bindings for each specialization. Bindings you add swap automatically when you change spec."] })
    local perLoadoutW = GUI:CreateFormCheckbox(s.frame, nil, "perLoadout", cc, refreshClickCast,
        { description = ns.L["Also split bindings per talent loadout within each spec, so each saved loadout can have its own click-cast layout. Requires Per-Spec Bindings."] })
    local smartResW = GUI:CreateFormCheckbox(s.frame, nil, "smartRes", cc, refreshClickCast,
        { description = ns.L["When hovering a dead unit, any spell binding is temporarily replaced by your class's resurrection spell if you know one. Restores the original spell when the unit is alive."] })
    local tooltipW = GUI:CreateFormCheckbox(s.frame, nil, "showTooltip", cc, RefreshGF,
        { description = ns.L["Append a summary of your current click-cast bindings to the unit tooltip whenever you hover a group frame, so you can see at a glance which click does what."] })

    local CLICK_DIRECTION_OPTIONS = {
        { value = "down", text = ns.L["On Key Down"] },
        { value = "up",   text = ns.L["On Key Up"] },
        { value = "both", text = ns.L["On Both"] },
    }
    local clickDirDrop = GUI:CreateFormDropdown(s.frame, nil, CLICK_DIRECTION_OPTIONS,
        "clickDirection", cc, refreshClickCast,
        { description = ns.L["When spells fire: On Key Down casts as soon as you press the button (lower latency), On Key Up casts when you release, On Both fires on press and again on release."] })

    local perLoadoutCell = row(s.frame, ns.L["Per-Loadout Bindings"], perLoadoutW)
    pairCells(s, {
        row(s.frame, ns.L["Enable Click-Casting"], enableW),
        row(s.frame, ns.L["Per-Spec Bindings"], perSpecW),
        perLoadoutCell,
        row(s.frame, ns.L["Smart Resurrection"], smartResW),
        row(s.frame, ns.L["Show Binding Tooltip on Hover"], tooltipW),
        row(s.frame, ns.L["Click Direction"], clickDirDrop),
    })
    L.closeSection(s)

    local function UpdatePerLoadoutVisibility()
        perLoadoutCell:SetEnabled(cc.perSpec and true or false)
    end
    UpdatePerLoadoutVisibility()

    if not cc.unitFrames then cc.unitFrames = {} end
    L.intro(ns.L["Also apply click-casting to unit frames:"])

    local ufFrames = {
        { key = "player",       label = ns.L["Player"],           description = ns.L["Let click-cast bindings fire when you click the player unit frame, not just group or nameplate frames."] },
        { key = "target",       label = ns.L["Target"],           description = ns.L["Let click-cast bindings fire when you click the target unit frame."] },
        { key = "targettarget", label = ns.L["Target of Target"], description = ns.L["Let click-cast bindings fire when you click the target-of-target unit frame."] },
        { key = "focus",        label = ns.L["Focus"],            description = ns.L["Let click-cast bindings fire when you click the focus unit frame."] },
        { key = "pet",          label = ns.L["Pet"],              description = ns.L["Let click-cast bindings fire when you click the pet unit frame."] },
        { key = "boss",         label = ns.L["Boss"],             description = ns.L["Let click-cast bindings fire when you click boss unit frames during encounters."] },
    }

    local uf = L.sectionAt()
    local ufCells = {}
    for _, info in ipairs(ufFrames) do
        local ufCheck = GUI:CreateFormCheckbox(uf.frame, nil, info.key, cc.unitFrames, refreshClickCast,
            { description = info.description })
        ufCells[#ufCells + 1] = row(uf.frame, info.label, ufCheck)
    end
    pairCells(uf, ufCells)
    L.closeSection(uf)

    if state then
        state.perSpecCheck = perSpecW
        state.perLoadoutCheck = perLoadoutW
        state.UpdatePerLoadoutVisibility = UpdatePerLoadoutVisibility
    end
end

local function BuildClickCastPings(L, state)
    L.headerAt(ns.L["Global Ping Keybinds"])
    L.intro(ns.L["These keybinds work everywhere: nameplates, world mouseover, or current target. Pings the unit you're looking at."])

    local PING_KEYBIND_ENTRIES = {
        { binding = "TOGGLEPINGLISTENER", label = ns.L["Ping (Contextual)"] },
        { binding = "PINGASSIST",         label = ns.L["Ping: Assist"] },
        { binding = "PINGATTACK",         label = ns.L["Ping: Attack"] },
        { binding = "PINGWARNING",        label = ns.L["Ping: Warning"] },
        { binding = "PINGONMYWAY",        label = ns.L["Ping: On My Way"] },
    }

    local refreshAllPingRows
    local pingRowUpdaters = {}
    local pingCaptureButtons = {}
    local suspendedPingBindings = {}
    local isPingSuspended = false
    local PING_BUTTON_HEIGHT = 24
    local PING_CAPTURE_WIDTH = 130
    local PING_CLEAR_WIDTH = 44

    local function CreatePingKeybindCell(parent, entry)
        local widget = CreateFrame("Frame", nil, parent)
        widget:SetSize(PING_CAPTURE_WIDTH + PING_CLEAR_WIDTH + 6, PING_BUTTON_HEIGHT)

        local captureBtn = CreateClickCastButton(widget, "", PING_CAPTURE_WIDTH, PING_BUTTON_HEIGHT)
        captureBtn:SetPoint("LEFT", widget, "LEFT", 0, 0)
        SetButtonFill(captureBtn, 0.08, 0.08, 0.08, 1)
        SetButtonBorder(captureBtn, 0.35, 0.35, 0.35, 1)

        local keyText = captureBtn.text
        if keyText then
            CJKFont(keyText, GUI.FONT_PATH, 11, "")
        end

        local function UpdateKeyText()
            local key1 = GetBindingKey(entry.binding)
            if key1 then
                captureBtn:SetText(key1)
                if keyText then keyText:SetTextColor(C.text[1], C.text[2], C.text[3], 1) end
            else
                captureBtn:SetText(ns.L["Not bound"])
                if keyText then keyText:SetTextColor(C.textMuted[1], C.textMuted[2], C.textMuted[3], 1) end
            end
        end
        table.insert(pingRowUpdaters, UpdateKeyText)
        UpdateKeyText()

        local clearBtn = CreateClickCastButton(widget, ns.L["Clear"], PING_CLEAR_WIDTH, PING_BUTTON_HEIGHT, function()
            local key1, key2 = GetBindingKey(entry.binding)
            if key1 then SetBinding(key1) end
            if key2 then SetBinding(key2) end
            SaveBindings(GetCurrentBindingSet())
            if refreshAllPingRows then refreshAllPingRows() else UpdateKeyText() end
        end)
        clearBtn:SetPoint("LEFT", captureBtn, "RIGHT", 6, 0)
        SetButtonBorder(clearBtn, 1, 1, 1, 0.2)
        GUI:AttachTooltip(clearBtn, ns.L["Remove the current keybind for this ping action. The action stays defined but is no longer bound to a key."], ns.L["Clear Binding"])

        captureBtn.isCapturing = false
        captureBtn:EnableKeyboard(false)
        captureBtn:RegisterForClicks("AnyDown")
        captureBtn:EnableMouseWheel(true)
        table.insert(pingCaptureButtons, captureBtn)

        local function SuspendPingBindings()
            if isPingSuspended then return end
            wipe(suspendedPingBindings)
            for _, other in ipairs(PING_KEYBIND_ENTRIES) do
                local key1, key2 = GetBindingKey(other.binding)
                if key1 or key2 then
                    suspendedPingBindings[other.binding] = { key1, key2 }
                    if key1 then SetBinding(key1) end
                    if key2 then SetBinding(key2) end
                end
            end
            isPingSuspended = true
        end

        local function RestorePingBindings()
            if not isPingSuspended then return end
            for action, keys in pairs(suspendedPingBindings) do
                if keys[1] then SetBinding(keys[1], action) end
                if keys[2] then SetBinding(keys[2], action) end
            end
            wipe(suspendedPingBindings)
            isPingSuspended = false
        end

        local function FinishCapture(self, fullKey)
            for _, other in ipairs(PING_KEYBIND_ENTRIES) do
                if other.binding ~= entry.binding then
                    local keys = suspendedPingBindings[other.binding]
                    if keys then
                        if keys[1] and keys[1] ~= fullKey then SetBinding(keys[1], other.binding) end
                        if keys[2] and keys[2] ~= fullKey then SetBinding(keys[2], other.binding) end
                    end
                end
            end
            wipe(suspendedPingBindings)
            isPingSuspended = false

            SetBinding(fullKey, entry.binding)
            SaveBindings(GetCurrentBindingSet())

            self.isCapturing = false
            self:EnableKeyboard(false)
            SetButtonBorder(self, 0.35, 0.35, 0.35, 1)
            SetButtonHover(self, false)
            if refreshAllPingRows then refreshAllPingRows() end
        end

        local function CancelCapture(self)
            RestorePingBindings()
            self.isCapturing = false
            self:EnableKeyboard(false)
            SetButtonBorder(self, 0.35, 0.35, 0.35, 1)
            SetButtonHover(self, false)
            UpdateKeyText()
        end

        local function GetModifierPrefix()
            local mods = ""
            if IsAltKeyDown() then mods = mods .. "ALT-" end
            if IsControlKeyDown() then mods = mods .. "CTRL-" end
            if IsShiftKeyDown() then mods = mods .. "SHIFT-" end
            return mods
        end

        local MOUSE_BIND_NAMES = {
            LeftButton = "BUTTON1", RightButton = "BUTTON2",
            MiddleButton = "BUTTON3", Button4 = "BUTTON4", Button5 = "BUTTON5",
        }

        captureBtn:SetScript("OnClick", function(self, button)
            if not self.isCapturing then
                if button == "LeftButton" then
                    SuspendPingBindings()
                    self.isCapturing = true
                    self:EnableKeyboard(true)
                    SetButtonBorder(self, C.accent[1], C.accent[2], C.accent[3], 1)
                    captureBtn:SetText(ns.L["Press a key or click..."])
                    if keyText then keyText:SetTextColor(C.accent[1], C.accent[2], C.accent[3], 1) end
                end
                return
            end
            local bindName = MOUSE_BIND_NAMES[button]
            if not bindName then return end
            local mods = GetModifierPrefix()
            if button == "LeftButton" and mods == "" then
                CancelCapture(self)
                return
            end
            FinishCapture(self, mods .. bindName)
        end)
        captureBtn:SetScript("OnMouseWheel", function(self, delta)
            if not self.isCapturing then return end
            local scrollKey = delta > 0 and "MOUSEWHEELUP" or "MOUSEWHEELDOWN"
            FinishCapture(self, GetModifierPrefix() .. scrollKey)
        end)
        captureBtn:SetScript("OnKeyDown", function(self, key)
            if not self.isCapturing then self:SetPropagateKeyboardInput(true) return end
            self:SetPropagateKeyboardInput(false)
            if key == "ESCAPE" then
                CancelCapture(self)
                return
            end
            if key == "LSHIFT" or key == "RSHIFT" or key == "LCTRL" or key == "RCTRL"
               or key == "LALT" or key == "RALT" then
                return
            end
            FinishCapture(self, GetModifierPrefix() .. key)
        end)
        captureBtn:SetScript("OnEnter", function(self)
            if not self.isCapturing then
                SetButtonBorder(self, C.accent[1], C.accent[2], C.accent[3], 0.7)
                SetButtonHover(self, true, C.accent[1], C.accent[2], C.accent[3], 0.08)
            end
        end)
        captureBtn:SetScript("OnLeave", function(self)
            if not self.isCapturing then
                SetButtonBorder(self, 0.35, 0.35, 0.35, 1)
                SetButtonHover(self, false)
            end
        end)

        return row(parent, entry.label, widget)
    end

    local s = L.sectionAt()
    local pingCells = {}
    for _, entry in ipairs(PING_KEYBIND_ENTRIES) do
        pingCells[#pingCells + 1] = CreatePingKeybindCell(s.frame, entry)
    end
    pairCells(s, pingCells)
    L.closeSection(s)

    refreshAllPingRows = function()
        for _, updater in ipairs(pingRowUpdaters) do
            updater()
        end
    end

    if state then
        state.pingCaptureButtons = pingCaptureButtons
        state.isPingSuspended = function() return isPingSuspended end
        state.suspendedPingBindings = suspendedPingBindings
        state.clearPingSuspension = function()
            local saved = {}
            for k, v in pairs(suspendedPingBindings) do saved[k] = v end
            wipe(suspendedPingBindings)
            isPingSuspended = false
            return saved
        end
    end
end

local browsePopupHandle

local function EnsureBrowsePopup()
    if browsePopupHandle then return browsePopupHandle end

    local browsePopup = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    browsePopup:SetSize(320, 400)
    browsePopup:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    browsePopup:SetFrameStrata("TOOLTIP")
    browsePopup:SetFrameLevel(1000)
    browsePopup:SetToplevel(true)
    browsePopup:SetMovable(true)
    browsePopup:EnableMouse(true)
    browsePopup:RegisterForDrag("LeftButton")
    browsePopup:SetScript("OnDragStart", function(self) self:StartMoving() end)
    browsePopup:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
    ApplyPixelBackdrop(browsePopup, 1, true)
    browsePopup:SetBackdropColor(0.06, 0.06, 0.06, 0.97)
    browsePopup:SetBackdropBorderColor(C.accent[1], C.accent[2], C.accent[3], 0.8)
    browsePopup:Hide()

    local browseTitle = browsePopup:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    browseTitle:SetPoint("TOPLEFT", 10, -8)
    browseTitle:SetText(ns.L["Browse Spells"])
    CJKFont(browseTitle, GUI.FONT_PATH, 12, "")
    browseTitle:SetTextColor(C.accent[1], C.accent[2], C.accent[3], 1)

    UIKit.CreateCloseButton(browsePopup, {
        size = 20,
        point = "TOPRIGHT",
        x = -6,
        y = -6,
        onClick = function() browsePopup:Hide() end,
    })

    local browseSearchBg = CreateFrame("Frame", nil, browsePopup, "BackdropTemplate")
    browseSearchBg:SetPoint("TOPLEFT", 8, -28)
    browseSearchBg:SetPoint("RIGHT", browsePopup, "RIGHT", -8, 0)
    SetHeightPx(browseSearchBg, 24)
    ApplyPixelBackdrop(browseSearchBg, 1, true)
    browseSearchBg:SetBackdropColor(0.08, 0.08, 0.08, 1)
    browseSearchBg:SetBackdropBorderColor(0.35, 0.35, 0.35, 1)

    local browseSearch = CreateFrame("EditBox", nil, browseSearchBg)
    browseSearch:SetPoint("LEFT", 8, 0)
    browseSearch:SetPoint("RIGHT", -8, 0)
    browseSearch:SetHeight(22)
    browseSearch:SetAutoFocus(false)
    CJKFont(browseSearch, GUI.FONT_PATH, 11, "")
    browseSearch:SetTextColor(C.text[1], C.text[2], C.text[3], 1)
    browseSearch:SetText("")

    local browseSearchPlaceholder = browseSearchBg:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    browseSearchPlaceholder:SetPoint("LEFT", 8, 0)
    browseSearchPlaceholder:SetText(ns.L["Search spells..."])
    CJKFont(browseSearchPlaceholder, GUI.FONT_PATH, 11, "")
    browseSearchPlaceholder:SetTextColor(C.textMuted[1], C.textMuted[2], C.textMuted[3], 0.6)
    browseSearch:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

    local SCROLLBAR_WIDTH = 4
    local SCROLL_STEP = 45

    local browseScroll = CreateFrame("ScrollFrame", nil, browsePopup)
    browseScroll:SetPoint("TOPLEFT", 8, -58)
    browseScroll:SetPoint("BOTTOMRIGHT", -(8 + SCROLLBAR_WIDTH + 2), 8)

    local browseScrollChild = CreateFrame("Frame", nil, browseScroll)
    browseScrollChild:SetWidth(browseScroll:GetWidth() or 296)
    browseScrollChild:SetHeight(1)
    browseScroll:SetScrollChild(browseScrollChild)

    -- Rows are laid out synchronously into browseScrollChild; measure overflow
    -- from it rather than the native range, which lags a layout pass behind.
    local function BrowseRange()
        return math.max(0, (browseScrollChild:GetHeight() or 0) - (browseScroll:GetHeight() or 0))
    end

    browseScroll:SetScript("OnSizeChanged", function(self, w)
        browseScrollChild:SetWidth(w or 296)
    end)

    local uikit = ns.UIKit or UIKit
    local browseScrollBar = uikit.CreateScrollBar(browseScroll, {
        parent = browsePopup,
        anchor = browsePopup,
        offsetX = -8,
        insetTop = 58,
        insetBottom = 8,
        width = SCROLLBAR_WIDTH,
        getRange = BrowseRange,
    })
    local browseScrollCtl = uikit.AttachSmoothScroll(browseScroll, {
        step = SCROLL_STEP,
        getRange = BrowseRange,
    })
    local function UpdateBrowseThumb()
        browseScrollBar:Update()
    end

    local BROWSE_ROW_H = 24
    local browseRows = {}
    local browseRowIndex = 0
    local expandedTabs = {}

    local function GetOrCreateSpellRow()
        browseRowIndex = browseRowIndex + 1
        local row = browseRows[browseRowIndex]
        if row and row.isSpellRow then
            row:ClearAllPoints()
            row:Show()
            return row
        end
        row = CreateFrame("Button", nil, browseScrollChild)
        row.isSpellRow = true
        row.icon = row:CreateTexture(nil, "ARTWORK")
        row.icon:SetSize(18, 18)
        row.icon:SetPoint("LEFT", 4, 0)
        row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        row.text = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        row.text:SetPoint("LEFT", row.icon, "RIGHT", 4, 0)
        row.text:SetPoint("RIGHT", row, "RIGHT", -4, 0)
        row.text:SetJustifyH("LEFT")
        CJKFont(row.text, GUI.FONT_PATH, 11, "")
        local hl = row:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints()
        hl:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 0.15)
        row:SetScript("OnClick", function(self)
            if self.spellName then
                if browsePopupHandle and browsePopupHandle.onPick then
                    browsePopupHandle.onPick(self.spellName)
                end
                browsePopup:Hide()
            end
        end)
        browseRows[browseRowIndex] = row
        return row
    end

    local function GetOrCreateHeaderRow()
        browseRowIndex = browseRowIndex + 1
        local row = browseRows[browseRowIndex]
        if row and not row.isSpellRow then
            row:ClearAllPoints()
            row:Show()
            return row
        end
        row = CreateFrame("Button", nil, browseScrollChild)
        row.isSpellRow = false

        row.chevron = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        row.chevron:SetPoint("LEFT", 2, 0)
        CJKFont(row.chevron, GUI.FONT_PATH, 10, "")
        row.chevron:SetTextColor(C.accent[1], C.accent[2], C.accent[3], 0.6)

        row.text = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        row.text:SetPoint("LEFT", row.chevron, "RIGHT", 4, 0)
        CJKFont(row.text, GUI.FONT_PATH, 10, "")

        local hl = row:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints()
        hl:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 0.08)

        browseRows[browseRowIndex] = row
        return row
    end

    local BuildBrowseList

    local function BuildBrowseListImpl(filter)
        for _, row in ipairs(browseRows) do row:Hide() end
        browseRowIndex = 0

        local spells = EnsureSpellCache()
        local lower = filter and filter ~= "" and FoldSearchUTF8(filter) or nil
        local by = 0
        local currentTab = nil

        local ignoreCollapse = lower ~= nil

        for _, entry in ipairs(spells) do
            if not lower or FoldSearchUTF8(entry.name):find(lower, 1, true) or (entry.baseName and FoldSearchUTF8(entry.baseName):find(lower, 1, true)) then
                if entry.tab ~= currentTab then
                    currentTab = entry.tab
                    local isCollapsed = not ignoreCollapse and not expandedTabs[currentTab]
                    local headerRow = GetOrCreateHeaderRow()
                    headerRow:SetHeight(BROWSE_ROW_H)
                    headerRow:SetPoint("TOPLEFT", 0, by)
                    headerRow:SetPoint("RIGHT", browseScrollChild, "RIGHT", 0, 0)
                    headerRow.text:SetText(currentTab)
                    headerRow.text:SetTextColor(C.accent[1], C.accent[2], C.accent[3], 0.8)
                    headerRow.chevron:SetText(isCollapsed and ">" or "v")
                    headerRow.tabName = currentTab
                    headerRow:SetScript("OnClick", function(self)
                        expandedTabs[self.tabName] = not expandedTabs[self.tabName]
                        BuildBrowseList(browseSearch:GetText())
                    end)
                    by = by - BROWSE_ROW_H
                end

                if not (not ignoreCollapse and not expandedTabs[currentTab]) then
                    local row = GetOrCreateSpellRow()
                    row:SetHeight(BROWSE_ROW_H)
                    row:SetPoint("TOPLEFT", 0, by)
                    row:SetPoint("RIGHT", browseScrollChild, "RIGHT", 0, 0)
                    row.icon:SetTexture(entry.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
                    local display = entry.baseName and (entry.name .. "  |cFF888888(" .. entry.baseName .. ")|r") or entry.name
                    row.text:SetText(display)
                    row.text:SetTextColor(C.text[1], C.text[2], C.text[3], 1)
                    row.spellName = entry.name
                    by = by - BROWSE_ROW_H
                end
            end
        end

        browseScrollChild:SetHeight(math.max(1, math.abs(by)))
        browseScrollCtl:ScrollTo(0, true)
        C_Timer.After(0, UpdateBrowseThumb)
    end

    BuildBrowseList = BuildBrowseListImpl

    local browseSearchTimer = nil
    browseSearch:SetScript("OnTextChanged", function(self, userInput)
        local txt = self:GetText()
        browseSearchPlaceholder:SetShown(not txt or txt == "")
        if not userInput then return end
        if browseSearchTimer then browseSearchTimer:Cancel() end
        browseSearchTimer = C_Timer.NewTimer(0.15, function()
            browseSearchTimer = nil
            BuildBrowseList(txt)
        end)
    end)

    browsePopup:SetScript("OnHide", function()
        browseSearch:SetText("")
        browseSearchPlaceholder:Show()
    end)

    browsePopupHandle = {
        popup = browsePopup,
        search = browseSearch,
        build = BuildBrowseList,
    }
    return browsePopupHandle
end

local function BuildClickCastBindings(L, content, cc, refreshClickCast, state)
    local GFCC = ns.QUI_GroupFrameClickCast

    local ACTION_TYPE_OPTIONS = {
        { value = "spell",        text = ns.L["Spell"] },
        { value = "item",         text = ns.L["Item"] },
        { value = "macro",        text = ns.L["Macro"] },
        { value = "target",       text = ns.L["Target Unit"] },
        { value = "focus",        text = ns.L["Set Focus"] },
        { value = "assist",       text = ns.L["Assist"] },
        { value = "menu",         text = ns.L["Unit Menu"] },
        { value = "ping",         text = ns.L["Ping (Contextual)"] },
        { value = "ping_assist",  text = ns.L["Ping: Assist"] },
        { value = "ping_attack",  text = ns.L["Ping: Attack"] },
        { value = "ping_warning", text = ns.L["Ping: Warning"] },
        { value = "ping_onmyway", text = ns.L["Ping: On My Way"] },
    }
    local BINDING_TYPE_OPTIONS = {
        { value = "mouse", text = ns.L["Mouse Button"] },
        { value = "key",   text = ns.L["Keyboard Key"] },
    }
    local BUTTON_OPTIONS = {
        { value = "LeftButton",   text = ns.L["Left Click"] },
        { value = "RightButton",  text = ns.L["Right Click"] },
        { value = "MiddleButton", text = ns.L["Middle Click"] },
        { value = "Button4",      text = ns.L["Button 4"] },
        { value = "Button5",      text = ns.L["Button 5"] },
        { value = "ScrollUp",     text = ns.L["Scroll Up"] },
        { value = "ScrollDown",   text = ns.L["Scroll Down"] },
    }
    local MOD_OPTIONS = {
        { value = "",              text = ns.L["None"] },
        { value = "shift",         text = ns.L["Shift"] },
        { value = "ctrl",          text = ns.L["Ctrl"] },
        { value = "alt",           text = ns.L["Alt"] },
        { value = "shift-ctrl",    text = ns.L["Shift+Ctrl"] },
        { value = "shift-alt",     text = ns.L["Shift+Alt"] },
        { value = "ctrl-alt",      text = ns.L["Ctrl+Alt"] },
        { value = "shift-ctrl-alt", text = ns.L["Shift+Ctrl+Alt"] },
    }
    local ACTION_FALLBACK_ICONS = {
        target       = "Interface\\Icons\\Ability_Hunter_SniperShot",
        focus        = "Interface\\Icons\\Ability_TrickShot",
        assist       = "Interface\\Icons\\Ability_Hunter_MasterMarksman",
        macro        = "Interface\\Icons\\INV_Misc_Note_01",
        menu         = "Interface\\Icons\\INV_Misc_GroupNeedMore",
        ping         = "Interface\\Icons\\Ping_Chat_Default",
        ping_assist  = "Interface\\Icons\\Ping_Chat_Assist",
        ping_attack  = "Interface\\Icons\\Ping_Chat_Attack",
        ping_warning = "Interface\\Icons\\Ping_Chat_Warning",
        ping_onmyway = "Interface\\Icons\\Ping_Chat_OnMyWay",
    }
    local PING_DISPLAY_NAMES = {
        ping         = ns.L["Ping"],
        ping_assist  = ns.L["Ping: Assist"],
        ping_attack  = ns.L["Ping: Attack"],
        ping_warning = ns.L["Ping: Warning"],
        ping_onmyway = ns.L["Ping: On My Way"],
    }

    L.headerAt(ns.L["Bindings"])

    local fixedTop = math.abs(L.offset())
    local bindingsBlock = CreateFrame("Frame", nil, content)
    L.placeCustom(bindingsBlock, 100)

    local by = 0
    local RefreshBindingList

    local specLabel = GUI:CreateLabel(bindingsBlock, "", 11, C.accent)
    specLabel:SetPoint("TOPLEFT", 0, by)
    specLabel:SetPoint("RIGHT", bindingsBlock, "RIGHT", 0, 0)
    specLabel:SetJustifyH("LEFT")
    specLabel:Hide()

    local function UpdateSpecLabel()
        if cc.perSpec then
            local specIndex = GetSpecialization()
            if specIndex then
                local _, specName = GetSpecializationInfo(specIndex)
                if specName then
                    local labelText = ns.L["Editing bindings for: "] .. specName
                    if cc.perLoadout and C_ClassTalents then
                        local configID = C_ClassTalents.GetActiveConfigID()
                        if configID then
                            local specID = GetSpecializationInfo(specIndex)
                            local savedID = specID and C_ClassTalents.GetLastSelectedSavedConfigID and C_ClassTalents.GetLastSelectedSavedConfigID(specID)
                            local builds = specID and C_ClassTalents.GetConfigIDsBySpecID(specID)
                            local ordinal
                            local lookupID = savedID or configID
                            if builds then
                                for idx, cid in ipairs(builds) do
                                    if cid == lookupID then
                                        ordinal = idx
                                        break
                                    end
                                end
                            end
                            local configInfo = C_Traits and C_Traits.GetConfigInfo and C_Traits.GetConfigInfo(lookupID)
                            local customName = configInfo and configInfo.name
                            if customName and customName ~= specName then
                                labelText = labelText .. " \226\128\148 " .. customName
                            elseif ordinal then
                                labelText = labelText .. " \226\128\148 " .. ns.L["Loadout"] .. " " .. ordinal
                            end
                        end
                    end
                    specLabel:SetText(labelText)
                    specLabel:Show()
                    return
                end
            end
        end
        specLabel:Hide()
    end
    UpdateSpecLabel()
    if specLabel:IsShown() then by = by - 20 end

    local function GetSpecName(specID)
        if GetSpecializationInfoByID then
            local _, specName = GetSpecializationInfoByID(specID)
            if specName and specName ~= "" then return specName end
        end
        return ns.L["Spec"] .. " " .. tostring(specID)
    end

    local function GetLoadoutName(specID, configID, specName)
        local configInfo = C_Traits and C_Traits.GetConfigInfo and C_Traits.GetConfigInfo(configID)
        local customName = configInfo and configInfo.name
        if customName and customName ~= "" and customName ~= specName then
            return customName
        end

        local configIDs = C_ClassTalents and C_ClassTalents.GetConfigIDsBySpecID
            and C_ClassTalents.GetConfigIDsBySpecID(specID)
        if configIDs then
            for index, savedConfigID in ipairs(configIDs) do
                if savedConfigID == configID then
                    return ns.L["Loadout"] .. " " .. index
                end
            end
        end

        return ns.L["Loadout"] .. " " .. tostring(configID)
    end

    local function GetBindingSetLabel(source)
        if source.scope == "shared" then
            return ns.L["Shared"]
        end

        local specName = GetSpecName(source.specID)
        if source.scope == "spec" then
            return specName .. " (" .. ns.L["Spec"] .. ")"
        end

        return specName .. ": " .. GetLoadoutName(source.specID, source.configID, specName)
    end

    Shared.CreateAccentDotLabel(bindingsBlock, ns.L["Copy Settings"], by); by = by - 30

    local copySelector = { selected = nil }
    local copyCard = Shared.CreateSettingsCardGroup(bindingsBlock, by)
    local copyControls = CreateFrame("Frame", nil, copyCard.frame)
    copyControls:SetHeight(FORM_ROW)

    local copyDropdown = GUI:CreateFormDropdown(copyControls, ns.L["Copy From"], {}, "selected", copySelector)
    copyDropdown:ClearAllPoints()
    copyDropdown:SetPoint("LEFT", copyControls, "LEFT", 0, 0)
    copyDropdown:SetWidth(COPY_LABEL_WIDTH + COPY_CONTROL_GAP + COPY_DROPDOWN_WIDTH)
    if copyDropdown.dropdown then
        copyDropdown.dropdown:ClearAllPoints()
        copyDropdown.dropdown:SetPoint("LEFT", copyDropdown, "LEFT", COPY_LABEL_WIDTH + COPY_CONTROL_GAP, 0)
        copyDropdown.dropdown:SetPoint("RIGHT", copyDropdown, "RIGHT", 0, 0)
    end

    local applyCopyBtn = GUI:CreateButton(copyControls, ns.L["Apply Copy"], 100, 24, function()
        if not copySelector.selected or copySelector.selected == "" then return end
        local ok = GFCC:CopyBindingsFrom(copySelector.selected)
        if ok and RefreshBindingList then RefreshBindingList() end
    end)
    applyCopyBtn:SetPoint("LEFT", copyDropdown, "RIGHT", COPY_CONTROL_GAP, 0)

    copyCard.AddRow(copyControls)
    copyCard.Finalize()
    by = by - copyCard.frame:GetHeight() - BINDINGS_SECTION_GAP

    local function UpdateCopyControls()
        local activeID = GFCC:GetEditableBindingSetID()
        local options = {}
        for _, source in ipairs(GFCC:GetBindingSetSources()) do
            if source.id ~= activeID then
                options[#options + 1] = {
                    value = source.id,
                    text = GetBindingSetLabel(source),
                }
            end
        end

        local hasSources = #options > 0
        if not hasSources then
            options[1] = { value = "", text = ns.L["None"] }
        end

        local selectionFound = false
        for _, option in ipairs(options) do
            if option.value == copySelector.selected then
                selectionFound = true
                break
            end
        end
        if not selectionFound then
            copySelector.selected = options[1].value
        end

        copyDropdown:SetOptions(options)
        copyDropdown:SetValue(copySelector.selected, true)
        copyDropdown:SetEnabled(hasSources)
        applyCopyBtn:SetEnabled(hasSources)
        applyCopyBtn:SetAlpha(hasSources and 1 or 0.4)
    end

    Shared.CreateAccentDotLabel(bindingsBlock, ns.L["Current Bindings"], by); by = by - 30

    local bindingListFrame = CreateFrame("Frame", nil, bindingsBlock)
    bindingListFrame:SetPoint("TOPLEFT", 0, by)
    bindingListFrame:SetSize(400, 20)
    local listTopOffset = math.abs(by)

    local addContainer = CreateFrame("Frame", nil, bindingsBlock)
    addContainer:SetPoint("TOPLEFT", bindingListFrame, "BOTTOMLEFT", 0, -10)
    addContainer:SetPoint("RIGHT", bindingsBlock, "RIGHT", 0, 0)
    addContainer:SetHeight(400)
    addContainer:EnableMouse(false)

    Shared.CreateAccentDotLabel(addContainer, ns.L["Add Binding"], 0)
    local ay = -30

    local dropPrompt = ns.L["Drop Spell or Item Here"] .. " / " .. ns.L["Macro"]
    local dropZone = CreateClickCastButton(addContainer, dropPrompt, 1, 68, nil, "primary")
    dropZone:RegisterForClicks("LeftButtonUp")
    SetHeightPx(dropZone, 68)
    dropZone:SetPoint("TOPLEFT", 0, ay)
    dropZone:SetPoint("RIGHT", addContainer, "RIGHT", 0, 0)
    SetButtonFill(dropZone, C.bg[1], C.bg[2], C.bg[3], 0.8)
    SetButtonBorder(dropZone, C.accent[1], C.accent[2], C.accent[3], 0.5)

    local dropLabel = dropZone.text
    if dropLabel then
        CJKFont(dropLabel, GUI.FONT_PATH, 11, "")
        dropLabel:SetTextColor(C.textMuted[1], C.textMuted[2], C.textMuted[3], 1)
    end

    local addState = { bindingType = "mouse", button = "LeftButton", key = nil, modifiers = "", actionType = "spell", spellName = "", itemName = nil, itemID = nil, macroText = "", targetFilter = "any" }
    local spellInput, macroInput, actionDrop
    local spellInputContainer, macroInputContainer
    local mouseButtonContainer, keyCaptureContainer
    local triggerCell
    local targetFilterRow

    local function HandleCursorDrop()
        local cursorType, id1, id2, _, id4 = GetCursorInfo()
        if not cursorType then return false end

        if cursorType == "spell" then
            local slotIndex, bookType, spellID = id1, id2 or "spell", id4
            if not spellID and slotIndex then
                local spellBank = (bookType == "pet") and Enum.SpellBookSpellBank.Pet or Enum.SpellBookSpellBank.Player
                local info = C_SpellBook.GetSpellBookItemInfo(slotIndex, spellBank)
                if info then spellID = info.spellID end
            end
            if spellID then
                local overrideID = C_Spell.GetOverrideSpell(spellID)
                if overrideID and overrideID ~= spellID then spellID = overrideID end
                local name = C_Spell.GetSpellName(spellID)
                if name then
                    addState.itemName = nil
                    addState.itemID = nil
                    addState.spellName = name
                    addState.actionType = "spell"
                    if spellInput then spellInput:SetText(name) end
                    if actionDrop then actionDrop.SetValue("spell", true) end
                    if spellInputContainer then spellInputContainer:Show() end
                    if macroInputContainer then macroInputContainer:Hide() end
                    if dropLabel then dropLabel:SetText(dropPrompt) end
                end
            end
            ClearCursor()
            return true
        elseif cursorType == "macro" then
            local macroIndex = id1
            if macroIndex then
                local name, _, body = GetMacroInfo(macroIndex)
                if body then
                    addState.itemName = nil
                    addState.itemID = nil
                    addState.actionType = "macro"
                    addState.macroText = body
                    addState.spellName = name or ns.L["Macro"]
                    if macroInput then macroInput:SetText(body) end
                    if actionDrop then actionDrop.SetValue("macro", true) end
                    if macroInputContainer then macroInputContainer:Show() end
                    if spellInputContainer then spellInputContainer:Hide() end
                    if dropLabel then dropLabel:SetText(dropPrompt) end
                end
            end
            ClearCursor()
            return true
        elseif cursorType == "item" then
            local itemID = id1
            if itemID then
                local itemName = C_Item.GetItemInfo(itemID)
                addState.actionType = "item"
                addState.itemID = itemID
                addState.itemName = itemName
                if actionDrop then actionDrop.SetValue("item", true) end
                if spellInputContainer then spellInputContainer:Hide() end
                if macroInputContainer then macroInputContainer:Hide() end
                if targetFilterRow then targetFilterRow:Hide() end
                if dropLabel then dropLabel:SetText(itemName or ns.L["Item"]) end
            end
            ClearCursor()
            return true
        end
        return false
    end

    dropZone:SetScript("OnReceiveDrag", HandleCursorDrop)
    dropZone:SetScript("OnClick", function()
        if spellInput then spellInput:ClearFocus() end
        if macroInput then macroInput:ClearFocus() end
        if GetCursorInfo() then HandleCursorDrop() end
    end)
    dropZone:SetScript("OnEnter", function(self)
        if GetCursorInfo() then
            SetButtonBorder(self, C.accent[1], C.accent[2], C.accent[3], 1)
            SetButtonHover(self, true, C.accent[1], C.accent[2], C.accent[3], 0.08)
            if dropLabel then dropLabel:SetTextColor(C.accent[1], C.accent[2], C.accent[3], 1) end
        end
    end)
    dropZone:SetScript("OnLeave", function(self)
        SetButtonBorder(self, C.accent[1], C.accent[2], C.accent[3], 0.5)
        SetButtonHover(self, false)
        if dropLabel then dropLabel:SetTextColor(C.textMuted[1], C.textMuted[2], C.textMuted[3], 1) end
    end)
    ay = ay - 78

    local formCard = Shared.CreateSettingsCardGroup(addContainer, ay)

    local bindingTypeDrop = GUI:CreateFormDropdown(formCard.frame, nil, BINDING_TYPE_OPTIONS, "bindingType", addState, function(val)
        addState.bindingType = val
        if mouseButtonContainer then mouseButtonContainer:SetShown(val == "mouse") end
        if keyCaptureContainer then keyCaptureContainer:SetShown(val == "key") end
        if triggerCell and triggerCell._label then
            triggerCell._label:SetText(val == "key" and ns.L["Key"] or ns.L["Mouse Button"])
        end
    end, { description = ns.L["Whether this binding fires on a mouse button (including scroll) or on a keyboard key pressed while hovering a unit frame."] })

    local buttonDrop = GUI:CreateFormDropdown(formCard.frame, nil, BUTTON_OPTIONS, "button", addState, nil,
        { description = ns.L["Mouse button or scroll direction this binding fires on when hovering a unit frame. Combine with a modifier below to layer multiple actions onto the same button."] })
    mouseButtonContainer = buttonDrop

    keyCaptureContainer = CreateFrame("Frame", nil, formCard.frame)
    keyCaptureContainer:Hide()

    local keyCaptureBtn = CreateClickCastButton(keyCaptureContainer, ns.L["Click to bind a key"], 1, 26)
    keyCaptureBtn:SetPoint("LEFT", keyCaptureContainer, "LEFT", 0, 0)
    keyCaptureBtn:SetPoint("RIGHT", keyCaptureContainer, "RIGHT", 0, 0)
    SetHeightPx(keyCaptureBtn, 26)
    SetButtonFill(keyCaptureBtn, 0.08, 0.08, 0.08, 1)
    SetButtonBorder(keyCaptureBtn, 0.35, 0.35, 0.35, 1)

    local keyCaptureText = keyCaptureBtn.text
    if keyCaptureText then
        CJKFont(keyCaptureText, GUI.FONT_PATH, 11, "")
        keyCaptureText:SetTextColor(C.textMuted[1], C.textMuted[2], C.textMuted[3], 1)
    end

    local IGNORE_KEYS = { LSHIFT = true, RSHIFT = true, LCTRL = true, RCTRL = true, LALT = true, RALT = true, LMETA = true, RMETA = true }

    keyCaptureBtn:SetScript("OnClick", function(self)
        self.isCapturing = true
        keyCaptureBtn:SetText(ns.L["Press a key..."])
        if keyCaptureText then keyCaptureText:SetTextColor(C.accent[1], C.accent[2], C.accent[3], 1) end
        SetButtonBorder(self, C.accent[1], C.accent[2], C.accent[3], 1)
        self:EnableKeyboard(true)
    end)
    keyCaptureBtn:SetScript("OnKeyDown", function(self, key)
        if not self.isCapturing then self:SetPropagateKeyboardInput(true) return end
        self:SetPropagateKeyboardInput(false)
        if IGNORE_KEYS[key] then self:SetPropagateKeyboardInput(true) return end
        if key == "ESCAPE" then
            self.isCapturing = false
            self:EnableKeyboard(false)
            SetButtonBorder(self, 0.35, 0.35, 0.35, 1)
            SetButtonHover(self, false)
            if addState.key then
                keyCaptureBtn:SetText(addState.key)
                if keyCaptureText then keyCaptureText:SetTextColor(C.text[1], C.text[2], C.text[3], 1) end
            else
                keyCaptureBtn:SetText(ns.L["Click to bind a key"])
                if keyCaptureText then keyCaptureText:SetTextColor(C.textMuted[1], C.textMuted[2], C.textMuted[3], 1) end
            end
            return
        end
        addState.key = key
        self.isCapturing = false
        self:EnableKeyboard(false)
        SetButtonBorder(self, 0.35, 0.35, 0.35, 1)
        SetButtonHover(self, false)
        keyCaptureBtn:SetText(key)
        if keyCaptureText then keyCaptureText:SetTextColor(C.text[1], C.text[2], C.text[3], 1) end
    end)
    keyCaptureBtn:SetScript("OnEnter", function(self)
        if not self.isCapturing then
            SetButtonBorder(self, C.accent[1], C.accent[2], C.accent[3], 0.7)
            SetButtonHover(self, true, C.accent[1], C.accent[2], C.accent[3], 0.08)
        end
    end)
    keyCaptureBtn:SetScript("OnLeave", function(self)
        if not self.isCapturing then
            SetButtonBorder(self, 0.35, 0.35, 0.35, 1)
            SetButtonHover(self, false)
        end
    end)

    local modDrop = GUI:CreateFormDropdown(formCard.frame, nil, MOD_OPTIONS, "modifiers", addState, nil,
        { description = ns.L["Modifier key(s) that must be held for this binding to fire. Use None for the unmodified click or key — different modifiers let you stack multiple actions on the same button."] })

    actionDrop = GUI:CreateFormDropdown(formCard.frame, nil, ACTION_TYPE_OPTIONS, "actionType", addState, function(val)
        addState.actionType = val
        if spellInputContainer then spellInputContainer:SetShown(val == "spell") end
        if macroInputContainer then macroInputContainer:SetShown(val == "macro") end
        if targetFilterRow then targetFilterRow:SetShown(val == "spell" or val == "macro") end
    end, { description = ns.L["What this binding does: cast a spell or macro, change target/focus/assist, open the unit menu, or send a ping. Spell and Macro reveal an input below for the spell name or macro body."] })

    triggerCell = row(formCard.frame, ns.L["Mouse Button"], buttonDrop)
    keyCaptureContainer:SetParent(triggerCell)
    keyCaptureContainer:SetAllPoints(buttonDrop)
    formCard.AddRow(row(formCard.frame, ns.L["Binding Type"], bindingTypeDrop), triggerCell)
    formCard.AddRow(row(formCard.frame, ns.L["Modifier"], modDrop), row(formCard.frame, ns.L["Action Type"], actionDrop))

    local TARGET_FILTER_OPTIONS = {
        { value = "any",    text = ns.L["Any"] },
        { value = "friend", text = ns.L["Friendly only"] },
        { value = "enemy",  text = ns.L["Enemy only"] },
    }
    local targetFilterDrop = GUI:CreateFormDropdown(formCard.frame, nil, TARGET_FILTER_OPTIONS, "targetFilter", addState, function(val)
        addState.targetFilter = val
    end, { description = ns.L["Target Filter"] })
    targetFilterRow = row(formCard.frame, ns.L["Target Filter"], targetFilterDrop)
    targetFilterRow:SetShown(addState.actionType == "spell" or addState.actionType == "macro")
    formCard.AddRow(targetFilterRow)

    formCard.Finalize()
    ay = ay - formCard.frame:GetHeight() - 8

    spellInputContainer = CreateFrame("Frame", nil, addContainer)
    spellInputContainer:SetHeight(FORM_ROW)
    spellInputContainer:SetPoint("TOPLEFT", 0, ay)
    spellInputContainer:SetPoint("RIGHT", addContainer, "RIGHT", 0, 0)

    local spellLabel = spellInputContainer:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    spellLabel:SetPoint("LEFT", 0, 0)
    spellLabel:SetText(ns.L["Spell Name"])
    spellLabel:SetTextColor(C.text[1], C.text[2], C.text[3], 1)

    local browseBtn = CreateClickCastButton(spellInputContainer, ns.L["Browse"], 64, 24, nil, "primary")
    SetSizePx(browseBtn, 64, 24)
    browseBtn:SetPoint("RIGHT", spellInputContainer, "RIGHT", 0, 0)
    SetButtonFill(browseBtn, 0.12, 0.12, 0.12, 1)
    SetButtonBorder(browseBtn, 0.35, 0.35, 0.35, 1)
    if browseBtn.text then
        browseBtn.text:SetTextColor(C.accent[1], C.accent[2], C.accent[3], 1)
    end
    browseBtn:SetScript("OnEnter", function(self)
        SetButtonBorder(self, C.accent[1], C.accent[2], C.accent[3], 1)
        SetButtonHover(self, true, C.accent[1], C.accent[2], C.accent[3], 0.08)
    end)
    browseBtn:SetScript("OnLeave", function(self)
        SetButtonBorder(self, 0.35, 0.35, 0.35, 1)
        SetButtonHover(self, false)
    end)

    local spellInputBg = CreateFrame("Frame", nil, spellInputContainer, "BackdropTemplate")
    spellInputBg:SetPoint("LEFT", spellInputContainer, "LEFT", 180, 0)
    spellInputBg:SetPoint("RIGHT", browseBtn, "LEFT", -6, 0)
    SetHeightPx(spellInputBg, 24)
    ApplyPixelBackdrop(spellInputBg, 1, true)
    spellInputBg:SetBackdropColor(0.08, 0.08, 0.08, 1)
    spellInputBg:SetBackdropBorderColor(0.35, 0.35, 0.35, 1)

    spellInput = CreateFrame("EditBox", nil, spellInputBg)
    spellInput:SetPoint("LEFT", 8, 0)
    spellInput:SetPoint("RIGHT", -8, 0)
    spellInput:SetHeight(22)
    spellInput:SetAutoFocus(false)
    CJKFont(spellInput, GUI.FONT_PATH, 11, "")
    spellInput:SetTextColor(C.text[1], C.text[2], C.text[3], 1)
    spellInput:SetText("")

    local MAX_AC_ROWS = 8
    local AC_ROW_HEIGHT = 22

    local acMenu = CreateFrame("Frame", nil, spellInputBg, "BackdropTemplate")
    acMenu:SetPoint("TOPLEFT", spellInputBg, "BOTTOMLEFT", 0, -2)
    acMenu:SetPoint("RIGHT", spellInputBg, "RIGHT", 0, 0)
    acMenu:SetHeight(AC_ROW_HEIGHT * MAX_AC_ROWS + 4)
    acMenu:SetFrameStrata("TOOLTIP")
    acMenu:SetFrameLevel(1000)
    acMenu:SetToplevel(true)
    acMenu:EnableMouse(true)
    ApplyPixelBackdrop(acMenu, 1, true)
    acMenu:SetBackdropColor(0.08, 0.08, 0.08, 0.95)
    acMenu:SetBackdropBorderColor(C.accent[1], C.accent[2], C.accent[3], 0.6)
    acMenu:Hide()

    local function CommitAutocompleteSelection(row)
        if row and row.spellName then
            spellInput:SetText(row.spellName)
            addState.spellName = row.spellName
            acMenu:Hide()
            spellInput:ClearFocus()
        end
    end

    local acRows = {}
    for ri = 1, MAX_AC_ROWS do
        local row = CreateFrame("Button", nil, acMenu)
        row:SetHeight(AC_ROW_HEIGHT)
        row:SetPoint("TOPLEFT", acMenu, "TOPLEFT", 2, -2 - (ri - 1) * AC_ROW_HEIGHT)
        row:SetPoint("RIGHT", acMenu, "RIGHT", -2, 0)

        local rowIcon = row:CreateTexture(nil, "ARTWORK")
        rowIcon:SetSize(18, 18)
        rowIcon:SetPoint("LEFT", 2, 0)
        rowIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        row.icon = rowIcon

        local rowText = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        rowText:SetPoint("LEFT", rowIcon, "RIGHT", 4, 0)
        rowText:SetPoint("RIGHT", row, "RIGHT", -4, 0)
        rowText:SetJustifyH("LEFT")
        CJKFont(rowText, GUI.FONT_PATH, 11, "")
        rowText:SetTextColor(C.text[1], C.text[2], C.text[3], 1)
        row.text = rowText

        local rowHl = row:CreateTexture(nil, "HIGHLIGHT")
        rowHl:SetAllPoints()
        rowHl:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 0.15)

        row:SetScript("OnMouseDown", CommitAutocompleteSelection)

        row:Hide()
        acRows[ri] = row
    end

    local acDebounceTimer = nil
    local function ShowAutocomplete(searchText)
        if not searchText or #searchText < 2 then acMenu:Hide() return end
        local spells = EnsureSpellCache()
        local lower = FoldSearchUTF8(searchText)
        local matches = {}
        for _, entry in ipairs(spells) do
            if FoldSearchUTF8(entry.name):find(lower, 1, true) or (entry.baseName and FoldSearchUTF8(entry.baseName):find(lower, 1, true)) then
                matches[#matches + 1] = entry
                if #matches >= MAX_AC_ROWS then break end
            end
        end
        if #matches == 0 then acMenu:Hide() return end
        for ri = 1, MAX_AC_ROWS do
            local row = acRows[ri]
            local m = matches[ri]
            if m then
                row.icon:SetTexture(m.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
                local display = m.baseName and (m.name .. "  |cFF888888(" .. m.baseName .. ")|r") or m.name
                row.text:SetText(display)
                row.spellName = m.name
                row:Show()
            else
                row:Hide()
            end
        end
        acMenu:SetHeight(#matches * AC_ROW_HEIGHT + 4)
        acMenu:Show()
        acMenu:Raise()
    end

    spellInput:SetScript("OnEscapePressed", function(self) acMenu:Hide() self:ClearFocus() end)
    spellInput:SetScript("OnEnterPressed", function(self) acMenu:Hide() self:ClearFocus() end)
    spellInput:SetScript("OnTextChanged", function(self, userInput)
        addState.spellName = self:GetText()
        if not userInput then return end
        if acDebounceTimer then acDebounceTimer:Cancel() end
        acDebounceTimer = C_Timer.NewTimer(0.15, function()
            acDebounceTimer = nil
            ShowAutocomplete(self:GetText())
        end)
    end)
    spellInput:SetScript("OnEditFocusGained", function() spellInputBg:SetBackdropBorderColor(C.accent[1], C.accent[2], C.accent[3], 1) end)
    spellInput:SetScript("OnEditFocusLost", function()
        spellInputBg:SetBackdropBorderColor(0.35, 0.35, 0.35, 1)
        C_Timer.After(0.1, function() acMenu:Hide() end)
    end)

    local browse = EnsureBrowsePopup()
    local browsePopup = browse.popup
    browse.onPick = function(spellName)
        spellInput:SetText(spellName)
        addState.spellName = spellName
    end

    browseBtn:SetScript("OnClick", function()
        if browsePopup:IsShown() then
            browsePopup:Hide()
            return
        end
        RebuildSpellCache()
        browse.search:SetText("")
        browse.build(nil)
        browsePopup:Show()
        browsePopup:Raise()
    end)

    ay = ay - FORM_ROW

    macroInputContainer = CreateFrame("Frame", nil, addContainer)
    macroInputContainer:SetHeight(FORM_ROW)
    macroInputContainer:SetPoint("TOPLEFT", 0, ay)
    macroInputContainer:SetPoint("RIGHT", addContainer, "RIGHT", 0, 0)
    macroInputContainer:Hide()

    local macroLabel = macroInputContainer:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    macroLabel:SetPoint("LEFT", 0, 0)
    macroLabel:SetText(ns.L["Macro Text"])
    macroLabel:SetTextColor(C.text[1], C.text[2], C.text[3], 1)

    local macroInputBg = CreateFrame("Frame", nil, macroInputContainer, "BackdropTemplate")
    macroInputBg:SetPoint("LEFT", macroInputContainer, "LEFT", 180, 0)
    macroInputBg:SetPoint("RIGHT", macroInputContainer, "RIGHT", 0, 0)
    SetHeightPx(macroInputBg, 24)
    ApplyPixelBackdrop(macroInputBg, 1, true)
    macroInputBg:SetBackdropColor(0.08, 0.08, 0.08, 1)
    macroInputBg:SetBackdropBorderColor(0.35, 0.35, 0.35, 1)

    macroInput = CreateFrame("EditBox", nil, macroInputBg)
    macroInput:SetPoint("LEFT", 8, 0)
    macroInput:SetPoint("RIGHT", -8, 0)
    macroInput:SetHeight(22)
    macroInput:SetAutoFocus(false)
    CJKFont(macroInput, GUI.FONT_PATH, 11, "")
    macroInput:SetTextColor(C.text[1], C.text[2], C.text[3], 1)
    macroInput:SetText("")
    macroInput:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    macroInput:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    macroInput:SetScript("OnTextChanged", function(self) addState.macroText = self:GetText() end)
    macroInput:SetScript("OnEditFocusGained", function() macroInputBg:SetBackdropBorderColor(C.accent[1], C.accent[2], C.accent[3], 1) end)
    macroInput:SetScript("OnEditFocusLost", function() macroInputBg:SetBackdropBorderColor(0.35, 0.35, 0.35, 1) end)

    local function RefreshClickCastPixelFrames()
        SetHeightPx(dropZone, 68)
        if GetCursorInfo() then
            SetButtonBorder(dropZone, C.accent[1], C.accent[2], C.accent[3], 1)
            SetButtonHover(dropZone, true, C.accent[1], C.accent[2], C.accent[3], 0.08)
        else
            SetButtonBorder(dropZone, C.accent[1], C.accent[2], C.accent[3], 0.5)
            SetButtonHover(dropZone, false)
        end

        SetHeightPx(keyCaptureBtn, 26)
        if keyCaptureBtn.isCapturing then
            SetButtonBorder(keyCaptureBtn, C.accent[1], C.accent[2], C.accent[3], 1)
        else
            SetButtonBorder(keyCaptureBtn, 0.35, 0.35, 0.35, 1)
        end

        SetHeightPx(spellInputBg, 24)
        ApplyPixelBackdrop(spellInputBg, 1, true)
        spellInputBg:SetBackdropColor(0.08, 0.08, 0.08, 1)
        if spellInput and spellInput:HasFocus() then
            spellInputBg:SetBackdropBorderColor(C.accent[1], C.accent[2], C.accent[3], 1)
        else
            spellInputBg:SetBackdropBorderColor(0.35, 0.35, 0.35, 1)
        end

        SetHeightPx(macroInputBg, 24)
        ApplyPixelBackdrop(macroInputBg, 1, true)
        macroInputBg:SetBackdropColor(0.08, 0.08, 0.08, 1)
        if macroInput and macroInput:HasFocus() then
            macroInputBg:SetBackdropBorderColor(C.accent[1], C.accent[2], C.accent[3], 1)
        else
            macroInputBg:SetBackdropBorderColor(0.35, 0.35, 0.35, 1)
        end
    end

    local addBtnY = ay - FORM_ROW
    local addBtn = GUI:CreateButton(addContainer, ns.L["Add Binding"], 130, 26, function()
        local actionType = addState.actionType
        if type(actionType) ~= "string" then print("|cFFFF5555[QUI]|r " .. ns.L["Invalid action type. Please re-select."]) return end
        local newBinding = { modifiers = addState.modifiers, actionType = actionType }
        if addState.bindingType == "key" then
            if not addState.key or addState.key == "" then print("|cFFFF5555[QUI]|r " .. ns.L["Press a key to bind first."]) return end
            newBinding.key = addState.key
        else
            newBinding.button = addState.button
        end
        if actionType == "spell" then
            local name = addState.spellName
            if not name or name == "" then print("|cFFFF5555[QUI]|r " .. ns.L["Enter a spell name."]) return end
            local spellID = C_Spell.GetSpellIDForSpellIdentifier(name)
            if not spellID then print("|cFFFF5555[QUI]|r " .. ns.L["Spell not found: "] .. name) return end
            local baseID = C_Spell.GetBaseSpell and C_Spell.GetBaseSpell(spellID) or spellID
            newBinding.spellID = baseID
            local rootName = C_Spell.GetSpellName(baseID)
            newBinding.spell = rootName or C_Spell.GetSpellName(spellID) or name
        elseif actionType == "item" then
            if not addState.itemID then print("|cFFFF5555[QUI]|r " .. ns.L["Item"] .. ns.L[" unavailable."]) return end
            newBinding.itemID = addState.itemID
            newBinding.item = addState.itemName or C_Item.GetItemInfo(addState.itemID) or ns.L["Item"]
        elseif actionType == "macro" then
            local text = addState.macroText
            if not text or text == "" then print("|cFFFF5555[QUI]|r " .. ns.L["Enter macro text."]) return end
            newBinding.spell = "Macro"
            newBinding.macro = text
        else
            newBinding.spell = actionType
        end
        if actionType == "spell" or actionType == "macro" then
            if addState.targetFilter == "friend" then
                newBinding.friend = true
            elseif addState.targetFilter == "enemy" then
                newBinding.enemy = true
            end
        end
        local ok, err = GFCC:AddBinding(newBinding)
        if not ok then print("|cFFFF5555[QUI]|r " .. (err or ns.L["Failed to add binding."])) return end
        addState.spellName = ""
        addState.itemName = nil
        addState.itemID = nil
        addState.macroText = ""
        addState.key = nil
        addState.targetFilter = "any"
        if targetFilterDrop and targetFilterDrop.SetValue then targetFilterDrop.SetValue("any", true) end
        spellInput:SetText("")
        macroInput:SetText("")
        if dropLabel then dropLabel:SetText(dropPrompt) end
        keyCaptureBtn:SetText(ns.L["Click to bind a key"])
        if keyCaptureText then keyCaptureText:SetTextColor(C.textMuted[1], C.textMuted[2], C.textMuted[3], 1) end
        RefreshBindingList()
    end)
    addBtn:SetPoint("TOPLEFT", 0, addBtnY)
    addContainer:SetHeight(math.abs(addBtnY) + 36)

    local bindingRows = {}
    local bindingEmptyLabel

    local function AcquireBindingRow(index)
        local row = bindingRows[index]
        if row then
            row:Show()
            return row
        end
        row = CreateFrame("Frame", nil, bindingListFrame)
        row:SetSize(400, 28)
        row:SetPoint("TOPLEFT", 0, -30 * (index - 1))
        local iconTex = row:CreateTexture(nil, "ARTWORK")
        iconTex:SetSize(24, 24)
        iconTex:SetPoint("LEFT", 0, 0)
        iconTex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        row.iconTex = iconTex
        local comboText = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        comboText:SetPoint("LEFT", iconTex, "RIGHT", 6, 0)
        comboText:SetWidth(140)
        comboText:SetJustifyH("LEFT")
        row.comboText = comboText
        local spellText = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        spellText:SetPoint("LEFT", comboText, "RIGHT", 8, 0)
        spellText:SetWidth(140)
        spellText:SetJustifyH("LEFT")
        row.spellText = spellText
        local removeBtn = CreateClickCastButton(row, "X", 22, 22, function()
            GFCC:RemoveBinding(row.bindingIndex)
            RefreshBindingList()
        end)
        if removeBtn.text then
            removeBtn.text:SetTextColor(C.accent[1], C.accent[2], C.accent[3], 0.7)
        end
        removeBtn:SetScript("OnEnter", function(self)
            SetButtonBorder(self, C.accent[1], C.accent[2], C.accent[3], 1)
            SetButtonHover(self, true, C.accent[1], C.accent[2], C.accent[3], 0.08)
            if self.text then self.text:SetTextColor(C.accent[1], C.accent[2], C.accent[3], 1) end
        end)
        removeBtn:SetScript("OnLeave", function(self)
            SetButtonBorder(self, 0.3, 0.3, 0.3, 1)
            SetButtonHover(self, false)
            if self.text then self.text:SetTextColor(C.accent[1], C.accent[2], C.accent[3], 0.7) end
        end)
        removeBtn:SetPoint("LEFT", spellText, "RIGHT", 8, 0)
        row.removeBtn = removeBtn
        bindingRows[index] = row
        return row
    end

    RefreshBindingList = function()
        UpdateSpecLabel()
        UpdateCopyControls()
        local buttonNames = GFCC:GetButtonNames()
        local modLabels  = GFCC:GetModifierLabels()
        local bindings   = GFCC:GetEditableBindings()
        local listY = 0
        if #bindings == 0 then
            if not bindingEmptyLabel then
                bindingEmptyLabel = CreateFrame("Frame", nil, bindingListFrame)
                bindingEmptyLabel:SetSize(300, 28)
                bindingEmptyLabel:SetPoint("TOPLEFT", 0, 0)
                local emptyText = bindingEmptyLabel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
                emptyText:SetPoint("LEFT", 0, 0)
                emptyText:SetText(ns.L["No bindings configured yet."])
                emptyText:SetTextColor(C.textMuted[1], C.textMuted[2], C.textMuted[3], 1)
            end
            bindingEmptyLabel:Show()
            listY = -28
        else
            if bindingEmptyLabel then bindingEmptyLabel:Hide() end
            for i, binding in ipairs(bindings) do
                local actionType = binding.actionType
                if type(actionType) ~= "string" then actionType = "spell" end
                local spellName = binding.spell
                if type(spellName) ~= "string" then spellName = nil end
                local itemName = binding.item
                if type(itemName) ~= "string" then itemName = nil end
                local resolvedSpellID = binding.spellID
                if resolvedSpellID and actionType == "spell" then
                    local currentName = C_Spell.GetSpellName(resolvedSpellID)
                    if currentName then spellName = currentName end
                end
                local row = AcquireBindingRow(i)
                row.bindingIndex = i
                local iconTex = row.iconTex
                if actionType == "item" then
                    local itemInfo = binding.itemID or itemName
                    local itemTexture
                    if itemInfo then
                        local itemData = { C_Item.GetItemInfo(itemInfo) }
                        local currentName = itemData[1]
                        itemTexture = itemData[10]
                        if currentName then itemName = currentName end
                    end
                    iconTex:SetTexture(itemTexture or "Interface\\Icons\\INV_Misc_QuestionMark")
                elseif actionType == "spell" and spellName then
                    local lookupID = resolvedSpellID or C_Spell.GetSpellIDForSpellIdentifier(spellName)
                    if lookupID then
                        local info = C_Spell.GetSpellInfo(lookupID)
                        iconTex:SetTexture(info and info.iconID or "Interface\\Icons\\INV_Misc_QuestionMark")
                    else
                        iconTex:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
                    end
                else
                    iconTex:SetTexture(ACTION_FALLBACK_ICONS[actionType] or "Interface\\Icons\\INV_Misc_QuestionMark")
                end
                local modLabel = modLabels[binding.modifiers or ""] or ""
                local triggerLabel = binding.key or (buttonNames[binding.button] or binding.button)
                row.comboText:SetText(modLabel .. triggerLabel)
                row.comboText:SetTextColor(C.text[1], C.text[2], C.text[3], 1)
                local displayName = itemName or spellName or actionType
                if actionType == "macro" then displayName = ns.L["Macro"]
                elseif actionType == "menu" then displayName = ns.L["Unit Menu"]
                elseif PING_DISPLAY_NAMES[actionType] then displayName = PING_DISPLAY_NAMES[actionType] end
                if binding.friend then
                    displayName = displayName .. " " .. ns.L["(friendly)"]
                elseif binding.enemy then
                    displayName = displayName .. " " .. ns.L["(enemy)"]
                end
                row.spellText:SetText(displayName)
                row.spellText:SetTextColor(C.textMuted[1], C.textMuted[2], C.textMuted[3], 1)
                if row.removeBtn.text then
                    row.removeBtn.text:SetTextColor(C.accent[1], C.accent[2], C.accent[3], 0.7)
                end
                SetButtonFill(row.removeBtn, 0.1, 0.1, 0.1, 0.8)
                SetButtonBorder(row.removeBtn, 0.3, 0.3, 0.3, 1)
                SetButtonHover(row.removeBtn, false)
                listY = listY - 30
            end
        end
        for i = #bindings + 1, #bindingRows do
            bindingRows[i]:Hide()
        end
        local listHeight = math.max(20, math.abs(listY))
        bindingListFrame:SetHeight(listHeight)
        local blockHeight = listTopOffset + listHeight + 10 + addContainer:GetHeight()
        bindingsBlock:SetHeight(blockHeight)
        local totalHeight = fixedTop + blockHeight + 30
        content:SetHeight(totalHeight)

        local section = content._logicalSection
        if section and section._expanded and section._bodyClip then
            section._contentHeight = totalHeight
            section._bodyClip:SetHeight(totalHeight)
            local sectionH = 24 + totalHeight
            local prevH = section:GetHeight() or 0
            section:SetHeight(sectionH)
            local scrollContent = section:GetParent()
            if scrollContent and scrollContent.SetHeight and prevH > 0 then
                local outerH = scrollContent:GetHeight() or 0
                scrollContent:SetHeight(outerH + (sectionH - prevH))
            end
        end
    end

    RefreshBindingList()
    RefreshClickCastPixelFrames()
    if UIKit and UIKit.RegisterScaleRefresh then
        UIKit.RegisterScaleRefresh(content, "clickCastPixelFrames", RefreshClickCastPixelFrames)
    end

    local specListener = content._quiSpecChangeListener
    if not specListener then
        specListener = CreateFrame("Frame", nil, content)
        specListener:SetScript("OnEvent", function(self)
            local refreshFn = self._quiRefreshBindingList
            if content:IsShown() and refreshFn then
                C_Timer.After(0.5, function()
                    if content:IsShown() and self._quiRefreshBindingList == refreshFn then
                        refreshFn()
                    end
                end)
            end
        end)
        content._quiSpecChangeListener = specListener
    end
    specListener._quiRefreshBindingList = RefreshBindingList

    local function RegisterSpecListener()
        if specListener._quiRegistered then return end
        specListener:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
        specListener:RegisterEvent("TRAIT_CONFIG_UPDATED")
        specListener:RegisterEvent("ACTIVE_COMBAT_CONFIG_CHANGED")
        specListener._quiRegistered = true
    end

    local function UnregisterSpecListener()
        if not specListener._quiRegistered then return end
        specListener:UnregisterAllEvents()
        specListener._quiRegistered = false
    end

    if not content._quiSpecChangeListenerHooks then
        content._quiSpecChangeListenerHooks = true
        content:HookScript("OnShow", RegisterSpecListener)
        content:HookScript("OnHide", UnregisterSpecListener)
    end

    if content:IsShown() then
        RegisterSpecListener()
    else
        UnregisterSpecListener()
    end

    if state then
        state.spellInput = spellInput
        state.macroInput = macroInput
        state.keyCaptureBtn = keyCaptureBtn
        state.RefreshBindingList = RefreshBindingList
        state.browsePopup = browsePopup
        state.acMenu = acMenu
    end
end

local function BuildClickCastContent(content)
    GUI:SetSearchContext({tabIndex = 7, tabName = "Click-Cast", subTabIndex = 1, subTabName = "Click-Cast"})

    local charDB = QUI and QUI.db and QUI.db.char
    if not charDB then
        local info = GUI:CreateLabel(content, ns.L["Click-cast settings not available."], 12, C.textMuted)
        info:SetPoint("TOPLEFT", PAD, -10)
        content:SetHeight(100)
        return
    end

    local cc = charDB.clickCast
    if not cc then charDB.clickCast = {} cc = charDB.clickCast end

    local refreshClickCast = function()
        local GFCC_ref = ns.QUI_GroupFrameClickCast
        if GFCC_ref and not InCombatLockdown() then
            GFCC_ref:RefreshBindings()
        end
    end

    local state = {}
    content._quiClickCastState = state

    local L = MakeLayout(content)

    SetGeneralSearchContext("Click-Cast")
    BuildClickCastGeneral(L, cc, refreshClickCast, state)
    BuildClickCastPings(L, state)
    BuildClickCastBindings(L, content, cc, refreshClickCast, state)

    if state.perSpecCheck and state.RefreshBindingList then
        state.perSpecCheck.track:HookScript("OnClick", function()
            C_Timer.After(0.05, function()
                if state.UpdatePerLoadoutVisibility then state.UpdatePerLoadoutVisibility() end
                state.RefreshBindingList()
            end)
        end)
    end
    if state.perLoadoutCheck and state.RefreshBindingList then
        state.perLoadoutCheck.track:HookScript("OnClick", function()
            C_Timer.After(0.05, function() state.RefreshBindingList() end)
        end)
    end

    if not content._quiClickCastCleanupHooked then
        content._quiClickCastCleanupHooked = true
        content:HookScript("OnHide", function(self)
            local cleanupState = self and self._quiClickCastState
            if not cleanupState then return end

            if cleanupState.spellInput then cleanupState.spellInput:ClearFocus() end
            if cleanupState.macroInput then cleanupState.macroInput:ClearFocus() end
            if cleanupState.browsePopup then cleanupState.browsePopup:Hide() end
            if cleanupState.acMenu then cleanupState.acMenu:Hide() end
            if cleanupState.keyCaptureBtn and cleanupState.keyCaptureBtn.isCapturing then
                cleanupState.keyCaptureBtn.isCapturing = false
                cleanupState.keyCaptureBtn:EnableKeyboard(false)
            end
            if cleanupState.pingCaptureButtons then
                for _, btn in ipairs(cleanupState.pingCaptureButtons) do
                    if btn.isCapturing then
                        btn.isCapturing = false
                        btn:EnableKeyboard(false)
                    end
                end
            end
            if cleanupState.isPingSuspended and cleanupState.isPingSuspended() then
                local saved = cleanupState.clearPingSuspension()
                C_Timer.After(0, function()
                    for action, keys in pairs(saved) do
                        if keys[1] then SetBinding(keys[1], action) end
                        if keys[2] then SetBinding(keys[2], action) end
                    end
                    SaveBindings(GetCurrentBindingSet())
                end)
            end
        end)
    end
end

local function CreateClickCastPage(parent)
    local _, content = CreateScrollableContent(parent)
    BuildClickCastContent(content)
end

ns.QUI_GroupFramesOptions = {
    BuildClickCastContent = BuildClickCastContent,
    CreateClickCastPage = CreateClickCastPage,
}

if Registry and Schema
    and type(Registry.RegisterFeature) == "function"
    and type(Schema.Feature) == "function"
    and type(Schema.Section) == "function" then
    Registry:RegisterFeature(Schema.Feature({
        id = "clickCastPage",
        moverKey = "clickCast",
        category = "global",
        nav = { tileId = "global", subPageIndex = 5 },
        sections = {
            Schema.Section({
                id = "settings",
                kind = "page",
                minHeight = 80,
                build = BuildClickCastContent,
            }),
        },
    }))
end
