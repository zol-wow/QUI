-- tests/unit/chat_editbox_top_focus_test.lua
-- Run: lua tests/unit/chat_editbox_top_focus_test.lua

local function noop() end

function _G.InCombatLockdown() return false end
function _G.GetChatWindowInfo() return "General" end
local stockTabClicks = 0
function _G.FCF_Tab_OnClick()
    stockTabClicks = stockTabClicks + 1
end

_G.C_Timer = {
    After = function(_, callback) callback() end,
}

local function createFrame()
    local frame = {
        shown = true,
        hooks = {},
        frameLevel = 20,
        width = 420,
    }

    function frame:RegisterEvent(event)
        self.events = self.events or {}
        self.events[event] = true
    end
    function frame:SetScript(script, callback) self.scripts = self.scripts or {}; self.scripts[script] = callback end
    function frame:HookScript(script, callback)
        self.hooks[script] = self.hooks[script] or {}
        table.insert(self.hooks[script], callback)
    end
    function frame:RunHooks(script)
        for _, callback in ipairs(self.hooks[script] or {}) do
            callback(self)
        end
    end
    function frame:ClearAllPoints() self.points = {} end
    function frame:SetPoint(...) self.points = self.points or {}; table.insert(self.points, {...}) end
    function frame:SetHeight(height) self.height = height end
    function frame:SetWidth(width) self.width = width end
    function frame:GetWidth() return self.width end
    function frame:GetName() return self.name end
    function frame:GetFrameLevel() return self.frameLevel end
    function frame:SetFrameLevel(level) self.frameLevel = level end
    function frame:Show() self.shown = true end
    function frame:Hide() self.shown = false end
    function frame:EnableMouse(enabled) self.mouseEnabled = enabled end
    function frame:SetAlpha(alpha) self.alpha = alpha end
    function frame:HasFocus() return self.focused end
    function frame:GetRegions() end
    function frame:SetTextInsets(left, right, top, bottom) self.insets = { left, right, top, bottom } end
    function frame:GetParent() return self.parent end
    function frame:SetParent(p) self.parent = p end

    return frame
end

local createdFrames = {}
function _G.CreateFrame(_, name, parent)
    local f = createFrame()
    f.parent = parent
    createdFrames[#createdFrames + 1] = f
    return f
end

local settings = {
    enabled = true,
    defaultTab = 2,
    defaultTabPerSpec = false,
    glass = { enabled = true },
    editBox = {
        enabled = true,
        positionTop = true,
    },
}
_G.ChatFrame2 = {}
_G.ChatFrame2Tab = {}

local editBox = createFrame()
editBox.focused = false
editBox.rejectHasFocusRead = true
function editBox:HasFocus()
    if self.rejectHasFocusRead then
        error("secret boolean focus state must not be read during style refresh")
    end
    return self.focused
end

local chatFrame = createFrame()
chatFrame.name = "ChatFrame1"
chatFrame.editBox = editBox

local ns = {
    Helpers = {
        IsSecretValue = function() return false end,
        GetCurrentSpecID = function() return nil end,
    },
    QUI = {
        Chat = {
            _internals = {
                editBoxState = setmetatable({}, { __mode = "k" }),
                editBoxBackdrops = setmetatable({}, { __mode = "k" }),
                GetSettings = function() return settings end,
                IsChatEnabled = function(s) return s and s.enabled ~= false end,
                ApplySurfaceStyle = noop,
            },
            TabUI = {
                ActivateFrameID = function(windowID, frameID)
                    settings._activatedDefaultTab = frameID
                    return true
                end,
            },
        },
    },
}

assert(loadfile("modules/chat/editbox_basics.lua"))("QUI", ns)

local EditBoxBasics = ns.QUI.Chat.EditBoxBasics

local defaultEventFrame
for _, frame in ipairs(createdFrames) do
    if frame.events and frame.events.PLAYER_ENTERING_WORLD then
        defaultEventFrame = frame
        break
    end
end
assert(defaultEventFrame, "default-tab event frame registered")
defaultEventFrame.scripts.OnEvent(defaultEventFrame, "PLAYER_ENTERING_WORLD", true, false)
assert(settings._activatedDefaultTab == 2,
    "default tab index must activate the matching QUI tab")
assert(stockTabClicks == 0,
    "default tab activation must not click or sync stock chat frame tabs")

EditBoxBasics.StyleEditBox(chatFrame)

local backdrop = ns.QUI.Chat._internals.editBoxBackdrops[chatFrame]
assert(backdrop, "top mode should create a backdrop")
assert(backdrop.shown == false, "unfocused top edit box should hide its backdrop")
assert(editBox.mouseEnabled == false, "unfocused top edit box should not intercept tab clicks")
assert(editBox.alpha == 0, "unfocused top edit box should hide retained draft text")

editBox.focused = true
editBox:RunHooks("OnEditFocusGained")
assert(backdrop.shown == true, "focused top edit box should show its backdrop")
assert(editBox.mouseEnabled == true, "focused top edit box should receive mouse input")
assert(editBox.alpha == 1, "focused top edit box should show text")

editBox.focused = false
editBox:RunHooks("OnEditFocusLost")
assert(backdrop.shown == false, "focus lost should hide top edit box backdrop")
assert(editBox.mouseEnabled == false, "focus lost should let tab clicks pass through")
assert(editBox.alpha == 0, "focus lost should hide retained draft text")

settings.editBox.positionTop = false
EditBoxBasics.StyleEditBox(chatFrame)
assert(backdrop.shown == true, "bottom edit box should show its backdrop")
assert(editBox.mouseEnabled == true, "bottom edit box should receive mouse input")
assert(editBox.alpha == 1, "bottom edit box should restore text visibility")

editBox:RunHooks("OnEditFocusGained")
editBox:RunHooks("OnEditFocusLost")
settings.editBox.positionTop = true
EditBoxBasics.StyleEditBox(chatFrame)
assert(backdrop.shown == false, "top edit box should ignore stale focus after bottom-mode blur")
assert(editBox.alpha == 0, "top edit box should hide stale draft text after bottom-mode blur")

-- Live-disabling the editBox sub-option: the settings bail inside StyleEditBox
-- must clean up prior styling (gate lives in ONE place — callers never
-- duplicate it), so the stock editbox returns without a /reload.
settings.editBox.positionTop = false
EditBoxBasics.StyleEditBox(chatFrame)
assert(backdrop.shown == true, "bottom edit box backdrop shown before the disable flip")
settings.editBox.enabled = false
EditBoxBasics.StyleEditBox(chatFrame)
assert(backdrop.shown == false, "gated-off styling must hide the QUI backdrop")
assert(editBox.mouseEnabled == true, "gated-off editbox regains mouse input")
assert(editBox.alpha == 1, "gated-off editbox text visible again")
settings.editBox.enabled = true

-- Turning off the chat background must not expose the stock input box chrome.
-- The input box has its own background setting; keep its takeover styling live.
EditBoxBasics.StyleEditBox(chatFrame)
assert(backdrop.shown == true, "re-enabling restores the backdrop")
settings.glass.enabled = false
EditBoxBasics.StyleEditBox(chatFrame)
assert(backdrop.shown == true, "chat background off must not remove the input box takeover backdrop")
settings.glass.enabled = true

-- STOCK RESTORE (review finding): a live disable flip must hand back a fully
-- stock editbox — anchors back on the chat frame per the Blizzard template
-- (TOPLEFT -> chatFrame BOTTOMLEFT -5,-2) and the styled latch cleared so a
-- re-enable re-strips.
editBox.points = {}
EditBoxBasics.RemoveEditBoxStyle(chatFrame)
local sawStock = false
for _, p in ipairs(editBox.points or {}) do
    if p[1] == "TOPLEFT" and p[2] == chatFrame and p[3] == "BOTTOMLEFT"
        and p[4] == -5 and p[5] == -2 then
        sawStock = true
    end
end
assert(sawStock, "RemoveEditBoxStyle must restore the stock TOPLEFT anchor")

print("OK: chat_editbox_top_focus_test")
