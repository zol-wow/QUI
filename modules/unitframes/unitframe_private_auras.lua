--[[
    QUI Unit Frame - Private Aura Support
    Displays private (boss debuff) auras on the player, target, and focus unit
    frames using C_UnitAuras.AddPrivateAuraAnchor. These auras are hidden from
    addon APIs and can only be rendered by the client into addon-provided
    anchor frames.

    Dual-anchor system: each slot registers a main anchor for the icon and
    cooldown spiral, and (when textScale != 1) a second scaled anchor that
    renders the stack count / countdown numbers at a custom scale.
]]

local ADDON_NAME, ns = ...

-- API guard — private auras require WoW 10.1.0+
if not C_UnitAuras or not C_UnitAuras.AddPrivateAuraAnchor then return end

-- 12.0.5+ introduced the `isContainer` discriminator on AddPrivateAuraAnchor
-- args. Non-container anchors must pass `isContainer = false` or the
-- registration silently fails on 12.0.5+ clients. On older clients the field
-- is unknown and must not be set at all.
local CLIENT_VERSION = select(4, GetBuildInfo())
local IS_CONTAINER_SUPPORTED = CLIENT_VERSION and CLIENT_VERSION >= 120005

local Helpers = ns.Helpers
local GetDB = Helpers.CreateDBGetter("quiUnitFrames")

---------------------------------------------------------------------------
-- MODULE TABLE
---------------------------------------------------------------------------
local QUI_UF_PA = {}
ns.QUI_UF_PrivateAuras = QUI_UF_PA

---------------------------------------------------------------------------
-- LOCALS
---------------------------------------------------------------------------
local AddPrivateAuraAnchor = C_UnitAuras.AddPrivateAuraAnchor
local RemovePrivateAuraAnchor = C_UnitAuras.RemovePrivateAuraAnchor

local pairs = pairs
local ipairs = ipairs
local pcall = pcall
local select = select
local CreateFrame = CreateFrame
local C_Timer = C_Timer
local UnitExists = UnitExists
local math_max = math.max

-- Unit keys this module services. Player has a fixed unit token and is always
-- valid; target/focus can be empty and must be handled.
local SUPPORTED_UNITS = { player = true, target = true, focus = true }

-- Weak-keyed per-frame state:
--   containers    = { [i] = frame }    main icon containers
--   scaleFrames   = { [i] = frame }    tiny scaled parents for text anchor
--   anchorIDs     = { [i] = id }       main anchor IDs
--   textAnchorIDs = { [i] = id }       text (stack/countdown) anchor IDs
--   unit          = string             last anchored unit token
local frameState = Helpers.CreateStateTable()

---------------------------------------------------------------------------
-- HELPERS
---------------------------------------------------------------------------
local function GetSettings(unitKey)
    if not unitKey then return nil end
    local db = GetDB()
    if not db then return nil end
    local vdb = db[unitKey]
    return vdb and vdb.privateAuras or nil
end

local function CalculateSlotOffset(index, iconSize, spacing, direction, totalCount)
    local step = (index - 1) * (iconSize + spacing)
    if direction == "RIGHT" then
        return step, 0
    elseif direction == "LEFT" then
        return -step, 0
    elseif direction == "CENTER" then
        local n = totalCount or 1
        local totalSpan = n * iconSize + math_max(n - 1, 0) * spacing
        return step - totalSpan / 2, 0
    elseif direction == "UP" then
        return 0, step
    elseif direction == "DOWN" then
        return 0, -step
    end
    return step, 0
end

--- Register main + optional text anchor for one slot.
local function RegisterDualAnchor(unit, auraIndex, container, scaleFrame, settings)
    local iconSize = settings.iconSize or 22
    local borderScale = settings.borderScale or 1
    local showCountdown = settings.showCountdown ~= false
    local textScale = settings.textScale or 1
    local textOffsetX = settings.textOffsetX or 0
    local textOffsetY = settings.textOffsetY or 0

    -- When textScale != 1 we render the numbers from the second anchor at
    -- that scale; silence numbers on the main anchor to avoid double draw.
    local mainShowNumbers = (textScale == 1) and (settings.showCountdownNumbers ~= false)

    local mainArgs = {
        unitToken = unit,
        auraIndex = auraIndex,
        parent = container,
        showCountdownFrame = showCountdown,
        showCountdownNumbers = mainShowNumbers,
        iconInfo = {
            iconWidth = iconSize,
            iconHeight = iconSize,
            borderScale = borderScale,
            iconAnchor = {
                point = "CENTER",
                relativeTo = container,
                relativePoint = "CENTER",
                offsetX = 0,
                offsetY = 0,
            },
        },
    }
    if IS_CONTAINER_SUPPORTED then mainArgs.isContainer = false end
    local ok1, mainID = pcall(AddPrivateAuraAnchor, mainArgs)
    local mainAnchorID = (ok1 and mainID) or nil

    local textAnchorID = nil
    if textScale ~= 1 and mainAnchorID then
        scaleFrame:SetSize(0.001, 0.001)
        scaleFrame:SetScale(textScale)
        scaleFrame:SetFrameStrata("DIALOG")
        scaleFrame:ClearAllPoints()
        scaleFrame:SetPoint("CENTER", container, "CENTER", 0, 0)
        scaleFrame:Show()

        local anchorOffX = textOffsetX / textScale
        local anchorOffY = textOffsetY / textScale

        local textArgs = {
            unitToken = unit,
            auraIndex = auraIndex,
            parent = scaleFrame,
            showCountdownFrame = showCountdown,
            showCountdownNumbers = settings.showCountdownNumbers ~= false,
            iconInfo = {
                iconWidth = 0.001,
                iconHeight = 0.001,
                borderScale = -100,
                iconAnchor = {
                    point = "BOTTOMRIGHT",
                    relativeTo = container,
                    relativePoint = "BOTTOMRIGHT",
                    offsetX = anchorOffX,
                    offsetY = anchorOffY,
                },
            },
        }
        if IS_CONTAINER_SUPPORTED then textArgs.isContainer = false end
        local ok2, textID = pcall(AddPrivateAuraAnchor, textArgs)
        textAnchorID = (ok2 and textID) or nil
    end

    return mainAnchorID, textAnchorID
end

local function RemoveAllAnchors(state)
    for i, id in ipairs(state.anchorIDs) do
        pcall(RemovePrivateAuraAnchor, id)
        state.anchorIDs[i] = nil
    end
    for i, id in ipairs(state.textAnchorIDs) do
        pcall(RemovePrivateAuraAnchor, id)
        state.textAnchorIDs[i] = nil
    end
    -- Hide stale WoW-rendered children left on containers. pcall in case any
    -- child is a protected C-side frame that can't be hidden in combat.
    for _, container in ipairs(state.containers) do
        for j = 1, container:GetNumChildren() do
            local child = select(j, container:GetChildren())
            if child then pcall(child.Hide, child) end
        end
    end
end

local function ApplyReverseSwipe(state, reverse)
    for _, container in ipairs(state.containers) do
        for i = 1, container:GetNumChildren() do
            local child = select(i, container:GetChildren())
            if child and child.IsObjectType and child:IsObjectType("Cooldown") and child.SetReverse then
                pcall(child.SetReverse, child, reverse == true)
            end
        end
    end
end

---------------------------------------------------------------------------
-- CORE
---------------------------------------------------------------------------
local function ClearFrame(frame)
    local state = frameState[frame]
    if not state then return end

    RemoveAllAnchors(state)

    for _, scaleFrame in ipairs(state.scaleFrames) do
        scaleFrame:Hide()
        scaleFrame:ClearAllPoints()
    end
    for _, container in ipairs(state.containers) do
        container:Hide()
        container:ClearAllPoints()
    end

    state.unit = ""
end

local function SetupFrame(frame)
    if not frame or not frame.unitKey then return end
    if not SUPPORTED_UNITS[frame.unitKey] then return end

    local settings = GetSettings(frame.unitKey)
    if not settings or not settings.enabled then
        ClearFrame(frame)
        return
    end

    local unit = frame.unit
    if not unit then
        ClearFrame(frame)
        return
    end

    -- target/focus can lack a valid unit — clear anchors until one exists
    if (unit == "target" or unit == "focus") and not UnitExists(unit) then
        ClearFrame(frame)
        return
    end

    local state = frameState[frame]
    if not state then
        state = { containers = {}, scaleFrames = {}, anchorIDs = {}, textAnchorIDs = {}, unit = "" }
        frameState[frame] = state
    end

    -- Already anchored to this unit — nothing to do
    if state.unit == unit and #state.anchorIDs > 0 then return end

    RemoveAllAnchors(state)

    local maxSlots = settings.maxPerFrame or 3
    local iconSize = settings.iconSize or 22
    local spacingVal = settings.spacing or 2
    local direction = settings.growDirection or "RIGHT"
    local anchorPoint = settings.anchor or "TOPLEFT"
    local offsetX = settings.anchorOffsetX or 0
    local offsetY = settings.anchorOffsetY or 0
    local reverseSwipe = settings.reverseSwipe == true
    local frameLevelOffset = settings.frameLevel or 50

    state.unit = unit

    for i = 1, maxSlots do
        local container = state.containers[i]
        if not container then
            container = CreateFrame("Frame", nil, frame)
            state.containers[i] = container
        else
            container:SetParent(frame)
        end
        container:ClearAllPoints()
        container:Show()
        container:SetSize(iconSize, iconSize)
        container:SetFrameLevel(frame:GetFrameLevel() + frameLevelOffset)

        local slotOffX, slotOffY = CalculateSlotOffset(i, iconSize, spacingVal, direction, maxSlots)
        container:SetPoint(anchorPoint, frame, anchorPoint, offsetX + slotOffX, offsetY + slotOffY)

        local scaleFrame = state.scaleFrames[i]
        if not scaleFrame then
            scaleFrame = CreateFrame("Frame", nil, frame)
            state.scaleFrames[i] = scaleFrame
        end

        local mainID, textID = RegisterDualAnchor(unit, i, container, scaleFrame, settings)
        state.anchorIDs[i] = mainID
        state.textAnchorIDs[i] = textID
    end

    -- Blizzard creates the cooldown spiral children asynchronously; apply
    -- reverse on next frame once they exist.
    if reverseSwipe then
        ApplyReverseSwipe(state, true)
        C_Timer.After(0, function()
            if frameState[frame] == state then
                ApplyReverseSwipe(state, true)
            end
        end)
    end
end

---------------------------------------------------------------------------
-- PUBLIC API
---------------------------------------------------------------------------
function QUI_UF_PA:Setup(frame)
    SetupFrame(frame)
end

function QUI_UF_PA:Clear(frame)
    ClearFrame(frame)
end

function QUI_UF_PA:Refresh(frame)
    if not frame then return end
    ClearFrame(frame)
    frameState[frame] = nil
    SetupFrame(frame)
end

function QUI_UF_PA:RefreshAll()
    local UF = ns.QUI_UnitFrames
    if not UF or not UF.frames then return end
    for unitKey, frame in pairs(UF.frames) do
        if SUPPORTED_UNITS[unitKey] and frame then
            self:Refresh(frame)
        end
    end
end

---------------------------------------------------------------------------
-- EVENTS
---------------------------------------------------------------------------
local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("PLAYER_TARGET_CHANGED")
eventFrame:RegisterEvent("PLAYER_FOCUS_CHANGED")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")

eventFrame:SetScript("OnEvent", function(_, event)
    local UF = ns.QUI_UnitFrames
    if not UF or not UF.frames then return end

    if event == "PLAYER_TARGET_CHANGED" then
        local f = UF.frames.target
        if f then SetupFrame(f) end

    elseif event == "PLAYER_FOCUS_CHANGED" then
        local f = UF.frames.focus
        if f then SetupFrame(f) end

    elseif event == "PLAYER_ENTERING_WORLD" then
        -- Defer slightly so unit frames are fully constructed first
        C_Timer.After(1.5, function()
            local _UF = ns.QUI_UnitFrames
            if not _UF or not _UF.frames then return end
            for unitKey, frame in pairs(_UF.frames) do
                if SUPPORTED_UNITS[unitKey] and frame then
                    SetupFrame(frame)
                end
            end
        end)
    end
end)

ns.QUI_PerfRegistry = ns.QUI_PerfRegistry or {}
ns.QUI_PerfRegistry[#ns.QUI_PerfRegistry + 1] = { name = "UF_PrivateAuras", frame = eventFrame }
