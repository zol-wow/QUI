---
layout: default
title: Profiles
parent: Getting Started
nav_order: 3
---

# Profiles

QUI uses the **AceDB** profile system to manage your settings. Profiles let you save, switch, copy, and share complete configurations.

## How Profiles Work

- **Default profile:** When you first log in, QUI creates a `Default` profile that all characters share.
- **Per-character profiles:** You can create a profile for a specific character. That character will use its own settings while others continue using the Default profile.
- **Copying and resetting:** You can copy settings from one profile to another, or reset a profile back to defaults.

Manage your profiles in `/qui` under the **Profiles** tab.

## Spec-Based Profile Switching

QUI integrates with **LibDualSpec** to automatically switch profiles when you change specializations. This is useful if you want different UI layouts for healing versus DPS, for example.

To set this up:

1. Open `/qui` and go to the **Profiles** tab.
2. Enable dual-spec profile switching.
3. Assign a profile to each of your specializations.
4. When you change specs, QUI will automatically load the associated profile.

## Import and Export

QUI supports importing and exporting profiles as compressed text strings, using **LibDeflate** for compression. This makes it easy to share your setup with others or back up your configuration.

1. Open `/qui` and go to the **Import & Export Strings** tab.
2. To **export**, select the data you want to export and copy the generated string.
3. To **import**, paste a profile string into the import field and click Import.

Profile strings include validation checks (maximum depth of 20, maximum of 50,000 nodes, and type checking) to ensure safe imports.

## Bundled Presets

QUI ships with several built-in profile presets that you can import from the **Import & Export Strings** tab:

| Preset | Description |
|--------|-------------|
| **Quazii Profile** | The standard QUI layout and settings. |
| **Quazii Dark Mode** | A darker visual variant of the standard profile. |
| **Quazii Details!** | Details damage meter profile complementing QUI's style. |
| **Quazii Plater** | Nameplate settings for the Plater addon. |
| **Quazii Platynator** | Nameplate settings for the Platynator addon. |
| **QUI Edit Mode Base** | The base Blizzard Edit Mode layout string (for Blizzard Edit Mode import). |
| **Quazii Edit Mode** | Quazii's original Blizzard Edit Mode layout string. |

## Reset All Movers

If you have repositioned QUI frames and want to return them all to their default positions, use the **Reset All Movers** button found in the Profiles or Anchoring tab. This resets frame positions without affecting your other profile settings.

## SavedVariables

QUI stores its data in two SavedVariables files:

- **QUI_DB** -- Primary database (AceDB profiles, per-character settings, global settings).
- **QUIDB** -- Secondary storage.

These files are located in your WoW installation at:
```
World of Warcraft\_retail_\WTF\Account\<ACCOUNT>\SavedVariables\QUI.lua
```

They are saved automatically when you log out or reload the UI.

## Migration Test Matrix

Use this checklist when validating changes to profile import, layout migration, or SavedVariables upgrades.

### Required Fixtures

- One `main`-era healing profile with non-default frame positions.
- One `main`-era `QUI1:` export string from the same character/profile.
- One old SavedVariables file copied before installing the next-version addon.

### Scenario 1: Old SavedVariables Upgrade

1. Install the next-version addon over the old SavedVariables file.
2. Log in on the healing character and let the addon load normally.
3. Verify that these elements still match the `main` branch look before touching any settings:
   - player, target, focus, pet, boss, and ToT frames
   - party and raid frame placement
   - cast bars and power bars
   - CDM essential and utility containers
   - loot window, loot history, and loot roll spacing
   - minimap, micro menu, and bag bar visibility
   - objective tracker, alert toasts, and ready-check/consumable anchors
   - addon accent/theme output

### Scenario 2: Old Profile Import

1. Start from a clean or throwaway next-version profile.
2. Import the `main`-era `QUI1:` string as a full profile replacement.
3. Repeat the same visual checks from Scenario 1.
4. Import the same string again into a named target profile and confirm the result is identical.

### Scenario 3: Selective Import Guardrails

1. From a customized next-version profile, selectively import only `Theme / Fonts / Colors`.
2. Confirm colors/fonts update without moving anchors.
3. Selectively import only `Layout / Positions`.
4. Confirm anchors move without replacing unrelated theme choices.
5. Selectively import loot/skinning-related categories and confirm old `general.skinLoot*` payloads land in `loot`, `lootRoll`, and `lootResults`.

### Pass Criteria

- No frame snaps back to next-version defaults unless the old profile also used those defaults.
- Old loot, roll-frame, and minimap visibility choices survive both upgrade paths.
- Old mint-accent profiles do not silently become sky blue.
- Re-importing or relogging is idempotent: the second load looks the same as the first.
