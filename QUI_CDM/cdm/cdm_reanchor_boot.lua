local _, ns = ...

local CDMReanchorBoot = {}
ns.CDMReanchorBoot = CDMReanchorBoot

local _issecretvalue = issecretvalue or function() return false end

local function MakePositionOwned(env)
    return function(icon, container, point, relPoint, x, y, rowConfig)
        if icon.GetScale and icon:GetScale() ~= 1 then
            icon:SetScale(1)
        end
        icon:ClearAllPoints()
        icon:SetPoint(point, container, relPoint, x, y)
        icon:Show()
        if env.onIconPlaced then env.onIconPlaced(icon, rowConfig) end
    end
end

local function MakeApplySize(env)
    return function(container, metrics)
        local w = metrics.iconWidth or 0
        local h = metrics.totalHeight or 0
        if env.pixelRound then
            w = env.pixelRound(w, container)
            h = env.pixelRound(h, container)
        end
        if w > 0 and h > 0 and ((not env.canMutate) or env.canMutate(container)) then
            ns.SafeCallMethod("best-effort-style", container, "SetSize", w, h)
        end
        if env.onMetrics then env.onMetrics(container, metrics) end
    end
end

local function MakeMintOwned(env)
    return function(entry, containerKey)
        local container = env.getContainer and env.getContainer(containerKey) or nil
        if not container then return nil end
        return env.acquireIcon(container, entry, containerKey)
    end
end

local function MakeGetAdditional(env)
    return function(containerKey)
        if env.resolveAdditional then
            return env.resolveAdditional(containerKey) or {}
        end
        return {}
    end
end

CDMReanchorBoot._MakePositionOwned = MakePositionOwned
CDMReanchorBoot._MakeApplySize = MakeApplySize
CDMReanchorBoot._MakeMintOwned = MakeMintOwned
CDMReanchorBoot._MakeGetAdditional = MakeGetAdditional

function CDMReanchorBoot.BuildRuntime(env)
    local bridge = env.CDMReanchor.New({ sinkAnchor = env.uiParent })
    local wiring = env.CDMReanchorWiring.New({ bridge = bridge, index = env.index })
    local runtime
    local function swipeSettings()
        return (ns._OwnedSwipe and ns._OwnedSwipe.GetSettings and ns._OwnedSwipe.GetSettings()) or {}
    end
    local function effectsHidden(containerKey)
        local swipe = ns._OwnedSwipe
        return swipe and swipe.IsContainerEffectsHidden
            and swipe.IsContainerEffectsHidden(containerKey) or false
    end
    local function modeColor(mode)
        if ns._CDM_ResolveModeColor then return ns._CDM_ResolveModeColor(swipeSettings(), mode) end
        if mode == "aura" then return 0.93, 0.77, 0.0, 0.45 end
        return 0, 0, 0, 0.8
    end
    local function cooldownShown(frame)
        local s = swipeSettings()
        local g = frame and frame.isOnGCD
        if _issecretvalue(g) then return s.showCooldownSwipe ~= false end
        if g == true then return s.showGCDSwipe == true end
        return s.showCooldownSwipe ~= false
    end
    local function isAuraPhaseEnabled()
        local s = ns._OwnedSwipe and ns._OwnedSwipe.GetSettings and ns._OwnedSwipe.GetSettings()
        return not (s and s.showCooldownIconAuraPhase == false)
    end
    local function isBuffIconFrameKey(key)
        return key == "buff" or key == "buffIcon"
    end
    local function queryRealCooldownDurObj(frame)
        local entry = runtime and runtime.GetEntryForFrame and runtime:GetEntryForFrame(frame)
        if not entry then return nil end
        local entryType = entry.type
        if entryType == "item" or entryType == "trinket" or entryType == "slot"
            or entryType == "macro" then
            local R = ns.CDMResolvers
            if R and R.BuildEntryItemDurationObject then
                return R.BuildEntryItemDurationObject(entry)
            end
            return nil
        end
        local spellID
        if entryType == "consumable" then
            local Index = ns.CDMIndex
            local indexEntry = Index and Index.GetByCategory and Index.GetByCategory(entry.id)
            spellID = indexEntry and indexEntry.primarySpellID
        else
            spellID = entry.overrideSpellID or entry.spellID or entry.id
        end
        if _issecretvalue(spellID) or type(spellID) ~= "number" then return nil end
        local Sources = ns.CDMSources
        if not Sources then return nil end
        local durObj
        if Sources.QuerySpellCooldownDuration then
            durObj = Sources.QuerySpellCooldownDuration(spellID, true)
        end
        if not durObj and Sources.QuerySpellChargeDuration then
            durObj = Sources.QuerySpellChargeDuration(spellID)
        end
        return durObj
    end
    local function restyleAuraPhaseAsCooldown(frame, cd)
        local durObj = queryRealCooldownDurObj(frame)
        if cd.SetUseAuraDisplayTime then cd:SetUseAuraDisplayTime(false) end
        if durObj and cd.SetCooldownFromDurationObject then
            local clearIfZero = true
            cd:SetCooldownFromDurationObject(durObj, clearIfZero)
            if swipeSettings().showCooldownSwipe ~= false then
                local r, g, b, a = modeColor("cooldown")
                cd:SetSwipeColor(r, g, b, a)
            else
                cd:SetSwipeColor(0, 0, 0, 0)
            end
        else
            if cd.Clear then cd:Clear() end
            cd:SetSwipeColor(0, 0, 0, 0)
        end
    end
    local function reassertColor(frame, cd, containerKey)
        if not (cd and cd.SetSwipeColor) then return end
        if effectsHidden(containerKey) then
            cd:SetSwipeColor(0, 0, 0, 0)
            if cd.SetDrawSwipe then cd:SetDrawSwipe(false) end
            if cd.SetDrawEdge then cd:SetDrawEdge(false) end
            return
        end
        if isBuffIconFrameKey(containerKey) then
            if swipeSettings().showBuffIconSwipe == false then
                cd:SetSwipeColor(0, 0, 0, 0)
            else
                local r, g, b, a = modeColor("aura")
                cd:SetSwipeColor(r, g, b, a)
            end
            return
        end
        if frame.cooldownUseAuraDisplayTime == true then
            if isAuraPhaseEnabled() then
                local r, g, b, a = modeColor("aura")
                cd:SetSwipeColor(r, g, b, a)
            else
                restyleAuraPhaseAsCooldown(frame, cd)
            end
        elseif cooldownShown(frame) then
            local r, g, b, a = modeColor("cooldown")
            cd:SetSwipeColor(r, g, b, a)
        else
            cd:SetSwipeColor(0, 0, 0, 0)
        end
    end
    local function reassertDesat(frame, tex)
        if not tex then return end
        if frame.cooldownUseAuraDisplayTime ~= true or isAuraPhaseEnabled() then return end
        local durObj = queryRealCooldownDurObj(frame)
        if not durObj then return end
        local curve = ns._CDM_GetCooldownDesatCurve and ns._CDM_GetCooldownDesatCurve()
        if curve and durObj.EvaluateRemainingPercent and tex.SetDesaturation then
            tex:SetDesaturation(durObj:EvaluateRemainingPercent(curve))
        elseif tex.SetDesaturated then
            tex:SetDesaturated(true)
        end
    end
    local function reassertEdge(_frame, cd, containerKey)
        if not (cd and cd.SetDrawEdge) then return end
        if effectsHidden(containerKey) then
            cd:SetDrawEdge(false)
            return
        end
        local s = swipeSettings()
        if isBuffIconFrameKey(containerKey) then
            if s.showBuffIconSwipe == false or s.showBuffEdge == false then
                cd:SetDrawEdge(false)
            end
            return
        end
        if s.showRechargeEdge then return end
        cd:SetDrawEdge(false)
    end
    local auraPhase = ns.CDMReanchorAuraPhase and ns.CDMReanchorAuraPhase.New({
        securecall = securecallfunction,
        isAuraPhaseEnabled = isAuraPhaseEnabled,
        reassertColor = reassertColor,
        reassertEdge = reassertEdge,
        reassertDesat = reassertDesat,
    })
    local pandemic = ns.CDMReanchorPandemic and ns.CDMReanchorPandemic.New({
        securecall = securecallfunction,
        getEntryForFrame = function(frame)
            return runtime and runtime.GetEntryForFrame and runtime:GetEntryForFrame(frame) or nil
        end,
        ensureOverlay = function(frame)
            local ensure = ns._CDMEnsureReanchorGlowOverlay
            return ensure and ensure(frame) or nil
        end,
        isPandemicEnabled = function(entry)
            local OG = ns._OwnedGlows
            if OG and OG.IsPandemicEnabledForEntry then
                return OG.IsPandemicEnabledForEntry(entry)
            end
            return false
        end,
        startPandemic = function(overlay)
            local OG = ns._OwnedGlows
            if OG and OG.ApplyPandemicToOverlay then OG.ApplyPandemicToOverlay(overlay) end
        end,
        stopPandemic = function(overlay)
            local OG = ns._OwnedGlows
            if OG and OG.ClearPandemicFromOverlay then OG.ClearPandemicFromOverlay(overlay) end
        end,
    })
    runtime = env.CDMReanchorRuntime.New({
        bridge = bridge,
        wiring = wiring,
        placementPlanner = env.CDMPlacementPlanner or ns.CDMPlacementPlanner,
        auraPhase = auraPhase,
        pandemic = pandemic,
        getProcGlow = function()
            return ns._cdmReanchorProcGlow
        end,
        getContainer = env.getContainer,
        getCurated = env.getCurated,
        getSettings = env.getSettings,
        getAdditional = MakeGetAdditional(env),
        buildLayout = env.buildLayout,
        buildBuffLayout = env.buildBuffLayout,
        frameIsActive = env.frameIsActive,
        entryAuraIsPresent = env.entryAuraIsPresent,
        inCombat = env.inCombat,
        canMutate = env.canMutate,
        isEditMode = env.isEditMode,
        pixelRound = env.pixelRound,
        mintOwned = MakeMintOwned(env),
        releaseOwned = env.releaseIcon,
        positionOwned = MakePositionOwned(env),
        acquireAuraMirror = env.acquireAuraMirror,
        positionAuraMirror = env.positionAuraMirror,
        beginAuraMirrorPass = env.beginAuraMirrorPass,
        endAuraMirrorPass = env.endAuraMirrorPass,
        applySize = MakeApplySize(env),
        decorate = env.decorate,
        positionClickSlot = env.positionClickSlot,
        ensureLiveTooltip = env.ensureLiveTooltip,
        hideLiveTooltip = env.hideLiveTooltip,
        updateClickOverlay = env.updateClickOverlay,
        beginShellPass = env.beginShellPass,
        endShellPass = env.endShellPass,
        resetShells = env.resetShells,
    })
    return {
        bridge = bridge,
        wiring = wiring,
        runtime = runtime,
        RefreshBuiltin = function(_, containerKey)
            return runtime:RefreshContainer(containerKey)
        end,
        RefreshBuiltins = function(_, containerKeys)
            return runtime:RefreshContainers(containerKeys)
        end,
        DrainPendingCombatRefresh = function(_)
            return runtime:DrainPendingCombatRefresh()
        end,
        GetReanchoredFrames = function(_, containerKey)
            return runtime:GetReanchoredFrames(containerKey)
        end,
        GetEntryForFrame = function(_, frame)
            return runtime:GetEntryForFrame(frame)
        end,
        GetPlacementsForFrame = function(_, frame)
            return runtime:GetPlacementsForFrame(frame)
        end,
    }
end
