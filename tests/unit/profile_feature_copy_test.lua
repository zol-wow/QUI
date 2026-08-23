local env = dofile("tools/_addon_env.lua")

local seed = {
    QUI_DB = {
        profileKeys = { ["TestChar - TestRealm"] = "Target" },
        profiles = {
            Target = {
                auraDisplays = {
                    enabled = false,
                    displays = { { id = "old", name = "Old" } },
                },
                quiGroupFrames = {
                    party = { staleOnly = true },
                    raid = { staleOnly = true },
                    clickCast = { targetLegacy = true },
                },
                raidBuffs = { targetOnly = true },
                frameAnchoring = {
                    auraDisplay_old = { offsetX = 90 },
                    auraDisplay_stale = { offsetX = 91 },
                    partyFrames = { offsetX = 92 },
                    raidFrames = { offsetX = 93 },
                    spotlightFrames = { offsetX = 94 },
                    missingRaidBuffs = { offsetX = 95 },
                    unrelated = { offsetX = 96 },
                },
            },
            Source = {
                auraDisplays = {
                    displays = { { id = "source", name = "Source" } },
                },
                quiGroupFrames = {
                    party = { general = { fontSize = 31 } },
                    raid = { general = { fontSize = 42 } },
                    clickCast = { sourceLegacy = true },
                },
                raidBuffs = { iconSize = 55 },
                frameAnchoring = {
                    auraDisplay_source = { offsetX = 10 },
                    partyFrames = { offsetX = 11 },
                    raidFrames = { offsetX = 12 },
                    spotlightFrames = { offsetX = 13 },
                    missingRaidBuffs = { offsetX = 14 },
                    sourceUnrelated = { offsetX = 15 },
                },
            },
        },
    },
}

local h = env.LoadHarness(seed, { noSeed = true })
local core = h.QUICore
local source = h.db.profiles.Source
local setProfileCalls = 0
local refreshCalls = 0
local pinCalls = 0
local originalSetProfile = h.db.SetProfile

h.db.SetProfile = function(db, name)
    setProfileCalls = setProfileCalls + 1
    return originalSetProfile(db, name)
end
h.ns.Registry = {
    RefreshByCategories = function(_, categoryIDs)
        refreshCalls = refreshCalls + 1
        assert(type(categoryIDs) == "table" and #categoryIDs == 1)
    end,
}
h.ns.Settings = {
    Pins = {
        HandleSelectiveImport = function(_, db, categories)
            pinCalls = pinCalls + 1
            assert(db == h.db and type(categories) == "table" and #categories == 1)
        end,
    },
}

h.db.char.clickCast.bindings.keep = { spellID = 123 }

local auraOK, auraMessage = core:CopyProfileSelection(" Source ", { "auraDisplays" })
assert(auraOK == true, tostring(auraMessage))
assert(h.db.profile.auraDisplays.enabled == true, "inactive source defaults were not materialized")
assert(h.db.profile.auraDisplays.displays[1].id == "source", "source aura displays were not copied")
assert(h.db.profile.auraDisplays.displays[2] == nil, "aura display replacement retained stale target entries")
assert(h.db.profile.frameAnchoring.auraDisplay_old == nil, "stale target aura anchor survived")
assert(h.db.profile.frameAnchoring.auraDisplay_stale == nil, "second stale target aura anchor survived")
assert(h.db.profile.frameAnchoring.auraDisplay_source.offsetX == 10, "source aura anchor was not copied")
assert(h.db.profile.frameAnchoring.sourceUnrelated == nil, "unrelated source anchor was copied")
assert(h.db.profile.frameAnchoring.unrelated.offsetX == 96, "unrelated target anchor was changed")
assert(rawget(source.auraDisplays, "enabled") == nil, "copy materialized defaults into the stored source")
h.db.profile.auraDisplays.displays[1].name = "Changed"
h.db.profile.frameAnchoring.auraDisplay_source.offsetX = 110
assert(source.auraDisplays.displays[1].name == "Source", "copied aura display aliases the source")
assert(source.frameAnchoring.auraDisplay_source.offsetX == 10, "copied aura anchor aliases the source")

h.db.profile.frameAnchoring.partyFrames = { offsetX = 20 }
h.db.profile.frameAnchoring.raidFrames = { offsetX = 21 }
h.db.profile.frameAnchoring.spotlightFrames = { offsetX = 22 }
h.db.profile.frameAnchoring.missingRaidBuffs = { offsetX = 23 }
local partyOK, partyMessage = core:CopyProfileSelection("Source", { "groupFramesParty" })
assert(partyOK == true, tostring(partyMessage))
assert(h.db.profile.quiGroupFrames.party.general.fontSize == 31, "party settings were not copied")
assert(h.db.profile.quiGroupFrames.party.general.font == "Quazii", "party defaults were not materialized")
assert(h.db.profile.quiGroupFrames.party.staleOnly == nil, "party replacement retained stale target settings")
assert(h.db.profile.frameAnchoring.partyFrames.offsetX == 11, "party anchor was not copied")
assert(h.db.profile.frameAnchoring.raidFrames.offsetX == 21, "party copy changed the raid anchor")
assert(h.db.profile.frameAnchoring.spotlightFrames.offsetX == 22, "party copy changed the spotlight anchor")
assert(h.db.profile.frameAnchoring.missingRaidBuffs.offsetX == 23, "party copy changed the missing-buff anchor")
h.db.profile.quiGroupFrames.party.general.fontSize = 32
assert(source.quiGroupFrames.party.general.fontSize == 31, "copied party settings alias the source")

h.db.profile.frameAnchoring.partyFrames = { offsetX = 30 }
h.db.profile.frameAnchoring.raidFrames = { offsetX = 31 }
h.db.profile.frameAnchoring.spotlightFrames = { offsetX = 32 }
h.db.profile.frameAnchoring.missingRaidBuffs = { offsetX = 33 }
local raidOK, raidMessage = core:CopyProfileSelection("Source", { "groupFramesRaid" })
assert(raidOK == true, tostring(raidMessage))
assert(h.db.profile.quiGroupFrames.raid.general.fontSize == 42, "raid settings were not copied")
assert(h.db.profile.frameAnchoring.partyFrames.offsetX == 30, "raid copy changed the party anchor")
assert(h.db.profile.frameAnchoring.raidFrames.offsetX == 12, "raid anchor was not copied")
assert(h.db.profile.frameAnchoring.spotlightFrames.offsetX == 13, "spotlight anchor was not copied")
assert(h.db.profile.frameAnchoring.missingRaidBuffs.offsetX == 33, "raid copy changed the missing-buff anchor")

h.db.profile.frameAnchoring.partyFrames = { offsetX = 40 }
h.db.profile.frameAnchoring.raidFrames = { offsetX = 41 }
h.db.profile.frameAnchoring.spotlightFrames = { offsetX = 42 }
h.db.profile.frameAnchoring.missingRaidBuffs = { offsetX = 43 }
local groupOK, groupMessage = core:CopyProfileSelection("Source", { "groupFrames" })
assert(groupOK == true, tostring(groupMessage))
assert(h.db.profile.frameAnchoring.partyFrames.offsetX == 11, "group copy missed the party anchor")
assert(h.db.profile.frameAnchoring.raidFrames.offsetX == 12, "group copy missed the raid anchor")
assert(h.db.profile.frameAnchoring.spotlightFrames.offsetX == 13, "group copy missed the spotlight anchor")
assert(h.db.profile.frameAnchoring.missingRaidBuffs.offsetX == 14, "group copy missed the missing-buff anchor")
assert(h.db.profile.raidBuffs.iconSize == 55, "group copy missed raid-buff settings")
assert(h.db.profile.raidBuffs.targetOnly == nil, "group replacement retained stale raid-buff settings")
assert(h.db.profile.quiGroupFrames.clickCast.targetLegacy == true, "group copy changed legacy profile click-cast settings")
assert(h.db.profile.quiGroupFrames.clickCast.sourceLegacy == nil, "group copy imported legacy source click-cast settings")
assert(h.db.char.clickCast.bindings.keep.spellID == 123, "profile copy changed character click-cast bindings")

local currentOK, currentError = core:CopyProfileSelection("Target", { "auraDisplays" })
assert(currentOK == false and currentError:find("current", 1, true), "current source profile was not rejected")
local missingOK, missingError = core:CopyProfileSelection("Missing", { "auraDisplays" })
assert(missingOK == false and missingError:find("No profile", 1, true), "missing source profile was not rejected")
local invalidOK, invalidError = core:CopyProfileSelection("Source", { "auraDisplays", "notAFeature" })
assert(invalidOK == false and invalidError:find("Unknown", 1, true), "invalid category was not rejected")
local emptyOK, emptyError = core:CopyProfileSelection("Source", {})
assert(emptyOK == false and emptyError:find("at least one", 1, true), "empty category selection was not rejected")

assert(h.db:GetCurrentProfile() == "Target", "copy changed the active profile")
assert(setProfileCalls == 0, "copy called SetProfile")
assert(refreshCalls == 4, "successful copies did not use category refresh")
assert(pinCalls == 4, "successful copies did not use selective pin handling")

h.db.profile.frameAnchoring.auraDisplay_source = { offsetX = 210 }
local importOK, importMessage = core:ImportProfileSelectionFromValidatedPayload({
    auraDisplays = { displays = { { id = "imported" } } },
    frameAnchoring = { auraDisplay_source = { offsetX = 310 } },
}, { "auraDisplays" })
assert(importOK == true, tostring(importMessage))
assert(h.db.profile.auraDisplays.displays[1].id == "imported", "normal selective import missed aura settings")
assert(h.db.profile.frameAnchoring.auraDisplay_source.offsetX == 210,
    "normal selective import copied profile-only feature anchors")

print("ok profile feature copy")
