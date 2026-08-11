-- tests/unit/tooltip_unit_aura_forbidden_probe_test.lua
-- Run: lua tests/unit/tooltip_unit_aura_forbidden_probe_test.lua

local function readFile(path)
    local fh = assert(io.open(path, "rb"), "failed to open " .. path)
    local text = fh:read("*a")
    fh:close()
    return text
end

local function assertContains(text, needle, reason)
    assert(text:find(needle, 1, true), reason)
end

local function assertNotContains(text, needle, reason)
    assert(not text:find(needle, 1, true), reason)
end

local tooltipSkin = readFile("modules/skinning/system/tooltips.lua")
local tooltipQOL = readFile("modules/qol/tooltip.lua")
local auraContainerTOC = readFile(
    "tests/framexml/Interface/AddOns/Blizzard_AuraContainer/Blizzard_AuraContainer.toc")
local auraTooltipXML = readFile(
    "tests/framexml/Interface/AddOns/Blizzard_AuraContainer/Mainline/Blizzard_AuraButtonTooltip.xml")
local auraContainerInbound = readFile(
    "tests/framexml/Interface/AddOns/Blizzard_AuraContainer/Blizzard_AuraContainerInbound.lua")

-- Blizzard contract: the tooltip object is not in the add-on-visible
-- environment, but 12.1 publishes narrow styling setters through the inbound
-- bridge.
assertContains(auraContainerTOC, "## UseSecureEnvironment: 1",
    "AuraContainer must be modeled as a secure-environment Blizzard add-on")
assertContains(auraTooltipXML, '<ScopedModifier forbidden="true" hideFromGlobalEnv="true">',
    "AuraButtonTooltip must be modeled as forbidden and hidden from _G")
assertContains(auraContainerInbound, "GetDefaultAuraDurationFormatter",
    "test fixture should expose AuraContainer's one public inbound helper")
assertContains(auraContainerInbound, "SetTooltipNineSlice",
    "AuraContainer must expose its secure tooltip nine-slice styling bridge")
assertContains(auraContainerInbound, "SetTooltipTextureSlice",
    "AuraContainer must expose its secure tooltip texture-slice styling bridge")
assertContains(auraContainerInbound, "SetTooltipBackdrop",
    "AuraContainer must expose its secure tooltip backdrop styling bridge")

-- Tripwire: only the audited styling surface may mention the tooltip. Census
-- every identifier in the file; any tooltip-mentioning identifier outside the
-- exact sanctioned set — including extensions of sanctioned names such as
-- SetTooltipBackdropBorderColor — must force this limitation to be re-audited.
local sanctionedTooltipIdentifiers = {
    ["SetTooltipNineSlice"] = true,
    ["InboundSetTooltipNineSlice"] = true,
    ["SetTooltipTextureSlice"] = true,
    ["InboundSetTooltipTextureSlice"] = true,
    ["SetTooltipBackdrop"] = true,
    ["InboundSetTooltipBackdrop"] = true,
    ["ResetTooltipStyle"] = true,
    ["TooltipDefaultLayout"] = true,
    ["TOOLTIP_DEFAULT_BACKGROUND_COLOR"] = true,
}
for identifier in auraContainerInbound:gmatch("[%w_]+") do
    if identifier:lower():find("tooltip", 1, true)
        and not sanctionedTooltipIdentifiers[identifier] then
        error("a new AuraContainer inbound tooltip identifier must force this"
            .. " limitation to be re-audited: " .. identifier)
    end
end
assertNotContains(auraContainerTOC, "Outbound",
    "AuraContainer must not expose its forbidden tooltip object through an outbound bridge")

-- Normal, add-on-visible UnitAura tooltips still use the standard post-call path.
assertContains(tooltipSkin,
    "local auraTooltipType = Enum.TooltipDataType.UnitAura or Enum.TooltipDataType.Aura",
    "tooltip skinning must resolve the aura tooltip type with a client-version fallback")
assertContains(tooltipSkin,
    "TooltipDataProcessor.AddTooltipPostCall(auraTooltipType, RunHandlePostCall)",
    "normal UnitAura tooltips must retain the standard QUI post-call")

-- The styling bridge does not make secure-environment globals visible.
-- PrivateAurasTooltipMixin, TooltipDataProcessor, and EventRegistry remain
-- separate inside the secure environment.
assertNotContains(tooltipSkin, "hooksecurefunc(PrivateAurasTooltipMixin",
    "QUI must not hook a secure-environment-only mixin")
assertNotContains(tooltipSkin, "SetupAuraTooltipEventHook",
    "QUI must not install an aura-specific global EventRegistry hook that cannot see the secure tooltip")
assertNotContains(tooltipSkin, "ApplyTooltipChrome(tooltip, true)",
    "QUI must not bypass secret geometry guards for forbidden AuraButtonTooltip")
assertContains(tooltipSkin, 'local bridge = _G.AuraContainerInbound',
    "the runtime probe status must feature-detect the inbound styling bridge")
assertContains(tooltipSkin, '"inbound-bridge" or "secure-environment"',
    "probe status must report bridge support with a secure-environment fallback")
assertContains(tooltipSkin, "ApplyAuraTooltipStyle",
    "the QUI side must push its skin through the inbound bridge (68914 re-patch)")
assertNotContains(tooltipSkin, "AuraButtonTooltip:",
    "QUI must never call methods on the forbidden tooltip object directly")
assertContains(tooltipQOL, "auratip status skin=%s supported=%s reason=%s",
    "tooltip debug must report the limitation instead of a dead hook status")
assertContains(tooltipQOL, 'AppendCounter(parts, "skin.protectedTooltipSkipped", "protSkip")',
    "protected tooltip skips must remain visible in periodic tooltip debug reports")
assertNotContains(tooltipQOL, "tryAuraButtonTooltipSkin",
    "tooltip debug must not expose a toggle for an impossible skin attempt")

local function makeFrame(name)
    local frame = {
        name = name,
        shown = false,
        scripts = {},
        events = {},
    }

    function frame:GetName() return self.name end
    function frame:RegisterEvent(event) self.events[event] = true end
    function frame:SetScript(scriptName, handler) self.scripts[scriptName] = handler end
    function frame:IsShown() return self.shown end
    function frame:Show() self.shown = true end
    function frame:Hide() self.shown = false end
    function frame:SetAllPoints() self.allPoints = true end
    function frame:EnableMouse() end
    function frame:SetFrameLevel(level) self.frameLevel = level end
    function frame:SetFrameStrata(strata) self.frameStrata = strata end
    function frame:GetWidth() return 200 end
    function frame:GetHeight() return 80 end
    function frame:GetFrameLevel() return 10 end
    function frame:GetFrameStrata() return "TOOLTIP" end
    function frame:GetObjectType() return self.objectType or "GameTooltip" end
    function frame:GetOwner() return self.owner end
    function frame:GetParent() return self.parent end
    function frame:IsForbidden() return self.forbidden == true end
    function frame:IsProtected() return self.protected == true end

    return frame
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
local hookedShows = {}
local callbacks = {}
local debugCounts = {}

_G.UIParent = makeFrame("UIParent")
_G.WorldFrame = makeFrame("WorldFrame")
_G.GameTooltip = makeFrame("GameTooltip")
_G.GameTooltip.shown = true
_G.GameTooltipHeaderText = makeFontObject("Fonts\\FRIZQT__.TTF", 14, "")
_G.GameTooltipText = makeFontObject("Fonts\\FRIZQT__.TTF", 12, "")
_G.InCombatLockdown = function() return false end
_G.issecretvalue = function() return false end
_G.STANDARD_TEXT_FONT = "Fonts\\FRIZQT__.TTF"
_G.ADDON_LOADED = "ADDON_LOADED"
_G.CreateFrame = function(_, name, parent)
    local frame = makeFrame(name)
    frame.parent = parent
    if not eventFrame then eventFrame = frame end
    return frame
end
_G.C_Timer = { After = function(_, callback) callback() end }
_G.hooksecurefunc = function(target, methodName)
    if methodName == "Show" then
        hookedShows[target] = (hookedShows[target] or 0) + 1
    end
end
_G.wipe = function(tbl)
    for key in pairs(tbl) do tbl[key] = nil end
end
_G.Enum = {
    TooltipDataType = {
        Item = 1,
        Spell = 2,
        Unit = 3,
        UnitAura = 4,
    },
}
_G.TooltipDataProcessor = {
    AddTooltipPostCall = function(tooltipType, callback)
        callbacks[tooltipType] = callback
    end,
}

local ns = {
    Helpers = {
        GetCore = function()
            return {
                db = { profile = { tooltip = {
                    enabled = true, skinTooltips = true, fontSize = 13,
                } } },
            }
        end,
        CreateStateTable = function() return setmetatable({}, { __mode = "k" }) end,
        FrameIsProtected = function(frame)
            return frame and frame.protected == true
        end,
        GetSkinBorderColor = function() return 1, 1, 1, 1 end,
        GetSkinBgColor = function() return 0, 0, 0, 1 end,
        GetGeneralFont = function() return "Fonts\\FRIZQT__.TTF" end,
        GetGeneralFontOutline = function() return "OUTLINE" end,
        IsSecretValue = function() return false end,
    },
    QUI_TooltipDebug = {
        enabled = true,
        Count = function(_, name, amount)
            debugCounts[name] = (debugCounts[name] or 0) + (amount or 1)
        end,
        Begin = function() return nil, nil end,
        End = function() end,
    },
    SkinBase = {
        CHROME = { BG_FALLBACK = {0, 0, 0, 1} },
        SkinFrameText = function() end,
    },
    UIKit = {
        CreateBackground = function() return { SetVertexColor = function() end } end,
        CreateBorderLines = function() end,
        UpdateBorderLines = function() end,
    },
    WhenLoggedIn = function(fn) fn() end,
    -- core/safecall.lua stub: silent pcall swallow matches the pre-SafeCall
    -- shape these tests were written against.
    SafeCall = function(_policy, fn, ...) return pcall(fn, ...) end,
    SafeCallMethod = function(_policy, obj, name, ...) return pcall(function(...) return obj[name](obj, ...) end, ...) end,
    SafeCallMethodIfPresent = function(_policy, obj, name, ...) if obj == nil then return nil end local okP, m = pcall(function() return obj[name] end) if not okP then return false end if m == nil then return nil end return pcall(m, obj, ...) end,
}

assert(loadfile("modules/skinning/system/tooltips.lua"))("QUI", ns)
local auraPostCall = assert(callbacks[Enum.TooltipDataType.UnitAura],
    "tooltip skinning must register a UnitAura TooltipDataProcessor callback")

local normalTooltip = makeFrame("NormalAuraTooltip")
auraPostCall(normalTooltip)
assert(hookedShows[normalTooltip] == 1,
    "normal UnitAura tooltip should install the standard tooltip Show hook")

local protectedOwner = makeFrame("ProtectedOwner")
protectedOwner.protected = true
local protectedTooltip = makeFrame("ProtectedAuraTooltip")
protectedTooltip.owner = protectedOwner
auraPostCall(protectedTooltip)
assert(hookedShows[protectedTooltip] == nil,
    "protected-owner UnitAura tooltip must return before installing hooks")

local forbiddenTooltip = makeFrame("AuraButtonTooltip")
forbiddenTooltip.forbidden = true
auraPostCall(forbiddenTooltip)
assert(hookedShows[forbiddenTooltip] == nil,
    "forbidden UnitAura tooltip must stay entirely Blizzard-owned")
assert(debugCounts["skin.protectedTooltipSkipped"] == 2,
    "protected and forbidden non-GameTooltip skips should remain observable")

local status = assert(ns.QUI_GetAuraTooltipProbeStatus and ns.QUI_GetAuraTooltipProbeStatus(),
    "tooltip skinning must expose the AuraButtonTooltip support status")
assert(status.skinningLoaded == true, "status should report the skinning module as loaded")
assert(status.supported == false, "status should report native AuraButtonTooltip skinning unsupported")
assert(status.reason == "secure-environment", "status should report the exact boundary")

print("OK: tooltip_unit_aura_forbidden_probe_test")
