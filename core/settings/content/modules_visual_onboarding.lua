---------------------------------------------------------------------------
-- QUI Modules — Visual onboarding (Phase 2)
--
-- Registers feature manifests with moduleEntry blocks for every static
-- visual module that already exists as a Layout Mode element. The
-- isEnabled/setEnabled callbacks proxy through ns.QUI_LayoutMode's
-- element registry, so the canonical DB write path is the LM element's
-- existing setEnabled closure (no duplication).
---------------------------------------------------------------------------
local ADDON_NAME, ns = ...
local Settings = ns.Settings
local Registry = Settings and Settings.Registry
local Schema = Settings and Settings.Schema

if not (Registry and Schema
    and type(Registry.RegisterFeature) == "function"
    and type(Schema.Feature) == "function") then
    return
end

---------------------------------------------------------------------------
-- Shared proxy helpers
---------------------------------------------------------------------------

local function MakeModuleEntry(key, group, label, caption, combatLocked, hidden)
    return {
        group        = group,
        label        = label,
        caption      = caption,
        combatLocked = combatLocked,
        hidden       = hidden,
        isEnabled    = function()
            local um = ns.QUI_LayoutMode
            if not um or not um.IsElementEnabled then return false end
            return um:IsElementEnabled(key) or false
        end,
        setEnabled   = function(val)
            local um = ns.QUI_LayoutMode
            if um and um.SetElementEnabled then
                um:SetElementEnabled(key, val)
                if ns.QUI_Modules then
                    ns.QUI_Modules:NotifyChanged(key)
                end
            end
        end,
    }
end

--- Register a feature with a moduleEntry proxy.
-- If a feature with this id already exists (e.g., from layoutmode_utils.lua
-- stubs), attach moduleEntry to it rather than creating a duplicate.
local function RegisterModuleFeature(key, group, label, caption, combatLocked, hidden)
    local existing = Registry:GetFeature(key)
    if existing then
        existing.moduleEntry = MakeModuleEntry(key, group, label, caption, combatLocked, hidden)
        return
    end
    Registry:RegisterFeature(Schema.Feature({
        id         = key,
        moverKey   = key,
        category   = "global",
        moduleEntry = MakeModuleEntry(key, group, label, caption, combatLocked, hidden),
    }))
end

---------------------------------------------------------------------------
-- Class/spec-gated hidden callbacks
---------------------------------------------------------------------------

local function HiddenUnlessDisciplinePriest()
    local _, class = UnitClass("player")
    if class ~= "PRIEST" then return true end
    local spec = GetSpecialization and GetSpecialization()
    if spec then
        local _, name = GetSpecializationInfo(spec)
        return name ~= "Discipline"
    end
    return true
end

local function HiddenUnlessShaman()
    local _, class = UnitClass("player")
    return class ~= "SHAMAN"
end

---------------------------------------------------------------------------
-- Static visual module inventory
--
-- Each entry:  { key, group, label, caption, combatLocked [, hidden] }
--
-- Rules:
--   combatLocked = true  — frame-touching toggles (all visual modules)
--   combatLocked = false — lightweight event-handler toggles only
---------------------------------------------------------------------------

local VISUAL_MODULES = {

    ---------------------------------------------------------------------------
    -- Display
    ---------------------------------------------------------------------------
    {
        key = "buffFrame", group = "Display", label = "Buff Frame",
        caption = "Active beneficial auras with custom borders.",
        combatLocked = true,
    },
    {
        key = "debuffFrame", group = "Display", label = "Debuff Frame",
        caption = "Active harmful auras with custom borders.",
        combatLocked = true,
    },
    {
        key = "chatFrame1", group = "Display", label = "Chat Frame",
        caption = "Custom chat frame replacing the default window.",
        combatLocked = true,
    },
    {
        key = "lootFrame", group = "Display", label = "Loot Frame",
        caption = "Custom loot window displayed when looting enemies.",
        combatLocked = true,
    },
    {
        key = "lootRollAnchor", group = "Display", label = "Loot Roll Anchor",
        caption = "Repositions the Need/Greed loot-roll dialog.",
        combatLocked = true,
    },
    {
        key = "alertAnchor", group = "Display", label = "Alert Anchor",
        caption = "Anchor for raid and encounter alert messages.",
        combatLocked = true,
    },
    {
        key = "toastAnchor", group = "Display", label = "Toast Anchor",
        caption = "Anchor for achievement and event toast notifications.",
        combatLocked = true,
    },
    {
        key = "bnetToastAnchor", group = "Display", label = "BNet Toast Anchor",
        caption = "Anchor for Battle.net friend-activity toast notifications.",
        combatLocked = true,
    },
    {
        key = "powerBarAlt", group = "Display", label = "Encounter Power Bar",
        caption = "Skinned alternate power bar shown during certain encounters.",
        combatLocked = true,
    },
    {
        key = "tooltipAnchor", group = "Display", label = "Tooltip Anchor",
        caption = "Repositions the game tooltip to a custom screen position.",
        combatLocked = true,
    },

    ---------------------------------------------------------------------------
    -- QoL
    ---------------------------------------------------------------------------
    {
        key = "crosshair", group = "QoL", label = "Crosshair",
        caption = "Reticle drawn at the screen center for precise targeting.",
        combatLocked = true,
    },
    {
        key = "skyriding", group = "QoL", label = "Skyriding HUD",
        caption = "Momentum and Second Wind HUD for Skyriding mounts.",
        combatLocked = true,
    },
    {
        key = "xpTracker", group = "QoL", label = "XP Tracker",
        caption = "Compact bar showing current XP or reputation progress.",
        combatLocked = true,
    },
    {
        key = "rangeCheck", group = "QoL", label = "Range Check",
        caption = "Indicator that alerts when your target steps out of range.",
        combatLocked = false,
    },
    {
        key = "actionTracker", group = "QoL", label = "Action Tracker",
        caption = "Tracks and displays the last ability or action used.",
        combatLocked = false,
    },
    {
        key = "focusCastAlert", group = "QoL", label = "Focus Cast Alert",
        caption = "Highlights when your focus target begins casting.",
        combatLocked = false,
    },
    {
        key = "petWarning", group = "QoL", label = "Pet Warning",
        caption = "Warns when your pet enters or exits combat unexpectedly.",
        combatLocked = false,
    },
    {
        key = "preyTracker", group = "QoL", label = "Prey Tracker",
        caption = "Tracks a designated enemy target across reloads.",
        combatLocked = false,
    },
    {
        key = "atonementCounter", group = "QoL", label = "Atonement Counter",
        caption = "Discipline Priest Atonement uptime tracker.",
        combatLocked = true,
        hidden = HiddenUnlessDisciplinePriest,
    },

    ---------------------------------------------------------------------------
    -- Instance
    ---------------------------------------------------------------------------
    {
        key = "combatTimer", group = "Instance", label = "Combat Timer",
        caption = "Tracks how long you have been in the current combat.",
        combatLocked = true,
    },
    {
        key = "brezCounter", group = "Instance", label = "Brez Counter",
        caption = "Shows remaining battle-resurrection charges for the group.",
        combatLocked = true,
    },
    {
        key = "mplusTimer", group = "Instance", label = "M+ Timer",
        caption = "Mythic+ keystone timer with depleted and timed thresholds.",
        combatLocked = true,
    },
    {
        key = "readyCheck", group = "Instance", label = "Ready Check",
        caption = "Custom skin for the party and raid ready-check dialog.",
        combatLocked = true,
    },
    {
        key = "consumables", group = "Instance", label = "Consumable Check",
        caption = "Pre-pull reminder when flask, food, or rune buffs are missing.",
        combatLocked = true,
    },
    {
        key = "missingRaidBuffs", group = "Instance", label = "Missing Raid Buffs",
        caption = "Shows which raid-wide utility buffs are absent from the group.",
        combatLocked = true,
    },
    {
        key = "partyKeystones", group = "Instance", label = "Party Keystones",
        caption = "Displays each group member's Mythic+ keystone level.",
        combatLocked = true,
    },

    ---------------------------------------------------------------------------
    -- Action Bars
    ---------------------------------------------------------------------------
    {
        key = "actionBars", group = "Action Bars", label = "Action Bars",
        caption = "Master toggle for the custom action bar system.",
        combatLocked = true,
    },
    {
        key = "bar1", group = "Action Bars", label = "Action Bar 1",
        caption = "Primary action bar (main bar).",
        combatLocked = true,
    },
    {
        key = "bar2", group = "Action Bars", label = "Action Bar 2",
        caption = "Second action bar.",
        combatLocked = true,
    },
    {
        key = "bar3", group = "Action Bars", label = "Action Bar 3",
        caption = "Third action bar.",
        combatLocked = true,
    },
    {
        key = "bar4", group = "Action Bars", label = "Action Bar 4",
        caption = "Fourth action bar.",
        combatLocked = true,
    },
    {
        key = "bar5", group = "Action Bars", label = "Action Bar 5",
        caption = "Fifth action bar.",
        combatLocked = true,
    },
    {
        key = "bar6", group = "Action Bars", label = "Action Bar 6",
        caption = "Sixth action bar.",
        combatLocked = true,
    },
    {
        key = "bar7", group = "Action Bars", label = "Action Bar 7",
        caption = "Seventh action bar.",
        combatLocked = true,
    },
    {
        key = "bar8", group = "Action Bars", label = "Action Bar 8",
        caption = "Eighth action bar.",
        combatLocked = true,
    },
    {
        key = "petBar", group = "Action Bars", label = "Pet Bar",
        caption = "Action bar for pet abilities.",
        combatLocked = true,
    },
    {
        key = "stanceBar", group = "Action Bars", label = "Stance Bar",
        caption = "Bar for stance, form, and presence buttons.",
        combatLocked = true,
    },
    {
        key = "microMenu", group = "Action Bars", label = "Micro Menu",
        caption = "Row of micro-buttons for the main menus.",
        combatLocked = true,
    },
    {
        key = "bagBar", group = "Action Bars", label = "Bag Bar",
        caption = "Bag slot buttons for quick inventory access.",
        combatLocked = true,
    },
    {
        key = "totemBar", group = "Action Bars", label = "Totem Bar",
        caption = "Shaman totem call buttons and active totem display.",
        combatLocked = true,
        hidden = HiddenUnlessShaman,
    },

    ---------------------------------------------------------------------------
    -- Castbars
    ---------------------------------------------------------------------------
    {
        key = "playerCastbar", group = "Castbars", label = "Player Castbar",
        caption = "Custom castbar for the player character.",
        combatLocked = true,
    },
    {
        key = "targetCastbar", group = "Castbars", label = "Target Castbar",
        caption = "Custom castbar for the current target.",
        combatLocked = true,
    },
    {
        key = "focusCastbar", group = "Castbars", label = "Focus Castbar",
        caption = "Custom castbar for the focus target.",
        combatLocked = true,
    },
    {
        key = "petCastbar", group = "Castbars", label = "Pet Castbar",
        caption = "Custom castbar for the player's pet.",
        combatLocked = true,
    },
    {
        key = "totCastbar", group = "Castbars", label = "Target of Target Castbar",
        caption = "Custom castbar for the target's target.",
        combatLocked = true,
    },

    ---------------------------------------------------------------------------
    -- Group Frames
    ---------------------------------------------------------------------------
    {
        key = "partyFrames", group = "Group Frames", label = "Party Frames",
        caption = "Custom party member frames for groups of up to five.",
        combatLocked = true,
    },
    {
        key = "raidFrames", group = "Group Frames", label = "Raid Frames",
        caption = "Custom raid member frames for groups larger than five.",
        combatLocked = true,
    },
    {
        key = "spotlightFrames", group = "Group Frames", label = "Spotlight",
        caption = "Separate large frames highlighting priority raid targets.",
        combatLocked = true,
    },

    ---------------------------------------------------------------------------
    -- Unit Frames
    ---------------------------------------------------------------------------
    {
        key = "playerFrame", group = "Unit Frames", label = "Player Frame",
        caption = "Custom frame displaying player health, power, and buffs.",
        combatLocked = true,
    },
    {
        key = "targetFrame", group = "Unit Frames", label = "Target Frame",
        caption = "Custom frame for the current target unit.",
        combatLocked = true,
    },
    {
        key = "totFrame", group = "Unit Frames", label = "Target of Target",
        caption = "Frame showing the unit your target is targeting.",
        combatLocked = true,
    },
    {
        key = "focusFrame", group = "Unit Frames", label = "Focus Frame",
        caption = "Custom frame for the focus target unit.",
        combatLocked = true,
    },
    {
        key = "petFrame", group = "Unit Frames", label = "Pet Frame",
        caption = "Custom frame for the player's pet.",
        combatLocked = true,
    },
    {
        key = "bossFrames", group = "Unit Frames", label = "Boss Frames",
        caption = "Frames for boss and encounter-special enemy units.",
        combatLocked = true,
    },

    ---------------------------------------------------------------------------
    -- Resource Bars
    ---------------------------------------------------------------------------
    {
        key = "primaryPower", group = "Resource Bars", label = "Primary Power",
        caption = "Custom bar for the player's primary resource (mana, rage, energy, etc.).",
        combatLocked = true,
    },
    {
        key = "secondaryPower", group = "Resource Bars", label = "Secondary Power",
        caption = "Custom bar for secondary resources such as combo points or holy power.",
        combatLocked = true,
    },

    ---------------------------------------------------------------------------
    -- Cooldown Manager & Custom Tracker Bars
    ---------------------------------------------------------------------------
    {
        key = "cdm", group = "Cooldown Manager & Custom Tracker Bars",
        label = "Cooldown Manager",
        caption = "Master toggle for cooldown viewers, buff trackers, and tracked bars.",
        combatLocked = true,
    },
    {
        key = "rotationAssistIcon", group = "Cooldown Manager & Custom Tracker Bars",
        label = "Rotation Assist Icon",
        caption = "Large icon showing the next recommended rotation ability.",
        combatLocked = true,
    },

    ---------------------------------------------------------------------------
    -- 3rd Party
    ---------------------------------------------------------------------------
    {
        key = "dandersParty", group = "3rd Party", label = "DF Party",
        caption = "DandersFrames party layout (requires optional companion addon).",
        combatLocked = true,
    },
    {
        key = "dandersRaid", group = "3rd Party", label = "DF Raid",
        caption = "DandersFrames raid layout (requires optional companion addon).",
        combatLocked = true,
    },
    {
        key = "dandersPinned1", group = "3rd Party", label = "DF Pinned 1",
        caption = "DandersFrames first pinned frame container.",
        combatLocked = true,
    },
    {
        key = "dandersPinned2", group = "3rd Party", label = "DF Pinned 2",
        caption = "DandersFrames second pinned frame container.",
        combatLocked = true,
    },
}

---------------------------------------------------------------------------
-- Registration pass
---------------------------------------------------------------------------

for _, m in ipairs(VISUAL_MODULES) do
    RegisterModuleFeature(m.key, m.group, m.label, m.caption, m.combatLocked, m.hidden)
end
