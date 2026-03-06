---
layout: default
title: Cooldown Manager
parent: Features
nav_order: 1
---

# Cooldown Manager

The Cooldown Manager (CDM) is QUI's core feature. It displays your ability cooldowns as icon rows near your character, giving you at-a-glance visibility of what is ready, what is cooling down, and what is about to come off cooldown -- all without looking at your action bars.

## Overview

The CDM organizes your abilities into distinct bars, each with its own layout, icon size, and behavior. It knows your class and spec, automatically populating the bars with relevant spells. You can further customize what appears through per-character custom entries.

## How to Enable

The Cooldown Manager is enabled by default. To access its settings:

- Type `/cdm` in chat, or
- Open `/qui` and navigate to the **Cooldown Manager** tab.

## Engines

QUI ships with two CDM engines:

- **Owned** (default) -- Addon-created frames managed entirely by QUI. This is the active, maintained engine and the one you should use.
- **Classic** -- A legacy engine that hooks into Blizzard frames. It exists for backward compatibility but is no longer actively developed.

The engine is set in your profile and defaults to "owned."

## Key Features

- **Essential Bar** -- Your primary rotation abilities. Defaults to 8 icons per row with up to 3 rows. Default icon size is 39px.
- **Utility Bar** -- Defensive and utility cooldowns. Defaults to 6 icons per row (row 1 only; rows 2-3 are disabled by default). Default icon size is 30px.
- **Buff Icons** -- Tracked buff and aura display with customizable shape, growth direction, and duration/stack text.
- **Tracked Bar** -- Status bars for tracked buffs with inactive mode options: always visible, fade out, or hide entirely.
- **Custom Entries** -- Per-character spell or item additions to the Essential or Utility bars. Stored in your character-specific database (`db.char`), so each character can have unique additions.
- **Effects** -- Glow types (Pixel Glow, Autocast Shine, Button Glow) and swipe overlays for GCD, cooldown, buff duration, and recharge edge visualization.
- **Range Indicator** -- Tints icons red when your target is out of range for that ability.
- **Usability Indicator** -- Shows when abilities cannot currently be used (insufficient resources, wrong stance, etc.).
- **Desaturation** -- Icons go desaturated while on cooldown for clear visual distinction.
- **Keybind Display** -- Shows your keybind text on each icon so you always know which key to press.
- **Rotation Helper Overlay** -- Integrates with WoW's `C_AssistedCombat` API to highlight suggested abilities.

## Important Settings

| Setting | Description | Default |
|:--------|:------------|:--------|
| Engine | "owned" (addon frames) or "classic" (Blizzard hooks) | owned |
| Essential icon size | Pixel size of Essential bar icons | 39 |
| Essential icons per row | Number of icons before wrapping to a new row | 8 |
| Essential rows | Maximum number of rows (1-3) | 3 |
| Utility icon size | Pixel size of Utility bar icons | 30 |
| Utility icons per row | Number of icons before wrapping | 6 |
| Range indicator | Tint out-of-range icons red | Enabled |
| Desaturation | Desaturate icons on cooldown | Enabled |
| Show keybinds | Display keybind text on icons | Enabled |

## Visibility Rules

The CDM supports several visibility modes that control when bars appear:

- Always visible
- In combat only
- When you have a target
- While in a group
- On mouseover
- Custom combinations of the above

Configure these per-bar in the CDM settings.

## Tips

{: .note }
Custom entries are stored per-character, not per-profile. If you add a trinket to your Essential bar on one character, it will not appear on another character even if they share the same profile.

{: .important }
The "classic" engine is legacy code. If you experience issues with cooldown tracking, make sure your engine is set to "owned" -- it receives all bug fixes and new features.

{: .note }
You can add both spells and items as custom entries. This is especially useful for tracking trinket cooldowns or on-use items alongside your rotation abilities.
