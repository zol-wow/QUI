-- tests/unit/buffborders_enchant_leads_grid_test.lua
-- Run: lua tests/unit/buffborders_enchant_leads_grid_test.lua
--
-- Temp weapon enchants used to render on a SEPARATE insecure strip that led
-- the buff row via a hand-rolled liveEnchantCount offset (the enchant count is
-- Lua-visible -- GetWeaponEnchantInfo, item info, not aura data -- while the
-- live aura count is secret, so only the enchant side could drive that
-- offset). PTR4 AddItemEnchantment (placement=BeforeAuraGroups) now folds
-- enchants INSIDE the buff container itself via AuraSkin.ConfigureEnchantments
-- (core/aura_skin.lua): the engine owns their frames, flow position and
-- updates, so the lead-in offset and the separate strip are both gone. This
-- guards the fold-in call site and the resulting simplified shapes of
-- AnchorElementContainer / GridExtent's callers.

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

-- No lead-in state (or the separate strip's own state) survives.
for _, dead in ipairs({ "liveEnchantCount", "tempEnchantFrame", "enchantCachedDuration" }) do
    assert(not src:find(dead, 1, true),
        "must not track " .. dead .. " as a file-local: temp enchants are engine-rendered now")
end

-- AnchorElementContainer is a pure 3-arg pin: no isFirstBuff / enchant xOff.
local anchor = slice("local function AnchorElementContainer(")
assert(anchor:find("local function AnchorElementContainer(container, baseFrame, element)", 1, true),
    "AnchorElementContainer must be the plain 3-arg shape (no isFirstBuff/enchant lead-in)")
assert(not anchor:find("isFirstBuff", 1, true) and not anchor:find("xOff", 1, true),
    "AnchorElementContainer must not carry the enchant lead-in xOff branch")

-- ApplyMoverElements registers the buff host's FIRST container's engine-owned
-- enchants via AuraSkin.ConfigureEnchantments -- gated to isBuff and i == 1 so
-- only strip 1 of the BUFF host ever gets enchants (debuff hosts never do).
local zone = slice("local function ApplyMoverElements(")
assert(zone:find('ns.SafeCall("defer-ooc", AnchorElementContainer, container, pool[1] or moverFrame, element)', 1, true),
    "the container anchor call site must drop the old isFirstBuff 4th argument and SafeCall-dock strips i>1 to strip 1's live container")
assert(zone:find("if isBuff and i == 1 then", 1, true),
    "ApplyMoverElements must gate enchant registration to the buff host's first container")
assert(zone:find('ns.SafeCall("defer-ooc", AuraSkin.ConfigureEnchantments, container, profile)', 1, true),
    "ApplyMoverElements must SafeCall-guard AuraSkin.ConfigureEnchantments (first call creates forbidden frames -> OOC only)")

-- First call is combat-unsafe (frame creation): in combat, if enchants were
-- never registered on this container yet, the pass must mark itself
-- incomplete so the OOC replay queues instead of silently dropping them; a
-- pcall failure or a still-missing _quiEnchantsAdded stamp after the call
-- must ALSO mark incomplete.
assert(zone:find("InCombatLockdown() and not container._quiEnchantsAdded then", 1, true),
    "ApplyMoverElements must gate first-time enchant registration on out-of-combat, queuing a replay otherwise")
assert(zone:find("not okE or not container._quiEnchantsAdded", 1, true),
    "ApplyMoverElements must treat a pcall failure OR a missing _quiEnchantsAdded stamp as incomplete")

-- GridExtent stays pure profile math -- no enchant widening.
local grid = slice("local function GridExtent(")
assert(not grid:lower():find("enchant", 1, true),
    "GridExtent must be pure profile math with no enchant-lead-in widening")

-- ApplyConfigPass no longer widens the buff zone's natural extent by any
-- enchant lead-in and no longer drives a separate enchant refresh -- enchant
-- registration now happens per-container inside ApplyMoverElements.
local pass = slice("local function ApplyConfigPass(allowCreate)")
assert(not pass:find("UpdateTempEnchants", 1, true) and not pass:find("RefreshTempEnchants", 1, true),
    "ApplyConfigPass must not call the deleted temp-enchant strip refresh")
assert(pass:find("local bw, bh = GridExtent(buffProfile)\n    buffContainer._naturalW, buffContainer._naturalH = bw, bh", 1, true),
    "the buff zone's natural extent must be GridExtent(buffProfile) alone, with no post-hoc widening")

print("OK: buffborders_enchant_leads_grid_test")
