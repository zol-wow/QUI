-- Validates profile round-trip with user-picked textures and fonts in
-- damageMeter.appearance.global. Confirms that non-default values survive
-- the load → migrate → export → import → save cycle without shape drift.
QUI_DB = {
    profileKeys = {
        ["TestChar - TestRealm"] = "Default",
    },
    profiles = {
        Default = {
            damageMeter = {
                appearance = {
                    global = {
                        textures = {
                            bar        = "Quazii v3",
                            background = "Square",
                            border     = "Quazii v2",
                        },
                        fonts = {
                            rowName  = { name = "Poppins Bold",   size = 12, outline = "OUTLINE" },
                            rowValue = { name = "Poppins Medium", size = 11, outline = "_inherit" },
                            header   = { name = "Expressway",     size = 14, outline = "THICKOUTLINE" },
                        },
                    },
                },
            },
        },
    },
}
QUIDB = {}
