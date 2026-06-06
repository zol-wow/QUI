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

-- UIKit.GetPixelSize is defined in the relocated skinning engine appended at the
-- end of this file (the superset (frame, default) signature from base.lua).

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

-- Shared edge-texture builder. Single implementation of "create the 4 edge
-- textures (top/bottom/left/right) on a frame at a given draw layer" used by
-- BOTH border paths:
--   * UIKit.CreateBorderLines       -> layer "OVERLAY", subLevel 7
--   * SkinBase EnsureManualBackdrop -> layer "BORDER"  (no subLevel)
-- It only unifies the CreateTexture calls + draw layer/subLevel; all anchoring,
-- sizing, color, snap, and scale-refresh registration stay in each caller, which
-- differ enough that forcing them together would risk a visual change.
-- `store` is the caller's own table; the 4 textures are written onto its
-- top/bottom/left/right keys (matching both existing storage models) and `store`
-- is returned.
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

---------------------------------------------------------------------------
-- SCALE-BOUND REGISTRY
---------------------------------------------------------------------------

function UIKit.RegisterScaleRefresh(owner, key, refreshFn)
    if not owner then return end
    -- Prefer the three-argument form with a stable string key. The
    -- two-argument compatibility form treats the callback itself as the key,
    -- so anonymous functions register as distinct callbacks.
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

function UIKit.RefreshPixelBorders()
    local failedBorderFrames
    for frame in pairs(borderLineState) do
        local ok = pcall(RefreshBorderLines, frame)
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

-- Coalesce the global border/scale resnap onto a short OnUpdate burst instead of
-- running a full registry walk synchronously on every call. CreateBorderLines
-- calls this once per bordered widget; doing the walk inline made each options
-- page build O(n^2) in bordered-widget count -- and re-touched every bordered
-- frame in the whole UI on each widget -- freezing the client while a settings
-- tab loaded. Each widget still snaps its OWN border synchronously inside
-- CreateBorderLines (RefreshBorderLines(frame)); only the global catch-up that
-- actual scale changes need is deferred a frame, which is imperceptible.
function UIKit.QueueScaleRefresh(ticks)
    ticks = max(Round(ticks or 1), 1)

    if type(CreateFrame) ~= "function" then
        -- No frame driver available (e.g. headless tooling): refresh inline.
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

---------------------------------------------------------------------------
-- QUI Skinning Base (relocated from modules/skinning/base.lua)
-- The skinning engine and the generic UI kit are ONE table. The block below
-- used to live in modules/skinning/base.lua and assigned onto its own
-- ns.SkinBase table; it now lands directly on the UIKit table via the
-- "local SkinBase = UIKit" alias so every function SkinBase.X defines a
-- UIKit method. Helpers/UIKit upvalues are reused from the top of this file.
---------------------------------------------------------------------------
local SkinBase = UIKit
-- Helpers.CHROME is always present in-game (core/utils.lua loads before this file
-- in core.xml). The `or {}` only matters for minimal headless harnesses that mock
-- ns.Helpers without CHROME; it never changes in-game values.
SkinBase.CHROME = Helpers.CHROME

-- Weak-keyed table to store backdrop references WITHOUT writing to Blizzard frames
-- All code that previously used frame.quiBackdrop should use SkinBase.GetBackdrop(frame) instead
local frameBackdrops = Helpers.CreateStateTable()
local manualBackdropData = Helpers.CreateStateTable()
local expandedPointData = Helpers.CreateStateTable()
local insetPointData = Helpers.CreateStateTable()
local customInsetPointData = Helpers.CreateStateTable()
local pixelPointData = Helpers.CreateStateTable()
local pixelBackdropData = Helpers.CreateStateTable()
local DEFAULT_BACKDROP_TEXTURE = "Interface\\Buttons\\WHITE8x8"

-- Shared color deltas for widget skinning (single source of truth — replaces
-- the magic numbers previously copy-pasted across frame skin files).
-- SkinBase.CHROME mirrors Helpers.CHROME (always present in-game); reading through
-- it keeps these upvalues defined even under CHROME-less headless harnesses.
local BG_BOOST_BUTTON = SkinBase.CHROME.BUTTON_BOOST
local BG_BOOST_ROW = SkinBase.CHROME.SCROLLROW_BOOST
local HOVER_BRIGHTEN = 1.3

---------------------------------------------------------------------------
-- GetPixelSize(frame, default)
-- Returns the pixel-perfect edge size for the given frame.
---------------------------------------------------------------------------
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

---------------------------------------------------------------------------
-- GetSkinColors()
-- Returns accent + background colors: sr, sg, sb, sa, bgr, bgg, bgb, bga
---------------------------------------------------------------------------
function SkinBase.GetSkinColors(moduleSettings, prefix)
    local sr, sg, sb, sa = Helpers.GetSkinBorderColor(moduleSettings, prefix)
    local bgr, bgg, bgb, bga = Helpers.GetSkinBgColorWithOverride(moduleSettings, prefix)
    return sr, sg, sb, sa, bgr, bgg, bgb, bga
end

function SkinBase.GetSkinBarColor(moduleSettings, prefix)
    return Helpers.GetSkinBarColor(moduleSettings, prefix)
end

-- Resolve a background-depth color for a tier (PANEL/SUBPANEL/ROW), expressed as
-- a boost+alpha on top of the themed skin bg. Replaces the ad-hoc per-module
-- "math.min(bgr + 0.0X, 1)" depth math so all panels layer consistently.
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

-- Shared chrome policy: one resolver for border/accent/background colors and
-- the canonical pixel-backdrop call. Frame files should pass frame-specific
-- wiring here instead of each cloning the color/default/backdrop branch.
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
    if not button then return end
    opts = opts or {}
    local key = opts.stateKey or "chromeCloseButton"
    HideButtonTextures(button)

    local palette = SkinBase.GetChromePalette(opts)
    local border = SkinBase.GetFrameData(button, key .. "Border")
    if not border then
        border = CreateFrame("Frame", nil, button, "BackdropTemplate")
        border:EnableMouse(false)
        SkinBase.SetFrameData(button, key .. "Border", border)
    end
    SkinBase.SetInsetPixelPoints(border, button, opts.insetPixels or 2)
    border:SetFrameLevel(math.max(button:GetFrameLevel() - 1, 1))
    SkinBase.ApplyChromeBackdrop(border, {
        palette = palette,
        withBackground = true,
        withInsets = true,
        borderColor = palette.border,
        bgColor = palette.bg,
    })

    local label = SkinBase.GetFrameData(button, key .. "Label")
    if not label then
        label = button:CreateFontString(nil, "OVERLAY")
        label:SetPoint("CENTER", button, "CENTER", 0, 0)
        if label.SetDrawLayer then
            label:SetDrawLayer("OVERLAY", 7)
        end
        SkinBase.SetFrameData(button, key .. "Label", label)
    end
    label:SetFont(opts.font or STANDARD_TEXT_FONT, opts.fontSize or 11, opts.fontFlags or "OUTLINE")
    label:SetText(opts.label or "X")
    local textColor = ResolveChromeColor(opts.textColor, { 1, 1, 1, 1 }, 1)
    label:SetTextColor(textColor[1], textColor[2], textColor[3], textColor[4])

    if SkinBase.GetFrameData(button, key .. "Hooked") then return end
    button:HookScript("OnEnter", function(self)
        local bd = SkinBase.GetFrameData(self, key .. "Border")
        if not bd then return end
        local hoverPalette = SkinBase.GetChromePalette(opts)
        bd:SetBackdropBorderColor(hoverPalette.accent[1], hoverPalette.accent[2], hoverPalette.accent[3], hoverPalette.accent[4])
    end)
    button:HookScript("OnLeave", function(self)
        local bd = SkinBase.GetFrameData(self, key .. "Border")
        if not bd then return end
        local restPalette = SkinBase.GetChromePalette(opts)
        bd:SetBackdropBorderColor(restPalette.border[1], restPalette.border[2], restPalette.border[3], restPalette.border[4])
    end)
    SkinBase.SetFrameData(button, key .. "Hooked", true)
end

local function TooltipTextHasPrintfPlaceholder(text)
    if type(text) ~= "string" then return false end
    if Helpers.IsSecretValue and Helpers.IsSecretValue(text) then return false end

    local withoutLiteralPercents = text:gsub("%%%%", "")
    return withoutLiteralPercents:find("%%[-+0#%d%.$]*[AacdeEfgGioqsuxX]") ~= nil
end

local function SanitizeSecretRestrictedTooltipText(text)
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
        if Helpers.IsSecretValue(value) then return nil end
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
            pcall(richBuilder, row, self)
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
            -- Same treatment ApplyColorTexture gives the border-line path: with
            -- the engine's default texel snapping bias, a 1-physical-pixel solid
            -- quad rasterizes to nothing at certain fractional screen offsets
            -- (CharacterFrame close-button border vanished on the Rep/Currency
            -- tabs purely because the button sits at a different screen position
            -- there). Re-apply after every SetColorTexture.
            UIKit.DisablePixelSnap(texture)
        else
            -- File-based (LSM) edges keep engine-default snapping on purpose.
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
    local px = Helpers.SafeToNumber(edgeSize, 1)
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

    -- Do NOT show the frame here. Building the backdrop must not change the
    -- frame's visibility — that is the caller's concern. This runs on every
    -- scale refresh (RefreshPixelBackdrop), so forcing :Show() here re-revealed
    -- intentionally-hidden frames (the loot window, the alert/toast/bnet movers)
    -- at login when the scale-refresh pass fires.
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

    -- One render path (#3): always build the manual 4-texture backdrop. Works on
    -- any frame and is more taint-safe than SetBackdrop on Blizzard frames.
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

---------------------------------------------------------------------------
-- CreateBackdrop(frame, sr, sg, sb, sa, bgr, bgg, bgb, bga)
-- Creates (or updates) a pixel-perfect QUI backdrop on the given frame.
-- Stores the backdrop in a local weak-keyed table (NOT on the frame itself)
-- to avoid tainting Blizzard frames in Midnight's taint model.
-- Use SkinBase.GetBackdrop(frame) to retrieve the backdrop.
---------------------------------------------------------------------------
function SkinBase.CreateBackdrop(frame, sr, sg, sb, sa, bgr, bgg, bgb, bga)
    if not frameBackdrops[frame] then
        local backdrop = CreateFrame("Frame", nil, frame)
        backdrop:SetAllPoints()
        backdrop:SetFrameLevel(frame:GetFrameLevel())
        backdrop:EnableMouse(false)
        frameBackdrops[frame] = backdrop
    end

    local backdrop = frameBackdrops[frame]
    -- Store backup color fields so third-party frame cleanup recognizes this
    -- as a QUI-owned frame and skips it during orphan/NineSlice suppression.
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

---------------------------------------------------------------------------
-- ApplyFullBackdrop(frame, sr, sg, sb, sa, bgr, bgg, bgb, bga)
-- Applies a pixel-perfect backdrop directly to a BackdropTemplate frame.
-- Unlike CreateBackdrop, this sets the backdrop on the frame itself
-- (for frames that already have BackdropTemplate or are addon-owned).
---------------------------------------------------------------------------
function SkinBase.ApplyFullBackdrop(frame, sr, sg, sb, sa, bgr, bgg, bgb, bga)
    if not frame then return end
    -- Store backup color fields so third-party frame cleanup recognizes this
    -- as a QUI-owned frame and skips it during orphan/NineSlice suppression.
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

---------------------------------------------------------------------------
-- GetBackdrop(frame)
-- Returns the QUI backdrop for a frame, or nil if none exists.
---------------------------------------------------------------------------
function SkinBase.GetBackdrop(frame)
    return frameBackdrops[frame]
end

---------------------------------------------------------------------------
-- RefreshFrameBackdropColors(frame)
-- Re-apply the current skin colors to a previously-skinned frame's QUI
-- backdrop. Single source of truth for the per-frame skin refreshers
-- (social/journals/interaction and any future frame skins).
---------------------------------------------------------------------------
function SkinBase.RefreshFrameBackdropColors(frame)
    if not frame then return end
    local bd = SkinBase.GetBackdrop(frame)
    if not bd then return end
    local sr, sg, sb, sa, bgr, bgg, bgb, bga = SkinBase.GetSkinColors()
    bd:SetBackdropColor(bgr, bgg, bgb, bga)
    bd:SetBackdropBorderColor(sr, sg, sb, sa)
end

---------------------------------------------------------------------------
-- Skinning state tracking (shared across all skinning modules)
-- Replaces frame.quiSkinned / frame.quiStyled / frame.quiBackdrop writes
-- which taint Blizzard frames in Midnight's taint model.
---------------------------------------------------------------------------
local skinnedFrames = Helpers.CreateStateTable()
local styledFrames = Helpers.CreateStateTable()

-- Mark a frame as skinned (replaces frame.quiSkinned = true)
function SkinBase.MarkSkinned(frame)
    skinnedFrames[frame] = true
end

-- Check if a frame has been skinned (replaces frame.quiSkinned check)
function SkinBase.IsSkinned(frame)
    return skinnedFrames[frame]
end

-- Mark a frame as styled (replaces frame.quiStyled = true)
function SkinBase.MarkStyled(frame)
    styledFrames[frame] = true
end

-- Check if a frame has been styled (replaces frame.quiStyled check)
function SkinBase.IsStyled(frame)
    return styledFrames[frame]
end

-- Store arbitrary per-frame data (replaces frame.quiXxx = value)
local frameData, getFrameData = Helpers.CreateStateTable()

function SkinBase.SetFrameData(frame, key, value)
    getFrameData(frame)[key] = value
end

function SkinBase.GetFrameData(frame, key)
    local data = frameData[frame]
    return data and data[key]
end

---------------------------------------------------------------------------
-- StripTextures(frame)
-- Hides all Texture regions on a frame (alpha → 0).
---------------------------------------------------------------------------
function SkinBase.StripTextures(frame)
    if not frame then return end
    for i = 1, frame:GetNumRegions() do
        local region = select(i, frame:GetRegions())
        if region and region:IsObjectType("Texture") then
            region:SetAlpha(0)
        end
    end
end

---------------------------------------------------------------------------
-- HidePortraitFrameChrome(frame)
-- Hides every standard chrome region exposed by PortraitFrameTemplate
-- and ButtonFrameTemplate (and their NoCloseButton / Minimizable / Flat
-- variants).
--
-- Template inheritance per Blizzard_SharedXML/Mainline/SharedUIPanelTemplates.xml:
--   PortraitFrameBaseTemplate
--     ├── .NineSlice            (NineSlicePanelTemplate)
--     ├── .PortraitContainer    (portrait + CircleMask)
--     └── .TitleContainer       (TitleText, sometimes .TitleBg)
--   PortraitFrameTexturedBaseTemplate ← .Bg + .TopTileStreaks
--   ButtonFrameBaseTemplate           ← .Bg + .TopTileStreaks + .CloseButton
--   ButtonFrameTemplate               ← .Inset (InsetFrameTemplate)
--
-- `TopTileStreaks` is the diagonal-streak band across the top — easy to
-- miss because it draws at BORDER subLevel and only matters when the
-- other chrome is hidden. Calling this helper is the single source of
-- truth for "remove the Blizzard panel chrome on this frame".
---------------------------------------------------------------------------
function SkinBase.HidePortraitFrameChrome(frame)
    if not frame then return end

    -- PortraitFrame / ButtonFrame template regions.
    if frame.NineSlice then frame.NineSlice:Hide() end
    if frame.Bg then frame.Bg:Hide() end
    if frame.TopTileStreaks then frame.TopTileStreaks:Hide() end
    if frame.PortraitContainer then frame.PortraitContainer:Hide() end
    if frame.TitleContainer and frame.TitleContainer.TitleBg then
        frame.TitleContainer.TitleBg:Hide()
    end

    -- BasicFrameTemplate regions (per Blizzard_UIPanelTemplates/
    -- UIPanelTemplates.xml:550-636 — 8 corner/edge textures + TitleBg).
    -- BasicFrameTemplate is structurally distinct from PortraitFrameTemplate:
    -- no NineSlice, no TopTileStreaks. Used by GuildBank and several other
    -- secondary frames. Hiding both region sets is safe — :Hide() no-ops on
    -- missing regions and the names don't collide.
    if frame.TopLeftCorner then frame.TopLeftCorner:Hide() end
    if frame.TopRightCorner then frame.TopRightCorner:Hide() end
    if frame.BotLeftCorner then frame.BotLeftCorner:Hide() end
    if frame.BotRightCorner then frame.BotRightCorner:Hide() end
    if frame.TopBorder then frame.TopBorder:Hide() end
    if frame.BottomBorder then frame.BottomBorder:Hide() end
    if frame.LeftBorder then frame.LeftBorder:Hide() end
    if frame.RightBorder then frame.RightBorder:Hide() end
    if frame.TitleBg then frame.TitleBg:Hide() end

    -- Legacy/derived names that several Blizzard frames still expose.
    if frame.Background then frame.Background:Hide() end
    if frame.portrait then frame.portrait:Hide() end

    -- ButtonFrameTemplate adds an Inset child with its own NineSlice/Bg.
    if frame.Inset then
        if frame.Inset.NineSlice then frame.Inset.NineSlice:Hide() end
        if frame.Inset.Bg then frame.Inset.Bg:Hide() end
    end
end

---------------------------------------------------------------------------
-- SkinCloseButton(closeButton)
-- Hides the Blizzard X chrome on a UIPanelCloseButton (or any of its
-- descendants: UIPanelCloseButtonDefaultAnchors, UIPanelCloseButtonNoScripts —
-- see Blizzard_SharedXML/Mainline/SharedUIPanelTemplates.xml:148-153) and
-- replaces it with a QUI accent backdrop + "×" label + hover hooks.
--
-- The Blizzard X graphic draws via the 4 button states
-- (Normal/Pushed/Highlight/Disabled), so hiding only .Border (a common
-- prior-art mistake — see commit ec36a542) leaves the X visible. This
-- helper hides all 5 layers.
--
-- Theme-aware: colors come from SkinBase.GetSkinColors() so live theme
-- changes propagate through OnEnter/OnLeave (which re-query on each fire).
--
-- Idempotent — flagged via SetFrameData(button, "closeStyled").
---------------------------------------------------------------------------
function SkinBase.SkinCloseButton(closeButton)
    if not closeButton or SkinBase.GetFrameData(closeButton, "closeStyled") then
        return
    end

    if closeButton.Border then closeButton.Border:SetAlpha(0) end
    if closeButton.GetNormalTexture and closeButton:GetNormalTexture() then
        closeButton:GetNormalTexture():SetAlpha(0)
    end
    if closeButton.GetPushedTexture and closeButton:GetPushedTexture() then
        closeButton:GetPushedTexture():SetAlpha(0)
    end
    if closeButton.GetHighlightTexture and closeButton:GetHighlightTexture() then
        closeButton:GetHighlightTexture():SetAlpha(0)
    end
    if closeButton.GetDisabledTexture and closeButton:GetDisabledTexture() then
        closeButton:GetDisabledTexture():SetAlpha(0)
    end

    local sr, sg, sb, sa, bgr, bgg, bgb, bga = SkinBase.GetSkinColors()
    SkinBase.CreateBackdrop(closeButton, sr, sg, sb, sa, bgr, bgg, bgb, bga)

    local label = closeButton:CreateFontString(nil, "OVERLAY")
    label:SetPoint("CENTER")
    label:SetFont(STANDARD_TEXT_FONT, 14, "OUTLINE")
    label:SetText("\195\151") -- UTF-8 "×" (U+00D7 MULTIPLICATION SIGN)
    label:SetTextColor(1, 1, 1, 1)
    SkinBase.SetFrameData(closeButton, "closeLabel", label)

    closeButton:HookScript("OnEnter", function(self)
        local bd = SkinBase.GetBackdrop(self)
        if bd then
            local r, g, b, a = SkinBase.GetSkinColors()
            bd:SetBackdropBorderColor(math.min(r * 1.3, 1), math.min(g * 1.3, 1), math.min(b * 1.3, 1), a)
        end
    end)
    closeButton:HookScript("OnLeave", function(self)
        local bd = SkinBase.GetBackdrop(self)
        if bd then
            local r, g, b, a = SkinBase.GetSkinColors()
            bd:SetBackdropBorderColor(r, g, b, a)
        end
    end)

    SkinBase.SetFrameData(closeButton, "closeStyled", true)
end

---------------------------------------------------------------------------
-- Tab skinning — works for both PanelTabButtonTemplate (legacy global
-- FrameTab1..N pattern) and modern TabSystemTemplate tabs.
--
-- SkinTabButton(tab)              — visual base: strip Blizzard textures,
--                                    apply QUI backdrop with the conventional
--                                    bottom-merging tab inset, cache colors
--                                    for later RefreshTabSelected calls.
-- RefreshTabSelected(tab, owner)  — set the backdrop to selected vs
--                                    unselected colors based on tab state.
-- SkinTab(tab, owner, opts)       — skin one tab; opts.hover wires a
--                                    brighten-on-enter + selected-state
--                                    restore-on-leave (used for pooled tabs).
-- SkinTabGroup(tabs, owner, opts) — skin every tab + hook each OnClick to
--                                    refresh the group; also registers the
--                                    owner for programmatic-switch refresh
--                                    (PanelTemplates_SetTab / TabSystem:SetTab).
--                                    opts.hover applies SkinTab hover to all.
-- RefreshTabGroup(tabs, owner)    — theme refresh: re-store colors then
--                                    re-apply selected/unselected visuals.
--
-- For owner detection (IsTabSelected): tab.IsSelected is checked first, then
-- owner.TabSystem:GetSelectedTab() vs tab.tabID, then
-- PanelTemplates_GetSelectedTab(owner) vs tab:GetID(), then a
-- tab.SelectedTexture:IsShown() fallback. Owner can be nil if only the
-- IsSelected path applies.
---------------------------------------------------------------------------
-- Belt-and-suspenders texture nuke: SetAlpha(0) + Hide() + SetTexture("").
-- Used on Blizzard tab textures because PanelTemplates_SelectTab/DeselectTab
-- (SharedUIPanelTemplates.lua:505,523) Show()/Hide() the named tab textures
-- on every tab switch — we need them gone regardless of which path Blizzard
-- runs through, and atlas-backed textures sometimes ignore the SetAlpha alone.
local function NukeTexture(t)
    if not t then return end
    if t.SetAlpha then t:SetAlpha(0) end
    if t.SetTexture then pcall(t.SetTexture, t, "") end
    if t.Hide then t:Hide() end
end

-- PanelTabButtonTemplate's twelve named texture regions
-- (Blizzard_SharedXML/Mainline/SharedUIPanelTemplates.xml:905-960).
local PANEL_TAB_TEXTURES = {
    "Left", "Middle", "Right",
    "LeftActive", "MiddleActive", "RightActive",
    "LeftHighlight", "MiddleHighlight", "RightHighlight",
    "LeftDisabled", "MiddleDisabled", "RightDisabled",
}

-- Re-apply the global QUI font to a tab's label when the tab opted in via
-- opts.font. Blizzard re-applies a font OBJECT (face + color) on every
-- selection change, so this runs from RefreshTabSelected as well as on skin.
local function ReapplyTabFont(tab)
    if not SkinBase.GetFrameData(tab, "skinTabFont") then return end
    local fs = tab.Text or (tab.GetFontString and tab:GetFontString())
    SkinBase.SkinFontString(fs)
end

function SkinBase.SkinTabButton(tab, opts)
    if not tab or SkinBase.IsStyled(tab) then return end
    opts = opts or {}

    -- Nuke each PanelTabButtonTemplate texture by name (atlas-backed; Show()
    -- by Blizzard tab-state code wouldn't otherwise affect our alpha=0).
    for _, name in ipairs(PANEL_TAB_TEXTURES) do
        NukeTexture(tab[name])
    end
    -- Catch-all for non-PanelTab variants (FriendsFrameTabTemplate, etc.)
    -- that may have differently-named regions.
    SkinBase.StripTextures(tab)
    local highlight = tab.GetHighlightTexture and tab:GetHighlightTexture()
    NukeTexture(highlight)

    local sr, sg, sb, sa, bgr, bgg, bgb = SkinBase.GetSkinColors()
    SkinBase.CreateBackdrop(tab, sr, sg, sb, sa, bgr, bgg, bgb, 0.9)
    local bd = SkinBase.GetBackdrop(tab)
    if bd then
        SkinBase.SetPixelInsetPoints(bd, tab, 3, 3, 3, 0)
        -- Keep backdrop at the tab's own frame level so it renders behind
        -- the tab's ButtonText fontstring. (NukeTexture above already
        -- triple-strikes the Blizzard textures so we don't need to raise
        -- the backdrop above them.)
    end

    -- Tab text: by default leave it to Blizzard, which swaps font objects
    -- between GameFontNormalSmall (yellow/unselected) and GameFontHighlightSmall
    -- (white/selected) via PanelTemplates_SelectTab. Most QUI frames (e.g. the
    -- character pane) intentionally keep that. opts.font opts a caller in to the
    -- global QUI font + themed text instead; because Blizzard re-swaps the font
    -- object on selection change, RefreshTabSelected re-applies it (the backdrop
    -- still signals which tab is selected).
    if opts.font then
        SkinBase.SetFrameData(tab, "skinTabFont", true)
        ReapplyTabFont(tab)
    end

    SkinBase.SetFrameData(tab, "skinColor", { sr, sg, sb, sa })
    SkinBase.SetFrameData(tab, "bgColor",   { bgr, bgg, bgb })
    SkinBase.MarkStyled(tab)
end

local function IsTabSelected(tab, owner)
    if tab.IsSelected and tab:IsSelected() then return true end
    if owner then
        local tabSystem = owner.TabSystem
        if tabSystem and tabSystem.GetSelectedTab and tab.tabID then
            if tab.tabID == tabSystem:GetSelectedTab() then return true end
        end
        if PanelTemplates_GetSelectedTab and tab.GetID then
            local selected = PanelTemplates_GetSelectedTab(owner)
            if selected and tab:GetID() == selected then return true end
        end
    end
    if tab.SelectedTexture and tab.SelectedTexture.IsShown and tab.SelectedTexture:IsShown() then
        return true
    end
    return false
end

function SkinBase.RefreshTabSelected(tab, owner)
    -- Re-assert the QUI font first (Blizzard's selected/unselected font-object
    -- swap would otherwise revert opted-in tabs on every tab change).
    ReapplyTabFont(tab)

    local bd = SkinBase.GetBackdrop(tab)
    local sc = SkinBase.GetFrameData(tab, "skinColor")
    local bg = SkinBase.GetFrameData(tab, "bgColor")
    if not bd or not sc or not bg then return end

    if IsTabSelected(tab, owner) then
        bd:SetBackdropBorderColor(sc[1], sc[2], sc[3], sc[4])
        bd:SetBackdropColor(math.min(bg[1] + 0.10, 1), math.min(bg[2] + 0.10, 1), math.min(bg[3] + 0.10, 1), 1)
    else
        bd:SetBackdropBorderColor(sc[1] * 0.5, sc[2] * 0.5, sc[3] * 0.5, sc[4] * 0.6)
        bd:SetBackdropColor(bg[1], bg[2], bg[3], 0.7)
    end
end

-- Tab hover: brighten border on enter, restore selected-state coloring on
-- leave. The enter half mirrors the widget HoverEnter (defined later in the
-- file), but tabs need a selected-state-aware leave (RefreshTabSelected) rather
-- than the plain border reset, so this pair lives here as its own small unit.
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

-- Programmatic tab-switch dispatch: one global PanelTemplates_SetTab hook plus
-- a per-TabSystem SetTab hook, both dispatching to the owner's refresh closure.
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

-- SkinTab(tab, owner, opts) — skin one tab; opts.hover wires brighten-on-enter
-- with selected-state restore on leave. Use directly for pooled tabs.
function SkinBase.SkinTab(tab, owner, opts)
    if not tab then return end
    opts = opts or {}
    SkinBase.SkinTabButton(tab, opts)
    if opts.hover and not SkinBase.GetFrameData(tab, "qTabHoverHooked") then
        tab:HookScript("OnEnter", TabHoverEnter)
        tab:HookScript("OnLeave", function(self) SkinBase.RefreshTabSelected(self, owner) end)
        SkinBase.SetFrameData(tab, "qTabHoverHooked", true)
    end
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

-- RefreshTabGroup(tabs, owner) — theme refresh: re-store colors from
-- GetSkinColors() then re-apply selected/unselected visuals.
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

---------------------------------------------------------------------------
-- HookScrollBoxAcquired(scrollBox, callback)
-- Replaces the legacy `hooksecurefunc(scrollBox, "Update", …) +
-- C_Timer.After(0) + ForEachFrame` triad with the documented
-- `ScrollUtil.AddAcquiredFrameCallback` API (defined at
-- Blizzard_SharedXML/Shared/Scroll/ScrollUtil.lua:35).
--
-- The legacy pattern fires on every scroll Update — many times per second
-- during scrolling — and iterates every visible row each time. This helper
-- fires the callback exactly once per frame acquisition (first time the
-- frame is reused from the pool for a new piece of data), which is what
-- visual-only skinning needs.
--
-- TAINT SAFETY: Both the initial iterate-existing pass AND the per-
-- acquisition fire are deferred via C_Timer.After(0). The OnAcquiredFrame
-- callback fires synchronously from Blizzard's secure scroll context, and
-- creating Backdrop frames in that path can propagate taint. The defer
-- also gives Blizzard's initializer time to bind elementData to the row.
--
-- Idempotent — flagged via SetFrameData(scrollBox, "qScrollHooked").
---------------------------------------------------------------------------
function SkinBase.HookScrollBoxAcquired(scrollBox, callback)
    if not scrollBox or SkinBase.GetFrameData(scrollBox, "qScrollHooked") then return end
    if not ScrollUtil or not ScrollUtil.AddAcquiredFrameCallback then return end

    C_Timer.After(0, function()
        if scrollBox.ForEachFrame then
            pcall(scrollBox.ForEachFrame, scrollBox, callback)
        end
    end)

    ScrollUtil.AddAcquiredFrameCallback(scrollBox, function(_, frame)
        C_Timer.After(0, function()
            callback(frame)
        end)
    end, scrollBox)

    SkinBase.SetFrameData(scrollBox, "qScrollHooked", true)
end

---------------------------------------------------------------------------
-- OnAddOnLoaded(addonName, callback, delay)
-- Idempotent helper for the canonical Blizzard-frame init pattern:
--   1. If addonName is already loaded, fire callback (optionally after delay).
--   2. Otherwise register ADDON_LOADED and fire on match, then unregister.
--
-- Replaces ~12 lines of boilerplate per skin file that did the same
-- ADDON_LOADED dance. Works for both LOD addons (Blizzard_MailFrame etc.)
-- and the always-loaded ones (Blizzard_UIPanels_Game), since the
-- already-loaded short-circuit fires immediately.
---------------------------------------------------------------------------
function SkinBase.OnAddOnLoaded(addonName, callback, delay)
    delay = delay or 0
    local function fire()
        if delay > 0 then
            C_Timer.After(delay, callback)
        else
            callback()
        end
    end

    if C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded(addonName) then
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

---------------------------------------------------------------------------
-- Generic widget hover (accent-brighten border on enter, restore on leave).
-- Reads colors from SkinBase weak state so live theme changes propagate.
---------------------------------------------------------------------------
local function HoverEnter(self)
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

-- Hover that restores a custom state on leave (vs the plain border reset that
-- AttachHover/HoverLeave does). Used by selection-state widgets.
local function AttachHoverWithRestore(frame, restoreFn)
    frame:HookScript("OnEnter", HoverEnter)
    frame:HookScript("OnLeave", function(self) restoreFn(self) end)
end

---------------------------------------------------------------------------
-- SkinFontString(fontString, opts)
-- Apply the global QUI font (face + outline) and a themed text color to a
-- fontstring (or an EditBox / any object exposing SetFont). This is the single
-- source of truth for "make this label use the QUI font/color", mirroring the
-- peer convention in statustracking.lua (default near-white text).
--   opts.size    : size override (default: keep the fontstring's current size)
--   opts.outline : outline override (default: Helpers.GetGeneralFontOutline())
--   opts.color   : { r, g, b, a } text color (default: near-white 0.95)
-- No-ops on nil or objects without SetFont, so callers can pass optional fields
-- directly. Idempotent in effect (re-applying the same font/color is harmless),
-- which matters for labels Blizzard re-skins on state changes.
---------------------------------------------------------------------------
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
        -- GetFont() can report a non-positive/garbage height for a fontstring
        -- whose font never successfully applied (e.g. a label SetFont'd with a
        -- not-yet-loaded font at ADDON_LOADED). Feeding that back into SetFont
        -- errors ("Invalid fontHeight: ..., height must be > 0"), so only adopt
        -- the current size when it's actually valid. Same `size > 0` invariant
        -- as core/font_system.lua.
        local _, curSize = fontString:GetFont()
        if type(curSize) == "number" and curSize > 0 then
            size = curSize
        end
    end
    size = size or 12

    fontString:SetFont(font, size, outline)
    if opts.fontOnly then return end

    if fontString.SetTextColor then
        local c = opts.color
        if type(c) == "table" then
            fontString:SetTextColor(c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1)
        else
            fontString:SetTextColor(0.95, 0.95, 0.95, 1)
        end
    end
end

-- Walk a frame's fontstrings and apply the QUI font. Font is applied to EVERY
-- fontstring (family/outline only; current size preserved), color is preserved
-- unless opts.chrome is set (chrome labels take the themed/near-white color via
-- opts.color). Optionally recurses into child frames (opts.recurse) up to
-- opts.maxDepth (default 6) so nested Blizzard fontstrings are covered too.
function SkinBase.SkinFrameText(frame, opts)
    if not frame then return end
    opts = opts or {}
    local fontOpts = opts.chrome and { color = opts.color } or { fontOnly = true }

    if frame.GetRegions then
        for i = 1, select("#", frame:GetRegions()) do
            local region = select(i, frame:GetRegions())
            if region and region.GetObjectType and region:GetObjectType() == "FontString" then
                SkinBase.SkinFontString(region, fontOpts)
            end
        end
    end

    if opts.recurse and frame.GetChildren then
        local depth = opts.maxDepth or 6
        if depth > 0 then
            for i = 1, select("#", frame:GetChildren()) do
                local child = select(i, frame:GetChildren())
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

-- Resolve a frame's primary label fontstring (button text / editbox).
local function GetLabelFontString(frame)
    if not frame then return nil end
    if frame.GetFontString then
        local fs = frame:GetFontString()
        if fs then return fs end
    end
    return frame.Text
end

---------------------------------------------------------------------------
-- SkinButton(button, opts)
--   opts.strip   : StripTextures instead of hiding named Left/Right/Middle/
--                  Center (use for WowStyle1-style buttons).
--   opts.bgBoost : background lighten amount (default BG_BOOST_BUTTON).
--   opts.hover   : attach hover hooks (default true).
---------------------------------------------------------------------------
function SkinBase.SkinButton(button, opts)
    if not button or SkinBase.IsStyled(button) then return end
    opts = opts or {}
    local sr, sg, sb, sa, bgr, bgg, bgb = SkinBase.GetSkinColors()
    local boost = opts.bgBoost or BG_BOOST_BUTTON

    if opts.strip then
        SkinBase.StripTextures(button)
    else
        if button.Left then button.Left:SetAlpha(0) end
        if button.Right then button.Right:SetAlpha(0) end
        if button.Middle then button.Middle:SetAlpha(0) end
        if button.Center then button.Center:SetAlpha(0) end
    end
    local highlight = button.GetHighlightTexture and button:GetHighlightTexture()
    if highlight then highlight:SetAlpha(0) end
    local pushed = button.GetPushedTexture and button:GetPushedTexture()
    if pushed then pushed:SetAlpha(0) end
    local normal = button.GetNormalTexture and button:GetNormalTexture()
    if normal then normal:SetAlpha(0) end

    SkinBase.CreateBackdrop(button, sr, sg, sb, sa,
        math.min(bgr + boost, 1), math.min(bgg + boost, 1), math.min(bgb + boost, 1), 1)
    if opts.belowChildren then
        local bd = SkinBase.GetBackdrop(button)
        if bd then bd:SetFrameLevel(math.max(0, button:GetFrameLevel() - 1)) end
    end
    SkinBase.SetFrameData(button, "skinColor", { sr, sg, sb, sa })
    SkinBase.SetFrameData(button, "skinKind", "button")
    SkinBase.SetFrameData(button, "bgBoost", boost)
    -- opt-in: restyle the label with the global QUI font (default off so the
    -- many shared SkinButton callers keep Blizzard fonts unless they ask).
    -- Flagged so RefreshWidget re-applies it on live font/theme changes.
    if opts.font then
        SkinBase.SetFrameData(button, "skinFont", true)
        SkinBase.SetFrameData(button, "skinFontColor", opts.fontColor)
        SkinBase.SkinFontString(GetLabelFontString(button), { color = opts.fontColor })
    end
    if opts.hover ~= false then AttachHover(button) end
    SkinBase.MarkStyled(button)
end

---------------------------------------------------------------------------
-- SkinEditBox(editBox) — strip Blizzard textures + QUI backdrop (no boost).
---------------------------------------------------------------------------
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
    -- opt-in: restyle the input text with the global QUI font.
    if opts.font then
        SkinBase.SetFrameData(editBox, "skinFont", true)
        SkinBase.SetFrameData(editBox, "skinFontColor", opts.fontColor)
        SkinBase.SkinFontString(editBox, { color = opts.fontColor })
    end
    SkinBase.MarkStyled(editBox)
end

---------------------------------------------------------------------------
-- SkinScrollRow(row, opts)
--   opts.bgBoost        : default BG_BOOST_ROW
--   opts.borderAlphaMult: default 0.5
--   opts.bgAlpha        : default 0.6
--   opts.hover          : default true
---------------------------------------------------------------------------
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

---------------------------------------------------------------------------
-- Selection-state category list button (AH / crafting-orders category lists).
-- Selected -> ROW depth + full border; unselected -> dimmer. State is read from
-- the button's SelectedTexture visibility (kept for detection, alpha 0).
---------------------------------------------------------------------------
function SkinBase.RefreshCategorySelected(button)
    local bd = SkinBase.GetBackdrop(button)
    local sc = SkinBase.GetFrameData(button, "skinColor")
    if not bd or not sc then return end
    local selected = button.SelectedTexture and button.SelectedTexture:IsShown()
    if selected then
        bd:SetBackdropBorderColor(sc[1], sc[2], sc[3], sc[4])
        bd:SetBackdropColor(SkinBase.GetDepthColor("ROW"))
    else
        bd:SetBackdropBorderColor(sc[1], sc[2], sc[3], (sc[4] or 1) * 0.5)
        local r, g, b = SkinBase.GetDepthColor("ROW")
        bd:SetBackdropColor(r, g, b, 0.7)
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
    SkinBase.RefreshCategorySelected(button)
    AttachHoverWithRestore(button, SkinBase.RefreshCategorySelected)
    SkinBase.MarkStyled(button)
end

---------------------------------------------------------------------------
-- SkinDropdown(dropdown, opts)
--   opts.keepArrow     : hide NineSlice/NormalTexture/HighlightTexture but
--                        leave dropdown.Arrow visible.
--   opts.noStrip       : do NOT strip textures (preserves child controls such
--                        as a clear-filter "X").
--   opts.bgBoost       : default BG_BOOST_BUTTON.
--   opts.insetY        : inset the backdrop vertically by N px.
--   opts.belowChildren : backdrop frame level = max(0, dropdown level - 1).
--   opts.hover         : default true.
---------------------------------------------------------------------------
function SkinBase.SkinDropdown(dropdown, opts)
    if not dropdown or SkinBase.IsStyled(dropdown) then return end
    opts = opts or {}
    local sr, sg, sb, sa, bgr, bgg, bgb = SkinBase.GetSkinColors()
    local boost = opts.bgBoost or BG_BOOST_BUTTON

    if opts.noStrip then
        -- preserve all child textures
    elseif opts.keepArrow then
        if dropdown.NineSlice then dropdown.NineSlice:SetAlpha(0) end
        if dropdown.NormalTexture then dropdown.NormalTexture:SetAlpha(0) end
        if dropdown.HighlightTexture then dropdown.HighlightTexture:SetAlpha(0) end
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
    if opts.hover ~= false then AttachHover(dropdown) end
    SkinBase.MarkStyled(dropdown)
end

---------------------------------------------------------------------------
-- SkinListContainer(list, rowStyler)
-- Hide NineSlice/Background, strip textures, hide the scrollbar background,
-- and style pooled rows via HookScrollBoxAcquired.
---------------------------------------------------------------------------
function SkinBase.SkinListContainer(list, rowStyler)
    if not list or SkinBase.IsStyled(list) then return end
    if list.NineSlice then list.NineSlice:Hide() end
    if list.BackgroundNineSlice then list.BackgroundNineSlice:Hide() end
    if list.Background and list.Background.SetAlpha then list.Background:SetAlpha(0) end
    SkinBase.StripTextures(list)
    if list.ScrollBox and rowStyler then
        SkinBase.HookScrollBoxAcquired(list.ScrollBox, rowStyler)
    end
    if list.ScrollBar and list.ScrollBar.Background then
        list.ScrollBar.Background:Hide()
    end
    SkinBase.MarkStyled(list)
end

---------------------------------------------------------------------------
-- RefreshWidget(frame) — re-derive colors from GetSkinColors() by skinKind,
-- re-apply to the QUI backdrop, and refresh stored "skinColor" so a later
-- hover uses the new colors. Handles button/dropdown/editbox/row. Tabs are
-- refreshed via RefreshTabGroup (they need owner context).
---------------------------------------------------------------------------
function SkinBase.RefreshWidget(frame)
    if not frame then return end
    local bd = SkinBase.GetBackdrop(frame)
    if not bd then return end
    local kind = SkinBase.GetFrameData(frame, "skinKind")
    if not kind then return end
    local sr, sg, sb, sa, bgr, bgg, bgb, bga = SkinBase.GetSkinColors()

    if kind == "button" or kind == "dropdown" then
        local boost = SkinBase.GetFrameData(frame, "bgBoost") or BG_BOOST_BUTTON
        bd:SetBackdropColor(math.min(bgr + boost, 1), math.min(bgg + boost, 1), math.min(bgb + boost, 1), 1)
        bd:SetBackdropBorderColor(sr, sg, sb, sa)
        SkinBase.SetFrameData(frame, "skinColor", { sr, sg, sb, sa })
        if kind == "dropdown" then
            SkinBase.SetFrameData(frame, "bgColor", { bgr, bgg, bgb })
        end
    elseif kind == "editbox" then
        bd:SetBackdropColor(bgr, bgg, bgb, bga)
        bd:SetBackdropBorderColor(sr, sg, sb, sa)
        SkinBase.SetFrameData(frame, "skinColor", { sr, sg, sb, sa })
    elseif kind == "row" then
        local boost = SkinBase.GetFrameData(frame, "bgBoost") or BG_BOOST_ROW
        local bgAlpha = SkinBase.GetFrameData(frame, "bgAlpha") or 0.6
        local mult = SkinBase.GetFrameData(frame, "borderAlphaMult") or 0.5
        bd:SetBackdropColor(math.min(bgr + boost, 1), math.min(bgg + boost, 1), math.min(bgb + boost, 1), bgAlpha)
        bd:SetBackdropBorderColor(sr, sg, sb, sa * mult)
        SkinBase.SetFrameData(frame, "skinColor", { sr, sg, sb, sa * mult })
    end

    -- Re-apply the global QUI font on live font/theme changes for widgets that
    -- opted in at skin time (SkinButton/SkinEditBox {font=true}).
    if SkinBase.GetFrameData(frame, "skinFont") then
        local color = SkinBase.GetFrameData(frame, "skinFontColor")
        local target = (kind == "editbox") and frame or GetLabelFontString(frame)
        SkinBase.SkinFontString(target, { color = color })
    end
end

---------------------------------------------------------------------------
-- SkinButtonFrameTemplate(frame)
-- One-call skinner for any frame that inherits PortraitFrameTemplate /
-- PortraitFrameTemplateNoCloseButton / ButtonFrameTemplate (or their
-- minimizable / flat variants). Composes the three primitive helpers:
--
--   1. HidePortraitFrameChrome — strip NineSlice, Bg, TopTileStreaks, etc.
--   2. CreateBackdrop          — apply the QUI accent backdrop using the
--                                current skin colors. Theme changes flow
--                                through because SkinBase.GetSkinColors() is
--                                queried at call time.
--   3. SkinCloseButton          — restyle frame.CloseButton if present.
--
-- This helper does NOT skin tabs, scroll regions, sub-panels, money frames,
-- or model-frame borders — those remain file-specific. It is the minimum
-- viable "make this frame look like QUI" call, intended for the ~17 daily-
-- use frames identified by the round-2 audit (Bank, Mail, Merchant,
-- GuildBank, Achievement, SpellBook, MacroFrame, ItemSocketing, etc.)
-- whose template inheritance gives them this shared chrome.
---------------------------------------------------------------------------
function SkinBase.SkinButtonFrameTemplate(frame)
    if not frame then return end
    SkinBase.HidePortraitFrameChrome(frame)
    local sr, sg, sb, sa, bgr, bgg, bgb, bga = SkinBase.GetSkinColors()
    SkinBase.CreateBackdrop(frame, sr, sg, sb, sa, bgr, bgg, bgb, bga)
    if frame.CloseButton then
        SkinBase.SkinCloseButton(frame.CloseButton)
    end
end

-- Skinning engine and the generic UI kit are one table; SkinBase is the
-- historical name used by skinning modules, UIKit by core/options.
ns.SkinBase = UIKit
