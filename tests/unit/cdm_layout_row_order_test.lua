-- tests/unit/cdm_layout_row_order_test.lua
-- Run: lua tests/unit/cdm_layout_row_order_test.lua

local ns = {}
local loadChunk = dofile("tests/helpers/load_cdm_consolidated_chunk.lua")
loadChunk("QUI_CDM/cdm/cdm_containers.lua", "cdm_layout.lua")("QUI", ns)

local Layout = assert(ns.CDMLayout, "CDMLayout should load")

local function icon(name, row)
    return {
        name = name,
        _spellEntry = {
            _assignedRow = row,
        },
    }
end

local function names(icons)
    local out = {}
    for i, item in ipairs(icons) do
        out[i] = item.name
    end
    return table.concat(out, ",")
end

local rows = {
    { rowNum = 1, count = 4 },
    { rowNum = 2, count = 4 },
}

local sorted = Layout.SortIconsByAssignedRow({
    icon("spell-a"),
    icon("spell-b"),
    icon("spell-c"),
    icon("item-last", 1),
}, rows)

assert(names(sorted) == "spell-a,spell-b,spell-c,item-last",
    "explicit row-1 entries should not jump ahead of unassigned row-1 entries")
assert(rows[1]._actualCount == 4, "row 1 should contain all four icons")
assert(rows[2]._actualCount == 0, "row 2 should be empty")

local function readAll(path)
    local file = assert(io.open(path, "rb"))
    local data = file:read("*a")
    file:close()
    return data
end

local source = readAll("QUI_CDM/cdm/cdm_spelldata.lua")
local buildStart = assert(source:find("function CDMSpellData:BuildSpellListFromOwned", 1, true),
    "BuildSpellListFromOwned should exist")
local buildEnd = assert(source:find("local RACE_RACIALS = {", buildStart, true),
    "extra-spell-tables section should follow BuildSpellListFromOwned")
local sortPos = source:find("table.sort(result", buildStart, true)
assert(not sortPos or sortPos > buildEnd,
    "BuildSpellListFromOwned should preserve saved entry order; row grouping belongs to CDMLayout")

local wrapperRows = {
    { rowNum = 1, count = 1 },
    { rowNum = 2, count = 2 },
}
local wrapperSorted = Layout.SortIconsByAssignedRow({
    { name = "native-row2", _assignedRow = 2 },
    { name = "owned-row1", _spellEntry = { _assignedRow = 1 } },
}, wrapperRows)

assert(names(wrapperSorted) == "owned-row1,native-row2",
    "reanchor wrappers must honor their direct _assignedRow when row-sorting")
assert(wrapperRows[1]._actualCount == 1, "row 1 should contain the owned row-1 icon")
assert(wrapperRows[2]._actualCount == 1, "row 2 should contain the native row-2 wrapper")

print("OK: cdm_layout_row_order_test")
