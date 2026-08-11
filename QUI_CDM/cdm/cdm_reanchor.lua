local _, ns = ...

local CDMReanchor = {}
ns.CDMReanchor = CDMReanchor

local _proxy = (CreateFrame and CreateFrame("Frame")) or {}
local RAW = {
    ClearAllPoints       = _proxy.ClearAllPoints or function() end,
    SetPoint             = _proxy.SetPoint or function() end,
    SetAlpha             = _proxy.SetAlpha or function() end,
    SetIgnoreParentAlpha = _proxy.SetIgnoreParentAlpha or function() end,
}

local _securecall = securecallfunction or function(callee, ...) return callee(...) end
local _issecretvalue = issecretvalue or function() return false end

local InstanceMT = { __index = CDMReanchor }

function CDMReanchor.New(deps)
    deps = deps or {}
    local self = {
        _deps = deps,
        _raw = deps.raw or RAW,
        _securecall = deps.securecall or _securecall,
        _hooksecurefunc = deps.hooksecurefunc or hooksecurefunc,
        _sinkAnchor = deps.sinkAnchor or UIParent,
        _frameData = setmetatable({}, { __mode = "k" }),
        _infoCache = {},
    }
    return setmetatable(self, InstanceMT)
end

function CDMReanchor:GetData(frame)
    local fd = self._frameData[frame]
    if not fd then
        fd = {}
        self._frameData[frame] = fd
    end
    return fd
end

function CDMReanchor:IsClaimed(frame)
    local fd = self._frameData[frame]
    return (fd ~= nil and fd.claimedBy ~= nil) or false
end

function CDMReanchor:OverlayRect(frame, relativeTo, tlRelPoint, tlX, tlY, brRelPoint, brX, brY)
    local fd = self:GetData(frame)
    fd.claimedBy = relativeTo
    fd.overlayAnchor = relativeTo
    fd.overlayRect = {
        relativeTo = relativeTo,
        tlRelPoint = tlRelPoint, tlX = tlX, tlY = tlY,
        brRelPoint = brRelPoint, brX = brX, brY = brY,
    }
    fd.sunk = nil
    local raw, sc = self._raw, self._securecall
    sc(raw.SetAlpha, frame, 1)
    sc(raw.ClearAllPoints, frame)
    sc(raw.SetPoint, frame, "TOPLEFT", relativeTo, tlRelPoint, tlX, tlY)
    sc(raw.SetPoint, frame, "BOTTOMRIGHT", relativeTo, brRelPoint, brX, brY)
end

function CDMReanchor:Overlay(frame, anchorIcon)
    return self:OverlayRect(frame, anchorIcon, "TOPLEFT", 0, 0, "BOTTOMRIGHT", 0, 0)
end

function CDMReanchor:Sink(frame)
    local fd = self:GetData(frame)
    fd.claimedBy = nil
    fd.overlayAnchor = nil
    fd.overlayRect = nil
    fd.sunk = true
    local raw, sc = self._raw, self._securecall
    sc(raw.SetAlpha, frame, 0)
    local cd = (frame.GetCooldownFrame and frame:GetCooldownFrame()) or frame.Cooldown
    if cd and cd.SetDrawSwipe then
        sc(cd.SetDrawSwipe, cd, false)
    end
end

function CDMReanchor:InstallAnchorGuard(frame)
    local fd = self:GetData(frame)
    if fd.guarded then return end
    fd.guarded = true
    local bridge = self
    local function reassert(f, _point, relativeTo)
        local d = bridge._frameData[f]
        if not d or not d.overlayAnchor then
            bridge._raw.SetAlpha(f, 0)
            return
        end
        local raw = bridge._raw
        local rect = d.overlayRect
        if rect then
            if relativeTo == rect.relativeTo then return end
            raw.ClearAllPoints(f)
            raw.SetPoint(f, "TOPLEFT", rect.relativeTo, rect.tlRelPoint, rect.tlX, rect.tlY)
            raw.SetPoint(f, "BOTTOMRIGHT", rect.relativeTo, rect.brRelPoint, rect.brX, rect.brY)
            return
        end
        if relativeTo == d.overlayAnchor then return end
        raw.ClearAllPoints(f)
        raw.SetPoint(f, "TOPLEFT", d.overlayAnchor, "TOPLEFT", 0, 0)
        raw.SetPoint(f, "BOTTOMRIGHT", d.overlayAnchor, "BOTTOMRIGHT", 0, 0)
    end
    self._hooksecurefunc(frame, "SetPoint", function(...)
        _securecall(reassert, ...)
    end)
end

function CDMReanchor:ResolveIdentity(frame)
    if self._deps.resolveIdentity then
        return self._deps.resolveIdentity(frame)
    end
    local getID = frame.GetCooldownID
    local cooldownID
    if getID then
        local ok, id = pcall(getID, frame)
        if ok then cooldownID = id end
    else
        cooldownID = frame.cooldownID
    end
    if _issecretvalue(cooldownID) then return nil end -- @secret-policy: reject-secret-ids
    if type(cooldownID) ~= "number" then return nil end

    local info = self._infoCache[cooldownID]
    if info == nil then
        if C_CooldownViewer and C_CooldownViewer.GetCooldownViewerCooldownInfo then
            local ok, resolved = ns.SafeCall("best-effort-style", C_CooldownViewer.GetCooldownViewerCooldownInfo, cooldownID)
            info = (ok and resolved) or false
        else
            info = false
        end
        self._infoCache[cooldownID] = info
    end
    if not info then return cooldownID, nil end
    return cooldownID, info.category
end

function CDMReanchor:GetFrameCooldownInfo(frame, cooldownID)
    if self._deps.getFrameCooldownInfo then
        return self._deps.getFrameCooldownInfo(frame, cooldownID)
    end
    if not frame then return nil end

    local getInfo = frame.GetCooldownInfo
    if getInfo then
        local ok, info = ns.SafeCall("best-effort-style", getInfo, frame)
        if ok and type(info) == "table" then
            return info
        end
    end

    if type(frame.cooldownInfo) == "table" then
        return frame.cooldownInfo
    end

    if type(cooldownID) ~= "number" or _issecretvalue(cooldownID) then
        cooldownID = self:ResolveIdentity(frame)
    end
    if type(cooldownID) ~= "number" or _issecretvalue(cooldownID) then
        return nil
    end

    local info = self._infoCache[cooldownID]
    if info == nil then
        if C_CooldownViewer and C_CooldownViewer.GetCooldownViewerCooldownInfo then
            local ok, resolved = ns.SafeCall("best-effort-style", C_CooldownViewer.GetCooldownViewerCooldownInfo, cooldownID)
            info = (ok and resolved) or false
        else
            info = false
        end
        self._infoCache[cooldownID] = info
    end
    return type(info) == "table" and info or nil
end

function CDMReanchor:EnumerateItems(viewer)
    if self._deps.enumerate then
        return self._deps.enumerate(viewer)
    end
    local out = {}
    if not viewer then return out end
    if viewer.GetItemFrames then
        local frames = viewer:GetItemFrames()
        if frames then
            for i = 1, #frames do out[i] = frames[i] end
        end
        return out
    end
    local pool = viewer.itemFramePool
    if pool and pool.EnumerateActive then
        for f in pool:EnumerateActive() do
            out[#out + 1] = f
        end
    end
    return out
end
