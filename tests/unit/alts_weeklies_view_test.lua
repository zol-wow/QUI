-- tests/unit/alts_weeklies_view_test.lua
-- Run: lua tests/unit/alts_weeklies_view_test.lua
-- Covers the PURE helpers of the weeklies tab:
--   WeekliesView.VaultSummary
--   WeekliesView.KeystoneText
--   WeekliesView.LockoutLine
--   WeekliesView.BuildDisplayRows
-- Frame-building Builder is NOT exercised (no WoW frame API headless).

local ns = {}

ns.Helpers = {
    GetGeneralFont        = function() return "Fonts\\FRIZQT__.TTF" end,
    GetGeneralFontOutline = function() return "" end,
}
ns.Storage = { Store = {}, Bus = {} }

-- Provide RosterData.FormatResetIn for LockoutLine.
ns.Alts = {
    RosterData = {
        FormatResetIn = function(resetAt, now)
            if not resetAt then return "—" end
            local left = resetAt - (now or 0)
            if left <= 0 then return "expired" end
            local d = math.floor(left / 86400)
            local h = math.floor((left % 86400) / 3600)
            if d > 0 then return string.format("%dd %dh", d, h) end
            local m = math.floor((left % 3600) / 60)
            if h > 0 then return string.format("%dh %dm", h, m) end
            return string.format("%dm", math.max(m, 1))
        end,
    },
    Window = { RegisterTab = function() end },
}

assert(loadfile("QUI_Alts/alts/views/weeklies.lua"))("QUI", ns)

local WV = ns.Alts.WeekliesView
assert(WV, "WeekliesView exported")

---------------------------------------------------------------------------
-- VaultSummary: nil / empty
---------------------------------------------------------------------------
assert(WV.VaultSummary(nil)           == "—", "nil weeklies → —")
assert(WV.VaultSummary({})            == "—", "no activities key → —")
assert(WV.VaultSummary({ activities = {} }) == "—", "empty activities → —")

---------------------------------------------------------------------------
-- VaultSummary: single type, all slots completed
---------------------------------------------------------------------------
local w_raid_full = {
    activities = {
        { type = 1, index = 1, threshold = 1, progress = 2 },
        { type = 1, index = 2, threshold = 3, progress = 4 },
        { type = 1, index = 3, threshold = 8, progress = 8 },
    }
}
-- Raid type 1: all 3 completed → "Raid 3/3"
local got = WV.VaultSummary(w_raid_full)
assert(got == "Raid 3/3", "raid all 3: " .. got)

---------------------------------------------------------------------------
-- VaultSummary: mixed progress, two types
---------------------------------------------------------------------------
-- Raid type 1: 1 completed out of 3; Dungeons type 2: 2 completed out of 3.
local w_mixed = {
    activities = {
        { type = 1, index = 1, threshold = 1,  progress = 2 },   -- Raid complete
        { type = 1, index = 2, threshold = 4,  progress = 3 },   -- Raid incomplete
        { type = 1, index = 3, threshold = 8,  progress = 1 },   -- Raid incomplete
        { type = 2, index = 1, threshold = 1,  progress = 5 },   -- Dungeons complete
        { type = 2, index = 2, threshold = 4,  progress = 8 },   -- Dungeons complete
        { type = 2, index = 3, threshold = 10, progress = 3 },   -- Dungeons incomplete
    }
}
got = WV.VaultSummary(w_mixed)
assert(got == "Raid 1/3 · Dungeons 2/3", "mixed: " .. got)

---------------------------------------------------------------------------
-- VaultSummary: unknown type falls back to "Type N"
---------------------------------------------------------------------------
local w_unknown = {
    activities = {
        { type = 99, index = 1, threshold = 5, progress = 5 },
    }
}
got = WV.VaultSummary(w_unknown)
assert(got == "Type 99 1/1", "unknown type label: " .. got)

---------------------------------------------------------------------------
-- VaultSummary: World type (3) and PvP (4)
---------------------------------------------------------------------------
local w_world = {
    activities = {
        { type = 3, index = 1, threshold = 1, progress = 0 },
        { type = 4, index = 1, threshold = 1, progress = 1 },
    }
}
got = WV.VaultSummary(w_world)
assert(got == "World 0/1 · PvP 1/1", "world + pvp: " .. got)

---------------------------------------------------------------------------
-- KeystoneText
---------------------------------------------------------------------------
assert(WV.KeystoneText(nil) == "—",        "nil weeklies → —")
assert(WV.KeystoneText({})  == "—",        "no mapID → —")

-- No level (nil level with mapID present)
local w_ks_nolevel = { keystoneMapID = 100, keystoneName = "Ara-Kara" }
got = WV.KeystoneText(w_ks_nolevel)
assert(got == "Ara-Kara +?", "no level → name +?: " .. got)

-- Normal keystone
local w_ks_normal = { keystoneMapID = 100, keystoneName = "The Stonevault", keystoneLevel = 12 }
got = WV.KeystoneText(w_ks_normal)
assert(got == "The Stonevault +12", "normal keystone: " .. got)

-- mapID present but no name (nil name)
local w_ks_noname = { keystoneMapID = 200, keystoneLevel = 7 }
got = WV.KeystoneText(w_ks_noname)
assert(got == "+7", "no name, has level: " .. got)

-- mapID present, no name, no level
local w_ks_neither = { keystoneMapID = 200 }
got = WV.KeystoneText(w_ks_neither)
assert(got == "+?", "no name no level: " .. got)

---------------------------------------------------------------------------
-- LockoutLine: normal with boss counts
---------------------------------------------------------------------------
-- now = 1000, resetAt = 1000 + 2*86400 + 5*3600 = 1000 + 190800 = 191800
local now = 1000
local lo_normal = {
    name           = "Amirdrassil",
    difficultyName = "Mythic",
    bossesKilled   = 8,
    bossesTotal    = 9,
    resetAt        = now + 2 * 86400 + 5 * 3600,
    extended       = nil,
}
got = WV.LockoutLine(lo_normal, now)
assert(got == "Amirdrassil Mythic 8/9 — resets 2d 5h",
    "normal lockout: " .. got)

---------------------------------------------------------------------------
-- LockoutLine: nil boss counts → omit progress
---------------------------------------------------------------------------
local lo_noboss = {
    name           = "Nerub-ar Palace",
    difficultyName = "Heroic",
    bossesKilled   = nil,
    bossesTotal    = nil,
    resetAt        = now + 86400,
}
got = WV.LockoutLine(lo_noboss, now)
assert(got == "Nerub-ar Palace Heroic — resets 1d 0h",
    "nil boss counts: " .. got)

---------------------------------------------------------------------------
-- LockoutLine: partial nil (one of killed/total nil) → omit progress
---------------------------------------------------------------------------
local lo_partial = {
    name         = "Blackrock Depths",
    bossesKilled = 3,
    bossesTotal  = nil,
    resetAt      = now + 3600,
}
got = WV.LockoutLine(lo_partial, now)
assert(got == "Blackrock Depths — resets 1h 0m",
    "partial nil boss: " .. got)

---------------------------------------------------------------------------
-- LockoutLine: extended suffix
---------------------------------------------------------------------------
local lo_extended = {
    name           = "Amirdrassil",
    difficultyName = "Normal",
    bossesKilled   = 9,
    bossesTotal    = 9,
    resetAt        = now + 86400,
    extended       = true,
}
got = WV.LockoutLine(lo_extended, now)
assert(got == "Amirdrassil Normal 9/9 — resets 1d 0h (extended)",
    "extended: " .. got)

---------------------------------------------------------------------------
-- LockoutLine: expired reset
---------------------------------------------------------------------------
local lo_expired = {
    name     = "Ulduar",
    resetAt  = now - 100,
}
got = WV.LockoutLine(lo_expired, now)
assert(got == "Ulduar — resets expired",
    "expired: " .. got)

---------------------------------------------------------------------------
-- LockoutLine: nil lockout
---------------------------------------------------------------------------
got = WV.LockoutLine(nil, now)
assert(got == "", "nil lockout → empty string: " .. tostring(got))

---------------------------------------------------------------------------
-- BuildDisplayRows: empty
---------------------------------------------------------------------------
local rows = WV.BuildDisplayRows({})
assert(#rows == 0, "empty chars → 0 rows")

rows = WV.BuildDisplayRows(nil)
assert(#rows == 0, "nil chars → 0 rows")

---------------------------------------------------------------------------
-- BuildDisplayRows: name-asc order + lockouts interleaved after character
---------------------------------------------------------------------------
local chars = {
    ["Zara-Realm"] = {
        name    = "Zara",
        details = { class = "MAGE" },
        weeklies = { mplusRating = 1200 },
        lockouts = {
            { name = "L1", resetAt = 9999 },
            { name = "L2", resetAt = 9999 },
        },
    },
    ["Arel-Realm"] = {
        name    = "Arel",
        details = { class = "WARRIOR" },
        weeklies = nil,
        lockouts = nil,
    },
    ["Mira-Realm"] = {
        name    = "Mira",
        details = { class = "DRUID" },
        weeklies = {},
        lockouts = {
            { name = "L3", resetAt = 9999 },
        },
    },
}

rows = WV.BuildDisplayRows(chars)

-- Expected order: Arel(char), Mira(char), L3(lockout), Zara(char), L1(lockout), L2(lockout)
assert(#rows == 6, "6 rows total: " .. #rows)

assert(rows[1].kind == "char"    and rows[1].name == "Arel", "row1 = Arel char: " .. tostring(rows[1].name))
assert(rows[2].kind == "char"    and rows[2].name == "Mira", "row2 = Mira char: " .. tostring(rows[2].name))
assert(rows[3].kind == "lockout" and rows[3].lockout.name == "L3", "row3 = L3 lockout")
assert(rows[4].kind == "char"    and rows[4].name == "Zara", "row4 = Zara char: " .. tostring(rows[4].name))
assert(rows[5].kind == "lockout" and rows[5].lockout.name == "L1", "row5 = L1 lockout")
assert(rows[6].kind == "lockout" and rows[6].lockout.name == "L2", "row6 = L2 lockout")

-- char rows carry weeklies
assert(rows[4].weeklies and rows[4].weeklies.mplusRating == 1200,
    "Zara char row carries weeklies")

-- char rows carry class
assert(rows[1].class == "WARRIOR", "Arel class: " .. tostring(rows[1].class))

print("OK: alts_weeklies_view_test")
