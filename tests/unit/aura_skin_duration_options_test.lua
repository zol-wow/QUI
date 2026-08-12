local function fail(msg)
    print("FAIL: aura_skin_duration_options_test - " .. msg)
    os.exit(1)
end

Enum = { NumericRuleFormatRounding = { Nearest = 0, Up = 1, Down = 2 } }
C_StringUtil = {
    CreateNumericRuleFormatter = function()
        local f = {}
        function f.SetBreakpoints(self, breakpoints) self.breakpoints = breakpoints end
        return f
    end,
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
local bp = dec.textFormatter.breakpoints
if not (bp and bp[1] and bp[1].format == "%.1fs" and bp[2] and bp[2].threshold == 3) then
    fail("decimals formatter must show tenths below 3s via breakpoints")
end

local noUnit = AuraSkin.BuildDurationTextOptions({ duration = { hideUnit = true } })
if noUnit.textFormatter == nil then fail("hideUnit must produce a textFormatter") end
bp = noUnit.textFormatter.breakpoints
if not (bp and bp[1] and bp[1].format == "%d") then
    fail("hideUnit formatter must render bare seconds (got " .. tostring(bp and bp[1] and bp[1].format) .. ")")
end
if not (bp[2] and bp[2].format == "%dm") then
    fail("hideUnit formatter must keep the minutes unit")
end

local both = AuraSkin.BuildDurationTextOptions({ duration = { decimals = true, hideUnit = true } })
bp = both.textFormatter and both.textFormatter.breakpoints
if not (bp and bp[1] and bp[1].format == "%.1f" and bp[2] and bp[2].format == "%d") then
    fail("decimals + hideUnit must render bare tenths and bare seconds")
end
if noUnit.textFormatter == dec.textFormatter then
    fail("distinct option combos must not share one cached formatter")
end

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
