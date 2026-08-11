-- tests/unit/cdm_resolvers_cast_secret_probe_test.lua
-- Run: lua tests/unit/cdm_resolvers_cast_secret_probe_test.lua
--
-- UnitCastingInfo/UnitChannelInfo are SecretWhenUnitSpellCastRestricted
-- (UnitDocumentation.lua:815): castSpellID/startMS/endMS can each arrive
-- secret. `==` and arithmetic on a secret THROW, so both resolver getters
-- must probe with ResolverIsSecretValue before comparing, and the
-- UNIT_SPELLCAST_START dispatch must probe arg3 before publishing it into
-- the bus (secret spellIDs land in table keys downstream).

local function readFile(path)
    local fh = assert(io.open(path, "rb"), "failed to open " .. path)
    local text = fh:read("*a")
    fh:close()
    return text
end

local function assertContains(text, needle, reason)
    assert(text:find(needle, 1, true), reason)
end

local source = readFile("QUI_CDM/cdm/cdm_resolvers.lua")

-- GetSpellCastInfo probes all three secretizable returns before use
local castStart = assert(source:find("function CDMResolvers.GetSpellCastInfo", 1, true))
local castEnd = assert(source:find("function CDMResolvers.GetSpellChannelInfo", castStart, true))
local castBody = source:sub(castStart, castEnd)
assertContains(castBody, "ResolverIsSecretValue(castSpellID)",
    "GetSpellCastInfo must probe castSpellID before ==")
assertContains(castBody, "ResolverIsSecretValue(startMS)",
    "GetSpellCastInfo must probe startMS before arithmetic")
assertContains(castBody, "ResolverIsSecretValue(endMS)",
    "GetSpellCastInfo must probe endMS before arithmetic")

-- GetSpellChannelInfo probes all three secretizable returns before use
local chanStart = castEnd
local chanEnd = assert(source:find("function CDMResolvers.GetSpellBuffInfo", chanStart, true))
local chanBody = source:sub(chanStart, chanEnd)
assertContains(chanBody, "ResolverIsSecretValue(channelSpellID)",
    "GetSpellChannelInfo must probe channelSpellID before ==")
assertContains(chanBody, "ResolverIsSecretValue(startMS)",
    "GetSpellChannelInfo must probe startMS before arithmetic")
assertContains(chanBody, "ResolverIsSecretValue(endMS)",
    "GetSpellChannelInfo must probe endMS before arithmetic")

-- UNIT_SPELLCAST_START publish probes arg3 like the SUCCEEDED branch
local startBranch = assert(source:find('evt == "UNIT_SPELLCAST_START"', 1, true))
local succBranch = assert(source:find('evt == "UNIT_SPELLCAST_SUCCEEDED"', startBranch, true))
local startBody = source:sub(startBranch, succBranch)
assertContains(startBody, "ResolverIsSecretValue(arg3)",
    "UNIT_SPELLCAST_START must probe arg3 before publishing")

print("PASS cdm_resolvers_cast_secret_probe_test")
