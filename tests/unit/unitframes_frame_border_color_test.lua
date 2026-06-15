-- tests/unit/unitframes_frame_border_color_test.lua
-- Verifies the unit-frame MAIN border is wired into the per-frame border-color
-- model: render reads per-frame settings, the Frame subtab exposes a picker
-- (prefix ""), and a "Frame" entry is registered in the UF border registry so it
-- appears in Appearance > Border Coloring.
-- Run from repo root: lua tests/unit/unitframes_frame_border_color_test.lua

local failures = 0
local function check(name, ok, detail)
    if ok then print(("  ok  %s"):format(name))
    else failures = failures + 1; print(("FAIL  %s  %s"):format(name, detail or "")) end
end

local function readFile(path)
    local f = assert(io.open(path, "r"), "cannot open " .. path)
    local s = f:read("*a"); f:close(); return s
end

local render = readFile("QUI_UnitFrames/unitframes/unitframes.lua")
local schema = readFile("QUI_UnitFrames/unitframes/settings/unit_frames_schema.lua")

-- 1. Render: no no-arg GetSkinBorderColor() remains; per-frame form used >= 4x.
local noArg = 0
for _ in render:gmatch("GetSkinBorderColor%(%)") do noArg = noArg + 1 end
check("render has no no-arg GetSkinBorderColor()", noArg == 0,
    "found " .. noArg .. " no-arg call(s)")

local perFrame = 0
for _ in render:gmatch('GetSkinBorderColor%(settings,%s*""%)') do perFrame = perFrame + 1 end
check('render uses GetSkinBorderColor(settings, "") >= 4 times', perFrame >= 4,
    "found " .. perFrame)

-- 2. Frame subtab: per-frame picker bound to unit.unitDB, prefix "".
local attachPicker = schema:find('QUI_BorderControl%.Attach%(%s*gui,%s*card%.frame,%s*unit%.unitDB,%s*""')
check('Frame subtab attaches per-frame picker (unit.unitDB, "")', attachPicker ~= nil)

-- 3. Registry: a "Frame" entry under category "Unit Frames" with key "unitFrame".
check('registry has key = "unitFrame"', render:find('key%s*=%s*"unitFrame"') ~= nil)
check('registry "Frame" label present', render:find('label%s*=%s*"Frame"') ~= nil)
check('CollectFrameUnits collector present', render:find("CollectFrameUnits") ~= nil)

if failures > 0 then
    print(("\n%d FAILURE(S)"):format(failures)); os.exit(1)
else
    print("\nAll checks passed."); os.exit(0)
end
