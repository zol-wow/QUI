-- tests/unit/aura_skin_enchant_cancel_test.lua
-- Run: lua tests/unit/aura_skin_enchant_cancel_test.lua
--
-- Guards Task 12: ConfigureEnchantments must re-assert SetCancelAuraButtons
-- on registry-tracked enchant frames every pass (68824 native click-to-cancel
-- parity with aura buttons), and the stale pre-68824 "no-op" comments in
-- buffborders.lua must be updated to reflect that.
local function readAll(path)
    local f = assert(io.open(path, "rb"))
    local data = f:read("*a"); f:close()
    return (data:gsub("\r\n", "\n"))
end

local skin = readAll("core/aura_skin.lua")

-- Isolate ONLY the ConfigureEnchantments function body. A lazy `.-\nend`
-- match stops at the FIRST literal "\nend" it finds. That happens to land
-- on the function's own (column-0) closing "end" today because every
-- nested if/for inside the function closes on an INDENTED "end" (no
-- newline-then-"end" with zero intervening whitespace) — but that is an
-- indentation-style coincidence, not a guarantee, and this test must not
-- silently start passing (or failing) for the wrong reason if the body is
-- ever reformatted. Anchor to the function's unique trailing statement
-- pair ("    return true\nend") instead of a bare "\nend" so the captured
-- span is provably the whole function, not a truncated prefix.
local fn = skin:match("function AuraSkin%.ConfigureEnchantments.-\n    return true\nend")
assert(fn, "ConfigureEnchantments not found (or isolation anchor stale)")

-- Prove the anchor is load-bearing rather than decorative: the function
-- must contain at least one INDENTED nested "end" (if/for close) so a
-- naive `.-\nend` match is only equivalent to the anchored one by the
-- indentation coincidence noted above, not by construction.
local nestedEnds = 0
for _ in fn:gmatch("\n%s+end\n") do
    nestedEnds = nestedEnds + 1
end
assert(nestedEnds >= 1,
    "expected indented nested-block ends inside ConfigureEnchantments; " ..
    "isolation-robustness assumption no longer holds, re-check the anchor")

assert(fn:find("SetCancelAuraButtons", 1, true),
    "ConfigureEnchantments must re-assert cancel clicks on enchant frames")
-- The re-assert walks the registry directly (enchant frames are never aura
-- group members), not EachTrackedButton.
assert(fn:find("container._quiButtons", 1, true),
    "ConfigureEnchantments cancel re-assert must use the _quiButtons registry")

-- 68675: button writes hard-error on restricted children while auras are
-- secret (Configure/Restyle both gate on this) — the cancel re-assert loop
-- must be gated too, and the gate must sit BEFORE the loop, not after.
local gatePos = fn:find("if not AurasAreSecret%(%) then")
assert(gatePos, "ConfigureEnchantments cancel re-assert must gate on AurasAreSecret()")
local loopPos = fn:find("container%._quiButtons")
assert(loopPos, "cancel re-assert registry read not found")
assert(gatePos < loopPos,
    "AurasAreSecret() gate must precede the _quiButtons re-assert loop")

local bb = readAll("QUI_ActionBars/actionbars/buffborders.lua")
assert(not bb:find("no%-ops for enchants"),
    "stale enchant-cancel no-op comments must be updated for 68824")

print("OK aura_skin_enchant_cancel_test")
