-- tests/taint/config.lua
-- Loader for taint analyzer config files. Returns a config table with sane
-- defaults if the file is missing.

local M = {}

local _unpack = table.unpack or unpack  -- Lua 5.1 compat

local DEFAULT_IGNORE_PATHS = {
    "libs/",          -- vendored libraries
    "tests/",         -- analyzer fixtures often deliberately unsafe
    "importstrings/", -- generated content
}

local DEFAULT_COVERAGE = {
    secretWhenCooldownsRestricted = true,
    -- Generic 12.1 class: ANY SecretWhen*Restricted flag (aura, spellcast,
    -- stats, identity, power, health-max, comparison, threat, ...). The
    -- cooldown key above predates this and is kept for back-compat configs.
    secretWhenRestricted = true,
    isSecretReturn = true,
    secretArguments_restricted = true,
    -- Requires* precondition flags (FailureMode=Error) — feeds the analyzer's
    -- review-tier raw-call scan, not the taint-source set.
    preconditions = true,
    -- SecretReturnsForAspect widget getters (GetText, GetAlpha, IsShown, …)
    -- register as aspect-returning methods. Exposure is additionally gated by
    -- aspect_paths — these getters are ubiquitous, so tainting them repo-wide
    -- would drown the tiers.
    secretReturnsForAspect = true,
    -- conditionalSecretContents (round-23): container return stays a safe
    -- truth-test, but registers the call on the element-secret track (see
    -- registry.lua) so later tasks can taint the ELEMENTS pulled back out.
    conditionalSecretContents = true,
}

local function defaults()
    return {
        strict_paths = {},
        strict_unwrap_paths = {},
        ignore_paths = { _unpack(DEFAULT_IGNORE_PATHS) },
        coverage = {
            secretWhenCooldownsRestricted = DEFAULT_COVERAGE.secretWhenCooldownsRestricted,
            secretWhenRestricted = DEFAULT_COVERAGE.secretWhenRestricted,
            isSecretReturn = DEFAULT_COVERAGE.isSecretReturn,
            secretArguments_restricted = DEFAULT_COVERAGE.secretArguments_restricted,
            preconditions = DEFAULT_COVERAGE.preconditions,
            secretReturnsForAspect = DEFAULT_COVERAGE.secretReturnsForAspect,
            conditionalSecretContents = DEFAULT_COVERAGE.conditionalSecretContents,
        },
        -- File prefixes where aspect-returning widget getters (index
        -- secretReturnsForAspect) taint their results. Empty by default:
        -- aspect secrets only materialize on objects whose aspect was
        -- secretized (CDM/aura surfaces), so this is a per-directory opt-in.
        aspect_paths = {},
        extra_safe_sinks = {},
        extra_unwraps = {},
        clean_fields = {},
        -- Module-local guard WRAPPERS (`local function IsSecret(v) return
        -- Helpers.IsSecretValue(v) end`). The analyzer's alias resolution
        -- covers bare copies (`local isv = issecretvalue`) but is
        -- non-interprocedural, so wrapper FUNCTIONS must be registered by
        -- name to participate in guard proofs.
        extra_guards = {},
        -- Round-23 element-secret container track: call-site spellings whose
        -- container return is safe but whose ELEMENTS secretize, plus the
        -- argument positions (per function name) that hold the container.
        element_secret_functions = {},
        element_container_params = {},
        extra_restriction_gates = {},
        restriction_preconditions = {},
        precondition_only_paths = {},
        strict_precondition_paths = {},
        -- event name → array of handler parameter POSITIONS carrying secret
        -- payload values (SetScript OnEvent signature: self, event, ...).
        event_payload_params = {},
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

--- Load taint analyzer config from a file path. Returns defaults if missing.
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

--- Is the given file path under an aspect_paths prefix? Aspect-returning
--- widget getters (GetText, GetAlpha, IsShown, …) only taint their results
--- in these files.
function M.isAspectPath(cfg, filePath)
    local p = filePath:gsub("\\", "/")
    for _, prefix in ipairs(cfg.aspect_paths or {}) do
        if p:sub(1, #prefix) == prefix then return true end
    end
    return false
end

--- Is the given file path under a strict_unwrap_paths prefix?
function M.isStrictUnwrapPath(cfg, filePath)
    -- Normalize backslashes to forward slashes for comparison
    local p = filePath:gsub("\\", "/")
    for _, prefix in ipairs(cfg.strict_unwrap_paths or {}) do
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

--- Is the given file path under a precondition_only_paths prefix? Such files
--- are exempted from ignore_paths for the precondition (raw guarded-call)
--- scan ONLY — the full taint pass still skips them. Lets vendored libraries
--- keep their restriction-crash coverage without drowning the taint tiers in
--- third-party findings.
function M.isPreconditionOnlyPath(cfg, filePath)
    local p = filePath:gsub("\\", "/")
    for _, prefix in ipairs(cfg.precondition_only_paths or {}) do
        if p:sub(1, #prefix) == prefix then return true end
    end
    return false
end

--- Is the given file path under a strict_precondition_paths prefix?
--- Precondition findings there are promoted to strict (CI-blocking) —
--- for audited vendored libs whose raw guarded calls are already
--- fixed/annotated, so a regression fails the gate.
function M.isStrictPreconditionPath(cfg, filePath)
    local p = filePath:gsub("\\", "/")
    for _, prefix in ipairs(cfg.strict_precondition_paths or {}) do
        if p:sub(1, #prefix) == prefix then return true end
    end
    return false
end

return M
