-- tests/taint/registry.lua
-- Sources, safe sinks, guards, unwraps. Built-in tables seeded at construction;
-- sources are added later from the api-index. Project config can extend
-- safe-sink and unwrap sets.

local M = {}

-- Method names that accept tainted values regardless of receiver type.
-- Derived from spec section "Safe sinks" and CLAUDE.md.
local BUILTIN_SAFE_SINK_METHODS = {
    -- Cooldown (only DurationObject path is secret-safe in 12.0.5+)
    SetCooldownFromDurationObject = true,
    -- Region / Frame visibility + geometry (C-side accept secret args)
    SetAlpha = true, Show = true, Hide = true,
    SetSize = true, SetWidth = true, SetHeight = true,
    SetPoint = true, ClearAllPoints = true,
    -- Texture + FontString display
    SetText = true, SetTexture = true,
    -- Private aura anchors (callable in combat post-12.0.5)
    AddPrivateAuraAnchor = true,
    RemovePrivateAuraAnchor = true,
    SetPrivateWarningTextAnchor = true,
    RemovePrivateAuraAppliedSound = true,
}

-- Fully-qualified function names that are safe sinks.
local BUILTIN_SAFE_SINK_FUNCTIONS = {
    -- C_StringUtil formatters render secret numbers without unwrapping
    ["C_StringUtil.RoundToNearestString"] = true,
    ["C_StringUtil.FloorToNearestString"] = true,
    ["C_StringUtil.TruncateWhenZero"]     = true,
    ["C_StringUtil.WrapString"]           = true,
}

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
}

-- Unwraps: return non-secret value (or nil) regardless of input.
-- Always emit a `review`-tier finding at the call site to push toward
-- C-side sinks.
local BUILTIN_UNWRAPS = {
    ["Helpers.SafeValue"]    = true,
    ["Helpers.SafeToNumber"] = true,
    ["Helpers.SafeToString"] = true,
    ["Helpers.SafeCompare"]  = true,
}

-- Clean fields: when reading `tainted_local.<field>`, if <field> is in this
-- set the read is treated as non-secret. Lets project memories like
-- "SpellCooldownInfo.isOnGCD is always a clean boolean per Blizzard contract"
-- be expressed as analyzer rules instead of per-line annotations.
-- No defaults — populated entirely from the taint config's clean_fields.
local BUILTIN_CLEAN_FIELDS = {}

local Registry = {}
Registry.__index = Registry

function M.new()
    local self = setmetatable({}, Registry)
    self.sources           = {}
    self.safeSinkMethods   = {}
    self.safeSinkFunctions = {}
    self.guards            = {}
    self.unwraps           = {}
    self.cleanFields       = {}
    self.secretReturning   = {}
    -- Seed built-ins (copy so two Registry.new() instances don't share mutation)
    for k, v in pairs(BUILTIN_SAFE_SINK_METHODS)    do self.safeSinkMethods[k]   = v end
    for k, v in pairs(BUILTIN_SAFE_SINK_FUNCTIONS)  do self.safeSinkFunctions[k] = v end
    for k, v in pairs(BUILTIN_GUARDS)               do self.guards[k]            = v end
    for k, v in pairs(BUILTIN_UNWRAPS)              do self.unwraps[k]           = v end
    for k, v in pairs(BUILTIN_CLEAN_FIELDS)         do self.cleanFields[k]       = v end
    for k, v in pairs(BUILTIN_SECRET_RETURNING)     do self.secretReturning[k]   = v end
    return self
end

function Registry:addSource(name)           self.sources[name]           = true end
function Registry:isSource(name)            return self.sources[name]           == true end

function Registry:addSafeSinkMethod(name)   self.safeSinkMethods[name]   = true end
function Registry:isSafeSinkMethod(name)    return self.safeSinkMethods[name]   == true end

function Registry:addSafeSinkFunction(name) self.safeSinkFunctions[name] = true end
function Registry:isSafeSinkFunction(name)  return self.safeSinkFunctions[name] == true end

function Registry:addGuard(name)            self.guards[name]            = true end
function Registry:isGuard(name)             return self.guards[name]            == true end

function Registry:addUnwrap(name)           self.unwraps[name]           = true end
function Registry:isUnwrap(name)            return self.unwraps[name]           == true end

function Registry:addCleanField(name)       self.cleanFields[name]       = true end
function Registry:isCleanField(name)        return self.cleanFields[name]       == true end

function Registry:addSecretReturning(name)  self.secretReturning[name]   = true end
function Registry:isSecretReturning(name)   return self.secretReturning[name]   == true end

return M
