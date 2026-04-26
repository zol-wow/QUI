---
layout: default
title: Import & Export
parent: Settings Reference
nav_order: 12
---

# Import & Export Strings

The **General > Import / Export** page handles profile import/export and bundled presets. Profiles are serialized with AceSerializer, compressed with LibDeflate, and validated on import with strict limits to prevent malformed data from corrupting your settings.

## Profile Import/Export

QUI profiles can be shared between players as compressed strings. The system enforces the following validation limits on import:

- **Max depth:** 20 levels of nested tables
- **Max nodes:** 50,000 total entries
- **Type checking:** Values are validated against expected types before applying

**Exporting** generates a shareable string of your entire current profile. Copy the string and send it to other players via any text channel (Discord, in-game mail, etc.).

**Importing** applies all settings from a pasted QUI profile string, overwriting your current profile.

## Bundled Presets

QUI currently ships one built-in import string:

| Preset | Description |
|--------|-------------|
| QUI Edit Mode Base | Blizzard Edit Mode layout for optimal QUI frame positioning |

The **QUI Edit Mode Base** preset configures Blizzard's built-in Edit Mode so that default frames are positioned correctly for QUI's layout.

## How to Import

1. Open `/qui` and navigate to **General > Import / Export**
2. Click the desired bundled preset button, or paste a profile string into the import text box
3. Follow the confirmation dialog to apply the profile
4. Type `/rl` to reload your UI and fully apply the changes
