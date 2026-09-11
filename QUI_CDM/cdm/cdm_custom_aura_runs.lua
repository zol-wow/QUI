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

function Runs.ShouldUseSettings(settings, viewerType)
    if type(settings) ~= "table" or settings.containerType ~= "customBar" then return false end
    if type(viewerType) ~= "string" or viewerType == "" then return false end
    if settings.dynamicLayout ~= true then return false end
    if (settings.showOnlyWhenActive ~= true and settings.iconDisplayMode ~= "active")
        or settings.showOnlyOnCooldown == true
        or settings.showOnlyWhenOffCooldown == true
        or settings.showOnlyInCombat == true
        or settings.hideNonUsable == true then
        return false
    end
    local rowCount = 0
    if settings.row1 and (settings.row1.iconCount or 0) > 0 then rowCount = rowCount + 1 end
    if settings.row2 and (settings.row2.iconCount or 0) > 0 then rowCount = rowCount + 1 end
    if settings.row3 and (settings.row3.iconCount or 0) > 0 then rowCount = rowCount + 1 end
    return rowCount > 0
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
        if entry and entry.enabled ~= false and (entry.kind == "aura" or entry.displayMode == "auraOnly")
            and ResolveRoute and ResolveRoute(entry) then
            return true
        end
    end
    return false
end

local function EntryHidden(entry, settings)
    local overrides = settings and settings.spellOverrides
    local override = overrides and entry and overrides[entry.id or entry.spellID]
    return entry and entry.hidden == true or type(override) == "table" and override.hidden == true
end

local function IsCooldownAuraOverlayEntry(entry)
    return type(entry) == "table"
        and entry.enabled ~= false
        and entry._isCustomEntry == true
        and entry.kind == "cooldown"
        and entry.type ~= "macro"
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
            and entry.type ~= "macro" then
            return true
        end
    end
    return false
end

local function CandidateIDs(entry)
    local mirrors = ns.CDMManagedAuraMirrors
    if mirrors and mirrors.ResolveCandidateIDs then
        return mirrors.ResolveCandidateIDs(entry, IsSecret)
    end
    local id = entry and (entry.overrideSpellID or entry.spellID or entry.id)
    return type(id) == "number" and not IsSecret(id) and id > 0 and { id } or {}
end

function Runs.ResolveAuraConfig(entry)
    if type(entry) ~= "table" then return nil end
    local ids = CandidateIDs(entry)
    local include = {}
    for i = 1, #ids do include[ids[i]] = true end
    if not next(include) then return nil end
    local unit, filter = entry.auraUnit, entry.auraFilter
    local selfAura = entry.kind == "aura" and entry._selfAura
    if entry.kind ~= "aura" then selfAura = nil end
    local spellData = ns.CDMSpellData
    local isItem = entry.type == "item" or entry.type == "slot" or entry.type == "trinket"
        or entry.type == "consumable"
    local primaryID = isItem and ids[1] or (entry.spellID or entry.id)
    if selfAura == nil and spellData and spellData.IsSelfAuraSpell then
        selfAura = spellData:IsSelfAuraSpell(primaryID)
    end
    if not unit then
        if selfAura == false then
            unit = "target"
        else
            unit = "player"
            for i = 1, #ids do
                if PET_AURA_UNITS[ids[i]] then unit = "pet"; break end
            end
        end
    end
    if not filter then
        if selfAura == false then
            local sources = ns.CDMSources
            local helpful = sources and sources.QuerySpellHelpful
                and sources.QuerySpellHelpful(primaryID) == true
            filter = helpful and HELPFUL_FILTER or HARMFUL_FILTER
        elseif selfAura == true then
            filter = HELPFUL_FILTER
        else
            filter = "HELPFUL"
        end
    end
    return { unit = unit, filter = filter, includeSpellIDs = include }
end

ResolveRoute = function(entry)
    local config = Runs.ResolveAuraConfig(entry)
    if not config then return nil end
    if config.unit == "player" and config.filter == HELPFUL_FILTER then return "SELF_HELPFUL" end
    if config.unit == "target" and config.filter == HELPFUL_FILTER then return "HELPFUL" end
    if config.unit == "target" and config.filter == HARMFUL_FILTER then return "HARMFUL" end
    return config.unit .. ":" .. config.filter
end

function Runs.ResolveRoute(entry)
    return ResolveRoute(entry)
end

local function Profile(rowConfig, settings, entry)
    local overrides = settings and settings.spellOverrides
    local override = overrides and entry and overrides[entry.id or entry.spellID]
    if type(override) == "table" then
        local merged = {}
        for key, value in pairs(rowConfig) do merged[key] = value end
        for key, value in pairs(override) do merged[key] = value end
        rowConfig = merged
    end
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
    local pandemicGlow
    local auraConfig = entry and Runs.ResolveAuraConfig(entry)
    local viewerType = entry and entry.viewerType
    local glowSettings = ns.Addon and ns.Addon.db and ns.Addon.db.profile.customGlow
    if auraConfig and viewerType then
        local suffix = auraConfig.filter:find("HARMFUL", 1, true)
            and "PandemicDebuffEnabled" or "PandemicBuffEnabled"
        if not glowSettings or glowSettings[viewerType .. suffix] ~= false then
            pandemicGlow = { color = { 1, 0.85, 0.2, 1 } }
        end
    end
    return {
        cdmProcGlow = ns._OwnedGlows and ns._OwnedGlows.ResolveGlowForEntry
            and ns._OwnedGlows.ResolveGlowForEntry(entry) or nil,
        cdmActiveGlow = settings and settings.activeGlowEnabled ~= false
            and not (override and override.glowEnabled == false) and {
            color = override and override.glowColor or settings.activeGlowColor or { 1, 0.85, 0.3, 1 },
            thickness = settings.activeGlowThickness or 2,
            glowType = settings.activeGlowType or "Pixel Glow",
            lines = settings.activeGlowLines or 8,
            frequency = settings.activeGlowFrequency or 0.25,
            scale = settings.activeGlowScale or 1,
        } or nil,
        pandemicGlow = pandemicGlow,
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

Runs.BuildProfile = Profile

function Runs.ConfigureNativeClick(button, source)
    if not button._quiNativeCast then return end
    local action = source and source.GetAttribute and source:GetAttribute("type")
    for _, key in ipairs({ "type", "spell", "item", "macro", "macrotext", "unit" }) do
        button:SetAttribute(key, action and source:GetAttribute(key) or nil)
    end
    button:RegisterForClicks("AnyUp", "AnyDown")
    if button.SetMouseClickEnabled then button:SetMouseClickEnabled(action ~= nil) end
    if button.SetMouseMotionEnabled then button:SetMouseMotionEnabled(true) end
end

function Runs.StyleNativeEffects(frame, profile, key)
    key = key or "_quiCDMNativeGlow"
    local glow = profile.cdmActiveGlow
    local effects = frame[key]
    if not effects then
        effects = {}
        frame[key] = effects
    end
    for _, effect in ipairs(effects) do
        effect.group:Stop()
        effect.playing = false
        effect.texture:SetAlpha(0)
        effect.enabled = false
    end
    if not glow or not frame.CreateTexture then return effects end
    local host = frame._quiCDMNativeEffectHost
    if not host then
        host = CreateFrame("Frame", nil, frame)
        host:SetAllPoints(frame)
        frame._quiCDMNativeEffectHost = host
    end
    local color = glow.color or { 1, 0.85, 0.3, 1 }
    local width = profile.iconWidth or profile.iconSize or 39
    local height = profile.iconHeight or width
    local style = glow.glowType or "Pixel Glow"
    local flipbook = style == "Proc Glow" or style == "Button Glow"
    local lines = math.max(1, math.floor(glow.lines or 8))
    local thickness = math.max(1, glow.thickness or 2)
    local length = math.max(thickness, math.min(width, height, math.floor((width + height) * (2 / lines - 0.1))))
    local segments = style == "Pixel Glow" and math.ceil(length / thickness) or 1
    local layers = style == "Autocast Shine" and 4 or 1
    local count = flipbook and 1 or lines * segments * layers
    local period = 1 / math.max(0.01, math.abs(glow.frequency or 0.25))
    local perimeter = (width + height) * 2
    for i = 1, count do
        local effect = effects[i]
        if not effect then
            local texture = host:CreateTexture(nil, "OVERLAY")
            effect = { texture = texture, group = host:CreateAnimationGroup() }
            effects[i] = effect
        end
        effect.enabled = true
        local texture, group = effect.texture, effect.group
        texture:ClearAllPoints()
        texture:SetVertexColor(color[1] or 1, color[2] or 1, color[3] or 1, color[4] or 1)
        texture:SetAlpha(1)
        texture:SetTexCoord(0, 1, 0, 1)
        texture:SetBlendMode("BLEND")
        group:RemoveAnimations()
        group:SetLooping("REPEAT")
        if flipbook then
            texture:SetPoint("CENTER", frame, "CENTER", 0, 0)
            texture:SetSize(width * 1.4, height * 1.4)
            if style == "Proc Glow" then
                texture:SetAtlas("UI-HUD-ActionBar-Proc-Loop-Flipbook")
            else
                texture:SetTexture("Interface\\SpellActivationOverlay\\IconAlertAnts")
            end
            local animation = group:CreateAnimation("FlipBook")
            animation:SetTarget(texture)
            animation:SetDuration(math.max(0.5, math.min(2, period * 0.25)))
            animation:SetFlipBookRows(style == "Proc Glow" and 6 or 5)
            animation:SetFlipBookColumns(5)
            animation:SetFlipBookFrames(style == "Proc Glow" and 30 or 22)
            animation:SetFlipBookFrameWidth(style == "Proc Glow" and 0 or 48 / 256)
            animation:SetFlipBookFrameHeight(style == "Proc Glow" and 0 or 48 / 256)
        else
            local layer = math.floor((i - 1) / lines) + 1
            local size = style == "Autocast Shine" and (8 - layer) * (glow.scale or 1) or thickness
            texture:SetSize(size, size)
            if style == "Autocast Shine" then
                texture:SetTexture("Interface\\Artifacts\\Artifacts")
                texture:SetTexCoord(0.8115234375, 0.9169921875, 0.8798828125, 0.9853515625)
                texture:SetBlendMode("ADD")
            else
                texture:SetColorTexture(1, 1, 1, 1)
            end
            local phase = ((i - 1) % lines) / lines
            if style == "Pixel Glow" then
                phase = math.floor((i - 1) / segments) / lines + ((i - 1) % segments) * thickness / perimeter
            end
            local start = (phase % 1) * perimeter
            local function Point(distance)
                distance = distance % perimeter
                if distance <= width then return distance, 0 end
                if distance <= width + height then return width, width - distance end
                if distance <= width * 2 + height then return width * 2 + height - distance, -height end
                return 0, distance - perimeter
            end
            local x, y = Point(start)
            texture:SetPoint("CENTER", frame, "TOPLEFT", x, y)
            local corners = {}
            for _, distance in ipairs({ width, width + height, width * 2 + height, perimeter }) do
                if distance <= start then distance = distance + perimeter end
                corners[#corners + 1] = distance
            end
            table.sort(corners)
            local path = group:CreateAnimation("Path")
            path:SetTarget(texture)
            path:SetDuration(period * (style == "Autocast Shine" and layer or 1))
            path:SetCurveType("NONE")
            for order = 1, #corners do
                local corner = (glow.frequency or 0.25) < 0 and #corners + 1 - order or order
                local cx, cy = Point(corners[corner])
                path:CreateControlPoint(nil, nil, order):SetOffset(cx - x, cy - y)
            end
            path:CreateControlPoint(nil, nil, #corners + 1):SetOffset(0, 0)
        end
        group:Play()
        effect.playing = true
    end
    return effects
end

function Runs.SetNativeProcGlow(icon, active)
    if not icon then return end
    icon._quiNativeProcGlowActive = active == true
    if not icon._quiNativeProcGlows then return end
    for effects in pairs(icon._quiNativeProcGlows) do
        for _, effect in ipairs(effects) do
            local playing = active == true and effect.enabled == true
            if effect.playing ~= playing then
                if playing then effect.group:Play() else effect.group:Stop() end
                effect.playing = playing
            end
            effect.texture:SetAlpha(playing and 1 or 0)
        end
    end
end

function Runs.ConfigureNativeEffects(frame, profile, owner)
    Runs.StyleNativeEffects(frame, profile)
    local effects = Runs.StyleNativeEffects(frame, {
        cdmActiveGlow = profile.cdmProcGlow,
        iconWidth = profile.iconWidth,
        iconHeight = profile.iconHeight,
        iconSize = profile.iconSize,
    }, "_quiCDMNativeProcGlow")
    if owner and effects then
        owner._quiNativeProcGlows = owner._quiNativeProcGlows or {}
        owner._quiNativeProcGlows[effects] = true
        Runs.SetNativeProcGlow(owner, owner._quiNativeProcGlowActive)
    end
end

local function StyleNativeFrame(frame, profile)
    local AuraSkin = ns.AuraSkin or (ns.Addon and ns.Addon.AuraSkin)
    if AuraSkin and AuraSkin.WireButton then AuraSkin.WireButton(frame, profile) end
    Runs.ConfigureNativeEffects(frame, profile, profile.cdmEffectOwner)
    Runs.ConfigureNativeClick(frame, profile.cdmClickSource)
end

local function GetAuraOverlayManager(config, clickable)
    local key = config.unit .. ":" .. config.filter .. (clickable and ":cast" or "")
    if auraOverlayManagers[key] then return auraOverlayManagers[key] end
    local mirrors = ns.CDMManagedAuraMirrors
    if not (mirrors and mirrors.New) then return nil end
    local AuraSkin = ns.AuraSkin or (ns.Addon and ns.Addon.AuraSkin)
    local manager = mirrors.New({
        createFrame = CreateFrame,
        unit = config.unit,
        filter = config.filter,
        interactive = true,
        secureClicks = clickable == true,
        configureClick = Runs.ConfigureNativeClick,
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
        styleFrame = AuraSkin and StyleNativeFrame,
        restyleFrame = AuraSkin and function(frame, rowConfig, profile)
            return StyleNativeFrame(frame, profile or Profile(rowConfig))
        end,
    })
    auraOverlayManagers[key] = manager
    return manager
end

local function DisableCooldownAuraOverlays(owner)
    ClearPreparedAuraOverlayIcons(owner)
    if not owner or not activeAuraOverlayOwners[owner] then return end
    for _, manager in pairs(auraOverlayManagers) do
        if manager.SetCombatVisibility then manager:SetCombatVisibility(owner, false) end
        if manager:BeginPass(owner, false) then manager:EndPass(owner) end
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
    if inCombat then return Runs.HasAuraOverlays(owner) end
    ClearPreparedAuraOverlayIcons(owner)
    local cooldownOverlays = Runs.ShouldUseCooldownAuraOverlays(settings, viewerType)
    local staticAuras = not Runs.ShouldUseSettings(settings, viewerType)
    local helpers = ns.Helpers
    local editMode = (helpers and helpers.IsEditModeActive and helpers.IsEditModeActive())
        or (helpers and helpers.IsLayoutModeActive and helpers.IsLayoutModeActive())
        or (_G.QUI_IsCDMEditModeActive and _G.QUI_IsCDMEditModeActive())
    if owner then
        preparedAuraOverlayOwners[owner] =
            (cooldownOverlays and Runs.HasCooldownAuraOverlayEntries(settings, viewerType))
            or (staticAuras and Runs.HasAuraEntries(settings, viewerType)) or nil
    end
    if not (owner and layoutPlan and layoutPlan.placements) then
        DisableCooldownAuraOverlays(owner)
        return false
    end
    local managers, preparedIcons = {}, {}
    local mirrored = 0
    for i = 1, #layoutPlan.placements do
        local placement = layoutPlan.placements[i]
        local icon = placement.icon
        local entry = icon and icon._spellEntry
        local managed = staticAuras and IsManagedAuraIcon(icon)
        if not EntryHidden(entry, settings)
            and (managed or (cooldownOverlays and IsCooldownAuraOverlayEntry(entry))) then
            local config = Runs.ResolveAuraConfig(entry)
            local manager = config and GetAuraOverlayManager(config, settings.clickableIcons)
            if manager and not managers[manager] then
                managers[manager] = manager:BeginPass(owner) and true or nil
            end
            if manager and managers[manager] then
                local rowConfig = placement.rowConfig or {}
                local width = rowConfig.size or 39
                local aspect = rowConfig.aspectRatioCrop or 1
                if aspect <= 0 then aspect = 1 end
                local profile = Profile(rowConfig, managed and settings or nil, entry)
                profile.cdmClickSource = settings.clickableIcons and icon.clickButton or nil
                profile.cdmEffectOwner = icon
                icon._quiNativeProcGlows = nil
                local record = manager:Acquire(owner, icon, entry, profile, config)
                if record and manager:PositionOverlay(record, icon, owner, placement.x, placement.y,
                    width, width / aspect, rowConfig) then
                    icon._customAuraOverlayPrepared = true
                    if managed then icon._quiManagedAuraProxy = nil end
                    preparedIcons[icon] = true
                    mirrored = mirrored + 1
                end
            end
        end
    end
    for _, manager in pairs(auraOverlayManagers) do
        if manager.SetCombatVisibility then
            manager:SetCombatVisibility(owner, managers[manager] and settings.showOnlyInCombat == true and not editMode)
        end
        if managers[manager] or manager:BeginPass(owner, false) then manager:EndPass(owner) end
    end
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

local function BuildGroup(icon, index, rowConfig, settings)
    local ids = CandidateIDs(icon._spellEntry)
    local include = {}
    for i = 1, #ids do include[ids[i]] = true end
    local filters = next(include) and not EntryHidden(icon._spellEntry, settings)
        and { includeSpellIDs = include } or { maxDuration = 0 }
    local spacing = rowConfig.padding or 0
    local profile = Profile(rowConfig, settings, icon._spellEntry)
    profile.cdmClickSource = settings.clickableIcons and icon.clickButton or nil
    profile.cdmEffectOwner = icon
    icon._quiNativeProcGlows = nil
    return {
        key = "a" .. tostring(index) .. (settings.clickableIcons and ":cast" or ""),
        secureClicks = settings.clickableIcons == true,
        profile = profile,
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

local function RouteConfig(route)
    if route == "SELF_HELPFUL" then return "player", HELPFUL_FILTER end
    if route == "HELPFUL" then return "target", HELPFUL_FILTER end
    if route == "HARMFUL" then return "target", HARMFUL_FILTER end
    return route:match("^([^:]+):(.+)$")
end

local function RouteActive(route)
    local unit, filter = RouteConfig(route)
    if unit ~= "target" then return unit ~= nil end
    if filter:find("HARMFUL", 1, true) then return HostileTarget() end
    return FriendlyTarget()
end

local function ApplyRoute(record)
    local unit, filter = RouteConfig(record.route)
    local active = RouteActive(record.route)
    local cancel = unit == "player" and filter:find("HELPFUL", 1, true) and "RightButtonUp" or nil
    for i = 1, #record.groups do
        local group = record.groups[i]
        group.filter = filter
        group.maxFrameCount = active and 1 or 0
        group.cancelButtons = cancel
    end
    local container = record.container
    container:SetUnit(unit)
    local buttons = container._quiCDMNativeButtons or {}
    local profiles = {}
    container._quiCDMNativeButtons = buttons
    container._quiCDMNativeProfiles = profiles
    for i = 1, #record.groups do
        local group = record.groups[i]
        local key = group.key
        profiles[key] = group.profile or record.profile
        if container.AddAuraGroup and container.HasAuraGroup and not container:HasAuraGroup(key) then
            container:AddAuraGroup(key, group.filter, {
                maxFrameCount = group.maxFrameCount,
                candidateFilters = group.candidateFilters,
                templateNames = group.secureClicks and { "SecureActionButtonTemplate" } or nil,
                initializeFrame = function(button)
                    button._quiNativeCast = group.secureClicks
                    buttons[button] = key
                    StyleNativeFrame(button, container._quiCDMNativeProfiles[key] or {})
                    if not button._quiNativeCast and button.SetCancelAuraButtons then button:SetCancelAuraButtons(cancel) end
                end,
            })
        end
    end
    record.AuraSkin.Configure(container, record.profile, record.groups)
    if not (InCombatLockdown and InCombatLockdown())
        and not (C_Secrets and C_Secrets.ShouldAurasBeSecret and C_Secrets.ShouldAurasBeSecret()) then
        for button, key in pairs(buttons) do StyleNativeFrame(button, profiles[key] or {}) end
    end
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
    if settings.clickableIcons then return false end
    local factory = ns.CDMIconFactory
    if factory and factory.PoolHasProtectedIcon and factory:PoolHasProtectedIcon(state.viewerType) then
        return false
    end
    for _, container in ipairs(owner._quiCDMAuraRuns or {}) do
        for button in pairs(container._quiCDMNativeButtons or {}) do
            if button._quiNativeCast then return false end
        end
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
    for icon in pairs(owner._quiCDMAuraRunByIcon or {}) do
        icon._quiManagedAuraProxy = nil
    end
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

local function ApplyRowRuns(owner, settings, layoutPlan, AuraSkin)
    local records, byIcon = {}, {}
    local previous, previousNative, rowConfig, currentRun
    local vertical = settings.layoutDirection == "VERTICAL"
    for _, placement in ipairs(layoutPlan.placements) do
        local icon = placement.icon
        local row = placement.rowConfig or {}
        if row ~= rowConfig then
            rowConfig, currentRun, previous = row, nil, nil
        end
        local frame
        local native = IsManagedAuraIcon(icon)
        if native then
            local route = icon._spellEntry._managedAuraRoute
            if not currentRun or currentRun.route ~= route then
                local container = AcquireRun(owner, #records + 1)
                currentRun = { container = container, route = route, groups = {}, rowConfig = row }
                currentRun.profile = Profile(row, settings)
                currentRun.profile.grow = vertical and "DOWN" or "RIGHT"
                currentRun.AuraSkin = AuraSkin
                records[#records + 1] = currentRun
                frame = container
            end
            byIcon[icon] = currentRun
            local group = BuildGroup(icon, #currentRun.groups + 1, row, settings)
            if vertical then
                group.elementWidth = row.size or 39
                group.elementHeight = (row.size or 39) / (row.aspectRatioCrop or 1)
                    + (row.padding or 0) + 1
            end
            currentRun.groups[#currentRun.groups + 1] = group
            HideProxy(icon)
        else
            currentRun = nil
            frame = icon
        end
        if frame then
            frame:ClearAllPoints()
            if previous then
                local gap = previousNative and -1 or (row.padding or 0)
                if vertical then
                    frame:SetPoint("TOPLEFT", previous, "BOTTOMLEFT", 0, -gap)
                else
                    frame:SetPoint("TOPLEFT", previous, "TOPRIGHT", gap, 0)
                end
            else
                local width = row.size or 39
                local height = width / (row.aspectRatioCrop or 1)
                frame:SetPoint("TOPLEFT", owner, "CENTER", placement.x - width / 2, placement.y + height / 2)
            end
            previous, previousNative = frame, native
        end
    end
    if #records == 0 then Disable(owner); return false end
    for _, record in ipairs(records) do ApplyRoute(record) end
    for i = #records + 1, #(owner._quiCDMAuraRuns or {}) do
        local container = owner._quiCDMAuraRuns[i]
        AuraSkin.Configure(container, container._quiProfile or {}, {})
        container:SetEnabled(false)
        container:Hide()
    end
    owner._quiCDMAuraRunRecords = records
    owner._quiCDMAuraRunByIcon = byIcon
    owner._quiCDMAuraCombatState = nil
    activeOwners[owner] = true
    return true
end

function Runs.Apply(owner, settings, layoutPlan, allIcons, inCombat, viewerType)
    if C_Secrets and C_Secrets.ShouldAurasBeSecret and C_Secrets.ShouldAurasBeSecret() then
        return Runs.HasActiveRuns(owner) or Runs.HasAuraOverlays(owner)
    end
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

    local rowCount = 0
    for i = 1, 3 do
        local row = settings["row" .. i]
        if row and (row.iconCount or 0) > 0 then rowCount = rowCount + 1 end
    end
    if rowCount > 1 or settings.layoutDirection == "VERTICAL" then
        return ApplyRowRuns(owner, settings, layoutPlan, AuraSkin) or overlaysApplied
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
                icon, #currentRun.groups + 1, currentRun.rowConfig, settings)
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
