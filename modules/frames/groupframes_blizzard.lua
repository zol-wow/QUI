--[[
    QUI Group Frames - Blizzard Frame Hider
    Hides default Blizzard party/raid frames when QUI group frames are enabled.
    Mirrors DandersFrames approach: alpha=0, selection highlight suppression,
    event stripping, and hooksecurefunc on CompactUnitFrame_UpdateSelectionHighlight.
]]

local ADDON_NAME, ns = ...
local Helpers = ns.Helpers
local GetDB = Helpers.CreateDBGetter("quiGroupFrames")

---------------------------------------------------------------------------
-- MODULE TABLE
---------------------------------------------------------------------------
local QUI_GFB = {}
ns.QUI_GroupFrameBlizzard = QUI_GFB

-- Track what we've hidden/stripped so we can restore
local hiddenFrames = {}
local strippedFrames = {}
local watcherFrame = nil

---------------------------------------------------------------------------
-- HELPERS: Safe alpha hide
---------------------------------------------------------------------------
local function SafeHideFrame(frame)
    if not frame then return end
    pcall(function()
        frame:SetAlpha(0)
        frame:EnableMouse(false)
    end)
    hiddenFrames[frame] = true
end

local function SafeHideFrameOffscreen(frame)
    if not frame then return end
    if InCombatLockdown() then return end
    pcall(function()
        frame:SetAlpha(0)
        frame:EnableMouse(false)
        frame:ClearAllPoints()
        frame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", -10000, 10000)
    end)
    hiddenFrames[frame] = true
end

local function SafeScaleContainer(frame, hide)
    if not frame then return end
    if InCombatLockdown() then return end
    pcall(function()
        if hide then
            frame:SetAlpha(0)
            frame:SetScale(0.001)
        else
            frame:SetAlpha(1)
            frame:SetScale(1)
        end
    end)
    if hide then hiddenFrames[frame] = true end
end

---------------------------------------------------------------------------
-- HELPERS: Selection highlight suppression
---------------------------------------------------------------------------
local function HideSelectionHighlights(frame)
    if not frame then return end
    pcall(function()
        if frame.selectionHighlight and frame.selectionHighlight.SetShown then
            frame.selectionHighlight:SetShown(false)
        end
        if frame.selectionIndicator and frame.selectionIndicator.SetShown then
            frame.selectionIndicator:SetShown(false)
        end
    end)
end

---------------------------------------------------------------------------
-- HELPERS: Event stripping (stop Blizzard from updating hidden frames)
---------------------------------------------------------------------------
local function StripUnitFrameEvents(frame)
    if not frame then return end
    pcall(function()
        frame:UnregisterAllEvents()
        -- Keep UNIT_AURA alive so Blizzard's aura cache still updates
        -- (DandersFrames "Blizzard mode" pattern — avoids stale aura data)
        local unit = frame.unit or frame.displayedUnit
        if unit and frame.RegisterUnitEvent then
            frame:RegisterUnitEvent("UNIT_AURA", unit)
        end
    end)
    strippedFrames[frame] = true
end

local function RestoreUnitFrameEvents(frame)
    if not frame or not strippedFrames[frame] then return end
    pcall(function()
        if CompactUnitFrame_UpdateUnitEvents then
            CompactUnitFrame_UpdateUnitEvents(frame)
        end
    end)
    strippedFrames[frame] = nil
end

---------------------------------------------------------------------------
-- HELPERS: Restore frame
---------------------------------------------------------------------------
local function RestoreFrame(frame)
    if not frame then return end
    if InCombatLockdown() then return false end
    pcall(function()
        frame:SetAlpha(1)
        frame:EnableMouse(true)
    end)
    hiddenFrames[frame] = nil
    return true
end

---------------------------------------------------------------------------
-- HOOK: Suppress Blizzard selection highlight updates
---------------------------------------------------------------------------
if CompactUnitFrame_UpdateSelectionHighlight then
    hooksecurefunc("CompactUnitFrame_UpdateSelectionHighlight", function(frame)
        local db = GetDB()
        if not db or not db.enabled then return end

        local unit = frame.unit or frame.displayedUnit
        if not unit then return end

        local isParty = unit:match("^party") or unit == "player"
        local isRaid = unit:match("^raid")

        if isParty or isRaid then
            if frame.selectionHighlight and frame.selectionHighlight.SetShown then
                frame.selectionHighlight:SetShown(false)
            end
            if frame.selectionIndicator and frame.selectionIndicator.SetShown then
                frame.selectionIndicator:SetShown(false)
            end
        end
    end)
end

---------------------------------------------------------------------------
-- HOOK: Suppress Blizzard ready check icons on hidden frames
---------------------------------------------------------------------------
local function SuppressBlizzardReadyCheck(frame)
    if not frame then return end
    local db = GetDB()
    if not db or not db.enabled then return end

    local unit = frame.unit or frame.displayedUnit
    if not unit then return end

    local isParty = unit:match("^party") or unit == "player"
    local isRaid = unit:match("^raid")

    if isParty or isRaid then
        if frame.readyCheckIcon then
            frame.readyCheckIcon:SetAlpha(0)
        end
        if frame.readyCheckDecline then
            frame.readyCheckDecline:SetAlpha(0)
        end
    end
end

if CompactUnitFrame_UpdateReadyCheck then
    hooksecurefunc("CompactUnitFrame_UpdateReadyCheck", SuppressBlizzardReadyCheck)
end

---------------------------------------------------------------------------
-- HOOK: Re-strip events when Blizzard tries to restore them
-- (DandersFrames pattern — Blizzard calls CompactUnitFrame_UpdateUnitEvents
-- on hidden frames during roster changes, which restores their events)
---------------------------------------------------------------------------
if CompactUnitFrame_UpdateUnitEvents then
    hooksecurefunc("CompactUnitFrame_UpdateUnitEvents", function(frame)
        if not frame then return end
        if not strippedFrames[frame] then return end

        -- Blizzard just restored events on a frame we stripped — re-strip it
        StripUnitFrameEvents(frame)
    end)
end

---------------------------------------------------------------------------
-- HIDE: Blizzard party frames
---------------------------------------------------------------------------
local function HideBlizzardPartyFrames()
    if InCombatLockdown() then return end

    -- CompactPartyFrame (Retail party frames)
    if CompactPartyFrame then
        SafeHideFrame(CompactPartyFrame)
        HideSelectionHighlights(CompactPartyFrame)
        StripUnitFrameEvents(CompactPartyFrame)

        -- Hide border/title overlays
        SafeHideFrame(CompactPartyFrame.borderFrame)
        SafeHideFrame(CompactPartyFrame.title)

        -- Individual member frames: alpha=0, suppress highlights/readycheck, strip events
        for i = 1, 5 do
            local mf = _G["CompactPartyFrameMember" .. i]
            if mf then
                SafeHideFrame(mf)
                HideSelectionHighlights(mf)
                StripUnitFrameEvents(mf)
                -- Hide ready check elements on Blizzard frames
                if mf.readyCheckIcon then pcall(function() mf.readyCheckIcon:SetAlpha(0) end) end
                if mf.readyCheckDecline then pcall(function() mf.readyCheckDecline:SetAlpha(0) end) end
            end
        end
    end

    -- Legacy PartyMemberFrame1-4
    for i = 1, 4 do
        local pf = _G["PartyMemberFrame" .. i]
        if pf then
            SafeHideFrameOffscreen(pf)
            StripUnitFrameEvents(pf)
        end
    end
end

---------------------------------------------------------------------------
-- HIDE: Blizzard raid frames
---------------------------------------------------------------------------
local function HideBlizzardRaidFrames()
    if InCombatLockdown() then return end

    -- CompactRaidFrameContainer — scale trick makes it effectively invisible
    SafeScaleContainer(CompactRaidFrameContainer, true)

    -- CompactRaidFrameManager (the "raid" tab on left side)
    if CompactRaidFrameManager then
        SafeHideFrame(CompactRaidFrameManager)
        SafeHideFrame(CompactRaidFrameManager.container)
        SafeHideFrame(CompactRaidFrameManager.toggleButton)
        SafeHideFrame(CompactRaidFrameManager.displayFrame)
    end

    -- Individual CompactRaidFrame1-40
    for i = 1, 40 do
        local rf = _G["CompactRaidFrame" .. i]
        if rf then
            SafeHideFrame(rf)
            HideSelectionHighlights(rf)
            StripUnitFrameEvents(rf)
        end
    end

    -- CompactRaidGroup headers and their members
    for group = 1, 8 do
        SafeHideFrame(_G["CompactRaidGroup" .. group])
        for member = 1, 5 do
            local rf = _G["CompactRaidGroup" .. group .. "Member" .. member]
            if rf then
                SafeHideFrame(rf)
                HideSelectionHighlights(rf)
                StripUnitFrameEvents(rf)
            end
        end
    end
end

---------------------------------------------------------------------------
-- HIDE: All Blizzard group frames
---------------------------------------------------------------------------
function QUI_GFB:HideBlizzardFrames()
    local db = GetDB()
    if not db or not db.enabled then return end

    if InCombatLockdown() then
        self.pendingHide = true
        return
    end

    HideBlizzardPartyFrames()
    HideBlizzardRaidFrames()

    -- Start watcher to re-hide frames if Blizzard restores them
    self:StartWatcher()
end

---------------------------------------------------------------------------
-- RESTORE: All Blizzard group frames
---------------------------------------------------------------------------
function QUI_GFB:RestoreBlizzardFrames()
    if InCombatLockdown() then
        self.pendingRestore = true
        return
    end

    -- Restore all hidden frames
    for frame in pairs(hiddenFrames) do
        RestoreFrame(frame)
    end
    wipe(hiddenFrames)

    -- Restore stripped events
    for frame in pairs(strippedFrames) do
        RestoreUnitFrameEvents(frame)
    end
    wipe(strippedFrames)

    -- Restore scaled containers
    SafeScaleContainer(CompactRaidFrameContainer, false)

    -- Stop watcher
    self:StopWatcher()
end

---------------------------------------------------------------------------
-- WATCHER: Re-hide if Blizzard restores frames
---------------------------------------------------------------------------
function QUI_GFB:StartWatcher()
    if watcherFrame then return end

    watcherFrame = CreateFrame("Frame")
    local elapsed = 0
    watcherFrame:SetScript("OnUpdate", function(self, dt)
        elapsed = elapsed + dt
        if elapsed < 1.0 then return end
        elapsed = 0

        if Helpers.IsEditModeActive and Helpers.IsEditModeActive() then return end
        if InCombatLockdown() then return end

        local db = GetDB()
        if not db or not db.enabled then return end

        -- Re-hide CompactPartyFrame and children if Blizzard restored them
        if CompactPartyFrame and CompactPartyFrame:GetAlpha() > 0 then
            C_Timer.After(0, function()
                if InCombatLockdown() then return end
                HideBlizzardPartyFrames()
            end)
        end

        -- Re-hide raid frames if restored
        if CompactRaidFrameManager and CompactRaidFrameManager:GetAlpha() > 0 then
            C_Timer.After(0, function()
                if InCombatLockdown() then return end
                HideBlizzardRaidFrames()
            end)
        end
        if CompactRaidFrameContainer and CompactRaidFrameContainer:GetAlpha() > 0 then
            C_Timer.After(0, function()
                if InCombatLockdown() then return end
                HideBlizzardRaidFrames()
            end)
        end
    end)
end

function QUI_GFB:StopWatcher()
    if watcherFrame then
        watcherFrame:SetScript("OnUpdate", nil)
        watcherFrame:Hide()
        watcherFrame = nil
    end
end

---------------------------------------------------------------------------
-- COMBAT EVENTS: Deferred operations
---------------------------------------------------------------------------
local combatFrame = CreateFrame("Frame")
combatFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
combatFrame:SetScript("OnEvent", function()
    if QUI_GFB.pendingHide then
        QUI_GFB.pendingHide = false
        QUI_GFB:HideBlizzardFrames()
    end
    if QUI_GFB.pendingRestore then
        QUI_GFB.pendingRestore = false
        QUI_GFB:RestoreBlizzardFrames()
    end
end)
