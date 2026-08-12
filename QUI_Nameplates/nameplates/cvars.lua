local ADDON_NAME, ns = ...
local NP = ns.QUI_Nameplates
if not NP then return end

local pcall = pcall
local type = type
local tostring = tostring
local InCombatLockdown = InCombatLockdown
local SetCVar = SetCVar
local CreateFrame = CreateFrame

local NPCVars = {}
ns.QUI_NameplatesCVars = NPCVars
NP.CVars = NPCVars

local pendingCVars = {}
local pendingActions = {}
local hasPending = false

local replayFrame = CreateFrame("Frame")
replayFrame:RegisterEvent("PLAYER_REGEN_ENABLED")

local function WriteCVar(name, value)
    pcall(SetCVar, name, value)
end

function NPCVars.Set(name, value)
    if InCombatLockdown() then
        pendingCVars[name] = value
        hasPending = true
        return
    end
    WriteCVar(name, value)
end

local function RunOrDefer(key, fn)
    if InCombatLockdown() then
        pendingActions[key] = fn
        hasPending = true
        return
    end
    pcall(fn)
end

replayFrame:SetScript("OnEvent", function()
    if not hasPending then return end
    hasPending = false
    for name, value in pairs(pendingCVars) do
        WriteCVar(name, value)
    end
    wipe(pendingCVars)
    for _, fn in pairs(pendingActions) do
        pcall(fn)
    end
    wipe(pendingActions)
end)

function NPCVars.ApplyScaleEnvironment()
    if not NP.IsEnabled() then return end
    local s = NP.GetSettings()
    local cv = s.cvars or {}

    NPCVars.Set("nameplateMinScale", 1)
    NPCVars.Set("nameplateMaxScale", 1)
    NPCVars.Set("nameplateSelectedScale", 1)
    NPCVars.Set("nameplateShowAll", 1)
    if cv.maxDistance then
        NPCVars.Set("nameplateMaxDistance", cv.maxDistance)
    end

    if C_CVar and C_CVar.GetCVarInfo and C_CVar.GetCVarInfo("nameplateSimplifiedScale") then
        NPCVars.Set("nameplateSimplifiedScale", NP.SimplifiedScale(s))
    end

    local fading = s.fading or {}
    if fading.occludedAlphaMult then
        NPCVars.Set("nameplateOccludedAlphaMult", fading.occludedAlphaMult)
    end
end

local function ResolvePlateSize(settings)
    local cv = (settings and settings.cvars) or {}
    local scaleX = (cv.hitboxScaleX or 100) / 100
    local scaleY = (cv.hitboxScaleY or 100) / 100

    if settings and NP.NormalizeTypes then
        NP.NormalizeTypes(settings)
    end
    local types = settings and settings.types
    local order = NP.PlateType and NP.PlateType.ORDER

    local maxW, maxH = 0, 0
    if type(types) == "table" and type(order) == "table" then
        for i = 1, #order do
            local t = types[order[i]]
            if type(t) == "table" then
                local health = t.health or {}
                local nameS = t.name or {}
                local pb = t.powerBar or {}
                local w = (health.width or 210) * scaleX
                local h = (health.height or 24) * scaleY
                local castH = (t.castbar and t.castbar.height) or 17
                local nameH = (nameS.size or 11) + math.abs(nameS.offsetY or 4)
                local powerH = (pb.enabled == true) and (pb.height or 6) or 0
                local totalH = h + castH + powerH + nameH
                if w > maxW then maxW = w end
                if totalH > maxH then maxH = totalH end
            end
        end
    end

    if maxW <= 0 or maxH <= 0 then
        maxW = 210 * scaleX
        maxH = (24 * scaleY) + 17 + 15
    end
    local plateScale = NP.PlateScale(settings)
    return maxW * plateScale, maxH * plateScale
end

function NPCVars.ApplyPlateSize()
    if not NP.IsEnabled() then return end
    if not (C_NamePlate and C_NamePlate.SetNamePlateSize) then return end
    local s = NP.GetSettings()
    local cv = s.cvars or {}
    local w, totalH = ResolvePlateSize(s)
    RunOrDefer("plateSize", function()
        C_NamePlate.SetNamePlateSize(w, totalH)
    end)

    if C_NamePlateManager and C_NamePlateManager.SetNamePlateHitTestInsets
        and Enum and Enum.NamePlateType then
        RunOrDefer("hitInsets", function()
            local CT = 10000
            local enemyInset = (cv.clickthroughEnemy == true) and CT or 0
            local friendInset = (cv.clickthroughFriendly == true) and CT or 0
            C_NamePlateManager.SetNamePlateHitTestInsets(Enum.NamePlateType.Enemy,
                enemyInset, enemyInset, enemyInset, enemyInset)
            C_NamePlateManager.SetNamePlateHitTestInsets(Enum.NamePlateType.Friendly,
                friendInset, friendInset, friendInset, friendInset)
        end)
    end
end

function NPCVars.ApplyStacking()
    if not NP.IsEnabled() then return end
    local s = NP.GetSettings()
    local cv = s.cvars or {}
    if not (C_CVar and C_CVar.SetCVarBitfield and Enum and Enum.NamePlateStackType) then return end
    RunOrDefer("stacking", function()
        C_CVar.SetCVarBitfield("nameplateStackingTypes", Enum.NamePlateStackType.Enemy, cv.stackingEnemy ~= false)
        C_CVar.SetCVarBitfield("nameplateStackingTypes", Enum.NamePlateStackType.Friendly, cv.stackingFriendly == true)
    end)
end

function NPCVars:IsActive()
    local s = NP.GetSettings()
    return NP.IsEnabled() and not (s.friendly and s.friendly.enabled == false)
end

local function ApplyFriendlyVisibility()
    local s = NP.GetSettings()
    local friendly = s.friendly or {}
    local mode = NP.Friendly.EffectiveMode()

    local inInstance = NP.Extras.GetContext().inInstance == true
    local visible = mode ~= "off" and (inInstance or friendly.showInWorld ~= false)
    local showPlayers = visible
    local showNPCs = visible and friendly.showNPCs ~= false
    NPCVars.Set("nameplateShowFriends", showPlayers and 1 or 0)
    NPCVars.Set("nameplateShowFriendlyPlayers", showPlayers and 1 or 0)
    NPCVars.Set("nameplateShowFriendlyNpcs", showNPCs and 1 or 0)
    NPCVars.Set("nameplateShowFriendlyNPCs", showNPCs and 1 or 0)
end
NPCVars.ApplyFriendlyVisibility = ApplyFriendlyVisibility

local UNIT_VISIBILITY_CVARS = {
    { key = "showEnemies",           cvar = "nameplateShowEnemies",                default = true },
    { key = "showEnemyPets",         cvar = "nameplateShowEnemyPets",              default = true },
    { key = "showEnemyTotems",       cvar = "nameplateShowEnemyTotems",            default = true },
    { key = "showEnemyGuardians",    cvar = "nameplateShowEnemyGuardians",         default = true },
    { key = "showEnemyMinions",      cvar = "nameplateShowEnemyMinions",           default = true },
    { key = "showEnemyMinus",        cvar = "nameplateShowEnemyMinus",             default = true },
    { key = "showFriendlyPets",      cvar = "nameplateShowFriendlyPlayerPets",      default = true },
    { key = "showFriendlyTotems",    cvar = "nameplateShowFriendlyPlayerTotems",    default = true },
    { key = "showFriendlyGuardians", cvar = "nameplateShowFriendlyPlayerGuardians", default = true },
    { key = "showFriendlyMinions",   cvar = "nameplateShowFriendlyPlayerMinions",   default = true },
}

local UNPIN_FLAG = "_friendlyVisibilityUnpinned"
local UNPIN_KEYS = {
    showFriendlyPets = true,
    showFriendlyTotems = true,
    showFriendlyGuardians = true,
    showFriendlyMinions = true,
}

function NPCVars.UnpinFriendlyVisibility(cv)
    if type(cv) ~= "table" then return false end
    if rawget(cv, UNPIN_FLAG) == true then return false end
    rawset(cv, UNPIN_FLAG, true)
    for i = 1, #UNIT_VISIBILITY_CVARS do
        local def = UNIT_VISIBILITY_CVARS[i]
        if UNPIN_KEYS[def.key] then
            rawset(cv, def.key, def.default)
        end
    end
    return true
end

local ENEMY_CHILD_KEYS = {
    showEnemyPets = true,
    showEnemyTotems = true,
    showEnemyGuardians = true,
    showEnemyMinions = true,
    showEnemyMinus = true,
}

local ENEMY_MINION_CHILD_KEYS = {
    showEnemyPets = true,
    showEnemyTotems = true,
    showEnemyGuardians = true,
}

local FRIENDLY_MINION_CHILD_KEYS = {
    showFriendlyPets = true,
    showFriendlyTotems = true,
    showFriendlyGuardians = true,
}

local FRIENDLY_KIND_KEYS = {
    showFriendlyPets = true,
    showFriendlyTotems = true,
    showFriendlyGuardians = true,
    showFriendlyMinions = true,
}

function NPCVars.ResolveUnitVisibility(cv, friendlyOff)
    cv = cv or {}

    local master = cv.showEnemies
    if master == nil then master = true end

    local enemyMinions = cv.showEnemyMinions
    if enemyMinions == nil then enemyMinions = true end

    local friendlyMinions = cv.showFriendlyMinions
    if friendlyMinions == nil then friendlyMinions = true end

    local out = {}
    for i = 1, #UNIT_VISIBILITY_CVARS do
        local def = UNIT_VISIBILITY_CVARS[i]
        local v = cv[def.key]
        if v == nil then v = def.default end
        if master == false and ENEMY_CHILD_KEYS[def.key] then v = false end
        if (master == false or enemyMinions == false) and ENEMY_MINION_CHILD_KEYS[def.key] then
            v = false
        end
        if friendlyMinions == false and FRIENDLY_MINION_CHILD_KEYS[def.key] then v = false end
        if friendlyOff == true and FRIENDLY_KIND_KEYS[def.key] then v = false end
        out[def.cvar] = v and 1 or 0
    end
    return out
end

function NPCVars.IsTypeVisible(cv, typeKey)
    cv = cv or {}
    local settings = NP.GetSettings()
    local friendly = type(settings) == "table" and settings.friendly or nil
    local friendlyOff = type(friendly) == "table" and friendly.enabled == false
    local map = NPCVars.ResolveUnitVisibility(cv, friendlyOff)
    if typeKey == "enemyPlayer" or typeKey == "enemyNPC" or typeKey == "bossElite" then
        return map.nameplateShowEnemies == 1
    end
    if typeKey == "minorTrivial" then
        return map.nameplateShowEnemyMinus == 1
    end
    if typeKey == "petMinion" then
        return map.nameplateShowEnemyPets == 1
            or map.nameplateShowEnemyTotems == 1
            or map.nameplateShowEnemyGuardians == 1
            or map.nameplateShowEnemyMinions == 1
            or map.nameplateShowFriendlyPlayerPets == 1
            or map.nameplateShowFriendlyPlayerTotems == 1
            or map.nameplateShowFriendlyPlayerGuardians == 1
            or map.nameplateShowFriendlyPlayerMinions == 1
    end
    if typeKey == "friendly" then
        return not friendlyOff
    end
    return true
end

function NPCVars.ApplyUnitVisibility()
    if not NP.IsEnabled() then return end
    local settings = NP.GetSettings()
    local cv = settings.cvars
    if type(cv) ~= "table" then
        cv = {}
        settings.cvars = cv
    end
    NPCVars.UnpinFriendlyVisibility(cv)
    local friendly = settings.friendly
    local friendlyOff = type(friendly) == "table" and friendly.enabled == false
    for cvar, value in pairs(NPCVars.ResolveUnitVisibility(cv, friendlyOff)) do
        NPCVars.Set(cvar, value)
    end
end

function NPCVars.ApplyAll()
    if not NP.IsEnabled() then return end
    NPCVars.ApplyScaleEnvironment()
    NPCVars.ApplyPlateSize()
    NPCVars.ApplyStacking()
    NPCVars.ApplyUnitVisibility()
    ApplyFriendlyVisibility()
end
