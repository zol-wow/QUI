---------------------------------------------------------------------------
-- QUI UIKit
-- Shared UI primitives for creating frames, borders, backgrounds, text
-- Eliminates duplicated factory functions across modules
---------------------------------------------------------------------------
local ADDON_NAME, ns = ...

local UIKit = {}
ns.UIKit = UIKit

local LSM = ns.LSM
local Helpers = ns.Helpers
local DEFAULT_FONT = "Fonts\\FRIZQT__.TTF"
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

-- Shared fallback color table for checkboxes (avoids per-widget allocation)
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

---------------------------------------------------------------------------
-- SCALE-BOUND REGISTRY
---------------------------------------------------------------------------

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
            pcall(refreshFn, owner)
        end
    end
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
                    pcall(state.onUpdate, owner, value, progress)
                end
                if progress >= 1 then
                    states[key] = nil
                    if state.onFinish then
                        pcall(state.onFinish, owner, state.toValue)
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

    pcall(options.onUpdate, owner, options.fromValue or 0, 0)
    local driver = EnsureAnimationDriver()
    driver:SetScript("OnUpdate", animationDriverOnUpdate)
end

---------------------------------------------------------------------------
-- PIXEL HELPERS
---------------------------------------------------------------------------

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

function UIKit.SetOutsidePx(frame, anchor, leftPixels, rightPixels, topPixels, bottomPixels)
    if rightPixels == nil and topPixels == nil and bottomPixels == nil then
        UIKit.SetInsetPointsPx(frame, anchor, -(leftPixels or 0), -(leftPixels or 0), -(leftPixels or 0), -(leftPixels or 0))
        return
    end
    UIKit.SetInsetPointsPx(frame, anchor, -(leftPixels or 0), -(rightPixels or 0), -(topPixels or 0), -(bottomPixels or 0))
end

---------------------------------------------------------------------------
-- FONT
---------------------------------------------------------------------------

--- Resolve a named font via LibSharedMedia, falling back to the user's
--- general font setting, then to the WoW default.
--- @param fontName string|nil  LSM font name (e.g. "Quazii"). nil = use general setting.
--- @return string Font file path
function UIKit.ResolveFontPath(fontName)
    if fontName and LSM then
        local path = LSM:Fetch("font", fontName)
        if path then return path end
    end
    return Helpers.GetGeneralFont()
end

---------------------------------------------------------------------------
-- BACKDROP
---------------------------------------------------------------------------

--- Build a backdrop info table with optional LSM border texture.
--- @param borderTextureName string|nil  LSM border name, or nil/"None" for no edge
--- @param borderSizePixels number|nil   Border thickness in physical pixels
--- @param frame Frame|nil               Reference frame for pixel scaling
--- @return table Backdrop info suitable for SetBackdrop()
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

---------------------------------------------------------------------------
-- BORDER LINES (pixel-perfect overlay textures)
---------------------------------------------------------------------------

--- Create 4 OVERLAY textures for solid pixel borders around a frame.
--- Stores the result in a weak registry; no-ops if already created.
--- @param frame Frame  The frame to add borders to
--- @return table  { top, bottom, left, right } texture handles
function UIKit.CreateBorderLines(frame)
    local state = borderLineState[frame]
    if state and state.edges then return state.edges end

    local borders = {
        top = frame:CreateTexture(nil, "OVERLAY", nil, 7),
        bottom = frame:CreateTexture(nil, "OVERLAY", nil, 7),
        left = frame:CreateTexture(nil, "OVERLAY", nil, 7),
        right = frame:CreateTexture(nil, "OVERLAY", nil, 7),
    }

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
    return borders
end

--- Size, color, and show/hide pixel border lines.
--- @param frame Frame             Frame with border lines created via CreateBorderLines
--- @param sizePixels number       Border thickness in physical pixels
--- @param r number                Red (0-1)
--- @param g number                Green (0-1)
--- @param b number                Blue (0-1)
--- @param a number|nil            Alpha (0-1), defaults to 1
--- @param hide boolean|nil        Force-hide all borders
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
    if state.sizePixels == newSize
        and state.hidden == newHidden
        and color
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
    RefreshBorderLines(frame)
end

---------------------------------------------------------------------------
-- TEXT
---------------------------------------------------------------------------

--- Create a FontString with sensible defaults.
--- @param parent Frame|Region     Parent frame or region
--- @param fontSize number         Font size in points
--- @param fontPath string|nil     Font file path (nil = general font)
--- @param fontOutline string|nil  Outline style ("OUTLINE", "THICKOUTLINE", "")
--- @param layer string|nil        Draw layer, defaults to "OVERLAY"
--- @return FontString
function UIKit.CreateText(parent, fontSize, fontPath, fontOutline, layer)
    local text = parent:CreateFontString(nil, layer or "OVERLAY")
    local path = fontPath or UIKit.ResolveFontPath()
    local outline = fontOutline or (Helpers and Helpers.GetGeneralFontOutline and Helpers.GetGeneralFontOutline()) or "OUTLINE"
    local core = GetCore()
    if core and core.ApplyFont then
        core:ApplyFont(text, parent, fontSize, path, outline)
    else
        text:SetFont(path, fontSize, outline)
    end
    text:SetTextColor(1, 1, 1, 1)
    text:SetWordWrap(false)
    return text
end

---------------------------------------------------------------------------
-- BACKGROUND
---------------------------------------------------------------------------

--- Create a BACKGROUND-layer texture filled with a solid color.
--- Uses WHITE8x8 + SetVertexColor so callers can update via SetVertexColor later.
--- @param parent Frame|Region     Parent frame
--- @param r number|nil            Red (default 0.149)
--- @param g number|nil            Green (default 0.149)
--- @param b number|nil            Blue (default 0.149)
--- @param a number|nil            Alpha (default 1)
--- @return Texture
function UIKit.CreateBackground(parent, r, g, b, a)
    local bg = parent:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetTexture("Interface\\Buttons\\WHITE8x8")
    bg:SetVertexColor(r or 0.149, g or 0.149, b or 0.149, a or 1)
    UIKit.DisablePixelSnap(bg)
    return bg
end

---------------------------------------------------------------------------
-- BACKDROP BORDER
---------------------------------------------------------------------------

--- Create a pixel-perfect border frame that surrounds the parent.
--- @param parent Frame            Parent frame
--- @param borderSizePixels number Border thickness in physical pixels
--- @param r number|nil            Red (default 0)
--- @param g number|nil            Green (default 0)
--- @param b number|nil            Blue (default 0)
--- @param a number|nil            Alpha (default 1)
--- @return Frame  The border frame (also stored as parent.Border)
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
            -- Manual border frames do not render a backdrop fill.
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

---------------------------------------------------------------------------
-- CHECKBOX
---------------------------------------------------------------------------

--- Create a QUI accent-style checkbox button.
--- options:
---   size number|nil               Checkbox size in pixels (default 16)
---   checked boolean|nil           Initial checked state (default false)
---   colors table|nil              Optional color table (GUI.Colors-style)
---   onChange fun(checked:boolean) Optional change callback
--- @param parent Frame             Parent frame
--- @param options table|nil        Checkbox options
--- @return Button                  Checkbox with helpers: GetChecked/SetChecked/Toggle/SetHovered
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
    -- UI-CheckBox-Check is naturally drawn ~40% bigger than the box; size accordingly.
    mark:SetSize(size * 1.4, size * 1.4)
    mark:SetPoint("CENTER", checkbox, "CENTER", 0, 0)
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

---------------------------------------------------------------------------
-- CHEVRON CARET
---------------------------------------------------------------------------

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

---------------------------------------------------------------------------
-- ICON
---------------------------------------------------------------------------

--- Create an icon frame with a border texture and cropped artwork.
--- @param parent Frame            Parent/anchor frame
--- @param size number             Icon dimensions in physical pixels (width = height)
--- @param borderSizePixels number Border inset in physical pixels
--- @param r number|nil            Border red (default 0)
--- @param g number|nil            Border green (default 0)
--- @param b number|nil            Border blue (default 0)
--- @param a number|nil            Border alpha (default 1)
--- @return Frame  The icon frame; also sets parent.icon, parent.iconTexture, parent.iconBorder
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

---------------------------------------------------------------------------
-- OBJECT POOL
---------------------------------------------------------------------------

--- Create a lightweight reusable object pool.
--- factory is called when the pool is empty.
--- resetter is called before an object is returned to the pool.
--- @param factory function Function that creates a new object
--- @param resetter function|nil Function called as resetter(object)
--- @return table Pool object with Acquire/Release/Available methods
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

---------------------------------------------------------------------------
-- ANCHOR PROXY
---------------------------------------------------------------------------

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
        -- Scale conversion: sizeResolver dimensions are in the source frame's
        -- coordinate space, but the proxy is parented to UIParent.  Convert
        -- so the proxy's screen-space size matches the actual source content.
        -- Cache effective scale — GetEffectiveScale can return secret values
        -- during combat which cannot be used in Lua arithmetic.
        local rawSrcScale = source:GetEffectiveScale()
        local rawPxyScale = self:GetEffectiveScale()
        local sourceScale, proxyScale
        if rawSrcScale and not (issecretvalue and issecretvalue(rawSrcScale)) then
            sourceScale = rawSrcScale
            cachedSourceScale = rawSrcScale
        else
            sourceScale = cachedSourceScale
        end
        if rawPxyScale and not (issecretvalue and issecretvalue(rawPxyScale)) then
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
        -- Use epsilon comparison — WoW's GetWidth/GetHeight can return
        -- slightly different floats than what was passed to SetSize,
        -- causing infinite SetSize→OnSizeChanged→SetSize loops.
        if math.abs(lastWidth - w) > 0.5 or math.abs(lastHeight - h) > 0.5 then
            -- pcall: if protection somehow propagated to the proxy (e.g.
            -- brief window at combat boundary), silently defer rather than
            -- throwing ADDON_ACTION_BLOCKED.
            local ok = pcall(self.SetSize, self, w, h)
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
            -- pcall: anchoring to source can propagate protection from
            -- Blizzard frames; if the proxy became protected, ClearAllPoints
            -- and SetPoint would be blocked during combat.
            if pcall(self.ClearAllPoints, self) then
                pcall(self.SetPoint, self, "CENTER", source, "CENTER", 0, 0)
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
