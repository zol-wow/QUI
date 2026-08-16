local loadstring = loadstring or load

local function readAll(path)
    local f = assert(io.open(path, "rb"))
    local d = f:read("*a"); f:close()
    return d:gsub("\r\n", "\n")
end

local source = readAll("modules/skinning/character_pane/character.lua")

local function extract(name)
    local S = "-- <<< QUI_TEST_EXTRACT " .. name
    local a1 = assert(source:find(S, 1, true), "start sentinel must exist: " .. name)
    local a2 = assert(source:find(S, a1 + #S, true), "end sentinel must exist: " .. name)
    return source:sub(a1 + #S, a2 - 1)
end

local chunk = table.concat({
    "local _G, GetSettings, CharacterFrame, StyleCloseButton, StyleSidebarTabs, ScheduleUpdate = ...",
    extract("character_refresh_gate"),
}, "\n")

local failures = 0
local function check(name, cond, detail)
    if cond then
        print("ok   - " .. name)
    else
        failures = failures + 1
        print("FAIL - " .. name .. (detail and ("  (" .. detail .. ")") or ""))
    end
end

local function runRefresh(enabled, characterFrame)
    local calls = { style = 0, close = 0, schedule = 0 }
    local fakeG = {}
    assert(loadstring(chunk, "character_refresh_gate"))(
        fakeG,
        function() return { enabled = enabled } end,
        characterFrame,
        function() calls.close = calls.close + 1 end,
        function() calls.style = calls.style + 1 end,
        function() calls.schedule = calls.schedule + 1 end
    )
    assert(type(fakeG.QUI_RefreshCharacterPane) == "function", "extract must define QUI_RefreshCharacterPane")
    fakeG.QUI_RefreshCharacterPane()
    return calls
end

do
    local calls = runRefresh(false, { CloseButton = {} })
    check("disabled module skips sidebar tab styling", calls.style == 0, "StyleSidebarTabs calls: " .. calls.style)
    check("disabled module skips close button styling", calls.close == 0, "StyleCloseButton calls: " .. calls.close)
    check("disabled module still schedules the overlay update", calls.schedule == 1)
end

do
    local calls = runRefresh(true, { CloseButton = {} })
    check("enabled module styles the sidebar tabs", calls.style == 1)
    check("enabled module styles the close button", calls.close == 1)
    check("enabled module schedules the overlay update", calls.schedule == 1)
end

do
    local calls = runRefresh(true, nil)
    check("missing CharacterFrame styles nothing", calls.style == 0 and calls.close == 0)
    check("missing CharacterFrame still schedules the overlay update", calls.schedule == 1)
end

if failures > 0 then
    error(failures .. " assertion(s) failed")
end
print("OK: character_refresh_disabled_gate_test")
