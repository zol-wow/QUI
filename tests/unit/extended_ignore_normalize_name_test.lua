-- tests/unit/extended_ignore_normalize_name_test.lua
-- Run: lua tests/unit/extended_ignore_normalize_name_test.lua
--
-- Pins NormalizeName (the SOC-01 Extended Ignore matching core): names are
-- matched realm-agnostically and case-insensitively, so both the ignore-list
-- entries and incoming senders/inviters normalize the same way. Extracts the
-- pure function from extended_ignore.lua between its QUI_TEST_EXTRACT sentinels.

local loadstring = loadstring or load

local function readAll(path)
    local f = assert(io.open(path, "rb"))
    local d = f:read("*a"); f:close()
    return d:gsub("\r\n", "\n")
end

local source = readAll("modules/qol/extended_ignore.lua")
local S = "-- <<< QUI_TEST_EXTRACT normalize_name"
local a1 = assert(source:find(S, 1, true), "start sentinel must exist")
local a2 = assert(source:find(S, a1 + #S, true), "end sentinel must exist")
local block = source:sub(a1 + #S, a2 - 1)

-- NormalizeName uses only the string library (pure), so no prelude is needed.
local chunk = block .. "\nreturn { NormalizeName = NormalizeName }"
local M = assert(loadstring(chunk, "extended_ignore_normalize"))()
local N = M.NormalizeName

local failures = 0
local function check(name, cond, detail)
    if cond then
        print("ok   - " .. name)
    else
        failures = failures + 1
        print("FAIL - " .. name .. (detail and ("  (" .. detail .. ")") or ""))
    end
end

-- Case-insensitive.
check("plain name lowercased", N("Bob") == "bob")
check("uppercase lowercased", N("BOB") == "bob")
-- Realm stripped (everything after the first dash).
check("realm stripped", N("Bob-Stormrage") == "bob")
check("multiword realm stripped", N("Bob-Argent Dawn") == "bob")
-- Whitespace removed so " Bob " matches "Bob".
check("surrounding whitespace removed", N(" Bob ") == "bob")
check("inner whitespace removed", N("Bo b") == "bob")
-- List entry and sender normalize identically (the whole point).
check("entry vs sender parity", N("MyName-Realm") == N("myname"))
-- Rejections -> nil (never matches).
check("empty string -> nil", N("") == nil)
check("nil -> nil", N(nil) == nil)
check("number -> nil", N(12345) == nil)
check("all-whitespace -> nil", N("   ") == nil)

if failures > 0 then
    print(("\n%d assertion(s) FAILED"):format(failures))
    os.exit(1)
end
print("\nall NormalizeName assertions passed")
