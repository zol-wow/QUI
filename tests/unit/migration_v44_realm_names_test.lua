-- tests/unit/migration_v44_realm_names_test.lua
-- Verifies the v44 MigrateChatRealmNames migration, which decouples sender
-- realm display from chat.modifiers.channelShorten into the new
-- chat.modifiers.showRealmNames setting:
--   - channelShorten.enabled = false (was showing realms) → showRealmNames = true
--   - channelShorten.enabled = true / absent / no modifiers → left default (nil)
--   - missing chat / modifiers tables → no error, no spurious tables
--   - idempotent
-- Run: lua tests/unit/migration_v44_realm_names_test.lua

local env = dofile("tools/_addon_env.lua")
local ns = env.LoadCore()
local Migrations = ns.Migrations

local failures = 0
local function check(name, ok, detail)
    if ok then print(("  ok  %s"):format(name))
    else failures = failures + 1; print(("FAIL  %s  %s"):format(name, detail or "")) end
end

-- 1. Explicit channelShorten.enabled = false → showRealmNames forced true,
--    profile stamped to the current schema version (44+; later migrations
--    in the chain may stamp higher).
do
    local profile = { _schemaVersion = 43,
        chat = { modifiers = { channelShorten = { enabled = false, preset = "letter" } } } }
    Migrations.RunOnProfile(profile)
    check("1: shorten-off profile → showRealmNames = true",
        profile.chat.modifiers.showRealmNames == true,
        tostring(profile.chat.modifiers.showRealmNames))
    check("1: _schemaVersion stamped to at least 44",
        (tonumber(profile._schemaVersion) or 0) >= 44, tostring(profile._schemaVersion))
end

-- 2. channelShorten.enabled = true → left at the false default (no write).
do
    local profile = { _schemaVersion = 43,
        chat = { modifiers = { channelShorten = { enabled = true, preset = "letter" } } } }
    Migrations.RunOnProfile(profile)
    check("2: shorten-on profile → showRealmNames untouched (nil)",
        profile.chat.modifiers.showRealmNames == nil,
        tostring(profile.chat.modifiers.showRealmNames))
end

-- 3. channelShorten absent entirely (AceDB stripped the default) → no write.
do
    local profile = { _schemaVersion = 43, chat = { modifiers = {} } }
    Migrations.RunOnProfile(profile)
    check("3: no channelShorten → showRealmNames untouched (nil)",
        profile.chat.modifiers.showRealmNames == nil,
        tostring(profile.chat.modifiers.showRealmNames))
end

-- 4. No modifiers / no chat table → no crash, nothing fabricated.
do
    local p1 = { _schemaVersion = 43, chat = {} }
    local ok1 = pcall(Migrations.RunOnProfile, p1)
    check("4a: chat without modifiers → no error", ok1)
    check("4a: modifiers not fabricated", p1.chat.modifiers == nil, tostring(p1.chat.modifiers))

    local p2 = { _schemaVersion = 43 }
    local ok2 = pcall(Migrations.RunOnProfile, p2)
    check("4b: profile without chat → no error", ok2)
    check("4b: chat not fabricated", p2.chat == nil, tostring(p2.chat))
end

-- 5. Idempotent: re-running the v44 gate on an already-true profile keeps it true.
do
    local profile = { _schemaVersion = 43,
        chat = { modifiers = { channelShorten = { enabled = false },
                               showRealmNames = true } } }
    Migrations.RunOnProfile(profile)
    check("5: idempotent — still true after re-run",
        profile.chat.modifiers.showRealmNames == true,
        tostring(profile.chat.modifiers.showRealmNames))
end

if failures > 0 then error(failures .. " failure(s)") end
print("migration_v44_realm_names_test OK")
