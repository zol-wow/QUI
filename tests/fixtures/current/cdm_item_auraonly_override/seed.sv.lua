-- CDM item with displayMode = "auraOnly" in a custom container.
-- Pins the round-trip shape for an item entry that overrides display mode.
-- The pipeline must preserve displayMode so the override survives persistence.
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
                            {
                                type = "item",
                                id = 5512,
                                kind = "cooldown",
                                displayMode = "auraOnly",
                            },
                        },
                    },
                },
            },
        },
    },
}
QUIDB = {}
