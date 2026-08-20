local file = assert(io.open("modules/qol/tooltip.lua", "r"))
local source = file:read("*a")
file:close()

local spellStart = assert(source:find('AddTrackedTooltipPostCall(Enum.TooltipDataType.Spell, "qol.spellIDPost"', 1, true))
local auraStart = assert(source:find('AddTrackedTooltipPostCall(auraTooltipType, "qol.auraIDPost"', spellStart, true))
local visibilityStart = assert(source:find('AddTrackedTooltipPostCall(Enum.TooltipDataType.Spell, "qol.spellVisibilityPost"', auraStart, true))
local itemStart = assert(source:find('AddTrackedTooltipPostCall(Enum.TooltipDataType.Item, "qol.itemPost"', visibilityStart, true))
local inspectStart = assert(source:find("if TooltipInspect", itemStart, true))

local spellPost = source:sub(spellStart, auraStart - 1)
local auraPost = source:sub(auraStart, visibilityStart - 1)
local itemPost = source:sub(itemStart, inspectStart - 1)

assert(not spellPost:find("InCombatLockdown()", 1, true), "spell tooltip IDs must remain available in combat")
assert(auraPost:find("if InCombatLockdown() then return end", 1, true), "aura tooltip IDs must retain the combat gate")
assert(not itemPost:find("InCombatLockdown()", 1, true), "item tooltip content must remain available in combat")

print("OK: tooltip_content_combat_scope_test")
