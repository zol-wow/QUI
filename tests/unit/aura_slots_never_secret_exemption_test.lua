-- tests/unit/aura_slots_never_secret_exemption_test.lua
-- Task 11: never-secret slot park exemption. 68824's AuraContainerUtil
-- exempts spells whose C_Secrets.GetSpellAuraSecrecy() == Enum.SecrecyLevel.
-- NeverSecret from the identity-filter restriction (vendored proof:
-- tests/framexml/.../Blizzard_AuraContainer/Blizzard_AuraContainerUtil.lua:
-- 23-24), so parking those slots whenever a container's parkAll fires is
-- over-conservative. core/aura_slots.lua's S.Sync must make the per-slot
-- park decision `parkAll and not SpellNeverSecret(spellID)`.
--
-- Part A (brief floor): source-text assertions — verbatim from
-- .superpowers/sdd/task-11-brief.md. Vacuous to a bug where SpellNeverSecret
-- exists textually but isn't actually wired into the park decision, or is
-- wired into only one of the two branches. Part B is a BEHAVIORAL harness
-- (mirrors tests/unit/aura_slots_layout_test.lua's established
-- MakeContainer/MakeFrame stub pattern, reusing its Test I parkAll setup)
-- that drives S.Sync end to end and inspects the actual filters/parked
-- flags landed on each slot.
-- Run: lua tests/unit/aura_slots_never_secret_exemption_test.lua

local fails = 0
local function check(name, ok, detail)
    if ok then print("  ok  " .. name)
    else fails = fails + 1; print("FAIL  " .. name .. (detail and ("  " .. detail) or "")) end
end

----------------------------------------------------------------------------
-- Part A: brief's source-text floor (verbatim from task-11-brief.md).
----------------------------------------------------------------------------
local function readAll(path)
    local f = assert(io.open(path, "rb"))
    local data = f:read("*a"); f:close()
    return (data:gsub("\r\n", "\n"))
end
local src = readAll("core/aura_slots.lua")
assert(src:find("GetSpellAuraSecrecy", 1, true),
    "Sync must consult C_Secrets.GetSpellAuraSecrecy for park exemption")
assert(src:find("SpellNeverSecret", 1, true), "helper SpellNeverSecret required")
assert(src:find("parkAll and not SpellNeverSecret", 1, true),
    "park decision must be per-slot: parkAll and not SpellNeverSecret(spellID)")
print("OK aura_slots_never_secret_exemption_test (source-text floor)")

----------------------------------------------------------------------------
-- Part B: behavioral harness. Loads a real core/ ns slice (tools/
-- _addon_env.lua LoadCore) and drives the real S.Sync against fake
-- container/frame stubs — the same boundary aura_slots_layout_test.lua
-- draws (forbidden objects can't run headless).
----------------------------------------------------------------------------
_G.InCombatLockdown = function() return false end

local env = dofile("tools/_addon_env.lua")
local ns = env.LoadCore()  -- real ns.AuraGlue.ElementProfile + ns.AuraElements

ns.Addon = ns.Addon or {}
ns.Addon.AuraSkin = { WireButton = function() end }

local S = assert(loadfile("core/aura_slots.lua"))("QUI", ns)

local function MakeFrame()
    return {
        SetSize = function() end,
        ClearAllPoints = function() end,
        SetPoint = function() end,
        Icon = { SetAlpha = function() end },
    }
end

local function MakeContainer()
    local c = { _filterCalls = {}, _stringCalls = {}, _createdKeys = {}, _birthFilters = {} }
    c.SetAuraSlotFilterString = function(self, key, base) c._stringCalls[key] = base end
    c.SetAuraSlotCandidateFilters = function(self, key, filters) c._filterCalls[key] = filters end
    c.AddAuraSlot = function(self, key, base, opts)
        c._createdKeys[#c._createdKeys + 1] = key
        c._birthFilters[key] = opts and opts.candidateFilters
        local frame = MakeFrame()
        if opts and type(opts.initializeFrame) == "function" then
            opts.initializeFrame(frame)
        end
        return frame
    end
    return c
end

-- parkAll=true setup: mirrors aura_slots_layout_test.lua Test I — a
-- party/raid HELPFUL container whose LiveAssistProbe is FALSE (identity
-- filters unenforceable for this unit right now), which is exactly the
-- quadrant the engine's NeverSecret exemption (Blizzard_AuraContainerUtil.
-- CanApplyIdentityCandidateFilters) is meant to unlock per-spell.
local function SetLiveAssistProbe(assistable)
    _G.UnitIsConnected = function() return assistable end
    _G.UnitIsDeadOrGhost = function() return false end
    _G.UnitCanAssist = function() return true end
    _G.UnitIsVisible = function() return true end
    _G.UnitPhaseReason = function() return nil end
end
local function ClearLiveAssistProbe()
    _G.UnitIsConnected = nil
    _G.UnitIsDeadOrGhost = nil
    _G.UnitCanAssist = nil
    _G.UnitIsVisible = nil
    _G.UnitPhaseReason = nil
end

----------------------------------------------------------------------------
-- Test 1: C_Secrets.GetSpellAuraSecrecy + Enum.SecrecyLevel present. Spell
-- list { 801 (AlwaysSecret), 802 (NeverSecret), 803 (ContextuallySecret) }
-- under parkAll=true. Slot 2 (802) must get REAL per-spell filters and land
-- unparked; slots 1 and 3 must get the PARK_FILTER recipe and land parked.
----------------------------------------------------------------------------
do
    _G.Enum = _G.Enum or {}
    _G.Enum.SecrecyLevel = { NeverSecret = 0, AlwaysSecret = 1, ContextuallySecret = 2 }
    local secrecyBySpell = { [801] = _G.Enum.SecrecyLevel.AlwaysSecret,
        [802] = _G.Enum.SecrecyLevel.NeverSecret,
        [803] = _G.Enum.SecrecyLevel.ContextuallySecret }
    _G.C_Secrets = {
        GetSpellAuraSecrecy = function(spellID) return secrecyBySpell[spellID] end,
    }
    SetLiveAssistProbe(false)

    local element = {
        spells = { 801, 802, 803 },
        enabled = true,
        auraType = "HELPFUL",
        anchor = "TOPLEFT",
        growDirection = "RIGHT",
    }
    local container = MakeContainer()
    container.GetUnit = function() return "party1" end

    local complete = S.Sync(container, element, true)
    check("present: Sync completes (OOC birth)", complete == true)

    local pool = container._quiSlots
    check("present: 3 shells created", pool and pool[3] ~= nil)

    check("present: slot 1 (AlwaysSecret) PARKED", pool[1] and pool[1].parked == true)
    check("present: slot 2 (NeverSecret) NOT parked", pool[2] and pool[2].parked == false)
    check("present: slot 3 (ContextuallySecret) PARKED", pool[3] and pool[3].parked == true)

    check("present: slot 1 birth filter is the park recipe",
        container._birthFilters["t1"] and container._birthFilters["t1"].maxDuration == 0)
    check("present: slot 2 birth filter is a REAL per-spell filter (not parked)",
        container._birthFilters["t2"]
        and container._birthFilters["t2"].maxDuration == nil
        and container._birthFilters["t2"].includeSpellIDs
        and container._birthFilters["t2"].includeSpellIDs[802] == true)
    check("present: slot 3 birth filter is the park recipe",
        container._birthFilters["t3"] and container._birthFilters["t3"].maxDuration == 0)

    ClearLiveAssistProbe()
    _G.C_Secrets = nil
    _G.Enum.SecrecyLevel = nil
end

----------------------------------------------------------------------------
-- Test 2: C_Secrets entirely absent (pre-68824 client) — SpellNeverSecret
-- must return false unconditionally, so parkThis collapses back to parkAll
-- for every slot: ALL park, identical to pre-task behavior.
----------------------------------------------------------------------------
do
    _G.C_Secrets = nil
    SetLiveAssistProbe(false)

    local element = {
        spells = { 901, 902, 903 },
        enabled = true,
        auraType = "HELPFUL",
        anchor = "TOPLEFT",
        growDirection = "RIGHT",
    }
    local container = MakeContainer()
    container.GetUnit = function() return "party1" end

    local complete = S.Sync(container, element, true)
    check("absent: Sync completes (OOC birth)", complete == true)

    local pool = container._quiSlots
    check("absent: 3 shells created", pool and pool[3] ~= nil)
    check("absent: slot 1 PARKED (pre-PTR parity)", pool[1] and pool[1].parked == true)
    check("absent: slot 2 PARKED (pre-PTR parity)", pool[2] and pool[2].parked == true)
    check("absent: slot 3 PARKED (pre-PTR parity)", pool[3] and pool[3].parked == true)
    for i = 1, 3 do
        local key = "t" .. i
        check("absent: " .. key .. " birth filter is the park recipe",
            container._birthFilters[key] and container._birthFilters[key].maxDuration == 0)
    end

    ClearLiveAssistProbe()
end

if fails > 0 then error(fails .. " failure(s) in aura_slots_never_secret_exemption_test") end
print("OK: aura_slots_never_secret_exemption_test (all checks passed)")
