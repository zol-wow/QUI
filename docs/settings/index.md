---
layout: default
title: Settings Reference
nav_order: 4
has_children: true
---

# Settings Reference

This section documents every configurable setting in QUI, organized to mirror the in-game `/qui` options panel. Each page corresponds to a tab in the settings UI.

Settings are stored in `QUI.db.profile` (profile-level, shared across characters using the same profile) or `QUI.db.char` (character-level, unique per character). Most changes take effect immediately; some require `/rl` (reload UI).

## In-Game Tabs

The QUI options panel (`/qui`) contains the following tabs:

| # | Tab | Description |
|---|-----|-------------|
| 1 | **Welcome** | First-time setup wizard and version info |
| 2 | **General & QoL** | Global appearance, automation, skinning, and quality-of-life features |
| 3 | **Frame Positioning** | Frame anchoring relationships and positioning |
| 4 | **Unit Frames** | Player, Target, ToT, Pet, Focus, and Boss unit frames |
| 5 | **Click-Cast** | Click-casting bindings for group frames and unit frames |
| 6 | **Action Bars** | Button skinning, mouseover fade, per-bar overrides |
| 7 | **Skinning & Autohide** | Blizzard frame skinning and conditional frame hiding |
| 8 | **Custom CDM Bars** | User-defined spell and item tracking bars |
| 9 | **Frame Levels** | HUD layering priority for all QUI frames |
| 10 | **Profiles** | AceDB profile management (create, copy, delete, switch) |
| 11 | **Import & Export Strings** | Profile import/export and bundled preset strings |
| 12 | **Search** | Search across all settings |
| 13 | **Help** | Help and documentation pages |

### Layout Mode Settings

The following settings have been moved out of the main options panel and into **Layout Mode** (`/qui layout`):

| Module | Access |
|--------|--------|
| **Cooldown Manager** | Layout Mode toolbar and settings panels |
| **Group Frames** | Layout Mode toolbar and drawer (Composer + settings panels) |
| **Minimap & Datatext** | Layout Mode toolbar and settings panels |

### Action Buttons

The options panel sidebar also includes quick-access action buttons:

- **CDM Settings** -- Opens the CDM settings panel directly
- **Blizz Edit Mode** -- Opens Blizzard's Edit Mode
- **QUI Edit Mode** -- Toggles QUI Layout Mode

## How Settings Are Organized

Each settings page in this section uses tables with the following columns:

| Column | Description |
|--------|-------------|
| **Setting** | The database key path relative to `QUI.db.profile` (or noted if `db.char`) |
| **Type** | Data type: `boolean`, `number`, `string`, `color` (RGBA table), `table` |
| **Default** | The default value as defined in the addon source |
| **Description** | What the setting controls |

## Accessing Settings in Code

```lua
-- Profile-level (shared across characters on the same profile)
local value = QUI.db.profile.general.uiScale

-- Character-level (unique per character)
local debug = QUI.db.char.debug.reload

-- Using the module pattern with CreateDBGetter
local GetDB = ns.Helpers.CreateDBGetter("general")
local db = GetDB()  -- returns QUI.db.profile.general
```
