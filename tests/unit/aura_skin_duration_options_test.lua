local function fail(msg)
    print("FAIL: aura_skin_duration_options_test - " .. msg)
    os.exit(1)
end

C_StringUtil = {
    CreateNumericRuleFormatter = function(a, b, n) return { fmt = { a, b, n } } end,
}

local ns = { Addon = {} }
assert(loadfile("core/aura_skin.lua"))("QUI", ns)
local AuraSkin = ns.Addon.AuraSkin or (_G.QUI and _G.QUI.AuraSkin)
if not AuraSkin then fail("AuraSkin must be exported") end
if type(AuraSkin.BuildDurationTextOptions) ~= "function" then
    fail("AuraSkin.BuildDurationTextOptions must be exported")
end
if type(AuraSkin.ResolveDurationTextOptions) ~= "function" then
    fail("AuraSkin.ResolveDurationTextOptions must be exported")
end

local plain = AuraSkin.BuildDurationTextOptions({ duration = {} })
if plain.textFormatter ~= nil then fail("no decimals means no textFormatter") end
if plain.textColor ~= nil then fail("plain profile means no textColor") end

local dec = AuraSkin.BuildDurationTextOptions({ duration = { decimals = true } })
if dec.textFormatter == nil then fail("decimals must produce a textFormatter") end

local legacy = AuraSkin.BuildDurationTextOptions({
    duration = { color = { 0, 0, 1, 1 }, pandemicColor = { 1, 0, 0 } },
})
if legacy.textColor ~= nil then
    fail("legacy pandemicColor must never produce a textColor binding")
end

local button = {}
local resolved = AuraSkin.ResolveDurationTextOptions(button, {
    duration = { color = { 0, 0, 1, 1 }, pandemicColor = { 1, 0, 0 } },
})
if resolved.textColor ~= nil then fail("resolve must never emit textColor") end
if button._quiPandemicCurved ~= nil then fail("resolve must not set the retired latch") end

local src = assert(io.open("core/aura_skin.lua", "rb")):read("*a")
if src:find("PandemicCurve", 1, true) then fail("PandemicCurve must be deleted") end
if src:find("_quiPandemicCurved", 1, true) then fail("the _quiPandemicCurved latch must be deleted") end
if src:find("BuildDurationClearCurveOptions", 1, true) then
    fail("BuildDurationClearCurveOptions must be deleted")
end

print("PASS: aura_skin_duration_options_test")
