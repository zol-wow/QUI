-- tests/unit/seed_import_strict_clean_test.lua
-- Run: lua tests/unit/seed_import_strict_clean_test.lua
-- The shipped Starter Profile string must pass STRICT import validation with
-- zero sanitizer strips — any strip surfaces as the "Auto-fixed N
-- incompatible settings during import." chat line on every fresh install.
-- Also pins the dual-typed dandersFrames absolutePoint exemption: defaults
-- declare boolean false, but modules/integrations/dandersframes.lua stores a
-- point STRING ("CENTER") once the container is dragged — both spellings must
-- import intact, while other type mismatches on the same subtree still strip.

local env = dofile("tools/_addon_env.lua")
local ns = env.LoadCore()
local core = ns.Addon

assert(type(ns.defaults) == "table" and type(ns.defaults.profile) == "table",
    "ns.defaults.profile missing from LoadCore harness")
core.db = {
    defaults = { profile = ns.defaults.profile },
    profile = {},
    global = {},
}

local failures = {}
local function check(name, ok)
    if not ok then failures[#failures + 1] = name end
end

-- 1) Shipped seed string sanitizes with ZERO strips.
local entry = assert(QUI._importLoaders.StarterProfile, "StarterProfile loader missing")()
local data = type(entry) == "table" and entry.data or entry
local sok, _, _, stripped = core:SanitizeProfileImportString(data)
check("seed string passes sanitize", sok == true)
check("seed string strips nothing, got: "
    .. table.concat(stripped or {}, "; "), (stripped == nil or #stripped == 0))

-- 2) Dual-type exemption: string absolutePoint imports intact; a number
--    still strips; the sibling boolean spelling stays valid.
local LibDeflate = LibStub("LibDeflate")
local AceSerializer = LibStub("AceSerializer-3.0")
local function Encode(payload)
    local serialized = AceSerializer:Serialize(payload)
    return "QUI1:" .. LibDeflate:EncodeForPrint(LibDeflate:CompressDeflate(serialized))
end

local dualOk, _, _, dualStripped = core:SanitizeProfileImportString(Encode({
    dandersFrames = {
        party = { absolutePoint = "CENTER" },
        raid = { absolutePoint = false },
    },
}))
check("string absolutePoint accepted", dualOk == true)
check("string absolutePoint not stripped, got: "
    .. table.concat(dualStripped or {}, "; "), (dualStripped == nil or #dualStripped == 0))

local numOk, numSanitized, _, numStripped = core:SanitizeProfileImportString(Encode({
    dandersFrames = {
        party = { absolutePoint = 5 },
    },
}))
check("number absolutePoint sanitizes", numOk == true)
check("number absolutePoint stripped", numStripped ~= nil and #numStripped == 1)
check("number absolutePoint removed from payload",
    numSanitized ~= nil and numSanitized.dandersFrames.party.absolutePoint == nil)

-- 3) Exemption is path-exact: the same type flip elsewhere still strips.
local otherOk, _, _, otherStripped = core:SanitizeProfileImportString(Encode({
    dandersFrames = {
        party = { enabled = "CENTER" },
    },
}))
check("non-exempt sibling field still sanitizes", otherOk == true)
check("non-exempt sibling type mismatch still strips",
    otherStripped ~= nil and #otherStripped == 1)

core.db = nil

if #failures > 0 then
    error("seed_import_strict_clean_test failures:\n  " .. table.concat(failures, "\n  "))
end
print("OK seed_import_strict_clean_test")
