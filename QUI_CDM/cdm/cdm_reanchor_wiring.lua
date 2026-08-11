local _, ns = ...

local CDMReanchorWiring = {}
ns.CDMReanchorWiring = CDMReanchorWiring

local VIEWER_GLOBAL_FOR_KEY = {
    essential  = "EssentialCooldownViewer",
    utility    = "UtilityCooldownViewer",
    buff       = "BuffIconCooldownViewer",
    trackedBar = "BuffBarCooldownViewer",
}

local InstanceMT = { __index = CDMReanchorWiring }
local _issecretvalue = issecretvalue or function() return false end

function CDMReanchorWiring.New(deps)
    deps = deps or {}
    local self = {
        _deps = deps,
        _bridge = deps.bridge,
        _identCache = setmetatable({}, { __mode = "k" }),
    }
    return setmetatable(self, InstanceMT)
end

function CDMReanchorWiring:GetViewerForKey(containerKey)
    if self._deps.getViewerForKey then
        return self._deps.getViewerForKey(containerKey)
    end
    local name = VIEWER_GLOBAL_FOR_KEY[containerKey]
    if not name then return nil end
    return _G[name]
end

function CDMReanchorWiring:GetViewersForKey(containerKey)
    if self._deps.getViewersForKey then
        return self._deps.getViewersForKey(containerKey) or {}
    end

    local out = {}
    if containerKey == "essential" or containerKey == "utility" then
        local primary = self:GetViewerForKey(containerKey)
        local siblingKey = (containerKey == "essential") and "utility" or "essential"
        local sibling = self:GetViewerForKey(siblingKey)
        if primary then out[#out + 1] = primary end
        if sibling and sibling ~= primary then out[#out + 1] = sibling end
        return out
    end

    local viewer = self:GetViewerForKey(containerKey)
    if viewer then out[#out + 1] = viewer end
    return out
end

local function appendID(list, id)
    if id ~= nil then
        list[#list + 1] = id
    end
end

local function isSafeNumber(value)
    return type(value) == "number" and not _issecretvalue(value)
end

local function readFrameSpellID(frame, method)
    if not frame then return nil end
    local fn = frame[method]
    if type(fn) ~= "function" then return nil end
    local ok, sid = pcall(fn, frame)
    if ok and isSafeNumber(sid) then return sid end
    return nil
end

local function toBaseSpellID(index, spellID)
    if not isSafeNumber(spellID) then return nil end
    if index and index.ToBaseSpellID then
        return index.ToBaseSpellID(spellID)
    end
    return spellID
end

local function claimByKey(map, key, frame)
    if key ~= nil and map[key] == nil then
        map[key] = frame
    end
end

local function forEachCooldownInfoID(index, info, callback)
    if type(info) ~= "table" then return end
    if index and index.ForEachCooldownInfoID then
        index.ForEachCooldownInfoID(info, callback)
        return
    end
    callback(info.overrideTooltipSpellID)
    callback(info.overrideSpellID)
    callback(info.spellID)
    if type(info.linkedSpellIDs) == "table" then
        for i = 1, #info.linkedSpellIDs do
            callback(info.linkedSpellIDs[i])
        end
    end
end

local function addFrameSpellAlias(frameMap, index, spellID, frame)
    local base = toBaseSpellID(index, spellID)
    if base then
        claimByKey(frameMap._bySpell, base, frame)
    end
end

local function addFrameInfoAliases(frameMap, index, frame, info)
    if type(info) ~= "table" then return end

    if isSafeNumber(info.equipSlot) then
        claimByKey(frameMap._byEquipSlot, info.equipSlot, frame)
    end
    if isSafeNumber(info.spellCategoryID) then
        claimByKey(frameMap._bySpellCategory, info.spellCategoryID, frame)
    end
    forEachCooldownInfoID(index, info, function(id)
        addFrameSpellAlias(frameMap, index, id, frame)
    end)
end

local function newFrameMap()
    local map, items = {}, {}
    map._bySpell = {}
    map._byEquipSlot = {}
    map._bySpellCategory = {}
    map._canonicalByFrame = {}
    map._canonicalFrames = {}
    return map, items
end

local function identFor(cache, frame)
    local ident = cache[frame]
    if not ident then
        ident = {}
        cache[frame] = ident
    end
    return ident
end

function CDMReanchorWiring:AddViewerToFrameMap(map, items, viewer)
    if not viewer then return end
    local bridge = self._bridge
    local index = self._deps.index
    local cache = self._identCache
    local viewerItems = bridge:EnumerateItems(viewer)
    for i = 1, #viewerItems do
        local frame = viewerItems[i]
        items[#items + 1] = frame
        local cached = cache and cache[frame]
        local cooldownID = bridge:ResolveIdentity(frame)
        if cooldownID ~= nil then
            if cache then
                local ident = identFor(cache, frame)
                if ident.cooldownID ~= nil and ident.cooldownID ~= cooldownID then
                    ident.spellID = nil
                    ident.canonical = nil
                end
                ident.cooldownID = cooldownID
            end
        elseif cached then
            cooldownID = cached.cooldownID
        end
        if cooldownID ~= nil then
            claimByKey(map, cooldownID, frame)
        end
        if bridge.GetFrameCooldownInfo then
            addFrameInfoAliases(map, index, frame, bridge:GetFrameCooldownInfo(frame, cooldownID))
        end
        if frame and frame.GetSpellID then
            local spellID = readFrameSpellID(frame, "GetSpellID")
            if spellID ~= nil then
                if cache then
                    identFor(cache, frame).spellID = spellID
                end
            elseif cached then
                spellID = cached.spellID
            end
            if spellID ~= nil then
                addFrameSpellAlias(map, index, spellID, frame)
            end
        end
        if frame and map._canonicalByFrame and map._canonicalByFrame[frame] == nil then
            local liveCanonical = readFrameSpellID(frame, "GetAuraSpellID")
                or readFrameSpellID(frame, "GetSpellID")
            local canonical = liveCanonical
            if canonical == nil and cached then
                canonical = cached.canonical
            end
            if liveCanonical ~= nil and cache then
                identFor(cache, frame).canonical = liveCanonical
            end
            if canonical ~= nil then
                map._canonicalByFrame[frame] = canonical
                map._canonicalFrames[#map._canonicalFrames + 1] = frame
            end
        end
    end
end

function CDMReanchorWiring:BuildFrameMap(viewer)
    local map, items = newFrameMap()
    self:AddViewerToFrameMap(map, items, viewer)
    return map, items
end

function CDMReanchorWiring:BuildFrameMapForViewers(viewers)
    local map, items = newFrameMap()
    if type(viewers) ~= "table" then return map, items end
    for i = 1, #viewers do
        self:AddViewerToFrameMap(map, items, viewers[i])
    end
    return map, items
end

function CDMReanchorWiring:ResolveEntryCooldownID(entry, containerKey)
    if self._deps.resolveEntryCooldownID then
        return self._deps.resolveEntryCooldownID(entry, containerKey)
    end
    local index = self._deps.index
    if not index then return nil end

    local etype = entry.type
    if etype == "slot" or etype == "trinket" then
        local rec = index.GetOrderedByEquipSlotForContainer
            and index.GetOrderedByEquipSlotForContainer(containerKey, entry.id)
        if not rec and index.GetOrderedByEquipSlot then
            rec = index.GetOrderedByEquipSlot(entry.id)
        end
        if not rec and index.GetByEquipSlot then
            rec = index.GetByEquipSlot(entry.id)
        end
        return (rec and rec.cooldownID) or nil
    elseif etype == "consumable" then
        local rec = index.GetOrderedByCategoryForContainer
            and index.GetOrderedByCategoryForContainer(containerKey, entry.id)
        if not rec and index.GetOrderedByCategory then
            rec = index.GetOrderedByCategory(entry.id)
        end
        if not rec and index.GetByCategory then
            rec = index.GetByCategory(entry.id)
        end
        return (rec and rec.cooldownID) or nil
    end

    local ids = {}
    appendID(ids, entry.overrideSpellID)
    appendID(ids, entry.spellID)
    appendID(ids, entry.id)
    if type(entry.linkedSpellIDs) == "table" then
        for i = 1, #entry.linkedSpellIDs do
            appendID(ids, entry.linkedSpellIDs[i])
        end
    end

    for i = 1, #ids do
        local id = ids[i]
        if index.IsUsableID(id) then
            local rec = index.GetOrderedForContainer
                and index.GetOrderedForContainer(containerKey, id)
            if not rec and index.GetOrdered then
                rec = index.GetOrdered(id)
            end
            if not rec then
                rec = index.Get(id)
            end
            if rec and rec.cooldownID ~= nil then
                return rec.cooldownID
            end
        end
    end
    return nil
end

function CDMReanchorWiring:ResolveEntryFrame(entry, frameMap)
    if not entry or type(frameMap) ~= "table" then return nil end

    local etype = entry.type
    if etype == "slot" or etype == "trinket" then
        local bySlot = frameMap._byEquipSlot
        return bySlot and bySlot[entry.id] or nil
    elseif etype == "consumable" then
        local byCategory = frameMap._bySpellCategory
        return byCategory and byCategory[entry.id] or nil
    end

    local bySpell = frameMap._bySpell
    if not bySpell then return nil end

    local index = self._deps.index
    local ids = {}
    appendID(ids, entry.overrideSpellID)
    appendID(ids, entry.spellID)
    appendID(ids, entry.id)
    if type(entry.linkedSpellIDs) == "table" then
        for i = 1, #entry.linkedSpellIDs do
            appendID(ids, entry.linkedSpellIDs[i])
        end
    end

    for i = 1, #ids do
        local base = toBaseSpellID(index, ids[i])
        local frame = base and bySpell[base]
        if frame then
            return frame
        end
    end
    return nil
end

function CDMReanchorWiring:AssignExactFrames(curated, frameMap, claimedFrames)
    local exactFrame = {}
    local canonicalByFrame = frameMap._canonicalByFrame
    local canonicalFrames = frameMap._canonicalFrames
    if type(canonicalByFrame) ~= "table" or type(canonicalFrames) ~= "table"
        or #canonicalFrames == 0 then
        return exactFrame
    end

    for i = 1, #curated do
        local entry = curated[i]
        local etype = entry.type
        if etype ~= "slot" and etype ~= "trinket" and etype ~= "consumable" then
            local ids = {}
            appendID(ids, entry.overrideSpellID)
            appendID(ids, entry.spellID)
            appendID(ids, entry.id)
            for k = 1, #ids do
                local target = ids[k]
                if isSafeNumber(target) then
                    for f = 1, #canonicalFrames do
                        local frame = canonicalFrames[f]
                        if not claimedFrames[frame] then
                            local sid = canonicalByFrame[frame]
                            if isSafeNumber(sid) and sid == target then
                                exactFrame[entry] = frame
                                claimedFrames[frame] = true
                                break
                            end
                        end
                    end
                end
                if exactFrame[entry] then break end
            end
        end
    end
    return exactFrame
end

function CDMReanchorWiring:MatchCuratedToFrames(curated, frameMap, containerKey)
    local matched, frameless, claimedFrames = {}, {}, {}
    local exactFrame = self:AssignExactFrames(curated, frameMap, claimedFrames)
    for i = 1, #curated do
        local entry = curated[i]
        local frame = exactFrame[entry]
        if frame then
            matched[#matched + 1] = { entry = entry, frame = frame }
        else
            local cooldownID = self:ResolveEntryCooldownID(entry, containerKey)
            frame = (cooldownID ~= nil) and frameMap[cooldownID] or nil
            if not frame then
                frame = self:ResolveEntryFrame(entry, frameMap)
            end
            if frame and not claimedFrames[frame] then
                claimedFrames[frame] = true
                matched[#matched + 1] = { entry = entry, frame = frame }
            else
                frameless[#frameless + 1] = entry
            end
        end
    end
    return matched, frameless, claimedFrames
end
