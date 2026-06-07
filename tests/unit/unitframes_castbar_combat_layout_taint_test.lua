-- tests/unit/unitframes_castbar_combat_layout_taint_test.lua
-- Run: lua tests/unit/unitframes_castbar_combat_layout_taint_test.lua
--
-- Regression guard for the "AddOn 'QUI' tried to call the protected function
-- 'Frame:SetHeight()'" taint error.
--
-- Root cause: a target/focus-change event can fire synchronously inside a secure
-- execution context. Pressing a key bound to TargetNearestEnemy (a protected
-- action, only restricted in combat) changes the target, dispatching
-- PLAYER_TARGET_CHANGED synchronously while the secure call is still on the stack.
-- The castbar's OnEvent handler ran Cast() there, and Cast() makes protected calls
-- (anchorFrame:SetHeight(), icon:Show()/Hide(), channel-tick SetPoint/Hide, ...),
-- each of which is ADDON_ACTION_BLOCKED in that context.
--
-- Fix: in combat the target/focus-change handlers defer Cast() by one frame
-- (C_Timer.After(0)), moving it out of the secure execution context into a normal,
-- unrestricted frame. Out of combat there is no restriction, so Cast() runs
-- synchronously for an instant update.
--
-- This test drives the real OnEvent handler and proves: in combat the protected
-- geometry does NOT run synchronously (it is deferred), and the deferred callback
-- applies it; out of combat it runs synchronously with no defer.
-- luacheck: globals GetTime CreateFrame InCombatLockdown UnitCastingInfo UnitChannelInfo UnitClass UnitGUID UIParent RAID_CLASS_COLORS C_Timer EventRegistry

local function noop() end

local function newRegion(frameType, parent)
    local region = {
        frameType = frameType or "Frame",
        parent = parent,
        width = 0,
        height = 0,
        shown = true,
        alpha = 1,
        frameLevel = 1,
        frameStrata = "MEDIUM",
        points = {},
    }

    function region:SetSize(width, height) self.width = width; self.height = height end
    function region:SetWidth(width) self.width = width end
    function region:SetHeight(height) self.height = height end
    function region:GetWidth() return self.width end
    function region:GetHeight() return self.height end
    function region:SetPoint(...) self.points[#self.points + 1] = {...} end
    function region:ClearAllPoints() self.points = {} end
    function region:SetAllPoints(anchor) self.allPoints = anchor or self.parent or true end
    function region:Show() self.shown = true end
    function region:Hide() self.shown = false end
    function region:IsShown() return self.shown end
    function region:IsVisible() return self.shown and self.alpha ~= 0 end
    function region:SetAlpha(alpha) self.alpha = alpha end
    function region:GetAlpha() return self.alpha end
    function region:SetFrameStrata(strata) self.frameStrata = strata end
    function region:GetFrameStrata() return self.frameStrata end
    function region:SetFrameLevel(level) self.frameLevel = level end
    function region:GetFrameLevel() return self.frameLevel end
    function region:GetParent() return self.parent end
    function region:CreateTexture() return newRegion("Texture", self) end

    function region:CreateFontString()
        local fs = newRegion("FontString", self)
        fs.fontPath = "Fonts\\FRIZQT__.TTF"
        fs.fontSize = 12
        fs.fontFlags = ""
        function fs:SetFont(path, size, flags) self.fontPath = path; self.fontSize = size; self.fontFlags = flags end
        function fs:GetFont() return self.fontPath, self.fontSize, self.fontFlags end
        function fs:SetText(text) self.text = text end
        function fs:SetFormattedText(format, value) self.text = string.format(format, value) end
        function fs:GetStringWidth() return #(self.text or "") * 6 end
        function fs:SetTextColor(r, g, b, a) self.textColor = {r, g, b, a} end
        function fs:SetWordWrap(value) self.wordWrap = value end
        function fs:SetJustifyH(value) self.justifyH = value end
        function fs:SetJustifyV(value) self.justifyV = value end
        return fs
    end

    function region:SetScript(scriptName, handler) self.scripts = self.scripts or {}; self.scripts[scriptName] = handler end
    function region:RegisterUnitEvent(event, ...) self.unitEvents = self.unitEvents or {}; self.unitEvents[event] = {...} end
    function region:RegisterEvent(event) self.events = self.events or {}; self.events[event] = true end
    function region:UnregisterAllEvents() self.unitEvents = {}; self.events = {} end
    function region:SetMovable(value) self.movable = value end
    function region:EnableMouse(value) self.mouseEnabled = value end
    function region:RegisterForDrag(...) self.dragButtons = {...} end
    function region:SetClampedToScreen(value) self.clampedToScreen = value end
    function region:GetCenter() return 0, 0 end
    function region:SetMinMaxValues(minValue, maxValue) self.minValue = minValue; self.maxValue = maxValue end
    function region:SetValue(value) self.value = value end
    function region:SetStatusBarColor(r, g, b, a) self.statusBarColor = {r, g, b, a} end
    function region:SetStatusBarTexture(texture) self.statusBarTexture = texture end
    function region:GetStatusBarTexture()
        if not self.statusBarTextureRegion then
            self.statusBarTextureRegion = newRegion("Texture", self)
        end
        return self.statusBarTextureRegion
    end
    function region:SetReverseFill(value) self.reverseFill = value end
    function region:SetTexture(texture) self.texture = texture end
    function region:GetTexture() return self.texture end
    function region:SetColorTexture(r, g, b, a) self.colorTexture = {r, g, b, a} end
    function region:SetVertexColor(r, g, b, a) self.vertexColor = {r, g, b, a} end
    function region:SetTexCoord(...) self.texCoord = {...} end
    function region:SetSnapToPixelGrid(value) self.snapToPixelGrid = value end
    function region:SetTexelSnappingBias(value) self.texelSnappingBias = value end

    return region
end

local now = 100

-- Mutable combat state and a *queuing* timer: C_Timer.After records callbacks so
-- the test can assert work was deferred (not run) and then fire it on demand.
local inCombat = false
local timerQueue = {}
local function flushTimers()
    local pending = timerQueue
    timerQueue = {}
    for _, cb in ipairs(pending) do cb() end
end

function GetTime() return now end
function CreateFrame(frameType, name, parent)
    local frame = newRegion(frameType, parent)
    frame.name = name
    return frame
end
function InCombatLockdown() return inCombat end
function UnitCastingInfo(unit)
    -- The target castbar watches "target"; report an active (non-channeled) cast
    -- so Cast() enters the real-cast branch that applies the protected geometry.
    if unit == "target" or unit == "player" then
        return "Frostbolt", "Frostbolt", 135846, (now - 0.2) * 1000, (now + 2.8) * 1000, false, "CastGUID", false, 116, nil, 0
    end
    return nil
end
function UnitChannelInfo() return nil end
function UnitClass() return "Target", "MAGE" end
function UnitGUID() return "Creature-0000-00000001" end

UIParent = newRegion("Frame")
RAID_CLASS_COLORS = { MAGE = { r = 0.25, g = 0.78, b = 0.92 } }
C_Timer = { After = function(_, callback) timerQueue[#timerQueue + 1] = callback end }
EventRegistry = { RegisterCallback = noop }

local ns = { Helpers = {}, Addon = {} }
local pixelScale = 1
ns.Helpers.IsSecretValue = function() return false end
ns.Helpers.SafeValue = function(value) return value end
ns.Helpers.EnsureDefaults = function(tbl, defaults)
    for key, value in pairs(defaults) do
        if tbl[key] == nil then tbl[key] = value end
    end
end
ns.Helpers.GetGeneralFont = function() return "Fonts\\FRIZQT__.TTF" end
ns.Helpers.GetGeneralFontOutline = function() return "" end
ns.Helpers.GetCore = function() return ns.Addon end
ns.Helpers.Clamp = function(value, minValue, maxValue)
    if value < minValue then return minValue end
    if value > maxValue then return maxValue end
    return value
end
ns.Helpers.CreateStateTable = function() return setmetatable({}, { __mode = "k" }) end
ns.Helpers.CHROME = { BORDER_PX = 1, BG_FALLBACK = { 0.05, 0.05, 0.05, 0.95 }, BORDER_FALLBACK = { 0, 0, 0, 1 }, BUTTON_BOOST = 0.07, SCROLLROW_BOOST = 0.03, DEPTH = { PANEL = { boost = 0, alpha = 0.95 }, SUBPANEL = { boost = 0.04, alpha = 0.85 }, ROW = { boost = 0.07, alpha = 0.75 } } }

function ns.Addon:PixelRound(value) return math.floor((value / pixelScale) + 0.5) * pixelScale end
function ns.Addon:Pixels(value) return value * pixelScale end
function ns.Addon:GetPixelSize() return pixelScale end
function ns.Addon:SetPixelPerfectSize(frame, width, height) frame:SetSize(math.floor(width + 0.5) * pixelScale, math.floor(height + 0.5) * pixelScale) end
function ns.Addon:SetPixelPerfectHeight(frame, height) frame:SetHeight(math.floor(height + 0.5) * pixelScale) end
function ns.Addon:SetPixelPerfectPoint(frame, point, relativeTo, relativePoint, x, y) frame:SetPoint(point, relativeTo, relativePoint, x, y) end
function ns.Addon:ApplyPixelSnapping() end
function ns.Addon:ApplyFont(fontString, _, size, path, outline) fontString:SetFont(path, size, outline) end

assert(loadfile("core/uikit.lua"))("QUI", ns)
assert(loadfile("QUI_UnitFrames/unitframes/castbar.lua"))("QUI", ns)

local settings = {
    target = {
        castbar = {
            enabled = true,
            showIcon = true,
            iconSize = 22,
            iconScale = 1,
            iconSpacing = 0,
            iconAnchor = "LEFT",
            iconBorderSize = 1,
            iconBorderColor = {0, 0, 0, 1},
            width = 220,
            height = 18,
            borderSize = 1,
            borderColor = {0, 0, 0, 1},
            color = {1, 0.7, 0, 1},
            bgColor = {0.149, 0.149, 0.149, 1},
            texture = "Flat",
            showSpellText = true,
            showTimeText = true,
        },
    },
}

ns.QUI_Castbar:SetHelpers({
    GetUnitSettings = function(unit) return settings[unit] end,
    GetGeneralSettings = function() return {} end,
    GetDB = function() return { general = {} } end,
    GetTexturePath = function() return "Interface\\Buttons\\WHITE8x8" end,
    GetUnitClassColor = function() return 1, 1, 1, 1 end,
    TruncateName = function(name) return name end,
})

local unitFrame = newRegion("Frame", UIParent)
unitFrame:SetSize(220, 40)

-- A target castbar registers PLAYER_TARGET_CHANGED -- the secure-execution vector.
local castbar = assert(ns.QUI_Castbar:CreateCastbar(unitFrame, "target", "target"))
local onEvent = assert(castbar.scripts and castbar.scripts.OnEvent,
    "castbar should wire an OnEvent handler")

-- Spy on the exact protected call the bug report blocked: anchorFrame:SetHeight().
local realSetHeight = castbar.SetHeight
local setHeightCalls = 0
castbar.SetHeight = function(self, height)
    setHeightCalls = setHeightCalls + 1
    return realSetHeight(self, height)
end

-- In combat, a target-change event must NOT run protected geometry synchronously
-- (it could be inside a secure execution context). It must defer Cast().
inCombat = true
setHeightCalls = 0
timerQueue = {}
onEvent(castbar, "PLAYER_TARGET_CHANGED")
assert(setHeightCalls == 0,
    "in combat, PLAYER_TARGET_CHANGED must not run anchorFrame:SetHeight() synchronously "
    .. "(got " .. setHeightCalls .. ") -- secure-execution taint vector")
assert(#timerQueue >= 1,
    "in combat, PLAYER_TARGET_CHANGED must defer Cast() to a later frame")

-- Firing the deferred callback (now outside the secure context) applies the layout.
flushTimers()
assert(setHeightCalls >= 1,
    "the deferred cast should apply the layout once outside the secure context "
    .. "(got " .. setHeightCalls .. ")")

-- A deferred callback whose castbar was destroyed before it fires must no-op.
inCombat = true
timerQueue = {}
onEvent(castbar, "PLAYER_TARGET_CHANGED")
assert(#timerQueue >= 1, "expected a deferred cast to be queued")
castbar._quiDestroyed = true
setHeightCalls = 0
flushTimers()
assert(setHeightCalls == 0,
    "a deferred cast for a destroyed castbar must not touch the orphaned frame")
castbar._quiDestroyed = nil

-- Out of combat there is no restriction: the cast runs synchronously, no defer.
inCombat = false
setHeightCalls = 0
timerQueue = {}
onEvent(castbar, "PLAYER_TARGET_CHANGED")
assert(setHeightCalls >= 1,
    "out of combat, PLAYER_TARGET_CHANGED should run the cast synchronously "
    .. "(got " .. setHeightCalls .. ")")

print("OK: unitframes_castbar_combat_layout_taint_test")
