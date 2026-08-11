-- tests/unit/groupframes_ping_template_test.lua
-- Run: lua tests/unit/groupframes_ping_template_test.lua
--
-- GroupFrames must remain ping receivers without addon-writing the Lua
-- `frame.unit` member. Blizzard's unit ping mixin prefers that member over the
-- secure `unit` attribute; an addon-written value taints the GUID passed to the
-- restricted C_PingSecure.SendUnitPing API. SecureGroupHeaderTemplate already
-- owns the clean attribute, so QUI keeps its runtime mirror in weak side state.

local loadstring = loadstring or load

local function readAll(path)
    local file = assert(io.open(path, "rb"))
    local data = file:read("*a")
    file:close()
    return (data:gsub("\r\n", "\n"))
end

local fails = 0
local function check(name, ok, detail)
    if ok then
        print("  ok  " .. name)
    else
        fails = fails + 1
        print("FAIL  " .. name .. (detail and ("  " .. detail) or ""))
    end
end

-------------------------------------------------------------------------------
-- Blizzard contract: pingable frames may resolve their target from the secure
-- unit attribute, and SecureGroupHeaderTemplate owns that attribute.
-------------------------------------------------------------------------------
local pingAttrXml = readAll(
    "tests/framexml/Interface/AddOns/Blizzard_SharedXML/PingAttributes.xml")
check("PingableUnitFrameTemplate is a unit-frame ping receiver",
    pingAttrXml:find(
        '<Frame name="PingableUnitFrameTemplate" mixin="PingableType_UnitFrameMixin" inherits="PingReceiverAttributeTemplate" virtual="true"/>',
        1, true) ~= nil
    and pingAttrXml:find(
        '<Attribute name="ping-receiver" type="boolean" value="true"/>',
        1, true) ~= nil)

local pingTypeLua = readAll(
    "tests/framexml/Interface/AddOns/Blizzard_SharedXML/PingableType.lua")
check("unit ping mixin falls through from self.unit to the unit attribute",
    pingTypeLua:find(
        'guid = UnitGUID(self.unit or self:GetAttribute("unit"))',
        1, true) ~= nil)

local secureHeaders = readAll(
    "tests/framexml/Interface/AddOns/Blizzard_RestrictedAddOnEnvironment/SecureGroupHeaders.lua")
check("secure header passes its child template to CreateFrame",
    secureHeaders:find('local buttonTemplate = self:GetAttribute("template");', 1, true) ~= nil
    and secureHeaders:find(
        'CreateFrame(templateType, name and (name.."UnitButton"..i), self, buttonTemplate)',
        1, true) ~= nil)
check("secure header owns each child unit attribute",
    secureHeaders:find(
        'unitButton:SetAttribute("unit", unitTable[i]);', 1, true) ~= nil)

local pingSecureDocs = readAll(
    "tests/api-docs/blizzard/PingManagerSecureDocumentation.lua")
local sendUnitStart = assert(pingSecureDocs:find('Name = "SendUnitPing"', 1, true))
local sendUnitBlock = pingSecureDocs:sub(sendUnitStart, sendUnitStart + 700)
check("SendUnitPing requires untainted arguments",
    sendUnitBlock:find("HasRestrictions = true", 1, true) ~= nil
    and sendUnitBlock:find(
        'SecretArguments = "AllowedWhenUntainted"', 1, true) ~= nil)

-------------------------------------------------------------------------------
-- All five live GroupFrames header families remain pingable.
-------------------------------------------------------------------------------
local gf = readAll("QUI_GroupFrames/groupframes/groupframes.lua")
local expectSites = {
    { "party header",      'partyHeader:SetAttribute("template", "SecureUnitButtonTemplate,BackdropTemplate,PingableUnitFrameTemplate")' },
    { "raid header",       'raidHeader:SetAttribute("template", "SecureUnitButtonTemplate,BackdropTemplate,PingableUnitFrameTemplate")' },
    { "raid group header", 'groupHeader:SetAttribute("template", "SecureUnitButtonTemplate,BackdropTemplate,PingableUnitFrameTemplate")' },
    { "self header",       'selfHeader:SetAttribute("template", "SecureUnitButtonTemplate,BackdropTemplate,PingableUnitFrameTemplate")' },
    { "spotlight header",  'header:SetAttribute("template", "SecureUnitButtonTemplate,BackdropTemplate,PingableUnitFrameTemplate")' },
}

for _, spec in ipairs(expectSites) do
    check(spec[1] .. " carries PingableUnitFrameTemplate",
        gf:find(spec[2], 1, true) ~= nil)
end

local pingReceiverCount = 0
local pingTemplateLiteral =
    'SetAttribute("template", "SecureUnitButtonTemplate,BackdropTemplate,PingableUnitFrameTemplate")'
local searchAt = 1
while true do
    local hit = gf:find(pingTemplateLiteral, searchAt, true)
    if not hit then break end
    pingReceiverCount = pingReceiverCount + 1
    searchAt = hit + #pingTemplateLiteral
end
check("exactly five GroupFrames header template sites are ping receivers",
    pingReceiverCount == 5, "found " .. pingReceiverCount)

-------------------------------------------------------------------------------
-- QUI's mirror is side state only. Exercise the real accessor bodies and prove
-- they never create the ping-sensitive Lua member on either live or preview
-- objects.
-------------------------------------------------------------------------------
local stateStart = assert(gf:find("function QUI_GF.GetFrameUnit(frame)", 1, true))
local stateEnd = assert(gf:find("\nlocal RAID_SECTION_ROLE_ORDER", stateStart, true))
local stateSource = gf:sub(stateStart, stateEnd - 1)
local stateFactory = assert(loadstring([[
return function()
    local QUI_GF = {}
    local frameState = setmetatable({}, { __mode = "k" })
    local function GetFrameState(frame)
        local state = frameState[frame]
        if not state then state = {}; frameState[frame] = state end
        return state
    end
]] .. stateSource .. [[
    return QUI_GF
end
]], "groupframes unit side-state"))
local sideStateGF = stateFactory()()
local child = setmetatable({}, {
    __newindex = function(t, key, value)
        assert(key ~= "unit", "side-state helper wrote child.unit")
        rawset(t, key, value)
    end,
})
sideStateGF.SetFrameUnit(child, "raid1")
check("side-state mirror returns a live unit without writing child.unit",
    sideStateGF.GetFrameUnit(child) == "raid1" and rawget(child, "unit") == nil)
sideStateGF.SetFrameUnit(child, nil)
check("side-state mirror clears without writing child.unit",
    sideStateGF.GetFrameUnit(child) == nil and rawget(child, "unit") == nil)
local preview = { previewUnit = "player" }
check("preview frames use a separate non-ping field",
    sideStateGF.GetFrameUnit(preview) == "player" and rawget(preview, "unit") == nil)

local rebindStart = assert(gf:find(
    'frame:HookScript("OnAttributeChanged", function(self, key, value)', 1, true))
local rebindEnd = assert(gf:find(
    "\n    local currentUnit = frame:GetAttribute(\"unit\")", rebindStart, true))
local rebind = gf:sub(rebindStart, rebindEnd - 1)
local getOld = rebind:find("local oldUnit = QUI_GF.GetFrameUnit(self)", 1, true)
local setNew = rebind:find("QUI_GF.SetFrameUnit(self, value)", 1, true)
local removeOld = rebind:find("RemoveFrameFromMap(oldUnit, self)", 1, true)
local addNew = rebind:find("AddFrameToMap(value, self)", 1, true)
check("unit rebind updates side state before remapping the child",
    getOld and setNew and removeOld and addNew
    and getOld < setNew and setNew < removeOld and removeOld < addNew)

-------------------------------------------------------------------------------
-- No live child runtime may regress to `.unit` or addon-write the secure unit
-- attribute. Comments are removed before the member-access guard.
-------------------------------------------------------------------------------
local function stripComments(src)
    src = src:gsub("%-%-%[%[.-%]%]", "")
    return (src:gsub("%-%-[^\n]*", ""))
end

local runtimeFiles = {
    "QUI_GroupFrames/groupframes/groupframes.lua",
    "QUI_GroupFrames/groupframes/groupframes_auras.lua",
    "QUI_GroupFrames/groupframes/groupframes_aura_render.lua",
}
for _, path in ipairs(runtimeFiles) do
    local code = stripComments(readAll(path))
    local badAccess
    for _, owner in ipairs({ "frame", "child", "self" }) do
        if code:find("%f[%a_]" .. owner .. "%.unit%f[^%w_]")
            or code:find("%f[%a_]" .. owner .. "%s*%[%s*[\"']unit[\"']%s*%]")
        then
            badAccess = owner .. ".unit"
            break
        end
    end
    check(path .. " has no live child .unit access",
        badAccess == nil, badAccess)
    check(path .. " never addon-writes the child unit attribute",
        code:find('SetAttribute%s*%(%s*["\']unit["\']') == nil)
    check(path .. " does not override Blizzard ping target methods",
        code:find("GetTargetInfo%s*=") == nil
        and code:find("GetIsPingable%s*=") == nil
        and code:find("GetAllowRadialWheel%s*=") == nil)
end

local previewDriver = readAll(
    "QUI_GroupFrames/groupframes/settings/group_frames_preview_driver.lua")
check("preview driver stores previewUnit instead of unit",
    previewDriver:find("f.previewUnit = fakeUnitToken", 1, true) ~= nil
    and previewDriver:find("f.unit = fakeUnitToken", 1, true) == nil)

print(string.format("groupframes_ping_template_test: %d failed", fails))
if fails > 0 then os.exit(1) end
