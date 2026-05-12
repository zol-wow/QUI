-- tests/cdm_fast_visual_refresh_contract_test.lua
-- Run: lua tests/cdm_fast_visual_refresh_contract_test.lua

local function readAll(path)
    local file = assert(io.open(path, "rb"))
    local text = file:read("*a")
    file:close()
    return text
end

local function assertContains(text, needle, message)
    assert(string.find(text, needle, 1, true), message .. " missing: " .. needle)
end

local function assertNotContains(text, needle, message)
    assert(not string.find(text, needle, 1, true), message .. " unexpected: " .. needle)
end

local function extractBlock(text, startNeedle, endNeedle, message)
    local startPos = string.find(text, startNeedle, 1, true)
    assert(startPos, message .. " missing start: " .. startNeedle)

    local endPos = string.find(text, endNeedle, startPos + #startNeedle, true)
    assert(endPos, message .. " missing end: " .. endNeedle)

    return string.sub(text, startPos, endPos + #endNeedle - 1)
end

local function assertContainsOrdered(text, needles, message)
    local searchStart = 1
    for _, needle in ipairs(needles) do
        local pos = string.find(text, needle, searchStart, true)
        assert(pos, message .. " missing ordered snippet: " .. needle)
        searchStart = pos + #needle
    end
end

local scheduler = readAll("modules/cdm/cdm_scheduler.lua")
local resolvers = readAll("modules/cdm/cdm_resolvers.lua")
local icons = readAll("modules/cdm/cdm_icons.lua")
local factory = readAll("modules/cdm/cdm_icon_factory.lua")
local sources = readAll("modules/cdm/cdm_sources.lua")
local effects = readAll("modules/cdm/cdm_effects.lua")
local composer = readAll("modules/cdm/cdm_composer.lua")

assertContains(
    scheduler,
    "_getDelay(fast, mode, trustIsOnGCD == true)",
    "scheduler should pass mode and trust flag to delay provider"
)

assertContains(
    icons,
    "local CDM_FAST_UPDATE_INTERVAL = 0",
    "icons should define next-frame fast cooldown interval"
)
assertContains(
    icons,
    "local CDM_FAST_FULL_UPDATE_INTERVAL = CDM_MIN_UPDATE_INTERVAL_IDLE",
    "icons should cap fast full updates to the idle interval"
)
assertContains(
    icons,
    "local function GetCDMUpdateDelay(fast, mode)",
    "icons delay function should be mode-aware"
)
assertContains(
    icons,
    "local function RefreshCooldownVisualsForSpellID(eventSpellID, eventBaseSpellID)",
    "icons should expose a targeted per-spell visual refresh helper"
)

local delayBlock = extractBlock(
    icons,
    "local function GetCDMUpdateDelay(fast, mode)",
    "local function RegisterCDMSchedulerHandler()",
    "icons delay block"
)
assertContainsOrdered(
    delayBlock,
    {
        "if fast then",
        "if mode == CDM_UPDATE_COOLDOWN then",
        "return CDM_FAST_UPDATE_INTERVAL",
        "return CDM_FAST_FULL_UPDATE_INTERVAL",
        "return CDM_MIN_UPDATE_INTERVAL_RAID_COMBAT",
        "return CDM_MIN_UPDATE_INTERVAL_COMBAT",
    },
    "icons delay block should route fast and combat delays in order"
)

local scheduleBlock = extractBlock(
    icons,
    "local function ScheduleCDMUpdate(fast, mode, trustIsOnGCD)",
    "-- Scoping rule for event-driven broad resolves:",
    "scheduler block"
)
assertContains(
    scheduleBlock,
    "local delay = GetCDMUpdateDelay(fast, mode)",
    "scheduler should pass mode into GetCDMUpdateDelay"
)

assertNotContains(
    icons,
    "SafetyTickOnUpdate",
    "icons should not keep a combat safety ticker after the resolver/mirror cutover"
)
assertNotContains(
    icons,
    "safetyTickFrame",
    "icons should not keep a combat safety ticker frame after the resolver/mirror cutover"
)
assertNotContains(
    icons,
    "RangePollOnUpdate",
    "icons should not keep a periodic range/usability poller"
)
assertNotContains(
    icons,
    "RANGE_POLL",
    "icons should not keep range/usability poll intervals"
)
assertNotContains(
    icons,
    "SyncRangePoll",
    "icons should not keep a range/usability poll compatibility shim"
)
assertNotContains(
    readAll("modules/cdm/cdm_containers.lua"),
    "SyncRangePoll",
    "container refresh should not call the removed range/usability poller"
)
assertContains(
    sources,
    "function CDMSources.EnableSpellRangeCheck(spellID, enable)",
    "sources should expose Blizzard's event-driven spell range subscription API"
)
assertContains(
    icons,
    'cdEventFrame:RegisterEvent("SPELL_RANGE_CHECK_UPDATE")',
    "icons should listen for event-driven spell range updates"
)
assertContains(
    icons,
    'if event == "SPELL_RANGE_CHECK_UPDATE" then',
    "icons should handle event-driven spell range updates"
)
assertContains(
    icons,
    "Sources.EnableSpellRangeCheck",
    "icons should subscribe tracked spells for range update events"
)
assertNotContains(
    effects,
    "UsabilityGlowOnUpdate",
    "glow effects must not install a usability OnUpdate writer"
)
assertNotContains(
    effects,
    "glowFallbackTicker",
    "glow effects must not use a periodic fallback scan"
)
assertNotContains(
    effects,
    "ScheduleUsabilityGlowScan",
    "glow effects must not use delayed usability scans"
)
assertContains(
    effects,
    'eventFrame:RegisterEvent("SPELL_UPDATE_USABLE")',
    "proc-on-usable glow should be event-driven by usability updates"
)
assertContains(
    effects,
    "procOnUsable",
    "explicit proc-on-usable overrides should remain supported"
)
assertContains(
    composer,
    "procOnUsable",
    "composer should expose the proc-on-usable glow override"
)
assertContains(
    effects,
    'eventFrame:RegisterEvent("SPELL_ACTIVATION_OVERLAY_SHOW")',
    "glow effects should listen to the documented overlay show event"
)
assertContains(
    effects,
    'eventFrame:RegisterEvent("SPELL_ACTIVATION_OVERLAY_HIDE")',
    "glow effects should listen to the documented overlay hide event"
)

local visualStateBlock = extractBlock(
    icons,
    "local function UpdateIconVisualState(icon, cachedDB",
    "function CDMIcons:UpdateAllIconRanges()",
    "visual state block"
)
assertNotContains(
    visualStateBlock,
    "ApplyIconStackTextFromResolver",
    "range/usability visual updates must not write stack text"
)

assertContains(
    icons,
    "function CDMIcons.ShouldAllowStackTextWrites()",
    "icons should expose a stack-write gate for broad factory refreshes"
)

local cooldownOnlyBlock = extractBlock(
    icons,
    "function CDMIcons:UpdateCooldownOnly()",
    "function CDMIcons:UpdateCooldownsForType(viewerType)",
    "cooldown-only update block"
)
assertContainsOrdered(
    cooldownOnlyBlock,
    {
        "local allowStackTextWrites = CDMIcons._pendingStackTextUpdate == true",
        "SetStackTextWritesForBatch(allowStackTextWrites)",
        "SetStackTextWritesForBatch(false)",
    },
    "cooldown-only refresh should preserve stack text unless a stack event requested writes"
)

local cooldownOnlyIconBlock = extractBlock(
    icons,
    "local function UpdateCooldownOnlyIcon(icon, entry)",
    "function CDMIcons:UpdateCooldownOnly()",
    "cooldown-only icon helper"
)
assertContainsOrdered(
    cooldownOnlyIconBlock,
    {
        "if icon._blizzMirrorCooldownID and not IsAuraEntry(entry) then",
        "ApplyResolvedCooldown(icon)",
        "SyncCooldownBling(icon)",
        "return",
        "UpdateIconCooldown(icon)",
    },
    "cooldown-only refresh should accept mirror-backed cooldown state instead of broad API fallback"
)

local chargesChangedBlock = extractBlock(
    icons,
    "local function OnCDMChargesChanged(_, spellID)",
    "ns.CDMResolvers.Subscribe(\"CDM:COOLDOWN_CHANGED\", OnCDMCooldownChanged)",
    "charges changed block"
)
assertContainsOrdered(
    chargesChangedBlock,
    {
        "CDMIcons._pendingStackTextUpdate = true",
        "ScheduleCDMUpdate(nil, CDM_UPDATE_COOLDOWN, false)",
    },
    "charge events should explicitly opt into stack text writes"
)

local spellUpdateUsableBlock = extractBlock(
    icons,
    'if event == "SPELL_UPDATE_USABLE" then',
    'if event == "SPELLS_CHANGED" then',
    "SPELL_UPDATE_USABLE branch"
)
assertContainsOrdered(
    spellUpdateUsableBlock,
    {
        "CDMIcons.ApplyResolvedCooldownForUsabilityEvent()",
        "CDMIcons.UpdateIconRangesForUsabilityEvent()",
    },
    "SPELL_UPDATE_USABLE should reconcile stale cooldown candidates and usability visuals without broad scheduling"
)

assertContainsOrdered(
    factory,
    {
        "local _stackTextResolved = false",
        'if stackTextWritesAllowed and entry.type == "spell" and CDMIcons.ResolveIconStackText then',
        "_stackVal, _stackSource, _stackMirrorBacked = CDMIcons.ResolveIconStackText(icon)",
        "if _stackMirrorBacked and CDMIcons.ValueIsMissing(_stackVal) then",
        'CDMIcons.HideIconStackText(icon, "mirror-stack-empty")',
        "local _chargeCountForwarded = false",
        "if not _stackMirrorBacked then",
    },
    "factory should resolve mirror stack text before any API charge writer"
)

local stackResolverBlock = extractBlock(
    factory,
    "elseif entry.type == \"spell\" then",
    "-- Forward to C-side for display.",
    "factory spell stack resolver block"
)
assertContainsOrdered(
    stackResolverBlock,
    {
        "if not _stackTextResolved and CDMIcons.ResolveIconStackText then",
        "stackVal, stackSource, stackMirrorBacked = CDMIcons.ResolveIconStackText(icon)",
        "if stackMirrorBacked and CDMIcons.ValueIsMissing(stackVal) then",
        "elseif CDMIcons.ValueIsMissing(stackVal) and isMultiCharge then",
        "elseif CDMIcons.ValueIsMissing(stackVal) then",
    },
    "factory spell stack path should keep mirror empty authoritative inside the display branch"
)
assertNotContains(
    stackResolverBlock,
    "CDMIcons.GetAuraApplicationsForSpell(spellID, entry, icon)",
    "factory spell stack path must not synthesize action-icon stacks from mapped aura applications"
)
assertContains(
    factory,
    "local stackTextWritesAllowed = CDMIcons.ShouldAllowStackTextWrites and CDMIcons.ShouldAllowStackTextWrites() == true",
    "factory stack writers should be gated by explicit stack-update context"
)

local resolverRuntimeBlock = extractBlock(
    resolvers,
    '_runtimeFrame:SetScript("OnEvent", function(_, evt, arg1, arg2, arg3)',
    "end)",
    "resolver runtime event block"
)
assertContainsOrdered(
    resolverRuntimeBlock,
    {
        'if evt == "SPELL_UPDATE_COOLDOWN" then',
        'publish("CDM:COOLDOWN_CHANGED", arg1, arg2, "refresh")',
        'elseif evt == "SPELL_UPDATE_CHARGES" then',
        'elseif evt == "UNIT_SPELLCAST_START" then',
        'publish("CDM:COOLDOWN_CHANGED", arg3, nil, "cast_start")',
        'elseif evt == "UNIT_SPELLCAST_SUCCEEDED" then',
        'publish("CDM:COOLDOWN_CHANGED", arg3, nil, "cast_succeeded")',
    },
    "resolver should preserve base spell IDs and handler payload shape"
)

local targetedRefreshBlock = extractBlock(
    icons,
    "if spellID and spellID ~= GCD_SPELL_ID and not gcdChanged then",
    "else",
    "targeted cooldown branch"
)
assertContainsOrdered(
    targetedRefreshBlock,
    {
        "ApplyResolvedCooldownForSpellID(spellID, baseSpellID)",
        "RefreshCooldownVisualsForSpellID(spellID, baseSpellID)",
    },
    "targeted cooldown refresh should reconcile per-spell visuals immediately"
)

print("OK: cdm_fast_visual_refresh_contract_test")
