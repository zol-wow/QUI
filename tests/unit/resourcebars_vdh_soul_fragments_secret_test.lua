local function readAll(path)
    local file = assert(io.open(path, "rb"))
    local data = file:read("*a"); file:close()
    return data:gsub("\r\n", "\n")
end

local src = readAll("QUI_ResourceBars/resourcebars/resourcebars.lua")

local start_pos = src:find("local function GetSecondaryResourceValue(resource)", 1, true)
assert(start_pos, "could not locate GetSecondaryResourceValue")
local end_pos = src:find("\nend\n", start_pos, true)
assert(end_pos, "could not locate the end of GetSecondaryResourceValue")

local chunk = src:sub(start_pos, end_pos + 4)

local SecretSentinel = dofile("tests/helpers/secret_sentinel.lua")
local restore = SecretSentinel.InstallSecretStub()

local VENG_SOUL_FRAGMENTS = 101

QUI_POWER = {
    MaelstromWeapon = 100,
    VengSoulFragments = VENG_SOUL_FRAGMENTS,
    Whirlwind = 102,
    TipOfTheSpear = 103,
    RenewingMistCharges = 104,
}

Helpers = {
    IsSecretValue = function(value)
        return issecretvalue and issecretvalue(value) or false
    end,
}

function SafeNumberOrNil(value)
    if issecretvalue and issecretvalue(value) then
        return nil
    end
    return tonumber(value)
end

local castCount
C_Spell = {
    GetSpellCastCount = function(spellID)
        assert(spellID == 228477, "the Vengeance branch must read Soul Cleave's cast count")
        return castCount
    end,
}

local loader = assert(loadstring(chunk .. "\nreturn GetSecondaryResourceValue"))
local GetSecondaryResourceValue = loader()

castCount = 4
do
    local max, current, displayValue, valueType = GetSecondaryResourceValue(VENG_SOUL_FRAGMENTS)
    assert(valueType == "number", "a readable cast count must render as a plain number")
    assert(max == 6, "Vengeance soul fragments cap at 6")
    assert(current == 4 and displayValue == 4, "a readable cast count must reach the bar unchanged")
end

castCount = nil
do
    local max, current, _, valueType = GetSecondaryResourceValue(VENG_SOUL_FRAGMENTS)
    assert(valueType == "number" and max == 6 and current == 0,
        "a missing cast count must render as an empty bar, not nil")
end

castCount = SecretSentinel.MakeSecretSentinel()
do
    local max, current, displayValue, valueType = GetSecondaryResourceValue(VENG_SOUL_FRAGMENTS)
    assert(valueType == "secret",
        "C_Spell.GetSpellCastCount is SecretWhenCooldownsRestricted, so an in-combat read must " ..
        "pass through to the sink, never collapse to 0")
    assert(max == 6, "the cap stays plain so SetMinMaxValues keeps a real range")
    assert(current == castCount and displayValue == castCount,
        "the secret must reach StatusBar:SetValue/SetFormattedText untouched")
end

SecretSentinel.RestoreSecretStub(restore)

print("OK: resourcebars_vdh_soul_fragments_secret_test")
