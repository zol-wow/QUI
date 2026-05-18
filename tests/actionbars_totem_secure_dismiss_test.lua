-- tests/actionbars_totem_secure_dismiss_test.lua
-- Run: lua tests/actionbars_totem_secure_dismiss_test.lua

local totemDB = {
    enabled = true,
    growDirection = "RIGHT",
    spacing = 4,
    iconSize = 36,
    hideDurationText = true,
}

local inCombat = false
local function noop() end

local frameMT
local function NewFrame(frameType, name, parent, template)
    local frame = {
        frameType = frameType,
        name = name,
        parent = parent,
        template = template,
        attributes = {},
        scripts = {},
        registeredClicks = {},
        shown = false,
    }

    frameMT = frameMT or {
        __index = function(_, key)
            if key == "SetAttribute" then
                return function(self, attr, value)
                    assert(not inCombat, "totem bar should not mutate secure attributes in combat")
                    self.attributes[attr] = value
                end
            elseif key == "GetAttribute" then
                return function(self, attr)
                    return self.attributes[attr]
                end
            elseif key == "RegisterForClicks" then
                return function(self, ...)
                    assert(not inCombat, "totem bar should not register secure clicks in combat")
                    self.registeredClicks = { ... }
                end
            elseif key == "SetScript" then
                return function(self, script, handler)
                    self.scripts[script] = handler
                end
            elseif key == "GetScript" then
                return function(self, script)
                    return self.scripts[script]
                end
            elseif key == "CreateTexture" or key == "CreateFontString" then
                return function(self)
                    return NewFrame(key, nil, self, nil)
                end
            elseif key == "Show" then
                return function(self)
                    self.shown = true
                end
            elseif key == "Hide" then
                return function(self)
                    self.shown = false
                end
            elseif key == "IsShown" then
                return function(self)
                    return self.shown
                end
            elseif key == "GetCenter" then
                return function()
                    return 0, 0
                end
            elseif key == "GetLeft" or key == "GetRight" or key == "GetTop" or key == "GetBottom" then
                return function()
                    return 0
                end
            elseif key == "Clear" then
                return function(self)
                    self.cleared = (rawget(self, "cleared") or 0) + 1
                end
            end
            return noop
        end,
    }

    return setmetatable(frame, frameMT)
end

UIParent = NewFrame("Frame", "UIParent", nil, nil)
QUI = {}
MAX_TOTEMS = 4
STANDARD_TOTEM_PRIORITIES = { 1, 2, 3, 4 }
SHAMAN_TOTEM_PRIORITIES = nil
GameTooltip = {
    SetOwner = noop,
    SetTotem = noop,
    Show = noop,
    Hide = noop,
}

function CreateFrame(frameType, name, parent, template)
    local frame = NewFrame(frameType, name, parent, template)
    if name then
        _G[name] = frame
    end
    return frame
end

function InCombatLockdown()
    return inCombat
end

function GetTotemInfo()
    return false, "", 0, 0, 0
end

function GetTotemTimeLeft()
    return 0
end

C_Timer = {
    After = noop,
    NewTicker = function()
        return { Cancel = noop }
    end,
}

local ns = {
    LSM = {},
    Addon = {
        db = { profile = { frameAnchoring = {} } },
        Pixels = function(_, value) return value end,
        PixelRound = function(_, value) return value end,
    },
    Helpers = {
        CreateDBGetter = function(key)
            assert(key == "totemBar", "totem module should request the totemBar DB")
            return function()
                return totemDB
            end
        end,
        ApplyCooldownFromStart = function()
            return false
        end,
        GetGeneralFont = function()
            return "Fonts\\FRIZQT__.TTF"
        end,
        GetGeneralFontOutline = function()
            return ""
        end,
        IsSecretValue = function()
            return false
        end,
    },
    Registry = {
        Register = noop,
    },
}

assert(loadfile("modules/actionbars/totems.lua"))("QUI", ns)

local TotemBar = assert(ns.QUI_TotemBar, "totem bar module should export QUI_TotemBar")
TotemBar:Refresh()

for i = 1, MAX_TOTEMS do
    local button = assert(TotemBar.buttons[i], "totem button should exist")
    assert(button.template == "SecureActionButtonTemplate",
        "totem buttons must use SecureActionButtonTemplate")
    assert(button.registeredClicks[1] == "RightButtonUp",
        "totem buttons must register right-click release")
    assert(button.attributes.type2 == "destroytotem",
        "right-click should use Blizzard's secure destroytotem action")
    assert(button.attributes["*type2"] == "destroytotem",
        "modified right-click should use Blizzard's secure destroytotem action")
    assert(button.attributes["totem-slot"] == i,
        "generic totem slot attribute should target the displayed slot")
    assert(button.attributes["totem-slot2"] == i,
        "right-click totem slot attribute should target the displayed slot")
    assert(button.attributes["*totem-slot2"] == i,
        "modified right-click totem slot attribute should target the displayed slot")
end

STANDARD_TOTEM_PRIORITIES = { 4, 3, 2, 1 }
TotemBar:Refresh()
assert(TotemBar.buttons[1].attributes["totem-slot"] == 4,
    "out-of-combat refresh should update secure slot attributes when display order changes")

inCombat = true
STANDARD_TOTEM_PRIORITIES = { 1, 2, 3, 4 }
TotemBar:Refresh()
assert(TotemBar.buttons[1].attributes["totem-slot"] == 4,
    "combat refresh should defer protected slot-attribute mutations")

inCombat = false
TotemBar:Refresh()
assert(TotemBar.buttons[1].attributes["totem-slot"] == 1,
    "out-of-combat refresh should reconcile deferred slot-attribute mutations")
