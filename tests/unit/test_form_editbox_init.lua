-- tests/unit/test_form_editbox_init.lua
-- Regression: CreateFormEditBox used to call SetValue(GetValue(), true) at
-- construction time. GetValue() stringifies the stored value for display
-- (tostring(v)) and falls back to options.value/"" when the key is absent;
-- routing either result back through SetValue rewrote dbTable[dbKey] on
-- every widget build -- corrupting non-string stored types (e.g. a stored
-- number became a stored string) and seeding absent keys with the fallback
-- default (violating the raw-SV absent-key-means-default convention). Init
-- must be display-only; only a real user commit (Enter, focus-lost, or live
-- typing) may write dbTable[dbKey].
--
-- Loads the REAL framework headlessly via the search-cache generator's WoW-API
-- stub preamble (same technique as tests/unit/test_form_slider_init.lua).
-- Run: lua tests/unit/test_form_editbox_init.lua

local GEN_PATH = "tools/generate_search_cache.lua"
local CUT_MARKER = 'local frame = create_stub_node("Frame", nil, false)'
local fh = assert(io.open(GEN_PATH, "rb"), "cannot open " .. GEN_PATH)
local src = fh:read("*a"); fh:close()
local cut = assert(src:find(CUT_MARKER, 1, true),
    "generator preamble cut marker not found -- update CUT_MARKER")
assert((loadstring or load)(src:sub(1, cut - 1), "@gen-preamble"))()

local GUI = assert(_G.QUI and _G.QUI.GUI, "framework did not initialize QUI.GUI")
assert(type(GUI.CreateFormEditBox) == "function", "framework must expose CreateFormEditBox")

-- The generator's stub CreateFrame maps SetScript to a shared noop (the
-- generator's own page-walk never fires script handlers). Give every stub
-- node a real Set/GetScript pair so this test can invoke the widget's own
-- OnEnterPressed handler and prove a genuine user commit still writes.
local realCreateFrame = _G.CreateFrame
_G.CreateFrame = function(frameType, name, parent, ...)
    local node = realCreateFrame(frameType, name, parent, ...)
    local scripts = {}
    node.SetScript = function(self, event, handler) scripts[event] = handler end
    node.GetScript = function(self, event) return scripts[event] end
    return node
end

local parent = _G.CreateFrame("Frame")

-- Case A: a pre-existing stored value must survive widget creation
-- unmodified -- including its Lua type. GetValue() stringifies for display
-- (tostring(5) == "5"); the old code wrote that display string back,
-- silently turning a stored number into a stored string on every build.
local store = { count = 5 }
GUI:CreateFormEditBox(parent, "Count", "count", store, nil, {}, {})
assert(store.count == 5 and type(store.count) == "number",
    "widget init corrupted stored value: " .. tostring(store.count) .. " (" .. type(store.count) .. ")")

-- Case B: an absent key must stay absent. GetValue() falls back to
-- options.value ("DefaultName") when the key is missing so the field has
-- something to display; the old code wrote that fallback into dbTable.
local storeAbsent = {}
GUI:CreateFormEditBox(parent, "Name", "name", storeAbsent, nil, { value = "DefaultName" }, {})
assert(storeAbsent.name == nil,
    "widget init seeded absent key: " .. tostring(storeAbsent.name))

-- Case C: a real user commit (Enter pressed) must still write dbTable[dbKey].
local storeCommit = {}
local widget = GUI:CreateFormEditBox(parent, "Name", "name", storeCommit, nil, { value = "DefaultName" }, {})
local editBox = widget.editBox
assert(editBox, "widget must expose its EditBox as .editBox")
editBox:SetText("Typed Value")
local onEnter = editBox:GetScript("OnEnterPressed")
assert(type(onEnter) == "function", "editbox must register an OnEnterPressed handler")
onEnter(editBox)
assert(storeCommit.name == "Typed Value",
    "user commit did not write the expected value: " .. tostring(storeCommit.name))

print("OK: test_form_editbox_init")
