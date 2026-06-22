-- tests/unit/character_tab_selection_persist_test.lua
-- Run: lua tests/unit/character_tab_selection_persist_test.lua
--
-- Regression guard for the "character-frame tab selection highlight reverts on
-- a scale refresh" bug.
--
-- The bottom tabs (Character/Reputation/Currency) get a SkinBase.CreateBackdrop
-- frame whose base colors are stored in SkinBase's pixelBackdropData. The
-- selected-vs-unselected tint (brightened bg for the active tab, dimmed for the
-- rest) is painted by the canonical SkinBase.RefreshTabSelected through
-- SkinBase.ApplyPixelBackdrop (same geometry CreateBackdrop used), so the
-- selection colors become the STORED data and survive a scale-refresh rebuild --
-- unlike a bare bd:SetBackdrop*Color, which updates only the live color that
-- SkinBase.RefreshPixelBackdrop discards on its next rebuild.
--
-- Since CharacterFrame's tabs migrated off their private fork onto the shared
-- SkinBase.SkinTabGroup, this also guards that the canonical verb persists the
-- selection tint. Drives the real _G.QUI_CharacterFrameSkinning.Refresh path
-- through the real SkinBase backdrop system and the real UIKit scale refresh.

-- luacheck: globals CreateFrame C_Timer hooksecurefunc InCombatLockdown
-- luacheck: globals CharacterFrame CharacterFrameTab1 CharacterFrameTab2 CharacterFrameTab3
-- luacheck: globals PanelTemplates_GetSelectedTab PanelTemplates_SetTab

local function approx(a, b) return a and math.abs(a - b) < 1e-4 end

-- A frame whose backdrop API mirrors WoW + supports SkinBase's manual texture
-- path (CreateTexture). Mirrors the proven shape from mplus_timer_backdrop_persist.
local function NewTexture()
    local t = {}
    function t:ClearAllPoints() end function t:SetPoint() end
    function t:SetHeight() end function t:SetWidth() end
    function t:Show() end function t:Hide() end
    function t:SetTexture() end
    function t:SetColorTexture(r, g, b, a) self.color = { r, g, b, a } end
    function t:SetVertexColor(r, g, b, a) self.color = { r, g, b, a } end
    return t
end

local function NewFrame()
    local f = { frameLevel = 4, id = 0 }
    function f:GetFrameLevel() return self.frameLevel end
    function f:SetFrameLevel(l) self.frameLevel = l end
    function f:SetFrameStrata() end
    function f:GetID() return self.id end
    function f:SetAllPoints() end
    function f:ClearAllPoints() end
    function f:SetPoint() end
    function f:EnableMouse() end
    function f:GetEffectiveScale() return 1 end
    function f:Show() end function f:Hide() end
    function f:IsShown() return false end
    function f:GetWidth() return 100 end
    function f:GetHeight() return 100 end
    function f:RegisterEvent() end function f:UnregisterEvent() end
    function f:SetScript() end function f:GetScript() end function f:HookScript() end
    function f:CreateTexture() return NewTexture() end
    function f:SetBackdrop(info) self.backdrop = info end
    function f:GetBackdrop() return self.backdrop end
    function f:SetBackdropColor(r, g, b, a) self._quiBgR, self._quiBgG, self._quiBgB, self._quiBgA = r, g, b, a or 1 end
    function f:SetBackdropBorderColor(r, g, b, a) self._quiBorderR, self._quiBorderG, self._quiBorderB, self._quiBorderA = r, g, b, a or 1 end
    return f
end

local function CreateStateTable()
    local tbl = setmetatable({}, { __mode = "k" })
    local function get(key)
        local s = tbl[key]
        if not s then s = {}; tbl[key] = s end
        return s
    end
    return tbl, get
end

-- Base theme colors GetSkinColors() returns: sr,sg,sb,sa, bgr,bgg,bgb,bga.
local BASE = { 0.10, 0.20, 0.30, 1, 0.40, 0.50, 0.60, 0.90 }

local ns = {
    Addon = { GetPixelSize = function() return 0.5 end },
    Helpers = {
        CHROME = { BORDER_PX = 1, BG_FALLBACK = { 0.05, 0.05, 0.05, 0.95 }, BORDER_FALLBACK = { 0, 0, 0, 1 }, BUTTON_BOOST = 0.07, SCROLLROW_BOOST = 0.03, DEPTH = { PANEL = { boost = 0, alpha = 0.95 }, SUBPANEL = { boost = 0.04, alpha = 0.85 }, ROW = { boost = 0.07, alpha = 0.75 } } },
        CreateStateTable = CreateStateTable,
        GetCore = function()
            return { db = { profile = {
                general = { skinCharacterFrame = true },
                character = { enabled = false },
            } } }
        end,
        CreateSkinColorGetter = function()
            return function()
                return BASE[1], BASE[2], BASE[3], BASE[4], BASE[5], BASE[6], BASE[7], BASE[8]
            end
        end,
        GetGeneralFont = function() return "Interface\\QUIFont.ttf" end,
        SafeToNumber = function(v, d) return tonumber(v) or d end,
        SetFrameBackdropColor = function(frame, r, g, b, a)
            frame:SetBackdropColor(r, g, b, a)
            frame._quiBgR, frame._quiBgG, frame._quiBgB, frame._quiBgA = r, g, b, a
        end,
        SetFrameBackdropBorderColor = function(frame, r, g, b, a)
            frame:SetBackdropBorderColor(r, g, b, a)
            frame._quiBorderR, frame._quiBorderG, frame._quiBorderB, frame._quiBorderA = r, g, b, a
        end,
    },
}

CreateFrame = function() return NewFrame() end
C_Timer = { After = function() end }
hooksecurefunc = function() end
function InCombatLockdown() return false end

-- Load the real UIKit/SkinBase, then the real character skinning module.
assert(loadfile("core/uikit.lua"))("QUI", ns)
local SkinBase = ns.SkinBase
assert(type(SkinBase) == "table", "SkinBase must load from uikit.lua")
assert(loadfile("QUI_Skinning/skinning/frames/character.lua"))("QUI", ns)

local API = _G.QUI_CharacterFrameSkinning
assert(type(API) == "table" and type(API.Refresh) == "function",
    "character.lua must expose _G.QUI_CharacterFrameSkinning.Refresh")

-- Build three tabs; tab 1 is the active one.
CharacterFrame = NewFrame()
CharacterFrame.selectedTab = 1
local tabs = {}
for i = 1, 3 do
    local tab = NewFrame()
    tab.id = i
    tabs[i] = tab
    _G["CharacterFrameTab" .. i] = tab
    -- Simulate the post-first-skin state: SkinBase.SkinTab early-returns on an
    -- already-styled tab, so pre-establish the backdrop + the skinColor/bgColor/
    -- skinTabFont frame data exactly as SkinTabButton sets them on first skin.
    -- SkinTabGroup's refreshAll() then drives the canonical RefreshTabSelected.
    SkinBase.CreateBackdrop(tab, BASE[1], BASE[2], BASE[3], BASE[4], BASE[5], BASE[6], BASE[7], 0.9)
    SkinBase.SetFrameData(tab, "skinColor", { BASE[1], BASE[2], BASE[3], BASE[4] })
    SkinBase.SetFrameData(tab, "bgColor", { BASE[5], BASE[6], BASE[7] })
    SkinBase.SetFrameData(tab, "skinTabFont", true)
    SkinBase.MarkStyled(tab)
end

-- Drive the real refresh path: SkinCharacterFrameTabs -> SkinBase.SkinTabGroup ->
-- refreshAll() -> RefreshTabSelected (canonical selected/unselected tint, persisted
-- via ApplyPixelBackdrop). CharacterFrame.selectedTab=1 resolves selection through
-- IsTabSelected's owner.selectedTab fallback.
API.Refresh()

local bd1 = SkinBase.GetBackdrop(tabs[1])
local bd2 = SkinBase.GetBackdrop(tabs[2])
assert(bd1 and bd2, "tabs must have SkinBase backdrops")

-- Selected tab bg is brightened (base + 0.10); unselected stays at base bg.
local SEL_BG = { math.min(BASE[5] + 0.10, 1), math.min(BASE[6] + 0.10, 1), math.min(BASE[7] + 0.10, 1) }

assert(approx(bd1._quiBgR, SEL_BG[1]) and approx(bd1._quiBgG, SEL_BG[2]) and approx(bd1._quiBgB, SEL_BG[3]),
    "precondition: selected tab bg is brightened right after refresh")
assert(approx(bd2._quiBgR, BASE[5]) and approx(bd2._quiBgG, BASE[6]),
    "precondition: unselected tab bg is the base color right after refresh")

-- A scale refresh (e.g. UI scale change with the frame open) rebuilds the tab
-- backdrops. The selection tint must SURVIVE, not revert to the base color.
ns.UIKit.RefreshScaleBoundWidgets()

assert(approx(bd1._quiBgR, SEL_BG[1]) and approx(bd1._quiBgG, SEL_BG[2]) and approx(bd1._quiBgB, SEL_BG[3]),
    "FIX: selected tab's brightened bg must survive the scale refresh, not revert to base")
assert(approx(bd1._quiBorderR, BASE[1]) and approx(bd1._quiBorderG, BASE[2]) and approx(bd1._quiBorderB, BASE[3]),
    "FIX: selected tab's full-strength border must survive the scale refresh")
-- Unselected tab keeps its dimmed border (sc * 0.5) through the refresh too.
assert(approx(bd2._quiBorderR, BASE[1] * 0.5) and approx(bd2._quiBorderG, BASE[2] * 0.5),
    "FIX: unselected tab's dimmed border must survive the scale refresh")

print("OK: character_tab_selection_persist_test")
