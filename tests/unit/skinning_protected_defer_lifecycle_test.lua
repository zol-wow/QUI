-- tests/unit/skinning_protected_defer_lifecycle_test.lua
-- Run: lua tests/unit/skinning_protected_defer_lifecycle_test.lua
--
-- Guard the protected-frame defers in ObjectiveTracker and OverrideActionBar.
-- C_Timer.After is only AllowedWhenUntainted in local API docs, so fixed
-- "wait long enough" delays must be replaced by the relevant Blizzard lifecycle
-- plus a named next-frame escape from the protected call stack.

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

local timerDocs = readFile("tests/framexml/Interface/AddOns/Blizzard_APIDocumentationGenerated/UITimerDocumentation.lua")
assertContains(timerDocs, 'Name = "After"', "local API docs must describe C_Timer.After")
assertContains(timerDocs, 'SecretArguments = "AllowedWhenUntainted"',
    "C_Timer.After must be treated as an untainted scheduling API, not a taint escape")

local dirtyMixin = readFile("tests/framexml/Interface/AddOns/Blizzard_SharedXML/MixinUtil.lua")
assertContains(dirtyMixin, "RunNextFrame(self.dirtyCallback);",
    "ObjectiveTracker dirty layout is already a next-frame lifecycle in local FrameXML")

local objectiveFrameXML = readFile("tests/framexml/Interface/AddOns/Blizzard_ObjectiveTracker/Blizzard_ObjectiveTrackerContainer.lua")
assertContains(objectiveFrameXML, "function ObjectiveTrackerContainerMixin:Update(dirtyUpdate)",
    "ObjectiveTracker container Update is the owner lifecycle for post-layout anchoring")
assertContains(objectiveFrameXML, "function ObjectiveTrackerContainerMixin:UpdateHeight()",
    "ObjectiveTracker height is owned by the container lifecycle")

local overrideFrameXML = readFile("tests/framexml/Interface/AddOns/Blizzard_OverrideActionBar/OverrideActionBar.lua")
assertContains(overrideFrameXML, "function OverrideActionBarMixin:UpdateSkin()",
    "OverrideActionBar UpdateSkin is the owner lifecycle before QUI reskins")
assertContains(overrideFrameXML, "self:Setup(C_ActionBar.GetOverrideBarSkin(), C_ActionBar.GetOverrideBarIndex());",
    "OverrideActionBar UpdateSkin must be treated as a Blizzard reset point")

local actionBarController = readFile("tests/framexml/Interface/AddOns/Blizzard_ActionBarController/ActionBarController.lua")
assertContains(actionBarController, "OverrideActionBar:UpdateSkin();",
    "ActionBarController must drive OverrideActionBar through UpdateSkin")
assertContains(actionBarController, "ValidateActionBarTransition();",
    "OverrideActionBar show/animation follows the controller lifecycle")

local objectiveSource = readFile("QUI_Skinning/skinning/gameplay/objectivetracker.lua")
assertAbsent(objectiveSource, "C_Timer.After(0.15",
    "ObjectiveTracker protected post-layout updates must not use a fixed 0.15s delay")
assertContains(objectiveSource, "local function DeferObjectiveTrackerPostLayoutUpdate()",
    "ObjectiveTracker must use a named post-layout defer helper")
assertContains(objectiveSource, "FrameXML DirtiableMixin:MarkDirty uses RunNextFrame",
    "ObjectiveTracker defer helper must document the FrameXML lifecycle reason")

local overrideSource = readFile("QUI_Skinning/skinning/frames/overrideactionbar.lua")
assertAbsent(overrideSource, "C_Timer.After(0.15",
    "OverrideActionBar protected post-update skinning must not use a fixed 0.15s delay")
assertContains(overrideSource, "local function DeferOverrideActionBarPostUpdate()",
    "OverrideActionBar must use a named post-UpdateSkin defer helper")
assertContains(overrideSource, 'hooksecurefunc(bar, "UpdateSkin"',
    "OverrideActionBar must anchor reskinning to Blizzard's UpdateSkin lifecycle")
assertContains(overrideSource, "FrameXML OverrideActionBarMixin:UpdateSkin resets skin, size, actionpage, buttons, and status bars",
    "OverrideActionBar defer helper must document the FrameXML lifecycle reason")
assertAbsent(overrideSource, "if not bar or SkinBase.IsSkinned(bar) then return end",
    "OverrideActionBar UpdateSkin can reset an already-skinned bar, so post-update reskinning must stay idempotent")

print("OK: skinning_protected_defer_lifecycle_test")
