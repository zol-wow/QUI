-- qui_spellscanner.lua
-- Spell Scanner System for Combat-Safe Buff Detection
--
-- Scans spell/item → buff mappings out of combat
-- Detects active states via UNIT_SPELLCAST_SUCCEEDED and item cooldown starts.
-- Enables accurate tracking of trinkets, potions, and class abilities during combat.

local ADDON_NAME, ns = ...
local QUI = QUI

-- Performance: cache frequently-called globals as locals
local type = type
local pairs = pairs
local pcall = pcall
local tonumber = tonumber
local GetTime = GetTime
local CreateFrame = CreateFrame
local InCombatLockdown = InCombatLockdown
local C_Timer = C_Timer
local string_format = string.format
local WoW_IsSecretValue = issecretvalue

local function ScannerIsSecretValue(value)
    if WoW_IsSecretValue then
        return WoW_IsSecretValue(value)
    end
    return false
end

local function IsCleanNumber(value)
    return not ScannerIsSecretValue(value) and type(value) == "number"
end

local function IsCleanPositiveDuration(duration)
    return IsCleanNumber(duration) and duration > 0
end

local function IsFutureExpiration(expirationTime, now)
    return IsCleanNumber(expirationTime) and expirationTime > now
end

---------------------------------------------------------------------------
-- MODULE STATE
---------------------------------------------------------------------------
local SpellScanner = {}
QUI.SpellScanner = SpellScanner

-- Runtime state: currently active buffs
-- Structure: { [spellID] = { startTime, duration, expirationTime, auraInstanceID, hasAuraInstanceID, auraUnit, source, sourceId } }
SpellScanner.activeBuffs = {}

-- Pending scanning: spells cast in combat that we'll try to scan after
-- Structure: { [spellID] = { timestamp, itemID (optional) } }
SpellScanner.pendingScanning = {}

-- Item use spells registered by CDM entries.
-- Structure: { [useSpellID] = itemID }
SpellScanner.registeredItemUseSpells = {}

-- Recent item use casts waiting for the matching UNIT_AURA addedAuras payload.
-- Structure: list of { spellID, itemID, time }
SpellScanner.pendingItemAuraCasts = {}

-- Recent player helpful aura additions. Used when item cooldown events arrive
-- after UNIT_AURA for trinkets/items that do not produce a useful cast event.
-- Structure: list of { auraInstanceID, hasAuraInstanceID, auraUnit, time }
SpellScanner.recentPlayerAuras = {}

-- Last observed item cooldown state. The item/aura fallback only correlates
-- player auras to item cooldowns that just started, not stale active cooldowns.
-- Structure: { [itemID] = { active, startTime, duration } }
SpellScanner.itemCooldownStates = {}

-- Scan mode toggle (explicit /quiscan)
SpellScanner.scanMode = false

-- Auto-scan: try to scan unknown spells when cast out of combat (off by default)
-- Stored in database for persistence
SpellScanner.autoScan = false

-- Callback for UI refresh when spell is scanned (set by options panel)
SpellScanner.onScanCallback = nil

-- Forward declarations
local EnsureCleanupTicker
local ITEM_AURA_CORRELATION_WINDOW = 0.1
local ITEM_COOLDOWN_AURA_WINDOW = 0.1

local function NotifyScannerChanged(spellID, itemID)
    local scheduler = ns and ns.CDMScheduler
    if scheduler and scheduler.Publish then
        scheduler.Publish("CDM:COOLDOWN_CHANGED", spellID, nil, itemID and "scanner_item" or "scanner_spell")
    end
end

local function PrunePendingItemAuraCasts(now)
    local cutoff = now - ITEM_AURA_CORRELATION_WINDOW
    while SpellScanner.pendingItemAuraCasts[1]
       and SpellScanner.pendingItemAuraCasts[1].time < cutoff do
        table.remove(SpellScanner.pendingItemAuraCasts, 1)
    end
end

local function PruneRecentPlayerAuras(now)
    local cutoff = now - ITEM_COOLDOWN_AURA_WINDOW
    while SpellScanner.recentPlayerAuras[1]
       and SpellScanner.recentPlayerAuras[1].time < cutoff do
        table.remove(SpellScanner.recentPlayerAuras, 1)
    end
end

local function RecordRecentPlayerAura(unit, auraInstanceID, hasAuraInstanceID)
    if hasAuraInstanceID ~= true then return end
    local now = GetTime()
    PruneRecentPlayerAuras(now)
    SpellScanner.recentPlayerAuras[#SpellScanner.recentPlayerAuras + 1] = {
        auraInstanceID = auraInstanceID,
        hasAuraInstanceID = true,
        auraUnit = unit or "player",
        time = now,
    }
end

local function RecordPendingItemAuraCast(spellID, itemID)
    if not spellID or not itemID then return end
    local now = GetTime()
    PrunePendingItemAuraCasts(now)
    SpellScanner.pendingItemAuraCasts[#SpellScanner.pendingItemAuraCasts + 1] = {
        spellID = spellID,
        itemID = itemID,
        time = now,
    }
end

local function GetRawAuraInstanceID(auraData)
    if not auraData then return nil, false end
    local ok, instID = pcall(function() return auraData.auraInstanceID end)
    if not ok then return nil, false end
    if ScannerIsSecretValue(instID) then return instID, true end
    if instID ~= nil then return instID, true end
    return nil, false
end

local function AuraInstanceAllowsHelpful(unit, auraInstanceID)
    if not (C_UnitAuras and C_UnitAuras.IsAuraFilteredOutByInstanceID) then
        return true
    end
    local ok, filtered = pcall(
        C_UnitAuras.IsAuraFilteredOutByInstanceID,
        unit, auraInstanceID, "HELPFUL")
    if ok and ScannerIsSecretValue(filtered) then
        return true
    end
    if ok and type(filtered) == "boolean" then
        return filtered == false
    end
    return true
end

local function AuraInstanceIsStillPresent(unit, auraInstanceID, hasAuraInstanceID)
    if hasAuraInstanceID ~= true then return false end
    if not (C_UnitAuras and C_UnitAuras.GetAuraDataByAuraInstanceID) then
        return true
    end
    local ok, aura = pcall(C_UnitAuras.GetAuraDataByAuraInstanceID, unit or "player", auraInstanceID)
    if not ok then return false end
    if ScannerIsSecretValue(aura) then return true end
    return aura ~= nil
end

local function ActivateItemAuraInstance(spellID, itemID, unit, auraInstanceID, hasAuraInstanceID)
    if not spellID or not itemID or hasAuraInstanceID ~= true then return false end
    SpellScanner.activeBuffs[spellID] = {
        auraInstanceID = auraInstanceID,
        hasAuraInstanceID = true,
        auraUnit = unit or "player",
        source = "item",
        sourceId = itemID,
    }
    NotifyScannerChanged(spellID, itemID)
    return true
end

local function ActivateMostRecentPlayerAuraForItem(spellID, itemID)
    local now = GetTime()
    PruneRecentPlayerAuras(now)
    for i = #SpellScanner.recentPlayerAuras, 1, -1 do
        local recent = SpellScanner.recentPlayerAuras[i]
        if recent and recent.hasAuraInstanceID == true then
            if ActivateItemAuraInstance(
                spellID, itemID, recent.auraUnit or "player", recent.auraInstanceID, true) then
                table.remove(SpellScanner.recentPlayerAuras, i)
                return true
            end
        end
    end
    return false
end

local function ItemCooldownLooksActive(itemID)
    if not itemID or not (C_Item and C_Item.GetItemCooldown) then
        return true
    end

    local ok, startTime, duration, enabled = pcall(C_Item.GetItemCooldown, itemID)
    if not ok then
        return true
    end
    if ScannerIsSecretValue(startTime)
        or ScannerIsSecretValue(duration)
        or ScannerIsSecretValue(enabled) then
        return true
    end
    if enabled == 0 or enabled == false then
        return false
    end
    if not IsCleanNumber(startTime) or not IsCleanPositiveDuration(duration) then
        return false
    end
    return startTime > 0 and (startTime + duration) > GetTime()
end

local function QueryCleanItemCooldownState(itemID)
    if not itemID or not (C_Item and C_Item.GetItemCooldown) then
        return nil, nil, nil, nil, false
    end

    local ok, startTime, duration, enabled = pcall(C_Item.GetItemCooldown, itemID)
    if not ok then
        return nil, nil, nil, nil, false
    end
    if ScannerIsSecretValue(startTime)
        or ScannerIsSecretValue(duration)
        or ScannerIsSecretValue(enabled) then
        return nil, nil, nil, nil, false
    end

    local active = false
    if enabled == 0 or enabled == false then
        active = false
    elseif IsCleanNumber(startTime) and IsCleanPositiveDuration(duration) then
        active = startTime > 0 and (startTime + duration) > GetTime()
    end

    return active, startTime, duration, enabled, true
end

local function StoreItemCooldownState(itemID, active, startTime, duration)
    if not itemID then return end
    SpellScanner.itemCooldownStates[itemID] = {
        active = active == true,
        startTime = startTime,
        duration = duration,
    }
end

local function ItemCooldownRecentlyStarted(itemID)
    local active, startTime, duration, _, known = QueryCleanItemCooldownState(itemID)
    if not known then
        return ItemCooldownLooksActive(itemID)
    end

    local prior = SpellScanner.itemCooldownStates[itemID]
    StoreItemCooldownState(itemID, active, startTime, duration)

    if active ~= true then
        return false
    end

    if not prior then
        if not IsCleanNumber(startTime) then return false end
        local age = GetTime() - startTime
        return age >= 0 and age <= ITEM_COOLDOWN_AURA_WINDOW
    end

    if prior.active ~= true then
        return true
    end

    if IsCleanNumber(startTime)
       and IsCleanNumber(prior.startTime)
       and startTime ~= prior.startTime then
        return true
    end

    return false
end

local function HandleUnitAura(unit, updateInfo)
    if unit ~= "player" or not updateInfo or updateInfo.isFullUpdate then return end
    local added = updateInfo.addedAuras
    if type(added) ~= "table" or #added == 0 then return end

    local now = GetTime()
    PrunePendingItemAuraCasts(now)
    PruneRecentPlayerAuras(now)
    local pending = SpellScanner.pendingItemAuraCasts[#SpellScanner.pendingItemAuraCasts]

    for _, auraData in ipairs(added) do
        local auraInstanceID, hasAuraInstanceID = GetRawAuraInstanceID(auraData)
        if hasAuraInstanceID == true and AuraInstanceAllowsHelpful(unit, auraInstanceID) then
            if pending and ActivateItemAuraInstance(pending.spellID, pending.itemID, unit, auraInstanceID, true) then
                table.remove(SpellScanner.pendingItemAuraCasts)
                return
            end
            RecordRecentPlayerAura(unit, auraInstanceID, true)
        end
    end
end

local function HandleBagUpdateCooldown()
    if not next(SpellScanner.registeredItemUseSpells) then return end
    local hasRecentAura = SpellScanner.recentPlayerAuras[1] ~= nil

    for useSpellID, itemID in pairs(SpellScanner.registeredItemUseSpells) do
        if ItemCooldownRecentlyStarted(itemID) then
            RecordPendingItemAuraCast(useSpellID, itemID)
            if hasRecentAura and ActivateMostRecentPlayerAuraForItem(useSpellID, itemID) then
                table.remove(SpellScanner.pendingItemAuraCasts)
                return
            end
        end
    end
end

---------------------------------------------------------------------------
-- DATABASE ACCESS
-- Uses QUI.db.global.spellScanner for cross-character persistence
---------------------------------------------------------------------------

local function GetDB()
    if QUI and QUI.db and QUI.db.global then
        if not QUI.db.global.spellScanner then
            QUI.db.global.spellScanner = {
                spells = {},  -- [castSpellID] = { buffSpellID, duration, icon, name }
                items = {},   -- [itemID] = { useSpellID, buffSpellID, duration, icon, name }
                autoScan = false,  -- Auto-scan setting (off by default)
            }
        end
        -- Load autoScan from DB into runtime state
        if QUI.db.global.spellScanner.autoScan ~= nil then
            SpellScanner.autoScan = QUI.db.global.spellScanner.autoScan
        end
        return QUI.db.global.spellScanner
    end
    return nil
end

local function GetScannedSpell(spellID)
    local db = GetDB()
    if db and db.spells and db.spells[spellID] then
        return db.spells[spellID]
    end
    return nil
end

local function GetScannedItem(itemID)
    local db = GetDB()
    if db and db.items and db.items[itemID] then
        return db.items[itemID]
    end
    return nil
end

local function FindScannedItemByUseSpellID(useSpellID)
    if not useSpellID then return nil end
    local db = GetDB()
    local items = db and db.items
    if not items then return nil end

    local lookupSpellID = tonumber(useSpellID) or useSpellID
    for itemID, data in pairs(items) do
        local itemUseSpellID = data and data.useSpellID
        if itemUseSpellID and (tonumber(itemUseSpellID) or itemUseSpellID) == lookupSpellID then
            return tonumber(itemID) or itemID
        end
    end
    return nil
end

local function CopyScannedInfo(data)
    if not data then return nil end
    return {
        useSpellID = data.useSpellID,
        buffSpellID = data.buffSpellID,
        duration = data.duration,
        icon = data.icon,
        name = data.name,
        scannedAt = data.scannedAt,
    }
end

local function SaveScannedSpell(castSpellID, data)
    local db = GetDB()
    if not db then return false end

    db.spells[castSpellID] = {
        buffSpellID = data.buffSpellID,
        duration = data.duration,
        icon = data.icon,
        name = data.name,
        scannedAt = time(),
    }
    return true
end

local function SaveScannedItem(itemID, data)
    local db = GetDB()
    if not db then return false end

    db.items[itemID] = {
        useSpellID = data.useSpellID,
        buffSpellID = data.buffSpellID,
        duration = data.duration,
        icon = data.icon,
        name = data.name,
        scannedAt = time(),
    }
    return true
end

---------------------------------------------------------------------------
-- SCANNING LOGIC
---------------------------------------------------------------------------

local function ScanSpellFromBuffs(castSpellID, itemID)
    if InCombatLockdown() then
        -- Queue for post-combat scanning
        SpellScanner.pendingScanning[castSpellID] = {
            timestamp = GetTime(),
            itemID = itemID,
        }
        return false
    end

    -- Already scanned?
    local scannedSpell = GetScannedSpell(castSpellID)
    if scannedSpell then
        if itemID and not GetScannedItem(itemID) then
            SaveScannedItem(itemID, {
                useSpellID = castSpellID,
                buffSpellID = scannedSpell.buffSpellID,
                duration = scannedSpell.duration,
                icon = scannedSpell.icon,
                name = scannedSpell.name,
            })
        end
        return true
    end

    -- Scan player buffs for recently applied ones
    local now = GetTime()
    local bestMatch = nil

    for i = 1, 40 do
        local aura = C_UnitAuras.GetAuraDataByIndex("player", i, "HELPFUL")
        if not aura then break end

        -- Secret values in Midnight: reading doesn't error, but comparisons/arithmetic do
        local spellId = aura.spellId
        local duration = aura.duration
        local expirationTime = aura.expirationTime
        local icon = aura.icon
        local name = aura.name

        -- Strict match: only accept a buff whose spellId equals the spell that
        -- was cast/used. That is the same ID for self-buff abilities and
        -- self-buff trinkets, and it eliminates the "newest recent buff wins"
        -- false positives (e.g. an external Ebon Might landing in the window
        -- when a health potion is used). A secret spellId cannot be confirmed
        -- to match, so it is rejected.
        local matchesCast = IsCleanNumber(spellId) and spellId == castSpellID

        local buffAge
        if IsCleanNumber(expirationTime) and IsCleanPositiveDuration(duration) then
            buffAge = duration - (expirationTime - now)
        end

        local isRecentBuff = matchesCast and buffAge ~= nil and buffAge < 2

        if isRecentBuff then
            if not bestMatch or buffAge < bestMatch.age then
                bestMatch = {
                    spellId = spellId,
                    duration = duration,
                    icon = icon,
                    name = name,
                    age = buffAge,
                    expirationTime = expirationTime,
                }
            end
        end
    end

    if bestMatch then
        -- Save spell and item mappings in their own namespaces. Item use
        -- spell IDs are implementation details of the item, so avoid writing
        -- them into the generic spell map where they could affect unrelated
        -- spell lookups.
        local success
        if itemID then
            success = SaveScannedItem(itemID, {
                useSpellID = castSpellID,
                buffSpellID = bestMatch.spellId,
                duration = bestMatch.duration,
                icon = bestMatch.icon,
                name = bestMatch.name,
            })
        else
            success = SaveScannedSpell(castSpellID, {
                buffSpellID = bestMatch.spellId,
                duration = bestMatch.duration,
                icon = bestMatch.icon,
                name = bestMatch.name,
            })
        end

        if success then
            -- Immediately activate the buff
            SpellScanner.activeBuffs[castSpellID] = {
                startTime = bestMatch.expirationTime - bestMatch.duration,
                duration = bestMatch.duration,
                expirationTime = bestMatch.expirationTime,
                source = itemID and "item" or "spell",
                sourceId = itemID or castSpellID,
            }
            EnsureCleanupTicker()

            -- Notify user in scan mode
            if SpellScanner.scanMode then
                print(string_format("|cff00ff00QUI:|r Scanned: %s = %.1fs",
                    bestMatch.name, bestMatch.duration))
            end

            -- Trigger UI refresh callback if registered
            if SpellScanner.onScanCallback then
                SpellScanner.onScanCallback()
            end
            NotifyScannerChanged(castSpellID, itemID)

            return true
        end
    end

    return false
end

local function ProcessPendingScanning()
    if InCombatLockdown() then return end
    if not next(SpellScanner.pendingScanning) then return end

    for spellID, data in pairs(SpellScanner.pendingScanning) do
        -- Try to scan this spell now
        ScanSpellFromBuffs(spellID, data.itemID)
        SpellScanner.pendingScanning[spellID] = nil
    end
end

---------------------------------------------------------------------------
-- SPELL CAST DETECTION
---------------------------------------------------------------------------

local function OnSpellCastSucceeded(unit, castGUID, spellID)
    if unit ~= "player" then return end
    if not spellID or spellID <= 0 then return end

    local registeredItemID = SpellScanner.registeredItemUseSpells[spellID]
        or FindScannedItemByUseSpellID(spellID)
    if registeredItemID then
        SpellScanner.registeredItemUseSpells[spellID] = registeredItemID
        RecordPendingItemAuraCast(spellID, registeredItemID)
    end

    -- Check if this cast is already scanned. Item mappings live under the
    -- item ID; fall back to the generic spell map only for legacy data.
    local itemData = registeredItemID and GetScannedItem(registeredItemID) or nil
    local data = itemData or GetScannedSpell(spellID)

    if data then
        if registeredItemID and not itemData then
            SaveScannedItem(registeredItemID, {
                useSpellID = spellID,
                buffSpellID = data.buffSpellID,
                duration = data.duration,
                icon = data.icon,
                name = data.name,
            })
        end
        -- Known spell: activate buff tracking (if we have valid duration data)
        local duration = data.duration
        if IsCleanPositiveDuration(duration) then
            local now = GetTime()
            SpellScanner.activeBuffs[spellID] = {
                startTime = now,
                duration = duration,
                expirationTime = now + duration,
                source = registeredItemID and "item" or "spell",
                sourceId = registeredItemID or spellID,
            }
            EnsureCleanupTicker()
        end
        NotifyScannerChanged(spellID, registeredItemID)
        -- Even without duration data, we treat this as "known" and skip further scanning
        return
    end

    if registeredItemID then
        if InCombatLockdown() then
            SpellScanner.pendingScanning[spellID] = {
                timestamp = GetTime(),
                itemID = registeredItemID,
            }
        else
            C_Timer.After(0.3, function()
                ScanSpellFromBuffs(spellID, registeredItemID)
            end)
        end
        return
    end

    -- Unknown spell: try to scan if enabled
    if SpellScanner.scanMode or SpellScanner.autoScan then
        if InCombatLockdown() then
            -- Queue for post-combat scanning
            SpellScanner.pendingScanning[spellID] = {
                timestamp = GetTime(),
                itemID = nil,
            }
        else
            -- Scan immediately (with small delay for buff to appear)
            C_Timer.After(0.3, function()
                ScanSpellFromBuffs(spellID, nil)
            end)
        end
    end
end

---------------------------------------------------------------------------
-- CACHE MAINTENANCE
---------------------------------------------------------------------------

local function CleanupExpiredBuffs()
    local now = GetTime()
    local hasAny = false
    for spellID, data in pairs(SpellScanner.activeBuffs) do
        local expirationTime = data.expirationTime
        if IsCleanNumber(expirationTime) and expirationTime < now then
            SpellScanner.activeBuffs[spellID] = nil
        else
            hasAny = true
        end
    end
    -- Auto-stop ticker when no active buffs remain
    if not hasAny and SpellScanner.cleanupTicker then
        SpellScanner.cleanupTicker:Cancel()
        SpellScanner.cleanupTicker = nil
    end
end

EnsureCleanupTicker = function()
    if not SpellScanner.cleanupTicker then
        SpellScanner.cleanupTicker = C_Timer.NewTicker(1, CleanupExpiredBuffs)
    end
end

---------------------------------------------------------------------------
-- PUBLIC API (for Custom Trackers)
---------------------------------------------------------------------------

-- Check if a spell's buff is currently active
-- Returns: isActive, expirationTime, duration
function SpellScanner.IsSpellActive(spellID)
    if not spellID then return false end

    local buff = SpellScanner.activeBuffs[spellID]
    if buff then
        if buff.hasAuraInstanceID == true then
            if AuraInstanceIsStillPresent(buff.auraUnit or "player", buff.auraInstanceID, true) then
                return true, buff.expirationTime, buff.duration, buff.auraInstanceID, buff.auraUnit or "player"
            end
            SpellScanner.activeBuffs[spellID] = nil
        elseif IsFutureExpiration(buff.expirationTime, GetTime()) then
            return true, buff.expirationTime, buff.duration, nil, nil
        end
    end

    -- Also check if this is a known spell with buff still applied
    -- (handles cases where we missed the cast event)
    local data = GetScannedSpell(spellID)
    if data and data.buffSpellID and not InCombatLockdown() then
        local ok, aura = pcall(C_UnitAuras.GetPlayerAuraBySpellID, data.buffSpellID)
        if ok and aura and IsFutureExpiration(aura.expirationTime, GetTime()) then
            return true, aura.expirationTime, aura.duration, GetRawAuraInstanceID(aura), "player"
        end
    end

    return false
end

-- Check if an item's buff is currently active
-- Returns: isActive, expirationTime, duration
function SpellScanner.IsItemActive(itemID)
    if not itemID then return false end

    local data = GetScannedItem(itemID)
    if data and data.useSpellID then
        return SpellScanner.IsSpellActive(data.useSpellID)
    end

    for useSpellID, registeredItemID in pairs(SpellScanner.registeredItemUseSpells) do
        if registeredItemID == itemID then
            return SpellScanner.IsSpellActive(useSpellID)
        end
    end

    return false
end

function SpellScanner.GetScannedSpellInfo(spellID)
    return CopyScannedInfo(GetScannedSpell(spellID))
end

function SpellScanner.GetScannedItemInfo(itemID)
    return CopyScannedInfo(GetScannedItem(itemID))
end

function SpellScanner.RegisterItemUseSpell(itemID, useSpellID)
    if not itemID or not useSpellID then return false end
    SpellScanner.registeredItemUseSpells[useSpellID] = itemID

    local data = GetScannedSpell(useSpellID)
    if data and not GetScannedItem(itemID) then
        SaveScannedItem(itemID, {
            useSpellID = useSpellID,
            buffSpellID = data.buffSpellID,
            duration = data.duration,
            icon = data.icon,
            name = data.name,
        })
    end
    return true
end

-- Check if a spellID has been scanned
function SpellScanner.IsSpellScanned(spellID)
    return GetScannedSpell(spellID) ~= nil
end

-- Get scanned duration for a spell (or nil if not scanned)
function SpellScanner.GetScannedDuration(spellID)
    local data = GetScannedSpell(spellID)
    return data and data.duration or nil
end

-- Toggle scan mode
function SpellScanner.ToggleScanMode()
    SpellScanner.scanMode = not SpellScanner.scanMode
    return SpellScanner.scanMode
end

-- Toggle auto-scan and persist to DB
function SpellScanner.ToggleAutoScan()
    SpellScanner.autoScan = not SpellScanner.autoScan
    local db = GetDB()
    if db then
        db.autoScan = SpellScanner.autoScan
    end
    return SpellScanner.autoScan
end

-- Set auto-scan and persist to DB
function SpellScanner.SetAutoScan(enabled)
    SpellScanner.autoScan = enabled
    local db = GetDB()
    if db then
        db.autoScan = enabled
    end
end

-- Manual trigger to scan a spell (for testing)
function SpellScanner.ScanSpell(spellID, itemID)
    return ScanSpellFromBuffs(spellID, itemID)
end

---------------------------------------------------------------------------
-- EVENT HANDLING
---------------------------------------------------------------------------

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
eventFrame:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
eventFrame:RegisterEvent("BAG_UPDATE_COOLDOWN")
eventFrame:RegisterUnitEvent("UNIT_AURA", "player")

-- Initialize the DB after login. ns.WhenLoggedIn runs now if already logged in
-- (the post-login LOD case) rather than this addon's own ADDON_LOADED, which is
-- NOT delivered when the core eager-LoadAddOn's the module from OnEnable (see
-- tooltip_provider.lua). Nil only in the headless test harness.
if ns.WhenLoggedIn then
    ns.WhenLoggedIn(GetDB)
end

eventFrame:SetScript("OnEvent", function(_, event, arg1, arg2, arg3)
    if event == "PLAYER_REGEN_ENABLED" then
        -- Process pending scanning after combat
        C_Timer.After(0.3, ProcessPendingScanning)

    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        OnSpellCastSucceeded(arg1, arg2, arg3)

    elseif event == "BAG_UPDATE_COOLDOWN" then
        HandleBagUpdateCooldown()

    elseif event == "UNIT_AURA" then
        HandleUnitAura(arg1, arg2)
    end
end)

local function SetupDebugInstrumentation()
    ns.QUI_PerfRegistry = ns.QUI_PerfRegistry or {}
    ns.QUI_PerfRegistry[#ns.QUI_PerfRegistry + 1] = { name = "SpellScanner_Events", frame = eventFrame }
end
if ns.DebugRegister then -- gate contract: core/debug_gate.lua
    ns.DebugRegister(SetupDebugInstrumentation)
else
    SetupDebugInstrumentation() -- standalone test harness: no gate, run eagerly
end

-- Cleanup ticker starts on-demand when buffs are tracked (see EnsureCleanupTicker)

---------------------------------------------------------------------------
-- SLASH COMMANDS
---------------------------------------------------------------------------

-- /quiscan - Toggle scan mode
SLASH_QUISCAN1 = "/quiscan"
SlashCmdList["QUISCAN"] = function()
    local enabled = SpellScanner.ToggleScanMode()
    if enabled then
        print("|cff00ff00QUI:|r Scan mode |cff00ff00ENABLED|r")
        print("|cffff8800-|r Cast abilities to scan their durations")
        print("|cffff8800-|r Type /quiscan again to stop")
    else
        print("|cff00ff00QUI:|r Scan mode |cffff0000DISABLED|r")
    end
end

-- /quiscanned - List scanned spells
SLASH_QUISCANNED1 = "/quiscanned"
SlashCmdList["QUISCANNED"] = function()
    local db = GetDB()
    if not db then
        print("|cffff0000QUI:|r Database not available")
        return
    end

    print("|cff00ff00QUI Scanned Spells:|r")
    local spellCount = 0
    for spellID, data in pairs(db.spells or {}) do
        print(string_format("  [%d] %s = %.1fs", spellID, data.name or "?", data.duration or 0))
        spellCount = spellCount + 1
    end
    if spellCount == 0 then
        print("  |cff888888(none)|r")
    else
        print(string_format("  |cff888888Total: %d spells|r", spellCount))
    end

    print("|cff00ff00QUI Scanned Items:|r")
    local itemCount = 0
    for itemID, data in pairs(db.items or {}) do
        local itemName = C_Item.GetItemNameByID(itemID) or "Item " .. itemID
        print(string_format("  [%d] %s = %.1fs", itemID, itemName, data.duration or 0))
        itemCount = itemCount + 1
    end
    if itemCount == 0 then
        print("  |cff888888(none)|r")
    end

    -- Show pending queue
    local pendingCount = 0
    for _ in pairs(SpellScanner.pendingScanning) do
        pendingCount = pendingCount + 1
    end
    if pendingCount > 0 then
        print(string_format("|cffff8800Pending scanning: %d spells|r", pendingCount))
    end

    -- Show active buffs
    local activeCount = 0
    for _ in pairs(SpellScanner.activeBuffs) do
        activeCount = activeCount + 1
    end
    print(string_format("|cff888888Active buffs tracked: %d|r", activeCount))
end

-- /quiclearscan <spellID|itemID> | all - Remove a scanned entry, or wipe all
SLASH_QUICLEARSCAN1 = "/quiclearscan"
SlashCmdList["QUICLEARSCAN"] = function(msg)
    local db = GetDB()
    if not db then
        print("|cffff0000QUI:|r Database not available")
        return
    end

    local arg = strtrim(msg or "")
    if arg == "" then
        print("|cffff0000QUI:|r Usage: /quiclearscan <spellID|itemID> | all")
        return
    end

    if arg:lower() == "all" then
        local spellCount, itemCount = 0, 0
        for _ in pairs(db.spells or {}) do spellCount = spellCount + 1 end
        for _ in pairs(db.items or {}) do itemCount = itemCount + 1 end
        if db.spells then wipe(db.spells) end
        if db.items then wipe(db.items) end
        wipe(SpellScanner.activeBuffs)
        wipe(SpellScanner.registeredItemUseSpells)
        wipe(SpellScanner.pendingScanning)
        wipe(SpellScanner.pendingItemAuraCasts)
        wipe(SpellScanner.recentPlayerAuras)
        wipe(SpellScanner.itemCooldownStates)
        print(string_format(
            "|cff00ff00QUI:|r Cleared all scanner data (%d spells, %d items)",
            spellCount, itemCount))
        return
    end

    local id = tonumber(arg)
    if not id then
        print("|cffff0000QUI:|r Usage: /quiclearscan <spellID|itemID> | all")
        return
    end

    local cleared = false

    if db.spells and db.spells[id] then
        local name = db.spells[id].name or "Unknown"
        db.spells[id] = nil
        SpellScanner.activeBuffs[id] = nil
        print(string_format("|cff00ff00QUI:|r Cleared spell: %s [%d]", name, id))
        cleared = true
    end

    if db.items and db.items[id] then
        local entry = db.items[id]
        local name = entry.name or "Unknown"
        local useSpellID = entry.useSpellID
        db.items[id] = nil
        if useSpellID then
            SpellScanner.registeredItemUseSpells[useSpellID] = nil
            SpellScanner.activeBuffs[useSpellID] = nil
        end
        print(string_format("|cff00ff00QUI:|r Cleared item: %s [%d]", name, id))
        cleared = true
    end

    if not cleared then
        print(string_format("|cffff8800QUI:|r %d not found in scanned spells or items", id))
    end
end
