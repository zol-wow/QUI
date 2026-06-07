local ADDON_NAME, ns = ...
local env = ns.ActionBarsEnv
env.ADDON_NAME = ADDON_NAME
env.ns = ns
env.SetChunkEnv(1, env)

---------------------------------------------------------------------------
-- BAR BUILD (native engine)
---------------------------------------------------------------------------

-- Get the ORIGINAL Blizzard buttons by name (bypassing nativeButtons cache).
-- Used during BuildBar to find buttons that need hiding.
function GetOriginalBlizzButtons(barKey)
    local buttons = {}
    local pattern = BUTTON_PATTERNS[barKey]
    local count = BUTTON_COUNTS[barKey] or 12
    if not pattern then return buttons end
    for i = 1, count do
        local buttonName = string.format(pattern, i)
        local button = _G[buttonName]
        if button then
            table.insert(buttons, button)
        end
    end
    return buttons
end

function SharedOwnedButtonUpdateCooldown(self)
    ActionBarsOwned.UpdateCooldown(self)
end

function SharedOwnedButtonUpdateCount(self)
    local action = self.action
    local count = self.Count
    if not action or not HasAction(action) then
        if count then count:SetText("") end
        return
    end

    if C_ActionBar and C_ActionBar.GetActionDisplayCount then
        if count then count:SetText(C_ActionBar.GetActionDisplayCount(action) or "") end
    elseif count then
        count:SetText("")
    end
end

function SharedOwnedButtonSetTooltip(self)
    if GetCVar("UberTooltips") == "1" then
        GameTooltip_SetDefaultAnchor(GameTooltip, self)
    else
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    end
    if GameTooltip:SetAction(self.action) then
        self.UpdateTooltip = self.SetTooltip
    else
        self.UpdateTooltip = nil
    end
end

function SharedOwnedButtonOnEvent(self, event, ...)
    if event == "ACTIONBAR_UPDATE_COOLDOWN"
        or event == "LOSS_OF_CONTROL_ADDED"
        or event == "LOSS_OF_CONTROL_UPDATE" then
        ActionBarsOwned.UpdateCooldown(self)
    else
        ActionBarsOwned.SafeUpdate(self)
    end
end

function SharedOwnedButtonPostDrag(self)
    OwnedButton_PostDrag(self)
end

ActionBarsOwned._sharedHandlers = ActionBarsOwned._sharedHandlers or {
    UpdateCooldown = SharedOwnedButtonUpdateCooldown,
    UpdateCount = SharedOwnedButtonUpdateCount,
    SetTooltip = SharedOwnedButtonSetTooltip,
    OnEvent = SharedOwnedButtonOnEvent,
    PostDrag = SharedOwnedButtonPostDrag,
}

function EnsureOwnedActionButton(container, barKey, btnName, index)
    local btn = _G[btnName]
    local existed = btn ~= nil
    if not btn then
        local ok
        ok, btn = pcall(CreateFrame, "CheckButton", btnName, container, "ActionButtonTemplate, SecureActionButtonTemplate")
        if not ok then btn = _G[btnName] end
        btn:SetAttribute("type", "action")
        btn:SetAttribute("checkselfcast", true)
        btn:SetAttribute("checkfocuscast", true)
        btn:SetAttribute("checkmouseovercast", true)
        btn:SetAttribute("useparent-unit", true)
        btn:SetAttribute("useparent-actionpage", true)
        btn:RegisterForDrag("LeftButton", "RightButton")
        btn:RegisterForClicks("AnyDown", "AnyUp")
        do
            local _db = GetDB()
            local _g = _db and _db.global
            btn:SetAttribute("useOnKeyDown", _g and _g.useOnKeyDown == true)
        end
        if not btn.HasPopup then
            local popupDir
            btn.HasPopup = true
            btn.SetPopupDirection = function(_, dir) popupDir = dir end
            btn.GetPopupDirection = function() return popupDir end
            btn.SetPopup = function(self2, popup)
                if popup then
                    rawset(self2, "_quiPopup", popup)
                end
            end
            btn.ClearPopup = function(self2)
                rawset(self2, "_quiPopup", nil)
            end
        end
        btn.flashing = 0
        btn.flashtime = 0
    else
        btn:SetParent(container)
    end
    btn._quiBarKey = barKey
    btn._quiButtonIndex = index
    btn:SetAttribute("qui-button-index", index)

    btn:SetAttribute("qui-refresh-ref", "btn-refresh-" .. barKey .. "-" .. index)
    InstallSecureActionFlagRefresh(btn)
    return btn, existed
end

function SetupPagedOwnedActionButton(btn, index)
    btn:SetAttribute("index", index)
    btn:SetAttribute("action", index)
    btn:SetAttribute("_childupdate-offset", [[
        local index = self:GetAttribute("index")
        local newAction = index + (message or 0)
        self:SetAttribute("action", newAction)
        self:RunAttribute("QUI_UpdateActionFlags")
        self:CallMethod("SafeSyncAction")
    ]])
    btn.SafeSyncAction = ActionBarsOwned.SafeSyncAction
    btn.UpdateCooldown = SharedOwnedButtonUpdateCooldown
    btn.UpdateCount = SharedOwnedButtonUpdateCount
end

function SetupFixedOwnedActionButton(container, btn, action)
    container:SetFrameRef("init-btn", btn)
    container:Execute(string.format([[
        local btn = self:GetFrameRef("init-btn")
        btn:SetAttribute("action", %d)
        btn:RunAttribute("QUI_UpdateActionFlags")
    ]], action))
end

function FinalizeStandardOwnedActionButtons(container, barKey, buttons)
    SetupSecureActionFlagRefresh(container)
    for i, btn in ipairs(buttons) do
        container:SetFrameRef("btn-refresh-" .. barKey .. "-" .. i, btn)
    end
end

function SuppressOriginalStandardBar(barFrame, barKey)
    if barFrame then
        HideManagedBlizzardBarFrame(barFrame, true)
    end
    local origButtons = GetOriginalBlizzButtons(barKey)
    for _, blizzBtn in ipairs(origButtons) do
        if barKey == "bar1" then
            blizzBtn:SetParent(hiddenBarParent)
        end
        SuppressBlizzardButton(blizzBtn)
    end
    if barKey == "bar1" then
        local leaveBtn = _G.MainMenuBarVehicleLeaveButton
        if leaveBtn then
            leaveBtn:SetParent(UIParent)
        end
    end
end

function BuildStandardOwnedButtons(container, barKey)
    local buttons = {}

    if barKey == "bar1" then
        for i = 1, 12 do
            local btnName = "QUI_Bar1Button" .. i
            local btn, existed = EnsureOwnedActionButton(container, barKey, btnName, i)
            if not existed then
                SetupPagedOwnedActionButton(btn, i)
                btn.action = i
            else
                btn.action = btn:GetAttribute("action") or i
            end
            btn:Show()
            buttons[i] = btn
        end
        SetupBar1Paging(container)
        return buttons
    end

    local offset = BAR_ACTION_OFFSETS[barKey] or 0
    local barNum = barKey:sub(4)
    for i = 1, 12 do
        local btnName = "QUI_Bar" .. barNum .. "Button" .. i
        local btn, existed = EnsureOwnedActionButton(container, barKey, btnName, i)
        local action = offset + i
        if not existed then
            SetupFixedOwnedActionButton(container, btn, action)
        end
        btn.action = action
        btn:Show()
        buttons[i] = btn
    end

    return buttons
end

function SetupStandardOwnedButtonRuntime(container, btn)
    btn:UnregisterAllEvents()
    btn:SetScript("OnEvent", SharedOwnedButtonOnEvent)
    btn.Update = ActionBarsOwned.SafeUpdate
    btn.UpdateAction = ActionBarsOwned.SafeSyncAction
    btn.SafeSyncAction = ActionBarsOwned.SafeSyncAction
    btn.UpdateCooldown = SharedOwnedButtonUpdateCooldown
    ---@type fun(...)
    btn.UpdatePressAndHoldAction = function() end
    btn.UpdateCount = SharedOwnedButtonUpdateCount
    if SetActionUIButton and btn.action and btn.cooldown then
        SetActionUIButton(btn, btn.action, btn.cooldown)
    end

    btn.SetTooltip = SharedOwnedButtonSetTooltip

    btn:SetAttribute("buttonlock", GetCVar("lockActionBars") == "1")
    btn.QUI_PostDrag = SharedOwnedButtonPostDrag

    if not btn.quiSecureHooksInstalled then
        btn.quiSecureHooksInstalled = true
        SecureHandlerWrapScript(btn, "OnAttributeChanged", btn, [[
            if name == "action" and IsPressHoldReleaseSpell and type(value) == "number" then
                self:RunAttribute("QUI_UpdateActionFlags")
            end
            if name == "action" then
                local container = self:GetParent()
                local flyoutHandler = container and container.GetFrameRef and container:GetFrameRef("qui-flyout-handler")
                if flyoutHandler and flyoutHandler:GetAttribute("flyoutParentHandle") == self then
                    local actionType, flyoutID = value and GetActionInfo(value)
                    if actionType ~= "flyout" or flyoutID ~= flyoutHandler:GetAttribute("flyoutID") then
                        flyoutHandler:Hide()
                    end
                end
            end
        ]])

        btn:HookScript("OnEnter", function(self)
            local global = GetGlobalSettings()
            if global and global.showTooltips == false then return end
            self:SetTooltip()
        end)
        btn:HookScript("OnLeave", function(self)
            self.UpdateTooltip = nil
            GameTooltip:Hide()
        end)

        if container then
            SecureHandlerWrapScript(btn, "OnClick", container, [[
                local flyoutHandler = owner:GetFrameRef("qui-flyout-handler")
                if self:GetAttribute("type") == "action" then
                    local action = self:GetAttribute("action")
                    local actionType, flyoutID, subType = action and GetActionInfo(action)
                    if actionType == "flyout" and flyoutHandler then
                        if not down then
                            local effectiveFlyoutID = self:GetAttribute("qui-flyout-id")
                            flyoutHandler:SetAttribute("flyoutParentHandle", self)
                            flyoutHandler:SetAttribute("flyoutID", effectiveFlyoutID)
                            flyoutHandler:RunAttribute("HandleFlyout")
                        end
                        return false
                    end
                    if flyoutHandler then
                        flyoutHandler:SetAttribute("flyoutID", nil)
                        flyoutHandler:Hide()
                    end
                    -- Pickup: a modified click on a locked bar should pick the
                    -- action up, not cast it, so temporarily clear on-down
                    -- casting (restored in the post-body). Done here in the
                    -- secure snippet rather than an insecure PreClick — an
                    -- insecure SetAttribute on useOnKeyDown taints the dispatch
                    -- and breaks AllowedWhenUntainted calls such as a /tm
                    -- macro's SetRaidTarget.
                    if button ~= "Keybind"
                        and self:GetAttribute("buttonlock")
                        and IsModifiedClick("PICKUPACTION")
                        and not self:GetAttribute("LABdisableDragNDrop")
                        and self:GetAttribute("useOnKeyDown") then
                        self:SetAttribute("qui-keydown-restore", true)
                        self:SetAttribute("useOnKeyDown", false)
                    end
                elseif flyoutHandler and (not down or self:GetParent() ~= flyoutHandler) then
                    flyoutHandler:SetAttribute("flyoutID", nil)
                    flyoutHandler:Hide()
                end
                if button == "Keybind" then
                    return "LeftButton"
                end
            ]], [[
                -- Restore on-down casting after a pickup click (see pre-body).
                if self:GetAttribute("qui-keydown-restore") then
                    self:SetAttribute("qui-keydown-restore", nil)
                    self:SetAttribute("useOnKeyDown", true)
                end
            ]])
        end

        btn:SetScript("OnDragStart", nil)
        SecureHandlerWrapScript(btn, "OnDragStart", btn, [[
            if (self:GetAttribute("buttonlock") and not IsModifiedClick("PICKUPACTION"))
                or self:GetAttribute("LABdisableDragNDrop") then
                return false
            end
            return "action", self:GetAttribute("action")
        ]])
        SecureHandlerWrapScript(btn, "OnDragStart", btn, [[
            return "message", "update"
        ]], [[
            self:CallMethod("QUI_PostDrag")
        ]])

        btn:SetScript("OnReceiveDrag", nil)
        SecureHandlerWrapScript(btn, "OnReceiveDrag", btn, [[
            if (self:GetAttribute("buttonlock") and not IsModifiedClick("PICKUPACTION"))
                or self:GetAttribute("LABdisableDragNDrop") then
                return false
            end
            return "action", self:GetAttribute("action")
        ]])
        SecureHandlerWrapScript(btn, "OnReceiveDrag", btn, [[
            return "message", "update"
        ]], [[
            self:CallMethod("QUI_PostDrag")
        ]])
    end
end

function PrimeStandardOwnedButtonVisuals(buttons)
    for _, btn in ipairs(buttons) do
        if ActionButton_Update then
            pcall(ActionButton_Update, btn)
        end
        ActionBarsOwned.UpdateCooldown(btn)
        ActionBarsOwned.UpdateOverlayGlow(btn)
    end
end

function BuildBar(barKey)
    local barFrame = GetBarFrame(barKey)

    if not ActionBarsOwned.containers[barKey] then
        ActionBarsOwned.containers[barKey] = CreateBarContainer(barKey)
    end
    local container = ActionBarsOwned.containers[barKey]

    local settings = GetEffectiveSettings(barKey)
    local buttons = {}

    if barKey == "bar1" or (barKey:match("^bar[2-8]$")) then
        SuppressOriginalStandardBar(barFrame, barKey)
        buttons = BuildStandardOwnedButtons(container, barKey)
    elseif barKey == "pet" or barKey == "stance" then
        -- PET/STANCE: Create fresh buttons from Blizzard templates, then
        -- fully suppress the originals (same pattern as bars 1-8 and
        -- action button addons).  Pet/stance buttons use GetID() for
        -- slot lookup — SetID is the only required setup.
        if barFrame then
            -- Purge Edit Mode's isShownExternal before reparenting to avoid
            -- tainting the Edit Mode system.  Writing enough nil keys pushes
            -- the tainted entry off the secure-variable tracking list.
            if barFrame.system then
                barFrame.isShownExternal = nil
                local c = 42
                repeat
                    if barFrame[c] == nil then
                        barFrame[c] = nil
                    end
                    c = c + 1
                until issecurevariable(barFrame, "isShownExternal")
            end
            barFrame:UnregisterAllEvents()
            barFrame:SetParent(hiddenBarParent)
            if barFrame.HideBase then
                barFrame:HideBase()
            else
                barFrame:Hide()
            end
            -- Do NOT write to the bar frame (numForms, Update, etc.) — any
            -- tainted write is read by ActionBarController, tainting its
            -- context and leaking into the ActionBarButtonEventsFrame dispatch.
            -- The bar is hidden + reparented + events unregistered; the
            -- controller's calls to Update/ShouldShow are harmless.
        end

        -- Suppress original Blizzard buttons — but for the pet bar we
        -- must leave the originals ALIVE (not UnregisterAllEvents, not
        -- statehidden).  Blizzard's native pet action bar keeps the
        -- server<->client state in sync via PetActionButton_OnEvent on
        -- the individual buttons — if we unregister their events, pet
        -- bar drag state fails to persist across /reload because the
        -- native sync path never runs.  The container is already
        -- hidden + reparented above, which is enough to make them
        -- invisible while preserving the native child-button event path.
        if barKey ~= "pet" then
            local origButtons = GetOriginalBlizzButtons(barKey)
            for _, blizzBtn in ipairs(origButtons) do
                SuppressBlizzardButton(blizzBtn)
            end
        end

        -- Create fresh buttons from the native template
        local template = barKey == "pet" and "PetActionButtonTemplate" or "StanceButtonTemplate"
        local prefix = barKey == "pet" and "QUI_PetButton" or "QUI_StanceButton"
        local count = BUTTON_COUNTS[barKey] or 10

        for i = 1, count do
            local btnName = prefix .. i
            local btn = _G[btnName]
            if not btn then
                local ok
                ok, btn = pcall(CreateFrame, "CheckButton", btnName, container, template)
                if not ok then btn = _G[btnName] end
                btn:SetID(i)
            else
                btn:SetParent(container)
            end
            -- Pet buttons inherit ActionButton OnEvent from the template, which
            -- runs BaseActionButtonMixin:Update (wrong for pet actions) and can
            -- taint the execution context.  Silence events — QUI drives pet
            -- button visuals via UpdatePetButton / UpdateAllPetButtons.
            if barKey == "pet" then
                btn:UnregisterAllEvents()
                btn:SetScript("OnEvent", nil)
                -- Pin the pet slot on the button itself so our drag
                -- overrides below don't depend on GetID() or on
                -- whatever the template's OnLoad populated.
                btn.id = i
                -- The inherited OnEnter is BaseActionButtonMixin:OnEnter →
                -- GameTooltip:SetAction(self.action), which is wrong for pet
                -- buttons (they have no .action).  Replace with SetPetAction.
                btn:SetScript("OnEnter", function(self)
                    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                    GameTooltip:SetPetAction(self:GetID())
                    GameTooltip:Show()
                end)
                btn:SetScript("OnLeave", GameTooltip_Hide)
                -- Explicit insecure drag handlers.  Pet action pickup /
                -- placement is not combat-protected, so plain Lua calls
                -- are fine here.  Overriding means we don't rely on the
                -- template's native OnDragStart / OnReceiveDrag, which
                -- may misbehave when the button is reparented outside
                -- the original PetActionBar frame or when the template
                -- internals read stale cached fields.
                btn:SetScript("OnDragStart", function(self)
                    if InCombatLockdown() then return end
                    local slot = self.id or self:GetID()
                    if not slot or slot < 1 then return end
                    self:SetChecked(false)
                    PickupPetAction(slot)
                    ActionBarsOwned.UpdatePetButton(self)
                end)
                btn:SetScript("OnReceiveDrag", function(self)
                    if InCombatLockdown() then return end
                    local slot = self.id or self:GetID()
                    if not slot or slot < 1 then return end
                    local cursorType = GetCursorInfo()
                    if cursorType == "petaction" then
                        self:SetChecked(false)
                        PickupPetAction(slot)
                        ActionBarsOwned.UpdatePetButton(self)
                    end
                end)
            end
            btn:Show()
            -- Both pet and stance bar-level Updates are suppressed — QUI
            -- drives button visuals directly via the Blizzard APIs.
            if barKey == "pet" then
                ActionBarsOwned.UpdatePetButton(btn)
            elseif barKey == "stance" then
                ActionBarsOwned.UpdateStanceButton(btn)
            end
            buttons[i] = btn
        end
    elseif barKey == "microbar" then
        -- MICRO MENU: Reparent individual micro buttons into QUI container.
        -- Fully silence the Blizzard container so its Layout() never fires
        -- during combat (which would propagate taint through our hooks).
        if barFrame then
            -- Purge Edit Mode's isShownExternal before reparenting to avoid
            -- tainting the Edit Mode system. Writing enough nil keys pushes
            -- the tainted entry off the secure-variable tracking list.
            if barFrame.system then
                barFrame.isShownExternal = nil
                local c = 42
                repeat
                    if barFrame[c] == nil then
                        barFrame[c] = nil
                    end
                    c = c + 1
                until issecurevariable(barFrame, "isShownExternal")
            end
            barFrame:UnregisterAllEvents()
            barFrame:SetParent(hiddenBarParent)
            -- Use the original C-side Hide to avoid Edit Mode's Lua override
            -- which can propagate taint on managed frames.
            if barFrame.HideBase then
                barFrame:HideBase()
            else
                barFrame:Hide()
            end
        end

        -- Suppress Blizzard's MicroMenu.Layout during reparenting — partially
        -- reparented children have nil positions, which crashes GetEdgeButton.
        local origLayout = MicroMenu and MicroMenu.Layout
        if MicroMenu then MicroMenu.Layout = function() end end

        -- Use explicit button list instead of fragile GetChildren enumeration
        ActionBarsOwned._microAnchors = {}
        for i, name in ipairs(MICRO_BUTTON_NAMES) do
            local btn = _G[name]
            if btn then
                -- Save original anchor for clean restoration during yield
                ActionBarsOwned._microAnchors[i] = { btn:GetPoint() }
                btn:SetParent(container)
                btn:Show()
                buttons[#buttons + 1] = btn
            end
        end

        -- HelpMicroButton shares StoreMicroButton's slot — reparent it into
        -- our container so Blizzard's Layout doesn't crash on orphaned children,
        -- but don't add it to the buttons array (LayoutNativeButtons handles it).
        local helpBtn = _G.HelpMicroButton
        if helpBtn then
            helpBtn:SetParent(container)
        end

        -- Restore MicroMenu.Layout now that all children are reparented
        if MicroMenu and origLayout then MicroMenu.Layout = origLayout end

        -- Apply clickthrough setting
        local barDB = GetBarSettings("microbar")
        if barDB and barDB.clickthrough then
            for _, btn in ipairs(buttons) do
                btn:EnableMouse(false)
            end
        end

        -- Hook Blizzard's layout to reclaim buttons if it tries to reparent them
        if not ActionBarsOwned._microLayoutHooked then
            ActionBarsOwned._microLayoutHooked = true

            -- Shared reclaim function: reparent stray buttons and reapply layout.
            -- During combat, defers via C_Timer.After(0) to break the taint
            -- chain from hooked Blizzard execution paths, then coalesces
            -- multiple hook fires into a single layout per frame.
            -- Reparenting (SetParent) is protected during combat,
            -- so that is deferred to PLAYER_REGEN_ENABLED, but SetPoint/SetScale
            -- on micro buttons works fine from untainted addon code.
            local microCombatLayoutPending = false
            local function ReclaimMicroButtons()
                if not ActionBarsOwned.initialized then return end
                -- Skip reclaim when Blizzard legitimately owns the buttons
                -- (vehicle, override bar, pet battle). The _microOwnedByUI
                -- flag is set by the MicroMenu:SetParent hook.
                if ActionBarsOwned._microOwnedByUI then return end

                -- Clear Blizzard's cached grid settings so its next Layout()
                -- doesn't reuse stale button positions from before QUI reclaimed.
                if MicroMenu then
                    MicroMenu.oldGridSettings = nil
                end

                local btns = ActionBarsOwned.nativeButtons["microbar"]
                local cont = ActionBarsOwned.containers["microbar"]
                if not btns or not cont then return end

                -- Check if any buttons need reparenting (protected during combat)
                local needsReparent = false
                for _, btn in ipairs(btns) do
                    if btn:GetParent() ~= cont then
                        needsReparent = true
                        break
                    end
                end

                if needsReparent and InCombatLockdown() then
                    -- SetParent is protected — defer reparenting to combat end
                    if not ActionBarsOwned._microDeferPending then
                        ActionBarsOwned._microDeferPending = true
                        ns.Addon:RegisterEvent("PLAYER_REGEN_ENABLED", function()
                            ns.Addon:UnregisterEvent("PLAYER_REGEN_ENABLED")
                            ActionBarsOwned._microDeferPending = false
                            ReclaimMicroButtons()
                        end)
                    end
                    return
                end

                if needsReparent then
                    for _, btn in ipairs(btns) do
                        if btn:GetParent() ~= cont then
                            btn:SetParent(cont)
                        end
                    end
                    -- Reclaim HelpMicroButton as well (shares Store's slot)
                    local helpBtn = _G.HelpMicroButton
                    if helpBtn and helpBtn:GetParent() ~= cont then
                        helpBtn:SetParent(cont)
                    end
                    -- Re-apply clickthrough after reparenting
                    local microDB = GetBarSettings("microbar")
                    local ct = microDB and microDB.clickthrough
                    for _, btn in ipairs(btns) do
                        btn:EnableMouse(not ct)
                    end
                end

                -- SetScale on the microbar container is protected during combat.
                -- Defer layout to combat end via a dedicated frame event handler
                -- (not ns.Addon:RegisterEvent, which would conflict with the
                -- reparent defer above).
                if InCombatLockdown() then
                    if not microCombatLayoutPending then
                        microCombatLayoutPending = true
                        local f = ActionBarsOwned._microLayoutFrame
                        if not f then
                            f = CreateFrame("Frame")
                            ActionBarsOwned._microLayoutFrame = f
                        end
                        f:RegisterEvent("PLAYER_REGEN_ENABLED")
                        f:SetScript("OnEvent", function(self)
                            self:UnregisterEvent("PLAYER_REGEN_ENABLED")
                            microCombatLayoutPending = false
                            if not ActionBarsOwned._microOwnedByUI then
                                LayoutNativeButtons("microbar")
                            end
                        end)
                    end
                else
                    LayoutNativeButtons("microbar")
                end
            end

            -- Yield micro buttons back to Blizzard when MicroMenu is
            -- reparented away from UIParent (vehicle, override, pet battle).
            -- Reclaim when it returns to UIParent.
            local function YieldMicroButtons()
                ActionBarsOwned._microOwnedByUI = true
                local btns = ActionBarsOwned.nativeButtons["microbar"]
                if btns and MicroMenu then
                    local savedAnchors = ActionBarsOwned._microAnchors
                    for i, btn in ipairs(btns) do
                        btn:SetParent(MicroMenu)
                        btn:EnableMouse(true)
                        -- Restore original anchor if saved
                        if savedAnchors and savedAnchors[i] then
                            btn:ClearAllPoints()
                            btn:SetPoint(unpack(savedAnchors[i]))
                        end
                    end
                    -- Return HelpMicroButton to MicroMenu as well
                    local helpBtn = _G.HelpMicroButton
                    if helpBtn then
                        helpBtn:SetParent(MicroMenu)
                    end
                end
            end

            local function ReclaimOrYield()
                if MicroMenu and MicroMenu:GetParent() ~= UIParent then
                    YieldMicroButtons()
                else
                    ActionBarsOwned._microOwnedByUI = false
                    ReclaimMicroButtons()
                end
            end

            -- Hook MicroMenu:SetParent — primary ownership detection.
            -- Fires when Blizzard reparents the frame for vehicle/override/
            -- pet battle transitions.
            if MicroMenu then
                hooksecurefunc(MicroMenu, "SetParent", function(_, parent)
                    if not ActionBarsOwned.initialized then return end
                    if parent == UIParent then
                        ActionBarsOwned._microOwnedByUI = false
                        ReclaimMicroButtons()
                    else
                        YieldMicroButtons()
                    end
                end)
            end

            -- Hook MicroMenuContainer AND MicroMenu Layout — both can fire
            -- when Blizzard re-layouts buttons (Edit Mode changes, grid
            -- recalculation, etc.). MicroMenu.Layout repositions individual
            -- buttons; MicroMenuContainer.Layout repositions the container.
            if MicroMenuContainer and MicroMenuContainer.Layout then
                hooksecurefunc(MicroMenuContainer, "Layout", ReclaimMicroButtons)
            end
            if MicroMenu and MicroMenu.Layout and MicroMenu ~= MicroMenuContainer then
                hooksecurefunc(MicroMenu, "Layout", ReclaimMicroButtons)
            end

            -- Hook UpdateMicroButtons — fires on many events (talent changes,
            -- guild updates, store state, etc.) and repositions buttons
            if UpdateMicroButtons then
                hooksecurefunc("UpdateMicroButtons", ReclaimMicroButtons)
            end

            -- Hook UpdateMicroButtonsParent — fires when Blizzard explicitly
            -- reparents micro buttons (vehicle, override bar, pet battle)
            if UpdateMicroButtonsParent then
                hooksecurefunc("UpdateMicroButtonsParent", ReclaimOrYield)
            end

            -- Hook ActionBarController_UpdateAll — fires on bar state changes
            -- (vehicle exit, stance changes) that can trigger button reparenting
            if ActionBarController_UpdateAll then
                hooksecurefunc("ActionBarController_UpdateAll", ReclaimMicroButtons)
            end

            -- Reclaim micro buttons when pet battle ends — no other hook
            -- reliably fires for this transition.
            if C_PetBattles then
                local petBattleFrame = CreateFrame("Frame")
                petBattleFrame:RegisterEvent("PET_BATTLE_CLOSE")
                petBattleFrame:SetScript("OnEvent", function()
                    if not ActionBarsOwned.initialized then return end
                    ActionBarsOwned._microOwnedByUI = false
                    -- Restore MicroMenu parent so the SetParent hook also fires
                    if MicroMenu and MicroMenu:GetParent() ~= UIParent then
                        MicroMenu:SetParent(UIParent)
                    else
                        ReclaimMicroButtons()
                    end
                end)
            end

            -- Reanchor MicroButtonAlert callouts when the microbar is near
            -- a screen edge so the alert bubble doesn't render off-screen.
            -- Blizzard's default is BOTTOM-of-alert to TOP-of-button (alert
            -- above button).  We flip to TOP-of-alert to BOTTOM-of-button
            -- when the button is in the upper portion of the screen, and
            -- nudge horizontally when near a side edge.
            if not ActionBarsOwned._microAlertAnchorHooked then
                ActionBarsOwned._microAlertAnchorHooked = true

                local EDGE_THRESHOLD_Y = 200  -- px from top before flipping
                local EDGE_THRESHOLD_X = 60   -- px from side before nudging

                local function ReanchorMicroAlert(button)
                    if not button then return end
                    local alert = button.alert
                    if not alert and button.GetName then
                        alert = _G[button:GetName() .. "Alert"]
                    end
                    -- FlashBorder/FlashContent are the button pulse textures,
                    -- not alert bubbles. Reanchoring them can detach Blizzard's
                    -- glow geometry from the micro button and inflate it.
                    if alert == button.FlashBorder or alert == button.FlashContent then
                        return
                    end
                    if not alert or not alert:IsShown() then return end

                    local screenH = GetScreenHeight()
                    local screenW = GetScreenWidth()
                    if not screenH or screenH == 0 then return end

                    local _, btnTop = button:GetCenter()
                    local btnLeft = button:GetLeft()
                    local btnRight = button:GetRight()
                    if not btnTop or not btnLeft then return end

                    -- Determine vertical anchor: flip below if near top
                    local nearTop = (screenH - btnTop) < EDGE_THRESHOLD_Y
                    -- Determine horizontal nudge
                    local xOff = 0
                    if btnLeft < EDGE_THRESHOLD_X then
                        xOff = EDGE_THRESHOLD_X - btnLeft
                    elseif btnRight and (screenW - btnRight) < EDGE_THRESHOLD_X then
                        xOff = -( EDGE_THRESHOLD_X - (screenW - btnRight) )
                    end

                    alert:ClearAllPoints()
                    if nearTop then
                        -- Alert below button
                        alert:SetPoint("TOP", button, "BOTTOM", xOff, -4)
                        -- Flip the arrow to point upward
                        if alert.Arrow then
                            alert.Arrow:ClearAllPoints()
                            alert.Arrow:SetPoint("BOTTOM", alert, "TOP", 0, -2)
                            alert.Arrow:SetTexCoord(0, 1, 1, 0) -- flip vertically
                        end
                    else
                        -- Alert above button (Blizzard default direction)
                        alert:SetPoint("BOTTOM", button, "TOP", xOff, 4)
                        if alert.Arrow then
                            alert.Arrow:ClearAllPoints()
                            alert.Arrow:SetPoint("TOP", alert, "BOTTOM", 0, 2)
                            alert.Arrow:SetTexCoord(0, 1, 0, 1) -- normal
                        end
                    end
                end

                -- Hook the global alert function to reposition after it sets up
                if type(MainMenuMicroButton_ShowAlert) == "function" then
                    hooksecurefunc("MainMenuMicroButton_ShowAlert", function(button)
                        C_Timer.After(0, function()
                            ReanchorMicroAlert(button)
                        end)
                    end)
                end
            end
        end
    elseif barKey == "bags" then
        -- BAG BAR: Reparent bag slot buttons into QUI container.
        -- Fully silence the Blizzard container so its Layout() never fires
        -- during combat (which would propagate taint through our hooks).
        if barFrame then
            if barFrame.system then
                barFrame.isShownExternal = nil
                local c = 42
                repeat
                    if barFrame[c] == nil then
                        barFrame[c] = nil
                    end
                    c = c + 1
                until issecurevariable(barFrame, "isShownExternal")
            end
            barFrame:UnregisterAllEvents()
            barFrame:SetParent(hiddenBarParent)
            if barFrame.HideBase then
                barFrame:HideBase()
            else
                barFrame:Hide()
            end
        end

        local bagButtons = GetBarButtons("bags")
        ---@type fun(...)
        local noopFunc = function() end
        for i, btn in ipairs(bagButtons) do
            btn:SetParent(container)
            btn:Show()
            -- Prevent Blizzard's expand/collapse animation from firing on
            -- reparented bag buttons.
            if btn.SetBarExpanded then
                btn.SetBarExpanded = noopFunc
            end
            buttons[i] = btn
        end

        -- Prevent BagsBar from responding to expand/collapse state changes
        -- which would trigger unnecessary Layout calls.
        if BagsBar and EventRegistry and EventRegistry.UnregisterCallback then
            pcall(EventRegistry.UnregisterCallback, EventRegistry, "MainMenuBarManager.OnExpandChanged", BagsBar)
        end

        -- Hook Blizzard's layout to reclaim buttons if it tries to reparent them
        if not ActionBarsOwned._bagsLayoutHooked then
            ActionBarsOwned._bagsLayoutHooked = true
            local bagsBar = BagsBar
            if bagsBar and bagsBar.Layout then
                hooksecurefunc(bagsBar, "Layout", function()
                    if not ActionBarsOwned.initialized then return end
                    if not ActionBarsOwned.nativeButtons["bags"] then return end
                    if InCombatLockdown() then
                        ActionBarsOwned.pendingBagsReclaim = true
                        return
                    end
                    C_Timer.After(0, function()
                        if InCombatLockdown() then
                            ActionBarsOwned.pendingBagsReclaim = true
                            return
                        end
                        local btns = ActionBarsOwned.nativeButtons["bags"]
                        local cont = ActionBarsOwned.containers["bags"]
                        if btns and cont then
                            for _, btn in ipairs(btns) do
                                if btn:GetParent() ~= cont then
                                    btn:SetParent(cont)
                                end
                            end
                            LayoutNativeButtons("bags")
                        end
                    end)
                end)
            end
        end
    end

    ActionBarsOwned.nativeButtons[barKey] = buttons
    if barKey ~= "pet" and barKey ~= "stance" and barKey ~= "microbar" and barKey ~= "bags" then
        FinalizeStandardOwnedActionButtons(container, barKey, buttons)
        if EnsureOwnedFlyoutFrame then
            local flyoutHandler = EnsureOwnedFlyoutFrame()
            if flyoutHandler then
                container:SetFrameRef("qui-flyout-handler", flyoutHandler)
            end
        end
    end

    -- Build slot→{button, barKey} lookup for O(1) ACTIONBAR_SLOT_CHANGED dispatch
    if not ActionBarsOwned.slotMap then ActionBarsOwned.slotMap = {} end
    for _, btn in ipairs(buttons) do
        if btn.action and btn.action > 0 then
            ActionBarsOwned.slotMap[btn.action] = { button = btn, barKey = barKey }
        end
    end

    -- Standard action bars (bar1-8): suppress Blizzard's event handling
    -- and shadow mixin methods with taint-safe versions.
    --
    -- Buttons ARE registered with SetActionUIButton so the C-side can
    -- push icon/cooldown/state updates (critical for assisted combat
    -- rotation which has no Lua event).  The taint-unsafe mixin methods
    -- (Update, UpdateAction, UpdateCooldown) are shadowed below with
    -- QUI's safe versions, so C-side ForceUpdateAction → btn:Update()
    -- hits SafeUpdate instead of the original mixin code.
    if barKey ~= "pet" and barKey ~= "stance" and barKey ~= "microbar" and barKey ~= "bags" then
        for _, btn in ipairs(buttons) do
            SetupStandardOwnedButtonRuntime(container, btn)
        end

        -- Populate visuals via the mixin (safe — GetActionCount is
        -- suppressed, and shadows are in place so any internal
        -- self:Method() calls hit the safe versions).
        PrimeStandardOwnedButtonVisuals(buttons)
    end

    -- Register frame refs for the secure layout handler (must be outside combat).
    if SKINNABLE_BAR_KEYS[barKey] then
        layoutHandler:SetFrameRef("bar-" .. barKey, container)
        for i, btn in ipairs(buttons) do
            layoutHandler:SetFrameRef("btn-" .. barKey .. "-" .. i, btn)
        end
    end

    -- Micro/bag buttons are not action buttons — skip skinning, keybinds, and override bindings
    if SKINNABLE_BAR_KEYS[barKey] then
        -- Defer skinning slightly so ActionButtonTemplate has time to
        -- populate icons and visuals from the action attribute.
        local capturedSettings = settings
        C_Timer.After(0, function()
            if not capturedSettings then return end
            local btns = ActionBarsOwned.nativeButtons[barKey]
            if not btns then return end
            for _, btn in ipairs(btns) do
                -- Reset skin key to force full re-skin
                local st = GetFrameState(btn)
                st.skinKey = nil
                SkinButton(btn, capturedSettings)
                UpdateButtonText(btn, capturedSettings)
                UpdateEmptySlotVisibility(btn, capturedSettings)
            end
        end)

        -- Register keybind methods for LibKeyBound
        local prefix = BINDING_COMMANDS[barKey]
        if prefix then
            local LKB = LibStub("LibKeyBound-1.0", true)
            for i, btn in ipairs(buttons) do
                local state = GetFrameState(btn)
                state.bindingCommand = prefix .. i
                state.keybindMethods = true
                -- Hook OnEnter so LibKeyBound detects hover.
                -- No OnLeave hook needed — the binder frame handles its own OnLeave.
                -- Guard against re-entry: if the binder is already targeting this
                -- button, skip Set() to avoid a show/hide flicker loop.
                if LKB then
                    btn:HookScript("OnEnter", function(self)
                        if LKB:IsShown() then
                            local bf = LKB.frame
                            if not bf or bf.button ~= self then
                                LKB:Set(self)
                            end
                        end
                    end)
                end
            end
        end
    end

    LayoutNativeButtons(barKey)
    RestoreContainerPosition(barKey)
    SetupOwnedBarMouseover(barKey)

    -- Action bars need override bindings (reparenting disconnects native bindings)
    if SKINNABLE_BAR_KEYS[barKey] then
        ApplyBarOverrideBindings(barKey)
    end

end

