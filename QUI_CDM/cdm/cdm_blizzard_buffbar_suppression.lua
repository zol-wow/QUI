local _, ns = ...
local unpackValue = table.unpack or unpack

local Suppressor = {
    _states = setmetatable({}, { __mode = "k" }),
    _pendingSuppress = setmetatable({}, { __mode = "k" }),
    _pendingNative = false,
    _pendingFlushScheduled = false,
    _dataRetryRegistered = false,
}
ns.CDMBlizzardBuffBarSuppressor = Suppressor

local function IsCooldownViewerReady()
    local catalog = ns.CDMCatalog
    if catalog and catalog.IsCooldownViewerReady then
        return catalog.IsCooldownViewerReady()
    end

    local api = _G.C_CooldownViewer
    if not api then return false end
    if not api.IsCooldownViewerAvailable then return true end
    local ok, ready = pcall(api.IsCooldownViewerAvailable)
    return ok and ready == true
end

local function InCombat()
    return InCombatLockdown and InCombatLockdown()
end

local function GetNativeBuffBar()
    return _G.BuffBarCooldownViewer
end

local function CapturePoints(frame)
    local points = {}
    if frame.GetNumPoints and frame.GetPoint then
        local count = frame:GetNumPoints() or 0
        for i = 1, count do
            points[#points + 1] = { frame:GetPoint(i) }
        end
    end
    return points
end

local function RestorePoints(frame, points)
    if not (frame and frame.ClearAllPoints and frame.SetPoint) then return end
    frame:ClearAllPoints()
    if type(points) == "table" and #points > 0 then
        for i = 1, #points do
            frame:SetPoint(unpackValue(points[i]))
        end
    elseif _G.UIParent then
        frame:SetPoint("CENTER", _G.UIParent, "CENTER", 0, 0)
    end
end

local function ParkOffscreen(frame, state)
    if not (frame and frame.ClearAllPoints and frame.SetPoint and _G.UIParent) then
        return false
    end
    state.parkGuard = true
    frame:ClearAllPoints()
    frame:SetPoint("TOPLEFT", _G.UIParent, "BOTTOMLEFT", 0, -10000)
    state.parkGuard = nil
    return true
end

local function IsParked(frame)
    if not (frame and frame.GetNumPoints and frame.GetPoint) then return false end
    if (frame:GetNumPoints() or 0) < 1 then return false end
    local point, relativeTo, relativePoint, _, y = frame:GetPoint(1)
    return point == "TOPLEFT"
        and (relativeTo == _G.UIParent or relativeTo == nil)
        and relativePoint == "BOTTOMLEFT"
        and type(y) == "number"
        and y < -9990
end

local function InstallParkHooks(frame, state)
    if state.parkHooked or not hooksecurefunc then return end
    local timer = _G.C_Timer
    if not (timer and timer.After) then return end

    local function QueueRepark()
        if not state.hidden or state.parkGuard or state.restoring or state.parkQueued then return end
        state.parkQueued = true
        timer.After(0, function()
            state.parkQueued = nil
            if state.hidden and not state.restoring then
                Suppressor:Suppress(frame)
            end
        end)
    end

    state.parkHooked = true
    if frame.SetAlpha then
        hooksecurefunc(frame, "SetAlpha", function()
            if not state.hidden or state.restoring or state.alphaGuard then return end
            state.alphaGuard = true
            frame:SetAlpha(0)
            state.alphaGuard = nil
        end)
    end
    if frame.SetPoint then hooksecurefunc(frame, "SetPoint", QueueRepark) end
    if frame.SetAllPoints then hooksecurefunc(frame, "SetAllPoints", QueueRepark) end
    if frame.SetParent then hooksecurefunc(frame, "SetParent", QueueRepark) end
end

local function PrimeHiddenFrame(frame)
    local state = Suppressor._states[frame]
    if not state then
        state = {}
        Suppressor._states[frame] = state
    end
    state.restorePending = nil
    state.restoring = nil
    state.hidden = true
    InstallParkHooks(frame, state)
    if frame.SetAlpha then frame:SetAlpha(0) end
    return state
end

local function DisableMouse(frame)
    if frame.EnableMouse then frame:EnableMouse(false) end
    if frame.EnableMouseMotion then frame:EnableMouseMotion(false) end
end

function Suppressor:ShouldSuppress(settings)
    if settings and settings.enabled == false then
        return false
    end

    local profile = _G.QUI and _G.QUI.db and _G.QUI.db.profile
    local ncdm = profile and profile.ncdm
    if ncdm and ncdm.enabled == false then
        return false
    end
    if ncdm and ncdm.trackedBar and ncdm.trackedBar.enabled == false then
        return false
    end

    return true
end

function Suppressor:Suppress(frame)
    frame = frame or GetNativeBuffBar()
    if not frame then
        self:QueueSuppress()
        return false
    end

    local state = PrimeHiddenFrame(frame)
    if not IsCooldownViewerReady() then
        self:QueueSuppress(frame)
        return false
    end

    if not state.originalPoints and not state.parked then
        state.originalPoints = CapturePoints(frame)
    end

    if not InCombat() then
        DisableMouse(frame)
        state.parked = ParkOffscreen(frame, state)
        state.parkPending = nil
    else
        state.parkPending = true
    end

    return true
end

function Suppressor:QueueSuppress(frame)
    frame = frame or GetNativeBuffBar()
    if frame then
        self._pendingSuppress[frame] = true
    else
        self._pendingNative = true
    end
    self:_EnsureDataRetry()
end

function Suppressor:Restore(frame)
    self._pendingNative = false
    frame = frame or GetNativeBuffBar()
    if not frame then return false end
    self._pendingSuppress[frame] = nil

    local state = self._states[frame]
    if state and state.hidden then state.restoring = true end
    if frame.SetAlpha then frame:SetAlpha(1) end

    if state and state.hidden and not InCombat() then
        if state.parked or state.parkPending then
            RestorePoints(frame, state.originalPoints)
        end
        state.parked = nil
        state.parkPending = nil
        state.hidden = false
        state.restoring = nil
    elseif state and state.hidden and InCombat() then
        state.restorePending = true
    end

    return false
end

function Suppressor:Apply(settings, frame)
    if self:ShouldSuppress(settings) then
        return self:Suppress(frame)
    end
    return self:Restore(frame)
end

function Suppressor:FlushPendingRestore()
    if InCombat() then return end
    for frame, state in pairs(self._states) do
        if state.restorePending then
            state.restorePending = nil
            state.restoring = true
            if state.parked or state.parkPending then
                RestorePoints(frame, state.originalPoints)
            end
            state.parked = nil
            state.parkPending = nil
            state.hidden = false
            state.restoring = nil
        elseif state.hidden and state.parkPending then
            state.parked = ParkOffscreen(frame, state)
            state.parkPending = nil
        end
    end
end

function Suppressor:FlushPendingSuppress()
    if not IsCooldownViewerReady() then return end
    if self._pendingNative then
        local frame = GetNativeBuffBar()
        if frame then
            self._pendingNative = false
            self:Suppress(frame)
        end
    end
    for frame in pairs(self._pendingSuppress) do
        self._pendingSuppress[frame] = nil
        self:Suppress(frame)
    end
end

function Suppressor:SchedulePendingSuppressFlush()
    if self._pendingNative then
        local frame = GetNativeBuffBar()
        if frame then PrimeHiddenFrame(frame) end
    end
    if self._pendingFlushScheduled then return end
    self._pendingFlushScheduled = true

    local function Flush()
        self._pendingFlushScheduled = false
        self:FlushPendingSuppress()
        self:CheckParkIntegrity()
    end
    local timer = _G.C_Timer
    if timer and timer.After then
        timer.After(0, Flush)
    else
        Flush()
    end
end

function Suppressor:CheckParkIntegrity(frame)
    frame = frame or GetNativeBuffBar()
    if not frame then return false end
    local state = self._states[frame]
    if not state or not state.hidden or state.restoring or state.parkQueued then return false end
    if frame.SetAlpha then frame:SetAlpha(0) end
    if IsParked(frame) then return true end
    return self:Suppress(frame)
end

local eventFrame
if CreateFrame then
    eventFrame = CreateFrame("Frame")
    eventFrame:RegisterEvent("ADDON_LOADED")
    eventFrame:RegisterEvent("DISPLAY_SIZE_CHANGED")
    eventFrame:RegisterEvent("EDIT_MODE_LAYOUTS_UPDATED")
    eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
    eventFrame:RegisterEvent("UI_SCALE_CHANGED")
    eventFrame:SetScript("OnEvent", function(_, event, arg1)
        if event == "PLAYER_REGEN_ENABLED" then
            Suppressor:FlushPendingRestore()
        elseif event == "COOLDOWN_VIEWER_DATA_LOADED" then
            Suppressor:SchedulePendingSuppressFlush()
            return
        elseif event == "ADDON_LOADED" then
            local viewerAddon = ns.CDMCooldownViewerAddon
            local isViewerAddon = viewerAddon and viewerAddon.IsViewerAddon
                and viewerAddon.IsViewerAddon(arg1)
            if not isViewerAddon and arg1 ~= "Blizzard_CooldownViewer" then return end
            Suppressor:SchedulePendingSuppressFlush()
            return
        end
        Suppressor:CheckParkIntegrity()
    end)
end

function Suppressor:_EnsureDataRetry()
    if self._dataRetryRegistered then return end
    self._dataRetryRegistered = true
    if eventFrame then
        eventFrame:RegisterEvent("COOLDOWN_VIEWER_DATA_LOADED")
    end
end
