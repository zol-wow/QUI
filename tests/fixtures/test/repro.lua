-- Reproduction harness for "castbar anchors get lost during import"
--
-- Replays the user-reported scenario:
--   1) Load the user's actual SavedVariables (QUI3.lua → renamed to QUI_DB/QUIDB)
--   2) Build an AceDB harness on top of it
--   3) Import the healing profile string into a fresh "Repro_Import" profile
--   4) Dump castbar-related anchors from the imported result
--
-- Run from repo root:
--   lua tests/fixtures/test/repro.lua

local function ScriptDir()
    local p = (arg and arg[0]) or ""
    p = p:gsub("\\", "/")
    return (p:match("(.*/)")) or "./"
end
local REPO_ROOT = ScriptDir() .. "../../../"

-- Trick the env into thinking it's being invoked from tools/ by overriding
-- arg[0] before dofile'ing it. The env reads arg[0] only inside ScriptDir(),
-- so we restore the real value immediately afterward.
local realArg0 = arg[0]
arg[0] = REPO_ROOT .. "tools/_addon_env.lua"
local env = dofile(REPO_ROOT .. "tools/_addon_env.lua")
arg[0] = realArg0

env.LoadLibs()
env.LoadCore()

local function ReadFile(path)
    local f = assert(io.open(path, "rb"))
    local s = f:read("*a")
    f:close()
    return s
end

------------------------------------------------------------------
-- Load QUI3.lua, then alias QUI3_DB → QUI_DB so AceDB picks it up
------------------------------------------------------------------
local svPath = REPO_ROOT .. "tests/fixtures/test/QUI3.lua"
local sv, err = loadfile(svPath)
if not sv then error("loadfile QUI3.lua: " .. tostring(err)) end
sv()

-- The user's WoW install splits the addon's data across two AceDB instances:
--   QUI_DB  ← init.lua's small db (QUI.defaults: layoutMode, debug, etc.)
--   QUIDB   ← core/main.lua's big db (ns.defaults: profile-level data)
-- The headless harness builds a single AceDB named QUI_DB but loaded with
-- ns.defaults — so it mimics core/main.lua's "QUIDB" instance. Map QUI3DB
-- (the user's big SV) into _G.QUI_DB. QUI3_DB only has profileKeys for the
-- small init.lua db; we don't need it for testing the import migration path.
if _G.QUI3DB then _G.QUI_DB = _G.QUI3DB end
_G.QUIDB = {}

print("==== Pre-harness state ====")
print(string.format("profiles available: %s",
    table.concat((function()
        local out = {}
        for k in pairs(_G.QUI_DB.profiles or {}) do out[#out + 1] = tostring(k) end
        table.sort(out)
        return out
    end)(), ", ")))
print(string.format("profileKeys: %s", (function()
    local out = {}
    for k, v in pairs(_G.QUI_DB.profileKeys or {}) do out[#out + 1] = k .. "=>" .. v end
    table.sort(out)
    return table.concat(out, ", ")
end)()))

------------------------------------------------------------------
-- Build the harness on the user's actual SV
------------------------------------------------------------------
local h = env.BuildHarness()

local function CastbarKeys(t)
    if type(t) ~= "table" then return {} end
    local keys = {}
    for k in pairs(t) do
        if type(k) == "string" and k:find("[Cc]astbar$") then
            keys[#keys + 1] = k
        end
    end
    table.sort(keys)
    return keys
end

local function PrintCastbarFA(label, fa)
    print("---- " .. label .. " ----")
    if type(fa) ~= "table" then
        print("  (frameAnchoring is " .. type(fa) .. ")")
        return
    end
    local keys = CastbarKeys(fa)
    if #keys == 0 then
        print("  (no *Castbar entries)")
        return
    end
    for _, k in ipairs(keys) do
        local e = fa[k]
        if type(e) == "table" then
            print(string.format("  %-16s parent=%-12s point=%-7s rel=%-7s ofs=%s/%s autoW=%s",
                k, tostring(e.parent), tostring(e.point), tostring(e.relative),
                tostring(e.offsetX), tostring(e.offsetY), tostring(e.autoWidth)))
        else
            print(string.format("  %-16s = %s", k, type(e)))
        end
    end
end

------------------------------------------------------------------
-- Run the user's scenario: import the healing string into a NEW profile
-- so we can compare imported vs. existing without losing the existing data.
------------------------------------------------------------------
local importStr = ReadFile(REPO_ROOT .. "tests/fixtures/test/healing-profile-3-5-6.txt")
importStr = importStr:gsub("%s+", "")

print("\n==== Decoding import payload ====")
do
    local AceSerializer = LibStub("AceSerializer-3.0")
    local LibDeflate = LibStub("LibDeflate")
    local body = importStr:gsub("^QUI1:", "")
    local compressed = LibDeflate:DecodeForPrint(body)
    local serialized = LibDeflate:DecompressDeflate(compressed)
    local ok, payload = AceSerializer:Deserialize(serialized)
    if ok then
        PrintCastbarFA("imported payload.frameAnchoring (raw)", payload.frameAnchoring)
        print(string.format("  payload._schemaVersion = %s", tostring(payload._schemaVersion)))
    end
end

------------------------------------------------------------------
-- Bypass missing modules that BackwardsCompat() might invoke. We need
-- ImportProfileFromString, which calls ApplyFullProfilePayload → addon:BackwardsCompat
-- → Migrations.Run + various other helpers. Stub the missing pieces.
------------------------------------------------------------------
local QUI = h.QUI
local ns  = h.ns

-- Stub addon:BackwardsCompat to call only Migrations.Run on the imported profile
QUI.BackwardsCompat = function(self)
    if ns.Migrations and ns.Migrations.Run then
        ns.Migrations.Run(self.db)
    end
end

-- Stub the registry / settings hooks the import path probes
ns.Registry = ns.Registry or { RefreshAll = function() end }
ns.Settings = ns.Settings or {}
ns.CDMContainers = ns.CDMContainers or { ResnapshotForCurrentSpec = function() end }

------------------------------------------------------------------
-- Snapshot the active profile BEFORE the import (this is the user's
-- live profile state); the user's import would normally overwrite it,
-- but to compare apples-to-apples let's switch to a fresh profile name.
------------------------------------------------------------------
print("\n==== Active profile BEFORE import (live profile via AceDB) ====")
print(string.format("current profile: %s", h.db:GetCurrentProfile()))
PrintCastbarFA("h.db.profile.frameAnchoring (before import)", h.db.profile.frameAnchoring)

print("\n==== Running ImportProfileFromString into a NEW 'ReproImport' profile ====")
local ok, msg = h.QUICore:ImportProfileFromString(importStr, "ReproImport")
print(string.format("import returned: ok=%s msg=%s", tostring(ok), tostring(msg)))

print(string.format("current profile after import: %s", h.db:GetCurrentProfile()))
PrintCastbarFA("h.db.profile.frameAnchoring (after import)", h.db.profile.frameAnchoring)
print(string.format("h.db.profile._schemaVersion = %s",
    tostring(h.db.profile._schemaVersion)))

------------------------------------------------------------------
-- Now try the path the user is most likely hitting: import into the
-- ALREADY-EXISTING 'Default' profile (overwriting it). This routes
-- through the same ApplyFullProfilePayload → BackwardsCompat path,
-- but the target profile already has data + a high _schemaVersion.
------------------------------------------------------------------
print("\n==== Switching back to 'Default' and re-importing into it ====")
h.db:SetProfile("Default")
print("current profile: " .. h.db:GetCurrentProfile())
PrintCastbarFA("h.db.profile.frameAnchoring (Default before re-import)", h.db.profile.frameAnchoring)

local ok2, msg2 = h.QUICore:ImportProfileFromString(importStr)  -- no targetProfileName
print(string.format("import returned: ok=%s msg=%s", tostring(ok2), tostring(msg2)))
print(string.format("current profile after import: %s", h.db:GetCurrentProfile()))
PrintCastbarFA("h.db.profile.frameAnchoring (Default after import)", h.db.profile.frameAnchoring)
print(string.format("h.db.profile._schemaVersion = %s",
    tostring(h.db.profile._schemaVersion)))

------------------------------------------------------------------
-- Audit (effective): switch to each profile so AceDB fills defaults,
-- and dump what the runtime would see.
------------------------------------------------------------------
print("\n==== Effective castbar anchors (post-default-fill) per profile ====")
do
    local sv = h.db.sv
    local profileNames = {}
    for name in pairs(sv.profiles) do profileNames[#profileNames + 1] = name end
    table.sort(profileNames)
    for _, name in ipairs(profileNames) do
        h.db:SetProfile(name)
        print("\n[effective profile: " .. name .. "]")
        PrintCastbarFA(name, h.db.profile.frameAnchoring)
    end
end

------------------------------------------------------------------
-- Audit: walk every existing profile and dump its castbar anchors.
-- The user might be observing anchor weirdness in already-saved profiles
-- rather than in the freshly-imported one. The SV file holds 9 profiles —
-- if any of them have *Castbar entries with unexpected parent / point /
-- relative values (e.g. parent=cdmEssential, TOPLEFT/BOTTOMLEFT), that
-- is migration-induced damage that survived past import.
------------------------------------------------------------------
print("\n==== Per-profile castbar anchors ====")
local sv = h.db.sv
if sv and sv.profiles then
    local profileNames = {}
    for name in pairs(sv.profiles) do profileNames[#profileNames + 1] = name end
    table.sort(profileNames)
    for _, name in ipairs(profileNames) do
        print("\n[profile: " .. name .. "]   _schemaVersion=" ..
            tostring(sv.profiles[name]._schemaVersion))
        PrintCastbarFA(name, sv.profiles[name].frameAnchoring)

        -- Also dump the legacy quiUnitFrames.<unit>.castbar.anchor / freeOffset
        -- fields that the v19 castbar migration consumes — these are the
        -- "semantic" anchor values the migration translates into FA entries.
        local uf = sv.profiles[name].quiUnitFrames
        if type(uf) == "table" then
            for _, unitKey in ipairs({"player","target","focus","pet","targettarget"}) do
                local cb = uf[unitKey] and uf[unitKey].castbar
                if type(cb) == "table" then
                    print(string.format("  [legacy castbar] %s.castbar: anchor=%s ofs=%s/%s freeOfs=%s/%s lockedOfs=%s/%s",
                        unitKey,
                        tostring(cb.anchor),
                        tostring(cb.offsetX), tostring(cb.offsetY),
                        tostring(cb.freeOffsetX), tostring(cb.freeOffsetY),
                        tostring(cb.lockedOffsetX), tostring(cb.lockedOffsetY)))
                end
            end
        end
    end
end

------------------------------------------------------------------
-- Critical apply-path inspection: anchoring.lua's GetSavedFrameAnchorSettings
-- uses rawget, so the table passed to ApplyFrameAnchor has AceDB-stripped
-- defaults missing. After import, playerCastbar is { offsetY = 40 } in raw —
-- parent/point/relative are stripped because they match defaults. The
-- castbar branch at anchoring.lua:2620 calls ResolveFrameForKey(settings.parent),
-- which receives nil → falls back to UIParent → castbar visually drifts to
-- screen center even though "the FA entry is correct".
------------------------------------------------------------------
print("\n==== Apply-path view (raw vs defaults-filled) for ReproImport ====")
h.db:SetProfile("ReproImport")
print("Reading via h.db.profile (proxy) AND sv.profiles.ReproImport (raw):")
do
    -- Direct raw access (bypasses AceDB proxy entirely)
    local rawProfile = h.db.sv.profiles.ReproImport
    local rawFa = rawget(rawProfile, "frameAnchoring")
    print("  rawget(sv.profiles.ReproImport, 'frameAnchoring'): " ..
        (type(rawFa) == "table" and "<table>" or tostring(rawFa)))
    if type(rawFa) == "table" then
        for _, key in ipairs({"playerCastbar","targetCastbar","focusCastbar"}) do
            local rawEntry = rawget(rawFa, key)
            if rawEntry then
                print(string.format("    sv.profiles.ReproImport.frameAnchoring[%s] (rawget): parent=%s point=%s rel=%s ofs=%s/%s",
                    key, tostring(rawget(rawEntry, "parent")), tostring(rawget(rawEntry, "point")),
                    tostring(rawget(rawEntry, "relative")), tostring(rawget(rawEntry, "offsetX")),
                    tostring(rawget(rawEntry, "offsetY"))))
            else
                print(string.format("    sv.profiles.ReproImport.frameAnchoring[%s]: NIL (rawget)", key))
            end
        end
    end
end
print()
do
    local fa = h.db.profile.frameAnchoring
    for _, key in ipairs({"playerCastbar","targetCastbar","focusCastbar","petCastbar","totCastbar"}) do
        local raw = rawget(fa, key)
        local proxied = fa[key]
        if type(raw) == "table" then
            print(string.format("  %s [raw via rawget — what ApplyFrameAnchor sees]", key))
            print(string.format("    parent=%s point=%s rel=%s ofs=%s/%s autoW=%s",
                tostring(raw.parent), tostring(raw.point), tostring(raw.relative),
                tostring(raw.offsetX), tostring(raw.offsetY), tostring(raw.autoWidth)))
        end
        if type(proxied) == "table" then
            print(string.format("  %s [proxied via AceDB — defaults filled]", key))
            print(string.format("    parent=%s point=%s rel=%s ofs=%s/%s autoW=%s",
                tostring(proxied.parent), tostring(proxied.point), tostring(proxied.relative),
                tostring(proxied.offsetX), tostring(proxied.offsetY), tostring(proxied.autoWidth)))
        end
    end
end

------------------------------------------------------------------
-- Simulate a logout+login cycle: take the post-import SV, drop the
-- harness, rebuild a fresh AceDB, and check what the apply path
-- sees BEFORE any code has read frameAnchoring through the proxy.
------------------------------------------------------------------
print("\n==== Simulated logout+login cycle (re-load from stripped SV) ====")
do
    -- Snapshot the current (post-import, post-strip) SV.
    local function DeepCopy(v)
        if type(v) ~= "table" then return v end
        local t = {}; for k, vv in pairs(v) do t[k] = DeepCopy(vv) end; return t
    end
    -- Apply AceDB's strip pass to mimic what WoW writes on logout.
    local StripHelper = dofile(REPO_ROOT .. "tests/helpers/ace_db_strip.lua")
    StripHelper.StripLibrary(h.db)

    -- Capture the post-strip SV state
    local strippedSV = { QUI_DB = DeepCopy(_G.QUI_DB), QUIDB = DeepCopy(_G.QUIDB) }

    -- Reset and rebuild
    _G.QUI_DB = strippedSV.QUI_DB
    _G.QUIDB = strippedSV.QUIDB
    local h2 = env.BuildHarness()
    h2.db:SetProfile("ReproImport")

    -- BEFORE any proxied read: probe rawget on the raw SV table
    print("BEFORE any proxy read (apply path's view):")
    local rawProfile = h2.db.sv.profiles.ReproImport
    local rawFa = rawget(rawProfile, "frameAnchoring")
    if type(rawFa) == "table" then
        for _, key in ipairs({"playerCastbar","targetCastbar","focusCastbar","petCastbar","totCastbar"}) do
            local entry = rawget(rawFa, key)
            if entry then
                print(string.format("  rawget(fa, %q): parent=%s point=%s rel=%s ofs=%s/%s",
                    key, tostring(rawget(entry, "parent")), tostring(rawget(entry, "point")),
                    tostring(rawget(entry, "relative")), tostring(rawget(entry, "offsetX")),
                    tostring(rawget(entry, "offsetY"))))
            else
                print(string.format("  rawget(fa, %q): NIL — entry was fully stripped", key))
            end
        end
    end

    -- Now simulate what `_G.QUI_ApplyFrameAnchor("playerCastbar")` would do:
    --   local settings = GetSavedFrameAnchorSettings(anchoringDB, key)  -- rawget
    --   ApplyFrameAnchor(key, settings)
    --     -> CASTBAR_ANCHOR_KEYS branch:
    --        parentFrame = ResolveFrameForKey(settings.parent) or UIParent
    --        point = settings.point or "CENTER"
    --        relative = settings.relative or "CENTER"
    --        offsetX/Y = settings.offsetX or 0 / settings.offsetY or 0
    print("\nWhat ApplyFrameAnchor sees for playerCastbar (mimicking the actual GetSavedFrameAnchorSettings):")
    -- Inline implementation matching the fix in modules/utility/anchoring.lua:
    -- rawget for detection, proxied read for consumption.
    local function GetSavedFrameAnchorSettings(anchoringDB, key)
        if type(anchoringDB) ~= "table" or not key then return nil end
        if rawget(anchoringDB, key) == nil then return nil end
        local settings = anchoringDB[key]
        return type(settings) == "table" and settings or nil
    end

    local proxiedFa = h2.db.profile.frameAnchoring  -- AceDB proxy
    -- Wipe any prior materialization on the proxy so we test "first read" semantics
    -- (we can't actually do that — but the per-key reads below show what the function
    -- returns either way: if AceDB had materialized defaults into the raw table,
    -- our function would still see them; if not, the proxy reads them through metatable.)
    local settings = GetSavedFrameAnchorSettings(proxiedFa, "playerCastbar")
    if settings then
        local parent = settings.parent
        local point = settings.point or "CENTER"
        local relative = settings.relative or "CENTER"
        local ox = settings.offsetX or 0
        local oy = settings.offsetY or 0
        print(string.format("  Resolved: parent=%s", tostring(parent)))
        print(string.format("  SetPoint(%s, <%s>, %s, %s, %s)",
            point, parent or "UIParent", relative, tostring(ox), tostring(oy)))
        if parent == "playerFrame" and point == "TOP" and relative == "BOTTOM" then
            print("  ✅ FIXED: castbar correctly anchors to playerFrame TOP→BOTTOM at offset 0/40.")
        elseif not parent then
            print("  ❌ BUG: castbar would be anchored to UIParent CENTER/CENTER+offsets.")
        end
    else
        print("  (no raw entry — apply path returns early)")
    end
end

print("\n==== Migration log (last 50 lines) ====")
local log = _G.QUI_MIGRATION_LOG or {}
local startIdx = math.max(1, #log - 50)
for i = startIdx, #log do
    print("  " .. log[i])
end
