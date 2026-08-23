-- tests/unit/groupframes_clickcast_dynamic_apply_test.lua
-- Run: lua tests/unit/groupframes_clickcast_dynamic_apply_test.lua
--
-- Repro probe: changing a click-cast binding out of combat should re-apply to
-- already-registered frames immediately (the UI path is AddBinding/RemoveBinding
-- -> RefreshBindings). User reports the change only takes effect after /reload.
-- This test exercises the pure-Lua apply path with mocked frames to determine
-- whether RefreshBindings actually updates a live frame's secure attributes.

local inCombat = false
local function noop() end

-- ---- spell tables -------------------------------------------------------
local SPELL_NAMES = { [774] = "Rejuvenation", [8936] = "Regrowth" }
local NAME_TO_ID  = { Rejuvenation = 774, Regrowth = 8936 }

-- ---- frame mock ---------------------------------------------------------
local frameMT
local function NewFrame(frameType, name, parent, template)
    local frame = {
        frameType = frameType, name = name, parent = parent, template = template,
        attributes = {}, scripts = {}, hooks = {}, events = {},
        secureWraps = {}, overrideBindings = {}, frameRefs = {},
    }
    frameMT = frameMT or {
        __index = function(_, key)
            if key == "SetAttribute" then
                return function(self, attr, value)
                    assert(not inCombat, "must not mutate secure attributes in combat")
                    self.attributes[attr] = value
                end
            elseif key == "GetAttribute" then
                return function(self, attr) return self.attributes[attr] end
            elseif key == "GetName" then
                return function(self) return self.name end
            elseif key == "SetScript" then
                return function(self, s, h) self.scripts[s] = h end
            elseif key == "HookScript" then
                return function(self, s, h) self.hooks[s] = self.hooks[s] or {}; table.insert(self.hooks[s], h) end
            elseif key == "RegisterEvent" then
                return function(self, e) self.events[e] = true end
            elseif key == "CreateTexture" or key == "CreateFontString" then
                return function(self) return NewFrame(key, nil, self, nil) end
            elseif key == "EnableMouseWheel" then
                return function(self, enabled) self.mouseWheelEnabled = enabled end
            elseif key == "ClearBindings" then
                return function(self) self.overrideBindings = {} end
            elseif key == "SetBindingClick" then
                return function(self, priority, bindKey, target, button)
                    self.overrideBindings[bindKey] = { priority = priority, target = target, button = button }
                end
            elseif key == "SetFrameRef" then
                return function(self, label, ref) self.frameRefs[label] = ref end
            elseif key == "GetFrameRef" then
                return function(self, label) return self.frameRefs[label] end
            elseif key == "IsVisible" then
                return function(self) return self.visible ~= false end
            elseif key == "GetMousePosition" then
                return function(self)
                    if self.underMouse == true then return 0.5, 0.5 end
                    return nil
                end
            elseif key == "Execute" then
                return function(self, snippet)
                    local loader = loadstring or load
                    local chunk, err = loader("local self = ...\n" .. snippet)
                    assert(chunk, err)
                    return chunk(self)
                end
            end
            return noop
        end,
    }
    return setmetatable(frame, frameMT)
end

function CreateFrame(frameType, name, parent, template)
    local f = NewFrame(frameType, name, parent, template)
    if name then _G[name] = f end
    return f
end

function InCombatLockdown() return inCombat end
function UnitClass() return "Druid", "DRUID" end
function UnitIsDeadOrGhost() return false end
function UnitIsConnected() return true end
function UnitIsPlayer() return true end
function GetSpecialization() return 1 end
function GetSpecializationInfo() return 102 end -- Balance specID (arbitrary)
SecureHandlerWrapScript = noop
RegisterStateDriver = noop
RegisterAttributeDriver = noop
UnregisterStateDriver = noop
GameTooltip = { GetOwner = function() return nil end, AddLine = noop, AddDoubleLine = noop, Show = noop }
_G.wipe = function(t) for k in pairs(t) do t[k] = nil end return t end

C_Timer = { After = function() end, NewTimer = function() return { Cancel = noop } end }

C_Spell = {
    GetSpellName = function(id) return SPELL_NAMES[id] end,
    GetSpellIDForSpellIdentifier = function(name) return NAME_TO_ID[name] end,
    GetBaseSpell = function(id) return id end,
}
C_ClassTalents = nil -- not perLoadout in this test

-- ---- ns / Helpers -------------------------------------------------------
local function DeepCopy(v)
    if type(v) ~= "table" then return v end
    local t = {}
    for k, vv in pairs(v) do t[k] = DeepCopy(vv) end
    return t
end

local ns = {
    Helpers = {
        CreateStateTable = function()
            local tbl = setmetatable({}, { __mode = "k" })
            local function get(key)
                local s = tbl[key]; if not s then s = {}; tbl[key] = s end; return s
            end
            return tbl, get
        end,
        DeepCopy = DeepCopy,
        GetCurrentSpecID = function() return 102 end,
    },
}

-- ---- DB ----------------------------------------------------------------
_G.QUI = {
    db = {
        char = {
            clickCast = {
                enabled = true,
                _migratedFromProfile = true, -- skip migration
                rootSpellMigrationDone = true,
                bindings = {
                    { button = "LeftButton", modifiers = "", actionType = "spell",
                      spell = "Rejuvenation", spellID = 774 },
                },
            },
        },
        profile = {},
    },
}

-- ---- group frame headers mock ------------------------------------------
local child = NewFrame("Button", "QUI_TestUnit1", nil, "SecureUnitButtonTemplate")
local partyHeader = NewFrame("Frame", "QUI_TestPartyHeader", nil, "SecureGroupHeaderTemplate")
partyHeader.attributes["child1"] = child
ns.QUI_GroupFrames = {
    headers = { party = partyHeader, raid = false, self = false },
    raidGroupHeaders = {},
}

-- ---- load module --------------------------------------------------------
assert(loadfile("QUI_GroupFrames/groupframes/groupframes_clickcast.lua"))("QUI", ns)
local GFCC = assert(ns.QUI_GroupFrameClickCast, "module should export QUI_GroupFrameClickCast")

-- ---- 1. initial apply ---------------------------------------------------
GFCC:Initialize()
assert(GFCC:IsEnabled(), "click-cast should be enabled after Initialize")
GFCC:RegisterAllFrames()

-- In the proxy routing model, cast attrs live on the per-frame proxy, not the
-- frame itself. The frame has type1="click" + clickbutton1=proxy.
local proxyName = child:GetAttribute("clickcast-proxyname")
assert(proxyName, "registered frame must have clickcast-proxyname")
local proxy = assert(_G[proxyName], "proxy must be in _G")

assert(proxy.attributes["type1"] == "macro",
    "after initial register, proxy left-click should be a macro action")
assert(proxy.attributes["macrotext1"]:find("Rejuvenation", 1, true),
    "after initial register, proxy left-click macro should cast Rejuvenation, got: "
    .. tostring(proxy.attributes["macrotext1"]))

-- ---- 2. change the binding out of combat via the real UI path -----------
-- The options UI changes "which click casts what" by removing the old binding
-- and adding the new one. Both call RefreshBindings() internally out of combat.
inCombat = false
assert(GFCC:RemoveBinding(1))
assert(GFCC:AddBinding({ button = "LeftButton", modifiers = "", actionType = "spell",
    spell = "Regrowth", spellID = 8936 }))

-- Re-fetch proxy after RefreshBindings (same frame, same proxy name).
proxyName = child:GetAttribute("clickcast-proxyname")
proxy = assert(_G[proxyName], "proxy must still be in _G after rebind")

-- ---- 3. assert the live proxy reflects the NEW binding ------------------
assert(proxy.attributes["type1"] == "macro",
    "after binding change, proxy left-click should still be a macro action")
assert(proxy.attributes["macrotext1"]:find("Regrowth", 1, true),
    "BUG: after changing the binding out of combat, proxy left-click macro should cast "
    .. "Regrowth without a /reload. Got: " .. tostring(proxy.attributes["macrotext1"]))
assert(not proxy.attributes["macrotext1"]:find("Rejuvenation", 1, true),
    "BUG: stale Rejuvenation macro should be gone from proxy after the binding change")

assert(GFCC:RemoveBinding(1))
assert(GFCC:AddBinding({ button = "LeftButton", modifiers = "", actionType = "item",
    item = "Emergency Soul Link", itemID = 123456 }))
assert(GFCC:AddBinding({ key = "F", modifiers = "", actionType = "item",
    item = "Emergency Soul Link", itemID = 123456 }))
assert(GFCC:AddBinding({ button = "ScrollUp", modifiers = "", actionType = "item",
    item = "Emergency Soul Link", itemID = 123456 }))

proxyName = child:GetAttribute("clickcast-proxyname")
proxy = assert(_G[proxyName], "proxy must still be in _G after item bindings")
assert(proxy.attributes["type1"] == "item" and proxy.attributes["item1"] == "item:123456",
    "mouse item bindings must publish native secure item attributes")
assert(proxy.attributes["type-keyf"] == "item" and proxy.attributes["item-keyf"] == "item:123456",
    "keyboard item bindings must publish native secure item attributes")
assert(proxy.attributes["type-keymousewheelup"] == "item"
    and proxy.attributes["item-keymousewheelup"] == "item:123456",
    "scroll item bindings must publish native secure item attributes")

assert(GFCC:RemoveBinding(3))
assert(GFCC:RemoveBinding(2))
assert(GFCC:RemoveBinding(1))
assert(GFCC:AddBinding({ button = "LeftButton", modifiers = "", actionType = "spell",
    spell = "Regrowth", spellID = 8936 }))
proxyName = child:GetAttribute("clickcast-proxyname")
proxy = assert(_G[proxyName], "proxy must still be in _G after replacing item bindings")
assert(proxy.attributes["type1"] == "macro" and proxy.attributes["item1"] == nil,
    "replacing an item with a spell must clear the stale mouse item attribute")
assert(proxy.attributes["type-keyf"] == nil and proxy.attributes["item-keyf"] == nil,
    "removing a keyboard item binding must clear its secure item attributes")
assert(proxy.attributes["type-keymousewheelup"] == nil
    and proxy.attributes["item-keymousewheelup"] == nil,
    "removing a scroll item binding must clear its secure item attributes")

-- ---- 4. copy between shared, spec, and loadout binding sets --------------
local cc = _G.QUI.db.char.clickCast
local loadoutBinding = {
    button = "RightButton",
    modifiers = "shift",
    actionType = "macro",
    spell = "Macro",
    macro = "/say loadout",
    metadata = { source = "loadout" },
}
local otherSpecBinding = {
    key = "F",
    modifiers = "",
    actionType = "spell",
    spell = "Regrowth",
    spellID = 8936,
}

cc.specBindings = {
    [102] = {
        { button = "MiddleButton", actionType = "target", spell = "target" },
    },
    [103] = { otherSpecBinding },
    [104] = {},
}
cc.loadoutBindings = {
    [102] = {
        [9001] = { loadoutBinding },
        [9002] = {
            { button = "Button4", actionType = "focus", spell = "focus" },
        },
        [9003] = {},
    },
}
cc.perSpec = true
cc.perLoadout = false

assert(GFCC:GetEditableBindingSetID() == "spec:102",
    "per-spec mode should edit the current spec bucket")

local sources = GFCC:GetBindingSetSources()
local sourceByID = {}
for _, source in ipairs(sources) do sourceByID[source.id] = source end

assert(#sources == 5, "only non-empty binding sets should be offered as copy sources")
assert(sourceByID.shared and sourceByID.shared.count == 1, "shared bindings should be listed")
assert(sourceByID["spec:102"] and sourceByID["spec:102"].isActive,
    "the current spec source should be marked active")
assert(sourceByID["spec:103"], "another spec should be listed")
assert(sourceByID["loadout:102:9001"], "a saved loadout should be listed")
assert(sourceByID["loadout:102:9002"], "the active loadout bucket should be listed")
assert(not sourceByID["spec:104"], "empty spec buckets should not be listed")
assert(not sourceByID["loadout:102:9003"], "empty loadout buckets should not be listed")

local ok, count = GFCC:CopyBindingsFrom("loadout:102:9001")
assert(ok and count == 1, "copying a loadout into the current spec should succeed")
assert(cc.specBindings[102][1].macro == "/say loadout",
    "the copied binding should replace the active spec set")
assert(cc.specBindings[102][1] ~= loadoutBinding,
    "the destination binding should not alias the source binding")
assert(cc.specBindings[102][1].metadata ~= loadoutBinding.metadata,
    "nested binding data should also be copied")
cc.specBindings[102][1].metadata.source = "changed"
assert(loadoutBinding.metadata.source == "loadout", "editing the copy should not change its source")

cc.perSpec = false
assert(GFCC:GetEditableBindingSetID() == "shared",
    "turning off per-spec mode should target shared bindings")
assert(GFCC:CopyBindingsFrom("spec:103"), "copying another spec into shared bindings should succeed")
assert(cc.bindings[1].spellID == 8936, "shared bindings should receive the other spec")
assert(cc.bindings[1] ~= otherSpecBinding, "the shared binding should be independent")

C_ClassTalents = {
    GetLastSelectedSavedConfigID = function() return 9002 end,
    GetActiveConfigID = function() return 9002 end,
}
cc.perSpec = true
cc.perLoadout = true
assert(GFCC:GetEditableBindingSetID() == "loadout:102:9002",
    "per-loadout mode should target the active loadout")
assert(GFCC:CopyBindingsFrom("spec:103"), "copying a spec into a loadout should succeed")
assert(cc.loadoutBindings[102][9002][1].spellID == 8936,
    "the active loadout should receive the copied spec binding")

local before = cc.loadoutBindings[102][9002][1]
assert(not GFCC:CopyBindingsFrom("loadout:102:9002"),
    "copying the active binding set onto itself should be rejected")
assert(cc.loadoutBindings[102][9002][1] == before,
    "a rejected self-copy should leave the active set untouched")
assert(not GFCC:CopyBindingsFrom("loadout:102:9999"),
    "an unknown source should be rejected")

print("OK: groupframes_clickcast_dynamic_apply_test")
