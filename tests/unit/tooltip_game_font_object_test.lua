-- tests/unit/tooltip_game_font_object_test.lua
-- Run: lua tests/unit/tooltip_game_font_object_test.lua

local function makeFrame()
    local frame = {
        shown = false,
        scripts = {},
        events = {},
    }

    function frame:RegisterEvent(event)
        self.events[event] = true
    end

    function frame:SetScript(scriptName, handler)
        self.scripts[scriptName] = handler
    end

    function frame:IsShown()
        return self.shown
    end

    function frame:Show()
        self.shown = true
    end

    function frame:Hide()
        self.shown = false
    end

    function frame:SetAllPoints()
        self.allPoints = true
    end

    function frame:EnableMouse()
    end

    function frame:SetFrameLevel(level)
        self.frameLevel = level
    end

    function frame:SetFrameStrata(strata)
        self.frameStrata = strata
    end

    function frame:GetWidth()
        return 200
    end

    function frame:GetHeight()
        return 80
    end

    function frame:GetFrameLevel()
        return 10
    end

    function frame:GetFrameStrata()
        return "TOOLTIP"
    end

    function frame:GetOwner()
        return nil
    end

    return frame
end

local function makeFontObject(path, size, flags)
    local fontObject = {
        path = path,
        size = size,
        flags = flags,
    }

    function fontObject:GetFont()
        return self.path, self.size, self.flags
    end

    function fontObject:SetFont(pathArg, sizeArg, flagsArg)
        self.path = pathArg
        self.size = sizeArg
        self.flags = flagsArg
    end

    return fontObject
end

local eventFrame
local customFont = "Interface\\AddOns\\QUI\\assets\\Quazii.ttf"
local gameTooltipSkinFrameTextCalls = 0

_G.UIParent = makeFrame()
_G.WorldFrame = makeFrame()
_G.GameTooltip = makeFrame()
_G.GameTooltip.shown = true
_G.GameTooltipHeaderText = makeFontObject("Fonts\\FRIZQT__.TTF", 14, "")
_G.GameTooltipText = makeFontObject("Fonts\\FRIZQT__.TTF", 12, "")
_G.InCombatLockdown = function() return false end
_G.issecretvalue = function() return false end
_G.STANDARD_TEXT_FONT = "Fonts\\FRIZQT__.TTF"
_G.ADDON_LOADED = "ADDON_LOADED"
_G.CreateFrame = function()
    local frame = makeFrame()
    if not eventFrame then eventFrame = frame end
    return frame
end
_G.C_Timer = { After = function(_, callback) callback() end }
_G.hooksecurefunc = function() end
_G.wipe = function(tbl)
    for key in pairs(tbl) do
        tbl[key] = nil
    end
end

local ns = {
    Helpers = {
        GetCore = function()
            return {
                db = {
                    profile = {
                        tooltip = {
                            enabled = true,
                            skinTooltips = true,
                            fontSize = 13,
                        },
                    },
                },
            }
        end,
        CreateStateTable = function()
            return setmetatable({}, { __mode = "k" })
        end,
        GetSkinBorderColor = function() return 1, 1, 1, 1 end,
        GetSkinBgColor = function() return 0, 0, 0, 1 end,
        GetGeneralFont = function() return customFont end,
        GetGeneralFontOutline = function() return "OUTLINE" end,
        IsSecretValue = function() return false end,
    },
    SkinBase = {
        SkinFrameText = function(frame)
            if frame == _G.GameTooltip then
                gameTooltipSkinFrameTextCalls = gameTooltipSkinFrameTextCalls + 1
            end
        end,
    },
    UIKit = {
        CreateBackground = function()
            return { SetVertexColor = function() end }
        end,
        CreateBorderLines = function() end,
        UpdateBorderLines = function() end,
    },
    -- The LOD skinning addon installs its tooltip hooks via ns.WhenLoggedIn
    -- (runs immediately when already logged in — the post-login LOD case),
    -- NOT via its own ADDON_LOADED. The harness runs the callback synchronously
    -- at load, so init happens during the loadfile call below.
    WhenLoggedIn = function(fn) fn() end,
    -- core/safecall.lua stub: silent pcall swallow matches the pre-SafeCall
    -- shape these tests were written against.
    SafeCall = function(_policy, fn, ...) return pcall(fn, ...) end,
    SafeCallMethod = function(_policy, obj, name, ...) return pcall(function(...) return obj[name](obj, ...) end, ...) end,
    SafeCallMethodIfPresent = function(_policy, obj, name, ...) if obj == nil then return nil end local okP, m = pcall(function() return obj[name] end) if not okP then return false end if m == nil then return nil end return pcall(m, obj, ...) end,
}

assert(loadfile("modules/skinning/system/tooltips.lua"))("QUI", ns)
-- Init already ran (ns.WhenLoggedIn fired synchronously during load). The
-- eventFrame remains for post-init addon-tooltip discovery + combat restore.
assert(eventFrame and eventFrame.scripts.OnEvent, "tooltip skinning must register an event handler")

assert(GameTooltipHeaderText.path == customFont,
    "GameTooltip header Font object should use the configured addon font")
assert(GameTooltipText.path == customFont,
    "GameTooltip body Font object should use the configured addon font for later tooltip lines")
assert(GameTooltipHeaderText.flags == "OUTLINE",
    "GameTooltip header Font object should use the configured outline")
assert(GameTooltipText.flags == "OUTLINE",
    "GameTooltip body Font object should use the configured outline")
assert(GameTooltipHeaderText.size == 15,
    "GameTooltip header Font object should be tooltip font size + 2")
assert(GameTooltipText.size == 13,
    "GameTooltip body Font object should be tooltip font size")
assert(gameTooltipSkinFrameTextCalls == 0,
    "GameTooltip must not route through SkinFrameText/direct FontString SetFont path")

local function readFile(path)
    local fh = assert(io.open(path, "rb"), "failed to open " .. path)
    local text = fh:read("*a")
    fh:close()
    return text
end

local function assertContains(text, needle, reason)
    assert(text:find(needle, 1, true), reason)
end

local function assertAbsent(text, needle, reason)
    assert(not text:find(needle, 1, true), reason)
end

local function assertBefore(text, first, second, reason)
    local firstAt = assert(text:find(first, 1, true), reason .. " (missing first: " .. first .. ")")
    local secondAt = assert(text:find(second, 1, true), reason .. " (missing second: " .. second .. ")")
    assert(firstAt < secondAt, reason)
end

local tooltipSkinningSource = readFile("modules/skinning/system/tooltips.lua")
local tooltipQoLSource = readFile("modules/qol/tooltip.lua")
local helpersSource = readFile("core/utils.lua")
assertContains(tooltipSkinningSource, "local function IsInternalEmbeddedItemTooltipFrame(tooltip)",
    "tooltip skinning must centralize the embedded item reward tooltip guard")

local family = assert(tooltipSkinningSource:match("local gameTooltipFamily = %{%s*(.-)%s*%}"),
    "tooltip skinning must expose the named GameTooltip family list")
assertAbsent(family, '"GameTooltipTooltip"',
    "GameTooltipTooltip is GameTooltip.ItemTooltip.Tooltip and must not receive the normal Show hook")

assertAbsent(tooltipSkinningSource, 'hooksecurefunc(GameTooltip.ItemTooltip, "Show"',
    "GameTooltip.ItemTooltip:Show fires inside Blizzard quest reward sizing and must not be hooked")

local hookBody = assert(tooltipSkinningSource:match("HookTooltipOnShow = function%(tooltip%)%s*(.-)\nend\n\nlocal function HookAllTooltips"),
    "tooltip skinning must define HookTooltipOnShow before HookAllTooltips")
assertContains(hookBody, "IsInternalEmbeddedItemTooltipFrame(tooltip)",
    "dynamic tooltip discovery must refuse embedded item reward tooltip frames before installing Show hooks")

assertContains(helpersSource, "function Helpers.HasTaintedWidgetContainer(tooltip)",
    "shared widget-container taint guard must exist for world quest/GameTooltip widget sets")
assertContains(helpersSource, 'type(child.RegisterForWidgetSet) == "function"',
    "widget-container guard must identify containers via a throw-proof type probe")
assertContains(helpersSource, "Helpers.IsSecretValue(shown)",
    "unreadable shown state must make the tooltip cycle unsafe before boolean test")
assertAbsent(helpersSource, "widgetSetID ~= nil or dirty == true",
    "registration and layout residue on a hidden container must not disable skinning")

assertContains(tooltipSkinningSource, "Helpers.HasTaintedWidgetContainer",
    "tooltip skinning must use the shared widget-container detector")
assertContains(tooltipSkinningSource, "skin.fontWidgetSkipped",
    "deferred GameTooltip font refresh must skip active widget-set tooltips")
local styleTooltipStart = assert(tooltipSkinningSource:find("local function StyleTooltip", 1, true))
local styleTooltipBody = tooltipSkinningSource:sub(styleTooltipStart)
assertBefore(styleTooltipBody,
    "HasActiveWidgetContainer and HasActiveWidgetContainer(tooltip)",
    "ns.SafeCall(\"best-effort-style\", ApplyTooltipChrome, tooltip)",
    "StyleTooltip must guard widget containers before applying chrome")
local onTooltipShowStart = assert(tooltipSkinningSource:find("local function OnTooltipShow", 1, true))
local onTooltipShowBody = tooltipSkinningSource:sub(onTooltipShowStart)
assertBefore(onTooltipShowBody,
    "if HasActiveWidgetContainer(tooltip) then",
    "if HasActiveMoneyFrame(tooltip) then",
    "OnTooltipShow must guard widget containers before money-frame fallback")
local styleGameTooltipStart = assert(tooltipSkinningSource:find("StyleGameTooltip = function%(tooltip%)", 1))
local styleGameTooltipBody = tooltipSkinningSource:sub(styleGameTooltipStart)
assertBefore(styleGameTooltipBody,
    "HasActiveWidgetContainer(tooltip)",
    "IsChromeStable(tooltip)",
    "StyleGameTooltip must fall back before the stable chrome fast path")

assertContains(tooltipQoLSource, "Helpers.HasTaintedWidgetContainer",
    "QoL tooltip layout refresh must use the shared widget-container detector")
assertContains(tooltipQoLSource, "tooltip == GameTooltip and HasActiveWidgetContainer(tooltip) then return false",
    "cursor anchoring must refuse active widget-set GameTooltip cycles")
assertBefore(tooltipQoLSource,
    "if tooltip == GameTooltip and HasActiveWidgetContainer(tooltip) then",
    "if settings.anchorToCursor then",
    "default-anchor hook must bail before immediate custom positioning")

print("OK: tooltip_game_font_object_test")
