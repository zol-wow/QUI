-- qui_rotationassist.lua
-- Displays a standalone icon showing Blizzard's next recommended ability
-- Uses C_AssistedCombat API (Starter Build / Rotation Helper)

local ADDON_NAME, QUI = ...
local LSM = QUI.LSM

local GetCore = QUI.Helpers.GetCore
local IsSecretValue = QUI.Helpers.IsSecretValue
local ApplyCooldownFromSpell = QUI.Helpers.ApplyCooldownFromSpell

-- Locals for performance
local GetTime = GetTime
local InCombatLockdown = InCombatLockdown
local UnitCanAttack = UnitCanAttack
local UnitExists = UnitExists
local CreateFrame = CreateFrame
local UIParent = UIParent
local pcall = pcall
local ipairs = ipairs
local C_Timer = C_Timer

-- No polling ticker — updates are event-driven via the centralized
-- OnSetActionSpell EventRegistry callback in actionbars.lua which calls
-- RotationAssistIcon.Update, plus direct DoUpdate() calls on
-- PLAYER_TARGET_CHANGED and combat state transitions.

-- Icon state colors
local COLOR_USABLE = { 1, 1, 1 }
local COLOR_UNUSABLE = { 0.4, 0.4, 0.4 }
local COLOR_NO_MANA = { 0.5, 0.5, 1 }
local COLOR_OUT_OF_RANGE = { 0.8, 0.2, 0.2 }

-- Frame references
local iconFrame = nil
local isInitialized = false
local lastSpellID = nil
local inCombat = false

-- Performance: Ticker instead of OnUpdate

-- GCD spell ID (standard global cooldown reference)
local GCD_SPELL_ID = 61304

-- Forward declarations
local CreateIconFrame, RefreshIconFrame, UpdateIconDisplay, UpdateVisibility

--------------------------------------------------------------------------------
-- Keybind Lookup (uses shared formatter from keybinds.lua)
--------------------------------------------------------------------------------

local function FormatKeybind(keybind)
    if QUI.FormatKeybind then
        return QUI.FormatKeybind(keybind)
    end
    return keybind -- fallback if not available
end

local function GetKeybindForSpell(spellID)
    if not spellID then return nil end

    local keybind = nil

    -- Use QUI.Keybinds if available (from keybinds.lua)
    if QUI.Keybinds and QUI.Keybinds.GetKeybindForSpell then
        keybind = QUI.Keybinds.GetKeybindForSpell(spellID)

        -- If no keybind found, try finding the BASE spell (for proc abilities)
        -- e.g., Thunder Blast -> Thunder Clap
        if not keybind then
            local ok, baseSpellID = pcall(function()
                return FindBaseSpellByID and FindBaseSpellByID(spellID)
            end)
            if ok and baseSpellID and baseSpellID ~= spellID then
                keybind = QUI.Keybinds.GetKeybindForSpell(baseSpellID)
            end
        end

        -- Also try C_Spell.GetOverrideSpell in reverse
        if not keybind then
            local ok, overrideID = pcall(function()
                return C_Spell.GetOverrideSpell and C_Spell.GetOverrideSpell(spellID)
            end)
            if ok and overrideID and overrideID ~= spellID then
                keybind = QUI.Keybinds.GetKeybindForSpell(overrideID)
            end
        end

        if keybind then return keybind end
    end

    -- Fallback: Find action buttons with this spell (try base spell too)
    local baseSpellID = FindBaseSpellByID and FindBaseSpellByID(spellID) or spellID
    local slots = C_ActionBar.FindSpellActionButtons(baseSpellID)

    if slots and #slots > 0 then
        for _, slot in ipairs(slots) do
            -- Try to get keybind for this action slot
            local actionName = "ACTIONBUTTON" .. slot
            if slot > 12 and slot <= 24 then
                actionName = "ACTIONBUTTON" .. (slot - 12)
            elseif slot > 24 and slot <= 36 then
                actionName = "MULTIACTIONBAR3BUTTON" .. (slot - 24)
            elseif slot > 36 and slot <= 48 then
                actionName = "MULTIACTIONBAR4BUTTON" .. (slot - 36)
            elseif slot > 48 and slot <= 60 then
                actionName = "MULTIACTIONBAR1BUTTON" .. (slot - 48)
            elseif slot > 60 and slot <= 72 then
                actionName = "MULTIACTIONBAR2BUTTON" .. (slot - 60)
            end

            local key1 = GetBindingKey(actionName)
            if key1 then
                return FormatKeybind(key1)
            end
        end
    end

    return nil
end

--------------------------------------------------------------------------------
-- Database Access
--------------------------------------------------------------------------------

local function GetDB()
    local core = GetCore()
    if core and core.db and core.db.profile then
        return core.db.profile.rotationAssistIcon
    end
    return nil
end

local function NormalizeFrameStrata(strata)
    if strata == "LOW" then
        return "LOW"
    end
    return "MEDIUM"
end

local function ApplyIconFrameLayering(frame, db)
    if not frame then return end

    local normalizedStrata = NormalizeFrameStrata(db and db.frameStrata)
    if db and db.frameStrata ~= normalizedStrata then
        db.frameStrata = normalizedStrata
    end
    frame:SetFrameStrata(normalizedStrata)

    local core = GetCore()
    if core and core.GetHUDFrameLevel then
        local profile = core.db and core.db.profile
        local hudLayering = profile and profile.hudLayering
        local layerPriority = hudLayering and hudLayering.essential or 5
        frame:SetFrameLevel(core:GetHUDFrameLevel(layerPriority))
    end
end

--------------------------------------------------------------------------------
-- Icon Frame Creation
--------------------------------------------------------------------------------

CreateIconFrame = function()
    if iconFrame then return iconFrame end

    -- Main frame
    iconFrame = CreateFrame("Button", "QUI_RotationAssistIcon", UIParent, "BackdropTemplate")
    iconFrame:SetSize(56, 56)
    iconFrame:SetPoint("CENTER", UIParent, "CENTER", 0, -180)
    ApplyIconFrameLayering(iconFrame, GetDB())
    iconFrame:SetClampedToScreen(true)
    iconFrame:EnableMouse(true)
    iconFrame:SetMovable(true)
    iconFrame:RegisterForDrag("LeftButton")

    -- Icon texture (inset by 2px default for border visibility)
    iconFrame.icon = iconFrame:CreateTexture(nil, "ARTWORK")
    iconFrame.icon:SetPoint("TOPLEFT", 2, -2)
    iconFrame.icon:SetPoint("BOTTOMRIGHT", -2, 2)
    iconFrame.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92) -- Crop edges

    -- Cooldown frame (matches icon inset)
    iconFrame.cooldown = CreateFrame("Cooldown", nil, iconFrame, "CooldownFrameTemplate")
    iconFrame.cooldown:SetPoint("TOPLEFT", 2, -2)
    iconFrame.cooldown:SetPoint("BOTTOMRIGHT", -2, 2)
    iconFrame.cooldown:SetDrawSwipe(true)
    iconFrame.cooldown:SetDrawEdge(false)
    iconFrame.cooldown:SetSwipeColor(0, 0, 0, 0.8)
    iconFrame.cooldown:SetHideCountdownNumbers(true)

    -- Keybind text
    iconFrame.keybindText = iconFrame:CreateFontString(nil, "OVERLAY")
    iconFrame.keybindText:SetFont(STANDARD_TEXT_FONT, 13, "OUTLINE")
    iconFrame.keybindText:SetPoint("BOTTOMRIGHT", iconFrame, "BOTTOMRIGHT", -2, 2)
    iconFrame.keybindText:SetTextColor(1, 1, 1, 1)
    iconFrame.keybindText:SetShadowOffset(1, -1)
    iconFrame.keybindText:SetShadowColor(0, 0, 0, 1)

    -- Drag handlers
    iconFrame:SetScript("OnDragStart", function(self)
        local db = GetDB()
        local isAnchoredOverride = _G.QUI_HasFrameAnchor and _G.QUI_HasFrameAnchor("rotationAssistIcon")
        if db and not db.isLocked and not isAnchoredOverride then
            self:StartMoving()
        end
    end)

    iconFrame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()

        -- Frame anchoring owns position while an override is active.
        if _G.QUI_HasFrameAnchor and _G.QUI_HasFrameAnchor("rotationAssistIcon") then
            return
        end

        -- Save position relative to screen center
        local db = GetDB()
        if db then
            local selfX, selfY = self:GetCenter()
            local parentX, parentY = UIParent:GetCenter()
            if selfX and selfY and parentX and parentY then
                local core = GetCore()
                if core and core.PixelRound then
                    db.positionX = core:PixelRound(selfX - parentX)
                    db.positionY = core:PixelRound(selfY - parentY)
                else
                    db.positionX = math.floor(selfX - parentX + 0.5)
                    db.positionY = math.floor(selfY - parentY + 0.5)
                end
            end
        end
    end)

    -- Hide initially
    iconFrame:Hide()

    return iconFrame
end

--------------------------------------------------------------------------------
-- Icon Display Update
--------------------------------------------------------------------------------

UpdateIconDisplay = function(spellID)
    if not iconFrame then return end

    local db = GetDB()
    if not db or not db.enabled then
        iconFrame:Hide()
        return
    end

    -- spellID may be secret during combat.  Secret userdata is truthy
    -- and non-zero, so it passes the nil/0 gate.  All downstream calls
    -- use C-side functions that accept secrets natively.
    if not spellID or spellID == 0 then
        -- No recommendation right now.  If the frame is already visible
        -- (mid-combat), keep showing the last spell rather than hiding
        -- and re-showing every time the API has a brief gap.
        if not iconFrame:IsShown() then
            UpdateVisibility()
        end
        return
    end

    -- We have a spell - make sure frame is visible (respecting visibility mode)
    UpdateVisibility()

    -- Texture: C_Spell.GetSpellTexture + SetTexture are both C-side.
    local texOk, texture = pcall(C_Spell.GetSpellTexture, spellID)
    if texOk and texture then
        iconFrame.icon:SetTexture(texture)
    end

    -- Usability / range tinting.
    -- C_Spell.IsSpellUsable and IsSpellInRange can return secret booleans.
    -- Secret userdata is always truthy, so use strict == true checks to
    -- avoid misclassification (e.g., secret-false → truthy → wrong branch).
    local usableOk, isUsable, notEnoughMana = pcall(C_Spell.IsSpellUsable, spellID)
    if not usableOk then isUsable, notEnoughMana = true, false end
    isUsable = (isUsable == true)
    notEnoughMana = (notEnoughMana == true)

    local inRange = true
    local rangeOk, hasRange = pcall(C_Spell.SpellHasRange, spellID)
    if rangeOk and hasRange == true and UnitExists("target") then
        local rOk, rangeCheck = pcall(C_Spell.IsSpellInRange, spellID, "target")
        if rOk and rangeCheck == false then
            inRange = false
        end
    end

    local color
    if not inRange then
        color = COLOR_OUT_OF_RANGE
    elseif notEnoughMana then
        color = COLOR_NO_MANA
    elseif not isUsable then
        color = COLOR_UNUSABLE
    else
        color = COLOR_USABLE
    end
    iconFrame.icon:SetVertexColor(color[1], color[2], color[3], 1)

    -- GCD cooldown swipe is handled separately by UpdateGCDCooldown()
    -- (triggered by SPELL_UPDATE_COOLDOWN events for responsiveness)

    -- Update keybind text
    if db.showKeybind then
        local keybind = GetKeybindForSpell(spellID)
        iconFrame.keybindText:SetText(keybind or "")
        iconFrame.keybindText:Show()
    else
        iconFrame.keybindText:Hide()
    end
end

--------------------------------------------------------------------------------
-- GCD Cooldown Update (event-driven for responsiveness)
--------------------------------------------------------------------------------

local function UpdateGCDCooldown()
    if not iconFrame or not iconFrame.cooldown then return end

    local db = GetDB()
    if not db or not db.cooldownSwipeEnabled then
        iconFrame.cooldown:Hide()
        return
    end

    -- Only show GCD swipe when the icon itself is visible
    if not iconFrame:IsShown() then return end

    local cd = iconFrame.cooldown
    if ApplyCooldownFromSpell(cd, GCD_SPELL_ID) then
        cd:Show()
        return
    end

    cd:Clear()
end

--------------------------------------------------------------------------------
-- Visibility Management
--------------------------------------------------------------------------------

UpdateVisibility = function()
    if not iconFrame then return end

    local db = GetDB()
    if not db or not db.enabled then
        iconFrame:Hide()
        return
    end

    local shouldShow = false
    local visibility = db.visibility or "always"

    if visibility == "always" then
        shouldShow = true
    elseif visibility == "combat" then
        shouldShow = inCombat
    elseif visibility == "hostile" then
        shouldShow = UnitExists("target") and UnitCanAttack("player", "target")
    end

    if shouldShow then
        iconFrame:Show()
    else
        iconFrame:Hide()
    end
end

--------------------------------------------------------------------------------
-- Ticker-based Update (Performance: runs only when needed, not every frame)
--------------------------------------------------------------------------------

local function DoUpdate(overrideSpellID)
    local db = GetDB()
    if not db or not db.enabled then
        return
    end

    local spellID = overrideSpellID
    if not spellID then
        -- Fallback: query the API if no override provided
        if not C_AssistedCombat or not C_AssistedCombat.GetNextCastSpell then
            return
        end
        local ok, sid = pcall(C_AssistedCombat.GetNextCastSpell, false)
        if ok then spellID = sid end
    end

    -- Secret spellID: pass directly to C-side display functions (texture,
    -- tint, keybind).  Skip the equality dedup — comparing secret to
    -- non-secret taints, and the update is cheap.
    local isSecret = spellID and IsSecretValue(spellID)
    if isSecret then
        UpdateIconDisplay(spellID)
        return
    end

    -- Resolve talent-transformed display spell.  Blizzard may recommend a
    -- base spell ID while talents have replaced it with an override.
    -- The texture, keybind, and usability should reflect the override.
    if spellID and C_Spell and C_Spell.GetOverrideSpell then
        local okOvr, overrideID = pcall(C_Spell.GetOverrideSpell, spellID)
        if okOvr and overrideID and overrideID ~= spellID then
            spellID = overrideID
        end
    end

    -- Non-secret: dedup by value
    if spellID ~= lastSpellID then
        lastSpellID = spellID
        UpdateIconDisplay(spellID)
    end
end


--------------------------------------------------------------------------------
-- Frame Refresh (Apply Settings)
--------------------------------------------------------------------------------

RefreshIconFrame = function()
    if not iconFrame then
        CreateIconFrame()
    end

    local db = GetDB()
    if not db then
        if iconFrame then iconFrame:Hide() end
        return
    end

    ApplyIconFrameLayering(iconFrame, db)

    if not db.enabled then
        iconFrame:Hide()
        return
    end

    -- Size (guard with pcall to prevent secret value crash when backdrop recalculates)
    -- SetSize triggers backdrop texture coordinate recalculation which can fail during combat
    local size = db.iconSize or 56
    pcall(iconFrame.SetSize, iconFrame, size, size)

    -- Position (manual only when no frame-anchoring override is active)
    local isAnchoredOverride = _G.QUI_HasFrameAnchor and _G.QUI_HasFrameAnchor("rotationAssistIcon")
    if not isAnchoredOverride then
        iconFrame:ClearAllPoints()
        local posX = db.positionX or 0
        local posY = db.positionY or -180
        iconFrame:SetPoint("CENTER", UIParent, "CENTER", posX, posY)
    end

    -- Border (uses SafeSetBackdrop to avoid secret value errors during combat)
    local inset = 0
    local core = GetCore()
    local SafeSetBackdrop = core and core.SafeSetBackdrop

    if db.showBorder then
        local borderColor = db.borderColor or { 0, 0, 0, 1 }
        local thickness = db.borderThickness or 2
        inset = thickness

        -- Use backdrop for border
        local backdropInfo = {
            edgeFile = "Interface\\Buttons\\WHITE8x8",
            edgeSize = thickness,
        }
        if not db.isLocked then
            -- Green border when unlocked
            if SafeSetBackdrop then
                SafeSetBackdrop(iconFrame, backdropInfo, { 0, 1, 0, 1 })
            else
                iconFrame:SetBackdrop(backdropInfo)
                iconFrame:SetBackdropBorderColor(0, 1, 0, 1)
            end
        else
            if SafeSetBackdrop then
                SafeSetBackdrop(iconFrame, backdropInfo, borderColor)
            else
                iconFrame:SetBackdrop(backdropInfo)
                iconFrame:SetBackdropBorderColor(borderColor[1], borderColor[2], borderColor[3], borderColor[4] or 1)
            end
        end
        iconFrame:SetBackdropColor(0, 0, 0, 0)
    else
        if SafeSetBackdrop then
            SafeSetBackdrop(iconFrame, nil)
        else
            iconFrame:SetBackdrop(nil)
        end
    end

    -- Adjust icon and cooldown inset based on border
    iconFrame.icon:ClearAllPoints()
    iconFrame.icon:SetPoint("TOPLEFT", inset, -inset)
    iconFrame.icon:SetPoint("BOTTOMRIGHT", -inset, inset)
    iconFrame.cooldown:ClearAllPoints()
    iconFrame.cooldown:SetPoint("TOPLEFT", inset, -inset)
    iconFrame.cooldown:SetPoint("BOTTOMRIGHT", -inset, inset)

    -- Update cooldown swipe visibility based on setting
    iconFrame.cooldown:SetDrawSwipe(db.cooldownSwipeEnabled)
    if not db.cooldownSwipeEnabled then
        iconFrame.cooldown:Hide()
    end

    -- Lock/unlock state
    iconFrame:EnableMouse(not db.isLocked or true) -- Always enable for visibility, but drag only when unlocked

    -- Keybind text styling
    if db.showKeybind then
        -- Get font: use keybindFont if set, otherwise fall back to general.font
        local fontName = db.keybindFont
        if not fontName then
            if core and core.db and core.db.profile and core.db.profile.general then
                fontName = core.db.profile.general.font
            end
        end
        local fontPath = LSM:Fetch("font", fontName) or STANDARD_TEXT_FONT
        local fontSize = db.keybindSize or 13
        local outline = db.keybindOutline and "OUTLINE" or ""
        iconFrame.keybindText:SetFont(fontPath, fontSize, outline)

        local color = db.keybindColor or { 1, 1, 1, 1 }
        iconFrame.keybindText:SetTextColor(color[1], color[2], color[3], color[4] or 1)

        -- Anchor position
        local anchor = db.keybindAnchor or "BOTTOMRIGHT"
        local offsetX = db.keybindOffsetX or -2
        local offsetY = db.keybindOffsetY or 2
        iconFrame.keybindText:ClearAllPoints()
        iconFrame.keybindText:SetPoint(anchor, iconFrame, anchor, offsetX, offsetY)
    end

    -- Force a full visibility + display recheck with the new settings.
    -- Reset lastSpellID so the next DoUpdate() treats the current spell as
    -- "changed" and runs UpdateIconDisplay → UpdateVisibility.
    lastSpellID = nil
    DoUpdate()
end

--------------------------------------------------------------------------------
-- Event Handling
--------------------------------------------------------------------------------

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
eventFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
eventFrame:RegisterEvent("PLAYER_TARGET_CHANGED")
eventFrame:RegisterEvent("SPELL_UPDATE_COOLDOWN")
eventFrame:RegisterEvent("ACTIONBAR_UPDATE_COOLDOWN")

eventFrame:SetScript("OnEvent", function(self, event, ...)
    if event == "PLAYER_ENTERING_WORLD" then
        C_Timer.After(0.5, function()
            if not isInitialized then
                CreateIconFrame()
                isInitialized = true
            end
            local db = GetDB()
            if db and db.enabled then
                RefreshIconFrame()
                DoUpdate()
            end
        end)
    elseif event == "PLAYER_REGEN_ENABLED" then
        inCombat = false
        local db = GetDB()
        if db and db.enabled then
            UpdateVisibility()
            DoUpdate()
        end
    elseif event == "PLAYER_REGEN_DISABLED" then
        inCombat = true
        local db = GetDB()
        if db and db.enabled then
            UpdateVisibility()
            DoUpdate()
        end
    elseif event == "PLAYER_TARGET_CHANGED" then
        UpdateVisibility()
        -- Force spell update on target change
        lastSpellID = nil
        DoUpdate()  -- Immediate update on target change
    elseif event == "SPELL_UPDATE_COOLDOWN" or event == "ACTIONBAR_UPDATE_COOLDOWN" then
        -- Skip if icon is hidden (no work needed when not visible)
        if iconFrame and iconFrame:IsShown() then
            UpdateGCDCooldown()
        end
    end
end)

QUI.QUI_PerfRegistry = QUI.QUI_PerfRegistry or {}
QUI.QUI_PerfRegistry[#QUI.QUI_PerfRegistry + 1] = { name = "RotationAssist", frame = eventFrame }

--------------------------------------------------------------------------------
-- Global Refresh Function
--------------------------------------------------------------------------------

local function RefreshRotationAssistIcon()
    RefreshIconFrame()
end

_G.QUI_RefreshRotationAssistIcon = RefreshRotationAssistIcon

--------------------------------------------------------------------------------
-- Export
--------------------------------------------------------------------------------

QUI.RotationAssistIcon = {
    Refresh = RefreshRotationAssistIcon,
    GetFrame = function() return iconFrame end,
    Update = DoUpdate,  -- called by centralized OnSetActionSpell callback
}

if QUI.Registry then
    QUI.Registry:Register("rotationAssist", {
        refresh = _G.QUI_RefreshRotationAssistIcon,
        priority = 40,
        group = "combat",
        importCategories = { "cdm" },
    })
end
