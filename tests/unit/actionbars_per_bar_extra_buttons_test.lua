-- tests/unit/actionbars_per_bar_extra_buttons_test.lua
-- Run: lua tests/unit/actionbars_per_bar_extra_buttons_test.lua

local function readFile(path)
    local fh = assert(io.open(path, "rb"), "failed to open " .. path)
    local text = fh:read("*a")
    fh:close()
    return text
end

local perBarSource = readFile("QUI_ActionBars/actionbars/settings/action_bars_per_bar.lua")
local actionBarsSource = readFile("QUI_ActionBars/actionbars/actionbars_per_bar_builders.lua")
local helpersSource = readFile("QUI_ActionBars/actionbars/actionbars_helpers.lua")
local eventsSource = readFile("QUI_ActionBars/actionbars/actionbars_events.lua")
local publicSource = readFile("QUI_ActionBars/actionbars/actionbars_public.lua")
local mouseoverSource = readFile("QUI_ActionBars/actionbars/actionbars_mouseover.lua")
local layoutSource = readFile("QUI_ActionBars/actionbars/actionbars_layout.lua")
local contentSource = readFile("QUI_ActionBars/actionbars/settings/action_bars_content.lua")
local hudVisibilitySource = readFile("QUI_CDM/cdm/hud_visibility.lua")

local function assertContains(source, needle, message)
    assert(source:find(needle, 1, true), message .. " (missing `" .. needle .. "`)")
end

assertContains(perBarSource,
    '{ value = "extraActionButton", text = ns.L["Extra Action Button"] }',
    "Per-Bar selector should include the Extra Action Button")
assertContains(perBarSource,
    '{ value = "zoneAbility",       text = ns.L["Zone Ability"] }',
    "Per-Bar selector should include Zone Ability")
assertContains(perBarSource,
    '"extraActionButton", "zoneAbility"',
    "Per-Bar search lookup keys should include the extra button entries")
assertContains(perBarSource,
    'local SPECIAL_BUTTON_OPTION_KEYS = { extraActionButton = true, zoneAbility = true }',
    "Per-Bar copy-all behavior should identify special button options")
assertContains(perBarSource,
    'if sourceIsSpecial == destinationIsSpecial then',
    "Apply-to-all should not copy regular bar settings into special button settings")
assertContains(perBarSource,
    'if _G.QUI_RefreshExtraButtons then',
    "Apply-to-all should refresh special button frames after copying settings")

assertContains(actionBarsSource,
    'local SPECIAL_BUTTON_BARS = { extraActionButton = true, zoneAbility = true }',
    "Per-Bar settings builder should identify special button bars")
assertContains(actionBarsSource,
    'local function BuildSpecialButtonSettings(content, barKey, barDB)',
    "Per-Bar settings builder should render special button controls")
assertContains(actionBarsSource,
    'local function ShowSpecialButtonReloadPrompt()',
    "Special button management toggles should prompt for reload")
assertContains(actionBarsSource,
    'GUI:CreateFormToggle(body, ns.L["Enabled"], "enabled", barDB, RefreshSpecialButtonEnabled',
    "Special button Enabled control should use a toggle")
assertContains(actionBarsSource,
    'GUI:CreateFormToggle(body, ns.L["Hide Artwork"], "hideArtwork", barDB, RefreshSpecialButton',
    "Special button Hide Artwork control should use a toggle")
assertContains(actionBarsSource,
    'GUI:CreateFormSlider(body, ns.L["Scale"]',
    "Special button Scale control should use a slider")
assertContains(actionBarsSource,
    '_G.QUI_RefreshExtraButtons',
    "Special button changes should refresh the managed extra button frames")

assertContains(helpersSource,
    'local LURA_MYTHIC_ENCOUNTER_ID = 3183',
    "Context visibility should key Mythic L'ura to the Midnight Falls encounter ID")
assertContains(helpersSource,
    'local MYTHIC_RAID_DIFFICULTY_ID = 16',
    "Context visibility should require Mythic raid difficulty for L'ura")
assertContains(helpersSource,
    'local MYTHIC_KEYSTONE_DIFFICULTY_ID = 8',
    "Context visibility should recognize Mythic+ difficulty")
assertContains(helpersSource,
    'function GetActionBarContentType()',
    "Context visibility should classify current content type")
assertContains(helpersSource,
    'function ActionBarContentTypeMatches(barSettings)',
    "Context visibility should match scoped content type toggles")
assertContains(helpersSource,
    'function RefreshActionBarContextVisibility()',
    "Context visibility should cache location state")
assertContains(helpersSource,
    'function ShouldForceShowForActionBarContext(barKey)',
    "Context visibility should expose a force-visible predicate")
assertContains(helpersSource,
    'or ShouldForceShowForActionBarContext(barKey)',
    "Mouseover fade suspension should include context visibility")

for _, eventName in ipairs({
    "ZONE_CHANGED_NEW_AREA",
    "ZONE_CHANGED",
    "ZONE_CHANGED_INDOORS",
    "PLAYER_DIFFICULTY_CHANGED",
    "UPDATE_INSTANCE_INFO",
    "CHALLENGE_MODE_START",
    "CHALLENGE_MODE_COMPLETED",
    "CHALLENGE_MODE_RESET",
    "ENCOUNTER_START",
    "ENCOUNTER_END",
}) do
    assertContains(publicSource, 'ownedEventFrame:RegisterEvent("' .. eventName .. '")',
        "Action bars should register " .. eventName)
    assertContains(eventsSource, eventName,
        "Action bars event handler should react to " .. eventName)
end

assertContains(eventsSource,
    'SetActionBarEncounterVisibilityContext(encounterID, encounterName, difficultyID)',
    "ENCOUNTER_START should capture encounter context")
assertContains(eventsSource,
    'ClearActionBarEncounterVisibilityContext(encounterID)',
    "ENCOUNTER_END should clear encounter context")
assertContains(layoutSource,
    'ShouldForceShowForActionBarContext(barKey)',
    "Owned action bar fade path should honor context visibility")
assertContains(mouseoverSource,
    'ShouldForceShowForActionBarContext(barKey)',
    "Special/non-owned fade path should honor context visibility")
for _, eventName in ipairs({
    "PLAYER_STARTED_MOVING",
    "PLAYER_STOPPED_MOVING",
    "PLAYER_IMPULSE_APPLIED",
    "PLAYER_IS_GLIDING_CHANGED",
}) do
    assertContains(hudVisibilitySource, 'visibilityEventFrame:RegisterEvent("' .. eventName .. '")',
        "HUD visibility should refresh action bars when " .. eventName .. " can change flying/skyriding state")
end
assertContains(actionBarsSource,
    'ns.L["Context Visibility"]',
    "Per-Bar settings should expose context visibility controls")
assertContains(actionBarsSource,
    '"showInOpenWorld"',
    "Per-Bar settings should expose the open-world visibility toggle")
assertContains(actionBarsSource,
    '"showInDungeons"',
    "Per-Bar settings should expose the dungeon visibility toggle")
assertContains(actionBarsSource,
    '"showInMythicPlus"',
    "Per-Bar settings should expose the Mythic+ visibility toggle")
assertContains(actionBarsSource,
    '"showInRaids"',
    "Per-Bar settings should expose the raid visibility toggle")
assertContains(actionBarsSource,
    '"showInMythicRaids"',
    "Per-Bar settings should expose the Mythic raid visibility toggle")
assertContains(actionBarsSource,
    '"showOnLuraMythic"',
    "Per-Bar settings should expose the Mythic L'ura toggle")
assert(not contentSource:find('"showOnLuraMythic"', 1, true),
    "Mouseover Hide tab should not expose a global Mythic L'ura toggle")

assert(not contentSource:find("locationMatchText", 1, true),
    "Mouseover Hide tab should not expose the ambiguous location matcher field")

local oldIsInInstance = IsInInstance
local oldGetInstanceInfo = GetInstanceInfo
local oldChallengeMode = C_ChallengeMode

local actionBarsDB = { fade = {}, bars = { bar5 = {}, bar6 = {} } }
local helperNS = {
    Helpers = {
        CreateDBGetter = function()
            return function() return actionBarsDB end
        end,
    },
}
assert(loadfile("QUI_ActionBars/actionbars/actionbars_env.lua"))("QUI", helperNS)
helperNS.ActionBarsEnv.Helpers = helperNS.Helpers
helperNS.ActionBarsEnv.ActionBarsOwned = { contextVisibility = {} }
assert(loadfile("QUI_ActionBars/actionbars/actionbars_helpers.lua"))("QUI", helperNS)
local helperEnv = helperNS.ActionBarsEnv

local function setInstanceContext(inInstance, instanceType, difficultyID, challengeActive)
    IsInInstance = function() return inInstance, instanceType end
    GetInstanceInfo = function() return "Instance", instanceType, difficultyID end
    C_ChallengeMode = {
        IsChallengeModeActive = function() return challengeActive end,
    }
end

local function assertContentType(inInstance, instanceType, difficultyID, challengeActive, expected)
    setInstanceContext(inInstance, instanceType, difficultyID, challengeActive)
    assert(helperEnv.GetActionBarContentType() == expected,
        "expected content type " .. tostring(expected) .. ", got " .. tostring(helperEnv.GetActionBarContentType()))
end

assertContentType(false, "none", nil, false, "openWorld")
assert(helperEnv.ActionBarContentTypeMatches({ showInOpenWorld = true }) == true,
    "open-world toggle should match open-world content")
assert(helperEnv.ActionBarContentTypeMatches({ showInDungeons = true }) == false,
    "dungeon toggle should not match open-world content")

assertContentType(true, "party", 23, false, "dungeon")
assert(helperEnv.ActionBarContentTypeMatches({ showInDungeons = true }) == true,
    "dungeon toggle should match non-Mythic+ dungeons")
assert(helperEnv.ActionBarContentTypeMatches({ showInMythicPlus = true }) == false,
    "Mythic+ toggle should not match non-Mythic+ dungeons")

assertContentType(true, "party", 8, false, "mythicPlus")
assert(helperEnv.ActionBarContentTypeMatches({ showInMythicPlus = true }) == true,
    "Mythic+ toggle should match keystone difficulty")
assert(helperEnv.ActionBarContentTypeMatches({ showInDungeons = true }) == false,
    "dungeon toggle should not implicitly match Mythic+")

assertContentType(true, "raid", 15, false, "raid")
assert(helperEnv.ActionBarContentTypeMatches({ showInRaids = true }) == true,
    "raid toggle should match non-Mythic raids")
assert(helperEnv.ActionBarContentTypeMatches({ showInMythicRaids = true }) == false,
    "Mythic raid toggle should not match non-Mythic raids")

assertContentType(true, "raid", 16, false, "mythicRaid")
assert(helperEnv.ActionBarContentTypeMatches({ showInMythicRaids = true }) == true,
    "Mythic raid toggle should match Mythic raids")
assert(helperEnv.ActionBarContentTypeMatches({ showInRaids = true }) == false,
    "raid toggle should not implicitly match Mythic raids")

setInstanceContext(false, "none", nil, false)
actionBarsDB.bars.bar5 = { showOnLuraMythic = false }
actionBarsDB.bars.bar6 = { showOnLuraMythic = true }
helperEnv.SetActionBarEncounterVisibilityContext(3183, "L'ura", 16)
helperEnv.RefreshActionBarContextVisibility()
assert(helperEnv.ShouldForceShowForActionBarContext("bar5") == false,
    "L'ura encounter should not force-show bars without the per-bar toggle")
assert(helperEnv.ShouldForceShowForActionBarContext("bar6") == true,
    "L'ura encounter should force-show only the bar with the per-bar toggle")
helperEnv.ClearActionBarEncounterVisibilityContext(3183)
helperEnv.RefreshActionBarContextVisibility()
assert(helperEnv.ShouldForceShowForActionBarContext("bar6") == false,
    "ending L'ura should clear the force-show state")

IsInInstance = oldIsInInstance
GetInstanceInfo = oldGetInstanceInfo
C_ChallengeMode = oldChallengeMode

print("OK: actionbars_per_bar_extra_buttons_test")
