---
layout: default
title: FAQ
parent: Getting Started
nav_order: 5
---

# Frequently Asked Questions

## What is QUI?

QUI (QuaziiUI Community Edition) is a comprehensive UI replacement addon for World of Warcraft Midnight (12.0+). It provides custom unit frames, cooldown tracking (CDM), action bar styling, group frames, buff/debuff displays, data panels, HUD layering, frame skinning, and much more -- all in a single addon. QUI is designed to replace the need for multiple separate UI addons.

## How do I move frames?

It depends on the type of frame:

- **Blizzard default frames** (action bars, minimap, chat, etc.) are moved through Blizzard's built-in **Edit Mode**. Press `Escape` > `Edit Mode` to enter it.
- **QUI-specific frames** (unit frames, data panels, CDM bars, etc.) are moved through `/qui` > **Anchoring & Layout**. Some frames also support drag-and-drop positioning when edit mode is active via `/qui editmode`.

## What is CDM?

CDM stands for **Cooldown Manager**. It displays your ability cooldowns as icon bars on screen, giving you clear visibility of when your abilities are ready. CDM tracks cooldowns, charges, and procs for your class and spec.

To configure CDM, open `/qui` and go to the **CDM** tab, or type `/cdm` to go there directly. CDM is disabled by default and must be enabled manually.

## How do I set up keybinds?

Type `/kb` to enter keybind mode (powered by LibKeyBound). In this mode:

1. Hover your mouse over any action bar button.
2. Press the key you want to bind to that button.
3. The keybind is applied immediately.
4. To unbind, hover over the button and press the currently bound key again.
5. Type `/kb` again to exit keybind mode.

## Where do I report bugs?

You can report bugs in two places:

- **GitHub Issues:** [github.com/zol-wow/QUI/issues](https://github.com/zol-wow/QUI/issues)
- **Discord:** [discord.gg/FFUjA4JXnH](https://discord.gg/FFUjA4JXnH)

When reporting a bug, include the QUI version (shown in `/qui`), any error messages (install BugSack/BugGrabber to capture Lua errors), and steps to reproduce the issue.

## Why are my action bars hidden?

QUI enables **mouseover fade** on action bars by default. Your action bars are still there -- they become visible when you move your mouse over them.

To disable this behavior:

1. Open `/qui`.
2. Go to the **Action Bars** tab.
3. Disable the mouseover fade option.
4. Your action bars will remain visible at all times.

## How do I enable group frames?

QUI Group Frames are **opt-in** and disabled by default. The addon does not override your group frames until you explicitly enable them.

To enable QUI Group Frames:

1. Open `/qui`.
2. Go to the **Group Frames** tab.
3. Enable QUI Group Frames.
4. Reload the UI with `/rl`.

## Why can I not click things in combat?

World of Warcraft 12.0 introduced stricter **taint protection** for the UI. This means that certain protected operations (moving frames, toggling frame visibility, modifying secure elements) cannot be performed during combat.

QUI respects these restrictions and automatically defers protected operations until combat ends. If you notice that a setting change or frame adjustment does not take effect immediately during combat, it will apply as soon as you leave combat. This is by design and prevents UI errors that could break your interface mid-encounter.

## How do I change fonts and textures?

QUI provides global font, texture, and outline settings that apply across the entire addon.

1. Open `/qui`.
2. Go to the **General & QoL** tab.
3. Adjust the **font**, **texture**, and **outline** settings to your preference.
4. Changes apply across all QUI elements that use the global settings.

Individual modules may also have their own font or texture overrides available in their respective tabs.
