local _, ns = ...

local Runs = {}
ns.CDMCustomAuraRuns = Runs

local activeOwners = setmetatable({}, { __mode = "k" })
local activeAuraOverlayOwners = setmetatable({}, { __mode = "k" })
local preparedAuraOverlayOwners = setmetatable({}, { __mode = "k" })
local preparedAuraOverlayIcons = setmetatable({}, { __mode = "k" })
local HELPFUL_FILTER = "HELPFUL|PLAYER|INCLUDE_NAME_PLATE_ONLY"
local HARMFUL_FILTER = "HARMFUL|PLAYER"
local PET_AURA_UNITS = { [1235391] = true }
local ResolveRoute
local auraOverlayManagers = {}

local function ClearPreparedAuraOverlayIcons(owner)
    local icons = owner and preparedAuraOverlayIcons[owner]
    if not icons then return end
    for icon in pairs(icons) do
        icon._customAuraOverlayPrepared = nil
    end
    preparedAuraOverlayIcons[owner] = nil
end

local function IsSecret(value)
    return issecretvalue and issecretvalue(value)
end

local function IsManagedAuraIcon(icon)
    local entry = icon and icon._spellEntry
    return entry and entry._useManagedAura == true and entry._managedAuraRoute ~= nil
end

local function EntryListHasAlerts(entries)
    if type(entries) ~= "table" then return false end
    for _, entry in pairs(entries) do
        if ns.CDMAlerts and ns.CDMAlerts.HasEnabled and ns.CDMAlerts.HasEnabled(entry) then
            return true
        end
    end
    return false
end

local function SettingsHaveAlerts(settings, viewerType)
    if EntryListHasAlerts(settings and settings.entries) then return true end
    local globalDB = ns.Addon and ns.Addon.db and ns.Addon.db.global
    local root = globalDB and globalDB.ncdm and globalDB.ncdm.specTrackerSpells
    local bySpec = root and root[viewerType]
    if type(bySpec) ~= "table" then return false end
    for _, entries in pairs(bySpec) do
        if EntryListHasAlerts(entries) then return true end
    end
    return false
end

function Runs.ShouldUseSettings(settings, viewerType)
    if type(settings) ~= "table" or settings.containerType ~= "customBar" then return false end
    if type(viewerType) ~= "string" or viewerType == "" then return false end
    if SettingsHaveAlerts(settings, viewerType) then return false end
    if settings.dynamicLayout ~= true then return false end
    if settings.clickableIcons == true then return false end
    if settings.activeGlowEnabled ~= false then return false end
    if settings.showOnlyWhenActive ~= true
        or settings.showOnlyOnCooldown == true
        or settings.showOnlyWhenOffCooldown == true
        or settings.showOnlyInCombat == true
        or settings.hideNonUsable == true then
        return false
    end
    if settings.layoutDirection == "VERTICAL" then return false end
    if settings.growDirection and settings.growDirection ~= "RIGHT" then return false end

    if type(settings.spellOverrides) == "table" then
        for _, override in pairs(settings.spellOverrides) do
            if type(override) == "table" and next(override) ~= nil then return false end
        end
    end

    local profile = ns.Addon and ns.Addon.db and ns.Addon.db.profile
    local glow = profile and profile.customGlow
    if not glow then return false end
    if glow[viewerType .. "Enabled"] == true
        or glow[viewerType .. "PandemicDebuffEnabled"] ~= false
        or glow[viewerType .. "PandemicBuffEnabled"] ~= false then
        return false
    end

    local rowCount = 0
    if settings.row1 and (settings.row1.iconCount or 0) > 0 then rowCount = rowCount + 1 end
    if settings.row2 and (settings.row2.iconCount or 0) > 0 then rowCount = rowCount + 1 end
    if settings.row3 and (settings.row3.iconCount or 0) > 0 then rowCount = rowCount + 1 end
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
        if entry and entry.enabled ~= false and entry.kind == "aura"
            and ResolveRoute and ResolveRoute(entry) then
            return true
        end
    end
    return false
end

local function IsCooldownAuraOverlayEntry(entry)
    return type(entry) == "table"
        and entry.enabled ~= false
        and entry._isCustomEntry == true
        and entry.kind == "cooldown"
        and (entry.type == nil or entry.type == "spell")
end

function Runs.ShouldUseCooldownAuraOverlays(settings, viewerType)
    if type(settings) ~= "table" or settings.containerType ~= "customBar" then return false end
    if type(viewerType) ~= "string" or viewerType == "" then return false end
    local swipe = ns._OwnedSwipe
    local swipeSettings = swipe and swipe.GetSettings and swipe.GetSettings()
    if swipeSettings and swipeSettings.showCooldownIconAuraPhase == false then return false end
    if (settings.iconDisplayMode or "always") ~= "always" then return false end
    if settings.showActiveState == false or settings.hideNonUsable == true then return false end
    return settings.showOnlyWhenActive ~= true
        and settings.showOnlyOnCooldown ~= true
        and settings.showOnlyWhenOffCooldown ~= true
        and settings.showOnlyInCombat ~= true
end

function Runs.HasCooldownAuraOverlayEntries(settings, viewerType)
    if not Runs.ShouldUseCooldownAuraOverlays(settings, viewerType) then return false end
    local entries
    if settings.specSpecific and ns.CDMSpellData and ns.CDMSpellData.GetSpecEntries then
        entries = ns.CDMSpellData:GetSpecEntries(viewerType)
    end
    entries = type(entries) == "table" and entries or settings.entries
    if type(entries) ~= "table" then return false end
    for i = 1, #entries do
        local entry = entries[i]
        if entry and entry.enabled ~= false and entry.kind == "cooldown"
            and (entry.type == nil or entry.type == "spell") then
            return true
        end
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

local function ResolveCooldownAuraUnit(entry)
    local unit = entry and entry.auraUnit
    if unit == "player" or unit == "pet" then return unit end
    local ids = CandidateIDs(entry)
    for i = 1, #ids do
        if PET_AURA_UNITS[ids[i]] then return "pet" end
    end
    return "player"
end

ResolveRoute = function(entry)
    if type(entry) ~= "table" or entry.source ~= "blizzardCDM" then return nil end
    local selfAura = entry._selfAura
    if entry.kind ~= "aura" then selfAura = nil end
    if selfAura == nil then
        local spellData = ns.CDMSpellData
        if spellData and spellData.IsSelfAuraSpell then
            selfAura = spellData:IsSelfAuraSpell(entry.id or entry.spellID)
        end
    end
    if selfAura == nil then return nil end

    local helpful, harmful = false, false
    local sources = ns.CDMSources
    local ids = CandidateIDs(entry)
    for i = 1, #ids do
        local spellID = ids[i]
        helpful = helpful or (sources and sources.QuerySpellHelpful
            and sources.QuerySpellHelpful(spellID) == true) or false
        harmful = harmful or (sources and sources.QuerySpellHarmful
            and sources.QuerySpellHarmful(spellID) == true) or false
    end
    if helpful == harmful then return nil end
    if selfAura == true then return helpful and "SELF_HELPFUL" or nil end
    return helpful and "HELPFUL" or "HARMFUL"
end

function Runs.ResolveRoute(entry)
    return ResolveRoute(entry)
end

local function Profile(rowConfig)
    local size = rowConfig.size or 39
    local aspect = rowConfig.aspectRatioCrop or 1
    if aspect <= 0 then aspect = 1 end
    local ncdm = ns.Addon and ns.Addon.db and ns.Addon.db.profile and ns.Addon.db.profile.ncdm
    local borderColor = rowConfig.borderColor
    local durationFont, stackFont
    local LSM = ns.LSM
    if LSM and type(rowConfig.durationFont) == "string" and rowConfig.durationFont ~= "" then
        durationFont = LSM:Fetch("font", rowConfig.durationFont)
    end
    if LSM and type(rowConfig.stackFont) == "string" and rowConfig.stackFont ~= "" then
        stackFont = LSM:Fetch("font", rowConfig.stackFont)
    end
    if ns.Helpers and ns.Helpers.GetSkinBorderColor then
        local r, g, b, a = ns.Helpers.GetSkinBorderColor(rowConfig, "")
        borderColor = { r, g, b, a }
    end
    local swipeSettings = ns._OwnedSwipe
        and ns._OwnedSwipe.GetSettings
        and ns._OwnedSwipe.GetSettings()
    local showSwipe = not (swipeSettings and swipeSettings.showBuffSwipe == false)
    local showEdge = showSwipe and not (swipeSettings and swipeSettings.showBuffEdge == false)
    local swipeColor
    if ns._CDM_ResolveModeColor and swipeSettings then
        local r, g, b, a = ns._CDM_ResolveModeColor(swipeSettings, "aura")
        swipeColor = { r, g, b, a }
    elseif swipeSettings and swipeSettings.overlayColorMode == "custom"
        and type(swipeSettings.overlayColor) == "table" then
        local c = swipeSettings.overlayColor
        swipeColor = { c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1 }
    else
        swipeColor = { 0.93, 0.77, 0, 0.45 }
    end
    return {
        maxIcons = 1,
        iconSize = size,
        iconWidth = size,
        iconHeight = size / aspect,
        spacing = rowConfig.padding or 0,
        opacity = rowConfig.opacity or 1,
        zoom = rowConfig.zoom or 0,
        aspectRatioCrop = aspect,
        grow = "RIGHT",
        maxPerRow = 0,
        anchor = "TOPLEFT",
        borderSize = rowConfig.borderSize or 1,
        showBorder = (rowConfig.borderSize or 1) > 0,
        borderColor = borderColor,
        hideSwipe = not showSwipe,
        showEdge = showEdge,
        swipeTexture = "Interface\\Buttons\\WHITE8X8",
        swipeColor = swipeColor,
        reverseSwipe = true,
        swipeStyle = "radial",
        duration = {
            show = rowConfig.hideDurationText ~= true,
            font = durationFont,
            fontSize = rowConfig.durationSize or 14,
            anchor = rowConfig.durationAnchor or "CENTER",
            offsetX = rowConfig.durationOffsetX or 0,
            offsetY = rowConfig.durationOffsetY or 0,
            color = rowConfig.durationTextColor,
        },
        stack = {
            show = rowConfig.hideStackText ~= true,
            font = stackFont,
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

local function GetAuraOverlayManager(unit)
    unit = unit or "player"
    if auraOverlayManagers[unit] then return auraOverlayManagers[unit] end
    local mirrors = ns.CDMManagedAuraMirrors
    if not (mirrors and mirrors.New) then return nil end
    local AuraSkin = ns.AuraSkin or (ns.Addon and ns.Addon.AuraSkin)
    local manager = mirrors.New({
        createFrame = CreateFrame,
        unit = unit,
        isSecret = IsSecret,
        canCreate = function()
            return not (InCombatLockdown and InCombatLockdown())
        end,
        canMutate = function()
            return not (InCombatLockdown and InCombatLockdown())
        end,
        aurasAreSecret = function()
            return C_Secrets and C_Secrets.ShouldAurasBeSecret
                and C_Secrets.ShouldAurasBeSecret()
        end,
        styleFrame = AuraSkin and AuraSkin.WireButton,
        restyleFrame = AuraSkin and function(frame, rowConfig)
            return AuraSkin.WireButton(frame, Profile(rowConfig))
        end,
    })
    auraOverlayManagers[unit] = manager
    return manager
end

local function DisableCooldownAuraOverlays(owner)
    ClearPreparedAuraOverlayIcons(owner)
    if not owner or not activeAuraOverlayOwners[owner] then return end
    for unit in pairs(auraOverlayManagers) do
        local manager = GetAuraOverlayManager(unit)
        if manager and manager:BeginPass(owner, false) then manager:EndPass(owner) end
    end
    activeAuraOverlayOwners[owner] = nil
end

function Runs.HasAuraOverlays(owner)
    return owner and activeAuraOverlayOwners[owner] == true
end

function Runs.HasPreparedAuraOverlays(owner)
    return owner and preparedAuraOverlayOwners[owner] == true
end

local function ApplyCooldownAuraOverlays(owner, settings, layoutPlan, inCombat, viewerType)
    if owner and not inCombat then
        ClearPreparedAuraOverlayIcons(owner)
    end
    if owner and not inCombat then
        preparedAuraOverlayOwners[owner] = Runs.ShouldUseCooldownAuraOverlays(settings, viewerType)
            and Runs.HasCooldownAuraOverlayEntries(settings, viewerType) or nil
    end
    if inCombat then return Runs.HasAuraOverlays(owner) end

    local eligible = owner
        and Runs.ShouldUseCooldownAuraOverlays(settings, viewerType)
        and layoutPlan and layoutPlan.placements
    if not eligible then
        DisableCooldownAuraOverlays(owner)
        return false
    end
    local managers = {}
    for i = 1, #layoutPlan.placements do
        local placement = layoutPlan.placements[i]
        if IsCooldownAuraOverlayEntry(placement.icon and placement.icon._spellEntry) then
            local unit = ResolveCooldownAuraUnit(placement.icon._spellEntry)
            if not managers[unit] then
                local manager = GetAuraOverlayManager(unit)
                if manager and manager:BeginPass(owner) then managers[unit] = manager end
            end
        end
    end
    for unit, manager in pairs(auraOverlayManagers) do
        if not managers[unit] and manager:BeginPass(owner, false) then
            managers[unit] = manager
        end
    end
    local managerCount = 0
    for _ in pairs(managers) do managerCount = managerCount + 1 end
    if managerCount == 0 then return Runs.HasAuraOverlays(owner) end

    local mirrored = 0
    local preparedIcons = {}
    for i = 1, #layoutPlan.placements do
        local placement = layoutPlan.placements[i]
        local icon = placement.icon
        if IsCooldownAuraOverlayEntry(icon and icon._spellEntry) then
            local rowConfig = placement.rowConfig or {}
            local width = rowConfig.size or 39
            local aspect = rowConfig.aspectRatioCrop or 1
            if aspect <= 0 then aspect = 1 end
            local manager = managers[ResolveCooldownAuraUnit(icon._spellEntry)]
            local record = manager and manager:Acquire(owner, icon, icon._spellEntry,
                Profile(rowConfig))
            if record and manager:PositionOverlay(record, icon, owner, placement.x, placement.y,
                width, width / aspect, rowConfig) then
                icon._customAuraOverlayPrepared = true
                preparedIcons[icon] = true
                mirrored = mirrored + 1
            end
        end
    end
    for _, manager in pairs(managers) do manager:EndPass(owner) end
    preparedAuraOverlayIcons[owner] = preparedIcons
    activeAuraOverlayOwners[owner] = mirrored > 0 or nil
    return mirrored > 0
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

local function BuildGroup(icon, index, rowConfig)
    local ids = CandidateIDs(icon._spellEntry)
    local include = {}
    for i = 1, #ids do include[ids[i]] = true end
    local filters = next(include) and { includeSpellIDs = include } or { maxDuration = 0 }
    local spacing = rowConfig.padding or 0
    return {
        key = "a" .. tostring(index),
        filter = HELPFUL_FILTER,
        maxFrameCount = 1,
        candidateFilters = filters,
        elementWidth = (rowConfig.size or 39) + spacing + 1,
        elementSpacing = -1,
    }
end

local function FriendlyTarget()
    return UnitExists and UnitExists("target")
        and UnitCanAssist and UnitCanAssist("player", "target") == true
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

function Runs.RefreshTargets(identityChanged)
    for owner in pairs(activeOwners) do
        local records = owner._quiCDMAuraRunRecords
        if records then
            for i = 1, #records do
                local record = records[i]
                if record.route ~= "SELF_HELPFUL" then
                    local maxFrameCount = RouteActive(record.route) and 1 or 0
                    local capacityChanged = false
                    for j = 1, #record.groups do
                        local group = record.groups[j]
                        if group.maxFrameCount ~= maxFrameCount then
                            capacityChanged = true
                            group.maxFrameCount = maxFrameCount
                            record.container:SetAuraGroupMaxFrameCount(group.key, maxFrameCount)
                        end
                    end
                    if (identityChanged or capacityChanged) and record.container.UpdateAllAuras then
                        record.container:UpdateAllAuras()
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

function Runs.HasActiveRuns(owner)
    return owner and activeOwners[owner] == true
end

function Runs.CanRelayoutInCombat(owner, settings, icons)
    local state = owner and owner._quiCDMAuraCombatState
    if not (activeOwners[owner] and state and state.settings == settings
        and state.icons == icons
        and state.valid ~= false and Runs.ShouldUseSettings(settings, state.viewerType)) then
        return false
    end
    local capacity = (settings.row1 and settings.row1.iconCount or 0)
        + (settings.row2 and settings.row2.iconCount or 0)
        + (settings.row3 and settings.row3.iconCount or 0)
    return state.capacity == capacity
        and #icons >= state.iconCount
end

function Runs.InvalidatePreparedCombatRelayout(owner)
    local state = owner and owner._quiCDMAuraCombatState
    if state then state.valid = false end
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
    owner._quiCDMAuraRunRecords = nil
    owner._quiCDMAuraRunByIcon = nil
    owner._quiCDMAuraCapacity = nil
    owner._quiCDMAuraCombatState = nil
end

function Runs.RelayoutPreparedInCombat(owner, settings, icons)
    if not Runs.CanRelayoutInCombat(owner, settings, icons) then return nil end
    local state = owner._quiCDMAuraCombatState
    local chain = state.chain
    local chainCount, proxyCount = 0, 0

    for i = 1, state.iconCount do
        local icon = icons[i]
        if not (icon and icon.ClearAllPoints and icon.SetPoint) then return nil end
        if IsManagedAuraIcon(icon) and not state.runByIcon[icon] then return nil end
    end

    for i = 1, state.iconCount do
        local icon = icons[i]
        local frame
        if IsManagedAuraIcon(icon) then
            frame = state.runByIcon[icon].container
            proxyCount = proxyCount + 1
            HideProxy(icon)
        elseif icon._lastLayoutFilterHidden ~= true then
            frame = icon
            proxyCount = proxyCount + 1
            icon:Show()
        else
            icon:Hide()
            icon:ClearAllPoints()
        end
        if frame and chain[chainCount] ~= frame then
            chainCount = chainCount + 1
            chain[chainCount] = frame
        end
    end
    for i = #chain, chainCount + 1, -1 do chain[i] = nil end
    if chainCount == 0 then return nil end

    local width = (proxyCount * state.iconWidth)
        + (math.max(proxyCount - 1, 0) * state.padding)
    local metrics = state.metrics
    metrics.iconWidth = width
    metrics.rawContentWidth = width
    metrics.row1Width = width
    metrics.bottomRowWidth = width
    metrics.rawRow1Width = width
    metrics.rawBottomRowWidth = width

    local previous
    for i = 1, chainCount do
        local frame = chain[i]
        frame:ClearAllPoints()
        if previous then
            local gap = state.spacingAfter[previous]
            frame:SetPoint("LEFT", previous, "RIGHT", gap == nil and state.padding or gap, 0)
        else
            frame:SetPoint("LEFT", owner, "LEFT", state.offsetX, state.offsetY)
        end
        previous = frame
    end
    return metrics
end

local function AnchorPreparedRuns(owner, layoutPlan, runByIcon)
    local Layout = ns.CDMLayout
    local chain = {}
    local spacingAfter = {}
    local firstPlacement = layoutPlan.placements[1]
    if not firstPlacement then return false end

    for i = 1, #layoutPlan.placements do
        local icon = layoutPlan.placements[i].icon
        if IsManagedAuraIcon(icon) then
            local record = runByIcon[icon]
            if not record then return false end
            local container = record.container
            if chain[#chain] ~= container then
                chain[#chain + 1] = container
                spacingAfter[container] = -1
            end
            HideProxy(icon)
        else
            chain[#chain + 1] = icon
        end
    end

    local metrics = layoutPlan.metrics or {}
    local rowConfig = firstPlacement.rowConfig
    local width = rowConfig.size or 39
    local offsetX = firstPlacement.x + ((metrics.iconWidth or width) * 0.5) - (width * 0.5)
    return Layout.AnchorLinearChain(owner, chain, {
        axis = "HORIZONTAL",
        grow = "RIGHT",
        spacing = rowConfig.padding or 0,
        spacingAfter = spacingAfter,
        offsetX = offsetX,
        offsetY = firstPlacement.y or 0,
    })
end

function Runs.Apply(owner, settings, layoutPlan, allIcons, inCombat, viewerType)
    local overlaysApplied = ApplyCooldownAuraOverlays(
        owner, settings, layoutPlan, inCombat, viewerType)
    if not (owner and Runs.ShouldUseSettings(settings, viewerType)
        and layoutPlan and layoutPlan.placements) then
        if not inCombat then Disable(owner) end
        return overlaysApplied
    end

    local AuraSkin = ns.AuraSkin or (ns.Addon and ns.Addon.AuraSkin)
    local Layout = ns.CDMLayout
    if not (AuraSkin and AuraSkin.Configure and Layout and Layout.AnchorLinearChain) then return false end

    if inCombat then
        return Runs.RelayoutPreparedInCombat(owner, settings, allIcons) ~= nil
            or overlaysApplied
    end

    local runRecords = {}
    local runByIcon = {}
    local currentRun
    local runCount = 0
    local firstPlacement = layoutPlan.placements[1]
    if not firstPlacement then
        Disable(owner)
        return false
    end
    local staticIcons = allIcons
    if type(staticIcons) ~= "table" then
        staticIcons = {}
        for i = 1, #layoutPlan.placements do
            staticIcons[i] = layoutPlan.placements[i].icon
        end
    end
    local capacity = Layout.GetTotalIconCapacity(settings)

    for i = 1, math.min(#staticIcons, capacity) do
        local icon = staticIcons[i]
        if IsManagedAuraIcon(icon) then
            local route = icon._spellEntry._managedAuraRoute
            if not currentRun or currentRun.route ~= route then
                runCount = runCount + 1
                local container = AcquireRun(owner, runCount)
                currentRun = {
                    container = container,
                    groups = {},
                    rowConfig = firstPlacement and firstPlacement.rowConfig,
                    route = route,
                }
                runRecords[#runRecords + 1] = currentRun
            end
            runByIcon[icon] = currentRun
            currentRun.groups[#currentRun.groups + 1] = BuildGroup(
                icon, #currentRun.groups + 1, currentRun.rowConfig)
        else
            currentRun = nil
        end
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
    owner._quiCDMAuraRunByIcon = runByIcon
    owner._quiCDMAuraCapacity = capacity
    activeOwners[owner] = true

    local combatState = owner._quiCDMAuraCombatState or {}
    local chain = combatState.chain or {}
    local spacingAfter = combatState.spacingAfter or {}
    for frame in pairs(spacingAfter) do spacingAfter[frame] = nil end
    local combatIcons = allIcons or staticIcons
    local iconCount = math.min(#combatIcons, capacity)
    for i = 1, iconCount do chain[i] = false end
    for i = iconCount, 1, -1 do chain[i] = nil end
    for i = 1, #runRecords do spacingAfter[runRecords[i].container] = -1 end
    local metrics = layoutPlan.metrics
    local rowConfig = firstPlacement.rowConfig
    local width = rowConfig.size or 39
    combatState.settings = settings
    combatState.viewerType = viewerType
    combatState.icons = combatIcons
    combatState.capacity = capacity
    combatState.iconCount = iconCount
    combatState.valid = true
    combatState.runByIcon = runByIcon
    combatState.chain = chain
    combatState.spacingAfter = spacingAfter
    combatState.metrics = metrics
    combatState.iconWidth = width
    combatState.padding = rowConfig.padding or 0
    combatState.offsetX = firstPlacement.x
        + ((metrics.iconWidth or width) * 0.5) - (width * 0.5)
    combatState.offsetY = firstPlacement.y or 0
    owner._quiCDMAuraCombatState = combatState

    local pool = owner._quiCDMAuraRuns or {}
    for i = runCount + 1, #pool do
        local container = pool[i]
        AuraSkin.Configure(container, container._quiProfile or {}, {})
        container:SetEnabled(false)
        container:Hide()
    end

    return AnchorPreparedRuns(owner, layoutPlan, runByIcon)
end

return Runs
