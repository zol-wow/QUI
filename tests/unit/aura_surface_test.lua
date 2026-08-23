local function fail(msg)
    print("FAIL: aura_surface_test - " .. msg)
    os.exit(1)
end
local function noop() end

local created = 0
local nilContainer = false
CreateFrame = function(kind, _name, parent)
    if kind ~= "AuraContainer" and kind ~= "Frame" then return nil end
    if nilContainer then return nil end
    if kind == "AuraContainer" then created = created + 1 end
    local c = {
        _parent = parent, _shown = false, _enabled = nil, _unit = nil,
        _points = {}, _index = created, _frameLevel = kind == "AuraContainer" and 5 or 0,
        SetSize = noop, ClearAllPoints = noop,
        GetFrameLevel = function(self) return self._frameLevel end,
        SetFrameLevel = function(self, level) self._frameLevel = level end,
        SetPoint = function(self, ...) self._points[#self._points + 1] = { ... } end,
        SetUnit = function(self, u) self._unit = u end,
        SetEnabled = function(self, v) self._enabled = v end,
        Show = function(self) self._shown = true end,
        Hide = function(self) self._shown = false end,
    }
    return c
end

local ns = {}
local configureCalls, syncCalls, inactiveCalls, parkCalls = {}, {}, {}, {}
local nextConfigureResult, nextSyncResult = true, true

ns.AuraGlue = {
    RunConfigPass = function(container, profile, groups, allowCreate)
        configureCalls[#configureCalls + 1] = {
            container = container, profile = profile,
            groups = groups, allowCreate = allowCreate,
        }
        return nextConfigureResult
    end,
    ElementGroups = function(unit, element, _profile, cancelEligible)
        return { { key = "g", unit = unit, mode = element.mode, cancel = cancelEligible } }
    end,
}
ns.AuraSlots = {
    Sync = function(container, element, allowCreate, overrides)
        syncCalls[#syncCalls + 1] = {
            container = container, element = element,
            allowCreate = allowCreate, overrides = overrides,
        }
        return nextSyncResult
    end,
    SyncInactiveIcons = function(container, element, allowCreate, shown)
        inactiveCalls[#inactiveCalls + 1] = {
            container = container, element = element,
            allowCreate = allowCreate, shown = shown,
        }
        return true
    end,
    HideInactiveIcons = noop,
    Park = function(container) parkCalls[#parkCalls + 1] = container end,
}

assert(loadfile("core/aura_surface.lua"))("QUI", ns)
local S = ns.AuraSurface
if not S or type(S.ApplyElementPass) ~= "function" then
    fail("ns.AuraSurface.ApplyElementPass must be exported")
end

local function NewHost() return { _quiAuraContainers = nil } end
local function BaseOpts(over)
    local o = {
        unit = "player",
        allowCreate = true,
        profileFor = function(element) return { tag = element.tag } end,
        anchorContainer = function(container, _host, element)
            container:SetPoint("TOPLEFT", element.tag)
        end,
    }
    for k, v in pairs(over or {}) do o[k] = v end
    return o
end

local strip = { mode = "filterStrip", tag = "s1" }
local tracked = { mode = "tracked", tag = "t1" }

local host = NewHost()
local ok = S.ApplyElementPass(host, { strip, tracked }, BaseOpts())
if ok ~= true then fail("clean pass must return true") end
if #host._quiAuraContainers ~= 2 then
    fail("pool must hold one container per element, got " .. #host._quiAuraContainers)
end
if host._quiAuraContainers[1]._unit ~= "player" then fail("SetUnit must be called") end
if #syncCalls ~= 1 then fail("tracked element must call AuraSlots.Sync once, got " .. #syncCalls) end
if syncCalls[1].element ~= tracked then fail("Sync must receive the tracked element") end
if #parkCalls ~= 1 then fail("filterStrip element must Park its slots, got " .. #parkCalls) end
if #configureCalls ~= 2 then
    fail("both elements must reach RunConfigPass, got " .. #configureCalls)
end
if not host._quiAuraContainers[1]._shown then fail("active containers must be shown") end

local shrunk = S.ApplyElementPass(host, { strip }, BaseOpts())
if shrunk ~= true then fail("shrinking the list must still return true") end
if host._quiAuraContainers[2]._shown ~= false then fail("tail container must be hidden") end
if host._quiAuraContainers[2]._enabled ~= false then fail("tail container must be disabled") end
if #host._quiAuraContainers ~= 2 then fail("pool must be retained, not truncated") end

local skipped = NewHost()
S.ApplyElementPass(skipped, { strip }, BaseOpts({ skip = function() return true end }))
if skipped._quiAuraContainers[1]._enabled ~= false then
    fail("skip must disable the container")
end
if skipped._quiAuraContainers[1]._shown ~= false then
    fail("skip must hide the container")
end

local incompleteHost = NewHost()
local reported = 0
nextConfigureResult = false
local res = S.ApplyElementPass(incompleteHost, { strip },
    BaseOpts({ onIncomplete = function() reported = reported + 1 end }))
nextConfigureResult = true
if res ~= false then fail("RunConfigPass failure must return false") end
if reported ~= 1 then fail("onIncomplete must fire exactly once, got " .. reported) end

local syncFailHost = NewHost()
nextSyncResult = false
local res2 = S.ApplyElementPass(syncFailHost, { tracked }, BaseOpts())
nextSyncResult = true
if res2 ~= false then fail("AuraSlots.Sync failure must mark the pass incomplete") end

local readyHost = NewHost()
local res3 = S.ApplyElementPass(readyHost, { strip }, BaseOpts({
    onContainerReady = function() return false end,
}))
if res3 ~= false then fail("onContainerReady returning false must mark incomplete") end

local noCreateHost = NewHost()
local res4 = S.ApplyElementPass(noCreateHost, { strip }, BaseOpts({ allowCreate = false }))
if res4 ~= false then fail("missing container with allowCreate=false must be incomplete") end

local nilCreateHost = NewHost()
nilContainer = true
local okCall, res5 = pcall(S.ApplyElementPass, nilCreateHost, { strip }, BaseOpts())
nilContainer = false
if not okCall then fail("CreateFrame returning nil must not error: " .. tostring(res5)) end
if res5 ~= false then fail("CreateFrame returning nil must mark the pass incomplete") end
if #nilCreateHost._quiAuraContainers ~= 0 then
    fail("CreateFrame returning nil must not populate the pool slot")
end

local overrideHost = NewHost()
local marker = { over = true }
S.ApplyElementPass(overrideHost, { tracked }, BaseOpts({ profileOverrides = marker }))
if syncCalls[#syncCalls].overrides ~= marker then
    fail("profileOverrides must be forwarded to AuraSlots.Sync")
end

local inactiveHost = NewHost()
S.ApplyElementPass(inactiveHost, { tracked }, BaseOpts({ showInactive = true }))
local inactiveCall = inactiveCalls[#inactiveCalls]
if not inactiveCall or inactiveCall.container._parent ~= inactiveHost
    or inactiveCall.container == inactiveHost._quiAuraContainers[1]
    or inactiveCall.element ~= tracked or inactiveCall.shown ~= true then
    fail("showInactive must reconcile host-owned inactive tracked icons")
end
if inactiveCall.container:GetFrameLevel() >= inactiveHost._quiAuraContainers[1]:GetFrameLevel() then
    fail("inactive tracked icons must stay below the native AuraContainer")
end

if S.ApplyElementPass(nil, {}, BaseOpts()) ~= false then fail("nil host must return false") end
if S.ApplyElementPass(NewHost(), {}, { unit = nil }) ~= false then fail("missing unit must return false") end

print("PASS: aura_surface_test")
