-- tests/cdm_debug_taint_test.lua
-- Run: lua tests/cdm_debug_taint_test.lua

SlashCmdList = {}
UIParent = {}

function strtrim(s)
    return (s or ""):gsub("^%s+", ""):gsub("%s+$", "")
end

local lastEditBox

local function newFrame(frameType)
    local frame = {}
    function frame:SetSize() end
    function frame:SetPoint() end
    function frame:SetFrameStrata() end
    function frame:EnableMouse() end
    function frame:SetMovable() end
    function frame:RegisterForDrag() end
    function frame:SetScript() end
    function frame:StartMoving() end
    function frame:StopMovingOrSizing() end
    function frame:SetAllPoints() end
    function frame:SetColorTexture() end
    function frame:SetText(text) self.text = text end
    function frame:SetMultiLine() end
    function frame:SetMaxLetters() end
    function frame:SetFontObject() end
    function frame:SetWidth() end
    function frame:SetAutoFocus() end
    function frame:ClearFocus() end
    function frame:SetScrollChild(child) self.child = child end
    function frame:GetVerticalScrollRange() return 0 end
    function frame:SetVerticalScroll() end
    function frame:CreateTexture() return newFrame("Texture") end
    function frame:CreateFontString() return newFrame("FontString") end

    if frameType == "EditBox" then
        lastEditBox = frame
    end

    return frame
end

function CreateFrame(frameType)
    return newFrame(frameType)
end

C_Timer = {
    After = function(_, callback)
        callback()
    end,
}

local ns = {
    CDMIcons = {},
    CDMIconFactory = { _iconPools = {} },
    CDMBlizzMirror = {
        GetRawCooldownViewerDebugLines = function()
            return {
                "[CDM raw] summary categorySetEntries=2 viewerChildren=2 mirrorInfoEntries=2",
            }
        end,
    },
}

assert(loadfile("modules/cdm/cdm_debug.lua"))("QUI", ns)

local Debug = ns.CDMDebug
assert(Debug and Debug.Taint, "CDMDebug.Taint should be exported")

SlashCmdList["QUI_CDMDEBUG"]("taint Sync")
assert(_G.QUI_CDM_TAINT_DEBUG == "Sync", "/cdmdebug taint <filter> should store a filter string")

Debug.Taint("hook.SetCooldown", "cdID", 1)
assert(lastEditBox == nil, "filtered taint messages should not create or update the frame")

Debug.Taint("Sync.in", "cdID", 73542, "durObj", nil)
assert(lastEditBox and lastEditBox.text:find("Sync.in", 1, true), "matching taint message should render")
local firstText = lastEditBox.text

Debug.Taint("hook.Clear", "cdID", 1)
assert(lastEditBox.text == firstText, "non-matching taint message should not change rendered text")

Debug.Taint("Sync.in", "cdID", 73542, "durObj", nil)
assert(lastEditBox.text:find("repeat=2:num", 1, true), "identical adjacent taint messages should coalesce")

_G.QUI_CDM_TAINT_DEBUG = true
_G.QUI_CDM_TAINT_FILTER = nil
Debug.Taint("hook.Clear", "cdID", 1)
assert(lastEditBox.text:find("hook.Clear", 1, true), "global taint debug should render unfiltered labels")

assert(SlashCmdList["QUI_CDMRAW"], "/cdmraw should be registered")
SlashCmdList["QUI_CDMRAW"]("")
assert(lastEditBox.text:find("categorySetEntries=2", 1, true), "/cdmraw should render raw lines in the debug EditBox")

print("OK: cdm_debug_taint_test")
