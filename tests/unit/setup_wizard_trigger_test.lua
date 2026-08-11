-- tests/unit/setup_wizard_trigger_test.lua
-- Run: lua tests/unit/setup_wizard_trigger_test.lua
--
-- Static contract for the setup-wizard trigger (plan 008):
--   * the old 4-line login lecture is gone from init.lua
--   * QUI:OnEnable carries the fresh-install auto-open (RunAfterFirstFrame,
--     re-checking completedAt at fire time) and the one-time legacy notice
--   * /qui install routes through EnsureOptionsLoaded to ns.QUI_SetupWizard
--   * core/main.lua samples rawget(_G, "QUIDB") BEFORE AceDB:New("QUIDB")
--     materializes the saved variable (order-sensitive fresh-install signal)
--   * defaults ship global.setupWizard with completedAt/noticeShown
--   * QUI_Options.toc loads wizard.lua

local function readAll(path)
    local fh = assert(io.open(path, "r"), "failed to open " .. path)
    local text = fh:read("*a")
    fh:close()
    return text
end

local initSrc = readAll("init.lua")
local mainSrc = readAll("core/main.lua")
local defaultsSrc = readAll("core/defaults.lua")
local tocSrc = readAll("QUI_Options/QUI_Options.toc")

local failures = {}
local function check(cond, msg)
    if not cond then failures[#failures + 1] = msg end
end

-- Lecture retired
check(not initSrc:find("QUI REMINDER", 1, true),
    "init.lua must no longer print the login lecture")
check(not initSrc:find("HIDDEN|r on mouseover", 1, true),
    "the stale mouseover-default lecture line must be gone")

-- Auto-open trigger shape
local onEnable = initSrc:match("function QUI:OnEnable%(%)(.-)\nend")
check(onEnable, "QUI:OnEnable should exist")
if onEnable then
    check(onEnable:find("setupWizard", 1, true), "OnEnable must consult db.global.setupWizard")
    check(onEnable:find("ns._freshInstall", 1, true), "OnEnable must branch on ns._freshInstall")
    check(onEnable:find("RunAfterFirstFrame", 1, true), "auto-open must defer via RunAfterFirstFrame")
    check(onEnable:find("if sw.completedAt then return end", 1, true),
        "the deferred auto-open must re-check completedAt at fire time")
    check(onEnable:find("noticeShown", 1, true), "legacy users get the one-time notice flag")
end

-- Slash routing
check(initSrc:find('input == "install"', 1, true), "/qui install clause must exist")
check(initSrc:find("EnsureOptionsLoaded", 1, true)
    and initSrc:find("ns.QUI_SetupWizard", 1, true),
    "install clause must load QUI_Options and open ns.QUI_SetupWizard")

-- Fresh-install sampling order in QUICore:OnInitialize
local samplePos = mainSrc:find('ns._freshInstall = rawget(_G, "QUIDB") == nil', 1, true)
local acedbPos = mainSrc:find('):New("QUIDB"', 1, true)
check(samplePos, "core/main.lua must sample the QUIDB fresh-install signal")
check(acedbPos, "core/main.lua must create the QUIDB AceDB store")
check(samplePos and acedbPos and samplePos < acedbPos,
    "fresh-install signal must be sampled BEFORE AceDB:New materializes QUIDB")

-- Defaults
check(defaultsSrc:find("setupWizard = {", 1, true)
    and defaultsSrc:find("completedAt = false", 1, true)
    and defaultsSrc:find("noticeShown = false", 1, true),
    "core/defaults.lua global section must ship setupWizard flags")

-- TOC
check(tocSrc:find("\nwizard.lua", 1, true), "QUI_Options.toc must load wizard.lua")

if #failures > 0 then
    for _, msg in ipairs(failures) do
        print("FAIL  " .. msg)
    end
    os.exit(1)
end

print("OK: setup_wizard_trigger")
