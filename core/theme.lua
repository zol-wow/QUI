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

    toggleOff = {1, 1, 1, 0.12},
    toggleThumb = {1, 1, 1, 1},

    warning = {0.961, 0.620, 0.043, 1},
}

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

    if type(self.RefreshCachedColors) == "function" then
        self:RefreshCachedColors()
    end
end
