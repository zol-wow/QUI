-- tests/unit/chat_tab_overflow_test.lua
-- Run: lua tests/unit/chat_tab_overflow_test.lua
-- Verifies tab-bar overflow handling: tabs that outgrow the bar hide from the
-- right into a "»" overflow button (leftmost always stays, room reserved for
-- the button itself), the button's menu lists hidden tabs in display order
-- (activate on click, middle-click closes a conversation, unread suffix),
-- the button restyles for hidden-active / hidden-unread state, resize
-- re-layout via OnSizeChanged, and unknown bar width disabling overflow.

local function makeFrame(ftype)
    local f = { ftype = ftype, shown = true, points = {} }
    local function noop() end
    f.SetPoint = function(s, ...) s.points[#s.points + 1] = { ... } end
    f.ClearAllPoints = function(s) s.points = {} end
    f.SetSize = noop; f.SetHeight = noop
    f.SetWidth = function(s, w) s.width = w end
    f.GetWidth = function(s) return s.width end -- nil until set
    f.Show = function(s) s.shown = true end
    f.Hide = function(s) s.shown = false end
    f.IsShown = function(s) return s.shown end
    f.EnableMouse = noop
    f.RegisterForDrag = noop
    f.RegisterForClicks = noop
    f.SetAlpha = noop
    f.SetFrameLevel = noop
    f.GetFrameLevel = function() return 5 end
    f.GetParent = function(s) return s._parent end
    f.SetParent = function(s, p) s._parent = p end
    f.SetScript = function(s, k, v) s["_" .. k] = v end
    f.CreateFontString = function()
        local fs = { points = {},
            SetPoint = function(o, ...) o.points[#o.points + 1] = { ... } end,
            ClearAllPoints = function(o) o.points = {} end,
            SetText = function(o, t) o.text = t end,
            GetStringWidth = function() return 30 end,
            GetFont = function() return "font.ttf", 11, "" end,
            SetFont = noop, SetFontObject = noop,
            SetTextColor = function(o, r, g, b) o.color = { r, g, b } end,
            SetJustifyH = noop }
        return fs
    end
    f.CreateTexture = function()
        local tx = { SetPoint = noop, ClearAllPoints = noop,
            SetAllPoints = noop, SetTexture = noop,
            SetColorTexture = function(o, r, g, b, a) o.color = { r, g, b, a } end,
            SetHeight = noop, SetWidth = noop,
            SetShown = function(o, v) o.visible = v end,
            Hide = function(o) o.visible = false end }
        return tx
    end
    return f
end

local created = {}
function _G.CreateFrame(ftype, name, parent)
    local f = makeFrame(ftype)
    f.name = name
    f._parent = parent
    created[#created + 1] = f
    return f
end
_G.NUM_CHAT_WINDOWS = 10
function _G.GetChatWindowInfo() return "" end
_G.ChatFontNormal = {}
_G.ChatTypeInfo = { WHISPER = { r = 1, g = 0.5, b = 1 } }

-- Menu API capture: clicking the overflow button hands us the generator.
local capturedGen
_G.MenuUtil = {
    CreateContextMenu = function(_, generator) capturedGen = generator end,
}
local function runMenu()
    assert(capturedGen, "overflow click should open a context menu")
    local root = { entries = {}, scroll = nil }
    function root:CreateButton(text, cb)
        local entry = { text = text, cb = cb }
        function entry:AddInitializer(fn) entry.init = fn end
        root.entries[#root.entries + 1] = entry
        return entry
    end
    function root:SetScrollMode(extent) root.scroll = extent end
    capturedGen(nil, root)
    capturedGen = nil
    return root
end

local container = makeFrame("Frame")
local setActiveCalls = {}
local activeFilter
local storeCb
local closedConvs = {}

-- Four saved tabs (72 px each with the 30 px stub string width) + one
-- conversation appended by the synthesis fallback.
local stubCustomTabs = {
    { name = "Alpha", groups = { A = true } },
    { name = "Beta",  groups = { B = true } },
    { name = "Gamma", groups = { C = true } },
    { name = "Delta", groups = { D = true } },
}
local stubConvs = { { key = "Pal-Realm", name = "Pal", windowID = 1 } }

local function makeFilter(td)
    return function(entry) return td.groups and td.groups[entry.k] or false end
end

local ns = {
    Helpers = {
        IsSecretValue = function() return false end,
        GetGeneralFont = function() return "font.ttf" end,
        GetGeneralFontOutline = function() return "" end,
    },
    QUI = { Chat = {
        _internals = {
            GetSettings = function() return { enabled = true } end,
            IsChatEnabled = function(s) return s and s.enabled ~= false end,
            GetAccent = function() return { 0.2, 0.8, 0.6, 1 } end,
            GetThemeColors = function() return {
                bg = { 0.05, 0.06, 0.07, 1 },
                bgDark = { 0.01, 0.02, 0.03, 1 },
                border = { 0.3, 0.3, 0.3, 0.4 },
                text = { 1, 1, 1, 1 },
                textDim = { 0.7, 0.7, 0.7, 1 },
            } end,
        },
        DisplayLayer = { GetContainer = function() return container end },
        MessageStore = { OnAppend = function(fn) storeCb = fn end },
        ConversationManager = {
            EachForWindow = function(windowID, fn)
                for i = 1, #stubConvs do
                    if stubConvs[i].windowID == windowID then fn(stubConvs[i]) end
                end
            end,
            Close = function(key) closedConvs[#closedConvs + 1] = key end,
        },
        TabManager = {
            SetActiveTab = function(_, td)
                activeFilter = td and makeFilter(td) or nil
                setActiveCalls[#setActiveCalls + 1] = { td = td }
            end,
            SetActiveConversation = function() end,
            GetActiveFilter = function() return activeFilter end,
            GetWindowTabs = function() return stubCustomTabs end,
            GetWindowTab = function(_, i) return stubCustomTabs[i] end,
            BuildTabFilter = makeFilter,
            BuildConversationFilter = function(key)
                return function(entry) return entry.conv == key end
            end,
        },
    } },
}

assert(loadfile("QUI_Chat/chat/tab_ui.lua"))("QUI", ns)
local TabUI = ns.QUI.Chat.TabUI

TabUI.EnsureAttached()
local inst = TabUI._instances[1]
local bar = inst.bar
local function buttons() return inst.buttons end

-- (1) Unknown bar width (stub returns nil): overflow disabled, all 5 visible.
assert(#buttons() == 5, "4 saved tabs + 1 conversation expected, got " .. #buttons())
for i = 1, 5 do
    assert(buttons()[i]:IsShown(), "tab " .. i .. " should be visible with unknown bar width")
end
assert(inst.firstHidden == nil, "no overflow with unknown bar width")
assert(not (inst.overflowBtn and inst.overflowBtn:IsShown()), "no overflow button when everything fits")

-- (2) Narrow bar: 5 tabs x 72 = 360 total; width 200 leaves tabs 1-2 (144)
-- plus the 42 px overflow button. OnSizeChanged drives the re-layout.
bar.width = 200
bar._OnSizeChanged(bar)
assert(inst.firstHidden == 3, "tabs 3+ should overflow, got " .. tostring(inst.firstHidden))
assert(buttons()[1]:IsShown() and buttons()[2]:IsShown(), "tabs 1-2 stay visible")
assert(not buttons()[3]:IsShown() and not buttons()[4]:IsShown() and not buttons()[5]:IsShown(),
    "tabs 3-5 hide into the overflow menu")
assert(inst.overflowBtn and inst.overflowBtn:IsShown(), "overflow button appears")
assert(inst.overflowBtn.points[1][1] == "BOTTOMLEFT" and inst.overflowBtn.points[1][4] == 144,
    "overflow button sits after the last visible tab, got x="
        .. tostring(inst.overflowBtn.points[1] and inst.overflowBtn.points[1][4]))
local lastVisX = buttons()[2].points[1][4]
assert(lastVisX + buttons()[2].width + inst.overflowBtn._quiTabW <= 200,
    "visible tabs + overflow button must fit inside the bar")

-- (3) Hidden-unread cue: a message for hidden tab Delta turns the » accent.
storeCb({ k = "D" })
assert(inst.unread[-4] == 1, "hidden tab still counts unread")
local accent = { 0.2, 0.8, 0.6 }
local c = inst.overflowBtn.label.color
assert(c and c[1] == accent[1] and c[2] == accent[2] and c[3] == accent[3],
    "overflow label should use accent while a hidden tab has unread")

-- (4) Menu lists exactly the hidden tabs, in order, with unread suffix and
-- conversation tint.
inst.overflowBtn._OnClick(inst.overflowBtn)
local root = runMenu()
assert(#root.entries == 3, "menu lists the 3 hidden tabs, got " .. #root.entries)
assert(root.entries[1].text == "Gamma", "first hidden tab first")
assert(root.entries[2].text == "Delta (1)", "unread count suffixed, got " .. tostring(root.entries[2].text))
assert(root.entries[3].text == "|cffff80ffPal|r", "conversation entry tinted, got " .. tostring(root.entries[3].text))
assert(root.scroll and root.scroll > 0, "long menus scroll")
assert(type(root.entries[3].init) == "function", "conversation rows register extra click types")

-- (5) Clicking a menu entry activates the hidden tab; » shows active styling.
root.entries[2].cb(nil, { buttonName = "LeftButton" })
assert(inst.activeID == -4, "hidden tab activates from the menu")
assert(setActiveCalls[#setActiveCalls].td == stubCustomTabs[4], "activation applies the tab data")
assert(inst.unread[-4] == nil, "activation clears unread")
assert(inst.overflowBtn.underline.visible == true, "» underlines while the active tab is hidden")

-- (6) Middle-click on a conversation entry closes it (no activation).
inst.overflowBtn._OnClick(inst.overflowBtn)
root = runMenu()
root.entries[3].cb(nil, { buttonName = "MiddleButton" })
assert(closedConvs[1] == "Pal-Realm", "middle-click closes the conversation")
assert(inst.activeID == -4, "middle-click must not activate")

-- (7) Widening the bar brings everything back.
bar.width = 4000
bar._OnSizeChanged(bar)
assert(inst.firstHidden == nil, "wide bar has no overflow")
for i = 1, 5 do
    assert(buttons()[i]:IsShown(), "tab " .. i .. " visible again after resize")
end
assert(not inst.overflowBtn:IsShown(), "overflow button hides when everything fits")
assert(inst.overflowBtn.underline.visible == false or inst.activeID ~= nil,
    "no stale underline state")

-- (8) Drag-reorder midpoints skip hidden tabs (no abort): shrink again and
-- check the exported drop-index math still sees only visible tabs.
bar.width = 200
bar._OnSizeChanged(bar)
assert(inst.firstHidden == 3, "overflow re-engages")

print("OK chat_tab_overflow_test")
