local ADDON_NAME, ns = ...
local env = ns.ActionBarsEnv
env.ADDON_NAME = ADDON_NAME
env.ns = ns
env.SetChunkEnv(1, env)

---@diagnostic disable: lowercase-global -- SetChunkEnv installs a setfenv

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

function SharedOwnedButtonPostDrag(self)
    OwnedButton_PostDrag(self)
end

function EnsureOwnedActionButton(container, barKey, btnName, index)
    local btn = _G[btnName]
    local existed = btn ~= nil
    if not btn then
        local ok
        ok, btn = ns.SafeCall("best-effort-style", CreateFrame, "CheckButton", btnName, container, "ActionBarButtonTemplate")
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

function SetupPagedOwnedActionButton(container, btn, index)
    btn:SetAttribute("index", index)
    btn:SetAttribute("_childupdate-offset", [[
        local index = self:GetAttribute("index")
        local newAction = index + (message or 0)
        self:SetAttribute("action", newAction)
        self:RunAttribute("QUI_UpdateActionFlags")
    ]])
    SetupFixedOwnedActionButton(container, btn, index)
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
                SetupPagedOwnedActionButton(container, btn, i)
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
        btn:Show()
        buttons[i] = btn
    end

    return buttons
end

function SetupStandardOwnedButtonRuntime(container, btn)
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
            if global and global.showTooltips == false then
                GameTooltip:Hide()
            end
        end)
        btn:HookScript("OnLeave", function(self)
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
            ns.SafeCall("best-effort-style", ActionButton_Update, btn)
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
        if barFrame then
            HideManagedBlizzardBarFrame(barFrame, true)
        end

        if barKey ~= "pet" then
            local origButtons = GetOriginalBlizzButtons(barKey)
            for _, blizzBtn in ipairs(origButtons) do
                SuppressBlizzardButton(blizzBtn)
            end
        end

        local template = barKey == "pet" and "PetActionButtonTemplate" or "StanceButtonTemplate"
        local prefix = barKey == "pet" and "QUI_PetButton" or "QUI_StanceButton"
        local count = BUTTON_COUNTS[barKey] or 10

        for i = 1, count do
            local btnName = prefix .. i
            local btn = _G[btnName]
            if not btn then
                local ok
                ok, btn = ns.SafeCall("best-effort-style", CreateFrame, "CheckButton", btnName, container, template)
                if not ok then btn = _G[btnName] end
                btn:SetID(i)
            else
                btn:SetParent(container)
            end
            if barKey == "pet" then
                btn:UnregisterAllEvents()
                btn:SetScript("OnEvent", nil)
                btn.id = i
                btn:SetScript("OnEnter", function(self)
                    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                    GameTooltip:SetPetAction(self:GetID())
                    GameTooltip:Show()
                end)
                btn:SetScript("OnLeave", GameTooltip_Hide)
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
            if barKey == "pet" then
                ActionBarsOwned.UpdatePetButton(btn)
            elseif barKey == "stance" then
                ActionBarsOwned.UpdateStanceButton(btn)
            end
            buttons[i] = btn
        end
    elseif barKey == "microbar" then
        if barFrame then
            HideManagedBlizzardBarFrame(barFrame, true)
        end

        local origLayout = MicroMenu and MicroMenu.Layout
        if MicroMenu then MicroMenu.Layout = function() end end

        ActionBarsOwned._microAnchors = {}
        for i, name in ipairs(MICRO_BUTTON_NAMES) do
            local btn = _G[name]
            if btn then
                ActionBarsOwned._microAnchors[i] = { btn:GetPoint() }
                btn:SetParent(container)
                btn:Show()
                buttons[#buttons + 1] = btn
            end
        end

        local helpBtn = _G.HelpMicroButton
        if helpBtn then
            helpBtn:SetParent(container)
        end

        if MicroMenu and origLayout then MicroMenu.Layout = origLayout end

        local barDB = GetBarSettings("microbar")
        if barDB and barDB.clickthrough then
            for _, btn in ipairs(buttons) do
                btn:EnableMouse(false)
            end
        end

        if not ActionBarsOwned._microLayoutHooked then
            ActionBarsOwned._microLayoutHooked = true

            local microCombatLayoutPending = false
            local function ReclaimMicroButtons()
                if not ActionBarsOwned.initialized then return end
                if ActionBarsOwned._microOwnedByUI then return end

                if MicroMenu then
                    MicroMenu.oldGridSettings = nil
                end

                local btns = ActionBarsOwned.nativeButtons["microbar"]
                local cont = ActionBarsOwned.containers["microbar"]
                if not btns or not cont then return end

                local needsReparent = false
                for _, btn in ipairs(btns) do
                    if btn:GetParent() ~= cont then
                        needsReparent = true
                        break
                    end
                end

                if needsReparent and InCombatLockdown() then
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
                    local helpBtn = _G.HelpMicroButton
                    if helpBtn and helpBtn:GetParent() ~= cont then
                        helpBtn:SetParent(cont)
                    end
                    local microDB = GetBarSettings("microbar")
                    local ct = microDB and microDB.clickthrough
                    for _, btn in ipairs(btns) do
                        btn:EnableMouse(not ct)
                    end
                end

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

            local function YieldMicroButtons()
                ActionBarsOwned._microOwnedByUI = true
                local btns = ActionBarsOwned.nativeButtons["microbar"]
                if btns and MicroMenu then
                    local savedAnchors = ActionBarsOwned._microAnchors
                    for i, btn in ipairs(btns) do
                        btn:SetParent(MicroMenu)
                        btn:EnableMouse(true)
                        if savedAnchors and savedAnchors[i] then
                            btn:ClearAllPoints()
                            btn:SetPoint(unpack(savedAnchors[i]))
                        end
                    end
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

            if MicroMenuContainer and MicroMenuContainer.Layout then
                hooksecurefunc(MicroMenuContainer, "Layout", ReclaimMicroButtons)
            end
            if MicroMenu and MicroMenu.Layout and MicroMenu ~= MicroMenuContainer then
                hooksecurefunc(MicroMenu, "Layout", ReclaimMicroButtons)
            end

            if MicroMenu and MicroMenu.UpdateHelpTicketButtonAnchor then
                local ticketAnchorPending = false
                hooksecurefunc(MicroMenu, "UpdateHelpTicketButtonAnchor", function()
                    if not ActionBarsOwned.initialized then return end
                    if ticketAnchorPending then return end
                    ticketAnchorPending = true
                    C_Timer.After(0, function()
                        ticketAnchorPending = false
                        AnchorHelpTicketButton()
                    end)
                end)
            end

            if UpdateMicroButtons then
                hooksecurefunc("UpdateMicroButtons", ReclaimMicroButtons)
            end

            if UpdateMicroButtonsParent then
                hooksecurefunc("UpdateMicroButtonsParent", ReclaimOrYield)
            end

            if ActionBarController_UpdateAll then
                hooksecurefunc("ActionBarController_UpdateAll", ReclaimMicroButtons)
            end

            if C_PetBattles then
                local petBattleFrame = CreateFrame("Frame")
                petBattleFrame:RegisterEvent("PET_BATTLE_CLOSE")
                petBattleFrame:SetScript("OnEvent", function()
                    if not ActionBarsOwned.initialized then return end
                    ActionBarsOwned._microOwnedByUI = false
                    if MicroMenu and MicroMenu:GetParent() ~= UIParent then
                        MicroMenu:SetParent(UIParent)
                    else
                        ReclaimMicroButtons()
                    end
                end)
            end

            if not ActionBarsOwned._microAlertAnchorHooked then
                ActionBarsOwned._microAlertAnchorHooked = true

                local EDGE_THRESHOLD_Y = 200
                local EDGE_THRESHOLD_X = 60

                local function ReanchorMicroAlert(button)
                    if not button then return end
                    local alert = button.alert
                    if not alert and button.GetName then
                        alert = _G[button:GetName() .. "Alert"]
                    end
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

                    local nearTop = (screenH - btnTop) < EDGE_THRESHOLD_Y
                    local xOff = 0
                    if btnLeft < EDGE_THRESHOLD_X then
                        xOff = EDGE_THRESHOLD_X - btnLeft
                    elseif btnRight and (screenW - btnRight) < EDGE_THRESHOLD_X then
                        xOff = -( EDGE_THRESHOLD_X - (screenW - btnRight) )
                    end

                    alert:ClearAllPoints()
                    if nearTop then
                        alert:SetPoint("TOP", button, "BOTTOM", xOff, -4)
                        if alert.Arrow then
                            alert.Arrow:ClearAllPoints()
                            alert.Arrow:SetPoint("BOTTOM", alert, "TOP", 0, -2)
                            alert.Arrow:SetTexCoord(0, 1, 1, 0)
                        end
                    else
                        alert:SetPoint("BOTTOM", button, "TOP", xOff, 4)
                        if alert.Arrow then
                            alert.Arrow:ClearAllPoints()
                            alert.Arrow:SetPoint("TOP", alert, "BOTTOM", 0, 2)
                            alert.Arrow:SetTexCoord(0, 1, 0, 1)
                        end
                    end
                end

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
        if barFrame then
            HideManagedBlizzardBarFrame(barFrame, true)
        end

        local bagButtons = GetBarButtons("bags")
        ---@type fun(...)
        local noopFunc = function() end
        for i, btn in ipairs(bagButtons) do
            btn:SetParent(container)
            btn:Show()
            if btn.SetBarExpanded then
                btn.SetBarExpanded = noopFunc
            end
            buttons[i] = btn
        end

        if BagsBar and EventRegistry and EventRegistry.UnregisterCallback then
            ns.SafeCallMethod("best-effort-style", EventRegistry, "UnregisterCallback", "MainMenuBarManager.OnExpandChanged", BagsBar)
        end

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

    if not ActionBarsOwned.slotMap then ActionBarsOwned.slotMap = {} end
    for _, btn in ipairs(buttons) do
        if btn.action and btn.action > 0 then
            ActionBarsOwned.slotMap[btn.action] = { button = btn, barKey = barKey }
        end
    end

    if barKey ~= "pet" and barKey ~= "stance" and barKey ~= "microbar" and barKey ~= "bags" then
        for _, btn in ipairs(buttons) do
            SetupStandardOwnedButtonRuntime(container, btn)
        end

        PrimeStandardOwnedButtonVisuals(buttons)
    end

    if SKINNABLE_BAR_KEYS[barKey] then
        layoutHandler:SetFrameRef("bar-" .. barKey, container)
        for i, btn in ipairs(buttons) do
            layoutHandler:SetFrameRef("btn-" .. barKey .. "-" .. i, btn)
        end
    end

    if SKINNABLE_BAR_KEYS[barKey] then
        local capturedSettings = settings
        C_Timer.After(0, function()
            if not capturedSettings then return end
            local btns = ActionBarsOwned.nativeButtons[barKey]
            if not btns then return end
            for _, btn in ipairs(btns) do
                local st = GetFrameState(btn)
                st.sk_sz = nil
                SkinButton(btn, capturedSettings)
                UpdateButtonText(btn, capturedSettings)
                UpdateEmptySlotVisibility(btn, capturedSettings)
            end
        end)

        local prefix = BINDING_COMMANDS[barKey]
        if prefix then
            local LKB = LibStub("LibKeyBound-1.0", true)
            for i, btn in ipairs(buttons) do
                local state = GetFrameState(btn)
                state.bindingCommand = prefix .. i
                state.keybindMethods = true
                if LKB and not state.lkbHooked then
                    state.lkbHooked = true
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

    if SKINNABLE_BAR_KEYS[barKey] then
        ApplyBarOverrideBindings(barKey)
    end

end
