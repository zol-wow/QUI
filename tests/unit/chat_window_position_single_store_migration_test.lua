-- tests/unit/chat_window_position_single_store_migration_test.lua
-- v45 MigrateChatWindowPositionsToFrameAnchoring: chat window position
-- becomes frameAnchoring-only (damage-meter pattern).
--   * windows[i].position folds into frameAnchoring.chatFrame1/chatWindow<i>
--     as a free entry (parent="disabled") and is deleted.
--   * The fold OVERWRITES free/stale FA entries (the display layer
--     re-asserted windows[i].position on every refresh — it is what the
--     user saw), including parent="screen" ones.
--   * An entry anchored to a REAL frame is an explicit user choice: kept
--     as-is; the legacy position is still deleted.
--   * Profiles without windows or without positions are untouched.
--   * Idempotent.
-- Run: lua tests/unit/chat_window_position_single_store_migration_test.lua

local env = dofile("tools/_addon_env.lua")
local ns = env.LoadCore()

local failures = 0
local function check(name, ok, detail)
    if ok then print(("  ok  %s"):format(name))
    else failures = failures + 1; print(("FAIL  %s  %s"):format(name, detail or "")) end
end

local function deepCopy(v)
    if type(v) ~= "table" then return v end
    local out = {}
    for k, nv in pairs(v) do out[k] = deepCopy(nv) end
    return out
end
local function deepEqual(a, b)
    if a == b then return true end
    if type(a) ~= "table" or type(b) ~= "table" then return false end
    for k, v in pairs(a) do if not deepEqual(v, b[k]) then return false end end
    for k in pairs(b) do if a[k] == nil then return false end end
    return true
end

-- 1. Multi-window fold: every windows[i].position lands under its index key.
local prof = {
    chat = { customDisplay = { windows = {
        { width = 430, height = 190,
          position = { point = "BOTTOMLEFT", relPoint = "BOTTOMLEFT", x = 35, y = 40 }, tabs = {} },
        { width = 300, height = 150,
          position = { point = "CENTER", relPoint = "CENTER", x = 80, y = -60 }, tabs = {} },
    } } },
}
ns.Migrations.RunOnProfile(prof)
local fa = prof.frameAnchoring
check("window 1 -> chatFrame1", fa and fa.chatFrame1
    and fa.chatFrame1.parent == "disabled"
    and fa.chatFrame1.point == "BOTTOMLEFT" and fa.chatFrame1.relative == "BOTTOMLEFT"
    and fa.chatFrame1.offsetX == 35 and fa.chatFrame1.offsetY == 40
    and fa.chatFrame1.sizeStable == true)
check("window 2 -> chatWindow2", fa and fa.chatWindow2
    and fa.chatWindow2.point == "CENTER" and fa.chatWindow2.offsetX == 80)
check("legacy positions deleted",
    prof.chat.customDisplay.windows[1].position == nil
    and prof.chat.customDisplay.windows[2].position == nil)
check("size keys untouched", prof.chat.customDisplay.windows[1].width == 430
    and prof.chat.customDisplay.windows[2].height == 150)

-- 2. Idempotent
local snapshot = deepCopy(prof)
ns.Migrations.RunOnProfile(prof)
check("re-run is a no-op", deepEqual(prof, snapshot))

-- 3. Free/stale FA entry loses to the legacy position (the display layer
--    kept re-asserting windows[i].position — that's what the user saw).
local prof2 = {
    frameAnchoring = { chatFrame1 = {
        parent = "disabled", point = "CENTER", relative = "CENTER",
        offsetX = -999, offsetY = 999 } },
    chat = { customDisplay = { windows = {
        { position = { point = "TOPLEFT", relPoint = "TOPLEFT", x = 10, y = -20 }, tabs = {} },
    } } },
}
ns.Migrations.RunOnProfile(prof2)
check("stale free entry overwritten", prof2.frameAnchoring.chatFrame1.point == "TOPLEFT"
    and prof2.frameAnchoring.chatFrame1.offsetX == 10)

-- 4. parent="screen" counts as free for the fold (display layer overrode it)
local prof3 = {
    frameAnchoring = { chatFrame1 = {
        parent = "screen", point = "CENTER", relative = "CENTER",
        offsetX = 0, offsetY = 0 } },
    chat = { customDisplay = { windows = {
        { position = { point = "BOTTOMRIGHT", relPoint = "BOTTOMRIGHT", x = -5, y = 5 }, tabs = {} },
    } } },
}
ns.Migrations.RunOnProfile(prof3)
check("screen entry overwritten", prof3.frameAnchoring.chatFrame1.parent == "disabled"
    and prof3.frameAnchoring.chatFrame1.point == "BOTTOMRIGHT")

-- 5. Real frame anchor is an explicit user choice: kept; legacy position
--    still deleted.
local prof4 = {
    frameAnchoring = { chatFrame1 = {
        parent = "minimap", point = "TOPRIGHT", relative = "BOTTOMRIGHT",
        offsetX = 0, offsetY = -8 } },
    chat = { customDisplay = { windows = {
        { position = { point = "BOTTOMLEFT", relPoint = "BOTTOMLEFT", x = 35, y = 40 }, tabs = {} },
    } } },
}
ns.Migrations.RunOnProfile(prof4)
check("real anchor preserved", prof4.frameAnchoring.chatFrame1.parent == "minimap"
    and prof4.frameAnchoring.chatFrame1.relative == "BOTTOMRIGHT")
check("legacy position deleted despite kept anchor",
    prof4.chat.customDisplay.windows[1].position == nil)

-- 6. No chat / no windows / no positions: untouched, no phantom FA table
local prof5 = { chat = { customDisplay = { windows = {
    { width = 430, height = 190, tabs = {} },
} } } }
ns.Migrations.RunOnProfile(prof5)
check("position-less window untouched", prof5.frameAnchoring == nil
    or prof5.frameAnchoring.chatFrame1 == nil)

if failures > 0 then os.exit(1) end
print("chat_window_position_single_store_migration_test: all passed")
