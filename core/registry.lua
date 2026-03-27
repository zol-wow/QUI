---------------------------------------------------------------------------
-- QUI Module Registry
-- Central registry mapping modules to refresh functions, priorities,
-- groups, and import categories. Enables targeted refresh after selective
-- profile imports and ordered refresh on profile change.
---------------------------------------------------------------------------
local ADDON_NAME, ns = ...

local Registry = {}
ns.Registry = Registry

Registry._modules = {}     -- name → module definition
Registry._moduleOrder = nil -- sorted name list (built lazily)

---------------------------------------------------------------------------
-- REGISTRATION
---------------------------------------------------------------------------

--- Register a module with the registry.
--- @param name string Unique module identifier
--- @param def table { refresh=fn, priority=number, group=string, importCategories={...} }
function Registry:Register(name, def)
    if not name or type(def) ~= "table" then return end
    def.name = name
    def.priority = def.priority or 50
    self._modules[name] = def
    self._moduleOrder = nil -- invalidate sort cache
end

---------------------------------------------------------------------------
-- INTERNAL SORT
---------------------------------------------------------------------------

function Registry:_RebuildOrder()
    local order = {}
    for name in pairs(self._modules) do
        order[#order + 1] = name
    end
    table.sort(order, function(a, b)
        local pa = self._modules[a].priority
        local pb = self._modules[b].priority
        if pa ~= pb then return pa < pb end
        return a < b
    end)
    self._moduleOrder = order
end

---------------------------------------------------------------------------
-- REFRESH API
---------------------------------------------------------------------------

local function SafeCallRefresh(name, fn)
    local ok, err = pcall(fn)
    if not ok then
        print("|cFFFF6666QUI:|r refresh error [" .. name .. "]: " .. tostring(err))
    end
end

--- Refresh all modules, optionally filtered by group.
--- @param groupFilter string|nil Only refresh modules in this group (nil = all)
function Registry:RefreshAll(groupFilter)
    if not self._moduleOrder then self:_RebuildOrder() end
    for _, name in ipairs(self._moduleOrder) do
        local m = self._modules[name]
        if m.refresh and (not groupFilter or m.group == groupFilter) then
            SafeCallRefresh(name, m.refresh)
        end
    end
end

--- Refresh only modules whose importCategories overlap with the given IDs.
--- Used by selective profile import to avoid refreshing unrelated modules.
--- @param categoryIDs table Array of category ID strings
function Registry:RefreshByCategories(categoryIDs)
    if not categoryIDs or #categoryIDs == 0 then return end

    local categorySet = {}
    for _, id in ipairs(categoryIDs) do
        categorySet[id] = true
    end

    if not self._moduleOrder then self:_RebuildOrder() end
    for _, name in ipairs(self._moduleOrder) do
        local m = self._modules[name]
        if m.refresh and m.importCategories then
            for _, catID in ipairs(m.importCategories) do
                if categorySet[catID] then
                    SafeCallRefresh(name, m.refresh)
                    break -- don't call refresh twice for same module
                end
            end
        end
    end
end

