---
layout: default
title: Performance Monitor
parent: Features
nav_order: 19
---

# Performance Monitor

QUI includes a built-in performance monitor that provides real-time diagnostics for addon resource usage. It surfaces memory consumption, event frequency, and CPU usage data to help you identify performance bottlenecks without needing external profiling tools.

## Overview

The performance monitor is a debugging and diagnostic tool aimed at players and addon developers who want to understand what is consuming resources in their UI. It tracks per-addon memory usage, provides an event frequency sniffer that ranks events by how often they fire, and offers real-time graph visualization for monitoring trends over time. This makes it straightforward to identify chatty events, memory-heavy addons, or unexpected resource spikes during gameplay.

## How to Enable

The performance monitor is accessed via slash command:

- Type `/qui perf` to open the performance monitor window.

## Key Features

- **Per-addon memory tracking** -- Displays memory consumption broken down by individual addon, making it easy to see which addons are using the most memory.
- **Event frequency sniffer** -- Monitors and ranks WoW events by occurrence count, showing you which events fire most frequently. This is invaluable for finding events that may be causing unnecessary processing overhead.
- **Real-time graph visualization** -- Plots resource usage over time so you can observe trends, identify spikes, and correlate performance changes with in-game activity.
- **CPU usage monitoring** -- Tracks CPU time spent by addons to help pinpoint processing-intensive code paths.

## Important Settings

| Setting | Description | Default |
|:--------|:------------|:--------|
| `/qui perf` | Open or close the performance monitor window | -- |

## Tips

{: .note }
The event frequency sniffer is one of the most useful features for diagnosing lag. If you notice frame rate drops during specific activities, open the sniffer and look for events with unusually high occurrence counts -- these are often the source of performance issues.

{: .important }
The performance monitor is primarily a debugging tool. Running it continuously adds its own small overhead from tracking and rendering the data. Open it when you need to diagnose a problem, then close it when you are done.

{: .note }
Per-addon memory tracking can help you decide which addons to keep or replace. If a single addon is consuming significantly more memory than others, it may be worth investigating whether a lighter alternative exists or whether it has a memory leak.
