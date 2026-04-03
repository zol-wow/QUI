--[[
    QUI Party Tracker — Kick Timer
    Shows each party member's interrupt spell icon on their frame.
    Always visible — dimmed when ready, cooldown swirl when on CD.
    Tracks via UNIT_SPELLCAST_SUCCEEDED with secret-safe spellID handling.
]]

local ADDON_NAME, ns = ...
local Helpers = ns.Helpers
local GetDB = Helpers.CreateDBGetter("quiGroupFrames")

local CreateFrame = CreateFrame
local UnitExists = UnitExists
local UnitIsEnemy = UnitIsEnemy
local UnitClass = UnitClass
local GetTime = GetTime
local C_Spell = C_Spell
local C_Timer = C_Timer
local pcall = pcall
local ipairs = ipairs
local pairs = pairs
local issecretvalue = _G.issecretvalue
local IsInRaid = IsInRaid
local GetNumGroupMembers = GetNumGroupMembers

local KickTimer = {}
ns.PartyTracker_KickTimer = KickTimer

local GF = nil
local SpecCache = nil

---------------------------------------------------------------------------
-- INTERRUPT SPELL DATABASE — one primary interrupt per class
---------------------------------------------------------------------------
local INTERRUPT_BY_CLASS = {
    DEATHKNIGHT = { id = 47528,  cd = 15 },  -- Mind Freeze
    DEMONHUNTER = { id = 183752, cd = 15 },  -- Disrupt
    DRUID       = { id = 106839, cd = 15 },  -- Skull Bash
    EVOKER      = { id = 351338, cd = 20 },  -- Quell
    HUNTER      = { id = 147362, cd = 24 },  -- Counter Shot
    MAGE        = { id = 2139,   cd = 24 },  -- Counterspell
    MONK        = { id = 116705, cd = 15 },  -- Spear Hand Strike
    PALADIN     = { id = 96231,  cd = 15 },  -- Rebuke
    PRIEST      = { id = 15487,  cd = 30 },  -- Silence
    ROGUE       = { id = 1766,   cd = 15 },  -- Kick
    SHAMAN      = { id = 57994,  cd = 30 },  -- Wind Shear
    WARLOCK     = { id = 19647,  cd = 24 },  -- Spell Lock
    WARRIOR     = { id = 6552,   cd = 15 },  -- Pummel
}

-- Spec overrides: false = no interrupt, table = different spell than class default
local INTERRUPT_BY_SPEC = {
    [102] = { id = 78675,  cd = 60 },  -- Balance Druid: Solar Beam
    [105] = false,                       -- Resto Druid: no interrupt
    [256] = false,                       -- Disc Priest: no interrupt
    [257] = false,                       -- Holy Priest: no interrupt
}

-- Reverse lookup for non-secret spellID fast path
local INTERRUPT_LOOKUP = {}
for class, info in pairs(INTERRUPT_BY_CLASS) do
    INTERRUPT_LOOKUP[info.id] = { cd = info.cd, class = class }
end
for _, info in pairs(INTERRUPT_BY_SPEC) do
    if info and info.id then
        INTERRUPT_LOOKUP[info.id] = { cd = info.cd }
    end
end

---------------------------------------------------------------------------
-- ICON TEXTURE CACHE
---------------------------------------------------------------------------
local textureCache = {}

local function GetInterruptTexture(spellID)
    if textureCache[spellID] then return textureCache[spellID] end
    local ok, tex = pcall(C_Spell.GetSpellTexture, spellID)
    if ok and tex then
        textureCache[spellID] = tex
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

local function CreateKickIcon(parent, px)
    local icon = CreateFrame("Frame", nil, parent)
    icon:SetSize(20, 20)
    icon:SetFrameStrata("HIGH")
    icon:SetFrameLevel(100)

    local tex = icon:CreateTexture(nil, "ARTWORK")
    tex:SetAllPoints()
    tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    icon.icon = tex

    -- Border via texture overlay (avoids BackdropTemplate overhead)
    local border = icon:CreateTexture(nil, "OVERLAY")
    border:SetAllPoints()
    border:SetTexture("Interface\\Buttons\\WHITE8x8")
    border:SetVertexColor(0, 0, 0, 1)
    icon.border = border

    local inner = icon:CreateTexture(nil, "OVERLAY", nil, 1)
    inner:SetPoint("TOPLEFT", px, -px)
    inner:SetPoint("BOTTOMRIGHT", -px, px)
    inner:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    icon.innerIcon = inner

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
    return icon
end

---------------------------------------------------------------------------
-- SETTINGS
---------------------------------------------------------------------------

local function GetSettings(isRaid)
    local db = GetDB()
    if not db then return nil end
    local vdb = isRaid and db.raid or db.party
    return vdb and vdb.partyTracker and vdb.partyTracker.kickTimer
end

---------------------------------------------------------------------------
-- LAZY ICON CREATION
---------------------------------------------------------------------------

local function EnsureKickIcon(frame)
    if frame._kickIcon then return end
    local px = frame._partyTrackerPx or GetPixelSize(frame)
    frame._kickIcon = CreateKickIcon(frame, px)
    frame._kickTimer = { active = false, timer = nil, key = 0 }
end

---------------------------------------------------------------------------
-- SHOW STATIC ICON (always visible for unit's class interrupt)
---------------------------------------------------------------------------

-- Resolve the interrupt info for a unit, checking spec overrides first
local function GetInterruptInfo(unit)
    SpecCache = SpecCache or ns.PartyTracker_SpecCache
    local specId = SpecCache and SpecCache.GetSpec(unit)
    if specId and INTERRUPT_BY_SPEC[specId] ~= nil then
        -- false means this spec has no interrupt
        return INTERRUPT_BY_SPEC[specId]
    end
    local _, classToken = UnitClass(unit)
    return classToken and INTERRUPT_BY_CLASS[classToken]
end

local function ShowStaticIcon(frame)
    local isRaid = frame._isRaid
    local settings = GetSettings(isRaid)
    if not settings or not settings.enabled then
        if frame._kickIcon then frame._kickIcon:Hide() end
        return
    end

    local unit = frame.unit
    if not unit or not UnitExists(unit) then
        if frame._kickIcon then frame._kickIcon:Hide() end
        return
    end

    local classInfo = GetInterruptInfo(unit)
    if not classInfo then
        if frame._kickIcon then frame._kickIcon:Hide() end
        return
    end

    EnsureKickIcon(frame)
    local icon = frame._kickIcon
    if not icon then return end

    -- Size + position
    local size = settings.iconSize or 20
    icon:SetSize(size, size)
    icon:ClearAllPoints()
    local anchor = settings.anchor or "TOPRIGHT"
    local offsetX = settings.offsetX or 2
    local offsetY = settings.offsetY or 2
    icon:SetPoint(anchor, frame, anchor, offsetX, offsetY)

    -- Scale countdown text to icon size
    local StyleCooldownText = ns.PartyTracker_StyleCooldownText
    if StyleCooldownText then StyleCooldownText(icon.cooldown, size * 0.55) end

    -- Set texture to this class's interrupt spell
    local texture = GetInterruptTexture(classInfo.id)
    if texture then
        pcall(icon.icon.SetTexture, icon.icon, texture)
        if icon.innerIcon then pcall(icon.innerIcon.SetTexture, icon.innerIcon, texture) end
    end

    -- Ensure strata is above the group frame (may be reset by layout mode)
    icon:SetFrameStrata("HIGH")
    icon:SetFrameLevel(100)

    icon:Show()
end

---------------------------------------------------------------------------
-- START COOLDOWN SWIRL (when interrupt is used)
---------------------------------------------------------------------------

local function StartKickCooldown(frame, unit, spellID, baseDuration)
    local icon = frame._kickIcon
    local state = frame._kickTimer
    if not icon or not state then return end

    local cd = icon.cooldown
    if cd then
        local isRaid = frame._isRaid
        local settings = GetSettings(isRaid)
        local reverseSwipe = settings and settings.reverseSwipe ~= false
        -- Pass real CD data directly to C-side (handles secret values natively)
        local SetRealCooldown = ns.PartyTracker_SetRealCooldown
        if SetRealCooldown then
            SetRealCooldown(cd, unit, spellID, baseDuration, reverseSwipe)
        else
            pcall(cd.SetReverse, cd, reverseSwipe)
            pcall(cd.SetCooldown, cd, GetTime(), baseDuration)
        end
    end

    local duration = baseDuration  -- for cleanup timer (needs real number)

    -- Cancel existing cleanup timer
    if state.timer then state.timer:Cancel() end

    local key = math.random(1000000)
    state.active = true
    state.key = key

    -- When cooldown expires, clear swirl (icon stays visible)
    state.timer = C_Timer.NewTimer(duration, function()
        if state.key == key then
            state.active = false
            state.timer = nil
            if cd and cd.Clear then cd:Clear() end
        end
    end)
end

---------------------------------------------------------------------------
-- UPDATE / REFRESH
---------------------------------------------------------------------------

function KickTimer.UpdateFrame(frame)
    if not frame then return end
    ShowStaticIcon(frame)
end

function KickTimer.RefreshAll()
    GF = GF or ns.QUI_GroupFrames
    if not GF then return end
    -- Use unitFrameMap instead of allFrames — allFrames is wiped during
    -- RefreshSettings and may be empty when testMode causes an early return
    -- in UpdateHeaderVisibility (e.g. during layout mode).
    if GF.unitFrameMap then
        for _, frame in pairs(GF.unitFrameMap) do
            ShowStaticIcon(frame)
        end
    end
end

---------------------------------------------------------------------------
-- EVENT HANDLING
-- UNIT_SPELLCAST_SUCCEEDED: spellID (arg3) is secret in combat.
-- When secret, compare against the unit's class interrupt via equality.
---------------------------------------------------------------------------

-- Resolve unit → frame, handling "player" → party/raid token mapping
local function GetFrameForUnit(unit)
    GF = GF or ns.QUI_GroupFrames
    if not GF or not GF.unitFrameMap then return nil end

    local frame = GF.unitFrameMap[unit]
    if not frame and unit == "player" then
        for token, f in pairs(GF.unitFrameMap) do
            if UnitIsUnit(token, "player") then
                return f
            end
        end
    end
    return frame
end

-- Track recent casts from party members (for UNIT_SPELLCAST_INTERRUPTED matching)
local recentCasts = {}  -- unit → GetTime()

local function OnSpellcastSucceeded(unit, castGUID, spellID)
    if UnitIsEnemy("player", unit) then return end

    -- Record cast time for interrupt matching (combat fallback)
    recentCasts[unit] = GetTime()

    -- Player: don't read spellID. Use event as trigger, check the known
    -- interrupt spell via C_Spell.GetSpellCooldownDuration (C-side).
    if UnitIsUnit(unit, "player") and C_Spell.GetSpellCooldownDuration then
        local classInfo = GetInterruptInfo(unit)
        if classInfo then
            local ok, durObj = pcall(C_Spell.GetSpellCooldownDuration, classInfo.id)
            if ok and durObj then
                local frame = GetFrameForUnit(unit)
                if frame and frame._kickIcon then
                    local cd = frame._kickIcon.cooldown
                    if cd then
                        local isRaid = frame._isRaid
                        local settings = GetSettings(isRaid)
                        local reverseSwipe = settings and settings.reverseSwipe ~= false
                        pcall(cd.SetReverse, cd, reverseSwipe)
                        pcall(cd.SetCooldownFromDurationObject, cd, durObj)
                    end
                    -- Start cleanup timer with base duration
                    local state = frame._kickTimer
                    if state then
                        if state.timer then state.timer:Cancel() end
                        local key = math.random(1000000)
                        state.active = true
                        state.key = key
                        state.timer = C_Timer.NewTimer(classInfo.cd, function()
                            if state.key == key then
                                state.active = false
                                state.timer = nil
                                if cd and cd.Clear then cd:Clear() end
                            end
                        end)
                    end
                end
            end
        end
        return
    end

    -- Party members: try pcall spellID lookup (best-effort, works when not secret)
    if not spellID then return end
    local ok, info = pcall(function() return INTERRUPT_LOOKUP[spellID] end)
    if not ok or not info then return end

    local frame = GetFrameForUnit(unit)
    if frame and frame._kickIcon then
        StartKickCooldown(frame, unit, spellID, info.cd)
    end
end

---------------------------------------------------------------------------
-- INTERRUPT DETECTION (UNIT_SPELLCAST_INTERRUPTED on nameplates/target/focus)
-- When an enemy's cast is interrupted, find which party member kicked by
-- matching against recent UNIT_SPELLCAST_SUCCEEDED timestamps.
-- Same approach as ExwindTools: record party cast times, watch enemy
-- interrupted casts, time-match within a short window.
---------------------------------------------------------------------------

local CAST_MATCH_WINDOW = 0.15  -- seconds — tight window to reduce false matches
local pendingInterrupts = {}     -- batched interrupt events
local processingScheduled = false

local function ProcessPendingInterrupts()
    processingScheduled = false
    local now = GetTime()

    -- Count pending interrupts — if multiple, it's AoE CC not a kick
    local count = 0
    for _ in pairs(pendingInterrupts) do
        count = count + 1
        if count > 1 then break end
    end
    if count ~= 1 then
        wipe(pendingInterrupts)
        return
    end

    -- Single interrupt — find which party member kicked
    local interruptTime = nil
    for _, data in pairs(pendingInterrupts) do
        interruptTime = data.time
    end
    wipe(pendingInterrupts)

    if not interruptTime then return end

    -- Find the party member who cast closest to the interrupt time
    local bestUnit, bestDiff = nil, CAST_MATCH_WINDOW
    for unit, castTime in pairs(recentCasts) do
        local diff = math.abs(interruptTime - castTime)
        if diff <= bestDiff then
            bestUnit = unit
            bestDiff = diff
        end
    end

    if not bestUnit then return end

    -- Already on CD? Skip.
    local frame = GetFrameForUnit(bestUnit)
    if not frame or not frame._kickIcon then return end
    local state = frame._kickTimer
    if state and state.active then return end

    -- Get this unit's interrupt info (spec-aware)
    local classInfo = GetInterruptInfo(bestUnit)
    if not classInfo then return end

    StartKickCooldown(frame, bestUnit, classInfo.id, classInfo.cd)
end

local function ScheduleInterruptProcessing()
    if processingScheduled then return end
    processingScheduled = true
    -- 30ms delay to batch events and let UNIT_SPELLCAST_SUCCEEDED arrive first
    C_Timer.After(0.03, ProcessPendingInterrupts)
end

local registeredFrame = nil

local function RegisterPartyUnits()
    if not registeredFrame then return end
    registeredFrame:UnregisterEvent("UNIT_SPELLCAST_SUCCEEDED")

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
        registeredFrame:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", unpack(units))
    end
end

C_Timer.After(0, function()
    registeredFrame = CreateFrame("Frame")
    registeredFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
    registeredFrame:RegisterEvent("PLAYER_ENTERING_WORLD")

    -- Watch UNIT_SPELLCAST_INTERRUPTED on ALL units (nameplates, target, focus)
    -- This catches enemy cast interrupts from any visible enemy, not just target.
    local interruptFrame = CreateFrame("Frame")
    interruptFrame:RegisterEvent("UNIT_SPELLCAST_INTERRUPTED")
    interruptFrame:SetScript("OnEvent", function(_, _, unit)
        -- Only process enemy unit interrupts (nameplate, target, focus)
        if not unit then return end
        local prefix = unit:match("^(%a+)")
        if prefix ~= "nameplate" and unit ~= "target" and unit ~= "focus" then return end

        pendingInterrupts[unit] = { time = GetTime() }
        ScheduleInterruptProcessing()
    end)

    registeredFrame:SetScript("OnEvent", function(_, event, arg1, arg2, arg3)
        if event == "UNIT_SPELLCAST_SUCCEEDED" then
            OnSpellcastSucceeded(arg1, arg2, arg3)
        else
            RegisterPartyUnits()
            KickTimer.RefreshAll()
        end
    end)

    RegisterPartyUnits()
    KickTimer.RefreshAll()
end)

---------------------------------------------------------------------------
-- AURA EVENT SUBSCRIPTION — refresh icons when units change on frames
---------------------------------------------------------------------------
C_Timer.After(0, function()
    if ns.AuraEvents then
        ns.AuraEvents:Subscribe("group", function(unit)
            GF = GF or ns.QUI_GroupFrames
            if not GF or not GF.unitFrameMap then return end
            local frame = GF.unitFrameMap[unit]
            if frame and not frame._kickIcon then
                ShowStaticIcon(frame)
            end
        end)
    end
end)

-- Re-show icons when layout mode exits (layout mode hides parent frames)
C_Timer.After(0, function()
    local um = ns.QUI_LayoutMode
    if um and um.RegisterExitCallback then
        um:RegisterExitCallback(function()
            C_Timer.After(0, function()
                KickTimer.RefreshAll()
                local ccIcons = ns.PartyTracker_CCIcons
                if ccIcons and ccIcons.RefreshAll then ccIcons.RefreshAll() end
                local cdDisplay = ns.PartyTracker_CooldownDisplay
                if cdDisplay and cdDisplay.RefreshAll then cdDisplay.RefreshAll() end
            end)
        end)
    end
end)
