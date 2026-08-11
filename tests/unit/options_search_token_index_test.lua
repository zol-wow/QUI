-- tests/unit/options_search_token_index_test.lua
-- Run: lua tests/unit/options_search_token_index_test.lua
--
-- GUI:ExecuteSearch scores only the entries the candidate token index returns
-- (GUI:CollectSearchCandidates), instead of walking all ~3,500 registry
-- entries per debounce tick. This test pins the two properties that make that
-- safe:
--
--   1. EQUIVALENCE — for queries the index serves, the results must match a
--      forced full scan exactly. The index is a way to skip entries that
--      cannot score, never a different ranking.
--   2. FALLBACK — the index is keyed on whole words and word starts, so it
--      cannot see ScorePreparedText's mid-word `find` ("olor" -> "Color") or
--      its one-typo DL1 rescue ("collor" -> "Color"). Those must take the full
--      scan, which is what an EMPTY candidate set triggers. If that fallback
--      ever silently stops firing, both behaviours vanish from search with no
--      other symptom.
--
-- Loads the REAL framework headlessly via the search-cache generator's WoW-API
-- stub preamble — same technique as options_search_widget_alloc_test.lua.

local GEN_PATH = "tools/generate_search_cache.lua"
local CUT_MARKER = 'local frame = create_stub_node("Frame", nil, false)'
local fh = assert(io.open(GEN_PATH, "rb"), "cannot open " .. GEN_PATH)
local src = fh:read("*a"); fh:close()
local cut = assert(src:find(CUT_MARKER, 1, true),
    "generator preamble cut marker not found -- update CUT_MARKER")
assert((loadstring or load)(src:sub(1, cut - 1), "@gen-preamble"))()

local GUI = assert(_G.QUI and _G.QUI.GUI, "framework did not initialize QUI.GUI")
assert(type(GUI.CollectSearchCandidates) == "function", "framework must expose CollectSearchCandidates")

-- Apply the shipped cache the way the runtime does: positional rows compiled
-- out of the packed string, inverted to named fields against the schema.
local cacheNS = {}
assert(loadfile("core/pack.lua"))("QUI", cacheNS)
assert(loadfile("QUI_Options/search_cache.lua"))("QUI_Options", cacheNS)
assert(GUI:ApplyGeneratedSearchCache(
    cacheNS.Unpack(cacheNS.QUI_SearchCachePacked, "@QUI_Options/search_cache.lua"),
    cacheNS.QUI_SearchCacheSchema), "cache did not apply")
assert(#GUI.StaticSettingsRegistry > 1000, "settings registry looks empty")

local failures = 0
local function check(name, ok, detail)
    if ok then
        print(("  ok  %s"):format(name))
    else
        failures = failures + 1
        print(("FAIL  %s  %s"):format(name, detail or ""))
    end
end

local function labels(list)
    local out = {}
    for _, result in ipairs(list) do out[#out + 1] = (result.data and result.data.label) or "?" end
    table.sort(out)
    return table.concat(out, "\30")
end

local realCollect = GUI.CollectSearchCandidates

-- Runs a query twice: once normally, once with the index forced off.
local function compare(query)
    local usedIndex = false
    GUI.CollectSearchCandidates = function(selfRef, terms, kind)
        local candidates = realCollect(selfRef, terms, kind)
        if candidates then usedIndex = true end
        return candidates
    end
    local indexedSettings, indexedNav = GUI:ExecuteSearch(query)

    GUI.CollectSearchCandidates = function() return nil end
    local scanSettings, scanNav = GUI:ExecuteSearch(query)
    GUI.CollectSearchCandidates = realCollect

    return usedIndex,
        labels(indexedSettings) == labels(scanSettings) and labels(indexedNav) == labels(scanNav),
        #indexedSettings, #indexedNav
end

-- 1. Queries the index serves must be indistinguishable from a full scan.
for _, query in ipairs({
    "cooldown", "color", "font", "health bar", "action bars",
    "resource", "minimap", "chat", "aura", "size", "bar",
}) do
    local usedIndex, identical, settings, nav = compare(query)
    check(("indexed %q matches a full scan (%d settings, %d nav)"):format(query, settings, nav),
        usedIndex and identical,
        usedIndex and "results differ from the full scan" or "expected this query to use the index")
end

-- 2. The behaviours the index cannot represent must fall back and still work.
for _, case in ipairs({
    { query = "olor",   why = "mid-word substring match" },
    { query = "collor", why = "one-typo DL1 rescue" },
    { query = "he",     why = "token shorter than the index minimum" },
}) do
    local usedIndex, identical, settings, nav = compare(case.query)
    check(("%q falls back to the full scan (%s)"):format(case.query, case.why),
        not usedIndex, "the index served this query; the fallback no longer fires")
    check(("%q still returns its matches (%d settings, %d nav)"):format(case.query, settings, nav),
        identical and (settings > 0 or nav > 0),
        "fallback path returned nothing or diverged from the full scan")
end

-- 3. A query that matches nothing must stay empty on both paths.
do
    local _, identical, settings, nav = compare("zzzznope")
    check("a no-match query returns nothing on both paths", identical and settings == 0 and nav == 0)
end

-- 4. Registering an entry must invalidate the index, or search keeps scoring a
--    stale entry set — including entries whose frames are gone.
do
    GUI:BuildSearchTokenIndex()
    assert(GUI._searchTokenIndex, "index did not build")
    GUI:RegisterStaticSettingEntry({ label = "Zzz Index Invalidation Probe" })
    check("registering an entry drops the cached index", GUI._searchTokenIndex == nil)

    local found = false
    for _, result in ipairs((GUI:ExecuteSearch("Zzz Index Invalidation Probe"))) do
        if result.data and result.data.label == "Zzz Index Invalidation Probe" then found = true end
    end
    check("the newly registered entry is searchable immediately", found)

    GUI:ResetStaticSearchIndex()
    check("resetting a registry drops the cached index", GUI._searchTokenIndex == nil)
end

if failures > 0 then
    io.stderr:write(("%d failure(s) in options_search_token_index_test\n"):format(failures))
    os.exit(1)
end
print("OK: options_search_token_index_test")
