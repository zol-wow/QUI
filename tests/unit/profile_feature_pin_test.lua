local env = dofile("tools/_addon_env.lua")

local h = env.LoadHarness({
    QUI_DB = {
        profileKeys = { ["TestChar - TestRealm"] = "Target" },
        profiles = {
            Target = {
                auraDisplays = { displays = { { id = "target" } } },
                quiGroupFrames = {
                    party = { general = { fontSize = 10 } },
                    clickCast = { keep = true },
                },
                frameAnchoring = {
                    auraDisplay_target = { offsetX = 1 },
                    partyFrames = { offsetX = 2 },
                    unrelated = { offsetX = 3 },
                },
            },
            Source = {
                auraDisplays = { displays = { { id = "source" } } },
                quiGroupFrames = { party = { general = { fontSize = 31 } } },
                raidBuffs = { iconSize = 44 },
                frameAnchoring = {
                    auraDisplay_source = { offsetX = 11 },
                    partyFrames = { offsetX = 12 },
                    raidFrames = { offsetX = 13 },
                },
            },
            Other = {
                auraDisplays = { displays = { { id = "other" } } },
            },
        },
    },
}, { noSeed = true })

local core = h.QUICore
local pins = h.ns.Settings.Pins
local source = h.db.profiles.Source

assert(pins:IsPathPinnable("auraDisplays.displays.1.visibility", "dropdown", "always") == false)
assert(pins:IsPathPinnable("auraDisplays.displays.1.layout.spacing", "slider", 2) == false)
assert(pins:IsPathPinnable("auraDisplays.enabled", "checkbox", true) == true)

local auraOK, auraError = core:PinProfileSelection("Source", "auraDisplays")
assert(auraOK == true, tostring(auraError))
local groupOK, groupError = core:PinProfileSelection("Source", "groupFrames")
assert(groupOK == true, tostring(groupError))
assert(h.db.global.profileFeaturePins.profiles.Target.auraDisplays == "Source")
assert(h.db.global.profileFeaturePins.profiles.Target.groupFrames == "Source")
assert(h.db.global.profileFeaturePins.profiles.Other == nil)

local pinnedAuraOK, pinnedAuraError = core:CopyProfileSelection("Other", { "auraDisplays" })
assert(pinnedAuraOK == false and pinnedAuraError:find("Unpin", 1, true))
local pinnedPartyOK, pinnedPartyError = core:CopyProfileSelection("Other", { "groupFramesParty" })
assert(pinnedPartyOK == false and pinnedPartyError:find("Unpin", 1, true))

source.auraDisplays.displays[1].id = "source-updated"
source.frameAnchoring.auraDisplay_source.offsetX = 21
source.quiGroupFrames.party.general.fontSize = 41
source.frameAnchoring.partyFrames.offsetX = 22
h.db.profile.auraDisplays.displays[1].id = "local-edit"
h.db.profile.quiGroupFrames.party.general.fontSize = 9
h.db.profile.quiGroupFrames.clickCast.keep = "preserved"

assert(pins:ApplyProfileFeaturePins(h.db) == true)
assert(h.db.profile.auraDisplays.displays[1].id == "source-updated")
assert(h.db.profile.frameAnchoring.auraDisplay_target == nil)
assert(h.db.profile.frameAnchoring.auraDisplay_source.offsetX == 21)
assert(h.db.profile.quiGroupFrames.party.general.fontSize == 41)
assert(h.db.profile.quiGroupFrames.party.general.font == "Quazii")
assert(h.db.profile.quiGroupFrames.clickCast.keep == "preserved")
assert(h.db.profile.frameAnchoring.partyFrames.offsetX == 22)
assert(h.db.profile.frameAnchoring.unrelated.offsetX == 3)
h.db.profile.auraDisplays.displays[1].id = "isolated"
assert(source.auraDisplays.displays[1].id == "source-updated")

local unpinOK, unpinError = core:UnpinProfileSelection("auraDisplays")
assert(unpinOK == true, tostring(unpinError))
assert(source.auraDisplays.displays[1].id == "isolated")
source.auraDisplays.displays[1].id = "after-unpin"
assert(pins:ApplyProfileFeaturePins(h.db) == true)
assert(h.db.profile.auraDisplays.displays[1].id == "isolated")
assert(core:GetProfileFeatureSource("auraDisplays") == nil)

source.quiGroupFrames.clickCast = { source = true }
h.db.profile.quiGroupFrames.party.general.fontSize = 52
h.db.profile.quiGroupFrames.clickCast.keep = "target-only"
h.db.profile.frameAnchoring.partyFrames.offsetX = 32

local postInitialize
h.ns.Addon.RegisterPostInitialize = function(_, callback)
    postInitialize = callback
end
env.LoadAddonFile("core/settings/pins_lifecycle.lua", "QUI", h.ns)
assert(type(postInitialize) == "function")
postInitialize(core)
h.db:SetProfile("Other")
assert(source.quiGroupFrames.party.general.fontSize == 52)
assert(source.quiGroupFrames.clickCast.source == true)
assert(source.quiGroupFrames.clickCast.keep == nil)
assert(source.frameAnchoring.partyFrames.offsetX == 32)

local otherPinOK, otherPinError = pins:SetProfileFeatureSource("Source", "groupFrames", h.db)
assert(otherPinOK == true, tostring(otherPinError))
assert(pins:ApplyProfileFeaturePins(h.db) == true)
assert(h.db.profile.quiGroupFrames.party.general.fontSize == 52)
assert(h.db.profile.frameAnchoring.partyFrames.offsetX == 32)

local unsupportedOK, unsupportedError = core:PinProfileSelection("Source", "theme")
assert(unsupportedOK == false and unsupportedError:find("Only Aura", 1, true))
local selfOK, selfError = pins:SetProfileFeatureSource("Other", "groupFrames", h.db)
assert(selfOK == false and selfError:find("current", 1, true))
local chainedOK, chainedError = pins:SetProfileFeatureSource("Target", "groupFrames", h.db, "Other")
assert(chainedOK == false and chainedError:find("not pinned", 1, true))

pins:DropProfile("Source", h.db)
assert(core:GetProfileFeatureSource("groupFrames") == nil)

local mainFile = assert(io.open("core/main.lua", "rb"))
local mainSource = mainFile:read("*a")
mainFile:close()
local initStart = assert(mainSource:find("function QUICore:OnInitialize()", 1, true))
local dualSpec = assert(mainSource:find("LibDualSpec:EnhanceDatabase", initStart, true))
local initApply = assert(mainSource:find("pins:ApplyProfileFeaturePins(self.db)", dualSpec, true))
assert(dualSpec < initApply)
local changeStart = assert(mainSource:find("function QUICore:OnProfileChanged", 1, true))
local runLate = assert(mainSource:find("ns.Migrations.RunLate(self.db)", changeStart, true))
local changeApply = assert(mainSource:find("pins:ApplyProfileFeaturePins(self.db)", runLate, true))
local cleanup = assert(mainSource:find("if self.CleanupFontRegistry then", changeApply, true))
assert(runLate < changeApply and changeApply < cleanup)

local lifecycleFile = assert(io.open("core/settings/pins_lifecycle.lua", "rb"))
local lifecycleSource = lifecycleFile:read("*a")
lifecycleFile:close()
assert(lifecycleSource:find('db.RegisterCallback(Lifecycle, "OnProfileShutdown", "SyncProfileFeatures")', 1, true))
assert(lifecycleSource:find('db.RegisterCallback(Lifecycle, "OnDatabaseShutdown", "SyncProfileFeatures")', 1, true))

local profileIOFile = assert(io.open("core/profile_io.lua", "rb"))
local profileIOSource = profileIOFile:read("*a")
profileIOFile:close()
local fullApply = assert(profileIOSource:find("local function ApplyFullProfilePayload", 1, true))
local fullSync = assert(profileIOSource:find("SettingsPins:SyncProfileFeatureSources(core.db)", fullApply, true))
local fullWipe = assert(profileIOSource:find("for key in pairs(profile) do", fullSync, true))
assert(fullSync < fullWipe)
local selectiveApply = assert(profileIOSource:find("local function RunImportProfileSelection", 1, true))
local selectiveSync = assert(profileIOSource:find("SettingsPins:SyncProfileFeatureSources(core.db)", selectiveApply, true))
local selectiveCopy = assert(profileIOSource:find("local previousProfile = CloneValue(profile)", selectiveSync, true))
assert(selectiveSync < selectiveCopy)

local profilesFile = assert(io.open("core/settings/content/profiles_content.lua", "rb"))
local profilesSource = profilesFile:read("*a")
profilesFile:close()
local resetStart = assert(profilesSource:find("local resetProfileCell", 1, true))
local resetSync = assert(profilesSource:find("core:SyncProfileFeatureSources()", resetStart, true))
local resetCall = assert(profilesSource:find("dbRef:ResetProfile()", resetSync, true))
assert(resetSync < resetCall)
local copyStart = assert(profilesSource:find("local copyDropdown", resetCall, true))
local copySync = assert(profilesSource:find("core:SyncProfileFeatureSources()", copyStart, true))
local copyCall = assert(profilesSource:find("dbRef:CopyProfile(value)", copySync, true))
assert(copySync < copyCall)

print("ok profile feature pin")
