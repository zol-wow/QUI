local _, ns = ...

---------------------------------------------------------------------------
-- CDM Shared Helpers
--
-- Small CDM-specific helpers used across runtime modules. Addon-wide helpers
-- stay in core/utils.lua; this file only owns cooldown-manager primitives.
---------------------------------------------------------------------------

local CDMShared = {}
ns.CDMShared = CDMShared

local type = type
local _G = _G
local issecretvalue = issecretvalue

local Helpers = ns.Helpers

CDMShared.BUILTIN_CONTAINER_KEYS = { "essential", "utility", "buff", "trackedBar" }
CDMShared.BUILTIN_COOLDOWN_CONTAINER_KEYS = { "essential", "utility" }
CDMShared.BUILTIN_AURA_CONTAINER_KEYS = { "buff", "trackedBar" }
CDMShared.BUILTIN_ICON_CONTAINER_KEYS = { "essential", "utility", "buff" }
CDMShared.BUILTIN_BAR_CONTAINER_KEYS = { "trackedBar" }

CDMShared.BUILTIN_CONTAINER_LABELS = {
    essential  = "Essential",
    utility    = "Utility",
    buff       = "Buff Icons",
    trackedBar = "Buff Bars",
}

-- Legacy persisted container type: describes the historical entry family,
-- not the renderer shape. New layout code should prefer container shape.
CDMShared.BUILTIN_CONTAINER_TYPES = {
    essential  = "cooldown",
    utility    = "cooldown",
    buff       = "aura",
    trackedBar = "auraBar",
}

CDMShared.BUILTIN_CONTAINER_SHAPES = {
    essential  = "icon",
    utility    = "icon",
    buff       = "icon",
    trackedBar = "bar",
}

-- Layout/options element key -> builtin container key. Shared by
-- cdm_layout_mode.lua and settings/containers_page.lua.
CDMShared.ELEMENT_TO_CONTAINER_MAP = {
    cdmEssential = "essential",
    cdmUtility = "utility",
    buffIcon = "buff",
    buffBar = "trackedBar",
}

local BUILTIN_CONTAINER_SET = {
    essential = true,
    utility = true,
    buff = true,
    trackedBar = true,
}

function CDMShared.IsBuiltinContainerKey(containerKey)
    return BUILTIN_CONTAINER_SET[containerKey] == true
end

function CDMShared.GetBuiltinContainerLabel(containerKey)
    return CDMShared.BUILTIN_CONTAINER_LABELS[containerKey]
end

function CDMShared.GetBuiltinContainerType(containerKey)
    return CDMShared.BUILTIN_CONTAINER_TYPES[containerKey]
end

function CDMShared.GetBuiltinContainerShape(containerKey)
    return CDMShared.BUILTIN_CONTAINER_SHAPES[containerKey]
end

function CDMShared.GetEntryKindForContainerType(containerType)
    if containerType == "cooldown" then return "cooldown" end
    if containerType == "aura" or containerType == "auraBar" then return "aura" end
    return nil
end

function CDMShared.GetBuiltinContainerEntryKind(containerKey)
    return CDMShared.GetEntryKindForContainerType(
        CDMShared.GetBuiltinContainerType(containerKey))
end

function CDMShared.ResolveKindForItemsTab(containerKey)
    local builtinKind = CDMShared.GetBuiltinContainerEntryKind(containerKey)
    if builtinKind == "aura" then return "aura" end
    return "cooldown"
end

function CDMShared.ShouldShowItemDisplayModeRow(entry, containerKey, containerDB)
    if type(entry) ~= "table" then return false end
    local etype = entry.type
    if etype ~= "item" and etype ~= "trinket" and etype ~= "slot" then
        return false
    end
    if CDMShared.IsBuiltinContainerKey(containerKey) then return false end
    if not CDMShared.IsCustomBarContainer(containerDB) then return false end
    return true
end

function CDMShared.GetBuiltinContainerKeysByEntryKind(entryKind)
    if entryKind == "cooldown" then
        return CDMShared.BUILTIN_COOLDOWN_CONTAINER_KEYS
    end
    if entryKind == "aura" then
        return CDMShared.BUILTIN_AURA_CONTAINER_KEYS
    end
    return nil
end

function CDMShared.GetBuiltinContainerKeysByShape(shape)
    if shape == "icon" then
        return CDMShared.BUILTIN_ICON_CONTAINER_KEYS
    end
    if shape == "bar" then
        return CDMShared.BUILTIN_BAR_CONTAINER_KEYS
    end
    return nil
end

function CDMShared.IsBuiltinCooldownContainerKey(containerKey)
    return CDMShared.GetBuiltinContainerEntryKind(containerKey) == "cooldown"
end

function CDMShared.IsBuiltinAuraContainerKey(containerKey)
    return CDMShared.GetBuiltinContainerEntryKind(containerKey) == "aura"
end

function CDMShared.IsBuiltinIconContainerKey(containerKey)
    return CDMShared.GetBuiltinContainerShape(containerKey) == "icon"
end

function CDMShared.IsBuiltinBarContainerKey(containerKey)
    return CDMShared.GetBuiltinContainerShape(containerKey) == "bar"
end

function CDMShared.IsCustomBarContainer(containerDB)
    return type(containerDB) == "table" and containerDB.containerType == "customBar"
end

function CDMShared.NormalizeCustomBarVisibilityFlags(containerDB)
    if not CDMShared.IsCustomBarContainer(containerDB) then return "always" end

    if containerDB.desaturateOnCooldown == nil then
        containerDB.desaturateOnCooldown = true
    end

    local mode = "always"
    if containerDB.showOnlyOnCooldown then
        mode = "onCooldown"
        containerDB.showOnlyWhenActive = false
        containerDB.showOnlyWhenOffCooldown = false
    elseif containerDB.showOnlyWhenActive then
        mode = "active"
        containerDB.showOnlyWhenOffCooldown = false
    elseif containerDB.showOnlyWhenOffCooldown then
        mode = "offCooldown"
    end

    containerDB.visibilityMode = mode

    if mode ~= "onCooldown" then
        containerDB.noDesaturateWithCharges = false
    end

    if containerDB.dynamicLayout == nil then
        containerDB.dynamicLayout = false
    end
    if containerDB.dynamicLayout and containerDB.clickableIcons then
        containerDB.clickableIcons = false
    end

    containerDB.tooltipContext = containerDB.tooltipContext or "customTrackers"
    containerDB.keybindContext = containerDB.keybindContext or "customTrackers"

    return mode
end

function CDMShared.GetCustomBarVisibilityMode(containerDB)
    if not CDMShared.IsCustomBarContainer(containerDB) then return "always" end
    return CDMShared.NormalizeCustomBarVisibilityFlags(containerDB)
end

function CDMShared.NormalizeMirrorCategory(category)
    if issecretvalue and issecretvalue(category) then return nil end
    if category == "essential"
        or category == "utility"
        or category == "buff"
        or category == "trackedBar" then
        return category
    end
    return nil
end

function CDMShared.IsAuraMirrorCategory(category)
    category = CDMShared.NormalizeMirrorCategory(category)
    return category == "buff" or category == "trackedBar"
end

function CDMShared.IsCooldownMirrorCategory(category)
    category = CDMShared.NormalizeMirrorCategory(category)
    return category == "essential" or category == "utility"
end

function CDMShared.IsRuntimeEnabled()
    local checker = _G.QUI_IsCDMMasterEnabled
    if type(checker) == "function" then
        return checker() ~= false
    end
    local ncdm = CDMShared.GetNcdmDB()
    return not ncdm or ncdm.enabled ~= false
end

function CDMShared.GetCore()
    if Helpers and Helpers.GetCore then
        local core = Helpers.GetCore()
        if core then return core end
    end
    return ns.Addon or _G.QUI
end

function CDMShared.GetNcdmDB()
    local core = CDMShared.GetCore()
    local db = core and core.db
    local profile = db and db.profile
    return profile and profile.ncdm or nil
end

function CDMShared.GetContainerDB(containerKey)
    local ncdm = CDMShared.GetNcdmDB()
    if not ncdm or type(containerKey) ~= "string" or containerKey == "" then
        return nil
    end
    if ncdm[containerKey] then
        return ncdm[containerKey]
    end
    return ncdm.containers and ncdm.containers[containerKey] or nil
end

function CDMShared.GetContainerType(containerKey, containerDB)
    local builtinType = CDMShared.GetBuiltinContainerType(containerKey)
    if builtinType then
        return builtinType
    end

    local db = containerDB or CDMShared.GetContainerDB(containerKey)
    return type(db) == "table" and db.containerType or nil
end

function CDMShared.GetContainerShape(containerKey, containerDB)
    local db = containerDB or CDMShared.GetContainerDB(containerKey)
    if type(db) == "table" then
        local shape = db.shape
        if shape == "icon" or shape == "bar" then
            return shape
        end
    end

    local builtinShape = CDMShared.GetBuiltinContainerShape(containerKey)
    if builtinShape then
        return builtinShape
    end

    if type(db) == "table" and db.containerType == "auraBar" then
        return "bar"
    end

    return "icon"
end

function CDMShared.GetContainerEntryKind(containerKey, containerDB)
    local builtinKind = CDMShared.GetBuiltinContainerEntryKind(containerKey)
    if builtinKind then
        return builtinKind
    end

    return CDMShared.GetEntryKindForContainerType(
        CDMShared.GetContainerType(containerKey, containerDB))
end

function CDMShared.IsSafeNumeric(value)
    if issecretvalue and issecretvalue(value) then
        return false
    end
    return type(value) == "number"
end

function CDMShared.SafeBoolean(value)
    if issecretvalue and issecretvalue(value) then
        return nil
    end
    if type(value) == "boolean" then
        return value
    end
    return nil
end

function CDMShared.SettingEnabled(value, fallback)
    if value == nil then
        return fallback == true
    end
    return value == true
end
