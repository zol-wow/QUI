---
layout: default
title: Cooldown Manager
parent: Settings Reference
nav_order: 2
---

# Cooldown Manager Settings

The **Cooldown Manager** (CDM) tab configures the core HUD system that displays your abilities, buffs, and tracked resources. Settings are stored under `QUI.db.profile.ncdm` for bar configuration, with visibility, glow, and swipe settings at the profile root level.

---

## Engine

| Setting | Type | Default | Description |
|---------|------|---------|-------------|
| `ncdm.engine` | string | `"owned"` | CDM engine: `"owned"` (addon-owned frames, recommended) or `"classic"` (legacy Blizzard hooks) |

---

## Essential Bar

The primary ability bar, typically showing core rotational and cooldown abilities.

### General

| Setting | Type | Default | Description |
|---------|------|---------|-------------|
| `ncdm.essential.enabled` | boolean | `true` | Enable the Essential bar |
| `ncdm.essential.desaturateOnCooldown` | boolean | `true` | Desaturate (grey out) icons when on cooldown |
| `ncdm.essential.rangeIndicator` | boolean | `true` | Tint icons when target is out of range |
| `ncdm.essential.rangeColor` | color | `{0.8, 0.1, 0.1, 1}` | Range indicator tint color (red) |
| `ncdm.essential.usabilityIndicator` | boolean | `true` | Show unusable state on icons |
| `ncdm.essential.layoutDirection` | string | `"HORIZONTAL"` | Icon layout direction |

### Row Configuration (Row 1)

Each Essential bar supports up to 3 rows. All rows share the same setting structure. Row 1 defaults are shown below; rows 2 and 3 have the same structure with `row2`/`row3` prefixes.

| Setting | Type | Default | Description |
|---------|------|---------|-------------|
| `ncdm.essential.row1.iconCount` | number | `8` | Number of icons in this row (0 = row disabled) |
| `ncdm.essential.row1.iconSize` | number | `39` | Icon size in pixels |
| `ncdm.essential.row1.borderSize` | number | `1` | Border thickness around icons (0-5) |
| `ncdm.essential.row1.borderColorTable` | color | `{0, 0, 0, 1}` | Border color |
| `ncdm.essential.row1.aspectRatioCrop` | number | `1.0` | Aspect ratio (1.0 = square, higher = wider) |
| `ncdm.essential.row1.zoom` | number | `0` | Icon texture zoom/crop (0-0.2) |
| `ncdm.essential.row1.padding` | number | `2` | Spacing between icons (-20 to 20) |
| `ncdm.essential.row1.xOffset` | number | `0` | Row horizontal offset |
| `ncdm.essential.row1.yOffset` | number | `0` | Row vertical offset (-50 to 50) |
| `ncdm.essential.row1.durationSize` | number | `16` | Duration text font size (8-24) |
| `ncdm.essential.row1.durationOffsetX` | number | `0` | Duration text horizontal offset |
| `ncdm.essential.row1.durationOffsetY` | number | `0` | Duration text vertical offset |
| `ncdm.essential.row1.durationTextColor` | color | `{1, 1, 1, 1}` | Duration text color (white) |
| `ncdm.essential.row1.durationAnchor` | string | `"CENTER"` | Duration text anchor point |
| `ncdm.essential.row1.stackSize` | number | `12` | Stack count text font size (8-24) |
| `ncdm.essential.row1.stackOffsetX` | number | `0` | Stack text horizontal offset |
| `ncdm.essential.row1.stackOffsetY` | number | `2` | Stack text vertical offset |
| `ncdm.essential.row1.stackTextColor` | color | `{1, 1, 1, 1}` | Stack text color (white) |
| `ncdm.essential.row1.stackAnchor` | string | `"BOTTOMRIGHT"` | Stack text anchor point |

**Row 2** defaults are identical to Row 1 except `yOffset = 3`.

**Row 3** defaults are identical to Row 1 except `iconCount = 8`, `yOffset = 0`.

---

## Utility Bar

The secondary ability bar, typically showing defensive, utility, and situational abilities.

### General

| Setting | Type | Default | Description |
|---------|------|---------|-------------|
| `ncdm.utility.enabled` | boolean | `true` | Enable the Utility bar |
| `ncdm.utility.desaturateOnCooldown` | boolean | `true` | Desaturate icons when on cooldown |
| `ncdm.utility.rangeIndicator` | boolean | `true` | Tint icons when out of range |
| `ncdm.utility.rangeColor` | color | `{0.8, 0.1, 0.1, 1}` | Range indicator tint color |
| `ncdm.utility.usabilityIndicator` | boolean | `true` | Show unusable state |
| `ncdm.utility.layoutDirection` | string | `"HORIZONTAL"` | Icon layout direction |
| `ncdm.utility.anchorBelowEssential` | boolean | `false` | Auto-anchor below the Essential bar |
| `ncdm.utility.anchorGap` | number | `0` | Gap in pixels when anchored to Essential |

### Row Configuration (Row 1)

Utility rows follow the same structure as Essential rows with different defaults.

| Setting | Type | Default | Description |
|---------|------|---------|-------------|
| `ncdm.utility.row1.iconCount` | number | `6` | Number of icons in row 1 |
| `ncdm.utility.row1.iconSize` | number | `30` | Icon size in pixels (smaller than Essential) |
| `ncdm.utility.row1.durationSize` | number | `14` | Duration text font size |
| `ncdm.utility.row1.stackSize` | number | `14` | Stack count text font size |

All other row1 settings match the Essential row structure. **Rows 2 and 3** default to `iconCount = 0` (disabled), `iconSize = 30`, `row2.yOffset = 8`, `row3.yOffset = 4`.

---

## Buff Icons

Standalone buff/proc icon display, typically anchored near the CDM bars.

| Setting | Type | Default | Description |
|---------|------|---------|-------------|
| `ncdm.buff.enabled` | boolean | `true` | Enable Buff Icons display |
| `ncdm.buff.iconSize` | number | `32` | Icon size in pixels |
| `ncdm.buff.borderSize` | number | `1` | Border thickness (0-8) |
| `ncdm.buff.aspectRatioCrop` | number | `1.0` | Aspect ratio (1.0 = square) |
| `ncdm.buff.growthDirection` | string | `"CENTERED_HORIZONTAL"` | Growth direction: `"CENTERED_HORIZONTAL"`, `"LEFT"`, `"RIGHT"` |
| `ncdm.buff.zoom` | number | `0` | Icon texture zoom (0-0.2) |
| `ncdm.buff.padding` | number | `4` | Spacing between icons (-20 to 20) |
| `ncdm.buff.durationSize` | number | `14` | Duration text font size (8-24) |
| `ncdm.buff.durationOffsetX` | number | `0` | Duration text horizontal offset |
| `ncdm.buff.durationOffsetY` | number | `8` | Duration text vertical offset |
| `ncdm.buff.durationAnchor` | string | `"TOP"` | Duration text anchor point |
| `ncdm.buff.stackSize` | number | `14` | Stack count text font size (8-24) |
| `ncdm.buff.stackOffsetX` | number | `0` | Stack text horizontal offset |
| `ncdm.buff.stackOffsetY` | number | `-8` | Stack text vertical offset |
| `ncdm.buff.stackAnchor` | string | `"BOTTOM"` | Stack text anchor point |
| `ncdm.buff.anchorTo` | string | `"disabled"` | Anchor to another frame |
| `ncdm.buff.anchorPlacement` | string | `"center"` | Placement when anchored |
| `ncdm.buff.anchorSpacing` | number | `0` | Spacing from anchor frame |

---

## Tracked Bar

Horizontal bars that display tracked buff/debuff durations and cooldowns.

| Setting | Type | Default | Description |
|---------|------|---------|-------------|
| `ncdm.trackedBar.enabled` | boolean | `true` | Enable the Tracked Bar |
| `ncdm.trackedBar.hideIcon` | boolean | `false` | Hide the spell icon on bars |
| `ncdm.trackedBar.barHeight` | number | `25` | Bar height in pixels |
| `ncdm.trackedBar.barWidth` | number | `215` | Bar width in pixels |
| `ncdm.trackedBar.texture` | string | `"Quazii v5"` | Bar texture (LibSharedMedia name) |
| `ncdm.trackedBar.useClassColor` | boolean | `true` | Use class color for bars |
| `ncdm.trackedBar.barColor` | color | `{0.204, 0.827, 0.6, 1}` | Fallback bar color (mint accent) |
| `ncdm.trackedBar.barOpacity` | number | `1.0` | Bar opacity |
| `ncdm.trackedBar.borderSize` | number | `2` | Border thickness |
| `ncdm.trackedBar.bgColor` | color | `{0, 0, 0, 1}` | Background color |
| `ncdm.trackedBar.bgOpacity` | number | `0.5` | Background opacity |
| `ncdm.trackedBar.textSize` | number | `14` | Text font size |
| `ncdm.trackedBar.spacing` | number | `2` | Spacing between bars |
| `ncdm.trackedBar.growUp` | boolean | `true` | Grow upward (true) or downward (false) |
| `ncdm.trackedBar.inactiveMode` | string | `"hide"` | Inactive bar behavior: `"always"`, `"fade"`, `"hide"` |
| `ncdm.trackedBar.inactiveAlpha` | number | `0.3` | Opacity when inactive (fade mode) |
| `ncdm.trackedBar.desaturateInactive` | boolean | `false` | Desaturate icon when inactive |
| `ncdm.trackedBar.reserveSlotWhenInactive` | boolean | `false` | Keep bar slot reserved when inactive |
| `ncdm.trackedBar.autoWidth` | boolean | `false` | Auto-size width to match anchored frame |
| `ncdm.trackedBar.orientation` | string | `"horizontal"` | Bar orientation: `"horizontal"` or `"vertical"` |
| `ncdm.trackedBar.fillDirection` | string | `"up"` | Fill direction for vertical bars |
| `ncdm.trackedBar.anchorTo` | string | `"disabled"` | Anchor to another frame |
| `ncdm.trackedBar.anchorPlacement` | string | `"center"` | Placement when anchored |
| `ncdm.trackedBar.anchorSpacing` | number | `0` | Spacing from anchor frame |

---

## Custom Buffs

Track additional spell IDs as buff icons on the CDM display.

| Setting | Type | Default | Description |
|---------|------|---------|-------------|
| `ncdm.customBuffs.enabled` | boolean | `true` | Enable custom buff tracking |
| `ncdm.customBuffs.spellIDs` | table | `{1254638}` | List of spell IDs to track |

---

## CDM Visibility

Controls when the CDM bars (Essential, Utility, Buff, power bars) are shown or hidden. Stored at `QUI.db.profile.cdmVisibility`.

| Setting | Type | Default | Description |
|---------|------|---------|-------------|
| `cdmVisibility.showAlways` | boolean | `true` | Always show CDM bars |
| `cdmVisibility.showWhenTargetExists` | boolean | `true` | Show when you have a target |
| `cdmVisibility.showInCombat` | boolean | `false` | Show when in combat |
| `cdmVisibility.showInGroup` | boolean | `false` | Show when in a group |
| `cdmVisibility.showInInstance` | boolean | `false` | Show when in an instance |
| `cdmVisibility.showOnMouseover` | boolean | `false` | Show on mouseover |
| `cdmVisibility.fadeDuration` | number | `0.2` | Fade in/out animation duration (seconds) |
| `cdmVisibility.fadeOutAlpha` | number | `0` | Alpha when faded out (0 = fully hidden) |
| `cdmVisibility.hideWhenMounted` | boolean | `false` | Hide when mounted |
| `cdmVisibility.hideWhenInVehicle` | boolean | `false` | Hide when in a vehicle |
| `cdmVisibility.hideWhenFlying` | boolean | `false` | Hide when flying |
| `cdmVisibility.hideWhenSkyriding` | boolean | `false` | Hide when skyriding |
| `cdmVisibility.dontHideInDungeonsRaids` | boolean | `false` | Override hide rules inside dungeons and raids |

---

## Glow Effects

Configure proc/ready glow effects on Essential and Utility bar icons. Stored at `QUI.db.profile.customGlow`.

### Essential Glow

| Setting | Type | Default | Description |
|---------|------|---------|-------------|
| `customGlow.essentialEnabled` | boolean | `true` | Enable glow on Essential bar icons |
| `customGlow.essentialGlowType` | string | `"Pixel Glow"` | Glow style: `"Pixel Glow"`, `"Autocast Shine"`, `"Button Glow"` |
| `customGlow.essentialColor` | color | `{0.95, 0.95, 0.32, 1}` | Glow color (yellow/gold) |
| `customGlow.essentialLines` | number | `14` | Number of lines (Pixel Glow) or spots (Autocast Shine) |
| `customGlow.essentialFrequency` | number | `0.25` | Animation speed |
| `customGlow.essentialThickness` | number | `2` | Line thickness for Pixel Glow |
| `customGlow.essentialScale` | number | `1` | Scale for Autocast Shine |
| `customGlow.essentialXOffset` | number | `0` | Glow horizontal offset |
| `customGlow.essentialYOffset` | number | `0` | Glow vertical offset |

### Utility Glow

| Setting | Type | Default | Description |
|---------|------|---------|-------------|
| `customGlow.utilityEnabled` | boolean | `true` | Enable glow on Utility bar icons |
| `customGlow.utilityGlowType` | string | `"Pixel Glow"` | Glow style: `"Pixel Glow"`, `"Autocast Shine"`, `"Button Glow"` |
| `customGlow.utilityColor` | color | `{0.95, 0.95, 0.32, 1}` | Glow color (yellow/gold) |
| `customGlow.utilityLines` | number | `14` | Number of lines or spots |
| `customGlow.utilityFrequency` | number | `0.25` | Animation speed |
| `customGlow.utilityThickness` | number | `2` | Line thickness for Pixel Glow |
| `customGlow.utilityScale` | number | `1` | Scale for Autocast Shine |
| `customGlow.utilityXOffset` | number | `0` | Glow horizontal offset |
| `customGlow.utilityYOffset` | number | `0` | Glow vertical offset |

---

## Swipe Effects

Control cooldown swipe (clock-hand sweep) visibility on various frame types. Stored at `QUI.db.profile.cooldownSwipe`.

| Setting | Type | Default | Description |
|---------|------|---------|-------------|
| `cooldownSwipe.showGCDSwipe` | boolean | `false` | Show GCD swipe on CDM icons |
| `cooldownSwipe.showCooldownSwipe` | boolean | `false` | Show spell cooldown swipe on CDM icons |
| `cooldownSwipe.showBuffSwipe` | boolean | `false` | Show buff/aura duration swipe on Essential/Utility bars |
| `cooldownSwipe.showBuffIconSwipe` | boolean | `false` | Show swipe on Buff Icon viewer |

| `cooldownSwipe.showActionSwipe` | boolean | `true` | Show cooldown swipe on action bar buttons |
| `cooldownSwipe.showNcdmSwipe` | boolean | `true` | Show cooldown swipe on NCDM (owned engine) icons |
| `cooldownSwipe.showCustomTrackerSwipe` | boolean | `true` | Show cooldown swipe on custom tracker bars |

---

## Rotation Assist Icon

A standalone icon that displays the next recommended ability using Blizzard's `C_AssistedCombat` API. Stored at `QUI.db.profile.rotationAssistIcon`.

| Setting | Type | Default | Description |
|---------|------|---------|-------------|
| `rotationAssistIcon.enabled` | boolean | `false` | Enable rotation assist icon |
| `rotationAssistIcon.isLocked` | boolean | `true` | Lock icon position (prevent dragging) |
| `rotationAssistIcon.iconSize` | number | `56` | Icon size in pixels |
| `rotationAssistIcon.visibility` | string | `"always"` | Visibility: `"always"`, `"combat"`, `"hostile"` |
| `rotationAssistIcon.frameStrata` | string | `"MEDIUM"` | Frame strata level |
| `rotationAssistIcon.showBorder` | boolean | `true` | Show border around icon |
| `rotationAssistIcon.borderThickness` | number | `2` | Border thickness in pixels |
| `rotationAssistIcon.borderColor` | color | `{0, 0, 0, 1}` | Border color (black) |
| `rotationAssistIcon.cooldownSwipeEnabled` | boolean | `true` | Show cooldown swipe on the icon |
| `rotationAssistIcon.showKeybind` | boolean | `true` | Show keybind text on icon |
| `rotationAssistIcon.keybindFont` | string | `nil` | Keybind font (`nil` = use `general.font`) |
| `rotationAssistIcon.keybindSize` | number | `13` | Keybind text font size |
| `rotationAssistIcon.keybindColor` | color | `{1, 1, 1, 1}` | Keybind text color (white) |
| `rotationAssistIcon.keybindOutline` | boolean | `true` | Apply outline to keybind text |
| `rotationAssistIcon.keybindAnchor` | string | `"BOTTOMRIGHT"` | Keybind text anchor point |
| `rotationAssistIcon.keybindOffsetX` | number | `-2` | Keybind horizontal offset |
| `rotationAssistIcon.keybindOffsetY` | number | `2` | Keybind vertical offset |
| `rotationAssistIcon.positionX` | number | `0` | Horizontal position (from screen center) |
| `rotationAssistIcon.positionY` | number | `-180` | Vertical position (from screen center) |
