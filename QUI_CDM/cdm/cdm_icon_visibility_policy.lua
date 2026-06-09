local _, ns = ...

---------------------------------------------------------------------------
-- CDM Icon Visibility Policy
--
-- Private controller used by CDMIcons. It owns container-level visibility
-- filters, dynamic-layout dirty tracking, and show/hide/alpha application.
---------------------------------------------------------------------------

local CDMIconVisibilityPolicy = {}
ns.CDMIconVisibilityPolicy = CDMIconVisibilityPolicy

local ipairs = ipairs
local next = next
local pairs = pairs
local type = type
local wipe = wipe or function(tbl)
    for key in pairs(tbl) do
        tbl[key] = nil
    end
end

local DRAIN_MAX_ROUNDS = 3

function CDMIconVisibilityPolicy.Create(callbacks)
    callbacks = callbacks or {}

    local controller = {
        layoutNeedsRefresh = {},
        buffIconLayoutRefreshPending = false,
        drainingLayoutDirty = false,
    }

    function controller:ComputeFilterHides(icon, entry, containerDB, inCombat, isOnCD)
        if not containerDB then return false end

        if callbacks.isCustomBarContainer and callbacks.isCustomBarContainer(containerDB) then
            local visibility = callbacks.computeCustomBarVisibility
                and callbacks.computeCustomBarVisibility(icon, entry, containerDB)
                or nil
            return not (visibility and visibility.layoutVisible)
        end

        local cooldownState = callbacks.resolveCooldownActivityState
            and callbacks.resolveCooldownActivityState(icon, entry, containerDB)
            or {}
        local effectiveOnCD = cooldownState.isOnCooldown or cooldownState.rechargeActive

        if containerDB.showOnlyInCombat and not inCombat then
            return true
        end

        if containerDB.showOnlyOnCooldown and not effectiveOnCD then
            return true
        end

        if containerDB.showOnlyWhenOffCooldown and effectiveOnCD then
            return true
        end

        if containerDB.showOnlyWhenActive and not icon._auraActive then
            return true
        end

        if containerDB.hideNonUsable then
            if entry.type == "item" then
                local count = callbacks.queryItemCount
                    and callbacks.queryItemCount(entry.id, false, false, nil)
                    or nil
                if not count or count <= 0 then return true end
            elseif entry.type == "trinket" or entry.type == "slot" then
                local equippedItemID = callbacks.queryInventoryItemID
                    and callbacks.queryInventoryItemID("player", entry.id)
                    or nil
                if not equippedItemID then return true end
                if entry.id == 13 or entry.id == 14 then
                    local spellName = callbacks.queryItemSpell
                        and callbacks.queryItemSpell(equippedItemID)
                        or nil
                    if not spellName then return true end
                end
            else
                local sid = icon._runtimeSpellID or entry.spellID or entry.id
                if sid then
                    local known = callbacks.isSpellKnown and callbacks.isSpellKnown(sid)
                    if known == false then
                        return true
                    end
                    if callbacks.querySpellUsable then
                        local usable = callbacks.querySpellUsable(sid)
                        if type(usable) == "boolean" and usable == false then return true end
                    end
                end
            end
        end

        return false
    end

    function controller:ShouldPlaceLayoutIcon(icon, entry, containerDB, inCombat)
        if not icon or not entry then return true end
        local filterHides = controller:ComputeFilterHides(
            icon, entry, containerDB, inCombat, icon._hasCooldownActive or false)
        if callbacks.debugLayoutFilter then
            callbacks.debugLayoutFilter(icon, filterHides, containerDB, icon._hasCooldownActive or false)
        end
        icon._lastLayoutFilterHidden = filterHides and true or false
        return not filterHides
    end

    function controller:WakeBuffIconContainer()
        if callbacks.isHiddenByAnchor and callbacks.isHiddenByAnchor("buffIcon") then
            return
        end

        local container = callbacks.getContainer and callbacks.getContainer("buff")
        if container and container.Show then
            container:Show()
        end
    end

    function controller:RequestBuffIconLayoutRefresh()
        -- WakeBuffIconContainer calls container:Show(). When this refresh is
        -- requested synchronously inside an in-combat cooldown/aura dispatch (a
        -- secure-execution context), that Show is a blocked protected action
        -- (ADDON_ACTION_BLOCKED on QUI_CDMBuffIconContainer:Show). Never wake
        -- here synchronously -- defer it one frame (below) so it runs outside
        -- the secure dispatch. The container is a plain UIParent child, so a
        -- deferred Show is safe even mid-combat. Mirrors the secure-context-vs-
        -- combat defer pattern used elsewhere in QUI.
        if controller.buffIconLayoutRefreshPending then return end
        controller.buffIconLayoutRefreshPending = true
        local schedule = callbacks.scheduleAfter
        if not schedule then return end
        schedule(0, function()
            controller.buffIconLayoutRefreshPending = false
            controller:WakeBuffIconContainer()
            if callbacks.onBuffLayoutReady then
                callbacks.onBuffLayoutReady()
            end
        end)
    end

    function controller:MarkLayoutDirtyOnFilterFlip(icon, entry, containerDB, filterHidesNow)
        if not (entry and entry.viewerType) then return end
        if not containerDB or containerDB.dynamicLayout == false then return end
        local previously = icon._lastLayoutFilterHidden
        if previously == nil then return end
        if filterHidesNow ~= previously then
            controller.layoutNeedsRefresh[entry.viewerType] = true
        end
    end

    function controller:DrainLayoutDirty()
        if controller.drainingLayoutDirty then return end
        if next(controller.layoutNeedsRefresh) == nil then return end
        controller.drainingLayoutDirty = true
        if not callbacks.forceLayoutContainer then
            wipe(controller.layoutNeedsRefresh)
            controller.drainingLayoutDirty = false
            return
        end

        local toProcess = {}
        for _ = 1, DRAIN_MAX_ROUNDS do
            if next(controller.layoutNeedsRefresh) == nil then break end
            wipe(toProcess)
            for trackerKey in pairs(controller.layoutNeedsRefresh) do
                toProcess[#toProcess + 1] = trackerKey
            end
            wipe(controller.layoutNeedsRefresh)
            for _, trackerKey in ipairs(toProcess) do
                callbacks.forceLayoutContainer(trackerKey)
            end
        end
        wipe(controller.layoutNeedsRefresh)
        controller.drainingLayoutDirty = false
    end

    local function getIconRowOpacity(icon)
        local opacity = icon and icon._rowOpacity
        if opacity == nil then
            return 1
        end
        return opacity
    end

    local function setIconRowAlpha(icon, multiplier)
        if not icon then return end
        icon:SetAlpha(getIconRowOpacity(icon) * (multiplier or 1))
    end

    function controller:ApplyIconVisibility(icon, shouldShow, dynamicLayout)
        if dynamicLayout == false then
            if not icon:IsShown() then icon:Show() end
            icon:SetAlpha(shouldShow and getIconRowOpacity(icon) or 0)
        else
            if shouldShow then
                if not icon:IsShown() then icon:Show() end
                setIconRowAlpha(icon)
            else
                if icon:IsShown() then icon:Hide() end
            end
        end
    end

    return controller
end
