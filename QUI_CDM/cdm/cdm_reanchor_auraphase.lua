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
        _keyByFrame = setmetatable({}, { __mode = "k" }),
    }, InstanceMT)
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

function CDMReanchorAuraPhase:OnNativeAuraDisplayTime(frame, show)
    if _issecretvalue and _issecretvalue(show) then return end
    local request = self._deps.requestAuraPhaseRefresh
    if request then
        ns.SafeCall("bulkhead", request, frame, self._keyByFrame[frame], show == true)
    end
end

function CDMReanchorAuraPhase:Hook(frame, containerKey)
    if not frame then return end
    if containerKey ~= nil then self._keyByFrame[frame] = containerKey end
    local hooksec = self._deps.hooksecurefunc or hooksecurefunc
    local securecall = self._deps.securecall or function(fn, ...) return fn(...) end
    local this = self

    local cd = frame.GetCooldownFrame and frame:GetCooldownFrame()
    if cd and type(cd.SetUseAuraDisplayTime) == "function"
        and self._deps.requestAuraPhaseRefresh then
        self._nativeAuraDisplayHooked = self._nativeAuraDisplayHooked
            or setmetatable({}, { __mode = "k" })
        if not self._nativeAuraDisplayHooked[cd] then
            self._nativeAuraDisplayHooked[cd] = true
            local function auraDisplayWork(show)
                this:OnNativeAuraDisplayTime(frame, show)
            end
            hooksec(cd, "SetUseAuraDisplayTime", function(_, show)
                securecall(auraDisplayWork, show)
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

function CDMReanchorAuraPhase:Reassert(frame)
    if not frame then return end
    local securecall = self._deps.securecall or function(fn, ...) return fn(...) end
    local cd = frame.GetCooldownFrame and frame:GetCooldownFrame()
    if not cd then return end
    local this = self
    securecall(function()
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
