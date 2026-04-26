---
layout: default
title: Profiles
parent: Getting Started
nav_order: 3
---

# Profiles

Profiles are how QUI remembers your setup. If you understand this page, you can experiment much more freely without worrying about losing your preferred layout.

## The Simple Version

- Use **one shared profile** if you want multiple characters to look the same.
- Use a **character-specific profile** if one character needs a different layout or role setup.
- Use **spec-based switching** if you want a healing layout in one spec and a damage layout in another.

Manage your profiles in `/qui` under **General > Profiles**.

## When To Use Each Option

- **Shared profile**: best for players who want one consistent UI everywhere.
- **Character profile**: best when one class needs unique spacing, trackers, or bars.
- **Spec profile**: best when your roles are very different, like healing versus damage.

## Spec-Based Switching

QUI can automatically switch profiles when you change specializations. This is one of the best quality-of-life features in the addon if you play multiple roles.

To set this up:

1. Open `/qui` and go to **General > Profiles**.
2. Enable dual-spec profile switching.
3. Assign a profile to each of your specializations.
4. When you change specs, QUI will automatically load the associated profile.

## Import and Export

Profiles can be imported and exported as shareable strings. This is the easiest way to:

- try a new setup without rebuilding everything manually
- share your UI with a friend
- keep a backup before a big redesign

1. Open `/qui` and go to **General > Import / Export**.
2. To **export**, select the data you want to export and copy the generated string.
3. To **import**, paste a profile string into the import field and click Import.

## Partial Imports

You do not always need to replace your whole setup. QUI can import only specific parts of a profile.

- **Theme / Fonts / Colors** -- Update visual settings without moving frame positions.
- **Layout / Positions** -- Update frame positions without changing visual settings.
- **Module-specific** -- Update only the area you care about.

This is especially useful when you like someone else's style but want to keep your own frame placement.

## Bundled Presets

QUI includes bundled imports so you have a stable place to start:

- **QUI Edit Mode Base** for the base layout import.
- Bundled profile presets for players who want a ready-made starting point.

## Reset All Movers

If you have repositioned QUI frames and want to return them all to their default positions, use the **Reset All Movers** button found in the Profiles or Anchoring tab. This resets frame positions without affecting your other profile settings.

## Backup Tip

If you have a setup you really love, export it before making major changes. That gives you an easy rollback point even if you later decide to rebuild from scratch.
