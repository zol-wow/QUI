---------------------------------------------------------------------------
-- QUI Unit Frames - Aura System
-- Buff/debuff icon creation, updating, preview mode, and tracking.
-- Extracted from modules/frames/unitframes.lua for maintainability.
---------------------------------------------------------------------------
local ADDON_NAME, ns = ...
local QUICore = ns.Addon

-- QUI_UF is created in unitframes.lua and exported to ns.QUI_UnitFrames.
-- This file loads after unitframes.lua, so the reference is available.
local QUI_UF = ns.QUI_UnitFrames
if not QUI_UF then return end

-- Internal helpers exposed by unitframes.lua
local GetFontPath = QUI_UF._GetFontPath
local GetFontOutline = QUI_UF._GetFontOutline
local GetUnitSettings = QUI_UF._GetUnitSettings
local UpdateFrame = QUI_UF._UpdateFrame

---------------------------------------------------------------------------
-- CONSTANTS
---------------------------------------------------------------------------

-- Preview aura data for buff/debuff preview mode (4 icons with varied stacks)
local PREVIEW_AURAS = {
    buffs = {
        {icon = "Interface\\Icons\\spell_nature_regenerate", stacks = 0, duration = 10},
        {icon = "Interface\\Icons\\spell_holy_powerwordshield", stacks = 0, duration = 10},
        {icon = "Interface\\Icons\\spell_nature_lightningshield", stacks = 3, duration = 10},
        {icon = "Interface\\Icons\\ability_warrior_battleshout", stacks = 5, duration = 10},
    },
    debuffs = {
        {icon = "Interface\\Icons\\spell_shadow_shadowwordpain", stacks = 0, duration = 10},
        {icon = "Interface\\Icons\\spell_shadow_mindblast", stacks = 0, duration = 10},
        {icon = "Interface\\Icons\\spell_nature_slow", stacks = 2, duration = 10},
        {icon = "Interface\\Icons\\spell_shadow_shadesofdarkness", stacks = 5, duration = 10},
    }
}

---------------------------------------------------------------------------
-- AURA THROTTLE STATE
---------------------------------------------------------------------------
local AURA_THROTTLE = 0.15  -- Update every 150ms max
local lastAuraUpdate = {}

-- Expose for QUI_RefreshAuras in unitframes.lua
QUI_UF._lastAuraUpdate = lastAuraUpdate

---------------------------------------------------------------------------
-- AURA ICON SETTINGS
---------------------------------------------------------------------------

-- Apply aura icon settings (for real-time updates without recreating icons)
-- isDebuff: true for debuffs, false for buffs - uses per-type settings when available
-- Duration text uses Blizzard's built-in countdown (handles secret values internally)
local function ApplyAuraIconSettings(icon, auraSettings, isDebuff)
    if not icon then return end
    auraSettings = auraSettings or {}

    local fontPath = GetFontPath()
    local fontOutline = GetFontOutline()

    -- Determine prefix for per-type settings (debuff* or buff*)
    local prefix = isDebuff and "debuff" or "buff"

    -- Stack text settings (per-type with fallback to shared settings)
    local showStack = auraSettings[prefix .. "ShowStack"]
    if showStack == nil then showStack = auraSettings.showStack end
    if showStack == nil then showStack = true end  -- default true

    local stackSize = auraSettings[prefix .. "StackSize"] or auraSettings.stackSize or 10
    local stackAnchor = auraSettings[prefix .. "StackAnchor"] or auraSettings.stackAnchor or "BOTTOMRIGHT"
    local stackOffsetX = auraSettings[prefix .. "StackOffsetX"] or auraSettings.stackOffsetX or -1
    local stackOffsetY = auraSettings[prefix .. "StackOffsetY"] or auraSettings.stackOffsetY or 1
    local stackColor = auraSettings[prefix .. "StackColor"] or auraSettings.stackColor or {1, 1, 1, 1}

    if icon.count then
        icon.count:SetFont(fontPath, stackSize, fontOutline)
        icon.count:ClearAllPoints()
        icon.count:SetPoint(stackAnchor, icon, stackAnchor, stackOffsetX, stackOffsetY)
        icon.count:SetTextColor(stackColor[1] or 1, stackColor[2] or 1, stackColor[3] or 1, stackColor[4] or 1)
    end
    icon._showStack = showStack

    -- Swipe toggle (per-type: debuffHideSwipe or buffHideSwipe)
    local hideSwipe = auraSettings[prefix .. "HideSwipe"]
    if hideSwipe == nil then hideSwipe = false end  -- default: show swipe
    if icon.cooldown then
        icon.cooldown:SetDrawSwipe(not hideSwipe)
    end

    -- Duration text settings (per-type)
    local showDuration = auraSettings[prefix .. "ShowDuration"]
    if showDuration == nil then showDuration = true end

    local durationSize = auraSettings[prefix .. "DurationSize"] or 12
    local durationAnchor = auraSettings[prefix .. "DurationAnchor"] or "CENTER"
    local durationOffsetX = auraSettings[prefix .. "DurationOffsetX"] or 0
    local durationOffsetY = auraSettings[prefix .. "DurationOffsetY"] or 0
    local durationColor = auraSettings[prefix .. "DurationColor"] or {1, 1, 1, 1}

    -- Safe duration text handling (pcall wrapped to prevent errors from breaking auras)
    if icon.cooldown then
        pcall(function()
            -- Toggle Blizzard countdown visibility
            if icon.cooldown.SetHideCountdownNumbers then
                icon.cooldown:SetHideCountdownNumbers(not showDuration)
            end

            -- Find and style the countdown FontString (created lazily by Blizzard)
            if showDuration and icon.cooldown.GetRegions then
                for _, region in ipairs({ icon.cooldown:GetRegions() }) do
                    if region and region.GetObjectType and region:GetObjectType() == "FontString" then
                        if region.SetFont then
                            region:SetFont(fontPath, durationSize, fontOutline)
                        end
                        if region.ClearAllPoints and region.SetPoint then
                            region:ClearAllPoints()
                            region:SetPoint(durationAnchor, icon, durationAnchor, durationOffsetX, durationOffsetY)
                        end
                        if region.SetTextColor then
                            region:SetTextColor(durationColor[1] or 1, durationColor[2] or 1, durationColor[3] or 1, durationColor[4] or 1)
                        end
                        break
                    end
                end
            end
        end)
    end
end

---------------------------------------------------------------------------
-- AURA ICON CREATION
---------------------------------------------------------------------------

local function CreateAuraIcon(parent, index, size, auraSettings, isDebuff)
    -- Use plain Frame (no BackdropTemplate) to avoid secret value crashes during combat
    -- BackdropTemplate causes "arithmetic on secret value" errors when frame is resized
    local icon = CreateFrame("Frame", nil, parent)
    -- Use parent's strata but higher frame level to render above unit frame
    -- (avoids showing through major UI panels like spellbook)
    icon:SetFrameLevel(parent:GetFrameLevel() + 10)
    icon:SetSize(size, size)

    -- Enable mouse for tooltip interaction
    icon:EnableMouse(true)

    -- Aura data storage for tooltips
    icon.unit = nil
    icon.auraInstanceID = nil
    icon.filter = nil  -- "HELPFUL" or "HARMFUL"

    -- Tooltip scripts using safe auraInstanceID API
    icon:SetScript("OnEnter", function(self)
        if self.unit and self.auraInstanceID then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            if self.filter == "HELPFUL" then
                GameTooltip:SetUnitBuffByAuraInstanceID(self.unit, self.auraInstanceID)
            else
                GameTooltip:SetUnitDebuffByAuraInstanceID(self.unit, self.auraInstanceID)
            end
            GameTooltip:Show()
        end
    end)

    icon:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    -- Border (using BACKGROUND texture to avoid secret value errors during combat)
    local border = icon:CreateTexture(nil, "BACKGROUND", nil, -8)
    border:SetColorTexture(0, 0, 0, 1)
    local iconPx = QUICore:GetPixelSize(icon)
    border:SetPoint("TOPLEFT", icon, "TOPLEFT", -iconPx, iconPx)
    border:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", iconPx, -iconPx)
    icon.border = border

    -- Icon texture
    local tex = icon:CreateTexture(nil, "ARTWORK")
    tex:SetPoint("TOPLEFT", 0, 0)
    tex:SetPoint("BOTTOMRIGHT", 0, 0)
    tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    icon.icon = tex

    -- Cooldown swipe
    local cd = CreateFrame("Cooldown", nil, icon, "CooldownFrameTemplate")
    cd:SetAllPoints(icon)
    cd:SetDrawEdge(false)
    cd:SetReverse(true)
    cd:SetSwipeTexture("Interface\\Buttons\\WHITE8X8")
    cd:SetSwipeColor(0, 0, 0, 0.8)
    cd.noOCC = true
    -- noCooldownCount removed to enable Blizzard countdown text (styled via ApplyAuraIconSettings)
    icon.cooldown = cd

    -- Stack count — parented to an overlay frame above the cooldown swipe
    local stackOverlay = CreateFrame("Frame", nil, icon)
    stackOverlay:SetAllPoints(icon)
    stackOverlay:SetFrameLevel(cd:GetFrameLevel() + 1)
    local count = stackOverlay:CreateFontString(nil, "OVERLAY")
    count:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", -iconPx, iconPx)  -- default, will be updated by settings
    count:SetTextColor(1, 1, 1, 1)
    icon.count = count
    icon._showStack = true  -- default

    -- Apply initial settings
    ApplyAuraIconSettings(icon, auraSettings, isDebuff)

    icon:Hide()
    return icon
end

local function GetAuraIcon(container, index, parent, size, auraSettings, isDebuff)
    if container[index] then
        container[index]:SetSize(size, size)
        -- Update settings on existing icon
        ApplyAuraIconSettings(container[index], auraSettings, isDebuff)
        return container[index]
    end

    local icon = CreateAuraIcon(parent, index, size, auraSettings, isDebuff)
    container[index] = icon
    return icon
end

---------------------------------------------------------------------------
-- AURA UPDATE
---------------------------------------------------------------------------

local function UpdateAuras(frame)
    if not frame or not frame.unit then return end
    local unit = frame.unit

    if not UnitExists(unit) then
        -- Hide all auras
        if frame.buffIcons then
            for _, icon in ipairs(frame.buffIcons) do
                icon:Hide()
            end
        end
        if frame.debuffIcons then
            for _, icon in ipairs(frame.debuffIcons) do
                icon:Hide()
            end
        end
        return
    end

    -- Throttle updates
    local now = GetTime()
    local lastUpdate = lastAuraUpdate[unit] or 0
    if (now - lastUpdate) < AURA_THROTTLE then
        return
    end
    lastAuraUpdate[unit] = now

    -- Check if C_UnitAuras is available
    if not C_UnitAuras or not C_UnitAuras.GetAuraDataByIndex then
        return
    end

    -- Get settings from database
    local settings = GetUnitSettings(frame.unitKey)
    local auraSettings = settings and settings.auras or {}

    local iconSize = auraSettings.iconSize or 22  -- Debuff icon size
    local buffIconSize = auraSettings.buffIconSize or 22  -- Buff icon size
    local showBuffs = auraSettings.showBuffs ~= false  -- default true
    local showDebuffs = auraSettings.showDebuffs ~= false  -- default true
    local onlyMyDebuffs = auraSettings.onlyMyDebuffs ~= false  -- default true

    -- Check if in preview mode for either aura type
    local unitKey = frame.unitKey
    local buffPreviewActive = QUI_UF.auraPreviewMode[unitKey .. "_buff"]
    local debuffPreviewActive = QUI_UF.auraPreviewMode[unitKey .. "_debuff"]

    -- Debuff settings
    local debuffAnchor = auraSettings.debuffAnchor or "TOPLEFT"
    local debuffGrow = auraSettings.debuffGrow or "RIGHT"
    local debuffMaxIcons = auraSettings.debuffMaxIcons or 16
    local debuffOffsetX = auraSettings.debuffOffsetX or 0
    local debuffOffsetY = auraSettings.debuffOffsetY or 2
    local debuffSpacing = auraSettings.debuffSpacing or auraSettings.iconSpacing or 2

    -- Buff settings
    local buffAnchor = auraSettings.buffAnchor or "BOTTOMLEFT"
    local buffGrow = auraSettings.buffGrow or "RIGHT"
    local buffMaxIcons = auraSettings.buffMaxIcons or 16
    local buffOffsetX = auraSettings.buffOffsetX or 0
    local buffOffsetY = auraSettings.buffOffsetY or -2
    local buffSpacing = auraSettings.buffSpacing or auraSettings.iconSpacing or 2

    -- Initialize containers
    frame.buffIcons = frame.buffIcons or {}
    frame.debuffIcons = frame.debuffIcons or {}

    -- Hide existing icons first (skip if preview is active for that type)
    if not buffPreviewActive then
        for _, icon in ipairs(frame.buffIcons) do
            icon:Hide()
        end
    end
    if not debuffPreviewActive then
        for _, icon in ipairs(frame.debuffIcons) do
            icon:Hide()
        end
    end

    -- Helper to safely set cooldown (handles secret values on enemy targets)
    -- Uses duration object API when available for combat-safe cooldown display
    local function SafeSetCooldown(cooldownFrame, auraData, unit)
        if not cooldownFrame then return false end
        if not auraData then return false end

        local applied = false

        -- Prefer duration object API (combat-safe on enemy targets)
        if cooldownFrame.SetCooldownFromDurationObject and auraData.auraInstanceID then
            local durationObj
            if C_UnitAuras and C_UnitAuras.GetAuraDuration then
                local ok, obj = pcall(C_UnitAuras.GetAuraDuration, unit, auraData.auraInstanceID)
                if ok and obj then
                    durationObj = obj
                end
            end

            if durationObj then
                local setOk = pcall(cooldownFrame.SetCooldownFromDurationObject, cooldownFrame, durationObj, true)
                if setOk then
                    applied = true
                else
                    -- Fallback: derive numbers from duration object methods
                    local eOK, elapsed = pcall(durationObj.GetElapsedDuration, durationObj)
                    local rOK, remaining = pcall(durationObj.GetRemainingDuration, durationObj)
                    if eOK and rOK and elapsed and remaining then
                        local startTime = GetTime() - elapsed
                        local total = elapsed + remaining
                        local numOk = pcall(cooldownFrame.SetCooldown, cooldownFrame, startTime, total)
                        if numOk then
                            applied = true
                        end
                    end
                end
            end
        end

        -- Fallback: numeric start/duration (avoid comparisons; allow secret-safe arithmetic)
        if not applied then
            local duration = auraData.duration
            local expirationTime = auraData.expirationTime
            if duration and expirationTime then
                local ok = pcall(function()
                    local startTime = expirationTime - duration
                    cooldownFrame:SetCooldown(startTime, duration)
                end)
                if ok then
                    applied = true
                end
            end
        end

        return applied
    end

    -- Helper to safely display stack count using combat-safe API
    -- Passes directly to SetText without comparing (return value may be secret-derived)
    local function DisplayStackCount(countText, unit, auraInstanceID)
        if not auraInstanceID or not C_UnitAuras.GetAuraApplicationDisplayCount then
            countText:SetText("")
            return
        end
        -- stackMinimum=2 means don't show "1", stackMaximum=99 for normal display
        -- API returns "" for <2 stacks, number string for 2-99, "*" for 100+
        local ok, stackText = pcall(C_UnitAuras.GetAuraApplicationDisplayCount, unit, auraInstanceID, 2, 99)
        if ok then
            countText:SetText(stackText)
        else
            countText:SetText("")
        end
    end

    -- Populate debuffs (skip if preview is active)
    local debuffCount = 0
    local debuffIndex = 1
    -- Filter: player frame always shows all; others respect onlyMyDebuffs setting
    local debuffFilter = "HARMFUL"
    if unit ~= "player" and onlyMyDebuffs then
        debuffFilter = "HARMFUL|PLAYER"
    end
    if showDebuffs and not debuffPreviewActive then
        while debuffCount < debuffMaxIcons do
            local auraData = C_UnitAuras.GetAuraDataByIndex(unit, debuffIndex, debuffFilter)
            if not auraData then break end

            debuffCount = debuffCount + 1

            local icon = GetAuraIcon(frame.debuffIcons, debuffCount, frame, iconSize, auraSettings, true)

            -- Store aura data for tooltip
            icon.unit = unit
            icon.auraInstanceID = auraData.auraInstanceID
            icon.filter = debuffFilter

            -- Safely set texture (icon field is always safe)
            if auraData.icon then
                icon.icon:SetTexture(auraData.icon)
            end

            -- Red border for debuffs
            if icon.border then
                icon.border:SetColorTexture(0.8, 0.2, 0.2, 1)
            end

            -- Cooldown (safely handles secret values via duration object API)
            if SafeSetCooldown(icon.cooldown, auraData, unit) then
                icon.cooldown:Show()
            else
                icon.cooldown:Hide()
            end

            -- Stack count (using combat-safe API, no comparisons on result)
            if icon._showStack then
                DisplayStackCount(icon.count, unit, auraData.auraInstanceID)
                icon.count:Show()
            else
                icon.count:Hide()
            end

            -- Calculate position based on anchor and single grow direction
            local idx = debuffCount - 1
            local xPos, yPos = debuffOffsetX, debuffOffsetY
            if debuffGrow == "RIGHT" then
                xPos = xPos + idx * (iconSize + debuffSpacing)
            elseif debuffGrow == "LEFT" then
                xPos = xPos - idx * (iconSize + debuffSpacing)
            elseif debuffGrow == "UP" then
                yPos = yPos + idx * (iconSize + debuffSpacing)
            elseif debuffGrow == "DOWN" then
                yPos = yPos - idx * (iconSize + debuffSpacing)
            end

            -- Map user anchor to frame anchor points (flip vertical only for outside positioning)
            -- Border compensation: icons have 1px border extending beyond frame
            local iconPoint, framePoint, borderOffsetX
            if debuffAnchor == "TOPLEFT" then
                iconPoint, framePoint, borderOffsetX = "BOTTOMLEFT", "TOPLEFT", 1
            elseif debuffAnchor == "TOPRIGHT" then
                iconPoint, framePoint, borderOffsetX = "BOTTOMRIGHT", "TOPRIGHT", -1
            elseif debuffAnchor == "BOTTOMLEFT" then
                iconPoint, framePoint, borderOffsetX = "TOPLEFT", "BOTTOMLEFT", 1
            elseif debuffAnchor == "BOTTOMRIGHT" then
                iconPoint, framePoint, borderOffsetX = "TOPRIGHT", "BOTTOMRIGHT", -1
            end

            icon:ClearAllPoints()
            icon:SetPoint(iconPoint, frame, framePoint, xPos + (borderOffsetX or 0), yPos)
            icon:Show()

            debuffIndex = debuffIndex + 1
        end
    end

    -- Populate buffs (skip if preview is active)
    local buffCount = 0
    local buffIndex = 1
    if showBuffs and not buffPreviewActive then
        while buffCount < buffMaxIcons do
            local auraData = C_UnitAuras.GetAuraDataByIndex(unit, buffIndex, "HELPFUL")
            if not auraData then break end

            buffCount = buffCount + 1

            local icon = GetAuraIcon(frame.buffIcons, buffCount, frame, buffIconSize, auraSettings, false)

            -- Store aura data for tooltip
            icon.unit = unit
            icon.auraInstanceID = auraData.auraInstanceID
            icon.filter = "HELPFUL"

            -- Safely set texture
            if auraData.icon then
                icon.icon:SetTexture(auraData.icon)
            end

            -- Default black border for buffs
            if icon.border then
                icon.border:SetColorTexture(0, 0, 0, 1)
            end

            -- Cooldown (safely handles secret values via duration object API)
            if SafeSetCooldown(icon.cooldown, auraData, unit) then
                icon.cooldown:Show()
            else
                icon.cooldown:Hide()
            end

            -- Stack count (using combat-safe API, no comparisons on result)
            if icon._showStack then
                DisplayStackCount(icon.count, unit, auraData.auraInstanceID)
                icon.count:Show()
            else
                icon.count:Hide()
            end

            -- Calculate position based on anchor and single grow direction
            local idx = buffCount - 1
            local xPos, yPos = buffOffsetX, buffOffsetY
            if buffGrow == "RIGHT" then
                xPos = xPos + idx * (buffIconSize + buffSpacing)
            elseif buffGrow == "LEFT" then
                xPos = xPos - idx * (buffIconSize + buffSpacing)
            elseif buffGrow == "UP" then
                yPos = yPos + idx * (buffIconSize + buffSpacing)
            elseif buffGrow == "DOWN" then
                yPos = yPos - idx * (buffIconSize + buffSpacing)
            end

            -- Map user anchor to frame anchor points (flip vertical only for outside positioning)
            -- Border compensation: icons have 1px border extending beyond frame
            local iconPoint, framePoint, borderOffsetX
            if buffAnchor == "TOPLEFT" then
                iconPoint, framePoint, borderOffsetX = "BOTTOMLEFT", "TOPLEFT", 1
            elseif buffAnchor == "TOPRIGHT" then
                iconPoint, framePoint, borderOffsetX = "BOTTOMRIGHT", "TOPRIGHT", -1
            elseif buffAnchor == "BOTTOMLEFT" then
                iconPoint, framePoint, borderOffsetX = "TOPLEFT", "BOTTOMLEFT", 1
            elseif buffAnchor == "BOTTOMRIGHT" then
                iconPoint, framePoint, borderOffsetX = "TOPRIGHT", "BOTTOMRIGHT", -1
            end

            icon:ClearAllPoints()
            icon:SetPoint(iconPoint, frame, framePoint, xPos + (borderOffsetX or 0), yPos)
            icon:Show()

            buffIndex = buffIndex + 1
        end
    end
end

-- Expose for unitframes.lua callers
QUI_UF.UpdateAuras = UpdateAuras

---------------------------------------------------------------------------
-- AURA TRACKING SETUP
---------------------------------------------------------------------------

local function SetupAuraTracking(frame)
    if not frame then return end

    local unit = frame.unit

    -- Register aura events and unit-change events based on unit type
    frame:RegisterEvent("UNIT_AURA")
    if unit == "target" then
        frame:RegisterEvent("PLAYER_TARGET_CHANGED")
    elseif unit == "focus" then
        frame:RegisterEvent("PLAYER_FOCUS_CHANGED")
    elseif unit == "pet" then
        frame:RegisterEvent("UNIT_PET")
    elseif unit == "targettarget" then
        frame:RegisterEvent("PLAYER_TARGET_CHANGED")  -- ToT changes when target changes
        frame:RegisterEvent("UNIT_TARGET")            -- ToT changes when target's target changes
    elseif unit:match("^boss%d+$") then
        frame:RegisterEvent("INSTANCE_ENCOUNTER_ENGAGE_UNIT")
    end
    -- player: no extra event needed, UNIT_AURA handles it

    -- Hook into existing OnEvent or create new one
    local oldOnEvent = frame:GetScript("OnEvent")
    frame:SetScript("OnEvent", function(self, event, arg1, ...)
        if oldOnEvent then
            oldOnEvent(self, event, arg1, ...)
        end

        if event == "UNIT_AURA" and arg1 == self.unit then
            -- Force immediate update by clearing throttle
            lastAuraUpdate[self.unit] = 0
            UpdateAuras(self)
        elseif event == "PLAYER_TARGET_CHANGED" then
            -- Update target and targettarget when target changes
            if self.unit == "target" or self.unit == "targettarget" then
                lastAuraUpdate[self.unit] = 0
                UpdateAuras(self)
            end
        elseif event == "PLAYER_FOCUS_CHANGED" and self.unit == "focus" then
            -- Clear throttle and update immediately on focus change
            lastAuraUpdate["focus"] = 0
            UpdateAuras(self)
        elseif event == "UNIT_PET" and self.unit == "pet" then
            -- Pet changed (summoned/dismissed)
            lastAuraUpdate["pet"] = 0
            UpdateAuras(self)
        elseif event == "UNIT_TARGET" and self.unit == "targettarget" then
            -- Target's target changed
            lastAuraUpdate["targettarget"] = 0
            UpdateAuras(self)
        elseif event == "INSTANCE_ENCOUNTER_ENGAGE_UNIT" and self.unit:match("^boss%d+$") then
            -- Boss unit changed - full refresh for name, health, power, auras
            lastAuraUpdate[self.unit] = 0
            UpdateFrame(self)
            UpdateAuras(self)
        end
    end)

    -- Multiple initial updates to catch auras after load
    C_Timer.After(0.1, function()
        lastAuraUpdate[unit] = 0
        UpdateAuras(frame)
    end)
    C_Timer.After(0.5, function()
        lastAuraUpdate[unit] = 0
        UpdateAuras(frame)
    end)
    C_Timer.After(1.0, function()
        lastAuraUpdate[unit] = 0
        UpdateAuras(frame)
    end)
end

-- Expose for unitframes.lua callers
QUI_UF.SetupAuraTracking = SetupAuraTracking

---------------------------------------------------------------------------
-- AURA PREVIEW MODE
---------------------------------------------------------------------------

function QUI_UF:ShowAuraPreview(unitKey, auraType)
    -- Handle boss frames specially - show aura preview on all 5
    if unitKey == "boss" then
        local previewKey = "boss_" .. auraType
        self.auraPreviewMode[previewKey] = true
        -- Only show if boss frame preview is active
        for i = 1, 5 do
            local bossKey = "boss" .. i
            local frame = self.frames[bossKey]
            if frame and self.previewMode[bossKey] then
                self:ShowAuraPreviewForFrame(frame, "boss", auraType)
            end
        end
        return
    end

    local frame = self.frames[unitKey]
    if not frame then return end

    local previewKey = unitKey .. "_" .. auraType
    self.auraPreviewMode[previewKey] = true

    self:ShowAuraPreviewForFrame(frame, unitKey, auraType)
end

function QUI_UF:ShowAuraPreviewForFrame(frame, unitKey, auraType)
    if not frame then return end

    -- Get settings
    local settings = GetUnitSettings(unitKey)
    local auraSettings = settings and settings.auras or {}

    -- Determine which preview data and settings to use
    local previewData = (auraType == "buff") and PREVIEW_AURAS.buffs or PREVIEW_AURAS.debuffs
    local isDebuff = (auraType == "debuff")

    -- Get size and positioning settings
    local iconSize, anchor, grow, offsetX, offsetY, spacing, maxIcons
    if isDebuff then
        iconSize = auraSettings.iconSize or 22
        anchor = auraSettings.debuffAnchor or "TOPLEFT"
        grow = auraSettings.debuffGrow or "RIGHT"
        offsetX = auraSettings.debuffOffsetX or 0
        offsetY = auraSettings.debuffOffsetY or 2
        spacing = auraSettings.debuffSpacing or 2
        maxIcons = auraSettings.debuffMaxIcons or 16
    else
        iconSize = auraSettings.buffIconSize or 22
        anchor = auraSettings.buffAnchor or "BOTTOMLEFT"
        grow = auraSettings.buffGrow or "RIGHT"
        offsetX = auraSettings.buffOffsetX or 0
        offsetY = auraSettings.buffOffsetY or -2
        spacing = auraSettings.buffSpacing or 2
        maxIcons = auraSettings.buffMaxIcons or 16
    end

    -- Initialize preview icon container if needed
    local containerKey = isDebuff and "previewDebuffIcons" or "previewBuffIcons"
    frame[containerKey] = frame[containerKey] or {}
    local container = frame[containerKey]

    -- Hide real auras of this type
    local realContainer = isDebuff and frame.debuffIcons or frame.buffIcons
    if realContainer then
        for _, icon in ipairs(realContainer) do
            icon:Hide()
        end
    end

    -- Hide any existing preview icons first (in case maxIcons was reduced)
    for _, icon in ipairs(container) do
        icon:SetScript("OnUpdate", nil)
        icon:Hide()
    end

    -- Track start time for looping cooldown animation
    local previewStartTime = GetTime()
    local previewDuration = 10
    local previewDataCount = #previewData

    -- Create/show preview icons based on maxIcons setting
    for i = 1, maxIcons do
        -- Cycle through mock data using modulo
        local dataIndex = ((i - 1) % previewDataCount) + 1
        local auraData = previewData[dataIndex]
        local icon = container[i]
        if not icon then
            -- Create new preview icon (simplified, no tooltip interaction needed)
            icon = CreateFrame("Frame", nil, frame)
            icon:SetFrameLevel(frame:GetFrameLevel() + 10)

            -- Border
            local border = icon:CreateTexture(nil, "BACKGROUND", nil, -8)
            border:SetColorTexture(0, 0, 0, 1)
            local prevIconPx = QUICore:GetPixelSize(icon)
            border:SetPoint("TOPLEFT", icon, "TOPLEFT", -prevIconPx, prevIconPx)
            border:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", prevIconPx, -prevIconPx)
            icon.border = border

            -- Icon texture
            local tex = icon:CreateTexture(nil, "ARTWORK")
            tex:SetPoint("TOPLEFT", 0, 0)
            tex:SetPoint("BOTTOMRIGHT", 0, 0)
            tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            icon.icon = tex

            -- Cooldown swipe
            local cd = CreateFrame("Cooldown", nil, icon, "CooldownFrameTemplate")
            cd:SetAllPoints(icon)
            cd:SetDrawEdge(false)
            cd:SetReverse(true)
            cd:SetSwipeTexture("Interface\\Buttons\\WHITE8X8")
            cd:SetSwipeColor(0, 0, 0, 0.8)
            cd.noOCC = true
            cd.noCooldownCount = true
            icon.cooldown = cd

            -- Stack count — parented above the cooldown swipe
            local stackOverlay = CreateFrame("Frame", nil, icon)
            stackOverlay:SetAllPoints(icon)
            stackOverlay:SetFrameLevel(cd:GetFrameLevel() + 1)
            local count = stackOverlay:CreateFontString(nil, "OVERLAY")
            count:SetTextColor(1, 1, 1, 1)
            icon.count = count

            container[i] = icon
        end

        -- Configure icon size
        icon:SetSize(iconSize, iconSize)

        -- Apply settings (font, stack position, etc.)
        local fontPath = GetFontPath()
        local fontOutline = GetFontOutline()
        local prefix = isDebuff and "debuff" or "buff"

        local showStack = auraSettings[prefix .. "ShowStack"]
        if showStack == nil then showStack = auraSettings.showStack end
        if showStack == nil then showStack = true end

        local stackSize = auraSettings[prefix .. "StackSize"] or auraSettings.stackSize or 10
        local stackAnchor = auraSettings[prefix .. "StackAnchor"] or auraSettings.stackAnchor or "BOTTOMRIGHT"
        local stackOffsetX = auraSettings[prefix .. "StackOffsetX"] or auraSettings.stackOffsetX or -1
        local stackOffsetY = auraSettings[prefix .. "StackOffsetY"] or auraSettings.stackOffsetY or 1
        local stackColor = auraSettings[prefix .. "StackColor"] or auraSettings.stackColor or {1, 1, 1, 1}

        icon.count:SetFont(fontPath, stackSize, fontOutline)
        icon.count:ClearAllPoints()
        icon.count:SetPoint(stackAnchor, icon, stackAnchor, stackOffsetX, stackOffsetY)
        icon.count:SetTextColor(stackColor[1] or 1, stackColor[2] or 1, stackColor[3] or 1, stackColor[4] or 1)

        -- Hide Duration Swipe setting
        local hideSwipe = auraSettings[prefix .. "HideSwipe"]
        if hideSwipe == nil then hideSwipe = false end
        icon.cooldown:SetDrawSwipe(not hideSwipe)

        -- Set texture
        icon.icon:SetTexture(auraData.icon)

        -- Set border color (red for debuffs, black for buffs)
        if isDebuff then
            icon.border:SetColorTexture(0.8, 0.2, 0.2, 1)
        else
            icon.border:SetColorTexture(0, 0, 0, 1)
        end

        -- Set stack count
        if showStack and auraData.stacks and auraData.stacks > 1 then
            icon.count:SetText(auraData.stacks)
            icon.count:Show()
        else
            icon.count:Hide()
        end

        -- Calculate position
        local idx = i - 1
        local xPos, yPos = offsetX, offsetY
        if grow == "RIGHT" then
            xPos = xPos + idx * (iconSize + spacing)
        elseif grow == "LEFT" then
            xPos = xPos - idx * (iconSize + spacing)
        elseif grow == "UP" then
            yPos = yPos + idx * (iconSize + spacing)
        elseif grow == "DOWN" then
            yPos = yPos - idx * (iconSize + spacing)
        end

        -- Map user anchor to frame anchor points (flip vertical only for outside positioning)
        -- Border compensation: icons have 1px border extending beyond frame
        local iconPoint, framePoint, borderOffsetX
        if anchor == "TOPLEFT" then
            iconPoint, framePoint, borderOffsetX = "BOTTOMLEFT", "TOPLEFT", 1
        elseif anchor == "TOPRIGHT" then
            iconPoint, framePoint, borderOffsetX = "BOTTOMRIGHT", "TOPRIGHT", -1
        elseif anchor == "BOTTOMLEFT" then
            iconPoint, framePoint, borderOffsetX = "TOPLEFT", "BOTTOMLEFT", 1
        elseif anchor == "BOTTOMRIGHT" then
            iconPoint, framePoint, borderOffsetX = "TOPRIGHT", "BOTTOMRIGHT", -1
        end

        icon:ClearAllPoints()
        icon:SetPoint(iconPoint, frame, framePoint, xPos + (borderOffsetX or 0), yPos)

        -- Setup looping cooldown animation
        icon.cooldown:SetCooldown(previewStartTime, previewDuration)
        icon.cooldown:Show()

        -- Store start time for OnUpdate loop
        icon._previewStartTime = previewStartTime
        icon._previewDuration = previewDuration

        icon:SetScript("OnUpdate", function(self, elapsed)
            local now = GetTime()
            local elapsedTime = now - self._previewStartTime
            if elapsedTime >= self._previewDuration then
                self._previewStartTime = now
                self.cooldown:SetCooldown(now, self._previewDuration)
            end
        end)

        icon:Show()
    end
end

function QUI_UF:HideAuraPreview(unitKey, auraType)
    -- Handle boss frames specially - hide aura preview on all 5
    if unitKey == "boss" then
        local previewKey = "boss_" .. auraType
        self.auraPreviewMode[previewKey] = false
        for i = 1, 5 do
            local bossKey = "boss" .. i
            local frame = self.frames[bossKey]
            if frame then
                self:HideAuraPreviewForFrame(frame, bossKey, auraType)
            end
        end
        return
    end

    local frame = self.frames[unitKey]
    if not frame then return end

    local previewKey = unitKey .. "_" .. auraType
    self.auraPreviewMode[previewKey] = false

    self:HideAuraPreviewForFrame(frame, unitKey, auraType)
end

function QUI_UF:HideAuraPreviewForFrame(frame, unitKey, auraType)
    if not frame then return end

    local isDebuff = (auraType == "debuff")
    local containerKey = isDebuff and "previewDebuffIcons" or "previewBuffIcons"
    local container = frame[containerKey]

    -- Hide and cleanup preview icons
    if container then
        for _, icon in ipairs(container) do
            icon:SetScript("OnUpdate", nil)
            icon:Hide()
        end
    end

    -- Refresh real auras
    lastAuraUpdate[unitKey] = 0
    UpdateAuras(frame)
end
