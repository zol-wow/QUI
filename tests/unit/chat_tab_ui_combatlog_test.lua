-- tests/unit/chat_tab_ui_combatlog_test.lua
-- Run: lua tests/unit/chat_tab_ui_combatlog_test.lua
-- Verifies the combat-log tab's tab_ui behaviour:
--  * right-click yields ONLY "Combat Log Settings" (no move/close);
--  * a normal tab's menu never offers "Combat Log Settings";
--  * the combat-log tab IS drag-reorderable within its own tab bar;
--  * activating it calls CombatLogTab.Activate; switching away calls Deactivate.

local function makeFrame(ftype)
    local f = { ftype = ftype, shown = true, points = {} }
    local function noop() end
    f.SetPoint = function(s, ...) s.points[#s.points + 1] = { ... } end
    f.ClearAllPoints = function(s) s.points = {} end
    f.SetSize = noop; f.SetHeight = noop
    f.SetWidth = function(s, w) s.width = w end
    f.Show = function(s) s.shown = true end
    f.Hide = function(s) s.shown = false end
    f.IsShown = function(s) return s.shown end
    f.EnableMouse = noop; f.RegisterForDrag = noop; f.RegisterForClicks = noop
    f.SetAlpha = noop; f.SetFrameLevel = noop
    f.GetFrameLevel = function() return 5 end
    f.GetParent = function(s) return s._parent end
    f.SetParent = function(s, p) s._parent = p end
    f.RegisterEvent = noop
    f.SetScript = function(s, k, v) s["_" .. k] = v end
    f.CreateFontString = function()
        return { points = {},
            SetPoint = function(o, ...) o.points[#o.points + 1] = { ... } end,
            ClearAllPoints = function(o) o.points = {} end,
            SetText = function(o, t) o.text = t end,
            GetStringWidth = function() return 30 end,
            GetFont = function() return "F", 11, "" end,
            SetFont = function(o, p, sz, ol) o.font = { p, sz, ol } end,
            SetFontObject = noop, SetTextColor = noop, SetJustifyH = noop }
    end
    f.CreateTexture = function()
        return { SetPoint = noop, SetAllPoints = noop, SetTexture = noop,
            SetColorTexture = noop, SetHeight = noop, SetWidth = noop,
            SetShown = noop, Hide = noop }
    end
    return f
end

local created = {}
function _G.CreateFrame(ftype, name, parent)
    local f = makeFrame(ftype); f.name = name; f._parent = parent
    created[#created + 1] = f
    return f
end
_G.NUM_CHAT_WINDOWS = 10
function _G.GetChatWindowInfo(i)
    if i == 1 then return "General", 14, 1, 1, 1, 1, true, false, true end
    return ""
end
_G.ChatFontNormal = {}
_G.ShowUIPanel = function() _G._shownPanel = true end
_G.ChatConfigFrame = {}

-- Capture menu labels per right-click.
local menuLabels
local function fakeRoot()
    local r = {}
    function r:CreateButton(label) menuLabels[#menuLabels + 1] = label; return r end
    function r:CreateDivider() return r end
    function r:CreateColorSwatch(label) menuLabels[#menuLabels + 1] = label; return r end
    return r
end
_G.MenuUtil = { CreateContextMenu = function(owner, gen) menuLabels = {}; gen(owner, fakeRoot()) end }

local container = makeFrame("Frame")
local stubTabs = { { name = "General" }, { name = "Combat Log", combatLog = true } }
local function makeFilter() return function() return false end end

local clCalls = { activate = 0, deactivate = 0 }
local ns = {
    Helpers = { IsSecretValue = function() return false end,
        GetGeneralFont = function() return "F" end,
        GetGeneralFontOutline = function() return "" end },
    QUI = { Chat = {
        _internals = {
            GetSettings = function() return { enabled = true } end,
            IsChatEnabled = function(s) return s and s.enabled ~= false end,
            GetAccent = function() return { 0.2, 0.8, 0.6, 1 } end,
            GetThemeColors = function() return { bg = {0,0,0,1}, bgDark = {0,0,0,1},
                border = {0,0,0,1}, text = {1,1,1,1}, textDim = {0.7,0.7,0.7,1} } end,
        },
        DisplayLayer = { GetContainer = function() return container end },
        MessageStore = { OnAppend = function() end },
        TabManager = {
            SetActiveTab = function() end,
            GetActiveFilter = function() return nil end,
            GetWindowTabs = function() return stubTabs end,
            GetWindowTab = function(_, i) return stubTabs[i] end,
            BuildTabFilter = makeFilter,
            IsCombatLogTab = function(td) return type(td) == "table" and td.combatLog == true end,
        },
        CombatLogTab = {
            Activate = function() clCalls.activate = clCalls.activate + 1 end,
            Deactivate = function() clCalls.deactivate = clCalls.deactivate + 1 end,
            IsActiveWindow = function() return false end,
        },
    } },
}

-- tab_ui.lua indexes ns.L["..."] at load (post-i18n); install identity resolver.
(dofile("tests/helpers/locale.lua"))(ns)
assert(loadfile("QUI_Chat/chat/tab_ui.lua"))("QUI", ns)
local TabUI = ns.QUI.Chat.TabUI
TabUI.EnsureAttached()

local inst = TabUI._instances[1]
local function btnByFrameID(fid)
    for _, b in ipairs(inst.buttons) do if b.frameID == fid then return b end end
end
local normalBtn = btnByFrameID(-1)
local clBtn = btnByFrameID(-2)
assert(normalBtn and clBtn, "both tab buttons built (General + Combat Log)")

-- 1. Right-click the combat-log tab => exactly "Combat Log Settings".
clBtn._OnClick(clBtn, "RightButton")
assert(#menuLabels == 1 and menuLabels[1] == "Combat Log Settings",
    "combat-log menu should be only 'Combat Log Settings', got " .. table.concat(menuLabels, ","))

-- 2. Right-click a normal tab => never offers "Combat Log Settings".
normalBtn._OnClick(normalBtn, "RightButton")
for _, l in ipairs(menuLabels) do
    assert(l ~= "Combat Log Settings", "normal tab must not offer combat-log settings")
end

-- 3. Drag: the combat-log tab reorders within its bar like any custom tab.
inst.draggingBtn = nil
clBtn._OnDragStart(clBtn)
assert(inst.draggingBtn == clBtn, "combat-log tab must be drag-reorderable in its own bar")
inst.draggingBtn = nil
if inst.bar and inst.bar._OnUpdate then inst.bar:SetScript("OnUpdate", nil) end

-- 4. Activation routing: activate combat-log tab => Activate; switch away => Deactivate.
assert(TabUI.ActivateFrameID(1, 2) == true, "activate combat-log tab (index 2)")
assert(clCalls.activate == 1, "CombatLogTab.Activate called on activation")
assert(inst.combatLogActive == true, "instance marked combat-log active")
assert(TabUI.ActivateFrameID(1, 1) == true, "switch to the General tab")
assert(clCalls.deactivate == 1, "CombatLogTab.Deactivate called on switch-away")
assert(inst.combatLogActive == false, "instance no longer combat-log active")

print("OK chat_tab_ui_combatlog_test")
