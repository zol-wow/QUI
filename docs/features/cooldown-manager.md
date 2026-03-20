---
layout: default
title: Cooldown Manager
parent: Features
nav_order: 1
---

# Cooldown Manager

The Cooldown Manager (CDM) is QUI's core feature. It displays your ability cooldowns as icon rows near your character, giving you at-a-glance visibility of what is ready, what is cooling down, and what is about to come off cooldown -- all without looking at your action bars.

## Overview

The CDM organizes your abilities into **containers**, each with its own layout, icon size, and behavior. It knows your class and spec, automatically populating the containers with relevant spells. You can further customize what appears through per-character custom entries and the **Composer** interface in Layout Mode.

## How to Access Settings

CDM settings are accessed through **Layout Mode** or the `/cdm` shortcut:

- Type `/qui layout` to enter Layout Mode, then use the toolbar and drawer to access CDM settings.
- Type `/cdm` in chat to open CDM settings directly.

## Engines

QUI ships with two CDM engines:

- **Owned** (default) -- Addon-created frames managed entirely by QUI. This is the active, maintained engine and the one you should use. It supports the full container system, Composer, per-spell settings, aura containers, and all modern features.
- **Classic** -- A legacy engine that hooks into Blizzard frames. It exists for backward compatibility but is no longer actively developed.

The engine is set in your profile and defaults to "owned."

## Container System

The owned engine uses a flexible **container** system. Each container has a type that determines what it tracks and how it displays:

- **Cooldown** -- Tracks ability cooldowns. The Essential and Utility bars are cooldown containers.
- **Aura** -- Tracks buffs and debuffs as icon displays (replaces the old "Buff Icons" concept).
- **Aura Bar** -- Tracks buffs as status bars with progress indicators (replaces the old "Tracked Bar" concept).

Containers can be positioned independently in Layout Mode and each has its own layout settings (icon count, icon size, growth direction, rows, etc.).

## Key Features

- **Essential Container** -- Your primary rotation abilities. Defaults to 8 icons per row with up to 3 rows. Default icon size is 39px.
- **Utility Container** -- Defensive and utility cooldowns. Defaults to 6 icons per row (row 1 only; rows 2-3 are disabled by default). Default icon size is 30px.
- **Aura Containers** -- Tracked buff and aura display with customizable shape, growth direction, and duration/stack text.
- **Aura Bar Containers** -- Status bars for tracked buffs with inactive mode options: always visible, fade out, or hide entirely.
- **Composer** -- A Layout Mode interface for managing what spells appear in each container, reordering them, enabling/disabling individual spells, and configuring per-spell settings.
- **Custom Entries** -- Per-character spell or item additions to the Essential or Utility containers. Stored in your character-specific database (`db.char`), so each character can have unique additions.
- **Per-Spell Settings** -- Individual spells in the Composer can have per-entry overrides for enabled/disabled state, glow behavior, and other display options.
- **Effects** -- Glow types (Pixel Glow, Autocast Shine, Button Glow) and swipe overlays for GCD, cooldown, and buff duration visualization. Separate swipe color defaults for aura and cooldown swipes.
- **Range Indicator** -- Tints icons red when your target is out of range for that ability.
- **Usability Indicator** -- Shows when abilities cannot currently be used (insufficient resources, wrong stance, etc.).
- **Desaturation** -- Icons go desaturated while on cooldown for clear visual distinction.
- **Keybind Display** -- Shows your keybind text on each icon so you always know which key to press.
- **Click-to-Cast** -- CDM icons can function as clickable buttons with macro resolution and secure overlays.
- **Rotation Helper Overlay** -- Integrates with WoW's `C_AssistedCombat` API to highlight suggested abilities.
- **Growth Direction** -- Configurable growth direction for containers (horizontal/vertical, left/right, up/down, center).
- **Target Debuff Tracking** -- Aura containers can track debuffs on your target using `auraDataUnit` and `linkedSpellIDs` for ability-to-debuff mapping.

## Important Settings

| Setting | Description | Default |
|:--------|:------------|:--------|
| Engine | "owned" (addon frames) or "classic" (Blizzard hooks) | owned |
| Essential icon size | Pixel size of Essential container icons | 39 |
| Essential icons per row | Number of icons before wrapping to a new row | 8 |
| Essential rows | Maximum number of rows (1-3) | 3 |
| Utility icon size | Pixel size of Utility container icons | 30 |
| Utility icons per row | Number of icons before wrapping | 6 |
| Layout direction | HORIZONTAL or VERTICAL | HORIZONTAL |
| Range indicator | Tint out-of-range icons red | Enabled |
| Desaturation | Desaturate icons on cooldown | Enabled |
| Show keybinds | Display keybind text on icons | Enabled |
| Clickable icons | Enable click-to-cast on CDM icons | Disabled |

## Visibility Rules

The CDM supports several visibility modes that control when containers appear:

- Always visible
- In combat only
- When you have a target
- While in a group
- On mouseover
- Custom combinations of the above
- Hide when mounted, flying, skyriding, or in a vehicle

Configure these in the CDM visibility settings or via the HUD Visibility tab.

## Tips

{: .note }
Custom entries are stored per-character, not per-profile. If you add a trinket to your Essential container on one character, it will not appear on another character even if they share the same profile.

{: .important }
The "classic" engine is legacy code. If you experience issues with cooldown tracking, make sure your engine is set to "owned" -- it receives all bug fixes and new features.

{: .note }
You can add both spells and items as custom entries. This is especially useful for tracking trinket cooldowns or on-use items alongside your rotation abilities.

{: .note }
The Composer in Layout Mode is the primary tool for managing your CDM spell list. Use it to reorder spells, enable/disable individual entries, and adjust per-spell settings without leaving Layout Mode.
