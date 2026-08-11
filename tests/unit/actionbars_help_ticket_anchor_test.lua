-- tests/unit/actionbars_help_ticket_anchor_test.lua
-- Run: lua tests/unit/actionbars_help_ticket_anchor_test.lua
--
-- Blizzard anchors HelpOpenWebTicketButton to the edge button of its own
-- MicroMenu (MicroMenuMixin:UpdateHelpTicketButtonAnchor → GetEdgeButton).
-- With the micro buttons reclaimed into QUI's microbar container,
-- GetEdgeButton() returns nil and Blizzard's SetPoint("CENTER", nil, ...)
-- drops the open-ticket icon at screen center. QUI must re-anchor it to
-- the reclaimed character micro button.

local function readFile(path)
    local fh = assert(io.open(path, "rb"), "failed to open " .. path)
    local text = fh:read("*a")
    fh:close()
    return text
end

local layoutSource = readFile("QUI_ActionBars/actionbars/actionbars_layout.lua")
local builderSource = readFile("QUI_ActionBars/actionbars/actionbars_builder.lua")
local defaultsSource = readFile("core/defaults.lua")
local perBarSource = readFile("QUI_ActionBars/actionbars/actionbars_per_bar_builders.lua")

local function blockBetween(source, startText, endText)
    local startPos = assert(source:find(startText, 1, true), "missing block start: " .. startText)
    local endPos = assert(source:find(endText, startPos, true), "missing block end: " .. endText)
    return source:sub(startPos, endPos - 1)
end

local anchorFn = blockBetween(layoutSource, "AnchorHelpTicketButton = function", "LayoutNativeButtons = function")

assert(
    anchorFn:find("_G.HelpOpenWebTicketButton", 1, true)
        and anchorFn:find("_G.CharacterMicroButton", 1, true),
    "ticket icon re-anchor must target HelpOpenWebTicketButton against CharacterMicroButton")

-- Blizzard's UpdateHelpTicketButtonAnchor replaces the button's single
-- CENTER point in place. QUI must reuse that same point: ClearAllPoints
-- plus a TOP/BOTTOM point makes Blizzard's secure SetPoint ADD a second
-- point, bridging two anchor families — Edit Mode's secure layout pass
-- blocks that on zone-in ("anchor family connection" warnings).
assert(
    not anchorFn:find("ClearAllPoints", 1, true),
    "ticket icon re-anchor must not ClearAllPoints — Blizzard replaces the CENTER point in place")

assert(
    anchorFn:find('SetPoint("CENTER", charBtn', 1, true)
        and not anchorFn:find('SetPoint("TOP"', 1, true)
        and not anchorFn:find('SetPoint("BOTTOM"', 1, true),
    "ticket icon must keep exactly one anchor point, on CENTER, like Blizzard's own code")

assert(
    anchorFn:find("ActionBarsOwned._microOwnedByUI", 1, true),
    "ticket icon re-anchor must yield while Blizzard owns the micro buttons (vehicle/pet battle)")

assert(
    anchorFn:find("InCombatLockdown", 1, true)
        and anchorFn:find("_helpTicketAnchorAbove", 1, true),
    "ticket icon side decision must skip GetCenter in combat and reuse the cached side")

local microLayoutBlock = blockBetween(layoutSource, 'if barKey == "microbar" then', "container.MarkClean")
assert(
    microLayoutBlock:find("AnchorHelpTicketButton()", 1, true),
    "microbar layout pass must re-anchor the open-ticket icon")

assert(
    builderSource:find('hooksecurefunc(MicroMenu, "UpdateHelpTicketButtonAnchor"', 1, true),
    "builder must fix the ticket icon right after Blizzard re-centers it")

local hookBlock = blockBetween(builderSource,
    'hooksecurefunc(MicroMenu, "UpdateHelpTicketButtonAnchor"',
    "hooksecurefunc(\"UpdateMicroButtons\"")
assert(
    hookBlock:find("AnchorHelpTicketButton()", 1, true),
    "UpdateHelpTicketButtonAnchor posthook must call the shared re-anchor helper")

assert(
    hookBlock:find("C_Timer.After(0", 1, true),
    "UpdateHelpTicketButtonAnchor posthook must defer out of Edit Mode's secure anchor pass")

-- User-facing positioning options (per-bar page → Micro Menu → Ticket Icon)
assert(
    anchorFn:find("barDB.ticketIcon", 1, true)
        and anchorFn:find('mode == "above"', 1, true)
        and anchorFn:find('mode == "below"', 1, true)
        and anchorFn:find("offX", 1, true)
        and anchorFn:find("offY", 1, true),
    "ticket icon re-anchor must honor the ticketIcon position/offset settings")

assert(
    defaultsSource:find('ticketIcon = { position = "auto", offsetX = 0, offsetY = 0 }', 1, true),
    "microbar defaults must seed the ticketIcon settings table")

local ticketOptionsBlock = blockBetween(perBarSource,
    'if dbKey == "microbar" then\n                barDB.ticketIcon',
    "if SKINNABLE_BAR_KEYS[dbKey] then")
assert(
    ticketOptionsBlock:find('"position", ticketDB', 1, true)
        and ticketOptionsBlock:find('"offsetX", ticketDB', 1, true)
        and ticketOptionsBlock:find('"offsetY", ticketDB', 1, true),
    "per-bar Micro Menu page must expose ticket icon position and offset controls")

print("OK: actionbars_help_ticket_anchor_test")
