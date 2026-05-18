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

local function collectCDMIconsPublicSurface(text)
    local symbols = {}
    for line in string.gmatch(text, "[^\r\n]+") do
        local symbol = string.match(line, "^%s*function%s+CDMIcons[:%.]([%w_]+)%s*%(")
        if symbol then
            symbols[symbol] = true
        end
        symbol = string.match(line, "^%s*CDMIcons%.([%w_]+)%s*=")
        if symbol then
            symbols[symbol] = true
        end
        symbol = string.match(line, "^%s*CDMIcons%[[\"']([%w_]+)[\"']%]%s*=")
        if symbol then
            symbols[symbol] = true
        end
        symbol = string.match(line, "^%s*function%s+ns%.CDMIcons[:%.]([%w_]+)%s*%(")
        if symbol then
            symbols[symbol] = true
        end
        symbol = string.match(line, "^%s*ns%.CDMIcons%.([%w_]+)%s*=")
        if symbol then
            symbols[symbol] = true
        end
    end
    return symbols
end

local function mergeAllowlist(categories)
    local merged = {}
    for _, category in pairs(categories) do
        for symbol in pairs(category) do
            merged[symbol] = true
        end
    end
    return merged
end

local function assertPublicSurface(publicSymbols, categories)
    local owners = {}
    for categoryName, category in pairs(categories) do
        for symbol in pairs(category) do
            if owners[symbol] then
                error("CDMIcons public symbol is categorized more than once: "
                    .. symbol .. " (" .. owners[symbol] .. ", " .. categoryName .. ")")
            end
            owners[symbol] = categoryName
        end
    end

    local allowed = mergeAllowlist(categories)
    local unexpected = {}
    for symbol in pairs(publicSymbols) do
        if not allowed[symbol] then
            unexpected[#unexpected + 1] = symbol
        end
    end
    table.sort(unexpected)
    assert(#unexpected == 0, "CDMIcons public surface has uncategorized symbols: " .. table.concat(unexpected, ", "))

    local missing = {}
    for symbol in pairs(allowed) do
        if not publicSymbols[symbol] then
            missing[#missing + 1] = symbol
        end
    end
    table.sort(missing)
    assert(#missing == 0, "CDMIcons public surface is missing categorized symbols: " .. table.concat(missing, ", "))
end

local scheduler = readAll("modules/cdm/cdm_scheduler.lua")
local resolvers = readAll("modules/cdm/cdm_resolvers.lua")
local runtimeQueries = readAll("modules/cdm/cdm_runtime_queries.lua")
local icons = readAll("modules/cdm/cdm_icons.lua")
local iconMirrorIndex = readAll("modules/cdm/cdm_icon_mirror_index.lua")
local iconRuntimeRefresh = readAll("modules/cdm/cdm_icon_runtime_refresh.lua")
local iconUpdateScheduler = readAll("modules/cdm/cdm_icon_update_scheduler.lua")
local iconRefreshBatch = readAll("modules/cdm/cdm_icon_refresh_batch.lua")
local iconRefreshWalker = readAll("modules/cdm/cdm_icon_refresh_walker.lua")
local iconVisibilityPolicy = readAll("modules/cdm/cdm_icon_visibility_policy.lua")
local iconRangePolicy = readAll("modules/cdm/cdm_icon_range_policy.lua")
local iconCooldownPolicy = readAll("modules/cdm/cdm_icon_cooldown_policy.lua")
local iconStackPolicy = readAll("modules/cdm/cdm_icon_stack_policy.lua")
local iconCustomBarPolicy = readAll("modules/cdm/cdm_icon_custom_bar_policy.lua")
local auraRuntime = readAll("modules/cdm/cdm_aura_runtime.lua")
local factory = readAll("modules/cdm/cdm_icon_factory.lua")
local containers = readAll("modules/cdm/cdm_containers.lua")
local buffLayout = readAll("modules/cdm/cdm_buff_layout.lua")
local sources = readAll("modules/cdm/cdm_sources.lua")
local effects = readAll("modules/cdm/cdm_effects.lua")
local composer = readAll("modules/cdm/cdm_composer.lua")
local spellData = readAll("modules/cdm/cdm_spelldata.lua")

local cdmIconsPublicSurface = {
    external = {
        IsRuntimeEnabled = true,
        CustomCDM = true,
        EnsureTextOverlayLevel = true,
        BuildIcons = true,
        ShouldContainerLayoutPlaceIcon = true,
        UpdateAllCooldowns = true,
        UpdateCooldownOnly = true,
        UpdateCooldownsForType = true,
        OnContainerIconPlaced = true,
        OnIconRowConfigApplied = true,
        OnContainerIconInteractionRestored = true,
        OnFactoryIconCreated = true,
        OnFactoryIconAcquired = true,
        OnFactoryIconReleased = true,
        OnFactoryMirrorBound = true,
        OnFactoryMirrorUnbound = true,
        UpdateAllIconRanges = true,
        ClearTextureCycleCache = true,
        RequestFullUpdate = true,
        RebuildBlizzMirrorIconIndex = true,
        RequestMirrorTextRefresh = true,
        GetCacheStats = true,
        HandleRuntimeRefresh = true,
        DisableRuntime = true,
    },
    debug = {
        ChargeDebug = true,
        DebugStackText = true,
        DebugSpellEvent = true,
        DebugIconEvent = true,
        DebugEntryBuild = true,
        DebugLayoutFilter = true,
        EventTracePrint = true,
        EventTraceAuraInfo = true,
        RecordEventProfile = true,
        SnapshotEventProfile = true,
        _ShouldDebugBlizzEntry = true,
        _FormatMirrorState = true,
        _DebugBlizzEntry = true,
        IsGCDSwipeEnabled = true,
        _BindDebugImports = true,
    },
    test = {
        ApplyResolvedCooldown = true,
        ShouldAllowStackTextWrites = true,
    },
}

assertPublicSurface(collectCDMIconsPublicSurface(icons), cdmIconsPublicSurface)

assertContains(
    scheduler,
    "_getDelay(fast, mode, trustIsOnGCD == true)",
    "scheduler should pass mode and trust flag to delay provider"
)

assertContains(
    iconUpdateScheduler,
    "local FAST_UPDATE_INTERVAL = 0",
    "icon update scheduler should define next-frame fast cooldown interval"
)
assertContains(
    iconUpdateScheduler,
    "local FAST_FULL_UPDATE_INTERVAL = MIN_UPDATE_INTERVAL_IDLE",
    "icon update scheduler should cap fast full updates to the idle interval"
)
assertContains(
    iconUpdateScheduler,
    "function controller:GetDelay(fast, mode)",
    "icon update scheduler delay function should be mode-aware"
)
assertContains(
    iconRuntimeRefresh,
    "function controller:RefreshCooldownVisualsForSpellID(eventSpellID, eventBaseSpellID)",
    "targeted per-spell visual refresh should live in the private runtime refresh controller"
)

local delayBlock = extractBlock(
    iconUpdateScheduler,
    "function controller:GetDelay(fast, mode)",
    "function controller:GetCombatQueueDelay()",
    "icon update scheduler delay block"
)
assertContainsOrdered(
    delayBlock,
    {
        "if fast then",
        "if mode == UPDATE_COOLDOWN then",
        "return FAST_UPDATE_INTERVAL",
        "return FAST_FULL_UPDATE_INTERVAL",
        "return MIN_UPDATE_INTERVAL_RAID_COMBAT",
        "return MIN_UPDATE_INTERVAL_COMBAT",
    },
    "icon update scheduler delay block should route fast and combat delays in order"
)

local scheduleBlock = extractBlock(
    iconUpdateScheduler,
    "function controller:Schedule(fast, mode, trustIsOnGCD)",
    "function controller:ScheduleFull(fast, trustIsOnGCD)",
    "icon update scheduler schedule block"
)
assertContains(
    scheduleBlock,
    "local delay = controller:GetDelay(fast, mode)",
    "icon update scheduler should pass mode into its delay policy"
)
assertContains(
    icons,
    "updateScheduler = CreateIconUpdateScheduler()",
    "CDMIcons should wire runtime update scheduling through the private controller"
)
assertContains(
    iconRefreshBatch,
    "function controller:Prepare()",
    "icon refresh batch should own refresh preparation and DB/time hoists"
)
assertContains(
    iconRefreshBatch,
    "function controller:ConsumeStackTextWriteRequest()",
    "icon refresh batch should own stack-text write requests"
)
assertContains(
    icons,
    "refreshBatch = CreateIconRefreshBatch()",
    "CDMIcons should wire batch state through the private refresh batch controller"
)
assertContains(
    iconRefreshWalker,
    "function controller:RefreshAll(context)",
    "icon refresh walker should own broad full-refresh traversal"
)
assertContains(
    iconRefreshWalker,
    "function controller:RefreshCooldownOnly(context)",
    "icon refresh walker should own broad cooldown-only traversal"
)
assertContains(
    iconRefreshWalker,
    "function controller:RefreshType(viewerType, context)",
    "icon refresh walker should own type-scoped traversal"
)
assertContains(
    icons,
    "local function GetIconRefreshWalker()",
    "CDMIcons should wire broad refresh walking through the private refresh walker"
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
    iconRuntimeRefresh,
    'if event == "SPELL_RANGE_CHECK_UPDATE" then',
    "runtime refresh controller should handle event-driven spell range updates"
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
    iconRangePolicy,
    "local function updateIconVisualState(icon, cachedDB",
    "function controller:IconNeedsUsabilityVisualRefresh",
    "visual state block"
)
assertNotContains(
    visualStateBlock,
    "ApplyIconStackTextFromResolver",
    "range/usability visual updates must not write stack text"
)
assertContains(
    icons,
    "rangePolicy:UpdateAllIconRanges(iconPools)",
    "CDMIcons should delegate range/usability refresh through the private range policy"
)
assertContains(
    iconRangePolicy,
    "function controller:SyncSpellRangeChecks(iconPools)",
    "spell range subscriptions should live in the private range policy"
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
        "local allowStackTextWrites = ConsumeStackTextWriteRequest()",
        "SetRefreshBatchStackTextWrites(allowStackTextWrites)",
        "SetRefreshBatchStackTextWrites(false)",
    },
    "cooldown-only refresh should preserve stack text unless a stack event requested writes"
)
assertContains(
    cooldownOnlyBlock,
    "walker:RefreshCooldownOnly(context)",
    "cooldown-only broad walk should route through the private refresh walker"
)

local updateAllBlock = extractBlock(
    icons,
    "function CDMIcons:UpdateAllCooldowns()",
    "function CDMIcons:UpdateCooldownOnly()",
    "update-all block"
)
assertContains(
    updateAllBlock,
    "walker:RefreshAll(context)",
    "full broad walk should route through the private refresh walker"
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
    iconRuntimeRefresh,
    "function controller:HandleChargesChanged(_, spellID)",
    "return controller",
    "charges changed block"
)
assertContainsOrdered(
    chargesChangedBlock,
    {
        "callbacks.requestStackTextUpdate()",
        "callbacks.scheduleUpdate(nil, UPDATE_COOLDOWN, false)",
    },
    "charge events should explicitly opt into stack text writes"
)
assertContains(
    icons,
    "RequestStackTextUpdate()",
    "CDMIcons should route stack-text write requests through the private refresh batch controller"
)
assertNotContains(
    icons,
    "pendingStackTextUpdate",
    "stack-text write request state should live in the private refresh batch controller"
)
assertNotContains(
    icons,
    "CDMIcons._pendingStackTextUpdate",
    "stack-text write requests should stay private behind the runtime refresh pipeline"
)
assertNotContains(
    icons,
    "CDMIcons._allowStackTextWritesForBatch",
    "stack-text batch flags should stay private behind the stack-write gate"
)
assertNotContains(
    icons,
    "CDMIcons._pendingMirrorRefreshByCategory",
    "mirror refresh queue state should stay private behind RequestMirrorTextRefresh and GetCacheStats"
)
assertNotContains(
    icons,
    "CDMIcons._mirrorRefreshPending",
    "mirror refresh pending state should stay private behind RequestMirrorTextRefresh and GetCacheStats"
)
assertNotContains(
    icons,
    "CDMIcons._mirrorRefreshStats",
    "mirror refresh counters should stay private behind GetCacheStats"
)
assertNotContains(
    icons,
    "CDMIcons._eventProfileStats",
    "event profile state should stay private behind RecordEventProfile/SnapshotEventProfile"
)
assertNotContains(
    icons,
    "CDMIcons._eventProfileLast",
    "event profile snapshot state should stay private behind SnapshotEventProfile"
)
assertNotContains(
    icons,
    "_hoistedNcdm",
    "batch DB hoists should live in the private refresh batch controller"
)
assertNotContains(
    icons,
    "_batchTime",
    "batch time hoists should live in the private refresh batch controller"
)
assertNotContains(
    icons,
    "resolverQueryBatchStats",
    "batch query stats should live in the private refresh batch controller"
)
assertNotContains(
    icons,
    "CDMIcons._pendingTrustIsOnGCD",
    "scheduler trust flags should stay private behind runtime update scheduling"
)
assertNotContains(
    icons,
    "_cdmUpdatePending",
    "runtime update pending state should live in the private icon update scheduler"
)
assertNotContains(
    icons,
    "_cdmUpdateElapsed",
    "runtime update elapsed state should live in the private icon update scheduler"
)
assertNotContains(
    icons,
    "_cdmUpdateDelay",
    "runtime update delay state should live in the private icon update scheduler"
)
assertNotContains(
    icons,
    "_cdmUpdateMode",
    "runtime update mode state should live in the private icon update scheduler"
)
assertNotContains(
    icons,
    "_barsDirty",
    "bar-dirty state should live in the private icon update scheduler"
)
assertNotContains(
    icons,
    "pendingTrustIsOnGCD",
    "merged GCD trust state should live in the private icon update scheduler"
)
assertNotContains(
    icons,
    "CDMIcons._auraDeltaInstanceIDs",
    "aura-delta scratch instance IDs should stay private behind the runtime refresh pipeline"
)
assertNotContains(
    icons,
    "CDMIcons._auraDeltaSpellIDs",
    "aura-delta scratch spell IDs should stay private behind the runtime refresh pipeline"
)

local spellUpdateUsableBlock = extractBlock(
    iconRuntimeRefresh,
    'if event == "SPELL_UPDATE_USABLE" then',
    'if event == "SPELLS_CHANGED" then',
    "SPELL_UPDATE_USABLE branch"
)
assertContainsOrdered(
    spellUpdateUsableBlock,
    {
        "controller:QueueUsabilityRefresh()",
    },
    "SPELL_UPDATE_USABLE should route through the combat coalescer"
)
assertContainsOrdered(
    iconRuntimeRefresh,
    {
        "function controller:RunUsabilityRefresh()",
        "controller:ApplyUsabilityRefresh()",
        "callbacks.updateIconRangesForUsabilityEvent()",
    },
    "coalesced usability refresh should still reconcile stale cooldown candidates and usability visuals together"
)
assertContains(
    icons,
    "function CDMIcons.HandleRuntimeRefresh(event, arg1, arg2, arg3)",
    "CDMIcons should expose one runtime refresh seam for external CDM event sources"
)
assertContains(
    spellData,
    'icons.HandleRuntimeRefresh("UNIT_AURA", unit, updateInfo)',
    "spell data should dispatch aura payloads through the CDMIcons runtime refresh seam"
)
assertNotContains(
    spellData,
    "icons.HandleUnitAuraChanged",
    "spell data should not call icon-specific aura refresh fragments directly"
)
assertNotContains(
    icons,
    "CDMIcons.EventFrameOnEvent",
    "frame event handling should stay behind the runtime refresh pipeline"
)
assertNotContains(
    icons,
    "CDMIcons.HandleUnitAuraChanged",
    "UNIT_AURA handling should stay behind the runtime refresh seam"
)
assertNotContains(
    icons,
    "CDMIcons.RefreshCooldownVisualsForSpellID",
    "targeted visual refresh should stay private behind the runtime refresh pipeline"
)
assertNotContains(
    icons,
    "CDMIcons.ApplyResolvedCooldownForUsabilityEvent",
    "usability cooldown reconciliation should stay private behind the runtime refresh pipeline"
)
assertNotContains(
    icons,
    "CDMIcons.UpdateIconRangesForUsabilityEvent",
    "usability visual refresh should stay private behind the runtime refresh pipeline"
)
assertNotContains(
    icons,
    "CDMIcons.IconNeedsUsabilityCooldownRefresh",
    "usability cooldown predicates should stay private behind the runtime refresh pipeline"
)
assertNotContains(
    icons,
    "CDMIcons.IconNeedsUsabilityVisualRefresh",
    "usability visual predicates should stay private behind the runtime refresh pipeline"
)
assertNotContains(
    icons,
    "CDMIcons.NoteChargeDurationObjectsUpdated",
    "charge-duration resolver notifications should stay private behind the runtime refresh pipeline"
)
assertNotContains(
    icons,
    "CDMIcons.ApplyAuraScopedResolvedCooldown",
    "aura-scoped icon refresh should stay private behind the runtime refresh pipeline"
)
assertNotContains(
    icons,
    "CDMIcons.RefreshIndexedMirrorIcon",
    "mirror index refresh should stay private behind the mirror refresh queue"
)
assertNotContains(
    icons,
    "CDMIcons.CountPendingMirrorRefreshKeys",
    "mirror refresh queue counting should stay private behind cache stats"
)
assertNotContains(
    icons,
    "function _resolverRuntimePolicy.QueueResolvedCooldownForSpellID",
    "per-spell refresh queues should live in the private runtime refresh controller"
)
assertNotContains(
    icons,
    "function _resolverRuntimePolicy.QueueUsabilityRefresh",
    "usability refresh queues should live in the private runtime refresh controller"
)
assertNotContains(
    icons,
    "function _resolverRuntimePolicy.QueueItemScopeRefresh",
    "item refresh queues should live in the private runtime refresh controller"
)
assertNotContains(
    icons,
    "local function ApplyResolvedCooldownForSpellScope",
    "spell-scope refresh walking should live in the private runtime refresh controller"
)
assertNotContains(
    icons,
    "local function ApplyResolvedCooldownForItemScope",
    "item-scope refresh walking should live in the private runtime refresh controller"
)
assertNotContains(
    icons,
    "local function ApplyResolvedCooldownForAuraInstances",
    "aura-delta refresh walking should live in the private runtime refresh controller"
)

assertContainsOrdered(
    icons,
    {
        "local _stackTextResolved = false",
        'if stackTextWritesAllowed and entry.type == "spell" and _resolverRuntimePolicy.ResolveIconStackText then',
        "_stackVal, _stackSource, _stackMirrorBacked = _resolverRuntimePolicy.ResolveIconStackText(icon)",
        "if _stackMirrorBacked and _resolverRuntimePolicy.ValueIsMissing(_stackVal) then",
        '_resolverRuntimePolicy.HideIconStackText(icon, "mirror-stack-empty")',
        "local _chargeCountForwarded = false",
        'if stackTextWritesAllowed and entry.type == "spell" and not _stackMirrorBacked then',
    },
    "icon runtime should resolve mirror stack text before any API charge writer"
)

local stackResolverBlock = extractBlock(
    icons,
    "local stackVal = _stackVal",
    "elseif stackMirrorEmpty then",
    "icon runtime spell stack resolver block"
)
assertContainsOrdered(
    stackResolverBlock,
    {
        "if not _stackTextResolved and _resolverRuntimePolicy.ResolveIconStackText then",
        "stackVal, stackSource, stackMirrorBacked = _resolverRuntimePolicy.ResolveIconStackText(icon)",
        "if stackMirrorBacked and _resolverRuntimePolicy.ValueIsMissing(stackVal) then",
        "elseif _resolverRuntimePolicy.ValueIsMissing(stackVal) and isMultiCharge then",
        "elseif _resolverRuntimePolicy.ValueIsMissing(stackVal) then",
    },
    "icon runtime spell stack path should keep mirror empty authoritative inside the display branch"
)
assertNotContains(
    stackResolverBlock,
    "CDMIcons.GetAuraApplicationsForSpell(spellID, entry, icon)",
    "icon runtime spell stack path must not synthesize action-icon stacks from mapped aura applications"
)
assertContains(
    icons,
    "local stackTextWritesAllowed = CDMIcons.ShouldAllowStackTextWrites and CDMIcons.ShouldAllowStackTextWrites() == true",
    "icon runtime stack writers should be gated by explicit stack-update context"
)
assertNotContains(
    icons,
    "SeedMirrorStackTextForBinding",
    "mirror-bind stack text seeding should stay local behind mirror lifecycle hooks"
)
assertContains(
    icons,
    "function CDMIcons.OnFactoryIconCreated(icon, entry)",
    "CDMIcons should expose an icon-created lifecycle hook for factory-owned frames"
)
assertContains(
    icons,
    "function CDMIcons.OnFactoryIconAcquired(icon, entry, reused)",
    "CDMIcons should expose an icon-acquired lifecycle hook for runtime setup"
)
assertContains(
    icons,
    "function CDMIcons.OnFactoryIconReleased(icon)",
    "CDMIcons should expose an icon-released lifecycle hook for runtime teardown"
)
assertContains(
    icons,
    "function CDMIcons.OnContainerIconInteractionRestored(icon, viewerType)",
    "CDMIcons should expose a container-interaction lifecycle hook for icon runtime refresh"
)
assertContains(
    icons,
    "function CDMIcons.ShouldContainerLayoutPlaceIcon(icon, entry, containerDB, inCombat)",
    "CDMIcons should expose a narrow layout-placement hook for dynamic-layout filtering"
)
assertContainsOrdered(
    icons,
    {
        "function CDMIcons.ShouldContainerLayoutPlaceIcon(icon, entry, containerDB, inCombat)",
        "visibilityPolicy:ShouldPlaceLayoutIcon(icon, entry, containerDB, inCombat)",
    },
    "layout-placement hook should delegate filter computation through the private visibility policy"
)
assertContains(
    iconVisibilityPolicy,
    "function controller:ComputeFilterHides(icon, entry, containerDB, inCombat, isOnCD)",
    "visibility filter computation should live in the private visibility policy"
)
assertContains(
    iconVisibilityPolicy,
    "icon._lastLayoutFilterHidden = filterHides and true or false",
    "visibility policy should own the layout-filter stamp"
)
assertContains(
    iconVisibilityPolicy,
    "function controller:ApplyIconVisibility(icon, shouldShow, dynamicLayout)",
    "show/hide/alpha application should live in the private visibility policy"
)
assertContains(
    icons,
    "function CDMIcons.OnContainerIconPlaced(icon, rowConfig)",
    "CDMIcons should expose a container placement lifecycle hook for row styling and runtime refresh"
)
assertContainsOrdered(
    icons,
    {
        "function CDMIcons.OnContainerIconPlaced(icon, rowConfig)",
        "ConfigureIcon(icon, rowConfig)",
        "UpdateIconCooldown(icon)",
    },
    "container placement hook should apply row styling before refreshing icon runtime"
)
assertNotContains(
    icons,
    "function CDMIcons.UpdateIconCooldown(icon)",
    "CDMIcons should not expose a generic single-icon cooldown update wrapper"
)
assertContains(
    icons,
    "function CDMIcons.OnIconRowConfigApplied(icon, rowConfig)",
    "CDMIcons should expose a row-config lifecycle hook for icon styling"
)
assertContains(
    icons,
    "function CDMIcons.OnFactoryMirrorBound(icon, cooldownID, category)",
    "CDMIcons should expose a mirror-bound lifecycle hook for mirror runtime setup"
)
assertContains(
    icons,
    "function CDMIcons.OnFactoryMirrorUnbound(icon)",
    "CDMIcons should expose a mirror-unbound lifecycle hook for mirror runtime teardown"
)
assertContainsOrdered(
    icons,
    {
        "function CDMIcons.OnFactoryMirrorBound(icon, cooldownID, category)",
        "mirrorController:BindIcon(icon, cooldownID, category)",
    },
    "mirror-bound hook should delegate mirror index registration through the private controller"
)
assertContainsOrdered(
    icons,
    {
        "function CDMIcons.OnFactoryMirrorUnbound(icon)",
        "mirrorController:UnbindIcon(icon)",
    },
    "mirror-unbound hook should delegate mirror index unregister through the private controller"
)
assertContains(
    iconMirrorIndex,
    "local controller = {",
    "mirror index storage should be private to CDMIconMirrorIndex"
)
assertContains(
    iconMirrorIndex,
    "iconSet = setmetatable({}, { __mode = \"k\" })",
    "mirror index should use weak icon sets inside the private controller"
)
assertContainsOrdered(
    icons,
    {
        "onBound = function(icon)",
        "ConfigureIcon(icon, icon._rowConfig)",
        "_resolverRuntimePolicy.ResolveIconStackText(icon)",
        'ClearIconStackText(icon, "mirror-bind-empty")',
    },
    "CDMIcons mirror-bound adapter should keep row-style reapplication and stack seeding private"
)
assertNotContains(
    icons,
    "CDMIcons.GetMirrorIconSet",
    "mirror index lookup should not be exposed as a public CDMIcons helper"
)
assertNotContains(
    icons,
    "CDMIcons._mirrorIconsByCategory",
    "mirror index storage should not be exposed on CDMIcons"
)
assertNotContains(
    icons,
    "function CDMIcons.OnFactoryMirrorBindingChanged(icon)",
    "CDMIcons should not expose a separate mirror-binding row-style hook"
)
assertNotContains(
    icons,
    "RegisterBlizzMirrorIcon",
    "mirror index registration should stay local behind mirror lifecycle hooks"
)
assertContains(
    iconRuntimeRefresh,
    "function controller:HandleAuraRefresh(unit, updateInfo)",
    "UNIT_AURA refresh branching should live in the private runtime refresh controller"
)
assertContains(
    icons,
    "runtimeRefresh = ns.CDMIconRuntimeRefresh and ns.CDMIconRuntimeRefresh.Create",
    "CDMIcons should wire runtime refresh through the private controller"
)
assertContains(
    auraRuntime,
    "function CDMAuraRuntime.ResolveState(params)",
    "runtime aura state should have a module-shaped interface"
)
assertContains(
    auraRuntime,
    "function CDMAuraRuntime.ResolveAbilityAuraSpellID(spellID)",
    "ability-to-aura lookup should live behind the runtime aura interface"
)
assertContains(
    spellData,
    "ns.CDMAuraRuntime.SetResolver(ResolveAuraRuntimeStateImpl)",
    "CDMSpellData should register its aura resolver behind CDMAuraRuntime"
)
assertContains(
    spellData,
    "ns.CDMAuraRuntime.SetAbilityAuraSpellIDResolver(ResolveAuraDisplaySpellID)",
    "CDMSpellData should register ability-to-aura lookup behind CDMAuraRuntime"
)
assertNotContains(
    spellData,
    "CDMSpellData._abilityToAuraSpellID =",
    "CDMSpellData should not export its private ability-to-aura map"
)
assertNotContains(
    spellData,
    "CDMSpellData._auraIDsForSpell =",
    "CDMSpellData should not export its private aura ID map"
)
assertContains(
    resolvers,
    "AuraRuntime.ResolveState(p)",
    "CDMResolvers should consume aura facts through CDMAuraRuntime"
)
assertContains(
    runtimeQueries,
    "local CDMRuntimeQueries = {}",
    "runtime query/cache state should live outside CDMResolvers"
)
assertContains(
    icons,
    "local RuntimeQueries = ns.CDMRuntimeQueries",
    "CDMIcons should consume runtime queries through the narrow runtime-query seam"
)
assertNotContains(
    resolvers,
    "function CDMResolvers.QueryCooldown(spellID)",
    "CDMResolvers should not own runtime query helper implementations"
)
assertNotContains(
    resolvers,
    "CDMResolvers.QueryCooldown =",
    "CDMResolvers should not export runtime query compatibility aliases"
)
assertNotContains(
    spellData,
    "function CDMSpellData:ResolveAuraState(params)",
    "CDMSpellData should not export aura resolution as a caller-facing wrapper"
)
assertNotContains(
    spellData,
    "CDMSpellData.ResolveAbilityAuraSpellID =",
    "CDMSpellData should not export ability-to-aura lookup compatibility aliases"
)
assertNotContains(
    spellData,
    "CDMSpellData.GetAuraApplications =",
    "CDMSpellData should not export aura application compatibility aliases"
)
assertContains(
    icons,
    "function _resolverRuntimePolicy.ResolveAuraApplicationsForEntry(spellID, entry, icon)",
    "CDMIcons should keep aura application fallback behind resolver runtime policy"
)
assertContains(
    iconStackPolicy,
    "auraRuntime.ResolveState(p)",
    "CDMIconStackPolicy should consume aura application fallback through CDMAuraRuntime"
)
assertContains(
    iconStackPolicy,
    "auraRuntime.ResolveAbilityAuraSpellID(auraID)",
    "CDMIconStackPolicy should consume ability-to-aura remaps through CDMAuraRuntime"
)
assertContains(
    icons,
    "AuraRuntime.HasAbilityAuraMapping(entry.id)",
    "CDMIcons grey-out detection should consume ability-to-aura facts through CDMAuraRuntime"
)
assertNotContains(
    icons,
    "CDMSpellData._abilityToAuraSpellID",
    "CDMIcons should not consume CDMSpellData private aura maps"
)
assertNotContains(
    icons .. factory .. spellData .. effects,
    "FALLBACK_BUILTIN_CONTAINER",
    "CDM modules should ask CDMShared instead of keeping fallback container taxonomy maps"
)
assertNotContains(
    icons,
    "UnregisterBlizzMirrorIcon",
    "mirror index unregister should stay local behind mirror lifecycle hooks"
)
assertNotContains(
    icons,
    "CDMIcons.ConfigureIcon =",
    "icon row styling should stay local behind CDMIcons lifecycle hooks"
)
assertNotContains(
    icons,
    "CDMIcons.ClearIconProfessionQuality =",
    "profession-quality teardown should stay local behind CDMIcons lifecycle hooks"
)
assertNotContains(
    icons,
    "CDMIcons.UpdateIconProfessionQuality =",
    "profession-quality setup should stay local behind CDMIcons lifecycle hooks"
)
assertNotContains(
    icons,
    "CDMIcons.CancelCooldownExpiryRefresh =",
    "cooldown-expiry timer cleanup should stay local behind CDMIcons lifecycle hooks"
)
assertNotContains(
    icons,
    "CDMIcons.UnmirrorBlizzCooldown =",
    "mirror cooldown runtime teardown should stay local behind CDMIcons lifecycle hooks"
)
assertNotContains(
    icons,
    "CDMIcons.ClearClickButtonAttributes =",
    "click-to-cast attribute clearing should stay local behind CDMIcons lifecycle hooks"
)
assertNotContains(
    icons,
    "CDMIcons.UpdateIconSecureAttributes =",
    "click-to-cast attribute refresh should stay local behind CDMIcons lifecycle hooks"
)
assertNotContains(
    icons,
    "CDMIcons.IsCustomBarContainer",
    "custom-bar container detection should live on CDMShared"
)
assertNotContains(
    icons,
    "CDMIcons.NormalizeCustomBarVisibilityFlags",
    "custom-bar visibility normalization should live on CDMShared"
)
assertNotContains(
    icons,
    "CDMIcons.GetCustomBarVisibilityMode",
    "custom-bar visibility mode lookup should live on CDMShared"
)
assertContains(
    iconCustomBarPolicy,
    "function controller:ComputeVisibility(icon, entry, containerDB, now)",
    "custom-bar visibility implementation should live in CDMIconCustomBarPolicy"
)
assertContains(
    iconCustomBarPolicy,
    "function controller:ApplyActiveGlow(icon, containerDB, visibility)",
    "custom-bar active glow implementation should live in CDMIconCustomBarPolicy"
)
assertContains(
    iconCustomBarPolicy,
    "function controller:ResolveActiveState(entry, icon, now)",
    "custom-bar active-state resolution should live in CDMIconCustomBarPolicy"
)
assertContains(
    iconCustomBarPolicy,
    "function controller:ResolveUsability(entry, containerDB, cooldownState)",
    "custom-bar usability policy should live in CDMIconCustomBarPolicy"
)
assertContains(
    iconCustomBarPolicy,
    "function controller:ApplySwipeStyle(icon, containerDB, cooldownState)",
    "custom-bar recharge swipe policy should live in CDMIconCustomBarPolicy"
)
assertNotContains(
    icons,
    "CDMIcons.ResolveItemActiveState",
    "custom-bar item active lookup should stay private behind CDMIcons implementation"
)
assertNotContains(
    icons,
    "CDMIcons.ResolveEntryRuntimeSpellID",
    "entry runtime spell ID lookup should stay private behind CDMIcons implementation"
)
assertNotContains(
    icons,
    "CDMIcons.CooldownHasVisualPriority",
    "cooldown visual-priority policy should stay private behind CDMIcons implementation"
)
assertNotContains(
    icons,
    "CDMIcons.ResolveCustomBarActiveState",
    "custom-bar active-state resolution should stay private behind CDMIcons implementation"
)
assertNotContains(
    icons,
    "CDMIcons.ResolveCustomBarCooldownState",
    "custom-bar cooldown-state adaptation should stay private behind CDMIcons implementation"
)
assertNotContains(
    icons,
    "CDMIcons.ResolveCustomBarUsability",
    "custom-bar usability policy should stay private behind CDMIcons implementation"
)
assertNotContains(
    icons,
    "CDMIcons.ComputeCustomBarVisibility",
    "custom-bar visibility policy should stay private behind CDMIcons implementation"
)
assertNotContains(
    icons,
    "CDMIcons.StartCustomBarActiveGlow",
    "custom-bar active glow start should stay private behind CDMIcons lifecycle hooks"
)
assertNotContains(
    icons,
    "CDMIcons.StopCustomBarActiveGlow",
    "custom-bar active glow cleanup should stay private behind CDMIcons lifecycle hooks"
)
assertNotContains(
    icons,
    "CDMIcons.ApplyCustomBarSwipeStyle",
    "custom-bar swipe policy should stay private behind CDMIcons implementation"
)
assertNotContains(
    icons,
    "CDMIcons.ApplyCustomBarActiveState",
    "custom-bar active-state application should stay private behind CDMIcons implementation"
)
assertNotContains(
    icons,
    "CDMIcons.ApplyCustomBarActiveGlow",
    "custom-bar active glow application should stay private behind CDMIcons implementation"
)
assertNotContains(
    icons,
    "local usable = _resolverRuntimePolicy.ResolveCustomBarUsability",
    "custom-bar visibility internals should not live in CDMIcons"
)
assertNotContains(
    icons,
    "LCG.PixelGlow_Start(icon",
    "custom-bar glow internals should not live in CDMIcons"
)
assertNotContains(
    icons,
    "CDMIcons.ClearAuraStateForIcon",
    "aura frame-state clearing should stay local to CDMIcons implementation"
)
assertNotContains(
    icons,
    "CDMIcons.ApplyAuraStateToIcon",
    "aura frame-state application should stay local to CDMIcons implementation"
)
assertNotContains(
    icons,
    "CDMIcons.ApplyCooldownDesaturation",
    "cooldown desaturation should stay local to CDMIcons implementation"
)
assertNotContains(
    icons,
    "CDMIcons.ResolveResolvedStateForIcon",
    "resolved-state icon adapter should stay private behind CDMIcons implementation"
)
assertNotContains(
    icons,
    "CDMIcons.ResolveAuraFactsForIcon",
    "aura fact adapter should stay private behind CDMIcons implementation"
)
assertNotContains(
    icons,
    "CDMIcons.ApplyAndReadResolvedCooldown",
    "apply/read resolved cooldown helper should not be a public CDMIcons surface"
)
assertNotContains(
    icons,
    "CDMIcons.ReadAppliedCooldownState",
    "applied cooldown state reads should use CDMRuntimeStore directly"
)
assertNotContains(
    icons,
    "CDMIcons.ResolveIconStackText",
    "stack text resolution should stay private behind CDMIcons lifecycle hooks"
)
assertNotContains(
    icons,
    "CDMIcons.GetAuraApplicationsForSpell",
    "aura stack lookup should stay private behind CDMIcons lifecycle hooks"
)
assertNotContains(
    icons,
    "CDMIcons.ApplyAuraCountText",
    "aura count rendering should stay private behind CDMIcons lifecycle hooks"
)
assertNotContains(
    icons,
    "CDMIcons.GetTrackerSettings",
    "tracker settings lookup should stay private behind CDMIcons implementation"
)
assertNotContains(
    icons,
    "CDMIcons.ValueIsPresent",
    "stack value predicates should stay private behind CDMIcons implementation"
)
assertNotContains(
    icons,
    "CDMIcons.ValueIsMissing",
    "stack value predicates should stay private behind CDMIcons implementation"
)
assertNotContains(
    icons,
    "CDMIcons.ClearIconStackText",
    "stack text clearing should stay private behind CDMIcons lifecycle hooks"
)
assertNotContains(
    icons,
    "CDMIcons.ShowIconStackText",
    "stack text showing should stay private behind CDMIcons lifecycle hooks"
)
assertNotContains(
    icons,
    "CDMIcons.HideIconStackText",
    "stack text hiding should stay private behind CDMIcons lifecycle hooks"
)
assertNotContains(
    icons,
    "CDMIcons.ShouldHideIconStackText",
    "stack text display predicates should stay private behind CDMIcons implementation"
)
assertNotContains(
    icons,
    "CDMIcons.ApplyMirrorStackText",
    "mirror stack rendering should stay private behind CDMIcons implementation"
)
assertContains(
    iconStackPolicy,
    "function controller:ResolveIconStackText(icon)",
    "stack text resolution implementation should live in CDMIconStackPolicy"
)
assertContains(
    iconStackPolicy,
    "function controller:GetAuraApplicationsForSpell(spellID, entryOrName, icon)",
    "aura application stack lookup should live in CDMIconStackPolicy"
)
assertContains(
    iconStackPolicy,
    "function controller:ApplyAuraCountText(icon, count, showZero, preserveWhenMissing)",
    "resolved count rendering policy should live in CDMIconStackPolicy"
)
assertContains(
    iconStackPolicy,
    "function controller:ApplyMirrorStackText(icon, mirrorState, showZero)",
    "mirror stack rendering policy should live in CDMIconStackPolicy"
)
assertNotContains(
    icons,
    "CDMIcons.HookTextHasDisplay",
    "stack text display probing should stay private behind CDMIcons implementation"
)
assertNotContains(
    icons,
    "CDMIcons.GetSpellNameForAlias",
    "recent-cast alias helpers should not be public CDMIcons surface"
)
assertNotContains(
    icons,
    "CDMIcons.NormalizeSpellAliasName",
    "recent-cast alias normalization should not be public CDMIcons surface"
)
assertNotContains(
    icons,
    "CDMIcons.RecordRecentPlayerSpellCast",
    "recent-cast alias recording should not be public CDMIcons surface"
)
assertNotContains(
    icons,
    "CDMIcons.GetRecentCastAliasForEntry",
    "recent-cast alias lookup should not be public CDMIcons surface"
)
assertNotContains(
    icons,
    "CDMIcons._recentCastSpellByName",
    "recent-cast alias scratch state should not be public CDMIcons surface"
)
assertNotContains(
    icons,
    "CDMIcons._recentCastAliasTTL",
    "recent-cast alias TTL should not be public CDMIcons surface"
)
assertNotContains(
    icons,
    "CDMIcons.RefreshSwipeBatchSettings",
    "swipe batch settings should stay private behind CDMIcons runtime batches"
)
assertNotContains(
    icons,
    "CDMIcons.ShouldSkipAuraPhaseForCooldownIcon",
    "aura-phase renderer policy should stay private behind resolver context construction"
)
assertNotContains(
    icons,
    "CDMIcons.ShouldUseBuffSwipeForIcon",
    "buff-swipe renderer policy should stay private behind resolver context construction"
)
assertNotContains(
    icons,
    "CDMIcons.DebugBlizzSyncSnapshot",
    "mirror sync debug snapshots should stay private behind mirror state sync"
)
assertNotContains(
    icons,
    "CDMIcons.SyncBlizzMirrorIconState",
    "mirror state sync should stay private behind icon cooldown updates"
)
assertContains(
    icons,
    "function _resolverRuntimePolicy.CaptureTrustedGCDState",
    "GCD trusted-state capture adapter should remain private to CDMIcons renderer runtime"
)
assertContains(
    iconCooldownPolicy,
    "function controller:CaptureTrustedGCDState(iconPools, spellState, stamp)",
    "GCD trusted-state capture implementation should live in CDMIconCooldownPolicy"
)
assertContains(
    icons,
    "function _resolverRuntimePolicy.UpdateIconChargeMirrorCycle",
    "mirror charge-cycle adapter should remain private to CDMIcons renderer runtime"
)
assertContains(
    iconCooldownPolicy,
    "function controller:UpdateIconChargeMirrorCycle(icon, mode, runtimeSpellID)",
    "mirror charge-cycle tracking implementation should live in CDMIconCooldownPolicy"
)
assertContains(
    iconCooldownPolicy,
    "function controller:MarkGCDSwipe(icon)",
    "GCD swipe flag implementation should live in CDMIconCooldownPolicy"
)
assertContains(
    iconCooldownPolicy,
    "function controller:MirrorPayloadMatchesRecentChargeCycle(icon, mirrorPayload)",
    "mirror charge-cycle matching implementation should live in CDMIconCooldownPolicy"
)
assertNotContains(
    icons,
    "CDMIcons.MarkGCDSwipe",
    "GCD swipe flag writes should stay private behind CDMIcons implementation"
)
assertNotContains(
    icons,
    "CDMIcons.ClearGCDSwipe",
    "GCD swipe flag clears should stay private behind CDMIcons implementation"
)
assertNotContains(
    icons,
    "CDMIcons.CaptureTrustedGCDStateForIcon",
    "per-icon GCD snapshot capture should stay private behind CDMIcons implementation"
)
assertNotContains(
    icons,
    "CDMIcons.CaptureTrustedGCDState",
    "GCD snapshot capture should stay private behind CDMIcons implementation"
)
assertNotContains(
    icons,
    "CDMIcons.GetIconMirrorState",
    "mirror state lookup should stay private behind CDMIcons implementation"
)
assertNotContains(
    icons,
    "CDMIcons.MirrorStateIsActive",
    "mirror active predicate should stay private behind CDMIcons implementation"
)
assertNotContains(
    icons,
    "CDMIcons.ClearIconChargeMirrorCycle",
    "mirror charge-cycle clearing should stay private behind CDMIcons implementation"
)
assertNotContains(
    icons,
    "CDMIcons.RememberIconChargeMirrorCycle",
    "mirror charge-cycle memory should stay private behind CDMIcons implementation"
)
assertNotContains(
    icons,
    "CDMIcons.UpdateIconChargeMirrorCycle",
    "mirror charge-cycle tracking should stay private behind CDMIcons implementation"
)
assertNotContains(
    icons,
    "CDMIcons.ReapplySwipeStyle",
    "swipe-style reapplication should stay private behind CDMIcons implementation"
)
assertContains(
    icons,
    "function _resolverRuntimePolicy.ApplyDurationObjectCooldown",
    "DurationObject cooldown application should remain private to CDMIcons renderer runtime"
)
assertContains(
    icons,
    "function _resolverRuntimePolicy.WakeBuffIconContainer",
    "buff container wakeup should remain private to CDMIcons renderer runtime"
)
assertContains(
    icons,
    "function _resolverRuntimePolicy.RequestBuffIconLayoutRefresh",
    "buff layout refresh requests should remain private to CDMIcons renderer runtime"
)
assertNotContains(
    icons,
    "CDMIcons.IsSafeNumeric",
    "numeric safety helpers should stay private behind CDMIcons implementation"
)
assertNotContains(
    icons,
    "CDMIcons.ApplyDurationObjectCooldown",
    "DurationObject cooldown application should stay private behind CDMIcons implementation"
)
assertNotContains(
    icons,
    "CDMIcons.GetItemCooldown",
    "item cooldown adapters should not be re-exported from CDMIcons"
)
assertNotContains(
    icons,
    "CDMIcons.GetSlotCooldown",
    "slot cooldown adapters should not be re-exported from CDMIcons"
)
assertNotContains(
    icons,
    "CDMIcons.IsTotemSlotEntry",
    "totem entry predicates should stay private behind CDMIcons implementation"
)
assertNotContains(
    icons,
    "CDMIcons.ResolveTrackerSettingsNow",
    "tracker settings lookup should stay private behind CDMIcons implementation"
)
assertNotContains(
    icons,
    "CDMIcons.BuildIconListSignature",
    "icon-list signature building should stay private behind CDMIcons implementation"
)
assertNotContains(
    icons,
    "CDMIcons.WakeBuffIconContainer",
    "buff container wakeup should stay private behind CDMIcons implementation"
)
assertNotContains(
    icons,
    "CDMIcons.RequestBuffIconLayoutRefresh",
    "buff layout refresh requests should stay private behind CDMIcons implementation"
)
assertContains(
    icons,
    "CDMCooldown.GetItemCooldown = GetItemCooldown",
    "CDMCooldown should own item cooldown adapter exposure"
)
assertContains(
    icons,
    "CDMCooldown.GetSlotCooldown = GetSlotCooldown",
    "CDMCooldown should own slot cooldown adapter exposure"
)
assertNotContains(
    icons,
    "CDMIcons.ComputeFilterHides",
    "layout filtering should stay behind the container layout-placement hook"
)
assertContains(
    containers,
    "ns.CDMIcons.OnContainerIconPlaced(icon, rowConfig)",
    "containers should notify CDMIcons when an icon has been placed"
)
assertContainsOrdered(
    containers,
    {
        "icon:SetPoint(\"CENTER\", container, \"CENTER\", x, y)",
        "icon:Show()",
        "ns.CDMIcons.OnContainerIconPlaced(icon, rowConfig)",
    },
    "containers should notify CDMIcons after geometry placement and show"
)
assertContains(
    containers,
    "ns.CDMIcons.OnContainerIconInteractionRestored(icon, viewerType)",
    "containers should notify CDMIcons when icon interaction is restored"
)
assertContains(
    containers,
    "local ShouldPlaceLayoutIcon = ns.CDMIcons and ns.CDMIcons.ShouldContainerLayoutPlaceIcon",
    "containers should use the CDMIcons layout-placement hook for dynamic-layout filtering"
)
assertContainsOrdered(
    containers,
    {
        "dynamicLayoutEnabled and ShouldPlaceLayoutIcon then",
        "if not ShouldPlaceLayoutIcon(icon, entry, settings, inCombatNow) then",
        "icon:Hide()",
        "icon:ClearAllPoints()",
        "skipIcon = true",
    },
    "containers should drop filtered dynamic-layout icons based on the placement hook"
)
assertNotContains(
    containers,
    "ComputeFilterHides",
    "containers should not call broad icon filter helpers directly"
)
assertNotContains(
    containers,
    "OnIconRowConfigApplied(icon, rowConfig)",
    "containers should not split row styling from placed-icon runtime refresh"
)
assertNotContains(
    containers,
    "UpdateIconCooldown",
    "containers should not call low-level icon cooldown refresh directly"
)
assertNotContains(
    containers,
    "ConfigureIcon",
    "containers should not call broad icon configuration helpers"
)
assertContains(
    buffLayout,
    "ns.CDMIcons.OnIconRowConfigApplied(icon, rowConfig)",
    "buff layout should notify CDMIcons when a row config is applied"
)
assertNotContains(
    buffLayout,
    "ConfigureIcon",
    "buff layout should not call broad icon configuration helpers"
)
assertContains(
    factory,
    "icons.OnFactoryMirrorBound(icon, cooldownID, viewerCategory)",
    "factory should notify CDMIcons when a mirror binding is created"
)
assertContains(
    factory,
    "icons.OnFactoryMirrorUnbound(icon)",
    "factory should notify CDMIcons when a mirror binding is cleared"
)
assertNotContains(
    factory,
    "ConfigureIcon",
    "factory should not call broad icon configuration helpers"
)
assertNotContains(
    factory,
    "RegisterBlizzMirrorIcon",
    "factory should not know mirror index registration details"
)
assertNotContains(
    factory,
    "UnregisterBlizzMirrorIcon",
    "factory should not know mirror index unregister details"
)
assertNotContains(
    factory,
    "SeedMirrorStackTextForBinding",
    "factory should not know mirror stack seeding details"
)
assertNotContains(
    factory,
    "OnFactoryMirrorBindingChanged",
    "factory should not call split mirror-binding row-style hooks"
)
assertNotContains(
    containers,
    "UpdateIconSecureAttributes",
    "containers should not call low-level icon secure-attribute helpers"
)
assertContainsOrdered(
    factory,
    {
        "icons.OnFactoryIconCreated(icon, spellEntry)",
        "icons.OnFactoryIconAcquired(icon, spellEntry, true)",
        "icons.OnFactoryIconAcquired(newIcon, spellEntry, false)",
        "icons.OnFactoryIconReleased(icon)",
    },
    "factory should route icon runtime setup/teardown through CDMIcons lifecycle hooks"
)
assertNotContains(
    factory,
    "CancelCooldownExpiryRefresh",
    "factory should not know cooldown-expiry timer cleanup details"
)
assertNotContains(
    factory,
    "StopCustomBarActiveGlow",
    "factory should not know custom-bar active glow teardown details"
)
assertNotContains(
    factory,
    "UpdateIconProfessionQuality",
    "factory should not know profession-quality overlay setup details"
)
assertNotContains(
    factory,
    "UpdateIconSecureAttributes",
    "factory should not know click-to-cast secure attribute setup details"
)
assertNotContains(
    factory,
    "UnmirrorBlizzCooldown",
    "factory should not know icon cooldown mirror runtime teardown details"
)
assertNotContains(
    factory,
    "ClearIconProfessionQuality",
    "factory should not know profession-quality overlay teardown details"
)
assertNotContains(
    factory,
    "ClearClickButtonAttributes",
    "factory should not know click-to-cast secure attribute teardown details"
)
assertNotContains(
    factory,
    "CDMRuntimeStore",
    "factory should not know resolved-state runtime-store teardown details"
)
assertNotContains(
    factory,
    "_OwnedGlows",
    "factory should not know owned-glow runtime teardown details"
)
assertNotContains(
    factory,
    "QUI_ClearKeybindIconState",
    "factory should not know keybind overlay runtime teardown details"
)
assertNotContains(
    factory,
    "IsAuraEntry",
    "factory should not import resolver entry classification for mirror-bind stack seeding"
)
assertNotContains(
    factory,
    "CDMIconFactory" .. ".UpdateIconCooldown",
    "factory should not expose an icon runtime update shim"
)
assertNotContains(
    factory,
    "CDMIconFactory" .. "." .. "_FinalizeImports",
    "factory should not expose late-bound CDMIcons import hooks"
)
assertNotContains(
    factory,
    "local " .. "CDMIcons",
    "factory should not keep a late-bound CDMIcons upvalue"
)
assertNotContains(
    icons,
    "function CDMIcons" .. ":" .. "AcquireIcon",
    "icons should not expose icon frame acquisition"
)
assertNotContains(
    icons,
    "function CDMIcons" .. ":" .. "ReleaseIcon",
    "icons should not expose icon frame release"
)
assertNotContains(
    icons,
    "function CDMIcons" .. ":" .. "GetIconPool",
    "icons should not expose icon pool lookup"
)
assertContains(
    factory,
    "function CDMIconFactory" .. ":" .. "AcquireIcon",
    "factory should own icon frame acquisition"
)
assertContains(
    factory,
    "function CDMIconFactory" .. ":" .. "GetIconPool",
    "factory should own icon pool lookup"
)
assertNotContains(
    resolvers,
    "CDMResolvers" .. "." .. "_FinalizeImports",
    "resolvers should not expose late-bound CDMIcons import hooks"
)
assertNotContains(
    resolvers,
    "CDMIcons",
    "resolved-state ownership should not depend on the icon renderer module"
)
assertContains(
    resolvers,
    "function CDMResolvers.GetCooldownInfoField",
    "resolver should own cooldown-info field access"
)
assertContains(
    resolvers,
    "context.showGCDSwipe",
    "GCD swipe policy should be explicit resolver context"
)
assertNotContains(
    icons,
    "CDMIcons" .. "." .. "ResolveCooldownState",
    "icons should not forward resolved-state fact APIs from CDMResolvers"
)
assertNotContains(
    icons,
    "CDMIcons" .. "." .. "ResolveCooldownActivityState",
    "icons should not expose the resolver activity adapter as a historical forwarder"
)
assertNotContains(
    icons,
    "CDMIcons" .. "." .. "ResolveSpellActiveState",
    "icons should not forward resolver source-query helpers"
)
assertNotContains(
    icons,
    "CDMIcons" .. "." .. "GetCooldownInfoField",
    "icons should not forward resolver cooldown-info helpers"
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
    iconRuntimeRefresh,
    "if comparableSpellID and not spellIDIsGCDSpell and not gcdChanged then",
    "else",
    "targeted cooldown branch"
)
assertContainsOrdered(
    targetedRefreshBlock,
    {
        "controller:QueueResolvedCooldownForSpellID(spellID, baseSpellID)",
    },
    "targeted cooldown refresh should route through the per-spell coalescer"
)

local broadRefreshBlock = extractBlock(
    iconRuntimeRefresh,
    "if gcdChanged or spellIDIsGCDSpell then",
    "controller:ApplySpellScope()",
    "broad cooldown refresh branch"
)
assertContainsOrdered(
    broadRefreshBlock,
    {
        "if gcdChanged or spellIDIsGCDSpell then",
        "controller:InvalidateGCDOnlyBindings()",
    },
    "broad cooldown refresh should only invalidate GCD bindings on real GCD edges"
)

print("OK: cdm_fast_visual_refresh_contract_test")
