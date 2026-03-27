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

    UIKit.SetSizePx(checkbox, state.sizePixels or 16, state.sizePixels or 16)

    local leftWidth = max(4, floor((state.sizePixels or 16) * 0.31))
    local rightWidth = max(6, floor((state.sizePixels or 16) * 0.5))
    SetRegionSizePx(checkbox.checkLeft, leftWidth, 2, checkbox)
    SetRegionSizePx(checkbox.checkRight, rightWidth, 2, checkbox)
    UIKit.SetPointPx(checkbox.checkLeft, "CENTER", checkbox, "CENTER", -2, -1)
    UIKit.SetPointPx(checkbox.checkRight, "CENTER", checkbox, "CENTER", 2, 0)
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

    state.sizePixels = sizePixels or state.sizePixels or 1
    state.color = { r or 0, g or 0, b or 0, a or 1 }
    state.hidden = hide or (state.sizePixels or 0) <= 0
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
    local size = options.size or 16
    local checked = options.checked and true or false
    local onChange = options.onChange

    local colors = options.colors
    if not colors and QUI and QUI.GUI and QUI.GUI.Colors then
        colors = QUI.GUI.Colors
    end
    colors = colors or DEFAULT_CHECKBOX_COLORS

    local checkbox = CreateFrame("Button", nil, parent)
    accentCheckboxState[checkbox] = { sizePixels = size }
    UIKit.SetSizePx(checkbox, size, size)

    checkbox.bg = UIKit.CreateBackground(checkbox)
    UIKit.CreateBorderLines(checkbox)

    checkbox.checkLeft = checkbox:CreateTexture(nil, "OVERLAY")
    ApplyColorTexture(checkbox.checkLeft, colors.accent[1], colors.accent[2], colors.accent[3], 0.7)
    checkbox.checkLeft:SetRotation(math.rad(-45))

    checkbox.checkRight = checkbox:CreateTexture(nil, "OVERLAY")
    ApplyColorTexture(checkbox.checkRight, colors.accent[1], colors.accent[2], colors.accent[3], 0.7)
    checkbox.checkRight:SetRotation(math.rad(45))

    local hovered = false
    local function UpdateVisual()
        if checked then
            checkbox.bg:SetVertexColor(colors.accent[1], colors.accent[2], colors.accent[3], 0.15)
            if hovered then
                UIKit.UpdateBorderLines(checkbox, 1, colors.accentHover[1], colors.accentHover[2], colors.accentHover[3], 1)
            else
                UIKit.UpdateBorderLines(checkbox, 1, colors.accent[1] * 0.8, colors.accent[2] * 0.8, colors.accent[3] * 0.8, 1)
            end
            checkbox.checkLeft:Show()
            checkbox.checkRight:Show()
        else
            checkbox.bg:SetVertexColor(colors.toggleOff[1], colors.toggleOff[2], colors.toggleOff[3], 1)
            if hovered then
                UIKit.UpdateBorderLines(checkbox, 1, 0.25, 0.28, 0.35, 1)
            else
                UIKit.UpdateBorderLines(checkbox, 1, 0.12, 0.14, 0.18, 1)
            end
            checkbox.checkLeft:Hide()
            checkbox.checkRight:Hide()
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
