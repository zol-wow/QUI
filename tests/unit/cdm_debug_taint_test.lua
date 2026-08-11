-- tests/unit/cdm_debug_taint_test.lua
-- Run: lua tests/unit/cdm_debug_taint_test.lua

SlashCmdList = {}
UIParent = {}

local printed = {}
local originalPrint = print
function print(...)
    local parts = {}
    for i = 1, select("#", ...) do
        parts[#parts + 1] = tostring(select(i, ...))
    end
    printed[#printed + 1] = table.concat(parts, " ")
end

function strtrim(s)
    return (s or ""):gsub("^%s+", ""):gsub("%s+$", "")
end

function InCombatLockdown()
    return false
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
    CDMIcons = {
        GetCacheStats = function()
            return {
                textureCycleCache = 2,
                barsDirty = false,
                updatePending = true,
            }
        end,
    },
    CDMIconFactory = { _iconPools = {} },
    CDMSpellData = {
        GetCacheStats = function()
            return {
                childMapDirty = false,
                childMapSize = 1,
                capturedAuraEntries = 2,
                capturedAuraUnits = 1,
                capturedAuraSpellKeys = 2,
                capturedAuraNameKeys = 3,
                learnedDirty = false,
                learnedSize = 4,
                tickAuraData = 5,
                tickAuraDuration = 6,
                tickAuraExpiration = 7,
                tickAuraApplication = 8,
                resolveIconMemo = 9,
                resolveAuraMemo = 10,
                totemSlotMap = 11,
            }
        end,
    },
    CDMBars = {
        GetCacheStats = function()
            return { activeBars = 12 }
        end,
    },
    CDMRuntimeStore = {
        GetStats = function()
            return { states = 13, version = 14 }
        end,
    },
    GetCDMFrameCacheStats = function()
        return { dirty = false, size = 15 }
    end,
}

local resetCalls = {}
ns.InvalidateCDMFrameCache = function() resetCalls.frame = true end
ns.CDMSpellData.InvalidateLearnedCache = function() resetCalls.learned = true end
ns.CDMSpellData.ClearChildCaches = function() resetCalls.children = true end
ns.CDMSpellData.CheckAllDormantSpells = function() resetCalls.dormant = true end
ns.CDMSpellData.ReconcileAllContainers = function() resetCalls.reconcile = true end
ns.CDMIcons.ClearTextureCycleCache = function() resetCalls.texture = true end
ns.CDMIcons.RequestFullUpdate = function() resetCalls.fullUpdate = true end
ns.CDMBars.ClearPerBarCaches = function() resetCalls.bars = true end
ns.CDMRuntimeStore.ClearAll = function() resetCalls.runtime = true end
_G.QUI_OnSpellDataChanged = function() resetCalls.spellDataChanged = true end
QUI = {
    SlashCommandOpen = function()
        resetCalls.delegated = true
    end,
}

assert(loadfile("QUI_Debug/cdm_debug.lua"))("QUI_Debug", ns)
assert(SlashCmdList["QUI_CDMDEBUG"], "/cdmdebug should be registered")
assert(SlashCmdList["QUI_CDMRAW"] == nil, "legacy /cdmraw command should not be registered")
assert(SlashCmdList["CDMEVENTS"] == nil, "legacy /cdmevents command should not be registered")

local Debug = ns.CDMDebug
assert(Debug and Debug.Taint, "CDMDebug.Taint should be exported")

SlashCmdList["QUI_CDMDEBUG"]("flags taint Sync")
assert(_G.QUI_CDM_TAINT_DEBUG == "Sync", "/cdmdebug flags taint <filter> should store a filter string")

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

SlashCmdList["QUI_CDMDEBUG"]("flags taint off")
assert(_G.QUI_CDM_TAINT_DEBUG == nil, "/cdmdebug flags taint off should clear the runtime flag")

SlashCmdList["QUI_CDMDEBUG"]("flags taint Sync")
SlashCmdList["QUI_CDMDEBUG"]("flags off")
assert(_G.QUI_CDM_TAINT_DEBUG == nil, "/cdmdebug flags off should clear taint runtime flag")

printed = {}
SlashCmdList["QUI_CDMDEBUG"]("cache status")
assert(not resetCalls.delegated, "/cdmdebug cache must not delegate to the removed /qui cdm_cache path")
local sawStatus = false
for _, line in ipairs(printed) do
    if line:find("[CDM-Cache]", 1, true) and line:find("status", 1, true) then
        sawStatus = true
        break
    end
end
assert(sawStatus, "/cdmdebug cache status should print direct cache status")

SlashCmdList["QUI_CDMDEBUG"]("cache reset")
assert(resetCalls.frame and resetCalls.learned and resetCalls.children
    and resetCalls.texture and resetCalls.bars and resetCalls.runtime
    and resetCalls.dormant and resetCalls.reconcile and resetCalls.spellDataChanged
    and resetCalls.fullUpdate, "/cdmdebug cache reset should directly reset CDM caches")
assert(not resetCalls.delegated, "/cdmdebug cache reset must not delegate to /qui")

print = originalPrint
print("OK: cdm_debug_taint_test")
