-- tests/unit/cdm_buff_layout_no_combat_end_populate_test.lua
-- Run: lua tests/unit/cdm_buff_layout_no_combat_end_populate_test.lua
--
-- Structural regression (cdm_buff_layout is too dependency-heavy to instantiate
-- headlessly; the suite asserts source structure -- see cdm_buff_anchor_uiparent_pin_test).
--
-- Buff layout maintains icon placement live during combat via UNIT_AURA and a
-- 10fps OnUpdate poll. ForcePopulateBuffIcons is a no-op stub. The
-- PLAYER_REGEN_ENABLED combat-end repopulate/relayout branch is therefore
-- redundant and was contributing to the end-of-pull FPS stutter.
--
-- Contract:
--   - eventFrame must NOT register PLAYER_REGEN_ENABLED
--   - eventFrame MUST still register PLAYER_ENTERING_WORLD (login/reload recovery)
--   - eventFrame MUST still register ADDON_LOADED (init)
--   - The PLAYER_REGEN_ENABLED elseif handler branch must not exist in the file

local function readAll(path)
    local f = assert(io.open(path, "rb"), "cannot open " .. path)
    local text = f:read("*a")
    f:close()
    return text
end

local src = readAll("QUI_CDM/cdm/cdm_buff_layout.lua")

local failures = 0
local function check(name, ok, detail)
    if ok then
        print(("  ok  %s"):format(name))
    else
        failures = failures + 1
        print(("FAIL  %s  %s"):format(name, detail or ""))
    end
end

-- 1. The eventFrame registration block must NOT contain PLAYER_REGEN_ENABLED.
--    Slice from eventFrame creation to the SetScript call so we only look at
--    the registration block, not any other occurrence in a comment.
local frameStart = assert(string.find(src, 'local eventFrame = CreateFrame("Frame")', 1, true),
    "eventFrame definition should exist")
local setScriptPos = assert(string.find(src, 'eventFrame:SetScript("OnEvent"', frameStart, true),
    "eventFrame:SetScript should follow the registration block")
local registrationBlock = string.sub(src, frameStart, setScriptPos)

check("eventFrame must NOT register PLAYER_REGEN_ENABLED",
    not string.find(registrationBlock, "PLAYER_REGEN_ENABLED", 1, true),
    "found RegisterEvent(\"PLAYER_REGEN_ENABLED\") in the registration block")

-- 2. Login/reload recovery path must remain: PLAYER_ENTERING_WORLD registered.
check("eventFrame must register PLAYER_ENTERING_WORLD",
    string.find(registrationBlock, "PLAYER_ENTERING_WORLD", 1, true) ~= nil,
    "PLAYER_ENTERING_WORLD registration not found in registration block")

-- 3. Init path must remain: ADDON_LOADED registered.
check("eventFrame must register ADDON_LOADED",
    string.find(registrationBlock, "ADDON_LOADED", 1, true) ~= nil,
    "ADDON_LOADED registration not found in registration block")

-- 4. The dead handler branch must be gone from the OnEvent body.
--    Slice from SetScript to just after the closing `end)` of OnEvent.
local handlerStart = setScriptPos
local handlerEnd = assert(string.find(src, "\nend)", handlerStart, true),
    "SetScript OnEvent closing end) not found")
local handlerBlock = string.sub(src, handlerStart, handlerEnd + 4)

check("elseif PLAYER_REGEN_ENABLED handler branch must be removed",
    not string.find(handlerBlock, 'event == "PLAYER_REGEN_ENABLED"', 1, true),
    "found 'event == \"PLAYER_REGEN_ENABLED\"' in the OnEvent handler -- dead branch not removed")

-- 5. The PLAYER_ENTERING_WORLD handler body must still be present (guard against
--    accidentally removing too much).
check("PLAYER_ENTERING_WORLD handler body intact (isInitialLogin check still present)",
    string.find(handlerBlock, "isInitialLogin", 1, true) ~= nil,
    "isInitialLogin reference missing -- PLAYER_ENTERING_WORLD handler may have been damaged")

print(("\n%d failure(s)"):format(failures))
os.exit(failures == 0 and 0 or 1)
