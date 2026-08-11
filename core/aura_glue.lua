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
    local maxIcons = element.maxIcons or 0
    if maxIcons <= 0 then maxIcons = 40 end
    local p = {
        maxIcons     = maxIcons,
        iconSize     = (element.iconSize and element.iconSize > 0) and element.iconSize or 22,
        spacing      = element.spacing or 2,
        grow         = element.growDirection or "RIGHT",
        maxPerRow    = element.iconsPerRow or 0,
        offsetX      = element.offsetX or 0,
        offsetY      = element.offsetY or 0,
        anchor       = anchor,
        wrap         = (anchor:find("BOTTOM", 1, true) and "UP" or "DOWN"),
        borderSize   = element.borderSize or 1,
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
