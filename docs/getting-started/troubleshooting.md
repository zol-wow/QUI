---
layout: default
title: Troubleshooting
parent: Getting Started
nav_order: 6
---

# Troubleshooting

Common issues and solutions for QUI.

## Frames Are Invisible or Missing

**Cause:** HUD Visibility rules may be hiding your frames.

1. Open `/qui` and check the **General & QoL** tab for Unit Frame visibility settings.
2. Enter **Layout Mode** (`/qui layout`) and check CDM visibility settings.
3. Temporarily set visibility to "Show Always" to confirm frames exist.
4. If frames appear, adjust the visibility rules to your preferred conditions.

{: .note }
The "Fade Out Alpha" setting at 0 makes hidden frames completely invisible. Set it to 0.3 temporarily to see faint outlines of where your frames are.

## CDM Icons Not Showing

**Cause:** The CDM may not have spell data for your spec, or containers may be disabled.

1. Enter Layout Mode (`/qui layout`) and check CDM settings.
2. Verify the CDM engine is set to **owned** (not "classic").
3. Open the **Composer** to verify spells are populated for your spec.
4. Check that containers (Essential, Utility) are enabled.
5. Check visibility rules -- CDM may be hidden outside of combat.

## Action Bars Seem to Have Disappeared

**Cause:** Mouseover fade is enabled by default in many profiles.

1. Move your mouse to where the action bars should be -- they will appear on hover.
2. To disable fade: open `/qui` > **Action Bars** tab > disable **Mouseover Fade**.
3. You can also set "Always Show In Combat" to keep bars visible during encounters.

## Click-Casting Not Working

**Cause:** Click-casting requires group frames to be enabled and the Click-Cast tab configured.

1. Verify QUI Group Frames are enabled (Layout Mode > Group Frames > Enable).
2. Open `/qui` > **Click-Cast** tab and configure your bindings.
3. Click-casting bindings are per-specialization -- switch to the correct spec.
4. A UI reload (`/rl`) may be required after enabling group frames for the first time.

{: .important }
Click-casting only works on secure frames (group frames, unit frames). It cannot work during combat on frames that were created after combat started.

## Frames Cannot Be Moved During Combat

**Cause:** WoW's taint protection prevents frame manipulation during combat.

This is a game limitation, not a QUI bug. Frame positioning, visibility changes, and other protected operations are automatically deferred until combat ends. Type `/qui layout` after leaving combat to reposition frames.

## Tooltip Issues or Errors

**Cause:** Tooltip taint from other addons or WoW API changes.

1. QUI uses Blizzard hooks (not a custom tooltip engine) to minimize taint risk.
2. If tooltips disappear or show errors, try disabling other addons that modify tooltips.
3. The **Combat Hiding** feature (enabled by default) hides tooltips during combat -- hold SHIFT to force-show them.
4. If OPie is installed and causing tooltip issues, ensure both QUI and OPie are updated to the latest versions.

## Group Frames Not Appearing

**Cause:** Group frames are opt-in and disabled by default.

1. Enter Layout Mode (`/qui layout`).
2. Access Group Frames settings through the toolbar or drawer.
3. Enable QUI Group Frames.
4. **Reload the UI** with `/rl` -- this is required when first enabling group frames.

{: .important }
Group frames replace Blizzard's secure group frame headers, which can only be swapped at load time. A reload is always required when toggling group frames on or off.

## Performance Issues in Large Groups

If frame rates drop in 20-40 player raids:

1. Disable group frame **castbars** (they update frequently and are disabled by default for a reason).
2. Disable group frame **portraits** if enabled.
3. Reduce the maximum number of **debuff icons** per group frame.
4. Consider disabling the **range check** feature if not needed.
5. Use `/qui perf` to identify which systems are consuming the most resources.

## Profile Import Not Working

1. Ensure the import string starts with `QUI1:` -- this is the format marker.
2. Check that the string was copied completely (no truncation from chat or clipboard limits).
3. Try importing into a fresh profile rather than overwriting an existing one.
4. Profile strings include validation (max depth 20, max 50,000 nodes) -- strings exceeding these limits are rejected for safety.

## Safe Reload

If you need to reload during combat, use `/rl` or `/reload`. QUI will queue the reload and execute it automatically when combat ends. This prevents UI errors and taint issues that can occur from mid-combat reloads.
