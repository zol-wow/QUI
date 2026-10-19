local _, ns = ...
local Helpers = ns.Helpers
local icons = setmetatable({}, { __mode = "k" })
local travelSpells = { [783] = true, [1066] = true, [33943] = true, [40120] = true }

local function RefreshVisibleCDM()
    if ns.RefreshCDMVisibilityForClick then ns.RefreshCDMVisibilityForClick() end
end

local function GetClickCondition()
    local profile = ns.Addon and ns.Addon.db and ns.Addon.db.profile
    local vis = profile and profile.cdmVisibility
    if vis and (vis.showWhenHealthBelow100 or not (vis.showInCombat or vis.showAlways)
        or vis.hideWhenInVehicle
        or (vis.hideWhenSkyriding and not (vis.hideWhenMounted or vis.hideWhenFlying))) then
        return nil
    end
    if profile and profile.ncdm and profile.ncdm.enabled == false then
        return "hidden"
    end
    local conditions = { "[nocombat] alpha" }
    local ignoreHides = vis and vis.dontHideInDungeonsRaids and Helpers.IsPlayerInDungeonOrRaid()
    if vis and not ignoreHides and (vis.fadeOutAlpha or 0) <= 0.001 then
        if vis.hideWhenMounted then
            conditions[#conditions + 1] = "[mounted] hidden"
            local forms = {}
            for i = 1, GetNumShapeshiftForms() do
                local _, _, _, spellID = GetShapeshiftFormInfo(i)
                if travelSpells[spellID] then
                    forms[#forms + 1] = tostring(i)
                end
            end
            if #forms > 0 then
                conditions[#conditions + 1] = "[form:" .. table.concat(forms, "/") .. "] hidden"
            end
        end
        if vis.hideWhenFlying then
            conditions[#conditions + 1] = "[flying] hidden"
        end
    end
    conditions[#conditions + 1] = "shown"
    return table.concat(conditions, "; ")
end

function ns.SyncCDMClickVisibility(icon, hidden)
    local button = icon and icon.clickButton
    if not button then return false end
    if InCombatLockdown() then return button._quiClickVisibilityManaged == true end

    local viewerType = icon._quiCdmClickViewerType or (icon._spellEntry and icon._spellEntry.viewerType)
    local eligible = not icon._quiLayoutRestricted and (viewerType == "essential" or viewerType == "utility")
    icons[icon] = eligible or nil
    local condition = eligible and GetClickCondition() or nil
    if hidden == nil and (condition or button._quiClickVisibilityManaged) then
        local alpha = icon:GetEffectiveAlpha()
        hidden = (issecretvalue and issecretvalue(alpha)) or alpha <= 0.001
    end
    if not condition then
        if button._quiClickVisibilityManaged then
            UnregisterStateDriver(button, "quiclick")
            button._quiClickVisibilityManaged = nil
            button._quiClickCondition = nil
            button:EnableMouse(not hidden)
            icon._pendingVisibilityMouseSync = true
        end
        return false
    end

    button._quiClickVisibilityManaged = true
    local enabled = not hidden and condition ~= "hidden"
        and not Helpers.IsEditModeActive() and not Helpers.IsLayoutModeActive()
    button:SetAttribute("qui-alpha-visible", enabled)
    if button._quiClickCondition ~= condition then
        button.QUIRefreshClickVisibility = RefreshVisibleCDM
        button:SetAttribute("_onstate-quiclick", [[
            if newstate == "shown" then self:CallMethod("QUIRefreshClickVisibility") end
            self:EnableMouse(newstate == "shown"
                or (newstate == "alpha" and self:GetAttribute("qui-alpha-visible")))
        ]])
        RegisterStateDriver(button, "quiclick", condition)
        button._quiClickCondition = condition
    end
    button:EnableMouse(enabled)
    icon:SetMouseClickEnabled(false)
    local restoreAction = icon._quiClickButtonSuppressed
    icon._quiClickButtonSuppressed = nil
    icon._pendingVisibilityMouseSync = nil
    if restoreAction and ns.CDMIcons and ns.CDMIcons.OnContainerIconInteractionRestored then
        ns.CDMIcons.OnContainerIconInteractionRestored(icon, viewerType)
    end
    return true
end

function ns.RefreshCDMClickVisibility()
    if InCombatLockdown() then return end
    for icon in pairs(icons) do
        ns.SyncCDMClickVisibility(icon)
    end
end
