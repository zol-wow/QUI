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
}

assert(loadfile("QUI_Skinning/skinning/system/tooltips.lua"))("QUI", ns)
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

local tooltipSkinningSource = readFile("QUI_Skinning/skinning/system/tooltips.lua")
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

print("OK: tooltip_game_font_object_test")
