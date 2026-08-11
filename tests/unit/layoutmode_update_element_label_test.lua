local function fail(msg)
    print("FAIL: layoutmode_update_element_label_test - " .. msg)
    os.exit(1)
end

local function auto()
    return setmetatable({}, { __index = function() return function(...) return auto() end end })
end

local ns = {
    L = setmetatable({}, { __index = function(_, k) return k end }),
    UIKit = auto(),
    Helpers = auto(),
    SafeCall = function(...) end,
    SafeCallMethod = function(...) end,
}

CreateFrame = function(...) return auto() end
UIParent = auto()
C_Timer = { After = function(...) end, NewTicker = function(...) return auto() end }

assert(loadfile("modules/layout/layoutmode.lua"))("QUI", ns)

local LM = ns.QUI_LayoutMode
if type(LM) ~= "table" or type(LM.UpdateElementLabel) ~= "function" then
    fail("QUI_LayoutMode:UpdateElementLabel must be defined - cdm_containers.lua calls it "
        .. "behind an existence guard, so a missing definition is a SILENT no-op")
end

local painted
local function FakeLabel()
    return { SetText = function(_, text) painted = text end }
end

LM._elements = LM._elements or {}
LM._handles = LM._handles or {}

LM._elements["cdmCustom_x1"] = { key = "cdmCustom_x1", label = "Old Name" }

if LM:UpdateElementLabel("cdmCustom_x1", "New Name") ~= true then
    fail("UpdateElementLabel must report success for a registered element")
end
if LM._elements["cdmCustom_x1"].label ~= "New Name" then
    fail("UpdateElementLabel must rewrite def.label, got "
        .. tostring(LM._elements["cdmCustom_x1"].label))
end

painted = nil
LM._handles["cdmCustom_x1"] = { _label = FakeLabel() }
if LM:UpdateElementLabel("cdmCustom_x1", "Live Name") ~= true then
    fail("UpdateElementLabel must succeed when a live handle exists")
end
if painted ~= "Live Name" then
    fail("UpdateElementLabel must repaint a live handle's label, got " .. tostring(painted))
end

painted = nil
LM._handles["cdmCustom_x1"] = {}
if LM:UpdateElementLabel("cdmCustom_x1", "No Label Field") ~= true then
    fail("a handle with no _label must not break the rename")
end
if painted ~= nil then fail("nothing should have been painted") end

if LM:UpdateElementLabel("cdmCustom_missing", "Whatever") ~= false then
    fail("an unregistered key must report false, not silently succeed")
end

local before = LM._elements["cdmCustom_x1"].label
for _, bad in ipairs({ "", 7, true }) do
    if LM:UpdateElementLabel("cdmCustom_x1", bad) ~= false then
        fail("a non-string or empty label must be refused: " .. tostring(bad))
    end
end
if LM:UpdateElementLabel("cdmCustom_x1", nil) ~= false then
    fail("a nil label must be refused - FontString:SetText is Nilable = false")
end
if LM:UpdateElementLabel(nil, "Name") ~= false then
    fail("a nil key must be refused")
end
if LM._elements["cdmCustom_x1"].label ~= before then
    fail("a refused rename must leave def.label untouched, got "
        .. tostring(LM._elements["cdmCustom_x1"].label))
end

local src = io.open("QUI_CDM/cdm/cdm_containers.lua"):read("*a")
if not src:find("self:RegisterDynamicFrameResolver(containerKey, settings)", 1, true) then
    fail("RenameContainer must also refresh the frame resolver, or the anchoring "
        .. "dropdown keeps the old name while the mover label updates")
end

print("PASS: layoutmode_update_element_label_test")
