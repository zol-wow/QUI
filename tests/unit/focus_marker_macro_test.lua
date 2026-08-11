-- tests/unit/focus_marker_macro_test.lua
-- Run: lua tests/unit/focus_marker_macro_test.lua
--
-- Pins BuildMacroBody (GRP-04 focus-marker core): mouseover mode emits the
-- [@mouseover,harm,nodead][] conditional pair, plain mode targets the
-- current target; the marker index is clamped to 1-8 and defaults to 8.
-- Extracted from focus_marker.lua between its QUI_TEST_EXTRACT sentinels.

local loadstring = loadstring or load

local function readAll(path)
    local f = assert(io.open(path, "rb"))
    local d = f:read("*a"); f:close()
    return d:gsub("\r\n", "\n")
end

local source = readAll("modules/qol/focus_marker.lua")
local S = "-- <<< QUI_TEST_EXTRACT macro_body"
local a1 = assert(source:find(S, 1, true), "start sentinel must exist")
local a2 = assert(source:find(S, a1 + #S, true), "end sentinel must exist")
local block = source:sub(a1 + #S, a2 - 1)

local chunk = block .. "\nreturn { BuildMacroBody = BuildMacroBody }"
local M = assert(loadstring(chunk, "focus_marker_macro"))()
local B = M.BuildMacroBody

local failures = 0
local function check(name, cond, detail)
    if cond then
        print("ok   - " .. name)
    else
        failures = failures + 1
        print("FAIL - " .. name .. (detail and ("  (" .. detail .. ")") or ""))
    end
end

check("mouseover body", B(8, true) ==
    "/focus [@mouseover,harm,nodead][]\n/tm [@mouseover,harm,nodead][] 8")
check("plain body", B(3, false) == "/focus\n/tm 3")
check("nil marker defaults to 8", B(nil, false) == "/focus\n/tm 8")
check("marker clamped low", B(0, false) == "/focus\n/tm 1")
check("marker clamped high", B(99, false) == "/focus\n/tm 8")
check("string marker coerced", B("5", false) == "/focus\n/tm 5")

if failures > 0 then
    print(failures .. " failure(s)")
    os.exit(1)
end
print("all passed")
