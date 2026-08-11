-- tests/unit/groupframes_mrb_relevance_test.lua
-- ElementShouldCheckBuff: in classDetection mode, a no-providerClass (CDM) buff is
-- always relevant; built-in buffs stay gated to the player's class.
-- Run: lua tests/unit/groupframes_mrb_relevance_test.lua

_G.issecretvalue = function() return false end
function CreateFrame() return { RegisterEvent = function() end, RegisterUnitEvent = function() end, SetScript = function() end } end
_G.C_Timer = { After = function() end }
_G.wipe = function(t) for k in pairs(t) do t[k] = nil end end
-- player class = MAGE (GetPlayerClass localizes UnitClass at load, so set first)
_G.UnitClass = function(unit) return "Mage", "MAGE" end

local ns = {}
assert(loadfile("QUI_GroupFrames/groupframes/groupframes_missing_raid_buffs.lua"))("QUI", ns)
local MRB = assert(ns.QUI_GroupFrameMissingRaidBuffs)
local check = assert(MRB.ElementShouldCheckBuff, "ElementShouldCheckBuff must be exposed")

local el = { classDetection = true }
assert(check(el, { key = "cdm:100", providerClass = nil }) == true,
    "CDM (no providerClass) buff is always relevant in classDetection mode")
assert(check(el, { key = "intellect", providerClass = "MAGE" }) == true,
    "player-class (MAGE -> intellect) built-in buff is relevant")
assert(check(el, { key = "stamina", providerClass = "PRIEST" }) == false,
    "non-player-class built-in buff (PRIEST) is NOT relevant for a MAGE")

print("OK groupframes_mrb_relevance_test")
