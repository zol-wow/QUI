---
layout: default
title: Group Frames
parent: Features
nav_order: 3
---

# Group Frames

QUI Group Frames are an opt-in party and raid frame system built for players who need more control and more information than the default group UI provides.

![Actual QUI Group Frames page]({{ '/assets/images/qui-group-frames-full.png' | relative_url }})
_The Group Frames page in `/qui`, with the unit-group selector, preview frame, and detailed page tabs visible._

## Important First Note

Group Frames are **disabled by default**. QUI does not take over your party or raid frames unless you tell it to.

## How to Enable

1. Open `/qui` and select **Group Frames**.
2. Choose the unit group you want to work on, such as **Party** or **Raid**.
3. Toggle **Enable QUI Group Frames**.
4. Reload your UI when prompted.
5. Use **Edit in Layout Mode** only when you want to move the frames on screen.

Most group frame behavior is configured directly from the main `/qui` page. Click-casting is configured separately under **General > Click-Cast**.

## Who Should Turn Them On

- Healers who need strong dispel, HoT, buff, and debuff visibility
- Support players who want better group awareness
- Raid players who dislike the feel of default group frames
- Anyone who wants separate party and raid layouts

## Important Settings

| Setting | Description | Default |
|:--------|:------------|:--------|
| Enable | Master toggle for group frames | Disabled |
| Sort by | Role, index, or name | Role |
| Group by | GROUP, ROLE, or CLASS | GROUP |
| Health display | Percent, absolute, both, or deficit | Percent |
| Max debuff icons | Number of debuff icons shown per frame | 3 |
| Range check alpha | Opacity for out-of-range members | 0.4 |
| Click-casting | Enable click-cast bindings | Disabled |
| Spotlight | Pin members by role/name | Disabled |
| Castbar | Show castbars on group frames | Disabled |
| Pet frames | Show pet frames | Disabled |

## Best First Tweaks

1. Enable the frames and reload.
2. Use test mode to preview party or raid sizes without waiting for a real group.
3. Set the size and spacing before turning on lots of indicators.
4. Add click-casting only after the frames already feel readable.
5. Turn on castbars only if you truly need them.

## What Makes Them Powerful

- Auto-scaling layouts for party, small raid, and large raid contexts
- Separate party and raid profiles
- Click-casting with spec-based bindings
- Healer-focused indicators like dispels, my-buffs, and defensives
- Spotlight rules and sorting controls for keeping important players visible
- Range fading, aura handling, and optional power or cast information

## Good To Know

{: .important }
Group frames require a UI reload when first enabled or disabled. This is because they replace Blizzard's secure group frame headers, which can only be swapped at load time.

{: .note }
Click-casting bindings are stored per-specialization. If you play multiple specs (e.g., Holy and Retribution on a Paladin), each spec can have completely different click-cast setups.

{: .note }
Test mode is invaluable for configuring raid frames. You can preview how your frames look with 5, 10, 20, or 40 players without needing to join an actual group. Access it from the Group Frames settings.

{: .important }
Enabling castbars on group frames in a 40-player raid can impact performance. If you notice frame rate drops in large groups, consider disabling group frame castbars.
