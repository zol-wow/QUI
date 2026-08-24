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
        _nativeAuraDisplayState = setmetatable({}, { __mode = "k" }),
        _keyByFrame = setmetatable({}, { __mode = "k" }),
        _entryByFrame = setmetatable({}, { __mode = "k" }),
        _nativeClearHooked = setmetatable({}, { __mode = "k" }),
        _nativeDesaturatedHooked = setmetatable({}, { __mode = "k" }),
        _nativeDesaturationHooked = setmetatable({}, { __mode = "k" }),
        _nativeRepairReentry = setmetatable({}, { __mode = "k" }),
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
    if not cd then return end
    self:ObserveNativeAuraDisplayTime(frame, cd)
    if self._edgeReentry[cd] then return end
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

function CDMReanchorAuraPhase:OnNativeAuraDisplayTime(frame, show, cd)
    if _issecretvalue and _issecretvalue(show) then return end
    cd = cd or (frame and frame.GetCooldownFrame and frame:GetCooldownFrame())
    self:ObserveNativeAuraDisplayTime(frame, cd, show)
end

function CDMReanchorAuraPhase:OnNativeCooldownPush(frame, cd)
    local deps = self._deps
    if not (deps.requestAuraPhaseRefresh and deps.isAuraPhaseEnabled
        and deps.isAuraPhaseEnabled() == false) then
        return
    end
    local show = frame and frame.cooldownUseAuraDisplayTime
    if (_issecretvalue and _issecretvalue(show)) or show ~= true then return end
    ns.SafeCall("bulkhead", deps.requestAuraPhaseRefresh, frame, self._keyByFrame[frame], true)
end

function CDMReanchorAuraPhase:IsStaleLinkedAura(frame)
    local info = frame and frame.cooldownInfo
    local linkedSpellID = info and info.linkedSpellID
    local auraInstanceID = frame and frame.auraInstanceID
    local wasSetFromAura = frame and frame.wasSetFromAura
    if (_issecretvalue and _issecretvalue(linkedSpellID))
        or (_issecretvalue and _issecretvalue(auraInstanceID))
        or (_issecretvalue and _issecretvalue(wasSetFromAura)) then
        return false
    end
    return linkedSpellID ~= nil and auraInstanceID == nil and wasSetFromAura ~= true
end

function CDMReanchorAuraPhase:IsNativeCooldownRepairFrame(frame, containerKey)
    local deps = self._deps
    if not deps.isNativeCooldownRepairFrame then return false end
    local ok, eligible = ns.SafeCall("bulkhead", deps.isNativeCooldownRepairFrame,
        frame, containerKey, self._entryByFrame[frame])
    return ok and eligible == true
end

function CDMReanchorAuraPhase:OnNativeRepairDriver(frame, cd, reason)
    if not cd or self._nativeRepairReentry[cd] then return end
    local deps = self._deps
    if not deps.repairStaleLinkedAura
        or not self:IsNativeCooldownRepairFrame(frame, self._keyByFrame[frame])
        or not self:IsStaleLinkedAura(frame) then
        return
    end
    self._nativeRepairReentry[cd] = true
    ns.SafeCall("bulkhead", deps.repairStaleLinkedAura, frame, cd,
        self._entryByFrame[frame], reason)
    self._nativeRepairReentry[cd] = nil
end

function CDMReanchorAuraPhase:ObserveNativeAuraDisplayTime(frame, cd, show)
    if not cd then return end
    local state = show
    if state == nil then
        local ok, value = ns.SafeCall("bulkhead", function()
            return frame and frame.cooldownUseAuraDisplayTime
        end)
        if not ok or (_issecretvalue and _issecretvalue(value)) then return end
        state = value
    elseif _issecretvalue and _issecretvalue(state) then
        return
    end
    state = state == true
    local previous = self._nativeAuraDisplayState[cd]
    self._nativeAuraDisplayState[cd] = state
    if previous == nil or previous == state then return end
    local request = self._deps.requestAuraPhaseRefresh
    if request then
        ns.SafeCall("bulkhead", request, frame, self._keyByFrame[frame], state)
    end
end

function CDMReanchorAuraPhase:Hook(frame, containerKey, entry)
    if not frame then return end
    if containerKey ~= nil then self._keyByFrame[frame] = containerKey end
    if entry ~= nil then self._entryByFrame[frame] = entry end
    local hooksec = self._deps.hooksecurefunc or hooksecurefunc
    local securecall = self._deps.securecall or function(fn, ...) return fn(...) end
    local this = self

    local cd = frame.GetCooldownFrame and frame:GetCooldownFrame()
    if cd and self._deps.requestAuraPhaseRefresh then
        self._nativeAuraDisplayHooked = self._nativeAuraDisplayHooked
            or setmetatable({}, { __mode = "k" })
        self:ObserveNativeAuraDisplayTime(frame, cd)
        if type(cd.SetUseAuraDisplayTime) == "function" and not self._nativeAuraDisplayHooked[cd] then
            self._nativeAuraDisplayHooked[cd] = true
            local function auraDisplayWork(show)
                this:OnNativeAuraDisplayTime(frame, show, cd)
            end
            hooksec(cd, "SetUseAuraDisplayTime", function(_, show)
                securecall(auraDisplayWork, show)
            end)
        end
        self._nativeCooldownPushHooked = self._nativeCooldownPushHooked
            or setmetatable({}, { __mode = "k" })
        local function cooldownPushWork()
            this:OnNativeCooldownPush(frame, cd)
        end
        if type(cd.SetCooldown) == "function" and not self._nativeCooldownPushHooked[cd] then
            self._nativeCooldownPushHooked[cd] = true
            hooksec(cd, "SetCooldown", function()
                securecall(cooldownPushWork)
            end)
        end
        if type(cd.SetCooldownFromDurationObject) == "function"
            and not self._nativeCooldownDurationPushHooked then
            self._nativeCooldownDurationPushHooked = setmetatable({}, { __mode = "k" })
        end
        if type(cd.SetCooldownFromDurationObject) == "function"
            and not self._nativeCooldownDurationPushHooked[cd] then
            self._nativeCooldownDurationPushHooked[cd] = true
            hooksec(cd, "SetCooldownFromDurationObject", function()
                securecall(cooldownPushWork)
            end)
        end
    end
    if cd and self._deps.repairStaleLinkedAura
        and self:IsNativeCooldownRepairFrame(frame, containerKey) then
        if type(cd.Clear) == "function" and not self._nativeClearHooked[cd] then
            self._nativeClearHooked[cd] = true
            local function clearWork()
                this:OnNativeRepairDriver(frame, cd, "clear")
            end
            hooksec(cd, "Clear", function()
                securecall(clearWork)
            end)
        end
        local texture = frame.Icon
        if texture and type(texture.SetDesaturated) ~= "function" then
            texture = texture.Icon
        end
        if texture and type(texture.SetDesaturated) == "function"
            and not self._nativeDesaturatedHooked[frame] then
            self._nativeDesaturatedHooked[frame] = true
            local function desaturatedWork()
                this:OnNativeRepairDriver(frame, cd, "desaturated")
            end
            hooksec(texture, "SetDesaturated", function()
                securecall(desaturatedWork)
            end)
        end
        if texture and type(texture.SetDesaturation) == "function"
            and not self._nativeDesaturationHooked[frame] then
            self._nativeDesaturationHooked[frame] = true
            local function desaturationWork()
                this:OnNativeRepairDriver(frame, cd, "desaturation")
            end
            hooksec(texture, "SetDesaturation", function()
                securecall(desaturationWork)
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
