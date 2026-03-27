---
layout: default
title: First Setup
parent: Getting Started
nav_order: 2
---

# First Setup

After installing QUI, follow these steps to get the full experience up and running.

## Step 1: Import the Edit Mode Layout

QUI is designed around a specific Blizzard Edit Mode layout. Importing it ensures that default Blizzard frames are positioned correctly for QUI's design.

1. Open QUI settings with `/qui`.
2. Go to the **Import & Export Strings** tab.
3. Select the **QUI Edit Mode Base** preset and copy the Edit Mode layout string.
4. Open Blizzard's **Edit Mode** (press `Escape` > `Edit Mode`, or use the keybind).
5. Click **Import** in Edit Mode and paste the string.
6. Apply the imported layout.

## Step 2: Browse the Settings

Open `/qui` and take a moment to explore the available tabs. Each tab controls a different area of the UI. You do not need to change anything right away -- the defaults are a solid starting point.

## Step 3: Import a QUI Profile

QUI comes with bundled profile presets that configure all QUI-specific settings (fonts, textures, frame visibility, cooldown tracking, and more).

1. In `/qui`, navigate to the **Import & Export Strings** tab.
2. Select one of the bundled presets (e.g., the **Quazii** profile or the **Dark Mode** variant).
3. Click **Import** to apply the profile.

## Step 4: Reload

Type `/rl` to reload the UI. This ensures all settings are fully applied.

## Step 5: Enter Layout Mode

Type `/qui layout` to enter Layout Mode. This is where you can:

- Reposition CDM bars, unit frames, group frames, and other QUI elements by dragging their handles.
- Access CDM, Group Frames, and Minimap settings through the Layout Mode toolbar and drawer.
- Fine-tune frame spacing, anchoring, and layout direction.
- Click **Save** when you are happy with the layout.

## Important Notes

- **Action bars are hidden on mouseover by default.** If your action bars seem to have disappeared, move your mouse to where they should be. You can disable this behavior in the **Action Bars** tab within `/qui`.

- **CDM (Cooldown Manager) is enabled by default.** The Essential bar is on by default. If you do not see cooldown icons, enter Layout Mode (`/qui layout`) to position them, or check that your spec's spells are populated in the CDM settings. The intro message on first login will remind you to configure CDM.

- **CDM, Group Frames, and Minimap settings are in Layout Mode.** These settings have been moved out of the main `/qui` options panel and into Layout Mode's side panels and toolbar. Use `/qui layout` to access them.

## Tip: CDM Icon Size in Edit Mode

When positioning CDM bars in Blizzard Edit Mode, set the icon size to **100%** on CDM bars. This prevents scaling conflicts between Edit Mode and QUI's own scaling system.
