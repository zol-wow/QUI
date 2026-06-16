-- tests/unit/groupframes_targeted_spells_runtime_test.lua
-- Run: lua tests/unit/groupframes_targeted_spells_runtime_test.lua

local db = {
    enabled = true,
    party = {
        targetedSpells = {
            enabled = true,
            iconSize = 24,
            maxIcons = 3,
            spacing = 2,
            growDirection = "CENTER",
            position = "CENTER",
            offsetX = 0,
            offsetY = 0,
            reverseSwipe = true,
        },
    },
    raid = {
        targetedSpells = {
            enabled = true,
        },
    },
}

local timers = {}
local now = 100
local durationObject = {
    IsZero = function()
        return false
    end,
}
local displayGateCalls = 0
local castingDurationCalls = 0

local function noop() end

local frameMT
local function NewFrame(parent)
    local frame = {
        parent = parent,
        children = {},
        events = {},
        scripts = {},
        shown = true,
        frameLevel = 1,
    }
    if parent and parent.children then
        parent.children[#parent.children + 1] = frame
    end

    frameMT = frameMT or {
        __index = function(_, key)
            if key == "RegisterEvent" then
                return function(self, event)
                    self.events[event] = true
                end
            elseif key == "UnregisterEvent" then
                return function(self, event)
                    self.events[event] = nil
                end
            elseif key == "SetScript" then
                return function(self, script, handler)
                    self.scripts[script] = handler
                end
            elseif key == "CreateTexture" then
                return function(self)
                    return NewFrame(self)
                end
            elseif key == "SetTexture" then
                return function(self, texture)
                    self.texture = texture
                end
            elseif key == "SetTexCoord" then
                return function(self, ...)
                    self.texCoord = { ... }
                end
            elseif key == "SetAllPoints" then
                return noop
            elseif key == "SetDrawEdge" then
                return noop
            elseif key == "SetDrawSwipe" then
                return function(self, value)
                    self.drawSwipe = value
                end
            elseif key == "SetSwipeColor" then
                return noop
            elseif key == "SetHideCountdownNumbers" then
                return noop
            elseif key == "SetReverse" then
                return function(self, value)
                    self.reverse = value
                end
            elseif key == "SetCooldownFromDurationObject" then
                return function(self, object)
                    self.durationObject = object
                end
            elseif key == "SetAlphaFromBoolean" then
                return function(self, value, falseAlpha, trueAlpha)
                    self.alphaFromBoolean = { value, falseAlpha, trueAlpha }
                end
            elseif key == "SetAlpha" then
                return function(self, value)
                    self.alpha = value
                end
            elseif key == "SetCooldown" then
                return function(self, start, duration)
                    self.cooldown = { start, duration }
                end
            elseif key == "Clear" then
                return function(self)
                    self.cleared = true
                    self.durationObject = nil
                    self.cooldown = nil
                end
            elseif key == "SetBackdrop" then
                return noop
            elseif key == "SetBackdropBorderColor" then
                return noop
            elseif key == "SetSize" then
                return function(self, width, height)
                    self.width = width
                    self.height = height
                end
            elseif key == "GetParent" then
                return function(self)
                    return self.parent
                end
            elseif key == "GetFrameLevel" then
                return function(self)
                    return self.frameLevel
                end
            elseif key == "SetFrameLevel" then
                return function(self, level)
                    self.frameLevel = level
                end
            elseif key == "Hide" then
                return function(self)
                    self.shown = false
                end
            elseif key == "Show" then
                return function(self)
                    self.shown = true
                end
            elseif key == "IsShown" then
                return function(self)
                    return self.shown
                end
            elseif key == "ClearAllPoints" then
                return function(self)
                    self.points = {}
                end
            elseif key == "SetPoint" then
                return function(self, ...)
                    self.points = self.points or {}
                    self.points[#self.points + 1] = { ... }
                end
            end
            return noop
        end,
    }

    return setmetatable(frame, frameMT)
end

local eventFrame
function CreateFrame(_, _, parent)
    local frame = NewFrame(parent)
    if not parent and not eventFrame then
        eventFrame = frame
    end
    return frame
end

function wipe(tbl)
    for key in pairs(tbl) do
        tbl[key] = nil
    end
end

function GetTime()
    return now
end

C_Timer = {
    After = function(delay, callback)
        timers[#timers + 1] = { delay = delay, callback = callback }
    end,
}

C_NamePlate = {
    GetNamePlates = function()
        return {}
    end,
}

function UnitExists(unit)
    return unit == "party1"
end

function UnitClass(unit)
    if unit == "party1" or unit == "nameplate1target" then
        return "Paladin", "PALADIN"
    end
    return nil, nil
end

function UnitRace(unit)
    if unit == "party1" or unit == "nameplate1target" then
        return "Human", "Human"
    end
    return nil, nil
end

function UnitSex(unit)
    if unit == "party1" or unit == "nameplate1target" then
        return 2
    end
    return nil
end

function UnitGroupRolesAssigned(unit)
    if unit == "party1" or unit == "nameplate1target" then
        return "DAMAGER"
    end
    return "NONE"
end

local casting = true
function UnitCastingInfo(unit)
    if unit == "nameplate1" and casting then
        return "Targeted Fire", nil, 135807, 100000, 104000
    end
    return nil
end

function UnitChannelInfo()
    return nil
end

function UnitCastingDuration(unit)
    if unit == "nameplate1" then
        castingDurationCalls = castingDurationCalls + 1
        return durationObject
    end
    return nil
end

function UnitChannelDuration()
    return nil
end

function UnitCanAttack(player, unit)
    return player == "player" and unit == "nameplate1"
end

function UnitShouldDisplaySpellTargetName(unit)
    if unit == "nameplate1" then
        displayGateCalls = displayGateCalls + 1
        return true
    end
    return false
end

function IsInGroup()
    return true
end

function IsInRaid()
    return false
end

local ns = {
    Helpers = {
        CreateDBGetter = function()
            return function()
                return db
            end
        end,
        IsSecretValue = function()
            return false
        end,
    },
    QUI_GroupFrames = {
        unitFrameMap = {},
    },
}

local groupFrame = NewFrame(nil)
groupFrame.healthBar = NewFrame(groupFrame)
ns.QUI_GroupFrames.unitFrameMap.party1 = { groupFrame }

assert(loadfile("QUI_GroupFrames/groupframes/groupframes_targeted_spells.lua"))("QUI", ns)
assert(ns.QUI_GroupFrameTargetedSpells, "targeted spells module should export its API")
assert(eventFrame, "targeted spells module should create an event frame")
assert(eventFrame.events.PLAYER_LOGIN, "module should listen for login activation")

eventFrame.scripts.OnEvent(eventFrame, "PLAYER_LOGIN")
assert(eventFrame.events.NAME_PLATE_UNIT_ADDED, "active module should watch nameplate additions")
assert(eventFrame.events.UNIT_TARGET, "active module should watch nameplate retargets")
assert(eventFrame.events.UNIT_SPELLCAST_START, "active module should watch cast starts")

eventFrame.scripts.OnEvent(eventFrame, "NAME_PLATE_UNIT_ADDED", "nameplate1")
assert(#timers == 2, "nameplate cast should schedule pickup and verify resolves")

table.sort(timers, function(a, b)
    return a.delay < b.delay
end)
while #timers > 0 do
    local timer = table.remove(timers, 1)
    now = now + timer.delay
    timer.callback()
end

local icon = assert(groupFrame.children[2], "targeted spell icon should be parented to the group frame")
assert(rawget(icon, "_targetedCaster") == "nameplate1", "icon should be assigned to the hostile caster")
assert(icon.shown == true, "icon should be shown after delayed target resolution")
assert(icon._texture.texture == 135807, "icon should use the casting spell texture")
assert(icon._cooldown.durationObject == durationObject, "icon should use the Blizzard duration object cooldown path")
assert(displayGateCalls > 0, "cast flow should gate through UnitShouldDisplaySpellTargetName")
assert(castingDurationCalls > 0, "cast flow should query UnitCastingDuration")

casting = false
eventFrame.scripts.OnEvent(eventFrame, "UNIT_SPELLCAST_STOP", "nameplate1")
assert(rawget(icon, "_targetedCaster") == nil, "stop event should release the caster assignment")
assert(icon.shown == false, "stop event should hide the targeted spell icon")
assert(icon._cooldown.shown == false, "stop event should hide the cooldown swipe")

print("OK: groupframes_targeted_spells_runtime_test")
