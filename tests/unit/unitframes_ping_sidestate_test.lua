-- tests/unit/unitframes_ping_sidestate_test.lua
-- Run: lua tests/unit/unitframes_ping_sidestate_test.lua
--
-- UnitFrames must remain ping receivers without addon-writing the Lua
-- `frame.unit` member (same contract groupframes_ping_template_test.lua pins
-- for header children). Blizzard's PingableType_UnitFrameMixin prefers that
-- member over the secure `unit` attribute; an addon-written value taints the
-- target info the ping flow hands to C_PingSecure.SendUnitPing. QUI keeps its
-- runtime token in weak side state (QUI_UF.GetFrameUnit / SetFrameUnit).
--
-- Unlike header children, these frames are created directly by QUI, so QUI
-- itself must stamp the secure `unit` attribute (RegisterUnitWatch, secure
-- clicks). That write is unavoidable here and intentionally NOT pinned
-- against; the side-state rule only covers the Lua member the mixin prefers.

local loadstring = loadstring or load

local function readAll(path)
    local file = assert(io.open(path, "rb"))
    local data = file:read("*a")
    file:close()
    return (data:gsub("\r\n", "\n"))
end

local fails = 0
local function check(name, ok, detail)
    if ok then
        print("  ok  " .. name)
    else
        fails = fails + 1
        print("FAIL  " .. name .. (detail and ("  " .. detail) or ""))
    end
end

local uf = readAll("QUI_UnitFrames/unitframes/unitframes.lua")

-------------------------------------------------------------------------------
-- Both CreateFrame sites stay ping receivers and route their unit token
-- through the side-state setter instead of the Lua member.
-------------------------------------------------------------------------------
local pingTemplateLiteral =
    '"SecureUnitButtonTemplate, BackdropTemplate, PingableUnitFrameTemplate"'
local templateCount = 0
for _ in uf:gmatch(pingTemplateLiteral) do
    templateCount = templateCount + 1
end
check("both unit-frame CreateFrame sites carry PingableUnitFrameTemplate",
    templateCount == 2, "found " .. templateCount)

local setterCount = 0
-- leading newline+indent excludes the accessor's own definition line
for _ in uf:gmatch("\n%s+QUI_UF%.SetFrameUnit%(frame, unit%)") do
    setterCount = setterCount + 1
end
check("both creation sites store the unit token via QUI_UF.SetFrameUnit",
    setterCount == 2, "found " .. setterCount)

-------------------------------------------------------------------------------
-- Exercise the real accessor bodies: they must never create the
-- ping-sensitive Lua member on the frame.
-------------------------------------------------------------------------------
local stateStart = assert(uf:find("function QUI_UF.GetFrameUnit(frame)", 1, true))
local stateEnd = assert(uf:find("\nQUI_UF.frames = {}", stateStart, true))
local stateSource = uf:sub(stateStart, stateEnd - 1)
local stateFactory = assert(loadstring([[
return function()
    local QUI_UF = {}
    local ufUnitState = setmetatable({}, { __mode = "k" })
    local function GetUFUnitState(frame)
        local state = ufUnitState[frame]
        if not state then state = {}; ufUnitState[frame] = state end
        return state
    end
]] .. stateSource .. [[
    return QUI_UF
end
]], "unitframes unit side-state"))
local sideStateUF = stateFactory()()
local button = setmetatable({}, {
    __newindex = function(t, key, value)
        assert(key ~= "unit", "side-state helper wrote button.unit")
        rawset(t, key, value)
    end,
})
sideStateUF.SetFrameUnit(button, "boss1")
check("side-state mirror returns a live unit without writing button.unit",
    sideStateUF.GetFrameUnit(button) == "boss1" and rawget(button, "unit") == nil)
sideStateUF.SetFrameUnit(button, nil)
check("side-state mirror clears without writing button.unit",
    sideStateUF.GetFrameUnit(button) == nil and rawget(button, "unit") == nil)

-------------------------------------------------------------------------------
-- No unit-frame runtime may regress to the `.unit` member or override the
-- Blizzard ping target methods. Comments are removed before the guard.
-- (castbar.lua is exempt: castbars/anchors are plain frames, not receivers,
-- and own a private .unit field the ping mixin never sees.)
-------------------------------------------------------------------------------
local function stripComments(src)
    src = src:gsub("%-%-%[%[.-%]%]", "")
    return (src:gsub("%-%-[^\n]*", ""))
end

local runtimeFiles = {
    "QUI_UnitFrames/unitframes/unitframes.lua",
    "QUI_UnitFrames/unitframes/unitframe_auras.lua",
}
for _, path in ipairs(runtimeFiles) do
    local code = stripComments(readAll(path))
    local badAccess
    for _, owner in ipairs({ "frame", "self" }) do
        if code:find("%f[%a_]" .. owner .. "%.unit%f[^%w_]")
            or code:find("%f[%a_]" .. owner .. "%s*%[%s*[\"']unit[\"']%s*%]")
        then
            badAccess = owner .. ".unit"
            break
        end
    end
    check(path .. " has no live frame .unit access",
        badAccess == nil, badAccess)
    check(path .. " does not override Blizzard ping target methods",
        code:find("GetTargetInfo%s*=") == nil
        and code:find("GetIsPingable%s*=") == nil
        and code:find("GetAllowRadialWheel%s*=") == nil)
end

print(string.format("unitframes_ping_sidestate_test: %d failed", fails))
if fails > 0 then os.exit(1) end
