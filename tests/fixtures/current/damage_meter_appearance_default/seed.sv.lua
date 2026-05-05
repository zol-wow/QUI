-- Fresh-install profile that does NOT carry the damageMeter.appearance shelf.
-- After AceDB merge, the appearance subtable should be present with the
-- font shelves populated (size = 0, outline = "_inherit") and texture keys
-- nil/empty (nil leaves don't serialize).
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
