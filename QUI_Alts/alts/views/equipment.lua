---------------------------------------------------------------------------
-- Alts equipment tab. Cross-character comparison grid: rows are equipment
-- slots, columns are characters (header row: class-colored names; footer
-- row: average item level). Cells render icon + per-slot item level with a
-- 1px quality-colored border. Data comes entirely from core storage
-- (rec.equipped.slots — itemID/link/quality/icon/ilvl, scan_equipped.lua);
-- entries scanned before ilvl existed fall back to a live
-- C_Item.GetDetailedItemLevelInfo(link) lookup (MayReturnNothing → blank).
-- Mouse wheel scrolls columns horizontally when characters overflow.
-- Hover: GameTooltip:SetHyperlink(link). Shift-click: link to chat.
--
-- Pure helpers exported on Alts.EquipmentView for headless tests:
--   BuildSlotRows(characters) → ordered { slot, label } list (optional
--     slots — shirt/tabard/ranged — elided when empty on every character)
--   BuildColumns(characters)  → { key, name } sorted by display name
-- Frame parts are NOT tested (no WoW frame API headless).
---------------------------------------------------------------------------
-- luacheck: read globals ColorManager ITEM_QUALITY_COLORS ChatEdit_InsertLink
local ADDON_NAME, ns = ...

local Shared = ns.AltsViewShared
local ClassColor = Shared.ClassColor
local GeneralFont = Shared.GeneralFont
local GeneralOutline = Shared.GeneralOutline
local MakeFS = Shared.MakeFS
local Alts = ns.Alts or {}; ns.Alts = Alts

local Helpers = ns.Helpers
local UIKit = ns.UIKit

local EquipmentView = {}
Alts.EquipmentView = EquipmentView

local ROW_H, HEADER_H = 24, 22
local CELL_PAD = 6
local SLOT_LABEL_W = 80  -- left column: slot names
local COL_W = 78         -- one character column
local ICON_SIZE = 18

-- Paper-doll display order (inv slots 1..19; constants vendored
-- Blizzard_FrameXMLBase/Constants.lua — scan_equipped.lua precedent).
-- optional = true rows are elided when empty across every character.
local SLOT_DEFS = {
    { slot = 1,  label = "Head" },
    { slot = 2,  label = "Neck" },
    { slot = 3,  label = "Shoulder" },
    { slot = 15, label = "Back" },
    { slot = 5,  label = "Chest" },
    { slot = 4,  label = "Shirt",  optional = true },
    { slot = 19, label = "Tabard", optional = true },
    { slot = 9,  label = "Wrist" },
    { slot = 10, label = "Hands" },
    { slot = 6,  label = "Waist" },
    { slot = 7,  label = "Legs" },
    { slot = 8,  label = "Feet" },
    { slot = 11, label = "Finger 1" },
    { slot = 12, label = "Finger 2" },
    { slot = 13, label = "Trinket 1" },
    { slot = 14, label = "Trinket 2" },
    { slot = 16, label = "Main Hand" },
    { slot = 17, label = "Off Hand" },
    { slot = 18, label = "Ranged", optional = true }, -- retail-dead relic slot
}

---------------------------------------------------------------------------
-- Pure helpers (tested headless).
---------------------------------------------------------------------------

--- Ordered { slot, label } rows. Optional slots (shirt/tabard/ranged) are
--- included only when at least one character has that slot filled.
function EquipmentView.BuildSlotRows(characters)
    local filled = {}
    for _, rec in pairs(characters or {}) do
        local slots = rec and rec.equipped and rec.equipped.slots
        if type(slots) == "table" then
            for slot, entry in pairs(slots) do
                if entry then filled[slot] = true end
            end
        end
    end
    local rows = {}
    for _, def in ipairs(SLOT_DEFS) do
        if not def.optional or filled[def.slot] then
            rows[#rows + 1] = { slot = def.slot, label = def.label }
        end
    end
    return rows
end

--- Sorted { key, name } character columns (name falls back to the key).
function EquipmentView.BuildColumns(characters)
    local cols = {}
    for key, rec in pairs(characters or {}) do
        cols[#cols + 1] = { key = key, name = (rec and rec.name) or key }
    end
    table.sort(cols, function(a, b)
        if a.name == b.name then return a.key < b.key end
        return a.name < b.name
    end)
    return cols
end

---------------------------------------------------------------------------
-- Frame parts (no headless test).
---------------------------------------------------------------------------





local function GetQualityColor(quality)
    -- 12.0 modern path: ColorManager wraps quality colors (incl. user
    -- accessibility overrides); ITEM_QUALITY_COLORS kept as fallback
    -- (bags item_buttons.lua precedent).
    local c
    if ColorManager and ColorManager.GetColorDataForItemQuality then
        c = ColorManager.GetColorDataForItemQuality(quality)
    end
    if not c then
        c = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality]
    end
    if c then return c.r, c.g, c.b end
    return 0.5, 0.5, 0.5
end

--- Per-slot item level: stored value first; pre-ilvl records resolve live
--- from the stored link (MayReturnNothing → nil → blank cell text).
local function EntryIlvl(entry)
    if entry.ilvl then return entry.ilvl end
    local itemInfo = entry.link or entry.itemID
    if itemInfo and C_Item and C_Item.GetDetailedItemLevelInfo then
        return C_Item.GetDetailedItemLevelInfo(itemInfo)
    end
    return nil
end

local function Builder(parent)
    local Store = ns.Storage and ns.Storage.Store
    local Bus   = ns.Storage and ns.Storage.Bus

    local frame = CreateFrame("Frame", nil, parent)

    local view      = { frame = frame }
    local colOffset = 0      -- first visible character column (0-based)
    local slotRows  = {}     -- BuildSlotRows result
    local columns   = {}     -- BuildColumns result
    local cachedChars = {}

    -- pools: cells[rowIndex][visibleColIndex]; header/footer fontstrings
    -- per visible column; slot labels per row
    local cellPool   = {}
    local headerPool = {}
    local footerPool = {}
    local labelPool  = {}

    local function VisibleCols()
        local w = (frame:GetWidth() or 0) - SLOT_LABEL_W
        if w < COL_W then return 1 end
        return math.max(1, math.floor(w / COL_W))
    end

    local function GetSlotLabel(i)
        local fs = labelPool[i]
        if fs then return fs end
        fs = MakeFS(frame, 11)
        fs:SetPoint("TOPLEFT", frame, "TOPLEFT", CELL_PAD,
            -(HEADER_H + 2) - (i - 1) * ROW_H - 6)
        fs:SetWidth(SLOT_LABEL_W - CELL_PAD)
        fs:SetJustifyH("LEFT")
        fs:SetTextColor(0.7, 0.7, 0.7)
        labelPool[i] = fs
        return fs
    end

    local function GetHeader(c)
        local fs = headerPool[c]
        if fs then return fs end
        fs = MakeFS(frame, 11)
        fs:SetWidth(COL_W - 4)
        fs:SetJustifyH("CENTER")
        headerPool[c] = fs
        return fs
    end

    local function GetFooter(c)
        local fs = footerPool[c]
        if fs then return fs end
        fs = MakeFS(frame, 11)
        fs:SetWidth(COL_W - 4)
        fs:SetJustifyH("CENTER")
        fs:SetTextColor(0.8, 0.8, 0.8)
        footerPool[c] = fs
        return fs
    end

    local function GetCell(i, c)
        cellPool[i] = cellPool[i] or {}
        local cell = cellPool[i][c]
        if cell then return cell end
        cell = CreateFrame("Button", nil, frame)
        cell:SetSize(COL_W - 4, ROW_H - 2)
        cell._icon = cell:CreateTexture(nil, "ARTWORK")
        cell._icon:SetSize(ICON_SIZE, ICON_SIZE)
        cell._icon:SetPoint("LEFT", cell, "LEFT", 4, 0)
        -- 1px quality border around the icon (UIKit border lines handle
        -- DisablePixelSnap internally — window.lua precedent)
        cell._iconFrame = CreateFrame("Frame", nil, cell)
        cell._iconFrame:SetPoint("TOPLEFT", cell._icon, "TOPLEFT", -1, 1)
        cell._iconFrame:SetPoint("BOTTOMRIGHT", cell._icon, "BOTTOMRIGHT", 1, -1)
        UIKit.CreateBorderLines(cell._iconFrame)
        cell._ilvl = MakeFS(cell, 11)
        cell._ilvl:SetPoint("LEFT", cell._icon, "RIGHT", 5, 0)
        cell._ilvl:SetPoint("RIGHT", cell, "RIGHT", -2, 0)
        cell._ilvl:SetJustifyH("LEFT")
        cell:SetScript("OnEnter", function(self)
            if not self._link then return end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetHyperlink(self._link)
            GameTooltip:Show()
        end)
        cell:SetScript("OnLeave", function() GameTooltip:Hide() end)
        cell:SetScript("OnClick", function(self)
            if self._link and IsShiftKeyDown() and ChatEdit_InsertLink then
                ChatEdit_InsertLink(self._link)
            end
        end)
        cellPool[i][c] = cell
        return cell
    end

    -- status line (bottom-left; footer chrome shared with other tabs)
    local status = MakeFS(frame, 11)
    status:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", CELL_PAD, 4)
    status:SetTextColor(0.8, 0.8, 0.8)

    local function RenderGrid()
        local visible = VisibleCols()
        local maxOff = math.max(0, #columns - visible)
        if colOffset > maxOff then colOffset = maxOff end
        if colOffset < 0 then colOffset = 0 end

        -- slot labels (left column)
        for i, rowDef in ipairs(slotRows) do
            local fs = GetSlotLabel(i)
            fs:SetText(rowDef.label)
            fs:Show()
        end
        for i = #slotRows + 1, #labelPool do labelPool[i]:Hide() end
        -- hide surplus pooled cell rows from a previously taller grid
        -- (e.g. an optional slot emptied), across every visible column
        for i = #slotRows + 1, #cellPool do
            local row = cellPool[i]
            if row then
                for _, cell in pairs(row) do cell:Hide() end
            end
        end

        local footY = -(HEADER_H + 2) - #slotRows * ROW_H

        for c = 1, visible do
            local col = columns[colOffset + c]
            local x = SLOT_LABEL_W + (c - 1) * COL_W
            local header = GetHeader(c)
            local footer = GetFooter(c)
            header:ClearAllPoints()
            header:SetPoint("TOPLEFT", frame, "TOPLEFT", x, -4)
            footer:ClearAllPoints()
            footer:SetPoint("TOPLEFT", frame, "TOPLEFT", x, footY - 4)

            if not col then
                header:Hide()
                footer:Hide()
                for i = 1, #slotRows do
                    if cellPool[i] and cellPool[i][c] then cellPool[i][c]:Hide() end
                end
            else
                local rec = cachedChars[col.key]
                header:SetText(col.name)
                header:SetTextColor(ClassColor(rec and rec.details and rec.details.class))
                header:Show()

                local avg = rec and rec.details and rec.details.ilvl
                footer:SetText(avg and string.format("%.0f", avg) or "—")
                footer:Show()

                local slots = rec and rec.equipped and rec.equipped.slots
                for i, rowDef in ipairs(slotRows) do
                    local cell = GetCell(i, c)
                    cell:ClearAllPoints()
                    cell:SetPoint("TOPLEFT", frame, "TOPLEFT", x,
                        -(HEADER_H + 2) - (i - 1) * ROW_H - 1)
                    local entry = slots and slots[rowDef.slot]
                    if entry then
                        cell._link = entry.link
                        cell._icon:SetTexture(entry.icon or 134400) -- question mark
                        cell._icon:Show()
                        local qr, qg, qb = GetQualityColor(entry.quality)
                        UIKit.UpdateBorderLines(cell._iconFrame, 1, qr, qg, qb, 0.8)
                        cell._iconFrame:Show()
                        local ilvl = EntryIlvl(entry)
                        cell._ilvl:SetText(ilvl and tostring(ilvl) or "")
                        cell._ilvl:SetTextColor(0.9, 0.9, 0.9)
                    else
                        cell._link = nil
                        cell._icon:Hide()
                        cell._iconFrame:Hide()
                        cell._ilvl:SetText("—")
                        cell._ilvl:SetTextColor(0.4, 0.4, 0.4)
                    end
                    cell:Show()
                end
            end
        end
        -- hide surplus pooled columns beyond `visible`
        for c = visible + 1, #headerPool do
            headerPool[c]:Hide()
            if footerPool[c] then footerPool[c]:Hide() end
            for i = 1, #slotRows do
                if cellPool[i] and cellPool[i][c] then cellPool[i][c]:Hide() end
            end
        end

        if #columns > visible then
            status:SetText(string.format("%d characters (scroll for more)", #columns))
        else
            status:SetText(string.format("%d characters", #columns))
        end
    end

    function view.Refresh()
        if not (Store and Store.IsInitialized and Store.IsInitialized()) then return end
        cachedChars = {}
        if Store.ListCharacters and Store.GetCharacter then
            for _, key in ipairs(Store.ListCharacters()) do
                local rec = Store.GetCharacter(key)
                if rec then cachedChars[key] = rec end
            end
        end
        slotRows = EquipmentView.BuildSlotRows(cachedChars)
        columns  = EquipmentView.BuildColumns(cachedChars)
        RenderGrid()
    end

    -- mouse-wheel: horizontal column scroll (vertical content always fits)
    frame:EnableMouseWheel(true)
    frame:SetScript("OnMouseWheel", function(_, delta)
        local maxOff = math.max(0, #columns - VisibleCols())
        colOffset = colOffset - delta
        if colOffset < 0 then colOffset = 0 end
        if colOffset > maxOff then colOffset = maxOff end
        RenderGrid()
    end)

    -- Bus subscriptions: refresh only when visible
    if Bus and Bus.Subscribe then
        local function OnBus()
            if frame:IsVisible() then view.Refresh() end
        end
        Bus.Subscribe("EquippedChanged", OnBus)
        Bus.Subscribe("CharacterDeleted", OnBus)
    end

    return view
end

Alts.Window.RegisterTab("equipment", "Equipment", Builder,
    "Currently equipped gear for every character, side by side — icons, item levels, and quality colors per slot.")
