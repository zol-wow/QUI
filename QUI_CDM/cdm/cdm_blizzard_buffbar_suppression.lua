local _, ns = ...
local unpackValue = table.unpack or unpack

local Suppressor = {
    _states = setmetatable({}, { __mode = "k" }),
    _pendingSuppress = setmetatable({}, { __mode = "k" }),
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

local function ParkOffscreen(frame)
    if not (frame and frame.ClearAllPoints and frame.SetPoint and _G.UIParent) then
        return false
    end
    frame:ClearAllPoints()
    frame:SetPoint("TOPLEFT", _G.UIParent, "BOTTOMLEFT", 0, -10000)
    return true
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
    if not frame then return false end
    if not IsCooldownViewerReady() then
        self:QueueSuppress(frame)
        return false
    end

    local state = self._states[frame]
    if not state then
        state = {}
        self._states[frame] = state
    end
    if not state.originalPoints and not state.parked then
        state.originalPoints = CapturePoints(frame)
    end
    state.hidden = true

    if frame.SetAlpha then frame:SetAlpha(0) end

    if not InCombat() then
        DisableMouse(frame)
        state.parked = ParkOffscreen(frame)
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
    end
    self:_EnsureDataRetry()
end

function Suppressor:Restore(frame)
    frame = frame or GetNativeBuffBar()
    if not frame then return false end
    if not IsCooldownViewerReady() then return false end

    local state = self._states[frame]
    if frame.SetAlpha then frame:SetAlpha(1) end

    if state and state.hidden and not InCombat() then
        if state.parked or state.parkPending then
            RestorePoints(frame, state.originalPoints)
        end
        state.parked = nil
        state.parkPending = nil
        state.hidden = false
    elseif state and InCombat() then
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
            if state.parked or state.parkPending then
                RestorePoints(frame, state.originalPoints)
            end
            state.parked = nil
            state.parkPending = nil
            state.hidden = false
        elseif state.hidden and state.parkPending then
            state.parked = ParkOffscreen(frame)
            state.parkPending = nil
        end
    end
end

function Suppressor:FlushPendingSuppress()
    if not IsCooldownViewerReady() then return end
    for frame in pairs(self._pendingSuppress) do
        self._pendingSuppress[frame] = nil
        self:Suppress(frame)
    end
end

local eventFrame
if CreateFrame then
    eventFrame = CreateFrame("Frame")
    eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
    eventFrame:SetScript("OnEvent", function(_, event)
        if event == "PLAYER_REGEN_ENABLED" then
            Suppressor:FlushPendingRestore()
        elseif event == "COOLDOWN_VIEWER_DATA_LOADED" then
            Suppressor:FlushPendingSuppress()
        end
    end)
end

function Suppressor:_EnsureDataRetry()
    if self._dataRetryRegistered then return end
    self._dataRetryRegistered = true
    if eventFrame then
        eventFrame:RegisterEvent("COOLDOWN_VIEWER_DATA_LOADED")
    end
end
