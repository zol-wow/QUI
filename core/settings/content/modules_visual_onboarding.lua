---------------------------------------------------------------------------
-- QUI Feature Toggles — Visual onboarding (Phase 2)
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

local function HiddenFromFeatureToggles()
    return true
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
        key = "buffFrame", group = ns.L["Display"], label = ns.L["Buff Frame"],
        caption = ns.L["Active beneficial auras with custom borders."],
        combatLocked = true,
        hidden = HiddenFromFeatureToggles,
    },
    {
        key = "debuffFrame", group = ns.L["Display"], label = ns.L["Debuff Frame"],
        caption = ns.L["Active harmful auras with custom borders."],
        combatLocked = true,
        hidden = HiddenFromFeatureToggles,
    },
    {
        key = "chatFrame1", group = ns.L["Display"], label = ns.L["Chat Frame"],
        caption = ns.L["Custom chat frame replacing the default window."],
        combatLocked = true,
        hidden = HiddenFromFeatureToggles,
    },
    {
        key = "lootFrame", group = ns.L["Display"], label = ns.L["Loot Frame"],
        caption = ns.L["Custom loot window displayed when looting enemies."],
        combatLocked = true,
    },
    {
        key = "lootRollAnchor", group = ns.L["Display"], label = ns.L["Loot Roll Anchor"],
        caption = ns.L["Repositions the Need/Greed loot-roll dialog."],
        combatLocked = true,
        hidden = HiddenFromFeatureToggles,
    },
    {
        key = "alertAnchor", group = ns.L["Display"], label = ns.L["Alert Anchor"],
        caption = ns.L["Anchor for raid and encounter alert messages."],
        combatLocked = true,
        hidden = HiddenFromFeatureToggles,
    },
    {
        key = "toastAnchor", group = ns.L["Display"], label = ns.L["Toast Anchor"],
        caption = ns.L["Anchor for achievement and event toast notifications."],
        combatLocked = true,
        hidden = HiddenFromFeatureToggles,
    },
    {
        key = "bnetToastAnchor", group = ns.L["Display"], label = ns.L["BNet Toast Anchor"],
        caption = ns.L["Anchor for Battle.net friend-activity toast notifications."],
        combatLocked = true,
        hidden = HiddenFromFeatureToggles,
    },
    {
        key = "powerBarAlt", group = ns.L["Display"], label = ns.L["Encounter Power Bar"],
        caption = ns.L["Skinned alternate power bar shown during certain encounters."],
        combatLocked = true,
        hidden = HiddenFromFeatureToggles,
    },
    {
        key = "tooltipAnchor", group = ns.L["Display"], label = ns.L["Tooltip Anchor"],
        caption = ns.L["Repositions the game tooltip to a custom screen position."],
        combatLocked = true,
        hidden = HiddenFromFeatureToggles,
    },

    ---------------------------------------------------------------------------
    -- QoL
    ---------------------------------------------------------------------------
    {
        key = "crosshair", group = ns.L["QoL"], label = ns.L["Crosshair"],
        caption = ns.L["Reticle drawn at the screen center for precise targeting."],
        combatLocked = true,
    },
    {
        key = "skyriding", group = ns.L["QoL"], label = ns.L["Skyriding HUD"],
        caption = ns.L["Momentum and Second Wind HUD for Skyriding mounts."],
        combatLocked = true,
    },
    {
        key = "xpTracker", group = ns.L["QoL"], label = ns.L["XP Tracker"],
        caption = ns.L["Compact bar showing current XP or reputation progress."],
        combatLocked = true,
    },
    {
        key = "rangeCheck", group = ns.L["QoL"], label = ns.L["Range Check"],
        caption = ns.L["Indicator that alerts when your target steps out of range."],
        combatLocked = false,
    },
    {
        key = "actionTracker", group = ns.L["QoL"], label = ns.L["Action Tracker"],
        caption = ns.L["Tracks and displays the last ability or action used."],
        combatLocked = false,
    },
    {
        key = "focusCastAlert", group = ns.L["QoL"], label = ns.L["Focus Cast Alert"],
        caption = ns.L["Highlights when your focus target begins casting."],
        combatLocked = false,
    },
    {
        key = "petWarning", group = ns.L["QoL"], label = ns.L["Pet Warning"],
        caption = ns.L["Warns when your pet enters or exits combat unexpectedly."],
        combatLocked = false,
    },
    {
        key = "preyTracker", group = ns.L["QoL"], label = ns.L["Prey Tracker"],
        caption = ns.L["Tracks a designated enemy target across reloads."],
        combatLocked = false,
    },
    {
        key = "atonementCounter", group = ns.L["QoL"], label = ns.L["Atonement Counter"],
        caption = ns.L["Discipline Priest Atonement uptime tracker."],
        combatLocked = true,
        hidden = HiddenUnlessDisciplinePriest,
    },

    ---------------------------------------------------------------------------
    -- Instance
    ---------------------------------------------------------------------------
    {
        key = "combatTimer", group = ns.L["Instance"], label = ns.L["Combat Timer"],
        caption = ns.L["Tracks how long you have been in the current combat."],
        combatLocked = true,
    },
    {
        key = "brezCounter", group = ns.L["Instance"], label = ns.L["Brez Counter"],
        caption = ns.L["Shows remaining battle-resurrection charges for the group."],
        combatLocked = true,
    },
    {
        key = "mplusTimer", group = ns.L["Instance"], label = ns.L["M+ Timer"],
        caption = ns.L["Mythic+ keystone timer with depleted and timed thresholds."],
        combatLocked = true,
    },
    {
        key = "readyCheck", group = ns.L["Instance"], label = ns.L["Ready Check"],
        caption = ns.L["Custom skin for the party and raid ready-check dialog."],
        combatLocked = true,
    },
    {
        key = "consumables", group = ns.L["Instance"], label = ns.L["Consumable Check"],
        caption = ns.L["Pre-pull reminder when flask, food, or rune buffs are missing."],
        combatLocked = true,
    },
    {
        key = "missingRaidBuffs", group = ns.L["Instance"], label = ns.L["Missing Raid Buffs"],
        caption = ns.L["Shows which raid-wide utility buffs are absent from the group."],
        combatLocked = true,
    },
    {
        key = "partyKeystones", group = ns.L["Instance"], label = ns.L["Party Keystones"],
        caption = ns.L["Displays each group member's Mythic+ keystone level."],
        combatLocked = true,
    },

    ---------------------------------------------------------------------------
    -- Action Bars
    ---------------------------------------------------------------------------
    {
        key = "bar1", group = ns.L["Action Bars"], label = ns.L["Action Bar 1"],
        caption = ns.L["Primary action bar (main bar)."],
        combatLocked = true,
        hidden = HiddenFromFeatureToggles,
    },
    {
        key = "bar2", group = ns.L["Action Bars"], label = ns.L["Action Bar 2"],
        caption = ns.L["Second action bar."],
        combatLocked = true,
        hidden = HiddenFromFeatureToggles,
    },
    {
        key = "bar3", group = ns.L["Action Bars"], label = ns.L["Action Bar 3"],
        caption = ns.L["Third action bar."],
        combatLocked = true,
        hidden = HiddenFromFeatureToggles,
    },
    {
        key = "bar4", group = ns.L["Action Bars"], label = ns.L["Action Bar 4"],
        caption = ns.L["Fourth action bar."],
        combatLocked = true,
        hidden = HiddenFromFeatureToggles,
    },
    {
        key = "bar5", group = ns.L["Action Bars"], label = ns.L["Action Bar 5"],
        caption = ns.L["Fifth action bar."],
        combatLocked = true,
        hidden = HiddenFromFeatureToggles,
    },
    {
        key = "bar6", group = ns.L["Action Bars"], label = ns.L["Action Bar 6"],
        caption = ns.L["Sixth action bar."],
        combatLocked = true,
        hidden = HiddenFromFeatureToggles,
    },
    {
        key = "bar7", group = ns.L["Action Bars"], label = ns.L["Action Bar 7"],
        caption = ns.L["Seventh action bar."],
        combatLocked = true,
        hidden = HiddenFromFeatureToggles,
    },
    {
        key = "bar8", group = ns.L["Action Bars"], label = ns.L["Action Bar 8"],
        caption = ns.L["Eighth action bar."],
        combatLocked = true,
        hidden = HiddenFromFeatureToggles,
    },
    {
        key = "petBar", group = ns.L["Action Bars"], label = ns.L["Pet Bar"],
        caption = ns.L["Action bar for pet abilities."],
        combatLocked = true,
        hidden = HiddenFromFeatureToggles,
    },
    {
        key = "stanceBar", group = ns.L["Action Bars"], label = ns.L["Stance Bar"],
        caption = ns.L["Bar for stance, form, and presence buttons."],
        combatLocked = true,
        hidden = HiddenFromFeatureToggles,
    },
    {
        key = "microMenu", group = ns.L["Action Bars"], label = ns.L["Micro Menu"],
        caption = ns.L["Row of micro-buttons for the main menus."],
        combatLocked = true,
        hidden = HiddenFromFeatureToggles,
    },
    {
        key = "bagBar", group = ns.L["Action Bars"], label = ns.L["Bag Bar"],
        caption = ns.L["Bag slot buttons for quick inventory access."],
        combatLocked = true,
        hidden = HiddenFromFeatureToggles,
    },
    {
        key = "totemBar", group = ns.L["Action Bars"], label = ns.L["Totem Bar"],
        caption = ns.L["Shaman totem call buttons and active totem display."],
        combatLocked = true,
        hidden = HiddenFromFeatureToggles,
    },

    ---------------------------------------------------------------------------
    -- Castbars
    ---------------------------------------------------------------------------
    {
        key = "playerCastbar", group = ns.L["Castbars"], label = ns.L["Player Castbar"],
        caption = ns.L["Custom castbar for the player character."],
        combatLocked = true,
        hidden = HiddenFromFeatureToggles,
    },
    {
        key = "targetCastbar", group = ns.L["Castbars"], label = ns.L["Target Castbar"],
        caption = ns.L["Custom castbar for the current target."],
        combatLocked = true,
        hidden = HiddenFromFeatureToggles,
    },
    {
        key = "focusCastbar", group = ns.L["Castbars"], label = ns.L["Focus Castbar"],
        caption = ns.L["Custom castbar for the focus target."],
        combatLocked = true,
        hidden = HiddenFromFeatureToggles,
    },
    {
        key = "petCastbar", group = ns.L["Castbars"], label = ns.L["Pet Castbar"],
        caption = ns.L["Custom castbar for the player's pet."],
        combatLocked = true,
        hidden = HiddenFromFeatureToggles,
    },
    {
        key = "totCastbar", group = ns.L["Castbars"], label = ns.L["Target of Target Castbar"],
        caption = ns.L["Custom castbar for the target's target."],
        combatLocked = true,
        hidden = HiddenFromFeatureToggles,
    },

    ---------------------------------------------------------------------------
    -- Group Frames
    ---------------------------------------------------------------------------
    {
        key = "partyFrames", group = ns.L["Group Frames"], label = ns.L["Party Frames"],
        caption = ns.L["Custom party member frames for groups of up to five."],
        combatLocked = true,
        hidden = HiddenFromFeatureToggles,
    },
    {
        key = "raidFrames", group = ns.L["Group Frames"], label = ns.L["Raid Frames"],
        caption = ns.L["Custom raid member frames for groups larger than five."],
        combatLocked = true,
        hidden = HiddenFromFeatureToggles,
    },
    {
        key = "spotlightFrames", group = ns.L["Group Frames"], label = ns.L["Spotlight"],
        caption = ns.L["Separate large frames highlighting priority raid targets."],
        combatLocked = true,
        hidden = HiddenFromFeatureToggles,
    },

    ---------------------------------------------------------------------------
    -- Unit Frames
    ---------------------------------------------------------------------------
    {
        key = "playerFrame", group = ns.L["Unit Frames"], label = ns.L["Player Frame"],
        caption = ns.L["Custom frame displaying player health, power, and buffs."],
        combatLocked = true,
        hidden = HiddenFromFeatureToggles,
    },
    {
        key = "targetFrame", group = ns.L["Unit Frames"], label = ns.L["Target Frame"],
        caption = ns.L["Custom frame for the current target unit."],
        combatLocked = true,
        hidden = HiddenFromFeatureToggles,
    },
    {
        key = "totFrame", group = ns.L["Unit Frames"], label = ns.L["Target of Target"],
        caption = ns.L["Frame showing the unit your target is targeting."],
        combatLocked = true,
        hidden = HiddenFromFeatureToggles,
    },
    {
        key = "focusFrame", group = ns.L["Unit Frames"], label = ns.L["Focus Frame"],
        caption = ns.L["Custom frame for the focus target unit."],
        combatLocked = true,
        hidden = HiddenFromFeatureToggles,
    },
    {
        key = "petFrame", group = ns.L["Unit Frames"], label = ns.L["Pet Frame"],
        caption = ns.L["Custom frame for the player's pet."],
        combatLocked = true,
        hidden = HiddenFromFeatureToggles,
    },
    {
        key = "bossFrames", group = ns.L["Unit Frames"], label = ns.L["Boss Frames"],
        caption = ns.L["Frames for boss and encounter-special enemy units."],
        combatLocked = true,
        hidden = HiddenFromFeatureToggles,
    },

    ---------------------------------------------------------------------------
    -- Resource Bars
    ---------------------------------------------------------------------------
    {
        key = "primaryPower", group = ns.L["Resource Bars"], label = ns.L["Primary Power"],
        caption = ns.L["Custom bar for the player's primary resource (mana, rage, energy, etc.)."],
        combatLocked = true,
        hidden = HiddenFromFeatureToggles,
    },
    {
        key = "secondaryPower", group = ns.L["Resource Bars"], label = ns.L["Secondary Power"],
        caption = ns.L["Custom bar for secondary resources such as combo points or holy power."],
        combatLocked = true,
        hidden = HiddenFromFeatureToggles,
    },

    ---------------------------------------------------------------------------
    -- Cooldown Manager & Custom Tracker Bars
    ---------------------------------------------------------------------------
    {
        key = "rotationAssistIcon", group = ns.L["Cooldown Manager & Custom Tracker Bars"],
        label = ns.L["Rotation Assist Icon"],
        caption = ns.L["Large icon showing the next recommended rotation ability."],
        combatLocked = true,
    },

    ---------------------------------------------------------------------------
    -- 3rd Party
    ---------------------------------------------------------------------------
    {
        key = "dandersParty", group = ns.L["3rd Party"], label = ns.L["DF Party"],
        caption = ns.L["DandersFrames party layout (requires optional companion addon)."],
        combatLocked = true,
        hidden = HiddenFromFeatureToggles,
    },
    {
        key = "dandersRaid", group = ns.L["3rd Party"], label = ns.L["DF Raid"],
        caption = ns.L["DandersFrames raid layout (requires optional companion addon)."],
        combatLocked = true,
        hidden = HiddenFromFeatureToggles,
    },
    {
        key = "dandersPinned1", group = ns.L["3rd Party"], label = ns.L["DF Pinned 1"],
        caption = ns.L["DandersFrames first pinned frame container."],
        combatLocked = true,
        hidden = HiddenFromFeatureToggles,
    },
    {
        key = "dandersPinned2", group = ns.L["3rd Party"], label = ns.L["DF Pinned 2"],
        caption = ns.L["DandersFrames second pinned frame container."],
        combatLocked = true,
        hidden = HiddenFromFeatureToggles,
    },
}

---------------------------------------------------------------------------
-- Registration pass
---------------------------------------------------------------------------

for _, m in ipairs(VISUAL_MODULES) do
    RegisterModuleFeature(m.key, m.group, m.label, m.caption, m.combatLocked, m.hidden)
end
