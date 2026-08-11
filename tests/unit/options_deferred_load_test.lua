-- tests/unit/options_deferred_load_test.lua
-- Run: lua tests/unit/options_deferred_load_test.lua
--
-- profile_io.lua (the profile import/export engine) and the bundled preset
-- import strings are options-only: a caller audit confirms nothing in the
-- gameplay/login path references them — their only callers are the
-- QUI_Options settings content files and the headless test harness. They must
-- therefore load via QUI_Options (LoadOnDemand), NOT in the main addon's login
-- path, so a fresh login does not parse preset strings plus the ~2.8k-line
-- serialization engine that the player may never open.
--
-- ONE exception since the lazy-seed inversion: importstrings/
-- starter_profile.lua IS the fresh-install seed source (decoded by
-- core/new_profile_defaults.lua in the OnNewProfile hook, direct
-- LibDeflate/AceSerializer — not profile_io), so its ~44 KB string loads at
-- login, replacing the 347 KB literal seed table that used to load there.
--
-- This guard prevents a regression that silently re-adds the rest to startup.

local function readAll(path)
    local file = assert(io.open(path, "rb"), "failed to open " .. path)
    local data = file:read("*a")
    file:close()
    return (data:gsub("\r\n", "\n"))
end

-- Strip XML comments so the checks assert what is *loaded*, not what is merely
-- *mentioned* — documentation comments are free to reference these files when
-- explaining where they moved. Also normalize backslash path separators
-- (QUI.toc and options.xml use backslashes) so a single forward-slash needle
-- matches either manifest. TOC '#' comment lines are skipped below.
local function loadManifest(path)
    local text = readAll(path):gsub("<!%-%-.-%-%->", "") -- drop XML comments
    return (text:gsub("\\", "/"))                         -- normalize separators
end

-- Drop TOC comment lines ("# == section ==") so needles only match entries.
local quiToc = {}
for line in loadManifest("QUI.toc"):gmatch("[^\n]*") do
    if not line:match("^%s*#") then
        quiToc[#quiToc + 1] = line
    end
end
quiToc = table.concat(quiToc, "\n")
local optionsXml = {}
for line in loadManifest("QUI_Options/QUI_Options.toc"):gmatch("[^\n]*") do
    if not line:match("^%s*#") then
        optionsXml[#optionsXml + 1] = line
    end
end
optionsXml = table.concat(optionsXml, "\n")

local failures = {}
local function check(cond, msg)
    if not cond then failures[#failures + 1] = msg end
end

-- profile_io.lua: out of the main-addon login path, into QUI_Options.
check(not quiToc:find("profile_io", 1, true),
    "QUI.toc must NOT load profile_io.lua (it is options-only)")
check(optionsXml:find("profile_io", 1, true) ~= nil,
    "QUI_Options.toc must load core\\profile_io.lua")

-- Bundled preset import strings: qui_editmode_base stays options-only;
-- starter_profile is root-owned (lazy-seed source — see header).
check(quiToc:find("importstrings/starter_profile.lua", 1, true) ~= nil,
    "QUI.toc must load importstrings\\starter_profile.lua (lazy-seed source)")
check(not quiToc:find("qui_editmode_base", 1, true),
    "QUI.toc must NOT load qui_editmode_base at login (options-only)")
check(optionsXml:find("qui_editmode_base", 1, true) ~= nil,
    "QUI_Options/options.xml must load importstrings\\qui_editmode_base.lua")
check(not optionsXml:find("starter_profile", 1, true),
    "QUI_Options.toc must not double-load starter_profile.lua (root owns it; the Profiles tab reads the same QUI.imports entry)")

-- Settings framework split (core/settings/*.lua):
--
-- These 8 are options-only — every consumer reaches them lazily (inside a
-- function) from code that only runs once the settings/layout-mode UI is open;
-- none is captured at file scope on the login path. They load via QUI_Options.
for _, f in ipairs({
    "providers", "provider_panels", "model_kit", "fields", "surfaces",
    "surface_features", "nav", "renderer",
}) do
    -- Both manifests need the "core/" prefix so e.g. provider_panels doesn't
    -- collide with the module file modules/qol/settings/provider_panels.lua.
    check(not quiToc:find("core/settings/" .. f .. ".lua", 1, true),
        "QUI.toc must NOT load core/settings/" .. f .. ".lua (options-only)")
    check(optionsXml:find("core/settings/" .. f .. ".lua", 1, true) ~= nil,
        "QUI_Options/options.xml must load core/settings/" .. f .. ".lua")
end

-- These 7 MUST remain on the login path: feature registration runs at login
-- (module do-blocks call Registry:RegisterFeature(Schema.Feature{...})), and
-- Schema.Feature -> CloneTable needs Util at that moment. pins is touched by
-- core/main.lua on profile change. Deferring any of these silently breaks
-- registration/runtime (nil-guards degrade instead of erroring).
for _, f in ipairs({
    "util", "render_adapters", "registry", "schema", "provider_features",
    "pins", "pins_lifecycle",
}) do
    check(quiToc:find("core/settings/" .. f .. ".lua", 1, true) ~= nil,
        "QUI.toc MUST keep core/settings/" .. f .. ".lua on the login path")
end

if #failures > 0 then
    for _, msg in ipairs(failures) do
        io.stderr:write("FAIL: " .. msg .. "\n")
    end
    io.stderr:write(("options_deferred_load_test: %d failure(s)\n"):format(#failures))
    os.exit(1)
end

print("options_deferred_load_test: OK")
