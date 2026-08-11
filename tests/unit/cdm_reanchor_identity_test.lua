-- tests/unit/cdm_reanchor_identity_test.lua
-- Run: lua tests/unit/cdm_reanchor_identity_test.lua
-- secret sentinel
local secret = { token = "secret" }
issecretvalue = function(v) return v == secret end

local ns = {}
-- Task 45f: cdm_reanchor.lua routes discarded-result pcall guards through
-- ns.SafeCall. Additive stub (T1d/T1e precedent) — bare pcall passthrough.
ns.SafeCall = function(_policy, fn, ...) return pcall(fn, ...) end
ns.SafeCallMethod = function(_policy, obj, name, ...) return pcall(function(...) return obj[name](obj, ...) end, ...) end
ns.SafeCallMethodIfPresent = function(_policy, obj, name, ...) if obj == nil then return nil end local okP, m = pcall(function() return obj[name] end) if not okP then return false end if m == nil then return nil end return pcall(m, obj, ...) end
local loadChunk = dofile("tests/helpers/load_cdm_consolidated_chunk.lua")
loadChunk("QUI_CDM/cdm/cdm_reanchor.lua", "cdm_reanchor.lua")("QUI", ns)
local CDMReanchor = assert(ns.CDMReanchor)

-- cached info source; count lookups to prove caching
local lookups = 0
C_CooldownViewer = {
    GetCooldownViewerCooldownInfo = function(id)
        lookups = lookups + 1
        if id == 70001 then return { cooldownID = 70001, category = 0 } end
        return nil
    end,
}

local bridge = CDMReanchor.New()

local f1 = { GetCooldownID = function() return 70001 end }
local id, cat = bridge:ResolveIdentity(f1)
assert(id == 70001 and cat == 0, "resolves id + category")

local id2, cat2 = bridge:ResolveIdentity(f1)
assert(id2 == 70001 and cat2 == 0, "second resolve consistent")
assert(lookups == 1, "category info is cached per cooldownID")

local fSecret = { GetCooldownID = function() return secret end }
assert(bridge:ResolveIdentity(fSecret) == nil, "secret cooldownID -> nil")

local fField = { cooldownID = 70001 }   -- fallback to .cooldownID field
local id3 = bridge:ResolveIdentity(fField)
assert(id3 == 70001, "falls back to .cooldownID field")

local fNone = {}
assert(bridge:ResolveIdentity(fNone) == nil, "no id -> nil")

issecretvalue = nil
C_CooldownViewer = nil
print("OK: cdm_reanchor_identity_test")
