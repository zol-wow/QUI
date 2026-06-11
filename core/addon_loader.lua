---------------------------------------------------------------------------
-- QUI AddonLoader — loads LoadOnDemand sub-addons and backs the per-module
-- addon toggles in options. Two-stage at login:
--   * Eager: the core eager-loads non-lateLoad modules inside the ADDON_LOADED
--     safe window (LoadEnabledLODModulesEager, called from QUICore:OnEnable) so
--     their files compile on the loading screen instead of a post-login hitch.
--   * Late: a staggered, combat-parking pass (LoadEnabledLODModules) runs
--     post-first-frame as a catch-up for any manifest entry flagged lateLoad,
--     plus anything the eager pass missed. No entry is lateLoad by default
--     today (the mechanism is retained); the same staggered pass also backs
--     live profile switches via OnProfileChanged.
--
-- Model: Blizzard addon enable state = "is the code present" (hard, zero
-- cost when off).  LOD eligibility = lod class + not loaded + exists +
-- addon-enabled.  Profile flags are NOT load gates here; three dormant-guard
-- flags (chat.enabled, quiGroupFrames.enabled, bags.enabled) are handled by
-- the Module Addons rows (AND-read / heal-on-enable) and by each module's
-- own init.
--
-- GetProfile() is kept as an overridable readiness hook so tests can inject
-- a profile table and prevent the kick-off stagger from firing during
-- loadLoader().  It is NOT used to gate individual module loads.
--
-- C_AddOns.IsAddOnLoaded returns (loadedOrLoading, loaded); we gate on the
-- first return so a currently-loading addon is also skipped.
-- C_AddOns.LoadAddOn returns (loaded Nilable, value Nilable) — nil on fail.
-- C_AddOns.GetAddOnEnableState returns AddOnEnableState: 0=None,1=Some,2=All.
---------------------------------------------------------------------------
local ADDON_NAME, ns = ...

local AddonLoader = {}
ns.AddonLoader = AddonLoader

---------------------------------------------------------------------------
-- Profile accessor (overridable for tests — readiness bail only)
---------------------------------------------------------------------------

-- Overridable for tests.  Real implementation returns the live AceDB profile
-- when the DB is ready; nil otherwise.  LoadEnabledLODModules bails when nil
-- so the kick-off stagger (ns.WhenLoggedIn below) does not fire during the
-- headless loadLoader() call in tests.  The profile content is NOT used to
-- gate individual module loads.
function AddonLoader.GetProfile()
    return QUI and QUI.db and QUI.db.profile
end

---------------------------------------------------------------------------
-- Addon-state helpers
---------------------------------------------------------------------------

function AddonLoader.IsModuleAddonEnabled(folder)
    if not (C_AddOns and C_AddOns.GetAddOnEnableState) then return true end
    -- Blizzard idiom (AddOnUtil.IsAddOnEnabledForCurrentCharacter): query by
    -- the player GUID and require Enum.AddOnEnableState.All. A per-character
    -- query never answers All for a character the addon is disabled on;
    -- "Some" means enabled on OTHER characters only and must NOT gate as
    -- enabled here (the AddOns-list per-character boundary is hard).
    local guid = UnitGUID and UnitGUID("player")
    if guid then
        local state = C_AddOns.GetAddOnEnableState(folder, guid)
        local all = Enum and Enum.AddOnEnableState and Enum.AddOnEnableState.All or 2
        return state == all
    end
    -- No GUID (headless / very early): aggregate no-arg query — 0=None,
    -- 1=Some, 2=All; any non-zero = possibly enabled somewhere.
    local state = C_AddOns.GetAddOnEnableState(folder)
    return (tonumber(state) or 0) > 0
end

-- Returns true when the addon is loaded or currently loading (first return
-- of IsAddOnLoaded). Either way, calling LoadAddOn again would be a no-op.
function AddonLoader.IsModuleLoaded(folder)
    if not (C_AddOns and C_AddOns.IsAddOnLoaded) then return false end
    local loadedOrLoading = C_AddOns.IsAddOnLoaded(folder)
    return loadedOrLoading == true
end

---------------------------------------------------------------------------
-- Internal load + notify
---------------------------------------------------------------------------

local function LoadNow(folder)
    local ok = C_AddOns.LoadAddOn(folder)
    if ok and ns.QUI_Modules then
        -- Notify wildcard subscribers; cross-module re-poll subscriptions key
        -- on folder names once the sub-addon split lands.
        ns.QUI_Modules:NotifyChanged(folder)
    end
    return ok
end

-- Manifest-ordered list of lod folders eligible to load now: lod class + not
-- already loaded/loading + exists on disk + addon-enabled. Profile flags are
-- NOT load gates; dormant-guard flags are handled by the Module Addons rows
-- and by each module's own init. Shared by the eager and staggered loaders.
--   includeLate=false (eager, loading-screen): skip lateLoad entries — those
--     need post-login state (e.g. settled EditMode) and break if loaded early.
--   includeLate=true (staggered, post-login): load everything still eligible,
--     i.e. the lateLoad modules plus anything the eager pass missed.
local function CollectEligibleLODFolders(includeLate)
    local queue = {}
    for _, entry in ipairs(ns.AddonManifest or {}) do
        if entry.class == "lod"
            and (includeLate or not entry.lateLoad)
            and not AddonLoader.IsModuleLoaded(entry.folder)
            and (not C_AddOns.DoesAddOnExist or C_AddOns.DoesAddOnExist(entry.folder))
            and AddonLoader.IsModuleAddonEnabled(entry.folder) then
            queue[#queue + 1] = entry.folder
        end
    end
    return queue
end

-- Re-register anchor targets and re-apply saved anchors after a load batch:
-- module frames may be created during/after the load, past the core's earlier
-- anchoring passes. Idempotent; only call when ≥1 module actually loaded.
local function ApplyAnchoringCatchUp()
    if ns.QUI_Anchoring then
        if ns.QUI_Anchoring.RegisterAllFrameTargets then
            ns.QUI_Anchoring:RegisterAllFrameTargets()
        end
        if ns.QUI_Anchoring.ApplyAllFrameAnchors then
            ns.QUI_Anchoring:ApplyAllFrameAnchors()
        end
    end
end

-- Eager load (login / combat /reload): invoked from QUICore:OnEnable, which
-- runs synchronously inside the ADDON_LOADED safe window. Loading the sub-addon
-- files here puts their compile cost on the loading screen (no post-login
-- hitch) and lets any secure setup in their init run in the protected window,
-- exactly like the login-class siblings. No stagger / combat park: the safe
-- window is the sanctioned place for this even during a combat /reload, so we
-- load every eligible module synchronously in manifest order.
function AddonLoader:LoadEnabledLODModulesEager()
    if not AddonLoader.GetProfile() then return end  -- DB not ready; keeps headless tests inert
    local loadedAny = false
    for _, folder in ipairs(CollectEligibleLODFolders(false)) do  -- exclude lateLoad
        -- Re-check per folder: a live toggle racing OnEnable could have loaded it.
        if not AddonLoader.IsModuleLoaded(folder) then
            LoadNow(folder)
            loadedAny = true
        end
    end
    if loadedAny then ApplyAnchoringCatchUp() end
end

---------------------------------------------------------------------------
-- LOD stagger
---------------------------------------------------------------------------

-- Hidden frame used to resume a parked LOD chain after combat ends.
-- Created at most once; reused across multiple LoadEnabledLODModules calls.
local regenResumeFrame

-- Walk LOD manifest entries in order; load each eligible one on its own
-- frame so the work never lands as a single hitch. Used for LIVE profile
-- switches (OnProfileChanged re-invokes via core/main.lua), which can happen
-- mid-combat — hence the per-frame stagger + combat park. The login path uses
-- LoadEnabledLODModulesEager instead.
-- Safe to call multiple times; already-loaded folders are skipped by
-- IsModuleLoaded re-checks (in CollectEligibleLODFolders and inside step()).
function AddonLoader:LoadEnabledLODModules()
    if not AddonLoader.GetProfile() then return end  -- DB not ready; keeps headless tests inert
    local queue = CollectEligibleLODFolders(true)  -- include lateLoad (post-login)
    local i = 0
    local loadedAny = false
    local function step()
        i = i + 1
        local folder = queue[i]
        if not folder then
            -- Queue drained — re-anchor any LOD frames that were just created.
            if loadedAny then ApplyAnchoringCatchUp() end
            return
        end
        -- Combat gating: loading addon files mid-lockdown is an unaudited
        -- context (post-combat /reload stagger point can still be in lockdown).
        -- Park the remaining queue and drain after PLAYER_REGEN_ENABLED.
        if InCombatLockdown and InCombatLockdown() then
            if not regenResumeFrame then
                regenResumeFrame = CreateFrame("Frame")
            end
            -- Back up i so the parked entry is retried on regen.
            i = i - 1
            regenResumeFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
            regenResumeFrame:SetScript("OnEvent", function(self)
                self:UnregisterEvent("PLAYER_REGEN_ENABLED")
                C_Timer.After(0, step)
            end)
            return
        end
        -- Re-entrancy guard: a toggle or profile switch may have already loaded
        -- this folder while it was sitting in the pending chain.
        if not AddonLoader.IsModuleLoaded(folder) then
            LoadNow(folder)
            loadedAny = true
        end
        C_Timer.After(0, step)
    end
    step()
end

---------------------------------------------------------------------------
-- Options-toggle backend
---------------------------------------------------------------------------

-- First TOC dependency of `folder` that exists on disk but is disabled for
-- this character; nil when every dep is enabled (or the API is absent).
-- The client refuses to load an addon whose hard dependency is disabled
-- (LoadAddOn fails with reason DEP_DISABLED, and a reload won't help), so
-- the toggle backend surfaces the dep instead of a useless reload prompt.
-- Limitation: a dep MISSING from disk is skipped here, so it falls through
-- to the LoadNow failure → "reload"; acceptable because the Module Addons
-- tile for that dep would itself show as not installed.
local function GetDisabledDependency(folder)
    if not (C_AddOns and C_AddOns.GetAddOnDependencies) then return nil end
    local deps = { C_AddOns.GetAddOnDependencies(folder) }
    for _, dep in ipairs(deps) do
        if (not C_AddOns.DoesAddOnExist or C_AddOns.DoesAddOnExist(dep))
            and not AddonLoader.IsModuleAddonEnabled(dep) then
            return dep
        end
    end
    return nil
end

-- Options-toggle backend. Returns:
--   "loaded"  — LOD module enabled and loaded live, no reload needed
--   "reload"  — change recorded; takes effect on next reload (caller prompts)
--   "missing" — folder not on disk; caller renders "not installed"
--   "depDisabled", depFolder — enable recorded, but a hard TOC dependency is
--               disabled so the addon cannot load (now or after reload);
--               caller surfaces the dependency
function AddonLoader.SetModuleAddonEnabled(folder, on)
    if C_AddOns.DoesAddOnExist and not C_AddOns.DoesAddOnExist(folder) then
        return "missing"
    end
    local entry
    for _, e in ipairs(ns.AddonManifest or {}) do
        if e.folder == folder then entry = e break end
    end
    if on then
        C_AddOns.EnableAddOn(folder)
        if C_AddOns.SaveAddOns then C_AddOns.SaveAddOns() end
        -- Hard TOC dependency disabled (e.g. QUI_InfoBar → QUI_Datatexts):
        -- LoadAddOn would fail with DEP_DISABLED and a reload won't fix it.
        -- The enable is recorded above so the addon comes up once the dep is
        -- enabled; tell the caller which dep is blocking.
        if not AddonLoader.IsModuleLoaded(folder) then
            local dep = GetDisabledDependency(folder)
            if dep then return "depDisabled", dep end
        end
        if entry and entry.class == "lod" and not AddonLoader.IsModuleLoaded(folder) then
            -- Loading mid-combat would run file-scope secure setup under lockdown;
            -- the reload prompt covers it.
            if InCombatLockdown and InCombatLockdown() then return "reload" end
            if LoadNow(folder) then return "loaded" end
            return "reload"
        end
        return AddonLoader.IsModuleLoaded(folder) and "loaded" or "reload"
    end
    C_AddOns.DisableAddOn(folder)
    if C_AddOns.SaveAddOns then C_AddOns.SaveAddOns() end
    return "reload"
end

---------------------------------------------------------------------------
-- Login kick-off
---------------------------------------------------------------------------
--
-- Two-stage load:
--   1. Eager (loading screen): QUICore:OnEnable (core/main.lua) calls
--      LoadEnabledLODModulesEager inside the ADDON_LOADED safe window, so the
--      non-lateLoad sub-addon files compile on the loading screen rather than
--      as a post-login hitch. With no lateLoad entries today, this loads every
--      eligible lod module (including QUI_Minimap).
--   2. Late (post-login): the stagger below is now a catch-up safety net — it
--      re-scans after the first frame and loads any lateLoad entry (none by
--      default) or anything the eager pass missed; normally a no-op.
-- Live profile switches re-invoke the staggered LoadEnabledLODModules via
-- QUICore:OnProfileChanged.
ns.WhenLoggedIn(function()
    ns.RunAfterFirstFrame(function()
        AddonLoader:LoadEnabledLODModules()
    end, 1.2)
end)
