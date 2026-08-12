-- tests/unit/actionbars_ping_receiver_test.lua
-- Run: lua tests/unit/actionbars_ping_receiver_test.lua

local function readAll(path)
    local file = assert(io.open(path, "rb"))
    local data = file:read("*a")
    file:close()
    return (data:gsub("\r\n", "\n"))
end

local fails = 0
local function check(name, ok)
    if ok then
        print("  ok  " .. name)
    else
        fails = fails + 1
        print("FAIL  " .. name)
    end
end

local xml = readAll(
    "tests/framexml/Interface/AddOns/Blizzard_ActionBar/Mainline/ActionButtonTemplate.xml")
local framexml = readAll(
    "tests/framexml/Interface/AddOns/Blizzard_ActionBar/Shared/ActionButton.lua")
local pingable = readAll(
    "tests/framexml/Interface/AddOns/Blizzard_SharedXML/PingableType.lua")
local pingDocs = readAll(
    "tests/api-docs/blizzard/PingManagerSecureDocumentation.lua")
local builder = readAll("QUI_ActionBars/actionbars/actionbars_builder.lua")
local actionbars = readAll("QUI_ActionBars/actionbars/actionbars.lua")

check("Blizzard's supported ActionBarButtonTemplate composes visual and code templates",
    xml:find(
        '<CheckButton name="ActionBarButtonTemplate" inherits="ActionButtonTemplate, ActionBarButtonCodeTemplate"',
        1, true) ~= nil)
check("ActionBarButtonCodeTemplate installs ActionBarActionButtonDerivedMixin",
    xml:find(
        '<CheckButton name="ActionBarButtonCodeTemplate" inherits="SecureActionButtonTemplate, QuickKeybindButtonTemplate, ActionButtonSpellFXTemplate" virtual="true" mixin="ActionBarActionButtonDerivedMixin">',
        1, true) ~= nil)

check("Blizzard UpdateAction owns self.action and refreshes ping attributes",
    framexml:find("function ActionBarActionButtonMixin:UpdateAction(force)", 1, true) ~= nil
        and framexml:find("self.action = action;", 1, true) ~= nil
        and framexml:find("self:UpdatePingAttributes();", 1, true) ~= nil)
check("Blizzard action-button ping identity reads the Blizzard-owned action",
    framexml:find("function ActionBarActionButtonMixin:HasAction()\n\treturn C_ActionBar.HasAction(self.action);\nend", 1, true) ~= nil
        and framexml:find("function ActionBarActionButtonMixin:GetActionButtonInfo()", 1, true) ~= nil
        and framexml:find("local actionType, id, subType = GetActionInfo(self.action);", 1, true) ~= nil)
check("Pingable action buttons use HasAction and GetActionButtonInfo",
    pingable:find("if self:HasAction() then", 1, true) ~= nil
        and pingable:find("local actionButtonInfo = self:GetActionButtonInfo();", 1, true) ~= nil)
check("spell ping is SecureOnly and AllowedWhenUntainted",
    pingDocs:find('Environment = "SecureOnly"', 1, true) ~= nil
        and pingDocs:find('Name = "SendPlayerSpellPing"', 1, true) ~= nil
        and pingDocs:find('SecretArguments = "AllowedWhenUntainted"', 1, true) ~= nil)

check("QUI owned buttons keep Blizzard's ActionBarButtonTemplate and append SecureActionButtonTemplate so useOnKeyDown survives",
    builder:find(
        'CreateFrame, "CheckButton", btnName, container, "ActionBarButtonTemplate, SecureActionButtonTemplate"',
        1, true) ~= nil)
check("QUI does not replace Blizzard's ping identity or update lifecycle",
    builder:find("btn.HasAction =", 1, true) == nil
        and builder:find("btn.GetActionButtonInfo =", 1, true) == nil
        and builder:find("btn.UpdateAction =", 1, true) == nil
        and builder:find("btn.Update =", 1, true) == nil
        and builder:find("btn.UpdatePressAndHoldAction =", 1, true) == nil)
check("QUI never assigns the action identity directly",
    builder:find("btn.action =", 1, true) == nil
        and actionbars:find("self.action = action", 1, true) == nil)
check("paged actions change through a restricted action attribute",
    builder:find('btn:SetAttribute("_childupdate-offset", [[', 1, true) ~= nil
        and builder:find('self:SetAttribute("action", newAction)', 1, true) ~= nil
        and builder:find('self:CallMethod("SafeSyncAction")', 1, true) == nil)
check("initial actions are seeded through SecureHandler Execute",
    builder:find("container:Execute(string.format([[", 1, true) ~= nil
        and builder:find('btn:SetAttribute("action", %d)', 1, true) ~= nil)
check("obsolete Lua-side SafeSyncAction no longer exists",
    actionbars:find("function ActionBarsOwned.SafeSyncAction", 1, true) == nil)

print(string.format("actionbars_ping_receiver_test: checks complete, %d failed", fails))
if fails > 0 then os.exit(1) end
print("OK: actionbars_ping_receiver_test")
