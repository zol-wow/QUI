-- tests/unit/search_cache_locale_consistency_test.lua
-- Run: lua tests/unit/search_cache_locale_consistency_test.lua
--
-- Guard 1: the generated cache may not contain any of the six retired
-- moduleAddon IDs that were replaced during the Module Addons consolidation.
-- If a future registry change leaves the cache stale, this catches it before
-- ship.
--
-- Guard 2: no search index may sit next to the locale overlays. Those are
-- root-TOC files now (core/locale/<loc>.lua), loaded at login on every client,
-- so an index there is a ~3.2 MB parse everyone pays whether or not they ever
-- open the options window. Ten translated copies used to ship that way.
--
-- Guard 3: the cache must keep emitting ns.L KEYS, not resolved translations.
-- That is the precondition for localizing it at apply time
-- (GUI:PrepareSearchEntry in QUI_Options/framework.lua): every cached
-- string is looked up in the per-locale overlay the client already loaded. If
-- the generator ever resolves strings itself again, the key hit rate collapses
-- and every locale silently falls back to English — the same class of silent
-- failure the old byte-identity guard existed to catch.

local RETIRED_IDS = {
    "moduleAddon_QUI_Skinning",
    "moduleAddon_QUI_Datatexts",
    "moduleAddon_QUI_Minimap",
    "moduleAddon_QUI_InfoBar",
    "moduleAddon_QUI_QoL",
    "moduleAddon_QUI_Alts",
}

local LOCALES = {
    "deDE", "esES", "esMX", "frFR", "itIT",
    "koKR", "ptBR", "ruRU", "zhCN", "zhTW",
}

-- Measured hit rate when the per-locale caches were retired was ~87% for every
-- locale. The floor sits far below that on purpose: it must fail on a collapse
-- (generator stopped emitting keys), not on translation coverage drifting.
local MIN_KEY_HIT_RATE = 0.60

local ENUS_PATH = "QUI_Options/search_cache.lua"

local function readAll(path)
    local f = io.open(path, "rb")
    if not f then return nil end
    local data = f:read("*a")
    f:close()
    return data
end

-- The cache ships as a packed string of positional rows; the helper compiles it
-- and inverts the rows back to field-keyed records (same mapping the runtime
-- does in GUI:ApplyGeneratedSearchCache).
local loadSearchCache = dofile("tests/helpers/search_cache.lua")

local function loadChunkNS(path, locale)
    local chunk = loadfile(path)
    if not chunk then return nil, "loadfile failed" end
    local previous = _G.GetLocale
    _G.GetLocale = function() return locale end
    local ns = {}
    local ok, err = pcall(chunk, "QUI", ns)
    _G.GetLocale = previous
    if not ok then return nil, err end
    return ns
end

local failures = {}

local enUS = readAll(ENUS_PATH)
if not enUS then
    table.insert(failures, ("MISSING: %s"):format(ENUS_PATH))
else
    for _, id in ipairs(RETIRED_IDS) do
        if enUS:find(id, 1, true) then
            table.insert(failures,
                ("%s: contains retired featureId %q — run bash tools/i18n/gen_all_caches.sh")
                    :format(ENUS_PATH, id))
        end
    end
end

for _, path in ipairs({ "core/locale/search_cache.lua",
                        "QUI_OptionsSearch_deDE/search_cache.lua" }) do
    if readAll(path) then
        table.insert(failures,
            ("%s exists — locale files load at LOGIN, so an index there costs every player a ~3.2 MB "
                .. "parse. The index is English-only and is localized at apply time."):format(path))
    end
end

-- Guard 3 needs the cache as data, not as text.
local cacheOk, cache = pcall(loadSearchCache)
if enUS and not cacheOk then
    table.insert(failures, ("%s did not load as a search cache: %s")
        :format(ENUS_PATH, tostring(cache)))
elseif cacheOk then
    local strings, count = {}, 0
    local function collect(value)
        if type(value) == "string" and value ~= "" and not strings[value] then
            strings[value] = true
            count = count + 1
        end
    end
    for _, list in ipairs({ cache.navigation or {}, cache.settings or {} }) do
        for _, entry in ipairs(list) do
            collect(entry.label)
            collect(entry.description)
            collect(entry.tabName)
            collect(entry.subTabName)
            collect(entry.sectionName)
            if type(entry.keywords) == "table" then
                for _, keyword in ipairs(entry.keywords) do collect(keyword) end
            end
        end
    end

    -- Overlays are POSITIONAL: slot N holds the translation of enUS key N, so
    -- a cached string is "resolvable" when its ID has a non-nil slot, not when
    -- the overlay has a key of that name (it has no key text at all).
    local enusNS = loadChunkNS("core/locale/enUS.lua", "enUS")
    local enusKeys = enusNS and enusNS.LocaleData and enusNS.LocaleData.keys
    local ids = {}
    if type(enusKeys) ~= "table" or #enusKeys == 0 then
        table.insert(failures, "core/locale/enUS.lua did not produce ns.LocaleData.keys")
    else
        for index = 1, #enusKeys do ids[enusKeys[index]] = index end
    end

    for _, locale in ipairs(LOCALES) do
        local path = ("core/locale/%s.lua"):format(locale)
        local overlayNS, err = loadChunkNS(path, locale)
        local active = overlayNS and overlayNS.LocaleData and overlayNS.LocaleData.active
        if type(active) ~= "table" then
            table.insert(failures,
                ("%s did not produce ns.LocaleData.active (%s)"):format(path, tostring(err)))
        else
            local hits = 0
            for text in pairs(strings) do
                local id = ids[text]
                if id and active[id] ~= nil then hits = hits + 1 end
            end
            local rate = count > 0 and (hits / count) or 0
            if rate < MIN_KEY_HIT_RATE then
                table.insert(failures, ("%s: only %.1f%% of its %d strings are keys in %s (floor %.0f%%) — "
                    .. "the cache must ship ns.L KEYS so the runtime can localize it"):format(
                    ENUS_PATH, rate * 100, count, path, MIN_KEY_HIT_RATE * 100))
            end
        end
    end
end

if #failures > 0 then
    for _, msg in ipairs(failures) do
        io.stderr:write("FAIL: " .. msg .. "\n")
    end
    os.exit(1)
end

print("ok: one English search cache, no locale copies, keys resolvable in all "
    .. #LOCALES .. " overlays")
