-- tests/unit/cdm_composer_add_unlearned_test.lua
-- Run: lua tests/unit/cdm_composer_add_unlearned_test.lua

local function readAll(path)
    local file = assert(io.open(path, "rb"))
    local data = file:read("*a")
    file:close()
    return data
end

local source = readAll("modules/cdm/settings/composer.lua")

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
assert(source:find("RefreshEntryList = function()", 1, true),
    "RefreshEntryList should exist")
assert(source:find("cell._isUnlearned = entry.isKnown == false", refreshStart, true),
    "RefreshAddList should mark add cells whose CDM source entry is unlearned")
assert(source:find("cell._icon:SetDesaturated(isOwned or cell._isUnlearned)", refreshStart, true),
    "unlearned add entries should render desaturated like dormant entries")
assert(source:find("cell._isUnlearned and 0.6", refreshStart, true),
    "unlearned add entries should use the same soft alpha treatment as dormant entries")
assert(source:find("spellData:AddSpell(activeContainer, addID, kindFromTab, targetRow)", refreshStart, true),
    "right-click add should pass the target row to AddSpell — and never a known-state hint: adds always land in the list")
assert(not source:find("entryRef.isKnown", refreshStart, true),
    "the picker's known-state must not be forwarded into the data layer")
assert(not source:find("spells%[#spells%]%.row = targetRow", refreshStart),
    "right-click add should not assign targetRow by mutating the last active entry after AddSpell")
assert(source:find('activeAddTab == "other_auras"', refreshStart, true)
    and source:find('AppendSpellIDSearchCandidate(sourceEntries, filterText)', refreshStart, true),
    "Other Auras should support numeric Spell ID search so non-passive aura entries can be added directly")

-- Right-click add's row1/2/3 capacity check applies only to built-in cooldown
-- containers (Essential/Utility). Custom bars (cooldown or auraBar shape) grow
-- from a single anchor and have no per-row caps; entering the row check for a
-- custom bar with no row1 defined leaves targetRow=nil and silently surfaces
-- "All rows are full" via UIErrorsFrame, which user UIs often suppress — the
-- click looks dead. The gate must include IsBuiltInContainer.
assert(source:find("if IsBuiltInContainer%(activeContainer%)%s+and ResolveContainerType%(activeContainer%) == \"cooldown\" then", refreshStart),
    "right-click add row capacity check should be gated on IsBuiltInContainer so custom bars don't fall into the built-in row1/2/3 model")

print("OK: cdm_composer_add_unlearned_test")
