-- cooldownswipe.lua
-- Granular cooldown swipe control: Buff Duration / GCD / Cooldown swipes

local _, ns = ...
local Helpers = ns.Helpers

-- Default settings
local DEFAULTS = {
    showBuffSwipe = true,
    showBuffIconSwipe = false,
    showGCDSwipe = true,
    showCooldownSwipe = true,
    showRechargeEdge = true,
}

-- Get settings from AceDB via shared helper
local function GetSettings()
    return Helpers.GetModuleSettings("cooldownSwipe", DEFAULTS)
end

local function IsSecret(value)
    return Helpers.IsSecretValue and Helpers.IsSecretValue(value)
end

local function IsSafeNumber(value)
    return type(value) == "number" and not IsSecret(value)
end

-- Apply swipe/edge settings to one icon.
-- Intentionally avoids hooking Cooldown:SetCooldown to prevent tainting
-- Blizzard's secret cooldown/totem values in combat.
local function ApplySettingsToIcon(icon, settings)
    if not icon or not icon.Cooldown then return end
    if icon.IsForbidden and icon:IsForbidden() then return end

    settings = settings or GetSettings()

    local parent = icon:GetParent()
    local isBuffIconViewer = (parent == _G.BuffIconCooldownViewer)
    local showSwipe
    local auraActive = false
    local mode = nil -- "aura" | "gcd" | "cooldown"
    local auraInstanceID = icon.auraInstanceID

    -- Restrict aura classification to BuffIcon viewer only.
    -- Essential/Utility can transiently expose aura-like flags which causes
    -- false buff classification and hidden swipes when buff-swipe is disabled.
    if isBuffIconViewer then
        local wasSetFromAura = (type(icon.wasSetFromAura) == "boolean") and icon.wasSetFromAura or false
        local useAuraDisplayTime = (type(icon.cooldownUseAuraDisplayTime) == "boolean") and icon.cooldownUseAuraDisplayTime or false
        if wasSetFromAura or useAuraDisplayTime then
            auraActive = true
            mode = "aura"
        end

        -- Use auraInstanceID only when it is safely readable.
        if not auraActive and auraInstanceID ~= nil then
            if IsSafeNumber(auraInstanceID) then
                if auraInstanceID > 0 then
                    auraActive = true
                    mode = "aura"
                end
            else
                local auraNumber = Helpers.SafeToNumber and Helpers.SafeToNumber(auraInstanceID, nil) or nil
                if IsSafeNumber(auraNumber) and auraNumber > 0 then
                    auraActive = true
                    mode = "aura"
                end
            end
        end
    end

    -- Distinguish short GCD swipes from normal cooldown swipes without CooldownFlash.
    -- CooldownFlash is intentionally hidden by CDM skinning, so it cannot be used here.
    local isGCD = false
    if not auraActive then
        local durationRaw = icon.cooldownDuration
        local duration = nil
        if IsSafeNumber(durationRaw) then
            duration = durationRaw
        elseif Helpers.SafeToNumber then
            duration = Helpers.SafeToNumber(durationRaw, nil)
        end
        if IsSafeNumber(duration) and duration > 0 and duration <= 2.5 then
            isGCD = true
            mode = "gcd"
        end
    end

    -- Use explicit Blizzard flags for cooldowns when available.
    if not mode then
        local wasSetFromCooldown = (type(icon.wasSetFromCooldown) == "boolean") and icon.wasSetFromCooldown or false
        local wasSetFromCharges = (type(icon.wasSetFromCharges) == "boolean") and icon.wasSetFromCharges or false
        if wasSetFromCooldown or wasSetFromCharges then
            mode = "cooldown"
        end
    end

    -- Stabilize behavior when Blizzard data is temporarily unavailable.
    if not mode then
        mode = icon._QUI_LastSwipeMode or "cooldown"
    end
    icon._QUI_LastSwipeMode = mode

    if mode == "aura" then
        if parent == _G.BuffIconCooldownViewer then
            showSwipe = settings.showBuffIconSwipe
        else
            showSwipe = settings.showBuffSwipe
        end
    elseif mode == "gcd" then
        showSwipe = settings.showGCDSwipe
    else
        showSwipe = settings.showCooldownSwipe
    end

    -- Avoid reapplying unchanged values every pulse; frequent redundant writes can
    -- produce subtle visual jitter on the radial edge animation.
    if icon._QUI_LastDrawSwipe ~= showSwipe then
        icon._QUI_LastDrawSwipe = showSwipe
        icon.Cooldown:SetDrawSwipe(showSwipe)
    end

    local drawEdge
    if mode == "aura" then
        drawEdge = showSwipe
    else
        drawEdge = settings.showRechargeEdge
    end
    if icon._QUI_LastDrawEdge ~= drawEdge then
        icon._QUI_LastDrawEdge = drawEdge
        icon.Cooldown:SetDrawEdge(drawEdge)
    end
end

-- Process all icons in a viewer
local function ProcessViewer(viewer, settings)
    if not viewer then return end

    local children = {viewer:GetChildren()}

    settings = settings or GetSettings()
    for _, icon in ipairs(children) do
        if icon.Cooldown then
            ApplySettingsToIcon(icon, settings)
        end
    end
end

-- Apply settings to all CDM viewers
local function ApplyAllSettings()
    local settings = GetSettings()
    local viewers = {
        _G.EssentialCooldownViewer,
        _G.UtilityCooldownViewer,
        _G.BuffIconCooldownViewer,
    }

    for _, viewer in ipairs(viewers) do
        ProcessViewer(viewer, settings)

        -- Hook Layout to catch new icons
        if viewer and viewer.Layout and not viewer._QUI_LayoutHooked then
            viewer._QUI_LayoutHooked = true
            hooksecurefunc(viewer, "Layout", function()
                C_Timer.After(0.15, function()  -- 150ms debounce for CPU efficiency
                    ProcessViewer(viewer, GetSettings())
                end)
            end)
        end
    end
end

-- Queue refreshes to break secure event taint chains (notably PLAYER_TOTEM_UPDATE).
local queuedRefresh = false
local pendingCombatRefresh = false

local function QueueApplyAllSettings(delaySeconds)
    if queuedRefresh then return end
    queuedRefresh = true
    C_Timer.After(delaySeconds or 0, function()
        queuedRefresh = false
        if InCombatLockdown() then
            pendingCombatRefresh = true
            return
        end
        pendingCombatRefresh = false
        ApplyAllSettings()
    end)
end

-- Event-driven refresh for cooldown state changes without SetCooldown hooks.
local refreshEventFrame = CreateFrame("Frame")
refreshEventFrame:RegisterEvent("SPELL_UPDATE_COOLDOWN")
refreshEventFrame:RegisterEvent("ACTIONBAR_UPDATE_COOLDOWN")
refreshEventFrame:RegisterEvent("ACTIONBAR_SLOT_CHANGED")
refreshEventFrame:RegisterEvent("BAG_UPDATE_COOLDOWN")
refreshEventFrame:RegisterEvent("PLAYER_TOTEM_UPDATE")
refreshEventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
refreshEventFrame:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_REGEN_ENABLED" then
        if pendingCombatRefresh then
            QueueApplyAllSettings(0.05)
        end
        return
    end

    if event == "PLAYER_TOTEM_UPDATE" then
        -- BUG-010: break secure totem update context to avoid taint propagation
        QueueApplyAllSettings(0)
        return
    end

    QueueApplyAllSettings(0)
end)

-- Keep swipe state responsive while viewers are visible.
local pulseFrame = CreateFrame("Frame")
pulseFrame:SetScript("OnUpdate", function(self, elapsed)
    self._quiElapsed = (self._quiElapsed or 0) + elapsed
    if self._quiElapsed < 0.12 then return end
    self._quiElapsed = 0

    local essential = _G.EssentialCooldownViewer
    local utility = _G.UtilityCooldownViewer
    local buff = _G.BuffIconCooldownViewer
    local anyVisible = (essential and essential:IsShown())
        or (utility and utility:IsShown())
        or (buff and buff:IsShown())
    if anyVisible then
        if InCombatLockdown() then
            pendingCombatRefresh = true
            return
        end
        QueueApplyAllSettings(0)
    end
end)

-- Initialize on addon load
local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")

eventFrame:SetScript("OnEvent", function(self, event, arg)
    if event == "ADDON_LOADED" and arg == "Blizzard_CooldownManager" then
        C_Timer.After(0.5, ApplyAllSettings)
        C_Timer.After(1.5, ApplyAllSettings)  -- Apply again to catch late icons
    elseif event == "PLAYER_ENTERING_WORLD" then
        C_Timer.After(0.5, ApplyAllSettings)
        C_Timer.After(1.5, ApplyAllSettings)  -- Apply again to catch late icons
    end
end)

-- Export to QUI namespace
QUI.CooldownSwipe = {
    Apply = ApplyAllSettings,
    GetSettings = GetSettings,
}

-- Global function for config panel to call
_G.QUI_RefreshCooldownSwipe = function()
    ApplyAllSettings()
end
