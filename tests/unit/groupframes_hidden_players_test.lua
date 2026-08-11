-- tests/unit/groupframes_hidden_players_test.lua
-- Run: lua tests/unit/groupframes_hidden_players_test.lua
--
-- Hidden players: db.quiGroupFrames.hiddenPlayers is a user-typed name list
-- whose frames are removed from the party/raid headers entirely. The secure
-- header has include-filters only (nameList/groupFilter/roleFilter — see
-- tests/framexml .../SecureGroupHeaders.lua:410-495), so exclusion is
-- expressed by computing include-lists that omit the hidden names:
--   raid  — a non-empty list forces nameList-section mode in EVERY raid
--           layout and GetRaidDisplaySections skips hidden names;
--   party — ConfigurePartyHeader switches to a computed nameList, folding
--           hideDPS + role ordering in (the header's nameList branch is only
--           taken when roleFilter is unset and it ignores groupBy).
--
-- Behavior tests cover the shared Helpers parser/matcher (core/utils.lua);
-- source-scan asserts pin the groupframes.lua wiring, including the
-- attribute-ordering discipline around switching nameList mode on/off.

-- The secret-value probe must be installed BEFORE core loads: utils.lua's
-- IsSecretValue reads the global at call time, but installing it first keeps
-- this robust if it ever gets localized at file scope.
local SECRET = setmetatable({}, { __tostring = function() return "<secret>" end })
_G.issecretvalue = function(v) return v == SECRET end

local env = dofile("tools/_addon_env.lua")
local ns = env.LoadCore()
local Helpers = ns.Helpers
assert(Helpers, "core utils must export ns.Helpers")

local fails = 0
local function check(name, ok, detail)
    if ok then print("  ok  " .. name)
    else fails = fails + 1; print("FAIL  " .. name .. (detail and ("  " .. detail) or "")) end
end

----------------------------------------------------------------------------
-- Helpers.ParseNameListString
----------------------------------------------------------------------------
check("nil/empty/whitespace-only input parses to nil",
    Helpers.ParseNameListString(nil) == nil
    and Helpers.ParseNameListString("") == nil
    and Helpers.ParseNameListString(",, ;\n") == nil)

local set = Helpers.ParseNameListString(" Bob ,alice-Stormrage;EVE\nMallory-Twisting Nether ")
check("entries split on comma/semicolon/newline and are trimmed + lowercased",
    set ~= nil and set["bob"] == true and set["alice-stormrage"] == true
    and set["eve"] == true and set["mallory-twisting nether"] == true)

check("no stray entries from separators",
    (function()
        local n = 0
        for _ in pairs(set) do n = n + 1 end
        return n == 4
    end)())

----------------------------------------------------------------------------
-- Helpers.NameListContains
----------------------------------------------------------------------------
check("realm-less entry matches the plain roster name (case-insensitive)",
    Helpers.NameListContains(set, "BOB") == true)
check("realm-less entry matches the name on ANY realm",
    Helpers.NameListContains(set, "Bob-Draenor") == true)
check("realm-qualified entry matches only its full Name-Realm string",
    Helpers.NameListContains(set, "Alice-Stormrage") == true
    and Helpers.NameListContains(set, "Alice-Draenor") == false
    and Helpers.NameListContains(set, "Alice") == false)
check("realm names with spaces survive the round trip",
    Helpers.NameListContains(set, "Mallory-Twisting Nether") == true)
check("non-members do not match",
    Helpers.NameListContains(set, "Carol") == false
    and Helpers.NameListContains(set, "Bobby") == false)
check("nil set / nil name / empty name / secret name never match",
    Helpers.NameListContains(nil, "Bob") == false
    and Helpers.NameListContains(set, nil) == false
    and Helpers.NameListContains(set, "") == false
    and Helpers.NameListContains(set, SECRET) == false)

----------------------------------------------------------------------------
-- Defaults
----------------------------------------------------------------------------
local gf = ns.defaults and ns.defaults.profile and ns.defaults.profile.quiGroupFrames
check("quiGroupFrames.hiddenPlayers defaults to the empty string",
    gf ~= nil and gf.hiddenPlayers == "")

----------------------------------------------------------------------------
-- groupframes.lua wiring (source scan — the 5900-line monolith needs real
-- WoW frames and cannot load headless; same pinning style as
-- groupframes_trailing_coalesce_test.lua)
----------------------------------------------------------------------------
local fh = assert(io.open("QUI_GroupFrames/groupframes/groupframes.lua", "rb"))
local source = fh:read("*a")
fh:close()

check("hidden-set accessor exists and is cached on the raw string",
    source:find("_state.GetHiddenPlayerSet = function", 1, true) ~= nil
    and source:find("Helpers.ParseNameListString(raw)", 1, true) ~= nil)

-- Both raid predicates must force section/nameList mode when the list is set.
local useSectionsStart = assert(source:find("local function UseRaidSectionHeaders", 1, true))
local useNameListStart = assert(source:find("_state.UseRaidNameListSections = function", 1, true))
local nameListEnd = assert(source:find("local function GetLayoutGrowDirection", useNameListStart, true))
check("UseRaidSectionHeaders forces section headers when hidden players set",
    source:sub(useSectionsStart, useNameListStart):find("GetHiddenPlayerSet", 1, true) ~= nil)
check("UseRaidNameListSections forces nameList sections when hidden players set",
    source:sub(useNameListStart, nameListEnd):find("GetHiddenPlayerSet", 1, true) ~= nil)

-- GetRaidDisplaySections must drop hidden names inside its roster loop.
local sectionsStart = assert(source:find("GetRaidDisplaySections = function", 1, true))
local sectionsEnd = assert(source:find("GetRaidSectionUnitsPerColumn = function", sectionsStart, true))
local sectionsBody = source:sub(sectionsStart, sectionsEnd)
check("GetRaidDisplaySections filters hidden names from raid sections",
    sectionsBody:find("GetHiddenPlayerSet", 1, true) ~= nil
    and sectionsBody:find("not Helpers.NameListContains(hiddenSet, name)", 1, true) ~= nil)

-- Party include-list mode: attribute-ordering discipline.
local partyCfgStart = assert(source:find("local function ConfigurePartyHeader", 1, true))
local partyCfgEnd = assert(source:find("local function ConfigureRaidHeader", partyCfgStart, true))
local partyCfg = source:sub(partyCfgStart, partyCfgEnd)

check("ConfigurePartyHeader consults the computed party nameList info",
    partyCfg:find("GetPartyNameListInfo", 1, true) ~= nil)

-- Switching INTO include-list mode: nameList/sortMethod must be set BEFORE
-- roleFilter is cleared, otherwise an intermediate secure update sees the
-- header with no filters at all.
local setNameList = partyCfg:find('"nameList", nameListInfo.nameList', 1, true)
local setNamelistSort = partyCfg:find('"sortMethod", "NAMELIST"', 1, true)
local branchEnd = partyCfg:find("else", setNameList or 1, true)
check("include-list mode sets nameList/sortMethod before clearing roleFilter",
    setNameList ~= nil and setNamelistSort ~= nil and branchEnd ~= nil
    and setNameList < setNamelistSort
    and setNamelistSort < assert(partyCfg:find('"roleFilter", nil', setNamelistSort, true))
    and partyCfg:find('"roleFilter", nil', setNamelistSort, true) < branchEnd)

-- Switching OUT: nameList must be cleared LAST, after roleFilter/sorting are
-- restored, so the header never briefly shows unfiltered units.
local elseBranch = partyCfg:sub(branchEnd)
local restoreRole = elseBranch:find('"roleFilter", layout.hideDPS', 1, true)
local clearNameList = elseBranch:find('"nameList", nil', 1, true)
check("normal mode restores roleFilter before clearing nameList",
    restoreRole ~= nil and clearNameList ~= nil and restoreRole < clearNameList)

-- The party name-list builder must mirror the secure header's name format
-- (UnitName + "-Server" for cross-realm) and fold hideDPS in.
local builderStart = assert(source:find("local function BuildPartyNameListEntries", 1, true))
local builderEnd = assert(source:find("_state.GetPartyNameListInfo = function", builderStart, true))
local builder = source:sub(builderStart, builderEnd)
check("party builder mirrors SecureGroupHeaders name format",
    builder:find('name .. "-" .. server', 1, true) ~= nil)
check("party builder folds hideDPS into the include list",
    builder:find("layout.hideDPS", 1, true) ~= nil
    and builder:find('role == "TANK" or role == "HEALER"', 1, true) ~= nil)

-- Sizing: the party header count must honor the filtered member count.
local countStart = assert(source:find("local function GetVisiblePartyUnitCount", 1, true))
local countEnd = assert(source:find("local function ConfigurePartyHeader", countStart, true))
check("GetVisiblePartyUnitCount uses the filtered party count",
    source:sub(countStart, countEnd):find("GetPartyNameListInfo", 1, true) ~= nil)

----------------------------------------------------------------------------
if fails > 0 then
    print(("FAILED %d check(s)"):format(fails))
    os.exit(1)
end
print("PASS groupframes_hidden_players_test")
