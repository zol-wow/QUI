-- LOD sub-addons load after PLAYER_LOGIN; a raw registration would never
-- fire. ns.WhenLoggedIn is the only allowed pattern.
local manifest = assert(loadfile("core/addon_manifest.lua"))()
local bad = {}
for _, e in ipairs(manifest) do
    if e.class == "lod" then
        local p = io.popen(('grep -rn "RegisterEvent(\\"PLAYER_LOGIN\\"" %q --include="*.lua"'):format(e.folder))
        for line in p:lines() do bad[#bad + 1] = line end
        p:close()
    end
end
assert(#bad == 0, "raw PLAYER_LOGIN in LOD module:\n" .. table.concat(bad, "\n"))
print("lod_login_event_guard_test OK")
