local ADDON_NAME, ns = ...

-- Export/import strings for Aura Displays: a single display, or a group with
-- its whole subtree (nested groups + displays), WeakAuras-style. UI-free and
-- headless-testable; the options panel provides the copy/paste surfaces.
--
-- String format matches profile_io: "AD1:" .. EncodeForPrint(Deflate(AceSerialize(payload))).

local Share = ns.QUI_AuraDisplayShare or {}
ns.QUI_AuraDisplayShare = Share

Share.PREFIX = "AD1"
Share.PAYLOAD_TYPE = "auraDisplaysShare"
Share.VERSION = 1

local MAX_ENTITIES = 400
local MAX_NAME_LENGTH = 120
local MAX_TREE_DEPTH = 12
local MAX_TREE_NODES = 60000

local GROUP_FIELDS = {
    "enabled", "growDirection", "alignment", "spacing", "scale",
    "itemWidth", "itemHeight", "sort",
}

local DISPLAY_FIELDS = {
    "enabled", "unitMode", "unit", "visibility",
}

local function AD()
    return ns.QUI_AuraDisplays
end

local function Libs()
    local LibStub = _G.LibStub
    if not LibStub then return nil, nil end
    return LibStub("AceSerializer-3.0", true), LibStub("LibDeflate", true)
end

local function Profile()
    local H = ns.Helpers
    if H and type(H.GetProfile) == "function" then return H.GetProfile() end
    return nil
end

-- Deep copy for plain data; keys named in `stripKeys` are dropped at every
-- level (element ids and aura-store bookkeeping flags re-mint on import).
local AURA_STRIP_KEYS = {
    id = true,
    _elementIDsBackfilled = true,
    _specBucketsNormalized = true,
    elementsSeeded = true,
}

local function CopyData(value, stripKeys)
    if type(value) ~= "table" then return value end
    local out = {}
    for k, v in pairs(value) do
        if not (stripKeys and stripKeys[k]) then
            out[k] = CopyData(v, stripKeys)
        end
    end
    return out
end

local function CopyAnchor(anchorKey)
    local profile = Profile()
    local record = anchorKey and profile
        and type(profile.frameAnchoring) == "table"
        and profile.frameAnchoring[anchorKey]
    if type(record) ~= "table" then return nil end
    return CopyData(record)
end

local function SerializeDisplay(display, groupNameOut)
    local ad = AD()
    local out = {
        name = display.name,
        group = groupNameOut,
        layout = CopyData(display.layout),
        load = CopyData(display.load),
        auras = CopyData(display.auras, AURA_STRIP_KEYS),
        anchor = CopyAnchor(ad.ANCHOR_PREFIX .. display.id),
    }
    for i = 1, #DISPLAY_FIELDS do
        out[DISPLAY_FIELDS[i]] = display[DISPLAY_FIELDS[i]]
    end
    return out
end

local function SerializeGroup(name, parentNameOut)
    local ad = AD()
    local group = ad.GetGroup(name, false)
    local out = {
        name = name,
        parent = parentNameOut,
        anchor = CopyAnchor(ad.GroupAnchorKey(name, false)),
    }
    if type(group) == "table" then
        for i = 1, #GROUP_FIELDS do
            out[GROUP_FIELDS[i]] = group[GROUP_FIELDS[i]]
        end
    end
    return out
end

function Share.BuildDisplayPayload(displayID)
    local ad = AD()
    local display = ad and ad.GetDisplay(displayID)
    if not display then return nil, "unknown display" end
    return {
        type = Share.PAYLOAD_TYPE,
        version = Share.VERSION,
        root = { kind = "display", name = display.name },
        groups = {},
        displays = { SerializeDisplay(display, nil) },
    }
end

function Share.BuildGroupPayload(groupName)
    local ad = AD()
    if not (ad and ad.GetGroup(groupName, false)) then return nil, "unknown group" end
    local payload = {
        type = Share.PAYLOAD_TYPE,
        version = Share.VERSION,
        root = { kind = "group", name = groupName },
        groups = {},
        displays = {},
    }
    local visited = {}
    local function AddGroup(name, parentNameOut)
        if visited[name] then return end
        visited[name] = true
        payload.groups[#payload.groups + 1] = SerializeGroup(name, parentNameOut)
        local members = ad.GroupMembers(name)
        for i = 1, #members do
            payload.displays[#payload.displays + 1] = SerializeDisplay(members[i], name)
        end
        local children = ad.GroupChildren(name)
        for i = 1, #children do
            AddGroup(children[i], name)
        end
    end
    AddGroup(groupName, nil)
    return payload
end

function Share.Encode(payload)
    local AceSerializer, LibDeflate = Libs()
    if not AceSerializer or not LibDeflate then
        return nil, "Export requires AceSerializer-3.0 and LibDeflate."
    end
    local serialized = AceSerializer:Serialize(payload)
    local compressed = serialized and LibDeflate:CompressDeflate(serialized)
    local encoded = compressed and LibDeflate:EncodeForPrint(compressed)
    if not encoded then return nil, "Failed to encode aura display string." end
    return Share.PREFIX .. ":" .. encoded
end

-- Bounded structural check on decoded payloads: plain data only, capped depth
-- and node count, so a hostile string cannot smuggle in anything surprising.
local function ValidateTree(value, depth, budget)
    local t = type(value)
    if t == "number" or t == "string" or t == "boolean" or t == "nil" then
        return budget
    end
    if t ~= "table" then return nil end
    if depth >= MAX_TREE_DEPTH then return nil end
    for k, v in pairs(value) do
        budget = budget - 1
        if budget <= 0 then return nil end
        local kt = type(k)
        if kt ~= "string" and kt ~= "number" then return nil end
        budget = ValidateTree(v, depth + 1, budget)
        if not budget then return nil end
    end
    return budget
end

local function ValidName(name)
    return type(name) == "string" and name ~= "" and #name <= MAX_NAME_LENGTH
end

function Share.Decode(str)
    local AceSerializer, LibDeflate = Libs()
    if not AceSerializer or not LibDeflate then
        return false, nil, "Import requires AceSerializer-3.0 and LibDeflate."
    end
    if type(str) ~= "string" then return false, nil, "Paste an aura display string." end
    str = str:gsub("%s+", "")
    if str == "" then return false, nil, "Paste an aura display string." end
    local prefix, body = str:match("^([A-Z]+%d+):(.+)$")
    if prefix and prefix ~= Share.PREFIX then
        return false, nil,
            ("This is a %s string, not an aura display export."):format(prefix)
    end
    local decoded = LibDeflate:DecodeForPrint(body or str)
    if not decoded then return false, nil, "Could not decode string (maybe corrupted)." end
    local decompressed = LibDeflate:DecompressDeflate(decoded)
    if not decompressed then return false, nil, "Could not decompress data." end
    local ok, payload = AceSerializer:Deserialize(decompressed)
    if not ok or type(payload) ~= "table" then
        return false, nil, "Could not read data (maybe corrupted)."
    end
    if payload.type ~= Share.PAYLOAD_TYPE then
        return false, nil, "This string does not contain aura displays."
    end
    if type(payload.version) ~= "number" or payload.version > Share.VERSION then
        return false, nil, "This string was made by a newer QUI version."
    end
    if type(payload.groups) ~= "table" or type(payload.displays) ~= "table" then
        return false, nil, "Malformed aura display string."
    end
    if #payload.groups + #payload.displays == 0
        or #payload.groups + #payload.displays > MAX_ENTITIES then
        return false, nil, "Malformed aura display string."
    end
    if not ValidateTree(payload, 0, MAX_TREE_NODES) then
        return false, nil, "Malformed aura display string."
    end
    for i = 1, #payload.groups do
        if not ValidName(payload.groups[i].name) then
            return false, nil, "Malformed aura display string."
        end
    end
    for i = 1, #payload.displays do
        if not ValidName(payload.displays[i].name) then
            return false, nil, "Malformed aura display string."
        end
    end
    return true, payload
end

local function GroupNameInUse(store, name)
    if store.groups[name] ~= nil then return true end
    for _, display in pairs(store.displays) do
        if display.group == name then return true end
    end
    return false
end

local function UniqueName(base, taken)
    base = base:sub(1, MAX_NAME_LENGTH)
    if not taken(base) then return base, false end
    local n = 2
    while true do
        local candidate = base .. " " .. n
        if not taken(candidate) then return candidate, true end
        n = n + 1
    end
end

local function WriteAnchor(anchorKey, anchor)
    if not anchorKey or type(anchor) ~= "table" then return end
    local profile = Profile()
    if not profile then return end
    profile.frameAnchoring = profile.frameAnchoring or {}
    profile.frameAnchoring[anchorKey] = CopyData(anchor)
end

-- Recreates the payload's groups and displays. Duplicate group or display
-- names get " 2"-style suffixes, WeakAuras-style. Returns a summary table.
function Share.Import(payload)
    local ad = AD()
    local store = ad and ad.Store and ad.Store()
    if not store then return nil, "Aura displays are not available." end

    local summary = { groups = 0, displays = 0, renamed = 0 }

    -- Groups first: mint collision-free names, then link parents.
    local nameMap = {}
    local claimed = {}
    for i = 1, #payload.groups do
        local entry = payload.groups[i]
        local newName, renamed = UniqueName(entry.name, function(candidate)
            return claimed[candidate] or GroupNameInUse(store, candidate)
        end)
        claimed[newName] = true
        nameMap[entry.name] = newName
        if renamed then summary.renamed = summary.renamed + 1 end

        local group = ad.GetGroup(newName, true)
        for f = 1, #GROUP_FIELDS do
            local field = GROUP_FIELDS[f]
            if entry[field] ~= nil then group[field] = CopyData(entry[field]) end
        end
        summary.groups = summary.groups + 1
    end
    for i = 1, #payload.groups do
        local entry = payload.groups[i]
        local parent = entry.parent and nameMap[entry.parent] or nil
        if parent then
            ad.SetGroupParent(nameMap[entry.name], parent)
        end
    end

    -- Displays: names are only unique among displays; groups map through.
    local displayNameTaken = {}
    local existing = ad.OrderedDisplays()
    for i = 1, #existing do
        displayNameTaken[existing[i].name or ""] = true
    end
    for i = 1, #payload.displays do
        local entry = payload.displays[i]
        local newName, renamed = UniqueName(entry.name, function(candidate)
            return displayNameTaken[candidate] == true
        end)
        displayNameTaken[newName] = true
        if renamed then summary.renamed = summary.renamed + 1 end

        local groupName = entry.group and nameMap[entry.group] or nil
        local display = ad.NewDisplay(newName, groupName)
        if display then
            for f = 1, #DISPLAY_FIELDS do
                local field = DISPLAY_FIELDS[f]
                if entry[field] ~= nil then display[field] = CopyData(entry[field]) end
            end
            if type(entry.layout) == "table" then display.layout = CopyData(entry.layout) end
            if type(entry.load) == "table" then display.load = CopyData(entry.load) end
            if type(entry.auras) == "table" then display.auras = CopyData(entry.auras) end
            if not groupName then
                WriteAnchor(ad.ANCHOR_PREFIX .. display.id, entry.anchor)
            end
            summary.displays = summary.displays + 1
            if not summary.rootName and payload.root
                and payload.root.kind == "display" then
                summary.rootKind = "display"
                summary.rootName = newName
                summary.rootID = display.id
            end
        end
    end

    -- The imported root group keeps its (possibly renamed) identity and gets
    -- the exported screen position; nested groups flow inside it.
    for i = 1, #payload.groups do
        local entry = payload.groups[i]
        if not entry.parent or not nameMap[entry.parent] then
            local newName = nameMap[entry.name]
            WriteAnchor(ad.GroupAnchorKey(newName, true), entry.anchor)
            if not summary.rootName then
                summary.rootKind = "group"
                summary.rootName = newName
            end
        end
    end

    return summary
end

function Share.ImportString(str)
    local ok, payload, err = Share.Decode(str)
    if not ok then return nil, err end
    return Share.Import(payload)
end

function Share.ExportDisplayString(displayID)
    local payload, err = Share.BuildDisplayPayload(displayID)
    if not payload then return nil, err end
    return Share.Encode(payload)
end

function Share.ExportGroupString(groupName)
    local payload, err = Share.BuildGroupPayload(groupName)
    if not payload then return nil, err end
    return Share.Encode(payload)
end

return Share
