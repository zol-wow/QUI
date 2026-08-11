-- tests/unit/instanceframes_lifecycle_test.lua
-- Run: lua tests/unit/instanceframes_lifecycle_test.lua

local function readFile(path)
    local fh = assert(io.open(path, "rb"), "failed to open " .. path)
    local text = fh:read("*a")
    fh:close()
    return text
end

local function assertContains(text, needle, reason)
    assert(text:find(needle, 1, true), reason)
end

local function assertAbsent(text, needle, reason)
    assert(not text:find(needle, 1, true), reason)
end

local instanceframes = readFile("modules/skinning/frames/instanceframes.lua")
local pveFrame = readFile("tests/framexml/Interface/AddOns/Blizzard_GroupFinder/Mainline/PVEFrame.lua")
local pvpui = readFile("tests/framexml/Interface/AddOns/Blizzard_PVPUI/Mainline/Blizzard_PVPUI.lua")
local challenges = readFile("tests/framexml/Interface/AddOns/Blizzard_ChallengesUI/Mainline/Blizzard_ChallengesUI.lua")

assertContains(pveFrame, "if not panels[tabIndex].loadFunc() then",
    "FrameXML must load PVP/Challenges addons (12.1 loadFunc) inside PVEFrame_ShowFrame before the selected panel is shown")
assertContains(pveFrame, "panel:Show();",
    "FrameXML must show the selected child panel synchronously after addon loading")
assertContains(pveFrame, "function PVEFrameMixin:OnShow()",
    "FrameXML must expose a stable PVEFrame OnShow lifecycle")
assertContains(pvpui, "function PVPUIFrame_OnShow(self)",
    "FrameXML must expose a stable PVPUIFrame OnShow lifecycle")
assertContains(challenges, "function ChallengesFrameMixin:OnShow()",
    "FrameXML must expose a stable ChallengesFrame OnShow lifecycle")

assertAbsent(instanceframes, "single qScrollHooked flag makes a second hook a no-op",
    "Instance-frame comments must not claim HookScrollBoxRowFonts cannot compose; SkinBase now composes acquired callbacks")
assertContains(instanceframes, "HookScrollBoxAcquired composes callbacks",
    "Specific battleground row comment must document the current SkinBase composition behavior")

assertAbsent(instanceframes, "C_Timer.After(0.1, SkinInstanceFrames)",
    "Instance-frame load/show lifecycle must not use fixed 0.1s catch-up timers")
assertAbsent(instanceframes, "frame:RegisterEvent(\"ADDON_LOADED\")",
    "Instance-frame lifecycle must use SkinBase.OnAddOnLoaded instead of a local ADDON_LOADED watcher")
assertContains(instanceframes, "SkinBase.OnAddOnLoaded(\"Blizzard_PVPUI\", SkinInstanceFrames, 0)",
    "PVP LOD catch-up must use SkinBase.OnAddOnLoaded's fully-loaded lifecycle")
assertContains(instanceframes, "SkinBase.OnAddOnLoaded(\"Blizzard_ChallengesUI\", SkinInstanceFrames, 0)",
    "Challenges LOD catch-up must use SkinBase.OnAddOnLoaded's fully-loaded lifecycle")
assertContains(instanceframes, "PVEFrame:HookScript(\"OnShow\", SkinInstanceFrames)",
    "PVEFrame OnShow should skin through the direct FrameXML lifecycle")

do
    local hooks = {}
    function hooksecurefunc(target, methodOrFn, maybeFn)
        local name, fn
        if type(target) == "string" then
            name, fn = target, methodOrFn
        else
            name, fn = tostring(target) .. "." .. tostring(methodOrFn), maybeFn
        end
        hooks[name] = fn
    end

    C_Timer = { After = function(_, fn) fn() end }
    function CreateFrame() return {} end
    function LFGListCategorySelection_UpdateCategoryButtons() end
    function LFGListCategorySelection_UpdateNavButtons() end

    local function NewTexture(shown)
        local t = { shown = shown and true or false }
        function t:SetAlpha(a) self.alpha = a end
        function t:IsShown() return self.shown end
        function t:SetShown(v) self.shown = v and true or false end
        return t
    end

    local function NewButton(name, selected)
        return { name = name, SelectedTexture = NewTexture(selected) }
    end

    local cat1 = NewButton("Questing", true)
    local cat2 = NewButton("Dungeons", false)
    local startButton = NewButton("Start", false)
    local findButton = NewButton("Find", false)

    local lfgListFrame = {
        CategorySelection = {
            CategoryButtons = { cat1, cat2 },
            StartGroupButton = startButton,
            FindGroupButton = findButton,
        },
    }
    LFGListFrame = lfgListFrame

    local state = setmetatable({}, { __mode = "k" })
    local categorySkinCalls, buttonSkinCalls = 0, 0
    local buttonRefreshCalls = 0
    local refreshes = {}

    local SkinBase = {}
    function SkinBase.GetSkinColors() return 0.6, 0.7, 0.8, 1, 0.1, 0.2, 0.3, 0.9 end
    function SkinBase.IsSkinned(frame) return frame and frame._skinned end
    function SkinBase.MarkSkinned(frame) frame._skinned = true end
    function SkinBase.IsStyled(frame) return frame and frame._styled end
    function SkinBase.MarkStyled(frame) frame._styled = true end
    function SkinBase.GetFrameData(frame, key) return state[frame] and state[frame][key] end
    function SkinBase.SetFrameData(frame, key, value)
        state[frame] = state[frame] or {}
        state[frame][key] = value
    end
    function SkinBase.StripTextures() end
    function SkinBase.SkinFrameText() end
    function SkinBase.LockFrameTextObjects() end
    function SkinBase.SkinButton(button)
        buttonSkinCalls = buttonSkinCalls + 1
        SkinBase.MarkStyled(button)
    end
    function SkinBase.RefreshButtonVisualState()
        buttonRefreshCalls = buttonRefreshCalls + 1
    end
    function SkinBase.SkinCategoryButton(button)
        categorySkinCalls = categorySkinCalls + 1
        SkinBase.MarkStyled(button)
    end
    function SkinBase.RefreshCategorySelected(button)
        refreshes[#refreshes + 1] = {
            button = button,
            selected = button.SelectedTexture and button.SelectedTexture:IsShown() or false,
            selectedTextColor = SkinBase.GetFrameData(button, "categorySelectedTextColor"),
        }
    end
    function SkinBase.OnAddOnLoaded(addon, fn)
        if addon == "Blizzard_GroupFinder" then fn() end
    end

    local ns = {
        Helpers = {
            GetCore = function()
                return { db = { profile = { general = { skinInstanceFrames = true } } } }
            end,
        },
        SkinBase = SkinBase,
    }

    assert(loadfile("modules/skinning/frames/instanceframes.lua"))("QUI", ns)

    assert(categorySkinCalls == 2, "LFG category rows must use SkinCategoryButton for selected-state visuals")
    assert(buttonSkinCalls == 2, "Start/Find action buttons should still use the regular button skin")
    assert(buttonRefreshCalls == 2, "Start/Find action buttons must sync visible state after skinning")
    assert(#refreshes == 2, "initial category skin pass must sync selected-state visuals")
    assert(refreshes[1].button == cat1 and refreshes[1].selected == true, "initial selected row should be Questing")
    assert(refreshes[2].button == cat2 and refreshes[2].selected == false, "initial unselected row should be Dungeons")

    cat1.SelectedTexture:SetShown(false)
    cat2.SelectedTexture:SetShown(true)
    assert(type(hooks.LFGListCategorySelection_UpdateCategoryButtons) == "function",
        "LFG category update hook must be installed")
    hooks.LFGListCategorySelection_UpdateCategoryButtons()

    assert(#refreshes == 4, "category update hook must refresh existing rows, not only skin new rows")
    assert(refreshes[3].button == cat1 and refreshes[3].selected == false, "Questing should lose selected styling")
    assert(refreshes[4].button == cat2 and refreshes[4].selected == true, "Dungeons should gain selected styling")
    assert(refreshes[4].selectedTextColor and math.abs(refreshes[4].selectedTextColor[2] - 0.82) < 1e-9,
        "selected LFG category text must use the readable yellow action color")

    assert(type(hooks.LFGListCategorySelection_UpdateNavButtons) == "function",
        "LFG nav button update hook must be installed")
    hooks.LFGListCategorySelection_UpdateNavButtons(lfgListFrame.CategorySelection)
    assert(buttonRefreshCalls == 4, "nav button update must resync visible enabled/disabled styling")
end

print("OK: instanceframes_lifecycle_test")
