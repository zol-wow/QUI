---
layout: default
title: Unit Frames
parent: Settings Reference
nav_order: 3
---

# Unit Frames Settings

The **Unit Frames** tab configures QUI's custom unit frames for Player, Target, Target-of-Target, Pet, Focus, and Boss units. All settings are stored under `QUI.db.profile.quiUnitFrames` with separate sub-tables for general settings and each unit type.

---

## General Unit Frame Settings

Shared settings that apply across all unit frames. Stored at `quiUnitFrames.general`.

| Setting | Type | Default | Description |
|---------|------|---------|-------------|
| `general.darkMode` | boolean | `false` | Enable dark mode for all unit frame health bars |
| `general.darkModeHealthColor` | color | `{0.15, 0.15, 0.15, 1}` | Dark mode health bar color |
| `general.darkModeBgColor` | color | `{0.25, 0.25, 0.25, 1}` | Dark mode background color |
| `general.darkModeOpacity` | number | `1.0` | Dark mode frame opacity (0.1-1.0) |
| `general.darkModeHealthOpacity` | number | `1.0` | Dark mode health bar opacity |
| `general.darkModeBgOpacity` | number | `1.0` | Dark mode background opacity |
| `general.defaultUseClassColor` | boolean | `true` | Use class color for health bars |
| `general.defaultHealthColor` | color | `{0.2, 0.2, 0.2, 1}` | Default health bar color (when class color off) |
| `general.defaultBgColor` | color | `{0, 0, 0, 1}` | Default background color |
| `general.defaultOpacity` | number | `1.0` | Default bar opacity |
| `general.defaultHealthOpacity` | number | `1.0` | Default health bar opacity |
| `general.defaultBgOpacity` | number | `1.0` | Default background opacity |
| `general.masterColorNameText` | boolean | `false` | Apply class/reaction color to all name text |
| `general.masterColorHealthText` | boolean | `false` | Apply class/reaction color to all health text |
| `general.masterColorPowerText` | boolean | `false` | Apply class/reaction color to all power text |
| `general.masterColorCastbarText` | boolean | `false` | Apply class/reaction color to all castbar text |
| `general.masterColorToTText` | boolean | `false` | Apply class/reaction color to all ToT text |
| `general.font` | string | `"Quazii"` | Font face for all unit frames |
| `general.fontSize` | number | `12` | Base font size |
| `general.fontOutline` | string | `"OUTLINE"` | Font outline: `"NONE"`, `"OUTLINE"`, `"THICKOUTLINE"` |
| `general.showTooltips` | boolean | `true` | Show tooltips on unit frame mouseover |
| `general.smootherAnimation` | boolean | `false` | Uncap 60 FPS throttle for smoother castbar animation |
| `general.hostilityColorHostile` | color | `{0.8, 0.2, 0.2, 1}` | Hostile NPC color (red) |
| `general.hostilityColorNeutral` | color | `{1, 1, 0.2, 1}` | Neutral NPC color (yellow) |
| `general.hostilityColorFriendly` | color | `{0.2, 0.8, 0.2, 1}` | Friendly NPC color (green) |

---

## Player Frame

Settings at `quiUnitFrames.player`. The Player frame is the most feature-rich unit frame with portrait, indicators, castbar, auras, absorbs, heal prediction, and power bar support.

### Frame Layout

| Setting | Type | Default | Description |
|---------|------|---------|-------------|
| `player.enabled` | boolean | `true` | Enable the Player unit frame |
| `player.borderSize` | number | `1` | Frame border thickness (0-5) |
| `player.width` | number | `240` | Frame width in pixels |
| `player.height` | number | `40` | Frame height in pixels |
| `player.offsetX` | number | `-290` | Horizontal offset from screen center |
| `player.offsetY` | number | `-219` | Vertical offset from screen center |
| `player.anchorTo` | string | `"disabled"` | Anchor to: `"disabled"`, `"essential"`, `"utility"`, `"primary"`, `"secondary"` |
| `player.anchorGap` | number | `10` | Gap when anchored to another frame |
| `player.anchorYOffset` | number | `0` | Vertical offset when anchored |
| `player.texture` | string | `"Quazii v5"` | Health bar texture |
| `player.useClassColor` | boolean | `true` | Use class color for health bar |
| `player.customHealthColor` | color | `{0.2, 0.6, 0.2, 1}` | Custom health color (when class color off) |

### Portrait

| Setting | Type | Default | Description |
|---------|------|---------|-------------|
| `player.showPortrait` | boolean | `false` | Show unit portrait |
| `player.portraitSide` | string | `"LEFT"` | Portrait position: `"LEFT"` or `"RIGHT"` |
| `player.portraitSize` | number | `40` | Portrait size in pixels |
| `player.portraitBorderSize` | number | `1` | Portrait border thickness |
| `player.portraitBorderUseClassColor` | boolean | `false` | Use class color for portrait border |
| `player.portraitBorderColor` | color | `{0, 0, 0, 1}` | Portrait border color |
| `player.portraitGap` | number | `0` | Gap between portrait and health bar |

### Name Text

| Setting | Type | Default | Description |
|---------|------|---------|-------------|
| `player.showName` | boolean | `true` | Show unit name |
| `player.nameTextUseClassColor` | boolean | `false` | Use class color for name text |
| `player.nameTextColor` | color | `{1, 1, 1, 1}` | Name text color (white) |
| `player.nameFontSize` | number | `16` | Name font size |
| `player.nameAnchor` | string | `"LEFT"` | Name text anchor point |
| `player.nameOffsetX` | number | `12` | Name horizontal offset |
| `player.nameOffsetY` | number | `0` | Name vertical offset |
| `player.maxNameLength` | number | `0` | Max name characters (0 = no limit) |

### Health Text

| Setting | Type | Default | Description |
|---------|------|---------|-------------|
| `player.showHealth` | boolean | `true` | Show health text |
| `player.showHealthPercent` | boolean | `true` | Show health percentage |
| `player.showHealthAbsolute` | boolean | `true` | Show absolute health value |
| `player.healthDisplayStyle` | string | `"both"` | Display style: `"percent"`, `"absolute"`, `"both"`, `"both_reverse"` |
| `player.healthDivider` | string | `" \| "` | Divider between percent and absolute: `" \| "`, `" - "`, `" / "` |
| `player.healthFontSize` | number | `16` | Health text font size |
| `player.healthAnchor` | string | `"RIGHT"` | Health text anchor point |
| `player.healthOffsetX` | number | `-12` | Health text horizontal offset |
| `player.healthOffsetY` | number | `0` | Health text vertical offset |
| `player.healthTextUseClassColor` | boolean | `false` | Use class color for health text |
| `player.healthTextColor` | color | `{1, 1, 1, 1}` | Custom health text color |

### Power Text

| Setting | Type | Default | Description |
|---------|------|---------|-------------|
| `player.showPowerText` | boolean | `false` | Show power resource text |
| `player.powerTextFormat` | string | `"percent"` | Format: `"percent"`, `"current"`, `"both"` |
| `player.powerTextUsePowerColor` | boolean | `true` | Use power type color (mana blue, rage red, etc.) |
| `player.powerTextUseClassColor` | boolean | `false` | Use class color for power text |
| `player.powerTextColor` | color | `{1, 1, 1, 1}` | Custom power text color |
| `player.powerTextFontSize` | number | `12` | Power text font size |
| `player.powerTextAnchor` | string | `"BOTTOMRIGHT"` | Power text anchor point |
| `player.powerTextOffsetX` | number | `-9` | Power text horizontal offset |
| `player.powerTextOffsetY` | number | `4` | Power text vertical offset |

### Power Bar

| Setting | Type | Default | Description |
|---------|------|---------|-------------|
| `player.showPowerBar` | boolean | `false` | Show inline power bar below health |
| `player.powerBarHeight` | number | `4` | Power bar height |
| `player.powerBarBorder` | boolean | `true` | Show power bar border |
| `player.powerBarUsePowerColor` | boolean | `true` | Use power type color |
| `player.powerBarColor` | color | `{0, 0.5, 1, 1}` | Custom power bar color |

### Absorbs & Heal Prediction

| Setting | Type | Default | Description |
|---------|------|---------|-------------|
| `player.absorbs.enabled` | boolean | `false` | Show absorb shields overlay |
| `player.absorbs.color` | color | `{1, 1, 1, 1}` | Absorb overlay color |
| `player.absorbs.opacity` | number | `0.3` | Absorb overlay opacity |
| `player.absorbs.texture` | string | `"QUI Stripes"` | Absorb overlay texture |
| `player.healPrediction.enabled` | boolean | `false` | Show incoming heal prediction |
| `player.healPrediction.color` | color | `{0.2, 1, 0.2}` | Heal prediction color (green) |
| `player.healPrediction.opacity` | number | `0.5` | Heal prediction opacity |

### Castbar

| Setting | Type | Default | Description |
|---------|------|---------|-------------|
| `player.castbar.enabled` | boolean | `true` | Enable castbar |
| `player.castbar.showIcon` | boolean | `true` | Show spell icon |
| `player.castbar.width` | number | `333` | Castbar width |
| `player.castbar.height` | number | `25` | Castbar height |
| `player.castbar.offsetX` | number | `0` | Horizontal offset |
| `player.castbar.offsetY` | number | `-35` | Vertical offset |
| `player.castbar.widthAdjustment` | number | `0` | Width adjustment |
| `player.castbar.fontSize` | number | `14` | Castbar text font size |
| `player.castbar.color` | color | `{0.404, 1, 0.984, 1}` | Castbar color (cyan) |
| `player.castbar.anchor` | string | `"none"` | Anchor mode: `"none"`, `"unitframe"` |
| `player.castbar.texture` | string | `"Quazii v5"` | Castbar texture |
| `player.castbar.bgColor` | color | `{0.149, 0.149, 0.149, 1}` | Background color |
| `player.castbar.borderSize` | number | `1` | Border thickness |
| `player.castbar.useClassColor` | boolean | `false` | Use class color for castbar |
| `player.castbar.highlightInterruptible` | boolean | `false` | Highlight interruptible casts |
| `player.castbar.interruptibleColor` | color | `{0.2, 0.8, 0.2, 1}` | Interruptible highlight color |
| `player.castbar.maxLength` | number | `0` | Max spell name length (0 = no limit) |

### Auras (Buffs/Debuffs)

| Setting | Type | Default | Description |
|---------|------|---------|-------------|
| `player.auras.showBuffs` | boolean | `false` | Show buffs on the frame |
| `player.auras.showDebuffs` | boolean | `false` | Show debuffs on the frame |
| `player.auras.iconSize` | number | `22` | Debuff icon size |
| `player.auras.debuffAnchor` | string | `"TOPLEFT"` | Debuff row anchor point |
| `player.auras.debuffGrow` | string | `"RIGHT"` | Debuff growth direction |
| `player.auras.debuffMaxIcons` | number | `4` | Max debuff icons shown |
| `player.auras.debuffOffsetX` | number | `0` | Debuff row horizontal offset |
| `player.auras.debuffOffsetY` | number | `0` | Debuff row vertical offset |
| `player.auras.buffIconSize` | number | `22` | Buff icon size |
| `player.auras.buffAnchor` | string | `"BOTTOMLEFT"` | Buff row anchor point |
| `player.auras.buffGrow` | string | `"RIGHT"` | Buff growth direction |
| `player.auras.buffMaxIcons` | number | `4` | Max buff icons shown |
| `player.auras.iconSpacing` | number | `2` | Spacing between icons |
| `player.auras.showDuration` | boolean | `false` | Show duration countdown text |
| `player.auras.durationSize` | number | `12` | Duration text font size |
| `player.auras.durationAnchor` | string | `"CENTER"` | Duration text anchor |
| `player.auras.showStack` | boolean | `true` | Show stack count text |
| `player.auras.stackSize` | number | `10` | Stack count font size |
| `player.auras.stackAnchor` | string | `"BOTTOMRIGHT"` | Stack text anchor |

### Indicators (Player Only)

| Setting | Type | Default | Description |
|---------|------|---------|-------------|
| `player.indicators.rested.enabled` | boolean | `false` | Show rested XP indicator |
| `player.indicators.rested.size` | number | `16` | Rested indicator size |
| `player.indicators.rested.anchor` | string | `"TOPLEFT"` | Rested indicator anchor |
| `player.indicators.combat.enabled` | boolean | `false` | Show combat indicator |
| `player.indicators.combat.size` | number | `16` | Combat indicator size |
| `player.indicators.combat.anchor` | string | `"TOPRIGHT"` | Combat indicator anchor |
| `player.indicators.stance.enabled` | boolean | `false` | Show stance/form text indicator |
| `player.indicators.stance.fontSize` | number | `12` | Stance text font size |
| `player.indicators.stance.anchor` | string | `"BOTTOM"` | Stance text anchor |
| `player.indicators.stance.useClassColor` | boolean | `true` | Use class color for stance text |
| `player.indicators.stance.showIcon` | boolean | `false` | Show stance icon instead of text |
| `player.indicators.stance.iconSize` | number | `14` | Stance icon size |

### Target Marker & Leader Icon

| Setting | Type | Default | Description |
|---------|------|---------|-------------|
| `player.targetMarker.enabled` | boolean | `false` | Show raid target marker (skull, cross, etc.) |
| `player.targetMarker.size` | number | `20` | Marker icon size |
| `player.targetMarker.anchor` | string | `"TOP"` | Marker anchor point |
| `player.leaderIcon.enabled` | boolean | `false` | Show leader/assistant crown icon |
| `player.leaderIcon.size` | number | `16` | Leader icon size |
| `player.leaderIcon.anchor` | string | `"TOPLEFT"` | Leader icon anchor |

---

## Target Frame

Settings at `quiUnitFrames.target`. The Target frame shares most settings with the Player frame but adds hostility coloring and inline Target-of-Target display.

### Key Differences from Player

| Setting | Type | Default | Description |
|---------|------|---------|-------------|
| `target.enabled` | boolean | `true` | Enable the Target unit frame |
| `target.width` | number | `240` | Frame width |
| `target.height` | number | `40` | Frame height |
| `target.offsetX` | number | `290` | Horizontal offset (right side of screen) |
| `target.offsetY` | number | `-219` | Vertical offset |
| `target.texture` | string | `"Quazii v5 Inverse"` | Health bar texture (inverse fill direction) |
| `target.invertHealthDirection` | boolean | `false` | Invert health depletion direction |
| `target.useHostilityColor` | boolean | `true` | Use red/yellow/green based on unit hostility |
| `target.nameAnchor` | string | `"RIGHT"` | Name text anchor (right-aligned) |
| `target.nameOffsetX` | number | `-9` | Name horizontal offset |
| `target.maxNameLength` | number | `10` | Truncate name to 10 characters |
| `target.healthAnchor` | string | `"LEFT"` | Health text anchor (left-aligned) |
| `target.healthOffsetX` | number | `9` | Health horizontal offset |

### Inline Target-of-Target

The Target frame can display the target's target name inline after the unit name (e.g., "Bossname >> YourName").

| Setting | Type | Default | Description |
|---------|------|---------|-------------|
| `target.showInlineToT` | boolean | `false` | Show inline Target-of-Target name |
| `target.totSeparator` | string | `" >> "` | Separator between target name and ToT name |
| `target.totUseClassColor` | boolean | `true` | Color ToT name by class/reaction |
| `target.totDividerUseClassColor` | boolean | `false` | Color divider by class/reaction |
| `target.totDividerColor` | color | `{1, 1, 1, 1}` | Custom divider color |
| `target.totNameCharLimit` | number | `0` | Max ToT name length (0 = no limit) |

### Target Castbar

| Setting | Type | Default | Description |
|---------|------|---------|-------------|
| `target.castbar.enabled` | boolean | `true` | Enable target castbar |
| `target.castbar.width` | number | `245` | Castbar width |
| `target.castbar.height` | number | `25` | Castbar height |
| `target.castbar.color` | color | `{0.2, 0.6, 1, 1}` | Castbar color (blue) |
| `target.castbar.notInterruptibleColor` | color | `{0.7, 0.2, 0.2, 1}` | Not-interruptible cast color |
| `target.castbar.anchor` | string | `"unitframe"` | Anchor to the unit frame |
| `target.castbar.highlightInterruptible` | boolean | `true` | Highlight interruptible casts |
| `target.castbar.interruptibleColor` | color | `{0.2, 0.8, 0.2, 1}` | Interruptible highlight color (green) |
| `target.castbar.maxLength` | number | `12` | Max spell name length |

### Target Absorbs

| Setting | Type | Default | Description |
|---------|------|---------|-------------|
| `target.absorbs.enabled` | boolean | `true` | Show absorb shields (enabled by default on Target) |

All other Target settings (portrait, power text/bar, auras, target marker, leader icon) follow the same structure as the Player frame with appropriate default differences.

---

## Target-of-Target Frame

Settings at `quiUnitFrames.targettarget`. A compact frame showing your target's target.

| Setting | Type | Default | Description |
|---------|------|---------|-------------|
| `targettarget.enabled` | boolean | `false` | Enable ToT frame (disabled by default) |
| `targettarget.width` | number | `160` | Frame width (compact) |
| `targettarget.height` | number | `30` | Frame height (compact) |
| `targettarget.offsetX` | number | `496` | Horizontal offset |
| `targettarget.offsetY` | number | `-214` | Vertical offset |
| `targettarget.texture` | string | `"Quazii"` | Health bar texture |
| `targettarget.useHostilityColor` | boolean | `true` | Use hostility coloring |
| `targettarget.healthDisplayStyle` | string | `"percent"` | Health display (percent only) |
| `targettarget.showHealthAbsolute` | boolean | `false` | Absolute health hidden |
| `targettarget.castbar.enabled` | boolean | `false` | Castbar disabled by default |
| `targettarget.absorbs.opacity` | number | `0.7` | Higher absorb opacity than Player |

---

## Pet Frame

Settings at `quiUnitFrames.pet`. A small frame for the player's pet.

| Setting | Type | Default | Description |
|---------|------|---------|-------------|
| `pet.enabled` | boolean | `true` | Enable Pet frame |
| `pet.width` | number | `140` | Frame width (small) |
| `pet.height` | number | `25` | Frame height (small) |
| `pet.offsetX` | number | `-340` | Horizontal offset |
| `pet.offsetY` | number | `-254` | Vertical offset |
| `pet.texture` | string | `"Quazii"` | Health bar texture |
| `pet.nameFontSize` | number | `10` | Name font size (smaller) |
| `pet.healthFontSize` | number | `10` | Health font size (smaller) |
| `pet.healthDisplayStyle` | string | `"percent"` | Health display (percent only) |
| `pet.showPowerBar` | boolean | `true` | Power bar enabled by default |
| `pet.powerBarHeight` | number | `3` | Thin power bar |
| `pet.castbar.enabled` | boolean | `false` | Castbar disabled by default |

---

## Focus Frame

Settings at `quiUnitFrames.focus`. Disabled by default; used for tracking a secondary target.

| Setting | Type | Default | Description |
|---------|------|---------|-------------|
| `focus.enabled` | boolean | `false` | Enable Focus frame (disabled by default) |
| `focus.width` | number | `160` | Frame width |
| `focus.height` | number | `30` | Frame height |
| `focus.offsetX` | number | `-496` | Horizontal offset (left side) |
| `focus.offsetY` | number | `-214` | Vertical offset |
| `focus.texture` | string | `"Quazii v5"` | Health bar texture |
| `focus.useHostilityColor` | boolean | `true` | Use hostility coloring |
| `focus.showPowerBar` | boolean | `true` | Power bar enabled |
| `focus.castbar.enabled` | boolean | `true` | Castbar enabled |
| `focus.castbar.showIcon` | boolean | `false` | Castbar icon hidden |
| `focus.castbar.anchor` | string | `"unitframe"` | Castbar anchored to frame |
| `focus.auras.debuffMaxIcons` | number | `16` | More debuff slots for focus tracking |
| `focus.auras.buffMaxIcons` | number | `16` | More buff slots for focus tracking |

Focus also supports portrait settings (same structure as Player/Target).

---

## Boss Frames

Settings at `quiUnitFrames.boss`. Displays up to 5 boss unit frames stacked vertically.

| Setting | Type | Default | Description |
|---------|------|---------|-------------|
| `boss.enabled` | boolean | `true` | Enable Boss frames |
| `boss.width` | number | `162` | Frame width |
| `boss.height` | number | `36` | Frame height |
| `boss.offsetX` | number | `974` | Horizontal offset (far right) |
| `boss.offsetY` | number | `106` | Vertical offset |
| `boss.spacing` | number | `35` | Vertical spacing between boss frames |
| `boss.texture` | string | `"Quazii v5"` | Health bar texture |
| `boss.useHostilityColor` | boolean | `true` | Use hostility coloring |
| `boss.customHealthColor` | color | `{0.6, 0.2, 0.2, 1}` | Custom health color (red tint) |
| `boss.nameFontSize` | number | `11` | Name font size (compact) |
| `boss.healthFontSize` | number | `11` | Health font size (compact) |
| `boss.healthDisplayStyle` | string | `"both"` | Show both percent and absolute |
| `boss.showPowerBar` | boolean | `true` | Power bar enabled |
| `boss.castbar.enabled` | boolean | `true` | Castbar enabled |
| `boss.castbar.height` | number | `16` | Compact castbar height |
| `boss.castbar.fontSize` | number | `11` | Compact castbar text |
| `boss.castbar.color` | color | `{1, 0.7, 0, 1}` | Castbar color (orange) |
| `boss.castbar.anchor` | string | `"unitframe"` | Castbar anchored to frame |

---

## Unit Frames Visibility

Controls when unit frames are shown or hidden. Stored at `QUI.db.profile.unitframesVisibility`.

| Setting | Type | Default | Description |
|---------|------|---------|-------------|
| `unitframesVisibility.showAlways` | boolean | `true` | Always show unit frames |
| `unitframesVisibility.showWhenTargetExists` | boolean | `false` | Show when you have a target |
| `unitframesVisibility.showInCombat` | boolean | `false` | Show when in combat |
| `unitframesVisibility.showInGroup` | boolean | `false` | Show when in a group |
| `unitframesVisibility.showInInstance` | boolean | `false` | Show when in an instance |
| `unitframesVisibility.showOnMouseover` | boolean | `false` | Show on mouseover |
| `unitframesVisibility.fadeDuration` | number | `0.2` | Fade animation duration (seconds) |
| `unitframesVisibility.fadeOutAlpha` | number | `0` | Alpha when faded out |
| `unitframesVisibility.alwaysShowCastbars` | boolean | `false` | Keep castbars visible even when UF hidden |
| `unitframesVisibility.hideWhenMounted` | boolean | `false` | Hide when mounted |
| `unitframesVisibility.hideWhenFlying` | boolean | `false` | Hide when flying |
| `unitframesVisibility.hideWhenSkyriding` | boolean | `false` | Hide when skyriding |
| `unitframesVisibility.dontHideInDungeonsRaids` | boolean | `false` | Override hide rules in dungeons and raids |

---

## Power Bar (Standalone)

A standalone power bar that attaches to CDM frames. Stored at `QUI.db.profile.powerBar`.

| Setting | Type | Default | Description |
|---------|------|---------|-------------|
| `powerBar.enabled` | boolean | `true` | Enable standalone power bar |
| `powerBar.attachTo` | string | `"EssentialCooldownViewer"` | Frame to attach to |
| `powerBar.height` | number | `8` | Bar height in pixels |
| `powerBar.width` | number | `326` | Bar width in pixels |
| `powerBar.borderSize` | number | `1` | Border thickness |
| `powerBar.offsetX` | number | `0` | Horizontal offset |
| `powerBar.offsetY` | number | `-204` | Vertical offset |
| `powerBar.texture` | string | `"Quazii v5"` | Bar texture |
| `powerBar.colorMode` | string | `"power"` | Color mode: `"power"` (type color) or `"class"` |
| `powerBar.usePowerColor` | boolean | `true` | Use power type color |
| `powerBar.useClassColor` | boolean | `false` | Use class color |
| `powerBar.customColor` | color | `{0.2, 0.6, 1, 1}` | Custom power bar color |
| `powerBar.showPercent` | boolean | `true` | Show percentage text |
| `powerBar.showText` | boolean | `true` | Show power text |
| `powerBar.textSize` | number | `16` | Text font size |
| `powerBar.bgColor` | color | `{0.078, 0.078, 0.078, 1}` | Background color |
| `powerBar.showTicks` | boolean | `false` | Show tick marks for segmented resources |
| `powerBar.tickThickness` | number | `2` | Tick mark thickness |
| `powerBar.tickColor` | color | `{0, 0, 0, 1}` | Tick mark color |
| `powerBar.orientation` | string | `"HORIZONTAL"` | Bar orientation |
| `powerBar.visibility` | string | `"always"` | Visibility: `"always"`, `"combat"`, `"hostile"` |
| `powerBar.lockedToEssential` | boolean | `false` | Auto-resize width to match Essential CDM |
| `powerBar.lockedToUtility` | boolean | `false` | Auto-resize width to match Utility CDM |
| `powerBar.snapGap` | number | `5` | Gap when snapped to CDM bar |

---

## Castbar (Standalone Player)

A standalone player castbar that attaches to CDM frames. Stored at `QUI.db.profile.castBar`.

| Setting | Type | Default | Description |
|---------|------|---------|-------------|
| `castBar.enabled` | boolean | `true` | Enable standalone player castbar |
| `castBar.attachTo` | string | `"EssentialCooldownViewer"` | Frame to attach to |
| `castBar.height` | number | `24` | Bar height |
| `castBar.offsetX` | number | `0` | Horizontal offset |
| `castBar.offsetY` | number | `-108.5` | Vertical offset |
| `castBar.texture` | string | `"Quazii"` | Bar texture |
| `castBar.color` | color | `{0.188, 1, 0.988, 1}` | Castbar color (cyan/mint) |
| `castBar.useClassColor` | boolean | `false` | Use class color |
| `castBar.textSize` | number | `16` | Text font size |
| `castBar.width` | number | `0` | Width (0 = auto-match attach target) |
| `castBar.bgColor` | color | `{0.078, 0.078, 0.067, 0.85}` | Background color |
| `castBar.showTimeText` | boolean | `true` | Show cast time text |
| `castBar.showIcon` | boolean | `true` | Show spell icon |

### Target Castbar (Standalone)

Stored at `QUI.db.profile.targetCastBar`.

| Setting | Type | Default | Description |
|---------|------|---------|-------------|
| `targetCastBar.enabled` | boolean | `true` | Enable standalone target castbar |
| `targetCastBar.attachTo` | string | `"QUICore_Target"` | Attach to Target unit frame |
| `targetCastBar.height` | number | `18` | Bar height |
| `targetCastBar.color` | color | `{1.0, 0.0, 0.0, 1.0}` | Castbar color (red) |
| `targetCastBar.width` | number | `241.2` | Bar width |

### Focus Castbar (Standalone)

Stored at `QUI.db.profile.focusCastBar`.

| Setting | Type | Default | Description |
|---------|------|---------|-------------|
| `focusCastBar.enabled` | boolean | `true` | Enable standalone focus castbar |
| `focusCastBar.attachTo` | string | `"QUICore_Focus"` | Attach to Focus unit frame |
| `focusCastBar.height` | number | `18` | Bar height |
| `focusCastBar.color` | color | `{1.0, 0.0, 0.0, 1.0}` | Castbar color (red) |
| `focusCastBar.width` | number | `241.2` | Bar width |

---

## Secondary Power Bar

A secondary resource bar (e.g., Holy Power, Soul Shards, Combo Points) that can position above or swap with the primary. Stored at `QUI.db.profile.secondaryPowerBar`.

| Setting | Type | Default | Description |
|---------|------|---------|-------------|
| `secondaryPowerBar.enabled` | boolean | `true` | Enable secondary power bar |
| `secondaryPowerBar.attachTo` | string | `"EssentialCooldownViewer"` | Frame to attach to |
| `secondaryPowerBar.height` | number | `8` | Bar height |
| `secondaryPowerBar.width` | number | `326` | Bar width |
| `secondaryPowerBar.borderSize` | number | `1` | Border thickness |
| `secondaryPowerBar.texture` | string | `"Quazii v5"` | Bar texture |
| `secondaryPowerBar.colorMode` | string | `"power"` | Color mode: `"power"` or `"class"` |
| `secondaryPowerBar.showPercent` | boolean | `false` | Show percentage text |
| `secondaryPowerBar.showText` | boolean | `false` | Show power text |
| `secondaryPowerBar.showTicks` | boolean | `true` | Show tick marks for segmented resources |
| `secondaryPowerBar.tickThickness` | number | `2` | Tick mark thickness |
| `secondaryPowerBar.tickColor` | color | `{0, 0, 0, 1}` | Tick mark color |
| `secondaryPowerBar.lockedToPrimary` | boolean | `true` | Position above primary power bar and match width |
| `secondaryPowerBar.swapToPrimaryPosition` | boolean | `false` | Swap to primary bar position (supported specs) |
| `secondaryPowerBar.hidePrimaryOnSwap` | boolean | `false` | Auto-hide primary bar when swapped |
| `secondaryPowerBar.showFragmentedPowerBarText` | boolean | `false` | Show text on fragmented power bars |
| `secondaryPowerBar.orientation` | string | `"AUTO"` | Bar orientation |
| `secondaryPowerBar.visibility` | string | `"always"` | Visibility rule |

---

## Reticle (GCD Cursor Ring)

A cursor-attached ring that displays the GCD cooldown. Stored at `QUI.db.profile.reticle`.

| Setting | Type | Default | Description |
|---------|------|---------|-------------|
| `reticle.enabled` | boolean | `false` | Enable reticle |
| `reticle.reticleStyle` | string | `"dot"` | Center style: `"dot"`, `"cross"`, `"chevron"`, `"diamond"` |
| `reticle.reticleSize` | number | `10` | Center marker size (4-20) |
| `reticle.ringStyle` | string | `"standard"` | Ring style: `"thin"`, `"standard"`, `"thick"`, `"solid"` |
| `reticle.ringSize` | number | `40` | Ring diameter in pixels (20-80) |
| `reticle.useClassColor` | boolean | `false` | Use class color vs custom |
| `reticle.customColor` | color | `{1, 1, 1, 1}` | Custom ring color (white) |
| `reticle.gcdEnabled` | boolean | `true` | Show GCD swipe on ring |
| `reticle.gcdFadeRing` | number | `0.35` | Fade ring opacity during GCD (0-1) |
| `reticle.gcdReverse` | boolean | `false` | Reverse GCD swipe direction |
| `reticle.hideOutOfCombat` | boolean | `false` | Hide when not in combat |
| `reticle.inCombatAlpha` | number | `1.0` | In-combat opacity |
| `reticle.outCombatAlpha` | number | `1.0` | Out-of-combat opacity |
| `reticle.offsetX` | number | `0` | Horizontal offset from cursor |
| `reticle.offsetY` | number | `0` | Vertical offset from cursor |
| `reticle.hideOnRightClick` | boolean | `false` | Hide when right mouse button held |

---

## Crosshair

A screen-center crosshair overlay. Stored at `QUI.db.profile.crosshair`.

| Setting | Type | Default | Description |
|---------|------|---------|-------------|
| `crosshair.enabled` | boolean | `false` | Enable crosshair |
| `crosshair.onlyInCombat` | boolean | `false` | Only show in combat |
| `crosshair.size` | number | `9` | Line half-length from center |
| `crosshair.thickness` | number | `3` | Line thickness in pixels |
| `crosshair.borderSize` | number | `3` | Border thickness around lines |
| `crosshair.lineColor` | color | `{0.796, 1, 0.780, 1}` | Crosshair line color |
| `crosshair.borderColorTable` | color | `{0, 0, 0, 1}` | Border color |
| `crosshair.strata` | string | `"LOW"` | Frame strata level |
| `crosshair.offsetX` | number | `0` | Horizontal offset from screen center |
| `crosshair.offsetY` | number | `0` | Vertical offset from screen center |
| `crosshair.changeColorOnRange` | boolean | `false` | Change color based on target range |
| `crosshair.enableMeleeRangeCheck` | boolean | `true` | Check melee range (5 yards) |
| `crosshair.enableMidRangeCheck` | boolean | `false` | Check mid-range (25 yards) for Evokers |
| `crosshair.outOfRangeColor` | color | `{1, 0.2, 0.2, 1}` | Out of range color (red) |
| `crosshair.midRangeColor` | color | `{1, 0.6, 0.2, 1}` | Mid-range color (orange) |
| `crosshair.rangeColorInCombatOnly` | boolean | `false` | Only change color in combat |
| `crosshair.hideUntilOutOfRange` | boolean | `false` | Only show crosshair when out of range in combat |

---

## Range Check

A text display showing the distance bracket to your current target. Stored at `QUI.db.profile.rangeCheck`.

| Setting | Type | Default | Description |
|---------|------|---------|-------------|
| `rangeCheck.enabled` | boolean | `false` | Enable range display |
| `rangeCheck.combatOnly` | boolean | `false` | Only show in combat |
| `rangeCheck.showOnlyWithTarget` | boolean | `true` | Only show when you have a target |
| `rangeCheck.updateRate` | number | `0.1` | Update frequency in seconds |
| `rangeCheck.shortenText` | boolean | `false` | Use abbreviated range text |
| `rangeCheck.dynamicColor` | boolean | `false` | Change text color by distance |
| `rangeCheck.font` | string | `"Quazii"` | Font face |
| `rangeCheck.fontSize` | number | `22` | Font size |
| `rangeCheck.useClassColor` | boolean | `false` | Use class color for text |
| `rangeCheck.textColor` | color | `{0.2, 0.95, 0.55, 1}` | Text color (green) |
| `rangeCheck.strata` | string | `"MEDIUM"` | Frame strata |
| `rangeCheck.offsetX` | number | `0` | Horizontal offset |
| `rangeCheck.offsetY` | number | `-190` | Vertical offset |
