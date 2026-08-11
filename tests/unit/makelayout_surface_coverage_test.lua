-- tests/unit/makelayout_surface_coverage_test.lua
-- Run: lua tests/unit/makelayout_surface_coverage_test.lua
--
-- Every provider file delegates its MakeLayout to the core builder
-- (core/settings_layout_shared.lua). REGRESSION CLASS THIS GUARDS: the
-- MakeLayout consolidation dropped per-file extras (qol/click-cast L.intro)
-- that only surfaced as in-game nil-call crashes at panel build — headless
-- gates never render panels. So: every `L.<method>(` a provider body calls
-- must exist on the core builder surface, or be added by that file itself
-- (click_cast's placeCustom wrapper / offset alias pattern).

local function readFile(path)
    local fh = assert(io.open(path, "rb"), "failed to open " .. path)
    local text = fh:read("*a")
    fh:close()
    return text
end

-- Core builder surface: function L.x(...) defs + L.x = assignments.
local core = readFile("core/settings_layout_shared.lua")
local surface = {}
for m in core:gmatch("function L%.([%w_]+)") do surface[m] = true end
for m in core:gmatch("\n%s*L%.([%w_]+)%s*=") do surface[m] = true end
assert(surface.headerAt and surface.sectionAt and surface.closeSection
    and surface.placeCustom and surface.finish and surface.relayoutSections
    and surface.sections and surface.intro and surface.getY and surface.setY,
    "core builder surface incomplete — did a method get renamed?")

-- Every file that builds layouts through the shared builder (directly or via
-- the modules/ui wrapper).
local p = io.popen([[grep -rl "QUI_SettingsLayoutShared.MakeLayout\|QUI_ModulesSettingsLayout.MakeLayout" --include=*.lua . 2>/dev/null | grep -v tests/]])
local files = {}
for line in p:lines() do files[#files + 1] = (line:gsub("^%./", "")) end
p:close()
assert(#files >= 15, "consumer discovery broke (found " .. #files .. ")")

local failures = {}
for _, path in ipairs(files) do
    if path ~= "core/settings_layout_shared.lua" then
        local src = readFile(path)
        -- methods this file adds/aliases onto a layout table itself
        local localAdds = {}
        for m in src:gmatch("function L%.([%w_]+)") do localAdds[m] = true end
        for m in src:gmatch("L%.([%w_]+)%s*=") do localAdds[m] = true end
        for m in src:gmatch("L%.([%w_]+)%s*%(") do
            if not surface[m] and not localAdds[m] then
                failures[#failures + 1] = path .. ": L." .. m .. "() not on core builder surface"
            end
        end
    end
end

assert(#failures == 0, "\n" .. table.concat(failures, "\n"))
print("PASS makelayout_surface_coverage_test")
