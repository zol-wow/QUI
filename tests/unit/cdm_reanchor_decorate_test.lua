-- tests/unit/cdm_reanchor_decorate_test.lua
-- Run: lua tests/unit/cdm_reanchor_decorate_test.lua
local ns = {}
local loadChunk = dofile("tests/helpers/load_cdm_consolidated_chunk.lua")
loadChunk("QUI_CDM/cdm/cdm_reanchor_decorate.lua", "cdm_reanchor_decorate.lua")("QUI", ns)
local D = assert(ns.CDMReanchorDecorate, "CDMReanchorDecorate should be exported")
assert(type(D.New) == "function", "New is a function")
-- Named-region list is trimmed to the regions that actually exist in the 12.x
-- CooldownViewer item templates. The anonymous IconOverlay/OOR atlas + the
-- rounding mask are handled by CDMIcons.NeutralizeBlizzardItemChrome, not here.
-- SpellActivationAlert (Task C / G6) is a belt-and-suspenders first-pass hide;
-- the load-bearing re-hide rides the ActionButtonSpellAlertManager ShowAlert hook
-- (the alert is lazily re-created + re-shown on every proc).
assert(#D.HIDDEN_REGIONS == 3, "hidden-region list trimmed to the real named regions")
do
    local names = {}
    for _, n in ipairs(D.HIDDEN_REGIONS) do names[n] = true end
    assert(names.DebuffBorder and names.CooldownFlash, "DebuffBorder + CooldownFlash listed")
    assert(names.SpellActivationAlert, "SpellActivationAlert listed (G6 first-pass hide)")
    assert(not names.Border and not names.IconShadow
        and not names.Shadow, "stale non-existent region guesses removed")
end

local hidden, chromeCalls = {}, {}
local inst = D.New({
    hideRegion = function(frame, name) hidden[#hidden+1] = { frame = frame, name = name } end,
    applyChrome = function(frame, rc, firstChrome)
        chromeCalls[#chromeCalls+1] = { frame = frame, rc = rc, firstChrome = firstChrome }
    end,
})

local frame = {}
local rc1 = { row = 1 }
local first = inst:Decorate(frame, rc1)
assert(first == true, "first decorate returns true")
assert(inst:IsDecorated(frame) == true, "frame marked decorated")
assert(next(frame) == nil, "decorate writes NO keys onto the Blizzard frame")
assert(#hidden == #D.HIDDEN_REGIONS, "every region hidden once")
local sawDebuff, sawCooldownNotHidden = false, true
for _, h in ipairs(hidden) do
    if h.name == "DebuffBorder" then sawDebuff = true end
    if h.name == "Cooldown" then sawCooldownNotHidden = false end
end
assert(sawDebuff, "DebuffBorder hidden")
assert(sawCooldownNotHidden, "native Cooldown is NEVER hidden (swipe/count kept)")
assert(#chromeCalls == 1 and chromeCalls[1].rc == rc1, "chrome applied with rowConfig on first decorate")
assert(chromeCalls[1].firstChrome == true, "first decorate may write one-time native chrome")

-- second call: idempotent -- no re-hide, chrome refreshed (rowConfig can change)
local rc2 = { row = 2 }
local second = inst:Decorate(frame, rc2)
assert(second == false, "second decorate returns false (already decorated)")
assert(#hidden == #D.HIDDEN_REGIONS, "regions not re-hidden on second decorate")
assert(#chromeCalls == 2 and chromeCalls[2].rc == rc2, "chrome re-applied with new rowConfig")
assert(chromeCalls[2].firstChrome == false, "repeat decorate must refresh own chrome without native cooldown rewrites")
-- no deps -> no crash
local bare = D.New()
assert(bare:Decorate({}) == true, "bare instance decorates without injected fns")

-- Decorate must NOT call deps.lift even when one is injected (lift dep removed Task 1)
do
    local liftCalls = {}
    local probe = D.New({
        lift        = function(f) liftCalls[#liftCalls+1] = f end,
        hideRegion  = function() end,
        applyChrome = function() end,
    })
    local pframe = {}
    probe:Decorate(pframe, {})
    probe:Decorate(pframe, {}) -- second call (was where lift re-fired every time)
    assert(#liftCalls == 0, "Decorate must not call deps.lift (lift dep removed)")
end

print("OK: cdm_reanchor_decorate_test")
