local _, ns = ...

local CDMPlacementPlanner = {}
ns.CDMPlacementPlanner = CDMPlacementPlanner

local CONTAINER_PRIORITY = {
    buff = 1,
    buffIcon = 1,
    essential = 2,
    utility = 3,
}

local NATIVE_ONLY_ENTRY_TYPES = {
    item = true,
    slot = true,
    trinket = true,
    consumable = true,
}

local function ValueID(value)
    if value == nil then return "nil" end
    return tostring(value)
end

local function IsAuraEntry(entry)
    return entry and (entry.kind == "aura" or entry.isAura == true)
end

function CDMPlacementPlanner.IsMirrorableEntry(entry)
    return entry ~= nil
        and entry._isTotemInstance ~= true
        and not NATIVE_ONLY_ENTRY_TYPES[entry.type]
end

function CDMPlacementPlanner.BuildPlacementKey(containerKey, ordinal, entry)
    entry = entry or {}
    local entryType = entry.type or "spell"
    local entryID = entry.id or entry.spellID or entry.overrideSpellID or entry.name or "unknown"
    local instanceKey = entry._instanceKey or entry.position or entry.index or ""
    return table.concat({
        ValueID(containerKey or "unknown"),
        ValueID(ordinal or 0),
        ValueID(entryType),
        ValueID(entryID),
        ValueID(instanceKey),
    }, ":")
end

local function CandidateLess(a, b)
    local aMirrorable = CDMPlacementPlanner.IsMirrorableEntry(a.entry)
    local bMirrorable = CDMPlacementPlanner.IsMirrorableEntry(b.entry)
    if aMirrorable ~= bMirrorable then
        return not aMirrorable
    end

    local ap = CONTAINER_PRIORITY[a.containerKey] or 100
    local bp = CONTAINER_PRIORITY[b.containerKey] or 100
    if ap ~= bp then return ap < bp end

    local ao = a.ordinal or 0
    local bo = b.ordinal or 0
    if ao ~= bo then return ao < bo end

    return tostring(a.placementKey or "") < tostring(b.placementKey or "")
end

function CDMPlacementPlanner.Plan(candidates)
    candidates = candidates or {}
    local byFrame = setmetatable({}, { __mode = "k" })
    local consumersByFrame = setmetatable({}, { __mode = "k" })
    local assignmentsByContainer = {}
    local assignmentsByKey = {}
    local ownerByFrame = setmetatable({}, { __mode = "k" })

    for i = 1, #candidates do
        local candidate = candidates[i]
        local frame = candidate and candidate.frame
        if frame then
            candidate.ordinal = candidate.ordinal or i
            candidate.placementKey = candidate.placementKey
                or CDMPlacementPlanner.BuildPlacementKey(
                    candidate.containerKey, candidate.ordinal, candidate.entry)
            local group = byFrame[frame]
            if not group then
                group = {}
                byFrame[frame] = group
            end
            group[#group + 1] = candidate
        end
    end

    for frame, group in pairs(byFrame) do
        table.sort(group, CandidateLess)
        local owner = group[1]
        ownerByFrame[frame] = owner
        local consumers = {}
        consumersByFrame[frame] = consumers

        for i = 1, #group do
            local candidate = group[i]
            local renderKind
            if candidate == owner then
                renderKind = "native"
            elseif not CDMPlacementPlanner.IsMirrorableEntry(candidate.entry) then
                renderKind = "unsupportedMirror"
            elseif IsAuraEntry(candidate.entry) then
                renderKind = "auraMirror"
            else
                renderKind = "spellMirror"
            end

            local assignment = {
                placementKey = candidate.placementKey,
                containerKey = candidate.containerKey,
                ordinal = candidate.ordinal,
                entry = candidate.entry,
                frame = frame,
                renderKind = renderKind,
                nativeOwner = owner,
            }
            local perContainer = assignmentsByContainer[candidate.containerKey]
            if not perContainer then
                perContainer = {}
                assignmentsByContainer[candidate.containerKey] = perContainer
            end
            perContainer[candidate.entry] = assignment
            assignmentsByKey[assignment.placementKey] = assignment
            consumers[#consumers + 1] = assignment
        end
    end

    return {
        ownerByFrame = ownerByFrame,
        consumersByFrame = consumersByFrame,
        assignmentsByContainer = assignmentsByContainer,
        assignmentsByKey = assignmentsByKey,
    }
end

return CDMPlacementPlanner
