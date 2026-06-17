-- tests/unit/external_skin_bridge_test.lua
-- Run: lua5.1 tests/unit/external_skin_bridge_test.lua
-- Bridge must load with NO external lib present and report unavailable,
-- and must route AddButton/RemoveButton to a group handle when a fake lib
-- is injected via LibStub.

-- Fake LibStub returning a fake skin lib only for the bridge's exact id.
local groups = {}
local fakeLib = {
    Group = function(_, addon, sub)
        local key = addon .. "::" .. sub
        groups[key] = groups[key] or { added = {}, removed = {},
            AddButton = function(self, b) self.added[#self.added + 1] = b end,
            RemoveButton = function(self, b) self.removed[#self.removed + 1] = b end }
        return groups[key]
    end,
}

local ns = {}

-- 1. No LibStub at all → loads, reports unavailable, AddButton is a safe no-op.
_G.LibStub = nil
local Bridge = assert(loadfile("core/external_skin_bridge.lua"))("QUI", ns)
assert(Bridge == ns.ExternalSkinBridge, "module must publish ns.ExternalSkinBridge")
assert(Bridge.IsAvailable() == false, "unavailable without LibStub")
Bridge.AddButton("actionbars", {}, {})  -- must not error

-- 2. Inject a fake lib via LibStub; reload; now available and routes buttons.
_G.LibStub = function(name) if name == "Masque" then return fakeLib end end
local ns2 = {}
local Bridge2 = assert(loadfile("core/external_skin_bridge.lua"))("QUI", ns2)
assert(Bridge2.IsAvailable() == true, "available once lib present")
local btn = {}
Bridge2.AddButton("actionbars", btn, { Icon = {}, Border = {} })
local g = groups["QUI::actionbars"]
assert(g and g.added[1] == btn, "button routed to the right surface group")
Bridge2.RemoveButton("actionbars", btn)
assert(g.removed[1] == btn, "RemoveButton routes to the group")

_G.LibStub = nil
print("external_skin_bridge_test OK")
