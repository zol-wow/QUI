---
layout: default
title: First Setup
parent: Getting Started
nav_order: 2
---

# First Setup

If you want QUI to feel right quickly, follow these steps in order. This is the setup path most players should use on their first login.

![Actual QUI sidebar navigation]({{ '/assets/images/qui-sidebar-navigation.png' | relative_url }})
_Actual QUI navigation panel, which is the quickest way to move between setup areas while you are getting started._

## Step 1: Open QUI

Type `/qui` in chat to open the main settings window.

This is the control center for feature tiles like Action Bars, Unit Frames, Group Frames, Appearance, and Quality of Life, plus the **General** tile for profiles and import/export tools.

## Step 2: Import the Base Layout

QUI is designed around a specific base layout. Importing that layout first gives the rest of the addon a clean starting point.

1. Open QUI settings with `/qui`.
2. Open **General > Import / Export**.
3. Select the **QUI Edit Mode Base** preset and copy the Edit Mode layout string.
4. Open Blizzard's **Edit Mode** (press `Escape` > `Edit Mode`, or use the keybind).
5. Click **Import** in Edit Mode and paste the string.
6. Apply the imported layout.

## Step 3: Import a QUI Profile

The layout handles placement. The profile handles how QUI itself behaves.

1. In `/qui`, navigate to **General > Import / Export**.
2. Select one of the bundled presets (e.g., the **Quazii** profile or the **Dark Mode** variant).
3. Click **Import** to apply the profile.

If you prefer to build your own look later, you can still start from a bundled profile and gradually change it.

## Step 4: Reload Once

Type `/rl` to reload the UI. This ensures all settings are fully applied.

## Step 5: Enter Layout Mode

Type `/qui layout` to enter Layout Mode. This is where you can:

- Reposition CDM bars, unit frames, group frames, minimap-related panels, and other QUI elements.
- Use the mover-side controls for quick placement adjustments while you arrange the HUD.
- Fine-tune spacing, anchoring, and visual grouping until the HUD feels natural on your screen.
- Click **Save** when you are done.

## Step 6: Do a Quick Comfort Pass

Before you head into real content, spend two minutes checking:

- Are your action bars visible the way you expect?
- Is the Cooldown Manager close enough to your character to read comfortably?
- Do your player and target frames sit where your eyes naturally go?
- If you heal or support, do you want to enable Group Frames now or later?

## Important Notes

- **Action bars may fade on mouseover.** If they seem to be missing, move your mouse over the bottom-center area first.

- **CDM is one of the main reasons people use QUI.** If you do not immediately love where it is sitting, move it before judging the addon.

- **Some important settings live in Layout Mode.** CDM, Group Frames, and Minimap-related tuning are not only in the main `/qui` window.

## Tip: CDM Icon Size in Edit Mode

When positioning CDM bars in Blizzard Edit Mode, set the icon size to **100%** on CDM bars. This prevents scaling conflicts between Edit Mode and QUI's own scaling system.
