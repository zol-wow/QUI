local _, ns = ...

local _issecretvalue = issecretvalue or function() return false end

local CDMReanchorAuraPhase = {}
ns.CDMReanchorAuraPhase = CDMReanchorAuraPhase

local InstanceMT = { __index = CDMReanchorAuraPhase }

function CDMReanchorAuraPhase.New(deps)
    deps = deps or {}
    return setmetatable({
        _deps = deps,
        _swipeHooked = setmetatable({}, { __mode = "k" }),
        _reentry = setmetatable({}, { __mode = "k" }),
        _edgeHooked = setmetatable({}, { __mode = "k" }),
        _edgeReentry = setmetatable({}, { __mode = "k" }),
        _drawSwipeHooked = setmetatable({}, { __mode = "k" }),
        _drawSwipeReentry = setmetatable({}, { __mode = "k" }),
        _nativeRearmHooked = setmetatable({}, { __mode = "k" }),
        _nativeRearmReentry = setmetatable({}, { __mode = "k" }),
        _nativeAuraActive = setmetatable({}, { __mode = "k" }),
        _nativeAuraState = setmetatable({}, { __mode = "k" }),
        _keyByFrame = setmetatable({}, { __mode = "k" }),
        _entryByFrame = setmetatable({}, { __mode = "k" }),
    }, InstanceMT)
end

function CDMReanchorAuraPhase:OnNativeCooldownPush(frame, cd)
    if not cd or self._nativeRearmReentry[cd] then return end
    local rearm = self._deps.rearmNativeCooldown
    if not rearm then return end
    self._nativeRearmReentry[cd] = true
    ns.SafeCall("bulkhead", rearm, frame, cd, self._keyByFrame[frame],
        self._entryByFrame[frame], self._nativeAuraActive[cd] == true,
        self._nativeAuraState[cd])
    self._nativeRearmReentry[cd] = false
end

function CDMReanchorAuraPhase:OnNativeAuraDisplayTime(frame, cd, show)
    if _issecretvalue and _issecretvalue(show) then return end
    if self._nativeRearmReentry[cd] and show ~= true then return end
    self._nativeAuraActive[cd] = show == true
    self:OnNativeCooldownPush(frame, cd)
end

function CDMReanchorAuraPhase:OnNativeCooldownClear(cd)
    if self._nativeRearmReentry[cd] then return end
    self._nativeAuraActive[cd] = false
    local state = self._nativeAuraState[cd]
    if state then
        state.durationObject = nil
        state.clearWhenZero = nil
        state.hasCooldown = nil
        state.start = nil
        state.duration = nil
        state.modRate = nil
    end
end

function CDMReanchorAuraPhase:SeedNativeState(frame, cd)
    if not frame or not cd then return end
    if self._nativeAuraActive[cd] == nil then
        local active = frame.cooldownUseAuraDisplayTime
        if not (_issecretvalue and _issecretvalue(active)) then
            self._nativeAuraActive[cd] = active == true
        end
    end
    if self._nativeAuraState[cd] then return end
    local start = frame.cooldownStartTime
    local duration = frame.cooldownDuration
    local modRate = frame.cooldownModRate
    if (_issecretvalue and (_issecretvalue(start) or _issecretvalue(duration)
        or _issecretvalue(modRate))) then
        return
    end
    if type(start) == "number" and type(duration) == "number" then
        self._nativeAuraState[cd] = {
            hasCooldown = true,
            start = start,
            duration = duration,
            modRate = modRate,
        }
    end
end

function CDMReanchorAuraPhase:OnSwipeColor(frame, cd)
    if not cd or self._reentry[cd] then return end
    self._reentry[cd] = true
    local deps = self._deps
    if deps.reassertColor then ns.SafeCall("bulkhead", deps.reassertColor, frame, cd, self._keyByFrame[frame]) end
    self._reentry[cd] = false
end

function CDMReanchorAuraPhase:OnDrawEdge(frame, cd)
    if not cd or self._edgeReentry[cd] then return end
    self._edgeReentry[cd] = true
    local deps = self._deps
    if deps.reassertEdge then ns.SafeCall("bulkhead", deps.reassertEdge, frame, cd, self._keyByFrame[frame]) end
    self._edgeReentry[cd] = false
end

function CDMReanchorAuraPhase:OnDrawSwipe(frame, cd, show)
    if not cd or self._drawSwipeReentry[cd] then return end
    if _issecretvalue and _issecretvalue(show) then return end
    self._drawSwipeReentry[cd] = true
    local deps = self._deps
    if deps.reassertSwipe then
        ns.SafeCall("bulkhead", deps.reassertSwipe, frame, cd, self._keyByFrame[frame], show)
    end
    self._drawSwipeReentry[cd] = false
end

function CDMReanchorAuraPhase:Hook(frame, containerKey, entry)
    if not frame then return end
    if containerKey ~= nil then self._keyByFrame[frame] = containerKey end
    if entry ~= nil then self._entryByFrame[frame] = entry end
    local hooksec = self._deps.hooksecurefunc or hooksecurefunc
    local securecall = self._deps.securecall or function(fn, ...) return fn(...) end
    local this = self

    local cd = frame.GetCooldownFrame and frame:GetCooldownFrame()
    if cd and self._deps.rearmNativeCooldown and not self._nativeRearmHooked[cd] then
        self._nativeRearmHooked[cd] = true
        self:SeedNativeState(frame, cd)
        local nativeState = self._nativeAuraState[cd]
        if not nativeState then
            nativeState = {}
            self._nativeAuraState[cd] = nativeState
        end
        local function rearmWork() this:OnNativeCooldownPush(frame, cd) end
        local function auraDisplayWork(show) this:OnNativeAuraDisplayTime(frame, cd, show) end
        local function clearWork() this:OnNativeCooldownClear(cd) end
        if type(cd.SetCooldown) == "function" then
            hooksec(cd, "SetCooldown", function(_, start, duration, modRate)
                if not this._nativeRearmReentry[cd] then
                    nativeState.durationObject = nil
                    nativeState.clearWhenZero = nil
                    nativeState.hasCooldown = true
                    nativeState.start = start
                    nativeState.duration = duration
                    nativeState.modRate = modRate
                end
                securecall(rearmWork)
            end)
        end
        if type(cd.SetCooldownFromDurationObject) == "function" then
            hooksec(cd, "SetCooldownFromDurationObject", function(_, durationObject, clearWhenZero)
                if not this._nativeRearmReentry[cd] then
                    nativeState.durationObject = durationObject
                    nativeState.clearWhenZero = clearWhenZero
                    nativeState.hasCooldown = nil
                end
                securecall(rearmWork)
            end)
        end
        if type(cd.SetUseAuraDisplayTime) == "function" then
            hooksec(cd, "SetUseAuraDisplayTime", function(_, show)
                securecall(auraDisplayWork, show)
            end)
        end
        if type(cd.Clear) == "function" then
            hooksec(cd, "Clear", function()
                securecall(clearWork)
            end)
        end
    end
    if cd and type(cd.SetSwipeColor) == "function" and not self._swipeHooked[cd] then
        self._swipeHooked[cd] = true
        local function colorWork() this:OnSwipeColor(frame, cd) end
        hooksec(cd, "SetSwipeColor", function()
            securecall(colorWork)
        end)
    end
    if cd and type(cd.SetDrawEdge) == "function" and not self._edgeHooked[cd] then
        self._edgeHooked[cd] = true
        local function edgeWork() this:OnDrawEdge(frame, cd) end
        hooksec(cd, "SetDrawEdge", function()
            securecall(edgeWork)
        end)
    end
    if cd and type(cd.SetDrawSwipe) == "function" and not self._drawSwipeHooked[cd] then
        self._drawSwipeHooked[cd] = true
        local function swipeWork(show) this:OnDrawSwipe(frame, cd, show) end
        hooksec(cd, "SetDrawSwipe", function(_, show)
            securecall(swipeWork, show)
        end)
    end
end

function CDMReanchorAuraPhase:Reassert(frame, entry)
    if not frame then return end
    if entry ~= nil then self._entryByFrame[frame] = entry end
    local securecall = self._deps.securecall or function(fn, ...) return fn(...) end
    local cd = frame.GetCooldownFrame and frame:GetCooldownFrame()
    if not cd then return end
    local this = self
    securecall(function()
        this:OnNativeCooldownPush(frame, cd)
        this:OnSwipeColor(frame, cd)
        this:OnDrawEdge(frame, cd)
        if type(cd.GetDrawSwipe) == "function" then
            local ok, show = ns.SafeCallMethod("bulkhead", cd, "GetDrawSwipe")
            if ok and not (_issecretvalue and _issecretvalue(show)) then
                this:OnDrawSwipe(frame, cd, show)
            end
        end
    end)
end
