-- tests/unit/dispel_bleed_seed_test.lua
-- Run: lua5.1 tests/unit/dispel_bleed_seed_test.lua
--
-- IconLayout.SeedDispelColors(tbl) seeds all 5 dispel-type default colors
-- (Magic/Curse/Disease/Poison/Bleed) from the canonical DISPEL_DEFAULT_COLORS
-- palette into tbl, without clobbering any color already present. This is
-- the helper group_frames_schema.lua's EnsureDispelColors calls so the
-- settings-card dispel.colors seed picks up Bleed alongside the original 4.

local envmod = dofile("tools/_addon_env.lua")
local ns = envmod.LoadCore()
envmod.LoadAddonFile("QUI_GroupFrames/groupframes/group_frames_icon_layout.lua", "QUI_GroupFrames", ns)
local IL = ns.QUI_GroupFrameIconLayout

local failures = 0
local function check(n, ok, d)
    if ok then print("  ok  " .. n)
    else failures = failures + 1; print("FAIL  " .. n .. " " .. (d or "")) end
end

check("IconLayout loaded", type(IL) == "table")
check("DISPEL_DEFAULT_COLORS.Bleed canonical", type(IL.DISPEL_DEFAULT_COLORS) == "table"
    and type(IL.DISPEL_DEFAULT_COLORS.Bleed) == "table"
    and IL.DISPEL_DEFAULT_COLORS.Bleed[1] == 0.8
    and IL.DISPEL_DEFAULT_COLORS.Bleed[2] == 0.0
    and IL.DISPEL_DEFAULT_COLORS.Bleed[3] == 0.0
    and IL.DISPEL_DEFAULT_COLORS.Bleed[4] == 1)

do
    local t = {}
    IL.SeedDispelColors(t)
    check("seeds Bleed", type(t.Bleed) == "table" and t.Bleed[1] == 0.8 and t.Bleed[2] == 0.0,
        tostring(t.Bleed and t.Bleed[1]))
    check("seeds Magic", type(t.Magic) == "table")
    check("seeds Curse", type(t.Curse) == "table")
    check("seeds Disease", type(t.Disease) == "table")
    check("seeds Poison", type(t.Poison) == "table")
    check("keeps existing", (function()
        local u = { Magic = { 1, 1, 1, 1 } }
        IL.SeedDispelColors(u)
        return u.Magic[1] == 1
    end)())
end

check("non-table input returned unchanged", IL.SeedDispelColors(nil) == nil)

print("dispel_bleed_seed_test " .. (failures == 0 and "OK" or "FAILED"))
os.exit(failures == 0 and 0 or 1)
