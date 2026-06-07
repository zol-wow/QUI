-- modules/chat/scrollbar_custom.lua
-- Slim scroll indicator + jump-to-bottom button for the custom chat display.
-- Click-to-jump: clicking the track moves the scroll position to the cursor's
-- Y fraction within the track (bottom = newest / offset 0; top = full range).
-- Track drag: holding the mouse button down installs an OnUpdate that keeps
-- tracking the cursor, giving smooth drag behaviour. Driven by the SMF's own
-- scroll-changed callback.
-- Per-window instances: each windowID gets its own track/thumb/bottomBtn trio
-- stored in the `instances` table. EnsureAttached() walks all live windows and
-- creates any missing entries; OnWindowDeleted() hides every instance and
-- rebuilds from scratch (id compaction shuffles all ids, so we wipe + rebuild
-- rather than trying to re-point closures that captured old windowIDs by value).
local ADDON_NAME, ns = ...

local I = assert(ns.QUI.Chat and ns.QUI.Chat._internals,
    "QUI Chat: scrollbar_custom.lua loaded before chat.lua. Check chat.xml — chat.lua must precede scrollbar_custom.lua.")

ns.QUI.Chat.Scrollbar = ns.QUI.Chat.Scrollbar or {}
local Scrollbar = ns.QUI.Chat.Scrollbar

local instances = {} -- windowID -> { track, thumb, bottomBtn }
local TRACK_WIDTH = 8
local MIN_THUMB = 12
local JUMP_GLYPH_STROKE = 1

local function GetAccent()
    return (I.GetAccent and I.GetAccent()) or { 0.2, 0.8, 0.6, 1 }
end

local function GetTextDim()
    local colors = I.QUI_COLORS
    return (type(colors) == "table" and colors.textDim) or { 0.72, 0.72, 0.76, 1 }
end

local function AddGlyphLine(parent)
    local line = parent:CreateTexture(nil, "ARTWORK")
    line:SetTexture("Interface\\Buttons\\WHITE8x8")
    return line
end

local function ColorGlyphLine(line, color)
    if line and line.SetColorTexture and color then
        line:SetColorTexture(color[1] or 1, color[2] or 1, color[3] or 1, color[4] or 1)
    end
end

local function CreateJumpGlyph(button)
    if not button or button._quiGlyphParts then return end

    local parts = {}
    parts[1] = AddGlyphLine(button)
    parts[1]:SetSize(8, JUMP_GLYPH_STROKE)
    parts[1]:SetPoint("CENTER", button, "CENTER", -3, 1)
    if parts[1].SetRotation then parts[1]:SetRotation(-0.785) end

    parts[2] = AddGlyphLine(button)
    parts[2]:SetSize(8, JUMP_GLYPH_STROKE)
    parts[2]:SetPoint("CENTER", button, "CENTER", 3, 1)
    if parts[2].SetRotation then parts[2]:SetRotation(0.785) end

    parts[3] = AddGlyphLine(button)
    parts[3]:SetSize(12, JUMP_GLYPH_STROKE)
    parts[3]:SetPoint("CENTER", button, "CENTER", 0, -5)

    button._quiGlyphParts = parts
end

local function PaintJumpGlyph(button)
    if not (button and button._quiGlyphParts) then return end
    local accent = GetAccent()
    local dim = GetTextDim()
    local parts = button._quiGlyphParts
    ColorGlyphLine(parts[1], { accent[1], accent[2], accent[3], 0.9 })
    ColorGlyphLine(parts[2], { accent[1], accent[2], accent[3], 0.9 })
    ColorGlyphLine(parts[3], { dim[1], dim[2], dim[3], 0.5 })
end

local function GetSMF(windowID)
    local Display = ns.QUI.Chat.DisplayLayer
    return Display and Display.GetMessageFrame and Display.GetMessageFrame(windowID)
end

local function UpdateInstance(windowID)
    local sb = instances[windowID]
    local smf = GetSMF(windowID)
    if not (smf and sb and sb.track and sb.thumb and sb.bottomBtn) then return end
    local range = (smf.GetMaxScrollRange and smf:GetMaxScrollRange()) or 0
    local offset = (smf.GetScrollOffset and smf:GetScrollOffset()) or 0
    if range <= 0 then
        sb.track:SetShown(false)
        sb.bottomBtn:SetShown(false)
        return
    end
    sb.track:SetShown(true)
    local h = sb.track:GetHeight() or 100
    local frac = math.min(1, math.max(0, offset / range))
    local thumbH = math.max(MIN_THUMB, h * (1 / (1 + range / 25)))
    sb.thumb:SetHeight(thumbH)
    sb.thumb:ClearAllPoints()
    -- Two-anchor form: sets both X edges so the thumb fills the track width.
    sb.thumb:SetPoint("BOTTOMRIGHT", sb.track, "BOTTOMRIGHT", 0, (h - thumbH) * frac)
    sb.thumb:SetPoint("BOTTOMLEFT", sb.track, "BOTTOMLEFT", 0, (h - thumbH) * frac)
    sb.bottomBtn:SetShown(offset > 0)
end

function Scrollbar.Update()
    for windowID in pairs(instances) do
        UpdateInstance(windowID)
    end
end

-- Jump the scroll offset to the cursor's position on the track (bottom of
-- the track = newest / offset 0; top = full range).
-- QUI-owned chain anchored to UIParent: scale/anchor secrets can't occur
-- here; plain nil/zero guards suffice.
local function JumpToCursor(windowID)
    local sb = instances[windowID]
    local smf = GetSMF(windowID)
    if not (smf and sb and sb.track) then return end
    local scale = (sb.track.GetEffectiveScale and sb.track:GetEffectiveScale()) or 1
    if not scale or scale <= 0 then scale = 1 end
    local _, cy = _G.GetCursorPosition()
    local bottom = sb.track.GetBottom and sb.track:GetBottom()
    local h = sb.track:GetHeight() or 0
    if type(cy) ~= "number" or not bottom or h <= 0 then return end
    local frac = ((cy / scale) - bottom) / h
    frac = math.min(1, math.max(0, frac))
    local range = (smf.GetMaxScrollRange and smf:GetMaxScrollRange()) or 0
    if smf.SetScrollOffset then
        smf:SetScrollOffset(math.floor(frac * range + 0.5))
    end
    UpdateInstance(windowID)
end

local function CreateInstance(windowID, container, smf)
    local sb = {}
    instances[windowID] = sb
    local trackName = (windowID == 1) and "QUI_CustomChatScrollbar" or nil
    local btnName   = (windowID == 1) and "QUI_CustomChatJumpBottom" or nil
    sb.track = CreateFrame("Frame", trackName, container)
    sb.track:SetPoint("TOPRIGHT", container, "TOPRIGHT", -3, -16)
    sb.track:SetPoint("BOTTOMRIGHT", container, "BOTTOMRIGHT", -3, 24)
    sb.track:SetWidth(TRACK_WIDTH)
    local bg = sb.track:CreateTexture(nil, "BACKGROUND")
    bg:SetPoint("TOPLEFT", sb.track, "TOPLEFT", 0, 0)
    bg:SetPoint("BOTTOMRIGHT", sb.track, "BOTTOMRIGHT", 0, 0)
    bg:SetColorTexture(1, 1, 1, 0.06)
    sb.thumb = sb.track:CreateTexture(nil, "ARTWORK")
    -- Initial anchors: both X edges fill the track; Y repositioned in Update.
    sb.thumb:SetPoint("BOTTOMRIGHT", sb.track, "BOTTOMRIGHT", 0, 0)
    sb.thumb:SetPoint("BOTTOMLEFT", sb.track, "BOTTOMLEFT", 0, 0)
    sb.thumb:SetHeight(MIN_THUMB)
    local accent = GetAccent()
    sb.thumb:SetColorTexture(accent[1], accent[2], accent[3], 0.55)

    sb.bottomBtn = CreateFrame("Button", btnName, container)
    sb.bottomBtn:SetSize(16, 16)
    sb.bottomBtn:SetPoint("BOTTOMRIGHT", container, "BOTTOMRIGHT", -4, 5)
    sb.bottomBtn:EnableMouse(true)
    CreateJumpGlyph(sb.bottomBtn)
    PaintJumpGlyph(sb.bottomBtn)
    sb.bottomBtn:SetScript("OnClick", function()
        local frame = GetSMF(windowID)
        if frame and frame.ScrollToBottom then frame:ScrollToBottom() end
        UpdateInstance(windowID)
    end)

    -- Click-to-jump + drag: the slim track gets a widened hit rect; while
    -- the button is held an OnUpdate keeps tracking the cursor.
    sb.track:EnableMouse(true)
    if sb.track.SetHitRectInsets then
        -- Safe: the track is a QUI-owned, unprotected frame.
        sb.track:SetHitRectInsets(-5, -5, 0, 0)
    end
    sb.track:SetScript("OnMouseDown", function(self)
        JumpToCursor(windowID)
        self:SetScript("OnUpdate", function() JumpToCursor(windowID) end)
    end)
    sb.track:SetScript("OnMouseUp", function(self)
        self:SetScript("OnUpdate", nil)
    end)
    sb.track:SetScript("OnHide", function(self)
        self:SetScript("OnUpdate", nil)
    end)

    -- SetOnScrollChangedCallback is a single-slot setter, not an adder: the
    -- new closure REPLACES any previous one on this SMF. After OnWindowDeleted
    -- rebuilds, the old instance's closure is unreachable (never called),
    -- so there is no risk of a stale closure updating a dead instance.
    if smf.SetOnScrollChangedCallback then
        smf:SetOnScrollChangedCallback(function() UpdateInstance(windowID) end)
    end
end

function Scrollbar.EnsureAttached()
    local Display = ns.QUI.Chat.DisplayLayer
    if not (Display and Display.GetWindowCount) then return end
    for windowID = 1, Display.GetWindowCount() do
        local container = Display.GetContainer(windowID)
        local smf = GetSMF(windowID)
        if container and smf and not instances[windowID] then
            CreateInstance(windowID, container, smf)
        end
    end
    Scrollbar.Update()
end

-- Window deletion shuffles ids; these closures capture windowID by VALUE,
-- so the whole map is rebuilt rather than re-pointed.
function Scrollbar.OnWindowDeleted()
    for _, sb in pairs(instances) do
        if sb.track then sb.track:Hide() end
        if sb.bottomBtn then sb.bottomBtn:Hide() end
    end
    instances = {}
    Scrollbar.EnsureAttached()
end

-- Re-apply the theme accent (skin-refresh path; creation-time color
-- otherwise goes stale until /reload).
function Scrollbar.Restyle()
    local accent = GetAccent()
    for _, sb in pairs(instances) do
        if sb.thumb and sb.thumb.SetColorTexture then
            sb.thumb:SetColorTexture(accent[1], accent[2], accent[3], 0.55)
        end
        PaintJumpGlyph(sb.bottomBtn)
    end
end
