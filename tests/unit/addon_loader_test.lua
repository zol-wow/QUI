-- Verifies core/addon_loader.lua: flag resolution, LOD load gating,
-- staggered loading, and the toggle helper's Enable/Disable/Load calls.
-- Standalone: stubs ns + C_AddOns; loads manifest + loader via loadfile.

local function newEnv()
    local calls = {}
    local state = { loaded = {}, enabled = {}, exists = {}, loadFails = {} }
    -- Capture the most recently created frame stub so tests can fire its events.
    local lastFrame
    _G.CreateFrame = function()
        local frame = { _events = {}, _scripts = {} }
        function frame:RegisterEvent(evt) self._events[evt] = true end
        function frame:UnregisterEvent(evt) self._events[evt] = nil end
        function frame:SetScript(name, fn) self._scripts[name] = fn end
        function frame:FireEvent(evt)
            if self._scripts["OnEvent"] then self._scripts["OnEvent"](self, evt) end
        end
        lastFrame = frame
        return frame
    end
    _G.C_AddOns = {
        DoesAddOnExist = function(n) return state.exists[n] ~= false end,
        IsAddOnLoaded = function(n) return state.loaded[n] == true end,
        -- Accept optional second arg (character name) per fix 4; ignore it in stub.
        GetAddOnEnableState = function(n, _char)
            if state.enabled[n] == false then return 0 end
            return 2
        end,
        EnableAddOn  = function(n) calls[#calls+1] = "enable:"..n;  state.enabled[n] = true  end,
        DisableAddOn = function(n) calls[#calls+1] = "disable:"..n; state.enabled[n] = false end,
        SaveAddOns   = function()  calls[#calls+1] = "save" end,
        LoadAddOn = function(n)
            calls[#calls+1] = "load:"..n
            if state.loadFails[n] then return nil, "DEP_MISSING" end
            if state.enabled[n] == false then return nil, "DISABLED" end
            state.loaded[n] = true
            return true
        end,
    }
    -- C_Timer.After runs synchronously in tests (stagger collapses to in-order)
    -- UNLESS InCombatLockdown returns true, in which case step() parks and returns.
    _G.C_Timer = { After = function(_, fn) fn() end }
    _G.InCombatLockdown = function() return false end
    _G.UnitName = function() return "TestPlayer", nil end
    local ns = {
        QUI_Modules = { notified = {}, NotifyChanged = function(self, id)
            self.notified[#self.notified+1] = id
        end },
        RunAfterFirstFrame = function(fn) fn() end,
        WhenLoggedIn = function(fn) fn() end,
    }
    return ns, calls, state, function() return lastFrame end
end

local function loadLoader(ns)
    local manifest = assert(loadfile("core/addon_manifest.lua"))("QUI", ns)
    assert(type(manifest) == "table" and #manifest > 0, "manifest returns entries")
    assert(loadfile("core/addon_loader.lua"))("QUI", ns)
    assert(ns.AddonLoader, "ns.AddonLoader set")
    return ns.AddonLoader
end

-- 1) Manifest shape: 10 entries, classes valid, folders unique
do
    local ns = newEnv()
    loadLoader(ns)
    local seen, lod, login = {}, 0, 0
    for _, e in ipairs(ns.AddonManifest) do
        assert(type(e.folder) == "string" and e.folder:match("^QUI_"), "folder name")
        assert(not seen[e.folder], "unique folder"); seen[e.folder] = true
        assert(e.class == "login" or e.class == "lod", "class")
        assert(type(e.sources) == "table" and #e.sources > 0, "sources")
        if e.class == "lod" then lod = lod + 1 else login = login + 1 end
    end
    assert(login == 6, "6 login-class entries, got " .. login)
    assert(lod == 4, "4 lod entries, got " .. lod)
end

-- 2) Flag resolution: nested paths + nil flag means "on"
do
    local ns = newEnv()
    local loader = loadLoader(ns)
    local profile = { damageMeter = { native = { enabled = false } }, minimap = { enabled = true } }
    assert(loader.IsFlagOn(profile, { "minimap", "enabled" }) == true)
    assert(loader.IsFlagOn(profile, { "damageMeter", "native", "enabled" }) == false)
    assert(loader.IsFlagOn(profile, nil) == true, "no flag = on")
    assert(loader.IsFlagOn(profile, { "absent", "enabled" }) == true, "missing table = default on")
end

-- 3) LOD stagger: loads exactly the flag-on modules in manifest order, pings QUI_Modules
-- QUI_Minimap now has flag=nil (always loads); exclude DamageMeter by flag instead.
do
    local ns, calls = newEnv()
    local loader = loadLoader(ns)
    loader.GetProfile = function() return { damageMeter = { native = { enabled = false } } } end
    loader:LoadEnabledLODModules()
    local loads = {}
    for _, c in ipairs(calls) do if c:match("^load:") then loads[#loads+1] = c end end
    -- DamageMeter is excluded by flag; the remaining three load in manifest order.
    assert(#loads == 3, "expected 3 loads (no damagemeter), got " .. #loads)
    assert(loads[1] == "load:QUI_Skinning", "1st: skinning, got "  .. tostring(loads[1]))
    assert(loads[2] == "load:QUI_Minimap",  "2nd: minimap, got "   .. tostring(loads[2]))
    assert(loads[3] == "load:QUI_QoL",      "3rd: qol, got "       .. tostring(loads[3]))
    assert(#ns.QUI_Modules.notified == 3, "one notify per load")
end

-- 4) Toggle helper: lod enable = Enable+Load now; login enable = reload; disable = reload;
--    LoadAddOn failure returns "reload"; SaveAddOns called after Enable/Disable.
do
    local ns, calls, state = newEnv()
    local loader = loadLoader(ns)

    -- enable a disabled LOD module: Enable → Load → "loaded", SaveAddOns called
    state.enabled.QUI_Skinning = false
    assert(loader.SetModuleAddonEnabled("QUI_Skinning", true) == "loaded")
    assert(calls[1] == "enable:QUI_Skinning", "1st call enable")
    assert(calls[2] == "save",                "2nd call save after enable")
    assert(calls[3] == "load:QUI_Skinning",   "3rd call load")

    -- disable a login-class module → "reload", SaveAddOns called
    -- Clear in-place so the C_AddOns stubs (which close over the same table) see the reset.
    for k in pairs(calls) do calls[k] = nil end
    assert(loader.SetModuleAddonEnabled("QUI_UnitFrames", false) == "reload")
    assert(calls[1] == "disable:QUI_UnitFrames", "disable call")
    assert(calls[2] == "save",                   "save after disable")

    -- enable a login-class (already loaded) → "reload"
    assert(loader.SetModuleAddonEnabled("QUI_UnitFrames", true) == "reload")

    -- missing addon
    state.exists.QUI_Chat = false
    assert(loader.SetModuleAddonEnabled("QUI_Chat", true) == "missing")

    -- LOD enable whose LoadAddOn fails → "reload"
    state.enabled.QUI_QoL = false
    state.loaded.QUI_QoL  = nil
    state.loadFails.QUI_QoL = true
    assert(loader.SetModuleAddonEnabled("QUI_QoL", true) == "reload",
        "LoadAddOn failure must return reload")
end

-- 5) Combat parking: no loads during lockdown; all drain after PLAYER_REGEN_ENABLED
do
    local ns, calls, state, getLastFrame = newEnv()
    local loader = loadLoader(ns)
    loader.GetProfile = function() return {} end  -- all flags on (nil flag = on)

    -- Enter simulated combat before the stagger starts.
    _G.InCombatLockdown = function() return true end

    loader:LoadEnabledLODModules()
    -- The first step() should have parked immediately — no load calls.
    local loadsBefore = {}
    for _, c in ipairs(calls) do if c:match("^load:") then loadsBefore[#loadsBefore+1] = c end end
    assert(#loadsBefore == 0, "no loads during combat, got " .. #loadsBefore)

    -- The frame must have registered for PLAYER_REGEN_ENABLED.
    local frame = getLastFrame()
    assert(frame, "regenResumeFrame created")
    assert(frame._events["PLAYER_REGEN_ENABLED"], "registered PLAYER_REGEN_ENABLED")

    -- Leave combat and fire the event; C_Timer.After is still synchronous so
    -- the remaining chain drains immediately.
    _G.InCombatLockdown = function() return false end
    frame:FireEvent("PLAYER_REGEN_ENABLED")

    -- All 4 LOD modules (all flags on) must now be loaded in manifest order.
    local loadsAfter = {}
    for _, c in ipairs(calls) do if c:match("^load:") then loadsAfter[#loadsAfter+1] = c end end
    assert(#loadsAfter == 4, "all 4 lod modules loaded after regen, got " .. #loadsAfter)
    assert(loadsAfter[1] == "load:QUI_Skinning",    "post-regen 1st: skinning")
    assert(loadsAfter[2] == "load:QUI_Minimap",     "post-regen 2nd: minimap")
    assert(loadsAfter[3] == "load:QUI_QoL",         "post-regen 3rd: qol")
    assert(loadsAfter[4] == "load:QUI_DamageMeter", "post-regen 4th: damagemeter")

    -- Frame must have unregistered after draining.
    assert(not frame._events["PLAYER_REGEN_ENABLED"], "unregistered after drain")
end

-- 6) Combat guard on SetModuleAddonEnabled: enabling a LOD addon mid-combat
--    records EnableAddOn+SaveAddOns but skips LoadNow, returns "reload".
--    Out of combat: LoadNow fires and returns "loaded".
do
    -- In-combat path: no "load:" call, returns "reload"
    do
        local ns, calls, state = newEnv()
        local loader = loadLoader(ns)
        state.enabled.QUI_Skinning = false
        _G.InCombatLockdown = function() return true end
        local result = loader.SetModuleAddonEnabled("QUI_Skinning", true)
        assert(result == "reload", "in-combat LOD enable must return 'reload', got " .. tostring(result))
        local hasLoad = false
        for _, c in ipairs(calls) do if c:match("^load:") then hasLoad = true end end
        assert(not hasLoad, "in-combat LOD enable must not call LoadAddOn")
        -- EnableAddOn and SaveAddOns still recorded
        assert(calls[1] == "enable:QUI_Skinning", "EnableAddOn still called in combat")
        assert(calls[2] == "save",                "SaveAddOns still called in combat")
        _G.InCombatLockdown = function() return false end
    end

    -- Out-of-combat path: LoadNow fires, returns "loaded"
    do
        local ns, calls, state = newEnv()
        local loader = loadLoader(ns)
        state.enabled.QUI_Skinning = false
        _G.InCombatLockdown = function() return false end
        local result = loader.SetModuleAddonEnabled("QUI_Skinning", true)
        assert(result == "loaded", "out-of-combat LOD enable must return 'loaded', got " .. tostring(result))
        local hasLoad = false
        for _, c in ipairs(calls) do if c:match("^load:") then hasLoad = true end end
        assert(hasLoad, "out-of-combat LOD enable must call LoadAddOn")
    end
end

-- 7) Anchoring catch-up: RegisterAllFrameTargets + ApplyAllFrameAnchors called
--    exactly once after a stagger that loaded ≥1 module; NOT called when nothing loaded.
do
    -- 7a) At least one load → both anchoring methods called exactly once.
    do
        local ns, calls, state = newEnv()
        local loader = loadLoader(ns)
        loader.GetProfile = function() return {} end  -- all flags on
        local anchorCalls = {}
        ns.QUI_Anchoring = {
            RegisterAllFrameTargets = function(self) anchorCalls[#anchorCalls+1] = "register" end,
            ApplyAllFrameAnchors    = function(self) anchorCalls[#anchorCalls+1] = "apply" end,
        }
        loader:LoadEnabledLODModules()
        assert(#anchorCalls == 2, "expect 2 anchoring calls after stagger, got " .. #anchorCalls)
        assert(anchorCalls[1] == "register", "RegisterAllFrameTargets called first")
        assert(anchorCalls[2] == "apply",    "ApplyAllFrameAnchors called second")
    end

    -- 7b) Nothing eligible (all already loaded) → anchoring methods NOT called.
    do
        local ns, calls, state = newEnv()
        -- Mark all LOD modules as already loaded so nothing gets enqueued.
        state.loaded.QUI_Skinning    = true
        state.loaded.QUI_Minimap     = true
        state.loaded.QUI_QoL         = true
        state.loaded.QUI_DamageMeter = true
        local loader = loadLoader(ns)
        loader.GetProfile = function() return {} end
        local anchorCalls = {}
        ns.QUI_Anchoring = {
            RegisterAllFrameTargets = function(self) anchorCalls[#anchorCalls+1] = "register" end,
            ApplyAllFrameAnchors    = function(self) anchorCalls[#anchorCalls+1] = "apply" end,
        }
        loader:LoadEnabledLODModules()
        assert(#anchorCalls == 0, "no anchoring calls when nothing loaded, got " .. #anchorCalls)
    end

    -- 7c) Combat-deferred stagger: anchoring fires after regen drain (loads happened post-combat).
    do
        local ns, calls, state, getLastFrame = newEnv()
        local loader = loadLoader(ns)
        loader.GetProfile = function() return {} end
        local anchorCalls = {}
        ns.QUI_Anchoring = {
            RegisterAllFrameTargets = function(self) anchorCalls[#anchorCalls+1] = "register" end,
            ApplyAllFrameAnchors    = function(self) anchorCalls[#anchorCalls+1] = "apply" end,
        }
        _G.InCombatLockdown = function() return true end
        loader:LoadEnabledLODModules()
        -- Still in combat — no anchoring yet.
        assert(#anchorCalls == 0, "no anchoring during combat")
        -- Leave combat, drain queue.
        _G.InCombatLockdown = function() return false end
        local frame = getLastFrame()
        frame:FireEvent("PLAYER_REGEN_ENABLED")
        -- Now anchoring must have fired.
        assert(#anchorCalls == 2, "anchoring called after combat drain, got " .. #anchorCalls)
        assert(anchorCalls[1] == "register", "register after combat drain")
        assert(anchorCalls[2] == "apply",    "apply after combat drain")
    end
end

print("addon_loader_test OK")
