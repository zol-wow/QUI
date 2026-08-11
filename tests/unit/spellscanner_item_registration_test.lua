-- tests/unit/spellscanner_item_registration_test.lua
-- Run: lua tests/unit/spellscanner_item_registration_test.lua

local frames = {}
local events = {}
local now = 100
local inCombat = false
local itemCooldowns = {}
local secretAuraInstanceID = { token = "secret-aura-instance" }
-- 68569: the WHOLE UNIT_AURA updateInfo payload (not just a field inside it)
-- can itself be an opaque secret value under restriction. A real secret value
-- THROWS on field access, so this sentinel must throw too — a plain table
-- here would pass even against pre-fix code (zero regression protection).
local secretUpdateInfo = setmetatable({}, {
    __index = function() error("attempt to use a secret value", 2) end,
    __newindex = function() error("attempt to use a secret value", 2) end,
})
-- Wave 2b Task B: UNIT_SPELLCAST_SUCCEEDED's spellID can itself be
-- whole-secret under SecretWhenUnitSpellCastRestricted. A real secret
-- spellID throws as a table key and in a numeric compare (`spellID <= 0`);
-- this sentinel throws on both so a plain number/table would give zero
-- regression protection against the pre-fix `spellID <= 0` compare.
local secretSpellID = setmetatable({}, {
    __index = function() error("attempt to use a secret value", 2) end,
    __newindex = function() error("attempt to use a secret value", 2) end,
    __le = function() error("attempt to use a secret value", 2) end,
    __lt = function() error("attempt to use a secret value", 2) end,
})
-- 12.1 per-field secrecy: updateInfo can be a READABLE table whose scalar
-- isFullUpdate field is itself a secret boolean. In-game a boolean test on
-- it THROWS; Lua metatables cannot trap truthiness, so a pre-fix boolean
-- test on this token silently passes (truthy table). The RED signal is
-- probe ABSENCE instead: probedValues records every value handed to
-- issecretvalue, and the per-field case below asserts the token was probed.
local secretIsFullUpdate = { token = "secret-isFullUpdate" }
local probedValues = {}

QUI = {
    db = {
        global = {},
    },
}

SlashCmdList = {}

function GetTime() return now end
function InCombatLockdown() return inCombat end
function time() return 1234 end
function issecretvalue(value)
    if value ~= nil then probedValues[value] = true end
    return value == secretAuraInstanceID or value == secretUpdateInfo
        or value == secretSpellID or value == secretIsFullUpdate
end

function CreateFrame()
    local frame = { events = {} }
    function frame:RegisterEvent(event)
        self.events[event] = true
    end
    function frame:RegisterUnitEvent(event, ...)
        self.events[event] = { ... }
    end
    function frame:UnregisterEvent(event)
        self.events[event] = nil
    end
    function frame:SetScript(scriptType, handler)
        self[scriptType] = handler
    end
    frames[#frames + 1] = frame
    return frame
end

C_Timer = {
    After = function(delay, callback)
        callback()
    end,
    NewTicker = function()
        return { Cancel = function() end }
    end,
}

C_UnitAuras = {
    GetAuraDataByIndex = function(unit, index, filter)
        if unit == "player" and index == 1 and filter == "HELPFUL" then
            -- Same-ID self-buff: the aura's spellId equals the item use spell
            -- (9002). The scanner only adopts a buff whose spellId matches the
            -- spell that was cast/used.
            return {
                spellId = 9002,
                duration = 30,
                expirationTime = now + 30,
                icon = 123,
                name = "Registered Item Aura",
            }
        end
        return nil
    end,
    IsAuraFilteredOutByInstanceID = function(unit, auraInstanceID, filter)
        return filter ~= "HELPFUL"
    end,
    GetAuraDataByAuraInstanceID = function(unit, auraInstanceID)
        if unit == "player" and auraInstanceID == 91001 then
            return { auraInstanceID = auraInstanceID }
        end
        if unit == "player" and auraInstanceID == 91002 then
            return { auraInstanceID = auraInstanceID }
        end
        if unit == "player" and auraInstanceID == 91003 then
            return { auraInstanceID = auraInstanceID }
        end
        if unit == "player" and auraInstanceID == 91004 then
            return { auraInstanceID = auraInstanceID }
        end
        if unit == "player" and auraInstanceID == 91005 then
            return { auraInstanceID = auraInstanceID }
        end
        if unit == "player" and auraInstanceID == 91008 then
            return { auraInstanceID = auraInstanceID }
        end
        if unit == "player" and auraInstanceID == secretAuraInstanceID then
            return { auraInstanceID = auraInstanceID }
        end
        return nil
    end,
}

C_Item = {
    GetItemNameByID = function(itemID)
        return "Item " .. tostring(itemID)
    end,
    GetItemCooldown = function(itemID)
        local cd = itemCooldowns[itemID]
        if cd then
            return cd.startTime, cd.duration, cd.enabled
        end
        return 0, 0, true
    end,
}

local ns = {
    CDMScheduler = {
        Publish = function(...)
            events[#events + 1] = { ... }
        end,
    },
}

assert(loadfile("modules/trackers/spellscanner.lua"))("QUI", ns)

local scanner = assert(QUI.SpellScanner, "SpellScanner should be exported")
assert(scanner.RegisterItemUseSpell(2001, 9002) == true,
    "item use spell registration should succeed")

local eventFrame = assert(frames[1], "event frame should be created")
assert(eventFrame.OnEvent, "event frame should install OnEvent handler")

-- Wave 2b Task B: UNIT_SPELLCAST_SUCCEEDED must be RegisterUnitEvent'd to
-- "player" (matching UNIT_AURA on the same frame), never a bare
-- RegisterEvent -- the C-side filter is the only trusted unit identity.
assert(type(eventFrame.events["UNIT_SPELLCAST_SUCCEEDED"]) == "table",
    "UNIT_SPELLCAST_SUCCEEDED must be registered via RegisterUnitEvent, not RegisterEvent")
assert(eventFrame.events["UNIT_SPELLCAST_SUCCEEDED"][1] == "player",
    "UNIT_SPELLCAST_SUCCEEDED must be scoped to the player unit")

eventFrame.OnEvent(eventFrame, "UNIT_SPELLCAST_SUCCEEDED", "player", "cast-guid", 9002)

local db = QUI.db.global.spellScanner
assert(db.spells[9002] == nil, "registered item cast should not save generic spell aura mapping")
assert(db.items[2001].buffSpellID == 9002, "registered item cast should save item aura mapping")
assert(db.items[2001].useSpellID == 9002, "registered item mapping should keep use spell")

local active, expiration, duration, auraInstanceID, auraUnit = scanner.IsItemActive(2001)
assert(active == true and expiration == 130 and duration == 30,
    "registered item cast should activate item aura timing")

assert(events[1][1] == "CDM:COOLDOWN_CHANGED", "scanner should publish CDM cooldown refresh")
assert(events[1][2] == 9002, "scanner refresh should include use spell")
assert(events[1][4] == "scanner_item", "scanner refresh should target item scope")

events = {}
now = 200
inCombat = true
scanner.registeredItemUseSpells[9100] = nil
db.items[2100] = {
    useSpellID = 9100,
    buffSpellID = 8100,
    duration = 15,
    icon = 456,
    name = "Persisted Item Aura",
    scannedAt = 123,
}

eventFrame.OnEvent(eventFrame, "UNIT_SPELLCAST_SUCCEEDED", "player", "cast-guid-2", 9100)

active, expiration, duration = scanner.IsItemActive(2100)
assert(active == true and expiration == 215 and duration == 15,
    "persisted item mapping should activate item aura timing in combat without runtime registration")
assert(events[1][1] == "CDM:COOLDOWN_CHANGED", "persisted item mapping should publish CDM refresh")
assert(events[1][2] == 9100, "persisted item refresh should include use spell")
assert(events[1][4] == "scanner_item",
    "persisted item mapping should target item scope even when runtime registration is empty")

events = {}
now = 300
inCombat = true
scanner.RegisterItemUseSpell(2200, 9200)
QUI.db.global.spellScanner.spells[9200] = nil
QUI.db.global.spellScanner.items[2200] = nil
eventFrame.OnEvent(eventFrame, "UNIT_SPELLCAST_SUCCEEDED", "player", "cast-guid-3", 9200)
eventFrame.OnEvent(eventFrame, "UNIT_AURA", "player", {
    addedAuras = {
        { auraInstanceID = 91001 },
    },
})

active, expiration, duration, auraInstanceID, auraUnit = scanner.IsItemActive(2200)
assert(active == true, "registered item cast should bind added aura instance in combat")
assert(expiration == nil and duration == nil,
    "runtime aura instance binding should not require readable timing fields")
assert(auraInstanceID == 91001 and auraUnit == "player",
    "runtime aura instance binding should return aura instance identity")
assert(events[1][1] == "CDM:COOLDOWN_CHANGED", "runtime aura instance binding should publish CDM refresh")
assert(events[1][2] == 9200, "runtime aura instance refresh should include use spell")
assert(events[1][4] == "scanner_item", "runtime aura instance binding should target item scope")

events = {}
now = 400
inCombat = true
scanner.RegisterItemUseSpell(2300, 9300)
QUI.db.global.spellScanner.spells[9300] = nil
QUI.db.global.spellScanner.items[2300] = nil
eventFrame.OnEvent(eventFrame, "UNIT_AURA", "player", {
    addedAuras = {
        { auraInstanceID = 91002 },
    },
})
itemCooldowns[2300] = {
    startTime = now,
    duration = 120,
    enabled = true,
}
eventFrame.OnEvent(eventFrame, "BAG_UPDATE_COOLDOWN")

active, expiration, duration, auraInstanceID, auraUnit = scanner.IsItemActive(2300)
assert(active == true, "registered item cooldown start should bind recent player aura instance")
assert(auraInstanceID == 91002 and auraUnit == "player",
    "cooldown-start binding should return the recent aura instance identity")
assert(QUI.db.global.spellScanner.items[2300] == nil,
    "cooldown-start runtime binding should not persist scanner item data")
assert(events[1][1] == "CDM:COOLDOWN_CHANGED", "cooldown-start aura binding should publish CDM refresh")
assert(events[1][2] == 9300, "cooldown-start aura binding should include use spell")
assert(events[1][4] == "scanner_item", "cooldown-start aura binding should target item scope")

events = {}
now = 500
inCombat = true
itemCooldowns[2300] = nil
scanner.RegisterItemUseSpell(2400, 9400)
QUI.db.global.spellScanner.spells[9400] = nil
QUI.db.global.spellScanner.items[2400] = nil
eventFrame.OnEvent(eventFrame, "UNIT_AURA", "player", {
    addedAuras = {
        { auraInstanceID = 91003 },
    },
})
eventFrame.OnEvent(eventFrame, "BAG_UPDATE_COOLDOWN")

active, expiration, duration, auraInstanceID, auraUnit = scanner.IsItemActive(2400)
assert(active == false, "player aura should not bind before its item cooldown starts")
assert(#events == 0, "ignored cooldown update should not publish a scanner refresh")

now = 500.1
itemCooldowns[2400] = {
    startTime = now,
    duration = 120,
    enabled = true,
}
eventFrame.OnEvent(eventFrame, "BAG_UPDATE_COOLDOWN")

active, expiration, duration, auraInstanceID, auraUnit = scanner.IsItemActive(2400)
assert(active == true, "delayed item cooldown start should bind recent player aura instance")
assert(auraInstanceID == 91003 and auraUnit == "player",
    "cooldown-start binding should keep player aura identity")
assert(events[1][1] == "CDM:COOLDOWN_CHANGED", "delayed player cooldown binding should publish CDM refresh")
assert(events[1][2] == 9400, "delayed player cooldown binding should include use spell")
assert(events[1][4] == "scanner_item", "delayed player cooldown binding should target item scope")

events = {}
now = 550
inCombat = true
scanner.RegisterItemUseSpell(2401, 9401)
QUI.db.global.spellScanner.spells[9401] = nil
QUI.db.global.spellScanner.items[2401] = nil
eventFrame.OnEvent(eventFrame, "UNIT_AURA", "player", {
    addedAuras = {
        { auraInstanceID = 91006 },
    },
})
now = 550.11
itemCooldowns[2401] = {
    startTime = now,
    duration = 120,
    enabled = true,
}
eventFrame.OnEvent(eventFrame, "BAG_UPDATE_COOLDOWN")

active = scanner.IsItemActive(2401)
assert(active == false, "player aura outside the cooldown correlation window should not bind")
assert(#events == 0, "expired player aura correlation should not publish a scanner refresh")

events = {}
now = 600
inCombat = true
scanner.RegisterItemUseSpell(2500, 9500)
scanner.RegisterItemUseSpell(2501, 9501)
QUI.db.global.spellScanner.spells[9500] = nil
QUI.db.global.spellScanner.items[2500] = nil
QUI.db.global.spellScanner.spells[9501] = nil
QUI.db.global.spellScanner.items[2501] = nil
itemCooldowns[2500] = {
    startTime = now - 20,
    duration = 120,
    enabled = true,
}
eventFrame.OnEvent(eventFrame, "UNIT_AURA", "player", {
    addedAuras = {
        { auraInstanceID = 91004 },
    },
})
itemCooldowns[2501] = {
    startTime = now,
    duration = 120,
    enabled = true,
}
eventFrame.OnEvent(eventFrame, "BAG_UPDATE_COOLDOWN")

active = scanner.IsItemActive(2500)
assert(active == false, "stale active item cooldown should not steal a new player aura")
active, expiration, duration, auraInstanceID, auraUnit = scanner.IsItemActive(2501)
assert(active == true, "fresh item cooldown start should bind the recent player aura")
assert(auraInstanceID == 91004 and auraUnit == "player",
    "fresh item cooldown binding should keep the recent player aura identity")
assert(events[1][1] == "CDM:COOLDOWN_CHANGED", "fresh item cooldown binding should publish CDM refresh")
assert(events[1][2] == 9501, "fresh item cooldown binding should include the fresh item use spell")
assert(events[1][4] == "scanner_item", "fresh item cooldown binding should target item scope")

events = {}
now = 700
inCombat = true
scanner.RegisterItemUseSpell(2600, 9600)
QUI.db.global.spellScanner.spells[9600] = nil
QUI.db.global.spellScanner.items[2600] = nil
eventFrame.OnEvent(eventFrame, "UNIT_AURA", "player", {
    addedAuras = {
        { auraInstanceID = secretAuraInstanceID },
    },
})
itemCooldowns[2600] = {
    startTime = now,
    duration = 120,
    enabled = true,
}
eventFrame.OnEvent(eventFrame, "BAG_UPDATE_COOLDOWN")

active, expiration, duration, auraInstanceID, auraUnit = scanner.IsItemActive(2600)
assert(active == true, "secret aura instance IDs should bind to a fresh item cooldown")
assert(auraInstanceID == secretAuraInstanceID and auraUnit == "player",
    "secret aura instance IDs should be preserved as opaque C-side tokens")
assert(events[1][1] == "CDM:COOLDOWN_CHANGED", "secret aura binding should publish CDM refresh")
assert(events[1][2] == 9600, "secret aura binding should include item use spell")
assert(events[1][4] == "scanner_item", "secret aura binding should target item scope")

events = {}
now = 800
inCombat = true
scanner.RegisterItemUseSpell(2700, 9700)
QUI.db.global.spellScanner.spells[9700] = nil
QUI.db.global.spellScanner.items[2700] = nil
itemCooldowns[2700] = {
    startTime = now,
    duration = 120,
    enabled = true,
}
eventFrame.OnEvent(eventFrame, "BAG_UPDATE_COOLDOWN")

active = scanner.IsItemActive(2700)
assert(active == false, "cooldown-first item aura should wait for the aura payload")
assert(#events == 0, "cooldown-first pending correlation should not publish before aura payload")

now = 800.1
eventFrame.OnEvent(eventFrame, "UNIT_AURA", "player", {
    addedAuras = {
        { auraInstanceID = 91005 },
    },
})

active, expiration, duration, auraInstanceID, auraUnit = scanner.IsItemActive(2700)
assert(active == true, "cooldown-first item aura should bind when UNIT_AURA arrives")
assert(auraInstanceID == 91005 and auraUnit == "player",
    "cooldown-first item aura should keep the player aura identity")
assert(events[1][1] == "CDM:COOLDOWN_CHANGED", "cooldown-first aura binding should publish CDM refresh")
assert(events[1][2] == 9700, "cooldown-first aura binding should include item use spell")
assert(events[1][4] == "scanner_item", "cooldown-first aura binding should target item scope")

events = {}
now = 900
inCombat = true
scanner.RegisterItemUseSpell(2800, 9800)
QUI.db.global.spellScanner.spells[9800] = nil
QUI.db.global.spellScanner.items[2800] = nil
itemCooldowns[2800] = {
    startTime = now,
    duration = 120,
    enabled = true,
}
eventFrame.OnEvent(eventFrame, "BAG_UPDATE_COOLDOWN")

now = 900.11
eventFrame.OnEvent(eventFrame, "UNIT_AURA", "player", {
    addedAuras = {
        { auraInstanceID = 91007 },
    },
})

active = scanner.IsItemActive(2800)
assert(active == false, "aura payload outside the pending item-use window should not bind")
assert(#events == 0, "expired pending item-use correlation should not publish a scanner refresh")

events = {}
now = 1000
inCombat = true
scanner.RegisterItemUseSpell(2900, 9900)
QUI.db.global.spellScanner.spells[9900] = nil
QUI.db.global.spellScanner.items[2900] = nil

-- 68569: a whole-secret UNIT_AURA updateInfo payload (the arg itself is
-- opaque, not merely a field within it) must not throw -- a direct field
-- access like `updateInfo.isFullUpdate` on a secret value throws -- and must
-- have zero observable effect (the same no-op as the pre-existing
-- isFullUpdate/nil full-rescan branch).
local ok = pcall(eventFrame.OnEvent, eventFrame, "UNIT_AURA", "player", secretUpdateInfo)
assert(ok, "a whole-secret UNIT_AURA updateInfo payload must not throw")
assert(scanner.IsItemActive(2900) == false,
    "a whole-secret updateInfo payload must not activate any buff")
assert(#events == 0, "a whole-secret updateInfo payload must not publish a scanner refresh")

-- 12.1 per-field secrecy: readable table, secret isFullUpdate scalar (live
-- shape: { addedAuras=<secret table>, isFullUpdate=<secret boolean> }). Must
-- not throw, must have zero observable effect, and the flag must have been
-- PROBED via issecretvalue before any boolean test (see probedValues note at
-- the top -- truthiness is untrappable, so probe absence is the RED signal).
local okField = pcall(eventFrame.OnEvent, eventFrame, "UNIT_AURA", "player", {
    isFullUpdate = secretIsFullUpdate,
    addedAuras = secretUpdateInfo,
})
assert(okField, "a per-field secret isFullUpdate must not throw")
assert(scanner.IsItemActive(2900) == false,
    "a per-field secret isFullUpdate payload must not activate any buff")
assert(#events == 0, "a per-field secret isFullUpdate payload must not publish a scanner refresh")
assert(probedValues[secretIsFullUpdate] == true,
    "isFullUpdate must be probed via issecretvalue before any boolean test")

-- The scanner keeps working normally afterward: a real payload right after
-- the secret one still binds correctly (the secret probe did not wedge any
-- runtime state).
eventFrame.OnEvent(eventFrame, "UNIT_AURA", "player", {
    addedAuras = {
        { auraInstanceID = 91008 },
    },
})
itemCooldowns[2900] = {
    startTime = now,
    duration = 120,
    enabled = true,
}
eventFrame.OnEvent(eventFrame, "BAG_UPDATE_COOLDOWN")

active, expiration, duration, auraInstanceID, auraUnit = scanner.IsItemActive(2900)
assert(active == true, "scanner should keep working normally after a whole-secret updateInfo payload")
assert(auraInstanceID == 91008 and auraUnit == "player",
    "post-secret-payload aura binding should keep the player aura identity")
assert(events[1][1] == "CDM:COOLDOWN_CHANGED", "post-secret-payload binding should publish CDM refresh")
assert(events[1][2] == 9900, "post-secret-payload refresh should include item use spell")

events = {}
now = 1100
inCombat = true
scanner.RegisterItemUseSpell(3000, 9950)
QUI.db.global.spellScanner.spells[9950] = nil
db.items[3000] = {
    useSpellID = 9950,
    buffSpellID = 8950,
    duration = 20,
    icon = 789,
    name = "Secret Boundary Item Aura",
    scannedAt = 123,
}

-- 68569: a whole-secret UNIT_SPELLCAST_SUCCEEDED spellID must not throw
-- (the sentinel throws on table-index and `<=`, the two operations the
-- pre-fix `if not spellID or spellID <= 0 then return end` guard would
-- have hit) and must have zero observable effect.
local castOk = pcall(eventFrame.OnEvent, eventFrame, "UNIT_SPELLCAST_SUCCEEDED", "player", "cast-guid-secret", secretSpellID)
assert(castOk, "a whole-secret UNIT_SPELLCAST_SUCCEEDED spellID must not throw")
assert(scanner.IsItemActive(3000) == false,
    "a whole-secret spellID must not activate any buff")
assert(#events == 0, "a whole-secret spellID must not publish a scanner refresh")

-- The scanner keeps working normally afterward: a real cast right after the
-- secret one still binds correctly (the secret probe did not wedge state).
eventFrame.OnEvent(eventFrame, "UNIT_SPELLCAST_SUCCEEDED", "player", "cast-guid-3000", 9950)

active, expiration, duration = scanner.IsItemActive(3000)
assert(active == true and expiration == now + 20 and duration == 20,
    "scanner should keep working normally after a whole-secret spellID")
assert(events[1][1] == "CDM:COOLDOWN_CHANGED", "post-secret-spellID binding should publish CDM refresh")
assert(events[1][2] == 9950, "post-secret-spellID refresh should include item use spell")
assert(events[1][4] == "scanner_item", "post-secret-spellID refresh should target item scope")

print("OK: spellscanner_item_registration_test")
