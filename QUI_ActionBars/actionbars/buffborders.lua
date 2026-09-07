local _, ns = ...
local Helpers = ns.Helpers

local AuraSkin = (ns.Addon and ns.Addon.AuraSkin) or (_G.QUI and _G.QUI.AuraSkin)
local E = ns.AuraElements or (_G.QUI and _G.QUI.AuraElements)
local G = ns.AuraGlue    or (_G.QUI and _G.QUI.AuraGlue)
local S = ns.AuraSlots   or (_G.QUI and _G.QUI.AuraSlots)

local type = type
local ipairs = ipairs
local pcall = pcall
local CreateFrame = CreateFrame
local InCombatLockdown = InCombatLockdown

local DEFAULTS = {
    enableBuffs = true,
    enableDebuffs = true,
    showBuffBorders = true,
    showDebuffBorders = true,
    hideBuffFrame = false,
    hideDebuffFrame = false,
    fadeBuffFrame = false,
    fadeDebuffFrame = false,
    fadeOutAlpha = 0,
    externalSkinning = false,
    iconSkin = "Default",
    borderSize = 2,
    fontSize = 12,
    fontOutline = true,
    showStacks = true,
    hideSwipe = false,
}

local function GetSettings()
    return Helpers.GetModuleSettings("buffBorders", DEFAULTS)
end

local BUFF_MAX_DISPLAY = 40
local DEBUFF_MAX_DISPLAY = 40

local function ResolveAuraDeps()
    AuraSkin = AuraSkin or (ns.Addon and ns.Addon.AuraSkin) or (_G.QUI and _G.QUI.AuraSkin)
    E = E or ns.AuraElements or (_G.QUI and _G.QUI.AuraElements)
    G = G or ns.AuraGlue    or (_G.QUI and _G.QUI.AuraGlue)
    S = S or ns.AuraSlots   or (_G.QUI and _G.QUI.AuraSlots)
    return AuraSkin and E and G and S
end

local EMPTY = {}

local _buffStrips = {}
local _debuffStrips = {}

local function DefaultBuffBucket()
    local EE = E or ns.AuraElements or (_G.QUI and _G.QUI.AuraElements)
    if not EE then return {} end
    local e = EE.NewFilterStripElement("HELPFUL")
    e.id = "buffs"
    e.enabled = true
    e.iconSize = 35
    e.iconsPerRow = 10
    e.spacing = 2
    e.growDirection = "LEFT"
    e.anchor = "TOPRIGHT"
    e.maxIcons = BUFF_MAX_DISPLAY
    e.sortRule = "INDEX"
    e.sortReverse = false
    e.rightClickCancel = true
    e.duration = { show = true, fontSize = 12, anchor = "CENTER", offsetX = 0, offsetY = 0, color = { 1, 1, 1, 1 } }
    e.stack = { show = true, fontSize = 12, anchor = "BOTTOMRIGHT", offsetX = -1, offsetY = 1, color = { 1, 1, 1, 1 } }
    return { e }
end

local function DefaultDebuffBucket()
    local EE = E or ns.AuraElements or (_G.QUI and _G.QUI.AuraElements)
    if not EE then return {} end
    local e = EE.NewFilterStripElement("HARMFUL")
    e.id = "debuffs"
    e.enabled = true
    e.iconSize = 35
    e.iconsPerRow = 10
    e.spacing = 2
    e.growDirection = "LEFT"
    e.anchor = "TOPRIGHT"
    e.maxIcons = DEBUFF_MAX_DISPLAY
    e.sortRule = "INDEX"
    e.sortReverse = false
    e.rightClickCancel = false
    e.duration = { show = true, fontSize = 12, anchor = "CENTER", offsetX = 0, offsetY = 0, color = { 1, 1, 1, 1 } }
    e.stack = { show = true, fontSize = 12, anchor = "BOTTOMRIGHT", offsetX = -1, offsetY = 1, color = { 1, 1, 1, 1 } }
    return { e }
end

local BB = ns.QUI_BuffBorders or {}
ns.QUI_BuffBorders = BB
BB.DefaultBuffBucket = DefaultBuffBucket
BB.DefaultDebuffBucket = DefaultDebuffBucket

local function GetBuffStore(settings)
    settings.buffAuras = settings.buffAuras or {}
    return settings.buffAuras
end
local function GetDebuffStore(settings)
    settings.debuffAuras = settings.debuffAuras or {}
    return settings.debuffAuras
end

-- Pre-5.0 buff borders were black; the strip's custom color still wins.
local BORDER_COLOR_DEFAULT = { 0, 0, 0, 1 }
local STACKS_HIDDEN = { show = false }

-- Merges the module-level settings (Show Borders, Border Size, Button Skin,
-- External Skinning, ...) into the per-strip profile. Per-strip values win
-- where both exist. Pass isBuff = nil for layout-only uses (anchoring).
local function ElementProfileFor(element, isBuff)
    local overrides
    if isBuff ~= nil then
        local settings = GetSettings()
        if settings then
            local moduleShow
            if isBuff then
                moduleShow = settings.showBuffBorders ~= false
            else
                moduleShow = settings.showDebuffBorders ~= false
            end
            overrides = {
                showBorder       = moduleShow and element.hideBorder ~= true,
                borderSize       = element.borderSize or settings.borderSize or 2,
                borderColor      = element.borderColor or BORDER_COLOR_DEFAULT,
                iconSkin         = settings.iconSkin,
                externalSkinning = settings.externalSkinning == true,
                externalSkinKey  = isBuff and "Buff Frame" or "Debuff Frame",
            }
            if settings.showStacks == false then
                overrides.stack = STACKS_HIDDEN
            end
            if settings.hideSwipe then
                overrides.hideSwipe = true
            end
        end
    end
    return G.ElementProfile(element, overrides)
end

local function FallbackProfile(defaultBucketFn)
    local bucket = defaultBucketFn()
    if bucket and bucket[1] then return ElementProfileFor(bucket[1]) end
    return G.ElementProfile({})
end

local function ResolveStrips(store, defaultBucketFn, out, auraType)
    for i = #out, 1, -1 do out[i] = nil end
    if not store then return out end
    E.EnsureSeeded(store, defaultBucketFn)
    if E.NormalizeSingleStripBucket then
        E.NormalizeSingleStripBucket(store, auraType)
    end
    local elements = E.ActiveElementsForSpec(store, nil)
    for i = 1, #elements do
        local e = elements[i]
        if e.mode == "filterStrip" then
            out[#out + 1] = e
        end
    end
    return out
end

local function GridExtent(profile)
    local cols = math.min(profile.maxPerRow > 0 and profile.maxPerRow or profile.maxIcons, profile.maxIcons)
    if cols < 1 then cols = 1 end
    local rows = math.ceil(profile.maxIcons / cols)
    local rowGap = (profile.rowSpacing and profile.rowSpacing > 0)
        and profile.rowSpacing or profile.spacing
    local w = cols * profile.iconSize + math.max(0, cols - 1) * profile.spacing
    local h = rows * profile.iconSize + math.max(0, rows - 1) * rowGap
    return w, h
end

local buffContainer = nil
local debuffContainer = nil
local initialized = false

local blizzBuffBanished = false
local blizzDebuffBanished = false
local blizzardBanishState = Helpers.CreateStateTable()
local blizzardBanishParent

local function GetBlizzardBanishState(frame)
    local state = blizzardBanishState[frame]
    if not state then
        state = {}
        blizzardBanishState[frame] = state
    end
    return state
end

local previewActive = false

local buffBorderStats

local pendingContainerWork = false

local function ApplyContainerConfig() end

local function FlushPendingContainerWork()
    if pendingContainerWork then
        pendingContainerWork = false
        ApplyContainerConfig()
    end
end

local function QueueContainerWork()
    pendingContainerWork = true
end

local function SetDescendantMouse(frame, enable)
    for i = 1, frame:GetNumChildren() do
        local child = select(i, frame:GetChildren())
        if child then
            if child.EnableMouse then child:EnableMouse(enable) end
            SetDescendantMouse(child, enable)
        end
    end
end

local function EnsureBlizzardBanishParent()
    if not blizzardBanishParent then
        blizzardBanishParent = CreateFrame("Frame", "QUI_BuffBordersHiddenParent", UIParent)
        blizzardBanishParent:Hide()
    end
    return blizzardBanishParent
end

local function RemoveFromManagedContainer(frame)
    if not frame then return nil end
    local currentParent = frame.GetParent and frame:GetParent() or nil
    ns.SafeCallMethodIfPresent("best-effort-style", currentParent, "RemoveManagedFrame", frame)
    frame.ignoreFramePositionManager = true
    return currentParent
end

local function BanishBlizzardFrame(frame)
    if not frame then return false end
    if InCombatLockdown() and not ns._inInitSafeWindow then return false end

    local state = GetBlizzardBanishState(frame)
    if not state.banished then
        state.originalParent = frame.GetParent and frame:GetParent() or UIParent
        state.originalAlpha = frame.GetAlpha and frame:GetAlpha() or 1
        state.originalMouse = frame.IsMouseEnabled and frame:IsMouseEnabled()
        state.originalIgnoreFramePositionManager = frame.ignoreFramePositionManager
    end

    RemoveFromManagedContainer(frame)

    local hiddenParent = EnsureBlizzardBanishParent()
    ns.SafeCall("best-effort-style", function()
        if frame:GetParent() ~= hiddenParent then frame:SetParent(hiddenParent) end
    end)
    ns.SafeCallMethodIfPresent("best-effort-style", frame, "SetAlpha", 0)
    ns.SafeCallMethodIfPresent("best-effort-style", frame, "EnableMouse", false)
    SetDescendantMouse(frame, false)

    state.banished = true
    return true
end

local function RestoreBlizzardFrame(frame)
    if not frame then return false end
    if InCombatLockdown() and not ns._inInitSafeWindow then return false end

    local state = blizzardBanishState[frame]
    if state and state.originalIgnoreFramePositionManager ~= nil then
        frame.ignoreFramePositionManager = state.originalIgnoreFramePositionManager
    else
        frame.ignoreFramePositionManager = nil
    end

    local parent = state and state.originalParent or UIParent
    if parent then
        ns.SafeCallMethodIfPresent("best-effort-style", frame, "SetParent", parent)
    end

    local alpha = (state and state.originalAlpha ~= nil) and state.originalAlpha or 1
    ns.SafeCallMethodIfPresent("best-effort-style", frame, "SetAlpha", alpha)

    local mouse = not (state and state.originalMouse == false)
    ns.SafeCallMethodIfPresent("best-effort-style", frame, "EnableMouse", mouse)
    SetDescendantMouse(frame, mouse)

    ns.SafeCallMethodIfPresent("best-effort-style", frame, "Show")
    if state then state.banished = false end
    return true
end

local function ManageBlizzardFrames()
    local settings = GetSettings()
    if not settings then return end

    if settings.enableBuffs then
        if BanishBlizzardFrame(BuffFrame) then
            blizzBuffBanished = true
        end
    else
        if blizzBuffBanished then
            if RestoreBlizzardFrame(BuffFrame) then
                blizzBuffBanished = false
            end
        end
    end

    if settings.enableDebuffs then
        if BanishBlizzardFrame(DebuffFrame) then
            blizzDebuffBanished = true
        end
    else
        if blizzDebuffBanished then
            if RestoreBlizzardFrame(DebuffFrame) then
                blizzDebuffBanished = false
            end
        end
    end
end

local function AnchorElementContainer(container, baseFrame, element)
    local profile = ElementProfileFor(element)
    container:ClearAllPoints()
    container:SetPoint(AuraSkin.LayoutAnchor(profile), baseFrame, element.anchor or "TOPRIGHT",
        (element.offsetX or 0), (element.offsetY or 0))
end

local function ApplyMoverElements(moverFrame, strips, isBuff, allowCreate)
    local pool = moverFrame._quiAuraContainers
    if not pool then
        pool = {}
        moverFrame._quiAuraContainers = pool
    end
    local incomplete = false
    local createdFresh = false
    for i = 1, #strips do
        local element = strips[i]
        local container = pool[i]
        if not container then
            if allowCreate and not InCombatLockdown() and CreateFrame then
                container = CreateFrame("AuraContainer", nil, moverFrame, "CustomAuraContainerTemplate")
                container:SetSize(1, 1)
                pool[i] = container
                createdFresh = true
            else
                incomplete = true
            end
        end
        if container then
            if i == 1 then
                moverFrame._quiLiveContainer = container
                container._quiHostMover = moverFrame
            end
            container:SetUnit("player")
            if not InCombatLockdown() and i > 1 then
                local okA = ns.SafeCall("defer-ooc", AnchorElementContainer, container, pool[1] or moverFrame, element)
                if not okA then
                    ns.SafeCall("defer-ooc", AnchorElementContainer, container, moverFrame, element)
                    incomplete = true
                end
            end
            local profile = ElementProfileFor(element, isBuff)
            local groups = G.ElementGroups("player", element, profile, isBuff)
            if not G.RunConfigPass(container, profile, groups, allowCreate) then incomplete = true end
            S.Park(container)
            if isBuff and i == 1 then
                if InCombatLockdown() and not container._quiEnchantsAdded then
                    incomplete = true
                else
                    local okE = ns.SafeCall("defer-ooc", AuraSkin.ConfigureEnchantments, container, profile)
                    if not okE or not container._quiEnchantsAdded then
                        incomplete = true
                    end
                end
            end
            container:SetEnabled(true)
            container:Show()
        end
    end
    if #strips == 0 then
        moverFrame._quiLiveContainer = nil
    end

    for i = #strips + 1, #pool do
        local container = pool[i]
        if not G.RunConfigPass(container, container._quiProfile or {}, {}, allowCreate) then incomplete = true end
        S.Park(container)
        container:SetEnabled(false)
        container:Hide()
    end
    return incomplete, createdFresh
end

local function DisableMoverContainers(moverFrame)
    local pool = moverFrame._quiAuraContainers
    if not pool then return end
    for i = 1, #pool do
        local c = pool[i]
        if c then
            ns.SafeCallMethod("best-effort-style", c, "SetEnabled", false)
            ns.SafeCallMethod("best-effort-style", c, "Hide")
        end
    end
end

local function ApplyConfigPass(allowCreate)
    if not buffContainer or not debuffContainer then return end
    if previewActive then return end
    if not ResolveAuraDeps() then return end

    local settings = GetSettings()
    if not settings then return end

    local buffStrips   = ResolveStrips(GetBuffStore(settings),   DefaultBuffBucket,   _buffStrips,   "HELPFUL")
    local debuffStrips = ResolveStrips(GetDebuffStore(settings), DefaultDebuffBucket, _debuffStrips, "HARMFUL")

    local buffProfile   = buffStrips[1]   and ElementProfileFor(buffStrips[1], true)    or FallbackProfile(DefaultBuffBucket)
    local debuffProfile = debuffStrips[1] and ElementProfileFor(debuffStrips[1], false) or FallbackProfile(DefaultDebuffBucket)

    local bw, bh = GridExtent(buffProfile)
    buffContainer._naturalW, buffContainer._naturalH = bw, bh
    buffContainer:SetSize(bw, bh)

    local dw, dh = GridExtent(debuffProfile)
    debuffContainer._naturalW, debuffContainer._naturalH = dw, dh
    debuffContainer:SetSize(dw, dh)

    local anyBuffs   = settings.enableBuffs   and not settings.hideBuffFrame
    local anyDebuffs = settings.enableDebuffs and not settings.hideDebuffFrame
    local buffActive   = anyBuffs   and buffStrips   or EMPTY
    local debuffActive = anyDebuffs and debuffStrips or EMPTY

    local inc1, fresh1, inc2, fresh2
    if allowCreate then
        inc1, fresh1 = ApplyMoverElements(buffContainer,   buffActive,   true,  true)
        inc2, fresh2 = ApplyMoverElements(debuffContainer, debuffActive, false, true)
        if inc1 or inc2 then QueueContainerWork() end
    else
        local ok1, ok2
        ok1, inc1, fresh1 = ns.SafeCall("defer-ooc", ApplyMoverElements, buffContainer,   buffActive,   true,  false)
        ok2, inc2, fresh2 = ns.SafeCall("defer-ooc", ApplyMoverElements, debuffContainer, debuffActive, false, false)
        if (not ok1) or (not ok2) or inc1 or inc2 then QueueContainerWork() end
    end

    if anyBuffs then
        buffContainer:SetAlpha(settings.fadeBuffFrame and (settings.fadeOutAlpha or 0) or 1)
    else
        buffContainer:SetAlpha(0)
    end
    if anyDebuffs then
        debuffContainer:SetAlpha(settings.fadeDebuffFrame and (settings.fadeOutAlpha or 0) or 1)
    else
        debuffContainer:SetAlpha(0)
    end

    if ((not Helpers.IsLayoutModeActive()) or fresh1 or fresh2) and _G.QUI_ApplyFrameAnchor then
        _G.QUI_ApplyFrameAnchor("buffFrame")
        _G.QUI_ApplyFrameAnchor("debuffFrame")
    end

    if buffBorderStats then buffBorderStats.containerConfigs = buffBorderStats.containerConfigs + 1 end
end

ApplyContainerConfig = function()
    ApplyConfigPass(true)
end

local function ApplyMutableConfig()
    ApplyConfigPass(false)
end

local function ApplyOrDefer()
    if previewActive then return end
    if InCombatLockdown() then
        ApplyMutableConfig()
        QueueContainerWork()
        return
    end
    ApplyContainerConfig()
end

local function ShowPreview()
    if previewActive then return end
    if not buffContainer or not debuffContainer then return end

    local settings = GetSettings()
    if not settings then return end
    local Preview = ns.AuraPreview
    if not Preview or not ResolveAuraDeps() then return end
    previewActive = true

    if not InCombatLockdown() then
        DisableMoverContainers(buffContainer)
        DisableMoverContainers(debuffContainer)
    end

    if not buffContainer:IsShown() then buffContainer:Show() end
    if not debuffContainer:IsShown() then debuffContainer:Show() end
    buffContainer:SetAlpha(1)
    debuffContainer:SetAlpha(1)

    local function PreviewResolve(isBuff)
        return function(e)
            return ElementProfileFor(e, isBuff), e.anchor or "TOPLEFT",
                e.offsetX or 0, e.offsetY or 0
        end
    end

    local buffStrips  = ResolveStrips(GetBuffStore(settings), DefaultBuffBucket, _buffStrips, "HELPFUL")
    local buffProfile = buffStrips[1] and ElementProfileFor(buffStrips[1], true) or FallbackProfile(DefaultBuffBucket)
    local bw, bh = GridExtent(buffProfile)
    buffContainer._naturalW, buffContainer._naturalH = bw, bh
    buffContainer:SetSize(bw, bh)
    Preview.Show(buffContainer, buffStrips, { resolve = PreviewResolve(true) })

    local debuffStrips  = ResolveStrips(GetDebuffStore(settings), DefaultDebuffBucket, _debuffStrips, "HARMFUL")
    local debuffProfile = debuffStrips[1] and ElementProfileFor(debuffStrips[1], false) or FallbackProfile(DefaultDebuffBucket)
    local dw, dh = GridExtent(debuffProfile)
    debuffContainer._naturalW, debuffContainer._naturalH = dw, dh
    debuffContainer:SetSize(dw, dh)
    Preview.Show(debuffContainer, debuffStrips, { resolve = PreviewResolve(false) })

    if _G.QUI_LayoutModeSyncHandle then
        _G.QUI_LayoutModeSyncHandle("buffFrame")
        _G.QUI_LayoutModeSyncHandle("debuffFrame")
    end
end

local function HidePreview()
    if not previewActive then return end
    previewActive = false

    local Preview = ns.AuraPreview
    if Preview then
        Preview.Hide(buffContainer)
        Preview.Hide(debuffContainer)
    end

    ApplyOrDefer()
end

local GROW_ANCHOR_FRAC_X = { TOPLEFT = 0, TOPRIGHT = 1, BOTTOMLEFT = 0, BOTTOMRIGHT = 1 }
local GROW_ANCHOR_FRAC_Y = { TOPLEFT = 1, TOPRIGHT = 1, BOTTOMLEFT = 0, BOTTOMRIGHT = 0 }

local function FirstEnabledStripAnchor(store, fallback)
    if type(store) == "table" and type(store.elements) == "table" then
        local bucket = store.elements["*"]
        if type(bucket) == "table" then
            for _, e in ipairs(bucket) do
                if type(e) == "table" and e.enabled ~= false and e.mode == "filterStrip"
                    and GROW_ANCHOR_FRAC_X[e.anchor] ~= nil then
                    return e.anchor
                end
            end
        end
    end
    return fallback
end

local function UpdateGrowAnchor(faKey)
    if not faKey then return end
    local profile = QUI and QUI.db and QUI.db.profile
    if not profile then return end
    local bbDB = profile.buffBorders
    if type(bbDB) ~= "table" then return end

    local newCorner
    if faKey == "buffFrame" then
        newCorner = FirstEnabledStripAnchor(bbDB.buffAuras, "TOPRIGHT")
    elseif faKey == "debuffFrame" then
        newCorner = FirstEnabledStripAnchor(bbDB.debuffAuras, "TOPRIGHT")
    else
        return
    end

    if not profile.frameAnchoring then
        profile.frameAnchoring = {}
    end
    if not profile.frameAnchoring[faKey] then
        profile.frameAnchoring[faKey] = {}
    end
    local entry = profile.frameAnchoring[faKey]
    local oldCorner = entry.growAnchor

    if oldCorner == newCorner then return end

    local isNewCornerFormat = entry.point == oldCorner
        and entry.relative == oldCorner
        and GROW_ANCHOR_FRAC_X[oldCorner] ~= nil

    local isFreePosition = entry.parent == "disabled" or entry.parent == "screen"
    if isNewCornerFormat and oldCorner and isFreePosition then
        local pw = UIParent:GetWidth()
        local ph = UIParent:GetHeight()
        local dX = (GROW_ANCHOR_FRAC_X[oldCorner] - GROW_ANCHOR_FRAC_X[newCorner]) * pw
        local dY = (GROW_ANCHOR_FRAC_Y[oldCorner] - GROW_ANCHOR_FRAC_Y[newCorner]) * ph
        entry.offsetX = math.floor((entry.offsetX or 0) + dX + 0.5)
        entry.offsetY = math.floor((entry.offsetY or 0) + dY + 0.5)
        entry.point = newCorner
        entry.relative = newCorner
    end

    entry.growAnchor = newCorner

    if _G.QUI_ApplyFrameAnchor then
        _G.QUI_ApplyFrameAnchor(faKey)
    end
end

local Init

local function FullRefresh()
    if not buffContainer or not debuffContainer then return end

    ManageBlizzardFrames()

    UpdateGrowAnchor("buffFrame")
    UpdateGrowAnchor("debuffFrame")

    if previewActive then
        HidePreview()
        ShowPreview()
        return
    end

    ApplyOrDefer()

    if not Helpers.IsLayoutModeActive() then
        if _G.QUI_ApplyFrameAnchor then
            _G.QUI_ApplyFrameAnchor("buffFrame")
            _G.QUI_ApplyFrameAnchor("debuffFrame")
            if _G.QUI_UpdateFramesAnchoredTo then
                _G.QUI_UpdateFramesAnchoredTo("buffFrame")
                _G.QUI_UpdateFramesAnchoredTo("debuffFrame")
            end
        end
    else
        if _G.QUI_LayoutModeSyncHandle then
            _G.QUI_LayoutModeSyncHandle("buffFrame")
            _G.QUI_LayoutModeSyncHandle("debuffFrame")
        end
    end
end

local function TryDeferredFullRefresh()
    if previewActive then return end
    if not initialized then
        Init()
        return
    end
    if not buffContainer or not debuffContainer then return end
    FullRefresh()
end

local function BuildFrames()
    buffContainer = CreateFrame("Frame", "QUI_BuffIconContainer", UIParent)
    buffContainer:SetSize(1, 1)
    buffContainer:SetClampedToScreen(true)

    debuffContainer = CreateFrame("Frame", "QUI_DebuffIconContainer", UIParent)
    debuffContainer:SetSize(1, 1)
    debuffContainer:SetClampedToScreen(true)
end

Init = function()
    if initialized then return true end
    initialized = true

    BuildFrames()

    UpdateGrowAnchor("buffFrame")
    UpdateGrowAnchor("debuffFrame")

    local applyAnchor = _G.QUI_ApplyFrameAnchor
    if applyAnchor then
        applyAnchor("buffFrame")
        applyAnchor("debuffFrame")
    end

    ManageBlizzardFrames()

    ApplyOrDefer()

    C_Timer.After(0.1, ApplyOrDefer)
    C_Timer.After(0.5, TryDeferredFullRefresh)
    C_Timer.After(2.0, TryDeferredFullRefresh)
    return true
end

local paRegenFrame = CreateFrame("Frame")
paRegenFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
paRegenFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
paRegenFrame:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_ENTERING_WORLD" then
        C_Timer.After(0, function()
            if previewActive then return end
            local container = buffContainer and buffContainer._quiLiveContainer
            if container then container:UpdateAllAuras() end
        end)
    else
        FlushPendingContainerWork()
    end
end)

local function SetupDebugInstrumentation()
    buffBorderStats = {
        containerConfigs = 0,
    }
    local mp = ns._memprobes or {}; ns._memprobes = mp
    mp[#mp + 1] = { name = "BB_containerConfigs", counter = true, fn = function() return buffBorderStats.containerConfigs end }
    local reg = ns.QUI_PerfRegistry or {}; ns.QUI_PerfRegistry = reg
    reg[#reg + 1] = { name = "BuffBorders_CombatEnd", frame = paRegenFrame }
end
if ns.DebugRegister then
    ns.DebugRegister(SetupDebugInstrumentation)
else
    SetupDebugInstrumentation()
end

C_Timer.After(1, TryDeferredFullRefresh)

local function RefreshBuffBorders()
    if not initialized and not Init() then return end
    FullRefresh()
end

QUI.BuffBorders = {
    Init = Init,
    Apply = RefreshBuffBorders,
    ShowPreview = ShowPreview,
    HidePreview = HidePreview,
}

_G.QUI_RefreshBuffBorders = RefreshBuffBorders

ns.QUI_RefreshBuffBorderAuras = RefreshBuffBorders

_G.QUI_BuffBordersShowPreview = ShowPreview
_G.QUI_BuffBordersHidePreview = HidePreview

if ns.Registry then
    ns.Registry:Register("buffBorders", {
        refresh = _G.QUI_RefreshBuffBorders,
        priority = 60,
        group = "ui",
        importCategories = { "cdm" },
    })
end
