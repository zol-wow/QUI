-- tests/cdm_icon_factory_bling_test.lua
-- Run: lua tests/cdm_icon_factory_bling_test.lua

local function noop() end

function InCombatLockdown() return false end

UIParent = {}
GameTooltip = {
    IsForbidden = function() return false end,
    Hide = noop,
}

local cooldownFrames = {}

local function NewRegion()
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
        Show = noop,
        Hide = noop,
    }
end

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
    function frame:CreateTexture() return NewRegion() end
    function frame:CreateFontString() return NewRegion() end

    if frameType == "Cooldown" then
        cooldownFrames[#cooldownFrames + 1] = frame
        function frame:SetDrawSwipe(value) self.drawSwipe = value end
        function frame:SetHideCountdownNumbers(value) self.hideCountdownNumbers = value end
        function frame:SetSwipeTexture(value) self.swipeTexture = value end
        function frame:SetSwipeColor(r, g, b, a) self.swipeColor = { r, g, b, a } end
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
        GetEntryTexture = function() return 134400 end,
        GetSpellTexture = function() return 134400 end,
        QueryCharges = function() return nil end,
        QueryCooldown = function() return nil end,
        QueryOverrideSpell = function() return nil end,
        QueryDisplayCount = function() return nil end,
        ResolveAuraStateForIcon = function() return nil end,
        HasRealCooldownState = function() return false end,
        ResolveMacro = function() return nil end,
        IsAuraEntry = function() return false end,
        ResolveBlizzardMirrorIdentity = function()
            return 9001, "essential"
        end,
    },
}

assert(loadfile("modules/cdm/cdm_icon_factory.lua"))("QUI", ns)

local iconAPI = {
    CancelCooldownExpiryRefresh = noop,
    StopCustomBarActiveGlow = noop,
    UpdateIconProfessionQuality = noop,
    UpdateIconSecureAttributes = noop,
}

ns.CDMIconFactory._FinalizeImports(iconAPI)

local parent = CreateFrame("Frame", "Parent", UIParent)
local entry = {
    id = 12345,
    spellID = 12345,
    type = "spell",
    kind = "cooldown",
    viewerType = "essential",
}

local icon = ns.CDMIconFactory:AcquireIcon(parent, entry)
local cooldown = assert(icon and icon.Cooldown, "AcquireIcon should create a cooldown frame")

assert(cooldown.drawBling == false,
    "owned CDM cooldowns should suppress Blizzard ready-flash bling at creation and mirror bind")

icon:Show()
icon:SetAlpha(1)
ns.CDMIconFactory.SyncCooldownBling(icon)

assert(cooldown.drawBling == false,
    "visibility sync should keep Blizzard ready-flash bling suppressed")

assert(#cooldownFrames == 1, "test should create exactly one cooldown frame")

print("OK: cdm_icon_factory_bling_test")
