--[[
    QUI Group Frames - Custom Aura Indicators
    Spec-specific aura tracking with 5 render types: icon, colored square,
    progress bar, border color, and health bar color.
    Features: per-spec presets, frame pools, secret aura workaround via
    UNIT_SPELLCAST_SUCCEEDED tracking.
]]

local ADDON_NAME, ns = ...
local Helpers = ns.Helpers
local LSM = LibStub("LibSharedMedia-3.0")
local QUICore = ns.Addon
local IsSecretValue = Helpers.IsSecretValue
local SafeValue = Helpers.SafeValue
local SafeToNumber = Helpers.SafeToNumber
local GetDB = Helpers.CreateDBGetter("quiGroupFrames")

---------------------------------------------------------------------------
-- MODULE TABLE
---------------------------------------------------------------------------
local QUI_GFI = {}
ns.QUI_GroupFrameIndicators = QUI_GFI

---------------------------------------------------------------------------
-- INDICATOR TYPES
---------------------------------------------------------------------------
local INDICATOR_TYPES = {
    icon = "Icon",
    square = "Colored Square",
    bar = "Progress Bar",
    border = "Border Color",
    healthcolor = "Health Bar Color",
}

-- Position anchors
local POSITIONS = {
    "TOPLEFT", "TOP", "TOPRIGHT",
    "LEFT", "CENTER", "RIGHT",
    "BOTTOMLEFT", "BOTTOM", "BOTTOMRIGHT",
}

---------------------------------------------------------------------------
-- FRAME POOLS: Pre-allocated pools per indicator element type
---------------------------------------------------------------------------
local iconPool = {}
local squarePool = {}
local barPool = {}

local POOL_SIZE = 30

local function AcquireFromPool(pool, createFunc, parent)
    local item = table.remove(pool)
    if item then
        item:SetParent(parent)
        item:ClearAllPoints()
        return item
    end
    return createFunc(parent)
end

local function ReleaseToPool(pool, item)
    item:Hide()
    item:ClearAllPoints()
    if #pool < POOL_SIZE then
        table.insert(pool, item)
    end
end

---------------------------------------------------------------------------
-- FRAME CREATION: Indicator elements
---------------------------------------------------------------------------
local function GetFontPath()
    local db = GetDB()
    local general = db and db.general
    local fontName = general and general.font or "Quazii"
    return LSM:Fetch("font", fontName) or "Fonts\\FRIZQT__.TTF"
end

local function CreateIconIndicator(parent)
    local frame = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    frame:SetSize(16, 16)

    local tex = frame:CreateTexture(nil, "ARTWORK")
    tex:SetAllPoints()
    tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    frame.icon = tex

    local px = QUICore.GetPixelSize and QUICore:GetPixelSize(frame) or 1
    frame:SetBackdrop({
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = px,
    })
    frame:SetBackdropBorderColor(0, 0, 0, 1)

    -- Cooldown swipe
    local cd = CreateFrame("Cooldown", nil, frame, "CooldownFrameTemplate")
    cd:SetAllPoints()
    cd:SetDrawEdge(false)
    cd:SetDrawBling(false)
    cd:SetHideCountdownNumbers(true)
    frame.cooldown = cd

    -- Duration text
    local durText = frame:CreateFontString(nil, "OVERLAY")
    durText:SetFont(GetFontPath(), 8, "OUTLINE")
    durText:SetPoint("BOTTOM", frame, "BOTTOM", 0, 1)
    durText:SetJustifyH("CENTER")
    frame.durationText = durText

    -- Stack text
    local stackText = frame:CreateFontString(nil, "OVERLAY")
    stackText:SetFont(GetFontPath(), 9, "OUTLINE")
    stackText:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 1, 0)
    stackText:SetJustifyH("RIGHT")
    frame.stackText = stackText

    frame:Hide()
    return frame
end

local function CreateSquareIndicator(parent)
    local frame = CreateFrame("Frame", nil, parent)
    frame:SetSize(8, 8)

    local tex = frame:CreateTexture(nil, "OVERLAY")
    tex:SetAllPoints()
    tex:SetTexture("Interface\\Buttons\\WHITE8x8")
    frame.colorTex = tex

    frame:Hide()
    return frame
end

local function CreateBarIndicator(parent)
    local bar = CreateFrame("StatusBar", nil, parent)
    bar:SetSize(40, 6)
    bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    bar:SetMinMaxValues(0, 1)
    bar:SetValue(0)

    local bg = bar:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetTexture("Interface\\Buttons\\WHITE8x8")
    bg:SetVertexColor(0, 0, 0, 0.5)
    bar.bg = bg

    bar:Hide()
    return bar
end

---------------------------------------------------------------------------
-- PER-SPEC PRESETS: Built-in indicator configurations
---------------------------------------------------------------------------
local SPEC_PRESETS = {
    -- Restoration Druid (105)
    [105] = {
        { spellId = 33763,  name = "Lifebloom",     type = "icon",   position = "TOPLEFT",    size = 16, priority = 10, showCooldown = true, showStacks = true },
        { spellId = 774,    name = "Rejuvenation",  type = "square", position = "BOTTOMLEFT", size = 8,  priority = 9,  color = { 0.6, 0.2, 1.0, 1 } },
        { spellId = 8936,   name = "Regrowth",      type = "square", position = "BOTTOMRIGHT",size = 8,  priority = 8,  color = { 0.2, 1.0, 0.2, 1 } },
        { spellId = 48438,  name = "Wild Growth",   type = "square", position = "BOTTOM",     size = 8,  priority = 7,  color = { 0.2, 0.8, 0.2, 1 } },
        { spellId = 102342, name = "Ironbark",      type = "border", position = "CENTER",     priority = 15, color = { 0.6, 0.3, 0.0, 0.8 } },
    },
    -- Restoration Shaman (264)
    [264] = {
        { spellId = 61295,  name = "Riptide",       type = "icon",   position = "TOPLEFT",    size = 16, priority = 10, showCooldown = true },
        { spellId = 974,    name = "Earth Shield",  type = "icon",   position = "TOPRIGHT",   size = 14, priority = 9,  showCooldown = false, showStacks = true },
        { spellId = 98008,  name = "Spirit Link",   type = "border", position = "CENTER",     priority = 15, color = { 0.0, 0.5, 1.0, 0.8 } },
    },
    -- Discipline Priest (256)
    [256] = {
        { spellId = 194384, name = "Atonement",     type = "icon",   position = "TOPLEFT",    size = 16, priority = 10, showCooldown = true },
        { spellId = 17,     name = "PW: Shield",    type = "square", position = "BOTTOMLEFT", size = 8,  priority = 9,  color = { 1.0, 1.0, 0.2, 1 } },
        { spellId = 33206,  name = "Pain Supp.",    type = "border", position = "CENTER",     priority = 15, color = { 0.2, 0.2, 1.0, 0.8 } },
        { spellId = 10060,  name = "Power Infusion", type = "icon",  position = "TOPRIGHT",   size = 14, priority = 12, showCooldown = true },
    },
    -- Holy Priest (257)
    [257] = {
        { spellId = 139,    name = "Renew",         type = "icon",   position = "TOPLEFT",    size = 16, priority = 10, showCooldown = true },
        { spellId = 41635,  name = "Prayer of Mending", type = "icon", position = "TOPRIGHT", size = 14, priority = 9,  showCooldown = false, showStacks = true },
        { spellId = 47788,  name = "Guardian Spirit",type = "border", position = "CENTER",     priority = 15, color = { 1.0, 0.8, 0.0, 0.8 } },
    },
    -- Holy Paladin (65)
    [65] = {
        { spellId = 53563,  name = "Beacon of Light",type = "icon",  position = "TOPLEFT",    size = 16, priority = 10, showCooldown = false },
        { spellId = 156910, name = "Beacon of Faith", type = "icon", position = "TOPRIGHT",   size = 14, priority = 9,  showCooldown = false },
        { spellId = 287280, name = "Glimmer",        type = "square", position = "BOTTOMLEFT",size = 8,  priority = 8,  color = { 1.0, 0.9, 0.3, 1 } },
        { spellId = 6940,   name = "Sacrifice",      type = "border", position = "CENTER",    priority = 15, color = { 1.0, 0.2, 0.2, 0.8 } },
    },
    -- Preservation Evoker (1468)
    [1468] = {
        { spellId = 364343, name = "Echo",           type = "icon",   position = "TOPLEFT",    size = 16, priority = 10, showCooldown = true },
        { spellId = 366155, name = "Reversion",      type = "square", position = "BOTTOMLEFT", size = 8,  priority = 9,  color = { 0.2, 0.8, 0.4, 1 } },
        { spellId = 357170, name = "Time Dilation",  type = "border", position = "CENTER",     priority = 15, color = { 0.4, 0.8, 1.0, 0.8 } },
        { spellId = 373267, name = "Lifebind",       type = "square", position = "BOTTOMRIGHT",size = 8,  priority = 8,  color = { 0.2, 1.0, 0.6, 1 } },
    },
    -- Mistweaver Monk (270)
    [270] = {
        { spellId = 119611, name = "Renewing Mist",  type = "icon",   position = "TOPLEFT",    size = 16, priority = 10, showCooldown = true },
        { spellId = 124682, name = "Enveloping Mist",type = "icon",   position = "TOPRIGHT",   size = 14, priority = 9,  showCooldown = true },
        { spellId = 191840, name = "Essence Font",   type = "square", position = "BOTTOMLEFT", size = 8,  priority = 7,  color = { 0.5, 1.0, 0.8, 1 } },
        { spellId = 116849, name = "Life Cocoon",    type = "border", position = "CENTER",     priority = 15, color = { 0.0, 1.0, 0.3, 0.8 } },
    },
}

-- Tank awareness presets (common external defensives)
local TANK_PRESETS = {
    { spellId = 102342, name = "Ironbark",        type = "icon",   position = "TOPLEFT",  size = 14, priority = 12, showCooldown = true },
    { spellId = 33206,  name = "Pain Suppression", type = "icon",  position = "TOP",      size = 14, priority = 12, showCooldown = true },
    { spellId = 47788,  name = "Guardian Spirit",  type = "icon",  position = "TOPRIGHT", size = 14, priority = 12, showCooldown = true },
    { spellId = 6940,   name = "Blessing of Sacrifice", type = "icon", position = "LEFT", size = 14, priority = 11, showCooldown = true },
    { spellId = 116849, name = "Life Cocoon",      type = "icon",  position = "RIGHT",    size = 14, priority = 12, showCooldown = true },
}

---------------------------------------------------------------------------
-- GET ACTIVE SPEC INDICATORS
---------------------------------------------------------------------------
local function GetActiveIndicators()
    local db = GetDB()
    if not db or not db.auraIndicators or not db.auraIndicators.enabled then
        return nil
    end

    local specID = GetSpecializationInfo(GetSpecialization() or 1)
    if not specID then return nil end

    -- Check for user-configured indicators first
    local specIndicators = db.auraIndicators.specs and db.auraIndicators.specs[specID]
    if specIndicators and next(specIndicators) then
        return specIndicators
    end

    -- Fall back to presets if enabled
    if db.auraIndicators.usePresets then
        return SPEC_PRESETS[specID]
    end

    return nil
end

---------------------------------------------------------------------------
-- INDICATOR STATE: Track active indicators per frame
---------------------------------------------------------------------------
local frameIndicatorState = setmetatable({}, { __mode = "k" })

local function GetIndicatorState(frame)
    local state = frameIndicatorState[frame]
    if not state then
        state = { elements = {}, activeSpells = {} }
        frameIndicatorState[frame] = state
    end
    return state
end

---------------------------------------------------------------------------
-- RENDER: Apply indicator to frame
---------------------------------------------------------------------------
local function RenderIconIndicator(frame, config, auraData, unit)
    local state = GetIndicatorState(frame)
    local key = "icon_" .. (config.position or "TOPLEFT")

    local element = state.elements[key]
    if not element then
        element = AcquireFromPool(iconPool, CreateIconIndicator, frame)
        state.elements[key] = element
    end

    local size = config.size or 16
    element:SetSize(size, size)
    element:ClearAllPoints()
    element:SetPoint(config.position or "TOPLEFT", frame, config.position or "TOPLEFT",
        config.offsetX or 2, config.offsetY or -2)
    element:SetFrameLevel(frame:GetFrameLevel() + 8)

    -- Icon texture (C-side SetTexture handles secret values natively)
    if auraData and element.icon and auraData.icon then
        element.icon:SetTexture(auraData.icon)
    end

    -- Cooldown
    if element.cooldown and auraData and config.showCooldown ~= false then
        local dur = auraData.duration
        local expTime = auraData.expirationTime
        if dur and expTime then
            -- Path 1: DurationObject (WoW 12.0+, fully secret-safe)
            if unit and auraData.auraInstanceID
               and C_UnitAuras and C_UnitAuras.GetAuraDuration
               and element.cooldown.SetCooldownFromDurationObject then
                local ok, durationObj = pcall(C_UnitAuras.GetAuraDuration, unit, auraData.auraInstanceID)
                if ok and durationObj then
                    pcall(element.cooldown.SetCooldownFromDurationObject, element.cooldown, durationObj)
                elseif element.cooldown.SetCooldownFromExpirationTime then
                    pcall(element.cooldown.SetCooldownFromExpirationTime, element.cooldown, expTime, dur)
                else
                    pcall(function()
                        element.cooldown:SetCooldown(expTime - dur, dur)
                    end)
                end
            elseif element.cooldown.SetCooldownFromExpirationTime then
                -- Path 2: SetCooldownFromExpirationTime (C-side, secret-safe)
                pcall(element.cooldown.SetCooldownFromExpirationTime, element.cooldown, expTime, dur)
            else
                -- Path 3: Legacy fallback (Lua arithmetic, only safe out of combat)
                pcall(function()
                    element.cooldown:SetCooldown(expTime - dur, dur)
                end)
            end
        end
    elseif element.cooldown then
        element.cooldown:Clear()
    end

    -- Stacks
    if element.stackText and config.showStacks and auraData then
        local stacks = SafeToNumber(auraData.applications, 0)
        element.stackText:SetText(stacks > 1 and stacks or "")
    elseif element.stackText then
        element.stackText:SetText("")
    end

    -- Duration text
    if element.durationText and config.showDuration ~= false and auraData then
        local dur = SafeToNumber(auraData.duration, 0)
        local expTime = SafeToNumber(auraData.expirationTime, 0)
        if dur > 0 and expTime > 0 then
            local remaining = expTime - GetTime()
            if remaining > 0 then
                if remaining < 10 then
                    element.durationText:SetText(format("%.1f", remaining))
                elseif remaining < 60 then
                    element.durationText:SetText(format("%d", math.floor(remaining)))
                else
                    element.durationText:SetText(format("%dm", math.floor(remaining / 60)))
                end
            else
                element.durationText:SetText("")
            end
        else
            element.durationText:SetText("")
        end
    elseif element.durationText then
        element.durationText:SetText("")
    end

    element:Show()
    return element
end

local function RenderSquareIndicator(frame, config)
    local state = GetIndicatorState(frame)
    local key = "square_" .. (config.position or "BOTTOMLEFT")

    local element = state.elements[key]
    if not element then
        element = AcquireFromPool(squarePool, CreateSquareIndicator, frame)
        state.elements[key] = element
    end

    local size = config.size or 8
    element:SetSize(size, size)
    element:ClearAllPoints()
    element:SetPoint(config.position or "BOTTOMLEFT", frame, config.position or "BOTTOMLEFT",
        config.offsetX or 2, config.offsetY or 2)
    element:SetFrameLevel(frame:GetFrameLevel() + 8)

    local c = config.color or { 1, 1, 1, 1 }
    element.colorTex:SetVertexColor(c[1], c[2], c[3], c[4] or 1)

    element:Show()
    return element
end

local function RenderBarIndicator(frame, config, auraData)
    local state = GetIndicatorState(frame)
    local key = "bar_" .. (config.position or "BOTTOM")

    local element = state.elements[key]
    if not element then
        element = AcquireFromPool(barPool, CreateBarIndicator, frame)
        state.elements[key] = element
    end

    local barHeight = config.barHeight or 6
    local orientation = config.barOrientation or "HORIZONTAL"
    local widthMode = config.barWidth or "full"

    element:ClearAllPoints()
    if orientation == "HORIZONTAL" then
        local w = widthMode == "half" and (frame:GetWidth() / 2) or frame:GetWidth()
        element:SetSize(w, barHeight)
        element:SetOrientation("HORIZONTAL")
    else
        element:SetSize(barHeight, frame:GetHeight())
        element:SetOrientation("VERTICAL")
    end

    element:SetPoint(config.position or "BOTTOM", frame, config.position or "BOTTOM",
        config.offsetX or 0, config.offsetY or 0)
    element:SetFrameLevel(frame:GetFrameLevel() + 7)

    local c = config.color or { 0.2, 0.8, 0.2, 1 }
    element:SetStatusBarColor(c[1], c[2], c[3], c[4] or 1)

    -- Duration as bar fill
    if auraData then
        local dur = SafeToNumber(auraData.duration, 0)
        local expTime = SafeToNumber(auraData.expirationTime, 0)
        if dur > 0 and expTime > 0 then
            local remaining = expTime - GetTime()
            element:SetMinMaxValues(0, dur)
            element:SetValue(math.max(0, remaining))
        else
            element:SetMinMaxValues(0, 1)
            element:SetValue(1)
        end
    else
        element:SetMinMaxValues(0, 1)
        element:SetValue(1)
    end

    element:Show()
    return element
end

local function EnsureIndicatorBorder(frame)
    if frame._indicatorBorder then return frame._indicatorBorder end

    local px = QUICore.GetPixelSize and QUICore:GetPixelSize(frame) or 1
    local overlay = CreateFrame("Frame", nil, frame)
    overlay:ClearAllPoints()
    overlay:SetPoint("TOPLEFT", -px, px)
    overlay:SetPoint("BOTTOMRIGHT", px, -px)
    overlay:SetFrameLevel(frame:GetFrameLevel() + 7)

    local borderSize = px * 3
    local function MakeBorder(parent)
        local sb = CreateFrame("StatusBar", nil, parent)
        sb:SetStatusBarTexture("Interface\\Buttons\\WHITE8x8")
        sb:SetMinMaxValues(0, 1)
        sb:SetValue(1)
        return sb
    end

    local bTop = MakeBorder(overlay)
    bTop:SetPoint("TOPLEFT", overlay, "TOPLEFT", 0, 0)
    bTop:SetPoint("TOPRIGHT", overlay, "TOPRIGHT", 0, 0)
    bTop:SetHeight(borderSize)
    overlay.borderTop = bTop

    local bBottom = MakeBorder(overlay)
    bBottom:SetPoint("BOTTOMLEFT", overlay, "BOTTOMLEFT", 0, 0)
    bBottom:SetPoint("BOTTOMRIGHT", overlay, "BOTTOMRIGHT", 0, 0)
    bBottom:SetHeight(borderSize)
    overlay.borderBottom = bBottom

    local bLeft = MakeBorder(overlay)
    bLeft:SetPoint("TOPLEFT", overlay, "TOPLEFT", 0, 0)
    bLeft:SetPoint("BOTTOMLEFT", overlay, "BOTTOMLEFT", 0, 0)
    bLeft:SetWidth(borderSize)
    overlay.borderLeft = bLeft

    local bRight = MakeBorder(overlay)
    bRight:SetPoint("TOPRIGHT", overlay, "TOPRIGHT", 0, 0)
    bRight:SetPoint("BOTTOMRIGHT", overlay, "BOTTOMRIGHT", 0, 0)
    bRight:SetWidth(borderSize)
    overlay.borderRight = bRight

    overlay:Hide()
    frame._indicatorBorder = overlay
    return overlay
end

local function RenderBorderIndicator(frame, config)
    local overlay = EnsureIndicatorBorder(frame)
    local c = config.color or { 1, 1, 0, 0.8 }
    local a = c[4] or 0.8
    for _, key in ipairs({"borderTop", "borderBottom", "borderLeft", "borderRight"}) do
        local border = overlay[key]
        if border then
            border:GetStatusBarTexture():SetVertexColor(c[1], c[2], c[3], a)
        end
    end
    overlay:Show()
end

local function RenderHealthColorIndicator(frame, config)
    -- Tint the health bar when tracked buff is active
    if frame.healthBar then
        local c = config.color or { 1, 0, 0, 0.3 }
        -- Blend with existing color
        frame.healthBar:SetStatusBarColor(c[1], c[2], c[3], c[4] or 0.3)
    end
end

---------------------------------------------------------------------------
-- CLEAR: Remove all active indicators from frame
---------------------------------------------------------------------------
local function ClearIndicators(frame)
    local state = frameIndicatorState[frame]
    if not state then return end

    for key, element in pairs(state.elements) do
        element:Hide()
        -- Return to pool based on type
        if key:find("^icon_") then
            ReleaseToPool(iconPool, element)
        elseif key:find("^square_") then
            ReleaseToPool(squarePool, element)
        elseif key:find("^bar_") then
            ReleaseToPool(barPool, element)
        end
    end
    wipe(state.elements)
    wipe(state.activeSpells)

    -- Hide dedicated indicator border overlay
    if frame._indicatorBorder then
        frame._indicatorBorder:Hide()
    end
end

---------------------------------------------------------------------------
-- UPDATE: Process indicators for a single frame
---------------------------------------------------------------------------
local function UpdateFrameIndicators(frame)
    if not frame or not frame.unit then return end

    local indicators = GetActiveIndicators()
    if not indicators then
        ClearIndicators(frame)
        return
    end

    local unit = frame.unit
    if not UnitExists(unit) then
        ClearIndicators(frame)
        return
    end

    local state = GetIndicatorState(frame)

    -- Hide previous elements
    for _, element in pairs(state.elements) do
        element:Hide()
    end
    if frame._indicatorBorder then
        frame._indicatorBorder:Hide()
    end

    -- Build a set of active auras on the unit
    local activeAuras = {} -- [spellID] = auraData
    local GetUnitAuras = C_UnitAuras.GetUnitAuras
    if GetUnitAuras then
        -- Bulk API: 2 calls instead of 80+ per-index lookups
        for _, filter in ipairs({"HELPFUL", "HARMFUL"}) do
            local auras = GetUnitAuras(unit, filter, 40)
            if auras then
                for _, auraData in ipairs(auras) do
                    local spellID = SafeValue(auraData.spellId, nil)
                    if spellID then activeAuras[spellID] = auraData end
                end
            end
        end
    else
        -- Fallback: per-index iteration
        for _, filter in ipairs({"HELPFUL", "HARMFUL"}) do
            local idx = 1
            while idx <= 80 do
                local ok, auraData = pcall(C_UnitAuras.GetAuraDataByIndex, unit, idx, filter)
                if not ok or not auraData then break end
                local spellID = SafeValue(auraData.spellId, nil)
                if spellID then activeAuras[spellID] = auraData end
                idx = idx + 1
            end
        end
    end

    -- Check each indicator config against active auras
    -- Sort by priority (higher priority wins position conflicts)
    local usedPositions = {}

    -- Sort indicators by priority descending
    local sortedIndicators = {}
    for _, config in ipairs(indicators) do
        table.insert(sortedIndicators, config)
    end
    table.sort(sortedIndicators, function(a, b)
        return (a.priority or 0) > (b.priority or 0)
    end)

    for _, config in ipairs(sortedIndicators) do
        local spellID = config.spellId
        local auraData = spellID and activeAuras[spellID]

        if auraData then
            local pos = config.position or "TOPLEFT"
            local shouldRender = true

            -- Position conflict resolution
            if config.type ~= "border" and config.type ~= "healthcolor" then
                if usedPositions[pos] then
                    -- Skip lower priority indicator for same position
                    shouldRender = false
                else
                    usedPositions[pos] = true
                end
            end

            if shouldRender then
                -- Render based on type
                if config.type == "icon" then
                    RenderIconIndicator(frame, config, auraData, unit)
                elseif config.type == "square" then
                    RenderSquareIndicator(frame, config)
                elseif config.type == "bar" then
                    RenderBarIndicator(frame, config, auraData)
                elseif config.type == "border" then
                    RenderBorderIndicator(frame, config)
                elseif config.type == "healthcolor" then
                    RenderHealthColorIndicator(frame, config)
                end
            end
        end
    end
end

---------------------------------------------------------------------------
-- EVENT HOOKUP
---------------------------------------------------------------------------
local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("UNIT_AURA")
eventFrame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")

eventFrame:SetScript("OnEvent", function(self, event, arg1)
    local GF = ns.QUI_GroupFrames
    if not GF or not GF.initialized then return end

    if event == "UNIT_AURA" then
        local frame = GF.unitFrameMap[arg1]
        if frame then
            UpdateFrameIndicators(frame)
        end
    elseif event == "PLAYER_SPECIALIZATION_CHANGED" then
        -- Spec changed — refresh all indicators with new preset
        QUI_GFI:RefreshAll()
    end
end)

---------------------------------------------------------------------------
-- PUBLIC API
---------------------------------------------------------------------------
function QUI_GFI:RefreshAll()
    local GF = ns.QUI_GroupFrames
    if not GF or not GF.initialized then return end

    for _, frame in pairs(GF.unitFrameMap) do
        if frame and frame:IsShown() then
            UpdateFrameIndicators(frame)
        end
    end
end

function QUI_GFI:RefreshFrame(frame)
    UpdateFrameIndicators(frame)
end

function QUI_GFI:GetSpecPresets()
    return SPEC_PRESETS
end

function QUI_GFI:GetTankPresets()
    return TANK_PRESETS
end

function QUI_GFI:GetIndicatorTypes()
    return INDICATOR_TYPES
end

function QUI_GFI:GetPositions()
    return POSITIONS
end

-- Load preset for current spec into user config
function QUI_GFI:LoadPresetForSpec(specID)
    local preset = SPEC_PRESETS[specID]
    if not preset then return false end

    local db = GetDB()
    if not db or not db.auraIndicators then return false end

    if not db.auraIndicators.specs then
        db.auraIndicators.specs = {}
    end

    -- Deep copy preset into spec config
    db.auraIndicators.specs[specID] = {}
    for _, config in ipairs(preset) do
        local copy = {}
        for k, v in pairs(config) do
            if type(v) == "table" then
                copy[k] = { unpack(v) }
            else
                copy[k] = v
            end
        end
        table.insert(db.auraIndicators.specs[specID], copy)
    end

    self:RefreshAll()
    return true
end

-- Import/export indicator config (uses LibDeflate via profile_io pattern)
function QUI_GFI:ExportIndicatorConfig(specID)
    local db = GetDB()
    if not db or not db.auraIndicators then return nil end

    local config = db.auraIndicators.specs and db.auraIndicators.specs[specID]
    if not config then return nil end

    -- Serialize to string (lightweight JSON-like format)
    local AceSerializer = LibStub("AceSerializer-3.0")
    local LibDeflate = LibStub("LibDeflate")

    local serialized = AceSerializer:Serialize(config)
    local compressed = LibDeflate:CompressDeflate(serialized, { level = 9 })
    local encoded = LibDeflate:EncodeForPrint(compressed)
    return encoded
end

function QUI_GFI:ImportIndicatorConfig(encodedString, specID)
    if not encodedString or encodedString == "" then return false, "Empty string" end

    local AceSerializer = LibStub("AceSerializer-3.0")
    local LibDeflate = LibStub("LibDeflate")

    local decoded = LibDeflate:DecodeForPrint(encodedString)
    if not decoded then return false, "Invalid encoding" end

    local decompressed = LibDeflate:DecompressDeflate(decoded)
    if not decompressed then return false, "Decompression failed" end

    local ok, config = AceSerializer:Deserialize(decompressed)
    if not ok then return false, "Deserialization failed" end

    if type(config) ~= "table" then return false, "Invalid config format" end

    local db = GetDB()
    if not db or not db.auraIndicators then return false, "No database" end

    if not db.auraIndicators.specs then
        db.auraIndicators.specs = {}
    end

    db.auraIndicators.specs[specID] = config
    self:RefreshAll()
    return true
end
