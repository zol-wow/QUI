-- tests/unit/aura_slots_api_test.lua
-- Source-text contract pins for core/aura_slots.lua (forbidden objects can't
-- run headless). Run: lua5.1 tests/unit/aura_slots_api_test.lua
local function readAll(path)
    local f = assert(io.open(path, "rb"))
    local d = f:read("*a"); f:close()
    return (d:gsub("\r\n", "\n"))
end
local src = readAll("core/aura_slots.lua")
local fails = 0
local function check(name, ok)
    if ok then print("  ok  " .. name)
    else fails = fails + 1; print("FAIL  " .. name) end
end

check("exports S.Sync", src:find("function S.Sync", 1, true) ~= nil)
check("exports S.Park", src:find("function S.Park", 1, true) ~= nil)
check("slot creation via AddAuraSlot", src:find(":AddAuraSlot(", 1, true) ~= nil)
check("NO slot removal API (addon-unremovable; reconcile by rewrite)",
    src:find("UnregisterAuraSlot", 1, true) == nil and src:find("ClearAuraSlots", 1, true) == nil)
check("stale slots reconciled via SetAuraSlotFilterString",
    src:find(":SetAuraSlotFilterString(", 1, true) ~= nil)
check("candidate filters rewritten via SetAuraSlotCandidateFilters",
    src:find(":SetAuraSlotCandidateFilters(", 1, true) ~= nil)
check("park filter is the never-match maxDuration=0 recipe",
    src:find("maxDuration = 0", 1, true) ~= nil)
check("creation gated on InCombatLockdown (AddAuraSlot creates a forbidden frame synchronously)",
    src:find("InCombatLockdown()", 1, true) ~= nil)
check("slot frames wired through AuraSkin.WireButton",
    src:find("AuraSkin.WireButton(", 1, true) ~= nil)
check("inactive icons reuse the active icon crop and border styling",
    src:find("AuraSkin.StyleIconArt(frame, profile)", 1, true) ~= nil)
check("onlyMine routed to isFromPlayerOrPlayerPet",
    src:find("isFromPlayerOrPlayerPet", 1, true) ~= nil)
check("per-spell include map drives the slot filter",
    src:find("includeSpellIDs", 1, true) ~= nil)
check("no Lua reads of aura data (secrets-safe by construction)",
    src:find("GetAuraDataBy", 1, true) == nil and src:find("GetUnitAuras", 1, true) == nil
    and src:find("UnitAura(", 1, true) == nil)
check("bar/linear fill rides the engine's SetDurationBar, never Lua duration math",
    src:find(":SetDurationBar(", 1, true) ~= nil and src:find("GetTime()", 1, true) == nil)
check("icon/square swipe styling routes through the shared helper",
    src:find("ApplyCooldownSwipeStyle", 1, true) ~= nil and src:find("swipeStyle", 1, true) ~= nil)
check("mid-combat linear-fill creation deferred (StatusBar child is OOC-only)",
    src:find("not fill and InCombatLockdown()", 1, true) ~= nil)
check("bar track dimmed behind the fill (depletion must read visually)",
    src:find("trackDim", 1, true) ~= nil)
check("healthTint feeder slots: passive art attached, engine renders it",
    src:find("StyleFeederSlot", 1, true) ~= nil
    and src:find("ns.AuraFeederAttach", 1, true) ~= nil
    and src:find("ns.AuraFeederDetach", 1, true) ~= nil)
-- The engine refuses SetShown() with secret aura presence on buttons carrying
-- script handlers — feeder slots must stay scriptless forever.
check("feeder slots carry NO script handlers (secret SetShown would error)",
    src:find("HookScript", 1, true) == nil
    and src:find("SetScript", 1, true) == nil)
check("feeder retire path clears state when a slot changes display type",
    src:find("RetireFeederSlot", 1, true) ~= nil)
check("feeder element syncs ONE union slot (stacked covers composite darker)",
    src:find("SyncFeederElement", 1, true) ~= nil
    and src:find("FeederSpellMap", 1, true) ~= nil)
check("bar low-time recolor rides the engine refresh window, capability-gated + bind-once",
    src:find("AddPandemicRegion", 1, true) ~= nil
    and src:find("frame.AddPandemicRegion", 1, true) ~= nil)
check("linear fills suppress the cooldown edge + bling overlays",
    src:find("SetDrawEdge(false)", 1, true) ~= nil
    and src:find("SetDrawBling(false)", 1, true) ~= nil)

-- Live-assist gate (party/raid HELPFUL quadrant): the engine's identity
-- filter check is LIVE UnitCanAssist per aura, not token class — a
-- cross-faction/MC/dead/phased member silently loses includeSpellIDs.
check("live assist probe exists for the party/raid HELPFUL quadrant",
    src:find("local function LiveAssistProbe(unit)", 1, true) ~= nil)
check("live probe requires every positive trust signal",
    src:find("UnitIsConnected(unit)", 1, true) ~= nil
    and src:find("UnitIsDeadOrGhost(unit)", 1, true) ~= nil
    and src:find('UnitCanAssist("player", unit)', 1, true) ~= nil
    and src:find("UnitIsVisible(unit)", 1, true) ~= nil
    and src:find("UnitPhaseReason(unit)", 1, true) ~= nil)
check("probe throw fails CLOSED (pcall, park on error/secret)",
    src:find("return ok and trusted == true", 1, true) ~= nil)
check("player/pet exempt by LEXICAL token compare, never a UnitIsUnit call",
    src:find('unit == "player" or unit == "pet"', 1, true) ~= nil
    and src:find("UnitIsUnit(", 1, true) == nil)
check("HELPFUL on assist-class tokens gated by the LIVE probe",
    src:find("local live = LiveAssistProbe(unit)", 1, true) ~= nil
    and src:find("return live, true, live", 1, true) ~= nil)
check("Sync is the WRITER of the applied assist state (never a reader cache)",
    src:find("container._quiAssistApplied = nil", 1, true) ~= nil
    and src:find("container._quiAssistApplied = live", 1, true) ~= nil)
check("Park clears the applied assist record",
    src:find("function S.Park(container)", 1, true) ~= nil
    and select(2, src:gsub("container%._quiAssistApplied = nil", "")) >= 2)

if fails > 0 then error(fails .. " failure(s) in aura_slots_api_test") end
print("OK: aura_slots_api_test (all checks passed)")
