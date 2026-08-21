local ADDON_NAME, ns = ...
local QUICore = ns.Addon
local nsHelpers = ns.Helpers

local QUI_Anchoring = {}
ns.QUI_Anchoring = QUI_Anchoring

local _forceRawPointMode = true
C_Timer.After(0.5, function() _forceRawPointMode = false end)

local pendingAnchoredFrameUpdateAfterCombat = false

local pendingCombatConsumerOps = {}

local function latchCombatConsumerOp(originKey, slotKey, op)
    if not originKey or type(op) ~= "function" then return end
    local bySlot = pendingCombatConsumerOps[originKey]
    if not bySlot then
        bySlot = {}
        pendingCombatConsumerOps[originKey] = bySlot
    end
    bySlot[slotKey or "apply"] = op
end

local function drainPendingCombatConsumerOps()
    if next(pendingCombatConsumerOps) == nil then return end
    local snapshot = pendingCombatConsumerOps
    pendingCombatConsumerOps = {}
    for originKey, bySlot in pairs(snapshot) do
        for _, op in pairs(bySlot) do
            ns.SafeCall("bulkhead", op, originKey)
        end
    end
end

QUI_Anchoring.anchorTargets = {}

QUI_Anchoring.categories = {}

QUI_Anchoring.layoutOwnedFrames = {}
QUI_Anchoring.claimedAnchorKeys = {}

local Helpers = {}

local CDM_LOGICAL_SIZE_KEYS = {}

local CORNER_POINTS = {
    TOPLEFT     = true,
    TOPRIGHT    = true,
    BOTTOMLEFT  = true,
    BOTTOMRIGHT = true,
}

local _editModeReapplyGuard = false

local function FrameAlreadyAtPosition(frame, pt, relativeTo, relPt, x, y)
    if not frame or not frame.GetNumPoints then return false end
    if frame:GetNumPoints() ~= 1 then return false end
    local cp, crt, crp, cx, cy = frame:GetPoint(1)
    if cp ~= pt or crt ~= relativeTo or crp ~= relPt then return false end
    return math.abs((cx or 0) - (x or 0)) < 0.1 and math.abs((cy or 0) - (y or 0)) < 0.1
end

local function SmoothSetPoint(frame, pt, relativeTo, relPt, x, y)
    local H = ns.Helpers
    local numPts = frame:GetNumPoints()
    if numPts == 1 then
        local cp = frame:GetPoint(1)
        if cp == pt then
            H.BaseSetPoint(frame, pt, relativeTo, relPt, x, y)
            return
        end
    end
    H.BaseClearAllPoints(frame)
    H.BaseSetPoint(frame, pt, relativeTo, relPt, x, y)
end

function QUI_Anchoring:SetHelpers(helpers)
    Helpers = helpers or {}
end

local function Scale(x, frame)
    return Helpers.Scale and Helpers.Scale(x, frame) or (QUICore and QUICore.Scale and QUICore:Scale(x, frame) or x)
end

local function PixelRound(frame, value)
    if value == 0 then return 0 end
    if QUICore and QUICore.PixelRound then
        return QUICore:PixelRound(value, frame)
    end
    return value
end

local function GetSavedFrameAnchorSettings(anchoringDB, key)
    if type(anchoringDB) ~= "table" or not key then
        return nil
    end
    if rawget(anchoringDB, key) == nil then
        return nil
    end
    local settings = anchoringDB[key]
    if type(settings) == "table" then
        return settings
    end
    return nil
end

local function GetBorderAdjustment(anchorPoint, borderSize)
    if not borderSize or borderSize == 0 then return 0, 0 end

    local adjX, adjY = 0, 0
    if anchorPoint == "TOPLEFT" then
        adjX = borderSize
        adjY = -borderSize
    elseif anchorPoint == "TOP" then
        adjY = -borderSize
    elseif anchorPoint == "TOPRIGHT" then
        adjX = -borderSize
        adjY = -borderSize
    elseif anchorPoint == "LEFT" then
        adjX = borderSize
    elseif anchorPoint == "RIGHT" then
        adjX = -borderSize
    elseif anchorPoint == "BOTTOMLEFT" then
        adjX = borderSize
        adjY = borderSize
    elseif anchorPoint == "BOTTOM" then
        adjY = borderSize
    elseif anchorPoint == "BOTTOMRIGHT" then
        adjX = -borderSize
        adjY = borderSize
    end
    return adjX, adjY
end

function QUI_Anchoring:RegisterAnchorTarget(name, frame, options)
    if not name or not frame then
        return false
    end

    options = options or {}
    self.anchorTargets[name] = {
        frame = frame,
        options = options
    }

    local category = options.category
    if category then
        if not self.categories[category] then
            self.categories[category] = {
                order = options.categoryOrder or 999
            }
        end
    end

    return true
end

function QUI_Anchoring:UnregisterAnchorTarget(name)
    if not name then return false end
    self.anchorTargets[name] = nil
    return true
end

function QUI_Anchoring:GetAnchorTarget(name)
    if not name then return nil end

    local registered = self.anchorTargets[name]
    if registered then
        return registered.frame
    end

    return nil
end

function QUI_Anchoring:GetAnchorTargetList(include, exclude, excludeSelf)
    exclude = exclude or {}

    local includeLookup = {}
    local excludeLookup = {}

    if include == nil then
        includeLookup = nil
    elseif type(include) == "table" then
        for _, value in ipairs(include) do
            includeLookup[value] = true
        end
    end

    if type(exclude) == "table" then
        for _, value in ipairs(exclude) do
            excludeLookup[value] = true
        end
    end

    local function ShouldInclude(value)
        if excludeLookup[value] then
            return false
        end
        if excludeSelf and value == excludeSelf then
            return false
        end
        if includeLookup then
            return includeLookup[value] == true
        end
        return true
    end

    local list = {}

    if ShouldInclude("disabled") then
        table.insert(list, {value = "disabled", text = "Disabled"})
    end
    if ShouldInclude("screen") then
        table.insert(list, {value = "screen", text = "Screen Center"})
    end

    local categorized = {}
    local uncategorized = {}

    for name, data in pairs(self.anchorTargets) do
        if ShouldInclude(name) then
            local displayName = data.options and data.options.displayName or name
            displayName = tostring(displayName)
            displayName = displayName:gsub("^%l", string.upper)
            displayName = displayName:gsub("([a-z])([A-Z])", "%1 %2")

            local category = data.options and data.options.category
            local order = data.options and data.options.order or 999
            local item = {value = name, text = displayName, category = category, order = order}

            if category then
                if not categorized[category] then
                    categorized[category] = {}
                end
                table.insert(categorized[category], item)
            else
                table.insert(uncategorized, item)
            end
        end
    end

    local sortedCategories = {}
    for category, items in pairs(categorized) do
        local categoryInfo = self.categories[category] or {}
        local categoryOrder = categoryInfo.order or 999
        table.insert(sortedCategories, {name = category, order = categoryOrder})
        table.sort(items, function(a, b)
            if a.order ~= b.order then
                return a.order < b.order
            end
            return a.text < b.text
        end)
    end
    table.sort(sortedCategories, function(a, b)
        if a.order ~= b.order then
            return a.order < b.order
        end
        return a.name < b.name
    end)

    table.sort(uncategorized, function(a, b)
        if a.order ~= b.order then
            return a.order < b.order
        end
        return a.text < b.text
    end)

    for _, catInfo in ipairs(sortedCategories) do
        local category = catInfo.name
        table.insert(list, {value = nil, text = category, isHeader = true})
        for _, item in ipairs(categorized[category]) do
            table.insert(list, item)
        end
    end

    if #uncategorized > 0 then
        if #sortedCategories > 0 then
            table.insert(list, {value = nil, text = "Other", isHeader = true})
        end
        for _, item in ipairs(uncategorized) do
            table.insert(list, item)
        end
    end

    return list
end

local function GetBorderSize(frame)
    if not frame or not frame.GetBackdrop then
        return 0
    end

    local backdrop = frame:GetBackdrop()
    if not backdrop or not backdrop.edgeSize then
        return 0
    end

    return backdrop.edgeSize or 0
end

local VALID_ANCHOR_POINTS = {
    TOPLEFT = true, TOP = true, TOPRIGHT = true,
    LEFT = true, CENTER = true, RIGHT = true,
    BOTTOMLEFT = true, BOTTOM = true, BOTTOMRIGHT = true,
}

function QUI_Anchoring:PositionFrame(frame, anchorTarget, anchorPoint, offsetX, offsetY, parentFrame, options)
    if not frame then return false end

    if self.layoutOwnedFrames[frame] then return true end

    if InCombatLockdown() and not ns._inInitSafeWindow then
        pendingAnchoredFrameUpdateAfterCombat = true
        return false
    end

    options = options or {}
    offsetX = offsetX or 0
    offsetY = offsetY or 0

    anchorPoint = anchorPoint or "CENTER"
    if not VALID_ANCHOR_POINTS[anchorPoint] then
        anchorPoint = "CENTER"
    end

    local targetAnchorPoint = options.targetAnchorPoint or anchorPoint
    if not VALID_ANCHOR_POINTS[targetAnchorPoint] then
        targetAnchorPoint = anchorPoint
    end

    local sourceAnchorPoint2 = options.sourceAnchorPoint2
    local targetAnchorPoint2 = options.targetAnchorPoint2
    local useExplicitDualAnchors = sourceAnchorPoint2 and targetAnchorPoint2 and
                                   VALID_ANCHOR_POINTS[sourceAnchorPoint2] and
                                   VALID_ANCHOR_POINTS[targetAnchorPoint2]

    local success = ns.SafeCallMethod("best-effort-style", frame, "ClearAllPoints")
    if not success then
        C_Timer.After(0, function()
            if InCombatLockdown() then
                pendingAnchoredFrameUpdateAfterCombat = true
                return
            end
            ns.SafeCallMethodIfPresent("best-effort-style", frame, "ClearAllPoints")
        end)
        return false
    end

    if not anchorTarget or anchorTarget == "none" or anchorTarget == "disabled" or anchorTarget == "screen" then
        frame:SetPoint("CENTER", UIParent, "CENTER", offsetX, offsetY)
        return true
    end

    if anchorTarget == "unitframe" and parentFrame then
        local sourceBorderSize = GetBorderSize(frame)
        local targetBorderSize = GetBorderSize(parentFrame)

        local sourceAdjX, sourceAdjY = GetBorderAdjustment(anchorPoint, sourceBorderSize)
        local targetAdjX, targetAdjY = GetBorderAdjustment(targetAnchorPoint, targetBorderSize)
        local netAdjX = targetAdjX - sourceAdjX
        local netAdjY = targetAdjY - sourceAdjY

        local scaledOffsetX = PixelRound(frame, Scale(offsetX, frame) + netAdjX)
        local scaledOffsetY = PixelRound(frame, Scale(offsetY, frame) + netAdjY)

        if useExplicitDualAnchors then
            local sourceAdjX2, sourceAdjY2 = GetBorderAdjustment(sourceAnchorPoint2, sourceBorderSize)
            local targetAdjX2, targetAdjY2 = GetBorderAdjustment(targetAnchorPoint2, targetBorderSize)
            local netAdjX2 = targetAdjX2 - sourceAdjX2
            local netAdjY2 = targetAdjY2 - sourceAdjY2

            local scaledOffsetX2 = PixelRound(frame, Scale(offsetX, frame) + netAdjX2)
            local scaledOffsetY2 = PixelRound(frame, Scale(offsetY, frame) + netAdjY2)

            frame:SetPoint(anchorPoint, parentFrame, targetAnchorPoint, scaledOffsetX, scaledOffsetY)
            frame:SetPoint(sourceAnchorPoint2, parentFrame, targetAnchorPoint2, scaledOffsetX2, scaledOffsetY2)
            return true
        end

        frame:SetPoint(anchorPoint, parentFrame, targetAnchorPoint, scaledOffsetX, scaledOffsetY)
        return true
    end

    local anchorFrame = self:GetAnchorTarget(anchorTarget)
    if not anchorFrame then
        return false
    end

    if not anchorFrame:IsShown() then
        return false
    end

    local sourceBorderSize = GetBorderSize(frame)
    local targetBorderSize = GetBorderSize(anchorFrame)

    local sourceAdjX, sourceAdjY = GetBorderAdjustment(anchorPoint, sourceBorderSize)
    local targetAdjX, targetAdjY = GetBorderAdjustment(targetAnchorPoint, targetBorderSize)
    local netAdjX = targetAdjX - sourceAdjX
    local netAdjY = targetAdjY - sourceAdjY

    local scaledOffsetX = PixelRound(frame, Scale(offsetX, frame) + netAdjX)
    local scaledOffsetY = PixelRound(frame, Scale(offsetY, frame) + netAdjY)

    if useExplicitDualAnchors then
        local sourceAdjX2, sourceAdjY2 = GetBorderAdjustment(sourceAnchorPoint2, sourceBorderSize)
        local targetAdjX2, targetAdjY2 = GetBorderAdjustment(targetAnchorPoint2, targetBorderSize)
        local netAdjX2 = targetAdjX2 - sourceAdjX2
        local netAdjY2 = targetAdjY2 - sourceAdjY2

        local scaledOffsetX2 = PixelRound(frame, Scale(offsetX, frame) + netAdjX2)
        local scaledOffsetY2 = PixelRound(frame, Scale(offsetY, frame) + netAdjY2)

        frame:SetPoint(anchorPoint, anchorFrame, targetAnchorPoint, scaledOffsetX, scaledOffsetY)
        frame:SetPoint(sourceAnchorPoint2, anchorFrame, targetAnchorPoint2, scaledOffsetX2, scaledOffsetY2)
        return true
    end

    frame:SetPoint(anchorPoint, anchorFrame, targetAnchorPoint, scaledOffsetX, scaledOffsetY)

    return true
end

function QUI_Anchoring:SnapTo(frame, anchorTarget, anchorPoint, offsetX, offsetY, options)
    if not frame or not anchorTarget then
        return false
    end

    options = options or {}
    offsetX = offsetX or 0
    offsetY = offsetY or 0

    local targetFrame = self:GetAnchorTarget(anchorTarget)
    if not targetFrame then
        if options.onFailure then
            options.onFailure("Anchor target not found: " .. tostring(anchorTarget))
        end
        return false
    end

    if options.checkVisible ~= false then
        if not targetFrame:IsShown() then
            if options.onFailure then
                local registered = self.anchorTargets and self.anchorTargets[anchorTarget]
                local displayName = registered and registered.options and registered.options.displayName or anchorTarget
                options.onFailure(displayName .. " not visible.")
            end
            return false
        end
    end

    if not anchorPoint then
        if anchorTarget == "screen" or anchorTarget == "disabled" or anchorTarget == "none" then
            anchorPoint = "CENTER"
        else
            anchorPoint = "BOTTOMLEFT"
        end
    end

    local positionOptions = {
        targetAnchorPoint = options.targetAnchorPoint,
    }
    local success = self:PositionFrame(frame, anchorTarget, anchorPoint, offsetX, offsetY, nil, positionOptions)

    if success and frame._quiReRegisterStateDriver then
        C_Timer.After(0, function()
            if frame and frame._quiReRegisterStateDriver then
                frame._quiReRegisterStateDriver()
            end
        end)
    end

    if success and options.onSuccess then
        options.onSuccess()
    end

    return success
end

local anchoredFramesCombatFrame = CreateFrame("Frame")
anchoredFramesCombatFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
anchoredFramesCombatFrame:SetScript("OnEvent", function()
    if not pendingAnchoredFrameUpdateAfterCombat
        and next(pendingCombatConsumerOps) == nil then return end

    local runFullApply = pendingAnchoredFrameUpdateAfterCombat
    pendingAnchoredFrameUpdateAfterCombat = false
    C_Timer.After(0.05, function()
        if InCombatLockdown() then
            if runFullApply then
                pendingAnchoredFrameUpdateAfterCombat = true
            end
            return
        end
        if runFullApply and QUI_Anchoring then
            local applyOK, status = ns.SafeCallMethod("best-effort-style", QUI_Anchoring, "ApplyAllFrameAnchors",
                false, drainPendingCombatConsumerOps)
            if not applyOK then
                pendingAnchoredFrameUpdateAfterCombat = true
                return
            end
            if status == "skipped" then
                drainPendingCombatConsumerOps()
            end
            return
        end
        drainPendingCombatConsumerOps()
    end)
end)

local layoutUpdateFrame = CreateFrame("Frame")
layoutUpdateFrame:RegisterEvent("EDIT_MODE_LAYOUTS_UPDATED")
local _layoutUpdatePending = false
layoutUpdateFrame:SetScript("OnEvent", function()
    if _layoutUpdatePending then return end
    _layoutUpdatePending = true
    C_Timer.After(0.3, function()
        _layoutUpdatePending = false
        if InCombatLockdown() then
            pendingAnchoredFrameUpdateAfterCombat = true
            return
        end
        if not nsHelpers.IsEditModeActive() then
            if QUI_Anchoring then
                QUI_Anchoring:ApplyAllFrameAnchors()
            end
            local RefreshUnitFrames = _G.QUI_RefreshUnitFrames
            if RefreshUnitFrames then ns.SafeCall("bulkhead", RefreshUnitFrames) end
            local RefreshGroupFrames = _G.QUI_RefreshGroupFrames
            if RefreshGroupFrames then ns.SafeCall("bulkhead", RefreshGroupFrames) end
        end
    end)
end)

local HasFrameResolverForKey
local ResolveApplyFrameForKey

local _anchorGuardedFrames = {}
local _setPointGuardedFrames = {}

local DYNAMIC_REANCHOR_KEYS = { buffFrame = true, debuffFrame = true }

local function InstallAnchorGuard(frame, key)
    if _anchorGuardedFrames[frame] then return end
    if key == "chatFrame1" then return end
    if not frame.ApplySystemAnchor then
        if DYNAMIC_REANCHOR_KEYS[key] then return end
        if _setPointGuardedFrames[frame] then return end
        _setPointGuardedFrames[frame] = true
        hooksecurefunc(frame, "SetPoint", function()
            if _editModeReapplyGuard then return end
            if _G.QUI_IsLayoutModeActive and _G.QUI_IsLayoutModeActive() then return end
            C_Timer.After(0, function()
                if InCombatLockdown() then
                    pendingAnchoredFrameUpdateAfterCombat = true
                    return
                end
                local anchoringDB = QUICore.db and QUICore.db.profile
                    and QUICore.db.profile.frameAnchoring
                local settings = GetSavedFrameAnchorSettings(anchoringDB, key)
                if settings then
                    QUI_Anchoring:ApplyFrameAnchor(key, settings)
                end
            end)
        end)
        return
    end
    _anchorGuardedFrames[frame] = true
    hooksecurefunc(frame, "ApplySystemAnchor", function()
        if _editModeReapplyGuard then return end
        C_Timer.After(0, function()
            if InCombatLockdown() then
                pendingAnchoredFrameUpdateAfterCombat = true
                return
            end
            local anchoringDB = QUICore.db and QUICore.db.profile
                and QUICore.db.profile.frameAnchoring
            local settings = GetSavedFrameAnchorSettings(anchoringDB, key)
            if settings then
                QUI_Anchoring:ApplyFrameAnchor(key, settings)
            end
        end)
    end)
end

local function InstallAllAnchorGuards()
    local anchoringDB = QUICore.db and QUICore.db.profile
        and QUICore.db.profile.frameAnchoring
    if not anchoringDB then return end
    for key, settings in pairs(anchoringDB) do
        if type(settings) == "table" and HasFrameResolverForKey(key) then
            local frame = ResolveApplyFrameForKey(key)
            if frame then
                InstallAnchorGuard(frame, key)
            end
        end
    end
end

if EditModeManagerFrame then
    hooksecurefunc(EditModeManagerFrame, "ExitEditMode", function()
        C_Timer.After(0, function()
            if InCombatLockdown() then
                pendingAnchoredFrameUpdateAfterCombat = true
                return
            end
            InstallAllAnchorGuards()
            if QUI_Anchoring then
                QUI_Anchoring:ApplyAllFrameAnchors()
            end
            local RefreshUnitFrames = _G.QUI_RefreshUnitFrames
            if RefreshUnitFrames then ns.SafeCall("bulkhead", RefreshUnitFrames) end
        end)
    end)
end

local anchorGuardInitFrame = CreateFrame("Frame")
anchorGuardInitFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
anchorGuardInitFrame:SetScript("OnEvent", function(f)
    f:UnregisterAllEvents()
    C_Timer.After(1, InstallAllAnchorGuards)
end)

local DebouncedReapplyOverrides
local ComputeAnchorApplyOrder
local function IsModuleDisabled(dbKey, enabledField)
    local profile = QUI and QUI.db and QUI.db.profile
    if not profile then return false end
    local db = profile[dbKey]
    if not db then return false end
    return db[enabledField or "enabled"] == false
end

local function IsBlizzardElementDisabled(elementKey)
    local profile = QUI and QUI.db and QUI.db.profile
    local elements = profile and profile.blizzardFrames and profile.blizzardFrames.elements
    local db = elements and elements[elementKey]
    return db and db.enabled == false
end

local MANAGED_REPARENT_TARGETS = {
    { key = "objectiveTracker",    frameName = "ObjectiveTrackerFrame",            holderName = "QUI_ObjectiveTrackerHolder"    },
    { key = "topCenterWidgets",    frameName = "UIWidgetTopCenterContainerFrame",  holderName = "QUI_TopCenterWidgetsHolder"    },
    { key = "belowMinimapWidgets", frameName = "UIWidgetBelowMinimapContainerFrame", holderName = "QUI_BelowMinimapWidgetsHolder" },
}

local managedReparentState = {}

local function MirrorHolderSize(key)
    local state = managedReparentState[key]
    if not state or not state.holder or not state.frame then return end
    local frame = state.frame
    local w = (frame.GetWidth  and frame:GetWidth())  or 0
    local h = (frame.GetHeight and frame:GetHeight()) or 0
    if type(w) ~= "number" or w < 1 then w = 1 end
    if type(h) ~= "number" or h < 1 then h = 1 end
    state.holder:SetSize(w, h)
end

local function ReanchorFrameToHolder(key)
    local state = managedReparentState[key]
    if not state or not state.holder or not state.frame then return end
    if InCombatLockdown() then return end
    local frame = state.frame
    state.hookingSetPoint = true
    ns.SafeCallMethod("best-effort-style", frame, "ClearAllPoints")
    ns.SafeCallMethod("best-effort-style", frame, "SetPoint", "TOPLEFT", state.holder, "TOPLEFT", 0, 0)
    state.hookingSetPoint = false
    MirrorHolderSize(key)
end

local function QueueManagedReanchor(key)
    local state = managedReparentState[key]
    if not state or state.pendingReanchor then return end
    state.pendingReanchor = true
    C_Timer.After(0, function()
        state.pendingReanchor = false
        if InCombatLockdown() then return end
        ReanchorFrameToHolder(key)
    end)
end

local function InstallManagedReparent(def)
    local state = managedReparentState[def.key]
    if state and state.installed then return state.holder end
    if InCombatLockdown() then return nil end

    local frame = _G[def.frameName]
    if not frame then return nil end

    state = state or {}
    managedReparentState[def.key] = state
    state.key   = def.key
    state.frame = frame

    local holder = state.holder or _G[def.holderName]
    if not holder then
        holder = CreateFrame("Frame", def.holderName, UIParent)
        local strata = frame.GetFrameStrata and frame:GetFrameStrata() or "MEDIUM"
        holder:SetFrameStrata(strata)
        local seedW = (frame.GetWidth  and frame:GetWidth())  or 0
        local seedH = (frame.GetHeight and frame:GetHeight()) or 0
        if type(seedW) ~= "number" or seedW < 1 then seedW = 200 end
        if type(seedH) ~= "number" or seedH < 1 then seedH = 200 end
        holder:SetSize(seedW, seedH)
        holder:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    end
    state.holder = holder

    -- reparenting. Otherwise the container's showingFrames array still holds
    local currentParent = frame.GetParent and frame:GetParent() or nil
    ns.SafeCallMethodIfPresent("best-effort-style", currentParent, "RemoveManagedFrame", frame)
    frame.ignoreFramePositionManager = true

    state.hookingSetParent = true
    ns.SafeCallMethod("best-effort-style", frame, "SetParent", holder)
    state.hookingSetParent = false

    ReanchorFrameToHolder(def.key)

    if frame.HookScript and not state.sizeHooked then
        state.sizeHooked = true
        frame:HookScript("OnSizeChanged", function()
            MirrorHolderSize(def.key)
        end)
    end

    if not state.setPointHooked then
        state.setPointHooked = true
        hooksecurefunc(frame, "SetPoint", function()
            if state.hookingSetPoint then return end
            QueueManagedReanchor(def.key)
        end)
    end

    if not state.setParentHooked then
        state.setParentHooked = true
        hooksecurefunc(frame, "SetParent", function(self, newParent)
            if state.hookingSetParent then return end
            if newParent == state.holder then return end
            C_Timer.After(0, function()
                if InCombatLockdown() then return end
                if state.frame:GetParent() == state.holder then return end
                state.hookingSetParent = true
                ns.SafeCallMethod("best-effort-style", state.frame, "SetParent", state.holder)
                state.hookingSetParent = false
                QueueManagedReanchor(def.key)
            end)
        end)
    end

    state.installed = true
    return holder
end

local function EnsureAllManagedReparents()
    if InCombatLockdown() then return end
    local installedAny = false
    for _, def in ipairs(MANAGED_REPARENT_TARGETS) do
        local wasInstalled = managedReparentState[def.key] and managedReparentState[def.key].installed
        if InstallManagedReparent(def) and not wasInstalled then
            installedAny = true
        end
    end
    if installedAny and QUI_Anchoring and QUI_Anchoring.ApplyAllFrameAnchors then
        C_Timer.After(0, function()
            if InCombatLockdown() then return end
            ns.SafeCallMethod("best-effort-style", QUI_Anchoring, "ApplyAllFrameAnchors")
        end)
    end
end

local managedReparentInitFrame = CreateFrame("Frame")
managedReparentInitFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
managedReparentInitFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
managedReparentInitFrame:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_REGEN_ENABLED" then
        EnsureAllManagedReparents()
        return
    end
    C_Timer.After(0.5, EnsureAllManagedReparents)
end)

local FRAME_RESOLVERS = {
    cdmEssential = function() return _G.QUI_GetCDMViewerFrame and _G.QUI_GetCDMViewerFrame("essential") end,
    cdmUtility = function() return _G.QUI_GetCDMViewerFrame and _G.QUI_GetCDMViewerFrame("utility") end,
    buffIcon = function() return _G.QUI_GetCDMViewerFrame and _G.QUI_GetCDMViewerFrame("buffIcon") end,
    buffBar = function() return _G.QUI_GetCDMViewerFrame and _G.QUI_GetCDMViewerFrame("buffBar") end,
    rotationAssistIcon = function()
        local frame = _G.QUI_RotationAssistIcon
        if frame then
            return frame
        end

        if _G.QUI and _G.QUI.RotationAssistIcon and _G.QUI.RotationAssistIcon.GetFrame then
            frame = _G.QUI.RotationAssistIcon.GetFrame()
            if frame then
                return frame
            end
        end

        if _G.QUI_RefreshRotationAssistIcon then
            _G.QUI_RefreshRotationAssistIcon()
            return _G.QUI_RotationAssistIcon
        end

        return nil
    end,
    primaryPower = function()
        if QUICore and QUICore.GetSwapAwareBarFor then
            local f = QUICore:GetSwapAwareBarFor("primaryPower")
            if f then return f end
        end
        return QUICore and QUICore.powerBar
    end,
    secondaryPower = function()
        if QUICore and QUICore.GetSwapAwareBarFor then
            local f = QUICore:GetSwapAwareBarFor("secondaryPower")
            if f then return f end
        end
        return QUICore and QUICore.secondaryPowerBar
    end,
    playerFrame = function() return ns.QUI_UnitFrames and ns.QUI_UnitFrames.frames and ns.QUI_UnitFrames.frames.player end,
    targetFrame = function() return ns.QUI_UnitFrames and ns.QUI_UnitFrames.frames and ns.QUI_UnitFrames.frames.target end,
    totFrame = function() return ns.QUI_UnitFrames and ns.QUI_UnitFrames.frames and ns.QUI_UnitFrames.frames.targettarget end,
    focusFrame = function() return ns.QUI_UnitFrames and ns.QUI_UnitFrames.frames and ns.QUI_UnitFrames.frames.focus end,
    petFrame = function() return ns.QUI_UnitFrames and ns.QUI_UnitFrames.frames and ns.QUI_UnitFrames.frames.pet end,
    bossFrames = function()
        local frames = {}
        if ns.QUI_UnitFrames and ns.QUI_UnitFrames.frames then
            for i = 1, 5 do
                local f = ns.QUI_UnitFrames.frames["boss" .. i]
                if f then table.insert(frames, f) end
            end
        end
        return #frames > 0 and frames or nil
    end,
    playerCastbar = function() return ns.QUI_Castbar and ns.QUI_Castbar.castbars and ns.QUI_Castbar.castbars["player"] end,
    targetCastbar = function() return ns.QUI_Castbar and ns.QUI_Castbar.castbars and ns.QUI_Castbar.castbars["target"] end,
    focusCastbar = function() return ns.QUI_Castbar and ns.QUI_Castbar.castbars and ns.QUI_Castbar.castbars["focus"] end,
    petCastbar = function() return ns.QUI_Castbar and ns.QUI_Castbar.castbars and ns.QUI_Castbar.castbars["pet"] end,
    totCastbar = function() return ns.QUI_Castbar and ns.QUI_Castbar.castbars and ns.QUI_Castbar.castbars["targettarget"] end,
    bar1 = function()
        local owned = ns.ActionBarsOwned and ns.ActionBarsOwned.containers and ns.ActionBarsOwned.containers["bar1"]
        if owned then return owned end
        return nil
    end,
    bar2 = function()
        local owned = ns.ActionBarsOwned and ns.ActionBarsOwned.containers and ns.ActionBarsOwned.containers["bar2"]
        if owned then return owned end
        return nil
    end,
    bar3 = function()
        local owned = ns.ActionBarsOwned and ns.ActionBarsOwned.containers and ns.ActionBarsOwned.containers["bar3"]
        if owned then return owned end
        return nil
    end,
    bar4 = function()
        local owned = ns.ActionBarsOwned and ns.ActionBarsOwned.containers and ns.ActionBarsOwned.containers["bar4"]
        if owned then return owned end
        return nil
    end,
    bar5 = function()
        local owned = ns.ActionBarsOwned and ns.ActionBarsOwned.containers and ns.ActionBarsOwned.containers["bar5"]
        if owned then return owned end
        return nil
    end,
    bar6 = function()
        local owned = ns.ActionBarsOwned and ns.ActionBarsOwned.containers and ns.ActionBarsOwned.containers["bar6"]
        if owned then return owned end
        return nil
    end,
    bar7 = function()
        local owned = ns.ActionBarsOwned and ns.ActionBarsOwned.containers and ns.ActionBarsOwned.containers["bar7"]
        if owned then return owned end
        return nil
    end,
    bar8 = function()
        local owned = ns.ActionBarsOwned and ns.ActionBarsOwned.containers and ns.ActionBarsOwned.containers["bar8"]
        if owned then return owned end
        return nil
    end,
    petBar = function()
        local owned = ns.ActionBarsOwned and ns.ActionBarsOwned.containers and ns.ActionBarsOwned.containers["pet"]
        if owned then return owned end
        return nil
    end,
    stanceBar = function()
        local owned = ns.ActionBarsOwned and ns.ActionBarsOwned.containers and ns.ActionBarsOwned.containers["stance"]
        if owned then return owned end
        return nil
    end,
    microMenu = function()
        local owned = ns.ActionBarsOwned and ns.ActionBarsOwned.containers and ns.ActionBarsOwned.containers["microbar"]
        if owned then return owned end
        return nil
    end,
    bagBar = function()
        local owned = ns.ActionBarsOwned and ns.ActionBarsOwned.containers and ns.ActionBarsOwned.containers["bags"]
        if owned then return owned end
        return nil
    end,
    extraActionButton = function()
        local owned = _G["QUI_extraActionButtonHolder"]
        if owned then return owned end
        if IsBlizzardElementDisabled("extraActionButton") then return nil end
        return _G["ExtraActionBarFrame"]
    end,
    zoneAbility = function()
        local owned = _G["QUI_zoneAbilityHolder"]
        if owned then return owned end
        if IsBlizzardElementDisabled("zoneAbility") then return nil end
        return _G["ZoneAbilityFrame"]
    end,
    leaveVehicle = function() return _G["MainMenuBarVehicleLeaveButton"] end,
    equipmentDurability = function() return _G["DurabilityFrame"] end,
    brezCounter = function() return _G["QUI_BrezCounter"] end,
    atonementCounter = function() return _G["QUI_AtonementCounter"] end,
    combatTimer = function() return _G["QUI_CombatTimer"] end,
    lustTimer = function() return _G["QUI_LustTimer"] end,
    rangeCheck = function() return _G["QUI_RangeCheckFrame"] end,
    actionTracker = function() return _G["QUI_ActionTracker"] end,
    xpTracker = function() return _G["QUI_XPTracker"] end,
    skyriding = function() return _G["QUI_Skyriding"] end,
    petWarning = function() return _G["QUI_PetWarningFrame"] end,
    focusCastAlert = function() return _G["QUI_FocusCastAlertFrame"] end,
    missingRaidBuffs = function() return _G["QUI_MissingRaidBuffs"] end,
    mplusTimer = function() return _G["QUI_MPlusTimerFrame"] end,
    preyTracker = function() return _G["QUI_PreyTracker"] end,
    incomingCasts = function() return _G["QUI_IncomingCasts"] end,
    crosshair = function() return _G["QUI_Crosshair"] end,
    totemBar = function()
        local owned = ns.QUI_TotemBar and ns.QUI_TotemBar.container
        if owned then return owned end
        if IsModuleDisabled("totemBar") then return nil end
        return _G["TotemFrame"]
    end,
    raidMarkersBar = function()
        return ns.QUI_RaidMarkersBar and ns.QUI_RaidMarkersBar.container
    end,
    readyCheck = function()
        if IsModuleDisabled("general", "skinReadyCheck") then return nil end
        return _G["ReadyCheckFrame"]
    end,
    bonusRollFrame = function() return _G["BonusRollFrame"] end,
    consumables = function() return _G["QUI_ConsumablesFrame"] end,
    alertAnchor = function() return _G["QUI_AlertFrameHolder"] end,
    toastAnchor = function() return _G["QUI_EventToastHolder"] end,
    bnetToastAnchor = function() return _G["QUI_BNetToastHolder"] end,
    tooltipAnchor = function() return _G["QUI_TooltipAnchor"] end,
    powerBarAlt = function() return _G["QUI_AltPowerBar"] end,
    lootFrame = function() return _G["QUI_LootFrame"] end,
    lootRollAnchor = function() return _G["QUI_LootRollAnchor"] end,
    partyKeystones = function() return _G["QUIKeyTrackerFrame"] end,
    partyFrames = function()
        local GFEM = ns.QUI_GroupFrameEditMode
        if GFEM then
            local active = GFEM:GetActiveFrame("party")
            if active then return active end
        end
        local GF = ns.QUI_GroupFrames
        if GF and GF.anchorFrames and GF.anchorFrames.party then
            return GF.anchorFrames.party
        end
        return GF and GF.headers and GF.headers.party
    end,
    raidFrames = function()
        local GFEM = ns.QUI_GroupFrameEditMode
        if GFEM then
            local active = GFEM:GetActiveFrame("raid")
            if active then return active end
        end
        local GF = ns.QUI_GroupFrames
        if GF and GF.anchorFrames and GF.anchorFrames.raid then
            return GF.anchorFrames.raid
        end
        return GF and GF.headers and GF.headers.raid
    end,
    minimap = function() return _G["QUI_MinimapAnchor"] or _G["Minimap"] end,
    datatextPanel = function() return _G["QUI_DatatextPanel"] end,
    objectiveTracker = function()
        local state = managedReparentState["objectiveTracker"]
        return state and state.holder or nil
    end,
    topCenterWidgets = function()
        local state = managedReparentState["topCenterWidgets"]
        return state and state.holder or nil
    end,
    belowMinimapWidgets = function()
        local state = managedReparentState["belowMinimapWidgets"]
        return state and state.holder or nil
    end,
    buffFrame = function()
        local owned = _G["QUI_BuffIconContainer"]
        if owned then return owned end
        if IsModuleDisabled("buffBorders", "enableBuffs") then return nil end
        return nil
    end,
    debuffFrame = function()
        local owned = _G["QUI_DebuffIconContainer"]
        if owned then return owned end
        if IsModuleDisabled("buffBorders", "enableDebuffs") then return nil end
        return nil
    end,
    chatFrame1 = function()
        if IsModuleDisabled("chat") then return nil end
        return _G["QUI_CustomChatFrame"]
    end,
    dandersParty = function()
        if ns.QUI_DandersFrames and ns.QUI_DandersFrames:IsAvailable() then
            local frames = ns.QUI_DandersFrames:GetContainerFrames("party")
            return frames and frames[1]
        end
    end,
    dandersRaid = function()
        if ns.QUI_DandersFrames and ns.QUI_DandersFrames:IsAvailable() then
            local frames = ns.QUI_DandersFrames:GetContainerFrames("raid")
            return frames and frames[1]
        end
    end,
    abilityTimelineTimeline = function()
        return _G["AbilityTimelineFrame"]
    end,
    abilityTimelineBigIcon = function()
        return _G["AbilityTimelineBigIconFrame"]
    end,
}

local CUSTOM_TRACKER_ANCHOR_PREFIX = "customTracker:"
local CUSTOM_TRACKER_ANCHOR_CATEGORY = "Cooldown Manager & Custom Tracker Bars"
local CUSTOM_TRACKER_ANCHOR_CATEGORY_ORDER = 90

local function GetCustomTrackerBarIDFromAnchorKey(key)
    if type(key) ~= "string" then return nil end
    if key:sub(1, #CUSTOM_TRACKER_ANCHOR_PREFIX) ~= CUSTOM_TRACKER_ANCHOR_PREFIX then
        return nil
    end
    local barID = key:sub(#CUSTOM_TRACKER_ANCHOR_PREFIX + 1)
    if barID == "" then
        return nil
    end
    return barID
end

local function ResolveCustomTrackerFrameForKey(key)
    local barID = GetCustomTrackerBarIDFromAnchorKey(key)
    if not barID then
        return nil
    end

    local migratedKey = "cdmCustom_customBar_" .. tostring(barID)
    local migratedResolver = FRAME_RESOLVERS and FRAME_RESOLVERS[migratedKey]
    if migratedResolver then
        local frame = migratedResolver()
        if frame then
            return frame
        end
    end

    local trackerModule = QUICore and QUICore.CustomTrackers
    local activeBars = trackerModule and trackerModule.activeBars
    if not activeBars then
        return nil
    end
    return activeBars[barID]
end

HasFrameResolverForKey = function(key)
    if FRAME_RESOLVERS[key] then
        return true
    end
    return GetCustomTrackerBarIDFromAnchorKey(key) ~= nil
end

ResolveApplyFrameForKey = function(key)
    local resolver = FRAME_RESOLVERS[key]
    if resolver then
        local frame = resolver()
        if type(frame) == "table" and not frame.GetObjectType then
            frame = frame[1]
        end
        return frame
    end
    return ResolveCustomTrackerFrameForKey(key)
end

local UNSAFE_BLIZZARD_MANAGED_OVERRIDES = {
}

local SELF_ANCHORED_FRAMES = {
    partyKeystones = true,
}

local FRAME_ANCHOR_INFO = {
    cdmEssential    = { displayName = "CDM Essential Viewer",  category = "Cooldown Manager & Custom Tracker Bars",  order = 1 },
    cdmUtility      = { displayName = "CDM Utility Viewer",    category = "Cooldown Manager & Custom Tracker Bars",  order = 2 },
    buffIcon        = { displayName = "CDM Buff Icons",        category = "Cooldown Manager & Custom Tracker Bars",  order = 3 },
    buffBar         = { displayName = "CDM Buff Bars",         category = "Cooldown Manager & Custom Tracker Bars",  order = 4 },
    rotationAssistIcon = { displayName = "CDM Rotation Assist Icon", category = "Cooldown Manager & Custom Tracker Bars", order = 5 },
    primaryPower    = { displayName = "Primary Power Bar",     category = "Resource Bars",     order = 1 },
    secondaryPower  = { displayName = "Secondary Power Bar",   category = "Resource Bars",     order = 2 },
    playerFrame     = { displayName = "Player Frame",          category = "Unit Frames",       order = 1 },
    targetFrame     = { displayName = "Target Frame",          category = "Unit Frames",       order = 2 },
    totFrame        = { displayName = "Target of Target",      category = "Unit Frames",       order = 3 },
    focusFrame      = { displayName = "Focus Frame",           category = "Unit Frames",       order = 4 },
    petFrame        = { displayName = "Pet Frame",             category = "Unit Frames",       order = 5 },
    bossFrames      = { displayName = "Boss Frames",           category = "Unit Frames",       order = 6 },
    playerCastbar   = { displayName = "Player Castbar",        category = "Castbars",          order = 1 },
    targetCastbar   = { displayName = "Target Castbar",        category = "Castbars",          order = 2 },
    focusCastbar    = { displayName = "Focus Castbar",         category = "Castbars",          order = 3 },
    petCastbar      = { displayName = "Pet Castbar",           category = "Castbars",          order = 4 },
    totCastbar      = { displayName = "Target of Target Castbar", category = "Castbars",       order = 5 },
    bar1            = { displayName = "Action Bar 1",          category = "Action Bars",       order = 1 },
    bar2            = { displayName = "Action Bar 2",          category = "Action Bars",       order = 2 },
    bar3            = { displayName = "Action Bar 3",          category = "Action Bars",       order = 3 },
    bar4            = { displayName = "Action Bar 4",          category = "Action Bars",       order = 4 },
    bar5            = { displayName = "Action Bar 5",          category = "Action Bars",       order = 5 },
    bar6            = { displayName = "Action Bar 6",          category = "Action Bars",       order = 6 },
    bar7            = { displayName = "Action Bar 7",          category = "Action Bars",       order = 7 },
    bar8            = { displayName = "Action Bar 8",          category = "Action Bars",       order = 8 },
    petBar          = { displayName = "Pet Action Bar",        category = "Action Bars",       order = 9 },
    stanceBar       = { displayName = "Stance Bar",            category = "Action Bars",       order = 10 },
    microMenu       = { displayName = "Micro Menu",            category = "Action Bars",       order = 11 },
    bagBar          = { displayName = "Bag Bar",               category = "Action Bars",       order = 12 },
    extraActionButton = { displayName = "Extra Action Button", category = "Action Bars",       order = 13 },
    zoneAbility     = { displayName = "Zone Ability Button",   category = "Action Bars",       order = 14 },
    leaveVehicle    = { displayName = "Leave Vehicle Button", category = "Action Bars",       order = 15 },
    equipmentDurability = { displayName = "Equipment Durability", category = "Display",        order = 10 },
    brezCounter     = { displayName = "Brez Counter",          category = "QoL",               order = 1 },
    atonementCounter = { displayName = "Atonement Counter",    category = "QoL",               order = 2 },
    combatTimer     = { displayName = "Combat Timer",          category = "QoL",               order = 3 },
    lustTimer       = { displayName = "Lust Timer",            category = "QoL",               order = 14 },
    rangeCheck      = { displayName = "Target Distance Bracket Display", category = "QoL",      order = 4 },
    actionTracker   = { displayName = "Action Tracker",        category = "QoL",               order = 5 },
    xpTracker       = { displayName = "XP Tracker",            category = "QoL",               order = 6 },
    skyriding       = { displayName = "Skyriding",             category = "QoL",               order = 7 },
    petWarning      = { displayName = "Pet Warning",           category = "QoL",               order = 8 },
    focusCastAlert  = { displayName = "Focus Cast Alert",      category = "QoL",               order = 9 },
    missingRaidBuffs = { displayName = "Missing Raid Buffs",   category = "QoL",               order = 10 },
    mplusTimer      = { displayName = "M+ Timer",              category = "QoL",               order = 11 },
    readyCheck      = { displayName = "Ready Check",           category = "QoL",               order = 12 },
    preyTracker     = { displayName = "Prey Tracker",          category = "QoL",               order = 13 },
    incomingCasts   = { displayName = "Incoming Casts",        category = "QoL",               order = 15 },
    partyFrames     = { displayName = "Party Frames",           category = "Group Frames",      order = 1 },
    raidFrames      = { displayName = "Raid Frames",            category = "Group Frames",      order = 2 },
    minimap         = { displayName = "Minimap",               category = "Display",           order = 1 },
    objectiveTracker = { displayName = "Objective Tracker",    category = "Display",           order = 2 },
    topCenterWidgets = { displayName = "Top Center Widgets",  category = "Display",           order = 3 },
    belowMinimapWidgets = { displayName = "Below Minimap Widgets", category = "Display",      order = 4 },
    buffFrame       = { displayName = "Buff Frame",            category = "Display",           order = 5 },
    debuffFrame     = { displayName = "Debuff Frame",          category = "Display",           order = 6 },
    chatFrame1      = { displayName = "Chat Frame",            category = "Display",           order = 7 },
    datatextPanel   = { displayName = "Datatext Panel",        category = "Display",           order = 8 },
    bonusRollFrame  = { displayName = "Bonus Roll",            category = "Display",           order = 9 },
    dandersParty    = { displayName = "DandersFrames Party",   category = "External",          order = 1 },
    dandersRaid     = { displayName = "DandersFrames Raid",    category = "External",          order = 2 },
    abilityTimelineTimeline = { displayName = "AbilityTimeline Timeline", category = "External", order = 3 },
    abilityTimelineBigIcon = { displayName = "AbilityTimeline Big Icon", category = "External", order = 4 },
}
ns.FRAME_ANCHOR_INFO = FRAME_ANCHOR_INFO

_G.QUI_RegisterFrameResolver = function(key, info)
    if not key then return end
    if info.resolver then
        FRAME_RESOLVERS[key] = info.resolver
    end
    if info.displayName then
        FRAME_ANCHOR_INFO[key] = {
            displayName = info.displayName,
            category = info.category or "Cooldown Manager & Custom Tracker Bars",
            order = info.order or 100,
        }
    end
    if info.category == "Cooldown Manager & Custom Tracker Bars" and CDM_LOGICAL_SIZE_KEYS then
        CDM_LOGICAL_SIZE_KEYS[key] = true
    end
    if info.resolver and QUI_Anchoring and QUI_Anchoring.RegisterAnchorTarget then
        local frame = info.resolver()
        if frame then
            QUI_Anchoring:RegisterAnchorTarget(key, frame, {
                displayName = info.displayName or key,
                category = info.category or "Cooldown Manager & Custom Tracker Bars",
                categoryOrder = info.order or 100,
                order = info.order or 100,
            })
        end
    end
end

_G.QUI_UnregisterFrameResolver = function(key)
    if not key then return end
    FRAME_RESOLVERS[key] = nil
    FRAME_ANCHOR_INFO[key] = nil
    if CDM_LOGICAL_SIZE_KEYS then
        CDM_LOGICAL_SIZE_KEYS[key] = nil
    end
end

local hideWithParentHidden = {}
local resolveUnreadableRetried = {}
local RESOLVE_RETRY_MAX_ARMS = 8
local function clearResolveRetrySlots(originKey, retryKey)
    local byKey = resolveUnreadableRetried[originKey]
    if byKey then
        byKey[retryKey or "apply"] = nil
        if next(byKey) == nil then
            resolveUnreadableRetried[originKey] = nil
        end
    end
    local bySlot = pendingCombatConsumerOps[originKey]
    if bySlot then
        bySlot[retryKey or "apply"] = nil
        if next(bySlot) == nil then
            pendingCombatConsumerOps[originKey] = nil
        end
    end
end
local hideWithParentUnreadableRetried = {}
local _visibilityHooked = {}
local FRAME_ANCHOR_FALLBACKS
local HUD_MIN_WIDTH_DEFAULT = (ns.Helpers and ns.Helpers.HUD_MIN_WIDTH_DEFAULT) or 200

FRAME_ANCHOR_FALLBACKS = {
    secondaryPower = "primaryPower",
    primaryPower   = "cdmEssential",
    petFrame       = "playerFrame",
    totFrame       = "targetFrame",
}

local function ResolveFrameForKey(key)
    do
        local customTrackerFrame = ResolveCustomTrackerFrameForKey(key)
        if customTrackerFrame then return customTrackerFrame end
    end

    local resolver = FRAME_RESOLVERS[key]
    if resolver then
        local frame = resolver()
        if type(frame) == "table" and not frame.GetObjectType then
            frame = frame[1]
        end
        if frame then return frame end
    end

    local registered = QUI_Anchoring.anchorTargets[key]
    if registered then return registered.frame end

    return nil
end

local function ProbeVisibilityHookMembers(frame)
    return frame.HookScript ~= nil, frame.SetAlpha ~= nil
end

local function InvokeGetAlpha(frame)
    return frame:GetAlpha()
end

local function InstallVisibilityHook(frame)
    if (nsHelpers and nsHelpers.IsSecretValue and nsHelpers.IsSecretValue(frame))
        or frame == nil then
        return
    end
    local okProbe, canHook, wantAlpha = pcall(ProbeVisibilityHookMembers, frame)
    if not okProbe or not canHook then return end
    local hooked = _visibilityHooked[frame]
    if not hooked then
        hooked = {}
        _visibilityHooked[frame] = hooked
    end
    if hooked.onShow and hooked.onHide and (hooked.alpha or not wantAlpha) then
        return
    end
    local function onVisibilityChanged()
        if QUI_Anchoring then
            QUI_Anchoring:ApplyAllFrameAnchors()
        end
    end
    if not hooked.onShow then
        local ok, success = ns.SafeCallMethod("best-effort-style", frame, "HookScript", "OnShow", onVisibilityChanged)
        if ok and success then hooked.onShow = true end
    end
    if not hooked.onHide then
        local ok, success = ns.SafeCallMethod("best-effort-style", frame, "HookScript", "OnHide", onVisibilityChanged)
        if ok and success then hooked.onHide = true end
    end
    if wantAlpha and not hooked.alpha then
        local okAlpha, curAlpha = pcall(InvokeGetAlpha, frame)
        local curAlphaSecret = not okAlpha
            or (nsHelpers and nsHelpers.IsSecretValue and nsHelpers.IsSecretValue(curAlpha))
        local wasAlphaHidden
        if not curAlphaSecret and type(curAlpha) == "number" then
            wasAlphaHidden = curAlpha < 0.01
        end
        local okHook = ns.SafeCall("best-effort-style", hooksecurefunc, frame, "SetAlpha", function(self, alpha)
            if type(alpha) ~= "number" then return end
            if nsHelpers and nsHelpers.IsSecretValue and nsHelpers.IsSecretValue(alpha) then
                return
            end
            local isAlphaHidden = alpha < 0.01
            if isAlphaHidden ~= wasAlphaHidden then
                wasAlphaHidden = isAlphaHidden
                onVisibilityChanged()
            end
        end)
        if okHook then hooked.alpha = true end
    end
end

local function ResolveParentFrame(parentKey, originKey, retryOp, retryKey)
    if not parentKey or parentKey == "screen" or parentKey == "disabled" then
        if originKey then clearResolveRetrySlots(originKey, retryKey) end
        return UIParent, nil
    end

    local key = parentKey
    local visited = {}
    if originKey then
        visited[originKey] = true
    end

    local anchoringDB = QUICore and QUICore.db and QUICore.db.profile
        and QUICore.db.profile.frameAnchoring

    local lastChainSettings = nil

    while key do
        if visited[key] then
            local fallback = FRAME_ANCHOR_FALLBACKS[key]
            if fallback and not visited[fallback] then
                key = fallback
            else
                break
            end
        else
            visited[key] = true

            local frame = ResolveFrameForKey(key)

            local visible = false
            if frame then
                visible = nsHelpers.FrameVisibleSecure(frame, 0)
            end

            if visible == true then
                InstallVisibilityHook(frame)
                if originKey then clearResolveRetrySlots(originKey, retryKey) end
                return frame, lastChainSettings
            end

            if visible == nil then
                InstallVisibilityHook(frame)
                if InCombatLockdown() then
                    pendingAnchoredFrameUpdateAfterCombat = true
                    latchCombatConsumerOp(originKey, retryKey, retryOp)
                elseif originKey and frame then
                    local byKey = resolveUnreadableRetried[originKey]
                    if not byKey then
                        byKey = {}
                        resolveUnreadableRetried[originKey] = byKey
                    end
                    local slotKey = retryKey or "apply"
                    local state = byKey[slotKey]
                    if not state then
                        state = { burned = {} }
                        byKey[slotKey] = state
                    end
                    state.op = retryOp or true
                    if not state.pending and not state.burned[frame]
                        and (state.arms or 0) < RESOLVE_RETRY_MAX_ARMS then
                        state.arms = (state.arms or 0) + 1
                        state.burned[frame] = true
                        state.pending = true
                        C_Timer.After(0, function()
                            local liveByKey = resolveUnreadableRetried[originKey]
                            if not liveByKey or liveByKey[slotKey] ~= state then
                                return
                            end
                            state.pending = false
                            local op = state.op
                            if InCombatLockdown() then
                                if type(op) == "function" then
                                    latchCombatConsumerOp(originKey, slotKey, op)
                                else
                                    pendingAnchoredFrameUpdateAfterCombat = true
                                end
                                return
                            end
                            local reapply
                            if type(op) == "function" then
                                reapply = op
                            else
                                reapply = _G.QUI_ApplyFrameAnchor
                            end
                            if reapply then reapply(originKey) end
                        end)
                    end
                end
                return frame, lastChainSettings, true
            end

            if frame and ns.QUI_LayoutMode and ns.QUI_LayoutMode.isActive then
                InstallVisibilityHook(frame)
                if originKey then clearResolveRetrySlots(originKey, retryKey) end
                return frame, lastChainSettings
            end

            if frame then
                InstallVisibilityHook(frame)
            end

            local fallback = FRAME_ANCHOR_FALLBACKS[key]
            if fallback then
                key = fallback
            else
                local chainEntry = GetSavedFrameAnchorSettings(anchoringDB, key)
                local chainParent = chainEntry and chainEntry.parent
                if chainParent and chainParent ~= "screen" and chainParent ~= "disabled" then
                    lastChainSettings = chainEntry
                    key = chainParent
                else
                    if originKey then clearResolveRetrySlots(originKey, retryKey) end
                    return frame or UIParent, lastChainSettings
                end
            end
        end
    end

    if originKey then clearResolveRetrySlots(originKey, retryKey) end
    return UIParent, lastChainSettings
end

---@type fun(...)
_G.QUI_UpdateCDMAnchorProxyFrames = function() end
_G.QUI_GetCDMAnchorProxyFrame = function() return nil end

local function ClearCustomTrackerAnchorTargets()
    for name in pairs(QUI_Anchoring.anchorTargets) do
        if GetCustomTrackerBarIDFromAnchorKey(name) then
            QUI_Anchoring.anchorTargets[name] = nil
        end
    end
end

local function RegisterCustomTrackerAnchorTargets(self)
    ClearCustomTrackerAnchorTargets()

    local profile = QUICore and QUICore.db and QUICore.db.profile
    local bars = profile and profile.customTrackers and profile.customTrackers.bars
    if type(bars) ~= "table" then
        return
    end

    for index, barConfig in ipairs(bars) do
        local barID = barConfig and barConfig.id
        if type(barID) == "string" and barID ~= "" then
            local anchorKey = CUSTOM_TRACKER_ANCHOR_PREFIX .. barID
            local frame = ResolveCustomTrackerFrameForKey(anchorKey)
            if frame then
                local displayName = barConfig.name
                if type(displayName) ~= "string" or displayName == "" then
                    displayName = ("CDM Bar %d"):format(index)
                end
                self:RegisterAnchorTarget(anchorKey, frame, {
                    displayName = displayName,
                    category = CUSTOM_TRACKER_ANCHOR_CATEGORY,
                    categoryOrder = CUSTOM_TRACKER_ANCHOR_CATEGORY_ORDER,
                    order = index,
                })
            end
        end
    end
end

function QUI_Anchoring:RegisterAllFrameTargets()
    for key, resolver in pairs(FRAME_RESOLVERS) do
        local frame = resolver()
        if type(frame) == "table" and not frame.GetObjectType then
            frame = frame[1]
        end
        if frame then
            local info = FRAME_ANCHOR_INFO[key] or {}
            self:RegisterAnchorTarget(key, frame, {
                displayName = info.displayName or key,
                category = info.category,
                categoryOrder = info.order,
                order = info.order,
            })
        end
    end
    RegisterCustomTrackerAnchorTargets(self)
end

local function SetFrameOverride(frame, active, key)
    if not frame then return end
    if type(frame) == "table" and not frame.GetObjectType then
        for _, f in ipairs(frame) do
            QUI_Anchoring.layoutOwnedFrames[f] = active and key or nil
        end
        if BossTargetFrameContainer then
            QUI_Anchoring.layoutOwnedFrames[BossTargetFrameContainer] = active and key or nil
        end
    else
        QUI_Anchoring.layoutOwnedFrames[frame] = active and key or nil
    end
end

local VALID_BOSS_GROW_DIRECTION = {
    UP = true,
    DOWN = true,
    LEFT = true,
    RIGHT = true,
}

local function GetBossFrameLayout()
    local profile = QUICore and QUICore.db and QUICore.db.profile
    local boss = profile and profile.quiUnitFrames and profile.quiUnitFrames.boss
    if type(boss) ~= "table" then return "DOWN", 35, 35 end

    local direction = rawget(boss, "growDirection") or boss.growDirection or "DOWN"
    if not VALID_BOSS_GROW_DIRECTION[direction] then
        direction = "DOWN"
    end

    local legacySpacing = rawget(boss, "spacing")
    if legacySpacing == nil then
        legacySpacing = boss.spacing
    end
    legacySpacing = tonumber(legacySpacing) or 35

    local xSpacing = rawget(boss, "xSpacing")
    if xSpacing == nil then
        xSpacing = legacySpacing
    end
    xSpacing = tonumber(xSpacing) or legacySpacing

    local ySpacing = rawget(boss, "ySpacing")
    if ySpacing == nil then
        ySpacing = legacySpacing
    end
    ySpacing = tonumber(ySpacing) or legacySpacing

    return direction, xSpacing, ySpacing
end

local function GetBossStackPoint(direction, xSpacing, ySpacing)
    if direction == "UP" then
        return "BOTTOM", "TOP", 0, ySpacing
    elseif direction == "LEFT" then
        return "RIGHT", "LEFT", -xSpacing, 0
    elseif direction == "RIGHT" then
        return "LEFT", "RIGHT", xSpacing, 0
    end
    return "TOP", "BOTTOM", 0, -ySpacing
end

local hookedParentFrames = {}
local function SetupDebugInstrumentation()
    local mp = ns._memprobes or {}; ns._memprobes = mp
    mp[#mp + 1] = { name = "Anch_anchorGuardedFrames",   tbl = _anchorGuardedFrames }
    mp[#mp + 1] = { name = "Anch_setPointGuardedFrames", tbl = _setPointGuardedFrames }
    mp[#mp + 1] = { name = "Anch_visibilityHooked", tbl = _visibilityHooked }
    mp[#mp + 1] = { name = "Anch_hookedParentFrames", tbl = hookedParentFrames }
end
if ns.DebugRegister then
    ns.DebugRegister(SetupDebugInstrumentation)
else
    SetupDebugInstrumentation()
end

CDM_LOGICAL_SIZE_KEYS.cdmEssential = true
CDM_LOGICAL_SIZE_KEYS.cdmUtility = true
CDM_LOGICAL_SIZE_KEYS.buffIcon = true
CDM_LOGICAL_SIZE_KEYS.buffBar = true
local CASTBAR_ANCHOR_KEYS = {
    playerCastbar = true,
    targetCastbar = true,
    focusCastbar = true,
    petCastbar = true,
    totCastbar = true,
}

local DYNAMIC_SIZE_ANCHOR_KEYS = {
    buffIcon = true,
    buffBar = true,
    buffFrame = true,
    debuffFrame = true,
    totemBar = true,
}

local function IsDynamicSizeAnchorKey(key)
    if not key then return false end
    if DYNAMIC_SIZE_ANCHOR_KEYS[key] then return true end
    if type(key) == "string" and key:find("^cdmCustom_") then return true end
    return false
end

local FORBIDDEN_AURA_KEYS = { buffFrame = true, debuffFrame = true }

local function LiveAuraContainerFor(key)
    if not FORBIDDEN_AURA_KEYS[key] then return nil end
    local resolver = FRAME_RESOLVERS[key]
    local mover = resolver and resolver()
    if not mover then return nil end
    return mover._quiLiveContainer, mover
end

do
    local ResolveParentFrameBase = ResolveParentFrame
    ResolveParentFrame = function(parentKey, originKey, retryOp, retryKey)
        if FORBIDDEN_AURA_KEYS[parentKey] and originKey and FORBIDDEN_AURA_KEYS[originKey] then
            local live = LiveAuraContainerFor(parentKey)
            if live then
                clearResolveRetrySlots(originKey, retryKey)
                return live
            end
        end
        return ResolveParentFrameBase(parentKey, originKey, retryOp, retryKey)
    end
end

local function GetPointOffsetForRect(point, width, height)
    local halfW = (width or 0) * 0.5
    local halfH = (height or 0) * 0.5
    if point == "TOPLEFT" then
        return -halfW, halfH
    elseif point == "TOP" then
        return 0, halfH
    elseif point == "TOPRIGHT" then
        return halfW, halfH
    elseif point == "LEFT" then
        return -halfW, 0
    elseif point == "RIGHT" then
        return halfW, 0
    elseif point == "BOTTOMLEFT" then
        return -halfW, -halfH
    elseif point == "BOTTOM" then
        return 0, -halfH
    elseif point == "BOTTOMRIGHT" then
        return halfW, -halfH
    end
    return 0, 0
end

local function GetFrameAnchorRect(frame, key)
    if not frame then return 1, 1 end

    local width, height

    if CDM_LOGICAL_SIZE_KEYS[key] then
        local vs = _G.QUI_GetCDMViewerState and _G.QUI_GetCDMViewerState(frame)
        if vs then
            width = vs.row1Width or vs.iconWidth
            height = vs.totalHeight
        end
    end

    if not width or width <= 0 then
        width = frame.GetWidth and frame:GetWidth() or 1
    end
    if not height or height <= 0 then
        height = frame.GetHeight and frame:GetHeight() or 1
    end

    if not CDM_LOGICAL_SIZE_KEYS[key] and frame.GetScale then
        local fScale = frame:GetScale() or 1
        if fScale > 0 and fScale ~= 1 then
            width = width * fScale
            height = height * fScale
        end
    end

    return math.max(1, width), math.max(1, height)
end

local function GetParentAnchorRect(frame, parentKey)
    if not frame then return 1, 1 end

    if frame._quiHostMover then
        frame = frame._quiHostMover
    end

    local width, height

    if parentKey then
        if parentKey == "essential" then parentKey = "cdmEssential"
        elseif parentKey == "utility" then parentKey = "cdmUtility" end

        if CDM_LOGICAL_SIZE_KEYS[parentKey] then
            local resolver = FRAME_RESOLVERS[parentKey]
            local sourceFrame = resolver and resolver()
            if sourceFrame then
                local vs = _G.QUI_GetCDMViewerState and _G.QUI_GetCDMViewerState(sourceFrame)
                if vs then
                    width = vs.row1Width or vs.iconWidth
                    height = vs.totalHeight
                end
            end
        end
    end

    if not width or width <= 0 then
        width = frame.GetWidth and frame:GetWidth() or 1
    end
    if not height or height <= 0 then
        height = frame.GetHeight and frame:GetHeight() or 1
    end

    return math.max(1, width), math.max(1, height)
end

local LAYOUT_HANDLE_MIN = 20
local TINY_ANCHOR_THRESHOLD = 3

local function ComputeCenterOffsetsForAnchor(frame, key, parentFrame, sourcePoint, targetPoint, offsetX, offsetY, parentKey)
    local frameW, frameH = GetFrameAnchorRect(frame, key)
    local parentW, parentH = GetParentAnchorRect(parentFrame, parentKey)

    if parentFrame and parentFrame ~= UIParent then
        if parentW < TINY_ANCHOR_THRESHOLD then parentW = LAYOUT_HANDLE_MIN end
        if parentH < TINY_ANCHOR_THRESHOLD then parentH = LAYOUT_HANDLE_MIN end
    end
    if frameW < TINY_ANCHOR_THRESHOLD then frameW = LAYOUT_HANDLE_MIN end
    if frameH < TINY_ANCHOR_THRESHOLD then frameH = LAYOUT_HANDLE_MIN end

    local targetX, targetY = GetPointOffsetForRect(targetPoint or "CENTER", parentW, parentH)
    local sourceX, sourceY = GetPointOffsetForRect(sourcePoint or "CENTER", frameW, frameH)

    return (targetX + (offsetX or 0) - sourceX), (targetY + (offsetY or 0) - sourceY)
end

local function IsSizeStableAnchoringEnabled(settings)
    if type(settings) ~= "table" then
        return true
    end
    return settings.sizeStable ~= false
end

local CASTBAR_UNIT_KEY_MAP = {
    playerCastbar = "player",
    targetCastbar = "target",
    focusCastbar  = "focus",
    petCastbar    = "pet",
    totCastbar    = "targettarget",
}

local function GetCastbarConfiguredWidth(key)
    local unitKey = CASTBAR_UNIT_KEY_MAP[key]
    if not unitKey then return nil end
    local db = QUICore and QUICore.db
    if not db then return nil end
    local unitSettings = db.profile and db.profile.unitframes and db.profile.unitframes[unitKey]
    local castSettings = unitSettings and unitSettings.castbar
    local w = castSettings and castSettings.width
    return (type(w) == "number" and w > 0) and w or nil
end

local suppressAutoSizingKeys = {}

local function ApplyAutoSizing(frame, settings, parentFrame, key)
    if not frame then return end
    if key then
        for i = #suppressAutoSizingKeys, 1, -1 do
            local keys = suppressAutoSizingKeys[i]
            if keys and keys[key] then return end
        end
    end

    if settings.autoWidth and parentFrame and parentFrame ~= UIParent
        and not parentFrame._quiHostMover
    then
        local ok, parentWidth = pcall(function() return parentFrame:GetWidth() end)
        if ok and parentWidth and parentWidth > 0 then
            local isResourceBar = (key == "primaryPower" or key == "secondaryPower")
            if isResourceBar then
                local parentKey = settings.parent
                if parentKey == "essential" then parentKey = "cdmEssential"
                elseif parentKey == "utility" then parentKey = "cdmUtility" end
                local resolver = parentKey and FRAME_RESOLVERS[parentKey]
                local sourceFrame = resolver and resolver()
                if sourceFrame then
                    local contentWidth
                    if CDM_LOGICAL_SIZE_KEYS[parentKey] then
                        local vs = _G.QUI_GetCDMViewerState and _G.QUI_GetCDMViewerState(sourceFrame)
                        contentWidth = vs and vs.rawContentWidth
                    end
                    if not contentWidth or contentWidth <= 0 then
                        local frameOk, frameWidth = pcall(function() return sourceFrame:GetWidth() end)
                        if frameOk and frameWidth and frameWidth > 0 then
                            contentWidth = frameWidth
                        end
                    end
                    if contentWidth and contentWidth > 0 then
                        parentWidth = contentWidth
                    end
                end
            end
            local adjustedWidth = parentWidth + (settings.widthAdjust or 0)
            if adjustedWidth > 0 then
                ns.SafeCallMethod("best-effort-style", frame, "SetWidth", adjustedWidth)
                if isResourceBar then
                    C_Timer.After(0, function()
                        if key == "primaryPower" then
                            if QUICore and QUICore.UpdatePowerBar then QUICore:UpdatePowerBar() end
                        elseif key == "secondaryPower" then
                            if QUICore and QUICore.UpdateSecondaryPowerBar then QUICore:UpdateSecondaryPowerBar() end
                        end
                    end)
                end
            end
        end

        if not hookedParentFrames[parentFrame] then
            hookedParentFrames[parentFrame] = true
            ns.SafeCallMethod("best-effort-style", parentFrame, "HookScript", "OnSizeChanged", function()
                DebouncedReapplyOverrides()
            end)
        end
    elseif settings.autoWidth and CASTBAR_ANCHOR_KEYS[key] then
        local fallbackWidth = GetCastbarConfiguredWidth(key)
        if fallbackWidth then
            ns.SafeCallMethod("best-effort-style", frame, "SetWidth", fallbackWidth)
        end
    end

    if settings.autoHeight then
        local viewer = _G.QUI_GetCDMViewerFrame and _G.QUI_GetCDMViewerFrame("essential")
        if viewer then
            local vs = _G.QUI_GetCDMViewerState and _G.QUI_GetCDMViewerState(viewer)
            local iconHeight = vs and vs.row1IconHeight
            if iconHeight and iconHeight > 0 then
                local adjustedHeight = iconHeight + (settings.heightAdjust or 0)
                if adjustedHeight > 0 then
                    ns.SafeCallMethod("best-effort-style", frame, "SetHeight", adjustedHeight)
                end
            end

            if not hookedParentFrames[viewer] then
                hookedParentFrames[viewer] = true
                ns.SafeCallMethod("best-effort-style", viewer, "HookScript", "OnSizeChanged", function()
                    DebouncedReapplyOverrides()
                end)
            end
        end
    end
end

local function ParentRestricts(parentFrame)
    if parentFrame == UIParent then return false end
    return ns.Helpers.FrameIsProtected(parentFrame)
        or ns.Helpers.FrameIsAnchoringRestricted(parentFrame)
end

local function FrameSelfRestricts(frame)
    if frame == UIParent then return false end
    return ns.Helpers.FrameIsProtected(frame)
        or ns.Helpers.FrameIsAnchoringRestricted(frame)
end

local function AnchorOrPin(key, frame, pt, parentFrame, relPt, x, y)
    local live, mover = LiveAuraContainerFor(key)
    if live then
        ns.SafeCallMethod("best-effort-style", live, "ClearAllPoints")
        ns.SafeCallMethod("best-effort-style", live, "SetPoint", pt, parentFrame, relPt, x, y)
        if mover then
            local moverParent = parentFrame
            if moverParent and moverParent._quiHostMover then
                moverParent = moverParent._quiHostMover
            end
            SmoothSetPoint(mover, pt, moverParent, relPt, x, y)
        end
        return
    end
    if parentFrame and parentFrame._quiHostMover then
        parentFrame = parentFrame._quiHostMover
    end
    if IsDynamicSizeAnchorKey(key) and ParentRestricts(parentFrame)
        and not FrameSelfRestricts(frame)
    then
        ns.Helpers.PinFrameToTargetAbsolute(frame, pt, parentFrame, relPt, x, y)
        return
    end
    SmoothSetPoint(frame, pt, parentFrame, relPt, x, y)
end

function QUI_Anchoring:ApplyFrameAnchor(key, settings)
    if type(settings) ~= "table" then return end

    if self.claimedAnchorKeys[key] then return end

    if not HasFrameResolverForKey(key) then
        return
    end

    local resolved = ResolveApplyFrameForKey(key)
    if not resolved then
        return
    end

    if UNSAFE_BLIZZARD_MANAGED_OVERRIDES[key] then
        SetFrameOverride(resolved, true, key)
        return
    end

    if SELF_ANCHORED_FRAMES[key] then
        SetFrameOverride(resolved, true, key)
        return
    end

    SetFrameOverride(resolved, true, key)

    if InCombatLockdown() and not ns._inInitSafeWindow then
        local probe = resolved
        if type(resolved) == "table" and not resolved.GetObjectType then
            probe = resolved[1]
        end
        if ns.Helpers.FrameMutationRestricted(probe) then
            pendingAnchoredFrameUpdateAfterCombat = true
            return
        end
    end

    local parentKey = settings.parent
    local parentIsSentinel = not parentKey or parentKey == "screen" or parentKey == "disabled"

    local parentFrame
    if settings.hideWithParent and not parentIsSentinel then
        local directParent = ResolveFrameForKey(parentKey)
        if directParent then
            InstallVisibilityHook(directParent)
        end
        local directVisible = ns.Helpers.FrameVisibleSecure(directParent)
        if directVisible == nil then
            if InCombatLockdown() then
                pendingAnchoredFrameUpdateAfterCombat = true
                return
            end
            if hideWithParentUnreadableRetried[key] ~= directParent then
                hideWithParentUnreadableRetried[key] = directParent
                C_Timer.After(0, function()
                    if InCombatLockdown() then
                        pendingAnchoredFrameUpdateAfterCombat = true
                        return
                    end
                    local reapply = _G.QUI_ApplyFrameAnchor
                    if reapply then reapply(key) end
                end)
            end
        else
            hideWithParentUnreadableRetried[key] = nil
            if not directVisible then
                local canMutate = not InCombatLockdown()
                    or not ns.Helpers.FrameMutationRestricted(resolved)
                if canMutate then
                    if type(resolved) == "table" and not resolved.GetObjectType then
                        for _, frame in ipairs(resolved) do ns.SafeCallMethod("best-effort-style", frame, "Hide") end
                    else
                        ns.SafeCallMethod("best-effort-style", resolved, "Hide")
                    end
                end
                hideWithParentHidden[key] = true
                return
            end
            if hideWithParentHidden[key] then
                local canMutate = not InCombatLockdown()
                    or not ns.Helpers.FrameMutationRestricted(resolved)
                if canMutate then
                    if type(resolved) == "table" and not resolved.GetObjectType then
                        for _, frame in ipairs(resolved) do ns.SafeCallMethod("best-effort-style", frame, "Show") end
                    else
                        ns.SafeCallMethod("best-effort-style", resolved, "Show")
                    end
                end
                hideWithParentHidden[key] = nil
            end
        end
        parentFrame = directParent
    elseif settings.keepInPlace and not parentIsSentinel then
        local directParent = ResolveFrameForKey(parentKey)
        if directParent then
            InstallVisibilityHook(directParent)
        end
        parentFrame = directParent or UIParent
    elseif CASTBAR_ANCHOR_KEYS[key] then
        parentFrame = ResolveFrameForKey(settings.parent) or UIParent
    else
        local chainSettings, parentUnreadable
        parentFrame, chainSettings, parentUnreadable = ResolveParentFrame(settings.parent, key)

        if parentUnreadable and InCombatLockdown() then
            return
        end

        if chainSettings then
            settings = {
                point = chainSettings.point or settings.point,
                relative = chainSettings.relative or settings.relative,
                offsetX = chainSettings.offsetX or settings.offsetX,
                offsetY = chainSettings.offsetY or settings.offsetY,
                sizeStableAnchoring = settings.sizeStableAnchoring,
            }
        end
    end

    if FORBIDDEN_AURA_KEYS[key] and parentKey and FORBIDDEN_AURA_KEYS[parentKey] then
        local liveParent = LiveAuraContainerFor(parentKey)
        if liveParent then
            parentFrame = liveParent
        end
    end

    local point = settings.point or "CENTER"
    local relative = settings.relative or "CENTER"
    local offsetX = settings.offsetX or 0
    local offsetY = settings.offsetY or 0

    local entryPoint    = settings.point or "CENTER"
    local entryRelative = settings.relative or "CENTER"
    local isLegacyCenter = entryPoint == "CENTER" and entryRelative == "CENTER"

    if isLegacyCenter
        and settings.growAnchor and CORNER_POINTS and CORNER_POINTS[settings.growAnchor]
        and (key == "buffFrame" or key == "debuffFrame")
        and not (parentFrame and parentFrame._quiHostMover)
    then
        local corner = settings.growAnchor
        local fwRaw = (resolved.GetWidth and resolved:GetWidth()) or 0
        local fhRaw = (resolved.GetHeight and resolved:GetHeight()) or 0
        local fw, fh = fwRaw, fhRaw
        local sizeIsReal = fwRaw >= 4 and fhRaw >= 4
        if fw < 4 then
            fw = resolved._naturalW or settings._minWidth or 32
        end
        if fh < 4 then
            fh = resolved._naturalH or settings._minHeight or 32
        end
        if not sizeIsReal and (resolved._naturalW and resolved._naturalW >= 4) then
            sizeIsReal = true
        end
        local pw = (parentFrame and parentFrame.GetWidth and parentFrame:GetWidth()) or UIParent:GetWidth()
        local ph = (parentFrame and parentFrame.GetHeight and parentFrame:GetHeight()) or UIParent:GetHeight()
        local GA_FRAC_X = { TOPLEFT = 0, TOPRIGHT = 1, BOTTOMLEFT = 0, BOTTOMRIGHT = 1 }
        local GA_FRAC_Y = { TOPLEFT = 1, TOPRIGHT = 1, BOTTOMLEFT = 0, BOTTOMRIGHT = 0 }
        local cornerX = offsetX + (GA_FRAC_X[corner] - 0.5) * (fw - pw)
        local cornerY = offsetY + (GA_FRAC_Y[corner] - 0.5) * (fh - ph)
        AnchorOrPin(key, resolved, corner, parentFrame, corner, cornerX, cornerY)

        if sizeIsReal and QUICore and QUICore.db and QUICore.db.profile then
            local faDB = QUICore.db.profile.frameAnchoring
            local dbEntry = faDB and faDB[key]
            if dbEntry
                and (dbEntry.point == nil or dbEntry.point == "CENTER")
                and (dbEntry.relative == nil or dbEntry.relative == "CENTER")
            then
                dbEntry.point = corner
                dbEntry.relative = corner
                dbEntry.offsetX = math.floor(cornerX + 0.5)
                dbEntry.offsetY = math.floor(cornerY + 0.5)
            end
        end

        return
    end

    local useSizeStable = IsSizeStableAnchoringEnabled(settings)
    if _forceRawPointMode then
        useSizeStable = false
    end
    if CASTBAR_ANCHOR_KEYS[key] then
        useSizeStable = false
    end
    if IsDynamicSizeAnchorKey(key) or IsDynamicSizeAnchorKey(settings.parent) then
        useSizeStable = false
    end

    if key == "bossFrames" and type(resolved) == "table" and not resolved.GetObjectType then
        local bossGrowDirection, bossSpacingX, bossSpacingY = GetBossFrameLayout()
        for i, frame in ipairs(resolved) do
            if useSizeStable then
                ApplyAutoSizing(frame, settings, parentFrame, key)
            end
            local targetParent = parentFrame
            local targetPt, targetRelPt, targetX, targetY
            if i == 1 then
                if useSizeStable then
                    local centerX, centerY = ComputeCenterOffsetsForAnchor(
                        frame, key, parentFrame, point, relative, offsetX, offsetY, settings.parent
                    )
                    targetPt, targetRelPt, targetX, targetY = "CENTER", "CENTER", centerX, centerY
                else
                    targetPt, targetRelPt, targetX, targetY = point, relative, offsetX, offsetY
                end
            else
                targetParent = resolved[i - 1]
                targetPt, targetRelPt, targetX, targetY = GetBossStackPoint(bossGrowDirection, bossSpacingX, bossSpacingY)
            end
            if targetParent and not FrameAlreadyAtPosition(frame, targetPt, targetParent, targetRelPt, targetX, targetY) then
                _editModeReapplyGuard = true
                ns.SafeCall("best-effort-style", SmoothSetPoint, frame, targetPt, targetParent, targetRelPt, targetX, targetY)
                _editModeReapplyGuard = false
            end
        end
        if not useSizeStable then
            ApplyAutoSizing(resolved[1], settings, parentFrame, key)
            for i = 2, #resolved do
                ApplyAutoSizing(resolved[i], settings, parentFrame, key)
            end
        end
        return
    end

    if useSizeStable then
        ApplyAutoSizing(resolved, settings, parentFrame, key)
        local centerX, centerY = ComputeCenterOffsetsForAnchor(
            resolved, key, parentFrame, point, relative, offsetX, offsetY, settings.parent
        )
        if resolved and resolved.GetScale then
            local fScale = resolved:GetScale() or 1
            if fScale > 0 and fScale ~= 1 then
                centerX = centerX / fScale
                centerY = centerY / fScale
            end
        end
        if not FrameAlreadyAtPosition(resolved, "CENTER", parentFrame, "CENTER", centerX, centerY) then
            _editModeReapplyGuard = true
            ns.SafeCall("best-effort-style", AnchorOrPin, key, resolved, "CENTER", parentFrame, "CENTER", centerX, centerY)
            _editModeReapplyGuard = false
        end
    else
        local skipInflation = IsDynamicSizeAnchorKey(key)
            or IsDynamicSizeAnchorKey(settings.parent)
        local needsInflation = false
        if not skipInflation and parentFrame and parentFrame ~= UIParent and parentFrame.GetSize then
            local ok, pw, ph = pcall(parentFrame.GetSize, parentFrame)
            if ok and pw and ph and (pw < TINY_ANCHOR_THRESHOLD or ph < TINY_ANCHOR_THRESHOLD) then
                needsInflation = true
            end
        end
        if not skipInflation and not needsInflation and resolved and resolved.GetSize then
            local ok, rw, rh = pcall(resolved.GetSize, resolved)
            if ok and rw and rh and (rw < TINY_ANCHOR_THRESHOLD or rh < TINY_ANCHOR_THRESHOLD) then
                needsInflation = true
            end
        end
        if needsInflation then
            local centerX, centerY = ComputeCenterOffsetsForAnchor(
                resolved, key, parentFrame, point, relative, offsetX, offsetY, settings.parent
            )
            if not FrameAlreadyAtPosition(resolved, "CENTER", parentFrame, "CENTER", centerX, centerY) then
                _editModeReapplyGuard = true
                ns.SafeCall("best-effort-style", AnchorOrPin, key, resolved, "CENTER", parentFrame, "CENTER", centerX, centerY)
                _editModeReapplyGuard = false
            end
        else
            local live = LiveAuraContainerFor(key)
            if live or not FrameAlreadyAtPosition(resolved, point, parentFrame, relative, offsetX, offsetY) then
                _editModeReapplyGuard = true
                ns.SafeCall("best-effort-style", AnchorOrPin, key, resolved, point, parentFrame, relative, offsetX, offsetY)
                _editModeReapplyGuard = false
            end
        end
        ApplyAutoSizing(resolved, settings, parentFrame, key)
    end
end

ComputeAnchorApplyOrder = function(anchoringDB)
    local enabledSet = {}
    local enabledList = {}
    for key, settings in pairs(anchoringDB) do
        if type(settings) == "table" and HasFrameResolverForKey(key) then
            enabledSet[key] = true
            enabledList[#enabledList + 1] = key
        end
    end

    if #enabledList == 0 then return enabledList end

    local inDegree  = {}
    local childrenOf = {}
    for _, key in ipairs(enabledList) do
        inDegree[key] = 0
        childrenOf[key] = {}
    end

    for _, key in ipairs(enabledList) do
        local parent = anchoringDB[key].parent
        if parent == "essential" then parent = "cdmEssential" end
        if parent == "utility"  then parent = "cdmUtility"   end

        if parent and enabledSet[parent] then
            inDegree[key] = inDegree[key] + 1
            childrenOf[parent][#childrenOf[parent] + 1] = key
        end
    end

    local sorted = {}
    local queue  = {}
    for _, key in ipairs(enabledList) do
        if inDegree[key] == 0 then
            queue[#queue + 1] = key
        end
    end

    local head = 1
    while head <= #queue do
        local key = queue[head]
        head = head + 1
        sorted[#sorted + 1] = key
        for _, child in ipairs(childrenOf[key]) do
            inDegree[child] = inDegree[child] - 1
            if inDegree[child] == 0 then
                queue[#queue + 1] = child
            end
        end
    end

    if #sorted < #enabledList then
        for _, key in ipairs(enabledList) do
            if inDegree[key] > 0 then
                sorted[#sorted + 1] = key
            end
        end
    end

    return sorted
end

local _anchorThrottleFrame = nil
local _anchorThrottlePending = false
local _anchorThrottleReplay = false
local _anchorThrottleAfterApply = {}
local _anchorApplyDepth = 0

local function QueueAfterAnchorApply(callback)
    if callback then
        _anchorThrottleAfterApply[#_anchorThrottleAfterApply + 1] = callback
    end
end

local function RunAfterAnchorApply()
    if #_anchorThrottleAfterApply == 0 then return end
    local callbacks = _anchorThrottleAfterApply
    _anchorThrottleAfterApply = {}
    for _, callback in ipairs(callbacks) do
        callback()
    end
end

function QUI_Anchoring:ApplyAllFrameAnchors(force, afterApply)
    if not QUICore or not QUICore.db or not QUICore.db.profile then
        return "skipped"
    end
    local anchoringDB = QUICore.db.profile.frameAnchoring
    if not anchoringDB then return "skipped" end

    if not force and _G.QUI_IsLayoutModeActive and _G.QUI_IsLayoutModeActive() then
        return "skipped"
    end

    if not force and _anchorThrottlePending then
        QueueAfterAnchorApply(afterApply)
        _anchorThrottleReplay = true
        return "deferred"
    end
    QueueAfterAnchorApply(afterApply)
    _anchorThrottlePending = true
    if not _anchorThrottleFrame then
        _anchorThrottleFrame = CreateFrame("Frame")
        _anchorThrottleFrame:SetScript("OnUpdate", function(self)
            _anchorThrottlePending = false
            self:Hide()
            if _anchorThrottleReplay then
                _anchorThrottleReplay = false
                local replayOK, replayStatus = pcall(
                    QUI_Anchoring.ApplyAllFrameAnchors, QUI_Anchoring)
                if not replayOK then
                    if #_anchorThrottleAfterApply > 0 then
                        pendingAnchoredFrameUpdateAfterCombat = true
                    else
                        error(replayStatus, 0)
                    end
                elseif replayStatus == "skipped" then
                    RunAfterAnchorApply()
                end
            end
        end)
    end
    _anchorThrottleFrame:Show()

    _anchorApplyDepth = _anchorApplyDepth + 1
    local suppressionPushed = false
    local applyOK, applyError = xpcall(function()
        local replayConsumerOps
        local positionOnlyPending
        for opOriginKey, bySlot in pairs(resolveUnreadableRetried) do
            for slotKey, state in pairs(bySlot) do
                if type(state.op) == "function" then
                    replayConsumerOps = replayConsumerOps or {}
                    replayConsumerOps[#replayConsumerOps + 1] = { op = state.op, key = opOriginKey }
                end
                if slotKey == "positionOnly" then
                    positionOnlyPending = positionOnlyPending or {}
                    positionOnlyPending[opOriginKey] = true
                end
            end
        end
        for opOriginKey, bySlot in pairs(pendingCombatConsumerOps) do
            if bySlot["positionOnly"] then
                positionOnlyPending = positionOnlyPending or {}
                positionOnlyPending[opOriginKey] = true
            end
        end

        wipe(self.layoutOwnedFrames)
        wipe(hideWithParentUnreadableRetried)
        wipe(resolveUnreadableRetried)

        local sorted = ComputeAnchorApplyOrder(anchoringDB)
        suppressAutoSizingKeys[#suppressAutoSizingKeys + 1] = positionOnlyPending or false
        suppressionPushed = true
        for _, key in ipairs(sorted) do
            self:ApplyFrameAnchor(key, anchoringDB[key])
        end
        suppressAutoSizingKeys[#suppressAutoSizingKeys] = nil
        suppressionPushed = false

        InstallAllAnchorGuards()

        if replayConsumerOps then
            for _, entry in ipairs(replayConsumerOps) do
                ns.SafeCall("bulkhead", entry.op, entry.key)
            end
        end
    end, function(err)
        return err
    end)
    if suppressionPushed then
        suppressAutoSizingKeys[#suppressAutoSizingKeys] = nil
    end
    _anchorApplyDepth = _anchorApplyDepth - 1
    if not applyOK then
        error(applyError, 0)
    end

    if _anchorApplyDepth == 0 and not _anchorThrottleReplay then
        RunAfterAnchorApply()
    end
    return "applied"
end

_G.QUI_HasFrameAnchor = function(key)
    if not key then return false end
    local core = QUICore
    local db = core and core.db and core.db.profile
    return GetSavedFrameAnchorSettings(db and db.frameAnchoring, key) ~= nil
end

_G.QUI_IsFrameHiddenByAnchor = function(key)
    return hideWithParentHidden[key] or false
end

_G.QUI_SetFrameLayoutOwned = function(frame, key)
    if QUI_Anchoring and frame then
        QUI_Anchoring.layoutOwnedFrames[frame] = key or nil
    end
end

_G.QUI_ClaimAnchorKey = function(key, claimed)
    if not key then return end
    if not QUI_Anchoring then return end
    QUI_Anchoring.claimedAnchorKeys[key] = claimed and true or nil
end

_G.QUI_ApplyAllFrameAnchors = function(force)
    if QUI_Anchoring then
        QUI_Anchoring:ApplyAllFrameAnchors(force)
    end
end

_G.QUI_ApplyFrameAnchor = function(key)
    if not QUI_Anchoring or not QUICore or not QUICore.db or not QUICore.db.profile then
        return
    end
    local anchoringDB = QUICore.db.profile.frameAnchoring
    local settings = GetSavedFrameAnchorSettings(anchoringDB, key)
    if settings and HasFrameResolverForKey(key) then
        QUI_Anchoring:ApplyFrameAnchor(key, settings)
    end
end

_G.QUI_ResolveAnchorApplyFrame = function(key)
    if not key then return nil end
    return ResolveApplyFrameForKey(key)
end

_G.QUI_ResolveAnchorTargetFrame = function(key)
    if not key or key == "screen" or key == "disabled" then return nil end
    return ResolveFrameForKey(key)
end

_G.QUI_ForceReapplyFrameAnchor = function(key)
    if not QUI_Anchoring or not QUICore or not QUICore.db or not QUICore.db.profile then
        return
    end
    local anchoringDB = QUICore.db.profile.frameAnchoring
    local settings = GetSavedFrameAnchorSettings(anchoringDB, key)
    if not settings or not HasFrameResolverForKey(key) then return end
    local resolved = ResolveApplyFrameForKey(key)
    if resolved then
        if type(resolved) == "table" and not resolved.GetObjectType then
            for _, frame in ipairs(resolved) do ns.SafeCallMethod("best-effort-style", frame, "ClearAllPoints") end
        else
            ns.SafeCallMethod("best-effort-style", resolved, "ClearAllPoints")
        end
    end
    QUI_Anchoring:ApplyFrameAnchor(key, settings)
end

_G.QUI_ReassertAnchorAfterResize = function(key)
    if not key or not QUICore or not QUICore.db or not QUICore.db.profile then
        return
    end
    local anchoringDB = QUICore.db.profile.frameAnchoring
    local settings = GetSavedFrameAnchorSettings(anchoringDB, key)
    if not settings then return end
    local parent = settings.parent
    if not parent or parent == "disabled" then return end
    if _G.QUI_LayoutModeClearPending then
        _G.QUI_LayoutModeClearPending(key)
    end
    _G.QUI_ForceReapplyFrameAnchor(key)
    if _G.QUI_LayoutModeSyncHandle then
        _G.QUI_LayoutModeSyncHandle(key)
    end
end

_G.QUI_ReanchorFramePositionOnly = function(key)
    if not key then return end
    if InCombatLockdown() then
        latchCombatConsumerOp(key, "positionOnly", _G.QUI_ReanchorFramePositionOnly)
        return
    end
    if not QUI_Anchoring or not QUICore or not QUICore.db or not QUICore.db.profile then return end
    local anchoringDB = QUICore.db.profile.frameAnchoring
    if not anchoringDB then return end
    local settings = anchoringDB[key]
    if type(settings) ~= "table" then return end

    if not HasFrameResolverForKey(key) then return end
    local resolved = ResolveApplyFrameForKey(key)
    if not resolved then return end

    local parentFrame = ResolveParentFrame(settings.parent, key,
        _G.QUI_ReanchorFramePositionOnly, "positionOnly")
    if not parentFrame then return end
    if parentFrame._quiHostMover then
        parentFrame = parentFrame._quiHostMover
    end

    local point = settings.point or "CENTER"
    local relative = settings.relative or "CENTER"
    local offsetX = settings.offsetX or 0
    local offsetY = settings.offsetY or 0
    local useSizeStable = IsSizeStableAnchoringEnabled(settings)
    if CASTBAR_ANCHOR_KEYS[key] or IsDynamicSizeAnchorKey(key)
        or IsDynamicSizeAnchorKey(settings.parent) then
        useSizeStable = false
    end

    local H = nsHelpers or ns.Helpers
    ns.SafeCall("best-effort-style", function()
        H.BaseClearAllPoints(resolved)
        if useSizeStable then
            local centerX, centerY = ComputeCenterOffsetsForAnchor(
                resolved, key, parentFrame, point, relative, offsetX, offsetY, settings.parent
            )
            H.BaseSetPoint(resolved, "CENTER", parentFrame, "CENTER", centerX, centerY)
        else
            H.BaseSetPoint(resolved, point, parentFrame, relative, offsetX, offsetY)
        end
    end)
end

_G.QUI_AnchorOverlayToParent = function(overlayFrame, key, overlayW, overlayH)
    if not overlayFrame or not key then return end
    if not QUI_Anchoring or not QUICore or not QUICore.db or not QUICore.db.profile then return end
    local anchoringDB = QUICore.db.profile.frameAnchoring
    if not anchoringDB then return end
    local settings = anchoringDB[key]
    if type(settings) ~= "table" then return end

    local parentFrame, _, parentUnreadable = ResolveParentFrame(
        settings.parent, key,
        function()
            _G.QUI_AnchorOverlayToParent(overlayFrame, key, overlayW, overlayH)
        end,
        overlayFrame)
    if not parentFrame then return end
    if parentUnreadable and InCombatLockdown() then return end
    if parentFrame._quiHostMover then
        parentFrame = parentFrame._quiHostMover
    end

    local point = settings.point or "CENTER"
    local relative = settings.relative or "CENTER"
    local offsetX = settings.offsetX or 0
    local offsetY = settings.offsetY or 0
    local useSizeStable = IsSizeStableAnchoringEnabled(settings)
    if CASTBAR_ANCHOR_KEYS[key] or IsDynamicSizeAnchorKey(key)
        or IsDynamicSizeAnchorKey(settings.parent) then
        useSizeStable = false
    end

    overlayFrame:ClearAllPoints()
    if overlayW and overlayW > 0 then overlayFrame:SetWidth(overlayW) end
    if overlayH and overlayH > 0 then overlayFrame:SetHeight(overlayH) end
    if useSizeStable then
        local parentW, parentH = GetParentAnchorRect(parentFrame, settings.parent)
        if parentFrame ~= UIParent then
            if parentW < TINY_ANCHOR_THRESHOLD then parentW = LAYOUT_HANDLE_MIN end
            if parentH < TINY_ANCHOR_THRESHOLD then parentH = LAYOUT_HANDLE_MIN end
        end
        local ow = (overlayW or 1) < TINY_ANCHOR_THRESHOLD and LAYOUT_HANDLE_MIN or (overlayW or 1)
        local oh = (overlayH or 1) < TINY_ANCHOR_THRESHOLD and LAYOUT_HANDLE_MIN or (overlayH or 1)
        local targetX, targetY = GetPointOffsetForRect(relative or "CENTER", parentW, parentH)
        local sourceX, sourceY = GetPointOffsetForRect(point or "CENTER", ow, oh)
        local centerX = (targetX + (offsetX or 0) - sourceX)
        local centerY = (targetY + (offsetY or 0) - sourceY)
        overlayFrame:SetPoint("CENTER", parentFrame, "CENTER", centerX, centerY)
    else
        overlayFrame:SetPoint(point, parentFrame, relative, offsetX, offsetY)
    end
end

local pendingOverrideReapply = nil

DebouncedReapplyOverrides = function()
    if pendingOverrideReapply then return end
    pendingOverrideReapply = true
    C_Timer.After(0.15, function()
        pendingOverrideReapply = nil
        if QUI_Anchoring then
            QUI_Anchoring:ApplyAllFrameAnchors()
        end
    end)
end

local function HookRefreshGlobal(name)
    local original = _G[name]
    if not original then return end
    _G[name] = function(...)
        original(...)
        DebouncedReapplyOverrides()
    end
end

HookRefreshGlobal("QUI_RefreshCastbar")
HookRefreshGlobal("QUI_RefreshCastbars")
HookRefreshGlobal("QUI_RefreshUnitFrames")
HookRefreshGlobal("QUI_RefreshGroupFrames")
HookRefreshGlobal("QUI_RefreshNCDM")
HookRefreshGlobal("QUI_RefreshCDMBuffLayout")
HookRefreshGlobal("QUI_RefreshRaidBuffs")

C_Timer.After(0, function()
    HookRefreshGlobal("QUI_RefreshCustomTrackers")
    HookRefreshGlobal("QUI_RefreshBrezCounter")
    HookRefreshGlobal("QUI_RefreshAtonementCounter")
    HookRefreshGlobal("QUI_RefreshCombatTimer")
    HookRefreshGlobal("QUI_RefreshRangeCheck")
    HookRefreshGlobal("QUI_RefreshXPTracker")
    HookRefreshGlobal("QUI_RefreshActionTracker")
    HookRefreshGlobal("QUI_RefreshSkyriding")
    HookRefreshGlobal("QUI_RefreshPetWarning")
    HookRefreshGlobal("QUI_RefreshFocusCastAlert")
end)

local anchoredFramesPostHooks = {}

function QUI_Anchoring.RegisterAnchoredFramesPostHook(name, fn)
    if type(name) ~= "string" or type(fn) ~= "function" then return end
    for _, hook in ipairs(anchoredFramesPostHooks) do
        if hook.name == name then
            hook.fn = fn
            return
        end
    end
    anchoredFramesPostHooks[#anchoredFramesPostHooks + 1] = { name = name, fn = fn }
end

local function RunAnchoredFramesPostHooks(...)
    for _, hook in ipairs(anchoredFramesPostHooks) do
        ns.SafeCall("bulkhead", hook.fn, ...)
    end
end

local previousUpdateAnchoredFrames = _G.QUI_UpdateAnchoredFrames
local previousUpdateAnchoredUnitFrames = _G.QUI_UpdateAnchoredUnitFrames
local previousUpdateCDMAnchoredUnitFrames = _G.QUI_UpdateCDMAnchoredUnitFrames

_G.QUI_UpdateAnchoredFrames = function(...)
    if previousUpdateAnchoredFrames and previousUpdateAnchoredFrames ~= _G.QUI_UpdateAnchoredFrames then
        previousUpdateAnchoredFrames(...)
    end
    DebouncedReapplyOverrides()
    RunAnchoredFramesPostHooks(...)
end

_G.QUI_UpdateAnchoredUnitFrames = function(...)
    if previousUpdateAnchoredUnitFrames and previousUpdateAnchoredUnitFrames ~= _G.QUI_UpdateAnchoredUnitFrames and previousUpdateAnchoredUnitFrames ~= previousUpdateAnchoredFrames then
        previousUpdateAnchoredUnitFrames(...)
    end
    _G.QUI_UpdateAnchoredFrames(...)
end

_G.QUI_UpdateCDMAnchoredUnitFrames = function(...)
    if previousUpdateCDMAnchoredUnitFrames and previousUpdateCDMAnchoredUnitFrames ~= _G.QUI_UpdateCDMAnchoredUnitFrames and previousUpdateCDMAnchoredUnitFrames ~= previousUpdateAnchoredFrames then
        previousUpdateCDMAnchoredUnitFrames(...)
    end
    _G.QUI_UpdateAnchoredFrames(...)
end

_G.QUI_UpdateFramesAnchoredTo = function(targetKeyOrFrame)
    if not targetKeyOrFrame then return end

    local targetKey = targetKeyOrFrame
    if type(targetKeyOrFrame) ~= "string" then
        targetKey = nil
        if QUI_Anchoring and QUI_Anchoring.anchorTargets then
            for name, entry in pairs(QUI_Anchoring.anchorTargets) do
                if entry.frame == targetKeyOrFrame then
                    targetKey = name
                    break
                end
            end
        end
        if not targetKey then return end
    end

    if InCombatLockdown() then
        if targetKey ~= "cdmEssential" and targetKey ~= "cdmUtility"
            and targetKey ~= "buffIcon" and targetKey ~= "buffBar"
            and targetKey ~= "buffFrame" and targetKey ~= "debuffFrame"
        then
            return
        end
    end

    local anchoringDB = QUICore and QUICore.db and QUICore.db.profile
        and QUICore.db.profile.frameAnchoring

    local queue = { targetKey }
    local visited = { [targetKey] = true }

    while #queue > 0 do
        local currentTarget = table.remove(queue, 1)

        if anchoringDB and QUI_Anchoring then
            for key, settings in pairs(anchoringDB) do
                if type(settings) == "table" and settings.parent == currentTarget then
                    QUI_Anchoring:ApplyFrameAnchor(key, settings)
                    if not visited[key] then
                        visited[key] = true
                        queue[#queue + 1] = key
                    end
                end
            end
        end
    end
end

if ns.Registry then
    ns.Registry:Register("anchoring", {
        refresh = _G.QUI_ApplyAllFrameAnchors,
        priority = 70,
        group = "anchoring",
        importCategories = { "layout" },
    })
end
