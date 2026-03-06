---
layout: default
title: Group Frames
parent: Settings Reference
nav_order: 4
---

# Group Frames

QUI Group Frames replace Blizzard's default party and raid frames with a fully custom secure header system. They support class colors, absorb shields, heal prediction, dispel overlays, range checking, role icons, threat borders, target highlights, click-casting, and automatic scaling based on group size.

Group Frames are **opt-in** and disabled by default. Enable them in `/qui` under Frames > Group Frames.

**DB path:** `db.profile.quiGroupFrames`

---

## General

General appearance settings that apply across all group frame elements.

| Setting | Type | Default | Description |
|---------|------|---------|-------------|
| `quiGroupFrames.enabled` | boolean | `false` | Enable QUI group frames (opt-in, replaces Blizzard frames) |
| `general.useClassColor` | boolean | `true` | Use class color for health bar fill |
| `general.texture` | string | `"Quazii v5"` | Health bar texture (LibSharedMedia name) |
| `general.borderSize` | number | `1` | Frame border thickness in pixels |
| `general.font` | string | `"Quazii"` | Font face for all text elements (LibSharedMedia name) |
| `general.fontSize` | number | `12` | Base font size |
| `general.fontOutline` | string | `"OUTLINE"` | Font outline style: `OUTLINE`, `THICKOUTLINE`, `NONE` |
| `general.showTooltips` | boolean | `true` | Show unit tooltips on hover |
| `general.darkMode` | boolean | `false` | Enable dark mode (muted health bar, darker background) |
| `general.darkModeHealthColor` | color | `{0.15, 0.15, 0.15, 1}` | Health bar color in dark mode |
| `general.darkModeBgColor` | color | `{0.25, 0.25, 0.25, 1}` | Background color in dark mode |

---

## Layout

Controls how frames are arranged, sorted, and grouped for party and raid.

| Setting | Type | Default | Description |
|---------|------|---------|-------------|
| `layout.growDirection` | string | `"DOWN"` | Frame grow direction: `DOWN`, `UP` |
| `layout.groupGrowDirection` | string | `"RIGHT"` | Raid group column direction: `RIGHT`, `LEFT` |
| `layout.spacing` | number | `2` | Pixel gap between individual frames |
| `layout.groupSpacing` | number | `10` | Pixel gap between raid group columns |
| `layout.showPlayer` | boolean | `true` | Include the player in the group display |
| `layout.sortMethod` | string | `"INDEX"` | Sort method: `INDEX` (group index), `NAME` (alphabetical) |
| `layout.sortByRole` | boolean | `true` | Sort by role priority (Tank > Healer > DPS) |
| `layout.groupBy` | string | `"GROUP"` | Grouping method: `GROUP` (raid group number), `ROLE`, `CLASS` |

---

## Dimensions

Frame sizes auto-scale based on current group size. Party uses the largest sizes, large raids use the smallest.

| Setting | Type | Default | Description |
|---------|------|---------|-------------|
| `dimensions.partyWidth` | number | `200` | Frame width in party (1-5 players) |
| `dimensions.partyHeight` | number | `40` | Frame height in party |
| `dimensions.smallRaidWidth` | number | `180` | Frame width in small raid (6-15 players) |
| `dimensions.smallRaidHeight` | number | `36` | Frame height in small raid |
| `dimensions.mediumRaidWidth` | number | `160` | Frame width in medium raid (16-25 players) |
| `dimensions.mediumRaidHeight` | number | `30` | Frame height in medium raid |
| `dimensions.largeRaidWidth` | number | `140` | Frame width in large raid (26-40 players) |
| `dimensions.largeRaidHeight` | number | `24` | Frame height in large raid |

---

## Health

Health text display on each unit frame.

| Setting | Type | Default | Description |
|---------|------|---------|-------------|
| `health.showHealthText` | boolean | `true` | Show health text on frames |
| `health.healthDisplayStyle` | string | `"percent"` | Display style: `percent`, `absolute`, `both`, `deficit` |
| `health.healthFontSize` | number | `12` | Health text font size |
| `health.healthAnchor` | string | `"RIGHT"` | Health text anchor point: `LEFT`, `RIGHT` |
| `health.healthOffsetX` | number | `-4` | Health text horizontal offset |
| `health.healthOffsetY` | number | `0` | Health text vertical offset |
| `health.healthTextColor` | color | `{1, 1, 1, 1}` | Health text color (white) |

---

## Power

Power bar (mana, rage, energy, etc.) displayed below the health bar.

| Setting | Type | Default | Description |
|---------|------|---------|-------------|
| `power.showPowerBar` | boolean | `true` | Show power bar beneath health |
| `power.powerBarHeight` | number | `4` | Power bar height in pixels |
| `power.powerBarUsePowerColor` | boolean | `true` | Use power type color (blue for mana, red for rage, etc.) |
| `power.powerBarColor` | color | `{0.2, 0.4, 0.8, 1}` | Fallback power bar color when type coloring is off |

---

## Name

Unit name text display settings.

| Setting | Type | Default | Description |
|---------|------|---------|-------------|
| `name.showName` | boolean | `true` | Show unit name text |
| `name.nameFontSize` | number | `12` | Name text font size |
| `name.nameAnchor` | string | `"LEFT"` | Name text anchor point: `LEFT`, `RIGHT` |
| `name.nameOffsetX` | number | `4` | Name text horizontal offset |
| `name.nameOffsetY` | number | `0` | Name text vertical offset |
| `name.maxNameLength` | number | `10` | Maximum name characters before truncation |
| `name.nameTextUseClassColor` | boolean | `false` | Use class color for name text |
| `name.nameTextColor` | color | `{1, 1, 1, 1}` | Name text color (white) |

---

## Indicators

Status icons and visual indicators displayed on frames.

| Setting | Type | Default | Description |
|---------|------|---------|-------------|
| `indicators.showRoleIcon` | boolean | `true` | Show role icon (tank/healer/DPS) |
| `indicators.roleIconSize` | number | `12` | Role icon size in pixels |
| `indicators.roleIconAnchor` | string | `"TOPLEFT"` | Role icon anchor point |
| `indicators.showReadyCheck` | boolean | `true` | Show ready check status icon |
| `indicators.showResurrection` | boolean | `true` | Show pending resurrection icon |
| `indicators.showSummonPending` | boolean | `true` | Show pending summon icon |
| `indicators.showLeaderIcon` | boolean | `true` | Show party/raid leader and assistant icon |
| `indicators.showTargetMarker` | boolean | `true` | Show raid target icons (skull, cross, etc.) |
| `indicators.showThreatBorder` | boolean | `true` | Show colored border when unit has threat |
| `indicators.threatColor` | color | `{1, 0, 0, 0.8}` | Threat border color (red) |
| `indicators.showPhaseIcon` | boolean | `true` | Show phase mismatch icon |

---

## Healer Features

Specialized overlays and indicators for healing-focused gameplay.

| Setting | Type | Default | Description |
|---------|------|---------|-------------|
| `healer.dispelOverlay.enabled` | boolean | `true` | Flash overlay when unit has a dispellable debuff |
| `healer.dispelOverlay.opacity` | number | `0.8` | Dispel overlay opacity (0-1) |
| `healer.targetHighlight.enabled` | boolean | `true` | Highlight border on your current target |
| `healer.targetHighlight.color` | color | `{1, 1, 1, 0.6}` | Target highlight border color |
| `healer.myBuffIndicator.enabled` | boolean | `false` | Show indicator for your active buffs on the unit |
| `healer.myBuffIndicator.color` | color | `{0.2, 0.8, 0.2, 0.5}` | My buff indicator color |
| `healer.defensiveIndicator.enabled` | boolean | `false` | Show indicator for active defensive cooldowns |
| `healer.defensiveIndicator.iconSize` | number | `16` | Defensive cooldown indicator icon size |

---

## Absorbs and Heal Prediction

Absorb shield overlay and incoming heal prediction bars.

| Setting | Type | Default | Description |
|---------|------|---------|-------------|
| `absorbs.enabled` | boolean | `true` | Show absorb shield overlay on health bar |
| `absorbs.color` | color | `{1, 1, 1, 1}` | Absorb overlay color |
| `absorbs.opacity` | number | `0.3` | Absorb overlay opacity |
| `healPrediction.enabled` | boolean | `true` | Show incoming heal prediction bar |
| `healPrediction.color` | color | `{0.2, 1, 0.2}` | Heal prediction bar color |
| `healPrediction.opacity` | number | `0.5` | Heal prediction bar opacity |

---

## Auras

Buff and debuff icon display on group frames.

| Setting | Type | Default | Description |
|---------|------|---------|-------------|
| `auras.showDebuffs` | boolean | `true` | Show debuff icons on frames |
| `auras.maxDebuffs` | number | `3` | Maximum number of debuff icons displayed |
| `auras.debuffIconSize` | number | `16` | Debuff icon size in pixels |
| `auras.showBuffs` | boolean | `false` | Show buff icons on frames |
| `auras.maxBuffs` | number | `0` | Maximum number of buff icons displayed |
| `auras.buffIconSize` | number | `14` | Buff icon size in pixels |
| `auras.showDurationColor` | boolean | `true` | Color aura borders based on remaining duration |
| `auras.showExpiringPulse` | boolean | `true` | Pulse animation when an aura is about to expire |

---

## Aura Indicators

Per-spec custom aura indicators (colored squares, bars, icons on specific frame positions).

| Setting | Type | Default | Description |
|---------|------|---------|-------------|
| `auraIndicators.enabled` | boolean | `false` | Enable custom aura indicators |
| `auraIndicators.usePresets` | boolean | `true` | Auto-load built-in indicator presets for current spec |
| `auraIndicators.specs` | table | `{}` | Per-spec indicator configuration (populated by user or presets) |

---

## Click-Cast

Click-casting allows binding spells to mouse clicks on group frames.

| Setting | Type | Default | Description |
|---------|------|---------|-------------|
| `clickCast.enabled` | boolean | `false` | Enable click-casting on group frames |
| `clickCast.perSpec` | boolean | `true` | Use separate click-cast bindings per specialization |
| `clickCast.smartRes` | boolean | `true` | Smart resurrection (auto-detect correct resurrection spell) |
| `clickCast.showTooltip` | boolean | `true` | Show click-cast binding tooltips |
| `clickCast.bindings` | table | `{}` | Click-cast binding configuration |

---

## Range

Out-of-range fading to indicate units beyond spell range.

| Setting | Type | Default | Description |
|---------|------|---------|-------------|
| `range.enabled` | boolean | `true` | Enable range check fading |
| `range.outOfRangeAlpha` | number | `0.4` | Frame opacity when unit is out of range (0-1) |

---

## Spotlight

Pin specific group members to a separate, independently positioned group.

| Setting | Type | Default | Description |
|---------|------|---------|-------------|
| `spotlight.enabled` | boolean | `false` | Enable spotlight frame group |
| `spotlight.growDirection` | string | `"DOWN"` | Spotlight frame grow direction |
| `spotlight.spacing` | number | `2` | Spacing between spotlight frames |
| `spotlight.useMainFrameStyle` | boolean | `true` | Match main group frame style settings |
| `spotlight.byRole` | table | `{}` | Auto-spotlight roles (e.g., `{"TANK"}`) |
| `spotlight.byName` | table | `{}` | Spotlight specific player names |

---

## Castbar

Optional cast bar display on group frames.

| Setting | Type | Default | Description |
|---------|------|---------|-------------|
| `castbar.enabled` | boolean | `false` | Show cast bars on group frames |
| `castbar.height` | number | `8` | Cast bar height in pixels |
| `castbar.showIcon` | boolean | `false` | Show spell icon on cast bar |
| `castbar.showText` | boolean | `false` | Show spell name text on cast bar |

---

## Portrait

Optional unit portraits on group frames.

| Setting | Type | Default | Description |
|---------|------|---------|-------------|
| `portrait.showPortrait` | boolean | `false` | Show unit portrait |
| `portrait.portraitSide` | string | `"LEFT"` | Portrait position: `LEFT`, `RIGHT` |
| `portrait.portraitSize` | number | `30` | Portrait size in pixels |

---

## Pets

Pet frame display attached to the group frames.

| Setting | Type | Default | Description |
|---------|------|---------|-------------|
| `pets.enabled` | boolean | `false` | Show pet frames |
| `pets.anchorTo` | string | `"BOTTOM"` | Pet frame anchor relative to group: `BOTTOM`, `RIGHT`, `LEFT` |
| `pets.anchorGap` | number | `2` | Gap between group frames and pet frames |

---

## Class Power

Class-specific resource pips (Holy Power, Chi, Combo Points, etc.) on group frames.

| Setting | Type | Default | Description |
|---------|------|---------|-------------|
| `classPower.enabled` | boolean | `false` | Show class power pips |
| `classPower.height` | number | `4` | Pip bar height in pixels |
| `classPower.spacing` | number | `1` | Gap between individual pips |

---

## Test Mode

Preview mode settings for configuring frames without being in a group.

| Setting | Type | Default | Description |
|---------|------|---------|-------------|
| `testMode.partyCount` | number | `5` | Number of simulated party members |
| `testMode.raidCount` | number | `25` | Number of simulated raid members |
