---
layout: default
title: Module Addons
parent: Getting Started
nav_order: 3
---

# Module Addons

QUI 4 is a suite. The main `QUI` folder provides shared settings, layout, profiles, storage, and core services. Feature folders such as `QUI_Chat`, `QUI_Bags`, `QUI_InfoBar`, and `QUI_Alts` provide the larger systems around that core.

## Where To Manage Modules

Open `/qui` and use **Module Addons** to turn whole feature addons on or off. This page mirrors the in-game AddOns list, but keeps QUI modules grouped together and explains reload requirements.

Most toggles are account-wide because they enable or disable an addon folder, not only one profile. Some modules also have their own profile-level **Enabled** setting inside their feature page.

## Modules To Know

| Module | Default | What it does |
|--------|---------|--------------|
| Action Bars | On | QUI action bar styling, behavior, keybind text, buff borders, pet and stance handling |
| Cooldown Manager | On | CDM containers, spell composer, cooldown and aura display |
| Unit Frames | On | Player, target, focus, pet, boss, and related frame support |
| Resource Bars | On | Class and combat resource displays |
| Group Frames | Off | Party and raid frames with click-casting, private auras, and raid buff tools |
| Chat | Off | Optional QUI-owned chat display with custom tabs, copy tools, and Combat Log tab |
| Datatexts | On | Shared datatext registry, minimap panel widgets, and custom data panels |
| Minimap | On | QUI minimap skin, drawer, labels, and minimap panel |
| Skinning | On | QUI visual treatment for supported Blizzard windows and alerts |
| Quality of Life | On | Automation, dungeon tools, tooltip helpers, combat helpers, and miscellaneous utility |
| Damage Meter | On | Native QUI damage meter windows |
| Info Bar | Off | Optional top or bottom datatext bar with micro menu, travel, and spec widgets |
| Bags | Off | Optional bag, bank, Warband bank, guild bank, search, sorting, and item tools |
| Alts | Off | Optional account-wide character tracker and item search window |

{: .note }
Bags, Info Bar, Alts, and QUI Chat are newer beta modules. They are intentionally opt-in so you can keep your existing setup stable while testing them.

## Reload Rules

Some modules can start or stop immediately. Others need a reload because they own secure frames, replace large Blizzard windows, or load from separate addon folders.

When QUI asks for a reload, use `/rl`. If you are in combat, QUI queues the reload and runs it when combat ends.

## Manual Install Check

If a module is missing from **Module Addons**, the most common cause is a partial manual install.

1. Exit the game.
2. Open `World of Warcraft\_retail_\Interface\AddOns\`.
3. Confirm the release zip's `QUI*` folders are present side by side.
4. Confirm each folder contains its own `.toc` file directly inside it.
5. Start the game and check the AddOns list again.

## What Stays Running

The shared character storage cache lives in core. It can keep collecting data for features such as Alts and Bags even when their UI modules are off. That means enabling those modules later can show data the core already learned, though offline inventory snapshots may still need each character to log in once.
