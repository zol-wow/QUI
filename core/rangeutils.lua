---------------------------------------------------------------------------
-- QUI Range Utilities
-- Shared range-checking functions with cached action bar scanning.
-- Consumers: crosshair.lua, rangecheck.lua (and any future module).
---------------------------------------------------------------------------
local ADDON_NAME, ns = ...

local RangeUtils = {}
ns.RangeUtils = RangeUtils

---------------------------------------------------------------------------
-- ABILITY TABLES (single source of truth)
---------------------------------------------------------------------------

-- Melee range abilities (5 yards only)
RangeUtils.MELEE_RANGE_ABILITIES = {
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
RangeUtils.MID_RANGE_ABILITIES = {
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

-- Build a fast lookup set from the ability lists
local meleeSet = {}
for _, id in ipairs(RangeUtils.MELEE_RANGE_ABILITIES) do meleeSet[id] = true end
local midSet = {}
for _, id in ipairs(RangeUtils.MID_RANGE_ABILITIES) do midSet[id] = true end

---------------------------------------------------------------------------
-- CACHED ACTION BAR SCAN
-- Builds spellID -> slot mapping once, invalidated on bar change events.
-- Turns O(180 * N_abilities) per range check into O(N_abilities).
---------------------------------------------------------------------------
local meleeSlots = {}   -- spellID -> slot  (only melee abilities found on bars)
local midSlots = {}     -- spellID -> slot  (only mid-range abilities found on bars)
local cacheValid = false

local function RebuildSlotCache()
    wipe(meleeSlots)
    wipe(midSlots)
    if not IsActionInRange then
        cacheValid = true
        return
    end
    for slot = 1, 180 do
        local actionType, id, subType = GetActionInfo(slot)
        if id and (actionType == "spell" or (actionType == "macro" and subType == "spell")) then
            if meleeSet[id] then
                meleeSlots[id] = slot
            end
            if midSet[id] then
                midSlots[id] = slot
            end
        end
    end
    cacheValid = true
end

local function EnsureCache()
    if not cacheValid then RebuildSlotCache() end
end

-- Invalidate on relevant events
-- ACTIONBAR_SLOT_CHANGED intentionally not registered: fires constantly
-- even while idle.  SPELLS_CHANGED covers real action bar content changes.
local cacheFrame = CreateFrame("Frame")
cacheFrame:RegisterEvent("SPELLS_CHANGED")
cacheFrame:RegisterEvent("UPDATE_MACROS")
cacheFrame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
cacheFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
cacheFrame:SetScript("OnEvent", function()
    cacheValid = false
end)

---------------------------------------------------------------------------
-- SHARED TARGET VALIDATION
---------------------------------------------------------------------------
function RangeUtils.HasAttackableTarget()
    if not UnitExists("target") then return false end
    if not UnitCanAttack("player", "target") then return false end
    if UnitIsDeadOrGhost("target") then return false end
    return true
end

---------------------------------------------------------------------------
-- MELEE RANGE CHECK (5 yards)
---------------------------------------------------------------------------
function RangeUtils.IsOutOfMeleeRange()
    if not RangeUtils.HasAttackableTarget() then return false end

    EnsureCache()

    -- Priority 1: Cached action bar slots
    if IsActionInRange then
        for _, abilityID in ipairs(RangeUtils.MELEE_RANGE_ABILITIES) do
            local slot = meleeSlots[abilityID]
            if slot then
                local inRange = IsActionInRange(slot)
                if inRange == true then return false end
                if inRange == false then return true end
            end
        end
    end

    -- Priority 2: Legacy IsSpellInRange (11.x retail)
    if IsSpellInRange then
        local attackInRange = IsSpellInRange("Attack", "target")
        if attackInRange == 1 then return false end
        if attackInRange == 0 then return true end
    end

    -- Priority 3: C_Spell.IsSpellInRange fallback
    if C_Spell and C_Spell.IsSpellInRange then
        for _, spellID in ipairs(RangeUtils.MELEE_RANGE_ABILITIES) do
            if IsSpellKnown and IsSpellKnown(spellID) then
                local inRange = C_Spell.IsSpellInRange(spellID, "target")
                if inRange == true then return false end
                if inRange == false then return true end
            end
        end
    end

    return false
end

---------------------------------------------------------------------------
-- MID-RANGE CHECK (25 yards)
---------------------------------------------------------------------------
function RangeUtils.IsOutOfMidRange()
    if not RangeUtils.HasAttackableTarget() then return false end

    EnsureCache()

    -- Priority 1: Cached action bar slots
    if IsActionInRange then
        local foundOutOfRange = false
        for _, abilityID in ipairs(RangeUtils.MID_RANGE_ABILITIES) do
            local slot = midSlots[abilityID]
            if slot then
                local inRange = IsActionInRange(slot)
                if inRange == false then foundOutOfRange = true; break end
                if inRange == true then return false end
            end
        end
        if foundOutOfRange then return true end
    end

    -- Priority 2: C_Spell.IsSpellInRange fallback
    if C_Spell and C_Spell.IsSpellInRange then
        for _, spellID in ipairs(RangeUtils.MID_RANGE_ABILITIES) do
            if IsPlayerSpell and IsPlayerSpell(spellID) then
                local inRange = C_Spell.IsSpellInRange(spellID, "target")
                if inRange == true then return false end
                if inRange == false then return true end
            end
        end
    end

    return false
end
