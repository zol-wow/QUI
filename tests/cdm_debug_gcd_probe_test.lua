-- tests/cdm_debug_gcd_probe_test.lua
-- Run: lua tests/cdm_debug_gcd_probe_test.lua

SlashCmdList = {}
UIParent = {}

function strtrim(s)
    return (s or ""):gsub("^%s+", ""):gsub("%s+$", "")
end

function CreateFrame()
    return {
        SetSize = function() end,
        SetPoint = function() end,
        SetFrameStrata = function() end,
        EnableMouse = function() end,
        SetMovable = function() end,
        RegisterForDrag = function() end,
        SetScript = function() end,
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
    _showingGCDSwipe = true,
    _showingRealCooldownSwipe = nil,
    _hasRealCooldownActive = false,
    _lastDurObjKey = "gcd-only:12345",
    _resolvedCooldownMode = "gcd-only",
    _spellEntry = {
        name = "Debug Spell",
        id = 12345,
        spellID = 12345,
        viewerType = "essential",
        kind = "cooldown",
        type = "spell",
    },
    Cooldown = {
        _quiIntendedDrawSwipe = true,
        _quiIntendedDrawEdge = false,
        _quiIntendedSwipeColor = { 0, 0, 0, 0.8 },
        GetDrawSwipe = function() return true end,
        GetDrawEdge = function() return false end,
    },
    IsShown = function() return true end,
}

local ns = {
    CDMIcons = {
        IsRuntimeEnabled = function() return true end,
        ResolveIconDurationObject = function()
            return { token = "gcd" }, "gcd-only", 12345
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
            return { isActive = true, isOnGCD = true }
        end,
        QuerySpellCooldownDuration = function(_, ignoreGCD)
            return ignoreGCD and { token = "real" } or { token = "gcd" }
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

SlashCmdList["CDMGCD"]("Debug Spell")

print = originalPrint

local output = table.concat(lines, "\n")
assert(output:find("settings", 1, true), "/cdmgcd should print swipe settings")
assert(output:find("api", 1, true), "/cdmgcd should print cooldown API state")
assert(output:find("resolver", 1, true), "/cdmgcd should print resolver output")
assert(output:find("resolver mode=gcd%-only"), "/cdmgcd should preserve resolver mode return value")
assert(output:find("icon", 1, true), "/cdmgcd should print icon flags")
assert(output:find("cooldown", 1, true), "/cdmgcd should print cooldown frame draw state")

originalPrint("OK: cdm_debug_gcd_probe_test")
