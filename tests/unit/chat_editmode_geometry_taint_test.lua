-- tests/unit/chat_editmode_geometry_taint_test.lua
-- Run: lua tests/unit/chat_editmode_geometry_taint_test.lua
--
-- Regression: ChatFrame1 is an Edit Mode system frame whose event script enters
-- Blizzard's protected chat HistoryKeeper tables. Runtime addon calls that
-- reparent or reposition ChatFrame1 can taint that dispatch path before a
-- channel notice reaches ChatHistory_GetAccessID. The runtime chat addon must
-- therefore not load or call the old ChatFrame1 detach/geometry helper.
--
-- Covered vectors:
--   0. QUI.toc does not load chat_frame1.lua on the runtime path
--   1. options.xml does not load it either (the helper is DELETED — the
--      takeover suppresses ChatFrame1 and never sizes/positions it)
--   2. chat.lua does not call ChatFrame1Sizing.DetachFromEditMode/SyncToStored
--   3. shared anchoring still uses *Base setters for any system frame it owns

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

-- 0. The runtime chat addon must not load the sizing/detach helper. It stays in
--    the load-on-demand options addon only, so normal chat startup never calls
--    protected ChatFrame1 geometry paths.
local chatXML = readAll("QUI.toc")
hasnot(chatXML, [[modules\chat\settings\chat_frame1.lua]],
    "QUI.toc must not load the ChatFrame1 sizing/detach helper on the runtime path")

local optionsXML = readAll("QUI_Options/QUI_Options.toc")
hasnot(optionsXML, [[chat_frame1.lua]],
    "QUI_Options.toc must not load the deleted ChatFrame1 sizing/detach helper")

local chatRuntime = readAll("QUI_Chat/chat/chat.lua")
hasnot(chatRuntime, "DetachFromEditMode",
    "runtime chat.lua must not call ChatFrame1Sizing.DetachFromEditMode")
hasnot(chatRuntime, "SyncToStored",
    "runtime chat.lua must not call ChatFrame1Sizing.SyncToStored")

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

-- 2. The sizing/detach helper is DELETED — nothing may resurrect ChatFrame1
--    geometry mutation in the provider.
local chatProvider = readAll("QUI_Chat/chat/settings/chat_frame1_provider.lua")
hasnot(chatProvider, "ChatFrame1Sizing",
    "the deleted ChatFrame1 sizing helper must not be referenced by the provider")
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
