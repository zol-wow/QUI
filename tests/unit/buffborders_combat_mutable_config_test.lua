-- tests/unit/buffborders_combat_mutable_config_test.lua
-- Run: lua tests/unit/buffborders_combat_mutable_config_test.lua
--
-- 12.1 PTR contract: CREATING a forbidden CustomAuraContainer/AuraButton in
-- combat is restricted (crashes the client today), but MUTATING pre-created
-- ones (SetPoint / SetSize / groups / enable) is legal in combat. The old
-- ApplyOrDefer deferred ALL config to PLAYER_REGEN_ENABLED; the split applies
-- the combat-legal subset immediately and still queues the full pass (any
-- missing creation is OOC-only), so a wrong PTR assumption self-heals at
-- regen.

local function readAll(path)
    local file = assert(io.open(path, "rb"))
    local data = file:read("*a")
    file:close()
    return (data:gsub("\r\n", "\n"))
end

local src = readAll("QUI_ActionBars/actionbars/buffborders.lua")

-- Slice helper: function start → next line-leading `end`.
local function slice(marker)
    local startPos = src:find(marker, 1, true)
    assert(startPos, "missing: " .. marker)
    local endPos = src:find("\nend", startPos, true)
    assert(endPos, "unterminated function at: " .. marker)
    return src:sub(startPos, endPos)
end

-- The shared pass must exist and gate creation-class work on allowCreate.
local pass = slice("local function ApplyConfigPass(allowCreate)")
local gatePos = pass:find("if allowCreate then", 1, true)
assert(gatePos, "ApplyConfigPass must gate OOC-only work on allowCreate")

-- The private-aura anchor subsystem is fully removed (12.1 AuraContainers
-- render private auras natively) — lock this in so it cannot creep back.
assert(not src:find("PrivateAura", 1, true) and not src:find("QUI_PA_", 1, true),
    "buffborders.lua must not reintroduce the private-aura anchor subsystem")

-- Per-host element pass (ApplyMoverElements): container CREATION is gated on
-- allowCreate AND out-of-combat (forbidden object); the combat path only mutates
-- pre-created containers, reconciling groups through the SHARED
-- AuraGlue.RunConfigPass (which owns the pcall(AuraSkin.Configure) + Restyle
-- fallback internally, so buffborders.lua no longer names them directly).
local zone = slice("local function ApplyMoverElements(")
assert(zone:find("allowCreate and not InCombatLockdown()", 1, true),
    "container creation must be gated on allowCreate AND out-of-combat")
assert(zone:find("CreateFrame(\"AuraContainer\"", 1, true),
    "ApplyMoverElements creates the forbidden AuraContainer under the OOC gate")
assert(zone:find("G.RunConfigPass(", 1, true),
    "the pass must reconcile groups via the shared AuraGlue.RunConfigPass (Configure OOC / Restyle combat)")
assert(zone:find("S.Park(", 1, true),
    "BB is strips-only: the pass must Park (never Sync) each container's slot pool")
-- "AuraSkin.Configure(" (the direct-call form) must not appear — but
-- AuraSkin.ConfigureEnchantments(...) (a DIFFERENT function, folding temp
-- weapon enchants into the strip-1 container) legitimately does, so the
-- needle must not be a bare prefix of that name.
assert(not zone:find("AuraSkin.Configure(", 1, true),
    "the pass must not call AuraSkin.Configure directly — it goes through AuraGlue.RunConfigPass")

-- ApplyOrDefer: in combat, apply the mutable subset now AND queue the full pass.
local apply = slice("local function ApplyOrDefer()")
assert(apply:find("InCombatLockdown()", 1, true),
    "ApplyOrDefer must still branch on combat lockdown")
assert(apply:find("ApplyMutableConfig()", 1, true),
    "ApplyOrDefer must apply the combat-legal mutation pass immediately in combat")
assert(apply:find("QueueContainerWork()", 1, true),
    "ApplyOrDefer must STILL queue the full pass for PLAYER_REGEN_ENABLED (self-heal)")

-- The combat pass must SafeCall-guard forbidden-container mutation (PTR-observed
-- legality; a restriction error must not abort the rest of the pass).
assert(pass:find('ns.SafeCall("defer-ooc", ApplyMoverElements', 1, true),
    "the mutation pass must SafeCall-guard the per-host container mutation")

-- v50 grow-anchor repoint: the mover's grow corner must derive from the element
-- store (buffAuras/debuffAuras), NOT the pruned flat buff*/debuffGrowLeft/GrowUp
-- keys. Reading the flat keys here would compute the WRONG corner for every
-- default/LEFT-grow profile after v50 prunes them.
local grow = slice("local function UpdateGrowAnchor(faKey)")
assert(not grow:find("GrowLeft", 1, true) and not grow:find("GrowUp", 1, true),
    "UpdateGrowAnchor must not read the pruned flat buff*/debuffGrowLeft/GrowUp keys")
assert(grow:find("buffAuras", 1, true) and grow:find("debuffAuras", 1, true),
    "UpdateGrowAnchor must derive the grow corner from the buffAuras/debuffAuras element store")

print("OK: buffborders_combat_mutable_config_test")
