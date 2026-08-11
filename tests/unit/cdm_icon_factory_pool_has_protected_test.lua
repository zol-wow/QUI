-- tests/unit/cdm_icon_factory_pool_has_protected_test.lua
-- Run: lua tests/unit/cdm_icon_factory_pool_has_protected_test.lua
--
-- PoolHasProtectedIcon: true iff a pooled icon carries a secure clickButton
-- child (protected for life, even after clickableIcons is toggled off). The
-- container combat gate uses this to defer a rebuild that would ADDON_ACTION_BLOCK.
local ns = {
    Helpers = {
        GetGeneralFont = function() return "Fonts\\FRIZQT__.TTF" end,
        GetGeneralFontOutline = function() return "" end,
        IsSecretValue = function() return false end,
        SafeValue = function(value) return value end,
    },
    CDMSources = {},
    CDMResolvers = {
        GetEntryTexture = function() return 134400 end,
        GetSpellTexture = function() return 134400 end,
        ResolveCooldownState = function() return nil end,
        ResolveMacro = function() return nil end,
        IsAuraEntry = function() return false end,
    },
}
local loadChunk = dofile("tests/helpers/load_cdm_consolidated_chunk.lua")
loadChunk("QUI_CDM/cdm/cdm_icon_factory.lua", "cdm_icon_factory.lua")("QUI", ns)
local F = assert(ns.CDMIconFactory)

assert(F:PoolHasProtectedIcon("nope") == false, "absent pool -> false")
local pool = F:EnsurePool("essential")
assert(F:PoolHasProtectedIcon("essential") == false, "empty pool -> false")

pool[1] = { id = 1 }
pool[2] = { id = 2 }
assert(F:PoolHasProtectedIcon("essential") == false, "plain icons -> false")

pool[2].clickButton = { secure = true }   -- hidden/cleared clickButton still counts
assert(F:PoolHasProtectedIcon("essential") == true, "a clickButton icon -> true")

pool[1] = nil; pool[2] = nil
assert(F:PoolHasProtectedIcon("essential") == false, "cleared pool -> false")

print("OK: cdm_icon_factory_pool_has_protected_test")
