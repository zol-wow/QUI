-- tests/unit/character_backdrop_persist_test.lua
-- Run: lua tests/unit/character_backdrop_persist_test.lua
--
-- Regression guard for the "character-frame live recolor reverts on the next
-- scale refresh" bug.
--
-- Root cause: QUI_Skinning/skinning/frames/character.lua skins several frames with a
-- LOCAL ApplyPixelBackdrop that persists color in a per-frame `state.bgColor` /
-- `state.borderColor` (the 5th/6th args), and re-applies that state on every
-- UIKit scale refresh via the local RefreshPixelBackdrop. The live-recolor
-- paths (RefreshEquipmentManagerColors / RefreshTitlePaneColors / the rep &
-- currency border refreshers) wrote the NEW theme color with a bare
-- frame:SetBackdrop*Color, which updates the live color but NOT `state`. So a
-- scale refresh fired after a theme change rebuilt the backdrop from the STALE
-- creation-time `state` color, reverting the theme change.
--
-- The fix routes those live-recolor writes through a local helper that updates
-- `state.bgColor`/`state.borderColor` AND the live color, so the rebuild keeps
-- the new color. This test drives the real production path
-- (_G.QUI_CharacterFrameSkinning.SkinEquipmentManager +
-- _G.QUI_CharacterFrameSkinning.Refresh) through the real local
-- RefreshPixelBackdrop to prove the contract.

-- luacheck: globals CreateFrame C_Timer hooksecurefunc InCombatLockdown
-- luacheck: globals QUI_EquipMgrPopup PanelTemplates_GetSelectedTab PanelTemplates_SetTab

-- A frame whose backdrop API mirrors WoW: SetBackdrop rebuilds the backdrop
-- textures and resets their color to white until SetBackdrop*Color is called.
local WHITE = { 1, 1, 1, 1 }
local function NewFrame()
    local f = { frameLevel = 1 }
    f.appliedBg = nil
    f.appliedBorder = nil
    function f:GetFrameLevel() return self.frameLevel end
    function f:SetFrameLevel(l) self.frameLevel = l end
    function f:SetFrameStrata() end
    function f:SetAllPoints() end
    function f:ClearAllPoints() end
    function f:SetPoint() end
    function f:EnableMouse() end
    function f:Show() end function f:Hide() end
    function f:IsShown() return false end
    function f:GetWidth() return 100 end
    function f:GetHeight() return 100 end
    function f:RegisterEvent() end
    function f:UnregisterEvent() end
    function f:SetScript() end
    function f:GetScript() end
    function f:HookScript() end
    -- WoW: SetBackdrop resets the backdrop colors to white until re-applied.
    function f:SetBackdrop(info)
        self.backdrop = info
        self.appliedBg = { WHITE[1], WHITE[2], WHITE[3], WHITE[4] }
        self.appliedBorder = { WHITE[1], WHITE[2], WHITE[3], WHITE[4] }
    end
    function f:GetBackdrop() return self.backdrop end
    function f:SetBackdropColor(r, g, b, a) self.appliedBg = { r, g, b, a or 1 } end
    function f:SetBackdropBorderColor(r, g, b, a) self.appliedBorder = { r, g, b, a or 1 } end
    return f
end

-- Capture scale-refresh callbacks so the test can fire one on demand. character.lua
-- registers via ns.UIKit.RegisterScaleRefresh(frame, key, fn).
local scaleRefreshers = {}
local function SimulateScaleRefresh()
    for _, entry in ipairs(scaleRefreshers) do entry.fn(entry.owner) end
end

-- Mutable themed skin colors the character module reads through GetSkinColors.
-- Order matches GetSkinColors(): sr,sg,sb,sa, bgr,bgg,bgb,bga.
local currentColors = { 0.1, 0.2, 0.3, 1, 0.4, 0.5, 0.6, 0.9 }
local function SetColors(t) currentColors = t end

local function CreateStateTable()
    local tbl = setmetatable({}, { __mode = "k" })
    local function get(key)
        local s = tbl[key]
        if not s then s = {}; tbl[key] = s end
        return s
    end
    return tbl, get
end

-- Model the canonical SkinBase pixel-backdrop engine (core/uikit.lua) that
-- character.lua's thin ApplyPixelBackdrop / SetPixelBackdropColors shims now
-- delegate to. Persist border/bg per frame in `pixelData` and re-render on each
-- scale refresh through the shared snapped 4-texture ApplyTextureBackdrop path.
-- SetBackdropColors updates the persisted data (NOT a bare setter) so a recolor
-- survives the next rebuild — the exact contract this test guards.
local pixelData = setmetatable({}, { __mode = "k" })
local function ApplyTextureBackdropStub(frame, _bgFile, _edgeFile, _edgeSize, borderColor, bgColor)
    if bgColor then
        frame:SetBackdropColor(bgColor[1], bgColor[2], bgColor[3], bgColor[4])
    else
        frame:SetBackdropColor(frame._quiBgR or 1, frame._quiBgG or 1, frame._quiBgB or 1, frame._quiBgA)
    end
    if borderColor then
        frame:SetBackdropBorderColor(borderColor[1], borderColor[2], borderColor[3], borderColor[4])
    else
        frame:SetBackdropBorderColor(frame._quiBorderR or 1, frame._quiBorderG or 1, frame._quiBorderB or 1, frame._quiBorderA)
    end
    return true
end
local function RenderPixelBackdrop(frame)
    local d = pixelData[frame]
    if not frame or not d then return end
    local edgeSize = (d.borderPixels or 1) * 0.5
    local bgColor = d.bgColor
    if not bgColor and frame._quiBgR ~= nil then
        bgColor = { frame._quiBgR, frame._quiBgG, frame._quiBgB, frame._quiBgA }
    end
    local borderColor = d.borderColor
    if not borderColor and frame._quiBorderR ~= nil then
        borderColor = { frame._quiBorderR, frame._quiBorderG, frame._quiBorderB, frame._quiBorderA }
    end
    ApplyTextureBackdropStub(frame, false, edgeSize > 0 and "x" or false, edgeSize, borderColor, bgColor)
end

local ns = {
    Addon = {
        GetPixelSize = function() return 0.5 end,
    },
    Helpers = {
        CreateStateTable = CreateStateTable,
        GetCore = function()
            return { db = { profile = {
                general = { skinCharacterFrame = true },
                character = { enabled = false },
            } } }
        end,
        CreateSkinColorGetter = function()
            return function()
                return currentColors[1], currentColors[2], currentColors[3], currentColors[4],
                    currentColors[5], currentColors[6], currentColors[7], currentColors[8]
            end
        end,
        GetGeneralFont = function() return "Interface\\QUIFont.ttf" end,
        -- The blessed persisting helpers (mirror core/utils.lua). Used at the
        -- customBg creation site (172-173); not the focus of this test.
        SetFrameBackdropColor = function(frame, r, g, b, a)
            frame:SetBackdropColor(r, g, b, a)
            frame._quiBgR, frame._quiBgG, frame._quiBgB, frame._quiBgA = r, g, b, a
        end,
        SetFrameBackdropBorderColor = function(frame, r, g, b, a)
            frame:SetBackdropBorderColor(r, g, b, a)
            frame._quiBorderR, frame._quiBorderG, frame._quiBorderB, frame._quiBorderA = r, g, b, a
        end,
    },
    -- The local ApplyPixelBackdrop now delegates its RENDER to the shared snapped
    -- 4-texture path (SkinBase.ApplyTextureBackdrop) — crisp at fractional UI
    -- scale, unlike SetBackdrop edge files. Colour PERSISTENCE stays local
    -- (state.bgColor/borderColor drive every re-apply). The stub mirrors
    -- ApplyTextureBackdrop's colour application (uikit.lua:2057-2067): use the
    -- passed colour, else the _quiBg*/_quiBorder* fallback fields.
    SkinBase = {
        -- Guarded pixel-size entry point (numerically mirrors Addon:GetPixelSize).
        GetPixelSize = function() return 0.5 end,
        ApplyTextureBackdrop = ApplyTextureBackdropStub,
        -- The canonical engine character.lua's shims delegate to.
        ApplyPixelBackdrop = function(frame, borderPixels, withBackground, withInsets, borderColor, bgColor)
            local d = pixelData[frame]
            if not d then d = {}; pixelData[frame] = d end
            d.borderPixels = borderPixels or 1
            d.withBackground = withBackground and true or false
            d.withInsets = withInsets and true or false
            d.borderColor = borderColor
            d.bgColor = bgColor
            RenderPixelBackdrop(frame)
            if not d.registered then
                -- mirror ns.UIKit.RegisterScaleRefresh (append to the captured
                -- list; `ns` is not yet in scope inside its own initializer).
                scaleRefreshers[#scaleRefreshers + 1] = { owner = frame, fn = RenderPixelBackdrop }
                d.registered = true
            end
        end,
        SetBackdropColors = function(frame, borderColor, bgColor)
            local d = pixelData[frame]
            if not d then
                if bgColor then frame:SetBackdropColor(bgColor[1], bgColor[2], bgColor[3], bgColor[4]) end
                if borderColor then frame:SetBackdropBorderColor(borderColor[1], borderColor[2], borderColor[3], borderColor[4]) end
                return
            end
            if borderColor ~= nil then d.borderColor = borderColor end
            if bgColor ~= nil then d.bgColor = bgColor end
            RenderPixelBackdrop(frame)
        end,
        -- character.lua registers its init via SkinBase.OnAddOnLoaded
        -- (uikit.lua). CharacterFrame is left nil above so auto-init is
        -- skipped; the stub absorbs the registration without firing it.
        OnAddOnLoaded = function() end,
        -- Bottom tabs now route through the canonical SkinBase.SkinTabGroup; this
        -- test only exercises the equipment-manager popup backdrop, so absorb the
        -- tab calls as no-ops.
        CollectNumberedTabs = function() return {} end,
        SkinTabGroup = function() end,
    },
    UIKit = {
        RegisterScaleRefresh = function(owner, _, fn)
            scaleRefreshers[#scaleRefreshers + 1] = { owner = owner, fn = fn }
        end,
    },
}

-- Globals the module references at load / in the popup path.
CreateFrame = function() return NewFrame() end
C_Timer = { After = function() end }
hooksecurefunc = function() end
function InCombatLockdown() return false end

-- Leave CharacterFrame/tabs nil so the module's auto-init is skipped; we drive
-- the exposed API directly.

assert(loadfile("QUI_Skinning/skinning/frames/character.lua"))("QUI", ns)

local API = _G.QUI_CharacterFrameSkinning
assert(type(API) == "table", "character.lua must expose _G.QUI_CharacterFrameSkinning")
assert(type(API.SkinEquipmentManager) == "function", "API must expose SkinEquipmentManager")
assert(type(API.Refresh) == "function", "API must expose Refresh")

-- THEME A: skin the equipment-manager popup. The local ApplyPixelBackdrop must
-- theme it and record the colors in `state` for scale-refresh persistence.
local THEME_A = { 0.10, 0.20, 0.30, 1, 0.40, 0.50, 0.60, 0.9 }
local THEME_B = { 0.70, 0.65, 0.20, 1, 0.12, 0.13, 0.14, 0.95 }

local popup = NewFrame()
_G.QUI_EquipMgrPopup = popup

SetColors(THEME_A)
API.SkinEquipmentManager()

assert(popup.appliedBg, "precondition: popup received a backdrop bg color on skin")
assert(popup.appliedBg[1] == THEME_A[5] and popup.appliedBg[4] == THEME_A[8],
    "precondition: themed popup bg is applied right after skinning")

-- THEME B: a theme change recolors via the refresh path.
SetColors(THEME_B)
API.Refresh()

assert(popup.appliedBg[1] == THEME_B[5] and popup.appliedBg[4] == THEME_B[8],
    "precondition: refresh applies the new theme bg to the live popup")

-- A scale refresh (e.g. UI scale change) rebuilds the backdrop. The new theme
-- color must SURVIVE it, not revert to the THEME_A color captured at skin time.
SimulateScaleRefresh()

assert(popup.appliedBg[1] == THEME_B[5] and popup.appliedBg[2] == THEME_B[6]
    and popup.appliedBg[3] == THEME_B[7] and popup.appliedBg[4] == THEME_B[8],
    "FIX: popup bg must survive the post-theme-change scale refresh, not revert to the old theme")
assert(popup.appliedBorder[1] == THEME_B[1] and popup.appliedBorder[2] == THEME_B[2]
    and popup.appliedBorder[3] == THEME_B[3] and popup.appliedBorder[4] == THEME_B[4],
    "FIX: popup border must survive the post-theme-change scale refresh, not revert to the old theme")

print("OK: character_backdrop_persist_test")
