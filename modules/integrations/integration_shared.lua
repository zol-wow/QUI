--[[
    QUI Integration Shared Helpers
    Shared resolution logic used by the third-party integration modules.
    Loaded before each consumer in QUI.toc.
]]

local ADDON_NAME, ns = ...

local IntegrationShared = {}
ns.QUI_IntegrationShared = IntegrationShared

---------------------------------------------------------------------------
-- ANCHOR FRAME RESOLUTION
-- Resolves a QUI element name to its live frame. Shared verbatim across the
-- three integration modules.
---------------------------------------------------------------------------
function IntegrationShared.GetAnchorFrame(anchorName)
    if not anchorName or anchorName == "disabled" then
        return nil
    end

    local QUICore = ns.Addon

    -- Hardcoded QUI element map
    if anchorName == "essential" then
        return _G.QUI_GetCDMViewerFrame and _G.QUI_GetCDMViewerFrame("essential")
    elseif anchorName == "utility" then
        return _G.QUI_GetCDMViewerFrame and _G.QUI_GetCDMViewerFrame("utility")
    elseif anchorName == "primary" then
        return QUICore and QUICore.powerBar
    elseif anchorName == "secondary" then
        return QUICore and QUICore.secondaryPowerBar
    elseif anchorName == "playerCastbar" then
        return ns.QUI_Castbar and ns.QUI_Castbar.castbars and ns.QUI_Castbar.castbars["player"]
    elseif anchorName == "playerFrame" then
        return ns.QUI_UnitFrames and ns.QUI_UnitFrames.frames and ns.QUI_UnitFrames.frames.player
    elseif anchorName == "targetFrame" then
        return ns.QUI_UnitFrames and ns.QUI_UnitFrames.frames and ns.QUI_UnitFrames.frames.target
    end

    -- Registry fallback
    if ns.QUI_Anchoring and ns.QUI_Anchoring.GetAnchorTarget then
        return ns.QUI_Anchoring:GetAnchorTarget(anchorName)
    end

    return nil
end

---------------------------------------------------------------------------
-- ANCHORED-FRAMES HOOK / RETRY
-- Each integration module owns its own retry timer + hook-installed flag.
-- These factories build per-module closures so the bookkeeping stays distinct
-- while the (previously copy-pasted) bodies live in one place.
---------------------------------------------------------------------------

-- Returns a QueueRetry function that debounces a 1s retry calling
-- ns[moduleName]:ApplyAllPositions(). State is captured per call site.
function IntegrationShared.MakeQueueRetry(moduleName)
    local retryTimer
    return function()
        if retryTimer then
            return
        end
        retryTimer = C_Timer.NewTimer(1.0, function()
            retryTimer = nil
            local module = ns[moduleName]
            if module then
                module:ApplyAllPositions()
            end
        end)
    end
end

-- Returns a TryInstallAnchoredFramesHook function that registers
-- ns[moduleName]:ApplyAllPositions() as a post-update hook on the anchoring
-- module via ns.QUI_Anchoring.RegisterAnchoredFramesPostHook. Returns false
-- until that API is available so callers keep retrying. This routes through
-- QUI's explicit post-hook registry instead of re-wrapping the global
-- _G.QUI_UpdateAnchoredFrames (which the global-assignment ratchet forbids).
function IntegrationShared.MakeTryInstallAnchoredFramesHook(moduleName)
    local installed = false
    return function()
        if installed then
            return true
        end

        if not (ns.QUI_Anchoring and ns.QUI_Anchoring.RegisterAnchoredFramesPostHook) then
            return false
        end

        ns.QUI_Anchoring.RegisterAnchoredFramesPostHook(moduleName, function()
            local module = ns[moduleName]
            if module then
                module:ApplyAllPositions()
            end
        end)
        installed = true
        return true
    end
end
