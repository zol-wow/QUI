---
layout: default
title: Blizzard Frame Mover
parent: Features
nav_order: 18
---

# Blizzard Frame Mover

QUI's Blizzard Frame Mover lets you reposition default Blizzard UI elements by dragging them directly, without needing to enter Blizzard's Edit Mode. This is useful for quick adjustments to frames that Blizzard's Edit Mode does not expose or that you want to move independently of the Edit Mode system.

## Overview

Many default Blizzard frames -- the objective tracker, durability indicator, vehicle seat indicator, and others -- are placed in fixed positions that may not suit your layout. While Blizzard's Edit Mode covers some frames, it does not provide control over all of them. The Blizzard Frame Mover fills that gap by making these frames directly draggable. Once repositioned, frame positions are saved and persist across reloads and sessions. If you ever want to start fresh, a reset option restores all frames to their original Blizzard default positions.

## How to Enable

To enable and configure the Blizzard Frame Mover:

- Open `/qui` and navigate to the **QoL** tab, then select **Blizzard Frame Mover**.

## Key Features

- **Drag-and-drop repositioning** -- Click and drag supported Blizzard frames to move them anywhere on screen. No Edit Mode required.
- **Position persistence** -- Frame positions are saved to your profile and restored automatically on login, reload, and between sessions.
- **Reset to default** -- A single button restores all moved frames to their original Blizzard default positions.
- **Broad frame coverage** -- Supports many standard Blizzard frames that Edit Mode does not handle, giving you control over UI elements that are otherwise fixed in place.

## Important Settings

| Setting | Description | Default |
|:--------|:------------|:--------|
| Enable | Toggle the Blizzard Frame Mover on or off | Disabled |
| Reset All | Reset all moved frames to their original Blizzard positions | -- |

## Tips

{: .note }
The Blizzard Frame Mover is especially useful for frames that Blizzard's Edit Mode does not cover. If you find a default UI element is overlapping your custom layout, check whether the Frame Mover supports it before resorting to other workarounds.

{: .important }
Positions are stored per profile. If you switch QUI profiles, your frame positions will change to match the new profile's saved layout. Use the Reset All button if you want to clear all custom positions and return to Blizzard defaults.

{: .note }
The Frame Mover complements QUI's Layout Mode rather than replacing it. Layout Mode handles QUI's own frames (unit frames, action bars, cooldown containers, etc.), while the Blizzard Frame Mover handles native Blizzard frames that are outside QUI's direct control.
