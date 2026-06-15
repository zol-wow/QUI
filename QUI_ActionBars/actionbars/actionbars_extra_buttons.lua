local ADDON_NAME, ns = ...
local env = ns.ActionBarsEnv
env.ADDON_NAME = ADDON_NAME
env.ns = ns
env.SetChunkEnv(1, env)

---------------------------------------------------------------------------
-- EXTRA BUTTON CUSTOMIZATION (Extra Action Button & Zone Ability)
---------------------------------------------------------------------------
do

extraBtnState = {
    extraActionHolder = nil,
    extraActionMover = nil,
    zoneAbilityHolder = nil,
    zoneAbilityMover = nil,
    moversVisible = false,
    hookingSetPoint = false,
    extraActionSetPointHooked = false,
    zoneAbilitySetPointHooked = false,
    extraAbilityContainerSetPointHooked = false,
    hookingSetParent = false,
    extraActionSetParentHooked = false,
    zoneAbilitySetParentHooked = false,
    extraAbilityContainerSetParentHooked = false,
    extraActionShowHooked = false,
    zoneAbilityShowHooked = false,
    extraAbilityContainerShowHooked = false,
    pageArrowShowHooked = {},
    pageArrowRetryTimer = nil,
    pageArrowRetryAttempts = 0,
    PAGE_ARROW_RETRY_MAX_ATTEMPTS = 15,
    PAGE_ARROW_RETRY_DELAY = 0.2,
}

function GetExtraButtonDB(buttonType)
    local core = GetCore()
    if not core or not core.db or not core.db.profile then return nil end
    return core.db.profile.actionBars and core.db.profile.actionBars.bars
        and core.db.profile.actionBars.bars[buttonType]
end

function GetSavedExtraButtonFrameAnchor(buttonType)
    local core = GetCore()
    local profile = core and core.db and core.db.profile
    local fa = profile and profile.frameAnchoring
    if type(fa) ~= "table" or not buttonType then return nil end
    local entry = rawget(fa, buttonType)
    if type(entry) == "table" then
        return entry
    end
    return nil
end

function ApplyExtraButtonFrameAnchor(buttonType)
    local HasAnchor = _G.QUI_HasFrameAnchor
    local ApplyAnchor = _G.QUI_ApplyFrameAnchor
    if HasAnchor and ApplyAnchor and HasAnchor(buttonType) then
        ApplyAnchor(buttonType)
    end
end

function SaveExtraButtonFrameAnchor(buttonType, point, relPoint, x, y)
    local core = GetCore()
    local profile = core and core.db and core.db.profile
    if not profile or not buttonType or not point then return end

    if type(profile.frameAnchoring) ~= "table" then
        profile.frameAnchoring = {}
    end

    local fa = profile.frameAnchoring
    local entry = rawget(fa, buttonType)
    if type(entry) ~= "table" then
        entry = {}
        fa[buttonType] = entry
    end

    entry.parent = "screen"
    entry.point = point
    entry.relative = relPoint or point
    entry.offsetX = x or 0
    entry.offsetY = y or 0
    entry.sizeStable = true
    entry.autoWidth = false
    entry.autoHeight = false
    entry.hideWithParent = false
    entry.keepInPlace = true
    entry.widthAdjust = 0
    entry.heightAdjust = 0
end

function SaveExtraButtonHolderPosition(buttonType, holder)
    if not holder then return end

    local core = GetCore()
    local point, relPoint, x, y

    if core and core.SnapFramePosition then
        local snappedPoint, _, snappedRelPoint, snappedX, snappedY = core:SnapFramePosition(holder)
        point, relPoint, x, y = snappedPoint, snappedRelPoint, snappedX, snappedY
    end

    if not point and holder.GetPoint then
        local fallbackPoint, _, fallbackRelPoint, fallbackX, fallbackY = holder:GetPoint(1)
        point, relPoint, x, y = fallbackPoint, fallbackRelPoint, fallbackX, fallbackY
    end

    if not point then return end

    x = Helpers.SafeToNumber(x, 0)
    y = Helpers.SafeToNumber(y, 0)
    relPoint = relPoint or point

    local db = GetExtraButtonDB(buttonType)
    if db then
        db.position = { point = point, relPoint = relPoint, x = x, y = y }
    end

    SaveExtraButtonFrameAnchor(buttonType, point, relPoint, x, y)
    ApplyExtraButtonFrameAnchor(buttonType)

    if _G.QUI and _G.QUI.SendMessage then
        _G.QUI:SendMessage("QUI_FRAME_ANCHOR_CHANGED", buttonType)
    end
end

function GetExtraButtonInitialPosition(buttonType, fallbackPosition)
    local anchor = GetSavedExtraButtonFrameAnchor(buttonType)
    if anchor then
        local parentKey = anchor.parent
        local parentFrame
        if not parentKey or parentKey == "screen" or parentKey == "disabled" then
            parentFrame = UIParent
        elseif parentKey == "extraActionButton" and buttonType ~= "extraActionButton" then
            parentFrame = extraBtnState.extraActionHolder or _G["QUI_extraActionButtonHolder"]
        elseif parentKey == "zoneAbility" and buttonType ~= "zoneAbility" then
            parentFrame = extraBtnState.zoneAbilityHolder or _G["QUI_zoneAbilityHolder"]
        end

        if parentFrame then
            local point = anchor.point or "CENTER"
            return point, parentFrame, anchor.relative or point, anchor.offsetX or 0, anchor.offsetY or 0
        end
    end

    if fallbackPosition and fallbackPosition.point then
        return fallbackPosition.point, UIParent, fallbackPosition.relPoint or fallbackPosition.point,
            fallbackPosition.x or 0, fallbackPosition.y or 0
    end

    return nil
end

function CreateExtraButtonNudgeButton(parent, direction, holder, buttonType)
    local btn = CreateFrame("Button", nil, parent)
    btn:SetSize(18, 18)
    btn:SetFrameStrata("HIGH")
    btn:SetFrameLevel(100)

    local bg = btn:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetTexture("Interface\\Buttons\\WHITE8x8")
    bg:SetVertexColor(0.1, 0.1, 0.1, 0.7)

    local line1 = btn:CreateTexture(nil, "ARTWORK")
    line1:SetColorTexture(1, 1, 1, 0.9)
    line1:SetSize(7, 2)

    local line2 = btn:CreateTexture(nil, "ARTWORK")
    line2:SetColorTexture(1, 1, 1, 0.9)
    line2:SetSize(7, 2)

    if direction == "DOWN" then
        line1:SetPoint("CENTER", btn, "CENTER", -2, 1)
        line1:SetRotation(math.rad(-45))
        line2:SetPoint("CENTER", btn, "CENTER", 2, 1)
        line2:SetRotation(math.rad(45))
    elseif direction == "UP" then
        line1:SetPoint("CENTER", btn, "CENTER", -2, -1)
        line1:SetRotation(math.rad(45))
        line2:SetPoint("CENTER", btn, "CENTER", 2, -1)
        line2:SetRotation(math.rad(-45))
    elseif direction == "LEFT" then
        line1:SetPoint("CENTER", btn, "CENTER", 1, -2)
        line1:SetRotation(math.rad(-45))
        line2:SetPoint("CENTER", btn, "CENTER", 1, 2)
        line2:SetRotation(math.rad(45))
    elseif direction == "RIGHT" then
        line1:SetPoint("CENTER", btn, "CENTER", -1, -2)
        line1:SetRotation(math.rad(45))
        line2:SetPoint("CENTER", btn, "CENTER", -1, 2)
        line2:SetRotation(math.rad(-45))
    end

    btn:SetScript("OnEnter", function(self)
        line1:SetVertexColor(1, 0.8, 0, 1)
        line2:SetVertexColor(1, 0.8, 0, 1)
    end)
    btn:SetScript("OnLeave", function(self)
        line1:SetVertexColor(1, 1, 1, 0.9)
        line2:SetVertexColor(1, 1, 1, 0.9)
    end)

    btn:SetScript("OnClick", function()
        local dx, dy = 0, 0
        if direction == "UP" then dy = 1
        elseif direction == "DOWN" then dy = -1
        elseif direction == "LEFT" then dx = -1
        elseif direction == "RIGHT" then dx = 1
        end
        if holder.AdjustPointsOffset then
            holder:AdjustPointsOffset(dx, dy)
        else
            local point, relativeTo, relativePoint, xOfs, yOfs = holder:GetPoint(1)
            if point then
                holder:ClearAllPoints()
                holder:SetPoint(point, relativeTo, relativePoint, (xOfs or 0) + dx, (yOfs or 0) + dy)
            end
        end
        SaveExtraButtonHolderPosition(buttonType, holder)
    end)

    return btn
end

function CreateExtraButtonHolder(buttonType, displayName)
    local settings = GetExtraButtonDB(buttonType)
    if not settings then return nil, nil end

    local holder = CreateFrame("Frame", "QUI_" .. buttonType .. "Holder", UIParent)
    holder:SetSize(64, 64)
    holder:SetMovable(true)
    holder:SetClampedToScreen(true)

    local point, relativeTo, relPoint, x, y = GetExtraButtonInitialPosition(buttonType, settings.position)
    if point then
        holder:SetPoint(point, relativeTo or UIParent, relPoint or point, x or 0, y or 0)
    else
        if buttonType == "extraActionButton" then
            holder:SetPoint("CENTER", UIParent, "CENTER", -100, -200)
        else
            holder:SetPoint("CENTER", UIParent, "CENTER", 100, -200)
        end
    end

    local mover = CreateFrame("Frame", "QUI_" .. buttonType .. "Mover", holder, "BackdropTemplate")
    mover:SetAllPoints(holder)
    ns.SkinBase.ApplyPixelBackdrop(mover, 2, true, false, {0.376, 0.647, 0.980, 1}, {0.2, 0.8, 0.6, 0.5})
    mover:EnableMouse(true)
    mover:SetMovable(true)
    mover:RegisterForDrag("LeftButton")
    mover:SetFrameStrata("HIGH")
    mover:Hide()

    local text = mover:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    text:SetPoint("CENTER")
    text:SetText(displayName)
    mover.text = text

    local nudgeUp = CreateExtraButtonNudgeButton(mover, "UP", holder, buttonType)
    nudgeUp:SetPoint("BOTTOM", mover, "TOP", 0, 4)
    local nudgeDown = CreateExtraButtonNudgeButton(mover, "DOWN", holder, buttonType)
    nudgeDown:SetPoint("TOP", mover, "BOTTOM", 0, -4)
    local nudgeLeft = CreateExtraButtonNudgeButton(mover, "LEFT", holder, buttonType)
    nudgeLeft:SetPoint("RIGHT", mover, "LEFT", -4, 0)
    local nudgeRight = CreateExtraButtonNudgeButton(mover, "RIGHT", holder, buttonType)
    nudgeRight:SetPoint("LEFT", mover, "RIGHT", 4, 0)

    mover:SetScript("OnDragStart", function(self)
        holder:StartMoving()
    end)

    mover:SetScript("OnDragStop", function(self)
        holder:StopMovingOrSizing()
        SaveExtraButtonHolderPosition(buttonType, holder)
    end)

    return holder, mover
end

extraButtonOriginalParents = {}

function GetExtraButtonVisualFrame(buttonType, blizzFrame)
    if not blizzFrame then return nil end

    if buttonType == "extraActionButton" then
        return blizzFrame.button or _G["ExtraActionButton1"]
    end

    local container = blizzFrame.SpellButtonContainer
    if container then
        if container.EnumerateActive then
            for button in container:EnumerateActive() do
                if button then
                    return button
                end
            end
        end
        return container
    end

    return blizzFrame.SpellButton
end

function GetExtraButtonHolderSize(buttonType, blizzFrame, settings, scale)
    local width = Helpers.SafeToNumber(blizzFrame:GetWidth(), 64)
    local height = Helpers.SafeToNumber(blizzFrame:GetHeight(), 64)

    if settings.hideArtwork then
        local visualFrame = GetExtraButtonVisualFrame(buttonType, blizzFrame)
        if visualFrame then
            local visualWidth = visualFrame.GetWidth and Helpers.SafeToNumber(visualFrame:GetWidth(), width) or width
            local visualHeight = visualFrame.GetHeight and Helpers.SafeToNumber(visualFrame:GetHeight(), height) or height
            if visualWidth > 0 then width = visualWidth end
            if visualHeight > 0 then height = visualHeight end
        end
    end

    scale = Helpers.SafeToNumber(scale, 1)
    if scale <= 0 then scale = 1 end

    return math.max(width * scale, 64), math.max(height * scale, 64)
end

function ApplyExtraButtonSettings(buttonType)
    if InCombatLockdown() and not inInitSafeWindow then
        ActionBarsOwned.pendingExtraButtonRefresh = true
        return
    end

    local settings = GetExtraButtonDB(buttonType)
    if not settings or not settings.enabled then return end

    local blizzFrame
    local holder

    if buttonType == "extraActionButton" then
        blizzFrame = ExtraActionBarFrame
        holder = extraBtnState.extraActionHolder
    else
        blizzFrame = ZoneAbilityFrame
        holder = extraBtnState.zoneAbilityHolder
    end

    if not blizzFrame or not holder then return end

    local scale = settings.scale or 1.0
    blizzFrame:SetScale(scale)

    local offsetX = settings.offsetX or 0
    local offsetY = settings.offsetY or 0

    -- TAINT SAFETY: Reparent the Blizzard frame to our holder, removing it
    -- from the UIParent managed frame container's layout chain.  Calling
    -- ClearAllPoints/SetPoint on managed frames from addon code permanently
    -- taints their position data; when Blizzard's secure UseAction chain
    -- later calls UIParent_ManageFramePositions, the taint propagates to
    -- all managed containers (including UIParentRightManagedFrameContainer),
    -- causing ADDON_ACTION_BLOCKED.  Reparenting removes the frame from the
    -- managed container entirely so its position is never read by the secure
    -- layout system.
    if not extraButtonOriginalParents[buttonType] then
        extraButtonOriginalParents[buttonType] = blizzFrame:GetParent()
    end
    -- Deregister from the managed-container's layout chain BEFORE reparenting,
    -- otherwise the container still iterates this frame during Layout passes
    -- (e.g. cinematic start), runs our hooks, and taints the container's
    -- SetSize call — ADDON_ACTION_BLOCKED on UIParentRightManagedFrameContainer.
    local currentParent = blizzFrame:GetParent()
    if currentParent and currentParent.RemoveManagedFrame then
        pcall(currentParent.RemoveManagedFrame, currentParent, blizzFrame)
    end
    blizzFrame.ignoreFramePositionManager = true
    extraBtnState.hookingSetParent = true
    blizzFrame:SetParent(holder)
    extraBtnState.hookingSetParent = false
    extraBtnState.hookingSetPoint = true
    blizzFrame:ClearAllPoints()
    blizzFrame:SetPoint("CENTER", holder, "CENTER", offsetX, offsetY)
    extraBtnState.hookingSetPoint = false

    local holderWidth, holderHeight = GetExtraButtonHolderSize(buttonType, blizzFrame, settings, scale)
    holder:SetSize(holderWidth, holderHeight)

    if settings.hideArtwork then
        if buttonType == "extraActionButton" and blizzFrame.button and blizzFrame.button.style then
            blizzFrame.button.style:SetAlpha(0)
        end
        if buttonType == "zoneAbility" and blizzFrame.Style then
            blizzFrame.Style:SetAlpha(0)
        end
    else
        if buttonType == "extraActionButton" and blizzFrame.button and blizzFrame.button.style then
            blizzFrame.button.style:SetAlpha(1)
        end
        if buttonType == "zoneAbility" and blizzFrame.Style then
            blizzFrame.Style:SetAlpha(1)
        end
    end

    if not settings.fadeEnabled then
        blizzFrame:SetAlpha(1)
    end
end

pendingExtraButtonReanchor = {}

function QueueExtraButtonReanchor(buttonType)
    if pendingExtraButtonReanchor[buttonType] then return end
    pendingExtraButtonReanchor[buttonType] = true

    C_Timer.After(0, function()
        pendingExtraButtonReanchor[buttonType] = false

        if InCombatLockdown() then
            ActionBarsOwned.pendingExtraButtonRefresh = true
            return
        end

        local settings = GetExtraButtonDB(buttonType)
        if settings and settings.enabled then
            ApplyExtraButtonSettings(buttonType)
            ApplyExtraButtonFrameAnchor(buttonType)
        end
    end)
end

function QueueManagedExtraButtonReanchor(buttonType)
    local holder = buttonType == "extraActionButton"
        and extraBtnState.extraActionHolder
        or extraBtnState.zoneAbilityHolder
    local settings = GetExtraButtonDB(buttonType)
    if holder and settings and settings.enabled then
        QueueExtraButtonReanchor(buttonType)
    end
end

function QueueAllExtraButtonReanchors()
    QueueManagedExtraButtonReanchor("extraActionButton")
    QueueManagedExtraButtonReanchor("zoneAbility")
end

-- Hook Blizzard frames to prevent them from repositioning.
-- After reparenting, the managed container won't reposition these frames,
-- but other Blizzard code (e.g. ability grant, zone transition) may call
-- SetPoint directly.  The hooks re-anchor to our holder after each attempt.
function HookExtraButtonPositioning()
    if ExtraActionBarFrame and not extraBtnState.extraActionSetPointHooked then
        extraBtnState.extraActionSetPointHooked = true
        hooksecurefunc(ExtraActionBarFrame, "SetPoint", function(self)
            if extraBtnState.hookingSetPoint then return end
            C_Timer.After(0, function()
                if extraBtnState.hookingSetPoint then return end
                QueueManagedExtraButtonReanchor("extraActionButton")
            end)
        end)
    end

    if ZoneAbilityFrame and not extraBtnState.zoneAbilitySetPointHooked then
        extraBtnState.zoneAbilitySetPointHooked = true
        hooksecurefunc(ZoneAbilityFrame, "SetPoint", function(self)
            if extraBtnState.hookingSetPoint then return end
            C_Timer.After(0, function()
                if extraBtnState.hookingSetPoint then return end
                QueueManagedExtraButtonReanchor("zoneAbility")
            end)
        end)
    end

    if ExtraAbilityContainer and not extraBtnState.extraAbilityContainerSetPointHooked then
        extraBtnState.extraAbilityContainerSetPointHooked = true
        hooksecurefunc(ExtraAbilityContainer, "SetPoint", function()
            if extraBtnState.hookingSetPoint then return end
            C_Timer.After(0, function()
                if extraBtnState.hookingSetPoint then return end
                QueueAllExtraButtonReanchors()
            end)
        end)
    end

    -- Hook SetParent to reclaim frames if Blizzard reparents them back to
    -- a managed container (e.g. during Edit Mode layout recalculation).
    local function HookSetParentForType(blizzFrame, buttonType, holder)
        if not blizzFrame then return end
        hooksecurefunc(blizzFrame, "SetParent", function(self, newParent)
            if extraBtnState.hookingSetParent then return end
            if newParent == holder then return end
            C_Timer.After(0, function()
                if extraBtnState.hookingSetParent then return end
                local settings = GetExtraButtonDB(buttonType)
                if holder and settings and settings.enabled then
                    if InCombatLockdown() then
                        ActionBarsOwned.pendingExtraButtonRefresh = true
                        return
                    end
                    extraBtnState.hookingSetParent = true
                    blizzFrame:SetParent(holder)
                    extraBtnState.hookingSetParent = false
                    QueueExtraButtonReanchor(buttonType)
                end
            end)
        end)
    end
    if ExtraActionBarFrame and not extraBtnState.extraActionSetParentHooked then
        extraBtnState.extraActionSetParentHooked = true
        HookSetParentForType(ExtraActionBarFrame, "extraActionButton", extraBtnState.extraActionHolder)
    end
    if ZoneAbilityFrame and not extraBtnState.zoneAbilitySetParentHooked then
        extraBtnState.zoneAbilitySetParentHooked = true
        HookSetParentForType(ZoneAbilityFrame, "zoneAbility", extraBtnState.zoneAbilityHolder)
    end
    if ExtraAbilityContainer and not extraBtnState.extraAbilityContainerSetParentHooked then
        extraBtnState.extraAbilityContainerSetParentHooked = true
        hooksecurefunc(ExtraAbilityContainer, "SetParent", function()
            if extraBtnState.hookingSetParent then return end
            C_Timer.After(0, function()
                if extraBtnState.hookingSetParent then return end
                QueueAllExtraButtonReanchors()
            end)
        end)
    end

    -- Hook Show to recapture frames when Blizzard makes them visible
    -- (e.g., zone ability appearing upon entering a new zone).
    if ExtraActionBarFrame and not extraBtnState.extraActionShowHooked then
        extraBtnState.extraActionShowHooked = true
        hooksecurefunc(ExtraActionBarFrame, "Show", function()
            QueueExtraButtonReanchor("extraActionButton")
        end)
    end
    if ZoneAbilityFrame and not extraBtnState.zoneAbilityShowHooked then
        extraBtnState.zoneAbilityShowHooked = true
        hooksecurefunc(ZoneAbilityFrame, "Show", function()
            QueueExtraButtonReanchor("zoneAbility")
        end)
    end
    if ExtraAbilityContainer and not extraBtnState.extraAbilityContainerShowHooked then
        extraBtnState.extraAbilityContainerShowHooked = true
        hooksecurefunc(ExtraAbilityContainer, "Show", function()
            QueueAllExtraButtonReanchors()
        end)
    end
end

function ShowExtraButtonMovers()
    extraBtnState.moversVisible = true
    if extraBtnState.extraActionMover then extraBtnState.extraActionMover:Show() end
    if extraBtnState.zoneAbilityMover then extraBtnState.zoneAbilityMover:Show() end
end

function HideExtraButtonMovers()
    extraBtnState.moversVisible = false
    if extraBtnState.extraActionMover then extraBtnState.extraActionMover:Hide() end
    if extraBtnState.zoneAbilityMover then extraBtnState.zoneAbilityMover:Hide() end
end

function ToggleExtraButtonMovers()
    if extraBtnState.moversVisible then
        HideExtraButtonMovers()
    else
        ShowExtraButtonMovers()
    end
end

-- Assign to upvalue for forward declaration in event handler
InitializeExtraButtons = function()
    if InCombatLockdown() and not inInitSafeWindow then
        ActionBarsOwned.pendingExtraButtonInit = true
        return
    end

    extraBtnState.extraActionHolder, extraBtnState.extraActionMover = CreateExtraButtonHolder("extraActionButton", "Extra Action Button")
    extraBtnState.zoneAbilityHolder, extraBtnState.zoneAbilityMover = CreateExtraButtonHolder("zoneAbility", "Zone Ability")

    C_Timer.After(0.5, function()
        ApplyExtraButtonSettings("extraActionButton")
        ApplyExtraButtonFrameAnchor("extraActionButton")
        ApplyExtraButtonSettings("zoneAbility")
        ApplyExtraButtonFrameAnchor("zoneAbility")
        HookExtraButtonPositioning()
    end)
end

-- Assign to upvalue for forward declaration in event handler
RefreshExtraButtons = function()
    if InCombatLockdown() and not inInitSafeWindow then
        ActionBarsOwned.pendingExtraButtonRefresh = true
        return
    end
    ApplyExtraButtonSettings("extraActionButton")
    ApplyExtraButtonFrameAnchor("extraActionButton")
    ApplyExtraButtonSettings("zoneAbility")
    ApplyExtraButtonFrameAnchor("zoneAbility")
    -- Set up hooks on any newly available frames (handles late-loaded
    -- frames like ZoneAbilityFrame that may not exist at init time).
    HookExtraButtonPositioning()
end

_G.QUI_ToggleExtraButtonMovers = ToggleExtraButtonMovers
_G.QUI_RefreshExtraButtons = RefreshExtraButtons
ActionBarsOwned.extraBtnState = extraBtnState

end -- do (extra buttons)

---------------------------------------------------------------------------
