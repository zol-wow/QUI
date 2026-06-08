-- Run: lua tests/unit/keybind_text_layering_test.lua

local function noop() end

function wipe(tbl)
    for key in pairs(tbl) do
        tbl[key] = nil
    end
end

function issecretvalue()
    return false
end

function InCombatLockdown()
    return false
end

function GetTime()
    return 2
end

function GetSpecialization()
    return nil
end

function GetSpecializationInfo()
    return nil
end

function GetInventoryItemID()
    return nil
end

function GetActionInfo()
    return "macro", 1
end

function GetActionText()
    return "UseRank1002"
end

function GetMacroInfo(macroIndex)
    if macroIndex == 1 then
        return "UseRank1002", nil, "/use Rank 1002"
    end
    return nil
end

function GetMacroSpell()
    return nil
end

UIParent = {}
C_Item = {
    GetItemInfo = function(itemInfo)
        if itemInfo == 1002 then
            return "Rank 1002"
        end
        if itemInfo == "Rank 1002" then
            return "Rank 1002"
        end
        return "Item " .. tostring(itemInfo)
    end,
}
C_Spell = {
    GetSpellInfo = function()
        return nil
    end,
}
C_Timer = {
    After = noop,
}

local createdFrames = {}
local fontStrings = {}

local function NewFontString(parent, layer, sublevel)
    local fontString = {
        parent = parent,
        layer = layer,
        sublevel = sublevel,
        shown = false,
    }

    function fontString:GetParent()
        return self.parent
    end
    function fontString:SetShadowOffset() end
    function fontString:SetShadowColor() end
    function fontString:SetText(text)
        self.text = text
    end
    function fontString:GetText()
        return self.text
    end
    function fontString:Show()
        self.shown = true
    end
    function fontString:Hide()
        self.shown = false
    end
    function fontString:IsShown()
        return self.shown
    end
    function fontString:ClearAllPoints()
        self.point = nil
    end
    function fontString:SetPoint(...)
        self.point = { ... }
    end
    function fontString:SetFont(font, size, outline)
        self.font = font
        self.fontSize = size
        self.fontOutline = outline
    end
    function fontString:SetTextColor(r, g, b, a)
        self.textColor = { r, g, b, a }
    end

    fontStrings[#fontStrings + 1] = fontString
    return fontString
end

local function NewFrame(frameType, parent)
    local frame = {
        frameType = frameType,
        parent = parent,
        frameLevel = parent and parent.frameLevel or 1,
        frameStrata = parent and parent.frameStrata or "LOW",
        shown = true,
    }

    function frame:GetParent()
        return self.parent
    end
    function frame:SetAllPoints(target)
        self.allPoints = target or true
    end
    function frame:GetFrameLevel()
        return self.frameLevel
    end
    function frame:SetFrameLevel(level)
        self.frameLevel = level
    end
    function frame:GetFrameStrata()
        return self.frameStrata
    end
    function frame:SetFrameStrata(strata)
        self.frameStrata = strata
    end
    function frame:CreateFontString(_, layer, _, sublevel)
        return NewFontString(self, layer, sublevel)
    end
    function frame:RegisterEvent() end
    function frame:SetScript() end
    function frame:Show()
        self.shown = true
    end
    function frame:Hide()
        self.shown = false
    end
    function frame:IsShown()
        return self.shown
    end

    return frame
end

function CreateFrame(frameType, _, parent)
    local frame = NewFrame(frameType, parent)
    createdFrames[#createdFrames + 1] = frame
    return frame
end

local icon = NewFrame("Frame", nil)
icon.frameLevel = 10
icon._spellEntry = {
    type = "item",
    id = 1002,
    viewerType = "customQuality",
    _isCustomEntry = true,
}
icon.Cooldown = NewFrame("Cooldown", icon)
icon.Cooldown.frameLevel = 20
icon.TextOverlay = NewFrame("Frame", icon)
icon.TextOverlay.frameLevel = 30

_G.QUI_Bar1Button1 = {
    action = 1,
    HotKey = {
        GetText = function()
            return "F"
        end,
    },
    GetName = function()
        return "QUI_Bar1Button1"
    end,
    GetObjectType = function()
        return "CheckButton"
    end,
}

local container = {
    GetChildren = function()
        return icon
    end,
}
local viewer = {
    viewerFrame = container,
}

local core = {
    db = {
        profile = {
            keybindOverridesEnabledCDM = true,
            keybindOverridesEnabledTrackers = true,
            viewers = {},
            ncdm = {
                containers = {
                    customQuality = {
                        showKeybinds = true,
                    },
                },
            },
        },
        char = {
            keybindOverrides = {
                [0] = {},
            },
        },
    },
}

local addon = {
    QUICore = core,
    Helpers = {
        GetCore = function()
            return core
        end,
        CanAccessTable = function()
            return true
        end,
        CreateStateTable = function()
            return setmetatable({}, { __mode = "k" })
        end,
        GetGeneralFont = function()
            return "Fonts\\FRIZQT__.TTF"
        end,
        GetGeneralFontOutline = function()
            return "OUTLINE"
        end,
    },
}

_G.QUI = addon
_G.QUI_GetCDMViewerFrame = function(viewerName)
    if viewerName == "customQuality" then
        return viewer
    end
    return nil
end

-- FormatKeybind now lives in core (core/utils.lua); in-game the core addon
-- loads before this LoadOnDemand module and sets ns.FormatKeybind on the shared
-- namespace. Mirror that ordering by grafting the real core function onto the
-- namespace (via a throwaway load) without disturbing this test's Helpers stubs.
do
    local coreNs = {}
    LibStub = function() return nil end
    assert(loadfile("core/utils.lua"))("QUI", coreNs)
    LibStub = nil
    addon.FormatKeybind = coreNs.FormatKeybind
end

assert(loadfile("QUI_QoL/utility/keybinds.lua"))("QUI", addon)

addon.Keybinds.UpdateViewer("customQuality")

local keybindLayer
for _, frame in ipairs(createdFrames) do
    if frame.parent == icon.TextOverlay and frame.allPoints == icon.TextOverlay then
        keybindLayer = frame
        break
    end
end

assert(keybindLayer, "CDM keybind text layer should be parented to the icon TextOverlay")
assert(fontStrings[#fontStrings] and fontStrings[#fontStrings].parent == keybindLayer,
    "CDM keybind text should be created on the TextOverlay child layer")
assert(fontStrings[#fontStrings].layer == "OVERLAY",
    "CDM keybind text should remain on the overlay draw layer")
assert(fontStrings[#fontStrings].text == "F",
    "CDM item keybind text should resolve through item macros on action buttons")

print("OK: keybind_text_layering_test")
