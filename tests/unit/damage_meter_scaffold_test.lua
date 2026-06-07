-- tests/unit/damage_meter_scaffold_test.lua
-- Run: lua tests/unit/damage_meter_scaffold_test.lua

local function readAll(path)
    local file = assert(io.open(path, "rb"))
    local data = file:read("*a")
    file:close()
    -- Normalize CRLF -> LF so source-pattern searches work on Windows.
    data = data:gsub("\r\n", "\n")
    return data
end

-- T1: damage_meter.lua exists and publishes ns.QUI_DamageMeter
local coreSrc = readAll("QUI_DamageMeter/damage_meter/damage_meter.lua")
assert(coreSrc:find("ns.QUI_DamageMeter", 1, true),
    "core must publish ns.QUI_DamageMeter")

-- T1: QUI_DamageMeter.toc registers the module file
local tocSrc = readAll("QUI_DamageMeter/QUI_DamageMeter.toc")
assert(tocSrc:find("damage_meter\\damage_meter.lua", 1, true),
    "QUI_DamageMeter.toc must load damage_meter/damage_meter.lua")

-- T2: section markers + skeleton declarations
for _, marker in ipairs({
    "-- ==== Settings ====",
    "-- ==== Data ====",
    "-- ==== WindowManager ====",
    "-- ==== Window ====",
    "-- ==== Formatters ====",
    "-- ==== Init ====",
}) do
    assert(coreSrc:find(marker, 1, true),
        "core must include section marker " .. marker)
end

-- T2: stub function declarations exist on QUI_DamageMeter and on internal tables
for _, decl in ipairs({
    "local Data = {}",
    "local WindowManager = {",
    "local Window = {}",
}) do
    assert(coreSrc:find(decl, 1, true),
        "core must declare " .. decl)
end

-- T3: native settings block exists in defaults.lua
local defaultsSrc = readAll("core/defaults.lua")
assert(defaultsSrc:find("native = {", 1, true),
    "defaults must declare damageMeter.native = {...}")
for _, key in ipairs({
    "enabled",
    "visibility",
    "refreshRateCombat",
    "refreshRateIdle",
    "appearance",
    "windows",
    "windowCount",
}) do
    -- Loose pattern: key followed by `=` on the same line, somewhere in the
    -- native block. (Skinner block also has `enabled =` — that's fine, this
    -- just asserts the key exists at least once in the file.)
    assert(defaultsSrc:find(key .. "%s*=", 1, false),
        "defaults must include damageMeter.native." .. key)
end

-- T4: event subscriptions
for _, ev in ipairs({
    "DAMAGE_METER_COMBAT_SESSION_UPDATED",
    "DAMAGE_METER_CURRENT_SESSION_UPDATED",
    "DAMAGE_METER_RESET",
    "PLAYER_REGEN_DISABLED",
    "PLAYER_REGEN_ENABLED",
}) do
    assert(coreSrc:find('RegisterEvent("' .. ev .. '"', 1, true),
        "Data must RegisterEvent " .. ev)
end

-- T4: handlers must NOT call C_DamageMeter inline (only mark dirty)
-- Extract the OnEvent handler to check it specifically (T6/T7 use C_DamageMeter in separate functions)
local handlerMatch = coreSrc:match('SetScript%("OnEvent",%s*function%([^)]*%)(.-)end%)')
if handlerMatch then
    local _, ndmCalls = handlerMatch:gsub("C_DamageMeter%.", "")
    assert(ndmCalls == 0,
        "T4 event handler must not call C_DamageMeter — deferred pulls land in T6")
end

-- T4: dirty table exists
assert(coreSrc:find("Data._dirty", 1, true) or coreSrc:find("Data%.dirty", 1, false),
    "Data must maintain a dirty-flags table")

-- T5: ticker frame + OnUpdate + cadence read from settings
assert(coreSrc:find("Data._ticker", 1, true),
    "Data must hold a ticker frame")
assert(coreSrc:find('Data._ticker:SetScript("OnUpdate"', 1, true)
    or coreSrc:find("Data._ticker:SetScript(\"OnUpdate\"", 1, true),
    "Data._ticker must wire OnUpdate")
assert(coreSrc:find("refreshRateCombat", 1, true),
    "ticker must read refreshRateCombat from settings")
assert(coreSrc:find("refreshRateIdle", 1, true),
    "ticker must read refreshRateIdle from settings")
assert(coreSrc:find("function Data:Refresh", 1, true)
    or coreSrc:find("Data.Refresh = function", 1, true),
    "Data:Refresh must be defined")

-- T7: Data:GetView + cache + generation
assert(coreSrc:find("function Data:GetView", 1, true)
    or coreSrc:find("Data.GetView = function", 1, true),
    "Data:GetView must be defined")
assert(coreSrc:find("Data._cache", 1, true),
    "Data must maintain a view cache")
assert(coreSrc:find("C_DamageMeter%.GetCombatSessionFromType", 1, false),
    "Data:Refresh must call C_DamageMeter.GetCombatSessionFromType")
assert(coreSrc:find("generation", 1, true),
    "view must carry a generation counter")

-- T8: WindowManager surface
for _, fn in ipairs({"Spawn", "Despawn", "Enumerate", "Get"}) do
    assert(coreSrc:find("function WindowManager:" .. fn, 1, true)
        or coreSrc:find("WindowManager." .. fn .. " = function", 1, true),
        "WindowManager:" .. fn .. " must be defined")
end

-- T9: Window.New + frame composition (static factory — dot, not colon)
assert(coreSrc:find("function Window.New", 1, true)
    or coreSrc:find("function Window:New", 1, true)
    or coreSrc:find("Window.New = function", 1, true),
    "Window.New must be defined")
for _, name in ipairs({"frame", "backdrop", "header", "TypeLabel", "SessionTimer",
                       "ConfigButton", "CloseButton"}) do
    assert(coreSrc:find(name, 1, true),
        "Window must reference " .. name)
end
assert(coreSrc:find('"QUI_DamageMeterWindow"', 1, true)
    or coreSrc:find("QUI_DamageMeterWindow", 1, true),
    "frame must be named with QUI_DamageMeterWindow prefix")

-- T10: row template + pool
assert(coreSrc:find("BAR_POOL_SIZE", 1, true),
    "row pool size constant must exist")
assert(coreSrc:find("function Window:_BuildRow", 1, true)
    or coreSrc:find("Window._BuildRow = function", 1, true),
    "Window:_BuildRow must be defined")
for _, child in ipairs({"Icon", "Bar", "Name", "Value"}) do
    -- Each row child must be referenced in the row constructor.
    assert(coreSrc:find('row%.' .. child .. '%s*=', 1, false),
        "row must define field " .. child)
end
assert(coreSrc:find('"Interface\\\\Buttons\\\\WHITE8X8"', 1, true)
    or coreSrc:find("WHITE8X8", 1, true),
    "row bar must use WHITE8x8 texture path")

-- T11: row source-binding method
assert(coreSrc:find("function Window:_SetRowSource", 1, true)
    or coreSrc:find("Window._SetRowSource = function", 1, true),
    "Window:_SetRowSource must be defined")
assert(coreSrc:find("RAID_CLASS_COLORS", 1, true),
    "row must look up class color via RAID_CLASS_COLORS")
assert(coreSrc:find('"Interface\\\\Icons\\\\INV_Misc_QuestionMark"', 1, true)
    or coreSrc:find("INV_Misc_QuestionMark", 1, true),
    "row must have a fallback icon path")

-- T12: Window:Refresh + Data._onChange fan-out
assert(coreSrc:find("function Window:Refresh", 1, true)
    or coreSrc:find("Window.Refresh = function", 1, true),
    "Window:Refresh must be defined")
assert(coreSrc:find("Data._onChange", 1, true),
    "Data._onChange must be set so refreshes fan out to windows")
assert(coreSrc:find("_lastGeneration", 1, true),
    "Window:Refresh must compare _lastGeneration to skip no-op repaints")

-- T13: Layout Mode + anchor registry registration
assert(coreSrc:find("ns%.QUI_LayoutMode", 1, false),
    "must reference ns.QUI_LayoutMode")
assert(coreSrc:find("RegisterElement", 1, true),
    "must call Layout Mode RegisterElement")
assert(coreSrc:find("QUI_RegisterFrameResolver", 1, true),
    "must call _G.QUI_RegisterFrameResolver")
assert(coreSrc:find('"damageMeter_window_"', 1, true)
    or coreSrc:find("damageMeter_window_", 1, true),
    "layout key prefix must be damageMeter_window_")

-- T14: Blizzard meter suppression
assert(coreSrc:find('SetCVar%("damageMeterEnabled"', 1, false),
    "must SetCVar damageMeterEnabled")
assert(coreSrc:find("_G%.DamageMeter", 1, false)
    or coreSrc:find("_G.DamageMeter", 1, true),
    "must reference _G.DamageMeter to Hide it")
assert(coreSrc:find('PLAYER_LOGIN', 1, true),
    "must register PLAYER_LOGIN")

-- T15: format helpers + lockdown queue
assert(coreSrc:find("local function FormatDuration", 1, true),
    "FormatDuration must be defined")
assert(coreSrc:find("local function FormatNumber", 1, true),
    "FormatNumber must be defined")
assert(coreSrc:find("InCombatLockdown", 1, true),
    "lockdown queue must consult InCombatLockdown")
assert(coreSrc:find("pendingCombatWrites", 1, true),
    "lockdown queue must use pendingCombatWrites")

-- T16 / Phase 3: PLAYER_LOGIN handler spawns saved windows via LoadSavedWindows.
-- (Phase 1 used WindowManager:Spawn(1) directly; Phase 3 generalized to N windows.)
assert(coreSrc:find("WindowManager:LoadSavedWindows", 1, true)
    or coreSrc:find("WindowManager:Spawn(1)", 1, true),
    "PLAYER_LOGIN handler must spawn savedvars windows")

-- T1 (Phase 2): textures + fonts schema blocks and array-form colors
for _, key in ipairs({
    "textures",
    "fonts",
}) do
    assert(defaultsSrc:find(key .. "%s*=%s*{", 1, false),
        "defaults must include damageMeter.native.appearance.global." .. key .. " = {")
end
-- Color arrays use the array-style `{r,g,b,a}` shape after T1.
assert(defaultsSrc:find("bg%s*=%s*{%s*0%s*,%s*0%s*,%s*0%s*,%s*0%.85%s*}", 1, false),
    "colors.bg must be array form { 0, 0, 0, 0.85 }")

-- T2 (Phase 2): WindowManager:RefreshAll exists and unconditionally re-renders
assert(coreSrc:find("function WindowManager:RefreshAll", 1, true)
    or coreSrc:find("WindowManager.RefreshAll = function", 1, true),
    "WindowManager:RefreshAll must be defined")

-- T4 (Phase 2): TYPE_LABELS table covers DamageDone..Deaths
for _, label in ipairs({
    '"Damage Done"',
    '"Healing Done"',
    '"Damage Taken"',
    '"Interrupts"',
    '"Dispels"',
    '"Deaths"',
}) do
    assert(coreSrc:find(label, 1, true),
        "TYPE_LABELS must contain " .. label)
end
assert(coreSrc:find("function Window:_ApplyHeader", 1, true)
    or coreSrc:find("Window._ApplyHeader = function", 1, true),
    "Window:_ApplyHeader must be defined")

-- T5 (Phase 2): ConfigButton wires MenuUtil.CreateContextMenu with type radios
assert(coreSrc:find("MenuUtil.CreateContextMenu", 1, true),
    "ConfigButton must wire MenuUtil.CreateContextMenu")
assert(coreSrc:find('root:CreateTitle("Meter Type")', 1, true),
    "menu must title the Type section")
assert(coreSrc:find("function Window:_OpenConfigMenu", 1, true)
    or coreSrc:find("Window._OpenConfigMenu = function", 1, true),
    "Window:_OpenConfigMenu must be defined")
-- METER_TYPES is built dynamically from Enum.DamageMeterType names (no
-- hardcoded integers — see TYPE_LABEL_NAMES comment in damage_meter.lua).
assert(coreSrc:find("local METER_TYPES = {}", 1, true),
    "METER_TYPES must be initialized empty (populated from Enum at load)")
assert(coreSrc:find('"AvoidableDamageTaken"', 1, true)
    and coreSrc:find('"EnemyDamageTaken"', 1, true),
    "METER_TYPES order list must include AvoidableDamageTaken + EnemyDamageTaken")
assert(coreSrc:find("root:CreateRadio", 1, true),
    "menu must call root:CreateRadio (looped over METER_TYPES)")

-- T6 (Phase 2): Session subsection in the config menu
assert(coreSrc:find('root:CreateTitle("Session")', 1, true),
    "menu must title the Session section")
assert(coreSrc:find('label%s*=%s*"Current"', 1, false)
    or coreSrc:find('"Current"', 1, true),
    "menu must label Current session")
assert(coreSrc:find('"Overall"', 1, true),
    "menu must label Overall session")
assert(coreSrc:find("root:CreateDivider", 1, true),
    "menu must use a CreateDivider between Type and Session sections")

-- T7 (Phase 2): LSM bar texture resolution
assert(coreSrc:find("ns%.LSM", 1, false)
    or coreSrc:find("ns.LSM", 1, true),
    "must reference ns.LSM to resolve bar textures")
assert(coreSrc:find('LSM:Fetch%("statusbar"', 1, false)
    or coreSrc:find('LSM:Fetch("statusbar"', 1, true),
    "must call LSM:Fetch(\"statusbar\", name)")
assert(coreSrc:find("local function ResolveBarTexture", 1, true),
    "ResolveBarTexture helper must be defined")

-- T8 (Phase 2): font resolution and ApplyFonts hook
assert(coreSrc:find('LSM:Fetch%("font"', 1, false)
    or coreSrc:find('LSM:Fetch("font"', 1, true),
    "must call LSM:Fetch(\"font\", name) for font resolution")
assert(coreSrc:find("function Window:_ApplyFonts", 1, true)
    or coreSrc:find("Window._ApplyFonts = function", 1, true),
    "Window:_ApplyFonts must be defined")
assert(coreSrc:find("local function ResolveFontSlot", 1, true),
    "ResolveFontSlot helper must be defined")

-- T9 (Phase 2): color application helper + barColorAccent + per-row colors
assert(coreSrc:find("function Window:_ApplyColors", 1, true)
    or coreSrc:find("Window._ApplyColors = function", 1, true),
    "Window:_ApplyColors must be defined")
assert(coreSrc:find("barColorAccent", 1, true),
    "must read barColorAccent for bar fill")
assert(coreSrc:find("headerText", 1, true),
    "must read colors.headerText for header text color")
assert(coreSrc:find("GetAddonAccentColor", 1, true),
    "must look up accent via QUI:GetAddonAccentColor")

-- T10 (Phase 2): hover tooltip
assert(coreSrc:find("GameTooltip:SetOwner", 1, true),
    "row OnEnter must call GameTooltip:SetOwner")
assert(coreSrc:find("GameTooltip:Hide", 1, true),
    "row OnLeave must call GameTooltip:Hide")
assert(coreSrc:find("showHoverTooltip", 1, true),
    "tooltip wiring must consult showHoverTooltip setting")

-- T11 (Phase 2): pinned-self helper + Refresh integration
assert(coreSrc:find("local function FindLocalPlayerInSources", 1, true),
    "FindLocalPlayerInSources helper must be defined")
assert(coreSrc:find("showPinnedSelf", 1, true),
    "Window:Refresh must consult showPinnedSelf setting")

print("OK: damage_meter_scaffold_test (Phases 1-7 complete)")
