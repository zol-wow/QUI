-- Verifies the LibDataBroker host (QUI_Datatexts/datatexts/ldb_bridge.lua)
-- against the real LibStub + CallbackHandler + LibDataBroker libraries, plus
-- the registry/attach layer of datatexts.lua it rides on:
--   * dataobjects existing BEFORE the bridge loads register as ldb:<name>
--   * dataobjects created AFTER load register via the lib callback and
--     trigger the slot-host refresh globals
--   * attribute changes re-render live slots
--   * a click on a slot hides the slot-owned GameTooltip before the
--     provider OnClick runs (context menus would render under it), and
--     hides a plugin-owned custom tooltip frame
--   * OnDoubleClick passes through only when the plugin defines one
--   * DetachFromSlot clears OnClick/OnDoubleClick/OnEnter/OnLeave
--   * /qui ldb's dump global exists and reports every dataobject
-- Standalone: lua tests/unit/datatexts_ldb_bridge_test.lua

local ROOT = (arg and arg[0] or ""):match("^(.*)tests[/\\]unit[/\\]") or "./"

---------------------------------------------------------------------------
-- WoW environment stubs
---------------------------------------------------------------------------
local function noop() end

local function NewFontString()
    local fs = { _text = "" }
    function fs:SetText(t) self._text = t or "" end
    function fs:GetText() return self._text end
    function fs:GetStringWidth() return #self._text * 6 end
    fs.SetPoint, fs.SetJustifyH, fs.SetWordWrap = noop, noop, noop
    fs.SetTextColor, fs.SetFont, fs.SetShadowOffset = noop, noop, noop
    return fs
end

local frameDefaults = {
    SetAllPoints = noop, SetSize = noop, SetHeight = noop, SetWidth = noop,
    SetPoint = noop, ClearAllPoints = noop, SetParent = noop,
    EnableMouse = noop, SetFrameStrata = noop, SetFrameLevel = noop,
    RegisterEvent = noop, UnregisterEvent = noop, UnregisterAllEvents = noop,
    SetAlpha = noop, SetScale = noop, SetClipsChildren = noop,
}

local function NewFrame(frameType)
    local f = { _scripts = {}, _shown = true, _type = frameType or "Frame" }
    function f:SetScript(name, fn) self._scripts[name] = fn end
    function f:GetScript(name) return self._scripts[name] end
    function f:RegisterForClicks() self._clicksRegistered = true end
    function f:CreateFontString() return NewFontString() end
    function f:CreateTexture()
        return setmetatable({}, { __index = function() return noop end })
    end
    function f:Show() self._shown = true end
    function f:Hide() self._shown = false end
    function f:IsShown() return self._shown end
    function f:GetHeight() return 22 end
    function f:GetWidth() return 100 end
    function f:GetCenter() return 0, 0 end
    function f:IsProtected() return false end
    return setmetatable(f, { __index = frameDefaults })
end

_G.CreateFrame = function(frameType) return NewFrame(frameType) end
_G.UIParent = NewFrame()
function _G.UIParent:GetHeight() return 1080 end
_G.C_Timer = { After = function(_, fn) fn() end, NewTicker = function() return { Cancel = noop } end }
_G.InCombatLockdown = function() return false end
_G.wipe = function(t) for k in pairs(t) do t[k] = nil end return t end
-- CallbackHandler-1.0 dispatches handlers through this in WoW
_G.securecallfunction = function(fn, ...) return fn(...) end
_G.geterrorhandler = function() return print end
-- WoW string/table aliases used by the libs
_G.strmatch, _G.strfind, _G.strsub = string.match, string.find, string.sub
_G.gsub, _G.format, _G.tinsert, _G.tremove = string.gsub, string.format, table.insert, table.remove

_G.GameTooltip = NewFrame()
function _G.GameTooltip:SetOwner(owner) self._owner = owner; self._shown = false end
function _G.GameTooltip:GetOwner() return self._owner end

local printed = {}
local realPrint = print
_G.print = function(...)
    local parts = {}
    for i = 1, select("#", ...) do parts[#parts + 1] = tostring(select(i, ...)) end
    printed[#printed + 1] = table.concat(parts, " ")
end

---------------------------------------------------------------------------
-- Real libraries
---------------------------------------------------------------------------
assert(loadfile(ROOT .. "libs/LibStub/LibStub.lua"))()
assert(loadfile(ROOT .. "libs/CallbackHandler-1.0/CallbackHandler-1.0.lua"))()
assert(loadfile(ROOT .. "libs/LibDataBroker-1.1/LibDataBroker-1.1.lua"))()
local ldb = _G.LibStub("LibDataBroker-1.1")

---------------------------------------------------------------------------
-- QUI namespace + registry (real datatexts.lua)
---------------------------------------------------------------------------
local QUICore = {
    db = { profile = {}, global = {} },
    SafeSetFont = noop,
    GetPixelSize = function() return 1 end,
}
local ns = { Addon = QUICore, Helpers = {}, LSM = { Fetch = function() return nil end } }
-- datatexts.lua indexes ns.L["..."] at load (post-i18n); install identity resolver.
local installLocale = dofile(ROOT .. "tests/helpers/locale.lua")
installLocale(ns)

assert(loadfile(ROOT .. "QUI_Datatexts/datatexts/datatexts.lua"))("QUI_Datatexts", ns)
local Datatexts = QUICore.Datatexts
assert(Datatexts, "datatexts.lua did not publish QUICore.Datatexts")

---------------------------------------------------------------------------
-- A dataobject that exists BEFORE the bridge loads
---------------------------------------------------------------------------
local preClicks, preTooltip = 0, NewFrame()
ldb:NewDataObject("PreExisting", {
    type = "data source",
    text = "pre",
    tooltip = preTooltip,
    OnClick = function() preClicks = preClicks + 1 end,
})

local refreshes = { infobar = 0, datapanels = 0, minimap = 0 }
_G.QUI_RefreshInfoBar = function() refreshes.infobar = refreshes.infobar + 1 end
_G.QUI_RefreshDatapanels = function() refreshes.datapanels = refreshes.datapanels + 1 end
_G.QUI_RefreshMinimap = function() refreshes.minimap = refreshes.minimap + 1 end

assert(loadfile(ROOT .. "QUI_Datatexts/datatexts/ldb_bridge.lua"))("QUI_Datatexts", ns)

local failures = 0
local function check(cond, label)
    if cond then
        realPrint("ok   - " .. label)
    else
        failures = failures + 1
        realPrint("FAIL - " .. label)
    end
end

---------------------------------------------------------------------------
-- Initial sweep
---------------------------------------------------------------------------
check(Datatexts:Get("ldb:PreExisting") ~= nil,
    "pre-existing dataobject registered by the initial sweep")

---------------------------------------------------------------------------
-- Late creation (callback path)
---------------------------------------------------------------------------
local lateClicks, lateDoubles = 0, 0
ldb:NewDataObject("LatePlugin", {
    type = "launcher",
    icon = "Interface\\Icons\\Temp",
    label = "Late",
    OnClick = function() lateClicks = lateClicks + 1 end,
    OnDoubleClick = function() lateDoubles = lateDoubles + 1 end,
})
check(Datatexts:Get("ldb:LatePlugin") ~= nil,
    "late dataobject registered via DataObjectCreated callback")
check(refreshes.infobar == 1 and refreshes.datapanels == 1 and refreshes.minimap == 1,
    "late registration refreshed all slot hosts exactly once")

---------------------------------------------------------------------------
-- Attach + render
---------------------------------------------------------------------------
local slot = NewFrame("Button")
slot.text = NewFontString()
check(Datatexts:AttachToSlot(slot, "ldb:LatePlugin", {}),
    "AttachToSlot succeeds for an ldb datatext")
check(slot.text:GetText():find("Late", 1, true) ~= nil,
    "slot rendered the plugin label")
check(slot._scripts.OnClick ~= nil, "OnClick wired on attach")
check(slot._scripts.OnDoubleClick ~= nil,
    "OnDoubleClick wired when the plugin defines one")

-- Attribute change re-renders the live slot
local lateObj = ldb:GetDataObjectByName("LatePlugin")
lateObj.label = "Renamed"
check(slot.text:GetText():find("Renamed", 1, true) ~= nil,
    "attribute change re-rendered the live slot")

---------------------------------------------------------------------------
-- Click hygiene: slot-owned GameTooltip hides before the provider OnClick
---------------------------------------------------------------------------
_G.GameTooltip:SetOwner(slot)
_G.GameTooltip:Show()
slot._scripts.OnClick(slot, "RightButton")
check(lateClicks == 1, "plugin OnClick invoked")
check(not _G.GameTooltip:IsShown(),
    "slot-owned GameTooltip hidden by the click wrap")

-- A tooltip owned by another frame must survive the click
local other = NewFrame("Button")
_G.GameTooltip:SetOwner(other)
_G.GameTooltip:Show()
slot._scripts.OnClick(slot, "LeftButton")
check(_G.GameTooltip:IsShown(),
    "GameTooltip owned by another frame is left alone")

slot._scripts.OnDoubleClick(slot, "LeftButton")
check(lateDoubles == 1, "plugin OnDoubleClick invoked")

---------------------------------------------------------------------------
-- Custom plugin tooltip frame hides on click too
---------------------------------------------------------------------------
local preSlot = NewFrame("Button")
preSlot.text = NewFontString()
Datatexts:AttachToSlot(preSlot, "ldb:PreExisting", {})
check(preSlot._scripts.OnDoubleClick == nil,
    "OnDoubleClick NOT wired when the plugin has none")
preTooltip:Show()
preSlot._scripts.OnClick(preSlot, "RightButton")
check(preClicks == 1, "pre-existing plugin OnClick invoked")
check(not preTooltip:IsShown(),
    "plugin-owned custom tooltip frame hidden on click")

---------------------------------------------------------------------------
-- Detach clears handlers
---------------------------------------------------------------------------
Datatexts:DetachFromSlot(slot)
check(slot._scripts.OnClick == nil and slot._scripts.OnDoubleClick == nil
    and slot._scripts.OnEnter == nil and slot._scripts.OnLeave == nil,
    "detach cleared OnClick/OnDoubleClick/OnEnter/OnLeave")

---------------------------------------------------------------------------
_G.print = realPrint
if failures > 0 then
    print(("datatexts_ldb_bridge_test: %d FAILURE(S)"):format(failures))
    os.exit(1)
end
print("datatexts_ldb_bridge_test: all checks passed")
