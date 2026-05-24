-- Legacy SV from before the displayMode field was introduced.
-- The item entry has no displayMode and no kind field.
-- After migration: kind = "cooldown" is inferred by ResolveEntryKind.
-- displayMode remains absent (nil) — no migration stamps the new field.
QUI_DB = {
    profileKeys = {
        ["TestChar - TestRealm"] = "Default",
    },
    profiles = {
        Default = {
            ncdm = {
                containers = {
                    ["customBar:mybar"] = {
                        containerType = "customBar",
                        ownedSpells = {
                            { type = "item", id = 5512 },
                        },
                    },
                },
            },
        },
    },
}
QUIDB = {}
