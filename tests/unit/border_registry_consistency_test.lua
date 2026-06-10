-- Static-analysis guard for the centralized border-coloring registry.
--
-- The headless harness (tools/_addon_env.lua LoadCore) loads only core files,
-- NOT modules, so ns.Helpers.BorderRegistry is EMPTY at runtime here. We cannot
-- introspect the live registry; instead we statically scan every module .lua for
-- BorderRegistry.Register({...}) calls and assert:
--   1. The exact expected set of registered keys is present (no more, no fewer).
--   2. No key is registered twice (across all files).
--   3. Every Register block declares both `db` and `refresh`.
-- It also prints (informational, non-fatal) every no-argument
-- GetSkinBorderColor() call site still present in modules/, for human review:
-- some are legitimately global (character pane, minimap menu/drawer, resource
-- bars, group frames) but a per-module surface that should pass (table, prefix)
-- and doesn't would show up here.
--
-- Plain Lua 5.1, file-driven (no harness): read repo files with io.open and
-- match with patterns.
--
-- Run from repo root: lua tests/unit/border_registry_consistency_test.lua

local failures = 0
local function check(name, ok, detail)
    if ok then
        print(("  ok  %s"):format(name))
    else
        failures = failures + 1
        print(("FAIL  %s  %s"):format(name, detail or ""))
    end
end

-- The 21 "remaining" converted modules plus minimap, the native damage meter,
-- and chat-tab chrome == 24 keys, plus the CDM Buff Icons/Bars (aura/auraBar)
-- container border entry == 25 keys.
local EXPECTED_KEYS = {
    "minimap", "buttonDrawer", "datatext", "crosshair", "castbar", "castbarIcon",
    "portrait", "skyriding", "xpTracker", "preyTracker", "atonement",
    "combatTimer", "brezCounter", "actionTracker", "actionTrackerIcon",
    "rotationAssist", "cdmContainers", "cdmBuffContainers", "mplusTimer",
    "readyCheck", "alerts", "chat", "tooltip", "damageMeter",
}
local expectedLookup = {}
for _, k in ipairs(EXPECTED_KEYS) do expectedLookup[k] = true end

-- Enumerate module .lua files. Prefer `find`; fall back to a hard-coded list of
-- the files known to Register (kept in sync with grep) if `find` is unavailable.
local function listModuleLuaFiles()
    local files = {}
    local p = io.popen and io.popen("find QUI_ActionBars QUI_CDM QUI_Chat QUI_DamageMeter QUI_GroupFrames QUI_Minimap QUI_QoL QUI_ResourceBars QUI_Skinning QUI_UnitFrames modules/layout modules/ui modules/integrations -name '*.lua' -type f 2>/dev/null")
    if p then
        for line in p:lines() do
            files[#files + 1] = line
        end
        p:close()
    end
    if #files > 0 then return files end
    -- Fallback: the files known to host Register calls.
    return {
        "QUI_CDM/cdm/cdm_container_border_registry.lua",
        "QUI_Chat/chat/chat.lua",
        "QUI_QoL/combat/rotationassist.lua",
        "QUI_DamageMeter/damage_meter/damage_meter.lua",
        "QUI_QoL/dungeon/brez_counter.lua",
        "QUI_Minimap/minimap/datapanels.lua",
        "QUI_Minimap/minimap/minimap.lua",
        "QUI_QoL/qol/actiontracker.lua",
        "QUI_QoL/qol/combattimer.lua",
        "QUI_QoL/qol/crosshair.lua",
        "QUI_QoL/qol/skyriding.lua",
        "QUI_QoL/qol/xptracker.lua",
        "QUI_Skinning/skinning/gameplay/mplus_timer.lua",
        "QUI_Skinning/skinning/notifications/alerts.lua",
        "QUI_Skinning/skinning/notifications/readycheck.lua",
        "QUI_Skinning/skinning/system/tooltips.lua",
        "QUI_QoL/trackers/atonement_counter.lua",
        "QUI_QoL/trackers/preytracker.lua",
        "QUI_UnitFrames/unitframes/unitframes.lua",
    }
end

local function readFile(path)
    local fh = io.open(path, "r")
    if not fh then return nil end
    local data = fh:read("*a")
    fh:close()
    return data
end

local function assertBorderColoringRefreshBroadcast()
    local src = assert(readFile("QUI_Skinning/skinning/settings/border_coloring_content.lua"),
        "cannot open border coloring settings file")

    local refreshPos = src:find("local function RefreshBorderColoring", 1, true)
    check("border coloring page centralizes refresh callback", refreshPos ~= nil)
    if not refreshPos then return end

    local nextFn = src:find("\nlocal function ", refreshPos + 1, true)
    local body = src:sub(refreshPos, (nextFn or #src + 1) - 1)
    check("border coloring refresh repaints border registry",
        body:find("Helpers.RefreshAllBorders", 1, true) ~= nil)
    check("border coloring refresh broadcasts skinning group",
        body:find('RefreshAll("skinning")', 1, true) ~= nil)
    check("border coloring controls avoid narrow refresh callback",
        not src:find("function%(%) Helpers%.RefreshAllBorders%(%) end"))
end

-- Extract each BorderRegistry.Register({ ... }) block as raw text. A block runs
-- from the line containing "Register({" up to the first line that is exactly a
-- closing "})" at the same or lesser indentation (the Register's own closer).
-- Register blocks here are hand-written with the closing "})" on its own line,
-- so we collect lines until we hit a line whose trimmed content is "})".
local function extractRegisterBlocks(text)
    local blocks = {}
    local lines = {}
    for line in (text .. "\n"):gmatch("([^\n]*)\n") do
        lines[#lines + 1] = line
    end
    local i = 1
    while i <= #lines do
        if lines[i]:match("BorderRegistry%.Register%(%s*{") then
            local buf = { lines[i] }
            local j = i + 1
            while j <= #lines do
                buf[#buf + 1] = lines[j]
                -- closing line: trimmed == "})" (possibly with trailing comment)
                local trimmed = lines[j]:gsub("^%s+", "")
                if trimmed:match("^}%)") then
                    break
                end
                j = j + 1
            end
            blocks[#blocks + 1] = { text = table.concat(buf, "\n"), line = i }
            i = j + 1
        else
            i = i + 1
        end
    end
    return blocks
end

local registered = {}          -- key -> { file, line }
local duplicates = {}          -- list of "key (fileA, fileB)"
local blocksMissingDb = {}     -- list of "file:line key"
local blocksMissingRefresh = {}
local noArgCallSites = {}      -- informational

for _, path in ipairs(listModuleLuaFiles()) do
    local text = readFile(path)
    if text then
        -- Register blocks.
        for _, block in ipairs(extractRegisterBlocks(text)) do
            local key = block.text:match("key%s*=%s*\"([%w_]+)\"")
            if key then
                if registered[key] then
                    duplicates[#duplicates + 1] = ("%s (%s and %s)"):format(
                        key, registered[key].file, path)
                else
                    registered[key] = { file = path, line = block.line }
                end
                if not block.text:match("[%s,{]db%s*=") then
                    blocksMissingDb[#blocksMissingDb + 1] = ("%s key=%s"):format(path, key)
                end
                if not block.text:match("[%s,{]refresh%s*=") then
                    blocksMissingRefresh[#blocksMissingRefresh + 1] = ("%s key=%s"):format(path, key)
                end
            else
                check("Register block has a key", false,
                      ("%s near line %d: no key=\"...\" found"):format(path, block.line))
            end
        end

        -- Informational: no-arg GetSkinBorderColor() call sites.
        local lineNo = 0
        for line in (text .. "\n"):gmatch("([^\n]*)\n") do
            lineNo = lineNo + 1
            if line:match("GetSkinBorderColor%(%s*%)") then
                noArgCallSites[#noArgCallSites + 1] =
                    ("%s:%d  %s"):format(path, lineNo, (line:gsub("^%s+", "")))
            end
        end
    end
end

-- 1. Exact expected set: present, no missing, no extra.
local missing, extra = {}, {}
for _, k in ipairs(EXPECTED_KEYS) do
    if not registered[k] then missing[#missing + 1] = k end
end
local registeredKeys = {}
for k in pairs(registered) do
    registeredKeys[#registeredKeys + 1] = k
    if not expectedLookup[k] then extra[#extra + 1] = k end
end
table.sort(registeredKeys)
table.sort(missing)
table.sort(extra)

print(("  --  found %d registered keys: %s"):format(#registeredKeys, table.concat(registeredKeys, ", ")))

check("no missing keys", #missing == 0,
      #missing > 0 and ("missing: " .. table.concat(missing, ", ")) or nil)
check("no unexpected keys", #extra == 0,
      #extra > 0 and ("unexpected: " .. table.concat(extra, ", ")
                      .. " -- a real finding: a new key was registered but not added to EXPECTED_KEYS")
                  or nil)
check(("exactly %d keys registered"):format(#EXPECTED_KEYS),
      #registeredKeys == #EXPECTED_KEYS,
      ("expected %d, found %d"):format(#EXPECTED_KEYS, #registeredKeys))

-- 2. No duplicates.
check("no duplicate keys across files", #duplicates == 0,
      #duplicates > 0 and table.concat(duplicates, "; ") or nil)

-- 3. Every block has db and refresh.
check("every Register block declares db", #blocksMissingDb == 0,
      #blocksMissingDb > 0 and table.concat(blocksMissingDb, "; ") or nil)
check("every Register block declares refresh", #blocksMissingRefresh == 0,
      #blocksMissingRefresh > 0 and table.concat(blocksMissingRefresh, "; ") or nil)

assertBorderColoringRefreshBroadcast()

-- Informational dump of no-arg call sites (NOT a failure).
print(("\n-- informational: %d no-arg GetSkinBorderColor() call site(s) (human review):")
      :format(#noArgCallSites))
table.sort(noArgCallSites)
for _, site in ipairs(noArgCallSites) do
    print("     " .. site)
end

print(("\n%d failure(s)"):format(failures))
os.exit(failures == 0 and 0 or 1)
