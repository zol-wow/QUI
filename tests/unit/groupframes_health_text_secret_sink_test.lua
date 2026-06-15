-- tests/unit/groupframes_health_text_secret_sink_test.lua
-- Run: lua tests/unit/groupframes_health_text_secret_sink_test.lua
--
-- UnitHealth and UnitHealthMissing can return secret values. Health text modes
-- must forward those values to the font string C-side sink without abbreviating
-- or otherwise formatting the secret in Lua.

local env = dofile("tools/_addon_env.lua")

local function readAll(path)
    local f = assert(io.open(path, "rb"))
    local d = f:read("*a")
    f:close()
    return d:gsub("\r\n", "\n")
end

local source = readAll("QUI_GroupFrames/groupframes/groupframes.lua")
local startPos = assert(source:find("local function UpdateHealth%(frame%)"),
    "UpdateHealth should exist")
local endMarker = "\n---------------------------------------------------------------------------\n-- UPDATE: Power"
local endPos = assert(source:find(endMarker, startPos, true),
    "UpdateHealth should end before UPDATE: Power")
local updateHealthSource = source:sub(startPos, endPos - 1)

local function newFontString()
    local calls = {}
    local fs = {}

    function fs:SetText(text)
        calls[#calls + 1] = { method = "SetText", text }
    end

    function fs:SetFormattedText(fmt, ...)
        calls[#calls + 1] = { method = "SetFormattedText", fmt, ... }
    end

    function fs:SetTextColor(...) end
    function fs:Show() end
    function fs:Hide() end

    return fs, calls
end

local function loadUpdateHealth(ctx)
    local prelude = [[
local ns = ns
local COLORS = COLORS
local UnitExists = UnitExists
local UnitHealth = UnitHealth
local UnitHealthMissing = UnitHealthMissing
local GetHealthPct = GetHealthPct
local GetHealthSettings = GetHealthSettings
local GetHealthBarColor = GetHealthBarColor
local GetUnitLifeState = GetUnitLifeState
local UpdateDarkModeVisuals = UpdateDarkModeVisuals
local AbbreviateNumbers = AbbreviateNumbers
local AbbreviateLargeNumbers = AbbreviateLargeNumbers
local C_StringUtil = C_StringUtil
local IsSecretValue = IsSecretValue
]]
    local loader = assert(loadstring(prelude .. updateHealthSource .. "\nreturn UpdateHealth"))
    setfenv(loader, ctx)
    return loader()
end

local function render(style, healthValue, missingValue)
    local abbrCalls = {}
    local ctx = {
        ns = {},
        COLORS = {
            WHITE = { 1, 1, 1, 1 },
            OFFLINE = { 0.5, 0.5, 0.5, 1 },
            DEAD = { 0.5, 0.5, 0.5, 1 },
        },
        UnitExists = function() return true end,
        UnitHealth = function() return healthValue end,
        UnitHealthMissing = function() return missingValue end,
        GetHealthPct = function() return 37 end,
        GetHealthSettings = function()
            return {
                showHealthText = true,
                healthDisplayStyle = style,
                hideHealthPercentSymbol = false,
                healthTextColor = { 1, 1, 1, 1 },
            }
        end,
        GetHealthBarColor = function() return 0.1, 0.2, 0.3, 1 end,
        GetUnitLifeState = function() return true, false, false end,
        UpdateDarkModeVisuals = function() end,
        IsSecretValue = issecretvalue,
        C_StringUtil = nil,
        pcall = pcall,
        AbbreviateNumbers = function(value)
            if issecretvalue(value) then
                error("AbbreviateNumbers must not receive secret health", 2)
            end
            abbrCalls[#abbrCalls + 1] = value
            return "abbr:" .. tostring(value)
        end,
    }
    ctx.AbbreviateLargeNumbers = ctx.AbbreviateNumbers

    local UpdateHealth = loadUpdateHealth(ctx)
    local healthText, calls = newFontString()
    local frame = {
        unit = "raid1",
        healthText = healthText,
        healthBar = {
            SetValue = function() end,
            SetStatusBarColor = function() end,
        },
        SetAlpha = function() end,
    }

    local ok, err = pcall(UpdateHealth, frame)
    assert(ok, err)
    return calls, abbrCalls
end

local secretHealth = env.MakeSecret()
local secretMissing = env.MakeSecret()

do
    local calls, abbrCalls = render("absolute", secretHealth, 2500)
    assert(#abbrCalls == 0, "absolute mode must not abbreviate secret UnitHealth")
    assert(calls[#calls].method == "SetFormattedText", "absolute secret should use formatted text sink")
    assert(calls[#calls][1] == "%s", "absolute secret should use raw string format")
    assert(calls[#calls][2] == secretHealth, "absolute secret should be forwarded raw")
end

do
    local calls, abbrCalls = render("both", secretHealth, 2500)
    assert(#abbrCalls == 0, "both mode must not abbreviate secret UnitHealth")
    assert(calls[#calls].method == "SetFormattedText", "both secret should use formatted text sink")
    assert(calls[#calls][1] == "%s | %.0f%%", "both secret should preserve combined format")
    assert(calls[#calls][2] == secretHealth, "both mode should forward secret health raw")
    assert(calls[#calls][3] == 37, "both mode should keep percent argument")
end

do
    local calls, abbrCalls = render("deficit", 10000, secretMissing)
    assert(#abbrCalls == 0, "deficit mode must not abbreviate secret UnitHealthMissing")
    assert(calls[#calls].method == "SetFormattedText", "deficit secret should use formatted text sink")
    assert(calls[#calls][1] == "-%s", "deficit secret should use C-side prefix formatting")
    assert(calls[#calls][2] == secretMissing, "deficit secret should be forwarded raw")
end

do
    local calls, abbrCalls = render("absolute", 12345, 2500)
    assert(#abbrCalls == 1 and abbrCalls[1] == 12345,
        "absolute non-secret behavior should still abbreviate")
    assert(calls[#calls].method == "SetText", "absolute non-secret should keep SetText path")
    assert(calls[#calls][1] == "abbr:12345", "absolute non-secret should render abbreviated value")
end

print("OK: groupframes_health_text_secret_sink_test")
