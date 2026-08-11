-- tests/unit/mail_contacts_recipient_test.lua
-- Run: lua tests/unit/mail_contacts_recipient_test.lua
--
-- Pins FormatRecipient (MAIL-01 contacts core): same-realm contacts fill the
-- bare character name (realms compared normalized — spaces/hyphens/apostrophes
-- stripped, case-folded), cross-realm contacts fill "Name-Realm". Extracted
-- from mail_contacts.lua between its QUI_TEST_EXTRACT sentinels (pure string
-- logic, no WoW APIs).

local loadstring = loadstring or load

local function readAll(path)
    local f = assert(io.open(path, "rb"))
    local d = f:read("*a"); f:close()
    return d:gsub("\r\n", "\n")
end

local source = readAll("modules/qol/mail_contacts.lua")
local S = "-- <<< QUI_TEST_EXTRACT recipient_format"
local a1 = assert(source:find(S, 1, true), "start sentinel must exist")
local a2 = assert(source:find(S, a1 + #S, true), "end sentinel must exist")
local block = source:sub(a1 + #S, a2 - 1)

local chunk = block .. "\nreturn { FormatRecipient = FormatRecipient, NormalizeRealm = NormalizeRealm }"
local M = assert(loadstring(chunk, "mail_contacts_recipient"))()
local F = M.FormatRecipient

local failures = 0
local function check(name, cond, detail)
    if cond then
        print("ok   - " .. name)
    else
        failures = failures + 1
        print("FAIL - " .. name .. (detail and ("  (" .. detail .. ")") or ""))
    end
end

-- Same realm (exact) -> bare name.
check("same realm exact", F("Bob", "Area52", "Area52") == "Bob")
-- Same realm, display form vs normalized form (space stripped).
check("same realm spaced", F("Bob", "Area 52", "Area52") == "Bob")
check("same realm case-fold", F("Bob", "AREA52", "area52") == "Bob")
check("same realm apostrophe", F("Bob", "Kel'Thuzad", "KelThuzad") == "Bob")
check("same realm hyphen", F("Bob", "Azjol-Nerub", "AzjolNerub") == "Bob")
-- Cross-realm -> Name-Realm.
check("cross realm", F("Bob", "Stormrage", "Area52") == "Bob-Stormrage")
-- No realm recorded -> bare name.
check("empty realm", F("Bob", "", "Area52") == "Bob")
check("nil realm", F("Bob", nil, "Area52") == "Bob")
-- Invalid name -> nil.
check("nil name", F(nil, "Area52", "Area52") == nil)
check("empty name", F("", "Area52", "Area52") == nil)
-- NormalizeRealm behavior.
check("normalize strips + folds", M.NormalizeRealm("Kel'Thuzad Alpha-Two") == "kelthuzadalphatwo")
check("normalize non-string", M.NormalizeRealm(nil) == "")

if failures > 0 then
    print(failures .. " failure(s)")
    os.exit(1)
end
print("all passed")
