local function readAll(path)
    local file = assert(io.open(path, "rb"))
    local data = file:read("*a")
    file:close()
    return data
end

local source = readAll("QUI_CDM/cdm/cdm_bar_renderer.lua")

assert(source:find("local function ColorStateChanged", 1, true),
    "bar renderer must compare configured color components")
assert(source:find("ColorStateChanged(fingerprint.bar, settings.barColor)", 1, true),
    "bar state must include the fallback bar color")
assert(source:find("ColorStateChanged(fingerprint.override,", 1, true),
    "bar state must include the per-spell override color")
assert(source:find("bar._cfgFingerprint", 1, true),
    "bar state must be cached on each bar")
assert(source:find("if configChanged or bar._cfgActive ~= bar._active", 1, true),
    "color changes must re-run ConfigureBar")

print("OK: cdm_bars_color_override_test")
