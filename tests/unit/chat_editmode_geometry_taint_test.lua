-- tests/unit/chat_editmode_geometry_taint_test.lua
-- Run: lua tests/unit/chat_editmode_geometry_taint_test.lua
--
-- Regression: ChatFrame1 is an Edit Mode system frame. EditModeSystemMixin:
-- OnSystemLoad replaces its SetPoint/ClearAllPoints/SetScale with overrides that
-- re-enter EditModeManagerFrame (SetPointOverride -> OnEditModeSystemAnchorChanged).
-- Reparenting ChatFrame1 out of Edit Mode (DetachFromEditMode) does NOT remove
-- those per-instance overrides, so any QUI frame:SetPoint/frame:ClearAllPoints on
-- it still re-enters the secure manager from our tainted execution. That taints
-- ChatFrame1's OWN chat-event dispatch, and the next chat line carrying a secret
-- payload trips Blizzard's secret-string guard inside ChatHistory_GetToken:
--     attempt to perform string conversion on a secret string value
--     (execution tainted by 'QUI')   [HistoryKeeper.lua]:35
--
-- Fix: reposition ChatFrame1 through the saved *Base setters (the original C
-- methods, captured before the override swap) via Helpers.BaseSetPoint /
-- Helpers.BaseClearAllPoints, so positioning never re-enters Edit Mode. SetSize
-- is NOT overridden, so the size path may stay a plain call.
--
-- Covered always-on vectors:
--   0. chat.xml loads chat_frame1.lua before chat.lua, so startup detach exists
--   1. chat_frame1.lua ApplyStoredPosition  (runs on every login -> session taint)
--   2. anchoring.lua  SmoothSetPoint         (chat anchored via Frame Positioning)
--   3. anchoring.lua  QUI_ReanchorFramePositionOnly (settings/layout refresh)

local function readAll(path)
    local f = assert(io.open(path, "rb"), "failed to open " .. path)
    local d = f:read("*a"); f:close()
    return d:gsub("\r\n", "\n")
end

local function has(src, needle, msg)
    assert(src:find(needle, 1, true), msg)
end
local function hasnot(src, needle, msg)
    assert(not src:find(needle, 1, true), msg)
end

-- 0. The runtime chat addon must load the sizing/detach helper before chat.lua
--    calls it on ADDON_LOADED / PLAYER_ENTERING_WORLD. Loading it only from the
--    load-on-demand options addon leaves startup ChatFrame1 managed by Edit Mode.
local chatXML = readAll("modules/chat/chat.xml")
has(chatXML, [[<Script file="settings/chat_frame1.lua"/>]],
    "chat.xml must load the ChatFrame1 sizing/detach helper on the runtime path")
has(chatXML, [[<Script file="settings/chat_frame1.lua"/>
    <Script file="chat.lua"/>]],
    "chat.xml must load chat_frame1.lua before chat.lua")

local optionsXML = readAll("QUI_Options/options.xml")
hasnot(optionsXML, [[<Script file="..\QUI\modules\chat\settings\chat_frame1.lua"/>]],
    "options.xml must not load chat_frame1.lua a second time and reset its file-local detach state")

-- 1. The shared helpers exist and prefer the Edit Mode *Base originals.
local utils = readAll("core/utils.lua")
has(utils, "function Helpers.BaseClearAllPoints(frame)",
    "Helpers.BaseClearAllPoints must exist")
has(utils, "frame.ClearAllPointsBase or frame.ClearAllPoints",
    "BaseClearAllPoints must prefer the saved ClearAllPointsBase override-bypass")
has(utils, "function Helpers.BaseSetPoint(frame, ...)",
    "Helpers.BaseSetPoint must exist")
has(utils, "frame.SetPointBase or frame.SetPoint",
    "BaseSetPoint must prefer the saved SetPointBase override-bypass")

-- 2. The login reposition (ApplyStoredPosition) goes through the base helpers and
--    no longer calls the overridden frame:SetPoint/frame:ClearAllPoints directly.
local chat = readAll("modules/chat/settings/chat_frame1.lua")
has(chat, "Helpers.BaseClearAllPoints(frame)",
    "ApplyStoredPosition must clear points via the override-bypass helper")
has(chat, "Helpers.BaseSetPoint(frame, pos.point, UIParent, pos.relPoint or pos.point, x, y)",
    "ApplyStoredPosition must set the stored point via the override-bypass helper")
hasnot(chat, "frame:SetPoint(pos.point",
    "ApplyStoredPosition must not call the overridden frame:SetPoint (re-enters Edit Mode -> taints chat dispatch)")
hasnot(chat, "frame:ClearAllPoints()",
    "ApplyStoredPosition must not call the overridden frame:ClearAllPoints (re-enters Edit Mode -> taints chat dispatch)")

local chatProvider = readAll("modules/chat/settings/chat_frame1_provider.lua")
hasnot(chatProvider, "FCF_SetWindowSize",
    "ChatFrame1 size controls must never fall back to FCF_SetWindowSize")

-- 3. The anchoring choke point (SmoothSetPoint) also routes through the base
--    helpers, so anchoring a detached ChatFrame1 can't re-taint it either.
local anchoring = readAll("modules/layout/anchoring.lua")
has(anchoring, "H.BaseClearAllPoints(frame)",
    "SmoothSetPoint must clear points via the override-bypass helper")
has(anchoring, "H.BaseSetPoint(frame, pt, relativeTo, relPt, x, y)",
    "SmoothSetPoint must set the point via the override-bypass helper")
hasnot(anchoring, "frame:SetPoint(pt, relativeTo, relPt, x, y)",
    "SmoothSetPoint must not call the overridden frame:SetPoint (re-enters Edit Mode -> taints chat dispatch)")

-- 4. The position-only reanchor helper is another settings/layout refresh path
--    that can target ChatFrame1. It must use the same override-bypass helpers.
has(anchoring, "H.BaseClearAllPoints(resolved)",
    "QUI_ReanchorFramePositionOnly must clear points via the override-bypass helper")
has(anchoring, "H.BaseSetPoint(resolved, \"CENTER\", parentFrame, \"CENTER\", centerX, centerY)",
    "QUI_ReanchorFramePositionOnly must center-anchor via the override-bypass helper")
has(anchoring, "H.BaseSetPoint(resolved, point, parentFrame, relative, offsetX, offsetY)",
    "QUI_ReanchorFramePositionOnly must normal-anchor via the override-bypass helper")
hasnot(anchoring, "resolved:ClearAllPoints()",
    "QUI_ReanchorFramePositionOnly must not call the overridden resolved:ClearAllPoints")
hasnot(anchoring, "resolved:SetPoint(\"CENTER\", parentFrame",
    "QUI_ReanchorFramePositionOnly must not call the overridden center SetPoint")
hasnot(anchoring, "resolved:SetPoint(point, parentFrame",
    "QUI_ReanchorFramePositionOnly must not call the overridden normal SetPoint")

print("OK: chat_editmode_geometry_taint_test")
