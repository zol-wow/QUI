local ADDON_NAME, ns = ...
local env = ns.ActionBarsEnv
env.ADDON_NAME = ADDON_NAME
env.ns = ns
env.SetChunkEnv(1, env)

---@diagnostic disable: lowercase-global -- SetChunkEnv installs a setfenv

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
    containerOwned = false,
    containerNeutralized = false,
    zoneOwned = false,
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

-- NO-OVERRIDE FALLBACK on refresh: a profile whose mover was never dragged
function ApplyExtraButtonHolderFallbackPosition(buttonType, holder)
    if not holder then return end
    local settings = GetExtraButtonDB(buttonType)
    local point, relativeTo, relPoint, x, y =
        GetExtraButtonInitialPosition(buttonType, settings and settings.position)
    if not point then
        point, relativeTo, relPoint = "CENTER", UIParent, "CENTER"
        x = buttonType == "extraActionButton" and -100 or 100
        y = -200
    end
    holder:ClearAllPoints()
    holder:SetPoint(point, relativeTo or UIParent, relPoint or point, x or 0, y or 0)
end

function ApplyExtraButtonFrameAnchor(buttonType)
    -- COMBAT GATE (extra path): the extra holder hosts the anchored
    if buttonType == "extraActionButton"
        and InCombatLockdown() and not inInitSafeWindow
    then
        ActionBarsOwned.pendingExtraButtonRefresh = true
        return
    end
    local HasAnchor = _G.QUI_HasFrameAnchor
    local ApplyAnchor = _G.QUI_ApplyFrameAnchor
    if HasAnchor and ApplyAnchor and HasAnchor(buttonType) then
        ApplyAnchor(buttonType)
        return
    end
    -- NO-OVERRIDE FALLBACK (see ApplyExtraButtonHolderFallbackPosition).
    local holder = buttonType == "extraActionButton"
        and extraBtnState.extraActionHolder
        or extraBtnState.zoneAbilityHolder
    if not holder then return end
    if InCombatLockdown() and not inInitSafeWindow
        and Helpers.FrameMutationRestricted(holder)
    then
        ActionBarsOwned.pendingExtraButtonRefresh = true
        return
    end
    ApplyExtraButtonHolderFallbackPosition(buttonType, holder)
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

    if Helpers.HasSecretValue(point, relPoint, x, y) then return end

    if not point and holder.GetPoint then
        local fallbackPoint, _, fallbackRelPoint, fallbackX, fallbackY = holder:GetPoint(1)
        point, relPoint, x, y = fallbackPoint, fallbackRelPoint, fallbackX, fallbackY
    end

    if Helpers.HasSecretValue(point, relPoint, x, y) then return end

    if not point then return end

    x = tonumber(x) or 0
    y = tonumber(y) or 0
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
            if Helpers.HasSecretValue(point, relativeTo, relativePoint, xOfs, yOfs) then return end
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

    ApplyExtraButtonHolderFallbackPosition(buttonType, holder)

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

    if settings.enabled == true and settings.hideArtwork then
        local visualFrame = GetExtraButtonVisualFrame(buttonType, blizzFrame)
        if visualFrame then
            local visualWidth = visualFrame.GetWidth and Helpers.SafeToNumber(visualFrame:GetWidth(), width) or width
            local visualHeight = visualFrame.GetHeight and Helpers.SafeToNumber(visualFrame:GetHeight(), height) or height
            if visualWidth > 0 then width = visualWidth end
            if visualHeight > 0 then height = visualHeight end
        end
    end

    scale = tonumber(scale) or 1
    if scale <= 0 then scale = 1 end

    return math.max(width * scale, 64), math.max(height * scale, 64)
end

local function GetExtraActionContainerAnchorOffset(container, bar, scale, offsetX, offsetY)
    scale = tonumber(scale) or 1
    if scale <= 0 then scale = 1 end

    offsetX = tonumber(offsetX) or 0
    offsetY = tonumber(offsetY) or 0
    if not container or not bar then return offsetX, offsetY end

    local barWidth = Helpers.SafeToNumber(bar:GetWidth(), 0)
    local barHeight = Helpers.SafeToNumber(bar:GetHeight(), 0)
    if barWidth <= 0 or barHeight <= 0 then return offsetX, offsetY end

    local childLayoutWidth = barWidth
    local childLayoutHeight = barHeight
    if container.respectChildScale then
        childLayoutWidth = childLayoutWidth * scale
        childLayoutHeight = childLayoutHeight * scale
    end

    local layoutWidth = Helpers.SafeToNumber(container.fixedWidth, 0)
    if layoutWidth <= 0 then layoutWidth = childLayoutWidth end
    local minimumWidth = Helpers.SafeToNumber(container.minimumWidth, 0)
    local maximumWidth = Helpers.SafeToNumber(container.maximumWidth, 0)
    if minimumWidth > 0 then layoutWidth = math.max(layoutWidth, minimumWidth) end
    if maximumWidth > 0 then layoutWidth = math.min(layoutWidth, maximumWidth) end

    local layoutHeight = Helpers.SafeToNumber(container.fixedHeight, 0)
    if layoutHeight <= 0 then layoutHeight = childLayoutHeight end
    local minimumHeight = Helpers.SafeToNumber(container.minimumHeight, 0)
    local maximumHeight = Helpers.SafeToNumber(container.maximumHeight, 0)
    if minimumHeight > 0 then layoutHeight = math.max(layoutHeight, minimumHeight) end
    if maximumHeight > 0 then layoutHeight = math.min(layoutHeight, maximumHeight) end

    local visualWidth = barWidth * scale
    local visualHeight = barHeight * scale
    return offsetX + (layoutWidth - visualWidth) / 2,
        offsetY + (visualHeight - layoutHeight) / 2
end

-- drags it back.  We never call ExtraAbilityContainer:RemoveFrame -- it does
function ApplyExtraActionContainerAnchor(holder, offsetX, offsetY, scale)
    local container = ExtraAbilityContainer
    if not container or not holder then return end

    if not extraButtonOriginalParents["extraActionButton"] then
        extraButtonOriginalParents["extraActionButton"] = container:GetParent()
    end

    container.ignoreInLayout = true
    container.ignoreFramePositionManager = true
    ns.SafeCallMethodIfPresent("best-effort-style", container, "SetIsLayoutFrame", false)

    -- takeover is already registered in the manager's showingFrames, and
    -- ourselves: an insecure write into the manager's showingFrames table

    extraBtnState.containerOwned = true

    extraBtnState.hookingSetParent = true
    container:SetParent(holder)
    extraBtnState.hookingSetParent = false

    local anchorX, anchorY = GetExtraActionContainerAnchorOffset(
        container, ExtraActionBarFrame, scale, offsetX, offsetY)

    extraBtnState.hookingSetPoint = true
    if container.ClearAllPointsBase and container.SetPointBase then
        container:ClearAllPointsBase()
        container:SetPointBase("CENTER", holder, "CENTER", anchorX, anchorY)
    else
        container:ClearAllPoints()
        container:SetPoint("CENTER", holder, "CENTER", anchorX, anchorY)
    end
    extraBtnState.hookingSetPoint = false
end

function NeutralizeExtraAbilityContainer()
    local container = ExtraAbilityContainer
    if not container or extraBtnState.containerNeutralized then return end
    if InCombatLockdown() and not inInitSafeWindow then return end
    extraBtnState.containerNeutralized = true

    container:SetScript("OnShow", nil)
    container:SetScript("OnHide", nil)

    local sel = container.Selection
    if sel then
        sel:SetAlpha(0)
        if sel.EnableMouse then sel:EnableMouse(false) end
        if not extraBtnState.containerSelectionHooked then
            extraBtnState.containerSelectionHooked = true
            hooksecurefunc(sel, "Show", function(self)
                self:SetAlpha(0)
                if self.EnableMouse and not InCombatLockdown() then
                    self:EnableMouse(false)
                end
            end)
        end
    end

    if ExtraActionBarFrame and ExtraActionBarFrame:IsMouseEnabled() then
        ExtraActionBarFrame:EnableMouse(false)
    end

    if container.AddFrame and not extraBtnState.containerAddFrameHooked then
        extraBtnState.containerAddFrameHooked = true
        hooksecurefunc(container, "AddFrame", function(_, frame)
            if frame and frame.EnableMouse and not InCombatLockdown() then
                frame:EnableMouse(true)
            end
        end)
    end
end

-- DELIBERATE SAFETY EXCEPTION to the dual-mover invariant: when this
local function ZoneFrameCombatMutable(frame, holder)
    if not InCombatLockdown() or inInitSafeWindow then return true end
    if Helpers.FrameMutationRestricted(frame) then return false end
    if holder and Helpers.FrameMutationRestricted(holder) then return false end
    return true
end

local function IsExtraButtonEnabled(buttonType)
    local settings = GetExtraButtonDB(buttonType)
    return (settings and settings.enabled) == true
end

-- SESSION-LONG OWNERSHIP: either enabled surface acquires the shared
function ShouldOwnExtraAbilityContainer()
    return extraBtnState.containerOwned
        or extraBtnState.zoneOwned
        or IsExtraButtonEnabled("extraActionButton")
        or IsExtraButtonEnabled("zoneAbility")
end

-- DUAL-MOVER INVARIANT (user requirement): extra action and zone ability
-- each keep their OWN mover; outside the deliberate safety exception above
function IsZoneAbilityManaged()
    return extraBtnState.zoneOwned or ShouldOwnExtraAbilityContainer()
end

local function EvictZoneAbilityFrame(scale, offsetX, offsetY)
    local blizzFrame = ZoneAbilityFrame
    local holder = extraBtnState.zoneAbilityHolder
    if not blizzFrame or not holder then return nil, nil end
    if not ZoneFrameCombatMutable(blizzFrame, holder) then
        ActionBarsOwned.pendingExtraButtonRefresh = true
        return nil, nil
    end
    blizzFrame:SetScale(scale)
    blizzFrame.ignoreInLayout = true
    blizzFrame.ignoreFramePositionManager = true
    extraBtnState.hookingSetParent = true
    blizzFrame:SetParent(holder)
    extraBtnState.hookingSetParent = false
    extraBtnState.hookingSetPoint = true
    blizzFrame:ClearAllPoints()
    blizzFrame:SetPoint("CENTER", holder, "CENTER", offsetX, offsetY)
    extraBtnState.hookingSetPoint = false
    extraBtnState.zoneOwned = true
    local container = ExtraAbilityContainer
    if container then
        if not InCombatLockdown() or inInitSafeWindow then
            ns.SafeCallMethodIfPresent("defer-ooc", container, "MarkDirty")
        else
            ActionBarsOwned.pendingExtraButtonRefresh = true
        end
    end
    return blizzFrame, holder
end

function ApplyExtraButtonSettings(buttonType)
    local settings = GetExtraButtonDB(buttonType)
    local enabled = (settings and settings.enabled) == true
    local effectiveSettings = settings or {}
    local scale = enabled and (effectiveSettings.scale or 1.0) or 1.0
    local offsetX = enabled and (effectiveSettings.offsetX or 0) or 0
    local offsetY = enabled and (effectiveSettings.offsetY or 0) or 0

    local blizzFrame
    local holder

    if buttonType == "extraActionButton" then
        if not ShouldOwnExtraAbilityContainer() then return end
        -- COMBAT GATE (load-bearing).  ExtraActionBarFrame owns the secure
        if InCombatLockdown() and not inInitSafeWindow then
            ActionBarsOwned.pendingExtraButtonRefresh = true
            return
        end
        blizzFrame = ExtraActionBarFrame
        holder = extraBtnState.extraActionHolder
        if not blizzFrame or not holder then return end
        blizzFrame:SetScale(scale)
        ApplyExtraActionContainerAnchor(holder, offsetX, offsetY, scale)
        NeutralizeExtraAbilityContainer()
    else
        if not IsZoneAbilityManaged() then return end
        blizzFrame, holder = EvictZoneAbilityFrame(scale, offsetX, offsetY)
        if not blizzFrame or not holder then return end
    end

    local holderWidth, holderHeight = GetExtraButtonHolderSize(
        buttonType, blizzFrame, effectiveSettings, scale)
    holder:SetSize(holderWidth, holderHeight)

    if enabled and effectiveSettings.hideArtwork then
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

    if not enabled or not effectiveSettings.fadeEnabled then
        blizzFrame:SetAlpha(1)
    end

    if not enabled and type(SetupBarMouseover) == "function" then
        SetupBarMouseover(buttonType)
    end
end

pendingExtraButtonReanchor = {}

function QueueExtraButtonReanchor(buttonType)
    if pendingExtraButtonReanchor[buttonType] then return end
    pendingExtraButtonReanchor[buttonType] = true

    C_Timer.After(0, function()
        pendingExtraButtonReanchor[buttonType] = false

        local active
        if buttonType == "zoneAbility" then
            active = IsZoneAbilityManaged()
        else
            active = ShouldOwnExtraAbilityContainer()
        end
        if active then
            ApplyExtraButtonSettings(buttonType)
            ApplyExtraButtonFrameAnchor(buttonType)
        end
    end)
end

function QueueManagedExtraButtonReanchor(buttonType)
    local holder = buttonType == "extraActionButton"
        and extraBtnState.extraActionHolder
        or extraBtnState.zoneAbilityHolder
    local active
    if buttonType == "zoneAbility" then
        active = IsZoneAbilityManaged()
    else
        active = ShouldOwnExtraAbilityContainer()
    end
    if holder and active then
        QueueExtraButtonReanchor(buttonType)
    end
end

function HookExtraButtonPositioning()
    if ExtraActionBarFrame and not extraBtnState.extraActionShowHooked then
        extraBtnState.extraActionShowHooked = true
        hooksecurefunc(ExtraActionBarFrame, "Show", function()
            QueueExtraButtonReanchor("extraActionButton")
        end)
    end

    if ExtraAbilityContainer and not extraBtnState.extraAbilityContainerSetPointHooked then
        extraBtnState.extraAbilityContainerSetPointHooked = true
        hooksecurefunc(ExtraAbilityContainer, "SetPoint", function()
            if extraBtnState.hookingSetPoint then return end
            C_Timer.After(0, function()
                if extraBtnState.hookingSetPoint then return end
                QueueManagedExtraButtonReanchor("extraActionButton")
            end)
        end)
    end

    if ExtraAbilityContainer and not extraBtnState.extraAbilityContainerSetParentHooked then
        extraBtnState.extraAbilityContainerSetParentHooked = true
        hooksecurefunc(ExtraAbilityContainer, "SetParent", function()
            if extraBtnState.hookingSetParent then return end
            C_Timer.After(0, function()
                if extraBtnState.hookingSetParent then return end
                QueueManagedExtraButtonReanchor("extraActionButton")
            end)
        end)
    end

    if ExtraAbilityContainer and not extraBtnState.extraAbilityContainerShowHooked then
        extraBtnState.extraAbilityContainerShowHooked = true
        hooksecurefunc(ExtraAbilityContainer, "Show", function()
            QueueManagedExtraButtonReanchor("extraActionButton")
        end)
    end

    if ExtraAbilityContainer and ExtraAbilityContainer.ApplySystemAnchor
        and not extraBtnState.extraAbilityContainerAnchorHooked then
        extraBtnState.extraAbilityContainerAnchorHooked = true
        hooksecurefunc(ExtraAbilityContainer, "ApplySystemAnchor", function()
            QueueManagedExtraButtonReanchor("extraActionButton")
        end)
    end

    -- legal: the frame has no secure descendant.  The C_Timer.After(0) hop
    local function HookSetParentForType(blizzFrame, buttonType, holder)
        if not blizzFrame then return end
        hooksecurefunc(blizzFrame, "SetParent", function(self, newParent)
            if extraBtnState.hookingSetParent then return end
            if newParent == holder then return end
            C_Timer.After(0, function()
                if extraBtnState.hookingSetParent then return end
                if holder and IsZoneAbilityManaged() then
                    if not ZoneFrameCombatMutable(blizzFrame, holder) then
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
    if ZoneAbilityFrame and not extraBtnState.zoneAbilitySetParentHooked then
        extraBtnState.zoneAbilitySetParentHooked = true
        HookSetParentForType(ZoneAbilityFrame, "zoneAbility", extraBtnState.zoneAbilityHolder)
    end
    if ZoneAbilityFrame and not extraBtnState.zoneAbilityShowHooked then
        extraBtnState.zoneAbilityShowHooked = true
        hooksecurefunc(ZoneAbilityFrame, "Show", function()
            QueueExtraButtonReanchor("zoneAbility")
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

InitializeExtraButtons = function()
    if InCombatLockdown() and not inInitSafeWindow then
        ActionBarsOwned.pendingExtraButtonInit = true
        return
    end

    if not extraBtnState.extraActionHolder then
        extraBtnState.extraActionHolder, extraBtnState.extraActionMover =
            CreateExtraButtonHolder("extraActionButton", "Extra Action Button")
    end
    if not extraBtnState.zoneAbilityHolder then
        extraBtnState.zoneAbilityHolder, extraBtnState.zoneAbilityMover =
            CreateExtraButtonHolder("zoneAbility", "Zone Ability")
    end

    local function applyAll()
        ApplyExtraButtonSettings("extraActionButton")
        ApplyExtraButtonFrameAnchor("extraActionButton")
        ApplyExtraButtonSettings("zoneAbility")
        ApplyExtraButtonFrameAnchor("zoneAbility")
        HookExtraButtonPositioning()
    end

    if inInitSafeWindow then
        applyAll()
    end
    C_Timer.After(0.5, applyAll)
end

RefreshExtraButtons = function()
    ApplyExtraButtonSettings("extraActionButton")
    ApplyExtraButtonFrameAnchor("extraActionButton")
    ApplyExtraButtonSettings("zoneAbility")
    ApplyExtraButtonFrameAnchor("zoneAbility")
    HookExtraButtonPositioning()
end

_G.QUI_ToggleExtraButtonMovers = ToggleExtraButtonMovers
_G.QUI_RefreshExtraButtons = RefreshExtraButtons
ActionBarsOwned.extraBtnState = extraBtnState

end
