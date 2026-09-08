local ADDON_NAME, ns = ...

QUI.GUI = QUI.GUI or {}
local GUI = QUI.GUI

-- Palette owner: core/theme.lua (QUI.toc loads it before this file). Every
-- role (bg*, accent*, tab*, text*, state ladder, scroll*) lives there.
assert(GUI.Colors, "core/theme.lua must load before core/gui_shell.lua (QUI.toc order)")
local C = GUI.Colors

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

function GUI:RefreshCachedColors()
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
        ---@type fun(...): ... -- GUI.Show is swapped in by the LoD Options addon
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
