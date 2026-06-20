-- tests/unit/character_pane_timer_lifecycle_guard_test.lua
-- Run: lua tests/unit/character_pane_timer_lifecycle_guard_test.lua

local function readFile(path)
    local fh = assert(io.open(path, "rb"), "failed to open " .. path)
    local text = fh:read("*a")
    fh:close()
    return text
end

local function assertContains(text, needle, reason)
    assert(text:find(needle, 1, true), reason)
end

local function assertAbsentPattern(text, pattern, reason)
    assert(not text:find(pattern), reason)
end

local characterPane = readFile("QUI_Skinning/skinning/character_pane/character.lua")
local characterPaneOptions = readFile("QUI_Skinning/skinning/character_pane/settings/character_pane_content.lua")

assertAbsentPattern(characterPane, "C_Timer%.After%(%s*0%.1%s*,",
    "character pane runtime code must not use fixed 0.1s lifecycle catch-up timers")
assertAbsentPattern(characterPane, "C_Timer%.After%(%s*0%.15%s*,",
    "character pane runtime code must not use fixed 0.15s lifecycle catch-up timers")
assertAbsentPattern(characterPaneOptions, "C_Timer%.After%(%s*0%.1%s*,",
    "character pane options code must not use fixed 0.1s open-panel timers")

assertContains(characterPane, "local function RunAfterCharacterPaneLayoutTick(callback)",
    "runtime zero-delay layout deferrals must go through a named character-pane lifecycle helper")
assertContains(characterPane, "RunAfterCharacterPaneLayoutTick(function()",
    "runtime character-pane layout follow-ups must use the named zero-delay helper")
assertContains(characterPaneOptions, "C_Timer.After(0, function()",
    "options open-panel handoff may defer one frame, but must not wait a fixed 0.1s")

print("OK: character_pane_timer_lifecycle_guard_test")
