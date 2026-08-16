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

-- 1) Manifest shape: 14 entries, classes valid, folders unique;
--    legacyFlag present on exactly QUI_Bags, QUI_Chat, QUI_GroupFrames,
--    QUI_Nameplates, absent on other folder entries; 5 coreModule entries
--    (minimap/infobar/alts/datatexts/skinning).
do
    local ns = newEnv()
    loadLoader(ns)
    local seen, lod, login, coreModule = {}, 0, 0, 0
    local legacyFlagFolders = {}
    local lateLoadFolders = {}
    local loadPolicyFolders = {}
    local coreModules = {}
    for _, e in ipairs(ns.AddonManifest) do
        if e.folder then
            -- FOLDER ENTRY: a shipped sibling addon folder.
            assert(type(e.folder) == "string" and e.folder:match("^QUI_"), "folder name")
            assert(not seen[e.folder], "unique folder"); seen[e.folder] = true
            assert(e.class == "login" or e.class == "lod", "class")
            -- sources documents the pre-split module paths.
            assert(type(e.sources) == "table", "sources")
            -- coreModule/host-backed fields must NOT appear on a folder entry
            assert(e.coreModule == nil and e.hostAddon == nil and e.module == nil and e.flag == nil,
                "folder entry must not carry coreModule or host-backed fields: " .. e.folder)
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
            if e.loadPolicy ~= nil then
                assert(e.loadPolicy == "profile",
                    "loadPolicy must be the string \"profile\" on " .. e.folder)
                assert(e.class == "lod",
                    "loadPolicy only valid on lod entries: " .. e.folder)
                assert(e.legacyFlag ~= nil,
                    "loadPolicy requires a legacyFlag to consult: " .. e.folder)
                loadPolicyFolders[#loadPolicyFolders + 1] = e.folder
            end
            if e.class == "lod" then lod = lod + 1 else login = login + 1 end
        else
            -- CORE-MODULE ENTRY: a module shipping inside the main QUI addon.
            assert(type(e.coreModule) == "string" and #e.coreModule > 0,
                "coreModule entry needs a coreModule name")
            assert(type(e.flag) == "table" and #e.flag > 0,
                "coreModule entry needs a non-empty flag table")
            -- a coreModule entry has no standalone folder/class/sources/legacyFlag
            assert(e.folder == nil and e.class == nil and e.sources == nil and e.legacyFlag == nil,
                "coreModule entry must not carry folder-entry fields: " .. e.coreModule)
            coreModule = coreModule + 1
            coreModules[#coreModules + 1] = e.coreModule
        end
    end
    assert(login == 7, "7 login-class entries, got " .. login)
    assert(lod == 2, "2 lod folder entries (QUI_DamageMeter/QUI_Bags), got " .. lod)
    assert(coreModule == 5, "5 coreModule entries (minimap/infobar/alts/datatexts/skinning), got " .. coreModule)
    assert(#legacyFlagFolders == 5,
        "exactly 5 legacyFlag entries, got " .. #legacyFlagFolders)
    -- Sort for deterministic comparison (manifest order may vary)
    table.sort(legacyFlagFolders)
    assert(legacyFlagFolders[1] == "QUI_Bags",
        "1st legacyFlag entry must be QUI_Bags, got " .. tostring(legacyFlagFolders[1]))
    assert(legacyFlagFolders[2] == "QUI_Chat",
        "2nd legacyFlag entry must be QUI_Chat, got " .. tostring(legacyFlagFolders[2]))
    assert(legacyFlagFolders[3] == "QUI_GroupFrames",
        "3rd legacyFlag entry must be QUI_GroupFrames, got " .. tostring(legacyFlagFolders[3]))
    assert(legacyFlagFolders[4] == "QUI_Nameplates",
        "4th legacyFlag entry must be QUI_Nameplates, got " .. tostring(legacyFlagFolders[4]))
    assert(legacyFlagFolders[5] == "QUI_UnitFrames",
        "5th legacyFlag entry must be QUI_UnitFrames, got " .. tostring(legacyFlagFolders[5]))
    table.sort(coreModules)
    assert(table.concat(coreModules, ",") == "alts,datatexts,infobar,minimap,skinning",
        "coreModule entries must be alts/datatexts/infobar/minimap/skinning, got " .. table.concat(coreModules, ","))
    -- lateLoad: none today. The mechanism is retained for future use.
    assert(#lateLoadFolders == 0,
        "no lateLoad entries expected, got " .. #lateLoadFolders)
    -- loadPolicy: exactly QUI_Bags opts into the eager-pass profile gate.
    assert(#loadPolicyFolders == 1 and loadPolicyFolders[1] == "QUI_Bags",
        "loadPolicy=\"profile\" expected on exactly QUI_Bags, got \""
            .. table.concat(loadPolicyFolders, ",") .. "\"")
end

-- 2) LOD stagger: the automatic passes load the 2 LOD folders (QUI_DamageMeter/
--    QUI_Bags) when addon-enabled, regardless of profile content. Profile flags
--    are not load gates; only addon enable state matters.
do
    -- 2a) Empty profile: the 2 LOD folders load in manifest order.
    do
        local ns, calls = newEnv()
        local loader = loadLoader(ns)
        loader.GetProfile = function() return {} end
        loader:LoadEnabledLODModules()
        local loads = {}
        for _, c in ipairs(calls) do if c:match("^load:") then loads[#loads+1] = c end end
        assert(#loads == 2, "2a: expected 2 loads, got " .. #loads)
        assert(loads[1] == "load:QUI_DamageMeter", "2a 1st: damagemeter")
        assert(loads[2] == "load:QUI_Bags",        "2a 2nd: bags")
        assert(#ns.QUI_Modules.notified == 2, "2a: one notify per load")
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
        assert(#loads == 2, "2b: expected 2 loads (flag-false profile), got " .. #loads)
        assert(loads[1] == "load:QUI_DamageMeter",
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

    -- enable a disabled LOD folder: Enable → Load → "loaded", SaveAddOns called
    state.enabled.QUI_DamageMeter = false
    assert(loader.SetModuleAddonEnabled("QUI_DamageMeter", true) == "loaded")
    assert(calls[1] == "enable:QUI_DamageMeter", "1st call enable")
    assert(calls[2] == "save",                   "2nd call save after enable")
    assert(calls[3] == "load:QUI_DamageMeter",   "3rd call load")

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
    state.enabled.QUI_DamageMeter = false
    state.loaded.QUI_DamageMeter  = nil
    state.loadFails.QUI_DamageMeter = true
    assert(loader.SetModuleAddonEnabled("QUI_DamageMeter", true) == "reload",
        "LoadAddOn failure must return reload")
    state.loadFails.QUI_DamageMeter = nil

    -- enable a LOD folder whose existing-on-disk hard dep is disabled →
    -- "depDisabled" + dep folder; enable+save still recorded, no LoadAddOn attempt.
    -- (Synthetic dep: QUI_DamageMeter declares a hard dep on QUI_Bags for this case;
    -- the dep mechanism is folder-generic.)
    state.deps.QUI_DamageMeter = { "QUI_Bags" }
    state.enabled.QUI_DamageMeter = false
    state.loaded.QUI_DamageMeter = nil
    state.enabled.QUI_Bags = false
    for k in pairs(calls) do calls[k] = nil end
    local result, dep = loader.SetModuleAddonEnabled("QUI_DamageMeter", true)
    assert(result == "depDisabled",
        "disabled dep: expected depDisabled, got " .. tostring(result))
    assert(dep == "QUI_Bags",
        "disabled dep: 2nd return must name the dep, got " .. tostring(dep))
    assert(calls[1] == "enable:QUI_DamageMeter", "enable still recorded before dep check")
    assert(calls[2] == "save",                   "save still recorded before dep check")
    for _, c in ipairs(calls) do
        assert(not c:match("^load:"), "disabled dep: LoadAddOn must not be attempted")
    end

    -- same folder with the dep enabled → prior token ("loaded"), no regression
    state.enabled.QUI_Bags = true
    assert(loader.SetModuleAddonEnabled("QUI_DamageMeter", true) == "loaded",
        "deps all enabled: LOD enable must still return loaded")

    -- GetAddOnDependencies absent (headless / older client) → old behavior:
    -- falls through to the load attempt (which fails on a disabled dep) → "reload"
    _G.C_AddOns.GetAddOnDependencies = nil
    state.loaded.QUI_DamageMeter = nil
    state.enabled.QUI_DamageMeter = false
    state.enabled.QUI_Bags = false
    state.loadFails.QUI_DamageMeter = true  -- client would fail with DEP_DISABLED
    assert(loader.SetModuleAddonEnabled("QUI_DamageMeter", true) == "reload",
        "GetAddOnDependencies absent: must fall back to reload, not depDisabled")
end

-- 4) Combat parking: no loads during lockdown; all drain after PLAYER_REGEN_ENABLED.
--    The 2 LOD folders are addon-enabled (default stub) so both load post-regen.
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

    -- The 2 LOD folders must now be loaded in manifest order.
    local loadsAfter = {}
    for _, c in ipairs(calls) do if c:match("^load:") then loadsAfter[#loadsAfter+1] = c end end
    assert(#loadsAfter == 2, "both lod folders loaded after regen, got " .. #loadsAfter)
    assert(loadsAfter[1] == "load:QUI_DamageMeter", "post-regen 1st: damagemeter")
    assert(loadsAfter[2] == "load:QUI_Bags",        "post-regen 2nd: bags")

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
        state.enabled.QUI_DamageMeter = false
        _G.InCombatLockdown = function() return true end
        local result = loader.SetModuleAddonEnabled("QUI_DamageMeter", true)
        assert(result == "reload", "in-combat LOD enable must return 'reload', got " .. tostring(result))
        local hasLoad = false
        for _, c in ipairs(calls) do if c:match("^load:") then hasLoad = true end end
        assert(not hasLoad, "in-combat LOD enable must not call LoadAddOn")
        -- EnableAddOn and SaveAddOns still recorded
        assert(calls[1] == "enable:QUI_DamageMeter", "EnableAddOn still called in combat")
        assert(calls[2] == "save",                   "SaveAddOns still called in combat")
        _G.InCombatLockdown = function() return false end
    end

    -- Out-of-combat path: LoadNow fires, returns "loaded"
    do
        local ns, calls, state = newEnv()
        local loader = loadLoader(ns)
        state.enabled.QUI_DamageMeter = false
        _G.InCombatLockdown = function() return false end
        local result = loader.SetModuleAddonEnabled("QUI_DamageMeter", true)
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
        -- Mark all LOD folders as already loaded so nothing gets enqueued.
        state.loaded.QUI_DamageMeter = true
        state.loaded.QUI_Bags        = true
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
--    eligible LOD folder synchronously in manifest order, in ONE pass with NO
--    combat parking (it runs inside the ADDON_LOADED safe window), and runs the
--    anchoring catch-up exactly once when ≥1 folder loaded.
do
    -- 7a) The 2 LOD folders load in manifest order; one notify each; anchoring
    --     catch-up once.
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
        assert(#loads == 2, "7a: expected 2 eager loads, got " .. #loads)
        assert(loads[1] == "load:QUI_DamageMeter", "7a 1st: damagemeter")
        assert(loads[2] == "load:QUI_Bags",        "7a 2nd: bags")
        assert(#ns.QUI_Modules.notified == 2, "7a: one notify per eager load")
        assert(#anchorCalls == 2, "7a: anchoring catch-up runs once (register+apply)")
        assert(anchorCalls[1] == "register" and anchorCalls[2] == "apply", "7a: register then apply")
    end

    -- 7b) Combat is IRRELEVANT to the eager path: still loads the 2 in lockdown
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
        assert(#loads == 2, "7b: eager load ignores combat lockdown, got " .. #loads)
    end

    -- 7c) Both LOD folders load when addon-enabled.
    do
        local ns, calls, state = newEnv()
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
        assert(#loads == 2, "7c: expected 2 eager loads, got " .. #loads)
        assert(#anchorCalls == 2, "7c: anchoring still runs (2 loaded)")
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

    -- 7e) Two-stage split: the eager pass loads the 2 LOD folders; the staggered
    --     post-login pass is then a no-op catch-up — everything it would load is
    --     already loaded.
    do
        local ns, calls = newEnv()
        local loader = loadLoader(ns)
        loader.GetProfile = function() return {} end
        ns.QUI_Anchoring = {
            RegisterAllFrameTargets = function() end,
            ApplyAllFrameAnchors    = function() end,
        }
        -- Stage 1: eager.
        loader:LoadEnabledLODModulesEager()
        local afterEager = 0
        for _, c in ipairs(calls) do
            if c:match("^load:") then afterEager = afterEager + 1 end
        end
        assert(afterEager == 2, "7e: eager loads the 2 LOD folders, got " .. afterEager)
        -- Stage 2: staggered post-login — both already loaded, loads nothing new.
        loader:LoadEnabledLODModules()
        local total = 0
        for _, c in ipairs(calls) do
            if c:match("^load:") then total = total + 1 end
        end
        assert(total == 2, "7e: staggered catch-up loads nothing new, got " .. total)
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
    assert(loader.IsModuleAddonEnabled("QUI_DamageMeter") == true,
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

-- 9) Eager load policy (loadPolicy = "profile" on QUI_Bags): the EAGER pass
--    skips a policy entry whose legacyFlag profile path is explicitly false;
--    absent flag = on (same semantics as the Module Addons ReadLegacyFlag).
--    The staggered pass and the toggle backend never consult the policy —
--    it gates login eagerness only.
do
    -- 9a) bags.enabled == false → eager loads only QUI_DamageMeter.
    do
        local ns, calls = newEnv()
        local loader = loadLoader(ns)
        loader.GetProfile = function() return { bags = { enabled = false } } end
        loader:LoadEnabledLODModulesEager()
        local loads = {}
        for _, c in ipairs(calls) do if c:match("^load:") then loads[#loads+1] = c end end
        assert(#loads == 1, "9a: expected 1 eager load, got " .. #loads)
        assert(loads[1] == "load:QUI_DamageMeter", "9a: only damagemeter eager-loads")
    end

    -- 9b) Same profile, staggered pass: policy NOT consulted — both load, so
    --     the post-login catch-up / profile-switch path still brings bags up.
    do
        local ns, calls = newEnv()
        local loader = loadLoader(ns)
        loader.GetProfile = function() return { bags = { enabled = false } } end
        loader:LoadEnabledLODModules()
        local loads = {}
        for _, c in ipairs(calls) do if c:match("^load:") then loads[#loads+1] = c end end
        assert(#loads == 2, "9b: staggered pass ignores loadPolicy, got " .. #loads)
        assert(loads[2] == "load:QUI_Bags", "9b: bags loads via the staggered pass")
    end

    -- 9c) Absent flag (empty profile) = on → eager loads both (new profiles
    --     seed the flag true; absent must not gate).
    do
        local ns, calls = newEnv()
        local loader = loadLoader(ns)
        loader.GetProfile = function() return {} end
        loader:LoadEnabledLODModulesEager()
        local loads = {}
        for _, c in ipairs(calls) do if c:match("^load:") then loads[#loads+1] = c end end
        assert(#loads == 2, "9c: absent flag must not gate the eager pass, got " .. #loads)
    end

    -- 9d) Pure predicate, exported for tests.
    do
        local ns = newEnv()
        local loader = loadLoader(ns)
        local entry = { loadPolicy = "profile", legacyFlag = { "bags", "enabled" } }
        assert(loader.IsEagerLoadAllowedByPolicy(entry, { bags = { enabled = false } }) == false,
            "9d: explicit false blocks eager")
        assert(loader.IsEagerLoadAllowedByPolicy(entry, { bags = { enabled = true } }) == true,
            "9d: true allows eager")
        assert(loader.IsEagerLoadAllowedByPolicy(entry, {}) == true,
            "9d: absent flag allows eager")
        assert(loader.IsEagerLoadAllowedByPolicy(entry, nil) == true,
            "9d: nil profile allows eager")
        assert(loader.IsEagerLoadAllowedByPolicy({ legacyFlag = { "bags", "enabled" } },
            { bags = { enabled = false } }) == true,
            "9d: no loadPolicy → profile content irrelevant")
    end

    -- 9e) Module Addons toggle live-load ignores the policy: flag-false
    --     profile, enabling the addon still LoadAddOn's it now ("loaded").
    do
        local ns, calls, state = newEnv()
        local loader = loadLoader(ns)
        loader.GetProfile = function() return { bags = { enabled = false } } end
        state.enabled.QUI_Bags = false
        assert(loader.SetModuleAddonEnabled("QUI_Bags", true) == "loaded",
            "9e: toggle enable must live-load regardless of loadPolicy")
        local hasLoad = false
        for _, c in ipairs(calls) do if c == "load:QUI_Bags" then hasLoad = true end end
        assert(hasLoad, "9e: LoadAddOn called for QUI_Bags")
    end
end

print("addon_loader_test OK")
