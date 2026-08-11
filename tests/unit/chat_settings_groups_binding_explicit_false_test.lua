-- tests/unit/chat_settings_groups_binding_explicit_false_test.lua
-- Run: lua tests/unit/chat_settings_groups_binding_explicit_false_test.lua
--
-- UI-path contract for the GUILD_DISCORD family fallback: the settings
-- "Message groups" checkboxes must persist EXPLICIT FALSE on uncheck
-- (groupsBinding passes explicitFalse=true to makeSetBinding), or no click
-- sequence can ever produce groups.GUILD_DISCORD=false and the fallback's
-- explicit-override branch is unreachable from the UI.
--
-- This test drives the REAL binding code: makeSetBinding is extracted from
-- chat_frame1_provider.lua source and compiled (not hand-copied, so it can't
-- drift), the call site's explicitFalse argument is source-pinned, and the
-- persisted table feeds the real TabManager.BuildFilter.

local function readAll(path)
    local f, err = io.open(path, "r")
    assert(f, err)
    local text = f:read("*a")
    f:close()
    return text
end

local src = readAll("QUI_Chat/chat/settings/chat_frame1_provider.lua")

-- ---------------------------------------------------------------------------
-- Source pins
-- ---------------------------------------------------------------------------

-- The groupsBinding call site must pass explicitFalse=true: pin the argument
-- against the groups getter's tail so it can't be confused with the channels
-- binding (which also passes true).
assert(src:find("return t.groups\n                end, true)", 1, true),
    "groupsBinding must pass explicitFalse=true to makeSetBinding")

-- GUILD_DISCORD checkbox tooltip explains the inherit-from-GUILD semantics.
assert(src:find('groupKey == "GUILD_DISCORD"', 1, true),
    "GUILD_DISCORD checkbox must get a dedicated description")
assert(src:find("follow their GUILD setting", 1, true),
    "GUILD_DISCORD description must explain the GUILD inherit semantics")

-- Dead-code fallback literal (used only if TabFilters failed to load) lists
-- GUILD_DISCORD like the live STANDARD_GROUPS source of truth.
assert(src:find('"GUILD", "OFFICER", "GUILD_DISCORD", "GUILD_ACHIEVEMENT"', 1, true),
    "provider fallback group literal must include GUILD_DISCORD")

-- ---------------------------------------------------------------------------
-- Extract and compile the real makeSetBinding from the provider source.
-- ---------------------------------------------------------------------------
local fnStart = assert(src:find("local function makeSetBinding", 1, true),
    "makeSetBinding must exist in the provider")
-- The function closes with `}))` and a 12-space-indented `end`.
local fnStop = assert(src:find("}))\n            end", fnStart, true),
    "makeSetBinding closing shape changed; update this extractor")
local fnSrc = src:sub(fnStart, fnStop + #"}))\n            end" - 1)
assert(fnSrc:find("__newindex", 1, true) and fnSrc:find("__index", 1, true),
    "extracted makeSetBinding must contain both metamethods")
-- The uncheck write must be an explicit branch, NOT the and-or expression
-- `explicitFalse and false or nil` -- that collapses to nil for every input
-- (false middle operand), which is exactly what the runtime drive below
-- catches. The positive pin here just names the intended shape.
assert(fnSrc:find("elseif explicitFalse then", 1, true),
    "makeSetBinding must branch on explicitFalse for the uncheck write")

local loadstring = loadstring or load
local chunk = assert(loadstring(fnSrc .. "\nreturn makeSetBinding",
    "makeSetBinding (extracted)"))
if setfenv then
    setfenv(chunk, {
        MarkTransientOptionsBinding = function(t) return t end,
        setmetatable = setmetatable,
        type = type,
    })
else
    -- Lua 5.2+ fallback (CI runs 5.1): re-load with an env upvalue.
    chunk = assert(load(fnSrc .. "\nreturn makeSetBinding", "makeSetBinding", "t", {
        MarkTransientOptionsBinding = function(t) return t end,
        setmetatable = setmetatable,
        type = type,
    }))
end
local makeSetBinding = chunk()
assert(type(makeSetBinding) == "function", "extracted makeSetBinding compiles")

-- ---------------------------------------------------------------------------
-- Real TabManager.BuildFilter (family fallback consumer).
-- ---------------------------------------------------------------------------
local settings = { enabled = true, customDisplay = { windows = {} } }
local ns = {
    Helpers = { IsSecretValue = function() return false end },
    QUI = { Chat = { _internals = {
        GetSettings = function() return settings end,
        IsChatEnabled = function(s) return s and s.enabled ~= false end,
    } } },
}
assert(loadfile("QUI_Chat/chat/tab_manager.lua"))("QUI", ns)
local TM = ns.QUI.Chat.TabManager

-- ---------------------------------------------------------------------------
-- Drive check -> uncheck through the real binding, mirroring the provider's
-- groups getter (curTab().groups with lazy table creation).
-- ---------------------------------------------------------------------------
-- A curated tab saved before 12.1: GUILD whitelisted, GUILD_DISCORD unknown.
local tab = { name = "Guild", groups = { GUILD = true }, channels = {} }
local binding = makeSetBinding(function()
    if type(tab.groups) ~= "table" then tab.groups = {} end
    return tab.groups
end, true)

-- Baseline: absent key inherits the GUILD verdict (family fallback) and the
-- checkbox renders unchecked (inherit state is not shown as checked).
assert(TM.BuildFilter(tab)({ k = "GUILD_DISCORD" }) == true,
    "pre-12.1 tab inherits GUILD verdict for the Discord stream")
assert(binding.GUILD_DISCORD == false, "absent key reads unchecked through the binding")

-- Check: writes true, stream shown by its own verdict.
binding.GUILD_DISCORD = true
assert(tab.groups.GUILD_DISCORD == true, "check persists true")
assert(TM.BuildFilter(tab)({ k = "GUILD_DISCORD" }) == true, "checked -> Discord stream shown")

-- Uncheck: MUST persist explicit false (not nil), and the explicit override
-- must beat the inherited GUILD verdict.
binding.GUILD_DISCORD = false
assert(tab.groups.GUILD_DISCORD == false,
    "uncheck persists EXPLICIT false (nil would silently re-inherit GUILD)")
local filt = TM.BuildFilter(tab)
assert(filt({ k = "GUILD_DISCORD" }) == false,
    "unchecked-after-touch hides the Discord stream despite GUILD=true")
assert(filt({ k = "GUILD" }) == true, "GUILD itself stays shown")
assert(binding.GUILD_DISCORD == false, "persisted false reads back unchecked")

-- "Leave all unchecked to show all groups" survives false-writes: a groups
-- table holding only explicit falses still reads as unconstrained.
binding.GUILD = false
assert(tab.groups.GUILD == false, "GUILD uncheck also persists false")
assert(TM.BuildFilter(tab) == nil,
    "all-unchecked groups (all-false) + no channels still means no constraint")

print("OK: chat_settings_groups_binding_explicit_false_test")
