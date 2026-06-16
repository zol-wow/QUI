--[[
    QUI Click-Cast Settings
    Click-casting binding management for group frames.
    Visual/element settings moved to Layout Mode (layoutmode_composer.lua).
]]

local ADDON_NAME, ns = ...
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

-- Local references
local PADDING = Shared.PADDING
local CreateScrollableContent = Shared.CreateScrollableContent

-- Constants
local FORM_ROW = 32
local PAD = 10
local UIKit = ns.UIKit

---------------------------------------------------------------------------
-- SPELL CACHE: Enumerate known non-passive spells from spellbook
---------------------------------------------------------------------------
local spellCache = {}  -- { { spellID, name, icon, tab }, ... }
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
                        -- Only include spells the player currently knows for active spec
                        -- Override spells (e.g. Sacred Weapon overriding Divine Toll) may fail IsPlayerSpell on the override ID — check the base spell too
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
                                -- Resolve base spell so override transforms (e.g. Holy Bulwark → Sacred Weapon) are searchable by either name
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
    -- Sort alphabetically within each tab group
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
        pcall(frame.SetBackdrop, frame, nil)
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
            pcall(compat.originalSetBackdropColor, self, compat.bgColor[1], compat.bgColor[2], compat.bgColor[3], compat.bgColor[4])
        end
    end

    frame.SetBackdropBorderColor = function(self, r, g, b, a)
        local compat = self and self._quiPixelBackdropCompat
        if not compat then return end
        compat.borderColor[1], compat.borderColor[2], compat.borderColor[3], compat.borderColor[4] = r or 0, g or 0, b or 0, a or 1

        if uikit and uikit.UpdateBorderLines then
            uikit.UpdateBorderLines(self, compat.borderPixels or 1, compat.borderColor[1], compat.borderColor[2], compat.borderColor[3], compat.borderColor[4], false)
        elseif compat.originalSetBackdropBorderColor then
            pcall(compat.originalSetBackdropBorderColor, self, compat.borderColor[1], compat.borderColor[2], compat.borderColor[3], compat.borderColor[4])
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

---------------------------------------------------------------------------
-- HELPERS

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

---------------------------------------------------------------------------
-- V3 layout helpers (standard dual-column card pattern, matches other tabs)
---------------------------------------------------------------------------
local HEADER_GAP = 26
local SECTION_GAP = 14

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
        frame:SetParent(content)
        frame:ClearAllPoints()
        frame:SetPoint("TOPLEFT", content, "TOPLEFT", PAD, y)
        frame:SetPoint("RIGHT", content, "RIGHT", -PAD, 0)
        frame:SetHeight(height)
        y = y - height - SECTION_GAP
    end
    function L.offset()
        return y
    end
    return L
end

local function row(parent, label, widget, desc)
    return Shared.BuildSettingRow(parent, label, widget, desc)
end

-- Pair an iterable list of cells 2-per-row, with a trailing unpaired cell.
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
    local smartResW = GUI:CreateFormCheckbox(s.frame, nil, "smartRes", cc, RefreshGF,
        { description = ns.L["When hovering a dead unit, any spell binding is temporarily replaced by your class's resurrection spell if you know one. Restores the original spell when the unit is alive."] })
    local tooltipW = GUI:CreateFormCheckbox(s.frame, nil, "showTooltip", cc, RefreshGF,
        { description = ns.L["Append a summary of your current click-cast bindings to the unit tooltip whenever you hover a group frame, so you can see at a glance which click does what."] })

    local perLoadoutCell = row(s.frame, ns.L["Per-Loadout Bindings"], perLoadoutW)
    pairCells(s, {
        row(s.frame, ns.L["Enable Click-Casting"], enableW),
        row(s.frame, ns.L["Per-Spec Bindings"], perSpecW),
        perLoadoutCell,
        row(s.frame, ns.L["Smart Resurrection"], smartResW),
        row(s.frame, ns.L["Show Binding Tooltip on Hover"], tooltipW),
    })
    L.closeSection(s)

    -- Per-loadout only applies when per-spec is on: standard dependent-row
    -- treatment (grayed + non-interactive instead of hidden, so the card
    -- pairing never reflows).
    local function UpdatePerLoadoutVisibility()
        perLoadoutCell:SetEnabled(cc.perSpec and true or false)
    end
    UpdatePerLoadoutVisibility()

    -- Unit Frame click-cast toggles
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

-- Section 2: Global Ping Keybinds
local function BuildClickCastPings(L, state)
    L.headerAt(ns.L["Global Ping Keybinds"])
    L.intro(ns.L["These keybinds work everywhere: nameplates, world mouseover, or current target. Pings the unit you're looking at."])

    -- Bind directly to Blizzard's native ping binding actions — these
    -- call C_Ping.TogglePingListener / C_Ping.SendMacroPing in secure
    -- context. No SecureActionButtons or /ping macros needed.
    local PING_KEYBIND_ENTRIES = {
        { binding = "TOGGLEPINGLISTENER", label = ns.L["Ping (Contextual)"] },
        { binding = "PINGASSIST",         label = ns.L["Ping: Assist"] },
        { binding = "PINGATTACK",         label = ns.L["Ping: Attack"] },
        { binding = "PINGWARNING",        label = ns.L["Ping: Warning"] },
        { binding = "PINGONMYWAY",        label = ns.L["Ping: On My Way"] },
    }

    local refreshAllPingRows  -- forward declaration; populated after rows are created
    local pingRowUpdaters = {}
    local pingCaptureButtons = {} -- track capture buttons for OnHide cleanup
    -- Shared state for suspending/restoring ping bindings during capture.
    -- Only one capture can be active at a time, so one set of saved
    -- bindings is sufficient.
    local suspendedPingBindings = {}
    local isPingSuspended = false
    local PING_BUTTON_HEIGHT = 24
    local PING_CAPTURE_WIDTH = 130
    local PING_CLEAR_WIDTH = 44

    local function CreatePingKeybindCell(parent, entry)
        -- Capture + clear buttons grouped as the right-hand control of a
        -- standard setting cell (label provided by BuildSettingRow).
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
            -- Restore other bindings (except the key we're about to use)
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
            -- Dismiss any stuck ping listener
            -- Update ALL rows since we may have cleared another entry's key
            if refreshAllPingRows then refreshAllPingRows() end
        end

        local function CancelCapture(self)
            -- Restore all bindings that were suspended
            RestorePingBindings()
            self.isCapturing = false
            self:EnableKeyboard(false)
            SetButtonBorder(self, 0.35, 0.35, 0.35, 1)
            SetButtonHover(self, false)
            -- Dismiss any stuck ping listener
            UpdateKeyText()
        end

        local function GetModifierPrefix()
            local mods = ""
            if IsAltKeyDown() then mods = mods .. "ALT-" end
            if IsControlKeyDown() then mods = mods .. "CTRL-" end
            if IsShiftKeyDown() then mods = mods .. "SHIFT-" end
            return mods
        end

        -- Mouse button names to WoW binding names
        local MOUSE_BIND_NAMES = {
            LeftButton = "BUTTON1", RightButton = "BUTTON2",
            MiddleButton = "BUTTON3", Button4 = "BUTTON4", Button5 = "BUTTON5",
        }

        captureBtn:SetScript("OnClick", function(self, button)
            if not self.isCapturing then
                -- Start capture on left click
                if button == "LeftButton" then
                    -- Suspend all ping bindings first so they don't fire
                    -- when the user presses the key they want to rebind
                    SuspendPingBindings()
                    self.isCapturing = true
                    self:EnableKeyboard(true)
                    SetButtonBorder(self, C.accent[1], C.accent[2], C.accent[3], 1)
                    captureBtn:SetText(ns.L["Press a key or click..."])
                    if keyText then keyText:SetTextColor(C.accent[1], C.accent[2], C.accent[3], 1) end
                end
                return
            end
            -- Capturing: bind the mouse button (except unmodified left which toggles)
            local bindName = MOUSE_BIND_NAMES[button]
            if not bindName then return end
            local mods = GetModifierPrefix()
            -- Unmodified left click cancels capture instead of binding
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
            -- Ignore bare modifier keys
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
            -- Don't cancel capture on leave — the user may move
            -- the mouse while pressing a key. Capture ends on key
            -- press or Escape.
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

    -- Wire up cross-row refresh (called when a binding is set/cleared to update all rows)
    refreshAllPingRows = function()
        for _, updater in ipairs(pingRowUpdaters) do
            updater()
        end
    end

    -- Export cleanup refs for OnHide handler
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

-- Section 3: Manage Bindings (current list + add form)
local function BuildClickCastBindings(L, content, cc, refreshClickCast, state)
    local GFCC = ns.QUI_GroupFrameClickCast

    local ACTION_TYPE_OPTIONS = {
        { value = "spell",        text = ns.L["Spell"] },
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

    -- Dynamic block: spec label + current-bindings list + add form. The
    -- add form anchors to the list bottom so it flows down as bindings are
    -- added/removed; RefreshBindingList re-measures the block and the
    -- page content height.
    local fixedTop = math.abs(L.offset())
    local bindingsBlock = CreateFrame("Frame", nil, content)
    L.placeCustom(bindingsBlock, 100) -- provisional; RefreshBindingList re-measures

    local by = 0

    -- Spec context label
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
                            -- The active configID is an ephemeral staging copy;
                            -- match it to the saved loadout via GetLastSelectedSavedConfigID
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
                            -- Use custom name if it differs from the spec name, otherwise just "Loadout N"
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

    -- Current bindings list
    Shared.CreateAccentDotLabel(bindingsBlock, ns.L["Current Bindings"], by); by = by - 30

    local bindingListFrame = CreateFrame("Frame", nil, bindingsBlock)
    bindingListFrame:SetPoint("TOPLEFT", 0, by)
    bindingListFrame:SetSize(400, 20)
    local listTopOffset = math.abs(by)

    local RefreshBindingList

    -- Add binding form
    local addContainer = CreateFrame("Frame", nil, bindingsBlock)
    addContainer:SetPoint("TOPLEFT", bindingListFrame, "BOTTOMLEFT", 0, -10)
    addContainer:SetPoint("RIGHT", bindingsBlock, "RIGHT", 0, 0)
    addContainer:SetHeight(400)
    addContainer:EnableMouse(false)

    Shared.CreateAccentDotLabel(addContainer, ns.L["Add Binding"], 0)
    local ay = -30

    -- Drop zone for spellbook/macro drag
    local dropZone = CreateClickCastButton(addContainer, ns.L["Drop a spell or macro here"], 1, 68, nil, "primary")
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

    local addState = { bindingType = "mouse", button = "LeftButton", key = nil, modifiers = "", actionType = "spell", spellName = "", macroText = "" }
    local spellInput, macroInput, actionDrop
    local spellInputContainer, macroInputContainer
    local mouseButtonContainer, keyCaptureContainer
    local triggerCell

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
                    addState.spellName = name
                    addState.actionType = "spell"
                    if spellInput then spellInput:SetText(name) end
                    if actionDrop then actionDrop.SetValue("spell", true) end
                    if spellInputContainer then spellInputContainer:Show() end
                    if macroInputContainer then macroInputContainer:Hide() end
                end
            end
            ClearCursor()
            return true
        elseif cursorType == "macro" then
            local macroIndex = id1
            if macroIndex then
                local name, _, body = GetMacroInfo(macroIndex)
                if body then
                    addState.actionType = "macro"
                    addState.macroText = body
                    addState.spellName = name or ns.L["Macro"]
                    if macroInput then macroInput:SetText(body) end
                    if actionDrop then actionDrop.SetValue("macro", true) end
                    if macroInputContainer then macroInputContainer:Show() end
                    if spellInputContainer then spellInputContainer:Hide() end
                end
            end
            ClearCursor()
            return true
        end
        return false
    end

    dropZone:SetScript("OnReceiveDrag", HandleCursorDrop)
    dropZone:SetScript("OnClick", function()
        -- Clear any lingering editbox focus
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

    -- Form card: standard dual-column rows for the add-binding dropdowns.
    local formCard = Shared.CreateSettingsCardGroup(addContainer, ay)

    -- Binding type dropdown
    local bindingTypeDrop = GUI:CreateFormDropdown(formCard.frame, nil, BINDING_TYPE_OPTIONS, "bindingType", addState, function(val)
        addState.bindingType = val
        if mouseButtonContainer then mouseButtonContainer:SetShown(val == "mouse") end
        if keyCaptureContainer then keyCaptureContainer:SetShown(val == "key") end
        if triggerCell and triggerCell._label then
            triggerCell._label:SetText(val == "key" and ns.L["Key"] or ns.L["Mouse Button"])
        end
    end, { description = ns.L["Whether this binding fires on a mouse button (including scroll) or on a keyboard key pressed while hovering a unit frame."] })

    -- Trigger control: the mouse-button dropdown is the cell widget (so it
    -- keeps its search registration); the key-capture button overlays it
    -- and the Binding Type dropdown swaps which is shown.
    local buttonDrop = GUI:CreateFormDropdown(formCard.frame, nil, BUTTON_OPTIONS, "button", addState, nil,
        { description = ns.L["Mouse button or scroll direction this binding fires on when hovering a unit frame. Combine with a modifier below to layer multiple actions onto the same button."] })
    mouseButtonContainer = buttonDrop

    -- Keyboard key capture (reparented over the dropdown once the cell is built)
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
        -- Don't cancel capture on leave — the user may move
        -- the mouse while pressing a key. Capture ends on key
        -- press or Escape.
        if not self.isCapturing then
            SetButtonBorder(self, 0.35, 0.35, 0.35, 1)
            SetButtonHover(self, false)
        end
    end)

    -- Modifier dropdown
    local modDrop = GUI:CreateFormDropdown(formCard.frame, nil, MOD_OPTIONS, "modifiers", addState, nil,
        { description = ns.L["Modifier key(s) that must be held for this binding to fire. Use None for the unmodified click or key — different modifiers let you stack multiple actions on the same button."] })

    -- Action type dropdown
    actionDrop = GUI:CreateFormDropdown(formCard.frame, nil, ACTION_TYPE_OPTIONS, "actionType", addState, function(val)
        addState.actionType = val
        if spellInputContainer then spellInputContainer:SetShown(val == "spell") end
        if macroInputContainer then macroInputContainer:SetShown(val == "macro") end
    end, { description = ns.L["What this binding does: cast a spell or macro, change target/focus/assist, open the unit menu, or send a ping. Spell and Macro reveal an input below for the spell name or macro body."] })

    triggerCell = row(formCard.frame, ns.L["Mouse Button"], buttonDrop)
    keyCaptureContainer:SetParent(triggerCell)
    keyCaptureContainer:SetAllPoints(buttonDrop)
    formCard.AddRow(row(formCard.frame, ns.L["Binding Type"], bindingTypeDrop), triggerCell)
    formCard.AddRow(row(formCard.frame, ns.L["Modifier"], modDrop), row(formCard.frame, ns.L["Action Type"], actionDrop))
    formCard.Finalize()
    ay = ay - formCard.frame:GetHeight() - 8

    -- Spell name editbox with autocomplete + browse
    spellInputContainer = CreateFrame("Frame", nil, addContainer)
    spellInputContainer:SetHeight(FORM_ROW)
    spellInputContainer:SetPoint("TOPLEFT", 0, ay)
    spellInputContainer:SetPoint("RIGHT", addContainer, "RIGHT", 0, 0)

    local spellLabel = spellInputContainer:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    spellLabel:SetPoint("LEFT", 0, 0)
    spellLabel:SetText(ns.L["Spell Name"])
    spellLabel:SetTextColor(C.text[1], C.text[2], C.text[3], 1)

    -- Browse button (right side)
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

    -----------------------------------------------------------------------
    -- AUTOCOMPLETE DROPDOWN: shows matching spells below the input
    -----------------------------------------------------------------------
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
        local lower = searchText:lower()
        local matches = {}
        for _, entry in ipairs(spells) do
            if entry.name:lower():find(lower, 1, true) or (entry.baseName and entry.baseName:lower():find(lower, 1, true)) then
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
        -- Delay hide so row OnClick fires first
        C_Timer.After(0.1, function() acMenu:Hide() end)
    end)

    -----------------------------------------------------------------------
    -- BROWSE SPELLS POPUP: scrollable grouped spell list with search
    -----------------------------------------------------------------------
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

    -- Title
    local browseTitle = browsePopup:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    browseTitle:SetPoint("TOPLEFT", 10, -8)
    browseTitle:SetText(ns.L["Browse Spells"])
    CJKFont(browseTitle, GUI.FONT_PATH, 12, "")
    browseTitle:SetTextColor(C.accent[1], C.accent[2], C.accent[3], 1)

    -- Close button
    local browseCloseBtn = CreateClickCastButton(browsePopup, "X", 20, 20, function() browsePopup:Hide() end)
    browseCloseBtn:SetPoint("TOPRIGHT", -6, -6)
    if browseCloseBtn.text then
        CJKFont(browseCloseBtn.text, GUI.FONT_PATH, 11, "")
    end

    -- Search box
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

    -- Scroll frame for spell list (custom styled, no UIPanelScrollFrameTemplate)
    local SCROLLBAR_WIDTH = 4
    local SCROLL_STEP = 24

    local browseScroll = CreateFrame("ScrollFrame", nil, browsePopup)
    browseScroll:SetPoint("TOPLEFT", 8, -58)
    browseScroll:SetPoint("BOTTOMRIGHT", -(8 + SCROLLBAR_WIDTH + 2), 8)

    local browseScrollChild = CreateFrame("Frame", nil, browseScroll)
    browseScrollChild:SetWidth(browseScroll:GetWidth() or 296)
    browseScrollChild:SetHeight(1)
    browseScroll:SetScrollChild(browseScrollChild)

    -- Thin accent-colored scrollbar thumb (matches framework dropdown style)
    local browseScrollBar = CreateFrame("Frame", nil, browsePopup)
    browseScrollBar:SetWidth(SCROLLBAR_WIDTH)
    browseScrollBar:SetPoint("TOPRIGHT", browsePopup, "TOPRIGHT", -8, -58)
    browseScrollBar:SetPoint("BOTTOMRIGHT", browsePopup, "BOTTOMRIGHT", -8, 8)
    browseScrollBar:Hide()

    local browseThumb = browseScrollBar:CreateTexture(nil, "OVERLAY")
    browseThumb:SetWidth(SCROLLBAR_WIDTH)
    browseThumb:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 0.5)

    local function UpdateBrowseThumb()
        local contentH = browseScrollChild:GetHeight()
        local frameH = browseScroll:GetHeight()
        if contentH <= frameH or frameH <= 0 then
            browseScrollBar:Hide()
            return
        end
        browseScrollBar:Show()
        local trackH = browseScrollBar:GetHeight()
        if trackH <= 0 then return end
        local thumbH = math.max(20, (frameH / contentH) * trackH)
        browseThumb:SetHeight(thumbH)
        local scrollMax = contentH - frameH
        local okScroll, scrollCur = pcall(browseScroll.GetVerticalScroll, browseScroll)
        scrollCur = (okScroll and scrollCur) or 0
        local ratio = (scrollMax > 0) and (scrollCur / scrollMax) or 0
        local yOff = -ratio * (trackH - thumbH)
        browseThumb:ClearAllPoints()
        browseThumb:SetPoint("TOP", browseScrollBar, "TOP", 0, yOff)
    end

    browseScroll:EnableMouseWheel(true)
    browseScroll:SetScript("OnMouseWheel", function(self, delta)
        local okCur, currentScroll = pcall(self.GetVerticalScroll, self)
        if not okCur then return end
        local contentH = browseScrollChild:GetHeight()
        local frameH = self:GetHeight()
        local maxScroll = math.max(0, contentH - frameH)
        local newScroll = math.max(0, math.min(currentScroll - (delta * SCROLL_STEP), maxScroll))
        pcall(self.SetVerticalScroll, self, newScroll)
        UpdateBrowseThumb()
    end)
    browseScroll:SetScript("OnScrollRangeChanged", function() UpdateBrowseThumb() end)

    -- Ensure child width matches scroll frame after layout
    browseScroll:SetScript("OnSizeChanged", function(self, w)
        browseScrollChild:SetWidth(w or 296)
    end)

    local BROWSE_ROW_H = 24
    local browseRows = {}
    local browseRowIndex = 0
    local expandedTabs = {}  -- [tabName] = true when expanded (default: collapsed)

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
                spellInput:SetText(self.spellName)
                addState.spellName = self.spellName
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

        -- Chevron indicator
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

    local BuildBrowseList  -- forward declaration for header click

    local function BuildBrowseListImpl(filter)
        -- Hide old rows
        for _, row in ipairs(browseRows) do row:Hide() end
        browseRowIndex = 0

        local spells = EnsureSpellCache()
        local lower = filter and filter ~= "" and filter:lower() or nil
        local by = 0
        local currentTab = nil

        -- When searching, ignore collapsed state so all matches show
        local ignoreCollapse = lower ~= nil

        for _, entry in ipairs(spells) do
            if not lower or entry.name:lower():find(lower, 1, true) or (entry.baseName and entry.baseName:lower():find(lower, 1, true)) then
                -- Tab header
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

                -- Spell row (skip if tab is collapsed and not searching)
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
        -- Reset scroll to top and update thumb
        pcall(browseScroll.SetVerticalScroll, browseScroll, 0)
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

    browseBtn:SetScript("OnClick", function()
        if browsePopup:IsShown() then
            browsePopup:Hide()
            return
        end
        RebuildSpellCache()
        browseSearch:SetText("")
        BuildBrowseList(nil)
        browsePopup:Show()
        browsePopup:Raise()
    end)

    browsePopup:SetScript("OnHide", function()
        browseSearch:SetText("")
        browseSearchPlaceholder:Show()
    end)

    ay = ay - FORM_ROW

    -- Macro text editbox
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

    -- Add Binding button
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
            -- Store root spell ID so binding survives talent overrides
            local baseID = C_Spell.GetBaseSpell and C_Spell.GetBaseSpell(spellID) or spellID
            newBinding.spellID = baseID
            local rootName = C_Spell.GetSpellName(baseID)
            newBinding.spell = rootName or C_Spell.GetSpellName(spellID) or name
        elseif actionType == "macro" then
            local text = addState.macroText
            if not text or text == "" then print("|cFFFF5555[QUI]|r " .. ns.L["Enter macro text."]) return end
            newBinding.spell = "Macro"
            newBinding.macro = text
        else
            newBinding.spell = actionType
        end
        local ok, err = GFCC:AddBinding(newBinding)
        if not ok then print("|cFFFF5555[QUI]|r " .. (err or ns.L["Failed to add binding."])) return end
        addState.spellName = ""
        addState.macroText = ""
        addState.key = nil
        spellInput:SetText("")
        macroInput:SetText("")
        keyCaptureBtn:SetText(ns.L["Click to bind a key"])
        if keyCaptureText then keyCaptureText:SetTextColor(C.textMuted[1], C.textMuted[2], C.textMuted[3], 1) end
        RefreshBindingList()
    end)
    addBtn:SetPoint("TOPLEFT", 0, addBtnY)
    addContainer:SetHeight(math.abs(addBtnY) + 36)

    -- Refresh binding list
    RefreshBindingList = function()
        for _, child in ipairs({bindingListFrame:GetChildren()}) do
            child:Hide()
            child:SetParent(nil)
        end
        UpdateSpecLabel()
        local buttonNames = GFCC:GetButtonNames()
        local modLabels  = GFCC:GetModifierLabels()
        local bindings   = GFCC:GetEditableBindings()
        local listY = 0
        if #bindings == 0 then
            local emptyLabel = CreateFrame("Frame", nil, bindingListFrame)
            emptyLabel:SetSize(300, 28)
            emptyLabel:SetPoint("TOPLEFT", 0, 0)
            local emptyText = emptyLabel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            emptyText:SetPoint("LEFT", 0, 0)
            emptyText:SetText(ns.L["No bindings configured yet."])
            emptyText:SetTextColor(C.textMuted[1], C.textMuted[2], C.textMuted[3], 1)
            listY = -28
        else
            for i, binding in ipairs(bindings) do
                local actionType = binding.actionType
                if type(actionType) ~= "string" then actionType = "spell" end
                local spellName = binding.spell
                if type(spellName) ~= "string" then spellName = nil end
                -- Resolve current spell name from root spellID (shows override if active)
                local resolvedSpellID = binding.spellID
                if resolvedSpellID and actionType == "spell" then
                    local currentName = C_Spell.GetSpellName(resolvedSpellID)
                    if currentName then spellName = currentName end
                end
                local row = CreateFrame("Frame", nil, bindingListFrame)
                row:SetSize(400, 28)
                row:SetPoint("TOPLEFT", 0, listY)
                local iconTex = row:CreateTexture(nil, "ARTWORK")
                iconTex:SetSize(24, 24)
                iconTex:SetPoint("LEFT", 0, 0)
                iconTex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
                if actionType == "spell" and spellName then
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
                local comboText = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
                comboText:SetPoint("LEFT", iconTex, "RIGHT", 6, 0)
                comboText:SetWidth(140)
                comboText:SetJustifyH("LEFT")
                comboText:SetText(modLabel .. triggerLabel)
                comboText:SetTextColor(C.text[1], C.text[2], C.text[3], 1)
                local spellText = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
                spellText:SetPoint("LEFT", comboText, "RIGHT", 8, 0)
                spellText:SetWidth(140)
                spellText:SetJustifyH("LEFT")
                local displayName = spellName or actionType
                if actionType == "macro" then displayName = ns.L["Macro"]
                elseif actionType == "menu" then displayName = ns.L["Unit Menu"]
                elseif PING_DISPLAY_NAMES[actionType] then displayName = PING_DISPLAY_NAMES[actionType] end
                spellText:SetText(displayName)
                spellText:SetTextColor(C.textMuted[1], C.textMuted[2], C.textMuted[3], 1)
                local removeBtn = CreateClickCastButton(row, "X", 22, 22, function() GFCC:RemoveBinding(i) RefreshBindingList() end)
                if removeBtn.text then
                    removeBtn.text:SetTextColor(C.accent[1], C.accent[2], C.accent[3], 0.7)
                end
                SetButtonFill(removeBtn, 0.1, 0.1, 0.1, 0.8)
                SetButtonBorder(removeBtn, 0.3, 0.3, 0.3, 1)
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
                listY = listY - 30
            end
        end
        local listHeight = math.max(20, math.abs(listY))
        bindingListFrame:SetHeight(listHeight)
        local blockHeight = listTopOffset + listHeight + 10 + addContainer:GetHeight()
        bindingsBlock:SetHeight(blockHeight)
        local totalHeight = fixedTop + blockHeight + 30
        content:SetHeight(totalHeight)

        -- Propagate new height to the collapsible section so it resizes.
        -- The section's bodyClip (ScrollFrame) clips content to the old
        -- height, so we must grow it — plus update the outer scroll
        -- content so the scroll range covers the new total.
        local section = content._logicalSection
        if section and section._expanded and section._bodyClip then
            section._contentHeight = totalHeight
            section._bodyClip:SetHeight(totalHeight)
            local sectionH = 24 + totalHeight -- 24 = COLLAPSIBLE_HEADER_HEIGHT
            local prevH = section:GetHeight() or 0
            section:SetHeight(sectionH)
            -- Grow the outer scroll content by the delta
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
        -- Scale refreshes are triggered by pixel-border creation. Rebuilding the
        -- binding rows here creates more bordered buttons, which queues more
        -- scale refreshes and can spiral while the options panel is open.
        UIKit.RegisterScaleRefresh(content, "clickCastPixelFrames", RefreshClickCastPixelFrames)
    end

    -- Only listen while the bindings section is actually visible so hidden
    -- search-index page builds do not leave background listeners behind.
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

    -- Export cleanup refs for OnHide handler
    if state then
        state.spellInput = spellInput
        state.macroInput = macroInput
        state.keyCaptureBtn = keyCaptureBtn
        state.RefreshBindingList = RefreshBindingList
        state.browsePopup = browsePopup
        state.acMenu = acMenu
    end
end

---------------------------------------------------------------------------
-- Combined builder for the click-cast page (calls all 3 sections)

local function BuildClickCastContent(content)
    GUI:SetSearchContext({tabIndex = 7, tabName = "Click-Cast", subTabIndex = 1, subTabName = "Click-Cast"})

    -- Click-cast settings are character-scoped (see groupframes_clickcast.lua
    -- for the rationale). Read directly from db.char rather than gfdb so the
    -- settings UI writes to the same location the runtime reads from.
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
    -- No trailing SetHeight here: BuildClickCastBindings' RefreshBindingList
    -- owns the final content height (the bindings list grows at runtime).

    -- Wire cross-section: per-spec toggle refreshes binding list + perLoadout visibility
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

    -- Clear editbox focus and cancel any active key captures when the
    -- scroll content is hidden (tab change / panel close) to prevent
    -- stuck keyboard capture.
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

---------------------------------------------------------------------------
-- EXPORT
---------------------------------------------------------------------------
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
