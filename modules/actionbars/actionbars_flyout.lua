local ADDON_NAME, ns = ...
local env = ns.ActionBarsEnv
env.ADDON_NAME = ADDON_NAME
env.ns = ns
env.SetChunkEnv(1, env)

do -- spell flyout skinning

spellFlyoutSkinHooked = false

do -- owned spell flyout (retail migration)

USE_OWNED_FLYOUT = (WOW_PROJECT_ID == WOW_PROJECT_MAINLINE)
ActionBarsOwned.useOwnedFlyout = USE_OWNED_FLYOUT

env.__declared.ownedFlyout = true
ownedFlyoutButtons = {}
env.__declared.lastOwnedFlyoutSyncPayload = true

function GetOwnedFlyoutSettings(parentButton)
    local barKey = GetBarKeyFromButton(parentButton)
    if barKey then
        local settings = GetEffectiveSettings(barKey)
        if settings then return settings end
    end
    return GetGlobalSettings()
end

function ApplyOwnedFlyoutButtonVisuals(button, spellID)
    if not button then return end
    button._quiFlyoutSpellID = spellID
    if button.icon then
        local texture
        if spellID then
            if C_Spell and C_Spell.GetSpellTexture then
                local ok, result = pcall(C_Spell.GetSpellTexture, spellID)
                if ok then texture = result end
            elseif GetSpellTexture then
                local ok, result = pcall(GetSpellTexture, spellID)
                if ok then texture = result end
            end
        end
        button.icon:SetTexture(texture)
        if spellID then
            button.icon:Show()
        else
            button.icon:Hide()
        end
    end
    if button.Name then button.Name:SetText("") end
    if button.Count then button.Count:SetText("") end

    -- State textures + hit rect are static button-level setup, applied once
    -- at button creation in EnsureOwnedFlyoutButton. Re-running here would
    -- call SetHitRectInsets from the tainted secure-CallMethod context that
    -- triggers this update, and that method is protected on SecureAction
    -- buttons.
    if InCombatLockdown() then return end
    local sourceButton = ownedFlyout and ownedFlyout:GetParent()
    local settings = GetOwnedFlyoutSettings(sourceButton)
    if settings and settings.skinEnabled then
        SkinButton(button, settings)
    end
end

-- DurationObject-driven CD swipe for popup buttons (no `action` slot, so the
-- ActionBarsOwned action-cooldown loop can't drive these — we mirror Blizzard
-- spell cooldowns directly via the only remaining secret-safe setter).
function UpdateOwnedFlyoutButtonCooldown(button)
    if not button then return end
    local cooldown = button.cooldown or button.Cooldown
    if not cooldown then return end

    local spellID = button._quiFlyoutSpellID
    if not spellID or not C_Spell or not C_Spell.GetSpellCooldownDuration then
        cooldown:Clear()
        if button.chargeCooldown then button.chargeCooldown:Clear() end
        return
    end

    local cdInfo = C_Spell.GetSpellCooldown and C_Spell.GetSpellCooldown(spellID)
    local chargeInfo = C_Spell.GetSpellCharges and C_Spell.GetSpellCharges(spellID)

    -- This runs via secure CallMethod from the flyout snippet, so any field
    -- on cdInfo / chargeInfo may be secret. Comparing secret numbers errors;
    -- coerce through Helpers before gating display.
    local cur = Helpers.SafeToNumber(chargeInfo and chargeInfo.currentCharges, 0)
    local max = Helpers.SafeToNumber(chargeInfo and chargeInfo.maxCharges, 0)
    local showCharge = max > 0 and cur < max

    local enabled = Helpers.SafeValue(cdInfo and cdInfo.isEnabled, false)
    local dur     = Helpers.SafeToNumber(cdInfo and cdInfo.duration, 0)
    local showNormal = enabled and dur > 0

    if showNormal then
        -- ignoreGCD=true so the flyout button's swipe tracks the spell's
        -- real cooldown instead of being masked by the 1.5s GCD sweep.
        local ok, durObj = pcall(C_Spell.GetSpellCooldownDuration, spellID, true)
        if ok and durObj then
            cooldown:SetCooldownFromDurationObject(durObj)
        else
            cooldown:Clear()
        end
    else
        cooldown:Clear()
    end

    if showCharge and C_Spell.GetSpellChargeDuration then
        if not button.chargeCooldown then
            local cd = CreateFrame("Cooldown", nil, button, "CooldownFrameTemplate")
            cd:SetHideCountdownNumbers(true)
            cd:SetDrawSwipe(false)
            cd:SetAllPoints(cooldown)
            cd:SetFrameLevel(button:GetFrameLevel())
            button.chargeCooldown = cd
        end
        local ok, durObj = pcall(C_Spell.GetSpellChargeDuration, spellID)
        if ok and durObj then
            button.chargeCooldown:SetCooldownFromDurationObject(durObj)
        else
            button.chargeCooldown:Clear()
        end
    elseif button.chargeCooldown then
        button.chargeCooldown:Clear()
    end
end

function UpdateAllOwnedFlyoutButtonCooldowns()
    if not ownedFlyout or not ownedFlyout:IsShown() then return end
    for i = 1, (ownedFlyout:GetAttribute("numFlyoutButtons") or 0) do
        local btn = ownedFlyoutButtons[i]
        if btn and btn:IsShown() then
            UpdateOwnedFlyoutButtonCooldown(btn)
        end
    end
end

function ClearOwnedFlyoutButtonCooldown(button)
    if not button then return end
    local cooldown = button.cooldown or button.Cooldown
    if cooldown then cooldown:Clear() end
    if button.chargeCooldown then button.chargeCooldown:Clear() end
end

EnsureOwnedFlyoutFrame = function()
    if ownedFlyout or not USE_OWNED_FLYOUT then return ownedFlyout end

    ownedFlyout = CreateFrame("Frame", "QUI_SpellFlyout", UIParent, "SecureHandlerBaseTemplate")
    ownedFlyout:SetFrameStrata("DIALOG")
    ownedFlyout:SetClampedToScreen(true)
    ownedFlyout:Hide()
    ownedFlyout.Background = CreateFrame("Frame", nil, ownedFlyout)
    ownedFlyout.Background:SetAllPoints()
    ownedFlyout.BackgroundTex = ownedFlyout.Background:CreateTexture(nil, "BACKGROUND")
    ownedFlyout.BackgroundTex:SetAllPoints()
    ownedFlyout.BackgroundTex:SetColorTexture(0, 0, 0, 0.35)
    ownedFlyout:SetScript("OnShow", function(self)
        for i = 1, (self:GetAttribute("numFlyoutButtons") or 0) do
            local btn = ownedFlyoutButtons[i]
            if btn and btn:IsShown() then
                ApplyOwnedFlyoutButtonVisuals(btn, btn:GetAttribute("qui-flyout-spell"))
                UpdateOwnedFlyoutButtonCooldown(btn)
            end
        end
    end)
    ownedFlyout:SetScript("OnHide", function(self)
        for i = 1, (self:GetAttribute("numFlyoutButtons") or 0) do
            local btn = ownedFlyoutButtons[i]
            if btn then
                ApplyOwnedFlyoutButtonVisuals(btn, nil)
                ClearOwnedFlyoutButtonCooldown(btn)
            end
        end
    end)
    ownedFlyout:SetAttribute("numFlyoutButtons", 0)
    ownedFlyout:Execute([[QUI_FlyoutInfo = newtable()]])
    ownedFlyout:SetAttribute("HandleFlyout", [[
        local parent = self:GetAttribute("flyoutParentHandle")
        if not parent then
            self:SetAttribute("flyoutID", nil)
            self:Hide()
            return
        end

        if self:IsShown() and self:GetParent() == parent then
            self:SetAttribute("flyoutID", nil)
            self:Hide()
            return
        end

        local flyoutID = self:GetAttribute("flyoutID")
        local info = QUI_FlyoutInfo and QUI_FlyoutInfo[flyoutID]
        if not info or not info.slots then
            self:SetAttribute("flyoutID", nil)
            self:Hide()
            return
        end

        local direction = parent:GetAttribute("flyoutDirection") or "UP"
        local width = 45
        local height = 45
        self:SetParent(parent)

        local usedSlots = 0
        local prevButton
        for slotID, slotInfo in ipairs(info.slots) do
            if slotInfo and slotInfo.spellID and slotInfo.isKnown then
                usedSlots = usedSlots + 1
                local slotButton = self:GetFrameRef("flyoutButton" .. usedSlots)
                if slotButton then
                    slotButton:SetAttribute("type", "spell")
                    slotButton:SetAttribute("spell", slotInfo.spellID)
                    slotButton:SetAttribute("qui-flyout-spell", slotInfo.spellID)
                    slotButton:CallMethod("QUI_UpdateOwnedFlyoutVisuals", slotInfo.spellID)
                    slotButton:SetWidth(width)
                    slotButton:SetHeight(height)
                    slotButton:ClearAllPoints()

                    if direction == "DOWN" then
                        if prevButton then
                            slotButton:SetPoint("TOP", prevButton, "BOTTOM", 0, -4)
                        else
                            slotButton:SetPoint("TOP", self, "TOP", 0, -7)
                        end
                    elseif direction == "LEFT" then
                        if prevButton then
                            slotButton:SetPoint("RIGHT", prevButton, "LEFT", -4, 0)
                        else
                            slotButton:SetPoint("RIGHT", self, "RIGHT", -7, 0)
                        end
                    elseif direction == "RIGHT" then
                        if prevButton then
                            slotButton:SetPoint("LEFT", prevButton, "RIGHT", 4, 0)
                        else
                            slotButton:SetPoint("LEFT", self, "LEFT", 7, 0)
                        end
                    else
                        if prevButton then
                            slotButton:SetPoint("BOTTOM", prevButton, "TOP", 0, 4)
                        else
                            slotButton:SetPoint("BOTTOM", self, "BOTTOM", 0, 7)
                        end
                    end

                    slotButton:Show()
                    prevButton = slotButton
                end
            end
        end

        for i = usedSlots + 1, self:GetAttribute("numFlyoutButtons") do
            local slotButton = self:GetFrameRef("flyoutButton" .. i)
            if slotButton then
                slotButton:Hide()
                slotButton:SetAttribute("type", nil)
                slotButton:SetAttribute("spell", nil)
                slotButton:SetAttribute("qui-flyout-spell", nil)
                slotButton:CallMethod("QUI_ClearOwnedFlyoutVisuals")
            end
        end

        if usedSlots == 0 then
            self:SetAttribute("flyoutID", nil)
            self:Hide()
            return
        end

        local extent
        if direction == "LEFT" or direction == "RIGHT" then
            extent = 14 + usedSlots * width + (usedSlots - 1) * 4
            self:SetWidth(extent)
            self:SetHeight(height)
        else
            extent = 14 + usedSlots * height + (usedSlots - 1) * 4
            self:SetWidth(width)
            self:SetHeight(extent)
        end

        self:SetAttribute("flyoutID", flyoutID)
        self:ClearAllPoints()
        if direction == "DOWN" then
            self:SetPoint("TOP", parent, "BOTTOM", 0, -4)
        elseif direction == "LEFT" then
            self:SetPoint("RIGHT", parent, "LEFT", -4, 0)
        elseif direction == "RIGHT" then
            self:SetPoint("LEFT", parent, "RIGHT", 4, 0)
        else
            self:SetPoint("BOTTOM", parent, "TOP", 0, 4)
        end

        self:Show()
    ]])

    return ownedFlyout
end

function EnsureOwnedFlyoutButton(index)
    local btn = ownedFlyoutButtons[index]
    if btn then return btn end

    local flyout = EnsureOwnedFlyoutFrame()
    if not flyout then return nil end

    local name = "QUI_SpellFlyoutButton" .. index
    btn = CreateFrame("CheckButton", name, flyout, "ActionButtonTemplate, SecureActionButtonTemplate")
    btn:RegisterForClicks("AnyDown", "AnyUp")
    do
        local _db = GetDB()
        local _g = _db and _db.global
        btn:SetAttribute("useOnKeyDown", _g and _g.useOnKeyDown == true)
    end
    btn:SetAttribute("checkselfcast", true)
    btn:SetAttribute("checkfocuscast", true)
    btn:SetAttribute("checkmouseovercast", true)
    btn:SetAttribute("type", nil)
    btn._quiOwnedFlyout = true

    btn:SetScript("OnDragStart", nil)
    btn:SetScript("OnReceiveDrag", nil)
    btn.QUI_UpdateOwnedFlyoutVisuals = function(self, spellID)
        ApplyOwnedFlyoutButtonVisuals(self, spellID)
        UpdateOwnedFlyoutButtonCooldown(self)
    end
    btn.QUI_ClearOwnedFlyoutVisuals = function(self)
        ApplyOwnedFlyoutButtonVisuals(self, nil)
        ClearOwnedFlyoutButtonCooldown(self)
    end
    btn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if self._quiFlyoutSpellID then
            GameTooltip:SetSpellByID(self._quiFlyoutSpellID)
        end
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", GameTooltip_Hide)
    ApplySpellFlyoutButtonStateTextures(btn)
    if btn.Name then btn.Name:SetText("") end
    if btn.Count then btn.Count:SetText("") end
    SecureHandlerWrapScript(btn, "OnClick", flyout, [[
        if not down then
            owner:SetAttribute("flyoutID", nil)
            owner:Hide()
        end
        if button == "Keybind" then
            return "LeftButton"
        end
    ]])

    flyout:SetFrameRef("flyoutButton" .. index, btn)
    ownedFlyoutButtons[index] = btn
    return btn
end

ownedFlyoutInfo = {}
ownedFlyoutInfoDiscovered = false
ownedFlyoutSeen = {}

function PopulateOwnedFlyoutInfoEntry(info, flyoutID, numSlots, isKnown)
    if not info then return end
    info.isKnown = isKnown and true or false
    info.slots = info.slots or {}

    for slot = 1, numSlots do
        local spellID, overrideSpellID, isKnownSlot = GetFlyoutSlotInfo(flyoutID, slot)
        if GetCallPetSpellInfo and type(spellID) == "number" and spellID > 0 then
            local petIndex, petName = GetCallPetSpellInfo(spellID)
            if petIndex and (not petName or petName == "") then
                isKnownSlot = false
            end
        end

        info.slots[slot] = info.slots[slot] or {}
        info.slots[slot].spellID = spellID
        info.slots[slot].isKnown = isKnownSlot and true or false
    end

    for slot = numSlots + 1, #info.slots do
        info.slots[slot] = nil
    end
end

function DiscoverOwnedFlyoutInfo()
    wipe(ownedFlyoutInfo)

    for flyoutID = 1, 300 do
        local ok, _, _, numSlots, isKnown = pcall(GetFlyoutInfo, flyoutID)
        if ok and type(numSlots) == "number" and numSlots > 0 then
            local info = { slots = {} }
            PopulateOwnedFlyoutInfoEntry(info, flyoutID, numSlots, isKnown)
            ownedFlyoutInfo[flyoutID] = info
        end
    end

    ownedFlyoutInfoDiscovered = true
end

function UpdateOwnedFlyoutInfo()
    if not ownedFlyoutInfoDiscovered then
        DiscoverOwnedFlyoutInfo()
        return
    end

    local seen = ownedFlyoutSeen
    wipe(seen)
    for flyoutID = 1, 300 do
        local ok, _, _, numSlots, isKnown = pcall(GetFlyoutInfo, flyoutID)
        if ok and type(numSlots) == "number" and numSlots > 0 then
            local info = ownedFlyoutInfo[flyoutID] or { slots = {} }
            PopulateOwnedFlyoutInfoEntry(info, flyoutID, numSlots, isKnown)
            ownedFlyoutInfo[flyoutID] = info
            seen[flyoutID] = true
        end
    end

    for flyoutID in pairs(ownedFlyoutInfo) do
        if not seen[flyoutID] then
            ownedFlyoutInfo[flyoutID] = nil
        end
    end
    wipe(seen)
end

HideOwnedFlyout = function()
    if ownedFlyout then
        if InCombatLockdown() then
            return
        end
        ownedFlyout:Hide()
        ownedFlyout:SetAttribute("flyoutID", nil)
    end
end
ActionBarsOwned.HideOwnedFlyout = HideOwnedFlyout

SyncOwnedFlyoutInfoToHandler = function()
    if not USE_OWNED_FLYOUT then return end
    if InCombatLockdown() then
        ActionBarsOwned.pendingOwnedFlyoutSync = true
        return
    end

    local flyout = EnsureOwnedFlyoutFrame()
    if not flyout then return end

    UpdateOwnedFlyoutInfo()
    local maxNumSlots = 0
    local data = "QUI_FlyoutInfo = newtable();\n"
    for flyoutID, info in pairs(ownedFlyoutInfo) do
        if info and info.slots and #info.slots > 0 then
            if #info.slots > maxNumSlots then
                maxNumSlots = #info.slots
            end

            data = data .. ("QUI_FlyoutInfo[%d] = newtable();QUI_FlyoutInfo[%d].slots = newtable();\n"):format(flyoutID, flyoutID)
            for slotID, slotInfo in ipairs(info.slots) do
                local spellID = (slotInfo and type(slotInfo.spellID) == "number" and slotInfo.spellID > 0) and slotInfo.spellID or 0
                data = data .. ("QUI_FlyoutInfo[%d].slots[%d] = newtable();QUI_FlyoutInfo[%d].slots[%d].spellID = %d;QUI_FlyoutInfo[%d].slots[%d].isKnown = %s;\n")
                    :format(flyoutID, slotID, flyoutID, slotID, spellID, flyoutID, slotID, slotInfo and slotInfo.isKnown and "true" or "nil")
            end
        end
    end

    if maxNumSlots > #ownedFlyoutButtons then
        for i = #ownedFlyoutButtons + 1, maxNumSlots do
            EnsureOwnedFlyoutButton(i)
        end
        flyout:SetAttribute("numFlyoutButtons", #ownedFlyoutButtons)
    end

    if data ~= lastOwnedFlyoutSyncPayload then
        flyout:Execute(data)
        lastOwnedFlyoutSyncPayload = data
    end

    ActionBarsOwned.pendingOwnedFlyoutSync = false
end

do
    -- Mirror SPELL_UPDATE_COOLDOWN/CHARGES into popup-button swipes while the
    -- flyout is open. No-op when hidden — OnHide path already clears.
    local cdEventFrame = CreateFrame("Frame")
    cdEventFrame:RegisterEvent("SPELL_UPDATE_COOLDOWN")
    cdEventFrame:RegisterEvent("SPELL_UPDATE_CHARGES")
    cdEventFrame:RegisterEvent("SPELL_UPDATE_USABLE")
    cdEventFrame:SetScript("OnEvent", UpdateAllOwnedFlyoutButtonCooldowns)
end

ShowOwnedFlyoutForButton = function(parentButton)
    if not USE_OWNED_FLYOUT or not parentButton then
        return false
    end

    local action = parentButton.action
    if not action then
        HideOwnedFlyout()
        return false
    end

    local actionType, flyoutID = GetActionInfo(action)
    if actionType ~= "flyout" or not flyoutID then
        HideOwnedFlyout()
        return false
    end

    SyncOwnedFlyoutInfoToHandler()
    local flyout = EnsureOwnedFlyoutFrame()
    if not flyout then return false end

    flyout:SetAttribute("flyoutParentHandle", parentButton)
    flyout:RunAttribute("HandleFlyout", flyoutID)
    return flyout:IsShown()
end

end -- do (owned spell flyout)

function IsSpellFlyoutButtonFrame(button, flyout)
    if not button then return false end
    if flyout and button.GetParent and button:GetParent() == flyout then
        return true
    end

    local name = button.GetName and button:GetName()
    if not name then return false end

    return name:match("^SpellFlyoutButton%d+$") ~= nil
        or name:match("^SpellFlyoutPopupButton%d+$") ~= nil
end

spellFlyoutButtonsScratch = {}
spellFlyoutSeenScratch = {}

function AddCollectedSpellFlyoutButton(button, flyout, buttons, seen)
    if not button or seen[button] then return end
    if not (button.IsObjectType and button:IsObjectType("Button")) then return end
    if not IsSpellFlyoutButtonFrame(button, flyout) then return end

    seen[button] = true
    buttons[#buttons + 1] = button
end

function CollectSpellFlyoutButtons(flyout)
    local buttons, seen = spellFlyoutButtonsScratch, spellFlyoutSeenScratch
    wipe(buttons)
    wipe(seen)

    if flyout and flyout.GetChildren then
        local nChildren = select('#', flyout:GetChildren())
        for i = 1, nChildren do
            local child = select(i, flyout:GetChildren())
            AddCollectedSpellFlyoutButton(child, flyout, buttons, seen)
            if child and child.GetChildren then
                local nGrand = select('#', child:GetChildren())
                for j = 1, nGrand do
                    local grandChild = select(j, child:GetChildren())
                    AddCollectedSpellFlyoutButton(grandChild, flyout, buttons, seen)
                end
            end
        end
    end

    for i = 1, 40 do
        AddCollectedSpellFlyoutButton(_G["SpellFlyoutButton" .. i], flyout, buttons, seen)
        AddCollectedSpellFlyoutButton(_G["SpellFlyoutPopupButton" .. i], flyout, buttons, seen)
    end

    wipe(seen)
    return buttons
end

function GetSpellFlyoutSkinSettings(flyout)
    local sourceBarKey = GetSpellFlyoutSourceBarKey(flyout)
    if sourceBarKey then
        local sourceSettings = GetEffectiveSettings(sourceBarKey)
        if sourceSettings then
            return sourceSettings
        end
    end

    return GetGlobalSettings()
end

function GetSpellFlyoutSourceButtonSize(flyout)
    local sourceButton = GetSpellFlyoutSourceButton(flyout)
    if not (sourceButton and sourceButton.GetSize) then
        return nil, nil
    end

    local rawW, rawH = sourceButton:GetSize()
    local width = Helpers.SafeToNumber(rawW)
    local height = Helpers.SafeToNumber(rawH)
    if not width or not height or width <= 0 or height <= 0 then
        return nil, nil
    end

    return width, height
end

function SkinSpellFlyoutContainer(flyout)
    if not flyout then return end

    local bg = flyout.Background
    if not bg then return end

    if bg.Start then bg.Start:SetAlpha(0) end
    if bg.End then bg.End:SetAlpha(0) end
    if bg.HorizontalMiddle then bg.HorizontalMiddle:SetAlpha(0) end
    if bg.VerticalMiddle then bg.VerticalMiddle:SetAlpha(0) end
end

ApplySpellFlyoutButtonStateTextures = function(button)
    if not button then return end

    if button.SetHitRectInsets then
        button:SetHitRectInsets(0, 0, 0, 0)
    end

    local normal = button.GetNormalTexture and button:GetNormalTexture()
    if normal then
        normal:SetAlpha(0)
        normal:ClearAllPoints()
        normal:SetAllPoints(button)
    end

    local pushed = button.GetPushedTexture and button:GetPushedTexture()
    if pushed then
        pushed:SetTexture(TEXTURES.pushed)
        pushed:ClearAllPoints()
        pushed:SetAllPoints(button)
    end

    local checked = button.GetCheckedTexture and button:GetCheckedTexture()
    if checked then
        checked:SetTexture(TEXTURES.checked)
        checked:ClearAllPoints()
        checked:SetAllPoints(button)
    end

    local highlight = button.GetHighlightTexture and button:GetHighlightTexture()
    if highlight then
        highlight:SetTexture(TEXTURES.highlight)
        highlight:ClearAllPoints()
        highlight:SetAllPoints(button)
    end
end

SkinSpellFlyoutButtons = function()
    if ActionBarsOwned.useOwnedFlyout then return end
    local flyout = _G.SpellFlyout
    if not (flyout and flyout.IsShown and flyout:IsShown()) then return end
    if InCombatLockdown() then
        ActionBarsOwned.pendingFlyoutSkin = true
        return
    end

    SkinSpellFlyoutContainer(flyout)

    local settings = GetSpellFlyoutSkinSettings(flyout)
    if not (settings and settings.skinEnabled) then return end

    local sourceWidth, sourceHeight = GetSpellFlyoutSourceButtonSize(flyout)

    for _, button in ipairs(CollectSpellFlyoutButtons(flyout)) do
        if sourceWidth and sourceHeight and button.SetSize then
            button:SetSize(sourceWidth, sourceHeight)
        end
        ApplySpellFlyoutButtonStateTextures(button)
        SkinButton(button, settings)
    end

    -- Rebuild flyout background extents after resizing popup buttons.
    if flyout.Layout then
        flyout:Layout()
    end
end

function HookSpellFlyoutSkinning()
    if spellFlyoutSkinHooked then return end

    local flyout = _G.SpellFlyout
    if not flyout then return end

    spellFlyoutSkinHooked = true
    flyout:HookScript("OnShow", function()
        C_Timer.After(0, SkinSpellFlyoutButtons)
    end)
end

ActionBarsOwned.HookSpellFlyoutSkinning = HookSpellFlyoutSkinning

end -- do (spell flyout skinning)

---------------------------------------------------------------------------
-- PAGE ARROW VISIBILITY
---------------------------------------------------------------------------
do

function CollectPageArrowFrames()
    local seen, frames = {}, {}

    local function AddFrame(frame)
        if not frame or seen[frame] then return end
        if frame.Hide and frame.Show then
            seen[frame] = true
            table.insert(frames, frame)
        end
    end

    local mainBar = _G.MainActionBar or _G.MainMenuBar
    AddFrame(mainBar and mainBar.ActionBarPageNumber)
    AddFrame(_G.ActionBarPageNumber)

    AddFrame(_G.ActionBarUpButton)
    AddFrame(_G.ActionBarDownButton)

    local artFrame = _G.MainMenuBarArtFrame
    AddFrame(artFrame and artFrame.PageNumber)
    AddFrame(artFrame and artFrame.PageUpButton)
    AddFrame(artFrame and artFrame.PageDownButton)

    return frames
end

function SchedulePageArrowVisibilityRetry()
    local ebs = ActionBarsOwned.extraBtnState
    if ebs.pageArrowRetryTimer or ebs.pageArrowRetryAttempts >= ebs.PAGE_ARROW_RETRY_MAX_ATTEMPTS then return end
    ebs.pageArrowRetryAttempts = ebs.pageArrowRetryAttempts + 1
    ebs.pageArrowRetryTimer = C_Timer.NewTimer(ebs.PAGE_ARROW_RETRY_DELAY, function()
        ebs.pageArrowRetryTimer = nil
        local db = GetDB()
        if db and db.bars and db.bars.bar1 then
            ApplyPageArrowVisibility(db.bars.bar1.hidePageArrow)
        end
    end)
end

ApplyPageArrowVisibility = function(hide)
    local frames = CollectPageArrowFrames()
    if #frames == 0 then
        if hide then
            SchedulePageArrowVisibilityRetry()
        end
        return
    end

    local ebs = ActionBarsOwned.extraBtnState
    ebs.pageArrowRetryAttempts = 0
    if ebs.pageArrowRetryTimer then
        ebs.pageArrowRetryTimer:Cancel()
        ebs.pageArrowRetryTimer = nil
    end

    if hide then
        for _, frame in ipairs(frames) do
            frame:Hide()
            if not ebs.pageArrowShowHooked[frame] then
                ebs.pageArrowShowHooked[frame] = true
                -- TAINT SAFETY: Defer to break taint chain from secure context.
                hooksecurefunc(frame, "Show", function(self)
                    C_Timer.After(0, function()
                        local db = GetDB()
                        if db and db.bars and db.bars.bar1 and db.bars.bar1.hidePageArrow and self and self.Hide then
                            self:Hide()
                        end
                    end)
                end)
            end
        end
    else
        for _, frame in ipairs(frames) do
            frame:Show()
        end
    end
end

_G.QUI_ApplyPageArrowVisibility = ApplyPageArrowVisibility

end -- do (page arrow visibility)
