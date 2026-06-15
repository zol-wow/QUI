---------------------------------------------------------------------------
-- QUI Alts — shared view helpers.
-- Font/outline/fontstring and class-color helpers that were previously
-- copy-pasted verbatim across every alts/views/*.lua file. Loaded before the
-- view files (see QUI_Alts.toc) so each view can capture these as locals.
---------------------------------------------------------------------------
local ADDON_NAME, ns = ...
local Helpers = ns.Helpers

local Shared = {}
ns.AltsViewShared = Shared

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
    fs:SetFont(Shared.GeneralFont(), size or 11, Shared.GeneralOutline())
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
