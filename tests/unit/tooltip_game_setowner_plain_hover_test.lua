-- tests/unit/tooltip_game_setowner_plain_hover_test.lua
-- Run: lua tests/unit/tooltip_game_setowner_plain_hover_test.lua
--
-- Plain hover tooltips often build GameTooltip with:
--   GameTooltip:SetOwner(owner, anchor); GameTooltip:SetText/AddLine(...); Show()
-- They do not necessarily call GameTooltip_SetDefaultAnchor or produce tooltip
-- data post-calls. GameTooltip intentionally has no Show hook, so SetOwner needs
-- a narrow styling trigger for safe owners.

local capturedSetOwnerHook
local updateBorderCalls = 0

local function makeFrame(name, objectType)
    local frame = {
        name = name,
        objectType = objectType or "Frame",
        shown = false,
        children = {},
    }

    function frame:GetName() return self.name end
    function frame:GetObjectType() return self.objectType end
    function frame:IsShown() return self.shown end
    function frame:Show() self.shown = true end
    function frame:Hide() self.shown = false end
    function frame:SetShown(shown) self.shown = shown and true or false end
    function frame:IsForbidden() return false end
    function frame:SetAllPoints() self.allPoints = true end
    function frame:EnableMouse() end
    function frame:SetFrameLevel(level) self.frameLevel = level end
    function frame:SetFrameStrata(strata) self.frameStrata = strata end
    function frame:GetFrameLevel() return 10 end
    function frame:GetFrameStrata() return "TOOLTIP" end
    function frame:GetWidth() return 220 end
    function frame:GetHeight() return 80 end
    function frame:GetNumChildren() return #self.children end
    function frame:GetChildren() return table.unpack(self.children) end
    function frame:GetParent() return self.parent end
    function frame:GetOwner() return self.owner end
    function frame:RegisterEvent(event)
        self.events = self.events or {}
        self.events[event] = true
    end
    function frame:SetScript(scriptName, handler)
        self.scripts = self.scripts or {}
        self.scripts[scriptName] = handler
    end
    function frame:SetOwner(owner, anchor)
        self.owner = owner
        self.anchor = anchor
    end
    function frame:NumLines() return 0 end

    return frame
end

local function makeNineSlice()
    local ns = makeFrame("GameTooltipNineSlice", "Frame")
    ns.shown = true
    function ns:IsShown() return self.shown end
    function ns:Show() self.shown = true end
    function ns:Hide() self.shown = false end
    function ns:SetFrameLevel(level) self.frameLevel = level end
    return ns
end

local function makeFontObject(path, size, flags)
    local fontObject = { path = path, size = size, flags = flags }
    function fontObject:GetFont() return self.path, self.size, self.flags end
    function fontObject:SetFont(pathArg, sizeArg, flagsArg)
        self.path = pathArg
        self.size = sizeArg
        self.flags = flagsArg
    end
    return fontObject
end

local eventFrame
local inCombat = false
local safeOwner = makeFrame("QUIPlainHoverOwner")

_G.UIParent = makeFrame("UIParent")
_G.WorldFrame = makeFrame("WorldFrame")
_G.GameTooltip = makeFrame("GameTooltip", "GameTooltip")
_G.GameTooltip.NineSlice = makeNineSlice()
_G.GameTooltipHeaderText = makeFontObject("Fonts\\FRIZQT__.TTF", 14, "")
_G.GameTooltipText = makeFontObject("Fonts\\FRIZQT__.TTF", 12, "")
_G.GameTooltipTextSmall = makeFontObject("Fonts\\FRIZQT__.TTF", 10, "")

_G.InCombatLockdown = function() return inCombat end
_G.issecretvalue = function() return false end
_G.STANDARD_TEXT_FONT = "Fonts\\FRIZQT__.TTF"
_G.ADDON_LOADED = "ADDON_LOADED"
_G.CreateFrame = function()
    local frame = makeFrame()
    if not eventFrame then eventFrame = frame end
    return frame
end
_G.C_Timer = { After = function(_, callback) callback() end }
_G.hooksecurefunc = function(target, method, callback)
    if target == _G.GameTooltip and method == "SetOwner" then
        capturedSetOwnerHook = callback
    end
end
_G.wipe = function(tbl)
    for key in pairs(tbl) do tbl[key] = nil end
end

local ns = {
    Helpers = {
        GetCore = function()
            return {
                db = { profile = { tooltip = {
                    enabled = true,
                    skinTooltips = true,
                    fontSize = 13,
                } } },
            }
        end,
        CreateStateTable = function() return setmetatable({}, { __mode = "k" }) end,
        GetSkinBorderColor = function() return 0.4, 0.7, 1, 1 end,
        GetSkinBgColor = function() return 0.02, 0.02, 0.02, 0.9 end,
        GetGeneralFont = function() return "Fonts\\FRIZQT__.TTF" end,
        GetGeneralFontOutline = function() return "" end,
        IsSecretValue = function() return false end,
        FrameIsProtected = function() return false end,
    },
    SkinBase = {
        CHROME = { BG_FALLBACK = { 0.02, 0.02, 0.02, 0.9 } },
    },
    UIKit = {
        CreateBackground = function()
            return { SetVertexColor = function() end }
        end,
        CreateBorderLines = function() end,
        UpdateBorderLines = function()
            updateBorderCalls = updateBorderCalls + 1
        end,
    },
    WhenLoggedIn = function(fn) fn() end,
    -- core/safecall.lua stub: silent pcall swallow matches the pre-SafeCall
    -- shape these tests were written against.
    SafeCall = function(_policy, fn, ...) return pcall(fn, ...) end,
    SafeCallMethod = function(_policy, obj, name, ...) return pcall(function(...) return obj[name](obj, ...) end, ...) end,
    SafeCallMethodIfPresent = function(_policy, obj, name, ...) if obj == nil then return nil end local okP, m = pcall(function() return obj[name] end) if not okP then return false end if m == nil then return nil end return pcall(m, obj, ...) end,
}

assert(loadfile("modules/skinning/system/tooltips.lua"))("QUI", ns)

assert(type(capturedSetOwnerHook) == "function",
    "GameTooltip plain SetOwner hovers must install a narrow skinning trigger")

-- Simulate a prior protected/fallback path that left Blizzard NineSlice visible.
_G.GameTooltip.NineSlice:Show()
updateBorderCalls = 0

_G.GameTooltip:SetOwner(safeOwner, "ANCHOR_RIGHT")
capturedSetOwnerHook(_G.GameTooltip, safeOwner, "ANCHOR_RIGHT")

assert(_G.GameTooltip.NineSlice:IsShown() == false,
    "safe plain GameTooltip:SetOwner hovers must re-hide Blizzard NineSlice")
assert(updateBorderCalls > 0,
    "safe plain GameTooltip:SetOwner hovers must refresh QUI tooltip chrome")

-- Combat hovers should still refresh addon-owned chrome. The production path
-- must use the existing CombatRefreshTooltip branch, not the normal font/layout
-- mutation path.
inCombat = true
_G.GameTooltip.NineSlice:Show()
updateBorderCalls = 0

_G.GameTooltip:SetOwner(safeOwner, "ANCHOR_RIGHT")
capturedSetOwnerHook(_G.GameTooltip, safeOwner, "ANCHOR_RIGHT")

assert(_G.GameTooltip.NineSlice:IsShown() == false,
    "safe combat GameTooltip:SetOwner hovers must re-hide Blizzard NineSlice")
assert(updateBorderCalls > 0,
    "safe combat GameTooltip:SetOwner hovers must refresh QUI tooltip chrome")

print("OK: tooltip_game_setowner_plain_hover_test")
