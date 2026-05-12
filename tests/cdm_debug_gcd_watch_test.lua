-- tests/cdm_debug_gcd_watch_test.lua
-- Run: lua tests/cdm_debug_gcd_watch_test.lua

SlashCmdList = {}
UIParent = {}

local now = 100
function GetTime()
    return now
end

function strtrim(s)
    return (s or ""):gsub("^%s+", ""):gsub("%s+$", "")
end

local watchFrame
function CreateFrame()
    local frame = {
        SetSize = function() end,
        SetPoint = function() end,
        SetFrameStrata = function() end,
        EnableMouse = function() end,
        SetMovable = function() end,
        RegisterForDrag = function() end,
        StartMoving = function() end,
        StopMovingOrSizing = function() end,
        SetAllPoints = function() end,
        SetColorTexture = function() end,
        SetText = function() end,
        SetMultiLine = function() end,
        SetMaxLetters = function() end,
        SetFontObject = function() end,
        SetWidth = function() end,
        SetAutoFocus = function() end,
        ClearFocus = function() end,
        SetScrollChild = function() end,
        GetVerticalScrollRange = function() return 0 end,
        SetVerticalScroll = function() end,
        CreateTexture = function() return {} end,
        CreateFontString = function() return {} end,
    }
    function frame:SetScript(scriptType, handler)
        if scriptType == "OnUpdate" then
            self.onUpdate = handler
        end
    end
    watchFrame = frame
    return frame
end

local lines = {}
local originalPrint = print
print = function(...)
    local parts = {}
    for i = 1, select("#", ...) do
        parts[#parts + 1] = tostring(select(i, ...))
    end
    lines[#lines + 1] = table.concat(parts, " ")
end

local icon = {
    _runtimeSpellID = 12345,
    _showingGCDSwipe = false,
    _showingRealCooldownSwipe = nil,
    _hasRealCooldownActive = false,
    _lastDurObjKey = "none:12345",
    _resolvedCooldownMode = "none",
    _spellEntry = {
        name = "Debug Spell",
        id = 12345,
        spellID = 12345,
        viewerType = "essential",
        kind = "cooldown",
        type = "spell",
    },
    Cooldown = {
        _quiIntendedDrawSwipe = false,
        _quiIntendedDrawEdge = false,
        GetDrawSwipe = function() return false end,
        GetDrawEdge = function() return false end,
    },
    IsShown = function() return true end,
}

local queryCount = 0
local ns = {
    Helpers = {
        IsSecretValue = function() return false end,
    },
    CDMIcons = {
        IsRuntimeEnabled = function() return true end,
        ResolveIconDurationObject = function()
            if queryCount >= 2 then
                icon._showingGCDSwipe = true
                icon._resolvedCooldownMode = "gcd-only"
                icon.Cooldown._quiIntendedDrawSwipe = true
                return { token = "gcd" }, "gcd-only", 12345
            end
            return nil, "none", 12345
        end,
        GetCooldownInfoField = function(info, key)
            return info and info[key]
        end,
        IsGCDSwipeEnabled = function() return true end,
    },
    CDMIconFactory = {
        _iconPools = {
            essential = { icon },
        },
    },
    CDMSources = {
        QuerySpellCooldown = function()
            queryCount = queryCount + 1
            return { isActive = queryCount >= 2, isOnGCD = queryCount >= 2 }
        end,
        QuerySpellCooldownDuration = function(_, ignoreGCD)
            if queryCount >= 2 and not ignoreGCD then
                return { token = "gcd" }
            end
            return nil
        end,
        QuerySpellChargeDuration = function()
            return nil
        end,
        QuerySpellCharges = function()
            return nil
        end,
    },
    _OwnedSwipe = {
        GetSettings = function()
            return {
                showGCDSwipe = true,
                showCooldownSwipe = true,
            }
        end,
    },
}

assert(loadfile("QUI_Debug/cdm_debug.lua"))("QUI_Debug", ns)
assert(SlashCmdList["CDMGCD"], "/cdmgcd should be registered")

SlashCmdList["CDMGCD"]("Debug Spell 1")
assert(watchFrame and watchFrame.onUpdate, "/cdmgcd should start a timed watch")

now = 100.00
watchFrame:onUpdate(0)
now = 100.25
watchFrame:onUpdate(0.25)
now = 100.50
watchFrame:onUpdate(0.25)
now = 101.10
watchFrame:onUpdate(0.60)

print = originalPrint

local output = table.concat(lines, "\n")
assert(output:find("watching", 1, true), "/cdmgcd should announce watch mode")
assert(output:find("+0.", 1, true), "/cdmgcd should print timed samples")
assert(output:find("mode=gcd%-only"), "/cdmgcd watch should preserve resolver mode return value")
assert(output:find("ended", 1, true), "/cdmgcd should announce watch end")

originalPrint("OK: cdm_debug_gcd_watch_test")
