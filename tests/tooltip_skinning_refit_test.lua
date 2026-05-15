-- tests/tooltip_skinning_refit_test.lua
-- Run: lua tests/tooltip_skinning_refit_test.lua

local createdFrames = {}

local function makeFrame(label)
    local frame = {
        label = label,
        shown = true,
        points = {},
    }

    function frame:IsShown()
        return self.shown
    end

    function frame:Show()
        self.shown = true
    end

    function frame:Hide()
        self.shown = false
    end

    function frame:ClearAllPoints()
        self.points = {}
    end

    function frame:SetPoint(point, relativeTo, relativePoint, x, y)
        self.points[#self.points + 1] = {
            point = point,
            relativeTo = relativeTo,
            relativePoint = relativePoint,
            x = x or 0,
            y = y or 0,
        }
    end

    function frame:SetHeight(height)
        self.height = height
    end

    function frame:GetParent()
        return self.parent
    end

    function frame:RegisterEvent(event)
        self.events = self.events or {}
        self.events[event] = true
    end

    function frame:SetScript(scriptName, handler)
        self.scripts = self.scripts or {}
        self.scripts[scriptName] = handler
    end

    createdFrames[#createdFrames + 1] = frame
    return frame
end

local function makeLine(text, right, bottom, left, wrappedWidth)
    local line = {
        text = text,
        right = right or 100,
        bottom = bottom or 0,
        left = left or 0,
        wrappedWidth = wrappedWidth,
        shown = true,
    }

    function line:IsShown()
        return self.shown
    end

    function line:GetText()
        return self.text
    end

    function line:GetRight()
        return self.right
    end

    function line:GetLeft()
        return self.left
    end

    function line:GetWrappedWidth()
        return self.wrappedWidth
    end

    function line:GetBottom()
        return self.bottom
    end

    function line:IsObjectType(kind)
        return kind == "FontString"
    end

    return line
end

local function findPoint(frame, point)
    for i = 1, #frame.points do
        if frame.points[i].point == point then
            return frame.points[i]
        end
    end
    return nil
end

local function getUpvalue(fn, expectedName)
    local index = 1
    while true do
        local name, value = debug.getupvalue(fn, index)
        if not name then
            error("missing upvalue: " .. expectedName)
        end
        if name == expectedName then
            return value
        end
        index = index + 1
    end
end

local function loadTooltipSkinning()
    _G.UIParent = makeFrame("UIParent")
    _G.WorldFrame = makeFrame("WorldFrame")
    _G.GameTooltip = makeFrame("GameTooltip")
    _G.InCombatLockdown = function() return false end
    _G.issecretvalue = function() return false end
    _G.UnitClass = function() return "Warrior", "WARRIOR" end
    _G.RAID_CLASS_COLORS = { WARRIOR = { r = 0.78, g = 0.61, b = 0.43 } }
    _G.STANDARD_TEXT_FONT = "Fonts\\FRIZQT__.TTF"
    _G.CreateFrame = function()
        return makeFrame("created")
    end
    _G.hooksecurefunc = function() end
    _G.wipe = function(tbl)
        for key in pairs(tbl) do
            tbl[key] = nil
        end
    end
    _G.C_Timer = { After = function(_, callback) callback() end }

    local core = {
        db = {
            profile = {
                tooltip = {
                    enabled = true,
                    skinTooltips = true,
                },
            },
        },
    }

    local ns = {
        Helpers = {
            GetCore = function() return core end,
            CreateStateTable = function()
                return setmetatable({}, { __mode = "k" })
            end,
            GetSkinBorderColor = function() return 1, 1, 1, 1 end,
            GetSkinBgColor = function() return 0, 0, 0, 1 end,
            IsSecretValue = function() return false end,
        },
        UIKit = {
            CreateBackground = function()
                return { SetVertexColor = function() end }
            end,
            CreateBorderLines = function() end,
            UpdateBorderLines = function() end,
        },
    }

    assert(loadfile("modules/skinning/system/tooltips.lua"))("QUI", ns)
    local refit = assert(ns.QUI_RefitTooltipChromeToContent, "refit function should be exported")
    local styleFrames = getUpvalue(refit, "styleFrames")
    return refit, styleFrames
end

local refit, styleFrames = loadTooltipSkinning()

local function test_refit_does_not_extend_to_left_line_text_width()
    local owner = makeFrame("owner")
    local tooltip = {
        owner = owner,
        count = 2,
        right = 100,
        leftLines = {},
        rightLines = {},
    }
    tooltip.leftLines[1] = makeLine("Header", 90, 90, 10, 80)
    tooltip.leftLines[2] = makeLine("Long dynamically appended line", 230, 80, 10, 220)
    tooltip.rightLines[1] = makeLine("", 100, 90)
    tooltip.rightLines[2] = makeLine("", 100, 80)

    function tooltip:NumLines()
        return self.count
    end

    function tooltip:GetLeftLine(index)
        return self.leftLines[index]
    end

    function tooltip:GetRightLine(index)
        return self.rightLines[index]
    end

    function tooltip:GetRight()
        return self.right
    end

    function tooltip:GetOwner()
        return self.owner
    end

    function tooltip:GetUnit()
        return nil
    end

    function tooltip:IsShown()
        return true
    end

    function tooltip:IsForbidden()
        return false
    end

    local chrome = makeFrame("chrome")
    styleFrames[tooltip] = chrome

    refit(tooltip)
    local topRight = assert(findPoint(chrome, "TOPRIGHT"), "chrome should have a top-right point")
    assert(topRight.x == 0,
        "left-side text should stay governed by tooltip text layout, not chrome width expansion")
end

local function test_refit_uses_wrapped_width_for_left_lines()
    local owner = makeFrame("owner")
    local tooltip = {
        owner = owner,
        count = 2,
        right = 100,
        leftLines = {
            makeLine("Header", 90, 90, 10, 80),
            makeLine("Wrapped description", 2400, 80, 10, 80),
        },
        rightLines = {
            makeLine("", 100, 90),
            makeLine("", 100, 80),
        },
    }

    function tooltip:NumLines()
        return self.count
    end

    function tooltip:GetLeftLine(index)
        return self.leftLines[index]
    end

    function tooltip:GetRightLine(index)
        return self.rightLines[index]
    end

    function tooltip:GetRight()
        return self.right
    end

    function tooltip:GetOwner()
        return self.owner
    end

    function tooltip:GetUnit()
        return nil
    end

    function tooltip:IsShown()
        return true
    end

    function tooltip:IsForbidden()
        return false
    end

    local chrome = makeFrame("chrome")
    styleFrames[tooltip] = chrome

    refit(tooltip)
    local topRight = assert(findPoint(chrome, "TOPRIGHT"), "chrome should have a top-right point")
    assert(topRight.x == 0,
        "refit should not trust natural unwrapped right bounds for wrapped left-side description text")
end

local function test_refit_extends_right_side_double_line_width()
    local owner = makeFrame("owner")
    local tooltip = {
        owner = owner,
        count = 2,
        right = 100,
        leftLines = {
            makeLine("Header", 90, 90, 10, 80),
            makeLine("Value", 90, 80, 10, 80),
        },
        rightLines = {
            makeLine("", 100, 90),
            makeLine("Very Long Dynamic Value", 150, 80),
        },
    }

    function tooltip:NumLines()
        return self.count
    end

    function tooltip:GetLeftLine(index)
        return self.leftLines[index]
    end

    function tooltip:GetRightLine(index)
        return self.rightLines[index]
    end

    function tooltip:GetRight()
        return self.right
    end

    function tooltip:GetOwner()
        return self.owner
    end

    function tooltip:GetUnit()
        return nil
    end

    function tooltip:IsShown()
        return true
    end

    function tooltip:IsForbidden()
        return false
    end

    local chrome = makeFrame("chrome")
    styleFrames[tooltip] = chrome

    refit(tooltip)
    local topRight = assert(findPoint(chrome, "TOPRIGHT"), "chrome should have a top-right point")
    assert(topRight.x == 54, "refit should still extend to cover right-side double-line values")
end

test_refit_does_not_extend_to_left_line_text_width()
test_refit_uses_wrapped_width_for_left_lines()
test_refit_extends_right_side_double_line_width()

print("tooltip_skinning_refit_test.lua: ok")
