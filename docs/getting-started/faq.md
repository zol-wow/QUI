---
layout: default
title: FAQ
parent: Getting Started
nav_order: 5
---

# Frequently Asked Questions

## What is QUI?

QUI is a full UI addon for World of Warcraft Midnight that combines a combat HUD, frame positioning tools, action bar styling, minimap and panel customization, group tools, quality-of-life helpers, and profile management in one package.

## How do I move frames?

Use **Layout Mode** for QUI-controlled HUD elements like CDM, unit frames, group frames, minimap-related panels, and similar custom pieces. Use Blizzard's own **Edit Mode** for Blizzard-controlled elements. If something still needs fine tuning, check the positioning settings inside `/qui`.

## What is CDM?

CDM stands for **Cooldown Manager**. It is QUI's signature cooldown display system, built to keep your important abilities, buffs, and procs close to your character so your eyes stay near the action.

## What is Layout Mode?

Layout Mode (`/qui layout`) is QUI's visual editor. It lets you drag major HUD elements, open layout-specific settings, and keep related pieces aligned without guessing at offsets.

## How do I set up keybinds?

Type `/kb` to enter keybind mode (powered by LibKeyBound). In this mode:

1. Hover your mouse over any action bar button.
2. Press the key you want to bind to that button.
3. The keybind is applied immediately.
4. To unbind, hover over the button and press the currently bound key again.
5. Type `/kb` again to exit keybind mode.

## Why are my action bars hidden?

Most likely, mouseover fade is active. Move your mouse over the area where the bars should be. If you want them always visible, open `/qui`, go to **Action Bars**, and turn the fade behavior off.

## How do I enable group frames?

QUI Group Frames are opt-in. Open `/qui`, select **Group Frames**, enable them, and reload if prompted. Use **Edit in Layout Mode** afterward if you want to reposition them.

They have separate party and raid setups, so you can keep them lightweight in small groups and more information-dense in raids.

## Why can I not click things in combat?

Combat locks down some protected UI actions. If a move, toggle, or secure interaction does not apply immediately during combat, QUI will wait and apply it after combat ends.

## How do I change fonts and textures?

Open `/qui`, go to **Appearance**, and start with **Fonts** or **UI Scale**. Those pages change a large part of the addon's overall look very quickly.

## Can I import just part of a profile?

Yes. During import, you can choose only the parts you want, such as visual styling or layout positions, without replacing the rest of your setup.

## Where do I get help?

- [GitHub Issues](https://github.com/zol-wow/QUI/issues) for bug reports and tracked issues
- [Discord](https://discord.gg/FFUjA4JXnH) for setup help and discussion
