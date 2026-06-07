---------------------------------------------------------------------------
-- QUI AddonLoader — loads LoadOnDemand sub-addons post-login (staggered,
-- one per frame) and backs the per-module addon toggles in options.
--
-- Model: Blizzard addon enable state = "is the code present" (hard, zero
-- cost when off). Profile master flags = "is the feature active" (live,
-- unchanged semantics). This loader never flips addon state on its own;
-- only the user-facing toggle does (SetModuleAddonEnabled).
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
-- Flag resolution
---------------------------------------------------------------------------

-- Resolve a manifest flag path against a profile table. nil flag and
-- missing intermediate tables default to ON (matches default-on modules;
-- quiGroupFrames defaults off in defaults.lua, which AceDB materializes,
-- so the explicit false is always present when off).
function AddonLoader.IsFlagOn(profile, flagPath)
    if not flagPath then return true end
    local node = profile
    for i = 1, #flagPath do
        if type(node) ~= "table" then return true end
        node = node[flagPath[i]]
    end
    return node ~= false
end

---------------------------------------------------------------------------
-- Profile accessor (overridable for tests)
---------------------------------------------------------------------------

-- Overridable for tests; real implementation reads the live AceDB profile.
function AddonLoader.GetProfile()
    return QUI and QUI.db and QUI.db.profile
end

---------------------------------------------------------------------------
-- Addon-state helpers
---------------------------------------------------------------------------

function AddonLoader.IsModuleAddonEnabled(folder)
    if not (C_AddOns and C_AddOns.GetAddOnEnableState) then return true end
    -- Pass the current character so that "enabled on another toon" (state=1)
    -- doesn't mis-gate this character. UnitName may be nil in headless/early
    -- contexts; fall back to the aggregate no-arg form in that case.
    local charName = UnitName and UnitName("player")
    local state = C_AddOns.GetAddOnEnableState(folder, charName)
    -- AddOnEnableState: 0=None (disabled), 1=Some (enabled for some chars),
    -- 2=All (enabled for all). Any non-zero value = effectively enabled.
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

---------------------------------------------------------------------------
-- LOD stagger
---------------------------------------------------------------------------

-- Hidden frame used to resume a parked LOD chain after combat ends.
-- Created at most once; reused across multiple LoadEnabledLODModules calls.
local regenResumeFrame

-- Walk LOD manifest entries in order; load each eligible one on its own
-- frame so post-login work never lands as a single hitch.
-- Safe to call multiple times (OnProfileChanged re-invokes via core/main.lua);
-- already-loaded folders are skipped by IsModuleLoaded re-checks inside step().
function AddonLoader:LoadEnabledLODModules()
    local profile = AddonLoader.GetProfile()
    if not profile then return end  -- DB not ready (also keeps headless tests inert)
    local queue = {}
    for _, entry in ipairs(ns.AddonManifest or {}) do
        if entry.class == "lod"
            and not AddonLoader.IsModuleLoaded(entry.folder)
            and (not C_AddOns.DoesAddOnExist or C_AddOns.DoesAddOnExist(entry.folder))
            and AddonLoader.IsModuleAddonEnabled(entry.folder)
            and AddonLoader.IsFlagOn(profile, entry.flag) then
            queue[#queue + 1] = entry.folder
        end
    end
    local i = 0
    local loadedAny = false
    local function applyAnchoringCatchUp()
        -- LOD frames were born after the +1.0s anchoring passes — re-register
        -- targets and re-apply saved anchors once the queue drains.
        if ns.QUI_Anchoring then
            if ns.QUI_Anchoring.RegisterAllFrameTargets then
                ns.QUI_Anchoring:RegisterAllFrameTargets()
            end
            if ns.QUI_Anchoring.ApplyAllFrameAnchors then
                ns.QUI_Anchoring:ApplyAllFrameAnchors()
            end
        end
    end
    local function step()
        i = i + 1
        local folder = queue[i]
        if not folder then
            -- Queue drained — re-anchor any LOD frames that were just created.
            if loadedAny then applyAnchoringCatchUp() end
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

-- Options-toggle backend. Returns:
--   "loaded"  — LOD module enabled and loaded live, no reload needed
--   "reload"  — change recorded; takes effect on next reload (caller prompts)
--   "missing" — folder not on disk; caller renders "not installed"
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

-- After the first rendered frame + the 1.0s anchor pass in QUICore:OnEnable,
-- start the stagger. Profile switches re-invoke LoadEnabledLODModules via
-- QUICore:OnProfileChanged in core/main.lua.
ns.WhenLoggedIn(function()
    ns.RunAfterFirstFrame(function()
        AddonLoader:LoadEnabledLODModules()
    end, 1.2)
end)
