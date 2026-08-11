local ADDON_NAME, ns = ...

local data = ns.LocaleData or {}
ns.LocaleData = data

local keys   = data.keys or {}
local active = data.active

local ids = {}
if active then
    for index = 1, #keys do
        ids[keys[index]] = index
    end
end

ns.L = setmetatable({}, {
    __index = function(_, key)
        if active then
            local id = ids[key]
            if id then
                local v = active[id]
                if v ~= nil then return v end
            end
        end
        return key
    end,
})
