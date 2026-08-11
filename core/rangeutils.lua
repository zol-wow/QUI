local ADDON_NAME, ns = ...

local RangeUtils = {}
ns.RangeUtils = RangeUtils

RangeUtils.MELEE_RANGE_ABILITIES = {
    96231,
    6552,
    1766,
    116705,
    183752,
    228478,
    263642,
    49143,
    55090,
    206930,
    100780,
    100784,
    107428,
    5221,
    3252,
    1822,
    22568,
    22570,
    33917,
    6807,
}

RangeUtils.MID_RANGE_ABILITIES = {
    361469,
    356995,
    382266,
    357211,
    355913,
    360995,
    364343,
    366155,
    473662,
    1226019,
    473728,
}

local meleeSet = {}
for _, id in ipairs(RangeUtils.MELEE_RANGE_ABILITIES) do meleeSet[id] = true end
local midSet = {}
for _, id in ipairs(RangeUtils.MID_RANGE_ABILITIES) do midSet[id] = true end

local meleeSlots = {}
local midSlots = {}
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

local cacheFrame = CreateFrame("Frame")
cacheFrame:RegisterEvent("SPELLS_CHANGED")
cacheFrame:RegisterEvent("UPDATE_MACROS")
cacheFrame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
cacheFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
cacheFrame:SetScript("OnEvent", function()
    cacheValid = false
end)

function RangeUtils.HasAttackableTarget()
    if not UnitExists("target") then return false end
    if not UnitCanAttack("player", "target") then return false end
    if UnitIsDeadOrGhost("target") then return false end
    return true
end

function RangeUtils.IsOutOfMeleeRange()
    if not RangeUtils.HasAttackableTarget() then return false end

    EnsureCache()

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

    if IsSpellInRange then
        local attackInRange = IsSpellInRange("Attack", "target")
        if attackInRange == 1 then return false end
        if attackInRange == 0 then return true end
    end

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

function RangeUtils.IsOutOfMidRange()
    if not RangeUtils.HasAttackableTarget() then return false end

    EnsureCache()

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
