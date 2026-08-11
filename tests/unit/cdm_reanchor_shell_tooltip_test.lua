-- tests/unit/cdm_reanchor_shell_tooltip_test.lua
-- Run: lua tests/unit/cdm_reanchor_shell_tooltip_test.lua

local function noop() end

function InCombatLockdown() return false end

UIParent = {}
QUICore = {
    db = {
        profile = {
            tooltip = {
                anchorToCursor = false,
                hideInCombat = false,
            },
        },
    },
}

local function NewRegion()
    return {
        ClearAllPoints = noop,
        SetPoint = noop,
        SetColorTexture = noop,
        Show = noop,
        Hide = noop,
    }
end

function CreateFrame(frameType, name, parent)
    local frame = {
        frameType = frameType,
        name = name,
        parent = parent,
        shown = false,
        frameLevel = parent and parent.frameLevel and (parent.frameLevel + 1) or 1,
        frameStrata = parent and parent.frameStrata or "MEDIUM",
    }

    function frame:GetParent() return self.parent end
    function frame:SetParent(newParent) self.parent = newParent end
    function frame:SetAllPoints(target) self.allPoints = target or true end
    function frame:ClearAllPoints() self.points = nil end
    function frame:SetPoint(...) self.points = { ... } end
    function frame:SetSize(width, height) self.width, self.height = width, height end
    function frame:EnableMouse(value) self.mouseEnabled = value ~= false end
    function frame:SetMouseClickEnabled(value) self.mouseClickEnabled = value == true end
    function frame:SetMouseMotionEnabled(value) self.mouseMotionEnabled = value == true end
    function frame:SetScript(scriptName, handler) self.scripts = self.scripts or {}; self.scripts[scriptName] = handler end
    function frame:GetScript(scriptName) return self.scripts and self.scripts[scriptName] end
    function frame:SetFrameLevel(level) self.frameLevel = level end
    function frame:GetFrameLevel() return self.frameLevel end
    function frame:SetFrameStrata(strata) self.frameStrata = strata end
    function frame:GetFrameStrata() return self.frameStrata end
    function frame:CreateTexture() return NewRegion() end
    function frame:Show() self.shown = true end
    function frame:Hide() self.shown = false end

    return frame
end

local tooltipContext
local ns = {
    Addon = QUICore,
    Helpers = {
        GetGeneralFont = function() return "Fonts\\FRIZQT__.TTF" end,
        GetGeneralFontOutline = function() return "" end,
    },
    CDMSources = {},
    CDMResolvers = {
        GetEntryTexture = function() return 134400 end,
        GetSpellTexture = function() return 134400 end,
    },
    CDMSpellData = {
        ResolveDisplaySpellID = function(_, entry)
            return entry and (entry.spellID or entry.overrideSpellID or entry.id)
        end,
    },
    TooltipProvider = {
        IsOwnerFadedOut = function() return false end,
        ShouldShowTooltip = function(_, context)
            tooltipContext = context
            return true
        end,
    },
    L = setmetatable({}, { __index = function(_, key) return key end }),
}

GameTooltip = {
    IsForbidden = function() return false end,
    SetOwner = function(self, owner, anchor)
        self.owner = owner
        self.anchor = anchor
    end,
    SetSpellByID = function(self, spellID) self.spellID = spellID end,
    Show = function(self) self.shown = true end,
    Hide = function(self) self.hidden = true end,
    AddLine = noop,
}

local loadChunk = dofile("tests/helpers/load_cdm_consolidated_chunk.lua")
loadChunk("QUI_CDM/cdm/cdm_icon_factory.lua", "cdm_icon_factory.lua")("QUI", ns)
loadChunk("QUI_CDM/cdm/cdm_reanchor_realenv.lua", "cdm_reanchor_realenv.lua")("QUI", ns)

assert(type(ns.CDMIconFactory.ShowEntryTooltip) == "function",
    "CDMIconFactory.ShowEntryTooltip must be shared by owned and reanchored CDM icons")

local container = CreateFrame("Frame", "QUI_CDM_Essential", UIParent)
local env = ns.CDMReanchorRealEnv.BuildEnv({
    CDMContainers = {
        GetContainer = function() return container end,
    },
    core = {
        Pixels = function(_, value) return value end,
        PixelRound = function(_, value) return value end,
    },
})

local entry = { id = 12345, spellID = 12345, viewerType = "essential" }
local live = CreateFrame("Frame", nil, container)
local shell = assert(env.positionClickSlot(container, live, entry, "essential", 0, 0, 40, 40),
    "positionClickSlot returns a hover click slot")

assert(shell._spellEntry == entry, "reanchored shell keeps the curated CDM entry for tooltip hover")
assert(shell._quiTooltipContext == "cdm" and shell.__quiTooltipContext == "cdm",
    "reanchored shell is explicitly stamped as CDM tooltip context")
assert(type(shell:GetScript("OnEnter")) == "function", "reanchored shell has tooltip OnEnter")
assert(type(shell:GetScript("OnLeave")) == "function", "reanchored shell has tooltip OnLeave")

shell:GetScript("OnEnter")(shell)
assert(tooltipContext == "cdm", "shell hover consults the CDM tooltip visibility context")
assert(GameTooltip.owner == shell and GameTooltip.anchor == "ANCHOR_BOTTOM",
    "shell hover anchors GameTooltip to the reanchored shell")
assert(GameTooltip.spellID == 12345 and GameTooltip.shown == true,
    "shell hover shows the spell tooltip")

local hover = assert(shell._quiCdmHoverOverlay, "reanchored shell has a hover-only overlay above the live frame")
assert(hover.mouseEnabled == true and hover.mouseMotionEnabled == true and hover.mouseClickEnabled == false,
    "hover overlay receives motion without taking click ownership")
assert(hover:GetFrameLevel() > shell:GetFrameLevel(),
    "hover overlay is raised above the shell")

GameTooltip.owner, GameTooltip.spellID, GameTooltip.shown = nil, nil, false
hover:GetScript("OnEnter")(hover)
assert(GameTooltip.owner == shell and GameTooltip.spellID == 12345 and GameTooltip.shown == true,
    "hover overlay forwards tooltip hover to the shell")

print("OK: cdm_reanchor_shell_tooltip_test")
