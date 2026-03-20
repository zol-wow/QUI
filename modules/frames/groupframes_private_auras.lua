--[[
    QUI Group Frames - Private Aura Support
    Displays private (boss debuff) auras on group frames using
    C_UnitAuras.AddPrivateAuraAnchor. These auras are hidden from addon
    APIs and can only be rendered by the client into addon-provided frames.

    Dual-anchor system: each aura slot registers two anchors with the same
    auraIndex — the main anchor shows the icon/cooldown, and a second
    scaled anchor renders the application count (stacks) and optionally
    repositioned countdown numbers.
]]

local ADDON_NAME, ns = ...

-- API guard — private auras require WoW 10.1.0+
if not C_UnitAuras or not C_UnitAuras.AddPrivateAuraAnchor then return end

local Helpers = ns.Helpers
local GetDB = Helpers.CreateDBGetter("quiGroupFrames")

---------------------------------------------------------------------------
-- MODULE TABLE
---------------------------------------------------------------------------
local QUI_GFPA = {}
ns.QUI_GroupFramePrivateAuras = QUI_GFPA

---------------------------------------------------------------------------
-- LOCALS
---------------------------------------------------------------------------
local AddPrivateAuraAnchor = C_UnitAuras.AddPrivateAuraAnchor
local RemovePrivateAuraAnchor = C_UnitAuras.RemovePrivateAuraAnchor

-- Weak-keyed state per frame:
--   containers    = { [i] = frame }       main icon containers
--   scaleFrames   = { [i] = frame }       tiny scaled parents for text anchor
--   anchorIDs     = { [i] = id }          main anchor IDs
--   textAnchorIDs = { [i] = id }          text (stack/countdown) anchor IDs
--   unit          = string
local frameState = Helpers.CreateStateTable()

-- Container pool
local containerPool = {}
local POOL_SIZE = 80

-- Deferred work
local pendingReanchor = false
local pendingCleanup = false
local reanchorTimer = nil

---------------------------------------------------------------------------
-- HELPERS
---------------------------------------------------------------------------
local function GetSettings(isRaid)
    local db = GetDB()
    if not db then return nil end
    local vdb = (isRaid and db.raid or db.party) or db
    return vdb.privateAuras
end

local function AcquireContainer(parent)
    local container = table.remove(containerPool)
    if container then
        container:SetParent(parent)
        container:ClearAllPoints()
        container:Show()
        return container
    end
    container = CreateFrame("Frame", nil, parent)
    container:Show()
    return container
end

local function ReleaseContainer(container)
    container:Hide()
    container:ClearAllPoints()
    container:SetParent(UIParent)
    if #containerPool < POOL_SIZE then
        table.insert(containerPool, container)
    end
end

--- Calculate position offset for a slot index
--- @param index number 1-based slot index
--- @param iconSize number icon pixel size
--- @param spacing number pixel spacing between icons
--- @param direction string "LEFT", "RIGHT", "UP", or "DOWN"
--- @return number offsetX, number offsetY
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

--- Register both anchors (main + text) for a single aura slot.
--- @param unit string unit token
--- @param auraIndex number slot index
--- @param container frame main icon container
--- @param scaleFrame frame tiny scaled parent for text anchor
--- @param settings table privateAuras settings
--- @return number|nil mainAnchorID, number|nil textAnchorID
local function RegisterDualAnchor(unit, auraIndex, container, scaleFrame, settings)
    local iconSize = settings.iconSize or 20
    local borderScale = settings.borderScale or 1
    local showCountdown = settings.showCountdown ~= false
    local textScale = settings.textScale or 2
    local textOffsetX = settings.textOffsetX or 0
    local textOffsetY = settings.textOffsetY or 0

    -- Disable countdown numbers on main anchor when text scale != 1,
    -- because the second anchor will render them at the scaled size instead.
    local mainShowNumbers = (textScale == 1) and (settings.showCountdownNumbers ~= false)

    -- Main anchor: icon + cooldown spiral
    local ok1, mainID = pcall(AddPrivateAuraAnchor, {
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
    })

    local mainAnchorID = (ok1 and mainID) or nil

    -- Text anchor: stacks + countdown numbers at custom scale
    -- Only register when textScale != 1, otherwise main anchor handles everything
    local textAnchorID = nil
    if textScale ~= 1 and mainAnchorID then
        -- Configure scale frame
        scaleFrame:SetSize(0.001, 0.001)
        scaleFrame:SetScale(textScale)
        scaleFrame:SetFrameStrata("DIALOG")
        scaleFrame:ClearAllPoints()
        scaleFrame:SetPoint("CENTER", container, "CENTER", 0, 0)
        scaleFrame:Show()

        -- Offset compensation: divide by textScale so the text lands
        -- at the intended pixel offset relative to the main icon
        local anchorOffX = textOffsetX / textScale
        local anchorOffY = textOffsetY / textScale

        local ok2, textID = pcall(AddPrivateAuraAnchor, {
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
        })

        textAnchorID = (ok2 and textID) or nil
    end

    return mainAnchorID, textAnchorID
end

--- Remove all anchors (main + text) from a state table
local function RemoveAllAnchors(state)
    for i, anchorID in ipairs(state.anchorIDs) do
        pcall(RemovePrivateAuraAnchor, anchorID)
        state.anchorIDs[i] = nil
    end
    for i, anchorID in ipairs(state.textAnchorIDs) do
        pcall(RemovePrivateAuraAnchor, anchorID)
        state.textAnchorIDs[i] = nil
    end
end

---------------------------------------------------------------------------
-- CORE: Setup private auras on a single frame
---------------------------------------------------------------------------
local function SetupPrivateAuras(frame)
    local settings = GetSettings(frame._isRaid)
    if not settings or not settings.enabled then return end

    local unit = frame.unit or frame:GetAttribute("unit")
    if not unit then return end

    local state = frameState[frame]
    if not state then
        state = { containers = {}, scaleFrames = {}, anchorIDs = {}, textAnchorIDs = {}, unit = "" }
        frameState[frame] = state
    end

    -- Already set up for this unit — skip
    if state.unit == unit and #state.anchorIDs > 0 then return end

    -- Clear any stale anchors first
    RemoveAllAnchors(state)

    local maxSlots = settings.maxPerFrame or 2
    local iconSize = settings.iconSize or 20
    local spacingVal = settings.spacing or 2
    local direction = settings.growDirection or "RIGHT"
    local anchor = settings.anchor or "RIGHT"
    local offsetX = settings.anchorOffsetX or -2
    local offsetY = settings.anchorOffsetY or 0
    if anchor:find("BOTTOM") then offsetY = offsetY + (frame._bottomPad or 0) end

    state.unit = unit

    for i = 1, maxSlots do
        -- Acquire or reuse main container
        local container = state.containers[i]
        if not container then
            container = AcquireContainer(frame)
            state.containers[i] = container
        else
            container:SetParent(frame)
            container:ClearAllPoints()
            container:Show()
        end

        container:SetSize(iconSize, iconSize)
        container:SetFrameLevel(frame:GetFrameLevel() + (settings.frameLevel or 50))

        -- Position relative to the anchor point on the parent frame
        local slotOffX, slotOffY = CalculateSlotOffset(i, iconSize, spacingVal, direction, maxSlots)
        container:SetPoint(anchor, frame, anchor, offsetX + slotOffX, offsetY + slotOffY)

        -- Acquire or reuse scale frame for text anchor
        local scaleFrame = state.scaleFrames[i]
        if not scaleFrame then
            scaleFrame = CreateFrame("Frame", nil, frame)
            state.scaleFrames[i] = scaleFrame
        end

        -- Register dual anchors
        local mainID, textID = RegisterDualAnchor(unit, i, container, scaleFrame, settings)
        state.anchorIDs[i] = mainID
        state.textAnchorIDs[i] = textID
    end
end

---------------------------------------------------------------------------
-- CORE: Clear private auras from a single frame
---------------------------------------------------------------------------
local function ClearPrivateAuras(frame)
    local state = frameState[frame]
    if not state then return end

    -- Remove all anchors
    RemoveAllAnchors(state)

    -- Hide scale frames (reused on next setup)
    for i, scaleFrame in ipairs(state.scaleFrames) do
        scaleFrame:Hide()
        scaleFrame:ClearAllPoints()
    end

    -- Release main containers back to pool
    for i, container in ipairs(state.containers) do
        ReleaseContainer(container)
        state.containers[i] = nil
    end

    state.unit = ""
end

---------------------------------------------------------------------------
-- CORE: Reanchor — unit token changed, rebuild anchors (reuse containers)
---------------------------------------------------------------------------
local function ReanchorPrivateAuras(frame)
    local settings = GetSettings(frame._isRaid)
    if not settings or not settings.enabled then return end

    local unit = frame.unit or frame:GetAttribute("unit")
    if not unit then
        ClearPrivateAuras(frame)
        return
    end

    local state = frameState[frame]
    if not state then
        -- No prior state — do full setup
        SetupPrivateAuras(frame)
        return
    end

    -- Same unit — nothing to do
    if state.unit == unit and #state.anchorIDs > 0 then return end

    -- Remove old anchors (keep containers and scale frames)
    RemoveAllAnchors(state)

    state.unit = unit

    local maxSlots = settings.maxPerFrame or 2

    for i = 1, maxSlots do
        local container = state.containers[i]
        if not container then break end

        local scaleFrame = state.scaleFrames[i]
        if not scaleFrame then
            scaleFrame = CreateFrame("Frame", nil, frame)
            state.scaleFrames[i] = scaleFrame
        end

        local mainID, textID = RegisterDualAnchor(unit, i, container, scaleFrame, settings)
        state.anchorIDs[i] = mainID
        state.textAnchorIDs[i] = textID
    end
end

---------------------------------------------------------------------------
-- PUBLIC API
---------------------------------------------------------------------------

--- Setup private auras on all visible group frames
function QUI_GFPA:SetupAll()
    local GF = ns.QUI_GroupFrames
    if not GF or not GF.initialized then return end

    for _, frame in pairs(GF.unitFrameMap) do
        if frame and frame:IsShown() then
            local settings = GetSettings(frame._isRaid)
            if settings and settings.enabled then
                SetupPrivateAuras(frame)
            end
        end
    end
end

--- Reanchor all frames (unit tokens may have changed)
function QUI_GFPA:ReanchorAll()
    local GF = ns.QUI_GroupFrames
    if not GF or not GF.initialized then return end

    for _, frame in pairs(GF.unitFrameMap) do
        if frame and frame:IsShown() then
            local settings = GetSettings(frame._isRaid)
            if settings and settings.enabled then
                ReanchorPrivateAuras(frame)
            else
                ClearPrivateAuras(frame)
            end
        end
    end
end

--- Remove all private aura anchors and return containers to pool
function QUI_GFPA:CleanupAll()
    for frame in pairs(frameState) do
        ClearPrivateAuras(frame)
    end
    wipe(frameState)
end

--- Full refresh — tear down and rebuild everything
function QUI_GFPA:RefreshAll()
    -- Clear existing anchors
    for frame in pairs(frameState) do
        ClearPrivateAuras(frame)
    end
    wipe(frameState)

    -- Rebuild (SetupAll checks per-frame context)
    self:SetupAll()
end

--- Refresh a single frame
function QUI_GFPA:RefreshFrame(frame)
    ClearPrivateAuras(frame)
    frameState[frame] = nil
    SetupPrivateAuras(frame)
end

---------------------------------------------------------------------------
-- TEST MODE: Show placeholder icons on preview frames
---------------------------------------------------------------------------
local testPlaceholders = {} -- [frame] = { frames }

local function CreatePlaceholderIcon(parent, size)
    local icon = CreateFrame("Frame", nil, parent)
    icon:SetFrameLevel(parent:GetFrameLevel() + 10)
    icon:SetSize(size, size)
    local tex = icon:CreateTexture(nil, "OVERLAY")
    tex:SetAllPoints()
    tex:SetColorTexture(0.8, 0.2, 0.2, 0.6)
    local label = icon:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetPoint("CENTER")
    label:SetText("PA")
    label:SetTextColor(1, 1, 1, 0.8)
    return icon
end

--- Attach placeholder icons to a test/preview frame
function QUI_GFPA:SetupTestFrame(frame)
    local settings = GetSettings(frame._isRaid)
    if not settings or not settings.enabled then return end

    -- Clean up any existing placeholders on this frame
    if testPlaceholders[frame] then
        for _, icon in ipairs(testPlaceholders[frame]) do
            icon:Hide()
        end
        wipe(testPlaceholders[frame])
    else
        testPlaceholders[frame] = {}
    end

    local maxSlots = settings.maxPerFrame or 2
    local iconSize = settings.iconSize or 20
    local spacingVal = settings.spacing or 2
    local direction = settings.growDirection or "RIGHT"
    local anchor = settings.anchor or "RIGHT"
    local offsetX = settings.anchorOffsetX or -2
    local offsetY = settings.anchorOffsetY or 0
    if anchor:find("BOTTOM") then offsetY = offsetY + (frame._bottomPad or 0) end

    for i = 1, maxSlots do
        local icon = CreatePlaceholderIcon(frame, iconSize)
        local slotOffX, slotOffY = CalculateSlotOffset(i, iconSize, spacingVal, direction, maxSlots)
        icon:SetPoint(anchor, frame, anchor, offsetX + slotOffX, offsetY + slotOffY)
        icon:Show()
        testPlaceholders[frame][i] = icon
    end
end

--- Remove all test mode placeholders
function QUI_GFPA:CleanupTestFrames()
    for frame, icons in pairs(testPlaceholders) do
        for _, icon in ipairs(icons) do
            icon:Hide()
        end
    end
    wipe(testPlaceholders)
end

---------------------------------------------------------------------------
-- EVENTS
---------------------------------------------------------------------------
local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")

eventFrame:SetScript("OnEvent", function(self, event)
    local GF = ns.QUI_GroupFrames
    if not GF or not GF.initialized then return end

    if event == "GROUP_ROSTER_UPDATE" then
        -- Debounce roster changes
        if reanchorTimer then return end
        reanchorTimer = C_Timer.After(0.3, function()
            reanchorTimer = nil
            QUI_GFPA:ReanchorAll()
        end)

    elseif event == "PLAYER_ENTERING_WORLD" then
        C_Timer.After(1.5, function()
            QUI_GFPA:SetupAll()
        end)

    elseif event == "PLAYER_REGEN_ENABLED" then
        -- Process deferred cleanup after combat ends
        if pendingCleanup then
            pendingCleanup = false
            QUI_GFPA:CleanupAll()
        end
        if pendingReanchor then
            pendingReanchor = false
            QUI_GFPA:ReanchorAll()
        end
    end
end)
