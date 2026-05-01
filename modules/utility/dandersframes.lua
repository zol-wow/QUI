--[[
    QUI DandersFrames Integration Module
    Anchors DandersFrames party/raid/pinned containers to QUI elements
    Requires DandersFrames v4.0.0+ API
]]

local ADDON_NAME, ns = ...
local QUICore = ns.Addon

---------------------------------------------------------------------------
-- MODULE TABLE
---------------------------------------------------------------------------
local QUI_DandersFrames = {}
ns.QUI_DandersFrames = QUI_DandersFrames

-- Pending combat-deferred updates
local pendingUpdate = false

-- Debounce timer handle for GROUP_ROSTER_UPDATE
local rosterTimer = nil

-- Hook install guard for Danders test mode callbacks
local previewHooksInstalled = false

-- Forward declaration for layout mode registration (defined at bottom)
local RegisterLayoutModeElements

---------------------------------------------------------------------------
-- DATABASE ACCESS
---------------------------------------------------------------------------
local function GetDB()
    if QUICore and QUICore.db and QUICore.db.profile and QUICore.db.profile.dandersFrames then
        return QUICore.db.profile.dandersFrames
    end
    return nil
end

---------------------------------------------------------------------------
-- DF AVAILABILITY
---------------------------------------------------------------------------
function QUI_DandersFrames:IsAvailable()
    return type(DandersFrames_IsReady) == "function" and DandersFrames_IsReady()
end

---------------------------------------------------------------------------
-- CONTAINER FRAME RESOLUTION
---------------------------------------------------------------------------
local function AddUniqueFrame(frames, seen, frame)
    if not frame or seen[frame] then
        return
    end
    seen[frame] = true
    table.insert(frames, frame)
end

local function IsFrameProtected(frame)
    if not frame then return false end
    if type(frame.IsProtected) ~= "function" then return false end

    local ok, isProtected = pcall(frame.IsProtected, frame)
    return ok and isProtected or false
end

local function GetDandersAddon()
    return _G["DandersFrames"]
end

local DANDERS_LAYOUT_KEYS = {
    party = "dandersParty",
    raid = "dandersRaid",
    pinned1 = "dandersPinned1",
    pinned2 = "dandersPinned2",
}

local function GetFrameAnchoringDB()
    if QUICore and QUICore.db and QUICore.db.profile and type(QUICore.db.profile.frameAnchoring) == "table" then
        return QUICore.db.profile.frameAnchoring
    end
    return nil
end

local function ClearLegacyFrameAnchoringForContainer(containerKey)
    local layoutKey = DANDERS_LAYOUT_KEYS[containerKey]
    if not layoutKey then return end

    local frameAnchoring = GetFrameAnchoringDB()
    if frameAnchoring and frameAnchoring[layoutKey] ~= nil then
        frameAnchoring[layoutKey] = nil
    end

    if _G.QUI_LayoutModeSyncHandle then
        _G.QUI_LayoutModeSyncHandle(layoutKey)
    end
end

local function GetPartyLiveContainer()
    local danders = GetDandersAddon()
    -- Header mode roots party layout in DF.container; partyContainer is SetAllPoints.
    if danders and danders.container then
        return danders.container
    end
    -- Fallback to known root container global.
    if _G["DandersFramesContainer"] then
        return _G["DandersFramesContainer"]
    end
    -- Intentionally do not fall back to DandersFrames_GetPartyContainer():
    -- that API can point at partyContainer, which should remain SetAllPoints
    -- to the root container and must not be independently re-anchored.
    return nil
end

function QUI_DandersFrames:GetContainerFrameSets(containerKey)
    if not self:IsAvailable() then return nil end

    local frameSets = {
        live = {},
        preview = {},
    }
    local seen = {}
    local danders = GetDandersAddon()

    if containerKey == "party" then
        -- Anchor the live party root container (not partyContainer) so we don't
        -- break Danders' internal SetAllPoints relationship.
        AddUniqueFrame(frameSets.live, seen, GetPartyLiveContainer())
        -- Danders test mode party preview container (non-secure)
        AddUniqueFrame(frameSets.preview, seen, _G["DandersTestPartyContainer"])
        if danders and danders.testPartyContainer then
            AddUniqueFrame(frameSets.preview, seen, danders.testPartyContainer)
        end
    elseif containerKey == "raid" then
        if type(DandersFrames_GetRaidContainer) == "function" then
            AddUniqueFrame(frameSets.live, seen, DandersFrames_GetRaidContainer())
        end
        -- Danders test mode raid preview container (non-secure)
        AddUniqueFrame(frameSets.preview, seen, _G["DandersTestRaidContainer"])
        if danders and danders.testRaidContainer then
            AddUniqueFrame(frameSets.preview, seen, danders.testRaidContainer)
        end
    elseif containerKey == "pinned1" and type(DandersFrames_GetPinnedContainer) == "function" then
        AddUniqueFrame(frameSets.live, seen, DandersFrames_GetPinnedContainer(1))
    elseif containerKey == "pinned2" and type(DandersFrames_GetPinnedContainer) == "function" then
        AddUniqueFrame(frameSets.live, seen, DandersFrames_GetPinnedContainer(2))
    end

    if #frameSets.live == 0 and #frameSets.preview == 0 then
        return nil
    end

    return frameSets
end

function QUI_DandersFrames:GetContainerFrames(containerKey)
    local frameSets = self:GetContainerFrameSets(containerKey)
    if not frameSets then return nil end

    local frames = {}
    for _, frame in ipairs(frameSets.live) do
        table.insert(frames, frame)
    end
    for _, frame in ipairs(frameSets.preview) do
        table.insert(frames, frame)
    end

    return frames
end

---------------------------------------------------------------------------
-- ANCHOR FRAME RESOLUTION
---------------------------------------------------------------------------
function QUI_DandersFrames:GetAnchorFrame(anchorName)
    if not anchorName or anchorName == "disabled" then
        return nil
    end

    -- Hardcoded QUI element map
    if anchorName == "essential" then
        return _G.QUI_GetCDMViewerFrame and _G.QUI_GetCDMViewerFrame("essential")
    elseif anchorName == "utility" then
        return _G.QUI_GetCDMViewerFrame and _G.QUI_GetCDMViewerFrame("utility")
    elseif anchorName == "primary" then
        return QUICore and QUICore.powerBar
    elseif anchorName == "secondary" then
        return QUICore and QUICore.secondaryPowerBar
    elseif anchorName == "playerCastbar" then
        return ns.QUI_Castbar and ns.QUI_Castbar.castbars and ns.QUI_Castbar.castbars["player"]
    elseif anchorName == "playerFrame" then
        return ns.QUI_UnitFrames and ns.QUI_UnitFrames.frames and ns.QUI_UnitFrames.frames.player
    elseif anchorName == "targetFrame" then
        return ns.QUI_UnitFrames and ns.QUI_UnitFrames.frames and ns.QUI_UnitFrames.frames.target
    end

    -- Registry fallback
    if ns.QUI_Anchoring and ns.QUI_Anchoring.GetAnchorTarget then
        return ns.QUI_Anchoring:GetAnchorTarget(anchorName)
    end

    return nil
end

---------------------------------------------------------------------------
-- POSITIONING
---------------------------------------------------------------------------
local function ApplyPositionToFrames(frames, applyFunc)
    local shouldRetryAfterCombat = false

    for _, container in ipairs(frames) do
        local ok = pcall(applyFunc, container)
        if not ok then
            shouldRetryAfterCombat = true
        end
    end

    return shouldRetryAfterCombat
end

function QUI_DandersFrames:ApplyPosition(containerKey)
    local db = GetDB()
    if not db or not db[containerKey] then return end

    local cfg = db[containerKey]
    ClearLegacyFrameAnchoringForContainer(containerKey)
    if not cfg.enabled then return end

    local frameSets = self:GetContainerFrameSets(containerKey)
    if not frameSets then return end

    local hasAnchor = cfg.anchorTo and cfg.anchorTo ~= "disabled"
    local hasAbsolute = type(cfg.absolutePoint) == "string"

    -- Need either an anchor target or an explicit absolute position
    if not hasAnchor and not hasAbsolute then return end

    local anchorFrame
    if hasAnchor then
        anchorFrame = self:GetAnchorFrame(cfg.anchorTo)
        if not anchorFrame then return end
    end

    local inCombat = InCombatLockdown()
    local liveContainers = frameSets.live or {}
    local previewContainers = frameSets.preview or {}

    if inCombat then
        for _, container in ipairs(liveContainers) do
            if IsFrameProtected(container) then
                pendingUpdate = true
                return
            end
        end
    end

    local shouldRetryAfterCombat = ApplyPositionToFrames(liveContainers, function(container)
        container:ClearAllPoints()
        if not hasAnchor then
            container:SetPoint(
                cfg.absolutePoint or "CENTER",
                UIParent,
                "CENTER",
                cfg.absoluteX or 0,
                cfg.absoluteY or 0
            )
        else
            container:SetPoint(
                cfg.sourcePoint or "TOP",
                anchorFrame,
                cfg.targetPoint or "BOTTOM",
                cfg.offsetX or 0,
                cfg.offsetY or -5
            )
        end
    end)

    if #previewContainers > 0 then
        local previewRetry = ApplyPositionToFrames(previewContainers, function(container)
            container:ClearAllPoints()
            if not hasAnchor then
                container:SetPoint(
                    cfg.absolutePoint or "CENTER",
                    UIParent,
                    "CENTER",
                    cfg.absoluteX or 0,
                    cfg.absoluteY or 0
                )
            else
                container:SetPoint(
                    cfg.sourcePoint or "TOP",
                    anchorFrame,
                    cfg.targetPoint or "BOTTOM",
                    cfg.offsetX or 0,
                    cfg.offsetY or -5
                )
            end
        end)
        shouldRetryAfterCombat = shouldRetryAfterCombat or previewRetry
    end

    if shouldRetryAfterCombat then
        pendingUpdate = true
    end
end

function QUI_DandersFrames:ApplyAllPositions()
    self:ApplyPosition("party")
    self:ApplyPosition("raid")
    self:ApplyPosition("pinned1")
    self:ApplyPosition("pinned2")
end

---------------------------------------------------------------------------
-- EVENT HANDLING
---------------------------------------------------------------------------
local eventFrame = CreateFrame("Frame")

local function OnEvent(self, event, arg1)
    if event == "PLAYER_ENTERING_WORLD" then
        C_Timer.After(1.5, function()
            QUI_DandersFrames:Initialize()
        end)

    elseif event == "ADDON_LOADED" and arg1 == "DandersFrames" then
        C_Timer.After(1.5, function()
            QUI_DandersFrames:Initialize()
        end)

    elseif event == "PLAYER_REGEN_ENABLED" then
        if pendingUpdate then
            pendingUpdate = false
            C_Timer.After(0.1, function()
                QUI_DandersFrames:ApplyAllPositions()
            end)
        end

    elseif event == "GROUP_ROSTER_UPDATE" then
        -- Debounce roster updates
        if rosterTimer then
            rosterTimer:Cancel()
        end
        rosterTimer = C_Timer.NewTimer(0.3, function()
            rosterTimer = nil
            QUI_DandersFrames:ApplyAllPositions()
        end)
    end
end

eventFrame:SetScript("OnEvent", OnEvent)
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
eventFrame:RegisterEvent("GROUP_ROSTER_UPDATE")

---------------------------------------------------------------------------
-- INITIALIZE
---------------------------------------------------------------------------
local initialized = false

local function QueueApplyPosition(containerKey, delay)
    C_Timer.After(delay or 0, function()
        QUI_DandersFrames:ApplyPosition(containerKey)
    end)
end

function QUI_DandersFrames:Initialize()
    if initialized then return end
    if not self:IsAvailable() then return end

    initialized = true
    ClearLegacyFrameAnchoringForContainer("party")
    ClearLegacyFrameAnchoringForContainer("raid")
    ClearLegacyFrameAnchoringForContainer("pinned1")
    ClearLegacyFrameAnchoringForContainer("pinned2")
    self:ApplyAllPositions()
    RegisterLayoutModeElements()

    -- Hook into CDM layout update callback
    local previousUpdateAnchoredFrames = _G.QUI_UpdateAnchoredFrames
    if previousUpdateAnchoredFrames then
        _G.QUI_UpdateAnchoredFrames = function(...)
            previousUpdateAnchoredFrames(...)
            QUI_DandersFrames:ApplyAllPositions()
        end
    end

    -- Re-apply QUI anchors right after Danders test mode shows preview containers.
    -- Danders positions preview containers from its own anchor values on activation.
    if not previewHooksInstalled then
        local danders = _G["DandersFrames"]
        if danders and type(danders.ShowTestFrames) == "function" then
            hooksecurefunc(danders, "ShowTestFrames", function()
                -- Danders can do a late layout pass while showing previews.
                -- Apply immediately and once more shortly after.
                QueueApplyPosition("party", 0)
                QueueApplyPosition("party", 0.05)
            end)
        end
        if danders and type(danders.ShowRaidTestFrames) == "function" then
            hooksecurefunc(danders, "ShowRaidTestFrames", function()
                -- Mirror party behavior for raid preview containers.
                QueueApplyPosition("raid", 0)
                QueueApplyPosition("raid", 0.05)
            end)
        end
        previewHooksInstalled = true
    end
end

---------------------------------------------------------------------------
-- LAYOUT MODE: COORDINATE TRANSLATION HELPERS
---------------------------------------------------------------------------

--- Return the x,y screen coordinates of a specific anchor point on a frame.
local function GetPointScreenPosition(frame, point)
    if not frame then return 0, 0 end
    local l, r, t, b = frame:GetLeft(), frame:GetRight(), frame:GetTop(), frame:GetBottom()
    if not (l and r and t and b) then return 0, 0 end
    local cx, cy = (l + r) * 0.5, (t + b) * 0.5
    if point == "TOPLEFT"     then return l, t end
    if point == "TOP"         then return cx, t end
    if point == "TOPRIGHT"    then return r, t end
    if point == "LEFT"        then return l, cy end
    if point == "CENTER"      then return cx, cy end
    if point == "RIGHT"       then return r, cy end
    if point == "BOTTOMLEFT"  then return l, b end
    if point == "BOTTOM"      then return cx, b end
    if point == "BOTTOMRIGHT" then return r, b end
    return cx, cy
end

--- Return dx,dy offset from frame center to the named anchor point.
local function GetPointOffsetFromCenter(point, width, height)
    local hw, hh = (width or 0) * 0.5, (height or 0) * 0.5
    if point == "TOPLEFT"     then return -hw,  hh end
    if point == "TOP"         then return   0,  hh end
    if point == "TOPRIGHT"    then return  hw,  hh end
    if point == "LEFT"        then return -hw,   0 end
    if point == "CENTER"      then return   0,   0 end
    if point == "RIGHT"       then return  hw,   0 end
    if point == "BOTTOMLEFT"  then return -hw, -hh end
    if point == "BOTTOM"      then return   0, -hh end
    if point == "BOTTOMRIGHT" then return  hw, -hh end
    return 0, 0
end

--- Read the container's current screen position and return as UIParent-CENTER coords.
local function LoadDandersPosition(containerKey)
    local frames = QUI_DandersFrames:GetContainerFrames(containerKey)
    if not frames then return "CENTER", "CENTER", 0, 0 end
    -- Prefer a visible container (test mode during layout)
    local f
    for _, frame in ipairs(frames) do
        if frame:IsShown() then f = frame; break end
    end
    f = f or frames[1]
    if f then
        local cx, cy = f:GetCenter()
        if cx and cy then
            local uiW, uiH = UIParent:GetWidth(), UIParent:GetHeight()
            return "CENTER", "CENTER", cx - uiW * 0.5, cy - uiH * 0.5
        end
    end
    return "CENTER", "CENTER", 0, 0
end

--- Convert a new UIParent-CENTER position back to anchor-relative offsets,
--- or save as absolute UIParent-CENTER position when no anchor is configured.
local function SaveDandersPosition(containerKey, ox, oy)
    local db = GetDB()
    if not db or not db[containerKey] then return end
    local cfg = db[containerKey]

    ClearLegacyFrameAnchoringForContainer(containerKey)

    if not cfg.enabled then return end

    local useAbsolute = (not cfg.anchorTo or cfg.anchorTo == "disabled")

    if useAbsolute then
        -- Save as absolute UIParent-CENTER position
        cfg.absolutePoint = "CENTER"
        cfg.absoluteX = math.floor(ox + 0.5)
        cfg.absoluteY = math.floor(oy + 0.5)
    else
        local anchorFrame = QUI_DandersFrames:GetAnchorFrame(cfg.anchorTo)
        if not anchorFrame then return end

        -- Where the anchor frame's target point is on screen
        local targetX, targetY = GetPointScreenPosition(anchorFrame, cfg.targetPoint or "BOTTOM")

        -- Where the container center will be at the new position
        local uiW, uiH = UIParent:GetWidth(), UIParent:GetHeight()
        local newCenterX = uiW * 0.5 + ox
        local newCenterY = uiH * 0.5 + oy

        -- Get container size for source point offset calculation (prefer visible)
        local frames = QUI_DandersFrames:GetContainerFrames(containerKey)
        local f
        if frames then
            for _, frame in ipairs(frames) do
                if frame:IsShown() then f = frame; break end
            end
            f = f or frames[1]
        end
        local cw = f and f:GetWidth() or 160
        local ch = f and f:GetHeight() or 40

        -- Where the container's source point would be at the new center
        local srcDx, srcDy = GetPointOffsetFromCenter(cfg.sourcePoint or "TOP", cw, ch)
        local sourceX = newCenterX + srcDx
        local sourceY = newCenterY + srcDy

        -- New relative offsets
        cfg.offsetX = math.floor(sourceX - targetX + 0.5)
        cfg.offsetY = math.floor(sourceY - targetY + 0.5)
    end

    QUI_DandersFrames:ApplyPosition(containerKey)
end

---------------------------------------------------------------------------
-- LAYOUT MODE: ELEMENT REGISTRATION
---------------------------------------------------------------------------

local layoutElementsRegistered = false

local DANDERS_ELEMENTS = {
    { key = "dandersParty",   label = "DF Party",    order = 1, containerKey = "party",   showTest = "ShowTestFrames",     hideTest = "HideTestFrames" },
    { key = "dandersRaid",    label = "DF Raid",     order = 2, containerKey = "raid",    showTest = "ShowRaidTestFrames", hideTest = "HideRaidTestFrames" },
    { key = "dandersPinned1", label = "DF Pinned 1", order = 3, containerKey = "pinned1" },
    { key = "dandersPinned2", label = "DF Pinned 2", order = 4, containerKey = "pinned2" },
}

RegisterLayoutModeElements = function()
    if layoutElementsRegistered then return end
    if not QUI_DandersFrames:IsAvailable() then return end

    local um = ns.QUI_LayoutMode
    if not um or not um.RegisterElement then return end

    layoutElementsRegistered = true

    for _, info in ipairs(DANDERS_ELEMENTS) do
        local containerKey = info.containerKey
        local elementKey = info.key

        -- Return the first *visible* container (test mode during layout),
        -- falling back to the first frame in the list.
        local function GetPreferredFrame()
            local frames = QUI_DandersFrames:GetContainerFrames(containerKey)
            if not frames then return nil end
            for _, f in ipairs(frames) do
                if f:IsShown() then return f end
            end
            return frames[1]
        end

        um:RegisterElement({
            key = elementKey,
            label = info.label,
            group = "3rd Party",
            order = info.order,
            isOwned = false,
            usesCustomPositionPersistence = true,

            getFrame = GetPreferredFrame,

            getSize = function()
                local f = GetPreferredFrame()
                if f and f:IsShown() then
                    local w = f:GetWidth()
                    local h = f:GetHeight()
                    if w and w > 1 and h and h > 1 then
                        return w, h
                    end
                end
                return 160, 40
            end,

            isEnabled = function()
                local db = GetDB()
                local cfg = db and db[containerKey]
                return cfg and cfg.enabled
            end,

            setEnabled = function(val)
                local db = GetDB()
                if not db or not db[containerKey] then return end
                local old = db[containerKey].enabled
                db[containerKey].enabled = val
                if (val and true or false) ~= (old and true or false) then
                    local GUI = QUI and QUI.GUI
                    if GUI and GUI.ShowConfirmation then
                        GUI:ShowConfirmation({
                            title = "Reload UI?",
                            message = "DandersFrames changes require a reload to take effect.",
                            acceptText = "Reload",
                            cancelText = "Later",
                            onAccept = function() QUI:SafeReload() end,
                        })
                    end
                end
            end,

            onOpen = info.showTest and function()
                local danders = GetDandersAddon()
                if danders and type(danders[info.showTest]) == "function" then
                    pcall(danders[info.showTest], danders)
                end
                -- Re-sync handle after test frames finish async layout
                C_Timer.After(0.1, function()
                    if _G.QUI_LayoutModeSyncHandle then
                        _G.QUI_LayoutModeSyncHandle(elementKey)
                    end
                end)
            end or nil,

            onClose = info.hideTest and function()
                local danders = GetDandersAddon()
                if danders and type(danders[info.hideTest]) == "function" then
                    pcall(danders[info.hideTest], danders)
                end
            end or nil,

            loadPosition = function()
                return LoadDandersPosition(containerKey)
            end,

            savePosition = function(key, point, relPoint, newOx, newOy)
                SaveDandersPosition(containerKey, newOx, newOy)
            end,
        })
    end
end

-- Fallback: attempt layout registration after a delay in case Initialize
-- fires before layout mode is ready (mirrors pattern in other modules).
C_Timer.After(2, function()
    RegisterLayoutModeElements()
end)
