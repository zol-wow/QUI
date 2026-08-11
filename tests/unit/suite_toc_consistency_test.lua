-- Permanent guard for the multi-addon suite:
--  * every manifest entry has a folder, TOC, bootstrap-first, Dependencies: QUI
--  * LoadOnDemand flag matches manifest class
--  * every .lua on disk under a sub-addon belongs to exactly one TOC
--    (its own, or QUI_Options.toc for settings/ files)
--  * core QUI.toc references no moved module paths
--  * bootstrap.lua files are byte-identical to the template

local manifest = assert(loadfile("core/addon_manifest.lua"))()

local function readFile(p)
    local f = io.open(p, "rb"); if not f then return nil end
    local c = f:read("*a"); f:close(); return c
end

-- Parse a TOC's .lua file lines. A file line is "<path>.lua" optionally
-- followed by whitespace + a per-file directive tag like "[Bootstrap]" (a
-- 12.1 per-file load tier). The tag is stripped before recording the path;
-- `tier` records true when the [Bootstrap] tag was present.
local function tocLuaEntries(tocPath)
    local body = assert(readFile(tocPath), "missing " .. tocPath)
    local set, order, tier = {}, {}, {}
    for line in (body .. "\n"):gmatch("(.-)\r?\n") do
        if not line:match("^%s*#") then
            -- Match a .lua path, then an optional trailing " [Bootstrap]" tag.
            local path, tag = line:match("^(%S+%.lua)%s*(%[%w+%])%s*$")
            if not path then
                path = line:match("^(%S+%.lua)%s*$")
            end
            if path then
                local norm = path:gsub("\\", "/")
                assert(not set[norm], "duplicate in " .. tocPath .. ": " .. norm)
                set[norm] = true
                order[#order + 1] = norm
                tier[norm] = (tag == "[Bootstrap]")
            end
        end
    end
    return set, order, tier
end

local template = assert(readFile("core/templates/subaddon_bootstrap.lua"))
local optionsSet = tocLuaEntries("QUI_Options/QUI_Options.toc")

for _, e in ipairs(manifest) do
    -- Host-backed entries ship inside another addon's folder and have no
    -- `folder` field, so the folder/TOC/bootstrap/disk-coverage checks below
    -- (which require a sibling folder + its own .toc) don't apply to them.
    if e.folder then
        local toc = e.folder .. "/" .. e.folder .. ".toc"
        local body = assert(readFile(toc), "missing " .. toc)
        assert(body:match("## Dependencies: QUI"), e.folder .. ": Dependencies")
        local isLOD = body:match("## LoadOnDemand: 1") ~= nil
        assert(isLOD == (e.class == "lod"), e.folder .. ": LoadOnDemand mismatch vs manifest")
        local set, order = tocLuaEntries(toc)
        assert(order[1] == "bootstrap.lua", e.folder .. ": bootstrap must be first")
        assert(readFile(e.folder .. "/bootstrap.lua") == template, e.folder .. ": bootstrap drift")

        -- disk coverage: every .lua under the folder is in exactly one TOC
        local p = io.popen(('find %q -name "*.lua" -type f'):format(e.folder))
        for path in p:lines() do
            local rel = path:gsub("^" .. e.folder .. "/", "")
            local inOwn = set[rel] or rel == "bootstrap.lua"
            local optRel = "../" .. e.folder .. "/" .. rel
            local inOptions = optionsSet[optRel]
            assert(inOwn or inOptions, "orphan file (in no TOC): " .. path)
            assert(not (inOwn and inOptions), "double-loaded file: " .. path)
        end
        p:close()
    end
end

-- core TOC must not reference sub-addon-owned module dirs.
-- Dirs legitimately in QUI.toc: always-core dirs (layout/ui/integrations) plus
-- the former QUI_UI bundle dirs now shipped inside the main addon as coreModules
-- (skinning/datatexts/minimap/infobar/qol/alts/combat/dungeon/trackers/utility).
local CORE_MODULE_DIRS = {
    layout = true, ui = true, integrations = true,
    skinning = true, datatexts = true, minimap = true, infobar = true,
    qol = true, alts = true, combat = true, dungeon = true,
    trackers = true, utility = true,
}
local coreSet = tocLuaEntries("QUI.toc")
for norm in pairs(coreSet) do
    local dir = norm:match("^modules/([%w_]+)/")
    if dir then
        assert(CORE_MODULE_DIRS[dir],
            "sub-addon module still in QUI.toc: " .. norm)
    end
end

-- Group 1 guard: no shipped folder exists just to hold generated data. The
-- English search index used to be its own LoadOnDemand addon
-- (QUI_OptionsSearch), one folder for one deferral point; it ships packed
-- inside QUI_Options now and framework.lua compiles it on first search. The
-- ten QUI_OptionsSearch_<loc> overlay addons are retired the same way —
-- their chunks are root-TOC files in core/locale/ because
-- core/locale/locale.lua captures ns.LocaleData.active as an upvalue at login.
do
    local p = io.popen('ls -d QUI_OptionsSearch* 2>/dev/null')
    local stray = p:read("*l")
    p:close()
    assert(stray == nil,
        "search-index addon folders are retired (the index is packed into "
            .. "QUI_Options/search_cache.lua): " .. tostring(stray))

    local optionsToc = tocLuaEntries("QUI_Options/QUI_Options.toc")
    assert(optionsToc["search_cache.lua"],
        "QUI_Options.toc must load search_cache.lua — without it the search "
            .. "box only ever finds the tile-seeded routes")
end

print("suite_toc_consistency_test OK")
