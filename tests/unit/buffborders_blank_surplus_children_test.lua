-- tests/unit/buffborders_blank_surplus_children_test.lua
-- Run: lua tests/unit/buffborders_blank_surplus_children_test.lua
--
-- Regression guard for stale borders on empty buff/debuff slots.
--
-- The secure aura header lays out its children synchronously on UNIT_AURA and
-- HIDES every dead child itself (Blizzard_FrameXML SecureGroupHeaders.lua
-- configureAuras: deadIndex = #auraTable+1 .. -> button:Hide()). QUI's styling
-- is coalesced to the next frame, so during rapid aura turnover (and on pooled
-- child reuse) the header can momentarily show a child that C_UnitAuras has no
-- live aura for. GetUnitAuras returns a dense, never-nil table (UnitAura doc:
-- auras Nilable=false), so a nil slot means that shown child has NO aura.
--
-- The QUI border textures are parented to the child and only vanish when the
-- child frame is hidden -- which is the header's job, not ours (hiding a
-- secure child from insecure code taints/blocks in combat). So QUI must blank
-- its OWN regions (borders/icon/cooldown/stacks) on any shown child it is not
-- painting this pass, or a stale border sits on an apparently-empty slot.

local function readFile(path)
    local fh = assert(io.open(path, "rb"), "failed to open " .. path)
    local text = fh:read("*a")
    fh:close()
    return text
end

local function sliceFunction(source, signature)
    local startPos = source:find(signature, 1, true)
    assert(startPos, signature .. " must exist in buffborders.lua")
    local nextFn = source:find("\nlocal function ", startPos + 1, true)
    return source:sub(startPos, nextFn or #source)
end

local source = readFile("QUI_ActionBars/actionbars/buffborders.lua")

-- A helper must exist to clear QUI-owned visuals on an unpainted shown child.
assert(source:find("local function BlankAuraChild", 1, true),
    "buffborders must have a BlankAuraChild helper to clear stale visuals on "
    .. "shown header children that have no live aura this pass")

-- It must hide all four border edges (the visible artifact the user reports).
local blankBody = sliceFunction(source, "local function BlankAuraChild")
for _, edge in ipairs({ "BorderTop", "BorderBottom", "BorderLeft", "BorderRight" }) do
    assert(blankBody:find(edge .. ":SetShown(false)", 1, true),
        "BlankAuraChild must hide the " .. edge .. " border so empty slots show no border")
end
-- It must also clear the icon texture so no stale icon is left behind.
assert(blankBody:find("SetTexture", 1, true),
    "BlankAuraChild must clear the icon texture on a blanked child")

-- The styling loop must blank shown children it has no aura data for instead
-- of leaving them with stale borders.
local styleBody = sliceFunction(source, "local function StyleHeaderChildren")
assert(styleBody:find("BlankAuraChild", 1, true),
    "StyleHeaderChildren must blank shown header children with no live aura "
    .. "data rather than break and leave stale borders on empty slots")

-- It must NOT hide the secure child frame itself from insecure code (that is
-- the header's responsibility and would taint / be protected in combat).
assert(not styleBody:find("child:Hide()", 1, true),
    "StyleHeaderChildren must not hide secure header children itself -- the "
    .. "header owns child visibility; QUI only clears its own regions")

print("OK: buffborders_blank_surplus_children_test")
