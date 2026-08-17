-- tests/unit/cdm_custom_aura_runs_test.lua
-- Run: lua tests/unit/cdm_custom_aura_runs_test.lua

local created = {}

local function Frame(name)
    local frame = { name = name, points = {}, shown = true }
    function frame:ClearAllPoints() self.points = {} end
    function frame:SetPoint(...) self.points[#self.points + 1] = { ... } end
    function frame:SetSize(w, h) self.width, self.height = w, h end
    function frame:SetUnit(unit) self.unit = unit end
    function frame:SetAuraGroupMaxFrameCount(key, count)
        self.maxFrameCountCalls = self.maxFrameCountCalls or {}
        self.maxFrameCountCalls[#self.maxFrameCountCalls + 1] = { key, count }
    end
    function frame:UpdateAllAuras()
        self.updateAllAurasCalls = (self.updateAllAurasCalls or 0) + 1
    end
    function frame:SetEnabled(enabled) self.enabled = enabled end
    function frame:Show() self.shown = true end
    function frame:Hide() self.shown = false end
    return frame
end

_G.CreateFrame = function(kind, name, parent, template)
    local frame = Frame(name or kind)
    frame.kind = kind
    frame.parent = parent
    frame.template = template
    created[#created + 1] = frame
    return frame
end
_G.issecretvalue = function() return false end

local target = { exists = false, friendly = false, assistable = false, attackable = false }
_G.UnitExists = function(unit) return unit == "target" and target.exists end
_G.UnitIsFriend = function(_, unit) return unit == "target" and target.friendly end
_G.UnitCanAssist = function(_, unit) return unit == "target" and target.assistable end
_G.UnitCanAttack = function(_, unit) return unit == "target" and target.attackable end

local configured = {}
local function LastConfig(container)
    for i = #configured, 1, -1 do
        if configured[i].container == container then return configured[i] end
    end
end
local ns = {
    LSM = {
        Fetch = function(_, kind, name)
            assert(kind == "font")
            return ({ DurationFace = "duration.ttf", StackFace = "stack.ttf" })[name]
        end,
    },
    Helpers = {
        GetSkinBorderColor = function(settings)
            assert(settings.borderColorSource == "inherit")
            return 0.2, 0.4, 0.6, 0.8
        end,
    },
    Addon = {
        db = { profile = { ncdm = {} } },
        AuraSkin = {
            Configure = function(container, profile, groups)
                container._quiProfile = profile
                configured[#configured + 1] = {
                    container = container,
                    profile = profile,
                    groups = groups,
                }
            end,
        },
    },
    CDMManagedAuraMirrors = {
        ResolveCandidateIDs = function(entry)
            return { entry.spellID or entry.id }
        end,
    },
    CDMSpellData = {
        IsSelfAuraSpell = function(_, spellID)
            if spellID == 222 then return true end
            if spellID == 333 or spellID == 444 or spellID == 666 then return false end
        end,
    },
    CDMSources = {
        QuerySpellHelpful = function(spellID)
            return spellID == 222 or spellID == 333 or spellID == 555 or spellID == 666
        end,
        QuerySpellHarmful = function(spellID) return spellID == 444 or spellID == 666 end,
    },
}

assert(loadfile("QUI_CDM/cdm/cdm_layout.lua"))("QUI", ns)
assert(loadfile("QUI_CDM/cdm/cdm_custom_aura_runs.lua"))("QUI", ns)

local settings = {
    builtIn = false,
    containerType = "customBar",
    dynamicLayout = true,
    showOnlyWhenActive = true,
    layoutDirection = "HORIZONTAL",
    growDirection = "RIGHT",
    row1 = {
        iconCount = 3,
        iconSize = 30,
        padding = 2,
        borderColorSource = "inherit",
        borderColor = { 0, 0, 0, 1 },
    },
    entries = {
        { id = 111, kind = "cooldown" },
        { id = 222, kind = "aura", source = "blizzardCDM" },
        { id = 333, kind = "cooldown" },
    },
}

local function CopySettings(changes)
    local copy = {}
    for key, value in pairs(settings) do copy[key] = value end
    for key, value in pairs(changes or {}) do copy[key] = value end
    return copy
end

assert(ns.CDMCustomAuraRuns.ShouldUseSettings(settings) == true,
    "active-only dynamic bars must use secure aura runs")
local unsafeCases = {
    { "default visibility", { showOnlyWhenActive = false } },
    { "on-cooldown visibility", { showOnlyOnCooldown = true } },
    { "off-cooldown visibility", { showOnlyWhenOffCooldown = true } },
    { "combat visibility", { showOnlyInCombat = true } },
    { "usability filtering", { hideNonUsable = true } },
    { "hidden spell overrides", { spellOverrides = { [222] = { hidden = true } } } },
}
for i = 1, #unsafeCases do
    local case = unsafeCases[i]
    assert(ns.CDMCustomAuraRuns.ShouldUseSettings(CopySettings(case[2])) == false,
        case[1] .. " must retain the ordinary proxy renderer")
end

local owner = Frame("owner")
local cooldownA = Frame("cooldown-a")
local auraProxy = Frame("aura-proxy")
local cooldownB = Frame("cooldown-b")
cooldownA._spellEntry = { spellID = 111, kind = "cooldown" }
auraProxy._spellEntry = {
    spellID = 222,
    kind = "aura",
    _useManagedAura = true,
    _selfAura = true,
    _managedAuraRoute = "SELF_HELPFUL",
    source = "blizzardCDM",
}
cooldownB._spellEntry = { spellID = 333, kind = "cooldown" }

local row = {
    size = 30,
    padding = 2,
    aspectRatioCrop = 1.5,
    opacity = 0.45,
    zoom = 0.12,
    durationFont = "DurationFace",
    stackFont = "StackFace",
    borderSize = 1,
    borderColorSource = "inherit",
    borderColor = { 0, 0, 0, 1 },
}
local plan = {
    metrics = { iconWidth = 94 },
    placements = {
        { icon = cooldownA, rowConfig = row, x = -32, y = 0 },
        { icon = auraProxy, rowConfig = row, x = 0, y = 0 },
        { icon = cooldownB, rowConfig = row, x = 32, y = 0 },
    },
}

local fallbackOwner = Frame("fallback-owner")
local fallbackProxy = Frame("fallback-proxy")
fallbackProxy._spellEntry = auraProxy._spellEntry
fallbackProxy:SetPoint("CENTER", fallbackOwner, "CENTER", 0, 0)
local fallbackCreated, fallbackConfigured = #created, #configured
for _, unsafe in ipairs({
    CopySettings({ showOnlyWhenActive = false }),
    CopySettings({ spellOverrides = { [222] = { hidden = true } } }),
}) do
    assert(ns.CDMCustomAuraRuns.Apply(fallbackOwner, unsafe, {
            metrics = { iconWidth = 30 },
            placements = { { icon = fallbackProxy, rowConfig = row, x = 0, y = 0 } },
        }) == false,
        "unsupported visibility settings must leave aura proxies on the ordinary renderer")
end
assert(#created == fallbackCreated and #configured == fallbackConfigured
    and fallbackProxy.shown == true and #fallbackProxy.points == 1
    and fallbackProxy._quiManagedAuraProxy == nil,
    "visibility fallback must preserve the visible proxy without secure allocation")

assert(ns.CDMCustomAuraRuns.Apply(owner, settings, plan) == true,
    "eligible mixed rows must use the secure aura run")
assert(#created == 1 and created[1].kind == "AuraContainer"
    and created[1].template == "CustomAuraContainerTemplate",
    "the aura run must use Blizzard's CustomAuraContainerTemplate")
assert(#configured == 1 and #configured[1].groups == 1,
    "one aura occurrence must register one secure group")
assert(configured[1].groups[1].maxFrameCount == 1
    and configured[1].groups[1].candidateFilters.includeSpellIDs[222] == true
    and configured[1].groups[1].elementWidth == 33
    and configured[1].groups[1].elementSpacing == -1,
    "the secure group must track the exact aura ID")
assert(configured[1].groups[1].cancelButtons == "RightButtonUp",
    "player buffs must use Blizzard's native right-click cancellation")
assert(configured[1].groups[1].filter == "HELPFUL|PLAYER|INCLUDE_NAME_PLATE_ONLY",
    "helpful entries must use Blizzard's player-cast helpful filter")
local borderColor = configured[1].profile.borderColor
assert(borderColor[1] == 0.2 and borderColor[2] == 0.4
    and borderColor[3] == 0.6 and borderColor[4] == 0.8,
    "the secure aura must resolve the same inherited border color as CDM icons")
assert(configured[1].profile.opacity == 0.45
    and configured[1].profile.zoom == 0.12
    and configured[1].profile.aspectRatioCrop == 1.5
    and configured[1].profile.duration.font == "duration.ttf"
    and configured[1].profile.stack.font == "stack.ttf",
    "the secure aura must inherit row opacity, crop, and resolved fonts")
assert(auraProxy.shown == false and auraProxy._quiManagedAuraProxy == true,
    "the addon aura proxy must not paint the live aura")
assert(ns.CDMCustomAuraRuns.ResolveRoute({
        id = 222, kind = "aura", source = "blizzardCDM",
    }) == "SELF_HELPFUL"
    and ns.CDMCustomAuraRuns.ResolveRoute({
        id = 333, kind = "aura", source = "blizzardCDM",
    }) == "HELPFUL"
    and ns.CDMCustomAuraRuns.ResolveRoute({
        id = 444, kind = "aura", source = "blizzardCDM",
    }) == "HARMFUL",
    "catalogued auras must resolve only their proven secure route")
assert(ns.CDMCustomAuraRuns.ResolveRoute({ id = 222, kind = "aura" }) == nil
    and ns.CDMCustomAuraRuns.ResolveRoute({
        id = 555, kind = "aura", source = "blizzardCDM",
    }) == nil
    and ns.CDMCustomAuraRuns.ResolveRoute({
        id = 666, kind = "aura", source = "blizzardCDM",
    }) == nil,
    "manual, uncatalogued, or ambiguous auras must remain on the legacy resolver")

local controller = created[1]
local first = cooldownA.points[1]
local middle = controller.points[1]
local last = cooldownB.points[1]
assert(first[1] == "LEFT" and first[2] == owner and first[3] == "LEFT",
    "the mixed chain must start on the owner")
assert(middle[1] == "LEFT" and middle[2] == cooldownA and middle[3] == "RIGHT",
    "the secure aura run must follow the first cooldown")
assert(middle[4] == 2 and last[1] == "LEFT" and last[2] == controller
    and last[3] == "RIGHT" and last[4] == -1,
    "the second cooldown must follow the secure aura run")
assert(controller.unit == "player" and controller.enabled == true and controller.shown == true,
    "the secure aura run must be live for player buffs")

target.exists, target.friendly, target.assistable, target.attackable = true, true, false, false
ns.CDMCustomAuraRuns.RefreshTargets()
local friendlyConfig = LastConfig(controller)
assert(controller.unit == "player"
    and friendlyConfig.groups[1].filter == "HELPFUL|PLAYER|INCLUDE_NAME_PLATE_ONLY"
    and friendlyConfig.groups[1].cancelButtons == "RightButtonUp",
    "selfAura helpful entries must remain on the player")

local friendlyOwner = Frame("friendly-owner")
local friendlyProxy = Frame("friendly-proxy")
local friendlyProxyB = Frame("friendly-proxy-b")
friendlyProxy._spellEntry = {
    spellID = 333, kind = "aura", _useManagedAura = true,
    _selfAura = false, _managedAuraRoute = "HELPFUL",
    source = "blizzardCDM",
}
friendlyProxyB._spellEntry = {
    spellID = 333, kind = "aura", _useManagedAura = true,
    _selfAura = false, _managedAuraRoute = "HELPFUL",
    source = "blizzardCDM",
}
local friendlySettings = {
    containerType = "customBar",
    dynamicLayout = true,
    showOnlyWhenActive = true,
    layoutDirection = "HORIZONTAL",
    growDirection = "RIGHT",
    row1 = { iconCount = 2 },
    entries = {
        { id = 333, kind = "aura", source = "blizzardCDM" },
        { id = 333, kind = "aura", source = "blizzardCDM" },
    },
}
local friendlyPlan = {
    metrics = { iconWidth = 30 },
    placements = {
        { icon = friendlyProxy, rowConfig = row, x = 0, y = 0 },
        { icon = friendlyProxyB, rowConfig = row, x = 32, y = 0 },
    },
}
assert(ns.CDMCustomAuraRuns.Apply(friendlyOwner, friendlySettings, friendlyPlan) == true)
local friendlyController = friendlyOwner._quiCDMAuraRuns[1]
friendlyConfig = LastConfig(friendlyController)
assert(friendlyController.unit == "target"
    and friendlyConfig.groups[1].filter == "HELPFUL|PLAYER|INCLUDE_NAME_PLATE_ONLY"
    and friendlyConfig.groups[1].maxFrameCount == 0
    and friendlyConfig.groups[1].cancelButtons == nil,
    "non-self helpful entries must park on friendly but unassistable targets")
local friendlyConfiguredBefore = #configured
target.assistable = true
ns.CDMCustomAuraRuns.RefreshTargets()
assert(#configured == friendlyConfiguredBefore
    and friendlyConfig.groups[1].maxFrameCount == 1
    and #(friendlyController.maxFrameCountCalls or {}) == 2
    and friendlyController.updateAllAurasCalls == 1,
    "non-self helpful entries must activate without rebuilding when the target is assistable")
local friendlyCallsBeforeTargetSwitch = #(friendlyController.maxFrameCountCalls or {})
ns.CDMCustomAuraRuns.RefreshTargets(true)
assert(friendlyController.updateAllAurasCalls == 2
    and controller.updateAllAurasCalls == nil
    and #(friendlyController.maxFrameCountCalls or {}) == friendlyCallsBeforeTargetSwitch,
    "same-reaction target changes must refresh auras without mutating group capacity")
assert(#friendlyConfig.groups == 2
    and friendlyConfig.groups[2].elementWidth == 33
    and friendlyConfig.groups[2].elementSpacing == -1
    and friendlyConfig.profile.spacing == 2,
    "adjacent aura groups must use row spacing exactly once")

local harmfulOwner = Frame("harmful-owner")
local harmfulProxy = Frame("harmful-proxy")
harmfulProxy._spellEntry = {
    spellID = 444, kind = "aura", _useManagedAura = true,
    _selfAura = false, _managedAuraRoute = "HARMFUL",
    source = "blizzardCDM",
}
local harmfulSettings = {
    containerType = "customBar",
    dynamicLayout = true,
    showOnlyWhenActive = true,
    layoutDirection = "HORIZONTAL",
    growDirection = "RIGHT",
    row1 = { iconCount = 1 },
    entries = { { id = 444, kind = "aura", source = "blizzardCDM" } },
}
local harmfulPlan = {
    metrics = { iconWidth = 30 },
    placements = { { icon = harmfulProxy, rowConfig = row, x = 0, y = 0 } },
}
assert(ns.CDMCustomAuraRuns.Apply(harmfulOwner, harmfulSettings, harmfulPlan) == true)
local harmfulController = harmfulOwner._quiCDMAuraRuns[1]
local harmfulConfig = LastConfig(harmfulController)
assert(harmfulController.unit == "target" and harmfulConfig.groups[1].maxFrameCount == 0,
    "harmful entries must park on friendly targets")

target.friendly, target.assistable, target.attackable = false, false, true
local configuredBeforeRefresh = #configured
ns.CDMCustomAuraRuns.RefreshTargets()
assert(#configured == configuredBeforeRefresh,
    "target refreshes must not rebuild secure aura layouts")
harmfulConfig = LastConfig(harmfulController)
assert(harmfulController.unit == "target"
    and harmfulConfig.groups[1].filter == "HARMFUL|PLAYER"
    and harmfulConfig.groups[1].maxFrameCount == 1
    and harmfulConfig.groups[1].cancelButtons == nil,
    "harmful entries must activate only for enemy targets")
friendlyConfig = LastConfig(friendlyController)
assert(friendlyConfig.groups[1].maxFrameCount == 0,
    "non-self helpful entries must park on enemy targets")
local friendlyCalls = #(friendlyController.maxFrameCountCalls or {})
local harmfulCalls = #(harmfulController.maxFrameCountCalls or {})
assert(friendlyCalls == 4 and harmfulCalls == 1
    and friendlyController.updateAllAurasCalls == 3
    and harmfulController.updateAllAurasCalls == 1,
    "target refreshes must update only changed group capacities")
local friendlyFullRefreshes = friendlyController.updateAllAurasCalls
ns.CDMCustomAuraRuns.RefreshTargets(true)
assert(friendlyController.updateAllAurasCalls == friendlyFullRefreshes + 1
    and harmfulController.updateAllAurasCalls == 2
    and #(friendlyController.maxFrameCountCalls or {}) == friendlyCalls
    and #(harmfulController.maxFrameCountCalls or {}) == harmfulCalls,
    "same-reaction hostile target changes must refresh every target run without capacity changes")
local friendlyUnchangedRefreshes = friendlyController.updateAllAurasCalls
local harmfulUnchangedRefreshes = harmfulController.updateAllAurasCalls
ns.CDMCustomAuraRuns.RefreshTargets()
assert(#(friendlyController.maxFrameCountCalls or {}) == friendlyCalls
    and #(harmfulController.maxFrameCountCalls or {}) == harmfulCalls
    and friendlyController.updateAllAurasCalls == friendlyUnchangedRefreshes
    and harmfulController.updateAllAurasCalls == harmfulUnchangedRefreshes,
    "unchanged target refreshes must not mutate secure groups")

local disabledSettings = {
    containerType = "customBar",
    dynamicLayout = true,
    showOnlyWhenActive = true,
    layoutDirection = "VERTICAL",
}
assert(ns.CDMCustomAuraRuns.Apply(owner, disabledSettings, plan) == false,
    "unsupported layouts must leave the secure chain path")
assert(controller.enabled == false and controller.shown == false,
    "leaving the secure chain path must park old aura runs")

local fixedSettings = {
    containerType = "customBar",
    showOnlyWhenActive = true,
    layoutDirection = "HORIZONTAL",
    growDirection = "RIGHT",
    row1 = { iconCount = 1 },
    entries = { { id = 222, kind = "aura", source = "blizzardCDM" } },
}
assert(ns.CDMCustomAuraRuns.ShouldUseSettings(fixedSettings) == false,
    "default fixed-slot bars must keep their ordinary aura proxies")
fixedSettings.dynamicLayout = false
fixedSettings.clickableIcons = true
assert(ns.CDMCustomAuraRuns.ShouldUseSettings(fixedSettings) == false,
    "clickable fixed-slot bars must keep their secure click proxies")
local fixedOwner = Frame("fixed-owner")
local fixedProxy = Frame("fixed-proxy")
fixedProxy._spellEntry = {
    spellID = 222, kind = "aura", _useManagedAura = true,
    _selfAura = true, _managedAuraRoute = "SELF_HELPFUL",
    source = "blizzardCDM",
}
fixedProxy:SetPoint("CENTER", fixedOwner, "CENTER", 0, 0)
local fixedClickButton = {}
fixedProxy.clickButton = fixedClickButton
local fixedCreated, fixedConfigured = #created, #configured
assert(ns.CDMCustomAuraRuns.Apply(fixedOwner, fixedSettings, {
        metrics = { iconWidth = 30 },
        placements = { { icon = fixedProxy, rowConfig = row, x = 0, y = 0 } },
    }) == false,
    "fixed-slot aura bars must stay on the ordinary renderer")
assert(#created == fixedCreated and #configured == fixedConfigured
    and fixedProxy.shown == true and #fixedProxy.points == 1
    and fixedProxy._quiManagedAuraProxy == nil and fixedProxy.clickButton == fixedClickButton,
    "fixed-slot fallback must preserve the visible slot and click surface")

assert(ns.CDMCustomAuraRuns.Apply(owner, settings, plan) == true)
local containersFile = assert(io.open("QUI_CDM/cdm/cdm_containers.lua", "rb"))
local containersSource = containersFile:read("*a")
containersFile:close()
local deferStart = assert(containersSource:find(
    "local function ShouldDeferContainerLayoutInCombat", 1, true))
local deferStop = assert(containersSource:find(
    "\nlocal function GetDefaultsByContainerType", deferStart, true))
local deferSource = containersSource:sub(deferStart, deferStop - 1)
deferSource = deferSource:gsub(
    "^local function ShouldDeferContainerLayoutInCombat", "return function", 1)
local inCombat = true
local deferEnv = setmetatable({
    ns = ns,
    containers = { custom = owner, plain = Frame("plain-owner") },
    inInitSafeWindow = true,
    InCombatLockdown = function() return inCombat end,
}, { __index = _G })
local deferChunk = assert(loadstring(deferSource,
    "@cdm_containers.lua#ShouldDeferContainerLayoutInCombat"))
setfenv(deferChunk, deferEnv)
local shouldDefer = deferChunk()
assert(shouldDefer("custom", settings) == true,
    "custom aura runs must defer creation even during the combat init window")
assert(shouldDefer("plain", {
        containerType = "customBar",
        row1 = { iconCount = 1 },
        entries = { { id = 111, kind = "cooldown" } },
    }) == false,
    "non-aura custom bars must retain the combat init window behavior")
local layoutStart = assert(containersSource:find(
    "local function LayoutContainer(trackerKey, runtimeVisibilityRelayout)", 1, true))
local layoutStop = assert(containersSource:find("\nlocal function RunPostLayoutRefresh()", layoutStart, true))
local layoutSource = containersSource:sub(layoutStart, layoutStop - 1)
layoutSource = layoutSource:gsub("^local function LayoutContainer", "return function", 1)
local globals = _G
local layoutEnv = setmetatable({
    ns = ns,
    containers = { custom = owner },
    viewerState = {},
    applying = {},
    BUILTIN_NAMES = {},
    CDMLayout = ns.CDMLayout,
    CDMContainers_API = { HUD_LAYERING = { keys = {}, viewers = {} } },
    Helpers = { IsEditModeActive = function() return false end },
    IsCDMRuntimeEnabled = function() return true end,
    GetTrackerSettings = function() return settings end,
    ShouldDeferContainerLayoutInCombat = shouldDefer,
    GetHUDMinWidth = function() return false, 0 end,
    ApplyViewerMetrics = function() return 94, 30 end,
    RefreshCustomBarRuntimeAfterLayout = function() end,
    C_Timer = { After = function() end },
    InCombatLockdown = function() return inCombat end,
}, { __index = globals })
layoutEnv._G = layoutEnv
local layoutChunk = assert(loadstring(layoutSource, "@cdm_containers.lua#LayoutContainer"))
setfenv(layoutChunk, layoutEnv)
local priorIcons = ns.CDMIcons
local buildCalls = 0
ns.CDMIcons = { BuildIcons = function()
    buildCalls = buildCalls + 1
    return {}
end }
local createdBeforeCombat = #created
local configuredBeforeCombat = #configured
layoutChunk()("custom")
assert(layoutEnv.specTrackingPendingRefresh == true and buildCalls == 0
    and #created == createdBeforeCombat and #configured == configuredBeforeCombat,
    "combat deferral must queue refresh without creating secure frames")
inCombat = false
layoutChunk()("custom")
ns.CDMIcons = priorIcons
assert(controller.enabled == false and controller.shown == false,
    "an empty container layout must park stale secure aura runs")

local mixedSettings = {
    containerType = "customBar",
    dynamicLayout = true,
    showOnlyWhenActive = true,
    layoutDirection = "HORIZONTAL",
    growDirection = "RIGHT",
    row1 = {
        iconCount = 3,
        iconSize = 30,
        padding = 2,
        borderColorSource = "inherit",
        borderColor = { 0, 0, 0, 1 },
    },
    entries = {
        { id = 222, kind = "aura", source = "blizzardCDM" },
        { id = 111, kind = "cooldown" },
        { id = 222, kind = "aura", source = "blizzardCDM" },
    },
}
local mixedOwner = Frame("mixed-owner")
local mixedAuraA = Frame("mixed-aura-a")
local mixedCooldown = Frame("mixed-cooldown")
local mixedAuraB = Frame("mixed-aura-b")
mixedAuraA._spellEntry = auraProxy._spellEntry
mixedCooldown._spellEntry = cooldownA._spellEntry
mixedAuraB._spellEntry = auraProxy._spellEntry
local mixedIcons = { mixedAuraA, mixedCooldown, mixedAuraB }
local mixedRow = ns.CDMLayout.BuildRows(mixedSettings)[1]
local mixedCreatedBefore = #created
local mixedConfiguredBefore = #configured
local preparedIcons = {}
local prepareCalls = 0
local combatBuilds = 0
local reusablePool = true
local showMixedCooldown = false
deferEnv.containers.custom = mixedOwner
layoutEnv.containers.custom = mixedOwner
layoutEnv.GetTrackerSettings = function() return mixedSettings end
layoutEnv.viewerState = {}
layoutEnv.specTrackingPendingRefresh = false
ns.CDMIcons = {
    BuildIcons = function(_, _, _, reuseOnly)
        if inCombat then
            assert(reuseOnly == true)
            combatBuilds = combatBuilds + 1
        end
        return reusablePool and mixedIcons or nil
    end,
    ShouldContainerLayoutPlaceIcon = function(icon, entry)
        return entry._useManagedAura == true or showMixedCooldown
    end,
    OnIconRowConfigApplied = function(icon, rowConfig)
        assert(not inCombat and rowConfig.size == mixedRow.size)
        preparedIcons[icon] = true
        prepareCalls = prepareCalls + 1
    end,
    OnContainerIconPlaced = function(icon)
        assert(preparedIcons[icon], "combat-visible icons must be configured out of combat")
    end,
}
inCombat = false
layoutChunk()("custom")
local mixedRecords = mixedOwner._quiCDMAuraRunRecords
assert(#mixedRecords == 2 and #created == mixedCreatedBefore + 2
    and #configured == mixedConfiguredBefore + 2
    and mixedRecords[1].rowConfig.size == mixedRow.size
    and prepareCalls == 3 and preparedIcons[mixedCooldown] == true,
    "hidden ordinary icons must split the preallocated aura-run topology")

inCombat = true
layoutEnv.specTrackingPendingRefresh = false
showMixedCooldown = true
local combatCreatedBefore = #created
local combatConfiguredBefore = #configured
layoutChunk()("custom", true)
assert(layoutEnv.specTrackingPendingRefresh ~= true and combatBuilds == 1
    and prepareCalls == 3
    and #created == combatCreatedBefore and #configured == combatConfiguredBefore,
    "prepared visibility relayouts must not create or configure secure frames in combat")
assert(mixedCooldown.points[1][2] == mixedRecords[1].container
    and mixedRecords[2].container.points[1][2] == mixedCooldown,
    "combat visibility relayouts must insert ordinary icons between stable aura runs")
local mixedCooldownPoints = #mixedCooldown.points
reusablePool = false
layoutEnv.specTrackingPendingRefresh = false
layoutChunk()("custom", true)
assert(layoutEnv.specTrackingPendingRefresh == true and combatBuilds == 2
    and #mixedCooldown.points == mixedCooldownPoints
    and #created == combatCreatedBefore and #configured == combatConfiguredBefore,
    "stale combat icon pools must defer before mutating layout or secure runs")
layoutChunk()("custom")
assert(layoutEnv.specTrackingPendingRefresh == true and combatBuilds == 2,
    "structural combat layouts must remain deferred")
inCombat = false
ns.CDMIcons = priorIcons

local rendererFile = assert(io.open("QUI_CDM/cdm/cdm_icon_renderer.lua", "rb"))
local rendererSource = rendererFile:read("*a")
rendererFile:close()
assert(rendererSource:find('cdEventFrame:RegisterUnitEvent("UNIT_FACTION", "target")', 1, true),
    "target reaction routing must subscribe to UNIT_FACTION")
assert(rendererSource:find('cdEventFrame:RegisterEvent("PLAYER_SOFT_FRIEND_CHANGED")', 1, true),
    "helpful target routing must subscribe to soft friendly target changes")
assert(rendererSource:find("QUI_ForceLayoutContainer(trackerKey, true)", 1, true),
    "visibility policy relayouts must identify their combat-safe runtime path")

print("OK: cdm_custom_aura_runs_test")
