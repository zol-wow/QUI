---
layout: default
title: Action Bars
parent: Settings Reference
nav_order: 5
---

# Action Bars

QUI Action Bars apply visual skinning and mouseover fade behavior to Blizzard's action buttons. The system hooks all standard action bars (1-8), pet bar, stance bar, micro menu, bag bar, extra action button, and zone ability button.

Bars are **fade-hidden by default** -- they appear on mouseover and hide when the cursor leaves. This is a common source of confusion for new users; disable fade or set `alwaysShowInCombat` if bars seem invisible.

**DB path:** `db.profile.actionBars`

---

## Global Settings

Global style settings applied to all action bar buttons. Individual bars can override these when `overrideEnabled` is set to `true`.

**DB path:** `db.profile.actionBars.global`

| Setting | Type | Default | Description |
|---------|------|---------|-------------|
| `global.skinEnabled` | boolean | `true` | Apply QUI button skinning (borders, gloss, backdrop) |
| `global.iconSize` | number | `36` | Base icon size in pixels (36x36) |
| `global.iconZoom` | number | `0.05` | Icon texture crop to remove transparent edges (0.05-0.15) |
| `global.showBackdrop` | boolean | `true` | Show dark backdrop behind icons |
| `global.backdropAlpha` | number | `0.8` | Backdrop opacity (0-1) |
| `global.showGloss` | boolean | `true` | Show gloss/shine overlay on buttons |
| `global.glossAlpha` | number | `0.6` | Gloss overlay opacity (0-1) |
| `global.showBorders` | boolean | `true` | Show button border frames |
| `global.showKeybinds` | boolean | `true` | Show keybind/hotkey text on buttons |
| `global.showMacroNames` | boolean | `false` | Show macro name text on buttons |
| `global.showCounts` | boolean | `true` | Show stack/charge count text |
| `global.hideEmptyKeybinds` | boolean | `false` | Hide keybind text on unbound buttons |
| `global.keybindFontSize` | number | `16` | Keybind text font size |
| `global.keybindColor` | color | `{1, 1, 1, 1}` | Keybind text color (white) |
| `global.keybindAnchor` | string | `"TOPRIGHT"` | Keybind text anchor point |
| `global.keybindOffsetX` | number | `0` | Keybind text horizontal offset |
| `global.keybindOffsetY` | number | `-5` | Keybind text vertical offset |
| `global.macroNameFontSize` | number | `10` | Macro name text font size |
| `global.macroNameColor` | color | `{1, 1, 1, 1}` | Macro name text color |
| `global.macroNameAnchor` | string | `"BOTTOM"` | Macro name text anchor point |
| `global.countFontSize` | number | `14` | Stack count text font size |
| `global.countColor` | color | `{1, 1, 1, 1}` | Stack count text color |
| `global.countAnchor` | string | `"BOTTOMRIGHT"` | Stack count text anchor point |
| `global.barScale` | number | `1.0` | Global scale multiplier for all bars (0.5-2.0) |
| `global.buttonSpacing` | number | `nil` | Button spacing override in pixels (`nil` = use Blizzard Edit Mode padding) |
| `global.hideEmptySlots` | boolean | `false` | Hide buttons with no ability assigned |
| `global.lockButtons` | boolean | `false` | Prevent dragging abilities off action buttons |
| `global.rangeIndicator` | boolean | `false` | Tint buttons red when target is out of range |
| `global.rangeColor` | color | `{0.8, 0.1, 0.1, 1}` | Out-of-range tint color |
| `global.usabilityIndicator` | boolean | `false` | Dim buttons for unusable abilities |
| `global.usabilityDesaturate` | boolean | `false` | Grey out (desaturate) unusable ability icons |
| `global.usabilityColor` | color | `{0.4, 0.4, 0.4, 1}` | Unusable ability dim color (when not desaturating) |
| `global.manaColor` | color | `{0.5, 0.5, 1.0, 1}` | Out-of-mana tint color |
| `global.fastUsabilityUpdates` | boolean | `false` | 5x faster range/usability checks (50ms vs 250ms) |
| `global.showTooltips` | boolean | `true` | Show tooltips when hovering action buttons |

---

## Fade Settings

Mouseover fade system that hides action bars until the cursor enters the bar region. All bars share these global fade parameters.

**DB path:** `db.profile.actionBars.fade`

| Setting | Type | Default | Description |
|---------|------|---------|-------------|
| `fade.enabled` | boolean | `true` | Master toggle for mouseover fade on all bars |
| `fade.fadeInDuration` | number | `0.2` | Fade-in animation speed in seconds |
| `fade.fadeOutDuration` | number | `0.3` | Fade-out animation speed in seconds |
| `fade.fadeOutAlpha` | number | `0.0` | Target opacity when fully faded out (0 = invisible) |
| `fade.fadeOutDelay` | number | `0.5` | Delay in seconds before fade-out begins after cursor leaves |
| `fade.alwaysShowInCombat` | boolean | `false` | Force bars to full opacity during combat |
| `fade.showWhenSpellBookOpen` | boolean | `false` | Force bars visible while the Spellbook is open |
| `fade.keepLeaveVehicleVisible` | boolean | `false` | Keep the leave-vehicle button visible when bars are faded |
| `fade.disableBelowMaxLevel` | boolean | `false` | Disable fade while character is below max level |
| `fade.linkBars1to8` | boolean | `false` | Link all action bars 1-8 for unified mouseover (hover any = show all) |

---

## Per-Bar Settings

Each action bar (bar1 through bar8) has its own configuration. Settings set to `nil` inherit from the global defaults. Style overrides only take effect when `overrideEnabled` is `true`.

**DB path:** `db.profile.actionBars.bars.barN` (where N is 1-8)

### Common Per-Bar Settings

| Setting | Type | Default | Description |
|---------|------|---------|-------------|
| `enabled` | boolean | `true` | Enable QUI skinning/fade for this bar |
| `fadeEnabled` | boolean | `nil` | Override fade for this bar (`nil` = use global) |
| `fadeOutAlpha` | number | `nil` | Override fade-out alpha (`nil` = use global) |
| `alwaysShow` | boolean | `false` | Keep this bar always visible (ignore fade) |

### Bar 1 Specific

| Setting | Type | Default | Description |
|---------|------|---------|-------------|
| `bars.bar1.hidePageArrow` | boolean | `true` | Hide the page-up/page-down arrows on the main action bar |

### Style Overrides (bar1-bar8)

When `overrideEnabled = true`, these per-bar values replace the global settings for that specific bar. All default to `nil` (use global) until the override is enabled.

| Setting | Type | Default | Description |
|---------|------|---------|-------------|
| `overrideEnabled` | boolean | `false` | Enable per-bar style overrides |
| `iconZoom` | number | `0.05` | Icon texture crop |
| `showBackdrop` | boolean | `nil` | Show backdrop (`nil` = global) |
| `backdropAlpha` | number | `0` | Backdrop opacity |
| `showGloss` | boolean | `nil` | Show gloss (`nil` = global) |
| `glossAlpha` | number | `0` | Gloss opacity |
| `showKeybinds` | boolean | `nil` | Show keybind text (`nil` = global) |
| `hideEmptyKeybinds` | boolean | `nil` | Hide empty keybinds (`nil` = global) |
| `keybindFontSize` | number | `8` | Keybind font size |
| `keybindColor` | color | `nil` | Keybind color (`nil` = global) |
| `keybindAnchor` | string | `nil` | Keybind anchor (`nil` = global) |
| `keybindOffsetX` | number | `-20` | Keybind horizontal offset |
| `keybindOffsetY` | number | `-20` | Keybind vertical offset |
| `showMacroNames` | boolean | `nil` | Show macro names (`nil` = global) |
| `macroNameFontSize` | number | `8` | Macro name font size |
| `showCounts` | boolean | `nil` | Show stack counts (`nil` = global) |
| `countFontSize` | number | `8` | Count font size |
| `countAnchor` | string | `nil` | Count anchor (`nil` = global) |
| `countOffsetX` | number | `-20` | Count horizontal offset |
| `countOffsetY` | number | `-20` | Count vertical offset |

---

## Special Bars

These bars support fade toggle but do **not** have style override settings.

**DB path:** `db.profile.actionBars.bars.<barKey>`

| Bar | Key | Default Enabled | Description |
|-----|-----|-----------------|-------------|
| Pet Bar | `pet` | `true` | Pet action bar (fade only) |
| Stance Bar | `stance` | `true` | Stance/shapeshifting bar (fade only) |
| Micro Menu | `microbar` | `true` | Micro menu bar -- Character, Spellbook, etc. (fade only) |
| Bag Bar | `bags` | `true` | Bag bar (fade only) |

Each special bar has: `enabled`, `fadeEnabled`, `fadeOutAlpha`, `alwaysShow` with the same meanings as the per-bar settings above.

---

## Extra Action Button

The Extra Action Button appears during boss encounters, quests, and special events.

**DB path:** `db.profile.actionBars.bars.extraActionButton`

| Setting | Type | Default | Description |
|---------|------|---------|-------------|
| `enabled` | boolean | `true` | Enable QUI handling of the Extra Action Button |
| `alwaysShow` | boolean | `true` | Always show when active (ignore fade) |
| `scale` | number | `1.0` | Scale multiplier |
| `offsetX` | number | `0` | Horizontal position offset |
| `offsetY` | number | `0` | Vertical position offset |
| `hideArtwork` | boolean | `false` | Hide the decorative artwork frame around the button |

---

## Zone Ability Button

The Zone Ability Button appears for garrison, covenant, and zone-specific powers.

**DB path:** `db.profile.actionBars.bars.zoneAbility`

| Setting | Type | Default | Description |
|---------|------|---------|-------------|
| `enabled` | boolean | `true` | Enable QUI handling of the Zone Ability Button |
| `alwaysShow` | boolean | `true` | Always show when active (ignore fade) |
| `scale` | number | `1.0` | Scale multiplier |
| `offsetX` | number | `0` | Horizontal position offset |
| `offsetY` | number | `0` | Vertical position offset |
| `hideArtwork` | boolean | `false` | Hide the decorative artwork frame around the button |
