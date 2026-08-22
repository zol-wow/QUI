-- tests/unit/cdm_debug_gcd_probe_test.lua
-- Run: lua tests/unit/cdm_debug_gcd_probe_test.lua

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
    _runtimeSpellID = 1711,
    _showingGCDSwipe = true,
    _showingRealCooldownSwipe = nil,
    _hasRealCooldownActive = false,
    _lastDurObjKey = "gcd-only:12345",
    _resolvedCooldownMode = "gcd-only",
    _spellEntry = {
        name = "Debug Spell",
        id = 1711,
        viewerType = "essential",
        kind = "cooldown",
        type = "consumable",
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
    CDMCatalog = {
        GetConsumableCategoryItemID = function(categoryID)
            assert(categoryID == 1711)
            return 5512
        end,
    },
    CDMShared = {
        GetContainerDB = function()
            return { usabilityIndicator = true }
        end,
    },
    CDMIcons = {
        IsRuntimeEnabled = function() return true end,
        ResolveCooldownState = function()
            return {
                mode = "gcd-only",
                active = true,
                isActive = true,
                durObj = { token = "gcd" },
                sourceID = 6262,
                spellID = 6262,
            }
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
        QueryLastCategoryCooldownSource = function(categoryID)
            assert(categoryID == 1711)
            return 6262, nil
        end,
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
        QueryItemUsable = function(itemID)
            assert(itemID == 5512, "debug probe should query the consumable item identity")
            return true, false
        end,
        QueryItemCooldown = function(itemID)
            assert(itemID == 5512, "API summary should query the catalog fallback item")
            return 300, 60, 1
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
assert(SlashCmdList["QUI_CDMDEBUG"], "/cdmdebug should be registered")
assert(SlashCmdList["CDMGCD"] == nil, "legacy /cdmgcd command should not be registered")
ns.CDMIcons._eventTraceSpellID = 1711
assert(ns.CDMIcons.EventTraceShouldPrintFrameEvent("BAG_UPDATE_COOLDOWN") == true,
    "consumable categories should retain bag cooldown event traces")
local apiSummary = ns.CDMIcons.EventTraceAPISummary(1711)
assert(apiSummary:find("itemID=5512", 1, true),
    "API summary should report the catalog fallback item identity")

SlashCmdList["QUI_CDMDEBUG"]("spell Debug Spell")

print = originalPrint

local output = table.concat(lines, "\n")
assert(output:find("settings", 1, true), "/cdmdebug spell should print swipe settings")
assert(output:find("sid=6262", 1, true), "/cdmdebug spell should probe the category source spell")
assert(output:find("api", 1, true), "/cdmdebug spell should print cooldown API state")
assert(output:find("itemID=5512 itemUsable=true", 1, true), "/cdmdebug spell should print item usability state")
assert(output:find("resolver", 1, true), "/cdmdebug spell should print resolver output")
assert(output:find("resolver mode=gcd%-only"), "/cdmdebug spell should preserve resolver mode return value")
assert(output:find("icon", 1, true), "/cdmdebug spell should print icon flags")
assert(output:find("usabilitySetting=true", 1, true), "/cdmdebug spell should print the container usability setting")
assert(output:find("usabilityTinted=", 1, true), "/cdmdebug spell should print the applied usability tint state")
assert(output:find("cooldown", 1, true), "/cdmdebug spell should print cooldown frame draw state")

originalPrint("OK: cdm_debug_gcd_probe_test")
