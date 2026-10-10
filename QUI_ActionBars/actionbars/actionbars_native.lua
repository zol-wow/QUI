local ADDON_NAME, ns = ...
local env = ns.ActionBarsEnv
env.ADDON_NAME = ADDON_NAME
env.ns = ns
env.SetChunkEnv(1, env)

local hiddenButtons = setmetatable({}, { __mode = "k" })
local hiddenBars = {}
local hookedBars = setmetatable({}, { __mode = "k" })
local hookedButtons = setmetatable({}, { __mode = "k" })
local refreshQueued = false
local refreshing = false
local syncingVisibility = false
local nativeAnchorKeys = { pet = "petBar", stance = "stanceBar", microbar = "microMenu", bags = "bagBar" }

function SetNativeButtonLayoutVisible(button, visible)
    if visible then
        if hiddenButtons[button] then
            RegisterStateDriver(button, "visibility", "show")
            UnregisterStateDriver(button, "visibility")
            local parent = button.container
            if parent then
                RegisterStateDriver(parent, "visibility", "show")
                UnregisterStateDriver(parent, "visibility")
            end
            hiddenButtons[button] = nil
        end
    elseif not hiddenButtons[button] then
        RegisterStateDriver(button, "visibility", "hide")
        hiddenButtons[button] = true
    end
end

function IsNativeBarEnabled(barKey)
    local settings = GetBarSettings(barKey)
    local layoutKey = nativeAnchorKeys[barKey] or barKey
    local core = GetCore()
    local profile = core and core.db and core.db.profile
    local handles = profile and profile.layoutMode and profile.layoutMode.hiddenHandles
    return not (settings and settings.enabled == false) and not hiddenBars[barKey]
        and not (handles and handles[layoutKey])
        and not (_G.QUI_IsFrameHiddenByAnchor and _G.QUI_IsFrameHiddenByAnchor(layoutKey))
end

function RefreshNativeUtilityVisibility(barKey)
    local container = ActionBarsOwned.containers[barKey]
    if not container then return end
    if InCombatLockdown() then
        ActionBarsOwned.pendingRefresh = true
        return
    end
    local enabled = IsNativeBarEnabled(barKey)
    container:SetAttribute("qui-user-shown", enabled and true or false)
    RegisterStateDriver(container, "visibility", enabled
        and "[overridebar][vehicleui][possessbar][petbattle] hide; show" or "hide")
end

function SetNativeBarShown(container, shown)
    for barKey, frame in pairs(ActionBarsOwned.containers) do
        if frame == container then
            hiddenBars[barKey] = not shown
            if refreshing then
                if SKINNABLE_BAR_KEYS[barKey] then
                    LayoutNativeButtons(barKey)
                else
                    RefreshNativeUtilityVisibility(barKey)
                end
            else
                ActionBarsOwned:RefreshNativeBars()
            end
            return
        end
    end
end

local function QueueNativeRefresh()
    if refreshing then return end
    if InCombatLockdown() then
        ActionBarsOwned.pendingRefresh = true
        return
    end
    if refreshQueued then return end
    refreshQueued = true
    C_Timer.After(0, function()
        refreshQueued = false
        ActionBarsOwned:RefreshNativeBars()
    end)
end

local nativeContainers = {}

local function HideNativeDividers(frame)
    for _, key in ipairs({ "HorizontalDividersPool", "VerticalDividersPool" }) do
        local pool = frame[key]
        if pool then
            for divider in pool:EnumerateActive() do divider:SetAlpha(0) end
        end
    end
end

local function EnsureNativeBarContainer(barKey)
    local existing = ActionBarsOwned.containers[barKey]
    if existing then return existing end
    local frame = GetBarFrame(barKey)
    if not frame then return end
    local container = nativeContainers[barKey]
    if not container then
        container = CreateFrame("Frame", "QUI_ActionBar_" .. barKey, UIParent)
        nativeContainers[barKey] = container
        container:HookScript("OnHide", function()
            if not syncingVisibility then SetNativeBarShown(container, false) end
        end)
        container:HookScript("OnShow", function()
            if not syncingVisibility then SetNativeBarShown(container, true) end
        end)
    end
    container:SetSize(frame:GetWidth(), frame:GetHeight())
    if not Helpers.PinFrameToTargetAbsolute(container, "CENTER", frame, "CENTER", 0, 0) then return end
    ActionBarsOwned.containers[barKey] = container
    return container
end

function BuildNativeBar(barKey)
    if InCombatLockdown() then
        ActionBarsOwned.pendingRefresh = true
        return
    end
    if not SKINNABLE_BAR_KEYS[barKey] then return end
    local frame = GetBarFrame(barKey)
    local settings = GetEffectiveSettings(barKey)
    if not frame or not settings then return end
    local buttons = GetOriginalBlizzButtons(barKey)
    if #buttons == 0 then return end

    local container = EnsureNativeBarContainer(barKey)
    if not container then return end
    ActionBarsOwned.nativeButtons[barKey] = buttons

    local barNumber = tonumber(barKey:match("^bar(%d)$"))
    if barNumber and barNumber > 1 and Settings and Settings.GetSetting and Settings.GetValue and Settings.SetValue then
        local key = "PROXY_SHOW_ACTIONBAR_" .. barNumber
        local enabled = settings.enabled ~= false
        if Settings.GetSetting(key) and Settings.GetValue(key) ~= enabled then Settings.SetValue(key, enabled) end
    end

    for _, button in ipairs(buttons) do
        local state = GetFrameState(button)
        state.sk_sz = nil
        SkinButton(button, settings)
        UpdateButtonText(button, settings)
        if not hookedButtons[button] then
            hookedButtons[button] = true
            if button.UpdateHotkeys then hooksecurefunc(button, "UpdateHotkeys", QueueNativeRefresh) end
        end
    end
    LayoutNativeButtons(barKey)

    local anchorKey = nativeAnchorKeys[barKey] or barKey
    if _G.QUI_HasFrameAnchor and _G.QUI_HasFrameAnchor(anchorKey) and _G.QUI_ApplyFrameAnchor then
        local wasEnabled = IsNativeBarEnabled(barKey)
        _G.QUI_ApplyFrameAnchor(anchorKey)
        if wasEnabled ~= IsNativeBarEnabled(barKey) then LayoutNativeButtons(barKey) end
    end

    frame:SetScale(1)
    frame:SetSize(container:GetWidth(), container:GetHeight())
    frame:ClearAllPoints()
    frame:SetPoint("CENTER", container, "CENTER", 0, 0)
    frame:SetAlpha(container:GetAlpha())
    syncingVisibility = true
    container:SetShown(frame:IsShown() and IsNativeBarEnabled(barKey))
    syncingVisibility = false

    if barKey == "bar1" then
        local pageNumber = frame.ActionBarPageNumber
        if pageNumber then SetNativeButtonLayoutVisible(pageNumber, IsNativeBarEnabled(barKey) and not settings.hidePageArrow) end
        if pageNumber and not hookedBars[frame] then
            pageNumber:ClearAllPoints()
            pageNumber:SetPoint("BOTTOMRIGHT", container, "BOTTOMLEFT", -4, 9)
        end
        for _, key in ipairs({ "EndCaps", "BorderArt", "Background" }) do
            local art = frame[key]
            if art then art:SetAlpha(0) end
        end
        HideNativeDividers(frame)
        if not hookedBars[frame] and type(frame.UpdateDividers) == "function" then
            hooksecurefunc(frame, "UpdateDividers", HideNativeDividers)
        end
    end

    if not hookedBars[frame] then
        hookedBars[frame] = true
        for _, method in ipairs({ "UpdateGridLayout", "ApplySystemAnchor" }) do
            if type(frame[method]) == "function" then hooksecurefunc(frame, method, QueueNativeRefresh) end
        end
        frame:HookScript("OnShow", QueueNativeRefresh)
        frame:HookScript("OnHide", QueueNativeRefresh)
    end
end

function ActionBarsOwned:RefreshNativeBars()
    if not self.initialized or refreshing then return end
    if InCombatLockdown() then
        self.pendingRefresh = true
        return
    end
    refreshing = true
    self.pendingRefresh = nil
    InvalidateEffectiveSettingsCache()
    for _, barKey in ipairs(LINKED_OWNED_BAR_KEYS) do EnsureNativeBarContainer(barKey) end
    for _, barKey in ipairs(LINKED_OWNED_BAR_KEYS) do BuildNativeBar(barKey) end
    for _, barKey in ipairs({ "microbar", "bags" }) do BuildBar(barKey) end
    ApplyAllFlyoutDirections()
    self.pendingFlyoutDirection = nil
    self.pendingBagsReclaim = nil
    refreshing = false
    _G.QUI_RefreshActionBarFade()
end

function ActionBarsOwned:InitializeNativeBars()
    if self.initialized then return end
    self.initialized = true
    self:InitializeTooltipSuppression()
    local frame = CreateFrame("Frame")
    self.nativeEventFrame = frame
    for _, event in ipairs({
        "PLAYER_ENTERING_WORLD", "PLAYER_REGEN_ENABLED", "PLAYER_REGEN_DISABLED", "EDIT_MODE_LAYOUTS_UPDATED",
        "UPDATE_BINDINGS", "ACTIONBAR_SLOT_CHANGED", "ACTIONBAR_PAGE_CHANGED",
        "UPDATE_SHAPESHIFT_FORMS", "PET_BAR_UPDATE", "SETTINGS_LOADED", "PET_BATTLE_CLOSE",
    }) do frame:RegisterEvent(event) end
    frame:SetScript("OnEvent", function(_, event)
        if event == "PLAYER_REGEN_DISABLED" then
            _G.QUI_RefreshActionBarFade()
        else
            QueueNativeRefresh()
        end
    end)
    local core = GetCore()
    if core and core.RegisterEditModeEnter then
        core:RegisterEditModeEnter(OnEditModeEnter)
        core:RegisterEditModeExit(function()
            for _, barKey in ipairs(ALL_MANAGED_BAR_KEYS) do SaveContainerPosition(barKey) end
            self.editModeActive = false
            for _, overlay in pairs(self.editOverlays) do overlay:Hide() end
            self:RefreshNativeBars()
        end)
    end
    self:RefreshNativeBars()
end
