local ADDON_NAME, ns = ...
local env = ns.ActionBarsEnv
env.ADDON_NAME = ADDON_NAME
env.ns = ns
env.SetChunkEnv(1, env)

---@diagnostic disable: lowercase-global -- SetChunkEnv installs a setfenv

local function ComputeGridColRow(idx, isVertical, numCols, numRows)
    if isVertical then
        return math.floor(idx / numRows), idx % numRows
    end
    return idx % numCols, math.floor(idx / numCols)
end

function GetOwnedLayout(barKey)
    local barDB = GetBarSettings(barKey)
    local profile = nil
    local core = GetCore()
    if core and core.db then
        profile = core.db.profile
    end

    if type(barDB) == "table"
        and type(profile) == "table"
        and profile._legacyMainlineUsesEditModeActionBars
        and (barKey == "bar1" or barKey == "bar2" or barKey == "bar3" or barKey == "bar4"
            or barKey == "bar5" or barKey == "bar6" or barKey == "bar7" or barKey == "bar8")
    then
        local layout = rawget(barDB, "ownedLayout")
        local expectedColumns = (barKey == "bar4" or barKey == "bar5") and 6 or 12
        local isSyntheticLayout = type(layout) == "table"
            and (layout.orientation or "horizontal") == "horizontal"
            and (layout.columns or 12) == expectedColumns
            and (layout.iconCount or 12) == 12
            and layout.buttonSize == nil
            and layout.buttonSpacing == nil
            and layout.buttonHeight == nil
            and (layout.growUp or false) == false
            and (layout.growLeft or false) == false

        if layout == nil or isSyntheticLayout then
            local barFrame = GetBarFrame(barKey)
            if barFrame and barFrame.GetSettingValue and Enum and Enum.EditModeActionBarSetting then
                local allButtons = GetBarButtons(barKey)
                local buttonCount = #allButtons
                if buttonCount > 0 then
                    local EditModeSettings = Enum.EditModeActionBarSetting
                    local okOrientation, orientation = pcall(barFrame.GetSettingValue, barFrame, EditModeSettings.Orientation)
                    local okRows, numRows = pcall(barFrame.GetSettingValue, barFrame, EditModeSettings.NumRows)
                    local okIcons, numIcons = pcall(barFrame.GetSettingValue, barFrame, EditModeSettings.NumIcons)
                    if not okIcons or type(numIcons) ~= "number" or numIcons <= 0 then
                        numIcons = buttonCount
                    else
                        numIcons = math.min(numIcons, buttonCount)
                    end

                    local isVertical = okOrientation and orientation == 1
                    local columns = 12
                    if okRows and type(numRows) == "number" and numRows > 0 then
                        if isVertical then
                            columns = numRows
                        else
                            columns = math.ceil(numIcons / numRows)
                        end
                    end

                    return isVertical and "vertical" or "horizontal", math.max(1, columns), numIcons, false, false, nil, nil, nil
                end
            end
        end
    end

    local layout = barDB and barDB.ownedLayout
    if not layout then
        return "horizontal", 12, 12, false, false, nil, nil, nil
    end
    return
        layout.orientation or "horizontal",
        layout.columns or 12,
        layout.iconCount or 12,
        layout.growUp or false,
        layout.growLeft or false,
        layout.buttonSize,
        layout.buttonSpacing,
        layout.buttonHeight
end

do
    ActionBarsOwned._visibleButtonCounts = ActionBarsOwned._visibleButtonCounts or {}

    local function ClampVisibleButtonCount(barKey, iconCount, buttonCount)
        local maxButtons = buttonCount or BUTTON_COUNTS[barKey] or 12
        local count = type(iconCount) == "number" and iconCount or maxButtons
        if count < 0 then count = 0 end
        if maxButtons > 0 and count > maxButtons then count = maxButtons end
        return count
    end

    local function GetVisibleButtonCount(barKey)
        if not barKey then return nil end
        local cached = ActionBarsOwned._visibleButtonCounts[barKey]
        if cached then return cached end
        local buttons = ActionBarsOwned.nativeButtons and ActionBarsOwned.nativeButtons[barKey]
        local buttonCount = buttons and #buttons or BUTTON_COUNTS[barKey] or 12
        local _, _, iconCount = GetOwnedLayout(barKey)
        return ClampVisibleButtonCount(barKey, iconCount, buttonCount)
    end

    IsButtonInsideVisibleLayout = function(button, barKey)
        if not button then return false end
        if not STANDARD_BAR_KEY_SET[barKey] then return true end

        local index = GetButtonIndex(button)
        if not index then return true end

        return index <= GetVisibleButtonCount(barKey)
    end
end

AnchorHelpTicketButton = function()
    if ActionBarsOwned._microOwnedByUI then return end
    local ticketBtn = _G.HelpOpenWebTicketButton
    local charBtn = _G.CharacterMicroButton
    if not (ticketBtn and charBtn) then return end

    local barDB = GetBarSettings("microbar")
    local iconDB = barDB and barDB.ticketIcon
    local mode = (iconDB and iconDB.position) or "auto"
    local offX = (iconDB and iconDB.offsetX) or 0
    local offY = (iconDB and iconDB.offsetY) or 0

    local anchorAbove
    if mode == "above" then
        anchorAbove = true
    elseif mode == "below" then
        anchorAbove = false
    else
        anchorAbove = ActionBarsOwned._helpTicketAnchorAbove
        if not InCombatLockdown() then
            local _, cy = charBtn:GetCenter()
            local screenH = UIParent:GetHeight()
            if cy and screenH and screenH > 0 then
                local relScale = charBtn:GetEffectiveScale() / UIParent:GetEffectiveScale()
                anchorAbove = (cy * relScale) < (screenH / 2)
                ActionBarsOwned._helpTicketAnchorAbove = anchorAbove
            end
        end
        if anchorAbove == nil then anchorAbove = true end
    end

    if anchorAbove then
        ticketBtn:SetPoint("CENTER", charBtn, "TOP", offX, 21 + offY)
    else
        ticketBtn:SetPoint("CENTER", charBtn, "BOTTOM", offX, -21 + offY)
    end
end

LayoutNativeButtons = function(barKey)
    local container = ActionBarsOwned.containers[barKey]
    local buttons = ActionBarsOwned.nativeButtons[barKey]
    if not container or not buttons or #buttons == 0 then return end

    local settings = GetGlobalSettings()

    local orientation, columns, iconCount, growUp, growLeft, sizeOverride, spacingOverride, heightOverride = GetOwnedLayout(barKey)

    if barKey == "stance" and GetNumShapeshiftForms then
        local numForms = GetNumShapeshiftForms() or 0
        if numForms > 0 then
            iconCount = math.min(iconCount, numForms)
        end
    end

    local isVertical = (orientation == "vertical")

    local numVisible = math.min(iconCount, #buttons)
    ActionBarsOwned._visibleButtonCounts[barKey] = numVisible
    if numVisible == 0 then
        for _, btn in ipairs(buttons) do
            ActionBarsOwned._activeButtons[btn] = nil
            ActionBarsOwned._activeStandardButtons[btn] = nil
        end
        return
    end
    if STANDARD_BAR_KEY_SET[barKey] then
        for i = numVisible + 1, #buttons do
            local btn = buttons[i]
            ActionBarsOwned._activeButtons[btn] = nil
            ActionBarsOwned._activeStandardButtons[btn] = nil
        end
    end

    local desiredSize
    if sizeOverride and sizeOverride > 0 then
        desiredSize = sizeOverride
    else
        local iconSize = settings and settings.iconSize
        if iconSize and iconSize > 0 then
            desiredSize = iconSize
        else
            desiredSize = 36
        end
    end

    if not ActionBarsOwned.cachedNaturalSize then
        ActionBarsOwned.cachedNaturalSize = {}
    end
    local naturalSize
    if not InCombatLockdown() then
        naturalSize = math.floor((buttons[1]:GetWidth() or 45) + 0.5)
        if naturalSize < 10 then naturalSize = 45 end
        ActionBarsOwned.cachedNaturalSize[barKey] = naturalSize
    else
        naturalSize = ActionBarsOwned.cachedNaturalSize[barKey] or 45
    end

    local spacing
    if spacingOverride then
        spacing = spacingOverride
    else
        spacing = settings and settings.buttonSpacing or 2
    end

    local Core = GetCore()
    local px = Core and Core.GetPixelSize and Core:GetPixelSize(container) or nil
    if px and px > 0 then
        desiredSize = math.floor(desiredSize / px + 0.5) * px
        spacing = math.floor(spacing / px + 0.5) * px
    end

    local desiredHeight = desiredSize
    if heightOverride and heightOverride > 0 then
        desiredHeight = heightOverride
        if px and px > 0 then
            desiredHeight = math.floor(desiredHeight / px + 0.5) * px
        end
    end

    local btnScale = desiredSize / naturalSize

    local numCols, numRows
    if isVertical then
        local buttonsPerCol = math.max(1, columns)
        numRows = buttonsPerCol
        numCols = math.ceil(numVisible / buttonsPerCol)
    else
        numCols = math.max(1, columns)
        numRows = math.ceil(numVisible / numCols)
    end

    local anchor
    if growUp then
        anchor = growLeft and "BOTTOMRIGHT" or "BOTTOMLEFT"
    else
        anchor = growLeft and "TOPRIGHT" or "TOPLEFT"
    end

    local groupWidth = numCols * desiredSize + math.max(0, numCols - 1) * spacing
    local groupHeight = numRows * desiredHeight + math.max(0, numRows - 1) * spacing

    local xStep = (desiredSize + spacing) / btnScale
    local yStep = (desiredHeight + spacing) / btnScale
    local xDir = growLeft and -1 or 1
    local yDir = growUp and 1 or -1

    if SKINNABLE_BAR_KEYS[barKey] then
        local positions = {}
        for i = 1, numVisible do
            local idx = i - 1
            local col, row = ComputeGridColRow(idx, isVertical, numCols, numRows)
            positions[i] = {
                x = col * xStep * xDir,
                y = row * yStep * yDir,
            }
        end

        SecureLayoutBar(barKey, buttons, numVisible, anchor, btnScale, positions, groupWidth, groupHeight)
    else
        for i, btn in ipairs(buttons) do
            if i <= numVisible then
                btn:SetScale(btnScale)
                btn:ClearAllPoints()
                local idx = i - 1
                local col, row = ComputeGridColRow(idx, isVertical, numCols, numRows)
                btn:SetPoint(anchor, container, anchor, col * xStep * xDir, row * yStep * yDir)
                btn:Show()
            else
                btn:Hide()
            end
        end
        container:SetScale(1)
        container:SetSize(groupWidth, groupHeight)
    end

    if barKey == "microbar" then
        local helpBtn = _G.HelpMicroButton
        local storeBtn = _G.StoreMicroButton
        if helpBtn and storeBtn then
            helpBtn:ClearAllPoints()
            helpBtn:SetAllPoints(storeBtn)
            if storeBtn:IsShown() then
                helpBtn:Hide()
            else
                helpBtn:Show()
            end
        end
        AnchorHelpTicketButton()
    end

    if container.MarkClean then
        container:MarkClean()
    end

    ActionBarsOwned.cachedLayouts[barKey] = {
        numCols = numCols,
        numRows = numRows,
        isVertical = isVertical,
        numIcons = numVisible,
        btnWidth = desiredSize,
        btnHeight = desiredHeight,
    }
end

local function GetContainerAnchorKey(barKey)
    return (barKey == "pet" and "petBar")
        or (barKey == "stance" and "stanceBar")
        or (barKey == "microbar" and "microMenu")
        or (barKey == "bags" and "bagBar")
        or barKey
end

local function ContainerMovedFromBarFrame(barKey, container)
    local barFrame = GetBarFrame(barKey)
    if not barFrame then return false end
    local okC, cp, crt, crp, cx, cy = ns.SafeCallMethod("best-effort-style", container, "GetPoint", 1)
    local okB, bp, brt, brp, bx, by = ns.SafeCallMethod("best-effort-style", barFrame, "GetPoint", 1)
    if not okC or not okB then return false end
    if Helpers.HasSecretValue(cp, crt, crp, cx, cy)
        or Helpers.HasSecretValue(bp, brt, brp, bx, by) then
        -- @secret-policy: reject-secret-value — secret anchor data cannot be compared; treat as unmoved, skip persisting
        return false
    end
    if not cp or not bp then return false end
    return cp ~= bp or crt ~= brt or crp ~= brp
        or math.abs((tonumber(cx) or 0) - (tonumber(bx) or 0)) > 0.5
        or math.abs((tonumber(cy) or 0) - (tonumber(by) or 0)) > 0.5
end

function SaveContainerPosition(barKey)
    local container = ActionBarsOwned.containers[barKey]
    if not container then return end

    local anchorKey = GetContainerAnchorKey(barKey)
    local core = GetCore()
    local profile = core and core.db and core.db.profile
    if not profile then return end

    local fa = profile.frameAnchoring
    local entry = type(fa) == "table" and rawget(fa, anchorKey) or nil
    if type(entry) ~= "table" then entry = nil end
    if entry and entry.parent and entry.parent ~= "screen" then return end

    if not entry and not ContainerMovedFromBarFrame(barKey, container) then return end

    local point, relPoint, x, y
    if core.SnapFramePosition then
        local sp, _, srp, sx, sy = core:SnapFramePosition(container)
        point, relPoint, x, y = sp, srp, sx, sy
    end
    if not point then
        local fp, _, frp, fx, fy = container:GetPoint(1)
        point, relPoint, x, y = fp, frp, fx, fy
    end
    if Helpers.HasSecretValue(point, relPoint, x, y) then return end
    if not point then return end

    if type(fa) ~= "table" then
        fa = {}
        profile.frameAnchoring = fa
    end
    if not entry then
        entry = {
            parent = "screen",
            sizeStable = true,
            autoWidth = false,
            autoHeight = false,
            hideWithParent = false,
            keepInPlace = true,
            widthAdjust = 0,
            heightAdjust = 0,
        }
        fa[anchorKey] = entry
    end
    entry.point = point
    entry.relative = relPoint or point
    entry.offsetX = tonumber(x) or 0
    entry.offsetY = tonumber(y) or 0

    if _G.QUI_ApplyFrameAnchor then
        _G.QUI_ApplyFrameAnchor(anchorKey)
    end
    if _G.QUI and _G.QUI.SendMessage then
        _G.QUI:SendMessage("QUI_FRAME_ANCHOR_CHANGED", anchorKey)
    end
end

function RestoreContainerPosition(barKey)
    local container = ActionBarsOwned.containers[barKey]
    if not container then return false end

    local anchorKey = GetContainerAnchorKey(barKey)
    if _G.QUI_HasFrameAnchor and _G.QUI_HasFrameAnchor(anchorKey) then
        return true
    end

    local barFrame = GetBarFrame(barKey)
    if barFrame then
        local ok, point, relativeTo, relPoint, x, y = pcall(barFrame.GetPoint, barFrame, 1)
        if ok and point then
            container:ClearAllPoints()
            local ox = Helpers.SafeToNumber(x, 0)
            local oy = Helpers.SafeToNumber(y, 0)
            local anchorParent = relativeTo or UIParent
            local anchorRelative = relPoint or point
            local setOk = ns.SafeCallMethod("best-effort-style", container, "SetPoint", point, anchorParent, anchorRelative, ox, oy)
            if setOk then
                return true
            end

            local rawCx, rawCy = barFrame:GetCenter()
            local rawSx, rawSy = UIParent:GetCenter()
            local cx = Helpers.SafeToNumber(rawCx)
            local cy = Helpers.SafeToNumber(rawCy)
            local sx = Helpers.SafeToNumber(rawSx)
            local sy = Helpers.SafeToNumber(rawSy)
            if cx and cx ~= 0 and cy and cy ~= 0 and sx and sy then
                container:SetPoint("CENTER", UIParent, "CENTER", cx - sx, cy - sy)
                return true
            end
        end
    end

    return false
end

fadeState = ActionBarsOwned.fadeState

function GetOwnedBarFadeState(barKey)
    if not fadeState[barKey] then
        fadeState[barKey] = {
            isFading = false,
            currentAlpha = 1,
            targetAlpha = 1,
            fadeStart = 0,
            fadeStartAlpha = 1,
            fadeDuration = 0.3,
            isMouseOver = false,
            delayTimer = nil,
            leaveCheckTimer = nil,
        }
    end
    return fadeState[barKey]
end

IsInEditMode = Helpers.IsEditModeShown

local function GlobalVisibilityHidingBars()
    local fn = ns.ShouldHideActionBarsForVisibility
    return type(fn) == "function" and fn() == true
end

function SetOwnedBarAlpha(barKey, alpha)
    local container = ActionBarsOwned.containers[barKey]
    if not container then return end

    local buttons = ActionBarsOwned.nativeButtons[barKey]

    container:SetAlpha(alpha)

    if buttons then
        for _, btn in ipairs(buttons) do
            local state = GetFrameState(btn)
            local hidden = alpha <= 0 or state.hiddenEmpty
            if hidden then
                if not state.fadeHidden then
                    FadeHideTextures(state, btn)
                end
            else
                if state.fadeHidden then
                    FadeShowTextures(state, btn)
                    btn:SetAlpha(1)
                end
                if alpha < 1 then
                    if state.gloss and state.gloss:IsShown() then
                        state.gloss:Hide(); state._fadeGloss = true
                    end
                    if state.tintOverlay and state.tintOverlay:IsShown() then
                        state.tintOverlay:Hide(); state._fadeTint = true
                    end
                else
                    if state._fadeGloss and state.gloss then
                        state.gloss:Show(); state._fadeGloss = nil
                    end
                    if state._fadeTint and state.tintOverlay then
                        state.tintOverlay:Show(); state._fadeTint = nil
                    end
                end
            end
        end
    end

    GetOwnedBarFadeState(barKey).currentAlpha = alpha
end

ActionBarsOwned.SetBarAlpha = SetOwnedBarAlpha

fadeFrame = nil
fadeFrameUpdate = nil

function StartOwnedBarFade(barKey, targetAlpha)
    if targetAlpha < 1 and IsInEditMode() then return end
    if targetAlpha < 1 and ShouldSuspendMouseoverFade(barKey) then return end

    local state = GetOwnedBarFadeState(barKey)
    local fadeSettings = GetFadeSettings()

    local duration = targetAlpha > state.currentAlpha
        and (fadeSettings and fadeSettings.fadeInDuration or 0.2)
        or (fadeSettings and fadeSettings.fadeOutDuration or 0.3)

    if math.abs(state.currentAlpha - targetAlpha) < 0.01 then
        state.isFading = false
        return
    end

    state.isFading = true
    state.targetAlpha = targetAlpha
    state.fadeStart = GetTime()
    state.fadeStartAlpha = state.currentAlpha
    state.fadeDuration = duration

    if not fadeFrame then
        fadeFrame = CreateFrame("Frame")
        fadeFrameUpdate = function(self, elapsed)
            local now = GetTime()
            local anyFading = false

            for bKey, bState in pairs(fadeState) do
                if bState.isFading then
                    anyFading = true
                    local elapsedTime = now - bState.fadeStart
                    local progress = math.min(elapsedTime / bState.fadeDuration, 1)
                    local easedProgress = progress * (2 - progress)
                    local a = bState.fadeStartAlpha + (bState.targetAlpha - bState.fadeStartAlpha) * easedProgress
                    local applyAlpha = ActionBarsOwned.containers[bKey] and SetOwnedBarAlpha or SetBarAlpha
                    applyAlpha(bKey, a)

                    if progress >= 1 then
                        bState.isFading = false
                        applyAlpha(bKey, bState.targetAlpha)
                    end
                end
            end

            if not anyFading then
                self:SetScript("OnUpdate", nil)
                self:Hide()
            end
        end
    end
    fadeFrame:SetScript("OnUpdate", fadeFrameUpdate)
    fadeFrame:Show()
end

CancelOwnedBarFadeTimers = CancelBarFadeTimers

function IsLinkedBar(barKey)
    for _, key in ipairs(LINKED_OWNED_BAR_KEYS) do
        if key == barKey then return true end
    end
    return false
end

function IsMouseOverOwnedBar(barKey)
    local container = ActionBarsOwned.containers[barKey]
    if container and container:IsMouseOver() then return true end

    local buttons = ActionBarsOwned.nativeButtons[barKey]
    if buttons then
        for _, btn in ipairs(buttons) do
            if btn:IsMouseOver() then return true end
        end
    end
    return false
end

function IsMouseOverAnyLinkedOwnedBar()
    for _, barKey in ipairs(LINKED_OWNED_BAR_KEYS) do
        if IsMouseOverOwnedBar(barKey) then return true end
    end
    return false
end

function HookOwnedFrameForMouseover(frame, barKey)
    if not frame then return end
    local state = GetFrameState(frame)
    if state.ownedMouseoverHooked then return end
    state.ownedMouseoverHooked = true

    frame:HookScript("OnEnter", function()
        ActionBarsOwned:OnBarMouseEnter(barKey)
    end)

    frame:HookScript("OnLeave", function()
        ActionBarsOwned:OnBarMouseLeave(barKey)
    end)
end

function ActionBarsOwned:OnBarMouseEnter(barKey)
    if GlobalVisibilityHidingBars() then return end

    local state = GetOwnedBarFadeState(barKey)
    local fadeSettings = GetFadeSettings()
    local barSettings = GetBarSettings(barKey)

    if ShouldSuppressMouseoverHideForLevel() then
        SetOwnedBarAlpha(barKey, 1)
        return
    end
    if ShouldForceShowForSpellBook() then
        SetOwnedBarAlpha(barKey, 1)
        return
    end
    if ShouldForceShowForActionBarContext(barKey) then
        SetOwnedBarAlpha(barKey, 1)
        return
    end

    if barSettings and barSettings.alwaysShow then return end

    local fadeEnabled = barSettings and barSettings.fadeEnabled
    if fadeEnabled == nil then
        fadeEnabled = fadeSettings and fadeSettings.enabled
    end
    if not fadeEnabled then return end

    state.isMouseOver = true

    if fadeSettings and fadeSettings.linkBars1to8 and IsLinkedBar(barKey) then
        for _, linkedKey in ipairs(LINKED_OWNED_BAR_KEYS) do
            if linkedKey ~= barKey then
                local linkedState = GetOwnedBarFadeState(linkedKey)
                CancelOwnedBarFadeTimers(linkedState)
                StartOwnedBarFade(linkedKey, 1)
            end
        end
    end

    CancelOwnedBarFadeTimers(state)
    StartOwnedBarFade(barKey, 1)
end

function ActionBarsOwned:OnBarMouseLeave(barKey)
    if IsInEditMode() then return end

    if GlobalVisibilityHidingBars() then return end

    local state = GetOwnedBarFadeState(barKey)
    local fadeSettings = GetFadeSettings()
    local barSettings = GetBarSettings(barKey)

    if ShouldSuppressMouseoverHideForLevel() then
        SetOwnedBarAlpha(barKey, 1)
        return
    end
    if ShouldForceShowForSpellBook() then
        SetOwnedBarAlpha(barKey, 1)
        return
    end
    if ShouldForceShowForActionBarContext(barKey) then
        SetOwnedBarAlpha(barKey, 1)
        return
    end

    if barSettings and barSettings.alwaysShow then return end

    local heldInCombat = (barKey and barKey:match("^bar%d$"))
        or (fadeSettings and fadeSettings.linkBars1to8 and IsLinkedBar(barKey))
    if heldInCombat and InCombatLockdown() and fadeSettings and fadeSettings.alwaysShowInCombat then
        return
    end

    local fadeEnabled = barSettings and barSettings.fadeEnabled
    if fadeEnabled == nil then
        fadeEnabled = fadeSettings and fadeSettings.enabled
    end
    if not fadeEnabled then return end

    if state.leaveCheckTimer then
        state.leaveCheckTimer:Cancel()
    end

    state.leaveCheckTimer = C_Timer.NewTimer(0.066, function()
        state.leaveCheckTimer = nil

        if IsMouseOverOwnedBar(barKey) then return end

        if fadeSettings and fadeSettings.linkBars1to8 and IsLinkedBar(barKey) then
            if IsMouseOverAnyLinkedOwnedBar() then return end
            for _, linkedKey in ipairs(LINKED_OWNED_BAR_KEYS) do
                local linkedBarSettings = GetBarSettings(linkedKey)
                local linkedFadeEnabled = linkedBarSettings and linkedBarSettings.fadeEnabled
                if linkedFadeEnabled == nil then
                    linkedFadeEnabled = fadeSettings and fadeSettings.enabled
                end
                if linkedFadeEnabled and not (linkedBarSettings and linkedBarSettings.alwaysShow) then
                    local linkedState = GetOwnedBarFadeState(linkedKey)
                    linkedState.isMouseOver = false
                    local linkedFadeOutAlpha = linkedBarSettings and linkedBarSettings.fadeOutAlpha
                    if linkedFadeOutAlpha == nil then
                        linkedFadeOutAlpha = fadeSettings and fadeSettings.fadeOutAlpha or 0
                    end
                    local delay = fadeSettings and fadeSettings.fadeOutDelay or 0.5
                    CancelOwnedBarFadeTimers(linkedState)
                    local function TryLinkedOwnedFade()
                        if ShouldForceShowForSpellBook() or ShouldForceShowForActionBarContext(linkedKey) then
                            SetOwnedBarAlpha(linkedKey, 1)
                            linkedState.delayTimer = nil
                            return
                        end
                        if IsSpellFlyoutActiveForBar(linkedKey) then
                            SetOwnedBarAlpha(linkedKey, 1)
                            linkedState.delayTimer = C_Timer.NewTimer(SPELL_UI_FADE_RECHECK_DELAY, TryLinkedOwnedFade)
                            return
                        end
                        linkedState.delayTimer = nil
                        if not IsMouseOverAnyLinkedOwnedBar() then
                            StartOwnedBarFade(linkedKey, linkedFadeOutAlpha)
                        end
                    end
                    linkedState.delayTimer = C_Timer.NewTimer(delay, TryLinkedOwnedFade)
                end
            end
            return
        end

        state.isMouseOver = false

        local fadeOutAlpha = barSettings and barSettings.fadeOutAlpha
        if fadeOutAlpha == nil then
            fadeOutAlpha = fadeSettings and fadeSettings.fadeOutAlpha or 0
        end
        local delay = fadeSettings and fadeSettings.fadeOutDelay or 0.5

        if state.delayTimer then
            state.delayTimer:Cancel()
        end
        local function TryOwnedFadeOut()
            if state.isMouseOver then
                state.delayTimer = nil
                return
            end
            if ShouldForceShowForSpellBook() or ShouldForceShowForActionBarContext(barKey) then
                SetOwnedBarAlpha(barKey, 1)
                state.delayTimer = nil
                return
            end
            if IsSpellFlyoutActiveForBar(barKey) then
                SetOwnedBarAlpha(barKey, 1)
                state.delayTimer = C_Timer.NewTimer(SPELL_UI_FADE_RECHECK_DELAY, TryOwnedFadeOut)
                return
            end
            local freshBarSettings = GetBarSettings(barKey)
            local freshFadeSettings = GetFadeSettings()
            local freshFadeOutAlpha = freshBarSettings and freshBarSettings.fadeOutAlpha
            if freshFadeOutAlpha == nil then
                freshFadeOutAlpha = freshFadeSettings and freshFadeSettings.fadeOutAlpha or 0
            end
            StartOwnedBarFade(barKey, freshFadeOutAlpha)
            state.delayTimer = nil
        end
        state.delayTimer = C_Timer.NewTimer(delay, TryOwnedFadeOut)
    end)
end

function SetupOwnedBarMouseover(barKey)
    if IsInEditMode() then
        SetOwnedBarAlpha(barKey, 1)
        return
    end

    if GlobalVisibilityHidingBars() then return end

    local barSettings = GetBarSettings(barKey)
    local fadeSettings = GetFadeSettings()

    if ShouldSuppressMouseoverHideForLevel() then
        SetOwnedBarAlpha(barKey, 1)
        return
    end
    if ShouldForceShowForSpellBook() then
        SetOwnedBarAlpha(barKey, 1)
        return
    end
    if ShouldForceShowForActionBarContext(barKey) then
        SetOwnedBarAlpha(barKey, 1)
        return
    end

    if barSettings and barSettings.alwaysShow then
        SetOwnedBarAlpha(barKey, 1)
        return
    end

    local fadeEnabled = barSettings and barSettings.fadeEnabled
    if fadeEnabled == nil then
        fadeEnabled = fadeSettings and fadeSettings.enabled
    end
    if not fadeEnabled then
        SetOwnedBarAlpha(barKey, 1)
        return
    end

    local heldInCombat = (barKey and barKey:match("^bar%d$"))
        or (fadeSettings and fadeSettings.linkBars1to8 and IsLinkedBar(barKey))
    if heldInCombat and InCombatLockdown() and fadeSettings and fadeSettings.alwaysShowInCombat then
        SetOwnedBarAlpha(barKey, 1)
        return
    end

    local fadeOutAlpha = barSettings and barSettings.fadeOutAlpha
    if fadeOutAlpha == nil then
        fadeOutAlpha = fadeSettings and fadeSettings.fadeOutAlpha or 0
    end

    local container = ActionBarsOwned.containers[barKey]
    if container then
        HookOwnedFrameForMouseover(container, barKey)
    end
    local buttons = ActionBarsOwned.nativeButtons[barKey]
    if buttons then
        for _, btn in ipairs(buttons) do
            HookOwnedFrameForMouseover(btn, barKey)
        end
    end

    local state = GetOwnedBarFadeState(barKey)
    state.isFading = false
    CancelOwnedBarFadeTimers(state)

    local isMouseOver = IsMouseOverOwnedBar(barKey)
    if fadeSettings and fadeSettings.linkBars1to8 and IsLinkedBar(barKey) then
        isMouseOver = IsMouseOverAnyLinkedOwnedBar()
    end

    state.isMouseOver = isMouseOver
    SetOwnedBarAlpha(barKey, isMouseOver and 1 or fadeOutAlpha)
end
