-- tests/unit/blizzard_mover_mail_taint_test.lua
-- Run: lua tests/unit/blizzard_mover_mail_taint_test.lua

local function readFile(path)
    local fh = assert(io.open(path, "rb"), "failed to open " .. path)
    local text = fh:read("*a")
    fh:close()
    return text
end

local function blockForId(source, id)
    local pattern = '{%s*id = "' .. id .. '".-defaultEnabled = true,%s*}'
    return source:match(pattern)
end

local frameRegistry = readFile("QUI_QoL/qol/blizzard_mover_frames.lua")

local mailBlock = assert(blockForId(frameRegistry, "MailFrame"), "MailFrame registry entry should exist")
assert(mailBlock:find("secureFrame = true", 1, true), "MailFrame must use secure-frame watcher mode")

local openMailBlock = assert(blockForId(frameRegistry, "OpenMailFrame"), "OpenMailFrame registry entry should exist")
assert(openMailBlock:find("secureFrame = true", 1, true), "OpenMailFrame must use secure-frame watcher mode")

local function noop() end

local frameMeta = {}
frameMeta.__index = function(frame, key)
    if key == "GetName" then
        return function(self) return self.name end
    elseif key == "IsForbidden" then
        return function() return false end
    elseif key == "IsProtected" then
        return function(self) return self.protected or false end
    elseif key == "GetNumPoints" then
        return function() return 1 end
    elseif key == "GetPoint" then
        return function() return "CENTER", UIParent, "CENTER", 0, 0 end
    elseif key == "GetWidth" or key == "GetHeight" then
        return function() return 300 end
    elseif key == "GetSize" then
        return function() return 300, 200 end
    elseif key == "GetScale" then
        return function() return 1 end
    elseif key == "GetFrameStrata" then
        return function() return "MEDIUM" end
    elseif key == "GetFrameLevel" then
        return function(self) return rawget(self, "frameLevel") or 1 end
    elseif key == "IsShown" then
        return function(self) return rawget(self, "shown") or false end
    elseif key == "IsMovable" or key == "IsClampedToScreen" or key == "IsMouseEnabled" or key == "IsMouseWheelEnabled" or key == "IsUserPlaced" then
        return function() return false end
    elseif key == "HookScript" then
        return function(self, script, handler)
            self.hookedScripts[script] = handler
        end
    elseif key == "SetScript" then
        return function(self, script, handler)
            self.scripts[script] = handler
        end
    elseif key == "RegisterEvent" then
        return noop
    elseif key == "SetShown" then
        return function(self, shown) self.shown = shown and true or false end
    elseif key == "Show" then
        return function(self) self.shown = true end
    elseif key == "Hide" then
        return function(self) self.shown = false end
    end
    return noop
end

local function newFrame(name, parent, protected)
    return setmetatable({
        name = name,
        parent = parent,
        protected = protected,
        scripts = {},
        hookedScripts = {},
        secureHooks = {},
        children = {},
    }, frameMeta)
end

UIParent = newFrame("UIParent")
MailFrame = newFrame("MailFrame", UIParent, true)
SendMailFrame = newFrame("SendMailFrame", MailFrame, true)
MailFrameInset = newFrame("MailFrameInset", MailFrame, true)

function CreateFrame(_, name, parent)
    local frame = newFrame(name, parent, false)
    if parent and parent.children then
        table.insert(parent.children, frame)
    end
    return frame
end

function hooksecurefunc(target, method, handler)
    if type(target) == "table" then
        target.secureHooks[method] = handler
    end
end

function InCombatLockdown() return false end
function IsShiftKeyDown() return false end
function IsControlKeyDown() return false end
function IsAltKeyDown() return false end

C_AddOns = {
    IsAddOnLoaded = function() return true end,
}

local profile = {
    blizzardMover = {
        enabled = true,
        requireModifier = true,
        modifier = "SHIFT",
        scaleEnabled = false,
        positionPersistence = "reset",
        frames = {},
    },
}

local ns = {
    Helpers = {
        GetProfile = function()
            return profile
        end,
    },
}

assert(loadfile("QUI_QoL/qol/blizzard_mover.lua"))("QUI", ns)
local mover = assert(ns.QUI_BlizzardMover, "Blizzard mover module should load")
mover.functions.InitDB()

mover.functions.RegisterFrame({
    id = "MailFrame",
    label = "Mail",
    group = "vendors",
    names = { "MailFrame" },
    addon = "Blizzard_MailFrame",
    useRootHandle = true,
    handles = { "SendMailFrame", "MailFrameInset" },
    defaultEnabled = true,
    secureFrame = true,
})

assert(not MailFrame.hookedScripts.OnShow, "secure-frame mover entries must not hook root OnShow")
assert(not MailFrame.hookedScripts.OnHide, "secure-frame mover entries must not hook root OnHide")
assert(not MailFrame.hookedScripts.OnEnter, "secure-frame mover entries must not hook root OnEnter")
assert(not MailFrame.hookedScripts.OnLeave, "secure-frame mover entries must not hook root OnLeave")
assert(not MailFrame.hookedScripts.OnMouseUp, "secure-frame mover entries must not hook root OnMouseUp")
assert(not MailFrame.secureHooks.SetPoint, "secure-frame mover entries must not hook root SetPoint")

assert(#MailFrame.children >= 1, "secure-frame mover entries should still create addon drag strips")

print("OK: blizzard_mover_mail_taint_test")
