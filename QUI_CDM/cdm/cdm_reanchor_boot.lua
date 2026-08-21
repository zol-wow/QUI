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
    local function isAuraPhaseEnabled()
        local s = ns._OwnedSwipe and ns._OwnedSwipe.GetSettings and ns._OwnedSwipe.GetSettings()
        return not (s and s.showCooldownIconAuraPhase == false)
    end
    local function frameIsAuraPhase(frame)
        local active = frame and frame.cooldownUseAuraDisplayTime
        if _issecretvalue(active) then return false end -- @secret-policy: reject-secret-value
        return active == true
    end
    local function frameCanUseAuraForDisplay(frame)
        return frameIsAuraPhase(frame) and isAuraPhaseEnabled()
    end
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
    local function isBuffIconFrameKey(key)
        return key == "buff" or key == "buffIcon"
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
        if frameCanUseAuraForDisplay(frame) then
            if not frame.GetCooldownID then return end
            local s = swipeSettings()
            if not isAuraPhaseEnabled() or s.showBuffSwipe == false then
                cd:SetSwipeColor(0, 0, 0, 0)
            else
                local r, g, b, a = modeColor("aura")
                cd:SetSwipeColor(r, g, b, a)
            end
        elseif cooldownShown(frame) then
            local r, g, b, a = modeColor("cooldown")
            cd:SetSwipeColor(r, g, b, a)
        else
            cd:SetSwipeColor(0, 0, 0, 0)
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
    local function reassertSwipe(frame, cd, containerKey, show)
        if not (cd and cd.SetDrawSwipe) then return end
        local s = swipeSettings()
        if effectsHidden(containerKey) then
            if show then cd:SetDrawSwipe(false) end
            return
        end
        if isBuffIconFrameKey(containerKey) then
            if s.showBuffIconSwipe == false and show then
                cd:SetDrawSwipe(false)
            elseif s.showBuffIconSwipe ~= false and show == false then
                cd:SetDrawSwipe(true)
            end
            return
        end
        if frameCanUseAuraForDisplay(frame) then
            if not isAuraPhaseEnabled() or s.showBuffSwipe == false then
                if show then cd:SetDrawSwipe(false) end
            elseif show == false then
                cd:SetDrawSwipe(true)
            end
            return
        end
        local gcd = frame and frame.isOnGCD
        if _issecretvalue(gcd) then return end
        if gcd == true then
            if s.showGCDSwipe == true and not show then
                cd:SetDrawSwipe(true)
            elseif s.showGCDSwipe ~= true and show then
                cd:SetDrawSwipe(false)
            end
            return
        end
        if s.showCooldownSwipe == false and show then
            cd:SetDrawSwipe(false)
            return
        end
        if not show then
            local hasCharges = type(frame and frame.HasVisualDataSource_Charges) == "function"
                and frame:HasVisualDataSource_Charges()
            if not hasCharges then cd:SetDrawSwipe(true) end
        end
    end
    local auraPhase = ns.CDMReanchorAuraPhase and ns.CDMReanchorAuraPhase.New({
        securecall = securecallfunction,
        isAuraPhaseEnabled = isAuraPhaseEnabled,
        requestAuraPhaseRefresh = function(_, containerKey)
            local hooks = ns._cdmReanchorHooks
            if hooks and hooks.MarkDirty then hooks:MarkDirty(containerKey) end
        end,
        reassertColor = reassertColor,
        reassertEdge = reassertEdge,
        reassertSwipe = reassertSwipe,
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
        shouldReplaceNativeAuraPhase = function(frame, entry, containerKey)
            if containerKey == "buff" or containerKey == "buffIcon"
                or entry.isAura or entry.kind == "aura" then
                return false
            end
            return not isAuraPhaseEnabled() and frameIsAuraPhase(frame)
        end,
        buildLayout = env.buildLayout,
        buildBuffLayout = env.buildBuffLayout,
        frameIsActive = env.frameIsActive,
        entryAuraIsPresent = env.entryAuraIsPresent,
        inCombat = env.inCombat,
        canMutate = env.canMutate,
        isEditMode = env.isEditMode,
        pixelRound = env.pixelRound,
        pixelSnapCenter = env.pixelSnapCenter,
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
