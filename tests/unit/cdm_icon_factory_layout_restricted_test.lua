local function noop() end

_G.InCombatLockdown = function() return false end
_G.UIParent = {}

local tooltipOwner, tooltipAnchor
_G.GameTooltip = {
    IsForbidden = function() return false end,
    SetOwner = function(_, owner, anchor)
        tooltipOwner, tooltipAnchor = owner, anchor
    end,
    SetSpellByID = noop,
    Show = noop,
    Hide = noop,
}

local function Region()
    return {
        SetAllPoints = noop,
        SetPoint = noop,
        SetTexture = noop,
        SetDesaturated = noop,
        SetVertexColor = noop,
        SetColorTexture = noop,
        SetFont = noop,
        SetText = noop,
        SetTextColor = noop,
        SetAlpha = noop,
        Show = noop,
        Hide = noop,
    }
end

_G.CreateFrame = function(frameType, name, parent, template)
    local frame = {
        frameType = frameType,
        name = name,
        parent = parent,
        template = template,
        shown = true,
        frameLevel = 1,
    }
    function frame:SetSize(width, height) self.width, self.height = width, height end
    function frame:SetAllPoints(target) self.allPoints = target or true end
    function frame:ClearAllPoints() self.allPoints = nil end
    function frame:SetPoint(...) self.point = { ... } end
    function frame:SetParent(value) self.parent = value end
    function frame:SetFrameLevel(value) self.frameLevel = value end
    function frame:GetFrameLevel() return self.frameLevel end
    function frame:EnableMouse(value) self.mouseEnabled = value end
    function frame:RegisterForClicks(...) self.registeredClicks = { ... } end
    function frame:SetScript(script, callback) self[script] = callback end
    function frame:Show() self.shown = true end
    function frame:Hide() self.shown = false end
    function frame:IsShown() return self.shown end
    function frame:SetAlpha(value) self.alpha = value end
    function frame:GetAlpha() return self.alpha or 1 end
    function frame:GetEffectiveAlpha() return self.alpha or 1 end
    function frame:CreateTexture() return Region() end
    function frame:CreateFontString() return Region() end
    if frameType == "Cooldown" then
        function frame:SetDrawSwipe(value) self.drawSwipe = value end
        function frame:SetHideCountdownNumbers(value) self.hideCountdownNumbers = value end
        function frame:SetSwipeTexture(value) self.swipeTexture = value end
        function frame:SetSwipeColor(...) self.swipeColor = { ... } end
        function frame:SetDrawBling(value) self.drawBling = value end
        function frame:Clear() self.cleared = true end
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
        GetEntryTexture = function() return nil end,
        GetSpellTexture = function() return nil end,
        ResolveCooldownState = function() return nil end,
        ResolveMacro = function() return nil end,
        IsAuraEntry = function() return false end,
    },
}

local loadChunk = dofile("tests/helpers/load_cdm_consolidated_chunk.lua")
loadChunk("QUI_CDM/cdm/cdm_icon_factory.lua", "cdm_icon_factory.lua")("QUI", ns)
local factory = assert(ns.CDMIconFactory)
local parent = CreateFrame("Frame", "Parent", UIParent)
local entry = { id = 777, spellID = 777, type = "spell" }

local plain = factory:AcquireIcon(parent, entry, false, false)
local restricted = factory:AcquireIcon(parent, entry, false, true)
assert(plain.template == nil and plain._quiLayoutRestricted == nil,
    "ordinary icons must remain unrestricted")
assert(restricted.template == "DisableUntrustedLayoutScriptsTemplate"
    and restricted._quiLayoutRestricted == true,
    "restricted icons must opt into the template at frame creation")
assert(plain.Cooldown.template == "CooldownFrameTemplate" and plain.TextOverlay.template == nil,
    "ordinary icon children must remain unrestricted")
assert(restricted.Cooldown.template
        == "CooldownFrameTemplate, DisableUntrustedLayoutScriptsTemplate"
    and restricted.TextOverlay.template == "DisableUntrustedLayoutScriptsTemplate",
    "restricted icon children must opt into the template at frame creation")

restricted._runtimeSpellID = 777
restricted.OnEnter(restricted)
assert(tooltipOwner == UIParent and tooltipAnchor == "ANCHOR_CURSOR",
    "restricted tooltips must anchor through UIParent")

factory:ReleaseIcon(restricted)
assert(factory._recycleRestrictedPool[1] == restricted
    and #factory._recyclePool == 0,
    "restricted icons must use their isolated recycle pool")
local secondPlain = factory:AcquireIcon(parent, entry, false, false)
assert(secondPlain ~= restricted,
    "ordinary acquisition must not reuse a restricted shell")
local reusedRestricted = factory:AcquireIcon(parent, entry, false, true)
assert(reusedRestricted == restricted,
    "restricted acquisition must reuse the restricted shell")

reusedRestricted.clickButton = {}
factory:ReleaseIcon(reusedRestricted)
assert(factory._recycleRestrictedProtectedPool[1] == restricted,
    "restricted protected icons must use their isolated protected pool")
assert(factory:AcquireIcon(parent, entry, true, true) == restricted,
    "clickable restricted acquisition must reuse the protected restricted shell")

local rendererFile = assert(io.open("QUI_CDM/cdm/cdm_icon_renderer.lua", "rb"))
local rendererSource = rendererFile:read("*a")
rendererFile:close()
local clickStart = assert(rendererSource:find("local function EnsureClickButton(icon)", 1, true))
local clickStop = assert(rendererSource:find("\nlocal function ClearClickButtonAttributes", clickStart, true))
local clickSource = rendererSource:sub(clickStart, clickStop - 1)
clickSource = clickSource:gsub("^local function EnsureClickButton", "return function", 1)
local clickEnv = setmetatable({
    CDMIcons = { EnsureTextOverlayLevel = noop },
    SyncClickButtonFrameLevel = noop,
}, { __index = _G })
local clickChunk = assert(loadstring(clickSource, "@cdm_icon_renderer.lua#EnsureClickButton"))
setfenv(clickChunk, clickEnv)
local ensureClickButton = clickChunk()
local plainClick = ensureClickButton({})
local restrictedClick = ensureClickButton({ _quiLayoutRestricted = true })
assert(plainClick.template == "SecureActionButtonTemplate",
    "ordinary click overlays must remain unrestricted")
assert(restrictedClick.template
        == "SecureActionButtonTemplate, DisableUntrustedLayoutScriptsTemplate",
    "restricted click overlays must opt into the template at frame creation")

print("OK: cdm_icon_factory_layout_restricted_test")
