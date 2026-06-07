-- Border Coloring registry: CDM per-row icon containers (multi-instance).
--
-- The per-row icon border color is stored on each row table (row1/row2/row3)
-- of the built-in cooldown containers and every unified/custom container.
-- The resolver reads borderColorSource + borderColor (prefix ""); migration
-- v40 renames the legacy per-row borderColorTable onto borderColor and stamps
-- borderColorSource = "custom" so existing per-row colors are preserved.
local ADDON_NAME, ns = ...
local Helpers = ns.Helpers

-- Collect every per-row settings table that drives icon borders. Returns the
-- SAME row tables that hold the keys so migration + bulk-apply mutate them in
-- place. Idempotent: migration skips any table already carrying the source key.
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

    -- Built-in top-level containers (the live tables GetContainerDB returns first).
    addRows(ncdm.essential)
    addRows(ncdm.utility)

    -- Unified containers mirror + any custom containers.
    if type(ncdm.containers) == "table" then
        for _, container in pairs(ncdm.containers) do
            addRows(container)
        end
    end

    return out
end

-- Collect the FLAT buff containers (aura icons + auraBar bars). Unlike the
-- cooldown containers above, these store their border config directly on the
-- container table (no row1/row2/row3), so the per-row collector never sees
-- them. The border color lives in borderColorSource + borderColor (prefix "")
-- exactly like a row table, so the resolver/options/refresh machinery works
-- once these tables are surfaced. Returns the SAME live tables for in-place
-- migration + bulk-apply. Built-in buff/trackedBar live at the top level (the
-- authoritative tables GetContainerDB returns first); the unified mirror and
-- any custom aura/auraBar containers come from ncdm.containers.
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

    -- Built-in top-level buff containers (authoritative live tables).
    add(ncdm.buff)
    add(ncdm.trackedBar)

    -- Unified mirror + any custom aura/auraBar containers.
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
        -- These containers never had a per-instance border color, so an
        -- un-migrated profile must fall through to "inherit" (the global skin
        -- border) — NOT the colorless "custom" the icon-row containers default
        -- to. See MigrateBorderColoringTable's defaultSource handling.
        legacy   = { defaultSource = "inherit" },
    })
end
