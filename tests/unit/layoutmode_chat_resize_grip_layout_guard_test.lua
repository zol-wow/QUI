-- tests/unit/layoutmode_chat_resize_grip_layout_guard_test.lua
-- Run: lua tests/unit/layoutmode_chat_resize_grip_layout_guard_test.lua
--
-- Regression guard for: "QUI_CustomChatFrame:StartSizing(): Frame is not
-- resizable" + Lua Taint: QUI (layoutmode.lua grip OnMouseDown).
--
-- The QUI chat container is SetResizable(true) only while Layout Mode is
-- active — display_layer.RefreshInteractionState() runs at window creation
-- and on every layout enter/exit, setting SetResizable(IsLayoutModeActive()).
-- So calling the protected StartSizing() on it outside Layout Mode throws
-- "Frame is not resizable" and taints QUI. display_layer's own bottom-right
-- resize grip guards every StartSizing/StopMovingOrSizing with an
-- IsLayoutModeActive() check; the four-corner grips in SetupChatWindowOverlay
-- must do the same, or a grip firing while Layout Mode is inactive crashes.

local function readAll(path)
    local f = assert(io.open(path, "rb"))
    local d = f:read("*a")
    f:close()
    return d:gsub("\r\n", "\n")
end

local source = readAll("modules/layout/layoutmode.lua")

-- Isolate the shared chat-window overlay builder (primary + windows 2+ grips).
local fnPos = assert(source:find("local function SetupChatWindowOverlay(", 1, true),
    "SetupChatWindowOverlay must exist")
local fnEnd = assert(source:find("local function PersistPrimaryChatGeometry", fnPos, true),
    "SetupChatWindowOverlay must be followed by PersistPrimaryChatGeometry")
local block = source:sub(fnPos, fnEnd - 1)

-- Plain-text "find the last occurrence of needle at or before limit".
local function findLastBefore(s, needle, limit)
    local last, from = nil, 1
    while true do
        local p = s:find(needle, from, true)
        if not p or p > limit then break end
        last, from = p, p + 1
    end
    return last
end

-- The grip OnMouseDown calls the protected StartSizing on the container.
local sizePos = assert(block:find("f:StartSizing(corner)", 1, true),
    "grip OnMouseDown must call f:StartSizing(corner)")

-- Find the OnMouseDown handler that encloses that StartSizing call and assert
-- it bails when Layout Mode is inactive BEFORE reaching StartSizing.
local downPos = assert(findLastBefore(block, 'SetScript("OnMouseDown"', sizePos),
    "StartSizing must live inside an OnMouseDown handler")
local downToSize = block:sub(downPos, sizePos)
assert(downToSize:find("QUI_LayoutMode.isActive", 1, true)
        or downToSize:find("IsLayoutModeActive", 1, true),
    "grip OnMouseDown must check Layout Mode active state before StartSizing "
    .. "(else StartSizing throws 'Frame is not resizable' + taints QUI)")

-- ...and it must GUARANTEE the resizable flag at the point of use. The
-- layout-active gate alone is not enough: in-game the container is reported
-- not-resizable even while Layout Mode is active (display_layer's SetResizable
-- toggle can lag/miss this window), so StartSizing still throws. The grip must
-- SetResizable(true) before StartSizing. (SetResizable is not a protected
-- function — no taint.)
assert(downToSize:find("f:SetResizable(true)", 1, true)
        or downToSize:find("SetResizable(true)", 1, true),
    "grip OnMouseDown must ensure f:SetResizable(true) before StartSizing "
    .. "(layout-active alone does not guarantee the frame is resizable in-game)")

-- StopMovingOrSizing path must be gated the same way (mirror display_layer).
local stopPos = assert(block:find("f:StopMovingOrSizing()", 1, true),
    "grip OnMouseUp must call f:StopMovingOrSizing()")
local upPos = assert(findLastBefore(block, 'SetScript("OnMouseUp"', stopPos),
    "StopMovingOrSizing must live inside an OnMouseUp handler")
local upToStop = block:sub(upPos, stopPos)
assert(upToStop:find("QUI_LayoutMode.isActive", 1, true)
        or upToStop:find("IsLayoutModeActive", 1, true),
    "grip OnMouseUp must check Layout Mode active state before StopMovingOrSizing")

-- Damage-meter alignment (display_layer): the container's resizable flag is set
-- ONCE at creation and NEVER toggled with layout-mode state. Toggling it is what
-- raced the grip (flag false at click time). "Only resizable in Layout Mode" is
-- enforced by the gated affordances, not by flipping SetResizable off.
local dl = readAll("QUI_Chat/chat/display_layer.lua")
assert(dl:find("container:SetResizable(true)", 1, true),
    "display_layer must create the container SetResizable(true) (damage-meter pattern)")

local riStart = assert(dl:find("local function RefreshInteractionState()", 1, true),
    "display_layer must define RefreshInteractionState")
local riEnd = assert(dl:find("local layoutCallbacksRegistered", riStart, true),
    "RefreshInteractionState must be followed by layoutCallbacksRegistered")
local riBody = dl:sub(riStart, riEnd - 1)
assert(not riBody:find("SetResizable", 1, true),
    "RefreshInteractionState must NOT toggle SetResizable — that flag-toggle "
    .. "raced the resize grips (StartSizing 'Frame is not resizable'); the flag "
    .. "stays true (set at creation) and resize is gated at the affordance")

-- ---------------------------------------------------------------------------
-- Anchored = locked resize (Shift detaches + resizes), shared with move-lock.
-- ---------------------------------------------------------------------------

-- Shared helpers must exist on QUI_LayoutMode (one definition for chat + dm).
for _, fn in ipairs({ "IsElementAnchored", "FlashLockedHandle", "DetachElementAnchor" }) do
    assert(source:find("function QUI_LayoutMode:" .. fn .. "(", 1, true),
        "QUI_LayoutMode:" .. fn .. " must be defined (shared anchor-lock helper)")
end

-- The chat resize grip must consult the anchor lock + Shift override BEFORE
-- StartSizing: anchored + no Shift = inert (flash), anchored + Shift = detach.
assert(downToSize:find("IsElementAnchored", 1, true),
    "chat grip OnMouseDown must check IsElementAnchored before StartSizing")
assert(downToSize:find("IsShiftKeyDown", 1, true),
    "chat grip OnMouseDown must honor Shift as the resize-while-anchored override")
assert(downToSize:find("DetachElementAnchor", 1, true),
    "chat grip must detach the anchor on Shift-resize (parity with Shift-drag)")

-- The move-lock (OnDragStart) must route through the SAME helper so move-lock
-- and resize-lock cannot drift apart.
local dragPos = assert(source:find('handle:SetScript("OnDragStart"', 1, true),
    "OnDragStart handler must exist")
local dragBody = source:sub(dragPos, dragPos + 1200)
assert(dragBody:find("IsElementAnchored", 1, true),
    "OnDragStart must use QUI_LayoutMode:IsElementAnchored (shared lock definition)")

-- The damage-meter resize grip must gate identically (lock + Shift + detach).
local dm = readAll("QUI_DamageMeter/damage_meter/damage_meter.lua")
local dmDownPos = assert(dm:find('grip:SetScript("OnMouseDown"', 1, true),
    "dm grip OnMouseDown handler must exist")
-- StartSizing AFTER the handler start (an earlier doc comment also mentions it).
local dmSizePos = assert(dm:find("frame:StartSizing(corner)", dmDownPos, true),
    "dm grip OnMouseDown must call frame:StartSizing(corner)")
local dmDownToSize = dm:sub(dmDownPos, dmSizePos)
assert(dmDownToSize:find("IsElementAnchored", 1, true)
        and dmDownToSize:find("IsShiftKeyDown", 1, true)
        and dmDownToSize:find("DetachElementAnchor", 1, true),
    "dm grip OnMouseDown must check IsElementAnchored + Shift + DetachElementAnchor "
    .. "before StartSizing (same lock as chat)")

print("OK: layoutmode_chat_resize_grip_layout_guard_test")
