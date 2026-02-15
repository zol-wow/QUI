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

function QUI_DandersFrames:GetContainerFrames(containerKey)
    if not self:IsAvailable() then return nil end

    local frames = {}
    local seen = {}
    local danders = GetDandersAddon()

    if containerKey == "party" then
        -- Anchor the live party root container (not partyContainer) so we don't
        -- break Danders' internal SetAllPoints relationship.
        AddUniqueFrame(frames, seen, GetPartyLiveContainer())
        -- Danders test mode party preview container (non-secure)
        AddUniqueFrame(frames, seen, _G["DandersTestPartyContainer"])
        if danders and danders.testPartyContainer then
            AddUniqueFrame(frames, seen, danders.testPartyContainer)
        end
    elseif containerKey == "raid" then
        if type(DandersFrames_GetRaidContainer) == "function" then
            AddUniqueFrame(frames, seen, DandersFrames_GetRaidContainer())
        end
        -- Danders test mode raid preview container (non-secure)
        AddUniqueFrame(frames, seen, _G["DandersTestRaidContainer"])
        if danders and danders.testRaidContainer then
            AddUniqueFrame(frames, seen, danders.testRaidContainer)
        end
    elseif containerKey == "pinned1" and type(DandersFrames_GetPinnedContainer) == "function" then
        AddUniqueFrame(frames, seen, DandersFrames_GetPinnedContainer(1))
    elseif containerKey == "pinned2" and type(DandersFrames_GetPinnedContainer) == "function" then
        AddUniqueFrame(frames, seen, DandersFrames_GetPinnedContainer(2))
    end

    if #frames == 0 then
        return nil
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
        return _G["EssentialCooldownViewer"]
    elseif anchorName == "utility" then
        return _G["UtilityCooldownViewer"]
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
-- ANCHOR OPTIONS FOR DROPDOWNS
---------------------------------------------------------------------------
function QUI_DandersFrames:BuildAnchorOptions()
    local options = {
        {value = "disabled", text = "Disabled"},
        {value = "essential", text = "Essential Cooldowns"},
        {value = "utility", text = "Utility Cooldowns"},
        {value = "primary", text = "Primary Resource Bar"},
        {value = "secondary", text = "Secondary Resource Bar"},
        {value = "playerCastbar", text = "Player Castbar"},
        {value = "playerFrame", text = "Player Frame"},
        {value = "targetFrame", text = "Target Frame"},
    }

    -- Add registered anchor targets from the anchoring system
    if ns.QUI_Anchoring and ns.QUI_Anchoring.anchorTargets then
        for name, data in pairs(ns.QUI_Anchoring.anchorTargets) do
            -- Skip targets already in our hardcoded list
            if name ~= "disabled" and name ~= "essential" and name ~= "utility"
               and name ~= "primary" and name ~= "secondary" and name ~= "playerCastbar"
               and name ~= "playerFrame" and name ~= "targetFrame" then
                local displayName = data.options and data.options.displayName or name
                displayName = displayName:gsub("^%l", string.upper)
                displayName = displayName:gsub("([a-z])([A-Z])", "%1 %2")
                table.insert(options, {value = name, text = displayName})
            end
        end
    end

    return options
end

---------------------------------------------------------------------------
-- POSITIONING
---------------------------------------------------------------------------
function QUI_DandersFrames:ApplyPosition(containerKey)
    local db = GetDB()
    if not db or not db[containerKey] then return end

    local cfg = db[containerKey]
    if not cfg.enabled or cfg.anchorTo == "disabled" then return end

    local containers = self:GetContainerFrames(containerKey)
    if not containers then return end

    local anchorFrame = self:GetAnchorFrame(cfg.anchorTo)
    if not anchorFrame then return end

    local inCombat = InCombatLockdown()
    local shouldRetryAfterCombat = false

    for _, container in ipairs(containers) do
        -- Live DF containers are protected in combat; preview containers are not.
        if inCombat and IsFrameProtected(container) then
            shouldRetryAfterCombat = true
        else
            local ok = pcall(function()
                container:ClearAllPoints()
                container:SetPoint(
                    cfg.sourcePoint or "TOP",
                    anchorFrame,
                    cfg.targetPoint or "BOTTOM",
                    cfg.offsetX or 0,
                    cfg.offsetY or -5
                )
            end)

            if not ok then
                shouldRetryAfterCombat = true
            end
        end
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
    self:ApplyAllPositions()

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
