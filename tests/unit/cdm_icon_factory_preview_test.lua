-- tests/unit/cdm_icon_factory_preview_test.lua
-- Run: lua tests/unit/cdm_icon_factory_preview_test.lua

local function readAll(path)
    local file = assert(io.open(path, "rb"))
    local data = file:read("*a")
    file:close()
    -- Normalize CRLF -> LF so source-pattern searches work on Windows.
    data = data:gsub("\r\n", "\n")
    return data
end

local source = readAll("modules/cdm/cdm_icon_renderer.lua")

-- T1: bare construction helper must exist and be separate from CreateIcon
local bareStart = assert(source:find("local function CreateIconBare(parent, spellEntry)", 1, true),
    "CreateIconBare must exist as a local function in cdm_icon_renderer.lua")
local createIconStart = assert(source:find("local function CreateIcon(parent, spellEntry)", 1, true),
    "CreateIcon must still exist as a local function")
assert(bareStart < createIconStart,
    "CreateIconBare must be defined before CreateIcon so CreateIcon can call it")

-- T1: CreateIcon must delegate construction to CreateIconBare
local createIconEnd = assert(source:find("\nend\n", createIconStart, true),
    "CreateIcon must terminate with end")
local delegation = source:find("CreateIconBare(parent, spellEntry)", createIconStart, true)
assert(delegation and delegation < createIconEnd,
    "CreateIcon must call CreateIconBare(parent, spellEntry) to build the frame tree")

-- T1: runtime hooks must remain INSIDE CreateIcon, not in CreateIconBare
local bareEnd = assert(source:find("\nend\n", bareStart, true),
    "CreateIconBare must terminate with end")
local hookInsideBare = source:find("OnFactoryIconCreated", bareStart, true)
assert(not hookInsideBare or hookInsideBare > bareEnd,
    "CreateIconBare must NOT call OnFactoryIconCreated (runtime-only hook)")
local mouseoverInsideBare = source:find("HookFrameForMouseover", bareStart, true)
assert(not mouseoverInsideBare or mouseoverInsideBare > bareEnd,
    "CreateIconBare must NOT call HookFrameForMouseover (runtime-only hook)")
local tooltipScriptInsideBare = source:find('SetScript("OnEnter"', bareStart, true)
assert(not tooltipScriptInsideBare or tooltipScriptInsideBare > bareEnd,
    "CreateIconBare must NOT install the tooltip OnEnter script (runtime-only hook)")
local onLeaveScriptInsideBare = source:find('SetScript("OnLeave"', bareStart, true)
assert(not onLeaveScriptInsideBare or onLeaveScriptInsideBare > bareEnd,
    "CreateIconBare must NOT install the tooltip OnLeave script (runtime-only hook)")

-- T1: CreateIcon must still install the runtime hooks
local hookInsideCreateIcon = source:find("OnFactoryIconCreated", createIconStart, true)
assert(hookInsideCreateIcon and hookInsideCreateIcon < createIconEnd,
    "CreateIcon must still call OnFactoryIconCreated after extraction")
local mouseoverInsideCreateIcon = source:find("HookFrameForMouseover", createIconStart, true)
assert(mouseoverInsideCreateIcon and mouseoverInsideCreateIcon < createIconEnd,
    "CreateIcon must still call HookFrameForMouseover after extraction")

-- T2: AcquireForPreview must exist on the CDMIconFactory table
assert(source:find("function CDMIconFactory.AcquireForPreview", 1, true)
    or source:find("CDMIconFactory.AcquireForPreview = function", 1, true),
    "CDMIconFactory.AcquireForPreview must be defined")

-- T2: AcquireForPreview must call CreateIconBare and skip runtime hooks
local acqStart = assert(
    source:find("function CDMIconFactory.AcquireForPreview", 1, true)
        or source:find("CDMIconFactory.AcquireForPreview = function", 1, true),
    "AcquireForPreview definition not located")
local acqEnd = assert(source:find("\nend\n", acqStart, true),
    "AcquireForPreview must terminate with end")
assert(source:find("CreateIconBare(parent, spellEntry)", acqStart, true) and
       source:find("CreateIconBare(parent, spellEntry)", acqStart, true) < acqEnd,
    "AcquireForPreview must construct via CreateIconBare")
do
    local tryBind = source:find("TryBindIconToBlizz", acqStart, true)
    assert(not tryBind or tryBind > acqEnd,
        "AcquireForPreview must NOT call TryBindIconToBlizz (mirror taint surface)")
end
do
    local onAcquired = source:find("OnFactoryIconAcquired", acqStart, true)
    assert(not onAcquired or onAcquired > acqEnd,
        "AcquireForPreview must NOT call OnFactoryIconAcquired")
end
do
    local onIconAssigned = source:find("_onIconAssigned", acqStart, true)
    assert(not onIconAssigned or onIconAssigned > acqEnd,
        "AcquireForPreview must NOT call _onIconAssigned (rotation-helper hook)")
end

-- T2: AcquireForPreview must mark the icon as preview-scoped
assert(source:find("icon._isPreview = true", acqStart, true) and
       source:find("icon._isPreview = true", acqStart, true) < acqEnd,
    "AcquireForPreview must set icon._isPreview = true for downstream guards")

-- T2: ReleaseForPreview must exist and clear visual state without pooling
assert(source:find("function CDMIconFactory.ReleaseForPreview", 1, true)
    or source:find("CDMIconFactory.ReleaseForPreview = function", 1, true),
    "CDMIconFactory.ReleaseForPreview must be defined")

local relStart = assert(
    source:find("function CDMIconFactory.ReleaseForPreview", 1, true)
        or source:find("CDMIconFactory.ReleaseForPreview = function", 1, true),
    "ReleaseForPreview definition not located")
local relEnd = assert(source:find("\nend\n", relStart, true),
    "ReleaseForPreview must terminate with end")
assert(source:find("icon:Hide()", relStart, true) and
       source:find("icon:Hide()", relStart, true) < relEnd,
    "ReleaseForPreview must hide the icon")
assert(source:find("icon.Cooldown:Clear()", relStart, true) and
       source:find("icon.Cooldown:Clear()", relStart, true) < relEnd,
    "ReleaseForPreview must clear any active cooldown swipe")
do
    local recycleInsert = source:find("table.insert(recyclePool", relStart, true)
    assert(not recycleInsert or recycleInsert > relEnd,
        "ReleaseForPreview must NOT return preview icons to the runtime recyclePool")
end

print("OK: cdm_icon_factory_preview_test (T1 + T2 portions)")
