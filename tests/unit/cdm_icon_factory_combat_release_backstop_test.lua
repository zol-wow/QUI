-- tests/unit/cdm_icon_factory_combat_release_backstop_test.lua
-- Run: lua tests/unit/cdm_icon_factory_combat_release_backstop_test.lua
--
-- Fail-closed backstop: a pooled icon that owns a SecureActionButton child
-- (clickButton) is visibility-protected. ReleaseIcon's Hide/ClearAllPoints/
-- SetParent would raise ADDON_ACTION_BLOCKED in combat, so ReleaseIcon must
-- refuse BEFORE any callback or mutation and return false. Out of combat, or with
-- no clickButton, it releases normally and returns true.

local function noop() end

local inCombat = false
_G.InCombatLockdown = function() return inCombat end

UIParent = {}
GameTooltip = {
    IsForbidden = function() return false end,
    Hide = noop,
}

function CreateFrame(frameType, name, parent)
    local frame = {
        frameType = frameType,
        name = name,
        parent = parent,
        shown = true,
        alpha = 1,
        frameLevel = 1,
    }
    function frame:SetSize(width, height)
        self.width = width
        self.height = height
    end
    function frame:SetAllPoints(target) self.allPoints = target or true end
    function frame:ClearAllPoints() self.allPoints = nil end
    function frame:SetPoint(...) self.point = { ... } end
    function frame:SetParent(newParent) self.parent = newParent end
    function frame:SetFrameLevel(level) self.frameLevel = level end
    function frame:GetFrameLevel() return self.frameLevel end
    function frame:EnableMouse(value) self.mouseEnabled = value end
    function frame:SetScript(scriptName, handler) self[scriptName] = handler end
    function frame:Show() self.shown = true end
    function frame:Hide() self.shown = false end
    function frame:IsShown() return self.shown end
    function frame:SetAlpha(value) self.alpha = value end
    function frame:GetAlpha() return self.alpha end
    function frame:GetEffectiveAlpha() return self.alpha end
    function frame:CreateTexture() return { SetAllPoints = noop, SetTexture = noop, SetDesaturated = noop, SetVertexColor = noop } end
    function frame:CreateFontString() return { SetPoint = noop, SetFont = noop, SetText = noop, SetTextColor = noop, Show = noop, Hide = noop } end
    if frameType == "Cooldown" then
        function frame:SetDrawSwipe(value) self.drawSwipe = value end
        function frame:SetHideCountdownNumbers(value) self.hideCountdownNumbers = value end
        function frame:SetSwipeTexture(value) self.swipeTexture = value end
        function frame:SetSwipeColor(r, g, b, a) self.swipeColor = { r, g, b, a } end
        function frame:SetDrawBling(value) self.drawBling = value end
        function frame:Clear() self.cleared = true end
        function frame:EnableMouse(value) self.mouseEnabled = value end
    end
    return frame
end

local ns = {
    Helpers = {
        GetGeneralFont = function() return "Fonts\\FRIZQT__.TTF" end,
        GetGeneralFontOutline = function() return "" end,
        IsSecretValue = function() return false end,
        SafeValue = function(value) return value end,
    },
    CDMSources = {},
    CDMResolvers = {
        GetEntryTexture = function() return 134400 end,
        GetSpellTexture = function() return 134400 end,
        ResolveCooldownState = function() return nil end,
        ResolveMacro = function() return nil end,
        IsAuraEntry = function() return false end,
    },
}

local loadChunk = dofile("tests/helpers/load_cdm_consolidated_chunk.lua")
loadChunk("QUI_CDM/cdm/cdm_icon_factory.lua", "cdm_icon_factory.lua")("QUI", ns)
local F = assert(ns.CDMIconFactory)

local hidden, callbackRan
local function newIcon(withClick)
    local icon = {}
    icon.Hide = function(self) hidden = true end
    icon.ClearAllPoints = function() end
    icon.SetParent = function() end
    icon.Cooldown = { Clear = function() end, SetAlpha = function() end }
    icon.StackText = { SetText = function() end, Hide = function() end, SetAlpha = function() end }
    icon.Border = { Hide = function() end, SetAlpha = function() end }
    icon.Icon = { SetVertexColor = function() end, SetDesaturated = function() end, SetAlpha = function() end }
    icon.DurationText = { SetAlpha = function() end }
    if withClick then icon.clickButton = { secure = true } end
    return icon
end
-- Route the released callback through a stub so we can prove it never runs on refusal.
ns.CDMIcons = ns.CDMIcons or {}
ns.CDMIcons.OnFactoryIconReleased = function()
    callbackRan = true
end

-- Combat + clickButton: refuse before any mutation/callback.
inCombat, hidden, callbackRan = true, false, false
local protectedIcon = newIcon(true)
local ret = F:ReleaseIcon(protectedIcon)
assert(ret == false, "combat + clickButton -> ReleaseIcon returns false")
assert(hidden == false, "refused ReleaseIcon must NOT Hide the protected parent")
assert(callbackRan == false, "backstop must refuse BEFORE callback runs")

-- Combat, no clickButton: safe to release, returns true.
inCombat, hidden, callbackRan = true, false, false
local plainIcon = newIcon(false)
assert(F:ReleaseIcon(plainIcon) == true, "combat + no clickButton -> release proceeds, returns true")
assert(hidden == true, "plain icon still hidden on release")
assert(callbackRan == true, "release must call OnFactoryIconReleased on success")

-- Out of combat + clickButton: release proceeds (OOC recycle is legal), returns true.
inCombat, hidden, callbackRan = false, false, false
local oocIcon = newIcon(true)
assert(F:ReleaseIcon(oocIcon) == true, "OOC + clickButton -> release proceeds, returns true")
assert(hidden == true, "OOC clickButton icon still hidden on release")
assert(callbackRan == true, "release must call OnFactoryIconReleased on success")

-- Init-safe carve-out: combat + clickButton but ns._inInitSafeWindow = true -> release proceeds, returns true.
inCombat, hidden, callbackRan = true, false, false
ns._inInitSafeWindow = true
local initSafeIcon = newIcon(true)
assert(F:ReleaseIcon(initSafeIcon) == true, "init-safe window + clickButton -> release proceeds, returns true")
assert(hidden == true, "init-safe icon must be hidden on release")
assert(callbackRan == true, "release must call OnFactoryIconReleased on success")
ns._inInitSafeWindow = nil

print("OK: cdm_icon_factory_combat_release_backstop_test")
