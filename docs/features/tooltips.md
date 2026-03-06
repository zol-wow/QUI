---
layout: default
title: Tooltips
parent: Features
nav_order: 6
---

# Tooltips

QUI's tooltip module reskins and enhances the default World of Warcraft tooltips, giving you full control over appearance, positioning, and per-context visibility. Whether you want tooltips anchored to your cursor, hidden during combat, or only shown when holding a modifier key, the tooltip module has you covered.

## Overview

The tooltip module replaces the default Blizzard tooltip appearance with QUI's themed style -- a dark background, mint accent border, and consistent fonts. Beyond visual changes, it adds practical features like class-colored player names, spell ID display for addon developers, and granular control over when and where tooltips appear. Each tooltip context (NPCs, abilities, items, frames, CDM icons, custom trackers) can be independently configured to always show, always hide, or require a modifier key.

## How to Enable

The tooltip module is enabled by default. To configure it:

- Open `/qui` and navigate to the **QoL** tab, then select **Tooltips**.

## Key Features

- **QUI-themed appearance** -- Dark background with mint accent border, replacing the default Blizzard tooltip style.
- **Cursor anchoring** -- Attach tooltips to your cursor with configurable X/Y offset, or keep the default Blizzard anchor position.
- **Combat hiding** -- Automatically hides tooltips during combat to reduce clutter (enabled by default).
- **Combat modifier key** -- When combat hiding is active, hold a modifier key (SHIFT by default) to force tooltips to appear in combat.
- **Class-colored player names** -- Player names in tooltips are colored by their class for quick identification.
- **Per-context visibility** -- Each tooltip context can be set to SHOW, HIDE, or require a modifier (SHIFT, CTRL, ALT):
  - NPCs
  - Abilities
  - Items
  - Unit frames
  - CDM icons
  - Custom trackers
- **Spell ID display** -- Shows the spell ID on ability tooltips, useful for debugging and addon development.
- **Health bar toggle** -- Option to hide the health bar on unit tooltips for a cleaner look.
- **Border customization** -- Choose between class color or accent color for the tooltip border, with adjustable thickness (1-10px).
- **Background opacity** -- Slider to control tooltip background transparency.

## Important Settings

| Setting | Description | Default |
|:--------|:------------|:--------|
| Anchor to cursor | Attach tooltip to cursor instead of default position | Disabled |
| Cursor offset X/Y | Pixel offset from cursor when anchored | 0, 0 |
| Hide in combat | Suppress tooltips during combat | Enabled |
| Combat key | Modifier to force-show tooltips in combat | SHIFT |
| Border color | Class color or accent color | Accent |
| Border thickness | Border width in pixels (1-10) | 2 |
| Show spell IDs | Display spell IDs on ability tooltips | Disabled |
| Hide health bar | Remove health bar from unit tooltips | Disabled |
| Background opacity | Tooltip background transparency | 1.0 |

## Tips

{: .note }
The per-context visibility system is powerful for reducing tooltip noise. For example, you can set NPC tooltips to SHOW but ability tooltips to SHIFT, so you only see spell information when you explicitly hold Shift over an action bar button.

{: .important }
Combat hiding is enabled by default for a reason -- tooltips can be distracting during encounters. If you disable it, consider setting a combat modifier key so you can still access tooltip information when needed without it appearing automatically.

{: .note }
The spell ID display option is primarily intended for addon developers and advanced users who need to look up spell IDs for WeakAuras, custom trackers, or bug reports. Most players can leave this disabled.
