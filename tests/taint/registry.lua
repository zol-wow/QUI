-- tests/taint/registry.lua
-- Sources, safe sinks, guards, unwraps. Built-in tables seeded at construction;
-- sources are added later from the api-index. Project config can extend
-- safe-sink and unwrap sets.

local M = {}

-- Method names that accept tainted values regardless of receiver type.
-- MINIMAL hand-kept seed: argless visibility/geometry methods only (the
-- sink question never arises for them, but bare unit-test registries lean
-- on their presence). Everything argument-carrying is GENERATED from the
-- api-index at scan time (tests/taint/index_load.lua) — registry_test pins
-- that these seeds never contradict the index.
local BUILTIN_SAFE_SINK_METHODS = {
    Show = true, Hide = true, ClearAllPoints = true,
}

-- Fully-qualified function names that are safe sinks. Empty hand-kept seed —
-- the former C_StringUtil.* entries are now GENERATED from the api-index
-- (secretArguments = "AllowedWhenTainted" / secretArgumentsAnyTainted).
-- Config extra_safe_sinks still feeds this table at scan time.
local BUILTIN_SAFE_SINK_FUNCTIONS = {}

-- Functions that PRODUCE a secret-tagged return value when handed a secret arg.
-- A safe sink says "you can pass a secret here without erroring"; a secret-
-- returning entry says "the result itself is secret". The C_StringUtil
-- formatters are both — pass them through SetText and you're fine, but assign
-- the result to a local and `== "0"` on it and you'll taint execution. Adding
-- the function here makes the analyzer taint the LHS of such assignments so
-- downstream comparisons are flagged.
local BUILTIN_SECRET_RETURNING = {
    ["C_StringUtil.RoundToNearestString"] = true,
    ["C_StringUtil.FloorToNearestString"] = true,
    ["C_StringUtil.TruncateWhenZero"]     = true,
    ["C_StringUtil.WrapString"]           = true,
}

-- Guard predicates: when used as `if [not] G(x) then`, prove x non-secret in
-- the appropriate branch. Both bare and Helpers.-qualified forms accepted.
local BUILTIN_GUARDS = {
    IsSecretValue              = true,
    HasSecretValue             = true,
    ["Helpers.IsSecretValue"]  = true,
    ["Helpers.HasSecretValue"] = true,
    -- 12.1 engine globals (lowercase): the canonical probe primitives.
    issecretvalue              = true,
    issecrettable              = true,
}

-- Unwraps: return non-secret value (or nil) regardless of input.
-- Always emit a `review`-tier finding at the call site to push toward
-- C-side sinks.
local BUILTIN_UNWRAPS = {
    ["Helpers.SafeValue"]        = true,
    ["Helpers.SafeToNumber"]     = true,
    ["Helpers.SafeToString"]     = true,
    ["Helpers.SafeCompare"]      = true,
    ["Helpers.SafeNumberOrNil"]  = true,
}

-- Clean fields: when reading `tainted_local.<field>`, if <field> is in this
-- set the read is treated as non-secret. Lets project memories like
-- "SpellCooldownInfo.isOnGCD is always a clean boolean per Blizzard contract"
-- be expressed as analyzer rules instead of per-line annotations.
-- No defaults — populated entirely from the taint config's clean_fields.
local BUILTIN_CLEAN_FIELDS = {}

-- Restriction gates: predicates whose presence in a function scope marks
-- calls to precondition-guarded APIs (RequiresUnitAuraAccess etc.,
-- FailureMode=Error) as handled — the scope is restriction-aware. Config can
-- extend via extra_restriction_gates.
local BUILTIN_RESTRICTION_GATES = {
    ["C_Secrets.ShouldAurasBeSecret"] = true,
}

local Registry = {}
Registry.__index = Registry

function M.new()
    local self = setmetatable({}, Registry)
    self.sources           = {}
    self.safeSinkMethods   = {}
    self.safeSinkFunctions = {}
    self.docArgRestrictedMethods   = {}
    self.docArgRestrictedFunctions = {}
    self.guards            = {}
    self.unwraps           = {}
    self.cleanFields       = {}
    self.secretReturning   = {}
    self.aspectReturningMethods = {}
    self.preconditionAPIs  = {}
    self.restrictionGates  = {}
    self.elementSecretFunctions = {}
    -- Storage for the helper-param seed track. Named apart from its getter
    -- (`elementContainerParams`) because Registry.__index = Registry: an
    -- instance field spelled like the method would shadow it.
    self.elementContainerParamPositions = {}
    self.secretEventParams = {}
    -- First dotted component of every guarded API / gate name ("C_UnitAuras",
    -- "C_Secrets") — feeds the analyzer's namespace-alias detection
    -- (`local UA = C_UnitAuras`).
    self.preconditionNamespaces = {}
    -- Seed built-ins (copy so two Registry.new() instances don't share mutation)
    for k, v in pairs(BUILTIN_SAFE_SINK_METHODS)    do self.safeSinkMethods[k]   = v end
    for k, v in pairs(BUILTIN_SAFE_SINK_FUNCTIONS)  do self.safeSinkFunctions[k] = v end
    for k, v in pairs(BUILTIN_GUARDS)               do self.guards[k]            = v end
    -- Builtin (engine/canon) guard NAMES get the direct-hit shadow rule: a
    -- file rebinding one is either an impostor or an alias resolved
    -- elsewhere. Custom guards added later (.taintrc extra_guards) are
    -- audited wrapper FUNCTIONS whose defining file necessarily binds the
    -- name to a function literal — exempt from the shadow rule.
    self.builtinGuardNames = {}
    for k in pairs(BUILTIN_GUARDS)                  do self.builtinGuardNames[k] = true end
    for k, v in pairs(BUILTIN_UNWRAPS)              do self.unwraps[k]           = v end
    for k, v in pairs(BUILTIN_CLEAN_FIELDS)         do self.cleanFields[k]       = v end
    for k, v in pairs(BUILTIN_SECRET_RETURNING)     do self.secretReturning[k]   = v end
    for k, v in pairs(BUILTIN_RESTRICTION_GATES)    do self.restrictionGates[k]  = v end
    -- Builtin gate NAMES get the same direct-hit shadow rule as builtin
    -- guards: a file rebinding one is either an impostor or an alias
    -- resolved elsewhere. Custom gates (.taintrc extra_restriction_gates)
    -- are audited wrapper FUNCTIONS bound by construction — exempt.
    self.builtinGateNames = {}
    for k in pairs(BUILTIN_RESTRICTION_GATES)       do self.builtinGateNames[k]  = true end
    for k in pairs(self.restrictionGates) do
        local ns = k:match("^([%w_]+)%.")
        if ns then self.preconditionNamespaces[ns] = true end
    end
    -- Guard namespaces feed the same alias detection (round-8: `local H =
    -- Helpers; H.IsSecretValue(x)` must resolve like gate/API namespaces).
    for k in pairs(self.guards) do
        local ns = k:match("^([%w_]+)%.")
        if ns then self.preconditionNamespaces[ns] = true end
    end
    return self
end

function Registry:addSource(name)           self.sources[name]           = true end
function Registry:isSource(name)            return self.sources[name]           == true end

function Registry:addSafeSinkMethod(name)   self.safeSinkMethods[name]   = true end
function Registry:isSafeSinkMethod(name)    return self.safeSinkMethods[name]   == true end

function Registry:addSafeSinkFunction(name) self.safeSinkFunctions[name] = true end
function Registry:isSafeSinkFunction(name)  return self.safeSinkFunctions[name] == true end

-- Documented argument restrictions (api-index secretArguments with NO
-- tainted-allowed system): tainted (addon) code cannot pass secrets to
-- these at all. Feeds the analyzer's default-reject consumer rule.
function Registry:addDocArgRestrictedMethod(name, level)   self.docArgRestrictedMethods[name]   = level end
function Registry:docArgRestrictionMethod(name)            return self.docArgRestrictedMethods[name] end
function Registry:addDocArgRestrictedFunction(name, level) self.docArgRestrictedFunctions[name] = level end
function Registry:docArgRestrictionFunction(name)          return self.docArgRestrictedFunctions[name] end

function Registry:addGuard(name)
    self.guards[name] = true
    local ns = type(name) == "string" and name:match("^([%w_]+)%.")
    if ns then self.preconditionNamespaces[ns] = true end
end
function Registry:isGuard(name)             return self.guards[name]            == true end
function Registry:isBuiltinGuard(name)      return self.builtinGuardNames ~= nil
                                                and self.builtinGuardNames[name] == true end

-- Element-secret container track (round-23): functions whose CONTAINER return
-- is safe to truth-test but whose ELEMENTS secretize (conditionalSecretContents
-- in the api-index). Deliberately separate from `sources` — registering here
-- must never make the call a whole-call taint source (container checks like
-- `if auras then` stay clean); later tasks consume this track to taint only
-- the elements pulled back out of the container.
function Registry:addElementSecretFunction(name) self.elementSecretFunctions[name] = true end
function Registry:isElementSecretFunction(name)  return self.elementSecretFunctions[name] == true end

-- Helper-param seeding (round-23): functions whose DECLARED name is
-- registered here get "<param>[*]" contamination markers seeded on the
-- listed parameter positions (analyzer walkFunctionBody). Positions index
-- the DECLARED argument list — the parser omits a colon method's implicit
-- `self` from Arguments, so position 1 of `function M:Copy(src)` is `src`.
-- Config spellings should be exact ("M.Copy" for both `function M.Copy`
-- and `function M:Copy`); the analyzer falls back to a bare-tail lookup
-- only when the exact spelling missed AND the bare name is registered.
function Registry:addElementContainerParams(fnName, positions)
    self.elementContainerParamPositions[fnName] = positions
end
function Registry:elementContainerParams(fnName)
    return self.elementContainerParamPositions[fnName]
end

function Registry:addUnwrap(name)           self.unwraps[name]           = true end
function Registry:isUnwrap(name)            return self.unwraps[name]           == true end

function Registry:addCleanField(name)       self.cleanFields[name]       = true end
function Registry:isCleanField(name)        return self.cleanFields[name]       == true end

function Registry:addSecretReturning(name)  self.secretReturning[name]   = true end
function Registry:isSecretReturning(name)   return self.secretReturning[name]   == true end

-- Aspect-returning widget getters (api-index secretReturnsForAspect, 12.1
-- aspect system): keyed by BARE method name — call sites are `obj:GetAlpha()`
-- on plain locals, so the doc's namespace never appears. `aspects` is the
-- aspect-name list from the index ({"Alpha"}), kept for finding messages.
function Registry:addAspectReturningMethod(name, aspects)
    self.aspectReturningMethods[name] = aspects or true
end
function Registry:isAspectReturningMethod(name)
    return self.aspectReturningMethods[name] ~= nil
end

-- View of this registry with aspect-returning methods hidden. The analyzer
-- swaps to this for files outside config aspect_paths: aspect getters
-- (GetText, IsShown, GetAlpha, …) are ubiquitous, and tainting them repo-wide
-- would flood the tiers. Method lookups chain proxy → real instance →
-- Registry metatable, so every other registry facility stays live.
function Registry:aspectStripped()
    if not self._aspectStripped then
        self._aspectStripped = setmetatable(
            { aspectReturningMethods = {} }, { __index = self })
    end
    return self._aspectStripped
end

-- flags: the api-index `preconditions` array (e.g. {"RequiresUnitAuraAccess"});
-- stored so the finding message can name the actual precondition.
local function noteNamespace(self, name)
    local ns = type(name) == "string" and name:match("^([%w_]+)%.")
    if ns then self.preconditionNamespaces[ns] = true end
end

function Registry:addPreconditionAPI(name, flags)
    self.preconditionAPIs[name] = flags or true
    noteNamespace(self, name)
end
function Registry:preconditionFlags(name)         return self.preconditionAPIs[name] end

function Registry:addRestrictionGate(name)
    self.restrictionGates[name] = true
    noteNamespace(self, name)
end
function Registry:isRestrictionGate(name)   return self.restrictionGates[name]  == true end
function Registry:isBuiltinGate(name)       return self.builtinGateNames ~= nil
                                                and self.builtinGateNames[name] == true end

-- Secret event payloads (config event_payload_params): event name → array of
-- handler parameter POSITIONS that carry secret payload values. A function
-- whose body compares against the event-name literal gets those parameters
-- seeded as taint sources (analyzer walkFunctionBody).
-- The entry may also carry `gateGoverned = false` for events whose payload is
-- ALWAYS secret rather than restriction-conditional (UNIT_AURA_BLOCKED): a
-- falsy aura restriction gate proves nothing about such payloads, so the
-- analyzer's gate clears/proofs must not bless them.
function Registry:addSecretPayloadEvent(name, params) self.secretEventParams[name] = params end
function Registry:secretPayloadParams(name)           return self.secretEventParams[name] end
function Registry:hasSecretPayloadEvents()            return next(self.secretEventParams) ~= nil end
function Registry:payloadGateGoverned(name)
    local params = self.secretEventParams[name]
    return not params or params.gateGoverned ~= false
end

return M
