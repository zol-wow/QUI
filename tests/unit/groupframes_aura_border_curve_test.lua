-- tests/unit/groupframes_aura_border_curve_test.lua
-- Run: lua tests/unit/groupframes_aura_border_curve_test.lua
-- Extracts ns.QUI_GroupFrameAuraBorderCurve from groupframes.lua (between its
-- QUI_TEST_EXTRACT sentinels) and drives it against mocks to verify the curve
-- maps None(0)->skin border and each dispel enum->its configured color, gates on
-- the per-context feature flag, and returns nil when C_CurveUtil is absent.

local loadstring = loadstring or load

local function readAll(path)
    local f = assert(io.open(path, "rb"))
    local d = f:read("*a"); f:close()
    return d:gsub("\r\n", "\n")
end

local source = readAll("QUI_GroupFrames/groupframes/groupframes.lua")
local marker = "ns.QUI_GroupFrameAuraBorderCurve = function"
local s = assert(source:find(marker, 1, true), "getter must exist")
local nl = assert(source:find("\n%-%- <<< QUI_TEST_EXTRACT GetAuraBorderColorCurve", s),
    "end sentinel must exist")
local fnSource = source:sub(s, nl - 1)

-- Mock color-curve: records AddPoint(x, color) pairs.
local function newCurve()
    local c = { points = {} }
    function c:SetType(t) self.curveType = t end
    function c:AddPoint(x, color) self.points[x] = color end
    return c
end

-- Wrap the extracted `ns.X = function ... end` assignment in a factory that
-- receives every upvalue it needs as a parameter, runs the assignment, and
-- returns the assigned getter. Clean for Lua 5.1 (no _ENV).
local factorySrc = table.concat({
    "return function(ns, _dispel, C_CurveUtil, CreateColor, Enum, GetDispelColors, GetVisualDB)",
    fnSource,
    "return ns.QUI_GroupFrameAuraBorderCurve",
    "end",
}, "\n")
local factory = assert(loadstring(factorySrc, "auraBorderCurve"))()

local function mkEnv(enabled, withCurveUtil)
    local recorded
    local nsStub = { Helpers = { GetSkinBorderColor = function() return 0.1, 0.2, 0.3, 1 end } }
    local dispelStub = {
        allEnums = { 1, 2, 3, 4, 9, 11 },
        enumNames = { [1]="Magic", [2]="Curse", [3]="Disease", [4]="Poison", [9]="Bleed", [11]="Bleed" },
        auraBorderCurves = {},
    }
    local ccu = withCurveUtil and { CreateColorCurve = function() recorded = newCurve(); return recorded end } or nil
    local createColor = function(r, g, b, a) return { r = r, g = g, b = b, a = a } end
    local enum = { LuaCurveType = { Step = "Step" } }
    local seenContexts = {}
    local getDispelColors = function(isRaid)
        seenContexts[#seenContexts + 1] = isRaid and "raid" or "party"
        local magic = isRaid and {0.9,0.1,0.1} or {0.2,0.6,1}
        return { Magic = magic, Curse = {0.6,0,1}, Disease = {0.6,0.4,0}, Poison = {0,0.6,0}, Bleed = {0.8,0.1,0.1} }
    end
    local getVisualDB = function() return { auras = { debuffBorderByType = enabled } } end
    local getter = factory(nsStub, dispelStub, ccu, createColor, enum, getDispelColors, getVisualDB)
    return getter, function() return recorded end, dispelStub, seenContexts
end

-- enabled -> curve built, point 0 = skin, enum points = configured colors
local getter, getRecorded = mkEnv(true, true)
local curve = getter(false)
assert(curve, "enabled: returns a curve")
local recorded = getRecorded()
assert(recorded.points[0] and recorded.points[0].r == 0.1, "None(0) -> skin border color")
assert(recorded.points[1] and recorded.points[1].r == 0.2, "Magic(1) -> configured Magic color")
assert(recorded.points[9] and recorded.points[9].r == 0.8, "Bleed(9) -> configured Bleed color")

-- disabled context -> nil
local getterDisabled = mkEnv(false, true)
assert(getterDisabled(false) == nil, "disabled: returns nil")

-- no C_CurveUtil -> nil
local getterNoCurve = mkEnv(true, false)
assert(getterNoCurve(false) == nil, "no C_CurveUtil: returns nil")

-- party and raid cache separately and read their own colors
local ctxGetter, ctxRecorded, ctxDispel, seenContexts = mkEnv(true, true)
local partyCurve = ctxGetter(false)
local partyPoints = ctxRecorded().points
assert(partyPoints[1].r == 0.2, "party Magic uses the party color")
local raidCurve = ctxGetter(true)
local raidPoints = ctxRecorded().points
assert(raidCurve ~= partyCurve, "raid must not reuse the party curve")
assert(raidPoints[1].r == 0.9, "raid Magic uses the raid color")
assert(seenContexts[1] == "party" and seenContexts[2] == "raid",
    "the getter must forward isRaid to GetDispelColors")
assert(ctxDispel.auraBorderCurves.party and ctxDispel.auraBorderCurves.raid,
    "both contexts must be cached under their own key")
assert(ctxGetter(true) == raidCurve, "a cached context returns its own curve")

print("PASS: groupframes_aura_border_curve")
