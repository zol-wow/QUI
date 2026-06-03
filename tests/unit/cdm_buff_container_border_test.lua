-- tests/unit/cdm_buff_container_border_test.lua
-- Verifies that the CDM Buff Icons (aura) and Buff Bars (auraBar) containers are
-- wired into the per-container border-color inheritance model the same way the
-- Essential/Utility cooldown rows are:
--   1. Defaults: the flat buff/trackedBar tables (top-level + unified mirror)
--      carry borderColorSource = "inherit" + a borderColor table.
--   2. Registry: a dedicated "cdmBuffContainers" multi entry collects those flat
--      tables, declares db/refresh/instances, and opts the migration into a
--      defaultSource of "inherit" (NOT "custom", which is correct only for the
--      icon-row containers that had a legacy per-row color).
--   3. Renderer: cdm_bar_renderer resolves the bar border via the per-container
--      settings (GetSkinBorderColor(settings, "")), not the no-arg global form,
--      and re-resolves per bar on a live skin-color refresh.
--   4. Options: the aura + auraBar layout sections attach a border-source control.
--   5. Buff icons forward the per-container source into their rowConfig.
--
-- Run from repo root: lua tests/unit/cdm_buff_container_border_test.lua

local env = dofile("tools/_addon_env.lua")
local ns = env.LoadCore()
local Helpers = ns.Helpers
local BorderRegistry = Helpers.BorderRegistry

-- Register the REAL CDM container border entries against the core registry.
env.LoadAddonFile("modules/cdm/cdm_container_border_registry.lua", "QUI", ns)

local failures = 0
local function check(name, ok, detail)
    if ok then print(("  ok  %s"):format(name))
    else failures = failures + 1; print(("FAIL  %s  %s"):format(name, detail or "")) end
end

local function deepCopy(v)
    if type(v) ~= "table" then return v end
    local out = {}
    for k, nv in pairs(v) do out[k] = deepCopy(nv) end
    return out
end

local function readFile(path)
    local fh = assert(io.open(path, "rb"), "failed to open " .. path)
    local s = fh:read("*a")
    fh:close()
    return s
end

---------------------------------------------------------------------------
-- 1. Defaults carry the inheritance keys on every buff container shape.
---------------------------------------------------------------------------
local ncdm = ns.defaults and ns.defaults.profile and ns.defaults.profile.ncdm
check("defaults expose ncdm", type(ncdm) == "table")

local function checkBorderKeys(t, label)
    check(label .. " has borderColorSource = inherit",
        type(t) == "table" and t.borderColorSource == "inherit",
        type(t) == "table" and tostring(t.borderColorSource) or "no table")
    check(label .. " has a borderColor table",
        type(t) == "table" and type(t.borderColor) == "table",
        type(t) == "table" and tostring(t.borderColor) or "no table")
end

if type(ncdm) == "table" then
    checkBorderKeys(ncdm.buff, "ncdm.buff (Buff Icons)")
    checkBorderKeys(ncdm.trackedBar, "ncdm.trackedBar (Buff Bars)")
    checkBorderKeys(ncdm.containers and ncdm.containers.buff, "ncdm.containers.buff")
    checkBorderKeys(ncdm.containers and ncdm.containers.trackedBar, "ncdm.containers.trackedBar")
end

---------------------------------------------------------------------------
-- 2. The dedicated "cdmBuffContainers" registry entry.
---------------------------------------------------------------------------
local entry = BorderRegistry.byKey and BorderRegistry.byKey["cdmBuffContainers"]
check("cdmBuffContainers entry registered", entry ~= nil)
check("entry is multi-instance", entry ~= nil and entry.multi == true)
check("entry declares db()", entry ~= nil and type(entry.db) == "function")
check("entry declares refresh()", entry ~= nil and type(entry.refresh) == "function")
check("entry declares instances()", entry ~= nil and type(entry.instances) == "function")
check("entry opts migration into defaultSource = inherit",
    entry ~= nil and type(entry.legacy) == "table" and entry.legacy.defaultSource == "inherit",
    entry and entry.legacy and tostring(entry.legacy.defaultSource) or "no legacy")

---------------------------------------------------------------------------
-- 3. The entry collects the flat buff/trackedBar tables (top-level + mirror).
---------------------------------------------------------------------------
if entry and type(entry.instances) == "function" and type(ncdm) == "table" then
    local profile = deepCopy(ns.defaults.profile)
    local insts = entry.instances(profile)
    local found = {}
    if type(insts) == "table" then
        for _, t in ipairs(insts) do found[t] = true end
    end
    local p = profile.ncdm
    check("collects top-level ncdm.buff", found[p.buff] == true)
    check("collects top-level ncdm.trackedBar", found[p.trackedBar] == true)
    check("collects mirror ncdm.containers.buff", p.containers and found[p.containers.buff] == true)
    check("collects mirror ncdm.containers.trackedBar", p.containers and found[p.containers.trackedBar] == true)
    -- It must NOT sweep the icon-row cooldown containers (those belong to the
    -- separate cdmContainers entry with legacy.table semantics).
    check("does NOT collect essential cooldown container", not found[p.essential])
    check("does NOT collect utility cooldown container", not found[p.utility])
end

---------------------------------------------------------------------------
-- 4. Bar renderer resolves the border via the per-container settings.
---------------------------------------------------------------------------
local bars = readFile("modules/cdm/cdm_bar_renderer.lua")
check("ConfigureBar resolves per-container border (settings passed)",
    bars:find('GetSkinBorderColor(settings, "")', 1, true) ~= nil)
check("live skin refresh resolves border per bar",
    bars:find("GetSkinBorderColor(bar._borderSettings", 1, true) ~= nil)
check("no no-arg GetSkinBorderColor() left in the bar renderer",
    bars:find("GetSkinBorderColor()", 1, true) == nil,
    "a no-arg call ignores the per-container border source")
check("bar config fingerprint folds in the border color",
    bars:find("borderColorSource", 1, true) ~= nil)

---------------------------------------------------------------------------
-- 5. Options page attaches a border-source control to the aura/auraBar sections.
--    (Cooldown rows already attach one; expect at least three total now.)
---------------------------------------------------------------------------
local cp = readFile("modules/cdm/settings/containers_page.lua")
local attachCount = 0
for _ in cp:gmatch("QUI_BorderControl%.Attach") do attachCount = attachCount + 1 end
check("aura + auraBar layout sections attach a border control (>= 3 total)",
    attachCount >= 3, "found " .. attachCount .. " QUI_BorderControl.Attach call(s)")

---------------------------------------------------------------------------
-- 6. Buff icons forward the per-container source into their rowConfig.
---------------------------------------------------------------------------
local buffLayout = readFile("modules/cdm/cdm_buff_layout.lua")
check("buff icon ApplyIconStyle forwards borderColorSource",
    buffLayout:find("borderColorSource = settings.borderColorSource", 1, true) ~= nil)

print(("\n%d failure(s)"):format(failures))
os.exit(failures == 0 and 0 or 1)
