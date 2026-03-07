---
layout: default
title: General & QoL
parent: Settings Reference
nav_order: 1
---

# General & QoL Settings

The **General & QoL** tab controls global appearance settings, dark mode, color overrides, quality-of-life automation, popup blocking, pet warnings, consumable checking, dungeon utilities, and Blizzard frame skinning. All settings are stored under `QUI.db.profile.general` unless otherwise noted.

---

## Global Appearance

Base visual settings that affect the entire addon.

| Setting | Type | Default | Description |
|---------|------|---------|-------------|
| `uiScale` | number | `0.64` | Global UI scale, optimized for 1440p+ monitors |
| `font` | string | `"Quazii"` | Default font face (LibSharedMedia name) |
| `fontOutline` | string | `"OUTLINE"` | Font outline style: `""` (none), `"OUTLINE"`, `"THICKOUTLINE"` |
| `texture` | string | `"Quazii v5"` | Default status bar texture (LibSharedMedia name) |
| `applyGlobalFontToBlizzard` | boolean | `true` | Apply the global QUI font to Blizzard UI elements |

---

## Dark Mode

Override health bar and background colors with a dark theme.

| Setting | Type | Default | Description |
|---------|------|---------|-------------|
| `darkMode` | boolean | `false` | Enable dark mode for health bars |
| `darkModeHealthColor` | color | `{0, 0, 0, 1}` | Dark mode health bar color |
| `darkModeBgColor` | color | `{0.592, 0.592, 0.592, 1}` | Dark mode background color |
| `darkModeOpacity` | number | `0.7` | Dark mode overall frame opacity |
| `darkModeHealthOpacity` | number | `0.7` | Dark mode health bar opacity |
| `darkModeBgOpacity` | number | `0.7` | Dark mode background opacity |

---

## Color Settings

Control class colors, health bar colors, hostility colors, and text color overrides.

| Setting | Type | Default | Description |
|---------|------|---------|-------------|
| `masterColorNameText` | boolean | `false` | Apply class/reaction color to name text |
| `masterColorToTText` | boolean | `false` | Apply class/reaction color to Target-of-Target text |
| `masterColorPowerText` | boolean | `false` | Apply class/reaction color to power text |
| `masterColorHealthText` | boolean | `false` | Apply class/reaction color to health text |
| `masterColorCastbarText` | boolean | `false` | Apply class/reaction color to castbar text |
| `defaultUseClassColor` | boolean | `true` | Use class color for health bars |
| `defaultHealthColor` | color | `{0.2, 0.2, 0.2, 1}` | Default health bar color (when class color is off) |
| `hostilityColorHostile` | color | `{0.8, 0.2, 0.2, 1}` | Hostile NPC health bar color (red) |
| `hostilityColorNeutral` | color | `{1, 1, 0.2, 1}` | Neutral NPC health bar color (yellow) |
| `hostilityColorFriendly` | color | `{0.2, 0.8, 0.2, 1}` | Friendly NPC health bar color (green) |
| `defaultBgColor` | color | `{0, 0, 0, 1}` | Default background color (pure black) |
| `defaultOpacity` | number | `1.0` | Default bar opacity |
| `defaultHealthOpacity` | number | `1.0` | Default health bar opacity |
| `defaultBgOpacity` | number | `1.0` | Default background opacity |

---

## QoL Automation

Convenience features that automate common tasks.

| Setting | Type | Default | Description |
|---------|------|---------|-------------|
| `sellJunk` | boolean | `true` | Auto-sell junk items at vendors |
| `autoRepair` | string | `"personal"` | Auto repair mode: `"off"`, `"personal"`, `"guild"` |
| `autoRoleAccept` | boolean | `true` | Auto-accept role confirmations in groups |
| `autoAcceptInvites` | string | `"all"` | Auto accept group invites: `"off"`, `"all"`, `"friends"`, `"guild"`, `"both"` |
| `autoAcceptQuest` | boolean | `false` | Auto-accept quests from NPCs |
| `autoTurnInQuest` | boolean | `false` | Auto turn-in completed quests |
| `questHoldShift` | boolean | `true` | Hold Shift to override auto quest accept/turn-in |
| `fastAutoLoot` | boolean | `true` | Enable fast auto-loot (instant item pickup) |
| `autoSelectGossip` | boolean | `false` | Auto-select single gossip options at NPCs |
| `autoCombatLog` | boolean | `false` | Auto start/stop combat logging in M+ dungeons |
| `autoCombatLogRaid` | boolean | `false` | Auto start/stop combat logging in raids |
| `autoDeleteConfirm` | boolean | `true` | Auto-fill the DELETE confirmation text when deleting items |

---

## Popup Blocker

Block specific Blizzard popup notifications and toast alerts. All options are disabled by default and require the master toggle to be enabled.

| Setting | Type | Default | Description |
|---------|------|---------|-------------|
| `popupBlocker.enabled` | boolean | `false` | Master toggle for the popup blocker |
| `popupBlocker.blockTalentMicroButtonAlerts` | boolean | `false` | Block unspent talent point reminder callouts |
| `popupBlocker.blockEventToasts` | boolean | `false` | Block event toast notifications (campaign, housing news) |
| `popupBlocker.blockMountAlerts` | boolean | `false` | Block new mount collection toasts |
| `popupBlocker.blockPetAlerts` | boolean | `false` | Block new pet collection toasts |
| `popupBlocker.blockToyAlerts` | boolean | `false` | Block new toy collection toasts |
| `popupBlocker.blockCosmeticAlerts` | boolean | `false` | Block new cosmetic collection toasts |
| `popupBlocker.blockWarbandSceneAlerts` | boolean | `false` | Block warband scene toasts |
| `popupBlocker.blockEntitlementAlerts` | boolean | `false` | Block entitlement/RAF delivery toasts |
| `popupBlocker.blockStaticTalentPopups` | boolean | `false` | Block talent-related static popup dialogs |
| `popupBlocker.blockStaticHousingPopups` | boolean | `false` | Block housing-related static popup dialogs |

---

## Pet Warning

Show a combat warning for pet-class players (Hunter, Warlock, Death Knight, Mage) when their pet is missing or passive in instances.

| Setting | Type | Default | Description |
|---------|------|---------|-------------|
| `petCombatWarning` | boolean | `true` | Show warning when pet is missing or passive in instances |
| `petWarningOffsetX` | number | `0` | Warning frame horizontal offset from screen center |
| `petWarningOffsetY` | number | `-200` | Warning frame vertical offset from screen center |

---

## Focus Cast Alert

Display an on-screen alert when your hostile focus target is casting and your interrupt is available.

| Setting | Type | Default | Description |
|---------|------|---------|-------------|
| `focusCastAlert.enabled` | boolean | `false` | Enable focus cast alert |
| `focusCastAlert.text` | string | `"Focus is casting. Kick!"` | Alert text message |
| `focusCastAlert.anchorTo` | string | `"screen"` | Anchor point: `"screen"`, `"essential"`, `"focus"` |
| `focusCastAlert.offsetX` | number | `0` | Alert horizontal offset |
| `focusCastAlert.offsetY` | number | `-120` | Alert vertical offset |
| `focusCastAlert.font` | string | `""` | Font face (empty string = use global QUI font) |
| `focusCastAlert.fontSize` | number | `26` | Alert text font size |
| `focusCastAlert.fontOutline` | string | `"OUTLINE"` | Font outline: `""`, `"OUTLINE"`, `"THICKOUTLINE"` |
| `focusCastAlert.textColor` | color | `{1, 0.2, 0.2, 1}` | Alert text color (red) |
| `focusCastAlert.useClassColor` | boolean | `false` | Use class color instead of custom text color |

---

## Consumable Check

Display missing consumable buffs on ready checks, dungeon entry, or resurrection.

| Setting | Type | Default | Description |
|---------|------|---------|-------------|
| `consumableCheckEnabled` | boolean | `false` | Master toggle for consumable checking |
| `consumableOnReadyCheck` | boolean | `true` | Show consumable check on ready check |
| `consumableOnDungeon` | boolean | `false` | Show consumable check on dungeon entrance |
| `consumableOnRaid` | boolean | `false` | Show consumable check on raid entrance |
| `consumableOnResurrect` | boolean | `false` | Show consumable check on instanced resurrect |
| `consumableFood` | boolean | `true` | Track food buff |
| `consumableFlask` | boolean | `true` | Track flask buff |
| `consumableOilMH` | boolean | `true` | Track main hand weapon enchant (oil/stone) |
| `consumableOilOH` | boolean | `true` | Track off hand weapon enchant (oil/stone) |
| `consumableRune` | boolean | `true` | Track augment rune |
| `consumableHealthstone` | boolean | `true` | Track healthstones (when warlock in group) |
| `consumableExpirationWarning` | boolean | `false` | Warn when tracked buffs are about to expire |
| `consumableExpirationThreshold` | number | `300` | Seconds before expiration to trigger warning |
| `consumableIconSize` | number | `40` | Icon size in pixels |
| `consumableScale` | number | `1` | Frame scale multiplier |
| `consumableAnchorMode` | boolean | `true` | Anchor to ready check frame |
| `consumableIconOffset` | number | `5` | Icon offset from anchor point |

---

## Quick Salvage

Enable modifier-key quick salvage of items in your bags.

| Setting | Type | Default | Description |
|---------|------|---------|-------------|
| `quickSalvage.enabled` | boolean | `false` | Enable quick salvage |
| `quickSalvage.modifier` | string | `"ALT"` | Modifier key: `"ALT"`, `"ALTCTRL"`, `"ALTSHIFT"` |

---

## Dungeon Teleport & Key Tracker

Dungeon-related utilities on the M+ tab of the PVE frame.

| Setting | Type | Default | Description |
|---------|------|---------|-------------|
| `mplusTeleportEnabled` | boolean | `true` | Click-to-teleport on M+ tab dungeon icons |
| `keyTrackerEnabled` | boolean | `true` | Show party keystones on the M+ tab |
| `keyTrackerFontSize` | number | `9` | Key tracker font size (7-12) |
| `keyTrackerFont` | string | `nil` | Font name from LibSharedMedia (`nil` = use global QUI font) |
| `keyTrackerTextColor` | color | `{1, 1, 1, 1}` | Key tracker text color (white) |
| `keyTrackerWidth` | number | `170` | Key tracker frame width in pixels |
| `keyTrackerPoint` | string | `"TOPRIGHT"` | Anchor point on the KeyTracker frame |
| `keyTrackerRelPoint` | string | `"BOTTOMRIGHT"` | Relative anchor point on PVEFrame |
| `keyTrackerOffsetX` | number | `0` | Horizontal offset from anchor |
| `keyTrackerOffsetY` | number | `0` | Vertical offset from anchor |

---

## Skinning

Blizzard frame skinning toggles that live under the General tab. These control which Blizzard UI elements receive the QUI visual treatment.

| Setting | Type | Default | Description |
|---------|------|---------|-------------|
| `skinGameMenu` | boolean | `false` | Skin the ESC/Game Menu |
| `addQUIButton` | boolean | `false` | Add a QUI button to the ESC menu |
| `gameMenuFontSize` | number | `12` | Game menu button font size |
| `gameMenuDim` | boolean | `true` | Dim background when game menu is open |
| `skinKeystoneFrame` | boolean | `true` | Skin the M+ keystone insertion window |
| `autoInsertKey` | boolean | `true` | Auto-insert keystone in the M+ UI |
| `skinPowerBarAlt` | boolean | `true` | Skin the encounter/quest power bar |
| `skinOverrideActionBar` | boolean | `false` | Skin the override/vehicle action bar |
| `skinObjectiveTracker` | boolean | `false` | Skin the objective tracker |
| `objectiveTrackerHeight` | number | `600` | Objective tracker max height |
| `objectiveTrackerModuleFontSize` | number | `12` | Module header font size (QUESTS, ACHIEVEMENTS, etc.) |
| `objectiveTrackerTitleFontSize` | number | `10` | Quest/achievement title font size |
| `objectiveTrackerTextFontSize` | number | `10` | Objective text line font size |
| `hideObjectiveTrackerBorder` | boolean | `false` | Hide the class-colored border on the objective tracker |
| `objectiveTrackerModuleColor` | color | `{1.0, 0.82, 0.0, 1.0}` | Module header text color (Blizzard gold) |
| `objectiveTrackerTitleColor` | color | `{1.0, 1.0, 1.0, 1.0}` | Quest title text color (white) |
| `objectiveTrackerTextColor` | color | `{0.8, 0.8, 0.8, 1.0}` | Objective text color (light gray) |
| `skinInstanceFrames` | boolean | `false` | Skin PVE/Dungeon/PVP group finder frames |
| `skinAlerts` | boolean | `true` | Skin alert and toast notification frames |
| `skinCharacterFrame` | boolean | `true` | Skin the Character Frame (Character, Reputation, Currency) |
| `skinInspectFrame` | boolean | `true` | Skin the Inspect Frame to match Character Frame |
| `skinLootWindow` | boolean | `true` | Enable custom loot window |
| `skinLootUnderMouse` | boolean | `true` | Position loot window at cursor position |
| `skinLootHistory` | boolean | `true` | Skin the loot history frame |
| `skinRollFrames` | boolean | `true` | Skin loot roll frames |
| `skinRollSpacing` | number | `6` | Spacing between loot roll frames |
| `skinUseClassColor` | boolean | `true` | Use class color for skinning accent highlights |
| `skinBgColor` | color | `{0.008, 0.008, 0.008, 1}` | Skinning background color |
