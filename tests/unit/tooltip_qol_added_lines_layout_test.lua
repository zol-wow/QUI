-- tests/unit/tooltip_qol_added_lines_layout_test.lua
-- Run: lua tests/unit/tooltip_qol_added_lines_layout_test.lua

local function readFile(path)
    local fh = assert(io.open(path, "rb"), "failed to open " .. path)
    local data = fh:read("*a")
    fh:close()
    return data
end

local source = readFile("QUI_QoL/qol/tooltip.lua")

assert(source:find("local function AddTooltipInfoLine", 1, true),
    "tooltip QoL additions should use a shared left-aligned wrapped line helper")

local forbiddenDoubleLines = {
    'tooltip:AddDoubleLine(label, string.format("%.1f", itemLevel)',
    'tooltip:AddDoubleLine("Target:", targetInfo.name',
    'tooltip:AddDoubleLine("Mount:", mountName',
    'tooltip:AddDoubleLine("M+ Rating:", string.format("%.1f", rating)',
    'tooltip:AddDoubleLine("Spell ID:", tostring(spellID)',
    'tooltip:AddDoubleLine("Icon ID:", tostring(iconID)',
    'tooltip:AddDoubleLine("Item ID:", tostring(itemID)',
}

for _, needle in ipairs(forbiddenDoubleLines) do
    assert(not source:find(needle, 1, true),
        "QUI-added tooltip info should not use right-column AddDoubleLine layout: " .. needle)
end

local requiredInfoLines = {
    'AddTooltipInfoLine(tooltip, label, string.format("%.1f", itemLevel)',
    'AddTooltipInfoLine(tooltip, ns.L["Target"], targetInfo.name',
    'AddTooltipInfoLine(tooltip, ns.L["Mount"], mountName',
    'AddTooltipInfoLine(tooltip, ns.L["M+ Rating"], string.format("%.1f", rating)',
    'AddTooltipInfoLine(tooltip, ns.L["Spell ID"], tostring(spellID)',
    'AddTooltipInfoLine(tooltip, ns.L["Icon ID"], tostring(iconID)',
    'AddTooltipInfoLine(tooltip, ns.L["Item ID"], tostring(itemID)',
}

for _, needle in ipairs(requiredInfoLines) do
    assert(source:find(needle, 1, true),
        "expected left-aligned wrapped info line call missing: " .. needle)
end

local forbiddenProviderName = string.char(82, 97, 105, 100, 101, 114, 73, 79)
assert(not source:find(forbiddenProviderName, 1, true),
    "tooltip source must not hardcode third-party addon names")

local ratingStart = assert(source:find("local function GetPlayerMythicRating", 1, true),
    "rating resolver should exist")
local ratingEnd = assert(source:find("local function AddUnitTooltipInfoToTooltip", ratingStart, true),
    "rating resolver should remain bounded before unit info handling")
local ratingBody = source:sub(ratingStart, ratingEnd)
local providerLookup = ratingBody:find("rawget(_G, string.char(82, 97, 105, 100, 101, 114, 73, 79))", 1, true)
local nativeLookup = ratingBody:find("C_PlayerInfo.GetPlayerMythicPlusRatingSummary", 1, true)
assert(providerLookup,
    "rating resolver should restore external score provider compatibility")
assert(nativeLookup,
    "rating resolver should keep the native client rating fallback")
assert(providerLookup < nativeLookup,
    "external score provider should be preferred before native client rating fallback")

assert(source:find("local function IsInternalEmbeddedItemTooltipFrame(tooltip)", 1, true),
    "tooltip QoL must identify Blizzard embedded item reward tooltip frames")

local idProcessStart = assert(source:find("local function ShouldProcessTooltipIDs", 1, true),
    "tooltip ID processing gate should exist")
local idProcessEnd = assert(source:find("local function ResolveSpellIDFromTooltipData", idProcessStart, true),
    "tooltip ID processing gate should remain bounded before ID resolvers")
local idProcessBody = source:sub(idProcessStart, idProcessEnd)
assert(idProcessBody:find("IsInternalEmbeddedItemTooltipFrame(tooltip)", 1, true),
    "tooltip ID injection must skip embedded quest reward item tooltips before Blizzard width sizing")

local extrasStart = assert(source:find("local function HandleUnitExtrasPost", 1, true),
    "unit extras post handler should exist")
local extrasEnd = assert(source:find("local function HandleUnitHealthPost", extrasStart, true),
    "unit extras post handler should remain bounded before health handling")
local extrasBody = source:sub(extrasStart, extrasEnd)

local immediateExtras = extrasBody:find("AddUnitTooltipInfoToTooltip(tooltip, unit, settings)", 1, true)
local deferredExtras = extrasBody:find("ScheduleDeferredUnitInfo(tooltip, unit)", 1, true)
assert(immediateExtras,
    "unit tooltip extras should try cheap data enrichment during TooltipDataProcessor before deferring")
assert(deferredExtras,
    "unit tooltip extras should keep deferred enrichment for async/late data")
assert(immediateExtras < deferredExtras,
    "immediate unit enrichment should run before deferred enrichment is scheduled")

local function runHideFadeSelfFocusRegression()
    local createdFrames = {}
    local now = 0
    local mouseFocus
    local unitExists = {}

    local function makeFrame(name)
        local frame = {
            name = name,
            shown = true,
            alpha = 1,
            scripts = {},
            events = {},
            parent = nil,
        }

        function frame:GetName()
            return self.name
        end

        function frame:GetParent()
            return self.parent
        end

        function frame:RegisterEvent(event)
            self.events[event] = true
        end

        function frame:SetScript(scriptName, handler)
            self.scripts[scriptName] = handler
        end

        function frame:HookScript(scriptName, handler)
            self.hooks = self.hooks or {}
            self.hooks[scriptName] = handler
        end

        function frame:IsShown()
            return self.shown
        end

        function frame:IsVisible()
            return self.shown
        end

        function frame:Show()
            self.shown = true
        end

        function frame:Hide()
            self.shown = false
        end

        function frame:SetAlpha(alpha)
            self.alpha = alpha
        end

        function frame:GetAlpha()
            return self.alpha
        end

        function frame:SetOwner(owner)
            self.owner = owner
        end

        function frame:GetOwner()
            return self.owner
        end

        function frame:GetUnit()
            return nil, self.unit
        end

        function frame:GetNumChildren()
            return 0
        end

        function frame:GetChildren()
            return nil
        end

        function frame:IsForbidden()
            return false
        end

        function frame:SetSize(width, height)
            self.width = width
            self.height = height
        end

        function frame:SetPoint(point, relativeTo, relativePoint, x, y)
            self.point = { point, relativeTo, relativePoint, x, y }
        end

        function frame:SetClampedToScreen(value)
            self.clamped = value
        end

        function frame:ClearAllPoints()
            self.point = nil
        end

        function frame:GetEffectiveScale()
            return 1
        end

        createdFrames[#createdFrames + 1] = frame
        return frame
    end

    _G.UIParent = makeFrame("UIParent")
    _G.WorldFrame = makeFrame("WorldFrame")
    _G.GameTooltip = makeFrame("GameTooltip")
    GameTooltip.owner = UIParent

    _G.CreateFrame = function(_, name, parent)
        local frame = makeFrame(name or ("Frame" .. tostring(#createdFrames + 1)))
        frame.parent = parent
        return frame
    end

    _G.GetTime = function()
        return now
    end

    _G.GetMouseFoci = function()
        return { mouseFocus }
    end

    _G.GetCursorPosition = function()
        return 100, 100
    end

    _G.InCombatLockdown = function()
        return false
    end

    _G.IsShiftKeyDown = function() return false end
    _G.IsControlKeyDown = function() return false end
    _G.IsAltKeyDown = function() return false end
    _G.UnitExists = function(unit) return unitExists[unit] == true end
    _G.UnitGUID = function(unit) return unitExists[unit] and "Player-1-00000001" or nil end
    _G.UnitIsPlayer = function(unit) return unitExists[unit] == true end
    _G.UnitClass = function() return "Warrior", "WARRIOR" end
    _G.RAID_CLASS_COLORS = { WARRIOR = { r = 0.78, g = 0.61, b = 0.43 } }
    _G.GetActionInfo = function() return nil end
    _G.hooksecurefunc = function() end
    _G.wipe = function(tbl)
        for key in pairs(tbl) do
            tbl[key] = nil
        end
    end
    _G.issecretvalue = function() return false end
    _G.TooltipDataProcessor = {
        AddTooltipPostCall = function() end,
    }
    _G.Enum = {
        TooltipDataType = {
            Unit = 1,
            Spell = 2,
            Item = 3,
            UnitAura = 4,
            Aura = 4,
        },
    }

    local settings = {
        enabled = true,
        hideDelay = 0.3,
        visibility = {},
    }

    local testNS = {
        Helpers = {
            CreateStateTable = function()
                return setmetatable({}, { __mode = "k" })
            end,
            GetCore = function()
                return { uiscale = 1 }
            end,
            GetModuleDB = function(moduleName)
                assert(moduleName == "tooltip", "unexpected module db request")
                return settings
            end,
            IsSecretValue = function() return false end,
            SafeToNumber = function(value, fallback)
                local number = tonumber(value)
                if number == nil then return fallback end
                return number
            end,
            SafeCompare = function(left, right)
                return left == right
            end,
        },
        L = setmetatable({}, {
            __index = function(_, key) return key end,
        }),
    }

    assert(loadfile("QUI_QoL/qol/tooltip_provider.lua"))("QUI", testNS)
    assert(loadfile("QUI_QoL/qol/tooltip.lua"))("QUI", testNS)
    testNS.TooltipProvider:InitializeEngine()

    local visibilityWatcher
    for _, frame in ipairs(createdFrames) do
        if frame.scripts.OnUpdate then
            visibilityWatcher = frame
        end
    end
    assert(visibilityWatcher, "tooltip visibility watcher should be installed")

    local function tick(elapsed)
        now = now + elapsed
        visibilityWatcher.scripts.OnUpdate(visibilityWatcher, elapsed)
    end

    mouseFocus = WorldFrame
    GameTooltip.unit = "mouseover"
    unitExists.mouseover = true
    tick(0.06)
    assert(GameTooltip.alpha == 1, "visible unit tooltip should remain fully opaque")

    GameTooltip.unit = nil
    unitExists.mouseover = false
    tick(0.06)
    local alphaAfterFadeStart = GameTooltip.alpha
    assert(alphaAfterFadeStart > 0 and alphaAfterFadeStart < 1,
        "unit tooltip should begin fading once mouseover clears")

    mouseFocus = GameTooltip
    tick(0.06)
    assert(GameTooltip.alpha < alphaAfterFadeStart,
        "tooltip self-focus during fade-out must be ignored so alpha keeps decreasing")
    assert(GameTooltip:IsShown(), "tooltip should remain shown until the fade completes")
end

runHideFadeSelfFocusRegression()

print("tooltip_qol_added_lines_layout_test.lua: ok")
