-- tests/unit/skinbase_widgets_test.lua
-- Run: lua tests/unit/skinbase_widgets_test.lua
-- luacheck: globals CreateFrame C_Timer hooksecurefunc PanelTemplates_SetTab ScrollUtil

local hookedScripts = {}

local function NewTexture()
    local t = { alpha = 1 }
    function t:SetAlpha(a) self.alpha = a end
    function t:SetTexture(f) self.file = f end
    function t:SetColorTexture(r, g, b, a) self.colorTexture = { r, g, b, a } end
    function t:SetVertexColor(r, g, b, a) self.color = { r, g, b, a } end
    function t:ClearAllPoints() self.points = {} end
    function t:SetPoint(...) self.points = self.points or {}; self.points[#self.points + 1] = { ... } end
    function t:SetHeight(h) self.height = h end
    function t:SetWidth(w) self.width = w end
    function t:Show() self.visible = true end
    function t:Hide() self.visible = false end
    function t:IsShown() return self.visible end
    function t:IsObjectType(objType) return objType == "Texture" end
    return t
end

local function NewFrame(parent)
    local f = { parent = parent, textures = {}, points = {}, frameLevel = 4, scripts = {} }
    function f:CreateTexture() local t = NewTexture(); self.textures[#self.textures + 1] = t; return t end
    function f:CreateFontString() return NewTexture() end
    function f:SetAllPoints() self.allPoints = true end
    function f:SetFrameLevel(l) self.frameLevel = l end
    function f:GetFrameLevel() return self.frameLevel end
    function f:EnableMouse(e) self.mouseEnabled = e end
    function f:ClearAllPoints() self.points = {} end
    function f:SetPoint(...) self.points[#self.points + 1] = { ... } end
    function f:SetWidth(w) self.width = w end
    function f:Show() self.shown = true end
    function f:Hide() self.shown = false end
    function f:GetRegions() return unpack(self.textures) end
    function f:GetNumRegions() return #self.textures end
    function f:GetHighlightTexture() self.highlight = self.highlight or NewTexture(); return self.highlight end
    function f:GetPushedTexture() self.pushed = self.pushed or NewTexture(); return self.pushed end
    function f:GetNormalTexture() self.normal = self.normal or NewTexture(); return self.normal end
    function f:HookScript(event, fn) self.scripts[event] = fn; hookedScripts[#hookedScripts + 1] = { f = self, event = event, fn = fn } end
    return f
end

function CreateFrame(_, _, parent) return NewFrame(parent) end
C_Timer = { After = function(_, fn) fn() end }
function hooksecurefunc(...) end
function PanelTemplates_SetTab() end

local skinColors = { 0.6, 0.7, 0.8, 1, 0.1, 0.2, 0.3, 0.9 }

local ns = {
    Helpers = {
        CHROME = { BORDER_PX = 1, BG_FALLBACK = { 0.05, 0.05, 0.05, 0.95 }, BORDER_FALLBACK = { 0, 0, 0, 1 }, BUTTON_BOOST = 0.07, SCROLLROW_BOOST = 0.03, DEPTH = { PANEL = { boost = 0, alpha = 0.95 }, SUBPANEL = { boost = 0.04, alpha = 0.85 }, ROW = { boost = 0.07, alpha = 0.75 } } },
        CreateStateTable = function()
            local tbl = setmetatable({}, { __mode = "k" })
            local function get(key)
                local s = tbl[key]
                if not s then s = {}; tbl[key] = s end
                return s
            end
            return tbl, get
        end,
        GetCore = function() return { GetPixelSize = function() return 0.5 end } end,
        SafeToNumber = function(v, d) return tonumber(v) or d end,
        GetSkinBorderColor = function() return skinColors[1], skinColors[2], skinColors[3], skinColors[4] end,
        GetSkinBgColorWithOverride = function() return skinColors[5], skinColors[6], skinColors[7], skinColors[8] end,
        GetSkinBarColor = function() return 0.5, 0.5, 0.5, 1 end,
    },
    UIKit = { RegisterScaleRefresh = function() end },
}

assert(loadfile("modules/skinning/base.lua"))("QUI", ns)
local SkinBase = ns.SkinBase

-- SkinButton: backdrop with button boost, hides named + state textures, tags kind, idempotent
local button = NewFrame()
button.Left, button.Right, button.Middle, button.Center = NewTexture(), NewTexture(), NewTexture(), NewTexture()
SkinBase.SkinButton(button)
assert(SkinBase.GetBackdrop(button), "SkinButton must create a backdrop")
assert(button.Left.alpha == 0, "SkinButton must hide named Left texture")
assert(button:GetNormalTexture().alpha == 0, "SkinButton must hide normal texture")
assert(SkinBase.GetFrameData(button, "skinKind") == "button", "SkinButton must tag skinKind")
assert(SkinBase.IsStyled(button), "SkinButton must mark styled")
local bd = SkinBase.GetBackdrop(button)
assert(math.abs(bd._quiBgR - (0.1 + 0.07)) < 1e-9, "SkinButton must apply the button bg boost")

-- SkinButton{strip=true} strips textures instead of hiding named regions
local stripBtn = NewFrame()
stripBtn.textures = { NewTexture() }
SkinBase.SkinButton(stripBtn, { strip = true })
assert(stripBtn.textures[1].alpha == 0, "SkinButton{strip=true} must StripTextures")

-- SkinEditBox
local edit = NewFrame()
edit.textures = { NewTexture() }
SkinBase.SkinEditBox(edit)
assert(SkinBase.GetFrameData(edit, "skinKind") == "editbox", "SkinEditBox must tag editbox kind")
assert(edit.textures[1].alpha == 0, "SkinEditBox must strip textures")

-- SkinScrollRow: row boost + alpha-multiplied border
local row = NewFrame()
row.textures = { NewTexture() }
SkinBase.SkinScrollRow(row)
assert(SkinBase.GetFrameData(row, "skinKind") == "row", "SkinScrollRow must tag row kind")
local rowSc = SkinBase.GetFrameData(row, "skinColor")
assert(math.abs(rowSc[4] - (1 * 0.5)) < 1e-9, "SkinScrollRow must halve the border alpha")

-- SkinDropdown options
local ddArrow = NewFrame()
ddArrow.Arrow = NewTexture()
ddArrow.NormalTexture = NewTexture()
SkinBase.SkinDropdown(ddArrow, { keepArrow = true, insetY = 2 })
assert(ddArrow.Arrow.alpha == 1, "SkinDropdown{keepArrow} must NOT hide the Arrow")
assert(ddArrow.NormalTexture.alpha == 0, "SkinDropdown{keepArrow} must hide NormalTexture")
assert(SkinBase.GetFrameData(ddArrow, "skinKind") == "dropdown", "SkinDropdown must tag dropdown kind")

local ddFilter = NewFrame()
ddFilter.textures = { NewTexture() }
SkinBase.SkinDropdown(ddFilter, { noStrip = true, belowChildren = true })
assert(ddFilter.textures[1].alpha == 1, "SkinDropdown{noStrip} must NOT strip child textures")
local ddBd = SkinBase.GetBackdrop(ddFilter)
assert(ddBd:GetFrameLevel() == math.max(0, ddFilter:GetFrameLevel() - 1),
    "SkinDropdown{belowChildren} must drop the backdrop frame level below the dropdown")

-- SkinListContainer hides NineSlice + ScrollBar.Background and styles rows via the scroll hook
local styledRows = {}
local list = NewFrame()
list.NineSlice = NewFrame()
list.ScrollBar = NewFrame(); list.ScrollBar.Background = NewTexture()
list.ScrollBox = NewFrame()
function list.ScrollBox:ForEachFrame(cb) cb(NewFrame()) end
-- Provide ScrollUtil so HookScrollBoxAcquired runs
ScrollUtil = { AddAcquiredFrameCallback = function() end }
SkinBase.SkinListContainer(list, function(r) styledRows[#styledRows + 1] = r end)
assert(list.NineSlice.shown == nil or list.NineSlice.shown == false, "SkinListContainer must hide NineSlice")
assert(list.ScrollBar.Background.visible == false, "SkinListContainer must hide ScrollBar.Background")
assert(#styledRows == 1, "SkinListContainer must style pooled rows via the scroll hook")

-- SkinListContainer is idempotent (second call is a no-op)
SkinBase.SkinListContainer(list, function(r) styledRows[#styledRows + 1] = r end)
assert(#styledRows == 1, "SkinListContainer must be idempotent (no re-styling on repeat call)")

-- RefreshWidget recolors by kind and updates stored skinColor
skinColors = { 0.9, 0.8, 0.7, 1, 0.4, 0.5, 0.6, 0.95 }

-- button branch
SkinBase.RefreshWidget(button)
local newSc = SkinBase.GetFrameData(button, "skinColor")
assert(newSc[1] == 0.9, "RefreshWidget must update stored skinColor for later hovers")
local rbd = SkinBase.GetBackdrop(button)
assert(math.abs(rbd._quiBorderR - 0.9) < 1e-9, "RefreshWidget must recolor the button border")
assert(math.abs(rbd._quiBgR - (0.4 + 0.07)) < 1e-9, "RefreshWidget must recolor the button bg with boost")

-- editbox branch (uses full background alpha, no boost)
SkinBase.RefreshWidget(edit)
local ebd = SkinBase.GetBackdrop(edit)
assert(math.abs(ebd._quiBgR - 0.4) < 1e-9, "RefreshWidget editbox must recolor bg with no boost")
assert(math.abs(ebd._quiBgA - 0.95) < 1e-9, "RefreshWidget editbox must apply the background alpha (bga)")
assert(math.abs(ebd._quiBorderR - 0.9) < 1e-9, "RefreshWidget editbox must recolor the border")

-- row branch (row boost, halved border alpha, fixed bg alpha)
SkinBase.RefreshWidget(row)
local rowBd = SkinBase.GetBackdrop(row)
assert(math.abs(rowBd._quiBgR - (0.4 + 0.03)) < 1e-9, "RefreshWidget row must recolor bg with row boost")
assert(math.abs(rowBd._quiBgA - 0.6) < 1e-9, "RefreshWidget row must keep the row bg alpha")
assert(math.abs(rowBd._quiBorderA - (1 * 0.5)) < 1e-9, "RefreshWidget row must keep the halved border alpha")
local rowSc2 = SkinBase.GetFrameData(row, "skinColor")
assert(math.abs(rowSc2[4] - 0.5) < 1e-9, "RefreshWidget row must re-store the halved-alpha skinColor")

-- dropdown branch (button boost, stored bgColor)
SkinBase.RefreshWidget(ddArrow)
local ddBd2 = SkinBase.GetBackdrop(ddArrow)
assert(math.abs(ddBd2._quiBgR - (0.4 + 0.07)) < 1e-9, "RefreshWidget dropdown must recolor bg with button boost")
assert(math.abs(ddBd2._quiBorderR - 0.9) < 1e-9, "RefreshWidget dropdown must recolor the border")


-- Tab selection detection: TabSystem GetSelectedTab vs tab.tabID
local tabA = NewFrame()
local tabB = NewFrame()
tabA.tabID, tabB.tabID = 1, 2
local owner = NewFrame()
owner.TabSystem = NewFrame()
owner.TabSystem.tabs = { tabA, tabB }
function owner.TabSystem:GetSelectedTab() return 1 end
function owner.TabSystem:SetTab() end

SkinBase.SkinTabGroup({ tabA, tabB }, owner, { hover = true })
assert(SkinBase.IsStyled(tabA), "SkinTabGroup must skin each tab")
assert(SkinBase.GetFrameData(tabA, "qTabHoverHooked"), "hover tabs must be hover-hooked")

-- Selected tab (tabID 1) gets full border alpha; unselected gets dimmed border
local bdA = SkinBase.GetBackdrop(tabA)
local bdB = SkinBase.GetBackdrop(tabB)
assert(bdA._quiBorderA == 1, "selected tab must use full border alpha")
assert(math.abs(bdB._quiBorderA - (1 * 0.6)) < 1e-9, "unselected tab must use dimmed border alpha")

-- Hover actually runs: enter brightens the border, leave restores the
-- dimmed unselected state (tabB stored skinColor = {0.9,0.8,0.7,1}).
tabB.scripts.OnEnter(tabB)
assert(math.abs(bdB._quiBorderB - math.min(0.7 * 1.3, 1)) < 1e-9, "tab hover enter must brighten the border")
tabB.scripts.OnLeave(tabB)
assert(math.abs(bdB._quiBorderA - (1 * 0.6)) < 1e-9, "tab hover leave must restore the dimmed unselected border")

-- RefreshTabGroup re-stores colors and re-applies selected state
skinColors = { 0.2, 0.3, 0.4, 1, 0.05, 0.06, 0.07, 0.9 }
SkinBase.RefreshTabGroup({ tabA, tabB }, owner)
local scA = SkinBase.GetFrameData(tabA, "skinColor")
assert(scA[1] == 0.2, "RefreshTabGroup must re-store tab skinColor")
assert(SkinBase.GetBackdrop(tabA)._quiBorderR == 0.2, "RefreshTabGroup must recolor selected tab border")

-- SkinTab (single tab, pooled-tab use) skins + hover-hooks
local poolTab = NewFrame()
poolTab.tabID = 1
SkinBase.SkinTab(poolTab, owner, { hover = true })
assert(SkinBase.IsStyled(poolTab), "SkinTab must skin the tab")
assert(SkinBase.GetFrameData(poolTab, "qTabHoverHooked"), "SkinTab{hover} must hover-hook")

print("OK: skinbase_widgets_test")
