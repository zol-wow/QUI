-- tests/chat_editbox_top_focus_test.lua
-- Run: lua tests/chat_editbox_top_focus_test.lua

local function noop() end

function InCombatLockdown() return false end
function GetChatWindowInfo() return "General" end
function FCF_Tab_OnClick() end

C_Timer = {
    After = function(_, callback) callback() end,
}

local function createFrame()
    local frame = {
        shown = true,
        hooks = {},
        frameLevel = 20,
        width = 420,
    }

    function frame:RegisterEvent() end
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

    return frame
end

function CreateFrame()
    return createFrame()
end

local settings = {
    enabled = true,
    glass = { enabled = true },
    editBox = {
        enabled = true,
        positionTop = true,
    },
}

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
        },
    },
}

assert(loadfile("modules/chat/editbox_basics.lua"))("QUI", ns)

local EditBoxBasics = ns.QUI.Chat.EditBoxBasics
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

print("OK: chat_editbox_top_focus_test")
