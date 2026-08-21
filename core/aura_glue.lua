local ADDON_NAME, ns = ...
local G = ns.AuraGlue or {}
ns.AuraGlue = G
_G.QUI = _G.QUI or {}
_G.QUI.AuraGlue = G

local E
local AuraSkin

local function ResolveE()
    E = E or ns.AuraElements
    return E
end

local function ResolveAuraSkin()
    AuraSkin = AuraSkin or (ns.Addon and ns.Addon.AuraSkin) or (_G.QUI and _G.QUI.AuraSkin)
    return AuraSkin
end

G.DISPEL_TYPES = { "Magic", "Curse", "Disease", "Poison", "Bleed" }

G.DISPEL_DEFAULT_COLORS = {
    Magic   = { 0.2, 0.6, 1.0, 1 },
    Curse   = { 0.6, 0.0, 1.0, 1 },
    Disease = { 0.6, 0.4, 0.0, 1 },
    Poison  = { 0.0, 0.6, 0.0, 1 },
    Bleed   = { 0.8, 0.0, 0.0, 1 },
}

local function SortMethodFor(rule)
    local M = _G.AuraContainerSortMethod
    if not M then return 0 end
    local map = {
        INDEX = M.AuraInstanceIDOnly or M.Default, DEFAULT = M.Default,
        EXPIRY = M.Expiration, EXPIRY_ONLY = M.ExpirationOnly,
        NAME = M.Name, NAME_ONLY = M.NameOnly,
        BIG_DEFENSIVE = M.BigDefensive,
        IMPORTANT_ONLY = M.ImportantOnly, UF_DEBUFF = M.UnitFrameDebuff,
    }
    return map[rule or "INDEX"] or M.Default
end

local function SortDirectionFor(reverse)
    local D = _G.AuraContainerSortDirection
    if not D then return reverse and 1 or 0 end
    return reverse and D.Reverse or D.Normal
end

function G.ElementProfile(element, overrides)
    local anchor = element.anchor or "TOPLEFT"
    local maxIcons
    if element.mode == "tracked" and ResolveE() and E.TrackedSpellCount then
        maxIcons = E.TrackedSpellCount(element)
    else
        maxIcons = element.maxIcons or 0
        if maxIcons <= 0 then maxIcons = 40 end
    end
    local p = {
        maxIcons     = maxIcons,
        iconSize     = (element.iconSize and element.iconSize > 0) and element.iconSize or 22,
        spacing      = element.spacing or 2,
        rowSpacing   = element.rowSpacing or 0,
        grow         = element.growDirection or "RIGHT",
        maxPerRow    = element.iconsPerRow or 0,
        offsetX      = element.offsetX or 0,
        offsetY      = element.offsetY or 0,
        anchor       = anchor,
        wrap         = (anchor:find("BOTTOM", 1, true) and "UP" or "DOWN"),
        borderSize   = element.borderSize or 1,
        showBorder   = element.hideBorder ~= true,
        fontSize     = (element.duration and element.duration.fontSize) or 9,
        hideSwipe    = element.hideSwipe or false,
        reverseSwipe = element.reverseSwipe or false,
        swipeStyle   = element.swipeStyle or "radial",
        duration     = element.duration,
        stack        = element.stack,
        borderColor  = element.borderColor,
        dispelColors = element.dispelColors,
        dispelAssets = element.dispelAssets,
        pandemicGlow = element.pandemicGlow,
        dispelBorderMode = element.dispelBorderMode,
        tooltipAnchor       = element.tooltipAnchor,
        tooltipAnchorX      = element.tooltipAnchorX,
        tooltipAnchorY      = element.tooltipAnchorY,
        tooltipHideInCombat = element.tooltipHideInCombat,
    }
    if overrides then
        for k, v in pairs(overrides) do p[k] = v end
    end
    return p
end

local probeVerdict = {}
local READABLE_SELF_FILTERS = { "HELPFUL", "HARMFUL" }
local READABLE_TARGET_FILTERS = { "HELPFUL|PLAYER", "HARMFUL|PLAYER" }
local readableAuraSeen = {}
local readableAuraData = {}
local readableAuraFilters = {}
local readableAuraCount = 0

local function ClearReadableAuraScratch()
    for i = 1, readableAuraCount do
        readableAuraData[i] = nil
        readableAuraFilters[i] = nil
    end
    readableAuraCount = 0
end

local function IsUsableSpellIDKey(spellID)
    return type(spellID) == "number" and spellID > 0
end

function G.FilterStringUsable(unit, filterString)
    local AU = _G.AuraUtil
    if AU and AU.IsValidFilterString and not AU.IsValidFilterString(filterString) then
        return false
    end
    if not (C_UnitAuras and C_UnitAuras.GetUnitAuras) then return true end
    local cached = probeVerdict[filterString]
    if C_Secrets and C_Secrets.ShouldAurasBeSecret and C_Secrets.ShouldAurasBeSecret() then
        if cached ~= nil then return cached end
        return true
    end
    if cached == true then return true end
    local ok = (pcall(C_UnitAuras.GetUnitAuras, unit, filterString))
    if ok then
        probeVerdict[filterString] = true
        return true
    end
    local baselineOk = (pcall(C_UnitAuras.GetUnitAuras, unit, "HELPFUL"))
    if not baselineOk then return true end
    ok = (pcall(C_UnitAuras.GetUnitAuras, unit, filterString))
    probeVerdict[filterString] = ok
    return ok
end

function G.CollectReadableAuras(unit, callback)
    if G.AurasAreSecret and G.AurasAreSecret() then return nil end
    local unitAuras = C_UnitAuras
    if not (unitAuras and unitAuras.GetUnitAuraInstanceIDs
        and unitAuras.GetAuraDataByAuraInstanceID
        and type(callback) == "function") then
        return nil
    end
    ClearReadableAuraScratch()
    for instanceID in pairs(readableAuraSeen) do
        readableAuraSeen[instanceID] = nil
    end
    local filters = unit == "target" and READABLE_TARGET_FILTERS or READABLE_SELF_FILTERS
    for _, filter in ipairs(filters) do
        local ok, instanceIDs = ns.SafeCall(
            "secret-probe", unitAuras.GetUnitAuraInstanceIDs, unit, filter)
        if not ok or type(instanceIDs) ~= "table"
            or (issecretvalue and issecretvalue(instanceIDs)) then
            ClearReadableAuraScratch()
            return nil
        end
        for _, instanceID in ipairs(instanceIDs) do
            if instanceID and not (issecretvalue and issecretvalue(instanceID))
                and not readableAuraSeen[instanceID] then
                readableAuraSeen[instanceID] = true
                local dataOK, auraData = ns.SafeCall(
                    "secret-probe", unitAuras.GetAuraDataByAuraInstanceID,
                    unit, instanceID)
                if not dataOK then
                    ClearReadableAuraScratch()
                    return nil
                end
                if issecretvalue and issecretvalue(auraData) then
                    ClearReadableAuraScratch()
                    return nil -- @secret-policy: reject-secret-value
                end
                if auraData then
                    readableAuraCount = readableAuraCount + 1
                    readableAuraData[readableAuraCount] = auraData
                    readableAuraFilters[readableAuraCount] = filter
                end
            end
        end
    end
    for i = 1, readableAuraCount do
        callback(readableAuraData[i], readableAuraFilters[i])
    end
    ClearReadableAuraScratch()
    return true
end

function G.ReadAurasByInstanceID(unit, instanceIDs, callback)
    if G.AurasAreSecret and G.AurasAreSecret() then return false end
    local unitAuras = C_UnitAuras
    if not (unitAuras and unitAuras.GetAuraDataByAuraInstanceID)
        or type(instanceIDs) ~= "table" or type(callback) ~= "function" then
        return false
    end
    for _, instanceID in ipairs(instanceIDs) do
        if issecretvalue and issecretvalue(instanceID) then return false end -- @secret-policy: report-secret-detected
        local ok, auraData = ns.SafeCall(
            "secret-probe", unitAuras.GetAuraDataByAuraInstanceID, unit, instanceID)
        if not ok then return false end
        if issecretvalue and issecretvalue(auraData) then -- @secret-policy: reject-secret-value
            return false -- @secret-policy: reject-secret-value
        end
        callback(auraData, instanceID)
    end
    return true
end

function G.ReadAuraDurationByInstanceID(unit, auraInstanceID)
    if G.AurasAreSecret and G.AurasAreSecret() then return nil end
    local unitAuras = C_UnitAuras
    if not (unitAuras and unitAuras.GetAuraDuration) then return nil end
    if issecretvalue and (issecretvalue(unit) or issecretvalue(auraInstanceID)) then
        return nil -- @secret-policy: reject-secret-value
    end
    local ok, durationObj = ns.SafeCall(
        "secret-probe", unitAuras.GetAuraDuration, unit, auraInstanceID)
    if not ok or (issecretvalue and issecretvalue(durationObj)) then
        return nil -- @secret-policy: reject-secret-value
    end
    return durationObj
end

function G.GetCooldownAuraBySpellID(spellID)
    local unitAuras = C_UnitAuras
    if not (unitAuras and unitAuras.GetCooldownAuraBySpellID) then return nil end
    local ok, auraSpellID = ns.SafeCall(
        "secret-probe", unitAuras.GetCooldownAuraBySpellID, spellID)
    if not ok or (issecretvalue and issecretvalue(auraSpellID)) then return nil end
    return IsUsableSpellIDKey(auraSpellID) and auraSpellID or nil
end

function G.ElementGroups(unit, element, profile, cancelEligible)
    if not ResolveE() then return {} end
    local base = element.auraType or "HELPFUL"
    local strings = E.CompileFilters(element)
    local usable = {}
    for i = 1, #strings do
        local canonical = E.CanonicalizeFilterString and E.CanonicalizeFilterString(strings[i]) or strings[i]
        if G.FilterStringUsable(unit, canonical) then
            usable[#usable + 1] = canonical
        end
    end
    if #usable == 0 then
        local fallback = base
        if element.nameplateOnly then
            fallback = fallback .. "|INCLUDE_NAME_PLATE_ONLY"
        end
        usable[1] = (E.CanonicalizeFilterString and E.CanonicalizeFilterString(fallback)) or fallback
    end
    local cf = E.CompileCandidateFilters(element)
    local sortMethod = SortMethodFor(element.sortRule)
    local sortDirection = SortDirectionFor(element.sortReverse == true)
    local cancel
    if cancelEligible and base == "HELPFUL" and element.rightClickCancel ~= false then
        cancel = "RightButtonUp"
    end
    local groups = {}
    for i = 1, #usable do
        groups[i] = {
            key              = "s" .. i,
            filter           = usable[i],
            maxFrameCount    = profile.maxIcons,
            sortMethod       = sortMethod,
            sortDirection    = sortDirection,
            candidateFilters = cf,
            cancelButtons    = cancel,
        }
    end
    return groups
end

function G.RunConfigPass(container, profile, groups, allowCreate)
    if not ResolveAuraSkin() then return false end
    if allowCreate then
        AuraSkin.Configure(container, profile, groups)
        return true
    end
    local ok = ns.SafeCall("chain-next", AuraSkin.Configure, container, profile, groups)
    if not ok then
        AuraSkin.Restyle(container, profile)
    end
    return ok
end

local _pending = {}
local _regenFrame
local _pollArmed = false

local function AurasAreSecret()
    return C_Secrets and C_Secrets.ShouldAurasBeSecret and C_Secrets.ShouldAurasBeSecret()
end
G.AurasAreSecret = AurasAreSecret

local FlushPending

local function ArmRestrictionPoll()
    if _pollArmed then return end
    local After = C_Timer and C_Timer.After
    if not After then return end
    _pollArmed = true
    After(0.5, function()
        _pollArmed = false
        FlushPending()
    end)
end

FlushPending = function()
    if next(_pending) == nil then return end
    if (InCombatLockdown and InCombatLockdown()) or AurasAreSecret() then
        ArmRestrictionPoll()
        return
    end
    local run = _pending
    _pending = {}
    for owner, fn in pairs(run) do
        ns.SafeCall("bulkhead", fn, owner)
    end
end

local function EnsureRegenFrame()
    if _regenFrame or not CreateFrame then return end
    _regenFrame = CreateFrame("Frame")
    _regenFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
    _regenFrame:SetScript("OnEvent", FlushPending)
end

function G.QueueRegenWork(owner, fn)
    if (not InCombatLockdown or not InCombatLockdown()) and not AurasAreSecret() then
        fn(owner)
        return
    end
    EnsureRegenFrame()
    _pending[owner] = fn
    if not (InCombatLockdown and InCombatLockdown()) then
        ArmRestrictionPoll()
    end
end

return G
