local function fail(msg)
    print("FAIL: pixel_reference_override_test - " .. msg)
    os.exit(1)
end

local function noop() end

GetPhysicalScreenSize = function() return 2560, 1440 end
GetScreenWidth = function() return 1920 end
GetScreenHeight = function() return 1080 end
InCombatLockdown = function() return false end
issecretvalue = nil
Round = function(x) return math.floor(x + 0.5) end
wipe = function(t) for k in pairs(t) do t[k] = nil end return t end
C_Timer = { After = function() end, NewTicker = function() return { Cancel = noop } end }

local function NewFrame(scale)
    local f = { _scale = scale or 1 }
    f.GetEffectiveScale = function(self) return self._scale end
    f.SetSize = function(self, w, h) self._w, self._h = w, h end
    f.SetWidth = function(self, w) self._w = w end
    f.SetHeight = function(self, h) self._h = h end
    return f
end

UIParent = NewFrame(1)

local ns = {
    Helpers = {
        CreateStateTable = function() return setmetatable({}, { __mode = "k" }) end,
    },
    Addon = {},
}
local QUI = { QUICore = ns.Addon }
_G.QUI = QUI

assert(loadfile("core/scaling.lua"))("QUI", ns)
local core = ns.Addon

if type(core.PushPixelReference) ~= "function" or type(core.PopPixelReference) ~= "function" then
    fail("scaling.lua must expose PushPixelReference/PopPixelReference")
end

local zoomed = NewFrame(3)

local livePx = core:GetPixelSize(nil)
local zoomedPx = core:GetPixelSize(zoomed)
if math.abs(zoomedPx - livePx / 3) > 1e-9 then
    fail("baseline: a 3x frame must resolve to a third of the reference pixel size")
end

core:PushPixelReference(nil)
if math.abs(core:GetPixelSize(zoomed) - livePx) > 1e-9 then
    fail("an override must make a scaled frame resolve against the reference")
end

core:SetPixelPerfectSize(zoomed, 210, 24)
local wOverridden, hOverridden = zoomed._w, zoomed._h

core:PopPixelReference()
if math.abs(core:GetPixelSize(zoomed) - livePx / 3) > 1e-9 then
    fail("pop must restore per-frame resolution")
end

core:SetPixelPerfectSize(zoomed, 210, 24)
if math.abs(wOverridden - zoomed._w * 3) > 1e-6 then
    fail("overridden sizing must be 3x the self-referenced sizing, got "
        .. tostring(wOverridden) .. " vs " .. tostring(zoomed._w))
end
if math.abs(hOverridden - zoomed._h * 3) > 1e-6 then
    fail("overridden height must be 3x the self-referenced height")
end

core:PushPixelReference(nil)
core:PushPixelReference(nil)
core:PopPixelReference()
if math.abs(core:GetPixelSize(zoomed) - livePx) > 1e-9 then
    fail("a nested pop must not clear the override early")
end
core:PopPixelReference()
if math.abs(core:GetPixelSize(zoomed) - livePx / 3) > 1e-9 then
    fail("the outermost pop must clear the override")
end

local driver = (function()
    local fh = assert(io.open("QUI_Nameplates/nameplates/settings/nameplates_preview_driver.lua", "rb"))
    local text = fh:read("*a")
    fh:close()
    return text
end)()

if not driver:find("core:PushPixelReference(nil)", 1, true)
    or not driver:find("core:PopPixelReference()", 1, true) then
    fail("the nameplate preview must lay its mock out against the live reference")
end

print("OK: pixel_reference_override_test")
