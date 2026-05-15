-- tests/cdm_composer_add_unlearned_test.lua
-- Run: lua tests/cdm_composer_add_unlearned_test.lua

local function readAll(path)
    local file = assert(io.open(path, "rb"))
    local data = file:read("*a")
    file:close()
    return data
end

local source = readAll("modules/cdm/cdm_composer.lua")

local addCellStart = assert(source:find("local function GetOrCreateAddCell", 1, true),
    "add cell factory should exist")
local addCellEnd = assert(source:find("RefreshAddList = function()", addCellStart, true),
    "add cell factory should appear before RefreshAddList")

local tooltipLine = source:find('GameTooltip:AddLine("Not Learned"', addCellStart, true)
assert(tooltipLine and tooltipLine < addCellEnd,
    "unlearned add entries should show a Not Learned tooltip line")
assert(source:find("self._isUnlearned", addCellStart, true),
    "add cell tooltip should read the cell's unlearned state")

local refreshStart = assert(source:find("RefreshAddList = function()", 1, true),
    "RefreshAddList should exist")
assert(source:find("cell._isUnlearned = entry.isKnown == false", refreshStart, true),
    "RefreshAddList should mark add cells whose CDM source entry is unlearned")
assert(source:find("cell._icon:SetDesaturated(isOwned or cell._isUnlearned)", refreshStart, true),
    "unlearned add entries should render desaturated like dormant entries")
assert(source:find("cell._isUnlearned and 0.6", refreshStart, true),
    "unlearned add entries should use the same soft alpha treatment as dormant entries")

print("OK: cdm_composer_add_unlearned_test")
