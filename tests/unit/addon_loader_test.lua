-- Verifies core/addon_loader.lua: manifest shape, LOD staggered loading,
-- and the toggle helper's Enable/Disable/Load calls.
-- Standalone: stubs ns + C_AddOns; loads manifest + loader via loadfile.

local function newEnv()
    local calls = {}
    local state = { loaded = {}, enabled = {}, exists = {}, loadFails = {}, deps = {} }
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
        -- Hard TOC deps per folder ({ [folder] = {dep, ...} }); none by default.
        GetAddOnDependencies = function(n)
            local d = state.deps[n]
            if d then return unpack(d) end
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

-- 1) Manifest shape: 13 entries, classes valid, folders unique;
--    legacyFlag present on exactly QUI_Chat, QUI_GroupFrames, QUI_Bags, absent on all
--    others; flag field absent on every entry.
do
    local ns = newEnv()
    loadLoader(ns)
    local seen, lod, login = {}, 0, 0
    local legacyFlagFolders = {}
    local lateLoadFolders = {}
    for _, e in ipairs(ns.AddonManifest) do
        assert(type(e.folder) == "string" and e.folder:match("^QUI_"), "folder name")
        assert(not seen[e.folder], "unique folder"); seen[e.folder] = true
        assert(e.class == "login" or e.class == "lod", "class")
        -- sources documents the PRE-SPLIT module paths; addons born after
        -- the suite split (QUI_Alts) legitimately have none.
        assert(type(e.sources) == "table", "sources")
        -- flag field must be gone from every entry
        assert(e.flag == nil, "flag field must be absent on " .. e.folder)
        -- track which entries carry legacyFlag
        if e.legacyFlag ~= nil then
            assert(type(e.legacyFlag) == "table" and #e.legacyFlag > 0,
                "legacyFlag must be a non-empty table on " .. e.folder)
            legacyFlagFolders[#legacyFlagFolders + 1] = e.folder
        end
        if e.lateLoad ~= nil then
            assert(e.lateLoad == true, "lateLoad must be boolean true on " .. e.folder)
            assert(e.class == "lod", "lateLoad only valid on lod entries: " .. e.folder)
            lateLoadFolders[#lateLoadFolders + 1] = e.folder
        end
        if e.class == "lod" then lod = lod + 1 else login = login + 1 end
    end
    assert(login == 6, "6 login-class entries, got " .. login)
    assert(lod == 8, "8 lod entries, got " .. lod)
    assert(#legacyFlagFolders == 4,
        "exactly 4 legacyFlag entries, got " .. #legacyFlagFolders)
    -- Sort for deterministic comparison (manifest order may vary)
    table.sort(legacyFlagFolders)
    assert(legacyFlagFolders[1] == "QUI_Alts",
        "1st legacyFlag entry must be QUI_Alts, got " .. tostring(legacyFlagFolders[1]))
    assert(legacyFlagFolders[2] == "QUI_Bags",
        "2nd legacyFlag entry must be QUI_Bags, got " .. tostring(legacyFlagFolders[2]))
    assert(legacyFlagFolders[3] == "QUI_Chat",
        "3rd legacyFlag entry must be QUI_Chat, got " .. tostring(legacyFlagFolders[3]))
    assert(legacyFlagFolders[4] == "QUI_GroupFrames",
        "4th legacyFlag entry must be QUI_GroupFrames, got " .. tostring(legacyFlagFolders[4]))
    -- lateLoad: none today. QUI_Minimap now eager-loads (skinned/anchored
    -- before the first frame, re-applying after EditMode settles), so no entry
    -- is flagged lateLoad. The mechanism itself is retained for future use.
    assert(#lateLoadFolders == 0,
        "no lateLoad entries expected, got " .. #lateLoadFolders)
end

-- 2) LOD stagger: all 8 LOD modules load when addon-enabled, regardless of
--    profile content.  Profile flags are no longer load gates; only
--    addon enable state matters.  Two variants: empty profile and a profile
--    with damageMeter.native.enabled=false both produce 8 loads.
do
    -- 2a) Empty profile: all 8 LOD modules load.
    do
        local ns, calls = newEnv()
        local loader = loadLoader(ns)
        loader.GetProfile = function() return {} end
        loader:LoadEnabledLODModules()
        local loads = {}
        for _, c in ipairs(calls) do if c:match("^load:") then loads[#loads+1] = c end end
        assert(#loads == 8, "2a: expected 8 loads (empty profile), got " .. #loads)
        assert(loads[1] == "load:QUI_Skinning",    "2a 1st: skinning")
        assert(loads[2] == "load:QUI_Datatexts",   "2a 2nd: datatexts")
        assert(loads[3] == "load:QUI_Minimap",     "2a 3rd: minimap")
        assert(loads[4] == "load:QUI_QoL",         "2a 4th: qol")
        assert(loads[5] == "load:QUI_DamageMeter", "2a 5th: damagemeter")
        assert(loads[6] == "load:QUI_InfoBar",     "2a 6th: infobar")
        assert(loads[7] == "load:QUI_Bags",        "2a 7th: bags")
        assert(loads[8] == "load:QUI_Alts",        "2a 8th: alts")
        assert(#ns.QUI_Modules.notified == 8, "2a: one notify per load")
    end

    -- 2b) Profile with damageMeter.native.enabled=false: DamageMeter still loads
    --    (profile flags are not load gates).
    do
        local ns, calls = newEnv()
        local loader = loadLoader(ns)
        loader.GetProfile = function()
            return { damageMeter = { native = { enabled = false } } }
        end
        loader:LoadEnabledLODModules()
        local loads = {}
        for _, c in ipairs(calls) do if c:match("^load:") then loads[#loads+1] = c end end
        assert(#loads == 8, "2b: expected 8 loads (flag-false profile), got " .. #loads)
        assert(loads[5] == "load:QUI_DamageMeter",
            "2b: DamageMeter must load even when profile flag is false")
    end
end

-- 3) Toggle helper: lod enable = Enable+Load now; login enable = reload; disable = reload;
--    LoadAddOn failure returns "reload"; SaveAddOns called after Enable/Disable;
--    disabled hard dep returns "depDisabled" + the dep folder.
--    Also documents the loader-level contract: enabling a login-class addon that is
--    already loaded returns "loaded" (the module ran at load time; the row layer in
--    module_addons_content.lua compensates by checking the dormant-guard flag flip).
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

    -- enable a login-class that is NOT yet loaded → "reload" (addon enabled, will load on reload)
    assert(loader.SetModuleAddonEnabled("QUI_UnitFrames", true) == "reload",
        "login-class not yet loaded: enable must return reload")

    -- enable a login-class that IS already loaded → "loaded" (loader-level contract:
    -- the module ran at load time; the module_addons_content row handles the
    -- dormant-guard-flag flip case separately by prompting reload when flipped+loaded).
    state.loaded.QUI_UnitFrames = true
    assert(loader.SetModuleAddonEnabled("QUI_UnitFrames", true) == "loaded",
        "login-class already loaded: enable must return loaded")

    -- missing addon
    state.exists.QUI_Chat = false
    assert(loader.SetModuleAddonEnabled("QUI_Chat", true) == "missing")

    -- LOD enable whose LoadAddOn fails → "reload"
    state.enabled.QUI_QoL = false
    state.loaded.QUI_QoL  = nil
    state.loadFails.QUI_QoL = true
    assert(loader.SetModuleAddonEnabled("QUI_QoL", true) == "reload",
        "LoadAddOn failure must return reload")

    -- enable a LOD module whose existing-on-disk hard dep is disabled →
    -- "depDisabled" + dep folder; enable+save still recorded, no LoadAddOn attempt
    state.deps.QUI_InfoBar = { "QUI_Datatexts" }
    state.enabled.QUI_InfoBar = false
    state.enabled.QUI_Datatexts = false
    for k in pairs(calls) do calls[k] = nil end
    local result, dep = loader.SetModuleAddonEnabled("QUI_InfoBar", true)
    assert(result == "depDisabled",
        "disabled dep: expected depDisabled, got " .. tostring(result))
    assert(dep == "QUI_Datatexts",
        "disabled dep: 2nd return must name the dep, got " .. tostring(dep))
    assert(calls[1] == "enable:QUI_InfoBar", "enable still recorded before dep check")
    assert(calls[2] == "save",               "save still recorded before dep check")
    for _, c in ipairs(calls) do
        assert(not c:match("^load:"), "disabled dep: LoadAddOn must not be attempted")
    end

    -- same module with the dep enabled → prior token ("loaded"), no regression
    state.enabled.QUI_Datatexts = true
    assert(loader.SetModuleAddonEnabled("QUI_InfoBar", true) == "loaded",
        "deps all enabled: LOD enable must still return loaded")

    -- GetAddOnDependencies absent (headless / older client) → old behavior:
    -- falls through to the load attempt (which fails on a disabled dep) → "reload"
    _G.C_AddOns.GetAddOnDependencies = nil
    state.loaded.QUI_InfoBar = nil
    state.enabled.QUI_InfoBar = false
    state.enabled.QUI_Datatexts = false
    state.loadFails.QUI_InfoBar = true  -- client would fail with DEP_DISABLED
    assert(loader.SetModuleAddonEnabled("QUI_InfoBar", true) == "reload",
        "GetAddOnDependencies absent: must fall back to reload, not depDisabled")
end

-- 4) Combat parking: no loads during lockdown; all drain after PLAYER_REGEN_ENABLED.
--    All 7 LOD modules are addon-enabled (default stub) so all 7 load post-regen.
do
    local ns, calls, state, getLastFrame = newEnv()
    local loader = loadLoader(ns)
    loader.GetProfile = function() return {} end  -- DB ready; profile content not used for gating

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

    -- All 7 LOD modules must now be loaded in manifest order.
    local loadsAfter = {}
    for _, c in ipairs(calls) do if c:match("^load:") then loadsAfter[#loadsAfter+1] = c end end
    assert(#loadsAfter == 8, "all 8 lod modules loaded after regen, got " .. #loadsAfter)
    assert(loadsAfter[1] == "load:QUI_Skinning",    "post-regen 1st: skinning")
    assert(loadsAfter[2] == "load:QUI_Datatexts",   "post-regen 2nd: datatexts")
    assert(loadsAfter[3] == "load:QUI_Minimap",     "post-regen 3rd: minimap")
    assert(loadsAfter[4] == "load:QUI_QoL",         "post-regen 4th: qol")
    assert(loadsAfter[5] == "load:QUI_DamageMeter", "post-regen 5th: damagemeter")
    assert(loadsAfter[6] == "load:QUI_InfoBar",     "post-regen 6th: infobar")
    assert(loadsAfter[7] == "load:QUI_Bags",        "post-regen 7th: bags")
    assert(loadsAfter[8] == "load:QUI_Alts",        "post-regen 8th: alts")

    -- Frame must have unregistered after draining.
    assert(not frame._events["PLAYER_REGEN_ENABLED"], "unregistered after drain")
end

-- 5) Combat guard on SetModuleAddonEnabled: enabling a LOD addon mid-combat
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

-- 6) Anchoring catch-up: RegisterAllFrameTargets + ApplyAllFrameAnchors called
--    exactly once after a stagger that loaded ≥1 module; NOT called when nothing loaded.
do
    -- 6a) At least one load → both anchoring methods called exactly once.
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

    -- 6b) Nothing eligible (all already loaded) → anchoring methods NOT called.
    do
        local ns, calls, state = newEnv()
        -- Mark all LOD modules as already loaded so nothing gets enqueued.
        state.loaded.QUI_Skinning    = true
        state.loaded.QUI_Datatexts   = true
        state.loaded.QUI_Minimap     = true
        state.loaded.QUI_QoL         = true
        state.loaded.QUI_DamageMeter = true
        state.loaded.QUI_InfoBar     = true
        state.loaded.QUI_Bags        = true
        state.loaded.QUI_Alts        = true
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

    -- 6c) Combat-deferred stagger: anchoring fires after regen drain (loads happened post-combat).
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

-- 7) Eager load (loading-screen path): LoadEnabledLODModulesEager loads every
--    eligible LOD module synchronously in manifest order, in ONE pass with NO
--    combat parking (it runs inside the ADDON_LOADED safe window), and runs the
--    anchoring catch-up exactly once when ≥1 module loaded. No entry is lateLoad
--    today, so QUI_Minimap loads here too (skinned/anchored before first frame).
do
    -- 7a) All 7 LOD modules load in manifest order (minimap included);
    --     one notify each; anchoring catch-up once.
    do
        local ns, calls = newEnv()
        local loader = loadLoader(ns)
        loader.GetProfile = function() return {} end
        local anchorCalls = {}
        ns.QUI_Anchoring = {
            RegisterAllFrameTargets = function() anchorCalls[#anchorCalls+1] = "register" end,
            ApplyAllFrameAnchors    = function() anchorCalls[#anchorCalls+1] = "apply" end,
        }
        loader:LoadEnabledLODModulesEager()
        local loads = {}
        for _, c in ipairs(calls) do if c:match("^load:") then loads[#loads+1] = c end end
        assert(#loads == 8, "7a: expected 8 eager loads (minimap included), got " .. #loads)
        assert(loads[1] == "load:QUI_Skinning",    "7a 1st: skinning")
        assert(loads[2] == "load:QUI_Datatexts",   "7a 2nd: datatexts")
        assert(loads[3] == "load:QUI_Minimap",     "7a 3rd: minimap")
        assert(loads[4] == "load:QUI_QoL",         "7a 4th: qol")
        assert(loads[5] == "load:QUI_DamageMeter", "7a 5th: damagemeter")
        assert(loads[6] == "load:QUI_InfoBar",     "7a 6th: infobar")
        assert(loads[7] == "load:QUI_Bags",        "7a 7th: bags")
        assert(loads[8] == "load:QUI_Alts",        "7a 8th: alts")
        assert(#ns.QUI_Modules.notified == 8, "7a: one notify per eager load")
        assert(#anchorCalls == 2, "7a: anchoring catch-up runs once (register+apply)")
        assert(anchorCalls[1] == "register" and anchorCalls[2] == "apply", "7a: register then apply")
    end

    -- 7b) Combat is IRRELEVANT to the eager path: still loads all 7 in lockdown
    --     (the safe window sanctions loading even during a combat /reload).
    do
        local ns, calls = newEnv()
        local loader = loadLoader(ns)
        loader.GetProfile = function() return {} end
        _G.InCombatLockdown = function() return true end
        loader:LoadEnabledLODModulesEager()
        _G.InCombatLockdown = function() return false end
        local loads = {}
        for _, c in ipairs(calls) do if c:match("^load:") then loads[#loads+1] = c end end
        assert(#loads == 8, "7b: eager load ignores combat lockdown, got " .. #loads)
    end

    -- 7c) Disabled addon is skipped: disable QoL → eager loads 6.
    do
        local ns, calls, state = newEnv()
        local loader = loadLoader(ns)
        loader.GetProfile = function() return {} end
        state.enabled.QUI_QoL = false
        local anchorCalls = {}
        ns.QUI_Anchoring = {
            RegisterAllFrameTargets = function() anchorCalls[#anchorCalls+1] = "register" end,
            ApplyAllFrameAnchors    = function() anchorCalls[#anchorCalls+1] = "apply" end,
        }
        loader:LoadEnabledLODModulesEager()
        local loads = {}
        for _, c in ipairs(calls) do if c:match("^load:") then loads[#loads+1] = c end end
        assert(#loads == 7, "7c: disabled QUI_QoL skipped, got " .. #loads)
        for _, c in ipairs(loads) do assert(c ~= "load:QUI_QoL", "7c: qol must not load") end
        assert(#anchorCalls == 2, "7c: anchoring still runs (7 loaded)")
    end

    -- 7d) DB not ready (GetProfile nil) → inert, no loads.
    do
        local ns, calls = newEnv()
        local loader = loadLoader(ns)
        loader.GetProfile = function() return nil end
        loader:LoadEnabledLODModulesEager()
        local loads = 0
        for _, c in ipairs(calls) do if c:match("^load:") then loads = loads + 1 end end
        assert(loads == 0, "7d: no eager loads when DB not ready, got " .. loads)
    end

    -- 7e) Two-stage split: with no lateLoad entries, eager loads ALL 8
    --     (including the minimap); the staggered post-login pass is a no-op
    --     catch-up — everything is already loaded, so it loads nothing more.
    do
        local ns, calls = newEnv()
        local loader = loadLoader(ns)
        loader.GetProfile = function() return {} end
        ns.QUI_Anchoring = {
            RegisterAllFrameTargets = function() end,
            ApplyAllFrameAnchors    = function() end,
        }
        -- Stage 1: eager — minimap IS among the loads now.
        loader:LoadEnabledLODModulesEager()
        local afterEager, minimapEager = 0, false
        for _, c in ipairs(calls) do
            if c:match("^load:") then
                afterEager = afterEager + 1
                if c == "load:QUI_Minimap" then minimapEager = true end
            end
        end
        assert(afterEager == 8, "7e: eager loads all 8, got " .. afterEager)
        assert(minimapEager, "7e: minimap now eager-loads")
        -- Stage 2: staggered post-login — all already loaded, loads nothing new.
        loader:LoadEnabledLODModules()
        local total = 0
        for _, c in ipairs(calls) do if c:match("^load:") then total = total + 1 end end
        assert(total == 8, "7e: staggered catch-up loads nothing new, got " .. total)
    end
end

-- 8) Per-character enable gating (Blizzard AddOnUtil idiom): query by the
--    player GUID and require Enum.AddOnEnableState.All. "Some" means the
--    addon is enabled on OTHER characters only — it must NOT gate as
--    enabled here (the old any-non-zero check loaded it anyway, defeating
--    the per-character AddOns-list boundary). Without a GUID (headless /
--    very early) the aggregate no-arg query keeps the legacy behavior.
do
    local ns, calls, state = newEnv()
    state.someOnly = {} -- folder → true = enabled on other characters only
    _G.Enum = { AddOnEnableState = { None = 0, Some = 1, All = 2 } }
    _G.UnitGUID = function() return "Player-1234-DEADBEEF" end
    _G.C_AddOns.GetAddOnEnableState = function(n, _char)
        if state.enabled[n] == false then return 0 end
        -- a Some addon never answers All, with or without a character arg
        if state.someOnly[n] then return 1 end
        return 2
    end
    local loader = loadLoader(ns)
    loader.GetProfile = function() return {} end
    state.someOnly.QUI_Bags = true
    assert(loader.IsModuleAddonEnabled("QUI_Bags") == false,
        "8: Some (enabled on another character only) must gate as disabled here")
    assert(loader.IsModuleAddonEnabled("QUI_QoL") == true,
        "8: All must still gate as enabled")
    loader:LoadEnabledLODModulesEager()
    for _, c in ipairs(calls) do
        assert(c ~= "load:QUI_Bags", "8: a per-character-disabled addon must not eager-load")
    end
    -- no GUID → aggregate fallback (any non-zero = enabled, legacy behavior)
    _G.UnitGUID = nil
    assert(loader.IsModuleAddonEnabled("QUI_Bags") == true,
        "8: without a GUID the aggregate fallback treats Some as enabled")
    _G.Enum = nil
end

print("addon_loader_test OK")
