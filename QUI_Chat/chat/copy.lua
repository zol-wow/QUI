local ADDON_NAME, ns = ...
local Helpers = ns.Helpers
local UIKit = ns.UIKit

local I = assert(ns.QUI.Chat and ns.QUI.Chat._internals,
    "QUI Chat: copy.lua loaded before chat.lua. Check chat.xml — chat.lua must precede copy.lua.")

ns.QUI.Chat.Copy = ns.QUI.Chat.Copy or {}
local Copy = ns.QUI.Chat.Copy

local tinsert = table.insert
local tconcat = table.concat

local AUTO_HIGHLIGHT_MAX_CHARS = 8000
local COPY_BUTTON_SIZE = 24
local COPY_BUTTON_FRAME_LEVEL = 100
local COPY_HOVER_POLL_INTERVAL = 0.1
local COPY_GLYPH_STROKE = 2

local urlPopup = nil
local chatCopyFrame = nil

local QUI_COLORS = I.QUI_COLORS
if type(QUI_COLORS) ~= "table" then
    QUI_COLORS = {
        bg      = {0.067, 0.094, 0.153, 0.97},
        accent  = {0.204, 0.827, 0.600, 1},
        text    = {0.953, 0.957, 0.965, 1},
        textDim = {0.72,  0.72,  0.76,  1},
    }
end

local function ResolveAccent()
    return (I.GetAccent and I.GetAccent()) or QUI_COLORS.accent
end

local function ResolveChatFontObject()
    return I.chatFontObject or _G.QUI_CustomChatFontObject or _G.ChatFontNormal
end

local function ApplyCopyFont(editBox)
    if not editBox then return end
    if not editBox._quiFontSeeded and editBox.SetFont then
        local path, size, flags = I.chatFontPath, I.chatFontSize, I.chatFontFlags
        if type(path) == "string" and path ~= "" and type(size) == "number" and size > 0 then
            if pcall(editBox.SetFont, editBox, path, size, flags or "") then
                editBox._quiFontSeeded = true
            end
        end
    end
    local fo = ResolveChatFontObject()
    if fo and editBox.SetFontObject then editBox:SetFontObject(fo) end
end

local function ApplyScrollingEditBoxFont(seb)
    if not seb then return end
    local fo = ResolveChatFontObject()
    if not fo then return end
    local editBox = seb.GetEditBox and seb:GetEditBox()
    if editBox then editBox.fontName = fo end
    if seb.SetFontObject then seb:SetFontObject(fo) end
end

local function StyleMinimalScrollBar(bar, accent)
    if not bar then return end
    local back = bar.GetBackStepper and bar:GetBackStepper()
    local fwd = bar.GetForwardStepper and bar:GetForwardStepper()
    if back then back:SetAlpha(0) end
    if fwd then fwd:SetAlpha(0) end
    local function hideAtlasRegions(region)
        for _, key in ipairs({ "Begin", "Middle", "End" }) do
            local r = region and region[key]
            if r and r.SetAlpha then r:SetAlpha(0) end
        end
    end
    local track = (bar.GetTrack and bar:GetTrack()) or bar.Track
    if track then
        hideAtlasRegions(track)
        if not track._quiBg then
            local trackBg = track:CreateTexture(nil, "BACKGROUND")
            trackBg:SetAllPoints(track)
            track._quiBg = trackBg
        end
        track._quiBg:SetColorTexture(1, 1, 1, 0.08)
    end
    local thumb = bar.GetThumb and bar:GetThumb()
    if thumb then
        hideAtlasRegions(thumb)
        if not thumb._quiFill then
            local fill = thumb:CreateTexture(nil, "ARTWORK")
            fill:SetAllPoints(thumb)
            thumb._quiFill = fill
        end
        thumb._quiFill:SetColorTexture(accent[1], accent[2], accent[3], 0.9)
    end
end

local function ResolveTheme()
    if I.GetThemeColors then
        local theme = I.GetThemeColors()
        if theme then return theme end
    end
    local accent = ResolveAccent()
    return {
        bg = QUI_COLORS.bg,
        bgDark = {0.03, 0.04, 0.06, 1},
        text = QUI_COLORS.text,
        textDim = QUI_COLORS.textDim,
        textMuted = QUI_COLORS.textDim,
        border = {1, 1, 1, 0.08},
        accent = accent,
        accentHover = accent,
    }
end

local function ColorTexture(texture, color)
    if texture and texture.SetColorTexture and color then
        texture:SetColorTexture(color[1] or 1, color[2] or 1, color[3] or 1, color[4] or 1)
    end
end

local function CreateThemedButton(parent, text, width, height, onClick, variant)
    local theme = ResolveTheme()
    return UIKit.CreateButton(parent, {
        text = text,
        width = width,
        height = height,
        onClick = onClick,
        variant = variant,
        colors = { text = theme.text, textDim = theme.textDim, accent = theme.accent },
    })
end

local function StyleThemedButton(button, variant)
    if not button then return end
    local theme = ResolveTheme()
    local isPrimary = variant == "primary"

    if button.SetBorderColor then
        if isPrimary then
            button:SetBorderColor(theme.accent[1], theme.accent[2], theme.accent[3], 0.55)
        else
            button:SetBorderColor(1, 1, 1, 0.2)
        end
    elseif UIKit and UIKit.UpdateBorderLines then
        if isPrimary then
            UIKit.UpdateBorderLines(button, 1, theme.accent[1], theme.accent[2], theme.accent[3], 0.55)
        else
            UIKit.UpdateBorderLines(button, 1, 1, 1, 1, 0.2)
        end
    end

    if button.text then
        local c = isPrimary and theme.accent or theme.textDim
        button.text:SetTextColor(c[1], c[2], c[3], c[4] or 1)
    end
end

local function CreateCloseButton(parent, onClick)
    return UIKit.CreateCloseButton(parent, { size = 22, onClick = onClick })
end

local function GetScrollBar(scrollFrame)
    if not scrollFrame then return nil end
    local scrollBar = scrollFrame.ScrollBar
    if scrollBar then return scrollBar end
    local name = scrollFrame.GetName and scrollFrame:GetName()
    if name then
        return _G[name .. "ScrollBar"]
    end
    return nil
end

local function HideButtonArtwork(button)
    if not button then return end
    button:SetAlpha(0)
    button:SetSize(1, 1)
    if button.GetRegions then
        for _, region in ipairs({button:GetRegions()}) do
            if region and region.SetAlpha then
                region:SetAlpha(0)
            end
        end
    end
end

local function HideFrameTextures(frame)
    if not frame or not frame.GetRegions then return end
    for _, region in ipairs({frame:GetRegions()}) do
        if region and region.GetObjectType and region:GetObjectType() == "Texture" and region.SetAlpha then
            region:SetAlpha(0)
        end
    end
end

local function StyleScrollFrame(scrollFrame)
    local scrollBar = GetScrollBar(scrollFrame)
    if not scrollBar then return end

    local theme = ResolveTheme()
    HideFrameTextures(scrollBar)
    if scrollBar.Track then
        scrollBar.Track:SetAlpha(0)
    end
    if scrollBar.Background then
        scrollBar.Background:SetAlpha(0)
    end
    if scrollBar.BG then
        scrollBar.BG:SetAlpha(0)
    end
    if scrollBar.SetWidth then
        scrollBar:SetWidth(8)
    end

    local thumb = scrollBar.ThumbTexture or (scrollBar.GetThumbTexture and scrollBar:GetThumbTexture())
    if thumb then
        thumb:SetTexture("Interface\\Buttons\\WHITE8x8")
        thumb:SetColorTexture(theme.accent[1], theme.accent[2], theme.accent[3], 0.7)
        if thumb.SetAlpha then thumb:SetAlpha(1) end
        if thumb.SetSize then
            thumb:SetSize(8, 40)
        end
    end

    HideButtonArtwork(scrollBar.ScrollUpButton)
    HideButtonArtwork(scrollBar.ScrollDownButton)

    local name = scrollFrame.GetName and scrollFrame:GetName()
    if name then
        HideButtonArtwork(_G[name .. "ScrollBarScrollUpButton"])
        HideButtonArtwork(_G[name .. "ScrollBarScrollDownButton"])
    end
end

local function StyleResizeButton(button)
    if not button then return end
    local theme = ResolveTheme()
    local textures = {
        button.GetNormalTexture and button:GetNormalTexture(),
        button.GetHighlightTexture and button:GetHighlightTexture(),
        button.GetPushedTexture and button:GetPushedTexture(),
    }
    for i, texture in ipairs(textures) do
        if texture then
            if texture.SetDesaturated then texture:SetDesaturated(true) end
            local alpha = (i == 2) and 0.9 or 0.55
            texture:SetVertexColor(theme.accent[1], theme.accent[2], theme.accent[3], alpha)
        end
    end
end

local function RefreshPopupAccent(popup)
    if not popup then return end
    local theme = ResolveTheme()
    local accent = theme.accent
    I.ApplySurfaceStyle(popup, theme.bg, accent, 2)
    if popup.title then
        popup.title:SetTextColor(accent[1], accent[2], accent[3], 1)
    end
    if popup.hint then
        popup.hint:SetTextColor(theme.textDim[1], theme.textDim[2], theme.textDim[3], theme.textDim[4] or 1)
    end
    if popup.editBg then
        I.ApplySurfaceStyle(popup.editBg, theme.bgDark, theme.border, 1)
    end
    if popup.editBox then
        popup.editBox:SetTextColor(theme.text[1], theme.text[2], theme.text[3], theme.text[4] or 1)
        if popup.scrollingEditBox then
            ApplyScrollingEditBoxFont(popup.scrollingEditBox)
            if popup.scrollBar then StyleMinimalScrollBar(popup.scrollBar, accent) end
        else
            ApplyCopyFont(popup.editBox)
        end
    end
    if popup.scrollFrame then
        StyleScrollFrame(popup.scrollFrame)
    end
    StyleThemedButton(popup.selectAllButton, "primary")
    StyleThemedButton(popup.closeButton, "ghost")
    StyleResizeButton(popup.resizeButton)
end

local function CreateCopyPopup()
    if urlPopup then return urlPopup end

    urlPopup = CreateFrame("Frame", "QUI_ChatCopyPopup", UIParent)
    urlPopup:SetSize(420, 90)
    urlPopup:SetPoint("CENTER")
    urlPopup:SetFrameStrata("DIALOG")
    local theme = ResolveTheme()
    local accent = theme.accent
    I.ApplySurfaceStyle(urlPopup, theme.bg, accent, 2)
    urlPopup:EnableMouse(true)
    urlPopup:SetMovable(true)
    urlPopup:RegisterForDrag("LeftButton")
    urlPopup:SetScript("OnDragStart", urlPopup.StartMoving)
    urlPopup:SetScript("OnDragStop", urlPopup.StopMovingOrSizing)
    urlPopup:Hide()

    local title = urlPopup:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -12)
    title:SetText(ns.L["Press Ctrl+C to copy"])
    title:SetTextColor(accent[1], accent[2], accent[3], 1)
    urlPopup.title = title

    local editBg = CreateFrame("Frame", nil, urlPopup)
    editBg:SetPoint("LEFT", 18, 0)
    editBg:SetPoint("RIGHT", -34, 0)
    editBg:SetHeight(26)
    editBg:SetPoint("CENTER", 0, -9)
    I.ApplySurfaceStyle(editBg, theme.bgDark, theme.border, 1)
    urlPopup.editBg = editBg

    local editBox = CreateFrame("EditBox", nil, editBg)
    editBox:SetPoint("LEFT", 8, 0)
    editBox:SetPoint("RIGHT", -8, 0)
    editBox:SetHeight(22)
    editBox:SetAutoFocus(true)
    editBox:SetTextColor(theme.text[1], theme.text[2], theme.text[3], theme.text[4] or 1)
    ApplyCopyFont(editBox)
    editBox:SetScript("OnEscapePressed", function() urlPopup:Hide() end)
    editBox:SetScript("OnEnterPressed", function() urlPopup:Hide() end)
    urlPopup.editBox = editBox

    local closeBtn = CreateCloseButton(urlPopup, function() urlPopup:Hide() end)
    closeBtn:SetPoint("TOPRIGHT", -6, -6)
    urlPopup.cornerCloseButton = closeBtn

    if not tContains(UISpecialFrames, "QUI_ChatCopyPopup") then
        tinsert(UISpecialFrames, "QUI_ChatCopyPopup")
    end

    return urlPopup
end

local function ShowCopyPopup(url)
    local popup = CreateCopyPopup()
    RefreshPopupAccent(popup)
    popup.editBox:SetText(url)
    popup.editBox:HighlightText()
    popup:Show()
    popup.editBox:SetFocus()
end

local function ExtractURLFromLink(link)
    if type(link) ~= "string" then return nil end

    local url = link:match("^addon:quichat:url:(.*)")
    if url then return url end

    local legacy = link:match("^addon:quichat:(.*)")
    if legacy
        and not legacy:find("^waypoint:")
        and not legacy:find("^player:") then
        return legacy
    end
    return nil
end

local function SetupURLClickHandler()
    EventRegistry:RegisterCallback("SetItemRef", function(_, link, text, button)
        local settings = I.GetSettings and I.GetSettings()
        if not (I.IsChatEnabled and I.IsChatEnabled(settings)) then return end

        local url = ExtractURLFromLink(link)
        if url then
            ShowCopyPopup(url)
            return true
        end
    end)
end

local function LineColorCode(entry)
    local r, g, b = entry.r, entry.g, entry.b
    local resolver = ns.QUI.Chat._lineColorResolver
    if resolver and entry.e then
        local orR, orG, orB = resolver(entry.e, entry.ch and { [9] = entry.ch } or nil)
        if orR then r, g, b = orR, orG, orB end
    end
    if type(r) ~= "number" or type(g) ~= "number" or type(b) ~= "number" then return nil end
    if r >= 1 and g >= 1 and b >= 1 then return nil end
    local function byte(v)
        if v < 0 then v = 0 elseif v > 1 then v = 1 end
        return math.floor(v * 255 + 0.5)
    end
    return ("|cff%02x%02x%02x"):format(byte(r), byte(g), byte(b))
end

local function CleanMessage(message, lineColor)
    if Helpers.IsSecretValue(message) or type(message) ~= "string" then return "" end

    local cleaned = message
    if _G.C_BattleNet and _G.C_BattleNet.GetAccountInfoByID then
        cleaned = cleaned:gsub("|HBNplayer:.-:(%d+):.-|h(%b[])|h", function(bnID)
            local id = tonumber(bnID)
            if not id then return nil end
            local ok, info = pcall(_G.C_BattleNet.GetAccountInfoByID, id)
            if not ok or type(info) ~= "table" then return nil end
            local bt = info.battleTag
            if type(bt) ~= "string" or bt == "" or bt:sub(1, 2) == "|K" then return nil end
            local hash = bt:find("#", 1, true)
            local name = hash and bt:sub(1, hash - 1) or bt
            if name ~= "" then
                return ("[%s]"):format(name)
            end
            return nil
        end)
    end
    cleaned = cleaned:gsub("%f[|]|K.-%f[|]|k", "???")
    cleaned = cleaned:gsub("%f[|]|W(.-)%f[|]|w", "%1")
    cleaned = cleaned:gsub("|TInterface\\TargetingFrame\\UI%-RaidTargetingIcon_(%d):[^|]*|t", "{rt%1}")
    cleaned = cleaned:gsub("|T[^|]*|t", "")
    cleaned = cleaned:gsub("|A[^|]*|a", "")
    cleaned = cleaned:gsub("|H[^|]*|h(%[.-%])|h", "%1")
    cleaned = cleaned:gsub("|H[^|]*|h(.-)|h", "%1")
    cleaned = cleaned:gsub("|n", "\n")
    if lineColor and cleaned ~= "" then
        cleaned = lineColor .. cleaned .. "|r"
    end

    return cleaned
end

local function GetCustomDisplayLines(windowID)
    local lines = {}
    local function collect(entry)
        if entry.s then
            lines[#lines + 1] = "??? (protected message)"
        else
            local cleaned = CleanMessage(entry.m, LineColorCode(entry))
            if cleaned ~= "" then
                lines[#lines + 1] = cleaned
            end
        end
    end
    local Display = ns.QUI.Chat.DisplayLayer
    if windowID and Display and Display.ForEachVisible then
        Display.ForEachVisible(windowID, collect)
    else
        local Store = ns.QUI.Chat.MessageStore
        if Store then Store.ForEach(collect) end
    end
    return lines
end
Copy.GetCustomDisplayLines = GetCustomDisplayLines

local function AddGlyphLine(parent, layer)
    local line = parent:CreateTexture(nil, layer or "ARTWORK")
    line:SetTexture("Interface\\Buttons\\WHITE8x8")
    return line
end

local function CreateCopyGlyph(button)
    if button._quiGlyphParts then return end

    local parts = {}
    local back = CreateFrame("Frame", nil, button)
    back:SetSize(10, 12)
    back:SetPoint("CENTER", -3, 3)
    parts.backTop = AddGlyphLine(back)
    parts.backBottom = AddGlyphLine(back)
    parts.backLeft = AddGlyphLine(back)
    parts.backRight = AddGlyphLine(back)
    parts.backTop:SetPoint("TOPLEFT")
    parts.backTop:SetPoint("TOPRIGHT")
    parts.backTop:SetHeight(COPY_GLYPH_STROKE)
    parts.backBottom:SetPoint("BOTTOMLEFT")
    parts.backBottom:SetPoint("BOTTOMRIGHT")
    parts.backBottom:SetHeight(COPY_GLYPH_STROKE)
    parts.backLeft:SetPoint("TOPLEFT")
    parts.backLeft:SetPoint("BOTTOMLEFT")
    parts.backLeft:SetWidth(COPY_GLYPH_STROKE)
    parts.backRight:SetPoint("TOPRIGHT")
    parts.backRight:SetPoint("BOTTOMRIGHT")
    parts.backRight:SetWidth(COPY_GLYPH_STROKE)

    local front = CreateFrame("Frame", nil, button)
    front:SetSize(12, 14)
    front:SetPoint("CENTER", 2, -2)
    parts.frontTop = AddGlyphLine(front)
    parts.frontBottom = AddGlyphLine(front)
    parts.frontLeft = AddGlyphLine(front)
    parts.frontRight = AddGlyphLine(front)
    parts.frontTop:SetPoint("TOPLEFT")
    parts.frontTop:SetPoint("TOPRIGHT", -4, 0)
    parts.frontTop:SetHeight(COPY_GLYPH_STROKE)
    parts.frontBottom:SetPoint("BOTTOMLEFT")
    parts.frontBottom:SetPoint("BOTTOMRIGHT")
    parts.frontBottom:SetHeight(COPY_GLYPH_STROKE)
    parts.frontLeft:SetPoint("TOPLEFT")
    parts.frontLeft:SetPoint("BOTTOMLEFT")
    parts.frontLeft:SetWidth(COPY_GLYPH_STROKE)
    parts.frontRight:SetPoint("TOPRIGHT", 0, -4)
    parts.frontRight:SetPoint("BOTTOMRIGHT")
    parts.frontRight:SetWidth(COPY_GLYPH_STROKE)
    parts.foldA = AddGlyphLine(front)
    parts.foldB = AddGlyphLine(front)
    parts.foldA:SetPoint("TOPRIGHT", 0, -4)
    parts.foldA:SetSize(4, COPY_GLYPH_STROKE)
    parts.foldB:SetPoint("TOPRIGHT", -4, 0)
    parts.foldB:SetSize(COPY_GLYPH_STROKE, 4)

    button._quiGlyphParts = parts
end

local function RefreshCopyGlyph(button, hovered)
    if not button then return end
    local theme = ResolveTheme()
    CreateCopyGlyph(button)
    if button._hoverBg then
        if hovered then
            button._hoverBg:SetColorTexture(theme.accent[1], theme.accent[2], theme.accent[3], 0.18)
            button._hoverBg:Show()
        else
            button._hoverBg:Hide()
        end
    end
    for key, part in pairs(button._quiGlyphParts) do
        if key:find("^back") then
            ColorTexture(part, {theme.text[1], theme.text[2], theme.text[3], hovered and 0.72 or 0.55})
        else
            ColorTexture(part, {theme.accent[1], theme.accent[2], theme.accent[3], hovered and 1 or 0.95})
        end
    end
end

local function CreateChatCopyFrame()
    if chatCopyFrame then return chatCopyFrame end

    chatCopyFrame = CreateFrame("Frame", "QUI_ChatCopyFrame", UIParent)
    chatCopyFrame:SetSize(500, 400)
    chatCopyFrame:SetPoint("CENTER")
    chatCopyFrame:SetFrameStrata("DIALOG")
    local theme = ResolveTheme()
    local accent = theme.accent
    I.ApplySurfaceStyle(chatCopyFrame, theme.bg, accent, 2)
    chatCopyFrame:EnableMouse(true)
    chatCopyFrame:SetMovable(true)
    chatCopyFrame:SetResizable(true)
    chatCopyFrame:SetResizeBounds(300, 200, 800, 600)
    chatCopyFrame:RegisterForDrag("LeftButton")
    chatCopyFrame:SetScript("OnDragStart", chatCopyFrame.StartMoving)
    chatCopyFrame:SetScript("OnDragStop", chatCopyFrame.StopMovingOrSizing)
    chatCopyFrame:Hide()

    local title = chatCopyFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -10)
    title:SetText(ns.L["Chat History - Select and Ctrl+C to copy"])
    title:SetTextColor(accent[1], accent[2], accent[3], 1)
    chatCopyFrame.title = title

    local hint = chatCopyFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    hint:SetPoint("TOP", title, "BOTTOM", 0, -4)
    hint:SetText(ns.L["Select all (Ctrl+A) then copy (Ctrl+C)"])
    hint:SetTextColor(theme.textDim[1], theme.textDim[2], theme.textDim[3], theme.textDim[4] or 1)
    chatCopyFrame.hint = hint

    local editBg = CreateFrame("Frame", nil, chatCopyFrame)
    editBg:SetPoint("TOPLEFT", 12, -55)
    editBg:SetPoint("BOTTOMRIGHT", -12, 45)
    I.ApplySurfaceStyle(editBg, theme.bgDark, theme.border, 1)
    chatCopyFrame.editBg = editBg

    local seb = CreateFrame("Frame", "QUI_ChatCopyScrollingEditBox", editBg, "ScrollingEditBoxTemplate")
    seb:SetPoint("TOPLEFT", 8, -8)
    seb:SetPoint("BOTTOMRIGHT", -8, 8)
    local editBox = seb:GetEditBox()
    editBox:SetAutoFocus(false)
    editBox:SetTextColor(theme.text[1], theme.text[2], theme.text[3], theme.text[4] or 1)
    chatCopyFrame.scrollingEditBox = seb
    chatCopyFrame.editBox = editBox
    ApplyScrollingEditBoxFont(seb)

    if _G.ScrollUtil and _G.ScrollUtil.RegisterScrollBoxWithScrollBar then
        local scrollBar = CreateFrame("EventFrame", nil, seb, "MinimalScrollBar")
        scrollBar:SetPoint("TOPRIGHT", seb, "TOPRIGHT", -1, -2)
        scrollBar:SetPoint("BOTTOMRIGHT", seb, "BOTTOMRIGHT", -1, 2)
        local scrollBox = seb:GetScrollBox()
        _G.ScrollUtil.RegisterScrollBoxWithScrollBar(scrollBox, scrollBar)
        if _G.ScrollUtil.AddManagedScrollBarVisibilityBehavior and _G.CreateAnchor then
            local withBar = {
                _G.CreateAnchor("TOPLEFT", seb, "TOPLEFT", 0, 0),
                _G.CreateAnchor("BOTTOMRIGHT", seb, "BOTTOMRIGHT", -16, 0),
            }
            local withoutBar = {
                _G.CreateAnchor("TOPLEFT", seb, "TOPLEFT", 0, 0),
                _G.CreateAnchor("BOTTOMRIGHT", seb, "BOTTOMRIGHT", 0, 0),
            }
            _G.ScrollUtil.AddManagedScrollBarVisibilityBehavior(scrollBox, scrollBar, withBar, withoutBar)
        end
        chatCopyFrame.scrollBar = scrollBar
        StyleMinimalScrollBar(scrollBar, accent)
    end

    local closeBtn = CreateCloseButton(chatCopyFrame, function() chatCopyFrame:Hide() end)
    closeBtn:SetPoint("TOPRIGHT", -6, -6)
    chatCopyFrame.cornerCloseButton = closeBtn

    local selectAllBtn = CreateThemedButton(chatCopyFrame, "Select All", 100, 24, function()
        editBox:SetFocus()
        editBox:HighlightText()
    end, "primary")
    selectAllBtn:SetPoint("BOTTOMLEFT", 12, 10)
    chatCopyFrame.selectAllButton = selectAllBtn
    StyleThemedButton(selectAllBtn, "primary")

    local closeBottomBtn = CreateThemedButton(chatCopyFrame, "Close", 80, 24, function()
        chatCopyFrame:Hide()
    end, "ghost")
    closeBottomBtn:SetPoint("BOTTOMRIGHT", -32, 10)
    chatCopyFrame.closeButton = closeBottomBtn
    StyleThemedButton(closeBottomBtn, "ghost")

    local resizeBtn = CreateFrame("Button", nil, chatCopyFrame)
    resizeBtn:SetSize(16, 16)
    resizeBtn:SetPoint("BOTTOMRIGHT", -4, 4)
    resizeBtn:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    resizeBtn:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    resizeBtn:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
    chatCopyFrame.resizeButton = resizeBtn
    StyleResizeButton(resizeBtn)
    resizeBtn:SetScript("OnMouseDown", function() chatCopyFrame:StartSizing("BOTTOMRIGHT") end)
    resizeBtn:SetScript("OnMouseUp", function()
        chatCopyFrame:StopMovingOrSizing()
    end)

    if not tContains(UISpecialFrames, "QUI_ChatCopyFrame") then
        tinsert(UISpecialFrames, "QUI_ChatCopyFrame")
    end

    return chatCopyFrame
end

function Copy.ShowCustomCopyFrame(windowID)
    local settings = I.GetSettings and I.GetSettings()
    if not (I.IsChatEnabled and I.IsChatEnabled(settings)) then return end
    local frame = CreateChatCopyFrame()
    RefreshPopupAccent(frame)
    local lines = GetCustomDisplayLines(windowID)
    local text = #lines > 0 and tconcat(lines, "\n") or "(No copyable messages in custom display)"
    frame.scrollingEditBox:SetText(text)
    frame:Show()
    frame.editBox:SetFocus()
    if #text <= AUTO_HIGHLIGHT_MAX_CHARS then
        frame.editBox:HighlightText()
    end
    if C_Timer and C_Timer.After then
        C_Timer.After(0, function()
            local seb = frame.scrollingEditBox
            local sb = seb and seb.GetScrollBox and seb:GetScrollBox()
            if frame:IsShown() and sb and sb.ScrollToEnd then
                sb:ScrollToEnd()
            end
        end)
    end
end

local function ApplyCustomCopyButtonMode(button, container)
    if not (button and container) then return end
    local settings = I.GetSettings and I.GetSettings()
    local mode = settings and settings.copyButtonMode or "always"
    if mode == "hidden" or mode == "disabled" then
        button:Hide()
        container:SetScript("OnEnter", nil)
        container:SetScript("OnLeave", nil)
        container:SetScript("OnUpdate", nil)
        container:EnableMouse(false)
    elseif mode == "hover" then
        button:Hide()
        container:EnableMouse(true)
        container._quiCopyHovered = false
        container:SetScript("OnEnter", nil)
        container:SetScript("OnLeave", nil)
        container._quiCopyPollT = 0
        container:SetScript("OnUpdate", function(self, elapsed)
            local t = self._quiCopyPollT + (elapsed or COPY_HOVER_POLL_INTERVAL)
            if t < COPY_HOVER_POLL_INTERVAL then
                self._quiCopyPollT = t
                return
            end
            self._quiCopyPollT = 0
            local over = (self.IsMouseOver and self:IsMouseOver()) or false
            if over ~= self._quiCopyHovered then
                self._quiCopyHovered = over
                button:SetShown(over)
            end
        end)
    else
        button:Show()
        container:SetScript("OnEnter", nil)
        container:SetScript("OnLeave", nil)
        container:SetScript("OnUpdate", nil)
        container:EnableMouse(false)
    end
end

local function CreateCopyButton(windowID, container)
    local name = (windowID == 1) and "QUI_CustomChatCopyButton" or nil
    local button = CreateFrame("Button", name, container)
    button:SetSize(COPY_BUTTON_SIZE, COPY_BUTTON_SIZE)
    button:SetPoint("TOPRIGHT", container, "TOPRIGHT", -2, 2)
    if button.SetFrameLevel then
        button:SetFrameLevel(COPY_BUTTON_FRAME_LEVEL)
    end
    button:EnableMouse(true)
    button._hoverBg = button:CreateTexture(nil, "BACKGROUND")
    button._hoverBg:SetAllPoints(button)
    button._hoverBg:Hide()
    RefreshCopyGlyph(button, false)
    button:SetScript("OnEnter", function(self)
        RefreshCopyGlyph(self, true)
    end)
    button:SetScript("OnLeave", function(self)
        RefreshCopyGlyph(self, false)
    end)
    button:SetScript("OnClick", function(self)
        Copy.ShowCustomCopyFrame(self._quiWindowID)
    end)
    container._quiCopyButton = button
    return button
end

function Copy.EnsureCustomCopyButton()
    local Display = ns.QUI.Chat.DisplayLayer
    if not (Display and Display.GetContainer) then return end
    local count = (Display.GetWindowCount and Display.GetWindowCount()) or 1
    local settings = I.GetSettings and I.GetSettings()
    local mode = settings and settings.copyButtonMode or "always"
    for windowID = 1, count do
        local container = Display.GetContainer(windowID)
        if container then
            local button = container._quiCopyButton
            if not button and mode ~= "hidden" and mode ~= "disabled" then
                button = CreateCopyButton(windowID, container)
            end
            if button then
                button._quiWindowID = windowID
                ApplyCustomCopyButtonMode(button, container)
            end
        end
    end
end

function Copy.OnWindowDeleted()
    Copy.EnsureCustomCopyButton()
end

Copy.ShowURLPopup  = ShowCopyPopup
Copy.SetupURLClick = SetupURLClickHandler
