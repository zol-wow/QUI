-- tests/unit/groupframes_dispel_typed_cache_test.lua
-- Run: lua5.1 tests/unit/groupframes_dispel_typed_cache_test.lua

local loadstring = loadstring or load

local function readAll(path)
    local f = assert(io.open(path, "rb"))
    local d = f:read("*a"); f:close()
    return d:gsub("\r\n", "\n")
end

local source = readAll("QUI_GroupFrames/groupframes/groupframes_auras.lua")
local beginMarker = "-- >>> QUI_TEST_EXTRACT RebuildDebuffMaps"
local endMarker = "-- <<< QUI_TEST_EXTRACT RebuildDebuffMaps"
local first = assert(source:find(beginMarker, 1, true), "begin marker")
local startPos = assert(source:find("\n", first, true)) + 1
local stopPos = assert(source:find(endMarker, startPos, true), "end marker")
local fnSource = source:sub(startPos, stopPos - 1)

local factory = assert(loadstring(table.concat({
    "return function(wipe, IsSecretValue, ClassifyDispellable, SafeValue)",
    fnSource,
    "return RebuildDebuffMaps",
    "end",
}, "\n"), "typedDebuffCache"))()

local SECRET = {}
local function isSecret(v) return v == SECRET end
local function wipeTable(t) for k in pairs(t) do t[k] = nil end end
local classifications = { [1] = false, [2] = false, [3] = true, [4] = false }
local function classify(_, instID) return classifications[instID] end
local function safeValue(v, fallback) return v ~= nil and v or fallback end
local rebuild = factory(wipeTable, isSecret, classify, safeValue)

local function newCache(debuffs)
    return {
        debuffs = debuffs,
        debuffsByID = {}, debuffsIndexByID = {},
        debuffsBySpellID = {}, debuffsByName = {},
        playerDispellable = {}, playerDispellableOrder = {},
        allDispellable = {}, typedDebuffs = {}, typedDebuffOrder = {},
    }
end

local cache = newCache({
    { auraInstanceID = 1, spellId = 101, name = "Magic", dispelName = "Magic", dispelType = 1 },
    { auraInstanceID = 2, spellId = 102, name = "Bleed", dispelType = 9 },
    { auraInstanceID = 3, spellId = 103, name = "Classified", dispelType = SECRET },
    { auraInstanceID = 4, spellId = 104, name = "Opaque", dispelType = SECRET },
    { auraInstanceID = 5, spellId = 105, name = "Fallback", dispelName = "Curse" },
})
rebuild("party1", cache)

assert(cache.allDispellable[1] == true and cache.allDispellable[5] == true,
    "readable dispelName maintains the legacy allDispellable set")
assert(cache.typedDebuffs[1] and cache.typedDebuffs[2] and cache.typedDebuffs[3]
    and cache.typedDebuffs[5], "typed set includes named, Bleed, and classifier-backed auras")
assert(cache.typedDebuffs[4] == nil,
    "secret enum is not truth-tested or treated as a known typed debuff")
assert(table.concat(cache.typedDebuffOrder, ",") == "1,2,3,5",
    "typed order is stable and includes awareness-only Bleed")
assert(cache.playerDispellable[1] == nil and cache.playerDispellable[2] == nil,
    "all-typed awareness does not widen player-actionable membership")
assert(cache.playerDispellable[3] == true and cache.playerDispellable[5] == true,
    "player classifier and legacy no-API fallback remain intact")

cache.debuffs = { cache.debuffs[2] }
rebuild("party1", cache)
assert(table.concat(cache.typedDebuffOrder, ",") == "2"
    and cache.typedDebuffs[1] == nil and cache.playerDispellable[3] == nil,
    "full rebuild clears stale typed and player-derived state")

assert(source:find("cache.typedDebuffs[instID] = true", 1, true)
    and source:find("cache.typedDebuffs[instID] = nil", 1, true)
    and source:find("RemoveIDFromOrder(cache.typedDebuffOrder, instID)", 1, true),
    "incremental add/remove paths maintain the typed set and order")
assert(source:find("dispel.showIcon == true", 1, true)
    and source:find("glow and glow.enabled == true", 1, true),
    "icon-only and glow-only profiles keep the aura cache active")

print("OK: groupframes_dispel_typed_cache_test")
