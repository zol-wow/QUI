---
layout: default
title: Import & Export
parent: Settings Reference
nav_order: 12
---

# Import & Export Strings

The Import & Export Strings tab handles profile import/export and bundled presets. Profiles are serialized with AceSerializer, compressed with LibDeflate, and validated on import with strict limits to prevent malformed data from corrupting your settings.

## Profile Import/Export

QUI profiles can be shared between players as compressed strings. The system enforces the following validation limits on import:

- **Max depth:** 20 levels of nested tables
- **Max nodes:** 50,000 total entries
- **Type checking:** Values are validated against expected types before applying

**Exporting** generates a shareable string of your entire current profile. Copy the string and send it to other players via any text channel (Discord, in-game mail, etc.).

**Importing** applies all settings from a pasted QUI profile string, overwriting your current profile.

## Bundled Presets

QUI ships with several ready-made import strings that configure QUI and compatible addons:

| Preset | Description |
|--------|-------------|
| QUI Edit Mode Base | Blizzard Edit Mode layout for optimal QUI frame positioning |
| Quazii Profile | Quazii's recommended QUI settings (the classic look) |
| Quazii Dark Mode | Dark variant of Quazii's profile |
| Quazii Details! | Details! damage meter profile matching QUI aesthetics |
| Quazii Plater | Plater nameplate profile for QUI |
| Quazii Platynator | Platynator nameplate profile for QUI |

The **QUI Edit Mode Base** preset configures Blizzard's built-in Edit Mode so that default frames are positioned correctly for QUI's layout. The **Quazii Profile** and **Quazii Dark Mode** presets configure QUI itself. The **Details!**, **Plater**, and **Platynator** presets are for third-party addons and require those addons to be installed.

## How to Import

1. Open `/qui` and navigate to the **Import & Export Strings** tab
2. Click the desired bundled preset button, or paste a profile string into the import text box
3. Follow the confirmation dialog to apply the profile
4. Type `/rl` to reload your UI and fully apply the changes
