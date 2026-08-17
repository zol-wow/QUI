local loadSource = loadstring or load

local function readFile(path)
    local fh = assert(io.open(path, "rb"), "failed to open " .. path)
    local text = fh:read("*a")
    fh:close()
    return text
end

local source = readFile("modules/skinning/character_pane/character.lua")

local function slice(first, after)
    local startAt = assert(source:find(first, 1, true), "missing " .. first)
    local endAt = assert(source:find(after, startAt + #first, true), "missing " .. after)
    return source:sub(startAt, endAt - 1)
end

local scaleTest = assert(loadSource([[
local applied
local CharacterFrame = { SetScale = function(_, scale) applied = scale end }
local InCombatLockdown = function() return true end
]] .. slice(
    "local function SetCharacterFrameScale(scale)",
    "local function AreCharacterStatsSecretsDisabled()") .. [[
return function()
    SetCharacterFrameScale(1.3)
    return applied
end
]], "@character.lua#SetCharacterFrameScale"))()

assert(scaleTest() == 1.3, "Character panel scale must apply during combat")

local hideTest = assert(loadSource([[
local hidden = 0
local CharacterFrame = {
    TopTileStreaks = { Hide = function() hidden = hidden + 1 end },
}
local GetSettings = function() return {} end
local AnchorCharacterFrameBottomTabs = function() end
local InCombatLockdown = function() return true end
local frameState, EMPTY = {}, {}
]] .. slice(
    "local function HideBlizzardDecorations()",
    "local function CreateCustomBackground()") .. [[
return function()
    HideBlizzardDecorations()
    return hidden
end
]], "@character.lua#HideBlizzardDecorations"))()

assert(hideTest() == 1, "Character panel decorations must be hidden during combat")

local repositionTest = assert(loadSource([[
local anchored = 0
local function newSlot()
    return {
        SetScale = function() end,
        ClearAllPoints = function() end,
        SetPoint = function() anchored = anchored + 1 end,
    }
end
local CharacterFrameBg = {}
local CharacterHeadSlot, CharacterNeckSlot, CharacterShoulderSlot = newSlot(), newSlot(), newSlot()
local CharacterBackSlot, CharacterChestSlot, CharacterShirtSlot = newSlot(), newSlot(), newSlot()
local CharacterTabardSlot, CharacterWristSlot, CharacterHandsSlot = newSlot(), newSlot(), newSlot()
local CharacterWaistSlot, CharacterLegsSlot, CharacterFeetSlot = newSlot(), newSlot(), newSlot()
local CharacterFinger0Slot, CharacterFinger1Slot = newSlot(), newSlot()
local CharacterTrinket0Slot, CharacterTrinket1Slot = newSlot(), newSlot()
local CharacterMainHandSlot, CharacterSecondaryHandSlot = newSlot(), newSlot()
local GetSettings = function() return {} end
local InCombatLockdown = function() return true end
]] .. slice(
    "local function RepositionSlots()",
    "local function PositionModelScene()") .. [[
return function()
    RepositionSlots()
    return anchored
end
]], "@character.lua#RepositionSlots"))()

assert(repositionTest() > 0, "Character equipment slots must be repositioned during combat")

local layoutTest = assert(loadSource([[
local calls = {}
local function called(name)
    calls[name] = (calls[name] or 0) + 1
end
local layoutApplied = false
local ApplyCharacterPaneLayout
local GetSettings = function() return { enabled = true } end
local InCombatLockdown = function() return true end
local HideBlizzardDecorations = function() called("decorations") end
local CreateCustomBackground = function() called("background") end
local SetupTitleArea = function() called("title") end
local RunAfterCharacterPaneLayoutTick = function(callback) callback() end
local RepositionSlots = function() called("slots") end
local RefreshEquipmentSlotBorders = function() called("borders") end
local PositionModelScene = function() called("model") end
local PositionStatsPanelForLayout = function() called("stats") end
]] .. slice(
    "ApplyCharacterPaneLayout = function(force)",
    "local function InitializeCharacterOverlays()") .. [[
return function()
    ApplyCharacterPaneLayout()
    return calls
end
]], "@character.lua#ApplyCharacterPaneLayout"))()

local calls = layoutTest()
for _, name in ipairs({ "decorations", "background", "title", "slots", "borders", "model", "stats" }) do
    assert(calls[name] == 1, "Character pane layout must apply " .. name .. " during combat")
end

local showNativeDecorations = assert(loadSource([[
local shown = 0
local function nativeDecoration()
    return { Show = function() shown = shown + 1 end }
end
local CharacterFramePortrait = nativeDecoration()
local CharacterFrameBg = nativeDecoration()
local CharacterFrame = {
    Background = nativeDecoration(),
    NineSlice = nativeDecoration(),
}
local InCombatLockdown = function() return true end
local statsPanel, customBg
local slotOverlays, frameState, EMPTY = {}, {}, {}
local RestoreCharacterPanePopouts = function() end
local IsSkinningHandlingBackground = function() return false end
local SetCharacterFrameScale = function() end
local AdjustForNonCharacterTab = function() end
]] .. slice(
    "    local function HideCustomElements()",
    "    if ReputationFrame then") .. [[
return function()
    HideCustomElements()
    return shown
end
]], "@character.lua#HideCustomElements"))()

assert(showNativeDecorations() == 4, "Native character decorations must be shown on other tabs during combat")

local hideNativeDecorations = assert(loadSource([[
local hidden = 0
local onShow
local function nativeDecoration()
    return { Hide = function() hidden = hidden + 1 end }
end
local PaperDollFrame = { HookScript = function(_, _, callback) onShow = callback end }
local CharacterFramePortrait = nativeDecoration()
local CharacterFrameBg = nativeDecoration()
local CharacterFrame = {
    Background = nativeDecoration(),
    NineSlice = nativeDecoration(),
}
local GetSettings = function() return { enabled = true, panelScale = 1 } end
local InCombatLockdown = function() return true end
local RestoreCharacterPanePopouts = function() end
local SelectCharacterStatsSidebarTab = function() end
local RestoreCharacterTabPositions = function() end
local SetCharacterFrameScale = function() end
local layoutApplied = true
local IsSkinningHandlingBackground = function() return false end
local customBg, statsPanel
local MaskNativeStatsPane = function() end
local slotOverlays, frameState, EMPTY = {}, {}, {}
local ScheduleUpdate = function() end
local allEquipmentSlots = {}
local RunAfterCharacterPaneLayoutTick = function(callback) callback() end
]] .. slice(
    "    if PaperDollFrame then\n        PaperDollFrame:HookScript(\"OnShow\", function()",
    "    if CharacterFrameTab1 and not") .. [[
return function()
    onShow()
    return hidden
end
]], "@character.lua#PaperDollFrameOnShow"))()

assert(hideNativeDecorations() == 4, "Native character decorations must be hidden on the character tab during combat")

print("OK: character_pane_combat_resize_immediate_test")
