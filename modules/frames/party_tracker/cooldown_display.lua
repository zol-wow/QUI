--[[
    QUI Party Tracker — Party Cooldown Display
    Shows defensive/offensive cooldown icons on party frames.
    Two modes:
      - Static: Always show all tracked abilities (dimmed when ready, bright + swirl when on CD)
      - Active: Only show abilities currently on cooldown

    Detection: UNIT_SPELLCAST_SUCCEEDED with pcall table lookup for secret spellIDs.
    Same approach as kick_timer — no aura scanning or evidence system needed.
]]

local ADDON_NAME, ns = ...
local Helpers = ns.Helpers
local GetDB = Helpers.CreateDBGetter("quiGroupFrames")

local CreateFrame = CreateFrame
local UnitExists = UnitExists
local UnitIsDeadOrGhost = UnitIsDeadOrGhost
local UnitClass = UnitClass
local UnitIsUnit = UnitIsUnit
local UnitIsEnemy = UnitIsEnemy
local C_Spell = C_Spell
local C_Timer = C_Timer
local GetTime = GetTime
local pcall = pcall
local pairs = pairs
local ipairs = ipairs
local wipe = wipe
local IsInRaid = IsInRaid
local GetNumGroupMembers = GetNumGroupMembers
local IsPlayerSpell = IsPlayerSpell

local CooldownDisplay = {}
ns.PartyTracker_CooldownDisplay = CooldownDisplay

local MAX_ICONS = 10
local GF = nil
local SpecCache = nil
local Rules = nil

---------------------------------------------------------------------------
-- SPELL TEXTURE CACHE
---------------------------------------------------------------------------
local textureCache = {}

local function GetSpellTexture(spellId)
    if not spellId then return nil end
    if textureCache[spellId] then return textureCache[spellId] end
    local ok, tex = pcall(C_Spell.GetSpellTexture, spellId)
    if ok and tex then
        textureCache[spellId] = tex
        return tex
    end
    return nil
end

---------------------------------------------------------------------------
-- ICON CREATION
---------------------------------------------------------------------------

local function GetPixelSize(frame)
    local QUICore = ns.Addon
    return QUICore and QUICore.GetPixelSize and QUICore:GetPixelSize(frame) or 1
end

local function CreateIcon(parent, px)
    local icon = CreateFrame("Frame", nil, parent)
    icon:SetSize(18, 18)
    icon:SetFrameStrata("HIGH")
    icon:SetFrameLevel(100)

    local border = icon:CreateTexture(nil, "BACKGROUND")
    border:SetAllPoints()
    border:SetTexture("Interface\\Buttons\\WHITE8x8")
    border:SetVertexColor(0, 0, 0, 1)

    local tex = icon:CreateTexture(nil, "ARTWORK")
    tex:SetPoint("TOPLEFT", px, -px)
    tex:SetPoint("BOTTOMRIGHT", -px, px)
    tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    icon.icon = tex

    local cd = CreateFrame("Cooldown", nil, icon, "CooldownFrameTemplate")
    cd:SetPoint("TOPLEFT", px, -px)
    cd:SetPoint("BOTTOMRIGHT", -px, px)
    cd:SetDrawEdge(false)
    cd:SetDrawSwipe(true)
    cd:SetReverse(true)
    cd:SetHideCountdownNumbers(false)
    icon.cooldown = cd

    if icon.SetMouseClickEnabled then icon:SetMouseClickEnabled(false) end
    icon:EnableMouse(false)
    icon:Hide()
    return icon
end

---------------------------------------------------------------------------
-- GROWTH OFFSETS
---------------------------------------------------------------------------
local GROWTH = {
    LEFT  = function(size, spacing) return -(size + spacing), 0 end,
    RIGHT = function(size, spacing) return (size + spacing), 0 end,
    UP    = function(size, spacing) return 0, (size + spacing) end,
    DOWN  = function(size, spacing) return 0, -(size + spacing) end,
}

---------------------------------------------------------------------------
-- SETTINGS
---------------------------------------------------------------------------

local function GetSettings(isRaid)
    local db = GetDB()
    if not db then return nil end
    local vdb = isRaid and db.raid or db.party
    return vdb and vdb.partyTracker and vdb.partyTracker.partyCooldowns
end

---------------------------------------------------------------------------
-- LAZY ICON CREATION
---------------------------------------------------------------------------

local function EnsureIcons(frame)
    if frame._partyCDIcons then return frame._partyCDIcons end
    local px = frame._partyTrackerPx or GetPixelSize(frame)
    local icons = {}
    for i = 1, MAX_ICONS do
        icons[i] = CreateIcon(frame, px)
    end
    frame._partyCDIcons = icons
    return icons
end

---------------------------------------------------------------------------
-- ACTIVE COOLDOWNS STATE
-- Simple per-unit table: { [spellId] = { startTime, cooldown, timer } }
---------------------------------------------------------------------------
local activeCooldowns = {}  -- unit → { [spellId] = cdData }

---------------------------------------------------------------------------
-- SPELL LOOKUP (built from Rules at init)
-- spellId → { cooldown = number, isOffensive = bool }
---------------------------------------------------------------------------
local spellCooldownLookup = {}

local function BuildSpellCooldownLookup()
    Rules = Rules or ns.PartyTracker_Rules
    if not Rules then return end
    wipe(spellCooldownLookup)
    local function AddFromRules(ruleList)
        if not ruleList then return end
        for _, rule in ipairs(ruleList) do
            if rule.SpellId and rule.Cooldown and not spellCooldownLookup[rule.SpellId] then
                spellCooldownLookup[rule.SpellId] = {
                    cooldown = rule.Cooldown,
                    isOffensive = rule.Offensive or (Rules.OffensiveSpellIds and Rules.OffensiveSpellIds[rule.SpellId]),
                }
            end
        end
    end
    for _, ruleList in pairs(Rules.BySpec) do AddFromRules(ruleList) end
    for _, ruleList in pairs(Rules.ByClass) do AddFromRules(ruleList) end
end

---------------------------------------------------------------------------
-- CHECK IF UNIT HAS SPELL
---------------------------------------------------------------------------

local openRaidLib = nil

local function UnitHasSpell(unit, spellId)
    if UnitIsUnit(unit, "player") then
        local ok, known = pcall(IsPlayerSpell, spellId)
        if ok then return known end
        return true
    end

    if not openRaidLib then
        openRaidLib = LibStub and LibStub:GetLibrary("LibOpenRaid-1.0", true)
    end
    if openRaidLib then
        local unitCDs = openRaidLib.GetUnitCooldowns(unit)
        if unitCDs and next(unitCDs) then
            return unitCDs[spellId] ~= nil
        end
    end

    return true
end

---------------------------------------------------------------------------
-- STATIC ABILITY LIST (from Rules for unit's spec/class)
---------------------------------------------------------------------------

local function GetStaticAbilities(unit, filterMode)
    Rules = Rules or ns.PartyTracker_Rules
    if not Rules then return {} end

    local abilities = {}
    local seen = {}

    SpecCache = SpecCache or ns.PartyTracker_SpecCache
    local specId = SpecCache and SpecCache.GetSpec(unit)
    local _, classToken = UnitClass(unit)

    local function CollectFromRules(ruleList)
        if not ruleList then return end
        for _, rule in ipairs(ruleList) do
            if rule.SpellId and not seen[rule.SpellId] then
                if UnitHasSpell(unit, rule.SpellId) then
                    local isOffensive = rule.Offensive or (Rules.OffensiveSpellIds and Rules.OffensiveSpellIds[rule.SpellId])
                    local include = false
                    if filterMode == "all" then
                        include = true
                    elseif filterMode == "defensive" then
                        include = not isOffensive
                    elseif filterMode == "offensive" then
                        include = isOffensive
                    end
                    if include then
                        seen[rule.SpellId] = true
                        abilities[#abilities + 1] = {
                            spellId = rule.SpellId,
                            isOffensive = isOffensive,
                        }
                    end
                end
            end
        end
    end

    if specId and Rules.BySpec[specId] then
        CollectFromRules(Rules.BySpec[specId])
    end
    if classToken and Rules.ByClass[classToken] then
        CollectFromRules(Rules.ByClass[classToken])
    end

    return abilities
end

---------------------------------------------------------------------------
-- RESOLVE UNIT → FRAME (handles "player" → party/raid token)
---------------------------------------------------------------------------

local function GetFrameForUnit(unit)
    GF = GF or ns.QUI_GroupFrames
    if not GF or not GF.unitFrameMap then return nil end
    local frame = GF.unitFrameMap[unit]
    if not frame and unit == "player" then
        for token, f in pairs(GF.unitFrameMap) do
            if UnitIsUnit(token, "player") then
                return f
            end
        end
    end
    return frame
end

---------------------------------------------------------------------------
-- UPDATE DISPLAY
---------------------------------------------------------------------------

function CooldownDisplay.UpdateFrame(frame)
    if not frame then return end

    local isRaid = frame._isRaid
    local settings = GetSettings(isRaid)
    local unit = frame.unit

    if not settings or not settings.enabled or not unit or not UnitExists(unit) or UnitIsDeadOrGhost(unit) then
        if frame._partyCDIcons then
            for _, icon in ipairs(frame._partyCDIcons) do icon:Hide() end
        end
        return
    end

    local icons = EnsureIcons(frame)

    local maxIcons = settings.maxIcons or 6
    local displayMode = settings.displayMode or "static"
    local filterMode = settings.filter or "all"
    local iconSize = settings.iconSize or 18
    local anchor = settings.anchor or "BOTTOM"
    local growDir = settings.growDirection or "RIGHT"
    local spacing = settings.spacing or 2
    local offsetX = settings.offsetX or 0
    local offsetY = settings.offsetY or -4
    local reverseSwipe = settings.reverseSwipe ~= false

    local growFn = GROWTH[growDir] or GROWTH.RIGHT
    local stepX, stepY = growFn(iconSize, spacing)

    local unitCDs = activeCooldowns[unit] or {}
    -- Also check "player" CDs if this frame shows the player
    if unit ~= "player" and UnitIsUnit(unit, "player") then
        local playerCDs = activeCooldowns["player"]
        if playerCDs then
            for k, v in pairs(playerCDs) do
                if not unitCDs[k] then
                    if not activeCooldowns[unit] then activeCooldowns[unit] = {} end
                    unitCDs = activeCooldowns[unit]
                    unitCDs[k] = v
                end
            end
        end
    end

    local idx = 0

    if displayMode == "static" then
        local abilities = GetStaticAbilities(unit, filterMode)

        for _, ability in ipairs(abilities) do
            idx = idx + 1
            if idx > maxIcons or idx > MAX_ICONS then break end

            local icon = icons[idx]
            icon:SetSize(iconSize, iconSize)
            icon:SetFrameStrata("HIGH")
            icon:SetFrameLevel(100)
            icon:ClearAllPoints()
            icon:SetPoint(anchor, frame, anchor, offsetX + (idx - 1) * stepX, offsetY + (idx - 1) * stepY)

            local StyleCooldownText = ns.PartyTracker_StyleCooldownText
            if StyleCooldownText then StyleCooldownText(icon.cooldown, iconSize * 0.55) end

            local texture = GetSpellTexture(ability.spellId)
            if texture then
                pcall(icon.icon.SetTexture, icon.icon, texture)
            end

            local cdData = unitCDs[ability.spellId]
            local cd = icon.cooldown
            if cdData then
                icon:SetAlpha(1.0)
                if cd then
                    pcall(cd.SetReverse, cd, reverseSwipe)
                    -- Use stored DurationObject if available (player, secret-safe)
                    if cdData.durObj and cd.SetCooldownFromDurationObject then
                        pcall(cd.SetCooldownFromDurationObject, cd, cdData.durObj)
                    elseif cdData.startTime and cdData.cooldown then
                        pcall(cd.SetCooldown, cd, cdData.startTime, cdData.cooldown)
                    end
                end
            else
                icon:SetAlpha(1.0)
                if cd and cd.Clear then cd:Clear() end
            end

            icon:Show()
        end

    elseif displayMode == "active" then
        for spellId, cdData in pairs(unitCDs) do
            local isOffensive = Rules and Rules.OffensiveSpellIds and Rules.OffensiveSpellIds[spellId]
            local include = false
            if filterMode == "all" then include = true
            elseif filterMode == "defensive" then include = not isOffensive
            elseif filterMode == "offensive" then include = isOffensive
            end

            if include then
                idx = idx + 1
                if idx > maxIcons or idx > MAX_ICONS then break end

                local icon = icons[idx]
                icon:SetSize(iconSize, iconSize)
                icon:SetFrameStrata("HIGH")
                icon:SetFrameLevel(100)
                icon:ClearAllPoints()
                icon:SetPoint(anchor, frame, anchor, offsetX + (idx - 1) * stepX, offsetY + (idx - 1) * stepY)

                local StyleCooldownText = ns.PartyTracker_StyleCooldownText
                if StyleCooldownText then StyleCooldownText(icon.cooldown, iconSize * 0.55) end

                local texture = GetSpellTexture(spellId)
                if texture then
                    pcall(icon.icon.SetTexture, icon.icon, texture)
                end

                icon:SetAlpha(1.0)
                local cd = icon.cooldown
                if cd then
                    pcall(cd.SetReverse, cd, reverseSwipe)
                    if cdData.durObj and cd.SetCooldownFromDurationObject then
                        pcall(cd.SetCooldownFromDurationObject, cd, cdData.durObj)
                    elseif cdData.startTime and cdData.cooldown then
                        pcall(cd.SetCooldown, cd, cdData.startTime, cdData.cooldown)
                    end
                end

                icon:Show()
            end
        end
    end

    for i = idx + 1, MAX_ICONS do
        icons[i]:Hide()
    end
end

---------------------------------------------------------------------------
-- REFRESH ALL
---------------------------------------------------------------------------

function CooldownDisplay.RefreshAll()
    GF = GF or ns.QUI_GroupFrames
    if not GF then return end
    if GF.unitFrameMap then
        for _, frame in pairs(GF.unitFrameMap) do
            CooldownDisplay.UpdateFrame(frame)
        end
    end
end

---------------------------------------------------------------------------
-- CAST-BASED DETECTION (UNIT_SPELLCAST_SUCCEEDED)
-- Don't read the secret spellID at all. Use the event as a trigger:
-- "this unit cast something." Then check all their tracked spells via
-- C_Spell.GetSpellCooldownDuration (C-side, handles secrets natively).
-- If a tracked spell now has a DurationObject, it just went on CD.
-- Works for the player. Party members use aura fallback below.
---------------------------------------------------------------------------

local function OnSpellcastSucceeded(unit, castGUID, spellID)
    if UnitIsEnemy("player", unit) then return end

    -- For the player: scan all tracked spells via C-side API
    if UnitIsUnit(unit, "player") and C_Spell.GetSpellCooldownDuration then
        local abilities = GetStaticAbilities(unit, "all")
        if not activeCooldowns[unit] then activeCooldowns[unit] = {} end
        local unitCDs = activeCooldowns[unit]

        for _, ability in ipairs(abilities) do
            local sid = ability.spellId
            if not unitCDs[sid] then
                -- Check if this spell just went on CD via DurationObject
                local ok, durObj = pcall(C_Spell.GetSpellCooldownDuration, sid)
                if ok and durObj then
                    local info = spellCooldownLookup[sid]
                    local baseDuration = info and info.cooldown or 60

                    unitCDs[sid] = {
                        startTime = GetTime(),
                        cooldown = baseDuration,
                        unit = unit,
                        spellId = sid,
                        durObj = durObj,  -- store for display
                        timer = C_Timer.NewTimer(baseDuration, function()
                            if unitCDs[sid] then
                                unitCDs[sid] = nil
                            end
                            local frame = GetFrameForUnit(unit)
                            if frame then CooldownDisplay.UpdateFrame(frame) end
                        end),
                    }
                end
            end
        end

        local frame = GetFrameForUnit(unit)
        if frame then CooldownDisplay.UpdateFrame(frame) end
        return
    end

    -- For party members: try pcall spellID lookup as best-effort
    -- (works when spellID is not secret; aura fallback handles combat)
    if not spellID then return end
    local ok, info = pcall(function() return spellCooldownLookup[spellID] end)
    if not ok or not info then return end

    if not activeCooldowns[unit] then activeCooldowns[unit] = {} end
    local unitCDs = activeCooldowns[unit]

    if unitCDs[spellID] and unitCDs[spellID].timer then
        unitCDs[spellID].timer:Cancel()
    end

    local startTime = GetTime()
    local cooldown = info.cooldown

    unitCDs[spellID] = {
        startTime = startTime,
        cooldown = cooldown,
        unit = unit,
        spellId = spellID,
        timer = C_Timer.NewTimer(cooldown, function()
            if unitCDs[spellID] then
                unitCDs[spellID] = nil
            end
            local frame = GetFrameForUnit(unit)
            if frame then CooldownDisplay.UpdateFrame(frame) end
        end),
    }

    local frame = GetFrameForUnit(unit)
    if frame then CooldownDisplay.UpdateFrame(frame) end
end

---------------------------------------------------------------------------
-- INIT + EVENT REGISTRATION
---------------------------------------------------------------------------

C_Timer.After(0, function()
    Rules = ns.PartyTracker_Rules
    SpecCache = ns.PartyTracker_SpecCache
    BuildSpellCooldownLookup()
    CooldownDisplay.RefreshAll()
end)

C_Timer.After(0, function()
    local eventFrame = CreateFrame("Frame")
    eventFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
    eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")

    local function RegisterUnits()
        eventFrame:UnregisterEvent("UNIT_SPELLCAST_SUCCEEDED")
        local units = { "player" }
        local numGroup = GetNumGroupMembers() or 0
        if numGroup > 0 then
            local prefix = IsInRaid() and "raid" or "party"
            local max = IsInRaid() and numGroup or (numGroup - 1)
            for i = 1, max do
                units[#units + 1] = prefix .. i
            end
        end
        if #units > 0 then
            eventFrame:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", unpack(units))
        end
    end

    eventFrame:SetScript("OnEvent", function(_, event, arg1, arg2, arg3)
        if event == "UNIT_SPELLCAST_SUCCEEDED" then
            OnSpellcastSucceeded(arg1, arg2, arg3)
        else
            -- Roster change: cleanup stale units + re-register
            for u in pairs(activeCooldowns) do
                if not UnitExists(u) then
                    for _, cdData in pairs(activeCooldowns[u]) do
                        if cdData.timer then cdData.timer:Cancel() end
                    end
                    activeCooldowns[u] = nil
                end
            end
            RegisterUnits()
            CooldownDisplay.RefreshAll()
        end
    end)

    RegisterUnits()
end)

---------------------------------------------------------------------------
-- AURA-BASED FALLBACK (combat detection for party members)
-- When UNIT_SPELLCAST_SUCCEEDED has secret spellIDs, aura detection
-- catches defensives/offensives that create buffs. On UNIT_AURA, pcall
-- read spellId from each added aura and match against our rules.
---------------------------------------------------------------------------

C_Timer.After(0, function()
    if not ns.AuraEvents then return end
    local C_UnitAuras = C_UnitAuras

    ns.AuraEvents:Subscribe("group", function(unit, updateInfo)
        if not updateInfo or updateInfo.isFullUpdate then return end
        if not updateInfo.addedAuras then return end

        Rules = Rules or ns.PartyTracker_Rules
        if not Rules then return end

        for _, auraData in ipairs(updateInfo.addedAuras) do
            -- pcall read spellId — may be secret
            local ok, spellId = pcall(function() return auraData.spellId end)
            if ok and spellId then
                -- pcall the lookup — spellId may still be secret as table key
                local lookupOk, info = pcall(function() return spellCooldownLookup[spellId] end)
                if lookupOk and info then
                    -- Found a tracked spell as an aura — start CD if not already active
                    if not activeCooldowns[unit] then activeCooldowns[unit] = {} end
                    local unitCDs = activeCooldowns[unit]
                    if not unitCDs[spellId] then
                        local startTime = GetTime()
                        local cooldown = info.cooldown

                        unitCDs[spellId] = {
                            startTime = startTime,
                            cooldown = cooldown,
                            unit = unit,
                            spellId = spellId,
                            timer = C_Timer.NewTimer(cooldown, function()
                                if unitCDs[spellId] then
                                    unitCDs[spellId] = nil
                                end
                                local frame = GetFrameForUnit(unit)
                                if frame then CooldownDisplay.UpdateFrame(frame) end
                            end),
                        }

                        local frame = GetFrameForUnit(unit)
                        if frame then CooldownDisplay.UpdateFrame(frame) end
                    end
                end
            end
        end
    end)
end)
