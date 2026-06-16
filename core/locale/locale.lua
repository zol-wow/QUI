local ADDON_NAME, ns = ...

-- Locale data is populated before this file by core/locale/enUS.lua (base,
-- always) and the active core/locale/<locale>.lua (guarded; sets .active only
-- when GetLocale() matches). Both write into ns.LocaleData.
local data = ns.LocaleData or {}
ns.LocaleData = data

local base   = data.enUS or {}
local active = data.active          -- nil on enUS clients / unknown locales

-- Resolution: active translation -> enUS base -> the literal key.
-- Never returns nil, so an un-extracted or untranslated string renders English.
ns.L = setmetatable({}, {
    __index = function(_, key)
        if active then
            local v = active[key]
            if v ~= nil then return v end
        end
        local b = base[key]
        if b ~= nil then return b end
        return key
    end,
})
