-- tests/unit/minimap_drawer_filter_test.lua
-- Run: lua tests/unit/minimap_drawer_filter_test.lua

local function noop() end

local Frame = {}
Frame.__index = Frame

local function newFrame(name, objectType, parent)
    return setmetatable({
        name = name,
        objectType = objectType or "Frame",
        parent = parent,
        scripts = {},
        children = {},
    }, Frame)
end

function Frame:IsObjectType(objectType)
    return self.objectType == objectType or objectType == "Frame"
end

function Frame:GetName()
    return self.name
end

function Frame:GetParent()
    return self.parent
end

function Frame:GetChildren()
    return unpack(self.children)
end

function Frame:HasScript(scriptName)
    return self.scripts[scriptName] ~= nil
end

function Frame:GetScript(scriptName)
    return self.scripts[scriptName]
end

function Frame:SetScript(scriptName, handler)
    self.scripts[scriptName] = handler
end

function Frame:RegisterEvent() end
function Frame:UnregisterEvent() end
function Frame:Hide() end
function Frame:Show() end

UIParent = newFrame("UIParent")
Minimap = newFrame("Minimap", "Frame", UIParent)
MinimapCluster = newFrame("MinimapCluster", "Frame", UIParent)
MinimapBackdrop = newFrame("MinimapBackdrop", "Frame", UIParent)

function CreateFrame(_, name, parent)
    local frame = newFrame(name, "Frame", parent or UIParent)
    if parent and parent.children then
        parent.children[#parent.children + 1] = frame
    end
    return frame
end

function InCombatLockdown()
    return false
end

function issecurevariable()
    return false
end

function hooksecurefunc() end

LibStub = function()
    return nil
end

C_Timer = {
    After = noop,
    NewTimer = function()
        return { Cancel = noop }
    end,
    NewTicker = function()
        return { Cancel = noop }
    end,
}

local ns = {
    Addon = { db = { profile = { minimapButton = { hide = false } } } },
    Helpers = {
        GetModuleDB = function()
            return {
                enabled = true,
                buttonDrawer = { enabled = true },
            }
        end,
        CreateDBGetter = function()
            return function()
                return {}
            end
        end,
        SafeToNumber = function(value, fallback)
            return tonumber(value) or fallback
        end,
    },
}

assert(loadfile("QUI_Minimap/minimap/minimap.lua"))("QUI", ns)

local function findUpvalue(func, wanted, seen)
    seen = seen or {}
    if seen[func] then return nil end
    seen[func] = true

    local i = 1
    while true do
        local name, value = debug.getupvalue(func, i)
        if not name then return nil end
        if name == wanted then return value end
        if type(value) == "function" then
            local found = findUpvalue(value, wanted, seen)
            if found then return found end
        end
        i = i + 1
    end
end

local refresh = assert(_G.QUI_RefreshMinimapButtonDrawer, "drawer refresh function should be exported")
local isDrawerCandidate = assert(findUpvalue(refresh, "IsMinimapButton"),
    "drawer candidate classifier should be reachable")

local launcher = newFrame("SampleMinimapButton", "Button", UIParent)
assert(isDrawerCandidate(launcher) == true,
    "named minimap launcher buttons should remain drawer candidates")

local ldbLauncher = newFrame("LibDBIcon10_Sample", "Button", UIParent)
assert(isDrawerCandidate(ldbLauncher) == true,
    "LibDBIcon launcher buttons should remain drawer candidates")

local numericIconPin = newFrame("WaypointMinimapIcon1", "Button", Minimap)
numericIconPin:SetScript("OnClick", noop)
assert(isDrawerCandidate(numericIconPin) == false,
    "numeric minimap icon frames should stay on the minimap instead of entering the drawer")

local numericButtonPin = newFrame("WaypointMinimapButton42", "Button", Minimap)
numericButtonPin:SetScript("OnMouseUp", noop)
assert(isDrawerCandidate(numericButtonPin) == false,
    "numeric minimap button frames should stay on the minimap instead of entering the drawer")

print("OK: minimap_drawer_filter_test")
