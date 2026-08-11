-- Packaging guard: release packaging must discover every top-level runtime
-- QUI_* sibling addon with a matching TOC, then verify expected runtime files.
-- Dev-only companions such as QUI_Debug / QUI_Logger must stay excluded from
-- releases.

local manifest = assert(loadfile("core/addon_manifest.lua"))()

local WORKFLOWS = {
    ".github/workflows/release.yml",
}

local EXCLUDED_RELEASE_FOLDERS = {
    QUI_Debug = true,
    QUI_Logger = true,
}

local function readFile(path)
    local file = io.open(path, "rb")
    if not file then return nil end
    local content = file:read("*a")
    file:close()
    return content
end

local function assertContains(body, needle, message)
    assert(body:find(needle, 1, true), message .. "\nmissing: " .. needle)
end

local function assertTocGroup(folder)
    local toc = assert(readFile(folder .. "/" .. folder .. ".toc"),
        "missing companion TOC: " .. folder)
    assertContains(toc, "## Group: QUI",
        folder .. ": companion TOC should stay grouped with QUI")
end

local function discoverSuiteFolders()
    local folders = {}
    local pipe = assert(io.popen("find . -maxdepth 1 -type d -name 'QUI_*' -print | sort"))
    for path in pipe:lines() do
        local folder = path:gsub("^%./", "")
        if readFile(folder .. "/" .. folder .. ".toc") then
            folders[folder] = true
        end
    end
    pipe:close()
    return folders
end

local folders = discoverSuiteFolders()
local releaseFolders = {}
for folder in pairs(folders) do
    if not EXCLUDED_RELEASE_FOLDERS[folder] then
        releaseFolders[folder] = true
    end
end

for _, entry in ipairs(manifest) do
    -- Host-backed entries ship inside another folder's addon and have no
    -- `folder` of their own, so there is no separate shipped folder to verify.
    if entry.folder then
        assert(releaseFolders[entry.folder],
            "manifest folder is not discoverable as a shipped suite addon: " .. entry.folder)
    end
end

for _, companion in ipairs({ "QUI_Options" }) do
    assert(releaseFolders[companion],
        "required companion addon is not discoverable: " .. companion)
end

assert(folders.QUI_Debug, "QUI_Debug should exist in the repo for local diagnostics")
assert(not releaseFolders.QUI_Debug, "QUI_Debug must not be treated as a release folder")
assert(folders.QUI_Logger, "QUI_Logger should exist in the repo for local event capture")
assert(not releaseFolders.QUI_Logger, "QUI_Logger must not be treated as a release folder")
assertTocGroup("QUI_Debug")
assertTocGroup("QUI_Logger")

for folder in pairs(releaseFolders) do
    local toc = folder .. "/" .. folder .. ".toc"
    assert(readFile(toc), "discoverable suite is missing TOC: " .. toc)

    -- Every shipped suite folder is a real addon with a bootstrap. There is no
    -- data-only folder any more: QUI_OptionsSearch existed solely to hold
    -- the generated index, which ships packed inside QUI_Options now, and
    -- the ten per-locale overlay addons are root-TOC files in core/locale/.
    assert(readFile(folder .. "/bootstrap.lua"),
        "suite addon is missing bootstrap.lua: " .. folder)
end

-- The generated index is not a folder any more, so nothing above would notice
-- it going missing from the packaged build.
assert(readFile("QUI_Options/search_cache.lua"),
    "generated search index is missing: QUI_Options/search_cache.lua")

for _, path in ipairs(WORKFLOWS) do
    local body = assert(readFile(path), "missing workflow: " .. path)

    assertContains(body, "find . -maxdepth 1 -type d -name 'QUI_*' -print",
        path .. ": workflow should discover suite folders dynamically")
    assertContains(body, "excluded_suite_folders=(",
        path .. ": workflow should declare release exclusions")
    assertContains(body, "QUI_Debug",
        path .. ": workflow should exclude debug companion addon")
    assertContains(body, "QUI_Logger",
        path .. ": workflow should exclude logger companion addon")
    assertContains(body, "! is_excluded_suite_folder \"$folder\"",
        path .. ": workflow should filter excluded suite folders")
    assertContains(body, '[[ -f "$folder/$folder.toc" ]]',
        path .. ": workflow should only ship folders with matching TOCs")
    assertContains(body, "--exclude='tests'",
        path .. ": workflow should exclude tests from rsync copies")
    assertContains(body, "--exclude='tools'",
        path .. ": workflow should exclude tools from rsync copies")
    assertContains(body, "build/QUI_Debug",
        path .. ": workflow should fail if debug addon is packaged")
    assertContains(body, "build/QUI_Logger",
        path .. ": workflow should fail if logger addon is packaged")
    assertContains(body, "Non-runtime directory packaged",
        path .. ": workflow should guard against test/tool/doc directories in build output")
    assertContains(body, 'required_paths+=("build/$folder/$folder.toc")',
        path .. ": workflow should require every discovered TOC")
    assertContains(body, 'required_paths+=("build/$folder/bootstrap.lua")',
        path .. ": workflow should require bootstrap.lua for runtime suites")
    assertContains(body, "build/QUI_Options/search_cache.lua",
        path .. ": workflow should require the packed search index in the build")
    -- Deliberately not pinning where the version expression comes from: the
    -- guard here is that the zip carries the main addon plus every discovered
    -- sibling, which is independent of whether the tag was parsed by a step
    -- output or a job output.
    assertContains(body, '.zip QUI "${suite_folders[@]}"',
        path .. ": workflow should zip every discovered suite folder")
    assertContains(body, "zip -r ../QUI-",
        path .. ": workflow should name the zip after the release tag")
    assertContains(body, "METADATA=$(jq -cn",
        path .. ": workflow should build compact CurseForge metadata JSON")
    assertContains(body, "printf '%s\\n' \"$METADATA\" | jq -e . >/dev/null",
        path .. ": workflow should validate CurseForge metadata JSON before upload")
    assertContains(body, '--form-string "metadata=${METADATA}"',
        path .. ": workflow should upload CurseForge metadata as literal form data")

    assert(not body:find("QUI_ActionBars QUI_CDM", 1, true),
        path .. ": workflow should not carry a static suite_folders list")
    assert(not body:find('-F "metadata=${METADATA}"', 1, true),
        path .. ": workflow should not let curl parse metadata as form syntax")
end

print("workflow_packaging_manifest_test OK")
