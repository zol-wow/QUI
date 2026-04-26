local ADDON_NAME, ns = ...
local QUICore = ns.Addon
local LSM = ns.LSM
local UIKit = ns.UIKit

local Helpers = ns.Helpers
local GetCore = Helpers.GetCore
local floor = math.floor

-- Pixel-snap with pre-computed pixel size (avoids per-call GetEffectiveScale in loops)
local function snapPx(value, px)
    if value == 0 then return 0 end
    return floor(value / px + 0.5) * px
end

-- Upvalue caching for hot-path performance
local type = type
local pairs = pairs
local ipairs = ipairs
local pcall = pcall
local math_floor = math.floor
local math_max = math.max
local math_min = math.min
local CreateFrame = CreateFrame
local InCombatLockdown = InCombatLockdown
local C_Timer = C_Timer
local GetTime = GetTime
local UnitCanAttack = UnitCanAttack
local tostring = tostring
local wipe = wipe
local table_insert = table.insert
local table_remove = table.remove
local string_format = string.format

-- Pre-create named frames so Edit Mode layout anchoring can resolve
-- "QUIPowerBar" / "QUISecondaryPowerBar" before full initialization.
-- GetPowerBar()/GetSecondaryPowerBar() will create the real frames later,
-- overwriting these globals.
if not _G[ADDON_NAME .. "PowerBar"] then
    CreateFrame("Frame", ADDON_NAME .. "PowerBar", UIParent):Hide()
end
if not _G[ADDON_NAME .. "SecondaryPowerBar"] then
    CreateFrame("Frame", ADDON_NAME .. "SecondaryPowerBar", UIParent):Hide()
end
-- Pre-create the bounding-box proxy frame ("QUIResourceBars") so anchored
-- elements (e.g., buff bars via GetTopVisibleResourceBarFrame) can reference
-- it before QUICore initialization finishes.  See GetOrCreateResourceBarsProxy
-- below for the live configuration applied during normal updates.
if not _G[ADDON_NAME .. "ResourceBars"] then
    local proxy = CreateFrame("Frame", ADDON_NAME .. "ResourceBars", UIParent)
    proxy:SetSize(1, 1)
    proxy:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    proxy:SetAlpha(1)  -- Frame draws nothing; alpha 1 keeps anchoring valid.
    if proxy.SetMouseClickEnabled then proxy:SetMouseClickEnabled(false) end
    if proxy.SetMouseMotionEnabled then proxy:SetMouseMotionEnabled(false) end
    proxy:Show()
end

-- Pixel-perfect scaling helper
local function Scale(x, frame)
    if QUICore and QUICore.Scale then
        return QUICore:Scale(x, frame)
    end
    return x
end

-- Check if CDM visibility says we should be hidden
local function IsCDMVisibilityHidden()
    -- Layout mode suspends all visibility rules
    if Helpers.IsLayoutModeActive() then return false end
    if _G.QUI_ShouldCDMBeVisible then
        return not _G.QUI_ShouldCDMBeVisible()
    end
    return false
end

-- Returns configured hidden alpha when CDM visibility is currently hidden.
-- nil means CDM visibility is not currently hiding the bars.
local function GetCDMHiddenAlpha()
    if Helpers.IsLayoutModeActive() then return nil end
    if _G.QUI_ShouldCDMBeVisible and not _G.QUI_ShouldCDMBeVisible() then
        local vis = QUICore and QUICore.db and QUICore.db.profile and QUICore.db.profile.cdmVisibility
        return (vis and vis.fadeOutAlpha) or 0
    end
    return nil
end

-- Avoid protected-frame errors in combat when bars become secure.
local SafeShow = Helpers.SafeShow
local SafeHide = Helpers.SafeHide

local function SafeSetFrameLevel(frame, frameLevel)
    if not frame or frameLevel == nil then return false end
    if frame.GetFrameLevel and frame:GetFrameLevel() == frameLevel then
        return true
    end
    if InCombatLockdown() and frame.IsProtected and frame:IsProtected() then
        return false
    end
    local ok = pcall(frame.SetFrameLevel, frame, frameLevel)
    return ok
end

-- Visibility check for resource bars ("always", "combat", "hostile")
local function ShouldShowBar(cfg)
    -- CDM visibility overrides (e.g. hide when mounted) take priority
    if IsCDMVisibilityHidden() then return false end

    local vis = cfg.visibility or "always"
    if vis == "always" then return true end
    if vis == "combat" then return InCombatLockdown() end
    if vis == "hostile" then
        return UnitExists("target") and UnitCanAttack("player", "target")
    end
    return true
end


-- Helper: Read CDM viewer state (taint-safe, avoids reading __cdm* frame properties).
-- Returns a table with iconWidth, totalHeight, row1Width, etc., or nil if unavailable.
local function GetViewerState(viewer)
    if not viewer then return nil end
    if _G.QUI_GetCDMViewerState then
        return _G.QUI_GetCDMViewerState(viewer)
    end
    return nil
end

-- Helper: Get raw content width from viewer state (before HUD min-width
-- inflation).  Resource bar content should match the actual icon content
-- span; the proxy handles min-width inflation independently.
local function GetRawContentWidth(vs)
    if not vs then return nil end
    return vs.rawContentWidth or vs.iconWidth
end

-- Helper: Get raw row width from viewer state (before HUD min-width inflation).
-- Row-specific raw widths are used when sizing resource bars that are locked
-- to a specific CDM viewer row.
local function GetRawRow1Width(vs)
    if not vs then return nil end
    return vs.rawRow1Width or vs.row1Width or vs.rawContentWidth or vs.iconWidth
end

local function GetRawBottomRowWidth(vs)
    if not vs then return nil end
    return vs.rawBottomRowWidth or vs.bottomRowWidth or vs.rawContentWidth or vs.iconWidth
end

-- Helper: Get last-known CDM viewer dimensions from DB.
-- Used as fallback when viewer state is temporarily nil (Edit Mode exit, etc.).
local function GetSavedViewerDims(viewerKey)
    local ncdm = QUICore and QUICore.db and QUICore.db.profile and QUICore.db.profile.ncdm
    if not ncdm then return 0, 0 end
    if viewerKey == "essential" then
        return ncdm._lastEssentialWidth or 0, ncdm._lastEssentialHeight or 0
    elseif viewerKey == "utility" then
        return ncdm._lastUtilityWidth or 0, ncdm._lastUtilityHeight or 0
    end
    return 0, 0
end

-- Locked-bar readiness flags.  When a bar is locked to a CDM viewer,
-- suppress visibility until the CDM has actually computed the correct
-- width.  This prevents a flash at a stale DB width on login/reload.
-- Set to true by QUI_UpdateLockedPowerBar / QUI_UpdateLockedSecondaryPowerBar
-- on their first successful run, or by a safety timeout.
local _primaryLockedReady = false
local _secondaryLockedReady = false

-- Helper to get texture from general settings (falls back to default)
local function GetDefaultTexture()
    if QUICore and QUICore.db and QUICore.db.profile and QUICore.db.profile.general then
        return QUICore.db.profile.general.texture or "Quazii"
    end
    return "Quazii"
end

-- Helper to get bar-specific texture (falls back to Solid)
local function GetBarTexture(cfg)
    if cfg and cfg.texture then
        return cfg.texture
    end
    return "Solid"
end

-- Helper to get font from general settings (uses shared helpers)
local GetGeneralFont = Helpers.GetGeneralFont
local GetGeneralFontOutline = Helpers.GetGeneralFontOutline

local function NormalizeTextAlign(align)
    if align == "LEFT" or align == "RIGHT" then
        return align
    end
    return "CENTER"
end

local function GetTextAnchorPointForAlign(align)
    local normalized = NormalizeTextAlign(align)
    if normalized == "LEFT" then
        return "LEFT", normalized
    elseif normalized == "RIGHT" then
        return "RIGHT", normalized
    end
    return "CENTER", normalized
end

local function FormatPercentValue(value, cfg)
    local pctSuffix = (cfg and cfg.hidePercentSymbol) and "" or "%"
    return string_format("%.0f%s", value or 0, pctSuffix)
end

local function ApplyPowerBarTextPlacement(bar, cfg)
    if not (bar and bar.TextValue and bar.TextFrame and QUICore and QUICore.PixelRound) then return end
    local anchorPoint, normalizedAlign = GetTextAnchorPointForAlign(cfg and cfg.textAlign)
    local textX = QUICore:PixelRound((cfg and cfg.textX) or 0, bar.TextValue)
    local textY = QUICore:PixelRound((cfg and cfg.textY) or 0, bar.TextValue)
    if bar._cachedTextX ~= textX or bar._cachedTextY ~= textY or bar._cachedTextAlign ~= normalizedAlign then
        bar.TextValue:ClearAllPoints()
        bar.TextValue:SetPoint(anchorPoint, bar.TextFrame, anchorPoint, textX, textY)
        bar.TextValue:SetJustifyH(normalizedAlign)
        bar._cachedTextX = textX
        bar._cachedTextY = textY
        bar._cachedTextAlign = normalizedAlign
    end
end


--TABLES

-- Custom power type IDs for aura-based resources (not Blizzard PowerTypes)
Enum.PowerType.MaelstromWeapon = 100
Enum.PowerType.VengSoulFragments = 101
Enum.PowerType.Whirlwind = 102       -- Fury Warrior Improved Whirlwind stacks
Enum.PowerType.TipOfTheSpear = 103   -- Survival Hunter Tip of the Spear stacks

---------------------------------------------------------------------------
-- WHIRLWIND STACK TRACKER (event-driven)
--
-- C_UnitAuras.GetPlayerAuraBySpellID(85739) is unreliable during combat.
-- Track stacks manually via UNIT_SPELLCAST_SUCCEEDED: generators set to max,
-- spenders decrement.
---------------------------------------------------------------------------
local WhirlwindTracker = {}
do
    local IW_MAX_STACKS = 4
    local IW_DURATION   = 20
    local IMPROVED_WW_TALENT = 12950

    -- Generators: set stacks to max
    local GENERATORS = {
        [190411] = true,  -- Whirlwind
        [6343]   = true,  -- Thunder Clap
        [435222] = true,  -- Thunder Blast
    }
    -- Thunder Clap/Blast require Crashing Thunder talent
    local CRASHING_THUNDER_TALENT = 436707

    -- Spenders: consume one stack
    local SPENDERS = {
        [23881]  = true,  -- Bloodthirst
        [85288]  = true,  -- Raging Blow
        [280735] = true,  -- Execute
        [202168] = true,  -- Impending Victory
        [184367] = true,  -- Rampage
        [335096] = true,  -- Bloodbath
        [335097] = true,  -- Crushing Blow
        [5308]   = true,  -- Execute (base)
    }
    -- Unhinged: BT/Bloodbath don't consume during Bladestorm
    local UNHINGED_TALENT = 386628

    local stacks    = 0
    local expiresAt = nil
    local seenGUID  = {}
    local pendingToken = 0

    do local mp = ns._memprobes or {}; ns._memprobes = mp; mp[#mp + 1] = { name = "RB_WW_seenGUID", tbl = seenGUID } end

    function WhirlwindTracker:GetStacks()
        -- Expire stale stacks
        if expiresAt and GetTime() >= expiresAt then
            stacks = 0
            expiresAt = nil
        end
        -- Check talent
        if not C_SpellBook or not C_SpellBook.IsSpellKnown(IMPROVED_WW_TALENT) then
            return nil, 0  -- talent not learned
        end
        return IW_MAX_STACKS, stacks
    end

    function WhirlwindTracker:Reset()
        stacks = 0
        expiresAt = nil
        wipe(seenGUID)
        pendingToken = pendingToken + 1
    end

    function WhirlwindTracker:OnSpellCast(spellID, castGUID)
        if castGUID and seenGUID[castGUID] then return end
        if castGUID then seenGUID[castGUID] = true end

        -- Generator
        if GENERATORS[spellID] then
            -- Thunder Clap/Blast need Crashing Thunder talent
            if (spellID == 6343 or spellID == 435222) then
                if not C_SpellBook.IsSpellKnown(CRASHING_THUNDER_TALENT) then
                    return
                end
            end
            -- Delayed grant (matches game behavior)
            pendingToken = pendingToken + 1
            local myToken = pendingToken
            C_Timer.After(0.15, function()
                if myToken ~= pendingToken then return end
                stacks = IW_MAX_STACKS
                expiresAt = GetTime() + IW_DURATION
                -- Force immediate resource bar update
                if QUICore and QUICore.UpdateSecondaryPowerBar then
                    QUICore:UpdateSecondaryPowerBar()
                end
            end)
            return
        end

        -- Spender
        if SPENDERS[spellID] then
            -- Unhinged: BT/Bloodbath don't consume during Bladestorm
            if (spellID == 23881 or spellID == 335096) then
                if C_SpellBook.IsSpellKnown(UNHINGED_TALENT) then
                    local ok, usable = pcall(C_Spell.IsSpellUsable, 446035)
                    if ok and not usable then return end
                end
            end
            if stacks > 0 then
                stacks = stacks - 1
                if stacks == 0 then expiresAt = nil end
                -- Force immediate resource bar update
                if QUICore and QUICore.UpdateSecondaryPowerBar then
                    QUICore:UpdateSecondaryPowerBar()
                end
            end
            return
        end
    end

    -- Event frame: only active for Fury Warriors
    local wwFrame = CreateFrame("Frame")
    wwFrame:RegisterEvent("ADDON_LOADED")
    wwFrame:SetScript("OnEvent", function(self, event, ...)
        if event == "ADDON_LOADED" then
            local addonName = ...
            if addonName ~= ADDON_NAME then return end
            self:UnregisterEvent("ADDON_LOADED")
        end
        if event == "ADDON_LOADED" or event == "ACTIVE_PLAYER_SPECIALIZATION_CHANGED"
            or event == "PLAYER_SPECIALIZATION_CHANGED" then
            local _, class = UnitClass("player")
            local spec = GetSpecialization()
            -- Fury = spec 2
            if class == "WARRIOR" and spec == 2 then
                self:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
                self:RegisterEvent("PLAYER_DEAD")
                self:RegisterEvent("PLAYER_REGEN_ENABLED")
            else
                self:UnregisterEvent("UNIT_SPELLCAST_SUCCEEDED")
                self:UnregisterEvent("PLAYER_DEAD")
                self:UnregisterEvent("PLAYER_REGEN_ENABLED")
                WhirlwindTracker:Reset()
            end
        elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
            local unit, castGUID, spellID = ...
            if unit == "player" then
                WhirlwindTracker:OnSpellCast(spellID, castGUID)
            end
        elseif event == "PLAYER_DEAD" then
            WhirlwindTracker:Reset()
        elseif event == "PLAYER_REGEN_ENABLED" then
            -- Combat ended: clear pending token to prevent stale delayed grants,
            -- and clear GUID cache to prevent memory growth.
            pendingToken = pendingToken + 1
            wipe(seenGUID)
        end
    end)
    wwFrame:RegisterEvent("ACTIVE_PLAYER_SPECIALIZATION_CHANGED")
    wwFrame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
end

---------------------------------------------------------------------------
-- TIP OF THE SPEAR STACK TRACKER (event-driven)
--
-- Same pattern as Whirlwind: aura API unreliable during combat.
-- Kill Command grants 1 stack (2 with Primal Surge), spenders consume 1.
---------------------------------------------------------------------------
local TipOfTheSpearTracker = {}
do
    local TIP_MAX_STACKS = 3
    local TIP_DURATION   = 10
    local TIP_TALENT     = 260285

    -- Generators
    local KILL_COMMAND    = 259489
    local TAKEDOWN        = 1250646
    local PRIMAL_SURGE    = 1272154  -- talent: Kill Command grants 2 stacks
    local TWIN_FANG       = 1272139  -- talent: Takedown grants 2 stacks

    -- Spenders: consume one stack
    local SPENDERS = {
        [186270]  = true,  -- Raptor Strike
        [1262293] = true,  -- Raptor Swipe
        [1261193] = true,  -- Boomstick
        [1253859] = true,  -- Takedown
        [259495]  = true,  -- Wildfire Bomb
        [193265]  = true,  -- Hatchet Toss
        [1264949] = true,  -- Chakram
        [1262343] = true,  -- Ranged Raptor Swipe
        [265189]  = true,  -- Ranged Raptor Strike
        [1251592] = true,  -- Flamefang Pitch
    }

    local stacks    = 0
    local expiresAt = nil

    function TipOfTheSpearTracker:GetStacks()
        if expiresAt and GetTime() >= expiresAt then
            stacks = 0
            expiresAt = nil
        end
        if not C_SpellBook or not C_SpellBook.IsSpellKnown(TIP_TALENT) then
            return nil, 0
        end
        return TIP_MAX_STACKS, stacks
    end

    function TipOfTheSpearTracker:Reset()
        stacks = 0
        expiresAt = nil
    end

    function TipOfTheSpearTracker:OnSpellCast(spellID)
        if not C_SpellBook.IsSpellKnown(TIP_TALENT) then return end

        -- Kill Command: +1 (or +2 with Primal Surge)
        if spellID == KILL_COMMAND then
            local gain = C_SpellBook.IsSpellKnown(PRIMAL_SURGE) and 2 or 1
            stacks = math_min(TIP_MAX_STACKS, stacks + gain)
            expiresAt = GetTime() + TIP_DURATION
            if QUICore and QUICore.UpdateSecondaryPowerBar then
                QUICore:UpdateSecondaryPowerBar()
            end
            return
        end

        -- Takedown: +2 with Twin Fang talent
        if spellID == TAKEDOWN and C_SpellBook.IsSpellKnown(TWIN_FANG) then
            stacks = math_min(TIP_MAX_STACKS, stacks + 2)
            expiresAt = GetTime() + TIP_DURATION
            if QUICore and QUICore.UpdateSecondaryPowerBar then
                QUICore:UpdateSecondaryPowerBar()
            end
            return
        end

        -- Spender: consume one stack
        if SPENDERS[spellID] then
            if stacks > 0 then
                stacks = stacks - 1
                if stacks == 0 then expiresAt = nil end
                if QUICore and QUICore.UpdateSecondaryPowerBar then
                    QUICore:UpdateSecondaryPowerBar()
                end
            end
            return
        end
    end

    local tipFrame = CreateFrame("Frame")
    tipFrame:RegisterEvent("ADDON_LOADED")
    tipFrame:SetScript("OnEvent", function(self, event, ...)
        if event == "ADDON_LOADED" then
            local addonName = ...
            if addonName ~= ADDON_NAME then return end
            self:UnregisterEvent("ADDON_LOADED")
        end
        if event == "ADDON_LOADED" or event == "ACTIVE_PLAYER_SPECIALIZATION_CHANGED"
            or event == "PLAYER_SPECIALIZATION_CHANGED" then
            local _, class = UnitClass("player")
            local spec = GetSpecialization()
            -- Survival = spec 3
            if class == "HUNTER" and spec == 3 then
                self:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
                self:RegisterEvent("PLAYER_DEAD")
            else
                self:UnregisterEvent("UNIT_SPELLCAST_SUCCEEDED")
                self:UnregisterEvent("PLAYER_DEAD")
                TipOfTheSpearTracker:Reset()
            end
        elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
            local unit, _, spellID = ...
            if unit == "player" then
                TipOfTheSpearTracker:OnSpellCast(spellID)
            end
        elseif event == "PLAYER_DEAD" then
            TipOfTheSpearTracker:Reset()
        end
    end)
    tipFrame:RegisterEvent("ACTIVE_PLAYER_SPECIALIZATION_CHANGED")
    tipFrame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
end

local VDH_SOUL_FRAGMENTS_POWER = (Enum.PowerType and type(Enum.PowerType.SoulFragments) == "number") and Enum.PowerType.SoulFragments or nil

local tocVersion = select(4, GetBuildInfo())
local HAS_UNIT_POWER_PERCENT = type(UnitPowerPercent) == "function"

-- Power percent with 12.01 API compatibility
-- API signature changed: old (unit, powerType, scaleTo100) -> new (unit, powerType, usePredicted, curve)
local function GetPowerPct(unit, powerType, usePredicted)
    if (tonumber(tocVersion) or 0) >= 120000 and HAS_UNIT_POWER_PERCENT then
        local ok, pct
        -- 12.01+: Use curve parameter (new API)
        if CurveConstants and CurveConstants.ScaleTo100 then
            ok, pct = pcall(UnitPowerPercent, unit, powerType, usePredicted, CurveConstants.ScaleTo100)
        end
        -- Fallback for older builds
        if not ok or pct == nil then
            ok, pct = pcall(UnitPowerPercent, unit, powerType, usePredicted)
        end
        if ok and pct ~= nil then
            return pct
        end
    end
    -- Manual calculation fallback (UnitPower/UnitPowerMax can return secret values in 12.0.x)
    local ok, result = pcall(function()
        local cur = UnitPower(unit, powerType)
        local max = UnitPowerMax(unit, powerType)
        if cur and max and max > 0 then return (cur / max) * 100 end
    end)
    return ok and result or nil
end

local tickedPowerTypes = {
    [Enum.PowerType.ArcaneCharges] = true,
    [Enum.PowerType.Chi] = true,
    [Enum.PowerType.ComboPoints] = true,
    [Enum.PowerType.Essence] = true,
    [Enum.PowerType.HolyPower] = true,
    [Enum.PowerType.Runes] = true,
    [Enum.PowerType.SoulShards] = true,
    [Enum.PowerType.MaelstromWeapon] = true,
    [Enum.PowerType.VengSoulFragments] = true,
    [Enum.PowerType.Whirlwind] = true,
    [Enum.PowerType.TipOfTheSpear] = true,
}
if VDH_SOUL_FRAGMENTS_POWER then
    tickedPowerTypes[VDH_SOUL_FRAGMENTS_POWER] = true
end

local fragmentedPowerTypes = {
    [Enum.PowerType.Runes] = true,
    [Enum.PowerType.Essence] = true,
}

-- Smooth rune timer update state
local runeUpdateElapsed = 0
local runeUpdateRunning = false

-- Essence regen timer state (timer-based extrapolation)
local essenceUpdateElapsed = 0
local essenceUpdateRunning = false
local essenceNextTick = nil      -- GetTime() when next essence will be ready
local essenceLastCount = nil     -- last integer essence count (detect gains)
local essenceTickDuration = nil  -- seconds per essence regen tick

-- Rune text format cache: only call string.format when the truncated value changes
local _lastRuneRounded = {}    -- [runeIndex] = last math_floor(remaining * 10) value
local _lastRuneFormatted = {}  -- [runeIndex] = last formatted string

-- Event throttle (16ms = ~60 FPS, smooth updates while managing CPU)
local UPDATE_THROTTLE = 0.016
local lastPrimaryUpdate = 0
local lastSecondaryUpdate = 0

-- Discrete resources that need instant feedback (no throttle)
-- These change infrequently and users expect immediate visual response
local instantFeedbackTypes = {
    [Enum.PowerType.HolyPower] = true,
    [Enum.PowerType.ComboPoints] = true,
    [Enum.PowerType.Chi] = true,
    [Enum.PowerType.Runes] = true,
    [Enum.PowerType.ArcaneCharges] = true,
    [Enum.PowerType.Essence] = true,
    [Enum.PowerType.SoulShards] = true,
    [Enum.PowerType.MaelstromWeapon] = true,
    [Enum.PowerType.VengSoulFragments] = true,
    [Enum.PowerType.Whirlwind] = true,
    [Enum.PowerType.TipOfTheSpear] = true,
}
if VDH_SOUL_FRAGMENTS_POWER then
    instantFeedbackTypes[VDH_SOUL_FRAGMENTS_POWER] = true
end

-- Druid utility forms (show spec resource instead of form resource)
local druidUtilityForms = {
    [0]  = true,  -- Human/Caster
    [2]  = true,  -- Tree of Life (Resto talent)
    [3]  = true,  -- Travel (ground)
    [4]  = true,  -- Aquatic
    [27] = true,  -- Swift Flight Form
    [29] = true,  -- Flight Form
    [36] = true,  -- Treant (cosmetic)
}

-- Druid spec primary resources
local druidSpecResource = {
    [1] = Enum.PowerType.LunarPower,  -- Balance
    [2] = Enum.PowerType.Energy,       -- Feral
    [3] = Enum.PowerType.Rage,         -- Guardian
    [4] = Enum.PowerType.Mana,         -- Restoration
}

-- Spec info for the "Swap Secondary to Primary Position" feature
-- Used by both runtime checks and the options UI (via namespace export)
local SwapCandidateSpecs = {
    { specID = 102,  name = "Balance",      classColor = "FF7C0A" },  -- Druid
    { specID = 251,  name = "Frost",        classColor = "C41E3A" },  -- Death Knight
    { specID = 1467, name = "Devastation",  classColor = "33937F" },  -- Evoker
    { specID = 1473, name = "Augmentation", classColor = "33937F" },  -- Evoker
    { specID = 66,   name = "Protection",   classColor = "F48CBA" },  -- Paladin
    { specID = 70,   name = "Retribution",  classColor = "F48CBA" },  -- Paladin
    { specID = 265,  name = "Affliction",   classColor = "8788EE" },  -- Warlock
    { specID = 266,  name = "Demonology",   classColor = "8788EE" },  -- Warlock
    { specID = 267,  name = "Destruction",  classColor = "8788EE" },  -- Warlock
    { specID = 263,  name = "Enhancement",  classColor = "0070DD" },  -- Shaman
}
ns.SwapCandidateSpecs = SwapCandidateSpecs
local SwapCandidateSpecByID = {}
for _, info in ipairs(SwapCandidateSpecs) do
    SwapCandidateSpecByID[info.specID] = true
end

local function IsSwapCandidateSpec(specID)
    return specID and SwapCandidateSpecByID[specID] or false
end

local function ShouldSwapBars()
    local cfg = QUICore and QUICore.db and QUICore.db.profile and QUICore.db.profile.secondaryPowerBar
    if not cfg or not cfg.swapToPrimaryPosition then return false end
    local spec = GetSpecialization()
    if not spec then return false end
    local specID = GetSpecializationInfo(spec)
    if not IsSwapCandidateSpec(specID) then return false end
    return cfg.swapSpecs and cfg.swapSpecs[specID] or false
end

local function ShouldHidePrimaryOnSwap()
    local cfg = QUICore and QUICore.db and QUICore.db.profile and QUICore.db.profile.secondaryPowerBar
    if not cfg or not cfg.swapToPrimaryPosition or not cfg.hidePrimaryOnSwap then return false end
    local spec = GetSpecialization()
    if not spec then return false end
    local specID = GetSpecializationInfo(spec)
    if not specID then return false end
    if not IsSwapCandidateSpec(specID) then return false end
    local swapEnabled = cfg.swapSpecs and cfg.swapSpecs[specID]
    local hideEnabled = cfg.hideSpecs and cfg.hideSpecs[specID]
    return (swapEnabled and hideEnabled) or false
end

-- ========================================================================
-- BOUNDING-BOX PROXY + NATURAL SLOT MATH
-- ========================================================================
-- The "natural slot" of a bar is where it would sit if the swap-to-primary
-- mechanic were OFF.  Slot computation is purely config-driven (independent
-- of live frame state) so callers can predict positions without needing the
-- target bar to already be laid out.  This is critical for the swap math:
-- to put each bar where the OTHER would naturally be, we need both natural
-- positions before either bar has been moved.
--
-- Asymmetry note:
--   * Primary in lockedToEssential/Utility: NCDM writes computed CDM-anchored
--     position into cfg.offsetX/Y directly.  So (offsetX, offsetY) IS the
--     natural slot center.
--   * Secondary in lockedToEssential/Utility: NCDM writes the computed
--     CDM-anchored base into cfg.lockedBaseX/Y, and cfg.offsetX/Y is the
--     user's nudge on top.  Natural slot center = lockedBase + offset.

-- Effective orientation of the primary bar (resolves AUTO via CDM viewer).
local function GetPrimaryEffectiveVertical()
    local cfg = QUICore and QUICore.db and QUICore.db.profile and QUICore.db.profile.powerBar
    if not cfg then return false end
    local orientation = cfg.orientation or "AUTO"
    if orientation == "VERTICAL" then return true end
    if orientation == "HORIZONTAL" then return false end
    if cfg.lockedToEssential then
        local viewer = _G.QUI_GetCDMViewerFrame and _G.QUI_GetCDMViewerFrame("essential")
        local vs = viewer and GetViewerState(viewer)
        return (vs and vs.layoutDir) == "VERTICAL"
    elseif cfg.lockedToUtility then
        local viewer = _G.QUI_GetCDMViewerFrame and _G.QUI_GetCDMViewerFrame("utility")
        local vs = viewer and GetViewerState(viewer)
        return (vs and vs.layoutDir) == "VERTICAL"
    end
    return false
end

-- Resolve a length (= bar's main-axis size in config space) from a cfg.width
-- value.  When width is missing or 0, fall back to CDM raw content width then
-- the saved last-known width.
local function ResolveBarLength(width)
    if width and width > 0 then return width end
    local viewer = _G.QUI_GetCDMViewerFrame and _G.QUI_GetCDMViewerFrame("essential")
    if viewer then
        local vs = GetViewerState(viewer)
        local w = GetRawContentWidth(vs)
        if w and w > 0 then return w end
    end
    local ncdm = QUICore and QUICore.db and QUICore.db.profile and QUICore.db.profile.ncdm
    local saved = ncdm and ncdm._lastEssentialWidth
    if saved and saved > 0 then return saved end
    return 200
end

-- Outer thickness (height + 2*border) of the primary bar.
local function GetPrimaryOuterThickness()
    local cfg = QUICore and QUICore.db and QUICore.db.profile and QUICore.db.profile.powerBar
    if not cfg then return 8 end
    return (cfg.height or 8) + (2 * (cfg.borderSize or 1))
end

-- Outer thickness (height + 2*border) of the secondary bar.
local function GetSecondaryOuterThickness()
    local cfg = QUICore and QUICore.db and QUICore.db.profile and QUICore.db.profile.secondaryPowerBar
    if not cfg then return 8 end
    return (cfg.height or 8) + (2 * (cfg.borderSize or 1))
end

-- Compute the primary bar's natural slot.  Returns (centerX, centerY, length, thickness).
-- centerX/Y are screen-relative offsets from UIParent CENTER.
local function ComputePrimaryNaturalSlot()
    local cfg = QUICore and QUICore.db and QUICore.db.profile and QUICore.db.profile.powerBar
    if not cfg then return 0, 0, 0, 0 end
    local cx = cfg.offsetX or 0
    local cy = cfg.offsetY or 0
    local thickness = GetPrimaryOuterThickness()
    local length = ResolveBarLength(cfg.width)
    return cx, cy, length, thickness
end

-- Compute the secondary bar's natural slot.  Returns (centerX, centerY, length, thickness).
-- Independent of swap state.  Handles all lock modes including lockedToPrimary
-- (which is computed off the primary's CONFIG slot, not its live frame).
local function ComputeSecondaryNaturalSlot()
    local cfg = QUICore and QUICore.db and QUICore.db.profile and QUICore.db.profile.secondaryPowerBar
    if not cfg then return 0, 0, 0, 0 end
    local thickness = GetSecondaryOuterThickness()
    local userOffsetX = cfg.offsetX or 0
    local userOffsetY = cfg.offsetY or 0

    if cfg.lockedToPrimary then
        local pcx, pcy, plen, pT = ComputePrimaryNaturalSlot()
        local isVertical = GetPrimaryEffectiveVertical()
        if isVertical then
            -- Secondary stacks to the RIGHT of primary
            return pcx + (pT / 2) + (thickness / 2) + userOffsetX,
                   pcy + userOffsetY,
                   plen,
                   thickness
        else
            -- Secondary stacks ABOVE primary
            return pcx + userOffsetX,
                   pcy + (pT / 2) + (thickness / 2) + userOffsetY,
                   plen,
                   thickness
        end
    elseif cfg.lockedToEssential or cfg.lockedToUtility then
        local cx = (cfg.lockedBaseX or 0) + userOffsetX
        local cy = (cfg.lockedBaseY or 0) + userOffsetY
        return cx, cy, ResolveBarLength(cfg.width), thickness
    else
        return userOffsetX, userOffsetY, ResolveBarLength(cfg.width), thickness
    end
end

-- Given primary and secondary natural slots, compute the position each bar
-- should occupy when swap is active so the COMBINED outer bounding box
-- remains identical (same union rectangle, same snap-gap between bars).
--
-- Each bar moves to the OTHER's slot, then is shifted along the stack axis
-- by (otherThickness - ownThickness)/2 in the "outward" direction so that
-- the bar's outer-edge facing the bbox boundary stays aligned with the
-- original slot's same-direction edge.
local function ComputeSwappedCenters(pcx, pcy, pT, scx, scy, sT, isVertical)
    local primaryNewCx, primaryNewCy = scx, scy
    local secondaryNewCx, secondaryNewCy = pcx, pcy
    if isVertical then
        local outwardDir = (scx >= pcx) and 1 or -1
        local shift = outwardDir * (sT - pT) / 2
        primaryNewCx = scx + shift
        secondaryNewCx = pcx + shift
    else
        local outwardDir = (scy >= pcy) and 1 or -1
        local shift = outwardDir * (sT - pT) / 2
        primaryNewCy = scy + shift
        secondaryNewCy = pcy + shift
    end
    return primaryNewCx, primaryNewCy, secondaryNewCx, secondaryNewCy
end

-- Internal proxy frame ("QUIResourceBars") representing the combined outer
-- bounding box of primary + secondary in their VISIBLE configuration.
--
-- * In normal mode: the union of both bars' outer rectangles.
-- * In swap mode (no hide): same as normal — bars exchange slots but the
--   union doesn't change, so the proxy stays put.
-- * In hidePrimaryOnSwap: shrinks to the secondary's visible area (which
--   occupies primary's natural slot).
--
-- Hidden/internal: never registered in the user-facing anchoring UI.  Used
-- by GetTopVisibleResourceBarFrame() in buffbar so anchored elements follow
-- the proxy across swap toggles instead of jumping with individual bars.
local function GetOrCreateResourceBarsProxy()
    if QUICore.resourceBars then return QUICore.resourceBars end
    local proxy = _G[ADDON_NAME .. "ResourceBars"]
    if not proxy then
        proxy = CreateFrame("Frame", ADDON_NAME .. "ResourceBars", UIParent)
    end
    proxy:SetFrameStrata("BACKGROUND")
    proxy:SetSize(1, 1)
    -- Alpha 1 because Frame itself draws nothing; consumers like
    -- IsFrameVisiblyShown reject alpha=0 frames as anchor targets.  Real
    -- invisibility comes from the proxy not containing any textures/regions.
    proxy:SetAlpha(1)
    if proxy.SetMouseClickEnabled then proxy:SetMouseClickEnabled(false) end
    if proxy.SetMouseMotionEnabled then proxy:SetMouseMotionEnabled(false) end
    proxy:ClearAllPoints()
    proxy:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    proxy:Show()  -- Must be Shown so layout computes.
    QUICore.resourceBars = proxy
    return proxy
end

-- Returns true if a bar frame is "really" contributing to the visible layout
-- (Shown AND alpha > 0).  Bars use alpha=0 for transient hides (CDM
-- visibility, swap-hidden primary, etc.) and we must NOT include those in
-- the proxy bbox or anchored elements would jump to invisible regions.
local function IsBarVisuallyShown(bar)
    if not bar then return false end
    local ok, shown = pcall(function() return bar:IsShown() end)
    if not ok or not shown then return false end
    local okA, alpha = pcall(function() return bar:GetEffectiveAlpha() end)
    if not okA then return false end
    return type(alpha) == "number" and alpha > 0.01
end

-- Get a bar's actual UIParent-relative outer rectangle from live frame state.
-- Returns (centerX, centerY, width, height) where centerX/Y are offsets from
-- UIParent's center.  Returns nil if the frame isn't laid out yet.
local function GetLiveBarRect(bar)
    if not bar then return nil end
    local okC, cx, cy = pcall(function() return bar:GetCenter() end)
    if not okC or type(cx) ~= "number" or type(cy) ~= "number" then return nil end
    local okW, w = pcall(function() return bar:GetWidth() end)
    local okH, h = pcall(function() return bar:GetHeight() end)
    if not okW or not okH or type(w) ~= "number" or type(h) ~= "number" or w <= 1 or h <= 1 then
        return nil
    end
    local okU, scx, scy = pcall(function() return UIParent:GetCenter() end)
    if not okU or type(scx) ~= "number" or type(scy) ~= "number" then return nil end
    return cx - scx, cy - scy, w, h
end

-- ========================================================================
-- LIVE NATURAL-SLOT CAPTURE
-- ========================================================================
-- The "natural slot" of a bar is where it would be drawn if swap were OFF.
-- For users who have positioned bars via Layout Mode (saved frame anchors)
-- the cfg.offsetX/offsetY values DO NOT reflect the bar's actual on-screen
-- position — the anchoring system places the bar relative to its anchor
-- target.  Swapping by cfg coordinates would teleport the bars away from
-- the user's chosen layout.
--
-- To swap correctly, we snapshot each bar's live UIParent-relative center
-- whenever we know swap is OFF (i.e. each bar IS at its natural slot).  Swap
-- math then uses those snapshots so the swapped bars stay inside the same
-- combined bounding box the user laid out.
local _capturedNaturalPrimary = nil   -- {cx, cy, w, h, isVertical}
local _capturedNaturalSecondary = nil

local function CaptureLiveBarSlot(bar)
    local cx, cy, w, h = GetLiveBarRect(bar)
    if not cx then return nil end
    return { cx = cx, cy = cy, w = w, h = h }
end

-- Snapshot whichever bars are currently at their natural slots (i.e. swap
-- is not currently being applied to them).  Called BEFORE we re-evaluate
-- the swap state so the snapshot reflects the user-laid-out positions.
local function CaptureNaturalSlotsIfPossible()
    if ShouldSwapBars() then return end  -- bars are in swap mode; positions aren't natural
    if InCombatLockdown() then return end
    if QUICore and QUICore.powerBar then
        local snap = CaptureLiveBarSlot(QUICore.powerBar)
        if snap then _capturedNaturalPrimary = snap end
    end
    if QUICore and QUICore.secondaryPowerBar then
        local snap = CaptureLiveBarSlot(QUICore.secondaryPowerBar)
        if snap then _capturedNaturalSecondary = snap end
    end
end

-- Throttled deferred capture: the anchoring system reapplies positions on a
-- ~0.15s debounce after our SetPoint calls, so capturing immediately after
-- UpdatePowerBar would record cfg-only coordinates (wrong for users with
-- saved frame anchors).  Schedule a capture slightly past the debounce
-- window so we record the actual final on-screen position.
local _captureScheduled = false
local function ScheduleNaturalSlotCapture()
    if _captureScheduled then return end
    if ShouldSwapBars() then return end
    _captureScheduled = true
    C_Timer.After(0.25, function()
        _captureScheduled = false
        CaptureNaturalSlotsIfPossible()
    end)
end

-- ========================================================================
-- BOOTSTRAP FOR FIRST-RELOAD-WITH-SWAP-ON
-- ========================================================================
-- When the user reloads with swap already enabled, swap math runs on the
-- first frame using cfg.offsetX/Y / cfg.lockedBaseX/Y.  Two failure modes:
--   1. NCDM ordering — primary NCDM may run before secondary's, so primary's
--      swap target reads stale (zero) secondary base.
--   2. Layout-Mode anchored bars — cfg.offsetX/Y is meaningless when the
--      anchoring system is positioning the bar; the captured live position
--      is the authoritative natural slot, but no capture exists yet.
--
-- Fix: bootstrap a natural-slot pass once shortly after world entry.  We
-- temporarily force the swap math OFF (via _swapBootstrapForcingNatural),
-- run Update*PowerBar so the bars land at their true natural slots (frame
-- anchors honored, NCDM computed), capture those positions, then release
-- the override and re-run with swap fully applied.
local _swapBootstrapForcingNatural = false
local _swapBootstrapDone = false
local _swapBootstrapPending = false

local function BothLockedBarsReady()
    if not QUICore or not QUICore.db or not QUICore.db.profile then return false end
    local pcfg = QUICore.db.profile.powerBar
    local scfg = QUICore.db.profile.secondaryPowerBar
    if pcfg and (pcfg.lockedToEssential or pcfg.lockedToUtility) and not _primaryLockedReady then
        return false
    end
    if scfg and (scfg.lockedToEssential or scfg.lockedToUtility) and not _secondaryLockedReady then
        return false
    end
    return true
end

-- Public wrapper queried by Update*PowerBar swap branches to know whether
-- the caller should bypass swap for the bootstrap natural-slot pass.
local function IsForcingNaturalDuringBootstrap()
    return _swapBootstrapForcingNatural
end

local function ScheduleSwapBootstrap()
    if _swapBootstrapDone or _swapBootstrapPending then return end
    if not ShouldSwapBars() then
        _swapBootstrapDone = true
        return
    end
    _swapBootstrapPending = true
    -- 0.6s lets NCDM updates settle (they fire shortly after CDM is laid
    -- out, typically within a few frames of PLAYER_ENTERING_WORLD).
    C_Timer.After(0.6, function()
        _swapBootstrapPending = false
        if InCombatLockdown() then
            -- Geometry calls are protected; retry post-combat.
            ScheduleSwapBootstrap()
            return
        end
        if not BothLockedBarsReady() then
            -- One side hasn't initialized yet; wait another 0.6s.
            ScheduleSwapBootstrap()
            return
        end
        -- Phase 1: force a natural-slot pass and capture live positions so
        -- swap math has authoritative slot data.
        _swapBootstrapForcingNatural = true
        if QUICore and QUICore.UpdatePowerBar then QUICore:UpdatePowerBar() end
        if QUICore and QUICore.UpdateSecondaryPowerBar then QUICore:UpdateSecondaryPowerBar() end
        -- Phase 2: after the anchoring system has reapplied frame anchors
        -- (~0.15s debounce), capture the final settled positions and apply
        -- swap.
        C_Timer.After(0.3, function()
            if InCombatLockdown() then
                _swapBootstrapForcingNatural = false
                ScheduleSwapBootstrap()
                return
            end
            if QUICore and QUICore.powerBar then
                local snap = CaptureLiveBarSlot(QUICore.powerBar)
                if snap then _capturedNaturalPrimary = snap end
            end
            if QUICore and QUICore.secondaryPowerBar then
                local snap = CaptureLiveBarSlot(QUICore.secondaryPowerBar)
                if snap then _capturedNaturalSecondary = snap end
            end
            _swapBootstrapForcingNatural = false
            _swapBootstrapDone = true
            -- Force a fresh swap-applied pass: clear caches so the SetPoint
            -- check inside Update*PowerBar can't match the natural-slot
            -- coordinates and skip applying swap.  Inline cache reset to
            -- avoid forward-reference to ResetBarPositionCache (declared
            -- later in this file).
            if QUICore then
                local pBar = QUICore.powerBar
                if pBar then
                    pBar._cachedX = nil
                    pBar._cachedY = nil
                    pBar._cachedAnchor = nil
                    pBar._cachedAutoMode = nil
                end
                local sBar = QUICore.secondaryPowerBar
                if sBar then
                    sBar._cachedX = nil
                    sBar._cachedY = nil
                    sBar._cachedAnchor = nil
                    sBar._cachedAutoMode = nil
                end
            end
            if QUICore and QUICore.UpdatePowerBar then QUICore:UpdatePowerBar() end
            if QUICore and QUICore.UpdateSecondaryPowerBar then QUICore:UpdateSecondaryPowerBar() end
        end)
    end)
end

-- Get the primary's natural slot, preferring the live capture taken while
-- swap was OFF.  Falls back to config-based math when no capture exists yet
-- (first frame after addon load).  Returns (cx, cy, length, thickness).
local function GetPrimaryNaturalSlotForSwap()
    local isVertical = GetPrimaryEffectiveVertical()
    local cap = _capturedNaturalPrimary
    if cap then
        local length, thickness
        if isVertical then
            length, thickness = cap.h, cap.w
        else
            length, thickness = cap.w, cap.h
        end
        return cap.cx, cap.cy, length, thickness
    end
    return ComputePrimaryNaturalSlot()
end

local function GetSecondaryNaturalSlotForSwap()
    -- Secondary's effective orientation can differ when locked to primary or
    -- a CDM viewer; fall back to primary's orientation as a reasonable proxy
    -- (only used to map captured w/h to length/thickness).
    local isVertical = GetPrimaryEffectiveVertical()
    local cap = _capturedNaturalSecondary
    if cap then
        local length, thickness
        if isVertical then
            length, thickness = cap.h, cap.w
        else
            length, thickness = cap.w, cap.h
        end
        return cap.cx, cap.cy, length, thickness
    end
    return ComputeSecondaryNaturalSlot()
end

-- ========================================================================
-- ANCHORING SYSTEM HANDOFF FOR SWAP
-- ========================================================================
-- When a user has positioned the resource bars via Layout Mode, their
-- frameAnchoring entries cause the anchoring system to actively reapply
-- positions on every UpdateAnchoredFrames pass.  Without coordination,
-- our swap SetPoint calls get overwritten ~150ms later by the debounced
-- reapply, so swap looks like a no-op to the user.
--
-- Solution: while swap is active, claim both bars' anchor keys so the
-- anchoring system skips them.  When swap turns off, release the claim
-- and force a re-apply so the bars snap back to the user's saved anchors.
local _swapOwnershipActive = false

-- Reset position-cache fields on a bar so the next Update*PowerBar pass
-- always re-applies SetPoint, even if the new desired offset happens to
-- equal the previously cached offset (e.g. swap toggle round-trip lands
-- the bar back at the same coordinates after lockedToPrimary maths).
local function ResetBarPositionCache(bar)
    if not bar then return end
    bar._cachedX = nil
    bar._cachedY = nil
    bar._cachedAnchor = nil
    bar._cachedAutoMode = nil
end

local function SyncSwapAnchorOwnership(active)
    local transitioning = (active ~= _swapOwnershipActive)

    if transitioning then
        -- Clearing caches guarantees the next swap-on/off pass calls
        -- ClearAllPoints+SetPoint regardless of cached coordinates.  This
        -- defends against silent toggle no-ops once stale autoMode strings
        -- happen to coincide with new coordinates in rare layouts.
        if QUICore then
            ResetBarPositionCache(QUICore.powerBar)
            ResetBarPositionCache(QUICore.secondaryPowerBar)
        end
    end

    if active then
        _swapOwnershipActive = true
        if _G.QUI_ClaimAnchorKey then
            _G.QUI_ClaimAnchorKey("primaryPower", true)
            _G.QUI_ClaimAnchorKey("secondaryPower", true)
        end
    else
        if not _swapOwnershipActive then
            -- Already released; nothing to undo, but if a transition snuck
            -- through (e.g. bars cleared but state was already false), skip
            -- the rest cleanly.
            return
        end
        _swapOwnershipActive = false
        if _G.QUI_ClaimAnchorKey then
            _G.QUI_ClaimAnchorKey("primaryPower", false)
            _G.QUI_ClaimAnchorKey("secondaryPower", false)
        end
        if _G.QUI_ForceReapplyFrameAnchor then
            _G.QUI_ForceReapplyFrameAnchor("primaryPower")
            _G.QUI_ForceReapplyFrameAnchor("secondaryPower")
        end
    end

    -- On every transition, notify dependents (unit frames anchored to
    -- power bars, buff bars, frame anchors) so they re-resolve which bar
    -- now occupies a given slot.  This is required for the swap-aware
    -- "anchor follows the bbox slot" behavior in GetSwapAwareBarFor.
    if transitioning then
        if _G.QUI_UpdateAnchoredUnitFrames then
            pcall(_G.QUI_UpdateAnchoredUnitFrames)
        end
        if _G.QUI_UpdateAnchoredFrames then
            pcall(_G.QUI_UpdateAnchoredFrames)
        end
        if _G.QUI_RefreshBuffBar then
            pcall(_G.QUI_RefreshBuffBar)
        end
    end
end

-- ========================================================================
-- RECIPROCAL SWAP UPDATE
-- ========================================================================
-- The swap math for each bar depends on the OTHER bar's natural slot
-- (primary moves to secondary's slot and vice-versa).  When NCDM updates
-- one side's locked offsets and triggers Update*PowerBar, the other bar's
-- swap target is computed against still-stale data and lands wrong.
--
-- Solution: after either Update*PowerBar finishes positioning in swap
-- mode, schedule a reciprocal call so the OTHER bar re-evaluates with
-- fresh data.  A reentry guard prevents infinite recursion (the inner
-- call's own reciprocal request short-circuits to a no-op).
local _swapReciprocalGuard = false

local function TriggerSwapReciprocalUpdate()
    if _swapReciprocalGuard then return end
    if not ShouldSwapBars() then return end
    if InCombatLockdown() then return end
    if not QUICore then return end
    _swapReciprocalGuard = true
    if QUICore.UpdatePowerBar then QUICore:UpdatePowerBar() end
    if QUICore.UpdateSecondaryPowerBar then QUICore:UpdateSecondaryPowerBar() end
    _swapReciprocalGuard = false
end

-- ========================================================================
-- SWAP-AWARE BAR RESOLVER
-- ========================================================================
-- External anchors (buff bars, unit frames, etc.) target a logical SLOT
-- via keys like "primaryPower"/"secondaryPower" or "primary"/"secondary".
-- The user's intent is positional: "anchor at the location of the primary
-- bar".  When swap is active, the FRAME at that location changes (the
-- secondary bar now sits at primary's natural slot and vice-versa), so
-- naive "return powerBar / secondaryPowerBar" anchoring causes external
-- elements to follow the moved frame instead of staying put.
--
-- This resolver returns whichever bar currently occupies the requested
-- slot, so anchors track the bbox slot rather than the underlying frame.
--
-- Special case (hidePrimaryOnSwap):
--   * Primary's natural slot has the visible secondary bar — return it.
--   * Secondary's natural slot is empty (bbox shrank) — return the proxy
--     when available so dependent elements anchor to a stable invisible
--     frame at the bbox; otherwise fall back to secondary so anchors
--     don't go nil.
function QUICore:GetSwapAwareBarFor(key)
    if not self then return nil end
    if key == "primaryPower" or key == "primary" then
        if not ShouldSwapBars() then return self.powerBar end
        if ShouldHidePrimaryOnSwap() then return self.secondaryPowerBar end
        return self.secondaryPowerBar
    elseif key == "secondaryPower" or key == "secondary" then
        if not ShouldSwapBars() then return self.secondaryPowerBar end
        if ShouldHidePrimaryOnSwap() then
            -- Secondary's natural slot is empty in shrink-box mode; the
            -- proxy provides a stable invisible anchor at the bbox.
            local proxy = self.GetResourceBarsProxy and self:GetResourceBarsProxy()
            if proxy then return proxy end
            return self.secondaryPowerBar
        end
        return self.powerBar
    end
    return nil
end

-- Compute the union outer rectangle of the bars in their VISIBLE state and
-- write it onto the proxy frame.  Safe to call from anywhere; no-ops in
-- combat (geometry is protected on named frames).
--
-- Strategy: prefer live frame state (handles UI-anchored bars correctly),
-- fall back to natural-slot config math when bars haven't been laid out yet.
function QUICore:UpdateResourceBarsProxy()
    if InCombatLockdown() then return end
    local proxy = GetOrCreateResourceBarsProxy()

    local primaryCfg = self.db.profile.powerBar
    local secondaryCfg = self.db.profile.secondaryPowerBar

    -- A bar contributes to the bbox only when it's actually visible.
    local primaryConsidered = primaryCfg and primaryCfg.enabled and IsBarVisuallyShown(self.powerBar)
    local secondaryConsidered = secondaryCfg and secondaryCfg.enabled and IsBarVisuallyShown(self.secondaryPowerBar)

    if not primaryConsidered and not secondaryConsidered then
        proxy:ClearAllPoints()
        proxy:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
        proxy:SetSize(1, 1)
        return
    end

    local isVertical = GetPrimaryEffectiveVertical()
    local swapped = ShouldSwapBars()
    local hidePrimary = ShouldHidePrimaryOnSwap()

    local rects = {}

    -- PRIMARY: exclude when hidePrimaryOnSwap is active (parked at alpha 0).
    if primaryConsidered and not hidePrimary then
        local lcx, lcy, lw, lh = GetLiveBarRect(self.powerBar)
        if lcx then
            rects[#rects + 1] = { cx = lcx, cy = lcy, w = lw, h = lh }
        else
            local pcx, pcy, plen, pT = ComputePrimaryNaturalSlot()
            local cx, cy = pcx, pcy
            if swapped then
                local scx, scy, _, sT = ComputeSecondaryNaturalSlot()
                cx, cy = ComputeSwappedCenters(pcx, pcy, pT, scx, scy, sT, isVertical)
            end
            if isVertical then
                rects[#rects + 1] = { cx = cx, cy = cy, w = pT, h = plen }
            else
                rects[#rects + 1] = { cx = cx, cy = cy, w = plen, h = pT }
            end
        end
    end

    if secondaryConsidered then
        local lcx, lcy, lw, lh = GetLiveBarRect(self.secondaryPowerBar)
        if lcx then
            rects[#rects + 1] = { cx = lcx, cy = lcy, w = lw, h = lh }
        else
            local pcx, pcy, _, pT = ComputePrimaryNaturalSlot()
            local scx, scy, slen, sT = ComputeSecondaryNaturalSlot()
            local cx, cy = scx, scy
            if swapped then
                if hidePrimary then
                    cx, cy = pcx, pcy
                else
                    local _, _, s2x, s2y = ComputeSwappedCenters(pcx, pcy, pT, scx, scy, sT, isVertical)
                    cx, cy = s2x, s2y
                end
            end
            if isVertical then
                rects[#rects + 1] = { cx = cx, cy = cy, w = sT, h = slen }
            else
                rects[#rects + 1] = { cx = cx, cy = cy, w = slen, h = sT }
            end
        end
    end

    if #rects == 0 then
        proxy:ClearAllPoints()
        proxy:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
        proxy:SetSize(1, 1)
        return
    end

    local minX, maxX, minY, maxY
    for _, r in ipairs(rects) do
        local left, right = r.cx - r.w / 2, r.cx + r.w / 2
        local bottom, top = r.cy - r.h / 2, r.cy + r.h / 2
        minX = minX and math_min(minX, left) or left
        maxX = maxX and math_max(maxX, right) or right
        minY = minY and math_min(minY, bottom) or bottom
        maxY = maxY and math_max(maxY, top) or top
    end

    local width = math_max(1, maxX - minX)
    local height = math_max(1, maxY - minY)
    local centerX = (minX + maxX) / 2
    local centerY = (minY + maxY) / 2

    proxy:ClearAllPoints()
    proxy:SetPoint("CENTER", UIParent, "CENTER",
        QUICore:PixelRound(centerX, proxy),
        QUICore:PixelRound(centerY, proxy))
    proxy:SetSize(QUICore:PixelRound(width, proxy), QUICore:PixelRound(height, proxy))
end

-- Public accessor (used by buffbar etc.).  Always returns a frame.
function QUICore:GetResourceBarsProxy()
    return GetOrCreateResourceBarsProxy()
end

-- RESOURCE DETECTION

local function GetPrimaryResource()
    local playerClass = select(2, UnitClass("player"))
    local primaryResources = {
        ["DEATHKNIGHT"] = Enum.PowerType.RunicPower,
        ["DEMONHUNTER"] = Enum.PowerType.Fury,
        ["DRUID"]       = {
            [0]   = Enum.PowerType.Mana,        -- Human/Caster
            [1]   = Enum.PowerType.Energy,      -- Cat
            [3]   = Enum.PowerType.Mana,        -- Travel (ground) - fallback
            [4]   = Enum.PowerType.Mana,        -- Aquatic - fallback
            [5]   = Enum.PowerType.Rage,        -- Bear
            [27]  = Enum.PowerType.Mana,        -- Swift Travel - fallback
            [31]  = Enum.PowerType.LunarPower,  -- Moonkin
        },
        ["EVOKER"]      = Enum.PowerType.Mana,
        ["HUNTER"]      = Enum.PowerType.Focus,
        ["MAGE"]        = Enum.PowerType.Mana,
        ["MONK"]        = {
            [268] = Enum.PowerType.Energy, -- Brewmaster
            [269] = Enum.PowerType.Energy, -- Windwalker
            [270] = Enum.PowerType.Mana, -- Mistweaver
        },
        ["PALADIN"]     = Enum.PowerType.Mana,
        ["PRIEST"]      = {
            [256] = Enum.PowerType.Mana, -- Disciple
            [257] = Enum.PowerType.Mana, -- Holy,
            [258] = Enum.PowerType.Insanity, -- Shadow,
        },
        ["ROGUE"]       = Enum.PowerType.Energy,
        ["SHAMAN"]      = {
            [262] = Enum.PowerType.Maelstrom, -- Elemental
            [263] = Enum.PowerType.Mana, -- Enhancement
            [264] = Enum.PowerType.Mana, -- Restoration
        },
        ["WARLOCK"]     = Enum.PowerType.Mana,
        ["WARRIOR"]     = Enum.PowerType.Rage,
    }

    local spec = GetSpecialization()
    if not spec then return Enum.PowerType.Mana end
    local specID = GetSpecializationInfo(spec)

    -- Druid: spec-aware for utility forms, form-based for combat forms
    if playerClass == "DRUID" then
        local formID = GetShapeshiftFormID()
        -- In utility forms (travel/aquatic/flight), show spec's primary resource
        if druidUtilityForms[formID or 0] then
            local druidSpec = GetSpecialization()
            if druidSpec and druidSpecResource[druidSpec] then
                return druidSpecResource[druidSpec]
            end
        end
        -- Combat forms and caster form: use form-based resource
        return primaryResources[playerClass][formID or 0]
    end

    if type(primaryResources[playerClass]) == "table" then
        return primaryResources[playerClass][specID]
    else 
        return primaryResources[playerClass]
    end
end

local function GetSecondaryResource()
    local playerClass = select(2, UnitClass("player"))
    local secondaryResources = {
        ["DEATHKNIGHT"] = Enum.PowerType.Runes,
        ["DEMONHUNTER"] = {
            [581] = VDH_SOUL_FRAGMENTS_POWER or Enum.PowerType.VengSoulFragments, -- Vengeance
            [1480] = "SOUL", -- Devourer / Aldrachi Reaver
        },
        ["DRUID"]       = {
            [1]    = Enum.PowerType.ComboPoints, -- Cat
            [31]   = Enum.PowerType.Mana, -- Moonkin
        },
        ["EVOKER"]      = Enum.PowerType.Essence,
        ["HUNTER"]      = {
            [255] = Enum.PowerType.TipOfTheSpear, -- Survival
        },
        ["MAGE"]        = {
            [62]   = Enum.PowerType.ArcaneCharges, -- Arcane
        },
        ["MONK"]        = {
            [268]  = "STAGGER", -- Brewmaster
            [269]  = Enum.PowerType.Chi, -- Windwalker
        },
        ["PALADIN"]     = Enum.PowerType.HolyPower,
        ["PRIEST"]      = {
            [258]  = Enum.PowerType.Mana, -- Shadow
        },
        ["ROGUE"]       = Enum.PowerType.ComboPoints,
        ["SHAMAN"]      = {
            [262]  = Enum.PowerType.Mana, -- Elemental
            [263]  = Enum.PowerType.MaelstromWeapon,  -- Enhancement (aura stacks via C_UnitAuras)
        },
        ["WARLOCK"]     = Enum.PowerType.SoulShards,
        ["WARRIOR"]     = {
            [72] = Enum.PowerType.Whirlwind, -- Fury
        },
    }

    local spec = GetSpecialization()
    if not spec then return nil end
    local specID = GetSpecializationInfo(spec)

    -- Druid: spec-aware for utility/caster forms, form-based for combat forms
    if playerClass == "DRUID" then
        local formID = GetShapeshiftFormID()
        -- In utility/caster forms, show Mana as secondary if spec primary isn't Mana
        if druidUtilityForms[formID] or formID == nil then
            local druidSpec = GetSpecialization()
            -- Only show Mana secondary for non-Resto specs (Resto primary is already Mana)
            if druidSpec and druidSpec ~= 4 then
                return Enum.PowerType.Mana
            end
            return nil
        end
        -- Combat forms: use form-based secondary
        return secondaryResources[playerClass][formID]
    end

    if type(secondaryResources[playerClass]) == "table" then
        return secondaryResources[playerClass][specID]
    else 
        return secondaryResources[playerClass]
    end
end

local function GetResourceColor(resource)
    -- Check for custom power colors first
    local core = GetCore()
    local pc = core and core.db and core.db.profile.powerColors

    if pc then
        local customColor = nil

        if resource == "STAGGER" then
            -- Dynamic stagger level colors (Light/Moderate/Heavy)
            if pc.useStaggerLevelColors then
                local stagger = UnitStagger("player") or 0
                local maxHealth = UnitHealthMax("player") or 1
                local staggerPercent = (stagger / maxHealth) * 100

                if staggerPercent >= 60 then
                    customColor = pc.staggerHeavy
                elseif staggerPercent >= 30 then
                    customColor = pc.staggerModerate
                else
                    customColor = pc.staggerLight
                end
            else
                customColor = pc.stagger
            end
        elseif resource == "SOUL" or resource == Enum.PowerType.VengSoulFragments or (VDH_SOUL_FRAGMENTS_POWER and resource == VDH_SOUL_FRAGMENTS_POWER) then
            customColor = pc.soulFragments
        elseif resource == Enum.PowerType.SoulShards then
            customColor = pc.soulShards
        elseif resource == Enum.PowerType.Runes then
            -- Check DK spec for spec-specific rune colors
            local _, class = UnitClass("player")
            if class == "DEATHKNIGHT" then
                local spec = GetSpecialization()
                if spec == 1 then customColor = pc.bloodRunes
                elseif spec == 2 then customColor = pc.frostRunes
                elseif spec == 3 then customColor = pc.unholyRunes
                else customColor = pc.runes end
            else
                customColor = pc.runes
            end
        elseif resource == Enum.PowerType.Essence then
            customColor = pc.essence
        elseif resource == Enum.PowerType.ComboPoints then
            customColor = pc.comboPoints
        elseif resource == Enum.PowerType.Chi then
            customColor = pc.chi
        elseif resource == Enum.PowerType.Mana then
            customColor = pc.mana
        elseif resource == Enum.PowerType.Rage then
            customColor = pc.rage
        elseif resource == Enum.PowerType.Energy then
            customColor = pc.energy
        elseif resource == Enum.PowerType.Focus then
            customColor = pc.focus
        elseif resource == Enum.PowerType.RunicPower then
            customColor = pc.runicPower
        elseif resource == Enum.PowerType.Insanity then
            customColor = pc.insanity
        elseif resource == Enum.PowerType.Fury then
            customColor = pc.fury
        elseif resource == Enum.PowerType.Maelstrom then
            customColor = pc.maelstrom
        elseif resource == Enum.PowerType.MaelstromWeapon then
            customColor = pc.maelstromWeapon or pc.maelstrom
        elseif resource == Enum.PowerType.Whirlwind then
            customColor = pc.whirlwind
        elseif resource == Enum.PowerType.TipOfTheSpear then
            customColor = pc.tipOfTheSpear
        elseif resource == Enum.PowerType.LunarPower then
            customColor = pc.lunarPower
        elseif resource == Enum.PowerType.HolyPower then
            customColor = pc.holyPower
        elseif resource == Enum.PowerType.ArcaneCharges then
            customColor = pc.arcaneCharges
        end

        if customColor then
            return { r = customColor[1], g = customColor[2], b = customColor[3], a = customColor[4] }
        end
    end

    -- Fallback to Blizzard's power bar colors
    local powerName = nil
    if type(resource) == "number" then
        for name, value in pairs(Enum.PowerType) do
            if value == resource then
                powerName = name:gsub("(%u)", "_%1"):gsub("^_", ""):upper()
                break
            end
        end
    end

    return GetPowerBarColor(powerName)
        or GetPowerBarColor(resource)
        or GetPowerBarColor("MANA")
end

-- GET RESOURCE VALUES

local cachedDHSoulBarParent = nil
local cachedDHSoulBarAlpha = nil

local function EnsureDemonHunterSoulBar()
    local soulBar = _G["DemonHunterSoulFragmentsBar"]
    if not soulBar then return nil end

    local isSoulResource = (GetSecondaryResource() == "SOUL")

    -- Restore original Blizzard ownership/state when no longer using SOUL as secondary.
    if not isSoulResource then
        if not InCombatLockdown() then
            if cachedDHSoulBarParent and soulBar.GetParent and soulBar:GetParent() ~= cachedDHSoulBarParent then
                soulBar:SetParent(cachedDHSoulBarParent)
            end
            if cachedDHSoulBarAlpha ~= nil and soulBar.SetAlpha then
                soulBar:SetAlpha(cachedDHSoulBarAlpha)
            end
        end
        return soulBar
    end

    -- Keep Blizzard's soul fragment driver alive even when PlayerFrame is hidden.
    if not InCombatLockdown() then
        if cachedDHSoulBarParent == nil and soulBar.GetParent then
            cachedDHSoulBarParent = soulBar:GetParent()
        end
        if cachedDHSoulBarAlpha == nil and soulBar.GetAlpha then
            cachedDHSoulBarAlpha = soulBar:GetAlpha()
        end
        if soulBar.GetParent and soulBar:GetParent() ~= UIParent then
            soulBar:SetParent(UIParent)
        end
        if soulBar.IsShown and not soulBar:IsShown() then
            soulBar:Show()
        end
        if soulBar.SetAlpha then
            soulBar:SetAlpha(0)
        end
    end

    return soulBar
end

local function GetPrimaryResourceValue(resource, cfg)
    if not resource then return nil, nil, nil, nil end

    local current = UnitPower("player", resource)
    local max = UnitPowerMax("player", resource)
    if max <= 0 then return nil, nil, nil, nil end

    -- Check both old (showManaAsPercent) and new (showPercent) field names
    if (cfg.showPercent or cfg.showManaAsPercent) and resource == Enum.PowerType.Mana then
        if HAS_UNIT_POWER_PERCENT then
            return max, current, GetPowerPct("player", resource, false), "percent"
        else
            return max, current, math_floor((current / max) * 100 + 0.5), "percent"
        end
    else
        return max, current, current, "number"
    end
end

local function GetSecondaryResourceValue(resource)
    if not resource then return nil, nil, nil, nil end

    if resource == "STAGGER" then
        local stagger = UnitStagger("player") or 0
        local maxHealth = UnitHealthMax("player") or 1
        local staggerPercent = (stagger / maxHealth) * 100
        return 100, staggerPercent, staggerPercent, "percent"
    end

    if resource == "SOUL" then
        local soulBar = EnsureDemonHunterSoulBar() or _G["DemonHunterSoulFragmentsBar"]
        if soulBar and soulBar.GetValue and soulBar.GetMinMaxValues then
            local current = soulBar:GetValue()
            local _, max = soulBar:GetMinMaxValues()
            if max and max > 0 then
                return max, current, current, "number"
            end
        end
    end

    if VDH_SOUL_FRAGMENTS_POWER and resource == VDH_SOUL_FRAGMENTS_POWER then
        local current = UnitPower("player", resource) or 0
        local max = UnitPowerMax("player", resource) or 0
        if max > 0 then
            return max, current, current, "number"
        end
    end

    if resource == Enum.PowerType.VengSoulFragments then
        local current = C_Spell.GetSpellCastCount(228477) or 0
        local max = 6

        return max, current, current, "number"
    end

    if resource == Enum.PowerType.MaelstromWeapon then
        -- Enhancement Shaman Maelstrom Weapon stacks (aura-based, spell ID 344179)
        local aura = C_UnitAuras.GetPlayerAuraBySpellID(344179)
        local current = aura and aura.applications or 0
        return 10, current, current, "number"
    end

    if resource == Enum.PowerType.Whirlwind then
        -- Fury Warrior Improved Whirlwind stacks.
        -- Manual tracker (UNIT_SPELLCAST_SUCCEEDED) is reliable during combat;
        -- C_UnitAuras.GetPlayerAuraBySpellID(85739) returns stale/secret data.
        local max, current = WhirlwindTracker:GetStacks()
        if not max then return nil, nil, nil, nil end
        return max, current, current, "number"
    end

    if resource == Enum.PowerType.TipOfTheSpear then
        -- Survival Hunter Tip of the Spear stacks.
        -- Manual tracker (UNIT_SPELLCAST_SUCCEEDED) is reliable during combat;
        -- C_UnitAuras.GetPlayerAuraBySpellID(260286) returns stale/secret data.
        local max, current = TipOfTheSpearTracker:GetStacks()
        if not max then return nil, nil, nil, nil end
        return max, current, current, "number"
    end

    if resource == Enum.PowerType.Runes then
        local current = 0
        local max = UnitPowerMax("player", resource)
        if max <= 0 then return nil, nil, nil, nil end

        for i = 1, max do
            local runeReady = select(3, GetRuneCooldown(i))
            if runeReady then
                current = current + 1
            end
        end

        return max, current, current, "number"
    end

    if resource == Enum.PowerType.SoulShards then
        local _, class = UnitClass("player")
        if class == "WARLOCK" then
            local spec = GetSpecialization()

            -- Destruction: fragments for bar fill, divided by 10 for display
            if spec == 3 then
                local fragments = UnitPower("player", resource, true)        -- 0–50
                local maxFragments = UnitPowerMax("player", resource, true)  -- 50
                if maxFragments <= 0 then return nil, nil, nil, nil end

                -- bar fill = fragments (0-50), display = decimal shards (0.0-5.0)
                return maxFragments, fragments, fragments / 10, "shards"
            end
        end

        -- Any other spec/class that somehow hits SoulShards:
        -- use NORMAL shard count (0–5) for both bar + text
        local current = UnitPower("player", resource)             -- 0–5
        local max     = UnitPowerMax("player", resource)          -- 0–5
        if max <= 0 then return nil, nil, nil, nil end

        -- bar = 0–5, text = 3, 4, 5 etc.
        return max, current, current, "number"
    end

    -- Default case for all other power types (ComboPoints, Chi, HolyPower, etc.)
    local current = UnitPower("player", resource)
    local max = UnitPowerMax("player", resource)
    if max <= 0 then return nil, nil, nil, nil end

    return max, current, current, "number"
end

local function GetCurrentSpecID()
    local spec = GetSpecialization()
    if not spec then return 0 end
    return GetSpecializationInfo(spec) or 0
end

-- Text setting keys eligible for per-spec override
local TEXT_SPEC_KEYS = {
    "showText", "showPercent", "hidePercentSymbol", "textAlign",
    "textSize", "textX", "textY", "textUseClassColor", "textCustomColor",
}

-- Ensure per-spec text overrides exist for the given spec, seeding from base config
local function EnsureTextSpecOverrides(cfg, specID)
    if not cfg.textSpecOverrides then cfg.textSpecOverrides = {} end
    if not cfg.textSpecOverrides[specID] then
        local base = {}
        for _, k in ipairs(TEXT_SPEC_KEYS) do
            local v = cfg[k]
            -- Deep-copy table values (e.g. textCustomColor) to avoid shared references
            if type(v) == "table" then
                local copy = {}
                for tk, tv in pairs(v) do copy[tk] = tv end
                v = copy
            end
            base[k] = v
        end
        cfg.textSpecOverrides[specID] = base
    end
    return cfg.textSpecOverrides[specID]
end

-- Return the effective text config table (per-spec overrides if enabled, otherwise base cfg)
local function GetSecondaryTextConfig(cfg)
    if not cfg or not cfg.textPerSpec then return cfg end
    local specID = GetCurrentSpecID()
    if specID == 0 then return cfg end
    return EnsureTextSpecOverrides(cfg, specID)
end

local function SanitizeIndicatorValues(values, maxValue)
    if type(values) ~= "table" or not maxValue or maxValue <= 0 then
        return {}
    end

    local dedupe = {}
    local sanitized = {}
    for _, rawValue in ipairs(values) do
        local value = tonumber(rawValue)
        if value and value > 0 and value < maxValue then
            -- Round to 3 decimals to avoid floating-point duplicate noise.
            value = math_floor((value * 1000) + 0.5) / 1000
            local dedupeKey = string_format("%.3f", value)
            if not dedupe[dedupeKey] then
                dedupe[dedupeKey] = true
                table_insert(sanitized, value)
            end
        end
    end

    table.sort(sanitized)
    while #sanitized > 3 do
        table_remove(sanitized)
    end

    return sanitized
end

local function GetIndicatorValuesForCurrentSpec(indicatorCfg, maxValue)
    if type(indicatorCfg) ~= "table" or not indicatorCfg.enabled then
        return {}
    end

    local perSpec = indicatorCfg.perSpec
    if type(perSpec) ~= "table" then
        return {}
    end

    local specID = GetCurrentSpecID()
    local specValues = perSpec[specID] or perSpec[tostring(specID)]
    return SanitizeIndicatorValues(specValues, maxValue)
end

local function UpdateBarIndicatorLines(bar, indicatorPool, values, maxValue, thickness, color, isVertical)
    for _, indicator in ipairs(indicatorPool) do
        indicator:Hide()
    end

    if #values == 0 or not maxValue or maxValue <= 0 then
        return
    end

    local width = bar:GetWidth()
    local height = bar:GetHeight()
    if width <= 0 or height <= 0 then
        return
    end

    local lineThickness = QUICore:Pixels(thickness or 1, bar)
    local lineColor = color or { 1, 1, 1, 1 }

    for i, value in ipairs(values) do
        local indicator = indicatorPool[i]
        if not indicator then
            indicator = bar:CreateTexture(nil, "OVERLAY")
            indicatorPool[i] = indicator
        end

        indicator:SetColorTexture(lineColor[1] or 1, lineColor[2] or 1, lineColor[3] or 1, lineColor[4] or 1)
        indicator:ClearAllPoints()

        if isVertical then
            local y = (value / maxValue) * height
            indicator:SetPoint("BOTTOM", bar.StatusBar, "BOTTOM", 0, QUICore:PixelRound(y - (lineThickness / 2), bar))
            indicator:SetSize(width, lineThickness)
        else
            local x = (value / maxValue) * width
            indicator:SetPoint("LEFT", bar.StatusBar, "LEFT", QUICore:PixelRound(x - (lineThickness / 2), bar), 0)
            indicator:SetSize(lineThickness, height)
        end

        indicator:Show()
    end
end


-- Old Edit Mode overlay system removed — Layout Mode handles replace these.
-- (See git history for CreatePowerBarNudgeButton, SetPowerBarEditOverlayStyle,
-- CreatePowerBarEditOverlay, EnablePowerBarEditMode, DisablePowerBarEditMode)


-- PRIMARY POWER BAR

function QUICore:GetPowerBar()
    if self.powerBar then return self.powerBar end

    local cfg = self.db.profile.powerBar
    
    -- Always parent to UIParent so power bar works independently of Essential Cooldowns
    local bar = CreateFrame("Frame", ADDON_NAME .. "PowerBar", UIParent)
    bar:SetFrameStrata("MEDIUM")
    -- Apply HUD layer priority
    local layerPriority = self.db.profile.hudLayering and self.db.profile.hudLayering.primaryPowerBar or 7
    local frameLevel = self:GetHUDFrameLevel(layerPriority)
    bar:SetFrameLevel(frameLevel)
    bar:SetHeight(QUICore:PixelRound(cfg.height or 6, bar))
    QUICore:SetSnappedPoint(bar, "CENTER", UIParent, "CENTER", cfg.offsetX or 0, cfg.offsetY or 6)

    -- Calculate width - use configured width or fallback.
    -- Avoid reading essentialViewer:GetWidth() here: at creation time CDM
    -- LayoutViewer has not run yet, so the Blizzard frame width is stale/wrong.
    -- Use raw content width (before HUD min-width inflation) so bars match
    -- the actual icon span, not the inflated proxy bounds.
    local width = cfg.width or 0
    if width <= 0 then
        local essentialViewer = _G.QUI_GetCDMViewerFrame("essential")
        if essentialViewer then
            local evs = GetViewerState(essentialViewer)
            width = GetRawContentWidth(evs) or 0
        end
        if width <= 0 then
            width = QUICore.db and QUICore.db.profile and QUICore.db.profile.ncdm
                and QUICore.db.profile.ncdm._lastEssentialWidth or 0
        end
        if width <= 0 then
            width = 200  -- Fallback width
        end
    end

    bar:SetWidth(QUICore:PixelRound(width, bar))


    -- BACKGROUND
    local bgColor = cfg.bgColor or { 0.15, 0.15, 0.15, 1 }
    bar.Background = UIKit.CreateBackground(bar, bgColor[1], bgColor[2], bgColor[3], bgColor[4] or 1)

    -- STATUS BAR
    bar.StatusBar = CreateFrame("StatusBar", nil, bar)
    bar.StatusBar:SetAllPoints()
    local tex = LSM:Fetch("statusbar", GetBarTexture(cfg))
    bar.StatusBar:SetStatusBarTexture(tex)
    bar.StatusBar:SetFrameLevel(bar:GetFrameLevel())

    -- BORDER (pixel-perfect)
    UIKit.CreateBackdropBorder(bar, cfg.borderSize or 1, 0, 0, 0, 1)

    -- TEXT FRAME (same strata, +2 levels to render above bar content but stay within element's layer band)
    bar.TextFrame = CreateFrame("Frame", nil, bar)
    bar.TextFrame:SetAllPoints(bar)
    bar.TextFrame:SetFrameStrata("MEDIUM")
    bar.TextFrame:SetFrameLevel(frameLevel + 2)

    bar.TextValue = bar.TextFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    ApplyPowerBarTextPlacement(bar, cfg)
    bar.TextValue:SetFont(GetGeneralFont(), QUICore:PixelRound(cfg.textSize or 12, bar.TextValue), GetGeneralFontOutline())
    bar.TextValue:SetShadowOffset(0, 0)
    bar.TextValue:SetText("0")

    -- TICKS
    bar.ticks = {}
    bar.indicatorLines = {}

    bar:Hide()

    self.powerBar = bar
    return bar
end

function QUICore:UpdatePowerBar()
    local cfg = self.db.profile.powerBar

    -- Always ensure the frame exists so the global name "QUIPowerBar" is
    -- available for Edit Mode layout anchoring even when the bar is disabled.
    local bar = self:GetPowerBar()

    if not cfg.enabled then
        SafeHide(bar)
        return
    end

    -- When locked to CDM, suppress until CDM has computed the correct width.
    -- Prevents a flash at a stale DB width on login/reload.
    if (cfg.lockedToEssential or cfg.lockedToUtility) and not _primaryLockedReady then
        if self.powerBar then SafeHide(self.powerBar) end
        return
    end

    -- Auto-hide primary when secondary is swapped to primary position (per-spec).
    -- Park the bar at its natural slot (alpha 0) so anything anchored directly
    -- to QUIPowerBar keeps its visual position aligned with the visible
    -- secondary bar (which now occupies primary's natural slot).
    -- Skip during bootstrap natural-slot pass: we need primary visible at its
    -- true natural position so we can capture it.
    if ShouldHidePrimaryOnSwap() and not IsForcingNaturalDuringBootstrap() then
        SyncSwapAnchorOwnership(true)
        local primaryBar = self.powerBar
        if primaryBar then
            if not InCombatLockdown() then
                local pcx, pcy = GetPrimaryNaturalSlotForSwap()
                local pxRounded = QUICore:PixelRound(pcx, primaryBar)
                local pyRounded = QUICore:PixelRound(pcy, primaryBar)
                if primaryBar._cachedX ~= pxRounded or primaryBar._cachedY ~= pyRounded or primaryBar._cachedAutoMode ~= "hiddenAtNaturalSlot" then
                    primaryBar:ClearAllPoints()
                    primaryBar:SetPoint("CENTER", UIParent, "CENTER", pxRounded, pyRounded)
                    primaryBar._cachedX = pxRounded
                    primaryBar._cachedY = pyRounded
                    primaryBar._cachedAutoMode = "hiddenAtNaturalSlot"
                    if _G.QUI_UpdateAnchoredUnitFrames then
                        _G.QUI_UpdateAnchoredUnitFrames()
                    end
                end
            end
            primaryBar:SetAlpha(0)
            SafeShow(primaryBar)
        end
        if self.UpdateResourceBarsProxy then self:UpdateResourceBarsProxy() end
        -- Re-run secondary positioning so its swap target reflects the
        -- now-known primary natural slot (handles NCDM ordering on first
        -- frame after reload where one side updates before the other).
        TriggerSwapReciprocalUpdate()
        return
    end

    local resource = GetPrimaryResource()

    if not resource then
        SafeHide(bar)
        return
    end

    -- CDM visibility can hide bars independently of bar visibility mode.
    -- Honor configured CDM fadeOutAlpha instead of forcing fully transparent.
    do -- CDM hidden alpha check (old edit mode guard removed)
        local cdmHiddenAlpha = GetCDMHiddenAlpha()
        if cdmHiddenAlpha ~= nil then
            bar:SetAlpha(cdmHiddenAlpha)
            SafeShow(bar)
            return
        end
    end

    -- Visibility mode check (always/combat/hostile)
    -- Use alpha instead of Hide so anchored frames keep their reference
    local visibilityHidden = not ShouldShowBar(cfg)
    if visibilityHidden then
        bar:SetAlpha(0)
        SafeShow(bar)
        return
    end

    -- Update HUD layer priority dynamically
    local layerPriority = self.db.profile.hudLayering and self.db.profile.hudLayering.primaryPowerBar or 7
    local frameLevel = self:GetHUDFrameLevel(layerPriority)
    SafeSetFrameLevel(bar, frameLevel)
    if bar.TextFrame then
        SafeSetFrameLevel(bar.TextFrame, frameLevel + 2)
    end

    -- Determine effective orientation (AUTO/HORIZONTAL/VERTICAL)
    local orientation = cfg.orientation or "AUTO"
    local isVertical = (orientation == "VERTICAL")

    -- For AUTO, check if locked to a CDM viewer and inherit its orientation
    if orientation == "AUTO" then
        if cfg.lockedToEssential then
            local viewer = _G.QUI_GetCDMViewerFrame("essential")
            local vs = GetViewerState(viewer)
            isVertical = (vs and vs.layoutDir) == "VERTICAL"
        elseif cfg.lockedToUtility then
            local viewer = _G.QUI_GetCDMViewerFrame("utility")
            local vs = GetViewerState(viewer)
            isVertical = (vs and vs.layoutDir) == "VERTICAL"
        end
    end

    -- Apply orientation to StatusBar
    bar.StatusBar:SetOrientation(isVertical and "VERTICAL" or "HORIZONTAL")

    -- Calculate width - use configured width, or fall back to Essential width.
    -- Use raw content width (before HUD min-width inflation) so bars match
    -- the actual icon span, not the inflated proxy bounds.
    local width = cfg.width
    if not width or width <= 0 then
        -- Try to get Essential Cooldowns width
        local essentialViewer = _G.QUI_GetCDMViewerFrame("essential")
        if essentialViewer then
            local evs = GetViewerState(essentialViewer)
            width = GetRawContentWidth(evs)
        end
        if width and width > 0 then
            -- Persist for next reload so bars don't flash at stale/fallback width.
            -- Skip during Edit Mode — those dimensions are transient.
            if not Helpers.IsEditModeActive() and self.db.profile.ncdm then
                self.db.profile.ncdm._lastEssentialWidth = width
            end
        else
            width = self.db.profile.ncdm and self.db.profile.ncdm._lastEssentialWidth
        end
        if not width or width <= 0 then
            width = 200 -- absolute fallback
        end
    end

    -- Calculate desired position and size (pixel-snapped for crisp borders)
    local offsetX, offsetY
    local isSwapped = ShouldSwapBars()
    -- Bootstrap pass: pretend swap is OFF so the bar lands at its true
    -- natural slot.  Capture phase reads that position; the second
    -- (post-bootstrap) call positions the bar with swap fully applied.
    if isSwapped and IsForcingNaturalDuringBootstrap() then
        isSwapped = false
    end
    -- Hand swap on/off events to the anchoring system: while swap is active
    -- we own positioning; when it deactivates we restore the user's saved
    -- frame anchors via QUI_ForceReapplyFrameAnchor.
    SyncSwapAnchorOwnership(isSwapped)
    if isSwapped then
        -- Compute primary's swapped position from natural slots so it works
        -- for ALL secondary lock modes (lockedToEssential/Utility/Primary or
        -- standalone), preserving the combined bounding box.  Prefer live
        -- captures so swap honors user-saved anchor positions.
        local pcx, pcy, _, pT = GetPrimaryNaturalSlotForSwap()
        local scx, scy, _, sT = GetSecondaryNaturalSlotForSwap()
        local primaryNewCx, primaryNewCy = ComputeSwappedCenters(pcx, pcy, pT, scx, scy, sT, isVertical)
        offsetX = QUICore:PixelRound(primaryNewCx, bar)
        offsetY = QUICore:PixelRound(primaryNewCy, bar)
        -- Primary keeps its own length when swapping (existing 'width' is correct).
    else
        offsetX = QUICore:PixelRound(cfg.offsetX or 0, bar)
        offsetY = QUICore:PixelRound(cfg.offsetY or 0, bar)
    end

    -- Geometry functions (SetHeight/SetWidth/SetPoint/ClearAllPoints) are
    -- protected on named frames during combat.  Config-driven dimensions
    -- don't change mid-fight; PLAYER_REGEN_ENABLED triggers a full update.
    if not InCombatLockdown() then
        -- While swap is active we own positioning even if the user has saved
        -- frame anchor entries — those are deferred to swap-off via the
        -- ownership handoff above.  Otherwise honor saved anchors.
        local swapMode = isSwapped and "swappedToSecondary" or nil
        local positionAllowed = isSwapped or not (_G.QUI_HasFrameAnchor and _G.QUI_HasFrameAnchor("primaryPower"))
        if positionAllowed and (bar._cachedX ~= offsetX or bar._cachedY ~= offsetY or bar._cachedAutoMode ~= swapMode) then
            bar:ClearAllPoints()
            bar:SetPoint("CENTER", UIParent, "CENTER", offsetX, offsetY)
            bar._cachedX = offsetX
            bar._cachedY = offsetY
            bar._cachedAutoMode = swapMode
            -- Notify unit frames that may be anchored to this power bar
            if _G.QUI_UpdateAnchoredUnitFrames then
                _G.QUI_UpdateAnchoredUnitFrames()
            end
        end

        -- For vertical bars, swap width and height (width = thickness, height = length)
        local wantedH, wantedW
        if isVertical then
            -- Vertical bar: cfg.width is the bar length (becomes height), cfg.height is thickness (becomes width)
            wantedW = QUICore:PixelRound(cfg.height or 6, bar)
            wantedH = QUICore:PixelRound(width, bar)
        else
            -- Horizontal bar: normal dimensions
            wantedH = QUICore:PixelRound(cfg.height or 6, bar)
            wantedW = QUICore:PixelRound(width, bar)
        end

        -- Only resize when dimensions actually changed (prevents flicker)
        if bar._cachedH ~= wantedH then
            bar:SetHeight(wantedH)
            bar._cachedH = wantedH
        end
        if bar._cachedW ~= wantedW then
            bar:SetWidth(wantedW)
            bar._cachedW = wantedW
        end

        -- Update border size only when changed (prevents flicker)
        local borderSizePixels = cfg.borderSize or 1
        if bar._cachedBorderSize ~= borderSizePixels then
            if UIKit and UIKit.CreateBackdropBorder then
                bar.Border = UIKit.CreateBackdropBorder(bar, borderSizePixels, 0, 0, 0, 1)
                if bar.Border then
                    bar.Border:SetShown(borderSizePixels > 0)
                end
            end
            bar._cachedBorderSize = borderSizePixels
        end
    end

    -- Update background color
    local bgColor = cfg.bgColor or { 0.15, 0.15, 0.15, 1 }
    if bar.Background then
        bar.Background:SetColorTexture(bgColor[1], bgColor[2], bgColor[3], bgColor[4] or 1)
    end

    -- Update texture only when changed (prevents flicker)
    local tex = LSM:Fetch("statusbar", GetBarTexture(cfg))
    if bar._cachedTex ~= tex then
        bar.StatusBar:SetStatusBarTexture(tex)
        bar._cachedTex = tex
    end

    -- Get resource values
    local max, current, displayValue, valueType = GetPrimaryResourceValue(resource, cfg)
    if not max then
        SafeHide(bar)
        return
    end

    -- Set bar values
    bar.StatusBar:SetMinMaxValues(0, max)
    bar.StatusBar:SetValue(current)

    -- Set bar color based on checkboxes: Power Type > Class > Custom
    if cfg.usePowerColor then
        -- Power type color (Mana=blue, Rage=red, Energy=yellow, etc.)
        local color = GetResourceColor(resource)
        bar.StatusBar:SetStatusBarColor(color.r, color.g, color.b, color.a or 1)
    elseif cfg.useClassColor then
        -- Class color
        local _, class = UnitClass("player")
        local classColor = RAID_CLASS_COLORS[class]
        if classColor then
            bar.StatusBar:SetStatusBarColor(classColor.r, classColor.g, classColor.b)
        else
            local color = GetResourceColor(resource)
            bar.StatusBar:SetStatusBarColor(color.r, color.g, color.b, color.a or 1)
        end
    elseif cfg.useCustomColor and cfg.customColor then
        -- Custom color override
        local c = cfg.customColor
        bar.StatusBar:SetStatusBarColor(c[1], c[2], c[3], c[4] or 1)
    else
        -- Power type color (default)
        local color = GetResourceColor(resource)
        bar.StatusBar:SetStatusBarColor(color.r, color.g, color.b, color.a or 1)
    end




    -- Update text
    if valueType == "percent" then
        bar.TextValue:SetText(FormatPercentValue(displayValue, cfg))
    else
        bar.TextValue:SetText(tostring(displayValue))
    end

    bar.TextValue:SetFont(GetGeneralFont(), QUICore:PixelRound(cfg.textSize or 12, bar.TextValue), GetGeneralFontOutline())
    bar.TextValue:SetShadowOffset(0, 0)

    -- Apply text color
    if cfg.textUseClassColor then
        local _, class = UnitClass("player")
        local classColor = RAID_CLASS_COLORS[class]
        if classColor then
            bar.TextValue:SetTextColor(classColor.r, classColor.g, classColor.b, 1)
        end
    else
        local c = cfg.textCustomColor or { 1, 1, 1, 1 }
        bar.TextValue:SetTextColor(c[1], c[2], c[3], c[4] or 1)
    end

    ApplyPowerBarTextPlacement(bar, cfg)

    -- Show text based on config
    bar.TextFrame:SetShown(cfg.showText ~= false)

    -- Update ticks if this is a ticked power type
    self:UpdatePowerBarTicks(bar, resource, max)
    self:UpdatePowerBarIndicators(bar, max, isVertical)

    bar:SetAlpha(1)
    SafeShow(bar)

    -- Propagate to Secondary bar if it's locked to Primary
    local secondaryCfg = self.db.profile.secondaryPowerBar
    if secondaryCfg and secondaryCfg.lockedToPrimary then
        self:UpdateSecondaryPowerBar()
    end

    if self.UpdateResourceBarsProxy then self:UpdateResourceBarsProxy() end
    ScheduleNaturalSlotCapture()
    -- See TriggerSwapReciprocalUpdate doc: ensures both bars settle to
    -- correct positions across NCDM ordering and lockedBase updates.
    TriggerSwapReciprocalUpdate()
end

function QUICore:UpdatePowerBarTicks(bar, resource, max)
    local cfg = self.db.profile.powerBar

    -- Hide all ticks first
    for _, tick in ipairs(bar.ticks) do
        tick:Hide()
    end

    if not cfg.showTicks or not tickedPowerTypes[resource] then
        return
    end

    local width = bar:GetWidth()
    local height = bar:GetHeight()
    if width <= 0 or height <= 0 then return end

    -- Determine if bar is vertical
    local orientation = cfg.orientation or "AUTO"
    local isVertical = (orientation == "VERTICAL")
    if orientation == "AUTO" then
        if cfg.lockedToEssential then
            local viewer = _G.QUI_GetCDMViewerFrame("essential")
            local vs = GetViewerState(viewer)
            isVertical = (vs and vs.layoutDir) == "VERTICAL"
        elseif cfg.lockedToUtility then
            local viewer = _G.QUI_GetCDMViewerFrame("utility")
            local vs = GetViewerState(viewer)
            isVertical = (vs and vs.layoutDir) == "VERTICAL"
        end
    end

    local tickPx = QUICore:GetPixelSize(bar)
    local tickThickness = (cfg.tickThickness or 1) * tickPx
    local tc = cfg.tickColor or { 0, 0, 0, 1 }
    local needed = max - 1
    for i = 1, needed do
        local tick = bar.ticks[i]
        if not tick then
            tick = bar:CreateTexture(nil, "OVERLAY")
            bar.ticks[i] = tick
        end
        tick:SetColorTexture(tc[1], tc[2], tc[3], tc[4] or 1)
        tick:ClearAllPoints()

        if isVertical then
            -- Vertical bar: ticks go along height (Y axis)
            local y = (i / max) * height
            tick:SetPoint("BOTTOM", bar.StatusBar, "BOTTOM", 0, snapPx(y - (tickThickness / 2), tickPx))
            tick:SetSize(width, tickThickness)
        else
            -- Horizontal bar: ticks go along width (X axis)
            local x = (i / max) * width
            tick:SetPoint("LEFT", bar.StatusBar, "LEFT", snapPx(x - (tickThickness / 2), tickPx), 0)
            tick:SetSize(tickThickness, height)
        end
        tick:Show()
    end

    -- Hide extra ticks
    for i = needed + 1, #bar.ticks do
        if bar.ticks[i] then
            bar.ticks[i]:Hide()
        end
    end
end

function QUICore:UpdatePowerBarIndicators(bar, max, isVertical)
    if not bar then return end
    bar.indicatorLines = bar.indicatorLines or {}

    local cfg = self.db and self.db.profile and self.db.profile.powerBar
    local indicatorCfg = cfg and cfg.indicators
    local values = GetIndicatorValuesForCurrentSpec(indicatorCfg, max)
    local thickness = indicatorCfg and indicatorCfg.thickness or 1
    local color = indicatorCfg and indicatorCfg.color or { 1, 1, 1, 1 }

    UpdateBarIndicatorLines(bar, bar.indicatorLines, values, max, thickness, color, isVertical)
end

-- Global callback for NCDM to update locked power bar width and position
_G.QUI_UpdateLockedPowerBar = function()
    -- During combat, Blizzard mutates CDM viewer sizes so GetCenter()
    -- returns incorrect positions.  Defer to post-combat RefreshAll.
    if InCombatLockdown() then return end
    -- During CDM Edit Mode, viewer dimensions are transient — don't persist
    -- them to cfg.width or the bar will flash at the Edit Mode width on
    -- next load.  Use QUI's own flag (not Blizzard's IsEditModeActive which
    -- can lag behind our exit callback).
    if _G.QUI_IsCDMEditModeHidden and _G.QUI_IsCDMEditModeHidden() then return end

    local core = GetCore()
    if not core or not core.db then return end

    local cfg = core.db.profile.powerBar
    if not cfg.enabled or not cfg.lockedToEssential then return end

    local essentialViewer = _G.QUI_GetCDMViewerFrame("essential")
    if not essentialViewer or not essentialViewer:IsShown() then return end

    local evs = GetViewerState(essentialViewer)
    local isVerticalCDM = (evs and evs.layoutDir) == "VERTICAL"

    local newWidth, newOffsetX, newOffsetY
    local barBorderSize = cfg.borderSize or 1

    local savedW, savedH = GetSavedViewerDims("essential")

    if isVerticalCDM then
        -- Vertical CDM: bar goes to the RIGHT, length matches total height
        local totalHeight = (evs and evs.totalHeight) or savedH
        if not totalHeight or totalHeight <= 0 then return end

        -- Width (bar length) = total CDM height + borders
        local topBottomBorderSize = (evs and evs.row1BorderSize) or 0
        local targetWidth = totalHeight + (2 * topBottomBorderSize) - (2 * barBorderSize)
        newWidth = math_floor(targetWidth + 0.5)

        -- Position to the right of Essential
        local essentialCenterX = Helpers.SafeValue(essentialViewer:GetCenter(), nil)
        local _, essentialCenterY = essentialViewer:GetCenter()
        essentialCenterY = Helpers.SafeValue(essentialCenterY, nil)
        local screenCenterX = Helpers.SafeValue(UIParent:GetCenter(), nil)
        local _, screenCenterY = UIParent:GetCenter()
        screenCenterY = Helpers.SafeValue(screenCenterY, nil)
        local totalWidth = (evs and evs.iconWidth) or savedW
        if totalWidth <= 0 then return end
        local barThickness = cfg.height or 6

        if essentialCenterX and essentialCenterY and screenCenterX and screenCenterY then
            -- CDM's visual right edge (GetWidth includes visual bounds)
            local rightColBorderSize = (evs and evs.bottomRowBorderSize) or 0
            local cdmVisualRight = essentialCenterX + (totalWidth / 2) + rightColBorderSize

            -- Power bar center X = visual right + bar thickness/2 + border
            local powerBarCenterX = cdmVisualRight + (barThickness / 2) + barBorderSize

            newOffsetX = math_floor(powerBarCenterX - screenCenterX + 0.5) - 4
            newOffsetY = math_floor(essentialCenterY - screenCenterY + 0.5)
        end
    else
        -- Horizontal CDM: bar below, width matches raw row content width
        -- (before HUD min-width inflation) so bar matches actual icon span.
        local rowWidth = GetRawRow1Width(evs) or savedW
        if not rowWidth or rowWidth <= 0 then return end

        local row1BorderSize = (evs and evs.row1BorderSize) or 0
        local targetWidth = rowWidth + (2 * row1BorderSize) - (2 * barBorderSize)
        newWidth = math_floor(targetWidth + 0.5)

        -- Center horizontally with Essential
        local rawCenterX = Helpers.SafeValue(essentialViewer:GetCenter(), nil)
        local rawScreenX = Helpers.SafeValue(UIParent:GetCenter(), nil)
        if rawCenterX and rawScreenX then
            local essentialCenterX = math_floor(rawCenterX + 0.5)
            local screenCenterX = math_floor(rawScreenX + 0.5)
            newOffsetX = essentialCenterX - screenCenterX
        end
    end


    -- First CDM update: mark primary locked bar as ready so it becomes visible.
    local needsUpdate = false
    if not _primaryLockedReady then
        _primaryLockedReady = true
        needsUpdate = true
    end

    if newWidth and cfg.width ~= newWidth then
        cfg.width = newWidth
        needsUpdate = true
    end
    if newOffsetX and cfg.offsetX ~= newOffsetX then
        cfg.offsetX = newOffsetX
        needsUpdate = true
    end
    if newOffsetY and cfg.offsetY ~= newOffsetY then
        cfg.offsetY = newOffsetY
        needsUpdate = true
    end

    if needsUpdate then
        core:UpdatePowerBar()
    end
end

-- Global callback for NCDM to update power bar locked to Utility
_G.QUI_UpdateLockedPowerBarToUtility = function()
    if InCombatLockdown() then return end
    if _G.QUI_IsCDMEditModeHidden and _G.QUI_IsCDMEditModeHidden() then return end

    local core = GetCore()
    if not core or not core.db then return end

    local cfg = core.db.profile.powerBar
    if not cfg.enabled or not cfg.lockedToUtility then return end

    local utilityViewer = _G.QUI_GetCDMViewerFrame("utility")
    if not utilityViewer or not utilityViewer:IsShown() then return end

    local uvs = GetViewerState(utilityViewer)
    local isVerticalCDM = (uvs and uvs.layoutDir) == "VERTICAL"

    local newWidth, newOffsetX, newOffsetY
    local barBorderSize = cfg.borderSize or 1

    local savedW, savedH = GetSavedViewerDims("utility")

    if isVerticalCDM then
        -- Vertical CDM: bar goes to the LEFT (Utility is typically on right side of screen)
        local totalHeight = (uvs and uvs.totalHeight) or savedH
        if not totalHeight or totalHeight <= 0 then return end

        -- Width (bar length) = total CDM height
        local row1BorderSize = (uvs and uvs.row1BorderSize) or 0
        local targetWidth = totalHeight + (2 * row1BorderSize) - (2 * barBorderSize)
        newWidth = math_floor(targetWidth + 0.5)

        -- Position to the LEFT of Utility
        local utilityCenterX, utilityCenterY = utilityViewer:GetCenter()
        local screenCenterX, screenCenterY = UIParent:GetCenter()
        local totalWidth = (uvs and uvs.iconWidth) or savedW
        if totalWidth <= 0 then return end
        local barThickness = cfg.height or 6

        if utilityCenterX and utilityCenterY and screenCenterX and screenCenterY then
            -- CDM's visual left edge (GetWidth includes visual bounds)
            local row1BorderSizePos = (uvs and uvs.row1BorderSize) or 0
            local cdmVisualLeft = utilityCenterX - (totalWidth / 2) - row1BorderSizePos

            -- Power bar center X = visual left - bar thickness/2 - border
            local powerBarCenterX = cdmVisualLeft - (barThickness / 2) - barBorderSize

            newOffsetX = math_floor(powerBarCenterX - screenCenterX + 0.5) + 1
            newOffsetY = math_floor(utilityCenterY - screenCenterY + 0.5)
        end
    else
        -- Horizontal CDM: bar below, width matches raw row content width
        local rowWidth = GetRawBottomRowWidth(uvs) or savedW
        if not rowWidth or rowWidth <= 0 then return end

        local bottomRowBorderSize = (uvs and uvs.bottomRowBorderSize) or 0
        local targetWidth = rowWidth + (2 * bottomRowBorderSize) - (2 * barBorderSize)
        newWidth = math_floor(targetWidth + 0.5)

        -- Center horizontally with Utility
        local rawCenterX = utilityViewer:GetCenter()
        local rawScreenX = UIParent:GetCenter()
        if rawCenterX and rawScreenX then
            local utilityCenterX = math_floor(rawCenterX + 0.5)
            local screenCenterX = math_floor(rawScreenX + 0.5)
            newOffsetX = utilityCenterX - screenCenterX
        end
    end

    -- First CDM update: mark primary locked bar as ready (Utility lock path).
    local needsUpdate = false
    if not _primaryLockedReady then
        _primaryLockedReady = true
        needsUpdate = true
    end

    if newWidth and cfg.width ~= newWidth then
        cfg.width = newWidth
        needsUpdate = true
    end
    if newOffsetX and cfg.offsetX ~= newOffsetX then
        cfg.offsetX = newOffsetX
        needsUpdate = true
    end
    if newOffsetY and cfg.offsetY ~= newOffsetY then
        cfg.offsetY = newOffsetY
        needsUpdate = true
    end

    if needsUpdate then
        core:UpdatePowerBar()
    end
end

-- Cache for Primary bar dimensions (used when Secondary is locked to Primary but Primary is hidden)
local cachedPrimaryDimensions = {
    centerX = nil,
    centerY = nil,
    width = nil,
    height = nil,
    borderSize = nil,
}

-- Global callback for NCDM to update SECONDARY power bar locked to Essential
_G.QUI_UpdateLockedSecondaryPowerBar = function()
    if InCombatLockdown() then return end
    if _G.QUI_IsCDMEditModeHidden and _G.QUI_IsCDMEditModeHidden() then return end

    local core = GetCore()
    if not core or not core.db then return end

    local cfg = core.db.profile.secondaryPowerBar
    if not cfg.enabled or not cfg.lockedToEssential then return end

    local essentialViewer = _G.QUI_GetCDMViewerFrame("essential")
    if not essentialViewer or not essentialViewer:IsShown() then return end

    local evs = GetViewerState(essentialViewer)
    local isVerticalCDM = (evs and evs.layoutDir) == "VERTICAL"

    local newWidth, newOffsetX, newOffsetY
    local barBorderSize = cfg.borderSize or 1
    local barThickness = cfg.height or 8
    local savedW, savedH = GetSavedViewerDims("essential")

    if isVerticalCDM then
        -- Vertical CDM: bar goes to the RIGHT, length matches total height
        local totalHeight = (evs and evs.totalHeight) or savedH
        if not totalHeight or totalHeight <= 0 then return end

        -- Width (bar length) = total CDM height + borders
        local topBottomBorderSize = (evs and evs.row1BorderSize) or 0
        local targetWidth = totalHeight + (2 * topBottomBorderSize) - (2 * barBorderSize)
        newWidth = math_floor(targetWidth + 0.5)

        -- Position to the right of Essential
        local essentialCenterX, essentialCenterY = essentialViewer:GetCenter()
        local screenCenterX, screenCenterY = UIParent:GetCenter()
        local totalWidth = (evs and evs.iconWidth) or savedW
        if totalWidth <= 0 then return end

        if essentialCenterX and essentialCenterY and screenCenterX and screenCenterY then
            -- CDM's visual right edge (GetWidth includes visual bounds)
            local rightColBorderSize = (evs and evs.bottomRowBorderSize) or 0
            local cdmVisualRight = essentialCenterX + (totalWidth / 2) + rightColBorderSize

            -- Power bar center X = visual right + bar thickness/2 + border
            local powerBarCenterX = cdmVisualRight + (barThickness / 2) + barBorderSize

            newOffsetX = math_floor(powerBarCenterX - screenCenterX + 0.5) - 4
            newOffsetY = math_floor(essentialCenterY - screenCenterY + 0.5)
        end
    else
        -- Horizontal CDM: bar above, width matches raw row content width
        local rowWidth = GetRawRow1Width(evs) or savedW
        if not rowWidth or rowWidth <= 0 then return end

        local row1BorderSize = (evs and evs.row1BorderSize) or 0
        local targetWidth = rowWidth + (2 * row1BorderSize) - (2 * barBorderSize)
        newWidth = math_floor(targetWidth + 0.5)

        local rawCenterX, rawCenterY = essentialViewer:GetCenter()
        local rawScreenX, rawScreenY = UIParent:GetCenter()

        if rawCenterX and rawCenterY and rawScreenX and rawScreenY then
            local essentialCenterX = math_floor(rawCenterX + 0.5)
            local essentialCenterY = math_floor(rawCenterY + 0.5)
            local screenCenterX = math_floor(rawScreenX + 0.5)
            local screenCenterY = math_floor(rawScreenY + 0.5)
            newOffsetX = essentialCenterX - screenCenterX
            -- Y offset (position above Essential CDM)
            local totalHeight = (evs and evs.totalHeight) or savedH
            if totalHeight > 0 then
                local cdmVisualTop = essentialCenterY + (totalHeight / 2) + row1BorderSize
                local powerBarCenterY = cdmVisualTop + (barThickness / 2) + barBorderSize
                newOffsetY = math_floor(powerBarCenterY - screenCenterY + 0.5) - 1
            end
        end
    end

    -- First CDM update: mark secondary locked bar as ready.
    local needsUpdate = false
    if not _secondaryLockedReady then
        _secondaryLockedReady = true
        needsUpdate = true
    end

    if newWidth and cfg.width ~= newWidth then
        cfg.width = newWidth
        needsUpdate = true
    end
    if newOffsetX and cfg.lockedBaseX ~= newOffsetX then
        cfg.lockedBaseX = newOffsetX
        needsUpdate = true
    end
    if newOffsetY and cfg.lockedBaseY ~= newOffsetY then
        cfg.lockedBaseY = newOffsetY
        needsUpdate = true
    end

    if needsUpdate then
        core:UpdateSecondaryPowerBar()
    end
end

-- Global callback for NCDM to update SECONDARY power bar locked to Utility
_G.QUI_UpdateLockedSecondaryPowerBarToUtility = function()
    if InCombatLockdown() then return end
    if _G.QUI_IsCDMEditModeHidden and _G.QUI_IsCDMEditModeHidden() then return end

    local core = GetCore()
    if not core or not core.db then return end

    local cfg = core.db.profile.secondaryPowerBar
    if not cfg.enabled or not cfg.lockedToUtility then return end

    local utilityViewer = _G.QUI_GetCDMViewerFrame("utility")
    if not utilityViewer or not utilityViewer:IsShown() then return end

    local uvs = GetViewerState(utilityViewer)
    local isVerticalCDM = (uvs and uvs.layoutDir) == "VERTICAL"

    local newWidth, newOffsetX, newOffsetY
    local barBorderSize = cfg.borderSize or 1
    local barThickness = cfg.height or 8
    local savedW, savedH = GetSavedViewerDims("utility")

    if isVerticalCDM then
        -- Vertical CDM: bar goes to the LEFT (Utility is typically on right side of screen)
        local totalHeight = (uvs and uvs.totalHeight) or savedH
        if not totalHeight or totalHeight <= 0 then return end

        -- Width (bar length) = total CDM height
        local row1BorderSize = (uvs and uvs.row1BorderSize) or 0
        local targetWidth = totalHeight + (2 * row1BorderSize) - (2 * barBorderSize)
        newWidth = math_floor(targetWidth + 0.5)

        -- Position to the LEFT of Utility
        local utilityCenterX, utilityCenterY = utilityViewer:GetCenter()
        local screenCenterX, screenCenterY = UIParent:GetCenter()
        local totalWidth = (uvs and uvs.iconWidth) or savedW
        if totalWidth <= 0 then return end

        if utilityCenterX and utilityCenterY and screenCenterX and screenCenterY then
            -- CDM's visual left edge (GetWidth includes visual bounds)
            local cdmVisualLeft = utilityCenterX - (totalWidth / 2)

            -- Power bar center X = visual left - bar thickness/2
            local powerBarCenterX = cdmVisualLeft - (barThickness / 2)

            newOffsetX = math_floor(powerBarCenterX - screenCenterX + 0.5)
            newOffsetY = math_floor(utilityCenterY - screenCenterY + 0.5)
        end
    else
        -- Horizontal CDM: bar below, width matches raw row content width
        local rowWidth = GetRawBottomRowWidth(uvs) or savedW
        if not rowWidth or rowWidth <= 0 then return end

        local bottomRowBorderSize = (uvs and uvs.bottomRowBorderSize) or 0
        local targetWidth = rowWidth + (2 * bottomRowBorderSize) - (2 * barBorderSize)
        newWidth = math_floor(targetWidth + 0.5)

        local rawCenterX, rawCenterY = utilityViewer:GetCenter()
        local rawScreenX, rawScreenY = UIParent:GetCenter()

        if rawCenterX and rawCenterY and rawScreenX and rawScreenY then
            local utilityCenterX = math_floor(rawCenterX + 0.5)
            local utilityCenterY = math_floor(rawCenterY + 0.5)
            local screenCenterX = math_floor(rawScreenX + 0.5)
            local screenCenterY = math_floor(rawScreenY + 0.5)
            newOffsetX = utilityCenterX - screenCenterX
            -- Y offset (position below Utility CDM)
            local totalHeight = (uvs and uvs.totalHeight) or savedH
            if totalHeight > 0 then
                local cdmVisualBottom = utilityCenterY - (totalHeight / 2) - bottomRowBorderSize
                local powerBarCenterY = cdmVisualBottom - (barThickness / 2) - barBorderSize
                newOffsetY = math_floor(powerBarCenterY - screenCenterY + 0.5) + 1
            end
        end
    end

    -- First CDM update: mark secondary locked bar as ready (Utility lock path).
    local needsUpdate = false
    if not _secondaryLockedReady then
        _secondaryLockedReady = true
        needsUpdate = true
    end

    if newWidth and cfg.width ~= newWidth then
        cfg.width = newWidth
        needsUpdate = true
    end
    if newOffsetX and cfg.lockedBaseX ~= newOffsetX then
        cfg.lockedBaseX = newOffsetX
        needsUpdate = true
    end
    if newOffsetY and cfg.lockedBaseY ~= newOffsetY then
        cfg.lockedBaseY = newOffsetY
        needsUpdate = true
    end

    if needsUpdate then
        QUICore:UpdateSecondaryPowerBar()
    end
end

-- SECONDARY POWER BAR

function QUICore:GetSecondaryPowerBar()
    if self.secondaryPowerBar then return self.secondaryPowerBar end

    local cfg = self.db.profile.secondaryPowerBar

    -- Always parent to UIParent so secondary power bar works independently
    local bar = CreateFrame("Frame", ADDON_NAME .. "SecondaryPowerBar", UIParent)
    bar:SetFrameStrata("MEDIUM")
    -- Apply HUD layer priority
    local layerPriority = self.db.profile.hudLayering and self.db.profile.hudLayering.secondaryPowerBar or 6
    local frameLevel = self:GetHUDFrameLevel(layerPriority)
    bar:SetFrameLevel(frameLevel)
    bar:SetHeight(QUICore:PixelRound(cfg.height or 4, bar))
    QUICore:SetSnappedPoint(bar, "CENTER", UIParent, "CENTER", cfg.offsetX or 0, cfg.offsetY or 12)

    -- Calculate width - use configured width or fallback.
    -- Avoid reading essentialViewer:GetWidth() here: at creation time CDM
    -- LayoutViewer has not run yet, so the Blizzard frame width is stale/wrong.
    -- Use raw content width (before HUD min-width inflation) so bars match
    -- the actual icon span, not the inflated proxy bounds.
    local width = cfg.width or 0
    if width <= 0 then
        local essentialViewer = _G.QUI_GetCDMViewerFrame("essential")
        if essentialViewer then
            local evs = GetViewerState(essentialViewer)
            width = GetRawContentWidth(evs) or 0
        end
        if width <= 0 then
            width = QUICore.db and QUICore.db.profile and QUICore.db.profile.ncdm
                and QUICore.db.profile.ncdm._lastEssentialWidth or 0
        end
        if width <= 0 then
            width = 200  -- Fallback width
        end
    end

    bar:SetWidth(QUICore:PixelRound(width, bar))

    -- BACKGROUND
    local bgColor = cfg.bgColor or { 0.15, 0.15, 0.15, 1 }
    bar.Background = UIKit.CreateBackground(bar, bgColor[1], bgColor[2], bgColor[3], bgColor[4] or 1)

    -- STATUS BAR (for non-fragmented resources)
    bar.StatusBar = CreateFrame("StatusBar", nil, bar)
    bar.StatusBar:SetAllPoints()
    local tex = LSM:Fetch("statusbar", GetBarTexture(cfg))
    bar.StatusBar:SetStatusBarTexture(tex)
    bar.StatusBar:SetFrameLevel(bar:GetFrameLevel())

    -- BORDER (pixel-perfect)
    UIKit.CreateBackdropBorder(bar, cfg.borderSize or 1, 0, 0, 0, 1)

    -- TEXT FRAME (same strata, +2 levels to render above bar content but stay within element's layer band)
    bar.TextFrame = CreateFrame("Frame", nil, bar)
    bar.TextFrame:SetAllPoints(bar)
    bar.TextFrame:SetFrameStrata("MEDIUM")
    bar.TextFrame:SetFrameLevel(frameLevel + 2)

    bar.TextValue = bar.TextFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    ApplyPowerBarTextPlacement(bar, cfg)
    bar.TextValue:SetFont(GetGeneralFont(), QUICore:PixelRound(cfg.textSize or 12, bar.TextValue), GetGeneralFontOutline())
    bar.TextValue:SetShadowOffset(0, 0)
    bar.TextValue:SetText("0")

    -- Fake decimal for Destro shards
    bar.SoulShardDecimal = bar.TextFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    bar.SoulShardDecimal:SetFont(GetGeneralFont(), QUICore:PixelRound(cfg.textSize or 12, bar.SoulShardDecimal), GetGeneralFontOutline())
    bar.SoulShardDecimal:SetShadowOffset(0, 0)
    bar.SoulShardDecimal:SetText(".")
    bar.SoulShardDecimal:Hide()


    -- FRAGMENTED POWER BARS (for Runes)
    bar.FragmentedPowerBars = {}
    bar.FragmentedPowerBarTexts = {}

    -- CHARGED COMBO POINT OVERLAYS
    bar.chargedOverlays = {}

    -- TICKS
    bar.ticks = {}
    bar.indicatorLines = {}

    bar:Hide()

    self.secondaryPowerBar = bar
    return bar
end

function QUICore:CreateFragmentedPowerBars(bar, resource, isVertical)
    local cfg = self.db.profile.secondaryPowerBar
    local maxPower = UnitPowerMax("player", resource)

    for i = 1, maxPower do
        if not bar.FragmentedPowerBars[i] then
            local fragmentBar = CreateFrame("StatusBar", nil, bar)
            local tex = LSM:Fetch("statusbar", GetBarTexture(cfg))
            fragmentBar:SetStatusBarTexture(tex)
            fragmentBar:GetStatusBarTexture()
            fragmentBar:SetOrientation(isVertical and "VERTICAL" or "HORIZONTAL")
            fragmentBar:SetFrameLevel(bar.StatusBar:GetFrameLevel())
            bar.FragmentedPowerBars[i] = fragmentBar
            
            -- Create text for reload time display (pixel-perfect)
            local text = fragmentBar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            QUICore:SetSnappedPoint(text, "CENTER", fragmentBar, "CENTER", cfg.runeTimerTextX or 0, cfg.runeTimerTextY or 0)
            text:SetJustifyH("CENTER")
            text:SetFont(GetGeneralFont(), QUICore:PixelRound(cfg.runeTimerTextSize or 10, text), GetGeneralFontOutline())
            text:SetShadowOffset(0, 0)
            text:SetText("")
            bar.FragmentedPowerBarTexts[i] = text
        end
    end
end

function QUICore:UpdateFragmentedPowerDisplay(bar, resource, isVertical)
    local cfg = self.db.profile.secondaryPowerBar
    local maxPower = UnitPowerMax("player", resource)
    if maxPower <= 0 then return end

    local barWidth = bar:GetWidth()
    local barHeight = bar:GetHeight()

    -- Calculate fragment dimensions based on orientation
    local fragmentedBarWidth, fragmentedBarHeight
    if isVertical then
        fragmentedBarHeight = barHeight / maxPower
        fragmentedBarWidth = barWidth
    else
        fragmentedBarWidth = barWidth / maxPower
        fragmentedBarHeight = barHeight
    end
    
    -- Hide the main status bar fill (we display bars representing one (1) unit of resource each)
    bar.StatusBar:SetAlpha(0)

    -- Update texture for all fragmented bars
    local tex = LSM:Fetch("statusbar", GetDefaultTexture())
    for i = 1, maxPower do
        if bar.FragmentedPowerBars[i] then
            bar.FragmentedPowerBars[i]:SetStatusBarTexture(tex)
        end
    end

    -- Determine color based on checkboxes: Power Type > Class > Custom
    local color

    if cfg.usePowerColor then
        -- Power type color
        color = GetResourceColor(resource)
    elseif cfg.useClassColor then
        local _, class = UnitClass("player")
        local classColor = RAID_CLASS_COLORS[class]
        if classColor then
            color = { r = classColor.r, g = classColor.g, b = classColor.b }
        else
            color = GetResourceColor(resource)
        end
    elseif cfg.useCustomColor and cfg.customColor then
        -- Custom color override
        local c = cfg.customColor
        color = { r = c[1], g = c[2], b = c[3], a = c[4] or 1 }
    else
        -- Power type color (default)
        color = GetResourceColor(resource)
    end


    if resource == Enum.PowerType.Runes then
        -- Collect rune states: ready and recharging
        local readyList = {}
        local cdList = {}
        local now = GetTime()
        
        for i = 1, maxPower do
            local start, duration, runeReady = GetRuneCooldown(i)
            if runeReady then
                table_insert(readyList, { index = i })
            else
                if start and duration and duration > 0 then
                    local elapsed = now - start
                    local remaining = math_max(0, duration - elapsed)
                    local frac = math_max(0, math_min(1, elapsed / duration))
                    table_insert(cdList, { index = i, remaining = remaining, frac = frac })
                else
                    table_insert(cdList, { index = i, remaining = math.huge, frac = 0 })
                end
            end
        end

        -- Sort cdList by ascending remaining time
        table.sort(cdList, function(a, b)
            return a.remaining < b.remaining
        end)

        -- Build final display order: ready runes first, then CD runes sorted
        local displayOrder = {}
        local readyLookup = {}
        local cdLookup = {}
        
        for _, v in ipairs(readyList) do
            table_insert(displayOrder, v.index)
            readyLookup[v.index] = true
        end
        
        for _, v in ipairs(cdList) do
            table_insert(displayOrder, v.index)
            cdLookup[v.index] = v
        end

        for pos = 1, #displayOrder do
            local runeIndex = displayOrder[pos]
            local runeFrame = bar.FragmentedPowerBars[runeIndex]
            local runeText = bar.FragmentedPowerBarTexts[runeIndex]

            if runeFrame then
                runeFrame:ClearAllPoints()
                runeFrame:SetSize(fragmentedBarWidth, fragmentedBarHeight)
                if isVertical then
                    runeFrame:SetPoint("BOTTOM", bar, "BOTTOM", 0, (pos - 1) * fragmentedBarHeight)
                else
                    runeFrame:SetPoint("LEFT", bar, "LEFT", (pos - 1) * fragmentedBarWidth, 0)
                end

                -- Update rune timer text position and font size
                if runeText then
                    runeText:ClearAllPoints()
                    QUICore:SetSnappedPoint(runeText, "CENTER", runeFrame, "CENTER", cfg.runeTimerTextX or 0, cfg.runeTimerTextY or 0)
                    runeText:SetFont(GetGeneralFont(), QUICore:PixelRound(cfg.runeTimerTextSize or 10, runeText), GetGeneralFontOutline())
                    runeText:SetShadowOffset(0, 0)
                end

                if readyLookup[runeIndex] then
                    -- Ready rune
                    runeFrame:SetMinMaxValues(0, 1)
                    runeFrame:SetValue(1)
                    runeText:SetText("")
                    runeFrame:SetStatusBarColor(color.r, color.g, color.b)
                else
                    -- Recharging rune
                    local cdInfo = cdLookup[runeIndex]
                    if cdInfo then
                        runeFrame:SetMinMaxValues(0, 1)
                        runeFrame:SetValue(cdInfo.frac)
                        
                        -- Only show timer text if enabled
                        if cfg.showFragmentedPowerBarText ~= false then
                            runeText:SetFormattedText("%.1f", math_max(0, cdInfo.remaining))
                        else
                            runeText:SetText("")
                        end
                        
                        runeFrame:SetStatusBarColor(color.r * 0.5, color.g * 0.5, color.b * 0.5)
                    else
                        runeFrame:SetMinMaxValues(0, 1)
                        runeFrame:SetValue(0)
                        runeText:SetText("")
                        runeFrame:SetStatusBarColor(color.r * 0.5, color.g * 0.5, color.b * 0.5)
                    end
                end

                runeFrame:Show()
            end
        end

        -- Hide any extra rune frames beyond current maxPower
        for i = maxPower + 1, #bar.FragmentedPowerBars do
            if bar.FragmentedPowerBars[i] then
                bar.FragmentedPowerBars[i]:Hide()
                if bar.FragmentedPowerBarTexts[i] then
                    bar.FragmentedPowerBarTexts[i]:SetText("")
                end
            end
        end
        
        -- Add ticks between rune segments if enabled (pixel-perfect)
        if cfg.showTicks then
            local runeTickPx = QUICore:GetPixelSize(bar)
            local tickThickness = (cfg.tickThickness or 1) * runeTickPx
            local tc = cfg.tickColor or { 0, 0, 0, 1 }
            for i = 1, maxPower - 1 do
                local tick = bar.ticks[i]
                if not tick then
                    tick = bar:CreateTexture(nil, "OVERLAY")
                    bar.ticks[i] = tick
                end
                tick:SetColorTexture(tc[1], tc[2], tc[3], tc[4] or 1)

                tick:ClearAllPoints()
                if isVertical then
                    local y = i * fragmentedBarHeight
                    tick:SetPoint("BOTTOM", bar, "BOTTOM", 0, snapPx(y - (tickThickness / 2), runeTickPx))
                    tick:SetSize(barWidth, tickThickness)
                else
                    local x = i * fragmentedBarWidth
                    tick:SetPoint("LEFT", bar, "LEFT", snapPx(x - (tickThickness / 2), runeTickPx), 0)
                    tick:SetSize(tickThickness, barHeight)
                end
                tick:Show()
            end
            
            -- Hide extra ticks
            for i = maxPower, #bar.ticks do
                if bar.ticks[i] then
                    bar.ticks[i]:Hide()
                end
            end
        else
            -- Hide all ticks if disabled
            for _, tick in ipairs(bar.ticks) do
                tick:Hide()
            end
        end

    elseif resource == Enum.PowerType.Essence then
        -- Evoker Essence with timer-based regen extrapolation on the recharging segment
        local current = UnitPower("player", Enum.PowerType.Essence) or 0
        local now = GetTime()

        -- Calculate tick duration from regen rate (cache outside combat, may be secret in combat)
        if not InCombatLockdown() then
            local regenRate = GetPowerRegenForPowerType(Enum.PowerType.Essence)
            if regenRate and not Helpers.IsSecretValue(regenRate) and regenRate > 0 then
                essenceTickDuration = 1 / regenRate
            end
        end
        if not essenceTickDuration or essenceTickDuration <= 0 then
            essenceTickDuration = 5  -- fallback (default 0.2 regen = 5s per essence)
        end

        -- Detect essence gain — reset timer for next tick
        if essenceLastCount and current > essenceLastCount then
            if current < maxPower then
                essenceNextTick = now + essenceTickDuration
            else
                essenceNextTick = nil
            end
        end

        -- If missing essence and no timer, start one
        if current < maxPower and not essenceNextTick then
            essenceNextTick = now + essenceTickDuration
        end

        -- If full essence, clear timer
        if current >= maxPower then
            essenceNextTick = nil
        end

        essenceLastCount = current

        -- Calculate partial fill from timer extrapolation
        local partialFill = 0
        if essenceNextTick and essenceTickDuration > 0 then
            local remaining = math_max(0, essenceNextTick - now)
            partialFill = math_max(0, math_min(1, 1 - (remaining / essenceTickDuration)))
        end

        for pos = 1, maxPower do
            local essenceFrame = bar.FragmentedPowerBars[pos]
            local essenceText = bar.FragmentedPowerBarTexts[pos]

            if essenceFrame then
                essenceFrame:ClearAllPoints()
                essenceFrame:SetSize(fragmentedBarWidth, fragmentedBarHeight)
                if isVertical then
                    essenceFrame:SetPoint("BOTTOM", bar, "BOTTOM", 0, (pos - 1) * fragmentedBarHeight)
                else
                    essenceFrame:SetPoint("LEFT", bar, "LEFT", (pos - 1) * fragmentedBarWidth, 0)
                end

                essenceFrame:SetMinMaxValues(0, 1)

                if pos <= current then
                    -- Full segment
                    essenceFrame:SetValue(1)
                    essenceFrame:SetStatusBarColor(color.r, color.g, color.b)
                elseif pos == current + 1 then
                    -- Recharging segment — partial fill via timer extrapolation
                    essenceFrame:SetValue(partialFill)
                    essenceFrame:SetStatusBarColor(color.r * 0.5, color.g * 0.5, color.b * 0.5)
                else
                    -- Empty segment
                    essenceFrame:SetValue(0)
                    essenceFrame:SetStatusBarColor(color.r * 0.5, color.g * 0.5, color.b * 0.5)
                end

                -- No timer text for essence segments
                if essenceText then
                    essenceText:SetText("")
                end

                essenceFrame:Show()
            end
        end

        -- Hide any extra frames beyond current maxPower
        for i = maxPower + 1, #bar.FragmentedPowerBars do
            if bar.FragmentedPowerBars[i] then
                bar.FragmentedPowerBars[i]:Hide()
                if bar.FragmentedPowerBarTexts[i] then
                    bar.FragmentedPowerBarTexts[i]:SetText("")
                end
            end
        end

        -- Ticks between essence segments
        if cfg.showTicks then
            local essTickPx = QUICore:GetPixelSize(bar)
            local tickThickness = (cfg.tickThickness or 1) * essTickPx
            local tc = cfg.tickColor or { 0, 0, 0, 1 }
            for i = 1, maxPower - 1 do
                local tick = bar.ticks[i]
                if not tick then
                    tick = bar:CreateTexture(nil, "OVERLAY")
                    bar.ticks[i] = tick
                end
                tick:SetColorTexture(tc[1], tc[2], tc[3], tc[4] or 1)

                tick:ClearAllPoints()
                if isVertical then
                    local y = i * fragmentedBarHeight
                    tick:SetPoint("BOTTOM", bar, "BOTTOM", 0, snapPx(y - (tickThickness / 2), essTickPx))
                    tick:SetSize(barWidth, tickThickness)
                else
                    local x = i * fragmentedBarWidth
                    tick:SetPoint("LEFT", bar, "LEFT", snapPx(x - (tickThickness / 2), essTickPx), 0)
                    tick:SetSize(tickThickness, barHeight)
                end
                tick:Show()
            end

            -- Hide extra ticks
            for i = maxPower, #bar.ticks do
                if bar.ticks[i] then
                    bar.ticks[i]:Hide()
                end
            end
        else
            for _, tick in ipairs(bar.ticks) do
                tick:Hide()
            end
        end
    end
end

-- Smooth rune timer update (runs at 20 FPS when runes are on cooldown)
local function RuneTimerOnUpdate(bar, delta)
    runeUpdateElapsed = runeUpdateElapsed + delta
    if runeUpdateElapsed < 0.05 then return end  -- 20 FPS throttle (smoother cooldown animation)
    runeUpdateElapsed = 0

    -- Quick update: refresh text/fill without full layout recalc
    local now = GetTime()
    local anyOnCooldown = false

    for i = 1, 6 do
        local runeFrame = bar.FragmentedPowerBars and bar.FragmentedPowerBars[i]
        local runeText = bar.FragmentedPowerBarTexts and bar.FragmentedPowerBarTexts[i]
        if runeFrame and runeFrame:IsShown() then
            local start, duration, runeReady = GetRuneCooldown(i)
            if not runeReady and start and duration and duration > 0 then
                anyOnCooldown = true
                local remaining = math_max(0, duration - (now - start))
                local frac = math_max(0, math_min(1, (now - start) / duration))
                runeFrame:SetValue(frac)
                if runeText then
                    local cfg = QUICore.db.profile.secondaryPowerBar
                    if cfg.showFragmentedPowerBarText ~= false then
                        -- Only reformat when the truncated value changes (avoids per-tick string.format)
                        local rounded = math_floor(remaining * 10)
                        if rounded ~= _lastRuneRounded[i] then
                            _lastRuneRounded[i] = rounded
                            _lastRuneFormatted[i] = string_format("%.1f", remaining)
                        end
                        runeText:SetText(_lastRuneFormatted[i])
                    else
                        runeText:SetText("")
                    end
                end
            end
        end
    end

    -- Auto-disable when all runes are ready
    if not anyOnCooldown then
        bar:SetScript("OnUpdate", nil)
        runeUpdateRunning = false
        -- Clear format cache so next cooldown cycle starts fresh
        wipe(_lastRuneRounded)
        wipe(_lastRuneFormatted)
    end
end

-- Smooth essence regen timer update (runs at 20 FPS while essence is recharging)
local function EssenceTimerOnUpdate(bar, delta)
    essenceUpdateElapsed = essenceUpdateElapsed + delta
    if essenceUpdateElapsed < 0.05 then return end  -- 20 FPS throttle
    essenceUpdateElapsed = 0

    local maxPower = UnitPowerMax("player", Enum.PowerType.Essence)
    if maxPower <= 0 then return end

    local current = UnitPower("player", Enum.PowerType.Essence) or 0

    -- At max essence, disable the timer
    if current >= maxPower then
        bar:SetScript("OnUpdate", nil)
        essenceUpdateRunning = false
        essenceNextTick = nil
        -- Set all visible segments to full
        for i = 1, maxPower do
            local essenceFrame = bar.FragmentedPowerBars and bar.FragmentedPowerBars[i]
            if essenceFrame and essenceFrame:IsShown() then
                essenceFrame:SetValue(1)
            end
        end
        return
    end

    -- Detect essence gain — reset timer for next tick
    if essenceLastCount and current > essenceLastCount then
        if current < maxPower then
            essenceNextTick = GetTime() + (essenceTickDuration or 5)
        else
            essenceNextTick = nil
        end
    end
    essenceLastCount = current

    -- If missing essence and no timer, start one
    if current < maxPower and not essenceNextTick then
        essenceNextTick = GetTime() + (essenceTickDuration or 5)
    end

    -- Update the recharging segment (current + 1) via timer extrapolation
    local rechargingIdx = current + 1
    if rechargingIdx <= maxPower and essenceNextTick and essenceTickDuration and essenceTickDuration > 0 then
        local now = GetTime()
        local remaining = math_max(0, essenceNextTick - now)
        local partialFill = 1 - (remaining / essenceTickDuration)
        partialFill = math_max(0, math_min(1, partialFill))

        local essenceFrame = bar.FragmentedPowerBars and bar.FragmentedPowerBars[rechargingIdx]
        if essenceFrame and essenceFrame:IsShown() then
            essenceFrame:SetValue(partialFill)
        end
    end
end

function QUICore:UpdateSecondaryPowerBarTicks(bar, resource, max)
    local cfg = self.db.profile.secondaryPowerBar

    -- Hide all ticks first
    for _, tick in ipairs(bar.ticks) do
        tick:Hide()
    end

    -- Don't show ticks if disabled, not a ticked power type, or if it's fragmented
    if not cfg.showTicks or not tickedPowerTypes[resource] or fragmentedPowerTypes[resource] then
        return
    end

    local width  = bar:GetWidth()
    local height = bar:GetHeight()
    if width <= 0 or height <= 0 then return end

    -- Determine if bar is vertical
    local orientation = cfg.orientation or "AUTO"
    local isVertical = (orientation == "VERTICAL")
    if orientation == "AUTO" then
        if cfg.lockedToEssential then
            local viewer = _G.QUI_GetCDMViewerFrame("essential")
            local vs = GetViewerState(viewer)
            isVertical = (vs and vs.layoutDir) == "VERTICAL"
        elseif cfg.lockedToUtility then
            local viewer = _G.QUI_GetCDMViewerFrame("utility")
            local vs = GetViewerState(viewer)
            isVertical = (vs and vs.layoutDir) == "VERTICAL"
        elseif cfg.lockedToPrimary then
            local primaryCfg = self.db.profile.powerBar
            if primaryCfg then
                if primaryCfg.lockedToEssential then
                    local viewer = _G.QUI_GetCDMViewerFrame("essential")
                    local vs = GetViewerState(viewer)
                    isVertical = (vs and vs.layoutDir) == "VERTICAL"
                elseif primaryCfg.lockedToUtility then
                    local viewer = _G.QUI_GetCDMViewerFrame("utility")
                    local vs = GetViewerState(viewer)
                    isVertical = (vs and vs.layoutDir) == "VERTICAL"
                end
            end
        end
    end

    -- For Soul Shards, use the display max (not the internal fractional max)
    local displayMax = max
    if resource == Enum.PowerType.SoulShards then
        displayMax = UnitPowerMax("player", resource) -- non-fractional max (usually 5)
    end

    local genTickPx = QUICore:GetPixelSize(bar)
    local tickThickness = (cfg.tickThickness or 1) * genTickPx
    local tc = cfg.tickColor or { 0, 0, 0, 1 }
    local needed = displayMax - 1
    for i = 1, needed do
        local tick = bar.ticks[i]
        if not tick then
            tick = bar:CreateTexture(nil, "OVERLAY")
            bar.ticks[i] = tick
        end
        tick:SetColorTexture(tc[1], tc[2], tc[3], tc[4] or 1)
        tick:ClearAllPoints()

        if isVertical then
            -- Vertical bar: ticks go along height (Y axis)
            local y = (i / displayMax) * height
            tick:SetPoint("BOTTOM", bar.StatusBar, "BOTTOM", 0, snapPx(y - (tickThickness / 2), genTickPx))
            tick:SetSize(width, tickThickness)
        else
            -- Horizontal bar: ticks go along width (X axis)
            local x = (i / displayMax) * width
            tick:SetPoint("LEFT", bar.StatusBar, "LEFT", snapPx(x - (tickThickness / 2), genTickPx), 0)
            tick:SetSize(tickThickness, height)
        end
        tick:Show()
    end

    -- Hide extra ticks
    for i = needed + 1, #bar.ticks do
        if bar.ticks[i] then
            bar.ticks[i]:Hide()
        end
    end
end

function QUICore:UpdateSecondaryPowerBarIndicators(bar, max, isVertical)
    if not bar then return end
    bar.indicatorLines = bar.indicatorLines or {}

    local cfg = self.db and self.db.profile and self.db.profile.secondaryPowerBar
    local indicatorCfg = cfg and cfg.indicators
    local values = GetIndicatorValuesForCurrentSpec(indicatorCfg, max)
    local thickness = indicatorCfg and indicatorCfg.thickness or 1
    local color = indicatorCfg and indicatorCfg.color or { 1, 1, 1, 1 }

    UpdateBarIndicatorLines(bar, bar.indicatorLines, values, max, thickness, color, isVertical)
end

-- CHARGED COMBO POINT OVERLAYS
function QUICore:UpdateChargedComboPoints(bar, resource, max, current, isVertical)
    bar.chargedOverlays = bar.chargedOverlays or {}

    -- Hide all existing overlays
    for _, overlay in ipairs(bar.chargedOverlays) do
        overlay:Hide()
    end

    -- Only applies to combo points
    if resource ~= Enum.PowerType.ComboPoints then return end
    if not max or max <= 0 then return end

    -- Query charged power points from the WoW API
    local chargedPoints = GetUnitChargedPowerPoints and GetUnitChargedPowerPoints("player")
    if not chargedPoints or #chargedPoints == 0 then return end

    local pc = self.db.profile.powerColors
    if not pc then return end

    local chargedColor = pc.chargedComboPoints or { 0.00, 0.68, 1.00, 1 }

    local width = bar:GetWidth()
    local height = bar:GetHeight()
    if width <= 0 or height <= 0 then return end

    local segmentSize = isVertical and (height / max) or (width / max)

    for idx, cpIndex in ipairs(chargedPoints) do
        -- cpIndex is 1-based combo point index
        if cpIndex >= 1 and cpIndex <= max then
            local overlay = bar.chargedOverlays[idx]
            if not overlay then
                overlay = CreateFrame("Frame", nil, bar, "BackdropTemplate")
                overlay.tex = overlay:CreateTexture(nil, "ARTWORK", nil, 2)
                overlay.tex:SetAllPoints()
                bar.chargedOverlays[idx] = overlay
            end

            overlay:SetFrameLevel(bar.StatusBar:GetFrameLevel() + 1)
            overlay:ClearAllPoints()

            local px = QUICore:GetPixelSize(overlay)
            if isVertical then
                local yOff = (cpIndex - 1) * segmentSize
                overlay:SetPoint("BOTTOMLEFT", bar.StatusBar, "BOTTOMLEFT", 0, QUICore:PixelRound(yOff, bar))
                overlay:SetSize(width, QUICore:PixelRound(segmentSize, bar))
            else
                local xOff = (cpIndex - 1) * segmentSize
                overlay:SetPoint("TOPLEFT", bar.StatusBar, "TOPLEFT", QUICore:PixelRound(xOff, bar), 0)
                overlay:SetSize(QUICore:PixelRound(segmentSize, bar), height)
            end

            -- Color fill only on filled charged points
            local isFilled = cpIndex <= current
            if isFilled then
                local tex = LSM:Fetch("statusbar", GetBarTexture(self.db.profile.secondaryPowerBar))
                overlay.tex:SetTexture(tex)
                overlay.tex:SetVertexColor(chargedColor[1], chargedColor[2], chargedColor[3], chargedColor[4] or 1)
            else
                overlay.tex:SetTexture(nil)
            end

            -- Border outline always visible on charged positions
            overlay:SetBackdrop({
                edgeFile = "Interface\\Buttons\\WHITE8x8",
                edgeSize = px,
            })
            overlay:SetBackdropBorderColor(chargedColor[1], chargedColor[2], chargedColor[3], chargedColor[4] or 1)
            overlay:Show()
        end
    end

    -- Hide extra overlays
    for i = #chargedPoints + 1, #bar.chargedOverlays do
        if bar.chargedOverlays[i] then
            bar.chargedOverlays[i]:Hide()
        end
    end
end

function QUICore:UpdateSecondaryPowerBar()
    local cfg = self.db.profile.secondaryPowerBar
    local textCfg = GetSecondaryTextConfig(cfg)

    -- Always ensure the frame exists so the global name "QUISecondaryPowerBar"
    -- is available for Edit Mode layout anchoring even when the bar is disabled.
    local bar = self:GetSecondaryPowerBar()

    -- Keep swap ownership in sync with the current swap state in case this
    -- function is invoked without a preceding UpdatePowerBar call.
    SyncSwapAnchorOwnership(ShouldSwapBars())

    if not cfg.enabled then
        local wasShown = bar:IsShown()
        SafeHide(bar)
        -- Visibility changed — reapply frame anchoring so fallback targets update
        if wasShown and not bar:IsShown() and _G.QUI_UpdateAnchoredFrames then
            _G.QUI_UpdateAnchoredFrames()
        end
        if self.UpdateResourceBarsProxy then self:UpdateResourceBarsProxy() end
        return
    end

    -- When locked to CDM, suppress until CDM has computed the correct width.
    if (cfg.lockedToEssential or cfg.lockedToUtility) and not _secondaryLockedReady then
        SafeHide(bar)
        return
    end
    local resource = GetSecondaryResource()

    if not resource then
        local wasShown = bar:IsShown()
        SafeHide(bar)
        -- Visibility changed — reapply frame anchoring so fallback targets update
        if wasShown and not bar:IsShown() and _G.QUI_UpdateAnchoredFrames then
            _G.QUI_UpdateAnchoredFrames()
        end
        if self.UpdateResourceBarsProxy then self:UpdateResourceBarsProxy() end
        return
    end

    -- CDM visibility can hide bars independently of bar visibility mode.
    -- Honor configured CDM fadeOutAlpha instead of forcing fully transparent.
    do -- CDM hidden alpha check (old edit mode guard removed)
        local cdmHiddenAlpha = GetCDMHiddenAlpha()
        if cdmHiddenAlpha ~= nil then
            bar:SetAlpha(cdmHiddenAlpha)
            SafeShow(bar)
            return
        end
    end

    -- Visibility mode check (always/combat/hostile)
    -- Use alpha instead of Hide so anchored frames keep their reference
    local visibilityHidden = not ShouldShowBar(cfg)
    if visibilityHidden then
        bar:SetAlpha(0)
        SafeShow(bar)
        return
    end

    -- Update HUD layer priority dynamically
    local layerPriority = self.db.profile.hudLayering and self.db.profile.hudLayering.secondaryPowerBar or 6
    local frameLevel = self:GetHUDFrameLevel(layerPriority)
    SafeSetFrameLevel(bar, frameLevel)
    if bar.TextFrame then
        SafeSetFrameLevel(bar.TextFrame, frameLevel + 2)
    end

    -- Determine effective orientation (AUTO/HORIZONTAL/VERTICAL)
    local orientation = cfg.orientation or "AUTO"
    local isVertical = (orientation == "VERTICAL")

    -- For AUTO, check if locked to a CDM viewer and inherit its orientation
    if orientation == "AUTO" then
        if cfg.lockedToEssential then
            local viewer = _G.QUI_GetCDMViewerFrame("essential")
            local vs = GetViewerState(viewer)
            isVertical = (vs and vs.layoutDir) == "VERTICAL"
        elseif cfg.lockedToUtility then
            local viewer = _G.QUI_GetCDMViewerFrame("utility")
            local vs = GetViewerState(viewer)
            isVertical = (vs and vs.layoutDir) == "VERTICAL"
        elseif cfg.lockedToPrimary then
            -- Inherit from Primary bar's locked CDM
            local primaryCfg = self.db.profile.powerBar
            if primaryCfg then
                if primaryCfg.lockedToEssential then
                    local viewer = _G.QUI_GetCDMViewerFrame("essential")
                    local vs = GetViewerState(viewer)
                    isVertical = (vs and vs.layoutDir) == "VERTICAL"
                elseif primaryCfg.lockedToUtility then
                    local viewer = _G.QUI_GetCDMViewerFrame("utility")
                    local vs = GetViewerState(viewer)
                    isVertical = (vs and vs.layoutDir) == "VERTICAL"
                end
            end
        end
    end

    -- Apply orientation to StatusBar
    bar.StatusBar:SetOrientation(isVertical and "VERTICAL" or "HORIZONTAL")

    -- =====================================================
    -- SWAP TO PRIMARY POSITION (highest priority positioning)
    -- =====================================================
    local width
    local lockedToPrimaryHandled = false

    if cfg.swapToPrimaryPosition and ShouldSwapBars() and not IsForcingNaturalDuringBootstrap() then
        -- Compute the secondary's swap target from natural slots so it works
        -- across all primary lock modes and preserves the combined bbox.
        -- Prefer live captures so swap honors user-saved anchor positions.
        local pcx, pcy, plen, pT = GetPrimaryNaturalSlotForSwap()
        local scx, scy, _, sT = GetSecondaryNaturalSlotForSwap()

        -- We own the primary AND secondary while swap is active so the
        -- anchoring system doesn't fight our SetPoint calls.
        SyncSwapAnchorOwnership(true)

        local offsetX, offsetY
        if ShouldHidePrimaryOnSwap() then
            -- Primary is invisible; secondary just lands centered on primary's
            -- natural slot (no edge-shift since there's no other visible bar
            -- to align against).  Bbox shrinks to the secondary's footprint.
            offsetX = QUICore:PixelRound(pcx, bar)
            offsetY = QUICore:PixelRound(pcy, bar)
        else
            local _, _, secondaryNewCx, secondaryNewCy = ComputeSwappedCenters(pcx, pcy, pT, scx, scy, sT, isVertical)
            offsetX = QUICore:PixelRound(secondaryNewCx, bar)
            offsetY = QUICore:PixelRound(secondaryNewCy, bar)
        end

        if (bar._cachedX ~= offsetX or bar._cachedY ~= offsetY or bar._cachedAutoMode ~= "swappedToPrimary") then
            bar:ClearAllPoints()
            bar:SetPoint("CENTER", UIParent, "CENTER", offsetX, offsetY)
            bar._cachedX = offsetX
            bar._cachedY = offsetY
            bar._cachedAnchor = nil
            bar._cachedAutoMode = "swappedToPrimary"
            if _G.QUI_UpdateAnchoredUnitFrames then
                _G.QUI_UpdateAnchoredUnitFrames()
            end
        end

        -- Width handling:
        --   * lockedToPrimary: keep existing behavior — secondary inherits
        --     primary's width, so the swapped secondary visually matches
        --     where primary used to be.
        --   * Otherwise: each bar keeps its own length when the bars exchange
        --     slots (per design — preserves user-intended sizes).
        if cfg.lockedToPrimary then
            width = plen
        else
            width = cfg.width
            if not width or width <= 0 then width = plen end
        end
        lockedToPrimaryHandled = true
    end

    -- =====================================================
    -- LOCKED TO PRIMARY MODE
    -- =====================================================
    if not lockedToPrimaryHandled and cfg.lockedToPrimary then
        local primaryBar = self.powerBar
        local primaryCfg = self.db.profile.powerBar

        if primaryBar and primaryBar:IsShown() and primaryCfg then
            -- Primary is visible - get live dimensions and cache them
            local primaryCenterX, primaryCenterY = primaryBar:GetCenter()
            local screenCenterX, screenCenterY = UIParent:GetCenter()

            if primaryCenterX and primaryCenterY and screenCenterX and screenCenterY then
                -- Round center coordinates to match Quick Position calculation
                primaryCenterX = math_floor(primaryCenterX + 0.5)
                primaryCenterY = math_floor(primaryCenterY + 0.5)
                screenCenterX = math_floor(screenCenterX + 0.5)
                screenCenterY = math_floor(screenCenterY + 0.5)
                -- Cache Primary dimensions for Standalone fallback
                -- For vertical Primary bar, GetWidth() returns thickness, GetHeight() returns length
                local primaryIsVertical = (primaryCfg.orientation == "VERTICAL")
                local primaryVisualLength = primaryIsVertical and primaryBar:GetHeight() or primaryBar:GetWidth()
                cachedPrimaryDimensions.centerX = primaryCenterX
                cachedPrimaryDimensions.centerY = primaryCenterY
                cachedPrimaryDimensions.width = primaryVisualLength
                cachedPrimaryDimensions.height = primaryCfg.height or 8
                cachedPrimaryDimensions.borderSize = primaryCfg.borderSize or 1

                local primaryHeight = cachedPrimaryDimensions.height
                local primaryBorderSize = cachedPrimaryDimensions.borderSize
                local primaryWidth = cachedPrimaryDimensions.width
                local secondaryHeight = cfg.height or 8
                local secondaryBorderSize = cfg.borderSize or 1

                local offsetX, offsetY

                if isVertical then
                    -- Vertical secondary: goes to the RIGHT of Primary
                    local primaryActualWidth = primaryBar:GetWidth()
                    local primaryVisualRight = primaryCenterX + (primaryActualWidth / 2)
                    local secondaryCenterX = primaryVisualRight + (secondaryHeight / 2)
                    offsetX = math_floor(secondaryCenterX - screenCenterX + 0.5)
                    offsetY = math_floor(primaryCenterY - screenCenterY + 0.5)
                else
                    -- Horizontal bar: Secondary goes ABOVE Primary
                    local primaryVisualTop = primaryCenterY + (primaryHeight / 2) + primaryBorderSize
                    local secondaryCenterY = primaryVisualTop + (secondaryHeight / 2) + secondaryBorderSize
                    offsetX = math_floor(primaryCenterX - screenCenterX + 0.5)
                    offsetY = math_floor(secondaryCenterY - screenCenterY + 0.5) - 1
                end

                -- Calculate width to match Primary's visual width
                local targetWidth = primaryWidth + (2 * primaryBorderSize) - (2 * secondaryBorderSize)
                width = math_floor(targetWidth + 0.5)

                -- Position the bar (add user adjustment on top of calculated base position)
                local finalX = offsetX + (cfg.offsetX or 0)
                local finalY = offsetY + (cfg.offsetY or 0)
                if not (_G.QUI_HasFrameAnchor and _G.QUI_HasFrameAnchor("secondaryPower")) and (bar._cachedX ~= finalX or bar._cachedY ~= finalY or bar._cachedAutoMode ~= "lockedToPrimary") then
                    bar:ClearAllPoints()
                    bar:SetPoint("CENTER", UIParent, "CENTER", finalX, finalY)
                    bar._cachedX = finalX
                    bar._cachedY = finalY
                    bar._cachedAnchor = nil
                    bar._cachedAutoMode = "lockedToPrimary"
                    -- Notify unit frames that may be anchored to this power bar
                    if _G.QUI_UpdateAnchoredUnitFrames then
                        _G.QUI_UpdateAnchoredUnitFrames()
                    end
                end

                lockedToPrimaryHandled = true
            else
                -- Primary bar not yet laid out (GetCenter returns nil on first frame)
                -- Defer update to allow layout to complete
                if not bar._lockedToPrimaryDeferred then
                    bar._lockedToPrimaryDeferred = true
                    C_Timer.After(0.1, function()
                        bar._lockedToPrimaryDeferred = nil
                        self:UpdateSecondaryPowerBar()
                    end)
                end
                return  -- Always return when GetCenter fails, prevents race condition fall-through
            end
        elseif cfg.standaloneMode and cachedPrimaryDimensions.centerX then
            -- Primary is hidden but Secondary is Standalone - use cached dimensions
            local screenCenterX, screenCenterY = UIParent:GetCenter()

            if screenCenterX and screenCenterY then
                -- Round screen center to match Quick Position calculation
                screenCenterX = math_floor(screenCenterX + 0.5)
                screenCenterY = math_floor(screenCenterY + 0.5)
                local primaryCenterX = cachedPrimaryDimensions.centerX
                local primaryCenterY = cachedPrimaryDimensions.centerY
                local primaryHeight = cachedPrimaryDimensions.height
                local primaryBorderSize = cachedPrimaryDimensions.borderSize
                local primaryWidth = cachedPrimaryDimensions.width  -- This is GetWidth() from when primary was visible
                local secondaryHeight = cfg.height or 8
                local secondaryBorderSize = cfg.borderSize or 1

                local offsetX, offsetY

                if isVertical then
                    -- Vertical secondary: goes to the RIGHT of Primary (use cached actual width)
                    local primaryVisualRight = primaryCenterX + (primaryWidth / 2)
                    local secondaryCenterX = primaryVisualRight + (secondaryHeight / 2)
                    offsetX = math_floor(secondaryCenterX - screenCenterX + 0.5)
                    offsetY = math_floor(primaryCenterY - screenCenterY + 0.5)
                else
                    -- Horizontal bar: Secondary goes ABOVE Primary
                    local primaryVisualTop = primaryCenterY + (primaryHeight / 2) + primaryBorderSize
                    local secondaryCenterY = primaryVisualTop + (secondaryHeight / 2) + secondaryBorderSize
                    offsetX = math_floor(primaryCenterX - screenCenterX + 0.5)
                    offsetY = math_floor(secondaryCenterY - screenCenterY + 0.5) - 1
                end

                local targetWidth = primaryWidth + (2 * primaryBorderSize) - (2 * secondaryBorderSize)
                width = math_floor(targetWidth + 0.5)

                -- Add user adjustment on top of calculated base position
                local finalX = offsetX + (cfg.offsetX or 0)
                local finalY = offsetY + (cfg.offsetY or 0)
                if not (_G.QUI_HasFrameAnchor and _G.QUI_HasFrameAnchor("secondaryPower")) and (bar._cachedX ~= finalX or bar._cachedY ~= finalY or bar._cachedAutoMode ~= "lockedToPrimaryCached") then
                    bar:ClearAllPoints()
                    bar:SetPoint("CENTER", UIParent, "CENTER", finalX, finalY)
                    bar._cachedX = finalX
                    bar._cachedY = finalY
                    bar._cachedAnchor = nil
                    bar._cachedAutoMode = "lockedToPrimaryCached"
                    -- Notify unit frames that may be anchored to this power bar
                    if _G.QUI_UpdateAnchoredUnitFrames then
                        _G.QUI_UpdateAnchoredUnitFrames()
                    end
                end

                lockedToPrimaryHandled = true
            end
        else
            -- Primary is hidden and Secondary is NOT Standalone - hide Secondary
            SafeHide(bar)
            return
        end
    end

    -- =====================================================
    -- LEGACY POSITIONING (autoAttach or manual)
    -- =====================================================
    if not lockedToPrimaryHandled then
        -- Get anchor frame (needed for autoAttach positioning)
        local anchor = cfg.autoAttach and _G.QUI_GetCDMViewerFrame("essential") or _G[cfg.attachTo]

        -- In standalone mode, don't hide when anchor is hidden (bar is independent)
        -- Otherwise, hide if anchor doesn't exist or isn't shown.
        -- If CDM visibility says it should be visible, don't hide based on anchor
        -- visibility because the viewer may still be fading in after mount changes.
        if not cfg.standaloneMode and not cfg.lockedToEssential and not cfg.lockedToUtility then
            local cdmShouldBeVisible = _G.QUI_ShouldCDMBeVisible and _G.QUI_ShouldCDMBeVisible()
            if not anchor or (not anchor:IsShown() and not cdmShouldBeVisible) then
                SafeHide(bar)
                return
            end
        end

        -- Safety check: don't attach if anchor has invalid/zero dimensions (not yet laid out)
        if cfg.autoAttach and anchor then
            local anchorWidth = anchor:GetWidth()
            local anchorHeight = anchor:GetHeight()
            if not anchorWidth or anchorWidth <= 1 or not anchorHeight or anchorHeight <= 1 then
                -- Viewer not ready yet, defer update
                SafeHide(bar)
                C_Timer.After(0.5, function() self:UpdateSecondaryPowerBar() end)
                return
            end
        end

        -- Calculate width and height first (needed for positioning)
        local barHeight = cfg.height or 8
        if cfg.autoAttach then
            -- Auto-attach: manual width takes priority if set, otherwise use auto-detected width
            -- Priority: manual width (if > 0) > NCDM calculated width > saved width from DB > fallback
            if cfg.width and cfg.width > 0 then
                -- User has set a manual width override
                width = cfg.width
            else
                -- Auto-detect from Essential Cooldowns or Primary bar.
                -- Use raw content width so bar matches actual icon span.
                if self.powerBar and self.powerBar:IsShown() then
                    width = self.powerBar:GetWidth()
                elseif anchor then
                    local avs = GetViewerState(anchor)
                    width = GetRawContentWidth(avs)
                end
                if not width or width <= 0 then
                    -- Use saved width from last NCDM layout (persists across reloads)
                    width = self.db.profile.ncdm and self.db.profile.ncdm._lastEssentialWidth
                end
                if not width or width <= 0 then
                    width = 200 -- absolute fallback
                end
            end

            -- Only reposition when anchor/offset actually changed (prevents flicker)
            local wantedOffsetX = QUICore:PixelRound(cfg.offsetX or 0, bar)
            local wantedAnchor = (self.powerBar and self.powerBar:IsShown()) and self.powerBar or anchor

            -- If no valid anchor available, fall through to manual positioning
            if not wantedAnchor then
                -- Fall through to manual positioning below
            else
                if not (_G.QUI_HasFrameAnchor and _G.QUI_HasFrameAnchor("secondaryPower")) and (bar._cachedAnchor ~= wantedAnchor or bar._cachedX ~= wantedOffsetX or bar._cachedAutoMode ~= true) then
                    bar:ClearAllPoints()
                    bar:SetPoint("BOTTOM", wantedAnchor, "TOP", wantedOffsetX, 0)
                    bar._cachedAnchor = wantedAnchor
                    bar._cachedX = wantedOffsetX
                    bar._cachedY = nil  -- Clear manual mode cache
                    bar._cachedAutoMode = true
                    -- Notify unit frames that may be anchored to this power bar
                    if _G.QUI_UpdateAnchoredUnitFrames then
                        _G.QUI_UpdateAnchoredUnitFrames()
                    end
                end
            end
        end

        -- Manual positioning (or fallback when autoAttach has no valid anchor)
        if not cfg.autoAttach or (cfg.autoAttach and not ((self.powerBar and self.powerBar:IsShown()) or anchor)) then
            -- Manual positioning - anchor to center of screen
            -- Default width to Essential Cooldowns raw content width if not manually set
            width = cfg.width
            if not width or width <= 0 then
                -- Try to get Essential Cooldowns width (raw, before min-width inflation)
                local essentialViewer = _G.QUI_GetCDMViewerFrame("essential")
                if essentialViewer then
                    local evs = GetViewerState(essentialViewer)
                    width = GetRawContentWidth(evs)
                end
                if width and width > 0 then
                    -- Persist for next reload so bars don't flash at stale/fallback width.
                    -- Skip during Edit Mode — those dimensions are transient.
                    if not Helpers.IsEditModeActive() and self.db.profile.ncdm then
                        self.db.profile.ncdm._lastEssentialWidth = width
                    end
                else
                    width = self.db.profile.ncdm and self.db.profile.ncdm._lastEssentialWidth
                end
                if not width or width <= 0 then
                    width = 200 -- absolute fallback
                end
            end

            -- Only reposition when offsets actually changed (prevents flicker)
            -- In locked modes, add lockedBase + user adjustment; otherwise just use offset as absolute
            local baseX = (cfg.lockedToEssential or cfg.lockedToUtility) and (cfg.lockedBaseX or 0) or 0
            local baseY = (cfg.lockedToEssential or cfg.lockedToUtility) and (cfg.lockedBaseY or 0) or 0
            local wantedX, wantedY
            wantedX = QUICore:PixelRound(baseX + (cfg.offsetX or 0), bar)
            wantedY = QUICore:PixelRound(baseY + (cfg.offsetY or 0), bar)
            if not (_G.QUI_HasFrameAnchor and _G.QUI_HasFrameAnchor("secondaryPower")) and (bar._cachedX ~= wantedX or bar._cachedY ~= wantedY or bar._cachedAutoMode ~= false) then
                bar:ClearAllPoints()
                bar:SetPoint("CENTER", UIParent, "CENTER", wantedX, wantedY)
                bar._cachedX = wantedX
                bar._cachedY = wantedY
                bar._cachedAnchor = nil  -- Clear auto-attach mode cache
                bar._cachedAutoMode = false
                -- Notify unit frames that may be anchored to this power bar
                if _G.QUI_UpdateAnchoredUnitFrames then
                    _G.QUI_UpdateAnchoredUnitFrames()
                end
            end
        end
    end

    -- Geometry functions (SetHeight/SetWidth/SetPoint/ClearAllPoints) are
    -- protected on named frames during combat.  Config-driven dimensions
    -- don't change mid-fight; PLAYER_REGEN_ENABLED triggers a full update.
    if not InCombatLockdown() then
        -- For vertical bars, swap width and height (width = thickness, height = length)
        local wantedH, wantedW
        if isVertical then
            -- Vertical bar: cfg.width is the bar length (becomes height), cfg.height is thickness (becomes width)
            wantedW = QUICore:PixelRound(cfg.height or 4, bar)
            wantedH = QUICore:PixelRound(width, bar)
        else
            -- Horizontal bar: normal dimensions
            wantedH = QUICore:PixelRound(cfg.height or 4, bar)
            wantedW = QUICore:PixelRound(width, bar)
        end

        -- Only resize when dimensions actually changed (prevents flicker)
        if bar._cachedH ~= wantedH then
            bar:SetHeight(wantedH)
            bar._cachedH = wantedH
        end
        if bar._cachedW ~= wantedW then
            bar:SetWidth(wantedW)
            bar._cachedW = wantedW
        end

        -- Update border size (pixel-perfect)
        local secBorderSizePixels = cfg.borderSize or 1
        if bar._cachedBorderSize ~= secBorderSizePixels then
            if UIKit and UIKit.CreateBackdropBorder then
                bar.Border = UIKit.CreateBackdropBorder(bar, secBorderSizePixels, 0, 0, 0, 1)
                if bar.Border then
                    bar.Border:SetShown(secBorderSizePixels > 0)
                end
            end
            bar._cachedBorderSize = secBorderSizePixels
        end
    end

    -- Update background color
    local bgColor = cfg.bgColor or { 0.15, 0.15, 0.15, 1 }
    if bar.Background then
        bar.Background:SetColorTexture(bgColor[1], bgColor[2], bgColor[3], bgColor[4] or 1)
    end

    -- Only update texture when changed (prevents flicker)
    local tex = LSM:Fetch("statusbar", GetBarTexture(cfg))
    if bar._cachedTex ~= tex then
        bar.StatusBar:SetStatusBarTexture(tex)
        bar._cachedTex = tex
    end

    -- Get resource values
    local max, current, displayValue, valueType = GetSecondaryResourceValue(resource)
    if not max then
        SafeHide(bar)
        return
    end

    -- Handle fragmented power types (Runes, Essence)
    if fragmentedPowerTypes[resource] then
        self:CreateFragmentedPowerBars(bar, resource, isVertical)
        self:UpdateFragmentedPowerDisplay(bar, resource, isVertical)

        -- Essence regen animation timer
        if resource == Enum.PowerType.Essence then
            local essenceMax = UnitPowerMax("player", Enum.PowerType.Essence) or 0
            local essenceCur = UnitPower("player", Enum.PowerType.Essence) or 0
            if essenceCur < essenceMax and not essenceUpdateRunning then
                essenceUpdateRunning = true
                essenceUpdateElapsed = 0
                bar:SetScript("OnUpdate", EssenceTimerOnUpdate)
            elseif essenceCur >= essenceMax and essenceUpdateRunning then
                bar:SetScript("OnUpdate", nil)
                essenceUpdateRunning = false
            end
        end

        bar.StatusBar:SetMinMaxValues(0, max)
        bar.StatusBar:SetValue(current)

        -- Set bar color based on checkboxes: Power Type > Class > Custom
        if cfg.usePowerColor then
            local color = GetResourceColor(resource)
            bar.StatusBar:SetStatusBarColor(color.r, color.g, color.b, color.a or 1)
        elseif cfg.useClassColor then
            local _, class = UnitClass("player")
            local classColor = RAID_CLASS_COLORS[class]
            if classColor then
                bar.StatusBar:SetStatusBarColor(classColor.r, classColor.g, classColor.b)
            else
                local color = GetResourceColor(resource)
                bar.StatusBar:SetStatusBarColor(color.r, color.g, color.b, color.a or 1)
            end
        elseif cfg.useCustomColor and cfg.customColor then
            -- Custom color override
            local c = cfg.customColor
            bar.StatusBar:SetStatusBarColor(c[1], c[2], c[3], c[4] or 1)
        else
            -- Power type color (default)
            local color = GetResourceColor(resource)
            bar.StatusBar:SetStatusBarColor(color.r, color.g, color.b, color.a or 1)
        end

        bar.TextValue:SetText(tostring(current))
    else
    -- Normal bar display
    bar.StatusBar:SetAlpha(1)
    bar.StatusBar:SetMinMaxValues(0, max)
    bar.StatusBar:SetValue(current)

    -- Set bar color based on checkboxes: Power Type > Class > Custom
    if cfg.usePowerColor then
        local color = GetResourceColor(resource)
        bar.StatusBar:SetStatusBarColor(color.r, color.g, color.b, color.a or 1)
    elseif cfg.useClassColor then
        local _, class = UnitClass("player")
        local classColor = RAID_CLASS_COLORS[class]
        if classColor then
            bar.StatusBar:SetStatusBarColor(classColor.r, classColor.g, classColor.b)
        else
            local color = GetResourceColor(resource)
            bar.StatusBar:SetStatusBarColor(color.r, color.g, color.b, color.a or 1)
        end
    elseif cfg.useCustomColor and cfg.customColor then
        -- Custom color override
        local c = cfg.customColor
        bar.StatusBar:SetStatusBarColor(c[1], c[2], c[3], c[4] or 1)
    else
        -- Power type color (default)
        local color = GetResourceColor(resource)
        bar.StatusBar:SetStatusBarColor(color.r, color.g, color.b, color.a or 1)
    end


    -- Update text (safe: uses only displayValue). SetFormattedText is C-side
    -- and skips the Lua-side string allocation that SetText(string_format(...))
    -- would create per UNIT_POWER_UPDATE.
    if valueType == "shards" then
        -- Destruction Warlock: show decimal shards (e.g., 3.4)
        bar.TextValue:SetFormattedText("%.1f", displayValue or 0)
    elseif valueType == "percent" and textCfg.showPercent then
        bar.TextValue:SetText(FormatPercentValue(displayValue, textCfg))
    elseif valueType == "percent" then
        -- Stagger with showPercent off: show raw stagger amount
        local stagger = UnitStagger("player") or 0
        bar.TextValue:SetText(tostring(math_floor(stagger)))
    else
        bar.TextValue:SetText(tostring(displayValue or 0))
    end
    
    -- Hide fragmented bars
    for _, fragmentBar in ipairs(bar.FragmentedPowerBars) do
        fragmentBar:Hide()
    end
end

    -- Apply text styling (pcall-guarded so errors here cannot prevent the bar from showing)
    pcall(function()
        bar.TextValue:SetFont(GetGeneralFont(), QUICore:PixelRound(textCfg.textSize or 12, bar.TextValue), GetGeneralFontOutline())
        bar.TextValue:SetShadowOffset(0, 0)
        ApplyPowerBarTextPlacement(bar, textCfg)

        -- Apply text color
        if textCfg.textUseClassColor then
            local _, class = UnitClass("player")
            local classColor = RAID_CLASS_COLORS[class]
            if classColor then
                bar.TextValue:SetTextColor(classColor.r, classColor.g, classColor.b, 1)
            end
        else
            local c = textCfg.textCustomColor or { 1, 1, 1, 1 }
            bar.TextValue:SetTextColor(c[1], c[2], c[3], c[4] or 1)
        end

        if bar.SoulShardDecimal then
            bar.SoulShardDecimal:SetFont(GetGeneralFont(), QUICore:PixelRound(textCfg.textSize or 12, bar.SoulShardDecimal), GetGeneralFontOutline())
            bar.SoulShardDecimal:SetShadowOffset(0, 0)
            if textCfg.textUseClassColor then
                local _, class = UnitClass("player")
                local classColor = RAID_CLASS_COLORS[class]
                if classColor then
                    bar.SoulShardDecimal:SetTextColor(classColor.r, classColor.g, classColor.b, 1)
                end
            else
                local c = textCfg.textCustomColor or { 1, 1, 1, 1 }
                bar.SoulShardDecimal:SetTextColor(c[1], c[2], c[3], c[4] or 1)
            end
        end

    end)

    -- Show/hide text (outside pcall so it always applies)
    bar.TextFrame:SetShown(textCfg.showText ~= false)

    if not fragmentedPowerTypes[resource] then
        self:UpdateSecondaryPowerBarTicks(bar, resource, max)
    end
    self:UpdateSecondaryPowerBarIndicators(bar, max, isVertical)

    -- Charged combo point overlays
    self:UpdateChargedComboPoints(bar, resource, max, current, isVertical)

    -- Hide legacy decimal overlay (no longer used - decimals now rendered via string.format)
    if bar.SoulShardDecimal then
        bar.SoulShardDecimal:Hide()
    end


    bar:SetAlpha(1)
    SafeShow(bar)

    if self.UpdateResourceBarsProxy then self:UpdateResourceBarsProxy() end
    ScheduleNaturalSlotCapture()
    -- See TriggerSwapReciprocalUpdate doc: re-runs primary positioning so
    -- its swap target reflects the now-known secondary natural slot
    -- (NCDM ordering on first frame, lockedBase late-arrival, etc.).
    TriggerSwapReciprocalUpdate()
end

-- EVENT HANDLER

function QUICore:OnUnitPower(_, unit)
    -- Unit filtering now handled at the C level via RegisterUnitEvent("player").
    -- Keep the guard for callers that invoke OnUnitPower directly (e.g. PLAYER_REGEN events).
    if unit and unit ~= "player" then
        return
    end

    local db = self.db and self.db.profile
    local unthrottled = db and db.powerBar and db.powerBar.unthrottledCPU
    local now = GetTime()

    -- Primary bar
    if unthrottled or (now - lastPrimaryUpdate >= UPDATE_THROTTLE) then
        self:UpdatePowerBar()
        lastPrimaryUpdate = now
    end

    -- Secondary bar: instant for discrete resources, unthrottled mode, or throttled otherwise
    local resource = GetSecondaryResource()
    if unthrottled or instantFeedbackTypes[resource] then
        self:UpdateSecondaryPowerBar()
    elseif now - lastSecondaryUpdate >= UPDATE_THROTTLE then
        self:UpdateSecondaryPowerBar()
        lastSecondaryUpdate = now
    end
end


-- UNIT_AURA handler for aura-based resources (Maelstrom Weapon stacks)
function QUICore:OnUnitAura(_, unit)
    if unit and unit ~= "player" then return end
    local resource = GetSecondaryResource()
    if resource == Enum.PowerType.MaelstromWeapon
        or resource == Enum.PowerType.VengSoulFragments
        or (VDH_SOUL_FRAGMENTS_POWER and resource == VDH_SOUL_FRAGMENTS_POWER)
        or resource == "SOUL"
        or resource == Enum.PowerType.Whirlwind
        or resource == Enum.PowerType.TipOfTheSpear then
        self:UpdateSecondaryPowerBar()
    end
end

function QUICore:OnUnitPowerPointCharge(_, unit)
    if unit and unit ~= "player" then return end
    if GetSecondaryResource() == Enum.PowerType.ComboPoints then
        self:UpdateSecondaryPowerBar()
    end
end

-- REFRESH

local oldRefreshAll = QUICore.RefreshAll
function QUICore:RefreshAll()
    if oldRefreshAll then
        oldRefreshAll(self)
    end

    -- CDM viewer skinning now refreshes in the cooldown modules.
    self:UpdatePowerBar()
    self:UpdateSecondaryPowerBar()
end

-- EVENT-DRIVEN RUNE UPDATES
-- RUNE_POWER_UPDATE triggers full layout refresh; smooth timer enabled while runes recharge

function QUICore:OnRunePowerUpdate()
    local now = GetTime()
    if now - lastSecondaryUpdate < UPDATE_THROTTLE then
        return
    end
    lastSecondaryUpdate = now

    local resource = GetSecondaryResource()
    if resource == Enum.PowerType.Runes then
        local bar = self.secondaryPowerBar
        if bar and bar:IsShown() and fragmentedPowerTypes[resource] then
            -- Determine orientation for proper positioning
            local cfg = self.db.profile.secondaryPowerBar
            local orientation = cfg.orientation or "HORIZONTAL"
            local isVertical = (orientation == "VERTICAL")
            self:UpdateFragmentedPowerDisplay(bar, resource, isVertical)

            -- Check if any runes are on cooldown
            local anyOnCooldown = false
            for i = 1, 6 do
                local _, _, runeReady = GetRuneCooldown(i)
                if not runeReady then
                    anyOnCooldown = true
                    break
                end
            end

            -- Enable/disable smooth updater
            if anyOnCooldown and not runeUpdateRunning then
                runeUpdateRunning = true
                runeUpdateElapsed = 0
                bar:SetScript("OnUpdate", RuneTimerOnUpdate)
            elseif not anyOnCooldown and runeUpdateRunning then
                bar:SetScript("OnUpdate", nil)
                runeUpdateRunning = false
            end
        end
    end
end

-- INITIALIZATION

local function InitializeResourceBars(self)
    if self._resourceBarsInitialized then
        return
    end

    self._resourceBarsInitialized = true

    -- Register additional events
    self:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED", "OnSpecChanged")
    self:RegisterEvent("UPDATE_SHAPESHIFT_FORM", "OnShapeshiftChanged")
    self:RegisterEvent("PLAYER_ENTERING_WORLD", function()
        EnsureDemonHunterSoulBar()
        self:OnUnitPower()
        -- First-reload-with-swap-on bootstrap: capture true natural slots
        -- before applying swap so swap math sees user-anchored positions
        -- and post-NCDM offsets, not stale cfg defaults.
        ScheduleSwapBootstrap()
    end)

    -- POWER UPDATES — use a raw frame with RegisterUnitEvent("player") so
    -- high-frequency events (UNIT_POWER_FREQUENT ~10x/sec/unit) are filtered
    -- at the C level instead of dispatching through AceEvent for every unit.
    local powerEventFrame = CreateFrame("Frame")
    powerEventFrame:RegisterUnitEvent("UNIT_POWER_FREQUENT", "player")
    powerEventFrame:RegisterUnitEvent("UNIT_POWER_UPDATE", "player")
    powerEventFrame:RegisterUnitEvent("UNIT_MAXPOWER", "player")
    powerEventFrame:RegisterUnitEvent("UNIT_AURA", "player")  -- Aura-based resources (Maelstrom Weapon stacks)
    powerEventFrame:RegisterEvent("UNIT_POWER_POINT_CHARGE")  -- Charged combo points
    powerEventFrame:RegisterEvent("RUNE_POWER_UPDATE")  -- DK rune updates (no unit filter available)
    powerEventFrame:SetScript("OnEvent", function(_, event, unit, ...)
        if event == "RUNE_POWER_UPDATE" then
            self:OnRunePowerUpdate(event, unit, ...)
        elseif event == "UNIT_AURA" then
            self:OnUnitAura(event, unit, ...)
        elseif event == "UNIT_POWER_POINT_CHARGE" then
            self:OnUnitPowerPointCharge(event, unit, ...)
        else
            self:OnUnitPower(event, unit, ...)
        end
    end)

    -- Combat state events - force update on combat transitions
    -- Ensures bars show correct values when entering/exiting combat
    self:RegisterEvent("PLAYER_REGEN_DISABLED", "OnUnitPower")
    self:RegisterEvent("PLAYER_REGEN_ENABLED", "OnUnitPower")

    -- Target change - needed for visibility modes (hostile target, etc.)
    self:RegisterEvent("PLAYER_TARGET_CHANGED", "OnUnitPower")

    -- Mount state - needed so CDM visibility (hideWhenMounted, etc.) hides resource bars
    self:RegisterEvent("PLAYER_MOUNT_DISPLAY_CHANGED", "OnShapeshiftChanged")

    EnsureDemonHunterSoulBar()

    -- Initial update
    self:UpdatePowerBar()
    self:UpdateSecondaryPowerBar()

    -- Safety timeout: ensure locked bars become visible even if CDM never
    -- calls UpdateLockedPowerBar (e.g. CDM disabled, addon load order issue).
    C_Timer.After(3, function()
        local changed = false
        if not _primaryLockedReady then
            _primaryLockedReady = true
            changed = true
        end
        if not _secondaryLockedReady then
            _secondaryLockedReady = true
            changed = true
        end
        if changed then
            self:UpdatePowerBar()
            self:UpdateSecondaryPowerBar()
        end
    end)

    -- Old Edit Mode overlay callbacks removed — Layout Mode handles replace these.
end


function QUICore:OnSpecChanged()
    EnsureDemonHunterSoulBar()

    self:UpdatePowerBar()
    self:UpdateSecondaryPowerBar()

    -- Reapply frame anchoring overrides: secondary resource availability may
    -- have changed, so frames anchored to secondaryPower need to re-evaluate
    -- whether to fall back to primaryPower (or vice versa).
    if _G.QUI_UpdateAnchoredFrames then
        _G.QUI_UpdateAnchoredFrames()
    end
end

function QUICore:OnShapeshiftChanged()
    -- Druid form changes affect primary/secondary resources
    self:UpdatePowerBar()
    self:UpdateSecondaryPowerBar()

    -- Druid form changes can toggle secondary resource availability
    if _G.QUI_UpdateAnchoredFrames then
        _G.QUI_UpdateAnchoredFrames()
    end
end
if QUICore and QUICore.RegisterPostEnable then
    QUICore:RegisterPostEnable(function(core)
        InitializeResourceBars(core)
    end)
end

---------------------------------------------------------------------------
-- UNLOCK MODE ELEMENT REGISTRATION
---------------------------------------------------------------------------
do
    local function RegisterLayoutModeElements()
        local um = ns.QUI_LayoutMode
        if not um then return end

        local function GetPowerDB(which)
            local core = ns.Helpers.GetCore()
            return core and core.db and core.db.profile and core.db.profile[which]
        end

        um:RegisterElement({
            key = "primaryPower",
            label = "Primary Power",
            group = "Resource Bars",
            order = 1,
            isOwned = true,
            isEnabled = function()
                local db = GetPowerDB("powerBar")
                return db and db.enabled ~= false
            end,
            setEnabled = function(val)
                local db = GetPowerDB("powerBar")
                if db then db.enabled = val end
                if QUICore and QUICore.UpdatePowerBar then QUICore:UpdatePowerBar() end
            end,
            setGameplayHidden = function(hide)
                local f = QUICore and QUICore.powerBar
                if f then
                    if hide then f:Hide() else f:Show() end
                end
            end,
            getFrame = function()
                return QUICore and QUICore.powerBar
            end,
        })

        um:RegisterElement({
            key = "secondaryPower",
            label = "Secondary Power",
            group = "Resource Bars",
            order = 2,
            isOwned = true,
            isEnabled = function()
                local db = GetPowerDB("secondaryPowerBar")
                return db and db.enabled ~= false
            end,
            setEnabled = function(val)
                local db = GetPowerDB("secondaryPowerBar")
                if db then db.enabled = val end
                if QUICore and QUICore.UpdateSecondaryPowerBar then QUICore:UpdateSecondaryPowerBar() end
            end,
            setGameplayHidden = function(hide)
                local f = QUICore and QUICore.secondaryPowerBar
                if f then
                    if hide then f:Hide() else f:Show() end
                end
            end,
            getFrame = function()
                return QUICore and QUICore.secondaryPowerBar
            end,
        })
    end

    C_Timer.After(2, RegisterLayoutModeElements)
end

---------------------------------------------------------------------------
-- OPTIONS PANEL PREVIEW
---------------------------------------------------------------------------
do
    local POWER_DISPLAY_NAMES = {
        [Enum.PowerType.Mana]            = "Mana",
        [Enum.PowerType.Rage]            = "Rage",
        [Enum.PowerType.Focus]           = "Focus",
        [Enum.PowerType.Energy]          = "Energy",
        [Enum.PowerType.RunicPower]      = "Runic Power",
        [Enum.PowerType.SoulShards]      = "Soul Shards",
        [Enum.PowerType.LunarPower]      = "Lunar Power",
        [Enum.PowerType.HolyPower]       = "Holy Power",
        [Enum.PowerType.Maelstrom]       = "Maelstrom",
        [Enum.PowerType.Chi]             = "Chi",
        [Enum.PowerType.Insanity]        = "Insanity",
        [Enum.PowerType.ArcaneCharges]   = "Arcane Charges",
        [Enum.PowerType.Runes]           = "Runes",
        [Enum.PowerType.Fury]            = "Fury",
        [Enum.PowerType.Essence]         = "Essence",
        [Enum.PowerType.ComboPoints]     = "Combo Points",
        [Enum.PowerType.MaelstromWeapon] = "Maelstrom Weapon",
        [Enum.PowerType.TipOfTheSpear]   = "Tip of the Spear",
        [Enum.PowerType.Whirlwind]       = "Whirlwind",
        ["STAGGER"]                      = "Stagger",
        ["SOUL"]                         = "Soul Fragments",
    }
    if Enum.PowerType.VengSoulFragments then
        POWER_DISPLAY_NAMES[Enum.PowerType.VengSoulFragments] = "Soul Fragments"
    end

    local MOCK_PRIMARY_FILL             = 0.70
    local MOCK_SECONDARY_FILL           = 0.60
    local BAR_PAD_X                     = 12
    local PREVIEW_LABEL_GAP             = 2
    local PREVIEW_SECTION_GAP           = 8
    local PREVIEW_MIN_HORIZONTAL_LENGTH = 80
    local PREVIEW_MIN_VERTICAL_LENGTH   = 20
    local PREVIEW_MIN_THICKNESS         = 8
    local PREVIEW_MAX_THICKNESS         = 22
    local PREVIEW_POWER_MAX_FALLBACKS   = {
        [Enum.PowerType.MaelstromWeapon] = 10,
        [Enum.PowerType.VengSoulFragments] = 6,
        [Enum.PowerType.Whirlwind] = 4,
        [Enum.PowerType.TipOfTheSpear] = 3,
    }

    local function GetPreviewPowerMax(resource)
        if type(resource) ~= "number" then return 0 end

        -- QUI adds pseudo power IDs for aura/event tracked resources. Blizzard's
        -- UnitPowerMax rejects those IDs, so preview rendering must not pass
        -- them through the native API.
        local fallback = PREVIEW_POWER_MAX_FALLBACKS[resource]
        if fallback then return fallback end

        local ok, maxValue = pcall(UnitPowerMax, "player", resource)
        if not ok then return 0 end
        if Helpers and Helpers.SafeToNumber then
            return Helpers.SafeToNumber(maxValue, 0)
        end
        return tonumber(maxValue) or 0
    end

    local function MapPreviewMetric(value, minValue, maxValue, minPixels, maxPixels)
        value = tonumber(value) or minValue
        value = math_max(minValue, math_min(maxValue, value))

        if maxValue <= minValue or maxPixels <= minPixels then
            return minPixels
        end

        local pct = (value - minValue) / (maxValue - minValue)
        return math_floor(minPixels + ((maxPixels - minPixels) * pct) + 0.5)
    end

    local function GetPreviewTextConfig(cfg, isSecondary)
        if isSecondary then
            return GetSecondaryTextConfig(cfg)
        end
        return cfg
    end

    local function GetPreviewDisplaySize(cfg, pv, visibleCount)
        local orientation = cfg and cfg.orientation or "HORIZONTAL"
        local isVertical = orientation == "VERTICAL"
        local previewWidth = pv and pv.GetWidth and pv:GetWidth() or 280
        local maxHorizontalLength = math_max(PREVIEW_MIN_HORIZONTAL_LENGTH, previewWidth - (BAR_PAD_X * 2))
        local maxVerticalLength = visibleCount > 1 and 30 or 42
        local maxThickness = visibleCount > 1 and 18 or PREVIEW_MAX_THICKNESS

        local displayLength = MapPreviewMetric(cfg and cfg.width or 200, 50, 600,
            isVertical and PREVIEW_MIN_VERTICAL_LENGTH or PREVIEW_MIN_HORIZONTAL_LENGTH,
            isVertical and maxVerticalLength or maxHorizontalLength)
        local displayThickness = MapPreviewMetric(cfg and cfg.height or 8, 2, 40,
            PREVIEW_MIN_THICKNESS, maxThickness)

        if isVertical then
            return displayThickness, displayLength, true
        end

        return displayLength, displayThickness, false
    end

    local function GetPreviewBarColor(cfg, resource)
        local mode = cfg and cfg.colorMode or "power"
        if mode == "custom" and cfg and cfg.customColor then
            local c = cfg.customColor
            return (c[1] or c.r or 0.2), (c[2] or c.g or 0.5), (c[3] or c.b or 1.0)
        elseif mode == "class" then
            local _, class = UnitClass("player")
            local cc = RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
            if cc then return cc.r, cc.g, cc.b end
        end
        local col = resource and GetResourceColor(resource)
        if col then return col.r, col.g, col.b end
        return 0.2, 0.5, 1.0
    end

    local function ApplyPreviewTicks(section, cfg, resource)
        section.ticks = section.ticks or {}
        for _, t in ipairs(section.ticks) do t:Hide() end
        if not cfg or not cfg.showTicks then return end
        if type(resource) ~= "number" or not tickedPowerTypes[resource] then return end

        local max = GetPreviewPowerMax(resource)
        if max < 2 then return end

        local bar = section.bar
        local width, height = bar:GetWidth(), bar:GetHeight()
        if width <= 0 or height <= 0 then return end

        local thickness = math_max(1, cfg.tickThickness or 1)
        local tc = cfg.tickColor or { 0, 0, 0, 1 }
        local isVertical = (cfg and cfg.orientation) == "VERTICAL"

        for i = 1, max - 1 do
            local tick = section.ticks[i]
            if not tick then
                tick = bar:CreateTexture(nil, "OVERLAY")
                section.ticks[i] = tick
            end
            tick:SetColorTexture(tc[1], tc[2], tc[3], tc[4] or 1)
            tick:ClearAllPoints()
            if isVertical then
                local y = (i / max) * height
                tick:SetPoint("BOTTOM", bar, "BOTTOM", 0, y - (thickness / 2))
                tick:SetSize(width, thickness)
            else
                local x = (i / max) * width
                tick:SetPoint("LEFT", bar, "LEFT", x - (thickness / 2), 0)
                tick:SetSize(thickness, height)
            end
            tick:Show()
        end
    end

    local function GetPreviewBgColor(cfg)
        local bg = cfg and cfg.bgColor
        if bg then
            return (bg[1] or bg.r or 0), (bg[2] or bg.g or 0), (bg[3] or bg.b or 0), (bg[4] or bg.a or 0.4)
        end
        return 0, 0, 0, 0.4
    end

    local function MockValueText(cfg, textCfg, pct, resource)
        if type(resource) == "number" and fragmentedPowerTypes and fragmentedPowerTypes[resource] then
            if cfg and cfg.showFragmentedPowerBarText == false then
                return ""
            end
            local maxValue = GetPreviewPowerMax(resource)
            if maxValue <= 0 then
                maxValue = 5
            end
            local current = math_max(1, math_floor((pct * maxValue) + 0.5))
            return string_format("%d / %d", current, maxValue)
        end

        if not textCfg or not textCfg.showText then return "" end
        if textCfg.showPercent then
            local v = math.floor(pct * 100)
            return textCfg.hidePercentSymbol and tostring(v) or (v .. "%")
        end
        return math.floor(pct * 100000)  -- fake raw value
    end

    local function MakeMockBar(parent, fpath)
        local section = CreateFrame("Frame", nil, parent)

        local lbl = section:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        if fpath then lbl:SetFont(fpath, 9, "") end
        lbl:SetTextColor(1, 1, 1, 0.75)
        lbl:SetPoint("TOP", section, "TOP", 0, 0)
        section.lbl = lbl

        local barFrame = CreateFrame("Frame", nil, section)
        barFrame:SetPoint("TOP", lbl, "BOTTOM", 0, -PREVIEW_LABEL_GAP)
        section.barFrame = barFrame

        local bg = barFrame:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints(barFrame)
        bg:SetColorTexture(0, 0, 0, 0.4)
        section.bg = bg

        local bar = CreateFrame("StatusBar", nil, barFrame)
        bar:SetAllPoints(barFrame)
        bar:SetMinMaxValues(0, 1)
        bar:SetValue(0.7)
        section.bar = bar

        if UIKit and UIKit.CreateBorderLines then
            UIKit.CreateBorderLines(barFrame)
        end

        local val = barFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        if fpath then val:SetFont(fpath, 9, "") end
        val:SetTextColor(1, 1, 1, 0.9)
        val:SetPoint("CENTER", barFrame, "CENTER", 0, 0)
        section.val = val

        return section
    end

    local function ApplyPreviewSectionLayout(section, cfg, pv, visibleCount)
        local width, height, isVertical = GetPreviewDisplaySize(cfg, pv, visibleCount)
        section:SetSize(math_max(width, 80), 12 + PREVIEW_LABEL_GAP + height)

        section.barFrame:ClearAllPoints()
        section.barFrame:SetSize(width, height)
        section.barFrame:SetPoint("TOP", section.lbl, "BOTTOM", 0, -PREVIEW_LABEL_GAP)

        section.bar:SetOrientation(isVertical and "VERTICAL" or "HORIZONTAL")

        local borderSize = cfg and cfg.borderSize or 0
        if UIKit and UIKit.UpdateBorderLines then
            UIKit.UpdateBorderLines(section.barFrame, borderSize, 0, 0, 0, 1, borderSize <= 0)
        end
    end

    local previewRef = nil

    _G.QUI_BuildResourceBarPreview = function(pv)
        local GUI    = QUI and QUI.GUI
        local C      = (GUI and GUI.Colors) or {}
        local accent = C.accent or { 0.204, 0.827, 0.6, 1 }
        local border = C.border or { 1, 1, 1, 0.06 }
        local fpath  = ns.UIKit and ns.UIKit.ResolveFontPath
                       and ns.UIKit.ResolveFontPath(GUI and GUI:GetFontPath())

        local fill = pv:CreateTexture(nil, "BACKGROUND")
        fill:SetAllPoints(pv)
        fill:SetColorTexture(0, 0, 0, 0.2)

        if ns.UIKit and ns.UIKit.CreateBorderLines then
            ns.UIKit.CreateBorderLines(pv)
            ns.UIKit.UpdateBorderLines(pv, 1, border[1] or 1, border[2] or 1, border[3] or 1, 0.15, false)
        end

        local lbl = pv:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        if fpath then lbl:SetFont(fpath, 8, "") end
        lbl:SetTextColor(accent[1], accent[2], accent[3], 0.7)
        lbl:SetPoint("TOPLEFT", pv, "TOPLEFT", 8, -6)
        lbl:SetText(("PREVIEW"):gsub(".", "%0 "):sub(1, -2))

        local primary = MakeMockBar(pv, fpath)
        primary:SetPoint("TOPLEFT",  pv, "TOPLEFT",  BAR_PAD_X,  -20)
        primary:SetPoint("TOPRIGHT", pv, "TOPRIGHT", -BAR_PAD_X, -20)
        primary:SetSize(100, 24)

        local secondary = MakeMockBar(pv, fpath)
        secondary:Hide()

        previewRef = { pv = pv, primary = primary, secondary = secondary, fpath = fpath }

        pv:SetScript("OnSizeChanged", function()
            if _G.QUI_RefreshResourceBarPreview then
                _G.QUI_RefreshResourceBarPreview()
            end
        end)

        _G.QUI_RefreshResourceBarPreview()
    end

    _G.QUI_RefreshResourceBarPreview = function()
        if not previewRef then return end
        local p   = previewRef.primary
        local s   = previewRef.secondary
        local fp  = previewRef.fpath

        local core    = GetCore()
        local profile = core and core.db and core.db.profile
        if not profile then return end

        local pc  = profile.powerBar
        local sc  = profile.secondaryPowerBar

        local primaryResource   = GetPrimaryResource()
        local secondaryResource = GetSecondaryResource()
        local primaryTextCfg    = GetPreviewTextConfig(pc, false)
        local secondaryTextCfg  = GetPreviewTextConfig(sc, true)
        local showPrimary       = pc and pc.enabled ~= false
        local showSecondary     = sc and sc.enabled ~= false and secondaryResource ~= nil
        local swapBars          = showSecondary and ShouldSwapBars()

        if showPrimary and swapBars and ShouldHidePrimaryOnSwap() then
            showPrimary = false
        end

        local visibleCount = (showPrimary and 1 or 0) + (showSecondary and 1 or 0)
        if visibleCount == 0 then
            p:Hide()
            s:Hide()
            return
        end

        p:Hide()
        s:Hide()

        local orderedSections = {}
        if swapBars then
            if showSecondary then
                orderedSections[#orderedSections + 1] = { section = s, cfg = sc, textCfg = secondaryTextCfg, resource = secondaryResource, fill = MOCK_SECONDARY_FILL, label = POWER_DISPLAY_NAMES[secondaryResource] or "Secondary" }
            end
            if showPrimary then
                orderedSections[#orderedSections + 1] = { section = p, cfg = pc, textCfg = primaryTextCfg, resource = primaryResource, fill = MOCK_PRIMARY_FILL, label = POWER_DISPLAY_NAMES[primaryResource] or "Power" }
            end
        else
            if showPrimary then
                orderedSections[#orderedSections + 1] = { section = p, cfg = pc, textCfg = primaryTextCfg, resource = primaryResource, fill = MOCK_PRIMARY_FILL, label = POWER_DISPLAY_NAMES[primaryResource] or "Power" }
            end
            if showSecondary then
                orderedSections[#orderedSections + 1] = { section = s, cfg = sc, textCfg = secondaryTextCfg, resource = secondaryResource, fill = MOCK_SECONDARY_FILL, label = POWER_DISPLAY_NAMES[secondaryResource] or "Secondary" }
            end
        end

        local nextY = -20
        for _, info in ipairs(orderedSections) do
            local section = info.section
            local cfg = info.cfg
            local textCfg = info.textCfg
            local resource = info.resource

            section:Show()
            section:ClearAllPoints()
            ApplyPreviewSectionLayout(section, cfg, previewRef.pv, visibleCount)
            section:SetPoint("TOP", previewRef.pv, "TOP", 0, nextY)
            nextY = nextY - section:GetHeight() - PREVIEW_SECTION_GAP

            section.lbl:SetText(info.label)

            local r, g, b = GetPreviewBarColor(cfg, resource)
            local bgr, bgg, bgb, bga = GetPreviewBgColor(cfg)
            section.bg:SetColorTexture(bgr, bgg, bgb, bga)

            local tex = LSM and LSM:Fetch("statusbar", GetBarTexture(cfg))
            if tex then section.bar:SetStatusBarTexture(tex) end
            section.bar:SetStatusBarColor(r, g, b)
            section.bar:SetValue(info.fill)

            ApplyPreviewTicks(section, cfg, resource)

            local fontSize = textCfg and math.max(7, math.min(textCfg.textSize or 9, 13)) or 9
            if fp then section.val:SetFont(fp, fontSize, "") end
            section.val:SetText(MockValueText(cfg, textCfg, info.fill, resource))

            local align = textCfg and textCfg.textAlign or "CENTER"
            section.val:ClearAllPoints()
            if align == "LEFT" then
                section.val:SetPoint("LEFT", section.barFrame, "LEFT", 4, (textCfg and textCfg.textY or 0))
            elseif align == "RIGHT" then
                section.val:SetPoint("RIGHT", section.barFrame, "RIGHT", -4, (textCfg and textCfg.textY or 0))
            else
                section.val:SetPoint("CENTER", section.barFrame, "CENTER", (textCfg and textCfg.textX or 0), (textCfg and textCfg.textY or 0))
            end
        end
    end
end
