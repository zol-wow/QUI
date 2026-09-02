local ADDON_NAME, ns = ...

QUI = QUI or {}
QUI.GUI = QUI.GUI or {}
local GUI = QUI.GUI

GUI.Colors = GUI.Colors or {
    bg = {0.051, 0.067, 0.09, 0.97},
    bgLight = {0.094, 0.11, 0.14, 1},
    bgDark = {0.03, 0.04, 0.06, 1},
    bgContent = {1, 1, 1, 0.02},
    bgSidebar = {0, 0, 0, 0.25},
    bgFooter = {0, 0, 0, 0.15},

    accent = {0.204, 0.827, 0.6, 1},
    accentLight = {0.431, 0.906, 0.718, 1},
    accentDark = {0.1, 0.5, 0.35, 1},
    accentHover = {0.3, 0.9, 0.65, 1},
    accentFaint = {0.204, 0.827, 0.6, 0.07},
    accentGlow = {0.204, 0.827, 0.6, 0.06},

    tabSelected = {0.204, 0.827, 0.6, 1},
    tabSelectedText = {1, 1, 1, 1},
    tabNormal = {1, 1, 1, 0.55},
    tabHover = {1, 1, 1, 0.85},

    -- State ladder (white, alpha-graded): disabled .30 / idle .55 (tabNormal) /
    -- hover .85 (tabHover) / selected 1.0 (tabSelectedText) + accent marker.
    disabled = {1, 1, 1, 0.30},
    disabledBg = {1, 1, 1, 0.04},
    -- Faint accent fill behind a selected row/item (accent RGB, derived).
    selectedWash = {0.204, 0.827, 0.6, 0.10},
    -- Accent used as a TEXT colour: lightened toward white until its relative
    -- luminance reaches GUI.ACCENT_TEXT_MIN_LUMINANCE (derived, see below).
    accentText = {0.204, 0.827, 0.6, 1},

    text = {1, 1, 1, 1},
    textBright = {1, 1, 1, 1},
    textMuted = {1, 1, 1, 0.45},
    textDim = {1, 1, 1, 0.6},
    sectionLabel = {1, 1, 1, 0.42},

    border = {1, 1, 1, 0.06},
    borderStrong = {1, 1, 1, 0.1},
    borderAccent = {0.204, 0.827, 0.6, 1},

    sectionHeader = {0.431, 0.906, 0.718, 1},

    sliderTrack = {1, 1, 1, 0.12},
    sliderThumb = {1, 1, 1, 1},
    sliderThumbBorder = {0, 0, 0, 0.2},

    -- Single scrollbar colour for every QUI scroll surface (accent RGB, derived).
    scrollThumb = {0.204, 0.827, 0.6, 0.6},
    scrollTrack = {1, 1, 1, 0.02},

    toggleOff = {1, 1, 1, 0.12},
    toggleThumb = {1, 1, 1, 1},

    warning = {0.961, 0.620, 0.043, 1},
}

-- Relative luminance (WCAG, sRGB -> linear) of an RGB triple in 0..1.
local function LinearChannel(c)
    c = tonumber(c) or 0
    if c <= 0.04045 then return c / 12.92 end
    return ((c + 0.055) / 1.055) ^ 2.4
end

function GUI:GetRelativeLuminance(r, g, b)
    return 0.2126 * LinearChannel(r) + 0.7152 * LinearChannel(g) + 0.0722 * LinearChannel(b)
end

-- Floor for accent-as-text: a dark custom accent (Horde red, navy) is unreadable
-- on the panel bg, so accentText lightens it toward white until luminance >= this.
GUI.ACCENT_TEXT_MIN_LUMINANCE = 0.45

function GUI:DeriveAccentText(r, g, b)
    local floor = self.ACCENT_TEXT_MIN_LUMINANCE or 0.45
    if self:GetRelativeLuminance(r, g, b) >= floor then return r, g, b end
    -- lerp(accent, white, t) is monotonic in luminance: bisect for the smallest t.
    local lo, hi = 0, 1
    for _ = 1, 16 do
        local mid = (lo + hi) / 2
        local mr, mg, mb = r + (1 - r) * mid, g + (1 - g) * mid, b + (1 - b) * mid
        if self:GetRelativeLuminance(mr, mg, mb) >= floor then hi = mid else lo = mid end
    end
    return r + (1 - r) * hi, g + (1 - g) * hi, b + (1 - b) * hi
end

do
    local C = GUI.Colors
    local accent = C.accent
    C.accentText = C.accentText or { accent[1], accent[2], accent[3], 1 }
    C.accentText[1], C.accentText[2], C.accentText[3] = GUI:DeriveAccentText(accent[1], accent[2], accent[3])
    C.accentText[4] = 1
end

-- Accent-change listeners. Persistent chrome that is NOT rebuilt by
-- GUI:RefreshAccentColor (the shared UIParent-parented dropdown menu, skin
-- surfaces) registers here and re-tints from the live GUI.Colors tokens.
-- Dispatch runs over a snapshot so listeners may (un)register mid-notify and
-- one erroring listener cannot stop the rest.
function GUI:OnAccentChanged(fn)
    if type(fn) ~= "function" then return false end
    self._accentListeners = self._accentListeners or {}
    for _, existing in ipairs(self._accentListeners) do
        if existing == fn then return false end
    end
    self._accentListeners[#self._accentListeners + 1] = fn
    return true
end

function GUI:OffAccentChanged(fn)
    local listeners = self._accentListeners
    if not listeners then return false end
    for i = #listeners, 1, -1 do
        if listeners[i] == fn then
            table.remove(listeners, i)
            return true
        end
    end
    return false
end

function GUI:NotifyAccentChanged()
    local listeners = self._accentListeners
    if not listeners or #listeners == 0 then return 0 end
    local snapshot = {}
    for i = 1, #listeners do snapshot[i] = listeners[i] end
    local colors = self.Colors
    for _, fn in ipairs(snapshot) do
        if ns.SafeCall then
            ns.SafeCall("bulkhead", fn, colors)
        else
            fn(colors)
        end
    end
    return #snapshot
end

GUI.ThemePresets = GUI.ThemePresets or {
    { name = "Sky Blue",     color = {0.376, 0.647, 0.980} },
    { name = "Classic Mint", color = {0.204, 0.827, 0.600} },
    { name = "Horde",        color = {0.780, 0.192, 0.192} },
    { name = "Alliance",     color = {0.267, 0.467, 0.800} },
    { name = "Midnight",     color = {0.580, 0.490, 0.890} },
    { name = "Amber",        color = {0.961, 0.620, 0.043} },
    { name = "Rose",         color = {0.914, 0.349, 0.518} },
    { name = "Emerald",      color = {0.196, 0.804, 0.494} },
}

function GUI:ResolveThemePreset(presetName)
    for _, preset in ipairs(self.ThemePresets or {}) do
        if preset.name == presetName then
            return preset.color[1], preset.color[2], preset.color[3]
        end
    end

    if presetName == "Class Colored" then
        local _, class = UnitClass("player")
        -- @secret-policy: collapse-only — UnitClass can return SECRET on 12.1 PTR7
        if issecretvalue and issecretvalue(class) then class = nil end
        local color = class and ns.Helpers and ns.Helpers.GetClassColorTable(class)
        if color then return color.r, color.g, color.b end
        return 0.376, 0.647, 0.980
    end

    if presetName == "Faction Auto" then
        local faction = UnitFactionGroup("player")
        if faction == "Horde" then return 0.780, 0.192, 0.192 end
        return 0.267, 0.467, 0.800
    end

    if presetName == "Custom" then
        local db = QUI.QUICore and QUI.QUICore.db and QUI.QUICore.db.profile
        local custom = db and db.general and db.general.addonAccentColor
        if custom then return custom[1], custom[2], custom[3] end
    end

    return 0.376, 0.647, 0.980
end

function GUI:ApplyAccentColor(r, g, b)
    local function lerp(a, b2, t) return a + (b2 - a) * t end
    local C = self.Colors
    C.accent[1], C.accent[2], C.accent[3], C.accent[4] = r, g, b, 1
    C.accentFaint[1], C.accentFaint[2], C.accentFaint[3] = r, g, b
    C.accentGlow[1], C.accentGlow[2], C.accentGlow[3] = r, g, b
    C.accentLight[1] = lerp(r, 1, 0.3)
    C.accentLight[2] = lerp(g, 1, 0.3)
    C.accentLight[3] = lerp(b, 1, 0.3)
    C.accentLight[4] = 1
    C.accentDark[1], C.accentDark[2], C.accentDark[3], C.accentDark[4] = r * 0.5, g * 0.5, b * 0.5, 1
    C.accentHover[1] = lerp(r, 1, 0.15)
    C.accentHover[2] = lerp(g, 1, 0.15)
    C.accentHover[3] = lerp(b, 1, 0.15)
    C.accentHover[4] = 1
    C.tabSelected[1], C.tabSelected[2], C.tabSelected[3] = r, g, b
    C.borderAccent[1], C.borderAccent[2], C.borderAccent[3] = r, g, b
    C.sectionHeader[1], C.sectionHeader[2], C.sectionHeader[3] = C.accentLight[1], C.accentLight[2], C.accentLight[3]

    -- Derived state roles (alpha is the role's own; only the hue follows accent).
    C.selectedWash = C.selectedWash or { r, g, b, 0.10 }
    C.selectedWash[1], C.selectedWash[2], C.selectedWash[3] = r, g, b
    C.scrollThumb = C.scrollThumb or { r, g, b, 0.6 }
    C.scrollThumb[1], C.scrollThumb[2], C.scrollThumb[3] = r, g, b
    C.accentText = C.accentText or { r, g, b, 1 }
    C.accentText[1], C.accentText[2], C.accentText[3] = self:DeriveAccentText(r, g, b)
    C.accentText[4] = 1

    if type(self.RefreshCachedColors) == "function" then
        self:RefreshCachedColors()
    end
end
