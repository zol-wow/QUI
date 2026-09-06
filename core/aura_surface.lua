local ADDON_NAME, ns = ...
local S = ns.AuraSurface or {}
ns.AuraSurface = S
_G.QUI = _G.QUI or {}
_G.QUI.AuraSurface = S

local function EnsurePool(host, key)
    local pool = host[key]
    if not pool then
        pool = {}
        host[key] = pool
    end
    return pool
end

function S.ApplyElementPass(host, elements, opts)
    if type(host) ~= "table" or type(elements) ~= "table" or type(opts) ~= "table" then
        return false
    end
    local unit = opts.unit
    if type(unit) ~= "string" then return false end
    if type(opts.profileFor) ~= "function" or type(opts.anchorContainer) ~= "function" then
        return false
    end

    local AuraGlue = ns.AuraGlue
    local AuraSlots = ns.AuraSlots
    if not (AuraGlue and AuraSlots) then return false end

    local pool = EnsurePool(host, "_quiAuraContainers")
    local inactivePool = opts.showInactive ~= nil
        and EnsurePool(host, "_quiAuraInactiveContainers") or nil
    local allowCreate = opts.allowCreate == true
    local cancelEligible = opts.cancelEligible == true
    local incomplete = false

    for i = 1, #elements do
        local element = elements[i]
        local container = pool[i]
        if not container then
            if allowCreate and CreateFrame then
                container = CreateFrame("AuraContainer", nil, host, "CustomAuraContainerTemplate")
                if container then
                    container:SetSize(1, 1)
                    pool[i] = container
                else
                    incomplete = true
                end
            else
                incomplete = true
            end
        end
        if container then
            if opts.onContainerReady
                and opts.onContainerReady(container, host, i) == false then
                incomplete = true
            end
            container:SetUnit(unit)
            local profile = opts.profileFor(element)
            opts.anchorContainer(container, host, element, profile)
            local skipped = opts.skip and opts.skip(element)
            local dynamic = type(AuraSlots.UsesDynamicGroups) == "function"
                and AuraSlots.UsesDynamicGroups(element)
            if skipped then
                if element.mode == "tracked" then AuraSlots.Park(container) end
                container:SetEnabled(false)
                container:Hide()
            elseif element.mode == "tracked" and dynamic then
                -- Packed tracked icons ride Blizzard aura groups (one per
                -- spell) so hidden auras leave no gap; any slots from an
                -- earlier fixed-layout pass are parked.
                local groups = AuraSlots.DynamicGroups(container, element, profile)
                if not AuraGlue.RunConfigPass(container, profile, groups, allowCreate) then
                    incomplete = true
                end
                AuraSlots.Park(container)
                container:SetEnabled(true)
                container:Show()
            elseif element.mode == "tracked" then
                if not AuraGlue.RunConfigPass(container, profile, {}, allowCreate) then
                    incomplete = true
                end
                if not AuraSlots.Sync(container, element, allowCreate, opts.profileOverrides) then
                    incomplete = true
                end
                container:SetEnabled(true)
                container:Show()
            else
                local groups = AuraGlue.ElementGroups(unit, element, profile, cancelEligible)
                if not AuraGlue.RunConfigPass(container, profile, groups, allowCreate) then
                    incomplete = true
                end
                AuraSlots.Park(container)
                container:SetEnabled(true)
                container:Show()
            end

            if inactivePool then
                local inactiveContainer = inactivePool[i]
                local inactiveEligible = element.mode == "tracked" and not dynamic
                    and (element.displayType == nil or element.displayType == "icon")
                local wantInactive = inactiveEligible and not skipped and opts.showInactive == true
                if wantInactive and not inactiveContainer then
                    if allowCreate and CreateFrame then
                        inactiveContainer = CreateFrame("Frame", nil, host)
                        inactiveContainer:SetSize(1, 1)
                        inactiveContainer:SetFrameLevel(math.max(0, container:GetFrameLevel() - 1))
                        inactivePool[i] = inactiveContainer
                    else
                        incomplete = true
                    end
                end
                if inactiveContainer then
                    opts.anchorContainer(inactiveContainer, host, element, profile)
                    if inactiveEligible then
                        if not AuraSlots.SyncInactiveIcons(inactiveContainer, element,
                            allowCreate, wantInactive) then
                            incomplete = true
                        end
                    else
                        AuraSlots.HideInactiveIcons(inactiveContainer)
                    end
                end
            end
        end
    end

    for i = #elements + 1, #pool do
        local container = pool[i]
        if not AuraGlue.RunConfigPass(container, container._quiProfile or {}, {}, allowCreate) then
            incomplete = true
        end
        AuraSlots.Park(container)
        container:SetEnabled(false)
        container:Hide()
    end
    if inactivePool then
        for i = #elements + 1, #inactivePool do
            AuraSlots.HideInactiveIcons(inactivePool[i])
        end
    end

    if incomplete and opts.onIncomplete then
        opts.onIncomplete(host)
    end
    return not incomplete
end

return S
