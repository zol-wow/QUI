local _, ns = ...

---------------------------------------------------------------------------
-- CDM Icon Cooldown Policy
--
-- Private controller used by CDMIcons. It owns icon-local GCD swipe flags,
-- mirror state lookup, and mirror charge-cycle memory.
---------------------------------------------------------------------------

local CDMIconCooldownPolicy = {}
ns.CDMIconCooldownPolicy = CDMIconCooldownPolicy

local type = type
local issecretvalue = issecretvalue

function CDMIconCooldownPolicy.Create(callbacks)
    callbacks = callbacks or {}

    local controller = {}

    local function SafeBoolean(value)
        if issecretvalue and issecretvalue(value) then return nil end
        if value == true then return true end
        if value == false then return false end
        return nil
    end

    local function SafeString(value)
        if issecretvalue and issecretvalue(value) then return nil end
        if type(value) == "string" then return value end
        return nil
    end

    function controller:MarkGCDSwipe(icon)
        if not icon then return end
        icon._showingGCDSwipe = true
        icon._showingRealCooldownSwipe = nil
    end

    function controller:ClearGCDSwipe(icon)
        if not icon then return end
        icon._showingGCDSwipe = nil
    end

    function controller:GetIconMirrorState(icon)
        if not (icon and icon._blizzMirrorCooldownID) then
            return nil
        end
        if callbacks.getCachedMirrorStateForIcon then
            local state = callbacks.getCachedMirrorStateForIcon(icon)
            if state then return state end
        end
        if callbacks.refreshCachedMirrorStateForIcon then
            local state = callbacks.refreshCachedMirrorStateForIcon(icon)
            if state then return state end
        end
        local mirror = callbacks.getMirror and callbacks.getMirror() or nil
        if not (mirror and mirror.GetStateByCooldownID) then return nil end
        return mirror.GetStateByCooldownID(icon._blizzMirrorCooldownID, icon._blizzMirrorCategory)
    end

    function controller:MirrorStateIsActive(state)
        if not state then return false end
        if SafeBoolean(state.childIsActive) == true then return true end
        if state.auraInstanceID then return true end
        if state.totemSlot or state.auraDurObj or state.totemDurObj then return true end
        return false
    end

    function controller:ClearIconChargeMirrorCycle(icon)
        if not icon then return end
        icon._lastChargeMirrorCooldownID = nil
        icon._lastChargeMirrorCategory = nil
        icon._lastChargeRuntimeSpellID = nil
    end

    function controller:RememberIconChargeMirrorCycle(icon, runtimeSpellID)
        if not (icon and icon._blizzMirrorCooldownID) then return end
        icon._lastChargeMirrorCooldownID = icon._blizzMirrorCooldownID
        icon._lastChargeMirrorCategory = icon._blizzMirrorCategory
        icon._lastChargeRuntimeSpellID = runtimeSpellID
    end

    function controller:UpdateIconChargeMirrorCycle(icon, mode, runtimeSpellID, hasCharges)
        if not icon then return end
        -- Resolver no longer emits mode=="charge"; charge spells now flow as
        -- mode=="cooldown" with the recharge timer in state.durObj. The
        -- "is a charge spell" signal is the entry-level hasCharges flag,
        -- threaded from the call site.
        if mode == "cooldown" and hasCharges == true then
            controller:RememberIconChargeMirrorCycle(icon, runtimeSpellID)
        elseif mode == "inactive"
            and not controller:MirrorStateIsActive(controller:GetIconMirrorState(icon)) then
            controller:ClearIconChargeMirrorCycle(icon)
        end
    end

    function controller:MirrorPayloadHasChargeState(mirrorPayload)
        if not mirrorPayload then return false end
        local state = mirrorPayload.state
        if not state then return false end
        if SafeBoolean(state.charges) == true
            or SafeBoolean(state.cooldownChargesShown) == true
            or SafeBoolean(state.chargeCountFrameShown) == true then
            return true
        end
        return SafeString(state.stackTextSource) == "ChargeCount"
            and SafeBoolean(state.stackTextShown) ~= false
    end

    function controller:MirrorPayloadMatchesRecentChargeCycle(icon, mirrorPayload)
        if not (icon and mirrorPayload and icon._lastChargeMirrorCooldownID) then
            return false
        end
        if mirrorPayload.active ~= true then return false end
        local state = mirrorPayload.state
        if not state then return false end
        local cooldownID = mirrorPayload.cooldownID or state.cooldownID or icon._blizzMirrorCooldownID
        if issecretvalue and issecretvalue(cooldownID) then
            return false
        end
        if cooldownID ~= icon._lastChargeMirrorCooldownID then
            return false
        end
        local category = mirrorPayload.category or state.viewerCategory or icon._blizzMirrorCategory
        if issecretvalue and issecretvalue(category) then
            return false
        end
        return icon._lastChargeMirrorCategory == nil or category == icon._lastChargeMirrorCategory
    end

    return controller
end
