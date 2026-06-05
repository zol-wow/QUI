local ADDON_NAME, ns = ...

local Helpers = ns.Helpers
ns.QUI = ns.QUI or {}
local ChatFrame1Sizing = ns.QUI.ChatFrame1Sizing or {}
ns.QUI.ChatFrame1Sizing = ChatFrame1Sizing

local Settings = ns.Settings
local ProviderFeatures = Settings and Settings.ProviderFeatures

-- ChatFrame1 size bounds. Lower limits match Blizzard's CHAT_FRAME_MIN_*; upper
-- limits are loose enough to allow large displays without being unbounded.
local CHAT_RESIZE_MIN_W, CHAT_RESIZE_MAX_W = 296, 1400
local CHAT_RESIZE_MIN_H, CHAT_RESIZE_MAX_H = 120, 900

-- Detach state. ChatFrame1 is an EditModeSystem frame; QUI only ever resizes or
-- repositions it AFTER detaching it from Blizzard's Edit Mode hierarchy (see
-- DetachFromEditMode). `detached` gates every SetSize/SetPoint we issue so we
-- can never taint the managed layout chain. `chatContainer` is the plain
-- reparent target; `editModeOverlayHome` is an off-screen home for Blizzard's
-- Edit Mode selection/resize widgets.
local detached = false
local chatContainer
local editModeOverlayHome

local function IsChatLayoutLockedDown()
    local I = ns.QUI and ns.QUI.Chat and ns.QUI.Chat._internals
    return (type(InCombatLockdown) == "function" and InCombatLockdown())
        or (I and I.IsChatMessagingLockedDown and I.IsChatMessagingLockedDown())
end

local function SafeFrameNumber(value, fallback)
    if Helpers and Helpers.IsSecretValue and Helpers.IsSecretValue(value) then
        return fallback or 0
    end
    return tonumber(value) or fallback or 0
end

local function ReadSafeNumber(value)
    if Helpers and Helpers.IsSecretValue and Helpers.IsSecretValue(value) then
        return nil
    end
    return tonumber(value)
end

local function ReadRoundedFrameNumber(value)
    value = ReadSafeNumber(value)
    if not value then return nil end
    return math.floor(value + 0.5)
end

local function IsSameFrameSize(frame, width, height)
    if not frame or type(frame.GetWidth) ~= "function" or type(frame.GetHeight) ~= "function" then
        return false
    end

    local currentWidth = ReadRoundedFrameNumber(frame:GetWidth())
    local currentHeight = ReadRoundedFrameNumber(frame:GetHeight())
    if not currentWidth or not currentHeight then return false end

    return currentWidth == math.floor(width + 0.5)
        and currentHeight == math.floor(height + 0.5)
end

local function SaveLegacyChatDimensions(frame)
    if frame and _G.FCF_SavePositionAndDimensions then
        _G.FCF_SavePositionAndDimensions(frame)
    end
end

-- QUI-owned chat size store. Edit Mode preset layouts (Modern/Classic) are
-- regenerated from code on load, so a size written into a preset's active
-- layout can't be saved and reverts on /reload. QUI therefore owns chat-frame
-- size outright: we mirror it into the QUI profile and re-apply on login (see
-- ApplyStoredSize). We deliberately do NOT write Blizzard's Edit Mode layout.
local function GetChatProfileDB()
    local core = Helpers and Helpers.GetCore and Helpers.GetCore()
    return core and core.db and core.db.profile and core.db.profile.chat
end

-- True when the user has anchored "Chat Frame" via the Frame Positioning panel.
-- In that case the anchoring system owns ChatFrame1's position (it applies a
-- live SetPoint to the chosen target), so our stored drag position stands down
-- to avoid the two systems fighting. Size stays QUI-owned either way.
local function HasSavedChatFrameAnchor()
    local core = Helpers and Helpers.GetCore and Helpers.GetCore()
    local fa = core and core.db and core.db.profile and core.db.profile.frameAnchoring
    return type(fa) == "table" and type(fa.chatFrame1) == "table"
end

local function StoreChatFrameSize(width, height)
    width = ReadSafeNumber(width)
    height = ReadSafeNumber(height)
    if not width or not height then return end
    local chatDB = GetChatProfileDB()
    if not chatDB then return end
    chatDB.frameSize = chatDB.frameSize or {}
    chatDB.frameSize.w = math.floor(width + 0.5)
    chatDB.frameSize.h = math.floor(height + 0.5)
end

function ChatFrame1Sizing.PersistSize(frame, width, height)
    frame = frame or _G.ChatFrame1
    -- Profile store is the source of truth; SaveLegacyChatDimensions keeps the
    -- legacy floating-chat config (position + dimensions) coherent. No Edit
    -- Mode layout write — see the store comment above.
    StoreChatFrameSize(width, height)
    SaveLegacyChatDimensions(frame)
    return true
end

-- Re-apply the QUI-stored chat size to the live frame. Called deferred on
-- login after Edit Mode restores its (possibly preset) layout size, so QUI's
-- size wins. Only resizes the live frame — it does not re-persist. No-op when
-- nothing is stored or the size already matches.
function ChatFrame1Sizing.ApplyStoredSize()
    -- Never size a still-Edit-Mode-managed frame -- that is the taint vector.
    if not detached then return false end
    local chatDB = GetChatProfileDB()
    local stored = chatDB and chatDB.frameSize
    if type(stored) ~= "table" then return false end
    local width = ReadSafeNumber(stored.w)
    local height = ReadSafeNumber(stored.h)
    if not width or not height then return false end
    local frame = _G.ChatFrame1
    if not frame then return false end
    if IsChatLayoutLockedDown() then return false end
    if IsSameFrameSize(frame, width, height) then return false end
    -- Plain SetSize only: ChatFrame1 is detached, so this no longer re-enters
    -- Blizzard's Edit Mode sizing chain. (FCF_SetWindowSize WOULD re-enter it.)
    frame:SetSize(width, height)
    return true
end

function ChatFrame1Sizing.PersistCurrentSize(frame)
    frame = frame or _G.ChatFrame1
    if not frame or type(frame.GetWidth) ~= "function" or type(frame.GetHeight) ~= "function" then
        return false
    end

    local width = ReadSafeNumber(frame:GetWidth())
    local height = ReadSafeNumber(frame:GetHeight())
    if not width or not height then
        SaveLegacyChatDimensions(frame)
        return false
    end

    return ChatFrame1Sizing.PersistSize(frame, width, height)
end

function ChatFrame1Sizing.SetSize(width, height)
    local frame = _G.ChatFrame1
    if not frame or type(width) ~= "number" or type(height) ~= "number" then return false end
    -- Refuse to size until detached from Edit Mode (login detach normally runs
    -- well before any settings UI is reachable, so this is effectively always
    -- satisfied at user-interaction time).
    if not detached then return false end
    if IsChatLayoutLockedDown() then return false end
    if IsSameFrameSize(frame, width, height) then return false end

    -- Plain SetSize: ChatFrame1 is detached from the Edit Mode layout chain.
    frame:SetSize(width, height)

    ChatFrame1Sizing.PersistSize(frame, width, height)

    if _G.QUI_RefreshChatSizeSliders then
        _G.QUI_RefreshChatSizeSliders()
    end

    return true
end

---------------------------------------------------------------------------
-- Detach ChatFrame1 from Blizzard's Edit Mode hierarchy + own its position.
--
-- ChatFrame1 is an EditModeSystem frame. Resizing/repositioning it from addon
-- (tainted) code while it is Edit-Mode-managed taints the frame's secure
-- layout chain; that taint then surfaces on the frame's OWN chat-event
-- dispatch and trips Blizzard's secret-string guard the moment a public
-- channel body (e.g. LookingForGroup) is a secret value -- Blizzard's own
-- gsub on the message body in ChatFrameOverrides' MessageFormatter throws
-- "string conversion on a secret string value (execution tainted by 'QUI')".
--
-- Reparenting ChatFrame1 under a plain container -- once, before any secret
-- chat payload is processed -- removes it from the managed layout chain, so
-- plain SetSize/SetPoint on it no longer taint. Blizzard then no longer
-- persists the frame's position, so QUI owns it: profile.chat.framePosition is
-- stored (lazily, like frameSize) and re-applied on login.
--
-- We deliberately do NOT install a SetPoint/SetParent hooksecurefunc. A
-- reactive hook re-fires during chat event processing and re-taints the secure
-- chain (the very thing we are removing). Position may drift if Blizzard tries
-- to re-assert it; we accept that -- taint-free chat is the priority.
---------------------------------------------------------------------------

function ChatFrame1Sizing.IsDetached()
    return detached
end

local function StorePosition(point, relPoint, x, y)
    if type(point) ~= "string" then return false end
    x = ReadSafeNumber(x)
    y = ReadSafeNumber(y)
    if not x or not y then return false end
    local chatDB = GetChatProfileDB()
    if not chatDB then return false end
    chatDB.framePosition = {
        point = point,
        relPoint = (type(relPoint) == "string" and relPoint) or point,
        x = math.floor(x + 0.5),
        y = math.floor(y + 0.5),
    }
    return true
end

-- Exposed for the layout-mode mover's savePosition callback.
function ChatFrame1Sizing.StorePosition(point, relPoint, x, y)
    return StorePosition(point, relPoint, x, y)
end

function ChatFrame1Sizing.PersistCurrentPosition(frame)
    frame = frame or _G.ChatFrame1
    if not frame or type(frame.GetPoint) ~= "function" then return false end
    local ok, point, _, relPoint, x, y = pcall(frame.GetPoint, frame, 1)
    if not ok or type(point) ~= "string" then return false end
    return StorePosition(point, relPoint, x, y)
end

function ChatFrame1Sizing.ApplyStoredPosition()
    -- Only reposition once detached (same invariant as sizing).
    if not detached then return false end
    -- Defer to the anchoring system when the user anchored chat via the Frame
    -- Positioning panel (it owns position then; ours would fight it).
    if HasSavedChatFrameAnchor() then return false end
    local chatDB = GetChatProfileDB()
    local pos = chatDB and chatDB.framePosition
    if type(pos) ~= "table" or type(pos.point) ~= "string" then return false end
    local x = ReadSafeNumber(pos.x)
    local y = ReadSafeNumber(pos.y)
    if not x or not y then return false end
    local frame = _G.ChatFrame1
    if not frame then return false end
    if IsChatLayoutLockedDown() then return false end
    -- Preserve the current size across the re-anchor. If Edit Mode sized the
    -- frame via two anchors, ClearAllPoints would otherwise collapse it; pinning
    -- the captured dimensions afterward keeps the frame intact regardless of the
    -- prior anchoring scheme. (A later ApplyStoredSize applies any custom size.)
    local w = (type(frame.GetWidth) == "function") and ReadSafeNumber(frame:GetWidth()) or nil
    local h = (type(frame.GetHeight) == "function") and ReadSafeNumber(frame:GetHeight()) or nil
    -- ChatFrame1 is an Edit Mode system frame whose SetPoint/ClearAllPoints are
    -- overridden to re-enter EditModeManagerFrame. Reparenting it (DetachFromEditMode)
    -- does NOT remove those overrides, so calling them here -- from our tainted
    -- login path -- taints ChatFrame1's own chat-event dispatch and trips
    -- Blizzard's secret-string guard (ChatHistory_GetToken) on the next secret
    -- chat line. Use the saved *Base setters so positioning never re-enters Edit
    -- Mode. (SetSize is not overridden, so ApplyStoredSize stays a plain call.)
    Helpers.BaseClearAllPoints(frame)
    Helpers.BaseSetPoint(frame, pos.point, UIParent, pos.relPoint or pos.point, x, y)
    if w and h and type(frame.SetSize) == "function" then
        frame:SetSize(w, h)
    end
    return true
end

local function GetEditModeOverlayHome()
    if not editModeOverlayHome and type(CreateFrame) == "function" then
        editModeOverlayHome = CreateFrame("Frame", nil, UIParent)
        if editModeOverlayHome and editModeOverlayHome.Hide then
            editModeOverlayHome:Hide()
        end
    end
    return editModeOverlayHome
end

-- Reparent ChatFrame1 out of Blizzard's Edit Mode hierarchy. One-time and
-- idempotent; must run before any secret chat payload is processed (callers
-- invoke it on login). Returns false (without detaching) under combat/messaging
-- lockdown so the caller can retry on a lockdown-end event.
function ChatFrame1Sizing.DetachFromEditMode()
    if detached then return true end
    local frame = _G.ChatFrame1
    if not frame or type(frame.SetParent) ~= "function" then return false end
    if type(InCombatLockdown) == "function" and InCombatLockdown() then return false end
    if IsChatLayoutLockedDown() then return false end
    if type(CreateFrame) ~= "function" then return false end

    -- Seed position from the live (Blizzard-restored) frame before reparenting,
    -- so we keep the current position and don't visually jump.
    local chatDB = GetChatProfileDB()
    if chatDB and type(chatDB.framePosition) ~= "table" then
        ChatFrame1Sizing.PersistCurrentPosition(frame)
    end

    chatContainer = chatContainer or CreateFrame("Frame", "QUIChatFrame1Container", UIParent)
    if chatContainer.SetAllPoints then chatContainer:SetAllPoints(UIParent) end
    if chatContainer.EnableMouse then chatContainer:EnableMouse(false) end

    frame:SetParent(chatContainer)
    if frame.SetClampedToScreen then frame:SetClampedToScreen(false) end

    -- Pull Blizzard's Edit Mode selection + resize widgets off-screen so they
    -- never render and QUI never needs to poke Edit Mode selection state.
    local hidden = GetEditModeOverlayHome()
    if hidden then
        if frame.Selection and frame.Selection.SetParent then
            pcall(frame.Selection.SetParent, frame.Selection, hidden)
        end
        if frame.EditModeResizeButton and frame.EditModeResizeButton.SetParent then
            pcall(frame.EditModeResizeButton.SetParent, frame.EditModeResizeButton, hidden)
        end
    end

    detached = true
    return true
end

-- Login / lockdown-end entry point: detach once, then re-assert QUI-owned
-- position + size. Guarded + idempotent. No-op (and no taint) while the chat
-- module is disabled -- we leave ChatFrame1 to Blizzard entirely in that case.
function ChatFrame1Sizing.SyncToStored()
    local chatDB = GetChatProfileDB()
    if chatDB and chatDB.enabled == false then return false end
    ChatFrame1Sizing.DetachFromEditMode()
    if not detached then return false end  -- locked down; caller retries
    ChatFrame1Sizing.ApplyStoredPosition()
    ChatFrame1Sizing.ApplyStoredSize()
    return true
end

if not ProviderFeatures or type(ProviderFeatures.Register) ~= "function" then
    return
end

local function ChatGetSize()
    local f = _G.ChatFrame1
    if not f then return CHAT_RESIZE_MIN_W, CHAT_RESIZE_MIN_H end
    return SafeFrameNumber(f:GetWidth(), CHAT_RESIZE_MIN_W), SafeFrameNumber(f:GetHeight(), CHAT_RESIZE_MIN_H)
end

local function ChatSetSize(w, h)
    ChatFrame1Sizing.SetSize(w, h)
end

local function ApplyChat()
    if _G.QUI_RefreshChat then
        _G.QUI_RefreshChat()
    end
end

local function RenderChatLayout(host, options)
    local providerKey = (options and options.providerKey) or "chatFrame1"
    local U = ns.QUI_LayoutMode_Utils
    local Settings2 = ns.Settings
    local RenderAdapters = Settings2 and Settings2.RenderAdapters
    if not host or not U
        or type(U.BuildPositionCollapsible) ~= "function"
        or type(U.BuildSizeCollapsible) ~= "function"
        or type(U.StandardRelayout) ~= "function" then
        if RenderAdapters and type(RenderAdapters.RenderPositionOnly) == "function" then
            return RenderAdapters.RenderPositionOnly(host, providerKey)
        end
        return 80
    end

    local prevPosOnly = U._layoutModePositionOnly
    U._layoutModePositionOnly = false
    local sections = {}
    local function relayout() U.StandardRelayout(host, sections) end
    local ok, err = xpcall(function()
        U.BuildPositionCollapsible(host, providerKey, nil, sections, relayout)
        U.BuildSizeCollapsible(host, {
            getSize = ChatGetSize,
            setSize = ChatSetSize,
            minW = CHAT_RESIZE_MIN_W, maxW = CHAT_RESIZE_MAX_W,
            minH = CHAT_RESIZE_MIN_H, maxH = CHAT_RESIZE_MAX_H,
            widthDescription  = "ChatFrame1 width in pixels. Blizzard persists this across logout.",
            heightDescription = "ChatFrame1 height in pixels. Blizzard persists this across logout.",
        }, sections, relayout)
        relayout()
    end, function(msg) return msg end)
    U._layoutModePositionOnly = prevPosOnly
    if not ok and geterrorhandler then geterrorhandler()(err) end
    return host:GetHeight()
end

local function RegisterChatFeature(id, subPageIndex, chatSections, includeLayoutRenderer)
    local feature = {
        id = id,
        moverKey = "chatFrame1",
        lookupKeys = { id },
        category = "chat",
        nav = {
            tileId = "chat_tooltips",
            subPageIndex = subPageIndex,
        },
        getDB = function(profile)
            return profile and profile.chat
        end,
        apply = ApplyChat,
        providerKey = "chatFrame1",
        providerOptions = {
            chatSections = chatSections,
        },
        render = includeLayoutRenderer and {
            layout = RenderChatLayout,
        } or nil,
    }

    if includeLayoutRenderer then
        feature.layoutPositionOnly = false
    end

    ProviderFeatures:Register(feature)
end

RegisterChatFeature("chatFrame1", 1, "general", true)
RegisterChatFeature("chatFrame1Filters", 2, "filters")
RegisterChatFeature("chatFrame1ButtonBar", 3, "buttonBar")
RegisterChatFeature("chatFrame1Alerts", 4, "alerts")
RegisterChatFeature("chatFrame1History", 5, "history")
