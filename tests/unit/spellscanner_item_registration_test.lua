-- tests/unit/spellscanner_item_registration_test.lua
-- Run: lua tests/unit/spellscanner_item_registration_test.lua

local frames = {}
local events = {}
local now = 100
local inCombat = false
local itemCooldowns = {}
local secretAuraInstanceID = { token = "secret-aura-instance" }

QUI = {
    db = {
        global = {},
    },
}

SlashCmdList = {}

function GetTime() return now end
function InCombatLockdown() return inCombat end
function time() return 1234 end
function issecretvalue(value) return value == secretAuraInstanceID end

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

assert(loadfile("QUI_QoL/trackers/spellscanner.lua"))("QUI", ns)

local scanner = assert(QUI.SpellScanner, "SpellScanner should be exported")
assert(scanner.RegisterItemUseSpell(2001, 9002) == true,
    "item use spell registration should succeed")

local eventFrame = assert(frames[1], "event frame should be created")
assert(eventFrame.OnEvent, "event frame should install OnEvent handler")
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

print("OK: spellscanner_item_registration_test")
