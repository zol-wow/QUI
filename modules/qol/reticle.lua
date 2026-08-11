local ADDON_NAME, ns = ...
local QUI = ns.QUI or {}
ns.QUI = QUI
local Helpers = ns.Helpers
local CreateTimeThrottle = Helpers and Helpers.CreateTimeThrottle
local ApplyCooldownFromSpell = Helpers and Helpers.ApplyCooldownFromSpell
local IsSecretValue = Helpers and Helpers.IsSecretValue

local UIParent = UIParent
local CreateFrame = CreateFrame
local GetCursorPosition = GetCursorPosition
-- luacheck: push ignore 113
---@diagnostic disable-next-line: undefined-global
local GetScaledCursorPosition = GetScaledCursorPosition or function()
    local scale = UIParent:GetEffectiveScale()
    local x, y = GetCursorPosition()
    return x / scale, y / scale
end
-- luacheck: pop
local InCombatLockdown = InCombatLockdown
local UnitClass = UnitClass
local C_ClassColor = C_ClassColor

local ringFrame, ringTexture, reticleTexture, gcdCooldown

local cachedSettings = nil
local cursorUpdateEnabled = false

local cachedOffsetX, cachedOffsetY = 0, 0
local lastCursorX, lastCursorY = 0, 0

local EnableCursorUpdate, DisableCursorUpdate

local GCD_SPELL_ID = 61304
local RETICLE_FRAME_STRATA = "TOOLTIP"
local RETICLE_FRAME_LEVEL = 9500
local GCD_FRAME_LEVEL_OFFSET = 2

local RING_TEXTURES = {
    thin     = Helpers.AssetPath .. "cursor\\qui_ring_thin.png",
    standard = Helpers.AssetPath .. "cursor\\qui_ring_standard.png",
    thick    = Helpers.AssetPath .. "cursor\\qui_ring_thick.png",
    solid    = Helpers.AssetPath .. "cursor\\qui_ring_solid.png",
}

local RETICLE_OPTIONS = {
    dot     = { path = Helpers.AssetPath .. "cursor\\qui_reticle_dot.tga", isAtlas = false },
    cross   = { path = "uitools-icon-plus", isAtlas = true },
    chevron = { path = "uitools-icon-chevron-down", isAtlas = true },
    diamond = { path = "UF-SoulShard-FX-FrameGlow", isAtlas = true },
}

local function ApplyReticleLayering()
    if not ringFrame then return end
    ringFrame:SetFrameStrata(RETICLE_FRAME_STRATA)
    ringFrame:SetFrameLevel(RETICLE_FRAME_LEVEL)
    if gcdCooldown then
        gcdCooldown:SetFrameLevel(RETICLE_FRAME_LEVEL + GCD_FRAME_LEVEL_OFFSET)
    end
end

local function GetSettings()
    if cachedSettings then return cachedSettings end
    cachedSettings = Helpers.GetModuleDB("reticle")
    return cachedSettings
end

local function InvalidateCache()
    cachedSettings = nil
end

local function CacheOffsets()
    local settings = GetSettings()
    cachedOffsetX = settings and settings.offsetX or 0
    cachedOffsetY = settings and settings.offsetY or 0
end

local function GetRingColor()
    local settings = GetSettings()
    if not settings then return 1, 1, 1, 1 end

    if settings.useClassColor then
        local _, classFile = UnitClass("player")
        local color = C_ClassColor.GetClassColor(classFile)
        if color then
            return color.r, color.g, color.b, 1
        end
        return 1, 1, 1, 1
    else
        local c = settings.customColor or {0.376, 0.647, 0.980, 1}
        return c[1] or 0.376, c[2] or 0.647, c[3] or 0.980, c[4] or 1
    end
end

local function GetCurrentAlpha()
    local settings = GetSettings()
    if not settings then return 1 end

    if InCombatLockdown() then
        return settings.inCombatAlpha or 0.8
    else
        return settings.outCombatAlpha or 0.3
    end
end

local function CreateReticle()
    if ringFrame then return end

    ringFrame = CreateFrame("Frame", "QUI_Reticle", UIParent)
    ringFrame:EnableMouse(false)
    ringFrame:SetSize(80, 80)

    ringTexture = ringFrame:CreateTexture(nil, "BACKGROUND")
    ringTexture:SetAllPoints()

    gcdCooldown = CreateFrame("Cooldown", nil, ringFrame, "CooldownFrameTemplate")
    gcdCooldown:SetAllPoints()
    gcdCooldown:EnableMouse(false)
    gcdCooldown:SetDrawSwipe(true)
    gcdCooldown:SetDrawEdge(false)
    gcdCooldown:SetHideCountdownNumbers(true)
    if gcdCooldown.SetDrawBling then gcdCooldown:SetDrawBling(false) end
    if gcdCooldown.SetUseCircularEdge then gcdCooldown:SetUseCircularEdge(true) end

    reticleTexture = ringFrame:CreateTexture(nil, "OVERLAY")
    reticleTexture:SetPoint("CENTER", ringFrame, "CENTER", 0, 0)

    ApplyReticleLayering()
    ringFrame:Hide()
end

local function UpdateReticleDot()
    if not reticleTexture then return end

    local settings = GetSettings()
    if not settings then return end

    local style = settings.reticleStyle or "dot"
    local size = settings.reticleSize or 10
    local r, g, b, a = GetRingColor()

    local reticleInfo = RETICLE_OPTIONS[style] or RETICLE_OPTIONS.dot

    if reticleInfo.isAtlas then
        reticleTexture:SetAtlas(reticleInfo.path)
    else
        reticleTexture:SetTexture(reticleInfo.path)
    end

    reticleTexture:SetSize(size, size)
    reticleTexture:SetVertexColor(r, g, b, a)
end

local function UpdateRingAppearance()
    if not ringFrame or not ringTexture then return end

    local settings = GetSettings()
    if not settings then return end

    local style = settings.ringStyle or "standard"
    local size = settings.ringSize or 40
    local r, g, b, a = GetRingColor()

    local texturePath = RING_TEXTURES[style] or RING_TEXTURES.standard
    ringTexture:SetTexture(texturePath)
    ringTexture:SetVertexColor(r, g, b, 1)

    local baseAlpha = GetCurrentAlpha()
    local ringAlpha = baseAlpha

    if gcdCooldown and gcdCooldown:IsShown() and settings.gcdEnabled then
        local fadeAmount = settings.gcdFadeRing or 0.35
        ringAlpha = baseAlpha * (1 - fadeAmount)
    end

    ringTexture:SetAlpha(ringAlpha)

    ringFrame:SetSize(size, size)

    if gcdCooldown and settings.gcdEnabled then
        if gcdCooldown.SetSwipeTexture then
            gcdCooldown:SetSwipeTexture(texturePath)
        end
        gcdCooldown:SetSwipeColor(r, g, b, baseAlpha)
        if gcdCooldown.SetReverse then
            gcdCooldown:SetReverse(settings.gcdReverse or false)
        end
    end
end

local function UpdateGCDCooldown()
    if not gcdCooldown then return end

    local settings = GetSettings()
    if not settings or not settings.gcdEnabled then
        gcdCooldown:Hide()
        UpdateRingAppearance()
        return
    end

    if ApplyCooldownFromSpell and ApplyCooldownFromSpell(gcdCooldown, GCD_SPELL_ID, nil, false) then
        gcdCooldown:Show()
    else
        gcdCooldown:Hide()
    end

    UpdateRingAppearance()
end

local ThrottledCooldownRefresh
if CreateTimeThrottle then
    ThrottledCooldownRefresh = CreateTimeThrottle(0.05, function()
        UpdateGCDCooldown()
    end)
else
    ThrottledCooldownRefresh = UpdateGCDCooldown
end

local function UpdateVisibility(forcedInCombat)
    if not ringFrame then return end

    local settings = GetSettings()
    if not settings or not settings.enabled then
        ringFrame:Hide()
        DisableCursorUpdate()
        return
    end

    local inCombat = (forcedInCombat ~= nil) and forcedInCombat or InCombatLockdown()

    if settings.hideOutOfCombat and not inCombat then
        ringFrame:Hide()
        DisableCursorUpdate()
        return
    end

    ringFrame:Show()
    EnableCursorUpdate()
end

local function UpdateReticle()
    if not ringFrame then
        CreateReticle()
    end

    CacheOffsets()
    UpdateVisibility()
    UpdateReticleDot()
    UpdateGCDCooldown()
end

local function OnCombatStart()
    UpdateVisibility(true)
    UpdateGCDCooldown()
end

local function OnCombatEnd()
    UpdateVisibility(false)
    UpdateRingAppearance()
end

local function SetupRightClickHide()
    WorldFrame:HookScript("OnMouseDown", function(_, button)
        C_Timer.After(0, function()
            if button == "RightButton" then
                local settings = GetSettings()
                if settings and settings.hideOnRightClick and ringFrame then
                    ringFrame:Hide()
                end
            end
        end)
    end)

    WorldFrame:HookScript("OnMouseUp", function(_, button)
        C_Timer.After(0, function()
            if button == "RightButton" then
                local settings = GetSettings()
                if settings and settings.enabled and settings.hideOnRightClick and ringFrame then
                    if not settings.hideOutOfCombat or InCombatLockdown() then
                        ringFrame:Show()
                    end
                end
            end
        end)
    end)
end

local function CursorOnUpdate(self, elapsed)
    local x, y = GetScaledCursorPosition()

    local dx, dy = x - lastCursorX, y - lastCursorY
    if dx > -0.5 and dx < 0.5 and dy > -0.5 and dy < 0.5 then
        return
    end
    lastCursorX, lastCursorY = x, y

    self:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x + cachedOffsetX, y + cachedOffsetY)
end

EnableCursorUpdate = function()
    if cursorUpdateEnabled or not ringFrame then return end
    cursorUpdateEnabled = true
    ringFrame:SetScript("OnUpdate", CursorOnUpdate)
end

DisableCursorUpdate = function()
    if not cursorUpdateEnabled or not ringFrame then return end
    cursorUpdateEnabled = false
    ringFrame:SetScript("OnUpdate", nil)
end

local function SetupCursorFollowing()
    local settings = GetSettings()
    if settings and settings.enabled then
        EnableCursorUpdate()
    end
end

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
eventFrame:RegisterEvent("SPELL_UPDATE_COOLDOWN")
eventFrame:RegisterEvent("ACTIONBAR_UPDATE_COOLDOWN")
eventFrame:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")

eventFrame:SetScript("OnEvent", function(self, event, _, _, spellID)
    if event == "PLAYER_ENTERING_WORLD" then
        UpdateReticle()

    elseif event == "PLAYER_REGEN_DISABLED" then
        OnCombatStart()

    elseif event == "PLAYER_REGEN_ENABLED" then
        OnCombatEnd()

    elseif event == "SPELL_UPDATE_COOLDOWN" or event == "ACTIONBAR_UPDATE_COOLDOWN" then
        ThrottledCooldownRefresh()

    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        local settings = GetSettings()
        if not settings or not settings.gcdEnabled then
            if gcdCooldown then gcdCooldown:Hide() end
            return
        end

        if IsSecretValue(spellID) then
            UpdateGCDCooldown()
        elseif spellID then
            if ApplyCooldownFromSpell and ApplyCooldownFromSpell(gcdCooldown, spellID) then
                gcdCooldown:Show()
                UpdateRingAppearance()
            else
                UpdateGCDCooldown()
            end
        else
            UpdateGCDCooldown()
        end
    end
end)

if ns.WhenLoggedIn then
    ns.WhenLoggedIn(function()
        CreateReticle()
        UpdateReticle()
        SetupCursorFollowing()
        SetupRightClickHide()
    end)
end

_G.QUI_RefreshReticle = function()
    InvalidateCache()
    UpdateReticle()
end

if ns.Registry then
    ns.Registry:Register("reticle", {
        refresh = _G.QUI_RefreshReticle,
        priority = 30,
        group = "qol",
        importCategories = { "castBars" },
    })
end

QUI.Reticle = {
    Update = UpdateReticle,
    Create = CreateReticle,
    Refresh = UpdateReticle,
    InvalidateCache = InvalidateCache,
}
