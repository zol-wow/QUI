local ADDON_NAME, ns = ...

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

local Helpers = ns.Helpers

local function IsSecretValue(value)
    if Helpers and Helpers.IsSecretValue then
        return Helpers.IsSecretValue(value) == true
    end
    if issecretvalue then
        return issecretvalue(value) == true
    end
    return false
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

function CDMShared.IsSafeNumeric(value)
    if IsSecretValue(value) then
        return false
    end
    return type(value) == "number"
end

function CDMShared.SafeBoolean(value)
    if IsSecretValue(value) then
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
