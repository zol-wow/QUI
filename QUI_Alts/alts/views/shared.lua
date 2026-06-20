---------------------------------------------------------------------------
-- QUI Alts — shared view helpers.
-- Font/outline/fontstring and class-color helpers that were previously
-- copy-pasted verbatim across every alts/views/*.lua file. Loaded before the
-- view files (see QUI_Alts.toc) so each view can capture these as locals.
---------------------------------------------------------------------------
local ADDON_NAME, ns = ...
local Helpers = ns.Helpers
local UIKit = ns.UIKit

local Shared = {}
ns.AltsViewShared = Shared

-- Width/height of the thin scroll track and the px a scrolled view reserves on
-- its scrolling axis so cells never sit under the bar (chat scrollbar_custom.lua
-- visual: 8px track, 6% white bg, accent thumb at 55%).
Shared.SCROLLBAR_W = 8
Shared.SCROLLBAR_RESERVE = 12

local function CJKFont(fs, p, s, f)
    if Helpers and Helpers.ApplyFontWithFallback then
        Helpers.ApplyFontWithFallback(fs, p, s, f)
    else
        fs:SetFont(p, s, f)
    end
end

--- Class token → r,g,b. RAID_CLASS_COLORS read directly (chat sender-recolor
--- precedent; routing through the CUSTOM-aware helper would drift here too).
function Shared.ClassColor(classToken)
    local c = classToken and RAID_CLASS_COLORS and RAID_CLASS_COLORS[classToken]
    if c then return c.r, c.g, c.b end
    return 1, 1, 1
end

function Shared.GeneralFont()
    return (Helpers and Helpers.GetGeneralFont and Helpers.GetGeneralFont())
        or STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
end

function Shared.GeneralOutline()
    return (Helpers and Helpers.GetGeneralFontOutline and Helpers.GetGeneralFontOutline())
        or ""
end

function Shared.MakeFS(parent, size)
    local fs = parent:CreateFontString(nil, "ARTWORK")
    CJKFont(fs, Shared.GeneralFont(), size or 11, Shared.GeneralOutline())
    fs:SetWordWrap(false)
    return fs
end

--- Pooled list-row button shared by the alts views: a WHITE8x8 background that
--- flips to 8% white on hover. Every view built this same Button + _bg + hover
--- flip by hand; this is the one copy. The caller adds the cells / OnClick /
--- RegisterForClicks on the returned button and positions it in its render pass.
---
---   opts.height     row height (SetHeight); omit to leave it unset
---   opts.hoverAlpha hover background alpha (default 0.08)
---   opts.hoverGuard optional predicate(self); when present the hover flip (and
---                   the onEnter hook) only run while it returns truthy — covers
---                   reputations' group rows and the filter popup's header rows
---   opts.onEnter    optional extra run after the flip (e.g. a tooltip)
---   opts.onLeave    optional extra run after the flip-back (e.g. tooltip hide)
---
--- Returns the Button with `._bg` assigned.
function Shared.CreateRow(parent, opts)
    opts = opts or {}
    local r = CreateFrame("Button", nil, parent)
    if opts.height then r:SetHeight(opts.height) end
    local bg = r:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetTexture("Interface\\Buttons\\WHITE8x8")
    bg:SetVertexColor(1, 1, 1, 0)
    r._bg = bg
    local alpha = opts.hoverAlpha or 0.08
    local guard = opts.hoverGuard
    local onEnter, onLeave = opts.onEnter, opts.onLeave
    r:SetScript("OnEnter", function(self)
        if guard and not guard(self) then return end
        self._bg:SetVertexColor(1, 1, 1, alpha)
        if onEnter then onEnter(self) end
    end)
    r:SetScript("OnLeave", function(self)
        self._bg:SetVertexColor(1, 1, 1, 0)
        if onLeave then onLeave(self) end
    end)
    return r
end

---------------------------------------------------------------------------
-- Scroll bar (thin track + draggable accent thumb). The alts views all scroll
-- a pooled row/column list by an integer offset via the mouse wheel; this adds
-- the matching visible bar so overflow is discoverable and draggable. Style
-- mirrors the custom chat scrollbar (8px track, 6% white track, accent thumb).
--
--   opts.orientation  "vertical" (default) | "horizontal"
--   opts.onScroll     function(newOffset) — fired on track click / drag with a
--                     clamped integer offset; the caller applies it + re-renders
--
-- The caller anchors `sb.track` (insets differ per view), then calls
--   sb:Update(total, visible, offset)
-- at the end of every render pass. Update hides the track when it all fits.
---------------------------------------------------------------------------
local liveBars = {}  -- all created bars, for accent restyle

local MIN_THUMB = 16

function Shared.CreateScrollBar(parent, opts)
    opts = opts or {}
    local horizontal = opts.orientation == "horizontal"
    local sb = { horizontal = horizontal, onScroll = opts.onScroll }

    local track = CreateFrame("Frame", nil, parent)
    sb.track = track
    if horizontal then track:SetHeight(Shared.SCROLLBAR_W)
    else track:SetWidth(Shared.SCROLLBAR_W) end

    local bg = track:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(1, 1, 1, 0.06)
    if UIKit and UIKit.DisablePixelSnap then UIKit.DisablePixelSnap(bg) end

    local thumb = track:CreateTexture(nil, "ARTWORK")
    sb.thumb = thumb
    if UIKit and UIKit.DisablePixelSnap then UIKit.DisablePixelSnap(thumb) end

    function sb:Paint()
        local r, g, b = 0.2, 0.8, 0.6
        if UIKit and UIKit.GetAccentColor then r, g, b = UIKit.GetAccentColor() end
        thumb:SetColorTexture(r, g, b, 0.55)
    end
    sb:Paint()

    sb._total, sb._visible, sb._offset = 0, 0, 0
    local function MaxOff()
        return math.max(0, (sb._total or 0) - (sb._visible or 0))
    end

    function sb:Update(total, visible, offset)
        self._total, self._visible = total or 0, visible or 0
        local maxOff = MaxOff()
        offset = math.min(math.max(offset or 0, 0), maxOff)
        self._offset = offset
        if maxOff <= 0 or self._total <= 0 then
            track:Hide()
            return
        end
        track:Show()
        local frac = offset / maxOff
        if horizontal then
            local w = track:GetWidth() or 1
            local tw = math.max(MIN_THUMB, math.min(w, w * (self._visible / self._total)))
            thumb:ClearAllPoints()
            thumb:SetPoint("TOPLEFT", track, "TOPLEFT", (w - tw) * frac, 0)
            thumb:SetPoint("BOTTOMLEFT", track, "BOTTOMLEFT", (w - tw) * frac, 0)
            thumb:SetWidth(tw)
        else
            local h = track:GetHeight() or 1
            local th = math.max(MIN_THUMB, math.min(h, h * (self._visible / self._total)))
            thumb:ClearAllPoints()
            -- top of track = offset 0; thumb slides down as the offset grows
            thumb:SetPoint("TOPLEFT", track, "TOPLEFT", 0, -(h - th) * frac)
            thumb:SetPoint("TOPRIGHT", track, "TOPRIGHT", 0, -(h - th) * frac)
            thumb:SetHeight(th)
        end
    end

    -- click + drag to jump (QUI-owned UIParent chain → plain scale guards).
    local function JumpToCursor()
        local maxOff = MaxOff()
        if maxOff <= 0 then return end
        local scale = (track.GetEffectiveScale and track:GetEffectiveScale()) or 1
        if not scale or scale <= 0 then scale = 1 end
        local cx, cy = GetCursorPosition()
        local frac
        if horizontal then
            local left, w = track:GetLeft(), track:GetWidth() or 0
            if not left or w <= 0 or type(cx) ~= "number" then return end
            frac = ((cx / scale) - left) / w
        else
            local top, h = track:GetTop(), track:GetHeight() or 0
            if not top or h <= 0 or type(cy) ~= "number" then return end
            frac = (top - (cy / scale)) / h
        end
        frac = math.min(1, math.max(0, frac))
        if sb.onScroll then sb.onScroll(math.floor(frac * maxOff + 0.5)) end
    end

    track:EnableMouse(true)
    track:SetScript("OnMouseDown", function(self)
        JumpToCursor()
        self:SetScript("OnUpdate", JumpToCursor)
    end)
    track:SetScript("OnMouseUp", function(self) self:SetScript("OnUpdate", nil) end)
    track:SetScript("OnHide", function(self) self:SetScript("OnUpdate", nil) end)

    liveBars[#liveBars + 1] = sb
    return sb
end

--- Re-tint every live scroll thumb to the current theme accent (skin-refresh
--- path; creation-time color otherwise goes stale until /reload).
function Shared.RestyleScrollBars()
    for _, sb in ipairs(liveBars) do sb:Paint() end
end
