---------------------------------------------------------------------------
-- QUI Action Tracker
-- Displays recent player-triggered casts as animated icons.
---------------------------------------------------------------------------
local ADDON_NAME, ns = ...
local Helpers = ns.Helpers
local UIKit = ns.UIKit

local DEFAULT_SETTINGS = {
    enabled = false,
    onlyInCombat = true,
    clearOnCombatEnd = true,
    inactivityFadeEnabled = false,
    inactivityFadeSeconds = 20,
    clearOnInactivity = false,
    showFailedCasts = true,
    maxEntries = 6,
    iconSize = 28,
    iconSpacing = 4,
    iconHideBorder = false,
    iconBorderUseClassColor = false,
    iconBorderColor = {0, 0, 0, 0.85},
    orientation = "VERTICAL", -- VERTICAL | HORIZONTAL
    invertScrollDirection = false,
    xOffset = 0,
    yOffset = -210,
    blocklistText = "",
    showBackdrop = true,
    hideBorder = false,
    borderSize = 1,
    backdropColor = {0, 0, 0, 0.6},
    borderColor = {0, 0, 0, 1},
}

local PREVIEW_ENTRIES = {
    { name = "Fireball", icon = 135812, spellID = 133 },
    { name = "Counterspell", icon = 135856, spellID = 2139 },
    { name = "Blink", icon = 135736, spellID = 1953 },
    { name = "Ice Barrier", icon = 135988, spellID = 11426 },
}

local STARTUP_SUPPRESS_SECONDS = 5
local DEDUP_WINDOW = 0.15
local SENT_CAST_WINDOW = 2.0
local FALLBACK_ICON = 136243
local CONTAINER_PADDING = 4
local ANIMATION_LERP_RATE = 18
local COMBAT_EXIT_FADE_DURATION = 0.2

-- Forward declarations for helpers referenced before definition.
local LayoutIcons, ClearHistory
local RefreshActionTracker

local state = {
    frame = nil,
    history = {},
    preview = false,
    inCombat = false,
    suppressUntil = 0,

    -- Cast lifecycle tracking
    castByGUID = {},
    sentByGUID = {},
    sentBySpell = {},

    -- Action bar fallback filter for instant spells
    actionBarSpells = {},
    actionBarCacheReady = false,

    -- Blocklist cache
    blockedSpells = {},

    -- Icon rendering state
    iconPool = {},
    activeIcons = {},
    iconByEntry = {},

    -- Combat-exit fade state
    pendingClearOnFade = false,
    fadeOutToken = 0,

    -- Inactivity fade tracking
    lastActivityTime = 0,
    inactivityTicker = nil,
}

local function CopyColor(color, fallback)
    if type(color) ~= "table" then
        return { fallback[1], fallback[2], fallback[3], fallback[4] }
    end
    return {
        color[1] or fallback[1],
        color[2] or fallback[2],
        color[3] or fallback[3],
        color[4] or fallback[4],
    }
end

local function Clamp(value, minValue, maxValue)
    local n = tonumber(value)
    if not n then return minValue end
    if n < minValue then return minValue end
    if n > maxValue then return maxValue end
    return n
end

local function GetSpellNameAndIcon(spellID)
    if C_Spell and C_Spell.GetSpellInfo then
        local info = C_Spell.GetSpellInfo(spellID)
        if info then
            return info.name, info.iconID
        end
    end

    if type(GetSpellInfo) == "function" then
        local name, _, icon = GetSpellInfo(spellID)
        return name, icon
    end

    return nil, nil
end

local function GetSettings()
    local general = Helpers.GetModuleDB("general")
    if not general then
        return nil
    end

    if type(general.actionTracker) ~= "table" then
        general.actionTracker = {}
    end

    local settings = general.actionTracker
    for key, defaultValue in pairs(DEFAULT_SETTINGS) do
        if settings[key] == nil then
            if type(defaultValue) == "table" then
                settings[key] = CopyColor(defaultValue, defaultValue)
            else
                settings[key] = defaultValue
            end
        end
    end

    settings.maxEntries = math.floor(Clamp(settings.maxEntries, 1, 10))
    settings.iconSize = math.floor(Clamp(settings.iconSize, 16, 64))
    settings.iconSpacing = math.floor(Clamp(settings.iconSpacing, 0, 24))
    settings.iconHideBorder = settings.iconHideBorder == true
    settings.iconBorderUseClassColor = settings.iconBorderUseClassColor == true
    settings.iconBorderColor = CopyColor(settings.iconBorderColor, DEFAULT_SETTINGS.iconBorderColor)
    settings.inactivityFadeEnabled = settings.inactivityFadeEnabled == true
    settings.inactivityFadeSeconds = math.floor(Clamp(settings.inactivityFadeSeconds, 10, 60))
    settings.clearOnInactivity = settings.clearOnInactivity == true
    settings.orientation = (settings.orientation == "HORIZONTAL") and "HORIZONTAL" or "VERTICAL"
    if settings.invertScrollDirection == nil then
        -- Backward compatibility: migrate old enum direction to boolean invert.
        if settings.orientation == "HORIZONTAL" then
            settings.invertScrollDirection = settings.scrollDirection == "LEFT"
        else
            settings.invertScrollDirection = settings.scrollDirection == "UP"
        end
    end
    settings.invertScrollDirection = settings.invertScrollDirection == true

    settings.backdropColor = CopyColor(settings.backdropColor, DEFAULT_SETTINGS.backdropColor)
    settings.borderColor = CopyColor(settings.borderColor, DEFAULT_SETTINGS.borderColor)
    settings.borderSize = Clamp(settings.borderSize, 0, 5)

    return settings
end

---------------------------------------------------------------------------
-- FILTERING CACHE
---------------------------------------------------------------------------
local function RebuildBlocklist(settings)
    if type(wipe) == "function" then
        wipe(state.blockedSpells)
    else
        state.blockedSpells = {}
    end

    if not settings then
        return
    end

    if type(settings.blocklistText) == "string" then
        for token in string.gmatch(settings.blocklistText, "[^,%s]+") do
            local spellID = tonumber(token)
            if spellID and spellID > 0 then
                state.blockedSpells[spellID] = true
            end
        end
    elseif type(settings.blocklistText) == "table" then
        for key, value in pairs(settings.blocklistText) do
            local spellID = tonumber(key) or tonumber(value)
            if spellID and spellID > 0 then
                state.blockedSpells[spellID] = true
            end
        end
    end
end

local function IsSpellBlocked(spellID)
    return state.blockedSpells[spellID] == true
end

local function CleanupSentCasts(now)
    for castGUID, data in pairs(state.sentByGUID) do
        if not data.timestamp or (now - data.timestamp) > SENT_CAST_WINDOW then
            state.sentByGUID[castGUID] = nil
        end
    end

    for spellID, timestamps in pairs(state.sentBySpell) do
        local write = 1
        for read = 1, #timestamps do
            local ts = timestamps[read]
            if ts and (now - ts) <= SENT_CAST_WINDOW then
                timestamps[write] = ts
                write = write + 1
            end
        end
        for i = #timestamps, write, -1 do
            timestamps[i] = nil
        end
        if #timestamps == 0 then
            state.sentBySpell[spellID] = nil
        end
    end
end

local function MarkSentCast(castGUID, spellID)
    local now = GetTime()
    CleanupSentCasts(now)

    local numericSpellID = tonumber(spellID)
    if numericSpellID then
        local bucket = state.sentBySpell[numericSpellID]
        if not bucket then
            bucket = {}
            state.sentBySpell[numericSpellID] = bucket
        end
        bucket[#bucket + 1] = now
        if #bucket > 20 then
            table.remove(bucket, 1)
        end
    end

    if castGUID then
        state.sentByGUID[castGUID] = {
            timestamp = now,
            spellID = numericSpellID,
        }
    end
end

local function ConsumeSentSpell(spellID)
    local numericSpellID = tonumber(spellID)
    if not numericSpellID then
        return false
    end

    local bucket = state.sentBySpell[numericSpellID]
    if not bucket or #bucket == 0 then
        return false
    end

    table.remove(bucket, 1)
    if #bucket == 0 then
        state.sentBySpell[numericSpellID] = nil
    end

    return true
end

local function WasSentCast(castGUID, spellID)
    local now = GetTime()
    CleanupSentCasts(now)

    if castGUID then
        local sent = state.sentByGUID[castGUID]
        if sent then
            local numericSpellID = tonumber(spellID)
            if sent.spellID and numericSpellID and sent.spellID ~= numericSpellID then
                return false
            end
            state.sentByGUID[castGUID] = nil
            ConsumeSentSpell(spellID)
            return true
        end
    end

    -- Fallback for instant casts with unreliable GUID linkage.
    if ConsumeSentSpell(spellID) then
        if castGUID then
            state.sentByGUID[castGUID] = nil
        end
        return true
    end

    return false
end

local function ExtractCastGUIDAndSpellID(...)
    local castGUID, spellID
    local lastNumeric

    for i = 1, select("#", ...) do
        local value = select(i, ...)
        if type(value) == "number" then
            lastNumeric = value
            spellID = value
        end
    end

    if not spellID then
        spellID = lastNumeric
    end

    return castGUID, spellID
end

local function RefreshActionBarSpellCache()
    local spells = state.actionBarSpells
    if type(wipe) == "function" then
        wipe(spells)
    else
        state.actionBarSpells = {}
        spells = state.actionBarSpells
    end

    for slot = 1, 180 do
        local actionType, actionID = GetActionInfo(slot)
        if actionType == "spell" and type(actionID) == "number" and actionID > 0 then
            spells[actionID] = true
        elseif actionType == "macro" and type(actionID) == "number" and actionID > 0 then
            local a, b, c = GetMacroSpell(actionID)
            local macroSpellID = type(a) == "number" and a or type(b) == "number" and b or type(c) == "number" and c or nil
            if macroSpellID and macroSpellID > 0 then
                spells[macroSpellID] = true
            end
        end
    end

    state.actionBarCacheReady = true
end

local function IsActionBarSpell(spellID)
    local numericSpellID = tonumber(spellID)
    if not numericSpellID then
        return false
    end
    if not state.actionBarCacheReady then
        RefreshActionBarSpellCache()
    end
    return state.actionBarSpells[numericSpellID] == true
end

---------------------------------------------------------------------------
-- ICON RENDERING
---------------------------------------------------------------------------
local function RemoveActiveIcon(icon)
    for i = #state.activeIcons, 1, -1 do
        if state.activeIcons[i] == icon then
            table.remove(state.activeIcons, i)
            return
        end
    end
end

local function CreateIconFrame()
    local icon = CreateFrame("Frame", nil, state.frame)
    icon:SetSize(DEFAULT_SETTINGS.iconSize, DEFAULT_SETTINGS.iconSize)

    icon.border = icon:CreateTexture(nil, "BACKGROUND")
    icon.border:SetPoint("TOPLEFT", icon, "TOPLEFT", -1, 1)
    icon.border:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", 1, -1)
    icon.border:SetColorTexture(0, 0, 0, 0.85)

    icon.tex = icon:CreateTexture(nil, "ARTWORK")
    icon.tex:SetAllPoints()
    icon.tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    icon.tex:SetTexture(FALLBACK_ICON)

    icon:Hide()
    return icon
end

local function AcquireIconFrame()
    local icon = table.remove(state.iconPool, #state.iconPool)
    if not icon then
        icon = CreateIconFrame()
    end

    icon.currentX = nil
    icon.currentY = nil
    icon.currentAlpha = nil
    icon.targetX = nil
    icon.targetY = nil
    icon.targetAlpha = nil
    icon.removeWhenDone = false
    icon.entry = nil

    table.insert(state.activeIcons, icon)
    return icon
end

local function ReleaseIconFrame(icon)
    if not icon then return end
    RemoveActiveIcon(icon)
    icon:Hide()
    icon:ClearAllPoints()
    icon.entry = nil
    icon.currentX = nil
    icon.currentY = nil
    icon.currentAlpha = nil
    icon.targetX = nil
    icon.targetY = nil
    icon.targetAlpha = nil
    icon.removeWhenDone = false
    table.insert(state.iconPool, icon)
end

local function SetIconCurrent(icon, x, y, alpha)
    icon.currentX = x
    icon.currentY = y
    icon.currentAlpha = alpha
    icon:ClearAllPoints()
    icon:SetPoint("TOPLEFT", state.frame, "TOPLEFT", x, y)
    icon:SetAlpha(alpha)
    icon:Show()
end

local function SetIconTarget(icon, x, y, alpha, removeWhenDone)
    icon.targetX = x
    icon.targetY = y
    icon.targetAlpha = alpha
    icon.removeWhenDone = removeWhenDone == true
end

local function GetIconBorderColor(settings)
    if settings.iconBorderUseClassColor and Helpers and Helpers.GetPlayerClassColor then
        local r, g, b = Helpers.GetPlayerClassColor()
        if r and g and b then
            return r, g, b, settings.iconBorderColor[4] or 0.85
        end
    end
    local c = settings.iconBorderColor or DEFAULT_SETTINGS.iconBorderColor
    return c[1], c[2], c[3], c[4]
end

local function StyleIconForEntry(icon, entry, settings)
    icon.tex:SetTexture(entry.icon or FALLBACK_ICON)
    icon.tex:SetDesaturated(entry.failed == true)

    if settings.iconHideBorder == true then
        icon.border:Hide()
    else
        icon.border:Show()
        local br, bg, bb, ba = GetIconBorderColor(settings)
        icon.border:SetColorTexture(br or 0, bg or 0, bb or 0, ba or 0.85)
    end

    if entry.failed then
        icon.tex:SetVertexColor(1, 0.35, 0.35, 1)
    elseif entry.casting then
        icon.tex:SetVertexColor(1, 1, 1, 1)
    else
        icon.tex:SetVertexColor(1, 1, 1, 1)
    end
end

local function GetDirectionAndStep(settings)
    local step = (settings.iconSize or DEFAULT_SETTINGS.iconSize) + (settings.iconSpacing or DEFAULT_SETTINGS.iconSpacing)
    if settings.orientation == "HORIZONTAL" then
        local dirX = (settings.invertScrollDirection == true) and -1 or 1
        return dirX, 0, step
    end
    local dirY = (settings.invertScrollDirection == true) and 1 or -1
    return 0, dirY, step
end

local function GetTargetPosition(index, settings, step)
    if settings.orientation == "HORIZONTAL" then
        if settings.invertScrollDirection == true then
            return CONTAINER_PADDING + ((settings.maxEntries - index) * step), -CONTAINER_PADDING
        end
        return CONTAINER_PADDING + ((index - 1) * step), -CONTAINER_PADDING
    end

    if settings.invertScrollDirection == true then
        return CONTAINER_PADDING, -CONTAINER_PADDING - ((settings.maxEntries - index) * step)
    end
    return CONTAINER_PADDING, -CONTAINER_PADDING - ((index - 1) * step)
end

local function ShouldShowTracker(settings)
    if not settings or not settings.enabled then
        return false
    end
    if state.preview then
        return true
    end
    if settings.onlyInCombat and not state.inCombat then
        return false
    end
    if settings.inactivityFadeEnabled and state.lastActivityTime > 0 and not state.preview then
        if (GetTime() - state.lastActivityTime) >= settings.inactivityFadeSeconds then
            return false
        end
    end
    return true
end

local function OnAnimate(_, elapsed)
    if not state.frame then return end

    local anyMoving = false
    local blend = math.min(1, elapsed * ANIMATION_LERP_RATE)

    for i = #state.activeIcons, 1, -1 do
        local icon = state.activeIcons[i]
        if icon.targetX ~= nil and icon.targetY ~= nil and icon.targetAlpha ~= nil then
            if icon.currentX == nil or icon.currentY == nil or icon.currentAlpha == nil then
                SetIconCurrent(icon, icon.targetX, icon.targetY, icon.targetAlpha)
            end

            local dx = icon.targetX - icon.currentX
            local dy = icon.targetY - icon.currentY
            local da = icon.targetAlpha - icon.currentAlpha

            if math.abs(dx) < 0.25 then dx = 0 end
            if math.abs(dy) < 0.25 then dy = 0 end
            if math.abs(da) < 0.02 then da = 0 end

            if dx ~= 0 or dy ~= 0 or da ~= 0 then
                icon.currentX = icon.currentX + (dx * blend)
                icon.currentY = icon.currentY + (dy * blend)
                icon.currentAlpha = icon.currentAlpha + (da * blend)
                anyMoving = true
            else
                icon.currentX = icon.targetX
                icon.currentY = icon.targetY
                icon.currentAlpha = icon.targetAlpha
            end

            icon:ClearAllPoints()
            icon:SetPoint("TOPLEFT", state.frame, "TOPLEFT", icon.currentX, icon.currentY)
            icon:SetAlpha(icon.currentAlpha)
            icon:Show()

            if icon.removeWhenDone and icon.currentAlpha <= 0.02 and dx == 0 and dy == 0 then
                ReleaseIconFrame(icon)
            end
        end
    end

    if not anyMoving then
        state.frame:SetScript("OnUpdate", nil)
    end
end

local function StartAnimationLoop()
    if state.frame and state.frame:GetScript("OnUpdate") ~= OnAnimate then
        state.frame:SetScript("OnUpdate", OnAnimate)
    end
end

local function StopAnimationLoop()
    if state.frame then
        state.frame:SetScript("OnUpdate", nil)
    end
end

local function BuildDisplayEntries(settings)
    local source = state.preview and PREVIEW_ENTRIES or state.history
    local entries = {}
    for _, entry in ipairs(source) do
        if settings.showFailedCasts ~= false or not entry.failed then
            entries[#entries + 1] = entry
            if #entries >= settings.maxEntries then
                break
            end
        end
    end
    return entries
end

LayoutIcons = function(animate)
    local settings = GetSettings()
    if not settings or not state.frame then
        return
    end

    local entries = BuildDisplayEntries(settings)
    local dirX, dirY, step = GetDirectionAndStep(settings)
    local usedEntries = {}

    for index, entry in ipairs(entries) do
        local icon = state.iconByEntry[entry]
        local isNew = icon == nil
        if not icon then
            icon = AcquireIconFrame()
            state.iconByEntry[entry] = icon
            icon.entry = entry
        end

        icon:SetSize(settings.iconSize, settings.iconSize)
        StyleIconForEntry(icon, entry, settings)

        local targetX, targetY = GetTargetPosition(index, settings, step)
        if isNew then
            if animate then
                SetIconCurrent(icon, targetX - (dirX * step), targetY - (dirY * step), 0)
            else
                SetIconCurrent(icon, targetX, targetY, 1)
            end
        end

        SetIconTarget(icon, targetX, targetY, 1, false)
        usedEntries[entry] = true
    end

    local staleEntries = {}
    for entry in pairs(state.iconByEntry) do
        if not usedEntries[entry] then
            staleEntries[#staleEntries + 1] = entry
        end
    end

    for _, entry in ipairs(staleEntries) do
        local icon = state.iconByEntry[entry]
        state.iconByEntry[entry] = nil
        if icon then
            if animate then
                local startX = icon.currentX or icon.targetX or CONTAINER_PADDING
                local startY = icon.currentY or icon.targetY or -CONTAINER_PADDING
                local targetX = startX + (dirX * step)
                local targetY = startY + (dirY * step)
                SetIconTarget(icon, targetX, targetY, 0, true)
            else
                ReleaseIconFrame(icon)
            end
        end
    end

    if animate then
        StartAnimationLoop()
    else
        StopAnimationLoop()
        for i = #state.activeIcons, 1, -1 do
            local icon = state.activeIcons[i]
            if icon.removeWhenDone then
                ReleaseIconFrame(icon)
            elseif icon.targetX and icon.targetY and icon.targetAlpha then
                SetIconCurrent(icon, icon.targetX, icon.targetY, icon.targetAlpha)
            end
        end
    end
end

local function CreateTrackerFrame()
    if state.frame then
        return
    end

    local frame = CreateFrame("Frame", "QUI_ActionTracker", UIParent, "BackdropTemplate")
    frame:SetFrameStrata("HIGH")
    frame:SetFrameLevel(50)
    frame:SetMovable(true)
    frame:SetClampedToScreen(true)
    frame:EnableMouse(false)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function(self)
        if state.preview ~= true then return end
        if _G.QUI_IsFrameOverridden and _G.QUI_IsFrameOverridden(self) then return end
        self:StartMoving()
    end)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        if state.preview ~= true then return end
        if _G.QUI_IsFrameOverridden and _G.QUI_IsFrameOverridden(self) then return end

        local settings = GetSettings()
        if not settings then return end
        local frameX, frameY = self:GetCenter()
        local uiX, uiY = UIParent:GetCenter()
        if not (frameX and frameY and uiX and uiY) then return end

        local relX = frameX - uiX
        local relY = frameY - uiY
        -- Match existing slider granularity (integer offsets).
        if relX >= 0 then
            settings.xOffset = math.floor(relX + 0.5)
        else
            settings.xOffset = math.ceil(relX - 0.5)
        end
        if relY >= 0 then
            settings.yOffset = math.floor(relY + 0.5)
        else
            settings.yOffset = math.ceil(relY - 0.5)
        end

        if RefreshActionTracker then
            RefreshActionTracker()
        end
    end)
    frame:Hide()
    state.frame = frame
end

local function UpdatePreviewDragState()
    if not state.frame then return end
    local canDrag = state.preview == true
        and not (_G.QUI_IsFrameOverridden and _G.QUI_IsFrameOverridden(state.frame))

    state.frame:EnableMouse(canDrag)
    if not canDrag then
        state.frame:StopMovingOrSizing()
    end
end

local function RefreshAppearance()
    local settings = GetSettings()
    if not settings then
        return
    end

    CreateTrackerFrame()
    if not state.frame then
        return
    end

    local _, _, step = GetDirectionAndStep(settings)
    local width, height
    if settings.orientation == "HORIZONTAL" then
        width = (CONTAINER_PADDING * 2) + settings.iconSize + ((settings.maxEntries - 1) * step)
        height = (CONTAINER_PADDING * 2) + settings.iconSize
    else
        width = (CONTAINER_PADDING * 2) + settings.iconSize
        height = (CONTAINER_PADDING * 2) + settings.iconSize + ((settings.maxEntries - 1) * step)
    end

    local isOverridden = _G.QUI_IsFrameOverridden and _G.QUI_IsFrameOverridden(state.frame)
    if not isOverridden then
        state.frame:ClearAllPoints()
        state.frame:SetPoint("CENTER", UIParent, "CENTER", settings.xOffset or 0, settings.yOffset or 0)
    end
    state.frame:SetSize(width, height)

    if settings.showBackdrop ~= false then
        if UIKit and UIKit.GetBackdropInfo then
            state.frame:SetBackdrop(UIKit.GetBackdropInfo(nil, nil, state.frame))
        end
        state.frame:SetBackdropColor(
            settings.backdropColor[1],
            settings.backdropColor[2],
            settings.backdropColor[3],
            settings.backdropColor[4]
        )
    else
        state.frame:SetBackdrop(nil)
    end

    if UIKit and UIKit.CreateBorderLines and UIKit.UpdateBorderLines then
        UIKit.CreateBorderLines(state.frame)
        UIKit.UpdateBorderLines(
            state.frame,
            settings.borderSize or 1,
            settings.borderColor[1],
            settings.borderColor[2],
            settings.borderColor[3],
            settings.borderColor[4],
            settings.hideBorder == true or (settings.borderSize or 1) <= 0
        )
    end

    UpdatePreviewDragState()
    LayoutIcons(false)
end

local function RefreshVisibility(useFadeOut)
    local settings = GetSettings()
    if not settings or not state.frame then
        return
    end

    local inactivityTimedOut = settings.inactivityFadeEnabled
        and not state.preview
        and state.lastActivityTime > 0
        and (GetTime() - state.lastActivityTime) >= settings.inactivityFadeSeconds
    local clearAfterHide = state.pendingClearOnFade
        or (inactivityTimedOut and settings.clearOnInactivity == true)

    if ShouldShowTracker(settings) then
        state.fadeOutToken = (state.fadeOutToken or 0) + 1
        state.pendingClearOnFade = false
        state.frame:SetAlpha(1)
        UpdatePreviewDragState()
        state.frame:Show()
    else
        state.pendingClearOnFade = clearAfterHide
        StopAnimationLoop()
        UpdatePreviewDragState()
        if useFadeOut and state.frame:IsShown() then
            local token = (state.fadeOutToken or 0) + 1
            state.fadeOutToken = token

            local fromAlpha = state.frame:GetAlpha() or 1
            if fromAlpha <= 0 then
                fromAlpha = 1
            end

            if type(UIFrameFadeOut) == "function" then
                UIFrameFadeOut(state.frame, COMBAT_EXIT_FADE_DURATION, fromAlpha, 0)
            else
                state.frame:SetAlpha(0)
            end

            C_Timer.After(COMBAT_EXIT_FADE_DURATION + 0.02, function()
                if not state.frame then return end
                if state.fadeOutToken ~= token then return end

                local latest = GetSettings()
                if latest and ShouldShowTracker(latest) then
                    return
                end

                state.frame:Hide()
                state.frame:SetAlpha(1)
                if state.pendingClearOnFade then
                    state.pendingClearOnFade = false
                    ClearHistory()
                    LayoutIcons(false)
                end
            end)
        else
            state.fadeOutToken = (state.fadeOutToken or 0) + 1
            state.frame:Hide()
            state.frame:SetAlpha(1)
            if state.pendingClearOnFade then
                state.pendingClearOnFade = false
                ClearHistory()
                LayoutIcons(false)
            end
        end
    end
end

local function StopInactivityTicker()
    if state.inactivityTicker then
        state.inactivityTicker:Cancel()
        state.inactivityTicker = nil
    end
end

local function StartInactivityTicker()
    if state.inactivityTicker then
        return
    end

    state.inactivityTicker = C_Timer.NewTicker(0.5, function()
        local settings = GetSettings()
        if not settings or not state.frame then
            return
        end
        if settings.enabled ~= true or settings.inactivityFadeEnabled ~= true then
            return
        end
        RefreshVisibility(true)
    end)
end

local function RefreshInactivityTicker(settings)
    if settings and settings.enabled == true and settings.inactivityFadeEnabled == true then
        StartInactivityTicker()
    else
        StopInactivityTicker()
    end
end

---------------------------------------------------------------------------
-- HISTORY / CAST LIFECYCLE
---------------------------------------------------------------------------
ClearHistory = function()
    if type(wipe) == "function" then
        wipe(state.history)
        wipe(state.castByGUID)
        wipe(state.sentByGUID)
        wipe(state.sentBySpell)
    else
        state.history = {}
        state.castByGUID = {}
        state.sentByGUID = {}
        state.sentBySpell = {}
    end

    for entry, icon in pairs(state.iconByEntry) do
        state.iconByEntry[entry] = nil
        ReleaseIconFrame(icon)
    end
end

local function TrimHistoryToLimit(maxEntries)
    while #state.history > maxEntries do
        local removed = table.remove(state.history)
        if removed and removed.castGUID then
            state.castByGUID[removed.castGUID] = nil
        end
    end
end

local function AddSpellToHistory(spellID, castGUID, casting, failed, isChannel)
    local settings = GetSettings()
    if not settings or not settings.enabled then return nil end

    if Helpers.IsSecretValue and Helpers.IsSecretValue(spellID) then return nil end

    local numericSpellID = tonumber(spellID)
    if not numericSpellID then return nil end
    if settings.onlyInCombat and not state.inCombat and not state.preview then return nil end
    if IsSpellBlocked(numericSpellID) then return nil end

    local spellName, spellIcon = GetSpellNameAndIcon(numericSpellID)
    if not spellName and not spellIcon then return nil end

    local now = GetTime()
    state.lastActivityTime = now
    local lastEntry = state.history[1]
    if lastEntry and lastEntry.spellID == numericSpellID and not castGUID and (now - (lastEntry.timestamp or 0)) < DEDUP_WINDOW then
        return nil
    end

    local entry = {
        spellID = numericSpellID,
        name = spellName or ("Spell " .. tostring(numericSpellID)),
        icon = spellIcon or FALLBACK_ICON,
        timestamp = now,
        castGUID = castGUID,
        casting = casting == true,
        failed = failed == true,
        channel = isChannel == true,
    }

    table.insert(state.history, 1, entry)
    if castGUID then
        state.castByGUID[castGUID] = entry
    end

    TrimHistoryToLimit(settings.maxEntries)
    LayoutIcons(true)
    RefreshVisibility()
    return entry
end

local function ResolveCastToSucceeded(castGUID, spellID, fromChannelStop)
    if castGUID and state.castByGUID[castGUID] then
        local entry = state.castByGUID[castGUID]
        if entry.channel and not fromChannelStop then
            return
        end
        entry.casting = false
        entry.failed = false
        entry.channel = false
        state.castByGUID[castGUID] = nil
        state.sentByGUID[castGUID] = nil
        LayoutIcons(true)
        RefreshVisibility()
        return
    end

    if WasSentCast(castGUID, spellID) then
        AddSpellToHistory(spellID, castGUID, false, false, false)
        if castGUID then
            state.castByGUID[castGUID] = nil
            state.sentByGUID[castGUID] = nil
        end
        return
    end

    -- Controlled fallback for instant melee/button casts.
    if IsActionBarSpell(spellID) then
        AddSpellToHistory(spellID, castGUID, false, false, false)
        if castGUID then
            state.castByGUID[castGUID] = nil
            state.sentByGUID[castGUID] = nil
        end
    end
end

local function ResolveCastToFailed(castGUID, spellID)
    local entry = castGUID and state.castByGUID[castGUID] or nil
    if not entry then return end

    entry.casting = false
    entry.channel = false

    local settings = GetSettings()
    if settings and settings.showFailedCasts == false then
        for i = #state.history, 1, -1 do
            if state.history[i] == entry then
                table.remove(state.history, i)
                break
            end
        end
    else
        entry.failed = true
    end

    if entry.castGUID then
        state.castByGUID[entry.castGUID] = nil
    end
    if castGUID then
        state.castByGUID[castGUID] = nil
        state.sentByGUID[castGUID] = nil
    end

    LayoutIcons(true)
    RefreshVisibility()
end

local function HandleCombatStart()
    state.inCombat = true
    state.lastActivityTime = GetTime()
    RefreshVisibility()
end

local function HandleCombatEnd()
    state.inCombat = false
    local settings = GetSettings()

    local shouldFadeOut = settings
        and settings.enabled == true
        and settings.onlyInCombat == true
        and state.preview ~= true
        and state.frame
        and state.frame:IsShown()

    if settings and settings.clearOnCombatEnd then
        if shouldFadeOut then
            state.pendingClearOnFade = true
        else
            ClearHistory()
        end
    end

    if not shouldFadeOut then
        LayoutIcons(false)
    end
    RefreshVisibility(shouldFadeOut)
end

RefreshActionTracker = function()
    local settings = GetSettings()
    CreateTrackerFrame()

    if not settings then
        StopInactivityTicker()
        if state.frame then
            StopAnimationLoop()
            state.frame:Hide()
        end
        return
    end

    if not settings.enabled then
        state.preview = false
    end

    if settings.showFailedCasts == false then
        for i = #state.history, 1, -1 do
            local entry = state.history[i]
            if entry.failed then
                if entry.castGUID then
                    state.castByGUID[entry.castGUID] = nil
                end
                table.remove(state.history, i)
            end
        end
    end

    RebuildBlocklist(settings)
    TrimHistoryToLimit(settings.maxEntries)
    RefreshActionBarSpellCache()
    RefreshInactivityTicker(settings)
    if state.lastActivityTime <= 0 then
        state.lastActivityTime = GetTime()
    end
    RefreshAppearance()
    -- Preserve anchor override position when changing tracker options.
    if state.frame and _G.QUI_IsFrameOverridden and _G.QUI_IsFrameOverridden(state.frame) and _G.QUI_ApplyFrameAnchor then
        _G.QUI_ApplyFrameAnchor("actionTracker")
    end
    RefreshVisibility()
end

local function TogglePreview(enable)
    state.preview = enable == true
    RefreshActionTracker()
end

local function IsPreviewMode()
    return state.preview
end

---------------------------------------------------------------------------
-- EVENTS
---------------------------------------------------------------------------
local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
eventFrame:RegisterEvent("ACTIONBAR_SLOT_CHANGED")
eventFrame:RegisterEvent("UPDATE_MACROS")
eventFrame:RegisterEvent("SPELLS_CHANGED")
eventFrame:RegisterUnitEvent("UNIT_SPELLCAST_START", "player")
eventFrame:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_START", "player")
eventFrame:RegisterUnitEvent("UNIT_SPELLCAST_SENT", "player")
eventFrame:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
eventFrame:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_STOP", "player")
eventFrame:RegisterUnitEvent("UNIT_SPELLCAST_FAILED", "player")
eventFrame:RegisterUnitEvent("UNIT_SPELLCAST_INTERRUPTED", "player")

eventFrame:SetScript("OnEvent", function(_, event, ...)
    if event == "PLAYER_LOGIN" then
        state.inCombat = InCombatLockdown()
        state.suppressUntil = GetTime() + STARTUP_SUPPRESS_SECONDS
        state.lastActivityTime = GetTime()
        RefreshActionBarSpellCache()
        C_Timer.After(0.5, RefreshActionTracker)
        return
    end

    if event == "PLAYER_ENTERING_WORLD" then
        state.suppressUntil = GetTime() + STARTUP_SUPPRESS_SECONDS
        RefreshActionBarSpellCache()
        return
    end

    if event == "PLAYER_REGEN_DISABLED" then
        HandleCombatStart()
        return
    end

    if event == "PLAYER_REGEN_ENABLED" then
        HandleCombatEnd()
        return
    end

    if event == "ACTIONBAR_SLOT_CHANGED" or event == "UPDATE_MACROS" or event == "SPELLS_CHANGED" then
        RefreshActionBarSpellCache()
        return
    end

    if GetTime() < state.suppressUntil then
        return
    end

    if event == "UNIT_SPELLCAST_SENT" then
        local sentCastGUID, sentSpellID = ExtractCastGUIDAndSpellID(...)
        if sentCastGUID or sentSpellID then
            MarkSentCast(sentCastGUID, sentSpellID)
        end
        return
    end

    local unit, castGUID, spellID = ...
    if unit ~= "player" then
        return
    end

    if event == "UNIT_SPELLCAST_START" or event == "UNIT_SPELLCAST_CHANNEL_START" then
        if castGUID and state.castByGUID[castGUID] then
            return
        end
        AddSpellToHistory(spellID, castGUID, true, false, event == "UNIT_SPELLCAST_CHANNEL_START")
    elseif event == "UNIT_SPELLCAST_SUCCEEDED" or event == "UNIT_SPELLCAST_CHANNEL_STOP" then
        ResolveCastToSucceeded(castGUID, spellID, event == "UNIT_SPELLCAST_CHANNEL_STOP")
    elseif event == "UNIT_SPELLCAST_FAILED" or event == "UNIT_SPELLCAST_INTERRUPTED" then
        ResolveCastToFailed(castGUID, spellID)
    end
end)

_G.QUI_RefreshActionTracker = RefreshActionTracker
_G.QUI_ToggleActionTrackerPreview = TogglePreview
_G.QUI_IsActionTrackerPreviewMode = IsPreviewMode

ns.QUI_ActionTracker = {
    Refresh = RefreshActionTracker,
    TogglePreview = TogglePreview,
    IsPreviewMode = IsPreviewMode,
}
