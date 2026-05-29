-- tests/unit/unitframes_castbar_icon_size_test.lua
-- Run: lua tests/unit/unitframes_castbar_icon_size_test.lua
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

    function region:SetSize(width, height)
        self.width = width
        self.height = height
    end

    function region:SetWidth(width)
        self.width = width
    end

    function region:SetHeight(height)
        self.height = height
    end

    function region:GetWidth()
        return self.width
    end

    function region:GetHeight()
        return self.height
    end

    function region:SetPoint(...)
        self.points[#self.points + 1] = {...}
    end

    function region:ClearAllPoints()
        self.points = {}
    end

    function region:SetAllPoints(anchor)
        self.allPoints = anchor or self.parent or true
    end

    function region:Show()
        self.shown = true
    end

    function region:Hide()
        self.shown = false
    end

    function region:IsShown()
        return self.shown
    end

    function region:IsVisible()
        return self.shown and self.alpha ~= 0
    end

    function region:SetAlpha(alpha)
        self.alpha = alpha
    end

    function region:GetAlpha()
        return self.alpha
    end

    function region:SetFrameStrata(strata)
        self.frameStrata = strata
    end

    function region:GetFrameStrata()
        return self.frameStrata
    end

    function region:SetFrameLevel(level)
        self.frameLevel = level
    end

    function region:GetFrameLevel()
        return self.frameLevel
    end

    function region:GetParent()
        return self.parent
    end

    function region:CreateTexture()
        return newRegion("Texture", self)
    end

    function region:CreateFontString()
        local fs = newRegion("FontString", self)
        fs.fontPath = "Fonts\\FRIZQT__.TTF"
        fs.fontSize = 12
        fs.fontFlags = ""
        function fs:SetFont(path, size, flags)
            self.fontPath = path
            self.fontSize = size
            self.fontFlags = flags
        end
        function fs:GetFont()
            return self.fontPath, self.fontSize, self.fontFlags
        end
        function fs:SetText(text)
            self.text = text
        end
        function fs:SetFormattedText(format, value)
            self.text = string.format(format, value)
        end
        function fs:GetStringWidth()
            return #(self.text or "") * 6
        end
        function fs:SetTextColor(r, g, b, a)
            self.textColor = {r, g, b, a}
        end
        function fs:SetWordWrap(value)
            self.wordWrap = value
        end
        function fs:SetJustifyH(value)
            self.justifyH = value
        end
        function fs:SetJustifyV(value)
            self.justifyV = value
        end
        return fs
    end

    function region:SetScript(scriptName, handler)
        self.scripts = self.scripts or {}
        self.scripts[scriptName] = handler
    end

    function region:RegisterUnitEvent(event, ...)
        self.unitEvents = self.unitEvents or {}
        self.unitEvents[event] = {...}
    end

    function region:RegisterEvent(event)
        self.events = self.events or {}
        self.events[event] = true
    end

    function region:UnregisterAllEvents()
        self.unitEvents = {}
        self.events = {}
    end

    function region:SetMovable(value)
        self.movable = value
    end

    function region:EnableMouse(value)
        self.mouseEnabled = value
    end

    function region:RegisterForDrag(...)
        self.dragButtons = {...}
    end

    function region:SetClampedToScreen(value)
        self.clampedToScreen = value
    end

    function region:GetCenter()
        return 0, 0
    end

    function region:SetMinMaxValues(minValue, maxValue)
        self.minValue = minValue
        self.maxValue = maxValue
    end

    function region:SetValue(value)
        self.value = value
    end

    function region:SetStatusBarColor(r, g, b, a)
        self.statusBarColor = {r, g, b, a}
    end

    function region:SetStatusBarTexture(texture)
        self.statusBarTexture = texture
    end

    function region:GetStatusBarTexture()
        if not self.statusBarTextureRegion then
            self.statusBarTextureRegion = newRegion("Texture", self)
        end
        return self.statusBarTextureRegion
    end

    function region:SetReverseFill(value)
        self.reverseFill = value
    end

    function region:SetTexture(texture)
        self.texture = texture
    end

    function region:GetTexture()
        return self.texture
    end

    function region:SetColorTexture(r, g, b, a)
        self.colorTexture = {r, g, b, a}
    end

    function region:SetVertexColor(r, g, b, a)
        self.vertexColor = {r, g, b, a}
    end

    function region:SetTexCoord(...)
        self.texCoord = {...}
    end

    function region:SetSnapToPixelGrid(value)
        self.snapToPixelGrid = value
    end

    function region:SetTexelSnappingBias(value)
        self.texelSnappingBias = value
    end

    return region
end

local now = 100
local activeCast = false
function GetTime() return now end
function CreateFrame(frameType, name, parent)
    local frame = newRegion(frameType, parent)
    frame.name = name
    return frame
end
function InCombatLockdown() return false end
function UnitCastingInfo(unit)
    if unit == "player" and activeCast then
        return "Frostbolt", "Frostbolt", 135846, (now - 0.2) * 1000, (now + 2.8) * 1000, false, "CastGUID", false, 116, nil, 0
    end
    return nil
end
function UnitChannelInfo() return nil end
function UnitClass() return "Player", "MAGE" end
function UnitGUID() return "Player-0000-00000001" end

UIParent = newRegion("Frame")
RAID_CLASS_COLORS = { MAGE = { r = 0.25, g = 0.78, b = 0.92 } }
C_Timer = { After = function(_, callback) callback() end }
EventRegistry = { RegisterCallback = noop }

local ns = {
    Helpers = {},
    Addon = {},
}
local pixelScale = 1
ns.Helpers.IsSecretValue = function() return false end
ns.Helpers.SafeValue = function(value) return value end
ns.Helpers.EnsureDefaults = function(tbl, defaults)
    for key, value in pairs(defaults) do
        if tbl[key] == nil then
            tbl[key] = value
        end
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
ns.Helpers.CreateStateTable = function()
    return setmetatable({}, { __mode = "k" })
end

function ns.Addon:PixelRound(value)
    return math.floor((value / pixelScale) + 0.5) * pixelScale
end
function ns.Addon:Pixels(value) return value * pixelScale end
function ns.Addon:GetPixelSize() return pixelScale end
function ns.Addon:SetPixelPerfectSize(frame, width, height) frame:SetSize(math.floor(width + 0.5) * pixelScale, math.floor(height + 0.5) * pixelScale) end
function ns.Addon:SetPixelPerfectHeight(frame, height) frame:SetHeight(math.floor(height + 0.5) * pixelScale) end
function ns.Addon:SetPixelPerfectPoint(frame, point, relativeTo, relativePoint, x, y)
    frame:SetPoint(point, relativeTo, relativePoint, x, y)
end
function ns.Addon:ApplyPixelSnapping() end
function ns.Addon:ApplyFont(fontString, _, size, path, outline)
    fontString:SetFont(path, size, outline)
end

assert(loadfile("core/uikit.lua"))("QUI", ns)
assert(loadfile("modules/unitframes/castbar.lua"))("QUI", ns)

local settings = {
    player = {
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

local castbar = assert(ns.QUI_Castbar:CreateCastbar(unitFrame, "player", "player"))
assert(castbar.icon:GetWidth() == 22, "test setup should create the icon at the initial setting")

activeCast = true
settings.player.castbar.iconSize = 40
ns.QUI_Castbar:RefreshCastbar(castbar, "player", settings.player.castbar, unitFrame)
assert(castbar.icon:GetWidth() == 40, "active cast refresh should apply the updated icon size immediately")

ns.UIKit.RefreshScaleBoundWidgets()
assert(castbar.icon:GetWidth() == 40, "scale refresh must preserve the castbar icon size setting during an active cast")

activeCast = false
settings.player.castbar.iconSize = 24
local secondUnitFrame = newRegion("Frame", UIParent)
secondUnitFrame:SetSize(220, 40)
local secondCastbar = assert(ns.QUI_Castbar:CreateCastbar(secondUnitFrame, "player", "player"))
assert(secondCastbar.icon:GetWidth() == 24, "test setup should create the second icon at the reset setting")

settings.player.castbar.iconSize = 52
activeCast = true
secondCastbar:Cast(116, false)
assert(secondCastbar.icon:GetWidth() == 52, "spell start should apply the current icon size even when no settings refresh ran")

settings.player.castbar.iconSize = 64
ns.QUI_Castbar:ApplyLiveCastbarSettings(secondCastbar, "player", settings.player.castbar)
assert(secondCastbar.icon:GetWidth() == 64, "combat-safe live castbar settings refresh should resize the current cast icon")

activeCast = false
pixelScale = 0.5
settings.player.castbar.iconSize = 40
settings.player.castbar.iconScale = 1
settings.player.castbar.iconBorderSize = 1
local scaledUnitFrame = newRegion("Frame", UIParent)
scaledUnitFrame:SetSize(220, 40)
local scaledCastbar = assert(ns.QUI_Castbar:CreateCastbar(scaledUnitFrame, "player", "player"))
assert(scaledCastbar.icon:GetWidth() == 40, "castbar icon size should remain in castbar coordinates at non-1 pixel scale")
local topLeftPoint = scaledCastbar.statusBar.points[1]
assert(topLeftPoint and topLeftPoint[1] == "TOPLEFT", "scaled castbar should anchor statusbar after the icon")
assert(topLeftPoint[4] == 40.5, "statusbar offset should use the same coordinate-sized icon width plus a one-pixel border")

print("OK: unitframes_castbar_icon_size_test")
