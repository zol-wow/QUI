-- tests/unit/groupframes_mrb_cdm_merge_test.lua
-- MRB:RebuildRaidBuffs merges Blizzard CDM Group Buff items into MRB.RaidBuffs
-- (built-in 6 + CDM shown, deduped by spellID, hidden excluded), idempotently.
-- Run: lua tests/unit/groupframes_mrb_cdm_merge_test.lua

_G.issecretvalue = function() return false end
function CreateFrame() return { RegisterEvent = function() end, RegisterUnitEvent = function() end, SetScript = function() end } end
_G.C_Timer = { After = function() end }
_G.wipe = function(t) for k in pairs(t) do t[k] = nil end end

local ns = {}
assert(loadfile("QUI_GroupFrames/groupframes/groupframes_missing_raid_buffs.lua"))("QUI", ns)
local MRB = assert(ns.QUI_GroupFrameMissingRaidBuffs, "MRB not exported")
assert(type(MRB.RebuildRaidBuffs) == "function", "RebuildRaidBuffs must exist")

-- CDM stubs set AFTER load (RebuildRaidBuffs reads _G at call time).
_G.C_CooldownViewer = {
    GetGroupBuffItems = function()
        return {
            { spellID = 100,  name = "Test Buff A" },
            { spellID = 1459, name = "Arcane Intellect (dup)" }, -- already a built-in id
            { spellID = 200,  name = "Hidden Buff B" },          -- hidden
        }
    end,
}
_G.C_UnitAuras = { GetHiddenGroupBuffs = function() return { 200 } end }

MRB:RebuildRaidBuffs()

local byKey = {}
for _, e in ipairs(MRB.RaidBuffs) do byKey[e.key] = e end

assert(byKey.intellect, "built-in intellect retained")
assert(byKey.bronze, "built-in bronze retained")
assert(byKey["cdm:100"], "CDM spellID 100 merged")
assert(byKey["cdm:100"].label == "Test Buff A", "CDM label carried")
assert(byKey["cdm:100"].ids[1] == 100 and #byKey["cdm:100"].ids == 1, "CDM ids = {spellID}")
assert(byKey["cdm:100"].providerClass == nil, "CDM providerClass nil")
assert(byKey["cdm:100"].iconSpellID == 100, "CDM iconSpellID = spellID")
assert(byKey["cdm:100"].source == "cdm", "CDM entry tagged source=cdm")
assert(byKey["cdm:1459"] == nil, "1459 deduped (already in built-in intellect ids)")
assert(byKey["cdm:200"] == nil, "200 excluded (hidden)")

-- HideByDefault precedence (mirrors Blizzard GroupBuffFilter.lua): the saved
-- layout's hidden list is authoritative when readable — a user-un-hidden
-- flagged buff must merge; the flag is only the no-layout fallback.
_G.Enum = { GroupBuffItemFlags = { HideByDefault = 1 }, CDMLayoutMode = { AccessOnly = 1 } }
-- plain lua5.1 has no `bit` library (the game client does); the module reads
-- _G.bit at call time, so a stub is enough to exercise the flags path.
_G.bit = { band = function(a, b)
    local r, p = 0, 1
    while a > 0 and b > 0 do
        if a % 2 == 1 and b % 2 == 1 then r = r + p end
        a = math.floor(a / 2); b = math.floor(b / 2); p = p * 2
    end
    return r
end }
_G.C_CooldownViewer = {
    GetGroupBuffItems = function()
        return {
            { spellID = 300, name = "Flagged, user-unhid", flags = 1 },
            { spellID = 400, name = "Flagged, layout-hidden", flags = 1 },
        }
    end,
}
_G.C_UnitAuras = { GetHiddenGroupBuffs = function() return { 400 } end }

-- No layout readable -> flags enforced: both flagged buffs skipped.
MRB:RebuildRaidBuffs()
local byKey3 = {}
for _, e in ipairs(MRB.RaidBuffs) do byKey3[e.key] = e end
assert(byKey3["cdm:300"] == nil, "no layout: flagged buff skipped (fallback)")
assert(byKey3["cdm:400"] == nil, "no layout: hidden buff skipped")

-- Layout readable -> its hidden list wins: 300 (un-hidden by user) merges,
-- 400 (still in the layout's hidden list) stays out.
local layout = {}
_G.CooldownViewerSettings = {
    GetLayoutManager = function()
        return { GetActiveLayout = function() return layout end }
    end,
}
_G.CooldownManagerLayout_GetHiddenGroupBuffs = function(l)
    assert(l == layout, "getter receives the active layout")
    return { 400 }
end
MRB:RebuildRaidBuffs()
local byKey4 = {}
for _, e in ipairs(MRB.RaidBuffs) do byKey4[e.key] = e end
assert(byKey4["cdm:300"], "layout read: user-un-hidden flagged buff merges")
assert(byKey4["cdm:400"] == nil, "layout read: layout-hidden buff stays excluded")

-- Adversarial (2026-07 re-review): a stale C-side sync copy
-- (C_UnitAuras.GetHiddenGroupBuffs — the sync TARGET Blizzard writes but
-- never reads back) still lists a buff the user just un-hid from the layout.
-- The layout list is authoritative; the stale copy must NOT re-hide 300.
_G.C_UnitAuras = { GetHiddenGroupBuffs = function() return { 300, 400 } end }
MRB:RebuildRaidBuffs()
local byKey5 = {}
for _, e in ipairs(MRB.RaidBuffs) do byKey5[e.key] = e end
assert(byKey5["cdm:300"], "stale C-side copy does not re-hide a layout-un-hidden buff")
assert(byKey5["cdm:400"] == nil, "layout-hidden buff still excluded with stale copy present")
_G.C_UnitAuras = { GetHiddenGroupBuffs = function() return { 400 } end }
_G.CooldownViewerSettings = nil
_G.CooldownManagerLayout_GetHiddenGroupBuffs = nil

-- Idempotent + guard: APIs absent -> CDM entries dropped, built-in retained.
_G.C_CooldownViewer = nil
MRB:RebuildRaidBuffs()
local byKey2 = {}
for _, e in ipairs(MRB.RaidBuffs) do byKey2[e.key] = e end
assert(byKey2["cdm:100"] == nil, "guard/idempotent: CDM entries removed when API absent")
assert(byKey2.intellect, "built-in retained after guard rebuild")

print("OK groupframes_mrb_cdm_merge_test")
