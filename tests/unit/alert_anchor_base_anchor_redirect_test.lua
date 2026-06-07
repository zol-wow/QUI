-- tests/unit/alert_anchor_base_anchor_redirect_test.lua
-- Run: lua tests/unit/alert_anchor_base_anchor_redirect_test.lua
--
-- Regression guard: Blizzard may temporarily move AlertFrame's base anchor while
-- certain first-party panels are open. Collection reward alerts must still follow
-- QUI's Alert Anchor mover instead of that temporary base frame.

local function readFile(path)
    local fh = assert(io.open(path, "rb"), "failed to open " .. path)
    local text = fh:read("*a")
    fh:close()
    return text
end

local source = readFile("QUI_Skinning/skinning/notifications/alerts.lua")

assert(source:find("local function GetAlertAnchorRelativeFrame", 1, true),
    "alerts.lua must centralize AlertFrame holder redirection")
assert(source:find("relativeAlert == AlertFrame.baseAnchorFrame", 1, true),
    "alert anchor redirection must handle temporary AlertFrame.baseAnchorFrame values")
assert(source:find("relativeAlert == AlertFrame then return alertHolder", 1, true),
    "alert anchor redirection must continue handling the default AlertFrame base case")
assert(source:find("relativeAlert = GetAlertAnchorRelativeFrame(relativeAlert)", 1, true),
    "queued/simple alert anchor logic must route through the redirect helper")
assert(source:find("relativeAnchor = GetAlertAnchorRelativeFrame(relativeAnchor)", 1, true),
    "anchor-frame alert logic must route through the redirect helper")

print("OK: alert_anchor_base_anchor_redirect_test")
