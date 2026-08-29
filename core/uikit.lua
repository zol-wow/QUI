local ADDON_NAME, ns = ...

local UIKit = {}
ns.UIKit = UIKit

function ns.IsSkinningEnabled()
    local p = _G.QUI and _G.QUI.db and _G.QUI.db.profile
    if not (p and p.skinning) then return true end
    return p.skinning.enabled ~= false
end

local LSM = ns.LSM
local Helpers = ns.Helpers
local DEFAULT_FONT = "Fonts\\FRIZQT__.TTF"

local function CJKFont(fs, p, s, f)
    if ns.Helpers and ns.Helpers.ApplyFontWithFallback then
        ns.Helpers.ApplyFontWithFallback(fs, p, s, f)
    else
        fs:SetFont(p, s, f)
    end
end
local floor = math.floor
local max = math.max
local next = next
local pairs = pairs
local pcall = pcall
local type = type
local unpack = unpack or table.unpack
local InCombatLockdown = InCombatLockdown

local scaleRefreshRegistry = (Helpers and Helpers.CreateStateTable and Helpers.CreateStateTable()) or setmetatable({}, { __mode = "k" })
local borderLineState = (Helpers and Helpers.CreateStateTable and Helpers.CreateStateTable()) or setmetatable({}, { __mode = "k" })
local backdropBorderState = (Helpers and Helpers.CreateStateTable and Helpers.CreateStateTable()) or setmetatable({}, { __mode = "k" })
local iconState = (Helpers and Helpers.CreateStateTable and Helpers.CreateStateTable()) or setmetatable({}, { __mode = "k" })
local accentCheckboxState = (Helpers and Helpers.CreateStateTable and Helpers.CreateStateTable()) or setmetatable({}, { __mode = "k" })
local chevronCaretState = (Helpers and Helpers.CreateStateTable and Helpers.CreateStateTable()) or setmetatable({}, { __mode = "k" })
local valueAnimationState = (Helpers and Helpers.CreateStateTable and Helpers.CreateStateTable()) or setmetatable({}, { __mode = "k" })

local DEFAULT_CHECKBOX_COLORS = {
    accent = {0.376, 0.647, 0.980},
    accentHover = {0.506, 0.737, 1.0},
    toggleOff = {0.18, 0.18, 0.20},
}

local GetCore = Helpers.GetCore

local function Round(value)
    return floor((value or 0) + 0.5)
end

local function GetPixelSize(frame)
    local core = GetCore()
    return (core and core.GetPixelSize and core:GetPixelSize(frame)) or 1
end

local function Pixels(value, frame)
    local core = GetCore()
    if core and core.Pixels then
        return core:Pixels(Round(value or 0), frame)
    end
    return Round(value or 0)
end

function UIKit.Pixels(value, frame)
    return Pixels(value, frame)
end

local function SetRegionSizePx(region, widthPixels, heightPixels, contextFrame)
    if not region then return end
    local frame = contextFrame or region
    if widthPixels and heightPixels then
        region:SetSize(Pixels(widthPixels, frame), Pixels(heightPixels, frame))
    elseif widthPixels then
        region:SetWidth(Pixels(widthPixels, frame))
    elseif heightPixels then
        region:SetHeight(Pixels(heightPixels, frame))
    end
end

local function ApplyColorTexture(texture, r, g, b, a)
    if not texture then return end
    texture:SetColorTexture(r or 0, g or 0, b or 0, a or 1)
    UIKit.DisablePixelSnap(texture)
end

local function ApplyBorderLineColor(edges, color)
    if not edges or not color then return end
    local r, g, b, a = color[1], color[2], color[3], color[4] or 1
    for _, line in pairs(edges) do
        ApplyColorTexture(line, r, g, b, a)
    end
end

UIKit._buildEdgeTexturesCount = 0
local function BuildEdgeTextures(frame, store, opts)
    local layer = (opts and opts.layer) or "BORDER"
    local subLevel = opts and opts.subLevel
    store.top = frame:CreateTexture(nil, layer, nil, subLevel)
    store.bottom = frame:CreateTexture(nil, layer, nil, subLevel)
    store.left = frame:CreateTexture(nil, layer, nil, subLevel)
    store.right = frame:CreateTexture(nil, layer, nil, subLevel)
    UIKit._buildEdgeTexturesCount = UIKit._buildEdgeTexturesCount + 1
    return store
end

local function RefreshBorderLines(frame)
    local state = borderLineState[frame]
    if not state or not state.edges then return end

    if state.hidden or (state.sizePixels or 0) <= 0 then
        for _, line in pairs(state.edges) do
            line:Hide()
        end
        return
    end

    local size = max(GetPixelSize(frame), Pixels(state.sizePixels or 1, frame))
    local color = state.color or { 0, 0, 0, 1 }
    local top = state.edges.top
    local bottom = state.edges.bottom
    local left = state.edges.left
    local right = state.edges.right

    top:ClearAllPoints()
    top:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
    top:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
    top:SetHeight(size)
    ApplyColorTexture(top, color[1], color[2], color[3], color[4] or 1)

    bottom:ClearAllPoints()
    bottom:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0)
    bottom:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
    bottom:SetHeight(size)
    ApplyColorTexture(bottom, color[1], color[2], color[3], color[4] or 1)

    left:ClearAllPoints()
    left:SetPoint("TOPLEFT", top, "BOTTOMLEFT", 0, 0)
    left:SetPoint("BOTTOMLEFT", bottom, "TOPLEFT", 0, 0)
    left:SetWidth(size)
    ApplyColorTexture(left, color[1], color[2], color[3], color[4] or 1)

    right:ClearAllPoints()
    right:SetPoint("TOPRIGHT", top, "BOTTOMRIGHT", 0, 0)
    right:SetPoint("BOTTOMRIGHT", bottom, "TOPRIGHT", 0, 0)
    right:SetWidth(size)
    ApplyColorTexture(right, color[1], color[2], color[3], color[4] or 1)

    for _, line in pairs(state.edges) do
        line:Show()
    end
end

local function ForgetBorderLineState(frame)
    borderLineState[frame] = nil
    local callbacks = scaleRefreshRegistry[frame]
    if callbacks then
        callbacks.borderLines = nil
    end
end

local function ApplyBackdropBorderLayout(borderFrame)
    local state = backdropBorderState[borderFrame]
    if not state or not state.parent then return end

    if state.hidden or (state.sizePixels or 0) <= 0 then
        borderFrame:Hide()
    else
        borderFrame:Show()
    end

    UIKit.SetInsetPointsPx(
        borderFrame,
        state.parent,
        -(state.sizePixels or 1),
        -(state.sizePixels or 1),
        -(state.sizePixels or 1),
        -(state.sizePixels or 1)
    )

    local color = state.color or { 0, 0, 0, 1 }
    UIKit.UpdateBorderLines(
        borderFrame,
        state.sizePixels or 1,
        color[1],
        color[2],
        color[3],
        color[4] or 1,
        state.hidden
    )
end

local function ApplyBackdropBorderState(borderFrame)
    local state = backdropBorderState[borderFrame]
    if not state then return end
    ApplyBackdropBorderLayout(borderFrame)
end

local function RefreshIconLayout(iconFrame)
    local state = iconState[iconFrame]
    if not state then return end

    UIKit.SetSizePx(iconFrame, state.sizePixels or 0, state.sizePixels or 0)

    if state.borderTexture then
        state.borderTexture:SetAllPoints(iconFrame)
        ApplyColorTexture(state.borderTexture, unpack(state.color or { 0, 0, 0, 1 }))
    end

    if state.texture then
        UIKit.SetInsetPointsPx(state.texture, iconFrame, state.borderSizePixels or 1)
        local core = GetCore()
        if core and core.ApplyPixelSnapping then
            core:ApplyPixelSnapping(state.texture)
        end
    end
end

function UIKit.UpdateIconLayout(iconFrame, sizePixels, borderSizePixels, r, g, b, a)
    if not iconFrame then
        return
    end

    local state = iconState[iconFrame]
    if not state then
        if sizePixels then
            UIKit.SetSizePx(iconFrame, sizePixels, sizePixels)
        end
        return
    end

    if sizePixels then
        state.sizePixels = sizePixels
    end
    if borderSizePixels then
        state.borderSizePixels = borderSizePixels
    end
    if r ~= nil or g ~= nil or b ~= nil or a ~= nil then
        local color = state.color
        if not color then
            color = {}
            state.color = color
        end
        color[1] = r or color[1] or 0
        color[2] = g or color[2] or 0
        color[3] = b or color[3] or 0
        color[4] = a or color[4] or 1
    end

    RefreshIconLayout(iconFrame)
end

local function RefreshAccentCheckboxLayout(checkbox)
    local state = accentCheckboxState[checkbox]
    if not state then return end

    UIKit.SetSizePx(checkbox, state.sizePixels or 25, state.sizePixels or 25)

    if checkbox.mark then
        local markSize = (state.sizePixels or 25) * 1.4
        UIKit.SetSizePx(checkbox.mark, markSize, markSize)
        UIKit.SetPointPx(checkbox.mark, "CENTER", checkbox, "CENTER", 0, 0)
    end
end

local function RefreshChevronCaretLayout(caret)
    local state = chevronCaretState[caret]
    if not state or not caret or not caret.line1 or not caret.line2 then return end

    UIKit.SetSizePx(caret, state.sizePixels or 10, state.sizePixels or 10)
    UIKit.SetPointPx(
        caret,
        state.point or "RIGHT",
        state.relativeTo or state.parent,
        state.relativePoint or state.point or "RIGHT",
        state.xPixels or 0,
        state.yPixels or 0
    )

    SetRegionSizePx(caret.line1, state.lineWidthPixels or 6, state.lineHeightPixels or 1, caret)
    SetRegionSizePx(caret.line2, state.lineWidthPixels or 6, state.lineHeightPixels or 1, caret)

    if state.expanded then
        caret.line1:SetRotation(math.rad(-45))
        caret.line1:ClearAllPoints()
        UIKit.SetPointPx(caret.line1, "CENTER", caret, "CENTER", -2, 0)

        caret.line2:SetRotation(math.rad(45))
        caret.line2:ClearAllPoints()
        UIKit.SetPointPx(caret.line2, "CENTER", caret, "CENTER", 2, 0)
    else
        local collapsedDirection = state.collapsedDirection or "left"
        if collapsedDirection == "right" then
            caret.line1:SetRotation(math.rad(-45))
            caret.line1:ClearAllPoints()
            UIKit.SetPointPx(caret.line1, "CENTER", caret, "CENTER", 1, 2)

            caret.line2:SetRotation(math.rad(45))
            caret.line2:ClearAllPoints()
            UIKit.SetPointPx(caret.line2, "CENTER", caret, "CENTER", 1, -2)
        else
            caret.line1:SetRotation(math.rad(45))
            caret.line1:ClearAllPoints()
            UIKit.SetPointPx(caret.line1, "CENTER", caret, "CENTER", -1, 2)

            caret.line2:SetRotation(math.rad(-45))
            caret.line2:ClearAllPoints()
            UIKit.SetPointPx(caret.line2, "CENTER", caret, "CENTER", -1, -2)
        end
    end

    local color = state.color or { 1, 1, 1, 1 }
    ApplyColorTexture(caret.line1, color[1], color[2], color[3], color[4] or 1)
    ApplyColorTexture(caret.line2, color[1], color[2], color[3], color[4] or 1)
end

function UIKit.RegisterScaleRefresh(owner, key, refreshFn)
    if not owner then return end
    if type(key) == "function" and refreshFn == nil then
        refreshFn = key
        key = refreshFn
    end
    if type(refreshFn) ~= "function" then return end

    local callbacks = scaleRefreshRegistry[owner]
    if not callbacks then
        callbacks = {}
        scaleRefreshRegistry[owner] = callbacks
    end
    callbacks[key or refreshFn] = refreshFn
end

function UIKit.RefreshScaleBoundWidgets()
    for owner, callbacks in pairs(scaleRefreshRegistry) do
        for _, refreshFn in pairs(callbacks) do
            ns.SafeCall("bulkhead", refreshFn, owner)
        end
    end
end

function UIKit.RefreshPixelBorders()
    local failedBorderFrames
    for frame in pairs(borderLineState) do
        local ok = ns.SafeCall("bulkhead", RefreshBorderLines, frame)
        if not ok then
            failedBorderFrames = failedBorderFrames or {}
            failedBorderFrames[#failedBorderFrames + 1] = frame
        end
    end
    if failedBorderFrames then
        for i = 1, #failedBorderFrames do
            ForgetBorderLineState(failedBorderFrames[i])
        end
    end
    for borderFrame in pairs(backdropBorderState) do
        ApplyBackdropBorderLayout(borderFrame)
    end
end

local queuedScaleRefreshTicks = 0
local scaleRefreshFrame

local function RunQueuedScaleRefresh()
    UIKit.RefreshScaleBoundWidgets()
    UIKit.RefreshPixelBorders()
end

local function OnScaleRefreshUpdate(self)
    RunQueuedScaleRefresh()
    queuedScaleRefreshTicks = queuedScaleRefreshTicks - 1
    if queuedScaleRefreshTicks <= 0 then
        self:SetScript("OnUpdate", nil)
    end
end

function UIKit.QueueScaleRefresh(ticks)
    ticks = max(Round(ticks or 1), 1)

    if type(CreateFrame) ~= "function" then
        RunQueuedScaleRefresh()
        return
    end

    queuedScaleRefreshTicks = max(queuedScaleRefreshTicks, ticks)
    if not scaleRefreshFrame then
        scaleRefreshFrame = CreateFrame("Frame")
    end

    scaleRefreshFrame:SetScript("OnUpdate", OnScaleRefreshUpdate)
end

local animationDriver
local animationDriverOnUpdate

local function EnsureAnimationDriver()
    if animationDriver then return animationDriver end
    animationDriver = CreateFrame("Frame")
    animationDriverOnUpdate = function(self, elapsed)
        local anyActive = false
        for owner, states in pairs(valueAnimationState) do
            for key, state in pairs(states) do
                state.elapsed = math.min((state.elapsed or 0) + elapsed, state.duration)
                local progress = (state.duration > 0) and (state.elapsed / state.duration) or 1
                local value = state.fromValue + ((state.toValue - state.fromValue) * progress)
                if state.onUpdate then
                    ns.SafeCall("bulkhead", state.onUpdate, owner, value, progress)
                end
                if progress >= 1 then
                    states[key] = nil
                    if state.onFinish then
                        ns.SafeCall("bulkhead", state.onFinish, owner, state.toValue)
                    end
                else
                    anyActive = true
                end
            end
            if not next(states) then
                valueAnimationState[owner] = nil
            end
        end
        if not anyActive then
            self:SetScript("OnUpdate", nil)
        end
    end
    animationDriver:SetScript("OnUpdate", animationDriverOnUpdate)
    return animationDriver
end

function UIKit.CancelValueAnimation(owner, key)
    local states = owner and valueAnimationState[owner]
    if not states then return end
    states[key or "default"] = nil
    if not next(states) then
        valueAnimationState[owner] = nil
    end
end

function UIKit.AnimateValue(owner, key, options)
    if not owner or type(options) ~= "table" then return end
    if type(options.onUpdate) ~= "function" then return end

    local animKey = key or "default"
    local states = valueAnimationState[owner]
    if not states then
        states = {}
        valueAnimationState[owner] = states
    end

    states[animKey] = {
        fromValue = options.fromValue or 0,
        toValue = options.toValue or 0,
        duration = math.max(0, options.duration or 0.16),
        elapsed = 0,
        onUpdate = options.onUpdate,
        onFinish = options.onFinish,
    }

    ns.SafeCall("bulkhead", options.onUpdate, owner, options.fromValue or 0, 0)
    local driver = EnsureAnimationDriver()
    driver:SetScript("OnUpdate", animationDriverOnUpdate)
end

function UIKit.DisablePixelSnap(obj)
    if not obj then return end
    if obj.SetSnapToPixelGrid then obj:SetSnapToPixelGrid(false) end
    if obj.SetTexelSnappingBias then obj:SetTexelSnappingBias(0) end

    if obj.GetStatusBarTexture then
        local ok, tex = pcall(obj.GetStatusBarTexture, obj)
        if ok and tex then
            if tex.SetSnapToPixelGrid then tex:SetSnapToPixelGrid(false) end
            if tex.SetTexelSnappingBias then tex:SetTexelSnappingBias(0) end
        end
    end
end

function UIKit.SetSizePx(frame, widthPixels, heightPixels)
    if not frame then return end
    local core = GetCore()
    if core and core.SetPixelPerfectSize then
        core:SetPixelPerfectSize(frame, widthPixels, heightPixels)
        return
    end
    SetRegionSizePx(frame, widthPixels, heightPixels, frame)
end

function UIKit.SetHeightPx(frame, heightPixels)
    if not frame then return end
    local core = GetCore()
    if core and core.SetPixelPerfectHeight then
        core:SetPixelPerfectHeight(frame, heightPixels)
        return
    end
    SetRegionSizePx(frame, nil, heightPixels, frame)
end

function UIKit.SetPointPx(frame, point, relativeTo, relativePoint, xPixels, yPixels)
    if not frame then return end
    local core = GetCore()
    if core and core.SetPixelPerfectPoint then
        core:SetPixelPerfectPoint(frame, point, relativeTo, relativePoint, xPixels, yPixels)
        return
    end
    frame:SetPoint(point, relativeTo, relativePoint, Pixels(xPixels or 0, frame), Pixels(yPixels or 0, frame))
end

function UIKit.SetInsetPointsPx(frame, anchor, leftPixels, rightPixels, topPixels, bottomPixels)
    if not frame then return end
    anchor = anchor or frame:GetParent()
    if not anchor then return end

    if rightPixels == nil and topPixels == nil and bottomPixels == nil then
        rightPixels = leftPixels or 0
        topPixels = leftPixels or 0
        bottomPixels = leftPixels or 0
    else
        rightPixels = rightPixels or 0
        topPixels = topPixels or 0
        bottomPixels = bottomPixels or 0
    end

    local px = GetPixelSize(frame)
    frame:ClearAllPoints()
    frame:SetPoint("TOPLEFT", anchor, "TOPLEFT", Round(leftPixels or 0) * px, -Round(topPixels) * px)
    frame:SetPoint("BOTTOMRIGHT", anchor, "BOTTOMRIGHT", -Round(rightPixels) * px, Round(bottomPixels) * px)
end

function UIKit.ResolveFontPath(fontName)
    if fontName and LSM then
        local path = LSM:Fetch("font", fontName)
        if path then return path end
    end
    return Helpers.GetGeneralFont()
end

function UIKit.GetBackdropInfo(borderTextureName, borderSizePixels, frame)
    local edgeFile = nil
    local edgeSize = 0

    if borderTextureName and borderTextureName ~= "None" and LSM then
        edgeFile = LSM:Fetch("border", borderTextureName)
        edgeSize = Pixels(borderSizePixels or 1, frame)
    end

    local px = GetPixelSize(frame)
    return {
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = edgeFile,
        tile = false,
        tileSize = 0,
        edgeSize = edgeSize,
        insets = { left = 0, right = px, top = 0, bottom = px },
    }
end

function UIKit.CreateBorderLines(frame)
    local state = borderLineState[frame]
    if state and state.edges then return state.edges end

    local borders = BuildEdgeTextures(frame, {}, { layer = "OVERLAY", subLevel = 7 })

    for _, line in pairs(borders) do
        ApplyColorTexture(line, 0, 0, 0, 1)
    end

    borderLineState[frame] = {
        edges = borders,
        sizePixels = 1,
        color = { 0, 0, 0, 1 },
        hidden = false,
    }

    UIKit.RegisterScaleRefresh(frame, "borderLines", RefreshBorderLines)
    RefreshBorderLines(frame)
    UIKit.QueueScaleRefresh(2)
    return borders
end

function UIKit.UpdateBorderLines(frame, sizePixels, r, g, b, a, hide)
    local state = borderLineState[frame]
    if not state then
        UIKit.CreateBorderLines(frame)
        state = borderLineState[frame]
    end
    if not state then return end

    local newSize = sizePixels or state.sizePixels or 1
    local newR, newG, newB, newA = r or 0, g or 0, b or 0, a or 1
    local newHidden = hide or (newSize or 0) <= 0
    local color = state.color
    local sameSize = state.sizePixels == newSize
    local sameHidden = state.hidden == newHidden
    if sameSize and sameHidden and color
        and color[1] == newR
        and color[2] == newG
        and color[3] == newB
        and color[4] == newA then
        return
    end

    state.sizePixels = newSize
    if not color then
        color = {}
        state.color = color
    end
    color[1], color[2], color[3], color[4] = newR, newG, newB, newA
    state.hidden = newHidden

    if sameSize and sameHidden then
        ApplyBorderLineColor(state.edges, color)
        return
    end

    RefreshBorderLines(frame)
end

function UIKit.CreateText(parent, fontSize, fontPath, fontOutline, layer)
    local text = parent:CreateFontString(nil, layer or "OVERLAY")
    local path = fontPath or UIKit.ResolveFontPath()
    local outline = fontOutline or (Helpers and Helpers.GetGeneralFontOutline and Helpers.GetGeneralFontOutline()) or "OUTLINE"
    local core = GetCore()
    if core and core.ApplyFont then
        core:ApplyFont(text, parent, fontSize, path, outline)
    else
        CJKFont(text, path, fontSize, outline)
    end
    text:SetTextColor(1, 1, 1, 1)
    text:SetWordWrap(false)
    return text
end

function UIKit.CreateBackground(parent, r, g, b, a)
    local bg = parent:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetTexture("Interface\\Buttons\\WHITE8x8")
    bg:SetVertexColor(r or 0.149, g or 0.149, b or 0.149, a or 1)
    UIKit.DisablePixelSnap(bg)
    return bg
end

function UIKit.CreateBackdropBorder(parent, borderSizePixels, r, g, b, a)
    local border = parent.Border
    if not border or not backdropBorderState[border] then
        border = CreateFrame("Frame", nil, parent)
        border:SetFrameStrata(parent:GetFrameStrata())
        border:SetFrameLevel(parent:GetFrameLevel() + 1)
        UIKit.CreateBorderLines(border)
        backdropBorderState[border] = { parent = parent }
        UIKit.RegisterScaleRefresh(border, "backdropBorder", ApplyBackdropBorderLayout)

        function border:SetBackdrop(backdrop)
            local state = backdropBorderState[self]
            if not state then return end
            if not backdrop then
                state.hidden = true
                ApplyBackdropBorderState(self)
                return
            end

            local edgeSize = backdrop.edgeSize or 0
            local pixelSize = GetPixelSize(self)
            local sizePixels = edgeSize > 0 and max(0, Round(edgeSize / pixelSize)) or 0
            state.sizePixels = sizePixels
            state.hidden = sizePixels <= 0
            ApplyBackdropBorderState(self)
        end

        function border:SetBackdropBorderColor(br, bg_, bb, ba)
            local state = backdropBorderState[self]
            if not state then return end
            state.color = { br or 0, bg_ or 0, bb or 0, ba or 1 }
            ApplyBackdropBorderState(self)
        end

        function border:SetBackdropColor()
        end
    end

    local state = backdropBorderState[border]
    state.parent = parent
    state.sizePixels = borderSizePixels or 1
    state.color = { r or 0, g or 0, b or 0, a or 1 }
    state.hidden = (borderSizePixels or 0) <= 0

    parent.Border = border
    ApplyBackdropBorderLayout(border)
    return border
end

function UIKit.CreateAccentCheckbox(parent, options)
    options = options or {}
    local size = options.size or 25
    local checked = options.checked and true or false
    local onChange = options.onChange

    local colors = options.colors
    if not colors and QUI and QUI.GUI and QUI.GUI.Colors then
        colors = QUI.GUI.Colors
    end
    colors = colors or DEFAULT_CHECKBOX_COLORS

    local accent = colors.accent or {0.204, 0.827, 0.6, 1}
    local accentHover = colors.accentHover or accent
    local bgDark = colors.bg or {0.051, 0.067, 0.09, 1}

    local checkbox = CreateFrame("Button", nil, parent)
    accentCheckboxState[checkbox] = { sizePixels = size }
    UIKit.SetSizePx(checkbox, size, size)

    checkbox.bg = UIKit.CreateBackground(checkbox)
    UIKit.CreateBorderLines(checkbox)

    local mark = checkbox:CreateTexture(nil, "OVERLAY")
    mark:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
    mark:SetDesaturated(true)
    mark:SetVertexColor(bgDark[1], bgDark[2], bgDark[3], 1)
    mark:Hide()
    checkbox.mark = mark

    local hovered = false
    local function UpdateVisual()
        if checked then
            checkbox.bg:SetVertexColor(accent[1], accent[2], accent[3], 1)
            if hovered then
                UIKit.UpdateBorderLines(checkbox, 1, accentHover[1], accentHover[2], accentHover[3], 1)
            else
                UIKit.UpdateBorderLines(checkbox, 1, accent[1], accent[2], accent[3], 1)
            end
            checkbox.mark:Show()
        else
            checkbox.bg:SetVertexColor(1, 1, 1, 0.06)
            if hovered then
                UIKit.UpdateBorderLines(checkbox, 1, accent[1], accent[2], accent[3], 1)
            else
                UIKit.UpdateBorderLines(checkbox, 1, 1, 1, 1, 0.2)
            end
            checkbox.mark:Hide()
        end
    end

    checkbox._RefreshVisual = UpdateVisual
    UIKit.RegisterScaleRefresh(checkbox, "accentCheckbox", function(owner)
        RefreshAccentCheckboxLayout(owner)
        if owner._RefreshVisual then owner:_RefreshVisual() end
    end)
    RefreshAccentCheckboxLayout(checkbox)

    function checkbox:GetChecked()
        return checked
    end

    function checkbox:SetChecked(val, skipOnChange)
        checked = val and true or false
        UpdateVisual()
        if not skipOnChange and onChange then
            onChange(checked)
        end
    end

    function checkbox:Toggle(skipOnChange)
        self:SetChecked(not checked, skipOnChange)
    end

    function checkbox:SetHovered(val)
        hovered = val and true or false
        UpdateVisual()
    end

    checkbox:SetScript("OnClick", function(self)
        self:Toggle()
    end)
    checkbox:SetScript("OnEnter", function(self)
        self:SetHovered(true)
    end)
    checkbox:SetScript("OnLeave", function(self)
        self:SetHovered(false)
    end)

    checkbox:SetChecked(checked, true)
    return checkbox
end

function UIKit.CreateChevronCaret(parent, options)
    options = options or {}

    local caret = CreateFrame("Frame", nil, parent)
    caret.line1 = caret:CreateTexture(nil, options.layer or "OVERLAY")
    caret.line2 = caret:CreateTexture(nil, options.layer or "OVERLAY")

    chevronCaretState[caret] = {
        parent = parent,
        point = options.point or "RIGHT",
        relativeTo = options.relativeTo or parent,
        relativePoint = options.relativePoint or options.point or "RIGHT",
        xPixels = options.xPixels or 0,
        yPixels = options.yPixels or 0,
        sizePixels = options.sizePixels or 10,
        lineWidthPixels = options.lineWidthPixels or 6,
        lineHeightPixels = options.lineHeightPixels or 1,
        expanded = options.expanded and true or false,
        collapsedDirection = options.collapsedDirection or "left",
        color = {
            options.r or 1,
            options.g or 1,
            options.b or 1,
            options.a or 1,
        },
    }

    UIKit.RegisterScaleRefresh(caret, "chevronCaret", function(owner)
        RefreshChevronCaretLayout(owner)
    end)
    RefreshChevronCaretLayout(caret)
    return caret
end

function UIKit.SetChevronCaretExpanded(caret, expanded)
    local state = chevronCaretState[caret]
    if not state then return end
    state.expanded = expanded and true or false
    RefreshChevronCaretLayout(caret)
end

function UIKit.SetChevronCaretColor(caret, r, g, b, a)
    local state = chevronCaretState[caret]
    if not state then return end
    state.color = { r or 1, g or 1, b or 1, a or 1 }
    RefreshChevronCaretLayout(caret)
end

function UIKit.CreateIcon(parent, size, borderSizePixels, r, g, b, a)
    local iconFrame = CreateFrame("Frame", nil, parent)
    UIKit.SetSizePx(iconFrame, size, size)
    iconFrame:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, 0)

    local border = iconFrame:CreateTexture(nil, "BACKGROUND", nil, -8)
    border:SetAllPoints(iconFrame)
    ApplyColorTexture(border, r or 0, g or 0, b or 0, a or 1)
    iconFrame.border = border

    local iconTexture = iconFrame:CreateTexture(nil, "ARTWORK")
    UIKit.SetInsetPointsPx(iconTexture, iconFrame, borderSizePixels or 1)
    iconTexture:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    local core = GetCore()
    if core and core.ApplyPixelSnapping then
        core:ApplyPixelSnapping(iconTexture)
    end
    iconFrame.texture = iconTexture

    iconState[iconFrame] = {
        sizePixels = size,
        borderSizePixels = borderSizePixels or 1,
        color = { r or 0, g or 0, b or 0, a or 1 },
        texture = iconTexture,
        borderTexture = border,
    }
    UIKit.RegisterScaleRefresh(iconFrame, "iconLayout", RefreshIconLayout)

    parent.icon = iconFrame
    parent.iconTexture = iconTexture
    parent.iconBorder = border
    return iconFrame
end

local BUTTON_FALLBACK_COLORS = {
    accent = { 0.204, 0.827, 0.6, 1 },
    text = { 1, 1, 1, 1 },
    textDim = { 1, 1, 1, 0.6 },
}

function UIKit.CreateButton(parent, opts)
    opts = opts or {}
    local gui = QUI and QUI.GUI
    local C = (gui and gui.Colors) or BUTTON_FALLBACK_COLORS
    local override = opts.colors
    local textColor = (override and override.text) or C.text or BUTTON_FALLBACK_COLORS.text
    local textDim = (override and override.textDim) or C.textDim or BUTTON_FALLBACK_COLORS.textDim
    local function accentRGB()
        local a = override and override.accent
        if type(a) == "function" then
            local r, g, b = a()
            if type(r) == "table" then return r[1], r[2], r[3] end
            return r, g, b
        elseif type(a) == "table" then
            return a[1], a[2], a[3]
        end
        return UIKit.GetAccentColor()
    end
    local variant = opts.variant or "ghost"

    local button = CreateFrame("Button", nil, parent)
    button:SetSize(opts.width or 120, opts.height or 22)

    UIKit.CreateBorderLines(button)

    local hoverBg = button:CreateTexture(nil, "BACKGROUND")
    hoverBg:SetAllPoints(button)
    hoverBg:SetColorTexture(1, 1, 1, 0.06)
    hoverBg:Hide()
    button._hoverBg = hoverBg

    local btnText = button:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    btnText:SetPoint("CENTER", 0, 0)
    btnText:SetText(opts.text or "Button")
    button.text = btnText

    local function ApplyButtonVariant(btn, variantName)
        if variantName == "primary" then
            local ar, ag, ab = accentRGB()
            UIKit.UpdateBorderLines(btn, 1, ar, ag, ab, 0.5)
            if btn.text then btn.text:SetTextColor(ar, ag, ab, 1) end
        else
            UIKit.UpdateBorderLines(btn, 1, 1, 1, 1, 0.2)
            if btn.text then btn.text:SetTextColor(textDim[1], textDim[2], textDim[3], 1) end
        end
    end
    ApplyButtonVariant(button, variant)

    local f, _, flags = button.text:GetFont()
    local fontPath = f
    if not fontPath then
        fontPath = (UIKit.ResolveFontPath and gui and gui.GetFontPath and UIKit.ResolveFontPath(gui:GetFontPath()))
            or (gui and gui.GetFontPath and gui:GetFontPath())
            or DEFAULT_FONT
    end
    CJKFont(button.text, fontPath, opts.fontSize or 10, flags or "")
    button:SetHeight(opts.height or 22)
    if not opts.width or opts.width <= 0 then
        button:SetWidth((button.text:GetStringWidth() or 0) + 24)
    end

    button:SetScript("OnEnter", function(self)
        if variant == "primary" then
            local ar, ag, ab = accentRGB()
            UIKit.UpdateBorderLines(self, 1, ar, ag, ab, 1)
            self._hoverBg:SetColorTexture(ar, ag, ab, 0.08)
        else
            if self.text then self.text:SetTextColor(textColor[1], textColor[2], textColor[3], 1) end
            self._hoverBg:SetColorTexture(1, 1, 1, 0.06)
        end
        self._hoverBg:Show()
    end)
    button:SetScript("OnLeave", function(self)
        if variant == "primary" then
            local ar, ag, ab = accentRGB()
            UIKit.UpdateBorderLines(self, 1, ar, ag, ab, 0.5)
        else
            if self.text then self.text:SetTextColor(textDim[1], textDim[2], textDim[3], 1) end
        end
        self._hoverBg:Hide()
    end)
    button:SetScript("OnMouseDown", function(self)
        if self.text then self.text:SetPoint("CENTER", 0, -1) end
        self._hoverBg:SetAlpha(1.4)
    end)
    button:SetScript("OnMouseUp", function(self)
        if self.text then self.text:SetPoint("CENTER", 0, 0) end
        self._hoverBg:SetAlpha(1)
    end)

    if opts.onClick then
        button:SetScript("OnClick", opts.onClick)
    end

    function button:SetText(newText)
        btnText:SetText(newText)
    end

    function button:SetBorderColor(r, g, b, a)
        UIKit.UpdateBorderLines(self, 1, r, g, b, a or 1, false)
    end

    button.SetFieldBorderColor = button.SetBorderColor

    return button
end

function UIKit.GetAccentColor()
    local gui = QUI and QUI.GUI
    local core = Helpers.GetCore and Helpers.GetCore()
    local general = core and core.db and core.db.profile and core.db.profile.general
    if gui and gui.ResolveThemePreset and general and general.themePreset then
        return gui:ResolveThemePreset(general.themePreset)
    end
    local custom = general and general.addonAccentColor
    if custom and custom[1] then return custom[1], custom[2], custom[3] end
    local accent = (gui and gui.Colors and gui.Colors.accent) or BUTTON_FALLBACK_COLORS.accent
    return accent[1], accent[2], accent[3]
end

function UIKit.CreateCloseButton(parent, opts)
    opts = opts or {}
    local size = opts.size or 22

    local close = CreateFrame("Button", nil, parent)
    close:SetSize(size, size)
    if opts.point then
        close:SetPoint(opts.point, opts.relativeTo or parent, opts.relativePoint or opts.point, opts.x or 0, opts.y or 0)
    end

    if opts.onClick then close:SetScript("OnClick", opts.onClick) end
    UIKit.SkinCloseButton(close, opts)

    return close
end

function UIKit.CreateIconButton(parent, opts)
    opts = opts or {}
    local btn = CreateFrame("Button", opts.name, parent)
    btn:SetSize(opts.size or 18, opts.size or 18)
    btn:RegisterForClicks(opts.registerClicks or "LeftButtonUp")

    local idle = opts.idleAlpha or 0.85
    local brighten = false

    if opts.atlasTriplet then
        btn:SetNormalAtlas(opts.atlasTriplet .. "-Up")
        btn:SetPushedAtlas(opts.atlasTriplet .. "-Down")
        btn:SetHighlightAtlas(opts.atlasTriplet .. "-Mouseover")
    elseif opts.portrait then
        local icon = btn:CreateTexture(nil, "ARTWORK")
        icon:SetAllPoints()
        SetPortraitTexture(icon, "player")
        btn.icon = icon
        if opts.squareHighlight then btn:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD") end
    elseif opts.atlas or opts.icon then
        local icon = btn:CreateTexture(nil, "ARTWORK")
        icon:SetAllPoints()
        if opts.atlas then icon:SetAtlas(opts.atlas) else icon:SetTexture(opts.icon) end
        btn.icon = icon
        if opts.squareHighlight then
            btn:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
        else
            icon:SetVertexColor(idle, idle, idle, 1)
            brighten = true
        end
    end

    local function showTooltip(self)
        local tip = opts.tooltip
        if not tip then return end
        GameTooltip:SetOwner(self, opts.tooltipAnchor or "ANCHOR_RIGHT")
        if type(tip) == "function" then tip(self) else GameTooltip:SetText(tip) end
        GameTooltip:Show()
    end

    btn:SetScript("OnEnter", function(self)
        if brighten and self.icon then self.icon:SetVertexColor(1, 1, 1, 1) end
        showTooltip(self)
        if opts.onEnter then opts.onEnter(self) end
    end)
    btn:SetScript("OnLeave", function(self)
        if brighten and self.icon then self.icon:SetVertexColor(idle, idle, idle, 1) end
        GameTooltip:Hide()
        if opts.onLeave then opts.onLeave(self) end
    end)
    if brighten then
        btn:SetScript("OnMouseDown", function(self) self.icon:SetVertexColor(0.72, 0.72, 0.72, 1) end)
        btn:SetScript("OnMouseUp", function(self)
            local v = self:IsMouseOver() and 1 or idle
            self.icon:SetVertexColor(v, v, v, 1)
        end)
    end
    if opts.onClick then
        local guard, click = opts.combatGuard, opts.onClick
        btn:SetScript("OnClick", function(self, ...)
            if guard and InCombatLockdown() then return end
            click(self, ...)
        end)
    end

    return btn
end

function UIKit.CreateTabButton(parent, opts)
    opts = opts or {}
    local btn = CreateFrame("Button", nil, parent)
    btn:SetHeight(opts.height or 20)

    btn._label = btn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    btn._label:SetPoint("CENTER")
    if opts.fontPath then CJKFont(btn._label, opts.fontPath, opts.fontSize or 12, opts.fontFlags or "") end
    btn._label:SetText(opts.label or "")
    btn:SetWidth(max(opts.minWidth or 80, (btn._label:GetStringWidth() or 0) + 24))

    UIKit.ApplyPixelBackdrop(btn, 1, true, false)

    local function chrome(field, fallback)
        local C = (QUI and QUI.GUI and QUI.GUI.Colors) or nil
        local c = (C and C[field]) or fallback
        return c[1], c[2], c[3]
    end

    function btn:SetActive(active)
        self._active = active and true or false
        local ar, ag, ab = UIKit.GetAccentColor()
        if self._active then
            self:SetBackdropColor(ar * 0.15, ag * 0.15, ab * 0.15, 1)
            self:SetBackdropBorderColor(ar, ag, ab, 0.8)
            self._label:SetTextColor(ar, ag, ab, 1)
        else
            local br, bgc, bb = chrome("bg", { 0.1, 0.1, 0.1, 1 })
            local dr, dg, db = chrome("border", { 1, 1, 1, 0.1 })
            self:SetBackdropColor(br, bgc, bb, 1)
            self:SetBackdropBorderColor(dr, dg, db, 1)
            self._label:SetTextColor(0.6, 0.6, 0.6, 1)
        end
    end

    btn:SetScript("OnEnter", function(self)
        if not self._active then
            local ar, ag, ab = UIKit.GetAccentColor()
            self:SetBackdropBorderColor(ar * 0.7, ag * 0.7, ab * 0.7, 1)
        end
    end)
    btn:SetScript("OnLeave", function(self)
        if not self._active then
            local dr, dg, db = chrome("border", { 1, 1, 1, 0.1 })
            self:SetBackdropBorderColor(dr, dg, db, 1)
        end
    end)
    if opts.onClick then btn:SetScript("OnClick", opts.onClick) end

    btn:SetActive(opts.isActive)
    return btn
end

function UIKit.CreateObjectPool(factory, resetter)
    local free = {}

    return {
        Acquire = function()
            local obj = table.remove(free)
            if not obj then
                obj = factory()
            end
            if obj and obj.Show then
                obj:Show()
            end
            return obj
        end,
        Release = function(_, obj)
            if not obj then return end
            if resetter then
                resetter(obj)
            end
            if obj.Hide then
                obj:Hide()
            end
            table.insert(free, obj)
        end,
        Available = function()
            return #free
        end,
    }
end

function UIKit.CreateAnchorProxy(sourceFrame, opts)
    opts = opts or {}
    local optCombatFreeze     = opts.combatFreeze ~= false
    local optMirrorVisibility = opts.mirrorVisibility ~= false
    local sizeResolver        = opts.sizeResolver
    local anchorResolver      = opts.anchorResolver
    local frameName           = opts.frameName
    if (opts.deferCreation) and InCombatLockdown() then return nil end

    local proxy = CreateFrame("Frame", frameName, UIParent)
    proxy:SetClampedToScreen(false)
    proxy:Show()

    local initialized = false
    local combatPending = false
    local currentSource = sourceFrame
    local lastWidth, lastHeight = 0, 0
    local lastAnchorSource = nil
    local cachedSourceScale, cachedProxyScale

    function proxy:Sync()
        local source = currentSource
        if not source then return false end
        if optMirrorVisibility then
            local visible = source.IsShown and source:IsShown()
            if visible then
                if not self:IsShown() then self:Show() end
            else
                if self:IsShown() then self:Hide() end
                return true
            end
        end
        local inCombat = InCombatLockdown()
        if optCombatFreeze and inCombat and initialized then
            combatPending = true
            return false
        end
        local w, h
        if sizeResolver then
            w, h = sizeResolver(source)
        else
            w = Helpers and Helpers.SafeToNumber(source:GetWidth(), 0) or (source:GetWidth() or 0)
            h = Helpers and Helpers.SafeToNumber(source:GetHeight(), 0) or (source:GetHeight() or 0)
        end
        w = math.max(1, w or 0)
        h = math.max(1, h or 0)
        local rawSrcScale = source:GetEffectiveScale()
        local rawPxyScale = self:GetEffectiveScale()
        local sourceScale, proxyScale
        local srcSecret = issecretvalue and issecretvalue(rawSrcScale)
        if not srcSecret and rawSrcScale then
            sourceScale = rawSrcScale
            cachedSourceScale = rawSrcScale
        else
            sourceScale = cachedSourceScale
        end
        local pxySecret = issecretvalue and issecretvalue(rawPxyScale)
        if not pxySecret and rawPxyScale then
            proxyScale = rawPxyScale
            cachedProxyScale = rawPxyScale
        else
            proxyScale = cachedProxyScale
        end
        if sourceScale and proxyScale and proxyScale > 0 and sourceScale ~= proxyScale then
            local scaleFactor = sourceScale / proxyScale
            w = w * scaleFactor
            h = h * scaleFactor
        end
        if math.abs(lastWidth - w) > 0.5 or math.abs(lastHeight - h) > 0.5 then
            local ok = ns.SafeCallMethod("defer-ooc", self, "SetSize", w, h)
            if ok then
                lastWidth, lastHeight = w, h
            else
                combatPending = true
            end
        end
        if anchorResolver then
            anchorResolver(self, source)
            lastAnchorSource = source
        elseif lastAnchorSource ~= source then
            if ns.SafeCallMethod("defer-ooc", self, "ClearAllPoints") then
                ns.SafeCallMethod("defer-ooc", self, "SetPoint", "CENTER", source, "CENTER", 0, 0)
            end
            lastAnchorSource = source
        end
        initialized = true
        if inCombat then combatPending = true end
        return true
    end

    function proxy:IsFrozen()
        return optCombatFreeze and initialized and InCombatLockdown()
    end
    function proxy:NeedsCombatRefresh() return combatPending end
    function proxy:ClearCombatPending() combatPending = false end
    function proxy:SetSourceFrame(frame)
        if currentSource == frame then return end
        currentSource = frame
        initialized = false
        lastAnchorSource = nil
        combatPending = false
    end
    function proxy:GetSourceFrame() return currentSource end

    return proxy
end

local SkinBase = UIKit
SkinBase.CHROME = Helpers.CHROME

local frameBackdrops = Helpers.CreateStateTable()
local manualBackdropData = Helpers.CreateStateTable()
local expandedPointData = Helpers.CreateStateTable()
local insetPointData = Helpers.CreateStateTable()
local customInsetPointData = Helpers.CreateStateTable()
local pixelPointData = Helpers.CreateStateTable()
local pixelBackdropData = Helpers.CreateStateTable()
local DEFAULT_BACKDROP_TEXTURE = "Interface\\Buttons\\WHITE8x8"

local BG_BOOST_BUTTON = SkinBase.CHROME.BUTTON_BOOST
local BG_BOOST_ROW = SkinBase.CHROME.SCROLLROW_BOOST
local HOVER_BRIGHTEN = 1.3

SkinBase.HOVER_BRIGHTEN = HOVER_BRIGHTEN
function SkinBase.HoverBrightenColor(r, g, b, a, factor)
    factor = factor or HOVER_BRIGHTEN
    return math.min((r or 0) * factor, 1), math.min((g or 0) * factor, 1), math.min((b or 0) * factor, 1), a
end

function SkinBase.GetPixelSize(frame, default)
    local core = Helpers.GetCore()
    if core and type(core.GetPixelSize) == "function" then
        local px = core:GetPixelSize(frame)
        if type(px) == "number" and px > 0 then
            return px
        end
    end
    return default or 1
end

local function RefreshExpandedPixelPoints(region)
    local data = expandedPointData[region]
    if not data or not data.relativeTo then return end
    local offset = (data.pixels or 1) * SkinBase.GetPixelSize(region, 1)
    region:ClearAllPoints()
    region:SetPoint("TOPLEFT", data.relativeTo, "TOPLEFT", -offset, offset)
    region:SetPoint("BOTTOMRIGHT", data.relativeTo, "BOTTOMRIGHT", offset, -offset)
end

function SkinBase.SetExpandedPixelPoints(region, relativeTo, pixels)
    if not region or not relativeTo then return end
    local data = expandedPointData[region]
    if not data then
        data = {}
        expandedPointData[region] = data
    end
    data.relativeTo = relativeTo
    data.pixels = pixels or 1
    RefreshExpandedPixelPoints(region)
    if UIKit and UIKit.RegisterScaleRefresh and not data.registered then
        UIKit.RegisterScaleRefresh(region, "skinningExpandedPixelPoints", RefreshExpandedPixelPoints)
        data.registered = true
    end
end

local function RefreshInsetPixelPoints(region)
    local data = insetPointData[region]
    if not data or not data.relativeTo then return end
    local inset = (data.pixels or 1) * SkinBase.GetPixelSize(region, 1)
    region:ClearAllPoints()
    region:SetPoint("TOPLEFT", data.relativeTo, "TOPLEFT", inset, -inset)
    region:SetPoint("BOTTOMRIGHT", data.relativeTo, "BOTTOMRIGHT", -inset, inset)
end

function SkinBase.SetInsetPixelPoints(region, relativeTo, pixels)
    if not region or not relativeTo then return end
    local data = insetPointData[region]
    if not data then
        data = {}
        insetPointData[region] = data
    end
    data.relativeTo = relativeTo
    data.pixels = pixels or 1
    RefreshInsetPixelPoints(region)
    if UIKit and UIKit.RegisterScaleRefresh and not data.registered then
        UIKit.RegisterScaleRefresh(region, "skinningInsetPixelPoints", RefreshInsetPixelPoints)
        data.registered = true
    end
end

local function RefreshCustomInsetPixelPoints(region)
    local data = customInsetPointData[region]
    if not data or not data.relativeTo then return end
    local px = SkinBase.GetPixelSize(region, 1)
    region:ClearAllPoints()
    region:SetPoint("TOPLEFT", data.relativeTo, "TOPLEFT", (data.left or 0) * px, -(data.top or 0) * px)
    region:SetPoint("BOTTOMRIGHT", data.relativeTo, "BOTTOMRIGHT", -(data.right or 0) * px, (data.bottom or 0) * px)
end

function SkinBase.SetPixelInsetPoints(region, relativeTo, left, top, right, bottom)
    if not region or not relativeTo then return end
    local data = customInsetPointData[region]
    if not data then
        data = {}
        customInsetPointData[region] = data
    end
    data.relativeTo = relativeTo
    data.left = left or 0
    data.top = top or 0
    data.right = right or 0
    data.bottom = bottom or 0
    RefreshCustomInsetPixelPoints(region)
    if UIKit and UIKit.RegisterScaleRefresh and not data.registered then
        UIKit.RegisterScaleRefresh(region, "skinningPixelInsetPoints", RefreshCustomInsetPixelPoints)
        data.registered = true
    end
end

local function RefreshPixelPoint(region)
    local data = pixelPointData[region]
    if not data then return end
    local px = SkinBase.GetPixelSize(region, 1)
    region:ClearAllPoints()
    region:SetPoint(
        data.point,
        data.relativeTo,
        data.relativePoint,
        (data.xPixels or 0) * px,
        (data.yPixels or 0) * px
    )
end

function SkinBase.SetPixelPoint(region, point, relativeTo, relativePoint, xPixels, yPixels)
    if not region or not point then return end
    local data = pixelPointData[region]
    if not data then
        data = {}
        pixelPointData[region] = data
    end
    data.point = point
    data.relativeTo = relativeTo
    data.relativePoint = relativePoint
    data.xPixels = xPixels or 0
    data.yPixels = yPixels or 0
    RefreshPixelPoint(region)
    if UIKit and UIKit.RegisterScaleRefresh and not data.registered then
        UIKit.RegisterScaleRefresh(region, "skinningPixelPoint", RefreshPixelPoint)
        data.registered = true
    end
end

function SkinBase.GetSkinColors(moduleSettings, prefix)
    local sr, sg, sb, sa = Helpers.GetSkinBorderColor(moduleSettings, prefix)
    local bgr, bgg, bgb, bga = Helpers.GetSkinBgColorWithOverride(moduleSettings, prefix)
    return sr, sg, sb, sa, bgr, bgg, bgb, bga
end

function SkinBase.GetSkinBarColor(moduleSettings, prefix)
    return Helpers.GetSkinBarColor(moduleSettings, prefix)
end

function SkinBase.GetDepthColor(tier, moduleSettings, prefix)
    local depth = SkinBase.CHROME.DEPTH[tier] or SkinBase.CHROME.DEPTH.PANEL
    local _, _, _, _, bgr, bgg, bgb = SkinBase.GetSkinColors(moduleSettings, prefix)
    bgr = bgr or SkinBase.CHROME.BG_FALLBACK[1]
    bgg = bgg or SkinBase.CHROME.BG_FALLBACK[2]
    bgb = bgb or SkinBase.CHROME.BG_FALLBACK[3]
    local boost = depth.boost
    return math.min(bgr + boost, 1), math.min(bgg + boost, 1), math.min(bgb + boost, 1), depth.alpha
end

local function ResolveChromeColor(color, fallback, defaultAlpha)
    fallback = fallback or SkinBase.CHROME.BORDER_FALLBACK
    if type(color) == "function" then
        local r, g, b, a = color()
        if type(r) == "table" then
            color = r
        elseif r ~= nil then
            return { r, g, b, a == nil and (fallback[4] or defaultAlpha or 1) or a }
        end
    end
    if type(color) == "table" then
        return {
            color[1] == nil and fallback[1] or color[1],
            color[2] == nil and fallback[2] or color[2],
            color[3] == nil and fallback[3] or color[3],
            color[4] == nil and (fallback[4] or defaultAlpha or 1) or color[4],
        }
    end
    return {
        fallback[1] or 0,
        fallback[2] or 0,
        fallback[3] or 0,
        fallback[4] == nil and (defaultAlpha or 1) or fallback[4],
    }
end

function SkinBase.GetChromePalette(opts)
    opts = opts or {}
    local sr, sg, sb, sa, bgr, bgg, bgb, bga = SkinBase.GetSkinColors(opts.moduleSettings, opts.prefix)
    local borderFallback = opts.borderFallback or SkinBase.CHROME.BORDER_FALLBACK
    local bgFallback = opts.bgFallback or SkinBase.CHROME.BG_FALLBACK
    local border = ResolveChromeColor(opts.borderColor or { sr, sg, sb, sa }, borderFallback, 1)
    local bg = ResolveChromeColor(opts.bgColor or { bgr, bgg, bgb, bga }, bgFallback, 0.95)
    local accentSource = opts.accentColor or opts.borderColor
    if not accentSource then
        accentSource = sr ~= nil and { sr, sg, sb, sa } or opts.accentFallback
    end
    local accent = ResolveChromeColor(accentSource, opts.accentFallback or border, 1)
    return { border = border, accent = accent, bg = bg }
end

function SkinBase.ApplyChromeBackdrop(frame, opts)
    if not frame then return nil end
    opts = opts or {}
    local palette = opts.palette or SkinBase.GetChromePalette(opts)
    local borderColor = ResolveChromeColor(opts.borderColor, palette.border, 1)
    local bgColor = ResolveChromeColor(opts.bgColor, palette.bg, 0.95)
    local withBackground = opts.withBackground
    if withBackground == nil then
        withBackground = opts.background
    end
    local withInsets = opts.withInsets
    if withInsets == nil then
        withInsets = withBackground
    end
    SkinBase.ApplyPixelBackdrop(
        frame,
        opts.borderPixels or SkinBase.CHROME.BORDER_PX,
        withBackground and true or false,
        withInsets and true or false,
        borderColor,
        withBackground and bgColor or nil,
        opts.bgFile,
        opts.edgeFile,
        opts.insetPixels
    )
    return palette
end

local function HideButtonTextures(button)
    if button.Border then button.Border:SetAlpha(0) end
    if button.GetNormalTexture and button:GetNormalTexture() then button:GetNormalTexture():SetAlpha(0) end
    if button.GetPushedTexture and button:GetPushedTexture() then button:GetPushedTexture():SetAlpha(0) end
    if button.GetHighlightTexture and button:GetHighlightTexture() then button:GetHighlightTexture():SetAlpha(0) end
    if button.GetDisabledTexture and button:GetDisabledTexture() then button:GetDisabledTexture():SetAlpha(0) end
end

function SkinBase.SkinChromeCloseButton(button, opts)
    return SkinBase.SkinCloseButton(button, opts)
end

local function TooltipTextHasPrintfPlaceholder(text)
    if type(text) ~= "string" then return false end
    if Helpers.IsSecretValue and Helpers.IsSecretValue(text) then return false end -- @secret-policy: reject-secret-value (caller drops the line)

    local withoutLiteralPercents = text:gsub("%%%%", "")
    return withoutLiteralPercents:find("%%[-+0#%d%.$]*[AacdeEfgGioqsuxX]") ~= nil
end

local function SanitizeSecretRestrictedTooltipText(text)
    if Helpers.IsSecretValue and Helpers.IsSecretValue(text) then
        return nil -- @secret-policy: reject-secret-value (tooltip line dropped)
    end
    if TooltipTextHasPrintfPlaceholder(text) then
        return nil
    end
    return text
end

function SkinBase.CreateSecretAwareStatPolicy(opts)
    opts = opts or {}
    local policy = {
        unit = opts.unit,
        secretsRestricted = false,
    }
    if opts.unit == "player" and type(opts.secretDetector) == "function" then
        local ok, restricted = pcall(opts.secretDetector)
        policy.secretsRestricted = ok and restricted and true or false
    end

    function policy:CanUseRichTooltip()
        return not self.secretsRestricted
    end

    function policy:ReadableNumber(value)
        if Helpers.IsSecretValue(value) then return nil end -- @secret-policy: reject-secret-value (caller substitutes its fallback)
        return tonumber(value)
    end

    function policy:GetNumber(func, fallback, ...)
        if type(func) ~= "function" then
            return fallback or 0
        end
        local ok, result = pcall(func, ...)
        if not ok then
            return fallback or 0
        end
        local value = self:ReadableNumber(result)
        if value == nil then
            return fallback or 0
        end
        return value
    end

    function policy:GetNumbers(func, ...)
        if type(func) ~= "function" then
            return 0, 0, 0, 0
        end
        local ok, a, b, c, d = pcall(func, ...)
        if not ok then
            return 0, 0, 0, 0
        end
        return self:ReadableNumber(a) or 0,
               self:ReadableNumber(b) or 0,
               self:ReadableNumber(c) or 0,
               self:ReadableNumber(d) or 0
    end

    function policy:GetRaw(func, ...)
        if type(func) ~= "function" then return nil end
        local ok, result = pcall(func, ...)
        if not ok or Helpers.IsSecretValue(result) then return nil end
        return result
    end

    function policy:ApplyTooltip(row, title, body, extraBody, richBuilder)
        if not row then return end
        row.tooltip = title
        if self:CanUseRichTooltip() then
            row.tooltip2 = body
            row.tooltip3 = extraBody
        else
            row.tooltip2 = SanitizeSecretRestrictedTooltipText(body)
            row.tooltip3 = SanitizeSecretRestrictedTooltipText(extraBody)
        end
        if self:CanUseRichTooltip() and type(richBuilder) == "function" then
            ns.SafeCall("bulkhead", richBuilder, row, self)
        end
    end

    return policy
end

local function SetTextureSource(texture, file)
    if not texture then return end
    if file == DEFAULT_BACKDROP_TEXTURE and texture.SetColorTexture then
        return
    end
    texture:SetTexture(file)
end

local function SetTextureColor(texture, file, r, g, b, a)
    if texture then
        local colorA = a == nil and 1 or a
        if file == DEFAULT_BACKDROP_TEXTURE and texture.SetColorTexture then
            texture:SetColorTexture(r or 1, g or 1, b or 1, colorA)
            UIKit.DisablePixelSnap(texture)
        else
            texture:SetVertexColor(r or 1, g or 1, b or 1, colorA)
        end
    end
end

local function ManualSetBackdropColor(self, r, g, b, a)
    self._quiBgR, self._quiBgG, self._quiBgB, self._quiBgA = r, g, b, a
    local data = manualBackdropData[self]
    if data then
        SetTextureColor(data.bg, data.bgFile, r, g, b, a)
    end
end

local function ManualSetBackdropBorderColor(self, r, g, b, a)
    self._quiBorderR, self._quiBorderG, self._quiBorderB, self._quiBorderA = r, g, b, a
    local data = manualBackdropData[self]
    if data then
        SetTextureColor(data.top, data.edgeFile, r, g, b, a)
        SetTextureColor(data.bottom, data.edgeFile, r, g, b, a)
        SetTextureColor(data.left, data.edgeFile, r, g, b, a)
        SetTextureColor(data.right, data.edgeFile, r, g, b, a)
    end
end

local function EnsureManualBackdrop(frame)
    local data = manualBackdropData[frame]
    if data then return data end

    data = { bg = frame:CreateTexture(nil, "BACKGROUND") }
    BuildEdgeTextures(frame, data, { layer = "BORDER" })
    manualBackdropData[frame] = data

    frame.SetBackdropColor = ManualSetBackdropColor
    frame.SetBackdropBorderColor = ManualSetBackdropBorderColor

    return data
end

local function ResetBorderTexture(texture, edgeFile, showBorder)
    texture:ClearAllPoints()
    if showBorder then
        SetTextureSource(texture, edgeFile)
        texture:Show()
    else
        texture:Hide()
    end
end

function SkinBase.ApplyTextureBackdrop(frame, bgFile, edgeFile, edgeSize, borderColor, bgColor, bgInset)
    if not frame then return false end

    local data = EnsureManualBackdrop(frame)
    local px = tonumber(edgeSize) or 1
    if px < 0 then px = 0 end
    local inset = bgInset
    if inset == nil then inset = px end

    if bgFile ~= false then
        bgFile = bgFile or DEFAULT_BACKDROP_TEXTURE
    end
    if edgeFile ~= false then
        edgeFile = edgeFile or DEFAULT_BACKDROP_TEXTURE
    end
    data.bgFile = bgFile
    data.edgeFile = edgeFile

    data.bg:ClearAllPoints()
    if bgFile then
        SetTextureSource(data.bg, bgFile)
        data.bg:SetPoint("TOPLEFT", frame, "TOPLEFT", inset, -inset)
        data.bg:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -inset, inset)
        data.bg:Show()
    else
        data.bg:Hide()
    end

    local showBorder = edgeFile and px > 0
    ResetBorderTexture(data.top, edgeFile, showBorder)
    ResetBorderTexture(data.bottom, edgeFile, showBorder)
    ResetBorderTexture(data.left, edgeFile, showBorder)
    ResetBorderTexture(data.right, edgeFile, showBorder)

    if showBorder then
        data.top:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
        data.top:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
        data.top:SetHeight(px)

        data.bottom:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0)
        data.bottom:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
        data.bottom:SetHeight(px)

        data.left:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, -px)
        data.left:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, px)
        data.left:SetWidth(px)

        data.right:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, -px)
        data.right:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, px)
        data.right:SetWidth(px)
    end

    if bgColor then
        frame:SetBackdropColor(bgColor[1], bgColor[2], bgColor[3], bgColor[4])
    else
        frame:SetBackdropColor(frame._quiBgR or 1, frame._quiBgG or 1, frame._quiBgB or 1, frame._quiBgA)
    end

    if borderColor then
        frame:SetBackdropBorderColor(borderColor[1], borderColor[2], borderColor[3], borderColor[4])
    else
        frame:SetBackdropBorderColor(frame._quiBorderR or 1, frame._quiBorderG or 1, frame._quiBorderB or 1, frame._quiBorderA)
    end

    return true
end

local function RefreshPixelBackdrop(frame)
    local data = pixelBackdropData[frame]
    if not data then return end

    local edgeSize = (data.borderPixels or 1) * SkinBase.GetPixelSize(frame, 1)
    local bgInset = 0
    if data.withInsets then
        local insetPixels = data.insetPixels
        if insetPixels == nil then
            insetPixels = data.borderPixels or 1
        end
        bgInset = insetPixels * SkinBase.GetPixelSize(frame, 1)
    end
    local bgColor = data.bgColor
    if not bgColor and frame._quiBgR ~= nil then
        bgColor = { frame._quiBgR, frame._quiBgG, frame._quiBgB, frame._quiBgA }
    end
    local borderColor = data.borderColor
    if not borderColor and frame._quiBorderR ~= nil then
        borderColor = { frame._quiBorderR, frame._quiBorderG, frame._quiBorderB, frame._quiBorderA }
    end

    local bgFile = data.withBackground and (data.bgFile or DEFAULT_BACKDROP_TEXTURE) or false
    local edgeFile = edgeSize > 0 and (data.edgeFile or DEFAULT_BACKDROP_TEXTURE) or false
    SkinBase.ApplyTextureBackdrop(frame, bgFile, edgeFile, edgeSize, borderColor, bgColor, bgInset)
end

function SkinBase.ApplyPixelBackdrop(frame, borderPixels, withBackground, withInsets, borderColor, bgColor, bgFile, edgeFile, insetPixels)
    if not frame then return end
    local data = pixelBackdropData[frame]
    if not data then
        data = {}
        pixelBackdropData[frame] = data
    end

    data.borderPixels = borderPixels or SkinBase.CHROME.BORDER_PX
    data.withBackground = withBackground and true or false
    data.withInsets = withInsets and true or false
    data.borderColor = borderColor
    data.bgColor = bgColor
    data.bgFile = bgFile
    data.edgeFile = edgeFile
    data.insetPixels = insetPixels

    RefreshPixelBackdrop(frame)
    if UIKit and UIKit.RegisterScaleRefresh and not data.registered then
        UIKit.RegisterScaleRefresh(frame, "skinningPixelBackdrop", RefreshPixelBackdrop)
        data.registered = true
    end
end

function SkinBase.SetBackdropColors(frame, borderColor, bgColor)
    if not frame then return end
    local data = pixelBackdropData[frame]
    if not data then
        if bgColor and frame.SetBackdropColor then
            frame:SetBackdropColor(bgColor[1], bgColor[2], bgColor[3], bgColor[4])
        end
        if borderColor and frame.SetBackdropBorderColor then
            frame:SetBackdropBorderColor(borderColor[1], borderColor[2], borderColor[3], borderColor[4])
        end
        return
    end
    if borderColor ~= nil then data.borderColor = borderColor end
    if bgColor ~= nil then data.bgColor = bgColor end
    RefreshPixelBackdrop(frame)
end

function SkinBase.CreateBackdrop(frame, sr, sg, sb, sa, bgr, bgg, bgb, bga)
    if not frameBackdrops[frame] then
        local backdrop = CreateFrame("Frame", nil, frame)
        backdrop:SetAllPoints()
        backdrop:SetFrameLevel(frame:GetFrameLevel())
        backdrop:EnableMouse(false)
        frameBackdrops[frame] = backdrop
    end

    local backdrop = frameBackdrops[frame]
    backdrop._quiBgR = bgr or SkinBase.CHROME.BG_FALLBACK[1]
    backdrop._quiBgG = bgg or SkinBase.CHROME.BG_FALLBACK[2]
    backdrop._quiBgB = bgb or SkinBase.CHROME.BG_FALLBACK[3]
    backdrop._quiBgA = bga or SkinBase.CHROME.BG_FALLBACK[4]
    backdrop._quiBorderR = sr or SkinBase.CHROME.BORDER_FALLBACK[1]
    backdrop._quiBorderG = sg or SkinBase.CHROME.BORDER_FALLBACK[2]
    backdrop._quiBorderB = sb or SkinBase.CHROME.BORDER_FALLBACK[3]
    backdrop._quiBorderA = sa or SkinBase.CHROME.BORDER_FALLBACK[4]
    SkinBase.ApplyPixelBackdrop(backdrop, 1, true, true, {
        backdrop._quiBorderR, backdrop._quiBorderG, backdrop._quiBorderB, backdrop._quiBorderA,
    }, {
        backdrop._quiBgR, backdrop._quiBgG, backdrop._quiBgB, backdrop._quiBgA,
    })
end

function SkinBase.ApplyFullBackdrop(frame, sr, sg, sb, sa, bgr, bgg, bgb, bga)
    if not frame then return end
    frame._quiBgR = bgr or SkinBase.CHROME.BG_FALLBACK[1]
    frame._quiBgG = bgg or SkinBase.CHROME.BG_FALLBACK[2]
    frame._quiBgB = bgb or SkinBase.CHROME.BG_FALLBACK[3]
    frame._quiBgA = bga or SkinBase.CHROME.BG_FALLBACK[4]
    frame._quiBorderR = sr or SkinBase.CHROME.BORDER_FALLBACK[1]
    frame._quiBorderG = sg or SkinBase.CHROME.BORDER_FALLBACK[2]
    frame._quiBorderB = sb or SkinBase.CHROME.BORDER_FALLBACK[3]
    frame._quiBorderA = sa or SkinBase.CHROME.BORDER_FALLBACK[4]
    SkinBase.ApplyPixelBackdrop(frame, 1, true, true, {
        frame._quiBorderR, frame._quiBorderG, frame._quiBorderB, frame._quiBorderA,
    }, {
        frame._quiBgR, frame._quiBgG, frame._quiBgB, frame._quiBgA,
    })
end

function SkinBase.GetBackdrop(frame)
    return frameBackdrops[frame]
end

function SkinBase.RefreshFrameBackdropColors(frame)
    if not frame then return end
    local bd = SkinBase.GetBackdrop(frame)
    if not bd then return end
    local sr, sg, sb, sa, bgr, bgg, bgb, bga = SkinBase.GetSkinColors()
    SkinBase.SetBackdropColors(bd, { sr, sg, sb, sa }, { bgr, bgg, bgb, bga })
end

local skinnedFrames = Helpers.CreateStateTable()
local styledFrames = Helpers.CreateStateTable()

function SkinBase.MarkSkinned(frame)
    skinnedFrames[frame] = true
end

function SkinBase.IsSkinned(frame)
    return skinnedFrames[frame]
end

function SkinBase.MarkStyled(frame)
    styledFrames[frame] = true
end

function SkinBase.IsStyled(frame)
    return styledFrames[frame]
end

local frameData, getFrameData = Helpers.CreateStateTable()

function SkinBase.SetFrameData(frame, key, value)
    getFrameData(frame)[key] = value
end

function SkinBase.GetFrameData(frame, key)
    local data = frameData[frame]
    return data and data[key]
end

function SkinBase.StripTextures(frame)
    if not frame then return end
    local regions = { frame:GetRegions() }
    for i = 1, #regions do
        local region = regions[i]
        if region and region:IsObjectType("Texture") then
            region:SetAlpha(0)
        end
    end
end

function SkinBase.StripTexturesExcept(frame, preserve)
    if not frame or not frame.GetNumRegions then return end
    local regions = { frame:GetRegions() }
    for i = 1, #regions do
        local region = regions[i]
        if region and region.IsObjectType and region:IsObjectType("Texture") then
            if not (preserve and preserve[region]) then
                region:SetAlpha(0)
            end
        end
    end
end

function SkinBase.HidePortraitFrameChrome(frame)
    if not frame then return end

    if frame.NineSlice then frame.NineSlice:Hide() end
    if frame.Bg then frame.Bg:Hide() end
    if frame.TopTileStreaks then frame.TopTileStreaks:Hide() end
    if frame.PortraitContainer then frame.PortraitContainer:Hide() end
    if frame.TitleContainer and frame.TitleContainer.TitleBg then
        frame.TitleContainer.TitleBg:Hide()
    end

    if frame.TopLeftCorner then frame.TopLeftCorner:Hide() end
    if frame.TopRightCorner then frame.TopRightCorner:Hide() end
    if frame.BotLeftCorner then frame.BotLeftCorner:Hide() end
    if frame.BotRightCorner then frame.BotRightCorner:Hide() end
    if frame.TopBorder then frame.TopBorder:Hide() end
    if frame.BottomBorder then frame.BottomBorder:Hide() end
    if frame.LeftBorder then frame.LeftBorder:Hide() end
    if frame.RightBorder then frame.RightBorder:Hide() end
    if frame.TitleBg then frame.TitleBg:Hide() end

    if frame.Background then frame.Background:Hide() end
    if frame.portrait then frame.portrait:Hide() end

    if frame.Inset then
        if frame.Inset.NineSlice then frame.Inset.NineSlice:Hide() end
        if frame.Inset.Bg then frame.Inset.Bg:Hide() end
    end
end

function SkinBase.SkinCloseButton(closeButton, opts)
    if not closeButton then return end
    opts = opts or {}

    HideButtonTextures(closeButton)
    SkinBase.SetFrameData(closeButton, "closeOptions", opts)

    local label = SkinBase.GetFrameData(closeButton, "closeLabel")
    if not label then
        label = closeButton:CreateFontString(nil, "OVERLAY")
        label:SetPoint("CENTER")
        SkinBase.SetFrameData(closeButton, "closeLabel", label)
        closeButton.text = label
    end
    CJKFont(label, opts.font or Helpers.GetGeneralFont() or STANDARD_TEXT_FONT, opts.fontSize or 12,
        opts.fontFlags or Helpers.GetGeneralFontOutline() or "OUTLINE")
    label:SetText(opts.label or "X")
    local textColor = ResolveChromeColor(opts.textColor, { 1, 1, 1, 0.8 }, 0.8)
    label:SetTextColor(textColor[1], textColor[2], textColor[3], textColor[4])

    if SkinBase.GetFrameData(closeButton, "closeStyled") then return end

    closeButton:HookScript("OnEnter", function(self)
        local current = SkinBase.GetFrameData(self, "closeOptions") or {}
        local ar, ag, ab = UIKit.GetAccentColor()
        local accent = ResolveChromeColor(current.accentColor, { ar, ag, ab, 1 }, 1)
        local closeLabel = SkinBase.GetFrameData(self, "closeLabel")
        if closeLabel then closeLabel:SetTextColor(accent[1], accent[2], accent[3], accent[4]) end
    end)
    closeButton:HookScript("OnLeave", function(self)
        local current = SkinBase.GetFrameData(self, "closeOptions") or {}
        local color = ResolveChromeColor(current.textColor, { 1, 1, 1, 0.8 }, 0.8)
        local closeLabel = SkinBase.GetFrameData(self, "closeLabel")
        if closeLabel then closeLabel:SetTextColor(color[1], color[2], color[3], color[4]) end
    end)

    SkinBase.SetFrameData(closeButton, "closeStyled", true)
end

local function NukeTexture(t)
    if not t then return end
    if t.SetAlpha then t:SetAlpha(0) end
    ns.SafeCallMethodIfPresent("best-effort-style", t, "SetTexture", "")
    if t.Hide then t:Hide() end
end

function SkinBase.ClampTextureHidden(tex)
    if not tex then return end
    NukeTexture(tex)
    if tex.SetAlpha and not SkinBase.GetFrameData(tex, "qTexClamped") then
        hooksecurefunc(tex, "SetAlpha", function(self, a)
            if a and a > 0 then self:SetAlpha(0) end
        end)
        SkinBase.SetFrameData(tex, "qTexClamped", true)
    end
end

function SkinBase.ClampAllTextures(frame)
    if not frame or not frame.GetNumRegions then return end
    local regions = { frame:GetRegions() }
    for i = 1, #regions do
        local region = regions[i]
        if region and region.IsObjectType and region:IsObjectType("Texture") then
            SkinBase.ClampTextureHidden(region)
        end
    end
end

local NINE_SLICE_PARTS = {
    "TopLeftCorner", "TopRightCorner", "BottomLeftCorner", "BottomRightCorner",
    "TopEdge", "BottomEdge", "LeftEdge", "RightEdge", "Center",
}
function SkinBase.KillNineSlice(nineSlice, durable)
    if not nineSlice then return end

    if nineSlice.GetNumRegions then
        local regions = { nineSlice:GetRegions() }
        for i = 1, #regions do
            local region = regions[i]
            if region and region.IsObjectType and region:IsObjectType("Texture") then
                if region.SetTexture then region:SetTexture(nil) end
                if region.SetShown then region:SetShown(false) end
            end
        end
    end

    for _, part in ipairs(NINE_SLICE_PARTS) do
        local tex = nineSlice[part]
        if tex then
            if tex.SetTexture then tex:SetTexture(nil) end
            if tex.SetShown then tex:SetShown(false) end
        end
    end

    nineSlice:Hide()
    if nineSlice.SetAlpha then nineSlice:SetAlpha(0) end

    if durable and nineSlice.HookScript and not SkinBase.GetFrameData(nineSlice, "qNineSliceKilled") then
        nineSlice:HookScript("OnShow", function(self) self:Hide() end)
        SkinBase.SetFrameData(nineSlice, "qNineSliceKilled", true)
    end
end

local PANEL_TAB_TEXTURES = {
    "Left", "Middle", "Right",
    "LeftActive", "MiddleActive", "RightActive",
    "LeftHighlight", "MiddleHighlight", "RightHighlight",
    "LeftDisabled", "MiddleDisabled", "RightDisabled",
}

local NORMAL_TEXT_COLOR = { 1, 1, 1, 1 }
local DISABLED_TEXT_COLOR = { 0.5, 0.5, 0.5, 1 }
local buttonFontObjects = {}
local buttonFontObjCount = 0
local function ColorKey(c)
    if type(c) ~= "table" then return "def" end
    return string.format("%.2f,%.2f,%.2f,%.2f", c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1)
end
local function GetButtonFontObject(size, color)
    if not _G.CreateFont then return nil end
    size = (type(size) == "number" and size > 0) and size or 12
    local sizeKey = floor(size + 0.5)
    local key = sizeKey .. "|" .. ColorKey(color)
    local obj = buttonFontObjects[key]
    if not obj then
        buttonFontObjCount = buttonFontObjCount + 1
        obj = _G.CreateFont("QUIButtonFontObject" .. buttonFontObjCount)
        buttonFontObjects[key] = obj
    end
    local font = (Helpers.GetGeneralFont and Helpers.GetGeneralFont()) or DEFAULT_FONT
    local outline = (Helpers.GetGeneralFontOutline and Helpers.GetGeneralFontOutline()) or ""
    local family = Helpers.GetFontFamilyObject and Helpers.GetFontFamilyObject(font, sizeKey, outline)
    if family then
        obj:SetFontObject(family)
    else
        obj:SetFont(font, sizeKey, outline)
    end
    if type(color) == "table" then
        obj:SetTextColor(color[1] or 1, color[2] or 1, color[3] or 1, color[4] or 1)
    else
        obj:SetTextColor(1, 1, 1, 1)
    end
    return obj
end

function SkinBase.ApplyButtonFontObjects(button, opts)
    if not button then return end
    local core = GetCore()
    if not (core and core.db and core.db.profile and core.db.profile.general
            and core.db.profile.general.applyGlobalFontToBlizzard) then
        return
    end
    opts = opts or {}
    local fs = button.Text or (button.GetFontString and button:GetFontString())
    local size = opts.size
    if not size and fs and fs.GetFont then
        local _, s = fs:GetFont()
        if type(s) == "number" and s > 0 then size = s end
    end
    local normalObj = GetButtonFontObject(size, opts.color)
    if normalObj then
        if button.SetNormalFontObject then button:SetNormalFontObject(normalObj) end
        if button.SetHighlightFontObject then button:SetHighlightFontObject(normalObj) end
        if button.SetDisabledFontObject then
            local disObj = GetButtonFontObject(size, opts.disabledColor or opts.color)
            button:SetDisabledFontObject(disObj or normalObj)
        end
    end
    if fs then
        SkinBase.SkinFontString(fs, type(opts.color) == "table" and { color = opts.color } or { fontOnly = true })
    end
end

SkinBase.ApplyTabFontObjects = SkinBase.ApplyButtonFontObjects

local function ReapplyTabFont(tab)
    if not SkinBase.GetFrameData(tab, "skinTabFont") then return end
    SkinBase.ApplyTabFontObjects(tab)
    if SkinBase.GetFrameData(tab, "skinTabResizeToText") and tab.OnShow then
        tab:OnShow()
    elseif tab.UpdateTabWidth then
        tab:UpdateTabWidth()
    end
end

local function ReassertTabSkin(tab)
    if not tab or not SkinBase.GetFrameData(tab, "qTabArtClamped") then return end
    SkinBase.ClampAllTextures(tab)
    local hl = tab.GetHighlightTexture and tab:GetHighlightTexture()
    if hl then SkinBase.ClampTextureHidden(hl) end
    SkinBase.RefreshTabSelected(tab, SkinBase.GetFrameData(tab, "skinTabOwner"))
end

local panelTabHooked = false
local function HookPanelTabSkin()
    if panelTabHooked then return end
    panelTabHooked = true
    if PanelTemplates_SelectTab then
        hooksecurefunc("PanelTemplates_SelectTab", function(tab) ReassertTabSkin(tab) end)
    end
    if PanelTemplates_DeselectTab then
        hooksecurefunc("PanelTemplates_DeselectTab", function(tab) ReassertTabSkin(tab) end)
    end
    if _G.PanelTemplates_SetDisabledTabState then
        hooksecurefunc("PanelTemplates_SetDisabledTabState", function(tab) ReassertTabSkin(tab) end)
    end
end

function SkinBase.RegisterTabArtClamp(tab)
    if not tab then return end
    SkinBase.SetFrameData(tab, "qTabArtClamped", true)
    SkinBase.SetFrameData(tab, "skinTabFont", true)
    HookPanelTabSkin()
end

function SkinBase.SkinTabButton(tab, opts)
    if not tab or SkinBase.IsStyled(tab) then return end
    opts = opts or {}

    SkinBase.ClampAllTextures(tab)
    local highlight = tab.GetHighlightTexture and tab:GetHighlightTexture()
    SkinBase.ClampTextureHidden(highlight)
    SkinBase.SetFrameData(tab, "qTabArtClamped", true)

    HookPanelTabSkin()

    local sr, sg, sb, sa, bgr, bgg, bgb = SkinBase.GetSkinColors()
    SkinBase.CreateBackdrop(tab, sr, sg, sb, sa, bgr, bgg, bgb, 0.9)
    local bd = SkinBase.GetBackdrop(tab)
    if bd then
        SkinBase.SetPixelInsetPoints(bd, tab, 3, 3, 3, 0)
    end

    if opts.font ~= false then
        SkinBase.SetFrameData(tab, "skinTabFont", true)
        if opts.resizeToText then SkinBase.SetFrameData(tab, "skinTabResizeToText", true) end
        ReapplyTabFont(tab)
    end

    SkinBase.SetFrameData(tab, "skinColor", { sr, sg, sb, sa })
    SkinBase.SetFrameData(tab, "bgColor",   { bgr, bgg, bgb })
    SkinBase.MarkStyled(tab)
end

local function IsTabSelected(tab, owner)
    if tab.isDisabled then return false end
    if tab.IsSelected and tab:IsSelected() then return true end
    if tab.isSelected then return true end
    if owner then
        local tabSystem = owner.TabSystem
        if tabSystem and tabSystem.GetSelectedTab and tab.tabID then
            if tab.tabID == tabSystem:GetSelectedTab() then return true end
        end
        local selected = (PanelTemplates_GetSelectedTab and PanelTemplates_GetSelectedTab(owner)) or owner.selectedTab
        if selected then
            if owner.Tabs and owner.Tabs[selected] == tab then return true end
            if tab.GetID and tab:GetID() == selected then return true end
        end
    end
    if tab.SelectedTexture and tab.SelectedTexture.IsShown and tab.SelectedTexture:IsShown() then
        return true
    end
    return false
end

function SkinBase.RefreshTabSelected(tab, owner)
    ReapplyTabFont(tab)

    local bd = SkinBase.GetBackdrop(tab)
    local sc = SkinBase.GetFrameData(tab, "skinColor")
    local bg = SkinBase.GetFrameData(tab, "bgColor")
    if not bd or not sc or not bg then return end

    local selected = IsTabSelected(tab, owner)
    local borderColor, bgColor
    if selected then
        borderColor = { sc[1], sc[2], sc[3], sc[4] }
        bgColor = { math.min(bg[1] + 0.10, 1), math.min(bg[2] + 0.10, 1), math.min(bg[3] + 0.10, 1), 1 }
    else
        borderColor = { sc[1] * 0.5, sc[2] * 0.5, sc[3] * 0.5, sc[4] * 0.6 }
        bgColor = { bg[1], bg[2], bg[3], 0.7 }
    end
    SkinBase.ApplyPixelBackdrop(bd, 1, true, true, borderColor, bgColor)

    if SkinBase.GetFrameData(tab, "skinTabFont") then
        local tabText = tab.Text or (tab.GetFontString and tab:GetFontString())
        if tabText and tabText.SetTextColor then
            if selected then
                tabText:SetTextColor(0.9, 0.9, 0.9, 1)
            else
                tabText:SetTextColor(0.55, 0.55, 0.55, 1)
            end
        end
    end
end

local function TabHoverEnter(self)
    local bd = SkinBase.GetBackdrop(self)
    local sc = SkinBase.GetFrameData(self, "skinColor")
    if bd and sc then
        bd:SetBackdropBorderColor(
            math.min(sc[1] * HOVER_BRIGHTEN, 1),
            math.min(sc[2] * HOVER_BRIGHTEN, 1),
            math.min(sc[3] * HOVER_BRIGHTEN, 1),
            sc[4])
    end
end

local ownerTabRefreshers = Helpers.CreateStateTable()
local panelSetTabHooked = false
local function RegisterOwnerTabRefresh(owner, refreshAll)
    ownerTabRefreshers[owner] = refreshAll
    if not panelSetTabHooked and PanelTemplates_SetTab then
        hooksecurefunc("PanelTemplates_SetTab", function(frame)
            local fn = ownerTabRefreshers[frame]
            if fn then C_Timer.After(0, fn) end
        end)
        panelSetTabHooked = true
    end
    local tabSystem = owner.TabSystem
    if tabSystem and tabSystem.SetTab and not SkinBase.GetFrameData(tabSystem, "qTabSysHooked") then
        hooksecurefunc(tabSystem, "SetTab", function()
            C_Timer.After(0, function()
                local fn = ownerTabRefreshers[owner]
                if fn then fn() end
            end)
        end)
        SkinBase.SetFrameData(tabSystem, "qTabSysHooked", true)
    end
end

function SkinBase.SkinTab(tab, owner, opts)
    if not tab then return end
    opts = opts or {}
    SkinBase.SetFrameData(tab, "skinTabOwner", owner)
    SkinBase.SkinTabButton(tab, opts)
    if tab.SetTabSelected and not SkinBase.GetFrameData(tab, "qTabStateHooked") then
        hooksecurefunc(tab, "SetTabSelected", ReassertTabSkin)
        SkinBase.SetFrameData(tab, "qTabStateHooked", true)
    end
    if opts.hover and not SkinBase.GetFrameData(tab, "qTabHoverHooked") then
        tab:HookScript("OnEnter", TabHoverEnter)
        tab:HookScript("OnLeave", function(self) SkinBase.RefreshTabSelected(self, owner) end)
        SkinBase.SetFrameData(tab, "qTabHoverHooked", true)
    end
    SkinBase.RefreshTabSelected(tab, owner)
end

function SkinBase.CollectNumberedTabs(prefix, count)
    local tabs = {}
    for i = 1, count do
        local tab = _G[prefix .. "Tab" .. i]
        if tab then tabs[#tabs + 1] = tab end
    end
    return tabs
end

function SkinBase.SkinTabGroup(tabs, owner, opts)
    if not tabs or #tabs == 0 then return end
    opts = opts or {}

    for _, tab in ipairs(tabs) do
        SkinBase.SkinTab(tab, owner, opts)
    end

    local function refreshAll()
        for _, t in ipairs(tabs) do
            SkinBase.RefreshTabSelected(t, owner)
        end
    end

    for _, tab in ipairs(tabs) do
        if not SkinBase.GetFrameData(tab, "qTabSelHooked") then
            tab:HookScript("OnClick", refreshAll)
            SkinBase.SetFrameData(tab, "qTabSelHooked", true)
        end
    end

    if owner then
        RegisterOwnerTabRefresh(owner, refreshAll)
    end

    refreshAll()
end

function SkinBase.RefreshTabGroup(tabs, owner)
    if not tabs then return end
    local sr, sg, sb, sa, bgr, bgg, bgb = SkinBase.GetSkinColors()
    for _, tab in ipairs(tabs) do
        SkinBase.SetFrameData(tab, "skinColor", { sr, sg, sb, sa })
        SkinBase.SetFrameData(tab, "bgColor", { bgr, bgg, bgb })
    end
    for _, tab in ipairs(tabs) do
        SkinBase.RefreshTabSelected(tab, owner)
    end
end

local scrollBoxAcquiredCallbacks = Helpers.CreateStateTable()

function SkinBase.ForEachScrollBoxFrame(scrollBox, callback)
    local okView, hasView = ns.SafeCallMethodIfPresent("best-effort-style", scrollBox, "HasView")
    if okView and not hasView then return end
    return ns.SafeCallMethodIfPresent("best-effort-style", scrollBox, "ForEachFrame", callback)
end

function SkinBase.HookScrollBoxAcquired(scrollBox, callback, opts)
    if not scrollBox or type(callback) ~= "function" then return end
    if not ScrollUtil or not ScrollUtil.AddAcquiredFrameCallback then return end

    local callbacks = scrollBoxAcquiredCallbacks[scrollBox]
    if not callbacks then
        callbacks = {}
        scrollBoxAcquiredCallbacks[scrollBox] = callbacks
    end
    local entry = {
        callback = callback,
        sync = opts and opts.sync == true,
    }
    callbacks[#callbacks + 1] = entry

    C_Timer.After(0, function()
        SkinBase.ForEachScrollBoxFrame(scrollBox, callback)
    end)

    if SkinBase.GetFrameData(scrollBox, "qScrollHooked") then return end

    ScrollUtil.AddAcquiredFrameCallback(scrollBox, function(_, frame)
        local list = scrollBoxAcquiredCallbacks[scrollBox]
        if not list then return end
        for _, item in ipairs(list) do
            if item.sync then
                item.callback(frame)
            else
                C_Timer.After(0, function()
                    item.callback(frame)
                end)
            end
        end
    end, scrollBox)

    SkinBase.SetFrameData(scrollBox, "qScrollHooked", true)
end

function SkinBase.LockPooledRowText(row, depth)
    if not row or SkinBase.GetFrameData(row, "qListRowFonted") then return end
    SkinBase.SkinFrameText(row, { recurse = true })
    SkinBase.LockFrameTextObjects(row, depth or 3)
    SkinBase.SetFrameData(row, "qListRowFonted", true)
end

function SkinBase.HookScrollBoxRowFonts(scrollBox, depth)
    if not scrollBox then return end
    SkinBase.HookScrollBoxAcquired(scrollBox, function(row)
        if not row or SkinBase.GetFrameData(row, "qListRowFonted") then return end
        SkinBase.LockPooledRowText(row, depth or 3)
    end, { sync = true })
end

function SkinBase.IsAddOnFullyLoaded(addonName)
    if not C_AddOns or not C_AddOns.IsAddOnLoaded then return false end
    local loadedOrLoading, loaded = C_AddOns.IsAddOnLoaded(addonName)
    if loaded ~= nil then return loaded end
    return loadedOrLoading == true
end

function SkinBase.OnAddOnLoaded(addonName, callback, delay)
    delay = delay or 0
    local function fire()
        if ns.RunAfterFirstFrame then
            ns.RunAfterFirstFrame(callback, delay)
        elseif delay > 0 then
            C_Timer.After(delay, callback)
        else
            callback()
        end
    end

    if SkinBase.IsAddOnFullyLoaded(addonName) then
        fire()
        return
    end

    local watcher = CreateFrame("Frame")
    watcher:RegisterEvent("ADDON_LOADED")
    watcher:SetScript("OnEvent", function(self, _, name)
        if name == addonName then
            self:UnregisterEvent("ADDON_LOADED")
            fire()
        end
    end)
end

local function HoverEnter(self)
    local bd = SkinBase.GetBackdrop(self)
    local sc = SkinBase.GetFrameData(self, "skinColor")
    if bd and sc then
        bd:SetBackdropBorderColor(
            math.min(sc[1] * HOVER_BRIGHTEN, 1),
            math.min(sc[2] * HOVER_BRIGHTEN, 1),
            math.min(sc[3] * HOVER_BRIGHTEN, 1),
            1)
    end
end

local function HoverLeave(self)
    local bd = SkinBase.GetBackdrop(self)
    local sc = SkinBase.GetFrameData(self, "skinColor")
    if bd and sc then
        bd:SetBackdropBorderColor(sc[1], sc[2], sc[3], sc[4])
    end
end

local function AttachHover(frame)
    if SkinBase.GetFrameData(frame, "qHoverHooked") then return end
    frame:HookScript("OnEnter", HoverEnter)
    frame:HookScript("OnLeave", HoverLeave)
    SkinBase.SetFrameData(frame, "qHoverHooked", true)
end

function SkinBase.SetRowHovered(frame, hovered)
    if not frame then return end
    if hovered then HoverEnter(frame) else HoverLeave(frame) end
end

local function AttachHoverWithRestore(frame, restoreFn)
    frame:HookScript("OnEnter", HoverEnter)
    frame:HookScript("OnLeave", function(self) restoreFn(self) end)
end

function SkinBase.SkinFontString(fontString, opts)
    if not fontString or not fontString.SetFont then return end
    opts = opts or {}

    local font = (Helpers.GetGeneralFont and Helpers.GetGeneralFont()) or STANDARD_TEXT_FONT
    local outline = opts.outline
    if outline == nil then
        outline = (Helpers.GetGeneralFontOutline and Helpers.GetGeneralFontOutline()) or ""
    end

    local size = opts.size
    if not size and fontString.GetFont then
        local _, curSize = fontString:GetFont()
        if type(curSize) == "number" and curSize > 0 then
            size = curSize
        end
    end
    size = size or 12

    CJKFont(fontString, font, size, outline)
    if opts.fontOnly then return end

    if fontString.SetTextColor then
        local c = opts.color
        if type(c) == "table" then
            fontString:SetTextColor(c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1)
        else
            fontString:SetTextColor(1, 1, 1, 1)
        end
    end
end

local function SafeWalkSkip(frame)
    if not frame then return true end
    if frame.IsForbidden and frame:IsForbidden() then return true end
    if frame.widgetType or frame.RegisterForWidgetSet then return true end
    return false
end
local function SafeRegions(frame)
    local ok, r = pcall(function() return { frame:GetRegions() } end)
    return ok and r or nil
end
local function SafeChildren(frame)
    local ok, c = pcall(function() return { frame:GetChildren() } end)
    return ok and c or nil
end

function SkinBase.SkinFrameText(frame, opts)
    if not frame then return end
    opts = opts or {}
    local fontOpts = opts.chrome and { color = opts.color } or { fontOnly = true }

    if SafeWalkSkip(frame) then return end

    local regions = frame.GetRegions and SafeRegions(frame)
    if regions then
        for _, region in ipairs(regions) do
            if region and region.GetObjectType and region:GetObjectType() == "FontString" then
                SkinBase.SkinFontString(region, fontOpts)
            end
        end
    end

    if opts.recurse and frame.GetChildren then
        local depth = opts.maxDepth or 6
        if depth > 0 then
            local children = SafeChildren(frame)
            if children then
                for _, child in ipairs(children) do
                    SkinBase.SkinFrameText(child, {
                        recurse = true,
                        maxDepth = depth - 1,
                        chrome = opts.chrome,
                        color = opts.color,
                    })
                end
            end
        end
    end
end

function SkinBase.LockFontObject(obj, opts)
    if not obj or SkinBase.GetFrameData(obj, "qFontLocked") then return end
    opts = opts or { fontOnly = true }

    if obj.SetFontObject and obj.SetFont then
        hooksecurefunc(obj, "SetFontObject", function(self)
            SkinBase.SkinFontString(self, opts)
        end)
    end

    local function LockButtonStateSetter(methodName)
        if obj[methodName] then
            hooksecurefunc(obj, methodName, function(self)
                local fs = self.GetFontString and self:GetFontString()
                if fs then SkinBase.SkinFontString(fs, opts) end
            end)
        end
    end
    LockButtonStateSetter("SetNormalFontObject")
    LockButtonStateSetter("SetHighlightFontObject")
    LockButtonStateSetter("SetDisabledFontObject")

    SkinBase.SetFrameData(obj, "qFontLocked", true)
end

function SkinBase.LockFrameTextObjects(frame, maxDepth)
    if not frame then return end
    maxDepth = maxDepth or 4
    if frame.GetObjectType and frame:GetObjectType() == "Button" and frame.SetNormalFontObject then
        SkinBase.LockFontObject(frame, { fontOnly = true })
    end
    if SafeWalkSkip(frame) then return end
    local regions = frame.GetRegions and SafeRegions(frame)
    if regions then
        for _, region in ipairs(regions) do
            if region and region.GetObjectType and region:GetObjectType() == "FontString" then
                SkinBase.LockFontObject(region, { fontOnly = true })
            end
        end
    end
    if maxDepth > 0 and frame.GetChildren then
        local children = SafeChildren(frame)
        if children then
            for _, child in ipairs(children) do
                SkinBase.LockFrameTextObjects(child, maxDepth - 1)
            end
        end
    end
end

function SkinBase.ApplyButtonFontObjectsDeep(frame, maxDepth)
    if not frame then return end
    maxDepth = maxDepth or 4
    if SafeWalkSkip(frame) then return end
    if frame.GetObjectType then
        local ok, t = pcall(frame.GetObjectType, frame)
        if not ok then return end
        if (t == "Button" or t == "CheckButton")
            and frame.GetFontString and frame:GetFontString()
            and not SkinBase.GetFrameData(frame, "qBtnFontDriven") then
            SkinBase.ApplyButtonFontObjects(frame)
            SkinBase.SetFrameData(frame, "qBtnFontDriven", true)
        end
    end
    if maxDepth > 0 and frame.GetChildren then
        local children = SafeChildren(frame)
        if children then
            for _, child in ipairs(children) do
                SkinBase.ApplyButtonFontObjectsDeep(child, maxDepth - 1)
            end
        end
    end
end

function SkinBase.LockDropdownText(dropdown, maxDepth)
    if not dropdown then return end
    local text = dropdown.Text or (dropdown.GetFontString and dropdown:GetFontString())
    if text then
        SkinBase.SkinFontString(text, { fontOnly = true })
        SkinBase.LockFontObject(text, { fontOnly = true })
    end
    SkinBase.LockFrameTextObjects(dropdown, maxDepth or 2)
end

local function GetLabelFontString(frame)
    if not frame then return nil end
    if frame.GetFontString then
        local fs = frame:GetFontString()
        if fs then return fs end
    end
    return frame.Text
end

local function SetFontStringColor(fs, color)
    if not fs or not fs.SetTextColor or type(color) ~= "table" then return end
    fs:SetTextColor(color[1] or 1, color[2] or 1, color[3] or 1, color[4] or 1)
end

local BUTTON_ART_KEYS = {
    "Left", "Right", "Middle", "Center",
    "NormalTexture", "HighlightTexture", "PushedTexture", "DisabledTexture",
}

local function SuppressButtonArt(button)
    if not button then return end
    for _, key in ipairs(BUTTON_ART_KEYS) do
        local tex = button[key]
        if tex and tex.SetAlpha then tex:SetAlpha(0) end
    end
    local highlight = button.GetHighlightTexture and button:GetHighlightTexture()
    if highlight then highlight:SetAlpha(0) end
    local pushed = button.GetPushedTexture and button:GetPushedTexture()
    if pushed then pushed:SetAlpha(0) end
    local normal = button.GetNormalTexture and button:GetNormalTexture()
    if normal then normal:SetAlpha(0) end
    local disabled = button.GetDisabledTexture and button:GetDisabledTexture()
    if disabled then disabled:SetAlpha(0) end
end

function SkinBase.RefreshButtonVisualState(button)
    if not button then return end
    SuppressButtonArt(button)

    if not SkinBase.GetFrameData(button, "skinFont") then return end

    local color = SkinBase.GetFrameData(button, "skinFontColor")
    local disabledColor = SkinBase.GetFrameData(button, "skinFontDisabledColor") or DISABLED_TEXT_COLOR
    SkinBase.ApplyButtonFontObjects(button, { color = color, disabledColor = disabledColor })

    if button.IsEnabled and not button:IsEnabled() then
        SetFontStringColor(GetLabelFontString(button), disabledColor)
    else
        SetFontStringColor(GetLabelFontString(button), color)
    end
end

local BUTTON_STATE_SCRIPTS = { "OnShow", "OnEnable", "OnDisable", "OnMouseDown", "OnMouseUp" }

local function HookButtonVisualState(button)
    if not button or not button.HookScript or SkinBase.GetFrameData(button, "qButtonVisualStateHooked") then return end
    for _, script in ipairs(BUTTON_STATE_SCRIPTS) do
        button:HookScript(script, SkinBase.RefreshButtonVisualState)
    end
    SkinBase.SetFrameData(button, "qButtonVisualStateHooked", true)
end

function SkinBase.SkinButton(button, opts)
    if not button or SkinBase.IsStyled(button) then return end
    opts = opts or {}
    local sr, sg, sb, sa, bgr, bgg, bgb = SkinBase.GetSkinColors()
    local boost = opts.bgBoost or BG_BOOST_BUTTON

    if opts.strip then
        SkinBase.StripTextures(button)
    else
        SuppressButtonArt(button)
    end

    SkinBase.CreateBackdrop(button, sr, sg, sb, sa,
        math.min(bgr + boost, 1), math.min(bgg + boost, 1), math.min(bgb + boost, 1), 1)
    if opts.belowChildren then
        local bd = SkinBase.GetBackdrop(button)
        if bd then bd:SetFrameLevel(math.max(0, button:GetFrameLevel() - 1)) end
    end
    SkinBase.SetFrameData(button, "skinColor", { sr, sg, sb, sa })
    SkinBase.SetFrameData(button, "skinKind", "button")
    SkinBase.SetFrameData(button, "bgBoost", boost)
    if opts.font ~= false then
        local fontColor = opts.fontColor or NORMAL_TEXT_COLOR
        SkinBase.SetFrameData(button, "skinFont", true)
        SkinBase.SetFrameData(button, "skinFontColor", fontColor)
        SkinBase.SetFrameData(button, "skinFontDisabledColor", opts.disabledFontColor or DISABLED_TEXT_COLOR)
        SkinBase.ApplyButtonFontObjects(button, { color = fontColor, disabledColor = opts.disabledFontColor or DISABLED_TEXT_COLOR })
    end
    if opts.hover ~= false then AttachHover(button) end
    HookButtonVisualState(button)
    SkinBase.RefreshButtonVisualState(button)
    SkinBase.MarkStyled(button)
end

function SkinBase.SkinEditBox(editBox, opts)
    if not editBox or SkinBase.IsStyled(editBox) then return end
    opts = opts or {}
    local sr, sg, sb, sa, bgr, bgg, bgb, bga = SkinBase.GetSkinColors()
    if opts.borderAlpha then sa = sa * opts.borderAlpha end
    if opts.bgAlpha then bga = opts.bgAlpha end
    SkinBase.StripTextures(editBox)
    SkinBase.CreateBackdrop(editBox, sr, sg, sb, sa, bgr, bgg, bgb, bga)
    SkinBase.SetFrameData(editBox, "skinColor", { sr, sg, sb, sa })
    SkinBase.SetFrameData(editBox, "skinKind", "editbox")
    if opts.font ~= false then
        SkinBase.SetFrameData(editBox, "skinFont", true)
        SkinBase.SetFrameData(editBox, "skinFontColor", opts.fontColor)
        SkinBase.SkinFontString(editBox, { color = opts.fontColor })
        SkinBase.LockFontObject(editBox, { fontOnly = true })
    end
    SkinBase.MarkStyled(editBox)
end

function SkinBase.SkinScrollRow(row, opts)
    if not row or SkinBase.IsStyled(row) then return end
    opts = opts or {}
    local sr, sg, sb, sa, bgr, bgg, bgb = SkinBase.GetSkinColors()
    local boost = opts.bgBoost or BG_BOOST_ROW
    local borderAlphaMult = opts.borderAlphaMult or 0.5
    local bgAlpha = opts.bgAlpha or 0.6

    SkinBase.StripTextures(row)
    SkinBase.CreateBackdrop(row, sr, sg, sb, sa * borderAlphaMult,
        math.min(bgr + boost, 1), math.min(bgg + boost, 1), math.min(bgb + boost, 1), bgAlpha)
    SkinBase.SetFrameData(row, "skinColor", { sr, sg, sb, sa * borderAlphaMult })
    SkinBase.SetFrameData(row, "skinKind", "row")
    SkinBase.SetFrameData(row, "bgBoost", boost)
    SkinBase.SetFrameData(row, "bgAlpha", bgAlpha)
    SkinBase.SetFrameData(row, "borderAlphaMult", borderAlphaMult)
    if opts.hover ~= false then AttachHover(row) end
    SkinBase.MarkStyled(row)
end

function SkinBase.SkinIcon(icon, opts)
    if not icon or not icon.SetTexCoord then return end
    opts = opts or {}
    if opts.crop ~= false then
        icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    end

    local existing = SkinBase.GetFrameData(icon, "iconBorder")
    if existing then
        if opts.border then SkinBase.SetBackdropColors(existing, opts.border, nil) end
        return existing
    end

    local host = opts.parent or (icon.GetParent and icon:GetParent())
    if not host then return end
    local pixels = opts.pixels or SkinBase.CHROME.BORDER_PX or 1
    local border = CreateFrame("Frame", nil, host, "BackdropTemplate")
    SkinBase.SetExpandedPixelPoints(border, icon, pixels)
    if border.SetFrameLevel and host.GetFrameLevel then
        border:SetFrameLevel(host:GetFrameLevel())
    end
    if border.EnableMouse then border:EnableMouse(false) end

    local bc = opts.border
    if not bc then
        local sr, sg, sb, sa = SkinBase.GetSkinColors()
        bc = { sr, sg, sb, sa }
    end
    SkinBase.ApplyPixelBackdrop(border, pixels, false, false, bc)
    SkinBase.SetFrameData(icon, "iconBorder", border)
    return border
end

function SkinBase.SkinStatusBar(bar, opts)
    if not bar or SkinBase.IsStyled(bar) then return end
    opts = opts or {}

    if bar.SetStatusBarTexture then
        bar:SetStatusBarTexture(opts.texture or DEFAULT_BACKDROP_TEXTURE)
        UIKit.DisablePixelSnap(bar)
    end
    if bar.SetStatusBarColor then
        local r, g, b, a
        if opts.color then
            r, g, b, a = opts.color[1], opts.color[2], opts.color[3], opts.color[4]
        else
            r, g, b, a = SkinBase.GetSkinBarColor(opts.settings, opts.prefix)
        end
        bar:SetStatusBarColor(r or 0.5, g or 0.5, b or 0.5, a or 1)
    end
    if opts.backdrop ~= false then
        local sr, sg, sb, sa, bgr, bgg, bgb, bga = SkinBase.GetSkinColors()
        SkinBase.CreateBackdrop(bar, sr, sg, sb, sa, bgr, bgg, bgb, bga)
    end
    SkinBase.MarkStyled(bar)
end

function SkinBase.SkinNextPrevButton(button, direction, opts)
    if not button or SkinBase.GetFrameData(button, "nextPrevStyled") then return end
    opts = opts or {}

    SkinBase.SkinButton(button, { strip = true })

    local bd = SkinBase.GetBackdrop(button)
    if bd and SkinBase.SetInsetPixelPoints then
        SkinBase.SetInsetPixelPoints(bd, button, opts.inset or 4)
    end

    if button.CreateFontString then
        local glyph = button:CreateFontString(nil, "OVERLAY")
        local font = (Helpers.GetGeneralFont and Helpers.GetGeneralFont()) or STANDARD_TEXT_FONT
        glyph:SetFont(font, opts.size or 14, "OUTLINE")
        local isPrev = direction == "left" or direction == "prev"
        glyph:SetText(isPrev and "\226\151\132" or "\226\150\186")
        glyph:SetPoint("CENTER")
        glyph:SetTextColor(1, 1, 1, 1)
        SkinBase.SetFrameData(button, "nextPrevGlyph", glyph)
    end
    SkinBase.SetFrameData(button, "nextPrevStyled", true)
end

function SkinBase.SkinCheckBox(check, opts)
    if not check or SkinBase.IsStyled(check) then return end
    opts = opts or {}

    local normal = check.GetNormalTexture and check:GetNormalTexture()
    if normal then
        if normal.SetTexture then normal:SetTexture(nil) end
        if normal.SetAlpha then normal:SetAlpha(0) end
    end
    local pushed = check.GetPushedTexture and check:GetPushedTexture()
    if pushed and pushed.SetAlpha then pushed:SetAlpha(0) end
    local hl = check.GetHighlightTexture and check:GetHighlightTexture()
    if hl and hl.SetAlpha then hl:SetAlpha(0) end

    local sr, sg, sb, sa, bgr, bgg, bgb, bga = SkinBase.GetSkinColors()
    SkinBase.CreateBackdrop(check, sr, sg, sb, sa, bgr, bgg, bgb, bga)

    local ar, ag, ab = UIKit.GetAccentColor()
    local checked = check.GetCheckedTexture and check:GetCheckedTexture()
    if checked then
        if checked.SetVertexColor and ar then checked:SetVertexColor(ar, ag, ab, 1) end
        if checked.SetDrawLayer then checked:SetDrawLayer("OVERLAY", 7) end
    end
    local disabledChecked = check.GetDisabledCheckedTexture and check:GetDisabledCheckedTexture()
    if disabledChecked then
        if disabledChecked.SetVertexColor and ar then
            disabledChecked:SetVertexColor(ar * 0.5, ag * 0.5, ab * 0.5, 1)
        end
        if disabledChecked.SetDrawLayer then disabledChecked:SetDrawLayer("OVERLAY", 7) end
    end

    SkinBase.MarkStyled(check)
end

function SkinBase.HandleIconBorder(nativeBorder, quiBorder, opts)
    if not nativeBorder or not quiBorder then return end
    if SkinBase.GetFrameData(nativeBorder, "iconBorderHandled") then return end
    SkinBase.SetFrameData(nativeBorder, "iconBorderHandled", true)
    opts = opts or {}
    local default = opts.defaultBorder

    if nativeBorder.SetVertexColor then
        hooksecurefunc(nativeBorder, "SetVertexColor", function(_, r, g, b, a)
            SkinBase.SetBackdropColors(quiBorder, { r, g, b, a or 1 }, nil)
        end)
    end
    if default then
        local function revert() SkinBase.SetBackdropColors(quiBorder, default, nil) end
        if nativeBorder.Hide then hooksecurefunc(nativeBorder, "Hide", revert) end
        if nativeBorder.SetShown then
            hooksecurefunc(nativeBorder, "SetShown", function(_, shown)
                if shown == false then revert() end
            end)
        end
    end

    if nativeBorder.GetVertexColor then
        local ok, r, g, b, a = pcall(nativeBorder.GetVertexColor, nativeBorder)
        if ok and r then SkinBase.SetBackdropColors(quiBorder, { r, g, b, a or 1 }, nil) end
    end

    if nativeBorder.SetAlpha then nativeBorder:SetAlpha(0) end
end

function SkinBase.SkinTrimScrollBar(scrollBar, opts)
    if not scrollBar then return end
    opts = opts or {}

    if scrollBar.Track then scrollBar.Track:SetAlpha(0) end
    if scrollBar.Background then scrollBar.Background:SetAlpha(0) end

    local thumb = scrollBar.ThumbTexture or (scrollBar.GetThumbTexture and scrollBar:GetThumbTexture()) or scrollBar.Thumb
    if thumb then
        local r, g, b
        if opts.color then
            r, g, b = opts.color[1], opts.color[2], opts.color[3]
        else
            r, g, b = SkinBase.GetSkinBarColor()
        end
        thumb:SetColorTexture(r or 0.5, g or 0.5, b or 0.5, opts.alpha or 0.78)
        UIKit.DisablePixelSnap(thumb)
        thumb:SetWidth((opts.width or 8) * SkinBase.GetPixelSize(scrollBar, 1))
    end

    local upBtn = scrollBar.ScrollUpButton or scrollBar.Back
    local downBtn = scrollBar.ScrollDownButton or scrollBar.Forward
    if upBtn then upBtn:SetAlpha(0); upBtn:SetSize(1, 1) end
    if downBtn then downBtn:SetAlpha(0); downBtn:SetSize(1, 1) end
end

function SkinBase.RefreshCategorySelected(button)
    local bd = SkinBase.GetBackdrop(button)
    local sc = SkinBase.GetFrameData(button, "skinColor")
    if not bd or not sc then return end
    local selected = button.SelectedTexture and button.SelectedTexture:IsShown()
    local label = button.Label or GetLabelFontString(button)
    local data = pixelBackdropData[bd]
    if data then data.borderColor, data.bgColor = nil, nil end
    local r, g, b, a = SkinBase.GetDepthColor("ROW")
    if selected then
        bd:SetBackdropBorderColor(sc[1], sc[2], sc[3], sc[4])
        bd:SetBackdropColor(r, g, b, a)
        SetFontStringColor(label, SkinBase.GetFrameData(button, "categorySelectedTextColor") or sc)
    else
        bd:SetBackdropBorderColor(sc[1], sc[2], sc[3], (sc[4] or 1) * 0.5)
        bd:SetBackdropColor(r, g, b, 0.7)
        SetFontStringColor(label, SkinBase.GetFrameData(button, "categoryTextColor") or { 1, 1, 1, 1 })
    end
end

function SkinBase.SkinCategoryButton(button, opts)
    if not button or SkinBase.IsStyled(button) then return end
    opts = opts or {}
    SkinBase.StripTextures(button)
    if button.SelectedTexture then button.SelectedTexture:SetAlpha(0) end
    if button.NormalTexture then button.NormalTexture:SetAlpha(0) end
    local hl = button.GetHighlightTexture and button:GetHighlightTexture()
    if hl then hl:SetAlpha(0) end
    local sr, sg, sb, sa = SkinBase.GetSkinColors()
    SkinBase.CreateBackdrop(button, sr, sg, sb, sa)
    SkinBase.SetFrameData(button, "skinColor", { sr, sg, sb, sa })
    SkinBase.SetFrameData(button, "skinKind", "category")
    SkinBase.SetFrameData(button, "categorySelectedTextColor", opts.selectedTextColor)
    SkinBase.SetFrameData(button, "categoryTextColor", opts.textColor)
    if opts.font ~= false then
        SkinBase.ApplyButtonFontObjects(button, { disabledColor = DISABLED_TEXT_COLOR })
    end
    SkinBase.RefreshCategorySelected(button)
    AttachHoverWithRestore(button, SkinBase.RefreshCategorySelected)
    SkinBase.MarkStyled(button)
end

function SkinBase.SkinDropdown(dropdown, opts)
    if not dropdown or SkinBase.IsStyled(dropdown) then return end
    opts = opts or {}
    local sr, sg, sb, sa, bgr, bgg, bgb = SkinBase.GetSkinColors()
    local boost = opts.bgBoost or BG_BOOST_BUTTON

    if opts.noStrip then
    elseif opts.skinArrow then
        SkinBase.StripTextures(dropdown)
        SuppressButtonArt(dropdown)
        SkinBase.ClampTextureHidden(dropdown.Arrow)
    elseif opts.keepArrow then
        if dropdown.NineSlice then dropdown.NineSlice:SetAlpha(0) end
        if dropdown.NormalTexture then dropdown.NormalTexture:SetAlpha(0) end
        if dropdown.HighlightTexture then dropdown.HighlightTexture:SetAlpha(0) end
        if dropdown.Background then dropdown.Background:SetAlpha(0) end
    else
        SkinBase.StripTextures(dropdown)
    end

    SkinBase.CreateBackdrop(dropdown, sr, sg, sb, sa,
        math.min(bgr + boost, 1), math.min(bgg + boost, 1), math.min(bgb + boost, 1), 1)
    local bd = SkinBase.GetBackdrop(dropdown)
    if bd then
        if opts.insetY then
            bd:ClearAllPoints()
            bd:SetPoint("TOPLEFT", 0, -opts.insetY)
            bd:SetPoint("BOTTOMRIGHT", 0, opts.insetY)
        end
        if opts.belowChildren then
            bd:SetFrameLevel(math.max(0, dropdown:GetFrameLevel() - 1))
        end
    end
    SkinBase.SetFrameData(dropdown, "skinColor", { sr, sg, sb, sa })
    SkinBase.SetFrameData(dropdown, "bgColor", { bgr, bgg, bgb })
    SkinBase.SetFrameData(dropdown, "skinKind", "dropdown")
    SkinBase.SetFrameData(dropdown, "bgBoost", boost)
    if opts.skinArrow and not SkinBase.GetFrameData(dropdown, "dropdownCaret") then
        local arrow = dropdown.Arrow
        local caret = UIKit.CreateChevronCaret(dropdown, {
            point = arrow and "CENTER" or "RIGHT",
            relativeTo = arrow or dropdown,
            relativePoint = arrow and "CENTER" or "RIGHT",
            xPixels = arrow and 0 or -8,
            sizePixels = 10,
            lineWidthPixels = 6,
            expanded = true,
            a = 0.8,
        })
        SkinBase.SetFrameData(dropdown, "dropdownCaret", caret)
    end
    SkinBase.LockDropdownText(dropdown, 2)
    if opts.hover ~= false then AttachHover(dropdown) end
    SkinBase.MarkStyled(dropdown)
end

function SkinBase.SkinListContainer(list, rowStyler)
    if not list or SkinBase.IsStyled(list) then return end
    if list.NineSlice then list.NineSlice:Hide() end
    if list.BackgroundNineSlice then list.BackgroundNineSlice:Hide() end
    if list.Background and list.Background.SetAlpha then list.Background:SetAlpha(0) end
    SkinBase.StripTextures(list)
    if list.ScrollBox and rowStyler then
        SkinBase.HookScrollBoxAcquired(list.ScrollBox, rowStyler)
    end
    if list.ScrollBar then
        SkinBase.SkinTrimScrollBar(list.ScrollBar)
    end
    if list.ResultsText then
        SkinBase.SkinFontString(list.ResultsText, { fontOnly = true })
        SkinBase.LockFontObject(list.ResultsText, { fontOnly = true })
    end
    SkinBase.MarkStyled(list)
end

function SkinBase.RefreshWidget(frame)
    if not frame then return end
    local bd = SkinBase.GetBackdrop(frame)
    if not bd then return end
    local kind = SkinBase.GetFrameData(frame, "skinKind")
    if not kind then return end
    local sr, sg, sb, sa, bgr, bgg, bgb, bga = SkinBase.GetSkinColors()

    if kind == "button" or kind == "dropdown" then
        local boost = SkinBase.GetFrameData(frame, "bgBoost") or BG_BOOST_BUTTON
        SkinBase.SetBackdropColors(bd,
            { sr, sg, sb, sa },
            { math.min(bgr + boost, 1), math.min(bgg + boost, 1), math.min(bgb + boost, 1), 1 })
        SkinBase.SetFrameData(frame, "skinColor", { sr, sg, sb, sa })
        if kind == "dropdown" then
            SkinBase.SetFrameData(frame, "bgColor", { bgr, bgg, bgb })
        end
    elseif kind == "editbox" then
        SkinBase.SetBackdropColors(bd, { sr, sg, sb, sa }, { bgr, bgg, bgb, bga })
        SkinBase.SetFrameData(frame, "skinColor", { sr, sg, sb, sa })
    elseif kind == "row" then
        local boost = SkinBase.GetFrameData(frame, "bgBoost") or BG_BOOST_ROW
        local bgAlpha = SkinBase.GetFrameData(frame, "bgAlpha") or 0.6
        local mult = SkinBase.GetFrameData(frame, "borderAlphaMult") or 0.5
        SkinBase.SetBackdropColors(bd,
            { sr, sg, sb, sa * mult },
            { math.min(bgr + boost, 1), math.min(bgg + boost, 1), math.min(bgb + boost, 1), bgAlpha })
        SkinBase.SetFrameData(frame, "skinColor", { sr, sg, sb, sa * mult })
    elseif kind == "category" then
        SkinBase.SetFrameData(frame, "skinColor", { sr, sg, sb, sa })
        SkinBase.RefreshCategorySelected(frame)
    end

    if SkinBase.GetFrameData(frame, "skinFont") then
        local color = SkinBase.GetFrameData(frame, "skinFontColor")
        if kind == "editbox" then
            SkinBase.SkinFontString(frame, { color = color })
        else
            local disabledColor = SkinBase.GetFrameData(frame, "skinFontDisabledColor") or DISABLED_TEXT_COLOR
            SkinBase.ApplyButtonFontObjects(frame, { color = color, disabledColor = disabledColor })
        end
    end
end

function SkinBase.SkinButtonFrameTemplate(frame)
    if not frame then return end
    SkinBase.HidePortraitFrameChrome(frame)
    local sr, sg, sb, sa, bgr, bgg, bgb, bga = SkinBase.GetSkinColors()
    SkinBase.CreateBackdrop(frame, sr, sg, sb, sa, bgr, bgg, bgb, bga)
    if frame.CloseButton then
        SkinBase.SkinCloseButton(frame.CloseButton)
    end
end

function SkinBase.SkinWindow(frame, opts)
    if not frame then return end
    opts = opts or {}
    local depth = opts.depth or 4

    SkinBase.HidePortraitFrameChrome(frame)
    if not opts.noBackdrop then
        local sr, sg, sb, sa, bgr, bgg, bgb, bga = SkinBase.GetSkinColors()
        SkinBase.CreateBackdrop(frame, sr, sg, sb, sa, bgr, bgg, bgb, bga)
    end
    if not opts.noClose and frame.CloseButton then
        SkinBase.SkinCloseButton(frame.CloseButton)
    end
    if opts.tabs then
        SkinBase.SkinTabGroup(opts.tabs, opts.tabOwner or frame, { resizeToText = true })
    end

    if not opts.noButtonFonts then
        SkinBase.ApplyButtonFontObjectsDeep(frame, depth)
    end

    if opts.scrollBars then
        for _, bar in ipairs(opts.scrollBars) do
            SkinBase.SkinTrimScrollBar(bar)
        end
    end
end

ns.SkinBase = UIKit
