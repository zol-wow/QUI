---------------------------------------------------------------------------
-- QUI Crosshair Module
-- A simple screen center crosshair overlay
---------------------------------------------------------------------------
local ADDON_NAME, ns = ...
local QUI = ns.QUI or {}
ns.QUI = QUI
local Helpers = ns.Helpers

local crosshairFrame, horizLine, vertLine, horizBorder, vertBorder

-- Separate frame for range checking (always visible so OnUpdate runs even when crosshair is hidden)
local rangeCheckFrame

-- Range tracking state
local isOutOfRange = false
local isOutOfMidRange = false  -- For 25-yard check
local rangeCheckElapsed = 0
local RANGE_CHECK_INTERVAL = 0.1  -- Check range 10 times per second


---------------------------------------------------------------------------
-- Get settings from database
---------------------------------------------------------------------------
local function GetSettings()
    return Helpers.GetModuleDB("crosshair")
end

---------------------------------------------------------------------------
-- Check if target is out of melee range
-- Uses action bar scanning with IsActionInRange for 12.x PTR compatibility
---------------------------------------------------------------------------

-- Melee abilities to scan for on action bars (module scope to avoid recreation)
-- ALL abilities must be 5-yard melee range for accurate detection
local MELEE_RANGE_ABILITIES = {
    -- Melee Interrupts (5 yards only)
    96231,  -- Paladin: Rebuke
    6552,   -- Warrior: Pummel
    1766,   -- Rogue: Kick
    116705, -- Monk: Spear Hand Strike
    183752, -- Demon Hunter: Disrupt (Havoc)
    -- NOTE: Mind Freeze (15yd) and Skull Bash (13yd) excluded - not true melee range
    -- Vengeance Demon Hunter (5 yards) - Disrupt may be talented away
    228478, -- Soul Cleave
    263642, -- Fracture
    -- Death Knight melee abilities (5 yards)
    49143,  -- Frost Strike
    55090,  -- Scourge Strike
    206930, -- Heart Strike
    -- Mistweaver Monk (healers don't have interrupts in Midnight)
    100780, -- Tiger Palm
    100784, -- Blackout Kick
    107428, -- Rising Sun Kick
    -- Druid cat form (5 yards)
    5221,   -- Shred
    3252,   -- Shred (alternate ID)
    1822,   -- Rake
    22568,  -- Ferocious Bite
    22570,  -- Maim
    -- Guardian Druid (5 yards)
    33917,  -- Mangle
    6807,   -- Maul
}

-- Mid-range abilities (25 yards) for Evokers and Devourer Demon Hunters
local MID_RANGE_ABILITIES = {
    -- Evoker (25 yards)
    361469, -- Living Flame
    356995, -- Disintegrate
    382266, -- Fire Breath
    357211, -- Pyre
    355913, -- Emerald Blossom
    360995, -- Verdant Embrace
    364343, -- Echo
    366155, -- Reversion
    -- Devourer Demon Hunter (25 yards) - Midnight spec
    473662,  -- Consume
    1226019, -- Reap
    473728,  -- Void Ray
}

local function IsOutOfMeleeRange()
    -- No target = not out of range (use normal color)
    if not UnitExists("target") then
        return false
    end

    -- Must be an attackable target
    if not UnitCanAttack("player", "target") then
        return false
    end

    -- Dead targets don't count
    if UnitIsDeadOrGhost("target") then
        return false
    end

    -- Priority 1: Scan action bar for a melee ability and use IsActionInRange
    -- This is the method that works on action bars in 12.x PTR
    if IsActionInRange then
        -- Scan for melee abilities with range data
        -- Check both direct spells AND macros that cast spells (subType == "spell")
        for slot = 1, 180 do
            local actionType, id, subType = GetActionInfo(slot)
            -- Match direct spells OR macros that cast a spell
            if id and (actionType == "spell" or (actionType == "macro" and subType == "spell")) then
                for _, abilityID in ipairs(MELEE_RANGE_ABILITIES) do
                    if id == abilityID then
                        local inRange = IsActionInRange(slot)
                        if inRange == true then
                            return false  -- In range
                        elseif inRange == false then
                            return true   -- Out of range
                        end
                        -- nil = no range data for this slot, continue scanning
                    end
                end
            end
        end
    end

    -- Priority 2: Try legacy IsSpellInRange with spell name (11.x retail)
    if IsSpellInRange then
        local attackInRange = IsSpellInRange("Attack", "target")
        if attackInRange == 1 then
            return false  -- In melee range
        elseif attackInRange == 0 then
            return true   -- Out of melee range
        end
        -- nil = not available, fall through
    end

    -- Priority 3: Try C_Spell.IsSpellInRange with melee abilities (11.x retail fallback)
    if C_Spell and C_Spell.IsSpellInRange then
        for _, spellID in ipairs(MELEE_RANGE_ABILITIES) do
            local spellKnown = IsSpellKnown and IsSpellKnown(spellID)
            if spellKnown then
                local inRange = C_Spell.IsSpellInRange(spellID, "target")
                if inRange == true then
                    return false
                elseif inRange == false then
                    return true
                end
                -- nil = melee spells don't have range on 12.x, fall through
            end
        end
    end

    -- Priority 4: CheckInteractDistance index 3 (~10 yards)
    -- Fallback - not ideal but better than nothing
    local inRange = CheckInteractDistance("target", 3)
    if inRange ~= nil then
        return not inRange
    end

    return false
end

---------------------------------------------------------------------------
-- Check if target is out of mid-range (25 yards)
-- Used for Evokers and Devourer Demon Hunters
---------------------------------------------------------------------------
local function IsOutOfMidRange()
    -- No target = not out of range (use normal color)
    if not UnitExists("target") then
        return false
    end

    -- Must be an attackable target
    if not UnitCanAttack("player", "target") then
        return false
    end

    -- Dead targets don't count
    if UnitIsDeadOrGhost("target") then
        return false
    end

    -- Priority 1: Scan action bar for a 25-yard ability and use IsActionInRange
    -- Only trust 'false' (definitely out of range). 'true' might mean "no max range".
    if IsActionInRange then
        local foundInRange = false
        local foundOutOfRange = false
        for slot = 1, 180 do
            local actionType, id, subType = GetActionInfo(slot)
            if id and (actionType == "spell" or (actionType == "macro" and subType == "spell")) then
                for _, abilityID in ipairs(MID_RANGE_ABILITIES) do
                    if id == abilityID then
                        local inRange = IsActionInRange(slot)
                        if inRange == false then
                            foundOutOfRange = true
                        elseif inRange == true then
                            foundInRange = true
                        end
                    end
                end
            end
        end
        -- Out of range takes priority (if any ability says out of range, we're out)
        if foundOutOfRange then
            return true
        end
        if foundInRange then
            return false
        end
    end

    -- Priority 2: Try C_Spell.IsSpellInRange with 25-yard abilities
    -- Only check spells the player actually has (IsPlayerSpell)
    if C_Spell and C_Spell.IsSpellInRange then
        for _, spellID in ipairs(MID_RANGE_ABILITIES) do
            if IsPlayerSpell and IsPlayerSpell(spellID) then
                local inRange = C_Spell.IsSpellInRange(spellID, "target")
                if inRange == true then
                    return false  -- In range
                elseif inRange == false then
                    return true   -- Out of range
                end
            end
        end
    end

    -- Fallback: assume in range if no abilities found
    return false
end

---------------------------------------------------------------------------
-- Apply crosshair color based on range state
-- Supports independent melee (5yd) and mid-range (25yd) checks
---------------------------------------------------------------------------
local function ApplyCrosshairColor(settings, outOfMelee, outOfMid)
    if not horizLine or not vertLine then return end

    local r, g, b, a

    if settings.changeColorOnRange then
        local meleeCheck = settings.enableMeleeRangeCheck ~= false  -- default true
        local midCheck = settings.enableMidRangeCheck == true

        if meleeCheck and midCheck then
            -- Both checks enabled: melee → mid-range → out-of-range
            if outOfMid then
                -- Out of 25-yard range - use out-of-range color
                local oorColor = settings.outOfRangeColor or { 1, 0.2, 0.2, 1 }
                r, g, b, a = oorColor[1] or 1, oorColor[2] or 0.2, oorColor[3] or 0.2, oorColor[4] or 1
            elseif outOfMelee then
                -- Out of melee but in 25-yard range - use mid-range color
                local midColor = settings.midRangeColor or { 1, 0.6, 0.2, 1 }
                r, g, b, a = midColor[1] or 1, midColor[2] or 0.6, midColor[3] or 0.2, midColor[4] or 1
            else
                -- In melee range - use normal color
                r, g, b, a = settings.r or 1, settings.g or 0.949, settings.b or 0, settings.a or 1
            end
        elseif meleeCheck then
            -- Only melee check: in melee → out-of-range
            if outOfMelee then
                local oorColor = settings.outOfRangeColor or { 1, 0.2, 0.2, 1 }
                r, g, b, a = oorColor[1] or 1, oorColor[2] or 0.2, oorColor[3] or 0.2, oorColor[4] or 1
            else
                r, g, b, a = settings.r or 1, settings.g or 0.949, settings.b or 0, settings.a or 1
            end
        elseif midCheck then
            -- Only mid-range check: in 25yd → out-of-range
            if outOfMid then
                local oorColor = settings.outOfRangeColor or { 1, 0.2, 0.2, 1 }
                r, g, b, a = oorColor[1] or 1, oorColor[2] or 0.2, oorColor[3] or 0.2, oorColor[4] or 1
            else
                r, g, b, a = settings.r or 1, settings.g or 0.949, settings.b or 0, settings.a or 1
            end
        else
            -- No checks enabled (shouldn't happen, but fallback to normal)
            r, g, b, a = settings.r or 1, settings.g or 0.949, settings.b or 0, settings.a or 1
        end
    else
        -- Range checking disabled - use normal color
        r, g, b, a = settings.r or 1, settings.g or 0.949, settings.b or 0, settings.a or 1
    end

    horizLine:SetColorTexture(r, g, b, a)
    vertLine:SetColorTexture(r, g, b, a)
end

---------------------------------------------------------------------------
-- Range check OnUpdate handler
---------------------------------------------------------------------------
local function OnRangeUpdate(self, elapsed)
    rangeCheckElapsed = rangeCheckElapsed + elapsed
    if rangeCheckElapsed < RANGE_CHECK_INTERVAL then return end
    rangeCheckElapsed = 0

    local settings = GetSettings()
    if not settings or not settings.enabled or not settings.changeColorOnRange then
        -- Feature disabled, stop checking
        self:SetScript("OnUpdate", nil)
        return
    end

    local inCombat = InCombatLockdown()

    -- Check if we should only track range in combat
    if settings.rangeColorInCombatOnly and not inCombat then
        -- Not in combat and combat-only is enabled, use normal color
        if isOutOfRange or isOutOfMidRange then
            isOutOfRange = false
            isOutOfMidRange = false
            ApplyCrosshairColor(settings, false, false)
        end
        -- If hideUntilOutOfRange, hide the crosshair when not in combat
        if settings.hideUntilOutOfRange and crosshairFrame then
            crosshairFrame:Hide()
        end
        return
    end

    local meleeCheck = settings.enableMeleeRangeCheck ~= false
    local midCheck = settings.enableMidRangeCheck == true

    local newOutOfRange = meleeCheck and IsOutOfMeleeRange() or false
    local newOutOfMidRange = midCheck and IsOutOfMidRange() or false

    if newOutOfRange ~= isOutOfRange or newOutOfMidRange ~= isOutOfMidRange then
        isOutOfRange = newOutOfRange
        isOutOfMidRange = newOutOfMidRange
        ApplyCrosshairColor(settings, isOutOfRange, isOutOfMidRange)
    end

    -- Handle hideUntilOutOfRange visibility (trigger on whichever range check is active)
    if settings.hideUntilOutOfRange and crosshairFrame then
        local shouldShow = inCombat and ((meleeCheck and isOutOfRange) or (midCheck and not meleeCheck and isOutOfMidRange))
        if shouldShow then
            crosshairFrame:Show()
        else
            crosshairFrame:Hide()
        end
    end
end

---------------------------------------------------------------------------
-- Start or stop range checking based on settings
---------------------------------------------------------------------------
local function UpdateRangeChecking()
    if not crosshairFrame then return end
    
    -- Create the range check frame if needed (separate frame so OnUpdate runs even when crosshair is hidden)
    if not rangeCheckFrame then
        rangeCheckFrame = CreateFrame("Frame", "QUI_CrosshairRangeCheck", UIParent)
        rangeCheckFrame:SetSize(1, 1)
        rangeCheckFrame:SetPoint("CENTER")
        rangeCheckFrame:Show()  -- Always visible
    end
    
    local settings = GetSettings()
    if settings and settings.enabled and settings.changeColorOnRange then
        -- Enable range checking on the always-visible frame
        rangeCheckElapsed = 0
        rangeCheckFrame:SetScript("OnUpdate", OnRangeUpdate)
        
        local inCombat = InCombatLockdown()
        
        -- Immediately check range (respecting combat-only setting)
        local meleeCheck = settings.enableMeleeRangeCheck ~= false
        local midCheck = settings.enableMidRangeCheck == true

        if settings.rangeColorInCombatOnly and not inCombat then
            isOutOfRange = false
            isOutOfMidRange = false
            ApplyCrosshairColor(settings, false, false)
        else
            isOutOfRange = meleeCheck and IsOutOfMeleeRange() or false
            isOutOfMidRange = midCheck and IsOutOfMidRange() or false
            ApplyCrosshairColor(settings, isOutOfRange, isOutOfMidRange)
        end
        
        -- Handle hideUntilOutOfRange initial visibility
        if settings.hideUntilOutOfRange then
            if inCombat and isOutOfRange then
                crosshairFrame:Show()
            else
                crosshairFrame:Hide()
            end
        end
    else
        -- Disable range checking
        if rangeCheckFrame then
            rangeCheckFrame:SetScript("OnUpdate", nil)
        end
        isOutOfRange = false
    end
end

---------------------------------------------------------------------------
-- Create the crosshair frame and textures
---------------------------------------------------------------------------
local function CreateCrosshair()
    if crosshairFrame then return end
    
    crosshairFrame = CreateFrame("Frame", "QUI_Crosshair", UIParent)
    crosshairFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    crosshairFrame:SetSize(1, 1)
    crosshairFrame:SetFrameStrata("HIGH")
    
    -- Border textures (drawn behind main lines)
    horizBorder = crosshairFrame:CreateTexture(nil, "BACKGROUND")
    horizBorder:SetPoint("CENTER", crosshairFrame)
    horizBorder:SetColorTexture(0, 0, 0, 1)
    
    vertBorder = crosshairFrame:CreateTexture(nil, "BACKGROUND")
    vertBorder:SetPoint("CENTER", crosshairFrame)
    vertBorder:SetColorTexture(0, 0, 0, 1)
    
    -- Main crosshair lines (drawn above borders)
    horizLine = crosshairFrame:CreateTexture(nil, "ARTWORK")
    horizLine:SetPoint("CENTER", crosshairFrame)
    horizLine:SetColorTexture(1, 0.949, 0, 1)  -- Default yellow
    
    vertLine = crosshairFrame:CreateTexture(nil, "ARTWORK")
    vertLine:SetPoint("CENTER", crosshairFrame)
    vertLine:SetColorTexture(1, 0.949, 0, 1)  -- Default yellow
    
    crosshairFrame:Hide()
end

---------------------------------------------------------------------------
-- Update crosshair appearance from settings
---------------------------------------------------------------------------
local function UpdateCrosshair()
    if not crosshairFrame then
        CreateCrosshair()
    end
    
    local settings = GetSettings()
    if not settings then
        crosshairFrame:Hide()
        return
    end
    
    -- Get settings with defaults
    local enabled = settings.enabled
    local size = settings.size or 12
    local thickness = settings.thickness or 3
    local borderSize = settings.borderSize or 2
    local offsetX = settings.offsetX or 0
    local offsetY = settings.offsetY or 0
    local borderR = settings.borderR or 0
    local borderG = settings.borderG or 0
    local borderB = settings.borderB or 0
    local borderA = settings.borderA or 1
    local strata = settings.strata or "HIGH"
    local onlyInCombat = settings.onlyInCombat
    
    -- Apply strata and position
    crosshairFrame:SetFrameStrata(strata)
    crosshairFrame:ClearAllPoints()
    crosshairFrame:SetPoint("CENTER", UIParent, "CENTER", offsetX, offsetY)
    
    -- Size the border textures (slightly larger than main lines)
    horizBorder:SetSize((size * 2) + borderSize * 2, thickness + borderSize * 2)
    vertBorder:SetSize(thickness + borderSize * 2, (size * 2) + borderSize * 2)
    horizBorder:SetColorTexture(borderR, borderG, borderB, borderA)
    vertBorder:SetColorTexture(borderR, borderG, borderB, borderA)
    
    -- Size the main crosshair lines
    horizLine:SetSize(size * 2, thickness)
    vertLine:SetSize(thickness, size * 2)
    
    -- Apply color based on range state (if feature enabled)
    if settings.changeColorOnRange then
        local meleeCheck = settings.enableMeleeRangeCheck ~= false
        local midCheck = settings.enableMidRangeCheck == true
        isOutOfRange = meleeCheck and IsOutOfMeleeRange() or false
        isOutOfMidRange = midCheck and IsOutOfMidRange() or false
        ApplyCrosshairColor(settings, isOutOfRange, isOutOfMidRange)
    else
        -- Use normal color
        local r = settings.r or 1
        local g = settings.g or 0.949
        local b = settings.b or 0
        local a = settings.a or 1
        horizLine:SetColorTexture(r, g, b, a)
        vertLine:SetColorTexture(r, g, b, a)
    end
    
    -- Show/hide based on settings
    if not enabled then
        crosshairFrame:Hide()
        crosshairFrame:SetScript("OnUpdate", nil)
    elseif onlyInCombat then
        crosshairFrame:SetShown(InCombatLockdown())
    else
        crosshairFrame:Show()
    end
    
    -- Update range checking state
    UpdateRangeChecking()
end

---------------------------------------------------------------------------
-- Combat visibility handling
---------------------------------------------------------------------------
local function OnCombatStart()
    local settings = GetSettings()
    if settings and settings.enabled and settings.onlyInCombat then
        if crosshairFrame then
            crosshairFrame:Show()
            UpdateRangeChecking()
        end
    end
end

local function OnCombatEnd()
    local settings = GetSettings()
    if settings and settings.onlyInCombat then
        if crosshairFrame then
            crosshairFrame:Hide()
            crosshairFrame:SetScript("OnUpdate", nil)
        end
    end
end

---------------------------------------------------------------------------
-- Target changed handler
---------------------------------------------------------------------------
local function OnTargetChanged()
    local settings = GetSettings()
    if settings and settings.enabled and settings.changeColorOnRange then
        -- Immediately update color when target changes
        local meleeCheck = settings.enableMeleeRangeCheck ~= false
        local midCheck = settings.enableMidRangeCheck == true
        isOutOfRange = meleeCheck and IsOutOfMeleeRange() or false
        isOutOfMidRange = midCheck and IsOutOfMidRange() or false
        ApplyCrosshairColor(settings, isOutOfRange, isOutOfMidRange)
    end
end

---------------------------------------------------------------------------
-- Initialize
---------------------------------------------------------------------------
local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
eventFrame:RegisterEvent("PLAYER_TARGET_CHANGED")
eventFrame:SetScript("OnEvent", function(self, event, ...)
    if event == "PLAYER_LOGIN" then
        C_Timer.After(1, function()
            CreateCrosshair()
            UpdateCrosshair()
        end)
    elseif event == "PLAYER_REGEN_DISABLED" then
        OnCombatStart()
    elseif event == "PLAYER_REGEN_ENABLED" then
        OnCombatEnd()
    elseif event == "PLAYER_TARGET_CHANGED" then
        OnTargetChanged()
    end
end)

---------------------------------------------------------------------------
-- Global refresh function for GUI
---------------------------------------------------------------------------
_G.QUI_RefreshCrosshair = UpdateCrosshair

QUI.Crosshair = {
    Update = UpdateCrosshair,
    Create = CreateCrosshair,
}

