---
layout: default
title: Slash Commands
parent: Getting Started
nav_order: 4
---

# Slash Commands

QUI registers several slash commands for quick access to its features. Type these into the WoW chat window.

## Command Reference

| Command | Description |
|---------|-------------|
| `/qui` or `/quaziiui` | Open the QUI options panel. |
| `/qui debug` | Enable debug mode. Debug output persists for one reload, then turns off automatically. |
| `/qui editmode` | Toggle the unit frame edit mode for repositioning QUI unit frames. |
| `/qui grouptest` | Toggle group frames test/preview mode to see how group frames look with simulated party/raid members. |
| `/rl` or `/reload` | Safe reload. If you are in combat, the reload is queued and executes automatically when combat ends. |
| `/kb` | Toggle keybind mode (LibKeyBound). Hover over action buttons and press a key to bind it. Press the key again to unbind. |
| `/cdm` | Open the CDM (Cooldown Manager) settings panel directly. |
| `/pull [seconds]` | Start a pull countdown timer. Accepts a value between 1 and 60 seconds. Defaults to 10 seconds if no value is given. |
| `/qpull` or `/quipull` | Same as `/pull`. These aliases are always available regardless of other addons. |

## Notes

- The `/pull` command is only registered if no other addon (such as **BigWigs** or **DBM**) has already claimed it. If you have BigWigs or DBM installed, use `/qpull` or `/quipull` instead to access QUI's pull timer.
- The `/rl` safe reload feature prevents the common issue of reloading during combat, which can cause UI errors and taint issues. If you type `/rl` while in combat, QUI will display a message and reload as soon as combat ends.
