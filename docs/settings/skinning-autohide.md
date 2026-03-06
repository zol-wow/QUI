---
layout: default
title: Skinning & Autohide
parent: Settings Reference
nav_order: 8
---

# Skinning & Autohide

The Skinning & Autohide tab controls visual reskinning of Blizzard UI frames and selective hiding of default UI elements. Skinning toggles reside primarily in `db.profile.general`, while the UI Hider settings live in `db.profile.uiHider`.

---

## Skinning Toggles

General skinning options that replace Blizzard frame visuals with QUI-styled alternatives. Found in `db.profile.general`.

### Game Menu

| Setting | Type | Default | Description |
|---|---|---|---|
| `skinGameMenu` | boolean | `false` | Skin the ESC game menu |
| `addQUIButton` | boolean | `false` | Add a QUI button to the ESC menu |
| `gameMenuFontSize` | number | `12` | Game menu font size |
| `gameMenuDim` | boolean | `true` | Dim background when menu is open |

### Alerts & Notifications

| Setting | Type | Default | Description |
|---|---|---|---|
| `skinAlerts` | boolean | `true` | Skin alert and toast frames |

### Character & Inspect

| Setting | Type | Default | Description |
|---|---|---|---|
| `skinCharacterFrame` | boolean | `true` | Skin the character frame |
| `skinInspectFrame` | boolean | `true` | Skin the inspect frame |

### Loot

| Setting | Type | Default | Description |
|---|---|---|---|
| `skinLootWindow` | boolean | `true` | Skin the loot window |
| `skinLootUnderMouse` | boolean | `true` | Position loot window at cursor |
| `skinLootHistory` | boolean | `true` | Skin the loot history frame |
| `skinRollFrames` | boolean | `true` | Skin loot roll frames |
| `skinRollSpacing` | number | `6` | Spacing between roll frames |

### Dungeon & Instance

| Setting | Type | Default | Description |
|---|---|---|---|
| `skinKeystoneFrame` | boolean | `true` | Skin the keystone frame |
| `skinInstanceFrames` | boolean | `false` | Skin PVE/Dungeon Finder frames |

### Encounter

| Setting | Type | Default | Description |
|---|---|---|---|
| `skinPowerBarAlt` | boolean | `true` | Skin the encounter power bar |
| `skinOverrideActionBar` | boolean | `false` | Skin the override action bar |

### Objective Tracker

| Setting | Type | Default | Description |
|---|---|---|---|
| `skinObjectiveTracker` | boolean | `false` | Skin the objective tracker |
| `objectiveTrackerHeight` | number | `600` | Objective tracker maximum height |
| `objectiveTrackerModuleFontSize` | number | `12` | Module header font size |
| `objectiveTrackerTitleFontSize` | number | `10` | Quest title font size |
| `objectiveTrackerTextFontSize` | number | `10` | Objective text font size |
| `hideObjectiveTrackerBorder` | boolean | `false` | Hide the tracker border |
| `objectiveTrackerModuleColor` | color | `{1, 0.82, 0, 1}` | Module header color |
| `objectiveTrackerTitleColor` | color | `{1, 1, 1, 1}` | Quest title color |
| `objectiveTrackerTextColor` | color | `{0.8, 0.8, 0.8, 1}` | Objective text color |

### Global Skinning Options

| Setting | Type | Default | Description |
|---|---|---|---|
| `skinBgColor` | color | `{0.008, 0.008, 0.008, 1}` | Skinning background color used across all skinned frames |
| `skinUseClassColor` | boolean | `true` | Use class color for accent elements |

---

## Alert Positions

Position overrides for alert and toast frames. Found in `db.profile.alerts`.

| Setting | Type | Default | Description |
|---|---|---|---|
| `alerts.enabled` | boolean | `true` | Enable alert skinning |
| `alerts.alertPosition` | table | `{point="TOP", y=-293}` | Alert frame anchor position |
| `alerts.toastPosition` | table | `{point="CENTER", y=268}` | Toast frame anchor position |

---

## Loot Settings

Custom loot window behavior. Found in `db.profile.loot`.

| Setting | Type | Default | Description |
|---|---|---|---|
| `loot.enabled` | boolean | `true` | Enable the custom loot window |
| `loot.lootUnderMouse` | boolean | `false` | Position loot window at cursor |
| `loot.showTransmogMarker` | boolean | `true` | Show uncollected transmog marker |

---

## Loot Roll

Custom loot roll frame settings. Found in `db.profile.lootRoll`.

| Setting | Type | Default | Description |
|---|---|---|---|
| `lootRoll.enabled` | boolean | `true` | Enable custom roll frames |
| `lootRoll.growDirection` | string | `"DOWN"` | Stack direction for roll frames |
| `lootRoll.spacing` | number | `4` | Spacing between roll frames |

---

## Character Pane

Overlays for the character and inspect frames. Found in `db.profile.character`.

| Setting | Type | Default | Description |
|---|---|---|---|
| `character.enabled` | boolean | `true` | Enable character frame overlays |
| `character.showItemName` | boolean | `true` | Show equipment name on slots |
| `character.showItemLevel` | boolean | `true` | Show item level and upgrade track |
| `character.showEnchants` | boolean | `true` | Show enchant status indicators |
| `character.showGems` | boolean | `true` | Show gem slot indicators |
| `character.showDurability` | boolean | `false` | Show durability bars on slots |
| `character.inspectEnabled` | boolean | `true` | Enable inspect frame overlays |
| `character.panelScale` | number | `1.0` | Panel scale (range: 0.75 to 1.5) |
| `character.overlayScale` | number | `0.75` | Overlay element scale |
| `character.statsTextSize` | number | `13` | Stats text font size |
| `character.secondaryStatFormat` | string | `"both"` | Secondary stat format: `"percent"`, `"rating"`, or `"both"` |
| `character.compactStats` | boolean | `true` | Use compact stats layout |
| `character.slotTextSize` | number | `12` | Slot text font size (range: 6 to 40) |
| `character.headerClassColor` | boolean | `true` | Use class color for stat headers |

---

## UI Hider

Selectively hide default Blizzard UI elements. Found in `db.profile.uiHider`.

### Objective Tracker

| Setting | Type | Default | Description |
|---|---|---|---|
| `hideObjectiveTrackerAlways` | boolean | `false` | Always hide the objective tracker |
| `hideObjectiveTrackerInstanceTypes.mythicPlus` | boolean | `false` | Hide in Mythic+ dungeons |
| `hideObjectiveTrackerInstanceTypes.raid` | boolean | `false` | Hide in raids |
| `hideObjectiveTrackerInstanceTypes.pvp` | boolean | `false` | Hide in PvP instances |

### Minimap

| Setting | Type | Default | Description |
|---|---|---|---|
| `hideMinimapBorder` | boolean | `true` | Hide the minimap border art |
| `hideTimeManager` | boolean | `true` | Hide the time manager button |
| `hideGameTime` | boolean | `true` | Hide the game time display |
| `hideMinimapTracking` | boolean | `true` | Hide the tracking icon |
| `hideMinimapZoneText` | boolean | `true` | Hide the minimap zone text |
| `hideMinimapZoomButtons` | boolean | `true` | Hide the zoom in/out buttons |

### Frames

| Setting | Type | Default | Description |
|---|---|---|---|
| `hideRaidFrameManager` | boolean | `true` | Hide the raid frame manager button |
| `hideBuffCollapseButton` | boolean | `true` | Hide the buff collapse/expand button |
| `hideTalkingHead` | boolean | `true` | Hide the talking head frame |
| `muteTalkingHead` | boolean | `false` | Mute talking head audio |

### Nameplates

| Setting | Type | Default | Description |
|---|---|---|---|
| `hideFriendlyPlayerNameplates` | boolean | `true` | Hide friendly player nameplates |
| `hideFriendlyNPCNameplates` | boolean | `true` | Hide friendly NPC nameplates |

### Messages

| Setting | Type | Default | Description |
|---|---|---|---|
| `hideErrorMessages` | boolean | `false` | Hide red error messages |
| `hideInfoMessages` | boolean | `false` | Hide yellow info messages |

### Bars

| Setting | Type | Default | Description |
|---|---|---|---|
| `hideWorldMapBlackout` | boolean | `true` | Hide the world map background blackout |
| `hideXPAtMaxLevel` | boolean | `false` | Hide XP bar when at max level |
| `hideExperienceBar` | boolean | `false` | Always hide the experience bar |
| `hideReputationBar` | boolean | `false` | Always hide the reputation bar |
| `hideMainActionBarArt` | boolean | `false` | Hide the main action bar artwork |
