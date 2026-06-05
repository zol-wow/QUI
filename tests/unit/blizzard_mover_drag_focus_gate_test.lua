-- tests/unit/blizzard_mover_drag_focus_gate_test.lua
-- Run: lua tests/unit/blizzard_mover_drag_focus_gate_test.lua
-- luacheck: globals UIParent TestMoverPanel CreateFrame hooksecurefunc InCombatLockdown
-- luacheck: globals IsShiftKeyDown IsControlKeyDown IsAltKeyDown GetMouseFoci C_AddOns

local currentFoci = {}

local frameMeta = {}
frameMeta.__index = function(frame, key)
	if key == "GetName" then
		return function(self) return self.name end
	elseif key == "SetParent" then
		return function(self, parent) self.parent = parent end
	elseif key == "GetParent" then
		return function(self) return self.parent end
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
		return function(self) return rawget(self, "scale") or 1 end
	elseif key == "GetFrameStrata" then
		return function() return "MEDIUM" end
	elseif key == "GetFrameLevel" then
		return function(self) return rawget(self, "frameLevel") or 1 end
	elseif key == "IsShown" then
		return function(self) return rawget(self, "shown") ~= false end
	elseif key == "IsMovable" then
		return function(self) return rawget(self, "movable") or false end
	elseif key == "IsClampedToScreen" then
		return function(self) return rawget(self, "clamped") or false end
	elseif key == "IsMouseEnabled" then
		return function(self) return rawget(self, "mouseEnabled") or false end
	elseif key == "IsMouseClickEnabled" then
		return function(self) return rawget(self, "mouseClickEnabled") or false end
	elseif key == "IsMouseWheelEnabled" then
		return function(self) return rawget(self, "mouseWheelEnabled") or false end
	elseif key == "IsUserPlaced" then
		return function(self) return rawget(self, "userPlaced") or false end
	elseif key == "SetMovable" then
		return function(self, enabled) self.movable = enabled and true or false end
	elseif key == "SetClampedToScreen" then
		return function(self, enabled) self.clamped = enabled and true or false end
	elseif key == "SetUserPlaced" then
		return function(self, enabled) self.userPlaced = enabled and true or false end
	elseif key == "EnableMouse" then
		return function(self, enabled)
			self.mouseEnabled = enabled and true or false
			self.mouseClickEnabled = enabled and true or false
		end
	elseif key == "EnableMouseWheel" then
		return function(self, enabled) self.mouseWheelEnabled = enabled and true or false end
	elseif key == "SetFrameStrata" then
		return function(self, strata) self.frameStrata = strata end
	elseif key == "SetFrameLevel" then
		return function(self, level) self.frameLevel = level end
	elseif key == "SetAllPoints" then
		return function(self, target) self.allPoints = target or true end
	elseif key == "ClearAllPoints" then
		return function(self) self.cleared = true end
	elseif key == "SetPoint" then
		return function(self, point, relative, relativePoint, x, y)
			self.point = { point, relative, relativePoint, x, y }
		end
	elseif key == "SetScale" then
		return function(self, scale) self.scale = scale end
	elseif key == "SetPropagateMouseMotion" then
		return function(self, enabled) self.propagateMotion = enabled and true or false end
	elseif key == "SetPropagateMouseClicks" then
		return function(self, enabled) self.propagateClicks = enabled and true or false end
	elseif key == "RegisterForDrag" then
		return function(self, button) self.dragButton = button end
	elseif key == "HookScript" then
		return function(self, script, handler) self.hookedScripts[script] = handler end
	elseif key == "SetScript" then
		return function(self, script, handler) self.scripts[script] = handler end
	elseif key == "RegisterEvent" then
		return function(self, event) self.events[event] = true end
	elseif key == "SetShown" then
		return function(self, shown) self.shown = shown and true or false end
	elseif key == "Show" then
		return function(self) self.shown = true end
	elseif key == "Hide" then
		return function(self) self.shown = false end
	elseif key == "StartMoving" then
		return function(self) self.startMovingCalls = self.startMovingCalls + 1 end
	elseif key == "StopMovingOrSizing" then
		return function(self) self.stopMovingCalls = self.stopMovingCalls + 1 end
	end
	return function() end
end

local function newFrame(name, parent, protected)
	local frame = setmetatable({
		name = name,
		parent = parent,
		protected = protected,
		children = {},
		events = {},
		hookedScripts = {},
		scripts = {},
		startMovingCalls = 0,
		stopMovingCalls = 0,
	}, frameMeta)
	if parent and parent.children then
		parent.children[#parent.children + 1] = frame
	end
	return frame
end

UIParent = newFrame("UIParent")
TestMoverPanel = newFrame("TestMoverPanel", UIParent)

function CreateFrame(_, name, parent)
	local frame = newFrame(name or "anonymousFrame", parent or UIParent)
	if name then _G[name] = frame end
	return frame
end

function hooksecurefunc(target, method, handler)
	local hooks = rawget(target, "secureHooks")
	if not hooks then
		hooks = {}
		target.secureHooks = hooks
	end
	hooks[method] = handler
end

function InCombatLockdown() return false end
function IsShiftKeyDown() return true end
function IsControlKeyDown() return false end
function IsAltKeyDown() return false end
function GetMouseFoci() return currentFoci end

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
		GetProfile = function() return profile end,
	},
}

assert(loadfile("modules/qol/blizzard_mover.lua"))("QUI", ns)
local mover = assert(ns.QUI_BlizzardMover, "mover module should load")
mover.functions.InitDB()
mover.functions.RegisterFrame({
	id = "TestMoverPanel",
	label = "Test",
	group = "system",
	names = { "TestMoverPanel" },
	useRootHandle = true,
	defaultEnabled = true,
})

local strip = assert(TestMoverPanel.children[1], "root drag strip should be created")
assert(strip.hookedScripts.OnDragStart, "drag strip should hook OnDragStart")
assert(strip.hookedScripts.OnDragStop, "drag strip should hook OnDragStop")

local childControl = newFrame("ChildControl", TestMoverPanel)
childControl.mouseClickEnabled = true

currentFoci = { strip, TestMoverPanel, childControl }
strip.hookedScripts.OnDragStart(strip)
assert(TestMoverPanel.startMovingCalls == 0, "interactive child focus should veto frame movement")

strip.hookedScripts.OnDragStop(strip)
assert(TestMoverPanel.stopMovingCalls == 0, "vetoed drag should not stop or store movement")
assert(not profile.blizzardMover.frames.TestMoverPanel.point, "vetoed drag should not save a position")

childControl.mouseClickEnabled = false
childControl.mouseWheelEnabled = true
strip.hookedScripts.OnDragStart(strip)
assert(TestMoverPanel.startMovingCalls == 0, "mouse wheel child focus should veto frame movement")

currentFoci = { strip, TestMoverPanel }
strip.hookedScripts.OnDragStart(strip)
assert(TestMoverPanel.startMovingCalls == 1, "plain mover focus should start frame movement")

strip.hookedScripts.OnDragStop(strip)
assert(TestMoverPanel.stopMovingCalls == 1, "started drag should stop frame movement")
assert(profile.blizzardMover.frames.TestMoverPanel.point == "CENTER", "started drag should save a position")

print("OK: blizzard_mover_drag_focus_gate_test")
