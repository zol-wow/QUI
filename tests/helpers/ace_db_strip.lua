--[[
  ace_db_strip.lua

  Simulate AceDB's strip-on-save behavior, which in WoW fires during
  PLAYER_LOGOUT via an internal event handler. Our headless harness has
  no event loop, so we trigger it explicitly.

  Two impls:
    M.StripLibrary(db)  — preferred: invokes AceDB's own dispatcher
    M.StripManual(db)   — fallback: replicates the recursive default-strip

  The runner picks via --strip-impl flag (default "library").

  Self-test: lua tests/helpers/ace_db_strip.lua --test
]]

local M = {}

----------------------------------------------------------------------------
-- Library impl: tries known AceDB shutdown hooks in order of preference.
--
-- Investigation findings (AceDB-3.0 r33):
--   - removeDefaults is a local closure; not public.
--   - logoutHandler fires PLAYER_LOGOUT → calls db:RegisterDefaults(nil)
--     for every registered db. That public method calls removeDefaults
--     internally and is the correct strip entry point.
--   - There is no db:Logout() or AceDB:Logout() method.
--   - OnDatabaseShutdown fires before the strip, not as its trigger.
--   - After stripping, re-register the original defaults so the live db
--     object stays usable (matches what logoutHandler does not do, but
--     callers in tests need the db intact for assertions).
----------------------------------------------------------------------------
function M.StripLibrary(db)
    local AceDB = LibStub and LibStub("AceDB-3.0", true)
    if not AceDB then
        error("ace_db_strip: AceDB-3.0 not registered with LibStub")
    end

    local CANDIDATES = {
        -- Primary: db:RegisterDefaults(nil) strips all defaults from the sv,
        -- mirroring what AceDB's PLAYER_LOGOUT handler does. Capture and
        -- restore defaults so the db object remains usable after the call.
        function()
            if db.RegisterDefaults then
                local saved = db.defaults
                db:RegisterDefaults(nil)
                db.defaults = saved
                return true
            end
        end,
        -- Fallback: dispatch via callbacks if exposed (fires listeners but
        -- does not itself strip defaults — kept as last-resort signal only).
        function()
            local cb = db.callbacks
            if cb and cb.Fire then cb:Fire("OnDatabaseShutdown", db); return true end
        end,
    }
    for _, fn in ipairs(CANDIDATES) do
        local ok, ret = pcall(fn)
        if ok and ret then return end
    end
    -- If none worked, fall through to manual.
    M.StripManual(db)
end

----------------------------------------------------------------------------
-- Manual impl: walk profile and remove values that exactly match defaults.
-- This is what AceDB's removeDefaults does — recursive, leaves user values.
----------------------------------------------------------------------------
local function StripDefaults(target, defaults)
    if type(target) ~= "table" or type(defaults) ~= "table" then return end
    for k, dv in pairs(defaults) do
        local tv = rawget(target, k)
        if type(dv) == "table" and type(tv) == "table" then
            StripDefaults(tv, dv)
            if next(tv) == nil then rawset(target, k, nil) end
        elseif tv == dv then
            rawset(target, k, nil)
        end
    end
end

function M.StripManual(db)
    if not db or not db.defaults then return end

    local rawDb = _G.QUI_DB
    if type(rawDb) ~= "table" then return end

    -- Keyed scopes: top-level SV key holds a table indexed by an identifier
    -- (profile name, char key, class token, etc.). Each entry gets stripped
    -- against its corresponding defaults sub-table.
    local KEYED_SCOPES = {
        { svKey = "profiles", defaultsKey = "profile" },
        { svKey = "char",     defaultsKey = "char" },
        { svKey = "class",    defaultsKey = "class" },
        { svKey = "race",     defaultsKey = "race" },
        { svKey = "faction",  defaultsKey = "faction" },
        { svKey = "locale",   defaultsKey = "locale" },
    }
    for _, scope in ipairs(KEYED_SCOPES) do
        local scopeDefaults = db.defaults[scope.defaultsKey]
        local scopeData = rawget(rawDb, scope.svKey)
        if scopeDefaults and type(scopeData) == "table" then
            for _, entry in pairs(scopeData) do
                if type(entry) == "table" then
                    StripDefaults(entry, scopeDefaults)
                end
            end
        end
    end

    -- Global is a single non-keyed scope.
    if db.defaults.global and type(rawget(rawDb, "global")) == "table" then
        StripDefaults(rawDb.global, db.defaults.global)
    end
end

----------------------------------------------------------------------------
-- Self-test (uses StripManual; library impl tested via fixture round-trips)
----------------------------------------------------------------------------
local function SelfTest()
    local profileDefaults = { foo = 1, nested = { a = "x", b = "y" } }
    local profile = { foo = 1, nested = { a = "x", b = "z" }, custom = 99 }
    StripDefaults(profile, profileDefaults)
    -- foo == default → stripped
    assert(profile.foo == nil, "foo should have been stripped")
    -- nested.a == default → stripped; nested.b customized → kept
    assert(profile.nested.a == nil, "nested.a should have been stripped")
    assert(profile.nested.b == "z", "nested.b should have been kept")
    -- custom kept
    assert(profile.custom == 99, "custom should have been kept")
    print("ace_db_strip self-test: OK")
end

if arg and arg[1] == "--test" then SelfTest() end

return M
