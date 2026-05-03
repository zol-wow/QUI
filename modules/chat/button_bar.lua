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
        label = "QUI",
        action = function()
            if _G.QUI and _G.QUI.GUI then
                _G.QUI.GUI:Toggle()
            else
                print("|cFF56D1FFQUI:|r GUI not loaded yet. Try again in a moment.")
            end
        end,
        tooltip = "Open QUI options",
    },
    qui_layout = {
        label = "Layout",
        action = function()
            if _G.QUI_ToggleLayoutMode then
                _G.QUI_ToggleLayoutMode()
            else
                print("|cff60A5FAQUI:|r Layout Mode not loaded yet.")
            end
        end,
        tooltip = "Toggle Layout Mode",
    },
    qui_keybind = {
        label = "KB",
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
        tooltip = "Toggle keybind mode",
    },
    qui_cdm = {
        label = "CDM",
        action = function()
            if _G.CooldownViewerSettings then
                _G.CooldownViewerSettings:SetShown(not _G.CooldownViewerSettings:IsShown())
            else
                print("|cff60A5FAQUI:|r Cooldown Settings not available. Enable CDM first.")
            end
        end,
        tooltip = "Open Cooldown Manager settings",
    },
    social = {
        label = "Friends",
        action = function()
            if type(_G.ToggleFriendsFrame) == "function" then
                _G.ToggleFriendsFrame()
            end
        end,
        tooltip = "Toggle Friends list",
    },
    guild = {
        label = "Guild",
        action = function()
            if type(_G.ToggleGuildFrame) == "function" then
                _G.ToggleGuildFrame()
            end
        end,
        tooltip = "Toggle Guild frame",
    },
    reload = {
        label = "Reload",
        action = function()
            if type(_G.ReloadUI) == "function" then
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
    -- ApplyFullBackdrop stores the canonical base colors on the frame as
    -- _quiBgR/G/B/A and _quiBorderR/G/B/A; the hover hooks read from those
    -- so a live theme refresh propagates without re-registering the hooks.

    if button._quiHoverHooked then return end
    button._quiHoverHooked = true

    button:HookScript("OnEnter", function(self)
        if not self._quiBgR then return end
        self:SetBackdropColor(
            math.min(self._quiBgR + 0.30, 1),
            math.min(self._quiBgG + 0.30, 1),
            math.min(self._quiBgB + 0.30, 1),
            self._quiBgA)
        self:SetBackdropBorderColor(
            math.min(self._quiBorderR * 1.6, 1),
            math.min(self._quiBorderG * 1.6, 1),
            math.min(self._quiBorderB * 1.6, 1),
            self._quiBorderA)
    end)
    button:HookScript("OnLeave", function(self)
        if not self._quiBgR then return end
        self:SetBackdropColor(self._quiBgR, self._quiBgG, self._quiBgB, self._quiBgA)
        self:SetBackdropBorderColor(self._quiBorderR, self._quiBorderG, self._quiBorderB, self._quiBorderA)
    end)
end

-- ---------------------------------------------------------------------------
-- Per-frame bar state
-- ---------------------------------------------------------------------------

-- Map: chatFrame -> bar Frame. Weak-keyed so a torn-down chat frame doesn't
-- pin the bar in memory.
local bars = setmetatable({}, { __mode = "k" })
local visibilityHookedFrames = setmetatable({}, { __mode = "k" })

-- ---------------------------------------------------------------------------
-- Bar creation / layout
-- ---------------------------------------------------------------------------

local function createButton(parent, def, customAction)
    local hasIcon = type(def.icon) == "string" and def.icon ~= ""
    local btn = CreateFrame("Button", nil, parent, "BackdropTemplate")

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
        fs:SetFont(fontPath, 11, "OUTLINE")
        fs:SetTextColor(0.9, 0.9, 0.9, 1)
        fs:SetPoint("CENTER")
        fs:SetText(def.label or "?")
        btn:SetFontString(fs)
    end

    btn.tooltipText = def.tooltip or def.label
    btn:SetScript("OnClick", customAction or def.action or function() end)
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

-- Execute a user-defined slash command. RunMacroText is Blizzard's canonical
-- programmatic entry point for macro/typed commands — slash commands, chat
-- messages, emotes — and is exactly what one line of an in-game macro does.
-- We previously routed through ChatFrame_OpenChat + the editbox send path,
-- but the 12.0 chat-send chain no longer dispatches from that programmatic
-- entry: the editbox would populate visibly but stay unsent until the user
-- pressed Enter manually. RunMacroText sends synchronously with no editbox
-- detour. Secure-only commands (e.g. /cast) still won't run because the
-- click context from a non-secure addon button is tainted regardless.
local function runSlashCommand(text)
    if type(text) ~= "string" or text == "" then return end
    if type(_G.RunMacroText) == "function" then
        _G.RunMacroText(text)
    end
end

local function buildBar(chatFrame, frameID, config)
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

    bar:ClearAllPoints()

    local ox = tonumber(config.offsetX) or 0
    local oy = tonumber(config.offsetY) or 0
    local buttonSpacing = tonumber(config.buttonSpacing) or 2
    if buttonSpacing < 0 then buttonSpacing = 0 end

    local position = config.position or "outside_left"
    if position == "outside_left" then
        bar:SetSize(70, math.max(chatFrame:GetHeight() or 100, 20))
        bar:SetPoint("TOPRIGHT",    chatFrame, "TOPLEFT",    ox, oy)
        bar:SetPoint("BOTTOMRIGHT", chatFrame, "BOTTOMLEFT", ox, oy)
    elseif position == "outside_right" then
        bar:SetSize(70, math.max(chatFrame:GetHeight() or 100, 20))
        bar:SetPoint("TOPLEFT",    chatFrame, "TOPRIGHT",    ox, oy)
        bar:SetPoint("BOTTOMLEFT", chatFrame, "BOTTOMRIGHT", ox, oy)
    elseif position == "inside_left" then
        bar:SetSize(70, math.max((chatFrame:GetHeight() or 100) - 24, 20))
        bar:SetPoint("TOPLEFT",    chatFrame, "TOPLEFT",    4 + ox, -24 + oy)
        bar:SetPoint("BOTTOMLEFT", chatFrame, "BOTTOMLEFT", 4 + ox,   4 + oy)
    elseif position == "inside_right" then
        bar:SetSize(70, math.max((chatFrame:GetHeight() or 100) - 24, 20))
        bar:SetPoint("TOPRIGHT",    chatFrame, "TOPRIGHT",    -4 + ox, -24 + oy)
        bar:SetPoint("BOTTOMRIGHT", chatFrame, "BOTTOMRIGHT", -4 + ox,   4 + oy)
    elseif position == "inside_tabs" then
        bar:SetSize(180, 22)
        -- Anchor to the configured frame's own tab. Visibility reconciliation
        -- below keeps inactive docked frames from leaving their bars behind.
        local tab = _G["ChatFrame" .. tostring(frameID) .. "Tab"]
        if tab and tab:IsShown() then
            bar:SetPoint("LEFT", tab, "RIGHT", 8 + ox, oy)
        else
            bar:SetPoint("TOPLEFT", chatFrame, "TOPLEFT", ox, 8 + oy)
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
                local cmd = cb.slashCommand
                local action = function() runSlashCommand(cmd) end
                widgets[#widgets + 1] = createButton(bar, {
                    label   = cb.label,
                    tooltip = cb.slashCommand,
                    icon    = cb.icon,
                }, action)
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
    bar:Hide()
    bar:ClearAllPoints()
    for _, child in ipairs({ bar:GetChildren() }) do
        child:Hide()
        child:SetParent(nil)
    end
end

local function hideBar(chatFrame)
    local bar = bars[chatFrame]
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

local function isInCombat()
    return type(InCombatLockdown) == "function" and InCombatLockdown()
end

local function reconcileFrame(chatFrame, frameID)
    if not chatFrame then return end
    if chatFrame.IsForbidden and chatFrame:IsForbidden() then return end

    local settings = I.GetSettings and I.GetSettings()
    local barsConfig = settings and settings.buttonBars
    local entry = barsConfig and barsConfig[frameID]

    if not (entry and entry.enabled) then
        teardownBar(chatFrame)
        return
    end

    if not isChatFrameVisible(chatFrame) then
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
