---
layout: default
title: Minimap & Datatext
parent: Settings Reference
nav_order: 7
---

# Minimap & Datatext

QUI replaces Blizzard's minimap with a clean, configurable version featuring square or round shapes, button management, a clock, coordinates, zone text, and a datatext information panel. Most minimap chrome (zoom buttons, tracking, difficulty badge) is hidden by default for a minimal look.

**DB path:** `db.profile.minimap` (minimap), `db.profile.datatext` (datatext panel)

---

## Shape & Size

Core minimap appearance settings.

**DB path:** `db.profile.minimap`

| Setting | Type | Default | Description |
|---------|------|---------|-------------|
| `minimap.enabled` | boolean | `true` | Enable QUI minimap module |
| `minimap.shape` | string | `"SQUARE"` | Minimap shape: `SQUARE` or `ROUND` |
| `minimap.size` | number | `160` | Minimap size in pixels |
| `minimap.scale` | number | `1.0` | Scale multiplier for the entire minimap frame |
| `minimap.borderSize` | number | `2` | Border thickness in pixels |
| `minimap.borderColor` | color | `{0, 0, 0, 1}` | Border color (black) |
| `minimap.useClassColorBorder` | boolean | `false` | Use your class color for the border |
| `minimap.useAccentColorBorder` | boolean | `false` | Use the addon accent color for the border |
| `minimap.buttonRadius` | number | `2` | LibDBIcon button radius for square minimap corners |

---

## Position

| Setting | Type | Default | Description |
|---------|------|---------|-------------|
| `minimap.lock` | boolean | `false` | Lock minimap position (prevent dragging) |

---

## Features

General minimap behavior toggles.

| Setting | Type | Default | Description |
|---------|------|---------|-------------|
| `minimap.autoZoom` | boolean | `false` | Automatically zoom out after 10 seconds when zoomed in |
| `minimap.hideAddonButtons` | boolean | `true` | Hide addon minimap buttons (show on hover only) |
| `minimap.middleClickMenuEnabled` | boolean | `true` | Open quick menu on middle-click |
| `minimap.hideMicroMenu` | boolean | `false` | Hide Blizzard's micro menu bar (Character, Spellbook, etc.) |
| `minimap.hideBagBar` | boolean | `false` | Hide Blizzard's bag bar |

---

## Button Drawer

Collects addon minimap buttons into a toggleable drawer panel instead of scattering them around the minimap edge.

**DB path:** `db.profile.minimap.buttonDrawer`

| Setting | Type | Default | Description |
|---------|------|---------|-------------|
| `buttonDrawer.enabled` | boolean | `false` | Enable the button drawer (opt-in) |
| `buttonDrawer.anchor` | string | `"RIGHT"` | Drawer anchor side: `LEFT`, `RIGHT`, `TOP`, `BOTTOM`, `TOPLEFT`, `TOPRIGHT`, `BOTTOMLEFT`, `BOTTOMRIGHT` |
| `buttonDrawer.offsetX` | number | `0` | Horizontal offset from anchor position |
| `buttonDrawer.offsetY` | number | `0` | Vertical offset from anchor position |
| `buttonDrawer.toggleOffsetX` | number | `0` | Horizontal offset for the toggle button |
| `buttonDrawer.toggleOffsetY` | number | `0` | Vertical offset for the toggle button |
| `buttonDrawer.autoHideToggle` | boolean | `false` | Auto-hide the toggle button (show on minimap hover) |
| `buttonDrawer.autoHideDelay` | number | `1.5` | Seconds after mouse leaves before drawer hides (0 = no auto-hide) |
| `buttonDrawer.buttonSize` | number | `28` | Collected button size in pixels |
| `buttonDrawer.buttonSpacing` | number | `2` | Gap between buttons in pixels |
| `buttonDrawer.columns` | number | `1` | Number of columns in grid layout (1 = vertical strip) |
| `buttonDrawer.hiddenButtons` | table | `{}` | Table of button names excluded from the drawer |

---

## Button Visibility

Toggle visibility of individual Blizzard minimap elements. Most are hidden by default for a clean look.

**DB path:** `db.profile.minimap`

| Setting | Type | Default | Description |
|---------|------|---------|-------------|
| `minimap.showZoomButtons` | boolean | `false` | Show zoom in/out buttons |
| `minimap.showMail` | boolean | `false` | Show mail indicator icon |
| `minimap.showCraftingOrder` | boolean | `true` | Show work order (crafting order) indicator |
| `minimap.showAddonCompartment` | boolean | `false` | Show addon compartment button |
| `minimap.showDifficulty` | boolean | `false` | Show dungeon/raid difficulty badge |
| `minimap.showMissions` | boolean | `false` | Show mission table indicator |
| `minimap.showCalendar` | boolean | `true` | Show calendar button |
| `minimap.showTracking` | boolean | `false` | Show tracking button |

---

## Dungeon Eye

Repositions the LFG Queue Status button (the "eye") to a minimap corner when you are in a dungeon queue.

**DB path:** `db.profile.minimap.dungeonEye`

| Setting | Type | Default | Description |
|---------|------|---------|-------------|
| `dungeonEye.enabled` | boolean | `true` | Enable dungeon eye repositioning |
| `dungeonEye.corner` | string | `"BOTTOMLEFT"` | Corner position on the minimap |
| `dungeonEye.scale` | number | `0.6` | Scale multiplier for the eye button |
| `dungeonEye.offsetX` | number | `0` | Horizontal offset from corner |
| `dungeonEye.offsetY` | number | `0` | Vertical offset from corner |

---

## Clock

Optional clock display anchored to the minimap.

**DB path:** `db.profile.minimap` and `db.profile.minimap.clockConfig`

| Setting | Type | Default | Description |
|---------|------|---------|-------------|
| `minimap.showClock` | boolean | `false` | Show clock on minimap |
| `clockConfig.timeFormat` | string | `"local"` | Time source: `local` (system time) or `server` (realm time) |
| `clockConfig.font` | string | `"Quazii"` | Clock font face (LibSharedMedia name) |
| `clockConfig.fontSize` | number | `12` | Clock font size |
| `clockConfig.outline` | string | `"OUTLINE"` | Font outline: `OUTLINE`, `THICKOUTLINE`, `NONE` |
| `clockConfig.color` | color | `{1, 1, 1, 1}` | Clock text color (white) |
| `clockConfig.useClassColor` | boolean | `false` | Use class color for clock text |
| `clockConfig.monochrome` | boolean | `false` | Monochrome font rendering |
| `clockConfig.align` | string | `"LEFT"` | Text alignment |
| `clockConfig.offsetX` | number | `0` | Horizontal offset |
| `clockConfig.offsetY` | number | `0` | Vertical offset |

---

## Coordinates

Optional player coordinate display on the minimap.

**DB path:** `db.profile.minimap` and `db.profile.minimap.coordsConfig`

| Setting | Type | Default | Description |
|---------|------|---------|-------------|
| `minimap.showCoords` | boolean | `false` | Show player coordinates |
| `coordPrecision` | string | `"%d,%d"` | Coordinate format: `%d,%d` (integer), `%.1f,%.1f` (one decimal), `%.2f,%.2f` (two decimals) |
| `coordUpdateInterval` | number | `1` | Update frequency in seconds |
| `coordsConfig.font` | string | `"Quazii"` | Coordinates font face |
| `coordsConfig.fontSize` | number | `12` | Coordinates font size |
| `coordsConfig.outline` | string | `"OUTLINE"` | Font outline |
| `coordsConfig.color` | color | `{1, 1, 1, 1}` | Text color (white) |
| `coordsConfig.useClassColor` | boolean | `false` | Use class color for text |
| `coordsConfig.monochrome` | boolean | `false` | Monochrome font rendering |
| `coordsConfig.align` | string | `"RIGHT"` | Text alignment |
| `coordsConfig.offsetX` | number | `0` | Horizontal offset |
| `coordsConfig.offsetY` | number | `0` | Vertical offset |

---

## Zone Text

Zone name display on the minimap, colored by zone type (friendly, hostile, contested, sanctuary).

**DB path:** `db.profile.minimap` and `db.profile.minimap.zoneTextConfig`

| Setting | Type | Default | Description |
|---------|------|---------|-------------|
| `minimap.showZoneText` | boolean | `true` | Show zone name text |
| `zoneTextConfig.allCaps` | boolean | `false` | Display zone name in all capitals |
| `zoneTextConfig.font` | string | `"Quazii"` | Zone text font face |
| `zoneTextConfig.fontSize` | number | `12` | Zone text font size |
| `zoneTextConfig.outline` | string | `"OUTLINE"` | Font outline |
| `zoneTextConfig.useClassColor` | boolean | `false` | Use class color instead of zone-type colors |
| `zoneTextConfig.monochrome` | boolean | `false` | Monochrome font rendering |
| `zoneTextConfig.align` | string | `"CENTER"` | Text alignment |
| `zoneTextConfig.colorNormal` | color | `{1, 0.82, 0, 1}` | Normal zone color (gold) |
| `zoneTextConfig.colorSanctuary` | color | `{0.41, 0.8, 0.94, 1}` | Sanctuary zone color (light blue) |
| `zoneTextConfig.colorArena` | color | `{1.0, 0.1, 0.1, 1}` | Arena/PvP zone color (red) |
| `zoneTextConfig.colorFriendly` | color | `{0.1, 1.0, 0.1, 1}` | Friendly zone color (green) |
| `zoneTextConfig.colorHostile` | color | `{1.0, 0.1, 0.1, 1}` | Hostile zone color (red) |
| `zoneTextConfig.colorContested` | color | `{1.0, 0.7, 0.0, 1}` | Contested zone color (orange) |

---

## Minimap Button (LibDBIcon)

The QUI addon button on the minimap ring. Separate from the minimap module itself.

**DB path:** `db.profile.minimapButton`

| Setting | Type | Default | Description |
|---------|------|---------|-------------|
| `minimapButton.hide` | boolean | `false` | Hide the QUI minimap button |
| `minimapButton.minimapPos` | number | `180` | Button position in degrees (180 = left side / 9 o'clock) |

---

## Datatext Panel

A configurable information panel anchored below the minimap with slot-based architecture. Supports datatexts like FPS, durability, time, gold, friends, guild, coordinates, volume, currencies, and more.

**DB path:** `db.profile.datatext`

### Panel Settings

| Setting | Type | Default | Description |
|---------|------|---------|-------------|
| `datatext.enabled` | boolean | `true` | Enable the datatext panel |
| `datatext.slots` | table | `{"fps", "durability", "time"}` | Ordered list of datatext slot assignments (up to 3) |
| `datatext.forceSingleLine` | boolean | `true` | Force single-line layout (ignore text wrapping) |
| `datatext.height` | number | `22` | Panel height in pixels |
| `datatext.offsetY` | number | `0` | Vertical offset from minimap bottom |
| `datatext.bgOpacity` | number | `60` | Background opacity (0-100) |
| `datatext.borderSize` | number | `2` | Border thickness (0-8, 0 = hidden) |
| `datatext.borderColor` | color | `{0, 0, 0, 1}` | Border color (black) |
| `datatext.separator` | string | `"  "` | Text separator between datatexts |

### Per-Slot Configuration

Each slot (slot1, slot2, slot3) has individual offset and label settings.

| Setting | Type | Default (Slot 1 / 2 / 3) | Description |
|---------|------|--------------------------|-------------|
| `slotN.shortLabel` | boolean | `false` / `false` / `true` | Use abbreviated labels |
| `slotN.noLabel` | boolean | `false` | Hide label entirely (value only) |
| `slotN.xOffset` | number | `-1` / `6` / `3` | Horizontal offset for this slot |
| `slotN.yOffset` | number | `0` | Vertical offset for this slot |

### Font Settings

| Setting | Type | Default | Description |
|---------|------|---------|-------------|
| `datatext.font` | string | `"Quazii"` | Datatext font face (LibSharedMedia name) |
| `datatext.fontSize` | number | `13` | Datatext font size |
| `datatext.fontOutline` | string | `"OUTLINE"` | Font outline: `OUTLINE` (thin), `THICKOUTLINE`, `NONE` |

### Color Settings

| Setting | Type | Default | Description |
|---------|------|---------|-------------|
| `datatext.useClassColor` | boolean | `false` | Use class color for value text |
| `datatext.valueColor` | color | `{0.1, 1.0, 0.1, 1}` | Value text color (#1AFF1A green) |

### Time Settings

| Setting | Type | Default | Description |
|---------|------|---------|-------------|
| `datatext.timeFormat` | string | `"local"` | Time display: `local` (system) or `server` (realm) |
| `datatext.use24Hour` | boolean | `true` | Use 24-hour time format |

### System Datatext

Combined FPS and latency datatext with detailed tooltip information.

**DB path:** `db.profile.datatext.system`

| Setting | Type | Default | Description |
|---------|------|---------|-------------|
| `system.latencyType` | string | `"home"` | Latency type on main display: `home` or `world` |
| `system.showLatency` | boolean | `true` | Show Home/World latency in tooltip |
| `system.showProtocols` | boolean | `true` | Show IPv4/IPv6 protocol info in tooltip |
| `system.showBandwidth` | boolean | `true` | Show bandwidth/download percentage in tooltip |
| `system.showAddonMemory` | boolean | `true` | Show addon memory usage in tooltip |
| `system.addonCount` | number | `10` | Number of top addons to show (sorted by memory) |
| `system.showFpsStats` | boolean | `true` | Show FPS avg/low/high stats when Shift is held |

### Volume Datatext

| Setting | Type | Default | Description |
|---------|------|---------|-------------|
| `volume.volumeStep` | number | `5` | Volume change per mouse scroll (1-20) |
| `volume.controlType` | string | `"master"` | Volume channel: `master`, `music`, `sfx`, `ambience`, `dialog` |
| `volume.showIcon` | boolean | `false` | Show speaker icon instead of "Vol:" label |

### Currencies Datatext

| Setting | Type | Default | Description |
|---------|------|---------|-------------|
| `datatext.currencyOrder` | table | `{}` | Ordered list of currency IDs to display (up to 6) |
| `datatext.currencyEnabled` | table | `{}` | Per-currency toggle map (currency ID to boolean) |

### Social Datatexts

| Setting | Type | Default | Description |
|---------|------|---------|-------------|
| `datatext.showTotal` | boolean | `true` | Show total count for friends/guild datatexts |
| `datatext.showGuildName` | boolean | `false` | Show guild name in guild datatext |

### Player Spec Datatext

| Setting | Type | Default | Description |
|---------|------|---------|-------------|
| `datatext.specDisplayMode` | string | `"full"` | Display mode: `icon` (icon only), `loadout` (icon + loadout name), `full` (icon + spec/loadout) |

### Legacy Toggles

These settings are from the legacy composite mode and may be used for migration or fallback.

| Setting | Type | Default | Description |
|---------|------|---------|-------------|
| `datatext.showFPS` | boolean | `true` | Show FPS display |
| `datatext.showLatency` | boolean | `false` | Show latency display |
| `datatext.showDurability` | boolean | `true` | Show durability display |
| `datatext.showGold` | boolean | `false` | Show gold display |
| `datatext.showTime` | boolean | `true` | Show time display |
| `datatext.showCoords` | boolean | `false` | Show coordinates display |
| `datatext.showFriends` | boolean | `false` | Show friends count |
| `datatext.showGuild` | boolean | `false` | Show guild count |
| `datatext.showLootSpec` | boolean | `false` | Show loot specialization |
| `datatext.lockoutCacheMinutes` | number | `5` | Minutes between lockout data refresh (minimum 1) |
