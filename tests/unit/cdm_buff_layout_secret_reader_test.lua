-- tests/unit/cdm_buff_layout_secret_reader_test.lua
-- Run: lua tests/unit/cdm_buff_layout_secret_reader_test.lua
--
-- Structural regression (cdm_buff_layout is too dependency-heavy to instantiate
-- headlessly; the suite asserts source structure -- see
-- cdm_buff_layout_no_combat_end_populate_test for precedent).
--
-- 12.1 secrets report their real type() ("string"/"number"/"boolean"), so a
-- bare type check lets them through into sort comparators / QuerySpellInfo,
-- where the first compare throws ("attempt to compare local 'text' (a secret
-- string value...)"). Contract:
--
--   1. ReadString / ReadNumber / ReadBoolean reject secrets BEFORE the type
--      check (fallback wins).
--   2. GetTrackedBarName reads the Blizzard StatusBar's Name FontString via
--      its parentKey (CooldownViewer.xml) -- no GetRegions scan, no text
--      inspection to guess which FontString is the name, no GetJustifyH
--      heuristic (Duration is justifyH="LEFT" in 12.1, so the old
--      `justify ~= "RIGHT"` filter never excluded it anyway).

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

-- Slice a `local function NAME(...)` body: from its definition to the next
-- line-anchored `end`.
local function sliceFunction(name)
    local start = assert(string.find(src, "local function " .. name, 1, true),
        name .. " definition should exist")
    local finish = assert(string.find(src, "\nend", start, true),
        name .. " should close")
    return string.sub(src, start, finish + 4), start
end

---------------------------------------------------------------------------
-- 1. Readers reject secrets before their type checks.
---------------------------------------------------------------------------
for _, reader in ipairs({ "ReadNumber", "ReadString", "ReadBoolean" }) do
    local body = sliceFunction(reader .. "(value, fallback)")
    local guard = string.find(body, "WoW_IsSecretValue(value)", 1, true)
    local typeCheck = string.find(body, "type(value)", 1, true)
    check(reader .. " must secret-guard before the type check",
        guard ~= nil and typeCheck ~= nil and guard < typeCheck,
        guard == nil and "no WoW_IsSecretValue(value) guard found"
            or "guard appears after type(value) -- secret passes the type check first")
    check(reader .. " secret branch must return the fallback",
        string.find(body, "WoW_IsSecretValue(value) then return fallback", 1, true) ~= nil,
        "secret branch does not return fallback")
end

---------------------------------------------------------------------------
-- 2. GetTrackedBarName: parentKey access, no region scan, no text heuristic.
---------------------------------------------------------------------------
local nameBody = sliceFunction("GetTrackedBarName(frame)")

check("GetTrackedBarName must read the Name parentKey",
    string.find(nameBody, "frame.Name", 1, true) ~= nil,
    "frame.Name access not found")

check("GetTrackedBarName must not scan regions",
    not string.find(nameBody, "GetRegions", 1, true),
    "GetRegions scan still present")

check("GetTrackedBarName must not use the justify heuristic",
    not string.find(nameBody, "GetJustifyH", 1, true),
    "GetJustifyH heuristic still present")

check("GetTrackedBarName must launder text through ReadString",
    string.find(nameBody, "ReadString(rawText", 1, true) ~= nil,
    "text not laundered through ReadString -- secret text would leak to identity consumers")

---------------------------------------------------------------------------
-- 3. The empty-string compare must sit AFTER the ReadString launder (a
--    compare against raw GetText output is exactly the original crash).
---------------------------------------------------------------------------
local launder = string.find(nameBody, "ReadString(rawText", 1, true)
local emptyCompare = string.find(nameBody, '== ""', 1, true)
check("empty-string compare must follow the ReadString launder",
    launder ~= nil and (emptyCompare == nil or launder < emptyCompare),
    "compare against un-laundered text -- secret string compare throws in combat")

---------------------------------------------------------------------------
-- 4. GetTrackedBarIconTexture: GetTexture returns a secret number in combat
--    (aura-driven icon); the secret must be dropped BEFORE the ~= 0 / ~= ""
--    compares, falling back to the spellID icon.
---------------------------------------------------------------------------
local texBody = sliceFunction("GetTrackedBarIconTexture(frame, spellData)")
local texGuard = string.find(texBody, "WoW_IsSecretValue(texture)", 1, true)
local texCompare = string.find(texBody, "~= 0", 1, true)
check("GetTrackedBarIconTexture must secret-guard before the compares",
    texGuard ~= nil and texCompare ~= nil and texGuard < texCompare,
    texGuard == nil and "no WoW_IsSecretValue(texture) guard found"
        or "guard appears after the ~= 0 compare -- secret number compare throws in combat")
check("GetTrackedBarIconTexture must keep the spellID icon fallback",
    string.find(texBody, "QuerySpellInfo(spellID)", 1, true) ~= nil,
    "spellID icon fallback missing -- secret texture would leave the bar iconless")

print(("\n%d failure(s)"):format(failures))
os.exit(failures == 0 and 0 or 1)
