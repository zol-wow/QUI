-- tests/unit/gamemenu_combat_skinning_test.lua
-- Run: lua tests/unit/gamemenu_combat_skinning_test.lua

function InCombatLockdown()
    return true
end

C_Timer = {
    After = function(_, callback)
        callback()
    end,
}

local createdByName = {}
local unnamedFrames = {}
local backdropApplications = 0

local function noop() end

local frameMeta = {}
frameMeta.__index = function(frame, key)
    if key == "SetFrameStrata" then
        return function(self, strata) self.frameStrata = strata end
    elseif key == "SetFrameLevel" then
        return function(self, level) self.frameLevel = level end
    elseif key == "SetDrawLayer" then
        return function(self, drawLayer, sublevel)
            self.drawLayer = drawLayer
            self.sublevel = sublevel or 0
        end
    elseif key == "SetSize"
        or key == "SetPoint" or key == "ClearAllPoints" or key == "SetAllPoints"
        or key == "EnableMouse" or key == "SetWidth" or key == "SetHeight"
        or key == "SetBackdropColor" or key == "SetBackdropBorderColor"
        or key == "SetText" or key == "RegisterForClicks" then
        return noop
    elseif key == "Show" then
        return function(self) self.shown = true end
    elseif key == "Hide" then
        return function(self)
            self.hidden = true
            self.shown = false
            self.hideCalls = (rawget(self, "hideCalls") or 0) + 1
        end
    elseif key == "IsShown" then
        return function(self) return self.shown and true or false end
    elseif key == "GetFrameLevel" then
        return function(self) return self.frameLevel or 10 end
    elseif key == "GetFrameStrata" then
        return function(self) return self.frameStrata or "MEDIUM" end
    elseif key == "GetBottom" then
        return function() return 100 end
    elseif key == "GetWidth" then
        return function() return 160 end
    elseif key == "GetHeight" then
        return function() return 30 end
    elseif key == "GetFontString" then
        return function(self) return self.fontString end
    elseif key == "GetHighlightTexture" or key == "GetPushedTexture"
        or key == "GetNormalTexture" or key == "GetDisabledTexture" then
        return function() return nil end
    elseif key == "HookScript" then
        return function(self)
            self.hookScriptCalls = (rawget(self, "hookScriptCalls") or 0) + 1
        end
    elseif key == "SetScript" then
        return function(self, script, handler) self.scripts[script] = handler end
    elseif key == "GetScript" then
        return function(self, script) return self.scripts[script] end
    elseif key == "CreateFontString" then
        return function(self)
            local fs = setmetatable({ scripts = {} }, frameMeta)
            self.createdFontString = fs
            return fs
        end
    elseif key == "CreateTexture" then
        return function(self, _, drawLayer)
            local texture = setmetatable({ scripts = {}, drawLayer = drawLayer }, frameMeta)
            table.insert(self.children, texture)
            return texture
        end
    elseif key == "IsMouseOver" then
        return function(self) return self.mouseOver and true or false end
    end
    if type(key) == "string" and key:match("^[A-Z]") then
        return noop
    end
    return nil
end

local function newFrame(name, parent)
    local frame = setmetatable({
        name = name,
        parent = parent,
        scripts = {},
        children = {},
        shown = false,
    }, frameMeta)
    if name then
        createdByName[name] = frame
    else
        table.insert(unnamedFrames, frame)
    end
    return frame
end

local function newTexture()
    return setmetatable({
        scripts = {},
    children = {},
    setAlphaCalls = 0,
    SetAlpha = function(self)
            self.setAlphaCalls = (rawget(self, "setAlphaCalls") or 0) + 1
    end,
}, frameMeta)
end

local fontString = setmetatable({
    scripts = {},
    children = {},
    text = "Options",
    setFontCalls = 0,
    setTextColorCalls = 0,
    GetText = function(self) return self.text end,
    SetFont = function(self) self.setFontCalls = (rawget(self, "setFontCalls") or 0) + 1 end,
    SetTextColor = function(self) self.setTextColorCalls = (rawget(self, "setTextColorCalls") or 0) + 1 end,
}, frameMeta)

local button = newFrame("GameMenuButtonOptions")
button.frameLevel = 105
button.frameStrata = "FULLSCREEN_DIALOG"
button.fontString = fontString
button.Left = newTexture()
button.Right = newTexture()
button.Center = newTexture()
button.Middle = newTexture()

UIParent = newFrame("UIParent")
GameMenuFrame = newFrame("GameMenuFrame", UIParent)
GameMenuFrame.shown = true
GameMenuFrame.frameStrata = "FULLSCREEN_DIALOG"
GameMenuFrame.frameLevel = 100
GameMenuFrame.Border = newFrame("GameMenuFrameBorder", GameMenuFrame)
GameMenuFrame.Header = newFrame("GameMenuFrameHeader", GameMenuFrame)
GameMenuFrame.buttonPool = {
    EnumerateActive = function()
        local yielded = false
        return function()
            if yielded then return nil end
            yielded = true
            return button
        end
    end,
}

function CreateFrame(_, name, parent)
    local frame = newFrame(name, parent)
    if parent and parent.children then
        table.insert(parent.children, frame)
    end
    return frame
end

local ns = {
    Helpers = {
        CreateStateTable = function()
            return setmetatable({}, { __mode = "k" })
        end,
        GetCore = function()
            return {
                db = {
                    profile = {
                        general = {
                            skinGameMenu = true,
                            gameMenuDim = false,
                            addQUIButton = false,
                            addEditModeButton = false,
                            gameMenuFontSize = 12,
                        },
                    },
                },
            }
        end,
        GetGeneralFont = function()
            return "Fonts\\FRIZQT__.TTF"
        end,
    },
    SkinBase = {
        CHROME = { BUTTON_BOOST = 0.07 },
        GetSkinColors = function()
            return 0.2, 0.6, 1, 1, 0.02, 0.02, 0.02, 0.95
        end,
        ApplyFullBackdrop = function()
            backdropApplications = backdropApplications + 1
        end,
        SkinFrameText = function() end,
    },
}

assert(loadfile("modules/skinning/system/gamemenu.lua"))("QUI", ns)

local watcher = assert(unnamedFrames[1], "game menu watcher should be created")
assert(type(watcher.scripts.OnUpdate) == "function", "game menu watcher should install OnUpdate")

watcher.scripts.OnUpdate(watcher, 0.05)

assert(createdByName.QUIGameMenuOverlay and createdByName.QUIGameMenuOverlay.shown, "overlay container should show when the menu opens in combat")
assert(createdByName.QUIGameMenuOverlay.frameStrata == GameMenuFrame.frameStrata, "overlay container should match GameMenuFrame strata")
assert(createdByName.QUIGameMenuOverlay.frameLevel > GameMenuFrame.frameLevel, "overlay container should be above GameMenuFrame")
local buttonOverlay
for _, child in ipairs(createdByName.QUIGameMenuOverlay.children) do
    if child.createdFontString then
        buttonOverlay = child
        break
    end
end
assert(buttonOverlay, "button overlay should be an addon-owned child of the overlay container")
assert(buttonOverlay.frameStrata == "TOOLTIP", "button overlay should render in a strata above Blizzard game menu buttons")
assert(buttonOverlay.frameLevel >= 9000, "button overlay should use a high frame level inside its overlay strata")
assert(buttonOverlay.coverTexture and buttonOverlay.coverTexture.drawLayer == "OVERLAY", "button overlay should use an OVERLAY cover texture above native button art")
assert(buttonOverlay.coverTexture.sublevel == 0, "button overlay cover should use the lower overlay sublevel")
assert(buttonOverlay.borderTop and buttonOverlay.borderTop.drawLayer == "OVERLAY", "button overlay should use OVERLAY border textures above native button art")
assert(buttonOverlay.borderTop.sublevel == 1, "button overlay borders should draw above the overlay cover")
assert(backdropApplications > 0, "combat game menu open should still apply addon-owned backdrop skinning")
assert((rawget(button, "hookScriptCalls") or 0) == 0, "combat skinning must not HookScript Blizzard game menu buttons")
assert(fontString.setFontCalls == 0, "combat skinning must not SetFont on Blizzard game menu text")
assert(button.Left.setAlphaCalls == 0, "combat skinning must not alter Blizzard button textures")
assert((rawget(GameMenuFrame.Border, "hideCalls") or 0) == 0, "combat skinning must not hide Blizzard game menu decorations directly")

print("OK: gamemenu_combat_skinning_test")
