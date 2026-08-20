local function readAll(path)
    local file = assert(io.open(path, "rb"))
    local data = file:read("*a")
    file:close()
    return data
end

local source = readAll("QUI_CDM/cdm/cdm_bar_renderer.lua")

assert(source:find("local function GetColorFingerprint", 1, true),
    "bar renderer must fingerprint configured colors")
assert(source:find("local barColorHash = GetColorFingerprint(settings.barColor)", 1, true),
    "bar fingerprint must include the fallback bar color")
assert(source:find("local overrideColorHash = GetColorFingerprint(", 1, true),
    "bar fingerprint must include the per-spell override color")
assert(source:find("barCfgFingerprint = cfgFingerprint", 1, true),
    "bar fingerprint must combine color changes with the base configuration")
assert(source:find("bar._cfgFingerprint ~= barCfgFingerprint", 1, true),
    "color changes must re-run ConfigureBar")

print("OK: cdm_bars_color_override_test")
