-- tests/unit/locale_lod_overlay_test.lua
-- Run: lua tests/unit/locale_lod_overlay_test.lua
--
-- Non-enUS UI-string translations are ROOT-TOC files (core/locale/<loc>.lua),
-- loaded on every client at login. Contract:
--   * Order is enUS base -> the ten overlays -> locale.lua. locale.lua captures
--     ns.LocaleData.active as an UPVALUE, so an overlay listed after it — or
--     moved into any LoadOnDemand addon — never reaches ns.L at all. That is
--     the whole reason these cannot be deferred: BINDING_NAME_* globals
--     (QUI_Bags/bags/bags.lua) and everything built during the login
--     sequence read ns.L before an options addon could possibly load.
--   * Each overlay self-gates on GetLocale() (honouring the
--     QUIDB.global.selectedLocale override) and returns immediately unless
--     it is the active one, so only ONE table is ever built. The other nine
--     cost compile time only.
--   * They previously shipped as ten LoadOnDemand per-locale sub-addon folders.
--     That saved ~51 ms of login compile at a cost of 10 shipped folders; the
--     folders won. Re-creating that folder set is a regression.
--   * The generated settings search index is NOT a locale file: it ships once,
--     in English, packed inside QUI_Options (search_cache.lua), and
--     QUI_Options localizes it on first search (GUI:PrepareSearchEntry).

local LOCALES = { "deDE", "esES", "esMX", "frFR", "itIT", "koKR", "ptBR", "ruRU", "zhCN", "zhTW" }

local function readFile(path)
    local fh = assert(io.open(path, "rb"), "failed to open " .. path)
    local text = fh:read("*a")
    fh:close()
    return text
end

local toc = readFile("QUI.toc")

local enusPos = assert(toc:find("core\\locale\\enUS.lua", 1, true), "enUS base must stay root-loaded")
local applierPos = assert(toc:find("core\\locale\\locale.lua", 1, true), "locale applier missing from root TOC")
assert(enusPos < applierPos, "enUS base must precede locale.lua")

assert(not toc:find("core\\locale\\load_overlay.lua", 1, true),
    "load_overlay.lua is retired — the overlays are listed in the TOC directly")

for _, loc in ipairs(LOCALES) do
    local entry = "core\\locale\\" .. loc .. ".lua"
    local pos = assert(toc:find(entry, 1, true), loc .. " overlay missing from the root TOC")
    assert(enusPos < pos and pos < applierPos,
        loc .. " must load between enUS.lua and locale.lua (locale.lua captures .active as an upvalue)")

    local chunk = readFile("core/locale/" .. loc .. ".lua")
    assert(chunk:find('if want ~= "' .. loc .. '" then return end', 1, true),
        loc .. " overlay must keep its locale gate — without it every client builds all ten tables")
    assert(chunk:find('ns.LocaleData.active = assert(loadstring(', 1, true),
        loc .. " overlay must keep its table as a compiled-on-demand string: as a plain table "
            .. "constructor the nine inactive locales compile ~5.7k fields each at every login "
            .. "(~54 ms vs ~36 ms), for a table that is then thrown away")
end

-- Every overlay must actually materialize when it IS the active one. The
-- wrapper compiles at login but the table inside compiles only when loadstring
-- runs, so `luac -p` on the file cannot catch a broken table body.
do
    local realGetLocale = _G.GetLocale
    for _, loc in ipairs(LOCALES) do
        _G.GetLocale = function() return loc end
        _G.QUIDB = nil
        local ns = {}
        assert(loadfile("core/locale/" .. loc .. ".lua"))("QUI", ns)
        local active = ns.LocaleData and ns.LocaleData.active
        assert(type(active) == "table", loc .. " overlay did not produce ns.LocaleData.active")
        local count = 0
        for _ in pairs(active) do count = count + 1 end
        assert(count > 1000, loc .. " overlay produced only " .. count .. " strings")
    end
    _G.GetLocale = realGetLocale
end

-- neither the retired per-locale folders nor a parallel locale-only set may reappear
local p = io.popen('ls -d QUI_OptionsSearch_* QUI_Locale_* 2>/dev/null')
local stray = p:read("*l")
p:close()
assert(stray == nil,
    "per-locale addon folders are retired (overlays live in core/locale/): " .. tostring(stray))

-- the framework must compile the ONE packed English index, never load a
-- per-locale index addon
local framework = readFile("QUI_Options/framework.lua")
assert(framework:find("ns.QUI_SearchCachePacked", 1, true),
    "EnsureSearchCacheLoaded must compile the single packed English index")
-- The quote is load-bearing: it matches the string LITERAL an addon name would
-- have to be written as to reach C_AddOns.LoadAddOn, and not the prose mention
-- of the retired folder in the comment above EnsureSearchCacheLoaded.
assert(not framework:find('"QUI_OptionsSearch', 1, true),
    "EnsureSearchCacheLoaded must not name a search-index addon as a load target (none ship)")
assert(framework:find("function GUI:PrepareSearchEntry", 1, true),
    "the apply-time localizer must exist — it is what makes one English index enough")

print("PASS locale_lod_overlay_test")
