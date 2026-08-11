local ADDON_NAME, ns = ...
local S = ns.AuraSurface or {}
ns.AuraSurface = S
_G.QUI = _G.QUI or {}
_G.QUI.AuraSurface = S

local function EnsurePool(host)
    local pool = host._quiAuraContainers
    if not pool then
        pool = {}
        host._quiAuraContainers = pool
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

    local pool = EnsurePool(host)
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
            if opts.skip and opts.skip(element) then
                container:SetEnabled(false)
                container:Hide()
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

    if incomplete and opts.onIncomplete then
        opts.onIncomplete(host)
    end
    return not incomplete
end

return S
