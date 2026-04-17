--[[
    QUI Party Tracker — Spell Rules Database
    Maps aura detection (buff duration + evidence) to cooldown durations.
    Used by the Brain to attribute party member cooldown usage.
    All durations and cooldowns sourced from wowhead.com (12.0 Midnight).

    Rule fields:
      BuffDuration       number   Expected aura duration (seconds)
      Cooldown           number   Full cooldown duration (seconds)
      SpellId            number?  Canonical spell ID (for texture + talent CDR)
      BigDefensive       bool?    Matches BIG_DEFENSIVE auras
      ExternalDefensive  bool?    Matches EXTERNAL_DEFENSIVE auras
      Important          bool?    Matches IMPORTANT auras
      RequiresEvidence   str|tbl|false|nil  Evidence constraint
      MinDuration        bool?    measured >= expected - tolerance
      CanCancelEarly     bool?    measured <= expected + tolerance
      RequiresTalent     number?  Talent gate
      ExcludeIfTalent    number|tbl?  Talent exclusion
      Offensive          bool?    Marks as offensive cooldown
]]

local ADDON_NAME, ns = ...
local Helpers = ns.Helpers
local IsInRaid = IsInRaid
local UnitIsUnit = UnitIsUnit
local pairs = pairs

---------------------------------------------------------------------------
-- SHARED HELPER: Style cooldown frame countdown text size
-- Called by cc_icons, kick_timer, cooldown_display after positioning icons.
---------------------------------------------------------------------------
local function StyleCooldownText(cooldownFrame, fontSize)
    if not cooldownFrame then return end
    local ok, regions = pcall(function() return { cooldownFrame:GetRegions() } end)
    if not ok or not regions then return end
    local fontPath = "Fonts\\FRIZQT__.TTF"
    local LSM = ns.LSM
    if LSM then
        local db = ns.Helpers and ns.Helpers.GetCore and ns.Helpers.GetCore()
        local generalFont = db and db.db and db.db.profile and db.db.profile.general and db.db.profile.general.font
        if generalFont then
            fontPath = LSM:Fetch("font", generalFont) or fontPath
        end
    end
    for _, region in ipairs(regions) do
        if region and region.GetObjectType and region:GetObjectType() == "FontString" then
            pcall(region.SetFont, region, fontPath, fontSize, "OUTLINE")
        end
    end
end
ns.PartyTracker_StyleCooldownText = StyleCooldownText

---------------------------------------------------------------------------
-- SHARED HELPER: Get actual cooldown duration for a spell on a unit.
-- For the player: C_Spell.GetSpellCooldown returns real duration with
-- talent CDR. For party members: try LibOpenRaid, fall back to base.
---------------------------------------------------------------------------
---------------------------------------------------------------------------
-- SHARED HELPER: Set cooldown swirl using real CD data from the game.
-- For the player, C_Spell.GetSpellCooldown returns actual startTime +
-- duration (with talent CDR). These may be secret — pass directly to
-- SetCooldown (C-side handles secrets natively). Never read them in Lua.
-- For party members, fall back to baseDuration + GetTime().
---------------------------------------------------------------------------
local function SetRealCooldown(cooldownFrame, unit, spellId, baseDuration, reverseSwipe)
    if not cooldownFrame then return end
    if reverseSwipe ~= nil then
        pcall(cooldownFrame.SetReverse, cooldownFrame, reverseSwipe)
    end

    -- Player: use C_Spell.GetSpellCooldownDuration → DurationObject
    -- Pass directly to SetCooldownFromDurationObject (fully secret-safe).
    -- Delay slightly — UNIT_SPELLCAST_SUCCEEDED fires before the CD starts,
    -- so GetSpellCooldownDuration returns stale data at the instant of cast.
    if UnitIsUnit(unit, "player") and C_Spell.GetSpellCooldownDuration then
        -- Set base duration immediately so the swirl starts right away
        pcall(cooldownFrame.SetCooldown, cooldownFrame, GetTime(), baseDuration)
        -- Then overwrite with real DurationObject next frame
        C_Timer.After(0, function()
            local ok, durObj = pcall(C_Spell.GetSpellCooldownDuration, spellId)
            if ok and durObj and cooldownFrame.SetCooldownFromDurationObject then
                pcall(cooldownFrame.SetCooldownFromDurationObject, cooldownFrame, durObj)
            end
        end)
        return
    end

    -- Party members / fallback
    pcall(cooldownFrame.SetCooldown, cooldownFrame, GetTime(), baseDuration)
end
ns.PartyTracker_SetRealCooldown = SetRealCooldown

---------------------------------------------------------------------------
-- SHARED HELPERS: Used by cc_icons, kick_timer, cooldown_display
---------------------------------------------------------------------------
local function PT_IsActive()
    if IsInRaid() then return false end
    local db = Helpers.CreateDBGetter("quiGroupFrames")()
    return db and db.enabled == true
end
ns.PartyTracker_IsActive = PT_IsActive

local function PT_IsPartyUnit(unit)
    if not unit then return false end
    return unit == "party1" or unit == "party2" or unit == "party3" or unit == "party4"
end
ns.PartyTracker_IsPartyUnit = PT_IsPartyUnit

local function PT_GetFrameForUnit(unit)
    local GF = ns.QUI_GroupFrames
    if not GF or not GF.unitFrameMap then return nil end
    -- unitFrameMap values are arrays of frames (main raid + spotlight may both
    -- display the same unit). Party tracker only cares about the primary party
    -- frame, so return the first frame in the list.
    local list = GF.unitFrameMap[unit]
    if list and list[1] then return list[1] end
    if unit == "player" then
        for token, l in pairs(GF.unitFrameMap) do
            if UnitIsUnit(token, "player") and l[1] then
                return l[1]
            end
        end
    end
    return nil
end
ns.PartyTracker_GetFrameForUnit = PT_GetFrameForUnit

local Rules = {
    BySpec = {},
    ByClass = {},
    OffensiveSpellIds = {},
}
ns.PartyTracker_Rules = Rules

---------------------------------------------------------------------------
-- OFFENSIVE SPELL IDS (for display filtering)
---------------------------------------------------------------------------
Rules.OffensiveSpellIds = {
    -- Death Knight
    [51271]  = true,  -- Pillar of Frost
    [207289] = true,  -- Unholy Assault
    [275699] = true,  -- Apocalypse
    [42650]  = true,  -- Army of the Dead
    [1233448] = true, -- Dark Transformation
    -- Demon Hunter
    [191427] = true,  -- Metamorphosis (Havoc)
    -- Druid
    [194223] = true,  -- Celestial Alignment
    [29166]  = true,  -- Innervate
    -- Evoker
    [375087] = true,  -- Dragonrage
    -- Hunter
    [19574]  = true,  -- Bestial Wrath
    [288613] = true,  -- Trueshot
    [266779] = true,  -- Coordinated Assault
    -- Mage
    [12472]  = true,  -- Icy Veins
    [190319] = true,  -- Combustion
    -- Monk
    [137639] = true,  -- Storm, Earth, and Fire
    [123904] = true,  -- Invoke Xuen
    -- Paladin
    [31884]  = true,  -- Avenging Wrath
    -- Priest
    [10060]  = true,  -- Power Infusion
    [228260] = true,  -- Void Eruption
    [391109] = true,  -- Dark Ascension
    -- Rogue
    [13750]  = true,  -- Adrenaline Rush
    [121471] = true,  -- Shadow Blades
    -- Shaman
    [114051] = true,  -- Ascendance
    [51533]  = true,  -- Feral Spirit
    -- Warlock
    [205180] = true,  -- Summon Darkglare
    [265187] = true,  -- Summon Demonic Tyrant
    [1122]   = true,  -- Summon Infernal
    -- Warrior
    [1719]   = true,  -- Recklessness
}

---------------------------------------------------------------------------
-- SPEC-LEVEL RULES (checked first, higher priority)
---------------------------------------------------------------------------

-- Death Knight
Rules.BySpec[250] = { -- Blood
    { BuffDuration = 10, Cooldown = 90,  SpellId = 55233,  BigDefensive = true, RequiresEvidence = "Cast", CanCancelEarly = true }, -- Vampiric Blood
    { BuffDuration = 8,  Cooldown = 90,  SpellId = 49028,  BigDefensive = true, RequiresEvidence = "Cast" }, -- Dancing Rune Weapon
    { BuffDuration = 5,  Cooldown = 45,  SpellId = 48707,  BigDefensive = true, RequiresEvidence = "Cast" }, -- Anti-Magic Shell (Blood)
}
Rules.BySpec[251] = { -- Frost
    { BuffDuration = 5,  Cooldown = 45,  SpellId = 48707,  BigDefensive = true, RequiresEvidence = "Cast" }, -- Anti-Magic Shell (Frost)
    { BuffDuration = 12, Cooldown = 45,  SpellId = 51271,  Important = true, Offensive = true, RequiresEvidence = "Cast", CanCancelEarly = true }, -- Pillar of Frost
}
Rules.BySpec[252] = { -- Unholy
    { BuffDuration = 5,  Cooldown = 45,  SpellId = 48707,   BigDefensive = true, RequiresEvidence = "Cast" }, -- Anti-Magic Shell (Unholy)
    { BuffDuration = 15, Cooldown = 45,  SpellId = 1233448, Important = true, Offensive = true, RequiresEvidence = "Cast", MinDuration = true }, -- Dark Transformation
    { BuffDuration = 20, Cooldown = 90,  SpellId = 207289,  Important = true, Offensive = true, RequiresEvidence = "Cast", CanCancelEarly = true }, -- Unholy Assault
    { BuffDuration = 0,  Cooldown = 45,  SpellId = 275699,  Important = true, Offensive = true, RequiresEvidence = "Cast" }, -- Apocalypse
    { BuffDuration = 15, Cooldown = 90,  SpellId = 42650,   Important = true, Offensive = true, RequiresEvidence = "Cast" }, -- Army of the Dead
}

-- Demon Hunter
Rules.BySpec[577] = { -- Havoc
    { BuffDuration = 20, Cooldown = 120, SpellId = 191427, Important = true, Offensive = true, RequiresEvidence = "Cast", CanCancelEarly = true }, -- Metamorphosis
}
Rules.BySpec[581] = { -- Vengeance
    { BuffDuration = 6,  Cooldown = 90,  SpellId = 204021, BigDefensive = true, RequiresEvidence = "Cast" }, -- Fiery Brand
    { BuffDuration = 15, Cooldown = 240, SpellId = 187827, BigDefensive = true, RequiresEvidence = "Cast", CanCancelEarly = true }, -- Metamorphosis (Vengeance)
}

-- Druid
Rules.BySpec[102] = { -- Balance
    { BuffDuration = 20, Cooldown = 180, SpellId = 194223, Important = true, Offensive = true, RequiresEvidence = "Cast", CanCancelEarly = true }, -- Celestial Alignment
}
Rules.BySpec[103] = { -- Feral
    { BuffDuration = 6,  Cooldown = 180, SpellId = 61336,  BigDefensive = true, RequiresEvidence = "Cast" }, -- Survival Instincts
}
Rules.BySpec[104] = { -- Guardian
    { BuffDuration = 6,  Cooldown = 180, SpellId = 61336,  BigDefensive = true, RequiresEvidence = "Cast" }, -- Survival Instincts
}
Rules.BySpec[105] = { -- Restoration
    { BuffDuration = 8,  Cooldown = 180, SpellId = 29166,  ExternalDefensive = true, Offensive = true, RequiresEvidence = "Cast" }, -- Innervate
    { BuffDuration = 8,  Cooldown = 180, SpellId = 740,    Important = true, RequiresEvidence = "Cast" }, -- Tranquility
}

-- Evoker
Rules.BySpec[1467] = { -- Devastation
    { BuffDuration = 18, Cooldown = 120, SpellId = 375087, Important = true, Offensive = true, RequiresEvidence = "Cast", CanCancelEarly = true }, -- Dragonrage
}
Rules.BySpec[1468] = { -- Preservation
    { BuffDuration = 12, Cooldown = 90,  SpellId = 363916, BigDefensive = true, RequiresEvidence = "Cast" }, -- Obsidian Scales
}
Rules.BySpec[1473] = { -- Augmentation
    { BuffDuration = 12, Cooldown = 90,  SpellId = 363916, BigDefensive = true, RequiresEvidence = "Cast" }, -- Obsidian Scales
}

-- Hunter
Rules.BySpec[253] = { -- Beast Mastery
    { BuffDuration = 15, Cooldown = 30,  SpellId = 19574,  Important = true, Offensive = true, RequiresEvidence = "Cast", CanCancelEarly = true }, -- Bestial Wrath
    { BuffDuration = 8,  Cooldown = 180, SpellId = 186265, BigDefensive = true, RequiresEvidence = { "Cast", "UnitFlags" }, CanCancelEarly = true }, -- Aspect of the Turtle
}
Rules.BySpec[254] = { -- Marksmanship
    { BuffDuration = 15, Cooldown = 120, SpellId = 288613, Important = true, Offensive = true, RequiresEvidence = "Cast", CanCancelEarly = true }, -- Trueshot
    { BuffDuration = 8,  Cooldown = 180, SpellId = 186265, BigDefensive = true, RequiresEvidence = { "Cast", "UnitFlags" }, CanCancelEarly = true }, -- Aspect of the Turtle
}
Rules.BySpec[255] = { -- Survival
    { BuffDuration = 20, Cooldown = 120, SpellId = 266779, Important = true, Offensive = true, RequiresEvidence = "Cast", CanCancelEarly = true }, -- Coordinated Assault
    { BuffDuration = 8,  Cooldown = 180, SpellId = 186265, BigDefensive = true, RequiresEvidence = { "Cast", "UnitFlags" }, CanCancelEarly = true }, -- Aspect of the Turtle
}

-- Mage
Rules.BySpec[62] = { -- Arcane
    { BuffDuration = 25, Cooldown = 180, SpellId = 12472,  Important = true, Offensive = true, RequiresEvidence = "Cast", CanCancelEarly = true }, -- Icy Veins
}
Rules.BySpec[63] = { -- Fire
    { BuffDuration = 10, Cooldown = 60,  SpellId = 190319, Important = true, Offensive = true, RequiresEvidence = "Cast", CanCancelEarly = true }, -- Combustion
}

-- Monk
Rules.BySpec[268] = { -- Brewmaster
    { BuffDuration = 15, Cooldown = 360, SpellId = 115203, BigDefensive = true, RequiresEvidence = "Cast" }, -- Fortifying Brew
    { BuffDuration = 10, Cooldown = 120, SpellId = 122278, BigDefensive = true, RequiresEvidence = "Cast" }, -- Dampen Harm
}
Rules.BySpec[269] = { -- Windwalker
    { BuffDuration = 15, Cooldown = 75,  SpellId = 137639, Important = true, Offensive = true, RequiresEvidence = "Cast", CanCancelEarly = true }, -- Storm, Earth, and Fire
    { BuffDuration = 20, Cooldown = 60,  SpellId = 123904, Important = true, Offensive = true, RequiresEvidence = "Cast" }, -- Invoke Xuen
    { BuffDuration = 10, Cooldown = 120, SpellId = 122278, BigDefensive = true, RequiresEvidence = "Cast" }, -- Dampen Harm
}
Rules.BySpec[270] = { -- Mistweaver
    { BuffDuration = 15, Cooldown = 360, SpellId = 243435, BigDefensive = true, RequiresEvidence = "Cast" }, -- Fortifying Brew (MW)
    { BuffDuration = 0,  Cooldown = 180, SpellId = 115310, Important = true, RequiresEvidence = "Cast" }, -- Revival
    { BuffDuration = 0,  Cooldown = 180, SpellId = 388615, Important = true, RequiresEvidence = "Cast" }, -- Restoral
}

-- Paladin
Rules.BySpec[65] = { -- Holy
    { BuffDuration = 8,  Cooldown = 210, SpellId = 642,    BigDefensive = true, RequiresEvidence = "Cast", CanCancelEarly = true }, -- Divine Shield
    { BuffDuration = 24, Cooldown = 60,  SpellId = 31884,  Important = true, Offensive = true, RequiresEvidence = "Cast", CanCancelEarly = true }, -- Avenging Wrath (Holy)
    { BuffDuration = 10, Cooldown = 240, SpellId = 1022,   ExternalDefensive = true, RequiresEvidence = "Cast" }, -- Blessing of Protection
    { BuffDuration = 12, Cooldown = 120, SpellId = 6940,   ExternalDefensive = true, RequiresEvidence = "Cast" }, -- Blessing of Sacrifice
    { BuffDuration = 8,  Cooldown = 180, SpellId = 31821,  BigDefensive = true, RequiresEvidence = "Cast" }, -- Aura Mastery
}
Rules.BySpec[66] = { -- Protection
    { BuffDuration = 8,  Cooldown = 210, SpellId = 642,    BigDefensive = true, RequiresEvidence = "Cast", CanCancelEarly = true }, -- Divine Shield
    { BuffDuration = 15, Cooldown = 60,  SpellId = 31884,  Important = true, Offensive = true, RequiresEvidence = "Cast", CanCancelEarly = true }, -- Avenging Wrath (Prot)
    { BuffDuration = 10, Cooldown = 240, SpellId = 1022,   ExternalDefensive = true, RequiresEvidence = "Cast" }, -- Blessing of Protection
    { BuffDuration = 12, Cooldown = 120, SpellId = 6940,   ExternalDefensive = true, RequiresEvidence = "Cast" }, -- Blessing of Sacrifice
    { BuffDuration = 8,  Cooldown = 180, SpellId = 871,    BigDefensive = true, RequiresEvidence = "Cast" }, -- Shield Wall (via Guardian of Ancient Kings replacement)
    { BuffDuration = 8,  Cooldown = 180, SpellId = 12975,  BigDefensive = true, RequiresEvidence = "Cast" }, -- Last Stand
}
Rules.BySpec[70] = { -- Retribution
    { BuffDuration = 8,  Cooldown = 210, SpellId = 642,    BigDefensive = true, RequiresEvidence = "Cast", CanCancelEarly = true }, -- Divine Shield
    { BuffDuration = 20, Cooldown = 60,  SpellId = 31884,  Important = true, Offensive = true, RequiresEvidence = "Cast", CanCancelEarly = true }, -- Avenging Wrath (Ret)
    { BuffDuration = 10, Cooldown = 240, SpellId = 1022,   ExternalDefensive = true, RequiresEvidence = "Cast" }, -- Blessing of Protection
}

-- Priest
Rules.BySpec[256] = { -- Discipline
    { BuffDuration = 8,  Cooldown = 180, SpellId = 33206,  ExternalDefensive = true, RequiresEvidence = "Cast" }, -- Pain Suppression
    { BuffDuration = 10, Cooldown = 180, SpellId = 62618,  BigDefensive = true, RequiresEvidence = "Cast" }, -- Power Word: Barrier
}
Rules.BySpec[257] = { -- Holy
    { BuffDuration = 10, Cooldown = 180, SpellId = 47788,  ExternalDefensive = true, RequiresEvidence = "Cast" }, -- Guardian Spirit
    { BuffDuration = 5,  Cooldown = 180, SpellId = 64843,  Important = true, RequiresEvidence = "Cast" }, -- Divine Hymn
}
Rules.BySpec[258] = { -- Shadow
    { BuffDuration = 12, Cooldown = 120, SpellId = 15286,  BigDefensive = true, RequiresEvidence = "Cast" }, -- Vampiric Embrace
    { BuffDuration = 6,  Cooldown = 90,  SpellId = 47585,  BigDefensive = true, RequiresEvidence = "Cast" }, -- Dispersion
    { BuffDuration = 0,  Cooldown = 90,  SpellId = 228260, Important = true, Offensive = true, RequiresEvidence = "Cast" }, -- Void Eruption
    { BuffDuration = 20, Cooldown = 60,  SpellId = 391109, Important = true, Offensive = true, RequiresEvidence = "Cast", CanCancelEarly = true }, -- Dark Ascension
}

-- Rogue
Rules.BySpec[259] = { -- Assassination
    { BuffDuration = 5,  Cooldown = 60,  SpellId = 31224,  BigDefensive = true, RequiresEvidence = "Cast" }, -- Cloak of Shadows
    { BuffDuration = 10, Cooldown = 120, SpellId = 5277,   BigDefensive = true, RequiresEvidence = "Cast" }, -- Evasion
}
Rules.BySpec[260] = { -- Outlaw
    { BuffDuration = 15, Cooldown = 180, SpellId = 13750,  Important = true, Offensive = true, RequiresEvidence = "Cast", CanCancelEarly = true }, -- Adrenaline Rush
    { BuffDuration = 5,  Cooldown = 60,  SpellId = 31224,  BigDefensive = true, RequiresEvidence = "Cast" }, -- Cloak of Shadows
    { BuffDuration = 10, Cooldown = 120, SpellId = 5277,   BigDefensive = true, RequiresEvidence = "Cast" }, -- Evasion
}
Rules.BySpec[261] = { -- Subtlety
    { BuffDuration = 16, Cooldown = 90,  SpellId = 121471, Important = true, Offensive = true, RequiresEvidence = "Cast", CanCancelEarly = true }, -- Shadow Blades
    { BuffDuration = 5,  Cooldown = 60,  SpellId = 31224,  BigDefensive = true, RequiresEvidence = "Cast" }, -- Cloak of Shadows
}

-- Shaman
Rules.BySpec[262] = { -- Elemental
    { BuffDuration = 15, Cooldown = 180, SpellId = 114051, Important = true, Offensive = true, RequiresEvidence = "Cast", CanCancelEarly = true }, -- Ascendance
    { BuffDuration = 12, Cooldown = 120, SpellId = 108271, BigDefensive = true, RequiresEvidence = "Cast" }, -- Astral Shift
}
Rules.BySpec[263] = { -- Enhancement
    { BuffDuration = 15, Cooldown = 180, SpellId = 114051, Important = true, Offensive = true, RequiresEvidence = "Cast", CanCancelEarly = true }, -- Ascendance
    { BuffDuration = 15, Cooldown = 120, SpellId = 51533,  Important = true, Offensive = true, RequiresEvidence = "Cast" }, -- Feral Spirit
    { BuffDuration = 12, Cooldown = 120, SpellId = 108271, BigDefensive = true, RequiresEvidence = "Cast" }, -- Astral Shift
}
Rules.BySpec[264] = { -- Restoration
    { BuffDuration = 12, Cooldown = 120, SpellId = 108271, BigDefensive = true, RequiresEvidence = "Cast" }, -- Astral Shift
    { BuffDuration = 6,  Cooldown = 180, SpellId = 98008,  BigDefensive = true, RequiresEvidence = "Cast" }, -- Spirit Link Totem
    { BuffDuration = 10, Cooldown = 180, SpellId = 108280, Important = true, RequiresEvidence = "Cast" }, -- Healing Tide Totem
}

-- Warlock
Rules.BySpec[265] = { -- Affliction
    { BuffDuration = 20, Cooldown = 120, SpellId = 205180, Important = true, Offensive = true, RequiresEvidence = "Cast" }, -- Summon Darkglare
}
Rules.BySpec[266] = { -- Demonology
    { BuffDuration = 15, Cooldown = 60,  SpellId = 265187, Important = true, Offensive = true, RequiresEvidence = "Cast" }, -- Summon Demonic Tyrant
}
Rules.BySpec[267] = { -- Destruction
    { BuffDuration = 30, Cooldown = 120, SpellId = 1122,   Important = true, Offensive = true, RequiresEvidence = "Cast" }, -- Summon Infernal
}

-- Warrior
Rules.BySpec[71] = { -- Arms
    { BuffDuration = 12, Cooldown = 90,  SpellId = 1719,   Important = true, Offensive = true, RequiresEvidence = "Cast", CanCancelEarly = true }, -- Recklessness
    { BuffDuration = 8,  Cooldown = 120, SpellId = 118038, BigDefensive = true, RequiresEvidence = "Cast" }, -- Die by the Sword
}
Rules.BySpec[72] = { -- Fury
    { BuffDuration = 12, Cooldown = 90,  SpellId = 1719,   Important = true, Offensive = true, RequiresEvidence = "Cast", CanCancelEarly = true }, -- Recklessness
    { BuffDuration = 8,  Cooldown = 120, SpellId = 184364, BigDefensive = true, RequiresEvidence = "Cast" }, -- Enraged Regeneration
}
Rules.BySpec[73] = { -- Protection
    { BuffDuration = 8,  Cooldown = 180, SpellId = 12975,  BigDefensive = true, RequiresEvidence = "Cast" }, -- Last Stand
    { BuffDuration = 8,  Cooldown = 180, SpellId = 871,    BigDefensive = true, RequiresEvidence = "Cast" }, -- Shield Wall
}

---------------------------------------------------------------------------
-- CLASS-LEVEL RULES (fallback when no spec-level match)
---------------------------------------------------------------------------

Rules.ByClass.DEATHKNIGHT = {
    { BuffDuration = 5,  Cooldown = 45,  SpellId = 48707,  BigDefensive = true, RequiresEvidence = "Cast" }, -- Anti-Magic Shell
    { BuffDuration = 8,  Cooldown = 120, SpellId = 48792,  BigDefensive = true, RequiresEvidence = "Cast" }, -- Icebound Fortitude
    { BuffDuration = 6,  Cooldown = 240, SpellId = 51052,  BigDefensive = true, RequiresEvidence = "Cast" }, -- Anti-Magic Zone
}
Rules.ByClass.DEMONHUNTER = {
    { BuffDuration = 10, Cooldown = 60,  SpellId = 198589, BigDefensive = true, RequiresEvidence = "Cast" }, -- Blur
    { BuffDuration = 8,  Cooldown = 300, SpellId = 196718, BigDefensive = true, RequiresEvidence = "Cast" }, -- Darkness
}
Rules.ByClass.DRUID = {
    { BuffDuration = 8,  Cooldown = 60,  SpellId = 22812,  BigDefensive = true, RequiresEvidence = "Cast" }, -- Barkskin
    { BuffDuration = 6,  Cooldown = 180, SpellId = 61336,  BigDefensive = true, RequiresEvidence = "Cast" }, -- Survival Instincts
    { BuffDuration = 8,  Cooldown = 120, SpellId = 106898, Important = true, RequiresEvidence = "Cast" }, -- Stampeding Roar
}
Rules.ByClass.EVOKER = {
    { BuffDuration = 12, Cooldown = 90,  SpellId = 363916, BigDefensive = true, RequiresEvidence = "Cast" }, -- Obsidian Scales
}
Rules.ByClass.HUNTER = {
    { BuffDuration = 8,  Cooldown = 180, SpellId = 186265, BigDefensive = true, RequiresEvidence = { "Cast", "UnitFlags" }, CanCancelEarly = true }, -- Aspect of the Turtle
}
Rules.ByClass.MAGE = {
    { BuffDuration = 10, Cooldown = 210, SpellId = 45438,  BigDefensive = true, RequiresEvidence = { "Cast", "UnitFlags" }, CanCancelEarly = true }, -- Ice Block
    { BuffDuration = 25, Cooldown = 180, SpellId = 12472,  Important = true, Offensive = true, RequiresEvidence = "Cast", CanCancelEarly = true }, -- Icy Veins
}
Rules.ByClass.MONK = {
    { BuffDuration = 15, Cooldown = 360, SpellId = 115203, BigDefensive = true, RequiresEvidence = "Cast" }, -- Fortifying Brew
    { BuffDuration = 10, Cooldown = 120, SpellId = 122278, BigDefensive = true, RequiresEvidence = "Cast" }, -- Dampen Harm
}
Rules.ByClass.PALADIN = {
    { BuffDuration = 8,  Cooldown = 210, SpellId = 642,    BigDefensive = true, RequiresEvidence = "Cast", CanCancelEarly = true }, -- Divine Shield
    { BuffDuration = 10, Cooldown = 240, SpellId = 1022,   ExternalDefensive = true, RequiresEvidence = "Cast" }, -- Blessing of Protection
    { BuffDuration = 12, Cooldown = 120, SpellId = 6940,   ExternalDefensive = true, RequiresEvidence = "Cast" }, -- Blessing of Sacrifice
}
Rules.ByClass.PRIEST = {
    { BuffDuration = 15, Cooldown = 120, SpellId = 10060,  ExternalDefensive = true, Offensive = true, RequiresEvidence = "Cast" }, -- Power Infusion
}
Rules.ByClass.ROGUE = {
    { BuffDuration = 5,  Cooldown = 60,  SpellId = 31224,  BigDefensive = true, RequiresEvidence = "Cast" }, -- Cloak of Shadows
    { BuffDuration = 10, Cooldown = 120, SpellId = 5277,   BigDefensive = true, RequiresEvidence = "Cast" }, -- Evasion
}
Rules.ByClass.SHAMAN = {
    { BuffDuration = 12, Cooldown = 120, SpellId = 108271, BigDefensive = true, RequiresEvidence = "Cast" }, -- Astral Shift
}
Rules.ByClass.WARLOCK = {
    { BuffDuration = 8,  Cooldown = 180, SpellId = 104773, BigDefensive = true, RequiresEvidence = "Cast" }, -- Unending Resolve
    { BuffDuration = 20, Cooldown = 60,  SpellId = 108416, BigDefensive = true, RequiresEvidence = "Cast" }, -- Dark Pact
}
Rules.ByClass.WARRIOR = {
    { BuffDuration = 10, Cooldown = 180, SpellId = 97462,  BigDefensive = true, RequiresEvidence = "Cast" }, -- Rallying Cry
}
