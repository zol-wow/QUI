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
    -- Overlay color: shown when spell/buff is ACTIVE (aura duration)
    overlayColorMode = "default",  -- "default" | "class" | "custom"
    overlayColor = {1, 1, 1, 1},   -- white (matches color picker default)
    -- Swipe color: shown when spell is ON COOLDOWN (radial darkening)
    swipeColorMode = "default",
    swipeColor = {1, 1, 1, 1},
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

-- Get the player's class color at 80% alpha
local function GetClassColor()
    local _, class = UnitClass("player")
    local classColor = RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
    if classColor then
        return classColor.r, classColor.g, classColor.b, 0.8
    end
    return 1, 1, 1, 0.8
end

-- Resolve r,g,b,a for a given mode + stored color table; nil = leave Blizzard default.
-- Falls back to white when mode is "custom" but no color has been picked yet.
local function ResolveColor(mode, colorTable)
    if mode == "class" then
        return GetClassColor()
    elseif mode == "accent" then
        local QUI = _G.QUI
        if QUI and QUI.GetSkinColor then
            local r, g, b, a = QUI:GetSkinColor()
            return r, g, b, 0.8
        end
        return 0.2, 1.0, 0.6, 0.8  -- fallback mint
    elseif mode == "custom" then
        local c = colorTable or {}
        return c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1
    end
    return nil  -- "default": don't override
end

-- Returns overlay and swipe colors for Essential/Utility icons (nil = Blizzard default).
--   overlayR..A  →  active/aura state (buff duration showing)
--   swipeR..A    →  cooldown state (radial darkening)
local function GetIconColors(viewer, settings)
    if viewer ~= _G.EssentialCooldownViewer and viewer ~= _G.UtilityCooldownViewer then
        return nil, nil, nil, nil, nil, nil, nil, nil
    end
    local oR, oG, oB, oA = ResolveColor(settings.overlayColorMode or "default", settings.overlayColor)
    local sR, sG, sB, sA = ResolveColor(settings.swipeColorMode  or "default", settings.swipeColor)
    return oR, oG, oB, oA, sR, sG, sB, sA
end

-- Apply the correct swipe color to one icon based on its wasSetFromAura state.
-- Called from both the SetCooldown hook (reactive) and the pulse (on settings change).
local function ApplyColorToIcon(icon, settings)
    settings = settings or GetSettings()
    local parent = icon:GetParent()
    local oR, oG, oB, oA, sR, sG, sB, sA = GetIconColors(parent, settings)
    if not oR and not sR then return end  -- both "default", nothing to override

    local isActive = type(icon.wasSetFromAura) == "boolean" and icon.wasSetFromAura
    if isActive then
        if oR then icon.Cooldown:SetSwipeColor(oR, oG, oB, oA) end
    else
        if sR then icon.Cooldown:SetSwipeColor(sR, sG, sB, sA) end
    end
end

-- Hook icon.Cooldown:SetCooldown so our color fires after Blizzard sets wasSetFromAura
-- and its own color in the same update. Safe: we don't read the secret arguments.
local function HookIconCooldown(icon)
    if icon._QUI_CDColorHooked then return end
    icon._QUI_CDColorHooked = true
    hooksecurefunc(icon.Cooldown, "SetCooldown", function()
        ApplyColorToIcon(icon)
    end)
end

-- Apply swipe/edge/color settings to one icon.
-- Swipe visibility avoids hooking SetCooldown to prevent tainting secret values.
-- Color overrides use a SetCooldown hook (safe: we don't read the secret arguments).
local EnsureViewerVisibilityHooks

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

    -- Hook SetCooldown to apply overlay/swipe color at the right moment
    -- (after Blizzard sets wasSetFromAura and its own color in the same update).
    -- Also apply immediately so settings changes take effect without waiting.
    HookIconCooldown(icon)
    ApplyColorToIcon(icon, settings)
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
    EnsureViewerVisibilityHooks()
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
-- Use ticker (0.12s) instead of OnUpdate to avoid per-frame CPU cost (~60-120 invocations/s -> ~8/s)
local PULSE_INTERVAL = 0.12
local pulseTicker = nil
local VIEWER_NAMES = {
    "EssentialCooldownViewer",
    "UtilityCooldownViewer",
    "BuffIconCooldownViewer",
}
local StartPulseTicker

local function IsAnyViewerVisible()
    for _, viewerName in ipairs(VIEWER_NAMES) do
        local viewer = _G[viewerName]
        if viewer and viewer:IsShown() then
            return true
        end
    end
    return false
end

local function StopPulseTicker()
    if pulseTicker then
        pulseTicker:Cancel()
        pulseTicker = nil
    end
end

EnsureViewerVisibilityHooks = function()
    for _, viewerName in ipairs(VIEWER_NAMES) do
        local viewer = _G[viewerName]
        if viewer and not viewer._QUI_SwipePulseHooked then
            viewer._QUI_SwipePulseHooked = true

            viewer:HookScript("OnShow", function()
                if StartPulseTicker then
                    StartPulseTicker()
                end
                QueueApplyAllSettings(0)
            end)

            viewer:HookScript("OnHide", function()
                if not IsAnyViewerVisible() then
                    StopPulseTicker()
                end
            end)
        end
    end
end

StartPulseTicker = function()
    if pulseTicker then return end
    pulseTicker = C_Timer.NewTicker(PULSE_INTERVAL, function()
        if not IsAnyViewerVisible() then
            StopPulseTicker()
            return
        end

        if InCombatLockdown() then
            pendingCombatRefresh = true
            return
        end

        QueueApplyAllSettings(0)
    end)
end
-- Start ticker immediately if viewers are already visible.
EnsureViewerVisibilityHooks()
if IsAnyViewerVisible() then
    StartPulseTicker()
end

-- Initialize on addon load
local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")

eventFrame:SetScript("OnEvent", function(self, event, arg)
    if event == "ADDON_LOADED" and arg == "Blizzard_CooldownManager" then
        EnsureViewerVisibilityHooks()
        if IsAnyViewerVisible() then
            StartPulseTicker()
        end
        C_Timer.After(0.5, ApplyAllSettings)
        C_Timer.After(1.5, ApplyAllSettings)  -- Apply again to catch late icons
        C_Timer.After(0.5, function()
            EnsureViewerVisibilityHooks()
            if IsAnyViewerVisible() then
                StartPulseTicker()
            end
        end)
        C_Timer.After(1.5, EnsureViewerVisibilityHooks)
    elseif event == "PLAYER_ENTERING_WORLD" then
        EnsureViewerVisibilityHooks()
        if IsAnyViewerVisible() then
            StartPulseTicker()
        end
        C_Timer.After(0.5, ApplyAllSettings)
        C_Timer.After(1.5, ApplyAllSettings)  -- Apply again to catch late icons
        C_Timer.After(0.5, function()
            EnsureViewerVisibilityHooks()
            if IsAnyViewerVisible() then
                StartPulseTicker()
            end
        end)
        C_Timer.After(1.5, EnsureViewerVisibilityHooks)
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
