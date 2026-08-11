-- tests/unit/safecall_swallow_t1f_test.lua
-- Source-text contract pins for Task 1f: 10 swallow-pcall sites converted to
-- ns.SafeCall (policy-classified) across QUI_Chat/chat/editbox_history.lua,
-- QUI_Chat/chat/settings/chat_frame1_provider.lua, QUI_Debug/perftest.lua,
-- QUI_Debug/cdm_debug.lua, QUI_Debug/memaudit.lua,
-- modules/datatexts/datatexts.lua,
-- QUI_GroupFrames/groupframes/groupframes_missing_raid_buffs.lua and
-- modules/trackers/preytracker.lua. Pins the converted shape present, the
-- old bare-pcall shape absent (exact strings), the loop-structure pins at
-- sites 3 and 9, and the exact policy strings used at each site.
-- Run: lua5.1 tests/unit/safecall_swallow_t1f_test.lua
local function readAll(path)
    local f = assert(io.open(path, "rb"))
    local d = f:read("*a"); f:close()
    return (d:gsub("\r\n", "\n"))
end

local fails = 0
local function check(name, ok)
    if ok then print("  ok  " .. name)
    else fails = fails + 1; print("FAIL  " .. name) end
end

---------------------------------------------------------------------------
-- File 1: QUI_Chat/chat/editbox_history.lua
---------------------------------------------------------------------------
local eh = readAll("QUI_Chat/chat/editbox_history.lua")

-- Site 1: RegisterPreSendCallback, per-outgoing-message capture.
check('site1: ns.SafeCall("bulkhead", captureSent, editBox)',
    eh:find('ns.SafeCall("bulkhead", captureSent, editBox)', 1, true) ~= nil)
check("site1: old bare pcall(captureSent, editBox) gone",
    eh:find("pcall(captureSent, editBox)", 1, true) == nil)

-- Site 2: AddHistoryLine post-hook, slash-command capture.
check('site2: ns.SafeCall("bulkhead", captureSlashCommand, self, text)',
    eh:find('ns.SafeCall("bulkhead", captureSlashCommand, self, text)', 1, true) ~= nil)
check("site2: old bare pcall(captureSlashCommand, self, text) gone",
    eh:find("pcall(captureSlashCommand, self, text)", 1, true) == nil)

---------------------------------------------------------------------------
-- File 2: QUI_Chat/chat/settings/chat_frame1_provider.lua
---------------------------------------------------------------------------
local cp = readAll("QUI_Chat/chat/settings/chat_frame1_provider.lua")

-- Site 3: custom-tab selector dropdown onChange, refreshList loop.
check('site3: ns.SafeCall("bulkhead", refreshList[i])',
    cp:find('ns.SafeCall("bulkhead", refreshList[i])', 1, true) ~= nil)
check("site3: old bare pcall(refreshList[i]) gone",
    cp:find("pcall(refreshList[i])", 1, true) == nil)
check("site3: loop structure unchanged (for i = 1, #refreshList do)",
    cp:find("for i = 1, #refreshList do\n                        ns.SafeCall(\"bulkhead\", refreshList[i])\n                    end", 1, true) ~= nil)

---------------------------------------------------------------------------
-- File 3: QUI_Debug/perftest.lua
---------------------------------------------------------------------------
local pt = readAll("QUI_Debug/perftest.lua")

-- Site 4: ApplyAndRefresh, dev-tool cold path. Closure kept as-is; existence
-- guard (GFA and GFA.RefreshAll) already present via ns.QUI_GroupFrameAuras,
-- not a raw _G lookup, so no guard change needed.
check('site4: ns.SafeCall("bulkhead", function() GFA:RefreshAll() end)',
    pt:find('ns.SafeCall("bulkhead", function() GFA:RefreshAll() end)', 1, true) ~= nil)
check("site4: old bare pcall(function() GFA:RefreshAll() end) gone",
    pt:find("pcall(function() GFA:RefreshAll() end)", 1, true) == nil)
check("site4: existence guard preserved (if GFA and GFA.RefreshAll then)",
    pt:find("if GFA and GFA.RefreshAll then ns.SafeCall(", 1, true) ~= nil)

---------------------------------------------------------------------------
-- File 4: QUI_Debug/cdm_debug.lua
---------------------------------------------------------------------------
local cd = readAll("QUI_Debug/cdm_debug.lua")

-- Site 5: CDMDebugCollectCurrentSpecCDMSpells, composer fallback branch.
-- "report" — debug tooling, our own composer, everything loud.
check('site5: ns.SafeCall("report", composer.CollectKnownCDMSpellIDs, knownSpells)',
    cd:find('ns.SafeCall("report", composer.CollectKnownCDMSpellIDs, knownSpells)', 1, true) ~= nil)
check("site5: old bare pcall(composer.CollectKnownCDMSpellIDs, knownSpells) gone",
    cd:find("pcall(composer.CollectKnownCDMSpellIDs, knownSpells)", 1, true) == nil)
check("site5: existence guard preserved (composer and type(...) == \"function\")",
    cd:find('if composer and type(composer.CollectKnownCDMSpellIDs) == "function" then', 1, true) ~= nil)

---------------------------------------------------------------------------
-- File 5: QUI_Debug/memaudit.lua
---------------------------------------------------------------------------
local ma = readAll("QUI_Debug/memaudit.lua")

-- Site 6: HandleExperiment "reset" loop. Straight wrapper swap (matches the
-- brief's default recipe) rather than mirroring SetExperimentState's (:764)
-- bespoke per-item print — mirroring would add per-item output, which is a
-- behavior change beyond error disposition; control flow here stays
-- byte-identical and failures now surface via the "report" policy's own
-- loud/deduped reporting instead of silent discard.
check('site6: ns.SafeCall("report", exps[i].setEnabled, true)',
    ma:find('ns.SafeCall("report", exps[i].setEnabled, true)', 1, true) ~= nil)
check("site6: old bare pcall(exps[i].setEnabled, true) gone",
    ma:find("pcall(exps[i].setEnabled, true)", 1, true) == nil)
check("site6: sibling SetExperimentState (:764 shape) untouched (bespoke print retained)",
    ma:find('local ok, err = pcall(exp.setEnabled, on)', 1, true) ~= nil)

---------------------------------------------------------------------------
-- File 6: modules/datatexts/datatexts.lua
---------------------------------------------------------------------------
local dt = readAll("modules/datatexts/datatexts.lua")

-- Site 7: DetachFromSlot, instance.def.OnDisable.
check('site7: ns.SafeCall("bulkhead", instance.def.OnDisable, instance.frame)',
    dt:find('ns.SafeCall("bulkhead", instance.def.OnDisable, instance.frame)', 1, true) ~= nil)
check("site7: old bare pcall(instance.def.OnDisable, instance.frame) gone",
    dt:find("pcall(instance.def.OnDisable, instance.frame)", 1, true) == nil)

-- Site 8: UpdateAll loop, active.instance.Update — no self/args, matching
-- the file's other bare Update() call shapes (e.g. popup.owner.Update()).
check('site8: ns.SafeCall("bulkhead", active.instance.Update)',
    dt:find('ns.SafeCall("bulkhead", active.instance.Update)', 1, true) ~= nil)
check("site8: old bare pcall(active.instance.Update) gone",
    dt:find("pcall(active.instance.Update)", 1, true) == nil)
check("site8: call shape preserved verbatim (no self, no extra args)",
    dt:find("ns.SafeCall(\"bulkhead\", active.instance.Update)\n        end", 1, true) ~= nil)

---------------------------------------------------------------------------
-- File 7: QUI_GroupFrames/groupframes/groupframes_missing_raid_buffs.lua
---------------------------------------------------------------------------
local mrb = readAll("QUI_GroupFrames/groupframes/groupframes_missing_raid_buffs.lua")

-- Site 9: HasActiveElements predicate loop — result feeds the any-active
-- decision; SafeCall returns false (no 2nd value) on failure, same
-- ok-false-short-circuits-active behavior as the old pcall swallow.
check('site9: ns.SafeCall("bulkhead", activePredicates[i])',
    mrb:find('ns.SafeCall("bulkhead", activePredicates[i])', 1, true) ~= nil)
check("site9: old bare pcall(activePredicates[i]) gone",
    mrb:find("pcall(activePredicates[i])", 1, true) == nil)
check("site9: loop + result-use structure unchanged",
    mrb:find('for i = 1, #activePredicates do\n        local ok, active = ns.SafeCall("bulkhead", activePredicates[i])\n        if ok and active then', 1, true) ~= nil)

---------------------------------------------------------------------------
-- File 8: modules/trackers/preytracker.lua
---------------------------------------------------------------------------
local pty = readAll("modules/trackers/preytracker.lua")

-- Site 10: EnsureWidgetSuppressionHook, OnShow re-suppression. Blizzard
-- widget-frame suppression can legitimately throw forbidden/lockdown, so
-- best-effort-style; closure kept as-is (wrapper swap only).
check('site10: ns.SafeCall("best-effort-style", function()',
    pty:find('ns.SafeCall("best-effort-style", function()', 1, true) ~= nil)
check("site10: old bare pcall(function() ... ApplyWidgetFrameSuppression ... end) gone",
    pty:find('pcall(function()\n            if not State.widgetSuppressed then return end', 1, true) == nil)
check("site10: closure body preserved verbatim (widgetSuppressed guard + settings gate)",
    pty:find('ns.SafeCall("best-effort-style", function()\n            if not State.widgetSuppressed then return end\n            local settings = GetSettings()\n            if settings and settings.replaceDefaultIndicator and settings.enabled then\n                ApplyWidgetFrameSuppression(self, true)\n            end\n        end)', 1, true) ~= nil)

if fails > 0 then error(fails .. " failure(s) in safecall_swallow_t1f_test") end
print("OK: safecall_swallow_t1f_test (all checks passed)")
