local ADDON_NAME, ns = ...

-- UI-free data + builders for the "New Display" dialog (templates, guided
-- wizard) and the Simple Mode summary sentence. Everything here must stay
-- loadable headless: no CreateFrame, no direct WoW API calls without guards.

local T = ns.QUI_AuraDisplayTemplates or {}
ns.QUI_AuraDisplayTemplates = T

local function E()
    return ns.AuraElements
end

local function AD()
    return ns.QUI_AuraDisplays
end

local FALLBACK_ICON = 134400

local function GetSpellName(spellID)
    if spellID and C_Spell and C_Spell.GetSpellName then
        local ok, name = ns.SafeCall("best-effort-style", C_Spell.GetSpellName, spellID)
        if ok and type(name) == "string" and name ~= "" then return name end
    end
    return nil
end

function T.SpellIcon(spellID)
    if spellID and C_Spell and C_Spell.GetSpellTexture then
        local ok, tex = ns.SafeCall("best-effort-style", C_Spell.GetSpellTexture, spellID)
        if ok and tex then return tex end
    end
    return FALLBACK_ICON
end

-- Tuned element constructors ------------------------------------------------
-- Every creation path (templates, wizard, quick create) goes through these so
-- new displays start at the DefaultBucket quality bar: readable icons and
-- duration text on, instead of the bare 16px constructor defaults.

function T.TunedTrackedElement(spells, displayType, auraType, onlyMine, iconSize)
    local elements = E()
    if not elements then return nil end
    -- Normalize to base spell IDs the same way the editor does, so wizard
    -- picks land on the ID the aura engine actually reports.
    local resolved = {}
    local seen = {}
    for i = 1, #(spells or {}) do
        local id = spells[i]
        if type(elements.ResolveTrackedSpellID) == "function" then
            id = elements.ResolveTrackedSpellID(id) or id
        end
        if id and not seen[id] then
            seen[id] = true
            resolved[#resolved + 1] = id
        end
    end
    local element = elements.NewTrackedElement(resolved, displayType or "icon")
    element.auraType = auraType or "HELPFUL"
    element.onlyMine = onlyMine == true
    element.iconSize = iconSize or 32
    element.duration.show = true
    element.duration.fontSize = 12
    element.stack.fontSize = 12
    return element
end

function T.TunedStripElement(auraType, whatToShow, opts)
    local elements = E()
    if not elements then return nil end
    opts = opts or {}
    local element = elements.NewFilterStripElement(auraType or "HELPFUL")
    element.anchor = "TOPLEFT"
    element.growDirection = "RIGHT"
    element.iconSize = opts.iconSize or 32
    element.maxIcons = opts.maxIcons or 8
    element.iconsPerRow = opts.iconsPerRow or 8
    element.duration = { show = true, fontSize = 12, anchor = "CENTER",
        offsetX = 0, offsetY = 0, color = { 1, 1, 1, 1 } }
    element.stack = { show = true, fontSize = 12, anchor = "BOTTOMRIGHT",
        offsetX = -1, offsetY = 1, color = { 1, 1, 1, 1 } }
    if whatToShow and type(elements.ApplyWhatToShow) == "function" then
        elements.ApplyWhatToShow(element, whatToShow)
    end
    if opts.hidePermanent then element.hidePermanent = true end
    if opts.sortRule then element.sortRule = opts.sortRule end
    return element
end

-- Screen position presets ----------------------------------------------------
-- Wizard/template displays get a real position instead of spawning dead
-- center. Records match what Layout Mode writes to profile.frameAnchoring.

local POSITION_PRESETS = {
    TOPLEFT     = { x = 80,  y = -80 },
    TOP         = { x = 0,   y = -80 },
    TOPRIGHT    = { x = -80, y = -80 },
    LEFT        = { x = 80,  y = 0 },
    CENTER      = { x = 0,   y = -120 },
    RIGHT       = { x = -80, y = 0 },
    BOTTOMLEFT  = { x = 80,  y = 220 },
    BOTTOM      = { x = 0,   y = 220 },
    BOTTOMRIGHT = { x = -80, y = 220 },
}
T.POSITION_PRESETS = POSITION_PRESETS

function T.ApplyPositionPreset(displayID, zone)
    local preset = zone and POSITION_PRESETS[zone]
    local ad = AD()
    local H = ns.Helpers
    local profile = H and type(H.GetProfile) == "function" and H.GetProfile() or nil
    if not (preset and ad and profile and displayID) then return false end
    profile.frameAnchoring = profile.frameAnchoring or {}
    profile.frameAnchoring[ad.ANCHOR_PREFIX .. displayID] = {
        point = zone, relative = zone,
        offsetX = preset.x, offsetY = preset.y,
        sizeStable = true,
    }
    return true
end

-- Unit choice ----------------------------------------------------------------

function T.ApplyUnitChoice(display, choice)
    if choice == "__cotank" then
        display.unitMode = "cotank"
        display.unit = nil
    elseif choice == "__name" then
        display.unitMode = "name"
        display.unit = ""
    else
        display.unitMode = "token"
        display.unit = choice or "player"
    end
end

-- Templates ------------------------------------------------------------------
-- Generic by design: built from Blizzard's aura classifications rather than
-- per-spec spell lists, so they keep working across patches. iconSpell only
-- feeds the gallery icon.

local TEMPLATES = {
    {
        id = "myShortBuffs",
        name = ns.L["My Active Buffs"],
        desc = ns.L["Every buff you cast on yourself, shortest first — procs, trinkets, personal cooldowns."],
        iconSpell = 21562,
        unitChoice = "player",
        position = "TOP",
        build = function()
            return { T.TunedStripElement("HELPFUL", "mine",
                { hidePermanent = true, sortRule = "EXPIRY", maxIcons = 12 }) }
        end,
    },
    {
        id = "defensives",
        name = ns.L["Defensives on Me"],
        desc = ns.L["Personal and external defensives active on you, nice and big."],
        iconSpell = 871,
        unitChoice = "player",
        position = "CENTER",
        build = function()
            return { T.TunedStripElement("HELPFUL", "defensives",
                { iconSize = 40, maxIcons = 6 }) }
        end,
    },
    {
        id = "cleanseHelper",
        name = ns.L["Cleanse Helper"],
        desc = ns.L["Debuffs on you that your class can dispel."],
        iconSpell = 527,
        unitChoice = "player",
        position = "BOTTOM",
        roles = { HEALER = true },
        build = function()
            return { T.TunedStripElement("HARMFUL", "dispellable",
                { maxIcons = 6 }) }
        end,
    },
    {
        id = "bossDebuffs",
        name = ns.L["Boss Debuffs on Me"],
        desc = ns.L["Debuffs bosses put on you — the ones fights are about."],
        iconSpell = 5782,
        unitChoice = "player",
        position = "TOP",
        build = function()
            return { T.TunedStripElement("HARMFUL", "boss",
                { iconSize = 36, maxIcons = 6, sortRule = "EXPIRY" }) }
        end,
    },
    {
        id = "crowdControl",
        name = ns.L["Crowd Control on Me"],
        desc = ns.L["Stuns, fears and other loss-of-control effects on you."],
        iconSpell = 118,
        unitChoice = "player",
        position = "CENTER",
        build = function()
            return { T.TunedStripElement("HARMFUL", "crowdControl",
                { iconSize = 40, maxIcons = 4 }) }
        end,
    },
    {
        id = "targetMyDebuffs",
        name = ns.L["My Debuffs on Target"],
        desc = ns.L["Your DoTs and debuffs on your current target, shortest first."],
        iconSpell = 172,
        unitChoice = "target",
        position = "RIGHT",
        roles = { DAMAGER = true },
        build = function()
            return { T.TunedStripElement("HARMFUL", "mine",
                { sortRule = "EXPIRY", maxIcons = 8 }) }
        end,
    },
    {
        id = "cotankDefensives",
        name = ns.L["Co-Tank Defensives"],
        desc = ns.L["Defensives active on the other tank in your group."],
        iconSpell = 355,
        unitChoice = "__cotank",
        position = "LEFT",
        roles = { TANK = true },
        loadRoles = { TANK = true },
        build = function()
            return { T.TunedStripElement("HELPFUL", "defensives",
                { maxIcons = 6 }) }
        end,
    },
    {
        id = "purgeableTarget",
        name = ns.L["Purgeable Buffs on Target"],
        desc = ns.L["Buffs on your target that can be stolen or purged."],
        iconSpell = 30449,
        unitChoice = "target",
        position = "RIGHT",
        build = function()
            return { T.TunedStripElement("HELPFUL", "purgeable",
                { maxIcons = 6 }) }
        end,
    },
}

local function PlayerRole()
    local W = ns.QUI_AuraWizard
    if W and type(W.PlayerRole) == "function" then
        local ok, role = ns.SafeCall("best-effort-style", W.PlayerRole)
        if ok then return role end
    end
    return nil
end

-- Templates matching the player's current role sort first; relative order is
-- otherwise preserved.
function T.List()
    local role = PlayerRole()
    local out = {}
    for i = 1, #TEMPLATES do
        local tpl = TEMPLATES[i]
        if role and tpl.roles and tpl.roles[role] then
            out[#out + 1] = tpl
        end
    end
    for i = 1, #TEMPLATES do
        local tpl = TEMPLATES[i]
        if not (role and tpl.roles and tpl.roles[role]) then
            out[#out + 1] = tpl
        end
    end
    return out
end

function T.TemplateByID(id)
    for i = 1, #TEMPLATES do
        if TEMPLATES[i].id == id then return TEMPLATES[i] end
    end
    return nil
end

local function SeedBucket(display, buildFn)
    local elements = E()
    local ad = AD()
    elements.EnsureSeeded(display.auras, ad.DefaultBucket)
    local bucket = display.auras.elements["*"]
    for i = #bucket, 1, -1 do bucket[i] = nil end
    local built = buildFn and buildFn() or nil
    if type(built) == "table" then
        for i = 1, #built do
            if built[i] then bucket[#bucket + 1] = built[i] end
        end
    end
    return bucket
end

function T.Install(id)
    local tpl = T.TemplateByID(id)
    local ad = AD()
    if not (tpl and ad and E()) then return nil end
    local display = ad.NewDisplay(tpl.name)
    if not display then return nil end
    T.ApplyUnitChoice(display, tpl.unitChoice)
    if tpl.loadRoles then
        for role in pairs(tpl.loadRoles) do
            display.load.roles[role] = true
        end
    end
    SeedBucket(display, tpl.build)
    T.ApplyPositionPreset(display.id, tpl.position)
    return display
end

-- Guided wizard --------------------------------------------------------------

T.SIZE_PRESETS = {
    { key = "S", size = 24, label = ns.L["Small"] },
    { key = "M", size = 32, label = ns.L["Medium"] },
    { key = "L", size = 40, label = ns.L["Large"] },
}

T.GOALS = {
    {
        id = "myBuff",
        name = ns.L["A buff or proc on me"],
        desc = ns.L["Track a specific buff you cast on yourself."],
        kind = "tracked", auraType = "HELPFUL", onlyMine = true,
        unitChoice = "player", position = "CENTER",
    },
    {
        id = "targetDebuff",
        name = ns.L["My debuff on my target"],
        desc = ns.L["Track your DoT or debuff on the current target."],
        kind = "tracked", auraType = "HARMFUL", onlyMine = true,
        unitChoice = "target", position = "RIGHT",
    },
    {
        id = "myShortBuffs",
        name = ns.L["All my short buffs"],
        desc = ns.L["Everything you cast on yourself, shortest first."],
        kind = "strip", auraType = "HELPFUL", whatToShow = "mine",
        hidePermanent = true, sortRule = "EXPIRY",
        unitChoice = "player", position = "TOP",
    },
    {
        id = "dispellable",
        name = ns.L["Debuffs I can dispel"],
        desc = ns.L["Debuffs on you that your class can remove."],
        kind = "strip", auraType = "HARMFUL", whatToShow = "dispellable",
        unitChoice = "player", position = "BOTTOM",
    },
    {
        id = "bossDebuffs",
        name = ns.L["Boss debuffs on me"],
        desc = ns.L["Only what bosses put on you."],
        kind = "strip", auraType = "HARMFUL", whatToShow = "boss",
        unitChoice = "player", position = "TOP",
    },
    {
        id = "otherPlayer",
        name = ns.L["Another player's auras"],
        desc = ns.L["Watch the co-tank, a party member, or a named player."],
        kind = "strip", auraType = "HELPFUL", whatToShow = "defensives",
        unitChoice = "__cotank", position = "LEFT",
    },
}

function T.GoalByID(id)
    for i = 1, #T.GOALS do
        if T.GOALS[i].id == id then return T.GOALS[i] end
    end
    return nil
end

local function PlayerClassToken()
    if type(UnitClass) ~= "function" then return nil end
    local ok, _, token = ns.SafeCall("best-effort-style", UnitClass, "player")
    if ok and type(token) == "string" then return token end
    return nil
end

local function PlayerSpecID()
    local H = ns.Helpers
    if H and type(H.GetCurrentSpecID) == "function" then
        local ok, spec = ns.SafeCall("best-effort-style", H.GetCurrentSpecID)
        if ok then return spec end
    end
    return nil
end

-- state = { goalID, name, spells, whatToShow, displayType, iconSize,
--           unitChoice, position, loadChoice = "always"|"class"|"spec" }
function T.BuildWizardDisplay(state)
    local goal = state and T.GoalByID(state.goalID)
    local ad = AD()
    if not (goal and ad and E()) then return nil end

    local name = state.name
    if type(name) ~= "string" or name == "" then
        name = (state.spells and state.spells[1] and GetSpellName(state.spells[1]))
            or goal.name
    end
    local display = ad.NewDisplay(name)
    if not display then return nil end

    T.ApplyUnitChoice(display, state.unitChoice or goal.unitChoice)

    if state.loadChoice == "class" then
        local class = PlayerClassToken()
        if class then display.load.classes[class] = true end
    elseif state.loadChoice == "spec" then
        local spec = PlayerSpecID()
        if spec then display.load.specs[spec] = true end
    end

    SeedBucket(display, function()
        if goal.kind == "tracked" then
            return { T.TunedTrackedElement(state.spells, state.displayType or "icon",
                goal.auraType, goal.onlyMine, state.iconSize) }
        end
        return { T.TunedStripElement(goal.auraType,
            state.whatToShow or goal.whatToShow, {
                iconSize = state.iconSize,
                hidePermanent = goal.hidePermanent,
                sortRule = goal.sortRule,
            }) }
    end)

    T.ApplyPositionPreset(display.id, state.position or goal.position)
    return display
end

-- Simple Mode summary sentence ----------------------------------------------
-- Rendered above an expanded element in the editor; reads back the element's
-- real settings in plain language so the form below stays learnable.

local WHAT_TO_SHOW_SUMMARY = {
    all          = ns.L["All"],
    mine         = ns.L["Only my auras"],
    defensives   = ns.L["Defensives"],
    important    = ns.L["Important"],
    purgeable    = ns.L["Purgeable"],
    dispellable  = ns.L["Dispellable by me"],
    crowdControl = ns.L["Crowd control"],
    boss         = ns.L["Boss debuffs"],
    roleBoss     = ns.L["Role-relevant boss debuffs"],
    whitelist    = ns.L["Specific spells"],
    custom       = ns.L["Custom…"],
}

function T.WhatToShowLabel(key)
    return WHAT_TO_SHOW_SUMMARY[key] or WHAT_TO_SHOW_SUMMARY.custom
end

function T.WhatToShowOptions(auraType)
    local elements = E()
    local out = {}
    if not (elements and type(elements.WhatToShowKeys) == "function") then return out end
    for _, key in ipairs(elements.WhatToShowKeys(auraType)) do
        out[#out + 1] = { value = key, text = WHAT_TO_SHOW_SUMMARY[key] or key }
    end
    return out
end

local GROW_SUMMARY = {
    LEFT = ns.L["Left"], RIGHT = ns.L["Right"], CENTER = ns.L["Center"],
    UP = ns.L["Up"], DOWN = ns.L["Down"],
}

local TRACKED_TYPE_SUMMARY = {
    icon       = ns.L["an icon"],
    square     = ns.L["a colored square"],
    bar        = ns.L["a bar"],
    healthTint = ns.L["a health bar tint"],
    border     = ns.L["a colored border"],
}

local HIGHLIGHT = "|cFFFFFFFF%s|r"

-- WoW's string.format understands positional specifiers (%1$s); plain Lua 5.1
-- does not, so headless runs fall back to manual substitution.
local function FormatPositional(fmt, ...)
    local ok, out = pcall(string.format, fmt, ...)
    if ok then return out end
    local args = { ... }
    return (fmt:gsub("%%(%d+)%$(%a)", function(n, kind)
        local value = args[tonumber(n)]
        if kind == "d" then
            return tostring(math.floor(tonumber(value) or 0))
        end
        return tostring(value)
    end))
end

function T.BuildElementSummary(element, unitText)
    if type(element) ~= "table" then return "" end
    local elements = E()
    unitText = (type(unitText) == "string" and unitText ~= "") and unitText or ns.L["Player"]
    local unit = HIGHLIGHT:format(unitText)

    if element.mode == "filterStrip" then
        local maxIcons = tonumber(element.maxIcons) or 0
        local count = maxIcons > 0
            and string.format(ns.L["up to %d"], maxIcons)
            or ns.L["all"]
        local kind = element.auraType == "HARMFUL" and ns.L["debuffs"] or ns.L["buffs"]
        local derived = elements and type(elements.DeriveWhatToShow) == "function"
            and elements.DeriveWhatToShow(element) or "all"
        local what = WHAT_TO_SHOW_SUMMARY[derived] or WHAT_TO_SHOW_SUMMARY.custom
        local grow = GROW_SUMMARY[element.growDirection] or GROW_SUMMARY.RIGHT
        return FormatPositional(ns.L["Shows %1$s %2$s on %3$s matching '%4$s', growing %5$s."],
            count, HIGHLIGHT:format(kind), unit, HIGHLIGHT:format(what), grow)
    end

    if element.mode == "tracked" then
        local typePhrase = TRACKED_TYPE_SUMMARY[element.displayType or "icon"]
            or TRACKED_TYPE_SUMMARY.icon
        local spells = element.spells or {}
        local spellText
        if spells[1] then
            spellText = GetSpellName(spells[1]) or (ns.L["Spell"] .. " " .. tostring(spells[1]))
            if #spells > 1 then
                spellText = spellText .. " +" .. tostring(#spells - 1)
            end
        else
            spellText = ns.L["no spells yet"]
        end
        local suffix = element.onlyMine and ns.L[" — only your casts"] or ""
        return FormatPositional(ns.L["Shows %1$s for %2$s on %3$s%4$s."],
            typePhrase, HIGHLIGHT:format(spellText), unit, suffix)
    end

    return ""
end

return T
