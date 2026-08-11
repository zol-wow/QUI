-- tests/unit/groupframes_dispel_type_icon_runtime_test.lua
-- Run: lua5.1 tests/unit/groupframes_dispel_type_icon_runtime_test.lua

local loadstring = loadstring or load

local function readAll(path)
    local f = assert(io.open(path, "rb"))
    local d = f:read("*a"); f:close()
    return d:gsub("\r\n", "\n")
end

local source = readAll("QUI_GroupFrames/groupframes/groupframes.lua")
local beginMarker = "-- >>> QUI_TEST_EXTRACT DispelTypeIconRuntime"
local endMarker = "-- <<< QUI_TEST_EXTRACT DispelTypeIconRuntime"
local first = assert(source:find(beginMarker, 1, true), "begin marker")
local startPos = assert(source:find("\n", first, true)) + 1
local stopPos = assert(source:find(endMarker, startPos, true), "end marker")
local fnSource = source:sub(startPos, stopPos - 1)

local factory = assert(loadstring(table.concat({
    "return function(_dispel, IsSecretValue, C_UnitAuras, C_Secrets, C_CurveUtil, CreateColor, Enum, Chrome)",
    fnSource,
    "return _dispel",
    "end",
}, "\n"), "dispelTypeIconRuntime"))()

local function newCurve()
    local curve = { points = {} }
    function curve:SetType(v) self.curveType = v end
    function curve:AddPoint(v, color) self.points[v] = color end
    return curve
end

local TYPES = { "Magic", "Curse", "Disease", "Poison", "Bleed" }
local Chrome = { DISPEL_ICON_TYPES = TYPES }
function Chrome.HideDispelTypeIcons(frame)
    for _, name in ipairs(TYPES) do frame.dispelTypeIcons[name]:Hide() end
end

local activeEnum = 9
local C_UnitAuras = {
    GetAuraDataByAuraInstanceID = function(_, id) return id == 11 and {} or nil end,
    GetAuraDispelTypeColor = function(_, _, curve)
        local point = curve.points[activeEnum]
        return { GetRGBA = function() return point.r, point.g, point.b, point.a end }
    end,
}
local dispel = factory({
    allEnums = { 1, 2, 3, 4, 9, 11 },
    enumNames = {
        [1] = "Magic", [2] = "Curse", [3] = "Disease", [4] = "Poison",
        [9] = "Bleed", [11] = "Bleed",
    },
    iconCurves = {},
}, function() return false end, C_UnitAuras,
    { ShouldAurasBeSecret = function() return false end },
    { CreateColorCurve = newCurve },
    function(r, g, b, a) return { r = r, g = g, b = b, a = a } end,
    { LuaCurveType = { Step = "Step" } }, Chrome)

assert(dispel.ReadableType({ dispelName = "Magic" }) == "Magic")
assert(dispel.ReadableType({ dispelName = "Enrage" }) == "Bleed")
assert(dispel.ReadableType({ dispelType = 11 }) == "Bleed")

local bleedCurve = dispel.GetIconCurve("Bleed")
assert(bleedCurve.points[9].a == 1 and bleedCurve.points[11].a == 1
    and bleedCurve.points[1].a == 0, "Bleed curve selects both Bleed/Enrage enums")
local magicCurve = dispel.GetIconCurve("Magic")
assert(magicCurve.points[1].a == 1 and magicCurve.points[9].a == 0,
    "Magic curve selects only the Magic enum")

local frame = { dispelTypeIcons = {} }
for _, name in ipairs(TYPES) do
    local texture = {}
    function texture:SetVertexColor(...) self.vertex = { ... } end
    local icon = { shown = false, texture = texture }
    function icon:GetStatusBarTexture() return self.texture end
    function icon:Show() self.shown = true end
    function icon:Hide() self.shown = false end
    frame.dispelTypeIcons[name] = icon
end
assert(dispel.ShowIconWithCurves(frame, "party1", 11) == true)
for _, name in ipairs(TYPES) do
    assert(frame.dispelTypeIcons[name].shown == true,
        "all overlapping curve-driven icon frames stay shown")
    local expectedAlpha = name == "Bleed" and 1 or 0
    assert(frame.dispelTypeIcons[name].texture.vertex[4] == expectedAlpha,
        name .. " atlas alpha must come from its type curve")
end

local id, typeName = dispel.SelectCachedAura({
    typedDebuffOrder = { 10, 11 },
    typedDebuffs = { [11] = true },
    debuffsByID = { [11] = { dispelName = "Poison" } },
}, "party1", "typedDebuffOrder", "typedDebuffs")
assert(id == 11 and typeName == "Poison",
    "selector ignores phantom order entries and resolves the first live member")

assert(fnSource:find("icon:GetStatusBarTexture():SetVertexColor(color:GetRGBA())", 1, true),
    "secret color components are forwarded directly into a supported texture sink")
assert(not fnSource:find("IsSecretValue(color)", 1, true),
    "curve-driven icon path never branches on the returned secret color")
assert(source:find('dispelCfg.scope == "ALL_TYPED"', 1, true)
    and source:find('"typedDebuffOrder", "typedDebuffs"', 1, true),
    "all-typed scope selects the dedicated awareness cache")
assert(source:find("if glowOn and playerInstID then", 1, true),
    "cleanse glow remains tied to player-actionable membership")

print("OK: groupframes_dispel_type_icon_runtime_test")
