local ADDON_NAME, ns = ...
local QUICore = ns.Addon
local LSM = LibStub("LibSharedMedia-3.0")

-- Pixel-perfect scaling helper
local function Scale(x)
    if QUICore and QUICore.Scale then
        return QUICore:Scale(x)
    end
    return x
end

-- Edit Mode state tracking for power bars
local PowerBarEditMode = {
    active = false,
    sliders = {
        primary = { x = nil, y = nil },
        secondary = { x = nil, y = nil }
    }
}

-- Helper to get texture from general settings (falls back to default)
local function GetDefaultTexture()
    if QUICore and QUICore.db and QUICore.db.profile and QUICore.db.profile.general then
        return QUICore.db.profile.general.texture or "Quazii"
    end
    return "Quazii"
end

-- Helper to get bar-specific texture (falls back to Solid)
local function GetBarTexture(cfg)
    if cfg and cfg.texture then
        return cfg.texture
    end
    return "Solid"
end

-- Helper to get font from general settings (uses shared helpers)
local Helpers = ns.Helpers
local GetGeneralFont = Helpers.GetGeneralFont
local GetGeneralFontOutline = Helpers.GetGeneralFontOutline

-- Register slider references for real-time sync during edit mode
function QUICore:RegisterPowerBarEditModeSliders(barKey, xSlider, ySlider)
    PowerBarEditMode.sliders[barKey] = PowerBarEditMode.sliders[barKey] or {}
    PowerBarEditMode.sliders[barKey].x = xSlider
    PowerBarEditMode.sliders[barKey].y = ySlider
end

-- Update sliders when position changes during edit mode
function QUICore:NotifyPowerBarPositionChanged(barKey, offsetX, offsetY)
    local sliders = PowerBarEditMode.sliders[barKey]
    if sliders then
        if sliders.x and sliders.x.SetValue then
            sliders.x.SetValue(offsetX, true)  -- true = skip onChange callback
        end
        if sliders.y and sliders.y.SetValue then
            sliders.y.SetValue(offsetY, true)
        end
    end

    -- Update info text on overlay if visible
    local bar = (barKey == "primary") and self.powerBar or self.secondaryPowerBar
    if bar and bar.editOverlay and bar.editOverlay.infoText then
        local label = (barKey == "primary") and "Primary" or "Secondary"
        bar.editOverlay.infoText:SetText(string.format("%s  X:%d Y:%d", label, offsetX, offsetY))
    end

    -- Notify unit frames that may be anchored to this power bar
    if _G.QUI_UpdateAnchoredUnitFrames then
        _G.QUI_UpdateAnchoredUnitFrames()
    end
end

--TABLES

local tocVersion = select(4, GetBuildInfo())
local HAS_UNIT_POWER_PERCENT = type(UnitPowerPercent) == "function"

-- Power percent with 12.01 API compatibility
-- API signature changed: old (unit, powerType, scaleTo100) -> new (unit, powerType, usePredicted, curve)
local function GetPowerPct(unit, powerType, usePredicted)
    if (tonumber(tocVersion) or 0) >= 120000 and HAS_UNIT_POWER_PERCENT then
        local ok, pct
        -- 12.01+: Use curve parameter (new API)
        if CurveConstants and CurveConstants.ScaleTo100 then
            ok, pct = pcall(UnitPowerPercent, unit, powerType, usePredicted, CurveConstants.ScaleTo100)
        end
        -- Fallback for older builds
        if not ok or pct == nil then
            ok, pct = pcall(UnitPowerPercent, unit, powerType, usePredicted)
        end
        if ok and pct ~= nil then
            return pct
        end
    end
    -- Manual calculation fallback
    local cur = UnitPower(unit, powerType)
    local max = UnitPowerMax(unit, powerType)
    if cur and max and max > 0 then
        return (cur / max) * 100
    end
    return nil
end

local tickedPowerTypes = {
    [Enum.PowerType.ArcaneCharges] = true,
    [Enum.PowerType.Chi] = true,
    [Enum.PowerType.ComboPoints] = true,
    [Enum.PowerType.Essence] = true,
    [Enum.PowerType.HolyPower] = true,
    [Enum.PowerType.Runes] = true,
    [Enum.PowerType.SoulShards] = true,
}

local fragmentedPowerTypes = {
    [Enum.PowerType.Runes] = true,
}

-- Smooth rune timer update state
local runeUpdateElapsed = 0
local runeUpdateRunning = false

-- Event throttle (16ms = ~60 FPS, smooth updates while managing CPU)
local UPDATE_THROTTLE = 0.016
local lastPrimaryUpdate = 0
local lastSecondaryUpdate = 0

-- Discrete resources that need instant feedback (no throttle)
-- These change infrequently and users expect immediate visual response
local instantFeedbackTypes = {
    [Enum.PowerType.HolyPower] = true,
    [Enum.PowerType.ComboPoints] = true,
    [Enum.PowerType.Chi] = true,
    [Enum.PowerType.Runes] = true,
    [Enum.PowerType.ArcaneCharges] = true,
    [Enum.PowerType.Essence] = true,
    [Enum.PowerType.SoulShards] = true,
}

-- Druid utility forms (show spec resource instead of form resource)
local druidUtilityForms = {
    [0]  = true,  -- Human/Caster
    [2]  = true,  -- Tree of Life (Resto talent)
    [3]  = true,  -- Travel (ground)
    [4]  = true,  -- Aquatic
    [27] = true,  -- Swift Flight Form
    [29] = true,  -- Flight Form
    [36] = true,  -- Treant (cosmetic)
}

-- Druid spec primary resources
local druidSpecResource = {
    [1] = Enum.PowerType.LunarPower,  -- Balance
    [2] = Enum.PowerType.Energy,       -- Feral
    [3] = Enum.PowerType.Rage,         -- Guardian
    [4] = Enum.PowerType.Mana,         -- Restoration
}

-- RESOURCE DETECTION

local function GetPrimaryResource()
    local playerClass = select(2, UnitClass("player"))
    local primaryResources = {
        ["DEATHKNIGHT"] = Enum.PowerType.RunicPower,
        ["DEMONHUNTER"] = Enum.PowerType.Fury,
        ["DRUID"]       = {
            [0]   = Enum.PowerType.Mana,        -- Human/Caster
            [1]   = Enum.PowerType.Energy,      -- Cat
            [3]   = Enum.PowerType.Mana,        -- Travel (ground) - fallback
            [4]   = Enum.PowerType.Mana,        -- Aquatic - fallback
            [5]   = Enum.PowerType.Rage,        -- Bear
            [27]  = Enum.PowerType.Mana,        -- Swift Travel - fallback
            [31]  = Enum.PowerType.LunarPower,  -- Moonkin
        },
        ["EVOKER"]      = Enum.PowerType.Mana,
        ["HUNTER"]      = Enum.PowerType.Focus,
        ["MAGE"]        = Enum.PowerType.Mana,
        ["MONK"]        = {
            [268] = Enum.PowerType.Energy, -- Brewmaster
            [269] = Enum.PowerType.Energy, -- Windwalker
            [270] = Enum.PowerType.Mana, -- Mistweaver
        },
        ["PALADIN"]     = Enum.PowerType.Mana,
        ["PRIEST"]      = {
            [256] = Enum.PowerType.Mana, -- Disciple
            [257] = Enum.PowerType.Mana, -- Holy,
            [258] = Enum.PowerType.Insanity, -- Shadow,
        },
        ["ROGUE"]       = Enum.PowerType.Energy,
        ["SHAMAN"]      = {
            [262] = Enum.PowerType.Maelstrom, -- Elemental
            [263] = Enum.PowerType.Mana, -- Enhancement
            [264] = Enum.PowerType.Mana, -- Restoration
        },
        ["WARLOCK"]     = Enum.PowerType.Mana,
        ["WARRIOR"]     = Enum.PowerType.Rage,
    }

    local spec = GetSpecialization()
    local specID = GetSpecializationInfo(spec)

    -- Druid: spec-aware for utility forms, form-based for combat forms
    if playerClass == "DRUID" then
        local formID = GetShapeshiftFormID()
        -- In utility forms (travel/aquatic/flight), show spec's primary resource
        if druidUtilityForms[formID or 0] then
            local druidSpec = GetSpecialization()
            if druidSpec and druidSpecResource[druidSpec] then
                return druidSpecResource[druidSpec]
            end
        end
        -- Combat forms and caster form: use form-based resource
        return primaryResources[playerClass][formID or 0]
    end

    if type(primaryResources[playerClass]) == "table" then
        return primaryResources[playerClass][specID]
    else 
        return primaryResources[playerClass]
    end
end

local function GetSecondaryResource()
    local playerClass = select(2, UnitClass("player"))
    local secondaryResources = {
        ["DEATHKNIGHT"] = Enum.PowerType.Runes,
        ["DEMONHUNTER"] = {
            [1480] = "SOUL", -- Aldrachi Reaver
        },
        ["DRUID"]       = {
            [1]    = Enum.PowerType.ComboPoints, -- Cat
            [31]   = Enum.PowerType.Mana, -- Moonkin
        },
        ["EVOKER"]      = Enum.PowerType.Essence,
        ["HUNTER"]      = nil,
        ["MAGE"]        = {
            [62]   = Enum.PowerType.ArcaneCharges, -- Arcane
        },
        ["MONK"]        = {
            [268]  = "STAGGER", -- Brewmaster
            [269]  = Enum.PowerType.Chi, -- Windwalker
        },
        ["PALADIN"]     = Enum.PowerType.HolyPower,
        ["PRIEST"]      = {
            [258]  = Enum.PowerType.Mana, -- Shadow
        },
        ["ROGUE"]       = Enum.PowerType.ComboPoints,
        ["SHAMAN"]      = {
            [262]  = Enum.PowerType.Mana, -- Elemental
        },
        ["WARLOCK"]     = Enum.PowerType.SoulShards,
        ["WARRIOR"]     = nil,
    }

    local spec = GetSpecialization()
    local specID = GetSpecializationInfo(spec)

    -- Druid: spec-aware for utility/caster forms, form-based for combat forms
    if playerClass == "DRUID" then
        local formID = GetShapeshiftFormID()
        -- In utility/caster forms, show Mana as secondary if spec primary isn't Mana
        if druidUtilityForms[formID] or formID == nil then
            local druidSpec = GetSpecialization()
            -- Only show Mana secondary for non-Resto specs (Resto primary is already Mana)
            if druidSpec and druidSpec ~= 4 then
                return Enum.PowerType.Mana
            end
            return nil
        end
        -- Combat forms: use form-based secondary
        return secondaryResources[playerClass][formID]
    end

    if type(secondaryResources[playerClass]) == "table" then
        return secondaryResources[playerClass][specID]
    else 
        return secondaryResources[playerClass]
    end
end

local function GetResourceColor(resource)
    -- Check for custom power colors first
    local QUICore = _G.QUI and _G.QUI.QUICore
    local pc = QUICore and QUICore.db and QUICore.db.profile.powerColors

    if pc then
        local customColor = nil

        if resource == "STAGGER" then
            -- Dynamic stagger level colors (Light/Moderate/Heavy)
            if pc.useStaggerLevelColors then
                local stagger = UnitStagger("player") or 0
                local maxHealth = UnitHealthMax("player") or 1
                local staggerPercent = (stagger / maxHealth) * 100

                if staggerPercent >= 60 then
                    customColor = pc.staggerHeavy
                elseif staggerPercent >= 30 then
                    customColor = pc.staggerModerate
                else
                    customColor = pc.staggerLight
                end
            else
                customColor = pc.stagger
            end
        elseif resource == "SOUL" then
            customColor = pc.soulFragments
        elseif resource == Enum.PowerType.SoulShards then
            customColor = pc.soulShards
        elseif resource == Enum.PowerType.Runes then
            -- Check DK spec for spec-specific rune colors
            local _, class = UnitClass("player")
            if class == "DEATHKNIGHT" then
                local spec = GetSpecialization()
                if spec == 1 then customColor = pc.bloodRunes
                elseif spec == 2 then customColor = pc.frostRunes
                elseif spec == 3 then customColor = pc.unholyRunes
                else customColor = pc.runes end
            else
                customColor = pc.runes
            end
        elseif resource == Enum.PowerType.Essence then
            customColor = pc.essence
        elseif resource == Enum.PowerType.ComboPoints then
            customColor = pc.comboPoints
        elseif resource == Enum.PowerType.Chi then
            customColor = pc.chi
        elseif resource == Enum.PowerType.Mana then
            customColor = pc.mana
        elseif resource == Enum.PowerType.Rage then
            customColor = pc.rage
        elseif resource == Enum.PowerType.Energy then
            customColor = pc.energy
        elseif resource == Enum.PowerType.Focus then
            customColor = pc.focus
        elseif resource == Enum.PowerType.RunicPower then
            customColor = pc.runicPower
        elseif resource == Enum.PowerType.Insanity then
            customColor = pc.insanity
        elseif resource == Enum.PowerType.Fury then
            customColor = pc.fury
        elseif resource == Enum.PowerType.Maelstrom then
            customColor = pc.maelstrom
        elseif resource == Enum.PowerType.LunarPower then
            customColor = pc.lunarPower
        elseif resource == Enum.PowerType.HolyPower then
            customColor = pc.holyPower
        elseif resource == Enum.PowerType.ArcaneCharges then
            customColor = pc.arcaneCharges
        end

        if customColor then
            return { r = customColor[1], g = customColor[2], b = customColor[3], a = customColor[4] }
        end
    end

    -- Fallback to Blizzard's power bar colors
    local powerName = nil
    if type(resource) == "number" then
        for name, value in pairs(Enum.PowerType) do
            if value == resource then
                powerName = name:gsub("(%u)", "_%1"):gsub("^_", ""):upper()
                break
            end
        end
    end

    return GetPowerBarColor(powerName)
        or GetPowerBarColor(resource)
        or GetPowerBarColor("MANA")
end

-- DEMON HUNTER SOUL FRAGMENTS BAR HANDLING

local function EnsureDemonHunterSoulBar()
    -- Ensure the Demon Hunter soul fragments bar is always shown and functional
    -- This is needed even when custom unit frames are enabled
    local _, class = UnitClass("player")
    if class ~= "DEMONHUNTER" then return end
    
    local spec = GetSpecialization()
    if spec ~= 3 then return end -- Devourer (spec 3, ID 1480)
    
    local soulBar = _G["DemonHunterSoulFragmentsBar"]
    if soulBar then
        -- Reparent to UIParent if not already (so it's not affected by PlayerFrame)
        if soulBar:GetParent() ~= UIParent then
            if not InCombatLockdown() then
                soulBar:SetParent(UIParent)
            end
        end
        -- Ensure it's shown (even if PlayerFrame is hidden)
        if not soulBar:IsShown() then
            soulBar:Show()
        end
        soulBar:SetAlpha(0)  -- ALWAYS hide visually (fixes Devourer spec)
        -- Unhook any hide scripts that might prevent it from showing
        if not InCombatLockdown() then
            soulBar:SetScript("OnShow", nil)
            -- Set OnHide to immediately show it again
            soulBar:SetScript("OnHide", function(self)
                if not InCombatLockdown() then
                    self:Show()
                    self:SetAlpha(0)
                end
            end)
        end
    end
end

-- GET RESOURCE VALUES

local function GetPrimaryResourceValue(resource, cfg)
    if not resource then return nil, nil, nil, nil end

    local current = UnitPower("player", resource)
    local max = UnitPowerMax("player", resource)
    if max <= 0 then return nil, nil, nil, nil end

    -- Check both old (showManaAsPercent) and new (showPercent) field names
    if (cfg.showPercent or cfg.showManaAsPercent) and resource == Enum.PowerType.Mana then
        if HAS_UNIT_POWER_PERCENT then
            return max, current, GetPowerPct("player", resource, false), "percent"
        else
            return max, current, math.floor((current / max) * 100 + 0.5), "percent"
        end
    else
        return max, current, current, "number"
    end
end

local function GetSecondaryResourceValue(resource)
    if not resource then return nil, nil, nil, nil end

    if resource == "STAGGER" then
        local stagger = UnitStagger("player") or 0
        local maxHealth = UnitHealthMax("player") or 1
        local staggerPercent = (stagger / maxHealth) * 100
        return 100, staggerPercent, staggerPercent, "percent"
    end

    if resource == "SOUL" then
        -- DH souls – get from default Blizzard bar
        local soulBar = _G["DemonHunterSoulFragmentsBar"]
        if not soulBar then return nil, nil, nil, nil end
        
        -- Ensure the bar is shown (even if PlayerFrame is hidden)
        if not soulBar:IsShown() then
            soulBar:Show()
            soulBar:SetAlpha(0)
        end

        local current = soulBar:GetValue()
        local _, max = soulBar:GetMinMaxValues()

        return max, current, current, "number"
    end

    if resource == Enum.PowerType.Runes then
        local current = 0
        local max = UnitPowerMax("player", resource)
        if max <= 0 then return nil, nil, nil, nil end

        for i = 1, max do
            local runeReady = select(3, GetRuneCooldown(i))
            if runeReady then
                current = current + 1
            end
        end

        return max, current, current, "number"
    end

    if resource == Enum.PowerType.SoulShards then
        local _, class = UnitClass("player")
        if class == "WARLOCK" then
            local spec = GetSpecialization()

            -- Destruction: fragments for bar fill, divided by 10 for display
            if spec == 3 then
                local fragments = UnitPower("player", resource, true)        -- 0–50
                local maxFragments = UnitPowerMax("player", resource, true)  -- 50
                if maxFragments <= 0 then return nil, nil, nil, nil end

                -- bar fill = fragments (0-50), display = decimal shards (0.0-5.0)
                return maxFragments, fragments, fragments / 10, "shards"
            end
        end

        -- Any other spec/class that somehow hits SoulShards:
        -- use NORMAL shard count (0–5) for both bar + text
        local current = UnitPower("player", resource)             -- 0–5
        local max     = UnitPowerMax("player", resource)          -- 0–5
        if max <= 0 then return nil, nil, nil, nil end

        -- bar = 0–5, text = 3, 4, 5 etc.
        return max, current, current, "number"
    end

    -- Default case for all other power types (ComboPoints, Chi, HolyPower, etc.)
    local current = UnitPower("player", resource)
    local max = UnitPowerMax("player", resource)
    if max <= 0 then return nil, nil, nil, nil end

    return max, current, current, "number"
end


-- EDIT MODE HELPERS

-- Create a nudge button for fine-tuning position
local function CreatePowerBarNudgeButton(parent, direction, deltaX, deltaY, barKey)
    local btn = CreateFrame("Button", nil, parent)
    btn:SetSize(18, 18)

    -- Background
    local bg = btn:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetTexture("Interface\\Buttons\\WHITE8x8")
    bg:SetVertexColor(0.1, 0.1, 0.1, 0.7)
    btn.bg = bg

    -- Chevron lines
    local line1 = btn:CreateTexture(nil, "ARTWORK")
    line1:SetColorTexture(1, 1, 1, 0.9)
    line1:SetSize(7, 2)
    local line2 = btn:CreateTexture(nil, "ARTWORK")
    line2:SetColorTexture(1, 1, 1, 0.9)
    line2:SetSize(7, 2)

    -- Direction-specific positioning
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

    -- Hover effect
    btn:SetScript("OnEnter", function(self)
        self.line1:SetColorTexture(0.204, 0.827, 0.6, 1)
        self.line2:SetColorTexture(0.204, 0.827, 0.6, 1)
    end)
    btn:SetScript("OnLeave", function(self)
        self.line1:SetColorTexture(1, 1, 1, 0.9)
        self.line2:SetColorTexture(1, 1, 1, 0.9)
    end)

    btn:SetScript("OnClick", function()
        local cfg = (barKey == "primary") and QUICore.db.profile.powerBar or QUICore.db.profile.secondaryPowerBar
        local shift = IsShiftKeyDown()
        local step = shift and 10 or 1
        cfg.offsetX = (cfg.offsetX or 0) + (deltaX * step)
        cfg.offsetY = (cfg.offsetY or 0) + (deltaY * step)

        -- Set to manual positioning mode
        cfg.autoAttach = false
        cfg.useRawPixels = true

        -- Refresh the bar position
        if barKey == "primary" then
            QUICore:UpdatePowerBar()
        else
            QUICore:UpdateSecondaryPowerBar()
        end

        -- Notify options panel
        QUICore:NotifyPowerBarPositionChanged(barKey, cfg.offsetX, cfg.offsetY)
    end)

    return btn
end

-- Create edit mode overlay for a power bar
local function CreatePowerBarEditOverlay(bar, barKey)
    if bar.editOverlay then return bar.editOverlay end

    local overlay = CreateFrame("Frame", nil, bar, "BackdropTemplate")
    overlay:SetAllPoints()
    overlay:SetFrameLevel(bar:GetFrameLevel() + 10)
    overlay:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 2,
    })
    overlay:SetBackdropColor(0.2, 0.8, 1, 0.3)
    overlay:SetBackdropBorderColor(0.2, 0.8, 1, 1)

    -- Nudge buttons
    overlay.nudgeLeft = CreatePowerBarNudgeButton(overlay, "LEFT", -1, 0, barKey)
    overlay.nudgeLeft:SetPoint("RIGHT", overlay, "LEFT", -4, 0)

    overlay.nudgeRight = CreatePowerBarNudgeButton(overlay, "RIGHT", 1, 0, barKey)
    overlay.nudgeRight:SetPoint("LEFT", overlay, "RIGHT", 4, 0)

    overlay.nudgeUp = CreatePowerBarNudgeButton(overlay, "UP", 0, 1, barKey)
    overlay.nudgeUp:SetPoint("BOTTOM", overlay, "TOP", 0, 4)

    overlay.nudgeDown = CreatePowerBarNudgeButton(overlay, "DOWN", 0, -1, barKey)
    overlay.nudgeDown:SetPoint("TOP", overlay, "BOTTOM", 0, -4)

    -- Info text above UP arrow
    local infoText = overlay:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    infoText:SetPoint("BOTTOM", overlay.nudgeUp, "TOP", 0, 2)
    infoText:SetTextColor(0.7, 0.7, 0.7, 1)
    overlay.infoText = infoText

    -- Store barKey for selection manager
    overlay.elementKey = barKey

    -- Hide nudge buttons initially (will show on click/selection)
    overlay.nudgeLeft:Hide()
    overlay.nudgeRight:Hide()
    overlay.nudgeUp:Hide()
    overlay.nudgeDown:Hide()
    infoText:Hide()

    -- Allow clicks to pass through overlay to bar for dragging
    overlay:EnableMouse(false)

    overlay:Hide()
    bar.editOverlay = overlay
    return overlay
end

-- Enable edit mode for power bars
function QUICore:EnablePowerBarEditMode()
    if InCombatLockdown() then return end
    PowerBarEditMode.active = true

    local bars = {
        { bar = self.powerBar, key = "primary", cfg = self.db.profile.powerBar },
        { bar = self.secondaryPowerBar, key = "secondary", cfg = self.db.profile.secondaryPowerBar }
    }

    for _, data in ipairs(bars) do
        local bar = data.bar
        local barKey = data.key
        local cfg = data.cfg

        if bar and cfg and cfg.enabled then
            -- Ensure bar is visible
            bar:Show()

            -- Create and show overlay
            CreatePowerBarEditOverlay(bar, barKey)
            bar.editOverlay:Show()

            -- Update info text with current position
            if bar.editOverlay.infoText then
                local label = (barKey == "primary") and "Primary" or "Secondary"
                local x = cfg.offsetX or 0
                local y = cfg.offsetY or 0
                bar.editOverlay.infoText:SetText(string.format("%s  X:%d Y:%d", label, x, y))
            end

            -- Enable dragging
            bar:SetMovable(true)
            bar:EnableMouse(true)
            bar:RegisterForDrag("LeftButton")

            -- Store barKey on bar for click handler
            bar._editModeBarKey = barKey

            -- Click handler to select this element and show its arrows
            bar:SetScript("OnMouseDown", function(self, button)
                if button == "LeftButton" and PowerBarEditMode.active then
                    if QUICore and QUICore.SelectEditModeElement then
                        QUICore:SelectEditModeElement("powerbar", self._editModeBarKey)
                    end
                end
            end)

            bar:SetScript("OnDragStart", function(self)
                if PowerBarEditMode.active then
                    self:StartMoving()
                    self._isMoving = true

                    -- Update position in real-time during drag
                    self:SetScript("OnUpdate", function(frame)
                        if not frame._isMoving then
                            frame:SetScript("OnUpdate", nil)
                            return
                        end

                        local selfX, selfY = frame:GetCenter()
                        local parentX, parentY = UIParent:GetCenter()
                        if selfX and selfY and parentX and parentY then
                            local offsetX = math.floor(selfX - parentX + 0.5)
                            local offsetY = math.floor(selfY - parentY + 0.5)

                            -- Update database in real-time
                            cfg.offsetX = offsetX
                            cfg.offsetY = offsetY
                            cfg.autoAttach = false  -- User is manually positioning
                            cfg.useRawPixels = true -- Pixel-perfect mode

                            -- Notify options panel
                            QUICore:NotifyPowerBarPositionChanged(barKey, offsetX, offsetY)
                        end
                    end)
                end
            end)

            bar:SetScript("OnDragStop", function(self)
                self:StopMovingOrSizing()
                self._isMoving = false
                self:SetScript("OnUpdate", nil)

                -- Final position save
                local selfX, selfY = self:GetCenter()
                local parentX, parentY = UIParent:GetCenter()
                if selfX and selfY and parentX and parentY then
                    local offsetX = math.floor(selfX - parentX + 0.5)
                    local offsetY = math.floor(selfY - parentY + 0.5)

                    cfg.offsetX = offsetX
                    cfg.offsetY = offsetY
                    cfg.autoAttach = false
                    cfg.useRawPixels = true

                    -- Notify options panel
                    QUICore:NotifyPowerBarPositionChanged(barKey, offsetX, offsetY)
                end
            end)
        end
    end
end

-- Disable edit mode for power bars
function QUICore:DisablePowerBarEditMode()
    PowerBarEditMode.active = false

    -- Clear Edit Mode selection if a power bar was selected
    if self.ClearEditModeSelection then
        self:ClearEditModeSelection()
    end

    local bars = { self.powerBar, self.secondaryPowerBar }

    for _, bar in ipairs(bars) do
        if bar then
            -- Hide overlay
            if bar.editOverlay then
                bar.editOverlay:Hide()
            end

            -- Disable dragging and click handlers
            bar:RegisterForDrag()
            bar:SetScript("OnMouseDown", nil)
            bar:SetScript("OnDragStart", nil)
            bar:SetScript("OnDragStop", nil)
            bar:SetScript("OnUpdate", nil)
        end
    end

    -- Refresh bars to apply saved positions
    self:UpdatePowerBar()
    self:UpdateSecondaryPowerBar()

    -- Defensive: ensure overlays are hidden after updates
    for _, bar in ipairs(bars) do
        if bar and bar.editOverlay then
            bar.editOverlay:Hide()
        end
    end
end


-- PRIMARY POWER BAR

function QUICore:GetPowerBar()
    if self.powerBar then return self.powerBar end

    local cfg = self.db.profile.powerBar
    
    -- Always parent to UIParent so power bar works independently of Essential Cooldowns
    local bar = CreateFrame("Frame", ADDON_NAME .. "PowerBar", UIParent)
    bar:SetFrameStrata("MEDIUM")
    -- Apply HUD layer priority
    local layerPriority = self.db.profile.hudLayering and self.db.profile.hudLayering.primaryPowerBar or 7
    local frameLevel = self:GetHUDFrameLevel(layerPriority)
    bar:SetFrameLevel(frameLevel)
    bar:SetHeight(cfg.useRawPixels and (cfg.height or 6) or Scale(cfg.height or 6))
    local offsetX = cfg.useRawPixels and (cfg.offsetX or 0) or Scale(cfg.offsetX or 0)
    local offsetY = cfg.useRawPixels and (cfg.offsetY or 6) or Scale(cfg.offsetY or 6)
    bar:SetPoint("CENTER", UIParent, "CENTER", offsetX, offsetY)

    -- Calculate width - use configured width or fallback
    local width = cfg.width or 0
    if width <= 0 then
        -- Try to get Essential Cooldowns width if available
        local essentialViewer = _G["EssentialCooldownViewer"]
        if essentialViewer then
            width = essentialViewer.__cdmIconWidth or essentialViewer:GetWidth() or 0
        end
        if width <= 0 then
            width = 200  -- Fallback width
        end
    end

    bar:SetWidth(cfg.useRawPixels and width or Scale(width))


    -- BACKGROUND
    bar.Background = bar:CreateTexture(nil, "BACKGROUND")
    bar.Background:SetAllPoints()
    local bgColor = cfg.bgColor or { 0.15, 0.15, 0.15, 1 }
    bar.Background:SetColorTexture(bgColor[1], bgColor[2], bgColor[3], bgColor[4] or 1)

    -- STATUS BAR
    bar.StatusBar = CreateFrame("StatusBar", nil, bar)
    bar.StatusBar:SetAllPoints()
    local tex = LSM:Fetch("statusbar", GetBarTexture(cfg))
    bar.StatusBar:SetStatusBarTexture(tex)
    bar.StatusBar:SetFrameLevel(bar:GetFrameLevel())


    -- BORDER (pixel-perfect 1px, raw pixels when snapped to CDM)
    local borderSize = cfg.useRawPixels and (cfg.borderSize or 1) or Scale(cfg.borderSize or 1)
    bar.Border = CreateFrame("Frame", nil, bar, "BackdropTemplate")
    bar.Border:SetPoint("TOPLEFT", bar, -borderSize, borderSize)
    bar.Border:SetPoint("BOTTOMRIGHT", bar, borderSize, -borderSize)
    bar.Border:SetBackdrop({
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = borderSize,
    })
    bar.Border:SetBackdropBorderColor(0, 0, 0, 1)

    -- TEXT FRAME (same strata, +2 levels to render above bar content but stay within element's layer band)
    bar.TextFrame = CreateFrame("Frame", nil, bar)
    bar.TextFrame:SetAllPoints(bar)
    bar.TextFrame:SetFrameStrata("MEDIUM")
    bar.TextFrame:SetFrameLevel(frameLevel + 2)

    bar.TextValue = bar.TextFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    bar.TextValue:SetPoint("CENTER", bar.TextFrame, "CENTER", Scale(cfg.textX or 0), Scale(cfg.textY or 0))
    bar.TextValue:SetJustifyH("CENTER")
    bar.TextValue:SetFont(GetGeneralFont(), Scale(cfg.textSize or 12), GetGeneralFontOutline())
    bar.TextValue:SetShadowOffset(0, 0)
    bar.TextValue:SetText("0")

    -- TICKS
    bar.ticks = {}

    bar:Hide()

    self.powerBar = bar
    return bar
end

function QUICore:UpdatePowerBar()
    local cfg = self.db.profile.powerBar
    if not cfg.enabled then
        if self.powerBar then self.powerBar:Hide() end
        return
    end

    local bar = self:GetPowerBar()
    local resource = GetPrimaryResource()

    if not resource then
        bar:Hide()
        return
    end

    -- Update HUD layer priority dynamically
    local layerPriority = self.db.profile.hudLayering and self.db.profile.hudLayering.primaryPowerBar or 7
    local frameLevel = self:GetHUDFrameLevel(layerPriority)
    bar:SetFrameLevel(frameLevel)
    if bar.TextFrame then
        bar.TextFrame:SetFrameLevel(frameLevel + 2)
    end

    -- Determine effective orientation (AUTO/HORIZONTAL/VERTICAL)
    local orientation = cfg.orientation or "AUTO"
    local isVertical = (orientation == "VERTICAL")

    -- For AUTO, check if locked to a CDM viewer and inherit its orientation
    if orientation == "AUTO" then
        if cfg.lockedToEssential then
            local viewer = _G.EssentialCooldownViewer
            isVertical = viewer and viewer.__cdmLayoutDirection == "VERTICAL"
        elseif cfg.lockedToUtility then
            local viewer = _G.UtilityCooldownViewer
            isVertical = viewer and viewer.__cdmLayoutDirection == "VERTICAL"
        end
    end

    -- Apply orientation to StatusBar
    bar.StatusBar:SetOrientation(isVertical and "VERTICAL" or "HORIZONTAL")

    -- Calculate width - use configured width, or fall back to Essential width
    local width = cfg.width
    if not width or width <= 0 then
        -- Try to get Essential Cooldowns width
        local essentialViewer = _G["EssentialCooldownViewer"]
        if essentialViewer then
            width = essentialViewer.__cdmIconWidth
        end
        if not width or width <= 0 then
            width = self.db.profile.ncdm and self.db.profile.ncdm._lastEssentialWidth
        end
        if not width or width <= 0 then
            width = 200 -- absolute fallback
        end
    end
    
    -- Calculate desired position and size
    local offsetX = cfg.useRawPixels and (cfg.offsetX or 0) or Scale(cfg.offsetX or 0)
    local offsetY = cfg.useRawPixels and (cfg.offsetY or 0) or Scale(cfg.offsetY or 0)

    -- Only reposition when offset actually changed (prevents flicker)
    if bar._cachedX ~= offsetX or bar._cachedY ~= offsetY then
        bar:ClearAllPoints()
        bar:SetPoint("CENTER", UIParent, "CENTER", offsetX, offsetY)
        bar._cachedX = offsetX
        bar._cachedY = offsetY
        -- Notify unit frames that may be anchored to this power bar
        if _G.QUI_UpdateAnchoredUnitFrames then
            _G.QUI_UpdateAnchoredUnitFrames()
        end
    end

    -- For vertical bars, swap width and height (width = thickness, height = length)
    local wantedH, wantedW
    if isVertical then
        -- Vertical bar: cfg.width is the bar length (becomes height), cfg.height is thickness (becomes width)
        wantedW = cfg.useRawPixels and (cfg.height or 6) or Scale(cfg.height or 6)
        wantedH = cfg.useRawPixels and width or Scale(width)
    else
        -- Horizontal bar: normal dimensions
        wantedH = cfg.useRawPixels and (cfg.height or 6) or Scale(cfg.height or 6)
        wantedW = cfg.useRawPixels and width or Scale(width)
    end

    -- Only resize when dimensions actually changed (prevents flicker)
    if bar._cachedH ~= wantedH then
        bar:SetHeight(wantedH)
        bar._cachedH = wantedH
    end
    if bar._cachedW ~= wantedW then
        bar:SetWidth(wantedW)
        bar._cachedW = wantedW
    end

    -- Update border size only when changed (prevents flicker)
    local borderSize = cfg.useRawPixels and (cfg.borderSize or 1) or Scale(cfg.borderSize or 1)
    if bar.Border and bar._cachedBorderSize ~= borderSize then
        bar.Border:ClearAllPoints()
        bar.Border:SetPoint("TOPLEFT", bar, -borderSize, borderSize)
        bar.Border:SetPoint("BOTTOMRIGHT", bar, borderSize, -borderSize)
        bar.Border:SetBackdrop({
            edgeFile = "Interface\\Buttons\\WHITE8X8",
            edgeSize = borderSize,
        })
        bar.Border:SetBackdropBorderColor(0, 0, 0, 1)
        bar.Border:SetShown(borderSize > 0)
        bar._cachedBorderSize = borderSize
    end

    -- Update background color
    local bgColor = cfg.bgColor or { 0.15, 0.15, 0.15, 1 }
    if bar.Background then
        bar.Background:SetColorTexture(bgColor[1], bgColor[2], bgColor[3], bgColor[4] or 1)
    end

    -- Update texture only when changed (prevents flicker)
    local tex = LSM:Fetch("statusbar", GetBarTexture(cfg))
    if bar._cachedTex ~= tex then
        bar.StatusBar:SetStatusBarTexture(tex)
        bar._cachedTex = tex
    end

    -- Get resource values
    local max, current, displayValue, valueType = GetPrimaryResourceValue(resource, cfg)
    if not max then
        bar:Hide()
        return
    end

    -- Set bar values
    bar.StatusBar:SetMinMaxValues(0, max)
    bar.StatusBar:SetValue(current)

    -- Set bar color based on checkboxes: Power Type > Class > Custom
    if cfg.usePowerColor then
        -- Power type color (Mana=blue, Rage=red, Energy=yellow, etc.)
        local color = GetResourceColor(resource)
        bar.StatusBar:SetStatusBarColor(color.r, color.g, color.b, color.a or 1)
    elseif cfg.useClassColor then
        -- Class color
        local _, class = UnitClass("player")
        local classColor = RAID_CLASS_COLORS[class]
        if classColor then
            bar.StatusBar:SetStatusBarColor(classColor.r, classColor.g, classColor.b)
        else
            local color = GetResourceColor(resource)
            bar.StatusBar:SetStatusBarColor(color.r, color.g, color.b, color.a or 1)
        end
    elseif cfg.useCustomColor and cfg.customColor then
        -- Custom color override
        local c = cfg.customColor
        bar.StatusBar:SetStatusBarColor(c[1], c[2], c[3], c[4] or 1)
    else
        -- Power type color (default)
        local color = GetResourceColor(resource)
        bar.StatusBar:SetStatusBarColor(color.r, color.g, color.b, color.a or 1)
    end




    -- Update text
    if valueType == "percent" then
        bar.TextValue:SetText(string.format("%.0f%%", displayValue))
    else
        bar.TextValue:SetText(tostring(displayValue))
    end

    bar.TextValue:SetFont(GetGeneralFont(), Scale(cfg.textSize or 12), GetGeneralFontOutline())
    bar.TextValue:SetShadowOffset(0, 0)

    -- Apply text color
    if cfg.textUseClassColor then
        local _, class = UnitClass("player")
        local classColor = RAID_CLASS_COLORS[class]
        if classColor then
            bar.TextValue:SetTextColor(classColor.r, classColor.g, classColor.b, 1)
        end
    else
        local c = cfg.textCustomColor or { 1, 1, 1, 1 }
        bar.TextValue:SetTextColor(c[1], c[2], c[3], c[4] or 1)
    end

    -- Only reposition text when offset changed (prevents flicker)
    local textX = Scale(cfg.textX or 0)
    local textY = Scale(cfg.textY or 0)
    if bar._cachedTextX ~= textX or bar._cachedTextY ~= textY then
        bar.TextValue:ClearAllPoints()
        bar.TextValue:SetPoint("CENTER", bar.TextFrame, "CENTER", textX, textY)
        bar._cachedTextX = textX
        bar._cachedTextY = textY
    end

    -- Show text based on config
    bar.TextFrame:SetShown(cfg.showText ~= false)

    -- Update ticks if this is a ticked power type
    self:UpdatePowerBarTicks(bar, resource, max)

    bar:Show()

    -- Propagate to Secondary bar if it's locked to Primary
    local secondaryCfg = self.db.profile.secondaryPowerBar
    if secondaryCfg and secondaryCfg.lockedToPrimary then
        self:UpdateSecondaryPowerBar()
    end
end

function QUICore:UpdatePowerBarTicks(bar, resource, max)
    local cfg = self.db.profile.powerBar

    -- Hide all ticks first
    for _, tick in ipairs(bar.ticks) do
        tick:Hide()
    end

    if not cfg.showTicks or not tickedPowerTypes[resource] then
        return
    end

    local width = bar:GetWidth()
    local height = bar:GetHeight()
    if width <= 0 or height <= 0 then return end

    -- Determine if bar is vertical
    local orientation = cfg.orientation or "AUTO"
    local isVertical = (orientation == "VERTICAL")
    if orientation == "AUTO" then
        if cfg.lockedToEssential then
            local viewer = _G.EssentialCooldownViewer
            isVertical = viewer and viewer.__cdmLayoutDirection == "VERTICAL"
        elseif cfg.lockedToUtility then
            local viewer = _G.UtilityCooldownViewer
            isVertical = viewer and viewer.__cdmLayoutDirection == "VERTICAL"
        end
    end

    local tickThickness = Scale(cfg.tickThickness or 1)
    local tc = cfg.tickColor or { 0, 0, 0, 1 }
    local needed = max - 1
    for i = 1, needed do
        local tick = bar.ticks[i]
        if not tick then
            tick = bar:CreateTexture(nil, "OVERLAY")
            bar.ticks[i] = tick
        end
        tick:SetColorTexture(tc[1], tc[2], tc[3], tc[4] or 1)
        tick:ClearAllPoints()

        if isVertical then
            -- Vertical bar: ticks go along height (Y axis)
            local y = (i / max) * height
            tick:SetPoint("BOTTOM", bar.StatusBar, "BOTTOM", 0, Scale(y - (tickThickness / 2)))
            tick:SetSize(width, tickThickness)
        else
            -- Horizontal bar: ticks go along width (X axis)
            local x = (i / max) * width
            tick:SetPoint("LEFT", bar.StatusBar, "LEFT", Scale(x - (tickThickness / 2)), 0)
            tick:SetSize(tickThickness, height)
        end
        tick:Show()
    end

    -- Hide extra ticks
    for i = needed + 1, #bar.ticks do
        if bar.ticks[i] then
            bar.ticks[i]:Hide()
        end
    end
end

-- Global callback for NCDM to update locked power bar width and position
_G.QUI_UpdateLockedPowerBar = function()
    local QUICore = _G.QUI and _G.QUI.QUICore
    if not QUICore or not QUICore.db then return end

    local cfg = QUICore.db.profile.powerBar
    if not cfg.enabled or not cfg.lockedToEssential then return end

    local essentialViewer = _G.EssentialCooldownViewer
    if not essentialViewer or not essentialViewer:IsShown() then return end

    local isVerticalCDM = essentialViewer.__cdmLayoutDirection == "VERTICAL"

    local newWidth, newOffsetX, newOffsetY
    local barBorderSize = cfg.borderSize or 1

    if isVerticalCDM then
        -- Vertical CDM: bar goes to the RIGHT, length matches total height
        local totalHeight = essentialViewer.__cdmTotalHeight or essentialViewer:GetHeight()
        if not totalHeight or totalHeight <= 0 then return end

        -- Width (bar length) = total CDM height + borders
        local topBottomBorderSize = essentialViewer.__cdmRow1BorderSize or 0
        local targetWidth = totalHeight + (2 * topBottomBorderSize) - (2 * barBorderSize)
        newWidth = math.floor(targetWidth + 0.5)

        -- Position to the right of Essential
        local essentialCenterX, essentialCenterY = essentialViewer:GetCenter()
        local screenCenterX, screenCenterY = UIParent:GetCenter()
        local totalWidth = essentialViewer.__cdmIconWidth or essentialViewer:GetWidth()
        local barThickness = cfg.height or 6

        if essentialCenterX and essentialCenterY and screenCenterX and screenCenterY then
            -- CDM's visual right edge (GetWidth includes visual bounds)
            local rightColBorderSize = essentialViewer.__cdmBottomRowBorderSize or 0
            local cdmVisualRight = essentialCenterX + (totalWidth / 2) + rightColBorderSize

            -- Power bar center X = visual right + bar thickness/2 + border
            local powerBarCenterX = cdmVisualRight + (barThickness / 2) + barBorderSize

            newOffsetX = math.floor(powerBarCenterX - screenCenterX + 0.5) - 4
            newOffsetY = math.floor(essentialCenterY - screenCenterY + 0.5)
        end
    else
        -- Horizontal CDM: bar below, width matches row width (current behavior)
        local rowWidth = essentialViewer.__cdmRow1Width or essentialViewer.__cdmIconWidth
        if not rowWidth or rowWidth <= 0 then return end

        local row1BorderSize = essentialViewer.__cdmRow1BorderSize or 0
        local targetWidth = rowWidth + (2 * row1BorderSize) - (2 * barBorderSize)
        newWidth = math.floor(targetWidth + 0.5)

        -- Center horizontally with Essential
        local rawCenterX = essentialViewer:GetCenter()
        local rawScreenX = UIParent:GetCenter()
        if rawCenterX and rawScreenX then
            local essentialCenterX = math.floor(rawCenterX + 0.5)
            local screenCenterX = math.floor(rawScreenX + 0.5)
            newOffsetX = essentialCenterX - screenCenterX
        end
    end

    -- Update if values changed
    local needsUpdate = false
    if newWidth and cfg.width ~= newWidth then
        cfg.width = newWidth
        needsUpdate = true
    end
    if newOffsetX and cfg.offsetX ~= newOffsetX then
        cfg.offsetX = newOffsetX
        needsUpdate = true
    end
    if newOffsetY and cfg.offsetY ~= newOffsetY then
        cfg.offsetY = newOffsetY
        needsUpdate = true
    end

    if needsUpdate then
        QUICore:UpdatePowerBar()
    end
end

-- Global callback for NCDM to update power bar locked to Utility
_G.QUI_UpdateLockedPowerBarToUtility = function()
    local QUICore = _G.QUI and _G.QUI.QUICore
    if not QUICore or not QUICore.db then return end

    local cfg = QUICore.db.profile.powerBar
    if not cfg.enabled or not cfg.lockedToUtility then return end

    local utilityViewer = _G.UtilityCooldownViewer
    if not utilityViewer or not utilityViewer:IsShown() then return end

    local isVerticalCDM = utilityViewer.__cdmLayoutDirection == "VERTICAL"

    local newWidth, newOffsetX, newOffsetY
    local barBorderSize = cfg.borderSize or 1

    if isVerticalCDM then
        -- Vertical CDM: bar goes to the LEFT (Utility is typically on right side of screen)
        local totalHeight = utilityViewer.__cdmTotalHeight or utilityViewer:GetHeight()
        if not totalHeight or totalHeight <= 0 then return end

        -- Width (bar length) = total CDM height
        local row1BorderSize = utilityViewer.__cdmRow1BorderSize or 0
        local targetWidth = totalHeight + (2 * row1BorderSize) - (2 * barBorderSize)
        newWidth = math.floor(targetWidth + 0.5)

        -- Position to the LEFT of Utility
        local utilityCenterX, utilityCenterY = utilityViewer:GetCenter()
        local screenCenterX, screenCenterY = UIParent:GetCenter()
        local totalWidth = utilityViewer.__cdmIconWidth or utilityViewer:GetWidth()
        local barThickness = cfg.height or 6

        if utilityCenterX and utilityCenterY and screenCenterX and screenCenterY then
            -- CDM's visual left edge (GetWidth includes visual bounds)
            local row1BorderSizePos = utilityViewer.__cdmRow1BorderSize or 0
            local cdmVisualLeft = utilityCenterX - (totalWidth / 2) - row1BorderSizePos

            -- Power bar center X = visual left - bar thickness/2 - border
            local powerBarCenterX = cdmVisualLeft - (barThickness / 2) - barBorderSize

            newOffsetX = math.floor(powerBarCenterX - screenCenterX + 0.5) + 1
            newOffsetY = math.floor(utilityCenterY - screenCenterY + 0.5)
        end
    else
        -- Horizontal CDM: bar below, width matches row width (current behavior)
        local rowWidth = utilityViewer.__cdmBottomRowWidth or utilityViewer.__cdmIconWidth
        if not rowWidth or rowWidth <= 0 then return end

        local bottomRowBorderSize = utilityViewer.__cdmBottomRowBorderSize or 0
        local targetWidth = rowWidth + (2 * bottomRowBorderSize) - (2 * barBorderSize)
        newWidth = math.floor(targetWidth + 0.5)

        -- Center horizontally with Utility
        local rawCenterX = utilityViewer:GetCenter()
        local rawScreenX = UIParent:GetCenter()
        if rawCenterX and rawScreenX then
            local utilityCenterX = math.floor(rawCenterX + 0.5)
            local screenCenterX = math.floor(rawScreenX + 0.5)
            newOffsetX = utilityCenterX - screenCenterX
        end
    end

    -- Update if values changed
    local needsUpdate = false
    if newWidth and cfg.width ~= newWidth then
        cfg.width = newWidth
        needsUpdate = true
    end
    if newOffsetX and cfg.offsetX ~= newOffsetX then
        cfg.offsetX = newOffsetX
        needsUpdate = true
    end
    if newOffsetY and cfg.offsetY ~= newOffsetY then
        cfg.offsetY = newOffsetY
        needsUpdate = true
    end

    if needsUpdate then
        QUICore:UpdatePowerBar()
    end
end

-- Cache for Primary bar dimensions (used when Secondary is locked to Primary but Primary is hidden)
local cachedPrimaryDimensions = {
    centerX = nil,
    centerY = nil,
    width = nil,
    height = nil,
    borderSize = nil,
}

-- Global callback for NCDM to update SECONDARY power bar locked to Essential
_G.QUI_UpdateLockedSecondaryPowerBar = function()
    local QUICore = _G.QUI and _G.QUI.QUICore
    if not QUICore or not QUICore.db then return end

    local cfg = QUICore.db.profile.secondaryPowerBar
    if not cfg.enabled or not cfg.lockedToEssential then return end

    local essentialViewer = _G.EssentialCooldownViewer
    if not essentialViewer or not essentialViewer:IsShown() then return end

    local isVerticalCDM = essentialViewer.__cdmLayoutDirection == "VERTICAL"

    local newWidth, newOffsetX, newOffsetY
    local barBorderSize = cfg.borderSize or 1
    local barThickness = cfg.height or 8

    if isVerticalCDM then
        -- Vertical CDM: bar goes to the RIGHT, length matches total height
        local totalHeight = essentialViewer.__cdmTotalHeight or essentialViewer:GetHeight()
        if not totalHeight or totalHeight <= 0 then return end

        -- Width (bar length) = total CDM height + borders
        local topBottomBorderSize = essentialViewer.__cdmRow1BorderSize or 0
        local targetWidth = totalHeight + (2 * topBottomBorderSize) - (2 * barBorderSize)
        newWidth = math.floor(targetWidth + 0.5)

        -- Position to the right of Essential
        local essentialCenterX, essentialCenterY = essentialViewer:GetCenter()
        local screenCenterX, screenCenterY = UIParent:GetCenter()
        local totalWidth = essentialViewer.__cdmIconWidth or essentialViewer:GetWidth()

        if essentialCenterX and essentialCenterY and screenCenterX and screenCenterY then
            -- CDM's visual right edge (GetWidth includes visual bounds)
            local rightColBorderSize = essentialViewer.__cdmBottomRowBorderSize or 0
            local cdmVisualRight = essentialCenterX + (totalWidth / 2) + rightColBorderSize

            -- Power bar center X = visual right + bar thickness/2 + border
            local powerBarCenterX = cdmVisualRight + (barThickness / 2) + barBorderSize

            newOffsetX = math.floor(powerBarCenterX - screenCenterX + 0.5) - 4
            newOffsetY = math.floor(essentialCenterY - screenCenterY + 0.5)
        end
    else
        -- Horizontal CDM: bar above, width matches row width (current behavior)
        local rowWidth = essentialViewer.__cdmRow1Width or essentialViewer.__cdmIconWidth
        if not rowWidth or rowWidth <= 0 then return end

        local row1BorderSize = essentialViewer.__cdmRow1BorderSize or 0
        local targetWidth = rowWidth + (2 * row1BorderSize) - (2 * barBorderSize)
        newWidth = math.floor(targetWidth + 0.5)

        local rawCenterX, rawCenterY = essentialViewer:GetCenter()
        local rawScreenX, rawScreenY = UIParent:GetCenter()

        if rawCenterX and rawCenterY and rawScreenX and rawScreenY then
            local essentialCenterX = math.floor(rawCenterX + 0.5)
            local essentialCenterY = math.floor(rawCenterY + 0.5)
            local screenCenterX = math.floor(rawScreenX + 0.5)
            local screenCenterY = math.floor(rawScreenY + 0.5)
            newOffsetX = essentialCenterX - screenCenterX
            -- Y offset (position above Essential CDM)
            local totalHeight = essentialViewer.__cdmTotalHeight or essentialViewer:GetHeight() or 100
            local cdmVisualTop = essentialCenterY + (totalHeight / 2) + row1BorderSize
            local powerBarCenterY = cdmVisualTop + (barThickness / 2) + barBorderSize
            newOffsetY = math.floor(powerBarCenterY - screenCenterY + 0.5) - 1
        end
    end

    -- Update if values changed
    local needsUpdate = false
    if newWidth and cfg.width ~= newWidth then
        cfg.width = newWidth
        needsUpdate = true
    end
    if newOffsetX and cfg.lockedBaseX ~= newOffsetX then
        cfg.lockedBaseX = newOffsetX
        needsUpdate = true
    end
    if newOffsetY and cfg.lockedBaseY ~= newOffsetY then
        cfg.lockedBaseY = newOffsetY
        needsUpdate = true
    end

    if needsUpdate then
        QUICore:UpdateSecondaryPowerBar()
    end
end

-- Global callback for NCDM to update SECONDARY power bar locked to Utility
_G.QUI_UpdateLockedSecondaryPowerBarToUtility = function()
    local QUICore = _G.QUI and _G.QUI.QUICore
    if not QUICore or not QUICore.db then return end

    local cfg = QUICore.db.profile.secondaryPowerBar
    if not cfg.enabled or not cfg.lockedToUtility then return end

    local utilityViewer = _G.UtilityCooldownViewer
    if not utilityViewer or not utilityViewer:IsShown() then return end

    local isVerticalCDM = utilityViewer.__cdmLayoutDirection == "VERTICAL"

    local newWidth, newOffsetX, newOffsetY
    local barBorderSize = cfg.borderSize or 1
    local barThickness = cfg.height or 8

    if isVerticalCDM then
        -- Vertical CDM: bar goes to the LEFT (Utility is typically on right side of screen)
        local totalHeight = utilityViewer.__cdmTotalHeight or utilityViewer:GetHeight()
        if not totalHeight or totalHeight <= 0 then return end

        -- Width (bar length) = total CDM height
        local row1BorderSize = utilityViewer.__cdmRow1BorderSize or 0
        local targetWidth = totalHeight + (2 * row1BorderSize) - (2 * barBorderSize)
        newWidth = math.floor(targetWidth + 0.5)

        -- Position to the LEFT of Utility
        local utilityCenterX, utilityCenterY = utilityViewer:GetCenter()
        local screenCenterX, screenCenterY = UIParent:GetCenter()
        local totalWidth = utilityViewer.__cdmIconWidth or utilityViewer:GetWidth()

        if utilityCenterX and utilityCenterY and screenCenterX and screenCenterY then
            -- CDM's visual left edge (GetWidth includes visual bounds)
            local cdmVisualLeft = utilityCenterX - (totalWidth / 2)

            -- Power bar center X = visual left - bar thickness/2
            local powerBarCenterX = cdmVisualLeft - (barThickness / 2)

            newOffsetX = math.floor(powerBarCenterX - screenCenterX + 0.5)
            newOffsetY = math.floor(utilityCenterY - screenCenterY + 0.5)
        end
    else
        -- Horizontal CDM: bar below, width matches row width (current behavior)
        local rowWidth = utilityViewer.__cdmBottomRowWidth or utilityViewer.__cdmIconWidth
        if not rowWidth or rowWidth <= 0 then return end

        local bottomRowBorderSize = utilityViewer.__cdmBottomRowBorderSize or 0
        local targetWidth = rowWidth + (2 * bottomRowBorderSize) - (2 * barBorderSize)
        newWidth = math.floor(targetWidth + 0.5)

        local rawCenterX, rawCenterY = utilityViewer:GetCenter()
        local rawScreenX, rawScreenY = UIParent:GetCenter()

        if rawCenterX and rawCenterY and rawScreenX and rawScreenY then
            local utilityCenterX = math.floor(rawCenterX + 0.5)
            local utilityCenterY = math.floor(rawCenterY + 0.5)
            local screenCenterX = math.floor(rawScreenX + 0.5)
            local screenCenterY = math.floor(rawScreenY + 0.5)
            newOffsetX = utilityCenterX - screenCenterX
            -- Y offset (position below Utility CDM)
            local totalHeight = utilityViewer.__cdmTotalHeight or utilityViewer:GetHeight() or 100
            local cdmVisualBottom = utilityCenterY - (totalHeight / 2) - bottomRowBorderSize
            local powerBarCenterY = cdmVisualBottom - (barThickness / 2) - barBorderSize
            newOffsetY = math.floor(powerBarCenterY - screenCenterY + 0.5) + 1
        end
    end

    -- Update if values changed
    local needsUpdate = false
    if newWidth and cfg.width ~= newWidth then
        cfg.width = newWidth
        needsUpdate = true
    end
    if newOffsetX and cfg.lockedBaseX ~= newOffsetX then
        cfg.lockedBaseX = newOffsetX
        needsUpdate = true
    end
    if newOffsetY and cfg.lockedBaseY ~= newOffsetY then
        cfg.lockedBaseY = newOffsetY
        needsUpdate = true
    end

    if needsUpdate then
        QUICore:UpdateSecondaryPowerBar()
    end
end

-- SECONDARY POWER BAR

function QUICore:GetSecondaryPowerBar()
    if self.secondaryPowerBar then return self.secondaryPowerBar end

    local cfg = self.db.profile.secondaryPowerBar

    -- Always parent to UIParent so secondary power bar works independently
    local bar = CreateFrame("Frame", ADDON_NAME .. "SecondaryPowerBar", UIParent)
    bar:SetFrameStrata("MEDIUM")
    -- Apply HUD layer priority
    local layerPriority = self.db.profile.hudLayering and self.db.profile.hudLayering.secondaryPowerBar or 6
    local frameLevel = self:GetHUDFrameLevel(layerPriority)
    bar:SetFrameLevel(frameLevel)
    bar:SetHeight(Scale(cfg.height or 4))
    bar:SetPoint("CENTER", UIParent, "CENTER", Scale(cfg.offsetX or 0), Scale(cfg.offsetY or 12))

    -- Calculate width - use configured width or fallback
    local width = cfg.width or 0
    if width <= 0 then
        -- Try to get Essential Cooldowns width if available
        local essentialViewer = _G["EssentialCooldownViewer"]
        if essentialViewer then
            width = essentialViewer.__cdmIconWidth or essentialViewer:GetWidth() or 0
        end
        if width <= 0 then
            width = 200  -- Fallback width
        end
    end

    bar:SetWidth(Scale(width))

    -- BACKGROUND
    bar.Background = bar:CreateTexture(nil, "BACKGROUND")
    bar.Background:SetAllPoints()
    local bgColor = cfg.bgColor or { 0.15, 0.15, 0.15, 1 }
    bar.Background:SetColorTexture(bgColor[1], bgColor[2], bgColor[3], bgColor[4] or 1)

    -- STATUS BAR (for non-fragmented resources)
    bar.StatusBar = CreateFrame("StatusBar", nil, bar)
    bar.StatusBar:SetAllPoints()
    local tex = LSM:Fetch("statusbar", GetBarTexture(cfg))
    bar.StatusBar:SetStatusBarTexture(tex)
    bar.StatusBar:SetFrameLevel(bar:GetFrameLevel())


    -- BORDER (pixel-perfect)
    local borderSize = Scale(cfg.borderSize or 1)
    bar.Border = CreateFrame("Frame", nil, bar, "BackdropTemplate")
    bar.Border:SetPoint("TOPLEFT", bar, -borderSize, borderSize)
    bar.Border:SetPoint("BOTTOMRIGHT", bar, borderSize, -borderSize)
    bar.Border:SetBackdrop({
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = borderSize,
    })
    bar.Border:SetBackdropBorderColor(0, 0, 0, 1)

    -- TEXT FRAME (same strata, +2 levels to render above bar content but stay within element's layer band)
    bar.TextFrame = CreateFrame("Frame", nil, bar)
    bar.TextFrame:SetAllPoints(bar)
    bar.TextFrame:SetFrameStrata("MEDIUM")
    bar.TextFrame:SetFrameLevel(frameLevel + 2)

    bar.TextValue = bar.TextFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    bar.TextValue:SetPoint("CENTER", bar.TextFrame, "CENTER", Scale(cfg.textX or 0), Scale(cfg.textY or 0))
    bar.TextValue:SetJustifyH("CENTER")
    bar.TextValue:SetFont(GetGeneralFont(), Scale(cfg.textSize or 12), GetGeneralFontOutline())
    bar.TextValue:SetShadowOffset(0, 0)
    bar.TextValue:SetText("0")

    -- Fake decimal for Destro shards
    bar.SoulShardDecimal = bar.TextFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    bar.SoulShardDecimal:SetFont(GetGeneralFont(), Scale(cfg.textSize or 12), GetGeneralFontOutline())
    bar.SoulShardDecimal:SetShadowOffset(0, 0)
    bar.SoulShardDecimal:SetText(".")
    bar.SoulShardDecimal:Hide()


    -- FRAGMENTED POWER BARS (for Runes)
    bar.FragmentedPowerBars = {}
    bar.FragmentedPowerBarTexts = {}

    -- TICKS
    bar.ticks = {}

    bar:Hide()

    self.secondaryPowerBar = bar
    return bar
end

function QUICore:CreateFragmentedPowerBars(bar, resource, isVertical)
    local cfg = self.db.profile.secondaryPowerBar
    local maxPower = UnitPowerMax("player", resource)

    for i = 1, maxPower do
        if not bar.FragmentedPowerBars[i] then
            local fragmentBar = CreateFrame("StatusBar", nil, bar)
            local tex = LSM:Fetch("statusbar", GetBarTexture(cfg))
            fragmentBar:SetStatusBarTexture(tex)
            fragmentBar:GetStatusBarTexture()
            fragmentBar:SetOrientation(isVertical and "VERTICAL" or "HORIZONTAL")
            fragmentBar:SetFrameLevel(bar.StatusBar:GetFrameLevel())
            bar.FragmentedPowerBars[i] = fragmentBar
            
            -- Create text for reload time display (pixel-perfect)
            local text = fragmentBar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            text:SetPoint("CENTER", fragmentBar, "CENTER", Scale(cfg.runeTimerTextX or 0), Scale(cfg.runeTimerTextY or 0))
            text:SetJustifyH("CENTER")
            text:SetFont(GetGeneralFont(), Scale(cfg.runeTimerTextSize or 10), GetGeneralFontOutline())
            text:SetShadowOffset(0, 0)
            text:SetText("")
            bar.FragmentedPowerBarTexts[i] = text
        end
    end
end

function QUICore:UpdateFragmentedPowerDisplay(bar, resource, isVertical)
    local cfg = self.db.profile.secondaryPowerBar
    local maxPower = UnitPowerMax("player", resource)
    if maxPower <= 0 then return end

    local barWidth = bar:GetWidth()
    local barHeight = bar:GetHeight()

    -- Calculate fragment dimensions based on orientation
    local fragmentedBarWidth, fragmentedBarHeight
    if isVertical then
        fragmentedBarHeight = barHeight / maxPower
        fragmentedBarWidth = barWidth
    else
        fragmentedBarWidth = barWidth / maxPower
        fragmentedBarHeight = barHeight
    end
    
    -- Hide the main status bar fill (we display bars representing one (1) unit of resource each)
    bar.StatusBar:SetAlpha(0)

    -- Update texture for all fragmented bars
    local tex = LSM:Fetch("statusbar", GetDefaultTexture())
    for i = 1, maxPower do
        if bar.FragmentedPowerBars[i] then
            bar.FragmentedPowerBars[i]:SetStatusBarTexture(tex)
        end
    end

    -- Determine color based on checkboxes: Power Type > Class > Custom
    local color

    if cfg.usePowerColor then
        -- Power type color
        color = GetResourceColor(resource)
    elseif cfg.useClassColor then
        local _, class = UnitClass("player")
        local classColor = RAID_CLASS_COLORS[class]
        if classColor then
            color = { r = classColor.r, g = classColor.g, b = classColor.b }
        else
            color = GetResourceColor(resource)
        end
    elseif cfg.useCustomColor and cfg.customColor then
        -- Custom color override
        local c = cfg.customColor
        color = { r = c[1], g = c[2], b = c[3], a = c[4] or 1 }
    else
        -- Power type color (default)
        color = GetResourceColor(resource)
    end


    if resource == Enum.PowerType.Runes then
        -- Collect rune states: ready and recharging
        local readyList = {}
        local cdList = {}
        local now = GetTime()
        
        for i = 1, maxPower do
            local start, duration, runeReady = GetRuneCooldown(i)
            if runeReady then
                table.insert(readyList, { index = i })
            else
                if start and duration and duration > 0 then
                    local elapsed = now - start
                    local remaining = math.max(0, duration - elapsed)
                    local frac = math.max(0, math.min(1, elapsed / duration))
                    table.insert(cdList, { index = i, remaining = remaining, frac = frac })
                else
                    table.insert(cdList, { index = i, remaining = math.huge, frac = 0 })
                end
            end
        end

        -- Sort cdList by ascending remaining time
        table.sort(cdList, function(a, b)
            return a.remaining < b.remaining
        end)

        -- Build final display order: ready runes first, then CD runes sorted
        local displayOrder = {}
        local readyLookup = {}
        local cdLookup = {}
        
        for _, v in ipairs(readyList) do
            table.insert(displayOrder, v.index)
            readyLookup[v.index] = true
        end
        
        for _, v in ipairs(cdList) do
            table.insert(displayOrder, v.index)
            cdLookup[v.index] = v
        end

        for pos = 1, #displayOrder do
            local runeIndex = displayOrder[pos]
            local runeFrame = bar.FragmentedPowerBars[runeIndex]
            local runeText = bar.FragmentedPowerBarTexts[runeIndex]

            if runeFrame then
                runeFrame:ClearAllPoints()
                runeFrame:SetSize(fragmentedBarWidth, fragmentedBarHeight)
                if isVertical then
                    runeFrame:SetPoint("BOTTOM", bar, "BOTTOM", 0, (pos - 1) * fragmentedBarHeight)
                else
                    runeFrame:SetPoint("LEFT", bar, "LEFT", (pos - 1) * fragmentedBarWidth, 0)
                end

                -- Update rune timer text position and font size
                if runeText then
                    runeText:ClearAllPoints()
                    runeText:SetPoint("CENTER", runeFrame, "CENTER", Scale(cfg.runeTimerTextX or 0), Scale(cfg.runeTimerTextY or 0))
                    runeText:SetFont(GetGeneralFont(), Scale(cfg.runeTimerTextSize or 10), GetGeneralFontOutline())
                    runeText:SetShadowOffset(0, 0)
                end

                if readyLookup[runeIndex] then
                    -- Ready rune
                    runeFrame:SetMinMaxValues(0, 1)
                    runeFrame:SetValue(1)
                    runeText:SetText("")
                    runeFrame:SetStatusBarColor(color.r, color.g, color.b)
                else
                    -- Recharging rune
                    local cdInfo = cdLookup[runeIndex]
                    if cdInfo then
                        runeFrame:SetMinMaxValues(0, 1)
                        runeFrame:SetValue(cdInfo.frac)
                        
                        -- Only show timer text if enabled
                        if cfg.showFragmentedPowerBarText ~= false then
                            runeText:SetText(string.format("%.1f", math.max(0, cdInfo.remaining)))
                        else
                            runeText:SetText("")
                        end
                        
                        runeFrame:SetStatusBarColor(color.r * 0.5, color.g * 0.5, color.b * 0.5)
                    else
                        runeFrame:SetMinMaxValues(0, 1)
                        runeFrame:SetValue(0)
                        runeText:SetText("")
                        runeFrame:SetStatusBarColor(color.r * 0.5, color.g * 0.5, color.b * 0.5)
                    end
                end

                runeFrame:Show()
            end
        end

        -- Hide any extra rune frames beyond current maxPower
        for i = maxPower + 1, #bar.FragmentedPowerBars do
            if bar.FragmentedPowerBars[i] then
                bar.FragmentedPowerBars[i]:Hide()
                if bar.FragmentedPowerBarTexts[i] then
                    bar.FragmentedPowerBarTexts[i]:SetText("")
                end
            end
        end
        
        -- Add ticks between rune segments if enabled (pixel-perfect)
        if cfg.showTicks then
            local tickThickness = Scale(cfg.tickThickness or 1)
            local tc = cfg.tickColor or { 0, 0, 0, 1 }
            for i = 1, maxPower - 1 do
                local tick = bar.ticks[i]
                if not tick then
                    tick = bar:CreateTexture(nil, "OVERLAY")
                    bar.ticks[i] = tick
                end
                tick:SetColorTexture(tc[1], tc[2], tc[3], tc[4] or 1)

                tick:ClearAllPoints()
                if isVertical then
                    local y = i * fragmentedBarHeight
                    tick:SetPoint("BOTTOM", bar, "BOTTOM", 0, Scale(y - (tickThickness / 2)))
                    tick:SetSize(barWidth, tickThickness)
                else
                    local x = i * fragmentedBarWidth
                    tick:SetPoint("LEFT", bar, "LEFT", Scale(x - (tickThickness / 2)), 0)
                    tick:SetSize(tickThickness, barHeight)
                end
                tick:Show()
            end
            
            -- Hide extra ticks
            for i = maxPower, #bar.ticks do
                if bar.ticks[i] then
                    bar.ticks[i]:Hide()
                end
            end
        else
            -- Hide all ticks if disabled
            for _, tick in ipairs(bar.ticks) do
                tick:Hide()
            end
        end
    end
end

-- Smooth rune timer update (runs at 20 FPS when runes are on cooldown)
local function RuneTimerOnUpdate(bar, delta)
    runeUpdateElapsed = runeUpdateElapsed + delta
    if runeUpdateElapsed < 0.05 then return end  -- 20 FPS throttle (smoother cooldown animation)
    runeUpdateElapsed = 0

    -- Quick update: refresh text/fill without full layout recalc
    local now = GetTime()
    local anyOnCooldown = false

    for i = 1, 6 do
        local runeFrame = bar.FragmentedPowerBars and bar.FragmentedPowerBars[i]
        local runeText = bar.FragmentedPowerBarTexts and bar.FragmentedPowerBarTexts[i]
        if runeFrame and runeFrame:IsShown() then
            local start, duration, runeReady = GetRuneCooldown(i)
            if not runeReady and start and duration and duration > 0 then
                anyOnCooldown = true
                local remaining = math.max(0, duration - (now - start))
                local frac = math.max(0, math.min(1, (now - start) / duration))
                runeFrame:SetValue(frac)
                if runeText then
                    local cfg = QUICore.db.profile.secondaryPowerBar
                    if cfg.showFragmentedPowerBarText ~= false then
                        runeText:SetText(string.format("%.1f", remaining))
                    else
                        runeText:SetText("")
                    end
                end
            end
        end
    end

    -- Auto-disable when all runes are ready
    if not anyOnCooldown then
        bar:SetScript("OnUpdate", nil)
        runeUpdateRunning = false
    end
end

function QUICore:UpdateSecondaryPowerBarTicks(bar, resource, max)
    local cfg = self.db.profile.secondaryPowerBar

    -- Hide all ticks first
    for _, tick in ipairs(bar.ticks) do
        tick:Hide()
    end

    -- Don't show ticks if disabled, not a ticked power type, or if it's fragmented
    if not cfg.showTicks or not tickedPowerTypes[resource] or fragmentedPowerTypes[resource] then
        return
    end

    local width  = bar:GetWidth()
    local height = bar:GetHeight()
    if width <= 0 or height <= 0 then return end

    -- Determine if bar is vertical
    local orientation = cfg.orientation or "AUTO"
    local isVertical = (orientation == "VERTICAL")
    if orientation == "AUTO" then
        if cfg.lockedToEssential then
            local viewer = _G.EssentialCooldownViewer
            isVertical = viewer and viewer.__cdmLayoutDirection == "VERTICAL"
        elseif cfg.lockedToUtility then
            local viewer = _G.UtilityCooldownViewer
            isVertical = viewer and viewer.__cdmLayoutDirection == "VERTICAL"
        elseif cfg.lockedToPrimary then
            local primaryCfg = self.db.profile.powerBar
            if primaryCfg then
                if primaryCfg.lockedToEssential then
                    local viewer = _G.EssentialCooldownViewer
                    isVertical = viewer and viewer.__cdmLayoutDirection == "VERTICAL"
                elseif primaryCfg.lockedToUtility then
                    local viewer = _G.UtilityCooldownViewer
                    isVertical = viewer and viewer.__cdmLayoutDirection == "VERTICAL"
                end
            end
        end
    end

    -- For Soul Shards, use the display max (not the internal fractional max)
    local displayMax = max
    if resource == Enum.PowerType.SoulShards then
        displayMax = UnitPowerMax("player", resource) -- non-fractional max (usually 5)
    end

    local tickThickness = Scale(cfg.tickThickness or 1)
    local tc = cfg.tickColor or { 0, 0, 0, 1 }
    local needed = displayMax - 1
    for i = 1, needed do
        local tick = bar.ticks[i]
        if not tick then
            tick = bar:CreateTexture(nil, "OVERLAY")
            bar.ticks[i] = tick
        end
        tick:SetColorTexture(tc[1], tc[2], tc[3], tc[4] or 1)
        tick:ClearAllPoints()

        if isVertical then
            -- Vertical bar: ticks go along height (Y axis)
            local y = (i / displayMax) * height
            tick:SetPoint("BOTTOM", bar.StatusBar, "BOTTOM", 0, Scale(y - (tickThickness / 2)))
            tick:SetSize(width, tickThickness)
        else
            -- Horizontal bar: ticks go along width (X axis)
            local x = (i / displayMax) * width
            tick:SetPoint("LEFT", bar.StatusBar, "LEFT", Scale(x - (tickThickness / 2)), 0)
            tick:SetSize(tickThickness, height)
        end
        tick:Show()
    end

    -- Hide extra ticks
    for i = needed + 1, #bar.ticks do
        if bar.ticks[i] then
            bar.ticks[i]:Hide()
        end
    end
end


function QUICore:UpdateSecondaryPowerBar()
    local cfg = self.db.profile.secondaryPowerBar
    if not cfg.enabled then
        if self.secondaryPowerBar then self.secondaryPowerBar:Hide() end
        return
    end

    local bar = self:GetSecondaryPowerBar()
    local resource = GetSecondaryResource()

    if not resource then
        bar:Hide()
        return
    end

    -- Update HUD layer priority dynamically
    local layerPriority = self.db.profile.hudLayering and self.db.profile.hudLayering.secondaryPowerBar or 6
    local frameLevel = self:GetHUDFrameLevel(layerPriority)
    bar:SetFrameLevel(frameLevel)
    if bar.TextFrame then
        bar.TextFrame:SetFrameLevel(frameLevel + 2)
    end

    -- Determine effective orientation (AUTO/HORIZONTAL/VERTICAL)
    local orientation = cfg.orientation or "AUTO"
    local isVertical = (orientation == "VERTICAL")

    -- For AUTO, check if locked to a CDM viewer and inherit its orientation
    if orientation == "AUTO" then
        if cfg.lockedToEssential then
            local viewer = _G.EssentialCooldownViewer
            isVertical = viewer and viewer.__cdmLayoutDirection == "VERTICAL"
        elseif cfg.lockedToUtility then
            local viewer = _G.UtilityCooldownViewer
            isVertical = viewer and viewer.__cdmLayoutDirection == "VERTICAL"
        elseif cfg.lockedToPrimary then
            -- Inherit from Primary bar's locked CDM
            local primaryCfg = self.db.profile.powerBar
            if primaryCfg then
                if primaryCfg.lockedToEssential then
                    local viewer = _G.EssentialCooldownViewer
                    isVertical = viewer and viewer.__cdmLayoutDirection == "VERTICAL"
                elseif primaryCfg.lockedToUtility then
                    local viewer = _G.UtilityCooldownViewer
                    isVertical = viewer and viewer.__cdmLayoutDirection == "VERTICAL"
                end
            end
        end
    end

    -- Apply orientation to StatusBar
    bar.StatusBar:SetOrientation(isVertical and "VERTICAL" or "HORIZONTAL")

    -- =====================================================
    -- LOCKED TO PRIMARY MODE (highest priority positioning)
    -- =====================================================
    local width
    local lockedToPrimaryHandled = false

    if cfg.lockedToPrimary then
        local primaryBar = self.powerBar
        local primaryCfg = self.db.profile.powerBar

        if primaryBar and primaryBar:IsShown() and primaryCfg then
            -- Primary is visible - get live dimensions and cache them
            local primaryCenterX, primaryCenterY = primaryBar:GetCenter()
            local screenCenterX, screenCenterY = UIParent:GetCenter()

            if primaryCenterX and primaryCenterY and screenCenterX and screenCenterY then
                -- Round center coordinates to match Quick Position calculation
                primaryCenterX = math.floor(primaryCenterX + 0.5)
                primaryCenterY = math.floor(primaryCenterY + 0.5)
                screenCenterX = math.floor(screenCenterX + 0.5)
                screenCenterY = math.floor(screenCenterY + 0.5)
                -- Cache Primary dimensions for Standalone fallback
                -- For vertical Primary bar, GetWidth() returns thickness, GetHeight() returns length
                local primaryIsVertical = (primaryCfg.orientation == "VERTICAL")
                local primaryVisualLength = primaryIsVertical and primaryBar:GetHeight() or primaryBar:GetWidth()
                cachedPrimaryDimensions.centerX = primaryCenterX
                cachedPrimaryDimensions.centerY = primaryCenterY
                cachedPrimaryDimensions.width = primaryVisualLength
                cachedPrimaryDimensions.height = primaryCfg.height or 8
                cachedPrimaryDimensions.borderSize = primaryCfg.borderSize or 1

                local primaryHeight = cachedPrimaryDimensions.height
                local primaryBorderSize = cachedPrimaryDimensions.borderSize
                local primaryWidth = cachedPrimaryDimensions.width
                local secondaryHeight = cfg.height or 8
                local secondaryBorderSize = cfg.borderSize or 1

                local offsetX, offsetY

                if isVertical then
                    -- Vertical secondary: goes to the RIGHT of Primary
                    local primaryActualWidth = primaryBar:GetWidth()
                    local primaryVisualRight = primaryCenterX + (primaryActualWidth / 2)
                    local secondaryCenterX = primaryVisualRight + (secondaryHeight / 2)
                    offsetX = math.floor(secondaryCenterX - screenCenterX + 0.5)
                    offsetY = math.floor(primaryCenterY - screenCenterY + 0.5)
                else
                    -- Horizontal bar: Secondary goes ABOVE Primary
                    local primaryVisualTop = primaryCenterY + (primaryHeight / 2) + primaryBorderSize
                    local secondaryCenterY = primaryVisualTop + (secondaryHeight / 2) + secondaryBorderSize
                    offsetX = math.floor(primaryCenterX - screenCenterX + 0.5)
                    offsetY = math.floor(secondaryCenterY - screenCenterY + 0.5) - 1
                end

                -- Calculate width to match Primary's visual width
                local targetWidth = primaryWidth + (2 * primaryBorderSize) - (2 * secondaryBorderSize)
                width = math.floor(targetWidth + 0.5)

                -- Position the bar (add user adjustment on top of calculated base position)
                local finalX = offsetX + (cfg.offsetX or 0)
                local finalY = offsetY + (cfg.offsetY or 0)
                if bar._cachedX ~= finalX or bar._cachedY ~= finalY or bar._cachedAutoMode ~= "lockedToPrimary" then
                    bar:ClearAllPoints()
                    bar:SetPoint("CENTER", UIParent, "CENTER", finalX, finalY)
                    bar._cachedX = finalX
                    bar._cachedY = finalY
                    bar._cachedAnchor = nil
                    bar._cachedAutoMode = "lockedToPrimary"
                    -- Notify unit frames that may be anchored to this power bar
                    if _G.QUI_UpdateAnchoredUnitFrames then
                        _G.QUI_UpdateAnchoredUnitFrames()
                    end
                end

                lockedToPrimaryHandled = true
            else
                -- Primary bar not yet laid out (GetCenter returns nil on first frame)
                -- Defer update to allow layout to complete
                if not bar._lockedToPrimaryDeferred then
                    bar._lockedToPrimaryDeferred = true
                    C_Timer.After(0.1, function()
                        bar._lockedToPrimaryDeferred = nil
                        self:UpdateSecondaryPowerBar()
                    end)
                end
                return  -- Always return when GetCenter fails, prevents race condition fall-through
            end
        elseif cfg.standaloneMode and cachedPrimaryDimensions.centerX then
            -- Primary is hidden but Secondary is Standalone - use cached dimensions
            local screenCenterX, screenCenterY = UIParent:GetCenter()

            if screenCenterX and screenCenterY then
                -- Round screen center to match Quick Position calculation
                screenCenterX = math.floor(screenCenterX + 0.5)
                screenCenterY = math.floor(screenCenterY + 0.5)
                local primaryCenterX = cachedPrimaryDimensions.centerX
                local primaryCenterY = cachedPrimaryDimensions.centerY
                local primaryHeight = cachedPrimaryDimensions.height
                local primaryBorderSize = cachedPrimaryDimensions.borderSize
                local primaryWidth = cachedPrimaryDimensions.width  -- This is GetWidth() from when primary was visible
                local secondaryHeight = cfg.height or 8
                local secondaryBorderSize = cfg.borderSize or 1

                local offsetX, offsetY

                if isVertical then
                    -- Vertical secondary: goes to the RIGHT of Primary (use cached actual width)
                    local primaryVisualRight = primaryCenterX + (primaryWidth / 2)
                    local secondaryCenterX = primaryVisualRight + (secondaryHeight / 2)
                    offsetX = math.floor(secondaryCenterX - screenCenterX + 0.5)
                    offsetY = math.floor(primaryCenterY - screenCenterY + 0.5)
                else
                    -- Horizontal bar: Secondary goes ABOVE Primary
                    local primaryVisualTop = primaryCenterY + (primaryHeight / 2) + primaryBorderSize
                    local secondaryCenterY = primaryVisualTop + (secondaryHeight / 2) + secondaryBorderSize
                    offsetX = math.floor(primaryCenterX - screenCenterX + 0.5)
                    offsetY = math.floor(secondaryCenterY - screenCenterY + 0.5) - 1
                end

                local targetWidth = primaryWidth + (2 * primaryBorderSize) - (2 * secondaryBorderSize)
                width = math.floor(targetWidth + 0.5)

                -- Add user adjustment on top of calculated base position
                local finalX = offsetX + (cfg.offsetX or 0)
                local finalY = offsetY + (cfg.offsetY or 0)
                if bar._cachedX ~= finalX or bar._cachedY ~= finalY or bar._cachedAutoMode ~= "lockedToPrimaryCached" then
                    bar:ClearAllPoints()
                    bar:SetPoint("CENTER", UIParent, "CENTER", finalX, finalY)
                    bar._cachedX = finalX
                    bar._cachedY = finalY
                    bar._cachedAnchor = nil
                    bar._cachedAutoMode = "lockedToPrimaryCached"
                    -- Notify unit frames that may be anchored to this power bar
                    if _G.QUI_UpdateAnchoredUnitFrames then
                        _G.QUI_UpdateAnchoredUnitFrames()
                    end
                end

                lockedToPrimaryHandled = true
            end
        else
            -- Primary is hidden and Secondary is NOT Standalone - hide Secondary
            bar:Hide()
            return
        end
    end

    -- =====================================================
    -- LEGACY POSITIONING (autoAttach or manual)
    -- =====================================================
    if not lockedToPrimaryHandled then
        -- Get anchor frame (needed for autoAttach positioning)
        local anchorName = cfg.autoAttach and "EssentialCooldownViewer" or cfg.attachTo
        local anchor = _G[anchorName]

        -- In standalone mode, don't hide when anchor is hidden (bar is independent)
        -- Otherwise, hide if anchor doesn't exist or isn't shown
        if not cfg.standaloneMode and not cfg.lockedToEssential and not cfg.lockedToUtility then
            if not anchor or not anchor:IsShown() then
                bar:Hide()
                return
            end
        end

        -- Safety check: don't attach if anchor has invalid/zero dimensions (not yet laid out)
        if cfg.autoAttach and anchor then
            local anchorWidth = anchor:GetWidth()
            local anchorHeight = anchor:GetHeight()
            if not anchorWidth or anchorWidth <= 1 or not anchorHeight or anchorHeight <= 1 then
                -- Viewer not ready yet, defer update
                bar:Hide()
                C_Timer.After(0.5, function() self:UpdateSecondaryPowerBar() end)
                return
            end
        end

        -- Calculate width and height first (needed for positioning)
        local barHeight = cfg.height or 8
        if cfg.autoAttach then
            -- Auto-attach: manual width takes priority if set, otherwise use auto-detected width
            -- Priority: manual width (if > 0) > NCDM calculated width > saved width from DB > fallback
            if cfg.width and cfg.width > 0 then
                -- User has set a manual width override
                width = cfg.width
            else
                -- Auto-detect from Essential Cooldowns or Primary bar
                if self.powerBar and self.powerBar:IsShown() then
                    width = self.powerBar:GetWidth()
                elseif anchor then
                    width = anchor.__cdmIconWidth
                end
                if not width or width <= 0 then
                    -- Use saved width from last NCDM layout (persists across reloads)
                    width = self.db.profile.ncdm and self.db.profile.ncdm._lastEssentialWidth
                end
                if not width or width <= 0 then
                    width = 200 -- absolute fallback
                end
            end

            -- Only reposition when anchor/offset actually changed (prevents flicker)
            local wantedOffsetX = Scale(cfg.offsetX or 0)
            local wantedAnchor = (self.powerBar and self.powerBar:IsShown()) and self.powerBar or anchor

            -- If no valid anchor available, fall through to manual positioning
            if not wantedAnchor then
                -- Fall through to manual positioning below
            else
                if bar._cachedAnchor ~= wantedAnchor or bar._cachedX ~= wantedOffsetX or bar._cachedAutoMode ~= true then
                    bar:ClearAllPoints()
                    bar:SetPoint("BOTTOM", wantedAnchor, "TOP", wantedOffsetX, 0)
                    bar._cachedAnchor = wantedAnchor
                    bar._cachedX = wantedOffsetX
                    bar._cachedY = nil  -- Clear manual mode cache
                    bar._cachedAutoMode = true
                    -- Notify unit frames that may be anchored to this power bar
                    if _G.QUI_UpdateAnchoredUnitFrames then
                        _G.QUI_UpdateAnchoredUnitFrames()
                    end
                end
            end
        end

        -- Manual positioning (or fallback when autoAttach has no valid anchor)
        if not cfg.autoAttach or (cfg.autoAttach and not ((self.powerBar and self.powerBar:IsShown()) or anchor)) then
            -- Manual positioning - anchor to center of screen
            -- Default width to Essential Cooldowns width if not manually set
            width = cfg.width
            if not width or width <= 0 then
                -- Try to get Essential Cooldowns width
                local essentialViewer = _G["EssentialCooldownViewer"]
                if essentialViewer then
                    width = essentialViewer.__cdmIconWidth
                end
                if not width or width <= 0 then
                    width = self.db.profile.ncdm and self.db.profile.ncdm._lastEssentialWidth
                end
                if not width or width <= 0 then
                    width = 200 -- absolute fallback
                end
            end

            -- Only reposition when offsets actually changed (prevents flicker)
            -- In locked modes, add lockedBase + user adjustment; otherwise just use offset as absolute
            local baseX = (cfg.lockedToEssential or cfg.lockedToUtility) and (cfg.lockedBaseX or 0) or 0
            local baseY = (cfg.lockedToEssential or cfg.lockedToUtility) and (cfg.lockedBaseY or 0) or 0
            local wantedX = cfg.useRawPixels and (baseX + (cfg.offsetX or 0)) or Scale(baseX + (cfg.offsetX or 0))
            local wantedY = cfg.useRawPixels and (baseY + (cfg.offsetY or 0)) or Scale(baseY + (cfg.offsetY or 0))
            if bar._cachedX ~= wantedX or bar._cachedY ~= wantedY or bar._cachedAutoMode ~= false then
                bar:ClearAllPoints()
                bar:SetPoint("CENTER", UIParent, "CENTER", wantedX, wantedY)
                bar._cachedX = wantedX
                bar._cachedY = wantedY
                bar._cachedAnchor = nil  -- Clear auto-attach mode cache
                bar._cachedAutoMode = false
                -- Notify unit frames that may be anchored to this power bar
                if _G.QUI_UpdateAnchoredUnitFrames then
                    _G.QUI_UpdateAnchoredUnitFrames()
                end
            end
        end
    end

    -- For vertical bars, swap width and height (width = thickness, height = length)
    local wantedH, wantedW
    if isVertical then
        -- Vertical bar: cfg.width is the bar length (becomes height), cfg.height is thickness (becomes width)
        wantedW = cfg.useRawPixels and (cfg.height or 4) or Scale(cfg.height or 4)
        wantedH = cfg.useRawPixels and width or Scale(width)
    else
        -- Horizontal bar: normal dimensions
        wantedH = cfg.useRawPixels and (cfg.height or 4) or Scale(cfg.height or 4)
        wantedW = cfg.useRawPixels and width or Scale(width)
    end

    -- Only resize when dimensions actually changed (prevents flicker)
    if bar._cachedH ~= wantedH then
        bar:SetHeight(wantedH)
        bar._cachedH = wantedH
    end
    if bar._cachedW ~= wantedW then
        bar:SetWidth(wantedW)
        bar._cachedW = wantedW
    end

    -- Update border size (pixel-perfect)
    local borderSize = cfg.useRawPixels and (cfg.borderSize or 1) or Scale(cfg.borderSize or 1)
    if bar.Border then
        bar.Border:ClearAllPoints()
        bar.Border:SetPoint("TOPLEFT", bar, -borderSize, borderSize)
        bar.Border:SetPoint("BOTTOMRIGHT", bar, borderSize, -borderSize)
        bar.Border:SetBackdrop({
            edgeFile = "Interface\\Buttons\\WHITE8X8",
            edgeSize = borderSize,
        })
        bar.Border:SetBackdropBorderColor(0, 0, 0, 1)
        bar.Border:SetShown(borderSize > 0)
    end

    -- Update background color
    local bgColor = cfg.bgColor or { 0.15, 0.15, 0.15, 1 }
    if bar.Background then
        bar.Background:SetColorTexture(bgColor[1], bgColor[2], bgColor[3], bgColor[4] or 1)
    end

    -- Only update texture when changed (prevents flicker)
    local tex = LSM:Fetch("statusbar", GetBarTexture(cfg))
    if bar._cachedTex ~= tex then
        bar.StatusBar:SetStatusBarTexture(tex)
        bar._cachedTex = tex
    end

    -- Get resource values
    local max, current, displayValue, valueType = GetSecondaryResourceValue(resource)
    if not max then
        bar:Hide()
        return
    end

    -- Handle fragmented power types (Runes)
    if fragmentedPowerTypes[resource] then
        self:CreateFragmentedPowerBars(bar, resource, isVertical)
        self:UpdateFragmentedPowerDisplay(bar, resource, isVertical)

        bar.StatusBar:SetMinMaxValues(0, max)
        bar.StatusBar:SetValue(current)

        -- Set bar color based on checkboxes: Power Type > Class > Custom
        if cfg.usePowerColor then
            local color = GetResourceColor(resource)
            bar.StatusBar:SetStatusBarColor(color.r, color.g, color.b, color.a or 1)
        elseif cfg.useClassColor then
            local _, class = UnitClass("player")
            local classColor = RAID_CLASS_COLORS[class]
            if classColor then
                bar.StatusBar:SetStatusBarColor(classColor.r, classColor.g, classColor.b)
            else
                local color = GetResourceColor(resource)
                bar.StatusBar:SetStatusBarColor(color.r, color.g, color.b, color.a or 1)
            end
        elseif cfg.useCustomColor and cfg.customColor then
            -- Custom color override
            local c = cfg.customColor
            bar.StatusBar:SetStatusBarColor(c[1], c[2], c[3], c[4] or 1)
        else
            -- Power type color (default)
            local color = GetResourceColor(resource)
            bar.StatusBar:SetStatusBarColor(color.r, color.g, color.b, color.a or 1)
        end

        bar.TextValue:SetText(tostring(current))
    else
    -- Normal bar display
    bar.StatusBar:SetAlpha(1)
    bar.StatusBar:SetMinMaxValues(0, max)
    bar.StatusBar:SetValue(current)

    -- Set bar color based on checkboxes: Power Type > Class > Custom
    if cfg.usePowerColor then
        local color = GetResourceColor(resource)
        bar.StatusBar:SetStatusBarColor(color.r, color.g, color.b, color.a or 1)
    elseif cfg.useClassColor then
        local _, class = UnitClass("player")
        local classColor = RAID_CLASS_COLORS[class]
        if classColor then
            bar.StatusBar:SetStatusBarColor(classColor.r, classColor.g, classColor.b)
        else
            local color = GetResourceColor(resource)
            bar.StatusBar:SetStatusBarColor(color.r, color.g, color.b, color.a or 1)
        end
    elseif cfg.useCustomColor and cfg.customColor then
        -- Custom color override
        local c = cfg.customColor
        bar.StatusBar:SetStatusBarColor(c[1], c[2], c[3], c[4] or 1)
    else
        -- Power type color (default)
        local color = GetResourceColor(resource)
        bar.StatusBar:SetStatusBarColor(color.r, color.g, color.b, color.a or 1)
    end


    -- Update text (safe: uses only displayValue)
    if valueType == "shards" then
        -- Destruction Warlock: show decimal shards (e.g., 3.4)
        bar.TextValue:SetText(string.format("%.1f", displayValue or 0))
    elseif valueType == "percent" and cfg.showPercent then
        bar.TextValue:SetText(string.format("%.0f%%", displayValue or 0))
    elseif valueType == "percent" then
        -- Stagger with showPercent off: show raw stagger amount
        local stagger = UnitStagger("player") or 0
        bar.TextValue:SetText(tostring(math.floor(stagger)))
    else
        bar.TextValue:SetText(tostring(displayValue or 0))
    end
    
    -- Hide fragmented bars
    for _, fragmentBar in ipairs(bar.FragmentedPowerBars) do
        fragmentBar:Hide()
    end
end

    bar.TextValue:SetFont(GetGeneralFont(), Scale(cfg.textSize or 12), GetGeneralFontOutline())
    bar.TextValue:SetShadowOffset(0, 0)
    bar.TextValue:ClearAllPoints()
    bar.TextValue:SetPoint("CENTER", bar.TextFrame, "CENTER", Scale(cfg.textX or 0), Scale(cfg.textY or 0))

    -- Apply text color
    if cfg.textUseClassColor then
        local _, class = UnitClass("player")
        local classColor = RAID_CLASS_COLORS[class]
        if classColor then
            bar.TextValue:SetTextColor(classColor.r, classColor.g, classColor.b, 1)
        end
    else
        local c = cfg.textCustomColor or { 1, 1, 1, 1 }
        bar.TextValue:SetTextColor(c[1], c[2], c[3], c[4] or 1)
    end

    if bar.SoulShardDecimal then
        bar.SoulShardDecimal:SetFont(GetGeneralFont(), Scale(cfg.textSize or 12), GetGeneralFontOutline())
        bar.SoulShardDecimal:SetShadowOffset(0, 0)
        -- Apply same text color to soul shard decimal
        if cfg.textUseClassColor then
            local _, class = UnitClass("player")
            local classColor = RAID_CLASS_COLORS[class]
            if classColor then
                bar.SoulShardDecimal:SetTextColor(classColor.r, classColor.g, classColor.b, 1)
            end
        else
            local c = cfg.textCustomColor or { 1, 1, 1, 1 }
            bar.SoulShardDecimal:SetTextColor(c[1], c[2], c[3], c[4] or 1)
        end
    end


    -- Show text
    bar.TextFrame:SetShown(cfg.showText ~= false)

    if not fragmentedPowerTypes[resource] then
        self:UpdateSecondaryPowerBarTicks(bar, resource, max)
    end

    -- Hide legacy decimal overlay (no longer used - decimals now rendered via string.format)
    if bar.SoulShardDecimal then
        bar.SoulShardDecimal:Hide()
    end


    bar:Show()
end

-- EVENT HANDLER

function QUICore:OnUnitPower(_, unit)
    -- Be forgiving: if unit is nil or not "player", still update.
    -- It's cheap and avoids missing power updates.
    if unit and unit ~= "player" then
        return
    end

    local db = self.db and self.db.profile
    local unthrottled = db and db.powerBar and db.powerBar.unthrottledCPU
    local now = GetTime()

    -- Primary bar
    if unthrottled or (now - lastPrimaryUpdate >= UPDATE_THROTTLE) then
        self:UpdatePowerBar()
        lastPrimaryUpdate = now
    end

    -- Secondary bar: instant for discrete resources, unthrottled mode, or throttled otherwise
    local resource = GetSecondaryResource()
    if unthrottled or instantFeedbackTypes[resource] then
        self:UpdateSecondaryPowerBar()
    elseif now - lastSecondaryUpdate >= UPDATE_THROTTLE then
        self:UpdateSecondaryPowerBar()
        lastSecondaryUpdate = now
    end
end


-- REFRESH

local oldRefreshAll = QUICore.RefreshAll
function QUICore:RefreshAll()
    if oldRefreshAll then
        oldRefreshAll(self)
    end

    -- Refresh resource bars with new settings
    for _, name in ipairs(self.viewers) do
        local viewer = _G[name]
        if viewer and viewer:IsShown() then
            self:ApplyViewerSkin(viewer)
        end
    end

    self:UpdatePowerBar()
    self:UpdateSecondaryPowerBar()
end

-- EVENT-DRIVEN RUNE UPDATES
-- RUNE_POWER_UPDATE triggers full layout refresh; smooth timer enabled while runes recharge

function QUICore:OnRunePowerUpdate()
    local now = GetTime()
    if now - lastSecondaryUpdate < UPDATE_THROTTLE then
        return
    end
    lastSecondaryUpdate = now

    local resource = GetSecondaryResource()
    if resource == Enum.PowerType.Runes then
        local bar = self.secondaryPowerBar
        if bar and bar:IsShown() and fragmentedPowerTypes[resource] then
            -- Determine orientation for proper positioning
            local cfg = self.db.profile.secondaryPowerBar
            local orientation = cfg.orientation or "HORIZONTAL"
            local isVertical = (orientation == "VERTICAL")
            self:UpdateFragmentedPowerDisplay(bar, resource, isVertical)

            -- Check if any runes are on cooldown
            local anyOnCooldown = false
            for i = 1, 6 do
                local _, _, runeReady = GetRuneCooldown(i)
                if not runeReady then
                    anyOnCooldown = true
                    break
                end
            end

            -- Enable/disable smooth updater
            if anyOnCooldown and not runeUpdateRunning then
                runeUpdateRunning = true
                runeUpdateElapsed = 0
                bar:SetScript("OnUpdate", RuneTimerOnUpdate)
            elseif not anyOnCooldown and runeUpdateRunning then
                bar:SetScript("OnUpdate", nil)
                runeUpdateRunning = false
            end
        end
    end
end

-- INITIALIZATION

local function InitializeResourceBars(self)
    -- Register additional events
    self:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED", "OnSpecChanged")
    self:RegisterEvent("UPDATE_SHAPESHIFT_FORM", "OnShapeshiftChanged")
    self:RegisterEvent("PLAYER_ENTERING_WORLD", function()
        EnsureDemonHunterSoulBar()
        self:OnUnitPower()
    end)

    -- POWER UPDATES
    self:RegisterEvent("UNIT_POWER_FREQUENT", "OnUnitPower")
    self:RegisterEvent("UNIT_POWER_UPDATE", "OnUnitPower")
    self:RegisterEvent("UNIT_MAXPOWER", "OnUnitPower")
    self:RegisterEvent("RUNE_POWER_UPDATE", "OnRunePowerUpdate")  -- DK rune updates (event-driven, replaces ticker)

    -- Combat state events - force update on combat transitions
    -- Ensures bars show correct values when entering/exiting combat
    self:RegisterEvent("PLAYER_REGEN_DISABLED", "OnUnitPower")
    self:RegisterEvent("PLAYER_REGEN_ENABLED", "OnUnitPower")

    -- Ensure Demon Hunter soul bar is spawned
    EnsureDemonHunterSoulBar()

    -- Initial update
    self:UpdatePowerBar()
    self:UpdateSecondaryPowerBar()

    -- Hook Blizzard Edit Mode for power bars
    C_Timer.After(0.6, function()
        if EditModeManagerFrame and not QUICore._powerBarEditModeHooked then
            QUICore._powerBarEditModeHooked = true
            hooksecurefunc(EditModeManagerFrame, "EnterEditMode", function()
                if not InCombatLockdown() then
                    QUICore:EnablePowerBarEditMode()
                end
            end)
            hooksecurefunc(EditModeManagerFrame, "ExitEditMode", function()
                if not InCombatLockdown() then
                    QUICore:DisablePowerBarEditMode()
                end
            end)
        end
    end)
end


function QUICore:OnSpecChanged()
    -- Ensure Demon Hunter soul bar is spawned when spec changes
    EnsureDemonHunterSoulBar()

    self:UpdatePowerBar()
    self:UpdateSecondaryPowerBar()
end

function QUICore:OnShapeshiftChanged()
    -- Druid form changes affect primary/secondary resources
    self:UpdatePowerBar()
    self:UpdateSecondaryPowerBar()
end
-- Hook into that shit
local oldOnEnable = QUICore.OnEnable
function QUICore:OnEnable()
    if oldOnEnable then
        oldOnEnable(self)
    end
    InitializeResourceBars(self)
end