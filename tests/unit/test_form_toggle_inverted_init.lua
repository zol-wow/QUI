-- tests/unit/test_form_toggle_inverted_init.lua
-- Regression: CreateFormToggleInverted (BuildPillToggle invert=true) used to
-- call SetValue(GetValue(), true) at construction. GetValue() for the
-- inverted variant returns `not db`, so an absent key (nil, falsy) reads as
-- display-ON (true); routing that back through SetValue wrote the inverted
-- DB value (false) into dbTable[dbKey] -- seeding the absent key and
-- violating the raw-SV absent-key-means-default convention. Init must be
-- display-only; only a real user click (the widget's own OnClick handler)
-- may write dbTable[dbKey].
--
-- Loads the REAL framework headlessly via the search-cache generator's WoW-API
-- stub preamble (same technique as tests/unit/test_form_slider_init.lua).
-- Run: lua tests/unit/test_form_toggle_inverted_init.lua

local GEN_PATH = "tools/generate_search_cache.lua"
local CUT_MARKER = 'local frame = create_stub_node("Frame", nil, false)'
local fh = assert(io.open(GEN_PATH, "rb"), "cannot open " .. GEN_PATH)
local src = fh:read("*a"); fh:close()
local cut = assert(src:find(CUT_MARKER, 1, true),
    "generator preamble cut marker not found -- update CUT_MARKER")
assert((loadstring or load)(src:sub(1, cut - 1), "@gen-preamble"))()

local GUI = assert(_G.QUI and _G.QUI.GUI, "framework did not initialize QUI.GUI")
assert(type(GUI.CreateFormToggleInverted) == "function", "framework must expose CreateFormToggleInverted")

-- The generator's stub CreateFrame maps SetScript to a shared noop (the
-- generator's own page-walk never fires script handlers). Give every stub
-- node a real Set/GetScript pair so this test can invoke the widget's own
-- OnClick handler and prove a genuine user interaction still writes.
local realCreateFrame = _G.CreateFrame
_G.CreateFrame = function(frameType, name, parent, ...)
    local node = realCreateFrame(frameType, name, parent, ...)
    local scripts = {}
    node.SetScript = function(self, event, handler) scripts[event] = handler end
    node.GetScript = function(self, event) return scripts[event] end
    return node
end

local parent = _G.CreateFrame("Frame")

-- Case A: a pre-existing stored value must survive widget creation unmodified
-- (both possible boolean states -- the inversion must not perturb storage).
local storeFalse = { hideNames = false }
GUI:CreateFormToggleInverted(parent, "Hide Names", "hideNames", storeFalse, nil, {})
assert(storeFalse.hideNames == false,
    "widget init mutated a pre-existing false value: " .. tostring(storeFalse.hideNames))

local storeTrue = { hideNames = true }
GUI:CreateFormToggleInverted(parent, "Hide Names", "hideNames", storeTrue, nil, {})
assert(storeTrue.hideNames == true,
    "widget init mutated a pre-existing true value: " .. tostring(storeTrue.hideNames))

-- Case B: an absent key must stay absent. GetValue() for the inverted
-- variant reads `not db`, so an absent key displays as ON (true); the old
-- code wrote the inverted DB value (false) back at construction.
local storeAbsent = {}
GUI:CreateFormToggleInverted(parent, "Hide Names", "hideNames", storeAbsent, nil, {})
assert(storeAbsent.hideNames == nil,
    "widget init seeded absent key: " .. tostring(storeAbsent.hideNames))

-- Case C: a real user click must still write dbTable[dbKey].
local storeClick = {}
local widget = GUI:CreateFormToggleInverted(parent, "Hide Names", "hideNames", storeClick, nil, {})
local toggleBtn = widget.thumb
assert(toggleBtn, "widget must expose its clickable toggle as .thumb")
local onClick = toggleBtn:GetScript("OnClick")
assert(type(onClick) == "function", "toggle must register an OnClick handler")
onClick(toggleBtn)
assert(storeClick.hideNames == true,
    "user click did not write the expected value: " .. tostring(storeClick.hideNames))

print("OK: test_form_toggle_inverted_init")
