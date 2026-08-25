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

local function EnsureGroup(store, key)
    local group = store.groups[key]
    if not group then
        group = { collapsed = false, enabled = true }
        store.groups[key] = group
    end
    return group
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
    local group = store.groups[key]
    return not (group and group.enabled == false)
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
    store.groups[key] = nil
    for _, display in pairs(store.displays) do
        if display.group == key then display.group = nil end
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
    store.groups[to] = group or { collapsed = false, enabled = true }
    for _, display in pairs(store.displays) do
        if display.group == from then display.group = to end
    end
    return true
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
    if not SetIsEmpty(load.encounters) then
        if not activeEncounter or load.encounters[activeEncounter] ~= true then return false end
    end
    return true
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
local registered = {}
local eventFrame
local watchingDynamicUnits = false

function AD.HostFor(id)
    return hosts[id]
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

local previewActive = false
local singlePreviewID

local ApplyDisplay

local function GameplayHidden(id)
    local H = Helpers()
    local profile = H and type(H.GetProfile) == "function" and H.GetProfile() or nil
    local hiddenHandles = profile and profile.layoutMode and profile.layoutMode.hiddenHandles
    return hiddenHandles ~= nil and hiddenHandles[AD.ANCHOR_PREFIX .. id] == true
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

    if unit then
        host:SetAlpha(1)
        if layoutActive or not GameplayHidden(display.id) then
            host:Show()
        else
            host:Hide()
            local lm = ns.QUI_LayoutMode
            if lm then
                lm._gameplayHidden = lm._gameplayHidden or {}
                lm._gameplayHidden[AD.ANCHOR_PREFIX .. display.id] = true
            end
        end
    else
        host:SetAlpha(0)
    end

    if not layoutActive and _G.QUI_ApplyFrameAnchor then
        _G.QUI_ApplyFrameAnchor(AD.ANCHOR_PREFIX .. display.id)
    end
end

function AD.RegisterLayoutElement(display)
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

function AD.UnregisterLayoutElement(id)
    local um = ns.QUI_LayoutMode
    if um and type(um.UnregisterElement) == "function" then
        um:UnregisterElement(AD.ANCHOR_PREFIX .. id)
    end
    if _G.QUI_UnregisterFrameResolver then
        _G.QUI_UnregisterFrameResolver(AD.ANCHOR_PREFIX .. id)
    end
    local host = hosts[id]
    if host then
        host:Hide()
        hosts[id] = nil
    end
end

function AD.Refresh()
    if not ResolveDeps() then return end
    if previewActive then return end
    local store = Store()
    local seen = {}
    local dynamic = false
    if store and store.enabled ~= false then
        local displays = AD.OrderedDisplays()
        for i = 1, #displays do
            local display = displays[i]
            seen[display.id] = true
            if (display.unitMode or "token") == "token"
                and STATIC_TOKENS[display.unit] == false then
                dynamic = true
            end
            local ok = ns.SafeCall("best-effort-style", ApplyDisplay, display, true)
            if not ok then RequeueDisplay(display) end
            local stamp = tostring(display.name or display.id)
                .. (hosts[display.id] and "+" or "-")
            if registered[display.id] ~= stamp then
                registered[display.id] = stamp
                AD.RegisterLayoutElement(display)
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
    watchingDynamicUnits = dynamic
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
    local displays = AD.OrderedDisplays()
    for i = 1, #displays do
        ShowPreviewForDisplay(displays[i])
    end
end

function AD.HidePreview()
    if not previewActive then return end
    previewActive = false
    singlePreviewID = nil
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
    if singlePreviewID and singlePreviewID ~= id then
        AD.HidePreviewFor(singlePreviewID)
    end
    if ShowPreviewForDisplay(display) then
        singlePreviewID = id
    end
end

function AD.HidePreviewFor(id)
    if previewActive then return end
    if singlePreviewID ~= id then return end
    singlePreviewID = nil
    local Preview = ns.AuraPreview
    local host = hosts[id]
    if Preview and type(Preview.Hide) == "function" and host then
        Preview.Hide(host)
    end
    AD.Refresh()
end

local WATCHED_EVENTS = {
    "PLAYER_ENTERING_WORLD",
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
