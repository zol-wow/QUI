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
    "itemWidth", "itemHeight", "sort", "dynamicLayout",
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

-- Expected Lua types for the scalar fields Import copies verbatim. Anything
-- listed here with the wrong type marks the payload malformed; unlisted
-- fields are only bounded by ValidateTree (plain data, capped size).
local GROUP_FIELD_TYPES = {
    enabled = "boolean", growDirection = "string", alignment = "string",
    spacing = "number", scale = "number", itemWidth = "number", itemHeight = "number",
    dynamicLayout = "boolean",
}
local DISPLAY_FIELD_TYPES = {
    enabled = "boolean", unitMode = "string", unit = "string", visibility = "string",
}

local function FieldsWellTyped(entry, types)
    for field, expected in pairs(types) do
        local value = entry[field]
        if value ~= nil and type(value) ~= expected then return false end
    end
    return true
end

-- Enum-like strings are checked against the values the editor can produce:
-- a mistyped anchor or aura type would otherwise persist and only fail
-- later, inside SetPoint or the aura-container filter APIs.
local function Set(list)
    local out = {}
    for i = 1, #list do out[list[i]] = true end
    return out
end
local ANCHOR_POINTS = Set({ "TOPLEFT", "TOP", "TOPRIGHT", "LEFT", "CENTER", "RIGHT",
    "BOTTOMLEFT", "BOTTOM", "BOTTOMRIGHT" })
local GROUP_FIELD_ENUMS = {
    growDirection = Set({ "RIGHT", "LEFT", "CENTER_H", "DOWN", "UP", "CENTER_V" }),
    alignment = Set({ "START", "CENTER", "END" }),
}
local DISPLAY_FIELD_ENUMS = {
    unitMode = Set({ "token", "cotank", "name" }),
    visibility = Set({ "active", "instance", "always" }),
}
local LAYOUT_FIELD_ENUMS = {
    direction = Set({ "LEFT", "RIGHT", "UP", "DOWN" }),
    alignment = Set({ "START", "CENTER", "END" }),
}
local ANCHOR_FIELD_ENUMS = { point = ANCHOR_POINTS, relative = ANCHOR_POINTS, relativePoint = ANCHOR_POINTS }
local ELEMENT_FIELD_ENUMS = {
    mode = Set({ "filterStrip", "tracked", "missingRaidBuff" }),
    auraType = Set({ "HELPFUL", "HARMFUL" }),
    displayType = Set({ "icon", "square", "bar", "healthTint", "border" }),
    growDirection = Set({ "LEFT", "RIGHT", "CENTER", "UP", "DOWN" }),
    anchor = ANCHOR_POINTS,
    swipeStyle = Set({ "radial", "horizontal", "vertical" }),
    applyToRoles = Set({ "all", "tank", "healer", "dps", "me" }),
    filterMode = Set({ "off", "flags", "classify", "classification", "whitelist" }),
    sortRule = Set({ "INDEX", "EXPIRY", "EXPIRY_ONLY", "NAME", "NAME_ONLY",
        "BIG_DEFENSIVE", "IMPORTANT_ONLY", "UF_DEBUFF" }),
    dispelFilterMode = Set({ "off", "include", "exclude" }),
    dispelBorderMode = Set({ "debuffs", "stealable", "all" }),
    tooltipAnchor = Set({ "ANCHOR_TOPRIGHT", "ANCHOR_TOP", "ANCHOR_TOPLEFT", "ANCHOR_RIGHT",
        "ANCHOR_LEFT", "ANCHOR_BOTTOMRIGHT", "ANCHOR_BOTTOM", "ANCHOR_BOTTOMLEFT", "ANCHOR_CURSOR" }),
}
local TEXT_FIELD_ENUMS = { anchor = ANCHOR_POINTS }
local BAR_FIELD_ENUMS = { orientation = Set({ "HORIZONTAL", "VERTICAL" }) }

local function FieldsInEnums(entry, enums)
    for field, allowed in pairs(enums) do
        local value = entry[field]
        if value ~= nil and not allowed[value] then return false end
    end
    return true
end

-- Nested records Import copies into the profile. Their scalar fields are
-- type-checked here so a hand-edited string cannot persist, say, a string
-- iconSize that later trips the element profile math on every refresh.
local ANCHOR_FIELD_TYPES = {
    point = "string", relative = "string", relativePoint = "string", parent = "string",
    offsetX = "number", offsetY = "number",
}
local LAYOUT_FIELD_TYPES = { direction = "string", alignment = "string", spacing = "number" }
local LOAD_FIELD_TYPES = { classes = "table", specs = "table", roles = "table", encounters = "table" }
local ELEMENT_FIELD_TYPES = {
    mode = "string", auraType = "string", displayType = "string", growDirection = "string",
    anchor = "string", swipeStyle = "string", applyToRoles = "string", filterMode = "string",
    sortRule = "string", dispelFilterMode = "string", dispelBorderMode = "string",
    tooltipAnchor = "string",
    iconSize = "number", spacing = "number", rowSpacing = "number", iconsPerRow = "number",
    maxIcons = "number", offsetX = "number", offsetY = "number", borderSize = "number",
    maxDurationSec = "number", tooltipAnchorX = "number", tooltipAnchorY = "number",
    enabled = "boolean", onlyMine = "boolean", hideSwipe = "boolean", reverseSwipe = "boolean",
    dynamicLayout = "boolean", hideBorder = "boolean", sortReverse = "boolean",
    rightClickCancel = "boolean", hidePermanent = "boolean", nameplateOnly = "boolean",
    classDetection = "boolean", tooltipHideInCombat = "boolean",
    spells = "table", onlyMineSpells = "table", duration = "table", stack = "table",
    bar = "table", border = "table", color = "table", auraSounds = "table",
    filterFlags = "table", classifications = "table", whitelist = "table", blacklist = "table",
    healthTint = "table", dispelColors = "table", dispelAssets = "table", pandemicGlow = "table",
    buffChecks = "table", borderColor = "table",
}
local TEXT_FIELD_TYPES = {
    show = "boolean", fontSize = "number", anchor = "string",
    offsetX = "number", offsetY = "number", color = "table",
}
local BAR_FIELD_TYPES = {
    thickness = "number", length = "number", orientation = "string",
    matchFrameSize = "boolean", hideBorder = "boolean", borderSize = "number",
    backgroundColor = "table", borderColor = "table", lowTimeColor = "table",
}
local BORDER_FIELD_TYPES = { thickness = "number" }
local ELEMENT_MODES = { filterStrip = true, tracked = true, missingRaidBuff = true }

local function ValidRecord(record, types, enums)
    if record == nil then return true end
    if type(record) ~= "table" or not FieldsWellTyped(record, types) then return false end
    return enums == nil or FieldsInEnums(record, enums)
end


local function ValidColor(color)
    if color == nil then return true end
    if type(color) ~= "table" then return false end
    for i = 1, 4 do
        if color[i] ~= nil and type(color[i]) ~= "number" then return false end
    end
    return true
end

local function ValidElement(element)
    if type(element) ~= "table" or not ELEMENT_MODES[element.mode] then return false end
    if not FieldsWellTyped(element, ELEMENT_FIELD_TYPES) then return false end
    if not FieldsInEnums(element, ELEMENT_FIELD_ENUMS) then return false end
    if type(element.spells) == "table" then
        for i = 1, #element.spells do
            if type(element.spells[i]) ~= "number" then return false end
        end
    end
    if not ValidRecord(element.duration, TEXT_FIELD_TYPES, TEXT_FIELD_ENUMS)
        or not ValidRecord(element.stack, TEXT_FIELD_TYPES, TEXT_FIELD_ENUMS)
        or not ValidRecord(element.bar, BAR_FIELD_TYPES, BAR_FIELD_ENUMS)
        or not ValidRecord(element.border, BORDER_FIELD_TYPES)
        or not ValidColor(element.color) or not ValidColor(element.borderColor)
        or not ValidColor(element.duration and element.duration.color)
        or not ValidColor(element.stack and element.stack.color) then
        return false
    end
    -- The element model's own validator has the final say (e.g. a tracked
    -- element needs at least one spell). It runs on a copy so a rejected
    -- payload leaves nothing behind, and behind SafeCall so a shape the type
    -- map above does not know about is rejected rather than raised.
    local E = ns.AuraElements
    if E and type(E.NormalizeElement) == "function" and type(E.Validate) == "function" then
        local function Probe()
            return E.Validate(E.NormalizeElement(CopyData(element)))
        end
        local ok, valid
        if type(ns.SafeCall) == "function" then
            ok, valid = ns.SafeCall("best-effort-style", Probe)
        else
            ok, valid = true, Probe()
        end
        if not ok or not valid then return false end
    end
    return true
end

local function ValidAuras(auras)
    if auras == nil then return true end
    if type(auras) ~= "table" then return false end
    if auras.enabled ~= nil and type(auras.enabled) ~= "boolean" then return false end
    if auras.elements == nil then return true end
    if type(auras.elements) ~= "table" then return false end
    for bucketKey, bucket in pairs(auras.elements) do
        if type(bucketKey) ~= "string" and type(bucketKey) ~= "number" then return false end
        if type(bucket) ~= "table" then return false end
        for i = 1, #bucket do
            if not ValidElement(bucket[i]) then return false end
        end
    end
    return true
end

local function MaxGroupDepth()
    local ad = AD()
    return (ad and tonumber(ad.MAX_GROUP_DEPTH)) or 6
end

local function OptionalTable(value)
    return value == nil or type(value) == "table"
end

local function OptionalString(value)
    return value == nil or type(value) == "string"
end

-- Shape check for a deserialized payload: every group and display entry must
-- be a table carrying a valid name and well-typed fields, and the root marker
-- (if any) must name a known kind. Decode runs this before handing the
-- payload to Import, so corrupted or hand-edited strings surface as the
-- advertised "malformed" error instead of a Lua error in the import button.
function Share.ValidatePayload(payload)
    if type(payload) ~= "table" then return false end
    if type(payload.groups) ~= "table" or type(payload.displays) ~= "table" then
        return false
    end
    if payload.root ~= nil then
        if type(payload.root) ~= "table" then return false end
        local kind = payload.root.kind
        if kind ~= "display" and kind ~= "group" then return false end
    end
    -- Group names double as identities (parents and display membership refer
    -- to them), so they must be unique within the payload.
    local groupByName = {}
    for i = 1, #payload.groups do
        local entry = payload.groups[i]
        if type(entry) ~= "table" or not ValidName(entry.name) then return false end
        if groupByName[entry.name] then return false end
        groupByName[entry.name] = entry
        if not OptionalString(entry.parent)
            or not ValidRecord(entry.anchor, ANCHOR_FIELD_TYPES, ANCHOR_FIELD_ENUMS) then
            return false
        end
        if not FieldsWellTyped(entry, GROUP_FIELD_TYPES) or not FieldsInEnums(entry, GROUP_FIELD_ENUMS) then
            return false
        end
    end
    -- Every parent must be a declared group, never the group itself, the
    -- chain must terminate (no cycles), and it must fit the runtime's nesting
    -- limit so every SetGroupParent during Import is guaranteed to succeed.
    local maxAncestors = MaxGroupDepth() - 1
    for i = 1, #payload.groups do
        local entry = payload.groups[i]
        local seen, current, ancestors = {}, entry, 0
        while current.parent ~= nil do
            local parent = groupByName[current.parent]
            if not parent or parent == current or seen[parent] then return false end
            seen[parent] = true
            ancestors = ancestors + 1
            if ancestors > maxAncestors then return false end
            current = parent
        end
    end
    local displayNames = {}
    for i = 1, #payload.displays do
        local entry = payload.displays[i]
        if type(entry) ~= "table" or not ValidName(entry.name) then return false end
        displayNames[entry.name] = true
        if not OptionalString(entry.group)
            or not ValidRecord(entry.anchor, ANCHOR_FIELD_TYPES, ANCHOR_FIELD_ENUMS)
            or not ValidRecord(entry.layout, LAYOUT_FIELD_TYPES, LAYOUT_FIELD_ENUMS)
            or not ValidRecord(entry.load, LOAD_FIELD_TYPES)
            or not ValidAuras(entry.auras) then
            return false
        end
        if entry.group ~= nil and not groupByName[entry.group] then return false end
        if not FieldsWellTyped(entry, DISPLAY_FIELD_TYPES) or not FieldsInEnums(entry, DISPLAY_FIELD_ENUMS) then
            return false
        end
    end
    -- A declared root must own everything in the payload: a group root means
    -- every group descends from it and every display sits in that subtree; a
    -- display root means exactly that one display and no groups.
    if payload.root ~= nil then
        local root = payload.root
        if root.kind == "group" then
            local rootGroup = groupByName[root.name]
            if not rootGroup then return false end
            for i = 1, #payload.groups do
                local current = payload.groups[i]
                while current ~= rootGroup and current.parent ~= nil do
                    current = groupByName[current.parent]
                end
                if current ~= rootGroup then return false end
            end
            for i = 1, #payload.displays do
                if payload.displays[i].group == nil then return false end
            end
        elseif root.kind == "display" then
            if #payload.groups ~= 0 or #payload.displays ~= 1
                or payload.displays[1].name ~= root.name or payload.displays[1].group ~= nil then
                return false
            end
        end
    end
    return true
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
    if not Share.ValidatePayload(payload) then
        return false, nil, "Malformed aura display string."
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
-- Import mutates the live store and anchor table in place; a snapshot lets a
-- failure midway restore both so nothing half-imported is left behind.
local function SnapshotState(store)
    local profile = Profile()
    return {
        displays = CopyData(store.displays), order = CopyData(store.order),
        groups = CopyData(store.groups),
        anchors = profile and CopyData(profile.frameAnchoring) or nil,
    }
end

local function RestoreState(store, snapshot)
    store.displays, store.order, store.groups = snapshot.displays, snapshot.order, snapshot.groups
    local profile = Profile()
    if profile then profile.frameAnchoring = snapshot.anchors end
end

function Share.Import(payload)
    if not Share.ValidatePayload(payload) then
        return nil, "Malformed aura display string."
    end
    local ad = AD()
    local store = ad and ad.Store and ad.Store()
    if not store then return nil, "Aura displays are not available." end
    local snapshot = SnapshotState(store)

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
        if parent and not ad.SetGroupParent(nameMap[entry.name], parent) then
            RestoreState(store, snapshot)
            return nil, "Malformed aura display string."
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
