--[[
    QUI Party Tracker — CC Icons
    Shows party members' crowd control abilities as static icons on frames.
    Cooldown swirl when used. Same UNIT_SPELLCAST_SUCCEEDED + pcall pattern
    as kick_timer and cooldown_display.
    Only tracks CC spells that have actual cooldowns (not Polymorph/Fear/etc).
]]

local ADDON_NAME, ns = ...
local Helpers = ns.Helpers
local GetDB = Helpers.CreateDBGetter("quiGroupFrames")

local CreateFrame = CreateFrame
local UnitExists = UnitExists
local UnitIsDeadOrGhost = UnitIsDeadOrGhost
local UnitClass = UnitClass
local UnitIsUnit = UnitIsUnit
local UnitIsEnemy = UnitIsEnemy
local C_Spell = C_Spell
local C_Timer = C_Timer
local GetTime = GetTime
local pcall = pcall
local pairs = pairs
local ipairs = ipairs
local wipe = wipe
local IsInRaid = IsInRaid
local GetNumGroupMembers = GetNumGroupMembers
local IsPlayerSpell = IsPlayerSpell

local CCIcons = {}
ns.PartyTracker_CCIcons = CCIcons

local MAX_ICONS = 5
local GF = nil
local SpecCache = nil

local IsActive = ns.PartyTracker_IsActive
local IsPartyUnit = ns.PartyTracker_IsPartyUnit

---------------------------------------------------------------------------
-- CC SPELL DATABASE — only spells with real cooldowns
-- { id = spellID, cd = cooldown in seconds }
---------------------------------------------------------------------------
local CC_BY_CLASS = {
    DEATHKNIGHT = {
        { id = 108194, cd = 45 },  -- Asphyxiate (Frost/Unholy talent)
    },
    DEMONHUNTER = {
        { id = 179057, cd = 45 },  -- Chaos Nova
        { id = 211881, cd = 30 },  -- Fel Eruption
    },
    DRUID = {
        { id = 5211,   cd = 60 },  -- Mighty Bash
        { id = 102359, cd = 30 },  -- Mass Entanglement
    },
    EVOKER = {
        { id = 357210, cd = 90 },  -- Deep Breath (lands with stun)
    },
    HUNTER = {
        { id = 109248, cd = 45 },  -- Binding Shot
        { id = 19386,  cd = 45 },  -- Wyvern Sting
        { id = 187650, cd = 25 },  -- Freezing Trap
    },
    MAGE = {
        { id = 157981, cd = 25 },  -- Blast Wave
        { id = 31661,  cd = 45 },  -- Dragon's Breath
    },
    MONK = {
        { id = 119381, cd = 60 },  -- Leg Sweep
        { id = 116844, cd = 45 },  -- Ring of Peace
    },
    PALADIN = {
        { id = 853,    cd = 45 },  -- Hammer of Justice
        { id = 20066,  cd = 15 },  -- Repentance
    },
    PRIEST = {
        { id = 205369, cd = 30 },  -- Mind Bomb
        { id = 8122,   cd = 45 },  -- Psychic Scream
    },
    ROGUE = {
        { id = 1833,   cd = 20 },  -- Cheap Shot (via Stealth)
        { id = 408,    cd = 20 },  -- Kidney Shot
    },
    SHAMAN = {
        { id = 51514,  cd = 45 },  -- Hex
        { id = 192058, cd = 60 },  -- Capacitor Totem
    },
    WARLOCK = {
        { id = 30283,  cd = 60 },  -- Shadowfury
        { id = 6789,   cd = 45 },  -- Mortal Coil
    },
    WARRIOR = {
        { id = 46968,  cd = 20 },  -- Shockwave
        { id = 107570, cd = 30 },  -- Storm Bolt
        { id = 5246,   cd = 90 },  -- Intimidating Shout
    },
}

-- Spec-specific CC overrides — used INSTEAD of CC_BY_CLASS when spec is known
local CC_BY_SPEC = {
    [250] = { -- Blood DK
        { id = 221562, cd = 45 },  -- Asphyxiate (Blood)
    },
    [257] = { -- Holy Priest
        { id = 88625,  cd = 60 },  -- Holy Word: Chastise
        { id = 205369, cd = 30 },  -- Mind Bomb
        { id = 8122,   cd = 45 },  -- Psychic Scream
    },
}

-- Reverse lookup: spellId → { cd }
local CC_LOOKUP = {}
for _, spells in pairs(CC_BY_CLASS) do
    for _, spell in ipairs(spells) do
        CC_LOOKUP[spell.id] = { cd = spell.cd }
    end
end
for _, spells in pairs(CC_BY_SPEC) do
    for _, spell in ipairs(spells) do
        CC_LOOKUP[spell.id] = { cd = spell.cd }
    end
end

---------------------------------------------------------------------------
-- SPELL TEXTURE CACHE
---------------------------------------------------------------------------
local textureCache = {}

local function GetSpellTexture(spellId)
    if not spellId then return nil end
    if textureCache[spellId] then return textureCache[spellId] end
    local ok, tex = pcall(C_Spell.GetSpellTexture, spellId)
    if ok and tex then
        textureCache[spellId] = tex
        return tex
    end
    return nil
end

---------------------------------------------------------------------------
-- ICON CREATION
---------------------------------------------------------------------------

local function GetPixelSize(frame)
    local QUICore = ns.Addon
    return QUICore and QUICore.GetPixelSize and QUICore:GetPixelSize(frame) or 1
end

local function CreateIcon(parent, px)
    local icon = CreateFrame("Frame", nil, parent)
    icon:SetSize(20, 20)
    icon:SetFrameStrata("HIGH")
    icon:SetFrameLevel(100)

    local border = icon:CreateTexture(nil, "BACKGROUND")
    border:SetAllPoints()
    border:SetTexture("Interface\\Buttons\\WHITE8x8")
    border:SetVertexColor(0, 0, 0, 1)

    local tex = icon:CreateTexture(nil, "ARTWORK")
    tex:SetPoint("TOPLEFT", px, -px)
    tex:SetPoint("BOTTOMRIGHT", -px, px)
    tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    icon.icon = tex

    local cd = CreateFrame("Cooldown", nil, icon, "CooldownFrameTemplate")
    cd:SetPoint("TOPLEFT", px, -px)
    cd:SetPoint("BOTTOMRIGHT", -px, px)
    cd:SetDrawEdge(false)
    cd:SetDrawSwipe(true)
    cd:SetReverse(true)
    cd:SetHideCountdownNumbers(false)
    icon.cooldown = cd

    if icon.SetMouseClickEnabled then icon:SetMouseClickEnabled(false) end
    icon:EnableMouse(false)
    icon:Hide()
    return icon
end

---------------------------------------------------------------------------
-- GROWTH OFFSETS
---------------------------------------------------------------------------
local GROWTH = {
    LEFT  = function(size, spacing) return -(size + spacing), 0 end,
    RIGHT = function(size, spacing) return (size + spacing), 0 end,
    UP    = function(size, spacing) return 0, (size + spacing) end,
    DOWN  = function(size, spacing) return 0, -(size + spacing) end,
}

---------------------------------------------------------------------------
-- SETTINGS
---------------------------------------------------------------------------

local function GetSettings(isRaid)
    local db = GetDB()
    if not db then return nil end
    local vdb = isRaid and db.raid or db.party
    return vdb and vdb.partyTracker and vdb.partyTracker.ccIcons
end

---------------------------------------------------------------------------
-- LAZY ICON CREATION
---------------------------------------------------------------------------

local function EnsureIcons(frame)
    if frame._ccIcons then return frame._ccIcons end
    local px = frame._partyTrackerPx or GetPixelSize(frame)
    local icons = {}
    for i = 1, MAX_ICONS do
        icons[i] = CreateIcon(frame, px)
    end
    frame._ccIcons = icons
    return icons
end

---------------------------------------------------------------------------
-- ACTIVE COOLDOWNS STATE
---------------------------------------------------------------------------
local activeCooldowns = {}  -- unit → { [spellId] = { startTime, cooldown, timer } }

---------------------------------------------------------------------------
-- CHECK IF UNIT HAS SPELL
---------------------------------------------------------------------------

local openRaidLib = nil

local function UnitHasSpell(unit, spellId)
    if UnitIsUnit(unit, "player") then
        local ok, known = pcall(IsPlayerSpell, spellId)
        if ok then return known end
        return true
    end

    if not openRaidLib then
        openRaidLib = LibStub and LibStub:GetLibrary("LibOpenRaid-1.0", true)
    end
    if openRaidLib then
        local unitCDs = openRaidLib.GetUnitCooldowns(unit)
        if unitCDs and next(unitCDs) then
            return unitCDs[spellId] ~= nil
        end
    end

    return true
end

---------------------------------------------------------------------------
-- STATIC ABILITY LIST (CC spells for unit's class that they have)
---------------------------------------------------------------------------

local function GetStaticAbilities(unit)
    local _, classToken = UnitClass(unit)
    if not classToken then return {} end

    -- Check spec first — use spec-specific CC list if available
    SpecCache = SpecCache or ns.PartyTracker_SpecCache
    local specId = SpecCache and SpecCache.GetSpec(unit)
    local spellList
    if specId and CC_BY_SPEC[specId] then
        spellList = CC_BY_SPEC[specId]
    else
        spellList = CC_BY_CLASS[classToken]
    end
    if not spellList then return {} end

    local abilities = {}
    for _, spell in ipairs(spellList) do
        if UnitHasSpell(unit, spell.id) then
            abilities[#abilities + 1] = spell
        end
    end
    return abilities
end

---------------------------------------------------------------------------
-- RESOLVE UNIT → FRAME
---------------------------------------------------------------------------

local GetFrameForUnit = ns.PartyTracker_GetFrameForUnit

---------------------------------------------------------------------------
-- UPDATE DISPLAY
---------------------------------------------------------------------------

function CCIcons.UpdateFrame(frame)
    if not frame then return end

    local isRaid = frame._isRaid
    local settings = GetSettings(isRaid)
    local unit = frame.unit

    if not settings or not settings.enabled or not unit or not UnitExists(unit) or UnitIsDeadOrGhost(unit) then
        if frame._ccIcons then
            for _, icon in ipairs(frame._ccIcons) do icon:Hide() end
        end
        return
    end

    local icons = EnsureIcons(frame)

    local maxIcons = settings.maxIcons or 3
    local iconSize = settings.iconSize or 20
    local anchor = settings.anchor or "LEFT"
    local growDir = settings.growDirection or "LEFT"
    local spacing = settings.spacing or 2
    local offsetX = settings.offsetX or -4
    local offsetY = settings.offsetY or 0
    local reverseSwipe = settings.reverseSwipe ~= false

    local growFn = GROWTH[growDir] or GROWTH.LEFT
    local stepX, stepY = growFn(iconSize, spacing)

    local unitCDs = activeCooldowns[unit] or {}
    if unit ~= "player" and UnitIsUnit(unit, "player") then
        local playerCDs = activeCooldowns["player"]
        if playerCDs then
            if not activeCooldowns[unit] then activeCooldowns[unit] = {} end
            unitCDs = activeCooldowns[unit]
            for k, v in pairs(playerCDs) do
                if not unitCDs[k] then unitCDs[k] = v end
            end
        end
    end

    local abilities = GetStaticAbilities(unit)
    local idx = 0

    for _, spell in ipairs(abilities) do
        idx = idx + 1
        if idx > maxIcons or idx > MAX_ICONS then break end

        local icon = icons[idx]
        icon:SetSize(iconSize, iconSize)
        icon:SetFrameStrata("HIGH")
        icon:SetFrameLevel(100)
        icon:ClearAllPoints()
        icon:SetPoint(anchor, frame, anchor, offsetX + (idx - 1) * stepX, offsetY + (idx - 1) * stepY)

        local StyleCooldownText = ns.PartyTracker_StyleCooldownText
        if StyleCooldownText then StyleCooldownText(icon.cooldown, iconSize * 0.55) end

        local texture = GetSpellTexture(spell.id)
        if texture then
            pcall(icon.icon.SetTexture, icon.icon, texture)
        end

        local cdData = unitCDs[spell.id]
        local cd = icon.cooldown
        if cdData and cdData.startTime and cdData.cooldown then
            icon:SetAlpha(1.0)
            if cd then
                local SetRealCooldown = ns.PartyTracker_SetRealCooldown
                if SetRealCooldown and cdData.unit then
                    SetRealCooldown(cd, cdData.unit, spell.id, cdData.cooldown, reverseSwipe)
                else
                    pcall(cd.SetReverse, cd, reverseSwipe)
                    pcall(cd.SetCooldown, cd, cdData.startTime, cdData.cooldown)
                end
            end
        else
            icon:SetAlpha(1.0)
            if cd and cd.Clear then cd:Clear() end
        end

        icon:Show()
    end

    for i = idx + 1, MAX_ICONS do
        icons[i]:Hide()
    end
end

---------------------------------------------------------------------------
-- REFRESH ALL
---------------------------------------------------------------------------

function CCIcons.RefreshAll()
    GF = GF or ns.QUI_GroupFrames
    if not GF then return end
    if GF.unitFrameMap then
        for _, frame in pairs(GF.unitFrameMap) do
            CCIcons.UpdateFrame(frame)
        end
    end
end

---------------------------------------------------------------------------
-- CAST-BASED DETECTION (UNIT_SPELLCAST_SUCCEEDED)
---------------------------------------------------------------------------

local function OnSpellcastSucceeded(unit, castGUID, spellID)
    if not spellID then return end
    if not IsActive() then return end
    if not IsPartyUnit(unit) then return end
    if UnitIsEnemy("player", unit) then return end

    local ok, info = pcall(function() return CC_LOOKUP[spellID] end)
    if not ok or not info then return end

    if not activeCooldowns[unit] then activeCooldowns[unit] = {} end
    local unitCDs = activeCooldowns[unit]

    if unitCDs[spellID] and unitCDs[spellID].timer then
        unitCDs[spellID].timer:Cancel()
    end

    local startTime = GetTime()
    local cooldown = info.cd  -- base duration for cleanup timer

    unitCDs[spellID] = {
        startTime = startTime,
        cooldown = cooldown,
        unit = unit,
        timer = C_Timer.NewTimer(cooldown, function()
            if unitCDs[spellID] then
                unitCDs[spellID] = nil
            end
            local frame = GetFrameForUnit(unit)
            if frame then CCIcons.UpdateFrame(frame) end
        end),
    }

    local frame = GetFrameForUnit(unit)
    if frame then CCIcons.UpdateFrame(frame) end
end

---------------------------------------------------------------------------
-- INIT + EVENT REGISTRATION
---------------------------------------------------------------------------

C_Timer.After(0, function()
    CCIcons.RefreshAll()
end)

C_Timer.After(0, function()
    local eventFrame = CreateFrame("Frame")
    eventFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
    eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")

    local function RegisterUnits()
        eventFrame:UnregisterEvent("UNIT_SPELLCAST_SUCCEEDED")
        local units = { "player" }
        local numGroup = GetNumGroupMembers() or 0
        if numGroup > 0 then
            local prefix = IsInRaid() and "raid" or "party"
            local max = IsInRaid() and numGroup or (numGroup - 1)
            for i = 1, max do
                units[#units + 1] = prefix .. i
            end
        end
        if #units > 0 then
            eventFrame:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", unpack(units))
        end
    end

    eventFrame:SetScript("OnEvent", function(_, event, arg1, arg2, arg3)
        if event == "UNIT_SPELLCAST_SUCCEEDED" then
            OnSpellcastSucceeded(arg1, arg2, arg3)
        else
            for u in pairs(activeCooldowns) do
                if not UnitExists(u) then
                    for _, cdData in pairs(activeCooldowns[u]) do
                        if cdData.timer then cdData.timer:Cancel() end
                    end
                    activeCooldowns[u] = nil
                end
            end
            RegisterUnits()
            CCIcons.RefreshAll()
        end
    end)

    RegisterUnits()
end)
