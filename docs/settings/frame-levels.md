---
layout: default
title: Frame Levels
parent: Settings Reference
nav_order: 10
---

# Frame Levels

QUI uses a priority-based HUD layering system to control the rendering order of on-screen elements. Each frame element can be assigned a priority value, and higher-priority elements render on top of lower-priority ones.

---

## How It Works

Each HUD element is assigned a **priority** from 0 to 10. The priority is converted to a WoW frame level using the following formula:

```
Frame Level = 100 + (priority * 20)
```

This produces a frame level range of **100** (priority 0) to **300** (priority 10).

The default priority for most elements is **5**, which maps to frame level **200**. Elements with the same priority share the same frame level, with WoW's internal sub-ordering determining which appears on top.

---

## Configurable Elements

The Frame Levels tab in `/qui` lets you set priorities for the following HUD elements:

### Cooldown Manager

| Element | Default Priority | Default Frame Level |
|---|---|---|
| Essential CDM | 5 | 200 |
| Utility CDM | 5 | 200 |

### Buffs & Trackers

| Element | Default Priority | Default Frame Level |
|---|---|---|
| Buff Icons | 5 | 200 |
| Tracked Bar | 5 | 200 |
| Custom Trackers | 5 | 200 |

### Power Bars

| Element | Default Priority | Default Frame Level |
|---|---|---|
| Power Bar (Primary) | 5 | 200 |
| Power Bar (Secondary) | 5 | 200 |

### Castbars

| Element | Default Priority | Default Frame Level |
|---|---|---|
| Player Castbar | 5 | 200 |
| Target Castbar | 5 | 200 |
| Focus Castbar | 5 | 200 |

### Unit Frames

| Element | Default Priority | Default Frame Level |
|---|---|---|
| Player UF | 5 | 200 |
| Target UF | 5 | 200 |
| ToT UF | 5 | 200 |
| Pet UF | 5 | 200 |
| Focus UF | 5 | 200 |
| Boss UFs | 5 | 200 |

### Miscellaneous

| Element | Default Priority | Default Frame Level |
|---|---|---|
| Skyriding Bar | 5 | 200 |
| Combat Timer | 5 | 200 |
| BRez Counter | 5 | 200 |
| M+ Timer | 5 | 200 |

---

## Usage Tips

- Raise the priority of elements you want to always remain visible on top (e.g., set Essential CDM to 8 so cooldowns always render above unit frames).
- Lower the priority of background or less critical elements (e.g., set Skyriding Bar to 2 so it sits behind everything else).
- When two elements overlap spatially, the one with the higher priority will be interactable and visible on top.
- Changes take effect immediately and do not require a reload.
