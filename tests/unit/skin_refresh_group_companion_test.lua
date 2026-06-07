-- tests/unit/skin_refresh_group_companion_test.lua
-- Run: lua tests/unit/skin_refresh_group_companion_test.lua
--
-- Source-invariant guard for the "skin-color propagation gap" fixes.
--
-- Several modules color a persistent frame from the GLOBAL skin
-- (GetSkinBorderColor/GetSkinBgColor/...) but register their refresh under a
-- NON-"skinning" Registry group. A skin/accent/border color change fires only
-- Registry:RefreshAll("skinning") (GUI:ApplyAccentColor does not broadcast), so
-- those modules would keep their old color until /reload. The fix is a COMPANION
-- registration under group = "skinning" that re-applies colors. See the memory
-- note skin-refresh-group-gap-audit. This test fails if any companion
-- registration is removed or its group is changed away from "skinning".

local EXPECTED = {
    -- Tier-1 fixes (2026-05-31):
    { "QUI_QoL/dungeon/party_keystones.lua", "keyTrackerSkin" },
    { "QUI_QoL/qol/combattimer.lua",        "combatTimerSkin" },
    { "QUI_UnitFrames/unitframes/unitframes.lua",  "unitframesSkin" },
    { "QUI_GroupFrames/groupframes/groupframes.lua","groupframesSkin" },
    { "QUI_QoL/qol/petwarning.lua",         "petWarningSkin" },
    { "QUI_QoL/qol/consumablecheck.lua",    "consumablesSkin" },
    { "QUI_Minimap/minimap/minimap.lua",        "minimapSkin" },
    { "QUI_DamageMeter/damage_meter/damage_meter.lua", "damageMeterSkin" },
    { "QUI_ResourceBars/resourcebars/resourcebars.lua", "resourceBarsSkin" },
    { "QUI_CDM/cdm/cdm_bar_renderer.lua",   "cdmBarsSkin" },
    -- Earlier same-pattern fixes (positive controls):
    { "QUI_Chat/chat/display_fallback.lua",  "chatCustomDisplaySkin" },
    { "QUI_Chat/chat/button_bar.lua",        "chatButtonBarSkin" },
    { "QUI_GroupFrames/groupframes/raidbuffs.lua",  "raidbuffsSkin" },
}

local function read(path)
    local f = assert(io.open(path, "r"), "cannot open " .. path)
    local s = f:read("*a")
    f:close()
    return s
end

local failures = 0
for _, entry in ipairs(EXPECTED) do
    local path, name = entry[1], entry[2]
    local src = read(path)
    local at = src:find('Register%("' .. name .. '"')
    if not at then
        print('FAIL: ' .. path .. ' is missing Register("' .. name .. '")')
        failures = failures + 1
    else
        -- The group = "skinning" field must appear within the registration body
        -- (from the Register( call to its closing "})"). A multi-line refresh
        -- function can push the group field well past the opening, so scan to the
        -- registration's close rather than a fixed window.
        local closeAt = src:find('}%)', at)
        local body = src:sub(at, closeAt and (closeAt + 1) or (at + 500))
        if not body:find('group%s*=%s*"skinning"') then
            print('FAIL: ' .. path .. ' registration "' .. name .. '" is not group="skinning"')
            failures = failures + 1
        end
    end
end

assert(failures == 0, failures .. ' companion skinning registration(s) missing or mis-grouped')
print('OK: skin_refresh_group_companion_test (' .. #EXPECTED .. ' registrations)')
