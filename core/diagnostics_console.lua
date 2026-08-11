local ADDON_NAME, ns = ...

local MAX_LINES = 1000
local Console = {}
ns.DiagnosticsConsole = Console

local buffer = {}

local livePanel = setmetatable({}, { __mode = "v" })

local KIND_DEFAULT = "captured"

local function appendInternal(line, kind)
    kind = kind or KIND_DEFAULT
    buffer[#buffer + 1] = { text = tostring(line or ""), kind = kind }
    if #buffer > MAX_LINES then
        table.remove(buffer, 1)
    end
    local panel = livePanel.frame
    if panel and panel._appendLine then
        panel._appendLine(buffer[#buffer].text, kind)
    end
end

function Console.Append(line, kind)
    appendInternal(line, kind)
end

function Console.Clear()
    for i = #buffer, 1, -1 do buffer[i] = nil end
    local panel = livePanel.frame
    if panel and panel._clear then
        panel._clear()
    end
end

function Console.GetText()
    local parts = {}
    for i, entry in ipairs(buffer) do
        parts[i] = entry.text
    end
    return table.concat(parts, "\n")
end

function Console.Run(label, fn)
    appendInternal("> " .. tostring(label or ""), "command")
    local realPrint = _G.print
    _G.print = function(...)
        local n, parts = select("#", ...), {}
        for i = 1, n do parts[i] = tostring((select(i, ...))) end
        appendInternal(table.concat(parts, " "), "captured")
        realPrint(...)
    end
    local ok, err = pcall(fn)
    _G.print = realPrint
    if not ok then
        appendInternal("ERROR: " .. tostring(err), "error")
    end
end

local KIND_COLOR = {
    command  = "|cff34D399",
    captured = "|cffFFFFFF",
    error    = "|cffE15D5D",
    info     = "|cff888888",
}

local function colorize(text, kind)
    local prefix = KIND_COLOR[kind] or KIND_COLOR.captured
    return prefix .. tostring(text or "") .. "|r"
end

local function showCopyPopup(text)
    local popup = _G.QUI_DiagnosticsCopyPopup
    if not popup then
        popup = CreateFrame("Frame", "QUI_DiagnosticsCopyPopup", UIParent, "BackdropTemplate")
        popup:SetSize(560, 320)
        popup:SetPoint("CENTER")
        popup:SetFrameStrata("FULLSCREEN_DIALOG")
        popup:SetFrameLevel(500)
        popup:SetToplevel(true)
        ns.SkinBase.ApplyPixelBackdrop(popup, 1, true, false, {0.4, 0.4, 0.4, 1}, {0, 0, 0, 0.92})
        popup:EnableMouse(true)
        popup:SetMovable(true)
        popup:RegisterForDrag("LeftButton")
        popup:SetScript("OnDragStart", popup.StartMoving)
        popup:SetScript("OnDragStop",  popup.StopMovingOrSizing)

        local title = popup:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        title:SetPoint("TOP", 0, -10)
        title:SetText(ns.L["Diagnostic Output — Ctrl+A then Ctrl+C"])

        local scroll = CreateFrame("ScrollFrame", nil, popup, "UIPanelScrollFrameTemplate")
        scroll:SetPoint("TOPLEFT", 12, -32)
        scroll:SetPoint("BOTTOMRIGHT", -28, 40)

        local edit = CreateFrame("EditBox", nil, scroll)
        edit:SetMultiLine(true)
        edit:SetMaxLetters(0)
        edit:SetFontObject("ChatFontNormal")
        edit:SetWidth(520)
        edit:SetAutoFocus(false)
        edit:SetScript("OnEscapePressed", function() popup:Hide() end)
        scroll:SetScrollChild(edit)
        popup._edit = edit

        local close = CreateFrame("Button", nil, popup, "UIPanelButtonTemplate")
        close:SetSize(80, 22)
        close:SetPoint("BOTTOM", 0, 10)
        close:SetText(ns.L["Close"])
        close:SetScript("OnClick", function() popup:Hide() end)
    end
    popup._edit:SetText(text or "")
    popup._edit:HighlightText()
    popup._edit:SetFocus()
    popup:Show()
    popup:Raise()
end

function Console.CreateOutputPanel(parent)
    local container = CreateFrame("Frame", nil, parent)
    container:SetSize(680, 320)

    local header = CreateFrame("Frame", nil, container)
    header:SetHeight(24)
    header:SetPoint("TOPLEFT", 0, 0)
    header:SetPoint("TOPRIGHT", 0, 0)

    local caption = header:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    caption:SetPoint("LEFT", 4, 0)
    caption:SetText(ns.L["Diagnostic Output"])
    caption:SetTextColor(0.65, 0.65, 0.65, 1)

    local QUI = _G.QUI
    local GUI = QUI and QUI.GUI

    local clearBtn, copyBtn
    if GUI and GUI.CreateButton then
        clearBtn = GUI:CreateButton(header, "Clear", 60, 20, function()
            Console.Clear()
        end, "ghost")
        copyBtn = GUI:CreateButton(header, "Copy", 60, 20, function()
            showCopyPopup(Console.GetText())
        end, "ghost")
    else
        clearBtn = CreateFrame("Button", nil, header, "UIPanelButtonTemplate")
        clearBtn:SetSize(60, 20); clearBtn:SetText(ns.L["Clear"])
        clearBtn:SetScript("OnClick", function() Console.Clear() end)
        copyBtn = CreateFrame("Button", nil, header, "UIPanelButtonTemplate")
        copyBtn:SetSize(60, 20); copyBtn:SetText(ns.L["Copy"])
        copyBtn:SetScript("OnClick", function() showCopyPopup(Console.GetText()) end)
    end
    copyBtn:ClearAllPoints()
    copyBtn:SetPoint("RIGHT", header, "RIGHT", -2, 0)
    clearBtn:ClearAllPoints()
    clearBtn:SetPoint("RIGHT", copyBtn, "LEFT", -6, 0)

    local body = CreateFrame("Frame", nil, container, "BackdropTemplate")
    body:SetPoint("TOPLEFT", 0, -26)
    body:SetPoint("BOTTOMRIGHT", 0, 0)
    ns.SkinBase.ApplyPixelBackdrop(body, 1, true, false, {0.3, 0.3, 0.3, 1}, {0, 0, 0, 0.5})

    local smf = CreateFrame("ScrollingMessageFrame", nil, body)
    smf:SetPoint("TOPLEFT", 6, -6)
    smf:SetPoint("BOTTOMRIGHT", -6, 6)
    smf:SetMaxLines(MAX_LINES)
    smf:SetFontObject("GameFontHighlightSmall")
    smf:SetJustifyH("LEFT")
    smf:SetFading(false)
    smf:SetInsertMode("BOTTOM")
    if smf.SetIndentedWordWrap then
        smf:SetIndentedWordWrap(true)
    end

    smf:EnableMouseWheel(true)
    smf:SetScript("OnMouseWheel", function(self, delta)
        if IsShiftKeyDown() then
            if delta > 0 then self:ScrollToTop() else self:ScrollToBottom() end
        else
            if delta > 0 then
                self:ScrollUp() self:ScrollUp() self:ScrollUp()
            else
                self:ScrollDown() self:ScrollDown() self:ScrollDown()
            end
        end
    end)

    container._smf = smf

    for _, entry in ipairs(buffer) do
        smf:AddMessage(colorize(entry.text, entry.kind))
    end
    if #buffer == 0 then
        smf:AddMessage(colorize("Ready. Click any button above to run a diagnostic command.", "info"))
    end

    container._appendLine = function(line, kind)
        smf:AddMessage(colorize(line, kind))
    end
    container._clear = function()
        smf:Clear()
        smf:AddMessage(colorize("Ready. Click any button above to run a diagnostic command.", "info"))
    end

    livePanel.frame = container
    return container
end

ns._DiagnosticsConsoleInternal = {
    bufferLength = function() return #buffer end,
    maxLines     = MAX_LINES,
}
