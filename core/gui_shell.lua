local ADDON_NAME, ns = ...

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

local C = GUI.Colors

---------------------------------------------------------------------------
-- FONT PATH (central) — bundled Quazii font, resolved lazily so LSM / AssetPath
-- are ready regardless of core file load order. QUI_Options/framework.lua mirrors
-- this; defining it on the core GUI shell makes the path reachable suite-wide at
-- login (UIKit.CreateButton and other early factories resolve through it before
-- the Options addon loads).
---------------------------------------------------------------------------
function GUI:GetFontPath()
    if not self.FONT_PATH then
        local lsm = ns.LSM
        local helpers = ns.Helpers
        self.FONT_PATH = (lsm and type(lsm.Fetch) == "function" and lsm:Fetch("font", "Quazii"))
            or (helpers and helpers.AssetPath and (helpers.AssetPath .. "Quazii.ttf"))
            or [[Interface\AddOns\QUI\assets\Quazii.ttf]]
    end
    return self.FONT_PATH
end

ns.QUI_Options = ns.QUI_Options or {}
local Options = ns.QUI_Options
Options.PADDING = Options.PADDING or 15

local function GetOptionDelegate(name, fallback)
    local method = Options and Options[name]
    if type(method) == "function" and method ~= fallback then
        return method
    end
    return nil
end

local function GetDBCompat()
    local delegate = GetOptionDelegate("GetDB", GetDBCompat)
    if delegate then
        return delegate()
    end

    local addon = ns.Addon or (QUI and QUI.QUICore)
    return addon and addon.db and addon.db.profile or nil
end

local function BuildLSMList(kind, fallback)
    local list = {}
    local lsm = ns.LSM
    if lsm and type(lsm.List) == "function" then
        for _, name in ipairs(lsm:List(kind) or {}) do
            list[#list + 1] = { value = name, text = name }
        end
    end
    if #list == 0 and fallback then
        list[1] = fallback
    end
    return list
end

local function GetTextureListCompat()
    local delegate = GetOptionDelegate("GetTextureList", GetTextureListCompat)
    if delegate then
        return delegate()
    end
    return BuildLSMList("statusbar", { value = "Solid", text = "Solid" })
end

local function GetFontListCompat()
    local delegate = GetOptionDelegate("GetFontList", GetFontListCompat)
    if delegate then
        return delegate()
    end
    return BuildLSMList("font", { value = "Friz Quadrata TT", text = "Friz Quadrata TT" })
end

local function GetSoundListCompat()
    local delegate = GetOptionDelegate("GetSoundList", GetSoundListCompat)
    if delegate then
        return delegate()
    end
    return BuildLSMList("sound", { value = "None", text = "None" })
end

local function CreateScrollableContentCompat(parent)
    local delegate = GetOptionDelegate("CreateScrollableContent", CreateScrollableContentCompat)
    if delegate then
        return delegate(parent)
    end

    if parent then
        local scrollFrame = CreateFrame("ScrollFrame", nil, parent, "UIPanelScrollFrameTemplate")
        scrollFrame:SetPoint("TOPLEFT", parent, "TOPLEFT", 5, -5)
        scrollFrame:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -28, 5)

        local content = CreateFrame("Frame", nil, scrollFrame)
        content:SetSize(760, 1)
        scrollFrame:SetScrollChild(content)

        if ns.ApplyScrollWheel then
            ns.ApplyScrollWheel(scrollFrame)
        end

        return scrollFrame, content
    end
end

local function CreateWrappedLabelCompat(parent, text, size, color, maxWidth)
    local delegate = GetOptionDelegate("CreateWrappedLabel", CreateWrappedLabelCompat)
    if delegate then
        return delegate(parent, text, size, color, maxWidth)
    end

    local gui = QUI and QUI.GUI
    local label
    if gui and type(gui.CreateLabel) == "function" then
        label = gui:CreateLabel(parent, text or "", size or 12, color or C.text)
    elseif parent and parent.CreateFontString then
        label = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        label:SetText(text or "")
        if type(color) == "table" then
            label:SetTextColor(color[1] or 1, color[2] or 1, color[3] or 1, color[4] or 1)
        end
    end

    if label and maxWidth and label.SetWidth then
        label:SetWidth(maxWidth)
        if label.SetWordWrap then
            label:SetWordWrap(true)
        end
    end

    return label
end

local function CreateLinkItemCompat(parent, label, url, iconR, iconG, iconB, iconTexture, popupTitle)
    local delegate = GetOptionDelegate("CreateLinkItem", CreateLinkItemCompat)
    if delegate then
        return delegate(parent, label, url, iconR, iconG, iconB, iconTexture, popupTitle)
    end

    local button = CreateFrame("Button", nil, parent)
    button:SetSize(220, 22)
    button.text = CreateWrappedLabelCompat(button, label or url or "", 12, C.text)
    if button.text then
        button.text:SetPoint("LEFT", button, "LEFT", 0, 0)
        button.text:SetPoint("RIGHT", button, "RIGHT", 0, 0)
    end
    button:SetScript("OnClick", function()
        if StaticPopup_Show then
            StaticPopup_Show("QUI_COPY_TEXT", popupTitle or ns.L["Copy URL"], nil, url)
        elseif url then
            print("|cFF30D1FFQUI:|r " .. tostring(url))
        end
    end)
    return button
end

if type(Options.GetDB) ~= "function" then Options.GetDB = GetDBCompat end
if type(Options.GetTextureList) ~= "function" then Options.GetTextureList = GetTextureListCompat end
if type(Options.GetFontList) ~= "function" then Options.GetFontList = GetFontListCompat end
if type(Options.GetSoundList) ~= "function" then Options.GetSoundList = GetSoundListCompat end
if type(Options.CreateScrollableContent) ~= "function" then Options.CreateScrollableContent = CreateScrollableContentCompat end
if type(Options.CreateWrappedLabel) ~= "function" then Options.CreateWrappedLabel = CreateWrappedLabelCompat end
if type(Options.CreateLinkItem) ~= "function" then Options.CreateLinkItem = CreateLinkItemCompat end

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

function GUI:RefreshCachedColors()
end

function GUI:ApplyAccentColor(r, g, b)
    local function lerp(a, b2, t) return a + (b2 - a) * t end

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

function GUI:ResolveThemePreset(presetName)
    for _, preset in ipairs(self.ThemePresets or {}) do
        if preset.name == presetName then
            return preset.color[1], preset.color[2], preset.color[3]
        end
    end

    if presetName == "Class Colored" then
        local _, class = UnitClass("player")
        -- CUSTOM_CLASS_COLORS-aware via the shared helper (resolved at runtime)
        local color = ns.Helpers and ns.Helpers.GetClassColorTable(class)
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

local REQUIRED_WIDGET_API = {
    "CreateButton",
    "CreateSectionHeader",
    "CreateFormCheckbox",
    "CreateFormColorPicker",
    "CreateFormDropdown",
    "CreateFormSlider",
}

local function HasWidgetAPI(gui)
    if type(gui) ~= "table" then
        return false
    end

    for _, methodName in ipairs(REQUIRED_WIDGET_API) do
        if type(gui[methodName]) ~= "function" then
            return false
        end
    end

    return true
end

function GUI:HasWidgetAPI()
    return HasWidgetAPI(self)
end

function GUI:EnsureWidgetAPI()
    if HasWidgetAPI(self) then
        return self
    end

    if QUI and type(QUI.EnsureOptionsLoaded) == "function" then
        local ok, reason = QUI:EnsureOptionsLoaded()
        local gui = QUI.GUI or self
        if HasWidgetAPI(gui) then
            return gui
        end
        return nil, reason or "settings widgets unavailable"
    end

    return nil, "options loader unavailable"
end

local function ShellToggle()
    if QUI and type(QUI.OpenOptions) == "function" then
        return QUI:OpenOptions()
    end
end

local function ShellShow()
    if QUI and type(QUI.EnsureOptionsLoaded) == "function" then
        local ok = QUI:EnsureOptionsLoaded()
        local show = GUI.Show
        if ok and type(show) == "function" and show ~= ShellShow then
            return show(GUI)
        end
    end
end

local function ShellShowConfirmation(self, options)
    if QUI and type(QUI.EnsureOptionsLoaded) == "function" then
        local ok = QUI:EnsureOptionsLoaded()
        if ok and GUI.ShowConfirmation and GUI.ShowConfirmation ~= ShellShowConfirmation then
            return GUI:ShowConfirmation(options)
        end
    end

    if options and options.message then
        print("|cFF30D1FFQUI:|r " .. tostring(options.message))
    end
end

GUI.Toggle = GUI.Toggle or ShellToggle
GUI.Show = GUI.Show or ShellShow
GUI.ShowConfirmation = GUI.ShowConfirmation or ShellShowConfirmation
