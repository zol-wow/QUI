local ADDON_NAME, QUI = ...
local ns = QUI
local LSM = QUI.LSM

local GetCore = QUI.Helpers.GetCore
local IsSecretValue = QUI.Helpers.IsSecretValue
local ApplyCooldownFromSpell = QUI.Helpers.ApplyCooldownFromSpell

local function CJKFont(fs, p, s, f)
    if ns.Helpers and ns.Helpers.ApplyFontWithFallback then
        ns.Helpers.ApplyFontWithFallback(fs, p, s, f)
    else
        fs:SetFont(p, s, f)
    end
end

local GetTime = GetTime
local InCombatLockdown = InCombatLockdown
local UnitCanAttack = UnitCanAttack
local UnitExists = UnitExists
local CreateFrame = CreateFrame
local UIParent = UIParent
local pcall = pcall
local ipairs = ipairs
local C_Timer = C_Timer

local COLOR_USABLE = { 1, 1, 1 }
local COLOR_UNUSABLE = { 0.4, 0.4, 0.4 }
local COLOR_NO_MANA = { 0.5, 0.5, 1 }
local COLOR_OUT_OF_RANGE = { 0.8, 0.2, 0.2 }

local iconFrame = nil
local isInitialized = false
local lastSpellID = nil
local inCombat = false

local GCD_SPELL_ID = 61304

local CreateIconFrame, RefreshIconFrame, UpdateIconDisplay, UpdateVisibility

local function FormatKeybind(keybind)
    if QUI.FormatKeybind then
        return QUI.FormatKeybind(keybind)
    end
    return keybind
end

local function GetKeybindForSpell(spellID)
    if not spellID then return nil end

    local keybind = nil

    if QUI.Keybinds and QUI.Keybinds.GetKeybindForSpell then
        keybind = QUI.Keybinds.GetKeybindForSpell(spellID)

        if not keybind then
            local ok, baseSpellID = pcall(function()
                return FindBaseSpellByID and FindBaseSpellByID(spellID)
            end)
            if ok and baseSpellID and baseSpellID ~= spellID then
                keybind = QUI.Keybinds.GetKeybindForSpell(baseSpellID)
            end
        end

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

    local baseSpellID = FindBaseSpellByID and FindBaseSpellByID(spellID) or spellID
    local slots = C_ActionBar.FindSpellActionButtons(baseSpellID)

    if slots and #slots > 0 then
        for _, slot in ipairs(slots) do
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

CreateIconFrame = function()
    if iconFrame then return iconFrame end

    iconFrame = CreateFrame("Button", "QUI_RotationAssistIcon", UIParent, "BackdropTemplate")
    iconFrame:SetSize(56, 56)
    iconFrame:SetPoint("CENTER", UIParent, "CENTER", 0, -180)
    ApplyIconFrameLayering(iconFrame, GetDB())
    iconFrame:SetClampedToScreen(true)
    iconFrame:EnableMouse(true)
    iconFrame:SetMovable(true)
    iconFrame:RegisterForDrag("LeftButton")

    iconFrame.icon = iconFrame:CreateTexture(nil, "ARTWORK")
    iconFrame.icon:SetPoint("TOPLEFT", 2, -2)
    iconFrame.icon:SetPoint("BOTTOMRIGHT", -2, 2)
    iconFrame.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    iconFrame.cooldown = CreateFrame("Cooldown", nil, iconFrame, "CooldownFrameTemplate")
    iconFrame.cooldown:SetPoint("TOPLEFT", 2, -2)
    iconFrame.cooldown:SetPoint("BOTTOMRIGHT", -2, 2)
    iconFrame.cooldown:SetDrawSwipe(true)
    iconFrame.cooldown:SetDrawEdge(false)
    iconFrame.cooldown:SetSwipeColor(0, 0, 0, 0.8)
    iconFrame.cooldown:SetHideCountdownNumbers(true)

    iconFrame.keybindText = iconFrame:CreateFontString(nil, "OVERLAY")
    CJKFont(iconFrame.keybindText, QUI.Helpers.GetGeneralFont(), 13, QUI.Helpers.GetGeneralFontOutline())
    iconFrame.keybindText:SetPoint("BOTTOMRIGHT", iconFrame, "BOTTOMRIGHT", -2, 2)
    iconFrame.keybindText:SetTextColor(1, 1, 1, 1)
    iconFrame.keybindText:SetShadowOffset(1, -1)
    iconFrame.keybindText:SetShadowColor(0, 0, 0, 1)

    iconFrame:SetScript("OnDragStart", function(self)
        local db = GetDB()
        local isAnchoredOverride = _G.QUI_HasFrameAnchor and _G.QUI_HasFrameAnchor("rotationAssistIcon")
        if db and not db.isLocked and not isAnchoredOverride then
            self:StartMoving()
        end
    end)

    iconFrame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()

        if _G.QUI_HasFrameAnchor and _G.QUI_HasFrameAnchor("rotationAssistIcon") then
            return
        end

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

    iconFrame:Hide()

    return iconFrame
end

UpdateIconDisplay = function(spellID)
    if not iconFrame then return end

    local db = GetDB()
    if not db or not db.enabled then
        iconFrame:Hide()
        return
    end

    local isEmpty = (spellID == nil) or
        (not IsSecretValue(spellID) and spellID == 0)
    if isEmpty then
        if not iconFrame:IsShown() then
            UpdateVisibility()
        end
        return
    end

    UpdateVisibility()

    local texOk, texture = pcall(C_Spell.GetSpellTexture, spellID)
    if texOk and texture then
        iconFrame.icon:SetTexture(texture)
    end

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

    if db.showKeybind then
        local keybind = GetKeybindForSpell(spellID)
        iconFrame.keybindText:SetText(keybind or "")
        iconFrame.keybindText:Show()
    else
        iconFrame.keybindText:Hide()
    end
end

local function UpdateGCDCooldown()
    if not iconFrame or not iconFrame.cooldown then return end

    local db = GetDB()
    if not db or not db.cooldownSwipeEnabled then
        iconFrame.cooldown:Hide()
        return
    end

    if not iconFrame:IsShown() then return end

    local cd = iconFrame.cooldown
    if ApplyCooldownFromSpell(cd, GCD_SPELL_ID, nil, false) then
        cd:Show()
        return
    end

    QUI.Helpers.ClearCooldown(cd)
end

local _isAvailable = nil

local function RefreshAvailability()
    if not (C_AssistedCombat and C_AssistedCombat.IsAvailable) then
        _isAvailable = true
        return
    end
    local ok, available = pcall(C_AssistedCombat.IsAvailable)
    _isAvailable = ok and (available == true)
end

UpdateVisibility = function()
    if not iconFrame then return end

    local db = GetDB()
    if not db or not db.enabled then
        iconFrame:Hide()
        return
    end

    if _isAvailable == nil then RefreshAvailability() end
    if not _isAvailable then
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

local function DoUpdate(overrideSpellID)
    local db = GetDB()
    if not db or not db.enabled then
        return
    end

    local spellID = overrideSpellID
    if not spellID then
        if not C_AssistedCombat or not C_AssistedCombat.GetNextCastSpell then
            return
        end
        local ok, sid = pcall(C_AssistedCombat.GetNextCastSpell, false)
        if ok then spellID = sid end
    end

    local isSecret = IsSecretValue(spellID)
    if isSecret then
        UpdateIconDisplay(spellID)
        return
    end

    if spellID and C_Spell and C_Spell.GetOverrideSpell then
        local okOvr, overrideID = ns.SafeCall("chain-next", C_Spell.GetOverrideSpell, spellID)
        if okOvr and overrideID and overrideID ~= spellID then
            spellID = overrideID
        end
    end

    if spellID ~= lastSpellID then
        lastSpellID = spellID
        UpdateIconDisplay(spellID)
    end
end

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

    local size = db.iconSize or 56
    ns.SafeCallMethod("best-effort-style", iconFrame, "SetSize", size, size)

    local isAnchoredOverride = _G.QUI_HasFrameAnchor and _G.QUI_HasFrameAnchor("rotationAssistIcon")
    if not isAnchoredOverride then
        iconFrame:ClearAllPoints()
        local posX = db.positionX or 0
        local posY = db.positionY or -180
        iconFrame:SetPoint("CENTER", UIParent, "CENTER", posX, posY)
    end

    local inset = 0
    local core = GetCore()
    local SafeSetBackdrop = core and core.SafeSetBackdrop

    if db.showBorder then
        local bR, bG, bB, bA = QUI.Helpers.GetSkinBorderColor(db, "")
        local thickness = db.borderThickness or 2
        inset = thickness

        local backdropInfo = {
            edgeFile = "Interface\\Buttons\\WHITE8x8",
            edgeSize = thickness,
        }
        if not db.isLocked then
            if SafeSetBackdrop then
                SafeSetBackdrop(iconFrame, backdropInfo, { 0, 1, 0, 1 })
            else
                iconFrame:SetBackdrop(backdropInfo)
                iconFrame:SetBackdropBorderColor(0, 1, 0, 1)
            end
        else
            if SafeSetBackdrop then
                SafeSetBackdrop(iconFrame, backdropInfo, { bR, bG, bB, bA })
            else
                iconFrame:SetBackdrop(backdropInfo)
                iconFrame:SetBackdropBorderColor(bR, bG, bB, bA)
            end
        end
        local _rbgR, _rbgG, _rbgB = 0, 0, 0
        if QUI.Helpers and QUI.Helpers.GetSkinBgColor then _rbgR, _rbgG, _rbgB = QUI.Helpers.GetSkinBgColor() end
        iconFrame:SetBackdropColor(_rbgR, _rbgG, _rbgB, 0)
    else
        if SafeSetBackdrop then
            SafeSetBackdrop(iconFrame, nil)
        else
            iconFrame:SetBackdrop(nil)
        end
    end

    iconFrame.icon:ClearAllPoints()
    iconFrame.icon:SetPoint("TOPLEFT", inset, -inset)
    iconFrame.icon:SetPoint("BOTTOMRIGHT", -inset, inset)
    iconFrame.cooldown:ClearAllPoints()
    iconFrame.cooldown:SetPoint("TOPLEFT", inset, -inset)
    iconFrame.cooldown:SetPoint("BOTTOMRIGHT", -inset, inset)

    iconFrame.cooldown:SetDrawSwipe(db.cooldownSwipeEnabled)
    if not db.cooldownSwipeEnabled then
        iconFrame.cooldown:Hide()
    end

    iconFrame:EnableMouse(true)

    if db.showKeybind then
        local fontName = db.keybindFont
        if not fontName then
            if core and core.db and core.db.profile and core.db.profile.general then
                fontName = core.db.profile.general.font
            end
        end
        local fontPath = LSM:Fetch("font", fontName) or QUI.Helpers.GetGeneralFont()
        local fontSize = db.keybindSize or 13
        local outline = db.keybindOutline and QUI.Helpers.GetGeneralFontOutline() or ""
        CJKFont(iconFrame.keybindText, fontPath, fontSize, outline)

        local color = db.keybindColor or { 1, 1, 1, 1 }
        iconFrame.keybindText:SetTextColor(color[1], color[2], color[3], color[4] or 1)

        local anchor = db.keybindAnchor or "BOTTOMRIGHT"
        local offsetX = db.keybindOffsetX or -2
        local offsetY = db.keybindOffsetY or 2
        iconFrame.keybindText:ClearAllPoints()
        iconFrame.keybindText:SetPoint(anchor, iconFrame, anchor, offsetX, offsetY)
    end

    lastSpellID = nil
    DoUpdate()
end

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
eventFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
eventFrame:RegisterEvent("PLAYER_TARGET_CHANGED")
eventFrame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
eventFrame:RegisterEvent("TRAIT_CONFIG_UPDATED")
eventFrame:RegisterEvent("SPELL_UPDATE_COOLDOWN")
eventFrame:RegisterEvent("ACTIONBAR_UPDATE_COOLDOWN")

if EventRegistry and EventRegistry.RegisterCallback then
    EventRegistry:RegisterCallback("AssistedCombatManager.OnSetActionSpell", function()
        if not (C_AssistedCombat and C_AssistedCombat.GetNextCastSpell) then return end
        local okSpell, newSpell = pcall(C_AssistedCombat.GetNextCastSpell, false)
        if not okSpell then newSpell = nil end
        DoUpdate(newSpell)
    end, "QUI_RotationAssistIcon_OnSetActionSpell")
end

if AssistedCombatManager and AssistedCombatManager.UpdateAllAssistedHighlightFramesForSpell then
    hooksecurefunc(AssistedCombatManager, "UpdateAllAssistedHighlightFramesForSpell", function(_, spellID)
        if not spellID then return end
        DoUpdate(spellID)
    end)
end

local function InitOrCatchUp()
    C_Timer.After(0.5, function()
        if not isInitialized then
            CreateIconFrame()
            isInitialized = true
        end
        RefreshAvailability()
        local db = GetDB()
        if db and db.enabled then
            RefreshIconFrame()
            DoUpdate()
        end
    end)
end

eventFrame:SetScript("OnEvent", function(self, event, ...)
    if event == "PLAYER_ENTERING_WORLD" then
        InitOrCatchUp()
    elseif event == "PLAYER_SPECIALIZATION_CHANGED" or event == "TRAIT_CONFIG_UPDATED" then
        RefreshAvailability()
        local db = GetDB()
        if db and db.enabled then
            UpdateVisibility()
            DoUpdate()
        end
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
        lastSpellID = nil
        DoUpdate()
    elseif event == "SPELL_UPDATE_COOLDOWN" or event == "ACTIONBAR_UPDATE_COOLDOWN" then
        if iconFrame and iconFrame:IsShown() then
            UpdateGCDCooldown()
        end
    end
end)

if QUI.WhenLoggedIn then
    QUI.WhenLoggedIn(function()
        InitOrCatchUp()
    end)
end

local function SetupDebugInstrumentation()
    QUI.QUI_PerfRegistry = QUI.QUI_PerfRegistry or {}
    QUI.QUI_PerfRegistry[#QUI.QUI_PerfRegistry + 1] = { name = "RotationAssist", frame = eventFrame }
end
if QUI.DebugRegister then
    QUI.DebugRegister(SetupDebugInstrumentation)
else
    SetupDebugInstrumentation()
end

local function RefreshRotationAssistIcon()
    RefreshIconFrame()
end

_G.QUI_RefreshRotationAssistIcon = RefreshRotationAssistIcon

QUI.RotationAssistIcon = {
    Refresh = RefreshRotationAssistIcon,
    GetFrame = function() return iconFrame end,
    Update = DoUpdate,
}

if QUI.Registry then
    QUI.Registry:Register("rotationAssist", {
        refresh = _G.QUI_RefreshRotationAssistIcon,
        priority = 40,
        group = "combat",
        importCategories = { "cdm" },
    })
end

if QUI.Helpers and QUI.Helpers.BorderRegistry then
    QUI.Helpers.BorderRegistry.Register({
        key = "rotationAssist", label = ns.L["Rotation Assist Icon"], category = ns.L["Trackers"], prefix = "",
        db = function(p) return p.rotationAssistIcon end,
        refresh = function() if _G.QUI_RefreshRotationAssistIcon then _G.QUI_RefreshRotationAssistIcon() end end,
        legacy = {},
    })
end
