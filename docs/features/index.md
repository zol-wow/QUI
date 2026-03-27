---
layout: default
title: Features
nav_order: 3
has_children: true
---

# Features

QUI provides a comprehensive set of UI modules that can be individually enabled or disabled to suit your playstyle. Whether you want a complete UI overhaul or just a few targeted improvements, you can pick and choose exactly what QUI manages.

## Feature Map

```mermaid
graph LR
    subgraph Combat["Combat HUD"]
        CDM["Cooldown Manager"]
        UF["Unit Frames"]
        GF["Group Frames"]
        CT["Custom Trackers"]
        HV["HUD Visibility"]
    end

    subgraph Interface["Action Bars & Interface"]
        AB["Action Bars"]
        MM["Minimap"]
        DP["Data Panels"]
        CHAT["Chat"]
        TT["Tooltips"]
        SKIN["Skinning"]
    end

    subgraph Dungeon["Dungeon & Group"]
        MPT["M+ Timer"]
        PK["Party Keystones"]
        BREZ["Battle Res"]
        TELE["Dungeon Teleport"]
    end

    subgraph QoL["Quality of Life"]
        CP["Character Pane"]
        BFM["Blizzard Frame Mover"]
        AUTO["Automation"]
        SKY["Skyriding"]
        XP["XP Tracker"]
    end

    subgraph Layout["Layout & Config"]
        LM["Layout Mode"]
        ANCHOR["Frame Anchoring"]
        KB["Keybinds"]
        PROF["Profiles"]
        PERF["Performance Monitor"]
    end

    style Combat fill:#1a1a2e,stroke:#34D399,color:#fff
    style Interface fill:#1a1a2e,stroke:#34D399,color:#fff
    style Dungeon fill:#1a1a2e,stroke:#34D399,color:#fff
    style QoL fill:#1a1a2e,stroke:#34D399,color:#fff
    style Layout fill:#1a1a2e,stroke:#34D399,color:#fff
```

## Feature Areas

- [Cooldown Manager]({% link features/cooldown-manager.md %}) -- QUI's flagship feature. Displays ability cooldowns as configurable icon containers near your character with glow effects, swipe overlays, range indicators, Composer for per-spell customization, and flexible container types (cooldown, aura, aura bar).

- [Unit Frames]({% link features/unit-frames.md %}) -- Replaces Blizzard's unit frames for Player, Target, Focus, Pet, Boss, and more. Includes castbars, auras, absorb shields, heal prediction, portraits, and extensive color and layout options.

- [Group Frames]({% link features/group-frames.md %}) -- Opt-in replacement for Blizzard party and raid frames. Separate party/raid profiles, auto-scaling layouts, click-casting with scroll wheel and ping support, Composer, dispel overlays, custom aura indicators, spotlight pinning, and healer-focused features.

- [Action Bars]({% link features/action-bars.md %}) -- Native action bar engine enhancing all 8 standard action bars plus pet, stance, and special bars. Mouseover fade, per-bar style overrides, range and usability indicators, and button spacing controls.

- [Chat]({% link features/chat.md %}) -- Enhances the default chat window with a glass effect, clickable URLs, message fade, timestamps, copy button, and edit box styling.

- [Tooltips]({% link features/tooltips.md %}) -- Reskins tooltips with QUI's dark theme, adds cursor anchoring, combat hiding, class-colored names, spell/item IDs, guild rank, M+ rating, and per-context visibility with modifier key controls.

- [Character Pane]({% link features/character-pane.md %}) -- Enhances the character and inspect frames with item level overlays, enchant status, gem indicators, durability bars, avoidance/stagger stats, PvP iLvl, and customizable stats formatting.

- [Skinning]({% link features/skinning.md %}) -- Applies QUI's visual theme to Blizzard frames including the game menu, loot window, objective tracker, keystone frame, ready check, status bars, and more.

- [Minimap & Data Panels]({% link features/minimap-datatext.md %}) -- Full minimap customization with shape, border, button drawer, clock, coordinates, zone text, and element visibility controls. See also [Data Panels]({% link features/data-panels.md %}).

- [Dungeon Features]({% link features/dungeon-features.md %}) -- M+ timer, party keystones, dungeon teleport, battle res counter, combat timer, and automatic combat logging for dungeons and raids.

- [Quality of Life]({% link features/quality-of-life.md %}) -- Automation features including junk selling, auto repair, consumable checks, popup blocking, pet warnings, focus cast alerts, Blizzard Frame Mover, and missing raid buff display.

- [Custom Trackers]({% link features/custom-trackers.md %}) -- User-defined spell and item tracking bars with dynamic layouts, clickable icons, and independent visibility rules.

- [Skyriding]({% link features/skyriding.md %}) -- Custom vigor bar for Skyriding with segmented display, Second Wind progress, speed readout, and Thrill of the Skies color change.

- [XP Tracker]({% link features/xp-tracker.md %}) -- XP progress bar with rested XP overlay, details panel, and hover-to-show option.

- [HUD Visibility]({% link features/hud-visibility.md %}) -- Visibility rule system for CDM, Unit Frames, and Custom Trackers. Show/hide based on combat, target, group, mounting, flying, and more.

- [Frame Layout]({% link features/frame-layout.md %}) -- Layout Mode with edge-docked toolbar for positioning frames, anchoring system for relative positioning, HUD layering priorities, and DandersFrames/BigWigs/AbilityTimeline integration.

- [Keybinds & Integrations]({% link features/keybinds-integrations.md %}) -- LibKeyBound keybind mode, keybind display on CDM and action bars, and third-party addon integrations (DandersFrames, BigWigs, Plater, LibDualSpec).

- [Blizzard Frame Mover]({% link features/blizzard-frame-mover.md %}) -- Drag-and-drop repositioning for default Blizzard UI frames without entering Edit Mode. Positions persist across sessions.

- [Performance Monitor]({% link features/performance-monitor.md %}) -- Real-time diagnostics showing per-addon memory usage, event frequency, and CPU monitoring. Access with `/qui perf`.

- [Data Panels]({% link features/data-panels.md %}) -- Configurable information displays for gold, FPS, latency, durability, guild info, and more. Assignable to minimap slots or standalone panels.

Every module reads its settings from the QUI profile database, so your configuration travels with your profile. Open the options panel with `/qui` to explore what each module offers.
