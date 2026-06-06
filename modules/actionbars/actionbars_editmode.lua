local ADDON_NAME, ns = ...
local env = ns.ActionBarsEnv
env.ADDON_NAME = ADDON_NAME
env.ns = ns
env.SetChunkEnv(1, env)

---------------------------------------------------------------------------
-- EDIT MODE INTEGRATION
---------------------------------------------------------------------------

function CreateEditOverlay(container, barKey)
    local overlay = CreateFrame("Frame", nil, container, "BackdropTemplate")
    overlay:SetAllPoints(container)
    local core = GetCore()
    local px = (core and core.GetPixelSize and core:GetPixelSize(overlay)) or 1
    local edge2 = 2 * px
    overlay:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = edge2,
    })
    overlay:SetBackdropColor(0.2, 0.8, 0.6, 0.3)
    overlay:SetBackdropBorderColor(0.376, 0.647, 0.980, 1)
    overlay:EnableMouse(true)
    overlay:SetMovable(true)
    overlay:RegisterForDrag("LeftButton")
    overlay:SetFrameStrata("HIGH")
    overlay:Hide()

    local text = overlay:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    text:SetPoint("CENTER")
    local displayName = barKey:gsub("bar", "Bar ")
    text:SetText(displayName)
    overlay.label = text

    overlay:SetScript("OnDragStart", function()
        container:StartMoving()
    end)

    overlay:SetScript("OnDragStop", function()
        container:StopMovingOrSizing()
        SaveContainerPosition(barKey)
    end)

    return overlay
end

function EnsureEditOverlay(barKey)
    local container = ActionBarsOwned.containers[barKey]
    if not container then return nil end

    local overlay = ActionBarsOwned.editOverlays[barKey]
    if not overlay then
        overlay = CreateEditOverlay(container, barKey)
        ActionBarsOwned.editOverlays[barKey] = overlay
    end

    return overlay
end

function SetEditOverlayVisible(barKey, visible)
    local overlay = EnsureEditOverlay(barKey)
    if not overlay then return end

    if visible then
        overlay:Show()
    else
        overlay:Hide()
    end
end

function OnEditModeEnter()
    ActionBarsOwned.editModeActive = true
    if ActionBarsOwned.HideOwnedFlyout then
        ActionBarsOwned.HideOwnedFlyout()
    end

    for _, barKey in ipairs(ALL_MANAGED_BAR_KEYS) do
        local container = ActionBarsOwned.containers[barKey]
        if container then
            container:SetMovable(true)

            local state = GetOwnedBarFadeState(barKey)
            state.isFading = false
            CancelOwnedBarFadeTimers(state)
            SetOwnedBarAlpha(barKey, 1)

            SetEditOverlayVisible(barKey, true)
        end
    end
end

function OnEditModeExit()
    ActionBarsOwned.editModeActive = false

    for _, barKey in ipairs(ALL_MANAGED_BAR_KEYS) do
        if ActionBarsOwned.editOverlays[barKey] then
            ActionBarsOwned.editOverlays[barKey]:Hide()
        end

        SaveContainerPosition(barKey)
        LayoutNativeButtons(barKey)
        SetupOwnedBarMouseover(barKey)
    end
end

---------------------------------------------------------------------------
-- OVERRIDE BINDING APPLICATION
---------------------------------------------------------------------------

function IsVehicleBarActive()
    return (HasVehicleActionBar and HasVehicleActionBar())
        or (HasOverrideActionBar and HasOverrideActionBar())
        or (UnitInVehicle and UnitInVehicle("player"))
end

function IsPetBattleActive()
    return C_PetBattles and C_PetBattles.IsInBattle and C_PetBattles.IsInBattle()
end

-- Apply override bindings for a bar. All bars need this because reparenting
-- + SetID(0) disconnects buttons from Blizzard's native binding lookup.
function ApplyBarOverrideBindings(barKey)
    if InCombatLockdown() and not inInitSafeWindow then
        ActionBarsOwned.pendingBindings = true
        return
    end

    local container = ActionBarsOwned.containers[barKey]
    if not container then return end

    -- Clear existing override bindings on this bar's container
    ClearOverrideBindings(container)

    -- Vehicle guard: bar1 keybinds should pass through to Blizzard's
    -- vehicle/override bar natively when one is active.
    if barKey == "bar1" and IsVehicleBarActive() then
        return
    end

    -- Pet battle guard: all bindings should pass through to the pet
    -- battle UI natively.  Clear and return for every bar.
    if IsPetBattleActive() then
        return
    end

    -- Housing guard: housing has its own keybinds.
    if ActionBarsOwned._inHousing then
        return
    end

    local buttons = ActionBarsOwned.nativeButtons[barKey]
    local prefix = BINDING_COMMANDS[barKey]
    if not buttons or not prefix then return end

    for i, btn in ipairs(buttons) do
        local command = prefix .. i
        for ki = 1, select("#", GetBindingKey(command)) do
            local key = select(ki, GetBindingKey(command))
            if key then
                local existing = GetBindingAction(key, true)
                if not existing or existing == "" or existing == command then
                    -- Pet/stance buttons use PetActionButtonTemplate / StanceButtonTemplate
                    -- whose OnClick handlers check for "LeftButton" specifically.  Standard
                    -- action bars (SecureActionButtonTemplate) fire via secure attributes
                    -- regardless of button string, so "Keybind" works for them.
                    -- (Click-cast does NOT yield keys: it overrides them on @mouseover via
                    -- its own state driver, so off-frame the bar keybind set here fires.)
                    local vBtn = ((barKey == "pet" or barKey == "stance") or btn:GetAttribute("gse-button"))
                        and "LeftButton" or "Keybind"
                    SetOverrideBindingClick(container, false, key, btn:GetName(), vBtn)
                end
            end
        end
    end
end

-- Apply override bindings for all managed bars (including pet/stance)
function ApplyAllOverrideBindings()
    for _, barKey in ipairs(ALL_MANAGED_BAR_KEYS) do
        ApplyBarOverrideBindings(barKey)
    end
end

-- Compat aliases
ApplyBar1OverrideBindings = function() ApplyBarOverrideBindings("bar1") end

---------------------------------------------------------------------------
-- BAR 1 PAGING STATE DRIVER
---------------------------------------------------------------------------

function BuildPagingCondition()
    local parts = {}
    -- Override/vehicle/possess/shapeshift: use string tokens resolved
    -- dynamically in the _onstate-page restricted snippet (bar indices
    -- can change mid-session so must not be baked at build time).
    table.insert(parts, "[overridebar] override")
    table.insert(parts, "[vehicleui][possessbar][shapeshift] possess")
    -- Dragonriding (bonusbar:5)
    table.insert(parts, "[bonusbar:5] 11")
    -- Class-specific bonus bars (Druid forms, Rogue stealth, etc.)
    for i = 4, 1, -1 do
        table.insert(parts, "[bonusbar:" .. i .. "] " .. (6 + i))
    end
    -- Manual page switching
    for i = 6, 2, -1 do
        table.insert(parts, "[bar:" .. i .. "] " .. i)
    end
    -- Default page
    table.insert(parts, "1")
    return table.concat(parts, "; ")
end

bar1PagingInitialized = false

function SetupBar1Paging(container)
    if bar1PagingInitialized then return end
    bar1PagingInitialized = true

    -- Resolve override/possess/shapeshift bar indices dynamically in
    -- restricted code (they can change mid-session).  String tokens from
    -- BuildPagingCondition are converted to real page numbers here.
    container:SetAttribute("_onstate-page", [[
        local page = newstate
        if page == "override" then
            if HasVehicleActionBar and HasVehicleActionBar() then
                page = GetVehicleBarIndex()
            elseif HasOverrideActionBar and HasOverrideActionBar() then
                page = GetOverrideBarIndex()
            elseif HasTempShapeshiftActionBar and HasTempShapeshiftActionBar() then
                page = GetTempShapeshiftBarIndex()
            else
                page = 1
            end
        elseif page == "possess" then
            if HasVehicleActionBar and HasVehicleActionBar() then
                page = GetVehicleBarIndex()
            elseif HasOverrideActionBar and HasOverrideActionBar() then
                page = GetOverrideBarIndex()
            elseif HasTempShapeshiftActionBar and HasTempShapeshiftActionBar() then
                page = GetTempShapeshiftBarIndex()
            elseif HasBonusActionBar and HasBonusActionBar() then
                page = GetBonusBarIndex()
            else
                page = 1
            end
        end
        page = tonumber(page) or 1
        local offset = (page - 1) * 12
        control:ChildUpdate("offset", offset)
    ]])
    RegisterStateDriver(container, "page", BuildPagingCondition())
end

function SetupSecureActionFlagRefresh(container)
    if not container or container._quiActionFlagRefreshSetup then return end
    container._quiActionFlagRefreshSetup = true
    container:SetAttribute("qui-refresh-target", nil)
    container:SetAttribute("_onattributechanged", [[
        if name ~= "qui-refresh-target" then return end
        local ref = value and self:GetFrameRef(value)
        if ref then
            ref:RunAttribute("QUI_UpdateActionFlags")
        end
    ]])
end

