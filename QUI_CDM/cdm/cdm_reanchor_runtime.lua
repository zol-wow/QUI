local _, ns = ...

local CDMReanchorRuntime = {}
ns.CDMReanchorRuntime = CDMReanchorRuntime

local InstanceMT = { __index = CDMReanchorRuntime }
local BLIZZARD_CDM_ENTRY_SOURCE = "blizzardCDM"

local function IsBuffIconKey(containerKey)
    return containerKey == "buff" or containerKey == "buffIcon"
end

local function IsBlizzardCDMEntry(entry)
    return entry and entry.source == BLIZZARD_CDM_ENTRY_SOURCE
end

local function PlacementRect(placement)
    local w, h = placement.w, placement.h
    if w and h then return w, h end
    local rc = placement.rowConfig
    local size = rc and rc.size
    if not size then return nil, nil end
    local aspect = rc.aspectRatioCrop or 1
    if type(aspect) ~= "number" or aspect <= 0 then aspect = 1 end
    return size, size / aspect
end

-- Snap a CENTER-anchored rect to whole physical pixels via the injected
-- pixelSnapCenter (QUICore:PixelSnapCenter): rounding only the center
-- leaves the edges on half-pixels when the size rounds to an odd pixel
-- count, which renders the 1px border 2px wide on one side. Without a
-- snapper (or without a size), fall back to rounding the center.
local function SnapPlacementRect(deps, container, x, y, w, h)
    local snap = deps.pixelSnapCenter
    if snap and w and h then
        x, w = snap(x, w, container)
        y, h = snap(y, h, container)
        return x, y, w, h
    end
    if deps.pixelRound then
        return deps.pixelRound(x, container), deps.pixelRound(y, container), w, h
    end
    return x, y, w, h
end

local function ShouldMintFramelessOwned(entry, containerKey, displayMode, editing)
    if IsBuffIconKey(containerKey) then
        if IsBlizzardCDMEntry(entry) then return editing == true end

        if displayMode == "active" and not editing then return false end
        return true
    end
    if IsBlizzardCDMEntry(entry) then return false end
    return true
end

function CDMReanchorRuntime.New(deps)
    deps = deps or {}
    local self = {
        _deps = deps,
        _bridge = deps.bridge,
        _wiring = deps.wiring,
        _reanchoredByKey = {},
        _entryByFrame = setmetatable({}, { __mode = "k" }),
        _nativePlacementByFrame = setmetatable({}, { __mode = "k" }),
        _consumersByFrame = setmetatable({}, { __mode = "k" }),
        _placementsByKey = {},
        _mintedOwnedByKey = {},
        _lastDiagByKey = {},
        _diagSeqByKey = {},
    }
    return setmetatable(self, InstanceMT)
end

function CDMReanchorRuntime:_NextDiag(containerKey, diag)
    local seq = (self._diagSeqByKey[containerKey] or 0) + 1
    self._diagSeqByKey[containerKey] = seq
    diag.seq = seq
    if GetTime then diag.at = GetTime() end
    self._lastDiagByKey[containerKey] = diag
    return diag
end

function CDMReanchorRuntime:GetLastDiag(containerKey)
    return self._lastDiagByKey[containerKey]
end

function CDMReanchorRuntime:ReleaseOwnedIcons(containerKey)
    local minted = self._mintedOwnedByKey[containerKey]
    if not minted then return end
    local release = self._deps.releaseOwned
    if not release then
        self._mintedOwnedByKey[containerKey] = nil
        return
    end
    local kept
    for i = 1, #minted do
        local ok = release(minted[i], containerKey)
        if ok == false then
            kept = kept or {}
            kept[#kept + 1] = minted[i]
        end
    end
    self._mintedOwnedByKey[containerKey] = kept
end

function CDMReanchorRuntime:_ShouldDeferOwnedReleaseInCombat(containerKey)
    local canMutate = self._deps.canMutate
    if not canMutate or canMutate() then return false end
    local minted = self._mintedOwnedByKey[containerKey]
    if not minted then return false end
    for i = 1, #minted do
        local icon = minted[i]
        if icon and icon.clickButton ~= nil then return true end
    end
    return false
end

function CDMReanchorRuntime:QueuePendingCombatRefresh(containerKey)
    if not containerKey then return end
    self._pendingCombatRefresh = self._pendingCombatRefresh or {}
    self._pendingCombatRefresh[containerKey] = true
end

function CDMReanchorRuntime:DrainPendingCombatRefresh()
    local pending = self._pendingCombatRefresh
    if not pending then return end
    self._pendingCombatRefresh = nil
    local keys = {}
    for key in pairs(pending) do keys[#keys + 1] = key end
    if self.RefreshContainers then
        self:RefreshContainers(keys)
    else
        for i = 1, #keys do self:RefreshContainer(keys[i]) end
    end
end

function CDMReanchorRuntime:_TrackMintedOwned(containerKey, icon)
    local minted = self._mintedOwnedByKey[containerKey]
    if not minted then
        minted = {}
        self._mintedOwnedByKey[containerKey] = minted
    end
    minted[#minted + 1] = icon
end

function CDMReanchorRuntime:GetReanchoredFrames(containerKey)
    return self._reanchoredByKey[containerKey]
end

function CDMReanchorRuntime:GetEntryForFrame(frame)
    if frame == nil then return nil end
    return self._entryByFrame[frame]
end

function CDMReanchorRuntime:GetPlacementsForFrame(frame)
    if frame == nil then return nil end
    return self._consumersByFrame[frame]
end

function CDMReanchorRuntime:IsFrameClaimedByAnyContainer(frame)
    if frame == nil then return false end
    return self._entryByFrame[frame] ~= nil
end

function CDMReanchorRuntime:ClearContainerRegistry(containerKey)
    local previous = self._reanchoredByKey[containerKey]
    if previous then
        for i = 1, #previous do
            local frame = previous[i]
            local placement = self._nativePlacementByFrame[frame]
            if not placement or placement.containerKey == containerKey then
                self._entryByFrame[frame] = nil
                self._nativePlacementByFrame[frame] = nil
            end
        end
    end
    self._reanchoredByKey[containerKey] = {}
end

function CDMReanchorRuntime:AssembleEntries(containerKey, frameMap, settings, prepared, placementPlan)
    local deps, wiring = self._deps, self._wiring
    self:ReleaseOwnedIcons(containerKey)
    local curated = (prepared and prepared.curated)
        or ((deps.getCurated and deps.getCurated(containerKey)) or {})
    local matched, frameless, claimedFrames
    if prepared and prepared.matched then
        matched = prepared.matched
        frameless = prepared.frameless
        claimedFrames = {}
        local sourceClaims = prepared.claimedFrames or {}
        for frame, claimed in pairs(sourceClaims) do
            if claimed then claimedFrames[frame] = true end
        end
    else
        matched, frameless, claimedFrames = wiring:MatchCuratedToFrames(curated, frameMap, containerKey)
    end
    matched = matched or {}
    frameless = frameless or {}
    claimedFrames = claimedFrames or {}
    if containerKey == "trackedBar" then
        return {}, claimedFrames
    end

    local displayMode = (prepared and prepared.displayMode)
        or ((settings and settings.iconDisplayMode) or "always")
    if not (prepared and prepared.displayMode) and displayMode == "combat" then
        displayMode = (deps.inCombat and deps.inCombat()) and "always" or "active"
    end
    local editing = prepared and prepared.editing
    if editing == nil then editing = deps.isEditMode and deps.isEditMode() end
    local filterInactive = prepared and prepared.filterInactive
    if filterInactive == nil then
        filterInactive = (displayMode == "active") and (deps.frameIsActive ~= nil) and not editing
    end
    local assignmentByEntry = placementPlan and placementPlan.assignmentsByContainer
        and placementPlan.assignmentsByContainer[containerKey] or nil

    local entries = {}
    local matchedByEntry, framelessByEntry = {}, {}
    for i = 1, #matched do
        local m = matched[i]
        if m and m.entry then
            matchedByEntry[m.entry] = m
        end
    end
    for i = 1, #frameless do
        local e = frameless[i]
        if e then
            framelessByEntry[e] = true
        end
    end

    local diag = self:_NextDiag(containerKey, {
        displayMode = displayMode,
        filterInactive = filterInactive and true or false,
        editing = editing and true or false,
        curated = #curated,
        matched = 0, frameless = 0, additional = 0,
        nativeClaimed = 0, staleNative = 0, hiddenPreview = 0,
        mirrored = 0, unsupportedMirror = 0,
        fallbackLive = 0, minted = 0, mintFailed = 0,
    })

    for i = 1, #curated do
        local e = curated[i]
        local m = matchedByEntry[e]
        if m then
            diag.matched = diag.matched + 1
        elseif framelessByEntry[e] then
            diag.frameless = diag.frameless + 1
        end
        local nativeUsable = prepared and prepared.nativeUsableByEntry
            and prepared.nativeUsableByEntry[e]
        if nativeUsable == nil and m and filterInactive then
            nativeUsable = deps.frameIsActive(m.frame, containerKey, e) and true or false
        end
        local assignment = assignmentByEntry and assignmentByEntry[e] or nil
        if IsBuffIconKey(containerKey) and not IsBlizzardCDMEntry(e)
            and not e._isTotemInstance and deps.acquireAuraMirror
            and (not m or (filterInactive and nativeUsable == false)) then
            if m then
                diag.staleNative = diag.staleNative + 1
                claimedFrames[m.frame] = nil
            end
            local icon = deps.mintOwned and deps.mintOwned(e, containerKey) or nil
            if icon then
                local planner = deps.placementPlanner or ns.CDMPlacementPlanner
                local placementKey = assignment and assignment.placementKey
                    or (planner and planner.BuildPlacementKey(containerKey, i, e))
                    or (containerKey .. ":" .. tostring(i))
                local auraMirrorOptions = {
                    dynamic = displayMode == "active" and not editing, order = i, source = icon,
                }
                local auraMirror = not auraMirrorOptions.dynamic
                    and deps.acquireAuraMirror(e, containerKey, placementKey, auraMirrorOptions) or nil
                diag.minted = diag.minted + 1
                diag.mirrored = diag.mirrored + 1
                self:_TrackMintedOwned(containerKey, icon)
                entries[#entries + 1] = {
                    src = e, frame = icon, reanchored = false,
                    mirrorKind = "auraMirror", auraMirror = auraMirror,
                    auraMirrorOptions = auraMirrorOptions.dynamic and auraMirrorOptions or nil,
                    hideAuraBase = displayMode == "active" and not editing,
                    placementKey = placementKey, _assignedRow = e._assignedRow,
                }
            else
                diag.mintFailed = diag.mintFailed + 1
            end
        elseif m and filterInactive and nativeUsable == false then
            diag.staleNative = diag.staleNative + 1
            claimedFrames[m.frame] = nil
        elseif m and assignment and assignment.renderKind ~= "native" then
            claimedFrames[m.frame] = nil
            if assignment.renderKind == "unsupportedMirror" then
                diag.unsupportedMirror = diag.unsupportedMirror + 1
            else
                local icon = deps.mintOwned and deps.mintOwned(e, containerKey) or nil
                if icon then
                    icon._blizzCooldown = m.frame
                    diag.mirrored = diag.mirrored + 1
                    diag.minted = diag.minted + 1
                    self:_TrackMintedOwned(containerKey, icon)
                    local auraMirror
                    if assignment.renderKind == "auraMirror" and deps.acquireAuraMirror then
                        auraMirror = deps.acquireAuraMirror(
                            e, containerKey, assignment.placementKey)
                    end
                    entries[#entries + 1] = {
                        src = e, frame = icon, reanchored = false,
                        mirrorKind = assignment.renderKind,
                        auraMirror = auraMirror,
                        sourceFrame = m.frame,
                        placementKey = assignment.placementKey,
                        _assignedRow = e._assignedRow,
                    }
                else
                    diag.mintFailed = diag.mintFailed + 1
                end
            end
        elseif m and deps.shouldReplaceNativeAuraPhase
            and deps.shouldReplaceNativeAuraPhase(m.frame, e, containerKey) then
            claimedFrames[m.frame] = nil
            local nativePlacement = self._nativePlacementByFrame[m.frame]
            if not nativePlacement or nativePlacement.containerKey == containerKey then
                self._entryByFrame[m.frame] = nil
                self._nativePlacementByFrame[m.frame] = nil
                self._consumersByFrame[m.frame] = nil
            end
            if self._bridge and self._bridge.Sink then
                self._bridge:Sink(m.frame)
            end
            local icon = deps.mintOwned and deps.mintOwned(e, containerKey) or nil
            if icon then
                icon._blizzCooldown = m.frame
                diag.minted = diag.minted + 1
                self:_TrackMintedOwned(containerKey, icon)
                entries[#entries + 1] = {
                    src = e, frame = icon, reanchored = false,
                    _assignedRow = e._assignedRow,
                }
            else
                diag.mintFailed = diag.mintFailed + 1
            end
        elseif m then
            local hiddenPreview = editing and IsBuffIconKey(containerKey)
                and deps.frameIsActive ~= nil
                and deps.frameIsActive(m.frame, containerKey, e) == false
            if hiddenPreview then
                diag.hiddenPreview = diag.hiddenPreview + 1
                claimedFrames[m.frame] = nil
                local icon = deps.mintOwned and deps.mintOwned(e, containerKey) or nil
                if icon then
                    diag.minted = diag.minted + 1
                    self:_TrackMintedOwned(containerKey, icon)
                    entries[#entries + 1] = {
                        src = e, frame = icon, reanchored = false,
                        _assignedRow = e._assignedRow,
                    }
                else
                    diag.mintFailed = diag.mintFailed + 1
                end
            else
                diag.nativeClaimed = diag.nativeClaimed + 1
                entries[#entries + 1] = {
                    src = e, frame = m.frame, liveFrame = m.frame,
                    reanchored = true, directAnchor = true,
                    placementKey = assignment and assignment.placementKey or nil,
                    _assignedRow = e._assignedRow,
                }
            end
        elseif framelessByEntry[e] and ShouldMintFramelessOwned(e, containerKey, displayMode, editing) then
            local icon = deps.mintOwned and deps.mintOwned(e, containerKey) or nil
            if icon then
                diag.minted = diag.minted + 1
                self:_TrackMintedOwned(containerKey, icon)
                entries[#entries + 1] = {
                    src = e, frame = icon, reanchored = false,
                    _assignedRow = e._assignedRow,
                }
            else
                diag.mintFailed = diag.mintFailed + 1
            end
        end
    end

    local additional = (deps.getAdditional and deps.getAdditional(containerKey)) or {}
    for i = 1, #additional do
        local e = additional[i]
        diag.additional = diag.additional + 1
        local icon = deps.mintOwned and deps.mintOwned(e, containerKey) or nil
        if icon then
            diag.minted = diag.minted + 1
            self:_TrackMintedOwned(containerKey, icon)
            local auraMirror, auraMirrorOptions
            local nativeAura = IsBuffIconKey(containerKey) and not IsBlizzardCDMEntry(e)
                and not e._isTotemInstance and deps.acquireAuraMirror
            if nativeAura then
                auraMirrorOptions = {
                        dynamic = displayMode == "active" and not editing, order = #curated + i, source = icon,
                    }
                if not auraMirrorOptions.dynamic then
                    auraMirror = deps.acquireAuraMirror(e, containerKey,
                        containerKey .. ":additional:" .. tostring(i), auraMirrorOptions)
                end
            end
            entries[#entries + 1] = {
                src = e, frame = icon, reanchored = false,
                auraMirror = auraMirror,
                auraMirrorOptions = auraMirrorOptions and auraMirrorOptions.dynamic and auraMirrorOptions or nil,
                placementKey = nativeAura and (containerKey .. ":additional:" .. tostring(i)) or nil,
                hideAuraBase = nativeAura and displayMode == "active" and not editing,
                _assignedRow = e._assignedRow,
            }
        else
            diag.mintFailed = diag.mintFailed + 1
        end
    end

    diag.entriesOut = #entries
    return entries, claimedFrames
end

function CDMReanchorRuntime:PositionEntries(container, plan, containerKey)
    if not (plan and plan.placements) then return 0 end
    local deps, bridge = self._deps, self._bridge
    local n = 0
    local hasDynamic = false
    for index, placement in ipairs(plan.placements) do
        local wrapper = placement.icon
        local frame = wrapper and wrapper.frame
        if frame then
            local options = wrapper.auraMirrorOptions
            if options then
                options.order = index
                options.rowConfig = placement.rowConfig
                wrapper.auraMirror = deps.acquireAuraMirror(wrapper.src, containerKey,
                    wrapper.placementKey or (containerKey .. ":layout:" .. index), options)
            end
            local record = wrapper.auraMirror
            if record and record.dynamic and not record.reserved then hasDynamic = true end
            local x, y = placement.x, placement.y
            local w, h = PlacementRect(placement)
            x, y, w, h = SnapPlacementRect(deps, container, x, y, w, h)
            if wrapper.reanchored then
                local rc = placement.rowConfig
                local live = wrapper.liveFrame
                if live and w and h then
                    local tlX, tlY = x - w / 2, y + h / 2
                    local brX, brY = x + w / 2, y - h / 2
                    bridge:InstallAnchorGuard(live)
                    bridge:OverlayRect(live, container, "CENTER", tlX, tlY, "CENTER", brX, brY)
                    if deps.decorate then
                        deps.decorate(live, { _spellEntry = wrapper.src }, rc, containerKey)
                    end
                    if deps.ensureLiveTooltip then
                        deps.ensureLiveTooltip(live, wrapper.src)
                    end
                    if containerKey ~= "buff" and deps.positionClickSlot then
                        local clickSlot = deps.positionClickSlot(container, live, wrapper.src,
                            containerKey, x, y, w, h, rc)
                        if clickSlot and deps.updateClickOverlay then
                            deps.updateClickOverlay(clickSlot, wrapper.src, containerKey)
                        end
                    end
                    n = n + 1
                end
            elseif deps.positionOwned then
                local positionedByAuraMirror = false
                if wrapper.auraMirror and deps.positionAuraMirror then
                    positionedByAuraMirror = deps.positionAuraMirror(
                        wrapper.auraMirror, frame, container, x, y, w, h, placement.rowConfig) == true
                end
                if not positionedByAuraMirror then
                    deps.positionOwned(frame, container, "CENTER", "CENTER", x, y, placement.rowConfig)
                end
                if wrapper.hideAuraBase and frame.Hide then frame:Hide() end
                n = n + 1
            end
        end
    end
    if not hasDynamic then return n end
    local scratch = self._nativeFlowScratch
    if not scratch then
        scratch = { rows = {}, rowOrder = {}, positionedFrames = {} }
        self._nativeFlowScratch = scratch
    end
    local rows, rowOrder, positionedFrames = scratch.rows, scratch.rowOrder, scratch.positionedFrames
    for _, placement in ipairs(plan.placements) do
        local wrapper = placement.icon
        local record = wrapper and wrapper.auraMirror
        local frame = record and record.dynamic and not record.reserved and record.host or wrapper and wrapper.frame
        local row = placement.rowConfig and placement.rowConfig.rowNum or 1
        local segments = rows[row]
        if not segments then segments = { count = 0 }; rows[row] = segments end
        if not segments.active then
            segments.active = true
            rowOrder[#rowOrder + 1] = row
        end
        if frame and not positionedFrames[frame] then
            positionedFrames[frame] = true
            segments.count = segments.count + 1
            local segment = segments[segments.count]
            if not segment then segment = {}; segments[segments.count] = segment end
            segment.frame, segment.record, segment.placement, segment.wrapper = frame, record, placement, wrapper
            if record and record.dynamic then
                segments.direction = segments.direction or record.run
                if not record.reserved then segments.hasDynamic = true end
            end
        end
    end
    for rowIndex, row in ipairs(rowOrder) do
        local segments = rows[row]
        if segments.hasDynamic then
            local previous, previousDynamic
            local direction = segments.direction
            local vertical, forward = direction.vertical, direction.forward
            local anchor = vertical and (forward and "BOTTOM" or "TOP") or (forward and "LEFT" or "RIGHT")
            local opposite = vertical and (forward and "TOP" or "BOTTOM") or (forward and "RIGHT" or "LEFT")
            for index = 1, segments.count do
                local segment = segments[index]
                local record, frame = segment.record, segment.frame
                local dynamic = record and record.dynamic and not record.reserved
                local placement = segment.placement
                local padding = placement.rowConfig and placement.rowConfig.padding or 0
                local w, h = PlacementRect(placement)
                if not dynamic then
                    container._quiBuffFlowProxies = container._quiBuffFlowProxies or {}
                    local proxyRows = container._quiBuffFlowProxies
                    proxyRows[row] = proxyRows[row] or {}
                    local proxies = proxyRows[row]
                    proxies[index] = proxies[index] or CreateFrame("Frame", nil, container,
                        "DisableUntrustedLayoutScriptsTemplate")
                    frame = proxies[index]
                    frame:SetSize(w, h)
                    if segment.wrapper.reanchored then
                        bridge:OverlayRect(segment.frame, frame, "TOPLEFT", 0, 0, "BOTTOMRIGHT", 0, 0)
                    else
                        segment.frame:ClearAllPoints()
                        segment.frame:SetPoint("CENTER", frame, "CENTER", 0, 0)
                    end
                end
                frame:ClearAllPoints()
                if segments.count == 1 then
                    local offset = (padding + 1) / 2 * (forward and 1 or -1)
                    local rc = placement.rowConfig
                    frame:SetPoint("CENTER", container, "CENTER",
                        vertical and placement.x or ((rc and rc.xOffset or 0) + offset),
                        vertical and ((rc and rc.yOffset or 0) + offset) or placement.y)
                elseif previous then
                    local offset = (previousDynamic and -1 or padding) * (forward and 1 or -1)
                    frame:SetPoint(anchor, previous, opposite, vertical and 0 or offset, vertical and offset or 0)
                else
                    local offset = (vertical and h or w) / 2 * (forward and -1 or 1)
                    frame:SetPoint(anchor, container, "CENTER", placement.x + (vertical and 0 or offset),
                        placement.y + (vertical and offset or 0))
                end
                previous, previousDynamic = frame, dynamic
            end
        end
        for index = 1, segments.count do
            local segment = segments[index]
            segment.frame, segment.record, segment.placement, segment.wrapper = nil, nil, nil, nil
        end
        segments.count, segments.active, segments.direction, segments.hasDynamic = 0, nil, nil, nil
        rowOrder[rowIndex] = nil
    end
    for frame in pairs(positionedFrames) do positionedFrames[frame] = nil end
    return n
end

local DEFAULT_BATCH_KEYS = { "essential", "utility", "buff" }

local function SortContainerKeys(keys)
    local priority = { essential = 1, utility = 2, buff = 3, buffIcon = 3 }
    table.sort(keys, function(a, b)
        local ap, bp = priority[a] or 100, priority[b] or 100
        if ap ~= bp then return ap < bp end
        return tostring(a) < tostring(b)
    end)
end

function CDMReanchorRuntime:_PrepareContainerState(containerKey)
    local deps, wiring = self._deps, self._wiring
    local state = { containerKey = containerKey }
    local viewers = wiring.GetViewersForKey and wiring:GetViewersForKey(containerKey) or nil
    if not viewers or #viewers == 0 then
        local viewer = wiring:GetViewerForKey(containerKey)
        if viewer then viewers = { viewer } end
    end
    state.viewers = viewers
    state.container = deps.getContainer and deps.getContainer(containerKey) or nil
    if not viewers or #viewers == 0 or not state.container then
        state.earlyReturn = "no-viewers-or-container"
        return state
    end

    state.settings = deps.getSettings and deps.getSettings(containerKey) or nil
    if not state.settings then
        state.earlyReturn = "no-settings"
        return state
    end

    if wiring.BuildFrameMapForViewers then
        state.frameMap, state.items = wiring:BuildFrameMapForViewers(viewers)
    else
        state.frameMap, state.items = wiring:BuildFrameMap(viewers[1])
    end
    state.frameMap = state.frameMap or {}
    state.items = state.items or {}
    state.curated = (deps.getCurated and deps.getCurated(containerKey)) or {}

    local displayMode = state.settings.iconDisplayMode or "always"
    if displayMode == "combat" then
        displayMode = (deps.inCombat and deps.inCombat()) and "always" or "active"
    end
    state.displayMode = displayMode
    state.editing = (deps.isEditMode and deps.isEditMode()) and true or false
    state.filterInactive = displayMode == "active"
        and deps.frameIsActive ~= nil and not state.editing

    if state.settings.enabled == false then
        state.earlyReturn = "disabled"
        state.matched, state.frameless, state.claimedFrames = {}, {}, {}
        return state
    end

    state.matched, state.frameless, state.claimedFrames =
        wiring:MatchCuratedToFrames(state.curated, state.frameMap, containerKey)
    state.matched = state.matched or {}
    state.frameless = state.frameless or {}
    state.claimedFrames = state.claimedFrames or {}

    if #state.frameless > 0 then
        local unresolved = {}
        for i = 1, #state.frameless do
            local entry = state.frameless[i]
            local frame
            if IsBlizzardCDMEntry(entry) then
                local cooldownID = wiring.ResolveEntryCooldownID
                    and wiring:ResolveEntryCooldownID(entry, containerKey) or nil
                frame = cooldownID ~= nil and state.frameMap[cooldownID] or nil
                if not frame and wiring.ResolveEntryFrame then
                    frame = wiring:ResolveEntryFrame(entry, state.frameMap)
                end
            end
            if frame then
                state.matched[#state.matched + 1] = { entry = entry, frame = frame }
                state.claimedFrames[frame] = true
            else
                unresolved[#unresolved + 1] = entry
            end
        end
        state.frameless = unresolved
    end

    state.nativeUsableByEntry = {}
    for i = 1, #state.matched do
        local match = state.matched[i]
        local usable = true
        if state.filterInactive then
            usable = deps.frameIsActive(match.frame, containerKey, match.entry) and true or false
        end
        state.nativeUsableByEntry[match.entry] = usable
    end
    return state
end

function CDMReanchorRuntime:RefreshContainers(containerKeys)
    if ns.CDMNativeCallTrace then ns.CDMNativeCallTrace:Checkpoint("reanchor batch entry") end
    local keys, seen = {}, {}
    containerKeys = containerKeys or DEFAULT_BATCH_KEYS
    for i = 1, #containerKeys do
        local key = containerKeys[i]
        if key and not seen[key] then
            seen[key] = true
            keys[#keys + 1] = key
        end
    end
    SortContainerKeys(keys)

    for i = 1, #keys do
        if self:_ShouldDeferOwnedReleaseInCombat(keys[i]) then
            self._pendingCombatRefresh = self._pendingCombatRefresh or {}
            for k = 1, #keys do
                local key = keys[k]
                self._pendingCombatRefresh[key] = true
                self:_NextDiag(key, { earlyReturn = "combat-protected-owned" })
            end
            return {}
        end
    end

    local states, candidates = {}, {}
    for i = 1, #keys do
        local key = keys[i]
        local state = self:_PrepareContainerState(key)
        states[key] = state
        if not state.earlyReturn then
            local ordinalByEntry = {}
            for ordinal = 1, #state.curated do
                ordinalByEntry[state.curated[ordinal]] = ordinal
            end
            for m = 1, #state.matched do
                local match = state.matched[m]
                if state.nativeUsableByEntry[match.entry] ~= false then
                    candidates[#candidates + 1] = {
                        containerKey = key,
                        ordinal = ordinalByEntry[match.entry] or m,
                        entry = match.entry,
                        frame = match.frame,
                    }
                end
            end
        end
    end

    local planner = self._deps.placementPlanner or ns.CDMPlacementPlanner
    local placementPlan = planner and planner.Plan and planner.Plan(candidates) or nil

    for i = 1, #keys do self:ClearContainerRegistry(keys[i]) end
    if placementPlan then
        self._consumersByFrame = placementPlan.consumersByFrame
        self._placementsByKey = placementPlan.assignmentsByKey
        for frame, owner in pairs(placementPlan.ownerByFrame) do
            local assignment = placementPlan.assignmentsByContainer[owner.containerKey]
                and placementPlan.assignmentsByContainer[owner.containerKey][owner.entry]
            self._nativePlacementByFrame[frame] = assignment
            self._entryByFrame[frame] = owner.entry
        end
    end

    local counts = {}
    for i = 1, #keys do
        local key = keys[i]
        counts[key] = self:RefreshContainer(key, states[key], placementPlan, true)
    end
    return counts
end

function CDMReanchorRuntime:RefreshContainer(containerKey, prepared, placementPlan, batchCommit)
    if ns.CDMNativeCallTrace then ns.CDMNativeCallTrace:Checkpoint("reanchor container entry") end
    if not batchCommit and self:_ShouldDeferOwnedReleaseInCombat(containerKey) then
        self._pendingCombatRefresh = self._pendingCombatRefresh or {}
        self._pendingCombatRefresh[containerKey] = true
        self:_NextDiag(containerKey, { earlyReturn = "combat-protected-owned" })
        return #(self._mintedOwnedByKey[containerKey] or {})
    end

    local deps, wiring, bridge = self._deps, self._wiring, self._bridge
    prepared = prepared or self:_PrepareContainerState(containerKey)
    local viewers = prepared.viewers
    local container = prepared.container
    if not viewers or #viewers == 0 or not container then
        self:_NextDiag(containerKey, { earlyReturn = "no-viewers-or-container" })
        if not batchCommit then self:ClearContainerRegistry(containerKey) end
        self:ReleaseOwnedIcons(containerKey)
        return 0
    end
    local settings = prepared.settings
    if not settings then
        self:_NextDiag(containerKey, { earlyReturn = "no-settings" })
        if not batchCommit then self:ClearContainerRegistry(containerKey) end
        self:ReleaseOwnedIcons(containerKey)
        return 0
    end

    local shellPassActive = false
    if deps.beginShellPass then
        deps.beginShellPass(container)
        shellPassActive = true
    elseif deps.resetShells then
        deps.resetShells(container)
    end
    local auraMirrorPassActive = deps.beginAuraMirrorPass
        and deps.beginAuraMirrorPass(container) == true

    local frameMap, items = prepared.frameMap or {}, prepared.items or {}
    local entries, claimedFrames
    if settings.enabled == false then
        self:_NextDiag(containerKey, { earlyReturn = "disabled" })
        self:ReleaseOwnedIcons(containerKey)
        entries, claimedFrames = {}, {}
    else
        entries, claimedFrames = self:AssembleEntries(
            containerKey, frameMap, settings, prepared, placementPlan)
    end

    if ns.CDMNativeCallTrace then ns.CDMNativeCallTrace:Checkpoint("reanchor entries assembled") end
    if not batchCommit then self:ClearContainerRegistry(containerKey) end
    local reanchored = {}
    for i = 1, #entries do
        local w = entries[i]
        if w.reanchored and w.liveFrame then
            reanchored[#reanchored + 1] = w.liveFrame
            self._entryByFrame[w.liveFrame] = w.src
            if not self._nativePlacementByFrame[w.liveFrame] then
                self._nativePlacementByFrame[w.liveFrame] = {
                    placementKey = w.placementKey,
                    containerKey = containerKey,
                    entry = w.src,
                    frame = w.liveFrame,
                    renderKind = "native",
                }
            end
            if not self._consumersByFrame[w.liveFrame] then
                self._consumersByFrame[w.liveFrame] = { self._nativePlacementByFrame[w.liveFrame] }
            end
            if deps.auraPhase then
                deps.auraPhase:Hook(w.liveFrame, containerKey, w.src)
                if ns.CDMNativeCallTrace then ns.CDMNativeCallTrace:Checkpoint("reanchor aura hooks installed") end
                if deps.auraPhase.Reassert then
                    deps.auraPhase:Reassert(w.liveFrame, w.src)
                end
            end
            if deps.pandemic then
                deps.pandemic:Hook(w.liveFrame)
                if deps.pandemic.OnClaim then
                    deps.pandemic:OnClaim(w.liveFrame, w.src)
                end
            end
            if deps.getProcGlow then
                local pg = deps.getProcGlow()
                if pg and pg.OnClaim then
                    pg:OnClaim(w.liveFrame, w.src)
                end
            end
        end
    end
    self._reanchoredByKey[containerKey] = reanchored

    local plan = deps.buildLayout and deps.buildLayout(settings, entries, {}) or nil
    if not plan and deps.buildBuffLayout then
        plan = deps.buildBuffLayout(settings, entries, {}, containerKey)
    end
    local positioned = self:PositionEntries(container, plan, containerKey)
    local diag = self._lastDiagByKey[containerKey]
    if diag then
        diag.planNil = plan == nil
        diag.positioned = positioned
    end
    if shellPassActive and deps.endShellPass then
        deps.endShellPass(container)
    end
    if auraMirrorPassActive and deps.endAuraMirrorPass then
        deps.endAuraMirrorPass(container)
    end

    if plan and plan.metrics and deps.applySize then
        deps.applySize(container, plan.metrics)
    end

    local preserveNativeAnchors = IsBuffIconKey(containerKey)
    for i = 1, #items do
        local frame = items[i]
        if not claimedFrames[frame] and not self:IsFrameClaimedByAnyContainer(frame) then
            local previouslyClaimed = bridge.IsClaimed and bridge:IsClaimed(frame)
            if not preserveNativeAnchors or previouslyClaimed or settings.enabled == false
                or bridge:ResolveIdentity(frame) ~= nil then
                bridge:Sink(frame, preserveNativeAnchors)
            end
            if deps.hideLiveTooltip then deps.hideLiveTooltip(frame) end
        end
    end

    return #entries
end
