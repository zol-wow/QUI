local ROOT = "."
local CACHE_PATH = "QUI_Options/search_cache.lua"

local KNOWN_ZERO_SETTING_FEATURES = {
    autohidePage = true,
    barHidingPage = true,
    clickCastPage = true,
    frameLevelsPage = true,
    skinningPage = true,
    thirdPartyAnchoring = true,
}

local function normalize_path(path)
    path = tostring(path or ""):gsub("\\", "/")
    path = path:gsub("/+", "/")
    path = path:gsub("^%./", "")
    return path
end

local function read_file(path)
    local handle, err = io.open(path, "r")
    if not handle then
        return nil, err
    end
    local text = handle:read("*a")
    handle:close()
    return text
end

local function collect_lua_files()
    local is_windows = package.config:sub(1, 1) == "\\"
    local command
    if is_windows then
        command = 'powershell -NoProfile -Command "Get-ChildItem -Path modules,QUI_Options -Recurse -File -Filter *.lua | ForEach-Object { $_.FullName }"'
    else
        command = 'find modules QUI_Options -type f -name "*.lua"'
    end

    local pipe, err = io.popen(command)
    if not pipe then
        return nil, err
    end

    local files = {}
    for line in pipe:lines() do
        line = normalize_path(line)
        if line ~= "" then
            files[#files + 1] = line
        end
    end

    local ok, _, code = pipe:close()
    if ok == nil then
        return nil, "file discovery command failed with exit code " .. tostring(code)
    end
    table.sort(files)
    return files
end

local function add_ref(refs, id, path, kind)
    if type(id) ~= "string" or id == "" then
        return
    end
    local ref = refs[id]
    if not ref then
        ref = { paths = {}, kinds = {} }
        refs[id] = ref
    end
    ref.paths[path] = true
    ref.kinds[kind] = true
end

local function scan_source_features(files)
    local registered = {}
    local tile_refs = {}
    local scan_errors = {}

    for _, path in ipairs(files) do
        local text, err = read_file(path)
        if not text then
            scan_errors[#scan_errors + 1] = path .. ": " .. tostring(err)
        else
            for id in text:gmatch("ProviderFeatures:Register%s*%(%s*%{.-id%s*=%s*\"([^\"]+)\"") do
                add_ref(registered, id, path, "ProviderFeatures")
            end
            for id in text:gmatch("SurfaceFeatures:Register%s*%(%s*%{.-id%s*=%s*\"([^\"]+)\"") do
                add_ref(registered, id, path, "SurfaceFeatures")
            end
            for block in text:gmatch("Registry:RegisterFeature%s*%(%s*Schema%.Feature%s*%(%s*%{(.-)sections%s*=") do
                local id = block:match("id%s*=%s*\"([^\"]+)\"")
                add_ref(registered, id, path, "Registry")
            end

            if path:match("/QUI_Options/tiles/") or path:match("^QUI_Options/tiles/") or path:match("/QUI_Options/init%.lua$") or path == "QUI_Options/init.lua" then
                for id in text:gmatch("featureId%s*=%s*\"([^\"]+)\"") do
                    add_ref(tile_refs, id, path, "FeatureTile")
                end
            end
        end
    end

    return registered, tile_refs, scan_errors
end

local function load_cache()
    local ns = {}
    local chunk, err = loadfile(CACHE_PATH)
    if not chunk then
        return nil, err
    end
    local ok, run_err = pcall(chunk, "QUI", ns)
    if not ok then
        return nil, run_err
    end
    if type(ns.QUI_SearchCache) ~= "table" then
        return nil, CACHE_PATH .. " did not define ns.QUI_SearchCache"
    end
    return ns.QUI_SearchCache
end

local function count_by_feature(entries)
    local counts = {}
    for _, entry in ipairs(entries or {}) do
        local id = entry.featureId
        if type(id) == "string" and id ~= "" then
            counts[id] = (counts[id] or 0) + 1
        end
    end
    return counts
end

local function sorted_ids(refs)
    local ids = {}
    for id in pairs(refs or {}) do
        ids[#ids + 1] = id
    end
    table.sort(ids)
    return ids
end

local function sorted_keys(tbl)
    local keys = {}
    for key in pairs(tbl or {}) do
        keys[#keys + 1] = key
    end
    table.sort(keys)
    return keys
end

local function format_ref(ref)
    if type(ref) ~= "table" then
        return ""
    end
    local paths = sorted_keys(ref.paths)
    if #paths == 0 then
        return ""
    end
    return " (" .. table.concat(paths, ", ") .. ")"
end

local function entry_haystack(entry)
    local parts = {
        entry.label or "",
        entry.tabName or "",
        entry.subTabName or "",
        entry.sectionName or "",
        entry.featureId or "",
        entry.providerKey or "",
        entry.category or "",
        entry.surfaceTabKey or "",
        entry.surfaceUnitKey or "",
    }
    if type(entry.keywords) == "table" then
        for _, keyword in ipairs(entry.keywords) do
            parts[#parts + 1] = tostring(keyword)
        end
    end
    return table.concat(parts, " "):lower()
end

local function split_query(query)
    local words = {}
    for word in tostring(query or ""):lower():gmatch("%S+") do
        words[#words + 1] = word
    end
    return words
end

local function count_query_hits(cache, query)
    local words = split_query(query)
    if #words == 0 then
        return 0
    end

    local total = 0
    for _, list in ipairs({ cache.settings or {}, cache.navigation or {} }) do
        for _, entry in ipairs(list) do
            local haystack = entry_haystack(entry)
            local matched = true
            for _, word in ipairs(words) do
                if not haystack:find(word, 1, true) then
                    matched = false
                    break
                end
            end
            if matched then
                total = total + 1
            end
        end
    end
    return total
end

local args = { ... }
local strict_tiles = false
local verbose = false
local queries = {}

local index = 1
while index <= #args do
    local arg = args[index]
    if arg == "--strict-tiles" then
        strict_tiles = true
    elseif arg == "--verbose" then
        verbose = true
    elseif arg == "--query" then
        index = index + 1
        queries[#queries + 1] = args[index] or ""
    elseif arg:match("^%-%-query=") then
        queries[#queries + 1] = arg:match("^%-%-query=(.*)$") or ""
    elseif arg == "--help" or arg == "-h" then
        print("Usage: lua tools/audit_search_cache.lua [--strict-tiles] [--verbose] [--query TEXT]")
        print("Run from the repository root after lua tools/generate_search_cache.lua.")
        os.exit(0)
    else
        io.stderr:write("unknown argument: " .. tostring(arg) .. "\n")
        os.exit(2)
    end
    index = index + 1
end

local cache, cache_err = load_cache()
if not cache then
    io.stderr:write("failed to load " .. CACHE_PATH .. ": " .. tostring(cache_err) .. "\n")
    os.exit(2)
end

local files, file_err = collect_lua_files()
if not files then
    io.stderr:write("failed to discover Lua files under " .. ROOT .. ": " .. tostring(file_err) .. "\n")
    os.exit(2)
end

local registered, tile_refs, scan_errors = scan_source_features(files)
if #scan_errors > 0 then
    io.stderr:write("source scan reported " .. tostring(#scan_errors) .. " error(s):\n")
    for _, err in ipairs(scan_errors) do
        io.stderr:write("  " .. err .. "\n")
    end
    os.exit(2)
end

local setting_counts = count_by_feature(cache.settings)
local nav_counts = count_by_feature(cache.navigation)
local errors = {}
local warnings = {}

for _, id in ipairs(sorted_ids(registered)) do
    if (setting_counts[id] or 0) == 0 then
        local message = "registered feature has zero settings: " .. id .. format_ref(registered[id])
        if KNOWN_ZERO_SETTING_FEATURES[id] then
            warnings[#warnings + 1] = message .. " [known]"
        else
            errors[#errors + 1] = message
        end
    elseif (setting_counts[id] or 0) <= 5 then
        warnings[#warnings + 1] = "registered feature has low settings count: " .. id .. "=" .. tostring(setting_counts[id]) .. format_ref(registered[id])
    end
end

for _, id in ipairs(sorted_ids(tile_refs)) do
    if (setting_counts[id] or 0) == 0 then
        local message = "tile feature ref has zero settings: " .. id .. format_ref(tile_refs[id])
        if strict_tiles then
            errors[#errors + 1] = message
        else
            warnings[#warnings + 1] = message
        end
    end
end

for _, query in ipairs(queries) do
    local hits = count_query_hits(cache, query)
    if hits == 0 then
        errors[#errors + 1] = "query has zero cache hits: " .. query
    elseif verbose then
        print("query hits: " .. query .. "=" .. tostring(hits))
    end
end

print("Search cache audit")
print("  settings entries: " .. tostring(#(cache.settings or {})))
print("  navigation entries: " .. tostring(#(cache.navigation or {})))
print("  source registered features: " .. tostring(#sorted_ids(registered)))
print("  tile feature refs: " .. tostring(#sorted_ids(tile_refs)))

if verbose then
    print("")
    print("Registered feature counts:")
    for _, id in ipairs(sorted_ids(registered)) do
        print("  " .. id .. ": settings=" .. tostring(setting_counts[id] or 0) .. ", navigation=" .. tostring(nav_counts[id] or 0))
    end
end

if #warnings > 0 then
    print("")
    print("Warnings:")
    for _, warning in ipairs(warnings) do
        print("  " .. warning)
    end
end

if #errors > 0 then
    print("")
    print("Errors:")
    for _, err in ipairs(errors) do
        print("  " .. err)
    end
    os.exit(1)
end

print("")
print("OK: no registered settings feature is missing from the generated cache.")
