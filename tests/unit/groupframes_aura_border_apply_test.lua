-- tests/unit/groupframes_aura_border_apply_test.lua
-- Run: lua tests/unit/groupframes_aura_border_apply_test.lua
-- Extracts the border helpers from groupframes_aura_render.lua and verifies the
-- debuff-type border applies ONLY for HARMFUL elements with a valid aura instance
-- and an available curve, tints via SetVertexColor + suppresses the skin border,
-- and otherwise leaves the skin border for the caller.

local loadstring = loadstring or load

local function readAll(path)
    local f = assert(io.open(path, "rb"))
    local d = f:read("*a"); f:close()
    return d:gsub("\r\n", "\n")
end

local source = readAll("QUI_GroupFrames/groupframes/groupframes_aura_render.lua")
local s = assert(source:find("-- >>> QUI_TEST_EXTRACT AuraBorderHelpers", 1, true), "begin sentinel")
local fnStart = assert(source:find("\n", s)) + 1
local nl = assert(source:find("\n%-%- <<< QUI_TEST_EXTRACT AuraBorderHelpers", fnStart), "end sentinel")
local fnSource = source:sub(fnStart, nl - 1)

local chunk = table.concat({
    "local C_UnitAuras = _CUA",
    -- Production defines this file-locally (above the extracted section);
    -- the standalone chunk needs its own. Mocks here are never secret.
    -- (RenderIsSecretValue: PTR7 wave renamed the wrapper so the bare
    -- builtin guard name is never file-bound — see .taintrc extra_guards.)
    "local RenderIsSecretValue = function() return false end",
    fnSource,
    "return ApplyDebuffTypeBorder, ShowTypeBorder, HideTypeBorder",
}, "\n")
-- inject C_UnitAuras stub via a factory
local factory = assert(loadstring("return function(_CUA)\n" .. chunk .. "\nend", "auraBorderHelpers"))()

local function newTex()
    local t = { shown = false }
    function t:SetVertexColor(r,g,b,a) self.v = {r,g,b,a} end
    function t:Show() self.shown = true end
    function t:Hide() self.shown = false end
    return t
end
local function newIcon(bridged)
    local ic = { _quiBridged = bridged, backdropColor = nil,
        _quiTypeBorder = { top=newTex(), bottom=newTex(), left=newTex(), right=newTex() } }
    function ic:SetBackdropBorderColor(r,g,b,a) self.backdropColor = {r,g,b,a} end
    return ic
end
-- secret-ish color mock with GetRGBA (mirrors ColorMixin)
local color = { GetRGBA = function() return 1, 0, 0, 1 end }
local CUA = { GetAuraDispelTypeColor = function(unit, id, curve) return color end }
local ApplyDebuffTypeBorder, ShowTypeBorder, HideTypeBorder = factory(CUA)

local curve = {}  -- opaque, non-nil
local harmful = { auraType = "HARMFUL" }
local helpful = { auraType = "HELPFUL" }
local aura = { auraInstanceID = 42 }

-- HARMFUL + instance + curve -> applies type border, returns true
local ic = newIcon(false)
assert(ApplyDebuffTypeBorder(ic, "raid1", harmful, aura, curve) == true, "harmful applies")
assert(ic._quiTypeBorder.top.shown == true, "top edge shown")
assert(ic._quiTypeBorder.top.v[1] == 1 and ic._quiTypeBorder.top.v[2] == 0, "edge tinted from color:GetRGBA")
assert(ic.backdropColor and ic.backdropColor[4] == 0, "skin backdrop border suppressed (alpha 0)")

-- HELPFUL -> false, no edges
local ic2 = newIcon(false)
assert(ApplyDebuffTypeBorder(ic2, "raid1", helpful, aura, curve) == false, "helpful skipped")
assert(ic2._quiTypeBorder.top.shown == false, "no edges for buff")

-- externally bridged -> false
local ic3 = newIcon(true)
assert(ApplyDebuffTypeBorder(ic3, "raid1", harmful, aura, curve) == false, "bridged skipped")

-- no curve -> false
local ic4 = newIcon(false)
assert(ApplyDebuffTypeBorder(ic4, "raid1", harmful, aura, nil) == false, "no curve skipped")

-- no instance id -> false
local ic5 = newIcon(false)
assert(ApplyDebuffTypeBorder(ic5, "raid1", harmful, { auraInstanceID = nil }, curve) == false, "no instID skipped")

-- HideTypeBorder hides edges
HideTypeBorder(ic)
assert(ic._quiTypeBorder.top.shown == false, "HideTypeBorder hides edges")

print("PASS: groupframes_aura_border_apply")
