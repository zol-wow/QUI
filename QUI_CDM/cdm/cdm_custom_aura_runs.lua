local _, ns = ...

local Runs = {}
ns.CDMCustomAuraRuns = Runs

local activeOwners = setmetatable({}, { __mode = "k" })
local HELPFUL_FILTER = "HELPFUL|PLAYER|INCLUDE_NAME_PLATE_ONLY"
local HARMFUL_FILTER = "HARMFUL|PLAYER"

local function IsSecret(value)
    return issecretvalue and issecretvalue(value)
end

local function IsManagedAuraIcon(icon)
    local entry = icon and icon._spellEntry
    return entry and entry._useManagedAura == true
end

function Runs.ShouldUseSettings(settings)
    if type(settings) ~= "table" or settings.containerType ~= "customBar" then return false end
    if settings.layoutDirection == "VERTICAL" then return false end
    if settings.growDirection and settings.growDirection ~= "RIGHT" then return false end

    local rowCount = 0
    for i = 1, 3 do
        local row = settings["row" .. i]
        if row and (row.iconCount or 0) > 0 then
            rowCount = rowCount + 1
        end
    end
    return rowCount == 1
end

function Runs.IsManagedAuraIcon(icon)
    return IsManagedAuraIcon(icon)
end

function Runs.HasAuraEntries(settings, viewerType)
    local entries
    if settings and settings.specSpecific and ns.CDMSpellData and ns.CDMSpellData.GetSpecEntries then
        entries = ns.CDMSpellData:GetSpecEntries(viewerType)
    end
    entries = type(entries) == "table" and entries or (settings and settings.entries)
    if type(entries) ~= "table" then return false end
    for i = 1, #entries do
        local entry = entries[i]
        if entry and entry.enabled ~= false and entry.kind == "aura" then return true end
    end
    return false
end

local function CandidateIDs(entry)
    local out, seen = {}, {}
    local function add(value)
        if type(value) == "number" and not IsSecret(value) and not seen[value] then
            seen[value] = true
            out[#out + 1] = value
        end
    end

    local mirrors = ns.CDMManagedAuraMirrors
    if mirrors and mirrors.ResolveCandidateIDs then
        local ids = mirrors.ResolveCandidateIDs(entry, IsSecret)
        for i = 1, #ids do add(ids[i]) end
    else
        add(entry and (entry.overrideSpellID or entry.spellID or entry.id))
    end

    local runtime = ns.CDMAuraRuntime
    if runtime and runtime.ResolveAbilityAuraSpellID then
        local mapped = runtime.ResolveAbilityAuraSpellID(entry and (entry.id or entry.spellID))
        add(mapped)
    end

    local spellData = ns.CDMSpellData
    if spellData and spellData.GetAuraIDsForSpell then
        local ids = spellData:GetAuraIDsForSpell(entry and (entry.id or entry.spellID))
        if type(ids) == "table" then
            for i = 1, #ids do add(ids[i]) end
        end
    end
    return out
end

local function Profile(rowConfig)
    local size = rowConfig.size or 39
    local aspect = rowConfig.aspectRatioCrop or 1
    if aspect <= 0 then aspect = 1 end
    local ncdm = ns.Addon and ns.Addon.db and ns.Addon.db.profile and ns.Addon.db.profile.ncdm
    local borderColor = rowConfig.borderColor
    if ns.Helpers and ns.Helpers.GetSkinBorderColor then
        local r, g, b, a = ns.Helpers.GetSkinBorderColor(rowConfig, "")
        borderColor = { r, g, b, a }
    end
    return {
        maxIcons = 1,
        iconSize = size,
        iconWidth = size,
        iconHeight = size / aspect,
        spacing = rowConfig.padding or 0,
        grow = "RIGHT",
        maxPerRow = 0,
        anchor = "TOPLEFT",
        borderSize = rowConfig.borderSize or 1,
        showBorder = (rowConfig.borderSize or 1) > 0,
        borderColor = borderColor,
        hideSwipe = false,
        reverseSwipe = false,
        swipeStyle = "radial",
        duration = {
            show = rowConfig.hideDurationText ~= true,
            fontSize = rowConfig.durationSize or 14,
            anchor = rowConfig.durationAnchor or "CENTER",
            offsetX = rowConfig.durationOffsetX or 0,
            offsetY = rowConfig.durationOffsetY or 0,
            color = rowConfig.durationTextColor,
        },
        stack = {
            show = rowConfig.hideStackText ~= true,
            fontSize = rowConfig.stackSize or 14,
            anchor = rowConfig.stackAnchor or "BOTTOMRIGHT",
            offsetX = rowConfig.stackOffsetX or 0,
            offsetY = rowConfig.stackOffsetY or 0,
            color = rowConfig.stackTextColor,
        },
        externalSkinning = ncdm and ncdm.externalSkinning == true,
        externalSkinKey = "cdm",
        iconSkin = ncdm and ncdm.iconSkin,
    }
end

local function AcquireRun(owner, index)
    local pool = owner._quiCDMAuraRuns
    if not pool then
        pool = {}
        owner._quiCDMAuraRuns = pool
    end
    local container = pool[index]
    if not container then
        container = CreateFrame("AuraContainer", nil, owner, "CustomAuraContainerTemplate")
        container:SetSize(1, 1)
        pool[index] = container
    end
    return container, pool
end

local function BuildGroup(icon, index)
    local ids = CandidateIDs(icon._spellEntry)
    local include = {}
    for i = 1, #ids do include[ids[i]] = true end
    local filters = next(include) and { includeSpellIDs = include } or { maxDuration = 0 }
    return {
        key = "a" .. tostring(index),
        filter = HELPFUL_FILTER,
        maxFrameCount = 1,
        candidateFilters = filters,
    }
end

local function AuraRoute(icon)
    local entry = icon and icon._spellEntry
    if entry and entry._selfAura == true then return "SELF_HELPFUL" end
    local sources = ns.CDMSources
    local ids = CandidateIDs(entry)
    if sources and sources.QuerySpellHarmful then
        for i = 1, #ids do
            if sources.QuerySpellHarmful(ids[i]) == true then return "HARMFUL" end
        end
    end
    if sources and sources.QuerySpellHelpful then
        for i = 1, #ids do
            if sources.QuerySpellHelpful(ids[i]) == true then return "HELPFUL" end
        end
    end
    return "SELF_HELPFUL"
end

local function FriendlyTarget()
    return UnitExists and UnitExists("target")
        and UnitIsFriend and UnitIsFriend("player", "target") == true
end

local function HostileTarget()
    return UnitExists and UnitExists("target")
        and UnitCanAttack and UnitCanAttack("player", "target") == true
end

local function RouteActive(route)
    return route == "SELF_HELPFUL"
        or (route == "HELPFUL" and FriendlyTarget())
        or (route == "HARMFUL" and HostileTarget())
end

local function ApplyRoute(record)
    local unit = record.route == "SELF_HELPFUL" and "player" or "target"
    local filter = record.route == "HARMFUL" and HARMFUL_FILTER or HELPFUL_FILTER
    local active = RouteActive(record.route)
    local cancel = record.route == "SELF_HELPFUL" and "RightButtonUp" or nil
    for i = 1, #record.groups do
        local group = record.groups[i]
        group.filter = filter
        group.maxFrameCount = active and 1 or 0
        group.cancelButtons = cancel
    end
    local container = record.container
    container:SetUnit(unit)
    record.AuraSkin.Configure(container, record.profile, record.groups)
    container:SetEnabled(true)
    container:Show()
end

function Runs.RefreshTargets()
    for owner in pairs(activeOwners) do
        local records = owner._quiCDMAuraRunRecords
        if records then
            for i = 1, #records do
                local record = records[i]
                if record.route ~= "SELF_HELPFUL" then
                    local maxFrameCount = RouteActive(record.route) and 1 or 0
                    for j = 1, #record.groups do
                        local group = record.groups[j]
                        if group.maxFrameCount ~= maxFrameCount then
                            group.maxFrameCount = maxFrameCount
                            record.container:SetAuraGroupMaxFrameCount(group.key, maxFrameCount)
                        end
                    end
                end
            end
        end
    end
end

local function HideProxy(icon)
    icon._quiManagedAuraProxy = true
    icon:ClearAllPoints()
    icon:Hide()
end

local function Disable(owner)
    if owner then activeOwners[owner] = nil end
    local pool = owner and owner._quiCDMAuraRuns
    if not pool then return end
    local AuraSkin = ns.AuraSkin or (ns.Addon and ns.Addon.AuraSkin)
    for i = 1, #pool do
        local container = pool[i]
        if AuraSkin and AuraSkin.Configure then
            AuraSkin.Configure(container, container._quiProfile or {}, {})
        end
        container:SetEnabled(false)
        container:Hide()
    end
end

function Runs.Apply(owner, settings, layoutPlan)
    if not (owner and Runs.ShouldUseSettings(settings) and layoutPlan and layoutPlan.placements) then
        Disable(owner)
        return false
    end

    local AuraSkin = ns.AuraSkin or (ns.Addon and ns.Addon.AuraSkin)
    local Layout = ns.CDMLayout
    if not (AuraSkin and AuraSkin.Configure and Layout and Layout.AnchorLinearChain) then return false end

    local chain = {}
    local runRecords = {}
    local currentRun
    local runCount = 0
    local firstPlacement

    for i = 1, #layoutPlan.placements do
        local placement = layoutPlan.placements[i]
        local icon = placement.icon
        if IsManagedAuraIcon(icon) then
            local route = AuraRoute(icon)
            if not currentRun or currentRun.route ~= route then
                runCount = runCount + 1
                local container = AcquireRun(owner, runCount)
                currentRun = {
                    container = container,
                    groups = {},
                    rowConfig = placement.rowConfig,
                    route = route,
                }
                runRecords[#runRecords + 1] = currentRun
                chain[#chain + 1] = container
            end
            currentRun.groups[#currentRun.groups + 1] = BuildGroup(icon, #currentRun.groups + 1)
            HideProxy(icon)
        else
            currentRun = nil
            chain[#chain + 1] = icon
        end
        firstPlacement = firstPlacement or placement
    end

    if #runRecords == 0 or not firstPlacement then
        Disable(owner)
        return false
    end

    for i = 1, #runRecords do
        local record = runRecords[i]
        record.profile = Profile(record.rowConfig)
        record.AuraSkin = AuraSkin
        ApplyRoute(record)
    end

    owner._quiCDMAuraRunRecords = runRecords
    activeOwners[owner] = true

    local pool = owner._quiCDMAuraRuns or {}
    for i = runCount + 1, #pool do
        local container = pool[i]
        AuraSkin.Configure(container, container._quiProfile or {}, {})
        container:SetEnabled(false)
        container:Hide()
    end

    local metrics = layoutPlan.metrics or {}
    local rowConfig = firstPlacement.rowConfig
    local width = rowConfig.size or 39
    local offsetX = firstPlacement.x + ((metrics.iconWidth or width) * 0.5) - (width * 0.5)
    return Layout.AnchorLinearChain(owner, chain, {
        axis = "HORIZONTAL",
        grow = "RIGHT",
        spacing = rowConfig.padding or 0,
        offsetX = offsetX,
        offsetY = firstPlacement.y or 0,
    })
end

return Runs
