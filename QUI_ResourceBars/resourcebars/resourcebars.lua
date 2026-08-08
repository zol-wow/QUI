local ADDON_NAME, ns = ...
local QUICore = ns.Addon
local LSM = ns.LSM
local UIKit = ns.UIKit

local Helpers = ns.Helpers
local SkinBase = ns.SkinBase
local GetCore = Helpers.GetCore

local function CJKFont(fs, p, s, f)
    if ns.Helpers and ns.Helpers.ApplyFontWithFallback then
        ns.Helpers.ApplyFontWithFallback(fs, p, s, f)
    else
        fs:SetFont(p, s, f)
    end
end
local floor = math.floor

local function snapPx(value, px)
    if value == 0 then return 0 end
    return floor(value / px + 0.5) * px
end

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
local issecretvalue = issecretvalue
local table_insert = table.insert
local table_remove = table.remove
local string_format = string.format

if not _G["QUIPowerBar"] then
    CreateFrame("Frame", "QUIPowerBar", UIParent):Hide()
end
if not _G["QUISecondaryPowerBar"] then
    CreateFrame("Frame", "QUISecondaryPowerBar", UIParent):Hide()
end
if not _G["QUIResourceBars"] then
    local proxy = CreateFrame("Frame", "QUIResourceBars", UIParent)
    proxy:SetSize(1, 1)
    proxy:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    proxy:SetAlpha(1)
    if proxy.SetMouseClickEnabled then proxy:SetMouseClickEnabled(false) end
    if proxy.SetMouseMotionEnabled then proxy:SetMouseMotionEnabled(false) end
    proxy:Show()
end

local function GetCDMViewerFrame(...)
    local fn = _G.QUI_GetCDMViewerFrame
    if fn then return fn(...) end
    return nil
end

local function IsCDMVisibilityHidden()
    if Helpers.IsLayoutModeActive() then return false end
    if _G.QUI_ShouldCDMBeVisible then
        return not _G.QUI_ShouldCDMBeVisible()
    end
    return false
end

local function GetCDMHiddenAlpha()
    if Helpers.IsLayoutModeActive() then return nil end
    if _G.QUI_ShouldCDMBeVisible and not _G.QUI_ShouldCDMBeVisible() then
        local vis = QUICore and QUICore.db and QUICore.db.profile and QUICore.db.profile.cdmVisibility
        return (vis and vis.fadeOutAlpha) or 0
    end
    return nil
end

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

local function ShouldShowBar(cfg)
    if IsCDMVisibilityHidden() then return false end

    local vis = cfg.visibility or "always"
    if vis == "always" then return true end
    if vis == "combat" then return InCombatLockdown() end
    if vis == "hostile" then
        return UnitExists("target") and UnitCanAttack("player", "target")
    end
    return true
end

local function GetViewerState(viewer)
    if not viewer then return nil end
    if _G.QUI_GetCDMViewerState then
        return _G.QUI_GetCDMViewerState(viewer)
    end
    return nil
end

local function GetRawContentWidth(vs)
    if not vs then return nil end
    return vs.rawContentWidth or vs.iconWidth
end

local function GetRawRow1Width(vs)
    if not vs then return nil end
    return vs.rawRow1Width or vs.row1Width or vs.rawContentWidth or vs.iconWidth
end

local function GetRawBottomRowWidth(vs)
    if not vs then return nil end
    return vs.rawBottomRowWidth or vs.bottomRowWidth or vs.rawContentWidth or vs.iconWidth
end

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

local _primaryLockedReady = false
local _secondaryLockedReady = false

local function GetDefaultTexture()
    if QUICore and QUICore.db and QUICore.db.profile and QUICore.db.profile.general then
        return QUICore.db.profile.general.texture or "Quazii"
    end
    return "Quazii"
end

local function GetBarTexture(cfg)
    if cfg and cfg.texture then
        return cfg.texture
    end
    return "Solid"
end

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

local QUI_POWER = {
    MaelstromWeapon = 100,
    VengSoulFragments = 101,
    Whirlwind = 102,
    TipOfTheSpear = 103,
    RenewingMistCharges = 104,
}

local function IsSecretSpellcastPayload(spellID, castGUID)
    if not issecretvalue then return false end
    if issecretvalue(spellID) then return true end -- @secret-policy: report-secret-detected
    if issecretvalue(castGUID) then return true end -- @secret-policy: report-secret-detected
    return false
end

local _rbSeenGUID
local WhirlwindTracker = {}
do
    local IW_MAX_STACKS = 4
    local IW_DURATION   = 20
    local IMPROVED_WW_TALENT = 12950

    local GENERATORS = {
        [190411] = true,
        [6343]   = true,
        [435222] = true,
    }
    local CRASHING_THUNDER_TALENT = 436707

    local SPENDERS = {
        [23881]  = true,
        [85288]  = true,
        [280735] = true,
        [202168] = true,
        [184367] = true,
        [335096] = true,
        [335097] = true,
        [5308]   = true,
    }
    local UNHINGED_TALENT = 386628

    local stacks    = 0
    local expiresAt = nil
    local seenGUID  = {}
    local pendingToken = 0
    _rbSeenGUID = seenGUID

    function WhirlwindTracker:GetStacks()
        if expiresAt and GetTime() >= expiresAt then
            stacks = 0
            expiresAt = nil
        end
        if not C_SpellBook or not C_SpellBook.IsSpellKnown(IMPROVED_WW_TALENT) then
            return nil, 0
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

        if GENERATORS[spellID] then
            if (spellID == 6343 or spellID == 435222) then
                if not C_SpellBook.IsSpellKnown(CRASHING_THUNDER_TALENT) then
                    return
                end
            end
            pendingToken = pendingToken + 1
            local myToken = pendingToken
            C_Timer.After(0.15, function()
                if myToken ~= pendingToken then return end
                stacks = IW_MAX_STACKS
                expiresAt = GetTime() + IW_DURATION
                if QUICore and QUICore.UpdateSecondaryPowerBar then
                    QUICore:UpdateSecondaryPowerBar()
                end
            end)
            return
        end

        if SPENDERS[spellID] then
            if (spellID == 23881 or spellID == 335096) then
                if C_SpellBook.IsSpellKnown(UNHINGED_TALENT) then
                    local ok, usable = pcall(C_Spell.IsSpellUsable, 446035)
                    if ok and not usable then return end
                end
            end
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
            -- @secret-policy: collapse-only — secret class takes the unregister/Reset branch
            if issecretvalue and issecretvalue(class) then class = nil end
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
            local _, castGUID, spellID = ...
            if not IsSecretSpellcastPayload(spellID, castGUID) then
                WhirlwindTracker:OnSpellCast(spellID, castGUID)
            end
        elseif event == "PLAYER_DEAD" then
            WhirlwindTracker:Reset()
        elseif event == "PLAYER_REGEN_ENABLED" then
            pendingToken = pendingToken + 1
            wipe(seenGUID)
        end
    end)
    wwFrame:RegisterEvent("ACTIVE_PLAYER_SPECIALIZATION_CHANGED")
    wwFrame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
end

local function SetupDebugInstrumentation()
    local mp = ns._memprobes or {}; ns._memprobes = mp
    mp[#mp + 1] = { name = "RB_WW_seenGUID", tbl = _rbSeenGUID }
end
if ns.DebugRegister then
    ns.DebugRegister(SetupDebugInstrumentation)
else
    SetupDebugInstrumentation()
end

local TipOfTheSpearTracker = {}
do
    local TIP_MAX_STACKS = 3
    local TIP_DURATION   = 10
    local TIP_TALENT     = 260285

    local KILL_COMMAND    = 259489
    local TAKEDOWN        = 1250646
    local PRIMAL_SURGE    = 1272154
    local TWIN_FANG       = 1272139

    local SPENDERS = {
        [186270]  = true,
        [1262293] = true,
        [1261193] = true,
        [1253859] = true,
        [259495]  = true,
        [193265]  = true,
        [1264949] = true,
        [1262343] = true,
        [265189]  = true,
        [1251592] = true,
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

        if spellID == KILL_COMMAND then
            local gain = C_SpellBook.IsSpellKnown(PRIMAL_SURGE) and 2 or 1
            stacks = math_min(TIP_MAX_STACKS, stacks + gain)
            expiresAt = GetTime() + TIP_DURATION
            if QUICore and QUICore.UpdateSecondaryPowerBar then
                QUICore:UpdateSecondaryPowerBar()
            end
            return
        end

        if spellID == TAKEDOWN and C_SpellBook.IsSpellKnown(TWIN_FANG) then
            stacks = math_min(TIP_MAX_STACKS, stacks + 2)
            expiresAt = GetTime() + TIP_DURATION
            if QUICore and QUICore.UpdateSecondaryPowerBar then
                QUICore:UpdateSecondaryPowerBar()
            end
            return
        end

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
            -- @secret-policy: collapse-only — secret class takes the unregister/Reset branch
            if issecretvalue and issecretvalue(class) then class = nil end
            if class == "HUNTER" and spec == 3 then
                self:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
                self:RegisterEvent("PLAYER_DEAD")
            else
                self:UnregisterEvent("UNIT_SPELLCAST_SUCCEEDED")
                self:UnregisterEvent("PLAYER_DEAD")
                TipOfTheSpearTracker:Reset()
            end
        elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
            local _, _, spellID = ...
            if not IsSecretSpellcastPayload(spellID) then
                TipOfTheSpearTracker:OnSpellCast(spellID)
            end
        elseif event == "PLAYER_DEAD" then
            TipOfTheSpearTracker:Reset()
        end
    end)
    tipFrame:RegisterEvent("ACTIVE_PLAYER_SPECIALIZATION_CHANGED")
    tipFrame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
end

local MaelstromWeaponTracker = {}
do
    local MW_MAX_STACKS = 10
    local MAELSTROM_WEAPON_SPELL_ID = 344179

    local GENERATORS = {
        [17364]  = true,
        [115356] = true,
        [60103]  = true,
    }

    local SPENDERS = {
        [188196] = true,
        [188443] = true,
        [8004]   = true,
        [1064]   = true,
    }

    local stacks = 0

    function MaelstromWeaponTracker:GetStacks()
        return MW_MAX_STACKS, stacks
    end

    function MaelstromWeaponTracker:Reset()
        stacks = 0
    end

    function MaelstromWeaponTracker:Resync()
        if not (C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID) then return end
        if C_Secrets and C_Secrets.ShouldAurasBeSecret and C_Secrets.ShouldAurasBeSecret() then
            return
        end
        local ok, aura = pcall(C_UnitAuras.GetPlayerAuraBySpellID, MAELSTROM_WEAPON_SPELL_ID)
        if not ok then return end
        if aura and type(aura.applications) == "number" then -- @secret-safe: GetPlayerAuraBySpellID is RequiresNonSecretAura — it returns NO values for a secret aura instead of secret AuraData, so `aura` is plain table-or-nil
            stacks = math_min(MW_MAX_STACKS, aura.applications)
        else
            stacks = 0
        end
    end

    function MaelstromWeaponTracker:OnSpellCast(spellID)
        if GENERATORS[spellID] then
            if stacks < MW_MAX_STACKS then
                stacks = stacks + 1
                if QUICore and QUICore.UpdateSecondaryPowerBar then
                    QUICore:UpdateSecondaryPowerBar()
                end
            end
            return
        end

        if SPENDERS[spellID] then
            if stacks > 0 then
                stacks = 0
                if QUICore and QUICore.UpdateSecondaryPowerBar then
                    QUICore:UpdateSecondaryPowerBar()
                end
            end
            return
        end
    end

    local mwFrame = CreateFrame("Frame")
    mwFrame:RegisterEvent("ADDON_LOADED")
    mwFrame:SetScript("OnEvent", function(self, event, ...)
        if event == "ADDON_LOADED" then
            local addonName = ...
            if addonName ~= ADDON_NAME then return end
            self:UnregisterEvent("ADDON_LOADED")
        end
        if event == "ADDON_LOADED" or event == "ACTIVE_PLAYER_SPECIALIZATION_CHANGED"
            or event == "PLAYER_SPECIALIZATION_CHANGED" then
            local _, class = UnitClass("player")
            local spec = GetSpecialization()
            -- @secret-policy: collapse-only — secret class takes the unregister/Reset branch
            if issecretvalue and issecretvalue(class) then class = nil end
            if class == "SHAMAN" and spec == 2 then
                self:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
                self:RegisterEvent("PLAYER_DEAD")
                self:RegisterEvent("PLAYER_REGEN_ENABLED")
                MaelstromWeaponTracker:Resync()
            else
                self:UnregisterEvent("UNIT_SPELLCAST_SUCCEEDED")
                self:UnregisterEvent("PLAYER_DEAD")
                self:UnregisterEvent("PLAYER_REGEN_ENABLED")
                MaelstromWeaponTracker:Reset()
            end
        elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
            local _, _, spellID = ...
            if not IsSecretSpellcastPayload(spellID) then
                MaelstromWeaponTracker:OnSpellCast(spellID)
            end
        elseif event == "PLAYER_DEAD" then
            MaelstromWeaponTracker:Reset()
        elseif event == "PLAYER_REGEN_ENABLED" then
            MaelstromWeaponTracker:Resync()
        end
    end)
    mwFrame:RegisterEvent("ACTIVE_PLAYER_SPECIALIZATION_CHANGED")
    mwFrame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
end

local VDH_SOUL_FRAGMENTS_POWER = (Enum.PowerType and type(Enum.PowerType.SoulFragments) == "number") and Enum.PowerType.SoulFragments or nil

local RENEWING_MIST_SPELL_IDS = { 115151, 448430 }
local RENEWING_MIST_FALLBACK_RECHARGE = 9
local RUSHING_WIND_KICK_SPELL_IDS = {
    [107428] = true,
    [467307] = true,
    [1250554] = true,
    [1269159] = true,
}
local RUSHING_WIND_KICK_RENEWING_MIST_REDUCTION = 1

local RenewingMistChargeState = {
    max = nil,
    current = nil,
    startTime = 0,
    duration = RENEWING_MIST_FALLBACK_RECHARGE,
    chargeModRate = 1,
}

local SafeNumberOrNil = Helpers.SafeNumberOrNil

local function ReadPlayerPowerPair(resource, unmodified)
    local current = UnitPower("player", resource, unmodified)
    local max = UnitPowerMax("player", resource, unmodified)
    if Helpers.IsSecretValue(current) or Helpers.IsSecretValue(max) then
        return current, max, true -- @secret-policy: report-secret-detected
    end
    return current, max, false -- @secret-policy: report-secret-detected
end

local function GetSpellChargesCompat(spellID)
    if C_Spell and C_Spell.GetSpellCharges then
        local ok, a, b, c, d, e = pcall(C_Spell.GetSpellCharges, spellID)
        if not ok then
            return nil, nil, nil, nil, nil
        end
        if type(a) == "table" then
            return a.currentCharges,
                   a.maxCharges,
                   a.cooldownStartTime,
                   a.cooldownDuration,
                   a.chargeModRate
        end
        return a, b, c, d, e
    end

    if type(GetSpellCharges) == "function" then
        local ok, a, b, c, d, e = pcall(GetSpellCharges, spellID)
        if ok then
            return a, b, c, d, e
        end
    end

    return nil, nil, nil, nil, nil
end

local function GetRenewingMistCharges()
    for _, spellID in ipairs(RENEWING_MIST_SPELL_IDS) do
        local current, max, startTime, duration, chargeModRate = GetSpellChargesCompat(spellID)

        local safeMax = SafeNumberOrNil(max)
        local safeCurrent = SafeNumberOrNil(current)
        local safeStartTime = SafeNumberOrNil(startTime)
        local safeDuration = SafeNumberOrNil(duration)
        local safeChargeModRate = SafeNumberOrNil(chargeModRate)

        if safeMax and safeMax > 0 then
            RenewingMistChargeState.max = safeMax
        end
        if safeCurrent then
            RenewingMistChargeState.current = safeCurrent
        end
        if safeStartTime then
            RenewingMistChargeState.startTime = safeStartTime
        end
        if safeDuration and safeDuration > 0 then
            RenewingMistChargeState.duration = safeDuration
        end
        if safeChargeModRate and safeChargeModRate > 0 then
            RenewingMistChargeState.chargeModRate = safeChargeModRate
        end

        local cachedMax = RenewingMistChargeState.max
        if cachedMax and cachedMax > 0 then
            local cachedCurrent = RenewingMistChargeState.current
            if cachedCurrent == nil then
                cachedCurrent = cachedMax
                RenewingMistChargeState.current = cachedCurrent
            end
            return cachedMax,
                   math_min(cachedMax, math_max(0, cachedCurrent)),
                   RenewingMistChargeState.startTime or 0,
                   RenewingMistChargeState.duration or RENEWING_MIST_FALLBACK_RECHARGE,
                   RenewingMistChargeState.chargeModRate or 1
        end
    end
    return nil, 0, 0, 0, 1
end

local function NoteRenewingMistCast()
    local max, current, startTime, duration = GetRenewingMistCharges()
    if not max then
        max = RenewingMistChargeState.max or 2
        RenewingMistChargeState.max = max
    end

    current = current or RenewingMistChargeState.current or max
    local wasFull = current >= max
    local hadActiveRecharge = startTime and startTime > 0 and duration and duration > 0 and current < max

    RenewingMistChargeState.current = math_max(0, math_min(max, current - 1))

    if duration and duration > 0 then
        RenewingMistChargeState.duration = duration
    elseif not RenewingMistChargeState.duration or RenewingMistChargeState.duration <= 0 then
        RenewingMistChargeState.duration = RENEWING_MIST_FALLBACK_RECHARGE
    end

    if wasFull or not hadActiveRecharge then
        RenewingMistChargeState.startTime = GetTime()
    else
        RenewingMistChargeState.startTime = startTime
    end
end

local function AdvanceRenewingMistRecharge(seconds)
    seconds = tonumber(seconds) or 0
    if seconds <= 0 then return end

    local max, current, startTime, duration, chargeModRate = GetRenewingMistCharges()
    max = max or RenewingMistChargeState.max
    current = current or RenewingMistChargeState.current
    duration = duration and duration > 0 and duration or RenewingMistChargeState.duration or RENEWING_MIST_FALLBACK_RECHARGE
    chargeModRate = chargeModRate and chargeModRate > 0 and chargeModRate or RenewingMistChargeState.chargeModRate or 1
    if not max or not current or current >= max then return end

    local now = GetTime()
    local elapsed = 0
    if startTime and startTime > 0 then
        elapsed = math_max(0, (now - startTime) * chargeModRate)
    end
    elapsed = elapsed + seconds

    while current < max and elapsed >= duration do
        current = current + 1
        elapsed = elapsed - duration
    end

    RenewingMistChargeState.current = math_min(max, current)
    if RenewingMistChargeState.current >= max then
        RenewingMistChargeState.startTime = 0
    else
        RenewingMistChargeState.startTime = now - (elapsed / chargeModRate)
    end
end

local tocVersion = select(4, GetBuildInfo())
local HAS_UNIT_POWER_PERCENT = type(UnitPowerPercent) == "function"

local function GetPowerPct(unit, powerType, usePredicted)
    if (tonumber(tocVersion) or 0) >= 120000 and HAS_UNIT_POWER_PERCENT then
        local ok, pct
        if CurveConstants and CurveConstants.ScaleTo100 then
            ok, pct = pcall(UnitPowerPercent, unit, powerType, usePredicted, CurveConstants.ScaleTo100)
        end
        if Helpers.IsSecretValue(pct) then
            return pct -- @secret-policy: sink-passthrough
        end
        if not ok or pct == nil then
            ok, pct = pcall(UnitPowerPercent, unit, powerType, usePredicted)
        end
        if Helpers.IsSecretValue(pct) then
            return pct -- @secret-policy: sink-passthrough
        end
        if ok and pct ~= nil then
            return pct
        end
    end
    local ok, result = pcall(function()
        local cur = UnitPower(unit, powerType)
        local max = UnitPowerMax(unit, powerType)
        if Helpers.IsSecretValue(cur) or Helpers.IsSecretValue(max) then
            return nil -- @secret-policy: reject-secret-value
        end
        if cur and max and max > 0 then return (cur / max) * 100 end
    end)
    if not ok then return nil end
    return result
end

local tickedPowerTypes = {
    [Enum.PowerType.ArcaneCharges] = true,
    [Enum.PowerType.Chi] = true,
    [Enum.PowerType.ComboPoints] = true,
    [Enum.PowerType.Essence] = true,
    [Enum.PowerType.HolyPower] = true,
    [Enum.PowerType.Runes] = true,
    [Enum.PowerType.SoulShards] = true,
    [QUI_POWER.MaelstromWeapon] = true,
    [QUI_POWER.VengSoulFragments] = true,
    [QUI_POWER.Whirlwind] = true,
    [QUI_POWER.TipOfTheSpear] = true,
    [QUI_POWER.RenewingMistCharges] = true,
}
if VDH_SOUL_FRAGMENTS_POWER then
    tickedPowerTypes[VDH_SOUL_FRAGMENTS_POWER] = true
end

local fragmentedPowerTypes = {
    [Enum.PowerType.Runes] = true,
    [Enum.PowerType.Essence] = true,
}

local runeUpdateElapsed = 0
local runeUpdateRunning = false

local essenceUpdateElapsed = 0
local essenceUpdateRunning = false
local essenceNextTick = nil
local essenceLastCount = nil
local essenceTickDuration = nil

local renewingMistUpdateElapsed = 0
local renewingMistUpdateRunning = false

local _lastRuneRounded = {}
local _lastRuneFormatted = {}

local runeScratch = {}
local runeOrder = {}
local function RuneDisplayLess(a, b)
    if a.ready ~= b.ready then return a.ready end
    if a.ready then return a.index < b.index end
    if a.remaining ~= b.remaining then return a.remaining < b.remaining end
    return a.index < b.index
end

local UPDATE_THROTTLE = 0.016
local lastPrimaryUpdate = 0
local lastSecondaryUpdate = 0

local primaryDrainQueued = false
local secondaryDrainQueued = false
local primaryFullQueued = false
local secondaryFullQueued = false

local function DrainPrimaryPowerUpdate()
    primaryDrainQueued = false
    if not (QUICore and QUICore.db) then return end
    lastPrimaryUpdate = GetTime()
    if primaryFullQueued then
        primaryFullQueued = false
        QUICore:UpdatePowerBar()
    else
        QUICore:UpdatePowerBarValue()
    end
end

local function DrainSecondaryPowerUpdate()
    secondaryDrainQueued = false
    if not (QUICore and QUICore.db) then return end
    lastSecondaryUpdate = GetTime()
    if secondaryFullQueued then
        secondaryFullQueued = false
        QUICore:UpdateSecondaryPowerBar()
    else
        QUICore:UpdateSecondaryPowerBarValue()
    end
end

local function QueuePrimaryTrailingUpdate()
    if primaryDrainQueued then return end
    primaryDrainQueued = true
    C_Timer.After(UPDATE_THROTTLE, DrainPrimaryPowerUpdate)
end

local function QueueSecondaryTrailingUpdate()
    if secondaryDrainQueued then return end
    secondaryDrainQueued = true
    C_Timer.After(UPDATE_THROTTLE, DrainSecondaryPowerUpdate)
end

local instantFeedbackTypes = {
    [Enum.PowerType.HolyPower] = true,
    [Enum.PowerType.ComboPoints] = true,
    [Enum.PowerType.Chi] = true,
    [Enum.PowerType.ArcaneCharges] = true,
    [Enum.PowerType.Essence] = true,
    [Enum.PowerType.SoulShards] = true,
    [QUI_POWER.MaelstromWeapon] = true,
    [QUI_POWER.VengSoulFragments] = true,
    [QUI_POWER.Whirlwind] = true,
    [QUI_POWER.TipOfTheSpear] = true,
    [QUI_POWER.RenewingMistCharges] = true,
}
if VDH_SOUL_FRAGMENTS_POWER then
    instantFeedbackTypes[VDH_SOUL_FRAGMENTS_POWER] = true
end

local druidUtilityForms = {
    [0]  = true,
    [2]  = true,
    [3]  = true,
    [4]  = true,
    [27] = true,
    [29] = true,
    [36] = true,
}

local druidSpecResource = {
    [1] = Enum.PowerType.LunarPower,
    [2] = Enum.PowerType.Energy,
    [3] = Enum.PowerType.Rage,
    [4] = Enum.PowerType.Mana,
}

local SwapCandidateSpecByID = {
    [102] = true,
    [251] = true,
    [1467] = true,
    [1473] = true,
    [66] = true,
    [70] = true,
    [265] = true,
    [266] = true,
    [267] = true,
    [263] = true,
}

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

local function ViewerLayoutIsVertical(viewerKey)
    local viewer = GetCDMViewerFrame(viewerKey)
    local vs = viewer and GetViewerState(viewer)
    return (vs and vs.layoutDir) == "VERTICAL"
end

local function ResolveIsVertical(cfg, primaryCfg)
    local orientation = cfg.orientation or "AUTO"
    if orientation ~= "AUTO" then return orientation == "VERTICAL" end
    if cfg.lockedToEssential then
        return ViewerLayoutIsVertical("essential")
    elseif cfg.lockedToUtility then
        return ViewerLayoutIsVertical("utility")
    elseif cfg.lockedToPrimary and primaryCfg then
        if primaryCfg.lockedToEssential then
            return ViewerLayoutIsVertical("essential")
        elseif primaryCfg.lockedToUtility then
            return ViewerLayoutIsVertical("utility")
        end
    end
    return false
end

local function GetPrimaryEffectiveVertical()
    local cfg = QUICore and QUICore.db and QUICore.db.profile and QUICore.db.profile.powerBar
    if not cfg then return false end
    return ResolveIsVertical(cfg)
end

local function ResolveBarLength(width)
    if width and width > 0 then return width end
    local viewer = GetCDMViewerFrame("essential")
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

local function GetPrimaryOuterThickness()
    local cfg = QUICore and QUICore.db and QUICore.db.profile and QUICore.db.profile.powerBar
    if not cfg then return 8 end
    return (cfg.height or 8) + (2 * (cfg.borderSize or 1))
end

local function GetSecondaryOuterThickness()
    local cfg = QUICore and QUICore.db and QUICore.db.profile and QUICore.db.profile.secondaryPowerBar
    if not cfg then return 8 end
    return (cfg.height or 8) + (2 * (cfg.borderSize or 1))
end

local function ComputePrimaryNaturalSlot()
    local cfg = QUICore and QUICore.db and QUICore.db.profile and QUICore.db.profile.powerBar
    if not cfg then return 0, 0, 0, 0 end
    local cx = cfg.offsetX or 0
    local cy = cfg.offsetY or 0
    local thickness = GetPrimaryOuterThickness()
    local length = ResolveBarLength(cfg.width)
    return cx, cy, length, thickness
end

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
            return pcx + (pT / 2) + (thickness / 2) + userOffsetX,
                   pcy + userOffsetY,
                   plen,
                   thickness
        else
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

local function GetOrCreateResourceBarsProxy()
    if QUICore.resourceBars then return QUICore.resourceBars end
    local proxy = _G["QUIResourceBars"]
    if not proxy then
        proxy = CreateFrame("Frame", "QUIResourceBars", UIParent)
    end
    proxy:SetFrameStrata("BACKGROUND")
    proxy:SetSize(1, 1)
    proxy:SetAlpha(1)
    if proxy.SetMouseClickEnabled then proxy:SetMouseClickEnabled(false) end
    if proxy.SetMouseMotionEnabled then proxy:SetMouseMotionEnabled(false) end
    proxy:ClearAllPoints()
    proxy:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    proxy:Show()
    QUICore.resourceBars = proxy
    return proxy
end

local function IsBarVisuallyShown(bar)
    if not bar then return false end
    if not bar:IsShown() then return false end
    local alpha = bar:GetEffectiveAlpha()
    return type(alpha) == "number" and alpha > 0.01
end

local function GetLiveBarRect(bar)
    if not bar then return nil end
    local cx, cy = bar:GetCenter()
    if type(cx) ~= "number" or type(cy) ~= "number" then return nil end
    local w, h = bar:GetWidth(), bar:GetHeight()
    if type(w) ~= "number" or type(h) ~= "number" or w <= 1 or h <= 1 then
        return nil
    end
    local scx, scy = UIParent:GetCenter()
    if type(scx) ~= "number" or type(scy) ~= "number" then return nil end
    return cx - scx, cy - scy, w, h
end

local _capturedNaturalPrimary = nil
local _capturedNaturalSecondary = nil

local function CaptureLiveBarSlot(bar)
    local cx, cy, w, h = GetLiveBarRect(bar)
    if not cx then return nil end
    return { cx = cx, cy = cy, w = w, h = h }
end

local function CaptureNaturalSlotsIfPossible()
    if ShouldSwapBars() then return end
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
    C_Timer.After(0.6, function()
        _swapBootstrapPending = false
        if InCombatLockdown() then
            ScheduleSwapBootstrap()
            return
        end
        if not BothLockedBarsReady() then
            ScheduleSwapBootstrap()
            return
        end
        _swapBootstrapForcingNatural = true
        if QUICore and QUICore.UpdatePowerBar then QUICore:UpdatePowerBar() end
        if QUICore and QUICore.UpdateSecondaryPowerBar then QUICore:UpdateSecondaryPowerBar() end
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

local function RecaptureNaturalSlotsForSwap()
    if not ShouldSwapBars() then return end
    _swapBootstrapDone = false
    ScheduleSwapBootstrap()
end

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

local _swapOwnershipActive = false

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

    if transitioning then
        if _G.QUI_UpdateAnchoredUnitFrames then
            ns.SafeCall("bulkhead", _G.QUI_UpdateAnchoredUnitFrames)
        end
        if _G.QUI_UpdateAnchoredFrames then
            ns.SafeCall("bulkhead", _G.QUI_UpdateAnchoredFrames)
        end
        if _G.QUI_RefreshCDMBuffLayout then
            ns.SafeCall("bulkhead", _G.QUI_RefreshCDMBuffLayout)
        end
    end
end

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

function QUICore:GetSwapAwareBarFor(key)
    if not self then return nil end
    if key == "primaryPower" or key == "primary" then
        if not ShouldSwapBars() then return self.powerBar end
        return self.secondaryPowerBar
    elseif key == "secondaryPower" or key == "secondary" then
        if not ShouldSwapBars() then return self.secondaryPowerBar end
        if ShouldHidePrimaryOnSwap() then
            local proxy = self.GetResourceBarsProxy and self:GetResourceBarsProxy()
            if proxy then return proxy end
            return self.secondaryPowerBar
        end
        return self.powerBar
    end
    return nil
end

function QUICore:UpdateResourceBarsProxy()
    if InCombatLockdown() then return end
    local proxy = GetOrCreateResourceBarsProxy()

    local primaryCfg = self.db.profile.powerBar
    local secondaryCfg = self.db.profile.secondaryPowerBar

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

function QUICore:GetResourceBarsProxy()
    return GetOrCreateResourceBarsProxy()
end

local primaryResources = {
        ["DEATHKNIGHT"] = Enum.PowerType.RunicPower,
        ["DEMONHUNTER"] = Enum.PowerType.Fury,
        ["DRUID"]       = {
            [0]   = Enum.PowerType.Mana,
            [1]   = Enum.PowerType.Energy,
            [3]   = Enum.PowerType.Mana,
            [4]   = Enum.PowerType.Mana,
            [5]   = Enum.PowerType.Rage,
            [27]  = Enum.PowerType.Mana,
            [31]  = Enum.PowerType.LunarPower,
        },
        ["EVOKER"]      = Enum.PowerType.Mana,
        ["HUNTER"]      = Enum.PowerType.Focus,
        ["MAGE"]        = Enum.PowerType.Mana,
        ["MONK"]        = {
            [268] = Enum.PowerType.Energy,
            [269] = Enum.PowerType.Energy,
            [270] = Enum.PowerType.Mana,
        },
        ["PALADIN"]     = Enum.PowerType.Mana,
        ["PRIEST"]      = {
            [256] = Enum.PowerType.Mana,
            [257] = Enum.PowerType.Mana,
            [258] = Enum.PowerType.Insanity,
        },
        ["ROGUE"]       = Enum.PowerType.Energy,
        ["SHAMAN"]      = {
            [262] = Enum.PowerType.Maelstrom,
            [263] = Enum.PowerType.Mana,
            [264] = Enum.PowerType.Mana,
        },
        ["WARLOCK"]     = Enum.PowerType.Mana,
        ["WARRIOR"]     = Enum.PowerType.Rage,
}

local function GetPrimaryResource()
    local _, playerClass = UnitClass("player")
    -- @secret-policy: collapse-only — secret class renders the Mana default (matches
    if issecretvalue and issecretvalue(playerClass) then playerClass = nil end
    if not playerClass then return Enum.PowerType.Mana end
    local spec = GetSpecialization()
    if not spec then return Enum.PowerType.Mana end
    local specID = GetSpecializationInfo(spec)

    if playerClass == "DRUID" then
        local formID = GetShapeshiftFormID()
        if druidUtilityForms[formID or 0] then
            if spec and druidSpecResource[spec] then
                return druidSpecResource[spec]
            end
        end
        return primaryResources[playerClass][formID or 0]
    end

    if type(primaryResources[playerClass]) == "table" then
        return primaryResources[playerClass][specID]
    else
        return primaryResources[playerClass]
    end
end

local secondaryResources = {
        ["DEATHKNIGHT"] = Enum.PowerType.Runes,
        ["DEMONHUNTER"] = {
            [581] = VDH_SOUL_FRAGMENTS_POWER or QUI_POWER.VengSoulFragments,
            [1480] = "SOUL",
        },
        ["DRUID"]       = {
            [1]    = Enum.PowerType.ComboPoints,
            [31]   = Enum.PowerType.Mana,
        },
        ["EVOKER"]      = Enum.PowerType.Essence,
        ["HUNTER"]      = {
            [255] = QUI_POWER.TipOfTheSpear,
        },
        ["MAGE"]        = {
            [62]   = Enum.PowerType.ArcaneCharges,
        },
        ["MONK"]        = {
            [268]  = "STAGGER",
            [269]  = Enum.PowerType.Chi,
            [270]  = QUI_POWER.RenewingMistCharges,
        },
        ["PALADIN"]     = Enum.PowerType.HolyPower,
        ["PRIEST"]      = {
            [258]  = Enum.PowerType.Mana,
        },
        ["ROGUE"]       = Enum.PowerType.ComboPoints,
        ["SHAMAN"]      = {
            [262]  = Enum.PowerType.Mana,
            [263]  = QUI_POWER.MaelstromWeapon,
        },
        ["WARLOCK"]     = Enum.PowerType.SoulShards,
        ["WARRIOR"]     = {
            [72] = QUI_POWER.Whirlwind,
        },
}

local function GetSecondaryResource()
    local _, playerClass = UnitClass("player")
    -- @secret-policy: collapse-only — secret class shows no secondary bar (matches
    if issecretvalue and issecretvalue(playerClass) then playerClass = nil end
    if not playerClass then return nil end
    local spec = GetSpecialization()
    if not spec then return nil end
    local specID = GetSpecializationInfo(spec)

    if playerClass == "DRUID" then
        local formID = GetShapeshiftFormID()
        if druidUtilityForms[formID] or formID == nil then
            if spec and spec ~= 4 then
                return Enum.PowerType.Mana
            end
            return nil
        end
        return secondaryResources[playerClass][formID]
    end

    if type(secondaryResources[playerClass]) == "table" then
        return secondaryResources[playerClass][specID]
    else
        return secondaryResources[playerClass]
    end
end

local function GetResourceColor(resource)
    local core = GetCore()
    local pc = core and core.db and core.db.profile.powerColors

    if pc then
        local customColor = nil

        if resource == "STAGGER" then
            if pc.useStaggerLevelColors then
                local stagger = UnitStagger("player")
                local maxHealth = UnitHealthMax("player")
                if Helpers.IsSecretValue(stagger) or Helpers.IsSecretValue(maxHealth) then
                    -- @secret-policy: keep-visible-when-unknown — level
                    customColor = pc.stagger
                else
                    if stagger == nil then stagger = 0 end
                    if maxHealth == nil or maxHealth <= 0 then maxHealth = 1 end
                    local staggerPercent = (stagger / maxHealth) * 100

                    if staggerPercent >= 60 then
                        customColor = pc.staggerHeavy
                    elseif staggerPercent >= 30 then
                        customColor = pc.staggerModerate
                    else
                        customColor = pc.staggerLight
                    end
                end
            else
                customColor = pc.stagger
            end
        elseif resource == "SOUL" or resource == QUI_POWER.VengSoulFragments or (VDH_SOUL_FRAGMENTS_POWER and resource == VDH_SOUL_FRAGMENTS_POWER) then
            customColor = pc.soulFragments
        elseif resource == Enum.PowerType.SoulShards then
            customColor = pc.soulShards
        elseif resource == Enum.PowerType.Runes then
            local _, class = UnitClass("player")
            -- @secret-policy: collapse-only — secret class falls back to the base rune color
            if issecretvalue and issecretvalue(class) then class = nil end
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
        elseif resource == QUI_POWER.MaelstromWeapon then
            customColor = pc.maelstromWeapon or pc.maelstrom
        elseif resource == QUI_POWER.Whirlwind then
            customColor = pc.whirlwind
        elseif resource == QUI_POWER.TipOfTheSpear then
            customColor = pc.tipOfTheSpear
        elseif resource == QUI_POWER.RenewingMistCharges then
            customColor = pc.renewingMistCharges or pc.renewingMist or pc.chi or pc.mana
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

local function GetResourceBarColorMode(cfg)
    if not cfg then return "power" end
    local mode = cfg.colorMode
    if mode == "power" or mode == "class" or mode == "custom" then
        return mode
    end
    if cfg.usePowerColor then return "power" end
    if cfg.useClassColor then return "class" end
    if cfg.useCustomColor then return "custom" end
    return "power"
end

local function GetConfiguredResourceColor(cfg, resource)
    local mode = GetResourceBarColorMode(cfg)
    if mode == "custom" and cfg.customColor then
        local c = cfg.customColor
        return { r = c[1], g = c[2], b = c[3], a = c[4] or 1 }
    end
    if mode == "class" then
        local _, class = UnitClass("player")
        -- @secret-policy: collapse-only — secret class falls back to the power color
        if issecretvalue and issecretvalue(class) then class = nil end
        local classColor = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
        if classColor then
            return { r = classColor.r, g = classColor.g, b = classColor.b, a = classColor.a or 1 }
        end
    end
    return GetResourceColor(resource)
end

local cachedDHSoulBarParent = nil
local cachedDHSoulBarAlpha = nil

local function EnsureDemonHunterSoulBar()
    local soulBar = _G["DemonHunterSoulFragmentsBar"]
    if not soulBar then return nil end

    local isSoulResource = (GetSecondaryResource() == "SOUL")

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

    local current, max, secret = ReadPlayerPowerPair(resource)
    if secret then
        -- @secret-policy: sink-passthrough — the bar keeps rendering from the
        return max, current, current, "secret"
    end
    if max <= 0 then return nil, nil, nil, nil end

    if (cfg.showPercent or cfg.showManaAsPercent) and resource == Enum.PowerType.Mana then
        if HAS_UNIT_POWER_PERCENT then
            local pct = GetPowerPct("player", resource, false)
            if Helpers.IsSecretValue(pct) then
                -- @secret-policy: sink-passthrough — percent unreadable,
                return max, current, current, "secret"
            end
            return max, current, pct, "percent"
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
        local stagger = UnitStagger("player")
        local maxHealth = UnitHealthMax("player")
        if Helpers.IsSecretValue(stagger) or Helpers.IsSecretValue(maxHealth) then
            -- @secret-policy: sink-passthrough
            return maxHealth, stagger, nil, "secret"
        end
        if stagger == nil then stagger = 0 end
        if maxHealth == nil or maxHealth <= 0 then maxHealth = 1 end
        local staggerPercent = (stagger / maxHealth) * 100
        return 100, staggerPercent, staggerPercent, "percent"
    end

    if resource == "SOUL" then
        local soulBar = EnsureDemonHunterSoulBar() or _G["DemonHunterSoulFragmentsBar"]
        if soulBar and soulBar.GetValue and soulBar.GetMinMaxValues then
            local current = soulBar:GetValue()
            local _, max = soulBar:GetMinMaxValues()
            if Helpers.IsSecretValue(current) or Helpers.IsSecretValue(max) then
                -- @secret-policy: sink-passthrough
                return max, current, current, "secret"
            end
            if max and max > 0 then
                return max, current, current, "number"
            end
        end
    end

    if VDH_SOUL_FRAGMENTS_POWER and resource == VDH_SOUL_FRAGMENTS_POWER then
        local current, max, secret = ReadPlayerPowerPair(resource)
        if secret then
            -- @secret-policy: sink-passthrough
            return max, current, current, "secret"
        end
        if current == nil then current = 0 end
        if max ~= nil and max > 0 then
            return max, current, current, "number"
        end
    end

    if resource == QUI_POWER.VengSoulFragments then
        local current = SafeNumberOrNil(C_Spell.GetSpellCastCount(228477)) or 0
        local max = 6

        return max, current, current, "number"
    end

    if resource == QUI_POWER.MaelstromWeapon then
        local max, current = MaelstromWeaponTracker:GetStacks()
        return max, current, current, "number"
    end

    if resource == QUI_POWER.Whirlwind then
        local max, current = WhirlwindTracker:GetStacks()
        if not max then return nil, nil, nil, nil end
        return max, current, current, "number"
    end

    if resource == QUI_POWER.TipOfTheSpear then
        local max, current = TipOfTheSpearTracker:GetStacks()
        if not max then return nil, nil, nil, nil end
        return max, current, current, "number"
    end

    if resource == QUI_POWER.RenewingMistCharges then
        local max, current, startTime, duration, chargeModRate = GetRenewingMistCharges()
        if not max then return nil, nil, nil, nil end

        local fillValue = current
        if current < max and startTime and startTime > 0 and duration and duration > 0 then
            local elapsed = (GetTime() - startTime) * (chargeModRate or 1)
            local partial = math_max(0, math_min(1, elapsed / duration))
            fillValue = math_min(max, current + partial)
        end

        return max, fillValue, current, "number"
    end

    if resource == Enum.PowerType.Runes then
        local current = 0
        local max = UnitPowerMax("player", resource)
        if Helpers.IsSecretValue(max) then
            -- @secret-policy: defer-until-readable
            return nil, nil, nil, "defer"
        end
        if max <= 0 then return nil, nil, nil, nil end

        for i = 1, max do
            local runeReady = select(3, GetRuneCooldown(i))
            if Helpers.IsSecretValue(runeReady) then
                -- @secret-policy: defer-until-readable — readiness unknowable
                return nil, nil, nil, "defer"
            end
            if runeReady then
                current = current + 1
            end
        end

        return max, current, current, "number"
    end

    if resource == Enum.PowerType.SoulShards then
        local _, class = UnitClass("player")
        -- @secret-policy: collapse-only — secret class takes the generic shard path below
        if issecretvalue and issecretvalue(class) then class = nil end
        if class == "WARLOCK" then
            local spec = GetSpecialization()

            if spec == 3 then
                local fragments, maxFragments, fragSecret = ReadPlayerPowerPair(resource, true)
                if fragSecret then
                    -- @secret-policy: sink-passthrough — bar ratio renders
                    return maxFragments, fragments, fragments, "secret"
                end
                if maxFragments <= 0 then return nil, nil, nil, nil end

                return maxFragments, fragments, fragments / 10, "shards"
            end
        end

        local current, max, secret = ReadPlayerPowerPair(resource)
        if secret then
            -- @secret-policy: sink-passthrough
            return max, current, current, "secret"
        end
        if max <= 0 then return nil, nil, nil, nil end

        return max, current, current, "number"
    end

    local current, max, secret = ReadPlayerPowerPair(resource)
    if secret then
        -- @secret-policy: sink-passthrough
        return max, current, current, "secret"
    end
    if max <= 0 then return nil, nil, nil, nil end

    return max, current, current, "number"
end

local function GetCurrentSpecID()
    return Helpers.GetCurrentSpecID() or 0
end

local TEXT_SPEC_KEYS = {
    "showText", "showPercent", "hidePercentSymbol", "textAlign",
    "textSize", "textX", "textY", "textUseClassColor", "textCustomColor",
}

local function EnsureTextSpecOverrides(cfg, specID)
    if not cfg.textSpecOverrides then cfg.textSpecOverrides = {} end
    if not cfg.textSpecOverrides[specID] then
        local base = {}
        for _, k in ipairs(TEXT_SPEC_KEYS) do
            local v = cfg[k]
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

local function GetSecondaryTextConfig(cfg)
    if not cfg or not cfg.textPerSpec then return cfg end
    local specID = GetCurrentSpecID()
    if specID == 0 then return cfg end
    return EnsureTextSpecOverrides(cfg, specID)
end

ns.QUI_ResourceBars_Internal = {
    PseudoPowerTypes        = QUI_POWER,
    GetBarTexture           = GetBarTexture,
    tickedPowerTypes        = tickedPowerTypes,
    fragmentedPowerTypes    = fragmentedPowerTypes,
    ShouldSwapBars          = ShouldSwapBars,
    ShouldHidePrimaryOnSwap = ShouldHidePrimaryOnSwap,
    GetPrimaryResource      = GetPrimaryResource,
    GetSecondaryResource    = GetSecondaryResource,
    GetResourceColor        = GetResourceColor,
    GetResourceBarColorMode = GetResourceBarColorMode,
    GetSecondaryTextConfig  = GetSecondaryTextConfig,
    GetCurrentSpecID        = GetCurrentSpecID,
    EnsureTextSpecOverrides = EnsureTextSpecOverrides,
}

local function SanitizeIndicatorValues(values, maxValue)
    if type(values) ~= "table" or not maxValue or maxValue <= 0 then
        return {}
    end

    local dedupe = {}
    local sanitized = {}
    for _, rawValue in ipairs(values) do
        local value = tonumber(rawValue)
        if value and value > 0 and value < maxValue then
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
            QUICore:ApplyPixelSnapping(indicator)
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

function QUICore:GetPowerBar()
    if self.powerBar then return self.powerBar end

    local cfg = self.db.profile.powerBar

    local bar = CreateFrame("Frame", "QUIPowerBar", UIParent)
    bar:SetFrameStrata("MEDIUM")
    local layerPriority = self.db.profile.hudLayering and self.db.profile.hudLayering.primaryPowerBar or 7
    local frameLevel = self:GetHUDFrameLevel(layerPriority)
    bar:SetFrameLevel(frameLevel)
    bar:SetHeight(QUICore:PixelRound(cfg.height or 6, bar))
    QUICore:SetSnappedPoint(bar, "CENTER", UIParent, "CENTER", cfg.offsetX or 0, cfg.offsetY or 6)

    local width = cfg.width or 0
    if width <= 0 then
        local essentialViewer = GetCDMViewerFrame("essential")
        if essentialViewer then
            local evs = GetViewerState(essentialViewer)
            width = GetRawContentWidth(evs) or 0
        end
        if width <= 0 then
            width = QUICore.db and QUICore.db.profile and QUICore.db.profile.ncdm
                and QUICore.db.profile.ncdm._lastEssentialWidth or 0
        end
        if width <= 0 then
            width = 200
        end
    end

    bar:SetWidth(QUICore:PixelRound(width, bar))

    local bgColor = cfg.bgColor or { 0.15, 0.15, 0.15, 1 }
    bar.Background = UIKit.CreateBackground(bar, bgColor[1], bgColor[2], bgColor[3], bgColor[4] or 1)

    bar.StatusBar = CreateFrame("StatusBar", nil, bar)
    bar.StatusBar:SetAllPoints()
    local tex = LSM:Fetch("statusbar", GetBarTexture(cfg))
    bar.StatusBar:SetStatusBarTexture(tex)
    bar.StatusBar:SetFrameLevel(bar:GetFrameLevel())

    local sbR, sbG, sbB, sbA = Helpers.GetSkinBorderColor(cfg, "")
    UIKit.CreateBackdropBorder(bar, cfg.borderSize or 1, sbR, sbG, sbB, sbA)

    bar.TextFrame = CreateFrame("Frame", nil, bar)
    bar.TextFrame:SetAllPoints(bar)
    bar.TextFrame:SetFrameStrata("MEDIUM")
    bar.TextFrame:SetFrameLevel(frameLevel + 2)

    bar.TextValue = bar.TextFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    ApplyPowerBarTextPlacement(bar, cfg)
    CJKFont(bar.TextValue, GetGeneralFont(), QUICore:PixelRound(cfg.textSize or 12, bar.TextValue), GetGeneralFontOutline())
    bar.TextValue:SetShadowOffset(0, 0)
    bar.TextValue:SetText("0")

    bar.ticks = {}
    bar.indicatorLines = {}

    bar:Hide()

    self.powerBar = bar
    return bar
end

local function LayoutSegmentDividers(bar, anchor, count, tickPx, tickThickness, tc, isVertical, offsetOf, crossSize)
    for i = 1, count do
        local tick = bar.ticks[i]
        if not tick then
            tick = bar:CreateTexture(nil, "OVERLAY")
            bar.ticks[i] = tick
        end
        tick:SetColorTexture(tc[1], tc[2], tc[3], tc[4] or 1)
        tick:ClearAllPoints()

        if isVertical then
            tick:SetPoint("BOTTOM", anchor, "BOTTOM", 0, snapPx(offsetOf(i) - (tickThickness / 2), tickPx))
            tick:SetSize(crossSize, tickThickness)
        else
            tick:SetPoint("LEFT", anchor, "LEFT", snapPx(offsetOf(i) - (tickThickness / 2), tickPx), 0)
            tick:SetSize(tickThickness, crossSize)
        end
        tick:Show()
    end

    for i = count + 1, #bar.ticks do
        if bar.ticks[i] then
            bar.ticks[i]:Hide()
        end
    end
end

function QUICore:UpdatePowerBarValue(forceShown)
    local db = self.db and self.db.profile
    local cfg = db and db.powerBar
    local bar = self.powerBar
    if not cfg or not cfg.enabled or not bar then return nil end
    if not forceShown and not bar:IsShown() then return nil end
    if (cfg.lockedToEssential or cfg.lockedToUtility) and not _primaryLockedReady then return nil end
    if ShouldHidePrimaryOnSwap() and not IsForcingNaturalDuringBootstrap() then return nil end
    local resource = GetPrimaryResource()
    if not resource then return nil end
    if GetCDMHiddenAlpha() ~= nil then return nil end
    if not ShouldShowBar(cfg) then return nil end

    local color = GetConfiguredResourceColor(cfg, resource)
    bar.StatusBar:SetStatusBarColor(color.r, color.g, color.b, color.a or 1)

    local max, current, displayValue, valueType = GetPrimaryResourceValue(resource, cfg)
    if valueType == "secret" then
        -- @secret-policy: keep-visible-when-unknown + sink-passthrough — the
        bar.StatusBar:SetMinMaxValues(0, max)
        bar.StatusBar:SetValue(current)
        bar.TextValue:SetFormattedText("%d", displayValue)
        bar:SetAlpha(1)
        SafeShow(bar)
        return "secret", nil, resource
    end
    if not max then
        SafeHide(bar)
        return nil
    end

    bar.StatusBar:SetMinMaxValues(0, max)
    bar.StatusBar:SetValue(current)

    if valueType == "percent" then
        bar.TextValue:SetText(FormatPercentValue(displayValue, cfg))
    else
        bar.TextValue:SetText(tostring(displayValue))
    end

    bar:SetAlpha(1)
    SafeShow(bar)
    return valueType, max, resource
end

function QUICore:UpdatePowerBar()
    local cfg = self.db.profile.powerBar

    local bar = self:GetPowerBar()

    if not cfg.enabled then
        SafeHide(bar)
        return
    end

    if (cfg.lockedToEssential or cfg.lockedToUtility) and not _primaryLockedReady then
        if self.powerBar then SafeHide(self.powerBar) end
        return
    end

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
        TriggerSwapReciprocalUpdate()
        return
    end

    local resource = GetPrimaryResource()

    if not resource then
        SafeHide(bar)
        return
    end

    do
        local cdmHiddenAlpha = GetCDMHiddenAlpha()
        if cdmHiddenAlpha ~= nil then
            bar:SetAlpha(cdmHiddenAlpha)
            SafeShow(bar)
            return
        end
    end

    local visibilityHidden = not ShouldShowBar(cfg)
    if visibilityHidden then
        bar:SetAlpha(0)
        SafeShow(bar)
        return
    end

    local layerPriority = self.db.profile.hudLayering and self.db.profile.hudLayering.primaryPowerBar or 7
    local frameLevel = self:GetHUDFrameLevel(layerPriority)
    SafeSetFrameLevel(bar, frameLevel)
    if bar.TextFrame then
        SafeSetFrameLevel(bar.TextFrame, frameLevel + 2)
    end

    local isVertical = ResolveIsVertical(cfg)

    bar.StatusBar:SetOrientation(isVertical and "VERTICAL" or "HORIZONTAL")

    local width = cfg.width
    if not width or width <= 0 then
        local essentialViewer = GetCDMViewerFrame("essential")
        if essentialViewer then
            local evs = GetViewerState(essentialViewer)
            width = GetRawContentWidth(evs)
        end
        if width and width > 0 then
            if not Helpers.IsEditModeActive() and self.db.profile.ncdm then
                self.db.profile.ncdm._lastEssentialWidth = width
            end
        else
            width = self.db.profile.ncdm and self.db.profile.ncdm._lastEssentialWidth
        end
        if not width or width <= 0 then
            width = 200
        end
    end

    local offsetX, offsetY
    local isSwapped = ShouldSwapBars()
    if isSwapped and IsForcingNaturalDuringBootstrap() then
        isSwapped = false
    end
    SyncSwapAnchorOwnership(isSwapped)
    if isSwapped then
        local pcx, pcy, _, pT = GetPrimaryNaturalSlotForSwap()
        local scx, scy, _, sT = GetSecondaryNaturalSlotForSwap()
        local primaryNewCx, primaryNewCy = ComputeSwappedCenters(pcx, pcy, pT, scx, scy, sT, isVertical)
        offsetX = QUICore:PixelRound(primaryNewCx, bar)
        offsetY = QUICore:PixelRound(primaryNewCy, bar)
    else
        offsetX = QUICore:PixelRound(cfg.offsetX or 0, bar)
        offsetY = QUICore:PixelRound(cfg.offsetY or 0, bar)
    end

    if not InCombatLockdown() then
        local swapMode = isSwapped and "swappedToSecondary" or nil
        local positionAllowed = isSwapped or not (_G.QUI_HasFrameAnchor and _G.QUI_HasFrameAnchor("primaryPower"))
        if positionAllowed and (bar._cachedX ~= offsetX or bar._cachedY ~= offsetY or bar._cachedAutoMode ~= swapMode) then
            bar:ClearAllPoints()
            bar:SetPoint("CENTER", UIParent, "CENTER", offsetX, offsetY)
            bar._cachedX = offsetX
            bar._cachedY = offsetY
            bar._cachedAutoMode = swapMode
            if _G.QUI_UpdateAnchoredUnitFrames then
                _G.QUI_UpdateAnchoredUnitFrames()
            end
        end

        local wantedH, wantedW
        if isVertical then
            wantedW = QUICore:PixelRound(cfg.height or 6, bar)
            wantedH = QUICore:PixelRound(width, bar)
        else
            wantedH = QUICore:PixelRound(cfg.height or 6, bar)
            wantedW = QUICore:PixelRound(width, bar)
        end

        if bar._cachedH ~= wantedH then
            bar:SetHeight(wantedH)
            bar._cachedH = wantedH
        end
        if bar._cachedW ~= wantedW then
            bar:SetWidth(wantedW)
            bar._cachedW = wantedW
        end

        local borderSizePixels = cfg.borderSize or 1
        local sbR, sbG, sbB, sbA = Helpers.GetSkinBorderColor(cfg, "")
        if bar._cachedBorderSize ~= borderSizePixels then
            if UIKit and UIKit.CreateBackdropBorder then
                bar.Border = UIKit.CreateBackdropBorder(bar, borderSizePixels, sbR, sbG, sbB, sbA)
                if bar.Border then
                    bar.Border:SetShown(borderSizePixels > 0)
                end
            end
            bar._cachedBorderSize = borderSizePixels
        elseif bar.Border and bar.Border.SetBackdropBorderColor then
            bar.Border:SetBackdropBorderColor(sbR, sbG, sbB, sbA)
        end
    end

    local bgColor = cfg.bgColor or { 0.15, 0.15, 0.15, 1 }
    if bar.Background then
        bar.Background:SetColorTexture(bgColor[1], bgColor[2], bgColor[3], bgColor[4] or 1)
    end

    local tex = LSM:Fetch("statusbar", GetBarTexture(cfg))
    if bar._cachedTex ~= tex then
        bar.StatusBar:SetStatusBarTexture(tex)
        bar._cachedTex = tex
    end

    local vType, vMax, vResource = self:UpdatePowerBarValue(true)
    if not vType then
        return
    end

    if vType ~= "secret" then
        CJKFont(bar.TextValue, GetGeneralFont(), QUICore:PixelRound(cfg.textSize or 12, bar.TextValue), GetGeneralFontOutline())
        bar.TextValue:SetShadowOffset(0, 0)

        if cfg.textUseClassColor then
            local _, class = UnitClass("player")
            -- @secret-policy: collapse-only — secret class keeps the current text color
            if issecretvalue and issecretvalue(class) then class = nil end
            local classColor = class and RAID_CLASS_COLORS[class]
            if classColor then
                bar.TextValue:SetTextColor(classColor.r, classColor.g, classColor.b, 1)
            end
        else
            local c = cfg.textCustomColor or { 1, 1, 1, 1 }
            bar.TextValue:SetTextColor(c[1], c[2], c[3], c[4] or 1)
        end

        ApplyPowerBarTextPlacement(bar, cfg)

        bar.TextFrame:SetShown(cfg.showText ~= false)

        self:UpdatePowerBarTicks(bar, vResource, vMax)
        self:UpdatePowerBarIndicators(bar, vMax, isVertical)
    end

    local secondaryCfg = self.db.profile.secondaryPowerBar
    local propagated = false
    if secondaryCfg and secondaryCfg.lockedToPrimary then
        self:UpdateSecondaryPowerBar()
        propagated = true
    end

    if self.UpdateResourceBarsProxy then self:UpdateResourceBarsProxy() end
    ScheduleNaturalSlotCapture()
    TriggerSwapReciprocalUpdate()
    return propagated
end

function QUICore:UpdatePowerBarTicks(bar, resource, max)
    local cfg = self.db.profile.powerBar

    for _, tick in ipairs(bar.ticks) do
        tick:Hide()
    end

    if not cfg.showTicks or not tickedPowerTypes[resource] then
        return
    end

    local width = bar:GetWidth()
    local height = bar:GetHeight()
    if width <= 0 or height <= 0 then return end

    local isVertical = ResolveIsVertical(cfg)

    local tickPx = QUICore:GetPixelSize(bar)
    LayoutSegmentDividers(bar, bar.StatusBar, max - 1, tickPx,
        (cfg.tickThickness or 1) * tickPx,
        cfg.tickColor or { 0, 0, 0, 1 },
        isVertical,
        isVertical and function(i) return (i / max) * height end
            or function(i) return (i / max) * width end,
        isVertical and width or height)
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

local LOCKED_BAR_VARIANTS = {
    primaryEssential = {
        cfgKey = "powerBar", lockKey = "lockedToEssential", viewerKey = "essential",
        defaultThickness = 6, safe = true, side = 1, computeY = false,
        vEdgeKey = "bottomRowBorderSize", vPadBorder = true, vFudgeX = -4,
        rowWidth = GetRawRow1Width, rowBorderKey = "row1BorderSize",
        writeX = "offsetX", writeY = "offsetY",
    },
    primaryUtility = {
        cfgKey = "powerBar", lockKey = "lockedToUtility", viewerKey = "utility",
        defaultThickness = 6, side = -1, computeY = false,
        vEdgeKey = "row1BorderSize", vPadBorder = true, vFudgeX = 1,
        rowWidth = GetRawBottomRowWidth, rowBorderKey = "bottomRowBorderSize",
        writeX = "offsetX", writeY = "offsetY",
    },
    secondaryEssential = {
        cfgKey = "secondaryPowerBar", lockKey = "lockedToEssential", viewerKey = "essential",
        defaultThickness = 8, side = 1, computeY = true,
        vEdgeKey = "bottomRowBorderSize", vPadBorder = true, vFudgeX = -4, hFudgeY = -1,
        rowWidth = GetRawRow1Width, rowBorderKey = "row1BorderSize",
        writeX = "lockedBaseX", writeY = "lockedBaseY",
    },
    secondaryUtility = {
        cfgKey = "secondaryPowerBar", lockKey = "lockedToUtility", viewerKey = "utility",
        defaultThickness = 8, side = -1, computeY = true,
        vPadBorder = false, vFudgeX = 0, hFudgeY = 1,
        rowWidth = GetRawBottomRowWidth, rowBorderKey = "bottomRowBorderSize",
        writeX = "lockedBaseX", writeY = "lockedBaseY",
    },
}

local function ComputeLockedBarGeometry(v)
    local core = GetCore()
    if not core or not core.db then return end

    local cfg = core.db.profile[v.cfgKey]
    if not cfg.enabled or not cfg[v.lockKey] then return end

    local viewer = GetCDMViewerFrame(v.viewerKey)
    if not viewer or not viewer:IsShown() then return end

    local vs = GetViewerState(viewer)
    local isVerticalCDM = (vs and vs.layoutDir) == "VERTICAL"

    local newWidth, newOffsetX, newOffsetY
    local barBorderSize = cfg.borderSize or 1
    local barThickness = cfg.height or v.defaultThickness

    local savedW, savedH = GetSavedViewerDims(v.viewerKey)

    if isVerticalCDM then
        local totalHeight = (vs and vs.totalHeight) or savedH
        if not totalHeight or totalHeight <= 0 then return end

        local row1BorderSize = (vs and vs.row1BorderSize) or 0
        local targetWidth = totalHeight + (2 * row1BorderSize) - (2 * barBorderSize)
        newWidth = math_floor(targetWidth + 0.5)

        local centerX, centerY = viewer:GetCenter()
        local screenCenterX, screenCenterY = UIParent:GetCenter()
        if v.safe then
            centerX = Helpers.SafeValue(centerX, nil)
            centerY = Helpers.SafeValue(centerY, nil)
            screenCenterX = Helpers.SafeValue(screenCenterX, nil)
            screenCenterY = Helpers.SafeValue(screenCenterY, nil)
        end
        local totalWidth = (vs and vs.iconWidth) or savedW
        if totalWidth <= 0 then return end

        if centerX and centerY and screenCenterX and screenCenterY then
            local edgeBorderSize = (v.vEdgeKey and vs and vs[v.vEdgeKey]) or 0
            local edgePad = v.vPadBorder and barBorderSize or 0
            local powerBarCenterX
            if v.side > 0 then
                powerBarCenterX = centerX + (totalWidth / 2) + edgeBorderSize + (barThickness / 2) + edgePad
            else
                powerBarCenterX = centerX - (totalWidth / 2) - edgeBorderSize - (barThickness / 2) - edgePad
            end

            newOffsetX = math_floor(powerBarCenterX - screenCenterX + 0.5) + v.vFudgeX
            newOffsetY = math_floor(centerY - screenCenterY + 0.5)
        end
    else
        local rowWidth = v.rowWidth(vs) or savedW
        if not rowWidth or rowWidth <= 0 then return end

        local rowBorderSize = (vs and vs[v.rowBorderKey]) or 0
        local targetWidth = rowWidth + (2 * rowBorderSize) - (2 * barBorderSize)
        newWidth = math_floor(targetWidth + 0.5)

        if v.computeY then
            local rawCenterX, rawCenterY = viewer:GetCenter()
            local rawScreenX, rawScreenY = UIParent:GetCenter()

            if rawCenterX and rawCenterY and rawScreenX and rawScreenY then
                local viewerCenterX = math_floor(rawCenterX + 0.5)
                local viewerCenterY = math_floor(rawCenterY + 0.5)
                local screenCenterX = math_floor(rawScreenX + 0.5)
                local screenCenterY = math_floor(rawScreenY + 0.5)
                newOffsetX = viewerCenterX - screenCenterX
                local totalHeight = (vs and vs.totalHeight) or savedH
                if totalHeight > 0 then
                    local powerBarCenterY
                    if v.side > 0 then
                        powerBarCenterY = viewerCenterY + (totalHeight / 2) + rowBorderSize + (barThickness / 2) + barBorderSize
                    else
                        powerBarCenterY = viewerCenterY - (totalHeight / 2) - rowBorderSize - (barThickness / 2) - barBorderSize
                    end
                    newOffsetY = math_floor(powerBarCenterY - screenCenterY + 0.5) + v.hFudgeY
                end
            end
        else
            local rawCenterX = viewer:GetCenter()
            local rawScreenX = UIParent:GetCenter()
            if v.safe then
                rawCenterX = Helpers.SafeValue(rawCenterX, nil)
                rawScreenX = Helpers.SafeValue(rawScreenX, nil)
            end
            if rawCenterX and rawScreenX then
                newOffsetX = math_floor(rawCenterX + 0.5) - math_floor(rawScreenX + 0.5)
            end
        end
    end

    local needsUpdate = false
    if newWidth and cfg.width ~= newWidth then
        cfg.width = newWidth
        needsUpdate = true
    end
    if newOffsetX and cfg[v.writeX] ~= newOffsetX then
        cfg[v.writeX] = newOffsetX
        needsUpdate = true
    end
    if newOffsetY and cfg[v.writeY] ~= newOffsetY then
        cfg[v.writeY] = newOffsetY
        needsUpdate = true
    end
    return needsUpdate
end

_G.QUI_UpdateLockedPowerBar = function()
    if InCombatLockdown() then return end
    if _G.QUI_IsCDMEditModeActive and _G.QUI_IsCDMEditModeActive() then return end

    local needsUpdate = ComputeLockedBarGeometry(LOCKED_BAR_VARIANTS.primaryEssential)
    if needsUpdate == nil then return end

    if not _primaryLockedReady then
        _primaryLockedReady = true
        needsUpdate = true
    end

    if needsUpdate then
        GetCore():UpdatePowerBar()
    end
end

_G.QUI_UpdateLockedPowerBarToUtility = function()
    if InCombatLockdown() then return end
    if _G.QUI_IsCDMEditModeActive and _G.QUI_IsCDMEditModeActive() then return end

    local needsUpdate = ComputeLockedBarGeometry(LOCKED_BAR_VARIANTS.primaryUtility)
    if needsUpdate == nil then return end

    if not _primaryLockedReady then
        _primaryLockedReady = true
        needsUpdate = true
    end

    if needsUpdate then
        GetCore():UpdatePowerBar()
    end
end

local cachedPrimaryDimensions = {
    centerX = nil,
    centerY = nil,
    width = nil,
    height = nil,
    borderSize = nil,
}

_G.QUI_UpdateLockedSecondaryPowerBar = function()
    if InCombatLockdown() then return end
    if _G.QUI_IsCDMEditModeActive and _G.QUI_IsCDMEditModeActive() then return end

    local needsUpdate = ComputeLockedBarGeometry(LOCKED_BAR_VARIANTS.secondaryEssential)
    if needsUpdate == nil then return end

    if not _secondaryLockedReady then
        _secondaryLockedReady = true
        needsUpdate = true
    end

    if needsUpdate then
        GetCore():UpdateSecondaryPowerBar()
    end
end

_G.QUI_UpdateLockedSecondaryPowerBarToUtility = function()
    if InCombatLockdown() then return end
    if _G.QUI_IsCDMEditModeActive and _G.QUI_IsCDMEditModeActive() then return end

    local needsUpdate = ComputeLockedBarGeometry(LOCKED_BAR_VARIANTS.secondaryUtility)
    if needsUpdate == nil then return end

    if not _secondaryLockedReady then
        _secondaryLockedReady = true
        needsUpdate = true
    end

    if needsUpdate then
        QUICore:UpdateSecondaryPowerBar()
    end
end

function QUICore:GetSecondaryPowerBar()
    if self.secondaryPowerBar then return self.secondaryPowerBar end

    local cfg = self.db.profile.secondaryPowerBar

    local bar = CreateFrame("Frame", "QUISecondaryPowerBar", UIParent)
    bar:SetFrameStrata("MEDIUM")
    local layerPriority = self.db.profile.hudLayering and self.db.profile.hudLayering.secondaryPowerBar or 6
    local frameLevel = self:GetHUDFrameLevel(layerPriority)
    bar:SetFrameLevel(frameLevel)
    bar:SetHeight(QUICore:PixelRound(cfg.height or 4, bar))
    QUICore:SetSnappedPoint(bar, "CENTER", UIParent, "CENTER", cfg.offsetX or 0, cfg.offsetY or 12)

    local width = cfg.width or 0
    if width <= 0 then
        local essentialViewer = GetCDMViewerFrame("essential")
        if essentialViewer then
            local evs = GetViewerState(essentialViewer)
            width = GetRawContentWidth(evs) or 0
        end
        if width <= 0 then
            width = QUICore.db and QUICore.db.profile and QUICore.db.profile.ncdm
                and QUICore.db.profile.ncdm._lastEssentialWidth or 0
        end
        if width <= 0 then
            width = 200
        end
    end

    bar:SetWidth(QUICore:PixelRound(width, bar))

    local bgColor = cfg.bgColor or { 0.15, 0.15, 0.15, 1 }
    bar.Background = UIKit.CreateBackground(bar, bgColor[1], bgColor[2], bgColor[3], bgColor[4] or 1)

    bar.StatusBar = CreateFrame("StatusBar", nil, bar)
    bar.StatusBar:SetAllPoints()
    local tex = LSM:Fetch("statusbar", GetBarTexture(cfg))
    bar.StatusBar:SetStatusBarTexture(tex)
    bar.StatusBar:SetFrameLevel(bar:GetFrameLevel())

    local sbR, sbG, sbB, sbA = Helpers.GetSkinBorderColor(cfg, "")
    UIKit.CreateBackdropBorder(bar, cfg.borderSize or 1, sbR, sbG, sbB, sbA)

    bar.TextFrame = CreateFrame("Frame", nil, bar)
    bar.TextFrame:SetAllPoints(bar)
    bar.TextFrame:SetFrameStrata("MEDIUM")
    bar.TextFrame:SetFrameLevel(frameLevel + 2)

    bar.TextValue = bar.TextFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    ApplyPowerBarTextPlacement(bar, cfg)
    CJKFont(bar.TextValue, GetGeneralFont(), QUICore:PixelRound(cfg.textSize or 12, bar.TextValue), GetGeneralFontOutline())
    bar.TextValue:SetShadowOffset(0, 0)
    bar.TextValue:SetText("0")

    bar.SoulShardDecimal = bar.TextFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    CJKFont(bar.SoulShardDecimal, GetGeneralFont(), QUICore:PixelRound(cfg.textSize or 12, bar.SoulShardDecimal), GetGeneralFontOutline())
    bar.SoulShardDecimal:SetShadowOffset(0, 0)
    bar.SoulShardDecimal:SetText(".")
    bar.SoulShardDecimal:Hide()

    bar.FragmentedPowerBars = {}
    bar.FragmentedPowerBarTexts = {}

    bar.chargedOverlays = {}

    bar.ticks = {}
    bar.indicatorLines = {}

    bar:Hide()

    self.secondaryPowerBar = bar
    return bar
end

function QUICore:CreateFragmentedPowerBars(bar, resource, isVertical)
    local cfg = self.db.profile.secondaryPowerBar
    local maxPower = UnitPowerMax("player", resource)
    if Helpers.IsSecretValue(maxPower) then
        -- @secret-policy: defer-until-readable — keep the existing pool.
        return
    end

    for i = 1, maxPower do
        if not bar.FragmentedPowerBars[i] then
            local fragmentBar = CreateFrame("StatusBar", nil, bar)
            local tex = LSM:Fetch("statusbar", GetBarTexture(cfg))
            fragmentBar:SetStatusBarTexture(tex)
            fragmentBar:SetOrientation(isVertical and "VERTICAL" or "HORIZONTAL")
            fragmentBar:SetFrameLevel(bar.StatusBar:GetFrameLevel())
            bar.FragmentedPowerBars[i] = fragmentBar

            local text = fragmentBar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            QUICore:SetSnappedPoint(text, "CENTER", fragmentBar, "CENTER", cfg.runeTimerTextX or 0, cfg.runeTimerTextY or 0)
            text:SetJustifyH("CENTER")
            CJKFont(text, GetGeneralFont(), QUICore:PixelRound(cfg.runeTimerTextSize or 10, text), GetGeneralFontOutline())
            text:SetShadowOffset(0, 0)
            text:SetText("")
            bar.FragmentedPowerBarTexts[i] = text
        end
    end
end

function QUICore:UpdateFragmentedPowerDisplay(bar, resource, isVertical)
    local cfg = self.db.profile.secondaryPowerBar
    local maxPower = UnitPowerMax("player", resource)
    if Helpers.IsSecretValue(maxPower) then
        -- @secret-policy: defer-until-readable — hold the last fragment layout.
        return
    end
    if maxPower <= 0 then return end

    local barWidth = bar:GetWidth()
    local barHeight = bar:GetHeight()

    local fragmentedBarWidth, fragmentedBarHeight
    if isVertical then
        fragmentedBarHeight = barHeight / maxPower
        fragmentedBarWidth = barWidth
    else
        fragmentedBarWidth = barWidth / maxPower
        fragmentedBarHeight = barHeight
    end

    bar.StatusBar:SetAlpha(0)

    local tex = LSM:Fetch("statusbar", GetBarTexture(cfg))
    if bar._quiFragmentTexture ~= tex then
        bar._quiFragmentTexture = tex
        for i = 1, #bar.FragmentedPowerBars do
            bar.FragmentedPowerBars[i]:SetStatusBarTexture(tex)
        end
    end

    local color = GetConfiguredResourceColor(cfg, resource)

    if resource == Enum.PowerType.Runes then
        local now = GetTime()
        for i = 1, maxPower do
            local rec = runeScratch[i]
            if not rec then
                rec = {}
                runeScratch[i] = rec
            end
            local start, duration, runeReady = GetRuneCooldown(i)
            rec.index = i
            if runeReady then
                rec.ready = true
                rec.remaining = 0
                rec.frac = 1
            else
                rec.ready = false
                if start and duration and duration > 0 then
                    local elapsed = now - start
                    rec.remaining = math_max(0, duration - elapsed)
                    rec.frac = math_max(0, math_min(1, elapsed / duration))
                else
                    rec.remaining = math.huge
                    rec.frac = 0
                end
            end
            runeOrder[i] = rec
        end
        for i = maxPower + 1, #runeOrder do
            runeOrder[i] = nil
        end

        table.sort(runeOrder, RuneDisplayLess)

        for pos = 1, maxPower do
            local rec = runeOrder[pos]
            local runeIndex = rec.index
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

                if runeText then
                    runeText:ClearAllPoints()
                    QUICore:SetSnappedPoint(runeText, "CENTER", runeFrame, "CENTER", cfg.runeTimerTextX or 0, cfg.runeTimerTextY or 0)
                    CJKFont(runeText, GetGeneralFont(), QUICore:PixelRound(cfg.runeTimerTextSize or 10, runeText), GetGeneralFontOutline())
                    runeText:SetShadowOffset(0, 0)
                end

                if rec.ready then
                    runeFrame:SetMinMaxValues(0, 1)
                    runeFrame:SetValue(1)
                    runeText:SetText("")
                    runeFrame:SetStatusBarColor(color.r, color.g, color.b)
                else
                    runeFrame:SetMinMaxValues(0, 1)
                    runeFrame:SetValue(rec.frac)

                    if cfg.showFragmentedPowerBarText ~= false then
                        runeText:SetFormattedText("%.1f", math_max(0, rec.remaining))
                    else
                        runeText:SetText("")
                    end

                    runeFrame:SetStatusBarColor(color.r * 0.5, color.g * 0.5, color.b * 0.5)
                end

                runeFrame:Show()
            end
        end

        for i = maxPower + 1, #bar.FragmentedPowerBars do
            if bar.FragmentedPowerBars[i] then
                bar.FragmentedPowerBars[i]:Hide()
                if bar.FragmentedPowerBarTexts[i] then
                    bar.FragmentedPowerBarTexts[i]:SetText("")
                end
            end
        end

        if cfg.showTicks then
            local runeTickPx = QUICore:GetPixelSize(bar)
            LayoutSegmentDividers(bar, bar, maxPower - 1, runeTickPx,
                (cfg.tickThickness or 1) * runeTickPx,
                cfg.tickColor or { 0, 0, 0, 1 },
                isVertical,
                isVertical and function(i) return i * fragmentedBarHeight end
                    or function(i) return i * fragmentedBarWidth end,
                isVertical and barWidth or barHeight)
        else
            for _, tick in ipairs(bar.ticks) do
                tick:Hide()
            end
        end

    elseif resource == Enum.PowerType.Essence then
        local current = UnitPower("player", Enum.PowerType.Essence)
        if Helpers.IsSecretValue(current) then
            -- @secret-policy: defer-until-readable — extrapolation state is
            return
        end
        if current == nil then current = 0 end
        local now = GetTime()

        if not InCombatLockdown() then
            local regenRate = GetPowerRegenForPowerType(Enum.PowerType.Essence)
            if Helpers.IsSecretValue(regenRate) then
                -- @secret-policy: defer-until-readable — keep the cached
                regenRate = nil
            elseif regenRate ~= nil and regenRate > 0 then
                essenceTickDuration = 1 / regenRate
            end
        end
        if not essenceTickDuration or essenceTickDuration <= 0 then
            essenceTickDuration = 5
        end

        if essenceLastCount and current > essenceLastCount then
            if current < maxPower then
                essenceNextTick = now + essenceTickDuration
            else
                essenceNextTick = nil
            end
        end

        if current < maxPower and not essenceNextTick then
            essenceNextTick = now + essenceTickDuration
        end

        if current >= maxPower then
            essenceNextTick = nil
        end

        essenceLastCount = current

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
                    essenceFrame:SetValue(1)
                    essenceFrame:SetStatusBarColor(color.r, color.g, color.b)
                elseif pos == current + 1 then
                    essenceFrame:SetValue(partialFill)
                    essenceFrame:SetStatusBarColor(color.r * 0.5, color.g * 0.5, color.b * 0.5)
                else
                    essenceFrame:SetValue(0)
                    essenceFrame:SetStatusBarColor(color.r * 0.5, color.g * 0.5, color.b * 0.5)
                end

                if essenceText then
                    essenceText:SetText("")
                end

                essenceFrame:Show()
            end
        end

        for i = maxPower + 1, #bar.FragmentedPowerBars do
            if bar.FragmentedPowerBars[i] then
                bar.FragmentedPowerBars[i]:Hide()
                if bar.FragmentedPowerBarTexts[i] then
                    bar.FragmentedPowerBarTexts[i]:SetText("")
                end
            end
        end

        if cfg.showTicks then
            local essTickPx = QUICore:GetPixelSize(bar)
            LayoutSegmentDividers(bar, bar, maxPower - 1, essTickPx,
                (cfg.tickThickness or 1) * essTickPx,
                cfg.tickColor or { 0, 0, 0, 1 },
                isVertical,
                isVertical and function(i) return i * fragmentedBarHeight end
                    or function(i) return i * fragmentedBarWidth end,
                isVertical and barWidth or barHeight)
        else
            for _, tick in ipairs(bar.ticks) do
                tick:Hide()
            end
        end
    end
end

local function RuneTimerOnUpdate(bar, delta)
    runeUpdateElapsed = runeUpdateElapsed + delta
    if runeUpdateElapsed < 0.05 then return end
    runeUpdateElapsed = 0

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

    if not anyOnCooldown then
        bar:SetScript("OnUpdate", nil)
        runeUpdateRunning = false
        wipe(_lastRuneRounded)
        wipe(_lastRuneFormatted)
    end
end

local function EssenceTimerOnUpdate(bar, delta)
    essenceUpdateElapsed = essenceUpdateElapsed + delta
    if essenceUpdateElapsed < 0.05 then return end
    essenceUpdateElapsed = 0

    local maxPower = UnitPowerMax("player", Enum.PowerType.Essence)
    local current = UnitPower("player", Enum.PowerType.Essence)
    if Helpers.IsSecretValue(maxPower) or Helpers.IsSecretValue(current) then
        -- @secret-policy: defer-until-readable — keep the timer running; the
        return
    end
    if maxPower <= 0 then return end
    if current == nil then current = 0 end

    if current >= maxPower then
        bar:SetScript("OnUpdate", nil)
        essenceUpdateRunning = false
        essenceNextTick = nil
        for i = 1, maxPower do
            local essenceFrame = bar.FragmentedPowerBars and bar.FragmentedPowerBars[i]
            if essenceFrame and essenceFrame:IsShown() then
                essenceFrame:SetValue(1)
            end
        end
        return
    end

    if essenceLastCount and current > essenceLastCount then
        essenceNextTick = GetTime() + (essenceTickDuration or 5)
    end
    essenceLastCount = current

    if current < maxPower and not essenceNextTick then
        essenceNextTick = GetTime() + (essenceTickDuration or 5)
    end

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

local function RenewingMistChargeOnUpdate(bar, delta)
    renewingMistUpdateElapsed = renewingMistUpdateElapsed + (delta or 0)
    if renewingMistUpdateElapsed < 0.05 then return end
    renewingMistUpdateElapsed = 0

    if GetSecondaryResource() ~= QUI_POWER.RenewingMistCharges then
        bar:SetScript("OnUpdate", nil)
        renewingMistUpdateRunning = false
        return
    end

    local max, current, startTime, duration, chargeModRate = GetRenewingMistCharges()
    if not max or not current or not startTime or startTime <= 0 or not duration or duration <= 0 then
        bar:SetScript("OnUpdate", nil)
        renewingMistUpdateRunning = false
        return
    end

    if current >= max then
        bar:SetScript("OnUpdate", nil)
        renewingMistUpdateRunning = false
        if bar.StatusBar then
            bar.StatusBar:SetValue(current)
        end
        return
    end

    local elapsed = (GetTime() - startTime) * (chargeModRate or 1)
    if elapsed >= duration then
        RenewingMistChargeState.current = math_min(max, current + 1)
        if RenewingMistChargeState.current < max then
            RenewingMistChargeState.startTime = GetTime()
            current = RenewingMistChargeState.current
            startTime = RenewingMistChargeState.startTime
            elapsed = 0
        else
            bar:SetScript("OnUpdate", nil)
            renewingMistUpdateRunning = false
            if bar.StatusBar then
                bar.StatusBar:SetValue(RenewingMistChargeState.current)
            end
            if bar.TextValue then
                bar.TextValue:SetText(tostring(RenewingMistChargeState.current))
            end
            return
        end
    end

    if bar.StatusBar then
        local partial = math_max(0, math_min(1, elapsed / duration))
        bar.StatusBar:SetValue(math_min(max, current + partial))
    end
    if bar.TextValue then
        bar.TextValue:SetText(tostring(current or 0))
    end
end

function QUICore:UpdateSecondaryPowerBarTicks(bar, resource, max)
    local cfg = self.db.profile.secondaryPowerBar

    for _, tick in ipairs(bar.ticks) do
        tick:Hide()
    end

    if not cfg.showTicks or not tickedPowerTypes[resource] or fragmentedPowerTypes[resource] then
        return
    end

    local width  = bar:GetWidth()
    local height = bar:GetHeight()
    if width <= 0 or height <= 0 then return end

    local isVertical = ResolveIsVertical(cfg, self.db.profile.powerBar)

    local displayMax = max
    if resource == Enum.PowerType.SoulShards then
        local shardMax = UnitPowerMax("player", resource)
        if Helpers.IsSecretValue(shardMax) then
            -- @secret-policy: defer-until-readable — hold the last tick layout.
            return
        end
        displayMax = shardMax
    end

    local genTickPx = QUICore:GetPixelSize(bar)
    LayoutSegmentDividers(bar, bar.StatusBar, displayMax - 1, genTickPx,
        (cfg.tickThickness or 1) * genTickPx,
        cfg.tickColor or { 0, 0, 0, 1 },
        isVertical,
        isVertical and function(i) return (i / displayMax) * height end
            or function(i) return (i / displayMax) * width end,
        isVertical and width or height)
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

function QUICore:UpdateChargedComboPoints(bar, resource, max, current, isVertical)
    bar.chargedOverlays = bar.chargedOverlays or {}

    for _, overlay in ipairs(bar.chargedOverlays) do
        overlay:Hide()
    end

    if resource ~= Enum.PowerType.ComboPoints then return end
    if not max or max <= 0 then return end

    local chargedPoints = GetUnitChargedPowerPoints and GetUnitChargedPowerPoints("player")
    if Helpers.IsSecretValue(chargedPoints) then
        -- @secret-policy: defer-until-readable — charged indices unknowable;
        return
    end
    if not chargedPoints or #chargedPoints == 0 then return end

    local pc = self.db.profile.powerColors
    if not pc then return end

    local chargedColor = pc.chargedComboPoints or { 0.00, 0.68, 1.00, 1 }

    local width = bar:GetWidth()
    local height = bar:GetHeight()
    if width <= 0 or height <= 0 then return end

    local segmentSize = isVertical and (height / max) or (width / max)

    for idx, cpIndex in ipairs(chargedPoints) do
        if not Helpers.IsSecretValue(cpIndex) and cpIndex >= 1 and cpIndex <= max then
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

            local isFilled = cpIndex <= current
            if isFilled then
                local tex = LSM:Fetch("statusbar", GetBarTexture(self.db.profile.secondaryPowerBar))
                overlay.tex:SetTexture(tex)
                overlay.tex:SetVertexColor(chargedColor[1], chargedColor[2], chargedColor[3], chargedColor[4] or 1)
            else
                overlay.tex:SetTexture(nil)
            end

            SkinBase.ApplyPixelBackdrop(overlay, px, false, false,
                { chargedColor[1], chargedColor[2], chargedColor[3], chargedColor[4] or 1 })
            overlay:Show()
        end
    end

    for i = #chargedPoints + 1, #bar.chargedOverlays do
        if bar.chargedOverlays[i] then
            bar.chargedOverlays[i]:Hide()
        end
    end
end

function QUICore:UpdateSecondaryPowerBarValue(forceShown)
    local db = self.db and self.db.profile
    local cfg = db and db.secondaryPowerBar
    local bar = self.secondaryPowerBar
    if not cfg or not cfg.enabled or not bar then return nil end
    if not forceShown and not bar:IsShown() then return nil end
    if (cfg.lockedToEssential or cfg.lockedToUtility) and not _secondaryLockedReady then return nil end
    local resource = GetSecondaryResource()
    if not resource then return nil end

    if resource ~= QUI_POWER.RenewingMistCharges and renewingMistUpdateRunning then
        bar:SetScript("OnUpdate", nil)
        renewingMistUpdateRunning = false
    end

    if GetCDMHiddenAlpha() ~= nil then return nil end
    if not ShouldShowBar(cfg) then return nil end

    local isVertical = bar._cachedIsVertical or false
    local textCfg = GetSecondaryTextConfig(cfg)

    local color = GetConfiguredResourceColor(cfg, resource)
    bar.StatusBar:SetStatusBarColor(color.r, color.g, color.b, color.a or 1)

    local max, current, displayValue, valueType = GetSecondaryResourceValue(resource)
    if valueType == "defer" then
        -- @secret-policy: defer-until-readable — Lua-derived state (rune
        return "defer", nil, resource
    end
    if valueType == "secret" then
        -- @secret-policy: keep-visible-when-unknown + sink-passthrough — the
        if bar.FragmentedPowerBars then
            for _, fragmentBar in ipairs(bar.FragmentedPowerBars) do
                fragmentBar:Hide()
            end
        end
        bar.StatusBar:SetAlpha(1)
        bar.StatusBar:SetMinMaxValues(0, max)
        bar.StatusBar:SetValue(current)
        if Helpers.IsSecretValue(displayValue) then
            bar.TextValue:SetFormattedText("%d", displayValue)
        else
            bar.TextValue:SetText("")
        end
        SafeShow(bar)
        return "secret", nil, resource
    end
    if not max then
        if renewingMistUpdateRunning then
            bar:SetScript("OnUpdate", nil)
            renewingMistUpdateRunning = false
        end
        SafeHide(bar)
        return nil
    end

    if resource == QUI_POWER.RenewingMistCharges then
        local _, rawCurrent, startTime, duration = GetRenewingMistCharges()
        local shouldAnimate = rawCurrent and rawCurrent < max and startTime and startTime > 0 and duration and duration > 0
        if shouldAnimate and not renewingMistUpdateRunning then
            renewingMistUpdateRunning = true
            renewingMistUpdateElapsed = 0
            bar:SetScript("OnUpdate", RenewingMistChargeOnUpdate)
        elseif not shouldAnimate and renewingMistUpdateRunning then
            bar:SetScript("OnUpdate", nil)
            renewingMistUpdateRunning = false
        end
    end

    if fragmentedPowerTypes[resource] then
        self:UpdateFragmentedPowerDisplay(bar, resource, isVertical)

        if resource == Enum.PowerType.Essence then
            local essenceCur, essenceMax, essSecret = ReadPlayerPowerPair(Enum.PowerType.Essence)
            if essSecret then
                -- @secret-policy: defer-until-readable — leave the animation
                essenceCur = nil
            elseif essenceCur < essenceMax and not essenceUpdateRunning then
                essenceUpdateRunning = true
                essenceUpdateElapsed = 0
                bar:SetScript("OnUpdate", EssenceTimerOnUpdate)
            elseif essenceCur >= essenceMax and essenceUpdateRunning then
                bar:SetScript("OnUpdate", nil)
                essenceUpdateRunning = false
            end
        end

        if resource == Enum.PowerType.Runes then
            local anyOnCooldown = false
            for i = 1, 6 do
                local _, _, runeReady = GetRuneCooldown(i)
                if not runeReady then
                    anyOnCooldown = true
                    break
                end
            end
            if anyOnCooldown and not runeUpdateRunning then
                runeUpdateRunning = true
                runeUpdateElapsed = 0
                bar:SetScript("OnUpdate", RuneTimerOnUpdate)
            elseif not anyOnCooldown and runeUpdateRunning then
                bar:SetScript("OnUpdate", nil)
                runeUpdateRunning = false
            end
        end

        bar.StatusBar:SetMinMaxValues(0, max)
        bar.StatusBar:SetValue(current)

        bar.StatusBar:SetStatusBarColor(color.r, color.g, color.b, color.a or 1)

        bar.TextValue:SetText(tostring(current))
    else
        bar.StatusBar:SetAlpha(1)
        bar.StatusBar:SetMinMaxValues(0, max)
        bar.StatusBar:SetValue(current)

        bar.StatusBar:SetStatusBarColor(color.r, color.g, color.b, color.a or 1)

        if valueType == "shards" then
            bar.TextValue:SetFormattedText("%.1f", displayValue or 0)
        elseif valueType == "percent" and textCfg.showPercent then
            bar.TextValue:SetText(FormatPercentValue(displayValue, textCfg))
        elseif valueType == "percent" then
            local stagger = UnitStagger("player")
            if Helpers.IsSecretValue(stagger) then
                bar.TextValue:SetFormattedText("%d", stagger) -- @secret-policy: sink-passthrough
            else
                if stagger == nil then stagger = 0 end
                bar.TextValue:SetText(tostring(math_floor(stagger)))
            end
        else
            bar.TextValue:SetText(tostring(displayValue or 0))
        end

        for _, fragmentBar in ipairs(bar.FragmentedPowerBars) do
            fragmentBar:Hide()
        end
    end

    self:UpdateChargedComboPoints(bar, resource, max, current, isVertical)

    bar:SetAlpha(1)
    SafeShow(bar)
    return valueType, max, resource
end

function QUICore:UpdateSecondaryPowerBar()
    local cfg = self.db.profile.secondaryPowerBar
    local textCfg = GetSecondaryTextConfig(cfg)

    local bar = self:GetSecondaryPowerBar()

    SyncSwapAnchorOwnership(ShouldSwapBars() and not IsForcingNaturalDuringBootstrap())

    if not cfg.enabled then
        local wasShown = bar:IsShown()
        SafeHide(bar)
        if wasShown and not bar:IsShown() and _G.QUI_UpdateAnchoredFrames then
            _G.QUI_UpdateAnchoredFrames()
        end
        if self.UpdateResourceBarsProxy then self:UpdateResourceBarsProxy() end
        return
    end

    if (cfg.lockedToEssential or cfg.lockedToUtility) and not _secondaryLockedReady then
        SafeHide(bar)
        return
    end
    local resource = GetSecondaryResource()

    if not resource then
        local wasShown = bar:IsShown()
        if renewingMistUpdateRunning then
            bar:SetScript("OnUpdate", nil)
            renewingMistUpdateRunning = false
        end
        SafeHide(bar)
        if wasShown and not bar:IsShown() and _G.QUI_UpdateAnchoredFrames then
            _G.QUI_UpdateAnchoredFrames()
        end
        if self.UpdateResourceBarsProxy then self:UpdateResourceBarsProxy() end
        return
    end

    if resource ~= QUI_POWER.RenewingMistCharges and renewingMistUpdateRunning then
        bar:SetScript("OnUpdate", nil)
        renewingMistUpdateRunning = false
    end

    do
        local cdmHiddenAlpha = GetCDMHiddenAlpha()
        if cdmHiddenAlpha ~= nil then
            bar:SetAlpha(cdmHiddenAlpha)
            SafeShow(bar)
            return
        end
    end

    local visibilityHidden = not ShouldShowBar(cfg)
    if visibilityHidden then
        bar:SetAlpha(0)
        SafeShow(bar)
        return
    end

    local layerPriority = self.db.profile.hudLayering and self.db.profile.hudLayering.secondaryPowerBar or 6
    local frameLevel = self:GetHUDFrameLevel(layerPriority)
    SafeSetFrameLevel(bar, frameLevel)
    if bar.TextFrame then
        SafeSetFrameLevel(bar.TextFrame, frameLevel + 2)
    end

    local isVertical = ResolveIsVertical(cfg, self.db.profile.powerBar)

    bar.StatusBar:SetOrientation(isVertical and "VERTICAL" or "HORIZONTAL")

    local width
    local lockedToPrimaryHandled = false

    if cfg.swapToPrimaryPosition and ShouldSwapBars() and not IsForcingNaturalDuringBootstrap() then
        local pcx, pcy, plen, pT = GetPrimaryNaturalSlotForSwap()
        local scx, scy, _, sT = GetSecondaryNaturalSlotForSwap()

        SyncSwapAnchorOwnership(true)

        local offsetX, offsetY
        if ShouldHidePrimaryOnSwap() then
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

        if cfg.lockedToPrimary then
            width = plen
        else
            width = cfg.width
            if not width or width <= 0 then width = plen end
        end
        lockedToPrimaryHandled = true
    end

    if not lockedToPrimaryHandled and cfg.lockedToPrimary then
        local primaryBar = self.powerBar
        local primaryCfg = self.db.profile.powerBar

        if primaryBar and primaryBar:IsShown() and primaryCfg then
            local primaryCenterX, primaryCenterY = primaryBar:GetCenter()
            local screenCenterX, screenCenterY = UIParent:GetCenter()

            if primaryCenterX and primaryCenterY and screenCenterX and screenCenterY then
                primaryCenterX = math_floor(primaryCenterX + 0.5)
                primaryCenterY = math_floor(primaryCenterY + 0.5)
                screenCenterX = math_floor(screenCenterX + 0.5)
                screenCenterY = math_floor(screenCenterY + 0.5)
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
                    local primaryActualWidth = primaryBar:GetWidth()
                    local primaryVisualRight = primaryCenterX + (primaryActualWidth / 2)
                    local secondaryCenterX = primaryVisualRight + (secondaryHeight / 2)
                    offsetX = math_floor(secondaryCenterX - screenCenterX + 0.5)
                    offsetY = math_floor(primaryCenterY - screenCenterY + 0.5)
                else
                    local primaryVisualTop = primaryCenterY + (primaryHeight / 2) + primaryBorderSize
                    local secondaryCenterY = primaryVisualTop + (secondaryHeight / 2) + secondaryBorderSize
                    offsetX = math_floor(primaryCenterX - screenCenterX + 0.5)
                    offsetY = math_floor(secondaryCenterY - screenCenterY + 0.5) - 1
                end

                local targetWidth = primaryWidth + (2 * primaryBorderSize) - (2 * secondaryBorderSize)
                width = math_floor(targetWidth + 0.5)

                local finalX = offsetX + (cfg.offsetX or 0)
                local finalY = offsetY + (cfg.offsetY or 0)
                if not (_G.QUI_HasFrameAnchor and _G.QUI_HasFrameAnchor("secondaryPower")) and (bar._cachedX ~= finalX or bar._cachedY ~= finalY or bar._cachedAutoMode ~= "lockedToPrimary") then
                    bar:ClearAllPoints()
                    bar:SetPoint("CENTER", UIParent, "CENTER", finalX, finalY)
                    bar._cachedX = finalX
                    bar._cachedY = finalY
                    bar._cachedAnchor = nil
                    bar._cachedAutoMode = "lockedToPrimary"
                    if _G.QUI_UpdateAnchoredUnitFrames then
                        _G.QUI_UpdateAnchoredUnitFrames()
                    end
                end

                lockedToPrimaryHandled = true
            else
                if not bar._lockedToPrimaryDeferred then
                    bar._lockedToPrimaryDeferred = true
                    C_Timer.After(0.1, function()
                        bar._lockedToPrimaryDeferred = nil
                        self:UpdateSecondaryPowerBar()
                    end)
                end
                return
            end
        elseif cfg.standaloneMode and cachedPrimaryDimensions.centerX then
            local screenCenterX, screenCenterY = UIParent:GetCenter()

            if screenCenterX and screenCenterY then
                screenCenterX = math_floor(screenCenterX + 0.5)
                screenCenterY = math_floor(screenCenterY + 0.5)
                local primaryCenterX = cachedPrimaryDimensions.centerX
                local primaryCenterY = cachedPrimaryDimensions.centerY
                local primaryHeight = cachedPrimaryDimensions.height
                local primaryBorderSize = cachedPrimaryDimensions.borderSize
                local primaryWidth = cachedPrimaryDimensions.width
                local secondaryHeight = cfg.height or 8
                local secondaryBorderSize = cfg.borderSize or 1

                local offsetX, offsetY

                if isVertical then
                    local primaryVisualRight = primaryCenterX + (primaryWidth / 2)
                    local secondaryCenterX = primaryVisualRight + (secondaryHeight / 2)
                    offsetX = math_floor(secondaryCenterX - screenCenterX + 0.5)
                    offsetY = math_floor(primaryCenterY - screenCenterY + 0.5)
                else
                    local primaryVisualTop = primaryCenterY + (primaryHeight / 2) + primaryBorderSize
                    local secondaryCenterY = primaryVisualTop + (secondaryHeight / 2) + secondaryBorderSize
                    offsetX = math_floor(primaryCenterX - screenCenterX + 0.5)
                    offsetY = math_floor(secondaryCenterY - screenCenterY + 0.5) - 1
                end

                local targetWidth = primaryWidth + (2 * primaryBorderSize) - (2 * secondaryBorderSize)
                width = math_floor(targetWidth + 0.5)

                local finalX = offsetX + (cfg.offsetX or 0)
                local finalY = offsetY + (cfg.offsetY or 0)
                if not (_G.QUI_HasFrameAnchor and _G.QUI_HasFrameAnchor("secondaryPower")) and (bar._cachedX ~= finalX or bar._cachedY ~= finalY or bar._cachedAutoMode ~= "lockedToPrimaryCached") then
                    bar:ClearAllPoints()
                    bar:SetPoint("CENTER", UIParent, "CENTER", finalX, finalY)
                    bar._cachedX = finalX
                    bar._cachedY = finalY
                    bar._cachedAnchor = nil
                    bar._cachedAutoMode = "lockedToPrimaryCached"
                    if _G.QUI_UpdateAnchoredUnitFrames then
                        _G.QUI_UpdateAnchoredUnitFrames()
                    end
                end

                lockedToPrimaryHandled = true
            end
        else
            SafeHide(bar)
            return
        end
    end

    if not lockedToPrimaryHandled then
        local anchor = cfg.autoAttach and GetCDMViewerFrame("essential") or _G[cfg.attachTo]

        if not cfg.standaloneMode and not cfg.lockedToEssential and not cfg.lockedToUtility then
            local cdmShouldBeVisible = _G.QUI_ShouldCDMBeVisible and _G.QUI_ShouldCDMBeVisible()
            if not anchor or (not anchor:IsShown() and not cdmShouldBeVisible) then
                SafeHide(bar)
                return
            end
        end

        if cfg.autoAttach and anchor then
            local anchorWidth = anchor:GetWidth()
            local anchorHeight = anchor:GetHeight()
            if not anchorWidth or anchorWidth <= 1 or not anchorHeight or anchorHeight <= 1 then
                SafeHide(bar)
                if not bar._autoAttachDeferred then
                    bar._autoAttachDeferred = true
                    C_Timer.After(0.5, function()
                        bar._autoAttachDeferred = nil
                        self:UpdateSecondaryPowerBar()
                    end)
                end
                return
            end
        end

        local barHeight = cfg.height or 8
        if cfg.autoAttach then
            if cfg.width and cfg.width > 0 then
                width = cfg.width
            else
                if self.powerBar and self.powerBar:IsShown() then
                    width = self.powerBar:GetWidth()
                elseif anchor then
                    local avs = GetViewerState(anchor)
                    width = GetRawContentWidth(avs)
                end
                if not width or width <= 0 then
                    width = self.db.profile.ncdm and self.db.profile.ncdm._lastEssentialWidth
                end
                if not width or width <= 0 then
                    width = 200
                end
            end

            local wantedOffsetX = QUICore:PixelRound(cfg.offsetX or 0, bar)
            local wantedAnchor = (self.powerBar and self.powerBar:IsShown()) and self.powerBar or anchor

            if not wantedAnchor then
            else
                if not (_G.QUI_HasFrameAnchor and _G.QUI_HasFrameAnchor("secondaryPower")) and (bar._cachedAnchor ~= wantedAnchor or bar._cachedX ~= wantedOffsetX or bar._cachedAutoMode ~= true) then
                    bar:ClearAllPoints()
                    bar:SetPoint("BOTTOM", wantedAnchor, "TOP", wantedOffsetX, 0)
                    bar._cachedAnchor = wantedAnchor
                    bar._cachedX = wantedOffsetX
                    bar._cachedY = nil
                    bar._cachedAutoMode = true
                    if _G.QUI_UpdateAnchoredUnitFrames then
                        _G.QUI_UpdateAnchoredUnitFrames()
                    end
                end
            end
        end

        if not cfg.autoAttach or (cfg.autoAttach and not ((self.powerBar and self.powerBar:IsShown()) or anchor)) then
            width = cfg.width
            if not width or width <= 0 then
                local essentialViewer = GetCDMViewerFrame("essential")
                if essentialViewer then
                    local evs = GetViewerState(essentialViewer)
                    width = GetRawContentWidth(evs)
                end
                if width and width > 0 then
                    if not Helpers.IsEditModeActive() and self.db.profile.ncdm then
                        self.db.profile.ncdm._lastEssentialWidth = width
                    end
                else
                    width = self.db.profile.ncdm and self.db.profile.ncdm._lastEssentialWidth
                end
                if not width or width <= 0 then
                    width = 200
                end
            end

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
                bar._cachedAnchor = nil
                bar._cachedAutoMode = false
                if _G.QUI_UpdateAnchoredUnitFrames then
                    _G.QUI_UpdateAnchoredUnitFrames()
                end
            end
        end
    end

    if not InCombatLockdown() then
        local wantedH, wantedW
        if isVertical then
            wantedW = QUICore:PixelRound(cfg.height or 4, bar)
            wantedH = QUICore:PixelRound(width, bar)
        else
            wantedH = QUICore:PixelRound(cfg.height or 4, bar)
            wantedW = QUICore:PixelRound(width, bar)
        end

        if bar._cachedH ~= wantedH then
            bar:SetHeight(wantedH)
            bar._cachedH = wantedH
        end
        if bar._cachedW ~= wantedW then
            bar:SetWidth(wantedW)
            bar._cachedW = wantedW
        end

        local secBorderSizePixels = cfg.borderSize or 1
        local sbR, sbG, sbB, sbA = Helpers.GetSkinBorderColor(cfg, "")
        if bar._cachedBorderSize ~= secBorderSizePixels then
            if UIKit and UIKit.CreateBackdropBorder then
                bar.Border = UIKit.CreateBackdropBorder(bar, secBorderSizePixels, sbR, sbG, sbB, sbA)
                if bar.Border then
                    bar.Border:SetShown(secBorderSizePixels > 0)
                end
            end
            bar._cachedBorderSize = secBorderSizePixels
        elseif bar.Border and bar.Border.SetBackdropBorderColor then
            bar.Border:SetBackdropBorderColor(sbR, sbG, sbB, sbA)
        end
    end

    local bgColor = cfg.bgColor or { 0.15, 0.15, 0.15, 1 }
    if bar.Background then
        bar.Background:SetColorTexture(bgColor[1], bgColor[2], bgColor[3], bgColor[4] or 1)
    end

    local tex = LSM:Fetch("statusbar", GetBarTexture(cfg))
    if bar._cachedTex ~= tex then
        bar.StatusBar:SetStatusBarTexture(tex)
        bar._cachedTex = tex
    end

    bar._cachedIsVertical = isVertical

    if fragmentedPowerTypes[resource] then
        self:CreateFragmentedPowerBars(bar, resource, isVertical)
    end

    local vType, vMax, vResource = self:UpdateSecondaryPowerBarValue(true)
    if vType == nil or vType == "defer" or vType == "secret" then
        return
    end

    ns.SafeCall("best-effort-style", function()
        CJKFont(bar.TextValue, GetGeneralFont(), QUICore:PixelRound(textCfg.textSize or 12, bar.TextValue), GetGeneralFontOutline())
        bar.TextValue:SetShadowOffset(0, 0)
        ApplyPowerBarTextPlacement(bar, textCfg)

        if textCfg.textUseClassColor then
            local _, class = UnitClass("player")
            -- @secret-policy: collapse-only — secret class keeps the current text color
            if issecretvalue and issecretvalue(class) then class = nil end
            local classColor = class and RAID_CLASS_COLORS[class]
            if classColor then
                bar.TextValue:SetTextColor(classColor.r, classColor.g, classColor.b, 1)
            end
        else
            local c = textCfg.textCustomColor or { 1, 1, 1, 1 }
            bar.TextValue:SetTextColor(c[1], c[2], c[3], c[4] or 1)
        end

        if bar.SoulShardDecimal then
            CJKFont(bar.SoulShardDecimal, GetGeneralFont(), QUICore:PixelRound(textCfg.textSize or 12, bar.SoulShardDecimal), GetGeneralFontOutline())
            bar.SoulShardDecimal:SetShadowOffset(0, 0)
            if textCfg.textUseClassColor then
                local _, class = UnitClass("player")
                -- @secret-policy: collapse-only — secret class keeps the current text color
                if issecretvalue and issecretvalue(class) then class = nil end
                local classColor = class and RAID_CLASS_COLORS[class]
                if classColor then
                    bar.SoulShardDecimal:SetTextColor(classColor.r, classColor.g, classColor.b, 1)
                end
            else
                local c = textCfg.textCustomColor or { 1, 1, 1, 1 }
                bar.SoulShardDecimal:SetTextColor(c[1], c[2], c[3], c[4] or 1)
            end
        end

    end)

    bar.TextFrame:SetShown(textCfg.showText ~= false)

    if not fragmentedPowerTypes[vResource] then
        self:UpdateSecondaryPowerBarTicks(bar, vResource, vMax)
    end
    self:UpdateSecondaryPowerBarIndicators(bar, vMax, isVertical)

    if bar.SoulShardDecimal then
        bar.SoulShardDecimal:Hide()
    end

    if self.UpdateResourceBarsProxy then self:UpdateResourceBarsProxy() end
    ScheduleNaturalSlotCapture()
    TriggerSwapReciprocalUpdate()
end

local POWER_EVENT_TOKENS = {
    [Enum.PowerType.Mana]          = "MANA",
    [Enum.PowerType.Rage]          = "RAGE",
    [Enum.PowerType.Focus]         = "FOCUS",
    [Enum.PowerType.Energy]        = "ENERGY",
    [Enum.PowerType.ComboPoints]   = "COMBO_POINTS",
    [Enum.PowerType.Runes]         = "RUNES",
    [Enum.PowerType.RunicPower]    = "RUNIC_POWER",
    [Enum.PowerType.SoulShards]    = "SOUL_SHARDS",
    [Enum.PowerType.LunarPower]    = "LUNAR_POWER",
    [Enum.PowerType.HolyPower]     = "HOLY_POWER",
    [Enum.PowerType.Maelstrom]     = "MAELSTROM",
    [Enum.PowerType.Chi]           = "CHI",
    [Enum.PowerType.Insanity]      = "INSANITY",
    [Enum.PowerType.ArcaneCharges] = "ARCANE_CHARGES",
    [Enum.PowerType.Fury]          = "FURY",
    [Enum.PowerType.Essence]       = "ESSENCE",
}

local function RoutePowerEvent(eventToken, primaryToken, secondaryToken)
    if eventToken == nil then return true, true end
    local updatePrimary = (primaryToken == nil) or (primaryToken == eventToken)
    local updateSecondary = (secondaryToken == nil) or (secondaryToken == eventToken)
    return updatePrimary, updateSecondary
end
ns.POWER_EVENT_TOKENS = POWER_EVENT_TOKENS
ns.RoutePowerEvent = RoutePowerEvent

local function RequestBarUpdates(updatePrimary, updateSecondary, fullRefresh, secondaryResource)
    if not (QUICore and QUICore.db) then return end
    local db = QUICore.db.profile
    local unthrottled = db and db.powerBar and db.powerBar.unthrottledCPU
    local now = GetTime()

    local secondaryHandled = false
    if updatePrimary then
        if unthrottled or (now - lastPrimaryUpdate >= UPDATE_THROTTLE) then
            lastPrimaryUpdate = now
            if fullRefresh then
                secondaryHandled = QUICore:UpdatePowerBar() == true
            else
                QUICore:UpdatePowerBarValue()
            end
        else
            if fullRefresh then primaryFullQueued = true end
            QueuePrimaryTrailingUpdate()
        end
    end

    if updateSecondary and not secondaryHandled then
        local resource = secondaryResource
        if resource == nil then resource = GetSecondaryResource() end
        if unthrottled or instantFeedbackTypes[resource] then
            if fullRefresh then
                QUICore:UpdateSecondaryPowerBar()
            else
                QUICore:UpdateSecondaryPowerBarValue()
            end
        elseif now - lastSecondaryUpdate >= UPDATE_THROTTLE then
            lastSecondaryUpdate = now
            if fullRefresh then
                QUICore:UpdateSecondaryPowerBar()
            else
                QUICore:UpdateSecondaryPowerBarValue()
            end
        else
            if fullRefresh then secondaryFullQueued = true end
            QueueSecondaryTrailingUpdate()
        end
    end
end

function QUICore:OnUnitPower(event, unit, powerType)
    if unit and unit ~= "player" then
        return
    end

    if Helpers.IsSecretValue(powerType) then
        powerType = nil
    end

    if powerType == nil then
        RequestBarUpdates(true, true, true)
        return
    end

    local primaryResource = GetPrimaryResource()
    local secondaryResource = GetSecondaryResource()
    local updatePrimary, updateSecondary = RoutePowerEvent(powerType,
        POWER_EVENT_TOKENS[primaryResource],
        POWER_EVENT_TOKENS[secondaryResource])
    RequestBarUpdates(updatePrimary, updateSecondary,
        event == "UNIT_MAXPOWER", secondaryResource)
end

function QUICore:OnUnitAura(_, _, updateInfo)
    if issecretvalue and issecretvalue(updateInfo) then
        updateInfo = nil
    end
    local resource = GetSecondaryResource()
    if resource == QUI_POWER.MaelstromWeapon then
        MaelstromWeaponTracker:Resync()
    elseif not (resource == QUI_POWER.VengSoulFragments
        or (VDH_SOUL_FRAGMENTS_POWER and resource == VDH_SOUL_FRAGMENTS_POWER)
        or resource == "SOUL"
        or resource == QUI_POWER.Whirlwind
        or resource == QUI_POWER.TipOfTheSpear) then
        return
    end
    local bar = self.secondaryPowerBar
    if not bar then
        self:UpdateSecondaryPowerBar()
        return
    end
    local vType, vMax = self:UpdateSecondaryPowerBarValue()
    if bar:IsShown()
        and vType == bar._cachedAuraValueType
        and vMax == bar._cachedAuraValueMax then
        return
    end
    bar._cachedAuraValueType, bar._cachedAuraValueMax = vType, vMax
    self:UpdateSecondaryPowerBar()
end

function QUICore:OnSpellChargeUpdate(event, spellID)
    if GetSecondaryResource() == QUI_POWER.RenewingMistCharges then
        if event == "UNIT_SPELLCAST_SUCCEEDED" then
            if Helpers.IsSecretValue(spellID) then
                -- @secret-policy: refresh-without-attribution — the cast
                spellID = nil
            end
            for _, renewingMistSpellID in ipairs(RENEWING_MIST_SPELL_IDS) do
                if spellID == renewingMistSpellID then
                    NoteRenewingMistCast()
                    break
                end
            end
            if spellID ~= nil and RUSHING_WIND_KICK_SPELL_IDS[spellID] then
                AdvanceRenewingMistRecharge(RUSHING_WIND_KICK_RENEWING_MIST_REDUCTION)
            end
        end
        self:UpdateSecondaryPowerBar()
    end
end

function QUICore:OnUnitPowerPointCharge(_, unit)
    if Helpers.IsSecretValue(unit) then
        unit = nil -- @secret-policy: refresh-without-attribution
    end
    if unit and unit ~= "player" then return end
    if GetSecondaryResource() == Enum.PowerType.ComboPoints then
        self:UpdateSecondaryPowerBar()
    end
end

local oldRefreshAll = QUICore.RefreshAll
function QUICore:RefreshAll()
    if oldRefreshAll then
        oldRefreshAll(self)
    end

    self:UpdatePowerBar()
    self:UpdateSecondaryPowerBar()
end

function QUICore:OnRunePowerUpdate()
    if GetSecondaryResource() ~= Enum.PowerType.Runes then return end
    RequestBarUpdates(false, true, false, Enum.PowerType.Runes)
end

local function InitializeResourceBars(self)
    if self._resourceBarsInitialized then
        return
    end

    self._resourceBarsInitialized = true

    self:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED", "OnSpecChanged")
    self:RegisterEvent("UPDATE_SHAPESHIFT_FORM", "OnShapeshiftChanged")
    self:RegisterEvent("PLAYER_ENTERING_WORLD", function()
        EnsureDemonHunterSoulBar()
        self:OnUnitPower()
        ScheduleSwapBootstrap()
    end)

    self:RegisterMessage("QUI_FRAME_ANCHOR_CHANGED", function(_, changedKey)
        if changedKey == "secondaryPower" or changedKey == "primaryPower" then
            RecaptureNaturalSlotsForSwap()
        end
    end)

    local powerEventFrame = CreateFrame("Frame")
    powerEventFrame:RegisterUnitEvent("UNIT_POWER_FREQUENT", "player")
    powerEventFrame:RegisterUnitEvent("UNIT_POWER_UPDATE", "player")
    powerEventFrame:RegisterUnitEvent("UNIT_MAXPOWER", "player")
    powerEventFrame:RegisterUnitEvent("UNIT_AURA", "player")
    powerEventFrame:RegisterEvent("UNIT_POWER_POINT_CHARGE")
    powerEventFrame:RegisterEvent("SPELL_UPDATE_CHARGES")
    powerEventFrame:RegisterEvent("SPELL_UPDATE_COOLDOWN")
    powerEventFrame:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
    powerEventFrame:RegisterEvent("RUNE_POWER_UPDATE")
    powerEventFrame:SetScript("OnEvent", function(_, event, unit, ...)
        if event == "RUNE_POWER_UPDATE" then
            self:OnRunePowerUpdate(event, unit, ...) -- @secret-safe: callee signature is `()` — the always-secret RUNE_POWER_UPDATE payload (SecretPayloads) is dropped at the call boundary; rune state re-reads via GetRuneCooldown
        elseif event == "UNIT_AURA" then
            self:OnUnitAura(event, unit, ...) -- @secret-safe: callee ignores the unit arg entirely (signature `_, _, updateInfo`) and probes updateInfo unconditionally at entry before any truth-test
        elseif event == "UNIT_POWER_POINT_CHARGE" then
            self:OnUnitPowerPointCharge(event, unit, ...) -- @secret-safe: callee probes the payload unit at entry (IsSecretValue) before its truth-test/compare; secret unit degrades to refresh-without-attribution
        elseif event == "SPELL_UPDATE_CHARGES" or event == "SPELL_UPDATE_COOLDOWN" then
            self:OnSpellChargeUpdate(event)
        elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
            local _, spellID = ...
            if not IsSecretSpellcastPayload(spellID) then
                local shouldUpdate = RUSHING_WIND_KICK_SPELL_IDS[spellID]
                if not shouldUpdate then
                    for _, renewingMistSpellID in ipairs(RENEWING_MIST_SPELL_IDS) do
                        if spellID == renewingMistSpellID then
                            shouldUpdate = true
                            break
                        end
                    end
                end
                if shouldUpdate then
                    self:OnSpellChargeUpdate(event, spellID)
                end
            end
        else
            self:OnUnitPower(event, unit, ...) -- @secret-safe: callee probes the powerType payload at entry (IsSecretValue) before RoutePowerEvent's == compares; a secret token degrades to the token-less full-refresh path
        end
    end)

    self:RegisterEvent("PLAYER_REGEN_DISABLED", "OnUnitPower")
    self:RegisterEvent("PLAYER_REGEN_ENABLED", "OnUnitPower")

    self:RegisterEvent("PLAYER_TARGET_CHANGED", "OnUnitPower")

    self:RegisterEvent("PLAYER_MOUNT_DISPLAY_CHANGED", "OnShapeshiftChanged")

    EnsureDemonHunterSoulBar()

    self:UpdatePowerBar()
    self:UpdateSecondaryPowerBar()

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

end

function QUICore:OnSpecChanged()
    EnsureDemonHunterSoulBar()

    self:UpdatePowerBar()
    self:UpdateSecondaryPowerBar()

    if _G.QUI_UpdateAnchoredFrames then
        _G.QUI_UpdateAnchoredFrames()
    end
end

function QUICore:OnShapeshiftChanged()
    self:UpdatePowerBar()
    self:UpdateSecondaryPowerBar()

    if _G.QUI_UpdateAnchoredFrames then
        _G.QUI_UpdateAnchoredFrames()
    end
end
if QUICore and QUICore.RegisterPostEnable then
    QUICore:RegisterPostEnable(function(core)
        InitializeResourceBars(core)
    end)
end

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
            label = ns.L["Primary Power"],
            group = ns.L["Resource Bars"],
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
            label = ns.L["Secondary Power"],
            group = ns.L["Resource Bars"],
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

_G.QUI_BuildResourceBarPreview = function(pv, options)
    if ns.QUI_ResourceBarsPreview and ns.QUI_ResourceBarsPreview.Build then
        ns.QUI_ResourceBarsPreview.Build(pv, options)
    end
end

_G.QUI_RefreshResourceBarPreview = function()
    if ns.QUI_ResourceBarsPreview and ns.QUI_ResourceBarsPreview.Refresh then
        ns.QUI_ResourceBarsPreview.Refresh()
    end
end

local function RecolorPowerBarBorder(bar, r, g, b, a)
    local border = bar and bar.Border
    if border and border.SetBackdropBorderColor then
        border:SetBackdropBorderColor(r, g, b, a)
    end
end

function QUICore:RefreshPowerBarSkinColors()
    if not (Helpers and Helpers.GetSkinBorderColor) then return end
    local profile = self.db and self.db.profile
    local pCfg = profile and profile.powerBar
    local sCfg = profile and profile.secondaryPowerBar
    local pr, pg, pb, pa = Helpers.GetSkinBorderColor(pCfg, "")
    local sr, sg, sb, sa = Helpers.GetSkinBorderColor(sCfg, "")
    RecolorPowerBarBorder(self.powerBar, pr, pg, pb, pa)
    RecolorPowerBarBorder(self.secondaryPowerBar, sr, sg, sb, sa)
end

if Helpers and Helpers.BorderRegistry then
    local function refreshBorders()
        if QUICore.RefreshPowerBarSkinColors then
            QUICore:RefreshPowerBarSkinColors()
        end
    end

    Helpers.BorderRegistry.Register({
        key      = "resourceBarPrimary",
        label    = "Primary",
        category = "Resource Bars",
        prefix   = "",
        db       = function(p) return p and p.powerBar end,
        refresh  = refreshBorders,
        legacy   = { defaultSource = "inherit" },
    })

    Helpers.BorderRegistry.Register({
        key      = "resourceBarSecondary",
        label    = "Secondary",
        category = "Resource Bars",
        prefix   = "",
        db       = function(p) return p and p.secondaryPowerBar end,
        refresh  = refreshBorders,
        legacy   = { defaultSource = "inherit" },
    })
end

if ns.Registry then
    ns.Registry:Register("resourceBarsSkin", {
        refresh = function()
            if QUICore.RefreshPowerBarSkinColors then
                QUICore:RefreshPowerBarSkinColors()
            end
        end,
        priority = 50,
        group = "skinning",
        importCategories = { "skinning", "theme" },
    })
end
