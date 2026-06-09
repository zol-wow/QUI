-- tests/unit/reticle_layering_test.lua
-- Run: lua tests/unit/reticle_layering_test.lua

local createdByName = {}
local eventFrame

local function noop() end

local frameMeta = {}
frameMeta.__index = function(frame, key)
    if key == "SetFrameStrata" then
        return function(self, strata) self.frameStrata = strata end
    elseif key == "SetFrameLevel" then
        return function(self, level) self.frameLevel = level end
    elseif key == "GetFrameLevel" then
        return function(self) return self.frameLevel or 10 end
    elseif key == "SetSize"
        or key == "SetAllPoints" or key == "SetPoint"
        or key == "EnableMouse" or key == "SetDrawSwipe"
        or key == "SetDrawEdge" or key == "SetHideCountdownNumbers"
        or key == "SetDrawBling" or key == "SetUseCircularEdge"
        or key == "SetTexture" or key == "SetVertexColor"
        or key == "SetAlpha" or key == "SetSwipeTexture"
        or key == "SetSwipeColor" or key == "SetReverse"
        or key == "SetAtlas" then
        return noop
    elseif key == "Show" then
        return function(self) self.shown = true end
    elseif key == "Hide" then
        return function(self) self.shown = false end
    elseif key == "IsShown" then
        return function(self) return self.shown and true or false end
    elseif key == "CreateTexture" then
        return function(self, _, drawLayer)
            local texture = setmetatable({ drawLayer = drawLayer, children = {}, scripts = {} }, frameMeta)
            table.insert(self.children, texture)
            return texture
        end
    elseif key == "RegisterEvent" then
        return function(self, event) self.events[event] = true end
    elseif key == "RegisterUnitEvent" then
        return function(self, event) self.events[event] = true end
    elseif key == "UnregisterEvent" then
        return function(self, event) self.events[event] = nil end
    elseif key == "SetScript" then
        return function(self, script, handler) self.scripts[script] = handler end
    elseif key == "HookScript" then
        return noop
    end
    return nil
end

local function newFrame(name, parent, frameType)
    local frame = setmetatable({
        name = name,
        parent = parent,
        frameType = frameType,
        frameLevel = 10,
        children = {},
        scripts = {},
        events = {},
    }, frameMeta)
    if name then
        createdByName[name] = frame
    end
    if parent and parent.children then
        table.insert(parent.children, frame)
    end
    return frame
end

UIParent = newFrame("UIParent")
WorldFrame = newFrame("WorldFrame", UIParent)

function CreateFrame(frameType, name, parent)
    local frame = newFrame(name, parent, frameType)
    if not name and not parent and not eventFrame then
        eventFrame = frame
    end
    return frame
end

function InCombatLockdown()
    return true
end

function UnitClass()
    return "Player", "MAGE"
end

C_ClassColor = {
    GetClassColor = function()
        return { r = 0.2, g = 0.6, b = 1 }
    end,
}

function GetScaledCursorPosition()
    return 500, 500
end

function GetTime()
    return 1
end

function IsLoggedIn()
    return true
end

C_Timer = {
    After = function(_, callback) callback() end,
}

local ns = {
    Helpers = {
        AssetPath = "Interface\\AddOns\\QUI\\media\\",
        GetModuleDB = function(moduleName)
            assert(moduleName == "reticle", "unexpected module db request")
            return {
                enabled = true,
                hideOutOfCombat = false,
                useClassColor = false,
                customColor = { 0.2, 0.6, 1, 1 },
                inCombatAlpha = 0.8,
                outCombatAlpha = 0.3,
                ringStyle = "standard",
                ringSize = 40,
                reticleStyle = "dot",
                reticleSize = 10,
                gcdEnabled = false,
                offsetX = 0,
                offsetY = 0,
            }
        end,
        CreateTimeThrottle = function(_, callback)
            return callback
        end,
        ApplyCooldownFromSpell = function()
            return false
        end,
    },
    QUI = {},
    -- Eager-LOD modules never receive their own ADDON_LOADED, so reticle inits
    -- via ns.WhenLoggedIn (runs immediately when already logged in). This stub
    -- mirrors that: init runs during loadfile, not off a fired ADDON_LOADED.
    WhenLoggedIn = function(fn) if fn then fn() end end,
}

assert(loadfile("QUI_QoL/qol/reticle.lua"))("QUI", ns)
assert(eventFrame and eventFrame.scripts.OnEvent, "reticle should register an event handler")

local reticle = assert(createdByName.QUI_Reticle, "reticle frame should be created")
assert(reticle.frameStrata == "TOOLTIP", "reticle should render in tooltip strata")
assert(reticle.frameLevel > 9000, "reticle should render above tooltip-level game menu button overlays")

local cooldown
for _, child in ipairs(reticle.children) do
    if child.frameType == "Cooldown" then
        cooldown = child
        break
    end
end
assert(cooldown and cooldown.frameLevel > reticle.frameLevel, "reticle cooldown swipe should stay above the ring frame")

print("OK: reticle_layering_test")
