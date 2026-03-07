---
layout: default
title: HUD Visibility
parent: Features
nav_order: 15
---

# HUD Visibility

QUI's HUD Visibility system gives you fine-grained control over when your HUD elements appear and disappear. Instead of your frames being permanently visible or manually toggled, you define rules that automatically show and hide them based on your current activity -- in combat, with a target, in a group, or on mouseover.

## Overview

The visibility system applies to three independent frame groups, each with its own set of rules:

- **CDM Visibility** -- Controls the Essential bar, Utility bar, Buff icons, and power bar from the Cooldown Manager.
- **Unit Frames Visibility** -- Controls the Player, Target, Focus, Pet, Target of Target, and Boss unit frames.
- **Custom Trackers Visibility** -- Controls all custom spell and item tracker bars.

Each group uses the same set of visibility rules, but is configured independently. This means you can have your CDM bars appear in combat while your unit frames are always visible, or any other combination that suits your playstyle.

## How to Enable

Visibility rules are configured in the QUI options panel:

- Open `/qui` and navigate to the **UI > HUD Visibility** tab.
- Select the frame group you want to configure (CDM, Unit Frames, or Custom Trackers).

## Key Features

- **Three independent rule groups** -- CDM, Unit Frames, and Custom Trackers each have their own visibility configuration, so you can tailor behavior per frame group.
- **Combinable show rules** -- Enable multiple show conditions simultaneously. The frame appears if any enabled show rule is satisfied (logical OR).
- **Hide overrides** -- Mounted, flying, and skyriding states can forcibly hide frames even when a show rule is active.
- **Dungeon/raid exception** -- A "Don't Hide In Dungeons/Raids" toggle overrides the mounted and flying hide rules when you are inside instanced content.
- **Fade animation** -- Frames fade in and out smoothly with configurable fade duration instead of snapping on and off.
- **Fade-out alpha** -- Set the minimum alpha when frames are hidden. A value of 0 makes them fully invisible; a higher value keeps them faintly visible as a reminder.
- **Mouseover reveal** -- When enabled, moving your cursor over the frame area brings frames to full visibility regardless of other hide rules.
- **Castbar exception** -- For Unit Frames, an option to always show castbars even when the unit frame itself is hidden, so you never miss a cast.
- **Vehicle hide (CDM only)** -- An additional hide rule specifically for the CDM that hides bars when you are in a vehicle.

## Visibility Rules Reference

Every frame group supports the following rules:

| Rule | Behavior | Default |
|:-----|:---------|:--------|
| Show Always | Frame is always visible; overrides all other rules | Disabled |
| Show When Target Exists | Frame appears when you have a target selected | Disabled |
| Show In Combat | Frame appears when you enter combat | Disabled |
| Show In Group | Frame appears when you are in a party or raid | Disabled |
| Show In Instance | Frame appears when you are inside a dungeon or raid instance | Disabled |
| Show On Mouseover | Frame appears when you hover over its area | Disabled |
| Fade Duration | Duration of the fade in/out animation in seconds | 0.2 |
| Fade Out Alpha | Minimum opacity when hidden (0 = fully invisible) | 0 |
| Hide When Mounted | Hide the frame when mounted on the ground | Disabled |
| Hide When In Vehicle | Hide the frame when in a vehicle (CDM only) | Disabled |
| Hide When Flying | Hide the frame when flying (non-skyriding) | Disabled |
| Hide When Skyriding | Hide the frame when skyriding | Disabled |
| Don't Hide In Dungeons/Raids | Override mounted/flying hide rules inside instances | Disabled |

## How Rules Interact

Show rules are evaluated first. If any enabled show rule is satisfied, the frame is eligible to appear. Hide rules are then checked; if any hide rule is satisfied, it overrides the show result and the frame stays hidden. The "Don't Hide In Dungeons/Raids" toggle overrides the mounted, flying, and skyriding hide rules specifically when you are inside instanced content.

If "Show Always" is enabled, no other show rules matter -- the frame is always eligible. Hide rules still apply on top of "Show Always" unless overridden by the dungeon/raid exception.

## Tips

{: .note }
A common setup is to enable "Show In Combat" and "Show When Target Exists" together. This keeps your HUD clean while questing but brings up your frames the moment you engage anything, whether you pull first or get pulled.

{: .important }
The "Fade Out Alpha" setting at 0 makes hidden frames completely invisible. If you are having trouble finding your frames, temporarily set this to 0.3 or higher so you can see where they are, then lower it once positioning is finalized.

{: .note }
The Unit Frames "always show castbars" option is particularly valuable for healers and PvP players who need to see incoming casts even when they have configured their unit frames to hide outside of certain conditions.

{: .note }
"Don't Hide In Dungeons/Raids" is a safety net for niche situations. For example, if you mount up inside a raid (between boss pulls), you probably still want your CDM visible. This toggle prevents mounted-hide from kicking in while you are inside the instance.
