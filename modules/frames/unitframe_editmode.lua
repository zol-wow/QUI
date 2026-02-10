---------------------------------------------------------------------------
-- QUI Unit Frames - Edit Mode
-- Draggable frames, nudge buttons, slider sync, Blizzard Edit Mode hook.
-- Extracted from modules/frames/unitframes.lua for maintainability.
---------------------------------------------------------------------------
local ADDON_NAME, ns = ...
local QUICore = ns.Addon

-- QUI_UF is created in unitframes.lua and exported to ns.QUI_UnitFrames.
-- This file loads after unitframes.lua, so the reference is available.
local QUI_UF = ns.QUI_UnitFrames
if not QUI_UF then return end

-- Internal helpers exposed by unitframes.lua
local GetUnitSettings = QUI_UF._GetUnitSettings
local UpdateFrame = QUI_UF._UpdateFrame
local GetCore = ns.Helpers.GetCore

---------------------------------------------------------------------------
-- EDIT MODE: Toggle draggable frames with arrow nudge buttons
---------------------------------------------------------------------------
QUI_UF.editModeActive = false

-- Edit Mode: Slider registry for real-time sync during drag
-- Format: { unitKey = { x = sliderRef, y = sliderRef, coordText = fontStringRef } }
QUI_UF.editModeSliders = {}

-- Register slider references for real-time sync during edit mode
function QUI_UF:RegisterEditModeSliders(unitKey, xSlider, ySlider)
    self.editModeSliders[unitKey] = self.editModeSliders[unitKey] or {}
    self.editModeSliders[unitKey].x = xSlider
    self.editModeSliders[unitKey].y = ySlider
end

-- Update sliders and coordinate display when position changes
function QUI_UF:NotifyPositionChanged(unitKey, offsetX, offsetY)
    -- Update options panel sliders if registered
    local sliders = self.editModeSliders[unitKey]
    if sliders then
        if sliders.x and sliders.x.SetValue then
            sliders.x.SetValue(offsetX, true)  -- true = skip onChange callback
        end
        if sliders.y and sliders.y.SetValue then
            sliders.y.SetValue(offsetY, true)
        end
    end

    -- Update info text on overlay if visible
    local frame = self.frames[unitKey]
    if frame and frame.editOverlay and frame.editOverlay.infoText then
        local label = frame.editOverlay.unitLabel or unitKey
        frame.editOverlay.infoText:SetText(string.format("%s  X:%d Y:%d", label, offsetX, offsetY))
    end
end

-- Helper: Create nudge button with chevron arrows (dropdown style)
local function CreateNudgeButton(parent, direction, deltaX, deltaY, unitKey)
    local btn = CreateFrame("Button", nil, parent)
    btn:SetSize(18, 18)
    -- Use TOOLTIP strata so nudge buttons appear above all other frames
    btn:SetFrameStrata("TOOLTIP")
    btn:SetFrameLevel(100)

    -- Background - dark grey at 70% for visibility over any game content
    local bg = btn:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetTexture("Interface\\Buttons\\WHITE8x8")
    bg:SetVertexColor(0.1, 0.1, 0.1, 0.7)
    btn.bg = bg

    -- Chevron lines - white for high contrast
    local line1 = btn:CreateTexture(nil, "ARTWORK")
    line1:SetColorTexture(1, 1, 1, 0.9)
    line1:SetSize(7, 2)

    local line2 = btn:CreateTexture(nil, "ARTWORK")
    line2:SetColorTexture(1, 1, 1, 0.9)
    line2:SetSize(7, 2)

    -- Direction-specific angles and positions
    if direction == "DOWN" then
        line1:SetPoint("CENTER", btn, "CENTER", -2, 1)
        line1:SetRotation(math.rad(-45))
        line2:SetPoint("CENTER", btn, "CENTER", 2, 1)
        line2:SetRotation(math.rad(45))
    elseif direction == "UP" then
        line1:SetPoint("CENTER", btn, "CENTER", -2, -1)
        line1:SetRotation(math.rad(45))
        line2:SetPoint("CENTER", btn, "CENTER", 2, -1)
        line2:SetRotation(math.rad(-45))
    elseif direction == "LEFT" then
        line1:SetPoint("CENTER", btn, "CENTER", -1, -2)
        line1:SetRotation(math.rad(-45))
        line2:SetPoint("CENTER", btn, "CENTER", -1, 2)
        line2:SetRotation(math.rad(45))
    elseif direction == "RIGHT" then
        line1:SetPoint("CENTER", btn, "CENTER", 1, -2)
        line1:SetRotation(math.rad(45))
        line2:SetPoint("CENTER", btn, "CENTER", 1, 2)
        line2:SetRotation(math.rad(-45))
    end
    btn.line1 = line1
    btn.line2 = line2

    -- Hover effect - mint accent on hover
    btn:SetScript("OnEnter", function(self)
        self.line1:SetColorTexture(0.204, 0.827, 0.6, 1)
        self.line2:SetColorTexture(0.204, 0.827, 0.6, 1)
    end)
    btn:SetScript("OnLeave", function(self)
        self.line1:SetColorTexture(1, 1, 1, 0.9)
        self.line2:SetColorTexture(1, 1, 1, 0.9)
    end)

    btn:SetScript("OnClick", function()
        local frame = parent:GetParent()
        local settingsKey = frame.unitKey
        if settingsKey and settingsKey:match("^boss%d+$") then
            settingsKey = "boss"
        end
        local settings = GetUnitSettings(settingsKey)

        -- Block nudging for anchored frames
        local isAnchored = settings and settings.anchorTo and settings.anchorTo ~= "disabled"
        if isAnchored and (settingsKey == "player" or settingsKey == "target") then
            return
        end

        if settings then
            local shift = IsShiftKeyDown()
            local step = shift and 10 or 1
            settings.offsetX = (settings.offsetX or 0) + (deltaX * step)
            settings.offsetY = (settings.offsetY or 0) + (deltaY * step)
            frame:ClearAllPoints()
            frame:SetPoint("CENTER", UIParent, "CENTER", settings.offsetX, settings.offsetY)

            -- Notify options panel of position change
            QUI_UF:NotifyPositionChanged(settingsKey, settings.offsetX, settings.offsetY)
        end
    end)

    return btn
end

function QUI_UF:EnableEditMode()
    if InCombatLockdown() then
        print("|cFF56D1FFQUI|r: Cannot enter Edit Mode during combat.")
        return
    end

    self.editModeActive = true

    -- Hide Blizzard's selection frames (prevents visual conflicts in Edit Mode)
    self:HideBlizzardSelectionFrames()

    -- Unregister state drivers so frames stay visible
    for unitKey, frame in pairs(self.frames) do
        UnregisterStateDriver(frame, "visibility")
    end

    -- Create central Save and Exit button if not exists
    if not self.exitEditModeBtn then
        local exitBtn = CreateFrame("Button", "QUI_ExitEditModeBtn", UIParent, "BackdropTemplate")
        exitBtn:SetSize(180, 40)
        exitBtn:SetPoint("TOP", UIParent, "TOP", 0, -100)
        exitBtn:SetFrameStrata("TOOLTIP")
        local exitBtnPx = QUICore:GetPixelSize(exitBtn)
        exitBtn:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Buttons\\WHITE8x8",
            edgeSize = exitBtnPx * 2,
        })
        exitBtn:SetBackdropColor(0.1, 0.1, 0.1, 0.95)
        exitBtn:SetBackdropBorderColor(0.34, 0.82, 1, 1)  -- Blue accent

        local exitText = exitBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        exitText:SetPoint("CENTER")
        exitText:SetText("SAVE AND EXIT")
        exitText:SetTextColor(0.34, 0.82, 1, 1)
        exitBtn.text = exitText

        -- Hint text below button
        local hintText = exitBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        hintText:SetPoint("TOP", exitBtn, "BOTTOM", 0, -5)
        hintText:SetText("Drag frames or click arrow buttons to nudge (Shift=1px)")
        hintText:SetTextColor(0.7, 0.7, 0.7, 1)
        exitBtn.hint = hintText

        exitBtn:SetScript("OnEnter", function(self)
            self:SetBackdropBorderColor(1, 1, 0, 1)
            self.text:SetTextColor(1, 1, 0, 1)
        end)
        exitBtn:SetScript("OnLeave", function(self)
            self:SetBackdropBorderColor(0.34, 0.82, 1, 1)
            self.text:SetTextColor(0.34, 0.82, 1, 1)
        end)
        exitBtn:SetScript("OnClick", function()
            if EditModeManagerFrame and EditModeManagerFrame:IsShown() then
                -- Close any open system settings panel before exit. Having a panel
                -- open (e.g. "Tracked Bars") taints the execution context so that
                -- Blizzard's OnEditModeExit → ResetPartyFrames → party frame updates
                -- hit secret values (maxHealth/checkedRange) and error, aborting exit.
                if EditModeManagerFrame.ClearSelectedSystem then
                    pcall(EditModeManagerFrame.ClearSelectedSystem, EditModeManagerFrame)
                end
                -- Save changes
                if EditModeManagerFrame.SaveLayoutChanges then
                    pcall(EditModeManagerFrame.SaveLayoutChanges, EditModeManagerFrame)
                end
                -- Then exit
                pcall(HideUIPanel, EditModeManagerFrame)
            end
            -- Always clean up QUI edit mode regardless of Blizzard exit success.
            -- In the success case, the ExitEditMode hook already called DisableEditMode
            -- (which sets editModeActive=false), so this is a no-op.
            -- In the failure case, this is the only cleanup path.
            if QUI_UF.editModeActive then
                QUI_UF.triggeredByBlizzEditMode = false
                pcall(QUI_UF.DisableEditMode, QUI_UF)
            end
        end)

        self.exitEditModeBtn = exitBtn
    end
    self.exitEditModeBtn:Show()

    for unitKey, frame in pairs(self.frames) do
        -- Create highlight overlay if not exists
        if not frame.editOverlay then
            local overlay = CreateFrame("Frame", nil, frame, "BackdropTemplate")
            overlay:SetAllPoints()
            overlay:SetFrameLevel(frame:GetFrameLevel() + 10)
            local overlayPx = QUICore:GetPixelSize(overlay)
            overlay:SetBackdrop({
                bgFile = "Interface\\Buttons\\WHITE8x8",
                edgeFile = "Interface\\Buttons\\WHITE8x8",
                edgeSize = overlayPx * 2,
            })
            overlay:SetBackdropColor(0.2, 0.8, 1, 0.3)
            overlay:SetBackdropBorderColor(0.2, 0.8, 1, 1)

            -- Nudge buttons (arrow buttons around the frame)
            local nudgeLeft = CreateNudgeButton(overlay, "LEFT", -1, 0, unitKey)
            nudgeLeft:SetPoint("RIGHT", overlay, "LEFT", -4, 0)
            overlay.nudgeLeft = nudgeLeft

            local nudgeRight = CreateNudgeButton(overlay, "RIGHT", 1, 0, unitKey)
            nudgeRight:SetPoint("LEFT", overlay, "RIGHT", 4, 0)
            overlay.nudgeRight = nudgeRight

            local nudgeUp = CreateNudgeButton(overlay, "UP", 0, 1, unitKey)
            nudgeUp:SetPoint("BOTTOM", overlay, "TOP", 0, 4)
            overlay.nudgeUp = nudgeUp

            -- Info line above UP arrow (consolidated: name + coords)
            local infoText = overlay:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            infoText:SetPoint("BOTTOM", nudgeUp, "TOP", 0, 2)  -- 2px above the up arrow
            infoText:SetTextColor(0.7, 0.7, 0.7, 1)  -- Subtle grey
            overlay.infoText = infoText
            overlay.unitLabel = unitKey:gsub("^%l", string.upper):gsub("(%l)(%u)", "%1 %2")

            local nudgeDown = CreateNudgeButton(overlay, "DOWN", 0, -1, unitKey)
            nudgeDown:SetPoint("TOP", overlay, "BOTTOM", 0, -4)
            overlay.nudgeDown = nudgeDown

            -- Store unitKey for selection manager
            overlay.elementKey = unitKey

            -- Hide nudge buttons initially (will show on click/selection)
            nudgeLeft:Hide()
            nudgeRight:Hide()
            nudgeUp:Hide()
            nudgeDown:Hide()
            infoText:Hide()

            -- Allow clicks to pass through overlay to frame for dragging
            overlay:EnableMouse(false)

            frame.editOverlay = overlay
        end

        -- Update info text with current position
        local settingsKey = unitKey
        if unitKey:match("^boss%d+$") then
            settingsKey = "boss"
        end
        local settings = GetUnitSettings(settingsKey)
        if settings and frame.editOverlay.infoText then
            local label = frame.editOverlay.unitLabel or unitKey
            local isAnchored = settings.anchorTo and settings.anchorTo ~= "disabled"
            if isAnchored and (settingsKey == "player" or settingsKey == "target") then
                local anchorNames = {essential = "Essential", utility = "Utility", primary = "Primary", secondary = "Secondary"}
                local anchorName = anchorNames[settings.anchorTo] or settings.anchorTo
                frame.editOverlay.infoText:SetText(label .. "  (Locked to " .. anchorName .. ")")
            else
                local x = settings.offsetX or 0
                local y = settings.offsetY or 0
                frame.editOverlay.infoText:SetText(string.format("%s  X:%d Y:%d", label, x, y))
            end
        end

        frame.editOverlay:Show()

        -- Enable dragging
        frame:SetMovable(true)
        frame:EnableMouse(true)
        frame:RegisterForDrag("LeftButton")

        -- Store unitKey on frame for click handler
        frame._editModeUnitKey = unitKey

        -- Click handler to select this element and show its arrows
        frame:SetScript("OnMouseDown", function(self, button)
            if button == "LeftButton" and QUI_UF.editModeActive then
                local core = GetCore()
                if core and core.SelectEditModeElement then
                    core:SelectEditModeElement("unitframe", self._editModeUnitKey)
                end
            end
        end)

        frame:SetScript("OnDragStart", function(self)
            if QUI_UF.editModeActive then
                -- Block dragging for anchored frames
                local settingsKey = self.unitKey
                if self.unitKey:match("^boss%d+$") then settingsKey = "boss" end
                local settings = GetUnitSettings(settingsKey)
                local isAnchored = settings and settings.anchorTo and settings.anchorTo ~= "disabled"
                if isAnchored and (settingsKey == "player" or settingsKey == "target") then
                    return -- Locked to anchor, cannot drag
                end

                self:StartMoving()
                self._isMoving = true

                -- Update position in real-time during drag
                self:SetScript("OnUpdate", function(self)
                    if not self._isMoving then
                        self:SetScript("OnUpdate", nil)
                        return
                    end

                    -- Calculate offset from UIParent center
                    local selfX, selfY = self:GetCenter()
                    local parentX, parentY = UIParent:GetCenter()
                    if selfX and selfY and parentX and parentY then
                        local rawX, rawY = selfX - parentX, selfY - parentY
                        local offsetX = QUICore and QUICore.PixelRound and QUICore:PixelRound(rawX) or Round(rawX)
                        local offsetY = QUICore and QUICore.PixelRound and QUICore:PixelRound(rawY) or Round(rawY)

                        -- Update database in real-time
                        local settingsKey = self.unitKey
                        if self.unitKey:match("^boss%d+$") then
                            settingsKey = "boss"
                        end
                        local settings = GetUnitSettings(settingsKey)
                        if settings then
                            settings.offsetX = offsetX
                            settings.offsetY = offsetY

                            -- Notify options panel of position change (real-time sync)
                            QUI_UF:NotifyPositionChanged(settingsKey, offsetX, offsetY)
                        end
                    end
                end)
            end
        end)

        frame:SetScript("OnDragStop", function(self)
            self:StopMovingOrSizing()
            self._isMoving = false
            self:SetScript("OnUpdate", nil)

            -- Final position save
            local selfX, selfY = self:GetCenter()
            local parentX, parentY = UIParent:GetCenter()
            if selfX and selfY and parentX and parentY then
                local rawX, rawY = selfX - parentX, selfY - parentY
                local offsetX = QUICore and QUICore.PixelRound and QUICore:PixelRound(rawX) or Round(rawX)
                local offsetY = QUICore and QUICore.PixelRound and QUICore:PixelRound(rawY) or Round(rawY)

                -- Boss frames: all boss frames save to "boss" settings
                local settingsKey = self.unitKey
                if self.unitKey:match("^boss%d+$") then
                    settingsKey = "boss"
                end
                local settings = GetUnitSettings(settingsKey)
                if settings then
                    settings.offsetX = offsetX
                    settings.offsetY = offsetY

                    -- Final notification to options panel
                    QUI_UF:NotifyPositionChanged(settingsKey, settings.offsetX, settings.offsetY)
                end
            end
        end)

        -- Enable keyboard for arrow key nudging (skip boss frames - SecureUnitButtonTemplate rejects this call)
        local isBossFrame = frame.unit and frame.unit:match("^boss%d$")
        if not isBossFrame then
            frame:EnableKeyboard(true)
        end
        frame:SetScript("OnKeyDown", function(self, key)
            if not QUI_UF.editModeActive then return end

            local deltaX, deltaY = 0, 0
            if key == "LEFT" then deltaX = -1
            elseif key == "RIGHT" then deltaX = 1
            elseif key == "UP" then deltaY = 1
            elseif key == "DOWN" then deltaY = -1
            else return end  -- Ignore other keys

            -- Use global selection system - nudge the SELECTED element, not this frame
            local core = GetCore()
            if core and core.EditModeSelection and core.EditModeSelection.selectedType then
                -- Delegate to the global nudge function which handles all element types
                -- Pass raw delta (1 or -1) - NudgeSelectedElement handles shift multiplier
                core:NudgeSelectedElement(deltaX, deltaY)
                return
            end

            -- Fallback: no selection, nudge this frame (legacy behavior)
            local settingsKey = self.unitKey
            if settingsKey and settingsKey:match("^boss%d+$") then
                settingsKey = "boss"
            end
            local settings = GetUnitSettings(settingsKey)

            -- Block nudging for anchored frames
            local isAnchored = settings and settings.anchorTo and settings.anchorTo ~= "disabled"
            if isAnchored and (settingsKey == "player" or settingsKey == "target") then
                return
            end

            local shift = IsShiftKeyDown()
            local step = shift and 10 or 1

            if settings then
                settings.offsetX = (settings.offsetX or 0) + (deltaX * step)
                settings.offsetY = (settings.offsetY or 0) + (deltaY * step)
                self:ClearAllPoints()
                self:SetPoint("CENTER", UIParent, "CENTER", settings.offsetX, settings.offsetY)

                -- Notify options panel of position change
                QUI_UF:NotifyPositionChanged(settingsKey, settings.offsetX, settings.offsetY)
            end
        end)

        -- Show frame even if unit doesn't exist (for positioning)
        frame:Show()

        -- Show preview data so frames are visible
        self:ShowPreview(unitKey)
    end

    print("|cFF56D1FFQUI|r: Edit Mode |cff00ff00ENABLED|r - Drag frames to reposition.")
end

function QUI_UF:DisableEditMode()
    self.editModeActive = false

    -- Clear Edit Mode selection (hides arrows on selected element)
    local core = GetCore()
    if core and core.ClearEditModeSelection then
        core:ClearEditModeSelection()
    end

    -- Hide the exit button
    if self.exitEditModeBtn then
        self.exitEditModeBtn:Hide()
    end

    for unitKey, frame in pairs(self.frames) do
        -- Hide overlay
        if frame.editOverlay then
            frame.editOverlay:Hide()
        end

        -- Disable dragging and click handlers
        frame:RegisterForDrag()
        -- Skip EnableKeyboard for boss frames (SecureUnitButtonTemplate rejects this call)
        local isBossFrame = frame.unit and frame.unit:match("^boss%d$")
        if not isBossFrame then
            frame:EnableKeyboard(false)
        end
        frame:SetScript("OnMouseDown", nil)
        frame:SetScript("OnDragStart", nil)
        frame:SetScript("OnDragStop", nil)
        frame:SetScript("OnKeyDown", nil)

        -- Hide preview mode that was enabled for edit mode
        self.previewMode[unitKey] = false

        -- Re-register state drivers for non-player units
        if not InCombatLockdown() then
            local unit = frame.unit
            if unit == "target" then
                RegisterStateDriver(frame, "visibility", "[@target,exists] show; hide")
            elseif unit == "focus" then
                RegisterStateDriver(frame, "visibility", "[@focus,exists] show; hide")
            elseif unit == "pet" then
                RegisterStateDriver(frame, "visibility", "[@pet,exists] show; hide")
            elseif unit == "targettarget" then
                RegisterStateDriver(frame, "visibility", "[@targettarget,exists] show; hide")
            elseif unit and unit:match("^boss%d$") then
                local bossNum = unit:match("^boss(%d)$")
                if bossNum then
                    RegisterStateDriver(frame, "visibility", "[@boss" .. bossNum .. ",exists] show; hide")
                end
            end
        end

        -- Update frame with real data if unit exists
        -- pcall: UnitHealth/UnitPower can return secret values that error in comparisons
        if UnitExists(frame.unit) or unitKey == "player" then
            pcall(UpdateFrame, frame)
        end
    end

    print("|cFF56D1FFQUI|r: Edit Mode |cffff0000DISABLED|r - Positions saved.")
end

function QUI_UF:ToggleEditMode()
    if self.editModeActive then
        self:DisableEditMode()
    else
        self:EnableEditMode()
    end
end

-- Restore edit overlay for a specific unit frame (called after RefreshFrame during Edit Mode)
function QUI_UF:RestoreEditOverlayIfNeeded(unitKey)
    if not self.editModeActive then return end
    if InCombatLockdown() then return end

    local frame = self.frames[unitKey]
    if not frame then return end

    -- Check if overlay exists and is still valid (parent might have changed)
    if frame.editOverlay and frame.editOverlay:GetParent() == frame then
        -- Overlay is still valid, just ensure it's shown
        frame.editOverlay:Show()
        return
    end

    -- Need to recreate overlay - delegate to EnableEditMode logic for this frame
    -- This is a simplified version that just shows the overlay
    C_Timer.After(0.05, function()
        if not self.editModeActive then return end
        local f = self.frames[unitKey]
        if f and f.editOverlay then
            f.editOverlay:Show()
        end
    end)
end

---------------------------------------------------------------------------
-- BLIZZARD EDIT MODE INTEGRATION
---------------------------------------------------------------------------
-- Hook Blizzard's Edit Mode to trigger QUI's edit mode when user enters via Esc > Edit Mode
function QUI_UF:HookBlizzardEditMode()
    if not EditModeManagerFrame then return end
    if self._blizzEditModeHooked then return end
    self._blizzEditModeHooked = true

    -- NOTE: Do NOT wrap AccountSettings:OnEditModeExit or any Blizzard exit
    -- functions in addon pcall — this taints the execution context and causes
    -- ADDON_ACTION_FORBIDDEN for protected functions like ClearTarget().
    -- The secret value error in ResetPartyFrames is a Blizzard bug; we handle
    -- it via the safety net in the OnClick handler (always calls DisableEditMode).

    -- Track if we triggered from Blizzard Edit Mode (vs /qui editmode)
    self.triggeredByBlizzEditMode = false

    hooksecurefunc(EditModeManagerFrame, "EnterEditMode", function()
        if InCombatLockdown() then return end
        if self.editModeActive then return end  -- Already active via /qui editmode
        self.triggeredByBlizzEditMode = true
        self:EnableEditMode()
    end)

    hooksecurefunc(EditModeManagerFrame, "ExitEditMode", function()
        if InCombatLockdown() then return end
        if not self.editModeActive then return end
        if not self.triggeredByBlizzEditMode then return end  -- Don't exit if user used /qui editmode
        self.triggeredByBlizzEditMode = false
        self:DisableEditMode()
    end)
end
