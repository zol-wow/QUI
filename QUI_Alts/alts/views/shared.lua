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
