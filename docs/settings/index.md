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

The QUI options panel contains the following tabs:

| # | Tab | Description |
|---|-----|-------------|
| 1 | **Welcome** | First-time setup wizard and version info |
| 2 | **General & QoL** | Global appearance, automation, skinning, and quality-of-life features |
| 3 | **Anchoring & Layout** | Frame positioning, anchoring, and HUD layering |
| 4 | **Cooldown Manager** | Essential, Utility, Buff, and Tracked bars plus glow/swipe effects |
| 5 | **Unit Frames** | Player, Target, ToT, Pet, Focus, and Boss unit frames |
| 6 | **Group Frames** | Party and raid frames with healer features and click-casting |
| 7 | **Action Bars** | Button skinning, mouseover fade, per-bar overrides |
| 8 | **Minimap & Datatext** | Minimap customization and data panel configuration |
| 9 | **Skinning & Autohide** | Blizzard frame skinning and conditional frame hiding |
| 10 | **Custom Trackers** | User-defined spell and item tracking bars |
| 11 | **Frame Levels** | HUD layering priority for all QUI frames |
| 12 | **Profiles** | AceDB profile management (create, copy, delete, switch) |
| 13 | **Import & Export Strings** | Profile import/export and bundled preset strings |

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
