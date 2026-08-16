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

local target = { exists = false, friendly = false, attackable = false }
_G.UnitExists = function(unit) return unit == "target" and target.exists end
_G.UnitIsFriend = function(_, unit) return unit == "target" and target.friendly end
_G.UnitCanAttack = function(_, unit) return unit == "target" and target.attackable end

local configured = {}
local function LastConfig(container)
    for i = #configured, 1, -1 do
        if configured[i].container == container then return configured[i] end
    end
end
local ns = {
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
            return { entry.spellID }
        end,
    },
    CDMSources = {
        QuerySpellHelpful = function(spellID) return spellID == 222 or spellID == 333 end,
        QuerySpellHarmful = function(spellID) return spellID == 444 end,
    },
}

assert(loadfile("QUI_CDM/cdm/cdm_layout.lua"))("QUI", ns)
assert(loadfile("QUI_CDM/cdm/cdm_custom_aura_runs.lua"))("QUI", ns)

local settings = {
    builtIn = false,
    containerType = "customBar",
    layoutDirection = "HORIZONTAL",
    growDirection = "RIGHT",
    row1 = { iconCount = 3, iconSize = 30, padding = 2 },
    entries = {
        { id = 111, kind = "cooldown" },
        { id = 222, kind = "aura" },
        { id = 333, kind = "cooldown" },
    },
}

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
}
cooldownB._spellEntry = { spellID = 333, kind = "cooldown" }

local row = {
    size = 30,
    padding = 2,
    aspectRatioCrop = 1,
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

assert(ns.CDMCustomAuraRuns.Apply(owner, settings, plan) == true,
    "eligible mixed rows must use the secure aura run")
assert(#created == 1 and created[1].kind == "AuraContainer"
    and created[1].template == "CustomAuraContainerTemplate",
    "the aura run must use Blizzard's CustomAuraContainerTemplate")
assert(#configured == 1 and #configured[1].groups == 1,
    "one aura occurrence must register one secure group")
assert(configured[1].groups[1].maxFrameCount == 1
    and configured[1].groups[1].candidateFilters.includeSpellIDs[222] == true,
    "the secure group must track the exact aura ID")
assert(configured[1].groups[1].cancelButtons == "RightButtonUp",
    "player buffs must use Blizzard's native right-click cancellation")
assert(configured[1].groups[1].filter == "HELPFUL|PLAYER|INCLUDE_NAME_PLATE_ONLY",
    "helpful entries must use Blizzard's player-cast helpful filter")
local borderColor = configured[1].profile.borderColor
assert(borderColor[1] == 0.2 and borderColor[2] == 0.4
    and borderColor[3] == 0.6 and borderColor[4] == 0.8,
    "the secure aura must resolve the same inherited border color as CDM icons")
assert(auraProxy.shown == false and auraProxy._quiManagedAuraProxy == true,
    "the addon aura proxy must not paint the live aura")

local controller = created[1]
local first = cooldownA.points[1]
local middle = controller.points[1]
local last = cooldownB.points[1]
assert(first[1] == "LEFT" and first[2] == owner and first[3] == "LEFT",
    "the mixed chain must start on the owner")
assert(middle[1] == "LEFT" and middle[2] == cooldownA and middle[3] == "RIGHT",
    "the secure aura run must follow the first cooldown")
assert(last[1] == "LEFT" and last[2] == controller and last[3] == "RIGHT",
    "the second cooldown must follow the secure aura run")
assert(controller.unit == "player" and controller.enabled == true and controller.shown == true,
    "the secure aura run must be live for player buffs")

target.exists, target.friendly, target.attackable = true, true, false
ns.CDMCustomAuraRuns.RefreshTargets()
local friendlyConfig = LastConfig(controller)
assert(controller.unit == "player"
    and friendlyConfig.groups[1].filter == "HELPFUL|PLAYER|INCLUDE_NAME_PLATE_ONLY"
    and friendlyConfig.groups[1].cancelButtons == "RightButtonUp",
    "selfAura helpful entries must remain on the player")

local friendlyOwner = Frame("friendly-owner")
local friendlyProxy = Frame("friendly-proxy")
local friendlyProxyB = Frame("friendly-proxy-b")
friendlyProxy._spellEntry = { spellID = 333, kind = "aura", _useManagedAura = true }
friendlyProxyB._spellEntry = { spellID = 333, kind = "aura", _useManagedAura = true }
local friendlySettings = {
    containerType = "customBar",
    layoutDirection = "HORIZONTAL",
    growDirection = "RIGHT",
    row1 = { iconCount = 1 },
    entries = { { id = 333, kind = "aura" }, { id = 333, kind = "aura" } },
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
    and friendlyConfig.groups[1].maxFrameCount == 1
    and friendlyConfig.groups[1].cancelButtons == nil,
    "non-self helpful entries must activate on friendly targets")
assert(#friendlyConfig.groups == 2 and friendlyConfig.groups[2].groupSpacing == nil
    and friendlyConfig.profile.spacing == 2,
    "adjacent aura groups must use row spacing exactly once")

local harmfulOwner = Frame("harmful-owner")
local harmfulProxy = Frame("harmful-proxy")
harmfulProxy._spellEntry = { spellID = 444, kind = "aura", _useManagedAura = true }
local harmfulSettings = {
    containerType = "customBar",
    layoutDirection = "HORIZONTAL",
    growDirection = "RIGHT",
    row1 = { iconCount = 1 },
    entries = { { id = 444, kind = "aura" } },
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

target.friendly, target.attackable = false, true
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
assert(friendlyCalls == 2 and harmfulCalls == 1,
    "target refreshes must update only changed group capacities")
ns.CDMCustomAuraRuns.RefreshTargets()
assert(#(friendlyController.maxFrameCountCalls or {}) == friendlyCalls
    and #(harmfulController.maxFrameCountCalls or {}) == harmfulCalls,
    "unchanged target refreshes must not mutate secure groups")

local disabledSettings = {
    containerType = "customBar",
    layoutDirection = "VERTICAL",
}
assert(ns.CDMCustomAuraRuns.Apply(owner, disabledSettings, plan) == false,
    "unsupported layouts must leave the secure chain path")
assert(controller.enabled == false and controller.shown == false,
    "leaving the secure chain path must park old aura runs")

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
    inInitSafeWindow = true,
    InCombatLockdown = function() return inCombat end,
}, { __index = _G })
local deferChunk = assert(loadstring(deferSource,
    "@cdm_containers.lua#ShouldDeferContainerLayoutInCombat"))
setfenv(deferChunk, deferEnv)
local shouldDefer = deferChunk()
assert(shouldDefer("custom", settings) == true,
    "custom aura runs must defer creation even during the combat init window")
assert(shouldDefer("custom", {
        containerType = "customBar",
        row1 = { iconCount = 1 },
        entries = { { id = 111, kind = "cooldown" } },
    }) == false,
    "non-aura custom bars must retain the combat init window behavior")
local layoutStart = assert(containersSource:find("local function LayoutContainer(trackerKey)", 1, true))
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

local rendererFile = assert(io.open("QUI_CDM/cdm/cdm_icon_renderer.lua", "rb"))
local rendererSource = rendererFile:read("*a")
rendererFile:close()
assert(rendererSource:find('cdEventFrame:RegisterUnitEvent("UNIT_FACTION", "target")', 1, true),
    "target reaction routing must subscribe to UNIT_FACTION")

print("OK: cdm_custom_aura_runs_test")
