local ADDON_NAME, ns = ...

local issecretvalue = _G.issecretvalue

local AddonLoader = {}
ns.AddonLoader = AddonLoader

function AddonLoader.GetProfile()
    return QUI and QUI.db and QUI.db.profile
end

function AddonLoader.IsModuleAddonEnabled(folder)
    if not (C_AddOns and C_AddOns.GetAddOnEnableState) then return true end
    local guid = UnitGUID and UnitGUID("player")
    if issecretvalue and issecretvalue(guid) then
        guid = nil -- @secret-policy: reject-secret-value (aggregate-query fallback)
    end
    if guid then
        local state = C_AddOns.GetAddOnEnableState(folder, guid)
        local all = Enum and Enum.AddOnEnableState and Enum.AddOnEnableState.All or 2
        return state == all
    end
    local state = C_AddOns.GetAddOnEnableState(folder)
    return (tonumber(state) or 0) > 0
end

function AddonLoader.IsModuleLoaded(folder)
    if not (C_AddOns and C_AddOns.IsAddOnLoaded) then return false end
    local loadedOrLoading = C_AddOns.IsAddOnLoaded(folder)
    return loadedOrLoading == true
end

local function ReadProfileFlag(profile, flagPath)
    local node = profile
    for i = 1, #flagPath do
        if type(node) ~= "table" then return true end
        node = node[flagPath[i]]
    end
    return node ~= false
end

function AddonLoader.IsEagerLoadAllowedByPolicy(entry, profile)
    if entry.loadPolicy ~= "profile" then return true end
    if not entry.legacyFlag or not profile then return true end
    return ReadProfileFlag(profile, entry.legacyFlag)
end

local function LoadNow(folder)
    local ok = C_AddOns.LoadAddOn(folder)
    if ok and ns.QUI_Modules then
        ns.QUI_Modules:NotifyChanged(folder)
    end
    return ok
end

local function CollectEligibleLODFolders(includeLate, applyLoadPolicy)
    local queue = {}
    local profile = applyLoadPolicy and AddonLoader.GetProfile() or nil
    for _, entry in ipairs(ns.AddonManifest or {}) do
        if entry.folder
            and entry.class == "lod"
            and (includeLate or not entry.lateLoad)
            and (not applyLoadPolicy or AddonLoader.IsEagerLoadAllowedByPolicy(entry, profile))
            and not AddonLoader.IsModuleLoaded(entry.folder)
            and (not C_AddOns.DoesAddOnExist or C_AddOns.DoesAddOnExist(entry.folder))
            and AddonLoader.IsModuleAddonEnabled(entry.folder) then
            queue[#queue + 1] = entry.folder
        end
    end
    return queue
end

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

function AddonLoader:LoadEnabledLODModulesEager()
    if not AddonLoader.GetProfile() then return end
    local loadedAny = false
    for _, folder in ipairs(CollectEligibleLODFolders(false, true)) do
        if not AddonLoader.IsModuleLoaded(folder) then
            LoadNow(folder)
            loadedAny = true
        end
    end
    if loadedAny then ApplyAnchoringCatchUp() end
end

local regenResumeFrame

function AddonLoader:LoadEnabledLODModules()
    if not AddonLoader.GetProfile() then return end
    local queue = CollectEligibleLODFolders(true)
    local i = 0
    local loadedAny = false
    local function step()
        i = i + 1
        local folder = queue[i]
        if not folder then
            if loadedAny then ApplyAnchoringCatchUp() end
            return
        end
        if InCombatLockdown and InCombatLockdown() then
            if not regenResumeFrame then
                regenResumeFrame = CreateFrame("Frame")
            end
            i = i - 1
            regenResumeFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
            regenResumeFrame:SetScript("OnEvent", function(self)
                self:UnregisterEvent("PLAYER_REGEN_ENABLED")
                C_Timer.After(0, step)
            end)
            return
        end
        if not AddonLoader.IsModuleLoaded(folder) then
            LoadNow(folder)
            loadedAny = true
        end
        C_Timer.After(0, step)
    end
    step()
end

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
        if not AddonLoader.IsModuleLoaded(folder) then
            local dep = GetDisabledDependency(folder)
            if dep then return "depDisabled", dep end
        end
        if entry and entry.class == "lod" and not AddonLoader.IsModuleLoaded(folder) then
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

ns.WhenLoggedIn(function()
    ns.RunAfterFirstFrame(function()
        AddonLoader:LoadEnabledLODModules()
    end, 1.2)
end)
