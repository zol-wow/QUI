-- tests/unit/aura_display_templates_test.lua
-- Run: LUA=luajit lua tests/unit/aura_display_templates_test.lua
--
-- Headless coverage for the "New Display" creation paths: the template
-- catalog, the guided-wizard builder, position presets, the Simple Mode
-- summary sentence, and the quick-create defaults fix.

local function fail(msg)
    print("FAIL: aura_display_templates_test - " .. msg)
    os.exit(1)
end

local profile = {}
local ns = {}
ns.L = setmetatable({}, { __index = function(_, k) return k end })
ns.Helpers = {
    GetProfile = function() return profile end,
    GetModuleSettings = function(name, defaults)
        if not profile[name] then
            profile[name] = {}
            for k, v in pairs(defaults or {}) do profile[name][k] = v end
        end
        return profile[name]
    end,
    GetCurrentSpecID = function() return 270 end,
}
_G.UnitClass = function() return "Monk", "MONK" end

assert(loadfile("core/safecall.lua"))("QUI", ns)
assert(loadfile("core/aura_elements.lua"))("QUI", ns)
assert(loadfile("modules/trackers/aura_displays.lua"))("QUI", ns)
assert(loadfile("modules/trackers/aura_display_templates.lua"))("QUI", ns)
assert(loadfile("modules/trackers/settings/aura_displays_content.lua"))("QUI", ns)

local T = ns.QUI_AuraDisplayTemplates
local E = ns.AuraElements
local AD = ns.QUI_AuraDisplays
if type(T) ~= "table" then fail("templates module must export ns.QUI_AuraDisplayTemplates") end

-- Template catalog ---------------------------------------------------------

local list = T.List()
if #list < 6 then fail("expected a real template catalog, got " .. #list) end

for _, tpl in ipairs(list) do
    if type(tpl.id) ~= "string" or type(tpl.name) ~= "string" or type(tpl.desc) ~= "string" then
        fail("template entries need id/name/desc")
    end
    if not T.POSITION_PRESETS[tpl.position] then
        fail(tpl.id .. ": position must be a valid preset zone")
    end
    local display = T.Install(tpl.id)
    if not display then fail(tpl.id .. ": Install must return a display") end
    local bucket = display.auras.elements["*"]
    if #bucket < 1 then fail(tpl.id .. ": installed display must have elements") end
    for _, element in ipairs(bucket) do
        if not E.Validate(element) then
            fail(tpl.id .. ": installed element must validate")
        end
        if (element.iconSize or 0) < 24 then
            fail(tpl.id .. ": templates must not ship tiny icons")
        end
        if element.duration.show ~= true then
            fail(tpl.id .. ": templates must ship duration text on")
        end
    end
    local anchor = profile.frameAnchoring
        and profile.frameAnchoring[AD.ANCHOR_PREFIX .. display.id]
    if not anchor then fail(tpl.id .. ": Install must write a position preset") end
    if anchor.point ~= tpl.position or anchor.relative ~= tpl.position then
        fail(tpl.id .. ": anchor record must use the template zone")
    end
end

local cotank = T.Install("cotankDefensives")
if cotank.unitMode ~= "cotank" then fail("co-tank template must set unitMode cotank") end
if cotank.load.roles.TANK ~= true then fail("co-tank template must load for tanks only") end

if T.Install("nope") ~= nil then fail("unknown template id must return nil") end

-- Guided wizard ------------------------------------------------------------

if #T.GOALS < 5 then fail("expected a real goal list") end

local tracked = T.BuildWizardDisplay({
    goalID = "myBuff",
    spells = { 115151 },
    displayType = "bar",
    iconSize = 40,
    name = "Renewing Mist",
    loadChoice = "spec",
    position = "LEFT",
})
if not tracked then fail("wizard must build a tracked display") end
local element = tracked.auras.elements["*"][1]
if element.mode ~= "tracked" or element.displayType ~= "bar" then
    fail("wizard must honor kind and display type")
end
if element.spells[1] ~= 115151 then fail("wizard must carry chosen spells") end
if element.onlyMine ~= true then fail("myBuff goal must set Only My Cast") end
if element.iconSize ~= 40 then fail("wizard must honor the size preset") end
if element.duration.show ~= true then fail("wizard elements must ship duration text on") end
if tracked.load.specs[270] ~= true then fail("spec load choice must gate on current spec") end
if tracked.unit ~= "player" or tracked.unitMode ~= "token" then
    fail("myBuff goal must default to the player unit")
end
local anchor = profile.frameAnchoring[AD.ANCHOR_PREFIX .. tracked.id]
if not anchor or anchor.point ~= "LEFT" then
    fail("wizard must write the chosen position preset")
end

local strip = T.BuildWizardDisplay({
    goalID = "dispellable",
    loadChoice = "class",
})
local stripElement = strip.auras.elements["*"][1]
if stripElement.mode ~= "filterStrip" or stripElement.auraType ~= "HARMFUL" then
    fail("dispellable goal must build a harmful strip")
end
if stripElement.filterMode ~= "classify"
    or stripElement.classifications.dispellable ~= true then
    fail("dispellable goal must apply the What to Show preset")
end
if strip.load.classes.MONK ~= true then fail("class load choice must gate on player class") end
if strip.name ~= "Debuffs I can dispel" then
    fail("empty wizard name must fall back to the goal name, got " .. tostring(strip.name))
end
local stripAnchor = profile.frameAnchoring[AD.ANCHOR_PREFIX .. strip.id]
if not stripAnchor or stripAnchor.point ~= "BOTTOM" then
    fail("wizard must fall back to the goal's position zone")
end

if T.BuildWizardDisplay({ goalID = "nope" }) ~= nil then
    fail("unknown goal must return nil")
end

-- Always-load choice leaves load conditions empty.
local always = T.BuildWizardDisplay({ goalID = "myShortBuffs", loadChoice = "always" })
if next(always.load.classes) or next(always.load.specs) then
    fail("always load choice must not gate anything")
end

-- What to Show options -----------------------------------------------------

local opts = T.WhatToShowOptions("HARMFUL")
local sawDispellable = false
for _, opt in ipairs(opts) do
    if opt.value == "dispellable" then sawDispellable = true end
end
if not sawDispellable then fail("harmful What to Show options must include dispellable") end

-- Simple Mode summary sentence ----------------------------------------------

local summary = T.BuildElementSummary(element, "Player")
if not summary:find("Renewing Mist", 1, true) and not summary:find("115151", 1, true) then
    fail("tracked summary must mention the spell, got: " .. summary)
end
if not summary:find("only your casts", 1, true) then
    fail("tracked summary must mention Only My Cast, got: " .. summary)
end

local emptyTracked = T.TunedTrackedElement({}, "icon")
local emptySummary = T.BuildElementSummary(emptyTracked, "Target")
if not emptySummary:find("no spells yet", 1, true) then
    fail("empty tracked summary must say no spells yet, got: " .. emptySummary)
end

local stripSummary = T.BuildElementSummary(stripElement, "Player")
if not stripSummary:find("Dispellable by me", 1, true) then
    fail("strip summary must surface What to Show, got: " .. stripSummary)
end
if not stripSummary:find("up to " .. tostring(stripElement.maxIcons), 1, true) then
    fail("strip summary must surface the icon cap, got: " .. stripSummary)
end

if T.BuildElementSummary(nil) ~= "" then fail("summary must tolerate nil elements") end

-- Quick-create ships tuned defaults now --------------------------------------

local Page = ns.QUI_AuraDisplaysOptions
local quick = Page._QuickCreate({ kind = "tracked", name = "Q", unitChoice = "player",
    spellID = 348 })
local quickElement = quick.auras.elements["*"][1]
if quickElement.iconSize ~= 32 then
    fail("quick-create tracked elements must start at 32px, got " .. tostring(quickElement.iconSize))
end
if quickElement.duration.show ~= true then
    fail("quick-create tracked elements must show duration text")
end

local quickStrip = Page._QuickCreate({ kind = "filterStrip", name = "QS", unitChoice = "player" })
local quickStripElement = quickStrip.auras.elements["*"][1]
if quickStripElement.iconSize ~= 32 then
    fail("quick-create strips must use the DefaultBucket defaults")
end

print("OK: aura_display_templates_test")
