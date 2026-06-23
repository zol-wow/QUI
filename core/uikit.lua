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

local function ApplyBorderLineColor(edges, color)
    if not edges or not color then return end
    local r, g, b, a = color[1], color[2], color[3], color[4] or 1
    for _, line in pairs(edges) do
        ApplyColorTexture(line, r, g, b, a)
    end
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
        CJKFont(text, path, fontSize, outline)
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
    -- UI-CheckBox-Check is naturally drawn ~40% bigger than the box; size/center
    -- handled by RefreshAccentCheckboxLayout below (pixel-perfect).
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
-- BUTTONS
---------------------------------------------------------------------------

-- Shared fallback palette for buttons (only used if QUI.GUI.Colors is somehow
-- unavailable; in practice core/gui_shell.lua always defines it before any
-- button is created). Mirrors the gui_shell defaults.
local BUTTON_FALLBACK_COLORS = {
    accent = { 0.204, 0.827, 0.6, 1 },
    text = { 1, 1, 1, 1 },
    textDim = { 1, 1, 1, 0.6 },
}

--- Canonical themed push/ghost button. Reads the LIVE central palette
--- (QUI.GUI.Colors, defined in core/gui_shell.lua and mutated in place by
--- GUI:ApplyAccentColor — so a theme change recolors on the next hover) and the
--- central font path (GUI:GetFontPath). QUI_Options' GUI:CreateButton delegates
--- here; new call sites should use this directly.
--- @param parent Frame
--- @param opts table { text, width, height, onClick, variant="ghost"|"primary", fontSize }
--- @return Button
function UIKit.CreateButton(parent, opts)
    opts = opts or {}
    local gui = QUI and QUI.GUI
    local C = (gui and gui.Colors) or BUTTON_FALLBACK_COLORS
    -- Optional palette override (opts.colors = { text, textDim, accent }) lets callers
    -- with a distinct palette (e.g. the chat module, which intentionally diverges from
    -- the options palette) route through this central factory instead of re-rolling.
    local override = opts.colors
    -- Text colors: override > live palette > fallback. Accent resolves at use-time via
    -- accentRGB() (override accent, else UIKit.GetAccentColor — correct before Options
    -- seeds GUI.Colors.accent, e.g. login-time windows).
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

    if not button._pixelBorderReady then
        UIKit.CreateBorderLines(button)
        button._pixelBorderReady = true
    end

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

    -- Public method for callers that need custom border colors.
    function button:SetBorderColor(r, g, b, a)
        UIKit.UpdateBorderLines(self, 1, r, g, b, a or 1, false)
    end

    -- Backward-compatible alias used by some option tabs.
    button.SetFieldBorderColor = button.SetBorderColor

    return button
end

--- Resolve the user's theme accent (r, g, b). GUI.Colors.accent is only seeded
--- with the user's preset once the Options panel first opens, so resolve the
--- saved preset directly when possible (this is what window.lua / full_surface /
--- pins_ui each hand-roll). Falls back to the live palette, then a sane default.
--- @return number, number, number
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

--- Themed close ("X") button: line-drawn X over a pixel-bordered chip, accent on
--- hover. Reads the central border palette + central accent resolver. Replaces the
--- line-drawn-X close buttons hand-rolled across the suite (settings-window style).
--- @param parent Frame
--- @param opts table { size=22, onClick, lineLen=10, lineWidth=1.5, point, relativeTo, relativePoint, x, y }
--- @return Button
function UIKit.CreateCloseButton(parent, opts)
    opts = opts or {}
    local gui = QUI and QUI.GUI
    local C = (gui and gui.Colors) or BUTTON_FALLBACK_COLORS
    local size = opts.size or 22
    local lineLen = opts.lineLen or 10
    local lineWidth = opts.lineWidth or 1.5

    local function borderRGBA()
        local b = C.border or { 1, 1, 1, 0.06 }
        return b[1], b[2], b[3], b[4] or 1
    end

    local close = CreateFrame("Button", nil, parent)
    close:SetSize(size, size)
    if opts.point then
        close:SetPoint(opts.point, opts.relativeTo or parent, opts.relativePoint or opts.point, opts.x or 0, opts.y or 0)
    end

    close._bg = UIKit.CreateBackground(close, 0.08, 0.08, 0.08, 0.6)
    UIKit.CreateBorderLines(close)
    UIKit.UpdateBorderLines(close, 1, borderRGBA())

    local xLine1 = close:CreateTexture(nil, "OVERLAY")
    xLine1:SetSize(lineLen, lineWidth)
    xLine1:SetPoint("CENTER")
    -- Thin (1.5px) rotated solid quads rasterize away at fractional screen
    -- offsets unless pixel-snap is disabled after every SetColorTexture; route
    -- through ApplyColorTexture (mirrors CreateChevronCaret / manual edges).
    ApplyColorTexture(xLine1, 1, 1, 1, 0.8)
    xLine1:SetRotation(math.rad(45))
    local xLine2 = close:CreateTexture(nil, "OVERLAY")
    xLine2:SetSize(lineLen, lineWidth)
    xLine2:SetPoint("CENTER")
    ApplyColorTexture(xLine2, 1, 1, 1, 0.8)
    xLine2:SetRotation(math.rad(-45))
    close._xLine1, close._xLine2 = xLine1, xLine2

    if opts.onClick then close:SetScript("OnClick", opts.onClick) end
    close:SetScript("OnEnter", function(self)
        local ar, ag, ab = UIKit.GetAccentColor()
        UIKit.UpdateBorderLines(self, 1, ar, ag, ab, 1)
        self._bg:SetVertexColor(ar, ag, ab, 0.15)
        ApplyColorTexture(xLine1, ar, ag, ab, 1)
        ApplyColorTexture(xLine2, ar, ag, ab, 1)
    end)
    close:SetScript("OnLeave", function(self)
        UIKit.UpdateBorderLines(self, 1, borderRGBA())
        self._bg:SetVertexColor(0.08, 0.08, 0.08, 0.6)
        ApplyColorTexture(xLine1, 1, 1, 1, 0.8)
        ApplyColorTexture(xLine2, 1, 1, 1, 0.8)
    end)

    return close
end

--- Clickable icon button: a child icon (texture / atlas / player portrait) with hover
--- feedback + GameTooltip + onClick. Covers the minimap icon-button idiom (vertex-color
--- brighten: idle 0.85 → hover 1 → mousedown 0.72) and the micro-menu idiom (a square
--- highlight texture, or a -Up/-Down/-Mouseover atlas triplet on the button itself).
--- @param parent Frame
--- @param opts table {
---   size, name,
---   icon | atlas | portrait,        -- icon source
---   atlasTriplet,                   -- atlas base; sets Normal/Pushed/Highlight "-Up"/"-Down"/"-Mouseover"
---   squareHighlight,                -- bool: ButtonHilight-Square (ADD) instead of vertex brighten
---   idleAlpha = 0.85,
---   tooltip,                        -- string OR function(self) building GameTooltip lines
---   tooltipAnchor = "ANCHOR_RIGHT",
---   onClick, combatGuard,           -- combatGuard skips onClick in lockdown
---   onEnter, onLeave,               -- extra hooks run AFTER the built-in handlers
---   registerClicks = "LeftButtonUp" }
--- @return Button
function UIKit.CreateIconButton(parent, opts)
    opts = opts or {}
    local btn = CreateFrame("Button", opts.name, parent)
    btn:SetSize(opts.size or 18, opts.size or 18)
    btn:RegisterForClicks(opts.registerClicks or "LeftButtonUp")

    local idle = opts.idleAlpha or 0.85
    -- brighten applies only to a child icon texture we own (not to button-template art)
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

--- Themed tab button: a pixel-backdrop chip with an auto-sized label, an accent active
--- state and a dim inactive state, plus a faint-accent hover border. Uses the kit's
--- manual-texture backdrop (crash-safe inside UIPanelScrollFrameTemplate children, where
--- native SetBackdrop can stack-overflow). Call btn:SetActive(bool) to switch state.
--- @param parent Frame
--- @param opts table { label, minWidth=80, height=20, fontPath, fontSize, fontFlags, onClick, isActive }
--- @return Button  (with :SetActive(active) and ._label)
function UIKit.CreateTabButton(parent, opts)
    opts = opts or {}
    local btn = CreateFrame("Button", nil, parent)
    btn:SetHeight(opts.height or 20)

    btn._label = btn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    btn._label:SetPoint("CENTER")
    if opts.fontPath then CJKFont(btn._label, opts.fontPath, opts.fontSize or 12, opts.fontFlags or "") end
    btn._label:SetText(opts.label or "")
    btn:SetWidth(max(opts.minWidth or 80, (btn._label:GetStringWidth() or 0) + 24))

    -- Manual-texture backdrop so SetBackdropColor/SetBackdropBorderColor below route to
    -- the kit's manual setters (crash-safe; never calls native SetBackdrop).
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

-- Hover-brighten: single source of truth for the 1.3x lighten applied to
-- backdrop/border colors on mouse-over (close buttons, tab hover, group-finder
-- rows, ...). HOVER_BRIGHTEN was file-local and skin files open-coded `* 1.3`
-- (e.g. frames/instanceframes.lua AddSkinColorHoverBorder). HoverBrightenColor
-- multiplies r,g,b by the factor (default HOVER_BRIGHTEN), clamps to 1 and
-- passes alpha through, returning 4 values. Wrap in a table for SetBackdropColors:
--   SkinBase.SetBackdropColors(bd, { SkinBase.HoverBrightenColor(r, g, b, a) }, nil)
SkinBase.HOVER_BRIGHTEN = HOVER_BRIGHTEN
function SkinBase.HoverBrightenColor(r, g, b, a, factor)
    factor = factor or HOVER_BRIGHTEN
    return math.min((r or 0) * factor, 1), math.min((g or 0) * factor, 1), math.min((b or 0) * factor, 1), a
end

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
    -- Default to the SAME glyph + size as SkinCloseButton ("×" U+00D7 at 14) so
    -- every close button across QUI reads identically; callers no longer override.
    CJKFont(label, opts.font or STANDARD_TEXT_FONT, opts.fontSize or 14, opts.fontFlags or "OUTLINE")
    label:SetText(opts.label or "\195\151")
    local textColor = ResolveChromeColor(opts.textColor, { 1, 1, 1, 1 }, 1)
    label:SetTextColor(textColor[1], textColor[2], textColor[3], textColor[4])

    if SkinBase.GetFrameData(button, key .. "Hooked") then return end
    button:HookScript("OnEnter", function(self)
        local bd = SkinBase.GetFrameData(self, key .. "Border")
        if not bd then return end
        local hoverPalette = SkinBase.GetChromePalette(opts)
        -- Persist the accent tint so a scale refresh while hovered keeps it
        -- (the chrome border is an ApplyChromeBackdrop frame with seeded data.*).
        SkinBase.SetBackdropColors(bd, hoverPalette.accent, nil)
    end)
    button:HookScript("OnLeave", function(self)
        local bd = SkinBase.GetFrameData(self, key .. "Border")
        if not bd then return end
        local restPalette = SkinBase.GetChromePalette(opts)
        SkinBase.SetBackdropColors(bd, restPalette.border, nil)
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
    -- Sanctioned direct frame state exception: manual/pixel backdrops emulate
    -- BackdropTemplate's setters on QUI-owned backdrop frames/textures. The
    -- `_quiBg*` fields are the color cache those setters re-use during scale
    -- refreshes and theme refreshes; general skinning state still belongs in
    -- the weak side tables below.
    self._quiBgR, self._quiBgG, self._quiBgB, self._quiBgA = r, g, b, a
    local data = manualBackdropData[self]
    if data then
        SetTextureColor(data.bg, data.bgFile, r, g, b, a)
    end
end

local function ManualSetBackdropBorderColor(self, r, g, b, a)
    -- Same sanctioned backdrop exception as ManualSetBackdropColor: these
    -- `_quiBorder*` fields are render data for QUI-owned manual backdrops, not
    -- arbitrary module state on Blizzard frames.
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
-- SetBackdropColors(frame, borderColor, bgColor)
-- Live-recolor a frame already managed by ApplyPixelBackdrop / CreateBackdrop /
-- ApplyFullBackdrop (hover/selection/theme-refresh states).
--
-- This is the sanctioned replacement for a bare frame:SetBackdropColor /
-- frame:SetBackdropBorderColor on a managed backdrop. RefreshPixelBackdrop
-- rebuilds the backdrop from data.borderColor / data.bgColor on every scale
-- refresh, so a bare setter (which only touches the live textures) is silently
-- DISCARDED on the next rebuild — the "live recolor reverts on scale refresh"
-- bug class. SetBackdropColors updates the PERSISTED data and re-renders, so the
-- new color survives. The render path re-applies the colors through the manual
-- backdrop setters, which keeps the _quiBg*/_quiBorder* cache coherent.
--
--   borderColor / bgColor: {r,g,b,a} tables. Pass nil to leave that component
--   unchanged (e.g. a hover that only re-tints the border). For CreateBackdrop
--   frames, pass the child returned by SkinBase.GetBackdrop(frame).
---------------------------------------------------------------------------
function SkinBase.SetBackdropColors(frame, borderColor, bgColor)
    if not frame then return end
    local data = pixelBackdropData[frame]
    if not data then
        -- Not an ApplyPixelBackdrop-managed frame: fall back to the live setters
        -- so callers still get a visible recolor on a plain BackdropTemplate frame.
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
    -- Route through the persist helper: bd is a CreateBackdrop child whose
    -- pixelBackdropData.bgColor/.borderColor are seeded non-nil, so a bare
    -- bd:SetBackdropColor would be discarded on the next scale-refresh rebuild
    -- (RefreshPixelBackdrop prefers data.* over the _quiBg*/_quiBorder* fallback).
    SkinBase.SetBackdropColors(bd, { sr, sg, sb, sa }, { bgr, bgg, bgb, bga })
end

---------------------------------------------------------------------------
-- Skinning state tracking (shared across all skinning modules)
-- Replaces frame.quiSkinned / frame.quiStyled / frame.quiBackdrop writes
-- which taint Blizzard frames in Midnight's taint model.
--
-- Policy: module state lives in weak-keyed side tables, not on the frame. This
-- keeps Blizzard/protected frames free of QUI marker fields while still letting
-- us associate lifecycle flags, hooks, and cached setup data with pooled rows.
-- The deliberate exception is backdrop render state (`_quiBg*`/`_quiBorder*`)
-- on QUI-created backdrop frames or addon-owned manual backdrops. Those fields
-- mirror the BackdropTemplate setter contract and are needed by the sanctioned
-- SetBackdropColor/SetBackdropBorderColor replacement path above; do not use
-- them as a general-purpose state channel.
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

-- Store arbitrary per-frame data (replaces frame.quiXxx = value). Use this for
-- flags such as qListRowFonted/qScrollHooked so pooled Blizzard rows can be
-- re-used without adding new fields to those frames.
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

-- StripTexturesExcept(frame, preserve)
-- Like StripTextures, but skips any Texture region present as a key in the
-- `preserve` set (region -> true). Used where a frame's icon / overlay
-- textures must survive a blanket strip — e.g. equipment slots keep
-- icon + ItemContextOverlay + IconOverlay/2 + searchOverlay + IconQuestTexture.
-- Extracted from the byte-identical loops in character_pane/character.lua and
-- character_pane/inspect.lua. `preserve` may be nil (then identical to
-- StripTextures). Uses the boolean IsObjectType("Texture") predicate (matches
-- StripTextures) rather than GetObjectType()=="Texture": GetObjectType's return
-- is secret-aspect-tagged (SecretReturnsForAspect=ObjectType), so the string
-- compare can throw in a restricted context; IsObjectType resolves C-side.
function SkinBase.StripTexturesExcept(frame, preserve)
    if not frame or not frame.GetNumRegions then return end
    for i = 1, select("#", frame:GetRegions()) do
        local region = select(i, frame:GetRegions())
        if region and region.IsObjectType and region:IsObjectType("Texture") then
            if not (preserve and preserve[region]) then
                region:SetAlpha(0)
            end
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

    HideButtonTextures(closeButton)

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
            SkinBase.SetBackdropColors(bd, { math.min(r * 1.3, 1), math.min(g * 1.3, 1), math.min(b * 1.3, 1), a }, nil)
        end
    end)
    closeButton:HookScript("OnLeave", function(self)
        local bd = SkinBase.GetBackdrop(self)
        if bd then
            local r, g, b, a = SkinBase.GetSkinColors()
            SkinBase.SetBackdropColors(bd, { r, g, b, a }, nil)
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

-- ClampTextureHidden(tex)
-- Force a texture PERMANENTLY hidden against Blizzard re-assertion. The one-shot
-- NukeTexture (alpha 0 + clear + Hide) is defeated when Blizzard later re-shows
-- or re-alphas the region on a state change (tab selection, layout, MarkDirty,
-- pool re-Init) — the symptom is Blizzard tab/chrome art rendering back on top
-- of the QUI skin. The SetAlpha clamp (mirrors the GameMenu slice-art clamp in
-- system/gamemenu.lua) re-zeroes any alpha>0, so the region can never become
-- visible again. The clamp's own SetAlpha(0) re-fires the hook with a==0, which
-- the a>0 guard ignores — no recursion. Idempotent per texture.
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

-- ClampAllTextures(frame)
-- Catch-all: clamp every Texture region on a frame hidden (custom tab templates
-- expose extra state icons/glows beyond the named PanelTab regions). Skips
-- FontStrings, so tab labels are untouched. Run BEFORE CreateBackdrop so the
-- QUI backdrop (a child frame, not a region of this frame) is never matched.
function SkinBase.ClampAllTextures(frame)
    if not frame or not frame.GetNumRegions then return end
    for i = 1, frame:GetNumRegions() do
        local region = select(i, frame:GetRegions())
        if region and region.IsObjectType and region:IsObjectType("Texture") then
            SkinBase.ClampTextureHidden(region)
        end
    end
end

-- KillNineSlice(nineSlice, durable)
-- Canonical NineSlice texture killer. Clears every named NineSlice part
-- (corners/edges/center) plus every child Texture region, then hides the
-- frame. Replaces the hand-rolled copies in gameplay/objectivetracker.lua
-- (KillNineSlice) and character_pane/character.lua (HideNineSlice).
--
-- API SAFETY: never calls SetAtlas(nil). SimpleTextureBase:SetAtlas declares
-- its atlas arg Nilable=false (tests/api-docs/blizzard/SimpleTextureBaseAPI-
-- Documentation.lua:284) so a nil atlas is illegal; the prior hand-rolled
-- killers' SetAtlas(nil) was an API violation. SetTexture(nil) is the
-- sanctioned clear (textureAsset Nilable=true, same doc l.447) and drops any
-- atlas too. IsObjectType("Texture") guards region typing C-side.
--
-- When `durable` is true an OnShow re-hide is installed so a later Blizzard
-- re-Show of the NineSlice cannot bring its art back over the QUI skin
-- (mirrors the character.lua HideNineSlice Show-reassert). Idempotent per frame
-- via SetFrameData.
--
-- NOTE: system/tooltips.lua deliberately uses its OWN no-SetAlpha NineSlice
-- hider — SetAlpha on a tooltip NineSlice propagates secret values into
-- Blizzard layout (see that file). Do NOT route tooltips through this helper.
local NINE_SLICE_PARTS = {
    "TopLeftCorner", "TopRightCorner", "BottomLeftCorner", "BottomRightCorner",
    "TopEdge", "BottomEdge", "LeftEdge", "RightEdge", "Center",
}
function SkinBase.KillNineSlice(nineSlice, durable)
    if not nineSlice then return end

    if nineSlice.GetNumRegions then
        for i = 1, select("#", nineSlice:GetRegions()) do
            local region = select(i, nineSlice:GetRegions())
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
        -- Re-hide on any Blizzard re-Show. Hooking OnShow (not the Show method
        -- via hooksecurefunc) keeps this taint-free and only fires when the
        -- frame actually transitions to shown.
        nineSlice:HookScript("OnShow", function(self) self:Hide() end)
        SkinBase.SetFrameData(nineSlice, "qNineSliceKilled", true)
    end
end

-- PanelTabButtonTemplate's twelve named texture regions
-- (Blizzard_SharedXML/Mainline/SharedUIPanelTemplates.xml:905-960).
local PANEL_TAB_TEXTURES = {
    "Left", "Middle", "Right",
    "LeftActive", "MiddleActive", "RightActive",
    "LeftHighlight", "MiddleHighlight", "RightHighlight",
    "LeftDisabled", "MiddleDisabled", "RightDisabled",
}

-- Shared QUI tab-label font OBJECTS, cached by integer size. A direct SetFont
-- on the tab's fontstring does NOT survive: a tab is a Button and re-applies its
-- own font OBJECT on every state change — the HIGHLIGHT object on mouseover, the
-- NORMAL/DISABLED object on selection — clobbering any SetFont the instant you
-- hover or switch tabs. Driving the button's three font objects keeps the QUI
-- font across every state. (Same reason GameMenu drives button font objects —
-- see system/gamemenu.lua.) Caching by size lets each tab keep its native size.
-- Shared QUI button/tab font OBJECTS, cached by integer size + color. Returns a
-- Font object configured with the QUI font face/outline + the given color
-- (default near-white). nil when _G.CreateFont is unavailable (test harness) so
-- callers fall back to a direct fontstring SetFont.
-- Dim grey for disabled button labels (QUI face, but still reads as disabled).
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
        obj:SetFontObject(family)   -- inherits per-script CJK fallback
    else
        obj:SetFont(font, sizeKey, outline)
    end
    if type(color) == "table" then
        obj:SetTextColor(color[1] or 1, color[2] or 1, color[3] or 1, color[4] or 1)
    else
        obj:SetTextColor(0.95, 0.95, 0.95, 1)
    end
    return obj
end

-- ApplyButtonFontObjects(button, opts)
-- Drive a BUTTON's normal/highlight/disabled font objects to the QUI font so the
-- label keeps the QUI font across EVERY state. A direct SetFont on the
-- fontstring is clobbered the instant the button is hovered (HighlightFontObject)
-- or disabled (DisabledFontObject) — driving the objects is the only durable fix
-- (same lesson as system/gamemenu.lua). Used by tabs and by SkinButton{font}.
--   opts.size          : size override (default: label's current size)
--   opts.color         : normal/highlight text color (default near-white)
--   opts.disabledColor : disabled text color (default: opts.color — i.e. tabs
--                        stay readable; SkinButton passes a dim grey so disabled
--                        buttons still read as disabled)
-- nil-safe: without CreateFont, only the fontstring SetFont path runs.
function SkinBase.ApplyButtonFontObjects(button, opts)
    if not button then return end
    -- Button face follows the global font toggle (decoupled from skinning).
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
    -- Also set the fontstring directly (non-button tabs + CreateFont-less envs).
    if fs then
        SkinBase.SkinFontString(fs, type(opts.color) == "table" and { color = opts.color } or { fontOnly = true })
    end
end

-- Back-compat alias for the tab skinners.
SkinBase.ApplyTabFontObjects = SkinBase.ApplyButtonFontObjects

-- Re-apply the QUI tab font (self-guards on the skinTabFont flag). Runs on skin,
-- from RefreshTabSelected, and from the selection hooks below.
local function ReapplyTabFont(tab)
    if not SkinBase.GetFrameData(tab, "skinTabFont") then return end
    SkinBase.ApplyTabFontObjects(tab)
end

-- Re-assert the full QUI tab skin (art clamp + font) synchronously after a
-- selection change. Blizzard re-SHOWS the active/inactive slice textures on
-- selection (SetTabSelected / PanelTemplates_Select/DeselectTab) — re-clamping
-- here re-hides them so the default tab art never lands on top of the QUI
-- backdrop. Guarded on qTabArtClamped so the global PanelTemplates hooks only
-- ever touch QUI-skinned tabs.
local function ReassertTabSkin(tab)
    if not tab or not SkinBase.GetFrameData(tab, "qTabArtClamped") then return end
    SkinBase.ClampAllTextures(tab)
    local hl = tab.GetHighlightTexture and tab:GetHighlightTexture()
    if hl then SkinBase.ClampTextureHidden(hl) end
    ReapplyTabFont(tab)
end

-- Legacy PanelTab tabs re-show slice art and swap the font object via
-- PanelTemplates_Select/DeselectTab on every selection. Re-assert the QUI skin
-- synchronously after those global helpers. Installed once.
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
end

-- RegisterTabArtClamp(tab)
-- Opt a bespoke-skinned PanelTab (CharacterFrame / InspectFrame bottom tabs,
-- which don't route through SkinTabButton) into the synchronous selection
-- re-assert: flag it as QUI-clamped and ensure the global PanelTemplates hooks
-- are installed. Pair with ClampAllTextures + ApplyTabFontObjects at skin time.
function SkinBase.RegisterTabArtClamp(tab)
    if not tab then return end
    SkinBase.SetFrameData(tab, "qTabArtClamped", true)
    -- Bespoke callers drive QUI tab fonts via ApplyTabFontObjects; flag them so
    -- the global selection hook re-asserts the font synchronously too.
    SkinBase.SetFrameData(tab, "skinTabFont", true)
    HookPanelTabSkin()
end

function SkinBase.SkinTabButton(tab, opts)
    if not tab or SkinBase.IsStyled(tab) then return end
    opts = opts or {}

    -- Clamp every tab texture hidden. A one-shot alpha=0 is not enough: Blizzard
    -- re-asserts the tab art on selection/layout changes (SetTabSelected,
    -- PanelTemplates_Select/DeselectTab, MarkDirty), which would otherwise show
    -- the default tab art back on top of the QUI backdrop. ClampAllTextures
    -- installs a SetAlpha clamp on every Texture region (named PanelTab slices,
    -- *Active/*Highlight variants, and custom-template state icons/glows alike)
    -- and skips FontStrings, so the label is untouched. Runs before
    -- CreateBackdrop so the QUI backdrop child frame is never matched.
    SkinBase.ClampAllTextures(tab)
    local highlight = tab.GetHighlightTexture and tab:GetHighlightTexture()
    SkinBase.ClampTextureHidden(highlight)
    SkinBase.SetFrameData(tab, "qTabArtClamped", true)

    -- Re-clamp the art on every selection change. Blizzard re-SHOWS the active
    -- (selected) and inactive slice textures via SetTabSelected /
    -- PanelTemplates_Select/DeselectTab, so a one-shot clamp at skin time is
    -- defeated — the active-tab art lands back on top of the QUI backdrop.
    -- ReassertTabSkin (art + font) runs synchronously after each, no flash.
    if tab.SetTabSelected and not SkinBase.GetFrameData(tab, "qTabStateHooked") then
        hooksecurefunc(tab, "SetTabSelected", function(self) ReassertTabSkin(self) end)
        SkinBase.SetFrameData(tab, "qTabStateHooked", true)
    end
    HookPanelTabSkin()

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

    -- Tab text: apply the global QUI font + themed color by default. Blizzard
    -- swaps the tab font OBJECT on every selection change (modern TabSystem via
    -- SetNormalFontObject inside SetTabSelected; legacy via PanelTemplates_
    -- Select/DeselectTab — GameFontNormalSmall yellow ↔ GameFontHighlightSmall
    -- white), so the QUI font is re-asserted from those hooks and from
    -- RefreshTabSelected; the QUI backdrop signals which tab is selected.
    -- opts.font == false opts a caller out (keep Blizzard's tab font).
    -- QUI font on tab labels by default (opts.font == false opts out). The
    -- selection hooks installed above (SetTabSelected / PanelTemplates) re-assert
    -- it; here we apply the initial state. Hover never reverts because
    -- ApplyTabFontObjects drives the button's HIGHLIGHT font object too.
    if opts.font ~= false then
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
        -- Legacy PanelTemplates frames store the active index directly on the
        -- owner (PanelTemplates_GetSelectedTab merely returns owner.selectedTab);
        -- fall back to it so the verb resolves selection even where the global
        -- accessor is unavailable (and so CharacterFrame/InspectFrame, which the
        -- old per-frame forks read this way, keep working post-migration).
        if owner.selectedTab and tab.GetID and tab:GetID() == owner.selectedTab then
            return true
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

    local selected = IsTabSelected(tab, owner)
    local borderColor, bgColor
    if selected then
        borderColor = { sc[1], sc[2], sc[3], sc[4] }
        bgColor = { math.min(bg[1] + 0.10, 1), math.min(bg[2] + 0.10, 1), math.min(bg[3] + 0.10, 1), 1 }
    else
        borderColor = { sc[1] * 0.5, sc[2] * 0.5, sc[3] * 0.5, sc[4] * 0.6 }
        bgColor = { bg[1], bg[2], bg[3], 0.7 }
    end
    -- Persist the selection-state colors into the backdrop data via
    -- ApplyPixelBackdrop (same geometry CreateBackdrop used), so a scale refresh
    -- rebuilds with the selection tint instead of reverting to the base color. A
    -- bare SetBackdrop*Color updates only the live color, which RefreshPixelBackdrop
    -- discards on its next rebuild.
    SkinBase.ApplyPixelBackdrop(bd, 1, true, true, borderColor, bgColor)

    -- Selection-state LABEL color, promoted from the former per-frame tab forks
    -- (CharacterFrame/InspectFrame each carried a private copy) so EVERY tab strip
    -- now reads selected/unselected identically: bright label when active, dimmed
    -- when not. Runs after ReapplyTabFont (which drives the QUI font OBJECT) so this
    -- SetTextColor lands on top; the selection hooks re-call RefreshTabSelected so it
    -- survives Blizzard's per-state font-object swap. Gated on skinTabFont so tabs
    -- that opted out of the QUI font (opts.font == false) keep their native label.
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

-- CollectNumberedTabs(prefix, count) — gather the global frame tabs named
-- "<prefix>Tab1".."<prefix>TabN" into an array (skipping any that don't exist).
-- Shared by the per-frame skinners that feed SkinTabGroup (Merchant/GuildBank/Mail).
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
-- HookScrollBoxAcquired(scrollBox, callback, opts)
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
-- TAINT SAFETY: The initial iterate-existing pass is always deferred via
-- C_Timer.After(0). Per-acquisition callbacks are also deferred by default
-- because OnAcquiredFrame fires synchronously from Blizzard's secure scroll
-- context, and creating Backdrop frames in that path can propagate taint. The
-- defer also gives Blizzard's initializer time to bind elementData to the row.
--
-- opts.sync == true is the narrow opt-in for callbacks that only touch
-- per-instance FontStrings and must run before the pooled row's first paint.
-- Callback entries keep their own sync policy so mixed sync/deferred helpers
-- compose on the same ScrollBox.
--
-- Idempotent — flagged via SetFrameData(scrollBox, "qScrollHooked").
---------------------------------------------------------------------------
local scrollBoxAcquiredCallbacks = Helpers.CreateStateTable()

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
        if scrollBox.ForEachFrame then
            pcall(scrollBox.ForEachFrame, scrollBox, callback)
        end
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

---------------------------------------------------------------------------
-- HookScrollBoxRowFonts(scrollBox, depth)
-- Canonical "lock pooled-row fonts" for a ScrollBox. The recursive
-- SkinFrameText + LockFrameTextObjects pass is expensive, and LockFrameTextObjects
-- installs SetFontObject hooks that re-assert the QUI face on every later
-- Blizzard rebind (acquire / presence / state refresh) — so re-walking + re-
-- SetFont on EVERY acquire is wasted work, and the synchronous burst of font
-- realizations across a panel's ScrollBoxes on open is the open-window hitch.
-- Guard per row (qListRowFonted) so the expensive recursive pass runs ONCE; the
-- LockFontObject hooks cover every later revert. This is the single source of
-- truth for the pattern — callers MUST use it instead of an inline acquire
-- callback that re-skins per acquire, or the hitch comes back.
---------------------------------------------------------------------------
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
        -- LockPooledRowText owns SkinBase.SetFrameData(row, "qListRowFonted", true).
    end, { sync = true })
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
function SkinBase.IsAddOnFullyLoaded(addonName)
    if not C_AddOns or not C_AddOns.IsAddOnLoaded then return false end
    local loadedOrLoading, loaded = C_AddOns.IsAddOnLoaded(addonName)
    if loaded ~= nil then return loaded end
    return loadedOrLoading == true
end

function SkinBase.OnAddOnLoaded(addonName, callback, delay)
    delay = delay or 0
    local function fire()
        if delay > 0 then
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

---------------------------------------------------------------------------
-- Generic widget hover (accent-brighten border on enter, restore on leave).
-- Reads colors from SkinBase weak state so live theme changes propagate.
---------------------------------------------------------------------------
local function HoverEnter(self)
    local bd = SkinBase.GetBackdrop(self)
    local sc = SkinBase.GetFrameData(self, "skinColor")
    if bd and sc then
        -- Brighten the color AND drive the border to FULL alpha on hover (the resting
        -- border is dimmed, so keeping that alpha made the hover too subtle).
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

-- Public border-brighten toggle for rows whose OnEnter *script* never fires (so
-- AttachHover's HookScript can't catch hover) but whose mixin OnEnter *method*
-- does run — e.g. ProfessionsRecipeListRecipeMixin (Init/SkillUps call it directly).
-- Callers hooksecurefunc the mixin method and route the hover here, so the row's
-- backdrop border brightens exactly like the (working) crafting-orders rows.
function SkinBase.SetRowHovered(frame, hovered)
    if not frame then return end
    if hovered then HoverEnter(frame) else HoverLeave(frame) end
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

    CJKFont(fontString, font, size, outline)
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

-- Secret-Hierarchy / forbidden frames reject GetRegions()/GetChildren() in 12.0.7
-- (SecretReturnsForAspect = Hierarchy). pcall converts the reject into an empty
-- list instead of an error. Widget containers are skipped to avoid tainting their
-- FontStrings. Used by every recursive font walk below.
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

-- Walk a frame's fontstrings and apply the QUI font. Font is applied to EVERY
-- fontstring (family/outline only; current size preserved), color is preserved
-- unless opts.chrome is set (chrome labels take the themed/near-white color via
-- opts.color). Optionally recurses into child frames (opts.recurse) up to
-- opts.maxDepth (default 6) so nested Blizzard fontstrings are covered too.
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

---------------------------------------------------------------------------
-- LockFontObject(obj, opts)
-- Defeat the "theming re-assert" anti-pattern where a Blizzard frame swaps a
-- fontstring's (or button's) font OBJECT back to a default on interaction —
-- e.g. ProfessionsRecipeListCategoryMixin:OnEnter/OnLeave SetFontObject on
-- hover, or a ScrollBox row button's SetNormalFontObject on re-bind. A one-shot
-- SkinFontString is reverted by those swaps; this hooks the swap and re-applies
-- the QUI font right after.
--   * FontStrings/EditBoxes expose SetFontObject → re-apply to the object itself.
--   * Buttons expose Set*FontObject state setters → re-apply to button:GetFontString().
-- The re-apply uses SkinFontString's SetFont (never SetFontObject), so it does
-- not re-trigger the hook. Defaults to fontOnly (preserve Blizzard's text
-- color, just enforce the QUI font face/outline). Idempotent per object.
---------------------------------------------------------------------------
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

---------------------------------------------------------------------------
-- LockFrameTextObjects(frame, maxDepth)
-- Recursively LockFontObject every fontstring (and button label) under a
-- frame. Unlike the one-shot SkinFrameText, this defeats Blizzard's hover /
-- selection / list re-bind font-OBJECT swaps so they don't revert the QUI
-- font. Idempotent per object (LockFontObject guards with qFontLocked), so it
-- is safe to call repeatedly on pooled rows and on re-skins. maxDepth bounds
-- the descent (default 4).
---------------------------------------------------------------------------
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

---------------------------------------------------------------------------
-- ApplyButtonFontObjectsDeep(frame, maxDepth)
-- Drive Normal/Highlight/Disabled font OBJECTS to the QUI font for EVERY button
-- under a frame. LockFrameTextObjects only re-asserts when Blizzard re-CALLS a
-- Set*FontObject setter (e.g. an element initializer on rebind); it canNOT stop
-- the engine's INTERNAL hover/disable highlight swap, which switches the shown
-- font to the button's HighlightFontObject/DisabledFontObject without ever
-- calling a setter. Driving the button's font objects themselves is the only
-- durable fix for that swap. Use on skinned frames whose action buttons are not
-- individually SkinButton{font}'d (collections/journal bottom buttons, etc.).
-- Guarded per button (qBtnFontDriven) so repeat walks on reskin are cheap.
-- maxDepth bounds the descent (default 4).
---------------------------------------------------------------------------
function SkinBase.ApplyButtonFontObjectsDeep(frame, maxDepth)
    if not frame then return end
    maxDepth = maxDepth or 4
    if frame.GetObjectType then
        local t = frame:GetObjectType()
        if (t == "Button" or t == "CheckButton")
            and frame.GetFontString and frame:GetFontString()
            and not SkinBase.GetFrameData(frame, "qBtnFontDriven") then
            SkinBase.ApplyButtonFontObjects(frame)
            SkinBase.SetFrameData(frame, "qBtnFontDriven", true)
        end
    end
    if SafeWalkSkip(frame) then return end
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

-- Resolve a frame's primary label fontstring (button text / editbox).
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
    -- QUI font on the label BY DEFAULT (opts.font == false opts out), matching
    -- SkinTab. A skinned button should carry the QUI face; relying on per-caller
    -- opt-in left most buttons reverting to Blizzard font on hover/disable.
    -- Flagged so RefreshWidget re-applies it on live font/theme changes.
    if opts.font ~= false then
        SkinBase.SetFrameData(button, "skinFont", true)
        SkinBase.SetFrameData(button, "skinFontColor", opts.fontColor)
        SkinBase.SetFrameData(button, "skinFontDisabledColor", opts.disabledFontColor or DISABLED_TEXT_COLOR)
        -- Drive the button's font OBJECTS (not a one-shot SetFont): UIPanel-style
        -- buttons swap their Highlight font object on hover and Disabled object on
        -- :Disable() WITHOUT calling a setter (so a Lock* hook never fires) — only
        -- driving the objects re-faces those swaps. Dim grey disabled color keeps
        -- disabled buttons reading as disabled.
        SkinBase.ApplyButtonFontObjects(button, { color = opts.fontColor, disabledColor = opts.disabledFontColor or DISABLED_TEXT_COLOR })
    end
    if opts.hover ~= false then AttachHover(button) end
    HookButtonVisualState(button)
    SkinBase.RefreshButtonVisualState(button)
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
    -- QUI font by default; dense/native editboxes can opt out with
    -- { font = false }. LockFontObject covers Blizzard focus/default
    -- paths that reapply font objects after the initial skin pass.
    if opts.font ~= false then
        SkinBase.SetFrameData(editBox, "skinFont", true)
        SkinBase.SetFrameData(editBox, "skinFontColor", opts.fontColor)
        SkinBase.SkinFontString(editBox, { color = opts.fontColor })
        SkinBase.LockFontObject(editBox, { fontOnly = true })
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
    -- Border-brighten on hover (HookScript OnEnter/OnLeave). Rows whose OnEnter
    -- script never fires (e.g. profession recipe rows) route hover via the mixin
    -- hook + SkinBase.SetRowHovered instead.
    if opts.hover ~= false then AttachHover(row) end
    SkinBase.MarkStyled(row)
end

---------------------------------------------------------------------------
-- SkinIcon(icon, opts)
-- Skin an EXISTING Blizzard icon Texture in place: crop the default border
-- padding to the QUI 0.08-0.92 TexCoord convention (shared by character/
-- keystone/inspect) and parent a thin hollow pixel border around it. Taint-safe
-- — only SetTexCoord on the texture plus a backdrop child on its host; never
-- replaces the Blizzard texture. Idempotent per icon (border cached via
-- SetFrameData "iconBorder"). Returns the border frame.
--   opts.parent : frame to host the border (default icon:GetParent()).
--   opts.pixels : border thickness, default CHROME.BORDER_PX.
--   opts.border : {r,g,b,a} color (default skin border); on re-call recolors.
--   opts.crop   : pass false to skip the TexCoord crop (already-cropped icons).
---------------------------------------------------------------------------
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

---------------------------------------------------------------------------
-- SkinStatusBar(bar, opts)
-- Skin an existing Blizzard StatusBar in place: flat fill texture (pixel-snapped
-- so it doesn't vanish at fractional scale), optional fill color, and a thin QUI
-- backdrop behind it. Idempotent (MarkStyled).
--   opts.color    : {r,g,b,a} fill color (default GetSkinBarColor).
--   opts.texture  : fill texture (default WHITE8x8).
--   opts.backdrop : pass false to skip the surrounding QUI backdrop.
--   opts.settings/opts.prefix : forwarded to GetSkinBarColor for themed bars.
---------------------------------------------------------------------------
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

---------------------------------------------------------------------------
-- SkinNextPrevButton(button, direction, opts)
-- Skin a Blizzard next/prev page-nav button: QUI backdrop + hover (via
-- SkinButton{strip}) with a directional chevron glyph replacing the Blizzard
-- arrow art. The QUI font carries the baked roman ◄/► glyphs. Idempotent.
--   direction : "left"/"prev" → ◄, anything else → ►.
--   opts.size : glyph font size (default 14).
---------------------------------------------------------------------------
function SkinBase.SkinNextPrevButton(button, direction, opts)
    if not button or SkinBase.GetFrameData(button, "nextPrevStyled") then return end
    opts = opts or {}

    SkinBase.SkinButton(button, { strip = true })

    -- Inset the QUI backdrop so it frames the chevron glyph rather than the button's
    -- full hit-rect. Blizzard page buttons (e.g. InboxPrev/NextPageButton are 32x32
    -- per MailFrame.xml) carry adjacent PREV/NEXT labels + neighbours; a full-bleed
    -- backdrop overruns them ("border too big, runs into other elements"). 4px
    -- matches the proven inset the mail arrows used before unification.
    local bd = SkinBase.GetBackdrop(button)
    if bd and SkinBase.SetInsetPixelPoints then
        SkinBase.SetInsetPixelPoints(bd, button, opts.inset or 4)
    end

    if button.CreateFontString then
        local glyph = button:CreateFontString(nil, "OVERLAY")
        local font = (Helpers.GetGeneralFont and Helpers.GetGeneralFont()) or STANDARD_TEXT_FONT
        glyph:SetFont(font, opts.size or 14, "OUTLINE")
        local isPrev = direction == "left" or direction == "prev"
        glyph:SetText(isPrev and "\226\151\132" or "\226\150\186") -- ◄ U+25C4 / ► U+25BA
        glyph:SetPoint("CENTER")
        glyph:SetTextColor(1, 1, 1, 1)
        SkinBase.SetFrameData(button, "nextPrevGlyph", glyph)
    end
    SkinBase.SetFrameData(button, "nextPrevStyled", true)
end

---------------------------------------------------------------------------
-- SkinCheckBox(check, opts)
-- Skin an existing Blizzard CheckButton in place: hide the box art (normal/
-- pushed/highlight), give it a small QUI backdrop box, and accent-tint the
-- native check mark (state stays engine-driven). Idempotent (MarkStyled).
---------------------------------------------------------------------------
function SkinBase.SkinCheckBox(check, opts)
    if not check or SkinBase.IsStyled(check) then return end
    opts = opts or {}

    -- Hide the Blizzard box art; keep the check mark itself.
    local normal = check.GetNormalTexture and check:GetNormalTexture()
    if normal then
        if normal.SetTexture then normal:SetTexture(nil) end
        if normal.SetAlpha then normal:SetAlpha(0) end
    end
    local pushed = check.GetPushedTexture and check:GetPushedTexture()
    if pushed and pushed.SetAlpha then pushed:SetAlpha(0) end
    local hl = check.GetHighlightTexture and check:GetHighlightTexture()
    if hl and hl.SetAlpha then hl:SetAlpha(0) end

    -- QUI backdrop box (BACKGROUND/BORDER); the check mark draws OVERLAY above it
    -- — same layering the proven SkinCloseButton uses for its "x" label.
    local sr, sg, sb, sa, bgr, bgg, bgb, bga = SkinBase.GetSkinColors()
    SkinBase.CreateBackdrop(check, sr, sg, sb, sa, bgr, bgg, bgb, bga)

    -- Accent-tint the native check mark so it reads as a QUI check.
    local ar, ag, ab = UIKit.GetAccentColor()
    local checked = check.GetCheckedTexture and check:GetCheckedTexture()
    if checked then
        if checked.SetVertexColor and ar then checked:SetVertexColor(ar, ag, ab, 1) end
        if checked.SetDrawLayer then checked:SetDrawLayer("OVERLAY", 7) end
    end
    local disabledChecked = check.GetDisabledCheckedTexture and check:GetDisabledCheckedTexture()
    if disabledChecked and disabledChecked.SetVertexColor and ar then
        disabledChecked:SetVertexColor(ar * 0.5, ag * 0.5, ab * 0.5, 1)
    end

    SkinBase.MarkStyled(check)
end

---------------------------------------------------------------------------
-- HandleIconBorder(nativeBorder, quiBorder, opts)
-- Drive a QUI border frame's color from a Blizzard item IconBorder by quality:
-- hide the native ring and mirror its quality color onto the QUI border. The
-- color is read straight from the SetVertexColor HOOK ARGS (forward-through —
-- never compares the values, so it is secret-safe AND avoids GetVertexColor's
-- MayReturnNothing). When Blizzard hides the ring (common item / no quality),
-- the QUI border reverts to opts.defaultBorder. Idempotent per native border.
--   quiBorder       : the QUI border frame (e.g. the one SkinIcon returns).
--   opts.defaultBorder : {r,g,b,a} fallback when no quality (default: none).
-- NOTE: covers the SetVertexColor quality path (the common case). Atlas-encoded
-- quality borders are not mirrored.
---------------------------------------------------------------------------
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

    -- Capture the native ring's CURRENT quality color once (it may have been set
    -- before we installed the SetVertexColor hook). GetVertexColor MayReturnNothing
    -- -> pcall; secret values forward through SetBackdropColors without comparison.
    if nativeBorder.GetVertexColor then
        local ok, r, g, b, a = pcall(nativeBorder.GetVertexColor, nativeBorder)
        if ok and r then SkinBase.SetBackdropColors(quiBorder, { r, g, b, a or 1 }, nil) end
    end

    -- Hide the native ring; the QUI border now carries the quality color.
    if nativeBorder.SetAlpha then nativeBorder:SetAlpha(0) end
end

---------------------------------------------------------------------------
-- SkinTrimScrollBar(scrollBar, opts)
-- Skin a WowTrimScrollBar / minimal scrollbar widget: hide track + background +
-- arrow buttons and render the thumb as a thin pixel-snapped QUI fill. Promoted
-- from frames/character.lua StyleThinScrollBar (which now delegates here).
--   opts.color : {r,g,b} thumb color (default skin bar color).
--   opts.width : thumb width in px (default 8).
--   opts.alpha : thumb fill alpha (default 0.78).
---------------------------------------------------------------------------
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
        UIKit.DisablePixelSnap(thumb) -- thin quad vanishes off-grid at fractional scale without this
        thumb:SetWidth((opts.width or 8) * SkinBase.GetPixelSize(scrollBar, 1))
    end

    local upBtn = scrollBar.ScrollUpButton or scrollBar.Back
    local downBtn = scrollBar.ScrollDownButton or scrollBar.Forward
    if upBtn then upBtn:SetAlpha(0); upBtn:SetSize(1, 1) end
    if downBtn then downBtn:SetAlpha(0); downBtn:SetSize(1, 1) end
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
    local label = button.Label or GetLabelFontString(button)
    -- Persist through scale-refresh WITHOUT rebuilding the backdrop. CreateBackdrop
    -- seeds pixelBackdropData.borderColor/bgColor with the full-alpha skin color;
    -- RefreshPixelBackdrop (login/first-show/scale change) re-applies that cached
    -- value, which is what snapped every category row back to a full-alpha border
    -- ("all highlighted" on first open). Routing through SetBackdropColors fixed
    -- the color but rebuilt the 4-texture backdrop on EVERY category bind
    -- (OnFilterClicked refresh + AuctionHouseFilterButton_SetUp per row) = a
    -- browse-time FPS stutter. Instead drop the cached colors so RefreshPixelBackdrop
    -- falls back to the live _quiBorder*/_quiBg* fields, then set those via the cheap
    -- bare setters (vertex recolor only, no SetPoint/texture rebuild).
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
        SetFontStringColor(label, SkinBase.GetFrameData(button, "categoryTextColor") or { 0.95, 0.95, 0.95, 1 })
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
    -- Drive the QUI font onto the button's font objects (default, like SkinButton):
    -- category buttons swap their Highlight font object on hover with no setter
    -- call, so only object-driving survives it. opts.font == false opts out.
    if opts.font ~= false then
        SkinBase.ApplyButtonFontObjects(button, { disabledColor = DISABLED_TEXT_COLOR })
    end
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
        -- WowStyle1DropdownTemplate (12.x DropdownButton) draws its frame via a
        -- .Background atlas (common-dropdown-textholder), not NineSlice/NormalTexture.
        -- Hide it so the QUI backdrop shows through; the .Arrow is kept.
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
    SkinBase.LockDropdownText(dropdown, 2)
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
    -- Canonical thin QUI scrollbar (was a bare Background:Hide() that left the stock
    -- thumb/track/arrows — the precedent every per-frame `ScrollBar.Background:Hide()`
    -- copy was cloned from). Routing it here unifies every SkinListContainer consumer.
    if list.ScrollBar then
        SkinBase.SkinTrimScrollBar(list.ScrollBar)
    end
    -- The "no results"/error fontstring is re-SetText'd on state refresh; lock its
    -- font face so it doesn't render in the stock font after the one-shot pass.
    if list.ResultsText then
        SkinBase.SkinFontString(list.ResultsText, { fontOnly = true })
        SkinBase.LockFontObject(list.ResultsText, { fontOnly = true })
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

    -- Route theme-refresh recolors through SetBackdropColors so they update the
    -- persisted pixelBackdropData and survive the next scale-refresh rebuild (a
    -- bare bd:SetBackdropColor only touches _quiBg*/the live textures, which are
    -- shadowed by the seeded data.* on rebuild). The SetFrameData skinColor/bgColor
    -- re-stores stay so a later hover derives from the new colors.
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

    -- Re-apply the global QUI font on live font/theme changes for widgets that
    -- opted into shared widget font handling at skin time.
    if SkinBase.GetFrameData(frame, "skinFont") then
        local color = SkinBase.GetFrameData(frame, "skinFontColor")
        if kind == "editbox" then
            SkinBase.SkinFontString(frame, { color = color })
        else
            -- Buttons: re-drive font objects so the QUI font survives hover/disable.
            local disabledColor = SkinBase.GetFrameData(frame, "skinFontDisabledColor") or DISABLED_TEXT_COLOR
            SkinBase.ApplyButtonFontObjects(frame, { color = color, disabledColor = disabledColor })
        end
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

---------------------------------------------------------------------------
-- SkinWindow(frame, opts)
-- The SINGLE canonical "skin a Blizzard window" sequence: chrome strip +
-- backdrop + close button + button font OBJECTS, so every window gets
-- UNIFORM treatment in ONE call. Replaces the error-prone per-frame manual
-- composition of 4-5 helpers (the source of "some frames skinned more than
-- others"). Every step is individually graceful/guarded, so it works on
-- ButtonFrameTemplate, PortraitFrameTemplate, InsetFrameTemplate AND bare
-- custom frames alike.
-- Static-text face comes from the global font-object override (font_system.lua
-- ApplyGlobalDefaultFont); SkinFrameText and LockFrameTextObjects are NOT
-- called here — they are superseded by the global shared-object override.
--   opts.depth        : ApplyButtonFontObjectsDeep depth (default 4)
--   opts.tabs         : array of tab buttons -> SkinTabGroup (optional)
--   opts.tabOwner     : owner for SkinTabGroup (default frame)
--   opts.scrollBars   : array of scrollbars -> SkinTrimScrollBar (optional)
--   opts.noClose      : skip close-button skinning
--   opts.noButtonFonts: skip ApplyButtonFontObjectsDeep
--   opts.noBackdrop   : skip CreateBackdrop (frame already has its own)
-- Does NOT MarkSkinned — the caller owns the per-frame IsSkinned guard.
---------------------------------------------------------------------------
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
        SkinBase.SkinTabGroup(opts.tabs, opts.tabOwner or frame)
    end

    -- Button font OBJECTS only (engine hover/disable swap). Static text face
    -- comes from the global font-object override.
    if not opts.noButtonFonts then
        SkinBase.ApplyButtonFontObjectsDeep(frame, depth)
    end

    if opts.scrollBars then
        for _, bar in ipairs(opts.scrollBars) do
            SkinBase.SkinTrimScrollBar(bar)
        end
    end
end

-- Skinning engine and the generic UI kit are one table; SkinBase is the
-- historical name used by skinning modules, UIKit by core/options.
ns.SkinBase = UIKit
