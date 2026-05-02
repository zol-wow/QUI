-- highlighter.lua
-- Cooldown Highlighter: briefly highlights the CDM icon matching a spell
-- the player just cast, giving visual feedback of what was pressed.

local _, ns = ...
local Helpers = ns.Helpers

local function IsCDMRuntimeEnabled()
    local checker = _G.QUI_IsCDMMasterEnabled
    return type(checker) ~= "function" or checker()
end

local LCG = LibStub and LibStub("LibCustomGlow-1.0", true)

local FLASH_TEXTURE = [[Interface\AddOns\QUI\assets\iconskin\Flash]]
local HAMMER_TEXTURE = [[Interface\AddOns\QUI\assets\quazii_hammer]]

---------------------------------------------------------------------------
-- SETTINGS
---------------------------------------------------------------------------
local GetSettings = Helpers.CreateDBGetter("cooldownHighlighter")

---------------------------------------------------------------------------
-- STATE
---------------------------------------------------------------------------
local activeHighlights = {}  -- [icon] = timerHandle
local GLOW_KEY = "_QUIHighlighter"

---------------------------------------------------------------------------
-- FIND CDM ICON BY SPELL ID
-- Searches all owned CDM icons for a matching spellID or overrideSpellID.
---------------------------------------------------------------------------
local VIEWER_TYPES = { "essential", "utility", "buff" }

local function FindIconBySpellID(castSpellID)
    if not castSpellID then return nil end

    local CDMIcons = ns.CDMIcons
    if not CDMIcons or not CDMIcons.GetIconPool then return nil end

    for _, viewerType in ipairs(VIEWER_TYPES) do
        local pool = CDMIcons:GetIconPool(viewerType)
        for _, icon in ipairs(pool) do
            if icon and icon._spellEntry and icon:IsShown() then
                local entry = icon._spellEntry
                local baseID = entry.spellID or entry.id
                if baseID == castSpellID then return icon end
                if entry.overrideSpellID and entry.overrideSpellID == castSpellID then return icon end
                if baseID and C_Spell and C_Spell.GetOverrideSpell then
                    local ok, overrideID = pcall(C_Spell.GetOverrideSpell, baseID)
                    if ok and overrideID and overrideID == castSpellID then return icon end
                end
            end
        end
    end

    return nil
end

---------------------------------------------------------------------------
-- TEXTURE OVERLAY GLOW HELPER
---------------------------------------------------------------------------
local function StartTextureGlow(icon, key, texturePath, color)
    local frame = icon[key]
    if not frame then
        frame = CreateFrame("Frame", nil, icon)
        frame:SetAllPoints(icon)
        icon[key] = frame

        local tex = frame:CreateTexture(nil, "OVERLAY")
        tex:SetTexture(texturePath)
        tex:SetTexCoord(0, 1, 0, 1)
        tex:SetBlendMode("ADD")
        tex:SetAllPoints(frame)
        frame.texture = tex

        local ag = frame:CreateAnimationGroup()
        ag:SetLooping("REPEAT")

        local fadeIn = ag:CreateAnimation("Alpha")
        fadeIn:SetFromAlpha(0.3)
        fadeIn:SetToAlpha(1)
        fadeIn:SetDuration(0.4)
        fadeIn:SetOrder(1)

        local fadeOut = ag:CreateAnimation("Alpha")
        fadeOut:SetFromAlpha(1)
        fadeOut:SetToAlpha(0.3)
        fadeOut:SetDuration(0.4)
        fadeOut:SetOrder(2)

        frame.animGroup = ag
    end

    local r, g, b, a = 1, 1, 1, 1
    if color then r, g, b, a = color[1] or 1, color[2] or 1, color[3] or 1, color[4] or 1 end
    frame.texture:SetVertexColor(r, g, b, a)
    frame:Show()
    frame.animGroup:Play()
    return frame
end

local function StopTextureGlow(icon, key)
    local frame = icon[key]
    if frame then
        frame.animGroup:Stop()
        frame:Hide()
    end
end

---------------------------------------------------------------------------
-- HIGHLIGHT APPLICATION
---------------------------------------------------------------------------
local function StopAllGlows(icon)
    if not icon or not LCG then return end
    LCG.PixelGlow_Stop(icon, GLOW_KEY)
    LCG.AutoCastGlow_Stop(icon, GLOW_KEY)
    LCG.ButtonGlow_Stop(icon)
    pcall(LCG.ProcGlow_Stop, icon, GLOW_KEY)
    StopTextureGlow(icon, "_QUIFlashHL")
    StopTextureGlow(icon, "_QUIHammerHL")
end

local function RemoveHighlight(icon)
    if not icon then return end
    StopAllGlows(icon)
    activeHighlights[icon] = nil
end

-- Ensure glow frame renders above the cooldown swipe
local function EnsureGlowAboveCooldown(icon, glowFrame)
    if not glowFrame or not icon or not icon.Cooldown then return end
    local cdLevel = icon.Cooldown:GetFrameLevel()
    if glowFrame:GetFrameLevel() <= cdLevel then
        glowFrame:SetFrameLevel(cdLevel + 1)
    end
end

local function ApplyHighlight(icon)
    if not icon or not LCG then return end

    local settings = GetSettings()
    if not settings or not settings.enabled then return end

    -- Remove existing highlight if any
    if activeHighlights[icon] then
        activeHighlights[icon]:Cancel()
        RemoveHighlight(icon)
    end

    local glowType = settings.glowType or "Pixel Glow"
    local color = settings.color or {1, 1, 1, 0.8}
    local duration = settings.duration or 0.4
    local lines = settings.lines or 8
    local thickness = settings.thickness or 1
    local scale = settings.scale or 1
    local frequency = settings.frequency or 0.25

    if glowType == "Pixel Glow" then
        LCG.PixelGlow_Start(icon, color, lines, frequency, nil, thickness, 0, 0, true, GLOW_KEY)
        EnsureGlowAboveCooldown(icon, icon["_PixelGlow_" .. GLOW_KEY])
    elseif glowType == "Autocast Shine" then
        LCG.AutoCastGlow_Start(icon, color, lines, frequency, scale, 0, 0, GLOW_KEY)
        EnsureGlowAboveCooldown(icon, icon["_AutoCastGlow_" .. GLOW_KEY])
    elseif glowType == "Button Glow" then
        LCG.ButtonGlow_Start(icon, color, frequency)
        EnsureGlowAboveCooldown(icon, icon["_ButtonGlow"])

    elseif glowType == "Flash" then
        EnsureGlowAboveCooldown(icon, StartTextureGlow(icon, "_QUIFlashHL", FLASH_TEXTURE, color))

    elseif glowType == "Hammer" then
        EnsureGlowAboveCooldown(icon, StartTextureGlow(icon, "_QUIHammerHL", HAMMER_TEXTURE, color))

    elseif glowType == "Proc Glow" then
        LCG.ProcGlow_Start(icon, {
            key = GLOW_KEY,
            color = color,
            startAnim = true,
        })
        EnsureGlowAboveCooldown(icon, icon["_ProcGlow" .. GLOW_KEY])
    end

    -- Auto-remove after duration
    activeHighlights[icon] = C_Timer.NewTimer(duration, function()
        RemoveHighlight(icon)
    end)
end

---------------------------------------------------------------------------
-- EVENT HANDLING
---------------------------------------------------------------------------
local eventFrame = CreateFrame("Frame")
eventFrame:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")

eventFrame:SetScript("OnEvent", function(_, _, _, _, castSpellID)
    if not IsCDMRuntimeEnabled() then return end

    local settings = GetSettings()
    if not settings or not settings.enabled then return end
    if not castSpellID then return end

    local icon = FindIconBySpellID(castSpellID)
    if icon then
        ApplyHighlight(icon)
    end
end)

ns.QUI_PerfRegistry = ns.QUI_PerfRegistry or {}
ns.QUI_PerfRegistry[#ns.QUI_PerfRegistry + 1] = { name = "CDM_Highlighter", frame = eventFrame }

local function ClearHighlights()
    for icon, timer in pairs(activeHighlights) do
        if timer and timer.Cancel then
            timer:Cancel()
        end
        RemoveHighlight(icon)
    end
end

local function DisableRuntime()
    eventFrame:UnregisterAllEvents()
    eventFrame:SetScript("OnEvent", nil)
    ClearHighlights()
end

ns._OwnedHighlighter = {
    DisableRuntime = DisableRuntime,
}

---------------------------------------------------------------------------
-- GLOBAL REFRESH
---------------------------------------------------------------------------
_G.QUI_RefreshCooldownHighlighter = function()
    if not IsCDMRuntimeEnabled() then
        ClearHighlights()
        return
    end

    local settings = GetSettings()
    if not settings or not settings.enabled then
        -- Remove all active highlights
        ClearHighlights()
    end
end

if ns.Registry then
    ns.Registry:Register("cooldownHighlighter", {
        refresh = _G.QUI_RefreshCooldownHighlighter,
        priority = 10,
        group = "cooldowns",
        importCategories = { "cdm" },
    })
end
