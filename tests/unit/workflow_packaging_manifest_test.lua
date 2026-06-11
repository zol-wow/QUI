-- Packaging guard: every sub-addon in core/addon_manifest.lua must be
-- packaged by BOTH GitHub workflows (release + dev-build), i.e. listed in
-- their suite_folders array AND covered by required_paths (TOC + bootstrap).
-- A manifest entry missing from packaging ships a core that points at an
-- absent sibling folder — the module silently never exists for users.

local manifest = assert(loadfile("core/addon_manifest.lua"))()

local WORKFLOWS = {
    ".github/workflows/release.yml",
    ".github/workflows/dev-build.yml",
}

local function readFile(p)
    local f = io.open(p, "rb"); if not f then return nil end
    local c = f:read("*a"); f:close(); return c
end

-- Extract the contents of a `name=( ... )` bash array from the workflow body.
local function bashArray(body, name, path)
    local inner = body:match(name .. "%s*=%s*%((.-)%)")
    assert(inner, path .. ": could not find bash array " .. name)
    local set = {}
    for word in inner:gmatch("%S+") do
        set[word] = true
    end
    return set
end

for _, path in ipairs(WORKFLOWS) do
    local body = assert(readFile(path), "missing workflow: " .. path)
    local folders = bashArray(body, "suite_folders", path)
    local required = bashArray(body, "required_paths", path)

    for _, e in ipairs(manifest) do
        assert(folders[e.folder],
            path .. ": manifest folder not in suite_folders: " .. e.folder)
        local toc = "build/" .. e.folder .. "/" .. e.folder .. ".toc"
        local boot = "build/" .. e.folder .. "/bootstrap.lua"
        assert(required[toc],
            path .. ": required_paths missing " .. toc)
        assert(required[boot],
            path .. ": required_paths missing " .. boot)
    end

    -- The options companions are not manifest entries but must ship too.
    assert(folders["QUI_Options"] and folders["QUI_OptionsSearch"],
        path .. ": options companions missing from suite_folders")
end

print("workflow_packaging_manifest_test OK")
