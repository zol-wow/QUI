-- Sandboxed Blizzard APIDocumentation table loader.
-- Runs each *.lua in a corpus directory under a controlled environment that
-- stubs APIDocumentation:AddDocumentationTable, captures registered tables,
-- and builds a compact flag index keyed by "Module.Function".
--
-- Usage:
--   local Extract = dofile("tests/api-docs/extract_api_index.lua")
--   local index = Extract.fromCorpus("tests/api-docs/synthetic-corpus")
--   print(Extract.renderLua(index))

local M = {}

-- ---------------------------------------------------------------------------
-- Sandbox helpers
-- ---------------------------------------------------------------------------

-- Doc files reference Enum.* / Constants.* values inside table constructors
-- (12.1.0.68675+ aspect flags, e.g. SecretReturnsForAspect =
-- { Enum.SecretAspect.Alpha }); a plain Lua host has neither global, so the
-- nil index would abort the chunk and silently drop every table in the file.
-- Auto-vivify with stable string placeholders — none of the extracted flags
-- carry these values, they just have to be indexable without erroring.
local function makeAutoTable(prefix)
    return setmetatable({}, {
        __index = function(t, k)
            local v = setmetatable({}, {
                __index = function(_, k2)
                    return prefix .. "." .. tostring(k) .. "." .. tostring(k2)
                end,
            })
            rawset(t, k, v)
            return v
        end,
    })
end

local function makeSandbox()
    local captured = {}
    local APIDocumentation = {}
    function APIDocumentation:AddDocumentationTable(tbl)
        captured[#captured + 1] = tbl
    end
    return APIDocumentation, captured
end

-- SecretReturnsForAspect / SecretArgumentsAddAspect (12.1.0.68675+) carry
-- lists of Enum.SecretAspect.* values. The sandbox auto-vivifies Enum into
-- placeholder strings ("Enum.SecretAspect.Alpha"); strip the prefix so the
-- index stores bare aspect names ({"Alpha"}).
local function collectAspects(v)
    if type(v) ~= "table" then return nil end
    local names = {}
    for _, item in ipairs(v) do
        local s = tostring(item)
        names[#names + 1] = s:match("^Enum%.SecretAspect%.(.+)$") or s
    end
    if #names == 0 then return nil end
    table.sort(names)
    return names
end

local function returnsFlaggedSecret(returns)
    if type(returns) ~= "table" then return false end
    for _, r in ipairs(returns) do
        if r.IsSecret == true then return true end
    end
    return false
end

-- ConditionalSecretContents marks a NON-secret container whose ELEMENTS can
-- be secret under restriction (GetUnitAuras' `auras` return). Distinct from
-- isSecretReturn (whole result secret): the container truth-test is safe,
-- each element must be probed. Captured for index completeness; analyzer
-- consumption (a "secret contents of a safe container" hazard class) is
-- backlog — the key is explicitly non-source in tests/taint/index_load.lua.
local function returnsFlaggedConditionalContents(returns)
    if type(returns) ~= "table" then return false end
    for _, r in ipairs(returns) do
        if r.ConditionalSecretContents == true then return true end
    end
    return false
end

-- Precondition flags (e.g. RequiresUnitAuraAccess = true) gate the whole
-- call: SecretPredicatesDocumentation.lua gives RequiresUnitAuraAccess
-- FailureMode = "Error", i.e. the API HARD-ERRORS under encounter/M+/PvP
-- restrictions. Audits that only looked for Secret* flags missed every
-- guarded-but-erroring API (the 2026-07 external review found three shipped
-- callers that way), so capture any truthy Requires*-prefixed flag.
local function collectPreconditions(fn)
    local pre
    for k, v in pairs(fn) do
        if type(k) == "string" and v == true and k:match("^Requires%u") then
            pre = pre or {}
            pre[#pre + 1] = k
        end
    end
    if pre then table.sort(pre) end
    return pre
end

-- Two doc systems can define the same bare-keyed name (SetText lives on
-- FontString AND Button AND EditBox with DIFFERENT SecretArguments; call
-- sites are receiver-blind). Merge deterministically instead of letting
-- file order pick a winner: booleans OR, name-lists union, and
-- secretArguments keeps the MOST restrictive spelling while
-- secretArgumentsAnyTainted records that some system allows tainted callers.
local SECRET_ARG_RANK = {
    AllowedWhenTainted = 1, AllowedWhenUntainted = 2, NotAllowed = 3,
}

local MERGE_BOOL_KEYS = {
    "secretWhenCooldownsRestricted", "isSecretReturn", "secretPayload",
    "secretArgumentsAnyTainted", "durationObjectArg", "scriptObject",
    "conditionalSecretContents",
}
local MERGE_LIST_KEYS = {
    "secretWhenRestricted", "secretReturnsForAspect",
    "secretArgumentsAddAspect", "preconditions", "eventFlags",
}

local function mergeInto(index, key, entry)
    local prev = index[key]
    if not prev then
        index[key] = entry
        return
    end
    for _, k in ipairs(MERGE_BOOL_KEYS) do
        if entry[k] then prev[k] = true end
    end
    for _, k in ipairs(MERGE_LIST_KEYS) do
        if entry[k] then
            if not prev[k] then
                prev[k] = entry[k]
            else
                local seen = {}
                for _, v in ipairs(prev[k]) do seen[v] = true end
                for _, v in ipairs(entry[k]) do
                    if not seen[v] then
                        seen[v] = true
                        prev[k][#prev[k] + 1] = v
                    end
                end
                table.sort(prev[k])
            end
        end
    end
    if entry.secretArguments then
        -- Unknown future spellings rank MOST restrictive (4), never 0: a 0
        -- fallback on BOTH sides would make an unrecognized spelling
        -- indistinguishable from "no secretArguments at all" (pr==er==0) and
        -- silently drop it instead of erring conservative.
        local pr = prev.secretArguments and (SECRET_ARG_RANK[prev.secretArguments] or 4) or 0
        local er = SECRET_ARG_RANK[entry.secretArguments] or 4
        if er > pr then prev.secretArguments = entry.secretArguments end
    end
end

local function processTable(tbl, index)
    -- Blizzard doc tables expose two names: tbl.Name (bare, e.g. "Spell") and
    -- tbl.Namespace (the runtime accessor, e.g. "C_Spell"). Code calls the
    -- function via the namespace form when one exists. A System WITHOUT a
    -- Namespace ("Unit", "PlayerScript", ...) exports its functions as bare
    -- GLOBALS (UnitHealth, GetUnitSpeed, ...) — keying those under the
    -- system name ("Unit.GetUnitSpeed") produced entries no call site could
    -- ever match, which silently voided their taint coverage.
    local moduleName = tbl.Namespace
    if not moduleName and not tbl.Name then return end
    -- ScriptObject systems are widget METHODS (SetValue on StatusBar, SetText
    -- on FontString, ...): call sites are receiver-blind, so these are
    -- exactly the entries prone to cross-system collisions on a bare name.
    local isScriptObject = (tbl.Type == "ScriptObject")
    if type(tbl.Functions) == "table" then
        for _, fn in ipairs(tbl.Functions) do
            local entry = {}
            local hasFlag = false
            -- ALL SecretWhen*Restricted-style flags, generically. The old
            -- extractor recognized only SecretWhenCooldownsRestricted and
            -- silently dropped the other ~18 12.1 variants (aura, spellcast,
            -- stats, identity, power, health-max, comparison, threat, ...) —
            -- which is exactly how unguarded GetUnitSpeed/UnitHealthMax/
            -- UnitCastingInfo call sites stayed green. Flag names are kept in
            -- the entry so findings can cite the specific restriction class.
            local secretWhen
            for k, v in pairs(fn) do
                if type(k) == "string" and v == true and k:match("^SecretWhen%u") then
                    secretWhen = secretWhen or {}
                    secretWhen[#secretWhen + 1] = k
                end
            end
            if secretWhen then
                table.sort(secretWhen)
                entry.secretWhenRestricted = secretWhen
                hasFlag = true
            end
            if fn.SecretWhenCooldownsRestricted then
                -- Back-compat key: pre-existing coverage/config keys on it.
                entry.secretWhenCooldownsRestricted = true
                hasFlag = true
            end
            if fn.SecretArguments then
                entry.secretArguments = fn.SecretArguments
                if fn.SecretArguments == "AllowedWhenTainted" then
                    entry.secretArgumentsAnyTainted = true
                end
                hasFlag = true
            end
            -- A LuaDurationObject-typed argument marks a sink for the WRAPPED
            -- secret (SetTimerDuration/SetCooldownFromDurationObject are
            -- SecretArguments="AllowedWhenUntainted" yet ARE the documented
            -- route for secret durations — the DurationObject is opaque, not
            -- a raw secret).
            if type(fn.Arguments) == "table" then
                for _, a in ipairs(fn.Arguments) do
                    if type(a) == "table" and a.Type == "LuaDurationObject" then
                        entry.durationObjectArg = true
                        hasFlag = true
                        break
                    end
                end
            end
            -- Top-level SecretReturns (UnitHealth, UnitGetTotalAbsorbs, ...)
            -- folds into the same key as per-return flags: both mean "the
            -- result can be a secret value".
            if fn.SecretReturns == true or returnsFlaggedSecret(fn.Returns) then
                entry.isSecretReturn = true
                hasFlag = true
            end
            if returnsFlaggedConditionalContents(fn.Returns) then
                entry.conditionalSecretContents = true
                hasFlag = true
            end
            local retAspects = collectAspects(fn.SecretReturnsForAspect)
            if retAspects then
                entry.secretReturnsForAspect = retAspects
                hasFlag = true
            end
            local argAspects = collectAspects(fn.SecretArgumentsAddAspect)
            if argAspects then
                entry.secretArgumentsAddAspect = argAspects
                hasFlag = true
            end
            local pre = collectPreconditions(fn)
            if pre then
                entry.preconditions = pre
                hasFlag = true
            end
            if isScriptObject and hasFlag then
                entry.scriptObject = true
            end
            if hasFlag then
                if moduleName then
                    mergeInto(index, moduleName .. "." .. fn.Name, entry)
                else
                    -- Namespace-less system: the function is a bare global.
                    mergeInto(index, fn.Name, entry)
                end
            end
        end
    end
    -- Events: keyed "event:LITERAL_NAME" (addon code registers by literal
    -- name, and the prefix keeps them from ever colliding with function
    -- lookups). Flagged when the event itself carries a truthy Secret*/
    -- Requires* flag, or any payload field is secretizable (Secret* flag or
    -- IsSecret) — those payloads land in handler args and poison table keys
    -- and comparisons downstream.
    if type(tbl.Events) == "table" then
        for _, ev in ipairs(tbl.Events) do
            local entry = {}
            local hasFlag = false
            local flags
            for k, v in pairs(ev) do
                if type(k) == "string" and v == true
                    and (k:match("^Secret%u") or k:match("^Requires%u")) then
                    flags = flags or {}
                    flags[#flags + 1] = k
                    hasFlag = true
                end
            end
            if flags then
                table.sort(flags)
                entry.eventFlags = flags
            end
            if type(ev.Payload) == "table" then
                for _, field in ipairs(ev.Payload) do
                    if type(field) == "table" then
                        if field.IsSecret == true then
                            entry.secretPayload = true
                            hasFlag = true
                        else
                            for k, v in pairs(field) do
                                if type(k) == "string" and v == true and k:match("^Secret%u") then
                                    entry.secretPayload = true
                                    hasFlag = true
                                    break
                                end
                            end
                        end
                    end
                    if entry.secretPayload then break end
                end
            end
            if hasFlag and ev.LiteralName then
                mergeInto(index, "event:" .. ev.LiteralName, entry)
            end
        end
    end
end

-- ---------------------------------------------------------------------------
-- File discovery
-- ---------------------------------------------------------------------------

local function discoverFiles(corpusDir)
    local files = {}
    local isWindows = package.config:sub(1, 1) == "\\"
    local cmd
    if isWindows then
        cmd = string.format('dir /b "%s\\*.lua" 2>nul', corpusDir:gsub("/", "\\"))
    else
        cmd = string.format('find "%s" -maxdepth 1 -type f -name "*.lua" 2>/dev/null', corpusDir)
    end
    local p = io.popen(cmd, "r")
    if p then
        for line in p:lines() do
            line = line:gsub("\\", "/"):match("^%s*(.-)%s*$")
            if line ~= "" then
                if isWindows and not line:find("/") then
                    -- Windows dir /b returns just the basename; prepend corpusDir
                    line = corpusDir:gsub("\\", "/") .. "/" .. line
                end
                files[#files + 1] = line
            end
        end
        p:close()
    end
    -- Deterministic processing order: file-listing order is filesystem/OS
    -- dependent, and mergeInto's list-union ordering (pre-sort dedup aside,
    -- ties within a rank keep whichever value arrived first) must not vary
    -- between runs on the same corpus.
    table.sort(files)
    return files
end

-- ---------------------------------------------------------------------------
-- Public API
-- ---------------------------------------------------------------------------

--- Build a flag index from all *.lua files in corpusDir.
-- Returns a flat table: { ["Module.Function"] = { flags... }, ... }
-- (plus { ["event:LITERAL_NAME"] = { flags... } } for flagged events).
-- Only entries that carry at least one taint-relevant flag are included.
-- Known flags:
--   secretWhenCooldownsRestricted = true
--   secretWhenRestricted          = { "SecretWhenUnitStatsRestricted", ... }
--                                   (ALL SecretWhen* flags, sorted)
--   secretArguments               = string  (captured verbatim, INCLUDING "AllowedWhenTainted")
--   secretArgumentsAnyTainted     = true    (SOME colliding system allows tainted callers)
--   durationObjectArg             = true    (an argument has Type == "LuaDurationObject")
--   scriptObject                  = true    (entry came from a Type == "ScriptObject" system,
--                                   i.e. a widget METHOD, not a namespaced C_* function)
--   isSecretReturn                = true    (per-return flag OR top-level SecretReturns)
--   secretReturnsForAspect        = { "Alpha", ... }  (aspect names, sorted)
--   secretArgumentsAddAspect      = { "Alpha", ... }  (aspect names, sorted)
--   preconditions                 = { "RequiresUnitAuraAccess", ... }
--   eventFlags                    = { "SecretInActivePvPMatch", ... }
--   secretPayload                 = true
--
-- Cross-system merge: a bare-keyed name ("SetText", "SetValue", ...) or event
-- literal name can be defined by multiple doc systems (call sites are
-- receiver-blind to which widget/system they're calling into). Entries
-- merge deterministically instead of file order picking a winner: boolean
-- flags OR together, name-lists union, and secretArguments keeps the MOST
-- restrictive spelling seen ("AllowedWhenTainted" < "AllowedWhenUntainted" <
-- "NotAllowed") while secretArgumentsAnyTainted separately records whether
-- ANY colliding system allows tainted callers.
function M.fromCorpus(corpusDir)
    local APIDocumentation, captured = makeSandbox()
    local files = discoverFiles(corpusDir)

    for _, path in ipairs(files) do
        local f = io.open(path, "rb")
        if f then
            local source = f:read("*a")
            f:close()
            local env = setmetatable({
                APIDocumentation = APIDocumentation,
                Enum = makeAutoTable("Enum"),
                Constants = makeAutoTable("Constants"),
            }, { __index = _G })
            local chunk
            if setfenv then
                -- Lua 5.1
                chunk = (loadstring or load)(source, path)
                if chunk then
                    setfenv(chunk, env)
                    pcall(chunk)
                end
            else
                -- Lua 5.2+
                chunk = load(source, path, "t", env)
                if chunk then
                    pcall(chunk)
                end
            end
        end
    end

    local index = {}
    for _, tbl in ipairs(captured) do
        processTable(tbl, index)
    end
    return index
end

--- Render an index table as sorted, committable Lua source.
-- The output is a return statement so it can be loaded with load()/loadfile().
function M.renderLua(index)
    local keys = {}
    for k in pairs(index) do
        keys[#keys + 1] = k
    end
    table.sort(keys)

    local parts = {
        "-- Auto-generated by tests/api-docs/extract_api_index.lua. Do not edit by hand.\n",
        "return {\n",
    }
    local function renderNameList(list)
        local quoted = {}
        for i, name in ipairs(list) do
            quoted[i] = string.format("%q", name)
        end
        return "{ " .. table.concat(quoted, ", ") .. " }"
    end

    for _, k in ipairs(keys) do
        local entry = index[k]
        local fields = {}
        if entry.secretWhenCooldownsRestricted then
            fields[#fields + 1] = "secretWhenCooldownsRestricted = true"
        end
        if entry.secretWhenRestricted then
            fields[#fields + 1] = "secretWhenRestricted = "
                .. renderNameList(entry.secretWhenRestricted)
        end
        if entry.secretArguments then
            fields[#fields + 1] = string.format("secretArguments = %q", entry.secretArguments)
        end
        if entry.secretArgumentsAnyTainted then
            fields[#fields + 1] = "secretArgumentsAnyTainted = true"
        end
        if entry.durationObjectArg then
            fields[#fields + 1] = "durationObjectArg = true"
        end
        if entry.scriptObject then
            fields[#fields + 1] = "scriptObject = true"
        end
        if entry.isSecretReturn then
            fields[#fields + 1] = "isSecretReturn = true"
        end
        if entry.conditionalSecretContents then
            fields[#fields + 1] = "conditionalSecretContents = true"
        end
        if entry.secretReturnsForAspect then
            fields[#fields + 1] = "secretReturnsForAspect = "
                .. renderNameList(entry.secretReturnsForAspect)
        end
        if entry.secretArgumentsAddAspect then
            fields[#fields + 1] = "secretArgumentsAddAspect = "
                .. renderNameList(entry.secretArgumentsAddAspect)
        end
        if entry.preconditions then
            fields[#fields + 1] = "preconditions = " .. renderNameList(entry.preconditions)
        end
        if entry.eventFlags then
            fields[#fields + 1] = "eventFlags = " .. renderNameList(entry.eventFlags)
        end
        if entry.secretPayload then
            fields[#fields + 1] = "secretPayload = true"
        end
        parts[#parts + 1] = string.format("    [%q] = { %s },\n", k, table.concat(fields, ", "))
    end
    parts[#parts + 1] = "}\n"
    return table.concat(parts)
end

return M
