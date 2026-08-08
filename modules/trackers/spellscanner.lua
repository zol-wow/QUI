local ADDON_NAME, ns = ...
local QUI = QUI

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

local SpellScanner = {}
QUI.SpellScanner = SpellScanner

SpellScanner.activeBuffs = {}

SpellScanner.pendingScanning = {}

SpellScanner.registeredItemUseSpells = {}

SpellScanner.pendingItemAuraCasts = {}

SpellScanner.recentPlayerAuras = {}

SpellScanner.itemCooldownStates = {}

SpellScanner.scanMode = false

SpellScanner.autoScan = false

SpellScanner.onScanCallback = nil

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
    if ScannerIsSecretValue(aura) then return true end -- @secret-policy: opaque-value-present
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
        return true -- @secret-policy: assume-cooldown-when-unknown
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
        return nil, nil, nil, nil, false -- @secret-policy: reject-secret-value
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

local function HandleUnitAura(updateInfo)
    if ScannerIsSecretValue(updateInfo) then
        updateInfo = nil
    end
    if updateInfo and ScannerIsSecretValue(updateInfo.isFullUpdate) then
        updateInfo = nil
    end
    if not updateInfo or updateInfo.isFullUpdate then return end
    local added = updateInfo.addedAuras
    if ScannerIsSecretValue(added) then return end
    if type(added) ~= "table" or #added == 0 then return end

    local now = GetTime()
    PrunePendingItemAuraCasts(now)
    PruneRecentPlayerAuras(now)
    local pending = SpellScanner.pendingItemAuraCasts[#SpellScanner.pendingItemAuraCasts]

    for _, auraData in ipairs(added) do
        local auraInstanceID, hasAuraInstanceID = GetRawAuraInstanceID(auraData)
        if hasAuraInstanceID == true and AuraInstanceAllowsHelpful("player", auraInstanceID) then
            if pending and ActivateItemAuraInstance(pending.spellID, pending.itemID, "player", auraInstanceID, true) then
                table.remove(SpellScanner.pendingItemAuraCasts)
                return
            end
            RecordRecentPlayerAura("player", auraInstanceID, true)
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

local function GetDB()
    if QUI and QUI.db and QUI.db.global then
        if not QUI.db.global.spellScanner then
            QUI.db.global.spellScanner = {
                spells = {},
                items = {},
                autoScan = false,
            }
        end
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

local C_Secrets = C_Secrets
local function ForEachPlayerHelpfulAura(callback)
    if C_Secrets and C_Secrets.ShouldAurasBeSecret and C_Secrets.ShouldAurasBeSecret() then
        return
    end
    local i = 0
    while true do
        i = i + 1
        local ok, aura = pcall(C_UnitAuras.GetAuraDataByIndex, "player", i, "HELPFUL")
        if not ok then return end
        if ScannerIsSecretValue(aura) then
            aura = nil -- @secret-policy: reject-secret-value — skip, keep walking
        elseif aura == nil then
            return
        end
        if aura ~= nil and callback(aura) then
            return
        end
    end
end

local function ScanSpellFromBuffs(castSpellID, itemID)
    if InCombatLockdown() then
        SpellScanner.pendingScanning[castSpellID] = {
            timestamp = GetTime(),
            itemID = itemID,
        }
        return false
    end

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

    local now = GetTime()
    local bestMatch = nil

    ForEachPlayerHelpfulAura(function(aura)
        local spellId = aura.spellId
        if ScannerIsSecretValue(spellId) then spellId = nil end
        local duration = aura.duration
        if ScannerIsSecretValue(duration) then duration = nil end
        local expirationTime = aura.expirationTime
        if ScannerIsSecretValue(expirationTime) then expirationTime = nil end
        local icon = aura.icon
        local name = aura.name

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
    end)

    if bestMatch then
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
            SpellScanner.activeBuffs[castSpellID] = {
                startTime = bestMatch.expirationTime - bestMatch.duration,
                duration = bestMatch.duration,
                expirationTime = bestMatch.expirationTime,
                source = itemID and "item" or "spell",
                sourceId = itemID or castSpellID,
            }
            EnsureCleanupTicker()

            if SpellScanner.scanMode then
                print(string_format(ns.L["|cff00ff00QUI:|r Scanned: %s = %.1fs"],
                    bestMatch.name, bestMatch.duration))
            end

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
        ScanSpellFromBuffs(spellID, data.itemID)
        SpellScanner.pendingScanning[spellID] = nil
    end
end

local function OnSpellCastSucceeded(_, castGUID, spellID)
    if ScannerIsSecretValue(spellID) then return end
    if not spellID or spellID <= 0 then return end

    local registeredItemID = SpellScanner.registeredItemUseSpells[spellID]
        or FindScannedItemByUseSpellID(spellID)
    if registeredItemID then
        SpellScanner.registeredItemUseSpells[spellID] = registeredItemID
        RecordPendingItemAuraCast(spellID, registeredItemID)
    end

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

    if SpellScanner.scanMode or SpellScanner.autoScan then
        if InCombatLockdown() then
            SpellScanner.pendingScanning[spellID] = {
                timestamp = GetTime(),
                itemID = nil,
            }
        else
            C_Timer.After(0.3, function()
                ScanSpellFromBuffs(spellID, nil)
            end)
        end
    end
end

local function CleanupExpiredBuffs()
    local now = GetTime()
    local hasAny = false
    for spellID, data in pairs(SpellScanner.activeBuffs) do
        local expired
        if data.hasAuraInstanceID == true then
            expired = not AuraInstanceIsStillPresent(data.auraUnit or "player", data.auraInstanceID, true)
        else
            local expirationTime = data.expirationTime
            expired = IsCleanNumber(expirationTime) and expirationTime < now
        end
        if expired then
            SpellScanner.activeBuffs[spellID] = nil
        else
            hasAny = true
        end
    end
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

    local data = GetScannedSpell(spellID)
    if data and data.buffSpellID and not InCombatLockdown() then
        local ok, aura = pcall(C_UnitAuras.GetPlayerAuraBySpellID, data.buffSpellID)
        if ScannerIsSecretValue(aura) then aura = nil end
        if ok and aura then
            local exp = aura.expirationTime
            if ScannerIsSecretValue(exp) then exp = nil end
            if IsFutureExpiration(exp, GetTime()) then
                return true, aura.expirationTime, aura.duration, GetRawAuraInstanceID(aura), "player"
            end
        end
    end

    return false
end

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

function SpellScanner.ToggleScanMode()
    SpellScanner.scanMode = not SpellScanner.scanMode
    return SpellScanner.scanMode
end

function SpellScanner.ScanSpell(spellID, itemID)
    return ScanSpellFromBuffs(spellID, itemID)
end

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
eventFrame:RegisterEvent("BAG_UPDATE_COOLDOWN")
eventFrame:RegisterUnitEvent("UNIT_AURA", "player")
eventFrame:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")

if ns.WhenLoggedIn then
    ns.WhenLoggedIn(GetDB)
end

eventFrame:SetScript("OnEvent", function(_, event, arg1, arg2, arg3)
    if event == "PLAYER_REGEN_ENABLED" then
        C_Timer.After(0.3, ProcessPendingScanning)

    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        OnSpellCastSucceeded(arg1, arg2, arg3)

    elseif event == "BAG_UPDATE_COOLDOWN" then
        HandleBagUpdateCooldown()

    elseif event == "UNIT_AURA" then
        HandleUnitAura(arg2)
    end
end)

local function SetupDebugInstrumentation()
    ns.QUI_PerfRegistry = ns.QUI_PerfRegistry or {}
    ns.QUI_PerfRegistry[#ns.QUI_PerfRegistry + 1] = { name = "SpellScanner_Events", frame = eventFrame }
end
if ns.DebugRegister then
    ns.DebugRegister(SetupDebugInstrumentation)
else
    SetupDebugInstrumentation()
end

SLASH_QUISCAN1 = "/quiscan"
SlashCmdList["QUISCAN"] = function()
    local enabled = SpellScanner.ToggleScanMode()
    if enabled then
        print(ns.L["|cff00ff00QUI:|r Scan mode |cff00ff00ENABLED|r"])
        print(ns.L["|cffff8800-|r Cast abilities to scan their durations"])
        print(ns.L["|cffff8800-|r Type /quiscan again to stop"])
    else
        print(ns.L["|cff00ff00QUI:|r Scan mode |cffff0000DISABLED|r"])
    end
end

SLASH_QUISCANNED1 = "/quiscanned"
SlashCmdList["QUISCANNED"] = function()
    local db = GetDB()
    if not db then
        print(ns.L["|cffff0000QUI:|r Database not available"])
        return
    end

    print(ns.L["|cff00ff00QUI Scanned Spells:|r"])
    local spellCount = 0
    for spellID, data in pairs(db.spells or {}) do
        print(string_format("  [%d] %s = %.1fs", spellID, data.name or "?", data.duration or 0))
        spellCount = spellCount + 1
    end
    if spellCount == 0 then
        print(ns.L["  |cff888888(none)|r"])
    else
        print(string_format(ns.L["  |cff888888Total: %d spells|r"], spellCount))
    end

    print(ns.L["|cff00ff00QUI Scanned Items:|r"])
    local itemCount = 0
    for itemID, data in pairs(db.items or {}) do
        local itemName = C_Item.GetItemNameByID(itemID) or ns.L["Item "] .. itemID
        print(string_format("  [%d] %s = %.1fs", itemID, itemName, data.duration or 0))
        itemCount = itemCount + 1
    end
    if itemCount == 0 then
        print(ns.L["  |cff888888(none)|r"])
    end

    local pendingCount = 0
    for _ in pairs(SpellScanner.pendingScanning) do
        pendingCount = pendingCount + 1
    end
    if pendingCount > 0 then
        print(string_format(ns.L["|cffff8800Pending scanning: %d spells|r"], pendingCount))
    end

    local activeCount = 0
    for _ in pairs(SpellScanner.activeBuffs) do
        activeCount = activeCount + 1
    end
    print(string_format(ns.L["|cff888888Active buffs tracked: %d|r"], activeCount))
end

SLASH_QUICLEARSCAN1 = "/quiclearscan"
SlashCmdList["QUICLEARSCAN"] = function(msg)
    local db = GetDB()
    if not db then
        print(ns.L["|cffff0000QUI:|r Database not available"])
        return
    end

    local arg = strtrim(msg or "")
    if arg == "" then
        print(ns.L["|cffff0000QUI:|r Usage: /quiclearscan <spellID|itemID> | all"])
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
            ns.L["|cff00ff00QUI:|r Cleared all scanner data (%d spells, %d items)"],
            spellCount, itemCount))
        return
    end

    local id = tonumber(arg)
    if not id then
        print(ns.L["|cffff0000QUI:|r Usage: /quiclearscan <spellID|itemID> | all"])
        return
    end

    local cleared = false

    if db.spells and db.spells[id] then
        local name = db.spells[id].name or ns.L["Unknown"]
        db.spells[id] = nil
        SpellScanner.activeBuffs[id] = nil
        print(string_format(ns.L["|cff00ff00QUI:|r Cleared spell: %s [%d]"], name, id))
        cleared = true
    end

    if db.items and db.items[id] then
        local entry = db.items[id]
        local name = entry.name or ns.L["Unknown"]
        local useSpellID = entry.useSpellID
        db.items[id] = nil
        if useSpellID then
            SpellScanner.registeredItemUseSpells[useSpellID] = nil
            SpellScanner.activeBuffs[useSpellID] = nil
        end
        print(string_format(ns.L["|cff00ff00QUI:|r Cleared item: %s [%d]"], name, id))
        cleared = true
    end

    if not cleared then
        print(string_format(ns.L["|cffff8800QUI:|r %d not found in scanned spells or items"], id))
    end
end
