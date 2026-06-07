-- tests/unit/damage_meter_layout_size_section_test.lua
-- Run: lua tests/unit/damage_meter_layout_size_section_test.lua
--
-- Verifies the Layout Mode settings panel for a damage meter window exposes a
-- precise Frame Size section (Width / Height sliders) alongside the existing
-- Position controls, mirroring the chat-frame provider. Source-pattern style to
-- match the rest of the damage_meter unit suite (the module is too heavy to
-- load under headless Lua).

local function readAll(path)
    local f = assert(io.open(path, "rb"))
    local d = f:read("*a"); f:close()
    return d:gsub("\r\n", "\n")
end

local src = readAll("QUI_DamageMeter/damage_meter/damage_meter.lua")

-- Size bounds live in named constants so the corner-drag grips and the numeric
-- sliders share one source of truth.
for _, k in ipairs({ "WINDOW_SIZE_MIN_W", "WINDOW_SIZE_MAX_W", "WINDOW_SIZE_MIN_H", "WINDOW_SIZE_MAX_H" }) do
    assert(src:find(k, 1, true), "size bound constant " .. k .. " must be defined")
end

-- The frame's resize bounds must be wired from those constants so corner-drag
-- and the sliders clamp identically.
assert(src:find("SetResizeBounds(WINDOW_SIZE_MIN_W, WINDOW_SIZE_MIN_H, WINDOW_SIZE_MAX_W, WINDOW_SIZE_MAX_H)", 1, true),
    "SetResizeBounds must consume the shared size-bound constants")

-- The Layout Mode renderer composes Position + Frame Size collapsibles
-- (the chat-frame pattern), replacing the position-only adapter.
assert(src:find("BuildPositionCollapsible", 1, true),
    "Layout renderer must build the Position collapsible")
assert(src:find("BuildSizeCollapsible", 1, true),
    "Layout renderer must build the Frame Size collapsible")

-- Renderer resolves the live window from the per-window layout key.
assert(src:find("damageMeter_window_(%d+)", 1, true),
    "Layout renderer must extract the window id from the layout key")

-- Size opts wire width/height descriptions (confirms the sliders are configured
-- for this window, not a generic fallback).
assert(src:find("Damage meter window width in pixels.", 1, true),
    "Frame Size section must describe the width slider")
assert(src:find("Damage meter window height in pixels.", 1, true),
    "Frame Size section must describe the height slider")

-- Slider-driven resize is blocked in combat, matching the corner-drag grips.
-- The exact guard idiom must appear for both the grips and the new size setter.
local _, guardCount = src:gsub("if InCombatLockdown and InCombatLockdown%(%) then return end", "")
assert(guardCount >= 2,
    "slider setSize must guard combat with the same idiom as the resize grips "
    .. "(expected >= 2 occurrences, found " .. guardCount .. ")")

-- After a corner-drag the Layout Mode Frame Size sliders must be re-synced to
-- the dragged dimensions (they read the live size only at build time), so the
-- grip release calls the shared layout-utils refresher.
assert(src:find("RefreshActiveSizeSliders", 1, true),
    "resize grip release must refresh the Layout Mode size sliders")

print("OK: damage_meter_layout_size_section_test")
