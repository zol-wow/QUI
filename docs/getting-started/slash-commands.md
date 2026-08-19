---
layout: default
title: Slash Commands
parent: Getting Started
nav_order: 5
---

# Slash Commands

These are the commands most players actually use. Type them into the WoW chat window.

## Everyday Commands

| Command | Description |
|---------|-------------|
| `/qui` or `/quaziiui` | Open the QUI options panel. |
| `/qui layout` | Toggle Layout Mode for repositioning QUI frames (CDM, unit frames, group frames, etc.) with an edge-docked toolbar and settings panels. |
| `/qui editmode` or `/qui unlock` | Aliases for `/qui layout`. |
| `/rl` or `/reload` | Safe reload. If you are in combat, the reload is queued and executes automatically when combat ends. |
| `/kb` | Toggle keybind mode (LibKeyBound). Hover over action buttons and press a key to bind it. Press the key again to unbind. |
| `/cdm` | Open the CDM (Cooldown Manager) settings panel directly. |
| `/qui cdm` | Open QUI's CDM composer/settings route from the QUI options panel. |
| `/alts` or `/quialts` | Toggle the Alts window when the Alts module is enabled. |

## Utility Commands

| Command | Description |
|---------|-------------|
| `/pull [seconds]` | Start a pull countdown timer. Accepts a value between 1 and 60 seconds. Defaults to 10 seconds if no value is given. |
| `/qpull` or `/quipull` | Always-available pull timer aliases. |
| `/qui perf` | Toggle the performance monitor overlay. |
| `/qui debug` | Enable debug mode. Debug output persists for one reload, then turns off automatically. |

## Azta'rec Helper

| Command | Description |
|---------|-------------|
| `/azt` | Toggle the movable Azta'rec safe-quadrant recorder. |
| `/azt STAR`, `/azt CIRCLE`, `/azt DIAMOND`, `/azt TRIANGLE` | Show the room map and add that world marker to the sequence. Numeric aliases `1`–`4` also work. |
| `/azt reset` | Clear the recorded sequence. |
| `/azt lock` or `/azt unlock` | Lock or unlock the recorder position. |

Before the pull, place Star at the top, Circle at the right, Diamond at the bottom, and Triangle at the left of the arena circle to match the four marker icons on the map. The map sections can also be pressed by macros such as `/click QUI_AztaRec_STAR` after the recorder is shown.

The recorder automatically appears when you enter Azta'rec's Nemesis lair and hides after you leave it.

## Bags Commands

These commands work when the Bags module is enabled.

| Command | Description |
|---------|-------------|
| `/quibags` | Toggle the QUI bag window. |
| `/quibags search` | Open Search Everywhere across cached character storage. |
| `/quibags bank` | Browse the live bank when open, or cached bank data when away from the bank. |
| `/quibags guild` | Browse the live guild bank when open, or cached guild-bank data when away from the vault. |
| `/quibags clearnew` | Clear all new-item glow markers. |

## Data Panel Commands

| Command | Description |
|---------|-------------|
| `/quidp show` | List custom datatext panels and their status. |
| `/quidp refresh` | Refresh all datatext panels. |

## Damage Meter Commands

| Command | Description |
|---------|-------------|
| `/quidmreset` | Reset the current damage meter session. |

## CDM Debug Commands

These are available after `/qui debug` reloads the load-on-demand debug tools.

| Command | Description |
|---------|-------------|
| `/cdmdebug` | Show CDM debug command groups and active flags. |
| `/cdmdebug flags [name] [on|off|filter]` | Toggle CDM debug flags for icon, bar, blizz, aura, charge, totem, or taint output. |
| `/cdmdebug spell <spellID|name> [once|watch|events [sec]|trace|charge|flicker]` | Inspect one CDM spell/icon path. `events` defaults to a 0.25s throttle; use `events 0` for raw output. |
| `/cdmdebug cache [status|reset]` | Print or reset CDM cache state. |
| `/cdmdebug profile [status|clean]` | Dump or clean CDM profile/spec tracking state. |

## Good To Know

- `/qui` and `/qui layout` are the two commands you will use the most.
- `/rl` is safe to use with QUI even in combat because it waits until combat ends.
- If another pull-timer addon already owns `/pull`, use `/qpull` or `/quipull` instead.
- Module-specific commands do nothing or print a disabled-module note when their module is off.
