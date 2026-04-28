--[[
    QUI Diagnostics Console
    --------------------------------------------------------------
    Public API:
        ns.DiagnosticsConsole.Run(label, fn)
            Wraps fn() in a temporary _G.print substitution.
            Lines fn() prints are mirrored to both chat AND the
            console buffer/panel. _G.print is always restored,
            even on Lua error.
            Note: fn must be synchronous. print() calls scheduled to
            run later (timers, events) after Run returns will not be
            captured.

        ns.DiagnosticsConsole.Append(line, kind)
            Append one line to the ring buffer (and panel if mounted).
            kind in { "command", "captured", "error", "info" }.

        ns.DiagnosticsConsole.Clear()
            Empty the buffer and panel.

        ns.DiagnosticsConsole.GetText()
            Return the buffer joined with "\n" (used by [Copy]).

        ns.DiagnosticsConsole.CreateOutputPanel(parent)
            Build the visible panel widget; returns the anchor frame.
]]

local ADDON_NAME, ns = ...

local MAX_LINES = 1000
local Console = {}
ns.DiagnosticsConsole = Console

-- Ring buffer: 1-indexed array; head points at the next slot to write.
-- We use a plain array with a length cap and table.remove(1) on overflow.
-- 1000 lines × O(1) appends with rare O(N) drops on overflow is fine for
-- a panel that updates at human click rate.
local buffer = {}

-- Weak-valued reference to the live panel so Append can push updates.
-- The value (the panel frame) is GC-eligible once the options window is
-- closed; we do not hold the panel alive ourselves.
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
        realPrint(...)            -- mirror to chat
    end
    local ok, err = pcall(fn)
    _G.print = realPrint           -- always restore
    if not ok then
        appendInternal("ERROR: " .. tostring(err), "error")
    end
end

-- Color tags applied per-kind. Returned as the WoW colour-escape prefix
-- so ScrollingMessageFrame renders them; |r terminates each line.
local KIND_COLOR = {
    command  = "|cff34D399",  -- accent green (#34D399)
    captured = "|cffFFFFFF",
    error    = "|cffE15D5D",
    info     = "|cff888888",
}

local function colorize(text, kind)
    local prefix = KIND_COLOR[kind] or KIND_COLOR.captured
    return prefix .. tostring(text or "") .. "|r"
end

-- A small generic copy popup. We do this inline (no dependency on
-- framework.lua's CreateExportPopup) because that helper isn't a
-- public export at the module level we run in.
local function showCopyPopup(text)
    local popup = _G.QUI_DiagnosticsCopyPopup
    if not popup then
        popup = CreateFrame("Frame", "QUI_DiagnosticsCopyPopup", UIParent, "BackdropTemplate")
        popup:SetSize(560, 320)
        popup:SetPoint("CENTER")
        -- FULLSCREEN_DIALOG + Toplevel + a high explicit frame level so the
        -- popup sits on top of the QUI options window (which itself runs at
        -- the DIALOG strata).
        popup:SetFrameStrata("FULLSCREEN_DIALOG")
        popup:SetFrameLevel(500)
        popup:SetToplevel(true)
        popup:SetBackdrop({
            bgFile   = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Buttons\\WHITE8X8",
            edgeSize = 1,
        })
        popup:SetBackdropColor(0, 0, 0, 0.92)
        popup:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)
        popup:EnableMouse(true)
        popup:SetMovable(true)
        popup:RegisterForDrag("LeftButton")
        popup:SetScript("OnDragStart", popup.StartMoving)
        popup:SetScript("OnDragStop",  popup.StopMovingOrSizing)

        local title = popup:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        title:SetPoint("TOP", 0, -10)
        title:SetText("Diagnostic Output — Ctrl+A then Ctrl+C")

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
        close:SetText("Close")
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

    -- ── header bar ────────────────────────────────────────────
    local header = CreateFrame("Frame", nil, container)
    header:SetHeight(24)
    header:SetPoint("TOPLEFT", 0, 0)
    header:SetPoint("TOPRIGHT", 0, 0)

    local caption = header:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    caption:SetPoint("LEFT", 4, 0)
    caption:SetText("Diagnostic Output")
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
        -- Defensive fallback if GUI is unavailable. Should not occur
        -- in normal load order; the page renderer guards on GUI before
        -- creating the panel.
        clearBtn = CreateFrame("Button", nil, header, "UIPanelButtonTemplate")
        clearBtn:SetSize(60, 20); clearBtn:SetText("Clear")
        clearBtn:SetScript("OnClick", function() Console.Clear() end)
        copyBtn = CreateFrame("Button", nil, header, "UIPanelButtonTemplate")
        copyBtn:SetSize(60, 20); copyBtn:SetText("Copy")
        copyBtn:SetScript("OnClick", function() showCopyPopup(Console.GetText()) end)
    end
    copyBtn:ClearAllPoints()
    copyBtn:SetPoint("RIGHT", header, "RIGHT", -2, 0)
    clearBtn:ClearAllPoints()
    clearBtn:SetPoint("RIGHT", copyBtn, "LEFT", -6, 0)

    -- ── body backdrop ─────────────────────────────────────────
    local body = CreateFrame("Frame", nil, container, "BackdropTemplate")
    body:SetPoint("TOPLEFT", 0, -26)
    body:SetPoint("BOTTOMRIGHT", 0, 0)
    body:SetBackdrop({
        bgFile   = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })
    body:SetBackdropColor(0, 0, 0, 0.5)
    body:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)

    -- ── scrolling message frame ───────────────────────────────
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

    -- Replay buffer into the freshly-built SMF so re-opening the
    -- options window restores the previous transcript.
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

-- Internal hook for Task 5 / 6 confirmation flow tests.
ns._DiagnosticsConsoleInternal = {
    bufferLength = function() return #buffer end,
    maxLines     = MAX_LINES,
}
