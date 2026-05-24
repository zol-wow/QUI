-- CDM item in built-in buff container.
-- Pins the round-trip shape for an item entry stored in the buff container
-- with kind = "aura". The pipeline should preserve the entry verbatim.
QUI_DB = {
    profileKeys = {
        ["TestChar - TestRealm"] = "Default",
    },
    profiles = {
        Default = {
            ncdm = {
                buff = {
                    ownedSpells = {
                        { type = "item", id = 5512, kind = "aura" },
                    },
                },
            },
        },
    },
}
QUIDB = {}
