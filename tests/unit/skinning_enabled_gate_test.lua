-- tests/unit/skinning_enabled_gate_test.lua
-- Run: lua tests/unit/skinning_enabled_gate_test.lua
--
-- Verifies the skinning master gate ns.IsSkinningEnabled() (added to
-- core/uikit.lua). Default ON: an absent profile / absent skinning table / nil
-- enabled all read as enabled; only an explicit enabled == false disables.
-- Every modules/skinning/** file reads this at the top of its hook/apply path,
-- so disabling skinning + /reload installs no QUI skin hooks.

-- luacheck: globals CreateFrame C_Timer hooksecurefunc ScrollUtil STANDARD_TEXT_FONT QUI
CreateFrame = function()
    local f = { textures = {}, level = 4 }
    function f:CreateTexture() local t = {}
        function t:ClearAllPoints() end function t:SetPoint() end function t:SetHeight() end
        function t:SetWidth() end function t:Show() end function t:Hide() end
        function t:SetTexture() end function t:SetColorTexture() end function t:SetVertexColor() end
        function t:SetAllPoints() end
        f.textures[#f.textures+1] = t; return t end
    function f:SetAllPoints() end function f:SetFrameLevel(l) self.level = l end
    function f:GetFrameLevel() return self.level end function f:EnableMouse() end
    function f:Show() end function f:Hide() end
    function f:SetBackdrop() end function f:SetBackdropColor(...) self.bgc = { ... } end
    function f:SetBackdropBorderColor(...) self.bdc = { ... } end
    return f
end
C_Timer = { After = function(_, fn) fn() end }
function hooksecurefunc() end
ScrollUtil = { AddAcquiredFrameCallback = function() end }
STANDARD_TEXT_FONT = "Fonts\\FRIZQT__.TTF"

local function CreateStateTable()
    local tbl = setmetatable({}, { __mode = "k" })
    return tbl, function(k) local s = tbl[k]; if not s then s = {}; tbl[k] = s end; return s end
end

local ns = {
    Helpers = {
        CHROME = {
            BORDER_PX = 1, BG_FALLBACK = { 0.05, 0.05, 0.05, 0.95 }, BORDER_FALLBACK = { 0, 0, 0, 1 },
            BUTTON_BOOST = 0.07, SCROLLROW_BOOST = 0.03,
            DEPTH = { PANEL = { boost = 0, alpha = 0.95 }, SUBPANEL = { boost = 0.04, alpha = 0.85 }, ROW = { boost = 0.07, alpha = 0.75 } },
        },
        CreateStateTable = CreateStateTable,
        GetCore = function() return { GetPixelSize = function() return 0.5 end } end,
        SafeToNumber = function(v, d) return tonumber(v) or d end,
        GetSkinBorderColor = function() return 0.6, 0.7, 0.8, 1 end,
        GetSkinBgColorWithOverride = function() return 0.1, 0.2, 0.3, 0.9 end,
        GetGeneralFont = function() return "Q.ttf" end,
        GetGeneralFontOutline = function() return "" end,
    },
}

-- Load the REAL core/uikit.lua (publishes ns.IsSkinningEnabled at file scope).
assert(loadfile("core/uikit.lua"))("QUI", ns)
assert(type(ns.IsSkinningEnabled) == "function", "core/uikit.lua must publish ns.IsSkinningEnabled")

-- Case 1: no _G.QUI at all -> default ON.
QUI = nil
assert(ns.IsSkinningEnabled() == true, "absent QUI db must read as enabled (default ON)")

-- Case 2: profile present but no skinning table -> default ON.
QUI = { db = { profile = {} } }
assert(ns.IsSkinningEnabled() == true, "absent profile.skinning must read as enabled (default ON)")

-- Case 3: skinning table present, enabled nil -> default ON.
QUI = { db = { profile = { skinning = {} } } }
assert(ns.IsSkinningEnabled() == true, "skinning.enabled == nil must read as enabled (default ON)")

-- Case 4: explicit enabled = true -> ON.
QUI = { db = { profile = { skinning = { enabled = true } } } }
assert(ns.IsSkinningEnabled() == true, "skinning.enabled == true must read as enabled")

-- Case 5: explicit enabled = false -> OFF (the only disabling case).
QUI = { db = { profile = { skinning = { enabled = false } } } }
assert(ns.IsSkinningEnabled() == false, "skinning.enabled == false must read as DISABLED")

QUI = nil
print("OK: skinning_enabled_gate_test")
