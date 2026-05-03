-- Fresh-install profile that does NOT carry the damageMeter shelf.
-- After AceDB merge, the shelf should be present with all 11 default keys.
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
