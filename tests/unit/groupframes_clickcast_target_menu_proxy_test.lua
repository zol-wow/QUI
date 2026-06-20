-- tests/unit/groupframes_clickcast_target_menu_proxy_test.lua
-- Run: lua tests/unit/groupframes_clickcast_target_menu_proxy_test.lua
--
-- WoW 12.0.7's SecureUnitButton_OnClick gates the native "target" and
-- "togglemenu" actions behind C_ClickBindings -- only Blizzard's default
-- unmodified left->target and right->menu interactions are registered, so a
-- MODIFIED (or non-default-button) click resolving to either type returns
-- ClickBindingType.None and is silently dropped. The fix routes those bindings
-- through a hidden child SecureActionButton via the ungated "click" action.
--
-- This test asserts:
--   * plain unmodified left->target stays a NATIVE type="target"
--   * plain unmodified right->menu stays a NATIVE type="togglemenu"
--   * alt+left->target becomes type="click" + clickbutton=<proxy>
--   * ctrl+right->menu becomes type="click" + clickbutton=<proxy>
--   * the proxy is a SecureActionButton with useparent-unit + per-button type

local inCombat = false
local function noop() end

-- ---- frame mock ---------------------------------------------------------
local frameMT
local function NewFrame(frameType, name, parent, template)
    local frame = {
        frameType = frameType, name = name, parent = parent, template = template,
        attributes = {}, scripts = {}, hooks = {}, events = {},
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
            elseif key == "SetScript" then
                return function(self, s, h) self.scripts[s] = h end
            elseif key == "HookScript" then
                return function(self, s, h) self.hooks[s] = self.hooks[s] or {}; table.insert(self.hooks[s], h) end
            elseif key == "RegisterEvent" then
                return function(self, e) self.events[e] = true end
            elseif key == "CreateTexture" or key == "CreateFontString" then
                return function(self) return NewFrame(key, nil, self, nil) end
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
function GetSpecializationInfo() return 102 end
SecureHandlerWrapScript = noop
RegisterStateDriver = noop
UnregisterStateDriver = noop
GameTooltip = { GetOwner = function() return nil end, AddLine = noop, AddDoubleLine = noop, Show = noop }
_G.wipe = function(t) for k in pairs(t) do t[k] = nil end return t end

C_Timer = { After = function() end, NewTimer = function() return { Cancel = noop } end }

C_Spell = {
    GetSpellName = function() return nil end,
    GetSpellIDForSpellIdentifier = function() return nil end,
    GetBaseSpell = function(id) return id end,
}
C_ClassTalents = nil

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
            return tbl
        end,
        DeepCopy = DeepCopy,
    },
}

-- ---- DB: target + menu bindings, plain and modified --------------------
_G.QUI = {
    db = {
        char = {
            clickCast = {
                enabled = true,
                _migratedFromProfile = true,
                rootSpellMigrationDone = true,
                bindings = {
                    { button = "LeftButton",  modifiers = "",     actionType = "target" },
                    { button = "LeftButton",  modifiers = "alt",  actionType = "target" },
                    { button = "RightButton", modifiers = "",     actionType = "menu"   },
                    { button = "RightButton", modifiers = "ctrl", actionType = "menu"   },
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

-- ---- load + apply -------------------------------------------------------
assert(loadfile("QUI_GroupFrames/groupframes/groupframes_clickcast.lua"))("QUI", ns)
local GFCC = assert(ns.QUI_GroupFrameClickCast, "module should export QUI_GroupFrameClickCast")
GFCC:Initialize()
assert(GFCC:IsEnabled(), "click-cast should be enabled after Initialize")
GFCC:RegisterAllFrames()

local a = child.attributes

-- ---- 1. plain unmodified left->target stays NATIVE ---------------------
assert(a["type1"] == "target",
    "plain left->target must stay native type=target (Blizzard default interaction), got: "
    .. tostring(a["type1"]))
assert(a["clickbutton1"] == nil,
    "plain left->target must NOT use a click proxy")

-- ---- 2. plain unmodified right->menu stays NATIVE ----------------------
assert(a["type2"] == "togglemenu",
    "plain right->menu must stay native type=togglemenu, got: " .. tostring(a["type2"]))
assert(a["clickbutton2"] == nil,
    "plain right->menu must NOT use a click proxy")

-- ---- 3. alt+left->target routes through the proxy ----------------------
assert(a["alt-type1"] == "click",
    "BUG: alt+left->target must route through the ungated click proxy (was the "
    .. "12.0.7 gate dropping modified target), got type: " .. tostring(a["alt-type1"]))
local tProxy = a["alt-clickbutton1"]
assert(type(tProxy) == "table" and tProxy.template == "SecureActionButtonTemplate",
    "alt+left->target clickbutton must be a SecureActionButton proxy frame")
assert(tProxy.attributes["type1"] == "target" and tProxy.attributes["type"] == "target",
    "target proxy must carry type=target on the bare + numbered buttons")
assert(tProxy.attributes["useparent-unit"] == true,
    "target proxy must resolve its unit from the parent unit button")
assert(tProxy.attributes["useOnKeyDown"] == false,
    "target proxy must act on the up-click regardless of the cast-on-keydown CVar")

-- ---- 4. ctrl+right->menu routes through the proxy ----------------------
assert(a["ctrl-type2"] == "click",
    "BUG: ctrl+right->menu must route through the click proxy, got type: "
    .. tostring(a["ctrl-type2"]))
local mProxy = a["ctrl-clickbutton2"]
assert(type(mProxy) == "table" and mProxy.template == "SecureActionButtonTemplate",
    "ctrl+right->menu clickbutton must be a SecureActionButton proxy frame")
assert(mProxy.attributes["type2"] == "togglemenu",
    "menu proxy must carry type=togglemenu on the numbered button")

-- ---- 5. target and menu proxies are distinct ---------------------------
assert(tProxy ~= mProxy, "target and menu proxies must be separate buttons")

-- ---- 6. clearing the frame drops the proxy routing ---------------------
inCombat = false
GFCC:RefreshBindings()
-- After a refresh with the same bindings, the routing is re-applied (idempotent).
assert(child.attributes["alt-type1"] == "click",
    "after RefreshBindings, modified target routing should persist")

print("OK: groupframes_clickcast_target_menu_proxy_test")
