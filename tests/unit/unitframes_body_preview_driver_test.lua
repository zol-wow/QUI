-- tests/unit/unitframes_body_preview_driver_test.lua
-- Run: lua tests/unit/unitframes_body_preview_driver_test.lua

local function readAll(path)
    local file = assert(io.open(path, "rb"))
    local data = file:read("*a")
    file:close()
    -- Normalize CRLF -> LF so source-pattern searches work on Windows.
    data = data:gsub("\r\n", "\n")
    return data
end

local source = readAll("modules/unitframes/settings/unit_frames_body_preview.lua")

-- T1: file exists and exposes the public surface on ns.QUI_UnitFramesBodyPreview
assert(source:find("ns.QUI_UnitFramesBodyPreview", 1, true),
    "driver must publish ns.QUI_UnitFramesBodyPreview")

for _, fnName in ipairs({"Build", "Refresh", "SetSelectedUnit", "Teardown", "GetCurrentPcts"}) do
    assert(source:find("function Module." .. fnName, 1, true)
        or source:find("Module." .. fnName .. " = function", 1, true),
        "driver must define Module." .. fnName)
end

-- T1: ticker frame must be created (driver-owned, parented to host on Build)
assert(source:find("CreateFrame", 1, true),
    "driver must create at least one frame (the ticker)")
assert(source:find('SetScript("OnUpdate"', 1, true),
    "driver must wire an OnUpdate handler on its ticker")

-- T1: driver must NOT register any game events (cycle is time-driven)
assert(not source:find("RegisterEvent", 1, true),
    "driver must not register any game events (cycle is time-driven)")

-- T2: FormatHealthText and FormatPowerText migrated to driver
assert(source:find("function Module.FormatHealthText", 1, true)
    or source:find("Module.FormatHealthText = function", 1, true),
    "driver must define Module.FormatHealthText")
assert(source:find("function Module.FormatPowerText", 1, true)
    or source:find("Module.FormatPowerText = function", 1, true),
    "driver must define Module.FormatPowerText")

-- T2: format helpers take a `pct` parameter (no file-constant reads)
assert(not source:find("MOCK_HEALTH_PCT", 1, true),
    "driver must not reference MOCK_HEALTH_PCT (pct flows in as a parameter)")
assert(not source:find("MOCK_POWER_PCT", 1, true),
    "driver must not reference MOCK_POWER_PCT (pct flows in as a parameter)")

-- T2: surface.lua no longer defines the format helpers or the pct constants
local surface = readAll("modules/unitframes/settings/unit_frames_surface.lua")
assert(not surface:find("MOCK_HEALTH_PCT", 1, true),
    "surface.lua must no longer define MOCK_HEALTH_PCT (driver owns the cycle pct)")
assert(not surface:find("MOCK_POWER_PCT", 1, true),
    "surface.lua must no longer define MOCK_POWER_PCT (driver owns the cycle pct)")
assert(not surface:find("local function FormatHealthText", 1, true),
    "surface.lua must no longer define FormatHealthText (migrated to driver)")
assert(not surface:find("local function FormatPowerText", 1, true),
    "surface.lua must no longer define FormatPowerText (migrated to driver)")

-- T3: cycle catalog constants and helpers
assert(source:find("CYCLE_LENGTH", 1, true),
    "driver must define a CYCLE_LENGTH constant")
assert(source:find("CYCLE_LENGTH = 14", 1, true)
    or source:find("CYCLE_LENGTH=14", 1, true),
    "driver CYCLE_LENGTH must be 14 (per spec)")
assert(source:find("local function ComputePcts", 1, true),
    "driver must define a local ComputePcts(t) function")
assert(source:find("local function AdvanceCycle", 1, true),
    "driver must define a local AdvanceCycle(elapsed) function")

-- T3: ComputePcts must produce the 4 pcts named in the spec
for _, sym in ipairs({"healthPct", "powerPct", "healPredPct", "absorbPct"}) do
    assert(source:find(sym, 1, true),
        "ComputePcts / GetCurrentPcts must expose " .. sym)
end

-- T3: AdvanceCycle wraps t at CYCLE_LENGTH
assert(source:find("% CYCLE_LENGTH", 1, true)
    or source:find("%%CYCLE_LENGTH", 1, true)
    or source:find("math.fmod", 1, true),
    "AdvanceCycle must wrap state.cycle.t at CYCLE_LENGTH (use t % CYCLE_LENGTH)")

-- T4: ApplyDynamics helper exists and writes to the expected primitives
assert(source:find("local function ApplyDynamics", 1, true),
    "driver must define a local ApplyDynamics function")
assert(source:find("_healthBar:SetWidth", 1, true),
    "ApplyDynamics must drive mock._healthBar:SetWidth")
assert(source:find("_powerBar:SetWidth", 1, true),
    "ApplyDynamics must drive mock._powerBar:SetWidth")
assert(source:find("_healthText:SetText", 1, true),
    "ApplyDynamics must drive mock._healthText:SetText (via FormatHealthText)")
assert(source:find("_powerText:SetText", 1, true),
    "ApplyDynamics must drive mock._powerText:SetText (via FormatPowerText)")
assert(source:find("_healPred:SetWidth", 1, true),
    "ApplyDynamics must drive mock._healPred:SetWidth")
assert(source:find("_absorb:SetWidth", 1, true),
    "ApplyDynamics must drive mock._absorb:SetWidth")

-- T5: OnUpdate ticker dispatches AdvanceCycle + ApplyDynamics
local tickerStart = assert(source:find('SetScript("OnUpdate"', 1, true),
    "ticker SetScript('OnUpdate', ...) required")
local tickerEnd = assert(source:find("\n%s*end%)", tickerStart),
    "OnUpdate handler must terminate")
local advanceCall = source:find("AdvanceCycle", tickerStart, true)
assert(advanceCall and advanceCall < tickerEnd,
    "OnUpdate handler must call AdvanceCycle(elapsed)")
local applyCall = source:find("ApplyDynamics", tickerStart, true)
assert(applyCall and applyCall < tickerEnd,
    "OnUpdate handler must call ApplyDynamics(...)")

-- T6: per-aura state init helper exists and randomizes initial values
assert(source:find("local function InitAuraState", 1, true)
    or source:find("local function EnsureAuraState", 1, true),
    "driver must define a per-aura state initializer")
assert(source:find("math.random", 1, true),
    "per-aura state must randomize initial duration and/or stack")

-- T6: AdvanceAuraStates exists and is called from OnUpdate
assert(source:find("local function AdvanceAuraStates", 1, true),
    "driver must define a local AdvanceAuraStates(elapsed) function")

local tickerStart2 = assert(source:find('SetScript("OnUpdate"', 1, true))
local tickerEnd2 = assert(source:find("\n%s*end%)", tickerStart2))
local auraTickCall = source:find("AdvanceAuraStates", tickerStart2, true)
assert(auraTickCall and auraTickCall < tickerEnd2,
    "OnUpdate handler must call AdvanceAuraStates(elapsed) every tick")

-- T6: ApplyDynamics writes per-aura stack + duration text
assert(source:find("_stack:SetText", 1, true),
    "ApplyDynamics must write per-aura stack text (icon._stack:SetText)")
assert(source:find("_dur:SetText", 1, true),
    "ApplyDynamics must write per-aura duration text (icon._dur:SetText)")
assert(source:find('"%%%.0fs"', 1, true)
    or source:find('"%%.0fs"', 1, true)
    or source:find('"%.0fs"', 1, true),
    "duration text must use the \"%.0fs\" format string")

-- T7: Refresh caches unitDB / general and applies dynamics immediately
-- Use the NEXT public method as the boundary (more reliable than '\nend\n'
-- which matches inner if/for/syncPool ends before the function close).
local refreshStart = assert(source:find("function Module.Refresh", 1, true),
    "Refresh definition required")
local refreshEnd = source:find("function Module.SetSelectedUnit", refreshStart + 1, true)
    or #source
assert(source:find("state.lastUnitDB", refreshStart, true) and
       source:find("state.lastUnitDB", refreshStart, true) < refreshEnd,
    "Refresh must cache unitDB on state.lastUnitDB")
local refreshApplyCall = source:find("ApplyDynamics", refreshStart, true)
assert(refreshApplyCall and refreshApplyCall < refreshEnd,
    "Refresh must call ApplyDynamics to paint the first frame after refresh")

-- T7: SetSelectedUnit resets cycle state
local setUnitStart = assert(source:find("function Module.SetSelectedUnit", 1, true),
    "SetSelectedUnit definition required")
local setUnitEnd = source:find("function Module.Teardown", setUnitStart + 1, true) or #source
local resetT = source:find("state.cycle.t", setUnitStart, true)
assert(resetT and resetT < setUnitEnd,
    "SetSelectedUnit must reset state.cycle.t")
local resetAura = source:find("state.auraStates", setUnitStart, true)
assert(resetAura and resetAura < setUnitEnd,
    "SetSelectedUnit must clear or re-randomize state.auraStates")

print("OK: unitframes_body_preview_driver_test")
