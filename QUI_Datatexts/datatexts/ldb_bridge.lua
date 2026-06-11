--- QUI Datatexts — LibDataBroker host.
--- Registers every LDB dataobject as datatext "ldb:<name>" in the shared
--- registry, so any slot consumer (info bar, minimap panel, custom
--- datapanels) can display third-party plugins. Icons render inline via |T
--- escapes (no texture-region management; auto-width measures the text).

local ADDON_NAME, ns = ...
local QUICore = ns.Addon
local Datatexts = QUICore and QUICore.Datatexts
if not Datatexts then return end

local ldb = LibStub and LibStub("LibDataBroker-1.1", true)
if not ldb then return end

local format = string.format
local floor = math.floor

local LDB_PREFIX = "ldb:"
local bridge = {}            -- callback host
-- Hosts must tear down via Datatexts:DetachFromSlot (slot frames are reused,
-- never destroyed) or entries here would pin dead frames.
local liveSlots = {}         -- ldbName -> set of slotFrames displaying it
local warnedPlugins = {}     -- ldbName -> true once a callback error was printed

-- Display attributes that affect what RenderSlot draws; all other attribute
-- churn (chatty plugins reassign bookkeeping keys frequently) is ignored.
local DISPLAY_KEYS = {
    text = true, value = true, suffix = true, label = true,
    icon = true, iconCoords = true, iconR = true, iconG = true, iconB = true,
}

local function GetObj(name)
    return ldb:GetDataObjectByName(name)
end

-- Third-party plugin code runs inside these callbacks; contain failures so a
-- broken plugin can't break the slot host. Errors print once per session.
local function CallPlugin(name, fn, ...)
    local ok, err = pcall(fn, ...)
    if not ok and not warnedPlugins[name] then
        warnedPlugins[name] = true
        print("|cffff0000QUI:|r Plugin '" .. tostring(name) .. "' error: "
            .. tostring(err))
    end
end

local function IconString(obj, size)
    local icon = obj.icon
    if not icon then return nil end
    local c = obj.iconCoords
    if type(c) == "table" and #c >= 4 then
        return format("|T%s:%d:%d:0:0:64:64:%d:%d:%d:%d|t", icon, size, size,
            floor(c[1] * 64), floor(c[2] * 64),
            floor(c[3] * 64), floor(c[4] * 64))
    end
    return format("|T%s:%d:%d|t", icon, size, size)
end

local function RenderSlot(slot, name)
    local obj = GetObj(name)
    local text = slot.text
    if not obj or not text then return end

    local h = slot:GetHeight()
    local size = math.max(8, floor(h) - 6)
    local parts = {}

    -- slot.hideIcon: per-widget override set by the info-bar host (nil on
    -- hosts without the setting) — text/value still render.
    local iconStr = (not slot.hideIcon) and IconString(obj, size) or nil
    if iconStr then parts[#parts + 1] = iconStr end

    if obj.label and not slot.noLabel then
        parts[#parts + 1] = tostring(obj.label) .. ":"
    end

    local value = obj.text
    if value == nil and obj.value ~= nil then
        value = obj.suffix and (tostring(obj.value) .. " " .. obj.suffix)
            or tostring(obj.value)
    end
    if value ~= nil and value ~= "" then
        parts[#parts + 1] = tostring(value)
    end

    if #parts == 0 then parts[1] = name end
    text:SetText(table.concat(parts, " "))

    -- Hook installed by the info-bar host for auto-width reflow; nil on
    -- fixed-width hosts.
    if slot._quiOnWidthDirty then slot._quiOnWidthDirty() end
end

local function PositionTooltip(tooltip, slot)
    tooltip:SetOwner(slot, "ANCHOR_NONE")
    tooltip:ClearAllPoints()
    local _, cy = slot:GetCenter()
    local half = (UIParent:GetHeight() or 0) / 2
    if cy and cy > half then
        tooltip:SetPoint("TOP", slot, "BOTTOM", 0, -4)
    else
        tooltip:SetPoint("BOTTOM", slot, "TOP", 0, 4)
    end
end

local function SlotOnEnter(slot)
    local name = slot._quiLdbName
    local obj = GetObj(name)
    if not obj then return end
    if obj.OnEnter then
        CallPlugin(name, obj.OnEnter, slot)
        return
    end
    if obj.tooltip then
        PositionTooltip(obj.tooltip, slot)
        obj.tooltip:Show()
        return
    end
    if obj.OnTooltipShow then
        PositionTooltip(GameTooltip, slot)
        CallPlugin(name, obj.OnTooltipShow, GameTooltip)
        GameTooltip:Show()
    end
end

local function SlotOnLeave(slot)
    local obj = GetObj(slot._quiLdbName)
    if obj and obj.OnLeave then
        CallPlugin(slot._quiLdbName, obj.OnLeave, slot)
        return
    end
    if obj and obj.tooltip then obj.tooltip:Hide() end
    GameTooltip:Hide()
end

local function SlotOnClick(slot, button)
    local obj = GetObj(slot._quiLdbName)
    if not obj then return end
    -- A plugin-owned tooltip frame (obj.tooltip) is not GameTooltip, so the
    -- host's generic hide-on-click wrap misses it; drop it here so a menu the
    -- plugin opens from OnClick isn't rendered under its own tooltip.
    if obj.tooltip and obj.tooltip.Hide then
        obj.tooltip:Hide()
    end
    if obj.OnClick then
        CallPlugin(slot._quiLdbName, obj.OnClick, slot, button)
    end
end

-- Undocumented in the LDB 1.1 spec but long supported by classic display
-- addons; some plugins rely on it.
local function SlotOnDoubleClick(slot, button)
    local obj = GetObj(slot._quiLdbName)
    if obj and obj.OnDoubleClick then
        CallPlugin(slot._quiLdbName, obj.OnDoubleClick, slot, button)
    end
end

local function RegisterObject(name)
    local id = LDB_PREFIX .. name
    if Datatexts:Get(id) then return false end
    local obj = GetObj(name)
    if not obj then return false end

    Datatexts:Register(id, {
        displayName = name,
        category = "Plugins",
        description = (obj.type == "launcher") and "Plugin button"
            or "Plugin data feed",

        OnEnable = function(slotFrame, settings)
            local frame = CreateFrame("Frame", nil, slotFrame)
            frame:SetAllPoints()
            frame._ldbName = name
            -- Remember the owning slot on the instance frame so OnDisable
            -- can clean up exactly this slot (the same plugin may be live
            -- on several slot surfaces at once).
            frame._slot = slotFrame

            slotFrame._quiLdbName = name
            liveSlots[name] = liveSlots[name] or {}
            liveSlots[name][slotFrame] = true

            if slotFrame.RegisterForClicks then
                slotFrame:RegisterForClicks("AnyUp")
                slotFrame:SetScript("OnClick", SlotOnClick)
                -- Only when the plugin defines it: a registered OnDoubleClick
                -- handler makes the client reclassify the second rapid click
                -- as a double-click, which would no-op for plugins without one.
                if obj.OnDoubleClick then
                    slotFrame:SetScript("OnDoubleClick", SlotOnDoubleClick)
                end
            end
            slotFrame:SetScript("OnEnter", SlotOnEnter)
            slotFrame:SetScript("OnLeave", SlotOnLeave)

            RenderSlot(slotFrame, name)
            return frame
        end,

        OnDisable = function(frame)
            local ldbName = frame and frame._ldbName
            local slot = frame and frame._slot
            if slot then
                if slot.RegisterForClicks then
                    slot:SetScript("OnClick", nil)
                    slot:SetScript("OnDoubleClick", nil)
                end
                slot:SetScript("OnEnter", nil)
                slot:SetScript("OnLeave", nil)
                slot._quiLdbName = nil
            end
            local slots = ldbName and liveSlots[ldbName]
            if slots and slot then
                slots[slot] = nil
                if next(slots) == nil then
                    liveSlots[ldbName] = nil
                end
            end
        end,
    })
    return true
end

function bridge:OnObjectCreated(event, name)
    -- Late plugin load (post initial sweep): rebuild the slot hosts so a
    -- placed-but-empty ldb:* slot picks up the now-available datatext. The
    -- hosts self-defer in combat, so this is at most one cheap rebuild per
    -- late-loaded plugin.
    if RegisterObject(name) then
        if _G.QUI_RefreshInfoBar then _G.QUI_RefreshInfoBar() end
        if _G.QUI_RefreshDatapanels then _G.QUI_RefreshDatapanels() end
        if _G.QUI_RefreshMinimap then _G.QUI_RefreshMinimap() end
    end
end

function bridge:OnAttributeChanged(event, name, key, value, obj)
    if not DISPLAY_KEYS[key] then return end
    local slots = liveSlots[name]
    if slots then
        for slot in pairs(slots) do
            RenderSlot(slot, name)
        end
    end
end

ldb.RegisterCallback(bridge, "LibDataBroker_DataObjectCreated", "OnObjectCreated")
ldb.RegisterCallback(bridge, "LibDataBroker_AttributeChanged", "OnAttributeChanged")

for name in ldb:DataObjectIterator() do
    RegisterObject(name)
end
