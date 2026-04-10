--[[
    QUI Party Tracker — Party Cooldown Display
    Shows defensive/offensive cooldown icons on party frames.
    Two modes:
      - Static: Always show all tracked abilities (dimmed when ready, bright + swirl when on CD)
      - Active: Only show abilities currently on cooldown

    Detection layers:
      1. Player: C_Spell.GetSpellCooldownDuration (DurationObject, secret-safe)
      2. Party out of combat: UNIT_SPELLCAST_SUCCEEDED pcall lookup (spellID is plain)
      3. Party in combat: UNIT_AURA classification via C_UnitAuras.IsAuraFilteredOutByInstanceID
         with compound filters (BIG_DEFENSIVE, EXTERNAL_DEFENSIVE, IMPORTANT).
         C-side functions handle secret values natively. Brain matches rules by
         aura type + evidence + duration.
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

local C_UnitAuras = C_UnitAuras

local CooldownDisplay = {}
ns.PartyTracker_CooldownDisplay = CooldownDisplay

local MAX_ICONS = 10
local GF = nil
local SpecCache = nil
local Rules = nil
local Brain = nil
local Observer = nil

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

local IsActive = ns.PartyTracker_IsActive
local IsPartyUnit = ns.PartyTracker_IsPartyUnit

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

    local settings = GetSettings(IsInRaid())
    local disabledSpells = settings and settings.disabledSpells or {}

    local function CollectFromRules(ruleList)
        if not ruleList then return end
        for _, rule in ipairs(ruleList) do
            if rule.SpellId and not seen[rule.SpellId] and not disabledSpells[rule.SpellId] then
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
    -- Only fall back to class rules when spec is unknown
    if not specId and classToken and Rules.ByClass[classToken] then
        CollectFromRules(Rules.ByClass[classToken])
    end

    return abilities
end

---------------------------------------------------------------------------
-- RESOLVE UNIT → FRAME (handles "player" → party/raid token)
---------------------------------------------------------------------------

local GetFrameForUnit = ns.PartyTracker_GetFrameForUnit

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
                local dimAlpha = settings.dimReadyAlpha or 0.4
                icon:SetAlpha(dimAlpha)
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

-- Cached list of the player's tracked spell IDs (avoids rebuilding via
-- GetStaticAbilities + UnitHasSpell/LibOpenRaid on every single cast).
-- Invalidated on spec change and roster update.
local playerTrackedSpellIds = nil

local function InvalidatePlayerSpellCache()
    playerTrackedSpellIds = nil
end

local function EnsurePlayerSpellCache()
    if playerTrackedSpellIds then return playerTrackedSpellIds end
    local abilities = GetStaticAbilities("player", "all")
    playerTrackedSpellIds = {}
    for _, ability in ipairs(abilities) do
        playerTrackedSpellIds[#playerTrackedSpellIds + 1] = ability.spellId
    end
    return playerTrackedSpellIds
end

local function OnSpellcastSucceeded(unit, castGUID, spellID)
    if not IsActive() then return end
    if unit ~= "player" and not IsPartyUnit(unit) then return end
    if UnitIsEnemy("player", unit) then return end

    -- For the player: scan cached tracked spells via C-side API
    if UnitIsUnit(unit, "player") and C_Spell.GetSpellCooldownDuration then
        local trackedIds = EnsurePlayerSpellCache()
        if not activeCooldowns[unit] then activeCooldowns[unit] = {} end
        local unitCDs = activeCooldowns[unit]

        for _, sid in ipairs(trackedIds) do
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

---------------------------------------------------------------------------
-- AURA CLASSIFICATION (MiniCC-style)
-- Uses C_UnitAuras.IsAuraFilteredOutByInstanceID with compound filters.
-- These are C-side functions that handle secret values natively.
---------------------------------------------------------------------------

local trackedAuras = {}  -- unit → { [instanceID] = { types, startTime, castSnapshot } }
local pendingReconciliation = {}  -- unit → { [signature] = { tracked1, tracked2, ... } }

local function AuraTypesSignature(types)
    if types.BigDefensive then return "BD" end
    if types.ExternalDefensive then return "ED" end
    if types.Important then return "IMP" end
    return "UNK"
end

local function ClassifyAura(unit, instanceID)
    -- Priority: BIG_DEFENSIVE > EXTERNAL_DEFENSIVE > IMPORTANT
    -- Returns the first matching type (prevents double-classification)
    local ok1, filtered1 = pcall(C_UnitAuras.IsAuraFilteredOutByInstanceID, unit, instanceID, "HELPFUL|BIG_DEFENSIVE")
    if ok1 and filtered1 == false then
        return { BigDefensive = true }
    end

    local ok2, filtered2 = pcall(C_UnitAuras.IsAuraFilteredOutByInstanceID, unit, instanceID, "HELPFUL|EXTERNAL_DEFENSIVE")
    if ok2 and filtered2 == false then
        return { ExternalDefensive = true }
    end

    local ok3, filtered3 = pcall(C_UnitAuras.IsAuraFilteredOutByInstanceID, unit, instanceID, "HELPFUL|IMPORTANT")
    if ok3 and filtered3 == false then
        return { Important = true }
    end

    return nil
end

---------------------------------------------------------------------------
-- BRAIN CALLBACK — fires when Brain detects/expires a cooldown
---------------------------------------------------------------------------

local function OnBrainCooldown(unit, spellId, startTime, cooldown, isOffensive)
    if not spellId then return end

    if not startTime then
        -- Brain says cooldown expired — clean up display entry
        if activeCooldowns[unit] then
            local entry = activeCooldowns[unit][spellId]
            if entry and entry.brainManaged then
                if entry.timer then entry.timer:Cancel() end
                activeCooldowns[unit][spellId] = nil
            end
        end
        local frame = GetFrameForUnit(unit)
        if frame then CooldownDisplay.UpdateFrame(frame) end
        return
    end

    if not activeCooldowns[unit] then activeCooldowns[unit] = {} end
    local unitCDs = activeCooldowns[unit]

    -- Cancel existing timer (Brain refinement replaces earlier detection)
    if unitCDs[spellId] and unitCDs[spellId].timer then
        unitCDs[spellId].timer:Cancel()
    end

    local remaining = cooldown - (GetTime() - startTime)
    if remaining <= 0 then return end

    unitCDs[spellId] = {
        startTime = startTime,
        cooldown = cooldown,
        unit = unit,
        spellId = spellId,
        brainManaged = true,
        timer = C_Timer.NewTimer(remaining, function()
            if unitCDs[spellId] then unitCDs[spellId] = nil end
            local frame = GetFrameForUnit(unit)
            if frame then CooldownDisplay.UpdateFrame(frame) end
        end),
    }

    local frame = GetFrameForUnit(unit)
    if frame then CooldownDisplay.UpdateFrame(frame) end
end

---------------------------------------------------------------------------
-- OBSERVER PARTY UNIT MANAGEMENT
---------------------------------------------------------------------------

local function WatchPartyUnits()
    Observer = Observer or ns.PartyTracker_Observer
    if not Observer then return end

    -- Clear and re-watch all party units (+ player for external defensive evidence)
    Observer.ClearAll()
    Observer.Watch("player")
    local numGroup = GetNumGroupMembers() or 0
    if numGroup > 0 then
        local prefix = IsInRaid() and "raid" or "party"
        local max = IsInRaid() and numGroup or (numGroup - 1)
        for i = 1, max do
            local unit = prefix .. i
            if UnitExists(unit) then
                Observer.Watch(unit)
            end
        end
    end
end

C_Timer.After(0, function()
    Rules = ns.PartyTracker_Rules
    SpecCache = ns.PartyTracker_SpecCache
    Brain = ns.PartyTracker_Brain
    Observer = ns.PartyTracker_Observer
    BuildSpellCooldownLookup()

    -- Initialize Brain with our callback
    if Brain then
        Brain.Init(OnBrainCooldown)
    end

    -- Start watching party units for evidence
    WatchPartyUnits()

    CooldownDisplay.RefreshAll()
end)

C_Timer.After(0, function()
    local eventFrame = CreateFrame("Frame")
    eventFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
    eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    eventFrame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")

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
            -- Roster/spec change: invalidate player spell cache + cleanup stale units
            InvalidatePlayerSpellCache()
            for u in pairs(activeCooldowns) do
                if not UnitExists(u) then
                    for _, cdData in pairs(activeCooldowns[u]) do
                        if cdData.timer then cdData.timer:Cancel() end
                    end
                    activeCooldowns[u] = nil
                end
            end
            -- Clear tracked auras for stale units
            for u in pairs(trackedAuras) do
                if not UnitExists(u) then
                    trackedAuras[u] = nil
                end
            end
            -- Re-watch party units for evidence
            WatchPartyUnits()
            RegisterUnits()
            CooldownDisplay.RefreshAll()
        end
    end)

    RegisterUnits()
end)

---------------------------------------------------------------------------
-- AURA-BASED DETECTION (MiniCC-style, primary combat detection)
-- Uses C-side aura classification (BIG_DEFENSIVE, EXTERNAL_DEFENSIVE,
-- IMPORTANT) which handles secret values natively. No spellId lookup needed.
-- On aura appear → classify + immediate Brain match → start CD.
-- On aura removed → measure duration + Brain refined match.
---------------------------------------------------------------------------

C_Timer.After(0, function()
    if not ns.AuraEvents then return end

    ns.AuraEvents:Subscribe("group", function(unit, updateInfo)
        if not updateInfo then return end
        if not IsActive() or not IsPartyUnit(unit) then return end
        Brain = Brain or ns.PartyTracker_Brain
        Observer = Observer or ns.PartyTracker_Observer

        -- Full update: move tracked auras to pending reconciliation by signature.
        -- Subsequent addedAuras will carry new instance IDs that we match by signature
        -- to recover startTime/castSnapshot (prevents losing in-progress tracking).
        if updateInfo.isFullUpdate then
            if trackedAuras[unit] and next(trackedAuras[unit]) then
                local pending = {}
                for _, tracked in pairs(trackedAuras[unit]) do
                    local sig = AuraTypesSignature(tracked.types)
                    if not pending[sig] then pending[sig] = {} end
                    pending[sig][#pending[sig] + 1] = tracked
                end
                pendingReconciliation[unit] = pending
                -- Timeout: discard unreconciled after 0.5s
                C_Timer.After(0.5, function()
                    pendingReconciliation[unit] = nil
                end)
            end
            trackedAuras[unit] = nil
            -- Don't return — full update may include addedAuras in same event
        end

        -- New auras: classify, reconcile or track fresh, snapshot cast times
        if updateInfo.addedAuras then
            for _, auraData in ipairs(updateInfo.addedAuras) do
                local instanceID = auraData.auraInstanceID
                if instanceID then
                    local auraTypes = ClassifyAura(unit, instanceID)
                    if auraTypes then
                        if not trackedAuras[unit] then trackedAuras[unit] = {} end

                        -- Try to reconcile from pending (full update recovery)
                        local startTime = GetTime()
                        local castSnapshot = nil
                        local reconciled = false
                        local pending = pendingReconciliation[unit]
                        if pending then
                            local sig = AuraTypesSignature(auraTypes)
                            if pending[sig] and #pending[sig] > 0 then
                                local old = table.remove(pending[sig], 1)
                                startTime = old.startTime
                                castSnapshot = old.castSnapshot
                                reconciled = true
                            end
                        end

                        -- Snapshot cast times at aura appearance (frozen state for later evaluation)
                        if not castSnapshot and Observer then
                            castSnapshot = Observer.SnapshotCastTimes()
                        end

                        trackedAuras[unit][instanceID] = {
                            types = auraTypes,
                            startTime = startTime,
                            castSnapshot = castSnapshot,
                        }

                        -- Immediate detection (skip for reconciled — already detected)
                        if not reconciled and Brain then
                            Brain.ProcessAuraAppearance(unit, auraTypes, castSnapshot)
                        end
                    end
                end
            end
        end

        -- Removed auras: measure duration, feed to Brain with cast snapshot
        if updateInfo.removedAuraInstanceIDs and trackedAuras[unit] then
            for _, instanceID in ipairs(updateInfo.removedAuraInstanceIDs) do
                local tracked = trackedAuras[unit][instanceID]
                if tracked then
                    local measuredDuration = GetTime() - tracked.startTime
                    trackedAuras[unit][instanceID] = nil

                    if Brain then
                        Brain.ProcessAuraDetection(unit, tracked.types, measuredDuration, tracked.startTime, tracked.castSnapshot)
                    end
                end
            end
        end
    end)
end)
