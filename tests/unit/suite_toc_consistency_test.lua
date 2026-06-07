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

local function tocLuaEntries(tocPath)
    local body = assert(readFile(tocPath), "missing " .. tocPath)
    local set, order = {}, {}
    for line in (body .. "\n"):gmatch("(.-)\r?\n") do
        if line:match("%.lua$") and not line:match("^#") then
            local norm = line:gsub("\\", "/")
            assert(not set[norm], "duplicate in " .. tocPath .. ": " .. norm)
            set[norm] = true
            order[#order + 1] = norm
        end
    end
    return set, order
end

local template = assert(readFile("core/templates/subaddon_bootstrap.lua"))
local optionsSet = tocLuaEntries("QUI_Options/QUI_Options.toc")

for _, e in ipairs(manifest) do
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

-- core TOC must not reference moved dirs
local coreSet = tocLuaEntries("QUI.toc")
for norm in pairs(coreSet) do
    local dir = norm:match("^modules/([%w_]+)/")
    if dir then
        assert(dir == "layout" or dir == "ui" or dir == "integrations",
            "moved module still in QUI.toc: " .. norm)
    end
end

print("suite_toc_consistency_test OK")
