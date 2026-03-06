-- cooldownswipe.lua
-- Granular cooldown swipe control for addon-owned CDM icons.
-- Simplified: operates directly on QUI's owned icon frames.
-- No hooks, no pulse tickers, no deferred operations needed.

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
    overlayColorMode = "default",  -- "default" | "class" | "accent" | "custom"
    overlayColor = {1, 1, 1, 1},
    -- Swipe color: shown when spell is ON COOLDOWN (radial darkening)
    swipeColorMode = "default",
    swipeColor = {1, 1, 1, 1},
}

-- Get settings from AceDB via shared helper
local function GetSettings()
    return Helpers.GetModuleSettings("cooldownSwipe", DEFAULTS)
end

---------------------------------------------------------------------------
-- COLOR RESOLUTION
---------------------------------------------------------------------------
local function GetClassColor()
    local _, class = UnitClass("player")
    local classColor = RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
    if classColor then
        return classColor.r, classColor.g, classColor.b, 0.8
    end
    return 1, 1, 1, 0.8
end

-- Resolve r,g,b,a for a given mode + stored color table; nil = leave default.
local function ResolveColor(mode, colorTable)
    if mode == "class" then
        return GetClassColor()
    elseif mode == "accent" then
        local QUI = _G.QUI
        if QUI and QUI.GetSkinColor then
            local r, g, b = QUI:GetSkinColor()
            return r, g, b, 0.8
        end
        return 0.2, 1.0, 0.6, 0.8  -- fallback mint
    elseif mode == "custom" then
        local c = colorTable or {}
        return c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1
    end
    return nil  -- "default": don't override
end

-- CDM default swipe color (dark overlay for cooldowns)
local CDM_DEFAULT_R, CDM_DEFAULT_G, CDM_DEFAULT_B, CDM_DEFAULT_A = 0, 0, 0, 0.8
-- Blizzard default buff/aura overlay color (yellow)
local BLIZZ_BUFF_R, BLIZZ_BUFF_G, BLIZZ_BUFF_B, BLIZZ_BUFF_A = 0.93, 0.77, 0.0, 0.45

---------------------------------------------------------------------------
-- APPLY SWIPE TO A SINGLE ICON
-- Classification uses icon._auraActive (from hook) and icon._isOnGCD (from API)
-- (set by cdm_icons.lua during cooldown updates).
---------------------------------------------------------------------------
local function ApplySwipeToIcon(icon, settings)
    if not icon or not icon.Cooldown or not icon._spellEntry then return end
    settings = settings or GetSettings()

    local entry = icon._spellEntry
    local isBuffIcon = (entry.viewerType == "buff")

    -- Classify: aura, gcd, or cooldown
    -- Buff viewer children are always auras, but cooldownInfo doesn't flag them
    local mode
    if isBuffIcon or (entry.isAura and icon._auraActive) then
        mode = "aura"
    elseif icon._isOnGCD then
        mode = "gcd"
    else
        mode = "cooldown"
    end

    -- Swipe visibility
    local showSwipe
    if mode == "aura" then
        if isBuffIcon then
            showSwipe = settings.showBuffIconSwipe
        else
            showSwipe = settings.showBuffSwipe
        end
    elseif mode == "gcd" then
        showSwipe = settings.showGCDSwipe
    else
        showSwipe = settings.showCooldownSwipe
    end

    icon.Cooldown:SetDrawSwipe(showSwipe)

    -- Edge visibility
    if mode == "aura" then
        icon.Cooldown:SetDrawEdge(showSwipe)
    else
        icon.Cooldown:SetDrawEdge(settings.showRechargeEdge)
    end

    -- Apply color and texture based on mode
    if mode == "aura" then
        local oR, oG, oB, oA = ResolveColor(settings.overlayColorMode or "default", settings.overlayColor)
        if not oR then oR, oG, oB, oA = BLIZZ_BUFF_R, BLIZZ_BUFF_G, BLIZZ_BUFF_B, BLIZZ_BUFF_A end
        icon.Cooldown:SetSwipeTexture("Interface\\Buttons\\WHITE8X8")
        icon.Cooldown:SetSwipeColor(oR, oG, oB, oA)
    else
        local sR, sG, sB, sA = ResolveColor(settings.swipeColorMode or "default", settings.swipeColor)
        if not sR then sR, sG, sB, sA = CDM_DEFAULT_R, CDM_DEFAULT_G, CDM_DEFAULT_B, CDM_DEFAULT_A end
        icon.Cooldown:SetSwipeColor(sR, sG, sB, sA)
    end
end

---------------------------------------------------------------------------
-- APPLY SWIPE TO A BLIZZARD BUFF VIEWER CHILD
-- These children have .Icon and .Cooldown but no ._spellEntry.
-- Buff viewer children are always auras, so classification is fixed.
---------------------------------------------------------------------------
local function ApplySwipeToBuffChild(icon, settings)
    if not icon or not icon.Cooldown then return end
    settings = settings or GetSettings()

    -- Buff viewer children are always auras in the buff viewer
    local showSwipe = settings.showBuffIconSwipe

    icon.Cooldown:SetDrawSwipe(showSwipe)
    icon.Cooldown:SetDrawEdge(showSwipe)

    -- Use overlay color (aura mode) — default to Blizzard yellow
    local oR, oG, oB, oA = ResolveColor(settings.overlayColorMode or "default", settings.overlayColor)
    if not oR then oR, oG, oB, oA = BLIZZ_BUFF_R, BLIZZ_BUFF_G, BLIZZ_BUFF_B, BLIZZ_BUFF_A end

    icon.Cooldown:SetSwipeTexture("Interface\\Buttons\\WHITE8X8")
    icon.Cooldown:SetSwipeColor(oR, oG, oB, oA)
end

---------------------------------------------------------------------------
-- REFRESH ALL ICONS
---------------------------------------------------------------------------
local function RefreshAllSwipes()
    local CDMIcons = ns.CDMIcons
    if not CDMIcons then return end

    local settings = GetSettings()

    -- Addon-owned icons (essential, utility, buff)
    for _, viewerType in ipairs({"essential", "utility", "buff"}) do
        local pool = CDMIcons:GetIconPool(viewerType)
        for _, icon in ipairs(pool) do
            ApplySwipeToIcon(icon, settings)
        end
    end
end

---------------------------------------------------------------------------
-- EXPORTS (deferred — only overwrite classic engine's exports when owned is active)
---------------------------------------------------------------------------
ns._OwnedSwipe = {
    Apply = RefreshAllSwipes,
    ApplyToIcon = ApplySwipeToIcon,
    ApplyToBuffChild = ApplySwipeToBuffChild,
    GetSettings = GetSettings,
}
