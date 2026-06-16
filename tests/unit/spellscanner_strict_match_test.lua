-- tests/unit/spellscanner_strict_match_test.lua
-- Run: lua tests/unit/spellscanner_strict_match_test.lua
--
-- Verifies the spell scanner only accepts an aura whose spellId matches the
-- cast/use spell (no more "newest recent buff wins" false positives), and the
-- unified /quiclearscan command.

local frames = {}
local events = {}
local now = 100
local inCombat = false

-- Opaque secret-value token (mirrors WoW 12.0 secret spellIds).
local secretSpellId = { token = "secret-spell-id" }

QUI = {
    db = {
        global = {},
    },
}

SlashCmdList = {}

function GetTime() return now end
function InCombatLockdown() return inCombat end
function time() return 1234 end
function issecretvalue(value) return value == secretSpellId end
function wipe(t)
    for k in pairs(t) do t[k] = nil end
    return t
end
function strtrim(s)
    return (s:gsub("^%s*(.-)%s*$", "%1"))
end

-- Suppress slash-command chat output; restore for the final result line.
local realPrint = print
print = function() end

-- Helpful auras returned to the scanner, swapped per scenario.
local helpfulAuras = {}

function CreateFrame()
    local frame = { events = {} }
    function frame:RegisterEvent(event) self.events[event] = true end
    function frame:RegisterUnitEvent(event, ...) self.events[event] = { ... } end
    function frame:UnregisterEvent(event) self.events[event] = nil end
    function frame:SetScript(scriptType, handler) self[scriptType] = handler end
    frames[#frames + 1] = frame
    return frame
end

C_Timer = {
    After = function(_, callback) callback() end,
    NewTicker = function() return { Cancel = function() end } end,
}

C_UnitAuras = {
    GetAuraDataByIndex = function(unit, index, filter)
        if unit == "player" and filter == "HELPFUL" then
            return helpfulAuras[index]
        end
        return nil
    end,
    GetPlayerAuraBySpellID = function() return nil end,
    GetAuraDataByAuraInstanceID = function() return nil end,
    IsAuraFilteredOutByInstanceID = function(_, _, filter) return filter ~= "HELPFUL" end,
}

C_Item = {
    GetItemNameByID = function(itemID) return "Item " .. tostring(itemID) end,
    GetItemCooldown = function() return 0, 0, true end,
}

local ns = {
    CDMScheduler = {
        Publish = function(...) events[#events + 1] = { ... } end,
    },
}

(dofile("tests/helpers/locale.lua"))(ns)
assert(loadfile("QUI_QoL/trackers/spellscanner.lua"))("QUI", ns)

local scanner = assert(QUI.SpellScanner, "SpellScanner should be exported")

---------------------------------------------------------------------------
-- Strict same-spellID matching
---------------------------------------------------------------------------

-- A different-ID buff present in the window (the Ebon Might false-positive)
-- must NOT be adopted as the item's effect.
now = 100
inCombat = false
helpfulAuras = {
    { spellId = 395296, duration = 4.323, expirationTime = now + 4.323, icon = 1, name = "Ebon Might" },
}
scanner.ScanSpell(1234768, 241305)

local db = QUI.db.global.spellScanner
assert(db.items[241305] == nil,
    "a buff whose spellId differs from the use spell must not be scanned for the item")
assert(db.spells[1234768] == nil,
    "a mismatched buff must not leak into the generic spell map either")

-- A same-ID self-buff (use spell == aura spellId) is accepted.
helpfulAuras = {
    { spellId = 1236616, duration = 30, expirationTime = now + 30, icon = 2, name = "Light's Potential" },
}
scanner.ScanSpell(1236616, 241309)
assert(db.items[241309], "a buff matching the use spell should be scanned")
assert(db.items[241309].buffSpellID == 1236616, "scanned item buffSpellID should equal the use spell")
assert(db.items[241309].duration == 30, "scanned item should record the matched buff duration")

-- The >= 3s floor is gone: a short same-ID buff is now accepted because the
-- spellId match is authoritative.
helpfulAuras = {
    { spellId = 5000, duration = 2, expirationTime = now + 2, icon = 3, name = "Short Buff" },
}
scanner.ScanSpell(5000, nil)
assert(db.spells[5000], "a short (<3s) buff matching the cast spell should still be scanned")
assert(db.spells[5000].duration == 2, "short same-ID buff duration should be recorded")

-- A secret spellId cannot be confirmed to match, so it is rejected.
helpfulAuras = {
    { spellId = secretSpellId, duration = 30, expirationTime = now + 30, icon = 4, name = "Secret" },
}
scanner.ScanSpell(6000, nil)
assert(db.spells[6000] == nil, "a secret (unconfirmable) spellId must not be scanned")

---------------------------------------------------------------------------
-- /quiclearscan
---------------------------------------------------------------------------

assert(SlashCmdList["QUICLEARSCAN"], "/quiclearscan command should be registered")
assert(SlashCmdList["QUICLEARSPELL"] == nil, "deprecated /quiclearspell command should be removed")

-- Clearing by itemID removes the item entry and its runtime traces.
db.items[241305] = { useSpellID = 1234768, buffSpellID = 1234768, duration = 10, name = "Combat Potion" }
scanner.registeredItemUseSpells[1234768] = 241305
scanner.activeBuffs[1234768] = { expirationTime = now + 10, duration = 10 }

SlashCmdList["QUICLEARSCAN"]("241305")
assert(db.items[241305] == nil, "/quiclearscan <itemID> should remove the item entry")
assert(scanner.registeredItemUseSpells[1234768] == nil,
    "/quiclearscan <itemID> should drop the item's registered use spell")
assert(scanner.activeBuffs[1234768] == nil,
    "/quiclearscan <itemID> should drop the item's active buff")

-- Clearing by spellID removes the spell entry and its active buff.
db.spells[7000] = { buffSpellID = 7000, duration = 5, name = "Some Spell" }
scanner.activeBuffs[7000] = { expirationTime = now + 5, duration = 5 }

SlashCmdList["QUICLEARSCAN"]("7000")
assert(db.spells[7000] == nil, "/quiclearscan <spellID> should remove the spell entry")
assert(scanner.activeBuffs[7000] == nil, "/quiclearscan <spellID> should drop the spell active buff")

-- Clearing a missing id leaves the store untouched (and does not error).
db.spells[7001] = { buffSpellID = 7001, duration = 5, name = "Keep Me" }
SlashCmdList["QUICLEARSCAN"]("999999")
assert(db.spells[7001], "/quiclearscan with an unknown id should not remove unrelated entries")

-- `all` wipes both maps and the runtime caches.
db.spells[8000] = { buffSpellID = 8000, duration = 5 }
db.items[8888] = { useSpellID = 8001, duration = 5 }
scanner.registeredItemUseSpells[8001] = 8888
scanner.activeBuffs[8000] = { expirationTime = now + 5 }
scanner.pendingScanning[8000] = { timestamp = now }

SlashCmdList["QUICLEARSCAN"]("all")
assert(next(db.spells) == nil, "/quiclearscan all should wipe scanned spells")
assert(next(db.items) == nil, "/quiclearscan all should wipe scanned items")
assert(next(scanner.registeredItemUseSpells) == nil, "/quiclearscan all should wipe registered item use spells")
assert(next(scanner.activeBuffs) == nil, "/quiclearscan all should wipe active buffs")
assert(next(scanner.pendingScanning) == nil, "/quiclearscan all should wipe pending scanning")

print = realPrint
print("OK: spellscanner_strict_match_test")
