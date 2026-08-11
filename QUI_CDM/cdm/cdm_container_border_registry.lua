local ADDON_NAME, ns = ...
local Helpers = ns.Helpers

local function CollectContainerRows(profile)
    local out = {}
    local ncdm = profile and profile.ncdm
    if type(ncdm) ~= "table" then return out end

    local seen = {}
    local function addRows(container)
        if type(container) ~= "table" then return end
        for i = 1, 3 do
            local rowTable = container["row" .. i]
            if type(rowTable) == "table" and not seen[rowTable] then
                seen[rowTable] = true
                out[#out + 1] = rowTable
            end
        end
    end

    addRows(ncdm.essential)
    addRows(ncdm.utility)

    if type(ncdm.containers) == "table" then
        for _, container in pairs(ncdm.containers) do
            addRows(container)
        end
    end

    return out
end

local function CollectBuffContainers(profile)
    local out = {}
    local ncdm = profile and profile.ncdm
    if type(ncdm) ~= "table" then return out end

    local seen = {}
    local function add(container)
        if type(container) == "table" and not seen[container] then
            seen[container] = true
            out[#out + 1] = container
        end
    end

    add(ncdm.buff)
    add(ncdm.trackedBar)

    if type(ncdm.containers) == "table" then
        add(ncdm.containers.buff)
        add(ncdm.containers.trackedBar)
        for _, container in pairs(ncdm.containers) do
            if type(container) == "table"
                and (container.containerType == "aura" or container.containerType == "auraBar") then
                add(container)
            end
        end
    end

    return out
end

if Helpers and Helpers.BorderRegistry then
    Helpers.BorderRegistry.Register({
        key      = "cdmContainers",
        label    = "CDM Icon Containers",
        category = "CDM",
        prefix   = "",
        multi    = true,
        db       = function(p)
            local insts = CollectContainerRows(p)
            return insts and insts[1]
        end,
        instances = CollectContainerRows,
        refresh  = function() if _G.QUI_RefreshNCDM then _G.QUI_RefreshNCDM() end end,
        legacy   = { table = "borderColorTable" },
    })

    Helpers.BorderRegistry.Register({
        key      = "cdmBuffContainers",
        label    = "CDM Buff Containers",
        category = "CDM",
        prefix   = "",
        multi    = true,
        db       = function(p)
            local insts = CollectBuffContainers(p)
            return insts and insts[1]
        end,
        instances = CollectBuffContainers,
        refresh  = function() if _G.QUI_RefreshNCDM then _G.QUI_RefreshNCDM() end end,
        legacy   = { defaultSource = "inherit" },
    })
end
