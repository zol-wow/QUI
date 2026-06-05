-- modules/chat/display_layer.lua
-- The custom chat display: QUI_CustomChatFrame (movable/resizable, glass
-- backdrop) containing a ScrollingMessageFrame view of MessageStore.
-- ScrollingMessageFrame is an intrinsic widget (Blizzard_SharedXML/
-- ScrollingMessageFrame.xml:3); its render path re-initializes fontstrings
-- "to clear secret aspects" before SetText (ScrollingMessageFrame.lua:632-635)
-- so secret entries pass straight through AddMessage untouched.
--
-- All geometry here is OUR OWN insecure frame — no protected-frame writes,
-- no combat deferral needed (the ChatFrame1 geometry constraint concerns
-- Blizzard's frame only, which this file never touches).
local ADDON_NAME, ns = ...
local Helpers = ns.Helpers
local UIKit = ns.UIKit

local I = assert(ns.QUI.Chat and ns.QUI.Chat._internals,
    "QUI Chat: display_layer.lua loaded before chat.lua. Check chat.xml — chat.lua must precede display_layer.lua.")

ns.QUI.Chat.DisplayLayer = ns.QUI.Chat.DisplayLayer or {}
local Display = ns.QUI.Chat.DisplayLayer

local Store = assert(ns.QUI.Chat.MessageStore, "message_store.lua must load before display_layer.lua")

local container, smf
local activeFilter -- set via Display.Rebuild; live appends respect it

local DRAG_STRIP_HEIGHT = 14
local MIN_W, MIN_H = 220, 100

local function GetCustomDisplaySettings()
    local settings = I.GetSettings and I.GetSettings()
    return settings and settings.customDisplay, settings
end

-- Position persists in the codebase-standard sub-table shape:
-- customDisplay.position = { point, relPoint, x, y } (see defaults.lua).
local function SaveGeometry()
    local cd = GetCustomDisplaySettings()
    if not cd or not container then return end
    local point, _, relPoint, x, y = container:GetPoint(1)
    if point then
        cd.position = cd.position or {}
        cd.position.point, cd.position.relPoint = point, relPoint or point
        cd.position.x, cd.position.y = x, y
    end
    cd.width = math.floor((container:GetWidth() or cd.width) + 0.5)
    cd.height = math.floor((container:GetHeight() or cd.height) + 0.5)
end

local function ApplySavedGeometry()
    local cd = GetCustomDisplaySettings()
    if not cd or not container then return end
    container:SetSize(cd.width or 430, cd.height or 190)
    container:ClearAllPoints()
    local pos = cd.position or {}
    container:SetPoint(pos.point or "BOTTOMLEFT", _G.UIParent, pos.relPoint or pos.point or "BOTTOMLEFT", pos.x or 35, pos.y or 40)
end

-- Render one entry into the SMF. Color override is resolved at RENDER time
-- via channel_colors' registered resolver (never ChatTypeInfo writes).
-- Secrets: no resolver call, no operators — straight to AddMessage.
local function RenderEntry(entry)
    if not smf then return end
    local r, g, b = entry.r or 1, entry.g or 1, entry.b or 1
    if not entry.s then
        local resolver = ns.QUI.Chat._lineColorResolver
        if resolver and entry.e then
            local orR, orG, orB = resolver(entry.e, entry.ch and { [9] = entry.ch } or nil)
            if orR then r, g, b = orR, orG, orB end
        end
    end
    smf:AddMessage(entry.m, r, g, b)
end

-- Secrets ALWAYS pass the filter — never classify them.
local function PassesFilter(entry)
    if entry.s then return true end
    if not activeFilter then return true end
    return activeFilter(entry) and true or false
end

local function OnStoreAppend(entry)
    if not container or not container:IsShown() then return end
    if PassesFilter(entry) then
        RenderEntry(entry)
    end
end

function Display.EnsureCreated()
    if container then return end
    local cd = GetCustomDisplaySettings()

    container = CreateFrame("Frame", "QUI_CustomChatFrame", _G.UIParent, "BackdropTemplate")
    container:SetFrameStrata("LOW")
    container:SetClampedToScreen(true)
    container:SetMovable(true)
    container:SetResizable(true)
    container:SetResizeBounds(MIN_W, MIN_H)
    if UIKit and UIKit.ApplyPixelBackdrop then
        UIKit.ApplyPixelBackdrop(container, 1, true)
    end
    -- Persist colors via Helpers so scale-refresh rebuilds keep them.
    if Helpers and Helpers.SetFrameBackdropColor then
        Helpers.SetFrameBackdropColor(container, 0, 0, 0, (cd and cd.bgAlpha) or 0.25)
        Helpers.SetFrameBackdropBorderColor(container, 0, 0, 0, 1)
    end

    -- Top drag strip (keeps the message area free for hyperlink clicks).
    local drag = CreateFrame("Frame", nil, container)
    drag:SetPoint("TOPLEFT", container, "TOPLEFT", 0, 0)
    drag:SetPoint("TOPRIGHT", container, "TOPRIGHT", 0, 0)
    drag:SetHeight(DRAG_STRIP_HEIGHT) -- width derives from the two anchors
    drag:EnableMouse(true)
    drag:SetScript("OnMouseDown", function() container:StartMoving() end)
    drag:SetScript("OnMouseUp", function()
        container:StopMovingOrSizing()
        SaveGeometry()
    end)

    -- Bottom-right resize grip.
    local grip = CreateFrame("Frame", nil, container)
    grip:SetPoint("BOTTOMRIGHT", container, "BOTTOMRIGHT", 0, 0)
    grip:SetSize(14, 14)
    grip:EnableMouse(true)
    grip:SetScript("OnMouseDown", function() container:StartSizing("BOTTOMRIGHT") end)
    grip:SetScript("OnMouseUp", function()
        container:StopMovingOrSizing()
        SaveGeometry()
    end)

    smf = CreateFrame("ScrollingMessageFrame", "QUI_CustomChatMessages", container)
    smf:SetPoint("TOPLEFT", container, "TOPLEFT", 6, -(DRAG_STRIP_HEIGHT + 2))
    smf:SetPoint("BOTTOMRIGHT", container, "BOTTOMRIGHT", -6, 6)
    smf:SetFontObject(_G.ChatFontNormal)
    smf:SetJustifyH("LEFT")
    smf:SetFading(false)
    smf:SetMaxLines((cd and cd.maxLines) or 1000)
    smf:SetHyperlinksEnabled(true)
    smf:SetScript("OnHyperlinkClick", function(self, link, text, button)
        if _G.SetItemRef then _G.SetItemRef(link, text, button, self) end
    end)
    -- Wheel scrolls 3 lines; Ctrl+wheel-down jumps to the newest line.
    smf:SetScript("OnMouseWheel", function(self, delta)
        if delta > 0 then
            self:ScrollUp(); self:ScrollUp(); self:ScrollUp()
        elseif _G.IsControlKeyDown and _G.IsControlKeyDown() then
            self:ScrollToBottom()
        else
            self:ScrollDown(); self:ScrollDown(); self:ScrollDown()
        end
    end)

    ApplySavedGeometry()
    Store.OnAppend(OnStoreAppend)
end

-- Clear + re-append the full store through `filterFn` (nil = everything).
-- This is how tab switching works losslessly.
function Display.Rebuild(filterFn)
    activeFilter = filterFn
    if not smf then return end
    smf:Clear()
    Store.ForEach(function(entry)
        if PassesFilter(entry) then
            RenderEntry(entry)
        end
    end)
    smf:ScrollToBottom()
end

-- Live-apply settings that can change without recreate.
function Display.Refresh()
    if not container then return end
    local cd = GetCustomDisplaySettings()
    if cd then
        if smf then smf:SetMaxLines(cd.maxLines or 1000) end
        Store.SetCap(cd.maxLines or 1000)
        if Helpers and Helpers.SetFrameBackdropColor then
            Helpers.SetFrameBackdropColor(container, 0, 0, 0, cd.bgAlpha or 0.25)
        end
        ApplySavedGeometry()
    end
end

-- CONTRACT: appends are skipped while hidden (OnStoreAppend gates on
-- IsShown), so callers showing a previously-hidden display must follow up
-- with Display.Rebuild(...) — display_fallback.Apply() does exactly that.
function Display.Show()
    if container then container:Show() end
end

function Display.Hide()
    if container then container:Hide() end
end

function Display.IsCreated()
    return container ~= nil
end
