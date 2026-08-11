-- tests/unit/consumablemacros_macro_cap_test.lua
-- Run: lua tests/unit/consumablemacros_macro_cap_test.lua
--
-- Regression: EnsureMacro's *create* path compared the live per-character
-- macro count against the bare global MAX_CHARACTER_MACROS. That global does
-- not exist in WoW 12.1 -- the value lives at
-- Constants.MacroConsts.MAX_CHARACTER_MACROS (30). The comparison therefore
-- raised "attempt to compare nil with number" for every slot whose macro was
-- missing, which is exactly the state of a fresh install (or an install where
-- the macro names changed and the old ones no longer match).
--
-- This test deliberately leaves _G.MAX_CHARACTER_MACROS unset, mirroring live.

local function noop() end

local function newFrame()
    return setmetatable({}, { __index = function() return noop end })
end
function CreateFrame() return newFrame() end

-- Live 12.1 shape: constants only under Constants.MacroConsts, no bare globals.
Constants = {
    MacroConsts = {
        MAX_ACCOUNT_MACROS = 120,
        MAX_CHARACTER_MACROS = 30,
    },
}
assert(rawget(_G, "MAX_CHARACTER_MACROS") == nil,
    "test precondition: the bare global must stay unset, as it is in WoW 12.1")

local chatMessages = {}
DEFAULT_CHAT_FRAME = { AddMessage = function(_, msg) chatMessages[#chatMessages + 1] = msg end }

function InCombatLockdown() return false end

function wipe(tbl)
    for k in pairs(tbl) do tbl[k] = nil end
    return tbl
end

-- Every configured item is owned, so each enabled slot produces a body.
C_Item = { GetItemCount = function() return 5 end }

-- Macro table stubs. numCharacter is what the cap check reads.
local numCharacter = 12
local created = {}
function GetNumMacros() return 13, numCharacter end
function GetMacroIndexByName() return 0 end -- macro absent -> create path
function GetMacroInfo() return nil end
function EditMacro() end
function DeleteMacro() end
function CreateMacro(name, icon, body, perCharacter)
    created[#created + 1] = { name = name, icon = icon, body = body, perCharacter = perCharacter }
    return #created
end

local macroDB = {
    enabled = true,
    chatNotifications = false,
    selectedFlask = "blood_knights",
}

local ns = {
    Helpers = {
        GetConsumableMacrosDB = function() return macroDB end,
    },
}

;(dofile("tests/helpers/locale.lua"))(ns)
assert(loadfile("modules/utility/consumablemacros.lua"))("QUI", ns)

local CM = assert(ns.ConsumableMacros, "ConsumableMacros should be exported on ns")

---------------------------------------------------------------------------
-- 1. Under the cap: the macro is created instead of erroring.
---------------------------------------------------------------------------
CM:ForceRefresh()

assert(#created == 1,
    ("expected exactly one macro to be created, got %d"):format(#created))
assert(created[1].name == "Flask_DUI",
    "the created macro should be Flask_DUI, got " .. tostring(created[1].name))
assert(created[1].perCharacter == true,
    "consumable macros are per-character")
assert(#chatMessages == 0,
    "no cap warning should be printed below the cap, got: " .. tostring(chatMessages[1]))

---------------------------------------------------------------------------
-- 2. At the cap: creation is refused with a warning, and the cap is the real
--    12.1 value (30), not the pre-12.x 18.
---------------------------------------------------------------------------
numCharacter = 18
created = {}
chatMessages = {}
CM:ForceRefresh()
assert(#created == 1,
    "18 character macros is below the 12.1 cap of 30; creation should still succeed")

numCharacter = 30
created = {}
chatMessages = {}
CM:ForceRefresh()
assert(#created == 0,
    "at the per-character cap no macro should be created")
assert(#chatMessages == 1 and chatMessages[1]:find("30/30", 1, true),
    "the cap warning should report the live 12.1 cap (30/30), got: " .. tostring(chatMessages[1]))

print("OK: consumablemacros_macro_cap_test")
