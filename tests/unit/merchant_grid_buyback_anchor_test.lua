-- tests/unit/merchant_grid_buyback_anchor_test.lua
-- Run: lua tests/unit/merchant_grid_buyback_anchor_test.lua
--
-- Regression: the merchant grid extender re-anchors item buttons into a grid,
-- but MerchantBuyBackItem is XML-anchored to MerchantItem10 and Blizzard never
-- re-anchors it in Lua. At >2 cols / >5 rows item10 moves into the grid
-- interior, dragging the buyback quick-slot on top of the item buttons.
-- ApplyGrid must re-pin the buyback slot to the bottom-left-role slot
-- ((rows-1)*cols + 2), and RestoreVanilla must put it back on item10.
--
-- Extracts BuybackRefIndex/ApplyGrid/RestoreVanilla from merchant_grid.lua
-- between its QUI_TEST_EXTRACT sentinels and drives them against mock widgets.

local loadstring = loadstring or load

local function readAll(path)
    local f = assert(io.open(path, "rb"))
    local d = f:read("*a"); f:close()
    return d:gsub("\r\n", "\n")
end

local source = readAll("modules/qol/merchant_grid.lua")
local S = "-- <<< QUI_TEST_EXTRACT buyback_anchor"
local a1 = assert(source:find(S, 1, true), "start sentinel must exist")
local a2 = assert(source:find(S, a1 + #S, true), "end sentinel must exist")
local block = source:sub(a1 + #S, a2 - 1)

-- Mock widget: records ClearAllPoints/SetPoint so tests can inspect anchoring.
local function newWidget(name)
    local w = { name = name, points = {}, shown = nil, size = nil }
    function w:ClearAllPoints() self.points = {} end
    function w:SetPoint(point, rel, relPoint, x, y)
        table.insert(self.points, { point = point, rel = rel, relPoint = relPoint, x = x, y = y })
    end
    function w:Show() self.shown = true end
    function w:Hide() self.shown = false end
    function w:SetSize(cw, ch) self.size = { cw, ch } end
    function w:lastPoint() return self.points[#self.points] end
    return w
end

-- Build a mock _G exposing MerchantFrame, MerchantItem1..32, next-page button
-- and the buyback slot. MAX_BUTTONS in source is 32.
local function newG()
    local g = {}
    g.MerchantFrame = newWidget("MerchantFrame")
    for i = 1, 32 do g["MerchantItem" .. i] = newWidget("MerchantItem" .. i) end
    g.MerchantNextPageButton = newWidget("MerchantNextPageButton")
    g.MerchantBuyBackItem = newWidget("MerchantBuyBackItem")
    return g
end

-- Prelude: everything the extracted block references besides _G and math.
local prelude = [[
local _G = ...
local BASE_W, BASE_H         = 336, 444
local ORIGIN_X, ORIGIN_Y     = 11, -69
local COL_STRIDE, ROW_STRIDE = 165, 52
local MAX_BUTTONS            = 32
local MIN_COLS, MIN_ROWS     = 2, 5
local NEXT_PAGE_INSET        = 26
local XML_BUTTONS            = 12
local BUYBACK_ANCHOR_X       = 30
local BUYBACK_ANCHOR_Y       = -53
local VANILLA_RELANCHORS = {
    { 2,  "MerchantItem1",  "TOPRIGHT",   12,   0 },
    { 4,  "MerchantItem3",  "TOPRIGHT",   12,   0 },
    { 6,  "MerchantItem5",  "TOPRIGHT",   12,   0 },
    { 8,  "MerchantItem7",  "TOPRIGHT",   12,   0 },
    { 10, "MerchantItem9",  "TOPRIGHT",   12,   0 },
    { 11, "MerchantItem9",  "BOTTOMLEFT",  0, -15 },
    { 12, "MerchantItem11", "TOPRIGHT",   12,   0 },
}
local function SafePanelUpdate() end
]]

local chunk = table.concat({
    prelude,
    block,
    "return { BuybackRefIndex = BuybackRefIndex, ApplyGrid = ApplyGrid, RestoreVanilla = RestoreVanilla }",
}, "\n")

-- The extracted block binds _G once at load, so build a fresh module + _G per
-- scenario rather than swapping the global underneath a live closure.
local function build()
    local g = newG()
    local m = assert(loadstring(chunk, "merchant_grid_buyback"))(g)
    return m, g
end

local M = build()   -- pure-math helpers (BuybackRefIndex) need no per-run _G state

local failures = 0
local function check(name, cond, detail)
    if cond then
        print("ok   - " .. name)
    else
        failures = failures + 1
        print("FAIL - " .. name .. (detail and ("  (" .. detail .. ")") or ""))
    end
end

-- 1. BuybackRefIndex math: 10 at 2x5 (pixel-vanilla), tracks grid otherwise.
check("refindex 2x5 == 10 (vanilla)", M.BuybackRefIndex(2, 5) == 10)
check("refindex 4x8 == 30", M.BuybackRefIndex(4, 8) == 30)
check("refindex 3x5 == 14", M.BuybackRefIndex(3, 5) == 14)
check("refindex 2x8 == 16", M.BuybackRefIndex(2, 8) == 16)

-- ref item is always column 1 and within the button pool -> constant x, real slot.
for _, c in ipairs({ { 2, 5 }, { 3, 5 }, { 4, 8 }, { 2, 8 } }) do
    local cols, rows = c[1], c[2]
    local ref = M.BuybackRefIndex(cols, rows)
    check(("ref %dx%d in [1,%d]"):format(cols, rows, cols * rows), ref >= 1 and ref <= cols * rows)
    check(("ref %dx%d is column 1"):format(cols, rows), (ref - 1) % cols == 1)
end

-- 2. ApplyGrid(4,8): buyback pinned to item30 (bottom row, col1), NOT item10.
local M48, G = build()
M48.ApplyGrid(4, 8)
local bp = G.MerchantBuyBackItem:lastPoint()
check("4x8 buyback has an anchor", bp ~= nil)
check("4x8 buyback -> MerchantItem30", bp and bp.rel == G.MerchantItem30,
    bp and bp.rel and bp.rel.name)
check("4x8 buyback NOT -> item10 (the bug)", bp and bp.rel ~= G.MerchantItem10)
check("4x8 buyback point/offset TOPLEFT<-BOTTOMLEFT 30,-53",
    bp and bp.point == "TOPLEFT" and bp.relPoint == "BOTTOMLEFT" and bp.x == 30 and bp.y == -53)
-- the ref slot itself must be on the bottom row (y == ORIGIN_Y-(rows-1)*ROW_STRIDE = -69-364)
local refPt = G.MerchantItem30:lastPoint()
check("4x8 item30 on bottom row (y=-433)", refPt and refPt.y == -69 - 7 * 52, refPt and tostring(refPt.y))
check("4x8 item30 in column 1 (x=176)", refPt and refPt.x == 11 + 165, refPt and tostring(refPt.x))

-- 3. ApplyGrid(2,5): pixel-vanilla -> buyback on item10.
local M25, G25 = build()
M25.ApplyGrid(2, 5)
local bp25 = G25.MerchantBuyBackItem:lastPoint()
check("2x5 buyback -> MerchantItem10 (pixel-vanilla)", bp25 and bp25.rel == G25.MerchantItem10)
check("2x5 buyback offset 30,-53", bp25 and bp25.x == 30 and bp25.y == -53)

-- 4. RestoreVanilla: buyback back on item10.
local Mr, Gr = build()
Mr.ApplyGrid(4, 8)              -- displace first
Mr.RestoreVanilla()
local bpr = Gr.MerchantBuyBackItem:lastPoint()
check("restore buyback -> MerchantItem10", bpr and bpr.rel == Gr.MerchantItem10)
check("restore buyback TOPLEFT<-BOTTOMLEFT 30,-53",
    bpr and bpr.point == "TOPLEFT" and bpr.relPoint == "BOTTOMLEFT" and bpr.x == 30 and bpr.y == -53)

if failures > 0 then
    print(("\n%d assertion(s) FAILED"):format(failures))
    os.exit(1)
end
print("\nall merchant_grid buyback-anchor assertions passed")
