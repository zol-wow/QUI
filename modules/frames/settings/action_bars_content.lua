local ADDON_NAME, ns = ...
local QUI = QUI
local GUI = QUI.GUI
local C = GUI.Colors
local Shared = ns.QUI_Options
local Opts = Shared  -- V3 body-pattern helpers

-- Local references
local PADDING = Shared.PADDING
local CreateScrollableContent = Shared.CreateScrollableContent
local GetDB = Shared.GetDB
local GetTextureList = Shared.GetTextureList
local GetFontList = Shared.GetFontList

local Helpers = ns.Helpers
local GetCore = Helpers.GetCore
local Settings = ns.Settings
local Registry = Settings and Settings.Registry
local Schema = Settings and Settings.Schema

---------------------------------------------------------------------------
-- SHARED CONTEXT & REFRESH CALLBACKS
---------------------------------------------------------------------------
local function ResolveContext()
    local db = GetDB()
    if not db or not db.actionBars then return nil end
    return {
        db = db,
        actionBars = db.actionBars,
        global = db.actionBars.global,
        fade = db.actionBars.fade,
        bars = db.actionBars.bars,
    }
end

local function RefreshActionBars()
    if _G.QUI_RefreshActionBars then _G.QUI_RefreshActionBars() end
end

-- Lightweight: only re-evaluate mouseover fade state (no full bar rebuild)
local function RefreshActionBarFade()
    if _G.QUI_RefreshActionBarFade then _G.QUI_RefreshActionBarFade() end
end

local function Unavailable(parent, label)
    local t = GUI:CreateLabel(parent, (label or "Action Bars") .. " settings not available. Please /reload.", 12, C.text)
    t:SetPoint("TOPLEFT", PADDING, -15)
end

---------------------------------------------------------------------------
-- PERSISTENT PREVIEW (tile-level, shared across all sub-tabs)
---------------------------------------------------------------------------
-- Called once by framework_v2 BuildTilePage via tile.config.preview.build.
-- Populates the preview frame with 10 action button mirrors + a bar
-- selector dropdown that picks which of bar 1-8 to mirror. Stays in sync
-- with live slot changes. Since it's built at the tile level (not the
-- sub-tab level), it persists across every sub-tab of Action Bars.
local BAR_OFFSETS = {
    bar1 = 0,    bar2 = 60,   bar3 = 48,   bar4 = 24,
    bar5 = 36,   bar6 = 144,  bar7 = 156,  bar8 = 168,
}
local BAR_OPTIONS = {
    { value = "bar1", text = "Bar 1" }, { value = "bar2", text = "Bar 2" },
    { value = "bar3", text = "Bar 3" }, { value = "bar4", text = "Bar 4" },
    { value = "bar5", text = "Bar 5" }, { value = "bar6", text = "Bar 6" },
    { value = "bar7", text = "Bar 7" }, { value = "bar8", text = "Bar 8" },
}
local BAR_BINDING_PREFIXES = {
    bar1 = "ACTIONBUTTON",
    bar2 = "MULTIACTIONBAR1BUTTON",
    bar3 = "MULTIACTIONBAR2BUTTON",
    bar4 = "MULTIACTIONBAR3BUTTON",
    bar5 = "MULTIACTIONBAR4BUTTON",
    bar6 = "MULTIACTIONBAR5BUTTON",
    bar7 = "MULTIACTIONBAR6BUTTON",
    bar8 = "MULTIACTIONBAR7BUTTON",
}
local PREVIEW_TEXTURE_PATH = [[Interface\AddOns\QUI\assets\iconskin\]]
local PREVIEW_TEXTURES = {
    normal = PREVIEW_TEXTURE_PATH .. "Normal",
    gloss = PREVIEW_TEXTURE_PATH .. "Gloss",
}
local MAX_PREVIEW_BUTTONS = 12
local SAMPLE_PREVIEW_KEYBINDS = { "1", "2", "3", "4", "R", "F", "C", "V", "Q", "E", "T", "G" }
local PreviewState = {
    bar = "bar1",
    refresh = nil,
}
local SelectedBarState = {
    key = "bar1",
}
local SelectedBarListeners = setmetatable({}, { __mode = "k" })

local function NotifySelectedBarChanged(origin)
    for owner, callback in pairs(SelectedBarListeners) do
        if owner and callback then
            local ok = pcall(callback, SelectedBarState.key, origin)
            if not ok then
                SelectedBarListeners[owner] = nil
            end
        end
    end
end

local function RegisterSelectedBarListener(owner, callback)
    if owner and type(callback) == "function" then
        SelectedBarListeners[owner] = callback
    end
end

local function GetSelectedBar()
    return SelectedBarState.key
end

local function SetSelectedBar(barKey, origin)
    if type(barKey) ~= "string" or barKey == "" then return end

    local changedSelection = SelectedBarState.key ~= barKey
    local changedPreview = BAR_OFFSETS[barKey] and PreviewState.bar ~= barKey

    SelectedBarState.key = barKey
    if BAR_OFFSETS[barKey] then
        PreviewState.bar = barKey
    end

    if changedSelection or changedPreview then
        NotifySelectedBarChanged(origin)
    end
end

local function FormatPreviewKeybind(keybind)
    if QUI and QUI.FormatKeybind then
        return QUI.FormatKeybind(keybind)
    end
    if ns and ns.FormatKeybind then
        return ns.FormatKeybind(keybind)
    end
    if not keybind then return nil end

    local upper = keybind:upper()
    upper = upper:gsub(" ", "")

    upper = upper:gsub("MOUSEWHEELUP", "WU")
    upper = upper:gsub("MOUSEWHEELDOWN", "WD")
    upper = upper:gsub("MIDDLEMOUSE", "B3")
    upper = upper:gsub("MIDDLEBUTTON", "B3")
    upper = upper:gsub("BUTTON(%d+)", "B%1")

    upper = upper:gsub("SHIFT%-", "S")
    upper = upper:gsub("CTRL%-", "C")
    upper = upper:gsub("ALT%-", "A")
    upper = upper:gsub("^S%-(.+)", "S%1")
    upper = upper:gsub("^C%-(.+)", "C%1")
    upper = upper:gsub("^A%-(.+)", "A%1")

    upper = upper:gsub("NUMPADPLUS", "N+")
    upper = upper:gsub("NUMPADMINUS", "N-")
    upper = upper:gsub("NUMPADMULTIPLY", "N*")
    upper = upper:gsub("NUMPADDIVIDE", "N/")
    upper = upper:gsub("NUMPADPERIOD", "N.")
    upper = upper:gsub("NUMPADENTER", "NE")

    upper = upper:gsub("NUMPAD", "N")
    upper = upper:gsub("CAPSLOCK", "CAP")
    upper = upper:gsub("DELETE", "DEL")
    upper = upper:gsub("ESCAPE", "ESC")
    upper = upper:gsub("BACKSPACE", "BS")
    upper = upper:gsub("SPACE", "SP")
    upper = upper:gsub("INSERT", "INS")
    upper = upper:gsub("PAGEUP", "PU")
    upper = upper:gsub("PAGEDOWN", "PD")
    upper = upper:gsub("HOME", "HM")
    upper = upper:gsub("END", "ED")
    upper = upper:gsub("PRINTSCREEN", "PS")
    upper = upper:gsub("SCROLLLOCK", "SL")
    upper = upper:gsub("PAUSE", "PA")
    upper = upper:gsub("TILDE", "`")
    upper = upper:gsub("GRAVE", "`")

    upper = upper:gsub("UPARROW", "UP")
    upper = upper:gsub("DOWNARROW", "DN")
    upper = upper:gsub("LEFTARROW", "LF")
    upper = upper:gsub("RIGHTARROW", "RT")

    upper = upper:gsub("SEMICOLON", ";")
    upper = upper:gsub("APOSTROPHE", "'")
    upper = upper:gsub("LEFTBRACKET", "[")
    upper = upper:gsub("RIGHTBRACKET", "]")
    upper = upper:gsub("BACKSLASH", "\\")
    upper = upper:gsub("MINUS", "-")
    upper = upper:gsub("EQUALS", "=")
    upper = upper:gsub("COMMA", ",")
    upper = upper:gsub("^PERIOD$", ".")
    upper = upper:gsub("SLASH", "/")

    if #upper > 4 then
        upper = upper:sub(1, 4)
    end

    return upper
end

local function IsPreviewSecretValue(value)
    return Helpers and Helpers.IsSecretValue and Helpers.IsSecretValue(value) or false
end

local function HasPreviewTextValue(value)
    if value == nil then
        return false
    end
    if IsPreviewSecretValue(value) then
        return true
    end
    return value ~= ""
end

local function GetPreviewEffectiveSettings(barKey)
    local ctx = ResolveContext()
    if not ctx then return nil, nil end

    local effective = {}
    if ctx.global then
        for key, value in pairs(ctx.global) do
            effective[key] = value
        end
    end

    local barDB = ctx.bars and ctx.bars[barKey]
    if barDB then
        for key, value in pairs(barDB) do
            effective[key] = value
        end
    end

    return effective, barDB
end

local function GetPreviewSlot(barKey, index)
    local buttons = ns.ActionBarsOwned
        and ns.ActionBarsOwned.nativeButtons
        and ns.ActionBarsOwned.nativeButtons[barKey]
    local button = buttons and buttons[index]
    local liveAction = button and button.action
    if Helpers.SafeValue then
        liveAction = Helpers.SafeValue(liveAction, nil)
    end
    local numericAction = liveAction and tonumber(liveAction)
    if numericAction and numericAction > 0 then
        return numericAction
    end

    local offset = BAR_OFFSETS[barKey] or 0
    return offset + index
end

local function GetPreviewSourceButton(barKey, index)
    local buttons = ns.ActionBarsOwned
        and ns.ActionBarsOwned.nativeButtons
        and ns.ActionBarsOwned.nativeButtons[barKey]
    return buttons and buttons[index] or nil
end

local function GetPreviewActionSlot(slot, sourceButton)
    local liveAction = sourceButton and sourceButton.action
    if Helpers.SafeValue then
        liveAction = Helpers.SafeValue(liveAction, nil)
    end

    local numericAction = liveAction and tonumber(liveAction)
    if numericAction and numericAction > 0 then
        return numericAction
    end

    return slot
end

local function GetPreviewDisplayedTexture(slot, sourceButton)
    local icon = sourceButton and (sourceButton.icon or sourceButton.Icon)
    if icon and icon.IsShown and icon:GetObjectType() == "Texture" and icon:IsShown() and icon.GetTexture then
        local displayed = icon:GetTexture()
        if displayed then
            return displayed
        end
    end

    return slot and GetActionTexture and GetActionTexture(slot) or nil
end

local function GetPreviewFontSettings()
    local fontPath = "Fonts\\FRIZQT__.TTF"
    local outline = "OUTLINE"
    local core = GetCore()
    local general = core and core.db and core.db.profile and core.db.profile.general
    if general then
        if general.font and ns.LSM then
            fontPath = ns.LSM:Fetch("font", general.font) or fontPath
        end
        outline = general.fontOutline or outline
    end
    return fontPath, outline
end

local function GetPreviewBindingText(barKey, index, sourceButton)
    local hotkey = sourceButton and (sourceButton.HotKey or sourceButton.hotKey)
    local displayed = hotkey and hotkey.GetText and hotkey:GetText() or nil
    if IsPreviewSecretValue(displayed) then
        return displayed
    end
    if type(displayed) == "string" and displayed ~= "" then
        return displayed
    end

    local prefix = BAR_BINDING_PREFIXES[barKey]
    if not prefix or not GetBindingKey then return nil end

    local binding = GetBindingKey(prefix .. index)
    return FormatPreviewKeybind(binding)
end

local function GetPreviewMacroText(slot, sourceButton)
    local actionSlot = GetPreviewActionSlot(slot, sourceButton)
    local displayed = sourceButton and sourceButton.Name and sourceButton.Name.GetText and sourceButton.Name:GetText() or nil
    if IsPreviewSecretValue(displayed) then
        return displayed
    end
    if type(displayed) == "string" and displayed ~= "" then
        return displayed
    end

    if not actionSlot or not GetActionText then return nil end

    local ok, text = pcall(GetActionText, actionSlot)
    if not ok then return nil end

    if IsPreviewSecretValue(text) then
        return text
    end
    if type(text) == "string" and text ~= "" then
        return text
    end
    return nil
end

local function GetPreviewCountText(slot, sourceButton)
    local actionSlot = GetPreviewActionSlot(slot, sourceButton)
    local displayed = sourceButton and sourceButton.Count and sourceButton.Count.GetText and sourceButton.Count:GetText() or nil
    if IsPreviewSecretValue(displayed) then
        return displayed
    end
    if type(displayed) == "string" and displayed ~= "" then
        return displayed
    end

    if not actionSlot or not (C_ActionBar and C_ActionBar.GetActionDisplayCount) then
        return nil
    end

    local ok, count = pcall(C_ActionBar.GetActionDisplayCount, actionSlot)
    if not ok then return nil end

    if IsPreviewSecretValue(count) then
        return count
    end
    if count == nil or count == "" or count == 0 or count == "0" then
        return nil
    end

    return tostring(count)
end

local function SetPreviewTextStyle(fontString, button, text, fontPath, outline, fontSize, color, anchor, offsetX, offsetY)
    if not fontString then return end
    local isSecretText = IsPreviewSecretValue(text)
    if text == nil or (not isSecretText and text == "") then
        fontString:SetText("")
        fontString:SetAlpha(0)
        fontString:Hide()
        return
    end

    if not isSecretText and type(text) ~= "string" then
        text = tostring(text)
    end

    local width = math.max((button:GetWidth() or 0) - 4, 1)
    local height = math.max((fontSize or 10) + 4, 1)
    local point = anchor or "CENTER"

    fontString:SetFont(fontPath, fontSize or 10, outline or "OUTLINE")
    fontString:SetText(text)
    fontString:SetWidth(width)
    fontString:SetHeight(height)
    fontString:ClearAllPoints()
    fontString:SetPoint(point, button, point, offsetX or 0, offsetY or 0)

    if point:find("LEFT") then
        fontString:SetJustifyH("LEFT")
    elseif point:find("RIGHT") then
        fontString:SetJustifyH("RIGHT")
    else
        fontString:SetJustifyH("CENTER")
    end

    if point:find("TOP") then
        fontString:SetJustifyV("TOP")
    elseif point:find("BOTTOM") then
        fontString:SetJustifyV("BOTTOM")
    else
        fontString:SetJustifyV("MIDDLE")
    end

    local r = color and color[1] or 1
    local g = color and color[2] or 1
    local b = color and color[3] or 1
    local a = color and color[4] or 1
    fontString:SetTextColor(r, g, b, a)
    fontString:SetAlpha(1)
    fontString:Show()
end

local function SetActionBarsPreviewBar(barKey)
    if not BAR_OFFSETS[barKey] then return end
    SetSelectedBar(barKey, "preview")
    if PreviewState.refresh then PreviewState.refresh() end
end

local function BuildActionBarsPreview(pv)
    local accent = C.accent or { 0.204, 0.827, 0.6, 1 }
    local border = (GUI.Colors and GUI.Colors.border) or { 1, 1, 1, 0.06 }

    local selectedBar = GetSelectedBar()
    if BAR_OFFSETS[selectedBar] then
        PreviewState.bar = selectedBar
    end

    local fill = pv:CreateTexture(nil, "BACKGROUND")
    fill:SetAllPoints(pv)
    fill:SetColorTexture(0, 0, 0, 0.2)

    if ns.UIKit and ns.UIKit.CreateBorderLines then
        ns.UIKit.CreateBorderLines(pv)
        ns.UIKit.UpdateBorderLines(pv, 1, border[1], border[2], border[3], 0.15, false)
    end

    local lbl = pv:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    local fpath = ns.UIKit and ns.UIKit.ResolveFontPath and ns.UIKit.ResolveFontPath(GUI:GetFontPath())
    lbl:SetFont(fpath or select(1, lbl:GetFont()), 8, "")
    lbl:SetTextColor(accent[1], accent[2], accent[3], 0.7)
    lbl:SetPoint("TOPLEFT", pv, "TOPLEFT", 8, -6)
    local spaced = ("PREVIEW"):gsub(".", "%0 "):sub(1, -2)
    lbl:SetText(spaced)

    local previewButtons = {}
    local previewHost = CreateFrame("Frame", nil, pv)
    previewHost:SetPoint("TOPLEFT", pv, "TOPLEFT", 12, -30)
    previewHost:SetPoint("TOPRIGHT", pv, "TOPRIGHT", -12, -30)
    previewHost:SetPoint("BOTTOM", pv, "BOTTOM", 0, 12)

    -- Each preview button bundles all the visual pieces that QUI's real
    -- SkinButton applies, so the tile preview reflects the real bar skin.
    for i = 1, MAX_PREVIEW_BUTTONS do
        local b = CreateFrame("Frame", nil, previewHost)

        local backdrop = b:CreateTexture(nil, "BACKGROUND", nil, -8)
        backdrop:SetAllPoints(b)
        backdrop:SetColorTexture(0, 0, 0, 1)

        local icon = b:CreateTexture(nil, "ARTWORK")
        icon:SetAllPoints(b)

        local normal = b:CreateTexture(nil, "OVERLAY", nil, 1)
        normal:SetAllPoints(b)
        normal:SetTexture(PREVIEW_TEXTURES.normal)
        normal:SetVertexColor(0, 0, 0, 1)

        local gloss = b:CreateTexture(nil, "OVERLAY", nil, 2)
        gloss:SetAllPoints(b)
        gloss:SetTexture(PREVIEW_TEXTURES.gloss)
        gloss:SetBlendMode("ADD")
        gloss:Hide()

        local hotkey = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        hotkey:SetWordWrap(false)
        hotkey:SetShadowOffset(1, -1)
        if hotkey.SetMaxLines then hotkey:SetMaxLines(1) end

        local name = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        name:SetWordWrap(false)
        name:SetShadowOffset(1, -1)
        if name.SetMaxLines then name:SetMaxLines(1) end

        local count = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        count:SetWordWrap(false)
        count:SetShadowOffset(1, -1)
        if count.SetMaxLines then count:SetMaxLines(1) end

        previewButtons[i] = {
            frame    = b,
            icon     = icon,
            backdrop = backdrop,
            normal   = normal,
            gloss    = gloss,
            hotkey   = hotkey,
            name     = name,
            count    = count,
        }
    end

    -- RefreshPreview applies every QUI setting we can visually reflect
    -- without a real ActionButton template: layout, icon zoom, backdrop,
    -- gloss, borders, and range/usability tint. Runs on every event +
    -- OnUpdate tick so it stays in sync with live slot changes and with
    -- the selected bar's current per-bar settings.
    local function RefreshPreview()
        local settings, barDB = GetPreviewEffectiveSettings(PreviewState.bar)
        settings = settings or {}

        local layout = barDB and barDB.ownedLayout or {}
        local requestedVisible = math.max(1, math.min(layout.iconCount or MAX_PREVIEW_BUTTONS, MAX_PREVIEW_BUTTONS))
        local previewSlots = {}
        local hasAnyTexture = false

        for i = 1, requestedVisible do
            local sourceButton = GetPreviewSourceButton(PreviewState.bar, i)
            local slot = GetPreviewSlot(PreviewState.bar, i)
            local tex = GetPreviewDisplayedTexture(slot, sourceButton)
            if tex then
                hasAnyTexture = true
            end

            previewSlots[i] = {
                index = i,
                slot = slot,
                sourceButton = sourceButton,
                texture = tex,
                hiddenEmpty = settings.hideEmptySlots and not tex,
            }
        end

        -- Keep one placeholder visible on completely empty bars so the tile
        -- preview does not disappear while tuning layout settings.
        if not hasAnyTexture and previewSlots[1] then
            previewSlots[1].hiddenEmpty = false
        end

        local visibleCount = math.min(requestedVisible, MAX_PREVIEW_BUTTONS)
        local buttonSize = math.max(20, layout.buttonSize or 30)
        local buttonSpacing = layout.buttonSpacing or 0
        local columns = math.max(1, math.min(layout.columns or visibleCount, visibleCount))
        local isVertical = layout.orientation == "vertical"
        local growLeft = layout.growLeft == true
        local growUp = layout.growUp == true
        local xStep = buttonSize + buttonSpacing
        local yStep = buttonSize + buttonSpacing
        local positions = {}
        local minX, maxX, minY, maxY

        for i = 1, visibleCount do
            local primary = (i - 1) % columns
            local secondary = math.floor((i - 1) / columns)
            local col = isVertical and secondary or primary
            local row = isVertical and primary or secondary
            local x = col * xStep
            local y = row * yStep

            if growLeft then
                x = -x
            end
            if not growUp then
                y = -y
            end

            positions[i] = { x = x, y = y }
            minX = (not minX or x < minX) and x or minX
            maxX = (not maxX or x > maxX) and x or maxX
            minY = (not minY or y < minY) and y or minY
            maxY = (not maxY or y > maxY) and y or maxY
        end

        local centerX = ((minX or 0) + (maxX or 0)) / 2
        local centerY = ((minY or 0) + (maxY or 0)) / 2
        local skinEnabled = settings.skinEnabled ~= false
        local zoom = skinEnabled and (settings.iconZoom or 0.05) or 0
        local showBackdrop = skinEnabled and settings.showBackdrop ~= false
        local backdropAlpha = settings.backdropAlpha or 0.2
        local showGloss = skinEnabled and settings.showGloss ~= false
        local glossAlpha = settings.glossAlpha or 0.3
        local showBorders = skinEnabled and settings.showBorders ~= false
        local rangeColor = settings.rangeColor or { 0.8, 0.1, 0.1, 1 }
        local usabColor = settings.usabilityColor or { 0.4, 0.4, 0.4, 1 }
        local manaColor = settings.manaColor or { 0.5, 0.5, 1.0, 1 }
        local fontPath, outline = GetPreviewFontSettings()
        local hasVisibleKeybind = false

        for i = 1, visibleCount do
            local slotInfo = previewSlots[i]
            if slotInfo then
                slotInfo.binding = GetPreviewBindingText(PreviewState.bar, slotInfo.index, slotInfo.sourceButton)
                slotInfo.macro = GetPreviewMacroText(slotInfo.slot, slotInfo.sourceButton)
                slotInfo.count = GetPreviewCountText(slotInfo.slot, slotInfo.sourceButton)
                hasVisibleKeybind = hasVisibleKeybind or (not slotInfo.hiddenEmpty and HasPreviewTextValue(slotInfo.binding))
            end
        end

        if settings.showKeybinds and not hasVisibleKeybind then
            for i = 1, visibleCount do
                local slotInfo = previewSlots[i]
                if slotInfo and slotInfo.texture and not HasPreviewTextValue(slotInfo.binding) then
                    slotInfo.binding = SAMPLE_PREVIEW_KEYBINDS[i] or SAMPLE_PREVIEW_KEYBINDS[((i - 1) % #SAMPLE_PREVIEW_KEYBINDS) + 1]
                end
            end
        end

        for i = 1, #previewButtons do
            local pb = previewButtons[i]
            local slotInfo = previewSlots[i]

            if not slotInfo then
                pb.frame:Hide()
                pb.hotkey:Hide()
                pb.name:Hide()
                pb.count:Hide()
            else
                local pos = positions[i]
                local tex = slotInfo.texture
                pb.frame:SetSize(buttonSize, buttonSize)
                pb.frame:ClearAllPoints()
                pb.frame:SetPoint("CENTER", previewHost, "CENTER", pos.x - centerX, pos.y - centerY)

                if slotInfo.hiddenEmpty then
                    pb.frame:Hide()
                    pb.hotkey:Hide()
                    pb.name:Hide()
                    pb.count:Hide()
                else
                    pb.frame:Show()

                    if tex then
                        pb.icon:SetTexture(tex)
                        pb.icon:SetTexCoord(zoom, 1 - zoom, zoom, 1 - zoom)
                        pb.icon:Show()

                        local isUsable, notEnoughMana, inRange = true, false, true
                        if IsUsableAction and slotInfo.slot then
                            isUsable, notEnoughMana = IsUsableAction(slotInfo.slot)
                        end
                        if IsActionInRange and slotInfo.slot then
                            local rangeState = IsActionInRange(slotInfo.slot)
                            inRange = not (rangeState == false or rangeState == 0)
                        end

                        if settings.rangeIndicator and not inRange then
                            pb.icon:SetVertexColor(rangeColor[1], rangeColor[2], rangeColor[3], 1)
                        elseif settings.usabilityIndicator and notEnoughMana then
                            pb.icon:SetVertexColor(manaColor[1], manaColor[2], manaColor[3], 1)
                        elseif settings.usabilityIndicator and not isUsable then
                            pb.icon:SetVertexColor(usabColor[1], usabColor[2], usabColor[3], 1)
                        else
                            pb.icon:SetVertexColor(1, 1, 1, 1)
                        end
                        pb.icon:SetAlpha(1)
                    else
                        pb.icon:SetTexture(nil)
                        pb.icon:SetTexCoord(0, 1, 0, 1)
                        pb.icon:SetVertexColor(1, 1, 1, 1)
                        pb.icon:SetAlpha(0)
                        pb.icon:Hide()
                    end

                    if showBackdrop then
                        pb.backdrop:SetAlpha(backdropAlpha)
                        pb.backdrop:Show()
                    else
                        pb.backdrop:Hide()
                    end

                    if showBorders then
                        pb.normal:Show()
                    else
                        pb.normal:Hide()
                    end

                    if showGloss then
                        pb.gloss:SetVertexColor(1, 1, 1, glossAlpha)
                        pb.gloss:Show()
                    else
                        pb.gloss:Hide()
                    end

                    if not skinEnabled then
                        pb.backdrop:Hide()
                        pb.normal:Hide()
                        pb.gloss:Hide()
                        pb.icon:SetTexCoord(0, 1, 0, 1)
                    end

                    local bindingText = slotInfo.binding
                    if settings.hideEmptyKeybinds and not tex then
                        bindingText = nil
                    end

                    SetPreviewTextStyle(
                        pb.hotkey, pb.frame, settings.showKeybinds and bindingText or nil,
                        fontPath, outline, settings.keybindFontSize or 11, settings.keybindColor,
                        settings.keybindAnchor or "TOPRIGHT",
                        settings.keybindOffsetX or 0, settings.keybindOffsetY or 0
                    )
                    SetPreviewTextStyle(
                        pb.name, pb.frame, settings.showMacroNames and slotInfo.macro or nil,
                        fontPath, outline, settings.macroNameFontSize or 10, settings.macroNameColor,
                        settings.macroNameAnchor or "BOTTOM",
                        settings.macroNameOffsetX or 0, settings.macroNameOffsetY or 0
                    )
                    SetPreviewTextStyle(
                        pb.count, pb.frame, settings.showCounts and slotInfo.count or nil,
                        fontPath, outline, settings.countFontSize or 14, settings.countColor,
                        settings.countAnchor or "BOTTOMRIGHT",
                        settings.countOffsetX or 0, settings.countOffsetY or 0
                    )
                end
            end
        end
    end
    PreviewState.refresh = RefreshPreview
    RefreshPreview()

    local selector = GUI:CreateFormDropdown(pv, nil, BAR_OPTIONS,
        "bar", PreviewState, function(val)
            SetActionBarsPreviewBar(val)
        end,
        { description = "Pick which action bar the preview panel renders. This only affects the preview above — it does not change any saved settings." })
    selector:ClearAllPoints()
    selector:SetPoint("TOPRIGHT", pv, "TOPRIGHT", -8, -4)
    selector:SetSize(80, 22)

    RegisterSelectedBarListener(pv, function(barKey, origin)
        if not BAR_OFFSETS[barKey] then return end
        PreviewState.bar = barKey
        if selector and selector.SetValue then
            selector.SetValue(barKey, true)
        end
        if origin ~= "preview" then
            RefreshPreview()
        end
    end)

    pv:RegisterEvent("ACTIONBAR_SLOT_CHANGED")
    pv:RegisterEvent("UPDATE_BINDINGS")
    pv:RegisterEvent("PLAYER_ENTERING_WORLD")
    pv:SetScript("OnEvent", function() RefreshPreview() end)

    -- Throttled OnUpdate picks up setting changes from the sub-tabs
    -- below without us having to hook every onChange callback. Every
    -- 0.25s is imperceptible latency for a visual preview.
    local _accum = 0
    pv:SetScript("OnUpdate", function(self, elapsed)
        _accum = _accum + elapsed
        if _accum < 0.25 then return end
        _accum = 0
        RefreshPreview()
    end)
end

---------------------------------------------------------------------------
-- SUB-TAB: General (section layout with mixed 2-col)
---------------------------------------------------------------------------
local function BuildMasterSettingsTab(tabContent)
    local ctx = ResolveContext()
    if not ctx then Unavailable(tabContent, "Action Bars"); return end
    local actionBars, global = ctx.actionBars, ctx.global

    local PAD = PADDING
    local HEADER_GAP = 26
    local SECTION_GAP = 14

    GUI:SetSearchContext({tabIndex = 8, tabName = "Action Bars", subTabIndex = 1, subTabName = "General"})

    local y = -10

    local function headerAt(text)
        local h = Opts.CreateAccentDotLabel(tabContent, text, y)
        h:ClearAllPoints()
        h:SetPoint("TOPLEFT", tabContent, "TOPLEFT", PAD, y)
        h:SetPoint("TOPRIGHT", tabContent, "TOPRIGHT", -PAD, y)
        y = y - HEADER_GAP
    end
    local function sectionAt()
        local c = Opts.CreateSettingsCardGroup(tabContent, y)
        c.frame:ClearAllPoints()
        c.frame:SetPoint("TOPLEFT", tabContent, "TOPLEFT", PAD, y)
        c.frame:SetPoint("TOPRIGHT", tabContent, "TOPRIGHT", -PAD, y)
        return c
    end
    local function closeSection(c)
        c.Finalize()
        y = y - c.frame:GetHeight() - SECTION_GAP
    end

    -- Button lock proxy (CVar-backed dropdown)
    local lockOptions = {
        {value = "unlocked", text = "Unlocked"},
        {value = "shift", text = "Locked - Shift to drag"},
        {value = "alt", text = "Locked - Alt to drag"},
        {value = "ctrl", text = "Locked - Ctrl to drag"},
        {value = "none", text = "Fully Locked"},
    }
    local lockProxy = setmetatable({}, {
        __index = function(t, k)
            if k == "buttonLock" then
                local isLocked = GetCVar("lockActionBars") == "1"
                if not isLocked then return "unlocked" end
                local modifier = GetModifiedClick("PICKUPACTION") or "SHIFT"
                if modifier == "NONE" then return "none" end
                return modifier:lower()
            end
        end,
        __newindex = function(t, k, v)
            if InCombatLockdown() then return end
            if k == "buttonLock" and type(v) == "string" then
                if v == "unlocked" then SetCVar("lockActionBars", "0")
                else
                    SetCVar("lockActionBars", "1")
                    SetModifiedClick("PICKUPACTION", (v == "none") and "NONE" or v:upper())
                    SaveBindings(GetCurrentBindingSet())
                end
            end
        end
    })

    -- GENERAL (mixed types paired for space efficiency)
    headerAt("General")
    local s1 = sectionAt()

    local enableW = GUI:CreateFormToggle(s1.frame, nil, "enabled", actionBars, function()
        GUI:ShowConfirmation({
            title = "Reload Required",
            message = "Action Bar styling requires a UI reload to take effect.",
            acceptText = "Reload Now", cancelText = "Later",
            onAccept = function() QUI:SafeReload() end,
        })
    end, { description = "Enable QUI's action bar styling. Requires a UI reload to take effect." })
    local lockDD = GUI:CreateFormDropdown(s1.frame, nil, lockOptions,
        "buttonLock", lockProxy, RefreshActionBars,
        { description = "Control whether action buttons can be dragged. Choose a modifier to unlock them on the fly or lock the bars fully." })
    lockDD:HookScript("OnShow", function(self) self.SetValue(lockProxy.buttonLock, true) end)
    s1.AddRow(
        Opts.BuildSettingRow(s1.frame, "Enable Action Bars", enableW),
        Opts.BuildSettingRow(s1.frame, "Button Lock", lockDD)
    )

    local showTipsW = GUI:CreateFormToggle(s1.frame, nil, "showTooltips", global, nil,
        { description = "Show the ability tooltip when hovering an action button." })
    local hideEmptyW = GUI:CreateFormToggle(s1.frame, nil, "hideEmptySlots", global, RefreshActionBars,
        { description = "Hide empty action slots so only buttons with abilities are visible." })
    s1.AddRow(
        Opts.BuildSettingRow(s1.frame, "Show Tooltips", showTipsW),
        Opts.BuildSettingRow(s1.frame, "Hide Empty Slots", hideEmptyW)
    )

    local qualityW = GUI:CreateFormToggle(s1.frame, nil, "showProfessionQuality", global, RefreshActionBars,
        { description = "Show a quality indicator on profession items placed on action bars." })
    local keyPressW = GUI:CreateFormToggle(s1.frame, nil, "useOnKeyDown", global, function()
        if _G.QUI_ApplyUseOnKeyDown then _G.QUI_ApplyUseOnKeyDown() end
    end, { description = "Cast abilities on key press instead of key release for lower input latency." })
    s1.AddRow(
        Opts.BuildSettingRow(s1.frame, "Show Crafted Item Quality", qualityW),
        Opts.BuildSettingRow(s1.frame, "Cast on Key Press", keyPressW)
    )

    local assistW = GUI:CreateFormToggle(s1.frame, nil, "assistedHighlight", global, function()
        if ns.ActionBarsOwned and ns.ActionBarsOwned.UpdateAllAssistedHighlights then
            ns.ActionBarsOwned.UpdateAllAssistedHighlights()
        end
    end, { description = "Highlight the suggested next ability based on your class rotation." })
    s1.AddRow(Opts.BuildSettingRow(s1.frame, "Rotation Assist", assistW))

    closeSection(s1)

    -- RANGE & USABILITY (mixed: toggle + color picker paired row)
    headerAt("Range & Usability")
    local s2 = sectionAt()

    local rangeW = GUI:CreateFormToggle(s2.frame, nil, "rangeIndicator", global, RefreshActionBars,
        { description = "Tint action buttons when your target is out of range." })
    local rangeColorW = GUI:CreateFormColorPicker(s2.frame, nil, "rangeColor", global, RefreshActionBars, nil,
        { description = "Color applied to buttons when the target is out of range." })
    s2.AddRow(
        Opts.BuildSettingRow(s2.frame, "Out of Range Indicator", rangeW),
        Opts.BuildSettingRow(s2.frame, "Out of Range Color", rangeColorW)
    )

    local unusableW = GUI:CreateFormToggle(s2.frame, nil, "usabilityIndicator", global, RefreshActionBars,
        { description = "Dim action buttons when their ability can't currently be cast." })
    local unusableColorW = GUI:CreateFormColorPicker(s2.frame, nil, "usabilityColor", global, RefreshActionBars, nil,
        { description = "Color overlay applied to unusable action buttons." })
    s2.AddRow(
        Opts.BuildSettingRow(s2.frame, "Dim Unusable Buttons", unusableW),
        Opts.BuildSettingRow(s2.frame, "Unusable Color", unusableColorW)
    )

    local fastW = GUI:CreateFormToggle(s2.frame, nil, "fastUsabilityUpdates", global, RefreshActionBars,
        { description = "Update range and usability every frame instead of on a timer. Higher accuracy, slight CPU cost." })
    local manaColorW = GUI:CreateFormColorPicker(s2.frame, nil, "manaColor", global, RefreshActionBars, nil,
        { description = "Color applied to buttons when you lack the mana or resource to cast." })
    s2.AddRow(
        Opts.BuildSettingRow(s2.frame, "Unthrottled CPU", fastW),
        Opts.BuildSettingRow(s2.frame, "Out of Mana Color", manaColorW)
    )

    closeSection(s2)

    -- QUICK KEYBIND
    headerAt("Quick Keybind")
    local s3 = sectionAt()

    local keybindBtn = GUI:CreateButton(s3.frame, "Toggle Keybind Mode", 160, 24, function()
        if InCombatLockdown() then return end
        local LibKeyBound = LibStub("LibKeyBound-1.0", true)
        if LibKeyBound then LibKeyBound:Toggle()
        elseif QuickKeybindFrame then ShowUIPanel(QuickKeybindFrame) end
    end)
    s3.AddRow(Opts.BuildSettingRow(s3.frame,
        "Keybind Mode", keybindBtn,
        "Show keybind overlays on action buttons"))

    closeSection(s3)

    tabContent:SetHeight(math.abs(y) + 40)
end

---------------------------------------------------------------------------
-- SUB-TAB: Mouseover Hide (section layout with mixed 2-col pairing)
---------------------------------------------------------------------------
local function BuildMouseoverHideTab(tabContent)
    local ctx = ResolveContext()
    if not ctx then Unavailable(tabContent, "Mouseover Hide"); return end
    local fade, bars = ctx.fade, ctx.bars

    local PAD = PADDING
    local HEADER_GAP = 26
    local SECTION_GAP = 14

    GUI:SetSearchContext({tabIndex = 8, tabName = "Action Bars", subTabIndex = 2, subTabName = "Mouseover Hide"})

    local y = -10

    local function headerAt(text)
        local h = Opts.CreateAccentDotLabel(tabContent, text, y)
        h:ClearAllPoints()
        h:SetPoint("TOPLEFT", tabContent, "TOPLEFT", PAD, y)
        h:SetPoint("TOPRIGHT", tabContent, "TOPRIGHT", -PAD, y)
        y = y - HEADER_GAP
    end
    local function sectionAt()
        local c = Opts.CreateSettingsCardGroup(tabContent, y)
        c.frame:ClearAllPoints()
        c.frame:SetPoint("TOPLEFT", tabContent, "TOPLEFT", PAD, y)
        c.frame:SetPoint("TOPRIGHT", tabContent, "TOPRIGHT", -PAD, y)
        return c
    end
    local function closeSection(c)
        c.Finalize()
        y = y - c.frame:GetHeight() - SECTION_GAP
    end

    -- FADE SETTINGS (mixed pairing: toggle+slider, slider+slider, toggle+toggle)
    headerAt("Fade Settings")
    local s1 = sectionAt()

    local enableW = GUI:CreateFormToggle(s1.frame, nil, "enabled", fade, RefreshActionBarFade,
        { description = "Fade action bars when you're not hovering over them. Hover to reveal." })
    local alphaW = GUI:CreateFormSlider(s1.frame, nil, 0, 1, 0.05, "fadeOutAlpha", fade, RefreshActionBarFade,
        { description = "Opacity of action bars when faded out. 0 is fully invisible, 1 is fully opaque." })
    s1.AddRow(
        Opts.BuildSettingRow(s1.frame, "Enable Mouseover Hide", enableW),
        Opts.BuildSettingRow(s1.frame, "Faded Opacity", alphaW)
    )

    local inW = GUI:CreateFormSlider(s1.frame, nil, 0.1, 1.0, 0.05, "fadeInDuration", fade, RefreshActionBarFade,
        { description = "How many seconds the fade-in animation takes when your cursor enters a bar." })
    local outW = GUI:CreateFormSlider(s1.frame, nil, 0.1, 1.0, 0.05, "fadeOutDuration", fade, RefreshActionBarFade,
        { description = "How many seconds the fade-out animation takes when your cursor leaves a bar." })
    s1.AddRow(
        Opts.BuildSettingRow(s1.frame, "Fade In Speed", inW),
        Opts.BuildSettingRow(s1.frame, "Fade Out Speed", outW)
    )

    local delayW = GUI:CreateFormSlider(s1.frame, nil, 0, 2.0, 0.1, "fadeOutDelay", fade, RefreshActionBarFade,
        { description = "Delay in seconds between your cursor leaving a bar and the fade-out starting." })
    local linkW = GUI:CreateFormToggle(s1.frame, nil, "linkBars1to8", fade, RefreshActionBarFade,
        { description = "Treat bars 1-8 as a single group so hovering any one shows all of them together." })
    s1.AddRow(
        Opts.BuildSettingRow(s1.frame, "Fade Out Delay", delayW),
        Opts.BuildSettingRow(s1.frame, "Link Bars 1-8", linkW)
    )

    local combatW = GUI:CreateFormToggle(s1.frame, nil, "alwaysShowInCombat", fade, RefreshActionBarFade,
        { description = "Keep action bars fully visible while you are in combat, overriding the fade." })
    local sbookW = GUI:CreateFormToggle(s1.frame, nil, "showWhenSpellBookOpen", fade, RefreshActionBarFade,
        { description = "Keep bars visible while the spellbook is open, so you can drag-and-drop abilities." })
    s1.AddRow(
        Opts.BuildSettingRow(s1.frame, "Do Not Hide In Combat", combatW),
        Opts.BuildSettingRow(s1.frame, "Show While Spellbook Open", sbookW)
    )

    local vehicleW = GUI:CreateFormToggle(s1.frame, nil, "keepLeaveVehicleVisible", fade, RefreshActionBarFade,
        { description = "Keep the Leave Vehicle button visible even when the rest of the bar is faded." })
    local levelW = GUI:CreateFormToggle(s1.frame, nil, "disableBelowMaxLevel", fade, RefreshActionBarFade,
        { description = "Disable mouseover fade on non-max-level characters, where full bars are easier to learn." })
    s1.AddRow(
        Opts.BuildSettingRow(s1.frame, "Keep Leave Vehicle Visible", vehicleW),
        Opts.BuildSettingRow(s1.frame, "Disable Below Max Level", levelW)
    )

    closeSection(s1)

    -- ALWAYS SHOW BARS (paired 2-up throughout)
    headerAt("Always Show Bars")
    local s2 = sectionAt()

    local alwaysShowBars = {
        { key = "bar1", label = "Bar 1" }, { key = "bar2", label = "Bar 2" },
        { key = "bar3", label = "Bar 3" }, { key = "bar4", label = "Bar 4" },
        { key = "bar5", label = "Bar 5" }, { key = "bar6", label = "Bar 6" },
        { key = "bar7", label = "Bar 7" }, { key = "bar8", label = "Bar 8" },
        { key = "microbar", label = "Microbar" }, { key = "bags", label = "Bags" },
        { key = "pet", label = "Pet Bar" }, { key = "stance", label = "Stance Bar" },
        { key = "extraActionButton", label = "Extra Action" }, { key = "zoneAbility", label = "Zone Ability" },
    }

    local pending = nil
    for _, barInfo in ipairs(alwaysShowBars) do
        local barDB = bars[barInfo.key]
        if barDB then
            local w = GUI:CreateFormToggle(s2.frame, nil, "alwaysShow", barDB, RefreshActionBarFade,
                { description = "Keep " .. barInfo.label .. " fully visible at all times, ignoring the mouseover fade." })
            local cell = Opts.BuildSettingRow(s2.frame, barInfo.label, w)
            if pending then
                s2.AddRow(pending, cell)
                pending = nil
            else
                pending = cell
            end
        end
    end
    if pending then s2.AddRow(pending) end

    closeSection(s2)

    tabContent:SetHeight(math.abs(y) + 40)
end

---------------------------------------------------------------------------
-- LEGACY ENTRY POINT (kept as a thin wrapper for backwards compat)
---------------------------------------------------------------------------
-- The V2 Action Bars tile now routes directly to BuildMasterSettingsTab and
-- BuildMouseoverHideTab, so there are no current callers of this function —
-- but leave it exported as a safety shim for any out-of-tree consumer.
local function CreateActionBarsPage(parent)
    local scroll, content = CreateScrollableContent(parent)
    BuildMasterSettingsTab(content)
    return scroll, content
end

---------------------------------------------------------------------------
-- Export
---------------------------------------------------------------------------
ns.QUI_ActionBarsOptions = {
    BuildActionBarsPreview = BuildActionBarsPreview,
    BuildMasterSettingsTab = BuildMasterSettingsTab,
    BuildMouseoverHideTab  = BuildMouseoverHideTab,
    SetPreviewBar          = SetActionBarsPreviewBar,
    SetSelectedBar         = SetSelectedBar,
    GetSelectedBar         = GetSelectedBar,
    RegisterSelectedBarListener = RegisterSelectedBarListener,
    RefreshPreview         = function()
        if PreviewState.refresh then
            PreviewState.refresh()
        end
    end,
    IsPreviewableBar       = function(barKey)
        return BAR_OFFSETS[barKey] ~= nil
    end,
    CreateActionBarsPage   = CreateActionBarsPage,  -- legacy shim
}

if Registry and Schema
    and type(Registry.RegisterFeature) == "function"
    and type(Schema.Feature) == "function"
    and type(Schema.Section) == "function" then
    Registry:RegisterFeature(Schema.Feature({
        id = "barHidingPage",
        moverKey = "barHiding",
        category = "appearance",
        nav = { tileId = "appearance", subPageIndex = 5 },
        sections = {
            Schema.Section({
                id = "settings",
                kind = "page",
                minHeight = 80,
                build = BuildMouseoverHideTab,
            }),
        },
    }))
end
