local _, ns = ...

local CDMManagedAuraMirrors = {}
ns.CDMManagedAuraMirrors = CDMManagedAuraMirrors

local InstanceMT = { __index = CDMManagedAuraMirrors }
local PARK_FILTER = { maxDuration = 0 }

local function AppendID(out, seen, value, isSecret)
    if type(value) ~= "number" or (isSecret and isSecret(value)) or seen[value] then return end
    seen[value] = true
    out[#out + 1] = value
end

function CDMManagedAuraMirrors.ResolveCandidateIDs(entry, isSecret)
    local out, seen = {}, {}
    if type(entry) ~= "table" then return out end
    AppendID(out, seen, entry.overrideSpellID, isSecret)
    AppendID(out, seen, entry.spellID, isSecret)
    if entry.type == nil or entry.type == "spell" then
        AppendID(out, seen, entry.id, isSecret)
    end
    AppendID(out, seen, entry.linkedSpellID, isSecret)
    local linked = entry.linkedSpellIDs
    if type(linked) == "table" then
        for i = 1, #linked do AppendID(out, seen, linked[i], isSecret) end
    end
    local baseID = entry.id or entry.spellID
    local runtime = ns.CDMAuraRuntime
    if runtime and runtime.ResolveAbilityAuraSpellID then
        local mapped = runtime.ResolveAbilityAuraSpellID(baseID)
        AppendID(out, seen, mapped, isSecret)
    end
    local spellData = ns.CDMSpellData
    if spellData and spellData.GetAuraIDsForSpell then
        local auraIDs = spellData:GetAuraIDsForSpell(baseID)
        if type(auraIDs) == "table" then
            for i = 1, #auraIDs do AppendID(out, seen, auraIDs[i], isSecret) end
        end
    end
    return out
end

local function CandidateFilter(spellID)
    return { includeSpellIDs = { [spellID] = true } }
end

function CDMManagedAuraMirrors.New(deps)
    deps = deps or {}
    local self = {
        _deps = deps,
        _pools = setmetatable({}, { __mode = "k" }),
    }
    return setmetatable(self, InstanceMT)
end

function CDMManagedAuraMirrors:_GetPool(ownerContainer, allowCreate)
    local pool = self._pools[ownerContainer]
    if pool or not allowCreate then return pool end
    local createFrame = self._deps.createFrame
    if not createFrame then return nil end
    local auraContainer = createFrame("AuraContainer", nil, ownerContainer,
        "CustomAuraContainerTemplate")
    if not auraContainer then return nil end
    if auraContainer.SetSize then auraContainer:SetSize(1, 1) end
    if auraContainer.SetUnit then auraContainer:SetUnit("player") end
    if auraContainer.SetEnabled then auraContainer:SetEnabled(true) end
    if auraContainer.Show then auraContainer:Show() end
    pool = {
        auraContainer = auraContainer,
        records = {},
        free = {},
        slotSeq = 0,
        generation = 0,
    }
    self._pools[ownerContainer] = pool
    return pool
end

function CDMManagedAuraMirrors:BeginPass(ownerContainer)
    local canCreate = not self._deps.canCreate or self._deps.canCreate(ownerContainer)
    local pool = self:_GetPool(ownerContainer, canCreate)
    if not pool then return false end
    pool.generation = pool.generation + 1
    return true
end

local function ParkRecord(pool, record)
    if record.parked then return end
    local auraContainer = pool.auraContainer
    for i = 1, #record.slots do
        auraContainer:SetAuraSlotCandidateFilters(record.slots[i].key, PARK_FILTER)
    end
    record.parked = true
end

local function ReleaseToFree(pool, record)
    if record.free then return end
    local free = pool.free
    free[#free + 1] = record
    record.free = true
    record.freeIndex = #free
end

local function DetachFree(pool, record)
    local free = pool.free
    local index, last = record.freeIndex, #free
    if index and free[index] == record then
        if index ~= last then
            local moved = free[last]
            free[index] = moved
            moved.freeIndex = index
        end
        free[last] = nil
    end
    record.free = false
    record.freeIndex = nil
end

local function ClaimFromFree(pool, record)
    if not record.free then return end
    DetachFree(pool, record)
end

local function TakeFree(pool)
    local free = pool.free
    local last = #free
    if last == 0 then return nil end
    local record = free[last]
    DetachFree(pool, record)
    return record
end

function CDMManagedAuraMirrors:Acquire(ownerContainer, placementKey, entry, profile)
    local pool = self._pools[ownerContainer]
    if not pool then return nil end
    local ids = CDMManagedAuraMirrors.ResolveCandidateIDs(entry, self._deps.isSecret)
    if #ids == 0 then return nil end

    local record = pool.records[placementKey]
    if record then
        ClaimFromFree(pool, record)
    else
        record = TakeFree(pool)
        if record then
            pool.records[record.placementKey] = nil
            record.placementKey = placementKey
            pool.records[placementKey] = record
        else
            local createFrame = self._deps.createFrame
            if not createFrame then return nil end
            local host = createFrame("Frame", nil, ownerContainer)
            if not host then return nil end
            record = { placementKey = placementKey, host = host, slots = {}, free = false }
            pool.records[placementKey] = record
        end
    end

    local auraContainer = pool.auraContainer
    for i = 1, #ids do
        local spellID = ids[i]
        local slot = record.slots[i]
        if slot then
            auraContainer:SetAuraSlotFilterString(slot.key, "HELPFUL")
            auraContainer:SetAuraSlotCandidateFilters(slot.key, CandidateFilter(spellID))
            slot.spellID = spellID
        else
            pool.slotSeq = pool.slotSeq + 1
            local key = "quiAuraMirror:" .. tostring(pool.slotSeq)
            local host = record.host
            local styleFrame = self._deps.styleFrame
            local frame = auraContainer:AddAuraSlot(key, "HELPFUL", {
                candidateFilters = CandidateFilter(spellID),
                initializeFrame = function(button)
                    if styleFrame then styleFrame(button, profile or {}) end
                    if button.ClearAllPoints then button:ClearAllPoints() end
                    if button.SetAllPoints then
                        button:SetAllPoints(host)
                    elseif button.SetPoint then
                        button:SetPoint("TOPLEFT", host, "TOPLEFT", 0, 0)
                        button:SetPoint("BOTTOMRIGHT", host, "BOTTOMRIGHT", 0, 0)
                    end
                    if button.SetFrameLevel then
                        local base = host.GetFrameLevel and host:GetFrameLevel() or 0
                        button:SetFrameLevel(base + 32 - i)
                    end
                    if button.EnableMouse then button:EnableMouse(false) end
                    if button.SetMouseClickEnabled then button:SetMouseClickEnabled(false) end
                    if button.SetMouseMotionEnabled then button:SetMouseMotionEnabled(false) end
                end,
            })
            slot = { key = key, frame = frame, spellID = spellID }
            record.slots[i] = slot
        end
    end
    for i = #ids + 1, #record.slots do
        auraContainer:SetAuraSlotCandidateFilters(record.slots[i].key, PARK_FILTER)
    end

    record.entry = entry
    record.generation = pool.generation
    record.parked = false
    record.profile = profile
    if record.host.Show then record.host:Show() end
    return record
end

function CDMManagedAuraMirrors:Position(record, baseIcon, ownerContainer, x, y, w, h, rowConfig)
    if not (record and record.host and baseIcon) then return false end
    local canMutate = self._deps.canMutate
    if canMutate and not canMutate(record.host) then return false end
    local host = record.host
    host:ClearAllPoints()
    host:SetPoint("CENTER", ownerContainer, "CENTER", x, y)
    if host.SetSize and w and h then host:SetSize(w, h) end
    if host.Show then host:Show() end
    local positionBase = self._deps.positionBase
    if positionBase then positionBase(baseIcon, host, rowConfig) end
    local restyleFrame = self._deps.restyleFrame
    if restyleFrame and not (self._deps.aurasAreSecret and self._deps.aurasAreSecret()) then
        for i = 1, #record.slots do
            local slot = record.slots[i]
            if slot.frame then restyleFrame(slot.frame, rowConfig or record.profile or {}) end
        end
    end
    return true
end

function CDMManagedAuraMirrors:EndPass(ownerContainer)
    local pool = self._pools[ownerContainer]
    if not pool then return true end
    local canMutate = self._deps.canMutate
    for _, record in pairs(pool.records) do
        if record.generation ~= pool.generation then
            ParkRecord(pool, record)
            if record.host.Hide and (not canMutate or canMutate(record.host)) then
                record.host:Hide()
            end
            ReleaseToFree(pool, record)
        end
    end
    return true
end

return CDMManagedAuraMirrors
