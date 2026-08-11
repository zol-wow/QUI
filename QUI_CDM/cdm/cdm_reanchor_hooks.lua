local _, ns = ...

local CDMReanchorHooks = {}
ns.CDMReanchorHooks = CDMReanchorHooks

local _securecall = securecallfunction or function(fn, ...) return fn(...) end

local MIXIN_GLOBAL_BY_KEY = {
    buff = "CooldownViewerBuffIconItemMixin",
    trackedBar = "CooldownViewerBuffBarItemMixin",
}

local function GetDefaultMixinForKey(key)
    local globalName = MIXIN_GLOBAL_BY_KEY[key]
    return globalName and _G[globalName] or nil
end

local InstanceMT = { __index = CDMReanchorHooks }

function CDMReanchorHooks.CreateActiveStateScheduler(createFrame)
    createFrame = createFrame or CreateFrame
    local driver
    local pending = {}
    local ticks = 0
    local age = 0
    local armed = false
    return function(fn)
        pending[#pending + 1] = fn
        ticks = 0
        if not armed then
            armed = true
            age = 0
        end
        if not driver then
            driver = createFrame("Frame")
            driver:Hide()
            driver:SetScript("OnUpdate", function(self)
                ticks = ticks + 1
                age = age + 1
                if ticks < 2 and age < 8 then return end
                self:Hide()
                armed = false
                local fns = pending
                pending = {}
                for i = 1, #fns do
                    fns[i]()
                end
            end)
        end
        driver:Show()
    end
end

function CDMReanchorHooks.New(deps)
    deps = deps or {}
    local self = {
        _deps = deps,
        _refresh = deps.refresh,
        _refreshMany = deps.refreshMany,
        _keys = deps.keys or { "essential", "utility", "buff" },
        _dirty = {},
        _scheduled = false,
        _activeScheduled = false,
        _hooked = setmetatable({}, { __mode = "k" }),
        _hookedPools = setmetatable({}, { __mode = "k" }),
        _hookedFrames = setmetatable({}, { __mode = "k" }),
        _hookedMixins = setmetatable({}, { __mode = "k" }),
        _indexSubscribed = false,
        _blank = deps.blank,
        _isInitWindow = deps.isInitWindow,
        _isInitialReanchorDone = deps.isInitialReanchorDone,
        _getMixinForKey = deps.getMixinForKey,
        _blankKeys = deps.blankKeys or {},
        _immediateRefreshLayoutKeys = deps.immediateRefreshLayoutKeys or deps.immediateKeys or {},
        _immediateAcquireKeys = deps.immediateAcquireKeys or {},
        _isClaimed = deps.isClaimed,
        _installGuard = deps.installGuard,
        _installGuardKeys = deps.installGuardKeys or {},
    }
    return setmetatable(self, InstanceMT)
end

function CDMReanchorHooks:MaybeBlankOnAcquire(key, frame)
    if not (self._blank and frame) then return end
    if not self._blankKeys[key] then return end
    if self._isInitWindow and self._isInitWindow(key, frame) then return end
    if self._isInitialReanchorDone and self._isInitialReanchorDone(key, frame) ~= true then return end
    if self._isClaimed and self._isClaimed(frame) then return end
    self._blank(frame, key)
end

function CDMReanchorHooks:MaybeInstallAnchorGuard(key, frame)
    local install = self._installGuard
    if not (install and frame) then return end
    if not self._installGuardKeys[key] then return end
    if self._isInitialReanchorDone and self._isInitialReanchorDone(key, frame) ~= true then return end
    install(frame, key)
end

function CDMReanchorHooks:MarkDirty(key)
    self._dirty[key] = true
    self:_Schedule()
end

function CDMReanchorHooks:MarkImmediate(key)
    self._dirty[key] = nil
    if self._refreshMany then
        self._refreshMany({ key })
    elseif self._refresh then
        self._refresh(key)
    end
end

function CDMReanchorHooks:MarkAcquire(key)
    if self._immediateAcquireKeys[key] then
        self:MarkImmediate(key)
    else
        self:MarkDirty(key)
    end
end

function CDMReanchorHooks:MarkActiveStateDirty(key)
    local reapply = self._deps.reapplyPositions
    if reapply then reapply(key) end

    self._dirty[key] = true
    if self._activeScheduled then return end
    self._activeScheduled = true
    local schedule = self._deps.scheduleActiveState or self._deps.schedule
    if schedule then
        local hooks = self
        schedule(function()
            hooks._activeScheduled = false
            hooks:Flush()
        end)
    else
        self._activeScheduled = false
    end
end

function CDMReanchorHooks:MarkAllDirty()
    for i = 1, #self._keys do
        self._dirty[self._keys[i]] = true
    end
    self:_Schedule()
end

function CDMReanchorHooks:_Schedule()
    if self._scheduled then return end
    self._scheduled = true
    local schedule = self._deps.schedule
    if schedule then
        local hooks = self
        schedule(function() hooks:Flush() end)
    else
        self._scheduled = false
    end
end

function CDMReanchorHooks:Flush()
    self._scheduled = false
    local dirty = self._dirty
    if self._refreshMany then
        local keys, emitted = {}, {}
        for i = 1, #self._keys do
            local key = self._keys[i]
            if dirty[key] then
                dirty[key] = nil
                emitted[key] = true
                keys[#keys + 1] = key
            end
        end
        for key in pairs(dirty) do
            dirty[key] = nil
            if not emitted[key] then keys[#keys + 1] = key end
        end
        if #keys > 0 then self._refreshMany(keys) end
        return
    end
    for key in pairs(dirty) do
        dirty[key] = nil
        if self._refresh then self._refresh(key) end
    end
end

function CDMReanchorHooks:GetMixinForKey(key)
    if self._getMixinForKey then
        return self._getMixinForKey(key)
    end
    return GetDefaultMixinForKey(key)
end

local function EnumerateViewerFrames(viewer, callback)
    if not (viewer and callback) then return end
    if viewer.GetItemFrames then
        local frames = viewer:GetItemFrames()
        if type(frames) == "table" then
            for i = 1, #frames do
                callback(frames[i])
            end
        end
    end
    local pool = viewer.itemFramePool
    if pool and pool.EnumerateActive then
        for frame in pool:EnumerateActive() do
            callback(frame)
        end
    end
end

function CDMReanchorHooks:InstallGlobalMixinHooks()
    local hooksec = self._deps.hooksecurefunc or hooksecurefunc
    if not hooksec then return false end

    local installed = false
    for i = 1, #self._keys do
        local key = self._keys[i]
        local mixin = self:GetMixinForKey(key)
        if mixin and not self._hookedMixins[mixin] and mixin.OnCooldownIDSet then
            self._hookedMixins[mixin] = true
            local hooks = self
            local function markCooldownIDSet()
                hooks:MarkDirty(key)
            end
            hooksec(mixin, "OnCooldownIDSet", function(...) _securecall(markCooldownIDSet, ...) end)
            installed = true
        end
    end
    return installed
end

function CDMReanchorHooks:_InstallFrameHooks(frame, key)
    if not frame then return end
    self:MaybeInstallAnchorGuard(key, frame)
    if self._hookedFrames[frame] then return end
    local hooksec = self._deps.hooksecurefunc or hooksecurefunc
    if not hooksec then return end

    local installed = false
    local hooks = self
    local function markDirty() hooks:MarkDirty(key) end
    local function markActiveStateDirty() hooks:MarkActiveStateDirty(key) end
    if frame.OnActiveStateChanged then
        hooksec(frame, "OnActiveStateChanged", function(...) _securecall(markActiveStateDirty, ...) end)
        installed = true
    end
    if frame.OnCooldownIDSet then
        hooksec(frame, "OnCooldownIDSet", function(...) _securecall(markDirty, ...) end)
        installed = true
    end
    if frame.HookScript then
        frame:HookScript("OnShow", function(...) _securecall(markActiveStateDirty, ...) end)
        installed = true
    end
    if installed then
        self._hookedFrames[frame] = true
    end
end

function CDMReanchorHooks:InstallViewerHooks(getViewer)
    local hooksec = self._deps.hooksecurefunc or hooksecurefunc
    if not (hooksec and getViewer) then return end
    for i = 1, #self._keys do
        local key = self._keys[i]
        local viewer = getViewer(key)
        if viewer and not self._hooked[viewer] and viewer.RefreshLayout then
            self._hooked[viewer] = true
            local hooks = self
            local function markDirty() hooks:MarkDirty(key) end
            local function markRefreshLayout()
                if hooks._immediateRefreshLayoutKeys[key] then
                    hooks:MarkImmediate(key)
                else
                    hooks:MarkDirty(key)
                end
            end
            hooksec(viewer, "RefreshLayout", function(...) _securecall(markRefreshLayout, ...) end)
            if viewer.OnAcquireItemFrame then
                local function onAcquire(_, itemFrame)
                    hooks:_InstallFrameHooks(itemFrame, key)
                    hooks:MaybeBlankOnAcquire(key, itemFrame)
                    hooks:MarkAcquire(key)
                end
                hooksec(viewer, "OnAcquireItemFrame", function(...) _securecall(onAcquire, ...) end)
            end
            if viewer.HookScript then
                viewer:HookScript("OnShow", function(...) _securecall(markDirty, ...) end)
                viewer:HookScript("OnHide", function(...) _securecall(markDirty, ...) end)
            end
        end

        if viewer then
            local pool = viewer.itemFramePool
            if pool and pool.Acquire and not self._hookedPools[pool] then
                self._hookedPools[pool] = true
                local hooks = self
                local function onPoolAcquire()
                    EnumerateViewerFrames(viewer, function(frame)
                        hooks:_InstallFrameHooks(frame, key)
                    end)
                    hooks:MarkAcquire(key)
                end
                hooksec(pool, "Acquire", function(...) _securecall(onPoolAcquire, ...) end)
            end
            EnumerateViewerFrames(viewer, function(frame)
                self:_InstallFrameHooks(frame, key)
            end)
        end
    end
end

function CDMReanchorHooks:_GlueViewer(entry)
    local viewer = entry.viewer
    local getContainer = self._glueGetContainer
    local canWrite = self._glueCanWrite
    local container = getContainer and getContainer(entry.key) or nil
    if not (viewer and container) then return false end
    if canWrite and not canWrite() then return false end
    viewer:ClearAllPoints()
    viewer:SetPoint("TOPLEFT", container, "TOPLEFT", 0, 0)
    viewer:SetPoint("BOTTOMRIGHT", container, "BOTTOMRIGHT", 0, 0)
    return true
end

function CDMReanchorHooks:InstallViewerGlue(getViewer, getContainer, glueKeys, canWrite)
    local hooksec = self._deps.hooksecurefunc or hooksecurefunc
    if not (hooksec and getViewer and getContainer) then return end
    self._glueGetContainer = getContainer
    self._glueCanWrite = canWrite
    self._gluedViewers = self._gluedViewers or setmetatable({}, { __mode = "k" })
    self._glueEntries = self._glueEntries or {}
    glueKeys = glueKeys or {}
    for i = 1, #self._keys do
        local key = self._keys[i]
        local viewer = glueKeys[key] and getViewer(key) or nil
        if viewer and not self._gluedViewers[viewer] then
            self._gluedViewers[viewer] = true
            local entry = { viewer = viewer, key = key, applied = false }
            self._glueEntries[#self._glueEntries + 1] = entry
            local hooks = self
            local function reglue(_, _point, relativeTo)
                local container = hooks._glueGetContainer
                    and hooks._glueGetContainer(entry.key) or nil
                if not container or relativeTo == container then return end
                entry.applied = hooks:_GlueViewer(entry)
            end
            hooksec(viewer, "SetPoint", function(...) _securecall(reglue, ...) end)
            entry.applied = self:_GlueViewer(entry)
        end
    end
    for i = 1, #self._glueEntries do
        local entry = self._glueEntries[i]
        if not entry.applied then
            entry.applied = self:_GlueViewer(entry)
        end
    end
end

function CDMReanchorHooks:ReassertViewerGlue()
    local entries = self._glueEntries
    if not entries then return end
    for i = 1, #entries do
        entries[i].applied = self:_GlueViewer(entries[i])
    end
end

function CDMReanchorHooks:InstallIndexSubscription(index)
    if self._indexSubscribed then return end
    if not (index and index.Subscribe) then return end
    local hooks = self
    index.Subscribe("reanchor", function()
        hooks:MarkAllDirty()
    end, 50)
    self._indexSubscribed = true
end

function CDMReanchorHooks:OnEvent()
    self:MarkAllDirty()
end

local CDMReanchorProcGlow = {}
ns.CDMReanchorProcGlow = CDMReanchorProcGlow

local ProcGlowMT = { __index = CDMReanchorProcGlow }

function CDMReanchorProcGlow.New(deps)
    deps = deps or {}
    local self = {
        _getEntryForFrame = deps.getEntryForFrame,
        _ensureOverlay    = deps.ensureOverlay,
        _resolveGlow      = deps.resolveGlow,
        _startGlow        = deps.startGlow,
        _stopGlow         = deps.stopGlow,
        _hooksecurefunc   = deps.hooksecurefunc or hooksecurefunc,
        _securecall       = deps.securecall or _securecall,
        _active           = setmetatable({}, { __mode = "k" }),
        _installed        = false,
    }
    return setmetatable(self, ProcGlowMT)
end

local function ProcGlowLatchKey(entry)
    if not entry then return nil end
    return entry.spellID or entry.id or entry
end

function CDMReanchorProcGlow:_StopFor(frame)
    self._active[frame] = nil
    if not (self._ensureOverlay and self._stopGlow) then return end
    local overlay = self._ensureOverlay(frame)
    if overlay then self._stopGlow(overlay) end
end

function CDMReanchorProcGlow:_OnShowAlert(frame)
    if not frame then return end
    local entry = self._getEntryForFrame and self._getEntryForFrame(frame) or nil
    if entry == nil then return end
    local alert = frame.SpellActivationAlert
    if alert then
        if alert.SetAlpha then alert:SetAlpha(0) end
        if alert.Hide then alert:Hide() end
    end
    if not (self._ensureOverlay and self._resolveGlow and self._startGlow) then return end
    local viewerSettings = self._resolveGlow(entry)
    if not viewerSettings then
        if self._active[frame] ~= nil then self:_StopFor(frame) end
        return
    end
    local key = ProcGlowLatchKey(entry)
    if self._active[frame] == key then return end
    if self._active[frame] ~= nil then self:_StopFor(frame) end
    local overlay = self._ensureOverlay(frame)
    if overlay then
        self._startGlow(overlay, viewerSettings)
        self._active[frame] = key
    end
end

function CDMReanchorProcGlow:_OnHideAlert(frame)
    if not frame then return end
    local entry = self._getEntryForFrame and self._getEntryForFrame(frame) or nil
    if entry == nil then return end
    if self._active[frame] == nil then return end
    self:_StopFor(frame)
end

function CDMReanchorProcGlow:OnClaim(frame, entry)
    if not frame then return end
    local current = self._active[frame]
    if current ~= nil and current ~= ProcGlowLatchKey(entry) then
        self:_StopFor(frame)
    end
end

function CDMReanchorProcGlow:Install(manager)
    if self._installed then return false end
    local hooksec = self._hooksecurefunc
    if not (manager and hooksec) then return false end
    if not (manager.ShowAlert and manager.HideAlert) then return false end
    self._installed = true
    local me = self
    local function onShow(_, frame) me:_OnShowAlert(frame) end
    local function onHide(_, frame) me:_OnHideAlert(frame) end
    hooksec(manager, "ShowAlert", function(...) me._securecall(onShow, ...) end)
    hooksec(manager, "HideAlert", function(...) me._securecall(onHide, ...) end)
    return true
end

local CDMReanchorPandemic = {}
ns.CDMReanchorPandemic = CDMReanchorPandemic

local PandemicMT = { __index = CDMReanchorPandemic }

function CDMReanchorPandemic.New(deps)
    deps = deps or {}
    local self = {
        _getEntryForFrame  = deps.getEntryForFrame,
        _ensureOverlay     = deps.ensureOverlay,
        _isPandemicEnabled = deps.isPandemicEnabled,
        _startPandemic     = deps.startPandemic,
        _stopPandemic      = deps.stopPandemic,
        _hooksecurefunc    = deps.hooksecurefunc or hooksecurefunc,
        _securecall        = deps.securecall or _securecall,
        _hooked            = setmetatable({}, { __mode = "k" }),
        _active            = setmetatable({}, { __mode = "k" }),
    }
    return setmetatable(self, PandemicMT)
end

local function PandemicLatchKey(entry)
    if not entry then return nil end
    return entry.spellID or entry.id or entry
end

function CDMReanchorPandemic:_StopFor(frame)
    self._active[frame] = nil
    if not (self._ensureOverlay and self._stopPandemic) then return end
    local overlay = self._ensureOverlay(frame)
    if overlay then self._stopPandemic(overlay) end
end

function CDMReanchorPandemic:_OnShowPandemic(frame)
    if not frame then return end
    local entry = self._getEntryForFrame and self._getEntryForFrame(frame) or nil
    if entry == nil then return end
    local nativeIcon = frame.PandemicIcon
    if nativeIcon then
        if nativeIcon.SetAlpha then nativeIcon:SetAlpha(0) end
        if nativeIcon.Hide then nativeIcon:Hide() end
    end
    local enabled = self._isPandemicEnabled and self._isPandemicEnabled(entry)
    if not enabled then
        if self._active[frame] ~= nil then self:_StopFor(frame) end
        return
    end
    if self._active[frame] == PandemicLatchKey(entry) then return end
    if not (self._ensureOverlay and self._startPandemic) then return end
    local overlay = self._ensureOverlay(frame)
    if overlay then
        self._startPandemic(overlay)
        self._active[frame] = PandemicLatchKey(entry)
    end
end

function CDMReanchorPandemic:_OnHidePandemic(frame)
    if not frame then return end
    if self._active[frame] == nil then return end
    self:_StopFor(frame)
end

function CDMReanchorPandemic:OnClaim(frame, entry)
    if not frame then return end
    local current = self._active[frame]
    if current ~= nil and current ~= PandemicLatchKey(entry) then
        self:_StopFor(frame)
    end
end

function CDMReanchorPandemic:Hook(frame)
    if not frame or self._hooked[frame] then return end
    local hooksec = self._hooksecurefunc
    if not hooksec then return end
    if not (frame.ShowPandemicStateFrame and frame.HidePandemicStateFrame) then return end
    self._hooked[frame] = true
    local me = self
    local function showWork(f) me:_OnShowPandemic(f) end
    local function hideWork(f) me:_OnHidePandemic(f) end
    hooksec(frame, "ShowPandemicStateFrame", function(...) me._securecall(showWork, ...) end)
    hooksec(frame, "HidePandemicStateFrame", function(...) me._securecall(hideWork, ...) end)
end
