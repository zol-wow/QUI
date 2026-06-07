-- tests/unit/cdm_icon_factory_bling_test.lua
-- Run: lua tests/unit/cdm_icon_factory_bling_test.lua

local BuildCooldownStateContext = dofile("tests/helpers/cdm_context_builder_stub.lua")

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
        BuildCooldownStateContext = BuildCooldownStateContext,
        GetEntryTexture = function() return 134400 end,
        GetSpellTexture = function() return 134400 end,
        ResolveCooldownState = function() return nil end,
        ResolveMacro = function() return nil end,
        IsAuraEntry = function() return false end,
        ResolveBlizzardMirrorIdentityState = function()
            return {
                cooldownID = 9001,
                category = "essential",
            }
        end,
    },
}

local loadChunk = dofile("tests/helpers/load_cdm_consolidated_chunk.lua")
loadChunk("QUI_CDM/cdm/cdm_icon_renderer.lua", "cdm_icon_factory.lua")("QUI", ns)

local createdIcon, createdEntry
local acquiredIcon, acquiredEntry, acquiredReused
local releasedIcon

ns.CDMIcons = {
    OnFactoryIconCreated = function(icon, entry)
        createdIcon = icon
        createdEntry = entry
    end,
    OnFactoryIconAcquired = function(icon, entry, reused)
        acquiredIcon = icon
        acquiredEntry = entry
        acquiredReused = reused
    end,
    OnFactoryIconReleased = function(icon)
        releasedIcon = icon
    end,
}

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

assert(createdIcon == icon and createdEntry == entry,
    "new icon creation should notify CDMIcons through the factory-created lifecycle hook")
assert(acquiredIcon == icon and acquiredEntry == entry and acquiredReused == false,
    "new icon acquisition should notify CDMIcons through the factory-acquired lifecycle hook")
assert(cooldown.drawBling == false,
    "owned CDM cooldowns should suppress Blizzard ready-flash bling at creation and mirror bind")

icon:Show()
icon:SetAlpha(1)
ns.CDMIconFactory.SyncCooldownBling(icon)

assert(cooldown.drawBling == false,
    "visibility sync should keep Blizzard ready-flash bling suppressed")

createdIcon = nil
acquiredIcon = nil
acquiredEntry = nil
acquiredReused = nil
releasedIcon = nil

ns.CDMIconFactory:ReleaseIcon(icon)
assert(releasedIcon == icon,
    "icon release should notify CDMIcons through the factory-released lifecycle hook")

local recycledIcon = ns.CDMIconFactory:AcquireIcon(parent, entry)
assert(recycledIcon == icon, "released icon should be reused from the recycle pool")
assert(createdIcon == nil,
    "recycled icon acquisition should not send another factory-created lifecycle hook")
assert(acquiredIcon == icon and acquiredEntry == entry and acquiredReused == true,
    "recycled icon acquisition should notify CDMIcons through the factory-acquired lifecycle hook")

assert(#cooldownFrames == 1, "test should create exactly one cooldown frame")

print("OK: cdm_icon_factory_bling_test")
