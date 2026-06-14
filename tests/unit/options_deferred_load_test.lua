-- tests/unit/options_deferred_load_test.lua
-- Run: lua tests/unit/options_deferred_load_test.lua
--
-- profile_io.lua (the profile import/export engine) and the bundled preset
-- import strings are options-only: a caller audit confirms nothing in the
-- gameplay/login path references them — their only callers are the
-- QUI_Options settings content files and the headless test harness. They must
-- therefore load via QUI_Options (LoadOnDemand), NOT in the main addon's login
-- path, so a fresh login does not parse ~190 KB of preset strings plus the
-- ~2.8k-line serialization engine that the player may never open.
--
-- This guard prevents a regression that silently re-adds either to startup.

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

-- Bundled preset import strings: out of load.xml, into QUI_Options.
check(not quiToc:find("importstrings", 1, true),
    "QUI.toc must NOT load importstrings at login (preset strings are options-only)")
for _, f in ipairs({
    "qui_editmode_base",
    "starter_profile",
}) do
    check(optionsXml:find(f, 1, true) ~= nil,
        "QUI_Options/options.xml must load importstrings\\" .. f .. ".lua")
end

-- Settings framework split (core/settings/*.lua):
--
-- These 9 are options-only — every consumer reaches them lazily (inside a
-- function) from code that only runs once the settings/layout-mode UI is open;
-- none is captured at file scope on the login path. They load via QUI_Options.
for _, f in ipairs({
    "providers", "provider_panels", "model_kit", "fields", "surfaces",
    "surface_features", "nav", "sync", "renderer",
}) do
    -- Both manifests need the "core/" prefix so e.g. provider_panels doesn't
    -- collide with the module file QUI_QoL/qol/settings/provider_panels.lua.
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
