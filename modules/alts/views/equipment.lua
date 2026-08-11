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

local ROW_H, HEADER_H = 22, 22
local BOTTOM_BAND = 34
local CELL_PAD = 6
local SLOT_LABEL_W = 80
local COL_W = 78
local ICON_SIZE = 18

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
    { slot = 18, label = "Ranged", optional = true },
}

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

local function GetQualityColor(quality)
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
    local colOffset = 0
    local scrollbar
    local slotRows  = {}
    local columns   = {}
    local cachedChars = {}

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

    local status = MakeFS(frame, 11)
    status:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", CELL_PAD, 4)
    status:SetTextColor(0.8, 0.8, 0.8)

    local function RenderGrid()
        local visible = VisibleCols()
        local maxOff = math.max(0, #columns - visible)
        if colOffset > maxOff then colOffset = maxOff end
        if colOffset < 0 then colOffset = 0 end

        for i, rowDef in ipairs(slotRows) do
            local fs = GetSlotLabel(i)
            fs:SetText(rowDef.label)
            fs:Show()
        end
        for i = #slotRows + 1, #labelPool do labelPool[i]:Hide() end
        for i = #slotRows + 1, #cellPool do
            local row = cellPool[i]
            if row then
                for _, cell in pairs(row) do cell:Hide() end
            end
        end

        local bodyH = frame:GetHeight() or 0
        local footY = -(HEADER_H + 2) - #slotRows * ROW_H
        local minFootY = BOTTOM_BAND - bodyH
        if footY < minFootY then footY = minFootY end

        for c = 1, visible do
            local col = columns[colOffset + c]
            local x = SLOT_LABEL_W + (c - 1) * COL_W
            local header = GetHeader(c)
            local footer = GetFooter(c)
            header:ClearAllPoints()
            header:SetPoint("TOPLEFT", frame, "TOPLEFT", x, -4)
            footer:ClearAllPoints()
            footer:SetPoint("TOPLEFT", frame, "TOPLEFT", x, footY)

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
                        cell._icon:SetTexture(entry.icon or 134400)
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
        for c = visible + 1, #headerPool do
            headerPool[c]:Hide()
            if footerPool[c] then footerPool[c]:Hide() end
            for i = 1, #slotRows do
                if cellPool[i] and cellPool[i][c] then cellPool[i][c]:Hide() end
            end
        end

        status:SetText(string.format("%d characters", #columns))
        if scrollbar then scrollbar:Update(#columns, visible, colOffset) end
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

    scrollbar = Shared.CreateScrollBar(frame, {
        orientation = "horizontal",
        onScroll = function(n) colOffset = n; RenderGrid() end,
    })
    scrollbar.track:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", SLOT_LABEL_W, 4)
    scrollbar.track:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -2, 4)

    frame:EnableMouseWheel(true)
    frame:SetScript("OnMouseWheel", function(_, delta)
        local maxOff = math.max(0, #columns - VisibleCols())
        colOffset = colOffset - delta
        if colOffset < 0 then colOffset = 0 end
        if colOffset > maxOff then colOffset = maxOff end
        RenderGrid()
    end)

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
