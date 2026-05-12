-- tests/taint/config.lua
-- Loader for .taintrc.lua. Returns a config table with sane defaults if the
-- file is missing.

local M = {}

local _unpack = table.unpack or unpack  -- Lua 5.1 compat

local DEFAULT_IGNORE_PATHS = {
    "libs/",          -- vendored libraries
    "tests/",         -- analyzer fixtures often deliberately unsafe
    "importstrings/", -- generated content
}

local DEFAULT_COVERAGE = {
    secretWhenCooldownsRestricted = true,
    isSecretReturn = true,
    secretArguments_restricted = true,
}

local function defaults()
    return {
        strict_paths = {},
        ignore_paths = { _unpack(DEFAULT_IGNORE_PATHS) },
        coverage = {
            secretWhenCooldownsRestricted = DEFAULT_COVERAGE.secretWhenCooldownsRestricted,
            isSecretReturn = DEFAULT_COVERAGE.isSecretReturn,
            secretArguments_restricted = DEFAULT_COVERAGE.secretArguments_restricted,
        },
        extra_safe_sinks = {},
        extra_unwraps = {},
        clean_fields = {},
    }
end

--- Load config from a Lua source string. Returns the loaded config table on
--- success, or nil if the source is malformed.
--- @param source string|nil  Lua source. nil → defaults.
--- @return table|nil
function M.loadFromString(source)
    if not source then return defaults() end
    local chunk, err = (rawget(_G, "loadstring") or load)(source, "taintrc")
    if not chunk then return nil end
    local ok, result = pcall(chunk)
    if not ok or type(result) ~= "table" then return nil end
    -- Merge with defaults so partial configs work.
    -- Top-level list keys replace the default (user intent). The `coverage`
    -- sub-table is deep-merged field-by-field so a partial override doesn't
    -- silently disable the unmentioned coverage tiers.
    local merged = defaults()
    for k, v in pairs(result) do
        if k == "coverage" and type(v) == "table" then
            -- Per-key merge: user's coverage entries override defaults;
            -- defaults preserved for unspecified keys.
            for ck, cv in pairs(v) do
                merged.coverage[ck] = cv
            end
        else
            merged[k] = v
        end
    end
    return merged
end

--- Load .taintrc.lua from a file path. Returns defaults if file missing.
function M.loadFromFile(path)
    local f = io.open(path, "rb")
    if not f then return defaults() end
    local src = f:read("*a")
    f:close()
    return M.loadFromString(src) or defaults()
end

--- Is the given file path under a strict_paths prefix?
function M.isStrictPath(cfg, filePath)
    -- Normalize backslashes to forward slashes for comparison
    local p = filePath:gsub("\\", "/")
    for _, prefix in ipairs(cfg.strict_paths) do
        if p:sub(1, #prefix) == prefix then return true end
    end
    return false
end

--- Is the given file path under an ignore_paths prefix?
function M.isIgnoredPath(cfg, filePath)
    local p = filePath:gsub("\\", "/")
    for _, prefix in ipairs(cfg.ignore_paths) do
        if p:sub(1, #prefix) == prefix then return true end
    end
    return false
end

return M
