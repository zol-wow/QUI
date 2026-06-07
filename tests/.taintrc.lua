-- tests/.taintrc.lua
-- Combat-taint analyzer config. See
-- docs/superpowers/specs/2026-05-04-taint-analyzer-design.md.
return {
    strict_paths = {
        -- Directories ratcheted into CI enforcement. Findings under these
        -- prefixes are classified strict (CI-blocking) instead of advisory.
        -- Add only after auditing — promoted findings must be either fixed
        -- or annotated with `-- @secret-safe: <reason>` to keep CI green.
        "QUI_CDM/cdm/",
        "QUI_Chat/chat/",
        "QUI_GroupFrames/groupframes/",
        "QUI_ActionBars/actionbars/",
        "QUI_DamageMeter/damage_meter/",
    },
    strict_unwrap_paths = {
        -- Safe* unwrap helpers are stricter in CDM: cooldown-secret values
        -- must stay opaque unless they are passed to approved C-side sinks.
        "QUI_CDM/cdm/",
    },
    ignore_paths = {
        "libs/",
        "tests/",
        "importstrings/",
        "meta/",  -- LuaLS editor-only ---@meta stubs; never loaded in-game
    },
    coverage = {
        secretWhenCooldownsRestricted = true,
        isSecretReturn = true,
        secretArguments_restricted = true,
    },
    extra_safe_sinks = {},
    extra_unwraps = {
        -- QUI imports Helpers.Safe* as bare locals at file scope and calls
        -- them by short name. Register the short forms so the analyzer
        -- recognizes those call sites as unwraps (review-tier findings).
        "SafeValue",
        "SafeToNumber",
        "SafeToString",
        "SafeCompare",
    },
    clean_fields = {
        -- Field names that are always non-secret per Blizzard's API contract.
        -- When the analyzer sees `tainted_local.<field>` for any of these,
        -- it treats the read as clean instead of propagating taint.
        "isOnGCD",  -- SpellCooldownInfo.isOnGCD is always a clean boolean
    },
}
