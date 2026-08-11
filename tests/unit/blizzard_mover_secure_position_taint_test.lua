-- tests/unit/blizzard_mover_secure_position_taint_test.lua
-- Run: lua tests/unit/blizzard_mover_secure_position_taint_test.lua
--
-- Guards the #1 fix: the mover must reposition PROTECTED frames through a
-- SecureHandlerBaseTemplate :Execute snippet, never via a raw insecure
-- frame:SetPoint (which taints the frame and blocks protected calls such as
-- the world map's OnShow PerformEmote). Non-protected frames keep the raw path.

local secureExecuteCount = 0
local function noop() end

local frameMeta = {}
frameMeta.__index = function(frame, key)
    if key == "GetName" then
        return function(self) return self.name end
    elseif key == "IsForbidden" then
        return function() return false end
    elseif key == "IsProtected" then
        return function(self) return self.protected or false end
    elseif key == "GetPoint" then
        return function() return "CENTER", UIParent, "CENTER", 0, 0 end
    elseif key == "GetScale" then
        return function() return 1 end
    elseif key == "GetFrameLevel" then
        return function() return 1 end
    elseif key == "GetFrameStrata" then
        return function() return "MEDIUM" end
    elseif key == "IsShown" then
        return function(self) return rawget(self, "shown") or false end
    elseif key == "IsMovable" or key == "IsClampedToScreen" or key == "IsMouseEnabled"
        or key == "IsMouseWheelEnabled" or key == "IsUserPlaced" then
        return function() return false end
    elseif key == "SetPoint" then
        return function(self) self.setPointCalls = (self.setPointCalls or 0) + 1 end
    elseif key == "SetScale" then
        return function(self) self.setScaleCalls = (self.setScaleCalls or 0) + 1 end
    elseif key == "ClearAllPoints" then
        return function(self) self.clearCalls = (self.clearCalls or 0) + 1 end
    elseif key == "Execute" then
        return function() secureExecuteCount = secureExecuteCount + 1 end
    elseif key == "HookScript" then
        return function(self, script, handler) self.hookedScripts[script] = handler end
    elseif key == "SetScript" then
        return function(self, script, handler) self.scripts[script] = handler end
    elseif key == "RegisterEvent" then
        return noop
    elseif key == "Show" then
        return function(self) self.shown = true end
    elseif key == "Hide" then
        return function(self) self.shown = false end
    end
    return noop
end

local function newFrame(name, parent, protected)
    return setmetatable({
        name = name, parent = parent, protected = protected,
        scripts = {}, hookedScripts = {}, secureHooks = {}, children = {},
        -- Pre-initialized as raw fields so reads bypass the noop __index.
        setPointCalls = 0, setScaleCalls = 0, clearCalls = 0,
    }, frameMeta)
end

UIParent = newFrame("UIParent")

function CreateFrame(_, name, parent)
    local frame = newFrame(name, parent, false)
    if parent and parent.children then table.insert(parent.children, frame) end
    return frame
end

function hooksecurefunc(target, method, handler)
    if type(target) == "table" then target.secureHooks[method] = handler end
end

function InCombatLockdown() return false end
function IsShiftKeyDown() return false end
function IsControlKeyDown() return false end
function IsAltKeyDown() return false end

C_AddOns = { IsAddOnLoaded = function() return true end }

local profile = {
    blizzardMover = {
        enabled = true,
        requireModifier = true,
        modifier = "SHIFT",
        scaleEnabled = false,
        positionPersistence = "reset",
        frames = {
            ProtectedPanel = { enabled = true, point = "CENTER", x = 120, y = 80 },
            PlainPanel = { enabled = true, point = "TOPLEFT", x = 10, y = -10 },
        },
    },
}

local ns = { Helpers = { GetProfile = function() return profile end } }

assert(loadfile("modules/qol/blizzard_mover.lua"))("QUI", ns)
local mover = assert(ns.QUI_BlizzardMover, "Blizzard mover module should load")
mover.functions.InitDB()

mover.functions.RegisterFrame({
    id = "ProtectedPanel", label = "Protected", group = "world",
    names = { "ProtectedPanel" }, defaultEnabled = true, secureFrame = true,
})
mover.functions.RegisterFrame({
    id = "PlainPanel", label = "Plain", group = "world",
    names = { "PlainPanel" }, defaultEnabled = true,
})

local protectedFrame = newFrame("ProtectedPanel", UIParent, true)
local plainFrame = newFrame("PlainPanel", UIParent, false)

-- Protected frame: must go through the secure positioner, never a raw SetPoint.
secureExecuteCount = 0
mover.functions.applyFrameSettings(protectedFrame, "ProtectedPanel")
assert((protectedFrame.setPointCalls or 0) == 0,
    "protected frame must NOT receive a raw insecure SetPoint (it taints the frame)")
assert((protectedFrame.clearCalls or 0) == 0,
    "protected frame must NOT receive a raw insecure ClearAllPoints")
assert(secureExecuteCount >= 1,
    "protected frame must be positioned via the secure positioner (:Execute)")

-- Non-protected frame: raw path is fine and expected; no secure positioner.
secureExecuteCount = 0
mover.functions.applyFrameSettings(plainFrame, "PlainPanel")
assert((plainFrame.setPointCalls or 0) >= 1,
    "non-protected frame should still use the raw SetPoint path")
assert(secureExecuteCount == 0,
    "non-protected frame must NOT go through the secure positioner")

print("OK: blizzard_mover_secure_position_taint_test")
