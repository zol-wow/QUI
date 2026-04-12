--[[
    QUI Group Frames - Aura System
    Compact aura display for group frames with priority filtering,
    table pooling, shared aura timer, and duration color coding.
]]

local ADDON_NAME, ns = ...
local Helpers = ns.Helpers
local LSM = ns.LSM
local QUICore = ns.Addon
local IsSecretValue = Helpers.IsSecretValue
local SafeValue = Helpers.SafeValue
local SafeToNumber = Helpers.SafeToNumber
local GetDB = Helpers.CreateDBGetter("quiGroupFrames")

-- Upvalue hot-path globals
local pairs = pairs
local ipairs = ipairs
local type = type
local pcall = pcall
local wipe = wipe
local format = format
local GetTime = GetTime
local UnitExists = UnitExists
local C_UnitAuras = C_UnitAuras
local sub = string.sub
local CreateFrame = CreateFrame
local table_insert = table.insert

---------------------------------------------------------------------------
-- MODULE TABLE
---------------------------------------------------------------------------
local QUI_GFA = {}
ns.QUI_GroupFrameAuras = QUI_GFA

-- Weak-keyed state for aura icons (taint safety)
local auraIconState = Helpers.CreateStateTable()

-- Layout versioning: only reposition icons when settings change
local layoutVersion = 0
local frameLayoutVersions = Helpers.CreateStateTable()

-- CENTER grow direction: track previous visible count per frame to skip
-- relayout when the count hasn't changed (avoids ClearAllPoints/SetPoint thrashing).
local framePrevDebuffCount = Helpers.CreateStateTable()
local framePrevBuffCount = Helpers.CreateStateTable()

-- (pendingAuraUnits removed: inline processing in dispatcher callback
-- eliminates the double-coalescing layer that added 1 frame of latency)

---------------------------------------------------------------------------
-- SHARED AURA CACHE: Single scan feeds aura icons, dispel, and defensive
---------------------------------------------------------------------------
-- Populated once per throttle window, read by all consumers.
-- Structure: unitAuraCache[unit] = {
--     helpful = {auraData...},
--     harmful = {auraData...},
--     playerDispellable = { [instID] = true },  -- scan-time classification
--     defensives        = { [instID] = true },  -- scan-time classification
-- }
--
-- `playerDispellable` and `defensives` are classified at scan/add time so the
-- dispel overlay and defensive indicator collapse from "iterate aura list and
-- filter-check each" into "next(set)" / "for id in pairs(set)". Classification
-- is invariant per aura instance ID, so the sets only need maintenance on
-- add/remove — in-place updates leave them untouched.
local unitAuraCache = {}

local DISPEL_FILTER = "HARMFUL|RAID_PLAYER_DISPELLABLE"

-- Classify a single harmful aura as dispellable by the current player.
-- Returns true/false; returns nil when the API is unavailable or call fails
-- (caller treats nil as "don't know" and skips set insertion).
local function ClassifyDispellable(unit, instID)
    if not instID or IsSecretValue(instID) then return nil end
    if not C_UnitAuras or not C_UnitAuras.IsAuraFilteredOutByInstanceID then return nil end
    local ok, filteredOut = pcall(C_UnitAuras.IsAuraFilteredOutByInstanceID, unit, instID, DISPEL_FILTER)
    if not ok or IsSecretValue(filteredOut) then return nil end
    return filteredOut == false
end

-- Classify a single helpful aura as a verified defensive (big or external).
-- Delegates to the groupframes.lua classifier which owns the spell-ID fast
-- path and the BigDefensive/ExternalDefensive filter cache.
local function ClassifyDefensive(unit, auraData)
    local GF = ns.QUI_GroupFrames
    if not GF or not GF.IsVerifiedDefensiveAura then return false end
    return GF.IsVerifiedDefensiveAura(unit, auraData) == true
end

local function ScanUnitAuras(unit)
    local cache = unitAuraCache[unit]
    if not cache then
        cache = { helpful = {}, harmful = {}, playerDispellable = {}, defensives = {} }
        unitAuraCache[unit] = cache
    else
        wipe(cache.helpful)
        wipe(cache.harmful)
        wipe(cache.playerDispellable)
        wipe(cache.defensives)
    end

    if not C_UnitAuras or not C_UnitAuras.GetUnitAuras then return cache end

    -- Copy API results into our existing tables instead of replacing refs
    -- (avoids abandoning 2 tables per unit per scan to GC — 40 tables in raids)
    local ok, harmful = pcall(C_UnitAuras.GetUnitAuras, unit, "HARMFUL", 40)
    if ok and harmful then
        local dst = cache.harmful
        local dispellable = cache.playerDispellable
        for i = 1, #harmful do
            local ad = harmful[i]
            dst[i] = ad
            -- Scan-time dispel classification: one pcall per aura now saves
            -- one pcall per aura per setChanged event later. Fall back to the
            -- legacy dispelName field when the filter API is unavailable or
            -- returns nil (preserves correctness in rare edge cases).
            local instID = ad.auraInstanceID
            if instID then
                local classified = ClassifyDispellable(unit, instID)
                if classified == true then
                    dispellable[instID] = true
                elseif classified == nil and ad.dispelName and not IsSecretValue(ad.dispelName) then
                    dispellable[instID] = true
                end
            end
        end
    end

    local ok2, helpful = pcall(C_UnitAuras.GetUnitAuras, unit, "HELPFUL", 40)
    if ok2 and helpful then
        local dst = cache.helpful
        local defensives = cache.defensives
        for i = 1, #helpful do
            local ad = helpful[i]
            dst[i] = ad
            -- Scan-time defensive classification: the IsVerifiedDefensiveAura
            -- spell-ID fast path makes most checks a single table lookup, and
            -- the rare filter-API path gets memoized in _defensive.cache for
            -- subsequent adds.
            local instID = ad.auraInstanceID
            if instID and ClassifyDefensive(unit, ad) then
                defensives[instID] = true
            end
        end
    end

    return cache
end

-- (IncrementalUpdateAuras removed: always full-scan via ScanUnitAuras.
-- Eliminates hundreds of GetAuraDataByAuraInstanceID calls per second in raids
-- that each allocate a fresh ~600-byte Blizzard table, overwhelming the GC.
-- Full scan uses GetUnitAuras which returns one bulk table per filter type.)

-- Evict stale cache entries for units no longer in the group.
-- Called on GROUP_ROSTER_UPDATE from the centralized event dispatcher.
local function PruneAuraCache()
    local GF = ns.QUI_GroupFrames
    if not GF or not GF.unitFrameMap then return end
    for unit in pairs(unitAuraCache) do
        if not GF.unitFrameMap[unit] then
            unitAuraCache[unit] = nil
        end
    end
end

-- Expose cache for other modules (dispel overlay, defensive indicator)
QUI_GFA.unitAuraCache = unitAuraCache
QUI_GFA.ScanUnitAuras = ScanUnitAuras
QUI_GFA.PruneAuraCache = PruneAuraCache

-- Table reuse: unitAuraCache[unit] sub-tables (helpful, harmful, etc.) are
-- created once per unit and wiped+refilled on each scan. Blizzard's auraData
-- tables from GetUnitAuras are C-side allocated and can't be pooled, but the
-- bulk-return pattern (one table per filter type) minimizes Lua-side garbage.

---------------------------------------------------------------------------
-- SHARED AURA TIMER: Single animation drives all icon duration updates
---------------------------------------------------------------------------
local timerIcons = {} -- Icons registered for duration updates
local sharedTimerFrame = CreateFrame("Frame")
local TIMER_INTERVAL = 0.2 -- Update duration text at 5 Hz (200ms)
local floor = math.floor

-- Compute the bucket for a remaining duration WITHOUT allocating a string.
-- Only call FormatDuration when the bucket actually changed.
local function ComputeBucket(remaining)
    if remaining <= 0 then return -1 end
    if remaining < 10 then return floor(remaining * 10) end
    if remaining < 60 then return 1000 + floor(remaining) end
    if remaining < 3600 then return 2000 + floor(remaining / 60) end
    return 3000 + floor(remaining / 3600)
end

-- Returns formatted text for a given remaining duration.
-- PERF: Only call this when ComputeBucket indicates the display changed.
local function FormatDuration(remaining)
    if remaining <= 0 then return "" end
    if remaining < 10 then return format("%.1f", remaining) end
    if remaining < 60 then return format("%d", floor(remaining)) end
    if remaining < 3600 then return format("%dm", floor(remaining / 60)) end
    return format("%dh", floor(remaining / 3600))
end

-- Compute color band cheaply (no allocation).
local function ComputeColorBand(remaining, duration)
    if duration <= 0 or remaining <= 0 then return 0 end
    local pct = remaining / duration
    if pct > 0.5 then return 3 end
    if pct > 0.25 then return 2 end
    return 1
end

-- Returns (r, g, b, colorBand) where colorBand changes only when the color
-- would actually differ, allowing callers to skip redundant SetTextColor.
local function GetDurationColor(remaining, duration)
    if duration <= 0 or remaining <= 0 then
        return 1, 0, 0, 0
    end
    local pct = remaining / duration
    if pct > 0.5 then
        return 0.2, 1, 0.2, 3
    elseif pct > 0.25 then
        return 1, 1, 0, 2
    else
        return 1, 0.2, 0.2, 1
    end
end

local timerElapsed = 0
local cachedShowDurationColor = true

local function SharedTimerOnUpdate(self, dt)
    timerElapsed = timerElapsed + dt
    if timerElapsed < TIMER_INTERVAL then return end
    timerElapsed = 0

    -- Skip when no group frames are active (solo play)
    local GF = ns.QUI_GroupFrames
    if not GF or not next(GF.unitFrameMap) then return end

    local now = GetTime()
    local db = GetDB()
    -- Pre-compute aura settings for both contexts (avoids per-icon table walks)
    local raidAuras = db and db.raid and db.raid.auras
    local partyAuras = db and db.party and db.party.auras
    local hasAny = false

    for icon, state in pairs(timerIcons) do
        hasAny = true
        if not icon:IsShown() then
            -- Skip hidden icons entirely — overflow icons that exceed
            -- maxDebuffs/maxBuffs limits in raids.
        elseif state.expirationTime then
            -- Values are guaranteed non-secret: UpdateAuraIcon only registers
            -- icons into timerIcons when duration passes IsSecretValue check.
            local expTime = state.expirationTime
            local dur = state.duration or 0
            local remaining = expTime - now

            if remaining > 0 then
                if icon.durationText then
                    local isRaid = icon.unitFrame and icon.unitFrame._isRaid
                    local auraSettings = isRaid and raidAuras or partyAuras
                    local showDurationText = not auraSettings or auraSettings.showDurationText ~= false
                    if showDurationText then
                        -- PERF: Compute bucket (zero allocation) BEFORE formatting.
                        -- Only call FormatDuration (string.format) when display changes.
                        local bucket = ComputeBucket(remaining)
                        if bucket ~= state._lastBucket then
                            icon.durationText:SetText(FormatDuration(remaining))
                            state._lastBucket = bucket
                        end
                        -- Color: throttled to 1 Hz per icon (expensive in raids)
                        local showDurationColor = not auraSettings or auraSettings.showDurationColor ~= false
                        if showDurationColor then
                            local lastColorTime = state._lastColorTime or 0
                            if (now - lastColorTime) >= 1.0 then
                                state._lastColorTime = now
                                local band = ComputeColorBand(remaining, dur)
                                if band ~= state._lastColorBand then
                                    local r, g, b = GetDurationColor(remaining, dur)
                                    icon.durationText:SetTextColor(r, g, b, 1)
                                    state._lastColorBand = band
                                end
                            end
                        elseif state._lastColorBand ~= 0 then
                            icon.durationText:SetTextColor(1, 1, 1, 1)
                            state._lastColorBand = 0
                        end
                    else
                        icon.durationText:SetText("")
                    end
                end
            else
                -- Expired
                if icon.durationText then icon.durationText:SetText("") end
                timerIcons[icon] = nil
            end
        else
            timerIcons[icon] = nil
        end
    end

    -- Auto-disable when no icons remain
    if not hasAny then
        self:SetScript("OnUpdate", nil)
    end
end

-- Start disabled — no icons at init
sharedTimerFrame:SetScript("OnUpdate", nil)

local function RegisterIconTimer(icon, state)
    local wasEmpty = next(timerIcons) == nil
    timerIcons[icon] = state
    if wasEmpty then
        timerElapsed = 0
        sharedTimerFrame:SetScript("OnUpdate", SharedTimerOnUpdate)
    end
end

local function UnregisterIconTimer(icon)
    timerIcons[icon] = nil
end

---------------------------------------------------------------------------
-- SLOT OFFSET: Calculate icon position for configurable grow direction
---------------------------------------------------------------------------
local function CalculateSlotOffset(index, iconSize, spacing, direction, totalCount)
    local step = (index - 1) * (iconSize + spacing)
    if direction == "RIGHT" then
        return step, 0
    elseif direction == "LEFT" then
        return -step, 0
    elseif direction == "CENTER" then
        local n = totalCount or 1
        local totalSpan = n * iconSize + math.max(n - 1, 0) * spacing
        return step - totalSpan / 2, 0
    elseif direction == "UP" then
        return 0, step
    elseif direction == "DOWN" then
        return 0, -step
    end
    return step, 0 -- fallback to RIGHT
end

-- Track icons that need mouse setup deferred from combat
local pendingMouseFix = false

---------------------------------------------------------------------------
-- AURA ICON: Create/get icon for a frame
---------------------------------------------------------------------------
-- Cached font path: rebuilt on layout invalidation, avoids per-icon DB+LSM lookups.
local _cachedFontPath = nil

local function GetFontPath()
    if _cachedFontPath then return _cachedFontPath end
    local db = GetDB()
    local vdb = db and (db.party or db)
    local general = vdb and vdb.general
    local fontName = general and general.font or "Quazii"
    _cachedFontPath = LSM:Fetch("font", fontName) or "Fonts\\FRIZQT__.TTF"
    return _cachedFontPath
end

local function CreateAuraIcon(parent, size)
    size = size or 16
    local icon = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    icon:SetSize(size, size)

    -- Render above healthBar (+0), healPrediction (+1), absorb (+2), dispel (+6)
    local baseLevel = parent.healthBar and parent.healthBar:GetFrameLevel() or parent:GetFrameLevel()
    icon:SetFrameLevel(baseLevel + 8)

    -- Icon texture
    local tex = icon:CreateTexture(nil, "ARTWORK")
    tex:SetAllPoints()
    tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    icon.icon = tex

    -- Border
    local px = QUICore.GetPixelSize and QUICore:GetPixelSize(icon) or 1
    icon:SetBackdrop({
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = px,
    })
    icon:SetBackdropBorderColor(0, 0, 0, 1)

    -- Cooldown swipe
    local cooldown = CreateFrame("Cooldown", nil, icon, "CooldownFrameTemplate")
    cooldown:SetAllPoints()
    cooldown:SetDrawEdge(false)
    cooldown:SetDrawBling(false)
    cooldown:SetHideCountdownNumbers(true)
    icon.cooldown = cooldown

    -- Stack count text
    local stackText = icon:CreateFontString(nil, "OVERLAY")
    local fontPath = GetFontPath()
    stackText:SetFont(fontPath, 10, "OUTLINE")
    stackText:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", 1, -1)
    stackText:SetJustifyH("RIGHT")
    icon.stackText = stackText

    -- Duration text
    local durationText = icon:CreateFontString(nil, "OVERLAY")
    durationText:SetFont(fontPath, 9, "OUTLINE")
    durationText:SetPoint("TOP", icon, "BOTTOM", 0, -1)
    durationText:SetJustifyH("CENTER")
    icon.durationText = durationText

    -- Expiring pulse animation
    local pulseGroup = icon:CreateAnimationGroup()
    local pulseAlpha = pulseGroup:CreateAnimation("Alpha")
    pulseAlpha:SetFromAlpha(1)
    pulseAlpha:SetToAlpha(0.3)
    pulseAlpha:SetDuration(0.4)
    pulseGroup:SetLooping("BOUNCE")
    icon.pulseGroup = pulseGroup

    -- Mouse propagation so @mouseover targeting and click-casting keep
    -- working when the cursor is over aura icons.
    -- EnableMouse(true)                  → icon receives OnEnter/OnLeave (tooltips)
    -- SetPropagateMouseMotion(true)      → parent frame also gets motion events (@mouseover)
    -- SetPropagateMouseClicks(true)      → clicks pass through to parent (targeting/cast)
    -- SetMouseClickEnabled(false)        → icon itself doesn't consume clicks
    if not InCombatLockdown() then
        icon:EnableMouse(true)
        if icon.SetPropagateMouseMotion then icon:SetPropagateMouseMotion(true) end
        if icon.SetPropagateMouseClicks then icon:SetPropagateMouseClicks(true) end
        if icon.SetMouseClickEnabled then icon:SetMouseClickEnabled(false) end
    else
        pendingMouseFix = true
    end

    -- Store parent unit frame reference for tooltip lookups
    icon.unitFrame = parent

    -- Aura tooltip on hover
    icon:SetScript("OnEnter", function(self)
        if not self:IsShown() then return end
        local state = auraIconState[self]
        local uf = self.unitFrame
        if not state or not uf or not uf.unit then return end
        local auraID = state.auraInstanceID
        if not auraID or IsSecretValue(auraID) then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if GameTooltip.SetUnitAuraByAuraInstanceID then
            pcall(GameTooltip.SetUnitAuraByAuraInstanceID, GameTooltip, uf.unit, auraID)
        end
        GameTooltip:Show()
    end)

    icon:SetScript("OnLeave", function(self)
        GameTooltip:Hide()
    end)

    icon:Hide()
    return icon
end

local function SafeSetReverse(cooldown, reverse)
    if cooldown and cooldown.SetReverse then
        pcall(cooldown.SetReverse, cooldown, reverse == true)
    end
end

local function SafeSetDrawSwipe(cooldown, showSwipe)
    if cooldown and cooldown.SetDrawSwipe then
        pcall(cooldown.SetDrawSwipe, cooldown, showSwipe ~= false)
    end
end

-- Dispel border colors (file-level to avoid per-call allocation)
local AURA_DISPEL_COLORS = {
    Magic   = { 0.2, 0.6, 1.0, 1 },
    Curse   = { 0.6, 0.0, 1.0, 1 },
    Disease = { 0.6, 0.4, 0.0, 1 },
    Poison  = { 0.0, 0.6, 0.0, 1 },
    Bleed   = { 0.8, 0.0, 0.0, 1 },
}

local function UpdateAuraIcon(icon, auraData, unit)
    if not icon or not auraData then
        if icon then icon:Hide() end
        return
    end

    -- Reuse icon-level state table (created once, fields overwritten).
    -- Avoids per-icon table creation and keeps state off Blizzard frames (taint safety).
    local state = icon._auraState
    if not state then
        state = {}
        icon._auraState = state
        auraIconState[icon] = state  -- register for tooltip lookups
    end

    -- Cache always has fresh data from full ScanUnitAuras — no refetch needed.
    local auraID = auraData.auraInstanceID
    local displayData = auraData

    -- Overwrite state fields (zero allocation)
    state.unit = unit
    state.auraInstanceID = auraID
    state.expirationTime = displayData.expirationTime
    state.duration = displayData.duration
    state.applications = displayData.applications

    -- Icon texture (C-side SetTexture handles secret values natively)
    if icon.icon then
        pcall(icon.icon.SetTexture, icon.icon, displayData.icon)
    end

    -- Stack count: GetAuraApplicationDisplayCount returns a display-ready
    -- string, fully secret-safe via C-side SetText.
    if icon.stackText then
        if auraID and not IsSecretValue(auraID) and C_UnitAuras.GetAuraApplicationDisplayCount then
            local ok, countStr = pcall(C_UnitAuras.GetAuraApplicationDisplayCount, unit, auraID, 2, 99)
            if ok and countStr then
                pcall(icon.stackText.SetText, icon.stackText, countStr)
            else
                icon.stackText:SetText("")
            end
        else
            local stacks = SafeToNumber(displayData.applications, 0)
            if stacks > 1 then
                icon.stackText:SetText(stacks)
            else
                icon.stackText:SetText("")
            end
        end
    end

    -- Cooldown swipe (prefer DurationObject → ExpirationTime → legacy)
    if icon.cooldown then
        local dur = displayData.duration
        local expTime = displayData.expirationTime

        if auraID and not IsSecretValue(auraID) and icon.cooldown.SetCooldownFromDurationObject and C_UnitAuras.GetAuraDuration then
            -- Path 1: DurationObject (WoW 12.0+, fully secret-safe)
            local ok, durationObj = pcall(C_UnitAuras.GetAuraDuration, unit, auraID)
            if ok and durationObj then
                pcall(icon.cooldown.SetCooldownFromDurationObject, icon.cooldown, durationObj, true)
            elseif not IsSecretValue(expTime) and not IsSecretValue(dur) then
                if icon.cooldown.SetCooldownFromExpirationTime then
                    pcall(icon.cooldown.SetCooldownFromExpirationTime, icon.cooldown, expTime, dur)
                else
                    pcall(icon.cooldown.SetCooldown, icon.cooldown, expTime - dur, dur)
                end
            else
                icon.cooldown:Clear()
            end
        elseif not IsSecretValue(dur) and dur and not IsSecretValue(expTime) and expTime then
            -- Path 2: Non-secret fallback (SetCooldownFromExpirationTime or legacy)
            if icon.cooldown.SetCooldownFromExpirationTime then
                pcall(icon.cooldown.SetCooldownFromExpirationTime, icon.cooldown, expTime, dur)
            else
                pcall(icon.cooldown.SetCooldown, icon.cooldown, expTime - dur, dur)
            end
        else
            icon.cooldown:Clear()
        end
    end

    -- Duration text + timer registration
    -- Skip entirely when values are secret (combat) — the cooldown swipe is
    -- already driven by DurationObject via C-side; Lua text/pulse would just
    -- SafeToNumber → 0 and do nothing useful.
    local dur = displayData.duration
    local expTime = displayData.expirationTime
    if not IsSecretValue(dur) and dur and dur > 0 then
        RegisterIconTimer(icon, state)

        -- Expiring pulse: uses per-frame cached setting (set by UpdateFrameAuras)
        -- to avoid calling GetDB() per icon (was ~120 DB lookups per aura batch)
        local showPulse = icon._cachedShowPulse
        if showPulse and not IsSecretValue(expTime) then
            local remaining = expTime - GetTime()
            if remaining > 0 and remaining < 5 then
                if icon.pulseGroup and not icon.pulseGroup:IsPlaying() then
                    icon.pulseGroup:Play()
                end
            else
                if icon.pulseGroup and icon.pulseGroup:IsPlaying() then
                    icon.pulseGroup:Stop()
                end
            end
        elseif icon.pulseGroup and icon.pulseGroup:IsPlaying() then
            icon.pulseGroup:Stop()
        end
    else
        UnregisterIconTimer(icon)
        if icon.durationText then icon.durationText:SetText("") end
        if icon.pulseGroup and icon.pulseGroup:IsPlaying() then
            icon.pulseGroup:Stop()
        end
    end

    -- Dispellable debuff border color
    if not IsSecretValue(displayData.dispelName) and displayData.dispelName then
        local dispelType = SafeValue(displayData.dispelName, nil)
        if dispelType and AURA_DISPEL_COLORS[dispelType] then
            local c = AURA_DISPEL_COLORS[dispelType]
            icon:SetBackdropBorderColor(c[1], c[2], c[3], c[4])
        else
            icon:SetBackdropBorderColor(0.8, 0, 0, 1) -- Default debuff red
        end
    else
        icon:SetBackdropBorderColor(0, 0, 0, 1) -- Default black border
    end

    icon:Show()
end

---------------------------------------------------------------------------
-- CLASSIFICATION FILTER: Build filter strings and check auras
---------------------------------------------------------------------------
-- Maps DB toggle keys to Blizzard classification filter strings
local BUFF_CLASSIFICATION_MAP = {
    raid             = "HELPFUL|RAID",
    cancelable       = "HELPFUL|CANCELABLE",
    important        = "HELPFUL|IMPORTANT",
}

local DEBUFF_CLASSIFICATION_MAP = {
    raid        = "HARMFUL|RAID",
    crowdControl = "HARMFUL|CROWD_CONTROL",
    important   = "HARMFUL|IMPORTANT",
}

-- Per-context (party/raid) cached filter data
-- Structure: filterCaches[contextKey] = { buffFilters={}, debuffFilters={}, filterMode="off", ... }
local filterCaches = { party = {}, raid = {} }
local cachedFilterVersion = -1

-- (Per-auraInstanceID classification cache removed: grew unboundedly during
-- long encounters. Now classify inline during each full scan — same approach
-- as reference addons. Cost is minimal since full scans only run once per
-- unit per coalesce tick, and IsAuraFilteredOutByInstanceID is C-side.)

local function InitFilterCache()
    return {
        buffFilters = {},
        debuffFilters = {},
        filterMode = "off",
        onlyMine = false,
        buffWhitelist = nil,
        buffBlacklist = nil,
        debuffWhitelist = nil,
        debuffBlacklist = nil,
    }
end
filterCaches.party = InitFilterCache()
filterCaches.raid = InitFilterCache()

local function RebuildFilterCacheForContext(cache, auraSettings)
    if not auraSettings then return end

    cache.filterMode = auraSettings.filterMode or "off"
    cache.onlyMine = auraSettings.buffFilterOnlyMine or false

    wipe(cache.buffFilters)
    wipe(cache.debuffFilters)
    cache.buffWhitelist = nil
    cache.buffBlacklist = nil
    cache.debuffWhitelist = nil
    cache.debuffBlacklist = nil

    if cache.filterMode == "classification" then
        local buffClass = auraSettings.buffClassifications
        if buffClass then
            for key, filterStr in pairs(BUFF_CLASSIFICATION_MAP) do
                if buffClass[key] then
                    table_insert(cache.buffFilters, filterStr)
                end
            end
        end

        local debuffClass = auraSettings.debuffClassifications
        if debuffClass then
            for key, filterStr in pairs(DEBUFF_CLASSIFICATION_MAP) do
                if debuffClass[key] then
                    table_insert(cache.debuffFilters, filterStr)
                end
            end
        end
    elseif cache.filterMode == "whitelist" then
        local bwl = auraSettings.buffWhitelist
        if bwl and next(bwl) then cache.buffWhitelist = bwl end
        local dwl = auraSettings.debuffWhitelist
        if dwl and next(dwl) then cache.debuffWhitelist = dwl end
    end

    -- Blacklist always applies regardless of filter mode (additive filter)
    local bbl = auraSettings.buffBlacklist
    if bbl and next(bbl) then cache.buffBlacklist = bbl end
    local dbl = auraSettings.debuffBlacklist
    if dbl and next(dbl) then cache.debuffBlacklist = dbl end
end

local function RebuildFilterCache()
    local db = GetDB()
    if not db then return end

    -- Build party filter cache
    local partyVdb = db.party or db
    RebuildFilterCacheForContext(filterCaches.party, partyVdb.auras)

    -- Build raid filter cache
    local raidVdb = db.raid or db
    RebuildFilterCacheForContext(filterCaches.raid, raidVdb.auras)

    cachedFilterVersion = layoutVersion
end

local function GetFilterCache(isRaid)
    return isRaid and filterCaches.raid or filterCaches.party
end

-- Check if an aura passes whitelist/blacklist filter by spellID.
-- Returns true if aura should be shown.
-- Fail-open: if spellID is secret, show the aura.
local function AuraPassesSpellFilter(auraData, whitelist, blacklist)
    local spellId = auraData and auraData.spellId
    if not spellId or IsSecretValue(spellId) then
        return true -- fail-open
    end
    if whitelist then
        return whitelist[spellId] == true
    end
    if blacklist then
        return blacklist[spellId] ~= true
    end
    return true
end

-- Check if an aura passes classification filter (OR logic, inline query).
-- Returns true if aura should be shown.
-- Fail-open: if API fails or returns secret, show the aura.
-- No per-auraInstanceID caching — classify inline during each scan.
-- IsAuraFilteredOutByInstanceID is C-side and fast.
local function AuraPassesFilter(unit, auraInstanceID, filterStrings)
    if not filterStrings or #filterStrings == 0 then
        return false
    end

    if not auraInstanceID or IsSecretValue(auraInstanceID) then
        return true -- fail-open
    end

    if not C_UnitAuras or not C_UnitAuras.IsAuraFilteredOutByInstanceID then
        return true
    end

    for _, filterStr in ipairs(filterStrings) do
        local ok, filteredOut = pcall(C_UnitAuras.IsAuraFilteredOutByInstanceID, unit, auraInstanceID, filterStr)
        if not ok then
            return true -- fail-open on error
        end
        if IsSecretValue(filteredOut) then
            return true -- fail-open on secret
        end
        if not filteredOut then
            return true -- aura matches this classification
        end
    end

    return false
end

---------------------------------------------------------------------------
-- AURA PRIORITY: Sort auras by importance
---------------------------------------------------------------------------
local PRIORITY_DISPELLABLE = 3
local PRIORITY_BOSS = 2
local PRIORITY_NORMAL = 1

-- Priority lookup table for zero-allocation sorting: auraData → priority.
-- Populated inline during aura collection, used by the sort comparator,
-- then wiped.  Eliminates AcquireAuraTable/ReleaseAuraTable per visible aura.
local _auraPrioMap = {}

-- Reusable sort comparator (avoids closure allocation per sort call)
local function AuraPrioritySort(a, b)
    return (_auraPrioMap[a] or 0) > (_auraPrioMap[b] or 0)
end

local function GetAuraPriority(auraData)
    if not auraData then return 0 end
    local isDispellable = SafeValue(auraData.dispelName, nil)
    local isBoss = SafeValue(auraData.isBossAura, false)

    if isDispellable then return PRIORITY_DISPELLABLE end
    if isBoss then return PRIORITY_BOSS end
    return PRIORITY_NORMAL
end

---------------------------------------------------------------------------
-- UPDATE: Auras for a single frame
---------------------------------------------------------------------------
-- (RefreshUpdatedIcons / delta-aware icon refresh removed: always full-scan
-- now, so every dispatch does ScanUnitAuras → UpdateFrameAuras. Simpler,
-- and avoids the per-aura GetAuraDataByAuraInstanceID allocation overhead.)

local sortedAuras = {} -- Reusable sort table

local function UpdateFrameAuras(frame)
    if not frame or not frame.unit then return end

    local db = GetDB()
    if not db then return end
    local isRaid = frame._isRaid
    local vdb = (isRaid and db.raid or db.party) or db
    if not vdb.auras then return end
    local auraSettings = vdb.auras

    -- Cache pulse setting for this frame (read by UpdateAuraIcon, avoids per-icon GetDB)
    local showPulse = auraSettings.showExpiringPulse ~= false
    frame._cachedShowPulse = showPulse

    -- Layout versioning: only reposition icons when settings have changed
    local needsLayout = (frameLayoutVersions[frame] or 0) ~= layoutVersion

    local unit = frame.unit
    if not UnitExists(unit) then
        -- Hide all icons
        if frame.debuffIcons then
            for _, icon in ipairs(frame.debuffIcons) do
                icon:Hide()
                UnregisterIconTimer(icon)
            end
        end
        if frame.buffIcons then
            for _, icon in ipairs(frame.buffIcons) do
                icon:Hide()
                UnregisterIconTimer(icon)
            end
        end
        return
    end

    -- Rebuild classification filter cache if settings changed
    if cachedFilterVersion ~= layoutVersion then
        RebuildFilterCache()
    end

    local fCache = GetFilterCache(isRaid)
    local useClassification = fCache.filterMode == "classification"
    local useWhitelist = fCache.filterMode == "whitelist"
    local onlyMine = fCache.onlyMine
    local playerUnit = "player"

    -- Process debuffs
    if auraSettings.showDebuffs then
        local maxDebuffs = auraSettings.maxDebuffs or 3
        local iconSize = auraSettings.debuffIconSize or 16

        -- Ensure icon pool exists
        if not frame.debuffIcons then
            frame.debuffIcons = {}
        end

        -- Collect harmful auras from shared cache (already scanned)
        wipe(sortedAuras)
        wipe(_auraPrioMap)
        local debuffFilters = useClassification and #fCache.debuffFilters > 0 and fCache.debuffFilters or nil
        local cache = unitAuraCache[unit]
        if cache and cache.harmful then
            for _, auraData in ipairs(cache.harmful) do
                local dominated = false

                -- Classification filter
                if debuffFilters and not AuraPassesFilter(unit, auraData.auraInstanceID, debuffFilters) then
                    dominated = true
                end

                -- Whitelist filter
                if not dominated and useWhitelist and fCache.debuffWhitelist then
                    if not AuraPassesSpellFilter(auraData, fCache.debuffWhitelist, nil) then
                        dominated = true
                    end
                end

                -- Blacklist filter (always applies)
                if not dominated and fCache.debuffBlacklist then
                    if not AuraPassesSpellFilter(auraData, nil, fCache.debuffBlacklist) then
                        dominated = true
                    end
                end

                if not dominated then
                    _auraPrioMap[auraData] = GetAuraPriority(auraData)
                    sortedAuras[#sortedAuras + 1] = auraData
                end
            end
        end

        -- Sort by priority (higher first)
        if #sortedAuras > maxDebuffs then
            table.sort(sortedAuras, AuraPrioritySort)
        end

        -- Display up to maxDebuffs
        local dAnchor = auraSettings.debuffAnchor or "BOTTOMRIGHT"
        local dGrow = auraSettings.debuffGrowDirection or "LEFT"
        local dSpacing = auraSettings.debuffSpacing or 2
        local dOffX = auraSettings.debuffOffsetX or -2
        local dOffY = auraSettings.debuffOffsetY or -18
        if sub(dAnchor, 1, 6) == "BOTTOM" then dOffY = dOffY + (frame._bottomPad or 0) end
        -- CENTER: only relayout when visible count actually changes (skip thrashing)
        local dVisibleCount = nil
        if dGrow == "CENTER" then
            local vc = math.min(#sortedAuras, maxDebuffs)
            if vc ~= (framePrevDebuffCount[frame] or -1) then
                dVisibleCount = vc
                framePrevDebuffCount[frame] = vc
            end
        end
        local fontPath = GetFontPath()
        local durationFontSize = auraSettings.durationFontSize or 9
        for i = 1, maxDebuffs do
            local auraData = sortedAuras[i]
            if not frame.debuffIcons[i] then
                frame.debuffIcons[i] = CreateAuraIcon(frame, iconSize)
                needsLayout = true -- New icon always needs positioning
            end
            -- Only reposition when layout settings changed (version mismatch)
            if needsLayout or dVisibleCount then
                local offX, offY = CalculateSlotOffset(i, iconSize, dSpacing, dGrow, dVisibleCount)
                frame.debuffIcons[i]:ClearAllPoints()
                frame.debuffIcons[i]:SetPoint(dAnchor, frame, dAnchor, dOffX + offX, dOffY + offY)
                frame.debuffIcons[i]:SetSize(iconSize, iconSize)
                -- Apply duration font size from settings
                if frame.debuffIcons[i].durationText then
                    frame.debuffIcons[i].durationText:SetFont(fontPath, durationFontSize, "OUTLINE")
                end
            end
            local icon = frame.debuffIcons[i]
            SafeSetDrawSwipe(icon and icon.cooldown, auraSettings.debuffHideSwipe ~= true)
            SafeSetReverse(icon and icon.cooldown, auraSettings.debuffReverseSwipe == true)
            if auraData then
                icon._cachedShowPulse = showPulse
                UpdateAuraIcon(icon, auraData, unit)
            else
                icon:Hide()
                UnregisterIconTimer(icon)
            end
        end

        -- Hide excess icons
        for i = maxDebuffs + 1, #frame.debuffIcons do
            frame.debuffIcons[i]:Hide()
            UnregisterIconTimer(frame.debuffIcons[i])
        end
    elseif frame.debuffIcons then
        for _, icon in ipairs(frame.debuffIcons) do
            icon:Hide()
            UnregisterIconTimer(icon)
        end
    end

    -- Process buffs (if enabled)
    if auraSettings.showBuffs and (auraSettings.maxBuffs or 0) > 0 then
        local maxBuffs = auraSettings.maxBuffs
        local iconSize = auraSettings.buffIconSize or 14

        if not frame.buffIcons then
            frame.buffIcons = {}
        end

        wipe(sortedAuras)
        local hidePermanent = auraSettings.buffHidePermanent
        local dedup = auraSettings.buffDeduplicateDefensives ~= false

        -- Build dedup set from defensives + aura indicators + pinned auras (reuse per frame)
        local dedupSet
        if dedup then
            local defIDs = frame._defensiveAuraIDs
            local indIDs = frame._indicatorAuraIDs
            local pinIDs = frame._pinnedAuraIDs
            local hasDef = defIDs and next(defIDs)
            local hasInd = indIDs and next(indIDs)
            local hasPin = pinIDs and next(pinIDs)
            local sourceCount = (hasDef and 1 or 0) + (hasInd and 1 or 0) + (hasPin and 1 or 0)
            if sourceCount > 1 then
                if not frame._buffDedupSet then frame._buffDedupSet = {} end
                wipe(frame._buffDedupSet)
                if hasDef then for id in pairs(defIDs) do frame._buffDedupSet[id] = true end end
                if hasInd then for id in pairs(indIDs) do frame._buffDedupSet[id] = true end end
                if hasPin then for id in pairs(pinIDs) do frame._buffDedupSet[id] = true end end
                dedupSet = frame._buffDedupSet
            elseif hasDef then
                dedupSet = defIDs
            elseif hasInd then
                dedupSet = indIDs
            elseif hasPin then
                dedupSet = pinIDs
            end
        end

        local cache = unitAuraCache[unit]
        if cache and cache.helpful then
            for _, auraData in ipairs(cache.helpful) do
                local dominated = false

                -- Dedup: skip buffs already shown as defensives or indicators
                if not dominated and dedupSet and auraData.auraInstanceID then
                    if dedupSet[auraData.auraInstanceID] then
                        dominated = true
                    end
                end

                -- Hide permanent (duration 0) buffs
                if not dominated and hidePermanent then
                    local dur = SafeToNumber(auraData.duration, -1)
                    if dur == 0 then
                        dominated = true
                    end
                end

                -- "Only My Buffs" filter (use C-side API to avoid secret value on isFromPlayerOrPlayerPet)
                if onlyMine and not dominated then
                    local instID = auraData.auraInstanceID
                    if C_UnitAuras.IsAuraFilteredOutByInstanceID and instID and not IsSecretValue(instID) then
                        -- Inline query — no per-ID caching (same approach as AuraPassesFilter)
                        local ok, fo = pcall(C_UnitAuras.IsAuraFilteredOutByInstanceID, unit, instID, "HELPFUL|PLAYER")
                        if ok and not IsSecretValue(fo) and fo then
                            dominated = true
                        end
                    elseif not IsSecretValue(auraData.isFromPlayerOrPlayerPet) then
                        if not auraData.isFromPlayerOrPlayerPet then
                            dominated = true
                        end
                    end
                end

                -- Classification filter
                if useClassification and not dominated and #fCache.buffFilters > 0 then
                    if not AuraPassesFilter(unit, auraData.auraInstanceID, fCache.buffFilters) then
                        dominated = true
                    end
                end

                -- Whitelist filter
                if not dominated and useWhitelist and fCache.buffWhitelist then
                    if not AuraPassesSpellFilter(auraData, fCache.buffWhitelist, nil) then
                        dominated = true
                    end
                end

                -- Blacklist filter (always applies)
                if not dominated and fCache.buffBlacklist then
                    if not AuraPassesSpellFilter(auraData, nil, fCache.buffBlacklist) then
                        dominated = true
                    end
                end

                if not dominated then
                    sortedAuras[#sortedAuras + 1] = auraData
                end
            end
        end
        -- Buffs have equal priority — no sort needed

        local bAnchor = auraSettings.buffAnchor or "TOPLEFT"
        local bGrow = auraSettings.buffGrowDirection or "RIGHT"
        local bSpacing = auraSettings.buffSpacing or 2
        local bOffX = auraSettings.buffOffsetX or 2
        local bOffY = auraSettings.buffOffsetY or 16
        if sub(bAnchor, 1, 6) == "BOTTOM" then bOffY = bOffY + (frame._bottomPad or 0) end
        -- CENTER: only relayout when visible count actually changes
        local bVisibleCount = nil
        if bGrow == "CENTER" then
            local vc = math.min(#sortedAuras, maxBuffs)
            if vc ~= (framePrevBuffCount[frame] or -1) then
                bVisibleCount = vc
                framePrevBuffCount[frame] = vc
            end
        end
        local fontPath = GetFontPath()
        local buffFontSize = auraSettings.durationFontSize or 9
        for i = 1, maxBuffs do
            local auraData = sortedAuras[i]
            if not frame.buffIcons[i] then
                frame.buffIcons[i] = CreateAuraIcon(frame, iconSize)
                needsLayout = true
            end
            -- Only reposition when layout settings changed
            if needsLayout or bVisibleCount then
                local offX, offY = CalculateSlotOffset(i, iconSize, bSpacing, bGrow, bVisibleCount)
                frame.buffIcons[i]:ClearAllPoints()
                frame.buffIcons[i]:SetPoint(bAnchor, frame, bAnchor, bOffX + offX, bOffY + offY)
                frame.buffIcons[i]:SetSize(iconSize, iconSize)
                -- Apply duration font size from settings
                if frame.buffIcons[i].durationText then
                    frame.buffIcons[i].durationText:SetFont(fontPath, buffFontSize, "OUTLINE")
                end
            end
            local bIcon = frame.buffIcons[i]
            SafeSetDrawSwipe(bIcon and bIcon.cooldown, auraSettings.buffHideSwipe ~= true)
            SafeSetReverse(bIcon and bIcon.cooldown, auraSettings.buffReverseSwipe == true)
            if auraData then
                bIcon._cachedShowPulse = showPulse
                UpdateAuraIcon(bIcon, auraData, unit)
            else
                bIcon:Hide()
                UnregisterIconTimer(frame.buffIcons[i])
            end
        end

        for i = maxBuffs + 1, #frame.buffIcons do
            frame.buffIcons[i]:Hide()
            UnregisterIconTimer(frame.buffIcons[i])
        end
    elseif frame.buffIcons then
        for _, icon in ipairs(frame.buffIcons) do
            icon:Hide()
            UnregisterIconTimer(icon)
        end
    end

    -- Stamp layout version so we skip repositioning until settings change
    frameLayoutVersions[frame] = layoutVersion
end

---------------------------------------------------------------------------
-- EVENT HOOKUP: Listen to UNIT_AURA via the group frame event system
---------------------------------------------------------------------------
local function FixIconMouse(icon, skipCombatCheck)
    if not icon then return end
    if not skipCombatCheck and InCombatLockdown() then return end
    pcall(function()
        icon:EnableMouse(true)
        if icon.SetPropagateMouseMotion then icon:SetPropagateMouseMotion(true) end
        if icon.SetPropagateMouseClicks then icon:SetPropagateMouseClicks(true) end
        if icon.SetMouseClickEnabled then icon:SetMouseClickEnabled(false) end
    end)
end

local function FixAllIconMouse()
    if InCombatLockdown() then return end
    local GF = ns.QUI_GroupFrames
    if not GF then return end
    for _, frame in pairs(GF.unitFrameMap) do
        if frame.debuffIcons then
            for _, icon in ipairs(frame.debuffIcons) do FixIconMouse(icon, true) end
        end
        if frame.buffIcons then
            for _, icon in ipairs(frame.buffIcons) do FixIconMouse(icon, true) end
        end
    end
    pendingMouseFix = false
end

-- (FlushPendingAuras removed: aura processing is inline in the dispatcher.
-- IncrementalUpdateAuras also removed: always full-scan now for simplicity
-- and to avoid per-aura GetAuraDataByAuraInstanceID table allocations.)

-- PLAYER_REGEN_ENABLED handler (mouse fix deferred from combat)
local regenFrame = CreateFrame("Frame")
regenFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
regenFrame:SetScript("OnEvent", function(self, event)
    if pendingMouseFix then FixAllIconMouse() end
end)

-- Subscribe to centralized aura dispatcher for group frame aura updates.
-- Always full-scan: ignores updateInfo deltas entirely. GetUnitAuras returns
-- one bulk table per filter type (zero per-aura allocation). This is simpler
-- and avoids the GetAuraDataByAuraInstanceID calls that created hundreds of
-- ~600-byte Blizzard tables per second in raids, overwhelming the GC.
if ns.AuraEvents then
    ns.AuraEvents:Subscribe("roster", function(unit)
        local GF = ns.QUI_GroupFrames
        if not GF or not GF.initialized then return end

        local frame = GF.unitFrameMap[unit]
        if not frame or not frame:IsShown() then return end

        -- Full scan: wipe + rebuild cache from GetUnitAuras (2 C-side calls)
        ScanUnitAuras(unit)

        -- Update all consumers: dispel overlay, defensive indicator,
        -- aura indicators, pinned auras, and icon display.
        if GF.UpdateDispelOverlay then GF:UpdateDispelOverlay(frame) end
        if GF.UpdateDefensiveIndicator then GF:UpdateDefensiveIndicator(frame) end
        local GFI = ns.QUI_GroupFrameIndicators
        if GFI and GFI.RefreshFrame then GFI:RefreshFrame(frame) end
        local GFP = ns.QUI_GroupFramePinnedAuras
        if GFP and GFP.RefreshFrame then GFP:RefreshFrame(frame) end
        UpdateFrameAuras(frame)
    end)
end

---------------------------------------------------------------------------
-- PUBLIC: Bump layout version (call when aura settings change in options)
---------------------------------------------------------------------------
function QUI_GFA:InvalidateLayout()
    layoutVersion = layoutVersion + 1
    _cachedFontPath = nil  -- force re-fetch on next access
    -- Refresh cached setting for shared timer
    local db = GetDB()
    cachedShowDurationColor = db and db.auras and db.auras.showDurationColor ~= false
end

---------------------------------------------------------------------------
-- PUBLIC: Refresh all frames
---------------------------------------------------------------------------
function QUI_GFA:RefreshAll()
    local GF = ns.QUI_GroupFrames
    if not GF or not GF.initialized then return end

    -- Force layout recalculation on explicit refresh
    layoutVersion = layoutVersion + 1
    _cachedFontPath = nil  -- force re-fetch on next access
    -- Sync cached setting from DB
    local db = GetDB()
    cachedShowDurationColor = db and db.auras and db.auras.showDurationColor ~= false

    for unit, frame in pairs(GF.unitFrameMap) do
        if frame and frame:IsShown() then
            ScanUnitAuras(unit)
            UpdateFrameAuras(frame)
        end
    end
end

function QUI_GFA:RefreshFrame(frame)
    if frame and frame.unit then
        ScanUnitAuras(frame.unit)
    end
    UpdateFrameAuras(frame)
end
