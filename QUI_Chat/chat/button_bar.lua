---------------------------------------------------------------------------
-- QUI Chat Module — Custom Button Bar (Phase F)
-- Per-chat-frame button bar with positioning modes. Built-in buttons
-- (QUI options, Layout Mode, Keybind, CDM, Friends, Guild, Reload) plus
-- user-defined slash-command buttons. Default off; opt-in per frame.
--
-- Storage: db.profile.chat.buttonBars[<frameID>] = {
--     enabled, position, offsetX, offsetY, buttonSpacing, hideInCombat,
--     buttons = { { id, visible }, ... },
--     customButtons = { { label, slashCommand, icon }, ... }
-- }
--
-- Reconcile triggers:
--   * ADDON_LOADED (after defaults wiring)
--   * PLAYER_LOGIN (after Blizzard finishes initializing chat windows)
--   * PLAYER_REGEN_DISABLED / PLAYER_REGEN_ENABLED visibility changes
--   * Settings change via the chat module's _afterRefresh chain
--   * FCF_OpenNewWindow / FCF_PopOutChat / FCF_Tab_OnClick layout shifts
---------------------------------------------------------------------------

local ADDON_NAME, ns = ...

local I = assert(ns.QUI.Chat and ns.QUI.Chat._internals,
    "QUI Chat: button_bar.lua loaded before chat.lua. Check chat.xml — chat.lua must precede button_bar.lua.")

local Helpers  = ns.Helpers

ns.QUI.Chat.ButtonBar = ns.QUI.Chat.ButtonBar or {}
local BB = ns.QUI.Chat.ButtonBar

-- Forward declaration so closures (event handler, after-refresh, hooks) can
-- capture ApplyEnabled before its body is assigned later in the file.
local ApplyEnabled
local reconcileAll
local scheduleReconcileAll
local ensureVisibilityHooks

-- ---------------------------------------------------------------------------
-- Built-in button definitions
-- ---------------------------------------------------------------------------
-- Each entry is keyed by a stable id stored in the user's buttons array.
-- The action closure runs on click; tooltip is shown on hover. label is the
-- button text (icons deferred — texture-based buttons would need additional
-- art assets; the text label keeps the bar self-contained).

local BUILTINS = {
    qui_options = {
        label = ns.L["QUI"],
        action = function()
            if _G.QUI and _G.QUI.OpenOptions then
                _G.QUI:OpenOptions()
            else
                print("|cFF56D1FFQUI:|r Options are not available yet. Try again in a moment.")
            end
        end,
        tooltip = ns.L["Open QUI options"],
    },
    qui_layout = {
        label = ns.L["Layout"],
        action = function()
            if _G.QUI_ToggleLayoutMode then
                _G.QUI_ToggleLayoutMode()
            else
                print("|cff60A5FAQUI:|r Layout Mode not loaded yet.")
            end
        end,
        tooltip = ns.L["Toggle Layout Mode"],
    },
    qui_keybind = {
        label = ns.L["KB"],
        action = function()
            local LibKeyBound = LibStub and LibStub("LibKeyBound-1.0", true)
            if LibKeyBound then
                LibKeyBound:Toggle()
            elseif _G.QuickKeybindFrame then
                ShowUIPanel(_G.QuickKeybindFrame)
            else
                print("|cff60A5FAQUI:|r Quick Keybind Mode not available.")
            end
        end,
        tooltip = ns.L["Toggle keybind mode"],
    },
    qui_cdm = {
        label = ns.L["CDM"],
        action = function()
            if _G.CooldownViewerSettings then
                _G.CooldownViewerSettings:SetShown(not _G.CooldownViewerSettings:IsShown())
            else
                print("|cff60A5FAQUI:|r Cooldown Settings not available. Enable CDM first.")
            end
        end,
        tooltip = ns.L["Open Cooldown Manager settings"],
    },
    social = {
        label = ns.L["Friends"],
        action = function()
            if type(_G.ToggleFriendsFrame) == "function" then
                _G.ToggleFriendsFrame()
            end
        end,
        tooltip = ns.L["Toggle Friends list"],
    },
    guild = {
        label = ns.L["Guild"],
        action = function()
            if type(_G.ToggleGuildFrame) == "function" then
                _G.ToggleGuildFrame()
            end
        end,
        tooltip = ns.L["Toggle Guild frame"],
    },
    reload = {
        label = ns.L["Reload"],
        action = function()
            if _G.QUI and type(_G.QUI.SafeReload) == "function" then
                _G.QUI:SafeReload()
            elseif type(_G.ReloadUI) == "function" then
                _G.ReloadUI()
            end
        end,
        tooltip = "/reload",
    },
}

-- Stable iteration order for the settings UI checklist + default buttons.
local BUILTIN_ORDER = {
    "qui_options", "qui_layout", "qui_keybind", "qui_cdm",
    "social", "guild", "reload",
}

-- ---------------------------------------------------------------------------
-- Visual skin (shared by text + icon variants)
-- ---------------------------------------------------------------------------
-- Buttons are addon-owned non-secure frames, so the QUI backdrop can be
-- applied directly — unlike skinning/system/gamemenu.lua which uses an
-- overlay container to avoid tainting GameMenuFrame's pool buttons.
local function applySkin(button)
    local sr, sg, sb, sa, bgr, bgg, bgb, bga = Helpers.GetSkinColors()
    ns.SkinBase.ApplyFullBackdrop(button, sr, sg, sb, sa, bgr, bgg, bgb, bga)
    -- Cache the canonical base colors in dedicated _quiBase* fields. The hover
    -- hooks must NOT read from _quiBg*/_quiBorder*: ApplyFullBackdrop's manual
    -- backdrop installs ManualSetBackdropColor as SetBackdropColor, which WRITES
    -- those fields on every call -- so the OnEnter brighten would overwrite them
    -- and OnLeave would "restore" to the brightened value (the highlight would
    -- stick and compound on each hover). These _quiBase* fields are only written
    -- here, by a real (re)skin, so a live theme refresh (re-running applySkin)
    -- still propagates the new colors to the hover state.
    button._quiBaseBgR, button._quiBaseBgG, button._quiBaseBgB, button._quiBaseBgA = bgr, bgg, bgb, bga
    button._quiBaseBorderR, button._quiBaseBorderG, button._quiBaseBorderB, button._quiBaseBorderA = sr, sg, sb, sa

    if button._quiHoverHooked then return end
    button._quiHoverHooked = true

    button:HookScript("OnEnter", function(self)
        if not self._quiBaseBgR then return end
        self:SetBackdropColor(
            math.min(self._quiBaseBgR + 0.30, 1),
            math.min(self._quiBaseBgG + 0.30, 1),
            math.min(self._quiBaseBgB + 0.30, 1),
            self._quiBaseBgA)
        self:SetBackdropBorderColor(
            math.min(self._quiBaseBorderR * 1.6, 1),
            math.min(self._quiBaseBorderG * 1.6, 1),
            math.min(self._quiBaseBorderB * 1.6, 1),
            self._quiBaseBorderA)
    end)
    button:HookScript("OnLeave", function(self)
        if not self._quiBaseBgR then return end
        self:SetBackdropColor(self._quiBaseBgR, self._quiBaseBgG, self._quiBaseBgB, self._quiBaseBgA)
        self:SetBackdropBorderColor(self._quiBaseBorderR, self._quiBaseBorderG, self._quiBaseBorderB, self._quiBaseBorderA)
    end)
end

-- ---------------------------------------------------------------------------
-- Per-frame bar state
-- ---------------------------------------------------------------------------

-- Map: chatFrame -> bar Frame. Weak-keyed so a torn-down chat frame doesn't
-- pin the bar in memory.
local bars = setmetatable({}, { __mode = "k" })
local visibilityHookedFrames = setmetatable({}, { __mode = "k" })

-- Re-apply the skin to every live button. Registered with the Registry
-- "skinning" group (below) so a skin/accent/border color change updates the
-- buttons immediately. The chat _afterRefresh chain only fires on chat settings
-- changes, not on a global skin-color change, so without this a recolor would
-- not reach the buttons until the next chat refresh or a /reload.
local function reskinAll()
    for _, bar in pairs(bars) do
        if bar.GetChildren then
            for _, child in ipairs({ bar:GetChildren() }) do
                if child._quiHoverHooked then
                    applySkin(child)
                end
            end
        end
    end
end

-- ---------------------------------------------------------------------------
-- Bar creation / layout
-- ---------------------------------------------------------------------------

local function isInCombat()
    return type(InCombatLockdown) == "function" and InCombatLockdown()
end

local function normalizeMacroText(text)
    if type(text) ~= "string" then return nil end
    text = text:match("^%s*(.-)%s*$") or ""
    if text == "" then return nil end
    if text:sub(1, 1) ~= "/" then
        text = "/" .. text
    end
    return text
end

local function hasCustomMacroButtons(config)
    if type(config) ~= "table" or type(config.customButtons) ~= "table" then
        return false
    end

    for i = 1, #config.customButtons do
        local cb = config.customButtons[i]
        if type(cb) == "table" and normalizeMacroText(cb.slashCommand) then
            return true
        end
    end

    return false
end

local function createButton(parent, def, customAction)
    local hasIcon = type(def.icon) == "string" and def.icon ~= ""
    local macroText = normalizeMacroText(def.macroText)
    -- Custom commands need a secure action button; RunMacroText is protected
    -- when called from an insecure addon click handler.
    local template = macroText and "SecureActionButtonTemplate,BackdropTemplate" or "BackdropTemplate"
    local btn = CreateFrame("Button", nil, parent, template)

    if macroText then
        btn:RegisterForClicks("AnyUp")
        btn:SetAttribute("type", "macro")
        btn:SetAttribute("macrotext", macroText)
    else
        btn:SetScript("OnClick", customAction or def.action or function() end)
    end

    if hasIcon then
        btn:SetSize(22, 22)
        local icon = btn:CreateTexture(nil, "ARTWORK")
        icon:SetTexture(def.icon)
        icon:SetPoint("TOPLEFT",     btn, "TOPLEFT",      2, -2)
        icon:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -2,  2)
        local hl = btn:CreateTexture(nil, "HIGHLIGHT")
        hl:SetTexture(def.icon)
        hl:SetPoint("TOPLEFT",     btn, "TOPLEFT",      2, -2)
        hl:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -2,  2)
        hl:SetBlendMode("ADD")
        hl:SetAlpha(0.4)
    else
        btn:SetSize(60, 18)
        local fs = btn:CreateFontString(nil, "ARTWORK")
        local fontPath = (Helpers and Helpers.GetGeneralFont and Helpers.GetGeneralFont()) or STANDARD_TEXT_FONT
        if ns.Helpers and ns.Helpers.ApplyFontWithFallback then
            ns.Helpers.ApplyFontWithFallback(fs, fontPath, 11, "OUTLINE")
        else
            fs:SetFont(fontPath, 11, "OUTLINE")
        end
        fs:SetTextColor(0.9, 0.9, 0.9, 1)
        fs:SetPoint("CENTER")
        fs:SetText(def.label or "?")
        btn:SetFontString(fs)
    end

    btn.tooltipText = def.tooltip or def.label
    btn:SetScript("OnEnter", function(self)
        if self.tooltipText then
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetText(self.tooltipText)
            GameTooltip:Show()
        end
    end)
    btn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    applySkin(btn)
    return btn
end

local function GetSafeFrameHeight(frame, fallback)
    fallback = fallback or 100
    if not frame or not frame.GetHeight then return fallback end

    local height = frame:GetHeight()
    if Helpers.IsSecretValue and Helpers.IsSecretValue(height) then
        return fallback
    end

    height = tonumber(height)
    if not height or height <= 0 then return fallback end
    return height
end

-- Takeover anchor: while the Blizzard frames are suppressed (reparented to the
-- hidden anchor), frame 1's bar follows the custom display container (the bar
-- itself is parented to UIParent, so it stays visible either way — only the
-- anchor moves).
local function GetBarAnchorFrame(chatFrame, frameID)
    if frameID == 1 then
        local Suppress = ns.QUI.Chat.BlizzardSuppress
        if Suppress and Suppress.IsActive and Suppress.IsActive() then
            local Display = ns.QUI.Chat.DisplayLayer
            local c = Display and Display.GetContainer and Display.GetContainer()
            if c and c.IsShown and c:IsShown() then
                return c
            end
        end
    end
    return chatFrame
end
BB._GetBarAnchorFrame = GetBarAnchorFrame -- exposed for unit tests

-- Visibility teardown only applies when the bar is actually anchored to the
-- Blizzard frame — a suppressed frame-1 (intentionally hidden) re-anchors to
-- the custom display instead (the old visibility check tore the bar down
-- before the anchor chooser could move it).
local function ShouldSkipVisibilityTeardown(chatFrame, frameID)
    return GetBarAnchorFrame(chatFrame, frameID) ~= chatFrame
end
BB._ShouldSkipVisibilityTeardown = ShouldSkipVisibilityTeardown -- for unit tests

-- Public reconcile for the display-fallback path: suppression flips change
-- the frame-1 bar's anchor target, and DisplayFallback.Apply runs AFTER the
-- _afterRefresh chain — re-reconcile here so the bar moves immediately
-- instead of one refresh late.
function BB.Reapply()
    if ApplyEnabled then
        ApplyEnabled()
    end
end

local function buildBar(chatFrame, frameID, config)
    local hasSecureButtons = hasCustomMacroButtons(config)
    if hasSecureButtons and isInCombat() then
        return
    end

    local bar = bars[chatFrame]
    if bar then
        -- Tear down children and rebuild — config changes are infrequent and
        -- per-button diffing isn't worth the complexity here.
        for _, child in ipairs({ bar:GetChildren() }) do
            child:Hide()
            child:SetParent(nil)
        end
    else
        bar = CreateFrame("Frame", "QUIChatButtonBar" .. tostring(frameID), UIParent)
        bars[chatFrame] = bar
    end
    bar._hasSecureCustomButtons = hasSecureButtons

    bar:ClearAllPoints()

    local anchorFrame = GetBarAnchorFrame(chatFrame, frameID)

    local ox = tonumber(config.offsetX) or 0
    local oy = tonumber(config.offsetY) or 0
    local buttonSpacing = tonumber(config.buttonSpacing) or 2
    if buttonSpacing < 0 then buttonSpacing = 0 end

    local position = config.position or "outside_left"
    local chatHeight = GetSafeFrameHeight(anchorFrame, 100)
    if position == "outside_left" then
        bar:SetSize(70, math.max(chatHeight, 20))
        bar:SetPoint("TOPRIGHT",    anchorFrame, "TOPLEFT",    ox, oy)
        bar:SetPoint("BOTTOMRIGHT", anchorFrame, "BOTTOMLEFT", ox, oy)
    elseif position == "outside_right" then
        bar:SetSize(70, math.max(chatHeight, 20))
        bar:SetPoint("TOPLEFT",    anchorFrame, "TOPRIGHT",    ox, oy)
        bar:SetPoint("BOTTOMLEFT", anchorFrame, "BOTTOMRIGHT", ox, oy)
    elseif position == "inside_left" then
        bar:SetSize(70, math.max(chatHeight - 24, 20))
        bar:SetPoint("TOPLEFT",    anchorFrame, "TOPLEFT",    4 + ox, -24 + oy)
        bar:SetPoint("BOTTOMLEFT", anchorFrame, "BOTTOMLEFT", 4 + ox,   4 + oy)
    elseif position == "inside_right" then
        bar:SetSize(70, math.max(chatHeight - 24, 20))
        bar:SetPoint("TOPRIGHT",    anchorFrame, "TOPRIGHT",    -4 + ox, -24 + oy)
        bar:SetPoint("BOTTOMRIGHT", anchorFrame, "BOTTOMRIGHT", -4 + ox,   4 + oy)
    elseif position == "inside_tabs" then
        bar:SetSize(180, 22)
        -- Anchor to the configured frame's own tab. Visibility reconciliation
        -- below keeps inactive docked frames from leaving their bars behind.
        -- When suppressed the tab is reparented to the hidden anchor, so skip
        -- the tab anchor while suppression is active.
        local tab = _G["ChatFrame" .. tostring(frameID) .. "Tab"]
        local suppressed = anchorFrame ~= chatFrame
        if tab and tab:IsShown() and not suppressed then
            bar:SetPoint("LEFT", tab, "RIGHT", 8 + ox, oy)
        else
            bar:SetPoint("TOPLEFT", anchorFrame, "TOPLEFT", ox, 8 + oy)
        end
    elseif position == "hidden" then
        bar:Hide()
        return
    end

    bar:Show()

    -- Resolve the button list. Built-in buttons live in config.buttons as
    -- { id = "<builtinKey>", visible = bool }. Custom buttons live in
    -- config.customButtons as { label, slashCommand, icon }.
    local widgets = {}
    if type(config.buttons) == "table" then
        for i = 1, #config.buttons do
            local b = config.buttons[i]
            if b and b.visible and BUILTINS[b.id] then
                widgets[#widgets + 1] = createButton(bar, BUILTINS[b.id])
            end
        end
    end
    if type(config.customButtons) == "table" then
        for i = 1, #config.customButtons do
            local cb = config.customButtons[i]
            local hasLabel   = type(cb) == "table" and type(cb.label) == "string" and cb.label ~= ""
            local hasIcon    = type(cb) == "table" and type(cb.icon) == "string" and cb.icon ~= ""
            local hasCommand = type(cb) == "table" and type(cb.slashCommand) == "string" and cb.slashCommand ~= ""
            if hasCommand and (hasLabel or hasIcon) then
                widgets[#widgets + 1] = createButton(bar, {
                    label   = cb.label,
                    tooltip = cb.slashCommand,
                    icon    = cb.icon,
                    macroText = cb.slashCommand,
                })
            end
        end
    end

    -- Layout: vertical for outside_left / inside_left, horizontal for
    -- inside_tabs.
    local horizontal = (position == "inside_tabs")
    local x, y = 0, 0
    for i = 1, #widgets do
        local btn = widgets[i]
        btn:ClearAllPoints()
        if horizontal then
            btn:SetPoint("LEFT", bar, "LEFT", x, 0)
            x = x + (btn:GetWidth() or 60) + buttonSpacing
        else
            btn:SetPoint("TOPLEFT", bar, "TOPLEFT", 0, y)
            y = y - ((btn:GetHeight() or 18) + buttonSpacing)
        end
        btn:Show()
    end
end

local function teardownBar(chatFrame)
    local bar = bars[chatFrame]
    if not bar then return end
    if bar._hasSecureCustomButtons and isInCombat() then return end
    bar:Hide()
    bar:ClearAllPoints()
    for _, child in ipairs({ bar:GetChildren() }) do
        child:Hide()
        child:SetParent(nil)
    end
end

local function hideBar(chatFrame)
    local bar = bars[chatFrame]
    if bar and bar._hasSecureCustomButtons and isInCombat() then return end
    if bar then bar:Hide() end
end

-- ---------------------------------------------------------------------------
-- Reconciliation
-- ---------------------------------------------------------------------------

local function isChatFrameVisible(chatFrame)
    if not chatFrame then return false end
    if chatFrame.IsShown and not chatFrame:IsShown() then return false end
    if chatFrame.IsVisible and not chatFrame:IsVisible() then return false end
    return true
end

local function reconcileFrame(chatFrame, frameID)
    if not chatFrame then return end
    if chatFrame.IsForbidden and chatFrame:IsForbidden() then return end

    local settings = I.GetSettings and I.GetSettings()
    if not (I.IsChatEnabled and I.IsChatEnabled(settings)) then
        teardownBar(chatFrame)
        return
    end

    local barsConfig = settings and settings.buttonBars
    local entry = barsConfig and barsConfig[frameID]

    if not (entry and entry.enabled) then
        teardownBar(chatFrame)
        return
    end

    if not isChatFrameVisible(chatFrame)
        and not ShouldSkipVisibilityTeardown(chatFrame, frameID) then
        teardownBar(chatFrame)
        return
    end

    if entry.hideInCombat and isInCombat() then
        hideBar(chatFrame)
        return
    end

    buildBar(chatFrame, frameID, entry)
end

reconcileAll = function()
    local n = _G.NUM_CHAT_WINDOWS or 10
    for i = 1, n do
        local f = _G["ChatFrame" .. i]
        if f then
            if ensureVisibilityHooks then ensureVisibilityHooks(f) end
            reconcileFrame(f, i)
        end
    end
end

do
    local queued = false
    scheduleReconcileAll = function()
        if queued then return end
        queued = true
        if C_Timer and C_Timer.After then
            C_Timer.After(0, function()
                queued = false
                reconcileAll()
            end)
        else
            queued = false
            reconcileAll()
        end
    end
end

ensureVisibilityHooks = function(chatFrame)
    if not chatFrame or visibilityHookedFrames[chatFrame] then return end
    if chatFrame.HookScript then
        chatFrame:HookScript("OnShow", scheduleReconcileAll)
        chatFrame:HookScript("OnHide", scheduleReconcileAll)
    end
    visibilityHookedFrames[chatFrame] = true
end

BB.ReconcileFrame = reconcileFrame
BB.ReconcileAll   = reconcileAll
BB.GetBuiltins    = function() return BUILTINS end
BB.GetBuiltinOrder = function() return BUILTIN_ORDER end

-- Settings-side helper: lazily initialise buttonBars[frameID] with all
-- built-ins set to visible. Used by the settings tile when the user first
-- enables a bar so they immediately see a sensible default.
function BB.InitFrameDefaults(frameID)
    local settings = I.GetSettings and I.GetSettings()
    if not settings then return nil end
    settings.buttonBars = settings.buttonBars or {}
    local entry = settings.buttonBars[frameID]
    if not entry then
        entry = {
            enabled = false,
            position = "outside_left",
            offsetX = 0,
            offsetY = 0,
            buttonSpacing = 2,
            hideInCombat = false,
            buttons = {},
            customButtons = {},
        }
        settings.buttonBars[frameID] = entry
    end
    if type(entry.offsetX) ~= "number" then entry.offsetX = 0 end
    if type(entry.offsetY) ~= "number" then entry.offsetY = 0 end
    if type(entry.buttonSpacing) ~= "number" then entry.buttonSpacing = 2 end
    if type(entry.hideInCombat) ~= "boolean" then entry.hideInCombat = false end
    if type(entry.buttons) ~= "table" then entry.buttons = {} end
    if type(entry.customButtons) ~= "table" then entry.customButtons = {} end
    if #entry.buttons == 0 then
        for _, id in ipairs(BUILTIN_ORDER) do
            entry.buttons[#entry.buttons + 1] = { id = id, visible = true }
        end
    end
    return entry
end

-- ---------------------------------------------------------------------------
-- ApplyEnabled
-- ---------------------------------------------------------------------------

function ApplyEnabled()
    reconcileAll()
end

-- Initial application. Defensive no-op if QUI.db isn't ready at file-load
-- time (GetSettings returns nil); PLAYER_LOGIN guarantees activation once
-- AceDB has been constructed in OnInitialize.
ApplyEnabled()

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
eventFrame:SetScript("OnEvent", function(self, event, name)
    if event == "ADDON_LOADED" and name == ADDON_NAME then
        ApplyEnabled()
    elseif event == "PLAYER_LOGIN" then
        ApplyEnabled()
    elseif event == "PLAYER_REGEN_DISABLED" or event == "PLAYER_REGEN_ENABLED" then
        scheduleReconcileAll()
    end
end)

-- Reposition on chat-frame layout changes.
if hooksecurefunc then
    if FCF_OpenNewWindow then
        hooksecurefunc("FCF_OpenNewWindow", function() scheduleReconcileAll() end)
    end
    if FCF_PopOutChat then
        hooksecurefunc("FCF_PopOutChat", function() scheduleReconcileAll() end)
    end
    if FCF_Tab_OnClick then
        hooksecurefunc("FCF_Tab_OnClick", function() scheduleReconcileAll() end)
    end
end

-- Register ApplyEnabled with the chat module's centralized after-refresh
-- hook list so it runs after every chat refresh (settings change, profile
-- switch, profile import, etc.).
table.insert(ns.QUI.Chat._afterRefresh, ApplyEnabled)

-- Register a re-skin with the "skinning" refresh group so a skin/accent/border
-- color change (which fires Registry:RefreshAll("skinning")) re-applies the
-- current colors to the live buttons. The chat _afterRefresh chain above only
-- runs on chat settings changes, so without this the buttons keep their old
-- color until the next chat refresh or a /reload.
if ns.Registry then
    ns.Registry:Register("chatButtonBarSkin", {
        refresh = reskinAll,
        priority = 50,
        group = "skinning",
        importCategories = { "skinning", "theme" },
    })
end
