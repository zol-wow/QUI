-- tests/chat_tab_secret_geometry_test.lua
-- Run: lua tests/chat_tab_secret_geometry_test.lua

local function noop() end

function InCombatLockdown() return false end

C_Timer = {
    After = function(_, callback) callback() end,
}

NUM_CHAT_WINDOWS = 11

local lastCreatedFrame

local function createFrame()
    local frame = {
        shown = true,
        frameLevel = 20,
        points = {},
    }

    function frame:RegisterEvent() end
    function frame:SetScript() end
    function frame:HookScript() end
    function frame:GetName() return self.name end
    function frame:GetID() return self.id end
    function frame:GetFrameLevel() return self.frameLevel end
    function frame:SetFrameLevel(level) self.frameLevel = level end
    function frame:SetIgnoreParentAlpha(value) self.ignoreParentAlpha = value end
    function frame:ClearAllPoints() self.points = {} end
    function frame:SetPoint(...) table.insert(self.points, {...}) end
    function frame:SetHeight(height) self.height = height end
    function frame:SetWidth(width) self.width = width end
    function frame:SetAlpha(alpha) self.alpha = alpha end
    function frame:SetTexture(texture) self.texture = texture end
    function frame:SetBlendMode(blendMode) self.blendMode = blendMode end
    function frame:SetVertexColor(r, g, b, a) self.vertexColor = { r, g, b, a } end
    function frame:SetTextColor(r, g, b, a) self.textColor = { r, g, b, a } end
    function frame:SetJustifyH(justify) self.justifyH = justify end
    function frame:SetFont(font, size, flags) self.font = { font, size, flags } end
    function frame:SetShadowOffset(x, y) self.shadowOffset = { x, y } end
    function frame:GetFont() return "Fonts\\FRIZQT__.TTF", 12, "" end
    function frame:GetFontString() return self.fontString end
    function frame:GetButtonState() return "NORMAL" end
    function frame:GetRegions() end
    function frame:IsShown() return self.shown end
    function frame:IsForbidden() return false end
    function frame:GetObjectType() return self.objectType or "Frame" end

    return frame
end

function CreateFrame()
    lastCreatedFrame = createFrame()
    return lastCreatedFrame
end

local chatFrame = createFrame()
chatFrame.name = "ChatFrame11"
chatFrame.id = 11
chatFrame.isTemporary = true

local fontString = createFrame()
local glow = createFrame()
local tab = createFrame()
tab.id = 11
tab.sizePadding = 10
tab.fontString = fontString
tab.glow = glow
function tab:GetWidth()
    error("secret tab width must not be read during tab chrome layout")
end

_G.ChatFrame11 = chatFrame
_G.ChatFrame11Tab = tab

local ns = {
    UIKit = {},
    QUI = {
        Chat = {
            _internals = {
                skinnedFrames = {},
                tabBackdrops = setmetatable({}, { __mode = "k" }),
                GetSettings = function()
                    return {
                        enabled = true,
                        glass = { enabled = true, bgAlpha = 0.4 },
                    }
                end,
                IsChatEnabled = function(settings) return settings and settings.enabled ~= false end,
                IsChatMessagingLockedDown = function() return false end,
                IsTemporaryChatFrame = function(frame) return frame and frame.isTemporary == true end,
                GetTabChatFrame = function(t) return t == tab and chatFrame or nil end,
                ApplySurfaceStyle = function(frame, bg, border)
                    frame.surface = { bg = bg, border = border }
                end,
                GetAccent = function() return { 0.2, 0.8, 0.6, 1 } end,
                QUI_COLORS = {
                    textDim = { 0.72, 0.72, 0.76, 1 },
                    accent = { 0.2, 0.8, 0.6, 1 },
                },
            },
        },
    },
}

assert(loadfile("modules/chat/skinning.lua"))("QUI", ns)

ns.QUI.Chat.Skinning.StyleTab(tab)

local backdrop = ns.QUI.Chat._internals.tabBackdrops[tab]
assert(backdrop, "tab styling should create a backdrop")
assert(backdrop == lastCreatedFrame, "backdrop should be the styled tab frame")

local rightPoint
for _, point in ipairs(backdrop.points) do
    if point[1] == "BOTTOMRIGHT" then
        rightPoint = point
        break
    end
end

assert(rightPoint, "temporary tab backdrop should use right-edge anchoring")
assert(rightPoint[4] == -10, "temporary tab backdrop should omit hidden icon reserve with a point offset")

print("OK: chat_tab_secret_geometry_test")
