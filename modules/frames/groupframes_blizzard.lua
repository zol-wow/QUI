--[[
    QUI Group Frames - Blizzard Frame Hider
    Hides default Blizzard party/raid frames when QUI group frames are enabled.
    Uses hooksecurefunc to catch Blizzard re-showing frames (reactive, not polling).
    Alpha=0, selection highlight suppression, event stripping.

    COMBAT RELOAD SAFETY: Initial hide runs at ADDON_LOADED where
    InCombatLockdown() returns false even during a combat /reload.
    Show hooks use SetAlpha(0) only (safe during combat) and defer
    Hide() to after combat ends.
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
local hookedFrames = {}  -- frames with Show hooks installed

---------------------------------------------------------------------------
-- Should we be hiding?
---------------------------------------------------------------------------
local function ShouldHide()
    local db = GetDB()
    return db and db.enabled
end

---------------------------------------------------------------------------
-- HELPERS: Safe alpha hide
---------------------------------------------------------------------------
local function SafeHideFrame(frame)
    if not frame then return end
    pcall(frame.SetAlpha, frame, 0)
    hiddenFrames[frame] = true
end

local function SafeScaleContainer(frame, hide)
    if not frame then return end
    if InCombatLockdown() then
        if hide then SafeHideFrame(frame) end
        return
    end
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
-- HELPERS: Combat-aware hide/show (Hide() is protected, SetAlpha is not)
---------------------------------------------------------------------------
local function ForceHideShow(frame, hide)
    if not frame then return end
    pcall(function()
        if InCombatLockdown() then
            frame:SetAlpha(hide and 0 or 1)
        else
            if hide then
                frame:Hide()
            else
                frame:SetAlpha(1)
                frame:Show()
            end
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
    pcall(frame.SetAlpha, frame, 1)
    hiddenFrames[frame] = nil
    return true
end

---------------------------------------------------------------------------
-- HOOK: Install a Show hook on a frame to re-hide it when Blizzard restores it
---------------------------------------------------------------------------
local function InstallShowHook(frame)
    if not frame or hookedFrames[frame] then return end
    hooksecurefunc(frame, "Show", function(self)
        if not ShouldHide() then return end
        ForceHideShow(self, true)
    end)
    hookedFrames[frame] = true
end

---------------------------------------------------------------------------
-- HOOK: Suppress Blizzard selection highlight updates
-- TAINT SAFETY: These hooks fire for ALL CompactUnitFrames, including
-- nameplate frames. During combat, any addon code in the posthook can
-- taint the nameplate widget chain. InCombatLockdown() guard prevents
-- addon data access during combat. Unit check before GetDB() minimizes
-- addon code execution for non-party/raid frames (nameplates, boss frames).
---------------------------------------------------------------------------
if CompactUnitFrame_UpdateSelectionHighlight then
    hooksecurefunc("CompactUnitFrame_UpdateSelectionHighlight", function(frame)
        if InCombatLockdown() then return end

        local unit = frame.unit or frame.displayedUnit
        if not unit then return end
        if not (unit == "player" or unit:match("^party") or unit:match("^raid")) then return end

        if not ShouldHide() then return end

        if frame.selectionHighlight and frame.selectionHighlight.SetShown then
            frame.selectionHighlight:SetShown(false)
        end
        if frame.selectionIndicator and frame.selectionIndicator.SetShown then
            frame.selectionIndicator:SetShown(false)
        end
    end)
end

---------------------------------------------------------------------------
-- HOOK: Suppress Blizzard ready check icons on hidden frames
---------------------------------------------------------------------------
local function SuppressBlizzardReadyCheck(frame)
    if not frame then return end
    if InCombatLockdown() then return end

    local unit = frame.unit or frame.displayedUnit
    if not unit then return end
    if not (unit == "player" or unit:match("^party") or unit:match("^raid")) then return end

    if not ShouldHide() then return end

    if frame.readyCheckIcon then
        frame.readyCheckIcon:SetAlpha(0)
    end
    if frame.readyCheckDecline then
        frame.readyCheckDecline:SetAlpha(0)
    end
end

if CompactUnitFrame_UpdateReadyCheck then
    hooksecurefunc("CompactUnitFrame_UpdateReadyCheck", SuppressBlizzardReadyCheck)
end

---------------------------------------------------------------------------
-- HOOK: Re-strip events when Blizzard tries to restore them
---------------------------------------------------------------------------
if CompactUnitFrame_UpdateUnitEvents then
    hooksecurefunc("CompactUnitFrame_UpdateUnitEvents", function(frame)
        if not frame then return end
        if InCombatLockdown() then return end
        if not strippedFrames[frame] then return end

        -- Blizzard just restored events on a frame we stripped — re-strip it
        StripUnitFrameEvents(frame)
    end)
end

---------------------------------------------------------------------------
-- HIDE: Blizzard party frames
---------------------------------------------------------------------------
local function HideBlizzardPartyFrames()
    -- Modern PartyFrame container
    if PartyFrame then
        SafeHideFrame(PartyFrame)
        InstallShowHook(PartyFrame)
    end

    -- CompactPartyFrame (Retail party frames)
    if CompactPartyFrame then
        SafeHideFrame(CompactPartyFrame)
        HideSelectionHighlights(CompactPartyFrame)
        StripUnitFrameEvents(CompactPartyFrame)
        InstallShowHook(CompactPartyFrame)

        -- Hide border/title overlays
        SafeHideFrame(CompactPartyFrame.borderFrame)
        SafeHideFrame(CompactPartyFrame.title)

        -- Individual member frames
        for i = 1, 5 do
            local mf = _G["CompactPartyFrameMember" .. i]
            if mf then
                SafeHideFrame(mf)
                HideSelectionHighlights(mf)
                StripUnitFrameEvents(mf)
                InstallShowHook(mf)
                if mf.readyCheckIcon then pcall(mf.readyCheckIcon.SetAlpha, mf.readyCheckIcon, 0) end
                if mf.readyCheckDecline then pcall(mf.readyCheckDecline.SetAlpha, mf.readyCheckDecline, 0) end
            end
        end
    end

    -- Legacy PartyMemberFrame1-4
    for i = 1, 4 do
        local pf = _G["PartyMemberFrame" .. i]
        if pf then
            SafeHideFrame(pf)
            StripUnitFrameEvents(pf)
            InstallShowHook(pf)
        end
    end
end

---------------------------------------------------------------------------
-- HIDE: Blizzard raid frames
---------------------------------------------------------------------------
local function HideBlizzardRaidFrames()
    -- CompactRaidFrameContainer — scale trick makes it effectively invisible
    SafeScaleContainer(CompactRaidFrameContainer, true)
    if CompactRaidFrameContainer then
        InstallShowHook(CompactRaidFrameContainer)
    end

    -- CompactRaidFrameManager (the "raid" tab on left side)
    if CompactRaidFrameManager then
        SafeHideFrame(CompactRaidFrameManager)
        SafeHideFrame(CompactRaidFrameManager.container)
        SafeHideFrame(CompactRaidFrameManager.toggleButton)
        SafeHideFrame(CompactRaidFrameManager.displayFrame)
        InstallShowHook(CompactRaidFrameManager)
        if CompactRaidFrameManager.displayFrame then
            InstallShowHook(CompactRaidFrameManager.displayFrame)
        end
    end

    -- Individual CompactRaidFrame1-40
    for i = 1, 40 do
        local rf = _G["CompactRaidFrame" .. i]
        if rf then
            SafeHideFrame(rf)
            HideSelectionHighlights(rf)
            StripUnitFrameEvents(rf)
            InstallShowHook(rf)
        end
    end

    -- CompactRaidGroup headers and their members
    for group = 1, 8 do
        local gf = _G["CompactRaidGroup" .. group]
        if gf then
            SafeHideFrame(gf)
            InstallShowHook(gf)
        end
        for member = 1, 5 do
            local rf = _G["CompactRaidGroup" .. group .. "Member" .. member]
            if rf then
                SafeHideFrame(rf)
                HideSelectionHighlights(rf)
                StripUnitFrameEvents(rf)
                InstallShowHook(rf)
            end
        end
    end
end

---------------------------------------------------------------------------
-- HIDE: All Blizzard group frames
---------------------------------------------------------------------------
function QUI_GFB:HideBlizzardFrames()
    if not ShouldHide() then return end

    if InCombatLockdown() then
        self.pendingHide = true
        return
    end

    HideBlizzardPartyFrames()
    HideBlizzardRaidFrames()
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

    -- Note: hooks remain installed but ShouldHide() will return false,
    -- so they become no-ops until re-enabled.
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

---------------------------------------------------------------------------
-- EVENTS: Initial hide at ADDON_LOADED + re-apply on group changes
--
-- ADDON_LOADED runs the initial hide. This is critical for combat reload
-- support: InCombatLockdown() returns false at ADDON_LOADED even during
-- a combat /reload, giving us a safe window for protected operations.
-- Subsequent events (roster changes, zone transitions) re-apply as needed.
---------------------------------------------------------------------------
local blizzardEventFrame = CreateFrame("Frame")
blizzardEventFrame:RegisterEvent("ADDON_LOADED")
blizzardEventFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
blizzardEventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
blizzardEventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
blizzardEventFrame:RegisterEvent("PARTY_MEMBER_ENABLE")
blizzardEventFrame:RegisterEvent("PARTY_MEMBER_DISABLE")
blizzardEventFrame:SetScript("OnEvent", function(_, event, addonName)
    -- Initial hide at ADDON_LOADED — runs during the safe window where
    -- InCombatLockdown() is false even on a combat /reload
    if event == "ADDON_LOADED" then
        if addonName == ADDON_NAME then
            -- Our own addon loaded — hide immediately if DB is ready
            if ShouldHide() then
                HideBlizzardPartyFrames()
                HideBlizzardRaidFrames()
            end
        elseif addonName == "Blizzard_CompactRaidFrames" then
            -- Blizzard raid frames loaded late — re-hide
            if ShouldHide() and not InCombatLockdown() then
                HideBlizzardRaidFrames()
            end
        end
        return
    end

    if not ShouldHide() then return end

    if InCombatLockdown() then
        QUI_GFB.pendingHide = true
        return
    end

    -- Delayed to let Blizzard frames initialize/reposition first
    C_Timer.After(0.2, function()
        if InCombatLockdown() then
            QUI_GFB.pendingHide = true
            return
        end
        QUI_GFB:HideBlizzardFrames()
    end)
end)
