-- tests/unit/cdm_reanchor_runtime_combat_owned_defer_test.lua
-- Run: lua tests/unit/cdm_reanchor_runtime_combat_owned_defer_test.lua
--
-- Combat-time reanchor refresh must NOT release owned icons that carry a secure
-- clickButton child: Factory:ReleaseIcon -> icon:Hide() on a protected-descendant
-- parent = ADDON_ACTION_BLOCKED (QUICDMIconN:Hide()). The runtime defers the whole
-- pass for such a container while combat-locked, records it in a pending set, and
-- the PLAYER_REGEN_ENABLED drain re-runs it out of combat. Containers with no
-- clickButton owned icons keep refreshing in combat.
local ns = {}
local loadChunk = dofile("tests/helpers/load_cdm_consolidated_chunk.lua")
loadChunk("QUI_CDM/cdm/cdm_reanchor_runtime.lua", "cdm_reanchor_runtime.lua")("QUI", ns)
local R = assert(ns.CDMReanchorRuntime)

local mutate = true            -- env.canMutate() return
local released = {}
local mintN = 0
local mintClickButton = false  -- minted icons get a secure clickButton child?

local wiring = {
    GetViewersForKey = function() return { { v = 1 } } end,
    BuildFrameMapForViewers = function() return {}, {} end,
    MatchCuratedToFrames = function() return {}, {}, {} end,
}
local function newRuntime()
    return R.New({
        bridge = {},
        wiring = wiring,
        canMutate = function() return mutate end,
        getContainer = function() return { c = 1 } end,
        getSettings = function() return {} end,
        getCurated = function() return {} end,
        getAdditional = function() return { { name = "additional" } } end,
        mintOwned = function()
            mintN = mintN + 1
            local icon = { id = mintN }
            if mintClickButton then icon.clickButton = { secure = true } end
            return icon
        end,
        releaseOwned = function(icon) released[#released + 1] = icon end,
    })
end

-- Pass 1 out of combat mints the ledger (nothing to release yet).
mutate, mintClickButton = true, true
local rt = newRuntime()
rt:RefreshContainer("essential")
assert(#released == 0, "first pass releases nothing")

-- Now combat: the ledger's owned icon has a clickButton -> defer the whole pass.
mutate = false
rt:RefreshContainer("essential")
assert(#released == 0, "combat pass must NOT release a clickButton-owning icon")
assert(rt:GetLastDiag("essential").earlyReturn == "combat-protected-owned",
    "deferred pass records the combat-protected-owned diag reason")

-- Drain on combat end re-runs the pass out of combat: release + re-mint happen.
mutate = true
rt:DrainPendingCombatRefresh()
assert(#released == 1, "regen drain releases the deferred pass's owned icon")

-- A second drain is a no-op (pending set cleared).
released = {}
rt:DrainPendingCombatRefresh()
assert(#released == 0, "drain clears the pending set; a re-drain does nothing")

-- Owned icons with NO clickButton keep refreshing in combat (no defer).
mutate, mintClickButton = true, false
local rt2 = newRuntime()
rt2:RefreshContainer("utility")   -- pass 1 mints plain icon
released = {}
mutate = false
rt2:RefreshContainer("utility")   -- combat pass 2
assert(#released == 1, "combat refresh still releases non-clickButton owned icons")
assert(rt2:GetLastDiag("utility").earlyReturn == nil,
    "non-protected container is not deferred in combat")

print("OK: cdm_reanchor_runtime_combat_owned_defer_test")
