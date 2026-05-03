-- Fresh-install profile that explicitly does NOT carry skinDamageMeter.
-- After AceDB merge, the key should be present with the default value (true).
QUI_DB = {
    profileKeys = {
        ["TestChar - TestRealm"] = "Default",
    },
    profiles = {
        Default = {
            -- intentionally empty — exercises the default-merge path
        },
    },
}
QUIDB = {}
