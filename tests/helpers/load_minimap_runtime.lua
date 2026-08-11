-- tests/helpers/load_minimap_runtime.lua
-- Loads modules/minimap/minimap.lua under a stub WoW environment and returns
-- handles for poking at its file-local internals.
--
-- Extracted from tests/unit/minimap_drawer_filter_test.lua so more than one
-- test can load the minimap module without duplicating ~95 lines of stubs.
-- The stubs are deliberately minimal: minimap.lua only *creates* frames when a
-- refresh runs, so load-time needs far less surface than a full frame fake.
-- luacheck: globals UIParent Minimap MinimapCluster MinimapBackdrop
-- luacheck: globals MicroMenuPositionEnum MicroMenuContainer MicroMenu
-- luacheck: globals QueueStatusButton CreateFrame InCombatLockdown
-- luacheck: globals issecurevariable hooksecurefunc LibStub C_Timer

local function noop() end

local Frame = {}
Frame.__index = Frame
local createdFrames = {}

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

function Frame:RegisterEvent(event)
    self.events = self.events or {}
    self.events[event] = true
end
function Frame:UnregisterEvent(event)
    if self.events then self.events[event] = nil end
end
function Frame:Hide() end
function Frame:Show() end
function Frame:GetPoint() end
function Frame:GetWidth() return self.width or 32 end
function Frame:GetHeight() return self.height or 32 end
function Frame:SetParent(parent) self.parent = parent end
function Frame:SetScale(scale) self.scale = scale end
function Frame:SetSize(width, height) self.width, self.height = width, height end
function Frame:SetFrameStrata(strata) self.strata = strata end

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

return function()
    UIParent = newFrame("UIParent")
    Minimap = newFrame("Minimap", "Frame", UIParent)
    MinimapCluster = newFrame("MinimapCluster", "Frame", UIParent)
    MinimapBackdrop = newFrame("MinimapBackdrop", "Frame", UIParent)
    MicroMenuPositionEnum = { BottomLeft = 1, BottomRight = 2, TopLeft = 3, TopRight = 4 }
    MicroMenuContainer = newFrame("MicroMenuContainer", "Frame", UIParent)
    MicroMenu = newFrame("MicroMenu", "Frame", MicroMenuContainer)
    MicroMenu.isHorizontal = true
    function MicroMenuContainer:GetPosition()
        return MicroMenuPositionEnum.BottomRight
    end
    QueueStatusButton = newFrame("QueueStatusButton", "Button", MicroMenu)
    function QueueStatusButton:UpdatePosition(microMenuPosition, isMenuHorizontal)
        assert(microMenuPosition ~= nil, "QueueStatusButton UpdatePosition requires a micro-menu position")
        self.lastMicroMenuPosition = microMenuPosition
        self.lastIsMenuHorizontal = isMenuHorizontal
    end

    function CreateFrame(_, name, parent)
        local frame = newFrame(name, "Frame", parent or UIParent)
        createdFrames[#createdFrames + 1] = frame
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
        SafeCall = function(_policy, fn, ...) return pcall(fn, ...) end,
        SafeCallMethod = function(_policy, obj, name, ...) return pcall(function(...) return obj[name](obj, ...) end, ...) end,
        SafeCallMethodIfPresent = function(_policy, obj, name, ...) if obj == nil then return nil end local okP, m = pcall(function() return obj[name] end) if not okP then return false end if m == nil then return nil end return pcall(m, obj, ...) end,
        Helpers = {
            GetModuleDB = function()
                return {
                    enabled = true,
                    buttonDrawer = { enabled = true },
                    dungeonEye = { enabled = false },
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

    assert(loadfile("modules/minimap/minimap.lua"))("QUI", ns)

    return {
        ns = ns,
        findUpvalue = findUpvalue,
        createdFrames = createdFrames,
        newFrame = newFrame,
    }
end
