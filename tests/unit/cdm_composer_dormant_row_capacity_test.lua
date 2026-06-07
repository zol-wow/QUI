-- tests/unit/cdm_composer_dormant_row_capacity_test.lua
-- Run: lua tests/unit/cdm_composer_dormant_row_capacity_test.lua

local function readAll(path)
    local file = assert(io.open(path, "rb"))
    local data = file:read("*a")
    file:close()
    return data
end

local source = readAll("QUI_CDM/cdm/settings/composer.lua")
local previewSource = readAll("QUI_CDM/cdm/settings/composer_preview_driver.lua")
local rendererSource = readAll("QUI_CDM/cdm/cdm_icon_renderer.lua")
local catalogSource = readAll("QUI_CDM/cdm/cdm_catalog.lua")
local spellDataSource = readAll("QUI_CDM/cdm/cdm_spelldata.lua")

local helperPos = assert(source:find("local function EntryCountsForCooldownRowCapacity", 1, true),
    "composer should centralize dormant-aware cooldown row capacity checks")
assert(source:find("local function IsEntryDormantOnCurrentPlayer", 1, true),
    "composer should ask CDMSpellData for display-time dormant state")
assert(not source:find('if entry.kind == "aura" then return true end', 1, true),
    "aura entries must not bypass dormant classification")

local refreshStart = assert(source:find("RefreshEntryList = function()", 1, true),
    "RefreshEntryList should exist")
local groupingStart = assert(source:find("local rowEntries = {}", refreshStart, true),
    "RefreshEntryList should build cooldown row groupings")
assert(source:find("EntryCountsForCooldownRowCapacity(entry)", groupingStart, true),
    "cooldown row grouping should skip dormant entries when counting row capacity")

local cooldownRenderStart = assert(source:find("if isCooldown and #activeRowNums > 0 then", groupingStart, true),
    "RefreshEntryList should render built-in cooldown rows")
local customRenderStart = assert(source:find("else\n        -- customBar entries render", cooldownRenderStart, true),
    "custom/non-row entry rendering should follow built-in cooldown row rendering")
local cooldownRenderBlock = source:sub(cooldownRenderStart, customRenderStart - 1)
assert(cooldownRenderBlock:find("Dormant — Not Learned on This Character", 1, true),
    "built-in cooldown containers should render dormant entries outside active row sections")

local previewEntriesHelper = assert(source:find("local function GetPreviewEntries", 1, true),
    "composer should provide a filtered preview-entry projection")
assert(source:find("_G.QUI_GetCDMPreviewEntries = GetPreviewEntries", previewEntriesHelper, true),
    "composer should expose filtered preview entries to the preview driver")
assert(not source:find('containerType ~= "cooldown" and not isCustomBar', previewEntriesHelper, true),
    "preview entries should be dormant-filtered for aura and bar containers too")

local previewLayoutStart = assert(source:find("local function LayoutPreviewIconsImpl", 1, true),
    "composer preview icon layout helper should exist")
assert(source:find("local entries = GetPreviewEntries(containerKey, db)", previewLayoutStart, true),
    "preview icon layout should position only active preview entries")

local previewStyleStart = assert(source:find("local function StylePreviewIconsImpl", 1, true),
    "composer preview icon style helper should exist")
assert(source:find("local entries = GetPreviewEntries(containerKey, db)", previewStyleStart, true),
    "preview icon styling should match active preview entries")

local refreshIconsStart = assert(previewSource:find("local function RefreshIcons", 1, true),
    "preview driver icon refresh helper should exist")
assert(previewSource:find("QUI_GetCDMPreviewEntries", 1, true),
    "preview driver should read filtered preview entries from composer")
assert(previewSource:find("GetPreviewEntries(containerKey, containerDB)", refreshIconsStart, true),
    "preview driver should acquire icons from filtered preview entries")

local customRuntimeStart = assert(rendererSource:find("local function IsCustomBarEntryUsableOnCurrentClass", 1, true),
    "custom bar runtime entry filter should exist")
assert(rendererSource:find("IsEntryDormantForContainer", customRuntimeStart, true),
    "custom bar runtime filtering should use the same display-time dormant predicate")
assert(catalogSource:find('source = BLIZZARD_CDM_ENTRY_SOURCE', 1, true),
    "catalog-sourced picker and snapshot entries should carry Blizzard CDM provenance")
assert(source:find("local entrySource = entryRef.source", 1, true),
    "composer should preserve add-list provenance for CDM-backed spell picks")
assert(source:find("AddSpell(activeContainer, addID, kindFromTab, targetRow, entrySource)", 1, true),
    "right-click add should persist source provenance on spell entries")
assert(source:find('local BLIZZARD_CDM_ENTRY_SOURCE = "blizzardCDM"', 1, true)
    and source:find("entry.source ~= BLIZZARD_CDM_ENTRY_SOURCE", 1, true),
    "only Blizzard-CDM-sourced entries should be eligible for the Not added to /cdm warning")
assert(source:find("source = entry.source", 1, true),
    "add-list warning checks should preserve source provenance instead of treating all spell picks as CDM-backed")
assert(spellDataSource:find('normalized.source ~= BLIZZARD_CDM_ENTRY_SOURCE', 1, true),
    "manual aura spell IDs must not be treated as dormant just because they are absent from Blizzard CDM")

local stopDragStart = assert(source:find("StopDrag = function()", 1, true),
    "StopDrag should exist")
assert(source:find("EntryCountsForCooldownRowCapacity(e)", stopDragStart, true),
    "drag-to-row capacity checks should skip dormant entries")

local contextMenuStart = assert(source:find("local function ShowEntryContextMenu", 1, true),
    "entry context menu should exist")
assert(source:find("EntryCountsForCooldownRowCapacity(e)", contextMenuStart, true),
    "context-menu row capacity checks should skip dormant entries")

local addStart = assert(source:find("RefreshAddList = function()", 1, true),
    "RefreshAddList should exist")
assert(source:find("EntryCountsForCooldownRowCapacity(e)", addStart, true),
    "right-click add row selection should skip dormant entries")

local splitStart = assert(source:find("-- For non-specSpecific", refreshStart, true),
    "RefreshEntryList should document the dormant split for non-row containers")
assert(source:find("local splitDormant = not (isCustomBar and db.specSpecific)", splitStart, true),
    "aura, bar, and non-spec custom containers should render dormant entries in their own section")

assert(helperPos < refreshStart,
    "row-capacity helper should be defined before refresh and menu handlers use it")

print("OK: cdm_composer_dormant_row_capacity_test")
