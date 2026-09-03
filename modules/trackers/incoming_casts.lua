local ADDON_NAME, ns = ...
local Helpers = ns.Helpers

local CreateFrame = CreateFrame
local InCombatLockdown = InCombatLockdown
local UIParent = UIParent
local UnitIsUnit = UnitIsUnit
local math_floor = math.floor
local pairs = pairs
local tonumber = tonumber
local type = type

local GetSettings = Helpers.CreateDBGetter("incomingCasts")
local IsSecretValue = Helpers.IsSecretValue

-- Personal incoming-cast display: a row of icons anchored to the screen that
-- shows enemy casts currently aimed at the player, fed by ns.IncomingCasts.
local SUBSCRIBER_KEY = "personalIncomingCasts"
local FALLBACK_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"
local PREVIEW_ICON = 136048 -- Lightning Bolt
local MAX_NAMEPLATE_CASTERS = 150

local DEFAULTS = {
    enabled = false,
    iconSize = 40,
    maxIcons = 5,
    spacing = 4,
    growDirection = "CENTER",
    collapseGaps = true,
    showSwipe = true,
    reverseSwipe = true,
    showCooldownText = false,
    borderSize = 1,
}

local GROW = {
    LEFT = true,
    RIGHT = true,
    CENTER = true,
    UP = true,
    DOWN = true,
}

local function Option(key)
    local settings = GetSettings()
    local value = settings and settings[key]
    if value == nil then
        return DEFAULTS[key]
    end
    return value
end

local function ClampedOption(key, minValue, maxValue)
    local n = tonumber(Option(key))
    if not n then
        return DEFAULTS[key]
    end
    if n < minValue then
        n = minValue
    elseif n > maxValue then
        n = maxValue
    end
    return n
end

local function IconSize()
    return ClampedOption("iconSize", 12, 96)
end

local function MaxIcons()
    return math_floor(ClampedOption("maxIcons", 1, 10))
end

local function IconSpacing()
    return ClampedOption("spacing", 0, 32)
end

local function BorderSize()
    return math_floor(ClampedOption("borderSize", 0, 4))
end

local function GrowthDirection()
    local grow = Option("growDirection")
    if type(grow) ~= "string" or not GROW[grow] then
        return DEFAULTS.growDirection
    end
    return grow
end

local COLLAPSED_SCALE = 0.01

local function CollapseActive()
    return Option("collapseGaps") ~= false
end

local host = CreateFrame("Frame", "QUI_IncomingCasts", UIParent)
host:SetSize(DEFAULTS.iconSize, DEFAULTS.iconSize)
host:SetPoint("CENTER", UIParent, "CENTER", 0, -180)

-- Visibility is secret (alpha-sunk), so Lua can never tell which icons are
-- showing. Reserve the full Blizzard nameplate token range out of combat;
-- maxIcons governs only the layout extent and preview count.
local icons = {}
local activeByCaster = {}
local previewActive = false
local subscribed = false
local deferredPoolGrowth = 0
local debugShows = 0
local debugHides = 0

local function ApplyIconStyle(icon)
    local size = IconSize()
    icon:SetSize(size, size)

    local borderSize = BorderSize()
    if icon._borderSize ~= borderSize then
        icon._borderSize = borderSize
        if borderSize > 0 then
            icon._border:SetBackdrop({
                edgeFile = "Interface\\Buttons\\WHITE8x8",
                edgeSize = borderSize,
            })
        else
            icon._border:SetBackdrop(nil)
        end
    end
    if borderSize > 0 then
        local r, g, b, a = Helpers.GetSkinBorderColor(GetSettings() or DEFAULTS, "")
        icon._border:SetBackdropBorderColor(r, g, b, a)
        icon._border:Show()
    else
        icon._border:Hide()
    end

    local cooldown = icon._cooldown
    cooldown:SetReverse(Option("reverseSwipe") ~= false)
    cooldown:SetDrawSwipe(Option("showSwipe") ~= false)
    cooldown:SetHideCountdownNumbers(Option("showCooldownText") ~= true)
end

local function ResetIconScale(icon)
    icon:SetScale(CollapseActive() and COLLAPSED_SCALE or 1)
end

local function NewIcon()
    local icon = CreateFrame("Frame", nil, host)
    icon:Hide()

    local texture = icon:CreateTexture(nil, "ARTWORK")
    texture:SetAllPoints()
    texture:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    icon._texture = texture

    local cooldown = CreateFrame("Cooldown", nil, icon, "CooldownFrameTemplate")
    cooldown:SetAllPoints()
    cooldown:SetDrawEdge(false)
    cooldown:SetSwipeColor(0, 0, 0, 0.6)
    icon._cooldown = cooldown

    local border = CreateFrame("Frame", nil, icon, "BackdropTemplate")
    border:SetAllPoints()
    border:SetFrameLevel(icon:GetFrameLevel() + 2)
    icon._border = border

    ApplyIconStyle(icon)
    ResetIconScale(icon)
    return icon
end

-- Pool index doubles as the icon's fixed slot: a cast keeps its slot (and
-- screen position) for its whole lifetime, and freed slots are refilled
-- lowest-first. Load-bearing: alpha-0 icons (casts aimed at someone else)
-- are invisible but still occupy a slot, so any count-based layout would
-- visibly shift icons whenever an invisible neighbor starts or stops.
local function AcquireIcon()
    for i = 1, #icons do
        if not icons[i]._inUse then
            return icons[i]
        end
    end
    if InCombatLockdown() then
        deferredPoolGrowth = deferredPoolGrowth + 1
        return nil
    end
    local icon = NewIcon()
    icon._slot = #icons + 1
    icons[#icons + 1] = icon
    return icon
end

local function StopCooldown(cooldown)
    ns.SafeCallMethodIfPresent("best-effort-style", cooldown, "Clear")
    cooldown:Hide()
end

local function StartCooldown(cooldown, durationObject, startMS, endMS)
    local durSecret = IsSecretValue(durationObject)
    if (durSecret or durationObject) and cooldown.SetCooldownFromDurationObject then
        local ok = ns.SafeCallMethod("sink-forward", cooldown, "SetCooldownFromDurationObject", durationObject)
        if ok then
            cooldown:SetAlpha(1)
            cooldown:Show()
            return
        end
    end

    if IsSecretValue(startMS) or IsSecretValue(endMS)
        or type(startMS) ~= "number" or type(endMS) ~= "number"
        or endMS <= startMS then
        StopCooldown(cooldown)
        return
    end

    local start = startMS
    local duration = endMS - startMS
    if start > 100000 then
        start = start / 1000
        duration = duration / 1000
    end

    if cooldown.SetCooldown then
        cooldown:SetCooldown(start, duration)
        cooldown:Show()
    else
        StopCooldown(cooldown)
    end
end

local function ChainAnchorIcon(icon)
    local spacing = IconSpacing()
    local grow = GrowthDirection()
    local slot = icon._slot or 1

    icon:ClearAllPoints()
    if grow == "CENTER" then
        if slot == 1 then
            icon:SetPoint("CENTER", host, "CENTER", 0, 0)
            return
        end
        local prev = icons[slot == 2 and 1 or slot - 2]
        if slot % 2 == 1 then
            icon:SetPoint("RIGHT", prev, "LEFT", -spacing, 0)
        else
            icon:SetPoint("LEFT", prev, "RIGHT", spacing, 0)
        end
        return
    end

    local prev = icons[slot - 1]
    if grow == "LEFT" then
        if prev then
            icon:SetPoint("RIGHT", prev, "LEFT", -spacing, 0)
        else
            icon:SetPoint("RIGHT", host, "RIGHT", 0, 0)
        end
    elseif grow == "UP" then
        if prev then
            icon:SetPoint("BOTTOM", prev, "TOP", 0, spacing)
        else
            icon:SetPoint("BOTTOM", host, "BOTTOM", 0, 0)
        end
    elseif grow == "DOWN" then
        if prev then
            icon:SetPoint("TOP", prev, "BOTTOM", 0, -spacing)
        else
            icon:SetPoint("TOP", host, "TOP", 0, 0)
        end
    else
        if prev then
            icon:SetPoint("LEFT", prev, "RIGHT", spacing, 0)
        else
            icon:SetPoint("LEFT", host, "LEFT", 0, 0)
        end
    end
end

local function PositionIcon(icon)
    if CollapseActive() then
        ChainAnchorIcon(icon)
        return
    end

    local stride = IconSize() + IconSpacing()
    local grow = GrowthDirection()
    local slot = icon._slot or 1

    icon:ClearAllPoints()
    if grow == "LEFT" then
        icon:SetPoint("RIGHT", host, "RIGHT", -(slot - 1) * stride, 0)
    elseif grow == "RIGHT" then
        icon:SetPoint("LEFT", host, "LEFT", (slot - 1) * stride, 0)
    elseif grow == "UP" then
        icon:SetPoint("BOTTOM", host, "BOTTOM", 0, (slot - 1) * stride)
    elseif grow == "DOWN" then
        icon:SetPoint("TOP", host, "TOP", 0, -(slot - 1) * stride)
    else
        -- CENTER fills outward: slot 1 sits on the anchor, later slots
        -- alternate right and left of it, so occupied slots never re-center.
        local k
        if slot % 2 == 0 then
            k = slot / 2
        else
            k = -((slot - 1) / 2)
        end
        icon:SetPoint("CENTER", host, "CENTER", k * stride, 0)
    end
end

local function LayoutIcons()
    local size = IconSize()
    local spacing = IconSpacing()
    local stride = size + spacing
    local grow = GrowthDirection()
    local maxIcons = MaxIcons()

    if grow == "UP" or grow == "DOWN" then
        host:SetSize(size, maxIcons * stride - spacing)
    else
        host:SetSize(maxIcons * stride - spacing, size)
    end

    for i = 1, #icons do
        PositionIcon(icons[i])
    end
end

local function ReleaseIcon(icon)
    icon._inUse = nil
    icon:Hide()
    icon:SetAlpha(1)
    ResetIconScale(icon)
    StopCooldown(icon._cooldown)
end

local function ClearActive()
    for caster, icon in pairs(activeByCaster) do
        activeByCaster[caster] = nil
        ReleaseIcon(icon)
    end
end

local function ApplyTargetScale(icon, matched)
    icon:SetScale(CollapseActive() and not IsSecretValue(matched)
        and matched ~= true and COLLAPSED_SCALE or 1)
end

-- The "is this cast aimed at me" verdict is a secret boolean in instances, so
-- it must never be truth-tested in Lua. Every hostile cast gets an icon and
-- this sink decides its visibility client-side; alpha-0 icons keep their
-- layout slot.
local function ApplyTargetVisibility(icon, caster)
    local ok, matched = ns.SafeCall("sink-forward", UnitIsUnit, caster .. "target", "player")
    if not ok then
        icon:SetAlpha(0)
        icon:SetScale(CollapseActive() and COLLAPSED_SCALE or 1)
        return
    end
    ApplyTargetScale(icon, matched)
    if icon.SetAlphaFromBoolean then
        local sunk = ns.SafeCallMethod("sink-forward", icon, "SetAlphaFromBoolean", matched, 1, 0)
        if sunk then
            return
        end
    end
    if IsSecretValue(matched) then
        icon:SetAlpha(0) -- @secret-policy: reject-secret-value — no alpha sink available, fail closed
    else
        icon:SetAlpha(matched == true and 1 or 0)
    end
end

-- Cast-specific work only; static styling is applied at icon creation, on
-- Refresh, and in preview — not per cast.
local function DisplayCast(icon, caster, cast)
    PositionIcon(icon)
    local texture = cast.texture
    if IsSecretValue(texture) then
        icon._texture:SetTexture(texture) -- @secret-policy: sink-forward — never compare a secret texture
    elseif texture == nil then
        icon._texture:SetTexture(FALLBACK_ICON)
    else
        icon._texture:SetTexture(texture)
    end
    StartCooldown(icon._cooldown, cast.durationObj, cast.startMS, cast.endMS)
    ApplyTargetVisibility(icon, caster)
    icon:Show()
end

local function OnCastShow(caster, _, cast)
    if previewActive then
        return
    end

    local icon = activeByCaster[caster]
    if not icon then
        icon = AcquireIcon()
        if not icon then
            return
        end
        icon._inUse = true
        activeByCaster[caster] = icon
    end
    debugShows = debugShows + 1
    DisplayCast(icon, caster, cast)
end

local function OnCastUpdate(caster)
    if previewActive then
        return
    end
    local icon = activeByCaster[caster]
    if icon then
        ApplyTargetVisibility(icon, caster)
    end
end

local function OnCastHide(caster)
    local icon = activeByCaster[caster]
    if not icon then
        return
    end
    activeByCaster[caster] = nil
    ReleaseIcon(icon)
    debugHides = debugHides + 1
end

local function UpdateSubscription()
    local IC = ns.IncomingCasts
    if not IC then
        return
    end

    local enabled = Option("enabled") == true
    if enabled and not subscribed then
        subscribed = IC.Subscribe(SUBSCRIBER_KEY, {
            allCasts = true,
            onShow = OnCastShow,
            onUpdate = OnCastUpdate,
            onHide = OnCastHide,
        }) == true
        if subscribed then
            -- pick up casts already in flight when the engine was running
            -- for another subscriber before this one joined
            IC.ResetSubscriber(SUBSCRIBER_KEY)
        end
    elseif not enabled and subscribed then
        IC.Unsubscribe(SUBSCRIBER_KEY)
        subscribed = false
        ClearActive()
    end
end

local function EnsurePool()
    if InCombatLockdown() then
        return
    end
    local target = #icons + deferredPoolGrowth
    if target < MAX_NAMEPLATE_CASTERS then
        target = MAX_NAMEPLATE_CASTERS
    end
    deferredPoolGrowth = 0
    for i = 1, target do
        if not icons[i] then
            local icon = NewIcon()
            icon._slot = i
            icons[i] = icon
        end
    end
end

local function Refresh()
    UpdateSubscription()
    if subscribed then
        EnsurePool()
    end
    for i = 1, #icons do
        ApplyIconStyle(icons[i])
        if not icons[i]._inUse then
            ResetIconScale(icons[i])
        end
    end
    LayoutIcons()
    for caster, icon in pairs(activeByCaster) do
        ApplyTargetVisibility(icon, caster)
    end
end

-- Re-entrant: settings changes call this again while preview is showing to
-- reconcile the icon count against the current maxIcons.
local function EnablePreview()
    previewActive = true
    ClearActive()

    local count = MaxIcons()
    for i = 1, count do
        local icon = icons[i]
        if not icon then
            icon = NewIcon()
            icon._slot = i
            icons[i] = icon
        end
        icon._inUse = true
        ApplyIconStyle(icon)
        icon:SetScale(1)
        icon._texture:SetTexture(PREVIEW_ICON)
        StopCooldown(icon._cooldown)
        icon:Show()
    end
    for i = count + 1, #icons do
        ReleaseIcon(icons[i])
    end
    LayoutIcons()
end

local function DisablePreview()
    if not previewActive then
        return
    end
    previewActive = false
    for i = 1, #icons do
        ReleaseIcon(icons[i])
    end
    LayoutIcons()

    -- The engine kept delivering (and marking shown) casts while preview
    -- swallowed them; re-evaluate in-flight casts so their icons come back.
    local IC = ns.IncomingCasts
    if subscribed and IC and IC.ResetSubscriber then
        IC.ResetSubscriber(SUBSCRIBER_KEY)
    end
end

-- Preview suppresses live cast delivery, so it must never survive into a
-- pull; entering combat force-disables it (DisablePreview re-delivers any
-- in-flight casts via ResetSubscriber).
local previewGuard = CreateFrame("Frame")
previewGuard:RegisterEvent("PLAYER_REGEN_DISABLED")
previewGuard:RegisterEvent("PLAYER_REGEN_ENABLED")
previewGuard:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_REGEN_ENABLED" then
        if subscribed then
            EnsurePool()
        end
    elseif previewActive then
        DisablePreview()
    end
end)

ns.QUI_IncomingCasts = {
    Refresh = Refresh,
    EnablePreview = EnablePreview,
    DisablePreview = DisablePreview,
    IsPreviewActive = function() return previewActive end,
    GetFrame = function() return host end,
}

if ns.Registry then
    ns.Registry:Register("incomingCasts", {
        refresh = Refresh,
        priority = 45,
        group = "trackers",
        importCategories = { "trackersTimers" },
    })
end

if ns.WhenLoggedIn then
    ns.WhenLoggedIn(Refresh)
end

-- /quiic         dump the incoming-casts pipeline state (display + engine)
-- /quiic log     toggle verbose per-event logging in the engine
SLASH_QUIIC1 = "/quiic"
SlashCmdList["QUIIC"] = function(msg)
    local prefix = "|cff34D399[QUI-IC]|r "
    local IC = ns.IncomingCasts

    msg = type(msg) == "string" and msg:lower():match("^%s*(%S*)") or ""
    if msg == "log" then
        if IC and IC.ToggleDebugLog then
            local enabled = IC.ToggleDebugLog()
            print(prefix .. "verbose logging " .. (enabled and "ON — casts will print as they happen" or "OFF"))
        end
        return
    end

    print(prefix .. "display: enabled=" .. tostring(Option("enabled") == true)
        .. " subscribed=" .. tostring(subscribed)
        .. " preview=" .. tostring(previewActive)
        .. " engineLoaded=" .. tostring(IC ~= nil))
    local activeIcons = 0
    for _ in pairs(activeByCaster) do
        activeIcons = activeIcons + 1
    end
    print(prefix .. "display: activeIcons=" .. activeIcons
        .. " shows=" .. debugShows .. " hides=" .. debugHides
        .. " slots=" .. #icons
        .. " hostShown=" .. tostring(host:IsShown()))
    if IC and IC.DebugDump then
        IC.DebugDump()
    end
end
