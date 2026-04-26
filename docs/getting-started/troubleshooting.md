---
layout: default
title: Troubleshooting
parent: Getting Started
nav_order: 6
---

# Troubleshooting

If something feels off, start here before rebuilding your whole UI.

## Quick Problem Finder

| Problem | Most likely fix |
|---------|-----------------|
| A frame is missing | Check visibility rules and Layout Mode placement |
| Action bars are gone | Mouseover fade is hiding them |
| Group frames will not appear | Enable them, then reload |
| A move or toggle will not apply | Leave combat and try again |
| Profile import failed | Recopy the full string and try a fresh profile |

## Frames Are Invisible or Missing

The most common cause is a visibility rule hiding the frame when you do not meet its conditions.

1. Open `/qui` and check **Appearance > HUD Visibility** for the visibility rules affecting CDM, Unit Frames, and trackers.
2. Open the feature page itself and confirm the module is enabled.
3. Temporarily set visibility to "Show Always" to confirm frames exist.
4. If frames appear, adjust the visibility rules to your preferred conditions.

{: .note }
The "Fade Out Alpha" setting at 0 makes hidden frames completely invisible. Set it to 0.3 temporarily to see faint outlines of where your frames are.

## CDM Icons Not Showing

Usually this means the container is hidden, misplaced, or not populated the way you expect for your spec.

1. Open `/qui` > **Cooldown Manager** or type `/cdm`.
2. Open the **Entries** page to verify spells are populated for your spec.
3. Check that containers (Essential, Utility) are enabled.
4. Check visibility rules -- CDM may be hidden outside of combat.

## Action Bars Seem to Have Disappeared

This is usually normal behavior, not a broken install.

1. Move your mouse to where the action bars should be -- they will appear on hover.
2. To disable fade: open `/qui` > **Action Bars** tab > disable **Mouseover Fade**.
3. You can also set "Always Show In Combat" to keep bars visible during encounters.

## Click-Casting Not Working

Click-casting depends on both the right frames and the right bindings.

1. Verify QUI Group Frames are enabled (`/qui` > **Group Frames** > enable toggle).
2. Open `/qui` > **General** > **Click-Cast** and configure your bindings.
3. Click-casting bindings are per-specialization -- switch to the correct spec.
4. A UI reload (`/rl`) may be required after enabling group frames for the first time.

{: .important }
Click-casting only works on secure frames (group frames, unit frames). It cannot work during combat on frames that were created after combat started.

## Frames Cannot Be Moved During Combat

This is expected. WoW blocks many protected frame changes during combat. Leave combat, then try again.

## Tooltip Issues or Errors

If tooltips are acting strangely:

1. Check whether **Combat Hiding** is active.
2. Hold **SHIFT** to force-show a tooltip in combat.
3. If the issue only happens with another tooltip-heavy addon enabled, test with that addon off once.

## Group Frames Not Appearing

Group Frames are disabled until you explicitly turn them on.

1. Open `/qui`.
2. Select **Group Frames**.
3. Enable QUI Group Frames.
4. **Reload the UI** with `/rl` -- this is required when first enabling group frames.

{: .important }
Group frames replace Blizzard's secure group frame headers, which can only be swapped at load time. A reload is always required when toggling group frames on or off.

## Performance Issues in Large Groups

If performance drops in large raids:

1. Disable group frame **castbars** (they update frequently and are disabled by default for a reason).
2. Disable group frame **portraits** if enabled.
3. Reduce the maximum number of **debuff icons** per group frame.
4. Consider disabling the **range check** feature if not needed.
5. Use `/qui perf` to identify which systems are consuming the most resources.

## Profile Import Not Working

1. Ensure the import string starts with `QUI1:` -- this is the format marker.
2. Check that the string was copied completely (no truncation from chat or clipboard limits).
3. Try importing into a fresh profile rather than overwriting an existing one.
4. If a selective import behaves strangely, retry as a full import in a throwaway profile to verify the string itself is valid.

## Safe Reload

If you need to reload during combat, use `/rl` or `/reload`. QUI will queue the reload and execute it automatically when combat ends. This prevents UI errors and taint issues that can occur from mid-combat reloads.
