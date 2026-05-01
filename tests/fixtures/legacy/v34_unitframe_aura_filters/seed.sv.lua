-- Profile at _schemaVersion = 33 with mixed onlyMyDebuffs values across
-- unit frames. v34 MigrateUnitFrameAuraFilters must translate true →
-- debuffFilter.modifiers.PLAYER = true and remove the old key from every
-- unit's auras table.
QUI_DB = {
    profileKeys = { ["TestChar - TestRealm"] = "Default" },
    profiles = {
        Default = {
            _schemaVersion = 33,
            cdm = { engine = "owned" },

            quiUnitFrames = {
                player = {
                    enabled = true,
                    auras   = {
                        showBuffs   = true,
                        showDebuffs = true,
                        -- player has no onlyMyDebuffs by current defaults
                    },
                },
                target = {
                    enabled = true,
                    auras   = {
                        showBuffs      = true,
                        showDebuffs    = true,
                        onlyMyDebuffs  = true,   -- migrate to PLAYER modifier
                    },
                },
                focus = {
                    enabled = true,
                    auras   = {
                        showDebuffs    = true,
                        onlyMyDebuffs  = true,   -- migrate to PLAYER modifier
                    },
                },
                pet = {
                    enabled = true,
                    auras   = {
                        showBuffs      = true,
                        onlyMyDebuffs  = false,  -- explicit off; remove key, no PLAYER
                    },
                },
                targettarget = {
                    enabled = true,
                    auras   = {
                        showBuffs      = true,
                        showDebuffs    = true,
                        -- onlyMyDebuffs absent; nothing to migrate
                    },
                },
            },
        },
    },
}
