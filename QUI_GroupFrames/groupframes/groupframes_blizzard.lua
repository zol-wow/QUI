local ADDON_NAME, ns = ...
local Helpers = ns.Helpers
local GetDB = Helpers.CreateDBGetter("quiGroupFrames")

local pairs = pairs
local wipe = wipe
local CreateFrame = CreateFrame
local InCombatLockdown = InCombatLockdown
local hooksecurefunc = hooksecurefunc
local C_Timer = C_Timer

local QUI_GFB = {}
ns.QUI_GroupFrameBlizzard = QUI_GFB

local hiddenFrames = {}
local strippedFrames = {}
local hookedFrames = {}
local mouseStates = Helpers.CreateStateTable()
local banishStates = Helpers.CreateStateTable()
local hiddenParent
local stripRefreshPending
local hideRefreshPending
local StripBlizzardGroupEvents

local function ShouldHide()
    local db = GetDB()
    return db and db.enabled
end

local function EnsureHiddenParent()
    if not hiddenParent then
        hiddenParent = CreateFrame("Frame", "QUI_GroupFramesHiddenParent", UIParent)
        ns.SafeCallMethodIfPresent("best-effort-style", hiddenParent, "SetAllPoints", UIParent)
        hiddenParent:Hide()
    end
    return hiddenParent
end

local function CaptureMouseState(frame)
    local state = mouseStates[frame]
    if state then return state end

    state = {}
    local ok, value
    if frame.IsMouseEnabled then
        ok, value = ns.SafeCallMethod("best-effort-style", frame, "IsMouseEnabled")
        if ok then state.mouseEnabled = value and true or false end
    end
    if frame.IsMouseClickEnabled then
        ok, value = ns.SafeCallMethod("best-effort-style", frame, "IsMouseClickEnabled")
        if ok then state.mouseClickEnabled = value and true or false end
    end
    if frame.IsMouseMotionEnabled then
        ok, value = ns.SafeCallMethod("best-effort-style", frame, "IsMouseMotionEnabled")
        if ok then state.mouseMotionEnabled = value and true or false end
    end
    if frame.IsMouseWheelEnabled then
        ok, value = ns.SafeCallMethod("best-effort-style", frame, "IsMouseWheelEnabled")
        if ok then state.mouseWheelEnabled = value and true or false end
    end

    mouseStates[frame] = state
    return state
end

local function SuppressFrameMouse(frame)
    if not frame or InCombatLockdown() then return end

    CaptureMouseState(frame)

    ns.SafeCallMethodIfPresent("best-effort-style", frame, "EnableMouse", false)
    ns.SafeCallMethodIfPresent("best-effort-style", frame, "SetMouseClickEnabled", false)
    ns.SafeCallMethodIfPresent("best-effort-style", frame, "SetMouseMotionEnabled", false)
    ns.SafeCallMethodIfPresent("best-effort-style", frame, "EnableMouseWheel", false)
end

local function RestoreFrameMouse(frame)
    if not frame or InCombatLockdown() then return false end

    local state = mouseStates[frame]
    if not state then return true end

    if state.mouseEnabled ~= nil and frame.EnableMouse then
        ns.SafeCallMethod("best-effort-style", frame, "EnableMouse", state.mouseEnabled)
    end
    if state.mouseClickEnabled ~= nil and frame.SetMouseClickEnabled then
        ns.SafeCallMethod("best-effort-style", frame, "SetMouseClickEnabled", state.mouseClickEnabled)
    end
    if state.mouseMotionEnabled ~= nil and frame.SetMouseMotionEnabled then
        ns.SafeCallMethod("best-effort-style", frame, "SetMouseMotionEnabled", state.mouseMotionEnabled)
    end
    if state.mouseWheelEnabled ~= nil and frame.EnableMouseWheel then
        ns.SafeCallMethod("best-effort-style", frame, "EnableMouseWheel", state.mouseWheelEnabled)
    end

    mouseStates[frame] = nil
    return true
end

local function CaptureBanishState(frame)
    local state = banishStates[frame]
    if not state then
        state = {}
        banishStates[frame] = state
    end
    if state.banished then return state end

    local originalParent = UIParent
    if frame.GetParent then
        local ok, parent = ns.SafeCallMethod("best-effort-style", frame, "GetParent")
        if ok and parent then
            originalParent = parent
        end
    end
    state.originalParent = originalParent
    return state
end

local function BanishFrame(frame)
    if not frame then return false end

    local hidden = hiddenParent
    local parentOK, parent
    if hidden then
        parentOK, parent = ns.SafeCallMethod("best-effort-style", frame, "GetParent")
        if hiddenFrames[frame] and parentOK and parent == hidden then
            return false
        end
    end

    if InCombatLockdown() then
        ns.SafeCallMethodIfPresent("best-effort-style", frame, "SetAlpha", 0)
        hiddenFrames[frame] = true
        QUI_GFB.pendingHide = true
        return false
    end

    hidden = EnsureHiddenParent()
    parentOK, parent = ns.SafeCallMethod("best-effort-style", frame, "GetParent")
    local state = CaptureBanishState(frame)
    local reparented = parentOK and parent == hidden
    if not reparented then
        reparented = ns.SafeCallMethodIfPresent("best-effort-style", frame, "SetParent", hidden) == true
    end
    ns.SafeCallMethodIfPresent("best-effort-style", frame, "SetAlpha", 0)
    SuppressFrameMouse(frame)

    hiddenFrames[frame] = true
    state.banished = reparented
    return reparented
end

local function QueueStripBlizzardGroupEvents()
    if stripRefreshPending then return end
    stripRefreshPending = true
    C_Timer.After(0, function()
        stripRefreshPending = false
        if ShouldHide() then StripBlizzardGroupEvents() end
    end)
end

local function QueueHideBlizzardFrames()
    if hideRefreshPending then return end
    hideRefreshPending = true
    C_Timer.After(0.2, function()
        hideRefreshPending = false
        if InCombatLockdown() then
            QUI_GFB.pendingHide = true
            return
        end
        if ShouldHide() then QUI_GFB:HideBlizzardFrames() end
    end)
end

local function SafeHideFrame(frame)
    if not frame then return end
    BanishFrame(frame)
end

local function HideSelectionHighlights(frame)
    if not frame then return end
    ns.SafeCall("best-effort-style", function()
        if frame.selectionHighlight and frame.selectionHighlight.SetShown then
            frame.selectionHighlight:SetShown(false)
        end
        if frame.selectionIndicator and frame.selectionIndicator.SetShown then
            frame.selectionIndicator:SetShown(false)
        end
    end)
end

local function StripUnitFrameEvents(frame)
    if not frame then return end
    ns.SafeCall("best-effort-style", function()
        frame:UnregisterAllEvents()
    end)
    strippedFrames[frame] = true
end

local function RestoreUnitFrameEvents(frame)
    if not frame or not strippedFrames[frame] then return end
    strippedFrames[frame] = nil
    ns.SafeCall("best-effort-style", function()
        if CompactUnitFrame_UpdateUnitEvents then
            CompactUnitFrame_UpdateUnitEvents(frame)
        end
    end)
end

StripBlizzardGroupEvents = function()
    if PartyFrame and PartyFrame.PartyMemberFramePool then
        for memberFrame in PartyFrame.PartyMemberFramePool:EnumerateActive() do
            StripUnitFrameEvents(memberFrame)
        end
    end
    if CompactPartyFrame then
        for i = 1, 5 do
            StripUnitFrameEvents(_G["CompactPartyFrameMember" .. i])
        end
    end
    for i = 1, 4 do
        StripUnitFrameEvents(_G["PartyMemberFrame" .. i])
    end
    for i = 1, 40 do
        StripUnitFrameEvents(_G["CompactRaidFrame" .. i])
    end
end

local function RestoreFrame(frame)
    if not frame then return end
    if InCombatLockdown() then return false end

    local state = banishStates[frame]
    if state and state.originalParent and frame.SetParent then
        ns.SafeCallMethod("best-effort-style", frame, "SetParent", state.originalParent)
    end
    if state then
        state.banished = false
        banishStates[frame] = nil
    end

    RestoreFrameMouse(frame)
    ns.SafeCallMethod("best-effort-style", frame, "SetAlpha", 1)
    hiddenFrames[frame] = nil
    return true
end

local function InstallShowHook(frame)
    if not frame or hookedFrames[frame] then return end
    hooksecurefunc(frame, "Show", function(self)
        if not ShouldHide() then return end
        SafeHideFrame(self)
    end)
    hookedFrames[frame] = true
end

if CompactUnitFrame_UpdateSelectionHighlight then
    local sub = string.sub
    hooksecurefunc("CompactUnitFrame_UpdateSelectionHighlight", function(frame)
        if InCombatLockdown() then return end

        local unit = frame.unit or frame.displayedUnit
        if not unit then return end
        local p4 = sub(unit, 1, 4)
        if not (p4 == "part" or p4 == "raid" or unit == "player") then return end

        if not ShouldHide() then return end

        if frame.selectionHighlight and frame.selectionHighlight.SetShown then
            frame.selectionHighlight:SetShown(false)
        end
        if frame.selectionIndicator and frame.selectionIndicator.SetShown then
            frame.selectionIndicator:SetShown(false)
        end
    end)
end

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

if CompactUnitFrame_UpdateUnitEvents then
    hooksecurefunc("CompactUnitFrame_UpdateUnitEvents", function(frame)
        if not frame then return end
        if InCombatLockdown() then return end
        if not strippedFrames[frame] then return end

        StripUnitFrameEvents(frame)
    end)
end

local function HideBlizzardPartyFrames()
    if PartyFrame then
        SafeHideFrame(PartyFrame)
        InstallShowHook(PartyFrame)
    end

    if CompactPartyFrame then
        SafeHideFrame(CompactPartyFrame)
        HideSelectionHighlights(CompactPartyFrame)
        StripUnitFrameEvents(CompactPartyFrame)
        InstallShowHook(CompactPartyFrame)

        SafeHideFrame(CompactPartyFrame.borderFrame)
        SafeHideFrame(CompactPartyFrame.title)

        for i = 1, 5 do
            local mf = _G["CompactPartyFrameMember" .. i]
            if mf then
                SafeHideFrame(mf)
                HideSelectionHighlights(mf)
                StripUnitFrameEvents(mf)
                InstallShowHook(mf)
                if mf.readyCheckIcon then ns.SafeCallMethod("best-effort-style", mf.readyCheckIcon, "SetAlpha", 0) end
                if mf.readyCheckDecline then ns.SafeCallMethod("best-effort-style", mf.readyCheckDecline, "SetAlpha", 0) end
            end
        end
    end

    if PartyFrame and PartyFrame.PartyMemberFramePool then
        for memberFrame in PartyFrame.PartyMemberFramePool:EnumerateActive() do
            SafeHideFrame(memberFrame)
            StripUnitFrameEvents(memberFrame)
            InstallShowHook(memberFrame)
        end
    end
    for i = 1, 4 do
        local pf = _G["PartyMemberFrame" .. i]
        if pf then
            SafeHideFrame(pf)
            StripUnitFrameEvents(pf)
            InstallShowHook(pf)
        end
    end
end

local function HideBlizzardRaidFrames()
    SafeHideFrame(CompactRaidFrameContainer)
    if CompactRaidFrameContainer then
        InstallShowHook(CompactRaidFrameContainer)
    end

    for i = 1, 40 do
        local rf = _G["CompactRaidFrame" .. i]
        if rf then
            SafeHideFrame(rf)
            HideSelectionHighlights(rf)
            StripUnitFrameEvents(rf)
            InstallShowHook(rf)
        end
    end

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

function QUI_GFB:HideBlizzardFrames()
    if not ShouldHide() then return end

    if InCombatLockdown() then
        self.pendingHide = true
        return
    end

    HideBlizzardPartyFrames()
    HideBlizzardRaidFrames()
end

function QUI_GFB:RestoreBlizzardFrames()
    if InCombatLockdown() then
        self.pendingRestore = true
        return
    end

    for frame in pairs(hiddenFrames) do
        RestoreFrame(frame)
    end
    wipe(hiddenFrames)

    for frame in pairs(strippedFrames) do
        RestoreUnitFrameEvents(frame)
    end
    wipe(strippedFrames)

end

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

local blizzardEventFrame = CreateFrame("Frame")
blizzardEventFrame:RegisterEvent("ADDON_LOADED")
blizzardEventFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
blizzardEventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
blizzardEventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
blizzardEventFrame:RegisterEvent("PARTY_MEMBER_ENABLE")
blizzardEventFrame:RegisterEvent("PARTY_MEMBER_DISABLE")
blizzardEventFrame:SetScript("OnEvent", function(_, event, addonName)
    if event == "ADDON_LOADED" then
        if addonName == ADDON_NAME then
            if ShouldHide() then
                HideBlizzardPartyFrames()
                HideBlizzardRaidFrames()
            end
        elseif addonName == "Blizzard_CompactRaidFrames" then
            if ShouldHide() and not InCombatLockdown() then
                HideBlizzardRaidFrames()
            end
        end
        return
    end

    if not ShouldHide() then return end

    QueueStripBlizzardGroupEvents()

    if InCombatLockdown() then
        QUI_GFB.pendingHide = true
        return
    end

    QueueHideBlizzardFrames()
end)
