local ADDON_NAME, ns = ...
local E = ns.AuraElements
local W = {}
ns.QUI_AuraWizard = W

local MATRIX = {
    TANK    = { groupParty = { buffs = {}, debuffs = { "dispellable" } }, player = { buffs = { "defensives" } }, target = { debuffs = { "boss" } } },
    HEALER  = { groupParty = { buffs = { "mine" }, debuffs = { "dispellable" } }, player = { buffs = { "defensives" } }, target = { debuffs = {} } },
    DAMAGER = { groupParty = { buffs = {}, debuffs = {} }, player = { buffs = { "mine" } }, target = { debuffs = { "mine" } } },
}
local function copyList(t) local o={} for i,v in ipairs(t or {}) do o[i]=v end return o end

W.PARTY_BUFF_INTENTS = {
    { key = "mine",       label = ns.L["My HoTs"] },
    { key = "defensives", label = ns.L["Big defensives on allies"] },
    { key = "all",        label = ns.L["All buffs"] },
}
W.PARTY_DEBUFF_INTENTS = {
    { key = "dispellable",  label = ns.L["Dispellable by me"] },
    { key = "boss",         label = ns.L["Boss debuffs"] },
    { key = "crowdControl", label = ns.L["Crowd control"] },
}

function W.RoleDefaults(role)
    local m = MATRIX[role] or MATRIX.DAMAGER
    return {
        groupParty = { buffs = copyList(m.groupParty.buffs), debuffs = copyList(m.groupParty.debuffs) },
        player = { buffs = copyList(m.player.buffs) },
        target = { debuffs = copyList(m.target.debuffs) },
    }
end
function W.SeedSurface(auras, auraType, intentKey)
    local e = E.NewFilterStripElement(auraType)
    E.ApplyWhatToShow(e, intentKey)
    return e
end
function W.PlayerRole()
    if not (C_SpecializationInfo and C_SpecializationInfo.GetSpecialization) then return "DAMAGER" end
    local idx = C_SpecializationInfo.GetSpecialization()
    if not idx then return "DAMAGER" end
    local role = select(5, GetSpecializationInfo(idx))
    if role == "TANK" or role == "HEALER" then return role end
    return "DAMAGER"
end

function W.PlayerSpecID()
    if not (C_SpecializationInfo and C_SpecializationInfo.GetSpecialization) then return nil end
    local idx = C_SpecializationInfo.GetSpecialization()
    if not idx then return nil end
    return (GetSpecializationInfo(idx))
end

function W.ActiveBucketKey(elements, specID)
    if E.HasSpecOverride and E.HasSpecOverride(elements, specID) then
        return specID
    end
    return "*"
end

local function deepCopyElement(v)
    if type(v) ~= "table" then return v end
    local t = {}
    for k, val in pairs(v) do t[k] = deepCopyElement(val) end
    return t
end

local function isDefensivesStrip(e)
    if type(e) ~= "table" then return false end
    if e.id == "defensives" then return true end
    if e.filterMode == "classify" and type(e.classifications) == "table"
        and e.classifications.bigDefensive and e.classifications.externalDefensive then
        return true
    end
    return false
end

local function claimNextStrip(bucket, auraType, claimed, skipDefensives)
    for _, e in ipairs(bucket) do
        if type(e) == "table" and e.mode == "filterStrip" and e.auraType == auraType
            and not claimed[e]
            and not (skipDefensives and isDefensivesStrip(e)) then
            return e
        end
    end
    return nil
end

local function applyIntentKeys(bucket, auraType, keys, skipDefensives, explicit)
    keys = keys or {}
    local claimed = {}
    for _, key in ipairs(keys) do
        local strip
        if key == "defensives" then
            for _, e in ipairs(bucket) do
                if type(e) == "table" and e.mode == "filterStrip" and isDefensivesStrip(e) then
                    strip = e
                    break
                end
            end
        else
            strip = claimNextStrip(bucket, auraType, claimed, skipDefensives)
            if strip then E.ApplyWhatToShow(strip, key) end
        end
        if not strip then
            strip = W.SeedSurface(nil, auraType, key)
            bucket[#bucket + 1] = strip
        end
        claimed[strip] = true
        strip.enabled = true
    end
    if explicit then
        for _, e in ipairs(bucket) do
            if type(e) == "table" and e.mode == "filterStrip" and e.auraType == auraType
                and not claimed[e] then
                e.enabled = false
            end
        end
    end
end

function W.SeedBucketForRole(bucket, buffKeys, debuffKeys, defaultBucketFn, explicit)
    bucket = bucket or {}
    if #bucket == 0 and type(defaultBucketFn) == "function" then
        local seed = defaultBucketFn() or {}
        for i, e in ipairs(seed) do
            bucket[i] = deepCopyElement(e)
        end
    end

    applyIntentKeys(bucket, "HARMFUL", debuffKeys, false, explicit)
    applyIntentKeys(bucket, "HELPFUL", buffKeys, true, explicit)

    return bucket
end

local function elementEqual(a, b)
    if a == b then return true end
    if type(a) ~= "table" or type(b) ~= "table" then return false end
    for k, v in pairs(a) do
        if k ~= "id" and not elementEqual(v, b[k]) then return false end
    end
    for k in pairs(b) do
        if k ~= "id" and a[k] == nil then return false end
    end
    return true
end

local function normalizedCopy(e)
    local c = deepCopyElement(e)
    if type(E.NormalizeElement) == "function" then E.NormalizeElement(c) end
    return c
end

function W.SurfaceIsCustomized(auras, defaultBucketFn, bucketKey)
    if type(auras) ~= "table" or not auras.elementsSeeded then return false end
    bucketKey = bucketKey or "*"
    local cur = (auras.elements and auras.elements[bucketKey]) or {}
    local def = (type(defaultBucketFn)=="function" and defaultBucketFn()) or {}
    if #cur ~= #def then return true end
    for i = 1, #cur do
        if not elementEqual(normalizedCopy(cur[i]), normalizedCopy(def[i])) then return true end
    end
    return false
end

function W.WizardSteps(role, surfaces)
    surfaces = surfaces or {}
    local steps = { "role", "surfaces" }
    if surfaces.party then steps[#steps + 1] = "partyAuras" end
    if role == "HEALER" and surfaces.party then steps[#steps + 1] = "placeHoTs" end
    steps[#steps + 1] = "review"
    return steps
end

function W.FocusDefaults(role)
    local m = MATRIX[role] or MATRIX.DAMAGER
    return { debuffs = copyList(m.target.debuffs) }
end

function W.CommitTrackedHoTs(bucket, staged)
    bucket = bucket or {}
    if type(staged) ~= "table" then return bucket end
    local ids = {}
    for spellID in pairs(staged) do ids[#ids + 1] = spellID end
    table.sort(ids)
    local stagedSet = {}
    for _, spellID in ipairs(ids) do stagedSet[spellID] = true end
    for i = #bucket, 1, -1 do
        local e = bucket[i]
        if type(e) == "table" and e.mode == "tracked" and type(e.spells) == "table" then
            local spells = e.spells
            for j = #spells, 1, -1 do
                if stagedSet[spells[j]] then table.remove(spells, j) end
            end
            if #spells == 0 then table.remove(bucket, i) end
        end
    end
    local slotsX, slotsY = {}, {}
    local function markInterval(map, corner, lo, hi)
        local list = map[corner]
        if not list then list = {}; map[corner] = list end
        list[#list + 1] = { lo, hi }
    end
    local function extX(corner) return corner:find("RIGHT", 1, true) and -1 or 1 end
    local function extY(corner) return corner:find("TOP", 1, true) and -1 or 1 end
    local function cellExtent(o, s, ext)
        if ext > 0 then return o, o + s end
        return o - s, o
    end
    local function spanFor(off, s, n, g, ext)
        local aLo, aHi
        if g == 0 then
            aLo = off - ((n - 1) / 2) * s
            aHi = off + ((n - 1) / 2) * s
        elseif g > 0 then
            aLo, aHi = off, off + (n - 1) * s
        else
            aLo, aHi = off - (n - 1) * s, off
        end
        if ext > 0 then return aLo, aHi + s end
        return aLo - s, aHi
    end
    local function claimOffset(map, corner, size, dir, ext)
        local list = map[corner]
        if not list then list = {}; map[corner] = list end
        local off = 0
        local moved = true
        while moved do
            moved = false
            local lo, hi = cellExtent(off, size, ext)
            for _, iv in ipairs(list) do
                if iv[1] < hi and iv[2] > lo then
                    if dir >= 0 then
                        off = (ext > 0) and iv[2] or (iv[2] + size)
                    else
                        off = (ext > 0) and (iv[1] - size) or iv[1]
                    end
                    moved = true
                    lo, hi = cellExtent(off, size, ext)
                end
            end
        end
        local lo, hi = cellExtent(off, size, ext)
        list[#list + 1] = { lo, hi }
        return off
    end
    local function renderedSpellCount(e)
        local n = E.TrackedSpellCount and E.TrackedSpellCount(e) or 0
        if n < 1 then n = 1 end
        return n
    end
    local function wrapCounts(e, n)
        local perRow = e.iconsPerRow
        if type(perRow) == "number" and perRow > 0 and perRow < n then
            return perRow, math.ceil(n / perRow)
        end
        return n, 1
    end
    local function elemSteps(e)
        local isBar = e.displayType == "bar"
        local size = (type(e.iconSize) == "number" and e.iconSize > 0) and e.iconSize or 22
        local spacing = e.spacing or 2
        local w = isBar and ((e.bar and e.bar.length) or 48) or size
        local h = isBar and ((e.bar and e.bar.thickness) or 12) or size
        return w + spacing, h + spacing
    end
    for _, e in ipairs(bucket) do
        if type(e) == "table" and e.mode == "tracked"
            and e.displayType ~= "border" and e.displayType ~= "healthTint" then
            local corner = e.anchor or "TOPLEFT"
            local grow = e.growDirection or "RIGHT"
            local n = renderedSpellCount(e)
            local mainN, crossN = wrapCounts(e, n)
            local stepX, stepY = elemSteps(e)
            local offX, offY = e.offsetX or 0, e.offsetY or 0
            if grow == "UP" or grow == "DOWN" then
                local g = (grow == "UP") and 1 or -1
                markInterval(slotsY, corner, spanFor(offY, stepY, mainN, g, extY(corner)))
                markInterval(slotsX, corner, cellExtent(offX, stepX * crossN, extX(corner)))
            else
                local g = (grow == "LEFT") and -1 or (grow == "CENTER") and 0 or 1
                markInterval(slotsX, corner, spanFor(offX, stepX, mainN, g, extX(corner)))
                markInterval(slotsY, corner, cellExtent(offY, stepY * crossN, extY(corner)))
            end
        end
    end
    for _, spellID in ipairs(ids) do
        local cfg = staged[spellID] or {}
        local e = E.NewTrackedElement({ spellID }, cfg.displayType or "icon")
        e.anchor = cfg.corner or "TOPLEFT"
        local stepX, stepY = elemSteps(e)
        if e.displayType == "bar" then
            local dir = extY(e.anchor)
            local off = claimOffset(slotsY, e.anchor, stepY, dir, extY(e.anchor))
            if off ~= 0 then e.offsetY = off end
            markInterval(slotsX, e.anchor, cellExtent(e.offsetX or 0, stepX, extX(e.anchor)))
        elseif e.displayType ~= "border" then
            local dir = extX(e.anchor)
            local off = claimOffset(slotsX, e.anchor, stepX, dir, extX(e.anchor))
            if off ~= 0 then e.offsetX = off end
            markInterval(slotsY, e.anchor, cellExtent(e.offsetY or 0, stepY, extY(e.anchor)))
        end
        bucket[#bucket + 1] = e
    end
    return bucket
end

return W
