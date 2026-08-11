-- tests/unit/buffborders_live_container_stamps_test.lua
-- Run: lua tests/unit/buffborders_live_container_stamps_test.lua
--
-- ApplyMoverElements pools forbidden AuraContainers by ordinal on the mover
-- and, for strip 1, publishes a paired stamp: moverFrame._quiLiveContainer =
-- container (forward) and container._quiHostMover = moverFrame (back-
-- pointer) -- the central anchoring system anchors THIS container directly
-- and docks the sibling aura host to it (container-first). A freshly-created
-- strip-1 container has never been SetPoint'd; if ApplyConfigPass's tail
-- reapply skipped it because Layout Mode happened to be active with no
-- preview/handle for the host (e.g. the host was disabled at layout-mode
-- open, then re-enabled), the container would render with zero anchor
-- points -- fail-invisible. ApplyMoverElements now reports fresh creation as
-- a second return value so the tail reapply can override the layout-mode
-- gate for that one pass. This guards: the paired stamp, the i>1 anchor
-- gate, the retirement clear, the fresh-creation return, and the
-- ApplyConfigPass tail's fresh-override gate.

local function readAll(path)
    local file = assert(io.open(path, "rb"))
    local data = file:read("*a")
    file:close()
    return (data:gsub("\r\n", "\n"))
end

local src = readAll("QUI_ActionBars/actionbars/buffborders.lua")

-- Slice helper: function start → next line-leading `end` (unindented,
-- matching this file's top-level function-closing convention).
local function slice(marker)
    local startPos = src:find(marker, 1, true)
    assert(startPos, "missing: " .. marker)
    local endPos = src:find("\nend", startPos, true)
    assert(endPos, "unterminated function at: " .. marker)
    return src:sub(startPos, endPos)
end

-- Bounded slice of a NESTED block within `text`: marker start → the closing
-- `end` at the given indent (e.g. 12 spaces for a block nested 3 levels
-- deep). Bounded to `limit` chars so a missing/misindented end can't run the
-- search past the block it's meant to isolate.
local function sliceIndented(text, marker, indent, limit)
    local startPos = text:find(marker, 1, true)
    assert(startPos, "missing: " .. marker)
    local endMarker = "\n" .. string.rep(" ", indent) .. "end"
    local endPos = text:find(endMarker, startPos, true)
    assert(endPos, "unterminated block at: " .. marker)
    assert(endPos - startPos <= (limit or 2000),
        "block at " .. marker .. " ran past the expected bound -- indent/marker mismatch?")
    return text:sub(startPos, endPos)
end

local zone = slice("local function ApplyMoverElements(")

-- (a) The paired stamp lives inside the SAME `if i == 1` block: forward
-- pointer (mover -> live container) and back-pointer (container -> host
-- mover) must not drift apart into separate conditionals.
local stampBlock = sliceIndented(zone, "if i == 1 then", 12, 800)
assert(stampBlock:find("moverFrame._quiLiveContainer = container", 1, true),
    "the i==1 block must publish the forward stamp moverFrame._quiLiveContainer = container")
assert(stampBlock:find("container._quiHostMover = moverFrame", 1, true),
    "the i==1 block must publish the back-pointer container._quiHostMover = moverFrame")

-- (b) AnchorElementContainer only runs for strips AFTER strip 1 (strip 1 is
-- owned by the central anchoring system), docked to strip 1's live
-- container with a cold-start fallback to the mover itself.
assert(zone:find("i > 1 then", 1, true),
    "the per-strip anchor call must be gated to i > 1 (strip 1 is centrally anchored, never self-anchored here)")
assert(zone:find('ns.SafeCall("defer-ooc", AnchorElementContainer, container, pool[1] or moverFrame, element)', 1, true),
    "strips i>1 must dock to pool[1] or moverFrame via SafeCall (forbidden->forbidden relativeTo is a PTR4 in-game unknown)")
assert(zone:find('ns.SafeCall("defer-ooc", AnchorElementContainer, container, moverFrame, element)', 1, true),
    "a rejected forbidden->forbidden dock must fall back to anchoring on the mover")

-- (c) Retiring every strip clears the forward stamp so the central anchoring
-- system never anchors to a hidden container.
assert(zone:find("if #strips == 0 then", 1, true),
    "ApplyMoverElements must branch on #strips == 0 to retire the host")
assert(zone:find("moverFrame._quiLiveContainer = nil", 1, true),
    "ApplyMoverElements must clear moverFrame._quiLiveContainer when #strips == 0")

-- (e) ApplyMoverElements reports fresh creation as a SECOND return value so
-- callers can tell a just-created (never SetPoint'd) container apart from a
-- reused one.
assert(zone:find("local createdFresh = false", 1, true),
    "ApplyMoverElements must track createdFresh across the strip loop")
assert(zone:find("createdFresh = true", 1, true),
    "ApplyMoverElements must flip createdFresh true in the CreateFrame branch")
assert(zone:find("return incomplete, createdFresh", 1, true),
    "ApplyMoverElements must return (incomplete, createdFresh)")

-- (d) ApplyConfigPass's tail reapply calls BOTH named anchors, and its gate
-- overrides the layout-mode skip when either host freshly created a
-- container this pass (a freshly-created strip-1 container has never been
-- SetPoint'd; skipping the reapply would leave it with zero anchor points --
-- fail-invisible -- and the central apply is the only owner of strip-1
-- anchors).
local pass = slice("local function ApplyConfigPass(allowCreate)")
assert(pass:find('_G.QUI_ApplyFrameAnchor("buffFrame")', 1, true),
    "ApplyConfigPass tail must reapply the buffFrame anchor")
assert(pass:find('_G.QUI_ApplyFrameAnchor("debuffFrame")', 1, true),
    "ApplyConfigPass tail must reapply the debuffFrame anchor")
assert(pass:find("fresh1 or fresh2", 1, true),
    "the tail reapply gate must override the layout-mode skip on fresh creation (expected `fresh1 or fresh2` or equivalent)")
assert(pass:find("not Helpers.IsLayoutModeActive()", 1, true),
    "the tail reapply gate must still short-circuit on the plain not-layout-mode check when nothing was freshly created")

print("OK: buffborders_live_container_stamps_test")
