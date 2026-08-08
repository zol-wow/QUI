local ADDON_NAME, ns = ...

local I = assert(ns.QUI.Chat and ns.QUI.Chat._internals,
    "QUI Chat: button_bar.lua loaded before chat.lua. Check chat.xml — chat.lua must precede button_bar.lua.")

local Helpers  = ns.Helpers

ns.QUI.Chat.ButtonBar = ns.QUI.Chat.ButtonBar or {}
local BB = ns.QUI.Chat.ButtonBar

local ApplyEnabled
local reconcileAll
local scheduleReconcileAll
local ensureVisibilityHooks

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

local BUILTIN_ORDER = {
    "qui_options", "qui_layout", "qui_keybind", "qui_cdm",
    "social", "guild", "reload",
}

local function applySkin(button)
    local sr, sg, sb, sa, bgr, bgg, bgb, bga = Helpers.GetSkinColors()
    ns.SkinBase.ApplyFullBackdrop(button, sr, sg, sb, sa, bgr, bgg, bgb, bga)
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

local bars = setmetatable({}, { __mode = "k" })
local visibilityHookedFrames = setmetatable({}, { __mode = "k" })

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

local RENAMED_BUILTIN_IDS = {
    qui_options = "qui_options",
    qui_layout  = "qui_layout",
    qui_keybind = "qui_keybind",
    qui_cdm     = "qui_cdm",
}

local function isCustomItem(item)
    if type(item) ~= "table" then return false end
    if item.kind == "custom" then return true end
    if item.kind == "builtin" then return false end
    return item.id == nil and item.slashCommand ~= nil
end
BB.IsCustomItem = isCustomItem

local function normalizeEntry(entry)
    if type(entry) ~= "table" then return entry end
    if type(entry.items) ~= "table" then entry.items = {} end

    local legacyBuiltins = entry.buttons
    if type(legacyBuiltins) == "table" then
        for i = 1, #legacyBuiltins do
            local b = legacyBuiltins[i]
            if type(b) == "table" and type(b.id) == "string" then
                entry.items[#entry.items + 1] = {
                    kind = "builtin", id = b.id, visible = b.visible and true or false,
                }
            end
        end
    end
    if legacyBuiltins ~= nil then entry.buttons = nil end

    local legacyCustom = entry.customButtons
    if type(legacyCustom) == "table" then
        for i = 1, #legacyCustom do
            local c = legacyCustom[i]
            if type(c) == "table" then
                entry.items[#entry.items + 1] = {
                    kind = "custom",
                    label       = type(c.label) == "string" and c.label or "",
                    slashCommand = type(c.slashCommand) == "string" and c.slashCommand or "",
                    icon        = type(c.icon) == "string" and c.icon or "",
                    visible     = c.visible ~= false,
                }
            end
        end
    end
    if legacyCustom ~= nil then entry.customButtons = nil end

    for i = #entry.items, 1, -1 do
        local item = entry.items[i]
        if type(item) ~= "table" then
            table.remove(entry.items, i)
        elseif isCustomItem(item) then
            item.visible = item.visible ~= false
        else
            local renamed = RENAMED_BUILTIN_IDS[item.id]
            if renamed then item.id = renamed end
            if BUILTINS[item.id] then
                item.kind = "builtin"
            else
                table.remove(entry.items, i)
            end
        end
    end

    return entry
end
BB.NormalizeEntry = normalizeEntry

local function hasCustomMacroButtons(config)
    if type(config) ~= "table" or type(config.items) ~= "table" then
        return false
    end

    for i = 1, #config.items do
        local item = config.items[i]
        if isCustomItem(item) and normalizeMacroText(item.slashCommand) then
            return true
        end
    end

    return false
end

local function createButton(parent, def, customAction)
    local hasIcon = type(def.icon) == "string" and def.icon ~= ""
    local macroText = normalizeMacroText(def.macroText)
    local template = macroText and "SecureActionButtonTemplate,BackdropTemplate" or "BackdropTemplate"
    local btn = CreateFrame("Button", nil, parent, template)

    if macroText then
        btn:RegisterForClicks("AnyUp", "AnyDown")
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

local function acquireButton(bar, def, key, used)
    local cache = bar._quiButtonCache
    if not cache then
        cache = {}
        bar._quiButtonCache = cache
    end
    local list = cache[key]
    if not list then
        list = {}
        cache[key] = list
    end
    local n = (used[key] or 0) + 1
    used[key] = n
    local btn = list[n]
    if btn then
        btn:SetParent(bar)
        applySkin(btn)
    else
        btn = createButton(bar, def)
        list[n] = btn
    end
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
BB._GetBarAnchorFrame = GetBarAnchorFrame

local function ShouldSkipVisibilityTeardown(chatFrame, frameID)
    return GetBarAnchorFrame(chatFrame, frameID) ~= chatFrame
end
BB._ShouldSkipVisibilityTeardown = ShouldSkipVisibilityTeardown

function BB.Reapply()
    if ApplyEnabled then
        ApplyEnabled()
    end
end

local function buildBar(chatFrame, frameID, config)
    normalizeEntry(config)
    local hasSecureButtons = hasCustomMacroButtons(config)
    if hasSecureButtons and isInCombat() then
        return
    end

    local bar = bars[chatFrame]
    if bar then
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

    local widgets = {}
    local used = {}
    if type(config.items) == "table" then
        for i = 1, #config.items do
            local item = config.items[i]
            if type(item) == "table" then
                if isCustomItem(item) then
                    local hasLabel   = type(item.label) == "string" and item.label ~= ""
                    local hasIcon    = type(item.icon) == "string" and item.icon ~= ""
                    local hasCommand = type(item.slashCommand) == "string" and item.slashCommand ~= ""
                    if item.visible ~= false and hasCommand and (hasLabel or hasIcon) then
                        local key = "c\1" .. (item.label or "") .. "\1" .. (item.icon or "") .. "\1" .. item.slashCommand
                        widgets[#widgets + 1] = acquireButton(bar, {
                            label     = item.label,
                            tooltip   = item.slashCommand,
                            icon      = item.icon,
                            macroText = item.slashCommand,
                        }, key, used)
                    end
                elseif item.visible and BUILTINS[item.id] then
                    widgets[#widgets + 1] = acquireButton(bar, BUILTINS[item.id], "b\1" .. item.id, used)
                end
            end
        end
    end

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
    normalizeEntry(entry)

    local fresh = (#entry.items == 0)
    local seen = {}
    for i = 1, #entry.items do
        local item = entry.items[i]
        if type(item) == "table" and not isCustomItem(item) and type(item.id) == "string" then
            seen[item.id] = true
        end
    end
    for _, id in ipairs(BUILTIN_ORDER) do
        if not seen[id] then
            entry.items[#entry.items + 1] = { kind = "builtin", id = id, visible = fresh }
        end
    end
    return entry
end

function BB.MoveItem(frameID, index, delta)
    local settings = I.GetSettings and I.GetSettings()
    local entry = settings and settings.buttonBars and settings.buttonBars[frameID]
    if type(entry) ~= "table" or type(entry.items) ~= "table" then return nil end

    local target = index + delta
    if index < 1 or index > #entry.items then return nil end
    if target < 1 or target > #entry.items then return nil end

    local item = table.remove(entry.items, index)
    table.insert(entry.items, target, item)
    return target
end

function ApplyEnabled()
    reconcileAll()
end

ApplyEnabled()

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("EDIT_MODE_LAYOUTS_UPDATED")
eventFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
eventFrame:SetScript("OnEvent", function(self, event, name)
    if event == "ADDON_LOADED" and name == ADDON_NAME then
        ApplyEnabled()
    elseif event == "PLAYER_LOGIN" then
        ApplyEnabled()
    elseif event == "PLAYER_ENTERING_WORLD" or event == "EDIT_MODE_LAYOUTS_UPDATED" then
        scheduleReconcileAll()
    elseif event == "PLAYER_REGEN_DISABLED" or event == "PLAYER_REGEN_ENABLED" then
        scheduleReconcileAll()
    end
end)

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

table.insert(ns.QUI.Chat._afterRefresh, ApplyEnabled)

if ns.Registry then
    ns.Registry:Register("chatButtonBarSkin", {
        refresh = reskinAll,
        priority = 50,
        group = "skinning",
        importCategories = { "skinning", "theme" },
    })
end
