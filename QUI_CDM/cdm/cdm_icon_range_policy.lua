local _, ns = ...

---------------------------------------------------------------------------
-- CDM Icon Range Policy
--
-- Private controller used by CDMIcons. It owns spell range registration,
-- range/usability tint caches, and event-targeted visual refresh.
---------------------------------------------------------------------------

local CDMIconRangePolicy = {}
ns.CDMIconRangePolicy = CDMIconRangePolicy

local ipairs = ipairs
local pairs = pairs
local tostring = tostring
local type = type
local wipe = wipe or function(tbl)
    for key in pairs(tbl) do
        tbl[key] = nil
    end
end

local issecretvalue = issecretvalue or function() return false end

local function normalizeSpellIdentifier(value)
    if value == nil then return nil end
    if issecretvalue and issecretvalue(value) then return nil end
    local valueType = type(value)
    if valueType == "number" or valueType == "string" then
        return value
    end
    return nil
end

local function spellIdentifiersMatch(a, b)
    a = normalizeSpellIdentifier(a)
    b = normalizeSpellIdentifier(b)
    if a == nil or b == nil then return false end
    return a == b or tostring(a) == tostring(b)
end

function CDMIconRangePolicy.Create(callbacks)
    callbacks = callbacks or {}

    local controller = {
        rangeCycleCache = {},
        hasRangeCycleCache = {},
        usableCycleCache = {},
        enabledRangeSpellChecks = {},
        desiredRangeSpellChecks = {},
        stackTextWritesForBatch = false,
    }

    local function getRangeUnit()
        if UnitExists("target") then return "target" end
        if UnitExists("softenemy") then return "softenemy" end
        return nil
    end

    local function queryReadableSpellInRange(spellID, unit)
        if not spellID or not unit or not callbacks.querySpellInRange then return nil end
        local inRange = callbacks.querySpellInRange(spellID, unit)
        if inRange == false then return false end
        if inRange == true then return true end
        return nil
    end

    local function queryReadableSpellUsable(spellID)
        if not spellID or not callbacks.querySpellUsable then return true, false end
        local usable, noMana = callbacks.querySpellUsable(spellID)
        local noManaBool = type(noMana) == "boolean" and noMana or false
        if type(usable) == "boolean" and usable == false then return false, noManaBool end
        if type(usable) == "boolean" and usable == true then return true, noManaBool end
        return true, noManaBool
    end

    function controller:SetStackTextWritesForBatch(enabled)
        controller.stackTextWritesForBatch = enabled == true
    end

    function controller:ShouldAllowStackTextWrites()
        return controller.stackTextWritesForBatch == true
    end

    function controller:GetIconRangeSpellID(icon, entry)
        entry = entry or (icon and icon._spellEntry)
        if not entry then return nil end
        return normalizeSpellIdentifier(icon and icon._runtimeSpellID or entry.spellID or entry.id)
    end

    local function resetIconVisuals(icon)
        icon.Icon:SetVertexColor(1, 1, 1, 1)
        icon._rangeTinted = nil
        icon._usabilityTinted = nil
    end

    local function updateIconVisualState(icon, cachedDB, rangeEventSpellID, rangeEventInRange, rangeEventChecksRange)
        if not icon or not icon._spellEntry then return end
        local entry = icon._spellEntry
        local viewerType = entry.viewerType
        if not viewerType then return end

        local settings = callbacks.resolveSettings
            and callbacks.resolveSettings(viewerType, cachedDB)
            or nil
        if not settings then
            if icon._rangeTinted or icon._usabilityTinted then
                icon._lastVisualState = nil
                resetIconVisuals(icon)
            end
            return
        end

        local rangeEnabled = settings.rangeIndicator
        local usabilityEnabled = settings.usabilityIndicator

        if not rangeEnabled and not usabilityEnabled then
            if icon._rangeTinted or icon._usabilityTinted then
                icon._lastVisualState = nil
                resetIconVisuals(icon)
            end
            return
        end

        if viewerType == "buff" then return end
        if entry.type == "item" or entry.type == "trinket" or entry.type == "slot" then return end

        local spellID = controller:GetIconRangeSpellID(icon, entry)
        if not spellID then return end

        local newVisualState = "normal"
        local cooldownVisualPriority = false

        local rangeUnit = rangeEnabled and getRangeUnit() or nil
        if rangeUnit then
            local hasRange
            local inRange
            if rangeEventSpellID ~= nil then
                hasRange = rangeEventChecksRange == true
                inRange = hasRange and (rangeEventInRange == true) or nil
            else
                hasRange = controller.hasRangeCycleCache[spellID]
                if hasRange == nil then
                    hasRange = callbacks.querySpellHasRange and callbacks.querySpellHasRange(spellID)
                    if type(hasRange) ~= "boolean" then
                        hasRange = nil
                    end
                    if hasRange == nil then hasRange = true end
                    controller.hasRangeCycleCache[spellID] = hasRange and true or false
                end
                if hasRange then
                    local cached = controller.rangeCycleCache[spellID]
                    if cached ~= nil then
                        inRange = cached ~= "nil" and cached or nil
                    else
                        inRange = queryReadableSpellInRange(spellID, rangeUnit)
                        controller.rangeCycleCache[spellID] = inRange == nil and "nil" or inRange
                    end
                end
            end
            if hasRange and inRange == false then
                newVisualState = "oor"
            end
        end

        if newVisualState == "normal" then
            cooldownVisualPriority = callbacks.cooldownHasVisualPriority
                and callbacks.cooldownHasVisualPriority(icon, entry, settings)
                or false
            if cooldownVisualPriority and icon._usabilityTinted then
                icon.Icon:SetVertexColor(1, 1, 1, 1)
                icon._usabilityTinted = nil
                icon._lastVisualState = nil
            end
        end

        if newVisualState == "normal" and usabilityEnabled and not cooldownVisualPriority then
            local isUsable = controller.usableCycleCache[spellID]
            if isUsable == nil then
                isUsable = queryReadableSpellUsable(spellID)
                controller.usableCycleCache[spellID] = isUsable
            end
            if not isUsable then
                local chargeState = callbacks.resolveCooldownActivityState
                    and callbacks.resolveCooldownActivityState(icon, entry, settings)
                    or {}
                if chargeState.hasCharges and chargeState.isOnCooldown ~= true then
                    isUsable = true
                end
            end
            if not isUsable then
                newVisualState = "unusable"
            end
        end

        if icon._lastVisualState == newVisualState then
            if newVisualState == "unusable"
               and not icon._usabilityTinted
               and not cooldownVisualPriority then
                icon.Icon:SetVertexColor(0.4, 0.4, 0.4, 1)
                icon._usabilityTinted = true
            end
            return
        end
        icon._lastVisualState = newVisualState

        if newVisualState == "oor" then
            if icon._usabilityTinted then
                icon._usabilityTinted = nil
            end
            local c = settings.rangeColor
            local r = c and c[1] or 0.8
            local g = c and c[2] or 0.1
            local b = c and c[3] or 0.1
            local a = c and c[4] or 1
            icon.Icon:SetVertexColor(r, g, b, a)
            icon._rangeTinted = true
            return
        end

        if icon._rangeTinted then
            icon.Icon:SetVertexColor(1, 1, 1, 1)
            icon._rangeTinted = nil
        end

        if newVisualState == "unusable" then
            icon.Icon:SetVertexColor(0.4, 0.4, 0.4, 1)
            icon._usabilityTinted = true
            return
        end

        if icon._usabilityTinted then
            icon.Icon:SetVertexColor(1, 1, 1, 1)
            icon._usabilityTinted = nil
        end
    end

    function controller:IconNeedsUsabilityVisualRefresh(icon, cachedDB)
        local entry = icon and icon._spellEntry
        if not entry then return false end
        if callbacks.isAuraEntry and callbacks.isAuraEntry(entry) then return false end
        if entry.kind == "aura" or entry.kind == "auraBar" then return false end
        if entry.type == "item" or entry.type == "trinket" or entry.type == "slot" then return false end

        if icon._rangeTinted or icon._usabilityTinted then
            return true
        end

        local viewerType = entry.viewerType
        if not viewerType or viewerType == "buff" then return false end

        local settings = callbacks.resolveSettings
            and callbacks.resolveSettings(viewerType, cachedDB)
            or nil
        return settings and settings.usabilityIndicator or false
    end

    local function resetCycleCaches()
        wipe(controller.rangeCycleCache)
        wipe(controller.hasRangeCycleCache)
        wipe(controller.usableCycleCache)
    end

    function controller:UpdateIconRangesForUsabilityEvent(iconPools)
        resetCycleCaches()
        local db = callbacks.getDB and callbacks.getDB() or nil
        for _, pool in pairs(iconPools or {}) do
            for _, icon in ipairs(pool) do
                if controller:IconNeedsUsabilityVisualRefresh(icon, db) then
                    updateIconVisualState(icon, db)
                end
            end
        end
    end

    function controller:UpdateAllIconRanges(iconPools)
        resetCycleCaches()
        local db = callbacks.getDB and callbacks.getDB() or nil
        for _, pool in pairs(iconPools or {}) do
            for _, icon in ipairs(pool) do
                updateIconVisualState(icon, db)
            end
        end
    end

    function controller:SyncSpellRangeChecks(iconPools)
        wipe(controller.desiredRangeSpellChecks)
        local db = callbacks.getDB and callbacks.getDB() or nil

        for _, pool in pairs(iconPools or {}) do
            for _, icon in ipairs(pool) do
                local entry = icon and icon._spellEntry
                if entry and entry.viewerType and entry.viewerType ~= "buff"
                    and entry.type ~= "item" and entry.type ~= "trinket" and entry.type ~= "slot" then
                    local settings = callbacks.resolveSettings
                        and callbacks.resolveSettings(entry.viewerType, db)
                        or nil
                    if settings and settings.rangeIndicator then
                        local spellID = controller:GetIconRangeSpellID(icon, entry)
                        if spellID then
                            controller.desiredRangeSpellChecks[spellID] = true
                        end
                    end
                end
            end
        end

        if not callbacks.enableSpellRangeCheck then
            wipe(controller.enabledRangeSpellChecks)
            return
        end

        for spellID in pairs(controller.enabledRangeSpellChecks) do
            if not controller.desiredRangeSpellChecks[spellID] then
                callbacks.enableSpellRangeCheck(spellID, false)
                controller.enabledRangeSpellChecks[spellID] = nil
            end
        end

        for spellID in pairs(controller.desiredRangeSpellChecks) do
            if not controller.enabledRangeSpellChecks[spellID] then
                if callbacks.enableSpellRangeCheck(spellID, true) then
                    controller.enabledRangeSpellChecks[spellID] = true
                end
            end
        end
    end

    function controller:DisableSpellRangeChecks()
        if callbacks.enableSpellRangeCheck then
            for spellID in pairs(controller.enabledRangeSpellChecks) do
                callbacks.enableSpellRangeCheck(spellID, false)
            end
        end
        wipe(controller.enabledRangeSpellChecks)
        wipe(controller.desiredRangeSpellChecks)
    end

    function controller:UpdateIconsForSpellRangeEvent(iconPools, spellIdentifier, isInRange, checksRange)
        local eventSpellID = normalizeSpellIdentifier(spellIdentifier)
        if not eventSpellID then return end

        local db = callbacks.getDB and callbacks.getDB() or nil
        for _, pool in pairs(iconPools or {}) do
            for _, icon in ipairs(pool) do
                local entry = icon and icon._spellEntry
                if entry and spellIdentifiersMatch(eventSpellID, controller:GetIconRangeSpellID(icon, entry)) then
                    local settings = callbacks.resolveSettings
                        and callbacks.resolveSettings(entry.viewerType, db)
                        or nil
                    if settings and settings.rangeIndicator and checksRange == true and isInRange == false
                        and icon.Icon and icon.Icon.SetVertexColor then
                        if icon._usabilityTinted then
                            icon._usabilityTinted = nil
                        end
                        local c = settings.rangeColor
                        local r = c and c[1] or 0.8
                        local g = c and c[2] or 0.1
                        local b = c and c[3] or 0.1
                        local a = c and c[4] or 1
                        icon.Icon:SetVertexColor(r, g, b, a)
                        icon._rangeTinted = true
                        icon._lastVisualState = "oor"
                    else
                        updateIconVisualState(icon, db, eventSpellID, isInRange == true, checksRange == true)
                    end
                end
            end
        end
    end

    return controller
end
