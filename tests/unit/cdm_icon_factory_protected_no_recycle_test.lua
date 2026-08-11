-- tests/unit/cdm_icon_factory_protected_no_recycle_test.lua
-- Run: lua tests/unit/cdm_icon_factory_protected_no_recycle_test.lua
--
-- Protected (clickButton) icons must NEVER enter the shared recyclePool: AcquireIcon
-- could otherwise pop one into a container rebuilding in combat -> protected
-- SetParent/SetSize/Hide -> ADDON_ACTION_BLOCKED. Plain icons still recycle.

local function noop() end

_G.InCombatLockdown = function() return false end  -- OOC: release runs to the recycle-push

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
local recycle = assert(F._recyclePool, "factory exposes _recyclePool")

local function newIcon(withClick)
    local icon = {}
    icon.Hide = function() end
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

local function inRecycle(icon)
    for i = 1, #recycle do if recycle[i] == icon then return true end end
    return false
end

-- Plain icon: recycled as before.
local plain = newIcon(false)
F:ReleaseIcon(plain)
assert(inRecycle(plain), "plain icon IS returned to the recyclePool")

-- Protected icon: quarantined, never recycled.
local prot = newIcon(true)
F:ReleaseIcon(prot)
assert(not inRecycle(prot), "protected (clickButton) icon is NOT recycled (quarantined)")

print("OK: cdm_icon_factory_protected_no_recycle_test")
