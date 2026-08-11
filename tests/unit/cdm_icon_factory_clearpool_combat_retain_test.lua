-- tests/unit/cdm_icon_factory_clearpool_combat_retain_test.lua
-- Run: lua tests/unit/cdm_icon_factory_clearpool_combat_retain_test.lua
--
-- ClearPool must honor the release-refusal contract. ReleaseIcon returns false
-- (without hiding) when it refuses to recycle a combat-protected icon (secure
-- clickButton child). ClearPool previously wiped the whole pool unconditionally,
-- stranding the refused icon: still Show()n, still clickable, no longer tracked =
-- untracked protected orphan. Fix: keep refused icons in the pool.

local function noop() end

local function wipeTable(t)
    for k in pairs(t) do
        t[k] = nil
    end
    return t
end

local inCombat = false
_G.InCombatLockdown = function() return inCombat end
_G.wipe = wipeTable

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

local function newIcon(withClick)
    local icon = { _shown = true }
    icon.Hide = function(self) self._shown = false end
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

local pool = F:EnsurePool("essential")
local prot = newIcon(true)
local plain = newIcon(false)
pool[1] = prot
pool[2] = plain

-- In combat: ClearPool retains the protected icon (refused, not hidden), releases + drops the plain one.
inCombat = true
local afterCombat = F:ClearPool("essential")
assert(prot._shown == true, "protected icon NOT hidden in combat (release refused)")
local protTracked, plainTracked = false, false
for i = 1, #afterCombat do
    if afterCombat[i] == prot then protTracked = true end
    if afterCombat[i] == plain then plainTracked = true end
end
assert(protTracked, "refused protected icon stays tracked in the pool (no orphan)")
assert(not plainTracked, "plain icon released + removed from pool")
assert(plain._shown == false, "plain icon hidden on release")

-- Out of combat: ClearPool fully clears (identical to legacy behavior).
inCombat = false
local afterOOC = F:ClearPool("essential")
assert(#afterOOC == 0, "OOC ClearPool wipes the pool entirely")
assert(prot._shown == false, "the retained protected icon is hidden once OOC")

print("OK: cdm_icon_factory_clearpool_combat_retain_test")
