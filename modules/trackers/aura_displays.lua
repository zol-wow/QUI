local ADDON_NAME, ns = ...

local AD = ns.QUI_AuraDisplays or {}
ns.QUI_AuraDisplays = AD
_G.QUI = _G.QUI or {}
_G.QUI.AuraDisplays = AD

local DEFAULTS = { enabled = true }

local DISPLAY_LAYOUT_DEFAULTS = {
    direction = "RIGHT",
    alignment = "CENTER",
    spacing = 2,
}

local NON_GAMEPLAY_INSTANCE_TYPES = {
    none = true,
    neighborhood = true,
    interior = true,
}

AD.ANCHOR_PREFIX = "auraDisplay_"
AD.GROUP_ANCHOR_PREFIX = "auraDisplayGroup_"

local function Helpers()
    return ns.Helpers
end

local function Store()
    local H = Helpers()
    if not H or type(H.GetModuleSettings) ~= "function" then return nil end
    if type(H.GetProfile) ~= "function" or not H.GetProfile() then return nil end
    local store = H.GetModuleSettings("auraDisplays", DEFAULTS)
    if type(store) ~= "table" then return nil end
    if type(store.displays) ~= "table" then store.displays = {} end
    if type(store.order) ~= "table" then store.order = {} end
    if type(store.groups) ~= "table" then store.groups = {} end
    return store
end
AD.Store = Store

local function DeepCopy(value)
    if type(value) ~= "table" then return value end
    local out = {}
    for k, v in pairs(value) do out[k] = DeepCopy(v) end
    return out
end

local function HighestID(store)
    local highest = 0
    for id in pairs(store.displays) do
        local n = tonumber(tostring(id):match("^d(%d+)$"))
        if n and n > highest then highest = n end
    end
    for i = 1, #store.order do
        local n = tonumber(tostring(store.order[i]):match("^d(%d+)$"))
        if n and n > highest then highest = n end
    end
    return highest
end

local function NextID(store)
    if type(store.nextID) ~= "number" then
        store.nextID = HighestID(store)
    end
    store.nextID = store.nextID + 1
    return "d" .. tostring(store.nextID)
end

function AD.NewDisplay(name, group)
    local store = Store()
    if not store then return nil end
    local id = NextID(store)
    local display = {
        id = id,
        name = (type(name) == "string" and name ~= "") and name or id,
        group = group,
        enabled = true,
        visibility = "active",
        unitMode = "token",
        unit = "player",
        layout = {
            direction = DISPLAY_LAYOUT_DEFAULTS.direction,
            alignment = DISPLAY_LAYOUT_DEFAULTS.alignment,
            spacing = DISPLAY_LAYOUT_DEFAULTS.spacing,
        },
        load = { classes = {}, specs = {}, roles = {}, encounters = {} },
        auras = {},
    }
    store.displays[id] = display
    store.order[#store.order + 1] = id
    return display
end

function AD.GetDisplay(id)
    local store = Store()
    return store and store.displays[id] or nil
end

function AD.DeleteDisplay(id)
    local store = Store()
    if not store or not store.displays[id] then return false end
    store.displays[id] = nil
    for i = #store.order, 1, -1 do
        if store.order[i] == id then table.remove(store.order, i) end
    end
    local H = Helpers()
    local profile = H and type(H.GetProfile) == "function" and H.GetProfile() or nil
    if profile and type(profile.frameAnchoring) == "table" then
        profile.frameAnchoring[AD.ANCHOR_PREFIX .. id] = nil
    end
    return true
end

function AD.DuplicateDisplay(id, newName)
    local store = Store()
    if not store then return nil end
    local source = store.displays[id]
    if not source then return nil end
    local copy = DeepCopy(source)
    copy.id = NextID(store)
    copy.name = (type(newName) == "string" and newName ~= "") and newName or copy.id
    if type(copy.auras) == "table" then
        copy.auras._elementIDsBackfilled = nil
        if type(copy.auras.elements) == "table" then
            for _, bucket in pairs(copy.auras.elements) do
                if type(bucket) == "table" then
                    for i = 1, #bucket do
                        if type(bucket[i]) == "table" then bucket[i].id = nil end
                    end
                end
            end
        end
    end
    store.displays[copy.id] = copy
    store.order[#store.order + 1] = copy.id
    return copy
end

function AD.RenameDisplay(id, newName)
    local display = AD.GetDisplay(id)
    if not display or type(newName) ~= "string" then return false end
    display.name = newName ~= "" and newName or id
    AD.RegisterLayoutElement(display)
    return true
end

function AD.MoveDisplayWithinGroup(id, delta)
    local store = Store()
    if not store or type(delta) ~= "number" or delta == 0 then return false end
    local display = store.displays[id]
    if not display then return false end
    local group = display.group

    local indices = {}
    for i = 1, #store.order do
        local sibling = store.displays[store.order[i]]
        if sibling and sibling.group == group then
            indices[#indices + 1] = i
        end
    end

    local pos
    for i = 1, #indices do
        if store.order[indices[i]] == id then
            pos = i
            break
        end
    end
    if not pos then return false end

    local targetPos = pos + delta
    if targetPos < 1 or targetPos > #indices then return false end

    local i1, i2 = indices[pos], indices[targetPos]
    store.order[i1], store.order[i2] = store.order[i2], store.order[i1]
    return true
end

function AD.OrderedDisplays()
    local store = Store()
    local out = {}
    if not store then return out end
    for i = 1, #store.order do
        local display = store.displays[store.order[i]]
        if display then out[#out + 1] = display end
    end
    return out
end

local function GroupKey(name)
    if type(name) ~= "string" or name == "" then return nil end
    return name
end

local GROUP_DEFAULTS = {
    collapsed = false,
    enabled = true,
    growDirection = "RIGHT",
    alignment = "CENTER",
    spacing = 4,
    scale = 1,
    itemWidth = 0,
    itemHeight = 0,
    dynamicLayout = false,
}

local function HighestGroupID(store)
    local highest = 0
    for _, group in pairs(store.groups) do
        if type(group) == "table" then
            local n = tonumber(tostring(group.id):match("^g(%d+)$"))
            if n and n > highest then highest = n end
        end
    end
    return highest
end

local function NextGroupID(store)
    store.nextGroupID = math.max(tonumber(store.nextGroupID) or 0, HighestGroupID(store)) + 1
    return "g" .. tostring(store.nextGroupID)
end

local function NormalizeGroup(store, group)
    if type(group.id) ~= "string" or not group.id:match("^g%d+$") then
        group.id = NextGroupID(store)
    end
    for key, value in pairs(GROUP_DEFAULTS) do
        if group[key] == nil then group[key] = value end
    end
    return group
end

local function EnsureGroup(store, key)
    local group = store.groups[key]
    if type(group) ~= "table" then
        group = {}
        store.groups[key] = group
    end
    return NormalizeGroup(store, group)
end

function AD.GetGroup(groupName, create)
    local key = GroupKey(groupName)
    local store = Store()
    if not store or key == nil then return nil end
    local group = store.groups[key]
    if group == nil and not create then return nil end
    return EnsureGroup(store, key)
end

function AD.GroupAnchorKey(groupName, create)
    local group = AD.GetGroup(groupName, create)
    return group and (AD.GROUP_ANCHOR_PREFIX .. group.id) or nil
end

function AD.GroupMembers(groupName)
    local key = GroupKey(groupName)
    local out = {}
    if key == nil then return out end
    local displays = AD.OrderedDisplays()
    for i = 1, #displays do
        if displays[i].group == key then out[#out + 1] = displays[i] end
    end
    return out
end

-- Nested groups: `group.parent` names another group; parent pointers form the
-- tree. Every walk carries a visited set — SetGroupParent refuses cycles, but
-- imported or hand-edited saved variables must never hang the client.
local MAX_GROUP_DEPTH = 6
AD.MAX_GROUP_DEPTH = MAX_GROUP_DEPTH

local function ParentKeyOf(store, key)
    local group = store and store.groups[key]
    if type(group) ~= "table" then return nil end
    return GroupKey(group.parent)
end

function AD.GroupParent(groupName)
    local store = Store()
    local key = GroupKey(groupName)
    if not store or key == nil then return nil end
    return ParentKeyOf(store, key)
end

-- Height of the subtree rooted at `key` (1 for a group with no children).
local function GroupSubtreeHeight(store, key, seen)
    seen = seen or {}
    if seen[key] then return 0 end
    seen[key] = true
    local height = 1
    for name, group in pairs(store.groups) do
        if type(group) == "table" and name ~= key and GroupKey(group.parent) == key then
            height = math.max(height, 1 + GroupSubtreeHeight(store, name, seen))
        end
    end
    return height
end

local function GroupDepth(store, key)
    local depth, seen, current = 0, {}, key
    while current and not seen[current] do
        seen[current] = true
        depth = depth + 1
        current = ParentKeyOf(store, current)
    end
    return depth
end

-- True when `ancestorName` appears strictly above `groupName` in the tree.
function AD.GroupIsAncestor(ancestorName, groupName)
    local store = Store()
    local ancestor, key = GroupKey(ancestorName), GroupKey(groupName)
    if not store or ancestor == nil or key == nil or ancestor == key then return false end
    local seen, current = {}, ParentKeyOf(store, key)
    while current and not seen[current] do
        if current == ancestor then return true end
        seen[current] = true
        current = ParentKeyOf(store, current)
    end
    return false
end

function AD.RootGroupName(groupName)
    local store = Store()
    local key = GroupKey(groupName)
    if not store or key == nil then return nil end
    local seen, current = {}, key
    while true do
        seen[current] = true
        local parent = ParentKeyOf(store, current)
        if not parent or seen[parent] then return current end
        current = parent
    end
end

function AD.SetGroupParent(groupName, parentName)
    local store = Store()
    local key = GroupKey(groupName)
    if not store or key == nil then return false, "invalid" end
    local group = EnsureGroup(store, key)
    local parent = GroupKey(parentName)
    if parent == nil then
        group.parent = nil
        return true
    end
    if parent == key or AD.GroupIsAncestor(key, parent) then
        return false, "cycle"
    end
    EnsureGroup(store, parent)
    -- The moved group brings its whole subtree along, so the deepest path
    -- after the move is the parent's depth plus that subtree's height.
    if GroupDepth(store, parent) + GroupSubtreeHeight(store, key) > MAX_GROUP_DEPTH then
        return false, "depth"
    end
    group.parent = parent
    return true
end

-- Child groups of `parentName` (nil for root groups), in layout order.
function AD.GroupChildren(parentName)
    local store = Store()
    local out = {}
    if not store then return out end
    local parent = GroupKey(parentName)
    for name, group in pairs(store.groups) do
        if type(group) == "table" and name ~= parent
            and GroupKey(group.parent) == parent then
            out[#out + 1] = name
        end
    end
    table.sort(out, function(a, b)
        local sa = tonumber(store.groups[a].sort) or math.huge
        local sb = tonumber(store.groups[b].sort) or math.huge
        if sa ~= sb then return sa < sb end
        return a < b
    end)
    return out
end

function AD.MoveGroupWithinParent(groupName, delta)
    local store = Store()
    local key = GroupKey(groupName)
    if not store or key == nil or type(delta) ~= "number" or delta == 0 then return false end
    local siblings = AD.GroupChildren(ParentKeyOf(store, key))
    local pos
    for i = 1, #siblings do
        store.groups[siblings[i]].sort = i
        if siblings[i] == key then pos = i end
    end
    if not pos then return false end
    local target = pos + delta
    if target < 1 or target > #siblings then return false end
    store.groups[siblings[pos]].sort, store.groups[siblings[target]].sort = target, pos
    return true
end

-- All displays in the group's subtree, own members first, then child groups.
function AD.GroupTreeDisplays(groupName, out, visited)
    out = out or {}
    visited = visited or {}
    local key = GroupKey(groupName)
    if key == nil or visited[key] then return out end
    visited[key] = true
    local members = AD.GroupMembers(key)
    for i = 1, #members do out[#out + 1] = members[i] end
    local children = AD.GroupChildren(key)
    for i = 1, #children do
        AD.GroupTreeDisplays(children[i], out, visited)
    end
    return out
end

function AD.GroupPathLabel(groupName)
    local store = Store()
    local key = GroupKey(groupName)
    if not store or key == nil then return groupName end
    local parts, seen, current = {}, {}, key
    while current and not seen[current] do
        seen[current] = true
        table.insert(parts, 1, current)
        current = ParentKeyOf(store, current)
    end
    return table.concat(parts, " > ")
end

local function GroupNameTaken(store, key)
    if store.groups[key] then return true end
    for _, display in pairs(store.displays) do
        if display.group == key then return true end
    end
    return false
end

function AD.GroupEnabled(groupName)
    local key = GroupKey(groupName)
    if key == nil then return true end
    local store = Store()
    if not store then return true end
    -- A disabled ancestor disables the whole subtree.
    local seen, current = {}, key
    while current and not seen[current] do
        seen[current] = true
        local group = store.groups[current]
        if type(group) ~= "table" then return true end
        if group.enabled == false then return false end
        current = GroupKey(group.parent)
    end
    return true
end

function AD.SetGroupEnabled(groupName, enabled)
    local key = GroupKey(groupName)
    if key == nil then return end
    local store = Store()
    if not store then return end
    EnsureGroup(store, key).enabled = enabled and true or false
end

function AD.SetGroupCollapsed(groupName, collapsed)
    local key = GroupKey(groupName)
    if key == nil then return end
    local store = Store()
    if not store then return end
    EnsureGroup(store, key).collapsed = collapsed and true or false
end

function AD.GroupCollapsed(groupName)
    local key = GroupKey(groupName)
    if key == nil then return false end
    local store = Store()
    local group = store and store.groups[key]
    return group ~= nil and group.collapsed == true
end

function AD.DeleteGroup(groupName)
    local key = GroupKey(groupName)
    local store = Store()
    if not store or key == nil then return false end
    local group = store.groups[key]
    local anchorKey = type(group) == "table" and type(group.id) == "string"
        and (AD.GROUP_ANCHOR_PREFIX .. group.id) or nil
    local parentKey = type(group) == "table" and GroupKey(group.parent) or nil
    store.groups[key] = nil
    -- Members and child groups are promoted to the deleted group's parent
    -- rather than dropped to the root.
    for _, display in pairs(store.displays) do
        if display.group == key then display.group = parentKey end
    end
    for _, other in pairs(store.groups) do
        if type(other) == "table" and GroupKey(other.parent) == key then
            other.parent = parentKey
        end
    end
    local H = Helpers()
    local profile = H and type(H.GetProfile) == "function" and H.GetProfile() or nil
    if anchorKey and profile and type(profile.frameAnchoring) == "table" then
        profile.frameAnchoring[anchorKey] = nil
    end
    if type(AD.UnregisterGroupLayoutElement) == "function" then
        AD.UnregisterGroupLayoutElement(group)
    end
    return true
end

function AD.RenameGroup(oldName, newName)
    local store = Store()
    local from, to = GroupKey(oldName), GroupKey(newName)
    if not store or from == nil or to == nil then return false, "invalid" end
    if from == to then return true end
    if GroupNameTaken(store, to) then return false, "collision" end
    local group = store.groups[from]
    store.groups[from] = nil
    store.groups[to] = NormalizeGroup(store, group or {})
    for _, display in pairs(store.displays) do
        if display.group == from then display.group = to end
    end
    for _, other in pairs(store.groups) do
        if type(other) == "table" and GroupKey(other.parent) == from then
            other.parent = to
        end
    end
    return true
end

local function PositiveNumber(value, fallback)
    value = tonumber(value)
    if not value or value <= 0 then return fallback end
    return value
end

local function NonNegativeNumber(value, fallback)
    value = tonumber(value)
    if not value or value < 0 then return fallback end
    return value
end

-- Pure layout seam used by the runtime and headless tests. Coordinates are
-- measured from the group's top-left; y is negative to match WoW SetPoint.
function AD.ComputeGroupLayout(group, members)
    group = type(group) == "table" and group or GROUP_DEFAULTS
    members = type(members) == "table" and members or {}
    local spacing = NonNegativeNumber(group.spacing, GROUP_DEFAULTS.spacing)
    local forcedW = NonNegativeNumber(group.itemWidth, 0)
    local forcedH = NonNegativeNumber(group.itemHeight, 0)
    local direction = group.growDirection or GROUP_DEFAULTS.growDirection
    local vertical = direction == "UP" or direction == "DOWN" or direction == "CENTER_V"
    local centered = direction == "CENTER_H" or direction == "CENTER_V"
    local reverse = direction == "LEFT" or direction == "UP"
    local slots = {}
    local crossExtent = 1

    for i = 1, #members do
        local member = members[i]
        local w = forcedW > 0 and forcedW or PositiveNumber(member.width, 1)
        local h = forcedH > 0 and forcedH or PositiveNumber(member.height, 1)
        slots[i] = { member = member, width = w, height = h }
        crossExtent = math.max(crossExtent, vertical and w or h)
    end

    local primaryExtent = 1
    if #slots > 0 then
        if centered then
            local negativeEdge, positiveEdge = 0, 0
            for i = 1, #slots do
                local size = vertical and slots[i].height or slots[i].width
                local center
                if i == 1 then
                    center = 0
                    negativeEdge, positiveEdge = size / 2, size / 2
                elseif i % 2 == 0 then
                    center = positiveEdge + spacing + size / 2
                    positiveEdge = positiveEdge + spacing + size
                else
                    center = -(negativeEdge + spacing + size / 2)
                    negativeEdge = negativeEdge + spacing + size
                end
                slots[i]._primary = center
            end
            primaryExtent = negativeEdge + positiveEdge
            for i = 1, #slots do
                slots[i]._primary = slots[i]._primary + negativeEdge
            end
        else
            local cursor = 0
            for i = 1, #slots do
                local size = vertical and slots[i].height or slots[i].width
                slots[i]._primary = cursor + size / 2
                cursor = cursor + size
                if i < #slots then cursor = cursor + spacing end
            end
            primaryExtent = math.max(cursor, 1)
            if reverse then
                for i = 1, #slots do
                    slots[i]._primary = primaryExtent - slots[i]._primary
                end
            end
        end
    end

    local width = vertical and crossExtent or primaryExtent
    local height = vertical and primaryExtent or crossExtent
    local alignment = group.alignment or GROUP_DEFAULTS.alignment
    for i = 1, #slots do
        local slot = slots[i]
        if vertical then
            if alignment == "START" then
                slot.x = slot.width / 2
            elseif alignment == "END" then
                slot.x = width - slot.width / 2
            else
                slot.x = width / 2
            end
            slot.y = -slot._primary
        else
            slot.x = slot._primary
            if alignment == "START" then
                slot.y = -slot.height / 2
            elseif alignment == "END" then
                slot.y = -(height - slot.height / 2)
            else
                slot.y = -height / 2
            end
        end
        slot._primary = nil
    end

    return width, height, slots
end

local STATIC_TOKENS = {
    player = "friendly", pet = "friendly",
    target = false, targettarget = false,
    focus = false, focustarget = false, mouseover = false,
}
for i = 1, 5 do
    STATIC_TOKENS["boss" .. i] = "hostile"
    STATIC_TOKENS["arena" .. i] = "hostile"
end
for i = 1, 4 do STATIC_TOKENS["party" .. i] = "friendly" end
for i = 1, 40 do STATIC_TOKENS["raid" .. i] = "friendly" end
AD.STATIC_TOKENS = STATIC_TOKENS

local activeEncounter

function AD.SetEncounter(encounterID)
    activeEncounter = tonumber(encounterID)
end

local function Fold(text)
    if type(text) ~= "string" then return nil end
    local H = Helpers()
    if H and type(H.FoldUTF8) == "function" then return H.FoldUTF8(text) end
    return text
end

local function GroupTokens()
    local out = {}
    local count = GetNumGroupMembers and GetNumGroupMembers() or 0
    if count == 0 then
        out[1] = "player"
        return out
    end
    if IsInRaid and IsInRaid() then
        for i = 1, count do out[#out + 1] = "raid" .. i end
    else
        out[1] = "player"
        for i = 1, count - 1 do out[#out + 1] = "party" .. i end
    end
    return out
end

local function SplitNameRealm(text)
    local name, realm = tostring(text):match("^([^%-]+)%-?(.*)$")
    if realm == "" then realm = nil end
    return name, realm
end

local function PlayerRealm()
    local _, realm = UnitFullName("player")
    if issecretvalue and issecretvalue(realm) then
        realm = nil -- @secret-policy: reject-secret-value (fallback chain decides)
    end
    if realm and realm ~= "" then return realm end
    if type(GetNormalizedRealmName) == "function" then
        realm = GetNormalizedRealmName()
        if realm and realm ~= "" then return realm end
    end
    if type(GetRealmName) == "function" then
        realm = GetRealmName()
        return realm and realm:gsub("[%s%-']", "") or nil
    end
    return nil
end

local function ResolveByName(wanted)
    if type(wanted) ~= "string" or wanted == "" then return nil end
    local wantName, wantRealm = SplitNameRealm(wanted)
    wantName = Fold(wantName)
    wantRealm = wantRealm and Fold((wantRealm:gsub("[%s%-']", ""))) or nil
    if not wantName then return nil end
    local tokens = GroupTokens()
    for i = 1, #tokens do
        local token = tokens[i]
        local name, realm = UnitFullName(token)
        if issecretvalue and issecretvalue(realm) then
            realm = nil -- @secret-policy: reject-secret-value (realm unprovable, skip this candidate)
            name = nil -- @secret-policy: reject-secret-value (realm unprovable, skip this candidate)
        end
        if issecretvalue and issecretvalue(name) then
            name = nil -- @secret-policy: reject-secret-value (identity unprovable, skip this candidate)
        end
        if type(name) == "string" then
            if type(realm) ~= "string" or realm == "" then
                realm = PlayerRealm()
            end
            if Fold(name) == wantName and (not wantRealm or Fold(realm or "") == wantRealm) then
                return token
            end
        end
    end
    return nil
end

local function ResolveCoTank()
    local H = Helpers()
    local UnitTokenMatches = H and H.UnitTokenMatches
    if type(UnitTokenMatches) ~= "function" then return nil end
    local tokens = GroupTokens()
    for i = 1, #tokens do
        local token = tokens[i]
        local isPlayer = UnitTokenMatches("player", token)
        local role = UnitGroupRolesAssigned(token)
        if issecretvalue and issecretvalue(role) then
            role = nil -- @secret-policy: reject-secret-value (role unprovable, not a co-tank)
        end
        if not isPlayer and role == "TANK" then
            return token
        end
    end
    return nil
end

function AD.ResolveUnit(display)
    if type(display) ~= "table" then return nil end
    local mode = display.unitMode or "token"
    if mode == "cotank" then return ResolveCoTank() end
    if mode == "name" then return ResolveByName(display.unit) end
    local token = display.unit
    if type(token) ~= "string" or STATIC_TOKENS[token] == nil then return nil end
    return token
end

function AD.UnitPolarityFor(display)
    if type(display) ~= "table" then return nil end
    local mode = display.unitMode or "token"
    if mode == "cotank" or mode == "name" then return "friendly" end
    local polarity = STATIC_TOKENS[display.unit]
    if polarity == false or polarity == nil then return nil end
    return polarity
end

local function SetIsEmpty(set)
    if type(set) ~= "table" then return true end
    for _, v in pairs(set) do
        if v == true then return false end
    end
    return true
end

local function PlayerClassToken()
    if type(UnitClass) ~= "function" then return nil end
    local _, token = UnitClass("player")
    if type(token) ~= "string" then return nil end
    return token
end

local function PlayerRoleToken()
    local W = ns.QUI_AuraWizard
    if W and type(W.PlayerRole) == "function" then return W.PlayerRole() end
    return nil
end

local function PlayerSpecID()
    local H = Helpers()
    if H and type(H.GetCurrentSpecID) == "function" then return H.GetCurrentSpecID() end
    return nil
end

function AD.PassesLoad(display)
    local load = type(display) == "table" and display.load or nil
    if type(load) ~= "table" then return true end

    if not SetIsEmpty(load.classes) then
        local class = PlayerClassToken()
        if not class or load.classes[class] ~= true then return false end
    end
    if not SetIsEmpty(load.specs) then
        local spec = PlayerSpecID()
        if not spec or load.specs[spec] ~= true then return false end
    end
    if not SetIsEmpty(load.roles) then
        local role = PlayerRoleToken()
        if not role or load.roles[role] ~= true then return false end
    end
    if AD.HasEncounterLoadConditions(display) then
        if not activeEncounter or load.encounters[activeEncounter] ~= true then return false end
    end
    return true
end

function AD.HasEncounterLoadConditions(display)
    local load = type(display) == "table" and display.load or nil
    return type(load) == "table" and not SetIsEmpty(load.encounters)
end

function AD.DisplayActive(display)
    if type(display) ~= "table" then return false end
    if display.enabled == false then return false end
    if not AD.GroupEnabled(display.group) then return false end
    if not AD.PassesLoad(display) then return false end
    return AD.ResolveUnit(display) ~= nil
end

function AD.ShouldShowInactiveIcons(display)
    local visibility = type(display) == "table" and display.visibility or "active"
    if visibility == "always" then return true end
    if visibility ~= "instance" then return false end
    local _, instanceType = GetInstanceInfo()
    return instanceType ~= nil and not NON_GAMEPLAY_INSTANCE_TYPES[instanceType]
end

local E, AuraGlue, AuraSurface, AuraSkin

local function ResolveDeps()
    E = E or ns.AuraElements
    AuraGlue = AuraGlue or ns.AuraGlue
    AuraSurface = AuraSurface or ns.AuraSurface
    AuraSkin = AuraSkin or (ns.Addon and ns.Addon.AuraSkin)
    return E and AuraGlue and AuraSurface and AuraSkin
end

function AD.DefaultBucket()
    local EE = E or ns.AuraElements
    if not EE or type(EE.NewFilterStripElement) ~= "function" then return {} end
    local element = EE.NewFilterStripElement("HELPFUL")
    element.enabled = true
    element.iconSize = 32
    element.iconsPerRow = 8
    element.spacing = 2
    element.growDirection = "RIGHT"
    element.anchor = "TOPLEFT"
    element.maxIcons = 16
    element.duration = { show = true, fontSize = 12, anchor = "CENTER",
        offsetX = 0, offsetY = 0, color = { 1, 1, 1, 1 } }
    element.stack = { show = true, fontSize = 12, anchor = "BOTTOMRIGHT",
        offsetX = -1, offsetY = 1, color = { 1, 1, 1, 1 } }
    return { element }
end

local hosts = {}
local groupHosts = {}
local registered = {}
local auraSoundRegistrations = {}
local registeredGroups = {}
local eventFrame
local watchingDynamicUnits = false
local visibilityAlpha = 1
local previewActive = false
local singlePreviewID
local singlePreviewGroup
local IsSecretValue = issecretvalue

local AURA_SOUND_TRIGGERS = {
    added = Enum and Enum.UnitAuraSoundTrigger and Enum.UnitAuraSoundTrigger.Added or 0,
    applicationsIncreased = Enum and Enum.UnitAuraSoundTrigger
        and Enum.UnitAuraSoundTrigger.ApplicationsIncreased or 1,
    removed = Enum and Enum.UnitAuraSoundTrigger and Enum.UnitAuraSoundTrigger.Removed or 2,
}

local function ResolveAuraSound(soundName)
    if type(soundName) ~= "string" or soundName == "" or soundName == "None" then return nil end
    local sound = ns.LSM and ns.LSM:Fetch("sound", soundName, true) or soundName
    if type(sound) ~= "string" and type(sound) ~= "number" then return nil end
    return sound
end

local function RemoveAuraSoundRegistration(record)
    if not (record and record.id and C_UnitAuras and C_UnitAuras.RemoveAuraSound) then return end
    ns.SafeCall("best-effort-style", C_UnitAuras.RemoveAuraSound, record.id)
end

local function ReconcileAuraSounds(store)
    if not (C_UnitAuras and C_UnitAuras.AddAuraSound and C_UnitAuras.RemoveAuraSound) then return end
    if InCombatLockdown and InCombatLockdown() then return end
    if C_Secrets and C_Secrets.ShouldAurasBeSecret and C_Secrets.ShouldAurasBeSecret() then return end
    E = E or ns.AuraElements
    if not E then return end

    local desired = {}
    if store and store.enabled ~= false then
        local specID = PlayerSpecID()
        for _, display in ipairs(AD.OrderedDisplays()) do
            local unitMode = display.unitMode or "token"
            local unitToken = display.unit
            if display.enabled ~= false and AD.GroupEnabled(display.group) and AD.PassesLoad(display)
                and not AD.HasEncounterLoadConditions(display)
                and type(display.auras) == "table" and display.auras.enabled ~= false
                and unitMode == "token" and type(unitToken) == "string"
                and STATIC_TOKENS[unitToken] ~= nil then
                E.EnsureSeeded(display.auras, AD.DefaultBucket)
                local elements = E.ActiveElementsForSpec(display.auras, specID)
                for _, element in ipairs(elements) do
                    if element.mode == "tracked" and type(element.spells) == "table"
                        and type(element.auraSounds) == "table" then
                        for _, spellID in ipairs(element.spells) do
                            local sounds = element.auraSounds[spellID]
                            if type(spellID) == "number" and type(sounds) == "table"
                                and not E.EffectiveOnlyMine(element, spellID) then
                                for eventKey, trigger in pairs(AURA_SOUND_TRIGGERS) do
                                    local sound = ResolveAuraSound(sounds[eventKey])
                                    if sound then
                                        local key = table.concat({ display.id, element.id or "", spellID, eventKey }, ":")
                                        desired[key] = {
                                            trigger = trigger,
                                            unitToken = unitToken,
                                            spellID = spellID,
                                            sound = sound,
                                            signature = table.concat({ unitToken, spellID, eventKey, tostring(sound) }, ":"),
                                        }
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
    end

    for key, record in pairs(auraSoundRegistrations) do
        local nextRecord = desired[key]
        if not nextRecord or nextRecord.signature ~= record.signature then
            RemoveAuraSoundRegistration(record)
            auraSoundRegistrations[key] = nil
        end
    end

    for key, record in pairs(desired) do
        if not auraSoundRegistrations[key] then
            local soundInfo = {
                unitToken = record.unitToken,
                spellID = record.spellID,
                outputChannel = "Master",
            }
            if type(record.sound) == "number" then
                soundInfo.soundFileID = record.sound
            else
                soundInfo.soundFileName = record.sound
            end
            local ok, id = ns.SafeCall("best-effort-style",
                C_UnitAuras.AddAuraSound, record.trigger, soundInfo)
            if ok and id then
                record.id = id
                auraSoundRegistrations[key] = record
            end
        end
    end
end

AD._ReconcileAuraSounds = ReconcileAuraSounds

function AD.PreviewAuraSound(soundName)
    local sound = ResolveAuraSound(soundName)
    if not sound or type(PlaySoundFile) ~= "function" then return false end
    return ns.SafeCall("best-effort-style", PlaySoundFile, sound, "Master")
end

-- True when `groupName` sits on the previewed group's chain — the previewed
-- group itself, one of its ancestors (they must render to show it), or one of
-- its descendants (previewing a group previews its whole subtree).
local function GroupPreviewRelated(groupName)
    if not singlePreviewGroup then return false end
    if groupName == singlePreviewGroup then return true end
    return AD.GroupIsAncestor(groupName, singlePreviewGroup)
        or AD.GroupIsAncestor(singlePreviewGroup, groupName)
end

local function GroupUnderPreview(groupName)
    if not singlePreviewGroup then return false end
    return groupName == singlePreviewGroup
        or AD.GroupIsAncestor(singlePreviewGroup, groupName)
end

local function DisplayUnderGroupPreview(id)
    if not singlePreviewGroup then return false end
    local display = AD.GetDisplay(id)
    return display ~= nil and GroupUnderPreview(GroupKey(display.group))
end

local function ApplyHostVisibilityAlpha(id, host, forceVisible)
    local alpha = 0
    if previewActive or id == singlePreviewID or DisplayUnderGroupPreview(id) then
        alpha = 1
    elseif host._quiAuraDisplayActive then
        alpha = forceVisible and 1 or visibilityAlpha
    end
    host:SetAlpha(alpha)
end

function AD.HostFor(id)
    return hosts[id]
end

function AD.GetVisibilityFrames()
    local frames = {}
    for _, host in pairs(hosts) do
        if host._quiAuraDisplayActive then
            frames[#frames + 1] = host
        end
    end
    return frames
end

function AD.IsVisibilityFrameMouseOver()
    for _, host in pairs(hosts) do
        if host._quiAuraDisplayActive then
            local mouseOver = host:IsMouseOver()
            if not (IsSecretValue and IsSecretValue(mouseOver)) and mouseOver then
                return true
            end
        end
    end
    return false
end

function AD.GetVisibilityAlpha()
    return visibilityAlpha
end

function AD.SetVisibilityAlpha(alpha)
    visibilityAlpha = alpha
    for id, host in pairs(hosts) do
        ApplyHostVisibilityAlpha(id, host)
    end
    for _, groupHost in pairs(groupHosts) do
        local container = groupHost._quiPackContainer
        if container and not container._quiPackParked then
            container:SetAlpha(previewActive and 1 or alpha)
        end
    end
end

function AD.GroupHostFor(groupName)
    local group = AD.GetGroup(groupName, false)
    return group and groupHosts[group.id] or nil
end

local function EnsureHost(id)
    local host = hosts[id]
    if host then return host end
    if InCombatLockdown() then return nil end
    host = CreateFrame("Frame", "QUI_AuraDisplay_" .. id, UIParent)
    host:SetSize(1, 1)
    host:SetClampedToScreen(true)
    host:ClearAllPoints()
    host:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    hosts[id] = host
    return host
end

local function EnsureGroupHost(group)
    local host = groupHosts[group.id]
    if host then return host end
    if InCombatLockdown() then return nil end
    host = CreateFrame("Frame", "QUI_AuraDisplayGroup_" .. group.id, UIParent)
    host:SetSize(1, 1)
    host:SetClampedToScreen(true)
    host:ClearAllPoints()
    host:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    groupHosts[group.id] = host
    return host
end

-- Preview editing -------------------------------------------------------------
-- While a display or group is being edited in the options panel (single
-- preview active), its on-screen preview is directly draggable and group
-- hosts show a bounding box, so positioning doesn't require a trip to Layout
-- Mode. Dragging always moves the ROOT entity — a nested display or child
-- group has no anchor of its own; its root group does.

local function PreviewAccent()
    local colors = QUI and QUI.GUI and QUI.GUI.Colors
    local accent = colors and colors.accent
    if type(accent) == "table" then
        return accent[1] or 0.2, accent[2] or 0.6, accent[3] or 1
    end
    return 0.2, 0.6, 1
end

local function UpdateGroupBox(host, groupName, mode)
    if not host then return end
    local box = host._quiPreviewBox
    if not mode then
        if box then
            for i = 1, 4 do box[i]:Hide() end
            box.label:Hide()
        end
        return
    end
    if not box then
        if type(host.CreateTexture) ~= "function"
            or type(host.CreateFontString) ~= "function" then
            return
        end
        box = {}
        for i = 1, 4 do
            box[i] = host:CreateTexture(nil, "OVERLAY")
        end
        box[1]:SetPoint("TOPLEFT", 0, 0)
        box[1]:SetPoint("TOPRIGHT", 0, 0)
        box[1]:SetHeight(1)
        box[2]:SetPoint("BOTTOMLEFT", 0, 0)
        box[2]:SetPoint("BOTTOMRIGHT", 0, 0)
        box[2]:SetHeight(1)
        box[3]:SetPoint("TOPLEFT", 0, 0)
        box[3]:SetPoint("BOTTOMLEFT", 0, 0)
        box[3]:SetWidth(1)
        box[4]:SetPoint("TOPRIGHT", 0, 0)
        box[4]:SetPoint("BOTTOMRIGHT", 0, 0)
        box[4]:SetWidth(1)
        box.label = host:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        box.label:SetPoint("BOTTOMLEFT", host, "TOPLEFT", 0, 2)
        host._quiPreviewBox = box
    end
    local r, g, b = PreviewAccent()
    local alpha = mode == "selected" and 0.9 or 0.4
    for i = 1, 4 do
        box[i]:SetColorTexture(r, g, b, alpha)
        box[i]:Show()
    end
    box.label:SetText(groupName)
    box.label:SetTextColor(r, g, b, alpha)
    box.label:Show()
end

local function PreviewBoxMode(groupName)
    if previewActive then return nil end -- Layout Mode draws its own movers
    if singlePreviewGroup then
        if not GroupPreviewRelated(groupName) then return nil end
        return groupName == singlePreviewGroup and "selected" or "related"
    end
    if singlePreviewID then
        local display = AD.GetDisplay(singlePreviewID)
        local dg = display and GroupKey(display.group)
        if dg and (groupName == dg or AD.GroupIsAncestor(groupName, dg)) then
            return "related"
        end
    end
    return nil
end

local dragOverlay
local dragTarget

local function ResolveDragTarget(kind, value)
    if kind == "display" then
        local display = AD.GetDisplay(value)
        if not display then return nil end
        local groupName = GroupKey(display.group)
        if not groupName then
            return hosts[display.id], AD.ANCHOR_PREFIX .. display.id
        end
        local rootName = AD.RootGroupName(groupName) or groupName
        local group = AD.GetGroup(rootName, false)
        return group and groupHosts[group.id],
            group and (AD.GROUP_ANCHOR_PREFIX .. group.id)
    end
    local rootName = AD.RootGroupName(value) or GroupKey(value)
    local group = rootName and AD.GetGroup(rootName, false)
    return group and groupHosts[group.id],
        group and (AD.GROUP_ANCHOR_PREFIX .. group.id)
end

local function SafeCoord(value)
    if IsSecretValue and IsSecretValue(value) then
        return nil -- @secret-policy: reject-to-nil — a secret coordinate is never committed; nil skips the drag write
    end
    return tonumber(value)
end

-- Writes the dragged host's center back as a CENTER/CENTER screen anchor,
-- the same record shape Layout Mode commits, then reapplies it.
function AD.CommitPreviewDragPosition()
    local target = dragTarget
    if not target or not target.host then return false end
    local host = target.host
    local hx, hy = host:GetCenter()
    local ux, uy = UIParent:GetCenter()
    local hs = type(host.GetEffectiveScale) == "function" and host:GetEffectiveScale() or 1
    local us = type(UIParent.GetEffectiveScale) == "function" and UIParent:GetEffectiveScale() or 1
    hx, hy = SafeCoord(hx), SafeCoord(hy)
    ux, uy = SafeCoord(ux), SafeCoord(uy)
    hs, us = SafeCoord(hs) or 1, SafeCoord(us) or 1
    if not (hx and hy and ux and uy) then
        if _G.QUI_ApplyFrameAnchor then _G.QUI_ApplyFrameAnchor(target.key) end
        return false
    end
    local H = Helpers()
    local profile = H and type(H.GetProfile) == "function" and H.GetProfile() or nil
    if not profile then return false end
    profile.frameAnchoring = profile.frameAnchoring or {}
    local record = profile.frameAnchoring[target.key]
    if type(record) ~= "table" then
        record = {}
        profile.frameAnchoring[target.key] = record
    end
    record.point = "CENTER"
    record.relative = "CENTER"
    record.offsetX = hx * hs / us - ux
    record.offsetY = hy * hs / us - uy
    if record.sizeStable == nil then record.sizeStable = true end
    if _G.QUI_ApplyFrameAnchor then _G.QUI_ApplyFrameAnchor(target.key) end
    if _G.QUI_LayoutModeSyncHandle then _G.QUI_LayoutModeSyncHandle(target.key) end
    return true
end

local function EnsureDragOverlay()
    if dragOverlay then return dragOverlay end
    local overlay = CreateFrame("Frame", nil, UIParent)
    if type(overlay.EnableMouse) == "function" then overlay:EnableMouse(true) end
    if type(overlay.RegisterForDrag) == "function" then overlay:RegisterForDrag("LeftButton") end
    local border
    if type(overlay.CreateTexture) == "function" then
        border = {}
        for i = 1, 4 do border[i] = overlay:CreateTexture(nil, "OVERLAY") end
        border[1]:SetPoint("TOPLEFT", -1, 1)
        border[1]:SetPoint("TOPRIGHT", 1, 1)
        border[1]:SetHeight(1)
        border[2]:SetPoint("BOTTOMLEFT", -1, -1)
        border[2]:SetPoint("BOTTOMRIGHT", 1, -1)
        border[2]:SetHeight(1)
        border[3]:SetPoint("TOPLEFT", -1, 1)
        border[3]:SetPoint("BOTTOMLEFT", -1, -1)
        border[3]:SetWidth(1)
        border[4]:SetPoint("TOPRIGHT", 1, 1)
        border[4]:SetPoint("BOTTOMRIGHT", 1, -1)
        border[4]:SetWidth(1)
        overlay._quiBorder = border
    end
    overlay:SetScript("OnDragStart", function()
        local target = dragTarget
        if not target or (InCombatLockdown and InCombatLockdown()) then return end
        if type(target.host.SetMovable) == "function" then target.host:SetMovable(true) end
        if type(target.host.StartMoving) == "function" then
            target.host:StartMoving()
            target.dragging = true
        end
    end)
    overlay:SetScript("OnDragStop", function()
        local target = dragTarget
        if not target or not target.dragging then return end
        target.dragging = nil
        if type(target.host.StopMovingOrSizing) == "function" then
            target.host:StopMovingOrSizing()
        end
        AD.CommitPreviewDragPosition()
        AD.Refresh()
    end)
    overlay:SetScript("OnEnter", function(self)
        if _G.GameTooltip then
            _G.GameTooltip:SetOwner(self, "ANCHOR_TOP")
            _G.GameTooltip:AddLine(ns.L["Drag to move. Fine-tune in Layout Mode."], 1, 0.82, 0)
            _G.GameTooltip:Show()
        end
    end)
    overlay:SetScript("OnLeave", function()
        if _G.GameTooltip then _G.GameTooltip:Hide() end
    end)
    dragOverlay = overlay
    return overlay
end

function AD.EnablePreviewDrag(kind, value)
    local host, key = ResolveDragTarget(kind, value)
    if not host or not key then
        AD.DisablePreviewDrag()
        return false
    end
    local overlay = EnsureDragOverlay()
    dragTarget = { host = host, key = key }
    overlay:SetParent(host)
    overlay:ClearAllPoints()
    overlay:SetAllPoints(host)
    if type(overlay.SetFrameLevel) == "function" and type(host.GetFrameLevel) == "function" then
        overlay:SetFrameLevel((host:GetFrameLevel() or 0) + 10)
    end
    local r, g, b = PreviewAccent()
    if overlay._quiBorder then
        for i = 1, 4 do
            overlay._quiBorder[i]:SetColorTexture(r, g, b, 0.8)
        end
    end
    overlay:Show()
    return true
end

function AD.DisablePreviewDrag()
    if dragTarget and dragTarget.dragging then
        if type(dragTarget.host.StopMovingOrSizing) == "function" then
            dragTarget.host:StopMovingOrSizing()
        end
    end
    dragTarget = nil
    if dragOverlay then
        dragOverlay:Hide()
        dragOverlay:SetParent(UIParent)
        dragOverlay:ClearAllPoints()
    end
end

function AD.PreviewDragTarget()
    return dragTarget and dragTarget.key or nil
end

local function DisableHostContainers(host)
    local pool = host._quiAuraContainers
    if pool then
        for i = 1, #pool do
            local container = pool[i]
            if container then
                ns.SafeCallMethod("best-effort-style", container, "SetEnabled", false)
                ns.SafeCallMethod("best-effort-style", container, "Hide")
            end
        end
    end
end

local function ParkOrphanHost(host)
    DisableHostContainers(host)
    host._quiAuraDisplayActive = false
    host:Hide()
end

local function GridExtent(profile)
    local perRow = profile.maxPerRow
    if not perRow or perRow < 1 then perRow = profile.maxIcons end
    local cols = math.min(perRow, profile.maxIcons)
    if cols < 1 then cols = 1 end
    local rows = math.ceil(profile.maxIcons / cols)
    local w = cols * profile.iconSize + math.max(0, cols - 1) * profile.spacing
    local h = rows * profile.iconSize + math.max(0, rows - 1) * profile.spacing
    return w, h
end

local function ElementExtent(element, profile)
    if element.mode == "tracked" and element.displayType == "bar"
        and not (element.bar and element.bar.matchFrameSize == true) then
        local bar = element.bar or {}
        if bar.orientation == "VERTICAL" then
            return bar.thickness or 12, bar.length or 48
        end
        return bar.length or 48, bar.thickness or 12
    end
    return GridExtent(profile)
end

local function DisplayElementProfile(element)
    local profile = AuraGlue.ElementProfile(element)
    if element.mode == "tracked" and E.TrackedSpellCount(element) <= 1 then
        profile.grow = "RIGHT"
        profile.spacing = 0
        profile.maxPerRow = 0
    end
    return profile
end

local function RenderableElement(element, profile)
    if element.mode == "tracked" then
        return element.displayType ~= "healthTint"
            and element.displayType ~= "border"
            and E.TrackedSpellCount(element) > 0
    end
    return element.mode == "filterStrip" or element.mode == "missingRaidBuff"
end

local function BuildDisplayLayout(display, elements, preview)
    if type(elements) ~= "table" then
        preview = elements
        elements = display
        display = nil
    end
    E = E or ns.AuraElements
    AuraGlue = AuraGlue or ns.AuraGlue
    if not E or not AuraGlue then
        return { placements = {}, profiles = {}, width = 1, height = 1 }
    end
    local renderable = {}
    local profiles = {}
    for i = 1, #elements do
        local element = elements[i]
        local profile = DisplayElementProfile(element)
        if preview and element.mode == "filterStrip" and (element.maxIcons or 0) == 0 then
            profile.maxIcons = 3
        end
        if RenderableElement(element, profile) then
            renderable[#renderable + 1] = element
            profiles[element] = profile
        end
    end

    if #renderable == 0 then
        return { placements = {}, profiles = profiles, width = 1, height = 1 }
    end

    local placements = {}
    local settings = type(display) == "table" and display.layout or nil
    local direction = settings and settings.direction or DISPLAY_LAYOUT_DEFAULTS.direction
    local alignment = settings and settings.alignment or DISPLAY_LAYOUT_DEFAULTS.alignment
    local gap = settings and settings.spacing or DISPLAY_LAYOUT_DEFAULTS.spacing
    if type(gap) ~= "number" or gap < 0 then gap = DISPLAY_LAYOUT_DEFAULTS.spacing end
    local width, height = 0, 0
    local extents = {}
    for i = 1, #renderable do
        local element = renderable[i]
        local profile = profiles[element]
        local elementWidth, elementHeight = ElementExtent(element, profile)
        extents[i] = { width = elementWidth, height = elementHeight }
        if direction == "UP" or direction == "DOWN" then
            width = math.max(width, elementWidth)
            height = height + elementHeight
        else
            width = width + elementWidth
            height = math.max(height, elementHeight)
        end
    end
    if #renderable > 1 then
        if direction == "UP" or direction == "DOWN" then
            height = height + gap * (#renderable - 1)
        else
            width = width + gap * (#renderable - 1)
        end
    end

    local cursor = 0
    for i = 1, #renderable do
        local element = renderable[i]
        local extent = extents[i]
        local offsetX, offsetY
        if direction == "UP" or direction == "DOWN" then
            if alignment == "END" then
                offsetX = width - extent.width
            elseif alignment == "CENTER" then
                offsetX = (width - extent.width) / 2
            else
                offsetX = 0
            end
            if direction == "UP" then
                offsetY = height - cursor - extent.height
            else
                offsetY = -cursor
            end
            cursor = cursor + extent.height + gap
        else
            if alignment == "END" then
                offsetY = -(height - extent.height)
            elseif alignment == "CENTER" then
                offsetY = -(height - extent.height) / 2
            else
                offsetY = 0
            end
            if direction == "LEFT" then
                offsetX = width - cursor - extent.width
            else
                offsetX = cursor
            end
            cursor = cursor + extent.width + gap
        end
        placements[element] = {
            point = "TOPLEFT",
            relativePoint = "TOPLEFT",
            pinCorner = "TOPLEFT",
            offsetX = offsetX,
            offsetY = offsetY,
        }
    end

    return { placements = placements, profiles = profiles, width = width, height = height }
end

AD.ResolveDisplayLayout = BuildDisplayLayout

local function AnchorElementContainer(container, host, element, placement)
    local profile = DisplayElementProfile(element)
    local offsetX = placement and placement.offsetX or element.offsetX or 0
    local offsetY = placement and placement.offsetY or element.offsetY or 0
    local point = placement and placement.point or AuraSkin.LayoutAnchor(profile)
    local relativePoint = placement and placement.relativePoint or element.anchor or "TOPLEFT"
    container:ClearAllPoints()
    container:SetPoint(point, host, relativePoint,
        offsetX, offsetY)
end

local EMPTY = {}

local ApplyDisplay
local QueueGroupReflow

local function GameplayHidden(anchorKey)
    local H = Helpers()
    local profile = H and type(H.GetProfile) == "function" and H.GetProfile() or nil
    local hiddenHandles = profile and profile.layoutMode and profile.layoutMode.hiddenHandles
    return hiddenHandles ~= nil and hiddenHandles[anchorKey] == true
end

local function RequeueDisplay(display)
    if not (InCombatLockdown() or AuraGlue.AurasAreSecret()) then return end
    local id = display.id
    AuraGlue.QueueRegenWork(AD.ANCHOR_PREFIX .. id, function()
        local current = AD.GetDisplay(id)
        if current then ApplyDisplay(current, true) end
    end)
end

ApplyDisplay = function(display, allowCreate)
    if previewActive then return end
    if display.id == singlePreviewID then return end
    -- Previewing a group freezes its whole subtree, nested groups included.
    if GroupUnderPreview(GroupKey(display.group)) then return end
    if not ResolveDeps() then return end
    local host = EnsureHost(display.id)
    if not host then
        RequeueDisplay(display)
        return
    end

    E.EnsureSeeded(display.auras, AD.DefaultBucket)

    local unit = nil
    if display.enabled ~= false and AD.GroupEnabled(display.group) and AD.PassesLoad(display) then
        unit = AD.ResolveUnit(display)
    end
    local activeElements = EMPTY
    if unit then
        local H = Helpers()
        local specID = H and type(H.GetCurrentSpecID) == "function" and H.GetCurrentSpecID() or nil
        activeElements = E.ActiveElementsForSpec(display.auras, specID)
    end
    if activeElements == EMPTY then
        local H = Helpers()
        local specID = H and type(H.GetCurrentSpecID) == "function" and H.GetCurrentSpecID() or nil
        activeElements = E.ActiveElementsForSpec(display.auras, specID)
    end
    local elements = unit and activeElements or EMPTY

    local layout = BuildDisplayLayout(display, activeElements)
    host._naturalW, host._naturalH = layout.width, layout.height
    host:SetSize(layout.width, layout.height)

    local skipElement
    local Slots = unit and ns.AuraSlots
    if Slots and type(Slots.LivePolarityMismatch) == "function" then
        skipElement = function(element)
            if element.mode ~= "tracked" then return false end
            return Slots.LivePolarityMismatch(unit, element.auraType or "HELPFUL")
        end
    end

    AuraSurface.ApplyElementPass(host, elements, {
        unit = unit or "player",
        allowCreate = allowCreate == true and not InCombatLockdown(),
        cancelEligible = false,
        profileFor = DisplayElementProfile,
        anchorContainer = function(container, anchorHost, element)
            AnchorElementContainer(container, anchorHost, element, layout.placements[element])
        end,
        showInactive = AD.ShouldShowInactiveIcons(display),
        skip = skipElement,
        onIncomplete = function() RequeueDisplay(display) end,
    })

    local H = Helpers()
    local layoutActive = H and type(H.IsLayoutModeActive) == "function" and H.IsLayoutModeActive()

    local grouped = GroupKey(display.group) ~= nil
    host._quiAuraDisplayActive = unit ~= nil
    ApplyHostVisibilityAlpha(display.id, host, layoutActive)
    if unit then
        if grouped then
            -- The group reflow owns where (and whether) a grouped host shows.
            -- A host it has not placed yet still sits at its birth spot —
            -- screen center, parented to UIParent — and one it packed into
            -- the shared container must stay hidden. Refreshes land mid-
            -- combat, when the reflow is deferred, so showing here would
            -- paint a stray copy until combat ends.
            if host._quiGroupPlaced and not host._quiGroupPacked then
                host:Show()
            else
                host:Hide()
                if InCombatLockdown() or AuraGlue.AurasAreSecret() then
                    QueueGroupReflow()
                end
            end
        elseif layoutActive or not GameplayHidden(AD.ANCHOR_PREFIX .. display.id) then
            host:Show()
        else
            host:Hide()
            local lm = ns.QUI_LayoutMode
            if lm then
                lm._gameplayHidden = lm._gameplayHidden or {}
                lm._gameplayHidden[AD.ANCHOR_PREFIX .. display.id] = true
            end
        end
    end

    if not grouped and not layoutActive then
        host._quiGroupPlaced, host._quiGroupPacked = nil, nil
        if host:GetParent() ~= UIParent then host:SetParent(UIParent) end
        host:SetScale(1)
        if _G.QUI_ApplyFrameAnchor then
            _G.QUI_ApplyFrameAnchor(AD.ANCHOR_PREFIX .. display.id)
        end
    end
end

-- Packed groups ---------------------------------------------------------------
-- A group with dynamicLayout renders its single-list icon displays through ONE
-- shared aura container on the group host: one single-frame Blizzard aura
-- group per tracked spell (ns.AuraSlots.DynamicGroups), styled with that
-- display's profile. Blizzard's flow layout skips empty groups, so the icons
-- pack together as auras come and go — Lua never reads aura presence. Members
-- that cannot pack (other units, strips, bars, multi-element displays) keep
-- their reserved positions after the packed block. Packing is suspended while
-- previewing or in Layout Mode so every display can be seen and dragged.
local PACK_FLOW = {
    RIGHT    = { grow = "RIGHT", vertical = false },
    LEFT     = { grow = "LEFT",  vertical = false },
    DOWN     = { grow = "DOWN",  vertical = true },
    UP       = { grow = "UP",    vertical = true },
    CENTER_H = { grow = "RIGHT", vertical = false, centered = true },
    CENTER_V = { grow = "DOWN",  vertical = true,  centered = true },
}

local function PackableElement(display, specID)
    if not E or not AD.DisplayActive(display) then return nil end
    if type(display.auras) ~= "table" then return nil end
    local elements = E.ActiveElementsForSpec(display.auras, specID)
    local found
    for i = 1, #elements do
        local element = elements[i]
        if RenderableElement(element) then
            if found then return nil end
            found = element
        end
    end
    if not found or found.mode ~= "tracked" then return nil end
    if found.displayType ~= nil and found.displayType ~= "icon" then return nil end
    return found
end

local function EnsurePackContainer(groupHost)
    local container = groupHost._quiPackContainer
    if container then return container end
    if InCombatLockdown() or type(CreateFrame) ~= "function" then return nil end
    container = CreateFrame("AuraContainer", nil, groupHost, "CustomAuraContainerTemplate")
    if not container then return nil end
    container:SetSize(1, 1)
    groupHost._quiPackContainer = container
    return container
end

local function ParkPackContainer(container)
    if not container or container._quiPackParked or not AuraGlue then return end
    AuraGlue.RunConfigPass(container, container._quiProfile or {}, {}, not InCombatLockdown())
    container:SetEnabled(false)
    container:Hide()
    container._quiPackParked = true
end

local function BuildPack(groupHost, group, groupDisplays)
    local Slots = ns.AuraSlots
    if not (E and AuraGlue and Slots and type(Slots.DynamicGroups) == "function") then
        return nil
    end
    local H = Helpers()
    local specID = H and type(H.GetCurrentSpecID) == "function" and H.GetCurrentSpecID() or nil
    local flow = PACK_FLOW[group.growDirection] or PACK_FLOW.RIGHT
    local spacing = NonNegativeNumber(group.spacing, GROUP_DEFAULTS.spacing)
    local alignment = group.alignment or GROUP_DEFAULTS.alignment
    local members, byID, unit = {}, {}, nil
    local primary, cross, count = 0, 1, 0
    for j = 1, #groupDisplays do
        local display = groupDisplays[j]
        local element = hosts[display.id] and PackableElement(display, specID)
        local memberUnit = element and AD.ResolveUnit(display)
        if element and memberUnit and (unit == nil or unit == memberUnit)
            and not (type(Slots.LivePolarityMismatch) == "function"
                and Slots.LivePolarityMismatch(memberUnit, element.auraType or "HELPFUL")) then
            unit = memberUnit
            local profile = DisplayElementProfile(element)
            local n = E.TrackedSpellCount(element)
            local size = PositiveNumber(profile.iconSize, 1)
            members[#members + 1] = { display = display, element = element, profile = profile }
            byID[display.id] = true
            if count > 0 then primary = primary + spacing end
            primary = primary + n * size + (n - 1) * NonNegativeNumber(profile.spacing, 0)
            cross = math.max(cross, size)
            count = count + n
        end
    end
    if #members == 0 then return nil end
    local container = EnsurePackContainer(groupHost)
    if not container then return nil end
    container:SetUnit(unit)
    local groups = {}
    for m = 1, #members do
        local member = members[m]
        local memberGroups = Slots.DynamicGroups(container, member.element, member.profile)
        for g = 1, #memberGroups do
            local desc = memberGroups[g]
            desc.key = "p" .. tostring(member.display.id) .. "_" .. tostring(desc.key)
            desc.profile = member.profile
            desc.elementWidth = member.profile.iconSize
            desc.elementHeight = member.profile.iconSize
            -- The gap between displays is the group's spacing; gaps inside a
            -- multi-spell display keep that element's own spacing.
            if g == 1 then desc.groupSpacing = spacing end
            groups[#groups + 1] = desc
        end
    end
    local containerProfile = {
        iconSize = cross, spacing = spacing, rowSpacing = 0, maxPerRow = 0,
        maxIcons = math.max(count, 1), grow = flow.grow, anchor = "TOPLEFT",
        wrap = (not flow.vertical and alignment == "END") and "UP" or "DOWN",
        crossEnd = (flow.vertical and alignment == "END") or nil,
    }
    AuraGlue.RunConfigPass(container, containerProfile, groups, not InCombatLockdown())
    container._quiPackParked = nil
    container:SetEnabled(true)
    container:SetAlpha(visibilityAlpha)
    container:Show()
    local spec = { host = container, isPacked = true, flow = flow }
    if flow.vertical then
        spec.width, spec.height = cross, math.max(primary, 1)
    else
        spec.width, spec.height = math.max(primary, 1), cross
    end
    return { byID = byID, spec = spec, unit = unit, members = members }
end

-- The engine sizes the container to its live contents, so anchoring the
-- container's leading edge (or center, for centered growth) to the block
-- reserved in the group layout makes the remaining icons pack toward it.
local function AnchorPackedBlock(container, groupHost, placement, group)
    local flow = placement.member.flow or PACK_FLOW.RIGHT
    local alignment = group.alignment or GROUP_DEFAULTS.alignment
    local w, h = placement.width, placement.height
    local x, y = placement.x, placement.y
    local point, ox, oy
    if flow.centered then
        point, ox, oy = "CENTER", x, y
    elseif flow.vertical then
        local v = flow.grow == "UP" and "BOTTOM" or "TOP"
        oy = v == "TOP" and (y + h / 2) or (y - h / 2)
        if alignment == "START" then
            point, ox = v .. "LEFT", x - w / 2
        elseif alignment == "END" then
            point, ox = v .. "RIGHT", x + w / 2
        else
            point, ox = v, x
        end
    else
        local hz = flow.grow == "LEFT" and "RIGHT" or "LEFT"
        ox = hz == "LEFT" and (x - w / 2) or (x + w / 2)
        if alignment == "START" then
            point, oy = "TOP" .. hz, y + h / 2
        elseif alignment == "END" then
            point, oy = "BOTTOM" .. hz, y - h / 2
        else
            point, oy = hz, y
        end
    end
    container:ClearAllPoints()
    container:SetPoint(point, groupHost, "TOPLEFT", ox, oy)
end

-- One stable callback: combat refreshes queue this repeatedly under the same
-- key, so a fresh closure per call would only be allocation churn.
local function RefreshAfterRegen() AD.Refresh() end

QueueGroupReflow = function()
    if AuraGlue and type(AuraGlue.QueueRegenWork) == "function" then
        AuraGlue.QueueRegenWork("auraDisplayGroups", RefreshAfterRegen)
    end
end

function AD.ReflowGroups(displays)
    displays = displays or AD.OrderedDisplays()
    if InCombatLockdown() then
        QueueGroupReflow()
        return false
    end

    local buckets = {}
    for i = 1, #displays do
        local display = displays[i]
        local key = GroupKey(display.group)
        if key then
            local bucket = buckets[key]
            if not bucket then
                bucket = {}
                buckets[key] = bucket
            end
            bucket[#bucket + 1] = display
        end
    end

    -- A group participates in layout when its subtree holds at least one
    -- display; mark every ancestor of a display-bearing group.
    local store = Store()
    local groupsWithContent = {}
    for key in pairs(buckets) do
        local seen, current = {}, key
        while current and not seen[current] do
            seen[current] = true
            groupsWithContent[current] = true
            local g = store and store.groups[current]
            current = type(g) == "table" and GroupKey(g.parent) or nil
        end
    end

    local seenGroupIDs = {}
    local H = Helpers()
    local layoutActive = H and type(H.IsLayoutModeActive) == "function" and H.IsLayoutModeActive()
    local visited = {}

    -- Post-order reflow: children are laid out first so their scaled extents
    -- can flow as blocks inside the parent's layout. Returns the host, its
    -- effective (scaled) extent in parent coordinates, and whether it shows.
    local function ReflowGroup(groupName)
        if visited[groupName] then return nil end
        visited[groupName] = true
        local group = AD.GetGroup(groupName, true)
        local groupHost = group and EnsureGroupHost(group)
        if not groupHost then return nil end
        seenGroupIDs[group.id] = true

        local memberSpecs = {}
        local children = AD.GroupChildren(groupName)
        for j = 1, #children do
            local childName = children[j]
            if groupsWithContent[childName] then
                local childHost, childW, childH, childShown = ReflowGroup(childName)
                if childHost and childShown then
                    memberSpecs[#memberSpecs + 1] = {
                        groupName = childName,
                        host = childHost,
                        isGroup = true,
                        width = childW,
                        height = childH,
                    }
                end
            end
        end

        local groupDisplays = buckets[groupName]
        local packAllowed = group.dynamicLayout == true and not previewActive
            and not layoutActive and not GroupPreviewRelated(groupName)
        local pack = (packAllowed and groupDisplays) and BuildPack(groupHost, group, groupDisplays) or nil
        if not pack and groupHost._quiPackContainer then
            ParkPackContainer(groupHost._quiPackContainer)
        end
        if groupDisplays then
            for j = 1, #groupDisplays do
                local display = groupDisplays[j]
                local host = hosts[display.id]
                local forcePreview = previewActive or GroupUnderPreview(groupName)
                    or singlePreviewID == display.id
                if pack and pack.byID[display.id] then
                    if not pack.placed then
                        pack.placed = true
                        memberSpecs[#memberSpecs + 1] = pack.spec
                    end
                    if host then
                        host._quiGroupPacked = true
                        host:Hide()
                    end
                elseif host and (forcePreview or AD.DisplayActive(display)) then
                    memberSpecs[#memberSpecs + 1] = {
                        id = display.id,
                        display = display,
                        host = host,
                        width = host._naturalW or host:GetWidth() or 1,
                        height = host._naturalH or host:GetHeight() or 1,
                    }
                elseif host then
                    host._quiGroupPlaced = nil
                    host:Hide()
                end
            end
        end

        local width, height, placements = AD.ComputeGroupLayout(group, memberSpecs)
        local scale = PositiveNumber(group.scale, GROUP_DEFAULTS.scale)
        groupHost._naturalW, groupHost._naturalH = width, height
        groupHost:SetSize(width, height)
        groupHost:SetScale(scale)
        for j = 1, #placements do
            local placement = placements[j]
            local host = placement.member.host
            if host:GetParent() ~= groupHost then host:SetParent(groupHost) end
            if placement.member.isPacked then
                AnchorPackedBlock(host, groupHost, placement, group)
            else
                if not placement.member.isGroup then
                    -- Child group hosts keep their own scale/size (already set by
                    -- their reflow); only plain display hosts are normalized.
                    host:SetScale(1)
                    host:SetSize(placement.width, placement.height)
                    host._quiGroupPlaced, host._quiGroupPacked = true, nil
                end
                host:ClearAllPoints()
                host:SetPoint("CENTER", groupHost, "TOPLEFT", placement.x, placement.y)
            end
            host:Show()
        end

        local isRoot = ParentKeyOf(store, groupName) == nil
        local shown = #placements > 0
            and (previewActive or GroupPreviewRelated(groupName) or group.enabled ~= false)
        if isRoot then
            local anchorKey = AD.GROUP_ANCHOR_PREFIX .. group.id
            local showGroup = shown and (layoutActive or not GameplayHidden(anchorKey))
            if showGroup then groupHost:Show() else groupHost:Hide() end
            if groupHost:GetParent() ~= UIParent then groupHost:SetParent(UIParent) end
            if not layoutActive and _G.QUI_ApplyFrameAnchor then
                _G.QUI_ApplyFrameAnchor(anchorKey)
            end
            if _G.QUI_LayoutModeSyncHandle then
                _G.QUI_LayoutModeSyncHandle(anchorKey)
            end
        else
            if shown then groupHost:Show() else groupHost:Hide() end
        end
        UpdateGroupBox(groupHost, groupName, PreviewBoxMode(groupName))
        return groupHost, width * scale, height * scale, shown
    end

    for key in pairs(groupsWithContent) do
        if ParentKeyOf(store, key) == nil then
            ReflowGroup(key)
        end
    end

    for groupID, host in pairs(groupHosts) do
        if not seenGroupIDs[groupID] then host:Hide() end
    end
    return true
end

function AD.RegisterLayoutElement(display)
    if GroupKey(display.group) ~= nil then return end
    local um = ns.QUI_LayoutMode
    if not um or type(um.RegisterElement) ~= "function" then return end
    local id = display.id
    um:RegisterElement({
        key = AD.ANCHOR_PREFIX .. id,
        label = display.name or id,
        group = ns.L["Aura Displays"],
        order = 100,
        isOwned = true,
        isEnabled = function()
            local d = AD.GetDisplay(id)
            return d ~= nil and d.enabled ~= false
        end,
        setEnabled = function(value)
            local d = AD.GetDisplay(id)
            if d then d.enabled = value and true or false end
            AD.Refresh()
        end,
        setGameplayHidden = function(hide)
            local host = hosts[id]
            if not host then return end
            if hide then host:Hide() else host:Show() end
        end,
        getFrame = function()
            return hosts[id]
        end,
        getSize = function()
            local host = hosts[id]
            return host and host._naturalW, host and host._naturalH
        end,
    })
    if _G.QUI_RegisterFrameResolver then
        _G.QUI_RegisterFrameResolver(AD.ANCHOR_PREFIX .. id, {
            resolver = function() return hosts[id] end,
            displayName = display.name or id,
            category = ns.L["Aura Displays"],
            order = 100,
        })
    end
end

function AD.RegisterGroupLayoutElement(groupName, group)
    group = group or AD.GetGroup(groupName, false)
    if not group then return end
    local um = ns.QUI_LayoutMode
    if not um or type(um.RegisterElement) ~= "function" then return end
    local anchorKey = AD.GROUP_ANCHOR_PREFIX .. group.id
    um:RegisterElement({
        key = anchorKey,
        label = groupName,
        group = ns.L["Aura Displays"],
        order = 100,
        isOwned = true,
        isEnabled = function()
            local current = AD.GetGroup(groupName, false)
            return current ~= nil and current.enabled ~= false
                and #AD.GroupTreeDisplays(groupName) > 0
        end,
        setEnabled = function(value)
            AD.SetGroupEnabled(groupName, value)
            AD.Refresh()
        end,
        setGameplayHidden = function(hide)
            local host = groupHosts[group.id]
            if not host then return end
            if hide then host:Hide() else host:Show() end
        end,
        getFrame = function()
            return groupHosts[group.id]
        end,
    })
    if _G.QUI_RegisterFrameResolver then
        _G.QUI_RegisterFrameResolver(anchorKey, {
            resolver = function() return groupHosts[group.id] end,
            displayName = groupName,
            category = ns.L["Aura Displays"],
            order = 100,
        })
    end
end

function AD.UnregisterLayoutElement(id, keepHost)
    local um = ns.QUI_LayoutMode
    if um and type(um.UnregisterElement) == "function" then
        um:UnregisterElement(AD.ANCHOR_PREFIX .. id)
    end
    if _G.QUI_UnregisterFrameResolver then
        _G.QUI_UnregisterFrameResolver(AD.ANCHOR_PREFIX .. id)
    end
    local host = hosts[id]
    if host and not keepHost then
        host:Hide()
        hosts[id] = nil
    end
end


function AD.UnregisterGroupLayoutElement(groupOrName, keepHost)
    local group = type(groupOrName) == "table" and groupOrName
        or AD.GetGroup(groupOrName, false)
    if not group or type(group.id) ~= "string" then return end
    local anchorKey = AD.GROUP_ANCHOR_PREFIX .. group.id
    local um = ns.QUI_LayoutMode
    if um and type(um.UnregisterElement) == "function" then
        um:UnregisterElement(anchorKey)
    end
    if _G.QUI_UnregisterFrameResolver then
        _G.QUI_UnregisterFrameResolver(anchorKey)
    end
    local host = groupHosts[group.id]
    if host and not keepHost then
        host:Hide()
        groupHosts[group.id] = nil
    end
end

function AD.Refresh()
    if not ResolveDeps() then return end
    local store = Store()
    ReconcileAuraSounds(store)
    if previewActive then return end
    local seen = {}
    local seenGroups = {}
    local dynamic = false
    local displays = {}
    if store and store.enabled ~= false then
        displays = AD.OrderedDisplays()
        for i = 1, #displays do
            local display = displays[i]
            seen[display.id] = true
            if (display.unitMode or "token") == "token"
                and STATIC_TOKENS[display.unit] == false then
                dynamic = true
            end
            local ok = ns.SafeCall("best-effort-style", ApplyDisplay, display, true)
            if not ok then RequeueDisplay(display) end
        end
        AD.ReflowGroups(displays)

        for i = 1, #displays do
            local display = displays[i]
            local groupName = GroupKey(display.group)
            if groupName then
                if registered[display.id] ~= nil then
                    registered[display.id] = nil
                    AD.UnregisterLayoutElement(display.id, true)
                end
                -- Only root groups own movers; nested groups flow inside them.
                local rootName = AD.RootGroupName(groupName) or groupName
                local group = AD.GetGroup(rootName, true)
                if group then seenGroups[group.id] = { name = rootName, group = group } end
            else
                local stamp = tostring(display.name or display.id)
                    .. (hosts[display.id] and "+" or "-")
                if registered[display.id] ~= stamp then
                    registered[display.id] = stamp
                    AD.RegisterLayoutElement(display)
                end
            end
        end

        for groupID, entry in pairs(seenGroups) do
            local stamp = entry.name .. (groupHosts[groupID] and "+" or "-")
            if registeredGroups[groupID] ~= stamp then
                registeredGroups[groupID] = stamp
                AD.RegisterGroupLayoutElement(entry.name, entry.group)
            end
        end
    end
    for id, host in pairs(hosts) do
        if not seen[id] then ParkOrphanHost(host) end
    end
    for id in pairs(registered) do
        if not seen[id] then
            registered[id] = nil
            AD.UnregisterLayoutElement(id)
        end
    end
    for groupID in pairs(registeredGroups) do
        if not seenGroups[groupID] then
            registeredGroups[groupID] = nil
            -- Keep the host: a group that stops being a root (nested under a
            -- parent) loses its mover but its frame still flows as a block.
            AD.UnregisterGroupLayoutElement({ id = groupID }, true)
        end
    end
    watchingDynamicUnits = dynamic
    if ns.RefreshAuraDisplaysVisibility then
        ns.RefreshAuraDisplaysVisibility()
    end
end

local function ShowPreviewForDisplay(display)
    local Preview = ns.AuraPreview
    if not Preview or type(Preview.Show) ~= "function" then return end
    local host = hosts[display.id] or EnsureHost(display.id)
    if not host then return end
    E.EnsureSeeded(display.auras, AD.DefaultBucket)
    local H = Helpers()
    local specID = H and type(H.GetCurrentSpecID) == "function"
        and H.GetCurrentSpecID() or nil
    local elements = E.ActiveElementsForSpec(display.auras, specID)
    DisableHostContainers(host)
    local layout = BuildDisplayLayout(display, elements, true)
    host._naturalW, host._naturalH = layout.width, layout.height
    host:SetSize(layout.width, layout.height)
    host:SetAlpha(1)
    host:Show()
    Preview.Show(host, elements, {
        resolve = function(element)
            local profile = layout.profiles[element] or DisplayElementProfile(element)
            local placement = layout.placements[element]
            return profile, placement and placement.relativePoint or element.anchor or "TOPLEFT",
                placement and placement.offsetX or element.offsetX or 0,
                placement and placement.offsetY or element.offsetY or 0,
                placement and placement.pinCorner
        end,
    })
    if _G.QUI_LayoutModeSyncHandle then
        _G.QUI_LayoutModeSyncHandle(AD.ANCHOR_PREFIX .. display.id)
    end
    return true
end

function AD.ShowPreview()
    if previewActive then return end
    if not ResolveDeps() then return end
    local Preview = ns.AuraPreview
    if not Preview or type(Preview.Show) ~= "function" then return end
    previewActive = true
    singlePreviewID = nil
    singlePreviewGroup = nil
    local displays = AD.OrderedDisplays()
    for i = 1, #displays do
        ShowPreviewForDisplay(displays[i])
    end
    AD.ReflowGroups(displays)
end

function AD.HidePreview()
    if not previewActive then return end
    previewActive = false
    singlePreviewID = nil
    singlePreviewGroup = nil
    local Preview = ns.AuraPreview
    if Preview and type(Preview.Hide) == "function" then
        for _, host in pairs(hosts) do
            Preview.Hide(host)
        end
    end
    AD.Refresh()
end

function AD.ShowPreviewFor(id)
    if previewActive then return end
    if not ResolveDeps() then return end
    local display = AD.GetDisplay(id)
    if not display then return end
    if singlePreviewGroup then AD.HidePreviewForGroup(singlePreviewGroup) end
    if singlePreviewID and singlePreviewID ~= id then
        AD.HidePreviewFor(singlePreviewID)
    end
    singlePreviewID = id
    if ShowPreviewForDisplay(display) then
        AD.ReflowGroups()
    else
        singlePreviewID = nil
    end
end

function AD.HidePreviewFor(id)
    if previewActive then return end
    if singlePreviewID ~= id then return end
    singlePreviewID = nil
    AD.DisablePreviewDrag()
    local Preview = ns.AuraPreview
    local host = hosts[id]
    if Preview and type(Preview.Hide) == "function" and host then
        Preview.Hide(host)
    end
    AD.Refresh()
end

function AD.ShowPreviewForGroup(groupName)
    local key = GroupKey(groupName)
    if previewActive or key == nil then return end
    if singlePreviewID then AD.HidePreviewFor(singlePreviewID) end
    if singlePreviewGroup and singlePreviewGroup ~= key then
        AD.HidePreviewForGroup(singlePreviewGroup)
    end
    singlePreviewGroup = key
    local shown = false
    local displays = AD.GroupTreeDisplays(key)
    for i = 1, #displays do
        if ShowPreviewForDisplay(displays[i]) then shown = true end
    end
    if shown then
        AD.ReflowGroups()
    else
        singlePreviewGroup = nil
    end
end

function AD.HidePreviewForGroup(groupName)
    local key = GroupKey(groupName)
    if previewActive or singlePreviewGroup ~= key then return end
    singlePreviewGroup = nil
    AD.DisablePreviewDrag()
    local Preview = ns.AuraPreview
    if Preview and type(Preview.Hide) == "function" then
        local displays = AD.GroupTreeDisplays(key)
        for i = 1, #displays do
            local host = hosts[displays[i].id]
            if host then Preview.Hide(host) end
        end
    end
    AD.Refresh()
end

local WATCHED_EVENTS = {
    "PLAYER_ENTERING_WORLD",
    "PLAYER_REGEN_ENABLED",
    "ZONE_CHANGED_NEW_AREA",
    "GROUP_ROSTER_UPDATE",
    "PLAYER_SPECIALIZATION_CHANGED",
    "PLAYER_ROLES_ASSIGNED",
    "ENCOUNTER_START",
    "ENCOUNTER_END",
    "PLAYER_TARGET_CHANGED",
    "PLAYER_FOCUS_CHANGED",
    "UPDATE_MOUSEOVER_UNIT",
    "UNIT_FACTION",
}

local REACTION_EVENTS = {
    PLAYER_TARGET_CHANGED = true,
    PLAYER_FOCUS_CHANGED = true,
    UPDATE_MOUSEOVER_UNIT = true,
    UNIT_FACTION = true,
}

local function OnEvent(_, event, arg1)
    if event == "ENCOUNTER_START" then
        AD.SetEncounter(arg1)
    elseif event == "ENCOUNTER_END" then
        AD.SetEncounter(nil)
    elseif REACTION_EVENTS[event] and not watchingDynamicUnits then
        return
    end
    AD.Refresh()
end

function AD.Init()
    if eventFrame then return end
    eventFrame = CreateFrame("Frame")
    for i = 1, #WATCHED_EVENTS do
        eventFrame:RegisterEvent(WATCHED_EVENTS[i])
    end
    eventFrame:SetScript("OnEvent", OnEvent)
    local um = ns.QUI_LayoutMode
    if um then
        if type(um.RegisterEnterCallback) == "function" then
            um:RegisterEnterCallback(AD.ShowPreview)
        end
        if type(um.RegisterExitCallback) == "function" then
            um:RegisterExitCallback(AD.HidePreview)
        end
    end
    AD.Refresh()
end

if ns.Registry then
    ns.Registry:Register("auraDisplays", {
        refresh = AD.Refresh,
        priority = 60,
        group = "ui",
        importCategories = { "auraDisplays" },
    })
end

if ns.RunAfterFirstFrame then ns.RunAfterFirstFrame(AD.Init, 0.1) end

return AD
