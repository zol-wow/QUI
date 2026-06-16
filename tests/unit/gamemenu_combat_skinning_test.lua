-- tests/unit/gamemenu_combat_skinning_test.lua
-- Run: lua tests/unit/gamemenu_combat_skinning_test.lua
--
-- Contract for the FLASH-FREE direct-skin design (replaced the old poll +
-- UIParent-overlay approach). The skin is baked into GameMenuFrame via a single
-- hooksecurefunc(GameMenuFrame, "InitButtons") that runs synchronously inside
-- OnShow before paint; dim + custom buttons are parented to GameMenuFrame so they
-- auto-hide. This test pins the COMBAT taint posture: the direct skin intentionally
-- performs cosmetic mutations (SetAlpha on slice art, SkinFontString on labels,
-- SetAlpha on decorations) on Blizzard frames even in combat -- those are not
-- protected calls -- but it must NEVER call AddButton/MarkDirty, HookScript a
-- secure frame, or hook the global ShowUIPanel/HideUIPanel.

function InCombatLockdown()
    return true
end

C_Timer = {
    After = function(_, callback) callback() end,
}

-- Stub font OBJECT returned by CreateFont. The direct skin drives the button's
-- per-state font objects (Normal/Highlight/Disabled) so the label keeps our
-- font across hover; record the calls so the test can assert it happened.
local FAMILY_SENTINEL = { __isFontFamily = true }
local labelFontObjectStub = {
    setFontObjectCalls = 0,
    setFontCalls = 0,
    SetFontObject = function(s) s.setFontObjectCalls = s.setFontObjectCalls + 1 end,
    SetFont = function(s) s.setFontCalls = s.setFontCalls + 1 end,
    SetTextColor = function() end,
}
function CreateFont() return labelFontObjectStub end

local createdByName = {}
local unnamedFrames = {}
local backdropApplications = 0
local fontStringSkins = {}      -- fontstrings routed through SkinFontString
local hookInstalls = {}         -- { obj=, method=, objIsString= }
local forbidden = {}            -- secure-mutation calls that must never happen

local function noop() end

-- Generic widget (frame OR texture) backed by a metatable so unmocked WoW
-- setters degrade to no-ops instead of erroring.
local widgetMeta = {}
widgetMeta.__index = function(_, key)
    if key == "SetFrameLevel" then
        return function(s, level) s.frameLevel = level end
    elseif key == "GetFrameLevel" then
        return function(s) return s.frameLevel or 10 end
    elseif key == "GetFrameStrata" then
        return function(s) return s.frameStrata or "MEDIUM" end
    elseif key == "SetAlpha" then
        -- Real (non-noop) so hooksecurefunc(tex,"SetAlpha") can wrap it and so
        -- we can count how often the direct skin touched a Blizzard texture.
        return function(s, a)
            s.alpha = a
            s.setAlphaCalls = (rawget(s, "setAlphaCalls") or 0) + 1
        end
    elseif key == "Hide" then
        return function(s)
            s.shown = false
            s.hideCalls = (rawget(s, "hideCalls") or 0) + 1
        end
    elseif key == "Show" then
        return function(s) s.shown = true end
    elseif key == "IsShown" then
        return function(s) return s.shown and true or false end
    elseif key == "IsObjectType" then
        return function(s, t) return t == "Texture" and s.isTexture or false end
    elseif key == "GetRegions" then
        return function(s) return unpack(s.regions or {}) end
    elseif key == "GetBottom" then
        return function() return 100 end
    elseif key == "GetWidth" then
        return function() return 160 end
    elseif key == "GetHeight" then
        return function() return 30 end
    elseif key == "GetFontString" then
        return function(s) return s.fontString end
    elseif key == "SetNormalFontObject" then
        return function(s, fo) s.normalFontObject = fo end
    elseif key == "SetHighlightFontObject" then
        return function(s, fo) s.highlightFontObject = fo end
    elseif key == "SetDisabledFontObject" then
        return function(s, fo) s.disabledFontObject = fo end
    elseif key == "CreateTexture" then
        return function(s, _, drawLayer)
            local tex = setmetatable(
                { scripts = {}, children = {}, drawLayer = drawLayer, isTexture = true },
                widgetMeta)
            table.insert(s.children, tex)
            return tex
        end
    elseif key == "CreateFontString" then
        return function(s)
            local fs = setmetatable({ scripts = {}, children = {}, isTexture = false }, widgetMeta)
            s.createdFontString = fs
            return fs
        end
    elseif key == "SetScript" then
        return function(s, script, handler) s.scripts[script] = handler end
    elseif key == "GetScript" then
        return function(s, script) return s.scripts[script] end
    elseif key == "HookScript" then
        -- Must NEVER be used on the secure game menu in the new design.
        return function(s)
            forbidden[#forbidden + 1] = "HookScript on " .. tostring(s.name or "?")
        end
    elseif key == "AddButton" then
        return function() forbidden[#forbidden + 1] = "AddButton" end
    elseif key == "MarkDirty" then
        return function() forbidden[#forbidden + 1] = "MarkDirty" end
    end
    if type(key) == "string" and key:match("^[A-Z]") then
        return noop
    end
    return nil
end

local function newWidget(name, parent, isTexture)
    local w = setmetatable({
        name = name,
        parent = parent,
        scripts = {},
        children = {},
        regions = {},
        shown = false,
        isTexture = isTexture or false,
    }, widgetMeta)
    if name then createdByName[name] = w else table.insert(unnamedFrames, w) end
    return w
end

function CreateFrame(_, name, parent)
    local frame = newWidget(name, parent, false)
    if parent and parent.children then table.insert(parent.children, frame) end
    return frame
end

function hooksecurefunc(obj, method, fn)
    -- Only the table form is permitted in the module; record everything so the
    -- test can assert there is no global ShowUIPanel/HideUIPanel hook and no
    -- OnUpdate/OnShow/OnHide frame hook.
    hookInstalls[#hookInstalls + 1] = { obj = obj, method = method, objIsString = type(obj) == "string" }
    if type(obj) == "table" and type(method) == "string" then
        local original = obj[method]
        obj[method] = function(...)
            if type(original) == "function" then original(...) end
            return fn(...)
        end
    end
end

-- ---- Blizzard game menu mocks --------------------------------------------
UIParent = newWidget("UIParent")
GameMenuFrame = newWidget("GameMenuFrame", UIParent)
GameMenuFrame.shown = true
GameMenuFrame.frameLevel = 100
GameMenuFrame.NineSlice = newWidget("GameMenuFrameNineSlice", GameMenuFrame)
GameMenuFrame.Border = newWidget("GameMenuFrameBorder", GameMenuFrame)
GameMenuFrame.Header = newWidget("GameMenuFrameHeader", GameMenuFrame)
GameMenuFrame.regions = {}  -- StripChromeOnce iterates these
GameMenuFrame.InitButtons = function() end  -- Blizzard original; our hook wraps it

local fontString = newWidget(nil, nil, false)
fontString.text = "Options"
fontString.GetText = function(s) return s.text end

local poolButton = newWidget("GameMenuButtonOptions", GameMenuFrame, false)
poolButton.frameLevel = 105
poolButton.fontString = fontString
poolButton.Left = newWidget(nil, nil, true)
poolButton.Center = newWidget(nil, nil, true)
poolButton.Right = newWidget(nil, nil, true)
-- GetRegions returns the slice textures + the label so StripButtonArt exercises
-- the strip loop (and must skip the fontstring + our own highlight).
poolButton.regions = { poolButton.Left, poolButton.Center, poolButton.Right, fontString }

GameMenuFrame.buttonPool = {
    EnumerateActive = function()
        local yielded = false
        return function()
            if yielded then return nil end
            yielded = true
            return poolButton
        end
    end,
}

local ns = {
    Registry = nil,
    Helpers = {
        CreateStateTable = function() return setmetatable({}, { __mode = "k" }) end,
        GetCore = function()
            return {
                db = { profile = { general = {
                    skinGameMenu = true,
                    gameMenuDim = false,
                    addQUIButton = false,
                    addEditModeButton = false,
                    gameMenuFontSize = 12,
                } } },
            }
        end,
        GetGeneralFont = function() return "Fonts\\FRIZQT__.TTF" end,
    },
    SkinBase = {
        CHROME = { BUTTON_BOOST = 0.07 },
        GetSkinColors = function() return 0.2, 0.6, 1, 1, 0.02, 0.02, 0.02, 0.95 end,
        ApplyFullBackdrop = function() backdropApplications = backdropApplications + 1 end,
        SkinFontString = function(fs) fontStringSkins[#fontStringSkins + 1] = fs end,
        SkinFrameText = function() end,
    },
}

assert(loadfile("QUI_Skinning/skinning/system/gamemenu.lua"))("QUI", ns)

-- ---- 1) Install surface: exactly one frame hook, on InitButtons -----------
local initHooks, scriptHooks = 0, 0
for _, h in ipairs(hookInstalls) do
    assert(not h.objIsString, "must not hooksecurefunc a global (no ShowUIPanel/HideUIPanel hook)")
    if h.obj == GameMenuFrame and h.method == "InitButtons" then initHooks = initHooks + 1 end
    if h.method == "OnUpdate" or h.method == "OnShow" or h.method == "OnHide" then
        scriptHooks = scriptHooks + 1
    end
end
assert(initHooks == 1, "exactly one hooksecurefunc(GameMenuFrame, 'InitButtons') must be installed")
assert(scriptHooks == 0, "must not install any OnUpdate/OnShow/OnHide frame hook")
assert(GameMenuFrame.scripts.OnUpdate == nil, "no OnUpdate poll watcher may exist")
assert(createdByName.QUIGameMenuOverlay == nil, "the UIParent overlay container must be gone")

-- ---- Trigger a menu open IN COMBAT (InitButtons fires synchronously) -------
GameMenuFrame:InitButtons()

-- ---- 2) The skin is applied during combat (no deferral) -------------------
assert(backdropApplications > 0, "combat menu open must apply addon-owned backdrops (menu bg + button inset)")
-- The label font must be driven through the button's per-state font OBJECTS,
-- not a one-shot fs:SetFont (which the button clobbers on hover by re-applying
-- its state font object). All three states get the same shared QUI font object.
assert(poolButton.normalFontObject == labelFontObjectStub,
    "button NormalFontObject must be the shared QUI label font object")
assert(poolButton.highlightFontObject == labelFontObjectStub,
    "button HighlightFontObject must be the shared QUI label font object (stable across hover)")
assert(poolButton.disabledFontObject == labelFontObjectStub,
    "button DisabledFontObject must be the shared QUI label font object")

-- ---- 3) Direct skin intentionally mutates Blizzard cosmetics in combat -----
assert((rawget(poolButton.Left, "setAlphaCalls") or 0) > 0, "direct skin must zero the Blizzard slice art")
assert(poolButton.Left.alpha == 0, "Blizzard slice art must be clamped to alpha 0")
assert(GameMenuFrame.Border.alpha == 0, "decorations must be hidden via SetAlpha(0)")

-- ---- 4) Decorations hidden via SetAlpha, never Hide -----------------------
assert((rawget(GameMenuFrame.Border, "hideCalls") or 0) == 0, "must not Hide() the secure decoration frame")
assert((rawget(GameMenuFrame.Header, "hideCalls") or 0) == 0, "must not Hide() the secure header frame")

-- ---- 5) No taint-vector calls ---------------------------------------------
assert(#forbidden == 0, "forbidden secure mutation(s): " .. table.concat(forbidden, ", "))

-- ---- 6) Slice SetAlpha clamp is installed once (idempotent across opens) ---
local function sliceHookCount()
    local n = 0
    for _, h in ipairs(hookInstalls) do
        if h.method == "SetAlpha" then n = n + 1 end
    end
    return n
end
local afterFirst = sliceHookCount()
assert(afterFirst >= 1, "slice SetAlpha clamp hook must be installed")
GameMenuFrame:InitButtons()  -- second open
assert(sliceHookCount() == afterFirst, "slice SetAlpha clamp must not re-install on re-open (info.clamped guard)")

-- ---- 7) Addon-owned frames parented to GameMenuFrame (auto-hide on close) --
assert(createdByName.QUIGameMenuBg and createdByName.QUIGameMenuBg.parent == GameMenuFrame,
    "menu background must be a child of GameMenuFrame")
assert(createdByName.QUIGameMenuDim and createdByName.QUIGameMenuDim.parent == GameMenuFrame,
    "dim frame must be a child of GameMenuFrame")

-- ---- 8) Per-button skin state lives off the secure button -----------------
assert(rawget(poolButton, "inset") == nil, "inset must live in the weak state table, not on the button")
assert(rawget(poolButton, "_quiBgR") == nil, "no QUI backdrop fields may be written onto the secure button")

print("OK: gamemenu_combat_skinning_test")
