-- tests/unit/groupframes_health_text_secret_sink_test.lua
-- Run: lua tests/unit/groupframes_health_text_secret_sink_test.lua
--
-- UnitHealth and UnitHealthMissing can return secret values. AbbreviateNumbers is
-- SecretArguments="AllowedWhenTainted", so it accepts a secret or plain value and
-- returns a string; absolute/both pass that result straight into the font string
-- (SetText / SetFormattedText) and never compare it in Lua (comparing a secret
-- throws). This matches the reference unit frames, which abbreviate UnitHealth
-- directly with no secret guard. Deficit keeps its zero-suppressing path and a raw
-- secret forward. The invariant: a secret may flow THROUGH AbbreviateNumbers into
-- the C-side sink, but is never bound to a compared local.

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
        -- AbbreviateNumbers is AllowedWhenTainted: it must accept a secret value
        -- without erroring, and returns a string (here a deterministic marker).
        AbbreviateNumbers = function(value)
            abbrCalls[#abbrCalls + 1] = { value = value, secret = issecretvalue(value) }
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

-- absolute + secret: secret flows through AbbreviateNumbers into SetText
do
    local calls, abbrCalls = render("absolute", secretHealth, 2500)
    assert(#abbrCalls == 1 and abbrCalls[1].secret,
        "absolute secret should be abbreviated (AbbreviateNumbers accepts secrets)")
    assert(calls[#calls].method == "SetText", "absolute should forward into the SetText sink")
    assert(calls[#calls][1] == "abbr:<secret>", "absolute secret should render the abbreviated result")
end

-- both + secret: abbreviated secret + percent through SetFormattedText
do
    local calls, abbrCalls = render("both", secretHealth, 2500)
    assert(#abbrCalls == 1 and abbrCalls[1].secret,
        "both secret should be abbreviated through AbbreviateNumbers")
    assert(calls[#calls].method == "SetFormattedText", "both should use the formatted text sink")
    assert(calls[#calls][1] == "%s | %.0f%%", "both should preserve the combined format")
    assert(calls[#calls][2] == "abbr:<secret>", "both secret should forward the abbreviated result")
    assert(calls[#calls][3] == 37, "both should keep the percent argument")
end

-- deficit + secret: raw forward (deficit retains its zero-suppressing structure)
do
    local calls, abbrCalls = render("deficit", 10000, secretMissing)
    assert(#abbrCalls == 0, "deficit secret should not abbreviate (raw forward path)")
    assert(calls[#calls].method == "SetFormattedText", "deficit secret should use formatted text sink")
    assert(calls[#calls][1] == "-%s", "deficit secret should use C-side prefix formatting")
    assert(calls[#calls][2] == secretMissing, "deficit secret should be forwarded raw")
end

-- absolute + non-secret: abbreviated normally
do
    local calls, abbrCalls = render("absolute", 12345, 2500)
    assert(#abbrCalls == 1 and abbrCalls[1].value == 12345 and not abbrCalls[1].secret,
        "absolute non-secret should abbreviate the raw value")
    assert(calls[#calls].method == "SetText", "absolute non-secret should use SetText")
    assert(calls[#calls][1] == "abbr:12345", "absolute non-secret should render abbreviated value")
end

print("OK: groupframes_health_text_secret_sink_test")
